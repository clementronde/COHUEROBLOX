--!strict
-- Builds each stage procedurally from Parts at stage start (dossier 20 section 3).
-- The layout comes from shared Heightmap (deterministic from a key), so the parts here and the
-- height grid used by enemies, loot and clients always agree. The key is published in the
-- Workspace attribute Heightmap.Attribute; clients rebuild the same layout without needing
-- streamed parts.
-- Budget: <= Worlds part budget (900) per stage, low-poly, anchored, visual parts with
-- CanTouch/CanQuery off and no shadows on small pieces (vault: "Physics Performance",
-- "Art Budgets - Triangles Draw Calls Memory").

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Worlds = require(Config:WaitForChild("Worlds"))
local Heightmap = require(Shared:WaitForChild("Heightmap"))

local PART_BUDGET = 900

local StageService = {}

local folder: Folder? = nil
local portal: Model? = nil
local cashOut: Model? = nil
local partCount = 0
local currentWorld: Worlds.World? = nil
local hazardState = { active = false, nextAt = math.huge, endsAt = 0, warned = false }

-- Part helpers -------------------------------------------------------------------------------

type PartOpts = {
	shape: string?,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	collide: boolean?,
	query: boolean?,
	shadow: boolean?,
	transparency: number?,
	name: string?,
	parent: Instance?,
}

local function makePart(o: PartOpts): BasePart
	local part: BasePart
	if o.shape == "Wedge" then
		part = Instance.new("WedgePart")
	else
		local p = Instance.new("Part")
		if o.shape == "Ball" then
			p.Shape = Enum.PartType.Ball
		elseif o.shape == "Cylinder" then
			p.Shape = Enum.PartType.Cylinder
		end
		part = p
	end
	part.Anchored = true
	part.Size = o.size
	part.CFrame = o.cframe
	part.Color = o.color
	part.Material = o.material or Enum.Material.SmoothPlastic
	part.CanCollide = o.collide ~= false
	part.CanQuery = o.query == true or (o.query == nil and o.collide ~= false)
	part.CanTouch = false
	part.CastShadow = o.shadow == true
	part.Transparency = o.transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Name = o.name or "Part"
	part.Parent = o.parent or folder
	partCount += 1
	return part
end

local function shade(c: Color3, k: number): Color3
	return Color3.new(math.clamp(c.R * k, 0, 1), math.clamp(c.G * k, 0, 1), math.clamp(c.B * k, 0, 1))
end

local UP_CYL = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis is X; rotate to vertical

-- Pieces -------------------------------------------------------------------------------------

local function buildGround(layout: Heightmap.Layout, world: Worlds.World)
	local tiles = 4
	local size = layout.size
	local step = size / tiles
	for i = 0, tiles - 1 do
		for j = 0, tiles - 1 do
			local cx = -size / 2 + step * (i + 0.5)
			local cz = -size / 2 + step * (j + 0.5)
			makePart({
				size = Vector3.new(step, 4, step),
				cframe = CFrame.new(cx, -2, cz),
				color = world.ground[(i + j) % 2 + 1],
				material = world.groundMaterial,
				shadow = false,
				name = "Ground",
			})
		end
	end
	-- Border cliffs
	local h, t = 40, 20
	for k = 0, 3 do
		local horizontal = k < 2
		local sign = if k % 2 == 0 then 1 else -1
		local offset = size / 2 + t / 2
		makePart({
			size = if horizontal then Vector3.new(size + t * 2, h, t) else Vector3.new(t, h, size + t * 2),
			cframe = if horizontal then CFrame.new(0, h / 2 - 4, sign * offset) else CFrame.new(sign * offset, h / 2 - 4, 0),
			color = world.cliff,
			material = Enum.Material.Slate,
			name = "Border",
		})
	end
end

