--!strict
-- Passifs des classes v2 (dossier 10 section 8) et objets à déclenchement (section 7 : minuteurs,
-- coup reçu, montée de niveau). Piloté par les données : chaque nombre vient de
-- Config/Weapons.Passives ou Config/Items.
-- Passifs de stats pures (armure du Guardian, zone du Mage, esquive de la Rogue) : StatsService.
-- Crit à distance de l'Archer et aura qui soigne du Cleric : WeaponService.
-- Ici : Valor (Knight, bonus par ennemi proche + parade), Rage (Barbarian), Shadowstep (Rogue),
-- épines de mêlée (Guardian et objets).
-- API interne au combat : getDamageBonus(player) -> number (seau additif), resetPlayer(player).
-- API pour RunManager (domaine run, même agent) : tryBlock(player, amount, source) -> boolean,
-- reviveSpeed(player) -> number.

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
	nearCount: number, -- ennemis à portée de Valor au dernier tick
	parryReadyAt: number,
	wasSliding: boolean,
	slideReadyAt: number,
	timers: { [string]: number }, -- id d'objet -> secondes avant la prochaine impulsion
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
			nearCount = 0,
			parryReadyAt = 0,
			wasSliding = false,
			slideReadyAt = 0,
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

local function passiveOf(player: Player): { [string]: any }?
	local classId = stats().getClass(player)
	return if classId then P[classId] else nil
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

local function hpFraction(player: Player): number
	local run = Registry.find("RunManager")
	if run and run.getHpFraction then
		local ok, frac = pcall(run.getHpFraction, player)
		if ok and type(frac) == "number" and frac == frac then
			return math.clamp(frac, 0, 1)
		end
	end
	return 1
end

-- Bonus de dégâts additif qui dépend de la situation (lu par WeaponService à chaque tir).
function PassiveService.getDamageBonus(player: Player): number
	local s = stats()
	local passive = passiveOf(player)
	local d = pdata[player]
	local bonus = 0
	if passive then
		-- Knight / Valor : +1 % par ennemi proche, plafonné
		if passive.damagePerEnemy and d then
			bonus += math.min(d.nearCount * passive.damagePerEnemy, passive.maxNearBonus or math.huge)
		end
		-- Barbarian / Rage : jusqu'à +50 % quand les PV baissent (linéaire, 0 % à PV pleins)
		if passive.maxRage then
			bonus += (1 - hpFraction(player)) * passive.maxRage
		end
	end
	local weapons = Registry.find("WeaponService")
	local motion = weapons and weapons.getMotion(player)
	if motion then
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

-- Knight / Valor : pare un coup toutes les `parryEvery` secondes. Appelé par
-- RunManager.damagePlayer avant l'esquive et l'armure. true = le coup est annulé.
function PassiveService.tryBlock(player: Player, _amount: number, _source: string): boolean
	local passive = passiveOf(player)
	if not passive or type(passive.parryEvery) ~= "number" then
		return false
	end
	local d = getData(player)
	if clock < d.parryReadyAt then
		return false
	end
	d.parryReadyAt = clock + passive.parryEvery
	local weapons = Registry.find("WeaponService")
	local motion = weapons and weapons.getMotion(player)
	if weapons and motion then
		weapons.areaFx(VIS.Parry, motion.x, motion.z, 3.5)
	end
	return true
end

-- Cleric / Blessing : multiplicateur de vitesse de relève (1 = normal).
function PassiveService.reviveSpeed(player: Player): number
	local passive = passiveOf(player)
	return if passive and type(passive.reviveSpeed) == "number" then passive.reviveSpeed else 1
end

function PassiveService.resetPlayer(player: Player)
	pdata[player] = nil
end

-- Tick par joueur -----------------------------------------------------------------------------

local function pulsePeriod(eff: any, count: number): number
	return math.max(eff.minPeriod, eff.period + eff.perStack * (count - 1))
end

local function tickPlayer(player: Player, d: PData)
	local s = stats()
	local weapons = Registry.get("WeaponService")
	local motion = weapons.getMotion(player)
	if not motion or not motion.active then
		d.lastX, d.lastZ = nil, nil
		d.nearCount = 0
		return
	end
	local passive = passiveOf(player)
	local x, z = motion.x, motion.z

	-- Knight / Valor : ennemis proches (lu par getDamageBonus)
	if passive and type(passive.nearRadius) == "number" then
		d.nearCount = Registry.get("EnemyService").queryRadius(x, z, passive.nearRadius, qbuf)
	else
		d.nearCount = 0
	end

	-- Rogue / Shadowstep : le début d'une glissade validée par MovementGuard (attribut Sliding)
	-- rend intouchable un court instant.
	local sliding = player:GetAttribute("Sliding") == true
	if passive and type(passive.slideInvuln) == "number" and sliding and not d.wasSliding and clock >= d.slideReadyAt then
		d.slideReadyAt = clock + (passive.slideCooldown or 0)
		local run = Registry.find("RunManager")
		if run and run.setInvulnerable then
			pcall(run.setInvulnerable, player, passive.slideInvuln)
		end
		weapons.areaFx(VIS.Shadowstep, x, z, 3)
	end
	d.wasSliding = sliding

	-- Distance pour le Fantôme-doudou
	local ghosts = s.getItemCount(player, "BlankieGhost")
	if d.lastX and d.lastZ then
		local dx, dz = x - d.lastX, z - d.lastZ
		local step = math.sqrt(dx * dx + dz * dz)
		if step < 20 then -- on ignore les téléportations
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

	-- Impulsions à minuteur
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

-- Événements -----------------------------------------------------------------------------------

-- Bus.PlayerDamaged : (player, amount, source) ; source = "Contact" pour la mêlée.
local function onDamaged(player: Player, amount: number, source: string?)
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return
	end
	local s = stats()
	if not s.getState(player) then
		return
	end
	local d = getData(player)

	-- Trousse renforcée : rend une partie du coup
	local cases = s.getItemCount(player, "ReinforcedPencilCase")
	if cases > 0 and clock >= d.absorbReadyAt then
		local eff = itemEffect("ReinforcedPencilCase")
		d.absorbReadyAt = clock + eff.cooldown
		heal(player, math.min(amount, eff.amount + eff.perStack * (cases - 1)))
	end

	-- Épines (Guardian et objets) : seuls les coups de mêlée sont renvoyés.
	local thorns = s.get(player).Thorns or 0
	if thorns > 0 and source == "Contact" then
		local weapons = Registry.get("WeaponService")
		local motion = weapons.getMotion(player)
		if motion then
			local es = Registry.get("EnemyService")
			local n = es.queryRadius(motion.x, motion.z, Weapons.Thorns.radius, qbuf)
			local ids = table.move(qbuf, 1, math.min(n, Weapons.Thorns.targets), 1, {})
			for _, id in ids do
				weapons.dealDamage(player, "Thorns", VIS.Thorns, id, amount * thorns, motion.x, motion.z, 0)
			end
			if #ids > 0 then
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

-- Cycle de vie -----------------------------------------------------------------------------------

function PassiveService.init()
	Bus.PlayerDamaged:connect(onDamaged)
	Bus.PlayerLeveledUp:connect(onLeveledUp)
	Players.PlayerRemoving:Connect(function(player)
		pdata[player] = nil
	end)
end

function PassiveService.start()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < DT then
			return
		end
		acc = math.min(acc - DT, DT)
		clock += DT
		local s = Registry.find("StatsService")
		if not s or not Registry.find("WeaponService") or not Registry.find("EnemyService") then
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
	end)
end

return PassiveService
