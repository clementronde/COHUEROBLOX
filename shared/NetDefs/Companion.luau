--!strict
-- Remotes en plus du domaine companion (fusionnés par shared/Net). Payloads : docs/dossier/40-compagnons.md §7.

return {
	CaptureState = "RemoteEvent", -- serveur -> le joueur qui capture (forme lue par CaptureUI)
	CageState = "RemoteEvent", -- serveur -> tous : cages vivantes
}
