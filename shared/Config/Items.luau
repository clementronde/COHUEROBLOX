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
		name = { en = "Magic Shoelace", fr = "Magic Shoelace" },
		desc = { en = "+8% XP", fr = "+8% XP" },
		rarity = "Common",
		stats = { XpGain = 0.08 },
	},
	{
		id = "LuckySock",
		name = { en = "Lucky Sock", fr = "Lucky Sock" },
		desc = { en = "+3 Luck", fr = "+3 Luck" },
		rarity = "Common",
		stats = { Luck = 3 },
	},
	{
		id = "StickyEraser",
		name = { en = "Sticky Eraser", fr = "Sticky Eraser" },
		desc = { en = "10% of hits slow by 40%", fr = "10% of hits slow by 40%" },
		rarity = "Common",
		effect = { kind = "SlowOnHit", chance = 0.10, maxChance = 0.5, mult = 0.6, duration = 1.5 },
	},
	{
		id = "ReinforcedPencilCase",
		name = { en = "Sturdy Pencil Case", fr = "Sturdy Pencil Case" },
		desc = { en = "Blocks 15 damage of a hit every 10 s", fr = "Blocks 15 damage of a hit every 10 s" },
		rarity = "Rare",
		effect = { kind = "Absorb", amount = 15, perStack = 10, cooldown = 10 },
	},
	{
		id = "RecessWhistle",
		name = { en = "Recess Whistle", fr = "Recess Whistle" },
		desc = { en = "Every 20 s, pushes nearby enemies away", fr = "Every 20 s, pushes nearby enemies away" },
		rarity = "Rare",
		effect = { kind = "PulseKnockback", period = 20, perStack = -2, minPeriod = 10, radius = 14, force = 18 },
	},
	{
		id = "Wrench",
		name = { en = "Wrench", fr = "Wrench" },
		desc = { en = "Shrines: +5% speed, +8% reward", fr = "Shrines: +5% speed, +8% reward" },
		rarity = "Rare",
		-- Read by ShrineService through StatsService.getBuild(player).items
		effect = { kind = "Shrine", speed = 0.05, reward = 0.08 },
	},
	{
		id = "BlankieGhost",
		name = { en = "Blankie Ghost", fr = "Blankie Ghost" },
		desc = { en = "Every 50 studs walked, a tiny ghost attacks", fr = "Every 50 studs walked, a tiny ghost attacks" },
		rarity = "Legendary",
		effect = { kind = "DistanceGhost", distance = 50, damage = 25, speed = 40, life = 2.5, radius = 1.5 },
	},
	{
		id = "FridgeMagnet",
		name = { en = "Fridge Magnet", fr = "Fridge Magnet" },
		desc = { en = "Every 45 s, pulls in all XP", fr = "Every 45 s, pulls in all XP" },
		rarity = "Epic",
		effect = { kind = "PulseMagnet", period = 45, perStack = -5, minPeriod = 25, magnet = 400, duration = 1.5 },
	},
	{
		id = "OldBattery",
		name = { en = "Old Battery", fr = "Old Battery" },
		desc = { en = "-10% max HP, +15% damage", fr = "-10% max HP, +15% damage" },
		rarity = "Rare",
		stats = { Damage = 0.15 },
		mult = { MaxHp = 0.9 },
	},
	{
		id = "HunterGlasses",
		name = { en = "Hunter Glasses", fr = "Hunter Glasses" },
		desc = { en = "+15% damage to elites and bosses", fr = "+15% damage to elites and bosses" },
		rarity = "Rare",
		effect = { kind = "EliteDamage", bonus = 0.15 },
	},

	-- New (school / household theme)
	{
		id = "ChalkStick",
		name = { en = "Magic Chalk", fr = "Magic Chalk" },
		desc = { en = "+5% damage", fr = "+5% damage" },
		rarity = "Common",
		stats = { Damage = 0.05 },
	},
	{
		id = "Ruler",
		name = { en = "Long Ruler", fr = "Long Ruler" },
		desc = { en = "+6% size", fr = "+6% size" },
		rarity = "Common",
		stats = { Size = 0.06 },
	},
	{
		id = "GymStopwatch",
		name = { en = "Gym Stopwatch", fr = "Gym Stopwatch" },
		desc = { en = "+6% attack speed", fr = "+6% attack speed" },
		rarity = "Common",
		stats = { AttackSpeed = 0.06 },
	},
	{
		id = "GlueStick",
		name = { en = "Glue Stick", fr = "Glue Stick" },
		desc = { en = "+8% duration", fr = "+8% duration" },
		rarity = "Common",
		stats = { Duration = 0.08 },
	},
	{
		id = "VelcroSneakers",
		name = { en = "Velcro Sneakers", fr = "Velcro Sneakers" },
		desc = { en = "+6% move speed", fr = "+6% move speed" },
		rarity = "Common",
		stats = { MoveSpeed = 0.06 },
	},
	{
		id = "LunchBox",
		name = { en = "Lunch Box", fr = "Lunch Box" },
		desc = { en = "+15 max HP", fr = "+15 max HP" },
		rarity = "Common",
		stats = { MaxHp = 15 },
	},
	{
		id = "DinoBandage",
		name = { en = "Dino Bandage", fr = "Dino Bandage" },
		desc = { en = "+0.4 HP/s", fr = "+0.4 HP/s" },
		rarity = "Common",
		stats = { Regen = 0.4 },
	},
	{
		id = "ComicBook",
		name = { en = "Dog-eared Comic", fr = "Dog-eared Comic" },
		desc = { en = "+4% crit chance", fr = "+4% crit chance" },
		rarity = "Common",
		stats = { CritChance = 0.04 },
	},
	{
		id = "BentPaperclip",
		name = { en = "Bent Paperclip", fr = "Bent Paperclip" },
		desc = { en = "+1 bounce", fr = "+1 bounce" },
		rarity = "Common",
		stats = { Bounces = 1 },
	},
	{
		id = "HomeworkFolder",
		name = { en = "Homework Folder", fr = "Homework Folder" },
		desc = { en = "+2 armor", fr = "+2 armor" },
		rarity = "Common",
		stats = { Armor = 2 },
	},
	{
		id = "SandTimer",
		name = { en = "Toothbrush Timer", fr = "Toothbrush Timer" },
		desc = { en = "+4% cooldown", fr = "+4% cooldown" },
		rarity = "Common",
		stats = { Cooldown = 0.04 },
	},
	{
		id = "StickyNote",
		name = { en = "Sticky Note", fr = "Sticky Note" },
		desc = { en = "+4 magnet", fr = "+4 magnet" },
		rarity = "Common",
		stats = { Magnet = 4 },
	},
	{
		id = "StarSticker",
		name = { en = "Star Sticker", fr = "Star Sticker" },
		desc = { en = "+3% damage, +3% XP", fr = "+3% damage, +3% XP" },
		rarity = "Common",
		stats = { Damage = 0.03, XpGain = 0.03 },
	},
	{
		id = "GeometryCompass",
		name = { en = "Pointy Compass", fr = "Pointy Compass" },
		desc = { en = "+3% crit chance, +15% crit damage", fr = "+3% crit chance, +15% crit damage" },
		rarity = "Rare",
		stats = { CritChance = 0.03, CritDamage = 0.15 },
	},
	{
		id = "BubbleWrap",
		name = { en = "Bubble Wrap", fr = "Bubble Wrap" },
		desc = { en = "+4% dodge", fr = "+4% dodge" },
		rarity = "Rare",
		stats = { Dodge = 0.04 },
	},
	{
		id = "FluffySlippers",
		name = { en = "Fluffy Slippers", fr = "Fluffy Slippers" },
		desc = { en = "+8% move speed, +2% dodge", fr = "+8% move speed, +2% dodge" },
		rarity = "Rare",
		stats = { MoveSpeed = 0.08, Dodge = 0.02 },
	},
	{
		id = "HotChocolate",
		name = { en = "Hot Chocolate", fr = "Hot Chocolate" },
		desc = { en = "Heals 20 HP on level up", fr = "Heals 20 HP on level up" },
		rarity = "Rare",
		effect = { kind = "HealOnLevel", amount = 20 },
	},
	{
		id = "LuckyCoin",
		name = { en = "Lucky Coin", fr = "Lucky Coin" },
		desc = { en = "3% of kills drop a coin", fr = "3% of kills drop a coin" },
		rarity = "Rare",
		effect = { kind = "CoinOnKill", chance = 0.03, coins = 1 },
	},
	{
		id = "Thumbtack",
		name = { en = "Thumbtack", fr = "Thumbtack" },
		desc = { en = "+10% thorns", fr = "+10% thorns" },
		rarity = "Rare",
		stats = { Thorns = 0.10 },
	},
	{
		id = "SolarCalculator",
		name = { en = "Solar Calculator", fr = "Solar Calculator" },
		desc = { en = "+12% XP, +2 Luck", fr = "+12% XP, +2 Luck" },
		rarity = "Rare",
		stats = { XpGain = 0.12, Luck = 2 },
	},
	{
		id = "WaterBottle",
		name = { en = "Water Bottle", fr = "Water Bottle" },
		desc = { en = "+1 HP/s", fr = "+1 HP/s" },
		rarity = "Rare",
		stats = { Regen = 1 },
	},
	{
		id = "RoundScissors",
		name = { en = "Safety Scissors", fr = "Safety Scissors" },
		desc = { en = "8% of hits deal double damage", fr = "8% of hits deal double damage" },
		rarity = "Rare",
		effect = { kind = "DoubleHit", chance = 0.08, maxChance = 0.5 },
	},
	{
		id = "TinyCar",
		name = { en = "Tiny Car", fr = "Tiny Car" },
		desc = { en = "+10% damage while moving", fr = "+10% damage while moving" },
		rarity = "Rare",
		effect = { kind = "MovingDamage", bonus = 0.10 },
	},
	{
		id = "CozyPillow",
		name = { en = "Cozy Pillow", fr = "Cozy Pillow" },
		desc = { en = "+20% damage while standing still", fr = "+20% damage while standing still" },
		rarity = "Rare",
		effect = { kind = "StillDamage", bonus = 0.20 },
	},
	{
		id = "ColoringPencils",
		name = { en = "Coloring Pencils", fr = "Coloring Pencils" },
		desc = { en = "+1 amount", fr = "+1 amount" },
		rarity = "Epic",
		stats = { Amount = 1 },
	},
	{
		id = "Megaphone",
		name = { en = "Megaphone", fr = "Megaphone" },
		desc = { en = "Every 12 s, stuns nearby enemies", fr = "Every 12 s, stuns nearby enemies" },
		rarity = "Epic",
		effect = { kind = "PulseStun", period = 12, perStack = -1, minPeriod = 6, radius = 10, duration = 1 },
	},
	{
		id = "Flashlight",
		name = { en = "Flashlight", fr = "Flashlight" },
		desc = { en = "Crits stun for 0.4 s", fr = "Crits stun for 0.4 s" },
		rarity = "Epic",
		effect = { kind = "StunOnCrit", duration = 0.4 },
	},
	{
		id = "RainbowLollipop",
		name = { en = "Rainbow Lollipop", fr = "Rainbow Lollipop" },
		desc = { en = "Each kill heals 1 HP", fr = "Each kill heals 1 HP" },
		rarity = "Epic",
		effect = { kind = "HealOnKill", amount = 1, maxPerSecond = 5 },
	},
	{
		id = "ChampionBackpack",
		name = { en = "Champion Backpack", fr = "Champion Backpack" },
		desc = { en = "+15% size, +15% duration, +10% damage", fr = "+15% size, +15% duration, +10% damage" },
		rarity = "Legendary",
		stats = { Size = 0.15, Duration = 0.15, Damage = 0.10 },
	},
	{
		id = "GoldStar",
		name = { en = "Gold Star", fr = "Gold Star" },
		desc = { en = "+1 amount, +10% damage", fr = "+1 amount, +10% damage" },
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
