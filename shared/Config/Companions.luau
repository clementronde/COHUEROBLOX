--!strict
-- Companion tuning (docs/dossier/40-compagnons.md). Every number of the companion domain is here.
-- Values written as { a, b, c, d, e } are per technique level (1..5) or per stage (1..3).

local Types = require(script.Parent.Parent.Types)

type LocalizedText = Types.LocalizedText

export type Num = number | { number } -- plain number, or one value per level / stage
export type StatusKind = "Burn" | "Poison" | "Slow" | "Freeze" | "Stun" | "Knockback"
export type Shape = "Target" | "Nova" | "Aura" | "Chain" | "Heal"

export type StatusDef = {
	kind: StatusKind,
	dps: Num?,
	duration: Num?,
	mult: Num?, -- Slow
	distance: Num?, -- Knockback
	chance: Num?, -- 0..1, default 1
}

export type TechDef = {
	id: string,
	line: string,
	name: LocalizedText,
	desc: LocalizedText,
	shape: Shape,
	damage: Num,
	cooldown: Num,
	radius: Num?, -- Nova / Aura / Heal radius, or Target splash radius
	targets: Num?, -- Chain: number of hits
	jump: number?, -- Chain: max distance between hops
	healPct: Num?, -- Heal: share of max HP
	status: { StatusDef }?,
}

export type StageDef = {
	name: LocalizedText,
	height: number, -- studs, model scale reference
	damage: number,
	interval: number, -- seconds between basic attacks
	range: number, -- acquire radius
	splash: number?, -- basic attack splash radius
	chain: number?, -- basic attack extra hops (Volt)
	freezeEvery: number?, -- Givre: freeze on every Nth hit on the same target
	status: { StatusDef }?, -- affinity effect of the basic attack
}

export type UltimateDef = {
	name: LocalizedText,
	desc: LocalizedText,
	duration: number, -- seconds the "ultimate active" flag stays on (visual + timed effects)
	radius: number,
	damage: number,
	tickRate: number?, -- hits per second for timed ultimates (Braise)
	maxTargets: number?, -- Volt
	spread: number?, -- Volt: seconds the strikes are spread over
	healPct: number?, -- Maree: share of max HP for every active teammate
	status: { StatusDef }?,
}

export type LineDef = {
	id: string,
	index: number, -- wire id (1..6, 3 bits)
	affinity: LocalizedText,
	flying: boolean,
	colors: { primary: Color3, secondary: Color3, accent: Color3, glow: Color3 },
	stages: { StageDef },
	techs: { string }, -- 4 technique ids; [1] is the default start technique
	ultimate: UltimateDef,
}

export type TreatDef = {
	id: string,
	name: LocalizedText,
	stat: "Power" | "Haste" | "Reach" | "Spirit",
	values: { [Types.Rarity]: number },
	maxStacks: number,
}

local function T(fr: string, en: string): LocalizedText
	return { fr = fr, en = en }
end

local Companions = {}

-- Simulation / network ---------------------------------------------------------------------
Companions.SimHz = 10 -- server brain + snapshot rate (vault: NPC brains at ~10 Hz)
Companions.StateMaxPerSecond = 4 -- CompanionState sends per owner when only the charge moved
Companions.Net = {
	HeaderBytes = 5, -- tick u32 | count u8
	RecordBytes = 23, -- userId f64 | x,y,z i16 | yaw u8 | flags u8 | evSeq u8 | evKind u8 | evX,evZ i16 | evRadius u8
	ChunkMaxBytes = 900, -- UnreliableRemoteEvent drops payloads over 1,000 bytes
	PositionScale = 4, -- 1/4 stud
	-- evKind values
	EvNone = 0,
	EvBasic = 1,
	EvTech1 = 2, -- EvTech1 + (index in line.techs - 1): 2..5
	EvUltimate = 6,
	EvHeal = 7,
	-- flags bits
	StageShift = 3, -- line: bits 0-2, stage: bits 3-4
	StunnedBit = 32,
	UltimateBit = 64,
}

