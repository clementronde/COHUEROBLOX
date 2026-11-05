--!strict
-- Remotes en plus du domaine companion (fusionnés par shared/Net). Payloads : docs/dossier/40-compagnons.md §7.
--
-- CaptureState (serveur -> le joueur concerné, au plus 10/s, seulement quand l'état ou la barre au 1/10 change) :
--   { state = "Idle" | "Available" | "Capturing" | "Interrupted" | "Captured" | "Refused",
--     progress: number (0..1), holdSeconds: number, name: LocalizedText?, isNew: boolean?, reason: ("Cap" | "Unavailable")? }
--   Available = une cage à capturer à moins de Capture.AvailableRadius (bouton Capture, pas de panneau).
--   Forme demandée par 60-ui-ux.md (CaptureUI) ; « Refused », isNew et reason sont en plus.
-- CageState (serveur -> tous) : { cages = {{ id, species, kind, x, y, z, expiresIn, done = { userId } }} }

return {
	CaptureState = "RemoteEvent",
	CageState = "RemoteEvent",
}
