--!strict
-- Shared UI tokens, builders, language, device profile and remote cache (ui domain).
-- Design: docs/dossier/60-ui-ux.md section 0 (v2 "Toy-block gloss", Figma 0Yq5m1skq5dzgOQXZ9bG6D)
-- and sections 1, 12, 13, 14. Every other UI module requires this one.
-- Code theme instead of engine StyleSheet: vault "UI Design Systems" section 4 (style editor beta).

local GuiService = game:GetService("GuiService")
local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ConfigFolder = Shared:WaitForChild("Config")
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Signal"))
local UIConfig = require(ConfigFolder:WaitForChild("UI"))

export type Lang = "fr" | "en"
export type Device = "phone" | "tablet" | "desktop"
export type Bar = { frame: Frame, fill: Frame, set: (frac: number) -> () }

local UITheme = {}

UITheme.Config = UIConfig
UITheme.S = UIConfig.Strings
-- reason: "lang" | "palette" | "text" | "device" | "motion" | "phase" | "profile"
UITheme.changed = Signal.new()

local settings = {
	colorblind = false,
	reduceFlashes = GuiService.ReducedMotionEnabled,
	textScale = 1,
	keepHat = true,
}
local langOverride: Lang? = nil
local autoLang: Lang = "en"
local device: Device = "phone"
local phase = "Loadout"
local profile: { [string]: any }? = nil

local weak = { __mode = "k" }
local texts: { [Instance]: { value: any, args: { [string]: any }? } } = setmetatable({}, weak) :: any
local textSizes: { [Instance]: number } = setmetatable({}, weak) :: any
local paints: { [Instance]: { [string]: string } } = setmetatable({}, weak) :: any
local backs: { [Instance]: number } = setmetatable({}, weak) :: any
local scales: { [UIScale]: boolean } = setmetatable({}, weak) :: any

-- v2 fonts: Luckiest Guy (numbers, banners), Fredoka One (labels, buttons), Nunito (body text).
local numberFont = Font.new(UIConfig.Fonts.Number, Enum.FontWeight.Regular, Enum.FontStyle.Normal)
local labelFont = Font.new(UIConfig.Fonts.Label, Enum.FontWeight.Regular, Enum.FontStyle.Normal)
local bodyFont = Font.new(UIConfig.Fonts.Body, Enum.FontWeight.Bold, Enum.FontStyle.Normal)
local bodyHeavyFont = Font.new(UIConfig.Fonts.Body, Enum.FontWeight.ExtraBold, Enum.FontStyle.Normal)
local flags: { [string]: any } = {}

---------------------------------------------------------------------------- language

local function detectLocale(id: string?): Lang
	if id and string.sub(string.lower(id), 1, 2) == "fr" then
		return "fr"
	end
	return "en"
end

autoLang = detectLocale(LocalizationService.RobloxLocaleId)

function UITheme.lang(): Lang
	return langOverride or (UIConfig.ForceLanguage :: any) or autoLang
end

function UITheme.langOverride(): Lang?
	return langOverride
end

function UITheme.format(value: any, args: { [string]: any }?): string
	local text: string
	if type(value) == "table" then
		local lang = UITheme.lang()
		text = value[lang] or value.en or value.fr or ""
	elseif value == nil then
		text = ""
	else
		text = tostring(value)
	end
	if args then
		text = string.gsub(text, "{(%w+)}", function(name: string)
			local v = args[name]
			return if v ~= nil then tostring(v) else "{" .. name .. "}"
		end)
	end
	return text
end

-- Assign text to a label and remember it so a language change rewrites it.
function UITheme.setText(label: TextLabel | TextButton, value: any, args: { [string]: any }?)
	texts[label] = { value = value, args = args }
	local text = UITheme.format(value, args)
	if label.Text ~= text then
		label.Text = text
	end
end

local function rewriteTexts()
	for label, entry in texts do
		local text = UITheme.format(entry.value, entry.args)
		local l = label :: TextLabel
		if l.Text ~= text then
			l.Text = text
		end
	end
end

function UITheme.setLanguage(lang: Lang?)
	langOverride = lang
	rewriteTexts()
	UITheme.changed:fire("lang")
end

---------------------------------------------------------------------------- settings / palette

function UITheme.settings()
	return settings
end

function UITheme.flashesReduced(): boolean
	return settings.reduceFlashes or GuiService.ReducedMotionEnabled
end

function UITheme.color(token: string): Color3
	if settings.colorblind then
		local c = (UIConfig.Palettes.Colorblind :: any)[token]
		if c then
			return c
		end
	end
	return (UIConfig.Palettes.Default :: any)[token] or Color3.new(1, 0, 1)
end

function UITheme.rarityColor(rarity: string?): Color3
	return UITheme.color(if rarity and (UIConfig.Rarity :: any)[rarity] then rarity else "Common")
end

-- Set a colour property from a token and keep it in sync with palette changes.
function UITheme.paint(obj: Instance, prop: string, token: string)
	local entry = paints[obj]
	if not entry then
		entry = {}
		paints[obj] = entry
	end
	entry[prop] = token;
	(obj :: any)[prop] = UITheme.color(token)
end

local function repaint()
	for obj, entry in paints do
		for prop, token in entry do
			(obj :: any)[prop] = UITheme.color(token)
		end
	end
end