-- Follow ------------------------------------------------------------------------------------
Companions.Follow = {
	Behind = 5, -- studs behind the owner
	Side = 2, -- studs to the side (alternates per owner)
	Speed = 24, -- studs/s (1.5 x base walk speed 16)
	SnapDistance = 60, -- teleport behind the owner past this distance
	FlyHeight = 2.5, -- extra height for flying lines
	ChaseLeash = 14, -- may step this far from its follow point toward a target
	GuardRadius = 10, -- downed owner: attack only around them
}

-- Ultimate charge ---------------------------------------------------------------------------
Companions.Ultimate = {
	Max = 100,
	PassivePerSecond = 0.5,
	OwnerKill = 0.25,
	CompanionKill = 1,
	EliteKill = 5,
	PerDamageTaken = 0.2,
	LevelUp = 5,
	MinInterval = 1, -- seconds between two uses (anti double-press)
	AllowedPhases = { Running = true, Boss = true, BossDefeated = true, FinalWave = true } :: { [string]: boolean },
	RemotePerSecond = 2,
}

Companions.StunOnDowned = 5 -- seconds (doc 7.3)
Companions.OwnerDamageShare = 0.5 -- share of the owner's Damage stat inherited
Companions.EvolveLevels = { 8, 20 } -- owner run level for stage 2 and stage 3
Companions.MaxTechs = 3
Companions.MaxTechLevel = 5
Companions.FragileBonus = 0.3 -- Givre: +30 % companion damage on targets it froze
Companions.SynergyBonus = 0.1 -- +10 % damage and charge gain
Companions.DefaultLine = "Braise"
Companions.VoltChain = { Jump = 10, Falloff = 0.6 } -- Volt basic attack hops: max distance, damage kept per hop
Companions.Debug = {
	SpawnWithoutRun = true, -- no RunManager loaded: give every player a default companion on spawn
}

-- Bond (meta, stored by the data domain) -------------------------------------------------------
Companions.Bond = {
	Max = 30,
	DamagePerStep = 0.01, -- +1 % per step
	StepEvery = 3, -- levels 3, 6, ..., 30 -> +10 % max
	StartTechUnlock = { 1, 5, 15, 25 } :: { number }, -- bond level that unlocks techs[i] as start technique
	TintLevels = { 4, 10, 20, 28 } :: { number },
	PoseLevel = 12,
	TitleLevel = 30,
	Title = T("Inséparable", "Inseparable"),
}

-- Class x affinity synergy (+10 %) -------------------------------------------------------------
Companions.Synergy = {
	Cornu = "Braise",
	Plumeline = "Maree",
	Mecano = "Volt",
	Felyne = "Volt",
	Rocailleux = "Ronce",
	Sporelin = "Ronce",
	Ecaille = "Braise",
	Astrel = "Echo",
	Cristallin = "Givre",
	Tentaculos = "Maree",
} :: { [string]: string }

-- Cards ---------------------------------------------------------------------------------------
Companions.Cards = {
	MaxOptions = 3, -- getCardOptions returns at most this many cards
	Weights = { CompanionTech = 3, CompanionTechUp = 4, CompanionTreat = 2 } :: { [string]: number },
	TechRarity = "Rare" :: Types.Rarity,
	TechUpRarity = "Common" :: Types.Rarity,
	TechMaxRarity = "Epic" :: Types.Rarity, -- the upgrade to level 5
	TreatRarityOdds = { { "Common", 0.6 }, { "Rare", 0.3 }, { "Epic", 0.1 } } :: { { any } },
}

-- Free eggs (earned only; the same table is shown and rolled by the data domain) ----------------
Companions.Eggs = {
	StarterLines = { "Braise", "Ronce", "Maree" } :: { string },
	EggLines = { "Volt", "Givre", "Echo" } :: { string }, -- equal odds among the ones not owned yet
	AllOwnedBondBonus = 3,
	PurchasableWithRobux = false, -- never: it would make the egg a paid random item
}

Companions.QuestKeys = {
	Evolved = "CompanionEvolved",
	Stage3 = "CompanionStage3",
	Ultimates = "UltimatesUsed",
	Kills = "CompanionKills",
	TechsLearned = "CompanionTechsLearned",
	Treats = "CompanionTreats",
}

