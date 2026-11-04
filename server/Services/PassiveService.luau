--!strict
-- Class passives (dossier 10, section 8) and triggered items (section 7: timers, on-damaged,
-- on-level-up). Data-driven: every number comes from Config.Weapons.Passives / Config.Items.
-- Stat-only passives (Rocailleux armor/thorns, Astrel luck, Cristallin size, Tentaculos slot) are
-- folded into StatsService; damage "more" factors into WeaponService.
-- Combat-internal API: getDamageBonus(player) -> number (additive bucket), resetPlayer(player).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Items = require(Config:WaitForChild("Items"))
local Weapons = require(Config:WaitForChild("Weapons"))
local FxCodec = require(Shared:WaitForChild("WeaponFxCodec"))
local Registry = require(Shared:WaitForChild("Registry"))
local Bus = require(script.Parent.Parent:WaitForChild("Bus"))

local DT = 1 / Balance.SimHz
local P = Weapons.Passives
local VIS = FxCodec.Visual

type PData = {
	ramStacks: number,
	ramHits: { [number]: number }, -- enemy id -> clock when it can be rammed again
	landings: number,
	wasAirborne: boolean,
	timers: { [string]: number }, -- item id -> seconds until next pulse
	absorbReadyAt: number,
	distance: number,
	lastX: number?,
	lastZ: number?,
}

local PassiveService = {}

local pdata: { [Player]: PData } = {}
local qbuf: { number } = {}
local clock = 0

local function stats(): any
	return Registry.get("StatsService")
end

local function getData(player: Player): PData
	local d = pdata[player]
	if not d then
		d = {
			ramStacks = 0,
			ramHits = {},
			landings = 0,
			wasAirborne = false,
			timers = {},
			absorbReadyAt = 0,
			distance = 0,
			lastX = nil,
			lastZ = nil,
		}
		pdata[player] = d
	end
	return d
end

local function itemEffect(id: string): any
	return (Items.Defs[id] :: any).effect
end

local function heal(player: Player, amount: number)
	local run = Registry.find("RunManager")
	if run and run.healPlayer and amount > 0 then
		pcall(run.healPlayer, player, amount)
	end
end

-- Additive damage bonus that depends on the situation (read by WeaponService at each fire).
function PassiveService.getDamageBonus(player: Player): number
	local s = stats()
	local classId = s.getClass(player)
	local weapons = Registry.find("WeaponService")
	local motion = weapons and weapons.getMotion(player)
	local bonus = 0
	local d = pdata[player]
	if classId == "Cornu" and d then
		bonus += d.ramStacks * P.Cornu.stackDamage
	end
	if motion then
		if classId == "Plumeline" and motion.airborne then
			bonus += P.Plumeline.airDamage
		end
		local car = s.getItemCount(player, "TinyCar")
		if car > 0 and motion.moving then
			bonus += itemEffect("TinyCar").bonus * car
		end
		local pillow = s.getItemCount(player, "CozyPillow")
		if pillow > 0 and not motion.moving then
			bonus += itemEffect("CozyPillow").bonus * pillow
		end
	end
	return bonus
end

function PassiveService.resetPlayer(player: Player)
	pdata[player] = nil
end

-- Damage helpers ------------------------------------------------------------------------------

local function damageCircle(player: Player, key: string, visual: number, x: number, z: number, radius: number, baseDamage: number, knockback: number, maxTargets: number?, filter: ((id: number) -> boolean)?)
	local es = Registry.get("EnemyService")
	local weapons = Registry.get("WeaponService")
	local block = stats().get(player)
	local damage = baseDamage * (1 + (block.Damage or 0) + PassiveService.getDamageBonus(player))
	local n = es.queryRadius(x, z, radius + Weapons.Sim.EnemyPad, qbuf)
	local ids = table.move(qbuf, 1, n, 1, table.create(n))
	local hits = 0
	for i = 1, n do
		if maxTargets and hits >= maxTargets then
			break
		end
		local id = ids[i]
		if filter and not filter(id) then
			continue
		end
		weapons.dealDamage(player, key, visual, id, damage, x, z, knockback)
		hits += 1
	end
	return hits
end

-- Per-player tick -------------------------------------------------------------------------------

local function pulsePeriod(eff: any, count: number): number
	return math.max(eff.minPeriod, eff.period + eff.perStack * (count - 1))
end