local function buildTerrain(layout: Heightmap.Layout, world: Worlds.World)
	for _, p in layout.plateaus do
		local height = p.h - p.base
		makePart({
			size = Vector3.new(p.sx, height, p.sz),
			cframe = CFrame.new(p.x, p.base + height / 2, p.z),
			color = world.cliff,
			material = Enum.Material.Slate,
			shadow = true,
			name = "Plateau",
		})
		makePart({
			size = Vector3.new(p.sx + 0.8, 1, p.sz + 0.8),
			cframe = CFrame.new(p.x, p.h - 0.45, p.z),
			color = world.top,
			material = world.groundMaterial,
			name = "PlateauTop",
		})
	end
	for _, r in layout.ramps do
		local dir = if r.dir == 1
			then Vector3.xAxis
			elseif r.dir == 2 then -Vector3.xAxis
			elseif r.dir == 3 then Vector3.zAxis
			else -Vector3.zAxis
		local height = r.h - r.base
		local centre = Vector3.new(r.x, r.base + height / 2, r.z)
		-- WedgePart rises toward local +Z; lookVector is -Z, so look away from the rise.
		makePart({
			shape = "Wedge",
			size = Vector3.new(r.width, height, r.length),
			cframe = CFrame.lookAt(centre, centre - dir),
			color = world.ramp,
			material = world.groundMaterial,
			name = "Ramp",
		})
	end
	for _, pad in layout.pads do
		makePart({
			shape = "Cylinder",
			size = Vector3.new(0.6, 7, 7),
			cframe = CFrame.new(pad.x, pad.y + 0.3, pad.z) * UP_CYL,
			color = Color3.fromRGB(80, 255, 220),
			material = Enum.Material.Neon,
			collide = false,
			name = "JumpPad",
		})
	end
end

