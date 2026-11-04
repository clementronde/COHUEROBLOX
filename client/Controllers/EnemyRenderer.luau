--!strict
-- Draws server enemies from binary snapshots (doc 12.2, dossier 20 section 8).
-- Pooled anchored low-poly models (2-5 parts per kind from Config.Enemies), interpolated between
-- samples, all moved in one BulkMoveTo per frame. LOD: full model < 80 studs, one part < 150,
-- a small flat impostor beyond (cheaper than one BillboardGui per enemy). Elites: gold neon ring
-- + crown (no Highlight: creating one per elite triggers a geometry rebuild, vault "Highlights
-- and Selection Effects"). Enemy projectiles are replayed in closed form from their launch data.
-- Bosses are drawn by BossRenderer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Enemies = require(Config:WaitForChild("Enemies"))
local Run = require(Config:WaitForChild("Run"))
local Worlds = require(Config:WaitForChild("Worlds"))
local Codec = require(Shared:WaitForChild("EnemyCodec"))
local Heightmap = require(Shared:WaitForChild("Heightmap"))
local Net = require(Shared:WaitForChild("Net"))
local ArtLibrary = require(Shared:WaitForChild("ArtLibrary"))

-- Meshes are drawn a bit taller than the gameplay height so they read from the high camera.
local ART_SCALE = 1.3

local SAMPLE_DT = 1 / Balance.SimHz
local HIDDEN = CFrame.new(0, -10000, 0)
local LOD_NEAR = 80
local LOD_FAR = 150
local LOD_HYST = 6
local GOLD = Color3.fromRGB(255, 200, 40)
local FROZEN = Color3.fromRGB(150, 210, 255)

local BIT_ELITE = 1
local BIT_ACTION = 2
local BIT_STOPPED = 4

type Model = { parts: { BasePart }, offsets: { CFrame }, colors: { Color3 } }

type Entry = {
	kind: number,
	elite: boolean,
	lod: number,
	model: Model,
	fromX: number,
	fromZ: number,
	toX: number,
	toZ: number,
	t0: number,
	span: number,
	lastTick: number,
	state: number,
	actionStart: number,
	tinted: boolean,
	faceX: number,
	faceZ: number,
}

type Projectile = {
	id: number,
	part: BasePart,
	x: number,
	y: number,
	z: number,
	dx: number,
	dz: number,
	speed: number,
	t0: number,
	ends: number,
}

local EnemyRenderer = {}

local entries: { [number]: Entry } = {}
local pools: { [number]: { Model } } = {}
local projectiles: { [number]: Projectile } = {}
local projectilePool: { BasePart } = {}
local latestTick = 0
local visibleCount = 0
local container: Folder

local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

-- Models ---------------------------------------------------------------------------------------

local function newPart(shape: string, size: Vector3, color: Color3, neon: boolean?): BasePart
	local part: BasePart
	if shape == "Wedge" then
		part = Instance.new("WedgePart")
	else
		local p = Instance.new("Part")
		if shape == "Ball" then
			p.Shape = Enum.PartType.Ball
		elseif shape == "Cylinder" then
			p.Shape = Enum.PartType.Cylinder
		end
		part = p
	end
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	part.Size = size
	part.Color = color
	part.CFrame = HIDDEN
	part.Parent = container
	return part
end

local function poolKey(kind: number, lod: number, elite: boolean): number
	return kind * 16 + lod * 2 + (if elite then 1 else 0)
end

local function buildModel(kind: number, lod: number, elite: boolean): Model
	local def = Enemies[kind]
	local m: Model = { parts = {}, offsets = {}, colors = {} }
	local s = if elite then Run.EliteSizeMult else 1
	local function add(part: BasePart, offset: CFrame)
		table.insert(m.parts, part)
		table.insert(m.offsets, offset)
		table.insert(m.colors, part.Color)
	end
	-- Generated mesh (ReplicatedStorage.Assets.Creatures.Enemy_<name>) for near and mid LOD.
	local mesh = if lod <= 2 then ArtLibrary.clonePart("Enemy_" .. def.name, def.height * ART_SCALE * s) else nil
	if mesh then
		mesh.CFrame = HIDDEN
		mesh.Parent = container
		add(mesh, CFrame.new(0, mesh.Size.Y / 2, 0))
	elseif lod == 1 and #def.model > 0 then
		for _, mp in def.model do
			local rot = mp.rot or Vector3.zero
			local offset = CFrame.new(mp.offset * s)
				* CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
			add(newPart(mp.shape, mp.size * s, mp.color, mp.neon), offset)
		end
	elseif lod <= 2 then
		add(
			newPart("Block", Vector3.new(def.radius * 2, def.height, def.radius * 2) * s, if elite then GOLD else def.color),
			CFrame.new(0, def.height * s / 2, 0)
		)
	else
		add(
			newPart("Block", Vector3.new(def.radius * 1.6 * s, 0.6, def.radius * 1.6 * s), if elite then GOLD else def.color),
			CFrame.new(0, 0.6, 0)
		)
	end
	if elite and lod <= 2 then
		local r = def.radius * s
		add(newPart("Cylinder", Vector3.new(0.3, r * 3, r * 3), GOLD, true), CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)))
		if lod == 1 then
			add(newPart("Block", Vector3.new(1.2, 0.8, 1.2), GOLD, true), CFrame.new(0, def.height * s + 0.8, 0) * CFrame.Angles(0, math.rad(45), 0))
		end
	end
	return m
