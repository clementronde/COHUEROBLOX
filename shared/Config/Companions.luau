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
	extraTargets: number?, -- ennemis en plus touchés à chaque attaque (à TechShare des dégâts)
	evKind: number, -- effet visuel (Companions.Net.Ev*)
}

-- Technique d'espèce (A05-03) : une carte qui s'apprend (niveau 1) puis s'améliore (2, 3).
-- values[n] = valeur au niveau n. Sens de la valeur selon `stat` :
--   Power / Haste / Reach : bonus en fraction (0,15 = +15 %) pour ce compagnon seulement
--   Splash : studs de zone en plus autour de la cible
--   Multishot : ennemis en plus touchés (à TechShare des dégâts)
--   Status : paramètre principal du statut ajouté (Burn/Poison : dps · Slow : mult · Stun/Freeze : durée · Knockback : distance)
--   Pulse : dégâts d'une onde autour du compagnon toutes les `pulse.interval` s, rayon `pulse.radius`
export type TechStat = "Power" | "Haste" | "Reach" | "Splash" | "Multishot" | "Status" | "Pulse"

export type TechDef = {
	id: string, -- unique dans tout le jeu : "<espèce>_<Nom>"
	name: string, -- anglais (textes joueur en anglais au lancement)
	stat: TechStat,
	values: { number },
	status: StatusDef?, -- Status : le statut ajouté (son paramètre principal vient de values)
	pulse: { interval: number, radius: number }?,
	desc: string, -- anglais ; {v} = valeur du niveau
}