-- Background transparency honouring GuiService.PreferredTransparency (vault: Accessibility).
function UITheme.back(obj: GuiObject, base: number)
	backs[obj] = base
	obj.BackgroundTransparency = base * GuiService.PreferredTransparency
end

local function reapplyBacks()
	for obj, base in backs do
		(obj :: GuiObject).BackgroundTransparency = base * GuiService.PreferredTransparency
	end
end

function UITheme.textSize(role: string): number
	local base = (UIConfig.TextSize :: any)[role] or UIConfig.TextSize.Body
	return math.round(base * settings.textScale)
end

local function reapplyTextSizes()
	for label, base in textSizes do
		(label :: TextLabel).TextSize = math.round(base * settings.textScale)
	end
end

function UITheme.applySettings(new: { [string]: any })
	local paletteChanged, textChanged, motionChanged = false, false, false
	if type(new.colorblind) == "boolean" and new.colorblind ~= settings.colorblind then
		settings.colorblind = new.colorblind
		paletteChanged = true
	end
	if type(new.reduceFlashes) == "boolean" and new.reduceFlashes ~= settings.reduceFlashes then
		settings.reduceFlashes = new.reduceFlashes
		motionChanged = true
	end
	if type(new.textScale) == "number" and new.textScale == new.textScale then
		local v = math.clamp(new.textScale, 1, 1.3)
		if v ~= settings.textScale then
			settings.textScale = v
			textChanged = true
		end
	end
	if type(new.keepHat) == "boolean" then
		settings.keepHat = new.keepHat
	end
	if paletteChanged then
		repaint()
		UITheme.changed:fire("palette")
	end
	if textChanged then
		reapplyTextSizes()
		UITheme.changed:fire("text")
	end
	if motionChanged then
		UITheme.changed:fire("motion")
	end
end

---------------------------------------------------------------------------- device / scale

local function computeDevice(): (Device, number)
	local camera = Workspace.CurrentCamera
	local vp = if camera then camera.ViewportSize else Vector2.new(844, 390)
	local short = math.min(vp.X, vp.Y)
	local kind: Device
	if UserInputService.TouchEnabled then
		kind = if short < UIConfig.Scale.PhoneShortSide then "phone" else "tablet"
	else
		kind = "desktop"
	end
	local scale = if kind == "phone"
		then UIConfig.Scale.Min
		else math.clamp(short / UIConfig.Scale.ReferenceShortSide, UIConfig.Scale.Min, UIConfig.Scale.Max)
	return kind, scale
end

local currentScale = 1
device, currentScale = computeDevice()

function UITheme.device(): Device
	return device
end

function UITheme.scale(): number
	return currentScale
end

-- Portrait phone (taller than wide): cards become rows, HUD stacks differently.
function UITheme.isPortrait(): boolean
	local camera = Workspace.CurrentCamera
	local vp = if camera then camera.ViewportSize else Vector2.new(844, 390)
	return vp.Y > vp.X and device == "phone"
end

local lastPortrait = false

function UITheme.isTouch(): boolean
	return UserInputService.PreferredInput == Enum.PreferredInput.Touch
		or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
end

function UITheme.inputName(): string
	local p = UserInputService.PreferredInput
	if p == Enum.PreferredInput.Gamepad then
		return "Gamepad"
	elseif p == Enum.PreferredInput.Touch then
		return "Touch"
	end
	return "KeyboardAndMouse"
end

local function refreshDevice()
	local kind, scale = computeDevice()
	local deviceChanged = kind ~= device
	device = kind
	local scaleChanged = scale ~= currentScale
	if scaleChanged then
		currentScale = scale
		for s in scales do
			s.Scale = scale
		end
	end
	if deviceChanged then
		UITheme.changed:fire("device")
	elseif scaleChanged then
		UITheme.changed:fire("scale")
	end
	local p = UITheme.isPortrait()
	if p ~= lastPortrait then
		lastPortrait = p
		UITheme.changed:fire("device")
	end
end

---------------------------------------------------------------------------- builders

function UITheme.new(className: string, props: { [string]: any }?, parent: Instance?): any
	local inst = Instance.new(className :: any)
	if props then
		for k, v in props do
			(inst :: any)[k] = v
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function UITheme.screen(name: string, displayOrder: number, insets: Enum.ScreenInsets?): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.DisplayOrder = displayOrder
	gui.ScreenInsets = insets or Enum.ScreenInsets.CoreUISafeInsets
	gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.AutoLocalize = false -- text is translated by us; invented names must not be captured
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

-- A layout zone: offset-sized frame anchored to a screen point, scaled by its own UIScale.
function UITheme.zone(parent: Instance, name: string, anchor: Vector2, position: UDim2, size: UDim2): Frame
	local frame = UITheme.new("Frame", {
		Name = name,
		AnchorPoint = anchor,
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
	}, parent)
	local s = Instance.new("UIScale")
	s.Scale = currentScale
	s.Parent = frame
	scales[s] = true
	return frame
end

function UITheme.corner(obj: Instance, radius: number?): UICorner
	return UITheme.new("UICorner", { CornerRadius = if radius then UDim.new(0, radius) else UDim.new(0, 8) }, obj)
end

function UITheme.round(obj: Instance): UICorner
	return UITheme.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, obj)
end

