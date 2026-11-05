--!nocheck
-- A04-12 — modèle d'équilibrage du monde 1 « sur papier » (lancé par tools/tests/a04-balance.sh).
-- Les configs (SRC.*) sont les vraies sources du dépôt, chargées avec des bouchons du moteur : un
-- réglage changé dans shared/Config change le résultat ici sans rien recopier.
--
-- Ce n'est PAS le jeu : c'est un modèle à pas de 0,5 s qui suit des moyennes. Ce qu'il reprend du code :
--   densité voulue (Balance.DensityCurve, EnemyService.desiredAlive), vagues et boost (Run.Waves),
--   mélange des familles (SwarmShare, FamilyUnlock, roster et variantes de Worlds), élites (EliteFirstAt,
--   EliteEvery, EliteHpMult, Loot.EliteXpMult), mini-boss (MiniBossAt, PV x EliteHpMult comme
--   RunManager.spawnMiniBoss), Overtime (Run.Overtime), XP (Enemies[].xp, Cards.xpToNext), tirage de
--   cartes (CardService.buildCandidates / takeWeighted, Rarities.roll, CompanionChance, garantie Mage),
--   stats (StatsService : base + Runes + objets + passif par niveau), dégâts des armes
--   (WeaponService : dégâts x (1 + Damage + bonus de carte) x dmgMult, recharge x (1 - Cooldown) /
--   (1 + AttackSpeed), Size, Amount, Duration, critiques), dégâts reçus (RunManager.damagePlayer :
--   parade du Knight, esquive, armure K / (K + armure)), boss (Bosses.List, attaques de phase 1).
-- Ce qu'il SUPPOSE (le « joueur moyen », section 1 du rapport docs/qa/equilibrage-monde1.md) : la
-- table AVG ci-dessous. Changer AVG, c'est changer de joueur, pas d'équilibrage.

local AVG = {
	crowdRadius = 10, -- studs : la foule qui colle au joueur tient dans ce disque
	ringDistance = 75, -- studs : distance moyenne d'apparition (SpawnRingMin..Max)
	exposure = 0.04, -- part du contact max (3 ennemis) subie : ~1 contact / 15 s à 1:00, ~1 / 5 s à 9:00
	exposureK = 8, -- « pression » (ennemis au contact) à laquelle le contact atteint 63 % de son max
	rangedDwell = 0.5, -- une arme qui porte loin tue avant le contact : temps au contact x 0,5
	shotHit = 0.12, -- part des tirs ennemis lents qui touchent
	shootersInRange = 0.25, -- part des tireurs vivants assez près pour tirer (ils restent à 26 studs)
	leapHit = 0.25, -- part des sauts de Jumper proches qui touchent
	bomberHit = 0.30, -- part des Bombers arrivés au contact qui explosent sur le joueur
	telegraphDodge = 0.60, -- part des attaques de boss annoncées esquivées
	ringDodge = 0.70, -- anneaux : se sautent
	pickup = 0.90, -- part de l'XP ramassée
	bigFocus = 0.5, -- part des coups « mono-cible » qui vont sur l'élite ou le mini-boss présent
	miniBossExposure = 0.03, -- contact d'une grosse cible lente (élite, mini-boss, boss) : part du temps collé
	bigRangedMult = 0.5, -- classe à arme de départ à distance : elle frappe de loin, collée 2 fois moins
	slamInRange = 0.20, -- part du temps passée à portée de la frappe du mini-boss
	merchantHeal = { at = 330, below = 0.7 }, -- un soin du marchand (Loot.MerchantHealFraction) si PV < 70 %
	randomPick = 0.20, -- part des cartes prises au hasard (le reste : stratégie simple)
	chestTimes = { 150, 300, 450 }, -- coffres achetés (1 objet chacun)
	bossStart = 570, -- arrivée à l'arène + compte à rebours (9:30 de jeu)
	bossTimeout = 300, -- au-delà, l'Overtime gagne : défaite
	companionDps = 7, -- Braise, mono-cible, avant cartes de compagnon
}

local DT = 0.5

-- Bouchons du moteur ---------------------------------------------------------------------------
local stub
stub = setmetatable({}, {
	__index = function(_, k)
		if k == "IsStudio" then
			return function()
				return false
			end
		elseif k == "WaitForChild" or k == "FindFirstChild" then
			return function()
				return stub
			end
		end
		return stub
	end,
})
local game = { GetService = function()
	return stub
end }
local function fakeRequire(_x)
	return {}
end
local Color3 = { fromRGB = function(r, g, b)
	return { r, g, b }
end, new = function(r, g, b)
	return { r, g, b }
end }
local Vector3 = { new = function(x, y, z)
	return { x, y, z }
end }

