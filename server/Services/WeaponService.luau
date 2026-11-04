--!strict
-- Server auto-fire for the 16 weapons and their fusions (dossier 10, sections 2, 5, 10; doc 12.3).
-- Projectiles and zones are data (pooled records, no Parts), stepped at Balance.SimHz.
-- Targets via EnemyService.queryRadius, damage via EnemyService.damage(id, amount, player),
-- statuses via EnemyService.applyStatus. Visuals: compact events on WeaponFx (WeaponFxCodec).
-- Combat-internal API for PassiveService: getMotion, dealDamage, knockArea, spawnGhost, pushFx,
-- getPoisoner, markPoison, resetPlayer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Items = require(Config:WaitForChild("Items"))
local Weapons = require(Config:WaitForChild("Weapons"))
local FxCodec = require(Shared:WaitForChild("WeaponFxCodec"))
local Net = require(Shared:WaitForChild("Net"))
local Registry = require(Shared:WaitForChild("Registry"))
local Bus = require(script.Parent.Parent:WaitForChild("Bus"))

local DT = 1 / Balance.SimHz
local SIM = Weapons.Sim
local PAD = SIM.EnemyPad
local KIND = FxCodec.Kind
local FX_RADIUS = 160
local FX_MAX_PER_PLAYER = FxCodec.PerChunk * 2
local ATTACH_REFRESH = 4 -- permanent zones re-send their attach event this often (unreliable)

type Stats = { [string]: number }

-- Damage spec, one per (player, weapon), refreshed at each fire.
type Spec = {
	key: string, -- damageByWeapon key
	visual: number,
	damage: number, -- before crit
	critChance: number,
	critMult: number,
	knockback: number,
	status: string?,
	statusDps: number,
	statusDuration: number,
	statusMult: number,
	maxStacks: number,
	lifesteal: number,
	lifestealCap: number,
	chainOnCrit: number,
	xpOnKill: number,
	popRadius: number,
}

type PState = {
	player: Player,
	slot: number,
	x: number,
	z: number,
	lookX: number,
	lookZ: number,
	speed: number,
	airborne: boolean,
	moving: boolean,
	active: boolean,
	hasRoot: boolean,
	cooldowns: { [string]: number },
	specs: { [string]: Spec },
	shieldCharges: number,
	shieldTimer: number,
	healBudget: number, -- lifesteal / lollipop HP per second left
}

type Proj = {
	ps: PState,
	spec: Spec,
	fxId: number,
	mode: number, -- 1 straight, 2 boomerang, 3 homing
	x: number,
	z: number,
	vx: number,
	vz: number,
	speed: number,
	age: number,
	life: number,
	outTime: number,
	returning: boolean,
	radius: number,
	pierce: number, -- remaining, -1 = infinite
	hits: { number },
	targetId: number,
	split: number,
}

type Zone = {
	kind: string, -- Turret | Orbit | Cloud | Beam | Delayed
	ps: PState,
	spec: Spec,
	weaponId: string,
	follow: boolean,
	ox: number, -- offset from owner when following
	oz: number,
	x: number,
	z: number,
	age: number,
	life: number, -- math.huge = permanent
	timer: number,
	interval: number,
	radius: number,
	count: number,
	spin: number,
	orbitRadius: number,
	range: number,
	speed: number,
	pierce: number,
	projLife: number,
	angle: number, -- spread for turret darts
	cluster: number,
	clusterDamage: number,
	refresh: number,
	hitTimes: { [number]: number },
	dead: boolean,
}

local WeaponService = {}

local fxRemote: UnreliableRemoteEvent
local rng = Random.new()
local simTick = 0
local clock = 0

local pstates: { [Player]: PState } = {}
local slots: { [number]: Player } = {}

local projs: { Proj } = {}
local projCount = 0
local projFree: { Proj } = {}
local nextFxId = 0

local zones: { Zone } = {}

-- delayed fires (volleys, extra waves)
type Pending = { at: number, ps: PState, weaponId: string, n: number, dirX: number, dirZ: number }
local pending: { Pending } = {}

local fxQueue = FxCodec.newQueue()
local fxIdx: { number } = {}

-- reused query buffers
local qbuf: { number } = {}
local qbuf2: { number } = {}
local chainHits: { number } = {}

local hitsThisTick = 0

-- Poison tracking for Sporelin's Contagion
local poisonUntil: { [number]: number } = {}
local poisonOwner: { [number]: Player } = {}

-- Helpers ---------------------------------------------------------------------------------

local function enemyService(): any
	return Registry.get("EnemyService")
end

local function statsService(): any
	return Registry.get("StatsService")
end

local function pushFx(kind: number, visual: number, scale: number, a: number, x: number, z: number, p1: number, p2: number, p3: number, p4: number)
	if fxQueue.n >= 2000 then
		return
	end
	FxCodec.push(fxQueue, kind, visual, scale, a, x, z, p1, p2, p3, p4)
end

local function areaFx(visual: number, x: number, z: number, radius: number, dirAngle: number, halfDeg: number, delay: number)
	pushFx(KIND.Area, visual, 1, 0, x, z, radius * FxCodec.Scale, dirAngle * 100, halfDeg, delay * 10)
end

local function nearestEnemy(x: number, z: number, range: number, skip: { number }?): (number?, number, number)
	local es = enemyService()
	local n = es.queryRadius(x, z, range, qbuf)
	local best: number? = nil
	local bx, bz = 0, 0
	local bestD2 = math.huge
	for i = 1, n do
		local id = qbuf[i]
		if skip and table.find(skip, id) then
			continue
		end
		local ex, ez = es.getPosition(id)
		if ex and ez then
			local dx, dz = ex - x, ez - z
			local d2 = dx * dx + dz * dz
			if d2 < bestD2 then
				bestD2, best, bx, bz = d2, id, ex, ez
			end
		end
	end
	return best, bx, bz
end