function UITheme.stroke(obj: Instance, thickness: number, token: string, mode: Enum.ApplyStrokeMode?): UIStroke
	local s = UITheme.new("UIStroke", {
		Thickness = thickness,
		ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Border,
	}, obj)
	UITheme.paint(s, "Color", token)
	return s
end

function UITheme.panel(parent: Instance, props: { [string]: any }?): Frame
	local f = UITheme.new("Frame", props, parent)
	f.BorderSizePixel = 0
	UITheme.paint(f, "BackgroundColor3", "Panel")
	UITheme.back(f, 0.15)
	UITheme.corner(f, 10)
	return f
end

export type LabelOpts = {
	text: any?,
	args: { [string]: any }?,
	role: string?,
	font: string?, -- "label" (default, Fredoka One) | "display" (= label) | "number" (Luckiest Guy) | "body" | "heavy" (Nunito)
	color: string?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	align: Enum.TextXAlignment?,
	valign: Enum.TextYAlignment?,
	autoSize: Enum.AutomaticSize?,
	wrap: boolean?,
	outline: boolean?,
	name: string?,
	z: number?,
}

local function styleText(t: TextLabel | TextButton, opts: LabelOpts)
	local role = opts.role or "Body"
	local base = (UIConfig.TextSize :: any)[role] or UIConfig.TextSize.Body
	textSizes[t] = base
	t.TextSize = math.round(base * settings.textScale)
	t.FontFace = if opts.font == "number"
		then numberFont
		elseif opts.font == "body" then bodyFont
		elseif opts.font == "heavy" then bodyHeavyFont
		else labelFont
	UITheme.paint(t, "TextColor3", opts.color or "Text")
	t.TextXAlignment = opts.align or Enum.TextXAlignment.Center
	t.TextYAlignment = opts.valign or Enum.TextYAlignment.Center
	t.TextWrapped = opts.wrap or false
	t.TextTruncate = if opts.wrap then Enum.TextTruncate.None else Enum.TextTruncate.AtEnd
	t.AutoLocalize = false
	if opts.outline then
		-- Ink outline at most 8 % of the size, min 1 px (vault SYMPTOMS: glyph counters; v2 review).
		local s = UITheme.new("UIStroke", {
			Name = "TextStroke",
			Thickness = math.max(1, math.round(base * UIConfig.TextStrokeRatio * 10) / 10),
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		}, t)
		UITheme.paint(s, "Color", "Outline")
	end
	if opts.text ~= nil then
		UITheme.setText(t, opts.text, opts.args)
	end
end

function UITheme.label(parent: Instance, opts: LabelOpts): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = opts.name or "Label"
	t.BackgroundTransparency = 1
	t.Size = opts.size or UDim2.new(1, 0, 0, 20)
	t.Position = opts.position or UDim2.new()
	t.AnchorPoint = opts.anchor or Vector2.zero
	t.AutomaticSize = opts.autoSize or Enum.AutomaticSize.None
	if opts.z then
		t.ZIndex = opts.z
	end
	styleText(t, opts)
	t.Parent = parent
	return t
end

-- Text button with min 44 px tap target. Fill token defaults to PanelLight.
function UITheme.button(parent: Instance, opts: LabelOpts & { fill: string? }): TextButton
	local b = Instance.new("TextButton")
	b.Name = opts.name or "Button"
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	b.Size = opts.size or UDim2.fromOffset(120, UIConfig.MinTap)
	b.Position = opts.position or UDim2.new()
	b.AnchorPoint = opts.anchor or Vector2.zero
	if opts.z then
		b.ZIndex = opts.z
	end
	UITheme.paint(b, "BackgroundColor3", opts.fill or "PanelLight")
	UITheme.corner(b, 10)
	styleText(b, opts)
	b.Parent = parent
	return b
end

function UITheme.bar(parent: Instance, size: UDim2, position: UDim2, fillToken: string, name: string?): Bar
	local frame = UITheme.new("Frame", {
		Name = name or "Bar",
		Size = size,
		Position = position,
		BorderSizePixel = 0,
	}, parent)
	UITheme.paint(frame, "BackgroundColor3", "Outline")
	UITheme.back(frame, 0.35)
	UITheme.corner(frame, 4)
	local fill = UITheme.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BorderSizePixel = 0,
	}, frame)
	UITheme.paint(fill, "BackgroundColor3", fillToken)
	UITheme.corner(fill, 4)
	local last = -1
	local function set(frac: number)
		if frac ~= frac then
			frac = 0
		end
		frac = math.clamp(frac, 0, 1)
		if math.abs(frac - last) < 0.002 then
			return
		end
		last = frac
		fill.Size = UDim2.fromScale(frac, 1)
	end
	return { frame = frame, fill = fill, set = set }
end

-- Rarity diamonds (second channel, count never changes between palettes).
function UITheme.gems(parent: Instance, gemSize: number): Frame
	local holder = UITheme.new("Frame", {
		Name = "Gems",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(gemSize * 4 + 9, gemSize + 4),
	}, parent)
	UITheme.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 3),
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, holder)
	for i = 1, 4 do
		local g = UITheme.new("Frame", {
			Name = "Gem" .. i,
			LayoutOrder = i,
			Size = UDim2.fromOffset(gemSize, gemSize),
			Rotation = 45,
			BorderSizePixel = 0,
		}, holder)
		UITheme.stroke(g, 1, "Outline")
	end
	return holder
end

