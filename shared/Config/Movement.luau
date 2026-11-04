--!strict
-- Movement tuning (avatar domain). Design: docs/dossier/50-classes-avatar-mouvement.md sections 4 and 6.

local Movement = {
	-- Defaults when no class is set (lobby, before the run)
	DefaultWalkSpeed = 16,
	DefaultJumpHeight = 7.2,

	-- Bunny-hop (doc 10.1)
	BhopWindow = 0.15, -- seconds after landing in which a jump counts as a hop
	BhopGainPerHop = 0.03, -- +3 % per successful hop
	BhopMaxBonus = 0.6, -- capped at +60 %
	BhopMinTurnDeg = 8, -- camera yaw change during the previous airtime needed to gain speed

	-- Jump forgiveness
	JumpBuffer = 0.12, -- seconds before landing a press still counts
	CoyoteTime = 0.10, -- seconds after walking off a ledge

	-- Slide
	SlideMinSpeed = 8, -- studs/s of horizontal speed needed to start
	SlideBoostDefault = 1.15, -- start speed multiplier (class slideBoost overrides)
	SlideFriction = 14, -- studs/s^2 lost on flat ground
	SlideSlopeGain = 0.6, -- share of g * sin(slope) gained downhill
	SlideMaxMult = 2.2, -- slide speed cap, x base walk speed
	SlideEndMult = 0.6, -- slide ends below this x walk speed
	SlideMaxFlatTime = 1.6, -- seconds of slide without slope before it ends

	-- Air abilities
	GlideFallSpeed = 8, -- studs/s max fall speed while gliding
	ClimbSpeed = 14, -- studs/s up a wall
	ClimbProbe = 2, -- studs, wall detection distance in front of the root
	GroundNormalMinY = 0.55, -- verified floor (refills air jumps / climb)

	-- Landing shockwave (visual only)
	ShockwaveMinFall = 18, -- studs of fall height
	ShockwaveMaxRadius = 12,
	ShockwaveTime = 0.35,

	-- Server signals (MoveEvent remote)
	MoveEventRate = 8, -- per second per player
	SlidingAttrTimeout = 2.5, -- seconds before the server clears Sliding on its own
	HopMinInterval = 0.2, -- seconds between two counted hops

	-- Trait growth (TraitService). Kept here so Config.Classes stays a pure { [classId]: ClassDef } map.
	Trait = {
		StageLevels = { 10, 20, 30 }, -- run levels that reach stages 2, 3, 4
		StageScale = { 1.0, 1.15, 1.3, 1.45 },
		AvatarScaleMin = 0.6,
		AvatarScaleMax = 1.6,
		AppearanceTimeout = 6, -- seconds to wait for CharacterAppearanceLoaded
	},

	-- MovementGuard (server plausibility, doc 12.4)
	Guard = {
		Interval = 0.25, -- seconds between samples
		SpeedMargin = 1.35, -- allowed multiple of the max plausible speed
		BucketMax = 40, -- studs of accumulated excess before a rubber-band
		LeakPerSecond = 20, -- studs of excess forgiven per second
		PingCap = 1, -- seconds; ping slack is clamped to this
		TeleportMinStuds = 45, -- a single step above max(this, dynamic) is a teleport
		HitchFactor = 3, -- skip a sample when dt > HitchFactor * Interval
		GraceAfterRubberBand = 0.6, -- seconds (+ ping) of rebase-only after a correction
		SpawnGrace = 3, -- seconds after CharacterAdded
		HoverLimit = 3.5, -- seconds airborne without descending
		HoverDescend = 0.5, -- studs below take-off height that count as descending
		HoverEnforce = false, -- shadow mode: log only until tuned from logs
		Enforce = true, -- false = log only for speed/teleport too
		LogEvery = 5, -- seconds between warnings per player
	},
}

return Movement