local function buildDecor(layout: Heightmap.Layout, world: Worlds.World)
	local id = world.id
	for _, d in layout.decor do
		if partCount > PART_BUDGET - 60 then
			break
		end
		local y = Heightmap.getY(d.x, d.z)
		local base = CFrame.new(d.x, y, d.z) * CFrame.Angles(0, math.rad(d.rot), 0)
		local s = d.s
		if id == "BoisGrognon" then
			if d.kind == "A" then -- tree: trunk collides, canopy does not (vault: low-poly tree set)
				makePart({ shape = "Cylinder", size = Vector3.new(8 * s, 2 * s, 2 * s), cframe = base * CFrame.new(0, 4 * s, 0) * UP_CYL, color = world.decorB, name = "Trunk" })
				makePart({ shape = "Ball", size = Vector3.new(9, 7, 9) * s, cframe = base * CFrame.new(0, 9.5 * s, 0), color = world.decorA, collide = false, shadow = true, name = "Canopy" })
				makePart({ shape = "Ball", size = Vector3.new(6, 5, 6) * s, cframe = base * CFrame.new(1.5 * s, 12.5 * s, 0.5 * s), color = shade(world.decorA, 1.15), collide = false, name = "Canopy" })
			elseif d.kind == "B" then
				makePart({ size = Vector3.new(4, 3, 3.4) * s, cframe = base * CFrame.new(0, 1.2 * s, 0) * CFrame.Angles(0.2, 0, 0.15), color = Color3.fromRGB(140, 140, 135), material = Enum.Material.Slate, name = "Rock" })
			else
				makePart({ shape = "Ball", size = Vector3.new(4, 2.6, 4) * s, cframe = base * CFrame.new(0, 1 * s, 0), color = shade(world.decorA, 0.85), collide = false, name = "Bush" })
			end
		elseif id == "DunesCroustillantes" then
			if d.kind == "A" then -- ruin column
				makePart({ shape = "Cylinder", size = Vector3.new(10 * s, 2.6 * s, 2.6 * s), cframe = base * CFrame.new(0, 5 * s, 0) * UP_CYL, color = world.decorA, material = Enum.Material.Sandstone, name = "Column" })
				makePart({ size = Vector3.new(3.6, 1, 3.6) * s, cframe = base * CFrame.new(0, 10.4 * s, 0), color = shade(world.decorA, 0.9), material = Enum.Material.Sandstone, name = "ColumnCap" })
			elseif d.kind == "B" then -- cactus
				makePart({ shape = "Cylinder", size = Vector3.new(7 * s, 2 * s, 2 * s), cframe = base * CFrame.new(0, 3.5 * s, 0) * UP_CYL, color = world.decorB, name = "Cactus" })
				makePart({ shape = "Cylinder", size = Vector3.new(3 * s, 1.2 * s, 1.2 * s), cframe = base * CFrame.new(1.6 * s, 4.5 * s, 0) * UP_CYL, color = shade(world.decorB, 0.9), collide = false, name = "CactusArm" })
			else
				makePart({ size = Vector3.new(5, 2.4, 4) * s, cframe = base * CFrame.new(0, 0.9 * s, 0) * CFrame.Angles(0.1, 0, 0.2), color = world.cliff, material = Enum.Material.Sandstone, name = "Rock" })
			end
		else
			if d.kind == "A" then -- desk
				makePart({ size = Vector3.new(5, 0.5, 3) * s, cframe = base * CFrame.new(0, 2.6 * s, 0), color = world.decorA, material = Enum.Material.Wood, name = "Desk" })
				makePart({ size = Vector3.new(4.4, 2.4, 0.4) * s, cframe = base * CFrame.new(0, 1.2 * s, 0), color = shade(world.decorA, 0.7), name = "DeskLeg" })
			elseif d.kind == "B" then -- bin
				makePart({ shape = "Cylinder", size = Vector3.new(3 * s, 2.2 * s, 2.2 * s), cframe = base * CFrame.new(0, 1.5 * s, 0) * UP_CYL, color = world.decorB, name = "Bin" })
			else -- hopscotch
				makePart({ size = Vector3.new(3, 0.1, 9) * s, cframe = base * CFrame.new(0, 0.06, 0), color = Color3.fromRGB(240, 240, 250), material = Enum.Material.SmoothPlastic, collide = false, name = "Hopscotch" })
			end
		end
	end
	for _, l in layout.lamps do
		local base = CFrame.new(l.x, l.y, l.z)
		makePart({ shape = "Cylinder", size = Vector3.new(12, 0.8, 0.8), cframe = base * CFrame.new(0, 6, 0) * UP_CYL, color = Color3.fromRGB(50, 50, 60), name = "LampPole" })
		local head = makePart({ shape = "Ball", size = Vector3.new(2, 2, 2), cframe = base * CFrame.new(0, 12.5, 0), color = Color3.fromRGB(255, 230, 150), material = Enum.Material.Neon, collide = false, name = "LampHead" })
		local light = Instance.new("PointLight")
		light.Range = 22
		light.Brightness = 2
		light.Color = Color3.fromRGB(255, 225, 160)
		light.Shadows = false
		light.Parent = head
	end
end

