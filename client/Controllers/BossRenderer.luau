--!strict
-- Boss visuals and stage FX (dossier 20 section 8).
--   * Boss model built from parts, interpolated between BossState samples (10 Hz).
--   * Ground telegraphs: translucent zone + a fill that grows until the impact time, so the
--     timing is readable on a phone (vault: "Boss Animation and Phases"). Same shape params as
--     the server hit test.
--   * Weak points (bell / gongs) glow gold when usable; the boss tints gold while vulnerable.
--   * Revealed Arche: tall light pillar visible across the map.
--   * Stage hazards from Workspace attributes: fog, sandstorm (pushes the local character),
--     blackout. Jump pads from the shared layout (the local client applies the launch).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Bosses = require(Config:WaitForChild("Bosses"))
local Worlds = require(Config:WaitForChild("Worlds"))
local Heightmap = require(Shared:WaitForChild("Heightmap"))
local Net = require(Shared:WaitForChild("Net"))
local ArtLibrary = require(Shared:WaitForChild("ArtLibrary"))

local HIDDEN = CFrame.new(0, -10000, 0)
local UP_CYL = CFrame.Angles(0, 0, math.rad(90))
local GOLD = Color3.fromRGB(255, 205, 60)
local PAD_RADIUS = 3.5
local PAD_SIDE_SPEED = 22

type PartSpec = { shape: string, size: Vector3, offset: CFrame, color: Color3, neon: boolean? }
type TelegraphVisual = { zone: BasePart, fill: BasePart, safe: BasePart? }

local BossRenderer = {}

local container: Folder
local bossParts: { BasePart } = {}
local bossOffsets: { CFrame } = {}
local bossColors: { Color3 } = {}
local bossKey = ""
local bossFrom = Vector3.zero
local bossTo = Vector3.zero
local bossT0 = 0
local bossVisible = false
local bossTint = false
local lastState: { [string]: any }? = nil

local telegraphs: { { data: { [string]: any }, visual: TelegraphVisual } } = {}
local discPool: { BasePart } = {}
local boxPool: { BasePart } = {}
local weakMarkers: { BasePart } = {}

local archeBeam: BasePart
local runState: { [string]: any } = {}

local savedLighting: { [string]: any }? = nil
local currentHazard = ""
local padCooldown = 0

local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

-- Parts ---------------------------------------------------------------------------------------

local function newPart(shape: string, size: Vector3, color: Color3, neon: boolean?, transparency: number?): BasePart
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
	part.Transparency = transparency or 0
	part.CFrame = HIDDEN
	part.Parent = container
	return part
end

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function at(x: number, y: number, z: number, rx: number?, ry: number?, rz: number?): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0))
end

