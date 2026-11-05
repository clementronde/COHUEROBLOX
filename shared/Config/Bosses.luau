--!strict
-- Bosses (docs/dossier/20-run-mondes-boss.md section 5, dossier 13 §4 et §11.5).
-- Every telegraph >= MinTelegraph and passes R <= 16 * (windup - 0.25) unless noted (vault:
-- "Combat Arena and Encounter Layout", "Boss Animation and Phases").

local Types = require(script.Parent.Parent.Types)

export type AttackKind =
	"TargetCircle" -- circle under one player (locks LockBefore s before the hit)
	| "MultiCircle" -- `count` circles near players
	| "SelfCircle" -- circle centred on the boss
	| "Ring" -- donut around the boss, inner..outer, can be jumped
	| "Line" -- rectangle from the boss toward a player
	| "Charge" -- Line, then the boss dashes along it
	| "Fan" -- projectiles (short self marker first)
	| "Summon"

export type Attack = {
	id: string,
	label: Types.LocalizedText,
	kind: AttackKind,
	minPhase: number,
	windup: number,
	cooldown: number,
	damage: number?,
	radius: number?,
	inner: number?,
	width: number?,
	length: number?,
	count: number?,
	spread: number?, -- degrees (Fan)
	speed: number?, -- projectile speed (Fan)
	summonKind: number?, -- enemy kind; 0 = world elites
	projectile: string?, -- Fan : objet Assets.FX.Bosses.<fxFolder>.<projectile> (sinon Assets.FX.Enemies.Projectiles.Default)
	fx: string?, -- objet d'impact Assets.FX.Bosses.<fxFolder>.<fx>, posé par BossRenderer à l'impact (facultatif)
	whileRooted: boolean?, -- the only attacks the Oak uses while rooted
}

export type Weakness = {
	kind: "Height" | "Pillar" | "Platform" | "None", -- None : pas de point faible
	label: Types.LocalizedText,
	minPhase: number,
	every: number?, -- Height: root cycle
	rootSeconds: number?,
	heightAbove: number?,
	range: number?,
	damageMult: number,
	stunSeconds: number?,
	standSeconds: number?,
	cooldown: number?,
}