end

local function acquire(kind: number, lod: number, elite: boolean): Model
	local pool = pools[poolKey(kind, lod, elite)]
	local m = pool and table.remove(pool)
	return m or buildModel(kind, lod, elite)
end

local function release(e: Entry)
	local m = e.model
	for k, part in m.parts do
		part.CFrame = HIDDEN -- moving is cheaper than reparenting
		if e.tinted then
			part.Color = m.colors[k]
		end
	end
	e.tinted = false
	local key = poolKey(e.kind, e.lod, e.elite)
	local pool = pools[key]
	if not pool then
		pool = {}
		pools[key] = pool
	end
	table.insert(pool, m)
end

local function setTint(e: Entry, on: boolean)
	if e.tinted == on then
		return
	end
	e.tinted = on
	for k, part in e.model.parts do
		part.Color = if on then e.model.colors[k]:Lerp(FROZEN, 0.6) else e.model.colors[k]
	end
end

-- Snapshots ------------------------------------------------------------------------------------

local function onSnapshot(payload: unknown)
	if typeof(payload) ~= "buffer" then
		return
	end
	local header = Codec.readHeader(payload)
	if not header or header.tick < latestTick then
		return -- malformed, or older than what we already drew
	end
	latestTick = header.tick
	local tick = header.tick
	local now = os.clock()

	Codec.forEach(payload, header.count, function(id, x, z, flags)
		local kind, st = Codec.unpackFlags(flags)
		local def = Enemies[kind]
		if not def or def.isBoss then
			return
		end
		local elite = bit32.band(st, BIT_ELITE) ~= 0
		local e = entries[id]
		if e and (e.kind ~= kind or e.elite ~= elite) then
			release(e)
			entries[id] = nil
			e = nil
		end
		if not e then
			entries[id] = {
				kind = kind,
				elite = elite,
				lod = 2,
				model = acquire(kind, 2, elite),
				fromX = x,
				fromZ = z,
				toX = x,
				toZ = z,
				t0 = now,
				span = SAMPLE_DT,
				lastTick = tick,
				state = st,
				actionStart = if bit32.band(st, BIT_ACTION) ~= 0 then now else 0,
				tinted = false,
				faceX = 0,
				faceZ = -1,
			}
		elseif tick > e.lastTick then
			local a = math.clamp((now - e.t0) / e.span, 0, 1)
			e.fromX = e.fromX + (e.toX - e.fromX) * a
			e.fromZ = e.fromZ + (e.toZ - e.fromZ) * a
			e.toX, e.toZ = x, z
			e.t0 = now
			e.span = math.max(SAMPLE_DT, (tick - e.lastTick) * SAMPLE_DT)
			e.lastTick = tick
			if bit32.band(st, BIT_ACTION) ~= 0 and bit32.band(e.state, BIT_ACTION) == 0 then
				e.actionStart = now
			end
			e.state = st
		end
	end)
end

local function onProjectiles(payload: unknown)
	if typeof(payload) ~= "buffer" then
		return
	end
	local spawns, removed = Codec.decodeProjectiles(payload)
	if not spawns or not removed then
		return
	end
	for _, p in spawns do
		local old = projectiles[p.id]
		if old then
			old.part.CFrame = HIDDEN
			table.insert(projectilePool, old.part)
		end
		local part = table.remove(projectilePool) or newPart("Ball", Vector3.one, p.color, true)
		part.Size = Vector3.one * math.max(1.6, p.radius * 2)
		part.Color = p.color
		projectiles[p.id] = {
			id = p.id,
			part = part,
			x = p.x,
			y = p.y,
			z = p.z,
			dx = math.cos(p.angle),
			dz = math.sin(p.angle),
			speed = p.speed,
			t0 = p.t0,
			ends = p.t0 + p.life,
		}
	end
	for _, id in removed do
		local pr = projectiles[id]
		if pr then
			pr.part.CFrame = HIDDEN
			table.insert(projectilePool, pr.part)
			projectiles[id] = nil
		end
	end
end

-- Frame ------------------------------------------------------------------------------------------

local function viewerPosition(): Vector3
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local camera = Workspace.CurrentCamera
	return if camera then camera.Focus.Position else Vector3.zero
end