-- Low-poly boss models (front = -Z, feet at y = 0).
local MODELS: { [string]: { PartSpec } } = {
	GrandCheneRonchon = {
		{ shape = "Cylinder", size = Vector3.new(14, 8, 8), offset = at(0, 7, 0) * UP_CYL, color = rgb(110, 75, 45) },
		{ shape = "Ball", size = Vector3.new(16, 10, 16), offset = at(0, 17, 0), color = rgb(70, 145, 55) },
		{ shape = "Ball", size = Vector3.new(10, 8, 10), offset = at(5, 20, 3), color = rgb(85, 165, 65) },
		{ shape = "Ball", size = Vector3.new(9, 7, 9), offset = at(-5, 19, -2), color = rgb(60, 130, 50) },
		{ shape = "Ball", size = Vector3.new(1.6, 1.6, 0.6), offset = at(-1.6, 9, -3.9), color = rgb(255, 220, 80), neon = true },
		{ shape = "Ball", size = Vector3.new(1.6, 1.6, 0.6), offset = at(1.6, 9, -3.9), color = rgb(255, 220, 80), neon = true },
		{ shape = "Block", size = Vector3.new(3.6, 0.6, 0.4), offset = at(0, 6.6, -4, 0, 0, 8), color = rgb(40, 25, 15) },
		{ shape = "Block", size = Vector3.new(10, 1.6, 1.6), offset = at(6, 11, 0, 0, 0, 25), color = rgb(100, 70, 40) },
		{ shape = "Block", size = Vector3.new(10, 1.6, 1.6), offset = at(-6, 11, 0, 0, 0, -25), color = rgb(100, 70, 40) },
	},
	PharaonGrillePain = {
		{ shape = "Block", size = Vector3.new(9, 7, 6), offset = at(0, 5.5, 0), color = rgb(200, 200, 210) },
		{ shape = "Block", size = Vector3.new(7, 0.4, 1), offset = at(0, 9.1, -1.2), color = rgb(40, 40, 45) },
		{ shape = "Block", size = Vector3.new(7, 0.4, 1), offset = at(0, 9.1, 1.2), color = rgb(40, 40, 45) },
		{ shape = "Block", size = Vector3.new(5, 3, 0.8), offset = at(0, 10, -1.2), color = rgb(225, 175, 100) },
		{ shape = "Wedge", size = Vector3.new(11, 4, 2), offset = at(0, 8, 3.6), color = rgb(40, 80, 170) },
		{ shape = "Block", size = Vector3.new(11.2, 0.6, 2.1), offset = at(0, 7.4, 3.6), color = GOLD },
		{ shape = "Ball", size = Vector3.new(1.4, 1.4, 0.5), offset = at(-2, 6.5, -3), color = rgb(255, 70, 40), neon = true },
		{ shape = "Ball", size = Vector3.new(1.4, 1.4, 0.5), offset = at(2, 6.5, -3), color = rgb(255, 70, 40), neon = true },
		{ shape = "Block", size = Vector3.new(1.4, 2.4, 1.4), offset = at(-2.6, 1.2, 0), color = rgb(60, 60, 70) },
		{ shape = "Block", size = Vector3.new(1.4, 2.4, 1.4), offset = at(2.6, 1.2, 0), color = rgb(60, 60, 70) },
	},
	DirectriceEternelle = {
		{ shape = "Cylinder", size = Vector3.new(8, 5, 5), offset = at(0, 4, 0) * UP_CYL, color = rgb(110, 80, 160) },
		{ shape = "Block", size = Vector3.new(4.4, 3, 3), offset = at(0, 9, 0), color = rgb(130, 95, 185) },
		{ shape = "Ball", size = Vector3.new(3.4, 3.4, 3.4), offset = at(0, 12, 0), color = rgb(210, 220, 240) },
		{ shape = "Ball", size = Vector3.new(2, 2, 2), offset = at(0, 13.8, 0.8), color = rgb(90, 90, 100) },
		{ shape = "Block", size = Vector3.new(2.8, 0.5, 0.2), offset = at(0, 12.2, -1.7), color = rgb(120, 255, 255), neon = true },
		{ shape = "Block", size = Vector3.new(0.4, 7, 0.6), offset = at(3, 9, -1, 0, 0, -30), color = rgb(230, 190, 90) },
		{ shape = "Block", size = Vector3.new(6, 0.3, 0.3), offset = at(0, 0.3, -2.5), color = rgb(200, 200, 220), neon = true },
	},
	GrandBrouhaha = {
		{ shape = "Ball", size = Vector3.new(13, 12, 13), offset = at(0, 7, 0), color = rgb(230, 90, 60) },
		{ shape = "Ball", size = Vector3.new(5, 5, 5), offset = at(-5, 12.5, 1), color = rgb(255, 180, 60) },
		{ shape = "Ball", size = Vector3.new(5, 5, 5), offset = at(5, 12.5, 1), color = rgb(120, 200, 255) },
		{ shape = "Ball", size = Vector3.new(5, 5, 5), offset = at(0, 14, 3), color = rgb(150, 230, 110) },
		{ shape = "Block", size = Vector3.new(6, 2, 0.6), offset = at(0, 6, -6.3), color = rgb(30, 20, 20) },
		{ shape = "Ball", size = Vector3.new(1.8, 1.8, 0.6), offset = at(-2.4, 9, -6), color = rgb(255, 255, 120), neon = true },
		{ shape = "Ball", size = Vector3.new(1.8, 1.8, 0.6), offset = at(2.4, 9, -6), color = rgb(255, 255, 120), neon = true },
		{ shape = "Wedge", size = Vector3.new(2, 3, 2), offset = at(-2.5, 14.5, -1), color = GOLD },
		{ shape = "Wedge", size = Vector3.new(2, 3, 2), offset = at(2.5, 14.5, -1), color = GOLD },
	},
}

local function clearBoss()
	for _, part in bossParts do
		part:Destroy()
	end
	table.clear(bossParts)
	table.clear(bossOffsets)
	table.clear(bossColors)
	bossKey = ""
	bossVisible = false
	bossTint = false
end

local BOSS_MESH_HEIGHT = 18 -- studs; the generated boss meshes replace the part model

