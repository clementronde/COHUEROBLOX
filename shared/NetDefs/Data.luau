--!strict
-- Data-domain remotes added to Net (docs/dossier/70-donnees-progression-monetisation.md section 16).
-- Contract remotes (Profile, SelectLoadout, EquipCosmetic, UpdateSettings) live in shared/Net.luau.

return {
	ShopBuy = "RemoteEvent", -- client -> server: (offerId: string)
	HatchEgg = "RemoteEvent", -- client -> server: ()
	RequestPurchase = "RemoteEvent", -- client -> server: (productKey: string)
	EggHatched = "RemoteEvent", -- server -> client: { line: string?, tokens: number? }
	Leaderboards = "RemoteEvent", -- server -> client: { [boardKey]: {{ userId, value }} }
	MatchRequest = "RemoteEvent", -- client -> server: (worldId: string, tier: number)
	MatchState = "RemoteEvent", -- server -> client: { state, reason: LocalizedText? }
	MatchMode = "RemoteEvent", -- client -> server: (mode: "Solo" | "Party" | "Public"), avant SelectLoadout
	DataNotice = "RemoteEvent", -- server -> client: { kind, text: LocalizedText, questId: string? }
}
