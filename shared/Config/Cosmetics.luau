--!strict
-- Cosmetics catalogue (data domain). Cosmetic only: no cosmetic changes gameplay stats.
-- Design: docs/dossier/70-donnees-progression-monetisation.md section 8.
-- Ids are stable: never rename a shipped id (profiles store them).

export type Source = "Free" | "Mastery" | "Bond" | "Tokens" | "Quest" | "Weekly" | "Pass" | "Product"
export type CosmeticDef = {
	id: string,
	-- base slot: Tint | Pose | CompanionTint | CompanionPose | Title | Emote | Footstep | Aura
	-- Equip slots: "Tint:<classId>", "Pose:<classId>", "CompanionTint:<line>", "CompanionPose:<line>",
	-- "Title", "Emote", "Footstep", "Aura". ("StartTech:<line>" takes a technique id, not a cosmetic.)
	slot: string,
	name: { fr: string, en: string },
	source: Source,
	price: number?, -- quest tokens, when source == "Tokens"
	pass: string?, -- pass key, when source == "Pass"
	classId: string?, -- restricts Tint/Pose to one class
	line: string?, -- restricts CompanionTint/CompanionPose (and line titles) to one companion line
	color: Color3?, -- tints: display colour (no asset ids)
}

local CLASSES = {
	"Cornu",
	"Plumeline",
	"Mecano",
	"Felyne",
	"Rocailleux",
	"Sporelin",
	"Ecaille",
	"Astrel",
	"Cristallin",
	"Tentaculos",
}
local LINES = { "Braise", "Ronce", "Maree", "Volt", "Givre", "Echo" }

local Cosmetics: { [string]: CosmeticDef } = {}

local function add(def: CosmeticDef)
	assert(Cosmetics[def.id] == nil, `duplicate cosmetic {def.id}`)
	Cosmetics[def.id] = def
end

-- Per class: 3 free tints, 4 mastery tints, 2 mastery poses, 2 mastery titles
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
for _, classId in CLASSES do
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

-- Per companion line (levels match Config.Companions.Bond): tints 4/10/20/28, pose 12, title 30
for _, line in LINES do
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

-- Quest-token shop
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
}
for _, t in TOKEN_ITEMS do
	add({ id = t[1], slot = t[2], name = { fr = t[3], en = t[4] }, source = "Tokens", price = t[5] })
end

-- Quest and weekly rewards
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

-- Game passes (Products.luau owns the pass ids)
local PREMIUM_TINTS: { { any } } = {
	{ "Or", "Or pur", "Pure gold", Color3.fromRGB(255, 205, 60) },
	{ "Nacre", "Nacre", "Pearl", Color3.fromRGB(240, 235, 250) },
	{ "Neon", "Néon", "Neon", Color3.fromRGB(60, 255, 160) },
	{ "Galaxie", "Galaxie", "Galaxy", Color3.fromRGB(80, 40, 160) },
	{ "Lave", "Lave", "Lava", Color3.fromRGB(255, 90, 30) },
	{ "Glace", "Glace", "Ice", Color3.fromRGB(150, 220, 255) },
}
for _, t in PREMIUM_TINTS do
	add({
		id = `Tint_Premium_{t[1]}`,
		slot = "Tint",
		name = { fr = t[2], en = t[3] },
		source = "Pass",
		pass = "TeintesPremium",
		color = t[4],
	})
end
local EMOTES: { { any } } = {
	{ "Danse", "Petite danse", "Little dance" },
	{ "Salut", "Révérence", "Bow" },
	{ "Flex", "Muscles", "Flex" },
	{ "Toupie", "Toupie", "Spin" },
	{ "Applaudir", "Applaudir", "Clap" },
	{ "Dodo", "Sieste", "Nap" },
}
for _, e in EMOTES do
	add({ id = `Emote_{e[1]}`, slot = "Emote", name = { fr = e[2], en = e[3] }, source = "Pass", pass = "Emotes" })
end
add({ id = "Title_VIP", slot = "Title", name = { fr = "VIP", en = "VIP" }, source = "Pass", pass = "VIP" })

-- Developer products (permanent cosmetic packs; Products.luau maps product -> cosmetics)
local PRODUCT_ITEMS: { { any } } = {
	{ "Tint_Pack_Braise", "Tint", "Braise", "Ember" },
	{ "Tint_Pack_Magma", "Tint", "Magma", "Magma" },
	{ "Tint_Pack_Soleil", "Tint", "Soleil", "Sun" },
	{ "Tint_Pack_Lagon", "Tint", "Lagon", "Lagoon" },
	{ "Tint_Pack_Abysse", "Tint", "Abysse", "Abyss" },
	{ "Tint_Pack_Ecume", "Tint", "Écume", "Foam" },
	{ "Footstep_Etoiles", "Footstep", "Pas d'étoiles", "Star steps" },
	{ "Footstep_Bulles", "Footstep", "Pas de bulles", "Bubble steps" },
	{ "Aura_Aurore", "Aura", "Aurore", "Aurora" },
	{ "Aura_Ombre", "Aura", "Ombre douce", "Soft shadow" },
}
for _, t in PRODUCT_ITEMS do
	add({ id = t[1], slot = t[2], name = { fr = t[3], en = t[4] }, source = "Product" })
end

return Cosmetics