local function buildBoss(bossId: string)
	clearBoss()
	-- Generated mesh first (ReplicatedStorage.Assets.Creatures.Boss_<bossId>).
	local mesh = ArtLibrary.clonePart("Boss_" .. bossId, BOSS_MESH_HEIGHT)
	if mesh then
		mesh.CFrame = HIDDEN
		mesh.Parent = container
		table.insert(bossParts, mesh)
		table.insert(bossOffsets, CFrame.new(0, mesh.Size.Y / 2, 0))
		table.insert(bossColors, mesh.Color)
		bossKey = bossId
		return
	end
	local specs = MODELS[bossId]
	if not specs then
		return
	end
	for _, s in specs do
		table.insert(bossParts, newPart(s.shape, s.size, s.color, s.neon))
		table.insert(bossOffsets, s.offset)
		table.insert(bossColors, s.color)
	end
	bossKey = bossId
end

-- Telegraphs -----------------------------------------------------------------------------------

local function takeDisc(): BasePart
	return table.remove(discPool) or newPart("Cylinder", Vector3.one, Color3.new(1, 0, 0), true, 0.55)
end

local function takeBox(): BasePart
	return table.remove(boxPool) or newPart("Block", Vector3.one, Color3.new(1, 0, 0), true, 0.55)
end

local function giveBack(part: BasePart, box: boolean)
	part.CFrame = HIDDEN
	table.insert(if box then boxPool else discPool, part)
end

local function clearTelegraphs()
	for _, t in telegraphs do
		local isLine = t.data.kind == "Line"
		giveBack(t.visual.zone, isLine)
		giveBack(t.visual.fill, isLine)
		if t.visual.safe then
			giveBack(t.visual.safe, false)
		end
	end
	table.clear(telegraphs)
end

local function setTelegraphs(list: { { [string]: any } })
	clearTelegraphs()
	for _, data in list do
		if typeof(data.position) ~= "Vector3" or type(data.radius) ~= "number" then
			continue
		end
		local color = if typeof(data.color) == "Color3" then data.color else Bosses.Colors.Normal
		local visual: TelegraphVisual
		if data.kind == "Line" then
			visual = { zone = takeBox(), fill = takeBox() }
		else
			visual = { zone = takeDisc(), fill = takeDisc() }
			if data.kind == "Ring" then
				visual.safe = takeDisc()
				visual.safe.Color = Color3.fromRGB(80, 220, 120)
				visual.safe.Transparency = 0.7
			end
		end
		visual.zone.Color = color
		visual.zone.Transparency = 0.7
		visual.fill.Color = color
		visual.fill.Transparency = 0.35
		table.insert(telegraphs, { data = data, visual = visual })
	end
end

local function onBossState(payload: unknown)
	if type(payload) ~= "table" then
		return
	end
	local p = payload :: { [string]: any }
	if p.removed or p.defeated then
		clearBoss()
		clearTelegraphs()
		for _, m in weakMarkers do
			m.CFrame = HIDDEN
		end
		lastState = nil
		return
	end
	if type(p.bossId) ~= "string" then
		return
	end
	if p.bossId ~= bossKey then
		buildBoss(p.bossId)
	end
	if typeof(p.position) == "Vector3" then
		local now = os.clock()
		if not bossVisible then
			bossFrom = p.position
		else
			local a = math.clamp((now - bossT0) / (1 / Bosses.SendHz), 0, 1)
			bossFrom = bossFrom:Lerp(bossTo, a)
		end
		bossTo = p.position
		bossT0 = now
		bossVisible = true
	end
	if type(p.telegraphs) == "table" then
		setTelegraphs(p.telegraphs)
	end
	local tint = p.vulnerable == true
	if tint ~= bossTint then
		bossTint = tint
		for k, part in bossParts do
			part.Color = if tint then bossColors[k]:Lerp(GOLD, 0.5) else bossColors[k]
		end
	end
	lastState = p
	-- Weak points
	local points = if type(p.weakPoints) == "table" then p.weakPoints else {}
	for k, wp in points do
		local marker = weakMarkers[k]
		if not marker then
			marker = newPart("Cylinder", Vector3.new(0.2, 10, 10), GOLD, true, 0.4)
			weakMarkers[k] = marker
		end
		if typeof(wp.position) == "Vector3" and wp.ready then
			marker.CFrame = CFrame.new(wp.position + Vector3.new(0, 0.15, 0)) * UP_CYL
		else
			marker.CFrame = HIDDEN
		end
	end
	for k = #points + 1, #weakMarkers do
		weakMarkers[k].CFrame = HIDDEN
	end