function UITheme.setGems(holder: Frame, rarity: string?)
	local def = (UIConfig.Rarity :: any)[rarity or "Common"] or UIConfig.Rarity.Common
	for i = 1, 4 do
		-- lihfolk-ignore: findfirstchild-chain -- fwjelaa-ignore: findfirstchild-chain (nil-checked on the next line)
		local g = holder:FindFirstChild("Gem" .. i) :: Frame?
		if g then
			g.Visible = i <= def.gems
			UITheme.paint(g, "BackgroundColor3", if rarity and (UIConfig.Rarity :: any)[rarity] then rarity else "Common")
		end
	end
end

local ICON_TINTS = {
	Color3.fromRGB(232, 106, 76),
	Color3.fromRGB(86, 160, 232),
	Color3.fromRGB(120, 200, 110),
	Color3.fromRGB(200, 120, 220),
	Color3.fromRGB(240, 190, 70),
	Color3.fromRGB(90, 200, 200),
	Color3.fromRGB(230, 120, 160),
	Color3.fromRGB(160, 160, 180),
}

local function initials(text: string): string
	local letters = string.gsub(text, "[^%a]", "")
	local caps = string.gsub(text, "[^%u]", "")
	if #caps >= 2 then
		return string.sub(caps, 1, 2)
	end
	return string.upper(string.sub(letters, 1, 2))
end

-- Placeholder icon: rounded tile with two letters (no asset ids). Returns the tile.
function UITheme.icon(parent: Instance, id: string, size: number, name: string?): Frame
	local tile = UITheme.new("Frame", {
		Name = name or "Icon",
		Size = UDim2.fromOffset(size, size),
		BorderSizePixel = 0,
	}, parent)
	UITheme.corner(tile, math.floor(size * 0.25))
	UITheme.stroke(tile, 1, "Outline")
	UITheme.label(tile, {
		name = "Letters",
		size = UDim2.fromScale(1, 1),
		role = if size >= 34 then "Title" else "Small",
		font = "display",
		outline = true,
	})
	UITheme.setIcon(tile, id)
	return tile
end

