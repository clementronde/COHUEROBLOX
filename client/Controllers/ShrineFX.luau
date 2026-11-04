--!strict
-- Shrine visuals from ShrineState: circle, pillar, progress disc, golden glow, Prankster prompt.
-- Also plays the Prankster team gags from ShrineGag. Design rule: gags never touch the avatar
-- (only screen, camera roll and colour tint), and never write FieldOfView (one FOV owner).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Shrines = require(Config:WaitForChild("Shrines"))
local Net = require(Shared:WaitForChild("Net"))

local FX = Shrines.FX
local localPlayer = Players.LocalPlayer
local isFrench = string.sub(string.lower(localPlayer.LocaleId), 1, 2) == "fr"
local FLAT = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis X -> Y
local DONE_COLOR = Color3.fromRGB(110, 110, 110)
local TILT_BIND = "ShrineFXTilt"

type Visual = {
	id: number,
	kind: string,
	state: string,
	position: Vector3,
	target: number, -- server progress
	shown: number, -- smoothed progress
	circle: BasePart,
	pillar: BasePart,
	disc: BasePart,
	light: PointLight?,
	prompt: ProximityPrompt?,
}

local ShrineFX = {}

local visuals: { [number]: Visual } = {}
local container: Folder
local interactRemote: RemoteEvent
local reduceFlashes = false

-- Gag state
local gagEnds: { [string]: number } = {}
local colorEffect: ColorCorrectionEffect? = nil
local confettiGui: ScreenGui? = nil
local confetti: { { frame: Frame, x: number, y: number, vy: number, spin: number } } = {}
local tiltBound = false

local function makePart(shape: Enum.PartType, size: Vector3, color: Color3, transparency: number): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Transparency = transparency
	part.Parent = container
	return part
end

local function kindColor(kind: string): Color3
	local def = Shrines.Kinds[kind]
	return if def then def.color else Color3.new(1, 1, 1)
end

local function kindName(kind: string): string
	local def = Shrines.Kinds[kind]
	if not def then
		return kind
	end
	return if isFrench then def.name.fr else def.name.en
end

local function applyLook(v: Visual)
	local finished = v.state == "Done" or v.state == "Failed"
	local color = if finished then DONE_COLOR else kindColor(v.kind)
	v.circle.Color = color
	v.circle.Transparency = if finished then 0.9 else 0.65
	v.pillar.Color = color
	v.disc.Color = color
	v.disc.Transparency = if finished then 1 else 0.35
	local light = v.light
	if light then
		light.Enabled = not finished
	end
	local prompt = v.prompt
	if prompt then
		prompt.Enabled = not finished
	end
end

local function createVisual(id: number, kind: string, position: Vector3): Visual
	local r = Shrines.Radius
	local base = CFrame.new(position)
	local circle = makePart(Enum.PartType.Cylinder, Vector3.new(FX.CircleHeight, r * 2, r * 2), kindColor(kind), 0.65)
	circle.CFrame = base * CFrame.new(0, FX.CircleHeight / 2, 0) * FLAT
	local pillar = makePart(Enum.PartType.Block, FX.PillarSize, kindColor(kind), 0)
	pillar.Material = Enum.Material.SmoothPlastic
	pillar.CFrame = base * CFrame.new(0, FX.PillarSize.Y / 2, 0)
	local disc = makePart(Enum.PartType.Cylinder, Vector3.new(FX.CircleHeight, 0.1, 0.1), kindColor(kind), 0.35)
	disc.CFrame = base * CFrame.new(0, FX.CircleHeight + 0.05, 0) * FLAT

	local v: Visual = {
		id = id,
		kind = kind,
		state = "Idle",
		position = position,
		target = 0,
		shown = 0,
		circle = circle,
		pillar = pillar,
		disc = disc,
		light = nil,
		prompt = nil,
	}
	if kind == "Golden" then
		-- One light per golden shrine only (VFX budget: few lights).
		local light = Instance.new("PointLight")
		light.Color = kindColor(kind)
		light.Range = FX.GoldenLightRange
		light.Brightness = FX.GoldenLightBrightness
		light.Parent = pillar
		v.light = light
	end
	if kind == "Prankster" then
		local prompt = Instance.new("ProximityPrompt")
		prompt.RequiresLineOfSight = false
		prompt.HoldDuration = 0.3
		prompt.MaxActivationDistance = Shrines.InteractRange
		prompt.ObjectText = kindName(kind)
		prompt.ActionText = if isFrench then "Jouer" else "Play"
		prompt.Triggered:Connect(function()
			interactRemote:FireServer(id)
		end)
		prompt.Parent = pillar
		v.prompt = prompt
	end
	return v
end

local function destroyVisual(v: Visual)
	v.circle:Destroy()
	v.pillar:Destroy()
	v.disc:Destroy()
	visuals[v.id] = nil
end

