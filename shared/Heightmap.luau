--!strict
-- Stage layout + ground height, shared by server and client (doc 12.2, dossier 20 section 3).
--
-- The layout is generated deterministically from (worldId, stage, seed, bossId) with one
-- Random per purpose, so server and clients build the exact same features and height grid.
-- The server publishes the key in the Workspace attribute "CohueStageKey"; clients rebuild
-- from it and never depend on streamed Parts (vault: "Procedural World Generation",
-- "Instance Streaming").
--
-- Height grid: 2-stud cells in a buffer of f32, bilinear lookup. No raycast per enemy per tick.
-- Before any stage exists, getY returns 0 (flat Baseplate).

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = script.Parent:WaitForChild("Config")
local Worlds = require(Config:WaitForChild("Worlds"))
local Run = require(Config:WaitForChild("Run"))

local CELL = 2
local ATTRIBUTE = "CohueStageKey"

export type Box = { x: number, z: number, sx: number, sz: number, base: number, h: number }
-- Ramp footprint centred on (x, z): rises from `base` at the low end to `h` at the high end.
-- dir: 1 = rises toward +X, 2 = toward -X, 3 = toward +Z, 4 = toward -Z
export type Ramp = { x: number, z: number, width: number, length: number, base: number, h: number, dir: number }
export type Pad = { x: number, z: number, y: number, dirX: number, dirZ: number, h: number }
export type Decor = { kind: string, x: number, z: number, s: number, rot: number }
export type Point = { x: number, z: number, y: number }

export type Layout = {
	key: string,
	worldId: string,
	stage: number,
	seed: number,
	bossId: string,
	size: number,
	plateaus: { Box },
	ramps: { Ramp },
	pads: { Pad },
	decor: { Decor },
	lamps: { Point },
	arche: Point,
	arenaRadius: number,
	pillars: { { x: number, z: number, r: number, h: number } },
	weakPoints: { Point },
	spawnPoints: { [string]: { Point } },
}

local Heightmap = {}

local current: Layout? = nil
local grid: buffer? = nil
local gridN = 0
local gridOrigin = 0

local function boxesOverlap(a: Box, b: Box, pad: number): boolean
	return math.abs(a.x - b.x) * 2 < a.sx + b.sx + pad * 2 and math.abs(a.z - b.z) * 2 < a.sz + b.sz + pad * 2
end

local function inCircle(x: number, z: number, cx: number, cz: number, r: number): boolean
	local dx, dz = x - cx, z - cz
	return dx * dx + dz * dz < r * r
end

-- Footprint of a ramp as a box (for overlap tests).
local function rampBox(r: Ramp): Box
	local alongX = r.dir <= 2
	return {
		x = r.x,
		z = r.z,
		sx = if alongX then r.length else r.width,
		sz = if alongX then r.width else r.length,
		base = r.base,
		h = r.h,
	}
end

-- Ramp attached to side `side` of box b, rising from `base` to b.h (the box top).
local function rampFor(b: Box, side: number, base: number, width: number): Ramp
	local length = math.max(6, (b.h - base) * 2.2)
	if side == 1 then -- on the -X side, rising toward +X
		return { x = b.x - b.sx / 2 - length / 2, z = b.z, width = width, length = length, base = base, h = b.h, dir = 1 }
	elseif side == 2 then
		return { x = b.x + b.sx / 2 + length / 2, z = b.z, width = width, length = length, base = base, h = b.h, dir = 2 }
	elseif side == 3 then
		return { x = b.x, z = b.z - b.sz / 2 - length / 2, width = width, length = length, base = base, h = b.h, dir = 3 }
	end
	return { x = b.x, z = b.z + b.sz / 2 + length / 2, width = width, length = length, base = base, h = b.h, dir = 4 }
end

