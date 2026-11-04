--!strict
-- Bottom-right touch buttons v2 (Figma L06 / P06): Jump 84 (blue), Slide 68 (teal), Ping 52
-- (neutral), Capture 68 (pink, only while a capture is possible, gold ring = ready). Round glossy
-- slabs, label under each button, >= 44 px with >= 8 px gaps. Hidden during the 8 s card offer
-- and while the ping wheel is open. Keyboard / gamepad: a key legend replaces them (Figma C06).
-- Design: docs/dossier/60-ui-ux.md section 0. Flags read: cardsOpen, pingWheelOpen, captureAvailable.
-- Input: UIInput.bindButton -> InputController.bindButton (engine UIButton binding), else trigger.

local UITheme = require(script.Parent:WaitForChild("UITheme"))
local UIInput = require(script.Parent:WaitForChild("UIInput"))

local Config = UITheme.Config
local MB = Config.Mobile
local S = UITheme.S

local MobileButtons = {}

type Btn = { holder: Frame, gloss: UITheme.Gloss, ring: Frame? }

local gui: ScreenGui
local zone: Frame
local buttons: { [string]: Btn } = {}
local legendGui: ScreenGui
local legendZone: Frame
local legendRows: { [string]: Frame } = {}

local ZONE_W, ZONE_H = 240, 260
local RING = 6 -- room around each circle for the Ready ring

-- Code-drawn glyphs (white with ink outline) until A08-07 icons are uploaded.
local function glyph(parent: Instance, kind: string, size: number)
	local h = UITheme.new("Frame", { Name = "Glyph", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1 }, parent)
	local function part(props: { [string]: any })
		local p = UITheme.new("Frame", props, h)
		p.BorderSizePixel = 0
		UITheme.paint(p, "BackgroundColor3", "Shine")
		UITheme.stroke(p, 2, "Outline")
		return p
	end
	if kind == "Jump" then
		part({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromScale(0.34, 0.5) })
		part({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.38), Size = UDim2.fromScale(0.5, 0.5), Rotation = 45 })
	elseif kind == "Slide" then
		part({ AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.08, 0.55), Size = UDim2.fromScale(0.5, 0.3) })
		part({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.62, 0.55), Size = UDim2.fromScale(0.44, 0.44), Rotation = 45 })
	elseif kind == "Ping" then
		local pole = part({ Position = UDim2.fromScale(0.22, 0.1), Size = UDim2.fromScale(0.12, 0.82) })
		UITheme.paint(pole, "BackgroundColor3", "CoinLip")
		local flag = part({ Position = UDim2.fromScale(0.32, 0.12), Size = UDim2.fromScale(0.52, 0.38) })
		UITheme.paint(flag, "BackgroundColor3", "Ko")
	elseif kind == "Capture" then
		local dome = part({ Position = UDim2.fromScale(0.14, 0.08), Size = UDim2.fromScale(0.72, 0.7) })
		UITheme.corner(dome, math.round(size * 0.28))
		for i, x in { 0.36, 0.5, 0.64 } do
			local b = UITheme.new("Frame", { Name = "Bar" .. i, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(x, 0.14), Size = UDim2.new(0, 2, 0.6, 0), BorderSizePixel = 0 }, h)
			UITheme.paint(b, "BackgroundColor3", "Outline")
		end
		local base = part({ Position = UDim2.fromScale(0.06, 0.8), Size = UDim2.fromScale(0.88, 0.14) })
		UITheme.paint(base, "BackgroundColor3", "Premium")
	end
end

local function makeButton(name: string, d: number, role: string, label: any, anchorOffset: Vector2): Btn
	local holder = UITheme.new("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, anchorOffset.X, 1, anchorOffset.Y),
		Size = UDim2.fromOffset(d + 2 * RING, d + 2 * RING + MB.LabelHeight),
	}, zone)
	local gloss = UITheme.glossy(holder, {
		name = "Button",
		button = true,
		role = role,
		radius = -1,
		lip = if d >= 80 then 7 elseif d >= 60 then 6 else 5,
		size = UDim2.fromOffset(d, d),
		position = UDim2.fromOffset(RING, RING),
	})
	glyph(gloss.content, name, math.round(d * 0.52))
	UITheme.label(holder, {
		name = "Label",
		size = UDim2.new(1, 8, 0, MB.LabelHeight),
		position = UDim2.new(0, -4, 1, -MB.LabelHeight),
		role = "LabelS",
		outline = true,
		text = label,
	})
	local b: Btn = { holder = holder, gloss = gloss, ring = nil }
	buttons[name] = b
	return b
