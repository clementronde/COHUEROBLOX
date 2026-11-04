--!strict
-- Companions (docs/dossier/40-compagnons.md). One companion per run player, simulated as data
-- (no server Instances) at Companions.SimHz: follows its owner, attacks the nearest enemy, casts
-- its techniques, charges and fires its ultimate. Clients draw it from CompanionSnapshot.
--
-- Cross-domain calls go through Registry.find inside functions (other services may be missing):
-- RunManager, EnemyService, StatsService, ProgressionService, DataService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Companions = require(Config:WaitForChild("Companions"))
local Heightmap = require(Shared:WaitForChild("Heightmap"))
local Net = require(Shared:WaitForChild("Net"))
local Registry = require(Shared:WaitForChild("Registry"))
local Types = require(Shared:WaitForChild("Types"))
local Bus = require(script.Parent.Parent:WaitForChild("Bus"))

type LineDef = Companions.LineDef
type StageDef = Companions.StageDef
type TechDef = Companions.TechDef
type StatusDef = Companions.StatusDef

local DT = 1 / Companions.SimHz
local NET = Companions.Net
local FOLLOW = Companions.Follow
local ULT = Companions.Ultimate
local at = Companions.at
local TWO_PI = math.pi * 2
local MAX_I16 = 32767

type OwnedTech = { id: string, level: number, timer: number }

type Companion = {
	player: Player,
	userId: number,
	line: LineDef,
	classId: string?,
	stage: number,
	level: number,
	x: number,
	y: number,
	z: number,
	yaw: number,
	side: number, -- -1 or 1
	techs: { OwnedTech },
	treatStacks: { [string]: number },
	power: number,
	haste: number,
	reach: number,
	spirit: number,
	synergy: boolean,
	bondBonus: number,
	attackTimer: number,
	charge: number,
	stunnedUntil: number,
	downed: boolean,
	dead: boolean,
	ultUntil: number,
	ultLastUse: number,
	ultTickAcc: number,
	ultStrikes: { number }, -- Volt: enemy ids still to strike
	ultStrikeAcc: number,
	hits: { [number]: number }, -- Givre: hits per enemy id (freezeEvery)
	dmgMult: number, -- refreshed every tick
	evSeq: number,
	evKind: number,
	evX: number,
	evZ: number,
	evRadius: number,
	stateDirty: boolean,
	sentCharge: number,
	lastStateAt: number,
	pendingKills: number,
}

local CompanionService = {}

local byPlayer: { [Player]: Companion } = {}
local order: { Companion } = {} -- stable send order
local frozenUntil: { [number]: number } = {} -- enemy id -> os.clock() (Givre Fragile)
local claimed: { [number]: boolean } = {} -- enemy ids targeted this tick (coop spread)
local simTick = 0
local stateRemote: RemoteEvent
local snapshotRemote: UnreliableRemoteEvent

-- Reused query buffers (no allocation in the tick)
local queryOut: { number } = {}
local auxOut: { number } = {}
local chainHit: { [number]: boolean } = {}

-- Helpers ----------------------------------------------------------------------------------------

local function find(name: string): any?
	return Registry.find(name)
end

local function recordStat(player: Player, key: string, amount: number)
	local progression = find("ProgressionService")
	if progression and amount > 0 then
		pcall(progression.recordStat, player, key, amount)
	end
end

local function ownerRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function stageOf(c: Companion): StageDef
	return c.line.stages[c.stage]
end

local function isStunned(c: Companion, now: number): boolean
	return c.dead or now < c.stunnedUntil
end

local function markEvent(c: Companion, kind: number, x: number, z: number, radius: number)
	c.evSeq = (c.evSeq + 1) % 256
	c.evKind = kind
	c.evX = x
	c.evZ = z
	c.evRadius = radius
end

local function addCharge(c: Companion, amount: number)
	if amount <= 0 or c.dead then
		return
	end
	local mult = (1 + c.spirit) * (if c.synergy then 1 + Companions.SynergyBonus else 1)
	c.charge = math.min(ULT.Max, c.charge + amount * mult)
end

local function phaseAllows(): boolean
	local runManager = find("RunManager")
	if not runManager then
		return true -- standalone test without the run domain
	end
	local ok, phase = pcall(runManager.getPhase)
	return ok and ULT.AllowedPhases[phase] == true
end

local function ownerActive(player: Player): boolean
	local runManager = find("RunManager")
	if not runManager then
		return true
	end
	local ok, active = pcall(runManager.isActive, player)
	return ok and active == true
end

