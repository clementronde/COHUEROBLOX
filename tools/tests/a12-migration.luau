-- A12 — migration des profils v1 -> schéma courant, HORS Studio. Lancer : bash tools/tests/a12-migration.sh
-- (le script place PROGRESSION_SRC et DATASERVICE_SRC devant ce fichier). Moteur simulé : seules les
-- fonctions appelées au chargement des modules existent. Rien n'est lu ni écrit sur un DataStore.

---------------------------------------------------------------------------------------------- stubs
local function node(name: string): any
	local n = { Name = name }
	function n:WaitForChild(child: string): any
		return node(child)
	end
	n.Parent = n
	return n
end
local function signal(): any
	return { Connect = function() end, Wait = function() end }
end
local services = {
	RunService = { IsStudio = function()
		return true
	end },
	ReplicatedStorage = node("ReplicatedStorage"),
	Players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function()
		return {}
	end },
}
game = {
	GetService = function(_, name: string): any
		return services[name] or node(name)
	end,
	BindToClose = function() end,
} :: any
script = node("DataService") :: any
Instance = { new = function(): any
	return { Event = signal(), Fire = function() end }
end } :: any

local modules: { [string]: any } = {}
modules.Progression = (loadstring(PROGRESSION_SRC, "Progression") :: any)()
modules.Net, modules.Registry, modules.Bus = {}, {}, {}
require = function(m: any): any
	local mod = modules[m.Name]
	assert(mod ~= nil, `stub require: unknown module {m.Name}`)
	return mod
end :: any

local warnings = {}
warn = function(...)
	table.insert(warnings, table.concat({ ... }, " "))
end :: any

local DataService = (loadstring(DATASERVICE_SRC, "DataService") :: any)()
local migrate = DataService._migrate
local Progression = modules.Progression

---------------------------------------------------------------------------------------------- outils
local passed, failed = 0, 0
local function check(cond: any, label: string)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL " .. label)
	end
end
local function eq(a: any, b: any, label: string)
	check(a == b, `{label} (attendu {tostring(b)}, obtenu {tostring(a)})`)
end
local function deepEqual(a: any, b: any): boolean
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

---------------------------------------------------------------------------------------------- 1. profil v1 fabriqué
local function v1Profile(): any
	return {
		-- pas de champ schema : un profil v1
		createdAt = 1700000000,
		lastJoinAt = 1700100000,
		sessions = 42,
		playSeconds = 36000,
		silver = 1234,
		questTokens = 560,
		silverEarnedTotal = 9000,
		stats = {
			Kills = 6000,
			Class_Cornu_Wins = 3,
			Class_Cornu_BestLevel = 25,
			Class_Felyne_Wins = 1,
			Class_Astrel_Wins = 2,
			DamageWeapon_HacheBoomerang = 1000,
		},
		questsDone = { Q_Felyne = 111, Q_Class_Cornu_Win_1 = 222, Q_Kill_Total_1 = 333, Q_Weapon_HacheBoomerang = 444 },
		unlocks = { Weapon = { CerfVolantLaser = true }, Grimoire = { Cooldown = true }, Item = { Bouclier = true }, Companion = { Volt = true } },
		shop = { grimoireSlots = 1, banish = 2, skip = 0, reroll = 1 },
		mastery = { Cornu = 3, Felyne = 2, Astrel = 4 },
		masteryXp = { Cornu = 250, Felyne = 120, Astrel = 400 },
		bond = { Braise = 5 },
		bondXp = { Braise = 300 },
		bondEggs = { Braise = true },
		companionStartTech = { Braise = "Flame" },
		eggs = 1,
		eggsHatched = 2,
		cosmetics = { Tint_Cornu_M3 = true, Title_Weekly = true, Tint_Astrel_M3 = true, CompanionTint_Braise_B4 = true },
		equipped = { ["Tint:Cornu"] = "Tint_Cornu_M3", Title = "Title_Weekly", ["Tint:Astrel"] = "Tint_Astrel_M3" },
		settings = { keepHat = true, colorblind = false, reduceFlashes = true, textScale = 1.2 },
		loadout = { classId = "Felyne", companionId = "Braise" },
		weekly = { week = 10, done = true, bestSeconds = 300, everDone = true },
		boards = { week = 10, kills = 100, bestFinalWave = 60 },
		receipts = { ["abc-1"] = 1700000500 },
		receiptOrder = { "abc-1" },
		purchaseLog = { { k = "VIP", r = 299, t = 1700000500 } },
		vipRoomId = "GUID-1",
		flags = { boardBanned = false },
		futureField = { keep = 7 }, -- champ inconnu : doit survivre
	}
end

local before = v1Profile()
local p = migrate(v1Profile())
local legacy = p.legacy and p.legacy.classesV1