local function randomEnemy(x: number, z: number, range: number): (number?, number, number)
	local es = enemyService()
	local n = es.queryRadius(x, z, range, qbuf)
	if n == 0 then
		return nil, 0, 0
	end
	local id = qbuf[rng:NextInteger(1, n)]
	local ex, ez = es.getPosition(id)
	if not ex or not ez then
		return nil, 0, 0
	end
	return id, ex, ez
end

local function applyStatus(id: number, status: string, params: { [string]: any })
	local es = enemyService()
	local fn = es.applyStatus
	if fn then
		fn(id, status, params)
	end
end

local function heal(ps: PState, amount: number)
	if amount <= 0 then
		return
	end
	local run = Registry.find("RunManager")
	if run and run.healPlayer then
		run.healPlayer(ps.player, amount)
	end
end

-- Context bonus (additive bucket) from PassiveService (air, ram stacks, moving/still items)
local function contextBonus(player: Player): number
	local passive = Registry.find("PassiveService")
	if passive and passive.getDamageBonus then
		return passive.getDamageBonus(player)
	end
	return 0
end

-- Damage ------------------------------------------------------------------------------------

local function onKill(ps: PState, spec: Spec, x: number, z: number)
	local stats = statsService()
	local player = ps.player
	local lolli = stats.getItemCount(player, "RainbowLollipop")
	if lolli > 0 and ps.healBudget > 0 then
		local eff = Items.Defs.RainbowLollipop.effect :: any
		local amount = math.min(eff.amount * lolli, ps.healBudget)
		ps.healBudget -= amount
		heal(ps, amount)
	end
	local coin = stats.getItemCount(player, "LuckyCoin")
	if coin > 0 then
		local eff = Items.Defs.LuckyCoin.effect :: any
		if rng:NextNumber() < eff.chance * coin then
			local loot = Registry.find("LootService")
			if loot and loot.dropCoins then
				loot.dropCoins(x, z, eff.coins)
			end
		end
	end
	if spec.xpOnKill > 0 then
		stats.addXp(player, spec.xpOnKill)
	end
end

local hitEnemy: (ps: PState, spec: Spec, id: number, fromX: number, fromZ: number, chained: boolean?) -> boolean

-- Applies one hit. Returns true if the enemy died.
hitEnemy = function(ps: PState, spec: Spec, id: number, fromX: number, fromZ: number, chained: boolean?): boolean
	local es = enemyService()
	local player = ps.player
	local stats = statsService()
	hitsThisTick += 1

	local amount = spec.damage
	local hunter = stats.getItemCount(player, "HunterGlasses")
	if hunter > 0 and es.isElite and es.isElite(id) then
		amount *= 1 + (Items.Defs.HunterGlasses.effect :: any).bonus * hunter
	end
	local crit = rng:NextNumber() < spec.critChance
	if crit then
		amount *= spec.critMult
	end
	local scissors = stats.getItemCount(player, "RoundScissors")
	if scissors > 0 then
		local eff = Items.Defs.RoundScissors.effect :: any
		if rng:NextNumber() < math.min(eff.chance * scissors, eff.maxChance) then
			amount *= 2
		end
	end
	amount = math.max(1, math.round(amount))

	local ex, ez = es.getPosition(id)
	local killed = es.damage(id, amount, player)
	stats.recordDamage(player, spec.key, amount)

	if spec.lifesteal > 0 and ps.healBudget > 0 then
		local h = math.min(amount * spec.lifesteal, ps.healBudget)
		ps.healBudget -= h
		heal(ps, h)
	end

	if killed then
		if ex and ez then
			onKill(ps, spec, ex, ez)
		end
	else
		local status = spec.status
		if status == "Burn" or status == "Poison" then
			local dmg = stats.get(player).Damage or 0
			applyStatus(id, status, {
				dps = spec.statusDps * (1 + dmg),
				duration = spec.statusDuration,
				source = player,
				maxStacks = spec.maxStacks,
			})
			if status == "Poison" then
				poisonUntil[id] = clock + spec.statusDuration
				poisonOwner[id] = player
			end
		elseif (status == "Stun" or status == "Freeze") and spec.statusDuration > 0 then
			applyStatus(id, status, { duration = spec.statusDuration })
		end
		if spec.statusMult > 0 then
			applyStatus(id, "Slow", { mult = spec.statusMult, duration = 1 })
		end
		if spec.knockback > 0 then
			applyStatus(id, "Knockback", { fromX = fromX, fromZ = fromZ, force = spec.knockback })
		end
		local sticky = stats.getItemCount(player, "StickyEraser")
		if sticky > 0 then
			local eff = Items.Defs.StickyEraser.effect :: any
			if rng:NextNumber() < math.min(eff.chance * sticky, eff.maxChance) then
				applyStatus(id, "Slow", { mult = eff.mult, duration = eff.duration })
			end
		end
		if crit and stats.getItemCount(player, "Flashlight") > 0 then
			applyStatus(id, "Stun", { duration = (Items.Defs.Flashlight.effect :: any).duration })
		end
	end

	-- Thunder Claw: crits arc to nearby enemies (no recursion)
	if crit and spec.chainOnCrit > 0 and not chained and ex and ez then
		local n = es.queryRadius(ex, ez, 10, qbuf2)
		local done = 0
		for i = 1, n do
			local other = qbuf2[i]
			if other ~= id and done < spec.chainOnCrit then
				local ox, oz = es.getPosition(other)
				if ox and oz then
					done += 1
					pushFx(KIND.Segment, FxCodec.Visual.ChainBolt, 1, 0, ex, ez, ox * FxCodec.Scale, oz * FxCodec.Scale, 0, 0)
					hitEnemy(ps, spec, other, ex, ez, true)
				end
			end
		end
	end
	return killed
end

