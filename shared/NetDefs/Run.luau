--!strict
-- Run-domain internal remotes (docs/dossier/20-run-mondes-boss.md section 7).
return {
	EnemyProjectiles = "RemoteEvent", -- S->C buffer, EnemyCodec.encodeProjectiles
	SelectStage = "RemoteEvent", -- C->S (worldId: string, tier: number)
}
