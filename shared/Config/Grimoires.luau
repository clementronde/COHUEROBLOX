--!strict
-- Grimoires (tomes), base stats and caps (dossier 10, sections 1 and 6).
-- `perLevel` stats are linear (value * level); `table` stats give the cumulative value per level.

export type GrimoireDef = {
	id: string,
	name: { fr: string, en: string },
	maxLevel: number,
	perLevel: { [string]: number },
	byLevel: { [string]: { number } }?,
	unlockGated: boolean?, -- needs ProgressionService.isUnlocked; locked when ProgressionService is missing
}

local Grimoires = {}

Grimoires.Order = {
	"Degats",
	"VitesseAttaque",
	"Quantite",
	"Taille",
	"Duree",
	"Cooldown",
	"Critique",
	"Chance",
	"Savoir",
	"Aimant",
	"Vitalite",
	"Rempart",
	"Agilite",
	"Interdit",
} :: { string }

Grimoires.Defs = {
	Degats = {
		id = "Degats",
		name = { fr = "Grimoire des Dégâts", en = "Tome of Damage" },
		maxLevel = 8,
		perLevel = { Damage = 0.08 },
	},
	VitesseAttaque = {
		id = "VitesseAttaque",
		name = { fr = "Grimoire de Vitesse d'attaque", en = "Tome of Attack Speed" },
		maxLevel = 8,
		perLevel = { AttackSpeed = 0.07 },
	},
	Quantite = {
		id = "Quantite",
		name = { fr = "Grimoire de Quantité", en = "Tome of Amount" },
		maxLevel = 8,
		perLevel = {},
		byLevel = {
			Amount = { 1, 1, 2, 2, 3, 3, 4, 4 },
			Damage = { 0, 0.04, 0.04, 0.08, 0.08, 0.12, 0.12, 0.16 },
		},
	},
	Taille = {
		id = "Taille",
		name = { fr = "Grimoire de Taille", en = "Tome of Size" },
		maxLevel = 8,
		perLevel = { Size = 0.08 },
	},
	Duree = {
		id = "Duree",
		name = { fr = "Grimoire de Durée", en = "Tome of Duration" },
		maxLevel = 8,
		perLevel = { Duration = 0.10 },
	},
	Cooldown = {
		id = "Cooldown",
		name = { fr = "Grimoire de Recharge", en = "Tome of Cooldown" },
		maxLevel = 8,
		perLevel = { Cooldown = 0.04 },
	},
	Critique = {
		id = "Critique",
		name = { fr = "Grimoire Critique", en = "Tome of Criticals" },
		maxLevel = 8,
		perLevel = { CritChance = 0.04, CritDamage = 0.10 },
	},
	Chance = {
		id = "Chance",
		name = { fr = "Grimoire de Chance", en = "Tome of Luck" },
		maxLevel = 8,
		perLevel = { Luck = 3 },
	},
	Savoir = {
		id = "Savoir",
		name = { fr = "Grimoire du Savoir", en = "Tome of Knowledge" },
		maxLevel = 8,
		perLevel = { XpGain = 0.10 },
	},
	Aimant = {
		id = "Aimant",
		name = { fr = "Grimoire Aimant", en = "Tome of Magnet" },
		maxLevel = 8,
		perLevel = { Magnet = 3 },
	},
	Vitalite = {
		id = "Vitalite",
		name = { fr = "Grimoire de Vitalité", en = "Tome of Vitality" },
		maxLevel = 8,
		perLevel = { MaxHp = 15, Regen = 0.1 },
	},
	Rempart = {
		id = "Rempart",
		name = { fr = "Grimoire Rempart", en = "Tome of Bulwark" },
		maxLevel = 8,
		perLevel = { Armor = 3 },
	},
	Agilite = {
		id = "Agilite",
		name = { fr = "Grimoire d'Agilité", en = "Tome of Agility" },
		maxLevel = 8,
		perLevel = { MoveSpeed = 0.04, Dodge = 0.02 },
	},
	Interdit = {
		id = "Interdit",
		name = { fr = "Grimoire Interdit", en = "Forbidden Tome" },
		maxLevel = 5,
		perLevel = { Difficulty = 0.10, LootBonus = 0.12, XpGain = 0.05, Damage = 0.05 },
		unlockGated = true,
	},
} :: { [string]: GrimoireDef }

-- Final StatBlock starts here (Types.StatName). Every stat must have an entry.
Grimoires.BaseStats = {
	Damage = 0,
	AttackSpeed = 0,
	Amount = 0,
	Size = 0,
	Duration = 0,
	Cooldown = 0,
	CritChance = 0.05,
	CritDamage = 0,
	Luck = 0,
	XpGain = 0,
	Magnet = 0,
	MaxHp = 100,
	Armor = 0,
	Regen = 0,
	MoveSpeed = 0,
	Dodge = 0,
	Thorns = 0,
	Bounces = 0,
	Difficulty = 0,
	LootBonus = 0,
} :: { [string]: number }

-- Upper caps applied last (lower bounds: none, except MaxHp >= 1).
Grimoires.StatCaps = {
	AttackSpeed = 3,
	Amount = 10,
	Size = 3,
	Duration = 3,
	Cooldown = 0.6,
	CritChance = 1,
	Luck = 999,
	MoveSpeed = 1,
	Dodge = 0.6,
	Thorns = 1,
	Bounces = 10,
} :: { [string]: number }

-- Short labels used to write card descriptions.
Grimoires.StatLabel = {
	Damage = { fr = "dégâts", en = "damage", pct = true },
	AttackSpeed = { fr = "vitesse d'attaque", en = "attack speed", pct = true },
	Amount = { fr = "quantité", en = "amount", pct = false },
	Size = { fr = "taille", en = "size", pct = true },
	Duration = { fr = "durée", en = "duration", pct = true },
	Cooldown = { fr = "recharge", en = "cooldown", pct = true },
	CritChance = { fr = "chance de critique", en = "crit chance", pct = true },
	CritDamage = { fr = "dégâts critiques", en = "crit damage", pct = true },
	Luck = { fr = "chance", en = "luck", pct = false },
	XpGain = { fr = "XP", en = "XP", pct = true },
	Magnet = { fr = "aimant", en = "magnet", pct = false },
	MaxHp = { fr = "PV max", en = "max HP", pct = false },
	Armor = { fr = "armure", en = "armor", pct = false },
	Regen = { fr = "PV/s", en = "HP/s", pct = false },
	MoveSpeed = { fr = "vitesse", en = "move speed", pct = true },
	Dodge = { fr = "esquive", en = "dodge", pct = true },
	Thorns = { fr = "épines", en = "thorns", pct = true },
	Bounces = { fr = "rebonds", en = "bounces", pct = false },
	Difficulty = { fr = "difficulté", en = "difficulty", pct = true },
	LootBonus = { fr = "butin", en = "loot", pct = true },
} :: { [string]: { fr: string, en: string, pct: boolean } }

-- Cumulative value of one stat for a grimoire at a level (0 if level < 1).
function Grimoires.valueAt(def: GrimoireDef, stat: string, level: number): number
	if level < 1 then
		return 0
	end
	local lvl = math.min(level, def.maxLevel)
	local v = (def.perLevel[stat] or 0) * lvl
	local by = def.byLevel and def.byLevel[stat]
	if by then
		v += by[lvl] or 0
	end
	return v
end

return Grimoires