local function ownerMaxHp(player: Player): number
	local stats = find("StatsService")
	if stats then
		local ok, block = pcall(stats.get, player)
		if ok and type(block) == "table" and type(block.MaxHp) == "number" then
			return block.MaxHp
		end
	end
	return 100
end

local function refreshDamageMult(c: Companion)
	local ownerDamage = 0
	local stats = find("StatsService")
	if stats then
		local ok, block = pcall(stats.get, c.player)
		if ok and type(block) == "table" and type(block.Damage) == "number" then
			ownerDamage = block.Damage
		end
	end
	c.dmgMult = (1 + Companions.OwnerDamageShare * ownerDamage)
		* (1 + c.power)
		* (1 + c.bondBonus)
		* (if c.synergy then 1 + Companions.SynergyBonus else 1)
end

-- Combat -----------------------------------------------------------------------------------------

local function applyStatuses(c: Companion, enemies: any, id: number, statuses: { StatusDef }?, i: number, fromX: number, fromZ: number, skipFreeze: boolean)
	if not statuses then
		return
	end
	for _, s in statuses do
		if s.kind == "Freeze" and skipFreeze then
			continue
		end
		local chance = if s.chance ~= nil then at(s.chance, i) else 1
		if chance < 1 and math.random() > chance then
			continue
		end
		local params: { [string]: any } = { source = c.player }
		if s.dps ~= nil then
			params.dps = at(s.dps, i)
		end
		if s.duration ~= nil then
			params.duration = at(s.duration, i)
		end
		if s.mult ~= nil then
			params.mult = at(s.mult, i)
		end
		if s.distance ~= nil then
			params.distance = at(s.distance, i)
			params.fromX = fromX
			params.fromZ = fromZ
		end
		pcall(enemies.applyStatus, id, s.kind, params)
		if s.kind == "Freeze" and params.duration then
			frozenUntil[id] = os.clock() + params.duration
		end
	end
end

-- One hit on one enemy. Returns true if it died.
local function hit(c: Companion, enemies: any, id: number, baseDamage: number, statuses: { StatusDef }?, i: number, fromX: number, fromZ: number, skipFreeze: boolean): boolean
	local amount = baseDamage * c.dmgMult
	local frozen = frozenUntil[id]
	if frozen and frozen > os.clock() then
		amount *= 1 + Companions.FragileBonus
	end
	applyStatuses(c, enemies, id, statuses, i, fromX, fromZ, skipFreeze)
	if amount <= 0 then
		return false
	end
	local ok, died = pcall(enemies.damage, id, amount, c.player)
	if ok and died then
		frozenUntil[id] = nil
		c.hits[id] = nil
		-- Bus.EnemyKilled credits the owner (OwnerKill); top it up to CompanionKill.
		addCharge(c, ULT.CompanionKill - ULT.OwnerKill)
		c.pendingKills += 1
		return true
	end
	return false
end

-- Nearest live enemy within radius of (x, z); prefers one no other companion claimed this tick.
local function nearestEnemy(enemies: any, x: number, z: number, radius: number, preferUnclaimed: boolean): (number?, number, number)
	local n = enemies.queryRadius(x, z, radius, queryOut)
	local best, bestFree = nil, nil
	local bestD2, bestFreeD2 = math.huge, math.huge
	local bx, bz, fx, fz = 0, 0, 0, 0
	for k = 1, n do
		local id = queryOut[k]
		local ex, ez = enemies.getPosition(id)
		if ex and ez then
			local dx, dz = ex - x, ez - z
			local d2 = dx * dx + dz * dz
			if d2 < bestD2 then
				best, bestD2, bx, bz = id, d2, ex, ez
			end
			if preferUnclaimed and not claimed[id] and d2 < bestFreeD2 then
				bestFree, bestFreeD2, fx, fz = id, d2, ex, ez
			end
		end
	end
	if bestFree then
		return bestFree, fx, fz
	end
	return best, bx, bz
end

-- Hits every enemy within radius of (x, z). Returns the number hit.
local function hitArea(c: Companion, enemies: any, x: number, z: number, radius: number, damage: number, statuses: { StatusDef }?, i: number, maxTargets: number?): number
	local n = enemies.queryRadius(x, z, radius, auxOut)
	if maxTargets then
		n = math.min(n, maxTargets)
	end
	for k = 1, n do
		hit(c, enemies, auxOut[k], damage, statuses, i, x, z, false)
	end
	return n
end

