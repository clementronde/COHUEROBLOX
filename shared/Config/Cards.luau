--!strict
-- Level-up cards and XP curve (dossier 10, sections 3 and 4).

local Cards = {
	OfferSize = 3,
	OfferSeconds = 8,
	SlowMultiplier = 0.5,
	CompanionChance = 0.25, -- per card slot (about 1 card in 4)

	-- Draw weights by candidate kind
	PoolWeight = {
		WeaponUp = 1.2,
		NewWeapon = 1.0,
		GrimoireUp = 1.0,
		NewGrimoire = 0.9,
		Fusion = 3.0,
	} :: { [string]: number },

	-- Levels gained by rarity
	WeaponLevels = { Common = 1, Rare = 1, Epic = 2, Legendary = 2 } :: { [string]: number },
	WeaponDamageBonus = { Common = 0, Rare = 0.10, Epic = 0.10, Legendary = 0.25 } :: { [string]: number },
	GrimoireLevels = { Common = 1, Rare = 2, Epic = 3, Legendary = 4 } :: { [string]: number },

	-- Fallback cards when nothing else can be offered
	HealFraction = 0.30, -- of MaxHp
	FallbackCoins = 20, -- x (1 + LootBonus)

	-- Draw controls (fallback when ProgressionService is missing)
	DefaultMeta = { weaponSlots = 4, grimoireSlots = 4, banish = 3, skip = 3, reroll = 3 },
	MaxSlots = 6,

	-- CardChoice remote: calls per second per player
	ChoiceRate = 5,

	Xp = {
		MaxLevel = 99,
		-- xp to go from level L to L+1 = floor(Base + Linear * L + Quad * L^2)
		Base = 6,
		Linear = 4,
		Quad = 0.35,
		-- LootService already applies XpGain and the 50 % / 40 studs coop share before calling
		-- StatsService.addXp, so addXp takes the amount as final.
	},

	Text = {
		NewWeapon = { fr = "Nouvelle arme", en = "New weapon" },
		NewGrimoire = { fr = "Nouveau grimoire", en = "New tome" },
		Fusion = { fr = "FUSION", en = "FUSION" },
		Heal = { fr = "Goûter", en = "Snack" },
		HealDesc = { fr = "Soigne 30 % des PV max", en = "Heals 30% of max HP" },
		Coins = { fr = "Tirelire", en = "Piggy bank" },
		CoinsDesc = { fr = "+20 pièces", en = "+20 coins" },
	},

	-- Language used for Card.title / Card.desc (Types.Card has plain strings).
	Locale = "fr",
}

function Cards.xpToNext(level: number): number
	local x = Cards.Xp
	return math.floor(x.Base + x.Linear * level + x.Quad * level * level)
end

return Cards
