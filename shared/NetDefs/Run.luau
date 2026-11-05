--!strict
-- Run-domain internal remotes (docs/dossier/20-run-mondes-boss.md section 7).
return {
	EnemyAttackVisual = "UnreliableRemoteEvent", -- S->C cosmetic attack cues
	EnemyProjectiles = "RemoteEvent", -- S->C buffer, EnemyCodec.encodeProjectiles
	EnemyCapturable = "RemoteEvent", -- S->C (id: number, on: boolean) variante capturable (A03-03), hors EnemyCodec
	SelectStage = "RemoteEvent", -- C->S (worldId: string, tier: number)
}
