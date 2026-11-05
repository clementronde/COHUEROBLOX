--!strict
-- Cartes de niveau et courbe d'XP (dossier 10, sections 3 et 4). Décisions v2 section 4 :
-- 3 choix, rareté visible, Bannir / Passer / Relancer limités par run. Les textes des cartes sont
-- en anglais. Depuis le 5 nov. : pause globale (Run.LevelUpPause). OfferSeconds et SlowMultiplier
-- ne servent plus qu'à l'ancien mode sans pause (Run.LevelUpPause.Enabled = false).

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
		NewWeapon = { en = "New weapon", fr = "New weapon" },
		NewGrimoire = { en = "New Rune", fr = "New Rune" },
		Level = { en = "Lv", fr = "Lv" },
		Fusion = { en = "FUSION", fr = "FUSION" },
		Heal = { en = "Snack", fr = "Snack" },
		HealDesc = { en = "Heals 30% of max HP", fr = "Heals 30% of max HP" },
		Coins = { en = "Piggy bank", fr = "Piggy bank" },
		CoinsDesc = { en = "+20 coins", fr = "+20 coins" },
		Damage = { en = "damage", fr = "damage" },
	},

	-- Mots affichés pour les deltas de niveau des armes (clé de stat -> texte joueur).
	-- Une clé absente n'est pas affichée (stats internes comme volleyDelay).
	WeaponStatWords = {
		damage = "damage",
		cooldown = "cooldown",
		radius = "area",
		popRadius = "blast area",
		amount = "projectile",
		speed = "speed",
		life = "range",
		pierce = "pierce",
		range = "range",
		duration = "duration",
		interval = "tick rate",
		angle = "° arc",
		bounces = "bounce",
		critChance = "crit chance",
		critDamage = "crit damage",
		knockback = "knockback",
		statusDps = "burn",
		statusDuration = "s freeze",
		statusMult = "slow",
		turrets = "turret",
		darts = "bolt",
		orbitRadius = "orbit",
		spin = "spin speed",
		volleys = "volley",
	} :: { [string]: string },

	-- Langue de Card.title / Card.desc (Types.Card porte des chaînes simples). v2 : anglais seul.
	Locale = "en",
}

function Cards.xpToNext(level: number): number
	local x = Cards.Xp
	return math.floor(x.Base + x.Linear * level + x.Quad * level * level)
end

return Cards
