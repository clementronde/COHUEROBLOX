--!strict
-- Draws weapon visuals from WeaponFx events (WeaponFxCodec). Cosmetic only (dossier 10, section 10).
-- Pooled anchored Parts per style, one BulkMoveTo per frame, quality tiers with hard caps:
-- phones get the Low tier (fewer pieces, no fades, SmoothPlastic). Meteor/bomb telegraphs are
-- gameplay information and are always drawn (vault: VFX Performance Budgets and Culling).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Weapons = require(Config:WaitForChild("Weapons"))
local Codec = require(Shared:WaitForChild("WeaponFxCodec"))
local Heightmap = require(Shared:WaitForChild("Heightmap"))
local Net = require(Shared:WaitForChild("Net"))

local HIDDEN = CFrame.new(0, -10000, 0)
local KIND = Codec.Kind
local VIS = Codec.Visual
local PROJ_HEIGHT = 2.5

type Tier = { maxProj: number, maxAreas: number, maxSegments: number, maxAttach: number, fade: boolean, material: Enum.Material }

local TIERS: { [string]: Tier } = {
	Low = { maxProj = 60, maxAreas = 12, maxSegments = 16, maxAttach = 24, fade = false, material = Enum.Material.SmoothPlastic },
	Medium = { maxProj = 150, maxAreas = 28, maxSegments = 40, maxAttach = 48, fade = true, material = Enum.Material.Neon },
	High = { maxProj = 300, maxAreas = 56, maxSegments = 80, maxAttach = 96, fade = true, material = Enum.Material.Neon },
}

-- Visual styles: shape + colour + base size (studs) per weapon index / special visual.
type Style = { shape: Enum.PartType, color: Color3, size: Vector3 }

local STYLES: { [number]: Style } = {
	[1] = { shape = Enum.PartType.Block, color = Color3.fromRGB(190, 120, 60), size = Vector3.new(2.4, 0.4, 1.2) }, -- axe
	[2] = { shape = Enum.PartType.Block, color = Color3.fromRGB(240, 240, 255), size = Vector3.new(1.4, 0.2, 0.3) }, -- feather
	[3] = { shape = Enum.PartType.Block, color = Color3.fromRGB(150, 160, 175), size = Vector3.new(1.6, 2.2, 1.6) }, -- turret
	[4] = { shape = Enum.PartType.Block, color = Color3.fromRGB(255, 240, 90), size = Vector3.new(1, 0.2, 1) }, -- claws
	[5] = { shape = Enum.PartType.Cylinder, color = Color3.fromRGB(150, 110, 70), size = Vector3.new(0.3, 1, 1) }, -- quake
	[6] = { shape = Enum.PartType.Cylinder, color = Color3.fromRGB(130, 200, 90), size = Vector3.new(0.4, 1, 1) }, -- spores
	[7] = { shape = Enum.PartType.Block, color = Color3.fromRGB(255, 120, 40), size = Vector3.new(1, 0.3, 1) }, -- flame
	[8] = { shape = Enum.PartType.Cylinder, color = Color3.fromRGB(255, 90, 60), size = Vector3.new(0.3, 1, 1) }, -- meteor
	[9] = { shape = Enum.PartType.Block, color = Color3.fromRGB(170, 230, 255), size = Vector3.new(0.3, 0.3, 1) }, -- prism
	[10] = { shape = Enum.PartType.Cylinder, color = Color3.fromRGB(180, 90, 200), size = Vector3.new(0.3, 1, 1) }, -- whip
	[11] = { shape = Enum.PartType.Cylinder, color = Color3.fromRGB(200, 200, 210), size = Vector3.new(0.3, 2.4, 2.4) }, -- saw
	[12] = { shape = Enum.PartType.Ball, color = Color3.fromRGB(40, 40, 90), size = Vector3.new(2, 2, 2) }, -- bowling
	[13] = { shape = Enum.PartType.Block, color = Color3.fromRGB(255, 70, 160), size = Vector3.new(0.4, 0.4, 1) }, -- laser
	[14] = { shape = Enum.PartType.Cylinder, color = Color3.fromRGB(90, 160, 255), size = Vector3.new(0.3, 1, 1) }, -- umbrella wave
	[15] = { shape = Enum.PartType.Cylinder, color = Color3.fromRGB(255, 150, 230), size = Vector3.new(0.3, 1, 1) }, -- glitter
	[16] = { shape = Enum.PartType.Ball, color = Color3.fromRGB(160, 220, 255), size = Vector3.new(1.4, 1.4, 1.4) }, -- bubble
	[VIS.FelyneBolt] = { shape = Enum.PartType.Cylinder, color = Color3.fromRGB(255, 255, 120), size = Vector3.new(0.3, 1, 1) },
	[VIS.CornuRam] = { shape = Enum.PartType.Cylinder, color = Color3.fromRGB(255, 200, 150), size = Vector3.new(0.3, 1, 1) },
	[VIS.Ghost] = { shape = Enum.PartType.Ball, color = Color3.fromRGB(235, 235, 255), size = Vector3.new(1.4, 1.6, 1.4) },
	[VIS.Whistle] = { shape = Enum.PartType.Cylinder, color = Color3.fromRGB(255, 255, 255), size = Vector3.new(0.2, 1, 1) },
	[VIS.Megaphone] = { shape = Enum.PartType.Cylinder, color = Color3.fromRGB(255, 220, 80), size = Vector3.new(0.2, 1, 1) },
	[VIS.Thorns] = { shape = Enum.PartType.Cylinder, color = Color3.fromRGB(140, 120, 100), size = Vector3.new(0.2, 1, 1) },
	[VIS.Contagion] = { shape = Enum.PartType.Cylinder, color = Color3.fromRGB(110, 220, 70), size = Vector3.new(0.2, 1, 1) },
	[VIS.ChainBolt] = { shape = Enum.PartType.Block, color = Color3.fromRGB(255, 255, 140), size = Vector3.new(0.3, 0.3, 1) },
	[VIS.MiniBomb] = { shape = Enum.PartType.Cylinder, color = Color3.fromRGB(255, 180, 240), size = Vector3.new(0.3, 1, 1) },
}
local DEFAULT_STYLE: Style = { shape = Enum.PartType.Block, color = Color3.new(1, 1, 1), size = Vector3.new(1, 1, 1) }
local KITE_STYLE: Style = { shape = Enum.PartType.Block, color = Color3.fromRGB(255, 120, 180), size = Vector3.new(2, 0.2, 2.4) }
local TELEGRAPH_STYLE: Style = { shape = Enum.PartType.Cylinder, color = Color3.fromRGB(255, 40, 40), size = Vector3.new(0.15, 1, 1) }