local function buildArena(layout: Heightmap.Layout, world: Worlds.World)
	local a = layout.arche
	local c = CFrame.new(a.x, 0, a.z)
	makePart({
		shape = "Cylinder",
		size = Vector3.new(0.12, layout.arenaRadius * 2, layout.arenaRadius * 2),
		cframe = c * CFrame.new(0, 0.06, 0) * UP_CYL,
		color = shade(world.ground[1], 0.8),
		collide = false,
		name = "ArenaFloor",
	})
	-- Arche: two pillars, a lintel and a glowing veil (the reveal trigger is a distance check).
	local model = Instance.new("Model")
	model.Name = "Arche"
	model.Parent = folder
	local stone = Color3.fromRGB(110, 100, 130)
	makePart({ size = Vector3.new(3, 16, 3), cframe = c * CFrame.new(-6, 8, 0), color = stone, material = Enum.Material.Slate, shadow = true, parent = model, name = "ArchePillar" })
	makePart({ size = Vector3.new(3, 16, 3), cframe = c * CFrame.new(6, 8, 0), color = stone, material = Enum.Material.Slate, shadow = true, parent = model, name = "ArchePillar" })
	local lintel = makePart({ size = Vector3.new(16, 3, 4), cframe = c * CFrame.new(0, 17.5, 0), color = shade(stone, 1.2), material = Enum.Material.Slate, shadow = true, parent = model, name = "ArcheLintel" })
	makePart({ size = Vector3.new(9, 15, 0.4), cframe = c * CFrame.new(0, 7.5, 0), color = Color3.fromRGB(190, 120, 255), material = Enum.Material.Neon, transparency = 0.35, collide = false, parent = model, name = "ArcheVeil" })
	model.PrimaryPart = lintel

	for _, p in layout.pillars do
		makePart({ shape = "Cylinder", size = Vector3.new(p.h, p.r * 2, p.r * 2), cframe = CFrame.new(p.x, p.h / 2, p.z) * UP_CYL, color = Color3.fromRGB(215, 190, 140), material = Enum.Material.Sandstone, shadow = true, name = "RuinPillar" })
	end
	for _, w in layout.weakPoints do
		local top = CFrame.new(w.x, w.y, w.z)
		if layout.bossId == "DirectriceEternelle" then
			makePart({ shape = "Ball", size = Vector3.new(3, 3, 3), cframe = top * CFrame.new(0, 5, 0), color = Color3.fromRGB(255, 205, 60), material = Enum.Material.Metal, collide = false, name = "Bell" })
			makePart({ size = Vector3.new(0.6, 4, 0.6), cframe = top * CFrame.new(0, 7.5, 0), color = Color3.fromRGB(60, 50, 40), collide = false, name = "BellRope" })
		elseif layout.bossId == "GrandBrouhaha" then
			makePart({ shape = "Cylinder", size = Vector3.new(0.6, 5, 5), cframe = top * CFrame.new(0, 3.2, 0) * CFrame.Angles(0, math.rad(90), 0), color = Color3.fromRGB(255, 190, 50), material = Enum.Material.Metal, collide = false, name = "Gong" })
		else
			makePart({ shape = "Ball", size = Vector3.new(4, 2, 4), cframe = top * CFrame.new(0, 0.5, 0), color = Color3.fromRGB(80, 160, 60), collide = false, name = "BranchLeaves" })
		end
	end
end

local function applyLighting(world: Worlds.World)
	Lighting.ClockTime = world.sky.clock
	Lighting.Ambient = world.sky.ambient
	Lighting.OutdoorAmbient = world.sky.ambient
	Lighting.FogColor = world.sky.fog
end

-- Public -------------------------------------------------------------------------------------

-- Builds the stage and publishes its key. Returns the layout.
function StageService.buildStage(worldId: string, stage: number, seed: number, bossId: string): Heightmap.Layout?
	StageService.clear()
	local key = Heightmap.makeKey(worldId, stage, seed, bossId)
	local layout = Heightmap.load(key)
	if not layout then
		warn("[StageService] bad stage key", key)
		return nil
	end
	local world = Worlds[layout.worldId]
	currentWorld = world
	local f = Instance.new("Folder")
	f.Name = "Stage"
	folder = f
	partCount = 0
	buildGround(layout, world)
	buildTerrain(layout, world)
	buildArena(layout, world)
	buildDecor(layout, world)
	if partCount > PART_BUDGET then
		warn(`[StageService] {partCount} parts, over the {PART_BUDGET} budget`)
	end
	f.Parent = Workspace
	applyLighting(world)
	Workspace:SetAttribute(Heightmap.Attribute, key)
	hazardState.active = false
	hazardState.nextAt = world.hazard.firstAt
	hazardState.warned = false
	Workspace:SetAttribute("CohueHazard", "")
	return layout
end

function StageService.clear()
	if folder then
		folder:Destroy()
		folder = nil
	end
	portal = nil
	cashOut = nil
	partCount = 0
	Workspace:SetAttribute(Heightmap.Attribute, "")
	Workspace:SetAttribute("CohueHazard", "")
	Heightmap.clear()
end