local function generate(worldId: string, stage: number, seed: number, bossId: string): Layout
	local world = Worlds[worldId] or Worlds[Run.DefaultWorld]
	local size = world.size
	local half = size / 2
	local margin = 24
	local rngArche = Random.new(seed)
	local rngTerrain = Random.new(seed + 1)
	local rngDecor = Random.new(seed + 2)
	local rngSpawn = Random.new(seed + 3)

	local layout: Layout = {
		key = "",
		worldId = world.id,
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
		spawnPoints = {},
	}

	-- Arche (boss arena centre): far from the centre, inside the map.
	local angle = rngArche:NextNumber(0, math.pi * 2)
	local dist = math.clamp(half * rngArche:NextNumber(0.6, 0.68), 180, half - Run.ArenaRadius - margin)
	local ax, az = math.cos(angle) * dist, math.sin(angle) * dist
	layout.arche = { x = ax, z = az, y = 0 }
	local arenaKeep = Run.ArenaRadius + 14
	local centreKeep = 44

	local solids: { Box } = {} -- plateaus and ramp footprints, for overlap tests
	local function free(b: Box, pad: number): boolean
		if math.abs(b.x) + b.sx / 2 > half - margin or math.abs(b.z) + b.sz / 2 > half - margin then
			return false
		end
		local r = math.max(b.sx, b.sz) / 2
		if inCircle(b.x, b.z, ax, az, arenaKeep + r) or inCircle(b.x, b.z, 0, 0, centreKeep + r) then
			return false
		end
		for _, s in solids do
			if boxesOverlap(b, s, pad) then
				return false
			end
		end
		return true
	end

	local function addPlateau(b: Box)
		table.insert(layout.plateaus, b)
		table.insert(solids, b)
	end
	local function addRamp(r: Ramp)
		table.insert(layout.ramps, r)
		table.insert(solids, rampBox(r))
	end

	-- Plateaus (some are cliffs with a jump pad instead of a ramp).
	local cliffsLeft = world.cliffs
	for _ = 1, world.plateaus do
		for _ = 1, 40 do
			local sx = rngTerrain:NextInteger(world.plateauSize[1], world.plateauSize[2])
			local sz = rngTerrain:NextInteger(world.plateauSize[1], world.plateauSize[2])
			local h = rngTerrain:NextInteger(world.plateauHeight[1], world.plateauHeight[2])
			local b: Box = {
				x = rngTerrain:NextNumber(-half + margin, half - margin),
				z = rngTerrain:NextNumber(-half + margin, half - margin),
				sx = sx,
				sz = sz,
				base = 0,
				h = h,
			}
			if not free(b, 14) then
				continue
			end
			local isCliff = cliffsLeft > 0
			local side = rngTerrain:NextInteger(1, 4)
			if isCliff then
				cliffsLeft -= 1
				addPlateau(b)
				-- Jump pad 5 studs off the chosen side, launching toward the plateau.
				local dx, dz = 0, 0
				if side == 1 then
					dx = -1
				elseif side == 2 then
					dx = 1
				elseif side == 3 then
					dz = -1
				else
					dz = 1
				end
				local px = b.x + dx * (b.sx / 2 + 5)
				local pz = b.z + dz * (b.sz / 2 + 5)
				table.insert(layout.pads, { x = px, z = pz, y = 0, dirX = -dx, dirZ = -dz, h = h })
				break
			end
			local ramp = rampFor(b, side, 0, 10)
			if free(rampBox(ramp), 4) then
				addPlateau(b)
				addRamp(ramp)
				break
			end
		end
	end

	-- Hills: two stacked tiers, each with its own ramp.
	for _ = 1, world.hills do
		for _ = 1, 40 do
			local lower: Box = {
				x = rngTerrain:NextNumber(-half + margin, half - margin),
				z = rngTerrain:NextNumber(-half + margin, half - margin),
				sx = rngTerrain:NextInteger(58, 70),
				sz = rngTerrain:NextInteger(58, 70),
				base = 0,
				h = rngTerrain:NextInteger(4, 7),
			}
			local side = rngTerrain:NextInteger(1, 4)
			local ramp = rampFor(lower, side, 0, 12)
			if not (free(lower, 14) and free(rampBox(ramp), 4)) then
				continue
			end
			addPlateau(lower)
			addRamp(ramp)
			local top: Box = {
				x = lower.x,
				z = lower.z,
				sx = 24,
				sz = 24,
				base = lower.h,
				h = lower.h + rngTerrain:NextInteger(5, 7),
			}
			table.insert(layout.plateaus, top)
			local topSide = (side % 4) + 1
			table.insert(layout.ramps, rampFor(top, topSide, lower.h, 8))
			break
		end
	end

	-- Boss arena furniture (terrain weakness, dossier 20 section 5).
	local function arenaPlatform(a: number, d: number, s: number, h: number, outward: boolean)
		local cx, cz = ax + math.cos(a) * d, az + math.sin(a) * d
		local b: Box = { x = cx, z = cz, sx = s, sz = s, base = 0, h = h }
		table.insert(layout.plateaus, b)
		-- Pick the axis side facing away from (or along) the arena centre.
		local vx, vz = cx - ax, cz - az
		local side
		if math.abs(vx) > math.abs(vz) then
			side = if (vx > 0) == outward then 2 else 1
		else
			side = if (vz > 0) == outward then 4 else 3
		end
		table.insert(layout.ramps, rampFor(b, side, 0, 6))
		table.insert(layout.weakPoints, { x = cx, z = cz, y = h })
	end
	if bossId == "GrandCheneRonchon" then
		for k = 0, 3 do
			arenaPlatform(math.pi / 4 + k * math.pi / 2, 17, 8, 8, true)
		end
	elseif bossId == "PharaonGrillePain" then
		for k = 0, 3 do
			local a = k * math.pi / 2 + math.pi / 4
			table.insert(layout.pillars, { x = ax + math.cos(a) * 26, z = az + math.sin(a) * 26, r = 3, h = 16 })
		end
	elseif bossId == "DirectriceEternelle" then
		arenaPlatform(rngArche:NextNumber(0, math.pi * 2), 32, 10, 10, true)
	elseif bossId == "GrandBrouhaha" then
		for k = 0, 3 do
			arenaPlatform(k * math.pi / 2, 42, 8, 6, false)
		end
	end

	-- Build the height grid now (spawn points and decor read it).
	Heightmap._buildGrid(layout)

	-- Decor (not part of the height grid).
	local decorKinds = { "A", "B", "C" }
	for _ = 1, world.decor do
		for _ = 1, 10 do
			local x = rngDecor:NextNumber(-half + 10, half - 10)
			local z = rngDecor:NextNumber(-half + 10, half - 10)
			if inCircle(x, z, ax, az, arenaKeep) or inCircle(x, z, 0, 0, 24) then
				continue
			end
			table.insert(layout.decor, {
				kind = decorKinds[rngDecor:NextInteger(1, 3)],
				x = x,
				z = z,
				s = rngDecor:NextNumber(0.8, 1.4),
				rot = rngDecor:NextNumber(0, 360),
			})
			break
		end
	end
	for _ = 1, world.lamps do
		local x = rngDecor:NextNumber(-half + 30, half - 30)
		local z = rngDecor:NextNumber(-half + 30, half - 30)
		table.insert(layout.lamps, { x = x, z = z, y = Heightmap.getY(x, z) })
	end

	-- Spawn points for the loot domain and players (StageService.getSpawnPoints).
	local taken: { Point } = {}
	local function pick(kind: string, n: number, minGap: number, ring: { number }?)
		local list: { Point } = {}
		for _ = 1, n do
			for _ = 1, 60 do
				local x, z
				if ring then
					local a = rngSpawn:NextNumber(0, math.pi * 2)
					local r = rngSpawn:NextNumber(ring[1], ring[2])
					x, z = math.cos(a) * r, math.sin(a) * r
				else
					x = rngSpawn:NextNumber(-half + 30, half - 30)
					z = rngSpawn:NextNumber(-half + 30, half - 30)
				end
				if not ring and (inCircle(x, z, ax, az, arenaKeep) or inCircle(x, z, 0, 0, 30)) then
					continue
				end
				local ok = true
				for _, p in taken do
					if inCircle(x, z, p.x, p.z, minGap) then
						ok = false
						break
					end
				end
				if ok then
					local p = { x = x, z = z, y = Heightmap.getY(x, z) }
					table.insert(list, p)
					table.insert(taken, p)
					break
				end
			end
		end
		layout.spawnPoints[kind] = list
	end
	pick("Player", 4, 4, { 6, 10 })
	pick("Merchant", 2, 40)
	pick("Shrine", 8, 50)
	pick("Chest", 18, 22)
	pick("Pot", 40, 10)

	return layout