-- Chain: first target, then hops to the nearest not-yet-hit enemy within `jump`.
local function hitChain(c: Companion, enemies: any, firstId: number, x: number, z: number, damage: number, hops: number, jump: number, falloff: number, statuses: { StatusDef }?, i: number)
	table.clear(chainHit)
	local id: number? = firstId
	local cx, cz = x, z
	local dmg = damage
	for _ = 1, hops + 1 do
		if not id then
			break
		end
		chainHit[id] = true
		hit(c, enemies, id, dmg, statuses, i, cx, cz, false)
		dmg *= falloff
		local n = enemies.queryRadius(cx, cz, jump, auxOut)
		local nextId, bestD2 = nil, math.huge
		local nx, nz = cx, cz
		for k = 1, n do
			local other = auxOut[k]
			if not chainHit[other] then
				local ex, ez = enemies.getPosition(other)
				if ex and ez then
					local d2 = (ex - cx) ^ 2 + (ez - cz) ^ 2
					if d2 < bestD2 then
						nextId, bestD2, nx, nz = other, d2, ex, ez
					end
				end
			end
		end
		id, cx, cz = nextId, nx, nz
	end
end

local function basicAttack(c: Companion, enemies: any, cx: number, cz: number): boolean
	local stage = stageOf(c)
	local range = stage.range * (1 + c.reach)
	local id, tx, tz = nearestEnemy(enemies, cx, cz, range, true)
	if not id then
		return false
	end
	claimed[id] = true
	local i = c.stage
	if stage.chain then
		hitChain(c, enemies, id, tx, tz, stage.damage, stage.chain, Companions.VoltChain.Jump * (1 + c.reach), Companions.VoltChain.Falloff, stage.status, i)
	elseif stage.splash then
		hitArea(c, enemies, tx, tz, stage.splash * (1 + c.reach), stage.damage, stage.status, i, nil)
	else
		local skipFreeze = false
		if stage.freezeEvery then
			local count = (c.hits[id] or 0) + 1
			c.hits[id] = count
			skipFreeze = count % stage.freezeEvery ~= 0
		end
		hit(c, enemies, id, stage.damage, stage.status, i, cx, cz, skipFreeze)
	end
	c.yaw = math.atan2(-(tx - cx), -(tz - cz))
	markEvent(c, NET.EvBasic, tx, tz, if stage.splash then stage.splash * (1 + c.reach) else 0)
	return true
end

-- Returns true if the technique fired (its cooldown restarts only then).
local function castTech(c: Companion, enemies: any, def: TechDef, level: number, slot: number, cx: number, cz: number, ox: number, oz: number): boolean
	local reachMult = 1 + c.reach
	local radius = at(def.radius, level) * reachMult
	local damage = at(def.damage, level)
	local evKind = NET.EvTech1 + slot - 1
	if def.shape == "Target" then
		local id, tx, tz = nearestEnemy(enemies, cx, cz, stageOf(c).range * reachMult, false)
		if not id then
			return false
		end
		if radius > 0 then
			hitArea(c, enemies, tx, tz, radius, damage, def.status, level, nil)
		else
			hit(c, enemies, id, damage, def.status, level, cx, cz, false)
		end
		markEvent(c, evKind, tx, tz, radius)
		return true
	elseif def.shape == "Nova" then
		if enemies.queryRadius(cx, cz, radius, auxOut) == 0 then
			return false
		end
		hitArea(c, enemies, cx, cz, radius, damage, def.status, level, nil)
		markEvent(c, evKind, cx, cz, radius)
		return true
	elseif def.shape == "Aura" then
		if hitArea(c, enemies, ox, oz, radius, damage, def.status, level, nil) > 0 then
			markEvent(c, evKind, ox, oz, radius)
		end
		return true
	elseif def.shape == "Chain" then
		local id, tx, tz = nearestEnemy(enemies, cx, cz, stageOf(c).range * reachMult, false)
		if not id then
			return false
		end
		hitChain(c, enemies, id, tx, tz, damage, at(def.targets, level) - 1, (def.jump or 10) * reachMult, 1, def.status, level)
		markEvent(c, evKind, tx, tz, 0)
		return true
	elseif def.shape == "Heal" then
		local runManager = find("RunManager")
		if not runManager then
			return true
		end
		local pct = at(def.healPct, level)
		local r2 = radius * radius
		local okPlayers, runPlayers = pcall(runManager.getRunPlayers)
		if okPlayers and type(runPlayers) == "table" then
			for _, mate in runPlayers do
				local root = ownerRoot(mate)
				if root and ownerActive(mate) then
					local p = root.Position
					if (p.X - ox) ^ 2 + (p.Z - oz) ^ 2 <= r2 then
						pcall(runManager.healPlayer, mate, ownerMaxHp(mate) * pct)
					end
				end
			end
		end
		markEvent(c, NET.EvHeal, ox, oz, radius)
		return true
	end
	return false
end

