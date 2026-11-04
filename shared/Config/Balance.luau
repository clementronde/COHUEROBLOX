--!strict
-- All tuning values live here (design doc 12.6): rebalance without touching logic.

local Balance = {
	-- Simulation
	SimHz = 15,
	MaxEnemies = 300, -- hard cap per server (doc 9.3 / 12.2)
	MaxSpawnsPerTick = 10,
	GridCellSize = 8, -- studs, spatial grid for separation (doc 12.2)
	SeparationGap = 0.3, -- extra space kept between two enemies' radii
	RelaxIterations = 2, -- overlap-resolution passes per tick (more = firmer crowd, more CPU)
	ContactDistance = 1.5, -- player half-width: enemies stop walking at this distance + their radius
	TargetRefreshTicks = 8, -- re-pick nearest player every N ticks
	SpawnRingMin = 60,
	SpawnRingMax = 90,
	RecycleDistance = 220, -- enemies this far from their target are moved back to the spawn ring

	-- Density curve (solo): {seconds since run start, enemies alive} (doc 9.3)
	DensityCurve = {
		{ 0, 10 },
		{ 60, 40 },
		{ 300, 120 },
		{ 540, 200 },
		{ 600, 200 },
	} :: { { number } },
	DensityPerExtraPlayer = 0.4, -- doc 5.2
	HpPerExtraPlayer = 0.6, -- doc 5.2
	SwarmShare = 0.8, -- share of spawns that are the basic swarm kind (doc 9.1)

	-- Network (doc 12.2)
	InterestRadiusNear = 80, -- sent every tick
	InterestRadiusFar = 160, -- sent every FarSendEveryNTicks; must cover the farthest LOD band
	FarSendEveryNTicks = 3,
	ChunkMaxBytes = 900, -- UnreliableRemoteEvent drops payloads over 1,000 bytes
	PositionScale = 4, -- quantization: 1/4 stud, i16 range = +/- 8191 studs

	-- Client
	ClientStaleTicks = 7, -- drop an enemy not seen for this many ticks (> FarSendEveryNTicks * 2)

	-- Debug / perf gate (doc 14, phase 0: 150 enemies at 60 fps on a mid-range phone)
	Debug = {
		ForceAlive = nil :: number?, -- set to e.g. 150 to hold a fixed count for the perf test
		ShowStats = true,
	},
}

return Balance
