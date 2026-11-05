--!strict
-- Catalogue des cosmétiques (domaine data). Purement visuel : aucun cosmétique ne change une stat.
-- Design : docs/dossier/70-donnees-progression-monetisation.md §8 et §9 (A12-04).
-- Les ids sont stables : ne jamais renommer un id publié (les profils les stockent).
--
-- Emplacements d'équipement (EquipCosmetic) :
--   "Tint:<classId>"  skin (couleur) de l'équipement de classe ; def.classId nil = toutes les classes
--   "Pose:<classId>"  pose de victoire ; def.classId nil = toutes les classes
--   "Title", "Emote", "Footstep", "Trail", "KoEffect"
--   "CompanionHat", "CompanionColor", "Aura"  (appliqués à tous les compagnons équipés)
--   "CompanionHat:<espèce>", "CompanionColor:<espèce>", "Aura:<espèce>"  (un compagnon ; voir la fin)
--   "CompanionTint:<line>", "CompanionPose:<line>"  (récompenses de Lien v1, gardées jusqu'à A12-01)
--   "StartTech:<line>" prend un id de technique, pas un cosmétique.
-- Le rendu (A01 modèles, A07 effets, A05 compagnons) clone un modèle nommé d'après l'id
-- (ex. ReplicatedStorage.Assets.FX.Trail_Comet) : rien n'est construit par script.

local Progression = require(script.Parent:WaitForChild("Progression"))
local Products = require(script.Parent:WaitForChild("Products"))

export type Source = "Free" | "Mastery" | "Bond" | "Tokens" | "Quest" | "Weekly" | "Pass" | "Season"
export type CosmeticDef = {
	id: string,
	slot: string, -- emplacement de base (voir l'en-tête)
	name: { fr: string, en: string },
	source: Source,
	price: number?, -- jetons de quête, quand source == "Tokens"
	pass: string?, -- clé de pass, quand source == "Pass" (rempli depuis Products.Passes)
	season: string?, -- quand source == "Season" (rempli depuis Products.Seasons)
	tier: number?,
	track: string?, -- "Free" | "Premium"
	classId: string?, -- restreint Tint / Pose à une classe
	line: string?, -- restreint CompanionTint / CompanionPose (et titres de lignée) à une lignée
	color: Color3?, -- teintes et couleurs : couleur d'affichage (aucun id d'asset)
}

local Cosmetics: { [string]: CosmeticDef } = {}

local function add(def: CosmeticDef)
	assert(Cosmetics[def.id] == nil, `duplicate cosmetic {def.id}`)
	Cosmetics[def.id] = def
end

-- Par classe (Progression.Classes, une seule liste) : 3 teintes gratuites, 4 teintes de maîtrise,
-- 2 poses de maîtrise, 2 titres de maîtrise.
local FREE_TINTS = {
	{ fr = "Naturel", en = "Natural", c = Color3.fromRGB(190, 160, 120) },
	{ fr = "Ardoise", en = "Slate", c = Color3.fromRGB(90, 100, 115) },
	{ fr = "Ivoire", en = "Ivory", c = Color3.fromRGB(235, 228, 210) },
}
local MASTERY_TINTS = {
	{ lvl = 3, fr = "Bronze", en = "Bronze", c = Color3.fromRGB(176, 120, 70) },
	{ lvl = 6, fr = "Argent", en = "Silver", c = Color3.fromRGB(200, 205, 215) },
	{ lvl = 9, fr = "Or", en = "Gold", c = Color3.fromRGB(240, 200, 70) },
	{ lvl = 12, fr = "Prisme", en = "Prism", c = Color3.fromRGB(170, 120, 255) },
}
for _, classId in Progression.Classes do
	for i, t in FREE_TINTS do
		add({
			id = `Tint_{classId}_Base{i}`,
			slot = "Tint",
			name = { fr = t.fr, en = t.en },
			source = "Free",
			classId = classId,
			color = t.c,
		})
	end
	for _, t in MASTERY_TINTS do
		add({
			id = `Tint_{classId}_M{t.lvl}`,
			slot = "Tint",
			name = { fr = `{t.fr} (maîtrise {t.lvl})`, en = `{t.en} (mastery {t.lvl})` },
			source = "Mastery",
			classId = classId,
			color = t.c,
		})
	end
	add({
		id = `Pose_{classId}_M5`,
		slot = "Pose",
		name = { fr = "Pose fière", en = "Proud pose" },
		source = "Mastery",
		classId = classId,
	})
	add({
		id = `Pose_{classId}_M15`,
		slot = "Pose",
		name = { fr = "Pose légendaire", en = "Legendary pose" },
		source = "Mastery",
		classId = classId,
	})
	add({
		id = `Title_{classId}_M10`,
		slot = "Title",
		name = { fr = `Expert {classId}`, en = `{classId} Expert` },
		source = "Mastery",
	})
	add({
		id = `Title_{classId}_M20`,
		slot = "Title",
		name = { fr = `Maître {classId}`, en = `{classId} Master` },
		source = "Mastery",
	})
end

-- Par lignée v1 (niveaux de Config.Companions.Bond) : teintes 4/10/20/28, pose 12, titre 30.
-- À revoir avec la collection v2 (A12-01).
for _, line in Progression.Lines do
	for _, lvl in { 4, 10, 20, 28 } do
		add({
			id = `CompanionTint_{line}_B{lvl}`,
			slot = "CompanionTint",
			name = { fr = `Teinte de Lien {lvl}`, en = `Bond tint {lvl}` },
			source = "Bond",
			line = line,
		})
	end
	add({
		id = `Pose_{line}_B12`,
		slot = "CompanionPose",
		name = { fr = "Pose complice", en = "Partner pose" },
		source = "Bond",
		line = line,
	})
	add({
		id = `Title_{line}_B30`,
		slot = "Title",
		name = { fr = "Inséparable", en = "Inseparable" },
		source = "Bond",
		line = line,
	})
end

-- Boutique de jetons de quête (gratuite : jetons gagnés en jouant, jamais achetables)
local TOKEN_ITEMS: { { any } } = {
	{ "Title_Explorateur", "Title", "Explorateur", "Explorer", 60 },
	{ "Title_Chasseur", "Title", "Chasseur", "Hunter", 60 },
	{ "Title_Increvable", "Title", "Increvable", "Unbreakable", 120 },
	{ "Title_Copain", "Title", "Bon copain", "Good buddy", 80 },
	{ "Footstep_Feuilles", "Footstep", "Pas de feuilles", "Leaf steps", 100 },
	{ "Footstep_Craie", "Footstep", "Pas de craie", "Chalk steps", 100 },
	{ "Footstep_Sable", "Footstep", "Pas de sable", "Sand steps", 100 },
	{ "Aura_Lucioles", "Aura", "Lucioles", "Fireflies", 150 },
	{ "Aura_Bulles", "Aura", "Bulles", "Bubbles", 150 },
	{ "Emote_Pouce", "Emote", "Pouce levé", "Thumbs up", 80 },
	{ "Emote_Coucou", "Emote", "Coucou", "Wave", 80 },
	{ "Tint_Token_Menthe", "Tint", "Menthe", "Mint", 120 },
	{ "Tint_Token_Corail", "Tint", "Corail", "Coral", 120 },
	{ "Tint_Token_Nuit", "Tint", "Nuit", "Night", 150 },
	{ "Trail_Token_Spark", "Trail", "Étincelles", "Sparks", 150 },
	{ "KoEffect_Token_Pop", "KoEffect", "Pop", "Pop", 150 },
	{ "CompanionHat_Token_Leaf", "CompanionHat", "Feuille", "Leaf hat", 120 },
}
for _, t in TOKEN_ITEMS do
	add({ id = t[1], slot = t[2], name = { fr = t[3], en = t[4] }, source = "Tokens", price = t[5] })
end

-- Récompenses de quêtes et du défi hebdo
local QUEST_ITEMS: { { any } } = {
	{ "Title_Centurion", "Title", "Centurion", "Centurion" },
	{ "Title_Survivant", "Title", "Survivant", "Survivor" },
	{ "Title_Collectionneur", "Title", "Collectionneur", "Collector" },
	{ "Title_Infatigable", "Title", "Infatigable", "Tireless" },
	{ "Title_Sauveteur", "Title", "Sauveteur", "Lifesaver" },
	{ "Title_Dresseur", "Title", "Ami des bêtes", "Beast friend" },
	{ "Footstep_Etincelles", "Footstep", "Pas d'étincelles", "Spark steps" },
	{ "Aura_Flammeche", "Aura", "Flammèche", "Ember" },
}
for _, t in QUEST_ITEMS do
	add({ id = t[1], slot = t[2], name = { fr = t[3], en = t[4] }, source = "Quest" })
end
add({ id = "Title_Weekly", slot = "Title", name = { fr = "Défieur", en = "Challenger" }, source = "Weekly" })

-- Objets vendus en pass de jeu (Products.Passes dit quel pass les contient : champ `pass` rempli
-- plus bas). Un id listé ici doit appartenir à exactement un pass.
local PAID: { { any } } = {
	-- slot, id, fr, en, couleur?, classId?
	{ "Tint", "Tint_Premium_Or", "Or pur", "Pure gold", Color3.fromRGB(255, 205, 60) },
	{ "Tint", "Tint_Premium_Nacre", "Nacre", "Pearl", Color3.fromRGB(240, 235, 250) },
	{ "Tint", "Tint_Premium_Neon", "Néon", "Neon", Color3.fromRGB(60, 255, 160) },
	{ "Tint", "Tint_Premium_Galaxie", "Galaxie", "Galaxy", Color3.fromRGB(80, 40, 160) },
	{ "Tint", "Tint_Premium_Lave", "Lave", "Lava", Color3.fromRGB(255, 90, 30) },
	{ "Tint", "Tint_Premium_Glace", "Glace", "Ice", Color3.fromRGB(150, 220, 255) },
	{ "Tint", "Tint_Pack_Braise", "Braise", "Ember", Color3.fromRGB(230, 90, 40) },
	{ "Tint", "Tint_Pack_Magma", "Magma", "Magma", Color3.fromRGB(180, 40, 20) },
	{ "Tint", "Tint_Pack_Soleil", "Soleil", "Sun", Color3.fromRGB(255, 190, 40) },
	{ "Tint", "Tint_Pack_Lagon", "Lagon", "Lagoon", Color3.fromRGB(40, 190, 200) },
	{ "Tint", "Tint_Pack_Abysse", "Abysse", "Abyss", Color3.fromRGB(20, 50, 120) },
	{ "Tint", "Tint_Pack_Ecume", "Écume", "Foam", Color3.fromRGB(210, 240, 245) },
	{ "Emote", "Emote_Danse", "Petite danse", "Little dance" },
	{ "Emote", "Emote_Salut", "Révérence", "Bow" },
	{ "Emote", "Emote_Flex", "Muscles", "Flex" },
	{ "Emote", "Emote_Toupie", "Toupie", "Spin" },
	{ "Emote", "Emote_Applaudir", "Applaudir", "Clap" },
	{ "Emote", "Emote_Dodo", "Sieste", "Nap" },
	{ "Pose", "Pose_Hero", "Pose de héros", "Hero pose" },
	{ "Pose", "Pose_Throne", "Trône", "Throne" },
	{ "Pose", "Pose_Flip", "Salto", "Backflip" },
	{ "KoEffect", "KoEffect_Confetti", "Confettis", "Confetti" },
	{ "KoEffect", "KoEffect_Stars", "Étoiles", "Stars" },
	{ "KoEffect", "KoEffect_Bubbles", "Bulles", "Bubbles" },
	{ "Trail", "Trail_Rainbow", "Arc-en-ciel", "Rainbow" },
	{ "Trail", "Trail_Comet", "Comète", "Comet" },
	{ "Trail", "Trail_Leaves", "Feuilles", "Leaves" },
	{ "Trail", "Trail_VIP_Gold", "Traînée dorée", "Gold trail" },
	{ "Footstep", "Footstep_Etoiles", "Pas d'étoiles", "Star steps" },
	{ "Footstep", "Footstep_Bulles", "Pas de bulles", "Bubble steps" },
	{ "CompanionHat", "CompanionHat_Crown", "Couronne", "Crown" },
	{ "CompanionHat", "CompanionHat_Party", "Chapeau de fête", "Party hat" },
	{ "CompanionHat", "CompanionHat_Pirate", "Tricorne", "Pirate hat" },
	{ "CompanionHat", "CompanionHat_Flower", "Couronne de fleurs", "Flower crown" },
	{ "CompanionColor", "CompanionColor_Gold", "Doré", "Golden", Color3.fromRGB(255, 200, 60) },
	{ "CompanionColor", "CompanionColor_Candy", "Bonbon", "Candy", Color3.fromRGB(255, 130, 200) },
	{ "CompanionColor", "CompanionColor_Mint", "Menthe", "Mint", Color3.fromRGB(120, 240, 190) },
	{ "CompanionColor", "CompanionColor_Midnight", "Minuit", "Midnight", Color3.fromRGB(40, 40, 110) },
	{ "Aura", "Aura_Aurore", "Aurore", "Aurora" },
	{ "Aura", "Aura_Ombre", "Ombre douce", "Soft shadow" },
	{ "Title", "Title_VIP", "VIP", "VIP" },
}
for _, t in PAID do
	add({ id = t[2], slot = t[1], name = { fr = t[3], en = t[4] }, source = "Pass", color = t[5] })
end
for key, pass in Products.Passes do
	for _, id in pass.cosmetics do
		local def = Cosmetics[id]
		assert(def and def.source == "Pass", `pass {key}: cosmetic {id} missing or not a Pass item`)
		assert(def.pass == nil, `cosmetic {id} is in two passes`)
		def.pass = key
	end
end
for id, def in Cosmetics do
	assert(def.source ~= "Pass" or def.pass ~= nil, `paid cosmetic {id} is in no pass`)
end

-- Pass saisonnier (piste gratuite + piste premium ; paliers dans Products.Seasons)
local SEASON_ITEMS: { { any } } = {
	-- slot, id, fr, en, couleur?
	{ "Tint", "Tint_S1_Moss", "Mousse", "Moss", Color3.fromRGB(110, 160, 70) },
	{ "Tint", "Tint_S1_Amber", "Ambre", "Amber", Color3.fromRGB(230, 150, 40) },
	{ "KoEffect", "KoEffect_S1_Leaves", "Pluie de feuilles", "Leaf burst" },
	{ "KoEffect", "KoEffect_S1_Gold", "Éclat d'or", "Gold burst" },
	{ "CompanionColor", "CompanionColor_S1_Autumn", "Automne", "Autumn", Color3.fromRGB(200, 110, 50) },
	{ "Trail", "Trail_S1_Firefly", "Lucioles", "Fireflies" },
	{ "Trail", "Trail_S1_Breeze", "Brise", "Breeze" },
	{ "Pose", "Pose_S1_Champion", "Champion", "Champion" },
	{ "CompanionHat", "CompanionHat_S1_Mushroom", "Champignon", "Mushroom cap" },
	{ "CompanionHat", "CompanionHat_S1_Acorn", "Gland", "Acorn cap" },
	{ "Emote", "Emote_S1_Victory", "Danse de victoire", "Victory dance" },
	{ "Emote", "Emote_S1_Cheer", "Hourra", "Cheer" },
	{ "Footstep", "Footstep_S1_Pebbles", "Cailloux", "Pebble steps" },
	{ "Aura", "Aura_S1_Spores", "Spores", "Spores" },
	{ "Title", "Title_S1_Rookie", "Recrue de la saison 1", "Season 1 Rookie" },
	{ "Title", "Title_S1_Veteran", "Vétéran de la saison 1", "Season 1 Veteran" },
	{ "Title", "Title_S1_Legend", "Légende de la saison 1", "Season 1 Legend" },
}
for _, t in SEASON_ITEMS do
	add({ id = t[2], slot = t[1], name = { fr = t[3], en = t[4] }, source = "Season", color = t[5] })
end
for seasonId, season in Products.Seasons.List do
	for _, reward in season.rewards do
		local def = Cosmetics[reward.cosmetic]
		assert(def and def.source == "Season", `season {seasonId}: cosmetic {reward.cosmetic} missing or not a Season item`)
		assert(def.season == nil, `cosmetic {reward.cosmetic} is rewarded twice`)
		assert(reward.tier >= 1 and reward.tier <= season.tiers, `season {seasonId}: bad tier {reward.tier}`)
		def.season = seasonId
		def.tier = reward.tier
		def.track = reward.track
	end
end
for id, def in Cosmetics do
	assert(def.source ~= "Season" or def.season ~= nil, `season cosmetic {id} is in no season`)
end

-- Personnalisation des compagnons (A05-05, dossier 40 §8.2) : trois emplacements par compagnon de la
-- collection, "CompanionHat:<espèce>", "CompanionColor:<espèce>", "Aura:<espèce>" (repli : l'emplacement
-- global du même nom, pour tous les compagnons). Ids ci-dessus (slot = CompanionHat / CompanionColor /
-- Aura), prix dans Products. Lecture et encodage : Config/Companions.Look ; rendu : CompanionRenderer
-- (Assets.Cosmetics.CompanionHats.<id>, def.color, Assets.FX.CompanionAuras.<id>).

return Cosmetics
