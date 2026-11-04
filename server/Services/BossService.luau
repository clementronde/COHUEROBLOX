--!strict
-- Stage bosses as server data (dossier 20 section 5).
-- The boss is an EnemyService entity (weapons hit it through queryRadius/damage); this service
-- moves it, runs its phases (100/66/33 %), telegraphed attacks and terrain weakness, and sends
-- BossState. Every attack: ground telegraph >= 0.6 s, following markers lock 0.5 s before the
-- hit (vault: "Boss Animation and Phases", "Combat Arena and Encounter Layout").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Bosses = require(Config:WaitForChild("Bosses"))
local Enemies = require(Config:WaitForChild("Enemies"))
local Run = require(Config:WaitForChild("Run"))
local Worlds = require(Config:WaitForChild("Worlds"))
local Heightmap = require(Shared:WaitForChild("Heightmap"))
local Net = require(Shared:WaitForChild("Net"))
local Registry = require(Shared:WaitForChild("Registry"))
local Bus = require(script.Parent.Parent:WaitForChild("Bus"))

local TICK = 1 / 15
local CHARGE_SPEED = 40

type Telegraph = {
	kind: "Circle" | "Ring" | "Line",
	attack: Bosses.Attack,
	x: number,
	z: number,
	radius: number,
	inner: number?,
	dirX: number?,
	dirZ: number?,
	length: number?,
	startAt: number, -- os.clock
	hitAt: number, -- os.clock
	follow: Player?,
	color: Color3,
	resolve: "Damage" | "Summon" | "Fan" | "Charge",
}

type BossRuntime = {
	bossId: string,
	def: Bosses.Boss,
	entity: number,
	stage: number,
	name: { fr: string, en: string },
	maxHp: number,
	cx: number, -- arena centre
	cz: number,
	x: number,
	z: number,
	phase: number,
	cooldownMult: number,
	readyAt: { [string]: number },
	nextAttackAt: number,
	telegraphs: { Telegraph },
	rootedUntil: number,
	nextRootAt: number,
	vulnerableUntil: number,
	weakReadyAt: number,
	standTime: { [Player]: number },
	charge: { dirX: number, dirZ: number, left: number, damage: number, hit: { [Player]: boolean } }?,
	dirty: boolean,
}

local BossService = {}

local boss: BossRuntime? = nil
local stateRemote: RemoteEvent
local sendAcc = 0

-- Helpers ------------------------------------------------------------------------------------

local function announce(kind: string, text: { fr: string, en: string }, duration: number)
	local run = Registry.find("RunManager")
	if run and run._announce then
		run._announce(kind, text, duration)
	end
end

