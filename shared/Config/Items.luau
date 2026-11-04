--!strict
-- The 40 launch items (dossier 10, section 7). Every item stacks.
-- `stats`: added once per stack to the StatBlock. `mult`: multiplied once per stack, after sums.
-- `effect`: triggered behaviour, read by WeaponService (on hit / on kill) or PassiveService (timers).

export type ItemDef = {
	id: string,
	name: { fr: string, en: string },
	desc: { fr: string, en: string },
	rarity: string,
	stats: { [string]: number }?,
	mult: { [string]: number }?,
	effect: { [string]: any }?,
}

local Items = {}

local defs: { ItemDef } = {
	-- From the design doc (8.3)
	{
		id = "MagicShoelace",
		name = { fr = "Lacet magique", en = "Magic Shoelace" },
		desc = { fr = "+8 % XP", en = "+8% XP" },
		rarity = "Common",
		stats = { XpGain = 0.08 },
	},
	{
		id = "LuckySock",
		name = { fr = "Chaussette porte-bonheur", en = "Lucky Sock" },
		desc = { fr = "+3 Chance", en = "+3 Luck" },
		rarity = "Common",
		stats = { Luck = 3 },
	},
	{
		id = "StickyEraser",
		name = { fr = "Gomme collante", en = "Sticky Eraser" },
		desc = { fr = "10 % des coups ralentissent de 40 %", en = "10% of hits slow by 40%" },
		rarity = "Common",
		effect = { kind = "SlowOnHit", chance = 0.10, maxChance = 0.5, mult = 0.6, duration = 1.5 },
	},
	{
		id = "ReinforcedPencilCase",
		name = { fr = "Trousse renforcée", en = "Sturdy Pencil Case" },
		desc = { fr = "Annule 15 dégâts d'un coup toutes les 10 s", en = "Blocks 15 damage of a hit every 10 s" },
		rarity = "Rare",
		effect = { kind = "Absorb", amount = 15, perStack = 10, cooldown = 10 },
	},
	{
		id = "RecessWhistle",
		name = { fr = "Sifflet de récré", en = "Recess Whistle" },
		desc = { fr = "Toutes les 20 s, repousse les ennemis proches", en = "Every 20 s, pushes nearby enemies away" },
		rarity = "Rare",
		effect = { kind = "PulseKnockback", period = 20, perStack = -2, minPeriod = 10, radius = 14, force = 18 },
	},
	{
		id = "Wrench",
		name = { fr = "Clé à molette", en = "Wrench" },
		desc = { fr = "Autels : +5 % vitesse, +8 % récompense", en = "Shrines: +5% speed, +8% reward" },
		rarity = "Rare",
		-- Read by ShrineService through StatsService.getBuild(player).items
		effect = { kind = "Shrine", speed = 0.05, reward = 0.08 },
	},
	{
		id = "BlankieGhost",
		name = { fr = "Fantôme de doudou", en = "Blankie Ghost" },
		desc = { fr = "Tous les 50 studs parcourus, un mini-fantôme attaque", en = "Every 50 studs walked, a tiny ghost attacks" },
		rarity = "Legendary",
		effect = { kind = "DistanceGhost", distance = 50, damage = 25, speed = 40, life = 2.5, radius = 1.5 },
	},
	{
		id = "FridgeMagnet",
		name = { fr = "Aimant de frigo", en = "Fridge Magnet" },
		desc = { fr = "Toutes les 45 s, aspire toute l'XP", en = "Every 45 s, pulls in all XP" },
		rarity = "Epic",
		effect = { kind = "PulseMagnet", period = 45, perStack = -5, minPeriod = 25, magnet = 400, duration = 1.5 },
	},
	{
		id = "OldBattery",
		name = { fr = "Pile usée", en = "Old Battery" },
		desc = { fr = "-10 % PV max, +15 % dégâts", en = "-10% max HP, +15% damage" },
		rarity = "Rare",
		stats = { Damage = 0.15 },
		mult = { MaxHp = 0.9 },
	},
	{
		id = "HunterGlasses",
		name = { fr = "Lunettes de chasseur", en = "Hunter Glasses" },
		desc = { fr = "+15 % dégâts contre élites et boss", en = "+15% damage to elites and bosses" },
		rarity = "Rare",
		effect = { kind = "EliteDamage", bonus = 0.15 },
	},

	-- New (school / household theme)
	{
		id = "ChalkStick",
		name = { fr = "Craie magique", en = "Magic Chalk" },
		desc = { fr = "+5 % dégâts", en = "+5% damage" },
		rarity = "Common",
		stats = { Damage = 0.05 },
	},
	{
		id = "Ruler",
		name = { fr = "Règle graduée", en = "Long Ruler" },
		desc = { fr = "+6 % taille", en = "+6% size" },
		rarity = "Common",
		stats = { Size = 0.06 },
	},
	{
		id = "GymStopwatch",
		name = { fr = "Chronomètre de gym", en = "Gym Stopwatch" },
		desc = { fr = "+6 % vitesse d'attaque", en = "+6% attack speed" },
		rarity = "Common",
		stats = { AttackSpeed = 0.06 },
	},
	{
		id = "GlueStick",
		name = { fr = "Bâton de colle", en = "Glue Stick" },
		desc = { fr = "+8 % durée", en = "+8% duration" },
		rarity = "Common",
		stats = { Duration = 0.08 },
	},
	{
		id = "VelcroSneakers",
		name = { fr = "Baskets à scratch", en = "Velcro Sneakers" },
		desc = { fr = "+6 % vitesse", en = "+6% move speed" },
		rarity = "Common",
		stats = { MoveSpeed = 0.06 },
	},
	{
		id = "LunchBox",
		name = { fr = "Boîte à goûter", en = "Lunch Box" },
		desc = { fr = "+15 PV max", en = "+15 max HP" },
		rarity = "Common",
		stats = { MaxHp = 15 },
	},
	{
		id = "DinoBandage",
		name = { fr = "Pansement dino", en = "Dino Bandage" },
		desc = { fr = "+0,4 PV/s", en = "+0.4 HP/s" },
		rarity = "Common",
		stats = { Regen = 0.4 },
	},
	{
		id = "ComicBook",
		name = { fr = "BD cornée", en = "Dog-eared Comic" },
		desc = { fr = "+4 % critique", en = "+4% crit chance" },
		rarity = "Common",
		stats = { CritChance = 0.04 },
	},
	{
		id = "BentPaperclip",
		name = { fr = "Trombone tordu", en = "Bent Paperclip" },
		desc = { fr = "+1 rebond", en = "+1 bounce" },
		rarity = "Common",
		stats = { Bounces = 1 },
	},
	{
		id = "HomeworkFolder",
		name = { fr = "Classeur de devoirs", en = "Homework Folder" },
		desc = { fr = "+2 armure", en = "+2 armor" },
		rarity = "Common",
		stats = { Armor = 2 },
	},
	{
		id = "SandTimer",
		name = { fr = "Sablier de brosse à dents", en = "Toothbrush Timer" },
		desc = { fr = "+4 % recharge", en = "+4% cooldown" },
		rarity = "Common",
		stats = { Cooldown = 0.04 },
	},
	{
		id = "StickyNote",
		name = { fr = "Pense-bête", en = "Sticky Note" },
		desc = { fr = "+4 aimant", en = "+4 magnet" },
		rarity = "Common",
		stats = { Magnet = 4 },
	},
	{
		id = "StarSticker",
		name = { fr = "Autocollant étoile", en = "Star Sticker" },
		desc = { fr = "+3 % dégâts, +3 % XP", en = "+3% damage, +3% XP" },
		rarity = "Common",
		stats = { Damage = 0.03, XpGain = 0.03 },
	},
	{
		id = "GeometryCompass",
		name = { fr = "Compas pointu", en = "Pointy Compass" },
		desc = { fr = "+3 % critique, +15 % dégâts critiques", en = "+3% crit chance, +15% crit damage" },
		rarity = "Rare",
		stats = { CritChance = 0.03, CritDamage = 0.15 },
	},
	{
		id = "BubbleWrap",
		name = { fr = "Papier bulle", en = "Bubble Wrap" },
		desc = { fr = "+4 % esquive", en = "+4% dodge" },
		rarity = "Rare",
		stats = { Dodge = 0.04 },
	},
	{
		id = "FluffySlippers",
		name = { fr = "Chaussons moelleux", en = "Fluffy Slippers" },
		desc = { fr = "+8 % vitesse, +2 % esquive", en = "+8% move speed, +2% dodge" },
		rarity = "Rare",
		stats = { MoveSpeed = 0.08, Dodge = 0.02 },
	},
	{
		id = "HotChocolate",
		name = { fr = "Chocolat chaud", en = "Hot Chocolate" },
		desc = { fr = "Soigne 20 PV à chaque niveau", en = "Heals 20 HP on level up" },
		rarity = "Rare",
		effect = { kind = "HealOnLevel", amount = 20 },
	},
	{
		id = "LuckyCoin",
		name = { fr = "Pièce porte-bonheur", en = "Lucky Coin" },
		desc = { fr = "3 % des ennemis tués lâchent une pièce", en = "3% of kills drop a coin" },
		rarity = "Rare",
		effect = { kind = "CoinOnKill", chance = 0.03, coins = 1 },
	},
	{
		id = "Thumbtack",
		name = { fr = "Punaise", en = "Thumbtack" },
		desc = { fr = "+10 % épines", en = "+10% thorns" },
		rarity = "Rare",
		stats = { Thorns = 0.10 },
	},
	{
		id = "SolarCalculator",
		name = { fr = "Calculatrice solaire", en = "Solar Calculator" },
		desc = { fr = "+12 % XP, +2 Chance", en = "+12% XP, +2 Luck" },
		rarity = "Rare",
		stats = { XpGain = 0.12, Luck = 2 },
	},
	{
		id = "WaterBottle",
		name = { fr = "Gourde", en = "Water Bottle" },
		desc = { fr = "+1 PV/s", en = "+1 HP/s" },
		rarity = "Rare",
		stats = { Regen = 1 },
	},
	{
		id = "RoundScissors",
		name = { fr = "Ciseaux à bouts ronds", en = "Safety Scissors" },
		desc = { fr = "8 % des coups font double dégâts", en = "8% of hits deal double damage" },
		rarity = "Rare",
		effect = { kind = "DoubleHit", chance = 0.08, maxChance = 0.5 },
	},
	{
		id = "TinyCar",
		name = { fr = "Petite voiture", en = "Tiny Car" },
		desc = { fr = "+10 % dégâts en mouvement", en = "+10% damage while moving" },
		rarity = "Rare",
		effect = { kind = "MovingDamage", bonus = 0.10 },
	},
	{
		id = "CozyPillow",
		name = { fr = "Oreiller douillet", en = "Cozy Pillow" },
		desc = { fr = "+20 % dégâts à l'arrêt", en = "+20% damage while standing still" },
		rarity = "Rare",
		effect = { kind = "StillDamage", bonus = 0.20 },
	},
	{
		id = "ColoringPencils",
		name = { fr = "Crayons de couleur", en = "Coloring Pencils" },
		desc = { fr = "+1 quantité", en = "+1 amount" },
		rarity = "Epic",
		stats = { Amount = 1 },
	},
	{
		id = "Megaphone",
		name = { fr = "Mégaphone", en = "Megaphone" },
		desc = { fr = "Toutes les 12 s, étourdit les ennemis proches", en = "Every 12 s, stuns nearby enemies" },
		rarity = "Epic",
		effect = { kind = "PulseStun", period = 12, perStack = -1, minPeriod = 6, radius = 10, duration = 1 },
	},
	{
		id = "Flashlight",
		name = { fr = "Lampe de poche", en = "Flashlight" },
		desc = { fr = "Les critiques étourdissent 0,4 s", en = "Crits stun for 0.4 s" },
		rarity = "Epic",
		effect = { kind = "StunOnCrit", duration = 0.4 },
	},
	{
		id = "RainbowLollipop",
		name = { fr = "Sucette arc-en-ciel", en = "Rainbow Lollipop" },
		desc = { fr = "Chaque ennemi tué soigne 1 PV", en = "Each kill heals 1 HP" },
		rarity = "Epic",
		effect = { kind = "HealOnKill", amount = 1, maxPerSecond = 5 },
	},
	{
		id = "ChampionBackpack",
		name = { fr = "Cartable de champion", en = "Champion Backpack" },
		desc = { fr = "+15 % taille, +15 % durée, +10 % dégâts", en = "+15% size, +15% duration, +10% damage" },
		rarity = "Legendary",
		stats = { Size = 0.15, Duration = 0.15, Damage = 0.10 },
	},
	{
		id = "GoldStar",
		name = { fr = "Bon point doré", en = "Gold Star" },
		desc = { fr = "+1 quantité, +10 % dégâts", en = "+1 amount, +10% damage" },
		rarity = "Legendary",
		stats = { Amount = 1, Damage = 0.10 },
	},
}

Items.List = defs
Items.Defs = {} :: { [string]: ItemDef }
for _, def in defs do
	assert(Items.Defs[def.id] == nil, `duplicate item {def.id}`)
	Items.Defs[def.id] = def
end

return Items
