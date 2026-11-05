--!strict
-- Tuiles et assemblage semi-procédural (docs/dossier/21-tuiles-assemblage.md). Domaine run, A02.

local Tiles = {
	-- Côté d'une case en studs. Une tuile normale = 1 case, l'arène = 2 x 2 cases.
	CellSize = 80,
	-- Taille de grille par monde (cases par côté). La carte fait grid x CellSize studs de côté.
	Worlds = {
		BoisGrognon = { grid = 7 },
		DunesCroustillantes = { grid = 7 },
		RecreFantome = { grid = 7 },
	} :: { [string]: { grid: number } },
	DefaultGrid = 7,

	-- Compatibilité des connecteurs de bord : Compat[a][b] = true si deux cases voisines peuvent
	-- avoir a et b face à face. Passage : aucun des deux côtés n'est "Wall".
	Compat = {
		Open = { Open = true, Path = true, Wall = true },
		Path = { Open = true, Path = true },
		Wall = { Open = true, Wall = true },
	} :: { [string]: { [string]: boolean } },
	Blocking = { Wall = true } :: { [string]: boolean },

	MaxAttempts = 40, -- essais de tirage avant d'abandonner
	MinReachable = 0.85, -- part des cases atteignables depuis l'apparition
	MinArenaDistance = 180, -- distance mini centre de carte -> centre de l'arène

	-- Points de butin : nombre gardé et écart minimal (studs) parmi les marqueurs des tuiles.
	SpawnPoints = {
		Shrine = { count = 8, gap = 50 },
		Chest = { count = 18, gap = 22 },
		Pot = { count = 40, gap = 10 },
		Merchant = { count = 2, gap = 40 },
	} :: { [string]: { count: number, gap: number } },
	ArenaKeepMargin = 14, -- pas de butin à moins de rayon d'arène + marge du centre de l'arène

	PartBudget = 6000, -- avertissement au-delà (Parts posées par monde)

	-- true : sans tuiles pour un monde (ou tirage impossible), StageService reconstruit l'ancienne
	-- carte en Parts et le signale. Passer à false une fois les tuiles posées dans COHUE.
	LegacyFallback = true,

	-- Portails (A02-08)
	PortalTemplates = { NextWorld = "PortalNextWorld", CashOut = "PortalCashOut" },
	TransitionSeconds = 1.5, -- fondu au noir entre deux mondes
}

return Tiles
