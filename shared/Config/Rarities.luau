--!strict
-- Rarity ladder for cards and items (dossier 10, section 4.1).
-- Luck model: normalised weighted table, effective weight = weight * (1 + min(Luck, LuckCap) * luckScale).
-- (vault: Genre Playbook - RNG and Collection Games, "Luck")

local Rarities = {
	Order = { "Common", "Rare", "Epic", "Legendary" } :: { string },

	Weight = {
		Common = 60,
		Rare = 26,
		Epic = 10,
		Legendary = 4,
	} :: { [string]: number },

	-- Extra weight per point of Luck (Common is not boosted, so it shrinks in share).
	LuckScale = {
		Common = 0,
		Rare = 0.02,
		Epic = 0.035,
		Legendary = 0.05,
	} :: { [string]: number },

	LuckCap = 100,

	Color = {
		Common = Color3.fromRGB(170, 170, 170),
		Rare = Color3.fromRGB(70, 140, 255),
		Epic = Color3.fromRGB(170, 80, 230),
		Legendary = Color3.fromRGB(255, 195, 40),
	} :: { [string]: Color3 },

	Name = {
		Common = { fr = "Commun", en = "Common" },
		Rare = { fr = "Rare", en = "Rare" },
		Epic = { fr = "Épique", en = "Epic" },
		Legendary = { fr = "Légendaire", en = "Legendary" },
	} :: { [string]: { fr: string, en: string } },
}

-- 1 = Common .. 4 = Legendary
function Rarities.rank(rarity: string): number
	return table.find(Rarities.Order, rarity) or 1
end

-- Rolls a rarity. `minRank` forces at least that rank (Astrel guarantee). Pure: pass your Random.
function Rarities.roll(luck: number, rng: Random, minRank: number?): string
	local l = math.clamp(if luck == luck then luck else 0, 0, Rarities.LuckCap)
	local lo = minRank or 1
	local total = 0
	for i = lo, #Rarities.Order do
		local r = Rarities.Order[i]
		total += Rarities.Weight[r] * (1 + l * Rarities.LuckScale[r])
	end
	local pick = rng:NextNumber() * total
	for i = lo, #Rarities.Order do
		local r = Rarities.Order[i]
		pick -= Rarities.Weight[r] * (1 + l * Rarities.LuckScale[r])
		if pick <= 0 then
			return r
		end
	end
	return Rarities.Order[#Rarities.Order]
end

return Rarities