-- Hits every enemy in a circle (optionally a cone). Returns hit count.
local function hitArea(ps: PState, spec: Spec, x: number, z: number, radius: number, dirX: number, dirZ: number, halfDeg: number): number
	local es = enemyService()
	local n = es.queryRadius(x, z, radius + PAD, qbuf2)
	if n == 0 then
		return 0
	end
	-- copy ids: hitEnemy may run nested queries
	local ids = table.move(qbuf2, 1, n, 1, table.create(n))
	local cosHalf = math.cos(math.rad(halfDeg))
	local count = 0
	for i = 1, n do
		local id = ids[i]
		if halfDeg > 0 and halfDeg < 180 then
			local ex, ez = es.getPosition(id)
			if not ex or not ez then
				continue
			end
			local dx, dz = ex - x, ez - z
			local d = math.sqrt(dx * dx + dz * dz)
			if d > 0.5 and (dx * dirX + dz * dirZ) / d < cosHalf then
				continue
			end
		end
		hitEnemy(ps, spec, id, x, z)
		count += 1
	end
	return count
end

-- Spec --------------------------------------------------------------------------------------

local function refreshSpec(ps: PState, weaponId: string, w: Stats): Spec
	local def = Weapons.Defs[weaponId]
	local player = ps.player
	local stats = statsService()
	local block = stats.get(player)
	local classId = stats.getClass(player)
	local passive = classId and Weapons.Passives[classId]

	local add = (block.Damage or 0) + stats.getWeaponBonus(player, weaponId) + contextBonus(player)
	local more = w.dmgMult or 1
	if passive and passive.damageMore then
		more *= passive.damageMore :: number
	end
	if w.armorDamage then
		more *= 1 + w.armorDamage * (block.Armor or 0)
	end
	local critChance = (block.CritChance or 0) + (w.critChance or 0) + (w.luckCrit or 0) * (block.Luck or 0)
	local maxStacks = Weapons.DefaultMaxStacks
	local statusDuration = w.statusDuration or 0
	if def.status == "Burn" and passive and passive.burnMaxStacks then
		maxStacks = passive.burnMaxStacks :: number
		statusDuration = passive.burnDuration :: number
	end

	local spec = ps.specs[weaponId]
	if not spec then
		spec = {
			key = weaponId,
			visual = def.index,
			damage = 0,
			critChance = 0,
			critMult = 2,
			knockback = 0,
			status = def.status,
			statusDps = 0,
			statusDuration = 0,
			statusMult = 0,
			maxStacks = 1,
			lifesteal = 0,
			lifestealCap = 0,
			chainOnCrit = 0,
			xpOnKill = 0,
			popRadius = 0,
		}
		ps.specs[weaponId] = spec
	end
	spec.damage = w.damage * (1 + add) * more
	spec.critChance = math.min(critChance, 1)
	spec.critMult = 2 + (block.CritDamage or 0) + (w.critDamage or 0)
	spec.knockback = w.knockback or 0
	spec.statusDps = w.statusDps or 0
	spec.statusDuration = statusDuration
	spec.statusMult = w.statusMult or 0
	spec.maxStacks = maxStacks
	spec.lifesteal = w.lifesteal or 0
	spec.lifestealCap = w.lifestealCap or 0
	spec.chainOnCrit = w.chainOnCrit or 0
	spec.xpOnKill = w.xpOnKill or 0
	spec.popRadius = (w.popRadius or 0) * (1 + (block.Size or 0))
	return spec
end

-- Projectiles -------------------------------------------------------------------------------

local function spawnProj(ps: PState, spec: Spec, mode: number, x: number, z: number, dirX: number, dirZ: number, speed: number, life: number, radius: number, pierce: number, outTime: number, split: number, targetId: number): Proj?
	if projCount >= SIM.MaxProjectiles then
		return nil
	end
	local p = table.remove(projFree)
	if not p then
		p = {
			ps = ps,
			spec = spec,
			fxId = 0,
			mode = 1,
			x = 0,
			z = 0,
			vx = 0,
			vz = 0,
			speed = 0,
			age = 0,
			life = 0,
			outTime = 0,
			returning = false,
			radius = 1,
			pierce = 1,
			hits = {},
			targetId = 0,
			split = 0,
		}
	end
	local proj = p :: Proj
	nextFxId = nextFxId % 65535 + 1
	proj.ps, proj.spec, proj.fxId, proj.mode = ps, spec, nextFxId, mode
	proj.x, proj.z, proj.vx, proj.vz, proj.speed = x, z, dirX * speed, dirZ * speed, speed
	proj.age, proj.life, proj.outTime, proj.returning = 0, life, outTime, false
	proj.radius, proj.pierce, proj.targetId, proj.split = radius, pierce, targetId, split
	table.clear(proj.hits)
	projCount += 1
	projs[projCount] = proj
	pushFx(KIND.Projectile, spec.visual, radius, proj.fxId, x, z, proj.vx * FxCodec.Scale, proj.vz * FxCodec.Scale, life * 10, ps.slot)
	return proj
end

local function removeProj(i: number, early: boolean)
	local p = projs[i]
	if early then
		pushFx(KIND.End, p.spec.visual, 1, p.fxId, p.x, p.z, 0, 0, 0, 0)
	end
	projs[i] = projs[projCount]
	projs[projCount] = nil :: any
	projCount -= 1
	table.insert(projFree, p)
end

