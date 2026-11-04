--!strict
-- TraitService (avatar domain): the class trait is an Accessory added to the player's own avatar,
-- built from parts in code (no asset ids), grown at run levels 10/20/30.
-- Design: docs/dossier/50-classes-avatar-mouvement.md section 3.
-- API (ARCHITECTURE section 4): applyClass(player, classId) · setTraitStage(player, stage) · clear(player)
-- Player attributes set here (server-owned): ClassId, TraitStage, KnockbackImmune.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Registry = require(Shared:WaitForChild("Registry"))
local Config = Shared:WaitForChild("Config")
local Classes = require(Config:WaitForChild("Classes"))
local Types = require(Shared:WaitForChild("Types"))
local Movement = require(Config:WaitForChild("Movement"))

local Bus = require(ServerScriptService:WaitForChild("Server"):WaitForChild("Bus"))

type Piece = {
	shape: Enum.PartType,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	transparency: number?,
	effect: string?, -- "Fire" | "Smoke" | "Sparkles" | "Light" | "Spores"
}

type BuildCtx = {
	stage: number,
	tint: Color3,
	side: number, -- -1 left, 1 right (shoulder builders), 1 otherwise
}

type State = {
	classId: string,
	stage: number,
	accessories: { Accessory },
	hidden: { [BasePart]: number },
	version: number,
}

local TraitService = {}

local TRAIT_ATTR = "CohueTrait"
local GOLD = Color3.fromRGB(240, 200, 80)
local DARK = Color3.fromRGB(40, 35, 35)
local WHITE = Color3.fromRGB(245, 245, 240)

local states: { [Player]: State } = {}

-- ---------------------------------------------------------------- geometry helpers

local function piece(
	shape: Enum.PartType,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	effect: string?
): Piece
	return { shape = shape, size = size, cf = cf, color = color, material = material, effect = effect }
end

local BALL = Enum.PartType.Ball
local BLOCK = Enum.PartType.Block
local CYL = Enum.PartType.Cylinder
local WEDGE = Enum.PartType.Wedge
local rad = math.rad

-- Cylinders run along X: this turns one upright.
local UPRIGHT = CFrame.Angles(0, 0, rad(90))

-- ---------------------------------------------------------------- builders (stage 1 sizes, scale 1)

local Builders: { [string]: (BuildCtx) -> { Piece } } = {}

function Builders.RamHorns(ctx: BuildCtx): { Piece }
	local out = {}
	local count = if ctx.stage >= 2 then 4 else 3
	for _, side in { -1, 1 } do
		for i = 0, count - 1 do
			local a = i * rad(70)
			local pos = Vector3.new(side * (0.5 + 0.45 * math.sin(a)), -0.1 + 0.45 * (math.cos(a) - 1) + 0.2, 0.05 + 0.12 * i)
			local d = 0.42 - 0.07 * i
			local tip = i == count - 1
			table.insert(
				out,
				piece(BALL, Vector3.one * d, CFrame.new(pos), ctx.tint, Enum.Material.SmoothPlastic, if tip and ctx.stage >= 4 then "Fire" else nil)
			)
			if ctx.stage >= 3 and i == 1 then
				table.insert(out, piece(CYL, Vector3.new(0.06, d + 0.04, d + 0.04), CFrame.new(pos), GOLD, Enum.Material.Neon))
			end
		end
	end
	return out
end

function Builders.FeatherWings(ctx: BuildCtx): { Piece }
	local out = {}
	local count = if ctx.stage >= 2 then 5 else 4
	local color = if ctx.stage >= 3 then GOLD else ctx.tint
	local material = if ctx.stage >= 4 then Enum.Material.Neon else Enum.Material.SmoothPlastic
	for _, side in { -1, 1 } do
		for i = 0, count - 1 do
			local pos = Vector3.new(side * (0.45 + i * 0.32), 0.35 - i * 0.1, 0.3)
			local size = Vector3.new(0.32, 1.5 - 0.15 * i, 0.08)
			local cf = CFrame.new(pos) * CFrame.Angles(0, 0, -side * rad(15 + i * 12))
			table.insert(out, piece(BLOCK, size, cf, color, material, if ctx.stage >= 4 and i == 0 then "Light" else nil))
		end
	end
	return out
