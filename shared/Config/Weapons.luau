--!strict
-- The 16 weapons, their levels 2..8 and fusions (level 9), plus class passive numbers.
-- Dossier: docs/dossier/10-combat-armes-grimoires-objets.md, sections 5 and 8.
--
-- Stat keys (all numbers):
--   damage (per hit) · cooldown (s) · radius (hit radius / area, studs) · amount · speed (studs/s)
--   life (s, projectile) · pierce (enemies per projectile, -1 = infinite) · range (targeting, studs)
--   duration (s, active time) · interval (s, tick or fire interval) · angle (degrees, cones/spread)
--   bounces · bounceRange · critChance · critDamage · knockback · statusDps · statusDuration
--   statusMult · turrets · darts · orbitRadius · spin (rad/s) · outTime (s) · delay (s) · charges
--   volleys · volleyDelay · dmgMult ("more" factor) · armorDamage (per Armor point)
--   Fusion flags (1 = on): follow, permanent, chainOnCrit (count), xpOnKill, lifesteal (fraction),
--   lifestealCap (HP/s), splitOnEnd (count), cluster (count), clusterDamage, popRadius, autoWave
-- Level deltas add to the key, except keys ending in "Pct", which add to the multiplier of the
-- key without the suffix (radiusPct = 0.15 => radius x1.15 cumulative with other Pct deltas).

export type Stats = { [string]: number }

export type WeaponDef = {
	id: string,
	index: number, -- wire index for WeaponFx (1..16)
	kind: string, -- behaviour in WeaponService
	status: string?, -- EnemyService.applyStatus kind
	name: { fr: string, en: string },
	desc: { fr: string, en: string },
	scaling: { string }, -- StatNames that make it shine (shown on cards)
	base: Stats,
	levels: { Stats }, -- [1] = level 2 ... [7] = level 8
	fusion: {
		grimoire: string,
		minGrimoireLevel: number,
		name: { fr: string, en: string },
		desc: { fr: string, en: string },
		delta: Stats,
	},
}

local Weapons = {}

Weapons.MaxLevel = 8
Weapons.FusionLevel = 9

Weapons.Order = {
	"HacheBoomerang",
	"PlumesDards",
	"CleTourelle",
	"GriffesEclair",
	"PoingSeisme",
	"NuageSpores",
	"SouffleBraise",
	"Meteorite",
	"EclatsPrisme",
	"FouetTentacule",
	"ToupieScie",
	"BouleBowling",
	"CerfVolantLaser",
	"ParapluieBouclier",
	"BombePaillettes",
	"PistoletBulles",
} :: { string }

-- Class -> start weapon (ARCHITECTURE.md section 3)
Weapons.StartWeapon = {
	Cornu = "HacheBoomerang",
	Plumeline = "PlumesDards",
	Mecano = "CleTourelle",
	Felyne = "GriffesEclair",
	Rocailleux = "PoingSeisme",
	Sporelin = "NuageSpores",
	Ecaille = "SouffleBraise",
	Astrel = "Meteorite",
	Cristallin = "EclatsPrisme",
	Tentaculos = "FouetTentacule",
} :: { [string]: string }

-- Global simulation numbers
Weapons.Sim = {
	EnemyPad = 1.3, -- added to hit radii (enemies are about 1.2-1.4 studs wide)
	MinCooldown = 0.15,
	MaxProjectiles = 400,
	MaxZones = 96,
	MaxHitsPerTick = 600, -- server-wide damage calls per sim tick before weapons wait
	TargetRange = 40, -- default nearest-enemy search
}

