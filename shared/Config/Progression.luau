--!strict
-- Meta-progression tuning (data domain). Design: docs/dossier/70-donnees-progression-monetisation.md
-- Server reads everything here; the client may read it for display only.

export type UnlockRule = { free: boolean?, quest: string?, silver: number?, classId: string? }

local Progression = {}

-- Classes v2 (01-decisions-v2 §3 ; ids de shared/Config/Classes.luau, domaine avatar).
-- Knight, Archer, Mage gratuites ; les autres par quête. Jamais vendues.
Progression.Classes = {
	"Knight",
	"Archer",
	"Mage",
	"Guardian",
	"Rogue",
	"Cleric",
	"Barbarian",
	"Tamer",
} :: { string }

-- Lignées v1 (évolution, Lien, œufs) : plus de contenu en v2 (capture et collection, dossier 40).
-- Gardées pour lire les vieux profils et les cosmétiques de Lien déjà accordés.
Progression.Lines = { "Braise", "Ronce", "Maree", "Volt", "Givre", "Echo" } :: { string }

Progression.Worlds = { "BoisGrognon", "DunesCroustillantes", "RecreFantome" } :: { string }
Progression.MaxTier = 3

-- Arme de départ de chaque classe (lue dans Config.Classes[classId].startWeapon, domaine avatar).
Progression.StartWeapon = {
	Knight = "Broadsword",
	Archer = "Longbow",
	Mage = "FireStaff",
	Guardian = "QuakeHammer",
	Rogue = "ThrowingDaggers",
	Cleric = "HolyAura",
	Barbarian = "SpinningAxes",
	Tamer = "BeastWhip",
} :: { [string]: string }

-- Unlock rules per kind. Quest unlocks are derived from questsDone (never stored twice).
Progression.Unlocks = {
	Class = {
		Knight = { free = true },
		Archer = { free = true },
		Mage = { free = true },
		Guardian = { quest = "Q_Guardian" },
		Rogue = { quest = "Q_Rogue" },
		Cleric = { quest = "Q_Cleric" },
		Barbarian = { quest = "Q_Barbarian" },
		Tamer = { quest = "Q_Tamer" },
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
	-- Companion : plus de regle en v2. Un compagnon se capture (ProgressionService.hasCompanion).
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

-- companionId "" = aucun : la collection est vide à la première run (dossier 40 §11.1, défaut).
Progression.DefaultLoadout = { classId = "Knight", companionId = "" }

-- Collection de compagnons (A12-01) : clés d'idempotence de capture gardées dans le profil.
Progression.Collection = { MaxKeys = 200 }

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

-- Classements v2 (A12-02, docs/security/regles-v2.md §4) : meilleur nombre de KO en UNE run.
-- OrderedDataStore = index, le profil (boards.best / boards.weekBest) = vérité.
-- Hebdo : store "<store>_W<week>" (week = weekIndex, reset lundi 00:00 UTC par le nom, sans suppression).
-- Écrit une fois par run et par joueur, par le serveur de run, en fin de run ou au départ du joueur.
Progression.Leaderboards = {
	RefreshSeconds = 120, -- lecture des tops (par serveur)
	RefreshJitter = 30,
	TopN = 100, -- GetSortedAsync(false, 100)
	MaxValue = 10_000_000, -- borne d'une valeur écrite
	WriteAttempts = 3,
	Boards = {
		{ key = "KoRunWeekly", store = "LB_KoRun", weekly = true },
		{ key = "KoRunAllTime", store = "LB_KoRun_AllTime_v1", weekly = false },
	} :: { { key: string, store: string, weekly: boolean } },
	-- §4.3.1 (décision de Clément en attente) : seuls les KO faits jusqu'à N s d'Overtime cumulé
	-- comptent au classement. 0 = désactivé (tous les KO de la run comptent).
	ScoreWindowOvertimeSeconds = 0,
	-- Signaux de quarantaine (§2.3, §4.5). Un seuil non mesuré en playtest ne fait que journaliser.
	Quarantine = {
		MaxStrikes = 3, -- MovementGuard.getRunStrikes >= 3 -> quarantaine
		MaxInvulnShare = 0.3, -- temps invulnérable / durée de la run (RunManager.getInvulnerableSeconds)
		MinRunSecondsForShare = 60, -- en dessous, la part d'invulnérabilité n'est pas jugée
		NoDamageAfterOvertime = 180, -- à partir de +03:00 d'Overtime...
		NoDamageSeconds = 180, -- ...3 min d'affilée sans dégât subi en étant actif
		NoDamageEnforce = false, -- log seul tant que non mesuré
		KoPerMinuteCap = 0, -- 0 = pas encore mesuré (p99,9 x 1,5) : log seul au-delà de KoPerMinuteLog
		KoPerMinuteLog = 600,
		KeepRecords = 20, -- relevés de runs en quarantaine gardés dans le profil
		BanCount = 3, -- 3 runs en quarantaine...
		BanWindowDays = 7, -- ...en 7 jours -> flags.boardBanned + retrait des deux classements
	},
	-- Ban manuel (Clément seulement) : userIds exclus à l'écriture ET à la lecture.
	BoardBans = {} :: { number },
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