type ProjEntry = {
	part: BasePart,
	key: string,
	visual: number,
	x0: number,
	z0: number,
	vx: number,
	vz: number,
	t0: number,
	life: number,
	slot: number,
	boomerang: boolean,
	outTime: number,
	x: number,
	z: number,
	returning: boolean,
	last: number,
}

type AreaEntry = {
	part: BasePart,
	key: string,
	telegraph: BasePart?,
	x: number,
	z: number,
	radius: number,
	dir: number,
	half: number,
	t0: number,
	delay: number,
	life: number,
}

type SegEntry = { part: BasePart, key: string, t0: number, life: number }

type AttachEntry = {
	parts: { BasePart },
	key: string,
	visual: number,
	slot: number,
	fixed: boolean,
	x: number,
	z: number,
	radius: number,
	count: number,
	spin: number,
	t0: number,
	life: number,
}

local WeaponFX = {}

local tier: Tier = TIERS.Medium
local container: Folder
local pools: { [string]: { BasePart } } = {}
local projs: { [number]: ProjEntry } = {}
local projCount = 0
local areas: { AreaEntry } = {}
local segs: { SegEntry } = {}
local attaches: { AttachEntry } = {}
local slotCache: { [number]: Player } = {}
local latestTick = 0

local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

-- Quality ---------------------------------------------------------------------------------------

local function detectTier(): Tier
	-- Heuristic (vault: Mobile and Low-End Optimization): touch without keyboard = phone/tablet.
	local camera = Workspace.CurrentCamera
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		local short = if camera then math.min(camera.ViewportSize.X, camera.ViewportSize.Y) else 400
		return if short < 500 then TIERS.Low else TIERS.Medium
	end
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel
	end)
	if ok and level ~= Enum.SavedQualitySetting.Automatic then
		local v = (level :: Enum.SavedQualitySetting).Value
		if v <= 4 then
			return TIERS.Low
		elseif v <= 7 then
			return TIERS.Medium
		end
	end
	return TIERS.High
end

-- Pools -----------------------------------------------------------------------------------------

