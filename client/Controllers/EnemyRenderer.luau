--!strict
-- Draws server enemies from binary snapshots (doc 12.2, dossier 20 section 8).
-- Pooled anchored meshes and low-poly fallback models, interpolated between
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
local Motion = require(script.Parent.EnemyMotion)
local Effects = require(script.Parent.EnemyAttackFX)
local RigMotion = require(script.Parent.EnemyRigMotion)
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

type Model = { parts: { BasePart }, offsets: { CFrame }, colors: { Color3 }, groundIndex: number?, rig: RigMotion.Rig? }

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
	aimAt: number,
	strikeAt: number,
	stride: number,
	walkWeight: number,
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
	local assetName = "Enemy_" .. def.name
	local template = if lod <= 2 then ArtLibrary.find(assetName) else nil
	local hasRig = template and template:IsA("Model") and template:FindFirstChildWhichIsA("Bone", true) ~= nil
	local mesh = if lod <= 2 and not hasRig then ArtLibrary.clonePart(assetName, def.height * ART_SCALE * s) else nil
	local source = if hasRig and template and template:IsA("Model")
		then template:FindFirstChildWhichIsA("MeshPart", true) else nil
	if source and template then
		local part = source:Clone()
		local scaleModel = Instance.new("Model")
		part.Parent = scaleModel
		local visualHeight = (template:GetAttribute("VisualHeight") :: number?) or def.height * ART_SCALE
		scaleModel:ScaleTo(visualHeight * s / part.Size.Y)
		part.Parent = nil
		scaleModel:Destroy()
		local floor = part.Position - Vector3.yAxis * (part.Size.Y * .5)
		local yaw = math.rad((template:GetAttribute("FaceYaw") :: number?) or 0)
		local facing = CFrame.new(floor) * CFrame.Angles(0, -yaw, 0)
		local rig = RigMotion.bind(part, facing)
		if lod == 1 then
			m.rig = rig
		else
			-- Hold a relaxed pose at middle distance, with no per-frame bone updates.
			RigMotion.apply(rig, def.name, 0, 0, 0, 0, os.clock())
		end
		add(part, facing:ToObjectSpace(part.CFrame))
		part.Name = def.name
		part.CFrame = HIDDEN
		part.Parent = container
	elseif mesh then
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
		m.groundIndex = #m.parts + 1
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
				aimAt = -math.huge,
				strikeAt = -math.huge,
				stride = id % 13,
				walkWeight = 0,
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
			if bit32.band(st, BIT_ACTION) ~= 0 and bit32.band(e.state, BIT_ACTION) == 0 and now - e.aimAt > .22 then
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

local function onAttackVisual(id: number, name: string, mode: string, position: Vector3, direction: Vector3, radius: number)
	local profile = Motion.profiles[name]
	if not profile then
		return
	end
	local now = os.clock()
	local entry = entries[id]
	local facing = if direction.Magnitude > .01 then direction.Unit
		elseif entry then Vector3.new(entry.faceX, 0, entry.faceZ) else -Vector3.zAxis
	if entry and Enemies[entry.kind].name == name then
		if mode == "aim" then
			entry.aimAt = now
			entry.actionStart = now
		elseif now - entry.strikeAt < .15 then
			return -- simultaneous contact from multiple players
		else
			entry.strikeAt = now
		end
		entry.faceX, entry.faceZ = facing.X, facing.Z
	end
	if mode == "aim" then
		return
	end
	local viewer = viewerPosition()
	if (position - viewer).Magnitude > (if mode == "boss" then 135 else 82) then
		return
	end
	if mode ~= "boss" and Workspace:GetAttribute("CohueHazard") == "Blackout" then
		local layout = Heightmap.getLayout()
		local world = layout and Worlds[layout.worldId]
		local hazard = world and world.hazard
		if hazard and not blackoutVisible(position.X, position.Z, viewer, hazard) then
			return
		end
	end
	if mode == "contact" and profile.style ~= "burst" then
		position += Vector3.yAxis * radius * .55 + facing * radius * .55
	end
	Effects.emit(profile, position, facing, mode, radius)
end

local function render(dt: number)
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
		local profile = Motion.profiles[def.name]
		local stopped = bit32.band(e.state, BIT_STOPPED) ~= 0
		local acting = bit32.band(e.state, BIT_ACTION) ~= 0
		local dx, dz = e.toX - e.fromX, e.toZ - e.fromZ
		local distance = math.sqrt(dx * dx + dz * dz)
		local speed = if distance < def.speed * e.span * 3 and a < 1 then distance / e.span else 0
		local striking = now - e.strikeAt
		if speed > .2 and not acting and not stopped and striking >= .38 then
			e.faceX, e.faceZ = dx / distance, dz / distance
		end
		local pos = Vector3.new(x, y, z)
		local base = if hidden then HIDDEN else CFrame.lookAt(pos, pos + Vector3.new(e.faceX, 0, e.faceZ))
		local modelBase = base
		local windupPose, strikePose = 0, 0
		if not hidden and e.lod <= 2 and not stopped and profile then
			local scale = if e.elite then Run.EliteSizeMult else 1
			local weight = if acting or striking < .38 then 0 else math.clamp(speed / def.speed, 0, 1)
			e.walkWeight += (weight - e.walkWeight) * math.min(dt * 13, 1)
			e.stride = (e.stride + speed * dt / scale) % profile.walk.stride
			if striking < .38 then
				strikePose = striking / .38
				modelBase *= Motion.strike(profile, strikePose, scale)
			elseif acting then
				local elapsed = now - e.actionStart
				local leaping = def.family == "Jumper" or def.leapAir ~= nil
				local windup = if leaping then def.leapWindup or .4 else def.shotWindup or .6
				if leaping and elapsed > windup then
					local travel = math.clamp((elapsed - windup) / (def.leapAir or .8), 0, 1)
					if def.name == "Golem" then
						windupPose = 1 - travel ^ 2
					end
					modelBase *= Motion.air(profile, travel, scale, if def.name == "Golem" then .75 else nil)
				else
					windupPose = math.clamp(elapsed / windup, 0, 1)
					modelBase *= Motion.charge(profile, windupPose, scale)
				end
			elseif e.lod == 1 then
				modelBase *= Motion.walk(profile, e.stride, e.walkWeight, now + id, scale)
			end
		end
		local m = e.model
		if m.rig and profile and not hidden then
			local phase = e.stride * (2 * math.pi / profile.walk.stride)
			local weight = if stopped or acting or striking < .38 then 0 else e.walkWeight
			RigMotion.apply(m.rig, def.name, phase, weight, windupPose, strikePose, now)
		end
		for k, part in m.parts do
			n += 1
			moveParts[n] = part
			moveCFrames[n] = if hidden then HIDDEN else (if k == m.groundIndex then base else modelBase) * m.offsets[k]
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
	Effects.init()
	container.Name = "ClientEnemies"
	container.Parent = Workspace
end

function EnemyRenderer.start()
	Net.unreliable("EnemySnapshot").OnClientEvent:Connect(onSnapshot)
	Net.unreliable("EnemyAttackVisual").OnClientEvent:Connect(onAttackVisual)
	Net.event("EnemyProjectiles").OnClientEvent:Connect(onProjectiles)
	RunService.PreRender:Connect(render)
end

return EnemyRenderer
