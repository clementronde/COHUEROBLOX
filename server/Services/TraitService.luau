--!strict
-- TraitService : l'équipement voxel de la classe (décisions v2 section 3) est un Accessory ajouté
-- à l'avatar du joueur, construit en blocs dans le code (aucun id d'asset), qui grandit aux niveaux
-- de run 10/20/30. Pièces provisoires en attendant les Accessories de A01 (vague 1, A04).
-- Ancien design (traits physiques v1) : docs/dossier/50-classes-avatar-mouvement.md section 3.
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
local rad = math.rad

-- ---------------------------------------------------------------- builders (stage 1 sizes, scale 1)

local Builders: { [string]: (BuildCtx) -> { Piece } } = {}

-- Équipement provisoire des 8 classes v2, en blocs (style voxel), en attendant les Accessories de
-- A01. Repère : celui de l'attachement R15 ; l'avant du personnage est -Z, le haut +Y.
-- Paliers : 1 = niveau 1, 2 = niveau 10, 3 = niveau 20, 4 = niveau 30 (Movement.Trait.StageLevels).
local SMOOTH = Enum.Material.SmoothPlastic
local METAL = Enum.Material.Metal
local NEON = Enum.Material.Neon
local RED = Color3.fromRGB(200, 45, 50)
local BROWN = Color3.fromRGB(120, 80, 45)

local function block(size: Vector3, pos: Vector3, color: Color3, material: Enum.Material?, effect: string?): Piece
	return piece(BLOCK, size, CFrame.new(pos), color, material or SMOOTH, effect)
end

-- Knight : casque ouvert (le visage reste visible), crête dorée au palier 3, armure brillante au 4.
function Builders.KnightHelm(ctx: BuildCtx): { Piece }
	local steel = if ctx.stage >= 4 then GOLD else ctx.tint
	local mat = if ctx.stage >= 4 then METAL else SMOOTH
	local out = {
		block(Vector3.new(1.35, 0.45, 1.35), Vector3.new(0, 0.05, 0), steel, mat),
		block(Vector3.new(0.16, 0.75, 1.1), Vector3.new(-0.68, -0.4, 0.05), steel, mat),
		block(Vector3.new(0.16, 0.75, 1.1), Vector3.new(0.68, -0.4, 0.05), steel, mat),
		block(Vector3.new(1.35, 0.75, 0.16), Vector3.new(0, -0.4, 0.62), steel, mat),
		block(Vector3.new(0.18, 0.5, 0.12), Vector3.new(0, -0.3, -0.7), steel, mat),
	}
	if ctx.stage >= 3 then
		local plume = if ctx.stage >= 4 then RED else GOLD
		for i = 0, 2 do
			table.insert(out, block(Vector3.new(0.22, 0.3, 0.35), Vector3.new(0, 0.42 + i * 0.12, -0.25 + i * 0.3), plume, SMOOTH, if ctx.stage >= 4 and i == 2 then "Sparkles" else nil))
		end
	end
	return out
end

function Builders.KnightCape(ctx: BuildCtx): { Piece }
	local long = if ctx.stage >= 4 then 0.5 else 0
	local out = {
		block(Vector3.new(1.7, 2.3 + long, 0.12), Vector3.new(0, -0.95 - long / 2, 0.25), RED),
		block(Vector3.new(1.9, 0.25, 0.25), Vector3.new(0, 0.2, 0.15), RED),
	}
	if ctx.stage >= 3 then
		table.insert(out, block(Vector3.new(1.72, 0.12, 0.14), Vector3.new(0, -2.05 - long, 0.25), GOLD, METAL))
	end
	return out
end

-- Archer : capuche et carquois ; plume au palier 2, carquois plein au 3, flèches dorées au 4.
function Builders.ArcherHood(ctx: BuildCtx): { Piece }
	local out = {
		block(Vector3.new(1.35, 0.45, 1.35), Vector3.new(0, 0.02, 0.02), ctx.tint),
		block(Vector3.new(1.35, 0.85, 0.2), Vector3.new(0, -0.42, 0.62), ctx.tint),
		block(Vector3.new(0.2, 0.8, 0.9), Vector3.new(-0.62, -0.42, 0.15), ctx.tint),
		block(Vector3.new(0.2, 0.8, 0.9), Vector3.new(0.62, -0.42, 0.15), ctx.tint),
		block(Vector3.new(0.5, 0.35, 0.5), Vector3.new(0, 0.1, 0.75), ctx.tint),
	}
	if ctx.stage >= 2 then
		table.insert(out, piece(BLOCK, Vector3.new(0.1, 0.9, 0.25), CFrame.new(0.72, 0.35, 0.2) * CFrame.Angles(0, 0, rad(-25)), RED, SMOOTH))
	end
	return out