local defs: { WeaponDef } = {
	{
		id = "HacheBoomerang",
		index = 1,
		kind = "Boomerang",
		name = { fr = "Hache-boomerang", en = "Boomerang Axe" },
		desc = { fr = "Aller-retour qui transperce", en = "Flies out and back, piercing" },
		scaling = { "Size", "Amount" },
		base = { damage = 14, cooldown = 1.5, radius = 1.8, amount = 1, speed = 34, outTime = 0.55, life = 2.5, pierce = -1, range = 40 },
		levels = {
			{ amount = 1 },
			{ damage = 6 },
			{ radiusPct = 0.15 },
			{ amount = 1 },
			{ damage = 6 },
			{ cooldownPct = -0.10 },
			{ amount = 1, damage = 8 },
		},
		fusion = {
			grimoire = "Taille",
			minGrimoireLevel = 5,
			name = { fr = "Hache Tempête", en = "Storm Axe" },
			desc = { fr = "×1,5 dégâts, +2 haches, +30 % zone", en = "x1.5 damage, +2 axes, +30% area" },
			delta = { dmgMult = 0.5, amount = 2, radiusPct = 0.30 },
		},
	},
	{
		id = "PlumesDards",
		index = 2,
		kind = "Shot",
		name = { fr = "Plumes-dards", en = "Feather Darts" },
		desc = { fr = "Rafale vers l'ennemi le plus proche", en = "Volley at the nearest enemy" },
		scaling = { "Amount", "AttackSpeed" },
		base = { damage = 8, cooldown = 1.1, radius = 0.8, amount = 2, speed = 70, life = 0.8, pierce = 1, angle = 8, range = 45, volleys = 1, volleyDelay = 0.2 },
		levels = {
			{ amount = 1 },
			{ damage = 3 },
			{ pierce = 1 },
			{ amount = 1 },
			{ cooldownPct = -0.10 },
			{ damage = 3 },
			{ amount = 2 },
		},
		fusion = {
			grimoire = "VitesseAttaque",
			minGrimoireLevel = 5,
			name = { fr = "Rafale d'Aigle", en = "Eagle Volley" },
			desc = { fr = "2 salves, +2 perce, ×1,3 dégâts", en = "2 volleys, +2 pierce, x1.3 damage" },
			delta = { volleys = 1, pierce = 2, dmgMult = 0.3 },
		},
	},
	{
		id = "CleTourelle",
		index = 3,
		kind = "Turret",
		name = { fr = "Clé-tourelle", en = "Wrench Turret" },
		desc = { fr = "Pose une tourelle qui tire seule", en = "Drops a turret that shoots on its own" },
		scaling = { "Duration", "Amount" },
		base = { damage = 7, cooldown = 6, duration = 8, interval = 0.8, turrets = 1, darts = 1, speed = 60, life = 0.7, radius = 0.7, pierce = 1, range = 35, angle = 10 },
		levels = {
			{ damage = 3 },
			{ duration = 2 },
			{ intervalPct = -0.15 },
			{ turrets = 1 },
			{ damage = 3 },
			{ darts = 1 },
			{ turrets = 1, damage = 3 },
		},
		fusion = {
			grimoire = "Quantite",
			minGrimoireLevel = 5,
			name = { fr = "Atelier Volant", en = "Flying Workshop" },
			desc = { fr = "Les tourelles te suivent, +1 dard, ×1,3 dégâts", en = "Turrets follow you, +1 dart, x1.3 damage" },
			delta = { follow = 1, darts = 1, dmgMult = 0.3 },
		},
	},
	{
		id = "GriffesEclair",
		index = 4,
		kind = "Cone",
		name = { fr = "Griffes éclair", en = "Lightning Claws" },
		desc = { fr = "Coup en cône devant soi", en = "Cone strike in front" },
		scaling = { "CritChance" },
		base = { damage = 18, cooldown = 1.0, radius = 7, angle = 100, amount = 1, critChance = 0.10, volleyDelay = 0.15, range = 12 },
		levels = {
			{ damage = 5 },
			{ radiusPct = 0.15 },
			{ critChance = 0.05 },
			{ amount = 1 },
			{ damage = 6 },
			{ cooldownPct = -0.10 },
			{ critDamage = 0.5, damage = 6 },
		},
		fusion = {
			grimoire = "Critique",
			minGrimoireLevel = 5,
			name = { fr = "Griffe Foudroyante", en = "Thunder Claw" },
			desc = { fr = "Les critiques font sauter un éclair sur 3 ennemis", en = "Crits arc lightning to 3 enemies" },
			delta = { chainOnCrit = 3, dmgMult = 0.3 },
		},
	},
	{
		id = "PoingSeisme",
		index = 5,
		kind = "Nova",
		name = { fr = "Poing-séisme", en = "Quake Fist" },
		desc = { fr = "Onde circulaire au sol", en = "Circular ground wave" },
		scaling = { "Size", "Armor" },
		base = { damage = 20, cooldown = 2.5, radius = 9, amount = 1, knockback = 8, armorDamage = 0.01, volleyDelay = 0.3 },
		levels = {
			{ damage = 6 },
			{ radiusPct = 0.15 },
			{ cooldownPct = -0.10 },
			{ amount = 1 },
			{ damage = 8 },
			{ radiusPct = 0.15 },
			{ damage = 10, statusDuration = 0.3 },
		},
		fusion = {
			grimoire = "Rempart",
			minGrimoireLevel = 5,
			name = { fr = "Faille Tellurique", en = "Tectonic Rift" },
			desc = { fr = "+2 % dégâts par armure, étourdit 0,6 s", en = "+2% damage per armor, stuns 0.6 s" },
			delta = { armorDamage = 0.01, statusDuration = 0.3, dmgMult = 0.3 },
		},
	},
	{
		id = "NuageSpores",
		index = 6,
		kind = "Cloud",
		status = "Poison",
		name = { fr = "Nuage de spores", en = "Spore Cloud" },
		desc = { fr = "Nappe de poison qui te suit", en = "Poison cloud that follows you" },
		scaling = { "Duration", "Size" },
		base = { damage = 4, cooldown = 5, duration = 3.5, interval = 0.5, radius = 6, amount = 1, statusDps = 3, statusDuration = 3 },
		levels = {
			{ damage = 2 },
			{ duration = 1 },
			{ radiusPct = 0.15 },
			{ statusDps = 3 },
			{ amount = 1 },
			{ duration = 1 },
			{ damage = 3, radiusPct = 0.20 },
		},
		fusion = {
			grimoire = "Aimant",
			minGrimoireLevel = 5,
			name = { fr = "Marée de Spores", en = "Spore Tide" },
			desc = { fr = "+40 % zone, ralentit de 50 %, ×1,4 dégâts", en = "+40% area, slows 50%, x1.4 damage" },
			delta = { radiusPct = 0.40, statusMult = 0.5, dmgMult = 0.4 },
		},
	},
	{
		id = "SouffleBraise",
		index = 7,
		kind = "Cone",
		status = "Burn",
		name = { fr = "Souffle de braise", en = "Ember Breath" },
		desc = { fr = "Lance-flamme court qui brûle", en = "Short flamethrower that burns" },
		scaling = { "AttackSpeed" },
		base = { damage = 6, cooldown = 0.45, radius = 9, angle = 50, amount = 1, statusDps = 4, statusDuration = 3, volleyDelay = 0.1, range = 14 },
		levels = {
			{ damage = 2 },
			{ radiusPct = 0.15 },
			{ statusDps = 3 },
			{ cooldownPct = -0.10 },
			{ damage = 3 },
			{ angle = 20 },
			{ statusDps = 4, radiusPct = 0.15 },
		},
		fusion = {
			grimoire = "Degats",
			minGrimoireLevel = 5,
			name = { fr = "Souffle du Dragon", en = "Dragon Breath" },
			desc = { fr = "+60 % portée, cône 90°, brûlure ×2", en = "+60% range, 90° cone, burn x2" },
			delta = { radiusPct = 0.60, angle = 20, statusDpsPct = 1.0, dmgMult = 0.3 },
		},
	},
	{
		id = "Meteorite",
		index = 8,
		kind = "Strike",
		name = { fr = "Météorite", en = "Meteorite" },
		desc = { fr = "Chute sur une grande zone", en = "Falls on a wide area" },
		scaling = { "Luck", "Size" },
		base = { damage = 40, cooldown = 3.0, radius = 7, amount = 1, delay = 0.7, range = 35, luckExtra = 0.01 },
		levels = {
			{ damage = 12 },
			{ amount = 1 },
			{ radiusPct = 0.15 },
			{ damage = 15 },
			{ cooldownPct = -0.10 },
			{ amount = 1 },
			{ damage = 20, radiusPct = 0.20 },
		},
		fusion = {
			grimoire = "Chance",
			minGrimoireLevel = 5,
			name = { fr = "Pluie d'Étoiles", en = "Star Shower" },
			desc = { fr = "+3 météores, +1 % critique par Chance", en = "+3 meteors, +1% crit per Luck" },
			delta = { amount = 3, luckCrit = 0.01 },
		},
	},
	{
		id = "EclatsPrisme",
		index = 9,
		kind = "Chain",
		name = { fr = "Éclats de prisme", en = "Prism Shards" },
		desc = { fr = "Rebondit entre les ennemis", en = "Bounces between enemies" },
		scaling = { "Bounces", "CritChance" },
		base = { damage = 11, cooldown = 1.3, range = 30, bounces = 2, bounceRange = 12, amount = 1, critChance = 0.05 },
		levels = {
			{ bounces = 1 },
			{ damage = 4 },
			{ amount = 1 },
			{ bounces = 1 },
			{ damage = 5 },
			{ cooldownPct = -0.10 },
			{ bounces = 2, damage = 5 },
		},
		fusion = {
			grimoire = "Savoir",
			minGrimoireLevel = 5,
			name = { fr = "Prisme du Savant", en = "Scholar Prism" },
			desc = { fr = "+3 rebonds, chaque ennemi tué donne +1 XP", en = "+3 bounces, each kill gives +1 XP" },
			delta = { bounces = 3, xpOnKill = 1 },
		},
	},
	{
		id = "FouetTentacule",
		index = 10,
		kind = "Nova",
		name = { fr = "Fouet-tentacule", en = "Tentacle Whip" },
		desc = { fr = "Balayage à 360°", en = "360° sweep" },
		scaling = { "Size" },
		base = { damage = 15, cooldown = 1.8, radius = 8, amount = 1, knockback = 6, volleyDelay = 0.25 },
		levels = {
			{ damage = 5 },
			{ radiusPct = 0.15 },
			{ amount = 1 },
			{ damage = 6 },
			{ radiusPct = 0.15 },
			{ cooldownPct = -0.10 },
			{ damage = 8, radiusPct = 0.20 },
		},
		fusion = {
			grimoire = "Vitalite",
			minGrimoireLevel = 5,
			name = { fr = "Kraken Tourbillon", en = "Kraken Swirl" },
			desc = { fr = "+1 balayage, soigne 2 % des dégâts", en = "+1 sweep, heals 2% of damage dealt" },
			delta = { amount = 1, lifesteal = 0.02, lifestealCap = 5 },
		},
	},
	{
		id = "ToupieScie",
		index = 11,
		kind = "Orbit",
		name = { fr = "Toupie à scie", en = "Saw Top" },
		desc = { fr = "Des scies tournent autour de toi", en = "Saws orbit around you" },
		scaling = { "Amount", "AttackSpeed" },
		base = { damage = 8, cooldown = 5, duration = 4, amount = 2, orbitRadius = 5, radius = 1.3, spin = 4, interval = 0.5 },
		levels = {
			{ amount = 1 },
			{ damage = 3 },
			{ duration = 1 },
			{ amount = 1 },
			{ radiusPct = 0.15, orbitRadiusPct = 0.15 },
			{ damage = 3, spinPct = 0.25 },
			{ amount = 1, duration = 1 },
		},
		fusion = {
			grimoire = "Agilite",
			minGrimoireLevel = 5,
			name = { fr = "Tornade d'Acier", en = "Steel Tornado" },
			desc = { fr = "Scies permanentes, +2 scies, vitesse ×1,5", en = "Permanent saws, +2 saws, x1.5 spin" },
			delta = { permanent = 1, amount = 2, spinPct = 0.5 },
		},
	},
	{
		id = "BouleBowling",
		index = 12,
		kind = "Shot",
		name = { fr = "Boule de bowling", en = "Bowling Ball" },
		desc = { fr = "Roule et renverse tout", en = "Rolls through everything" },
		scaling = { "Size", "Damage" },
		base = { damage = 25, cooldown = 2.2, radius = 2.2, amount = 1, speed = 26, life = 2.5, pierce = -1, knockback = 10, angle = 20, range = 40, volleys = 1, volleyDelay = 0.2 },
		levels = {
			{ damage = 8 },
			{ radiusPct = 0.15 },
			{ amount = 1 },
			{ damage = 10 },
			{ life = 0.5 },
			{ amount = 1 },
			{ damage = 12, radiusPct = 0.20 },
		},
		fusion = {
			grimoire = "Taille",
			minGrimoireLevel = 5,
			name = { fr = "Boule Titanesque", en = "Titan Ball" },
			desc = { fr = "Taille ×2, se divise en 3 en fin de course", en = "x2 size, splits into 3 at the end" },
			delta = { radiusPct = 1.0, splitOnEnd = 3 },
		},
	},
	{
		id = "CerfVolantLaser",
		index = 13,
		kind = "Beam",
		name = { fr = "Cerf-volant laser", en = "Laser Kite" },
		desc = { fr = "Un rayon qui suit le joueur", en = "A beam that follows you" },
		scaling = { "Duration" },
		base = { damage = 5, cooldown = 5, duration = 3, interval = 0.25, range = 28, radius = 1.5, amount = 1 },
		levels = {
			{ damage = 2 },
			{ duration = 1 },
			{ rangePct = 0.15 },
			{ amount = 1 },
			{ damage = 2 },
			{ duration = 1 },
			{ damage = 3, cooldownPct = -0.15 },
		},
		fusion = {
			grimoire = "Duree",
			minGrimoireLevel = 5,
			name = { fr = "Comète de Papier", en = "Paper Comet" },
			desc = { fr = "Rayon permanent, +1 rayon, ×1,3 dégâts", en = "Permanent beam, +1 beam, x1.3 damage" },
			delta = { permanent = 1, amount = 1, dmgMult = 0.3 },
		},
	},
	{
		id = "ParapluieBouclier",
		index = 14,
		kind = "Shield",
		name = { fr = "Parapluie-bouclier", en = "Umbrella Shield" },
		desc = { fr = "Bloque un coup et renvoie une onde", en = "Blocks a hit and sends a wave" },
		scaling = { "Cooldown" },
		base = { damage = 30, cooldown = 12, radius = 10, charges = 1, knockback = 12, invuln = 0.5 },
		levels = {
			{ damage = 10 },
			{ cooldownPct = -0.10 },
			{ radiusPct = 0.15 },
			{ charges = 1 },
			{ damage = 12 },
			{ cooldownPct = -0.10 },
			{ damage = 15, charges = 1 },
		},
		fusion = {
			grimoire = "Cooldown",
			minGrimoireLevel = 5,
			name = { fr = "Grand Chapiteau", en = "Big Top" },
			desc = { fr = "L'onde part aussi seule à chaque recharge, zone ×2", en = "Wave also fires on every recharge, x2 area" },
			delta = { autoWave = 1, radiusPct = 1.0 },
		},
	},
	{
		id = "BombePaillettes",
		index = 15,
		kind = "Strike",
		status = "Stun",
		name = { fr = "Bombe à paillettes", en = "Glitter Bomb" },
		desc = { fr = "Explosion qui aveugle", en = "Blinding explosion" },
		scaling = { "Size", "Amount" },
		base = { damage = 22, cooldown = 2.6, radius = 6, amount = 1, delay = 0.8, range = 25, statusDuration = 0.8 },
		levels = {
			{ damage = 7 },
			{ radiusPct = 0.15 },
			{ amount = 1 },
			{ statusDuration = 0.4 },
			{ damage = 8 },
			{ amount = 1 },
			{ damage = 10, radiusPct = 0.20 },
		},
		fusion = {
			grimoire = "Quantite",
			minGrimoireLevel = 5,
			name = { fr = "Feu d'Artifice Géant", en = "Grand Fireworks" },
			desc = { fr = "Chaque bombe éclate en 4 mini-bombes", en = "Each bomb bursts into 4 mini bombs" },
			delta = { cluster = 4, clusterDamage = 0.4 },
		},
	},
	{
		id = "PistoletBulles",
		index = 16,
		kind = "Shot",
		status = "Freeze",
		name = { fr = "Pistolet à bulles", en = "Bubble Blaster" },
		desc = { fr = "Des bulles qui emprisonnent 1 s", en = "Bubbles that trap for 1 s" },
		scaling = { "Amount" },
		base = { damage = 9, cooldown = 1.2, radius = 1.2, amount = 1, speed = 30, life = 1.6, pierce = 1, angle = 15, statusDuration = 1, range = 40, volleys = 1, volleyDelay = 0.2 },
		levels = {
			{ amount = 1 },
			{ damage = 3 },
			{ statusDuration = 0.3 },
			{ amount = 1 },
			{ damage = 4 },
			{ cooldownPct = -0.10 },
			{ amount = 2 },
		},
		fusion = {
			grimoire = "Interdit",
			minGrimoireLevel = 5,
			name = { fr = "Bulles Cosmiques", en = "Cosmic Bubbles" },
			desc = { fr = "Les bulles explosent en éclatant, ×1,3 dégâts", en = "Bubbles explode when they pop, x1.3 damage" },
			delta = { popRadius = 6, dmgMult = 0.3 },
		},
	},
}

