--!strict
-- Draws every companion from CompanionSnapshot (docs/dossier/40-compagnons.md section 12).
-- Low-poly creatures built from anchored, non-colliding, non-queryable Parts (no asset ids),
-- interpolated between server samples and moved with one BulkMoveTo per frame. Attack,
-- evolution and ultimate effects come from a bounded part pool (no create/destroy per hit).
--
-- Ultimate trigger (both paths fire the CompanionUltimate remote; the server validates):
--   * keyboard / gamepad: InputController.onAction("Ultimate", fn) (avatar domain)
--   * UI button: Registry.get("CompanionRenderer").requestUltimate()
-- HUD data: CompanionRenderer.getState() / CompanionRenderer.onStateChanged(fn) (CompanionState payload).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Companions = require(Config:WaitForChild("Companions"))
local Net = require(Shared:WaitForChild("Net"))
local Registry = require(Shared:WaitForChild("Registry"))

type LineDef = Companions.LineDef

local NET = Companions.Net
local SAMPLE_DT = 1 / Companions.SimHz
local STALE_SECONDS = 1.5 -- drop a companion not seen for this long (run ended, owner left)
local HIDDEN = CFrame.new(0, -10000, 0)
local TWO_PI = math.pi * 2
local MAX_FX = 48

export type State = {
	line: string,
	stage: number,
	level: number,
	name: { fr: string, en: string },
	ultimateCharge: number,
	stunned: boolean,
	techs: { { id: string, level: number } },
}

type Body = {
	parts: { BasePart },
	offsets: { CFrame },
	height: number,
}

type Entry = {
	userId: number,
	line: LineDef,
	stage: number,
	body: Body,
	stars: { BasePart },
	fromPos: Vector3,
	toPos: Vector3,
	fromYaw: number,
	toYaw: number,
	t0: number,
	span: number,
	lastTick: number,
	lastSeen: number,
	evSeq: number,
	stunned: boolean,
	ultimate: boolean,
	ultFxAcc: number,
	drawPos: Vector3,
	phase: number,
}

type Fx = {
	part: BasePart,
	shape: "Ball" | "Ring",
	active: boolean,
	t0: number,
	dur: number,
	fromPos: Vector3,
	toPos: Vector3,
	fromSize: Vector3,
	toSize: Vector3,
	fromAlpha: number,
	toAlpha: number,
}

local CompanionRenderer = {}

local container: Folder
local entries: { [number]: Entry } = {}
local latestTick = 0
local state: State? = nil
local stateListeners: { (State) -> () } = {}
local lastRequest = 0

local fxList: { Fx } = {}

-- Reused BulkMoveTo arrays
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

-- Body building ------------------------------------------------------------------------------------

local function newPart(shape: "Ball" | "Block" | "Cylinder" | "Wedge"): BasePart
	local part: BasePart
	if shape == "Wedge" then
		part = Instance.new("WedgePart")
	else
		local p = Instance.new("Part")
		p.Shape = if shape == "Ball"
			then Enum.PartType.Ball
			elseif shape == "Cylinder" then Enum.PartType.Cylinder
			else Enum.PartType.Block
		part = p
	end
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = HIDDEN
	return part
end

type Builder = {
	s: number,
	body: Body,
	add: (self: Builder, shape: "Ball" | "Block" | "Cylinder" | "Wedge", size: Vector3, cf: CFrame, color: Color3, neon: boolean?) -> (),
}

local function makeBuilder(s: number, height: number): Builder
	local b = {} :: Builder
	b.s = s
	b.body = { parts = {}, offsets = {}, height = height }
	function b.add(self: Builder, shape, size, cf, color, neon)
		local part = newPart(shape)
		part.Size = size * self.s
		part.Color = color
		if neon then
			part.Material = Enum.Material.Neon
		end
		part.Parent = container
		table.insert(self.body.parts, part)
		table.insert(self.body.offsets, CFrame.new(cf.Position * self.s) * cf.Rotation)
	end
	return b
end

local V = Vector3.new
local CF = CFrame.new
local BLACK = Color3.fromRGB(25, 25, 30)
local WHITE = Color3.fromRGB(250, 250, 250)
-- Upright cylinder: Roblox cylinders run along X, so roll them 90 degrees.
local UP = CFrame.Angles(0, 0, math.pi / 2)

local function eyes(b: Builder, y: number, z: number, spread: number, size: number)
	b:add("Ball", V(size, size, size), CF(-spread, y, z), BLACK)
	b:add("Ball", V(size, size, size), CF(spread, y, z), BLACK)
	b:add("Ball", V(size * 0.4, size * 0.4, size * 0.4), CF(-spread + 0.05, y + 0.06, z - size * 0.4), WHITE, true)
	b:add("Ball", V(size * 0.4, size * 0.4, size * 0.4), CF(spread + 0.05, y + 0.06, z - size * 0.4), WHITE, true)
end

-- Every body is designed facing -Z (CFrame forward), feet at y = 0, about 2 studs tall at s = 1.
local Builders: { [string]: (b: Builder, stage: number, c: { [string]: Color3 }) -> () } = {}

