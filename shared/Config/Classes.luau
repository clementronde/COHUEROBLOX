--!strict
-- The 10 launch classes (avatar domain). Design: docs/dossier/50-classes-avatar-mouvement.md section 2.
-- Shape: { [classId]: Types.ClassDef }. Sort by `order` for display.
-- Avatar fields beyond Types.ClassDef:
--   order: number                      display order
--   traits: { TraitPart }              accessories built by TraitService (builder = geometry key)
--   stages: { LocalizedText }          trait description per stage 1..4
--   tints: { Color3 }                  3 free trait tints (index from the data domain profile)
--   movement flags (all optional):
--     slideBoost: number               slide start speed multiplier (default Movement.SlideBoostDefault)
--     airJumps: number                 extra jumps in the air
--     glide: boolean                   hold Jump while falling to glide
--     climbTime: number                seconds of short wall climb
--     gravityMult: number              < 1 = low gravity
--     bhopWindow: number               overrides Movement.BhopWindow
--     bhopNoTurn: boolean              hop gain without camera turn
--     knockbackImmune: boolean         sets the KnockbackImmune player attribute

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

export type TraitPart = {
	attachment: string, -- R15 body attachment name
	builder: string, -- geometry key in TraitService
	fromStage: number?, -- first stage where this accessory appears (default 1)
}

local function t(fr: string, en: string): Types.LocalizedText
	return { fr = fr, en = en }
end

