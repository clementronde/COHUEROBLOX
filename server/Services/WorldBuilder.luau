--!strict
-- Assemblage semi-procédural des mondes (docs/dossier/21-tuiles-assemblage.md, A02-01).
-- Module simple (pas un service démarré) appelé par StageService.buildStage :
--   1. plan(worldId, seed, bossId) tire une disposition (tuiles + rotations) avec la graine ;
--   2. la disposition part dans la clé de stage : Heightmap (via TileLayout) en tire le sol de la horde
--      sur le serveur et sur chaque client ;
--   3. build(code, worldId, parent) clone les tuiles faites main et l'anneau de bordure.
-- Le code clone et place, il ne fabrique rien (01-decisions-v2.md section 12).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Tiles = require(Config:WaitForChild("Tiles"))
local TileLayout = require(Shared:WaitForChild("TileLayout"))

type TileDef = TileLayout.TileDef
type Placement = TileLayout.Placement

local WorldBuilder = {}

-- Grille de travail du tirage ---------------------------------------------------------------

type Board = {
	grid: number,
	owner: { [number]: number }, -- case -> index de placement
	edges: { [number]: { [number]: string } }, -- case -> côté monde -> connecteur
	placements: { Placement },
	defs: { TileDef }, -- parallèle à placements
	counts: { [string]: number },
}

local function newBoard(grid: number): Board
	return { grid = grid, owner = {}, edges = {}, placements = {}, defs = {}, counts = {} }
end

local function inside(b: Board, i: number, j: number): boolean
	return i >= 0 and j >= 0 and i < b.grid and j < b.grid
end

local function cellId(b: Board, i: number, j: number): number
	return j * b.grid + i
end

local function compatible(a: string, c: string): boolean
	local row = Tiles.Compat[a]
	return row ~= nil and row[c] == true
end

local function fits(b: Board, def: TileDef, i0: number, j0: number, r: number): boolean
	local c = def.cells
	for di = 0, c - 1 do
		for dj = 0, c - 1 do
			if not inside(b, i0 + di, j0 + dj) or b.owner[cellId(b, i0 + di, j0 + dj)] then
				return false
			end
		end
	end
	for side = 0, 3 do
		local segs = TileLayout.sideSegments(def, side, r)
		for k = 0, c - 1 do
			local _, _, ni, nj = TileLayout.sideCell(i0, j0, c, side, k)
			if inside(b, ni, nj) then
				local n = cellId(b, ni, nj)
				if b.owner[n] then
					local other = b.edges[n][(side + 2) % 4]
					if not compatible(segs[k + 1], other) then
						return false
					end
				end
			end
		end
	end
	return true
end

local function place(b: Board, def: TileDef, i0: number, j0: number, r: number)
	table.insert(b.placements, { i = i0, j = j0, r = r, name = def.name })
	table.insert(b.defs, def)
	local index = #b.placements
	b.counts[def.name] = (b.counts[def.name] or 0) + 1
	local c = def.cells
	for di = 0, c - 1 do
		for dj = 0, c - 1 do
			local id = cellId(b, i0 + di, j0 + dj)
			b.owner[id] = index
			b.edges[id] = {}
		end
	end
	for side = 0, 3 do
		local segs = TileLayout.sideSegments(def, side, r)
		for k = 0, c - 1 do
			local ci, cj = TileLayout.sideCell(i0, j0, c, side, k)
			b.edges[cellId(b, ci, cj)][side] = segs[k + 1]
		end
	end
end

local function rotations(def: TileDef): { number }
	return if def.rotate then { 0, 1, 2, 3 } else { 0 }
end