local function stepProjectiles()
	local es = enemyService()
	local i = 1
	while i <= projCount do
		local p = projs[i]
		p.age += DT
		local ps = p.ps
		-- steering
		if p.mode == 2 then
			if not p.returning and p.age >= p.outTime then
				p.returning = true
				table.clear(p.hits)
			end
			if p.returning then
				local dx, dz = ps.x - p.x, ps.z - p.z
				local d = math.sqrt(dx * dx + dz * dz)
				if d < 2 then
					removeProj(i, true)
					continue
				end
				local sp = p.speed * 1.2
				p.vx, p.vz = dx / d * sp, dz / d * sp
			end
		elseif p.mode == 3 then
			local tx, tz = es.getPosition(p.targetId)
			if not tx then
				local id, nx, nz = nearestEnemy(p.x, p.z, 25, nil)
				if id then
					p.targetId, tx, tz = id, nx, nz
				end
			end
			if tx and tz then
				local dx, dz = tx - p.x, tz - p.z
				local d = math.sqrt(dx * dx + dz * dz)
				if d > 0.01 then
					p.vx, p.vz = dx / d * p.speed, dz / d * p.speed
				end
			end
		end
		-- swept move: sub-steps no longer than the hit radius
		local mx, mz = p.vx * DT, p.vz * DT
		local len = math.sqrt(mx * mx + mz * mz)
		local steps = math.clamp(math.ceil(len / math.max(p.radius, 0.5)), 1, 6)
		local removed = false
		for _ = 1, steps do
			p.x += mx / steps
			p.z += mz / steps
			local n = es.queryRadius(p.x, p.z, p.radius + PAD, qbuf)
			for k = 1, n do
				local id = qbuf[k]
				if not table.find(p.hits, id) then
					table.insert(p.hits, id)
					hitEnemy(ps, p.spec, id, p.x - p.vx, p.z - p.vz)
					if p.pierce > 0 then
						p.pierce -= 1
						if p.pierce == 0 then
							if p.spec.popRadius > 0 then
								hitArea(ps, p.spec, p.x, p.z, p.spec.popRadius, 0, 0, 0)
								areaFx(p.spec.visual, p.x, p.z, p.spec.popRadius, 0, 0, 0)
							end
							removed = true
							break
						end
					end
				end
			end
			if removed then
				break
			end
		end
		if removed then
			removeProj(i, true)
			continue
		end
		if p.age >= p.life then
			if p.split > 0 then
				local spec, x, z, n = p.spec, p.x, p.z, p.split
				local r, sp = p.radius * 0.5, p.speed
				removeProj(i, false)
				for s = 1, n do
					local a = (s / n) * math.pi * 2
					spawnProj(ps, spec, 1, x, z, math.cos(a), math.sin(a), sp, 1.2, r, -1, 0, 0, 0)
				end
			else
				removeProj(i, false)
			end
			continue
		end
		i += 1
	end
end

-- Zones -------------------------------------------------------------------------------------

local function newZone(kind: string, ps: PState, spec: Spec, weaponId: string): Zone?
	if #zones >= SIM.MaxZones then
		return nil
	end
	local z: Zone = {
		kind = kind,
		ps = ps,
		spec = spec,
		weaponId = weaponId,
		follow = false,
		ox = 0,
		oz = 0,
		x = ps.x,
		z = ps.z,
		age = 0,
		life = 1,
		timer = 0,
		interval = 1,
		radius = 1,
		count = 1,
		spin = 0,
		orbitRadius = 0,
		range = 0,
		speed = 0,
		pierce = 1,
		projLife = 1,
		angle = 0,
		cluster = 0,
		clusterDamage = 0,
		refresh = 0,
		hitTimes = {},
		dead = false,
	}
	table.insert(zones, z)
	return z
end

local function killZones(ps: PState, weaponId: string)
	for _, z in zones do
		if z.ps == ps and z.weaponId == weaponId and z.kind ~= "Delayed" then
			z.dead = true
		end
	end
end

local function findZone(ps: PState, weaponId: string): Zone?
	for _, z in zones do
		if z.ps == ps and z.weaponId == weaponId and not z.dead and z.kind ~= "Delayed" then
			return z
		end
	end
	return nil
end

local function attachFx(z: Zone, fixed: boolean)
	local life = if z.life == math.huge then ATTACH_REFRESH + 1.5 else z.life - z.age
	local flag = if fixed then 128 else 0
	pushFx(KIND.Attach, z.spec.visual, 1, z.ps.slot, z.x, z.z, (if z.kind == "Orbit" then z.orbitRadius else z.radius) * FxCodec.Scale, life * 100, flag + math.min(z.count, 127), z.spin * 20)
end

-- Per-enemy hit cooldown inside a persistent zone
local function zoneCanHit(z: Zone, id: number): boolean
	local t = z.hitTimes[id]
	if t and t > clock then
		return false
	end
	z.hitTimes[id] = clock + z.interval
	return true
end

local function segmentHits(z: Zone, x1: number, z1: number, x2: number, z2: number, width: number)
	local es = enemyService()
	local mx, mz = (x1 + x2) * 0.5, (z1 + z2) * 0.5
	local dx, dz = x2 - x1, z2 - z1
	local len2 = dx * dx + dz * dz
	local n = es.queryRadius(mx, mz, math.sqrt(len2) * 0.5 + width + PAD, qbuf2)
	local ids = table.move(qbuf2, 1, n, 1, table.create(n))
	local w2 = (width + PAD) ^ 2
	for i = 1, n do
		local id = ids[i]
		local ex, ez = es.getPosition(id)
		if ex and ez then
			local t = if len2 > 0 then math.clamp(((ex - x1) * dx + (ez - z1) * dz) / len2, 0, 1) else 0
			local px, pz = x1 + dx * t - ex, z1 + dz * t - ez
			if px * px + pz * pz <= w2 then
				hitEnemy(z.ps, z.spec, id, x1, z1)
			end
		end
	end
end