end

function Builders.MechArm(ctx: BuildCtx): { Piece }
	local s = ctx.side
	local color = if ctx.stage >= 4 then GOLD else ctx.tint
	local metal = Enum.Material.Metal
	local out = {
		piece(BLOCK, Vector3.new(0.9, 0.35, 0.9), CFrame.new(s * 0.2, 0.1, 0.15), color, metal, if ctx.stage >= 4 then "Smoke" else nil),
		piece(CYL, Vector3.new(0.8, 0.32, 0.32), CFrame.new(s * 0.75, -0.35, 0.35) * UPRIGHT, color, metal),
		piece(BALL, Vector3.one * 0.38, CFrame.new(s * 0.75, -0.8, 0.35), DARK, metal),
		piece(CYL, Vector3.new(0.75, 0.28, 0.28), CFrame.new(s * 0.75, -1.2, 0.35) * UPRIGHT, color, metal),
		piece(WEDGE, Vector3.new(0.1, 0.35, 0.2), CFrame.new(s * 0.75, -1.7, 0.25), DARK, metal),
		piece(WEDGE, Vector3.new(0.1, 0.35, 0.2), CFrame.new(s * 0.75, -1.7, 0.45) * CFrame.Angles(0, rad(180), 0), DARK, metal),
	}
	if ctx.stage >= 2 then
		table.insert(out, piece(CYL, Vector3.new(0.7, 0.1, 0.1), CFrame.new(s * 0.95, -0.75, 0.5) * UPRIGHT, WHITE, metal))
		table.insert(out, piece(CYL, Vector3.new(0.7, 0.1, 0.1), CFrame.new(s * 0.55, -0.75, 0.5) * UPRIGHT, WHITE, metal))
	end
	if ctx.stage >= 3 then
		table.insert(out, piece(CYL, Vector3.new(1.0, 0.26, 0.26), CFrame.new(s * 0.6, 0.55, 0.6) * CFrame.Angles(0, 0, s * rad(35)), color, metal))
		table.insert(out, piece(BALL, Vector3.one * 0.3, CFrame.new(s * 1.0, 0.85, 0.6), DARK, metal))
	end
	return out
end

function Builders.CatEars(ctx: BuildCtx): { Piece }
	local out = {}
	for _, side in { -1, 1 } do
		local cf = CFrame.new(side * 0.38, 0.12, 0) * CFrame.Angles(0, rad(90), side * rad(-12))
		table.insert(out, piece(WEDGE, Vector3.new(0.12, 0.5, 0.35), cf, ctx.tint, Enum.Material.SmoothPlastic))
		if ctx.stage >= 2 then
			table.insert(out, piece(WEDGE, Vector3.new(0.13, 0.25, 0.18), cf * CFrame.new(0, -0.05, 0), DARK, Enum.Material.SmoothPlastic))
		end
	end
	return out
end

function Builders.CatTail(ctx: BuildCtx): { Piece }
	local out = {}
	local tails = if ctx.stage >= 3 then { -0.18, 0.18 } else { 0 }
	for _, x in tails do
		for i = 0, 3 do
			local pos = Vector3.new(x * (1 + i * 0.5), -0.1 + 0.08 * i * i, 0.3 + 0.28 * i)
			local stripe = ctx.stage >= 2 and i % 2 == 1
			table.insert(
				out,
				piece(BALL, Vector3.one * (0.3 - 0.03 * i), CFrame.new(pos), if stripe then DARK else ctx.tint, Enum.Material.SmoothPlastic, if ctx.stage >= 4 and i == 3 then "Sparkles" else nil)
			)
		end
	end
	return out
end