end

-- Hazards --------------------------------------------------------------------------------------

local function saveLighting()
	if savedLighting then
		return
	end
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	savedLighting = {
		FogStart = Lighting.FogStart,
		FogEnd = Lighting.FogEnd,
		FogColor = Lighting.FogColor,
		Brightness = Lighting.Brightness,
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		AtmosphereDensity = if atmosphere then atmosphere.Density else nil,
	}
end

local function restoreLighting()
	local s = savedLighting
	if not s then
		return
	end
	Lighting.FogStart = s.FogStart
	Lighting.FogEnd = s.FogEnd
	Lighting.FogColor = s.FogColor
	Lighting.Brightness = s.Brightness
	Lighting.Ambient = s.Ambient
	Lighting.OutdoorAmbient = s.OutdoorAmbient
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere and s.AtmosphereDensity then
		atmosphere.Density = s.AtmosphereDensity
	end
	savedLighting = nil
end

local function applyHazard()
	local hazard = Workspace:GetAttribute("CohueHazard")
	local id = if type(hazard) == "string" then hazard else ""
	if id == currentHazard then
		return
	end
	restoreLighting()
	currentHazard = id
	if id == "" then
		return
	end
	local layout = Heightmap.getLayout()
	local world = layout and Worlds[layout.worldId]
	if not world then
		return
	end
	saveLighting()
	local hz = world.hazard
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if id == "Fog" or id == "Sandstorm" then
		local view = hz.viewDistance or 60
		Lighting.FogColor = if id == "Sandstorm" then Color3.fromRGB(220, 180, 120) else world.sky.fog
		Lighting.FogStart = view * 0.3
		Lighting.FogEnd = view
		if atmosphere then
			atmosphere.Density = 0.75 -- Atmosphere overrides FogEnd when present
		end
	elseif id == "Blackout" then
		Lighting.Brightness = 0.2
		Lighting.Ambient = Color3.fromRGB(15, 15, 30)
		Lighting.OutdoorAmbient = Color3.fromRGB(20, 20, 35)
	end
end

local function localRoot(): (BasePart?, Humanoid?)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") then
		return root, hum
	end
	return nil, hum
end

local function stepLocalCharacter(dt: number)
	local root, hum = localRoot()
	if not root or not hum or hum.Health <= 0 then
		return
	end
	-- Sandstorm push
	if currentHazard == "Sandstorm" then
		local layout = Heightmap.getLayout()
		local world = layout and Worlds[layout.worldId]
		local angle = Workspace:GetAttribute("CohueHazardAngle")
		if world and type(angle) == "number" then
			local push = (world.hazard.pushSpeed or 6) * dt
			root.CFrame += Vector3.new(math.cos(angle) * push, 0, math.sin(angle) * push)
		end
	end
	-- Jump pads
	local layout = Heightmap.getLayout()
	if layout and os.clock() >= padCooldown then
		local p = root.Position
		local feet = p.Y - hum.HipHeight - root.Size.Y / 2
		for _, pad in layout.pads do
			local dx, dz = p.X - pad.x, p.Z - pad.z
			if dx * dx + dz * dz <= PAD_RADIUS * PAD_RADIUS and feet <= pad.y + 2.5 then
				local up = math.sqrt(2 * Workspace.Gravity * (pad.h + 6))
				root.AssemblyLinearVelocity = Vector3.new(pad.dirX * PAD_SIDE_SPEED, up, pad.dirZ * PAD_SIDE_SPEED)
				padCooldown = os.clock() + 1
				break
			end
		end
	end
end

-- Frame ------------------------------------------------------------------------------------------

