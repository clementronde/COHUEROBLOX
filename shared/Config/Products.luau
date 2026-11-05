--!strict
-- Catalogue Robux (domaine data, A12-04). 100 % cosmétique (01-decisions-v2 §9, 00-vision §11.3) :
-- aucune stat, aucune résurrection, aucune classe, aucun produit aléatoire, aucun œuf, aucune monnaie,
-- aucun saut de palier de saison. Design : docs/dossier/70-donnees-progression-monetisation.md §9.
--
-- Tout objet permanent est vendu en PASS DE JEU (audit S-10) : Roblox refuse lui-même de vendre deux
-- fois un pass, même si un client appelle PromptGamePassPurchase directement. Un produit développeur
-- peut être racheté sans fin, donc il ne doit JAMAIS porter un objet permanent : Products.Products est
-- vide et le chargement de MonetizationService refuse un produit qui accorde des cosmétiques.
--
-- Les clés sont stables ; les ids viennent du Creator Dashboard. id = 0 = « pas encore créé » : le
-- serveur ne propose jamais l'achat et personne ne possède le pass. TODO : créer chaque pass et coller
-- son id. `fallbackRobux` n'est affiché QUE si MarketplaceService:GetProductInfoAsync échoue (prix
-- régional, tests de prix et réduction Plus changent le vrai prix : toujours afficher le prix lu).

export type Text = { fr: string, en: string }
export type PassDef = {
	id: number,
	fallbackRobux: number,
	category: string, -- "VIP" | "Season" | "Bundle" (onglets de la boutique, A09-07)
	name: Text,
	description: Text,
	cosmetics: { string }, -- accordés tant que le pass est possédé (dérivé, jamais stocké)
	season: string?, -- pass saisonnier : id de la saison (Products.Seasons)
}
export type ProductDef = { id: number, fallbackRobux: number, name: Text }
export type SeasonReward = { tier: number, track: "Free" | "Premium", cosmetic: string }
export type SeasonDef = {
	id: string,
	name: Text,
	pass: string, -- clé du pass premium (Products.Passes)
	startsAt: number, -- os.time ; 0 = dès maintenant
	endsAt: number, -- os.time ; 0 = pas de date de fin (TODO dates de Clément)
	tiers: number,
	xpPerTier: number,
	rewards: { SeasonReward },
}

local Products = {}