function Builders.StonePlate(ctx: BuildCtx): { Piece }
	local s = ctx.side
	local mat = if ctx.stage >= 4 then Enum.Material.CrackedLava else Enum.Material.Slate
	local base = CFrame.new(s * 0.15, 0.15, 0) * CFrame.Angles(0, 0, -s * rad(15))
	local out = {
		piece(BLOCK, Vector3.new(1.1, 0.4, 1.0), base, ctx.tint, mat, if ctx.stage >= 4 then "Light" else nil),
		piece(BLOCK, Vector3.new(0.7, 0.3, 0.8), base * CFrame.new(s * 0.3, -0.3, 0), ctx.tint, mat),
	}
	if ctx.stage >= 2 then
		table.insert(out, piece(BLOCK, Vector3.new(0.9, 0.1, 0.8), base * CFrame.new(0, 0.22, 0), Color3.fromRGB(90, 140, 60), Enum.Material.Grass))
	end
	if ctx.stage >= 3 then
		for i = -1, 1 do
			table.insert(out, piece(WEDGE, Vector3.new(0.15, 0.45, 0.25), base * CFrame.new(i * 0.3, 0.45, 0), Color3.fromRGB(150, 230, 255), Enum.Material.Neon))
		end
	end
	return out
end

function Builders.MushroomCap(ctx: BuildCtx): { Piece }
	local g = if ctx.stage >= 4 then 1.3 else 1
	local out = {
		piece(BALL, Vector3.new(1.6, 0.6, 1.6) * g, CFrame.new(0, 0.25 * g, 0), ctx.tint, Enum.Material.SmoothPlastic, if ctx.stage >= 3 then "Spores" else nil),
	}
	if ctx.stage >= 2 then
		local spotMat = if ctx.stage >= 4 then Enum.Material.Neon else Enum.Material.SmoothPlastic
		for i = 0, 4 do
			local a = i * rad(72)
			table.insert(out, piece(BALL, Vector3.one * 0.25 * g, CFrame.new(math.cos(a) * 0.5 * g, 0.42 * g, math.sin(a) * 0.5 * g), WHITE, spotMat, if ctx.stage >= 4 and i == 0 then "Light" else nil))
		end
	end
	return out
end

function Builders.SmallHorns(ctx: BuildCtx): { Piece }
	local out = {}
	for _, side in { -1, 1 } do
		table.insert(out, piece(BALL, Vector3.one * 0.26, CFrame.new(side * 0.35, 0.02, 0), ctx.tint, Enum.Material.Slate))
		table.insert(out, piece(BALL, Vector3.one * 0.18, CFrame.new(side * 0.42, 0.22, 0.08), ctx.tint, Enum.Material.Slate))
		table.insert(out, piece(BALL, Vector3.one * 0.1, CFrame.new(side * 0.46, 0.36, 0.14), WHITE, Enum.Material.SmoothPlastic))
	end
	return out
end

function Builders.ScalyTail(ctx: BuildCtx): { Piece }
	local out = {}
	local count = if ctx.stage >= 2 then 5 else 4
	for i = 0, count - 1 do
		local pos = Vector3.new(0, -0.35 - 0.12 * i, 0.3 + 0.3 * i)
		local size = Vector3.new(0.4 - 0.05 * i, 0.32 - 0.04 * i, 0.4)
		local cf = CFrame.new(pos) * CFrame.Angles(rad(-15), 0, 0)
		table.insert(out, piece(BLOCK, size, cf, ctx.tint, if ctx.stage >= 2 then Enum.Material.Slate else Enum.Material.SmoothPlastic))
		if ctx.stage >= 3 then
			table.insert(out, piece(WEDGE, Vector3.new(0.06, 0.22, 0.25), cf * CFrame.new(0, size.Y / 2 + 0.1, 0), GOLD, Enum.Material.SmoothPlastic))
		end
	end
	return out
end

function Builders.DragonWings(ctx: BuildCtx): { Piece }
	local out = {}
	for _, side in { -1, 1 } do
		local cf = CFrame.new(side * 0.9, 0.45, 0.3) * CFrame.Angles(0, 0, -side * rad(25))
		table.insert(out, piece(BLOCK, Vector3.new(1.3, 0.8, 0.06), cf, ctx.tint, Enum.Material.SmoothPlastic))
		table.insert(out, piece(CYL, Vector3.new(1.4, 0.1, 0.1), cf * CFrame.new(0, 0.4, 0), DARK, Enum.Material.SmoothPlastic))
	end
	return out