end

function Builders.ArcherQuiver(ctx: BuildCtx): { Piece }
	local tilt = CFrame.Angles(0, 0, rad(20))
	local base = CFrame.new(0.15, -0.45, 0.45) * tilt
	local out = {
		piece(BLOCK, Vector3.new(0.55, 1.6, 0.55), base, BROWN, SMOOTH),
		piece(BLOCK, Vector3.new(0.6, 0.12, 0.6), base * CFrame.new(0, 0.55, 0), Color3.fromRGB(90, 60, 35), SMOOTH),
	}
	local arrows = if ctx.stage >= 3 then 5 else 3
	local tip = if ctx.stage >= 4 then GOLD else WHITE
	for i = 1, arrows do
		local ox = (i - (arrows + 1) / 2) * 0.12
		table.insert(out, piece(BLOCK, Vector3.new(0.06, 0.7, 0.06), base * CFrame.new(ox, 1.05, 0), Color3.fromRGB(200, 170, 120), SMOOTH))
		table.insert(out, piece(BLOCK, Vector3.new(0.14, 0.2, 0.04), base * CFrame.new(ox, 1.4, 0), tip, if ctx.stage >= 4 then NEON else SMOOTH))
	end
	return out
end

-- Mage : chapeau pointu en blocs empilés, étoile au palier 2, rune flottante au 3, lumineux au 4.
function Builders.MageHat(ctx: BuildCtx): { Piece }
	local band = if ctx.stage >= 4 then NEON else SMOOTH
	local out = {
		block(Vector3.new(2.0, 0.15, 2.0), Vector3.new(0, 0.05, 0), ctx.tint),
		block(Vector3.new(1.25, 0.5, 1.25), Vector3.new(0, 0.37, 0), ctx.tint),
		block(Vector3.new(1.28, 0.12, 1.28), Vector3.new(0, 0.18, 0), GOLD, band),
		block(Vector3.new(0.9, 0.5, 0.9), Vector3.new(0, 0.85, 0.05), ctx.tint),
		block(Vector3.new(0.6, 0.45, 0.6), Vector3.new(0, 1.3, 0.12), ctx.tint),
		block(Vector3.new(0.35, 0.4, 0.35), Vector3.new(0, 1.68, 0.25), ctx.tint, SMOOTH, if ctx.stage >= 4 then "Sparkles" else nil),
	}
	if ctx.stage >= 2 then
		table.insert(out, piece(BLOCK, Vector3.new(0.3, 0.3, 0.08), CFrame.new(0, 0.85, -0.5) * CFrame.Angles(0, 0, rad(45)), GOLD, NEON))
	end
	if ctx.stage >= 3 then
		table.insert(out, piece(BLOCK, Vector3.new(0.35, 0.35, 0.35), CFrame.new(0.9, 1.2, 0) * CFrame.Angles(rad(45), rad(45), 0), Color3.fromRGB(150, 220, 255), NEON, "Light"))
	end
	return out
end

-- Guardian : grosses épaulières de pierre ; rivets au palier 3, bords en fusion au 4.
function Builders.GuardianPauldron(ctx: BuildCtx): { Piece }
	local s = ctx.side
	local big = if ctx.stage >= 2 then 0.2 else 0
	local out = {
		block(Vector3.new(1.1 + big, 0.5, 1.25 + big), Vector3.new(s * 0.15, 0.2, 0), ctx.tint),
		block(Vector3.new(0.9 + big, 0.35, 1.05 + big), Vector3.new(s * 0.3, -0.15, 0), ctx.tint),
	}
	if ctx.stage >= 3 then
		for _, z in { -0.4, 0, 0.4 } do
			table.insert(out, piece(BALL, Vector3.one * 0.16, CFrame.new(s * 0.15, 0.48, z), DARK, METAL))
		end
	end
	if ctx.stage >= 4 then
		table.insert(out, block(Vector3.new(1.15 + big, 0.08, 1.3 + big), Vector3.new(s * 0.15, -0.02, 0), Color3.fromRGB(255, 120, 30), NEON, "Fire"))
	end
	return out
end

