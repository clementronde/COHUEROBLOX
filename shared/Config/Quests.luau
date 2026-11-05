--!strict
-- Quests and quest stat keys (data domain). Design: docs/dossier/70-donnees-progression-monetisation.md
-- sections 11-12. Quest ids are stable: never rename or reuse one (profiles store them).
--
-- Progress of a quest = profile.stats[quest.stat] (lifetime sum, or record for "max" keys).
-- Other domains call ProgressionService.recordStat(player, key, amount) ONLY with ExternalKeys.
-- AutoKeys are recorded by the data domain itself (Bus events + RunSummary): do not call them.

export type Reward = {
	tokens: number?,
	silver: number?,
	egg: number?,
	unlock: { kind: string, id: string }?, -- informational: unlocks are derived from questsDone
	cosmetic: string?,
}
export type QuestDef = {
	id: string,
	category: string, -- Unlock | Kill | Weapon | Survive | Explore | Mastery | Class | Companion | Coop
	stat: string,
	goal: number,
	reward: Reward,
	name: { fr: string, en: string },
}

local Quests = {}

local CLASSES = { "Knight", "Archer", "Mage", "Guardian", "Rogue", "Cleric", "Barbarian", "Tamer" }
local WORLDS = { "BoisGrognon", "DunesCroustillantes", "RecreFantome" }
local WORLD_NAMES = {
	BoisGrognon = { fr = "Bois Grognon", en = "Grumblewood" },
	DunesCroustillantes = { fr = "Dunes Croustillantes", en = "Crispy Dunes" },
	RecreFantome = { fr = "Récré Fantôme", en = "Ghost Recess" },
}
local WEAPONS = {
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
}
local FAMILIES = {
	Swarm = { fr = "essaim", en = "swarm", goals = { 250, 1000, 5000 } },
	Jumper = { fr = "sauteurs", en = "jumpers", goals = { 100, 500, 2000 } },
	Shooter = { fr = "tireurs", en = "shooters", goals = { 100, 500, 2000 } },
	Armored = { fr = "blindés", en = "armored", goals = { 50, 250, 1000 } },
}
local FAMILY_ORDER = { "Swarm", "Jumper", "Shooter", "Armored" }

-- Keys other domains record (anything else from outside is ignored with a warning).
Quests.ExternalKeys = {
	-- loot
	ChestsOpened = true,
	CoinsCollected = true,
	PotsBroken = true,
	ChestsBought = true,
	MerchantPurchases = true,
	-- loot (shrines)
	BossChallengesAccepted = true,
	AllShrinesCharged = true,
	TrialShrinesCompleted = true,
	RecessBellsRung = true,
	TeamTotemsActivated = true,
	PiggyBanksBroken = true,
	ShrinesCharged = true,
	GoldenShrinesCharged = true,
	PranksterUses = true,
	-- companion
	CompanionEvolved = true,
	CompanionStage3 = true,
	UltimatesUsed = true,
	CompanionKills = true,
	CompanionTechsLearned = true,
	CompanionTreats = true,
	CompanionsCaptured = true, -- v2 (A05)
	CompanionNewSpecies = true, -- v2 (A05)
	-- avatar
	Hops = true,
	DistanceTraveled = true,
	SlideCharges = true,
	-- combat
	WeaponsFused = true,
	CardsPicked = true,
	-- run
	BossFast30 = true,
	-- ui
	PingsSent = true,
} :: { [string]: boolean }

-- Keys recorded by the data domain. Exact keys, plus prefixes for per-id keys.
Quests.AutoKeys = {
	Kills = true,
	KillsElite = true,
	DamageTaken = true,
	Revives = true,
	ShrinesCompleted = true,
	ShrinesCoop = true,
	BossesDefeated = true,
	StagesCleared = true,
	FullBuildStageClears = true,
	BossNoDamage = true,
	CoopRuns = true,
	RunsPlayed = true,
	Wins = true,
	WinsTier3 = true,
	WinNoDown = true,
	CoopFullWins = true,
	FinalWaveSecondsTotal = true,
	BestFinalWave = true,
	BestRunLevel = true,
	DamageDealt = true,
} :: { [string]: boolean }
Quests.AutoPrefixes = {
	"KillsFamily_",
	"BossesDefeated_",
	"Win_",
	"DamageWeapon_",
	"Class_",
	"Companion_",
	"Bond_",
} :: { string }