end

function Heightmap._buildGrid(layout: Layout)
	local n = layout.size // CELL + 1
	local b = buffer.create(n * n * 4) -- zero-filled = flat ground at Y 0
	local origin = -layout.size / 2
	local function raster(x0: number, z0: number, x1: number, z1: number, fn: (x: number, z: number) -> number)
		local i0 = math.max(0, math.ceil((x0 - origin) / CELL))
		local i1 = math.min(n - 1, math.floor((x1 - origin) / CELL))
		local j0 = math.max(0, math.ceil((z0 - origin) / CELL))
		local j1 = math.min(n - 1, math.floor((z1 - origin) / CELL))
		for j = j0, j1 do
			local z = origin + j * CELL
			for i = i0, i1 do
				local x = origin + i * CELL
				local o = (j * n + i) * 4
				local h = fn(x, z)
				if h > buffer.readf32(b, o) then
					buffer.writef32(b, o, h)
				end
			end
		end
	end
	for _, p in layout.plateaus do
		local h = p.h
		raster(p.x - p.sx / 2, p.z - p.sz / 2, p.x + p.sx / 2, p.z + p.sz / 2, function()
			return h
		end)
	end
	for _, r in layout.ramps do
		local box = rampBox(r)
		local x0, x1 = r.x - r.length / 2, r.x + r.length / 2
		local z0, z1 = r.z - r.length / 2, r.z + r.length / 2
		raster(box.x - box.sx / 2, box.z - box.sz / 2, box.x + box.sx / 2, box.z + box.sz / 2, function(x, z)
			local t
			if r.dir == 1 then
				t = (x - x0) / r.length
			elseif r.dir == 2 then
				t = (x1 - x) / r.length
			elseif r.dir == 3 then
				t = (z - z0) / r.length
			else
				t = (z1 - z) / r.length
			end
			return r.base + (r.h - r.base) * math.clamp(t, 0, 1)
		end)
	end
	grid = b
	gridN = n
	gridOrigin = origin
