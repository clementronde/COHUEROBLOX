--!strict
-- Server-wide events between services. Contract: docs/ARCHITECTURE.md section 5.
-- Fire only from the owning service; anyone may connect.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Signal"))

return {
	-- EnemyService: (id: number, kind: number, x: number, z: number, killer: Player?, isElite: boolean, hordeElite: boolean)
	-- isElite = élite « à butin » (coffre). hordeElite = élite de l'Overtime au-delà du plafond
	-- classique : une vraie élite (XP, quêtes) mais sans coffre. Une élite est isElite or hordeElite.
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
	-- RunManager: (player: Player, amount: number, source: string) -- source "Contact" = mêlée
	PlayerDamaged = Signal.new(),
	-- RunManager (A04-v3, demande A05) : (player: Player, source: string). Tout coup reçu par un
	-- joueur actif, tiré au début de damagePlayer, avant invulnérabilité, parade, esquive et bouclier.
	-- Jamais pendant le gel du passage de niveau (aucun coup n'existe alors).
	PlayerHit = Signal.new(),
	-- RunManager (A04-v3) : (frozen: boolean, pausedSeconds: number). true au début du gel du
	-- passage de niveau, false à la reprise avec la durée du gel (pour décaler ses minuteries).
	RunFrozen = Signal.new(),
	-- RunManager (A04-v3) : (player: Player, summary: RunSummary). Un joueur quitte la run en
	-- Cash out pendant que les autres continuent (Keep going). Sa run est finie : nettoyer ce qui
	-- lui appartient (compagnon, offres). Le dernier à partir déclenche RunEnded comme avant.
	PlayerCashedOut = Signal.new(),
	-- LootService: (player: Player, chestKind: string)
	ChestOpened = Signal.new(),
	-- ShrineService: (players: {Player}, shrineKind: string)
	ShrineCompleted = Signal.new(),
	-- CompanionService: (player: Player, stage: number)
	CompanionEvolved = Signal.new(),
	-- DataService: (player: Player)
	ProfileLoaded = Signal.new(),
	-- StatsService (A04-03): (player: Player, runKills: number, enemyKind: number, isElite: boolean)
	-- Un KO compté par le serveur, déjà ajouté au total de la run. Aucune valeur ne vient du client.
	KOScored = Signal.new(),
}