local function blackoutVisible(x: number, z: number, viewer: Vector3, hazard: Worlds.Hazard): boolean
	local reveal = hazard.revealRadius or 20
	local dx, dz = x - viewer.X, z - viewer.Z
	if dx * dx + dz * dz <= reveal * reveal then
		return true
	end
	local layout = Heightmap.getLayout()
	if layout then
		local lr = hazard.lampRadius or 22
		for _, l in layout.lamps do
			local lx, lz = x - l.x, z - l.z
			if lx * lx + lz * lz <= lr * lr then
				return true
			end
		end
	end
	return false
end

local function render()
	local now = os.clock()
	local staleBefore = latestTick - Balance.ClientStaleTicks
	local viewer = viewerPosition()
	local blackout: Worlds.Hazard? = nil
	if Workspace:GetAttribute("CohueHazard") == "Blackout" then
		local layout = Heightmap.getLayout()
		local world = layout and Worlds[layout.worldId]
		blackout = world and world.hazard
	end
	local n = 0
	local drawn = 0
	for id, e in entries do
		if e.lastTick < staleBefore then
			release(e)
			entries[id] = nil
			continue
		end
		local a = math.clamp((now - e.t0) / e.span, 0, 1)
		local x = e.fromX + (e.toX - e.fromX) * a
		local z = e.fromZ + (e.toZ - e.fromZ) * a
		local vx, vz = x - viewer.X, z - viewer.Z
		local dist = math.sqrt(vx * vx + vz * vz)

		-- LOD with hysteresis
		local lod = e.lod
		local want = if dist < LOD_NEAR then 1 elseif dist < LOD_FAR then 2 else 3
		if want ~= lod then
			local edge = if want < lod then (if lod == 2 then LOD_NEAR else LOD_FAR) - LOD_HYST
				else (if lod == 1 then LOD_NEAR else LOD_FAR) + LOD_HYST
			if (want < lod and dist < edge) or (want > lod and dist > edge) then
				release(e)
				e.lod = want
				e.model = acquire(e.kind, want, e.elite)
			end
		end

		local def = Enemies[e.kind]
		local hidden = blackout ~= nil and not blackoutVisible(x, z, viewer, blackout)
		setTint(e, bit32.band(e.state, BIT_STOPPED) ~= 0)

		local y = Heightmap.getY(x, z)
		local jitterX = 0
		local acting = bit32.band(e.state, BIT_ACTION) ~= 0
		if acting and def.family == "Jumper" then
			local t = now - e.actionStart
			local windup = def.leapWindup or 0.4
			local air = def.leapAir or 0.8
			if t > windup then
				local u = math.clamp((t - windup) / air, 0, 1)
				y += math.sin(math.pi * u) * 7
			else
				y -= 0.3
			end
		elseif acting then
			jitterX = math.sin(now * 45) * 0.15 -- charging a shot: shake
		elseif e.lod == 1 then
			y += math.abs(math.sin(now * 9 + id)) * 0.35 -- hop walk
		end

		local dx, dz = e.toX - e.fromX, e.toZ - e.fromZ
		if dx * dx + dz * dz > 1e-4 then
			local d = math.sqrt(dx * dx + dz * dz)
			e.faceX, e.faceZ = dx / d, dz / d
		end
		local pos = Vector3.new(x + jitterX, y, z)
		local base = if hidden then HIDDEN else CFrame.lookAt(pos, pos + Vector3.new(e.faceX, 0, e.faceZ))
		local m = e.model
		for k, part in m.parts do
			n += 1
			moveParts[n] = part
			moveCFrames[n] = if hidden then HIDDEN else base * m.offsets[k]
		end
		if not hidden then
			drawn += 1
		end
	end

	-- Enemy projectiles (closed form from launch data)
	local serverNow = Workspace:GetServerTimeNow()
	for id, p in projectiles do
		if serverNow >= p.ends then
			p.part.CFrame = HIDDEN
			table.insert(projectilePool, p.part)
			projectiles[id] = nil
			continue
		end
		local t = math.max(0, serverNow - p.t0)
		n += 1
		moveParts[n] = p.part
		moveCFrames[n] = CFrame.new(p.x + p.dx * p.speed * t, p.y, p.z + p.dz * p.speed * t)
	end

	for i = n + 1, #moveParts do
		moveParts[i] = nil :: any
		moveCFrames[i] = nil :: any
	end
	if n > 0 then
		Workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	visibleCount = drawn
end

function EnemyRenderer.getVisibleCount(): number
	return visibleCount
end

function EnemyRenderer.init()
	container = Instance.new("Folder")
	container.Name = "ClientEnemies"
	container.Parent = Workspace
end

function EnemyRenderer.start()
	Net.unreliable("EnemySnapshot").OnClientEvent:Connect(onSnapshot)
	Net.event("EnemyProjectiles").OnClientEvent:Connect(onProjectiles)
	RunService.PreRender:Connect(render)
end

return EnemyRenderer