local function tickPlayer(player: Player, d: PData)
	local s = stats()
	local weapons = Registry.get("WeaponService")
	local motion = weapons.getMotion(player)
	if not motion or not motion.active then
		d.lastX, d.lastZ = nil, nil
		return
	end
	local classId = s.getClass(player)
	local x, z = motion.x, motion.z

	-- Cornu: ram while sliding
	if classId == "Cornu" and motion.speed > P.Cornu.chargeSpeed and not motion.airborne then
		local cfg = P.Cornu
		local hit = damageCircle(player, "Cornu", VIS.CornuRam, x, z, cfg.chargeRadius, cfg.chargeDamage, cfg.chargeKnockback, nil, function(id): boolean
			local t = d.ramHits[id]
			if t and t > clock then
				return false
			end
			d.ramHits[id] = clock + cfg.chargeHitCooldown
			return true
		end)
		if hit > 0 then
			d.ramStacks = math.min(d.ramStacks + hit, cfg.maxStacks)
			weapons.areaFx(VIS.CornuRam, x, z, cfg.chargeRadius)
		end
	end

	-- Felyne: count landings
	if classId == "Felyne" then
		if d.wasAirborne and not motion.airborne then
			d.landings += 1
			if d.landings >= P.Felyne.jumps then
				d.landings = 0
				damageCircle(player, "Felyne", VIS.FelyneBolt, x, z, P.Felyne.radius, P.Felyne.damage, 0, nil, nil)
				weapons.areaFx(VIS.FelyneBolt, x, z, P.Felyne.radius)
			end
		end
	end
	d.wasAirborne = motion.airborne

	-- Distance for Blankie Ghost
	local ghosts = s.getItemCount(player, "BlankieGhost")
	if d.lastX and d.lastZ then
		local dx, dz = x - d.lastX, z - d.lastZ
		local step = math.sqrt(dx * dx + dz * dz)
		if step < 20 then -- ignore teleports
			d.distance += step
		end
	end
	d.lastX, d.lastZ = x, z
	if ghosts > 0 then
		local eff = itemEffect("BlankieGhost")
		if d.distance >= eff.distance then
			d.distance = 0
			for _ = 1, ghosts do
				weapons.spawnGhost(player, eff.damage, eff.speed, eff.life, eff.radius)
			end
		end
	else
		d.distance = 0
	end

	-- Timed pulses
	for _, id in { "RecessWhistle", "Megaphone", "FridgeMagnet" } do
		local count = s.getItemCount(player, id)
		if count <= 0 then
			continue
		end
		local eff = itemEffect(id)
		local t = (d.timers[id] or pulsePeriod(eff, count)) - DT
		if t <= 0 then
			t = pulsePeriod(eff, count)
			if id == "RecessWhistle" then
				weapons.statusArea(x, z, eff.radius, "Knockback", { fromX = x, fromZ = z, force = eff.force })
				weapons.areaFx(VIS.Whistle, x, z, eff.radius)
			elseif id == "Megaphone" then
				weapons.statusArea(x, z, eff.radius, "Stun", { duration = eff.duration })
				weapons.areaFx(VIS.Megaphone, x, z, eff.radius)
			else
				s.addTimedStat(player, "Magnet", eff.magnet, eff.duration)
			end
		end
		d.timers[id] = t
	end
end

-- Event handlers ----------------------------------------------------------------------------------

local function onDamaged(player: Player, amount: number)
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return
	end
	local s = stats()
	if not s.getState(player) then
		return
	end
	local d = getData(player)
	d.landings = 0 -- Felyne: streak broken

	-- Sturdy Pencil Case: refund part of the hit
	local cases = s.getItemCount(player, "ReinforcedPencilCase")
	if cases > 0 and clock >= d.absorbReadyAt then
		local eff = itemEffect("ReinforcedPencilCase")
		d.absorbReadyAt = clock + eff.cooldown
		heal(player, math.min(amount, eff.amount + eff.perStack * (cases - 1)))
	end

	-- Thorns (Rocailleux and items)
	local thorns = s.get(player).Thorns or 0
	if thorns > 0 then
		local weapons = Registry.get("WeaponService")
		local motion = weapons.getMotion(player)
		if motion then
			local es = Registry.get("EnemyService")
			local n = es.queryRadius(motion.x, motion.z, Weapons.Thorns.radius, qbuf)
			local done = 0
			for i = 1, n do
				if done >= Weapons.Thorns.targets then
					break
				end
				local id = qbuf[i]
				weapons.dealDamage(player, "Thorns", VIS.Thorns, id, amount * thorns, motion.x, motion.z, 0)
				done += 1
			end
			if done > 0 then
				weapons.areaFx(VIS.Thorns, motion.x, motion.z, Weapons.Thorns.radius)
			end
		end
	end
end

local function onLeveledUp(player: Player, _level: number)
	local count = stats().getItemCount(player, "HotChocolate")
	if count > 0 then
		heal(player, itemEffect("HotChocolate").amount * count)
	end
end

local function onEnemyKilled(id: number, _kind: number, x: number, z: number)
	local weapons = Registry.find("WeaponService")
	if not weapons then
		return
	end
	local owner = weapons.getPoisoner(id)
	if not owner or stats().getClass(owner) ~= "Sporelin" then
		return
	end
	local cfg = P.Sporelin
	local es = Registry.get("EnemyService")
	if not es.applyStatus then
		return
	end
	local dps = cfg.spreadDps * (1 + (stats().get(owner).Damage or 0))
	local n = es.queryRadius(x, z, cfg.spreadRadius, qbuf)
	local done = 0
	for i = 1, n do
		if done >= cfg.spreadCount then
			break
		end
		local other = qbuf[i]
		if other ~= id then
			es.applyStatus(other, "Poison", { dps = dps, duration = cfg.spreadDuration, source = owner, maxStacks = 1 })
			weapons.markPoison(other, owner, cfg.spreadDuration)
			done += 1
		end
	end
	if done > 0 then
		weapons.areaFx(VIS.Contagion, x, z, cfg.spreadRadius)
	end
end

-- Lifecycle -------------------------------------------------------------------------------------

function PassiveService.init()
	Bus.PlayerDamaged:connect(onDamaged)
	Bus.PlayerLeveledUp:connect(onLeveledUp)
	Bus.EnemyKilled:connect(onEnemyKilled)
	Players.PlayerRemoving:Connect(function(player)
		pdata[player] = nil
	end)
end

function PassiveService.start()
	local acc = 0
	local sweep = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < DT then
			return
		end
		acc = math.min(acc - DT, DT)
		clock += DT
		local s = Registry.find("StatsService")
		if not s or not Registry.find("WeaponService") then
			return
		end
		for _, player in Players:GetPlayers() do
			if s.getState(player) then
				local ok, err = pcall(tickPlayer, player, getData(player))
				if not ok then
					warn(`[PassiveService] {err}`)
				end
			end
		end
		sweep += 1
		if sweep >= Balance.SimHz * 5 then
			sweep = 0
			for _, d in pdata do
				for id, t in d.ramHits do
					if t < clock then
						d.ramHits[id] = nil
					end
				end
			end
		end
	end)
end

return PassiveService