-- Toutes les cases atteignables depuis `start` (bords non bloquants des deux côtés).
local function reachable(b: Board, start: number): { [number]: boolean }
	local seen = { [start] = true }
	local queue = { start }
	local head = 1
	local DI = { [0] = 0, 1, 0, -1 }
	local DJ = { [0] = -1, 0, 1, 0 }
	while head <= #queue do
		local id = queue[head]
		head += 1
		local i, j = id % b.grid, id // b.grid
		for side = 0, 3 do
			local ni, nj = i + DI[side], j + DJ[side]
			if not inside(b, ni, nj) then
				continue
			end
			local n = cellId(b, ni, nj)
			if seen[n] or not b.owner[n] then
				continue
			end
			local same = b.owner[n] == b.owner[id]
			if same or (not Tiles.Blocking[b.edges[id][side]] and not Tiles.Blocking[b.edges[n][(side + 2) % 4]]) then
				seen[n] = true
				table.insert(queue, n)
			end
		end
	end
	return seen
end

local function pickWeighted(rng: Random, options: { { def: TileDef, r: number } }): { def: TileDef, r: number }?
	local total = 0
	for _, o in options do
		total += o.def.weight
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber(0, total)
	for _, o in options do
		roll -= o.def.weight
		if roll <= 0 then
			return o
		end
	end
	return options[#options]
end

local function byKind(cat: TileLayout.Catalogue, kind: string): { TileDef }
	local out = {}
	for _, def in cat.list do
		if def.kind == kind then
			table.insert(out, def)
		end
	end
	return out
end

local function attempt(cat: TileLayout.Catalogue, grid: number, seed: number, try: number, bossId: string): (Board?, string?)
	local b = newBoard(grid)
	local rng = Random.new(seed + 12 + 100 * try)
	local rngArena = Random.new(seed + 11 + 100 * try)

	-- 1. Apparition au centre.
	local spawns = byKind(cat, "Spawn")
	if #spawns == 0 then
		return nil, "aucune tuile Spawn"
	end
	local spawnDef = spawns[rng:NextInteger(1, #spawns)]
	local centre = grid // 2 - (spawnDef.cells - 1) // 2
	local rots = rotations(spawnDef)
	place(b, spawnDef, centre, centre, rots[rng:NextInteger(1, #rots)])
	local spawnCell = cellId(b, centre, centre)

	-- 2. Arène du boss dans un coin (même tuile à chaque run pour ce boss).
	local arenas = byKind(cat, "Arena")
	local forBoss = {}
	for _, def in arenas do
		if def.boss == bossId then
			table.insert(forBoss, def)
		end
	end
	if #forBoss == 0 then
		forBoss = arenas
	end
	if #forBoss == 0 then
		return nil, "aucune tuile Arena"
	end
	local arenaDef = forBoss[rngArena:NextInteger(1, #forBoss)]
	local c = arenaDef.cells
	local slots = { { 0, 0 }, { grid - c, 0 }, { grid - c, grid - c }, { 0, grid - c } }
	for n = #slots, 2, -1 do
		local m = rngArena:NextInteger(1, n)
		slots[n], slots[m] = slots[m], slots[n]
	end
	local placed = false
	for _, s in slots do
		local f = TileLayout.tileFrame(grid, s[1], s[2], c, 0)
		if f.Position.Magnitude < Tiles.MinArenaDistance then
			continue
		end
		for _, r in rotations(arenaDef) do
			if fits(b, arenaDef, s[1], s[2], r) then
				place(b, arenaDef, s[1], s[2], r)
				placed = true
				break
			end
		end
		if placed then
			break
		end
	end
	if not placed then
		return nil, "arène impossible à placer (grille trop petite ?)"
	end
	local arenaCell = cellId(b, b.placements[#b.placements].i, b.placements[#b.placements].j)

	-- 3. Les autres cases, ligne par ligne.
	local fields = byKind(cat, "Field")
	if #fields == 0 then
		return nil, "aucune tuile Field"
	end
	for j = 0, grid - 1 do
		for i = 0, grid - 1 do
			if b.owner[cellId(b, i, j)] then
				continue
			end
			local options = {}
			for _, def in fields do
				if (b.counts[def.name] or 0) >= def.maxCount then
					continue
				end
				for _, r in rotations(def) do
					if fits(b, def, i, j, r) then
						table.insert(options, { def = def, r = r })
					end
				end
			end
			local pick = pickWeighted(rng, options)
			if not pick then
				return nil, `case {i},{j} sans tuile compatible`
			end
			place(b, pick.def, i, j, pick.r)
		end
	end

	-- 4. Connexité : arène atteignable, et assez de cases.
	local seen = reachable(b, spawnCell)
	if not seen[arenaCell] then
		return nil, "arène inatteignable"
	end
	local n = 0
	for _ in seen do
		n += 1
	end
	if n < Tiles.MinReachable * grid * grid then
		return nil, `{n} cases atteignables sur {grid * grid}`
	end
	return b, nil
end

-- Tire une disposition pour ce monde. nil si le monde n'a pas de tuiles ou si le tirage échoue.
function WorldBuilder.plan(worldId: string, seed: number, bossId: string): string?
	local cat = TileLayout.catalogue(worldId)
	if not cat then
		return nil
	end
	local grid = TileLayout.gridFor(worldId)
	local lastWhy = "?"
	for try = 0, Tiles.MaxAttempts - 1 do
		local b, why = attempt(cat, grid, seed, try, bossId)
		if b then
			return TileLayout.encode({ grid = grid, placements = b.placements })
		end
		lastWhy = why or lastWhy
	end
	warn(`[WorldBuilder] {worldId} : tirage impossible après {Tiles.MaxAttempts} essais ({lastWhy})`)
	return nil
end

local function cloneTile(def: TileDef, cf: CFrame, parent: Instance): number
	local clone = def.model:Clone()
	local markers = clone:FindFirstChild("Markers")
	if markers then
		markers:Destroy()
	end
	clone:PivotTo(cf)
	local parts = 0
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	clone.Parent = parent
	return parts
end

-- Pose les tuiles de la disposition (et la bordure) sous `parent`. Renvoie le nombre de Parts.
function WorldBuilder.build(code: string, worldId: string, parent: Instance): number
	local cat = TileLayout.catalogue(worldId)
	local plan = TileLayout.decode(code)
	if not (cat and plan) then
		warn(`[WorldBuilder] {worldId} : disposition illisible`)
		return 0
	end
	local grid = plan.grid
	local parts = 0
	for _, p in plan.placements do
		local def = cat.byName[p.name]
		if def then
			parts += cloneTile(def, TileLayout.tileFrame(grid, p.i, p.j, def.cells, p.r), parent)
		else
			warn(`[WorldBuilder] tuile {p.name} manquante`)
		end
	end

	-- Bordure : le côté N d'une Border regarde la carte ; N et E d'une BorderCorner aussi.
	local borders = byKind(cat, "Border")
	local corners = byKind(cat, "BorderCorner")
	local function pick(list: { TileDef }, i: number, j: number): TileDef?
		if #list == 0 then
			return nil
		end
		return list[(math.abs(i * 7 + j * 13) % #list) + 1]
	end
	local function put(list: { TileDef }, i: number, j: number, r: number)
		local def = pick(list, i, j)
		if def then
			parts += cloneTile(def, TileLayout.tileFrame(grid, i, j, 1, r), parent)
		end
	end
	for k = 0, grid - 1 do
		put(borders, k, -1, 2) -- rangée nord, regarde le sud
		put(borders, grid, k, 3) -- colonne est, regarde l'ouest
		put(borders, k, grid, 0) -- rangée sud, regarde le nord
		put(borders, -1, k, 1) -- colonne ouest, regarde l'est
	end
	put(corners, -1, -1, 1)
	put(corners, grid, -1, 2)
	put(corners, grid, grid, 3)
	put(corners, -1, grid, 0)

	if parts > Tiles.PartBudget then
		warn(`[WorldBuilder] {worldId} : {parts} Parts, au-dessus du budget de {Tiles.PartBudget}`)
	end
	return parts
end

return WorldBuilder