-- Surcharge par espèce (A05-03).
export type SpeciesDef = {
	attack: AttackDef?,
	techs: { TechDef }?,
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
	AvailableRadius = 18, -- studs : une cage à capturer plus proche que ça -> CaptureState « Available » (bouton Capture)
	StickySeconds = 1.5, -- Interrupted / Captured / Refused restent affichés au moins ce temps hors de la cage
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
	EvPulse = 6, -- onde d'une technique Pulse (evRadius = rayon)
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

-- Espèces (A05-03) -----------------------------------------------------------------------------------
-- Clé = Config/Enemies[].name. Une attaque et 2 ou 3 techniques par espèce v2 (dossier 40 §5.2).
-- Équilibrage (dossier 40 §5.4) : base ≈ 9 DPS en mêlée sur une cible, ≈ 7 DPS à distance,
-- ≈ 6 DPS en zone ou avec un statut. Une technique au niveau 3 vaut ≈ +35 à +45 % de valeur.
-- Les mini-boss gardent l'attaque de leur famille (MiniBoss), sans technique au lancement.

Companions.TechMaxLevel = 3
Companions.TechShare = 0.6 -- part des dégâts sur les cibles en plus (Multishot, extraTargets)

local function A(name: string, damage: number, interval: number, range: number, evKind: number, extra: { [string]: any }?): AttackDef
	local a: { [string]: any } = { name = T(name, name), damage = damage, interval = interval, range = range, evKind = evKind }
	if extra then
		for k, v in extra do
			a[k] = v
		end
	end
	return (a :: any) :: AttackDef
end

-- Raccourcis de techniques (les textes {v} sont formatés par CompanionService).
local function techId(species: string, name: string): string
	return species .. "_" .. (string.gsub(name, "%W", ""))
end
local function Power(species: string, name: string, desc: string?): TechDef
	return { id = techId(species, name), name = name, stat = "Power", values = { 0.15, 0.25, 0.4 }, desc = desc or "+{v}% damage" }
end
local function Haste(species: string, name: string, desc: string?): TechDef
	return { id = techId(species, name), name = name, stat = "Haste", values = { 0.12, 0.2, 0.3 }, desc = desc or "+{v}% attack speed" }
end
local function Reach(species: string, name: string, desc: string?): TechDef
	return { id = techId(species, name), name = name, stat = "Reach", values = { 0.15, 0.25, 0.4 }, desc = desc or "+{v}% range and area" }
end
local function Splash(species: string, name: string, values: { number }, desc: string?): TechDef
	return { id = techId(species, name), name = name, stat = "Splash", values = values, desc = desc or "Hits everything within {v} studs of the target" }
end
local function Multi(species: string, name: string, values: { number }, desc: string?): TechDef
	return { id = techId(species, name), name = name, stat = "Multishot", values = values, desc = desc or "Also hits {v} more enemies" }
end
local function Status(species: string, name: string, status: StatusDef, values: { number }, desc: string): TechDef
	return { id = techId(species, name), name = name, stat = "Status", values = values, status = status, desc = desc }
end
local function Pulse(species: string, name: string, interval: number, radius: number, values: { number }, desc: string): TechDef
	return {
		id = techId(species, name),
		name = name,
		stat = "Pulse",
		values = values,
		pulse = { interval = interval, radius = radius },
		desc = desc,
	}
end

Companions.Species = {
	-- Monde 1 — Grumpy Woods --------------------------------------------------------------------
	GoblinGrunt = { -- mêlée, 9 DPS
		attack = A("Ladle Bonk", 9, 1.0, 5, NET.EvMelee, { melee = true }),
		techs = {
			Splash("GoblinGrunt", "Big Ladle", { 2, 3, 4 }),
			Haste("GoblinGrunt", "Soup's On"),
		},
	},
	GoblinArcher = { -- distance, 6,7 DPS
		attack = A("Slow Arrow", 8, 1.2, 26, NET.EvShot),
		techs = {
			Multi("GoblinArcher", "Split Shot", { 1, 2, 3 }, "Arrows split to {v} more enemies"),
			Power("GoblinArcher", "Sharp Tips"),
			Reach("GoblinArcher", "Eagle Eye"),
		},
	},
	GoblinShaman = { -- distance + ralenti, 5 DPS
		attack = A("Spirit Bolt", 6, 1.2, 20, NET.EvShot, { status = { { kind = "Slow", mult = 0.85, duration = 1.5 } } }),
		techs = {
			Status("GoblinShaman", "Hex", { kind = "Slow", duration = 2 }, { 0.75, 0.65, 0.55 }, "Slows enemies to {v}% speed for 2s"),
			Pulse("GoblinShaman", "Spirit Circle", 4, 8, { 10, 14, 18 }, "Every 4s, a spirit ring deals {v} damage around it"),
		},
	},
	GoblinBomber = { -- zone lente, 7,3 DPS répartis
		attack = A("Fizzle Bomb", 16, 2.2, 14, NET.EvPounce, { splash = 5 }),
		techs = {
			Reach("GoblinBomber", "Bigger Boom", "+{v}% blast size and range"),
			Haste("GoblinBomber", "Short Fuse", "+{v}% throw speed"),
			Status("GoblinBomber", "Sticky Tar", { kind = "Slow", duration = 1.5 }, { 0.8, 0.7, 0.6 }, "Blasts slow enemies to {v}% speed"),
		},
	},
	GlandGrincheux = { -- mêlée + petit recul, 8,9 DPS
		attack = A("Grumpy Headbutt", 8, 0.9, 5, NET.EvMelee, { melee = true, status = { { kind = "Knockback", distance = 2 } } }),
		techs = {
			Power("GlandGrincheux", "Grudge"),
			Status("GlandGrincheux", "Bonk", { kind = "Stun" }, { 0.3, 0.4, 0.5 }, "Headbutts stun for {v}s"),
		},
	},
	ChampignonSauteur = { -- bond en zone, 8,75 DPS
		attack = A("Spore Pounce", 14, 1.6, 14, NET.EvPounce, { splash = 4 }),
		techs = {
			Status("ChampignonSauteur", "Spore Cloud", { kind = "Poison", duration = 3 }, { 3, 4, 6 }, "Landings poison for {v} damage per second"),
			Haste("ChampignonSauteur", "Bouncy Cap", "+{v}% jump speed"),
		},
	},
	HibouPlongeur = { -- distance, 7 DPS, vole
		flying = true,
		attack = A("Feather Dart", 7, 1.0, 24, NET.EvShot),
		techs = {
			Multi("HibouPlongeur", "Feather Storm", { 1, 2, 3 }, "Darts also hit {v} more enemies"),
			Reach("HibouPlongeur", "Night Eyes"),
		},
	},

	-- Monde 2 — Soggy Graves --------------------------------------------------------------------
	ZombieShambler = { -- mêlée, 9,1 DPS
		attack = A("Grabby Swipe", 10, 1.1, 5, NET.EvMelee, { melee = true }),
		techs = {
			Status("ZombieShambler", "Rotten Touch", { kind = "Poison", duration = 3 }, { 2, 3, 4 }, "Swipes poison for {v} damage per second"),
			Haste("ZombieShambler", "Shamble Faster"),
		},
	},
	ZombieRunner = { -- grand jeté en zone, 8 DPS
		attack = A("Grand Jete", 12, 1.5, 16, NET.EvPounce, { splash = 4 }),
		techs = {
			Splash("ZombieRunner", "Pirouette", { 1.5, 2.5, 3.5 }, "Landing area +{v} studs"),
			Haste("ZombieRunner", "Encore"),
			Power("ZombieRunner", "Prima Ballerina"),
		},
	},
	ZombieGravedigger = { -- motte en petite zone, 6,4 DPS
		attack = A("Dirt Clod", 9, 1.4, 22, NET.EvShot, { splash = 2.5 }),
		techs = {
			Status("ZombieGravedigger", "Fresh Grave", { kind = "Slow", duration = 1.5 }, { 0.7, 0.6, 0.5 }, "Clods slow enemies to {v}% speed"),
			Power("ZombieGravedigger", "Bigger Shovel"),
		},
	},
	ZombieBloater = { -- coup de ventre en zone, 7,5 DPS
		attack = A("Belly Bump", 9, 1.2, 5, NET.EvCharge, { melee = true, splash = 3 }),
		techs = {
			Pulse("ZombieBloater", "Stink Cloud", 3, 7, { 6, 9, 12 }, "Every 3s, a stink cloud deals {v} damage around it"),
			Status("ZombieBloater", "Gassy", { kind = "Poison", duration = 3 }, { 2, 3, 4 }, "Bumps poison for {v} damage per second"),
		},
	},

	-- Monde 3 — Haunted Recess ------------------------------------------------------------------
	GhostWisp = { -- mêlée rapide, 9,3 DPS, flotte
		flying = true,
		attack = A("Spooky Nip", 7, 0.75, 5, NET.EvMelee, { melee = true }),
		techs = {
			Status("GhostWisp", "Chill Touch", { kind = "Slow", duration = 1.5 }, { 0.8, 0.7, 0.6 }, "Nips slow enemies to {v}% speed"),
			Haste("GhostWisp", "Flicker"),
		},
	},
	GhostPoltergeist = { -- 2 livres par lancer, 4,6 + 2,8 DPS, flotte
		flying = true,
		attack = A("Book Toss", 6, 1.3, 22, NET.EvShot, { extraTargets = 1 }),
		techs = {
			Multi("GhostPoltergeist", "Homework Pile", { 1, 2, 3 }, "Throws {v} more books"),
			Status("GhostPoltergeist", "Heavy Dictionary", { kind = "Stun" }, { 0.25, 0.35, 0.5 }, "Books stun for {v}s"),
		},
	},
	GhostBanshee = { -- cri en zone + ralenti, 3,6 DPS répartis, flotte
		flying = true,
		attack = A("Wail", 5, 1.4, 12, NET.EvHeavy, { splash = 6, status = { { kind = "Slow", mult = 0.75, duration = 1.5 } } }),
		techs = {
			Power("GhostBanshee", "Shriek"),
			Reach("GhostBanshee", "Haunting Echo", "+{v}% scream size and range"),
		},
	},
	GhostHallMonitor = { -- sifflet en petite zone + étourdit, 5,4 DPS, flotte
		flying = true,
		attack = A("Whistle Blast", 7, 1.3, 16, NET.EvHeavy, { splash = 3, status = { { kind = "Stun", duration = 0.2 } } }),
		techs = {
			Status("GhostHallMonitor", "Detention", { kind = "Stun" }, { 0.35, 0.5, 0.7 }, "Whistles stun for {v}s"),
			Haste("GhostHallMonitor", "Hall Pass"),
		},
	},
	HauntedArmor = { -- charge en zone + recul, 8,5 DPS
		attack = A("Pointer Lance", 11, 1.3, 5, NET.EvCharge, { melee = true, splash = 3, status = { { kind = "Knockback", distance = 4 } } }),
		techs = {
			Power("HauntedArmor", "Iron Charge"),
			Splash("HauntedArmor", "Ruler Sweep", { 1.5, 2.5, 3.5 }, "Charge area +{v} studs"),
			Status("HauntedArmor", "Shove", { kind = "Knockback" }, { 6, 8, 10 }, "Knocks enemies back {v} studs"),
		},
	},
} :: { [string]: SpeciesDef }

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

-- Cartes de niveau : techniques d'espèce (A05-03) et Friandises génériques ---------------------------
Companions.Cards = {
	MaxOptions = 3,
	MaxTechOptions = 2, -- au plus 2 techniques parmi les 3 options, le reste en Friandises
	TechRarity = "Rare", -- carte qui apprend une technique (CompanionTech)
	TechUpRarity = "Common", -- carte qui l'améliore (CompanionTechUp)
	TechUpPrefix = "Lv {n}: ", -- devant le texte d'une amélioration ; {v} y devient « avant -> après »
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
	Techs = "CompanionTechsLearned", -- 1 par technique apprise (niveau 1)
}

-- Lobby (client seul, CompanionRenderer ; 65-lobby.md §10) --------------------------------------------
-- Hors run : le(s) compagnon(s) équipé(s) suivent le joueur local, le reste de sa collection se promène
-- dans l'enclos. Chacun ne voit que les siens ; positions locales, rien n'est envoyé au serveur.
Companions.Lobby = {
	PenRole = "CritterPen", -- attribut LobbyRole de l'enclos (Workspace.HubbubVillage)
	-- Zone de promenade : la 1re Part de ce nom dans l'enclos, sinon la boîte de l'enclos entière.
	RoamPartNames = { "CritterRoam", "Meadow" },
	Margin = 3, -- studs gardés le long des bords
	MaxPenPets = 12, -- créatures de la collection dans l'enclos (les plus récentes d'abord)
	WanderSpeed = 6, -- studs/s
	WaitMin = 1, -- pause entre deux trajets (s)
	WaitMax = 4,
	PauseDistance = 120, -- joueur plus loin de l'enclos : les créatures ne bougent plus
	PenSearchSeconds = 5, -- enclos pas encore trouvé (streaming) : nouvelle recherche
}

-- Tests en Studio seulement (RunService:IsStudio()), jamais en jeu publié.
Companions.Debug = {
	-- Joueur sans compagnon valide équipé : reçoit cette espèce (nil = rien). Pour voir le suivi.
	TestSpecies = "GlandGrincheux" :: string?,
	-- Tant qu'A03 ne marque pas de capturables : un ennemi non boss sur N tués laisse une cage (0 = jamais).
	CageEveryNthKill = 15,
}

return Companions