function UITheme.setIcon(tile: Frame, id: string)
	local hash = 0
	for i = 1, #id do
		hash = (hash * 31 + string.byte(id, i)) % 65521
	end
	tile.BackgroundColor3 = ICON_TINTS[hash % #ICON_TINTS + 1]
	-- lihfolk-ignore: findfirstchild-chain -- fwjelaa-ignore: findfirstchild-chain (nil-checked on the next line)
	local letters = tile:FindFirstChild("Letters") :: TextLabel?
	if letters then
		letters.Text = initials(id)
	end
end

-- Scale pop through a UIScale (never Size: vault SYMPTOMS). Fade-only when motion is reduced.
function UITheme.pop(obj: GuiObject, from: number?)
	if UITheme.flashesReduced() then
		return
	end
	-- lihfolk-ignore: findfirstchild-chain -- fwjelaa-ignore: findfirstchild-chain (nil-checked on the next line)
	local s = obj:FindFirstChild("PopScale") :: UIScale?
	if not s then
		s = UITheme.new("UIScale", { Name = "PopScale" }, obj)
	end
	local ps = s :: UIScale
	ps.Scale = from or 0.85
	TweenService:Create(ps, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

---------------------------------------------------------------------------- v2 glossy builders
-- "Toy-block gloss" (Figma Foundations): flat face + crisp lighter band on top (two tones, no
-- gradient) + darker lip under it + navy ink outline + two square glints (voxel nod).

-- UI-wide flags shared between modules (cards open, ping wheel open...). Fires changed("flags").
function UITheme.setFlag(name: string, value: any)
	if flags[name] ~= value then
		flags[name] = value
		UITheme.changed:fire("flags")
	end
end

function UITheme.flag(name: string): any
	return flags[name]
end

export type Gloss = {
	root: GuiObject,
	face: Frame,
	shine: Frame,
	content: Frame,
	glints: { Frame },
	label: TextLabel?,
	lip: number,
	setRole: (role: string) -> (),
	setEnabled: (on: boolean) -> (),
	setPressed: (down: boolean) -> (),
}

export type GlossOpts = {
	role: string?, -- palette base token: Primary, Neutral, Danger, Premium, Info, Slide, Capture, Xp...
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	radius: number?, -- px; nil = 14, -1 = fully round
	lip: number?,
	stroke: number?,
	glints: boolean?,
	name: string?,
	button: boolean?,
	text: any?,
	args: { [string]: any }?,
	textRole: string?,
	font: string?,
	textColor: string?,
	z: number?,
}

local function addCorner(obj: Instance, radius: number)
	if radius < 0 then
		UITheme.round(obj)
	else
		UITheme.corner(obj, radius)
	end
end

-- A glossy slab (Frame, or TextButton when opts.button). Children go in `content`, which sits on the
-- face and sinks with it when pressed.
function UITheme.glossy(parent: Instance?, opts: GlossOpts): Gloss
	local role = opts.role or "Neutral"
	local radius = opts.radius or 14
	local lip = opts.lip or 5
	local root: GuiObject
	if opts.button then
		local b = Instance.new("TextButton")
		b.Text = ""
		b.AutoButtonColor = false
		root = b
	else
		root = Instance.new("Frame")
	end
	root.Name = opts.name or "Gloss"
	root.BorderSizePixel = 0
	root.Size = opts.size or UDim2.fromOffset(156, 46)
	root.Position = opts.position or UDim2.new()
	root.AnchorPoint = opts.anchor or Vector2.zero
	if opts.z then
		root.ZIndex = opts.z
	end
	addCorner(root, radius)
	local rootStroke = UITheme.stroke(root, opts.stroke or 3, "Outline")
	rootStroke.Name = "Ink"

	local face = UITheme.new("Frame", {
		Name = "Face",
		Size = UDim2.new(1, 0, 1, -lip),
		BorderSizePixel = 0,
	}, root)
	addCorner(face, radius)
	local inset = if radius < 0 then 0 else 5
	local shine = UITheme.new("Frame", {
		Name = "Shine",
		Position = if radius < 0 then UDim2.fromScale(0.14, 0.05) else UDim2.fromOffset(inset, 3),
		Size = if radius < 0 then UDim2.fromScale(0.72, 0.42) else UDim2.new(1, -2 * inset, 0.42, -2),
		BorderSizePixel = 0,
	}, face)
	addCorner(shine, if radius < 0 then -1 else math.max(2, radius - 4))
	local glints: { Frame } = {}
	if opts.glints ~= false then
		for i, sz in { 5, 3 } do
			local g = UITheme.new("Frame", {
				Name = "Glint" .. i,
				Size = UDim2.fromOffset(sz, sz),
				Position = if radius < 0
					then UDim2.new(0.26, (i - 1) * 8, 0.14, 0)
					else UDim2.fromOffset(inset + 6 + (i - 1) * 8, 6),
				BorderSizePixel = 0,
			}, face)
			UITheme.paint(g, "BackgroundColor3", "Shine")
			table.insert(glints, g)
		end
	end
	local content = UITheme.new("Frame", {
		Name = "Content",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, face)

	local label: TextLabel? = nil
	if opts.text ~= nil then
		local l = UITheme.label(content, {
			name = "Label",
			size = UDim2.fromScale(1, 1),
			role = opts.textRole or "LabelM",
			font = opts.font,
			color = opts.textColor or "Text",
			outline = true,
			text = opts.text,
			args = opts.args,
		})
		label = l
	end

	local enabled = true
	local currentRole = role
	local function paintRole()
		if enabled then
			UITheme.paint(root, "BackgroundColor3", currentRole .. "Lip")
			UITheme.paint(face, "BackgroundColor3", currentRole)
			UITheme.paint(shine, "BackgroundColor3", currentRole .. "Light")
		else
			UITheme.paint(root, "BackgroundColor3", "NeutralLip")
			UITheme.paint(face, "BackgroundColor3", "Neutral")
			UITheme.paint(shine, "BackgroundColor3", "PanelLight")
		end
		for _, g in glints do
			g.Visible = enabled
		end
		if label then
			UITheme.paint(label, "TextColor3", if enabled then (opts.textColor or "Text") else "TextMuted")
			-- lihfolk-ignore: findfirstchild-chain -- fwjelaa-ignore: findfirstchild-chain (nil-checked on the next line)
			local ts = label:FindFirstChild("TextStroke") :: UIStroke?
			if ts then
				ts.Enabled = enabled
			end
		end
	end
	paintRole()

	local pressedNow = false
	local function setPressed(down: boolean)
		if down == pressedNow then
			return
		end
		pressedNow = down
		face.Position = if down then UDim2.fromOffset(0, math.max(0, lip - 2)) else UDim2.new()
	end

	local gloss: Gloss = {
		root = root,
		face = face,
		shine = shine,
		content = content,
		glints = glints,
		label = label,
		lip = lip,
		setRole = function(r: string)
			currentRole = r
			paintRole()
		end,
		setEnabled = function(on: boolean)
			enabled = on
			if root:IsA("GuiButton") then
				root.Active = on
			end
			paintRole()
		end,
		setPressed = setPressed,
	}

	if root:IsA("GuiButton") then
		-- Press: the face sinks into the lip (lip - 2 px). Hover (mouse): UIScale 1.04.
		local hover = UITheme.new("UIScale", { Name = "HoverScale" }, root)
		root.InputBegan:Connect(function(input: InputObject)
			local t = input.UserInputType
			if enabled and (t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch) then
				setPressed(true)
			end
		end)
		root.InputEnded:Connect(function(input: InputObject)
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
				setPressed(false)
			end
		end)
		root.MouseEnter:Connect(function()
			if enabled and not UITheme.flashesReduced() then
				TweenService:Create(hover, TweenInfo.new(0.1, Enum.EasingStyle.Quad), { Scale = 1.04 }):Play()
			end
		end)
		root.MouseLeave:Connect(function()
			setPressed(false)
			TweenService:Create(hover, TweenInfo.new(0.1, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
		end)
		-- Gamepad / keyboard focus ring (gold, Figma FocusRing).
		root.SelectionImageObject = UITheme.focusRing(radius)
	end
	if parent then
		root.Parent = parent
	end
	return gloss
end

-- Focus ring used as SelectionImageObject (gamepad / keyboard navigation).
function UITheme.focusRing(radius: number?): Frame
	local ring = Instance.new("Frame")
	ring.Name = "FocusRing"
	ring.BackgroundTransparency = 1
	ring.Size = UDim2.new(1, 16, 1, 16)
	ring.Position = UDim2.fromOffset(-8, -8)
	addCorner(ring, if radius and radius >= 0 then radius + 6 else -1)
	local s = UITheme.stroke(ring, 4, "Legendary")
	s.Name = "Gold"
	return ring
end

-- Dark HUD chip behind numbers over the game (Figma Panel/Chip).
function UITheme.chip(parent: Instance?, props: { [string]: any }?): Frame
	local f = UITheme.new("Frame", props, nil)
	f.BorderSizePixel = 0
	UITheme.paint(f, "BackgroundColor3", "Panel")
	UITheme.back(f, 0.18)
	UITheme.corner(f, 14)
	UITheme.stroke(f, 2.5, "Outline").Name = "Ink"
	if parent then
		f.Parent = parent
	end
	return f
end

-- Dark panel for popups (Figma Panel/Default): ink outline 3, hard lip shadow under it.
function UITheme.popup(parent: Instance, props: { [string]: any }?): Frame
	local f = UITheme.panel(parent, props)
	UITheme.back(f, 0.04)
	-- lihfolk-ignore: findfirstchild-chain -- fwjelaa-ignore: findfirstchild-chain (nil-checked on the next line)
	local c = f:FindFirstChildOfClass("UICorner")
	if c then
		c.CornerRadius = UDim.new(0, 20)
	end
	UITheme.stroke(f, 3, "Outline").Name = "Ink"
	return f
end

-- Progress bar v2: sunken track + flat fill + white top band (45 %) + ink edge on the fill end.
function UITheme.glossBar(parent: Instance, size: UDim2, position: UDim2, fillToken: string, name: string?): Bar
	local frame = UITheme.new("Frame", {
		Name = name or "Bar",
		Size = size,
		Position = position,
		BorderSizePixel = 0,
	}, parent)
	UITheme.paint(frame, "BackgroundColor3", "PanelSunken")
	UITheme.back(frame, 0.15)
	UITheme.round(frame)
	UITheme.stroke(frame, 2.5, "Outline").Name = "Ink"
	local fill = UITheme.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BorderSizePixel = 0,
	}, frame)
	UITheme.paint(fill, "BackgroundColor3", fillToken)
	UITheme.round(fill)
	local band = UITheme.new("Frame", {
		Name = "Band",
		Position = UDim2.new(0, 3, 0, 2),
		Size = UDim2.new(1, -6, 0.32, 0),
		BorderSizePixel = 0,
		BackgroundTransparency = 0.55,
	}, fill)
	UITheme.paint(band, "BackgroundColor3", "Shine")
	UITheme.round(band)
	local last = -1
	local function set(frac: number)
		if frac ~= frac then
			frac = 0
		end
		frac = math.clamp(frac, 0, 1)
		if math.abs(frac - last) < 0.002 then
			return
		end
		last = frac
		fill.Size = UDim2.fromScale(frac, 1)
		fill.Visible = frac > 0.005
	end
	return { frame = frame, fill = fill, set = set }
end

export type Pill = { frame: Frame, label: TextLabel, setTone: (tone: string, textColor: string?) -> () }

-- Small tag (NEW, LV 3, OVERTIME, DANGER 3...). Tone = palette token of the fill.
function UITheme.pill(parent: Instance?, opts: { text: any?, args: { [string]: any }?, tone: string?, textColor: string?, name: string?, role: string? }): Pill
	local f = UITheme.new("Frame", {
		Name = opts.name or "Pill",
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		BorderSizePixel = 0,
	}, nil)
	UITheme.round(f)
	UITheme.stroke(f, 2, "Outline").Name = "Ink"
	UITheme.new("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }, f)
	local l = UITheme.label(f, {
		name = "Text",
		size = UDim2.new(0, 0, 1, 0),
		autoSize = Enum.AutomaticSize.X,
		role = opts.role or "LabelS",
		outline = true,
		text = opts.text,
		args = opts.args,
	})
	local function setTone(tone: string, textColor: string?)
		UITheme.paint(f, "BackgroundColor3", tone)
		UITheme.paint(l, "TextColor3", textColor or "Text")
		-- lihfolk-ignore: findfirstchild-chain -- fwjelaa-ignore: findfirstchild-chain (nil-checked on the next line)
		local ts = l:FindFirstChild("TextStroke") :: UIStroke?
		if ts then
			ts.Enabled = textColor == nil or textColor == "Text"
		end
	end
	setTone(opts.tone or "PanelLight", opts.textColor)
	if parent then
		f.Parent = parent
	end
	return { frame = f, label = l, setTone = setTone }
end

-- Keyboard key cap (PC hints only).
function UITheme.keycap(parent: Instance?, key: string, name: string?): Frame
	local f = UITheme.new("Frame", {
		Name = name or "Key",
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		BorderSizePixel = 0,
	}, nil)
	UITheme.paint(f, "BackgroundColor3", "Shield")
	UITheme.corner(f, 6)
	UITheme.stroke(f, 2, "Outline").Name = "Ink"
	UITheme.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, f)
	local l = UITheme.label(f, {
		name = "Text",
		size = UDim2.new(0, 0, 1, -3),
		autoSize = Enum.AutomaticSize.X,
		role = "LabelS",
		color = "OnLight",
		text = key,
	})
	l.TextYAlignment = Enum.TextYAlignment.Center
	if parent then
		f.Parent = parent
	end
	return f
end

-- Code-drawn icons (no asset ids until A08-07 icons are uploaded). Each returns a holder Frame.
local function iconPart(holder: Instance, props: { [string]: any }, color: Color3, ink: number?): Frame
	local p = UITheme.new("Frame", props, holder)
	p.BorderSizePixel = 0
	p.BackgroundColor3 = color
	if ink and ink > 0 then
		UITheme.stroke(p, ink, "Outline")
	end
	return p
end

-- KO icon: green cube head with X eyes and a pink tongue (Figma icon/ko).
function UITheme.koIcon(parent: Instance?, size: number): Frame
	local h = UITheme.new("Frame", { Name = "KoIcon", Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1 }, nil)
	local ink = math.max(1.5, size * 0.06)
	iconPart(h, { Name = "Top", Position = UDim2.fromScale(0.16, 0.06), Size = UDim2.fromScale(0.72, 0.2) }, Color3.fromHex("#A6F06B"), ink)
	iconPart(h, { Name = "Side", Position = UDim2.fromScale(0.7, 0.12), Size = UDim2.fromScale(0.2, 0.72) }, Color3.fromHex("#3FA52A"), ink)
	local face = iconPart(h, { Name = "Face", Position = UDim2.fromScale(0.04, 0.24), Size = UDim2.fromScale(0.7, 0.7) }, Color3.fromHex("#62D93D"), ink)
	local eyes = UITheme.new("TextLabel", {
		Name = "Eyes",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0.55),
		Position = UDim2.fromScale(0, 0.08),
		Text = "x x",
		TextScaled = true,
		FontFace = numberFont,
		TextColor3 = Color3.fromHex("#0E1424"),
	}, face)
	eyes.AutoLocalize = false
	iconPart(face, { Name = "Tongue", Position = UDim2.fromScale(0.34, 0.66), Size = UDim2.fromScale(0.3, 0.2) }, Color3.fromHex("#FF7FB8"), ink * 0.7)
	if parent then
		h.Parent = parent
	end
	return h
end

-- Heart (HP): two discs + a diamond, flat red with a square glint.
function UITheme.heartIcon(parent: Instance?, size: number): Frame
	local h = UITheme.new("Frame", { Name = "HeartIcon", Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1 }, nil)
	local red = UITheme.color("Hp")
	local d = iconPart(h, { Name = "Diamond", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.56), Size = UDim2.fromScale(0.52, 0.52), Rotation = 45 }, red)
	UITheme.paint(d, "BackgroundColor3", "Hp")
	for i, x in { 0.3, 0.7 } do
		local c = iconPart(h, { Name = "Lobe" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, 0.36), Size = UDim2.fromScale(0.5, 0.5) }, red)
		UITheme.round(c)
		UITheme.paint(c, "BackgroundColor3", "Hp")
	end
	local g = iconPart(h, { Name = "Glint", Position = UDim2.fromScale(0.2, 0.22), Size = UDim2.fromOffset(math.max(2, math.round(size * 0.12)), math.max(2, math.round(size * 0.12))) }, Color3.new(1, 1, 1))
	g.ZIndex = 2
	if parent then
		h.Parent = parent
	end
	return h
