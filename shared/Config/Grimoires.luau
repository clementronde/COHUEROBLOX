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

local function rune(id: string, en: string, fr: string, descEn: string, descFr: string, maxLevel: number, perLevel: { [string]: number }, byLevel: { [string]: { number } }?): GrimoireDef
	return { id = id, name = { en = en, fr = fr }, desc = { en = descEn, fr = descFr }, maxLevel = maxLevel, perLevel = perLevel, byLevel = byLevel }
end

Grimoires.Defs = {
	Damage = rune("Damage", "Damage Rune", "Rune de dégâts", "+8% damage per level", "+8 % de dégâts par niveau", 8, { Damage = 0.08 }),
	AttackSpeed = rune("AttackSpeed", "Attack Speed Rune", "Rune de vitesse d'attaque", "+7% attack speed per level", "+7 % de vitesse d'attaque par niveau", 8, { AttackSpeed = 0.07 }),
	Projectiles = rune("Projectiles", "Projectile Rune", "Rune de projectiles", "More projectiles, a bit more damage", "Plus de projectiles, un peu plus de dégâts", 8, {}, {
		Amount = { 1, 1, 2, 2, 3, 3, 4, 4 },
		Damage = { 0, 0.04, 0.04, 0.08, 0.08, 0.12, 0.12, 0.16 },
	}),
	Area = rune("Area", "Area Rune", "Rune de zone", "+8% area per level", "+8 % de zone par niveau", 8, { Size = 0.08 }),
	Duration = rune("Duration", "Duration Rune", "Rune de durée", "+10% duration per level", "+10 % de durée par niveau", 8, { Duration = 0.10 }),
	Cooldown = rune("Cooldown", "Cooldown Rune", "Rune de recharge", "-4% cooldown per level", "-4 % de recharge par niveau", 8, { Cooldown = 0.04 }),
	Crit = rune("Crit", "Crit Rune", "Rune critique", "+4% crit chance and +10% crit damage per level", "+4 % de critique et +10 % de dégâts critiques par niveau", 8, { CritChance = 0.04, CritDamage = 0.10 }),
	Luck = rune("Luck", "Luck Rune", "Rune de chance", "+3 luck per level: rarer cards and loot", "+3 de chance par niveau : cartes et butin plus rares", 8, { Luck = 3 }),
	Wisdom = rune("Wisdom", "Wisdom Rune", "Rune de sagesse", "+10% XP per level", "+10 % d'XP par niveau", 8, { XpGain = 0.10 }),
	Magnet = rune("Magnet", "Magnet Rune", "Rune aimant", "+3 studs pickup range per level", "+3 studs de ramassage par niveau", 8, { Magnet = 3 }),
	Vitality = rune("Vitality", "Vitality Rune", "Rune de vitalité", "+15 max HP and +0.1 HP/s per level", "+15 PV max et +0,1 PV/s par niveau", 8, { MaxHp = 15, Regen = 0.1 }),
	Armor = rune("Armor", "Armor Rune", "Rune d'armure", "+3 armor per level", "+3 d'armure par niveau", 8, { Armor = 3 }),
	Agility = rune("Agility", "Agility Rune", "Rune d'agilité", "+4% move speed and +2% dodge per level", "+4 % de vitesse et +2 % d'esquive par niveau", 8, { MoveSpeed = 0.04, Dodge = 0.02 }),
	Cursed = rune("Cursed", "Cursed Rune", "Rune maudite", "Tougher, more numerous enemies, but more loot, XP and damage", "Ennemis plus durs et plus nombreux, mais plus de butin, d'XP et de dégâts", 5, { Difficulty = 0.10, LootBonus = 0.12, XpGain = 0.05, Damage = 0.05 }),
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