-- Loot domain (dossier 20 section 3): points on the real ground, outside the boss arena.
function StageService.getSpawnPoints(kind: string): { Vector3 }
	local layout = Heightmap.getLayout()
	local out: { Vector3 } = {}
	if not layout then
		return out
	end
	for _, p in layout.spawnPoints[kind] or {} do
		table.insert(out, Vector3.new(p.x, p.y, p.z))
	end
	return out
end

function StageService.getArche(): Vector3?
	local layout = Heightmap.getLayout()
	if not layout then
		return nil
	end
	return Vector3.new(layout.arche.x, 0, layout.arche.z)
end

function StageService.getPartCount(): number
	return partCount
end

-- Panneau au-dessus d'un portail (texte joueur en anglais, police cartoon intégrée).
local function addSign(parent: Model, anchor: BasePart, text: string, color: Color3)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = UDim2.fromOffset(260, 70)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 220
	gui.LightInfluence = 0
	gui.Adornee = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.fromRGB(30, 20, 40)
	label.Parent = gui
	gui.Parent = parent
end

local function buildPortal(position: Vector3, name: string, color: Color3, sign: string): Model?
	if not folder then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = folder
	local c = CFrame.new(position.X, position.Y, position.Z)
	makePart({ shape = "Cylinder", size = Vector3.new(0.4, 16, 16), cframe = c * CFrame.new(0, 0.2, 0) * UP_CYL, color = color, material = Enum.Material.Neon, collide = false, transparency = 0.2, parent = model, name = "PortalDisc" })
	local beam = makePart({ shape = "Cylinder", size = Vector3.new(30, 4, 4), cframe = c * CFrame.new(0, 15, 0) * UP_CYL, color = color, material = Enum.Material.Neon, collide = false, transparency = 0.5, parent = model, name = "PortalBeam" })
	addSign(model, beam, sign, color)
	return model
end

-- Portail vers le monde suivant (boss tué, hors dernier monde).
function StageService.showPortal(position: Vector3)
	if portal then
		return
	end
	portal = buildPortal(position, "Portal", Color3.fromRGB(120, 255, 200), "NEXT WORLD")
end

-- Portail doré après le boss du dernier monde (A04-02) : tous les joueurs dedans = Cash out.
function StageService.showCashOut(position: Vector3)
	if cashOut then
		return
	end
	cashOut = buildPortal(position, "CashOut", Color3.fromRGB(255, 205, 60), "CASH OUT")
end

-- Hazards (dossier 20 section 3). Called by RunManager with seconds since stage start.
-- Returns "warn" | "start" | "end" | nil so RunManager can announce.
function StageService.updateHazard(elapsed: number): string?
	local world = currentWorld
	if not world then
		return nil
	end
	local hz = world.hazard
	if hazardState.active then
		if elapsed >= hazardState.endsAt then
			hazardState.active = false
			hazardState.nextAt = hazardState.endsAt - hz.duration + hz.every
			hazardState.warned = false
			Workspace:SetAttribute("CohueHazard", "")
			return "end"
		end
		return nil
	end
	if not hazardState.warned and elapsed >= hazardState.nextAt - hz.warn then
		hazardState.warned = true
		return "warn"
	end
	if elapsed >= hazardState.nextAt then
		hazardState.active = true
		hazardState.endsAt = elapsed + hz.duration
		Workspace:SetAttribute("CohueHazardAngle", math.random() * math.pi * 2)
		Workspace:SetAttribute("CohueHazardEnd", Workspace:GetServerTimeNow() + hz.duration)
		Workspace:SetAttribute("CohueHazard", hz.id)
		return "start"
	end
	return nil
end

function StageService.stopHazard()
	hazardState.active = false
	hazardState.nextAt = math.huge
	Workspace:SetAttribute("CohueHazard", "")
end

function StageService.getWorld(): Worlds.World?
	return currentWorld
end

function StageService.init()
	Workspace:SetAttribute(Heightmap.Attribute, "")
	Workspace:SetAttribute("CohueHazard", "")
end

return StageService