local function load(name)
	local f, e = loadstring("local game, script, require, Color3, Vector3, Enum = ...\n" .. SRC[name], name)
	assert(f, e)
	return f(game, stub, fakeRequire, Color3, Vector3, stub)
end

local Weapons = load("Weapons")
local Grimoires = load("Grimoires")
local Cards = load("Cards")
local Run = load("Run")
local Balance = load("Balance")
local Enemies = load("Enemies")
local Items = load("Items")
local Bosses = load("Bosses")
local Worlds = load("Worlds")
local Rarities = load("Rarities")
local Loot = load("Loot")

-- Variante (3e argument du .sh) : autre joueur ou réglage à l'essai, sans toucher aux fichiers.
-- Ex. "AVG.exposure = 0.05" ou "Run.MiniBossAt = {}". Variables : AVG et les configs ci-dessus.
if AVG_OVERRIDE ~= "" then
	local f = assert(loadstring("local AVG, Weapons, Grimoires, Cards, Run, Balance, Enemies, Bosses, Loot = ...\n" .. AVG_OVERRIDE, "AVG_OVERRIDE"))
	f(AVG, Weapons, Grimoires, Cards, Run, Balance, Enemies, Bosses, Loot)
end

local rngObj = { NextNumber = function()
	return math.random()
end }

-- Monde 1 : mélange des ennemis ------------------------------------------------------------------
local world = Worlds.BoisGrognon
local FAMILIES = { "Jumper", "Shooter", "Armored", "Support", "Kamikaze" }

local function kindMix(familyKind, family)
	-- { {def, part} } d'une famille avec sa variante
	local v = world.variants and world.variants[family]
	if v then
		return { { Enemies[familyKind], 1 - v.chance }, { Enemies[v.kind], v.chance } }
	end
	return { { Enemies[familyKind], 1 } }
end