local function makePart(style: Style): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Shape = style.shape
	part.Material = tier.material
	part.Color = style.color
	part.Size = style.size
	part.CFrame = HIDDEN
	part.Parent = container
	return part
end

local function acquire(key: string, style: Style): BasePart
	local pool = pools[key]
	local part = pool and table.remove(pool)
	if part then
		part.Transparency = 0
		return part
	end
	return makePart(style)
end

local function release(key: string, part: BasePart)
	part.CFrame = HIDDEN
	local pool = pools[key]
	if not pool then
		pool = {}
		pools[key] = pool
	end
	table.insert(pool, part)
end

local function styleOf(visual: number): Style
	return STYLES[visual] or DEFAULT_STYLE
end

local function groundY(x: number, z: number): number
	return Heightmap.getY(x, z)
end

local function playerFromSlot(slot: number): Player?
	local p = slotCache[slot]
	if p and p.Parent then
		return p
	end
	for _, other in Players:GetPlayers() do
		if other:GetAttribute("FxSlot") == slot then
			slotCache[slot] = other
			return other
		end
	end
	return nil
end

local function ownerPosition(slot: number): (number?, number?)
	local p = playerFromSlot(slot)
	local character = p and p.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local pos = root.Position
		return pos.X, pos.Z
	end
	return nil, nil
end

-- Event handlers -------------------------------------------------------------------------------

local function removeProj(id: number)
	local e = projs[id]
	if e then
		release(e.key, e.part)
		projs[id] = nil
		projCount -= 1
	end
end

local function onProjectile(scale: number, visual: number, id: number, x: number, z: number, p1: number, p2: number, p3: number, p4: number)
	if projs[id] then
		removeProj(id)
	end
	if projCount >= tier.maxProj then
		return
	end
	local style = styleOf(visual)
	local key = `p{visual}`
	local part = acquire(key, style)
	part.Size = style.size * scale / (if visual == 1 then 1.8 elseif visual == 12 then 2.2 elseif visual == 16 then 1.2 else 1)
	local boomerang = visual == 1
	local outTime = if boomerang then Weapons.Defs.HacheBoomerang.base.outTime else 0
	projs[id] = {
		part = part,
		key = key,
		visual = visual,
		x0 = x,
		z0 = z,
		vx = p1 / Codec.Scale,
		vz = p2 / Codec.Scale,
		t0 = os.clock(),
		life = p3 / 10,
		slot = p4,
		boomerang = boomerang,
		outTime = outTime,
		x = x,
		z = z,
		returning = false,
		last = os.clock(),
	}
	projCount += 1
end

local function onArea(scale: number, visual: number, x: number, z: number, p1: number, p2: number, p3: number, p4: number)
	local delay = p4 / 10
	if #areas >= tier.maxAreas and delay <= 0 then
		return
	end
	local _ = scale
	local style = styleOf(visual)
	local half = p3
	local key = if half > 0 and half < 180 then `c{visual}` else `a{visual}`
	local coneStyle = if half > 0 and half < 180 then { shape = Enum.PartType.Block, color = style.color, size = Vector3.one } else style
	local part = acquire(key, coneStyle)
	local telegraph: BasePart? = nil
	if delay > 0 then
		telegraph = acquire("tele", TELEGRAPH_STYLE)
	end
	table.insert(areas, {
		part = part,
		key = key,
		telegraph = telegraph,
		x = x,
		z = z,
		radius = p1 / Codec.Scale,
		dir = p2 / 100,
		half = half,
		t0 = os.clock(),
		delay = delay,
		life = 0.3,
	})
end

local function onSegment(visual: number, x: number, z: number, p1: number, p2: number)
	if #segs >= tier.maxSegments then
		return
	end
	local x2, z2 = p1 / Codec.Scale, p2 / Codec.Scale
	local style = styleOf(visual)
	local key = `s{visual}`
	local part = acquire(key, style)
	local dx, dz = x2 - x, z2 - z
	local len = math.max(0.1, math.sqrt(dx * dx + dz * dz))
	local y1 = groundY(x, z) + (if visual == 13 then 9 else PROJ_HEIGHT)
	local y2 = groundY(x2, z2) + 1.5
	local a = Vector3.new(x, y1, z)
	local b = Vector3.new(x2, y2, z2)
	part.Size = Vector3.new(style.size.X, style.size.Y, (b - a).Magnitude)
	part.CFrame = CFrame.lookAt((a + b) * 0.5, b)
	local _ = len
	table.insert(segs, { part = part, key = key, t0 = os.clock(), life = if visual == 13 then 0.27 else 0.15 })