local Classes: { [string]: Types.ClassDef } = {
	Cornu = {
		id = "Cornu",
		order = 1,
		name = t("Cornu", "Horned"),
		startWeapon = "HacheBoomerang",
		passive = "Cornu",
		walkSpeed = 16,
		jumpHeight = 7.2,
		unlock = "Free",
		traits = { { attachment = "HatAttachment", builder = "RamHorns" } },
		stages = {
			t("Cornes de bélier", "Ram horns"),
			t("Cornes plus longues", "Longer horns"),
			t("Gravures lumineuses", "Glowing carvings"),
			t("Cornes en flammes", "Flaming horns"),
		},
		tints = { Color3.fromRGB(222, 205, 170), Color3.fromRGB(120, 90, 70), Color3.fromRGB(70, 70, 80) },
		slideBoost = 1.4,
	},
	Plumeline = {
		id = "Plumeline",
		order = 2,
		name = t("Plumeline", "Featherling"),
		startWeapon = "PlumesDards",
		passive = "Plumeline",
		walkSpeed = 16,
		jumpHeight = 7.2,
		unlock = "Free",
		traits = { { attachment = "BodyBackAttachment", builder = "FeatherWings" } },
		stages = {
			t("Ailes de plumes", "Feather wings"),
			t("Ailes plus grandes", "Bigger wings"),
			t("Plumes dorées", "Golden feathers"),
			t("Ailes de lumière", "Wings of light"),
		},
		tints = { Color3.fromRGB(245, 245, 250), Color3.fromRGB(110, 170, 230), Color3.fromRGB(60, 60, 70) },
		airJumps = 1,
		glide = true,
	},
	Mecano = {
		id = "Mecano",
		order = 3,
		name = t("Mécano", "Tinker"),
		startWeapon = "CleTourelle",
		passive = "Mecano",
		walkSpeed = 17.6,
		jumpHeight = 5.5,
		unlock = "Free",
		traits = { { attachment = "RightShoulderAttachment", builder = "MechArm" } },
		stages = {
			t("Bras mécanique", "Mechanical arm"),
			t("Pistons", "Pistons"),
			t("Deuxième bras", "Second arm"),
			t("Bras doré à vapeur", "Golden steam arm"),
		},
		tints = { Color3.fromRGB(150, 155, 165), Color3.fromRGB(180, 110, 60), Color3.fromRGB(70, 110, 160) },
	},
	Felyne = {
		id = "Felyne",
		order = 4,
		name = t("Félyne", "Felyne"),
		startWeapon = "GriffesEclair",
		passive = "Felyne",
		walkSpeed = 16,
		jumpHeight = 7.2,
		unlock = "Q_Felyne",
		traits = {
			{ attachment = "HatAttachment", builder = "CatEars" },
			{ attachment = "WaistBackAttachment", builder = "CatTail" },
		},
		stages = {
			t("Oreilles et queue de chat", "Cat ears and tail"),
			t("Rayures", "Stripes"),
			t("Queue double", "Double tail"),
			t("Pelage étincelant", "Sparkling fur"),
		},
		tints = { Color3.fromRGB(240, 160, 70), Color3.fromRGB(60, 60, 60), Color3.fromRGB(235, 235, 235) },
		bhopWindow = 0.25,
		bhopNoTurn = true,
	},
	Rocailleux = {
		id = "Rocailleux",
		order = 5,
		name = t("Rocailleux", "Stoneback"),
		startWeapon = "PoingSeisme",
		passive = "Rocailleux",
		walkSpeed = 14,
		jumpHeight = 6.5,
		unlock = "Q_Rocailleux",
		traits = {
			{ attachment = "LeftShoulderAttachment", builder = "StonePlate" },
			{ attachment = "RightShoulderAttachment", builder = "StonePlate" },
		},
		stages = {
			t("Plaques de pierre", "Stone plates"),
			t("Mousse", "Moss"),
			t("Cristaux", "Crystals"),
			t("Armure de lave", "Lava armor"),
		},
		tints = { Color3.fromRGB(120, 120, 125), Color3.fromRGB(150, 120, 90), Color3.fromRGB(80, 90, 110) },
		knockbackImmune = true,
	},
	Sporelin = {
		id = "Sporelin",
		order = 6,
		name = t("Sporelin", "Sporeling"),
		startWeapon = "NuageSpores",
		passive = "Sporelin",
		walkSpeed = 16,
		jumpHeight = 7.2,
		unlock = "Q_Sporelin",
		traits = { { attachment = "HatAttachment", builder = "MushroomCap" } },
		stages = {
			t("Chapeau-champignon", "Mushroom cap"),
			t("Taches", "Spots"),
			t("Spores flottantes", "Floating spores"),
			t("Chapeau géant lumineux", "Giant glowing cap"),
		},
		tints = { Color3.fromRGB(200, 60, 60), Color3.fromRGB(150, 90, 200), Color3.fromRGB(230, 180, 60) },
	},
	Ecaille = {
		id = "Ecaille",
		order = 7,
		name = t("Écaille", "Scaleling"),
		startWeapon = "SouffleBraise",
		passive = "Ecaille",
		walkSpeed = 16,
		jumpHeight = 9.5,
		unlock = "Q_Ecaille",
		traits = {
			{ attachment = "HatAttachment", builder = "SmallHorns" },
			{ attachment = "WaistBackAttachment", builder = "ScalyTail" },
			{ attachment = "BodyBackAttachment", builder = "DragonWings", fromStage = 4 },
		},
		stages = {
			t("Petites cornes et queue écailleuse", "Small horns and scaly tail"),
			t("Écailles", "Scales"),
			t("Crête", "Crest"),
			t("Mini-ailes de dragon", "Mini dragon wings"),
		},
		tints = { Color3.fromRGB(70, 160, 90), Color3.fromRGB(200, 70, 50), Color3.fromRGB(60, 90, 170) },
	},
	Astrel = {
		id = "Astrel",
		order = 8,
		name = t("Astrel", "Starling"),
		startWeapon = "Meteorite",
		passive = "Astrel",
		walkSpeed = 16,
		jumpHeight = 7.2,
		unlock = "Q_Astrel",
		traits = { { attachment = "HatAttachment", builder = "StarCrown" } },
		stages = {
			t("Antennes et étoile", "Antennae and a star"),
			t("Deux étoiles", "Two stars"),
			t("Quatre étoiles", "Four stars"),
			t("Anneau galactique", "Galactic ring"),
		},
		tints = { Color3.fromRGB(255, 220, 90), Color3.fromRGB(150, 200, 255), Color3.fromRGB(255, 150, 220) },
		gravityMult = 0.6,
	},
	Cristallin = {
		id = "Cristallin",
		order = 9,
		name = t("Cristallin", "Crystalline"),
		startWeapon = "EclatsPrisme",
		passive = "Cristallin",
		walkSpeed = 16,
		jumpHeight = 7.2,
		unlock = "Q_Cristallin",
		traits = {
			{ attachment = "LeftShoulderAttachment", builder = "Crystals" },
			{ attachment = "RightShoulderAttachment", builder = "Crystals" },
		},
		stages = {
			t("Cristaux d'épaule", "Shoulder crystals"),
			t("Les cristaux poussent", "Crystals grow"),
			t("Grappe de cristaux", "Crystal cluster"),
			t("Couronne de cristaux", "Crystal crown"),
		},
		tints = { Color3.fromRGB(140, 220, 255), Color3.fromRGB(220, 140, 255), Color3.fromRGB(150, 255, 180) },
	},
	Tentaculos = {
		id = "Tentaculos",
		order = 10,
		name = t("Tentaculos", "Tentaclos"),
		startWeapon = "FouetTentacule",
		passive = "Tentaculos",
		walkSpeed = 16,
		jumpHeight = 7.2,
		unlock = "Q_Tentaculos",
		traits = { { attachment = "BodyBackAttachment", builder = "Tentacles" } },
		stages = {
			t("4 tentacules", "4 tentacles"),
			t("6 tentacules", "6 tentacles"),
			t("Ventouses lumineuses", "Glowing suckers"),
			t("8 tentacules", "8 tentacles"),
		},
		tints = { Color3.fromRGB(160, 80, 170), Color3.fromRGB(230, 110, 120), Color3.fromRGB(70, 150, 150) },
		climbTime = 1.2,
	},
}

return Classes