-- Ultimate ---------------------------------------------------------------------------------------

local function fireUltimate(c: Companion, ox: number, oz: number)
	local enemies = find("EnemyService")
	local ult = c.line.ultimate
	local now = os.clock()
	c.charge = 0
	c.ultLastUse = now
	c.ultUntil = now + ult.duration
	c.ultTickAcc = 0
	c.stateDirty = true
	markEvent(c, NET.EvUltimate, ox, oz, ult.radius)
	recordStat(c.player, Companions.QuestKeys.Ultimates, 1)

	local id = c.line.id
	if id == "Braise" then
		return -- timed: ticks in updateUltimate
	elseif id == "Volt" then
		table.clear(c.ultStrikes)
		c.ultStrikeAcc = 0
		if enemies then
			local n = math.min(enemies.queryRadius(ox, oz, ult.radius, auxOut), ult.maxTargets or 30)
			for k = 1, n do
				c.ultStrikes[k] = auxOut[k]
			end
		end
		return
	elseif id == "Maree" then
		local runManager = find("RunManager")
		if runManager and ult.healPct then
			local ok, runPlayers = pcall(runManager.getRunPlayers)
			if ok and type(runPlayers) == "table" then
				for _, mate in runPlayers do
					if ownerActive(mate) then
						pcall(runManager.healPlayer, mate, ownerMaxHp(mate) * ult.healPct)
					end
				end
			end
		end
	end
	if enemies then
		-- Ronce, Maree, Givre, Echo: one instant area. (Echo boss reveal: contract request.)
		hitArea(c, enemies, ox, oz, ult.radius, ult.damage, ult.status, 1, nil)
	end
end

local function updateUltimate(c: Companion, enemies: any, now: number, ox: number, oz: number)
	if now >= c.ultUntil then
		return
	end
	local ult = c.line.ultimate
	if c.line.id == "Braise" and ult.tickRate then
		c.ultTickAcc += DT * ult.tickRate
		while c.ultTickAcc >= 1 do
			c.ultTickAcc -= 1
			hitArea(c, enemies, ox, oz, ult.radius, ult.damage, ult.status, 1, nil)
		end
	elseif c.line.id == "Volt" then
		local total = ult.maxTargets or 30
		c.ultStrikeAcc += DT * total / math.max(ult.spread or 1, DT)
		while c.ultStrikeAcc >= 1 and #c.ultStrikes > 0 do
			c.ultStrikeAcc -= 1
			local target = table.remove(c.ultStrikes) :: number
			local ex, ez = enemies.getPosition(target)
			if ex and ez then
				hit(c, enemies, target, ult.damage, ult.status, 1, ex, ez, false)
				markEvent(c, NET.EvUltimate, ex, ez, 3)
			end
		end
	end
end

-- Movement ---------------------------------------------------------------------------------------

local function follow(c: Companion, root: BasePart)
	local p = root.Position
	local look = root.CFrame.LookVector
	local fx, fz = look.X, look.Z
	local len = math.sqrt(fx * fx + fz * fz)
	if len < 1e-3 then
		fx, fz = 0, -1
	else
		fx, fz = fx / len, fz / len
	end
	-- right vector of a flat forward (fx, fz) is (-fz, fx)
	local tx = p.X - fx * FOLLOW.Behind + (-fz) * FOLLOW.Side * c.side
	local tz = p.Z - fz * FOLLOW.Behind + fx * FOLLOW.Side * c.side
	local dx, dz = tx - c.x, tz - c.z
	local d = math.sqrt(dx * dx + dz * dz)
	if d > FOLLOW.SnapDistance then
		c.x, c.z = tx, tz
	elseif d > 0.05 then
		local stepLen = math.min(d, FOLLOW.Speed * DT)
		c.x += dx / d * stepLen
		c.z += dz / d * stepLen
		if d > 0.5 then
			c.yaw = math.atan2(-dx, -dz)
		end
	end
	local ground = Heightmap.getY(c.x, c.z)
	-- Root sits ~3 studs above the feet; follow the owner up platforms, never below the ground.
	local targetY = math.max(ground, p.Y - 3) + (if c.line.flying then FOLLOW.FlyHeight else 0)
	local dy = targetY - c.y
	if math.abs(dy) > FOLLOW.SnapDistance then
		c.y = targetY
	else
		c.y += math.clamp(dy, -30 * DT, 30 * DT)
	end
end

-- State / snapshot -------------------------------------------------------------------------------