end

-- Clock (timer) or stopwatch (overtime): white dial, ink hands.
function UITheme.clockIcon(parent: Instance?, size: number, overtime: boolean?): Frame
	local h = UITheme.new("Frame", { Name = "ClockIcon", Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1 }, nil)
	local ink = math.max(1.5, size * 0.07)
	local knob = iconPart(h, { Name = "Knob", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(0.3, 0.16) }, Color3.new(1, 1, 1), ink)
	UITheme.paint(knob, "BackgroundColor3", if overtime then "Overtime" else "Premium")
	local dial = iconPart(h, { Name = "Dial", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromScale(0.84, 0.84) }, Color3.new(1, 1, 1), ink)
	UITheme.round(dial)
	if overtime then
		UITheme.paint(dial, "BackgroundColor3", "Overtime")
		local inner = iconPart(dial, { Name = "Inner", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.68, 0.68) }, Color3.new(1, 1, 1), ink * 0.7)
		UITheme.round(inner)
	end
	local hand1 = iconPart(dial, { Name = "Hand1", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.new(0, math.max(2, math.round(size * 0.08)), 0.32, 0) }, Color3.fromHex("#0E1424"))
	hand1.ZIndex = 3
	local hand2 = iconPart(dial, { Name = "Hand2", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.48, 0.5), Size = UDim2.new(0.26, 0, 0, math.max(2, math.round(size * 0.08))), Rotation = 25 }, Color3.fromHex("#0E1424"))
	hand2.ZIndex = 3
	if parent then
		h.Parent = parent
	end
	return h