local function activePlayers(): { { player: Player, x: number, z: number, feet: number } }
	local out = {}
	local run = Registry.find("RunManager")
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and hum then
			local active = true
			if run then
				local ok, result = pcall(run.isActive, player)
				active = ok and result == true
			end
			if active then
				local p = root.Position
				-- S-01 : hauteur des pieds retenue par RunManager (au sol après 1,5 s en l'air)
				local feet = p.Y - hum.HipHeight - root.Size.Y / 2
				if run and run.getDamageFeetY then
					local ok, y = pcall(run.getDamageFeetY, player)
					if ok and type(y) == "number" then
						feet = y
					end
				end
				table.insert(out, { player = player, x = p.X, z = p.Z, feet = feet })
			end
		end
	end
	return out
end

local function damageScale(): number
	local enemies = Registry.find("EnemyService")
	return if enemies and enemies._damageScale then enemies._damageScale() else 1
end

local function serverTime(clockTime: number): number
	return Workspace:GetServerTimeNow() + (clockTime - os.clock())
end

local function inShape(t: Telegraph, x: number, z: number, feetAboveGround: number): boolean
	if t.kind == "Circle" then
		local dx, dz = x - t.x, z - t.z
		return dx * dx + dz * dz <= t.radius * t.radius
	elseif t.kind == "Ring" then
		if feetAboveGround > Bosses.JumpClear then
			return false -- jumped over the wave
		end
		local dx, dz = x - t.x, z - t.z
		local d2 = dx * dx + dz * dz
		local inner = t.inner or 0
		return d2 <= t.radius * t.radius and d2 >= inner * inner
	else
		local dirX, dirZ, len = t.dirX or 1, t.dirZ or 0, t.length or 0
		local rx, rz = x - t.x, z - t.z
		local along = rx * dirX + rz * dirZ
		local perp = math.abs(rx * -dirZ + rz * dirX)
		return along >= 0 and along <= len and perp <= t.radius / 2
	end
end

local function telegraphPayload(t: Telegraph)
	local y = Heightmap.getY(t.x, t.z)
	return {
		kind = t.kind,
		position = Vector3.new(t.x, y, t.z),
		radius = t.radius,
		inner = t.inner,
		dir = if t.dirX then Vector3.new(t.dirX, 0, t.dirZ or 0) else nil,
		length = t.length,
		start = serverTime(t.startAt),
		at = serverTime(t.hitAt),
		color = t.color,
	}
end

local function sendState(b: BossRuntime, defeated: boolean?)
	local enemies = Registry.find("EnemyService")
	local hp = if enemies then enemies._getHp(b.entity) else nil
	local list = {}
	for _, t in b.telegraphs do
		table.insert(list, telegraphPayload(t))
	end
	local weakPoints = {}
	local layout = Heightmap.getLayout()
	if layout and b.def.weakness.kind == "Platform" then
		for _, w in layout.weakPoints do
			table.insert(weakPoints, { position = Vector3.new(w.x, w.y, w.z), ready = os.clock() >= b.weakReadyAt })
		end
	end
	local now = os.clock()
	stateRemote:FireAllClients({
		bossId = b.bossId,
		kind = b.def.kind,
		name = b.name,
		hpFrac = if defeated then 0 else math.clamp((hp or 0) / b.maxHp, 0, 1),
		phase = b.phase,
		position = Vector3.new(b.x, Heightmap.getY(b.x, b.z), b.z),
		telegraph = list[1],
		telegraphs = list,
		stunned = enemies ~= nil and enemies._isStopped(b.entity),
		rooted = b.rootedUntil > now,
		vulnerable = b.vulnerableUntil > now,
		weakPoints = weakPoints,
		defeated = defeated == true,
	})
end

local function makeVulnerable(b: BossRuntime, seconds: number)
	local enemies = Registry.find("EnemyService")
	if enemies then
		enemies._stop(b.entity, seconds)
	end
	b.vulnerableUntil = os.clock() + seconds
	b.charge = nil
	b.telegraphs = {}
	b.nextAttackAt = os.clock() + seconds + 0.5
	b.dirty = true
	announce("Weakness", b.def.weakness.label, 3)
end

-- Attacks ------------------------------------------------------------------------------------

local function startAttack(b: BossRuntime, attack: Bosses.Attack, targets: { { player: Player, x: number, z: number, feet: number } })
	local now = os.clock()
	local windup = math.max(attack.windup, Bosses.MinTelegraph)
	local target = targets[math.random(#targets)]
	local color = if attack.kind == "Summon" then Bosses.Colors.Summon else Bosses.Colors.Normal
	local function add(t: Telegraph)
		table.insert(b.telegraphs, t)
	end
	if attack.kind == "TargetCircle" then
		add({ kind = "Circle", attack = attack, x = target.x, z = target.z, radius = attack.radius or 8, startAt = now, hitAt = now + windup, follow = target.player, color = color, resolve = "Damage" })
	elseif attack.kind == "MultiCircle" then
		for k = 1, attack.count or 3 do
			local t = targets[(k - 1) % #targets + 1]
			local spread = if k <= #targets then 0 else 10
			add({
				kind = "Circle",
				attack = attack,
				x = t.x + (math.random() - 0.5) * 2 * spread,
				z = t.z + (math.random() - 0.5) * 2 * spread,
				radius = attack.radius or 5,
				startAt = now,
				hitAt = now + windup + (k - 1) * 0.15,
				color = color,
				resolve = "Damage",
			})
		end
	elseif attack.kind == "SelfCircle" then
		add({ kind = "Circle", attack = attack, x = b.x, z = b.z, radius = attack.radius or 12, startAt = now, hitAt = now + windup, color = color, resolve = "Damage" })
	elseif attack.kind == "Ring" then
		add({ kind = "Ring", attack = attack, x = b.x, z = b.z, radius = attack.radius or 30, inner = attack.inner, startAt = now, hitAt = now + windup, color = color, resolve = "Damage" })
	elseif attack.kind == "Line" or attack.kind == "Charge" then
		local dx, dz = target.x - b.x, target.z - b.z
		local d = math.max(1e-3, math.sqrt(dx * dx + dz * dz))
		add({
			kind = "Line",
			attack = attack,
			x = b.x,
			z = b.z,
			radius = attack.width or 6,
			dirX = dx / d,
			dirZ = dz / d,
			length = attack.length or 40,
			startAt = now,
			hitAt = now + windup,
			color = color,
			resolve = if attack.kind == "Charge" then "Charge" else "Damage",
		})
	elseif attack.kind == "Fan" then
		local dx, dz = target.x - b.x, target.z - b.z
		local d = math.max(1e-3, math.sqrt(dx * dx + dz * dz))
		add({ kind = "Circle", attack = attack, x = b.x, z = b.z, radius = attack.radius or 5, dirX = dx / d, dirZ = dz / d, startAt = now, hitAt = now + windup, color = color, resolve = "Fan" })
	elseif attack.kind == "Summon" then
		add({ kind = "Circle", attack = attack, x = b.x, z = b.z, radius = attack.radius or 6, startAt = now, hitAt = now + windup, color = color, resolve = "Summon" })
	end
	b.readyAt[attack.id] = now + attack.cooldown * b.cooldownMult * Bosses.PhaseCooldownMult[b.phase]
	b.nextAttackAt = now + windup + Bosses.GlobalAttackGap
	b.dirty = true
end

local function resolveTelegraph(b: BossRuntime, t: Telegraph, targets: { { player: Player, x: number, z: number, feet: number } })
	local attack = t.attack
	local run = Registry.find("RunManager")
	local enemies = Registry.find("EnemyService")
	if enemies then
		local dx, dz = t.dirX or (t.x - b.x), t.dirZ or (t.z - b.z)
		local reach = if t.kind == "Line" then (t.length or 0) * .5 else 0
		enemies._attackVisual(b.entity, "boss", t.x + dx * reach, t.z + dz * reach, dx, dz, t.radius)
	end
	if t.resolve == "Damage" then
		local dmg = (attack.damage or 10) * damageScale()
		for _, p in targets do
			local above = p.feet - Heightmap.getY(p.x, p.z)
			if inShape(t, p.x, p.z, above) and run then
				task.spawn(run.damagePlayer, p.player, dmg, "Boss:" .. attack.id)
			end
		end
	elseif t.resolve == "Fan" and enemies then
		local count = attack.count or 5
		local spread = math.rad(attack.spread or 60)
		local baseAngle = math.atan2(t.dirZ or 0, t.dirX or 1)
		local full = (attack.spread or 0) >= 360
		for k = 1, count do
			local a
			if full then
				a = baseAngle + (k - 1) / count * math.pi * 2
			else
				a = baseAngle - spread / 2 + (if count > 1 then (k - 1) / (count - 1) else 0.5) * spread
			end
			enemies._fireProjectile(b.x, b.z, math.cos(a), math.sin(a), attack.speed or 18, (attack.damage or 10) * damageScale(), 1.4, 4.5, Heightmap.getY(b.x, b.z) + 4)
		end
	elseif t.resolve == "Summon" and enemies then
		local world = Worlds[(Heightmap.getLayout() or { worldId = Run.DefaultWorld }).worldId] or Worlds[Run.DefaultWorld]
		for k = 1, attack.count or 4 do
			local a = k / (attack.count or 4) * math.pi * 2
			local x, z = b.x + math.cos(a) * 9, b.z + math.sin(a) * 9
			if attack.summonKind == 0 then
				local kind = if k % 2 == 0 then world.roster.Armored else world.roster.Jumper
				enemies.spawnAt(kind, x, z, { elite = true })
			else
				enemies.spawnAt(attack.summonKind or world.roster.Swarm, x, z)
			end
		end
	elseif t.resolve == "Charge" then
		b.charge = { dirX = t.dirX or 1, dirZ = t.dirZ or 0, left = t.length or 40, damage = (attack.damage or 20) * damageScale(), hit = {} }
	end
end

-- Tick -----------------------------------------------------------------------------------------

local function stepCharge(b: BossRuntime, targets: { { player: Player, x: number, z: number, feet: number } }, enemies: any)
	local c = b.charge
	if not c then
		return
	end
	local stepLen = math.min(c.left, CHARGE_SPEED * TICK)
	b.x += c.dirX * stepLen
	b.z += c.dirZ * stepLen
	c.left -= stepLen
	local radius = Enemies[b.def.kind].radius
	local run = Registry.find("RunManager")
	for _, p in targets do
		local dx, dz = p.x - b.x, p.z - b.z
		if not c.hit[p.player] and dx * dx + dz * dz <= (radius + 2) ^ 2 and run then
			c.hit[p.player] = true
			task.spawn(run.damagePlayer, p.player, c.damage, "Boss:Charge")
		end
	end
	-- Terrain weakness: a ruin pillar stops the charge.
	local layout = Heightmap.getLayout()
	if layout and b.def.weakness.kind == "Pillar" then
		for _, pillar in layout.pillars do
			local dx, dz = pillar.x - b.x, pillar.z - b.z
			if dx * dx + dz * dz <= (pillar.r + radius) ^ 2 then
				makeVulnerable(b, b.def.weakness.stunSeconds or 5)
				return
			end
		end
	end
	if c.left <= 0 then
		b.charge = nil
	end
	enemies._setPosition(b.entity, b.x, b.z)
end

local function stepWeakness(b: BossRuntime, targets: { { player: Player, x: number, z: number, feet: number } }, now: number)
	local w = b.def.weakness
	if b.phase < w.minPhase then
		return
	end
	if w.kind == "Height" then
		if now >= b.nextRootAt and b.rootedUntil < now then
			b.rootedUntil = now + (w.rootSeconds or 8)
			b.nextRootAt = now + (w.every or 25)
			b.dirty = true
			announce("Weakness", w.label, 3)
		end
	elseif w.kind == "Platform" and now >= b.weakReadyAt then
		local layout = Heightmap.getLayout()
		if not layout then
			return
		end
		for _, p in targets do
			local on = false
			for _, wp in layout.weakPoints do
				local dx, dz = p.x - wp.x, p.z - wp.z
				if dx * dx + dz * dz <= (w.range or 5) ^ 2 and p.feet >= wp.y - 1.5 then
					on = true
					break
				end
			end
			if on then
				b.standTime[p.player] = (b.standTime[p.player] or 0) + TICK
				if b.standTime[p.player] >= (w.standSeconds or 2) then
					table.clear(b.standTime)
					b.weakReadyAt = now + (w.cooldown or 30)
					makeVulnerable(b, w.stunSeconds or 5)
					return
				end
			else
				b.standTime[p.player] = nil
			end
		end
	end
end

local function step()
	local b = boss
	if not b then
		return
	end
	local enemies = Registry.find("EnemyService")
	if not enemies or not enemies.isAlive(b.entity) then
		return
	end
	local now = os.clock()
	local targets = activePlayers()

	-- Phase
	local hp = enemies._getHp(b.entity) or 0
	local frac = hp / b.maxHp
	local phase = if not Bosses.PhaseEnabled then 1
		elseif frac <= Bosses.PhaseAt[2] then 3
		elseif frac <= Bosses.PhaseAt[1] then 2
		else 1
	if phase > b.phase then
		b.phase = phase
		b.dirty = true
		announce("BossPhase", { en = `{b.name.en}: phase {phase}!`, fr = `{b.name.en}: phase {phase}!` }, 2.5)
		if b.def.weakness.kind == "Height" and phase == b.def.weakness.minPhase then
			b.nextRootAt = now + 3
		end
	end

	local stopped = enemies._isStopped(b.entity)
	local rooted = b.rootedUntil > now

	if b.charge and not stopped then
		stepCharge(b, targets, enemies)
	elseif not stopped and not rooted and #targets > 0 then
		-- Walk toward the nearest player, staying inside the arena.
		local best, bestD2 = targets[1], math.huge
		for _, p in targets do
			local d2 = (p.x - b.x) ^ 2 + (p.z - b.z) ^ 2
			if d2 < bestD2 then
				best, bestD2 = p, d2
			end
		end
		local stopAt = Enemies[b.def.kind].radius + 3
		if bestD2 > stopAt * stopAt then
			local d = math.sqrt(bestD2)
			b.x += (best.x - b.x) / d * b.def.moveSpeed * TICK
			b.z += (best.z - b.z) / d * b.def.moveSpeed * TICK
		end
		local ox, oz = b.x - b.cx, b.z - b.cz
		local maxR = Run.ArenaRadius - 8
		local r = math.sqrt(ox * ox + oz * oz)
		if r > maxR then
			b.x, b.z = b.cx + ox / r * maxR, b.cz + oz / r * maxR
		end
		enemies._setPosition(b.entity, b.x, b.z)
	else
		-- Knockback-immune; keep our copy in sync with the entity.
		local x, z = enemies.getPosition(b.entity)
		if x and z then
			b.x, b.z = x, z
		end
	end

	-- Telegraphs: following markers lock LockBefore seconds before the hit.
	local i = 1
	while i <= #b.telegraphs do
		local t = b.telegraphs[i]
		if t.follow and now < t.hitAt - Bosses.LockBefore then
			for _, p in targets do
				if p.player == t.follow then
					t.x, t.z = p.x, p.z
				end
			end
		end
		if now >= t.hitAt then
			table.remove(b.telegraphs, i)
			resolveTelegraph(b, t, targets)
			b.dirty = true
		else
			i += 1
		end
	end

	stepWeakness(b, targets, now)

	-- New attack
	if not stopped and not b.charge and now >= b.nextAttackAt and #b.telegraphs == 0 and #targets > 0 then
		local options: { Bosses.Attack } = {}
		for _, attack in b.def.attacks do
			if attack.minPhase <= b.phase and now >= (b.readyAt[attack.id] or 0) and (not rooted or attack.whileRooted) then
				table.insert(options, attack)
			end
		end
		if #options > 0 then
			startAttack(b, options[math.random(#options)], targets)
		end
	end
end

-- Public / run-domain API -------------------------------------------------------------------

-- Spawns the stage boss at the arena centre. hp = base x tier x (1 + 0.8 (n - 1)) [x enraged].
function BossService.spawnBoss(bossId: string, centre: Vector3, stage: number, tier: number, nPlayers: number, enraged: boolean): boolean
	local def = Bosses.List[bossId]
	local enemies = Registry.find("EnemyService")
	if not def or not enemies then
		return false
	end
	BossService.despawn()
	-- `stage` = index du monde dans la run (Run.WorldScaling) ; `tier` n'est plus utilisé (v2).
	local _ = tier
	local scaling = Run.WorldScaling[math.clamp(stage, 1, #Run.WorldScaling)]
	local hp = def.hp
		* scaling.bossHp
		* (1 + Bosses.HpPerExtraPlayer * (math.max(1, nPlayers) - 1))
		* (if enraged then Bosses.EnragedHpMult else 1)
	local entity = enemies._spawnBoss(def.kind, centre.X, centre.Z, hp)
	if not entity then
		return false
	end
	local now = os.clock()
	local name = def.name
	if enraged then
		name = { fr = def.name.fr .. Bosses.EnragedSuffix.fr, en = def.name.en .. Bosses.EnragedSuffix.en }
	end
	boss = {
		bossId = bossId,
		def = def,
		entity = entity,
		stage = stage,
		name = name,
		maxHp = hp,
		cx = centre.X,
		cz = centre.Z,
		x = centre.X,
		z = centre.Z,
		phase = 1,
		cooldownMult = if enraged then Bosses.EnragedCooldownMult else 1,
		readyAt = {},
		nextAttackAt = now + 2.5,
		telegraphs = {},
		rootedUntil = 0,
		nextRootAt = math.huge,
		vulnerableUntil = 0,
		weakReadyAt = now,
		standTime = {},
		charge = nil,
		dirty = true,
		spawnedAt = os.clock(),
	}
	announce("BossStart", name, 3)
	return true
end

function BossService.despawn()
	local b = boss
	if not b then
		return
	end
	boss = nil
	local enemies = Registry.find("EnemyService")
	if enemies then
		enemies._remove(b.entity)
	end
	stateRemote:FireAllClients({ bossId = b.bossId, hpFrac = 0, phase = b.phase, defeated = false, removed = true, telegraphs = {} })
end

-- Run-domain internal (commandes de test de RunManager) : id d'entité EnemyService du boss.
function BossService._entityId(): number?
	return if boss then boss.entity else nil
end

function BossService.isActive(): boolean
	return boss ~= nil
end

function BossService.getPosition(): Vector3?
	local b = boss
	if not b then
		return nil
	end
	return Vector3.new(b.x, Heightmap.getY(b.x, b.z), b.z)
end

-- EnemyService hook: terrain weakness multipliers.
function BossService._modifyDamage(id: number, amount: number, source: Player?): number
	local b = boss
	if not b or b.entity ~= id then
		return amount
	end
	local now = os.clock()
	if b.vulnerableUntil > now then
		return amount * b.def.weakness.damageMult
	end
	local w = b.def.weakness
	if w.kind == "Height" and b.rootedUntil > now and source then
		local character = source.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and hum then
			local p = root.Position
			local feet = p.Y - hum.HipHeight - root.Size.Y / 2
			local dx, dz = p.X - b.x, p.Z - b.z
			if feet >= Heightmap.getY(b.x, b.z) + (w.heightAbove or 5) and dx * dx + dz * dz <= (w.range or 22) ^ 2 then
				return amount * w.damageMult
			end
		end
	end
	return amount
end

function BossService._controlMult(): number
	return Bosses.ControlStunMult
end

local function onEnemyKilled(id: number, _kind: number, _x: number, _z: number)
	local b = boss
	if not b or b.entity ~= id then
		return
	end
	boss = nil
	b.telegraphs = {}
	sendState(b, true)
	-- Boss chests are spawned by LootService on Bus.BossDefeated (review finding 8: no duplicates here).
	-- Quest counter for Q_BossFast_*: boss killed within 30 s of spawning (review finding 13).
	local spawnedAt = (b :: any).spawnedAt
	if type(spawnedAt) == "number" and os.clock() - spawnedAt <= 30 then
		local prog = Registry.find("ProgressionService")
		local run = Registry.find("RunManager")
		if prog and prog.recordStat and run then
			local ok, players = pcall(run.getRunPlayers)
			if ok and type(players) == "table" then
				for _, player in players do
					pcall(prog.recordStat, player, "BossFast30", 1)
				end
			end
		end
	end
	announce("BossDefeated", { en = `{b.name.en} is defeated!`, fr = `{b.name.en} is defeated!` }, 3)
	Bus.BossDefeated:fire(b.bossId, b.stage)
end

function BossService.init()
	stateRemote = Net.event("BossState")
	Bus.EnemyKilled:connect(onEnemyKilled)
end

function BossService.start()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		sendAcc += dt
		if acc < TICK then
			return
		end
		acc = math.min(acc - TICK, TICK)
		step()
		local b = boss
		if b and (b.dirty or sendAcc >= 1 / Bosses.SendHz) then
			b.dirty = false
			sendAcc = 0
			sendState(b)
		end
	end)
end

return BossService
