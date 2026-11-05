--!strict
-- Réglages du domaine companion v2 (docs/dossier/40-compagnons.md). Tous les nombres sont ici.
-- v2 : un compagnon est une créature battue puis capturée. Id d'espèce = Config/Enemies[kind].name.
-- Plus de lignées, d'évolution ni d'Ultime (01-decisions-v2.md §5).

local Types = require(script.Parent.Parent.Types)

type LocalizedText = Types.LocalizedText

export type StatusKind = "Burn" | "Poison" | "Slow" | "Freeze" | "Stun" | "Knockback"

export type StatusDef = {
	kind: StatusKind,
	dps: number?,
	duration: number?,
	mult: number?, -- Slow
	distance: number?, -- Knockback
}

-- Attaque de base d'un compagnon (par famille d'ennemi, surchargeable par espèce).
export type AttackDef = {
	name: LocalizedText,
	damage: number,
	interval: number, -- secondes entre deux attaques
	range: number, -- portée de frappe (studs, depuis le compagnon)
	melee: boolean?, -- va au contact : se rapproche de la cible (dans la laisse)
	splash: number?, -- rayon de zone autour de la cible
	status: { StatusDef }?,
	evKind: number, -- effet visuel (Companions.Net.Ev*)
}

-- Surcharge par espèce (A05-03).
export type SpeciesDef = {
	attack: AttackDef?,
	height: number?, -- studs ; défaut = hauteur de l'ennemi × Render.HeightScale
	flying: boolean?,
}

export type TreatDef = {
	id: string,
	name: LocalizedText,
	stat: "Power" | "Haste" | "Reach",
	values: { [Types.Rarity]: number },
	maxStacks: number,
}

local function T(fr: string, en: string): LocalizedText
	return { fr = fr, en = en }
end

local Companions = {}

Companions.SimHz = 10 -- cerveau serveur, capture et snapshot (vault : cerveaux de PNJ à ~10 Hz)
Companions.StateMaxPerSecond = 4

-- Capture ------------------------------------------------------------------------------------------
Companions.Capture = {
	CageSeconds = 10, -- durée de vie de la cage après la mort du capturable
	Radius = 6, -- studs, test 2D « dedans »
	VerticalTolerance = 6, -- studs entre les pieds du joueur et le sol de la cage
	HoldSeconds = 2, -- temps à tenir sans être touché (Tamer : ÷ Passives.Tamer.captureSpeed)
	InterruptLockout = 0.5, -- après un coup, la barre ne repart pas avant ce délai
	MaxPerRun = 5, -- captures par joueur et par run (anti-farm, à régler)
	MaxCages = 12, -- cages vivantes dans la run ; au-delà, la plus ancienne disparaît
	KeysKept = 200, -- clés d'idempotence gardées dans le profil (indication pour A12)
	-- Phases de run où une cage peut naître et progresser.
	Phases = { Running = true, Boss = true, BossDefeated = true, FinalWave = true, Overtime = true, KeepGoing = true } :: { [string]: boolean },
}

-- Équipement ---------------------------------------------------------------------------------------
Companions.DefaultSlots = 1 -- la classe peut en donner plus (Config/Weapons.Passives[classId].companionSlots)

-- Suivi --------------------------------------------------------------------------------------------
Companions.Follow = {
	Behind = 5, -- studs derrière le propriétaire
	Side = 2.5, -- studs sur le côté (gauche emplacement 1, droite emplacement 2)
	Speed = 24, -- studs/s (1,5 × marche de base 16)
	SnapDistance = 60, -- téléporté derrière le joueur au-delà
	FlyHeight = 2.5, -- hauteur en plus pour les espèces volantes
	ChaseLeash = 14, -- peut s'écarter de son point de suivi de cette distance vers une cible
	GuardRadius = 10, -- propriétaire à terre : n'attaque qu'autour de lui
}

Companions.StunOnDowned = 5 -- secondes sonné quand le propriétaire tombe
Companions.OwnerDamageShare = 0.5 -- part du stat Damage du propriétaire héritée
Companions.LevelScaling = 0.04 -- +4 % de dégâts par niveau de run du propriétaire au-delà du 1er

-- Réseau (CompanionSnapshot, non fiable) -----------------------------------------------------------
Companions.Net = {
	HeaderBytes = 5, -- tick u32 | count u8
	-- userId f64 | slot u8 | kind u8 | x,y,z i16 | yaw u8 | flags u8 | evSeq u8 | evKind u8 | evX,evZ i16 | evRadius u8
	RecordBytes = 25,
	ChunkMaxBytes = 900, -- un paquet non fiable de plus de 1 000 octets est perdu
	PositionScale = 4, -- 1/4 de stud
	StunnedBit = 1,
	EvNone = 0,
	EvMelee = 1,
	EvPounce = 2,
	EvShot = 3,
	EvCharge = 4,
	EvHeavy = 5,
}