end

-- Rarity frame tokens: <Rarity>, <Rarity>Light, <Rarity>Lip (falls back to Common).
function UITheme.rarityToken(rarity: string?): string
	return if rarity and (UIConfig.Rarity :: any)[rarity] then rarity else "Common"
end

---------------------------------------------------------------------------- formatting

function UITheme.clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

function UITheme.short(n: number): string
	local lang = UITheme.lang()
	local text: string
	if n >= 1e6 then
		text = string.format("%.1fM", n / 1e6)
	elseif n >= 1e4 then
		text = string.format("%.1fk", n / 1e3)
	else
		text = tostring(math.floor(n + 0.5))
	end
	if lang == "fr" then
		text = string.gsub(text, "%.", ",")
	end
	return text
end

function UITheme.statText(stat: string, value: number): string
	local def = (UIConfig.Stats :: any)[stat]
	local name = if def then UITheme.format(def.name) else stat
	local lang = UITheme.lang()
	local sep = if lang == "fr" then " " else ""
	if def and def.pct then
		return string.format("+%d%s%% %s", math.floor(value * 100 + 0.5), sep, name)
	end
	local num = if value % 1 == 0 then tostring(value) else string.format("%.1f", value)
	return "+" .. num .. " " .. name
end

---------------------------------------------------------------------------- other domains' configs

