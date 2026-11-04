--!strict
-- Avatar domain remotes (merged by shared/Net.luau).
-- MoveEvent (C->S): (kind: "SlideStart" | "SlideEnd" | "Hop" | "HopReset")
--   Validated by MovementGuard, which sets server attributes Sliding / HopChain / Airborne on the Player.

return {
	MoveEvent = "RemoteEvent",
}