export type Boss = {
	id: string,
	kind: number, -- Enemies kind id (16..19)
	asset: string?, -- modèle Assets.Creatures.<asset> (BossRenderer) ; sans asset : Enemies[kind].asset
	fxFolder: string?, -- dossier Assets.FX.Bosses.<fxFolder> (objets d'attaque, dossier 13 §9.2)
	name: Types.LocalizedText,
	hp: number,
	moveSpeed: number,
	contactDamage: number,
	attacks: { Attack },
	weakness: Weakness,
}

local Bosses = {
	HpPerExtraPlayer = 0.8, -- doc 5.2
	-- Décisions v2 section 6 : boss simples, 2 à 3 attaques annoncées 1 s avant, pas de phase
	-- d'escalade. PhaseEnabled = false : le boss reste en phase 1 (attaques minPhase 1 seulement).
	PhaseEnabled = false,
	PhaseAt = { 0.66, 0.33 }, -- hp fraction thresholds -> phase 2, 3 (si PhaseEnabled)
	PhaseCooldownMult = { 1, 0.85, 0.7 },
	MinTelegraph = 1.0,
	LockBefore = 0.5, -- following markers stop following this long before the hit
	JumpClear = 4, -- feet this high above the ground dodge a Ring
	EnragedHpMult = 1.6, -- stage 2 of T2/T3
	EnragedCooldownMult = 0.85,
	EnragedSuffix = { en = " (Enraged)", fr = " (Enraged)" },
	ControlStunMult = 0.25, -- Freeze/Stun from weapons last 25 % on bosses
	SendHz = 10,
	GlobalAttackGap = 1.2, -- seconds between two attack starts
	AnnounceAttacks = 1.5, -- s de bannière au premier usage de chaque attaque dans un combat (0 = jamais)
	ChestPerPlayer = true,
	Colors = {
		Normal = Color3.fromRGB(255, 60, 50),
		Summon = Color3.fromRGB(170, 80, 255),
		Weakness = Color3.fromRGB(255, 205, 60),
	},
	List = {} :: { [string]: Boss },
}

-- Boss v2 : 3 attaques de phase 1 chacun, rien d'autre (PhaseEnabled = false). Dégâts de base du
-- monde 1 : BossService les multiplie par EnemyService._damageScale (Run.WorldScaling[].damage :
-- x1,35 au monde 2, x1,8 au monde 3, plus l'Overtime). Repères : PV joueur ~130 à la fin du monde 1,
-- ~170 au 2, ~220 au 3 ; un coup encaissé = 12 à 18 % des PV, un éventail entier encaissé ~35 %.
-- Cadence : une attaque toutes les 2,2 à 3 s (préparation + GlobalAttackGap), au hasard parmi
-- celles dont la recharge est finie.

Bosses.List.GrandCheneRonchon = {
	id = "GrandCheneRonchon",
	kind = 16,
	asset = "Boss_GrumpyGreatOak",
	fxFolder = "GrumpyGreatOak",
	name = { en = "The Grumpy Great Oak", fr = "The Grumpy Great Oak" },
	hp = 5000,
	moveSpeed = 3,
	contactDamage = 20,
	attacks = {
		{ id = "RacinesSismiques", label = { en = "Get Off My Lawn!", fr = "Get Off My Lawn!" }, kind = "TargetCircle", minPhase = 1, windup = 1.0, cooldown = 5, damage = 20, radius = 8, fx = "RootBurst", whileRooted = true },
		{ id = "PluieDeGlands", label = { en = "Acorn Drizzle", fr = "Acorn Drizzle" }, kind = "MultiCircle", minPhase = 1, windup = 1.2, cooldown = 8, damage = 15, radius = 5, count = 5, fx = "Acorn" },
		{ id = "OndeEcorce", label = { en = "Leaf Me Alone!", fr = "Leaf Me Alone!" }, kind = "Ring", minPhase = 1, windup = 1.5, cooldown = 10, damage = 24, inner = 10, radius = 30, fx = "BarkWave" },
	},
	weakness = {
		-- Endormie : minPhase 2 n'arrive pas tant que PhaseEnabled = false (boss simple).
		kind = "Height",
		label = { en = "The oak takes root: climb its branches!", fr = "The oak takes root: climb its branches!" },
		minPhase = 2,
		every = 25,
		rootSeconds = 8,
		heightAbove = 5,
		range = 22,
		damageMult = 3,
	},
}

-- Monde 2 (cimetière) : remplace le Pharaon-Grille-Pain v1 (même kind 17, modèle Boss_HungryCoffin).
Bosses.List.CercueilAffame = {
	id = "CercueilAffame",
	kind = 17,
	asset = "Boss_HungryCoffin",
	fxFolder = "HungryCoffin",
	name = { en = "The Hungry Coffin", fr = "The Hungry Coffin" },
	hp = 6000,
	moveSpeed = 6,
	contactDamage = 20,
	attacks = {
		{ id = "CroqueCouvercle", label = { en = "Snack Time!", fr = "Snack Time!" }, kind = "TargetCircle", minPhase = 1, windup = 1.0, cooldown = 5, damage = 18, radius = 8, fx = "LidChomp" },
		{ id = "CrachatDOs", label = { en = "Bone Appetit", fr = "Bone Appetit" }, kind = "Fan", minPhase = 1, windup = 1.0, cooldown = 6, damage = 8, radius = 5, count = 7, spread = 60, speed = 18, projectile = "Bone" },
		-- Largeur 14 = 2 x (rayon du corps 5 + 2) : la zone touchée pendant la ruée (stepCharge) tient dans la ligne.
		{ id = "RueeAffamee", label = { en = "Late for Dinner!", fr = "Late for Dinner!" }, kind = "Charge", minPhase = 1, windup = 1.2, cooldown = 9, damage = 22, width = 14, length = 45 },
	},
	weakness = { kind = "None", label = { en = "", fr = "" }, minPhase = 99, damageMult = 1 },
}

Bosses.List.DirectriceEternelle = {
	id = "DirectriceEternelle",
	kind = 18,
	asset = "Boss_EternalHeadmistress",
	fxFolder = "EternalHeadmistress",
	name = { en = "The Eternal Headmistress", fr = "The Eternal Headmistress" },
	hp = 6500,
	moveSpeed = 7,
	contactDamage = 20,
	attacks = {
		{ id = "RegleTapante", label = { en = "Ruler Smack!", fr = "Ruler Smack!" }, kind = "TargetCircle", minPhase = 1, windup = 1.0, cooldown = 4.5, damage = 18, radius = 9, fx = "Ruler" },
		{ id = "AvionsEnPapier", label = { en = "Pop Quiz Planes", fr = "Pop Quiz Planes" }, kind = "Fan", minPhase = 1, windup = 1.0, cooldown = 5, damage = 8, radius = 5, count = 5, spread = 50, speed = 20, projectile = "PaperPlane" },
		{ id = "RetenueGenerale", label = { en = "Detention for Everyone!", fr = "Detention for Everyone!" }, kind = "Ring", minPhase = 1, windup = 1.6, cooldown = 11, damage = 22, inner = 16, radius = 40, fx = "DetentionWave" },
	},
	weakness = {
		-- La cloche (plateforme de l'arène, Heightmap) : 2 s dessus, étourdie 6 s, dégâts x2.
		kind = "Platform",
		label = { en = "The bell rings: the Headmistress is dazed!", fr = "The bell rings: the Headmistress is dazed!" },
		minPhase = 1,
		damageMult = 2,
		stunSeconds = 6,
		standSeconds = 2,
		cooldown = 30,
		range = 5,
	},
}

-- Réserve v1 : pas utilisée par la run v2 (RunManager ne lit que Worlds[].boss), sans modèle.
Bosses.List.GrandBrouhaha = {
	id = "GrandBrouhaha",
	kind = 19,
	name = { en = "The Great Hubbub", fr = "The Great Hubbub" },
	hp = 12000,
	moveSpeed = 6,
	contactDamage = 20,
	attacks = {
		{ id = "CohueTonnerre", label = { en = "Thunder Crowd", fr = "Thunder Crowd" }, kind = "MultiCircle", minPhase = 1, windup = 1.2, cooldown = 6, damage = 30, radius = 10, count = 3 },
		{ id = "Spirale", label = { en = "Spiral", fr = "Spiral" }, kind = "Fan", minPhase = 1, windup = 0.6, cooldown = 7, damage = 12, radius = 6, count = 12, spread = 360, speed = 16 },
		{ id = "Barrage", label = { en = "Barrage", fr = "Barrage" }, kind = "Line", minPhase = 2, windup = 1.2, cooldown = 8, damage = 32, width = 10, length = 60 },
		{ id = "Vague", label = { en = "Wave", fr = "Wave" }, kind = "Ring", minPhase = 2, windup = 1.8, cooldown = 12, damage = 35, inner = 12, radius = 45 },
		{ id = "Renforts", label = { en = "Reinforcements", fr = "Reinforcements" }, kind = "Summon", minPhase = 2, windup = 1.0, cooldown = 20, radius = 6, count = 2, summonKind = 0 },
	},
	weakness = {
		kind = "Platform",
		label = { en = "The gong rings: silence!", fr = "The gong rings: silence!" },
		minPhase = 1,
		damageMult = 2,
		stunSeconds = 5,
		standSeconds = 2,
		cooldown = 35,
		range = 5,
	},
}

return Bosses