eq(p.schema, DataService.CurrentSchema, "schéma courant")
eq(p.schema, 3, "schéma 3")
-- loadout
eq(p.loadout.classId, "Rogue", "loadout Felyne -> Rogue")
eq(p.loadout.companionId, "", "compagnon v1 retiré du loadout")
check(type(p.companions) == "table" and type(p.companions.owned) == "table", "collection créée")
-- maîtrise
eq(p.masteryXp.Knight, 250, "XP Cornu -> Knight")
eq(p.masteryXp.Rogue, 120, "XP Felyne -> Rogue")
eq(p.masteryXp.Cornu, nil, "plus de clé Cornu dans masteryXp")
eq(p.masteryXp.Astrel, nil, "Astrel sorti de masteryXp")
eq(p.mastery.Knight, 3, "niveau Knight recalculé (250 XP = niveau 3)")
eq(p.mastery.Rogue, 2, "niveau Rogue recalculé (120 XP = niveau 2)")
eq(p.mastery.Cornu, nil, "plus de clé Cornu dans mastery")
check(legacy ~= nil, "legacy.classesV1 présent")
eq(legacy.masteryXp.Cornu, 250, "legacy garde l'XP Cornu")
eq(legacy.masteryXp.Astrel, 400, "legacy garde l'XP Astrel")
eq(legacy.mastery.Astrel, 4, "legacy garde le niveau Astrel")
-- cosmétiques
eq(p.cosmetics.Tint_Knight_M3, true, "Tint_Cornu_M3 -> Tint_Knight_M3")
eq(p.cosmetics.Tint_Cornu_M3, nil, "plus de Tint_Cornu_M3")
eq(p.cosmetics.Title_Weekly, true, "cosmétique sans classe gardé")
eq(p.cosmetics.CompanionTint_Braise_B4, true, "cosmétique de lignée gardé")
eq(legacy.cosmetics.Tint_Astrel_M3, true, "cosmétique Astrel dans legacy")
eq(legacy.cosmetics.Tint_Cornu_M3, true, "cosmétique Cornu d'origine dans legacy")
-- équipement
eq(p.equipped["Tint:Knight"], "Tint_Knight_M3", "emplacement Tint:Cornu -> Tint:Knight")
eq(p.equipped["Tint:Cornu"], nil, "plus d'emplacement Tint:Cornu")
eq(p.equipped["Tint:Astrel"], nil, "emplacement Astrel retiré")
eq(p.equipped.Title, "Title_Weekly", "titre gardé")
eq(legacy.equipped["Tint:Astrel"], "Tint_Astrel_M3", "équipement Astrel dans legacy")
-- stats
eq(p.stats.Class_Knight_Wins, 3, "Class_Cornu_Wins -> Class_Knight_Wins")
eq(p.stats.Class_Knight_BestLevel, 25, "Class_Cornu_BestLevel -> Class_Knight_BestLevel")
eq(p.stats.Class_Rogue_Wins, 1, "Class_Felyne_Wins -> Class_Rogue_Wins")
eq(p.stats.Class_Astrel_Wins, nil, "stat Astrel retirée")
eq(legacy.stats.Class_Astrel_Wins, 2, "stat Astrel dans legacy")
eq(p.stats.Kills, 6000, "stat globale intacte")
eq(p.stats.DamageWeapon_HacheBoomerang, 1000, "stat d'arme v1 gardée")
-- quêtes
eq(p.questsDone.Q_Rogue, 111, "Q_Felyne -> Q_Rogue (classe toujours débloquée)")
eq(p.questsDone.Q_Felyne, 111, "Q_Felyne gardée")
eq(p.questsDone.Q_Class_Knight_Win_1, 222, "Q_Class_Cornu_Win_1 -> Q_Class_Knight_Win_1")
eq(p.questsDone.Q_Class_Cornu_Win_1, 222, "Q_Class_Cornu_Win_1 gardée")
eq(p.questsDone.Q_Kill_Total_1, 333, "quête globale intacte")
eq(p.questsDone.Q_Weapon_HacheBoomerang, 444, "quête d'arme v1 gardée")
eq(p.questsDone.Q_Guardian, nil, "aucune quête de déblocage inventée")
-- le reste : intact
for _, k in { "createdAt", "lastJoinAt", "sessions", "playSeconds", "silver", "questTokens", "silverEarnedTotal", "eggs", "eggsHatched", "vipRoomId" } do
	eq(p[k], before[k], `champ {k} intact`)
end
for _, k in { "unlocks", "shop", "bond", "bondXp", "bondEggs", "companionStartTech", "weekly", "receipts", "receiptOrder", "purchaseLog", "flags", "futureField" } do
	check(deepEqual(p[k], before[k]), `table {k} intacte`)