end

local function legendRow(parent: Instance, action: string, order: number, fallbackKey: string, label: any)
	local row = UITheme.new("Frame", { Name = action, BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = order }, parent)
	UITheme.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6) }, row)
	local key = UITheme.keycap(row, UIInput.hint(action, fallbackKey) or fallbackKey)
	key.LayoutOrder = 1
	local text = UITheme.label(row, { name = "Label", size = UDim2.new(0, 0, 1, 0), autoSize = Enum.AutomaticSize.X, role = "LabelM", outline = true, text = label })
	text.LayoutOrder = 2
	legendRows[action] = row
end

local function layout()
	local touch = UITheme.isTouch()
	local inRun = UITheme.inRun()
	local hidden = UITheme.flag("cardsOpen") == true or UITheme.flag("pingWheelOpen") == true
	gui.Enabled = inRun and touch and not hidden
	legendGui.Enabled = inRun and not touch and UITheme.flag("cardsOpen") ~= true
	local canCapture = UITheme.flag("captureAvailable") == true
	buttons.Jump.holder.Visible = MB.ShowJump
	buttons.Capture.holder.Visible = canCapture
	local ring = buttons.Capture.ring
	if ring then
		ring.Visible = canCapture and UITheme.flag("capturing") ~= true
	end
	legendRows.Capture.Visible = canCapture
end

function MobileButtons.start()
	gui = UITheme.screen("COHUE_Mobile", 15)
	zone = UITheme.zone(gui, "Buttons", Vector2.new(1, 1), UDim2.new(1, -MB.EdgeX, 1, -MB.EdgeY), UDim2.fromOffset(ZONE_W, ZONE_H))

	local jumpW = MB.Jump + 2 * RING
	local actionW = MB.Action + 2 * RING
	local jumpH = jumpW + MB.LabelHeight
	local actionH = actionW + MB.LabelHeight
	local jump = makeButton("Jump", MB.Jump, "Info", S.Jump, Vector2.new(0, 0))
	local slide = makeButton("Slide", MB.Action, "Slide", S.Slide, Vector2.new(-jumpW, 0))
	local ping = makeButton("Ping", MB.Ping, "Neutral", S.Ping, Vector2.new(-(jumpW + 8), -(actionH + 4)))
	local capture = makeButton("Capture", MB.Action, "Capture", S.Capture, Vector2.new(-8, -(jumpH + 8)))
	-- Ready ring: gold, static (no pulse: Reduce-flashes safe by default).
	local ring = UITheme.new("Frame", { Name = "ReadyRing", BackgroundTransparency = 1, Size = UDim2.fromOffset(actionW, actionW), ZIndex = 0 }, capture.holder)
	UITheme.round(ring)
	UITheme.stroke(ring, 4, "Legendary")
	capture.ring = ring

	UIInput.bindButton("Jump", jump.gloss.root :: GuiButton)
	UIInput.bindButton("Slide", slide.gloss.root :: GuiButton)
	UIInput.bindButton("Ping", ping.gloss.root :: GuiButton)
	UIInput.bindButton("Capture", capture.gloss.root :: GuiButton)

	-- Keyboard / gamepad legend (bottom right, Figma C01 / C06).
	legendGui = UITheme.screen("COHUE_KeyLegend", 15)
	legendZone = UITheme.zone(legendGui, "Legend", Vector2.new(1, 1), UDim2.new(1, -Config.Margin, 1, -Config.Margin), UDim2.fromOffset(240, 130))
	local col = UITheme.new("Frame", { Name = "Rows", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY }, legendZone)
	UITheme.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 6) }, col)
	legendRow(col, "Capture", 1, "E", S.Capture)
	legendRow(col, "Jump", 2, "SPACE", S.Jump)
	legendRow(col, "Slide", 3, "SHIFT", S.Slide)
	legendRow(col, "Ping", 4, "G", S.Ping)

	layout()
	UITheme.changed:connect(function(reason: string)
		if reason == "device" or reason == "phase" or reason == "flags" then
			layout()
		end
	end)
end

return MobileButtons