local function render(dt: number)
	applyHazard()
	stepLocalCharacter(dt)
	local n = 0
	local now = os.clock()

	-- Boss
	if bossVisible and #bossParts > 0 then
		local a = math.clamp((now - bossT0) / (1 / Bosses.SendHz), 0, 1)
		local pos = bossFrom:Lerp(bossTo, a)
		local dir = bossTo - bossFrom
		local base
		if dir.Magnitude > 0.05 then
			base = CFrame.lookAt(pos, pos + Vector3.new(dir.X, 0, dir.Z))
		else
			-- Face the local player when idle
			local root = localRoot()
			local look = if root then Vector3.new(root.Position.X, pos.Y, root.Position.Z) else pos - Vector3.zAxis
			base = if (look - pos).Magnitude > 0.1 then CFrame.lookAt(pos, look) else CFrame.new(pos)
		end
		local st = lastState
		if st and st.stunned then
			base *= CFrame.Angles(0, 0, math.rad(math.sin(now * 20) * 4))
		end
		for k, part in bossParts do
			n += 1
			moveParts[n] = part
			moveCFrames[n] = base * bossOffsets[k]
		end
	end

	-- Telegraphs (fill grows from start to impact)
	local serverNow = Workspace:GetServerTimeNow()
	for _, t in telegraphs do
		local d = t.data
		local pos: Vector3 = d.position
		local start = if type(d.start) == "number" then d.start else serverNow
		local hitAt = if type(d.at) == "number" then d.at else serverNow
		local u = math.clamp((serverNow - start) / math.max(0.05, hitAt - start), 0, 1)
		local y = Heightmap.getY(pos.X, pos.Z) + 0.12
		if d.kind == "Line" and typeof(d.dir) == "Vector3" and type(d.length) == "number" then
			local dir = Vector3.new(d.dir.X, 0, d.dir.Z)
			if dir.Magnitude < 1e-3 then
				continue
			end
			dir = dir.Unit
			local length: number = d.length
			local origin = Vector3.new(pos.X, y, pos.Z)
			local mid = origin + dir * length / 2
			local cf = CFrame.lookAt(mid, mid + dir)
			t.visual.zone.Size = Vector3.new(d.radius, 0.2, length)
			t.visual.fill.Size = Vector3.new(d.radius, 0.25, math.max(0.1, length * u))
			n += 1
			moveParts[n] = t.visual.zone
			moveCFrames[n] = cf
			local fmid = origin + dir * (length * u) / 2
			n += 1
			moveParts[n] = t.visual.fill
			moveCFrames[n] = CFrame.lookAt(fmid + Vector3.new(0, 0.03, 0), fmid + Vector3.new(0, 0.03, 0) + dir)
		else
			local r: number = d.radius
			local cf = CFrame.new(pos.X, y, pos.Z) * UP_CYL
			t.visual.zone.Size = Vector3.new(0.2, r * 2, r * 2)
			n += 1
			moveParts[n] = t.visual.zone
			moveCFrames[n] = cf
			local inner = if type(d.inner) == "number" then d.inner else 0
			local fr = inner + (r - inner) * u
			t.visual.fill.Size = Vector3.new(0.25, math.max(0.1, fr * 2), math.max(0.1, fr * 2))
			n += 1
			moveParts[n] = t.visual.fill
			moveCFrames[n] = cf * CFrame.new(0.03, 0, 0)
			local safe = t.visual.safe
			if safe and inner > 0 then
				safe.Size = Vector3.new(0.3, inner * 2, inner * 2)
				n += 1
				moveParts[n] = safe
				moveCFrames[n] = cf * CFrame.new(0.06, 0, 0)
			end
		end
	end

	-- Revealed Arche beam
	local showBeam = runState.bossRevealed == true
		and typeof(runState.bossPosition) == "Vector3"
		and (runState.phase == "Running" or runState.phase == "FinalWave")
	n += 1
	moveParts[n] = archeBeam
	if showBeam then
		local p: Vector3 = runState.bossPosition
		moveCFrames[n] = CFrame.new(p.X, 100, p.Z) * UP_CYL
	else
		moveCFrames[n] = HIDDEN
	end

	for i = n + 1, #moveParts do
		moveParts[i] = nil :: any
		moveCFrames[i] = nil :: any
	end
	if n > 0 then
		Workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function BossRenderer.init()
	container = Instance.new("Folder")
	container.Name = "ClientBoss"
	container.Parent = Workspace
	archeBeam = newPart("Cylinder", Vector3.new(200, 4, 4), Color3.fromRGB(200, 130, 255), true, 0.35)
end

function BossRenderer.start()
	Net.event("BossState").OnClientEvent:Connect(onBossState)
	Net.event("RunState").OnClientEvent:Connect(function(payload: unknown)
		if type(payload) == "table" then
			runState = payload :: { [string]: any }
			if runState.phase == "Ended" or runState.phase == "Loadout" then
				clearBoss()
				clearTelegraphs()
			end
		end
	end)
	RunService.PreRender:Connect(render)
end

return BossRenderer