-- Rogue : masque de bandit ; capuche au palier 2, nœud au 3, traînée d'ombre au 4.
function Builders.RogueMask(ctx: BuildCtx): { Piece }
	local out = {
		block(Vector3.new(1.28, 0.28, 1.28), Vector3.new(0, -0.62, 0), ctx.tint),
	}
	if ctx.stage >= 2 then
		table.insert(out, block(Vector3.new(1.35, 0.4, 1.35), Vector3.new(0, 0.02, 0.02), DARK))
		table.insert(out, block(Vector3.new(1.35, 0.8, 0.2), Vector3.new(0, -0.4, 0.62), DARK))
	end
	if ctx.stage >= 3 then
		table.insert(out, piece(BLOCK, Vector3.new(0.12, 0.5, 0.12), CFrame.new(0.15, -0.8, 0.75) * CFrame.Angles(rad(30), 0, rad(20)), ctx.tint, SMOOTH))
		table.insert(out, piece(BLOCK, Vector3.new(0.12, 0.5, 0.12), CFrame.new(-0.15, -0.8, 0.75) * CFrame.Angles(rad(30), 0, rad(-20)), ctx.tint, SMOOTH))
	end
	if ctx.stage >= 4 then
		out[1] = block(Vector3.new(1.28, 0.28, 1.28), Vector3.new(0, -0.62, 0), ctx.tint, SMOOTH, "Smoke")
	end
	return out
end

-- Cleric : auréole carrée lumineuse ; plus brillante au palier 2, double au 3, rayonnante au 4.
function Builders.ClericHalo(ctx: BuildCtx): { Piece }
	local out = {}
	local function halo(y: number, w: number, effect: string?)
		local t = 0.14
		table.insert(out, block(Vector3.new(w, t, t), Vector3.new(0, y, -w / 2), ctx.tint, NEON, effect))
		table.insert(out, block(Vector3.new(w, t, t), Vector3.new(0, y, w / 2), ctx.tint, NEON))
		table.insert(out, block(Vector3.new(t, t, w), Vector3.new(-w / 2, y, 0), ctx.tint, NEON))
		table.insert(out, block(Vector3.new(t, t, w), Vector3.new(w / 2, y, 0), ctx.tint, NEON))
	end
	halo(0.55, 1.0, if ctx.stage >= 2 then "Light" else nil)
	if ctx.stage >= 3 then
		halo(0.85, 0.6, if ctx.stage >= 4 then "Sparkles" else nil)
	end
	return out
end

-- Barbarian : casque à cornes ; cornes plus longues au palier 2, bandeau de fourrure au 3, en flammes au 4.
function Builders.BarbarianHelm(ctx: BuildCtx): { Piece }
	local out = {
		block(Vector3.new(1.3, 0.42, 1.3), Vector3.new(0, 0.02, 0), ctx.tint, METAL),
	}
	local segments = if ctx.stage >= 2 then 4 else 3
	for _, side in { -1, 1 } do
		for i = 0, segments - 1 do
			local tip = i == segments - 1
			local size = 0.34 - i * 0.05
			table.insert(out, block(Vector3.one * size, Vector3.new(side * (0.75 + i * 0.22), 0.05 + i * 0.2, -0.05), WHITE, SMOOTH, if tip and ctx.stage >= 4 then "Fire" else nil))
		end
	end
	if ctx.stage >= 3 then
		table.insert(out, block(Vector3.new(1.4, 0.18, 1.4), Vector3.new(0, -0.2, 0), BROWN))
	end
	return out
end

-- Tamer : chapeau de dompteuse ; badge patte au palier 2, plume au 3, bande dorée au 4.
function Builders.TamerHat(ctx: BuildCtx): { Piece }
	local bandMat = if ctx.stage >= 4 then NEON else SMOOTH
	local out = {
		block(Vector3.new(1.7, 0.12, 1.7), Vector3.new(0, 0.05, 0), DARK),
		block(Vector3.new(1.0, 0.9, 1.0), Vector3.new(0, 0.55, 0), ctx.tint, SMOOTH, if ctx.stage >= 4 then "Sparkles" else nil),
		block(Vector3.new(1.04, 0.16, 1.04), Vector3.new(0, 0.2, 0), GOLD, bandMat),
	}
	if ctx.stage >= 2 then
		table.insert(out, block(Vector3.new(0.3, 0.26, 0.06), Vector3.new(0, 0.55, -0.52), GOLD))
		for i = -1, 1 do
			table.insert(out, block(Vector3.new(0.08, 0.08, 0.05), Vector3.new(i * 0.1, 0.74, -0.53), GOLD))
		end
	end
	if ctx.stage >= 3 then
		table.insert(out, piece(BLOCK, Vector3.new(0.08, 0.8, 0.22), CFrame.new(0.45, 0.95, 0.1) * CFrame.Angles(0, 0, rad(-20)), Color3.fromRGB(80, 170, 230), SMOOTH))
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
		warn(`[TraitService] classe inconnue {classId}`)
		return
	end
	classId = def.id -- id v1 (domaine data) -> id v2 canonique
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
