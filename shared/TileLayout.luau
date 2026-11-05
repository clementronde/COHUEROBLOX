--!strict
-- Tuiles faites main -> données de stage (docs/dossier/21-tuiles-assemblage.md, A02-01 / A02-04).
-- Partagé serveur et client : lit les modèles de ReplicatedStorage.Assets.Worlds.<WorldId>,
-- décode la disposition publiée par le serveur (5e champ de la clé de stage) et produit un Layout
-- au format de Heightmap (plateaux, rampes, tremplins, Arche, points de butin...).
-- Le tirage lui-même est côté serveur (server/Services/WorldBuilder.luau) : le client ne fait que
-- relire la disposition, il ne retire jamais au sort.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = script.Parent:WaitForChild("Config")
local Tiles = require(Config:WaitForChild("Tiles"))
local Run = require(Config:WaitForChild("Run"))

-- Côtés : 0 = N (-Z), 1 = E (+X), 2 = S (+Z), 3 = W (-X).
local SIDE_NAMES = { "EdgeN", "EdgeE", "EdgeS", "EdgeW" }

export type GroundPiece = { cf: CFrame, size: Vector3, ramp: boolean }
export type MarkerPiece = { name: string, cf: CFrame, size: Vector3, height: number? }
export type TileDef = {
	name: string,
	model: Model,
	kind: string, -- Field | Spawn | Arena | Border | BorderCorner
	cells: number,
	edges: { { string } }, -- [side + 1] = segments dans le sens horaire
	weight: number,
	maxCount: number,
	rotate: boolean,
	boss: string?,
	radius: number?,
	ground: { GroundPiece },
	markers: { MarkerPiece },
}
export type Catalogue = {
	folder: Instance,
	byName: { [string]: TileDef },
	list: { TileDef }, -- triées par nom (ordre stable sur toutes les machines)
}
export type Placement = { i: number, j: number, r: number, name: string }
export type Plan = { grid: number, placements: { Placement } }

local TileLayout = {}

local cache: { [string]: Catalogue } = {}

local function warnOnce(seen: { [string]: boolean }, msg: string)
	if not seen[msg] then
		seen[msg] = true
		warn(msg)
	end
end
local warned: { [string]: boolean } = {}

function TileLayout.worldFolder(worldId: string): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local worlds = assets and assets:FindFirstChild("Worlds")
	return worlds and worlds:FindFirstChild(worldId)
end

local function parseEdges(model: Model, cells: number): { { string } }
	local out = {}
	for side = 1, 4 do
		local raw = model:GetAttribute(SIDE_NAMES[side])
		local segs: { string } = {}
		if type(raw) == "string" and raw ~= "" then
			for _, s in string.split(raw, ",") do
				local v = string.gsub(s, "%s", "")
				if not Tiles.Compat[v] then
					warnOnce(warned, `[TileLayout] {model:GetFullName()} : connecteur inconnu "{v}" ({SIDE_NAMES[side]})`)
				end
				table.insert(segs, v)
			end
		end
		if #segs == 0 then
			segs = { "Open" }
		end
		if #segs ~= cells then
			if #segs ~= 1 then
				warnOnce(warned, `[TileLayout] {model:GetFullName()} : {SIDE_NAMES[side]} a {#segs} valeurs pour {cells} cases`)
			end
			local first = segs[1]
			segs = {}
			for _ = 1, cells do
				table.insert(segs, first)
			end
		end
		out[side] = segs
	end
	return out
end

