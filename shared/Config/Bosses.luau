--!strict
-- Bosses (docs/dossier/20-run-mondes-boss.md section 5).
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
	whileRooted: boolean?, -- the only attacks the Oak uses while rooted
}

export type Weakness = {
	kind: "Height" | "Pillar" | "Platform",
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
	name: Types.LocalizedText,
	hp: number,
	moveSpeed: number,
	contactDamage: number,
	attacks: { Attack },
	weakness: Weakness,
}

local Bosses = {
	HpPerExtraPlayer = 0.8, -- doc 5.2
	PhaseAt = { 0.66, 0.33 }, -- hp fraction thresholds -> phase 2, 3
	PhaseCooldownMult = { 1, 0.85, 0.7 },
	MinTelegraph = 0.6,
	LockBefore = 0.5, -- following markers stop following this long before the hit
	JumpClear = 4, -- feet this high above the ground dodge a Ring
	EnragedHpMult = 1.6, -- stage 2 of T2/T3
	EnragedCooldownMult = 0.85,
	EnragedSuffix = { fr = " furieux", en = " (Enraged)" },
	ControlStunMult = 0.25, -- Freeze/Stun from weapons last 25 % on bosses
	SendHz = 10,
	GlobalAttackGap = 1.2, -- seconds between two attack starts
	ChestPerPlayer = true,
	Colors = {
		Normal = Color3.fromRGB(255, 60, 50),
		Summon = Color3.fromRGB(170, 80, 255),
		Weakness = Color3.fromRGB(255, 205, 60),
	},
	List = {} :: { [string]: Boss },
}

Bosses.List.GrandCheneRonchon = {
	id = "GrandCheneRonchon",
	kind = 16,
	name = { fr = "Le Grand Chêne Ronchon", en = "The Grumpy Great Oak" },
	hp = 5000,
	moveSpeed = 3,
	contactDamage = 20,
	attacks = {
		{ id = "RacinesSismiques", label = { fr = "Racines sismiques", en = "Quake Roots" }, kind = "TargetCircle", minPhase = 1, windup = 1.0, cooldown = 5, damage = 25, radius = 8, whileRooted = true },
		{ id = "PluieDeGlands", label = { fr = "Pluie de glands", en = "Acorn Rain" }, kind = "MultiCircle", minPhase = 1, windup = 1.2, cooldown = 8, damage = 18, radius = 5, count = 5 },
		{ id = "OndeEcorce", label = { fr = "Onde d'écorce", en = "Bark Wave" }, kind = "Ring", minPhase = 2, windup = 1.5, cooldown = 10, damage = 30, inner = 10, radius = 30 },
		{ id = "Rejetons", label = { fr = "Rejetons", en = "Saplings" }, kind = "Summon", minPhase = 2, windup = 1.0, cooldown = 15, radius = 6, count = 6, summonKind = 1 },
	},
	weakness = {
		kind = "Height",
		label = { fr = "Le chêne s'enracine : grimpe sur ses branches !", en = "The oak takes root: climb its branches!" },
		minPhase = 2,
		every = 25,
		rootSeconds = 8,
		heightAbove = 5,
		range = 22,
		damageMult = 3,
	},
}

Bosses.List.PharaonGrillePain = {
	id = "PharaonGrillePain",
	kind = 17,
	name = { fr = "Le Pharaon-Grille-Pain", en = "The Toaster Pharaoh" },
	hp = 6000,
	moveSpeed = 6,
	contactDamage = 20,
	attacks = {
		{ id = "TartinesBrulantes", label = { fr = "Tartines brûlantes", en = "Burning Toast" }, kind = "Line", minPhase = 1, windup = 1.0, cooldown = 5, damage = 22, width = 6, length = 40 },
		{ id = "Miettes", label = { fr = "Miettes", en = "Crumbs" }, kind = "Fan", minPhase = 1, windup = 0.6, cooldown = 6, damage = 10, radius = 5, count = 7, spread = 60, speed = 18 },
		{ id = "GrilleArdente", label = { fr = "Grille ardente", en = "Red-Hot Grill" }, kind = "SelfCircle", minPhase = 2, windup = 1.2, cooldown = 9, damage = 30, radius = 14 },
		{ id = "Momification", label = { fr = "Momification", en = "Mummify" }, kind = "Summon", minPhase = 2, windup = 1.0, cooldown = 15, radius = 6, count = 5, summonKind = 5 },
		{ id = "Ruee", label = { fr = "Ruée", en = "Rush" }, kind = "Charge", minPhase = 3, windup = 1.2, cooldown = 8, damage = 28, width = 8, length = 50 },
	},
	weakness = {
		kind = "Pillar",
		label = { fr = "Encastré dans un pilier !", en = "Stuck in a pillar!" },
		minPhase = 3,
		damageMult = 2,
		stunSeconds = 5,
	},
}