local function sendState(c: Companion)
	local techs = table.create(#c.techs)
	for k, t in c.techs do
		techs[k] = { id = t.id, level = t.level }
	end
	local stage = stageOf(c)
	stateRemote:FireClient(c.player, {
		line = c.line.id,
		stage = c.stage,
		level = c.level,
		name = stage.name,
		ultimateCharge = math.floor(c.charge),
		stunned = isStunned(c, os.clock()),
		techs = techs,
	})
	c.stateDirty = false
	c.sentCharge = math.floor(c.charge)
	c.lastStateAt = os.clock()
end

local function quantize(v: number): number
	return math.clamp(math.round(v * NET.PositionScale), -MAX_I16, MAX_I16)
end

local function sendSnapshot(now: number)
	local n = #order
	local perChunk = (NET.ChunkMaxBytes - NET.HeaderBytes) // NET.RecordBytes
	local chunks = math.max(1, math.ceil(n / perChunk))
	for ch = 0, chunks - 1 do
		local first = ch * perChunk + 1
		local last = math.min(n, first + perChunk - 1)
		local count = math.max(0, last - first + 1)
		local b = buffer.create(NET.HeaderBytes + count * NET.RecordBytes)
		buffer.writeu32(b, 0, simTick)
		buffer.writeu8(b, 4, count)
		local o = NET.HeaderBytes
		for k = first, last do
			local c = order[k]
			local flags = c.line.index + bit32.lshift(c.stage, NET.StageShift)
			if isStunned(c, now) then
				flags += NET.StunnedBit
			end
			if now < c.ultUntil then
				flags += NET.UltimateBit
			end
			buffer.writef64(b, o, c.userId)
			buffer.writei16(b, o + 8, quantize(c.x))
			buffer.writei16(b, o + 10, quantize(c.y))
			buffer.writei16(b, o + 12, quantize(c.z))
			buffer.writeu8(b, o + 14, math.floor((c.yaw % TWO_PI) / TWO_PI * 256) % 256)
			buffer.writeu8(b, o + 15, flags)
			buffer.writeu8(b, o + 16, c.evSeq)
			buffer.writeu8(b, o + 17, c.evKind)
			buffer.writei16(b, o + 18, quantize(c.evX))
			buffer.writei16(b, o + 20, quantize(c.evZ))
			buffer.writeu8(b, o + 22, math.clamp(math.round(c.evRadius), 0, 255))
			o += NET.RecordBytes
		end
		snapshotRemote:FireAllClients(b)
	end
end

-- Lifecycle --------------------------------------------------------------------------------------

local function flushKills(c: Companion)
	if c.pendingKills > 0 then
		recordStat(c.player, Companions.QuestKeys.Kills, c.pendingKills)
		c.pendingKills = 0
	end
end

local function removeCompanion(player: Player)
	local c = byPlayer[player]
	if not c then
		return
	end
	flushKills(c)
	byPlayer[player] = nil
	local i = table.find(order, c)
	if i then
		table.remove(order, i)
	end
end

local function clearAll()
	for player in byPlayer do
		removeCompanion(player)
	end
	table.clear(frozenUntil)
end

local function readProfile(player: Player): any?
	local data = find("DataService")
	if not data then
		return nil
	end
	local ok, profile = pcall(data.getProfile, player)
	if ok and type(profile) == "table" then
		return profile
	end
	return nil
end

local function stageForLevel(level: number): number
	local stage = 1
	for k, need in Companions.EvolveLevels do
		if level >= need then
			stage = k + 1
		end
	end
	return math.min(stage, 3)
end

local function createCompanion(player: Player)
	removeCompanion(player)

	local classId: string? = nil
	local lineId: string? = nil
	local runManager = find("RunManager")
	if runManager then
		local ok, cls, comp = pcall(runManager.getLoadout, player)
		if ok then
			classId = if type(cls) == "string" then cls else nil
			lineId = if type(comp) == "string" then comp else nil
		end
	end
	if not (lineId and Companions.Lines[lineId]) then
		local progression = find("ProgressionService")
		if progression then
			local ok, cls, comp = pcall(progression.getLoadout, player)
			if ok then
				classId = classId or (if type(cls) == "string" then cls else nil)
				lineId = if type(comp) == "string" then comp else nil
			end
		end
	end
	local line = Companions.Lines[lineId or ""] or Companions.Lines[Companions.DefaultLine]

	-- Bond (data domain): +1 % damage per 3 levels, start technique unlocks.
	local bond = 1
	local startTech = line.techs[1]
	local profile = readProfile(player)
	if profile then
		local bonds = profile.bond
		if type(bonds) == "table" and type(bonds[line.id]) == "number" then
			bond = math.clamp(math.floor(bonds[line.id]), 1, Companions.Bond.Max)
		end
		local chosen = profile.companionStartTech -- optional field (contract request)
		local wanted = if type(chosen) == "table" then chosen[line.id] else nil
		if type(wanted) == "string" then
			local idx = table.find(line.techs, wanted)
			if idx and bond >= Companions.Bond.StartTechUnlock[idx] then
				startTech = wanted
			end
		end
	end

	local level = 1
	local stats = find("StatsService")
	if stats then
		local ok, lv = pcall(stats.getLevel, player)
		if ok and type(lv) == "number" then
			level = lv
		end
	end

	local root = ownerRoot(player)
	local p = if root then root.Position else Vector3.zero
	local c: Companion = {
		player = player,
		userId = player.UserId,
		line = line,
		classId = classId,
		stage = stageForLevel(level),
		level = level,
		x = p.X,
		y = Heightmap.getY(p.X, p.Z),
		z = p.Z + FOLLOW.Behind,
		yaw = 0,
		side = if #order % 2 == 0 then 1 else -1,
		techs = { { id = startTech, level = 1, timer = 0 } },
		treatStacks = {},
		power = 0,
		haste = 0,
		reach = 0,
		spirit = 0,
		synergy = classId ~= nil and Companions.Synergy[classId] == line.id,
		bondBonus = math.min(
			math.floor(bond / Companions.Bond.StepEvery) * Companions.Bond.DamagePerStep,
			Companions.Bond.DamagePerStep * Companions.Bond.Max / Companions.Bond.StepEvery
		),
		attackTimer = 0,
		charge = 0,
		stunnedUntil = 0,
		downed = false,
		dead = false,
		ultUntil = 0,
		ultLastUse = -math.huge,
		ultTickAcc = 0,
		ultStrikes = {},
		ultStrikeAcc = 0,
		hits = {},
		dmgMult = 1,
		evSeq = 0,
		evKind = NET.EvNone,
		evX = 0,
		evZ = 0,
		evRadius = 0,
		stateDirty = true,
		sentCharge = 0,
		lastStateAt = 0,
		pendingKills = 0,
	}
	byPlayer[player] = c
	table.insert(order, c)
	sendState(c)
end

local function evolveTo(c: Companion, level: number)
	c.level = level
	local target = stageForLevel(level)
	while c.stage < target do
		c.stage += 1
		c.stateDirty = true
		Bus.CompanionEvolved:fire(c.player, c.stage)
		recordStat(c.player, Companions.QuestKeys.Evolved, 1)
		if c.stage == 3 then
			recordStat(c.player, Companions.QuestKeys.Stage3, 1)
		end
	end
end

-- Tick -------------------------------------------------------------------------------------------

local function updateCompanion(c: Companion, enemies: any?, now: number)
	local root = ownerRoot(c.player)
	if not root then
		return
	end
	follow(c, root)
	local op = root.Position
	local ox, oz = op.X, op.Z
	refreshDamageMult(c)

	local stunned = isStunned(c, now)
	if not stunned and enemies then
		addCharge(c, ULT.PassivePerSecond * DT)
		updateUltimate(c, enemies, now, ox, oz)

		-- Downed owner: guard them (attack around the owner only).
		local cx, cz = c.x, c.z
		if c.downed then
			cx, cz = ox, oz
		end
		local speed = 1 + c.haste
		c.attackTimer -= DT * speed
		if c.attackTimer <= 0 then
			if basicAttack(c, enemies, cx, cz) then
				c.attackTimer = stageOf(c).interval
			else
				c.attackTimer = 0
			end
		end
		for slot, t in c.techs do
			t.timer -= DT * speed
			if t.timer <= 0 then
				local def = Companions.Techs[t.id]
				local lineSlot = table.find(c.line.techs, t.id) or slot
				if def and castTech(c, enemies, def, t.level, lineSlot, cx, cz, ox, oz) then
					t.timer = at(def.cooldown, t.level)
				else
					t.timer = 0
				end
			end
		end
	end

	-- CompanionState: immediately on structural change, else when the charge moved (max 4/s).
	if c.stateDirty or (math.floor(c.charge) ~= c.sentCharge and now - c.lastStateAt >= 1 / Companions.StateMaxPerSecond) then
		sendState(c)
	end
end

local stunEdge: { [Player]: boolean } = {}

local function step()
	simTick += 1
	local now = os.clock()
	local enemies = find("EnemyService")
	table.clear(claimed)
	for _, c in order do
		-- Stun end is a state change the owner's HUD must see.
		local stunned = isStunned(c, now)
		if stunEdge[c.player] ~= stunned then
			stunEdge[c.player] = stunned
			c.stateDirty = true
		end
		local ok, err = pcall(updateCompanion, c, enemies, now)
		if not ok then
			warn(`[CompanionService] update failed for {c.player.Name}: {err}`)
		end
	end
	if #order > 0 then
		sendSnapshot(now)
	end
	if simTick % (Companions.SimHz * 5) == 0 then
		for _, c in order do
			flushKills(c)
		end
		for id, untilT in frozenUntil do
			if untilT < now then
				frozenUntil[id] = nil
			end
		end
	end
end

-- Remote handler ---------------------------------------------------------------------------------

local function onUltimateRequest(player: Player)
	local c = byPlayer[player]
	if not c then
		return
	end
	local now = os.clock()
	if c.charge < ULT.Max or isStunned(c, now) or now - c.ultLastUse < ULT.MinInterval then
		return
	end
	if not phaseAllows() or not ownerActive(player) then
		return
	end
	local root = ownerRoot(player)
	if not root then
		return
	end
	fireUltimate(c, root.Position.X, root.Position.Z)
	sendState(c)
end

-- Public API (ARCHITECTURE.md section 4) ---------------------------------------------------------

local function techTitle(def: TechDef): string
	return def.name.fr
end

local function weightedPick(pool: { Types.Card }, weights: { number }, count: number): { Types.Card }
	local out: { Types.Card } = {}
	for _ = 1, count do
		local total = 0
		for _, w in weights do
			total += w
		end
		if total <= 0 then
			break
		end
		local roll = math.random() * total
		for k, w in weights do
			roll -= w
			if roll <= 0 and w > 0 then
				table.insert(out, pool[k])
				weights[k] = 0
				break
			end
		end
	end
	return out
end

local function rollTreatRarity(): Types.Rarity
	local roll = math.random()
	for _, entry in Companions.Cards.TreatRarityOdds do
		roll -= entry[2]
		if roll <= 0 then
			return entry[1] :: Types.Rarity
		end
	end
	return "Common"
end

-- Up to Companions.Cards.MaxOptions companion cards for this player's next level-up.
-- CardService decides how often companion cards appear (~1 in 4, doc 7.3).
function CompanionService.getCardOptions(player: Player): { Types.Card }
	local c = byPlayer[player]
	if not c then
		return {}
	end
	local pool: { Types.Card } = {}
	local weights: { number } = {}
	local W = Companions.Cards.Weights
	if #c.techs < Companions.MaxTechs then
		for _, techId in c.line.techs do
			local owned = false
			for _, t in c.techs do
				if t.id == techId then
					owned = true
				end
			end
			local def = Companions.Techs[techId]
			if not owned and def then
				table.insert(pool, {
					kind = "CompanionTech",
					id = techId,
					rarity = Companions.Cards.TechRarity,
					level = 1,
					title = techTitle(def),
					desc = def.desc.fr,
					icon = nil,
				})
				table.insert(weights, W.CompanionTech)
			end
		end
	end
	for _, t in c.techs do
		local def = Companions.Techs[t.id]
		if def and t.level < Companions.MaxTechLevel then
			local nextLevel = t.level + 1
			table.insert(pool, {
				kind = "CompanionTechUp",
				id = t.id,
				rarity = if nextLevel == Companions.MaxTechLevel then Companions.Cards.TechMaxRarity else Companions.Cards.TechUpRarity,
				level = nextLevel,
				title = `{techTitle(def)} {nextLevel}`,
				desc = `Dégâts {at(def.damage, t.level)} → {at(def.damage, nextLevel)}`,
				icon = nil,
			})
			table.insert(weights, W.CompanionTechUp)
		end
	end
	for id, def in Companions.Treats do
		local stacks = c.treatStacks[id] or 0
		if stacks < def.maxStacks then
			local rarity = rollTreatRarity()
			table.insert(pool, {
				kind = "CompanionTreat",
				id = id,
				rarity = rarity,
				level = stacks + 1,
				title = def.name.fr,
				desc = `+{math.round(def.values[rarity] * 100)} % ({def.stat})`,
				icon = nil,
			})
			table.insert(weights, W.CompanionTreat)
		end
	end
	return weightedPick(pool, weights, Companions.Cards.MaxOptions)
end

-- Applies a picked companion card. Re-validates eligibility (kind, id, line, limits).
function CompanionService.applyCard(player: Player, card: Types.Card)
	local c = byPlayer[player]
	if not c or type(card) ~= "table" or type(card.id) ~= "string" then
		return
	end
	if card.kind == "CompanionTech" then
		local def = Companions.Techs[card.id]
		if not def or def.line ~= c.line.id or #c.techs >= Companions.MaxTechs then
			return
		end
		for _, t in c.techs do
			if t.id == card.id then
				return
			end
		end
		table.insert(c.techs, { id = card.id, level = 1, timer = 0 })
		recordStat(player, Companions.QuestKeys.TechsLearned, 1)
	elseif card.kind == "CompanionTechUp" then
		for _, t in c.techs do
			if t.id == card.id then
				if t.level >= Companions.MaxTechLevel then
					return
				end
				t.level += 1
				break
			end
		end
	elseif card.kind == "CompanionTreat" then
		local def = Companions.Treats[card.id]
		if not def then
			return
		end
		local stacks = c.treatStacks[card.id] or 0
		if stacks >= def.maxStacks then
			return
		end
		local value = def.values[card.rarity] or def.values.Common
		c.treatStacks[card.id] = stacks + 1
		if def.stat == "Power" then
			c.power += value
		elseif def.stat == "Haste" then
			c.haste += value
		elseif def.stat == "Reach" then
			c.reach += value
		elseif def.stat == "Spirit" then
			c.spirit += value
		end
		recordStat(player, Companions.QuestKeys.Treats, 1)
	else
		return
	end
	c.stateDirty = true
end

-- Adds ultimate charge (items, shrines...). Scaled by Star Honey and synergy like every gain.
function CompanionService.chargeUltimate(player: Player, amount: number)
	local c = byPlayer[player]
	if c and type(amount) == "number" and amount == amount then
		addCharge(c, math.clamp(amount, 0, ULT.Max))
	end
end

function CompanionService.getState(player: Player): { line: string, stage: number, level: number }?
	local c = byPlayer[player]
	if not c then
		return nil
	end
	return { line = c.line.id, stage = c.stage, level = c.level }
end

-- Boot -------------------------------------------------------------------------------------------

function CompanionService.init()
	stateRemote = Net.event("CompanionState")
	snapshotRemote = Net.unreliable("CompanionSnapshot")
	Net.onServerEvent("CompanionUltimate", ULT.RemotePerSecond, function(player)
		onUltimateRequest(player)
	end)

	Bus.RunStarted:connect(function(players: { Player })
		clearAll()
		if type(players) ~= "table" then
			return
		end
		for _, player in players do
			if typeof(player) == "Instance" and player:IsA("Player") and player.Parent then
				createCompanion(player)
			end
		end
	end)
	Bus.RunEnded:connect(function()
		clearAll()
	end)
	Bus.PlayerLeveledUp:connect(function(player: Player, level: number)
		local c = byPlayer[player]
		if c and type(level) == "number" then
			addCharge(c, ULT.LevelUp)
			evolveTo(c, level)
			c.stateDirty = true
		end
	end)
	Bus.EnemyKilled:connect(function(_id: number, _kind: number, _x: number, _z: number, killer: Player?, isElite: boolean)
		local c = killer and byPlayer[killer]
		if c then
			addCharge(c, ULT.OwnerKill + (if isElite then ULT.EliteKill else 0))
		end
	end)
	Bus.PlayerDamaged:connect(function(player: Player, amount: number)
		local c = byPlayer[player]
		if c and type(amount) == "number" then
			addCharge(c, amount * ULT.PerDamageTaken)
		end
	end)
	Bus.PlayerDowned:connect(function(player: Player)
		local c = byPlayer[player]
		if c then
			c.downed = true
			c.stunnedUntil = os.clock() + Companions.StunOnDowned
			c.ultUntil = 0
			c.stateDirty = true
		end
	end)
	Bus.PlayerRevived:connect(function(player: Player)
		local c = byPlayer[player]
		if c then
			c.downed = false
			c.stunnedUntil = 0
			c.stateDirty = true
		end
	end)
	Bus.PlayerDied:connect(function(player: Player)
		local c = byPlayer[player]
		if c then
			c.dead = true
			c.downed = false
			c.ultUntil = 0
			c.stateDirty = true
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		removeCompanion(player)
		stunEdge[player] = nil
	end)
end

function CompanionService.start()
	-- Standalone test: without the run domain, every player gets a default companion on spawn.
	if Companions.Debug.SpawnWithoutRun and not find("RunManager") then
		local function hook(player: Player)
			player.CharacterAdded:Connect(function()
				if not byPlayer[player] then
					createCompanion(player)
				end
			end)
			if player.Character and not byPlayer[player] then
				createCompanion(player)
			end
		end
		Players.PlayerAdded:Connect(hook)
		for _, player in Players:GetPlayers() do
			hook(player)
		end
	end

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < DT then
			return
		end
		acc = math.min(acc - DT, DT)
		step()
	end)
end

return CompanionService
