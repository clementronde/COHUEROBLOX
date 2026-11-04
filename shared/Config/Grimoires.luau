--!strict
-- Les 14 Runes (les « grimoires » de la v1, renommés : docs/dossier/01-decisions-v2.md section 4),
-- les stats de base et leurs plafonds (dossier 10, sections 1 et 6).
-- Le module garde son nom interne `Config/Grimoires` (et les champs `grimoires` du Build) pour ne
-- pas casser les autres domaines ; « Rune » est le nom affiché au joueur.
-- 4 emplacements de Rune par run (jusqu'à 6 avec la méta, lue chez ProgressionService).
-- `perLevel` : valeur linéaire (valeur x niveau) ; `byLevel` : valeur cumulée par niveau.

export type GrimoireDef = {
	id: string,
	name: { fr: string, en: string },
	desc: { fr: string, en: string }?,
	maxLevel: number,
	perLevel: { [string]: number },
	byLevel: { [string]: { number } }?,
	unlockGated: boolean?, -- true : demande ProgressionService.isUnlocked (bloquée sans lui)
}

local Grimoires = {}

Grimoires.Order = {
	"Damage",
	"AttackSpeed",
	"Projectiles",
	"Area",
	"Duration",
	"Cooldown",
	"Crit",
	"Luck",
	"Wisdom",
	"Magnet",
	"Vitality",
	"Armor",
	"Agility",
	"Cursed",
} :: { string }

-- Texte joueur : anglais seul (décisions v2 section 1) ; noms français dans le dossier 10 section 6.
local function rune(id: string, name: string, desc: string, maxLevel: number, perLevel: { [string]: number }, byLevel: { [string]: { number } }?): GrimoireDef
	return { id = id, name = { en = name, fr = name }, desc = { en = desc, fr = desc }, maxLevel = maxLevel, perLevel = perLevel, byLevel = byLevel }
end

Grimoires.Defs = {
	Damage = rune("Damage", "Damage Rune", "+8% damage per level", 8, { Damage = 0.08 }),
	AttackSpeed = rune("AttackSpeed", "Attack Speed Rune", "+7% attack speed per level", 8, { AttackSpeed = 0.07 }),
	Projectiles = rune("Projectiles", "Projectile Rune", "More projectiles, a bit more damage", 8, {}, {
		Amount = { 1, 1, 2, 2, 3, 3, 4, 4 },
		Damage = { 0, 0.04, 0.04, 0.08, 0.08, 0.12, 0.12, 0.16 },
	}),
	Area = rune("Area", "Area Rune", "+8% area per level", 8, { Size = 0.08 }),
	Duration = rune("Duration", "Duration Rune", "+10% duration per level", 8, { Duration = 0.10 }),
	Cooldown = rune("Cooldown", "Cooldown Rune", "-4% cooldown per level", 8, { Cooldown = 0.04 }),
	Crit = rune("Crit", "Crit Rune", "+4% crit chance and +10% crit damage per level", 8, { CritChance = 0.04, CritDamage = 0.10 }),
	Luck = rune("Luck", "Luck Rune", "+3 luck per level: rarer cards and loot", 8, { Luck = 3 }),
	Wisdom = rune("Wisdom", "Wisdom Rune", "+10% XP per level", 8, { XpGain = 0.10 }),
	Magnet = rune("Magnet", "Magnet Rune", "+3 studs pickup range per level", 8, { Magnet = 3 }),
	Vitality = rune("Vitality", "Vitality Rune", "+15 max HP and +0.1 HP/s per level", 8, { MaxHp = 15, Regen = 0.1 }),
	Armor = rune("Armor", "Armor Rune", "+3 armor per level", 8, { Armor = 3 }),
	Agility = rune("Agility", "Agility Rune", "+4% move speed and +2% dodge per level", 8, { MoveSpeed = 0.04, Dodge = 0.02 }),
	Cursed = rune("Cursed", "Cursed Rune", "Tougher, more numerous enemies, but more loot, XP and damage", 5, { Difficulty = 0.10, LootBonus = 0.12, XpGain = 0.05, Damage = 0.05 }),
} :: { [string]: GrimoireDef }

-- Le StatBlock final part d'ici (Types.StatName). Chaque stat doit avoir une entrée.
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

-- Plafonds appliqués en dernier (pas de plancher, sauf PV max >= 1).
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

-- Libellés courts pour écrire les descriptions des cartes (anglais = texte joueur).
Grimoires.StatLabel = {
	Damage = { en = "damage", fr = "damage", pct = true },
	AttackSpeed = { en = "attack speed", fr = "attack speed", pct = true },
	Amount = { en = "amount", fr = "amount", pct = false },
	Size = { en = "size", fr = "size", pct = true },
	Duration = { en = "duration", fr = "duration", pct = true },
	Cooldown = { en = "cooldown", fr = "cooldown", pct = true },
	CritChance = { en = "crit chance", fr = "crit chance", pct = true },
	CritDamage = { en = "crit damage", fr = "crit damage", pct = true },
	Luck = { en = "luck", fr = "luck", pct = false },
	XpGain = { en = "XP", fr = "XP", pct = true },
	Magnet = { en = "magnet", fr = "magnet", pct = false },
	MaxHp = { en = "max HP", fr = "max HP", pct = false },
	Armor = { en = "armor", fr = "armor", pct = false },
	Regen = { en = "HP/s", fr = "HP/s", pct = false },
	MoveSpeed = { en = "move speed", fr = "move speed", pct = true },
	Dodge = { en = "dodge", fr = "dodge", pct = true },
	Thorns = { en = "thorns", fr = "thorns", pct = true },
	Bounces = { en = "bounces", fr = "bounces", pct = false },
	Difficulty = { en = "difficulty", fr = "difficulty", pct = true },
	LootBonus = { en = "loot", fr = "loot", pct = true },
} :: { [string]: { fr: string, en: string, pct: boolean } }

-- Valeur cumulée d'une stat pour une Rune à un niveau (0 si niveau < 1).
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
