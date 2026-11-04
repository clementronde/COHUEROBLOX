--!strict
-- Run flow tuning (docs/dossier/20-run-mondes-boss.md sections 1, 2, 6).
-- Density curve and base coop scaling are read from Balance (lead-owned).

local Run = {
	-- Single-place test flow (ARCHITECTURE section 7). MatchService reads this.
	UseLobbyPlace = false,
	SurvivalEnabled = false, -- Survival mode behind a flag (doc 5.3)
	Mode = "Adventure" :: "Adventure" | "Survival",

	DefaultWorld = "BoisGrognon",
	DefaultTier = 1,
	DefaultClass = "Knight",
	DefaultCompanion = "Braise",
	LoadoutTimeout = 45, -- seconds before a player without a loadout gets the default
	StudioLoadoutTimeout = 5,
	ReplayTimeout = 10,

	-- Timers
	StageSeconds = 600,
	Waves = {
		{ timeLeft = 360, size = 40, boost = 1.3, boostSeconds = 45, spawnSeconds = 4 },
		{ timeLeft = 180, size = 60, boost = 1.3, boostSeconds = 45, spawnSeconds = 4 },
	},
	ArcheRevealRadius = 25,
	ArenaRadius = 60,
	ArenaStartSeconds = 20,
	FarmSeconds = 60,
	PortalRadius = 8,
	FinalWaveCoinsPer30s = 20, -- x tier
	FinalWaveHpRampPer30s = 0.15,
	PhaseDensity = { Running = 1, Boss = 0.4, BossDefeated = 1, FinalWave = 1 } :: { [string]: number },

	-- Player vitals
	Player = {
		BaseMaxHp = 100,
		DodgeCap = 0.6,
		ArmorK = 100, -- taken = amount * K / (K + armor)
		RegenInterval = 0.25,
		ContactHz = 15,
		ContactCooldown = 0.5,
		ContactMaxEnemies = 3,
		ContactHalfWidth = 1.5,
		ContactVerticalSlack = 2,
		EliteDamageMult = 1.5,
	},
	Coop = {
		DownedSeconds = 25,
		ReviveRadius = 6,
		ReviveSeconds = 3,
		ReviveDecay = 2, -- progress lost per second (x ReviveSeconds) when nobody is near
		ReviveHpFraction = 0.3,
		ReviveInvulnerable = 2,
		DownedSlow = 0.35,
		GhostShrineRate = 0.25, -- read by ShrineService (loot)
		GhostReturnHpFraction = 0.5, -- ghosts come back at the next stage
		GhostTransparency = 0.7,
	},
	VitalsMaxHz = 10,

	-- Tier / stage multipliers
	TierHp = { 1, 1.8, 3 },
	TierDamage = { 1, 1.35, 1.8 },
	TierSpeed = { 1, 1.05, 1.1 },
	TierDensity = { 1, 1.15, 1.3 },
	StageHpPer = 0.4, -- x (1 + 0.4 (stage - 1))
	StageDamagePer = 0.2,

	-- Spawn mix (seconds since stage start)
	FamilyUnlock = { Swarm = 0, Jumper = 30, Shooter = 120, Armored = 210 } :: { [string]: number },
	EliteFirstAt = 90,
	EliteEvery = 75,
	EliteChance = 0.005,
	EliteMaxAlive = 4,
	EliteHpMult = 6,
	EliteSizeMult = 1.3,
	MiniBossAt = { 180, 420 },

	-- Survival mode (doc 5.3)
	Survival = {
		TierSeconds = 120,
		HpPerTier = 1.3, -- multiplicative
		DamagePerTier = 1.15,
		DensityPerTier = 0.12,
		EliteEvery = 60,
		MiniBossEvery = 240,
		CoinsPer30s = 20,
	},

	-- Unlocks (read by the data domain): tier N of a world needs the previous tier cleared.
	TierUnlock = {
		[2] = { tier = 1, stage = 1, text = { fr = "Battre le boss du stage 1 en Tier 1", en = "Beat the stage 1 boss in Tier 1" } },
		[3] = { tier = 2, stage = 2, text = { fr = "Battre le boss du stage 2 en Tier 2", en = "Beat the stage 2 boss in Tier 2" } },
	},

	Debug = {
		AllowAnyStageInStudio = true,
	},
}

return Run