Builders.Braise = function(b, stage, c)
	if stage == 1 then
		-- Tisonnet: squat lizard, match head on the skull
		b:add("Ball", V(1.4, 1.1, 1.8), CF(0, 0.7, 0), c.primary)
		b:add("Ball", V(1.1, 1.0, 1.0), CF(0, 1.3, -0.9), c.primary)
		b:add("Ball", V(0.55, 0.55, 0.55), CF(0, 1.9, -0.9), c.accent, true)
		b:add("Block", V(0.35, 0.3, 1.1), CF(0, 0.55, 1.2) * CFrame.Angles(0.3, 0, 0), c.secondary)
		for _, sx in { -0.5, 0.5 } do
			for _, sz in { -0.5, 0.5 } do
				b:add("Block", V(0.3, 0.4, 0.3), CF(sx, 0.2, sz), c.secondary)
			end
		end
		eyes(b, 1.4, -1.35, 0.25, 0.22)
	elseif stage == 2 then
		-- Fournaïde: upright lizard, glowing oven-door belly, two shoulder chimneys
		b:add("Ball", V(1.3, 1.6, 1.2), CF(0, 1.0, 0), c.primary)
		b:add("Ball", V(1.1, 1.0, 1.0), CF(0, 2.0, -0.2), c.primary)
		b:add("Block", V(0.7, 0.6, 0.1), CF(0, 0.95, -0.6), c.glow, true)
		b:add("Block", V(0.3, 0.5, 0.3), CF(-0.5, 1.9, 0.35), c.secondary)
		b:add("Block", V(0.3, 0.5, 0.3), CF(0.5, 1.9, 0.35), c.secondary)
		b:add("Block", V(0.2, 0.1, 0.2), CF(-0.5, 2.2, 0.35), c.glow, true)
		b:add("Block", V(0.2, 0.1, 0.2), CF(0.5, 2.2, 0.35), c.glow, true)
		b:add("Block", V(0.35, 0.3, 1.0), CF(0, 0.4, 0.9) * CFrame.Angles(0.4, 0, 0), c.secondary)
		b:add("Block", V(0.4, 0.4, 0.5), CF(-0.35, 0.2, -0.1), c.secondary)
		b:add("Block", V(0.4, 0.4, 0.5), CF(0.35, 0.2, -0.1), c.secondary)
		eyes(b, 2.1, -0.65, 0.25, 0.2)
	else
		-- Volcarapace: big four-legged lizard, dark back plates with glowing vents
		b:add("Ball", V(1.8, 1.1, 2.3), CF(0, 0.85, 0), c.primary)
		b:add("Ball", V(1.0, 0.9, 1.0), CF(0, 1.1, -1.35), c.primary)
		for k, z in { -0.6, 0.1, 0.8 } do
			b:add("Wedge", V(0.9, 0.5, 0.7), CF(0, 1.45, z), c.secondary)
			b:add("Block", V(0.2, 0.15, 0.2), CF(0, 1.75, z + 0.1), if k == 2 then c.accent else c.glow, true)
		end
		b:add("Block", V(0.4, 0.35, 1.3), CF(0, 0.6, 1.6) * CFrame.Angles(0.25, 0, 0), c.secondary)
		for _, sx in { -0.75, 0.75 } do
			for _, sz in { -0.7, 0.7 } do
				b:add("Block", V(0.4, 0.5, 0.4), CF(sx, 0.25, sz), c.secondary)
			end
		end
		eyes(b, 1.25, -1.8, 0.25, 0.18)
	end
end

Builders.Ronce = function(b, stage, c)
	if stage == 1 then
		-- Pousseron: walking acorn with a sprout
		b:add("Ball", V(1.2, 1.4, 1.2), CF(0, 0.85, 0), c.primary)
		b:add("Ball", V(1.35, 0.6, 1.35), CF(0, 1.5, 0), c.secondary:Lerp(c.primary, 0.6))
		b:add("Block", V(0.12, 0.4, 0.12), CF(0, 1.95, 0), c.secondary)
		b:add("Ball", V(0.35, 0.15, 0.25), CF(0.15, 2.15, 0), c.secondary)
		b:add("Block", V(0.35, 0.2, 0.45), CF(-0.3, 0.1, -0.05), c.secondary:Lerp(BLACK, 0.4))
		b:add("Block", V(0.35, 0.2, 0.45), CF(0.3, 0.1, -0.05), c.secondary:Lerp(BLACK, 0.4))
		eyes(b, 1.0, -0.58, 0.22, 0.2)
	elseif stage == 2 then
		-- Ronciflore: split acorn, bramble crown with flowers, vine arms
		b:add("Ball", V(1.5, 1.7, 1.5), CF(0, 1.05, 0), c.primary)
		b:add("Ball", V(1.6, 0.35, 1.6), CF(0, 1.85, 0), c.secondary)
		for k = 0, 4 do
			local a = k / 5 * TWO_PI
			b:add("Wedge", V(0.2, 0.6, 0.3), CF(math.cos(a) * 0.55, 2.2, math.sin(a) * 0.55) * CFrame.Angles(0, -a, 0), c.secondary)
			if k % 2 == 0 then
				b:add("Ball", V(0.3, 0.3, 0.3), CF(math.cos(a) * 0.55, 2.55, math.sin(a) * 0.55), c.accent)
			end
		end
		b:add("Block", V(0.2, 0.9, 0.2), CF(-0.85, 1.0, -0.1) * CFrame.Angles(0, 0, 0.5), c.secondary)
		b:add("Block", V(0.2, 0.9, 0.2), CF(0.85, 1.0, -0.1) * CFrame.Angles(0, 0, -0.5), c.secondary)
		b:add("Block", V(0.4, 0.25, 0.5), CF(-0.35, 0.12, 0), c.secondary:Lerp(BLACK, 0.4))
		b:add("Block", V(0.4, 0.25, 0.5), CF(0.35, 0.12, 0), c.secondary:Lerp(BLACK, 0.4))
		eyes(b, 1.25, -0.72, 0.25, 0.2)
	else
		-- Sylvogarde: stump guardian, thick bramble arms, pink flower crown
		b:add("Cylinder", V(1.6, 1.6, 1.6), CF(0, 0.85, 0) * UP, c.primary)
		b:add("Cylinder", V(0.2, 1.75, 1.75), CF(0, 1.7, 0) * UP, c.primary:Lerp(WHITE, 0.25))
		for k = 0, 5 do
			local a = k / 6 * TWO_PI
			b:add("Ball", V(0.35, 0.35, 0.35), CF(math.cos(a) * 0.6, 1.9, math.sin(a) * 0.6), if k % 2 == 0 then c.accent else c.glow)
		end
		b:add("Block", V(0.35, 1.1, 0.35), CF(-1.05, 0.95, -0.2) * CFrame.Angles(0.3, 0, 0.35), c.secondary)
		b:add("Block", V(0.35, 1.1, 0.35), CF(1.05, 0.95, -0.2) * CFrame.Angles(0.3, 0, -0.35), c.secondary)
		b:add("Ball", V(0.5, 0.5, 0.5), CF(-1.25, 0.4, -0.45), c.secondary)
		b:add("Ball", V(0.5, 0.5, 0.5), CF(1.25, 0.4, -0.45), c.secondary)
		eyes(b, 1.15, -0.8, 0.3, 0.18)
	end