end
-- réglages
eq(p.settings.keepHat, true, "réglage keepHat gardé")
eq(p.settings.reduceFlashes, true, "réglage reduceFlashes gardé")
eq(p.settings.textScale, 1.2, "réglage textScale gardé")
eq(p.settings.masterVolume, 1, "masterVolume ajouté (1)")
eq(p.settings.musicVolume, 0.7, "musicVolume ajouté (0,7)")
eq(p.settings.sfxVolume, 1, "sfxVolume ajouté (1)")
-- classements
eq(p.boards.kills, 100, "compteur v1 boards.kills gardé")
eq(p.boards.bestFinalWave, 60, "boards.bestFinalWave gardé")
eq(p.boards.bestKills, 0, "bestKills initialisé à 0")

---------------------------------------------------------------------------------------------- 2. schéma 2 mixte (v1 + v2)
local s2 = migrate(v1Profile()) -- base valide
s2.schema = 2
s2.legacy = nil
s2.masteryXp = { Knight = 100, Cornu = 250 }
s2.mastery = { Knight = 2, Cornu = 3 }
s2.stats = { Class_Knight_Wins = 2, Class_Cornu_Wins = 3, Class_Knight_BestLevel = 30, Class_Cornu_BestLevel = 25 }
s2.equipped = { ["Tint:Knight"] = "Tint_Knight_Base1", ["Tint:Cornu"] = "Tint_Cornu_M3" }
s2.cosmetics = { Tint_Cornu_M3 = true }
s2.questsDone = { Q_Rogue = 50, Q_Felyne = 111 }
s2.loadout = { classId = "Knight", companionId = "" }
s2.boards.best = { ko = 420 }
s2.boards.weekBest = { ko = 500, week = 3 }
s2.boards.bestKills = nil
local m = migrate(s2)
eq(m.schema, 3, "2 -> 3")
eq(m.masteryXp.Knight, 350, "XP v2 + v1 additionnées")
eq(m.mastery.Knight, 3, "niveau recalculé sur l'XP fusionnée")
eq(m.stats.Class_Knight_Wins, 5, "compteurs additionnés")
eq(m.stats.Class_Knight_BestLevel, 30, "record : le max")
eq(m.equipped["Tint:Knight"], "Tint_Knight_Base1", "choix v2 déjà fait gardé")
eq(m.legacy.classesV1.equipped["Tint:Cornu"], "Tint_Cornu_M3", "choix v1 dans legacy")
eq(m.questsDone.Q_Rogue, 50, "quête v2 déjà faite : horodatage gardé")
eq(m.loadout.classId, "Knight", "loadout v2 intact")
eq(m.boards.bestKills, 500, "bestKills = meilleur relevé existant")
for lvl, template in Progression.Mastery.Rewards do
	if lvl <= 3 then
		eq(m.cosmetics[(string.gsub(template, "<C>", "Knight"))], true, `récompense de maîtrise niveau {lvl}`)
	end
end

---------------------------------------------------------------------------------------------- 3. stabilité et refus
local again = migrate(DataService.deepCopy(p))
check(deepEqual(again, p), "un profil déjà au schéma courant ne change pas")

local fresh = DataService._newProfile()
check(deepEqual(migrate(DataService.deepCopy(fresh)), fresh), "nouveau profil inchangé par migrate")
eq(fresh.settings.musicVolume, 0.7, "nouveau profil : musicVolume 0,7")
eq(fresh.boards.bestKills, 0, "nouveau profil : bestKills 0")

local okNewer = pcall(migrate, { schema = 99 })
check(not okNewer, "schéma plus récent refusé")
local okBad = pcall(migrate, "pas une table")
check(not okBad, "profil illisible refusé")

-- Valeurs corrompues : pas d'erreur, pas de NaN
local weird = v1Profile()
weird.masteryXp = { Cornu = 0 / 0, Felyne = "x" }
weird.stats = { Class_Cornu_Wins = math.huge }
local okWeird, w = pcall(migrate, weird)
check(okWeird, "valeurs corrompues : migration sans erreur")
if okWeird then
	check(w.masteryXp.Knight == 0, "XP NaN -> 0")
	check(w.stats.Class_Knight_Wins == 0, "stat infinie -> 0")
	local function finite(t: any, path: string): string?
		for k, v in t do
			if type(v) == "number" and not (v == v and v > -math.huge and v < math.huge) then
				return `{path}.{tostring(k)}`
			elseif type(v) == "table" then
				local bad = finite(v, `{path}.{tostring(k)}`)
				if bad then
					return bad
				end
			end
		end
		return nil
	end
	local bad = finite(w.legacy, "legacy")
	check(bad == nil, `aucun NaN / infini dans legacy ({tostring(bad)})`)
end

print(`a12-migration : {passed} ok, {failed} échec(s)`)
if failed > 0 then
	error("a12-migration : échecs")
end
