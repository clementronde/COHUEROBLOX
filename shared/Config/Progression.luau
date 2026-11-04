--!strict
-- Meta-progression tuning (data domain). Design: docs/dossier/70-donnees-progression-monetisation.md
-- Server reads everything here; the client may read it for display only.

export type UnlockRule = { free: boolean?, quest: string?, silver: number?, classId: string? }

local Progression = {}

-- Ids (docs/ARCHITECTURE.md section 3)
Progression.Classes = {
	"Cornu",
	"Plumeline",
	"Mecano",
	"Felyne",
	"Rocailleux",
	"Sporelin",
	"Ecaille",
	"Astrel",
	"Cristallin",
	"Tentaculos",
} :: { string }

Progression.Lines = { "Braise", "Ronce", "Maree", "Volt", "Givre", "Echo" } :: { string }

Progression.Worlds = { "BoisGrognon", "DunesCroustillantes", "RecreFantome" } :: { string }
Progression.MaxTier = 3

-- Class start weapons, same order as Classes (ARCHITECTURE section 3).
Progression.StartWeapon = {
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

-- Unlock rules per kind. Quest unlocks are derived from questsDone (never stored twice).
Progression.Unlocks = {
	Class = {
		Cornu = { free = true },
		Plumeline = { free = true },
		Mecano = { free = true },
		Felyne = { quest = "Q_Felyne" },
		Rocailleux = { quest = "Q_Rocailleux" },
		Sporelin = { quest = "Q_Sporelin" },
		Ecaille = { quest = "Q_Ecaille" },
		Astrel = { quest = "Q_Astrel" },
		Cristallin = { quest = "Q_Cristallin" },
		Tentaculos = { quest = "Q_Tentaculos" },
	},
	Weapon = {
		HacheBoomerang = { free = true },
		PlumesDards = { free = true },
		CleTourelle = { free = true },
		ToupieScie = { free = true },
		BouleBowling = { free = true },
		PistoletBulles = { free = true },
		GriffesEclair = { classId = "Felyne" },
		PoingSeisme = { classId = "Rocailleux" },
		NuageSpores = { classId = "Sporelin" },
		SouffleBraise = { classId = "Ecaille" },
		Meteorite = { classId = "Astrel" },
		EclatsPrisme = { classId = "Cristallin" },
		FouetTentacule = { classId = "Tentaculos" },
		CerfVolantLaser = { silver = 150 },
		ParapluieBouclier = { silver = 150 },
		BombePaillettes = { silver = 200 },
	},
	Grimoire = {
		Degats = { free = true },
		VitesseAttaque = { free = true },
		Quantite = { free = true },
		Taille = { free = true },
		Duree = { free = true },
		Vitalite = { free = true },
		Cooldown = { silver = 60 },
		Aimant = { silver = 60 },
		Savoir = { silver = 80 },
		Rempart = { silver = 80 },
		Agilite = { silver = 100 },
		Critique = { silver = 120 },
		Chance = { silver = 120 },
		Interdit = { quest = "Q_GrimoireInterdit" },
	},
	Companion = {
		Braise = { free = true },
		Ronce = { free = true },
		Maree = { free = true },
		Volt = { quest = "Q_Volt" },
		Givre = { quest = "Q_Givre" },
		Echo = { quest = "Q_Echo" },
	},
} :: { [string]: { [string]: UnlockRule } }

-- Items (Config.Items is owned by combat): an item with no `unlock` field, or unlock = "Free",
-- is in the pool; otherwise its rarity decides. Missing Config.Items => everything unlocked.
Progression.ItemSilverByRarity = {
	Common = 0, -- 0 = free
	Rare = 0,
	Epic = 60,
	Legendary = 120,
} :: { [string]: number }

-- Worlds: tier 1 unlock rule; tier n+1 needs stats["Win_<world>_T<n>"] >= 1.
Progression.WorldUnlock = {
	BoisGrognon = { free = true },
	DunesCroustillantes = { stat = "TrialShrinesCompleted", goal = 10 },
	RecreFantome = { stat = "Win_DunesCroustillantes_T2", goal = 1 },
} :: { [string]: { free: boolean?, stat: string?, goal: number? } }

Progression.DefaultLoadout = { classId = "Cornu", companionId = "Braise" }

-- Silver per run (doc 11.1)
Progression.Silver = {
	VictoryByTier = { 10, 25, 60 } :: { number },
	DefeatShare = 0.4,
	DefeatMin = 2,
	-- Anti-farm (review finding 1): a defeat pays nothing, and RunsPlayed / mastery / bond are not
	-- credited, unless the player started the run and lasted at least this long.
	MinRunSecondsForRewards = 120,
	FinalWavePer30sByTier = { 2, 5, 12 } :: { number },
	FinalWaveMaxSteps = 20,
}

-- Silver shop (doc 11.1): levels and prices. getMetaBonuses returns totals.
Progression.MetaBase = { weaponSlots = 4, grimoireSlots = 4, banish = 1, skip = 1, reroll = 2 }
Progression.ShopUpgrades = {
	Shop_GrimoireSlot = { field = "grimoireSlots", prices = { 300, 800 } },
	Shop_Banish = { field = "banish", prices = { 100, 250, 500 } },
	Shop_Skip = { field = "skip", prices = { 80, 200, 400 } },
	Shop_Reroll = { field = "reroll", prices = { 100, 250, 500 } },
} :: { [string]: { field: string, prices: { number } } }

-- Mastery 1-20 per class (cosmetic rewards only)
Progression.Mastery = {
	MaxLevel = 20,
	XpBase = 100,
	XpStep = 25, -- xp to go from n to n+1 = XpBase + XpStep * (n - 1)
	RunBase = 20,
	PerStage = 10,
	Victory = 30,
	KillsPerXp = 50,
	RunCap = 150,
	Rewards = { -- level -> cosmetic id template, "<C>" = class id
		[3] = "Tint_<C>_M3",
		[5] = "Pose_<C>_M5",
		[6] = "Tint_<C>_M6",
		[9] = "Tint_<C>_M9",
		[10] = "Title_<C>_M10",
		[12] = "Tint_<C>_M12",
		[15] = "Pose_<C>_M15",
		[20] = "Title_<C>_M20",
	} :: { [number]: string },
}

-- Bond 1-30 per companion line (<= +10 % companion stats)
Progression.Bond = {
	MaxLevel = 30,
	XpBase = 60,
	XpStep = 10,
	RunBase = 20,
	PerStage = 10,
	Victory = 20,
	RunCap = 120,
	StatBonusEvery = 3, -- +1 % every 3 levels
	StatBonusStep = 0.01,
	StatBonusMax = 0.10,
	EggAtLevel = 10, -- one free egg the first time each line reaches it
	-- Aligned with Config.Companions.Bond (companion domain): tints 4/10/20/28, pose 12, title 30.
	-- Start techniques are read by CompanionService from the bond level (StartTechUnlock).
	Rewards = { -- "<L>" = line id
		[4] = "CompanionTint_<L>_B4",
		[10] = "CompanionTint_<L>_B10",
		[12] = "Pose_<L>_B12",
		[20] = "CompanionTint_<L>_B20",
		[28] = "CompanionTint_<L>_B28",
		[30] = "Title_<L>_B30",
	} :: { [number]: string },
}

Progression.Eggs = {
	DuplicateTokens = 40, -- every line owned already
}

-- Weekly challenge (doc 5.3)
Progression.Weekly = {
	Modifiers = { "NoJump", "OneHitDown", "LavaFloor", "DoubleElites", "GlassCannon", "Fog" } :: { string },
	WorldId = "BoisGrognon",
	Tier = 1,
	RewardTokens = 50,
	RewardEggs = 1,
	FirstTimeCosmetic = "Title_Weekly",
}

-- One week formula for the whole game: Monday 00:00 UTC resets.
local SECONDS_PER_WEEK = 604800
local MONDAY_OFFSET = 345600 -- 1970-01-01 was a Thursday
function Progression.weekIndex(unixTime: number): number
	return math.floor((unixTime - MONDAY_OFFSET) / SECONDS_PER_WEEK)
end
function Progression.weekEndsAt(unixTime: number): number
	return (Progression.weekIndex(unixTime) + 1) * SECONDS_PER_WEEK + MONDAY_OFFSET
end

-- Leaderboards (OrderedDataStore). Weekly boards get "_W<week>" appended.
Progression.Leaderboards = {
	WriteSeconds = 120,
	RefreshSeconds = 120,
	RefreshJitter = 30,
	TopN = 50,
	Boards = {
		{ key = "KillsAllTime", store = "LB_Kills_AllTime_v1", weekly = false, source = "Kills" },
		{ key = "KillsWeekly", store = "LB_Kills_v1", weekly = true, source = "boards.kills" },
		{ key = "FinalWaveAllTime", store = "LB_FinalWave_AllTime_v1", weekly = false, source = "BestFinalWave" },
		{ key = "FinalWaveWeekly", store = "LB_FinalWave_v1", weekly = true, source = "boards.bestFinalWave" },
	} :: { { key: string, store: string, weekly: boolean, source: string } },
}

-- Shrine kinds counted as "trial" shrines (loot domain owns the kinds)
Progression.TrialShrineKinds = { Trial = true, Epreuve = true } :: { [string]: boolean }

-- Places (lobby/run split, doc 12.1). TODO: real place ids once both places are published.
Progression.Places = {
	LobbyPlaceId = 0,
	RunPlaceId = 0,
	RunConfigMap = "RunConfig_v1",
	RunConfigTtl = 600, -- seconds (MemoryStore: shortest sensible expiration)
	ArrivalWindow = 60, -- seconds to wait for every member before removing the config
	TeleportWatchdog = 45, -- seconds a teleported player may still be here before we re-acquire
}

-- Data timings (vault: Session Locking, Saving Correctly)
Progression.Data = {
	StoreName = "PlayerData_v1",
	LeaseSeconds = 90,
	AutosaveSeconds = 30, -- <= lease / 3
	AutosaveJitter = 5,
	LockedWaitSeconds = 100, -- keep retrying a locked key up to lease + margin
	ErrorClaimAttempts = 6,
	FinalSaveAttempts = 4,
	ShutdownBudget = 25,
	SaveSoonMin = 2,
	SaveSoonSpacing = 8,
	MaxReceipts = 100,
	MaxPurchaseLog = 50,
	SizeWarnChars = 200000,
}

return Progression