local function readTile(model: Model): TileDef?
	local kind = model:GetAttribute("Kind")
	if type(kind) ~= "string" then
		return nil
	end
	if string.find(model.Name, "[|;,]") then
		warnOnce(warned, `[TileLayout] nom de tuile interdit (| ; ,) : {model:GetFullName()}`)
		return nil
	end
	local cellsAttr = model:GetAttribute("Cells")
	local cells = if type(cellsAttr) == "number" then math.max(1, math.floor(cellsAttr)) elseif kind == "Arena" then 2 else 1
	local pivot = model:GetPivot()
	local def: TileDef = {
		name = model.Name,
		model = model,
		kind = kind,
		cells = cells,
		edges = parseEdges(model, cells),
		weight = (function()
			local w = model:GetAttribute("Weight")
			return if type(w) == "number" and w > 0 then w else 1
		end)(),
		maxCount = (function()
			local m = model:GetAttribute("MaxCount")
			return if type(m) == "number" then m else math.huge
		end)(),
		rotate = model:GetAttribute("Rotate") ~= false,
		boss = (function()
			local b = model:GetAttribute("Boss")
			return if type(b) == "string" then b else nil
		end)(),
		radius = (function()
			local r = model:GetAttribute("Radius")
			return if type(r) == "number" then r else nil
		end)(),
		ground = {},
		markers = {},
	}
	local ground = model:FindFirstChild("Ground")
	if ground then
		for _, d in ground:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("Ground") ~= false then
				table.insert(def.ground, { cf = pivot:ToObjectSpace(d.CFrame), size = d.Size, ramp = d:IsA("WedgePart") })
			end
		end
	elseif kind ~= "Border" and kind ~= "BorderCorner" then
		warnOnce(warned, `[TileLayout] {model:GetFullName()} n'a pas de dossier Ground : sol plat`)
	end
	local markers = model:FindFirstChild("Markers")
	if markers then
		for _, d in markers:GetDescendants() do
			if d:IsA("BasePart") then
				local h = d:GetAttribute("Height")
				table.insert(def.markers, {
					name = d.Name,
					cf = pivot:ToObjectSpace(d.CFrame),
					size = d.Size,
					height = if type(h) == "number" then h else nil,
				})
			end
		end
	end
	return def
end

-- Catalogue des tuiles d'un monde (lu une fois, puis en cache). nil si le monde n'a pas de tuiles.
function TileLayout.catalogue(worldId: string): Catalogue?
	local folder = TileLayout.worldFolder(worldId)
	if not folder then
		return nil
	end
	local cached = cache[worldId]
	if cached and cached.folder == folder then
		return cached
	end
	local cat: Catalogue = { folder = folder, byName = {}, list = {} }
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			local def = readTile(child)
			if def then
				if cat.byName[def.name] then
					warnOnce(warned, `[TileLayout] deux tuiles nommées {def.name} dans {folder:GetFullName()}`)
				else
					cat.byName[def.name] = def
					table.insert(cat.list, def)
				end
			end
		end
	end
	table.sort(cat.list, function(a, b)
		return a.name < b.name
	end)
	if #cat.list == 0 then
		return nil
	end
	cache[worldId] = cat
	return cat
end

function TileLayout.gridFor(worldId: string): number
	local w = Tiles.Worlds[worldId]
	return if w then w.grid else Tiles.DefaultGrid
end

-- CFrame du pivot d'une tuile posée à l'ancre (i, j) (case nord-ouest), rotation r quarts de tour
-- dans le sens horaire vu du dessus (N -> E -> S -> W).
function TileLayout.tileFrame(grid: number, i: number, j: number, cells: number, r: number): CFrame
	local t = Tiles.CellSize
	local half = grid * t / 2
	local cx = -half + t * (i + cells / 2)
	local cz = -half + t * (j + cells / 2)
	return CFrame.new(cx, 0, cz) * CFrame.Angles(0, -r * math.pi / 2, 0)
end

-- Segments du côté monde `side` (0-3) d'une tuile tournée de r.
function TileLayout.sideSegments(def: TileDef, side: number, r: number): { string }
	return def.edges[(side - r) % 4 + 1]
end

-- Case de la tuile (ancre i0, j0, taille c) qui porte le segment k (0-based) du côté monde `side`,
-- et la case voisine de l'autre côté de ce bord.
function TileLayout.sideCell(i0: number, j0: number, c: number, side: number, k: number): (number, number, number, number)
	if side == 0 then
		return i0 + k, j0, i0 + k, j0 - 1
	elseif side == 1 then
		return i0 + c - 1, j0 + k, i0 + c, j0 + k
	elseif side == 2 then
		return i0 + c - 1 - k, j0 + c - 1, i0 + c - 1 - k, j0 + c
	end
	return i0, j0 + c - 1 - k, i0 - 1, j0 + c - 1 - k
end

function TileLayout.encode(plan: Plan): string
	local parts = { tostring(plan.grid) }
	for _, p in plan.placements do
		table.insert(parts, `{p.i},{p.j},{p.r},{p.name}`)
	end
	return table.concat(parts, ";")