-- Record keys keep the highest value instead of summing.
Quests.MaxKeys = { BestFinalWave = true, BestRunLevel = true } :: { [string]: boolean }
Quests.MaxSuffixes = { "_BestLevel" } :: { string }
Quests.MaxPrefixes = { "Bond_" } :: { string }

Quests.MaxPerCall = 1000000

local list: { QuestDef } = {}
local byId: { [string]: QuestDef } = {}

local function q(id: string, category: string, stat: string, goal: number, reward: Reward, fr: string, en: string)
	assert(byId[id] == nil, `duplicate quest {id}`)
	local def: QuestDef = { id = id, category = category, stat = stat, goal = goal, reward = reward, name = { fr = fr, en = en } }
	table.insert(list, def)
	byId[id] = def
end

local TOKENS = { 10, 20, 35, 50, 75, 100, 150 }

-- Unlock (6) : classes v2 (01-decisions-v2 §3) + Rune interdite. Les compagnons se capturent.
q("Q_Guardian", "Unlock", "DamageTaken", 50000, { tokens = 30, unlock = { kind = "Class", id = "Guardian" } }, "Encaisser 50 000 dégâts", "Take 50,000 damage")
q("Q_Rogue", "Unlock", "Kills", 5000, { tokens = 30, unlock = { kind = "Class", id = "Rogue" } }, "Vaincre 5 000 ennemis", "Defeat 5,000 enemies")
q("Q_Cleric", "Unlock", "ShrinesCompleted", 25, { tokens = 30, unlock = { kind = "Class", id = "Cleric" } }, "Compléter 25 autels", "Complete 25 shrines")
q("Q_Barbarian", "Unlock", "BossesDefeated", 5, { tokens = 30, unlock = { kind = "Class", id = "Barbarian" } }, "Vaincre 5 boss", "Defeat 5 bosses")
q("Q_Tamer", "Unlock", "CompanionsCaptured", 10, { tokens = 30, unlock = { kind = "Class", id = "Tamer" } }, "Capturer 10 créatures", "Capture 10 creatures")
q("Q_GrimoireInterdit", "Unlock", "WinsTier3", 1, { tokens = 50, unlock = { kind = "Grimoire", id = "Interdit" } }, "Gagner un Tier 3", "Win a Tier 3 run")

-- Kill (31)
local killGoals = { 500, 2000, 5000, 10000, 25000, 50000, 100000 }
for i, goal in killGoals do
	local reward: Reward = { tokens = TOKENS[i] }
	if i == 5 then
		reward.cosmetic = "Title_Centurion"
	end
	q(`Q_Kill_Total_{i}`, "Kill", "Kills", goal, reward, `Vaincre {goal} ennemis`, `Defeat {goal} enemies`)
end
for i, goal in { 10, 50, 200 } do
	q(`Q_Kill_Elite_{i}`, "Kill", "KillsElite", goal, { tokens = TOKENS[i + 1] }, `Vaincre {goal} élites`, `Defeat {goal} elites`)
end
for _, fam in FAMILY_ORDER do
	local f = FAMILIES[fam]
	for i, goal in f.goals do
		q(`Q_Kill_{fam}_{i}`, "Kill", `KillsFamily_{fam}`, goal, { tokens = TOKENS[i] }, `Vaincre {goal} ennemis ({f.fr})`, `Defeat {goal} {f.en} enemies`)
	end
end
for i, goal in { 1, 10, 50 } do
	q(`Q_Boss_Total_{i}`, "Kill", "BossesDefeated", goal, { tokens = TOKENS[i + 1], silver = if i == 3 then 100 else nil }, `Vaincre {goal} boss`, `Defeat {goal} bosses`)
end
for _, w in WORLDS do
	for i, goal in { 1, 10 } do
		q(`Q_Boss_{w}_{i}`, "Kill", `BossesDefeated_{w}`, goal, { tokens = TOKENS[i + 1] }, `Vaincre {goal} boss de {WORLD_NAMES[w].fr}`, `Defeat {goal} {WORLD_NAMES[w].en} bosses`)
	end
end

