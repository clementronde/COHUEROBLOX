--!strict
-- Server-wide events between services. Contract: docs/ARCHITECTURE.md section 5.
-- Fire only from the owning service; anyone may connect.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Signal"))

return {
	-- EnemyService: (id: number, kind: number, x: number, z: number, killer: Player?, isElite: boolean)
	EnemyKilled = Signal.new(),
	-- StatsService: (player: Player, level: number)
	PlayerLeveledUp = Signal.new(),
	-- RunManager: (players: {Player}, worldId: string, tier: number)
	RunStarted = Signal.new(),
	-- RunManager: (stage: number, worldId: string)
	StageStarted = Signal.new(),
	-- RunManager: (position: Vector3)
	BossRevealed = Signal.new(),
	-- BossService: (bossId: string, stage: number)
	BossDefeated = Signal.new(),
	-- RunManager: ()
	FinalWaveStarted = Signal.new(),
	-- RunManager: (summaries: { [Player]: RunSummary }) -- see Types.RunSummary
	RunEnded = Signal.new(),
	-- RunManager: (player: Player)
	PlayerDowned = Signal.new(),
	-- RunManager: (player: Player, rescuer: Player)
	PlayerRevived = Signal.new(),
	-- RunManager: (player: Player)
	PlayerDied = Signal.new(),
	-- RunManager: (player: Player, amount: number)
	PlayerDamaged = Signal.new(),
	-- LootService: (player: Player, chestKind: string)
	ChestOpened = Signal.new(),
	-- ShrineService: (players: {Player}, shrineKind: string)
	ShrineCompleted = Signal.new(),
	-- CompanionService: (player: Player, stage: number)
	CompanionEvolved = Signal.new(),
	-- DataService: (player: Player)
	ProfileLoaded = Signal.new(),
}
