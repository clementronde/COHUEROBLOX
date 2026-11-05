--!strict
-- Compagnons v2 : capture et collection (docs/dossier/40-compagnons.md, regles-v2.md §3).
-- Un compagnon est une créature battue puis capturée ; id d'espèce = Config/Enemies[kind].name.
-- Simulation en données à 10 Hz (aucune Instance serveur par compagnon), une boucle partagée.
--
-- Capture : seul le serveur crée une cage (EnemyService -> onCapturableDefeated). Le joueur reste
-- HoldSeconds dans la cage sans être touché : réussite à 100 %, aucun remote, aucun hasard.
-- La collection est écrite par ProgressionService.grantCapture (A12), avec une clé d'idempotence.
--
-- APIs (dossier 40 §6) :
--   pour A03 : isSpecies(kind) · onCapturableDefeated(kind, x, z, killer) -> cageId?
--   pour A12 : slotsFor(classId) · isSpecies(id) · speciesName(id)
--   contrat  : getCardOptions · applyCard · chargeUltimate (sans effet) · getState · ensure · getCages
-- Appels sortants (tous optionnels, Registry.find dans les fonctions) : RunManager, EnemyService,
-- StatsService, CardService, MovementGuard, ProgressionService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Companions = require(Config:WaitForChild("Companions"))
local Enemies = require(Config:WaitForChild("Enemies"))
local Weapons = require(Config:WaitForChild("Weapons"))
local Classes = require(Config:WaitForChild("Classes"))
local Heightmap = require(Shared:WaitForChild("Heightmap"))
local Net = require(Shared:WaitForChild("Net"))
local Registry = require(Shared:WaitForChild("Registry"))
local Types = require(Shared:WaitForChild("Types"))
local Bus = require(script.Parent.Parent:WaitForChild("Bus"))

type AttackDef = Companions.AttackDef
type TechDef = Companions.TechDef
type StatusDef = Companions.StatusDef
type LocalizedText = Types.LocalizedText

local DT = 1 / Companions.SimHz
local CAP = Companions.Capture
local FOLLOW = Companions.Follow
local NET = Companions.Net
local IS_STUDIO = RunService:IsStudio()
local TWO_PI = math.pi * 2
local MAX_I16 = 32767
local NO_NAME: LocalizedText = { fr = "No companion", en = "No companion" }

type Owner = {
	player: Player,
	companions: { Companion },
	classId: string,
	level: number,
	power: number,
	haste: number,
	reach: number,
	tamerBonus: number,
	treatStacks: { [string]: number },
	techs: { [string]: number }, -- id de technique -> niveau (1..TechMaxLevel)
	dmgMult: number,
	stunnedUntil: number,
	dead: boolean, -- mort définitive : sonné jusqu'à la fin de la run
	pendingKills: number,
	stateDirty: boolean,
	lastStateAt: number,
}

export type Companion = {
	owner: Owner,
	userId: number,
	slot: number,
	kind: number,
	species: string,
	base: AttackDef, -- attaque de l'espèce, sans technique
	attack: AttackDef, -- attaque effective (base + techniques : zone, statuts, cibles en plus)
	power: number, -- bonus des techniques de ce compagnon
	haste: number,
	reach: number,
	pulse: { interval: number, radius: number, damage: number }?,
	pulseTimer: number,
	flying: boolean,
	x: number,
	y: number,
	z: number,
	yaw: number,
	timer: number,
	evSeq: number,
	evKind: number,
	evX: number,
	evZ: number,
	evRadius: number,
}