Products.Passes = {
	VIP = {
		id = 0, -- TODO pass id
		fallbackRobux = 299,
		category = "VIP",
		name = { fr = "VIP", en = "VIP" },
		description = {
			fr = "Salon privé gratuit pour toi et tes amis, titre doré et traînée dorée.",
			en = "Free private room for you and your friends, gold title and gold trail.",
		},
		cosmetics = { "Title_VIP", "Trail_VIP_Gold" },
	},
	Season1 = {
		id = 0, -- TODO pass id (retirer de la vente à la fin de la saison)
		fallbackRobux = 399,
		category = "Season",
		name = { fr = "Pass Saison 1", en = "Season 1 Pass" },
		description = {
			fr = "Débloque la piste premium de la saison 1, y compris les paliers déjà atteints.",
			en = "Unlocks the Season 1 premium track, including tiers you already reached.",
		},
		cosmetics = {},
		season = "S1",
	},
	PremiumSkins = {
		id = 0, -- TODO pass id
		fallbackRobux = 199,
		category = "Bundle",
		name = { fr = "Teintes premium", en = "Premium Skins" },
		description = { fr = "6 teintes d'équipement pour toutes les classes.", en = "6 gear colors for every class." },
		cosmetics = {
			"Tint_Premium_Or",
			"Tint_Premium_Nacre",
			"Tint_Premium_Neon",
			"Tint_Premium_Galaxie",
			"Tint_Premium_Lave",
			"Tint_Premium_Glace",
		},
	},
	FireSkins = {
		id = 0, -- TODO pass id
		fallbackRobux = 99,
		category = "Bundle",
		name = { fr = "Teintes de feu", en = "Fire Skins" },
		description = { fr = "3 teintes d'équipement chaudes.", en = "3 warm gear colors." },
		cosmetics = { "Tint_Pack_Braise", "Tint_Pack_Magma", "Tint_Pack_Soleil" },
	},
	OceanSkins = {
		id = 0, -- TODO pass id
		fallbackRobux = 99,
		category = "Bundle",
		name = { fr = "Teintes océan", en = "Ocean Skins" },
		description = { fr = "3 teintes d'équipement froides.", en = "3 cool gear colors." },
		cosmetics = { "Tint_Pack_Lagon", "Tint_Pack_Abysse", "Tint_Pack_Ecume" },
	},
	VictoryEmotes = {
		id = 0, -- TODO pass id
		fallbackRobux = 149,
		category = "Bundle",
		name = { fr = "Emotes de victoire", en = "Victory Emotes" },
		description = { fr = "6 emotes pour le lobby et la fin de run.", en = "6 emotes for the lobby and the end screen." },
		cosmetics = { "Emote_Danse", "Emote_Salut", "Emote_Flex", "Emote_Toupie", "Emote_Applaudir", "Emote_Dodo" },
	},
	VictoryPoses = {
		id = 0, -- TODO pass id
		fallbackRobux = 99,
		category = "Bundle",
		name = { fr = "Poses de victoire", en = "Victory Poses" },
		description = { fr = "3 poses de victoire pour toutes les classes.", en = "3 victory poses for every class." },
		cosmetics = { "Pose_Hero", "Pose_Throne", "Pose_Flip" },
	},
	KoEffects = {
		id = 0, -- TODO pass id
		fallbackRobux = 149,
		category = "Bundle",
		name = { fr = "Effets de KO", en = "KO Effects" },
		description = { fr = "3 effets quand tu mets un ennemi KO.", en = "3 effects when you knock out an enemy." },
		cosmetics = { "KoEffect_Confetti", "KoEffect_Stars", "KoEffect_Bubbles" },
	},
	Trails = {
		id = 0, -- TODO pass id
		fallbackRobux = 129,
		category = "Bundle",
		name = { fr = "Traînées", en = "Trails" },
		description = { fr = "3 traînées lumineuses derrière toi.", en = "3 glowing trails behind you." },
		cosmetics = { "Trail_Rainbow", "Trail_Comet", "Trail_Leaves" },
	},
	SparkleSteps = {
		id = 0, -- TODO pass id
		fallbackRobux = 79,
		category = "Bundle",
		name = { fr = "Pas scintillants", en = "Sparkle Steps" },
		description = { fr = "2 effets de pas.", en = "2 footstep effects." },
		cosmetics = { "Footstep_Etoiles", "Footstep_Bulles" },
	},
	CompanionHats = {
		id = 0, -- TODO pass id
		fallbackRobux = 129,
		category = "Bundle",
		name = { fr = "Chapeaux de compagnon", en = "Companion Hats" },
		description = { fr = "4 chapeaux pour tous tes compagnons.", en = "4 hats for all your companions." },
		cosmetics = { "CompanionHat_Crown", "CompanionHat_Party", "CompanionHat_Pirate", "CompanionHat_Flower" },
	},
	CompanionColors = {
		id = 0, -- TODO pass id
		fallbackRobux = 99,
		category = "Bundle",
		name = { fr = "Couleurs de compagnon", en = "Companion Colors" },
		description = { fr = "4 couleurs pour tous tes compagnons.", en = "4 colors for all your companions." },
		cosmetics = { "CompanionColor_Gold", "CompanionColor_Candy", "CompanionColor_Mint", "CompanionColor_Midnight" },
	},
	CompanionAuras = {
		id = 0, -- TODO pass id
		fallbackRobux = 99,
		category = "Bundle",
		name = { fr = "Auras de compagnon", en = "Companion Auras" },
		description = { fr = "2 auras pour tous tes compagnons.", en = "2 auras for all your companions." },
		cosmetics = { "Aura_Aurore", "Aura_Ombre" },
	},
} :: { [string]: PassDef }