end

function Builders.StarCrown(ctx: BuildCtx): { Piece }
	local out = {}
	for _, side in { -1, 1 } do
		local cf = CFrame.new(side * 0.25, 0.35, 0) * CFrame.Angles(0, 0, -side * rad(15)) * UPRIGHT
		table.insert(out, piece(CYL, Vector3.new(0.8, 0.06, 0.06), cf, DARK, Enum.Material.SmoothPlastic))
		table.insert(out, piece(BALL, Vector3.one * 0.18, CFrame.new(side * 0.36, 0.75, 0), ctx.tint, Enum.Material.Neon))
	end
	local stars = ({ 1, 2, 4, 4 })[ctx.stage] or 1
	for i = 0, stars - 1 do
		local a = i * (2 * math.pi / stars) + rad(30)
		table.insert(out, piece(BALL, Vector3.one * 0.3, CFrame.new(math.cos(a), 0.1, math.sin(a)), ctx.tint, Enum.Material.Neon, if i == 0 and ctx.stage >= 3 then "Light" else nil))
	end
	if ctx.stage >= 4 then
		local ring = piece(CYL, Vector3.new(0.05, 2.4, 2.4), CFrame.new(0, 0.1, 0) * UPRIGHT, ctx.tint, Enum.Material.Neon)
		ring.transparency = 0.4
		table.insert(out, ring)
	end
	return out
end

function Builders.Crystals(ctx: BuildCtx): { Piece }
	local out = {}
	local s = ctx.side
	for i = 0, ctx.stage - 1 do
		local h = 0.9 + 0.15 * i
		local cf = CFrame.new(s * (0.1 + 0.18 * i), 0.3 + h / 2 - 0.2, -0.2 + 0.15 * i) * CFrame.Angles(rad(10 * i), 0, -s * rad(12 + 10 * i))
		table.insert(out, piece(BLOCK, Vector3.new(0.3, h, 0.3), cf, ctx.tint, Enum.Material.Glass, if ctx.stage >= 4 and i == 0 then "Light" else nil))
		table.insert(out, piece(WEDGE, Vector3.new(0.3, 0.3, 0.3), cf * CFrame.new(0, h / 2 + 0.15, 0), ctx.tint, Enum.Material.Neon))
	end
	return out
end

function Builders.Tentacles(ctx: BuildCtx): { Piece }
	local out = {}
	local count = ({ 4, 6, 6, 8 })[ctx.stage] or 4
	for k = 0, count - 1 do
		local a = k * (2 * math.pi / count) + math.pi / 4 -- star around the back
		local dir = Vector3.new(math.cos(a), math.sin(a), 1.2).Unit
		local root = Vector3.new(math.cos(a) * 0.35, math.sin(a) * 0.35, 0.15)
		for i = 0, 2 do
			local d = 0.38 - 0.09 * i
			local pos = root + dir * (0.35 + 0.42 * i)
			table.insert(out, piece(BALL, Vector3.one * d, CFrame.new(pos), ctx.tint, Enum.Material.SmoothPlastic))
			if ctx.stage >= 3 and i < 2 then
				table.insert(out, piece(BALL, Vector3.one * 0.1, CFrame.new(pos + Vector3.new(0, -d / 2, 0)), Color3.fromRGB(255, 180, 230), Enum.Material.Neon))
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------- accessory assembly

local function addEffect(part: BasePart, effect: string, s: number, color: Color3)
	if effect == "Fire" then
		local fire = Instance.new("Fire")
		fire.Size = 1.5 * s
		fire.Heat = 3
		fire.Parent = part
	elseif effect == "Smoke" then
		local smoke = Instance.new("Smoke")
		smoke.Size = 0.6 * s
		smoke.RiseVelocity = 2
		smoke.Opacity = 0.15
		smoke.Parent = part
	elseif effect == "Sparkles" then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = color
		sparkles.Parent = part
	elseif effect == "Light" then
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 8
		light.Brightness = 1
		light.Parent = part
	elseif effect == "Spores" then
		local emitter = Instance.new("ParticleEmitter") -- default engine texture, no asset id
		emitter.Rate = 3
		emitter.Lifetime = NumberRange.new(1.5, 2.5)
		emitter.Speed = NumberRange.new(0.3, 0.8)
		emitter.Size = NumberSequence.new(0.15 * s)
		emitter.Color = ColorSequence.new(color)
		emitter.LightEmission = 0.5
		emitter.Parent = part
	end
