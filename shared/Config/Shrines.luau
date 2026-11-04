--!strict
-- Shrine tuning (docs/dossier/30-butin-autels.md section 6). Every shrine number lives here.

local Shrines = {}

Shrines.SimHz = 10
Shrines.StateMaxPerSecond = 4
Shrines.Radius = 8
Shrines.DecayTime = 1.5 -- seconds for progress to fall from 1 to 0 when the circle is empty
Shrines.GhostWeight = 0.25 -- vision 5.2
-- Effective chargers -> speed multiplier, linear between points, clamped after the last.
Shrines.CoopSpeed = { { 0, 0 }, { 1, 1 }, { 2, 1.5 }, { 3, 2 } } :: { { number } }
Shrines.OfferTimeout = 15
Shrines.InteractRange = 10

export type KindDef = {
	name: { fr: string, en: string },
	count: number, -- per stage
	chargeTime: number, -- seconds solo (0 = interaction only)
	minPlayers: number?, -- active players in the circle needed to charge
	color: Color3,
}

Shrines.Kinds = {
	Charge = {
		name = { fr = "Autel de charge", en = "Charge shrine" },
		count = 15,
		chargeTime = 6,
		color = Color3.fromRGB(80, 170, 255),
	},
	Golden = {
		name = { fr = "Autel doré", en = "Golden shrine" },
		count = 0, -- rolled from Charge shrines (GoldenChance)
		chargeTime = 9,
		color = Color3.fromRGB(255, 200, 50),
	},
	Trial = {
		name = { fr = "Autel d'épreuve", en = "Trial shrine" },
		count = 2,
		chargeTime = 3,
		color = Color3.fromRGB(230, 70, 70),
	},
	BossChallenge = {
		name = { fr = "Autel du défi du boss", en = "Boss challenge shrine" },
		count = 1,
		chargeTime = 4,
		color = Color3.fromRGB(140, 20, 40),
	},
	Prankster = {
		name = { fr = "Distributeur farceur", en = "Prank vending machine" },
		count = 1,
		chargeTime = 0,
		color = Color3.fromRGB(255, 120, 200),
	},
	PiggyBank = {
		name = { fr = "Tirelire avide", en = "Greedy piggy bank" },
		count = 1,
		chargeTime = 3,
		color = Color3.fromRGB(255, 150, 170),
	},
	RecessBell = {
		name = { fr = "Cloche de récré", en = "Recess bell" },
		count = 1,
		chargeTime = 3,
		color = Color3.fromRGB(240, 220, 120),
	},
	TeamTotem = {
		name = { fr = "Totem d'équipe", en = "Team totem" },
		count = 1,
		chargeTime = 5,
		minPlayers = 2,
		color = Color3.fromRGB(90, 220, 120),
	},
} :: { [string]: KindDef }

-- Spawn order (the first points go to the first kinds, so specials exist even on small maps).
Shrines.SpawnOrder = { "Trial", "BossChallenge", "Prankster", "PiggyBank", "RecessBell", "TeamTotem", "Charge" } :: { string }
Shrines.VerticalTolerance = 6 -- studs: a player under a high shrine does not charge it

Shrines.GoldenChance = 0.08

-- Stat choices (Charge / Golden)
Shrines.ChoiceCount = 3
Shrines.ChoiceRarity = { 60, 28, 10, 2 } :: { number } -- + Luck via Config.Loot.rarityWeights
Shrines.StatPool = {
	Damage = { 0.05, 0.08, 0.12, 0.18 },
	AttackSpeed = { 0.05, 0.08, 0.12, 0.18 },
	MaxHp = { 10, 16, 25, 40 },
	Armor = { 1, 2, 3, 5 },
	MoveSpeed = { 0.04, 0.06, 0.09, 0.13 },
	CritChance = { 0.02, 0.035, 0.05, 0.08 },
	Luck = { 1, 2, 3, 5 },
	XpGain = { 0.06, 0.1, 0.15, 0.22 },
	Magnet = { 2, 3, 5, 8 },
	Size = { 0.05, 0.08, 0.12, 0.18 },
	Regen = { 0.2, 0.35, 0.5, 0.8 },
	Dodge = { 0.015, 0.025, 0.04, 0.06 },
} :: { [string]: { number } }

-- Trial
Shrines.TrialEnemies = 5
Shrines.TrialEnemiesPerExtraPlayer = 2
Shrines.TrialEnemyKind = 2 -- Config.Enemies kind id (run domain)
Shrines.TrialSpawnRadius = 14
Shrines.TrialTimeLimit = 90

-- Boss challenge vote
Shrines.VoteDuration = 20

-- Prankster
Shrines.PranksterCost = 25
Shrines.PranksterCostStep = 15 -- per previous use by the same player
Shrines.PranksterRarity = "Normal" -- Config.Loot.ChestRarity key
Shrines.GagDuration = 20
Shrines.Gags = { "CameraTilt", "Disco", "Confetti" } :: { string }

-- Piggy bank
Shrines.PiggyCoins = 40
Shrines.PiggyStageBonus = 0.5
Shrines.PiggyLootBonus = 0.25
Shrines.PiggyDifficulty = 0.10

-- Recess bell
Shrines.BellRadius = 40
Shrines.BellDuration = 5
Shrines.BellPullEvery = 0.5
Shrines.BellPullDistance = 10 -- studs per pull
Shrines.BellXpMult = 2
Shrines.BellXpGrace = 1 -- extra seconds the XP bonus lasts

-- Team totem
Shrines.TotemDuration = 60
Shrines.TotemBuff = { Damage = 0.15, MoveSpeed = 0.10, Armor = 3 } :: { [string]: number }

-- Visuals (client)
Shrines.FX = {
	CircleHeight = 0.2,
	PillarSize = Vector3.new(2, 6, 2),
	GoldenLightRange = 14,
	GoldenLightBrightness = 1.5,
	TiltDegrees = 7,
	DiscoCycle = 4,
	ConfettiCount = 40,
}

return Shrines
