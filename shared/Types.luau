--!strict
-- Shared types. Cross-domain contract: docs/ARCHITECTURE.md. Domain-specific config types
-- live next to their config module; only types used by more than one domain go here.

export type EnemyDef = {
	id: number,
	name: string,
	hp: number,
	speed: number, -- studs per second
	radius: number,
	height: number,
	color: Color3,
	-- Optional fields owned by the run domain (contact damage, xp value, family...)
	contactDamage: number?,
	xp: number?,
	family: string?,
}

-- Every service/controller module returns this shape. init: no yielding. start: may yield.
export type System = {
	init: (() -> ())?,
	start: (() -> ())?,
}

export type LocalizedText = { fr: string, en: string }

export type Rarity = "Common" | "Rare" | "Epic" | "Legendary"

-- Stat semantics (ARCHITECTURE.md section 4):
--   percent stats are additive bonuses, effective multiplier = 1 + value (0.25 => x1.25)
--   flat stats are plain numbers
export type StatName =
	"Damage" -- percent
	| "AttackSpeed" -- percent
	| "Amount" -- flat, extra projectiles
	| "Size" -- percent
	| "Duration" -- percent
	| "Cooldown" -- percent reduction, capped by StatsService
	| "CritChance" -- flat 0..1
	| "CritDamage" -- percent, base crit = x2
	| "Luck" -- flat
	| "XpGain" -- percent
	| "Magnet" -- flat studs added to pickup radius
	| "MaxHp" -- flat
	| "Armor" -- flat
	| "Regen" -- flat hp per second
	| "MoveSpeed" -- percent
	| "Dodge" -- flat 0..1
	| "Thorns" -- flat 0..1 share of damage reflected
	| "Bounces" -- flat
	| "Difficulty" -- percent (Forbidden grimoire, Greedy piggy bank)
	| "LootBonus" -- percent

export type StatBlock = { [StatName]: number }

export type ClassDef = {
	id: string, -- see ARCHITECTURE.md ids
	name: LocalizedText,
	startWeapon: string, -- weapon id
	passive: string, -- passive id, implemented by the combat domain (same as class id)
	walkSpeed: number,
	jumpHeight: number,
	unlock: string, -- "Free" or a quest id
	-- Avatar domain adds its own fields (trait attachment, stages, movement flags...)
	[string]: any,
}

export type CardKind =
	"NewWeapon"
	| "WeaponUp"
	| "NewGrimoire"
	| "GrimoireUp"
	| "CompanionTech"
	| "CompanionTechUp"
	| "CompanionTreat"
	| "Heal"
	| "Coins"

export type Card = {
	kind: CardKind,
	id: string,
	rarity: Rarity,
	level: number, -- level after picking
	title: string,
	desc: string,
	icon: string?, -- rbxassetid or nil (UI draws a placeholder)
}

export type RunPhase = "Loadout" | "Running" | "Boss" | "BossDefeated" | "FinalWave" | "Ended"

export type RunSummary = {
	victory: boolean,
	worldId: string,
	tier: number,
	stageReached: number,
	kills: number,
	damageByWeapon: { [string]: number },
	finalWaveSeconds: number,
	coinsEarned: number,
	chestsOpened: number,
	shrinesCompleted: number,
	revives: number,
	classId: string,
	companionId: string,
	companionStage: number,
	level: number,
	-- Filled by ProgressionService before RunSummary is sent to the client
	silverEarned: number?,
	questsProgressed: { { id: string, progress: number, goal: number, completed: boolean } }?,
}

return nil
