--!strict
-- Remotes du domaine avatar (A06), fusionnés par shared/Net.luau.
-- MoveEvent (C->S, 10/s) : (kind: "SlideStart" | "SlideEnd" | "Hop" | "HopReset")
--   Validé par MovementGuard, qui pose les attributs serveur du Player (lecture seule ailleurs) :
--   Sliding (bool, expire seul après 2,5 s), SlideCharge (bool, glissade de charge du Barbarian),
--   HopChain (hops enchaînés), Airborne (bool, rayon serveur à 4 Hz),
--   HeavyLandAt (GetServerTimeNow du dernier atterrissage lourd d'une classe qui en a un).

return {
	MoveEvent = "RemoteEvent",
}