-- Treats ----------------------------------------------------------------------------------------
Companions.Treats = {
	TreatPower = {
		id = "TreatPower",
		name = T("Biscuit costaud", "Hearty Biscuit"),
		stat = "Power",
		values = { Common = 0.08, Rare = 0.12, Epic = 0.18, Legendary = 0.18 },
		maxStacks = 10,
	},
	TreatHaste = {
		id = "TreatHaste",
		name = T("Bonbon pétillant", "Fizzy Candy"),
		stat = "Haste",
		values = { Common = 0.06, Rare = 0.09, Epic = 0.14, Legendary = 0.14 },
		maxStacks = 10,
	},
	TreatReach = {
		id = "TreatReach",
		name = T("Baie longue-vue", "Spyglass Berry"),
		stat = "Reach",
		values = { Common = 0.08, Rare = 0.12, Epic = 0.18, Legendary = 0.18 },
		maxStacks = 10,
	},
	TreatSpirit = {
		id = "TreatSpirit",
		name = T("Miel d'étoile", "Star Honey"),
		stat = "Spirit",
		values = { Common = 0.08, Rare = 0.12, Epic = 0.18, Legendary = 0.18 },
		maxStacks = 10,
	},
} :: { [string]: TreatDef }

-- Lines -----------------------------------------------------------------------------------------
local C = Color3.fromRGB

