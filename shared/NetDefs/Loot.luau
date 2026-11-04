--!strict
-- Loot-domain extra remotes (merged by shared/Net). Payloads: docs/dossier/30-butin-autels.md section 8.

return {
	LootInteract = "RemoteEvent", -- client -> server (id: number)
	MerchantOffer = "RemoteEvent",
	MerchantBuy = "RemoteEvent", -- client -> server (slot: number)
	LootReward = "RemoteEvent",
	ShrineInteract = "RemoteEvent", -- client -> server (shrineId: number)
	ShrineGag = "RemoteEvent",
}