Weapons.List = defs
Weapons.Defs = {} :: { [string]: WeaponDef }
Weapons.ByIndex = {} :: { [number]: WeaponDef }
for _, def in defs do
	Weapons.Defs[def.id] = def
	Weapons.ByIndex[def.index] = def
end

-- Class passives (dossier 10, section 8). Read by StatsService (stats), WeaponService and
-- PassiveService (triggers). Passive id = class id.
Weapons.Passives = {
	Cornu = {
		name = { fr = "Bélier", en = "Ram" },
		chargeSpeed = 21, -- studs/s on the ground
		chargeRadius = 3.5,
		chargeDamage = 10,
		chargeKnockback = 10,
		chargeHitCooldown = 1,
		stackDamage = 0.005,
		maxStacks = 150,
	},
	Plumeline = {
		name = { fr = "Vent arrière", en = "Tailwind" },
		airDamage = 0.25,
	},
	Mecano = {
		name = { fr = "Bricoleur", en = "Tinkerer" },
		shrineSpeed = 0.35, -- read by ShrineService (class check)
		turretsFromAmount = 1,
	},
	Felyne = {
		name = { fr = "Élan", en = "Momentum" },
		jumps = 5,
		radius = 10,
		damage = 30,
	},
	Rocailleux = {
		name = { fr = "Bouclier vivant", en = "Living Shield" },
		perLevel = { Armor = 3 },
		flat = { Thorns = 0.30 },
	},
	Sporelin = {
		name = { fr = "Contagion", en = "Contagion" },
		spreadRadius = 8,
		spreadCount = 6,
		spreadDps = 4,
		spreadDuration = 3,
	},
	Ecaille = {
		name = { fr = "Combustion", en = "Combustion" },
		burnDuration = 2,
		burnMaxStacks = 999,
	},
	Astrel = {
		name = { fr = "Bonne étoile", en = "Lucky Star" },
		perLevel = { Luck = 1 },
		rareEveryOffers = 5,
	},
	Cristallin = {
		name = { fr = "Croissance", en = "Growth" },
		perLevel = { Size = 0.02 },
	},
	Tentaculos = {
		name = { fr = "Multitâche", en = "Multitask" },
		extraWeaponSlots = 1,
		damageMore = 0.9,
	},
} :: { [string]: { [string]: any } }