end

local function releaseAttach(e: AttachEntry)
	for _, part in e.parts do
		release(e.key, part)
	end
	table.clear(e.parts)
end

local function onAttach(visual: number, slot: number, x: number, z: number, p1: number, p2: number, p3: number, p4: number)
	local fixed = p3 >= 128
	local count = math.max(1, p3 % 128)
	if not fixed then
		for i, e in attaches do
			if e.slot == slot and e.visual == visual and not e.fixed then
				releaseAttach(e)
				table.remove(attaches, i)
				break
			end
		end
	end
	if #attaches >= tier.maxAttach then
		return
	end
	local style = if visual == 13 then KITE_STYLE else styleOf(visual)
	local key = `t{visual}`
	-- clouds and kites are one piece; saws and turrets one piece each
	local pieces = if visual == 11 then count else 1
	local parts = table.create(pieces)
	for k = 1, pieces do
		parts[k] = acquire(key, style)
	end
	local radius = p1 / Codec.Scale
	if visual == 6 then
		parts[1].Size = Vector3.new(0.4, radius * 2, radius * 2)
		parts[1].Transparency = if tier.fade then 0.55 else 0.4
	end
	table.insert(attaches, {
		parts = parts,
		key = key,
		visual = visual,
		slot = slot,
		fixed = fixed,
		x = x,
		z = z,
		radius = radius,
		count = count,
		spin = p4 / 20,
		t0 = os.clock(),
		life = p2 / 100,
	})
end

local function onPacket(payload: unknown)
	if typeof(payload) ~= "buffer" then
		return
	end
	local b = payload :: buffer
	local ok, header = pcall(Codec.readHeader, b)
	if not ok or not header then
		return
	end
	-- events are one-shots: older ticks are still drawn unless clearly stale
	if header.tick + 30 < latestTick then
		return
	end
	latestTick = math.max(latestTick, header.tick)
	pcall(Codec.forEach, b, header.count, function(kind, scale, visual, a, x, z, p1, p2, p3, p4)
		if kind == KIND.Projectile then
			onProjectile(scale, visual, a, x, z, p1, p2, p3, p4)
		elseif kind == KIND.End then
			removeProj(a)
		elseif kind == KIND.Area then
			onArea(scale, visual, x, z, p1, p2, p3, p4)
		elseif kind == KIND.Segment then
			onSegment(visual, x, z, p1, p2)
		elseif kind == KIND.Attach then
			onAttach(visual, a, x, z, p1, p2, p3, p4)
		end
	end)
end

-- Frame update ----------------------------------------------------------------------------------

local function queue(n: number, part: BasePart, cf: CFrame): number
	n += 1
	moveParts[n] = part
	moveCFrames[n] = cf
	return n
end