Companions.Lines = {
	Braise = {
		id = "Braise",
		index = 1,
		affinity = T("Braise", "Ember"),
		flying = false,
		colors = { primary = C(240, 130, 50), secondary = C(120, 60, 40), accent = C(230, 40, 40), glow = C(255, 170, 60) },
		stages = {
			{ name = T("Tisonnet", "Tinderling"), height = 2, damage = 7, interval = 1.0, range = 22, splash = 3, status = { { kind = "Burn", dps = 2, duration = 3 } } },
			{ name = T("Fournaïde", "Furnacid"), height = 3, damage = 16, interval = 0.9, range = 24, splash = 4, status = { { kind = "Burn", dps = 4, duration = 3 } } },
			{ name = T("Volcarapace", "Volcashell"), height = 4.5, damage = 34, interval = 0.8, range = 26, splash = 5, status = { { kind = "Burn", dps = 7, duration = 3 } } },
		},
		techs = { "EmberSpit", "FlameRing", "CinderTrail", "FireComet" },
		ultimate = {
			name = T("Pluie de cendres", "Ash Rain"),
			desc = T("6 s de cendres brûlantes autour de toi.", "6 s of burning ash around you."),
			duration = 6,
			radius = 18,
			damage = 10,
			tickRate = 4,
			status = { { kind = "Burn", dps = 8, duration = 3 } },
		},
	},
	Ronce = {
		id = "Ronce",
		index = 2,
		affinity = T("Ronce", "Bramble"),
		flying = false,
		colors = { primary = C(150, 100, 55), secondary = C(90, 160, 70), accent = C(235, 120, 170), glow = C(150, 230, 90) },
		stages = {
			{ name = T("Pousseron", "Sproutlet"), height = 2, damage = 5, interval = 1.0, range = 22, status = { { kind = "Poison", dps = 1.5, duration = 4 }, { kind = "Slow", mult = 0.75, duration = 2 } } },
			{ name = T("Ronciflore", "Bramblebloom"), height = 3, damage = 12, interval = 0.9, range = 24, status = { { kind = "Poison", dps = 3, duration = 4 }, { kind = "Slow", mult = 0.75, duration = 2 } } },
			{ name = T("Sylvogarde", "Sylvaward"), height = 4.5, damage = 26, interval = 0.8, range = 26, status = { { kind = "Poison", dps = 5, duration = 4 }, { kind = "Slow", mult = 0.75, duration = 2 } } },
		},
		techs = { "ThornShot", "BrambleField", "SporePuff", "RootSnare" },
		ultimate = {
			name = T("Racines géantes", "Giant Roots"),
			desc = T("Immobilise tout l'écran 3 s.", "Roots the whole screen for 3 s."),
			duration = 3,
			radius = 60,
			damage = 0,
			status = { { kind = "Stun", duration = 3 }, { kind = "Poison", dps = 6, duration = 4 } },
		},
	},
	Maree = {
		id = "Maree",
		index = 3,
		affinity = T("Marée", "Tide"),
		flying = true,
		colors = { primary = C(80, 170, 230), secondary = C(30, 60, 120), accent = C(120, 240, 220), glow = C(160, 230, 255) },
		stages = {
			{ name = T("Gouttelot", "Dropple"), height = 2, damage = 5, interval = 1.1, range = 24, status = { { kind = "Knockback", distance = 4 } } },
			{ name = T("Ondelin", "Wavelin"), height = 3, damage = 12, interval = 1.0, range = 26, status = { { kind = "Knockback", distance = 5 } } },
			{ name = T("Abyssale", "Abyssa"), height = 4.5, damage = 25, interval = 0.9, range = 28, status = { { kind = "Knockback", distance = 6 } } },
		},
		techs = { "BubbleShot", "TideRing", "Spring", "Geyser" },
		ultimate = {
			name = T("Grande vague", "Great Wave"),
			desc = T("Soigne toute l'équipe de 40 % et repousse.", "Heals the whole team 40% and pushes back."),
			duration = 1.5,
			radius = 20,
			damage = 30,
			healPct = 0.4,
			status = { { kind = "Knockback", distance = 12 } },
		},
	},
	Volt = {
		id = "Volt",
		index = 4,
		affinity = T("Volt", "Volt"),
		flying = false,
		colors = { primary = C(40, 170, 170), secondary = C(200, 120, 60), accent = C(240, 240, 240), glow = C(120, 255, 240) },
		stages = {
			{ name = T("Grésillon", "Fizzlet"), height = 2, damage = 6, interval = 0.9, range = 22, chain = 1 },
			{ name = T("Ampérat", "Amperat"), height = 3, damage = 13, interval = 0.8, range = 24, chain = 2 },
			{ name = T("Fulgurex", "Fulgurex"), height = 4.5, damage = 27, interval = 0.7, range = 26, chain = 3 },
		},
		techs = { "Spark", "StaticField", "ThunderPounce", "BallLightning" },
		ultimate = {
			name = T("Orage", "Thunderstorm"),
			desc = T("La foudre frappe 30 ennemis.", "Lightning strikes 30 enemies."),
			duration = 1.5,
			radius = 60,
			damage = 80,
			maxTargets = 30,
			spread = 1.5,
		},
	},
	Givre = {
		id = "Givre",
		index = 5,
		affinity = T("Givre", "Frost"),
		flying = false,
		colors = { primary = C(235, 245, 255), secondary = C(40, 60, 90), accent = C(250, 150, 40), glow = C(150, 220, 255) },
		stages = {
			{ name = T("Flocon", "Flurry"), height = 2, damage = 6, interval = 1.2, range = 22, freezeEvery = 4, status = { { kind = "Slow", mult = 0.7, duration = 2 }, { kind = "Freeze", duration = 1 } } },
			{ name = T("Stalagmo", "Stalagmo"), height = 3, damage = 14, interval = 1.1, range = 24, freezeEvery = 4, status = { { kind = "Slow", mult = 0.7, duration = 2 }, { kind = "Freeze", duration = 1.25 } } },
			{ name = T("Glaciarque", "Glaciarch"), height = 4.5, damage = 30, interval = 1.0, range = 26, freezeEvery = 4, status = { { kind = "Slow", mult = 0.7, duration = 2 }, { kind = "Freeze", duration = 1.5 } } },
		},
		techs = { "FrostShard", "IceRing", "HailVeil", "GlacierSpike" },
		ultimate = {
			name = T("Blizzard", "Blizzard"),
			desc = T("Gèle les ennemis proches 4 s.", "Freezes nearby enemies for 4 s."),
			duration = 4,
			radius = 50,
			damage = 20,
			status = { { kind = "Freeze", duration = 4 } },
		},
	},
	Echo = {
		id = "Echo",
		index = 6,
		affinity = T("Écho", "Echo"),
		flying = true,
		colors = { primary = C(110, 80, 160), secondary = C(40, 35, 60), accent = C(250, 220, 120), glow = C(200, 170, 255) },
		stages = {
			{ name = T("Pipistrou", "Pipistrill"), height = 2, damage = 5, interval = 0.9, range = 26, status = { { kind = "Stun", duration = 0.8, chance = 0.15 } } },
			{ name = T("Résonar", "Resonar"), height = 3, damage = 11, interval = 0.8, range = 28, status = { { kind = "Stun", duration = 0.8, chance = 0.2 } } },
			{ name = T("Tonnerlune", "Thundermoon"), height = 4.5, damage = 24, interval = 0.7, range = 30, status = { { kind = "Stun", duration = 0.8, chance = 0.25 } } },
		},
		techs = { "SonicPing", "Screech", "Ricochet", "Resonance" },
		ultimate = {
			name = T("Cri lunaire", "Moon Howl"),
			desc = T("Étourdit les ennemis proches 2,5 s.", "Stuns nearby enemies for 2.5 s."),
			duration = 2.5,
			radius = 45,
			damage = 25,
			status = { { kind = "Stun", duration = 2.5 } },
		},
	},
} :: { [string]: LineDef }