-- Thorns rule shared by every player (Rocailleux uses it with Thorns 0.3)
Weapons.Thorns = { radius = 6, targets = 3 }

-- Default burn/poison stacking when no passive changes it
Weapons.DefaultMaxStacks = 1

-- Cumulative stats at a level (1..8, 9 = fusion). Cached; never mutate the result.
local cache: { [string]: { [number]: Stats } } = {}

local function applyDelta(stats: Stats, mults: Stats, delta: Stats)
	for k, v in delta do
		if string.sub(k, -3) == "Pct" then
			local key = string.sub(k, 1, -4)
			mults[key] = (mults[key] or 1) + v
		else
			stats[k] = (stats[k] or 0) + v
		end
	end
end

function Weapons.statsAt(id: string, level: number): Stats
	local byLevel = cache[id]
	if not byLevel then
		byLevel = {}
		cache[id] = byLevel
	end
	local lvl = math.clamp(math.floor(level), 1, Weapons.FusionLevel)
	local hit = byLevel[lvl]
	if hit then
		return hit
	end
	local def = Weapons.Defs[id]
	assert(def, `unknown weapon {id}`)
	local stats: Stats = table.clone(def.base)
	local mults: Stats = {}
	for l = 2, math.min(lvl, Weapons.MaxLevel) do
		applyDelta(stats, mults, def.levels[l - 1])
	end
	if lvl >= Weapons.FusionLevel then
		applyDelta(stats, mults, def.fusion.delta)
	end
	for key, m in mults do
		stats[key] = (stats[key] or 0) * m
	end
	stats.dmgMult = 1 + (stats.dmgMult or 0)
	table.freeze(stats)
	byLevel[lvl] = stats
	return stats
end

return Weapons