-- Ordre d'affichage de la boutique (A09-07).
Products.ShopOrder = {
	"VIP",
	"Season1",
	"PremiumSkins",
	"FireSkins",
	"OceanSkins",
	"KoEffects",
	"Trails",
	"VictoryEmotes",
	"VictoryPoses",
	"SparkleSteps",
	"CompanionHats",
	"CompanionColors",
	"CompanionAuras",
} :: { string }

-- Produits développeur : AUCUN (voir l'en-tête, S-10). Un produit retiré garderait ici son entrée
-- pour que ses reçus en attente soient encore traités.
Products.Products = {} :: { [string]: ProductDef }

-- Pass saisonnier : XP de saison gagnée en jouant (jamais achetée), paliers accordés automatiquement
-- (pas de remote de réclamation). Piste gratuite pour tous, piste premium avec le pass de la saison,
-- rétroactive. Possession DÉRIVÉE : palier atteint (profil.seasons[id]) + pass pour la piste premium.
Products.Seasons = {
	Current = "S1",
	-- XP de saison par run terminée : Base + 1 par KoPerXp KO + PerWorld par monde fini, plafond Cap.
	Xp = { Base = 20, KoPerXp = 25, PerWorld = 10, Cap = 120 },
	List = {
		S1 = {
			id = "S1",
			name = { fr = "Saison 1 : Bois Grognon", en = "Season 1: Grumpy Woods" },
			pass = "Season1",
			startsAt = 0, -- TODO dates de la saison (Clément)
			endsAt = 0,
			tiers = 30,
			xpPerTier = 100, -- 3 000 XP au total, ~30-40 runs
			rewards = {
				{ tier = 1, track = "Premium", cosmetic = "Tint_S1_Moss" },
				{ tier = 3, track = "Premium", cosmetic = "KoEffect_S1_Leaves" },
				{ tier = 5, track = "Free", cosmetic = "Title_S1_Rookie" },
				{ tier = 6, track = "Premium", cosmetic = "CompanionColor_S1_Autumn" },
				{ tier = 9, track = "Premium", cosmetic = "Trail_S1_Firefly" },
				{ tier = 10, track = "Free", cosmetic = "Emote_S1_Cheer" },
				{ tier = 12, track = "Premium", cosmetic = "Pose_S1_Champion" },
				{ tier = 15, track = "Free", cosmetic = "Footstep_S1_Pebbles" },
				{ tier = 15, track = "Premium", cosmetic = "CompanionHat_S1_Mushroom" },
				{ tier = 18, track = "Premium", cosmetic = "Emote_S1_Victory" },
				{ tier = 20, track = "Free", cosmetic = "Trail_S1_Breeze" },
				{ tier = 21, track = "Premium", cosmetic = "Tint_S1_Amber" },
				{ tier = 24, track = "Premium", cosmetic = "Aura_S1_Spores" },
				{ tier = 25, track = "Free", cosmetic = "CompanionHat_S1_Acorn" },
				{ tier = 27, track = "Premium", cosmetic = "KoEffect_S1_Gold" },
				{ tier = 30, track = "Free", cosmetic = "Title_S1_Veteran" },
				{ tier = 30, track = "Premium", cosmetic = "Title_S1_Legend" },
			},
		},
	} :: { [string]: SeasonDef },
}

-- Saison en cours à cette date (nil hors saison).
function Products.activeSeason(now: number): SeasonDef?
	local season = Products.Seasons.List[Products.Seasons.Current]
	if not season then
		return nil
	end
	if season.startsAt > 0 and now < season.startsAt then
		return nil
	end
	if season.endsAt > 0 and now >= season.endsAt then
		return nil
	end
	return season
end

Products.ProfileWaitSeconds = 15 -- ProcessReceipt attend le profil d'un joueur qui arrive
Products.PassCheckAttempts = 3
Products.PassRecheckSeconds = 30

return Products