-- Weapon (16)
for _, w in WEAPONS do
	q(`Q_Weapon_{w}`, "Weapon", `DamageWeapon_{w}`, 50000, { tokens = 25 }, `Infliger 50 000 dégâts avec {w}`, `Deal 50,000 damage with {w}`)
end

-- Survive (25)
for i, goal in { 60, 300, 900, 1800 } do
	q(`Q_FinalWave_Total_{i}`, "Survive", "FinalWaveSecondsTotal", goal, { tokens = TOKENS[i + 1], silver = 20 * i }, `Survivre {goal} s en Vague Finale (cumulé)`, `Survive {goal} s of Final Wave (total)`)
end
for i, goal in { 60, 120, 180, 300 } do
	local reward: Reward = { tokens = TOKENS[i + 1] }
	if i == 4 then
		reward.cosmetic = "Title_Survivant"
	end
	q(`Q_FinalWave_Best_{i}`, "Survive", "BestFinalWave", goal, reward, `Survivre {goal} s en Vague Finale en une run`, `Survive {goal} s of Final Wave in one run`)
end
for i, goal in { 1, 10, 50, 100, 250 } do
	local reward: Reward = { tokens = TOKENS[i] }
	if i == 2 then
		reward.egg = 1
	elseif i == 5 then
		reward.cosmetic = "Title_Infatigable"
	end
	q(`Q_Runs_{i}`, "Survive", "RunsPlayed", goal, reward, `Jouer {goal} run(s)`, `Play {goal} run(s)`)
end
for i, goal in { 1, 10, 50 } do
	q(`Q_Wins_{i}`, "Survive", "Wins", goal, { tokens = TOKENS[i + 1], egg = if i == 2 then 1 else nil }, `Gagner {goal} run(s)`, `Win {goal} run(s)`)
end
for _, w in WORLDS do
	for tier = 1, 3 do
		q(`Q_Win_{w}_T{tier}`, "Survive", `Win_{w}_T{tier}`, 1, { tokens = 20 * tier, silver = 15 * tier }, `Gagner {WORLD_NAMES[w].fr} Tier {tier}`, `Win {WORLD_NAMES[w].en} Tier {tier}`)
	end
end

-- Explore (14)
for i, goal in { 25, 250, 1000 } do
	q(`Q_Chests_{i}`, "Explore", "ChestsOpened", goal, { tokens = TOKENS[i + 1], cosmetic = if i == 3 then "Title_Collectionneur" else nil }, `Ouvrir {goal} coffres`, `Open {goal} chests`)
end
for i, goal in { 10, 50, 200 } do
	q(`Q_Shrines_{i}`, "Explore", "ShrinesCompleted", goal, { tokens = TOKENS[i + 1] }, `Compléter {goal} autels`, `Complete {goal} shrines`)
end
for i, goal in { 25, 100 } do
	q(`Q_Trials_{i}`, "Explore", "TrialShrinesCompleted", goal, { tokens = TOKENS[i + 2] }, `Réussir {goal} autels d'épreuve`, `Clear {goal} trial shrines`)
end
for i, goal in { 1000, 10000, 50000 } do
	q(`Q_Coins_{i}`, "Explore", "CoinsCollected", goal, { tokens = TOKENS[i] }, `Ramasser {goal} pièces`, `Collect {goal} coins`)
end
for i, goal in { 5, 25, 100 } do
	q(`Q_Stages_{i}`, "Explore", "StagesCleared", goal, { tokens = TOKENS[i + 1] }, `Terminer {goal} stages`, `Clear {goal} stages`)
end

-- Mastery (11)
for i, goal in { 1, 5 } do
	q(`Q_BossNoDamage_{i}`, "Mastery", "BossNoDamage", goal, { tokens = TOKENS[i + 3] }, `Vaincre {goal} boss sans dégât`, `Defeat {goal} boss(es) without damage`)
end
for i, goal in { 1, 5 } do
	q(`Q_BossFast_{i}`, "Mastery", "BossFast30", goal, { tokens = TOKENS[i + 3], cosmetic = if i == 2 then "Aura_Flammeche" else nil }, `Vaincre {goal} boss en moins de 30 s`, `Defeat {goal} boss(es) in under 30 s`)
end
for i, goal in { 1, 10 } do
	q(`Q_Fusion_{i}`, "Mastery", "WeaponsFused", goal, { tokens = TOKENS[i + 2] }, `Fusionner {goal} arme(s)`, `Fuse {goal} weapon(s)`)