local function stepZone(z: Zone)
	local ps = z.ps
	z.age += DT
	if z.follow then
		z.x, z.z = ps.x + z.ox, ps.z + z.oz
	end
	if z.kind == "Delayed" then
		if z.age >= z.life then
			z.dead = true
			hitArea(ps, z.spec, z.x, z.z, z.radius, 0, 0, 0)
			if z.cluster > 0 then
				local spec = z.spec
				for k = 1, z.cluster do
					local a = (k / z.cluster) * math.pi * 2
					local mini = newZone("Delayed", ps, spec, z.weaponId)
					if mini then
						mini.x, mini.z = z.x + math.cos(a) * z.radius * 0.8, z.z + math.sin(a) * z.radius * 0.8
						mini.life = 0.35
						mini.radius = z.radius * 0.5
						-- mini bombs: reduced damage through a scaled spec copy
						local s2 = table.clone(spec)
						s2.damage = spec.damage * z.clusterDamage
						s2.visual = FxCodec.Visual.MiniBomb
						mini.spec = s2
						areaFx(FxCodec.Visual.MiniBomb, mini.x, mini.z, mini.radius, 0, 0, 0.35)
					end
				end
			end
		end
		return
	end
	if z.life ~= math.huge and z.age >= z.life then
		z.dead = true
		return
	end
	if not ps.active then
		return
	end
	if z.life == math.huge then
		z.refresh -= DT
		if z.refresh <= 0 then
			z.refresh = ATTACH_REFRESH
			attachFx(z, false)
		end
	end
	z.timer -= DT
	local es = enemyService()

	if z.kind == "Orbit" then
		local base = z.age * z.spin
		for k = 1, z.count do
			local a = base + (k - 1) / z.count * math.pi * 2
			local sx, sz = z.x + math.cos(a) * z.orbitRadius, z.z + math.sin(a) * z.orbitRadius
			local n = es.queryRadius(sx, sz, z.radius + PAD, qbuf)
			for i = 1, n do
				local id = qbuf[i]
				if zoneCanHit(z, id) then
					hitEnemy(ps, z.spec, id, z.x, z.z)
				end
			end
		end
	elseif z.timer <= 0 then
		z.timer += z.interval
		if z.kind == "Cloud" then
			hitArea(ps, z.spec, z.x, z.z, z.radius, 0, 0, 0)
		elseif z.kind == "Turret" then
			local id, tx, tz = nearestEnemy(z.x, z.z, z.range, nil)
			if id then
				local dx, dz = tx - z.x, tz - z.z
				local base = math.atan2(dz, dx)
				for k = 1, z.count do
					local a = base + math.rad(z.angle) * ((k - 1) - (z.count - 1) / 2)
					spawnProj(ps, z.spec, 1, z.x, z.z, math.cos(a), math.sin(a), z.speed, z.projLife, z.radius, z.pierce, 0, 0, 0)
				end
			end
		elseif z.kind == "Beam" then
			table.clear(chainHits)
			for _ = 1, z.count do
				local id, tx, tz = nearestEnemy(z.x, z.z, z.range, chainHits)
				if not id then
					break
				end
				table.insert(chainHits, id)
				segmentHits(z, z.x, z.z, tx, tz, z.radius)
				pushFx(KIND.Segment, z.spec.visual, 1, 0, z.x, z.z, tx * FxCodec.Scale, tz * FxCodec.Scale, 0, 0)
			end
		end
	end
end