type Cage = {
	id: number,
	kind: number,
	species: string,
	name: LocalizedText,
	x: number,
	y: number,
	z: number,
	expiresAt: number, -- en temps de simulation (s'arrête pendant un gel)
	done: { [Player]: boolean },
}

type Attempt = {
	cageId: number?,
	held: number,
	strikes: number,
	lockUntil: number,
	sentState: string,
	sentProgress: number,
	sentAt: number, -- os.clock du dernier envoi de CaptureState
}

local CompanionService = {}

local owners: { [Player]: Owner } = {}
local order: { Companion } = {}
local claimed: { [number]: boolean } = {}
local queryOut: { number } = {}
local hitArea: { number } = {}
local extraArea: { number } = {}

local cages: { Cage } = {}
local attempts: { [Player]: Attempt } = {}
local capturesThisRun: { [Player]: number } = {}
local runCaptured: { [Player]: { string } } = {} -- espèces capturées pendant la run (RunSummary.captured)
local hitFlag: { [Player]: boolean } = {}
local memory: { [Player]: { order: { string }, owned: { [string]: number } } } = {} -- repli sans A12
local speciesKind: { [string]: number } = {}

local cageSerial = 0
local runSerial = 0
local simTime = 0
local simTick = 0
local externalCages = false -- vrai dès qu'EnemyService appelle onCapturableDefeated (fin du mode debug)
local debugKills = 0
local warned: { [string]: boolean } = {}

local stateRemote: RemoteEvent
local snapshotRemote: UnreliableRemoteEvent
local captureRemote: RemoteEvent
local cageRemote: RemoteEvent

-- Outils ---------------------------------------------------------------------------------------

local function find(name: string): any?
	return Registry.find(name)
end

local function warnOnce(key: string, text: string)
	if not warned[key] then
		warned[key] = true
		warn("[CompanionService] " .. text)
	end
end

-- Appel protégé d'une fonction optionnelle d'un autre service.
local function try(service: any?, fnName: string, ...: any): (boolean, any, any, any)
	if not service then
		return false, nil, nil, nil
	end
	local fn = service[fnName]
	if type(fn) ~= "function" then
		return false, nil, nil, nil
	end
	local ok, a, b, c = pcall(fn, ...)
	if not ok then
		warnOnce(fnName, `{fnName} failed: {a}`)
		return false, nil, nil, nil
	end
	return true, a, b, c
end

local function recordStat(player: Player, key: string, amount: number)
	if amount > 0 then
		try(find("ProgressionService"), "recordStat", player, key, amount)
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

local function currentPhase(): string?
	local ok, phase = try(find("RunManager"), "getPhase")
	return if ok and type(phase) == "string" then phase else nil
end

local function phaseAllows(): boolean
	if not find("RunManager") then
		return true -- test sans le domaine run
	end
	local phase = currentPhase()
	return phase ~= nil and CAP.Phases[phase] == true
end

local function isFrozen(): boolean
	local ok, frozen = try(find("RunManager"), "isFrozen")
	return ok and frozen == true
end

local function isActive(player: Player): boolean
	local run = find("RunManager")
	if not run then
		return true
	end
	local ok, active = try(run, "isActive", player)
	return ok and active == true
end

local function isDowned(player: Player): boolean
	local ok, downed = try(find("RunManager"), "isDowned", player)
	return ok and downed == true
end

local function runPlayers(): { Player }
	local ok, list = try(find("RunManager"), "getRunPlayers")
	if ok and type(list) == "table" then
		return list
	end
	return Players:GetPlayers()
end

-- Espèces ----------------------------------------------------------------------------------------

local function capturableDef(kind: number): Enemies.Def?
	local def = Enemies[kind]
	if def and def.family ~= "Boss" and def.isBoss ~= true then
		return def
	end
	return nil
end

local function kindOf(id: any): number?
	if type(id) == "number" then
		return if capturableDef(id) then id else nil
	elseif type(id) == "string" then
		return speciesKind[id]
	end
	return nil
end

local function attackFor(def: Enemies.Def): AttackDef
	local override = Companions.Species[def.name]
	if override and override.attack then
		return override.attack
	end
	return Companions.Families[def.family] or Companions.Families[Companions.DefaultFamily]
end

-- Techniques (A05-03) -------------------------------------------------------------------------------

local techIndex: { [string]: { species: string, def: TechDef } } = {}

local function techsOf(species: string): { TechDef }
	local override = Companions.Species[species]
	return if override and override.techs then override.techs else {}
end

local function techValue(def: TechDef, level: number): number
	local values = def.values
	return values[math.clamp(level, 1, #values)] or 0
end

-- Paramètre principal d'un statut ajouté par une technique (Status), selon le genre de statut.
local function statusWithValue(base: StatusDef, value: number): StatusDef
	local s: StatusDef = table.clone(base)
	if s.kind == "Burn" or s.kind == "Poison" then
		s.dps = value
	elseif s.kind == "Slow" then
		s.mult = value
	elseif s.kind == "Knockback" then
		s.distance = value
	else
		s.duration = value
	end
	return s
end

-- Texte {v} d'une technique : pourcentage pour Power / Haste / Reach et le ralenti, nombre sinon.
local function formatTechValue(def: TechDef, value: number): string
	local pct = def.stat == "Power"
		or def.stat == "Haste"
		or def.stat == "Reach"
		or (def.stat == "Status" and def.status ~= nil and def.status.kind == "Slow")
	local n = if pct then value * 100 else value
	if math.abs(n - math.round(n)) < 1e-6 then
		return tostring(math.round(n))
	end
	return (string.gsub(string.format("%.2f", n), "0+$", ""))
end

-- Recalcule l'attaque effective d'un compagnon à partir de sa base et des techniques du propriétaire.
local function rebuildAttack(c: Companion)
	local a: AttackDef = table.clone(c.base)
	local statuses: { StatusDef } = if a.status then table.clone(a.status) else {}
	c.power, c.haste, c.reach, c.pulse = 0, 0, 0, nil
	for _, def in techsOf(c.species) do
		local level = c.owner.techs[def.id]
		if not level then
			continue
		end
		local v = techValue(def, level)
		if def.stat == "Power" then
			c.power += v
		elseif def.stat == "Haste" then
			c.haste += v
		elseif def.stat == "Reach" then
			c.reach += v
		elseif def.stat == "Splash" then
			a.splash = (a.splash or 0) + v
		elseif def.stat == "Multishot" then
			a.extraTargets = (a.extraTargets or 0) + math.floor(v)
		elseif def.stat == "Status" and def.status then
			-- Remplace un statut du même genre (pas de double recul), sinon l'ajoute.
			local s = statusWithValue(def.status, v)
			local replaced = false
			for k, old in statuses do
				if old.kind == s.kind then
					statuses[k] = s
					replaced = true
				end
			end
			if not replaced then
				table.insert(statuses, s)
			end
		elseif def.stat == "Pulse" and def.pulse then
			c.pulse = { interval = def.pulse.interval, radius = def.pulse.radius, damage = v }
		end
	end
	a.status = if #statuses > 0 then statuses else nil
	c.attack = a
end

-- Classe et Tamer ---------------------------------------------------------------------------------

local function passiveOf(classId: string?): { [string]: any }?
	if type(classId) ~= "string" then
		return nil
	end
	local def = (Classes :: any)[classId]
	local id = if type(def) == "table" and type(def.id) == "string" then def.id else classId
	return Weapons.Passives[id]
end

local function classOf(player: Player): string
	local ok, classId = try(find("RunManager"), "getLoadout", player)
	if ok and type(classId) == "string" then
		return classId
	end
	ok, classId = try(find("ProgressionService"), "getLoadout", player)
	return if ok and type(classId) == "string" then classId else ""
end

local function holdSecondsFor(player: Player): number
	local passive = passiveOf(classOf(player))
	local speed = if passive and type(passive.captureSpeed) == "number" and passive.captureSpeed > 0 then passive.captureSpeed else 1
	return CAP.HoldSeconds / speed
end

-- Owner state -------------------------------------------------------------------------------------

local function refreshDamageMult(o: Owner)
	local ownerDamage = 0
	local ok, block = try(find("StatsService"), "get", o.player)
	if ok and type(block) == "table" and type(block.Damage) == "number" and block.Damage == block.Damage then
		ownerDamage = block.Damage
	end
	o.dmgMult = (1 + Companions.OwnerDamageShare * ownerDamage)
		* (1 + Companions.LevelScaling * math.max(0, o.level - 1))
		* (1 + o.power)
		* (1 + o.tamerBonus)
end

local function isStunned(o: Owner, now: number): boolean
	return o.dead or now < o.stunnedUntil
end

local function sendState(o: Owner)
	local list = table.create(#o.companions)
	local techs = {}
	for k, c in o.companions do
		local def = Enemies[c.kind]
		list[k] = { species = c.species, name = if def then def.label else NO_NAME, slot = c.slot, attack = c.base.name.en }
		for _, tech in techsOf(c.species) do
			local level = o.techs[tech.id]
			if level then
				table.insert(techs, { id = tech.id, species = c.species, name = tech.name, level = level, maxLevel = Companions.TechMaxLevel })
			end
		end
	end
	local first = o.companions[1]
	local firstDef = first and Enemies[first.kind]
	stateRemote:FireClient(o.player, {
		line = if first then first.species else "",
		stage = 1,
		level = o.level,
		name = if firstDef then firstDef.label else NO_NAME,
		ultimateCharge = 0,
		stunned = isStunned(o, os.clock()),
		techs = techs,
		companions = list,
		none = first == nil,
	})
	o.stateDirty = false
	o.lastStateAt = os.clock()
end

-- Combat ------------------------------------------------------------------------------------------

local function markEvent(c: Companion, kind: number, x: number, z: number, radius: number)
	c.evSeq = (c.evSeq + 1) % 256
	c.evKind = kind
	c.evX = x
	c.evZ = z
	c.evRadius = radius
end

local function applyStatuses(c: Companion, enemies: any, id: number)
	local statuses = c.attack.status
	if not statuses then
		return
	end
	local player = c.owner.player
	for _, s in statuses do
		local params: { [string]: any } = { source = player }
		if s.kind == "Knockback" then
			params.fromX, params.fromZ, params.distance = c.x, c.z, s.distance or 4
		elseif s.kind == "Slow" then
			params.mult, params.duration = s.mult or 0.7, s.duration or 1.5
		elseif s.kind == "Burn" or s.kind == "Poison" then
			params.dps, params.duration = s.dps or 2, s.duration or 3
		else
			params.duration = s.duration or 0.5
		end
		pcall(enemies.applyStatus, id, s.kind, params)
	end
end

local function hit(c: Companion, enemies: any, id: number, amount: number)
	applyStatuses(c, enemies, id)
	local ok, died = pcall(enemies.damage, id, amount, c.owner.player)
	if ok and died then
		c.owner.pendingKills += 1
	end
end

-- Ennemi vivant le plus proche dans le rayon ; préfère une cible qu'aucun autre compagnon n'a prise.
local function nearestEnemy(enemies: any, x: number, z: number, radius: number): (number?, number, number)
	local okQ, n = pcall(enemies.queryRadius, x, z, radius, queryOut)
	if not okQ or type(n) ~= "number" then
		return nil, 0, 0
	end
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
			if not claimed[id] and d2 < bestFreeD2 then
				bestFree, bestFreeD2, fx, fz = id, d2, ex, ez
			end
		end
	end
	if bestFree then
		return bestFree, fx, fz
	end
	return best, bx, bz
end

local function attackTarget(c: Companion, enemies: any, id: number, tx: number, tz: number)
	local a = c.attack
	local o = c.owner
	local amount = a.damage * o.dmgMult * (1 + c.power)
	local reach = 1 + o.reach + c.reach
	local splash = if a.splash then a.splash * reach else 0
	if splash > 0 then
		local okQ, n = pcall(enemies.queryRadius, tx, tz, splash, hitArea)
		if okQ and type(n) == "number" and n > 0 then
			for k = 1, n do
				hit(c, enemies, hitArea[k], amount)
			end
		else
			hit(c, enemies, id, amount)
		end
	else
		hit(c, enemies, id, amount)
	end
	-- Cibles en plus (Multishot, Book Toss) : d'autres ennemis à portée, à TechShare des dégâts.
	local extra = a.extraTargets or 0
	if extra > 0 then
		local okQ, n = pcall(enemies.queryRadius, c.x, c.z, a.range * reach, extraArea)
		if okQ and type(n) == "number" then
			local share = amount * Companions.TechShare
			for k = 1, n do
				if extra <= 0 then
					break
				end
				local other = extraArea[k]
				if other ~= id then
					hit(c, enemies, other, share)
					extra -= 1
				end
			end
		end
	end
	markEvent(c, a.evKind, tx, tz, splash)
end

-- Onde d'une technique Pulse autour du compagnon (Spirit Circle, Stink Cloud).
local function firePulse(c: Companion, enemies: any)
	local pulse = c.pulse
	if not pulse then
		return
	end
	local o = c.owner
	local radius = pulse.radius * (1 + o.reach + c.reach)
	local amount = pulse.damage * o.dmgMult * (1 + c.power)
	local okQ, n = pcall(enemies.queryRadius, c.x, c.z, radius, extraArea)
	if okQ and type(n) == "number" then
		for k = 1, n do
			local ok, died = pcall(enemies.damage, extraArea[k], amount, o.player)
			if ok and died then
				o.pendingKills += 1
			end
		end
	end
	markEvent(c, NET.EvPulse, c.x, c.z, radius)
end

-- Suivi -------------------------------------------------------------------------------------------

-- Point de suivi derrière le propriétaire (à gauche pour l'emplacement 1, à droite pour le 2).
local function followPoint(c: Companion, root: BasePart): (number, number)
	local p = root.Position
	local look = root.CFrame.LookVector
	local fx, fz = look.X, look.Z
	local len = math.sqrt(fx * fx + fz * fz)
	if len < 1e-3 then
		fx, fz = 0, -1
	else
		fx, fz = fx / len, fz / len
	end
	local side = if c.slot == 1 then -1 else 1
	-- vecteur droit d'un avant plat (fx, fz) : (-fz, fx)
	return p.X - fx * FOLLOW.Behind + (-fz) * FOLLOW.Side * side, p.Z - fz * FOLLOW.Behind + fx * FOLLOW.Side * side
end

local function moveToward(c: Companion, gx: number, gz: number, faceMove: boolean)
	local dx, dz = gx - c.x, gz - c.z
	local d = math.sqrt(dx * dx + dz * dz)
	if d > 0.05 then
		local stepLen = math.min(d, FOLLOW.Speed * DT)
		c.x += dx / d * stepLen
		c.z += dz / d * stepLen
		if faceMove and d > 0.5 then
			c.yaw = math.atan2(-dx, -dz)
		end
	end
end

local function updateHeight(c: Companion, root: BasePart)
	local ground = Heightmap.getY(c.x, c.z)
	-- La racine est ~3 studs au-dessus des pieds : suit le joueur sur les plateformes, jamais sous le sol.
	local targetY = math.max(ground, root.Position.Y - 3) + (if c.flying then FOLLOW.FlyHeight else 0)
	local dy = targetY - c.y
	if math.abs(dy) > FOLLOW.SnapDistance then
		c.y = targetY
	else
		c.y += math.clamp(dy, -30 * DT, 30 * DT)
	end
end

local function updateCompanion(c: Companion, enemies: any?, now: number, frozen: boolean)
	local o = c.owner
	local root = ownerRoot(o.player)
	if not root then
		return
	end
	local fx, fz = followPoint(c, root)
	local ddx, ddz = fx - c.x, fz - c.z
	if ddx * ddx + ddz * ddz > FOLLOW.SnapDistance * FOLLOW.SnapDistance then
		c.x, c.z = fx, fz
		c.y = math.max(Heightmap.getY(fx, fz), root.Position.Y - 3)
	end
	if frozen then
		return
	end
	local stunned = isStunned(o, now)
	local speed = 1 + o.haste + c.haste
	c.timer -= DT * speed
	local a = c.attack
	local range = a.range * (1 + o.reach + c.reach)
	if c.pulse and enemies and not stunned then
		c.pulseTimer -= DT * speed
		if c.pulseTimer <= 0 then
			c.pulseTimer = c.pulse.interval
			firePulse(c, enemies)
		end
	end
	local targetId, tx, tz = nil, 0, 0
	if enemies and not stunned then
		if isDowned(o.player) then
			local p = root.Position
			targetId, tx, tz = nearestEnemy(enemies, p.X, p.Z, FOLLOW.GuardRadius)
		else
			targetId, tx, tz = nearestEnemy(enemies, c.x, c.z, range + (if a.melee then FOLLOW.ChaseLeash else 0))
		end
	end
	if targetId then
		claimed[targetId] = true
		local gx, gz = fx, fz
		if a.melee then
			-- Va au contact, sans quitter la laisse autour du point de suivi.
			local lx, lz = tx - fx, tz - fz
			local ld = math.sqrt(lx * lx + lz * lz)
			if ld > FOLLOW.ChaseLeash then
				lx, lz = lx / ld * FOLLOW.ChaseLeash, lz / ld * FOLLOW.ChaseLeash
			end
			gx, gz = fx + lx, fz + lz
		end
		moveToward(c, gx, gz, false)
		local dx, dz = tx - c.x, tz - c.z
		c.yaw = math.atan2(-dx, -dz)
		if c.timer <= 0 and dx * dx + dz * dz <= (range + 1.5) * (range + 1.5) then
			c.timer = a.interval
			attackTarget(c, enemies, targetId, tx, tz)
		end
	else
		moveToward(c, fx, fz, true)
	end
	updateHeight(c, root)
end

-- Snapshot ----------------------------------------------------------------------------------------

local function quantize(v: number): number
	return math.clamp(math.round(v * NET.PositionScale), -MAX_I16, MAX_I16)
end

local function sendSnapshot(now: number)
	local n = #order
	if n == 0 then
		return
	end
	local perChunk = (NET.ChunkMaxBytes - NET.HeaderBytes) // NET.RecordBytes
	local chunks = math.ceil(n / perChunk)
	for ch = 0, chunks - 1 do
		local first = ch * perChunk + 1
		local last = math.min(n, first + perChunk - 1)
		local count = last - first + 1
		local b = buffer.create(NET.HeaderBytes + count * NET.RecordBytes)
		buffer.writeu32(b, 0, simTick % 4294967296)
		buffer.writeu8(b, 4, count)
		local o = NET.HeaderBytes
		for k = first, last do
			local c = order[k]
			buffer.writef64(b, o, c.userId)
			buffer.writeu8(b, o + 8, c.slot)
			buffer.writeu8(b, o + 9, c.kind)
			buffer.writei16(b, o + 10, quantize(c.x))
			buffer.writei16(b, o + 12, quantize(c.y))
			buffer.writei16(b, o + 14, quantize(c.z))
			buffer.writeu8(b, o + 16, math.floor((c.yaw % TWO_PI) / TWO_PI * 256) % 256)
			buffer.writeu8(b, o + 17, if isStunned(c.owner, now) then NET.StunnedBit else 0)
			buffer.writeu8(b, o + 18, c.evSeq)
			buffer.writeu8(b, o + 19, c.evKind)
			buffer.writei16(b, o + 20, quantize(c.evX))
			buffer.writei16(b, o + 22, quantize(c.evZ))
			buffer.writeu8(b, o + 24, math.clamp(math.round(c.evRadius), 0, 255))
			o += NET.RecordBytes
		end
		snapshotRemote:FireAllClients(b)
	end
end

-- Cycle de vie des compagnons -----------------------------------------------------------------------

local function flushKills(o: Owner)
	if o.pendingKills > 0 then
		recordStat(o.player, Companions.QuestKeys.Kills, o.pendingKills)
		o.pendingKills = 0
	end
end

local function removeOwner(player: Player)
	local o = owners[player]
	if not o then
		return
	end
	flushKills(o)
	owners[player] = nil
	for k = #order, 1, -1 do
		if order[k].owner == o then
			table.remove(order, k)
		end
	end
end

local function addCompanion(o: Owner, kind: number)
	local def = capturableDef(kind)
	if not def then
		return
	end
	local override = Companions.Species[def.name]
	local root = ownerRoot(o.player)
	local p = if root then root.Position else Vector3.zero
	local c: Companion = {
		owner = o,
		userId = o.player.UserId,
		slot = #o.companions + 1,
		kind = kind,
		species = def.name,
		base = attackFor(def),
		attack = attackFor(def),
		power = 0,
		haste = 0,
		reach = 0,
		pulse = nil,
		pulseTimer = 0,
		flying = override ~= nil and override.flying == true,
		x = p.X,
		y = math.max(Heightmap.getY(p.X, p.Z), p.Y - 3),
		z = p.Z,
		yaw = 0,
		timer = 0,
		evSeq = 0,
		evKind = NET.EvNone,
		evX = 0,
		evZ = 0,
		evRadius = 0,
	}
	table.insert(o.companions, c)
	table.insert(order, c)
	rebuildAttack(c)
	o.stateDirty = true
end

-- Espèces équipées, validées : possédées (A12), capturables, sans doublon, au plus slotsFor(classe).
local function equippedSpecies(player: Player, slots: number): { number }
	local raw: { any } = {}
	local progression = find("ProgressionService")
	local ok, list = try(progression, "getCompanionLoadout", player)
	if ok and type(list) == "table" then
		raw = list
	else
		local okL, _, companionId = try(find("RunManager"), "getLoadout", player)
		if not okL then
			okL, _, companionId = try(progression, "getLoadout", player)
		end
		if okL and kindOf(companionId) then
			raw = { companionId }
		elseif memory[player] then
			-- Repli en mémoire (A12 absent) : les dernières espèces capturées.
			local mem = memory[player].order
			for k = #mem, math.max(1, #mem - slots + 1), -1 do
				table.insert(raw, mem[k])
			end
		end
	end
	local out: { number } = {}
	for _, id in raw do
		local kind = kindOf(id)
		if kind and not table.find(out, kind) and #out < slots then
			table.insert(out, kind)
		end
	end
	if #out == 0 and IS_STUDIO and Companions.Debug.TestSpecies then
		local kind = kindOf(Companions.Debug.TestSpecies)
		if kind then
			table.insert(out, kind)
		end
	end
	return out
end

local function createOwner(player: Player)
	removeOwner(player)
	local classId = classOf(player)
	local passive = passiveOf(classId)
	local level = 1
	local okLv, lv = try(find("StatsService"), "getLevel", player)
	if okLv and type(lv) == "number" then
		level = lv
	end
	local o: Owner = {
		player = player,
		companions = {},
		classId = classId,
		level = level,
		power = 0,
		haste = 0,
		reach = 0,
		tamerBonus = if passive and type(passive.companionDamage) == "number" then passive.companionDamage else 0,
		treatStacks = {},
		techs = {},
		dmgMult = 1,
		stunnedUntil = 0,
		dead = false,
		pendingKills = 0,
		stateDirty = true,
		lastStateAt = 0,
	}
	owners[player] = o
	for _, kind in equippedSpecies(player, CompanionService.slotsFor(classId)) do
		addCompanion(o, kind)
	end
	refreshDamageMult(o)
end

-- Cages -------------------------------------------------------------------------------------------

local function broadcastCages(target: Player?)
	local list = table.create(#cages)
	for k, cage in cages do
		local done = {}
		for p in cage.done do
			table.insert(done, p.UserId)
		end
		list[k] = {
			id = cage.id,
			species = cage.species,
			kind = cage.kind,
			x = cage.x,
			y = cage.y,
			z = cage.z,
			expiresIn = math.max(0, cage.expiresAt - simTime),
			done = done,
		}
	end
	if target then
		cageRemote:FireClient(target, { cages = list })
	else
		cageRemote:FireAllClients({ cages = list })
	end
end

local function sendCapture(player: Player, a: Attempt, state: string, progress: number, extra: { [string]: any }?)
	local rounded = math.floor(progress * 10 + 0.5) / 10
	if extra == nil and state == a.sentState and rounded == a.sentProgress then
		return
	end
	a.sentState = state
	a.sentProgress = rounded
	a.sentAt = os.clock()
	local payload: { [string]: any } = { state = state, progress = progress, holdSeconds = holdSecondsFor(player) }
	if extra then
		for k, v in extra do
			payload[k] = v
		end
	end
	captureRemote:FireClient(player, payload)
end

local function attemptOf(player: Player): Attempt
	local a = attempts[player]
	if not a then
		a = { cageId = nil, held = 0, strikes = 0, lockUntil = 0, sentState = "Idle", sentProgress = 0, sentAt = 0 }
		attempts[player] = a
	end
	return a
end

local function runStrikes(player: Player): number
	local ok, n = try(find("MovementGuard"), "getRunStrikes", player)
	return if ok and type(n) == "number" then n else 0
end

local function createCage(kind: number, x: number, z: number): number?
	local def = capturableDef(kind)
	if not def or type(x) ~= "number" or type(z) ~= "number" or x ~= x or z ~= z or not phaseAllows() then
		return nil
	end
	if #cages >= CAP.MaxCages then
		table.remove(cages, 1)
	end
	cageSerial += 1
	table.insert(cages, {
		id = cageSerial,
		kind = kind,
		species = def.name,
		name = def.label,
		x = x,
		y = Heightmap.getY(x, z),
		z = z,
		expiresAt = simTime + CAP.CageSeconds,
		done = {},
	})
	broadcastCages()
	return cageSerial
end

local function clearCages()
	table.clear(cages)
	for player, a in attempts do
		if a.sentState == "Capturing" and player.Parent then
			sendCapture(player, a, "Idle", 0)
		end
		a.cageId, a.held = nil, 0
	end
	broadcastCages()
end

-- Repli en mémoire quand ProgressionService.grantCapture n'existe pas encore (A12).
local function grantInMemory(player: Player, species: string): boolean
	warnOnce("memory", "ProgressionService.grantCapture missing: captures kept in memory only (lost on leave)")
	local mem = memory[player]
	if not mem then
		mem = { order = {}, owned = {} }
		memory[player] = mem
	end
	local isNew = mem.owned[species] == nil
	mem.owned[species] = (mem.owned[species] or 0) + 1
	local i = table.find(mem.order, species)
	if i then
		table.remove(mem.order, i)
	end
	table.insert(mem.order, species)
	-- Test : un joueur sans compagnon reçoit tout de suite sa capture.
	local o = owners[player]
	local kind = speciesKind[species]
	if o and kind and (#o.companions == 0 or (o.companions[1].species == Companions.Debug.TestSpecies and #o.companions == 1)) then
		if #o.companions == 1 then
			removeOwner(player)
			createOwner(player)
		else
			addCompanion(o, kind)
		end
	end
	return isNew
end

local function grant(player: Player, cage: Cage, a: Attempt)
	cage.done[player] = true
	capturesThisRun[player] = (capturesThisRun[player] or 0) + 1
	a.cageId, a.held = nil, 0
	local key = `{if game.JobId ~= "" then game.JobId else "studio"}:{runSerial}:{cage.id}`
	local species, name = cage.species, cage.name
	task.spawn(function()
		local progression = find("ProgressionService")
		local result, isNew = "Granted", false
		if progression and type(progression.grantCapture) == "function" then
			local ok, r, n = pcall(progression.grantCapture, player, species, key)
			result = if ok and type(r) == "string" then r else "Unavailable"
			isNew = ok and n == true
		else
			isNew = grantInMemory(player, species)
		end
		if not player.Parent then
			return
		end
		if result == "Unavailable" then
			-- Refusée, jamais mise de côté ; le joueur peut réessayer tant que la cage vit.
			cage.done[player] = nil
			capturesThisRun[player] = math.max(0, (capturesThisRun[player] or 1) - 1)
			sendCapture(player, a, "Refused", 0, { reason = "Unavailable", name = name })
			return
		end
		sendCapture(player, a, "Captured", 1, { name = name, isNew = isNew })
		local list = runCaptured[player] or {}
		runCaptured[player] = list
		table.insert(list, species)
		if result == "Granted" then
			recordStat(player, Companions.QuestKeys.Captured, 1)
			if isNew then
				recordStat(player, Companions.QuestKeys.NewSpecies, 1)
			end
		end
		broadcastCages()
	end)
end

local function stepCapture(now: number, frozen: boolean)
	-- Expiration (le temps de simulation s'arrête pendant un gel).
	local changed = false
	for k = #cages, 1, -1 do
		local cage = cages[k]
		local everyone = true
		for _, p in runPlayers() do
			if not cage.done[p] then
				everyone = false
				break
			end
		end
		if simTime >= cage.expiresAt or everyone then
			table.remove(cages, k)
			changed = true
		end
	end
	if changed then
		broadcastCages()
	end

	local phaseOk = phaseAllows()
	local run = find("RunManager")
	local cards = find("CardService")
	for _, player in runPlayers() do
		local hitNow = hitFlag[player] == true
		hitFlag[player] = nil
		local a = attemptOf(player)
		local root = ownerRoot(player)
		local inCage: Cage? = nil
		local near: Cage? = nil
		if root and #cages > 0 then
			local p = root.Position
			local okF, feet = try(run, "getDamageFeetY", player)
			local feetY = if okF and type(feet) == "number" then feet else p.Y - 3
			local bestD2 = CAP.Radius * CAP.Radius
			local nearD2 = CAP.AvailableRadius * CAP.AvailableRadius
			for _, cage in cages do
				if not cage.done[player] then
					local dx, dz = p.X - cage.x, p.Z - cage.z
					local d2 = dx * dx + dz * dz
					if d2 <= bestD2 and math.abs(feetY - cage.y) <= CAP.VerticalTolerance then
						bestD2 = d2
						inCage = cage
					end
					if d2 <= nearD2 then
						nearD2 = d2
						near = cage
					end
				end
			end
		end
		if not inCage then
			if a.cageId then
				a.cageId, a.held = nil, 0
			end
			-- « Available » : une cage à capturer est proche (bouton Capture du HUD, sans panneau).
			-- Interrupted / Captured / Refused restent affichés StickySeconds avant de céder la place.
			local sticky = (a.sentState == "Interrupted" or a.sentState == "Captured" or a.sentState == "Refused")
				and now - a.sentAt < CAP.StickySeconds
			local wanted = if near and phaseOk and (capturesThisRun[player] or 0) < CAP.MaxPerRun then "Available" else "Idle"
			if not sticky and a.sentState ~= wanted then
				sendCapture(player, a, wanted, 0, if near then { name = (near :: Cage).name } else nil)
			end
			continue
		end
		local cage = inCage :: Cage
		if a.cageId ~= cage.id then
			a.cageId, a.held, a.strikes = cage.id, 0, runStrikes(player)
		end
		if (capturesThisRun[player] or 0) >= CAP.MaxPerRun then
			if a.sentState ~= "Refused" then
				sendCapture(player, a, "Refused", 0, { reason = "Cap", name = cage.name })
			end
			continue
		end
		if not isActive(player) then
			a.held = 0
			if a.sentState == "Capturing" then
				sendCapture(player, a, "Idle", 0)
			end
			continue
		end
		local strikes = runStrikes(player)
		if hitNow or strikes > a.strikes then
			a.held, a.strikes = 0, strikes
			a.lockUntil = now + CAP.InterruptLockout
			sendCapture(player, a, "Interrupted", 0)
			continue
		end
		if now < a.lockUntil then
			continue
		end
		local hold = holdSecondsFor(player)
		local okC, choosing = try(cards, "isChoosing", player)
		if not (frozen or not phaseOk or (okC and choosing == true)) then
			a.held += DT
		end
		if a.held >= hold then
			grant(player, cage, a)
		else
			sendCapture(player, a, "Capturing", math.clamp(a.held / hold, 0, 1))
		end
	end
end

-- Boucle ------------------------------------------------------------------------------------------

local function step()
	simTick += 1
	local now = os.clock()
	local frozen = isFrozen()
	if not frozen then
		simTime += DT
	end
	local enemies = find("EnemyService")
	table.clear(claimed)
	local refresh = simTick % Companions.SimHz == 0
	for _, o in owners do
		if refresh then
			refreshDamageMult(o)
		end
	end
	for _, c in order do
		updateCompanion(c, enemies, now, frozen)
	end
	stepCapture(now, frozen)
	sendSnapshot(now)
	local minGap = 1 / Companions.StateMaxPerSecond
	for _, o in owners do
		if o.stateDirty and now - o.lastStateAt >= minGap and o.player.Parent then
			sendState(o)
		end
	end
end

-- Cartes : techniques d'espèce (A05-03) et Friandises -------------------------------------------------
-- Textes joueur en anglais seul au lancement (60-ui-ux.md, demandes à Ironix).

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

local function shuffle<T>(list: { T })
	for k = #list, 2, -1 do
		local j = math.random(1, k)
		list[k], list[j] = list[j], list[k]
	end
end

-- Carte d'une technique : apprendre (niveau 1) ou améliorer ({v} devient « avant -> après »).
local function techCard(def: TechDef, current: number): Types.Card
	local nextLevel = current + 1
	local nextValue = formatTechValue(def, techValue(def, nextLevel))
	local value = if current > 0 then `{formatTechValue(def, techValue(def, current))} -> {nextValue}` else nextValue
	local desc = string.gsub(def.desc, "{v}", value)
	if current > 0 then
		desc = string.gsub(Companions.Cards.TechUpPrefix, "{n}", tostring(nextLevel)) .. desc
	end
	return {
		kind = if current > 0 then "CompanionTechUp" else "CompanionTech",
		id = def.id,
		rarity = (if current > 0 then Companions.Cards.TechUpRarity else Companions.Cards.TechRarity) :: Types.Rarity,
		level = nextLevel,
		title = def.name,
		desc = desc,
		icon = nil,
	}
end

-- Jusqu'à Cards.MaxOptions cartes compagnon pour le prochain niveau (CardService décide de la fréquence) :
-- au plus MaxTechOptions techniques des compagnons équipés, le reste en Friandises.
function CompanionService.getCardOptions(player: Player): { Types.Card }
	local o = owners[player]
	if not o or #o.companions == 0 then
		return {}
	end
	local techCards: { Types.Card } = {}
	for _, c in o.companions do
		for _, def in techsOf(c.species) do
			local current = o.techs[def.id] or 0
			if current < math.min(Companions.TechMaxLevel, #def.values) then
				table.insert(techCards, techCard(def, current))
			end
		end
	end
	shuffle(techCards)
	local treatCards: { Types.Card } = {}
	for id, def in Companions.Treats do
		local stacks = o.treatStacks[id] or 0
		if stacks < def.maxStacks then
			local rarity = rollTreatRarity()
			local pct = tostring(math.round(def.values[rarity] * 100))
			table.insert(treatCards, {
				kind = "CompanionTreat",
				id = id,
				rarity = rarity,
				level = stacks + 1,
				title = def.name.en,
				desc = (string.gsub(Companions.TreatDesc[def.stat] or "+{p}%", "{p}", pct)),
				icon = nil,
			})
		end
	end
	shuffle(treatCards)
	local pool: { Types.Card } = {}
	for k = 1, math.min(#techCards, Companions.Cards.MaxTechOptions) do
		table.insert(pool, techCards[k])
	end
	for _, card in treatCards do
		if #pool >= Companions.Cards.MaxOptions then
			break
		end
		table.insert(pool, card)
	end
	shuffle(pool)
	return pool
end

local function applyTech(o: Owner, card: Types.Card)
	local entry = techIndex[card.id]
	if not entry then
		return
	end
	local target: Companion? = nil
	for _, c in o.companions do
		if c.species == entry.species then
			target = c
		end
	end
	if not target then
		return -- technique d'une espèce que le joueur n'a pas équipée : refusée
	end
	local current = o.techs[card.id] or 0
	local maxLevel = math.min(Companions.TechMaxLevel, #entry.def.values)
	-- La carte doit correspondre à l'état serveur : apprendre (0 -> 1) ou améliorer (n -> n+1).
	if current >= maxLevel or (card.kind == "CompanionTech") ~= (current == 0) then
		return
	end
	o.techs[card.id] = current + 1
	rebuildAttack(target)
	if current == 0 then
		recordStat(o.player, Companions.QuestKeys.Techs, 1)
	end
	o.stateDirty = true
end

-- Applique une carte choisie. Revalide tout (genre, id, plafond).
function CompanionService.applyCard(player: Player, card: Types.Card)
	local o = owners[player]
	if not o or type(card) ~= "table" or type(card.id) ~= "string" then
		return
	end
	if card.kind == "CompanionTech" or card.kind == "CompanionTechUp" then
		applyTech(o, card)
		return
	end
	if card.kind ~= "CompanionTreat" then
		return
	end
	local def = Companions.Treats[card.id]
	if not def then
		return
	end
	local stacks = o.treatStacks[card.id] or 0
	if stacks >= def.maxStacks then
		return
	end
	local value = def.values[card.rarity] or def.values.Common
	o.treatStacks[card.id] = stacks + 1
	if def.stat == "Power" then
		o.power += value
	elseif def.stat == "Haste" then
		o.haste += value
	elseif def.stat == "Reach" then
		o.reach += value
	end
	refreshDamageMult(o)
	recordStat(player, Companions.QuestKeys.Treats, 1)
	o.stateDirty = true
end

-- API publique ------------------------------------------------------------------------------------

-- Gardé pour le contrat (autels, objets) : pas d'Ultime en v2, sans effet.
function CompanionService.chargeUltimate(_player: Player, _amount: number) end

function CompanionService.getState(player: Player): { line: string, stage: number, level: number }?
	local o = owners[player]
	if not o or #o.companions == 0 then
		return nil
	end
	return { line = o.companions[1].species, stage = 1, level = o.level }
end

-- Emplacements de compagnon de la classe : 1, ou 2 pour le Tamer (Passives[classId].companionSlots).
function CompanionService.slotsFor(classId: string): number
	local passive = passiveOf(classId)
	if passive and type(passive.companionSlots) == "number" and passive.companionSlots >= 1 then
		return math.floor(passive.companionSlots)
	end
	return Companions.DefaultSlots
end

-- Vrai si `id` (nom d'espèce ou kind) est une espèce capturable (pas un boss).
function CompanionService.isSpecies(id: string | number): boolean
	return kindOf(id) ~= nil
end

function CompanionService.speciesName(id: string): LocalizedText?
	local kind = kindOf(id)
	return if kind then Enemies[kind].label else nil
end

-- A03 : à appeler UNE fois quand un ennemi marqué capturable à son apparition meurt sous les coups.
-- Ne cède jamais. Renvoie l'id de la cage, ou nil (espèce inconnue, boss, phase hors jeu).
function CompanionService.onCapturableDefeated(kind: number, x: number, z: number, _killer: Player?): number?
	if type(kind) ~= "number" then
		return nil
	end
	externalCages = true
	return createCage(kind, x, z)
end

function CompanionService.getCages(): { { id: number, species: string, x: number, z: number, expiresAt: number } }
	local out = table.create(#cages)
	for k, cage in cages do
		out[k] = { id = cage.id, species = cage.species, x = cage.x, z = cage.z, expiresAt = os.clock() + (cage.expiresAt - simTime) }
	end
	return out
end

-- RunManager (RunSummary.captured) : espèces capturées par ce joueur pendant la run, dans l'ordre.
function CompanionService.getRunCaptures(player: Player): { string }
	return table.clone(runCaptured[player] or {})
end

-- RunManager : joueur qui arrive en cours de run.
function CompanionService.ensure(player: Player)
	if player.Parent and not owners[player] then
		createOwner(player)
	end
	if player.Parent then
		broadcastCages(player)
	end
end

-- Démarrage ---------------------------------------------------------------------------------------

local function onHit(player: any)
	if typeof(player) == "Instance" and player:IsA("Player") then
		hitFlag[player] = true
	end
end

function CompanionService.init()
	for kind, def in Enemies do
		if type(kind) == "number" and capturableDef(kind) then
			speciesKind[def.name] = kind
		end
	end
	for species, sdef in Companions.Species do
		if not speciesKind[species] then
			warnOnce("species_" .. species, `Companions.Species.{species} is not a capturable enemy name (ignored)`)
		end
		for _, tech in sdef.techs or {} do
			if techIndex[tech.id] then
				warnOnce("tech_" .. tech.id, `duplicate technique id {tech.id}`)
			end
			techIndex[tech.id] = { species = species, def = tech }
		end
	end
	stateRemote = Net.event("CompanionState")
	snapshotRemote = Net.unreliable("CompanionSnapshot")
	captureRemote = Net.event("CaptureState")
	cageRemote = Net.event("CageState")
	-- Aucun remote C->S : la capture ne dépend que de la position mesurée par le serveur.

	Bus.RunStarted:connect(function(players: { Player })
		runSerial += 1
		simTime = 0
		debugKills = 0
		table.clear(capturesThisRun)
		table.clear(runCaptured)
		table.clear(attempts)
		table.clear(hitFlag)
		clearCages()
		for player in owners do
			removeOwner(player)
		end
		for _, player in players do
			if player.Parent then
				createOwner(player)
			end
		end
	end)
	Bus.RunEnded:connect(function()
		for player in owners do
			removeOwner(player)
		end
		clearCages()
	end)
	-- Cash out en coop (RunManager) : le joueur quitte la run, son compagnon aussi (ses captures
	-- sont déjà dans son RunSummary).
	Bus.PlayerCashedOut:connect(function(player: Player)
		removeOwner(player)
	end)
	Bus.StageStarted:connect(function()
		clearCages()
		for _, c in order do
			local root = ownerRoot(c.owner.player)
			if root then
				c.x, c.z = root.Position.X, root.Position.Z
				c.y = Heightmap.getY(c.x, c.z)
			end
		end
	end)
	Bus.PlayerLeveledUp:connect(function(player: Player, level: number)
		local o = owners[player]
		if o and type(level) == "number" then
			o.level = level
			refreshDamageMult(o)
			o.stateDirty = true
		end
	end)
	-- « Touché » : Bus.PlayerHit (A04-v3 : tout coup reçu, même bloqué, tiré au début de
	-- RunManager.damagePlayer). Repli sans lui : Bus.PlayerDamaged (seulement les coups qui font des dégâts).
	local busAny = Bus :: any
	if busAny.PlayerHit and type(busAny.PlayerHit.connect) == "function" then
		busAny.PlayerHit:connect(onHit)
	else
		warnOnce("hit", "Bus.PlayerHit missing: blocked hits do not interrupt captures yet")
	end
	Bus.PlayerDamaged:connect(onHit)
	-- Gel du passage de niveau (A04-v3, RunManager.isFrozen lu à chaque tic) : à la reprise,
	-- Bus.RunFrozen(false, pausedSeconds) décale les minuteries en temps réel (sonné, blocage après un coup).
	if busAny.RunFrozen and type(busAny.RunFrozen.connect) == "function" then
		busAny.RunFrozen:connect(function(frozen: any, pausedSeconds: any)
			if frozen ~= false or type(pausedSeconds) ~= "number" or pausedSeconds <= 0 or pausedSeconds ~= pausedSeconds then
				return
			end
			local now = os.clock()
			for _, o in owners do
				if o.stunnedUntil > now - pausedSeconds then
					o.stunnedUntil += pausedSeconds
				end
			end
			for _, a in attempts do
				if a.lockUntil > now - pausedSeconds then
					a.lockUntil += pausedSeconds
				end
			end
		end)
	end
	Bus.PlayerDowned:connect(function(player: Player)
		local o = owners[player]
		if o then
			o.stunnedUntil = os.clock() + Companions.StunOnDowned
			o.stateDirty = true
		end
	end)
	Bus.PlayerRevived:connect(function(player: Player)
		local o = owners[player]
		if o then
			o.stunnedUntil = 0
			o.dead = false
			o.stateDirty = true
		end
	end)
	Bus.PlayerDied:connect(function(player: Player)
		local o = owners[player]
		if o then
			o.dead = true
			o.stateDirty = true
		end
	end)
	-- Test en Studio tant qu'A03 ne marque pas de capturables : un ennemi non boss sur N laisse une cage.
	Bus.EnemyKilled:connect(function(_id: number, kind: number, x: number, z: number)
		local every = Companions.Debug.CageEveryNthKill
		if not IS_STUDIO or externalCages or every <= 0 or type(kind) ~= "number" or not capturableDef(kind) then
			return
		end
		debugKills += 1
		if debugKills % every == 0 then
			createCage(kind, x, z)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		removeOwner(player)
		attempts[player] = nil
		capturesThisRun[player] = nil
		runCaptured[player] = nil
		hitFlag[player] = nil
		memory[player] = nil
		for _, cage in cages do
			cage.done[player] = nil
		end
	end)
end

function CompanionService.start()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc = math.min(acc + dt, DT * 3)
		while acc >= DT do
			acc -= DT
			step()
		end
	end)
end

return CompanionService
