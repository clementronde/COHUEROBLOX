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

	-- Network (doc 12.2 ; PERF-01, A03-v3) : chaque client reçoit à chaque tick ses SnapshotNearCount
	-- ennemis les plus proches (et ceux qui agissent : préparation, saut, état qui change, boss), le
	-- reste à moins de InterestRadiusNear un tick sur NearRestEveryNTicks, et jusqu'à
	-- InterestRadiusFar un tick sur FarSendEveryNTicks (étalés par id).
	InterestRadiusNear = 80,
	InterestRadiusFar = 160, -- must cover the farthest LOD band
	SnapshotNearCount = 48,
	NearRestEveryNTicks = 4,
	FarSendEveryNTicks = 8,
	ChunkMaxBytes = 900, -- UnreliableRemoteEvent drops payloads over 1,000 bytes
	PositionScale = 4, -- quantization: 1/4 stud, i16 range = +/- 8191 studs
	AttackVisualRadius = 90, -- EnemyAttackVisual : seulement aux joueurs à moins de ce rayon (boss : x1,6)

	-- Client
	-- Drop an enemy not seen for this many ticks (> FarSendEveryNTicks * 2). Les morts partent tout de
	-- suite (liste removed d'EnemyCodec) : ce délai ne sert qu'aux ennemis qui sortent du rayon.
	ClientStaleTicks = 18,

	-- Debug / perf gate (doc 14, phase 0: 150 enemies at 60 fps on a mid-range phone)
	Debug = {
		ForceAlive = nil :: number?, -- set to e.g. 150 to hold a fixed count for the perf test (borné par MaxEnemies, avertissement sinon : QA-01)
		ShowStats = game:GetService("RunService"):IsStudio(), -- never on live servers
	},
}

return Balance