local function stepZones()
	for _, z in zones do
		if not z.dead then
			stepZone(z)
		end
	end
	for i = #zones, 1, -1 do
		local z = zones[i]
		if z.dead then
			zones[i] = zones[#zones]
			zones[#zones] = nil
		end
	end
end

-- Firing ------------------------------------------------------------------------------------

local function aimAt(ps: PState, range: number): (number, number)
	local id, tx, tz = nearestEnemy(ps.x, ps.z, range, nil)
	if id then
		local dx, dz = tx - ps.x, tz - ps.z
		local d = math.sqrt(dx * dx + dz * dz)
		if d > 0.01 then
			return dx / d, dz / d
		end
	end
	return ps.lookX, ps.lookZ
end

-- Fires one "volley" n (n = 0 first, then extra waves/volleys via `pending`).
local function fireWeapon(ps: PState, weaponId: string, level: number, n: number, dirX: number, dirZ: number)
	local def = Weapons.Defs[weaponId]
	local w = Weapons.statsAt(weaponId, level)
	local stats = statsService()
	local block = stats.get(ps.player)
	local spec = refreshSpec(ps, weaponId, w)
	local size = 1 + (block.Size or 0)
	local dur = 1 + (block.Duration or 0)
	local amount = math.max(1, math.floor((w.amount or 1) + (block.Amount or 0)))
	local kind = def.kind
	local classId = stats.getClass(ps.player)

	if kind == "Shot" or kind == "Boomerang" then
		if n == 0 then
			dirX, dirZ = aimAt(ps, w.range or SIM.TargetRange)
		end
		local base = math.atan2(dirZ, dirX)
		local spread = math.rad(w.angle or 10)
		local radius = (w.radius or 1) * size
		for k = 1, amount do
			local a = base + spread * ((k - 1) - (amount - 1) / 2)
			if kind == "Boomerang" then
				spawnProj(ps, spec, 2, ps.x, ps.z, math.cos(a), math.sin(a), w.speed, w.life * dur, radius, -1, w.outTime * dur, 0, 0)
			else
				spawnProj(ps, spec, 1, ps.x, ps.z, math.cos(a), math.sin(a), w.speed, w.life * dur, radius, w.pierce, 0, w.splitOnEnd or 0, 0)
			end
		end
		local volleys = math.floor(w.volleys or 1)
		if kind == "Shot" and n + 1 < volleys then
			table.insert(pending, { at = clock + (w.volleyDelay or 0.2), ps = ps, weaponId = weaponId, n = n + 1, dirX = dirX, dirZ = dirZ })
		end
	elseif kind == "Cone" then
		if n == 0 then
			dirX, dirZ = aimAt(ps, w.range or 12)
		end
		local radius = w.radius * size
		local half = w.angle * 0.5
		hitArea(ps, spec, ps.x, ps.z, radius, dirX, dirZ, half)
		areaFx(spec.visual, ps.x, ps.z, radius, math.atan2(dirZ, dirX), half, 0)
		if n + 1 < amount then
			-- claws alternate front/back; other cones fan out by 20 degrees
			local nx, nz
			if weaponId == "GriffesEclair" then
				nx, nz = -dirX, -dirZ
			else
				local a = math.atan2(dirZ, dirX) + math.rad(if n % 2 == 0 then 20 else -40)
				nx, nz = math.cos(a), math.sin(a)
			end
			table.insert(pending, { at = clock + (w.volleyDelay or 0.15), ps = ps, weaponId = weaponId, n = n + 1, dirX = nx, dirZ = nz })
		end
	elseif kind == "Nova" then
		local radius = w.radius * size
		hitArea(ps, spec, ps.x, ps.z, radius, 0, 0, 0)
		areaFx(spec.visual, ps.x, ps.z, radius, 0, 0, 0)
		if n + 1 < amount then
			table.insert(pending, { at = clock + (w.volleyDelay or 0.3), ps = ps, weaponId = weaponId, n = n + 1, dirX = 0, dirZ = 0 })
		end
	elseif kind == "Cloud" then
		for k = 1, amount do
			local z = newZone("Cloud", ps, spec, weaponId)
			if z then
				z.follow = true
				if k > 1 then
					local a = (k - 2) / math.max(1, amount - 1) * math.pi * 2
					z.ox, z.oz = math.cos(a) * w.radius * size, math.sin(a) * w.radius * size
				end
				z.x, z.z = ps.x + z.ox, ps.z + z.oz
				z.life = w.duration * dur
				z.interval = w.interval
				z.radius = w.radius * size
				z.count = 1
				attachFx(z, false)
			end
		end
	elseif kind == "Turret" then
		local mecano = classId ~= nil and Weapons.Passives[classId] ~= nil and Weapons.Passives[classId].turretsFromAmount ~= nil
		local extra = math.floor(block.Amount or 0)
		local turrets = math.floor(w.turrets) + (if mecano then extra else 0)
		local darts = math.floor(w.darts) + (if mecano then 0 else extra)
		local follow = (w.follow or 0) > 0
		for k = 1, turrets do
			local z = newZone("Turret", ps, spec, weaponId)
			if z then
				local a = rng:NextNumber() * math.pi * 2
				z.ox, z.oz = math.cos(a) * 3, math.sin(a) * 3
				z.x, z.z = ps.x + z.ox, ps.z + z.oz
				z.follow = follow
				z.life = w.duration * dur
				z.interval = w.interval / (1 + (block.AttackSpeed or 0))
				z.timer = 0.2 * k
				z.count = darts
				z.range = w.range
				z.speed = w.speed
				z.radius = w.radius * size
				z.pierce = w.pierce
				z.projLife = w.life
				z.angle = w.angle
				attachFx(z, not follow)
			end
		end
	elseif kind == "Strike" then
		local count = amount
		if w.luckExtra then
			local chance = w.luckExtra * (block.Luck or 0)
			count += math.floor(chance)
			if rng:NextNumber() < chance % 1 then
				count += 1
			end
		end
		local radius = w.radius * size
		for _ = 1, count do
			local id, tx, tz = randomEnemy(ps.x, ps.z, w.range)
			if not id then
				local a = rng:NextNumber() * math.pi * 2
				local r = rng:NextNumber() * 12
				tx, tz = ps.x + math.cos(a) * r, ps.z + math.sin(a) * r
			end
			local z = newZone("Delayed", ps, spec, weaponId)
			if z then
				z.x, z.z = tx, tz
				z.life = w.delay
				z.radius = radius
				z.cluster = math.floor(w.cluster or 0)
				z.clusterDamage = w.clusterDamage or 0
				areaFx(spec.visual, tx, tz, radius, 0, 0, w.delay)
			end
		end
	elseif kind == "Chain" then
		local bounces = math.floor((w.bounces or 0) + (block.Bounces or 0))
		local used: { number } = {}
		for _ = 1, amount do
			local id, tx, tz = nearestEnemy(ps.x, ps.z, w.range, used)
			if not id then
				break
			end
			table.insert(used, id)
			table.clear(chainHits)
			table.insert(chainHits, id)
			local fx, fz = ps.x, ps.z
			local cur: number? = id
			local cx, cz = tx, tz
			local b = 0
			while cur do
				pushFx(KIND.Segment, spec.visual, 1, 0, fx, fz, cx * FxCodec.Scale, cz * FxCodec.Scale, 0, 0)
				hitEnemy(ps, spec, cur, fx, fz)
				if b >= bounces then
					break
				end
				b += 1
				fx, fz = cx, cz
				local nid, nx, nz = nearestEnemy(fx, fz, w.bounceRange, chainHits)
				cur = nid
				if nid then
					table.insert(chainHits, nid)
					cx, cz = nx, nz
				end
			end
		end
	elseif kind == "Orbit" or kind == "Beam" then
		local permanent = (w.permanent or 0) > 0
		local z = if permanent then findZone(ps, weaponId) else nil
		if not z then
			killZones(ps, weaponId)
			z = newZone(kind, ps, spec, weaponId)
		end
		if z then
			z.follow = true
			z.x, z.z = ps.x, ps.z
			z.life = if permanent then math.huge else w.duration * dur
			z.count = amount
			if kind == "Orbit" then
				z.orbitRadius = w.orbitRadius * size
				z.radius = w.radius * size
				z.spin = w.spin * (1 + (block.AttackSpeed or 0))
				z.interval = w.interval
			else
				z.range = w.range * size
				z.radius = w.radius
				z.interval = w.interval
			end
			z.refresh = ATTACH_REFRESH
			attachFx(z, false)
		end
	end
end

local function finalCooldown(w: Stats, block: { [string]: number }): number
	local cd = w.cooldown * (1 - (block.Cooldown or 0)) / (1 + (block.AttackSpeed or 0))
	return math.max(cd, SIM.MinCooldown)
end

-- Umbrella: recharge and auto-wave (Big Top)
local function umbrellaWave(ps: PState, level: number)
	local w = Weapons.statsAt("ParapluieBouclier", level)
	local spec = refreshSpec(ps, "ParapluieBouclier", w)
	local block = statsService().get(ps.player)
	local radius = w.radius * (1 + (block.Size or 0))
	hitArea(ps, spec, ps.x, ps.z, radius, 0, 0, 0)
	areaFx(spec.visual, ps.x, ps.z, radius, 0, 0, 0)
end

local function stepShield(ps: PState, level: number, block: { [string]: number })
	local w = Weapons.statsAt("ParapluieBouclier", level)
	local maxCharges = math.floor(w.charges + math.floor((block.Amount or 0) / 2))
	if ps.shieldCharges >= maxCharges then
		ps.shieldTimer = 0
		return
	end
	ps.shieldTimer += DT
	if ps.shieldTimer >= finalCooldown(w, block) then
		ps.shieldTimer = 0
		ps.shieldCharges += 1
		if (w.autoWave or 0) > 0 and ps.active then
			umbrellaWave(ps, level)
		end
	end
end

local function onPlayerDamaged(player: Player, amount: number)
	local ps = pstates[player]
	if not ps or type(amount) ~= "number" or amount <= 0 then
		return
	end
	local stats = statsService()
	local level = stats.getWeaponLevel(player, "ParapluieBouclier")
	if level <= 0 or ps.shieldCharges <= 0 then
		return
	end
	ps.shieldCharges -= 1
	local w = Weapons.statsAt("ParapluieBouclier", level)
	heal(ps, amount)
	local run = Registry.find("RunManager")
	if run and run.setInvulnerable then
		run.setInvulnerable(player, w.invuln or 0.5)
	end
	umbrellaWave(ps, level)
end

-- Players -------------------------------------------------------------------------------------

local function assignSlot(player: Player)
	for i = 1, 255 do
		if slots[i] == nil then
			slots[i] = player
			player:SetAttribute("FxSlot", i)
			return i
		end
	end
	return 0
end

local function getPState(player: Player): PState
	local ps = pstates[player]
	if not ps then
		ps = {
			player = player,
			slot = assignSlot(player),
			x = 0,
			z = 0,
			lookX = 0,
			lookZ = 1,
			speed = 0,
			airborne = false,
			moving = false,
			active = false,
			hasRoot = false,
			cooldowns = {},
			specs = {},
			shieldCharges = 0,
			shieldTimer = 0,
			healBudget = 0,
		}
		pstates[player] = ps
	end
	return ps
end

local function runPlayers(): { Player }
	local run = Registry.find("RunManager")
	if run and run.getRunPlayers then
		local ok, list = pcall(run.getRunPlayers)
		if ok and type(list) == "table" then
			return list
		end
	end
	return Players:GetPlayers()
end

local function gather()
	local run = Registry.find("RunManager")
	local stats = statsService()
	for _, ps in pstates do
		ps.active = false
	end
	for _, player in runPlayers() do
		if not stats.getState(player) then
			continue
		end
		local ps = getPState(player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			ps.hasRoot = false
			continue
		end
		ps.hasRoot = true
		local pos = root.Position
		ps.x, ps.z = pos.X, pos.Z
		local look = root.CFrame.LookVector
		local lm = math.sqrt(look.X * look.X + look.Z * look.Z)
		if lm > 0.01 then
			ps.lookX, ps.lookZ = look.X / lm, look.Z / lm
		end
		local v = root.AssemblyLinearVelocity
		ps.speed = math.sqrt(v.X * v.X + v.Z * v.Z)
		ps.moving = ps.speed > 1
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		ps.airborne = humanoid ~= nil and humanoid.FloorMaterial == Enum.Material.Air
		local active = true
		if run and run.isActive then
			local ok, result = pcall(run.isActive, player)
			active = ok and result == true
		end
		ps.active = active
	end
end

local function step()
	clock += DT
	simTick += 1
	hitsThisTick = 0
	gather()
	local stats = statsService()

	-- heal budgets refill (lifesteal / lollipop caps are per second)
	for player, ps in pstates do
		local lolli = stats.getItemCount(player, "RainbowLollipop")
		local cap = lolli * (Items.Defs.RainbowLollipop.effect :: any).maxPerSecond
		local fl = stats.getWeaponLevel(player, "FouetTentacule")
		if fl >= Weapons.FusionLevel then
			cap += Weapons.statsAt("FouetTentacule", fl).lifestealCap or 0
		end
		ps.healBudget = math.min(ps.healBudget + cap * DT, cap)
	end

	-- delayed volleys
	for i = #pending, 1, -1 do
		local pf = pending[i]
		if clock >= pf.at then
			pending[i] = pending[#pending]
			pending[#pending] = nil
			if pf.ps.active then
				local level = stats.getWeaponLevel(pf.ps.player, pf.weaponId)
				if level > 0 then
					fireWeapon(pf.ps, pf.weaponId, level, pf.n, pf.dirX, pf.dirZ)
				end
			end
		end
	end

	-- auto-fire
	for player, ps in pstates do
		local s = stats.getState(player)
		if not s then
			continue
		end
		local block = stats.get(player)
		for _, entry in s.weapons do
			if entry.id == "ParapluieBouclier" then
				stepShield(ps, entry.level, block)
				continue
			end
			local cd = (ps.cooldowns[entry.id] or 0) - DT
			if cd <= 0 and ps.active and hitsThisTick < SIM.MaxHitsPerTick then
				local w = Weapons.statsAt(entry.id, entry.level)
				local ok, err = pcall(fireWeapon, ps, entry.id, entry.level, 0, ps.lookX, ps.lookZ)
				if not ok then
					warn(`[WeaponService] {entry.id}: {err}`)
				end
				cd = finalCooldown(w, block)
			end
			ps.cooldowns[entry.id] = math.max(cd, -1)
		end
	end

	stepProjectiles()
	stepZones()
end

local function sendFx()
	local n = fxQueue.n
	if n == 0 then
		return
	end
	local r2 = FX_RADIUS * FX_RADIUS
	for player, ps in pstates do
		if not ps.hasRoot then
			continue
		end
		local m = 0
		for i = 1, n do
			local dx, dz = fxQueue.x[i] / FxCodec.Scale - ps.x, fxQueue.z[i] / FxCodec.Scale - ps.z
			if dx * dx + dz * dz <= r2 then
				m += 1
				fxIdx[m] = i
				if m >= FX_MAX_PER_PLAYER then
					break
				end
			end
		end
		if m > 0 then
			for _, chunk in FxCodec.encode(simTick, fxQueue, fxIdx, m) do
				fxRemote:FireClient(player, chunk)
			end
		end
	end
	FxCodec.clear(fxQueue)
end

-- Domain API (combat only) ----------------------------------------------------------------

export type Motion = { x: number, z: number, speed: number, airborne: boolean, moving: boolean, active: boolean }

-- Live motion sample of a run player (updated at the sim rate). Read only.
function WeaponService.getMotion(player: Player): Motion?
	local ps = pstates[player]
	if not ps or not ps.hasRoot then
		return nil
	end
	return ps :: any
end

-- Direct damage from passives and items (credited under `key` in damageByWeapon).
function WeaponService.dealDamage(player: Player, key: string, visual: number, id: number, damage: number, fromX: number, fromZ: number, knockback: number): boolean
	local ps = pstates[player]
	if not ps then
		return false
	end
	local block = statsService().get(player)
	local spec: Spec = {
		key = key,
		visual = visual,
		damage = damage,
		critChance = block.CritChance or 0,
		critMult = 2 + (block.CritDamage or 0),
		knockback = knockback,
		status = nil,
		statusDps = 0,
		statusDuration = 0,
		statusMult = 0,
		maxStacks = 1,
		lifesteal = 0,
		lifestealCap = 0,
		chainOnCrit = 0,
		xpOnKill = 0,
		popRadius = 0,
	}
	return hitEnemy(ps, spec, id, fromX, fromZ)
end

-- Status in a circle (no damage): Knockback / Stun / Slow pulses from items.
function WeaponService.statusArea(x: number, z: number, radius: number, status: string, params: { [string]: any })
	local es = enemyService()
	local n = es.queryRadius(x, z, radius + PAD, qbuf2)
	for i = 1, n do
		applyStatus(qbuf2[i], status, params)
	end
end

-- Homing ghost (Blankie Ghost item)
function WeaponService.spawnGhost(player: Player, damage: number, speed: number, life: number, radius: number)
	local ps = pstates[player]
	if not ps or not ps.active then
		return
	end
	local id, tx, tz = nearestEnemy(ps.x, ps.z, 40, nil)
	local dx, dz = ps.lookX, ps.lookZ
	if id then
		local ddx, ddz = tx - ps.x, tz - ps.z
		local d = math.sqrt(ddx * ddx + ddz * ddz)
		if d > 0.01 then
			dx, dz = ddx / d, ddz / d
		end
	end
	local block = statsService().get(player)
	local spec = ps.specs.__ghost
	if not spec then
		spec = {
			key = "BlankieGhost",
			visual = FxCodec.Visual.Ghost,
			damage = 0,
			critChance = 0,
			critMult = 2,
			knockback = 0,
			status = nil,
			statusDps = 0,
			statusDuration = 0,
			statusMult = 0,
			maxStacks = 1,
			lifesteal = 0,
			lifestealCap = 0,
			chainOnCrit = 0,
			xpOnKill = 0,
			popRadius = 0,
		}
		ps.specs.__ghost = spec
	end
	spec.damage = damage * (1 + (block.Damage or 0) + contextBonus(player))
	spec.critChance = block.CritChance or 0
	spec.critMult = 2 + (block.CritDamage or 0)
	spawnProj(ps, spec, 3, ps.x, ps.z, dx, dz, speed, life, radius, 1, 0, 0, id or 0)
end

function WeaponService.pushFx(kind: number, visual: number, scale: number, a: number, x: number, z: number, p1: number, p2: number, p3: number, p4: number)
	pushFx(kind, visual, scale, a, x, z, p1, p2, p3, p4)
end

function WeaponService.areaFx(visual: number, x: number, z: number, radius: number)
	areaFx(visual, x, z, radius, 0, 0, 0)
end

function WeaponService.getPoisoner(id: number): Player?
	local t = poisonUntil[id]
	if t and t > clock then
		return poisonOwner[id]
	end
	return nil
end

function WeaponService.markPoison(id: number, player: Player, duration: number)
	poisonUntil[id] = clock + duration
	poisonOwner[id] = player
end

function WeaponService.getSlot(player: Player): number
	return getPState(player).slot
end

-- Called by StatsService.resetRun: clears cooldowns, zones and projectiles of this player.
function WeaponService.resetPlayer(player: Player)
	local ps = getPState(player)
	table.clear(ps.cooldowns)
	table.clear(ps.specs)
	ps.shieldCharges, ps.shieldTimer = 0, 0
	for _, z in zones do
		if z.ps == ps then
			z.dead = true
		end
	end
	for i = projCount, 1, -1 do
		if projs[i].ps == ps then
			removeProj(i, true)
		end
	end
	for i = #pending, 1, -1 do
		if pending[i].ps == ps then
			table.remove(pending, i)
		end
	end
end

-- Lifecycle -------------------------------------------------------------------------------------

function WeaponService.init()
	fxRemote = Net.unreliable("WeaponFx")
	Bus.PlayerDamaged:connect(onPlayerDamaged)
	Bus.EnemyKilled:connect(function(id: number)
		-- Contagion reads poisonOwner first (PassiveService connects too); clear a bit later.
		task.defer(function()
			poisonUntil[id] = nil
			poisonOwner[id] = nil
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local ps = pstates[player]
		if ps then
			WeaponService.resetPlayer(player)
			slots[ps.slot] = nil
			pstates[player] = nil
		end
		for id, owner in poisonOwner do
			if owner == player then
				poisonOwner[id] = nil
				poisonUntil[id] = nil
			end
		end
	end)
end

function WeaponService.start()
	local acc = 0
	local sweep = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < DT then
			return
		end
		acc = math.min(acc - DT, DT)
		local ok, err = pcall(step)
		if not ok then
			warn(`[WeaponService] step: {err}`)
		end
		sendFx()
		sweep += 1
		if sweep >= Balance.SimHz * 5 then
			sweep = 0
			for id, t in poisonUntil do
				if t < clock then
					poisonUntil[id] = nil
					poisonOwner[id] = nil
				end
			end
		end
	end)
end

return WeaponService
