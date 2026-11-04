--!strict
-- Level-up card offers (dossier 10, section 4; doc 5.2): 3 cards, 8 s, no pause, invulnerable and
-- slowed while choosing, auto-pick of the rarest card on timeout, queued level-ups.
-- CardChoice (C->S) is validated strictly: rate limit, types, offerId, action, index, charges.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Cards = require(Config:WaitForChild("Cards"))
local Grimoires = require(Config:WaitForChild("Grimoires"))
local Rarities = require(Config:WaitForChild("Rarities"))
local Weapons = require(Config:WaitForChild("Weapons"))
local Net = require(Shared:WaitForChild("Net"))
local Registry = require(Shared:WaitForChild("Registry"))
local Types = require(Shared:WaitForChild("Types"))
local Bus = require(script.Parent.Parent:WaitForChild("Bus"))

type Card = Types.Card

-- Server-only data kept next to each offered card.
type Meta = {
	source: string, -- "weapon" | "grimoire" | "companion" | "fallback"
	toLevel: number,
	bonus: number,
	companionCard: Card?,
}

type Offer = {
	offerId: number,
	cards: { Card },
	meta: { Meta },
	expiresAt: number,
}

type PlayerCards = {
	pending: number,
	offer: Offer?,
	offersMade: number,
}

type Candidate = { kind: string, id: string, weight: number }

local CardService = {}

local data: { [Player]: PlayerCards } = {}
local offerRemote: RemoteEvent
local nextOfferId = 0
local rng = Random.new()

local ACTIONS = { pick = true, ban = true, skip = true, reroll = true }

local function L(text: { fr: string, en: string }): string
	return if Cards.Locale == "en" then text.en else text.fr
end

local function getData(player: Player): PlayerCards
	local d = data[player]
	if not d then
		d = { pending = 0, offer = nil, offersMade = 0 }
		data[player] = d
	end
	return d
end

local function newOfferId(): number
	nextOfferId = nextOfferId % 1e9 + 1
	return nextOfferId
end