Bosses.List.DirectriceEternelle = {
	id = "DirectriceEternelle",
	kind = 18,
	name = { fr = "La Directrice Éternelle", en = "The Eternal Headmistress" },
	hp = 6500,
	moveSpeed = 7,
	contactDamage = 20,
	attacks = {
		{ id = "RegleTapante", label = { fr = "Règle tapante", en = "Ruler Smack" }, kind = "TargetCircle", minPhase = 1, windup = 1.0, cooldown = 4.5, damage = 26, radius = 9 },
		{ id = "AvionsEnPapier", label = { fr = "Avions en papier", en = "Paper Planes" }, kind = "Fan", minPhase = 1, windup = 0.6, cooldown = 5, damage = 11, radius = 5, count = 5, spread = 50, speed = 20 },
		{ id = "RetenueGenerale", label = { fr = "Retenue générale", en = "Detention for All" }, kind = "Ring", minPhase = 2, windup = 1.6, cooldown = 11, damage = 28, inner = 16, radius = 40 },
		{ id = "AppelEnRang", label = { fr = "Appel en rang", en = "Line Up!" }, kind = "Summon", minPhase = 2, windup = 1.0, cooldown = 14, radius = 6, count = 6, summonKind = 9 },
	},
	weakness = {
		kind = "Platform",
		label = { fr = "La cloche sonne : la Directrice est sonnée !", en = "The bell rings: the Headmistress is dazed!" },
		minPhase = 1,
		damageMult = 2,
		stunSeconds = 6,
		standSeconds = 2,
		cooldown = 30,
		range = 5,
	},
}

Bosses.List.GrandBrouhaha = {
	id = "GrandBrouhaha",
	kind = 19,
	name = { fr = "Le Grand Brouhaha", en = "The Great Hubbub" },
	hp = 12000,
	moveSpeed = 6,
	contactDamage = 20,
	attacks = {
		{ id = "CohueTonnerre", label = { fr = "Cohue tonnerre", en = "Thunder Crowd" }, kind = "MultiCircle", minPhase = 1, windup = 1.2, cooldown = 6, damage = 30, radius = 10, count = 3 },
		{ id = "Spirale", label = { fr = "Spirale", en = "Spiral" }, kind = "Fan", minPhase = 1, windup = 0.6, cooldown = 7, damage = 12, radius = 6, count = 12, spread = 360, speed = 16 },
		{ id = "Barrage", label = { fr = "Barrage", en = "Barrage" }, kind = "Line", minPhase = 2, windup = 1.2, cooldown = 8, damage = 32, width = 10, length = 60 },
		{ id = "Vague", label = { fr = "Vague", en = "Wave" }, kind = "Ring", minPhase = 2, windup = 1.8, cooldown = 12, damage = 35, inner = 12, radius = 45 },
		{ id = "Renforts", label = { fr = "Renforts", en = "Reinforcements" }, kind = "Summon", minPhase = 2, windup = 1.0, cooldown = 20, radius = 6, count = 2, summonKind = 0 },
	},
	weakness = {
		kind = "Platform",
		label = { fr = "Le gong résonne : silence !", en = "The gong rings: silence!" },
		minPhase = 1,
		damageMult = 2,
		stunSeconds = 5,
		standSeconds = 2,
		cooldown = 35,
		range = 5,
	},
}

return Bosses
