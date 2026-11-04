--!strict
-- Les 8 classes v2 (docs/dossier/01-decisions-v2.md section 3, détail : dossier 10 section 8).
-- Forme : { [classId]: Types.ClassDef }. Trier par `order` pour l'affichage.
-- La classe ajoute un équipement voxel à l'avatar du joueur (TraitService) ; les stats viennent
-- de la classe (passif dans Config/Weapons.Passives, même id), jamais de l'apparence.
--
-- Champs en plus de Types.ClassDef :
--   order: number                      ordre d'affichage
--   role: LocalizedText                une ligne de présentation (écran de choix)
--   traits: { TraitPart }              pièces d'équipement construites par TraitService
--   stages: { LocalizedText }          description de l'équipement par palier 1..4 (niveaux 1/10/20/30)
--   tints: { Color3 }                  3 teintes gratuites (index lu dans le profil du domaine data)
--   drapeaux de mouvement (lus par le domaine avatar, A06), tous optionnels :
--     slideBoost: number               multiplicateur de vitesse au début de la glissade
--     airJumps: number                 sauts en l'air en plus
--     glide: boolean                   maintenir Saut en tombant pour planer
--     glideSeconds: number             durée max du plané (Mage : plané court)
--     heavyLanding: boolean            atterrissage lourd (onde visuelle à chaque réception)
--     knockbackImmune: boolean         attribut joueur KnockbackImmune
--
-- Transition v1 -> v2 : le domaine data (Config/Progression) et l'UI (Config/UI) utilisent encore
-- les ids v1 (Cornu, Plumeline...). `Classes["Cornu"]` renvoie donc la définition Knight (alias en
-- lecture seule, via métatable : l'itération ne voit que les 8 classes v2). Toujours utiliser
-- `def.id` comme id canonique. À retirer quand ARCHITECTURE.md section 3 passe aux ids v2.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

export type TraitPart = {
	attachment: string, -- nom d'attachement R15 du corps
	builder: string, -- clé de géométrie dans TraitService
	fromStage: number?, -- premier palier où la pièce apparaît (défaut 1)
}

local function t(en: string, fr: string): Types.LocalizedText
	return { en = en, fr = fr }
end

local Classes: { [string]: Types.ClassDef } = {
	Knight = {
		id = "Knight",
		order = 1,
		name = t("Knight", "Chevalier"),
		role = t("Front-line sword swinger. Loves a crowd.", "Combattant au corps à corps. Adore la foule."),
		startWeapon = "Broadsword",
		passive = "Knight",
		walkSpeed = 16,
		jumpHeight = 7.2,
		unlock = "Free",
		traits = {
			{ attachment = "HatAttachment", builder = "KnightHelm" },
			{ attachment = "BodyBackAttachment", builder = "KnightCape", fromStage = 2 },
		},
		stages = {
			t("Bucket helmet", "Heaume seau"),
			t("Red cape", "Cape rouge"),
			t("Golden crest", "Crête dorée"),
			t("Shining armor", "Armure étincelante"),
		},
		tints = { Color3.fromRGB(200, 205, 215), Color3.fromRGB(70, 110, 200), Color3.fromRGB(205, 60, 60) },
	},
	Archer = {
		id = "Archer",
		order = 2,
		name = t("Archer", "Archère"),
		role = t("Long range sniper. Jumps high, shoots far.", "Tireuse à longue portée. Saute haut, tire loin."),
		startWeapon = "Longbow",
		passive = "Archer",
		walkSpeed = 16,
		jumpHeight = 10,
		unlock = "Free",
		traits = {
			{ attachment = "HatAttachment", builder = "ArcherHood" },
			{ attachment = "BodyBackAttachment", builder = "ArcherQuiver" },
		},
		stages = {
			t("Green hood and quiver", "Capuche verte et carquois"),
			t("Feather on the hood", "Plume sur la capuche"),
			t("Full quiver", "Carquois plein"),
			t("Golden arrows", "Flèches dorées"),
		},
		tints = { Color3.fromRGB(70, 150, 70), Color3.fromRGB(140, 90, 50), Color3.fromRGB(60, 60, 70) },
	},
	Mage = {
		id = "Mage",
		order = 3,
		name = t("Mage", "Mage"),
		role = t("Fireball thrower. Bigger spells every level.", "Lanceur de boules de feu. Sorts plus gros à chaque niveau."),
		startWeapon = "FireStaff",
		passive = "Mage",
		walkSpeed = 16,
		jumpHeight = 7.2,
		unlock = "Free",
		traits = {
			{ attachment = "HatAttachment", builder = "MageHat" },
		},
		stages = {
			t("Pointy hat", "Chapeau pointu"),
			t("Star on the hat", "Étoile sur le chapeau"),
			t("Floating rune", "Rune flottante"),
			t("Glowing hat", "Chapeau lumineux"),
		},
		tints = { Color3.fromRGB(90, 70, 190), Color3.fromRGB(190, 50, 60), Color3.fromRGB(40, 40, 50) },
		glide = true,
		glideSeconds = 1.2,
	},
	Guardian = {
		id = "Guardian",
		order = 4,
		name = t("Guardian", "Gardien"),
		role = t("Walking wall. Slow, heavy, hits back.", "Un mur qui marche. Lent, lourd, rend les coups."),
		startWeapon = "QuakeHammer",
		passive = "Guardian",
		walkSpeed = 14,
		jumpHeight = 6.5,
		unlock = "Q_Guardian",
		traits = {
			{ attachment = "LeftShoulderAttachment", builder = "GuardianPauldron" },
			{ attachment = "RightShoulderAttachment", builder = "GuardianPauldron" },
		},
		stages = {
			t("Stone pauldrons", "Épaulières de pierre"),
			t("Bigger pauldrons", "Épaulières plus grosses"),
			t("Iron rivets", "Rivets de fer"),
			t("Molten edges", "Bords en fusion"),
		},
		tints = { Color3.fromRGB(130, 130, 140), Color3.fromRGB(150, 110, 80), Color3.fromRGB(80, 100, 130) },
		heavyLanding = true,
		knockbackImmune = true,
	},
	Rogue = {
		id = "Rogue",
		order = 5,
		name = t("Rogue", "Voleuse"),
		role = t("Slippery dagger thrower. Slides through danger.", "Lanceuse de dagues insaisissable. Glisse à travers le danger."),
		startWeapon = "ThrowingDaggers",
		passive = "Rogue",
		walkSpeed = 17,
		jumpHeight = 7.2,
		unlock = "Q_Rogue",
		traits = {
			{ attachment = "HatAttachment", builder = "RogueMask" },
		},
		stages = {
			t("Bandit mask", "Masque de bandit"),
			t("Hood", "Capuche"),
			t("Dagger belt", "Ceinture de dagues"),
			t("Shadow trail", "Traînée d'ombre"),
		},
		tints = { Color3.fromRGB(50, 50, 60), Color3.fromRGB(120, 40, 60), Color3.fromRGB(40, 90, 90) },
		airJumps = 1,
	},
	Cleric = {
		id = "Cleric",
		order = 6,
		name = t("Cleric", "Clerc"),
		role = t("Holy aura that hurts foes and heals friends.", "Aura sacrée qui blesse les ennemis et soigne les amis."),
		startWeapon = "HolyAura",
		passive = "Cleric",
		walkSpeed = 16,
		jumpHeight = 7.2,
		unlock = "Q_Cleric",
		traits = {
			{ attachment = "HatAttachment", builder = "ClericHalo" },
		},
		stages = {
			t("Little halo", "Petite auréole"),
			t("Brighter halo", "Auréole plus brillante"),
			t("Double halo", "Double auréole"),
			t("Radiant halo", "Auréole rayonnante"),
		},
		tints = { Color3.fromRGB(255, 225, 120), Color3.fromRGB(180, 230, 255), Color3.fromRGB(255, 180, 210) },
	},
	Barbarian = {
		id = "Barbarian",
		order = 7,
		name = t("Barbarian", "Barbare"),
		role = t("Spinning axes. Hits harder when hurt.", "Haches tournoyantes. Frappe plus fort quand il est blessé."),
		startWeapon = "SpinningAxes",
		passive = "Barbarian",
		walkSpeed = 16,
		jumpHeight = 7.2,
		unlock = "Q_Barbarian",
		traits = {
			{ attachment = "HatAttachment", builder = "BarbarianHelm" },
		},
		stages = {
			t("Horned helmet", "Casque à cornes"),
			t("Longer horns", "Cornes plus longues"),
			t("War paint", "Peinture de guerre"),
			t("Flaming horns", "Cornes en flammes"),
		},
		tints = { Color3.fromRGB(150, 100, 60), Color3.fromRGB(110, 110, 120), Color3.fromRGB(200, 170, 120) },
		slideBoost = 1.6,
	},
	Tamer = {
		id = "Tamer",
		order = 8,
		name = t("Tamer", "Dompteuse"),
		role = t("Beast whip and two companions at once.", "Fouet de dompteuse et deux compagnons à la fois."),
		startWeapon = "BeastWhip",
		passive = "Tamer",
		walkSpeed = 16,
		jumpHeight = 7.2,
		unlock = "Q_Tamer",
		traits = {
			{ attachment = "HatAttachment", builder = "TamerHat" },
		},
		stages = {
			t("Ringmaster hat", "Chapeau de dompteuse"),
			t("Paw badge", "Badge patte"),
			t("Fur collar", "Col de fourrure"),
			t("Golden whistle", "Sifflet doré"),
		},
		tints = { Color3.fromRGB(180, 40, 50), Color3.fromRGB(40, 40, 50), Color3.fromRGB(230, 150, 40) },
	},
}

-- Ids v1 encore envoyés par Config/Progression et Config/UI (voir l'en-tête). Astrel et Cristallin
-- n'ont pas d'équivalent v2 : ils restent inconnus.
local LEGACY: { [string]: string } = {
	Cornu = "Knight",
	Plumeline = "Archer",
	Mecano = "Mage",
	Rocailleux = "Guardian",
	Felyne = "Rogue",
	Sporelin = "Cleric",
	Ecaille = "Barbarian",
	Tentaculos = "Tamer",
}

setmetatable(Classes :: any, {
	__index = function(self: any, key: any): any
		local id = if type(key) == "string" then LEGACY[key] else nil
		return if id then rawget(self, id) else nil
	end,
})

return Classes