-- Moyennes de la population qui apparaît à `elapsed` : PV, XP, contact, et parts par famille.
local function population(elapsed)
	local mix = {}
	for _, e in kindMix(world.roster.Swarm, "Swarm") do
		table.insert(mix, { e[1], e[2] * Balance.SwarmShare })
	end
	local open = {}
	for _, fam in FAMILIES do
		local k = world.roster[fam]
		if k and elapsed >= (Run.FamilyUnlock[fam] or math.huge) then
			table.insert(open, fam)
		end
	end
	local rest = 1 - Balance.SwarmShare
	if #open == 0 then
		mix[1][2] += rest * (mix[1][2] / Balance.SwarmShare)
		if mix[2] then
			mix[2][2] += rest * (mix[2][2] / Balance.SwarmShare)
		end
	else
		for _, fam in open do
			for _, e in kindMix(world.roster[fam], fam) do
				table.insert(mix, { e[1], e[2] * rest / #open })
			end
		end
	end
	local p = { hp = 0, xp = 0, contact = 0, Jumper = 0, Shooter = 0, Kamikaze = 0, Support = 0, speed = 0, shot = 0, blast = 0, leap = 0 }
	for _, e in mix do
		local d, w = e[1], e[2]
		p.hp += d.hp * w
		p.xp += d.xp * w
		p.contact += d.contactDamage * w
		p.speed += d.speed * w
		if p[d.family] then
			p[d.family] += w
		end
		if d.family == "Shooter" then
			p.shot += (d.shotDamage or 0) * w
		elseif d.family == "Kamikaze" then
			p.blast += (d.blastDamage or 0) * w
		elseif d.family == "Jumper" then
			p.leap += d.contactDamage * w
		end
	end
	if p.Shooter > 0 then
		p.shot /= p.Shooter
	end
	if p.Kamikaze > 0 then
		p.blast /= p.Kamikaze
	end
	if p.Jumper > 0 then
		p.leap /= p.Jumper
	end
	return p
end

local function curveAt(elapsed)
	local curve = Balance.DensityCurve
	for k = 1, #curve - 1 do
		local a, b = curve[k], curve[k + 1]
		if elapsed <= b[1] then
			local u = math.clamp((elapsed - a[1]) / (b[1] - a[1]), 0, 1)
			return a[2] + (b[2] - a[2]) * u
		end
	end
	return curve[#curve][2]
end

local function overtimeStep(t)
	if t < Run.StageSeconds then
		return 0
	end
	return (t - Run.StageSeconds) // Run.Overtime.StepSeconds
end

local function otFactor(per, k)
	if Run.Overtime.Compound then
		return (1 + per) ^ k
	end
	return 1 + per * k
end

-- Joueur ----------------------------------------------------------------------------------------
local function newPlayer(classId)
	local Classes = { Knight = "Broadsword", Archer = "Longbow", Mage = "FireStaff" }
	return {
		class = classId,
		level = 1,
		xp = 0,
		hp = Grimoires.BaseStats.MaxHp,
		weapons = { { id = Classes[classId], level = 1, bonus = 0 } },
		runes = {},
		items = {},
		companionLevel = 0,
		offersMade = 0,
		parryReadyAt = 0,
		levelAt = {},
		firstNewWeaponAt = nil,
	}
end

local function statBlock(pl)
	local b = table.clone(Grimoires.BaseStats)
	for _, r in pl.runes do
		local def = Grimoires.Defs[r.id]
		for stat in def.perLevel do
			b[stat] = (b[stat] or 0) + Grimoires.valueAt(def, stat, r.level)
		end
		if def.byLevel then
			for stat in def.byLevel do
				if not def.perLevel[stat] then
					b[stat] = (b[stat] or 0) + Grimoires.valueAt(def, stat, r.level)
				end
			end
		end
	end
	local mults = {}
	for _, it in pl.items do
		for stat, v in it.stats or {} do
			b[stat] = (b[stat] or 0) + v
		end
		for stat, v in it.mult or {} do
			mults[stat] = (mults[stat] or 1) * v
		end
	end
	local passive = Weapons.Passives[pl.class]
	if passive.perLevel then
		for stat, v in passive.perLevel do
			b[stat] += v * pl.level
		end
	end
	if passive.flat then
		for stat, v in passive.flat do
			b[stat] += v
		end
	end
	for stat, m in mults do
		b[stat] *= m
	end
	for stat, cap in Grimoires.StatCaps do
		if b[stat] then
			b[stat] = math.min(b[stat], cap)
		end
	end
	b.MaxHp = math.max(1, b.MaxHp) -- RunManager lit la stat MaxHp (Run.Player.BaseMaxHp n'est qu'un repli)
	return b
end

-- Portée « de boss » d'une arme : part de ses déclenchements qui touchent le boss (ou une grosse cible).
local BOSS_REACH = { Cone = 0.6, Nova = 0.6, Cloud = 0.5, Orbit = 0.4, Shot = 0.6, Chain = 0.7, Boomerang = 0.6, Strike = 0.5, Turret = 0.4 }
local PAD = Weapons.Sim.EnemyPad

-- Une arme dans la foule : renvoie (dégâts par coup, coups par seconde sur la foule, déclenchements
-- par seconde, crit chance, crit mult). `rho` = ennemis par stud² autour du joueur, `near` = foule,
-- `reach` = ennemis atteignables (foule + ceux qui arrivent dans la portée).
local function weaponProfile(pl, b, w, rho, near, reach)
	local def = Weapons.Defs[w.id]
	local s = Weapons.statsAt(w.id, w.level)
	local size = 1 + b.Size
	local dur = 1 + b.Duration
	local amount = math.max(1, math.floor((s.amount or 1) + b.Amount))
	local passive = Weapons.Passives[pl.class]
	local ctx = 0
	if passive.damagePerEnemy then
		ctx = math.min(passive.maxNearBonus, passive.damagePerEnemy * near)
	end
	local dmg = s.damage * (1 + b.Damage + w.bonus + ctx) * (s.dmgMult or 1)
	local cc = math.min(1, b.CritChance + (s.critChance or 0))
	if passive.farCrit then
		cc = math.min(1, cc + passive.farCrit * 0.5) -- la moitié des coups à plus de 20 studs
	end
	local cm = 2 + b.CritDamage + (s.critDamage or 0)
	local cd = math.max(Weapons.Sim.MinCooldown, s.cooldown * (1 - b.Cooldown) / (1 + b.AttackSpeed))
	local kind = def.kind
	local acts, hitsPer = 0, 0
	local function area(r)
		return math.min(near, rho * math.pi * (r + PAD) ^ 2)
	end
	if kind == "Cone" then
		acts = amount / cd
		hitsPer = math.max(math.min(near, 1), math.min(near, rho * (s.angle / 360) * math.pi * (s.radius * size + PAD) ^ 2))
	elseif kind == "Nova" then
		acts = amount / cd
		hitsPer = math.max(math.min(near, 1), area(s.radius * size))
	elseif kind == "Shot" then
		local per = amount * (s.volleys or 1)
		acts = per / cd
		local line = rho * 2 * (s.radius * size + PAD) * math.min(s.speed * s.life * dur, 2 * AVG.crowdRadius + 10)
		local pierce = if s.pierce < 0 then math.huge else s.pierce
		hitsPer = math.min(reach, math.max(1, math.min(pierce, line)))
		if (s.popRadius or 0) > 0 then
			local pop = math.min(near, rho * math.pi * (s.popRadius * size) ^ 2)
			hitsPer += pop * (if (s.endBlast or 0) > 0 then 1 else 0.7)
		end
		hitsPer = math.min(hitsPer, reach)
	elseif kind == "Cloud" then
		local interval = s.interval / (1 + b.AttackSpeed)
		acts = 1 / interval
		hitsPer = area(s.radius * size)
	elseif kind == "Orbit" then
		local oR = s.orbitRadius * size
		local r = s.radius * size + PAD
		local uptime = if (s.permanent or 0) > 0 then 1 else math.min(1, s.duration * dur / cd)
		local spin = s.spin * (1 + b.AttackSpeed)
		local inRing = rho * math.pi * ((oR + r) ^ 2 - math.max(0, oR - r) ^ 2)
		local swept = amount * rho * 2 * r * spin * oR
		local hps = math.min(swept, math.min(near, inRing) / s.interval) * uptime
		acts = amount * uptime / s.interval
		hitsPer = if acts > 0 then hps / acts else 0
	elseif kind == "Chain" then
		acts = amount / cd
		hitsPer = math.min(reach, 1 + s.bounces + b.Bounces)
	elseif kind == "Boomerang" then
		acts = amount / cd
		hitsPer = math.min(reach, math.max(1, rho * 2 * (s.radius * size + PAD) * s.speed * s.outTime * 2))
	elseif kind == "Strike" then
		acts = amount / cd
		hitsPer = math.min(reach, math.max(1, rho * 1.5 * math.pi * (s.radius * size + PAD) ^ 2))
	elseif kind == "Turret" then
		local active = math.min(s.turrets, s.turrets * s.duration * dur / s.cooldown)
		acts = active * s.darts * (1 + b.AttackSpeed) / s.interval
		hitsPer = math.min(reach, math.max(1, math.min(s.pierce, rho * 2 * (s.radius + PAD) * s.speed * s.life)))
	end
	if near + reach <= 0 then
		hitsPer = 0
	end
	-- Brûlure : dps de statut sur les cibles touchées (une pile)
	local burn = 0
	if (s.statusDps or 0) > 0 and def.status == "Burn" then
		burn = s.statusDps * math.min(s.statusDuration, cd) / cd * hitsPer * math.min(1, acts * cd)
	end
	return dmg, acts, hitsPer, cc, cm, burn, BOSS_REACH[kind] or 0.5
end

-- Tirage des crits sur n coups (petit n : binomial exact ; grand n : normale)
local function critCount(n, p)
	if n <= 0 or p <= 0 then
		return 0
	end
	if n < 20 then
		local c = 0
		for _ = 1, math.floor(n) do
			if math.random() < p then
				c += 1
			end
		end
		if math.random() < n - math.floor(n) and math.random() < p then
			c += 1
		end
		return c
	end
	local sd = math.sqrt(n * p * (1 - p))
	local g = math.sqrt(-2 * math.log(math.max(1e-9, math.random()))) * math.cos(2 * math.pi * math.random())
	return math.clamp(n * p + g * sd, 0, n)
end

-- Nombre de coups reçus sur dt (moyenne `rate * dt`, tirage de Poisson)
local function poisson(lambda)
	if lambda <= 0 then
		return 0
	end
	if lambda > 30 then
		return math.max(0, math.floor(lambda + math.sqrt(lambda) * (math.random() * 2 - 1) * 1.7 + 0.5))
	end
	local l, k, p = math.exp(-lambda), 0, 1
	repeat
		k += 1
		p *= math.random()
	until p <= l
	return k - 1
end

-- Cartes ----------------------------------------------------------------------------------------
local RUNE_PRIORITY = {
	Damage = 45, AttackSpeed = 42, Vitality = 40, Area = 38, Projectiles = 38, Cooldown = 35, Armor = 33,
	Crit = 30, Agility = 28, Duration = 25, Wisdom = 25, Magnet = 20, Luck = 15, Cursed = 5,
}

local function findOwned(list, id)
	for _, x in list do
		if x.id == id then
			return x
		end
	end
	return nil
end

local function drawOffer(pl, b)
	local slots = Cards.DefaultMeta
	local cands = {}
	for _, id in Weapons.Order do
		local o = findOwned(pl.weapons, id)
		if o then
			if o.level < Weapons.MaxLevel then
				table.insert(cands, { kind = "WeaponUp", id = id, weight = Cards.PoolWeight.WeaponUp })
			end
		elseif #pl.weapons < slots.weaponSlots then
			table.insert(cands, { kind = "NewWeapon", id = id, weight = Cards.PoolWeight.NewWeapon })
		end
	end
	for _, id in Grimoires.Order do
		local o = findOwned(pl.runes, id)
		if o then
			if o.level < Grimoires.Defs[id].maxLevel then
				table.insert(cands, { kind = "GrimoireUp", id = id, weight = Cards.PoolWeight.GrimoireUp })
			end
		elseif #pl.runes < slots.grimoireSlots then
			table.insert(cands, { kind = "NewGrimoire", id = id, weight = Cards.PoolWeight.NewGrimoire })
		end
	end
	local offer = {}
	local companionLeft = 2
	for _ = 1, Cards.OfferSize do
		if companionLeft > 0 and math.random() < Cards.CompanionChance then
			companionLeft -= 1
			table.insert(offer, { kind = "Companion", rarity = "Common" })
			continue
		end
		local total = 0
		for _, c in cands do
			total += c.weight
		end
		if total <= 0 then
			break
		end
		local pick = math.random() * total
		local chosen = #cands
		for i, c in cands do
			pick -= c.weight
			if pick <= 0 then
				chosen = i
				break
			end
		end
		local c = table.remove(cands, chosen)
		c.rarity = Rarities.roll(b.Luck, rngObj, nil)
		table.insert(offer, c)
	end
	pl.offersMade += 1
	local every = Weapons.Passives[pl.class].rareEveryOffers
	if every and pl.offersMade % every == 0 then
		local has = false
		for _, c in offer do
			if Rarities.rank(c.rarity) >= 2 then
				has = true
			end
		end
		if not has then
			for _, c in offer do
				if c.kind ~= "Companion" then
					c.rarity = Rarities.roll(b.Luck, rngObj, 2)
					break
				end
			end
		end
	end
	return offer
end

local function scoreCard(pl, c)
	local r = Rarities.rank(c.rarity)
	if c.kind == "NewWeapon" then
		return if #pl.weapons < 3 then 100 else 40
	elseif c.kind == "WeaponUp" then
		return 50 + r * 10 + (if c.id == pl.weapons[1].id then 10 else 0)
	elseif c.kind == "NewGrimoire" or c.kind == "GrimoireUp" then
		return RUNE_PRIORITY[c.id] + r * 8 + (if c.kind == "GrimoireUp" then 5 else 0)
	end
	return 30
end

local function applyCard(pl, c, t)
	if c.kind == "NewWeapon" then
		table.insert(pl.weapons, { id = c.id, level = math.min(Weapons.MaxLevel, Cards.WeaponLevels[c.rarity]), bonus = Cards.WeaponDamageBonus[c.rarity] })
		pl.firstNewWeaponAt = pl.firstNewWeaponAt or t
	elseif c.kind == "WeaponUp" then
		local w = findOwned(pl.weapons, c.id)
		w.level = math.min(Weapons.MaxLevel, w.level + Cards.WeaponLevels[c.rarity])
		w.bonus += Cards.WeaponDamageBonus[c.rarity]
	elseif c.kind == "NewGrimoire" or c.kind == "GrimoireUp" then
		local g = findOwned(pl.runes, c.id)
		if not g then
			g = { id = c.id, level = 0 }
			table.insert(pl.runes, g)
		end
		g.level = math.min(Grimoires.Defs[c.id].maxLevel, g.level + Cards.GrimoireLevels[c.rarity])
	elseif c.kind == "Companion" then
		pl.companionLevel += 1
	end
end

local function levelUp(pl, t)
	local b = statBlock(pl)
	local offer = drawOffer(pl, b)
	if #offer == 0 then
		pl.hp = math.min(b.MaxHp, pl.hp + b.MaxHp * Cards.HealFraction)
		return
	end
	local best
	if math.random() < AVG.randomPick then
		best = offer[math.random(#offer)]
	else
		local bs = -1
		for _, c in offer do
			local s = scoreCard(pl, c)
			if s > bs then
				bs, best = s, c
			end
		end
	end
	local before = b.MaxHp
	applyCard(pl, best, t)
	local after = statBlock(pl).MaxHp
	if after > before then
		pl.hp += after - before
	end
end

-- Objets de coffre : on ne garde que ceux à stats (les effets déclenchés ne sont pas modélisés)
local STAT_ITEMS = {}
for _, it in Items.List or {} do
	if it.stats or it.mult then
		table.insert(STAT_ITEMS, it)
	end
end
if #STAT_ITEMS == 0 then
	for _, it in Items.Defs or {} do
		if it.stats or it.mult then
			table.insert(STAT_ITEMS, it)
		end
	end
end

-- Une run ---------------------------------------------------------------------------------------
local function simulate(classId)
	local pl = newPlayer(classId)
	local t = 0
	local near, alive = 0, 0
	local nextEliteAt = Run.EliteFirstAt
	local bigs = {} -- { hp, xp, contact, mini }
	local miniDone = {}
	local wavesDone = {}
	local burstLeft, burstRate, boostUntil, boostMult = 0, 0, 0, 1
	local chestIdx = 1
	local boss = nil
	local bossDef = Bosses.List[world.boss]
	local kills = 0
	local dmgTaken = 0
	local log = {}
	while true do
		local b = statBlock(pl)
		if pl.hp > b.MaxHp then
			pl.hp = b.MaxHp
		end
		local k = overtimeStep(t)
		local O = Run.Overtime
		local hpMult = otFactor(O.HpPerStep, k) * (1 + (b.Difficulty or 0))
		local dmgMult = otFactor(O.DamagePerStep, k)
		local pop = population(t)
		local enemyHp = pop.hp * hpMult
		local phaseD = if boss then Run.PhaseDensity.Boss else 1
		local desired = curveAt(t) * otFactor(O.SpawnPerStep, k) * phaseD * (1 + (b.Difficulty or 0) * Run.DifficultyDensityShare)
		if t < boostUntil then
			desired *= boostMult
		end
		desired = math.min(desired, Balance.MaxEnemies)
		-- Vagues
		local left = Run.StageSeconds - t
		for i, wave in Run.Waves do
			if not wavesDone[i] and left <= wave.timeLeft then
				wavesDone[i] = true
				burstLeft += wave.size
				burstRate = wave.size / wave.spawnSeconds
				boostUntil = t + wave.boostSeconds
				boostMult = wave.boost
			end
		end
		if alive < desired then
			alive = desired
		end
		if burstLeft > 0 then
			local add = math.min(burstLeft, burstRate * DT, Balance.MaxEnemies - alive)
			burstLeft -= math.max(add, 0)
			alive += math.max(add, 0)
		end
		-- Élites et mini-boss
		if t >= nextEliteAt and not boss then
			nextEliteAt = t + Run.EliteEvery
			table.insert(bigs, { hp = pop.hp * hpMult * Run.EliteHpMult * 1.4, xp = pop.xp * Loot.EliteXpMult * 1.4, contact = pop.contact * Run.Player.EliteDamageMult })
		end
		for i, at in Run.MiniBossAt do
			if not miniDone[i] and t >= at then
				miniDone[i] = true
				local d = Enemies[world.miniBoss]
				table.insert(bigs, { hp = d.hp * hpMult * Run.EliteHpMult, xp = d.xp * Loot.EliteXpMult, contact = d.contactDamage, mini = d, born = t })
			end
		end
		if chestIdx <= #AVG.chestTimes and t >= AVG.chestTimes[chestIdx] then
			chestIdx += 1
			local it = STAT_ITEMS[math.random(#STAT_ITEMS)]
			if it then
				local before = b.MaxHp
				table.insert(pl.items, it)
				b = statBlock(pl)
				if b.MaxHp > before then
					pl.hp += b.MaxHp - before
				end
			end
		end
		if not boss and t >= AVG.bossStart then
			boss = { hp = bossDef.hp * Run.WorldScaling[1].bossHp, max = bossDef.hp, start = t, next = {} }
		end

		-- Arrivées dans la foule
		local speed = pop.speed
		local far = math.max(0, alive - near)
		near += far * speed / AVG.ringDistance * DT
		near = math.min(near, alive)
		local rho = near / (math.pi * AVG.crowdRadius ^ 2)

		-- Dégâts du joueur
		local crowdDamage, singleDamage = 0, 0
		for _, w in pl.weapons do
			local wdef = Weapons.Defs[w.id]
			local s = Weapons.statsAt(w.id, w.level)
			local range = s.range or Weapons.Sim.TargetRange
			local reach = near + far * math.clamp((range - AVG.crowdRadius) / 80, 0, 0.6)
			if wdef.kind == "Cone" or wdef.kind == "Nova" or wdef.kind == "Cloud" or wdef.kind == "Orbit" then
				reach = near
			end
			local dmg, acts, hitsPer, cc, cm, burn, bossReach = weaponProfile(pl, b, w, rho, near, reach)
			local hits = acts * hitsPer * DT
			local crits = critCount(hits, cc)
			local avgDmg = if hits > 0 then dmg * (hits + crits * (cm - 1)) / hits else dmg
			-- Gaspillage : un coup ne retire jamais plus que les PV d'un ennemi
			crowdDamage += hits * math.min(avgDmg, enemyHp) + burn * DT
			singleDamage += acts * DT * bossReach * dmg * (1 + cc * (cm - 1))
		end
		singleDamage += AVG.companionDps * (1 + 0.15 * pl.companionLevel) * DT
		crowdDamage += AVG.companionDps * (1 + 0.15 * pl.companionLevel) * DT * 0.5

		-- Une grosse cible présente prend une part des coups mono-cible
		local big = bigs[1]
		if big then
			local share = singleDamage * AVG.bigFocus
			big.hp -= share
			crowdDamage -= math.min(crowdDamage, share * 0.5)
			if big.hp <= 0 then
				table.remove(bigs, 1)
				if big.mini then
					MINITIMES[#MINITIMES + 1] = t - big.born
				end
				pl.xp += big.xp * (1 + b.XpGain) * AVG.pickup
			end
		end
		if boss then
			boss.hp -= singleDamage * (1 - (if big then AVG.bigFocus else 0))
		end

		local killed = math.min(near, crowdDamage / enemyHp)
		near -= killed
		alive -= killed
		kills += killed
		pl.xp += killed * pop.xp * (1 + b.XpGain) * AVG.pickup

		-- Dégâts reçus
		-- Pression au contact : ceux qui arrivent restent ~ une demi-recharge collés avant de mourir
		-- (moins si une arme qui porte loin les tue en chemin), plus la foule qui n'a pas été tuée.
		local cdMin, ranged = math.huge, false
		for _, w in pl.weapons do
			local s = Weapons.statsAt(w.id, w.level)
			cdMin = math.min(cdMin, math.max(Weapons.Sim.MinCooldown, s.cooldown * (1 - b.Cooldown) / (1 + b.AttackSpeed)))
			if (s.range or 0) > 20 then
				ranged = true
			end
		end
		local arrivals = far * speed / AVG.ringDistance
		local pressure = arrivals * 0.5 * cdMin * (if ranged then AVG.rangedDwell else 1) + near
		local touching = Run.Player.ContactMaxEnemies * (1 - math.exp(-pressure / AVG.exposureK)) * AVG.exposure
		local incoming = {}
		local function add(rate, amount, src)
			for _ = 1, poisson(rate * DT) do
				table.insert(incoming, { amount, src })
			end
		end
		add(touching / Run.Player.ContactCooldown, pop.contact * dmgMult, "contact")
		local shooters = alive * pop.Shooter * AVG.shootersInRange
		add(shooters / 3.2 * AVG.shotHit, pop.shot * dmgMult, "tirs")
		local jumpers = near * pop.Jumper
		add(jumpers / 3.5 * AVG.leapHit, pop.leap * dmgMult, "sauts")
		local bomberArrive = far * speed / AVG.ringDistance * pop.Kamikaze
		add(bomberArrive * AVG.bomberHit * math.max(0, 1 - crowdDamage / DT / math.max(1, enemyHp * 4)), pop.blast * dmgMult, "bombers")
		local startRange = Weapons.statsAt(pl.weapons[1].id, 1).range or 0
		local bigExp = AVG.miniBossExposure * (if startRange > 20 then AVG.bigRangedMult else 1)
		for _, g in bigs do
			if g.mini then
				add(bigExp / Run.Player.ContactCooldown, g.contact * dmgMult, "mini-boss")
				add(AVG.slamInRange * (1 - AVG.telegraphDodge) / g.mini.slamEvery, g.mini.slamDamage * dmgMult, "mini-boss")
			else
				add(bigExp / Run.Player.ContactCooldown, g.contact * dmgMult, "élites")
			end
		end
		if boss then
			add(bigExp / Run.Player.ContactCooldown, bossDef.contactDamage, "boss")
			for _, a in bossDef.attacks do
				if a.minPhase <= 1 and a.damage then
					local cd = math.max(a.cooldown, Bosses.GlobalAttackGap * #bossDef.attacks)
					local dodge = if a.kind == "Ring" then AVG.ringDodge else AVG.telegraphDodge
					local n = if a.kind == "MultiCircle" then 1 else 1
					add(n * (1 - dodge) / cd, a.damage, "boss")
				end
			end
		end
		local passive = Weapons.Passives[pl.class]
		for _, hit in incoming do
			local amount, src = hit[1], hit[2]
			if passive.parryEvery and t >= pl.parryReadyAt then
				pl.parryReadyAt = t + passive.parryEvery
			elseif math.random() < math.clamp(b.Dodge, 0, Run.Player.DodgeCap) then
				-- esquive
			else
				local d = amount * Run.Player.ArmorK / (Run.Player.ArmorK + math.max(0, b.Armor))
				pl.hp -= d
				dmgTaken += d
				SRCDMG[src] = (SRCDMG[src] or 0) + d
			end
		end
		pl.hp = math.min(b.MaxHp, pl.hp + b.Regen * DT)
		if not pl.merchantUsed and t >= AVG.merchantHeal.at and pl.hp < b.MaxHp * AVG.merchantHeal.below then
			pl.merchantUsed = true
			pl.hp = math.min(b.MaxHp, pl.hp + b.MaxHp * Loot.MerchantHealFraction)
		end

		-- Niveaux (le jeu se fige : pas de temps qui passe)
		while pl.xp >= Cards.xpToNext(pl.level) and pl.level < Cards.Xp.MaxLevel do
			pl.xp -= Cards.xpToNext(pl.level)
			pl.level += 1
			pl.levelAt[pl.level] = t
			levelUp(pl, t)
		end

		if t % 60 == 0 then
			table.insert(log, { t = t, alive = alive, hp = enemyHp, near = near, level = pl.level, php = pl.hp, kills = kills, dps = (crowdDamage / DT) })
		end

		if pl.hp <= 0 then
			return { win = false, t = t, pl = pl, log = log, kills = kills, dmgTaken = dmgTaken, bossLeft = boss and boss.hp / boss.max }
		end
		if boss and boss.hp <= 0 then
			return { win = true, t = t, pl = pl, log = log, kills = kills, dmgTaken = dmgTaken, hpLeft = pl.hp / b.MaxHp, bossTime = t - boss.start }
		end
		if boss and t - boss.start > AVG.bossTimeout then
			return { win = false, t = t, pl = pl, log = log, kills = kills, dmgTaken = dmgTaken, bossLeft = boss.hp / boss.max, timeout = true }
		end
		t += DT
	end
end

-- Rapport -----------------------------------------------------------------------------------------
local function fmt(sec)
	if not sec then
		return "  -  "
	end
	return string.format("%d:%02d", sec // 60, math.floor(sec % 60))
end

local function median(list)
	if #list == 0 then
		return nil
	end
	table.sort(list)
	return list[math.ceil(#list / 2)]
end

math.randomseed(SEED)
local MILESTONES = { 2, 5, 10, 15, 20, 25, 30 }
print(string.format("A04-12 modèle monde 1 : %d runs par classe, graine %d", RUNS, SEED))
for _, classId in { "Knight", "Archer", "Mage" } do
	local wins, timeouts = 0, 0
	SRCDMG = {}
	MINITIMES = {}
	local deathsAt = {}
	local hpLeft = {}
	local bossTimes = {}
	local firstWeapon = {}
	local lvAt = {}
	local finalLevel = {}
	local kills = {}
	local perMinute = {}
	for _ = 1, RUNS do
		local r = simulate(classId)
		if r.win then
			wins += 1
			table.insert(hpLeft, r.hpLeft)
			table.insert(bossTimes, r.bossTime)
		else
			if r.timeout then
				timeouts += 1
			end
			table.insert(deathsAt, r.t)
		end
		table.insert(firstWeapon, r.pl.firstNewWeaponAt or 9999)
		table.insert(finalLevel, r.pl.level)
		table.insert(kills, r.kills)
		for _, m in MILESTONES do
			lvAt[m] = lvAt[m] or {}
			table.insert(lvAt[m], r.pl.levelAt[m] or 9999)
		end
		for i, row in r.log do
			perMinute[i] = perMinute[i] or { n = 0, alive = 0, hp = 0, near = 0, level = 0, php = 0, dps = 0 }
			local p = perMinute[i]
			p.n += 1
			p.t = row.t
			for key in { alive = 0, hp = 0, near = 0, level = 0, php = 0, dps = 0 } do
				p[key] += row[key]
			end
		end
	end
	print("")
	print(string.format("== %s : victoire %d %% (%d/%d), dont %d boss trop longs", classId, math.round(wins / RUNS * 100), wins, RUNS, timeouts))
	local fw = median(table.clone(firstWeapon))
	local before90 = 0
	for _, x in firstWeapon do
		if x <= 90 then
			before90 += 1
		end
	end
	print(string.format("   1re arme en plus : médiane %s, avant 1:30 dans %d %% des runs", fmt(if fw < 9999 then fw else nil), math.round(before90 / RUNS * 100)))
	local line = "   niveaux (médiane) :"
	for _, m in MILESTONES do
		local v = median(table.clone(lvAt[m]))
		line ..= string.format(" N%d %s", m, fmt(if v < 9999 then v else nil))
	end
	print(line)
	print(string.format("   niveau final médian %d ; KO médians %d ; PV restants médians (victoires) %s ; boss tué en %s ; morts : médiane %s",
		median(table.clone(finalLevel)), math.round(median(table.clone(kills))),
		if #hpLeft > 0 then string.format("%d %%", math.round(median(table.clone(hpLeft)) * 100)) else "-",
		fmt(median(table.clone(bossTimes))), fmt(median(table.clone(deathsAt)))))
	local srcLine, srcTotal = "   dégâts reçus :", 0
	for _, v in SRCDMG do
		srcTotal += v
	end
	for src, v in SRCDMG do
		srcLine ..= string.format(" %s %d %% (%d PV/run)", src, math.round(v / srcTotal * 100), math.round(v / RUNS))
	end
	print(srcLine)
	print(string.format("   mini-boss tués : %d, en %s (médiane)", #MINITIMES, fmt(median(table.clone(MINITIMES)))))
	print("   min | vivants | PV ennemi | foule | niveau | PV joueur | dps foule  (moyennes des runs encore en vie)")
	for _, p in perMinute do
		print(string.format("   %3d | %7d | %9.1f | %5.1f | %6.1f | %9.0f | %8.0f  (%d runs)", p.t // 60, math.round(p.alive / p.n), p.hp / p.n, p.near / p.n, p.level / p.n, p.php / p.n, p.dps / p.n, p.n))
	end
end
