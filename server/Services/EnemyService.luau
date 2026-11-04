--!strict
-- Enemies as data, not Humanoids (doc 12.2, dossier 20 section 4).
-- Struct-of-arrays, dense indices 1..count, swap-remove on death.
-- 15 Hz: family AI (swarm / jumper / shooter / armored) + hard non-overlap relax through a
-- spatial grid, then each client gets only the enemies around it, in chunks of <= 900 bytes
-- over an UnreliableRemoteEvent. Enemy projectiles are simulated here as points and sent once
-- at creation (closed-form replay on the client, vault "Projectiles and Ballistics").
-- Bosses are entities here too (so weapons hit them) but BossService drives them ("external").
-- Run v2 (A04-02) : la force vient de Config/Run.WorldScaling (index du monde = director.stage) et
-- du directeur réglé par RunManager (Overtime : densité, PV, dégâts, part d'élites). Au-delà du
-- plafond technique Balance.MaxEnemies, l'excès de densité devient des PV (Run.Overtime.OverflowToHp).

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

local columns: { { any } } = {
	ids, xs, zs, hps, kinds, states, targetOf :: any, dmgMult, sizeMult, external, lootElite,
	actPhase, actT, actX, actZ, actOX, actOZ,
	burnDps, burnUntil, burnSrc :: any, poisonDps, poisonUntil, poisonSrc :: any, dotNext,
	slowMult, slowUntil, stopUntil, kbVX, kbVZ, kbUntil,
}

local indexOf: { [number]: number } = {} -- id -> index
local lootEliteAlive = 0 -- élites à butin vivantes, hors mini-boss (plafond Run.EliteMaxAlive)
local coinTimes: { [number]: number } = {}

local nextId = 1
local simTick = 0
local grid: { [number]: { number } } = {}
local snapshot: UnreliableRemoteEvent
local projectileRemote: RemoteEvent

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
	actPhase[i] = 0
	actT[i] = os.clock() + math.random() * 2
	actX[i], actZ[i], actOX[i], actOZ[i] = 0, 0, 0, 0
	burnDps[i], burnUntil[i], burnSrc[i] = 0, 0, nil
	poisonDps[i], poisonUntil[i], poisonSrc[i] = 0, 0, nil
	dotNext[i] = 0
	slowMult[i], slowUntil[i], stopUntil[i] = 1, 0, 0
	kbVX[i], kbVZ[i], kbUntil[i] = 0, 0, 0
	indexOf[id] = i
	return id
end

local function removeAt(i: number)
	if countsTowardEliteCap(i) then
		lootEliteAlive -= 1
	end
	indexOf[ids[i]] = nil
	coinTimes[ids[i]] = nil
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

local function gatherTargets(): ({ Target }, { Player })
	local list: { Target } = {}
	local viewers: { Player } = {}
	local run = Registry.find("RunManager")
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			table.insert(viewers, player)
			local active = true
			if run then
				local ok, result = pcall(run.isActive, player)
				active = ok and result == true
			end
			if active then
				local p = root.Position
				table.insert(list, { player = player, x = p.X, y = p.Y - 3, z = p.Z })
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
local function desiredAlive(elapsed: number, n: number): number
	local forced = Balance.Debug.ForceAlive
	if forced then
		director.overflowMult = 1
		return math.min(forced, Balance.MaxEnemies)
	end
	local scaled = curveAt(elapsed)
		* worldScale().density
		* director.densityMult
		* (1 + Balance.DensityPerExtraPlayer * (n - 1))
	director.overflowMult = math.max(1, scaled / Balance.MaxEnemies)
	return math.min(math.floor(scaled), Balance.MaxEnemies)
end

local function pickKind(elapsed: number): number
	local world = Worlds[director.worldId] or Worlds[Run.DefaultWorld]
	if math.random() < Balance.SwarmShare then
		return world.roster.Swarm
	end
	local options: { number } = {}
	for _, family in { "Jumper", "Shooter", "Armored" } do
		if elapsed >= Run.FamilyUnlock[family] * director.familyUnlockScale then
			table.insert(options, (world.roster :: any)[family])
		end
	end
	if #options == 0 then
		return world.roster.Swarm
	end
	return options[math.random(#options)]
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
	local dmg = scaledDamage() * (if elite then Run.Player.EliteDamageMult else 1)
	return insertEnemy(kind, x, z, hp, dmg, elite, false, noLoot)
end

-- Projectiles ----------------------------------------------------------------------------------

local function fireProjectile(x: number, z: number, dirX: number, dirZ: number, speed: number, damage: number, radius: number, life: number, y: number?)
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
	local world = Worlds[director.worldId] or Worlds[Run.DefaultWorld]
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
		color = world.projectile,
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

-- Simulation -------------------------------------------------------------------------------------

local function rebuildGrid()
	table.clear(grid)
	for i = 1, count do
		local key = cellKey(xs[i] // CELL, zs[i] // CELL)
		local cell = grid[key]
		if cell then
			table.insert(cell, i)
		else
			grid[key] = { i }
		end
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
		if t and actPhase[i] ~= 2 then
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
		director.burstLeft -= math.max(extra, 1)
		toSpawn = math.max(toSpawn, 0) + math.max(extra, 0)
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
	local byPlayer: { [Player]: Target } = {}
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
		if d2 > recycle2 and actPhase[i] == 0 then
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
		local d = math.sqrt(d2)
		local family = def.family
		local walk = true

		if family == "Jumper" then
			local phase = actPhase[i]
			if phase == 0 then
				if now >= actT[i] and d < (def.leapRange or 22) and d > 4 then
					actPhase[i] = 1
					actT[i] = now + (def.leapWindup or 0.4)
					actX[i], actZ[i] = t.x, t.z -- locked landing point
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
					fireProjectile(
						x,
						z,
						t.x - x,
						t.z - z,
						def.shotSpeed or 18,
						(def.shotDamage or 8) * dmgMult[i],
						def.shotRadius or 1.2,
						4
					)
				end
			elseif d <= (def.shotRange or 40) and now >= actT[i] then
				actPhase[i] = 1
				actT[i] = now + (def.shotWindup or 0.6)
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
	flushDamage()
end

local function send(viewers: { Player })
	local near2 = Balance.InterestRadiusNear ^ 2
	local far2 = Balance.InterestRadiusFar ^ 2
	local farTick = simTick % Balance.FarSendEveryNTicks == 0
	for _, player in viewers do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (root and root:IsA("BasePart")) then
			continue
		end
		local px, pz = root.Position.X, root.Position.Z
		local n = 0
		for i = 1, count do
			local dx, dz = xs[i] - px, zs[i] - pz
			local d2 = dx * dx + dz * dz
			if d2 <= near2 or (farTick and d2 <= far2) or external[i] then
				n += 1
				sendIds[n] = ids[i]
				sendXs[n] = xs[i]
				sendZs[n] = zs[i]
				sendFlags[n] = Codec.packFlags(kinds[i], states[i])
			end
		end
		for _, chunk in Codec.encode(simTick, sendIds, sendXs, sendZs, sendFlags, n) do
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
		local isElite = lootElite[i] -- élite à butin (voir lootElite)
		removeAt(i)
		Bus.EnemyKilled:fire(id, kind, x, z, source, isElite)
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
-- Large entities (bosses) are matched by their edge, not their centre.
function EnemyService.queryRadius(x: number, z: number, radius: number, out: { number }): number
	local n = 0
	local cells = math.ceil((radius + 8) / CELL)
	local cx, cz = x // CELL, z // CELL
	for ox = -cells, cells do
		for oz = -cells, cells do
			local cell = grid[cellKey(cx + ox, cz + oz)]
			if cell then
				for _, i in cell do
					if i <= count then
						local reach = radius + (if external[i] then radiusOf(i) else 0)
						local dx, dz = xs[i] - x, zs[i] - z
						if dx * dx + dz * dz <= reach * reach then
							n += 1
							out[n] = ids[i]
						end
					end
				end
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
	local best, bestD2 = 0, -1
	for i = 1, count do
		if not external[i] and bit32.band(states[i], BIT_ELITE) == 0 then
			local nearest2 = math.huge
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					local dx, dz = xs[i] - root.Position.X, zs[i] - root.Position.Z
					nearest2 = math.min(nearest2, dx * dx + dz * dz)
				end
			end
			if nearest2 > bestD2 then
				best, bestD2 = i, nearest2
			end
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
	local harmless = actPhase[i] == 2 or stopUntil[i] > os.clock()
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
	table.clear(grid)
	director.active = false
end

-- Removes every non-boss enemy without loot (stage transitions).
function EnemyService.clearNonBoss()
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

function EnemyService._fireProjectile(x: number, z: number, dirX: number, dirZ: number, speed: number, damage: number, radius: number, life: number, y: number?)
	fireProjectile(x, z, dirX, dirZ, speed, damage, radius, life, y)
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
end

function EnemyService.start()
	-- Standalone test (no RunManager): behave like Phase 0.
	if not Registry.find("RunManager") then
		EnemyService.beginStage(Run.DefaultWorld, 1, 1)
	end
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
