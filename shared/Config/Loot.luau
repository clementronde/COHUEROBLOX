--!strict
-- Loot tuning (docs/dossier/30-butin-autels.md). Every loot number lives here.

local Loot = {}

Loot.SimHz = 10 -- pickup / auto-open / send rate
Loot.FullSyncEvery = 10 -- ticks between full (repair) snapshots
Loot.InterestRadius = 160 -- studs, loot sent around each player

-- Magnet / pickup
Loot.BaseMagnet = 5 -- studs, plus StatsService Magnet (flat studs)
Loot.MaxMagnet = 60 -- safety clamp

-- XP gems: tier thresholds by value (index = tier)
Loot.GemTiers = { 1, 5, 25, 100 } :: { number }
Loot.GemMergeThreshold = 250
Loot.MaxGems = 400
Loot.GemMergeRadius = 12
Loot.XpByFamily = { Swarm = 1, Jumper = 2, Shooter = 2, Armored = 4 } :: { [string]: number }
Loot.DefaultXp = 1
Loot.EliteXpMult = 5

-- XP sharing (vision 5.2)
Loot.XpShareRadius = 40
Loot.XpShareRatio = 0.5

-- Coins
Loot.CoinPileValue = 5 -- value at which a coin is drawn as a pile
Loot.CoinMergeThreshold = 120
Loot.MaxCoins = 160
Loot.CoinMergeRadius = 12
Loot.CoinsByFamily = {
	Swarm = { chance = 0.08, amount = 1 },
	Jumper = { chance = 0.12, amount = 1 },
	Shooter = { chance = 0.15, amount = 1 },
	Armored = { chance = 0.30, amount = 2 },
} :: { [string]: { chance: number, amount: number } }
Loot.EliteCoins = 6
Loot.CoinTierBonus = 0.25 -- x(1 + bonus * (tier - 1))

-- Pots
Loot.PotsPerStage = 40
Loot.PotBreakRadius = 3.5
Loot.PotTable = {
	{ result = "Coins", weight = 60, min = 2, max = 4 },
	{ result = "Xp", weight = 25, min = 6, max = 6 },
	{ result = "Vacuum", weight = 5, min = 0, max = 0 },
	{ result = "Nothing", weight = 10, min = 0, max = 0 },
} :: { { result: string, weight: number, min: number, max: number } }

-- Chests
Loot.ChestsPerStage = 10 -- paid Normal chests at "Chest" points
Loot.ChestAutoOpenRadius = 3.5
Loot.InteractRange = 8 -- ProximityPrompt MaxActivationDistance
Loot.InteractSlack = 4 -- extra server tolerance for lag
Loot.ChestBaseCost = 20
Loot.ChestStageCostBonus = 0.5 -- x(1 + bonus * (stage - 1))
Loot.ChestCostGrowth = 1.3 -- per chest already bought this stage by this player
Loot.ChestItems = { Normal = 1, Elite = 1, Boss = 2, Shrine = 1 } :: { [string]: number }
Loot.BossChestOffset = 6 -- studs from the player

-- Rarities (Common, Rare, Epic, Legendary)
Loot.RarityOrder = { "Common", "Rare", "Epic", "Legendary" } :: { string }
Loot.ChestRarity = {
	Normal = { 70, 22, 7, 1 },
	Elite = { 45, 35, 16, 4 },
	Boss = { 0, 50, 38, 12 },
	Shrine = { 40, 38, 18, 4 },
} :: { [string]: { number } }
Loot.LuckCap = 50
Loot.LuckPerPoint = { 0, 0.02, 0.03, 0.04 } :: { number } -- per rarity index
Loot.ItemFallbackCoins = { 5, 10, 20, 40 } :: { number }
Loot.RarityColors = {
	Common = Color3.fromRGB(170, 170, 170),
	Rare = Color3.fromRGB(70, 140, 255),
	Epic = Color3.fromRGB(170, 80, 255),
	Legendary = Color3.fromRGB(255, 190, 40),
} :: { [string]: Color3 }

-- Merchant
Loot.MerchantAppearAt = 120 -- seconds into the stage
Loot.MerchantMoveEvery = 150
Loot.MerchantRange = 12
Loot.MerchantItemSlots = 3
Loot.MerchantRarity = "Elite" -- uses Loot.ChestRarity[...] weights
Loot.MerchantPrices = { 18, 35, 65, 120 } :: { number }
Loot.MerchantHealPrice = 12
Loot.MerchantHealFraction = 0.35
Loot.MerchantStagePriceBonus = 0.5
Loot.MerchantName = { fr = "Colporteur Grigri", en = "Trinket Peddler" }

-- Spawn fallback (no StageService points)
Loot.FallbackMinRadius = 40
Loot.FallbackMaxRadius = 260

-- Pure helper shared by server rolls and any UI that shows odds: one table, one formula.
-- Returns weights normalised to sum 1, in Loot.RarityOrder order.
function Loot.rarityWeights(base: { number }, luck: number): { number }
	local l = math.clamp(if luck == luck then luck else 0, 0, Loot.LuckCap)
	local out = table.create(4, 0)
	local sum = 0
	for i = 1, 4 do
		local w = (base[i] or 0) * (1 + Loot.LuckPerPoint[i] * l)
		out[i] = w
		sum += w
	end
	if sum <= 0 then
		out[1] = 1
		return out
	end
	for i = 1, 4 do
		out[i] /= sum
	end
	return out
end

-- Gem tier (1..4) for a value.
function Loot.gemTier(value: number): number
	local tier = 1
	for i, threshold in Loot.GemTiers do
		if value >= threshold then
			tier = i
		end
	end
	return tier
end

return Loot