end

local function makePart(name: string, size: Vector3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function buildAccessory(classId: string, index: number, attachmentName: string, pieces: { Piece }, s: number): Accessory
	local accessory = Instance.new("Accessory")
	accessory.Name = `CohueTrait_{classId}_{index}`
	accessory:SetAttribute(TRAIT_ATTR, true)

	local handle = makePart("Handle", Vector3.one * 0.2)
	handle.Transparency = 1
	handle.Parent = accessory

	local attachment = Instance.new("Attachment")
	attachment.Name = attachmentName
	attachment.Parent = handle

	for i, spec in pieces do
		local p = makePart(`Piece{i}`, spec.size * s)
		p.Shape = spec.shape
		p.Color = spec.color
		p.Material = spec.material or Enum.Material.SmoothPlastic
		p.Transparency = spec.transparency or 0
		local offset = CFrame.new(spec.cf.Position * s) * spec.cf.Rotation
		p.CFrame = handle.CFrame * offset
		local weld = Instance.new("Weld")
		weld.Part0 = handle
		weld.Part1 = p
		weld.C0 = offset
		weld.Parent = p
		if spec.effect then
			addEffect(p, spec.effect, s, spec.color)
		end
		p.Parent = accessory
	end
	return accessory
end

-- ---------------------------------------------------------------- avatar reading

local function scaleValue(humanoid: Humanoid, name: string): number
	local v = humanoid:FindFirstChild(name)
	if v and v:IsA("NumberValue") and v.Value > 0 then
		return v.Value
	end
	return 1
end

local function avatarScale(humanoid: Humanoid, attachmentName: string): number
	local s
	if attachmentName == "HatAttachment" or attachmentName == "HairAttachment" then
		s = scaleValue(humanoid, "HeadScale")
	elseif string.find(attachmentName, "Shoulder") then
		s = scaleValue(humanoid, "BodyWidthScale")
	else
		s = (scaleValue(humanoid, "BodyHeightScale") + scaleValue(humanoid, "BodyWidthScale")) / 2
	end
	return math.clamp(s, Movement.Trait.AvatarScaleMin, Movement.Trait.AvatarScaleMax)
end

local function readProfile(player: Player): { [string]: any }?
	local DataService = Registry.find("DataService")
	if not DataService then
		return nil
	end
	local ok, profile = pcall(DataService.getProfile, player)
	if ok and type(profile) == "table" then
		return profile
	end
	return nil
end

local function readKeepHat(profile: { [string]: any }?): boolean
	local settings = profile and profile.settings
	return type(settings) == "table" and settings.keepHat == true
end

local function readTint(profile: { [string]: any }?, def: Types.ClassDef): Color3
	local tints = def.tints :: { Color3 }
	local index = 1
	local equipped = profile and profile.equipped
	if type(equipped) == "table" and type(equipped.TraitTint) == "number" then
		index = math.clamp(math.floor(equipped.TraitTint), 1, #tints)
	end
	return tints[index]
end

-- A body attachment (not inside an accessory) with this name exists on the character.
local function findBodyAttachment(character: Model, attachmentName: string): Attachment?
	for _, d in character:GetDescendants() do
		if d.Name == attachmentName and d:IsA("Attachment") and d.Parent and d.Parent:IsA("BasePart") then
			if not d:FindFirstAncestorOfClass("Accessory") then
				return d
			end
		end
	end
	return nil
end

local FALLBACK_PARTS: { [string]: { string } } = {
	HatAttachment = { "Head" },
	LeftShoulderAttachment = { "LeftUpperArm", "Left Arm", "UpperTorso", "Torso" },
	RightShoulderAttachment = { "RightUpperArm", "Right Arm", "UpperTorso", "Torso" },
	BodyBackAttachment = { "UpperTorso", "Torso" },
	WaistBackAttachment = { "LowerTorso", "Torso" },
}
local FALLBACK_OFFSETS: { [string]: CFrame } = {
	HatAttachment = CFrame.new(0, 0.6, 0),
	LeftShoulderAttachment = CFrame.new(0, 0.6, 0),
	RightShoulderAttachment = CFrame.new(0, 0.6, 0),
	BodyBackAttachment = CFrame.new(0, 0, 0.5),
	WaistBackAttachment = CFrame.new(0, -0.2, 0.5),
}

-- Non-R15 or custom rig: weld the handle by hand.
local function fallbackWeld(character: Model, accessory: Accessory, attachmentName: string)
	local handle = accessory:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		return
	end
	for _, partName in FALLBACK_PARTS[attachmentName] or { "Head" } do
		local part = character:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			local weld = Instance.new("Weld")
			weld.Name = "CohueTraitWeld"
			weld.Part0 = part
			weld.Part1 = handle
			weld.C0 = FALLBACK_OFFSETS[attachmentName] or CFrame.identity
			weld.Parent = handle
			return
		end
	end
end

-- ---------------------------------------------------------------- state

local function restoreHidden(state: State)
	for part, transparency in state.hidden do
		if part.Parent then
			part.Transparency = transparency
		end
	end
	table.clear(state.hidden)
end

local function removeTraits(state: State)
	for _, accessory in state.accessories do
		accessory:Destroy()
	end
	table.clear(state.accessories)
	restoreHidden(state)
end

local function hideConflicts(state: State, character: Model, attachmentName: string)
	for _, child in character:GetChildren() do
		if not child:IsA("Accessory") or child:GetAttribute(TRAIT_ATTR) then
			continue
		end
		local handle = child:FindFirstChild("Handle")
		if not handle or not handle:IsA("BasePart") or handle:FindFirstChildOfClass("WrapLayer") then
			continue -- layered clothing never conflicts
		end
		local att = handle:FindFirstChild(attachmentName)
		if not att or not att:IsA("Attachment") then
			continue
		end
		local parts: { BasePart } = { handle }
		for _, d in handle:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(parts, d)
			end
		end
		for _, part in parts do
			if state.hidden[part] == nil then
				state.hidden[part] = part.Transparency
				part.Transparency = 1
			end
		end
	end
end

local function waitForAppearance(player: Player, character: Model)
	if player:HasAppearanceLoaded() then
		return
	end
	local loaded = false
	local conn = player.CharacterAppearanceLoaded:Connect(function()
		loaded = true
	end)
	local deadline = os.clock() + Movement.Trait.AppearanceTimeout
	while not loaded and os.clock() < deadline and character.Parent ~= nil do
		task.wait(0.1)
	end
	conn:Disconnect()
end

local function applyBaseline(humanoid: Humanoid, def: Types.ClassDef)
	humanoid.UseJumpPower = false
	humanoid.WalkSpeed = def.walkSpeed
	humanoid.JumpHeight = def.jumpHeight
end

-- Yields (appearance). A newer rebuild for the same player cancels this one.
local function rebuild(player: Player)
	local state = states[player]
	if not state then
		return
	end
	state.version += 1
	local version = state.version
	local character = player.Character
	if not character then
		return -- CharacterAdded re-applies
	end
	waitForAppearance(player, character)
	state = states[player]
	if not state or state.version ~= version or player.Character ~= character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local def = Classes[state.classId]
	if not def then
		return
	end

	removeTraits(state)
	applyBaseline(humanoid, def)
	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		warn(`[TraitService] {player.Name} is not R15: set Avatar Settings to R15 only (welding traits by hand)`)
	end

	local profile = readProfile(player)
	local keepHat = readKeepHat(profile)
	local tint = readTint(profile, def)
	local stageScale = Movement.Trait.StageScale[state.stage] or 1

	for index, trait in def.traits :: { Classes.TraitPart } do
		if (trait.fromStage or 1) > state.stage then
			continue
		end
		local builder = Builders[trait.builder]
		if not builder then
			warn(`[TraitService] unknown builder {trait.builder}`)
			continue
		end
		local side = if string.find(trait.attachment, "Left") then -1 else 1
		local pieces = builder({ stage = state.stage, tint = tint, side = side })
		local s = stageScale * avatarScale(humanoid, trait.attachment)

		if not (keepHat and trait.attachment == "HatAttachment") then
			hideConflicts(state, character, trait.attachment)
		end

		local accessory = buildAccessory(state.classId, index, trait.attachment, pieces, s)
		local hasBodyAttachment = findBodyAttachment(character, trait.attachment) ~= nil
		local ok, err = pcall(humanoid.AddAccessory, humanoid, accessory)
		if not ok then
			warn(`[TraitService] AddAccessory failed for {player.Name}: {err}`)
			accessory.Parent = character
		end
		if not hasBodyAttachment then
			fallbackWeld(character, accessory, trait.attachment)
		end
		table.insert(state.accessories, accessory)
	end
end

local function stageForLevel(level: number): number
	local stage = 1
	for i, threshold in Movement.Trait.StageLevels do
		if level >= threshold then
			stage = i + 1
		end
	end
	return stage
end

-- ---------------------------------------------------------------- API (ARCHITECTURE section 4)

function TraitService.applyClass(player: Player, classId: string)
	local def = Classes[classId]
	if not def then
		warn(`[TraitService] unknown class {classId}`)
		return
	end
	local state = states[player]
	if state then
		removeTraits(state)
		state.classId = classId
		state.stage = 1
	else
		state = { classId = classId, stage = 1, accessories = {}, hidden = {}, version = 0 }
		states[player] = state
	end
	player:SetAttribute("ClassId", classId)
	player:SetAttribute("TraitStage", 1)
	player:SetAttribute("KnockbackImmune", def.knockbackImmune == true)
	task.spawn(rebuild, player)
end

function TraitService.setTraitStage(player: Player, stage: number)
	local state = states[player]
	if not state or type(stage) ~= "number" then
		return
	end
	local clamped = math.clamp(math.floor(stage), 1, 4)
	if clamped == state.stage then
		return
	end
	state.stage = clamped
	player:SetAttribute("TraitStage", clamped)
	task.spawn(rebuild, player)
end

function TraitService.clear(player: Player)
	local state = states[player]
	if state then
		state.version += 1 -- cancels pending rebuilds
		removeTraits(state)
		states[player] = nil
	end
	if player.Parent then
		player:SetAttribute("ClassId", nil)
		player:SetAttribute("TraitStage", nil)
		player:SetAttribute("KnockbackImmune", nil)
	end
end

-- ---------------------------------------------------------------- lifecycle

local function onCharacterAdded(player: Player, _character: Model)
	local state = states[player]
	if state then
		-- Old accessories died with the old character.
		table.clear(state.accessories)
		table.clear(state.hidden)
		task.spawn(rebuild, player)
	end
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
end

function TraitService.init()
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player)
		local state = states[player]
		if state then
			state.version += 1
		end
		states[player] = nil
	end)

	Bus.PlayerLeveledUp:connect(function(player: Player, level: number)
		local state = states[player]
		if not state or type(level) ~= "number" then
			return
		end
		local stage = stageForLevel(level)
		if stage > state.stage then
			TraitService.setTraitStage(player, stage)
		end
	end)

	Bus.RunEnded:connect(function(summaries: { [Player]: any }?)
		local cleared: { [Player]: boolean } = {}
		if type(summaries) == "table" then
			for player in summaries do
				if typeof(player) == "Instance" and player:IsA("Player") then
					TraitService.clear(player)
					cleared[player] = true
				end
			end
		end
		-- Also clear anyone still carrying a trait (run ended for the whole server).
		for player in table.clone(states) do
			if not cleared[player] then
				TraitService.clear(player)
			end
		end
	end)
end

function TraitService.start()
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
end

return TraitService