end

function TileLayout.decode(code: string): Plan?
	local parts = string.split(code, ";")
	local grid = tonumber(parts[1])
	if not grid then
		return nil
	end
	local plan: Plan = { grid = grid, placements = {} }
	for index = 2, #parts do
		local f = string.split(parts[index], ",")
		local i, j, r, name = tonumber(f[1]), tonumber(f[2]), tonumber(f[3]), f[4]
		if not (i and j and r and name) then
			return nil
		end
		table.insert(plan.placements, { i = i, j = j, r = r, name = name })
	end
	return plan
end

-- Pièces de sol --------------------------------------------------------------------------------

local function boxOf(cf: CFrame, size: Vector3)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	local ex = math.abs(r00) * size.X + math.abs(r01) * size.Y + math.abs(r02) * size.Z
	local ey = math.abs(r10) * size.X + math.abs(r11) * size.Y + math.abs(r12) * size.Z
	local ez = math.abs(r20) * size.X + math.abs(r21) * size.Y + math.abs(r22) * size.Z
	return { x = x, z = z, sx = ex, sz = ez, base = y - ey / 2, h = y + ey / 2 }
end

-- WedgePart : monte vers son +Z local (même convention que l'ancien StageService).
local function rampOf(cf: CFrame, size: Vector3)
	local rise = cf:VectorToWorldSpace(Vector3.zAxis)
	local dir
	if math.abs(rise.X) > math.abs(rise.Z) then
		dir = if rise.X > 0 then 1 else 2
	else
		dir = if rise.Z > 0 then 3 else 4
	end
	local p = cf.Position
	return { x = p.X, z = p.Z, width = size.X, length = size.Z, base = p.Y - size.Y / 2, h = p.Y + size.Y / 2, dir = dir }
end

-- Heightmap passé en argument (pas de require : Heightmap requiert ce module).
export type HeightmapLike = { _buildGrid: (layout: any) -> (), getY: (x: number, z: number) -> number }

-- Construit le Layout d'un stage à partir de sa disposition. nil si une tuile manque.
function TileLayout.build(worldId: string, stage: number, seed: number, bossId: string, code: string, hm: HeightmapLike): any
	local cat = TileLayout.catalogue(worldId)
	local plan = TileLayout.decode(code)
	if not (cat and plan) then
		warnOnce(warned, `[TileLayout] tuiles introuvables pour {worldId} : sol plat`)
		return nil
	end
	local grid = plan.grid
	local size = grid * Tiles.CellSize
	local layout = {
		key = "",
		worldId = worldId,
		stage = stage,
		seed = seed,
		bossId = bossId,
		size = size,
		plateaus = {},
		ramps = {},
		pads = {},
		decor = {},
		lamps = {},
		arche = { x = 0, z = 0, y = 0 },
		arenaRadius = Run.ArenaRadius,
		pillars = {},
		weakPoints = {},
		spawnPoints = {} :: { [string]: { { x: number, z: number, y: number } } },
		portal = nil :: { x: number, z: number, y: number }?,
		tiles = code,
	}
	local playerMarks: { Vector3 } = {}
	local spawnCentre = Vector3.zero
	local candidates: { [string]: { Vector3 } } = {}
	local archeSet = false

	for _, p in plan.placements do
		local def = cat.byName[p.name]
		if not def then
			warnOnce(warned, `[TileLayout] tuile {p.name} absente de {cat.folder:GetFullName()}`)
			return nil
		end
		local cf = TileLayout.tileFrame(grid, p.i, p.j, def.cells, p.r)
		for _, g in def.ground do
			local wcf = cf * g.cf
			if g.ramp and wcf.UpVector.Y > 0.7 then
				table.insert(layout.ramps, rampOf(wcf, g.size))
			else
				local b = boxOf(wcf, g.size)
				if b.h > 0.05 then -- le sol plat (dessus à Y = 0) ne change pas la grille
					table.insert(layout.plateaus, b)
				end
			end
		end
		if def.kind == "Spawn" then
			spawnCentre = cf.Position
		elseif def.kind == "Arena" then
			layout.arche = { x = cf.X, z = cf.Z, y = 0 }
			layout.arenaRadius = def.radius or Run.ArenaRadius
		end
		for _, m in def.markers do
			local wcf = cf * m.cf
			local pos = wcf.Position
			local name = m.name
			if name == "Player" then
				table.insert(playerMarks, pos)
			elseif name == "Arche" then
				layout.arche = { x = pos.X, z = pos.Z, y = 0 }
				archeSet = true
			elseif name == "Portal" then
				layout.portal = { x = pos.X, z = pos.Z, y = 0 }
			elseif name == "WeakPoint" then
				table.insert(layout.weakPoints, { x = pos.X, z = pos.Z, y = 0 })
			elseif name == "Pillar" then
				table.insert(layout.pillars, { x = pos.X, z = pos.Z, r = math.max(m.size.X, m.size.Z) / 2, h = m.size.Y })
			elseif name == "JumpPad" then
				local look = wcf.LookVector
				local flat = Vector3.new(look.X, 0, look.Z)
				flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.xAxis
				table.insert(layout.pads, { x = pos.X, z = pos.Z, y = 0, dirX = flat.X, dirZ = flat.Z, h = m.height or 10 })
			elseif name == "Lamp" then
				table.insert(layout.lamps, { x = pos.X, z = pos.Z, y = 0 })
			elseif Tiles.SpawnPoints[name] then
				local list = candidates[name]
				if not list then
					list = {}
					candidates[name] = list
				end
				table.insert(list, pos)
			end
		end
	end
	if not archeSet and layout.arche.x == 0 and layout.arche.z == 0 then
		warnOnce(warned, `[TileLayout] {worldId} : aucune arène dans la disposition`)
	end

	hm._buildGrid(layout)
	local getY = hm.getY

	-- Hauteurs réelles des points (posés au sol de la grille).
	for _, list in { layout.pads, layout.lamps, layout.weakPoints } :: { { { x: number, z: number, y: number } } } do
		for _, pt in list do
			pt.y = getY(pt.x, pt.z)
		end
	end
	local portal = layout.portal
	if portal then
		portal.y = getY(portal.x, portal.z)
	end

	-- Joueurs : les marqueurs de la tuile d'apparition (complétés en croix autour du centre).
	local players = {}
	for _, pos in playerMarks do
		table.insert(players, { x = pos.X, z = pos.Z, y = getY(pos.X, pos.Z) })
	end
	local k = 0
	while #players < 4 do
		local a = k * math.pi / 2
		local x, z = spawnCentre.X + math.cos(a) * 8, spawnCentre.Z + math.sin(a) * 8
		table.insert(players, { x = x, z = z, y = getY(x, z) })
		k += 1
	end
	layout.spawnPoints.Player = players

	-- Butin : on mélange les candidats (graine + 13), puis on garde les plus espacés.
	local rng = Random.new(seed + 13)
	local ax, az = layout.arche.x, layout.arche.z
	local keep = layout.arenaRadius + Tiles.ArenaKeepMargin
	local taken: { Vector3 } = {}
	local kinds = {}
	for kind in Tiles.SpawnPoints do
		table.insert(kinds, kind)
	end
	-- Les rares d'abord (autels, marchands), pour qu'ils prennent les meilleures places.
	table.sort(kinds, function(a, b)
		local ga, gb = Tiles.SpawnPoints[a].gap, Tiles.SpawnPoints[b].gap
		return if ga ~= gb then ga > gb else a < b
	end)
	for _, kind in kinds do
		local rule = Tiles.SpawnPoints[kind]
		local list = table.clone(candidates[kind] or {})
		for n = #list, 2, -1 do
			local m = rng:NextInteger(1, n)
			list[n], list[m] = list[m], list[n]
		end
		local out = {}
		for _, pos in list do
			if #out >= rule.count then
				break
			end
			local dx, dz = pos.X - ax, pos.Z - az
			if dx * dx + dz * dz < keep * keep then
				continue
			end
			local ok = true
			for _, t in taken do
				local tx, tz = pos.X - t.X, pos.Z - t.Z
				if tx * tx + tz * tz < rule.gap * rule.gap then
					ok = false
					break
				end
			end
			if ok then
				table.insert(taken, pos)
				table.insert(out, { x = pos.X, z = pos.Z, y = getY(pos.X, pos.Z) })
			end
		end
		layout.spawnPoints[kind] = out
	end
	return layout
end

return TileLayout
