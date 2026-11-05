--!strict
-- Les 16 armes v2 (8 de départ + 8 du pool commun), leurs niveaux 2..8, les passifs des 8 classes
-- et le style visuel provisoire de chaque arme (WeaponFX, pièces simples en attendant la vague 2).
-- Décisions : docs/dossier/01-decisions-v2.md sections 3 et 4. Détail : dossier 10 sections 5 et 8.
-- Toutes les armes sont équipables par toutes les classes ; 4 emplacements (méta : jusqu'à 6).
--
-- Clés de stats (nombres) :
--   damage (par coup) · cooldown (s) · radius (rayon de touche ou de zone, studs) · amount · speed (studs/s)
--   life (s, projectile) · pierce (ennemis par projectile, -1 = infini) · range (ciblage, studs)
--   duration (s, temps actif) · interval (s, cadence de tick ou de tir) · angle (degrés, cône ou éventail)
--   bounces · bounceRange · critChance · critDamage · knockback · statusDps · statusDuration
--   statusMult (ralentissement, 0.5 = moitié de vitesse) · turrets · darts · orbitRadius · spin (rad/s)
--   outTime (s) · delay (s) · charges · volleys · volleyDelay · dmgMult (facteur « plus ») · armorDamage
--   popRadius (explosion au premier impact) · endBlast (1 = explose aussi en fin de course)
--   permanent (1 = zone permanente) · swingBack (1 = un coup sur deux part derrière)
--   follow, chainOnCrit, xpOnKill, lifesteal, lifestealCap, splitOnEnd, cluster, clusterDamage, autoWave
-- Les deltas de niveau s'ajoutent à la clé, sauf les clés en « Pct » qui s'ajoutent au multiplicateur
-- de la clé sans suffixe (radiusPct = 0.15 => rayon x1,15, cumulé avec les autres deltas Pct).
--
-- Fusions (A04-09) : en attente de la confirmation de Clément. `FusionEnabled = false` : aucune carte
-- de fusion n'est proposée. Le moteur (niveau 9 = base + niveaux + fusion.delta) reste en place.

export type Stats = { [string]: number }

-- Style visuel provisoire (client/Controllers/WeaponFX.luau). Tout est optionnel sauf shape/color/size.
export type FxStyle = {
	shape: "Block" | "Ball" | "Cylinder",
	color: Color3,
	size: Vector3, -- taille de base d'un projectile ou d'une pièce, en studs
	projDiv: number?, -- le serveur envoie le rayon de touche comme échelle : taille / projDiv
	spin: boolean?, -- le projectile tourne sur lui-même
	rolls: boolean?, -- le projectile roule au sol
	boomerang: boolean?, -- le client imite l'aller-retour
	orbit: boolean?, -- attache : une pièce par élément, en orbite
	aura: boolean?, -- attache : disque plat au sol, du rayon de la zone
	beamHeight: number?, -- segment : hauteur de départ (studs au-dessus du sol)
}

export type WeaponDef = {
	id: string,
	index: number, -- index réseau pour WeaponFx (1..16)
	kind: string, -- comportement dans WeaponService
	pool: "Start" | "Common",
	status: string?, -- statut EnemyService.applyStatus
	unlock: string?, -- "Free" (défaut) : toujours dans le tirage de cartes
	name: { fr: string, en: string },
	desc: { fr: string, en: string },
	scaling: { string }, -- StatNames qui la font briller (affichés sur les cartes)
	base: Stats,
	levels: { Stats }, -- [1] = niveau 2 ... [7] = niveau 8
	fx: FxStyle,
	fusion: {
		grimoire: string,
		minGrimoireLevel: number,
		name: { fr: string, en: string },
		desc: { fr: string, en: string },
		delta: Stats,
	}?,
}

local Weapons = {}

Weapons.MaxLevel = 8
Weapons.FusionLevel = 9
Weapons.FusionEnabled = false -- A04-09 : attend la confirmation de Clément

Weapons.Order = {
	-- Armes de départ (une par classe, dans l'ordre des classes)
	"Broadsword",
	"Longbow",
	"FireStaff",
	"QuakeHammer",
	"ThrowingDaggers",
	"HolyAura",
	"SpinningAxes",
	"BeastWhip",
	-- Pool commun
	"LightningChain",
	"FrostNova",
	"Boomerang",
	"BombBag",
	"SpearThrow",
	"MeteorRain",
	"OrbitingBlades",
	"CrossbowTurret",
} :: { string }

-- Nombres globaux de la simulation
Weapons.Sim = {
	EnemyPad = 1.3, -- ajouté aux rayons de touche (un ennemi fait 1,2 à 1,4 stud de large)
	MinCooldown = 0.15,
	MaxProjectiles = 400,
	MaxZones = 96,
	MaxHitsPerTick = 600, -- appels de dégâts par tick serveur avant que les armes attendent
	TargetRange = 40, -- recherche par défaut de l'ennemi le plus proche
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local defs: { WeaponDef } = {
	-- Armes de départ ------------------------------------------------------------------------
	{
		id = "Broadsword",
		index = 1,
		kind = "Cone",
		pool = "Start",
		name = { en = "Broadsword", fr = "Broadsword" },
		desc = { en = "Wide sword swing in front of you", fr = "Wide sword swing in front of you" },
		scaling = { "Size", "Damage" },
		base = { damage = 16, cooldown = 1.1, radius = 8, angle = 140, amount = 1, knockback = 4, volleyDelay = 0.18, range = 12, swingBack = 1 },
		levels = {
			{ damage = 5 },
			{ radiusPct = 0.15 },
			{ amount = 1 },
			{ damage = 6 },
			{ cooldownPct = -0.10 },
			{ angle = 40 },
			{ damage = 8, radiusPct = 0.15 },
		},
		fx = { shape = "Block", color = rgb(225, 230, 240), size = Vector3.new(1, 0.3, 1) },
	},
	{
		id = "Longbow",
		index = 2,
		kind = "Shot",
		pool = "Start",
		name = { en = "Longbow", fr = "Longbow" },
		desc = { en = "Auto-aimed arrows that pierce", fr = "Auto-aimed arrows that pierce" },
		scaling = { "Amount", "AttackSpeed" },
		base = { damage = 12, cooldown = 1.0, radius = 0.7, amount = 1, speed = 80, life = 1.0, pierce = 3, angle = 6, range = 55, volleys = 1, volleyDelay = 0.15 },
		levels = {
			{ amount = 1 },
			{ damage = 4 },
			{ pierce = 2 },
			{ volleys = 1 },
			{ damage = 5 },
			{ cooldownPct = -0.10 },
			{ amount = 1, pierce = 2 },
		},
		fx = { shape = "Block", color = rgb(250, 245, 220), size = Vector3.new(0.25, 0.25, 2.4) },
	},
	{
		id = "FireStaff",
		index = 3,
		kind = "Shot",
		pool = "Start",
		status = "Burn",
		name = { en = "Fire Staff", fr = "Fire Staff" },
		desc = { en = "Fireball that explodes in an area", fr = "Fireball that explodes in an area" },
		scaling = { "Size", "Damage" },
		-- A04-12 : 14 dég / 1,4 s -> 13 dég / 1,0 s. Le tir lent laissait la foule au contact : le Mage
		-- était la classe gratuite la plus fragile du modèle (3 % de victoires, contre 28 % au Knight).
		base = { damage = 13, cooldown = 1.0, radius = 1.0, amount = 1, speed = 42, life = 1.3, pierce = 1, angle = 12, range = 45, volleys = 1, volleyDelay = 0.2, popRadius = 5, endBlast = 1, statusDps = 4, statusDuration = 2 },
		levels = {
			{ damage = 4 },
			{ popRadiusPct = 0.20 },
			{ amount = 1 },
			{ statusDps = 3 },
			{ damage = 5 },
			{ cooldownPct = -0.10 },
			{ damage = 6, popRadiusPct = 0.25 },
		},
		fx = { shape = "Ball", color = rgb(255, 120, 30), size = Vector3.new(1.6, 1.6, 1.6), projDiv = 1 },
	},
	{
		id = "QuakeHammer",
		index = 4,
		kind = "Nova",
		pool = "Start",
		status = "Stun",
		name = { en = "Quake Hammer", fr = "Quake Hammer" },
		desc = { en = "Shockwave on the ground around you", fr = "Shockwave on the ground around you" },
		scaling = { "Size", "Armor" },
		base = { damage = 22, cooldown = 2.4, radius = 9, amount = 1, knockback = 8, armorDamage = 0.01, volleyDelay = 0.3, statusDuration = 0 },
		levels = {
			{ damage = 6 },
			{ radiusPct = 0.15 },
			{ cooldownPct = -0.10 },
			{ amount = 1 },
			{ damage = 8 },
			{ radiusPct = 0.15 },
			{ damage = 10, statusDuration = 0.3 },
		},
		fx = { shape = "Cylinder", color = rgb(165, 120, 75), size = Vector3.new(0.3, 1, 1) },
	},
	{
		id = "ThrowingDaggers",
		index = 5,
		kind = "Shot",
		pool = "Start",
		name = { en = "Throwing Daggers", fr = "Throwing Daggers" },
		desc = { en = "Fan of daggers at the nearest enemy", fr = "Fan of daggers at the nearest enemy" },
		scaling = { "Amount", "AttackSpeed" },
		base = { damage = 7, cooldown = 0.9, radius = 0.6, amount = 3, speed = 65, life = 0.6, pierce = 1, angle = 14, range = 35, volleys = 1, volleyDelay = 0.15 },
		levels = {
			{ amount = 1 },
			{ damage = 3 },
			{ pierce = 1 },
			{ amount = 1 },
			{ cooldownPct = -0.12 },
			{ damage = 3 },
			{ amount = 2 },
		},
		fx = { shape = "Block", color = rgb(190, 200, 215), size = Vector3.new(0.2, 0.2, 1.2) },
	},
	{
		id = "HolyAura",
		index = 6,
		kind = "Cloud",
		pool = "Start",
		name = { en = "Holy Aura", fr = "Holy Aura" },
		desc = { en = "Glowing ring that burns nearby foes", fr = "Glowing ring that burns nearby foes" },
		scaling = { "Size", "Damage" },
		base = { damage = 5, cooldown = 1.0, duration = 1, interval = 0.5, radius = 6, amount = 1, permanent = 1 },
		levels = {
			{ damage = 2 },
			{ radiusPct = 0.15 },
			{ intervalPct = -0.15 },
			{ damage = 2 },
			{ radiusPct = 0.15 },
			{ damage = 3 },
			{ damage = 3, radiusPct = 0.20 },
		},
		fx = { shape = "Cylinder", color = rgb(255, 225, 110), size = Vector3.new(0.4, 1, 1), aura = true },
	},
	{
		id = "SpinningAxes",
		index = 7,
		kind = "Orbit",
		pool = "Start",
		name = { en = "Spinning Axes", fr = "Spinning Axes" },
		desc = { en = "Big axes orbit around you", fr = "Big axes orbit around you" },
		scaling = { "Amount", "Duration" },
		base = { damage = 10, cooldown = 5, duration = 3.5, amount = 2, orbitRadius = 6, radius = 1.6, spin = 3.5, interval = 0.4, knockback = 5 },
		levels = {
			{ amount = 1 },
			{ damage = 4 },
			{ duration = 1 },
			{ radiusPct = 0.15, orbitRadiusPct = 0.15 },
			{ amount = 1 },
			{ damage = 4, spinPct = 0.25 },
			{ amount = 1, duration = 1 },
		},
		fx = { shape = "Block", color = rgb(150, 105, 60), size = Vector3.new(2.4, 0.4, 1.4), orbit = true },
	},
	{
		id = "BeastWhip",
		index = 8,
		kind = "Nova",
		pool = "Start",
		name = { en = "Beast Whip", fr = "Beast Whip" },
		desc = { en = "360° whip crack", fr = "360° whip crack" },
		scaling = { "Size" },
		base = { damage = 15, cooldown = 1.7, radius = 8.5, amount = 1, knockback = 6, volleyDelay = 0.25 },
		levels = {
			{ damage = 5 },
			{ radiusPct = 0.15 },
			{ amount = 1 },
			{ damage = 6 },
			{ radiusPct = 0.15 },
			{ cooldownPct = -0.10 },
			{ damage = 8, radiusPct = 0.20 },
		},
		fx = { shape = "Cylinder", color = rgb(190, 90, 60), size = Vector3.new(0.3, 1, 1) },
	},
	-- Pool commun ------------------------------------------------------------------------------
	{
		id = "LightningChain",
		index = 9,
		kind = "Chain",
		pool = "Common",
		name = { en = "Lightning Chain", fr = "Lightning Chain" },
		desc = { en = "Bolt that jumps between enemies", fr = "Bolt that jumps between enemies" },
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
		fx = { shape = "Block", color = rgb(150, 220, 255), size = Vector3.new(0.35, 0.35, 1) },
	},
	{
		id = "FrostNova",
		index = 10,
		kind = "Nova",
		pool = "Common",
		status = "Freeze",
		name = { en = "Frost Nova", fr = "Frost Nova" },
		desc = { en = "Icy blast that slows everything around", fr = "Icy blast that slows everything around" },
		scaling = { "Size", "Duration" },
		base = { damage = 10, cooldown = 3.0, radius = 10, amount = 1, statusMult = 0.5, statusDuration = 0, volleyDelay = 0.3 },
		levels = {
			{ damage = 4 },
			{ radiusPct = 0.15 },
			{ statusDuration = 0.4 },
			{ cooldownPct = -0.10 },
			{ damage = 5 },
			{ radiusPct = 0.15 },
			{ damage = 6, statusDuration = 0.4 },
		},
		fx = { shape = "Cylinder", color = rgb(170, 235, 255), size = Vector3.new(0.3, 1, 1) },
	},
	{
		id = "Boomerang",
		index = 11,
		kind = "Boomerang",
		pool = "Common",
		name = { en = "Boomerang", fr = "Boomerang" },
		desc = { en = "Flies out and back, hitting everything", fr = "Flies out and back, hitting everything" },
		scaling = { "Size", "Amount" },
		base = { damage = 13, cooldown = 1.5, radius = 1.6, amount = 1, speed = 34, outTime = 0.55, life = 2.5, pierce = -1, range = 40 },
		levels = {
			{ amount = 1 },
			{ damage = 6 },
			{ radiusPct = 0.15 },
			{ amount = 1 },
			{ damage = 6 },
			{ cooldownPct = -0.10 },
			{ amount = 1, damage = 8 },
		},
		fx = { shape = "Block", color = rgb(230, 170, 60), size = Vector3.new(2.4, 0.4, 0.8), projDiv = 1.6, spin = true, boomerang = true },
	},
	{
		id = "BombBag",
		index = 12,
		kind = "Strike",
		pool = "Common",
		name = { en = "Bomb Bag", fr = "Bomb Bag" },
		desc = { en = "Lobs bombs into the crowd", fr = "Lobs bombs into the crowd" },
		scaling = { "Size", "Amount" },
		base = { damage = 24, cooldown = 2.6, radius = 6, amount = 1, delay = 0.8, range = 25, knockback = 6 },
		levels = {
			{ damage = 7 },
			{ radiusPct = 0.15 },
			{ amount = 1 },
			{ damage = 8 },
			{ cooldownPct = -0.10 },
			{ amount = 1 },
			{ damage = 10, radiusPct = 0.20 },
		},
		fx = { shape = "Cylinder", color = rgb(255, 150, 40), size = Vector3.new(0.3, 1, 1) },
	},
	{
		id = "SpearThrow",
		index = 13,
		kind = "Shot",
		pool = "Common",
		name = { en = "Spear Throw", fr = "Spear Throw" },
		desc = { en = "Heavy spear that goes through everything", fr = "Heavy spear that goes through everything" },
		scaling = { "Damage", "Amount" },
		base = { damage = 20, cooldown = 1.8, radius = 0.9, amount = 1, speed = 75, life = 1.0, pierce = -1, angle = 6, range = 50, knockback = 3, volleys = 1, volleyDelay = 0.2 },
		levels = {
			{ damage = 6 },
			{ amount = 1 },
			{ radiusPct = 0.20 },
			{ damage = 7 },
			{ cooldownPct = -0.10 },
			{ amount = 1 },
			{ damage = 10, radiusPct = 0.30 },
		},
		fx = { shape = "Block", color = rgb(200, 160, 100), size = Vector3.new(0.3, 0.3, 4), projDiv = 0.9 },
	},
	{
		id = "MeteorRain",
		index = 14,
		kind = "Strike",
		pool = "Common",
		status = "Burn",
		name = { en = "Meteor Rain", fr = "Meteor Rain" },
		desc = { en = "Meteors crash on random enemies", fr = "Meteors crash on random enemies" },
		scaling = { "Luck", "Size" },
		base = { damage = 40, cooldown = 3.2, radius = 7, amount = 2, delay = 0.9, range = 35, luckExtra = 0.01, statusDps = 3, statusDuration = 2 },
		levels = {
			{ damage = 12 },
			{ amount = 1 },
			{ radiusPct = 0.15 },
			{ damage = 15 },
			{ cooldownPct = -0.10 },
			{ amount = 1 },
			{ damage = 20, radiusPct = 0.20 },
		},
		fx = { shape = "Cylinder", color = rgb(255, 80, 50), size = Vector3.new(0.3, 1, 1) },
	},
	{
		id = "OrbitingBlades",
		index = 15,
		kind = "Orbit",
		pool = "Common",
		name = { en = "Orbiting Blades", fr = "Orbiting Blades" },
		desc = { en = "Small blades always circle you", fr = "Small blades always circle you" },
		scaling = { "Amount", "AttackSpeed" },
		base = { damage = 6, cooldown = 2, duration = 2, permanent = 1, amount = 3, orbitRadius = 3.5, radius = 1.0, spin = 5, interval = 0.35 },
		levels = {
			{ amount = 1 },
			{ damage = 2 },
			{ spinPct = 0.20 },
			{ amount = 1 },
			{ damage = 3 },
			{ radiusPct = 0.15, orbitRadiusPct = 0.15 },
			{ amount = 2 },
		},
		fx = { shape = "Cylinder", color = rgb(210, 215, 230), size = Vector3.new(0.25, 1.6, 1.6), orbit = true },
	},
	{
		id = "CrossbowTurret",
		index = 16,
		kind = "Turret",
		pool = "Common",
		name = { en = "Crossbow Turret", fr = "Crossbow Turret" },
		desc = { en = "Drops a crossbow that shoots on its own", fr = "Drops a crossbow that shoots on its own" },
		scaling = { "Duration", "Amount" },
		base = { damage = 8, cooldown = 6, duration = 8, interval = 0.8, turrets = 1, darts = 1, speed = 70, life = 0.7, radius = 0.7, pierce = 2, range = 38, angle = 10 },
		levels = {
			{ damage = 3 },
			{ duration = 2 },
			{ intervalPct = -0.15 },
			{ turrets = 1 },
			{ damage = 3 },
			{ darts = 1 },
			{ turrets = 1, damage = 3 },
		},
		fx = { shape = "Block", color = rgb(130, 95, 60), size = Vector3.new(1.6, 2.2, 1.6) },
	},
}

Weapons.List = defs
Weapons.Defs = {} :: { [string]: WeaponDef }
Weapons.ByIndex = {} :: { [number]: WeaponDef }
for _, def in defs do
	assert(Weapons.Defs[def.id] == nil, `arme {def.id} définie deux fois`)
	assert(Weapons.ByIndex[def.index] == nil, `index d'arme {def.index} utilisé deux fois`)
	Weapons.Defs[def.id] = def
	Weapons.ByIndex[def.index] = def
end

-- Passifs des classes (dossier 10 section 8). Id du passif = id de la classe.
-- Lus par StatsService (perLevel / flat), WeaponService (crit, aura, plus) et PassiveService
-- (déclencheurs). Les champs `companion*` sont pour le domaine compagnons (vague 2).
Weapons.Passives = {
	Knight = {
		name = { en = "Valor", fr = "Valor" },
		desc = { en = "+1% damage per enemy within 10 studs (max +30%). Blocks one hit every 15 s.", fr = "+1% damage per enemy within 10 studs (max +30%). Blocks one hit every 15 s." },
		nearRadius = 10,
		damagePerEnemy = 0.01,
		maxNearBonus = 0.30,
		-- A04-12 : 8 -> 15 s. La parade bloque un coup entier (contact cumulé, mini-boss, boss) : à un coup
		-- toutes les 5 à 15 s, elle en bloquait 40 à 60 % et le Knight gagnait 25 points de plus que les autres.
		parryEvery = 15,
	},
	Archer = {
		name = { en = "Eagle Eye", fr = "Eagle Eye" },
		desc = { en = "+25% crit chance on enemies more than 20 studs away.", fr = "+25% crit chance on enemies more than 20 studs away." },
		farRange = 20,
		farCrit = 0.25,
	},
	Mage = {
		name = { en = "Arcane Surge", fr = "Arcane Surge" },
		desc = { en = "+2% area per level. Every 5th card offer has a Rare card or better.", fr = "+2% area per level. Every 5th card offer has a Rare card or better." },
		perLevel = { Size = 0.02 },
		rareEveryOffers = 5,
	},
	Guardian = {
		name = { en = "Bulwark", fr = "Bulwark" },
		desc = { en = "+3 armor per level. Reflects 30% of melee damage. Can't be knocked back.", fr = "+3 armor per level. Reflects 30% of melee damage. Can't be knocked back." },
		perLevel = { Armor = 3 },
		flat = { Thorns = 0.30 },
	},
	Rogue = {
		name = { en = "Shadowstep", fr = "Shadowstep" },
		desc = { en = "Sliding makes you untouchable for 0.5 s. +10% dodge.", fr = "Sliding makes you untouchable for 0.5 s. +10% dodge." },
		flat = { Dodge = 0.10 },
		slideInvuln = 0.5,
		slideCooldown = 2,
	},
	Cleric = {
		name = { en = "Blessing", fr = "Blessing" },
		desc = { en = "Your aura heals allies inside it. You revive friends twice as fast.", fr = "Your aura heals allies inside it. You revive friends twice as fast." },
		auraWeapon = "HolyAura",
		auraHealPerTick = 1.5,
		reviveSpeed = 2,
	},
	Barbarian = {
		name = { en = "Rage", fr = "Rage" },
		desc = { en = "Up to +50% damage as your HP drops.", fr = "Up to +50% damage as your HP drops." },
		maxRage = 0.50,
	},
	Tamer = {
		name = { en = "Pack Leader", fr = "Pack Leader" },
		desc = { en = "Bring 2 companions. Capture 50% faster. Companions deal +20% damage.", fr = "Bring 2 companions. Capture 50% faster. Companions deal +20% damage." },
		companionSlots = 2,
		captureSpeed = 1.5,
		companionDamage = 0.20,
	},
} :: { [string]: { [string]: any } }

-- Épines : règle commune (Guardian avec Thorns 0,3, et objets). Seuls les coups de mêlée
-- (contact) sont renvoyés.
Weapons.Thorns = { radius = 6, targets = 3 }

-- Empilement par défaut des brûlures et poisons quand aucun passif ne le change
Weapons.DefaultMaxStacks = 1

-- Stats cumulées à un niveau (1..8, 9 = fusion). En cache ; ne jamais modifier le résultat.
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
	assert(def, `arme inconnue {id}`)
	local stats: Stats = table.clone(def.base)
	local mults: Stats = {}
	for l = 2, math.min(lvl, Weapons.MaxLevel) do
		applyDelta(stats, mults, def.levels[l - 1])
	end
	local fusion = def.fusion
	if lvl >= Weapons.FusionLevel and fusion then
		applyDelta(stats, mults, fusion.delta)
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
