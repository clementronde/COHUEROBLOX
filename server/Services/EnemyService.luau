--!strict
-- Enemies as data, not Humanoids (doc 12.2, dossier 20 section 4).
-- Struct-of-arrays, dense indices 1..count, swap-remove on death.
-- 15 Hz: family AI (swarm / jumper / shooter / armored) + hard non-overlap relax through a
-- spatial grid, then each client gets only the enemies around it, in chunks of <= 900 bytes
-- over an UnreliableRemoteEvent. Enemy projectiles are simulated here as points and sent once
-- at creation (closed-form replay on the client, vault "Projectiles and Ballistics").
-- Bosses are entities here too (so weapons hit them) but BossService drives them ("external").
-- Run v2 (A04-02) : la force vient de Config/Run.WorldScaling (index du monde = director.stage) et
-- du directeur réglé par RunManager (Overtime : densité, PV, dégâts, part d'élites).
-- Au-delà du plafond technique Balance.MaxEnemies, l'excès de densité devient des PV (Run.Overtime.OverflowToHp).
-- Débit (A03-v3, PERF-01) : chaque client reçoit à chaque tick ses ennemis les plus proches et ceux
-- qui agissent, le reste à cadence réduite (voir send), plus la liste des ennemis retirés.
-- Pas d'allocation par tick dans les boucles chaudes (PERF-04) : grille, cibles et tampons réutilisés.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Enemies = require(Config:WaitForChild("Enemies"))
local Run = require(Config:WaitForChild("Run"))
local Worlds = require(Config:WaitForChild("Worlds"))
local Codec = require(Shared:WaitForChild("EnemyCodec"))
local Heightmap = require(Shared:WaitForChild("Heightmap"))
local Net = require(Shared:WaitForChild("Net"))
local Registry = require(Shared:WaitForChild("Registry"))
local Bus = require(script.Parent.Parent:WaitForChild("Bus"))

local DT = 1 / Balance.SimHz
local CELL = Balance.GridCellSize
local MAX_ID = 65535
local MAX_PROJECTILES = 150
local DOT_INTERVAL = 0.5
local KNOCKBACK_TIME = 0.25
local MAX_PUDDLES = 24
local PUDDLE_TICK = 0.5

-- actPhase : 0 marche, 1 préparation (saut, tir, aura, mèche), 2 en l'air, 3 sous terre, 4 surgit
local PHASE_AIR = 2
local PHASE_BURROWED = 3
local PHASE_EMERGING = 4

-- State bits (3 bits on the wire)
local BIT_ELITE = 1
local BIT_ACTION = 2
local BIT_STOPPED = 4

type Target = { player: Player, x: number, y: number, z: number }

local EnemyService = {}

-- Enemy state (parallel arrays) -------------------------------------------------------------
local count = 0
local ids: { number } = {}
local xs: { number } = {}
local zs: { number } = {}
local hps: { number } = {}
local kinds: { number } = {}
local states: { number } = {}
local targetOf: { [number]: Player } = {}
local dmgMult: { number } = {}
local sizeMult: { number } = {}
local external: { boolean } = {}
-- Élite « à butin » (coffre chez LootService). En Overtime, les élites en plus du plafond classique
-- Run.EliteMaxAlive gardent PV, taille et couronne mais sortent sans coffre : sinon la part d'élites
-- sans plafond ferait pleuvoir les coffres. Bus.EnemyKilled porte isElite = élite à butin.
local lootElite: { boolean } = {}
-- Family AI
local actPhase: { number } = {} -- 0 idle/walk, 1 windup, 2 airborne
local actT: { number } = {}
local actX: { number } = {}
local actZ: { number } = {}
local actOX: { number } = {}
local actOZ: { number } = {}
-- Statuses
local burnDps: { number } = {}
local burnUntil: { number } = {}
local burnSrc: { [number]: Player } = {}
local poisonDps: { number } = {}
local poisonUntil: { number } = {}
local poisonSrc: { [number]: Player } = {}
local dotNext: { number } = {}
local slowMult: { number } = {}
local slowUntil: { number } = {}
local stopUntil: { number } = {}
local kbVX: { number } = {}
local kbVZ: { number } = {}
local kbUntil: { number } = {}
-- Comportements spéciaux (A03-04)
local maxHps: { number } = {}
local hasteMult: { number } = {}
local hasteUntil: { number } = {}
-- Variante capturable (A03-03), marquée à l'apparition, jamais lue chez le client (remote à part)
local capturable: { boolean } = {}
-- Réseau (PERF-01) : dernier état vu par send et tick du dernier changement (envoi immédiat)
local stateSent: { number } = {}
local stateChangedAt: { number } = {}

local columns: { { any } } = {
	ids, xs, zs, hps, kinds, states, targetOf :: any, dmgMult, sizeMult, external, lootElite,
	actPhase, actT, actX, actZ, actOX, actOZ,
	burnDps, burnUntil, burnSrc :: any, poisonDps, poisonUntil, poisonSrc :: any, dotNext,
	slowMult, slowUntil, stopUntil, kbVX, kbVZ, kbUntil,
	maxHps, hasteMult, hasteUntil, capturable, stateSent, stateChangedAt,
}

-- Ids des entités externes (boss) : peu nombreuses, testées à part par queryRadius (PERF-03).
local externalIds: { number } = {}
-- Ids retirés depuis le dernier envoi (morts, nettoyage) : le client les efface tout de suite.
local removedQueue: { number } = {}
local removedN = 0

local indexOf: { [number]: number } = {} -- id -> index
local lootEliteAlive = 0 -- élites à butin vivantes, hors mini-boss (plafond Run.EliteMaxAlive)
local coinTimes: { [number]: number } = {}

local nextId = 1
local simTick = 0
-- Grille spatiale (PERF-04) : les tables des cases sont gardées d'un tick à l'autre et vidées par
-- table.clear ; les cases vides sont retirées toutes les GRID_PRUNE_TICKS.
local grid: { [number]: { number } } = {}
local gridUsed: { number } = {}
local gridUsedN = 0
local GRID_PRUNE_TICKS = 450
local snapshot: UnreliableRemoteEvent
local projectileRemote: RemoteEvent
local attackVisualRemote: UnreliableRemoteEvent
local capturableRemote: RemoteEvent
local capturableAlive = 0

-- Run director (set by RunManager) ---------------------------------------------------------
local director = {
	active = false,
	worldId = Run.DefaultWorld,
	tier = 1,
	stage = 1, -- index du monde dans la run (1..Run.WorldsPerRun)
	stageStart = 0,
	densityMult = 1, -- phase, vague, Overtime, Rune Cursed
	hpMult = 1, -- Overtime, Rune Cursed
	damageMult = 1, -- Overtime
	eliteShare = Run.EliteChance, -- part d'élites parmi les apparitions
	eliteMaxAlive = Run.EliteMaxAlive, -- math.huge en Overtime
	overflowMult = 1, -- densité voulue / plafond quand le plafond est atteint (>= 1)
	familyUnlockScale = 1,
	nextEliteAt = math.huge,
	burstLeft = 0,
	burstPerTick = 0,
}
local halfSize = 1e6

-- Reused buffers
local sendIds: { number } = {}
local sendXs: { number } = {}
local sendZs: { number } = {}
local sendFlags: { number } = {}
local pendingDamage: { number } = {} -- id, amount pairs flattened: [2k-1] = id, [2k] = amount
local pendingSource: { [number]: Player } = {}
local pendingN = 0

-- Projectiles
local pCount = 0
local pIds: { number } = {}
local pX: { number } = {}
local pY: { number } = {}
local pZ: { number } = {}
local pDX: { number } = {}
local pDZ: { number } = {}
local pSpeed: { number } = {}
local pDamage: { number } = {}
local pRadius: { number } = {}
local pEnd: { number } = {}
local nextProjectileId = 1
local projSpawns: { Codec.Projectile } = {}
local projRemoved: { number } = {}

-- Nappes au sol (Bloater, A03-04) : quelques zones en données, testées contre les joueurs.
local puddleN = 0
local pdX: { number } = {}
local pdZ: { number } = {}
local pdY: { number } = {}
local pdR: { number } = {}
local pdEnd: { number } = {}
local pdNext: { number } = {}
local pdDps: { number } = {}
local pdSlow: { number } = {}

-- Ennemis qui se retirent d'eux-mêmes (Kamikaze qui explose) : retirés après la boucle de step,
-- sans KO ni butin (regles-v2 §2.1).
local pendingRemove: { number } = {}
local removeN = 0
local auraBuf: { number } = {}
local warnedNoTakeXp = false

-- Helpers ------------------------------------------------------------------------------------

local function allocId(): number?
	for _ = 1, MAX_ID do
		local id = nextId
		nextId = nextId % MAX_ID + 1
		if indexOf[id] == nil then
			return id
		end
	end
	return nil
end

local function cellKey(cx: number, cz: number): number
	return (cx + 32768) * 65536 + (cz + 32768)
end

local function radiusOf(i: number): number
	return Enemies[kinds[i]].radius * sizeMult[i]
end

local cachedPlayers = 1 -- joueurs de la run, relu une fois par tick (pas une copie de liste par apparition)

local function countRunPlayers(): number
	local run = Registry.find("RunManager")
	if run then
		local ok, list = pcall(run.getRunPlayers)
		if ok and type(list) == "table" and #list > 0 then
			return #list
		end
	end
	return math.max(1, #Players:GetPlayers())
end

local function worldScale(): { hp: number, damage: number, speed: number, density: number, bossHp: number }
	local list = Run.WorldScaling
	return list[math.clamp(director.stage, 1, #list)]
end

local function scaledHp(): number
	local overflow = if Run.Overtime.OverflowToHp then director.overflowMult else 1
	return worldScale().hp * (1 + Balance.HpPerExtraPlayer * (cachedPlayers - 1)) * director.hpMult * overflow
end

local function scaledDamage(): number
	return worldScale().damage * director.damageMult
end

local function clampToMap(x: number, z: number): (number, number)
	local h = halfSize - 4
	return math.clamp(x, -h, h), math.clamp(z, -h, h)
end

local function countsTowardEliteCap(i: number): boolean
	return lootElite[i] and Enemies[kinds[i]].family ~= "MiniBoss"
end

local function insertEnemy(kind: number, x: number, z: number, hp: number, dmg: number, elite: boolean, isExternal: boolean, noLoot: boolean?): number?
	if count >= Balance.MaxEnemies and not isExternal then
		return nil
	end
	local def = Enemies[kind]
	if not def then
		return nil
	end
	local id = allocId()
	if not id then
		return nil
	end
	x, z = clampToMap(x, z)
	count += 1
	if isExternal then
		table.insert(externalIds, id)
	end
	local i = count
	ids[i] = id
	xs[i] = x
	zs[i] = z
	hps[i] = hp
	kinds[i] = kind
	states[i] = if elite then BIT_ELITE else 0
	targetOf[i] = nil
	dmgMult[i] = dmg
	sizeMult[i] = if elite and def.family ~= "MiniBoss" then Run.EliteSizeMult else 1
	external[i] = isExternal
	lootElite[i] = elite and not isExternal and noLoot ~= true
	if countsTowardEliteCap(i) then
		lootEliteAlive += 1
	end
	actPhase[i] = if def.burrow and not isExternal then PHASE_BURROWED else 0
	actT[i] = os.clock() + math.random() * 2
	maxHps[i] = hp
	hasteMult[i], hasteUntil[i] = 1, 0
	capturable[i] = false
	actX[i], actZ[i], actOX[i], actOZ[i] = 0, 0, 0, 0
	burnDps[i], burnUntil[i], burnSrc[i] = 0, 0, nil
	poisonDps[i], poisonUntil[i], poisonSrc[i] = 0, 0, nil
	dotNext[i] = 0
	slowMult[i], slowUntil[i], stopUntil[i] = 1, 0, 0
	kbVX[i], kbVZ[i], kbUntil[i] = 0, 0, 0
	stateSent[i], stateChangedAt[i] = states[i], simTick
	indexOf[id] = i
	return id
end

local function removeAt(i: number)
	if countsTowardEliteCap(i) then
		lootEliteAlive -= 1
	end
	if capturable[i] then
		capturableAlive -= 1
		capturableRemote:FireAllClients(ids[i], false)
	end
	local gone = ids[i]
	indexOf[gone] = nil
	coinTimes[gone] = nil
	removedN += 1
	removedQueue[removedN] = gone
	if external[i] then
		local k = table.find(externalIds, gone)
		if k then
			externalIds[k] = externalIds[#externalIds]
			externalIds[#externalIds] = nil
		end
	end
	local last = count
	if i ~= last then
		for _, col in columns do
			col[i] = col[last]
		end
		indexOf[ids[i]] = i
	end
	for _, col in columns do
		col[last] = nil
	end
	count -= 1
end

-- Tampons réutilisés à chaque tick (PERF-04) : liste des cibles, enregistrements Target, spectateurs
-- et leurs positions (lues aussi par _attackVisual pour n'envoyer qu'aux joueurs proches, PERF-07).
local targetList: { Target } = {}
local targetPool: { Target } = {}
local viewerList: { Player } = {}
local viewerX: { number } = {}
local viewerZ: { number } = {}
local viewerN = 0
local byPlayer: { [Player]: Target } = {}

local function gatherTargets(): ({ Target }, { Player })
	table.clear(targetList)
	table.clear(viewerList)
	viewerN = 0
	local list = targetList
	local viewers = viewerList
	local run = Registry.find("RunManager")
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			table.insert(viewers, player)
			viewerN += 1
			viewerX[viewerN] = root.Position.X
			viewerZ[viewerN] = root.Position.Z
			local active = true
			if run then
				local ok, result = pcall(run.isActive, player)
				active = ok and result == true
			end
			if active then
				local p = root.Position
				-- S-01 : hauteur des pieds retenue par RunManager (au sol après 1,5 s en l'air)
				local feet = p.Y - 3
				if run and run.getDamageFeetY then
					local ok, y = pcall(run.getDamageFeetY, player)
					if ok and type(y) == "number" then
						feet = y
					end
				end
				local k = #list + 1
				local t = targetPool[k]
				if t then
					t.player, t.x, t.y, t.z = player, p.X, feet, p.Z
				else
					t = { player = player, x = p.X, y = feet, z = p.Z }
					targetPool[k] = t
				end
				list[k] = t
			end
		end
	end
	return list, viewers
end

local function nearest(targets: { Target }, x: number, z: number): Target?
	local best: Target? = nil
	local bestD2 = math.huge
	for _, t in targets do
		local dx, dz = t.x - x, t.z - z
		local d2 = dx * dx + dz * dz
		if d2 < bestD2 then
			bestD2 = d2
			best = t
		end
	end
	return best
end

local function ringPoint(t: Target): (number, number)
	for _ = 1, 6 do
		local angle = math.random() * math.pi * 2
		local r = Balance.SpawnRingMin + math.random() * (Balance.SpawnRingMax - Balance.SpawnRingMin)
		local x, z = t.x + math.cos(angle) * r, t.z + math.sin(angle) * r
		if math.abs(x) < halfSize - 6 and math.abs(z) < halfSize - 6 then
			return x, z
		end
	end
	return clampToMap(t.x + (math.random() - 0.5) * 120, t.z + (math.random() - 0.5) * 120)
end

local function curveAt(elapsed: number): number
	local curve = Balance.DensityCurve
	local base = curve[#curve][2]
	for k = 1, #curve - 1 do
		local a, b = curve[k], curve[k + 1]
		if elapsed <= b[1] then
			local u = (elapsed - a[1]) / (b[1] - a[1])
			base = a[2] + (b[2] - a[2]) * math.clamp(u, 0, 1)
			break
		end
	end
	return base
end

-- Ennemis vivants voulus. Met aussi à jour director.overflowMult : la part de densité qui ne
-- tient pas sous le plafond technique (le joueur voit des ennemis plus forts, pas plus nombreux).
local warnedForced = false

local function desiredAlive(elapsed: number, n: number): number
	local forced = Balance.Debug.ForceAlive
	if forced then
		director.overflowMult = 1
		if forced > Balance.MaxEnemies and not warnedForced then
			-- QA-01 : un test à la main à 400 donnait 300 sans prévenir.
			warnedForced = true
			warn(`[EnemyService] Debug.ForceAlive = {forced} > MaxEnemies = {Balance.MaxEnemies} : la horde reste à {Balance.MaxEnemies}. Monter aussi Balance.MaxEnemies pour le test.`)
		end
		return math.min(forced, Balance.MaxEnemies)
	end
	local scaled = curveAt(elapsed)
		* worldScale().density
		* director.densityMult
		* (1 + Balance.DensityPerExtraPlayer * (n - 1))
	director.overflowMult = math.max(1, scaled / Balance.MaxEnemies)
	return math.min(math.floor(scaled), Balance.MaxEnemies)
end

-- Familles tirées hors essaim, dans l'ordre de Run.FamilyUnlock. Une famille absente du roster du
-- monde est ignorée. Tampons réutilisés (pas d'allocation par apparition).
local SPAWN_FAMILIES = { "Jumper", "Shooter", "Armored", "Support", "Kamikaze" }
local optionKinds: { number } = {}
local optionFamilies: { string } = {}

local function withVariant(world: Worlds.World, family: string, kind: number): number
	local variant = world.variants and world.variants[family]
	if variant and math.random() < variant.chance then
		return variant.kind
	end
	return kind
end

local function pickSwarm(world: Worlds.World): number
	return withVariant(world, "Swarm", world.roster.Swarm)
end

local function pickKind(elapsed: number): number
	local world = Worlds[director.worldId] or Worlds[Run.DefaultWorld]
	if math.random() < Balance.SwarmShare then
		return pickSwarm(world)
	end
	local n = 0
	for _, family in SPAWN_FAMILIES do
		local kind = (world.roster :: any)[family]
		local unlock = Run.FamilyUnlock[family]
		if type(kind) == "number" and unlock and elapsed >= unlock * director.familyUnlockScale then
			n += 1
			optionKinds[n] = kind
			optionFamilies[n] = family
		end
	end
	if n == 0 then
		return pickSwarm(world)
	end
	local k = math.random(n)
	return withVariant(world, optionFamilies[k], optionKinds[k])
end

-- Variante capturable (A03-03, dossier 40 §6.1) : tirage au sort, puis CompanionService.isSpecies
-- (pcall : sans CompanionService ou sans cette fonction, rien n'est capturable).
local function rollCapturable(kind: number, def: Enemies.Def): boolean
	local C = Run.Capturable
	if def.isBoss or def.family == "Boss" or capturableAlive >= C.MaxAlive then
		return false
	end
	if os.clock() - director.stageStart < C.FirstAt then
		return false
	end
	local chance = def.captureChance or (if def.family == "MiniBoss" then C.MiniBossChance else C.Chance)
	if chance <= 0 or math.random() >= chance then
		return false
	end
	local companions = Registry.find("CompanionService")
	local isSpecies = companions and (companions :: any).isSpecies
	if type(isSpecies) ~= "function" then
		return false
	end
	local ok, yes = pcall(isSpecies, kind)
	return ok and yes == true
end

local function spawnScaled(kind: number, x: number, z: number, elite: boolean, hpMult: number, noLoot: boolean?): number?
	local def = Enemies[kind]
	if not def then
		return nil
	end
	local hp = def.hp * scaledHp() * hpMult
	if elite and def.family ~= "MiniBoss" then
		hp *= Run.EliteHpMult
	end
	local catchable = rollCapturable(kind, def)
	if catchable then
		hp *= Run.Capturable.HpMult
	end
	local dmg = scaledDamage() * (if elite then Run.Player.EliteDamageMult else 1)
	-- Règles anti-triche §5.2 : jamais inf ni NaN, même après des heures d'Overtime.
	local cap = Run.Overtime.ValueCap
	hp = if hp == hp then math.min(hp, cap) else cap
	dmg = if dmg == dmg then math.min(dmg, cap) else cap
	local id = insertEnemy(kind, x, z, hp, dmg, elite, false, noLoot)
	if id and catchable then
		capturable[indexOf[id]] = true
		capturableAlive += 1
		capturableRemote:FireAllClients(id, true)
	end
	return id
end

-- Signal visuel en binaire (EnemyCodec.encodeAttack, 14 octets), envoyé seulement aux joueurs assez
-- proches pour le voir (PERF-07 : avant, deux textes et deux Vector3 vers tous les clients).
local function fireAttackCue(id: number, kind: number, mode: string, x: number, y: number, z: number, dx: number, dz: number, radius: number)
	local reach = Balance.AttackVisualRadius * (if mode == "boss" then 1.6 else 1)
	local reach2 = reach * reach
	local payload: buffer? = nil
	for k = 1, viewerN do
		local ox, oz = viewerX[k] - x, viewerZ[k] - z
		if ox * ox + oz * oz <= reach2 then
			payload = payload or Codec.encodeAttack(id, kind, mode, x, y, z, dx, dz, radius)
			if not payload then
				return
			end
			attackVisualRemote:FireClient(viewerList[k], payload)
		end
	end
end

-- Sends only cosmetic cues. Direction is flattened so effects stay aligned to the ground.
function EnemyService._attackVisual(id: number, mode: string, x: number, z: number, dx: number, dz: number, radius: number?)
	local i = indexOf[id]
	if not i then
		return
	end
	if mode == "contact" and (external[i] or actPhase[i] ~= 0) then
		return
	end
	local y = Heightmap.getY(x, z) + (if mode == "shot" then 2.5 else 0)
	fireAttackCue(id, kinds[i], mode, x, y, z, dx, dz, radius or radiusOf(i))
end

-- Projectiles ----------------------------------------------------------------------------------

-- style = EnemyCodec.packStyle(kind du tireur, rang de l'attaque de boss) : le client choisit l'objet.
local function fireProjectile(x: number, z: number, dirX: number, dirZ: number, speed: number, damage: number, radius: number, life: number, y: number?, style: number?)
	if pCount >= MAX_PROJECTILES then
		return
	end
	local d = math.sqrt(dirX * dirX + dirZ * dirZ)
	if d < 1e-4 then
		return
	end
	dirX, dirZ = dirX / d, dirZ / d
	local id = nextProjectileId
	nextProjectileId = nextProjectileId % MAX_ID + 1
	local py = y or (Heightmap.getY(x, z) + 2.5)
	pCount += 1
	local k = pCount
	pIds[k], pX[k], pY[k], pZ[k] = id, x, py, z
	pDX[k], pDZ[k], pSpeed[k], pDamage[k], pRadius[k] = dirX, dirZ, speed, damage, radius
	pEnd[k] = os.clock() + life
	table.insert(projSpawns, {
		id = id,
		x = x,
		y = py,
		z = z,
		angle = math.atan2(dirZ, dirX),
		speed = speed,
		life = life,
		radius = radius,
		t0 = Workspace:GetServerTimeNow(),
		style = style or 0,
	})
end

local function removeProjectile(k: number)
	local last = pCount
	if k ~= last then
		pIds[k], pX[k], pY[k], pZ[k] = pIds[last], pX[last], pY[last], pZ[last]
		pDX[k], pDZ[k], pSpeed[k], pDamage[k], pRadius[k], pEnd[k] =
			pDX[last], pDZ[last], pSpeed[last], pDamage[last], pRadius[last], pEnd[last]
	end
	pCount -= 1
end

local function stepProjectiles(targets: { Target }, now: number)
	local run = Registry.find("RunManager")
	local k = 1
	while k <= pCount do
		pX[k] += pDX[k] * pSpeed[k] * DT
		pZ[k] += pDZ[k] * pSpeed[k] * DT
		local hit: Player? = nil
		for _, t in targets do
			local dx, dz = t.x - pX[k], t.z - pZ[k]
			local r = pRadius[k] + Run.Player.ContactHalfWidth
			if dx * dx + dz * dz <= r * r and math.abs((t.y + 2.5) - pY[k]) < 4 then
				hit = t.player
				break
			end
		end
		if hit then
			if run then
				task.spawn(run.damagePlayer, hit, pDamage[k], "EnemyProjectile")
			end
			table.insert(projRemoved, pIds[k])
			removeProjectile(k)
		elseif now >= pEnd[k] then
			removeProjectile(k) -- the client expires it by itself
		else
			k += 1
		end
	end
	if #projSpawns > 0 or #projRemoved > 0 then
		projectileRemote:FireAllClients(Codec.encodeProjectiles(projSpawns, projRemoved))
		table.clear(projSpawns)
		table.clear(projRemoved)
	end
end

-- Comportements spéciaux (A03-04) -------------------------------------------------------------
-- Tout est en données : pas d'Instance par ennemi. Les signaux visuels passent par le remote
-- EnemyAttackVisual (modes "aura", "explode", "puddle" ; le client retombe sur Burst / Sweep tant
-- que les effets dédiés n'existent pas dans Assets.FX.Enemies).

-- Vol d'XP du Bomber. StatsService.takeXp(player, amount) -> number (XP réellement retirée, sans
-- jamais baisser le niveau) est une contract request au domaine combat : tant qu'il n'existe pas,
-- l'explosion blesse seulement. Une part de l'XP volée retombe en gemme un peu plus loin.
local function stealXp(player: Player, amount: number, dropFrac: number?, x: number, z: number)
	local stats = Registry.find("StatsService")
	local take = stats and (stats :: any).takeXp
	if type(take) ~= "function" then
		if not warnedNoTakeXp then
			warnedNoTakeXp = true
			warn("[EnemyService] StatsService.takeXp absent : le Bomber ne vole pas encore d'XP")
		end
		return
	end
	task.spawn(function()
		local ok, taken = pcall(take, player, amount)
		if not (ok and type(taken) == "number" and taken > 0 and taken == taken) then
			return
		end
		local frac = dropFrac or 0
		local loot = Registry.find("LootService")
		if frac > 0 and loot then
			local a = math.random() * math.pi * 2
			local gx, gz = clampToMap(x + math.cos(a) * 12, z + math.sin(a) * 12)
			pcall(loot.dropXp, gx, gz, taken * frac)
		end
	end)
end

-- Blesse les joueurs dans un disque au sol (explosion, surgissement), ou dans un anneau si inner > 0.
local function hitPlayers(targets: { Target }, x: number, z: number, radius: number, damage: number, source: string, steal: number?, dropFrac: number?, inner: number?)
	local run = Registry.find("RunManager")
	local groundY = Heightmap.getY(x, z)
	local reach = radius + Run.Player.ContactHalfWidth
	local hole = math.max(0, (inner or 0) - Run.Player.ContactHalfWidth)
	for _, t in targets do
		local dx, dz = t.x - x, t.z - z
		local d2 = dx * dx + dz * dz
		if d2 <= reach * reach and d2 >= hole * hole and math.abs(t.y - groundY) < 4 then
			if run then
				task.spawn(run.damagePlayer, t.player, damage, source)
			end
			if steal and steal > 0 then
				stealXp(t.player, steal, dropFrac, x, z)
			end
		end
	end
end

local function addPuddle(def: Enemies.Def, x: number, z: number, dmg: number)
	local r = def.puddleRadius
	if not r or puddleN >= MAX_PUDDLES then
		return
	end
	puddleN += 1
	local k = puddleN
	local now = os.clock()
	pdX[k], pdZ[k], pdY[k], pdR[k] = x, z, Heightmap.getY(x, z), r
	pdEnd[k] = now + (def.puddleTime or 5)
	pdNext[k] = now
	pdDps[k] = (def.puddleDps or 5) * dmg
	pdSlow[k] = def.puddleSlow or 1
	fireAttackCue(0, def.id, "puddle", x, pdY[k], z, 0, 0, r)
end

local function removePuddle(k: number)
	local last = puddleN
	if k ~= last then
		pdX[k], pdZ[k], pdY[k], pdR[k] = pdX[last], pdZ[last], pdY[last], pdR[last]
		pdEnd[k], pdNext[k], pdDps[k], pdSlow[k] = pdEnd[last], pdNext[last], pdDps[last], pdSlow[last]
	end
	puddleN -= 1
end

local function stepPuddles(targets: { Target }, now: number)
	if puddleN == 0 then
		return
	end
	local run = Registry.find("RunManager")
	local k = 1
	while k <= puddleN do
		if now >= pdEnd[k] then
			removePuddle(k)
			continue
		end
		if now >= pdNext[k] then
			pdNext[k] = now + PUDDLE_TICK
			local reach = pdR[k] + Run.Player.ContactHalfWidth
			for _, t in targets do
				local dx, dz = t.x - pdX[k], t.z - pdZ[k]
				if dx * dx + dz * dz <= reach * reach and math.abs(t.y - pdY[k]) < 3 and run then
					if pdDps[k] > 0 then
						task.spawn(run.damagePlayer, t.player, pdDps[k] * PUDDLE_TICK, "EnemyPuddle")
					end
					if pdSlow[k] < 1 then
						task.spawn(run.setSlow, t.player, pdSlow[k], PUDDLE_TICK + 0.3)
					end
				end
			end
		end
		k += 1
	end
end

-- Aura d'un soutien (Shaman : soin + hâte ; Surveillant : hâte + rassemblement ; Banshee : ralentit
-- les joueurs). Appelée au plus une fois toutes les auraEvery s par soutien.
local function castAura(i: number, def: Enemies.Def, targets: { Target }, now: number)
	local x, z = xs[i], zs[i]
	local r = def.auraRadius or 12
	EnemyService._attackVisual(ids[i], "aura", x, z, 0, 0, r)
	if def.auraHeal or def.auraHaste or def.auraRally then
		local heal = def.auraHeal or 0
		local haste = def.auraHaste or 1
		local hasteEnd = now + (def.auraHasteTime or 3)
		local chased = targetOf[i]
		local n = EnemyService.queryRadius(x, z, r, auraBuf)
		for k = 1, n do
			local j = indexOf[auraBuf[k]]
			if not j or external[j] then
				continue
			end
			if heal > 0 and Enemies[kinds[j]].family ~= "MiniBoss" then
				hps[j] = math.min(maxHps[j], hps[j] + maxHps[j] * heal)
			end
			if haste > 1 then
				hasteMult[j] = if hasteUntil[j] > now then math.max(hasteMult[j], haste) else haste
				hasteUntil[j] = math.max(hasteUntil[j], hasteEnd)
			end
			if def.auraRally and chased then
				targetOf[j] = chased
			end
		end
	end
	local slow = def.auraSlow
	if slow and slow < 1 then
		local run = Registry.find("RunManager")
		local groundY = Heightmap.getY(x, z)
		local reach = r + Run.Player.ContactHalfWidth
		for _, t in targets do
			local dx, dz = t.x - x, t.z - z
			if run and dx * dx + dz * dz <= reach * reach and math.abs(t.y - groundY) < 6 then
				task.spawn(run.setSlow, t.player, slow, def.auraSlowTime or 2.5)
			end
		end
	end
end

local function flushRemovals()
	for k = 1, removeN do
		local i = indexOf[pendingRemove[k]]
		if i then
			addPuddle(Enemies[kinds[i]], xs[i], zs[i], dmgMult[i])
			removeAt(i)
		end
	end
	removeN = 0
end

-- Simulation -------------------------------------------------------------------------------------

local function rebuildGrid()
	for k = 1, gridUsedN do
		local cell = grid[gridUsed[k]]
		if cell then
			table.clear(cell)
		end
	end
	gridUsedN = 0
	if simTick % GRID_PRUNE_TICKS == 0 then
		for key, cell in grid do
			if #cell == 0 then
				grid[key] = nil
			end
		end
	end
	for i = 1, count do
		if actPhase[i] == PHASE_BURROWED then
			continue -- sous terre : ni touché, ni poussé, ni compté au contact
		end
		local key = cellKey(xs[i] // CELL, zs[i] // CELL)
		local cell = grid[key]
		if not cell then
			cell = {}
			grid[key] = cell
		end
		local n = #cell
		if n == 0 then
			gridUsedN += 1
			gridUsed[gridUsedN] = key
		end
		cell[n + 1] = i
	end
end

local function weightOf(i: number): number
	if external[i] then
		return 1000
	end
	return Enemies[kinds[i]].weight or 1
end

-- Hard non-overlap constraint (position-based): every overlapping pair is pushed apart (split
-- by weight, so armored enemies shove the swarm), then enemies are pushed out of the player
-- they chase. A soft "steering" push loses against the walk of the outer ring and the crowd
-- collapses into one pile. Big entities (bosses) are checked from their own side with a wider
-- cell range.
local function relax(byPlayer: { [Player]: Target })
	for _ = 1, Balance.RelaxIterations do
		for i = 1, count do
			if actPhase[i] == PHASE_BURROWED then
				continue
			end
			local ri = radiusOf(i) + Balance.SeparationGap
			local wi = weightOf(i)
			local cx, cz = xs[i] // CELL, zs[i] // CELL
			local range = if ri > CELL / 2 then math.ceil((ri + 3) / CELL) else 1
			for ox = -range, range do
				for oz = -range, range do
					local cell = grid[cellKey(cx + ox, cz + oz)]
					if cell then
						for _, j in cell do
							if j > i and j <= count then
								local minD = ri + radiusOf(j)
								local dx, dz = xs[j] - xs[i], zs[j] - zs[i]
								local d2 = dx * dx + dz * dz
								if d2 < minD * minD then
									local d = math.sqrt(d2)
									if d < 1e-3 then
										local a = ids[i] * 2.39996
										dx, dz, d = math.cos(a), math.sin(a), 1
									end
									local wj = weightOf(j)
									local over = (minD - d) / d
									local si = wj / (wi + wj)
									local sj = wi / (wi + wj)
									xs[i] -= dx * over * si
									zs[i] -= dz * over * si
									xs[j] += dx * over * sj
									zs[j] += dz * over * sj
								end
							end
						end
					end
				end
			end
		end
	end

	-- The player is a solid circle: enemies stay outside it (airborne jumpers excepted).
	for i = 1, count do
		local chased = targetOf[i]
		local t = chased and byPlayer[chased]
		if t and actPhase[i] ~= PHASE_AIR and actPhase[i] ~= PHASE_BURROWED then
			local minD = Balance.ContactDistance + radiusOf(i)
			local dx, dz = xs[i] - t.x, zs[i] - t.z
			local d2 = dx * dx + dz * dz
			if d2 < minD * minD then
				local d = math.sqrt(d2)
				if d < 1e-3 then
					local a = ids[i] * 2.39996
					dx, dz, d = math.cos(a), math.sin(a), 1
				end
				xs[i] = t.x + dx / d * minD
				zs[i] = t.z + dz / d * minD
			end
		end
	end
end

local function queueDamage(id: number, amount: number, source: Player?)
	pendingN += 1
	pendingDamage[pendingN * 2 - 1] = id
	pendingDamage[pendingN * 2] = amount
	pendingSource[pendingN] = source
end

local function flushDamage()
	for k = 1, pendingN do
		EnemyService.damage(pendingDamage[k * 2 - 1], pendingDamage[k * 2], pendingSource[k])
		pendingSource[k] = nil
	end
	pendingN = 0
end

local function spawnTick(targets: { Target }, now: number)
	if not director.active or #targets == 0 then
		return
	end
	local n = #targets
	local elapsed = now - director.stageStart
	local want = desiredAlive(elapsed, n) - count
	local toSpawn = math.min(want, Balance.MaxSpawnsPerTick)
	if director.burstLeft > 0 then
		local extra = math.min(director.burstLeft, math.max(director.burstPerTick, 1), Balance.MaxEnemies - count)
		if extra > 0 then -- au plafond, la vague attend qu'une place se libère
			director.burstLeft -= extra
			toSpawn = math.max(toSpawn, 0) + extra
		end
	end
	for s = 1, toSpawn do
		local t = targets[(simTick + s) % n + 1] -- round robin: ~equal share per player
		local x, z = ringPoint(t)
		local elite = false
		local classicRoom = lootEliteAlive < Run.EliteMaxAlive
		local underCap = director.eliteMaxAlive == math.huge or lootEliteAlive < director.eliteMaxAlive
		if now >= director.nextEliteAt and underCap then
			elite = true
			director.nextEliteAt = now + Run.EliteEvery
		elseif elapsed >= Run.EliteFirstAt and math.random() < director.eliteShare and underCap then
			elite = true
		end
		local kind = pickKind(elapsed)
		if elite and kind == (Worlds[director.worldId] or Worlds[Run.DefaultWorld]).roster.Swarm and math.random() < 0.5 then
			kind = pickKind(math.huge)
		end
		spawnScaled(kind, x, z, elite, 1, elite and not classicRoom)
	end
end

local function step(targets: { Target }, now: number)
	if #targets == 0 then
		return
	end
	spawnTick(targets, now)

	rebuildGrid()
	table.clear(byPlayer)
	for _, t in targets do
		byPlayer[t.player] = t
	end
	local recycle2 = Balance.RecycleDistance * Balance.RecycleDistance

	for i = 1, count do
		local x, z = xs[i], zs[i]
		local def = Enemies[kinds[i]]

		-- Damage over time (applied after the loop: damage can remove entries)
		if now >= dotNext[i] and (burnUntil[i] > now or poisonUntil[i] > now) then
			dotNext[i] = now + DOT_INTERVAL
			if burnUntil[i] > now then
				queueDamage(ids[i], burnDps[i] * DOT_INTERVAL, burnSrc[i])
			end
			if poisonUntil[i] > now then
				queueDamage(ids[i], poisonDps[i] * DOT_INTERVAL, poisonSrc[i])
			end
		end

		local stopped = stopUntil[i] > now
		local st = states[i]
		st = if stopped then bit32.bor(st, BIT_STOPPED) else bit32.band(st, bit32.bnot(BIT_STOPPED))

		-- Knockback is applied even to stopped enemies
		if kbUntil[i] > now then
			xs[i] = x + kbVX[i] * DT
			zs[i] = z + kbVZ[i] * DT
			x, z = xs[i], zs[i]
		end

		if external[i] then
			states[i] = st
			continue
		end

		local chased = targetOf[i]
		local t = chased and byPlayer[chased]
		if not t or (i + simTick) % Balance.TargetRefreshTicks == 0 then
			t = nearest(targets, x, z)
			targetOf[i] = if t then t.player else nil
		end
		if not t then
			states[i] = st
			continue
		end

		local dx, dz = t.x - x, t.z - z
		local d2 = dx * dx + dz * dz
		if d2 > recycle2 and (actPhase[i] == 0 or actPhase[i] == PHASE_BURROWED) then
			xs[i], zs[i] = ringPoint(t)
			states[i] = st
			continue
		end

		if stopped then
			if actPhase[i] ~= 0 then
				actPhase[i] = 0
				actT[i] = now + 1
				st = bit32.band(st, bit32.bnot(BIT_ACTION))
			end
			states[i] = st
			continue
		end

		local speed = def.speed * (if slowUntil[i] > now then slowMult[i] else 1)
		speed *= worldScale().speed
		if hasteUntil[i] > now then
			speed *= hasteMult[i]
		end
		local d = math.sqrt(d2)
		local family = def.family
		local walk = true

		if actPhase[i] >= PHASE_BURROWED then
			-- Gravedigger : avance sous terre, surgit près du joueur (cercle annoncé), puis tire.
			walk = false
			if actPhase[i] == PHASE_BURROWED then
				if d <= (def.emergeRange or 9) then
					actPhase[i] = PHASE_EMERGING
					actT[i] = now + (def.emergeWindup or 0.7)
					st = bit32.bor(st, BIT_ACTION)
					EnemyService._attackVisual(ids[i], "aim", x, z, dx, dz, def.emergeRadius)
				elseif d > 1e-3 then
					local v = speed * (def.burrowSpeed or 1.4) * DT
					xs[i] = x + dx / d * v
					zs[i] = z + dz / d * v
				end
			elseif now >= actT[i] then
				actPhase[i] = 0
				actT[i] = now + 1
				st = bit32.band(st, bit32.bnot(BIT_ACTION))
				hitPlayers(targets, x, z, def.emergeRadius or 4, (def.emergeDamage or 10) * dmgMult[i], "EnemyEmerge")
				EnemyService._attackVisual(ids[i], "land", x, z, dx, dz, def.emergeRadius)
			end
		elseif family == "Jumper" or def.leapAir ~= nil then
			local phase = actPhase[i]
			if phase == 0 then
				if now >= actT[i] and d < (def.leapRange or 22) and d > 4 then
					actPhase[i] = 1
					actT[i] = now + (def.leapWindup or 0.4)
					actX[i], actZ[i] = t.x, t.z -- locked landing point
					EnemyService._attackVisual(ids[i], "aim", x, z, dx, dz)
					st = bit32.bor(st, BIT_ACTION)
					walk = false
				end
			elseif phase == 1 then
				walk = false
				if now >= actT[i] then
					actPhase[i] = 2
					actOX[i], actOZ[i] = x, z
					actT[i] = now + (def.leapAir or 0.8)
				end
			else
				walk = false
				local air = def.leapAir or 0.8
				local u = math.clamp(1 - (actT[i] - now) / air, 0, 1)
				xs[i] = actOX[i] + (actX[i] - actOX[i]) * u
				zs[i] = actOZ[i] + (actZ[i] - actOZ[i]) * u
				if u >= 1 then
					actPhase[i] = 0
					actT[i] = now + (def.leapCooldown or 3.5)
					EnemyService._attackVisual(ids[i], "land", xs[i], zs[i], actX[i] - actOX[i], actZ[i] - actOZ[i])
					st = bit32.band(st, bit32.bnot(BIT_ACTION))
				end
			end
		elseif family == "Shooter" then
			local keep = def.keepDistance or 26
			if actPhase[i] == 1 then
				walk = false
				if now >= actT[i] then
					actPhase[i] = 0
					actT[i] = now + (def.shotCooldown or 3.2) + math.random() * 0.5
					st = bit32.band(st, bit32.bnot(BIT_ACTION))
					local previousCount = pCount
					local shots = def.shotCount or 1
					local aim = math.atan2(t.z - z, t.x - x)
					local spread = math.rad(def.shotSpread or 0)
					for s = 1, shots do
						local a = if shots > 1 then aim - spread / 2 + (s - 1) / (shots - 1) * spread else aim
						fireProjectile(
							x,
							z,
							math.cos(a),
							math.sin(a),
							def.shotSpeed or 18,
							(def.shotDamage or 8) * dmgMult[i],
							def.shotRadius or 1.2,
							4,
							nil,
							Codec.packStyle(kinds[i])
						)
					end
					if pCount > previousCount then
						EnemyService._attackVisual(ids[i], "shot", x, z, dx, dz)
					end
				end
			elseif d <= (def.shotRange or 40) and now >= actT[i] then
				actPhase[i] = 1
				actT[i] = now + (def.shotWindup or 0.6)
				EnemyService._attackVisual(ids[i], "aim", x, z, dx, dz)
				st = bit32.bor(st, BIT_ACTION)
				walk = false
			elseif d < keep - 6 then
				-- Too close: back off slowly
				xs[i] = x - dx / d * speed * 0.5 * DT
				zs[i] = z - dz / d * speed * 0.5 * DT
				walk = false
			elseif d <= keep then
				walk = false
			end
		elseif family == "Support" then
			-- Shaman, Banshee, Surveillant : garde ses distances, lance son aura toutes les auraEvery s.
			walk = false
			local radius = def.auraRadius or 12
			if actPhase[i] == 1 then
				if now >= actT[i] then
					actPhase[i] = 0
					actT[i] = now + (def.auraEvery or 6)
					st = bit32.band(st, bit32.bnot(BIT_ACTION))
					castAura(i, def, targets, now)
				end
			elseif now >= actT[i] and (def.auraSlow == nil or d <= radius) then
				actPhase[i] = 1
				actT[i] = now + (def.auraWindup or 0.6)
				st = bit32.bor(st, BIT_ACTION)
				EnemyService._attackVisual(ids[i], "aim", x, z, dx, dz, radius)
			else
				local keep = def.keepDistance or 14
				if d < keep - 4 then
					xs[i] = x - dx / d * speed * 0.5 * DT
					zs[i] = z - dz / d * speed * 0.5 * DT
				elseif d > keep then
					walk = true
				end
			end
		elseif family == "Kamikaze" then
			-- Bomber, Bloater : fonce, allume sa mèche près du joueur, explose et disparaît.
			if actPhase[i] == 1 then
				walk = false
				if now >= actT[i] then
					actPhase[i] = 0
					actT[i] = math.huge -- n'explose qu'une fois (retiré après la boucle)
					local r = def.blastRadius or 5
					EnemyService._attackVisual(ids[i], "explode", x, z, 0, 0, r)
					hitPlayers(targets, x, z, r, (def.blastDamage or 15) * dmgMult[i], "EnemyBlast", def.xpSteal, def.xpStealDrop)
					removeN += 1
					pendingRemove[removeN] = ids[i]
				end
			elseif now >= actT[i] and d <= (def.fuseRange or 6) + radiusOf(i) and not capturable[i] then
				-- (une variante capturable n'explose pas : elle doit pouvoir finir en cage)
				actPhase[i] = 1
				actT[i] = now + (def.fuseTime or 1)
				st = bit32.bor(st, BIT_ACTION)
				EnemyService._attackVisual(ids[i], "aim", x, z, dx, dz, def.blastRadius or 5)
				walk = false
			end
		elseif def.slamShape then
			-- Mini-boss (contract request 5) : cercle devant lui, cercle centré ou anneau, annoncé
			-- slamWindup s avant (télégraphe client "slam"), puis impact ("boss").
			if actPhase[i] == 1 then
				walk = false
				if now >= actT[i] then
					actPhase[i] = 0
					actT[i] = now + (def.slamEvery or 8)
					st = bit32.band(st, bit32.bnot(BIT_ACTION))
					local r = def.slamRadius or 6
					local inner = if def.slamShape == "Ring" then def.slamInner else nil
					hitPlayers(targets, actX[i], actZ[i], r, (def.slamDamage or 20) * dmgMult[i], "EnemySlam", nil, nil, inner)
					EnemyService._attackVisual(ids[i], "boss", actX[i], actZ[i], actOX[i], actOZ[i], r)
				end
			elseif now >= actT[i] and d <= (def.slamRange or 10) + radiusOf(i) and d > 1e-3 then
				actPhase[i] = 1
				actT[i] = now + math.max(def.slamWindup or 1, 1) -- décisions v2 §6 : annoncé au moins 1 s avant
				st = bit32.bor(st, BIT_ACTION)
				walk = false
				local r = def.slamRadius or 6
				local ux, uz = dx / d, dz / d
				if def.slamShape == "Front" then
					actX[i], actZ[i] = clampToMap(x + ux * (radiusOf(i) + r * 0.6), z + uz * (radiusOf(i) + r * 0.6))
				else
					actX[i], actZ[i] = x, z
				end
				actOX[i], actOZ[i] = ux, uz
				local y = Heightmap.getY(actX[i], actZ[i])
				fireAttackCue(ids[i], kinds[i], "slam", actX[i], y, actZ[i], ux, uz, r)
			end
		end

		if walk then
			local stop = Balance.ContactDistance + radiusOf(i)
			if d > stop then
				xs[i] = x + dx / d * speed * DT
				zs[i] = z + dz / d * speed * DT
			end
		end
		states[i] = st
	end

	relax(byPlayer)
	for i = 1, count do
		xs[i], zs[i] = clampToMap(xs[i], zs[i])
	end
	stepProjectiles(targets, now)
	stepPuddles(targets, now)
	flushDamage()
	flushRemovals()
end

-- PERF-01 : qui part à ce tick, pour chaque client.
--   * à chaque tick : les SnapshotNearCount plus proches (seuil trouvé par un histogramme de
--     distances, sans tri), les boss, ceux qui agissent (préparation, saut, surgissement) et ceux dont
--     l'état vient de changer (2 ticks de suite, pour survivre à un paquet perdu) ;
--   * le reste à moins de InterestRadiusNear : un tick sur NearRestEveryNTicks ;
--   * jusqu'à InterestRadiusFar : un tick sur FarSendEveryNTicks.
-- Les cadences sont étalées par id (pas de pic un tick sur N). Le client interpole sur l'écart réel
-- entre deux échantillons. Les ids retirés partent dans le chunk 0 (liste removed d'EnemyCodec).
local BINS = 40
local binCount: { number } = table.create(BINS, 0)
local distBuf: { number } = {}
local sendRemoved: { number } = {}

local function send(viewers: { Player })
	local near = Balance.InterestRadiusNear
	local near2 = near * near
	local far2 = Balance.InterestRadiusFar ^ 2
	local binSize = near / BINS
	local wantNear = Balance.SnapshotNearCount
	local restEvery = Balance.NearRestEveryNTicks
	local farEvery = Balance.FarSendEveryNTicks

	-- Changements d'état (une fois pour tous les clients)
	for i = 1, count do
		if states[i] ~= stateSent[i] then
			stateSent[i] = states[i]
			stateChangedAt[i] = simTick
		end
	end

	-- Ids retirés depuis le dernier envoi (au plus MaxRemoved par tick, le reste attend)
	local nr = math.min(removedN, Codec.MaxRemoved)
	for k = 1, nr do
		sendRemoved[k] = removedQueue[k]
	end
	if removedN > nr then
		table.move(removedQueue, nr + 1, removedN, 1)
	end
	for k = removedN - nr + 1, removedN do
		removedQueue[k] = nil
	end
	removedN -= nr

	for _, player in viewers do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (root and root:IsA("BasePart")) then
			continue
		end
		local px, pz = root.Position.X, root.Position.Z

		-- 1. distances et histogramme (cases de binSize studs jusqu'à InterestRadiusNear)
		for b = 1, BINS do
			binCount[b] = 0
		end
		for i = 1, count do
			local dx, dz = xs[i] - px, zs[i] - pz
			local d2 = dx * dx + dz * dz
			distBuf[i] = d2
			if d2 <= near2 then
				local b = math.min(BINS, math.floor(math.sqrt(d2) / binSize) + 1)
				binCount[b] += 1
			end
		end
		local every2 = near2 -- sous ce seuil : envoyé à chaque tick
		local acc = 0
		for b = 1, BINS do
			acc += binCount[b]
			if acc >= wantNear then
				every2 = (b * binSize) ^ 2
				break
			end
		end

		-- 2. sélection
		local n = 0
		for i = 1, count do
			local isExternal = external[i]
			if actPhase[i] == PHASE_BURROWED and not isExternal then
				continue -- sous terre : invisible jusqu'à ce qu'il surgisse
			end
			local d2 = distBuf[i]
			local go
			if isExternal then
				go = true
			elseif d2 <= near2 then
				go = d2 <= every2
					or actPhase[i] ~= 0
					or simTick - stateChangedAt[i] <= 1
					or (ids[i] + simTick) % restEvery == 0
			elseif d2 <= far2 then
				go = (ids[i] + simTick) % farEvery == 0
			else
				go = false
			end
			if go then
				n += 1
				sendIds[n] = ids[i]
				sendXs[n] = xs[i]
				sendZs[n] = zs[i]
				sendFlags[n] = Codec.packFlags(kinds[i], states[i])
			end
		end
		for _, chunk in Codec.encode(simTick, sendIds, sendXs, sendZs, sendFlags, n, sendRemoved, nr) do
			snapshot:FireClient(player, chunk)
		end
	end
end

-- Public API (ARCHITECTURE section 4) ---------------------------------------------------------

-- Applies damage on the server. Returns true if the enemy died (fires Bus.EnemyKilled).
-- state bit 1 (value 1) = elite, 2 = action (leap / shot windup), 4 = frozen or stunned.
function EnemyService.damage(id: number, amount: number, source: Player?): boolean
	local i = indexOf[id]
	if not i or type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return false
	end
	local def = Enemies[kinds[i]]
	if external[i] then
		local bossService = Registry.find("BossService")
		if bossService and bossService._modifyDamage then
			amount = bossService._modifyDamage(id, amount, source)
		end
	elseif def.armor then
		amount *= 1 - def.armor
	end
	if def.coinsPerHit then
		local now = os.clock()
		if now - (coinTimes[id] or 0) >= 0.3 then
			coinTimes[id] = now
			local loot = Registry.find("LootService")
			if loot then
				task.spawn(loot.dropCoins, xs[i], zs[i], 1)
			end
		end
	end
	hps[i] -= amount
	if hps[i] <= 0 then
		local kind, x, z = kinds[i], xs[i], zs[i]
		-- isElite = élite à butin (coffre). hordeElite = élite de l'Overtime au-delà du plafond
		-- classique : PV, taille et couronne d'élite, XP et quêtes d'élite côté domaines qui le lisent,
		-- mais pas de coffre (contract request loot : XP / pièces d'élite pour isElite or hordeElite).
		local isElite = lootElite[i]
		local hordeElite = not isElite and bit32.band(states[i], BIT_ELITE) ~= 0 and not external[i]
		if def.puddleRadius and not external[i] then
			addPuddle(def, x, z, dmgMult[i]) -- Bloater : nappe laissée à sa mort
		end
		local wasCapturable = capturable[i]
		removeAt(i)
		Bus.EnemyKilled:fire(id, kind, x, z, source, isElite, hordeElite)
		if wasCapturable then
			-- Battue sous les coups : la cage (A05, dossier 40 §6.1). Jamais sur clearAll, dépop, explosion.
			local companions = Registry.find("CompanionService")
			local onDefeated = companions and (companions :: any).onCapturableDefeated
			if type(onDefeated) == "function" then
				pcall(onDefeated, kind, x, z, source)
			end
		end
		return true
	end
	return false
end

function EnemyService.getPosition(id: number): (number?, number?)
	local i = indexOf[id]
	if not i then
		return nil, nil
	end
	return xs[i], zs[i]
end

function EnemyService.isAlive(id: number): boolean
	return indexOf[id] ~= nil
end

-- True for a live elite (state bit 1). Used by the Hunter Glasses item (integration fix).
function EnemyService.isElite(id: number): boolean
	local i = indexOf[id]
	return i ~= nil and bit32.band(states[i], BIT_ELITE) ~= 0
end

-- Ids of enemies within radius. Uses the grid from the last tick, then re-checks the real
-- position, so results are always correct but may miss an enemy that died and was swapped.
-- Ordinary enemies are matched by their centre: only the cells that touch the query square are
-- read (PERF-03 : a radius-1 query reads 1 to 4 cells instead of 25). Large entities (bosses) are
-- matched by their edge, from their own short list, never through the grid.
function EnemyService.queryRadius(x: number, z: number, radius: number, out: { number }): number
	if type(radius) ~= "number" or radius ~= radius or radius < 0 then
		return 0
	end
	local n = 0
	local r2 = radius * radius
	local x0, x1 = (x - radius) // CELL, (x + radius) // CELL
	local z0, z1 = (z - radius) // CELL, (z + radius) // CELL
	for cx = x0, x1 do
		for cz = z0, z1 do
			local cell = grid[cellKey(cx, cz)]
			if cell then
				for _, i in cell do
					if i <= count and not external[i] then
						local dx, dz = xs[i] - x, zs[i] - z
						if dx * dx + dz * dz <= r2 then
							n += 1
							out[n] = ids[i]
						end
					end
				end
			end
		end
	end
	for _, id in externalIds do
		local i = indexOf[id]
		if i then
			local reach = radius + radiusOf(i)
			local dx, dz = xs[i] - x, zs[i] - z
			if dx * dx + dz * dz <= reach * reach then
				n += 1
				out[n] = id
			end
		end
	end
	return n
end

function EnemyService.getCount(): number
	return count
end

-- Au plafond technique, retire l'ennemi ordinaire (ni élite, ni boss) le plus loin de tout joueur,
-- sans butin ni KO, pour laisser passer une apparition voulue (mini-boss, invocation, autel).
local function makeRoom(): boolean
	if count < Balance.MaxEnemies then
		return true
	end
	local px: { number }, pz: { number } = {}, {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			table.insert(px, root.Position.X)
			table.insert(pz, root.Position.Z)
		end
	end
	-- 1er choix : ennemi ordinaire ; sinon (Overtime très avancé) une élite sans butin.
	local best, bestD2, bestRank = 0, -1, 0
	for i = 1, count do
		if external[i] or lootElite[i] then
			continue
		end
		local rank = if bit32.band(states[i], BIT_ELITE) == 0 then 2 else 1
		if rank < bestRank then
			continue
		end
		local nearest2 = math.huge
		for k = 1, #px do
			local dx, dz = xs[i] - px[k], zs[i] - pz[k]
			nearest2 = math.min(nearest2, dx * dx + dz * dz)
		end
		if rank > bestRank or nearest2 > bestD2 then
			best, bestD2, bestRank = i, nearest2, rank
		end
	end
	if best == 0 then
		return false
	end
	removeAt(best)
	return true
end

-- Spawns one enemy with the run's tier/stage/coop scaling. opts.hpMult multiplies on top.
-- Apparition voulue : jamais perdue au plafond technique (makeRoom).
function EnemyService.spawnAt(kind: number, x: number, z: number, opts: { elite: boolean?, hpMult: number? }?): number?
	if type(kind) ~= "number" or not Enemies[kind] or Enemies[kind].isBoss then
		return nil
	end
	if type(x) ~= "number" or type(z) ~= "number" or x ~= x or z ~= z then
		return nil
	end
	local elite = opts ~= nil and opts.elite == true
	local hpMult = if opts and type(opts.hpMult) == "number" and opts.hpMult > 0 then opts.hpMult else 1
	if not makeRoom() then
		return nil
	end
	return spawnScaled(kind, x, z, elite, hpMult)
end

function EnemyService.applyStatus(id: number, status: string, params: { [string]: any })
	local i = indexOf[id]
	if not i or type(params) ~= "table" then
		return
	end
	local now = os.clock()
	local def = Enemies[kinds[i]]
	local function num(key: string, default: number): number
		local v = params[key]
		return if type(v) == "number" and v == v then v else default
	end
	local src = params.source
	local source: Player? = if typeof(src) == "Instance" and src:IsA("Player") then src else nil
	local duration = math.clamp(num("duration", 1), 0, 30)
	if status == "Burn" then
		local dps = math.max(0, num("dps", 0))
		if burnUntil[i] <= now or dps >= burnDps[i] then
			burnDps[i] = dps
			burnSrc[i] = source
		end
		burnUntil[i] = math.max(burnUntil[i], now + duration)
	elseif status == "Poison" then
		local dps = math.max(0, num("dps", 0))
		local current = if poisonUntil[i] > now then poisonDps[i] else 0
		poisonDps[i] = math.min(current + dps, math.max(dps * 5, current))
		poisonUntil[i] = now + duration
		poisonSrc[i] = source
	elseif status == "Slow" then
		local mult = math.clamp(num("mult", 0.5), 0, 1)
		if slowUntil[i] <= now or mult <= slowMult[i] then
			slowMult[i] = mult
		end
		slowUntil[i] = math.max(slowUntil[i], now + duration)
	elseif status == "Freeze" or status == "Stun" then
		if external[i] then
			local bossService = Registry.find("BossService")
			local mult = if bossService and bossService._controlMult then bossService._controlMult() else 0.25
			duration *= mult
		end
		stopUntil[i] = math.max(stopUntil[i], now + duration)
	elseif status == "Knockback" then
		local mult = def.knockbackMult or 1
		local force = math.clamp(num("force", 6), 0, 60) * mult
		if force <= 0 then
			return
		end
		local dx, dz
		if type(params.dirX) == "number" and type(params.dirZ) == "number" then
			dx, dz = params.dirX, params.dirZ
		else
			dx, dz = xs[i] - num("fromX", xs[i]), zs[i] - num("fromZ", zs[i])
		end
		local d = math.sqrt(dx * dx + dz * dz)
		if d < 1e-4 or d ~= d then
			return
		end
		kbVX[i] = dx / d * force / KNOCKBACK_TIME
		kbVZ[i] = dz / d * force / KNOCKBACK_TIME
		kbUntil[i] = now + KNOCKBACK_TIME
	end
end

-- Run-domain internals (RunManager, BossService) -----------------------------------------------

-- Contact info for RunManager's 15 Hz contact check.
function EnemyService._contactInfo(id: number): (number?, number, number, boolean)
	local i = indexOf[id]
	if not i then
		return nil, 0, 0, false
	end
	local def = Enemies[kinds[i]]
	local harmless = actPhase[i] >= PHASE_AIR or stopUntil[i] > os.clock() -- en l'air, sous terre, surgit
	return radiusOf(i), def.height * sizeMult[i], def.contactDamage * dmgMult[i], harmless
end

function EnemyService._getKind(id: number): number?
	local i = indexOf[id]
	return if i then kinds[i] else nil
end

-- Stage director (RunManager).
function EnemyService.beginStage(worldId: string, tier: number, stage: number)
	EnemyService.clearAll()
	local layout = Heightmap.getLayout()
	halfSize = if layout then layout.size / 2 else 1e6
	director.active = true
	director.worldId = worldId
	director.tier = tier
	director.stage = stage
	director.stageStart = os.clock()
	director.densityMult = 1
	director.hpMult = 1
	director.damageMult = 1
	director.eliteShare = Run.EliteChance
	director.eliteMaxAlive = Run.EliteMaxAlive
	director.overflowMult = 1
	director.nextEliteAt = os.clock() + Run.EliteFirstAt
	director.burstLeft = 0
end

-- Réglé par RunManager. Les champs absents gardent leur valeur.
function EnemyService.setDirector(opts: { active: boolean?, densityMult: number?, hpMult: number?, damageMult: number?, eliteShare: number?, eliteMaxAlive: number? })
	if opts.active ~= nil then
		director.active = opts.active
	end
	director.densityMult = opts.densityMult or director.densityMult
	director.hpMult = opts.hpMult or director.hpMult
	director.damageMult = opts.damageMult or director.damageMult
	director.eliteShare = opts.eliteShare or director.eliteShare
	director.eliteMaxAlive = opts.eliteMaxAlive or director.eliteMaxAlive
end

-- Lecture du directeur (debug, HUD de test) : multiplicateur d'excès au plafond.
function EnemyService.getOverflowMult(): number
	return director.overflowMult
end

-- Wave: `size` extra enemies spread over `seconds` (still under the 300 cap).
function EnemyService.burst(size: number, seconds: number)
	director.burstLeft += size
	director.burstPerTick = math.ceil(director.burstLeft / math.max(1, seconds * Balance.SimHz))
end

function EnemyService.forceEliteSoon()
	director.nextEliteAt = os.clock()
end

function EnemyService.clearAll()
	while count > 0 do
		removeAt(count)
	end
	pCount = 0
	puddleN = 0
	removeN = 0
	table.clear(grid)
	gridUsedN = 0
	director.active = false
end

-- Removes every non-boss enemy without loot (stage transitions).
function EnemyService.clearNonBoss()
	puddleN = 0
	removeN = 0
	local i = 1
	while i <= count do
		if external[i] then
			i += 1
		else
			removeAt(i)
		end
	end
end

-- Commandes de test Studio (RunManager) : avance l'horloge du directeur avec le chrono de la run.
function EnemyService._debugSkip(seconds: number)
	director.stageStart -= seconds
end

function EnemyService._elapsed(): number
	return os.clock() - director.stageStart
end

-- Boss entity: not capped, not moved by the AI.
function EnemyService._spawnBoss(kind: number, x: number, z: number, hp: number): number?
	return insertEnemy(kind, x, z, hp, scaledDamage(), false, true)
end

-- Removes one entity without loot or EnemyKilled (boss despawn).
function EnemyService._remove(id: number)
	local i = indexOf[id]
	if i then
		removeAt(i)
	end
end

function EnemyService._setPosition(id: number, x: number, z: number)
	local i = indexOf[id]
	if i then
		xs[i], zs[i] = clampToMap(x, z)
	end
end

function EnemyService._getHp(id: number): number?
	local i = indexOf[id]
	return if i then hps[i] else nil
end

function EnemyService._isStopped(id: number): boolean
	local i = indexOf[id]
	return i ~= nil and stopUntil[i] > os.clock()
end

function EnemyService._stop(id: number, seconds: number)
	local i = indexOf[id]
	if i then
		stopUntil[i] = math.max(stopUntil[i], os.clock() + seconds)
	end
end

-- style : EnemyCodec.packStyle(kind du boss, rang de l'attaque) pour que le client choisisse l'objet.
function EnemyService._fireProjectile(x: number, z: number, dirX: number, dirZ: number, speed: number, damage: number, radius: number, life: number, y: number?, style: number?)
	fireProjectile(x, z, dirX, dirZ, speed, damage, radius, life, y, style)
end

function EnemyService._damageScale(): number
	return scaledDamage()
end

function EnemyService._hpScale(): number
	return scaledHp()
end

function EnemyService.init()
	snapshot = Net.unreliable("EnemySnapshot")
	projectileRemote = Net.event("EnemyProjectiles")
	attackVisualRemote = Net.unreliable("EnemyAttackVisual")
	capturableRemote = Net.event("EnemyCapturable")
end

-- Vrai pour une variante capturable vivante (A03-03). Lecture serveur, pour CompanionService.
function EnemyService.isCapturable(id: number): boolean
	local i = indexOf[id]
	return i ~= nil and capturable[i] == true
end

function EnemyService.start()
	-- Standalone test (no RunManager): behave like Phase 0.
	if not Registry.find("RunManager") then
		EnemyService.beginStage(Run.DefaultWorld, 1, 1)
	end
	Players.PlayerAdded:Connect(function(player)
		for i = 1, count do
			if capturable[i] then
				capturableRemote:FireClient(player, ids[i], true)
			end
		end
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < DT then
			return
		end
		acc = math.min(acc - DT, DT) -- never run more than one catch-up tick
		simTick += 1
		cachedPlayers = countRunPlayers()
		local targets, viewers = gatherTargets()
		step(targets, os.clock())
		send(viewers)
	end)
end

return EnemyService