end

Builders.Maree = function(b, stage, c)
	if stage == 1 then
		-- Gouttelot: tadpole inside a water bubble
		local bubble = makeBuilder(b.s, b.body.height)
		b:add("Ball", V(1.6, 1.6, 1.6), CF(0, 1.0, 0), c.glow)
		local shell = b.body.parts[#b.body.parts]
		shell.Transparency = 0.6
		shell.Material = Enum.Material.Glass
		b:add("Ball", V(0.9, 0.8, 0.9), CF(0, 1.0, -0.1), c.primary)
		b:add("Wedge", V(0.12, 0.5, 0.9), CF(0, 1.0, 0.9), c.secondary)
		eyes(b, 1.15, -0.5, 0.2, 0.17)
		for _, p in bubble.body.parts do
			p:Destroy()
		end
	elseif stage == 2 then
		-- Ondelin: round amphibian with a wave crest and fin hands
		b:add("Ball", V(1.6, 1.4, 1.5), CF(0, 0.9, 0), c.primary)
		b:add("Ball", V(1.1, 0.7, 0.9), CF(0, 0.7, -0.35), c.glow)
		for k, z in { -0.4, 0.0, 0.4 } do
			b:add("Wedge", V(0.15, 0.45 + k * 0.1, 0.4), CF(0, 1.7, z), c.accent)
		end
		b:add("Wedge", V(0.12, 0.5, 0.6), CF(-0.85, 0.8, 0) * CFrame.Angles(0, 0, 0.6), c.secondary)
		b:add("Wedge", V(0.12, 0.5, 0.6), CF(0.85, 0.8, 0) * CFrame.Angles(0, 0, -0.6), c.secondary)
		eyes(b, 1.25, -0.68, 0.3, 0.22)
	else
		-- Abyssale: floating ray, wide wings, small turquoise lantern
		b:add("Ball", V(1.6, 0.6, 2.0), CF(0, 1.0, 0), c.secondary)
		b:add("Wedge", V(0.2, 1.6, 1.4), CF(-1.3, 1.0, 0.1) * CFrame.Angles(0, 0, math.pi / 2), c.secondary)
		b:add("Wedge", V(0.2, 1.6, 1.4), CF(1.3, 1.0, 0.1) * CFrame.Angles(0, 0, -math.pi / 2), c.secondary)
		b:add("Ball", V(1.2, 0.3, 1.5), CF(0, 0.8, 0), c.primary)
		b:add("Block", V(0.1, 0.1, 1.6), CF(0, 1.0, 1.7), c.secondary)
		b:add("Block", V(0.08, 0.6, 0.08), CF(0, 1.55, -0.6), c.secondary)
		b:add("Ball", V(0.3, 0.3, 0.3), CF(0, 1.9, -0.7), c.accent, true)
		eyes(b, 1.15, -0.95, 0.3, 0.16)
	end
end

Builders.Volt = function(b, stage, c)
	if stage == 1 then
		-- Grésillon: battery-mouse, teal cylinder body with copper bands, terminal on the head
		b:add("Cylinder", V(1.3, 1.0, 1.0), CF(0, 0.65, 0) * CFrame.Angles(0, math.pi / 2, 0), c.primary)
		b:add("Cylinder", V(0.15, 1.05, 1.05), CF(0, 0.65, -0.4) * CFrame.Angles(0, math.pi / 2, 0), c.secondary)
		b:add("Cylinder", V(0.15, 1.05, 1.05), CF(0, 0.65, 0.4) * CFrame.Angles(0, math.pi / 2, 0), c.secondary)
		b:add("Ball", V(0.9, 0.85, 0.9), CF(0, 1.3, -0.5), c.primary)
		b:add("Block", V(0.25, 0.3, 0.25), CF(0, 1.8, -0.5), c.secondary)
		b:add("Ball", V(0.4, 0.4, 0.15), CF(-0.35, 1.7, -0.4), c.primary)
		b:add("Ball", V(0.4, 0.4, 0.15), CF(0.35, 1.7, -0.4), c.primary)
		b:add("Block", V(0.1, 0.1, 1.0), CF(0, 0.5, 1.1) * CFrame.Angles(0.5, 0, 0), c.secondary)
		eyes(b, 1.35, -0.92, 0.2, 0.17)
	elseif stage == 2 then
		-- Ampérat: longer rat, copper coil tail, capacitor ears
		b:add("Ball", V(1.2, 1.1, 2.0), CF(0, 0.8, 0), c.primary)
		b:add("Ball", V(1.0, 0.9, 1.0), CF(0, 1.3, -1.0), c.primary)
		b:add("Cylinder", V(0.4, 0.3, 0.3), CF(-0.35, 1.95, -0.9) * UP, c.secondary)
		b:add("Cylinder", V(0.4, 0.3, 0.3), CF(0.35, 1.95, -0.9) * UP, c.secondary)
		for k = 0, 3 do
			b:add("Cylinder", V(0.12, 0.45, 0.45), CF(0, 0.7 + k * 0.12, 1.1 + k * 0.25) * CFrame.Angles(0, math.pi / 2, 0), c.secondary)
		end
		b:add("Ball", V(0.25, 0.25, 0.25), CF(0, 1.25, 2.1), c.glow, true)
		eyes(b, 1.4, -1.45, 0.22, 0.17)
	else
		-- Fulgurex: long ferret on four legs, two lightning-rod antennae, glowing back arcs
		b:add("Ball", V(1.2, 1.0, 2.8), CF(0, 1.0, 0), c.primary)
		b:add("Ball", V(1.0, 0.9, 1.1), CF(0, 1.4, -1.6), c.primary)
		b:add("Block", V(0.1, 0.9, 0.1), CF(-0.25, 2.2, -1.5) * CFrame.Angles(0, 0, 0.2), c.secondary)
		b:add("Block", V(0.1, 0.9, 0.1), CF(0.25, 2.2, -1.5) * CFrame.Angles(0, 0, -0.2), c.secondary)
		b:add("Ball", V(0.2, 0.2, 0.2), CF(-0.35, 2.65, -1.5), c.glow, true)
		b:add("Ball", V(0.2, 0.2, 0.2), CF(0.35, 2.65, -1.5), c.glow, true)
		for _, z in { -0.6, 0.1, 0.8 } do
			b:add("Block", V(0.7, 0.08, 0.12), CF(0, 1.55, z) * CFrame.Angles(0, 0, 0.0), c.glow, true)
		end
		for _, sx in { -0.4, 0.4 } do
			for _, sz in { -0.9, 0.9 } do
				b:add("Block", V(0.25, 0.6, 0.25), CF(sx, 0.3, sz), c.secondary)
			end
		end
		b:add("Block", V(0.25, 0.25, 1.4), CF(0, 1.1, 2.0) * CFrame.Angles(-0.3, 0, 0), c.primary)
		eyes(b, 1.5, -2.1, 0.22, 0.16)
	end
end

Builders.Givre = function(b, stage, c)
	if stage == 1 then
		-- Flocon: snowball with penguin feet, orange beak, blue scarf
		b:add("Ball", V(1.5, 1.5, 1.5), CF(0, 0.9, 0), c.primary)
		b:add("Cylinder", V(0.25, 1.2, 1.2), CF(0, 1.25, 0) * UP, c.glow)
		b:add("Wedge", V(0.25, 0.2, 0.35), CF(0, 1.0, -0.8) * CFrame.Angles(math.pi, 0, 0), c.accent)
		b:add("Block", V(0.35, 0.1, 0.5), CF(-0.3, 0.05, -0.2), c.accent)
		b:add("Block", V(0.35, 0.1, 0.5), CF(0.3, 0.05, -0.2), c.accent)
		eyes(b, 1.2, -0.68, 0.25, 0.18)
	elseif stage == 2 then
		-- Stalagmo: stocky penguin with icicles on its back
		b:add("Ball", V(1.5, 2.0, 1.4), CF(0, 1.1, 0), c.secondary)
		b:add("Ball", V(1.1, 1.5, 0.8), CF(0, 1.0, -0.35), c.primary)
		b:add("Wedge", V(0.25, 0.2, 0.4), CF(0, 1.6, -0.8) * CFrame.Angles(math.pi, 0, 0), c.accent)
		for k, x in { -0.4, 0, 0.4 } do
			b:add("Wedge", V(0.2, 0.6 + (if k == 2 then 0.3 else 0), 0.3), CF(x, 2.1, 0.45), c.glow)
		end
		b:add("Block", V(0.2, 0.8, 0.4), CF(-0.8, 1.1, 0) * CFrame.Angles(0, 0, 0.3), c.secondary)
		b:add("Block", V(0.2, 0.8, 0.4), CF(0.8, 1.1, 0) * CFrame.Angles(0, 0, -0.3), c.secondary)
		b:add("Block", V(0.4, 0.1, 0.55), CF(-0.3, 0.05, -0.25), c.accent)
		b:add("Block", V(0.4, 0.1, 0.55), CF(0.3, 0.05, -0.25), c.accent)
		eyes(b, 1.8, -0.62, 0.25, 0.17)
	else
		-- Glaciarque: big penguin knight, ice crown and pauldrons
		b:add("Ball", V(1.9, 2.1, 1.7), CF(0, 1.1, 0), c.secondary)
		b:add("Ball", V(1.4, 1.6, 0.9), CF(0, 1.0, -0.45), c.primary)
		b:add("Wedge", V(0.3, 0.25, 0.45), CF(0, 1.6, -0.95) * CFrame.Angles(math.pi, 0, 0), c.accent)
		for k = 0, 4 do
			local x = (k - 2) * 0.25
			b:add("Wedge", V(0.18, if k == 2 then 0.6 else 0.4, 0.2), CF(x, 2.35, 0), c.glow, true)
		end
		b:add("Ball", V(0.8, 0.6, 0.8), CF(-0.95, 1.6, 0), c.glow)
		b:add("Ball", V(0.8, 0.6, 0.8), CF(0.95, 1.6, 0), c.glow)
		b:add("Block", V(0.45, 0.12, 0.6), CF(-0.35, 0.06, -0.3), c.accent)
		b:add("Block", V(0.45, 0.12, 0.6), CF(0.35, 0.06, -0.3), c.accent)
		eyes(b, 1.85, -0.72, 0.28, 0.17)
	end
end

Builders.Echo = function(b, stage, c)
	if stage == 1 then
		-- Pipistrou: round bat, speaker-cone belly, big ears
		b:add("Ball", V(1.3, 1.3, 1.2), CF(0, 1.0, 0), c.primary)
		b:add("Cylinder", V(0.15, 0.8, 0.8), CF(0, 0.9, -0.55) * CFrame.Angles(0, math.pi / 2, 0), c.secondary)
		b:add("Cylinder", V(0.16, 0.35, 0.35), CF(0, 0.9, -0.58) * CFrame.Angles(0, math.pi / 2, 0), c.accent, true)
		b:add("Wedge", V(0.15, 0.7, 0.4), CF(-0.35, 1.85, 0), c.primary)
		b:add("Wedge", V(0.15, 0.7, 0.4), CF(0.35, 1.85, 0), c.primary)
		b:add("Wedge", V(0.1, 0.7, 0.8), CF(-0.9, 1.1, 0.1) * CFrame.Angles(0, 0, 1.2), c.secondary)
		b:add("Wedge", V(0.1, 0.7, 0.8), CF(0.9, 1.1, 0.1) * CFrame.Angles(0, 0, -1.2), c.secondary)
		eyes(b, 1.35, -0.52, 0.22, 0.18)
	elseif stage == 2 then
		-- Résonar: bat with horn-shaped wings, two speakers
		b:add("Ball", V(1.4, 1.6, 1.3), CF(0, 1.1, 0), c.primary)
		for _, sx in { -0.3, 0.3 } do
			b:add("Cylinder", V(0.15, 0.5, 0.5), CF(sx, 0.9, -0.6) * CFrame.Angles(0, math.pi / 2, 0), c.secondary)
			b:add("Cylinder", V(0.16, 0.2, 0.2), CF(sx, 0.9, -0.63) * CFrame.Angles(0, math.pi / 2, 0), c.accent, true)
		end
		b:add("Wedge", V(0.15, 0.8, 0.45), CF(-0.4, 2.1, 0), c.primary)
		b:add("Wedge", V(0.15, 0.8, 0.45), CF(0.4, 2.1, 0), c.primary)
		b:add("Cylinder", V(1.2, 0.5, 0.9), CF(-1.2, 1.3, 0.1) * CFrame.Angles(0, 0, 0.4), c.secondary)
		b:add("Cylinder", V(1.2, 0.5, 0.9), CF(1.2, 1.3, 0.1) * CFrame.Angles(0, 0, -0.4), c.secondary)
		eyes(b, 1.55, -0.6, 0.25, 0.18)
	else
		-- Tonnerlune: big bat, crescent moon on the forehead, bass-box wings
		b:add("Ball", V(1.7, 1.9, 1.5), CF(0, 1.2, 0), c.primary)
		b:add("Cylinder", V(0.2, 0.9, 0.9), CF(0, 0.95, -0.7) * CFrame.Angles(0, math.pi / 2, 0), c.secondary)
		b:add("Cylinder", V(0.21, 0.4, 0.4), CF(0, 0.95, -0.73) * CFrame.Angles(0, math.pi / 2, 0), c.glow, true)
		b:add("Ball", V(0.6, 0.6, 0.2), CF(0, 2.2, -0.6), c.accent, true)
		b:add("Ball", V(0.5, 0.5, 0.22), CF(0.15, 2.3, -0.62), c.primary)
		b:add("Wedge", V(0.15, 0.9, 0.5), CF(-0.5, 2.4, 0.1), c.primary)
		b:add("Wedge", V(0.15, 0.9, 0.5), CF(0.5, 2.4, 0.1), c.primary)
		b:add("Block", V(1.4, 1.0, 0.25), CF(-1.4, 1.3, 0.2) * CFrame.Angles(0, 0.3, 0.3), c.secondary)
		b:add("Block", V(1.4, 1.0, 0.25), CF(1.4, 1.3, 0.2) * CFrame.Angles(0, -0.3, -0.3), c.secondary)
		b:add("Cylinder", V(0.26, 0.6, 0.6), CF(-1.4, 1.3, 0.05) * CFrame.Angles(0, 0.3 + math.pi / 2, 0), c.glow, true)
		b:add("Cylinder", V(0.26, 0.6, 0.6), CF(1.4, 1.3, 0.05) * CFrame.Angles(0, -0.3 + math.pi / 2, 0), c.glow, true)
		eyes(b, 1.7, -0.68, 0.3, 0.18)
	end
end

local function buildBody(line: LineDef, stage: number): Body
	local def = line.stages[stage]
	local s = def.height / 2
	local b = makeBuilder(s, def.height)
	local build = Builders[line.id]
	if build then
		build(b, stage, line.colors :: any)
	else
		b:add("Ball", V(1.4, 1.4, 1.4), CF(0, 0.8, 0), line.colors.primary)
	end
	return b.body
end

local function destroyBody(body: Body)
	for _, p in body.parts do
		p:Destroy()
	end
end

local function makeStars(): { BasePart }
	local list = {}
	for _ = 1, 3 do
		local p = newPart("Ball")
		p.Size = V(0.3, 0.3, 0.3)
		p.Color = Color3.fromRGB(255, 225, 80)
		p.Material = Enum.Material.Neon
		p.Parent = container
		table.insert(list, p)
	end
	return list
end

-- Effects (bounded pool) -----------------------------------------------------------------------------

local function acquireFx(shape: "Ball" | "Ring"): Fx?
	for _, fx in fxList do
		if not fx.active and fx.shape == shape then
			return fx
		end
	end
	if #fxList >= MAX_FX then
		return nil -- budget reached: skip the decoration (gameplay is server-side)
	end
	local part = newPart(if shape == "Ball" then "Ball" else "Cylinder")
	part.Material = Enum.Material.Neon
	part.Parent = container
	local fx: Fx = {
		part = part,
		shape = shape,
		active = false,
		t0 = 0,
		dur = 0,
		fromPos = Vector3.zero,
		toPos = Vector3.zero,
		fromSize = Vector3.one,
		toSize = Vector3.one,
		fromAlpha = 0,
		toAlpha = 1,
	}
	table.insert(fxList, fx)
	return fx
end

local function playFx(shape: "Ball" | "Ring", color: Color3, dur: number, fromPos: Vector3, toPos: Vector3, fromSize: Vector3, toSize: Vector3, fromAlpha: number, toAlpha: number)
	local fx = acquireFx(shape)
	if not fx then
		return
	end
	fx.active = true
	fx.t0 = os.clock()
	fx.dur = dur
	fx.fromPos, fx.toPos = fromPos, toPos
	fx.fromSize, fx.toSize = fromSize, toSize
	fx.fromAlpha, fx.toAlpha = fromAlpha, toAlpha
	fx.part.Color = color
	fx.part.Size = fromSize
	fx.part.Transparency = fromAlpha
end

-- Flat expanding ring on the ground (cylinder lying on its side).
local function ring(color: Color3, pos: Vector3, radius: number, dur: number)
	local d = math.max(radius * 2, 1)
	playFx("Ring", color, dur, pos, pos, V(0.2, 1, 1), V(0.2, d, d), 0.3, 1)
end

local function bolt(color: Color3, fromPos: Vector3, toPos: Vector3, size: number)
	playFx("Ball", color, 0.18, fromPos, toPos, V(size, size, size), V(size, size, size), 0, 0.2)
end

local function flash(color: Color3, pos: Vector3, fromD: number, toD: number, dur: number)
	playFx("Ball", color, dur, pos, pos, V(fromD, fromD, fromD), V(toD, toD, toD), 0.1, 1)
end

local function groundAt(e: Entry, x: number, z: number): Vector3
	return V(x, e.drawPos.Y + 0.2, z)
end

local function onEvent(e: Entry, evKind: number, evX: number, evZ: number, evRadius: number)
	local colors = e.line.colors
	local mouth = e.drawPos + V(0, e.body.height * 0.6, 0)
	local target = groundAt(e, evX, evZ)
	if evKind == NET.EvBasic then
		bolt(colors.glow, mouth, target + V(0, 1, 0), 0.5 + e.stage * 0.15)
		if evRadius > 0 then
			ring(colors.glow, target, evRadius, 0.3)
		end
	elseif evKind >= NET.EvTech1 and evKind < NET.EvUltimate then
		local techId = e.line.techs[evKind - NET.EvTech1 + 1]
		local def = techId and Companions.Techs[techId]
		local shape = if def then def.shape else "Target"
		if shape == "Target" or shape == "Chain" then
			bolt(colors.accent, mouth, target + V(0, 1, 0), 0.9)
			ring(colors.accent, target, math.max(evRadius, 2), 0.35)
		else
			ring(colors.accent, target, evRadius, 0.45)
		end
	elseif evKind == NET.EvHeal then
		ring(Color3.fromRGB(120, 255, 150), target, evRadius, 0.6)
	elseif evKind == NET.EvUltimate then
		if evRadius <= 4 then
			-- single ultimate strike (Volt)
			playFx("Ball", colors.glow, 0.25, target + V(0, 12, 0), target, V(0.6, 0.6, 0.6), V(1.2, 1.2, 1.2), 0, 0.3)
			ring(colors.glow, target, 3, 0.3)
		else
			flash(colors.glow, mouth, 1, e.body.height * 3, 0.5)
			ring(colors.glow, target, evRadius, 0.8)
			ring(colors.accent, target, evRadius * 0.6, 0.6)
		end
	end
end

local function onEvolve(e: Entry)
	local center = e.drawPos + V(0, e.body.height / 2, 0)
	flash(Color3.new(1, 1, 1), center, e.body.height, e.body.height * 2.5, 0.5)
	ring(e.line.colors.glow, groundAt(e, e.drawPos.X, e.drawPos.Z), 8, 0.7)
	e.phase = os.clock() -- restart the bob; the scale pop below reads it
end

-- Snapshot ------------------------------------------------------------------------------------------

local function lineFromIndex(index: number): LineDef?
	local id = Companions.LineOrder[index]
	return if id then Companions.Lines[id] else nil
end

local function onSnapshot(payload: unknown)
	if typeof(payload) ~= "buffer" then
		return
	end
	local len = buffer.len(payload)
	if len < NET.HeaderBytes then
		return
	end
	local count = buffer.readu8(payload, 4)
	if len ~= NET.HeaderBytes + count * NET.RecordBytes then
		return -- malformed
	end
	local tick = buffer.readu32(payload, 0)
	if tick < latestTick then
		return -- older than what we already drew
	end
	latestTick = tick
	local now = os.clock()
	local scale = NET.PositionScale
	local o = NET.HeaderBytes
	for _ = 1, count do
		local userId = buffer.readf64(payload, o)
		local x = buffer.readi16(payload, o + 8) / scale
		local y = buffer.readi16(payload, o + 10) / scale
		local z = buffer.readi16(payload, o + 12) / scale
		local yaw = buffer.readu8(payload, o + 14) / 256 * TWO_PI
		local flags = buffer.readu8(payload, o + 15)
		local evSeq = buffer.readu8(payload, o + 16)
		local evKind = buffer.readu8(payload, o + 17)
		local evX = buffer.readi16(payload, o + 18) / scale
		local evZ = buffer.readi16(payload, o + 20) / scale
		local evRadius = buffer.readu8(payload, o + 22)
		o += NET.RecordBytes

		local line = lineFromIndex(bit32.band(flags, 7))
		local stage = math.clamp(bit32.band(bit32.rshift(flags, NET.StageShift), 3), 1, 3)
		if not line then
			continue
		end
		local pos = V(x, y, z)
		local e = entries[userId]
		if e and e.line ~= line then
			destroyBody(e.body)
			for _, s in e.stars do
				s:Destroy()
			end
			entries[userId] = nil
			e = nil
		end
		if not e then
			e = {
				userId = userId,
				line = line,
				stage = stage,
				body = buildBody(line, stage),
				stars = makeStars(),
				fromPos = pos,
				toPos = pos,
				fromYaw = yaw,
				toYaw = yaw,
				t0 = now,
				span = SAMPLE_DT,
				lastTick = tick,
				lastSeen = now,
				evSeq = evSeq, -- do not replay the last event on first sight
				stunned = false,
				ultimate = false,
				ultFxAcc = 0,
				drawPos = pos,
				phase = 0,
			}
			entries[userId] = e
		else
			local entry = e :: Entry
			if tick > entry.lastTick then
				entry.fromPos = entry.drawPos
				local a = math.clamp((now - entry.t0) / entry.span, 0, 1)
				local dyaw = (entry.toYaw - entry.fromYaw + math.pi) % TWO_PI - math.pi
				entry.fromYaw = entry.fromYaw + dyaw * a
				entry.toPos = pos
				entry.toYaw = yaw
				entry.t0 = now
				entry.span = math.max(SAMPLE_DT, (tick - entry.lastTick) * SAMPLE_DT)
				entry.lastTick = tick
			end
			entry.lastSeen = now
			if stage ~= entry.stage then
				local grew = stage > entry.stage
				destroyBody(entry.body) -- evolution happens twice per run: rebuild is fine
				entry.body = buildBody(line, stage)
				entry.stage = stage
				if grew then
					onEvolve(entry)
				end
			end
			if evSeq ~= entry.evSeq then
				entry.evSeq = evSeq
				onEvent(entry, evKind, evX, evZ, evRadius)
			end
		end
		local entry = e :: Entry
		entry.stunned = bit32.band(flags, NET.StunnedBit) ~= 0
		entry.ultimate = bit32.band(flags, NET.UltimateBit) ~= 0
	end
end

-- Render --------------------------------------------------------------------------------------------

local function render(dt: number)
	local now = os.clock()
	local n = 0
	for userId, e in entries do
		if now - e.lastSeen > STALE_SECONDS then
			destroyBody(e.body)
			for _, s in e.stars do
				s:Destroy()
			end
			entries[userId] = nil
			continue
		end
		local a = math.clamp((now - e.t0) / e.span, 0, 1)
		local pos = e.fromPos:Lerp(e.toPos, a)
		e.drawPos = pos
		local dyaw = (e.toYaw - e.fromYaw + math.pi) % TWO_PI - math.pi
		local yaw = e.fromYaw + dyaw * a
		local moving = (e.toPos - e.fromPos).Magnitude > 0.2
		local s = e.body.height / 2
		local bob = 0
		local tilt = 0
		if e.stunned then
			tilt = math.sin(now * 6) * 0.15
		elseif e.line.flying then
			bob = math.sin(now * 3 + e.userId % 7) * 0.3 * s
		elseif moving then
			bob = math.abs(math.sin(now * 12)) * 0.35 * s -- little hops
		end
		-- Evolution pop: the new body rises out of the flash.
		local since = now - e.phase
		if since < 0.6 then
			bob += math.sin(since / 0.6 * math.pi) * 0.8 * s
		end
		local root = CFrame.new(pos.X, pos.Y + bob, pos.Z) * CFrame.Angles(0, yaw, tilt)
		for k, part in e.body.parts do
			n += 1
			moveParts[n] = part
			moveCFrames[n] = root * e.body.offsets[k]
		end
		for k, star in e.stars do
			n += 1
			moveParts[n] = star
			if e.stunned then
				local ang = now * 4 + k * TWO_PI / 3
				moveCFrames[n] = CFrame.new(pos.X + math.cos(ang) * 0.6 * s, pos.Y + e.body.height + 0.4, pos.Z + math.sin(ang) * 0.6 * s)
			else
				moveCFrames[n] = HIDDEN
			end
		end
		-- Ultimate ambience: periodic sparks within the ultimate radius.
		if e.ultimate then
			e.ultFxAcc += dt
			if e.ultFxAcc >= 0.25 then
				e.ultFxAcc = 0
				local r = e.line.ultimate.radius
				local ang = math.random() * TWO_PI
				local dist = math.random() * math.min(r, 25)
				local p = groundAt(e, pos.X + math.cos(ang) * dist, pos.Z + math.sin(ang) * dist)
				ring(e.line.colors.glow, p, 2.5, 0.4)
			end
		end
	end

	for _, fx in fxList do
		if not fx.active then
			continue
		end
		local t = (now - fx.t0) / fx.dur
		n += 1
		moveParts[n] = fx.part
		if t >= 1 then
			fx.active = false
			moveCFrames[n] = HIDDEN
			continue
		end
		local p = fx.fromPos:Lerp(fx.toPos, t)
		moveCFrames[n] = if fx.shape == "Ring" then CFrame.new(p) * CFrame.Angles(0, 0, math.pi / 2) else CFrame.new(p)
		if fx.fromSize ~= fx.toSize then
			fx.part.Size = fx.fromSize:Lerp(fx.toSize, t)
		end
		fx.part.Transparency = fx.fromAlpha + (fx.toAlpha - fx.fromAlpha) * t
	end

	for i = n + 1, #moveParts do
		moveParts[i] = nil :: any
		moveCFrames[i] = nil :: any
	end
	if n > 0 then
		Workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- State / ultimate ----------------------------------------------------------------------------------

local function onState(payload: unknown)
	if type(payload) ~= "table" then
		return
	end
	local p = payload :: any
	if type(p.line) ~= "string" or type(p.stage) ~= "number" or type(p.ultimateCharge) ~= "number" then
		return
	end
	state = p :: State
	for _, fn in table.clone(stateListeners) do
		task.spawn(fn, p :: State)
	end
end

-- Latest CompanionState of the local player (nil before the first run).
function CompanionRenderer.getState(): State?
	return state
end

-- Calls fn(state) on every CompanionState. Returns a disconnect function.
function CompanionRenderer.onStateChanged(fn: (State) -> ()): () -> ()
	table.insert(stateListeners, fn)
	return function()
		local i = table.find(stateListeners, fn)
		if i then
			table.remove(stateListeners, i)
		end
	end
end

-- True when the gauge is full and the companion is not stunned (HUD can glow the button).
function CompanionRenderer.isUltimateReady(): boolean
	local s = state
	return s ~= nil and not s.stunned and s.ultimateCharge >= Companions.Ultimate.Max
end

-- Asks the server to fire the ultimate. Used by the Ultimate input action and the UI button.
-- Returns true if a request was sent (the server still validates).
function CompanionRenderer.requestUltimate(): boolean
	local now = os.clock()
	if not CompanionRenderer.isUltimateReady() or now - lastRequest < 0.3 then
		return false
	end
	lastRequest = now
	Net.event("CompanionUltimate"):FireServer()
	return true
end

local function bindInput()
	local input = Registry.find("InputController")
	if input and type(input.onAction) == "function" then
		input.onAction("Ultimate", function(...)
			local first = ...
			if first == false or first == Enum.UserInputState.End then
				return -- release, not press
			end
			CompanionRenderer.requestUltimate()
		end)
		return
	end
	-- Fallback while the avatar domain's InputController is missing (dossier vision 10: E / Y).
	warn("[CompanionRenderer] InputController.onAction missing: using a temporary E / ButtonY binding")
	UserInputService.InputBegan:Connect(function(io, processed)
		if processed then
			return
		end
		if io.KeyCode == Enum.KeyCode.E or io.KeyCode == Enum.KeyCode.ButtonY then
			CompanionRenderer.requestUltimate()
		end
	end)
end

function CompanionRenderer.init()
	container = Instance.new("Folder")
	container.Name = "ClientCompanions"
	container.Parent = Workspace
end

function CompanionRenderer.start()
	Net.unreliable("CompanionSnapshot").OnClientEvent:Connect(onSnapshot)
	Net.event("CompanionState").OnClientEvent:Connect(onState)
	RunService.PreRender:Connect(render)
	bindInput()
	local _ = Players.LocalPlayer
end

return CompanionRenderer