local configCache: { [string]: any } = {}

-- pcall-require a config module owned by another domain; nil if missing or broken.
function UITheme.config(name: string): any
	local cached = configCache[name]
	if cached ~= nil then
		return if cached == false then nil else cached
	end
	local module = ConfigFolder:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		return nil -- not cached: the module may be added later in Studio
	end
	local ok, result = pcall(require, module)
	configCache[name] = if ok and type(result) == "table" then result else false
	return if ok and type(result) == "table" then result else nil
end

-- Find a definition by id whatever the config layout ({[id]=def}, .Defs, .List, or an array).
function UITheme.def(configName: string, id: string): any
	local cfg = UITheme.config(configName)
	if not cfg then
		return nil
	end
	local direct = cfg[id]
	if type(direct) == "table" then
		return direct
	end
	for _, key in { "Defs", "Lines", "Techs", "Treats", "Kinds", "List", "All", "ById", configName } do
		local sub = cfg[key]
		if type(sub) == "table" then
			if type(sub[id]) == "table" then
				return sub[id]
			end
			for _, d in sub do
				if type(d) == "table" and d.id == id then
					return d
				end
			end
		end
	end
	for _, d in cfg do
		if type(d) == "table" and d.id == id then
			return d
		end
	end
	return nil
end

-- Display name: LocalizedText from the config's `name` field, else the id itself.
function UITheme.nameOf(configName: string, id: string): any
	local d = UITheme.def(configName, id)
	if d then
		local n = d.name or d.displayName or d.title
		if type(n) == "table" and (n.en or n.fr) then
			return n
		elseif type(n) == "string" then
			return n
		end
	end
	return id
end

---------------------------------------------------------------------------- remote cache

type Store = { last: any, signal: any, connected: boolean }
local stores: { [string]: Store } = {}

-- One connection per remote, last payload cached, late subscribers get it immediately.
-- (OnClientEvent only queues events for the first connection.)
function UITheme.watch(remoteName: string, handler: (payload: any) -> ())
	local store = stores[remoteName]
	if not store then
		local newStore: Store = { last = nil, signal = Signal.new(), connected = false }
		store = newStore
		stores[remoteName] = newStore
		task.spawn(function()
			Net.event(remoteName).OnClientEvent:Connect(function(payload)
				newStore.last = payload
				newStore.signal:fire(payload)
			end)
			newStore.connected = true
		end)
	end
	local s = store :: Store
	s.signal:connect(handler)
	if s.last ~= nil then
		task.spawn(handler, s.last)
	end
end

function UITheme.last(remoteName: string): any
	local store = stores[remoteName]
	return if store then store.last else nil
end

function UITheme.phase(): string
	return phase
end

function UITheme.inRun(): boolean
	return phase == "Running" or phase == "Boss" or phase == "BossDefeated" or phase == "FinalWave"
end

function UITheme.profile(): { [string]: any }?
	return profile
end

---------------------------------------------------------------------------- lifecycle

function UITheme.start()
	-- Language: player translator, re-detected when the player switches language (vault: Localization).
	task.spawn(function()
		local ok, translator = pcall(function()
			return LocalizationService:GetTranslatorForPlayerAsync(Players.LocalPlayer)
		end)
		if ok and translator then
			local t = translator :: Translator
			local function apply()
				local lang = detectLocale(t.LocaleId)
				if lang ~= autoLang then
					autoLang = lang
					if not langOverride then
						rewriteTexts()
						UITheme.changed:fire("lang")
					end
				end
			end
			apply()
			t:GetPropertyChangedSignal("LocaleId"):Connect(apply)
		end
	end)

	GuiService:GetPropertyChangedSignal("PreferredTransparency"):Connect(reapplyBacks)
	GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(function()
		UITheme.changed:fire("motion")
	end)
	UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
		UITheme.changed:fire("device")
	end)
	local function hookCamera()
		local camera = Workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshDevice)
		end
		refreshDevice()
	end
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hookCamera)
	hookCamera()

	UITheme.watch("RunState", function(state)
		if type(state) == "table" and type(state.phase) == "string" and state.phase ~= phase then
			phase = state.phase
			UITheme.changed:fire("phase")
		end
	end)
	UITheme.watch("RunSummary", function()
		if phase ~= "Ended" then
			phase = "Ended"
			UITheme.changed:fire("phase")
		end
	end)
	UITheme.watch("Profile", function(p)
		if type(p) ~= "table" then
			return
		end
		profile = p
		if type(p.settings) == "table" then
			UITheme.applySettings(p.settings)
		end
		UITheme.changed:fire("profile")
	end)
end

return UITheme