local function onFrame()
	local now = os.clock()
	local n = 0

	-- Projectiles
	for id, e in projs do
		local t = now - e.t0
		if t >= e.life then
			removeProj(id)
			continue
		end
		local dt = now - e.last
		e.last = now
		if e.boomerang and t >= e.outTime then
			local ox, oz = ownerPosition(e.slot)
			if ox and oz then
				local dx, dz = ox - e.x, oz - e.z
				local d = math.sqrt(dx * dx + dz * dz)
				if d < 2 then
					removeProj(id)
					continue
				end
				local sp = math.sqrt(e.vx * e.vx + e.vz * e.vz) * 1.2
				e.x += dx / d * sp * dt
				e.z += dz / d * sp * dt
			end
		else
			e.x = e.x0 + e.vx * t
			e.z = e.z0 + e.vz * t
		end
		local y = groundY(e.x, e.z) + (if e.visual == 12 then e.part.Size.Y * 0.5 else PROJ_HEIGHT)
		local cf = CFrame.new(e.x, y, e.z)
		if e.boomerang or e.visual == 11 then
			cf *= CFrame.Angles(0, t * 20, 0)
		elseif e.vx ~= 0 or e.vz ~= 0 then
			cf = CFrame.lookAt(cf.Position, cf.Position + Vector3.new(e.vx, 0, e.vz))
		end
		n = queue(n, e.part, cf)
	end

	-- Areas
	for i = #areas, 1, -1 do
		local e = areas[i]
		local t = now - e.t0
		local y = groundY(e.x, e.z) + 0.3
		if t < e.delay then
			local tele = e.telegraph
			if tele then
				local d = e.radius * 2
				tele.Size = Vector3.new(0.15, d, d)
				n = queue(n, tele, CFrame.new(e.x, y, e.z) * CFrame.Angles(0, 0, math.pi / 2))
				if tier.fade then
					tele.Transparency = 0.6 - 0.4 * (t / e.delay)
				end
			end
			continue
		end
		local u = (t - e.delay) / e.life
		if u >= 1 then
			release(e.key, e.part)
			local tele = e.telegraph
			if tele then
				release("tele", tele)
			end
			table.remove(areas, i)
			continue
		end
		if e.telegraph then
			release("tele", e.telegraph :: BasePart)
			e.telegraph = nil
		end
		local grow = if tier.fade then 0.4 + 0.6 * math.min(1, u * 2) else 1
		if e.half > 0 and e.half < 180 then
			local r = e.radius * grow
			local width = math.max(1, 2 * r * math.sin(math.rad(math.min(e.half, 89))))
			e.part.Size = Vector3.new(width, 0.3, r)
			local dx, dz = math.cos(e.dir), math.sin(e.dir)
			local center = Vector3.new(e.x + dx * r * 0.5, y + 1, e.z + dz * r * 0.5)
			n = queue(n, e.part, CFrame.lookAt(center, center + Vector3.new(dx, 0, dz)))
		else
			local d = e.radius * 2 * grow
			e.part.Size = Vector3.new(0.3, d, d)
			n = queue(n, e.part, CFrame.new(e.x, y, e.z) * CFrame.Angles(0, 0, math.pi / 2))
		end
		if tier.fade then
			e.part.Transparency = 0.2 + 0.8 * u
		end
	end

	-- Segments (already placed; just expire)
	for i = #segs, 1, -1 do
		local e = segs[i]
		if now - e.t0 >= e.life then
			release(e.key, e.part)
			table.remove(segs, i)
		end
	end

	-- Attached effects
	for i = #attaches, 1, -1 do
		local e = attaches[i]
		local t = now - e.t0
		if t >= e.life then
			releaseAttach(e)
			table.remove(attaches, i)
			continue
		end
		local cx, cz = e.x, e.z
		if not e.fixed then
			local ox, oz = ownerPosition(e.slot)
			if ox and oz then
				cx, cz = ox, oz
			end
		end
		local y = groundY(cx, cz)
		if e.visual == 11 then
			local count = #e.parts
			for k, part in e.parts do
				local a = t * e.spin + (k - 1) / count * math.pi * 2
				local sx, sz = cx + math.cos(a) * e.radius, cz + math.sin(a) * e.radius
				n = queue(n, part, CFrame.new(sx, y + 2, sz) * CFrame.Angles(0, t * 15, math.pi / 2))
			end
		elseif e.visual == 6 then
			n = queue(n, e.parts[1], CFrame.new(cx, y + 0.4, cz) * CFrame.Angles(0, 0, math.pi / 2))
		elseif e.visual == 13 then
			n = queue(n, e.parts[1], CFrame.new(cx + 1.5, y + 9 + math.sin(t * 3) * 0.5, cz) * CFrame.Angles(0.4, t, 0))
		else
			n = queue(n, e.parts[1], CFrame.new(cx, y + 1.1, cz))
		end
	end

	if n > 0 then
		for k = n + 1, #moveParts do
			moveParts[k] = nil :: any
			moveCFrames[k] = nil :: any
		end
		Workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- Lifecycle -------------------------------------------------------------------------------------

function WeaponFX.init()
	tier = detectTier()
	container = Instance.new("Folder")
	container.Name = "WeaponFX"
	container.Parent = Workspace
end

function WeaponFX.start()
	Net.unreliable("WeaponFx").OnClientEvent:Connect(onPacket)
	Players.PlayerRemoving:Connect(function(player)
		for slot, p in slotCache do
			if p == player then
				slotCache[slot] = nil
			end
		end
	end)
	RunService.RenderStepped:Connect(onFrame)
end

-- Debug / settings hook: "Low" | "Medium" | "High"
function WeaponFX.setQuality(name: string)
	local t = TIERS[name]
	if t then
		tier = t
	end
end

return WeaponFX
