--!strict
-- Shared UI tokens, builders, language, device profile and remote cache (ui domain).
-- Design: docs/dossier/60-ui-ux.md sections 1, 12, 13, 14. Every other UI module requires this one.
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

local bodyFont = Font.new(UIConfig.Fonts.Body, Enum.FontWeight.Medium, Enum.FontStyle.Normal)
local boldFont = Font.new(UIConfig.Fonts.Body, Enum.FontWeight.Bold, Enum.FontStyle.Normal)
local displayFont = Font.fromName(UIConfig.Fonts.Display)

---------------------------------------------------------------------------- language

local function detectLocale(id: string?): Lang
	if id and string.sub(string.lower(id), 1, 2) == "fr" then
		return "fr"
	end
	return "en"
end

autoLang = detectLocale(LocalizationService.RobloxLocaleId)

function UITheme.lang(): Lang
	return langOverride or autoLang
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
	if scale ~= currentScale then
		currentScale = scale
		for s in scales do
			s.Scale = scale
		end
	end
	if deviceChanged then
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
	font: string?, -- "body" | "bold" | "display"
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
	t.FontFace = if opts.font == "display" then displayFont elseif opts.font == "body" then bodyFont else boldFont
	UITheme.paint(t, "TextColor3", opts.color or "Text")
	t.TextXAlignment = opts.align or Enum.TextXAlignment.Center
	t.TextYAlignment = opts.valign or Enum.TextYAlignment.Center
	t.TextWrapped = opts.wrap or false
	t.TextTruncate = if opts.wrap then Enum.TextTruncate.None else Enum.TextTruncate.AtEnd
	t.AutoLocalize = false
	if opts.outline then
		-- Stroke at or below ~7% of the text size (vault SYMPTOMS: glyph counters).
		local s = UITheme.new("UIStroke", {
			Thickness = math.max(1, math.floor(base * 0.07)),
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
		-- lihfolk-ignore: findfirstchild-chain (nil-checked on the next line)
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
	-- lihfolk-ignore: findfirstchild-chain (nil-checked on the next line)
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
	-- lihfolk-ignore: findfirstchild-chain (nil-checked on the next line)
	local s = obj:FindFirstChild("PopScale") :: UIScale?
	if not s then
		s = UITheme.new("UIScale", { Name = "PopScale" }, obj)
	end
	local ps = s :: UIScale
	ps.Scale = from or 0.85
	TweenService:Create(ps, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
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