local function onState(payload: any)
	if type(payload) ~= "table" or type(payload.shrines) ~= "table" then
		return
	end
	local seen: { [number]: boolean } = {}
	for _, s in payload.shrines do
		if type(s) ~= "table" or type(s.id) ~= "number" or type(s.kind) ~= "string" or typeof(s.position) ~= "Vector3" then
			continue
		end
		seen[s.id] = true
		local v = visuals[s.id]
		if v and (v.kind ~= s.kind or v.position ~= s.position) then
			destroyVisual(v)
			v = nil
		end
		if not v then
			v = createVisual(s.id, s.kind, s.position)
			visuals[s.id] = v
		end
		local visual = v :: Visual
		visual.target = if type(s.progress) == "number" then math.clamp(s.progress, 0, 1) else 0
		local state = if type(s.state) == "string" then s.state else "Idle"
		if state ~= visual.state then
			visual.state = state
			applyLook(visual)
		end
		local prompt = visual.prompt
		if prompt and type(s.cost) == "number" then
			prompt.ActionText = if isFrench then `Jouer ({s.cost} pièces)` else `Play ({s.cost} coins)`
		end
	end
	for id, v in visuals do
		if not seen[id] then
			destroyVisual(v)
		end
	end
end

-- Gags -------------------------------------------------------------------------

local function gagActive(gag: string, now: number): boolean
	local t = gagEnds[gag]
	return t ~= nil and now < t
end

local function startConfetti()
	if confettiGui then
		return
	end
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "ShrineConfetti"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = -1 -- under the HUD
	for i = 1, FX.ConfettiCount do
		local frame = Instance.new("Frame")
		frame.BorderSizePixel = 0
		frame.Size = UDim2.fromOffset(8, 14)
		frame.BackgroundColor3 = Color3.fromHSV((i * 0.137) % 1, 0.8, 1)
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Parent = gui
		confetti[i] = { frame = frame, x = math.random(), y = -math.random(), vy = 0.12 + math.random() * 0.12, spin = math.random(-200, 200) }
	end
	gui.Parent = playerGui
	confettiGui = gui
end

local function stopConfetti()
	local gui = confettiGui
	if gui then
		gui:Destroy()
		confettiGui = nil
	end
	table.clear(confetti)
end

local function stopTilt()
	if tiltBound then
		RunService:UnbindFromRenderStep(TILT_BIND)
		tiltBound = false
	end
end

local function startTilt()
	if tiltBound then
		return
	end
	tiltBound = true
	-- After the camera scripts: add a roll on top of their CFrame for this frame only.
	RunService:BindToRenderStep(TILT_BIND, Enum.RenderPriority.Camera.Value + 1, function()
		local camera = Workspace.CurrentCamera
		if camera then
			local roll = math.rad(FX.TiltDegrees) * math.sin(os.clock() * 0.8)
			camera.CFrame *= CFrame.Angles(0, 0, roll)
		end
	end)
end

local function onGag(payload: any)
	if type(payload) ~= "table" or type(payload.gag) ~= "string" or type(payload.duration) ~= "number" then
		return
	end
	if not table.find(Shrines.Gags, payload.gag) then
		return
	end
	local duration = math.clamp(payload.duration, 0, 60)
	gagEnds[payload.gag] = os.clock() + duration
	if payload.gag == "Confetti" then
		startConfetti()
	elseif payload.gag == "CameraTilt" then
		startTilt()
	elseif payload.gag == "Disco" and not colorEffect then
		local effect = Instance.new("ColorCorrectionEffect")
		effect.Name = "ShrineDisco"
		effect.Parent = Lighting
		colorEffect = effect
	end
end

local function updateGags(dt: number, now: number)
	if confettiGui then
		if not gagActive("Confetti", now) then
			stopConfetti()
		else
			for _, c in confetti do
				c.y += c.vy * dt
				if c.y > 1.05 then
					c.y = -0.05
					c.x = math.random()
				end
				c.frame.Position = UDim2.fromScale(c.x, c.y)
				c.frame.Rotation = (c.frame.Rotation + c.spin * dt) % 360
			end
		end
	end
	if tiltBound and not gagActive("CameraTilt", now) then
		stopTilt()
	end
	local effect = colorEffect
	if effect then
		if not gagActive("Disco", now) then
			effect:Destroy()
			colorEffect = nil
		else
			-- Slow hue cycle, no flashing; weaker when the player asked for fewer flashes.
			local hue = (now / FX.DiscoCycle) % 1
			effect.TintColor = Color3.fromHSV(hue, if reduceFlashes then 0.12 else 0.3, 1)
		end
	end
end

-- Frame loop -------------------------------------------------------------------

local function render(dt: number)
	local now = os.clock()
	local r = Shrines.Radius
	for _, v in visuals do
		if v.shown ~= v.target then
			local diff = v.target - v.shown
			local stepLen = dt * 3
			v.shown = if math.abs(diff) <= stepLen then v.target else v.shown + math.sign(diff) * stepLen
			local d = math.max(0.1, r * 2 * v.shown)
			v.disc.Size = Vector3.new(FX.CircleHeight, d, d)
		end
		local light = v.light
		if light and light.Enabled then
			light.Brightness = FX.GoldenLightBrightness * (0.75 + 0.25 * math.sin(now * 2))
		end
	end
	updateGags(dt, now)
end

function ShrineFX.init()
	container = Instance.new("Folder")
	container.Name = "ClientShrines"
	container.Parent = Workspace
end

function ShrineFX.start()
	interactRemote = Net.event("ShrineInteract")
	Net.event("ShrineState").OnClientEvent:Connect(onState)
	Net.event("ShrineGag").OnClientEvent:Connect(onGag)
	Net.event("Profile").OnClientEvent:Connect(function(profile: any)
		if type(profile) == "table" and type(profile.settings) == "table" then
			reduceFlashes = profile.settings.reduceFlashes == true
		end
	end)
	RunService.PreRender:Connect(render)
end

return ShrineFX
