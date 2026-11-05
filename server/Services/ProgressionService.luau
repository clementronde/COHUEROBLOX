--!strict
-- Meta-progression (data domain): unlocks, loadout, quests/stats, silver shop, mastery, bond, eggs,
-- weekly challenge, run rewards, leaderboards, analytics, Profile replication.
-- Design: docs/dossier/70-donnees-progression-monetisation.md (sections 4-14, 16).
--
-- Cross-domain API (ARCHITECTURE section 4):
--   getLoadout(player) -> (classId, companionId)
--   isUnlocked(player, kind: "Class"|"Weapon"|"Grimoire"|"Item"|"Companion", id) -> boolean
--   getMetaBonuses(player) -> { weaponSlots, grimoireSlots, banish, skip, reroll }   (run totals)
--   recordStat(player, key, amount)   (keys: Config.Quests.ExternalKeys; others ignored + warned once)
--   grantRunRewards(player, summary) -> RunSummary   (fills silverEarned / questsProgressed)
-- Extra functions below (isWorldUnlocked, getBond, getWeeklyChallenge, hasSelectedLoadout,
-- LoadoutSelected) are listed as contract requests in the data report.
--
-- Every profile change goes through DataService.mutate (synchronous, no yields inside).

local AnalyticsService = game:GetService("AnalyticsService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Progression = require(Config:WaitForChild("Progression"))
local Quests = require(Config:WaitForChild("Quests"))
local Cosmetics = require(Config:WaitForChild("Cosmetics"))
local Products = require(Config:WaitForChild("Products"))
local Net = require(Shared:WaitForChild("Net"))
local Registry = require(Shared:WaitForChild("Registry"))
local Signal = require(Shared:WaitForChild("Signal"))
local Types = require(Shared:WaitForChild("Types"))
local Bus = require(script.Parent.Parent:WaitForChild("Bus"))

type Data = { [string]: any }
type QuestDef = Quests.QuestDef

local ProgressionService = {}

-- Fired as (player, classId, companionId) when a loadout is accepted.
ProgressionService.LoadoutSelected = Signal.new()

---------------------------------------------------------------------------------------------------
-- Optional configs owned by other domains (read with pcall, never required at the top level)
---------------------------------------------------------------------------------------------------
local optionalCache: { [string]: any } = {}
local function optionalConfig(name: string): any?
	local cached = optionalCache[name]
	if cached ~= nil then
		return if cached == false then nil else cached
	end
	local module = Config:FindFirstChild(name)
	local ok, result = false, nil
	if module and module:IsA("ModuleScript") then
		ok, result = pcall(require, module)
	end
	optionalCache[name] = if ok and type(result) == "table" then result else false
	return if ok and type(result) == "table" then result else nil
end

local warnedKeys: { [string]: boolean } = {}
local function warnOnce(tag: string, message: string)
	if not warnedKeys[tag] then
		warnedKeys[tag] = true
		warn(`[ProgressionService] {message}`)
	end
end

local function dataService(): any
	return Registry.get("DataService")
end

local function isFiniteNumber(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function isPlayer(v: any): boolean
	return typeof(v) == "Instance" and (v :: Instance):IsA("Player")
end

local function validId(v: any, maxLen: number): boolean
	return type(v) == "string" and #v > 0 and #v <= maxLen and string.match(v, "^[%w_:]+$") ~= nil
end

local CLASS_SET: { [string]: boolean } = {}
for _, c in Progression.Classes do
	CLASS_SET[c] = true
end
local LINE_SET: { [string]: boolean } = {}
for _, l in Progression.Lines do
	LINE_SET[l] = true
end
local WORLD_SET: { [string]: boolean } = {}
for _, w in Progression.Worlds do
	WORLD_SET[w] = true
end

---------------------------------------------------------------------------------------------------
-- Analytics (server only, all in pcall, low-cardinality fields, batched custom events)
---------------------------------------------------------------------------------------------------
local FIELD_KEYS = { "CustomField01", "CustomField02", "CustomField03" }

local function toFields(values: { string }?): { [string]: string }?
	if not values then
		return nil
	end
	local out: { [string]: string } = {}
	for i = 1, math.min(#values, 3) do
		local ok, keyName = pcall(function()
			return (Enum.AnalyticsCustomFieldKeys :: any)[FIELD_KEYS[i]].Name
		end)
		out[if ok then keyName else FIELD_KEYS[i]] = tostring(values[i])
	end
	return out
end

local function safe(fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warnOnce("analytics:" .. tostring(err), `analytics error: {err}`)
	end
end

local pendingEvents: { [Player]: { [string]: { name: string, value: number, fields: { string }? } } } = {}

-- Batched custom event (flushed every 60 s and on leave).
function ProgressionService.logCustom(player: Player, eventName: string, amount: number?, fields: { string }?)
	local byKey = pendingEvents[player]
	if not byKey then
		byKey = {}
		pendingEvents[player] = byKey
	end
	local key = eventName .. "|" .. table.concat(fields or {}, "|")
	local entry = byKey[key]
	if entry then
		entry.value += amount or 1
	else
		byKey[key] = { name = eventName, value = amount or 1, fields = fields }
	end
end

local function flushEvents(player: Player)
	local byKey = pendingEvents[player]
	pendingEvents[player] = nil
	if not byKey then
		return
	end
	for _, e in byKey do
		safe(function()
			AnalyticsService:LogCustomEvent(player, e.name, e.value, toFields(e.fields))
		end)
	end
end

local function logEconomy(player: Player, source: boolean, currency: string, amount: number, balance: number, tx: string, sku: string)
	if amount <= 0 then
		return
	end
	safe(function()
		local flow = if source then Enum.AnalyticsEconomyFlowType.Source else Enum.AnalyticsEconomyFlowType.Sink
		local txName = (Enum.AnalyticsEconomyTransactionType :: any)[tx].Name
		AnalyticsService:LogEconomyEvent(player, flow, currency, amount, balance, txName, sku)
	end)
end

local onboardingMax: { [Player]: number } = {}
local function onboarding(player: Player, step: number, stepName: string)
	local data = dataService().peek(player)
	if not data or (tonumber(data.sessions) or 0) > 1 then
		return -- one-time funnel: first session only
	end
	if step <= (onboardingMax[player] or 0) then
		return
	end
	onboardingMax[player] = step
	safe(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, stepName)
	end)
end

---------------------------------------------------------------------------------------------------
-- Levels
---------------------------------------------------------------------------------------------------
local function levelFromXp(xp: number, base: number, step: number, maxLevel: number): number
	local level = 1
	local remaining = xp
	while level < maxLevel do
		local need = base + step * (level - 1)
		if remaining < need then
			break
		end
		remaining -= need
		level += 1
	end
	return level
end

local function bondLevelOf(data: Data?, line: string): number
	if not data or type(data.bond) ~= "table" then
		return 1
	end
	return math.clamp(tonumber(data.bond[line]) or 1, 1, Progression.Bond.MaxLevel)
end

---------------------------------------------------------------------------------------------------
-- Unlocks
---------------------------------------------------------------------------------------------------
local function questDone(data: Data?, questId: string): boolean
	return data ~= nil and type(data.questsDone) == "table" and data.questsDone[questId] ~= nil
end

local function stored(data: Data?, kind: string, id: string): boolean
	if not data or type(data.unlocks) ~= "table" then
		return false
	end
	local bucket = data.unlocks[kind]
	return type(bucket) == "table" and bucket[id] == true
end

local function itemSilverPrice(id: string): number?
	local items = optionalConfig("Items")
	if not items then
		return 0 -- no item config: never block the game
	end
	local defs = items.Defs
	local def = if type(defs) == "table" then defs[id] else nil
	if type(def) ~= "table" then
		return nil -- unknown item
	end
	if def.unlock == nil or def.unlock == "Free" then
		local price = Progression.ItemSilverByRarity[def.rarity]
		return if type(price) == "number" then price else 0
	end
	return if type(def.unlock) == "number" then def.unlock else nil
end

local function unlockedIn(data: Data?, kind: string, id: string): boolean
	if kind == "Item" then
		local price = itemSilverPrice(id)
		if price == nil then
			warnOnce("item:" .. id, `isUnlocked: unknown item "{id}"`)
			return false
		end
		return price <= 0 or stored(data, "Item", id)
	end
	if kind == "Companion" then
		-- v2 : la collection capturée (A12-01), plus de règle de déblocage.
		local c = data and data.companions
		return type(c) == "table" and type(c.owned) == "table" and c.owned[id] ~= nil
	end
	local rules = Progression.Unlocks[kind]
	if not rules then
		return false
	end
	local rule = rules[id]
	if not rule then
		return false
	end
	if rule.free then
		return true
	end
	if rule.quest and questDone(data, rule.quest) then
		return true
	end
	if rule.classId and unlockedIn(data, "Class", rule.classId) then
		return true
	end
	return stored(data, kind, id)
end

function ProgressionService.isUnlocked(player: Player, kind: string, id: string): boolean
	if type(kind) ~= "string" or type(id) ~= "string" then
		return false
	end
	local data = if isPlayer(player) then dataService().peek(player) else nil
	return unlockedIn(data, kind, id)
end

local function worldUnlockedIn(data: Data?, worldId: string, tier: number): boolean
	local rule = Progression.WorldUnlock[worldId]
	if not rule or tier < 1 or tier > Progression.MaxTier or tier ~= math.floor(tier) then
		return false
	end
	local stats = if data and type(data.stats) == "table" then data.stats else {}
	if not rule.free then
		if not (rule.stat and (tonumber(stats[rule.stat]) or 0) >= (rule.goal or 1)) then
			return false
		end
	end
	if tier > 1 then
		return (tonumber(stats[`Win_{worldId}_T{tier - 1}`]) or 0) >= 1
	end
	return true
end

-- Contract request: RunManager / MatchService use it to validate world + tier.
function ProgressionService.isWorldUnlocked(player: Player, worldId: string, tier: number): boolean
	if type(worldId) ~= "string" or not isFiniteNumber(tier) then
		return false
	end
	local data = if isPlayer(player) then dataService().peek(player) else nil
	return worldUnlockedIn(data, worldId, tier)
end

---------------------------------------------------------------------------------------------------
-- Cosmetics ownership
---------------------------------------------------------------------------------------------------
local function ownsPass(player: Player, passKey: string): boolean
	local monetization = Registry.find("MonetizationService")
	if monetization and type(monetization.ownsPass) == "function" then
		local ok, owns = pcall(monetization.ownsPass, player, passKey)
		return ok and owns == true
	end
	return false
end

local function ownsCosmetic(player: Player, data: Data, id: string): boolean
	local def = Cosmetics[id]
	if not def then
		return false
	end
	if def.source == "Free" then
		return true
	end
	if def.source == "Pass" then
		return def.pass ~= nil and ownsPass(player, def.pass)
	end
	if def.source == "Season" then
		-- Dérivé (jamais stocké) : palier atteint, et pass de la saison pour la piste premium.
		local season = def.season and Products.Seasons.List[def.season]
		if not season or not def.tier then
			return false
		end
		local xp = type(data.seasons) == "table" and tonumber(data.seasons[season.id]) or 0
		if (xp or 0) < def.tier * season.xpPerTier then
			return false
		end
		return def.track == "Free" or ownsPass(player, season.pass)
	end
	return type(data.cosmetics) == "table" and data.cosmetics[id] == true
end

-- XP de saison d'une run (A12-04) : gagnée en jouant, jamais achetée.
local function seasonXpFor(kills: number, worldsCleared: number): number
	local x = Products.Seasons.Xp
	return math.min(x.Cap, x.Base + math.floor(kills / x.KoPerXp) + x.PerWorld * worldsCleared)
end

local function grantCosmetic(data: Data, id: string)
	if Cosmetics[id] then
		data.cosmetics[id] = true
	else
		warnOnce("cos:" .. id, `reward cosmetic "{id}" missing from Config.Cosmetics`)
	end
end

---------------------------------------------------------------------------------------------------
-- Stats and quests (synchronous; called inside DataService.mutate)
---------------------------------------------------------------------------------------------------
local function grantReward(data: Data, reward: Quests.Reward)
	if reward.tokens and reward.tokens > 0 then
		data.questTokens += reward.tokens
	end
	if reward.silver and reward.silver > 0 then
		data.silver += reward.silver
		data.silverEarnedTotal += reward.silver
	end
	if reward.egg and reward.egg > 0 then
		data.eggs += reward.egg
	end
	if reward.cosmetic then
		grantCosmetic(data, reward.cosmetic)
	end
end

local function rollWeek(data: Data)
	local week = Progression.weekIndex(os.time())
	if data.boards.week ~= week then
		data.boards.week = week
		data.boards.kills = 0
		data.boards.bestFinalWave = 0
	end
end

-- Adds (or records the max of) one stat, then completes any quest that reached its goal.
local function applyStat(data: Data, key: string, amount: number, done: { QuestDef })
	if #key > 48 or not isFiniteNumber(amount) or amount <= 0 then
		return
	end
	local stats = data.stats
	local current = tonumber(stats[key]) or 0
	if Quests.isMaxKey(key) then
		if amount <= current then
			return
		end
		stats[key] = amount
	else
		stats[key] = math.min(current + amount, 1e12)
	end
	local list = Quests.ByStat[key]
	if not list then
		return
	end
	local value = stats[key]
	for _, def in list do
		if data.questsDone[def.id] == nil and value >= def.goal then
			data.questsDone[def.id] = os.time()
			grantReward(data, def.reward)
			table.insert(done, def)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Profile replication (debounced)
---------------------------------------------------------------------------------------------------
local dirty: { [Player]: boolean } = {}
local function markDirty(player: Player)
	dirty[player] = true
end
ProgressionService.markDirty = markDirty

local function metaBonusesOf(data: Data?): { weaponSlots: number, grimoireSlots: number, banish: number, skip: number, reroll: number }
	local base = Progression.MetaBase
	local shop = if data and type(data.shop) == "table" then data.shop else {}
	local function lvl(field: string): number
		return math.max(0, math.floor(tonumber(shop[field]) or 0))
	end
	return {
		weaponSlots = base.weaponSlots,
		grimoireSlots = base.grimoireSlots + lvl("grimoireSlots"),
		banish = base.banish + lvl("banish"),
		skip = base.skip + lvl("skip"),
		reroll = base.reroll + lvl("reroll"),
	}
end

-- v2 (A12-01) : un compagnon se gagne uniquement par capture (01-decisions-v2 §5). Un œuf gagné
-- (quêtes v1, défi hebdo) n'éclôt plus en créature : il donne les jetons de repli (Eggs.DuplicateTokens).
local function eggCandidates(_data: Data?): { string }
	return {}
end

function ProgressionService.getWeeklyChallenge(): { week: number, classId: string, companionId: string, modifier: string, worldId: string, tier: number, endsAt: number }
	local now = os.time()
	local week = Progression.weekIndex(now)
	local rng = Random.new(week * 7919 + 17)
	local classes = Progression.Classes
	local mods = Progression.Weekly.Modifiers
	return {
		week = week,
		classId = classes[rng:NextInteger(1, #classes)],
		companionId = "", -- v2 : compagnon libre (collection capturée, chacun la sienne)
		modifier = mods[rng:NextInteger(1, #mods)],
		worldId = Progression.Weekly.WorldId,
		tier = Progression.Weekly.Tier,
		endsAt = Progression.weekEndsAt(now),
	}
end

local function buildView(player: Player, data: Data): { [string]: any }
	local unlocks: { [string]: { [string]: boolean } } = {}
	for kind, rules in Progression.Unlocks do
		local bucket: { [string]: boolean } = {}
		for id in rules do
			if unlockedIn(data, kind, id) then
				bucket[id] = true
			end
		end
		unlocks[kind] = bucket
	end
	local itemBucket: { [string]: boolean } = {}
	local items = optionalConfig("Items")
	if items and type(items.Defs) == "table" then
		for id in items.Defs do
			if type(id) == "string" and unlockedIn(data, "Item", id) then
				itemBucket[id] = true
			end
		end
	end
	unlocks.Item = itemBucket
	local companionBucket: { [string]: boolean } = {}
	for id in data.companions.owned do
		companionBucket[id] = true
	end
	unlocks.Companion = companionBucket -- contrat v1 : vue des espèces possédées

	local quests = table.create(#Quests.List)
	for i, def in Quests.List do
		local progress = tonumber(data.stats[def.stat]) or 0
		quests[i] = {
			id = def.id,
			progress = math.min(progress, def.goal),
			goal = def.goal,
			completed = data.questsDone[def.id] ~= nil,
		}
	end

	local owned: { [string]: boolean } = {}
	for id in Cosmetics do
		if ownsCosmetic(player, data, id) then
			owned[id] = true
		end
	end

	local worlds: { [string]: number } = {}
	for _, w in Progression.Worlds do
		local maxTier = 0
		for tier = 1, Progression.MaxTier do
			if worldUnlockedIn(data, w, tier) then
				maxTier = tier
			end
		end
		worlds[w] = maxTier
	end

	local candidates = eggCandidates(data)
	local eggOdds: { [string]: number } = {}
	for _, l in candidates do
		eggOdds[l] = 1 / #candidates
	end

	local passes: { [string]: boolean } = {}
	for key in Products.Passes do
		if ownsPass(player, key) then
			passes[key] = true
		end
	end

	-- Pass saisonnier : saison en cours (ou nil), XP, palier, piste premium possédée.
	local seasonView = nil
	local active = Products.activeSeason(os.time())
	if active then
		local xp = tonumber(data.seasons[active.id]) or 0
		seasonView = {
			id = active.id,
			xp = xp,
			tier = math.min(active.tiers, math.floor(xp / active.xpPerTier)),
			tiers = active.tiers,
			xpPerTier = active.xpPerTier,
			premium = passes[active.pass] == true,
			endsAt = active.endsAt,
		}
	end

	local challenge = ProgressionService.getWeeklyChallenge()
	local weeklyDone = data.weekly.week == challenge.week and data.weekly.done == true

	-- Record perso de KO en une run (A12-02). Jamais l'état de quarantaine : le tricheur ne voit rien.
	local wb, best = data.boards.weekBest, data.boards.best
	local koRecord = {
		weekly = if type(wb) == "table" and wb.week == challenge.week then tonumber(wb.ko) or 0 else 0,
		allTime = if type(best) == "table" then tonumber(best.ko) or 0 else 0,
		weekEndsAt = challenge.endsAt,
	}

	return {
		silver = data.silver,
		questTokens = data.questTokens,
		unlocks = unlocks,
		quests = quests,
		mastery = table.clone(data.mastery),
		bond = table.clone(data.bond),
		cosmetics = owned,
		equipped = table.clone(data.equipped),
		settings = table.clone(data.settings),
		loadout = table.clone(data.loadout),
		-- extra fields (additive to the contract payload)
		eggs = data.eggs,
		eggOdds = eggOdds,
		shop = table.clone(data.shop),
		metaBonuses = metaBonusesOf(data),
		worlds = worlds,
		weekly = { challenge = challenge, done = weeklyDone },
		passes = passes,
		vip = passes.VIP == true,
		companionStartTech = table.clone(data.companionStartTech),
		-- Collection v2 (A09-07) : owned[espèce] = { n, at }, equipped = { espèce1, espèce2? } (sans keys).
		companions = {
			owned = (function()
				local owned = {}
				for id, e in data.companions.owned do
					if type(e) == "table" then
						owned[id] = { n = tonumber(e.n) or 1, at = tonumber(e.at) or 0 }
					end
				end
				return owned
			end)(),
			equipped = ProgressionService.getCompanionLoadout(player),
		},
		koRecord = koRecord,
		season = seasonView,
	}
end

local function sendProfile(player: Player)
	local data = dataService().peek(player)
	if not data or not dataService().canMutate(player) then
		return
	end
	local ok, view = pcall(buildView, player, data)
	if ok then
		Net.event("Profile"):FireClient(player, view)
	else
		warn(`[ProgressionService] profile view failed: {view}`)
	end
end

local function notice(player: Player, kind: string, text: Types.LocalizedText, questId: string?)
	if player.Parent then
		Net.event("DataNotice"):FireClient(player, { kind = kind, text = text, questId = questId })
	end
end

-- After a mutation that completed quests: notices, analytics, save soon.
local function afterQuests(player: Player, done: { QuestDef })
	if #done == 0 then
		return
	end
	local data = dataService().peek(player)
	for _, def in done do
		notice(player, "QuestDone", def.name, def.id)
		ProgressionService.logCustom(player, "QuestCompleted", 1, { def.category })
		if def.reward.unlock then
			ProgressionService.logCustom(player, "Unlock", 1, { def.reward.unlock.kind })
		end
		if data then
			if def.reward.tokens then
				logEconomy(player, true, "QuestTokens", def.reward.tokens, data.questTokens, "Gameplay", def.category)
			end
			if def.reward.silver then
				logEconomy(player, true, "Silver", def.reward.silver, data.silver, "Gameplay", "Quest")
			end
		end
	end
	dataService().saveSoon(player)
end

-- Runs fn inside DataService.mutate, then handles quest completions and replication.
-- silent: only resend the Profile if a quest completed (high-frequency counters).
local function withProfile(player: Player, fn: (data: Data, done: { QuestDef }) -> (), silent: boolean?): boolean
	local done: { QuestDef } = {}
	local ok = dataService().mutate(player, function(data)
		fn(data, done)
	end)
	if ok then
		afterQuests(player, done)
		if not silent or #done > 0 then
			markDirty(player)
		end
	end
	return ok
end

---------------------------------------------------------------------------------------------------
-- Stat recording
---------------------------------------------------------------------------------------------------
-- Buffered high-frequency counters (kills, damage taken), flushed every second and before saves.
local pending: { [Player]: { [string]: number } } = {}

local function bufferStat(player: Player, key: string, amount: number)
	local bucket = pending[player]
	if not bucket then
		bucket = {}
		pending[player] = bucket
	end
	bucket[key] = (bucket[key] or 0) + amount
end

local function flushPending(player: Player)
	local bucket = pending[player]
	if not bucket then
		return
	end
	pending[player] = nil
	withProfile(player, function(data, done)
		rollWeek(data)
		for key, amount in bucket do
			applyStat(data, key, amount, done)
			if key == "Kills" then
				data.boards.kills += amount
			end
		end
	end, true)
end

function ProgressionService.recordStat(player: Player, key: string, amount: number)
	if not isPlayer(player) or type(key) ~= "string" then
		return
	end
	if not isFiniteNumber(amount) or amount <= 0 then
		return
	end
	if Quests.isAutoKey(key) then
		warnOnce("auto:" .. key, `recordStat("{key}") ignored: recorded automatically by the data domain`)
		return
	end
	if not Quests.ExternalKeys[key] then
		warnOnce("unknown:" .. key, `recordStat: unknown key "{key}" ignored (see Config.Quests.ExternalKeys)`)
		return
	end
	bufferStat(player, key, math.min(amount, Quests.MaxPerCall))
end

---------------------------------------------------------------------------------------------------
-- Loadout et collection de compagnons (A12-01, dossier 40 §3 et §4, regles-v2 §3)
---------------------------------------------------------------------------------------------------
local selected: { [Player]: boolean } = {}

-- Id de classe canonique v2. Accepte les alias v1 encore envoyés par l'UI (Cornu -> Knight, résolus
-- par Config.Classes) pendant la transition.
local function canonicalClass(classId: any): string?
	if not validId(classId, 32) then
		return nil
	end
	if CLASS_SET[classId] then
		return classId
	end
	local classes = optionalConfig("Classes")
	local def = classes and classes[classId]
	if type(def) == "table" and type(def.id) == "string" and CLASS_SET[def.id] then
		return def.id
	end
	return nil
end

-- Espèce capturable (CompanionService.isSpecies) ; sans CompanionService, un id bien formé.
local function validSpecies(id: any): boolean
	if not validId(id, 48) then
		return false
	end
	local companions = Registry.find("CompanionService")
	if companions and type(companions.isSpecies) == "function" then
		local ok, yes = pcall(companions.isSpecies, id)
		return ok and yes == true
	end
	return true
end

local function slotsFor(classId: string): number
	local companions = Registry.find("CompanionService")
	if companions and type(companions.slotsFor) == "function" then
		local ok, n = pcall(companions.slotsFor, classId)
		if ok and isFiniteNumber(n) then
			return math.clamp(math.floor(n), 1, 2)
		end
	end
	return if classId == "Tamer" then 2 else 1
end

local function ownsSpecies(data: Data?, id: string): boolean
	local c = data and data.companions
	return type(c) == "table" and type(c.owned) == "table" and c.owned[id] ~= nil
end

function ProgressionService.hasCompanion(player: Player, speciesId: string): boolean
	if not isPlayer(player) or type(speciesId) ~= "string" then
		return false
	end
	return ownsSpecies(dataService().peek(player), speciesId)
end

-- Espèces équipées, déjà validées : possédées, capturables, sans doublon, au plus slotsFor(classe).
function ProgressionService.getCompanionLoadout(player: Player): { string }
	local out: { string } = {}
	local data = if isPlayer(player) then dataService().peek(player) else nil
	local c = data and data.companions
	if type(c) ~= "table" or type(c.equipped) ~= "table" then
		return out
	end
	local classId = canonicalClass(data and data.loadout and data.loadout.classId) or Progression.DefaultLoadout.classId
	local max = slotsFor(classId)
	for i = 1, 2 do
		local id = c.equipped[i]
		if #out < max and type(id) == "string" and ownsSpecies(data, id) and validSpecies(id) and not table.find(out, id) then
			table.insert(out, id)
		end
	end
	return out
end

-- Contrat : (classId, companionId). companionId = 1re espèce équipée, "" si aucune.
function ProgressionService.getLoadout(player: Player): (string, string)
	local def = Progression.DefaultLoadout
	local data = if isPlayer(player) then dataService().peek(player) else nil
	if not data or type(data.loadout) ~= "table" then
		return def.classId, ""
	end
	local classId = canonicalClass(data.loadout.classId)
	if not classId or not unlockedIn(data, "Class", classId) then
		classId = def.classId
	end
	local list = ProgressionService.getCompanionLoadout(player)
	return classId :: string, list[1] or ""
end

-- Capture accordée par CompanionService (regles-v2 §3.1.7) : un seul mutate, clé d'idempotence
-- dans le profil. Ne cède jamais. Profil non modifiable -> "Unavailable" (refusée, jamais différée).
function ProgressionService.grantCapture(player: Player, speciesId: any, captureKey: any): (string, boolean)
	if not isPlayer(player) or not validSpecies(speciesId) or type(captureKey) ~= "string" or #captureKey == 0 or #captureKey > 120 then
		return "Unavailable", false
	end
	local result, isNew = "Unavailable", false
	local ok = withProfile(player, function(d, done)
		local c = d.companions
		if c.keys[captureKey] then
			result = "AlreadyGranted"
			return
		end
		local now = os.time()
		c.keys[captureKey] = now
		local entry = c.owned[speciesId]
		if type(entry) == "table" then
			entry.n = (tonumber(entry.n) or 0) + 1
		else
			c.owned[speciesId] = { n = 1, at = now }
			isNew = true
		end
		-- Garder les MaxKeys clés les plus récentes (les vieilles runs ne reviennent jamais).
		local count, oldestKey, oldestAt = 0, nil :: string?, math.huge
		for k, t in c.keys do
			count += 1
			if type(t) == "number" and t < oldestAt then
				oldestKey, oldestAt = k, t
			end
		end
		if count > Progression.Collection.MaxKeys and oldestKey then
			c.keys[oldestKey] = nil
		end
		-- Premier compagnon : équipé d'office (collection vide à la première run).
		if #c.equipped == 0 then
			c.equipped[1] = speciesId
		end
		result = "Granted"
	end)
	if not ok then
		return "Unavailable", false
	end
	if result == "Granted" then
		dataService().saveSoon(player)
	end
	return result, isNew
end

function ProgressionService.hasSelectedLoadout(player: Player): boolean
	return selected[player] == true
end

local function loadoutChangeAllowed(): boolean
	local run = Registry.find("RunManager")
	if not run or type(run.getPhase) ~= "function" then
		return true
	end
	local ok, phase = pcall(run.getPhase)
	return not ok or phase == "Loadout" or phase == "Ended"
end

-- Choix validé (remote et arrivée MatchService). companionId / companionId2 : "" ou nil = aucun.
-- Chaque espèce doit être possédée ; la 2e seulement si slotsFor(classe) == 2 ; pas de doublon.
function ProgressionService.setLoadout(player: Player, classId: any, companionId: any, companionId2: any): boolean
	local cls = canonicalClass(classId)
	if not cls then
		return false
	end
	local data = dataService().peek(player)
	if not data or not unlockedIn(data, "Class", cls) then
		return false
	end
	local list: { string } = {}
	for _, id in { companionId, companionId2 } do
		if id == nil or id == "" then
			continue
		end
		if not validSpecies(id) or not ownsSpecies(data, id) or table.find(list, id) then
			return false
		end
		table.insert(list, id)
	end
	if #list > slotsFor(cls) then
		return false
	end
	local ok = withProfile(player, function(d)
		d.loadout.classId = cls
		d.loadout.companionId = list[1] or ""
		d.companions.equipped = list
	end)
	if ok then
		selected[player] = true
		ProgressionService.logCustom(player, "ClassPicked", 1, { cls })
		if list[1] then
			ProgressionService.logCustom(player, "CompanionPicked", 1, { "Species" })
		end
		onboarding(player, 3, "LoadoutSelected")
		ProgressionService.LoadoutSelected:fire(player, cls, list[1] or "")
	end
	return ok
end

---------------------------------------------------------------------------------------------------
-- Meta API
---------------------------------------------------------------------------------------------------
function ProgressionService.getMetaBonuses(player: Player): { weaponSlots: number, grimoireSlots: number, banish: number, skip: number, reroll: number }
	local data = if isPlayer(player) then dataService().peek(player) else nil
	return metaBonusesOf(data)
end

-- Contract request: (bond level 1..30, companion stat bonus 0..0.10).
function ProgressionService.getBond(player: Player, line: string): (number, number)
	local data = if isPlayer(player) then dataService().peek(player) else nil
	local level = bondLevelOf(data, line)
	local cfg = Progression.Bond
	local bonus = math.min(cfg.StatBonusMax, math.floor(level / cfg.StatBonusEvery) * cfg.StatBonusStep)
	return level, bonus
end

---------------------------------------------------------------------------------------------------
-- Mastery and bond progression (inside mutate)
---------------------------------------------------------------------------------------------------
local function addMastery(data: Data, classId: string, xp: number)
	local cfg = Progression.Mastery
	local before = math.clamp(tonumber(data.mastery[classId]) or 1, 1, cfg.MaxLevel)
	data.masteryXp[classId] = (tonumber(data.masteryXp[classId]) or 0) + xp
	local after = levelFromXp(data.masteryXp[classId], cfg.XpBase, cfg.XpStep, cfg.MaxLevel)
	data.mastery[classId] = after
	for lvl = before + 1, after do
		local template = cfg.Rewards[lvl]
		if template then
			grantCosmetic(data, (string.gsub(template, "<C>", classId)))
		end
	end
end

local function addBond(data: Data, line: string, xp: number, done: { QuestDef })
	local cfg = Progression.Bond
	local before = math.clamp(tonumber(data.bond[line]) or 1, 1, cfg.MaxLevel)
	data.bondXp[line] = (tonumber(data.bondXp[line]) or 0) + xp
	local after = levelFromXp(data.bondXp[line], cfg.XpBase, cfg.XpStep, cfg.MaxLevel)
	data.bond[line] = after
	for lvl = before + 1, after do
		local template = cfg.Rewards[lvl]
		if template then
			grantCosmetic(data, (string.gsub(template, "<L>", line)))
		end
	end
	if after >= cfg.EggAtLevel and not data.bondEggs[line] then
		data.bondEggs[line] = true
		data.eggs += 1
	end
	applyStat(data, `Bond_{line}`, after, done)
end

---------------------------------------------------------------------------------------------------
-- Run tracking (Bus) and rewards
---------------------------------------------------------------------------------------------------
type RunInfo = {
	runId: number,
	runKey: string, -- JobId:runId, clé d'idempotence du classement (boards.lastRunKey)
	worldId: string,
	tier: number,
	partySize: number,
	startedAt: number,
	downed: boolean,
	bossHit: boolean,
	statsBefore: { [string]: number },
	-- Classement (A12-02)
	ko: number, -- dernier total de KO lu sur Bus.KOScored (source : StatsService)
	koCounted: number, -- KO faits dans la fenêtre de score (ScoreWindowOvertimeSeconds)
	lastDamagedAt: number, -- os.clock du dernier dégât subi (ou de la dernière inactivité)
	noDamage: boolean, -- signal « aucun dégât en Overtime » levé
	scored: boolean, -- score déjà soumis pour cette run
}
local runCounter = 0
local runInfo: { [Player]: RunInfo } = {}
local rewardedRun: { [Player]: number } = {}
local sessionRuns: { [Player]: number } = {}
local joinedAt: { [Player]: number } = {}
local firstKill: { [Player]: boolean } = {}

local function runManager(): any?
	return Registry.find("RunManager")
end

-- Overtime cumulé de la run (une run par serveur) : Bus.FinalWaveStarted ouvre un segment,
-- Bus.StageStarted (monde suivant) le ferme. Sert aux signaux du classement, pas à l'affichage.
local overtimeSince: number? = nil
local overtimeAccum = 0

local function overtimeSeconds(): number
	local since = overtimeSince
	return overtimeAccum + (if since then os.clock() - since else 0)
end

local function currentPhase(): string?
	local run = runManager()
	if run and type(run.getPhase) == "function" then
		local ok, phase = pcall(run.getPhase)
		if ok and type(phase) == "string" then
			return phase
		end
	end
	return nil
end

local function onRunStarted(players: { Player }, worldId: string, tier: number)
	if type(players) ~= "table" then
		return
	end
	runCounter += 1
	overtimeSince = nil
	overtimeAccum = 0
	local size = #players
	for _, p in players do
		if not isPlayer(p) then
			continue
		end
		local data = dataService().peek(p)
		local before: { [string]: number } = {}
		if data then
			for k, v in data.stats do
				before[k] = v
			end
		end
		runInfo[p] = {
			runId = runCounter,
			runKey = `{game.JobId}:{runCounter}`,
			worldId = if type(worldId) == "string" then worldId else "?",
			tier = if isFiniteNumber(tier) then tier else 1,
			partySize = size,
			startedAt = os.clock(),
			downed = false,
			bossHit = false,
			statsBefore = before,
			ko = 0,
			koCounted = 0,
			lastDamagedAt = os.clock(),
			noDamage = false,
			scored = false,
		}
		if size >= 2 then
			withProfile(p, function(d, done)
				applyStat(d, "CoopRuns", 1, done)
			end)
		end
		sessionRuns[p] = (sessionRuns[p] or 0) + 1
		onboarding(p, 4, "RunStarted")
		if sessionRuns[p] == 2 then
			onboarding(p, 7, "SecondRun")
		end
		ProgressionService.logCustom(p, "RunStart", 1, { tostring(worldId), `T{tier}`, tostring(math.clamp(size, 1, 4)) })
	end
end

local function onEnemyKilled(_id: number, kind: number, _x: number, _z: number, killer: Player?, isElite: boolean)
	if not killer or not isPlayer(killer) then
		return
	end
	bufferStat(killer, "Kills", 1)
	if isElite then
		bufferStat(killer, "KillsElite", 1)
	end
	local enemies = optionalConfig("Enemies")
	local def = enemies and enemies[kind]
	if type(def) == "table" and type(def.family) == "string" and #def.family <= 16 then
		bufferStat(killer, `KillsFamily_{def.family}`, 1)
	end
	if not firstKill[killer] then
		firstKill[killer] = true
		onboarding(killer, 5, "FirstKill")
	end
end

local function onPlayerDamaged(player: Player, amount: number)
	if not isPlayer(player) or not isFiniteNumber(amount) or amount <= 0 then
		return
	end
	bufferStat(player, "DamageTaken", amount)
	local hit = runInfo[player]
	if hit then
		hit.lastDamagedAt = os.clock()
	end
	if currentPhase() == "Boss" then
		local info = runInfo[player]
		if info then
			info.bossHit = true
		end
	end
end

local function onBossDefeated(_bossId: string, _stage: number)
	local players: { Player } = {}
	local worldId: string? = nil
	local run = runManager()
	if run then
		local ok, list = pcall(run.getRunPlayers)
		if ok and type(list) == "table" then
			players = list
		end
		local okInfo, info = pcall(run.getRunInfo)
		if okInfo and type(info) == "table" and type(info.worldId) == "string" then
			worldId = info.worldId
		end
	end
	if #players == 0 then
		for p in runInfo do
			table.insert(players, p)
		end
	end
	local stats = Registry.find("StatsService")
	for _, p in players do
		if not isPlayer(p) then
			continue
		end
		local info = runInfo[p]
		local w = worldId or (info and info.worldId)
		local fullBuild = false
		if stats then
			local ok, build = pcall(stats.getBuild, p)
			if ok and type(build) == "table" and type(build.weapons) == "table" and type(build.grimoires) == "table" then
				fullBuild = #build.weapons >= 4 and #build.grimoires >= 4
			end
		end
		local active = true
		if run and type(run.isActive) == "function" then
			local ok, a = pcall(run.isActive, p)
			active = ok and a == true
		end
		local noDamage = info ~= nil and not info.bossHit and active
		withProfile(p, function(d, done)
			applyStat(d, "BossesDefeated", 1, done)
			applyStat(d, "StagesCleared", 1, done)
			if w and WORLD_SET[w] then
				applyStat(d, `BossesDefeated_{w}`, 1, done)
			end
			if fullBuild then
				applyStat(d, "FullBuildStageClears", 1, done)
			end
			if noDamage then
				applyStat(d, "BossNoDamage", 1, done)
			end
		end)
		if info then
			info.bossHit = false
		end
	end
end

local function onStageStarted()
	for _, info in runInfo do
		info.bossHit = false
	end
	local since = overtimeSince
	if since then
		overtimeAccum += os.clock() - since
		overtimeSince = nil
	end
end

local function onFinalWaveStarted()
	if not overtimeSince then
		overtimeSince = os.clock()
	end
end

-- KO compté par StatsService (A04-03) : on ne recalcule rien, on garde le dernier total.
local function onKOScored(player: Player, runKills: number)
	local info = runInfo[player]
	if not info or not isFiniteNumber(runKills) then
		return
	end
	info.ko = runKills
	local window = Progression.Leaderboards.ScoreWindowOvertimeSeconds
	if window <= 0 or overtimeSeconds() <= window then
		info.koCounted = runKills
	end
end

local function onPlayerDowned(player: Player)
	local info = runInfo[player]
	if info then
		info.downed = true
	end
end

local function onPlayerRevived(_player: Player, rescuer: Player)
	if isPlayer(rescuer) then
		withProfile(rescuer, function(d, done)
			applyStat(d, "Revives", 1, done)
		end)
	end
end

local function onShrineCompleted(players: { Player }, _kind: string)
	if type(players) ~= "table" then
		return
	end
	local together = #players >= 2
	for _, p in players do
		if isPlayer(p) then
			withProfile(p, function(d, done)
				applyStat(d, "ShrinesCompleted", 1, done)
				if together then
					applyStat(d, "ShrinesCoop", 1, done)
				end
			end)
		end
	end
end

local function onCompanionEvolved(player: Player, stage: number)
	if not isPlayer(player) or stage ~= 3 then
		return
	end
	local _, line = ProgressionService.getLoadout(player)
	local run = runManager()
	if run and type(run.getLoadout) == "function" then
		local ok, _c, l = pcall(run.getLoadout, player)
		if ok and type(l) == "string" and LINE_SET[l] then
			line = l
		end
	end
	withProfile(player, function(d, done)
		applyStat(d, `Companion_{line}_Stage3`, 1, done)
	end)
end

-- Défini dans la section Leaderboards (plus bas).
local scoreRun: (player: Player, info: RunInfo, kills: number, ending: string) -> ()

local function num(v: any, lo: number, hi: number): number
	if not isFiniteNumber(v) then
		return lo
	end
	return math.clamp(v, lo, hi)
end

-- Fills silverEarned / questsProgressed, grants silver, mastery, bond, weekly. Once per run.
function ProgressionService.grantRunRewards(player: Player, summary: Types.RunSummary): Types.RunSummary
	local out: any = table.clone(summary :: any)
	out.silverEarned = 0
	out.questsProgressed = {}
	if not isPlayer(player) or type(summary) ~= "table" then
		return out
	end
	local info = runInfo[player]
	local runId = if info then info.runId else -1
	if info and rewardedRun[player] == runId then
		warn(`[ProgressionService] grantRunRewards called twice for {player.Name} (run {runId}): ignored`)
		return out
	end
	flushPending(player)

	local tier = math.floor(num(summary.tier, 1, Progression.MaxTier))
	local worldId = if type(summary.worldId) == "string" and WORLD_SET[summary.worldId] then summary.worldId else nil
	local victory = summary.victory == true
	local finalWave = num(summary.finalWaveSeconds, 0, 3600)
	local level = math.floor(num(summary.level, 0, 1000))
	local kills = math.floor(num(summary.kills, 0, 1e6))
	local stageReached = math.floor(num(summary.stageReached, 1, 3))
	local companionStage = math.floor(num(summary.companionStage, 1, 3))
	local classId = if type(summary.classId) == "string" and CLASS_SET[summary.classId] then summary.classId else nil
	local line = if type(summary.companionId) == "string" and LINE_SET[summary.companionId] then summary.companionId else nil
	local partySize = if info then info.partySize else 1
	local downed = info ~= nil and info.downed
	-- Classement (regles-v2 §4.2) : une écriture par run, par ce serveur de run, avant les gains.
	-- Les retardataires (pas de runInfo) ne sont jamais classés (§5.5).
	if info then
		scoreRun(player, info, kills, if summary.cashedOut == true then "CashOut" else "End")
	end

	local cfgS = Progression.Silver
	-- Review findings 1, 2, 5: only players who started this run get credit (late joiners and
	-- repeated calls have no runInfo), and a defeat only counts after MinRunSecondsForRewards.
	local duration = if info and type(info.startedAt) == "number" then os.clock() - info.startedAt else 0
	local played = info ~= nil and duration >= cfgS.MinRunSecondsForRewards
	victory = victory and info ~= nil
	local base = cfgS.VictoryByTier[tier]
	local silver = if victory then base elseif played then math.max(cfgS.DefeatMin, math.floor(base * cfgS.DefeatShare)) else 0
	local steps = if info then math.min(cfgS.FinalWaveMaxSteps, math.floor(finalWave / 30)) else 0
	silver += steps * cfgS.FinalWavePer30sByTier[tier]
	silver = math.clamp(silver, 0, base + cfgS.FinalWaveMaxSteps * cfgS.FinalWavePer30sByTier[tier])

	local damageTotal = 0
	local weaponDamage: { [string]: number } = {}
	if type(summary.damageByWeapon) == "table" then
		local n = 0
		for id, dmg in summary.damageByWeapon do
			n += 1
			if n > 16 then
				break
			end
			if validId(id, 32) and isFiniteNumber(dmg) and dmg > 0 then
				local d = math.min(dmg, 1e9)
				weaponDamage[id] = d
				damageTotal += d
			end
		end
	end

	local challenge = ProgressionService.getWeeklyChallenge()
	local weeklyNow = false
	-- Pass saisonnier (A12-04) : XP gagnée en jouant, bornée par la saison.
	local season = Products.activeSeason(os.time())
	local worldsCleared = math.floor(num((summary :: any).worldsCleared, 0, 3))
	local seasonXp = if season and (played or victory) then seasonXpFor(kills, worldsCleared) else 0
	local ok = withProfile(player, function(d, done)
		rollWeek(d)
		d.silver += silver
		d.silverEarnedTotal += silver
		if season and seasonXp > 0 then
			local current = tonumber(d.seasons[season.id]) or 0
			d.seasons[season.id] = math.min(season.tiers * season.xpPerTier, current + seasonXp)
		end
		if played or victory then
			applyStat(d, "RunsPlayed", 1, done)
		end
		if victory then
			applyStat(d, "Wins", 1, done)
			if tier == 3 then
				applyStat(d, "WinsTier3", 1, done)
			end
			if worldId then
				applyStat(d, `Win_{worldId}_T{tier}`, 1, done)
			end
			if not downed then
				applyStat(d, "WinNoDown", 1, done)
			end
			if partySize >= 4 then
				applyStat(d, "CoopFullWins", 1, done)
			end
			if classId then
				applyStat(d, `Class_{classId}_Wins`, 1, done)
			end
		end
		if finalWave > 0 then
			applyStat(d, "FinalWaveSecondsTotal", finalWave, done)
			applyStat(d, "BestFinalWave", math.floor(finalWave), done)
			if finalWave > d.boards.bestFinalWave then
				d.boards.bestFinalWave = math.floor(finalWave)
			end
		end
		applyStat(d, "BestRunLevel", level, done)
		applyStat(d, "DamageDealt", damageTotal, done)
		for id, dmg in weaponDamage do
			applyStat(d, `DamageWeapon_{id}`, dmg, done)
		end
		if classId and (played or victory) then
			applyStat(d, `Class_{classId}_BestLevel`, level, done)
			local m = Progression.Mastery
			local xp = m.RunBase + m.PerStage * stageReached + (if victory then m.Victory else 0) + math.floor(kills / m.KillsPerXp)
			addMastery(d, classId, math.min(xp, m.RunCap))
		end
		if line and (played or victory) then
			local b = Progression.Bond
			local xp = b.RunBase + b.PerStage * companionStage + (if victory then b.Victory else 0)
			addBond(d, line, math.min(xp, b.RunCap), done)
		end
		-- Weekly challenge: victory with the imposed class + companion, once per week.
		if d.weekly.week ~= challenge.week then
			d.weekly.week = challenge.week
			d.weekly.done = false
			d.weekly.bestSeconds = 0
		end
		if victory and not d.weekly.done and classId == challenge.classId and (challenge.companionId == "" or line == challenge.companionId) then
			d.weekly.done = true
			weeklyNow = true
			local w = Progression.Weekly
			d.questTokens += w.RewardTokens
			d.eggs += w.RewardEggs
			if not d.weekly.everDone then
				d.weekly.everDone = true
				grantCosmetic(d, w.FirstTimeCosmetic)
			end
		end
	end)
	if not ok then
		return out -- profile not mutable (loading, released, lost): nothing granted
	end
	if info then
		rewardedRun[player] = runId
	end
	out.silverEarned = silver
	out.seasonXp = seasonXp -- champ en plus du contrat RunSummary (écran de fin)

	-- Quests that moved during this run (completed first, then closest to their goal), max 8.
	local data = dataService().peek(player)
	if data then
		local before = if info then info.statsBefore else {}
		local moved = {}
		for _, def in Quests.List do
			local now = tonumber(data.stats[def.stat]) or 0
			local was = tonumber(before[def.stat]) or 0
			local completedNow = data.questsDone[def.id] ~= nil
			local wasDone = was >= def.goal
			if now > was and not wasDone then
				table.insert(moved, { id = def.id, progress = math.min(now, def.goal), goal = def.goal, completed = completedNow })
			end
		end
		table.sort(moved, function(a, b)
			if a.completed ~= b.completed then
				return a.completed
			end
			return a.progress / a.goal > b.progress / b.goal
		end)
		local list = {}
		for i = 1, math.min(8, #moved) do
			list[i] = moved[i]
		end
		out.questsProgressed = list
		logEconomy(player, true, "Silver", silver, data.silver, "Gameplay", "RunReward")
	end
	if weeklyNow then
		ProgressionService.logCustom(player, "WeeklyDone", 1, nil)
	end
	ProgressionService.logCustom(player, "RunEnd", 1, {
		`{worldId or "?"}-T{tier}`,
		if victory then "Win" else "Loss",
		tostring(math.clamp(partySize, 1, 4)),
	})
	onboarding(player, 6, "RunEnded")
	runInfo[player] = nil
	dataService().saveSoon(player)
	return out
end

---------------------------------------------------------------------------------------------------
-- Remote handlers
---------------------------------------------------------------------------------------------------
local function onSelectLoadout(player: Player, classId: any, companionId: any, companionId2: any)
	if not loadoutChangeAllowed() then
		return
	end
	if not ProgressionService.setLoadout(player, classId, companionId, companionId2) then
		markDirty(player) -- resend the real state so the client UI resyncs
	end
end

-- Pose / Tint : un cosmétique sans classId (premium, saison) va sur toutes les classes (A12-04).
local SIMPLE_SLOTS = {
	Title = true,
	Emote = true,
	Footstep = true,
	Aura = true,
	Trail = true,
	KoEffect = true,
	CompanionHat = true,
	CompanionColor = true,
}
local CLASS_SLOTS = { Tint = true, Pose = true }
local LINE_SLOTS = { CompanionTint = true, CompanionPose = true }

local function onEquipCosmetic(player: Player, slot: any, cosmeticId: any)
	if type(slot) ~= "string" or #slot > 48 then
		return
	end
	if cosmeticId ~= nil and not validId(cosmeticId, 64) then
		return
	end
	local data = dataService().peek(player)
	if not data then
		return
	end
	local base, arg = string.match(slot, "^(%a+):(%w+)$")
	if not base then
		base = slot
	end
	-- Companion start technique (sidegrade gated by bond level, read by CompanionService).
	if base == "StartTech" then
		if not arg or not LINE_SET[arg] then
			return
		end
		if cosmeticId ~= nil then
			local companions = optionalConfig("Companions")
			local lineDef = companions and companions.Lines and companions.Lines[arg]
			local unlockAt = companions and companions.Bond and companions.Bond.StartTechUnlock
			if type(lineDef) ~= "table" or type(lineDef.techs) ~= "table" or type(unlockAt) ~= "table" then
				return
			end
			local idx = table.find(lineDef.techs, cosmeticId)
			if not idx or bondLevelOf(data, arg) < (tonumber(unlockAt[idx]) or math.huge) then
				return
			end
		end
		withProfile(player, function(d)
			d.companionStartTech[arg :: string] = cosmeticId
		end)
		return
	end
	if arg then
		if CLASS_SLOTS[base] then
			if not CLASS_SET[arg] then
				return
			end
		elseif LINE_SLOTS[base] then
			if not LINE_SET[arg] then
				return
			end
		else
			return
		end
	elseif not SIMPLE_SLOTS[base] then
		return
	end
	if cosmeticId ~= nil then
		local def = Cosmetics[cosmeticId]
		if not def or def.slot ~= base then
			return
		end
		if CLASS_SLOTS[base] and def.classId ~= nil and def.classId ~= arg then
			return
		end
		if LINE_SLOTS[base] and def.line ~= arg then
			return
		end
		if not ownsCosmetic(player, data, cosmeticId) then
			return
		end
	end
	withProfile(player, function(d)
		d.equipped[slot] = cosmeticId
	end)
end

local SETTINGS_BOOL = { keepHat = true, colorblind = true, reduceFlashes = true }
local function onUpdateSettings(player: Player, settings: any)
	if type(settings) ~= "table" then
		return
	end
	local clean: { [string]: any } = {}
	local count = 0
	for k, v in settings do
		count += 1
		if count > 8 or type(k) ~= "string" then
			return
		end
		if SETTINGS_BOOL[k] then
			if type(v) ~= "boolean" then
				return
			end
			clean[k] = v
		elseif k == "textScale" then
			if not isFiniteNumber(v) then
				return
			end
			clean[k] = math.clamp(math.floor(v * 100 + 0.5) / 100, 0.8, 1.5)
		else
			return -- unknown key: reject the whole request
		end
	end
	withProfile(player, function(d)
		for k, v in clean do
			d.settings[k] = v
		end
	end)
end

local function shopPrice(data: Data, offerId: string): (string?, number?, (Data) -> ())
	local upgrade = Progression.ShopUpgrades[offerId]
	if upgrade then
		local lvl = math.floor(tonumber(data.shop[upgrade.field]) or 0)
		local price = upgrade.prices[lvl + 1]
		if not price then
			return nil, nil, function() end
		end
		return "Silver", price, function(d: Data)
			d.shop[upgrade.field] = lvl + 1
		end
	end
	local kind, id = string.match(offerId, "^Shop_(%a+)_([%w_]+)$")
	if kind == "Weapon" or kind == "Grimoire" then
		local rule = Progression.Unlocks[kind][id :: string]
		if not rule or not rule.silver or unlockedIn(data, kind, id :: string) then
			return nil, nil, function() end
		end
		return "Silver", rule.silver, function(d: Data)
			d.unlocks[kind :: string][id :: string] = true
		end
	elseif kind == "Item" then
		local price = itemSilverPrice(id :: string)
		if not price or price <= 0 or stored(data, "Item", id :: string) then
			return nil, nil, function() end
		end
		return "Silver", price, function(d: Data)
			d.unlocks.Item[id :: string] = true
		end
	end
	local cosmeticId = string.match(offerId, "^Cosmetic_([%w_]+)$")
	if cosmeticId then
		local def = Cosmetics[cosmeticId]
		if not def or def.source ~= "Tokens" or not def.price or data.cosmetics[cosmeticId] then
			return nil, nil, function() end
		end
		return "QuestTokens", def.price, function(d: Data)
			d.cosmetics[cosmeticId] = true
		end
	end
	return nil, nil, function() end
end

local function onShopBuy(player: Player, offerId: any)
	if not validId(offerId, 64) then
		return
	end
	local data = dataService().peek(player)
	if not data then
		return
	end
	local currency, price, apply = shopPrice(data, offerId)
	if not currency or not price then
		return
	end
	local field = if currency == "Silver" then "silver" else "questTokens"
	local paid = false
	withProfile(player, function(d)
		-- re-check inside the mutation (no yield since the lookup, but stay defensive)
		if (tonumber(d[field]) or 0) < price then
			return
		end
		d[field] -= price
		apply(d)
		paid = true
	end)
	if paid then
		local after = dataService().peek(player)
		logEconomy(player, false, currency, price, if after then after[field] else 0, "Shop", offerId)
		dataService().saveSoon(player)
	end
end

local rng = Random.new()
local function onHatchEgg(player: Player)
	local data = dataService().peek(player)
	if not data or (tonumber(data.eggs) or 0) < 1 then
		return
	end
	local candidates = eggCandidates(data)
	local line: string? = if #candidates > 0 then candidates[rng:NextInteger(1, #candidates)] else nil
	local tokens = if line then nil else Progression.Eggs.DuplicateTokens
	local ok = withProfile(player, function(d)
		if d.eggs < 1 then
			return
		end
		d.eggs -= 1
		d.eggsHatched += 1
		if line then
			d.unlocks.Companion[line :: string] = true
		else
			d.questTokens += tokens :: number
		end
	end)
	if ok then
		Net.event("EggHatched"):FireClient(player, { line = line, tokens = tokens })
		ProgressionService.logCustom(player, "EggHatched", 1, { line or "Tokens" })
		dataService().saveSoon(player)
	end
end

---------------------------------------------------------------------------------------------------
-- Leaderboards v2 (A12-02) : meilleur nombre de KO en UNE run, hebdo + all-time.
-- Règles : docs/security/regles-v2.md §4 (corrige S-06). OrderedDataStore = index, jamais la vérité :
-- le profil garde le relevé (boards.best / boards.weekBest). Écrit une fois par run et par joueur,
-- par le serveur de run (fin de run, Cash out ou départ en cours de run), jamais depuis Studio,
-- jamais pour un retardataire, un banni ou une run en quarantaine. Le tricheur ne voit rien.
---------------------------------------------------------------------------------------------------
local LB = Progression.Leaderboards
local QC = LB.Quarantine
local WEEKLY_BOARD, ALLTIME_BOARD = LB.Boards[1], LB.Boards[2]
for _, board in LB.Boards do
	if board.weekly then
		WEEKLY_BOARD = board
	else
		ALLTIME_BOARD = board
	end
end
local IS_STUDIO = RunService:IsStudio()
local boardCache: { [string]: { { userId: number, value: number } } } = {}
local memoryBoards: { [string]: { [string]: number } } = {}
local bannedIds: { [number]: boolean } = {}
for _, id in LB.BoardBans do
	if type(id) == "number" then
		bannedIds[id] = true
	end
end

-- Repli en mémoire : Studio (jamais d'écriture réelle depuis Studio, §4.2), profil de test, ou
-- magasin de données en mémoire. En live, une erreur reste une erreur (réessais, puis log).
local function boardsInMemory(): boolean
	local ds = dataService()
	return IS_STUDIO or ds.isTestSession() or ds.isMemoryBackend()
end

local warnedMemoryBoards = false
local function noteMemoryBoards()
	if not warnedMemoryBoards then
		warnedMemoryBoards = true
		warn(
			"[ProgressionService] Leaderboards use an IN-MEMORY store (Studio / test profile / no API access):"
				.. " nothing is written to the real OrderedDataStores and scores vanish when the server stops."
		)
	end
end

local function storeName(board: { store: string, weekly: boolean }, week: number): string
	return if board.weekly then `{board.store}_W{week}` else board.store
end

local function boardKey(userId: number): string
	return `u_{userId}`
end

-- Garde le maximum, ne baisse jamais une valeur. Yields (réessais). true si écrit ou déjà >= value.
local function boardUpdate(name: string, userId: number, value: number): boolean
	local key = boardKey(userId)
	if boardsInMemory() then
		noteMemoryBoards()
		local t = memoryBoards[name]
		if not t then
			t = {}
			memoryBoards[name] = t
		end
		if (t[key] or 0) < value then
			t[key] = value
		end
		return true
	end
	for attempt = 1, LB.WriteAttempts do
		local ok, err = pcall(function()
			DataStoreService:GetOrderedDataStore(name):UpdateAsync(key, function(old: any): any
				if type(old) == "number" and old >= value then
					return nil -- score monotone dans sa période
				end
				return value
			end)
		end)
		if ok then
			return true
		end
		warn(`[ProgressionService] board {name} write failed ({attempt}/{LB.WriteAttempts}): {err}`)
		if attempt < LB.WriteAttempts then
			task.wait(attempt * 2 * (0.5 + math.random()))
		end
	end
	return false
end

local function boardRemove(name: string, userId: number)
	local key = boardKey(userId)
	if boardsInMemory() then
		local t = memoryBoards[name]
		if t then
			t[key] = nil
		end
		return
	end
	for attempt = 1, LB.WriteAttempts do
		local ok, err = pcall(function()
			DataStoreService:GetOrderedDataStore(name):RemoveAsync(key)
		end)
		if ok then
			return
		end
		warn(`[ProgressionService] board {name} remove failed ({attempt}/{LB.WriteAttempts}): {err}`)
		if attempt < LB.WriteAttempts then
			task.wait(attempt * 2)
		end
	end
end

local function boardRead(name: string): { { userId: number, value: number } }
	local rows: { { userId: number, value: number } } = {}
	if boardsInMemory() then
		for key, value in memoryBoards[name] or {} do
			local userId = tonumber(string.match(key, "^u_(%d+)$"))
			if userId then
				table.insert(rows, { userId = userId, value = value })
			end
		end
		table.sort(rows, function(a, b)
			return a.value > b.value
		end)
		while #rows > LB.TopN do
			table.remove(rows)
		end
		return rows
	end
	local page = DataStoreService:GetOrderedDataStore(name):GetSortedAsync(false, LB.TopN):GetCurrentPage()
	for _, entry in page do
		local userId = tonumber(string.match(entry.key, "^u_(%d+)$"))
		if userId and type(entry.value) == "number" then
			table.insert(rows, { userId = userId, value = entry.value })
		end
	end
	return rows
end

local function safeCall(service: any, fnName: string, ...: any): any
	if service and type(service[fnName]) == "function" then
		local ok, result = pcall(service[fnName], ...)
		if ok then
			return result
		end
	end
	return nil
end

-- Petit résumé du build pour le relevé (purge par filtre plus tard) : "<arme>:<niveau>", 4 max.
local function buildDigest(player: Player): { string }
	local out: { string } = {}
	local build = safeCall(Registry.find("StatsService"), "getBuild", player)
	if type(build) == "table" and type(build.weapons) == "table" then
		for _, w in build.weapons do
			if #out >= 4 then
				break
			end
			if type(w) == "table" and validId(w.id, 32) and isFiniteNumber(w.level) then
				table.insert(out, `{w.id}:{math.floor(w.level)}`)
			end
		end
	end
	return out
end

-- Pousse le relevé du profil vers les tableaux (écriture déjà validée par un serveur de run).
-- Marque `written` si le joueur est toujours là ; sinon on repoussera au prochain chargement.
local function pushRecords(player: Player, week: number, pushWeek: boolean, pushAll: boolean, ko: number)
	local userId = player.UserId
	task.spawn(function()
		local okWeek = not pushWeek or boardUpdate(storeName(WEEKLY_BOARD, week), userId, ko)
		local okAll = not pushAll or boardUpdate(storeName(ALLTIME_BOARD, week), userId, ko)
		if player.Parent then
			dataService().mutate(player, function(d)
				local b = d.boards
				if pushWeek and okWeek and type(b.weekBest) == "table" and b.weekBest.week == week then
					b.weekBest.written = true
				end
				if pushAll and okAll and type(b.best) == "table" then
					b.best.written = true
				end
			end)
		end
	end)
end

local function countRecent(list: { any }, now: number, windowSeconds: number): number
	local n = 0
	for _, rec in list do
		if type(rec) == "table" and isFiniteNumber(rec.at) and now - rec.at <= windowSeconds then
			n += 1
		end
	end
	return n
end

-- Soumet le score d'une run (synchrone pour le profil ; les écritures de tableau partent en tâche).
-- ending : "End" | "CashOut" | "Left". kills : total serveur de la run (StatsService).
function scoreRun(player: Player, info: RunInfo, kills: number, ending: string)
	if info.scored then
		return
	end
	info.scored = true
	local userId = player.UserId
	local ko = math.floor(num(kills, 0, LB.MaxValue))
	if LB.ScoreWindowOvertimeSeconds > 0 then
		ko = math.min(ko, math.floor(num(info.koCounted, 0, LB.MaxValue)))
	end
	local duration = math.max(1, os.clock() - info.startedAt)
	local reasons: { string } = {}
	local logs: { string } = {}

	-- §2.3 : on juge les conditions qui ont produit le score, pas le nombre seul.
	local strikes = safeCall(Registry.find("MovementGuard"), "getRunStrikes", player)
	strikes = if isFiniteNumber(strikes) then strikes else 0
	if strikes >= QC.MaxStrikes then
		table.insert(reasons, "Strikes")
	end
	local invuln = safeCall(runManager(), "getInvulnerableSeconds", player)
	if isFiniteNumber(invuln) and duration >= QC.MinRunSecondsForShare and invuln / duration > QC.MaxInvulnShare then
		table.insert(reasons, "Invulnerable")
	end
	if info.noDamage then
		table.insert(if QC.NoDamageEnforce then reasons else logs, "NoDamageOvertime")
	end
	local perMinute = ko / (duration / 60)
	if QC.KoPerMinuteCap > 0 then
		if perMinute > QC.KoPerMinuteCap then
			table.insert(reasons, "KoRate")
		end
	elseif perMinute > QC.KoPerMinuteLog then
		table.insert(logs, "KoRate")
	end
	-- §2.2 invariants (si EnemyService expose le nombre d'ennemis apparus : contract request A03/A04).
	local spawned = safeCall(Registry.find("EnemyService"), "getRunSpawned")
	if isFiniteNumber(spawned) then
		local sum = 0
		local all = safeCall(Registry.find("StatsService"), "getRunKills")
		if type(all) == "table" then
			for _, n in all do
				if isFiniteNumber(n) then
					sum += n
				end
			end
		end
		if ko > spawned or sum > spawned then
			warn(`[ProgressionService] KO invariant broken for {userId}: ko={ko} sum={sum} spawned={spawned}`)
			table.insert(reasons, "Invariant")
		end
	end
	if #logs > 0 then
		warn(`[ProgressionService] board signal (log only) {userId}: {table.concat(logs, ",")} ko={ko} kpm={math.floor(perMinute)}`)
	end

	local now = os.time()
	local week = Progression.weekIndex(now)
	local record = {
		ko = ko,
		runKey = info.runKey,
		seconds = math.floor(duration),
		overtimeSeconds = math.floor(overtimeSeconds()),
		partySize = info.partySize,
		strikes = strikes,
		worldId = info.worldId,
		tier = info.tier,
		ending = ending,
		build = buildDigest(player),
		at = now,
	}
	local quarantined = #reasons > 0
	local banNow, pushWeek, pushAll = false, false, false
	withProfile(player, function(d)
		local b = d.boards
		if b.lastRunKey == info.runKey then
			return -- déjà soumis (idempotence, même après un double appel)
		end
		b.lastRunKey = info.runKey
		if quarantined then
			local rec = table.clone(record)
			rec.reasons = reasons
			table.insert(b.quarantined, rec)
			while #b.quarantined > QC.KeepRecords do
				table.remove(b.quarantined, 1)
			end
			if not d.flags.boardBanned and countRecent(b.quarantined, now, QC.BanWindowDays * 86400) >= QC.BanCount then
				d.flags.boardBanned = true
				banNow = true
			end
			return
		end
		if d.flags.boardBanned or bannedIds[userId] or ko <= 0 then
			return
		end
		local wb = b.weekBest
		if type(wb) ~= "table" or wb.week ~= week or ko > (tonumber(wb.ko) or 0) then
			local rec = table.clone(record)
			rec.week = week
			rec.written = false
			b.weekBest = rec
			pushWeek = true
		end
		if type(b.best) ~= "table" or ko > (tonumber(b.best.ko) or 0) then
			local rec = table.clone(record)
			rec.build = table.clone(record.build)
			rec.written = false
			b.best = rec
			pushAll = true
		end
	end, true)

	if quarantined then
		-- Log serveur seulement ; l'écran de fin reste normal (§0.5).
		warn(`[ProgressionService] run quarantined for {userId}: {table.concat(reasons, ",")} ko={ko}`)
	end
	if banNow then
		warn(`[ProgressionService] {userId} removed from leaderboards (3 quarantined runs in 7 days)`)
		task.spawn(function()
			for _, board in LB.Boards do
				boardRemove(storeName(board, week), userId)
			end
		end)
	end
	if pushWeek or pushAll then
		pushRecords(player, week, pushWeek, pushAll, ko)
		dataService().saveSoon(player)
	end
end

-- Au chargement : repousse un relevé validé dont l'écriture de tableau a échoué (idempotent, max).
local function pushPendingRecords(player: Player)
	local data = dataService().peek(player)
	if not data or data.flags.boardBanned or bannedIds[player.UserId] then
		return
	end
	local b = data.boards
	local week = Progression.weekIndex(os.time())
	local wb, best = b.weekBest, b.best
	local pushWeek = type(wb) == "table" and wb.week == week and wb.written == false and isFiniteNumber(wb.ko) and wb.ko > 0
	local pushAll = type(best) == "table" and best.written == false and isFiniteNumber(best.ko) and best.ko > 0
	if pushWeek then
		pushRecords(player, week, true, false, math.floor(wb.ko))
	end
	if pushAll then
		pushRecords(player, week, false, true, math.floor(best.ko))
	end
end

-- Départ en cours de run : les KO déjà faits comptent pour le classement (§4.2, §6.4).
local function scoreOnLeave(player: Player)
	local info = runInfo[player]
	if not info or info.scored then
		return
	end
	local phase = currentPhase()
	if phase == "Loadout" or phase == "Ended" then
		return
	end
	local kills = safeCall(Registry.find("StatsService"), "getKills", player)
	scoreRun(player, info, math.max(info.ko, if isFiniteNumber(kills) then kills else 0), "Left")
end

-- Signal « aucun dégât en Overtime » (§2.3), 1 Hz. Un joueur inactif (à terre, fantôme) remet le
-- compteur à zéro : il ne peut pas être touché, ce n'est pas suspect.
local function checkNoDamage()
	local ot = overtimeSeconds()
	if ot < QC.NoDamageAfterOvertime then
		return
	end
	local now = os.clock()
	local thresholdAt = now - (ot - QC.NoDamageAfterOvertime)
	local run = runManager()
	for player, info in runInfo do
		if info.noDamage then
			continue
		end
		if safeCall(run, "isActive", player) ~= true then
			info.lastDamagedAt = now
			continue
		end
		if now - math.max(info.lastDamagedAt, thresholdAt) >= QC.NoDamageSeconds then
			info.noDamage = true
		end
	end
end

local function refreshBoards()
	local week = Progression.weekIndex(os.time())
	for _, board in LB.Boards do
		local ok, result = pcall(boardRead, storeName(board, week))
		if ok then
			local rows = {}
			for _, row in result do
				if not bannedIds[row.userId] then -- §4.4 : bannis filtrés à la lecture aussi
					table.insert(rows, row)
				end
			end
			boardCache[board.key] = rows
		else
			warn(`[ProgressionService] board {board.key} read failed: {result}`)
		end
	end
	Net.event("Leaderboards"):FireAllClients(boardCache)
end

---------------------------------------------------------------------------------------------------
-- Session hooks
---------------------------------------------------------------------------------------------------
local function returnBucket(createdAt: number): string
	local days = math.floor((os.time() - createdAt) / 86400)
	if days <= 0 then
		return "D0"
	elseif days == 1 then
		return "D1"
	elseif days <= 7 then
		return "D2-7"
	elseif days <= 28 then
		return "D8-28"
	end
	return "D29+"
end

local function onProfileLoaded(player: Player)
	local data = dataService().peek(player)
	if not data then
		return
	end
	onboarding(player, 2, "ProfileLoaded")
	ProgressionService.logCustom(player, "ReturnDay", 1, { returnBucket(tonumber(data.createdAt) or os.time()) })
	-- Backfill bond/mastery cosmetics and stats if config levels moved (idempotent).
	withProfile(player, function(d, done)
		for line, lvl in d.bond do
			if type(line) == "string" and LINE_SET[line] and isFiniteNumber(lvl) then
				applyStat(d, `Bond_{line}`, lvl, done)
			end
		end
	end)
	markDirty(player)
	pushPendingRecords(player)
	if next(boardCache) then
		Net.event("Leaderboards"):FireClient(player, boardCache)
	end
end

local function beforeRelease(player: Player)
	flushPending(player)
	scoreOnLeave(player) -- profil encore modifiable : le relevé part dans la sauvegarde finale
	local started = joinedAt[player]
	if started then
		ProgressionService.logCustom(player, "SessionMinutes", math.floor((os.clock() - started) / 60), nil)
		ProgressionService.logCustom(player, "SessionRuns", sessionRuns[player] or 0, nil)
		joinedAt[player] = nil
	end
	flushEvents(player)
end

local function onPlayerAdded(player: Player)
	joinedAt[player] = os.clock()
	sessionRuns[player] = 0
	safe(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, 1, "Joined")
	end)
	onboardingMax[player] = 1
	task.delay(600, function()
		if player.Parent then
			onboarding(player, 8, "Minute10")
		end
	end)
end

local function onPlayerRemoving(player: Player)
	-- DataService runs beforeRelease through its release hook while the profile is still mutable.
	task.defer(function()
		flushEvents(player)
		pending[player] = nil
		dirty[player] = nil
		selected[player] = nil
		runInfo[player] = nil
		rewardedRun[player] = nil
		sessionRuns[player] = nil
		joinedAt[player] = nil
		firstKill[player] = nil
		onboardingMax[player] = nil
	end)
end

---------------------------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------------------------
function ProgressionService.init()
	Net.onServerEvent("SelectLoadout", 2, onSelectLoadout)
	Net.onServerEvent("EquipCosmetic", 4, onEquipCosmetic)
	Net.onServerEvent("UpdateSettings", 2, onUpdateSettings)
	Net.onServerEvent("ShopBuy", 3, onShopBuy)
	Net.onServerEvent("HatchEgg", 1, onHatchEgg)

	Bus.ProfileLoaded:connect(onProfileLoaded)
	Bus.RunStarted:connect(onRunStarted)
	Bus.EnemyKilled:connect(onEnemyKilled)
	Bus.PlayerDamaged:connect(onPlayerDamaged)
	Bus.BossDefeated:connect(onBossDefeated)
	Bus.StageStarted:connect(onStageStarted)
	Bus.PlayerDowned:connect(onPlayerDowned)
	Bus.PlayerRevived:connect(onPlayerRevived)
	Bus.ShrineCompleted:connect(onShrineCompleted)
	Bus.CompanionEvolved:connect(onCompanionEvolved)
	Bus.FinalWaveStarted:connect(onFinalWaveStarted)
	Bus.KOScored:connect(onKOScored)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	dataService().addReleaseHook(beforeRelease)
end

function ProgressionService.start()
	for _, p in Players:GetPlayers() do
		if not joinedAt[p] then
			onPlayerAdded(p)
		end
	end
	-- Buffered stats (1 s) and Profile replication (0.25 s)
	task.spawn(function()
		local acc = 0
		while true do
			task.wait(0.25)
			acc += 0.25
			if acc >= 1 then
				acc = 0
				for p in pending do
					flushPending(p)
				end
				checkNoDamage()
			end
			for p in dirty do
				dirty[p] = nil
				if p.Parent then
					sendProfile(p)
				end
			end
		end
	end)
	-- Analytics flush (60 s)
	task.spawn(function()
		while true do
			task.wait(60)
			for p in pendingEvents do
				flushEvents(p)
			end
		end
	end)
	-- Leaderboards: written once per run (scoreRun) ; tops read every 120 s + jitter
	task.spawn(function()
		task.wait(5 + math.random() * LB.RefreshJitter)
		while true do
			refreshBoards()
			task.wait(LB.RefreshSeconds + math.random() * LB.RefreshJitter)
		end
	end)
end

return ProgressionService