end
for i, goal in { 20, 30, 40 } do
	q(`Q_RunLevel_{i}`, "Mastery", "BestRunLevel", goal, { tokens = TOKENS[i + 1], cosmetic = if i == 3 then "Footstep_Etincelles" else nil }, `Atteindre le niveau {goal} en run`, `Reach level {goal} in a run`)
end
for i, goal in { 1, 10 } do
	q(`Q_WinNoDown_{i}`, "Mastery", "WinNoDown", goal, { tokens = TOKENS[i + 3] }, `Gagner {goal} run(s) sans être à terre`, `Win {goal} run(s) without going down`)
end

-- Class (30)
for _, c in CLASSES do
	q(`Q_Class_{c}_Level30`, "Class", `Class_{c}_BestLevel`, 30, { tokens = 40 }, `Niveau 30 avec {c}`, `Level 30 with {c}`)
	q(`Q_Class_{c}_Win_1`, "Class", `Class_{c}_Wins`, 1, { tokens = 25 }, `Gagner une run avec {c}`, `Win a run with {c}`)
	q(`Q_Class_{c}_Win_2`, "Class", `Class_{c}_Wins`, 10, { tokens = 60 }, `Gagner 10 runs avec {c}`, `Win 10 runs with {c}`)
end

-- Companion (6) : capture et collection (dossier 40 §9 ; clés envoyées par CompanionService).
for i, goal in { 1, 10, 50 } do
	q(`Q_Capture_{i}`, "Companion", "CompanionsCaptured", goal, { tokens = TOKENS[i + 1], cosmetic = if i == 3 then "Title_Dresseur" else nil }, `Capturer {goal} créature(s)`, `Capture {goal} creature(s)`)
end
for i, goal in { 3, 10, 25 } do
	q(`Q_Species_{i}`, "Companion", "CompanionNewSpecies", goal, { tokens = TOKENS[i + 2] }, `Collectionner {goal} espèces`, `Collect {goal} species`)
end

-- Coop (10)
for i, goal in { 1, 10, 50 } do
	q(`Q_Coop_Revive_{i}`, "Coop", "Revives", goal, { tokens = TOKENS[i + 1], cosmetic = if i == 3 then "Title_Sauveteur" else nil }, `Relever {goal} coéquipier(s)`, `Revive {goal} teammate(s)`)
end
for i, goal in { 1, 10, 50 } do
	q(`Q_Coop_Runs_{i}`, "Coop", "CoopRuns", goal, { tokens = TOKENS[i], egg = if i == 2 then 1 else nil }, `Jouer {goal} run(s) en coop`, `Play {goal} coop run(s)`)
end
for i, goal in { 1, 10 } do
	q(`Q_Coop_Full_{i}`, "Coop", "CoopFullWins", goal, { tokens = TOKENS[i + 2] }, `Gagner {goal} run(s) à 4`, `Win {goal} run(s) as a team of 4`)
end
for i, goal in { 10, 50 } do
	q(`Q_Coop_Shrine_{i}`, "Coop", "ShrinesCoop", goal, { tokens = TOKENS[i + 1] }, `Compléter {goal} autels à plusieurs`, `Complete {goal} shrines together`)
end

Quests.List = list
Quests.ById = byId

-- stat key -> quests using it (server indexes completion checks with this)
local byStat: { [string]: { QuestDef } } = {}
for _, def in list do
	local bucket = byStat[def.stat]
	if not bucket then
		bucket = {}
		byStat[def.stat] = bucket
	end
	table.insert(bucket, def)
end
Quests.ByStat = byStat

function Quests.isAutoKey(key: string): boolean
	if Quests.AutoKeys[key] then
		return true
	end
	for _, prefix in Quests.AutoPrefixes do
		if string.sub(key, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

function Quests.isMaxKey(key: string): boolean
	if Quests.MaxKeys[key] then
		return true
	end
	for _, prefix in Quests.MaxPrefixes do
		if string.sub(key, 1, #prefix) == prefix then
			return true
		end
	end
	for _, suffix in Quests.MaxSuffixes do
		if #key > #suffix and string.sub(key, -#suffix) == suffix then
			return true
		end
	end
	return false
end

return Quests
