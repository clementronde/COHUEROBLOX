--!strict
-- Draws server enemies from binary snapshots (doc 12.2).
-- Pooled anchored parts, interpolated between samples, moved in one BulkMoveTo per frame.
-- Phase 0 uses plain boxes; real models and LOD (80 / 150 studs) come later.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Enemies = require(Config:WaitForChild("Enemies"))
local Codec = require(Shared:WaitForChild("EnemyCodec"))
local Heightmap = require(Shared:WaitForChild("Heightmap"))
local Net = require(Shared:WaitForChild("Net"))

local SAMPLE_DT = 1 / Balance.SimHz
local HIDDEN = CFrame.new(0, -10000, 0)

type Entry = {
	kind: number,
	part: BasePart,
	fromX: number,
	fromZ: number,
	toX: number,
	toZ: number,
	t0: number,
	span: number,
	lastTick: number,
}

local EnemyRenderer = {}

local entries: { [number]: Entry } = {}
local pools: { [number]: { BasePart } } = {}
local latestTick = 0
local visibleCount = 0
local container: Folder

-- Reused BulkMoveTo arrays
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

local function makePart(kind: number): BasePart
	local def = Enemies[kind]
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Size = Vector3.new(def.radius * 2, def.height, def.radius * 2)
	part.Color = def.color
	part.CFrame = HIDDEN
	part.Parent = container
	return part
end

local function acquire(kind: number): BasePart
	local pool = pools[kind]
	local part = pool and table.remove(pool)
	return part or makePart(kind)
end

local function release(kind: number, part: BasePart)
	part.CFrame = HIDDEN -- moving is cheaper than reparenting
	local pool = pools[kind]
	if not pool then
		pool = {}
		pools[kind] = pool
	end
	table.insert(pool, part)
end

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
		local kind = Codec.unpackFlags(flags)
		if not Enemies[kind] then
			return
		end
		local e = entries[id]
		if e and e.kind ~= kind then
			release(e.kind, e.part)
			entries[id] = nil
			e = nil
		end
		if not e then
			entries[id] = {
				kind = kind,
				part = acquire(kind),
				fromX = x,
				fromZ = z,
				toX = x,
				toZ = z,
				t0 = now,
				span = SAMPLE_DT,
				lastTick = tick,
			}
		elseif tick > e.lastTick then
			-- Start the next segment from where the enemy is drawn right now.
			local a = math.clamp((now - e.t0) / e.span, 0, 1)
			e.fromX = e.fromX + (e.toX - e.fromX) * a
			e.fromZ = e.fromZ + (e.toZ - e.fromZ) * a
			e.toX, e.toZ = x, z
			e.t0 = now
			e.span = math.max(SAMPLE_DT, (tick - e.lastTick) * SAMPLE_DT)
			e.lastTick = tick
		end
	end)
end

local function render()
	local now = os.clock()
	local staleBefore = latestTick - Balance.ClientStaleTicks
	local n = 0
	for id, e in entries do
		if e.lastTick < staleBefore then
			-- Died, or left our interest radius.
			release(e.kind, e.part)
			entries[id] = nil
			continue
		end
		local a = math.clamp((now - e.t0) / e.span, 0, 1)
		local x = e.fromX + (e.toX - e.fromX) * a
		local z = e.fromZ + (e.toZ - e.fromZ) * a
		local y = Heightmap.getY(x, z) + Enemies[e.kind].height / 2
		local pos = Vector3.new(x, y, z)
		local dx, dz = e.toX - e.fromX, e.toZ - e.fromZ
		n += 1
		moveParts[n] = e.part
		moveCFrames[n] = if dx * dx + dz * dz > 1e-4
			then CFrame.lookAt(pos, pos + Vector3.new(dx, 0, dz))
			else CFrame.new(pos)
	end
	for i = n + 1, #moveParts do
		moveParts[i] = nil :: any
		moveCFrames[i] = nil :: any
	end
	if n > 0 then
		Workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	visibleCount = n
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
	RunService.PreRender:Connect(render)
end

return EnemyRenderer