-- Wire order: Lines[LineOrder[i]].index == i
Companions.LineOrder = { "Braise", "Ronce", "Maree", "Volt", "Givre", "Echo" } :: { string }

-- Techniques --------------------------------------------------------------------------------------
local function tech(def: TechDef): TechDef
	return def
end

Companions.Techs = {
	-- Braise
	EmberSpit = tech({
		id = "EmberSpit", line = "Braise", shape = "Target",
		name = T("Crachat de braise", "Ember Spit"),
		desc = T("Crache une braise qui brûle autour de l'impact.", "Spits an ember that burns around the impact."),
		damage = { 12, 16, 21, 27, 35 }, cooldown = { 3.0, 2.8, 2.6, 2.4, 2.2 }, radius = 5,
		status = { { kind = "Burn", dps = { 4, 5, 6, 8, 10 }, duration = 3 } },
	}),
	FlameRing = tech({
		id = "FlameRing", line = "Braise", shape = "Nova",
		name = T("Cercle de flammes", "Flame Ring"),
		desc = T("Un anneau de feu autour du compagnon.", "A ring of fire around your companion."),
		damage = { 10, 14, 18, 23, 30 }, cooldown = { 6, 5.5, 5, 4.5, 4 }, radius = { 8, 9, 10, 11, 12 },
		status = { { kind = "Burn", dps = { 3, 4, 5, 6, 8 }, duration = 3 } },
	}),
	CinderTrail = tech({
		id = "CinderTrail", line = "Braise", shape = "Aura",
		name = T("Cendres chaudes", "Cinder Trail"),
		desc = T("Des cendres brûlent les ennemis autour de toi.", "Hot cinders burn enemies around you."),
		damage = { 4, 5, 7, 9, 12 }, cooldown = 1.0, radius = { 6, 6.5, 7, 7.5, 8 },
	}),
	FireComet = tech({
		id = "FireComet", line = "Braise", shape = "Target",
		name = T("Comète de feu", "Fire Comet"),
		desc = T("Une grosse comète qui explose.", "A big comet that explodes."),
		damage = { 40, 55, 70, 90, 120 }, cooldown = { 9, 8.5, 8, 7.5, 7 }, radius = 8,
		status = { { kind = "Burn", dps = { 6, 8, 10, 12, 15 }, duration = 3 } },
	}),
	-- Ronce
	ThornShot = tech({
		id = "ThornShot", line = "Ronce", shape = "Target",
		name = T("Tir d'épines", "Thorn Shot"),
		desc = T("Des épines empoisonnées.", "Poisoned thorns."),
		damage = { 8, 11, 14, 18, 23 }, cooldown = { 2.5, 2.4, 2.3, 2.2, 2.0 },
		status = { { kind = "Poison", dps = { 3, 4, 5, 6, 8 }, duration = 4 } },
	}),
	BrambleField = tech({
		id = "BrambleField", line = "Ronce", shape = "Nova",
		name = T("Champ de ronces", "Bramble Field"),
		desc = T("Des ronces ralentissent et empoisonnent.", "Brambles slow and poison."),
		damage = { 6, 8, 10, 13, 16 }, cooldown = { 7, 6.5, 6, 5.5, 5 }, radius = { 9, 10, 11, 12, 13 },
		status = { { kind = "Slow", mult = 0.6, duration = 3 }, { kind = "Poison", dps = { 2, 3, 4, 5, 6 }, duration = 3 } },
	}),
	SporePuff = tech({
		id = "SporePuff", line = "Ronce", shape = "Aura",
		name = T("Bouffée de spores", "Spore Puff"),
		desc = T("Des spores empoisonnent autour de toi.", "Spores poison enemies around you."),
		damage = { 3, 4, 5, 6, 8 }, cooldown = 1.5, radius = { 6, 6.5, 7, 7.5, 8 },
		status = { { kind = "Poison", dps = { 2, 2.5, 3, 4, 5 }, duration = 3 } },
	}),
	RootSnare = tech({
		id = "RootSnare", line = "Ronce", shape = "Target",
		name = T("Piège racine", "Root Snare"),
		desc = T("Des racines immobilisent un groupe.", "Roots hold a group in place."),
		damage = { 15, 20, 26, 33, 42 }, cooldown = { 8, 7.5, 7, 6.5, 6 }, radius = 6,
		status = { { kind = "Stun", duration = { 1.0, 1.2, 1.4, 1.6, 2.0 } } },
	}),
	-- Maree
	BubbleShot = tech({
		id = "BubbleShot", line = "Maree", shape = "Target",
		name = T("Tir de bulle", "Bubble Shot"),
		desc = T("Une bulle qui repousse.", "A bubble that pushes back."),
		damage = { 9, 12, 16, 20, 26 }, cooldown = { 2.5, 2.4, 2.3, 2.2, 2.0 },
		status = { { kind = "Knockback", distance = 6 } },
	}),
	TideRing = tech({
		id = "TideRing", line = "Maree", shape = "Nova",
		name = T("Anneau de marée", "Tide Ring"),
		desc = T("Une vague circulaire repousse tout.", "A circular wave pushes everything back."),
		damage = { 8, 11, 14, 18, 23 }, cooldown = { 6, 5.5, 5, 4.5, 4 }, radius = { 9, 10, 11, 12, 13 },
		status = { { kind = "Knockback", distance = 8 } },
	}),
	Spring = tech({
		id = "Spring", line = "Maree", shape = "Heal",
		name = T("Source fraîche", "Spring"),
		desc = T("Soigne les coéquipiers proches.", "Heals nearby teammates."),
		damage = 0, cooldown = { 12, 11, 10, 9, 8 }, radius = 30, healPct = { 0.04, 0.05, 0.06, 0.07, 0.08 },
	}),
	Geyser = tech({
		id = "Geyser", line = "Maree", shape = "Target",
		name = T("Geyser", "Geyser"),
		desc = T("Un geyser projette les ennemis.", "A geyser throws enemies away."),
		damage = { 30, 40, 52, 66, 85 }, cooldown = { 9, 8.5, 8, 7.5, 7 }, radius = 7,
		status = { { kind = "Knockback", distance = 10 } },
	}),
	-- Volt
	Spark = tech({
		id = "Spark", line = "Volt", shape = "Chain",
		name = T("Étincelle", "Spark"),
		desc = T("Une étincelle saute d'ennemi en ennemi.", "A spark jumps from enemy to enemy."),
		damage = { 8, 10, 13, 17, 22 }, cooldown = { 2.5, 2.4, 2.3, 2.2, 2.0 }, targets = { 3, 3, 4, 4, 5 }, jump = 10,
	}),
	StaticField = tech({
		id = "StaticField", line = "Volt", shape = "Aura",
		name = T("Champ statique", "Static Field"),
		desc = T("De l'électricité crépite autour de toi.", "Electricity crackles around you."),
		damage = { 4, 5, 7, 9, 12 }, cooldown = 1.0, radius = { 6, 6.5, 7, 7.5, 8 },
	}),
	ThunderPounce = tech({
		id = "ThunderPounce", line = "Volt", shape = "Target",
		name = T("Bond tonnerre", "Thunder Pounce"),
		desc = T("Un bond électrique qui étourdit.", "An electric pounce that stuns."),
		damage = { 25, 34, 44, 56, 72 }, cooldown = { 7, 6.5, 6, 5.5, 5 }, radius = 5,
		status = { { kind = "Stun", duration = { 0.6, 0.7, 0.8, 0.9, 1.0 } } },
	}),
	BallLightning = tech({
		id = "BallLightning", line = "Volt", shape = "Chain",
		name = T("Boule d'éclair", "Ball Lightning"),
		desc = T("Une boule d'éclair traverse la horde.", "A lightning ball runs through the horde."),
		damage = { 18, 24, 31, 40, 52 }, cooldown = { 8, 7.5, 7, 6.5, 6 }, targets = { 6, 7, 8, 9, 10 }, jump = 12,
	}),
	-- Givre
	FrostShard = tech({
		id = "FrostShard", line = "Givre", shape = "Target",
		name = T("Éclat de givre", "Frost Shard"),
		desc = T("Un éclat qui ralentit.", "A shard that slows."),
		damage = { 10, 13, 17, 22, 28 }, cooldown = { 2.5, 2.4, 2.3, 2.2, 2.0 },
		status = { { kind = "Slow", mult = 0.6, duration = 2 } },
	}),
	IceRing = tech({
		id = "IceRing", line = "Givre", shape = "Nova",
		name = T("Anneau de glace", "Ice Ring"),
		desc = T("Gèle les ennemis autour du compagnon.", "Freezes enemies around your companion."),
		damage = { 8, 11, 14, 18, 23 }, cooldown = { 8, 7.5, 7, 6.5, 6 }, radius = { 8, 9, 10, 11, 12 },
		status = { { kind = "Freeze", duration = { 1.0, 1.2, 1.4, 1.6, 2.0 } } },
	}),
	HailVeil = tech({
		id = "HailVeil", line = "Givre", shape = "Aura",
		name = T("Voile de grêle", "Hail Veil"),
		desc = T("La grêle ralentit autour de toi.", "Hail slows enemies around you."),
		damage = { 3, 4, 5, 7, 9 }, cooldown = 1.0, radius = { 6, 6.5, 7, 7.5, 8 },
		status = { { kind = "Slow", mult = 0.7, duration = 1.5 } },
	}),
	GlacierSpike = tech({
		id = "GlacierSpike", line = "Givre", shape = "Target",
		name = T("Pic glaciaire", "Glacier Spike"),
		desc = T("Un pic de glace qui gèle un groupe.", "An ice spike that freezes a group."),
		damage = { 35, 48, 62, 80, 100 }, cooldown = { 9, 8.5, 8, 7.5, 7 }, radius = 6,
		status = { { kind = "Freeze", duration = { 1.5, 1.7, 1.9, 2.1, 2.5 } } },
	}),
	-- Echo
	SonicPing = tech({
		id = "SonicPing", line = "Echo", shape = "Target",
		name = T("Ping sonique", "Sonic Ping"),
		desc = T("Un ping qui étourdit.", "A ping that stuns."),
		damage = { 8, 11, 14, 18, 23 }, cooldown = { 2.0, 1.9, 1.8, 1.7, 1.5 },
		status = { { kind = "Stun", duration = 0.5 } },
	}),
	Screech = tech({
		id = "Screech", line = "Echo", shape = "Nova",
		name = T("Cri perçant", "Screech"),
		desc = T("Étourdit tout autour du compagnon.", "Stuns everything around your companion."),
		damage = { 8, 11, 14, 18, 23 }, cooldown = { 7, 6.5, 6, 5.5, 5 }, radius = { 10, 11, 12, 13, 14 },
		status = { { kind = "Stun", duration = { 1.0, 1.1, 1.2, 1.4, 1.6 } } },
	}),
	Ricochet = tech({
		id = "Ricochet", line = "Echo", shape = "Chain",
		name = T("Ricochet", "Ricochet"),
		desc = T("Une onde qui rebondit.", "A sound wave that bounces."),
		damage = { 10, 13, 17, 22, 28 }, cooldown = { 3, 2.9, 2.8, 2.7, 2.5 }, targets = { 3, 4, 4, 5, 6 }, jump = 12,
	}),
	Resonance = tech({
		id = "Resonance", line = "Echo", shape = "Aura",
		name = T("Résonance", "Resonance"),
		desc = T("Des basses frappent autour de toi.", "Bass hits enemies around you."),
		damage = { 4, 5, 7, 9, 12 }, cooldown = 1.0, radius = { 7, 7.5, 8, 8.5, 9 },
	}),
} :: { [string]: TechDef }

-- Reads a Num at a level / stage index (clamped to the last entry).
function Companions.at(v: Num?, i: number): number
	if v == nil then
		return 0
	elseif typeof(v) == "number" then
		return v
	end
	local list = v :: { number }
	return list[math.clamp(i, 1, #list)]
end

return Companions