-- Une arme ou une Rune non verrouillée (unlock "Free", le défaut v2) est toujours dans le tirage.
-- Les autres demandent ProgressionService.isUnlocked (bloquées s'il manque). Les règles du domaine
-- data (Config/Progression) portent encore les ids v1 : voir la contract request du rapport A04.
local function isUnlocked(player: Player, kind: string, id: string, gated: boolean?): boolean
	if not gated then
		return true
	end
	local progression = Registry.find("ProgressionService")
	if progression and progression.isUnlocked then
		local ok, result = pcall(progression.isUnlocked, player, kind, id)
		return ok and result == true
	end
	return false
end

local function isActive(player: Player): boolean
	local run = Registry.find("RunManager")
	if run and run.isActive then
		local ok, result = pcall(run.isActive, player)
		return ok and result == true
	end
	return player.Character ~= nil
end

-- Card text ---------------------------------------------------------------------------

-- Texte joueur (anglais) d'un delta de niveau d'arme : "+5 damage, +15% area".
local function formatDelta(delta: { [string]: number }): string
	local parts = {}
	for k, v in delta do
		local pct = false
		local key = k
		if string.sub(k, -3) == "Pct" then
			key = string.sub(k, 1, -4)
			pct = true
		end
		if key == "dmgMult" then
			key, pct = "damage", true
		end
		local label = Cards.WeaponStatWords[key]
		if not label then
			continue
		end
		if pct then
			table.insert(parts, string.format("%+d%% %s", math.round(v * 100), label))
		elseif key == "critChance" or key == "critDamage" or key == "lifesteal" then
			table.insert(parts, string.format("%+d%% %s", math.round(v * 100), label))
		else
			table.insert(parts, string.format("%+g %s", v, label))
		end
	end
	table.sort(parts)
	return table.concat(parts, ", ")
end

local function grimoireDesc(def: Grimoires.GrimoireDef, fromLevel: number, toLevel: number): string
	local parts = {}
	for stat in Grimoires.BaseStats do
		local diff = Grimoires.valueAt(def, stat, toLevel) - Grimoires.valueAt(def, stat, fromLevel)
		if diff ~= 0 then
			local label = Grimoires.StatLabel[stat]
			local name = if Cards.Locale == "en" then label.en else label.fr
			if label.pct then
				table.insert(parts, string.format("%+d%% %s", math.round(diff * 100), name))
			else
				table.insert(parts, string.format("%+g %s", diff, name))
			end
		end
	end
	table.sort(parts)
	return table.concat(parts, ", ")
end

-- Candidates ---------------------------------------------------------------------------

local function buildCandidates(player: Player, exclude: { [string]: boolean }): { Candidate }
	local stats = Registry.get("StatsService")
	local s = stats.getState(player)
	local list: { Candidate } = {}
	if not s then
		return list
	end
	local owned: { [string]: number } = {}
	for _, w in s.weapons do
		owned[w.id] = w.level
	end
	for _, id in Weapons.Order do
		if s.banished[id] or exclude[id] then
			continue
		end
		local level = owned[id]
		if level then
			if level < Weapons.MaxLevel then
				table.insert(list, { kind = "WeaponUp", id = id, weight = Cards.PoolWeight.WeaponUp })
			elseif level == Weapons.MaxLevel then
				local fusion = Weapons.Defs[id].fusion
				if Weapons.FusionEnabled and fusion and stats.getGrimoireLevel(player, fusion.grimoire) >= fusion.minGrimoireLevel then
					table.insert(list, { kind = "Fusion", id = id, weight = Cards.PoolWeight.Fusion })
				end
			end
		elseif #s.weapons < s.weaponSlots and isUnlocked(player, "Weapon", id, Weapons.Defs[id].unlock ~= nil and Weapons.Defs[id].unlock ~= "Free") then
			table.insert(list, { kind = "NewWeapon", id = id, weight = Cards.PoolWeight.NewWeapon })
		end
	end
	local gOwned: { [string]: number } = {}
	for _, g in s.grimoires do
		gOwned[g.id] = g.level
	end
	for _, id in Grimoires.Order do
		if s.banished[id] or exclude[id] then
			continue
		end
		local def = Grimoires.Defs[id]
		local level = gOwned[id]
		if level then
			if level < def.maxLevel then
				table.insert(list, { kind = "GrimoireUp", id = id, weight = Cards.PoolWeight.GrimoireUp })
			end
		elseif #s.grimoires < s.grimoireSlots and isUnlocked(player, "Grimoire", id, def.unlockGated) then
			table.insert(list, { kind = "NewGrimoire", id = id, weight = Cards.PoolWeight.NewGrimoire })
		end
	end
	return list
end

local function takeWeighted(list: { Candidate }): Candidate?
	local total = 0
	for _, c in list do
		total += c.weight
	end
	if total <= 0 then
		return nil
	end
	local pick = rng:NextNumber() * total
	for i, c in list do
		pick -= c.weight
		if pick <= 0 then
			table.remove(list, i)
			return c
		end
	end
	return table.remove(list)
end

local function makeCard(player: Player, cand: Candidate, minRank: number?): (Card, Meta)
	local stats = Registry.get("StatsService")
	local luck = stats.get(player).Luck or 0
	if cand.kind == "Fusion" then
		local def = Weapons.Defs[cand.id]
		local fusion = def.fusion :: any
		return {
			kind = "WeaponUp",
			id = cand.id,
			rarity = "Legendary",
			level = Weapons.FusionLevel,
			title = `{L(Cards.Text.Fusion)}: {L(fusion.name)}`,
			desc = L(fusion.desc),
			icon = nil,
		}, { source = "weapon", toLevel = Weapons.FusionLevel, bonus = 0 }
	end
	local rarity = Rarities.roll(luck, rng, minRank)
	if cand.kind == "NewWeapon" or cand.kind == "WeaponUp" then
		local def = Weapons.Defs[cand.id]
		local cur = stats.getWeaponLevel(player, cand.id)
		local toLevel = math.min(cur + Cards.WeaponLevels[rarity], Weapons.MaxLevel)
		local bonus = Cards.WeaponDamageBonus[rarity]
		local desc: string
		if cur == 0 then
			desc = L(def.desc)
		else
			local deltas = {}
			for l = cur + 1, toLevel do
				table.insert(deltas, formatDelta(def.levels[l - 1]))
			end
			desc = table.concat(deltas, " | ")
		end
		if bonus > 0 then
			desc ..= string.format(" (+%d%% %s)", math.round(bonus * 100), L(Cards.Text.Damage))
		end
		local title = if cur == 0 then `{L(Cards.Text.NewWeapon)}: {L(def.name)}` else `{L(def.name)} {L(Cards.Text.Level)} {toLevel}`
		return {
			kind = if cur == 0 then "NewWeapon" else "WeaponUp",
			id = cand.id,
			rarity = rarity :: any,
			level = toLevel,
			title = title,
			desc = desc,
			icon = nil,
		}, { source = "weapon", toLevel = toLevel, bonus = bonus }
	end
	local def = Grimoires.Defs[cand.id]
	local cur = stats.getGrimoireLevel(player, cand.id)
	local toLevel = math.min(cur + Cards.GrimoireLevels[rarity], def.maxLevel)
	return {
		kind = if cur == 0 then "NewGrimoire" else "GrimoireUp",
		id = cand.id,
		rarity = rarity :: any,
		level = toLevel,
		title = if cur == 0 then `{L(Cards.Text.NewGrimoire)}: {L(def.name)}` else `{L(def.name)} {L(Cards.Text.Level)} {toLevel}`,
		desc = grimoireDesc(def, cur, toLevel),
		icon = nil,
	}, { source = "grimoire", toLevel = toLevel, bonus = 0 }
end

local function fallbackCards(): ({ Card }, { Meta })
	local cards: { Card } = {
		{ kind = "Heal", id = "Heal", rarity = "Common", level = 1, title = L(Cards.Text.Heal), desc = L(Cards.Text.HealDesc), icon = nil },
		{ kind = "Coins", id = "Coins", rarity = "Common", level = 1, title = L(Cards.Text.Coins), desc = L(Cards.Text.CoinsDesc), icon = nil },
	}
	local meta: { Meta } = {
		{ source = "fallback", toLevel = 1, bonus = 0 },
		{ source = "fallback", toLevel = 1, bonus = 0 },
	}
	return cards, meta
end

local function companionOptions(player: Player): { Card }
	local companion = Registry.find("CompanionService")
	if companion and companion.getCardOptions then
		local ok, options = pcall(companion.getCardOptions, player)
		if ok and type(options) == "table" then
			return table.clone(options)
		end
	end
	return {}
end

-- Construit `count` cartes en sautant les ids de `exclude`. `forceRare` : garantie du passif Mage.
local function drawCards(player: Player, count: number, exclude: { [string]: boolean }, forceRare: boolean): ({ Card }, { Meta })
	local candidates = buildCandidates(player, exclude)
	local companions = companionOptions(player)
	local cards: { Card } = {}
	local meta: { Meta } = {}
	for _ = 1, count do
		if #companions > 0 and (rng:NextNumber() < Cards.CompanionChance or #candidates == 0) then
			local c = table.remove(companions, rng:NextInteger(1, #companions)) :: Card
			table.insert(cards, c)
			table.insert(meta, { source = "companion", toLevel = c.level, bonus = 0, companionCard = c })
			continue
		end
		local cand = takeWeighted(candidates)
		if not cand then
			break
		end
		local card, m = makeCard(player, cand, nil)
		table.insert(cards, card)
		table.insert(meta, m)
	end
	if forceRare then
		local hasRare = false
		for _, c in cards do
			if Rarities.rank(c.rarity) >= 2 then
				hasRare = true
			end
		end
		if not hasRare then
			for i, m in meta do
				if m.source == "weapon" or m.source == "grimoire" then
					local id = cards[i].id
					local kind = if m.source == "weapon" then "WeaponUp" else "GrimoireUp"
					local card, newMeta = makeCard(player, { kind = kind, id = id, weight = 1 }, 2)
					cards[i], meta[i] = card, newMeta
					break
				end
			end
		end
	end
	if #cards == 0 then
		return fallbackCards()
	end
	return cards, meta
end

-- Offer lifecycle -------------------------------------------------------------------------

local function sendOffer(player: Player, offer: Offer)
	local s = Registry.get("StatsService").getState(player)
	offerRemote:FireClient(player, {
		offerId = offer.offerId,
		cards = offer.cards,
		expiresIn = math.max(0, offer.expiresAt - os.clock()),
		banish = if s then s.banish else 0,
		skip = if s then s.skip else 0,
		reroll = if s then s.reroll else 0,
	})
end

local function forceRareFor(player: Player, d: PlayerCards): boolean
	local classId = Registry.get("StatsService").getClass(player)
	local passive = classId and Weapons.Passives[classId]
	local every = passive and passive.rareEveryOffers :: number?
	return every ~= nil and d.offersMade % every == 0
end

local function tryOpen(player: Player)
	local d = data[player]
	if not d or d.offer or d.pending <= 0 then
		return
	end
	local stats = Registry.get("StatsService")
	if not stats.getState(player) or not isActive(player) then
		return
	end
	d.offersMade += 1
	local cards, meta = drawCards(player, Cards.OfferSize, {}, forceRareFor(player, d))
	local offer: Offer = {
		offerId = newOfferId(),
		cards = cards,
		meta = meta,
		expiresAt = os.clock() + Cards.OfferSeconds,
	}
	d.offer = offer
	local run = Registry.find("RunManager")
	if run then
		if run.setInvulnerable then
			pcall(run.setInvulnerable, player, Cards.OfferSeconds, "Card")
		end
		if run.setSlow then
			pcall(run.setSlow, player, Cards.SlowMultiplier, Cards.OfferSeconds)
		end
	end
	sendOffer(player, offer)
end

local function closeOffer(player: Player, d: PlayerCards)
	local offer = d.offer
	if not offer then
		return
	end
	d.offer = nil
	d.pending = math.max(0, d.pending - 1)
	-- S-05 : l'invulnérabilité du choix s'arrête avec le choix (l'offre suivante la redonne,
	-- dans la limite du plafond de RunManager).
	local run = Registry.find("RunManager")
	if run and run.clearInvulnerable then
		pcall(run.clearInvulnerable, player, "Card")
	end
	offerRemote:FireClient(player, { offerId = offer.offerId, closed = true })
	tryOpen(player)
end

local function applyCard(player: Player, card: Card, m: Meta)
	local stats = Registry.get("StatsService")
	if m.source == "weapon" then
		stats.upgradeWeapon(player, card.id, m.toLevel, m.bonus)
	elseif m.source == "grimoire" then
		stats.upgradeGrimoire(player, card.id, m.toLevel)
	elseif m.source == "companion" then
		local companion = Registry.find("CompanionService")
		if companion and companion.applyCard and m.companionCard then
			pcall(companion.applyCard, player, m.companionCard)
		end
	elseif card.kind == "Heal" then
		local run = Registry.find("RunManager")
		if run and run.healPlayer then
			pcall(run.healPlayer, player, stats.get(player).MaxHp * Cards.HealFraction)
		end
	elseif card.kind == "Coins" then
		local loot = Registry.find("LootService")
		if loot and loot.addCoins then
			local bonus = stats.get(player).LootBonus or 0
			pcall(loot.addCoins, player, math.floor(Cards.FallbackCoins * (1 + bonus)))
		end
	end
end

local function pickIndex(player: Player, d: PlayerCards, index: number)
	local offer = d.offer
	if not offer then
		return
	end
	local card, m = offer.cards[index], offer.meta[index]
	if card and m then
		applyCard(player, card, m)
		local prog = Registry.find("ProgressionService")
		if prog and prog.recordStat then
			pcall(prog.recordStat, player, "CardsPicked", 1) -- review finding 13
		end
	end
	closeOffer(player, d)
end

local function rarestIndex(cards: { Card }): number
	local best, bestRank = 1, -1
	for i, c in cards do
		local r = Rarities.rank(c.rarity)
		if r > bestRank then
			best, bestRank = i, r
		end
	end
	return best
end

local function onChoice(player: Player, offerId: unknown, action: unknown, index: unknown)
	-- Shape checks first (Net.onServerEvent already rate limited)
	if type(offerId) ~= "number" or offerId ~= offerId or offerId % 1 ~= 0 then
		return
	end
	if type(action) ~= "string" or not ACTIONS[action] then
		return
	end
	local d = data[player]
	local offer = d and d.offer
	if not d or not offer or offer.offerId ~= offerId then
		return
	end
	local needsIndex = action == "pick" or action == "ban"
	local i = 0
	if needsIndex then
		if type(index) ~= "number" or index ~= index or index % 1 ~= 0 or index < 1 or index > #offer.cards then
			return
		end
		i = index
	end
	local stats = Registry.get("StatsService")

	if action == "pick" then
		pickIndex(player, d, i)
	elseif action == "skip" then
		if stats.useCharge(player, "skip") then
			closeOffer(player, d)
		end
	elseif action == "reroll" then
		if offer.meta[1] and offer.meta[1].source == "fallback" then
			return
		end
		if stats.useCharge(player, "reroll") then
			local cards, meta = drawCards(player, Cards.OfferSize, {}, false)
			offer.cards, offer.meta = cards, meta
			offer.offerId = newOfferId()
			sendOffer(player, offer)
		end
	elseif action == "ban" then
		local m = offer.meta[i]
		if m.source ~= "weapon" and m.source ~= "grimoire" then
			return
		end
		if stats.useCharge(player, "banish") then
			local bannedId = offer.cards[i].id
			stats.banishId(player, bannedId)
			local exclude: { [string]: boolean } = {}
			for _, c in offer.cards do
				exclude[c.id] = true
			end
			local cands = buildCandidates(player, exclude)
			local cand = takeWeighted(cands)
			if cand then
				local card, newMeta = makeCard(player, cand, nil)
				offer.cards[i], offer.meta[i] = card, newMeta
			else
				table.remove(offer.cards, i)
				table.remove(offer.meta, i)
			end
			if #offer.cards == 0 then
				local cards, meta = fallbackCards()
				offer.cards, offer.meta = cards, meta
			end
			offer.offerId = newOfferId()
			sendOffer(player, offer)
		end
	end
end

-- Public API -----------------------------------------------------------------------------

function CardService.isChoosing(player: Player): boolean
	local d = data[player]
	return d ~= nil and d.offer ~= nil
end

function CardService.init()
	offerRemote = Net.event("CardOffer")
	Net.onServerEvent("CardChoice", Cards.ChoiceRate, onChoice)
	Bus.PlayerLeveledUp:connect(function(player: Player, _level: number)
		local d = getData(player)
		d.pending += 1
		tryOpen(player)
	end)
	Bus.RunStarted:connect(function(players: { Player })
		for _, p in players do
			local d = data[p]
			if d and d.offer then
				offerRemote:FireClient(p, { offerId = d.offer.offerId, closed = true })
			end
			data[p] = { pending = 0, offer = nil, offersMade = 0 }
		end
	end)
	Bus.RunEnded:connect(function()
		for p, d in data do
			if d.offer then
				offerRemote:FireClient(p, { offerId = d.offer.offerId, closed = true })
			end
			d.offer = nil
			d.pending = 0
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		data[player] = nil
	end)
end

function CardService.start()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.25 then
			return
		end
		acc = 0
		local now = os.clock()
		for player, d in data do
			local offer = d.offer
			if offer then
				if now >= offer.expiresAt then
					pickIndex(player, d, rarestIndex(offer.cards))
				end
			elseif d.pending > 0 then
				tryOpen(player) -- was downed or not yet in the run
			end
		end
	end)
end

return CardService