local NET = Companions.Net

-- Attaque par famille (Config/Enemies[].family) ------------------------------------------------------
Companions.Families = {
	Swarm = { name = T("Morsure", "Bite"), damage = 8, interval = 0.9, range = 5, melee = true, evKind = NET.EvMelee },
	Jumper = { name = T("Bond", "Pounce"), damage = 14, interval = 1.6, range = 14, splash = 4, evKind = NET.EvPounce },
	Shooter = { name = T("Tir", "Shot"), damage = 7, interval = 1.1, range = 24, evKind = NET.EvShot },
	Armored = {
		name = T("Charge", "Charge"),
		damage = 10,
		interval = 1.3,
		range = 5,
		melee = true,
		splash = 3,
		status = { { kind = "Knockback", distance = 4 } },
		evKind = NET.EvCharge,
	},
	MiniBoss = {
		name = T("Coup lourd", "Heavy Smash"),
		damage = 24,
		interval = 1.4,
		range = 8,
		melee = true,
		splash = 6,
		status = { { kind = "Stun", duration = 0.5 } },
		evKind = NET.EvHeavy,
	},
} :: { [string]: AttackDef }

Companions.DefaultFamily = "Swarm" -- famille inconnue (nouvelle famille d'A03) : attaque de Swarm

-- Surcharges par espèce (clé = Config/Enemies[].name). Vide jusqu'à A05-03.
Companions.Species = {} :: { [string]: SpeciesDef }

-- Rendu (client) -----------------------------------------------------------------------------------
-- Gabarits cherchés dans ReplicatedStorage.Assets (ArtLibrary.find, recherche récursive par nom).
Companions.Render = {
	ModelPrefix = "Companion_", -- maille propre au compagnon : Companion_<espèce>
	EnemyPrefix = "Enemy_", -- repli : la maille de l'ennemi
	HeightScale = 0.8 * 1.3, -- hauteur de gameplay de l'ennemi × 1,3 (échelle de dessin d'EnemyRenderer) × 0,8
	CageTemplate = "FX_CaptureCage",
	CageSuccessTemplate = "FX_CaptureSuccess",
	StunTemplate = "FX_CompanionStun",
	HitTemplate = "FX_CompanionHit",
	HitPool = 24,
	HitSeconds = 0.35,
	SuccessSeconds = 1.5,
	CageBlinkSeconds = 3, -- la cage clignote pendant ses dernières secondes
	InterpDelay = 0.12, -- retard d'interpolation (s), un peu plus d'un tic serveur
	StaleSeconds = 1.5, -- compagnon plus reçu depuis ce délai : retiré
	HopHeight = 0.35,
	HopHz = 3,
}

-- Cartes de niveau (en attendant les techniques par espèce, A05-03) ----------------------------------
Companions.Cards = {
	MaxOptions = 3,
	TreatRarityOdds = { { "Common", 0.6 }, { "Rare", 0.3 }, { "Epic", 0.1 } } :: { { any } },
}

Companions.Treats = {
	TreatPower = {
		id = "TreatPower",
		name = T("Biscuit costaud", "Hearty Biscuit"),
		stat = "Power",
		values = { Common = 0.08, Rare = 0.12, Epic = 0.18, Legendary = 0.18 },
		maxStacks = 10,
	},
	TreatHaste = {
		id = "TreatHaste",
		name = T("Bonbon pétillant", "Fizzy Candy"),
		stat = "Haste",
		values = { Common = 0.06, Rare = 0.09, Epic = 0.14, Legendary = 0.14 },
		maxStacks = 10,
	},
	TreatReach = {
		id = "TreatReach",
		name = T("Baie longue-vue", "Spyglass Berry"),
		stat = "Reach",
		values = { Common = 0.08, Rare = 0.12, Epic = 0.18, Legendary = 0.18 },
		maxStacks = 10,
	},
} :: { [string]: TreatDef }

-- Texte de carte (anglais seul au lancement) ; {p} = pourcentage.
Companions.TreatDesc = {
	Power = "+{p}% companion damage",
	Haste = "+{p}% companion attack speed",
	Reach = "+{p}% companion range and area",
} :: { [string]: string }

-- Clés de quêtes (ProgressionService.recordStat) -----------------------------------------------------
Companions.QuestKeys = {
	Captured = "CompanionsCaptured",
	NewSpecies = "CompanionNewSpecies",
	Kills = "CompanionKills",
	Treats = "CompanionTreats",
}

-- Tests en Studio seulement (RunService:IsStudio()), jamais en jeu publié.
Companions.Debug = {
	-- Joueur sans compagnon valide équipé : reçoit cette espèce (nil = rien). Pour voir le suivi.
	TestSpecies = "GlandGrincheux" :: string?,
	-- Tant qu'A03 ne marque pas de capturables : un ennemi non boss sur N tués laisse une cage (0 = jamais).
	CageEveryNthKill = 15,
}

return Companions