end

-- Ground height at (x, z): top of the walkable surface (plateaus, ramps, flat ground).
function Heightmap.getY(x: number, z: number): number
	local b = grid
	if not b then
		return 0
	end
	local n = gridN
	local fx = math.clamp((x - gridOrigin) / CELL, 0, n - 1.001)
	local fz = math.clamp((z - gridOrigin) / CELL, 0, n - 1.001)
	local i, j = fx // 1, fz // 1
	local tx, tz = fx - i, fz - j
	local o = (j * n + i) * 4
	local h00 = buffer.readf32(b, o)
	local h10 = buffer.readf32(b, o + 4)
	local h01 = buffer.readf32(b, o + n * 4)
	local h11 = buffer.readf32(b, o + n * 4 + 4)
	return (h00 + (h10 - h00) * tx) + ((h01 + (h11 - h01) * tx) - (h00 + (h10 - h00) * tx)) * tz
end

-- Highest point of the 2x2 cell block (no interpolation): use for "is standing on a plateau".
function Heightmap.getMaxY(x: number, z: number): number
	return math.max(Heightmap.getY(x, z), Heightmap.getY(x + 1, z + 1), Heightmap.getY(x - 1, z - 1))
end

function Heightmap.getLayout(): Layout?
	return current
end

function Heightmap.makeKey(worldId: string, stage: number, seed: number, bossId: string): string
	return `{worldId}|{stage}|{seed}|{bossId}`
end

-- Builds (or rebuilds) the layout and grid for a key. Same key -> same result on every machine.
function Heightmap.load(key: string): Layout?
	if current and current.key == key then
		return current
	end
	local parts = string.split(key, "|")
	local worldId, stage, seed, bossId = parts[1], tonumber(parts[2]), tonumber(parts[3]), parts[4]
	if not (worldId and stage and seed and bossId) then
		return nil
	end
	local layout = generate(worldId, stage, seed, bossId)
	layout.key = key
	current = layout
	return layout
end

-- Back to flat ground (between runs).
function Heightmap.clear()
	current = nil
	grid = nil
end

Heightmap.Attribute = ATTRIBUTE

-- Clients follow the server's stage key.
if RunService:IsClient() then
	local function sync()
		local key = Workspace:GetAttribute(ATTRIBUTE)
		if typeof(key) == "string" and key ~= "" then
			Heightmap.load(key)
		else
			Heightmap.clear()
		end
	end
	Workspace:GetAttributeChangedSignal(ATTRIBUTE):Connect(sync)
	sync()
end

return Heightmap
