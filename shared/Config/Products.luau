--!strict
-- Robux catalogue (data domain). Cosmetic only (doc 11.3): no random items, no revives, no classes,
-- no power, no eggs, no currency. Design: docs/dossier/70-donnees-progression-monetisation.md section 9.
--
-- Keys are stable; ids come from the Creator Dashboard. id = 0 means "not created yet": the server
-- never prompts it and ProcessReceipt ignores it. TODO: create every pass/product and paste the ids.
-- Retired products keep their entry (and so their grant) so pending receipts can still be granted.
-- `fallbackRobux` is shown ONLY if MarketplaceService:GetProductInfoAsync fails (regional pricing,
-- price tests and Plus discounts make the real price differ: always display the live price).

export type PassDef = { id: number, fallbackRobux: number, name: { fr: string, en: string }, cosmetics: { string } }
export type ProductDef = { id: number, fallbackRobux: number, name: { fr: string, en: string }, cosmetics: { string } }

local Products = {}

Products.Passes = {
	TeintesPremium = {
		id = 0, -- TODO pass id
		fallbackRobux = 199,
		name = { fr = "Teintes Premium", en = "Premium Tints" },
		cosmetics = {
			"Tint_Premium_Or",
			"Tint_Premium_Nacre",
			"Tint_Premium_Neon",
			"Tint_Premium_Galaxie",
			"Tint_Premium_Lave",
			"Tint_Premium_Glace",
		},
	},
	Emotes = {
		id = 0, -- TODO pass id
		fallbackRobux = 149,
		name = { fr = "Emotes de victoire", en = "Victory Emotes" },
		cosmetics = { "Emote_Danse", "Emote_Salut", "Emote_Flex", "Emote_Toupie", "Emote_Applaudir", "Emote_Dodo" },
	},
	VIP = {
		id = 0, -- TODO pass id
		fallbackRobux = 299,
		name = { fr = "VIP (salon privé + titre doré)", en = "VIP (private room + gold title)" },
		cosmetics = { "Title_VIP" },
	},
} :: { [string]: PassDef }

-- Developer products: permanent cosmetic packs, refused at prompt time when already owned.
Products.Products = {
	PackTeintesFeu = {
		id = 0, -- TODO product id
		fallbackRobux = 99,
		name = { fr = "Pack Teintes de Feu", en = "Fire Tints Pack" },
		cosmetics = { "Tint_Pack_Braise", "Tint_Pack_Magma", "Tint_Pack_Soleil" },
	},
	PackTeintesOcean = {
		id = 0, -- TODO product id
		fallbackRobux = 99,
		name = { fr = "Pack Teintes Océan", en = "Ocean Tints Pack" },
		cosmetics = { "Tint_Pack_Lagon", "Tint_Pack_Abysse", "Tint_Pack_Ecume" },
	},
	EffetPasEtoiles = {
		id = 0, -- TODO product id
		fallbackRobux = 49,
		name = { fr = "Pas d'étoiles", en = "Star Steps" },
		cosmetics = { "Footstep_Etoiles" },
	},
	EffetPasBulles = {
		id = 0, -- TODO product id
		fallbackRobux = 49,
		name = { fr = "Pas de bulles", en = "Bubble Steps" },
		cosmetics = { "Footstep_Bulles" },
	},
	AuraCompagnonAurore = {
		id = 0, -- TODO product id
		fallbackRobux = 79,
		name = { fr = "Aura de compagnon Aurore", en = "Aurora Companion Aura" },
		cosmetics = { "Aura_Aurore" },
	},
	AuraCompagnonOmbre = {
		id = 0, -- TODO product id
		fallbackRobux = 79,
		name = { fr = "Aura de compagnon Ombre douce", en = "Soft Shadow Companion Aura" },
		cosmetics = { "Aura_Ombre" },
	},
} :: { [string]: ProductDef }

Products.ProfileWaitSeconds = 15 -- ProcessReceipt waits this long for a joining player's profile
Products.PassCheckAttempts = 3
Products.PassRecheckSeconds = 30

return Products
