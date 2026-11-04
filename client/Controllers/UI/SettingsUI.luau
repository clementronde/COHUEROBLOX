--!strict
-- Settings panel: colorblind, reduce flashes, text size, keep hat, language, map legend.
-- Design: docs/dossier/60-ui-ux.md section 11. Reads Profile.settings (via UITheme).
-- Sends: UpdateSettings(settings) (batched, max 1 per 0.5 s). Language is local only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Registry = require(Shared:WaitForChild("Registry"))
local UITheme = require(script.Parent:WaitForChild("UITheme"))

local Config = UITheme.Config
local S = UITheme.S

local SettingsUI = {}

local gearGui: ScreenGui
local gearZone: Frame
local gui: ScreenGui
local toggles: { [string]: TextButton } = {}
local sizeButtons: { TextButton } = {}
local langButtons: { [string]: TextButton } = {}
local legend: TextLabel
local pending: { [string]: any } = {}
local sendScheduled = false

local function queueSend(key: string, value: any)
	pending[key] = value
	if sendScheduled then
		return
	end
	sendScheduled = true
	task.delay(Config.Settings.SendDelay, function()
		sendScheduled = false
		local payload = pending
		pending = {}
		Net.event("UpdateSettings"):FireServer(payload)
	end)
end

local function render()
	local st = UITheme.settings()
	for key, b in toggles do
		local on = (st :: any)[key] == true
		UITheme.setText(b, if on then S.On else S.Off)
		UITheme.paint(b, "BackgroundColor3", if on then "Primary" else "PanelLight")
	end
	for i, b in sizeButtons do
		local on = math.abs(Config.TextScales[i] - st.textScale) < 0.01
		UITheme.paint(b, "BackgroundColor3", if on then "Primary" else "PanelLight")
	end
	local override = UITheme.langOverride()
	for key, b in langButtons do
		local on = (key == "auto" and override == nil) or key == override
		UITheme.paint(b, "BackgroundColor3", if on then "Primary" else "PanelLight")
	end
end

local function row(parent: Instance, orderN: number, label: any): Frame
	local f = UITheme.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = orderN }, parent)
	UITheme.label(f, {
		size = UDim2.new(0.5, 0, 1, 0),
		role = "Body",
		align = Enum.TextXAlignment.Left,
		wrap = true,
		text = label,
	})
	return f
end

local function toggleRow(parent: Instance, orderN: number, label: any, key: string)
	local f = row(parent, orderN, label)
	local b = UITheme.button(f, {
		name = key,
		size = UDim2.fromOffset(80, 44),
		position = UDim2.fromScale(1, 0),
		anchor = Vector2.new(1, 0),
		role = "Body",
	})
	b.Activated:Connect(function()
		local st = UITheme.settings()
		local value = not ((st :: any)[key] == true)
		UITheme.applySettings({ [key] = value })
		queueSend(key, value)
		render()
	end)
	toggles[key] = b
end

function SettingsUI.open()
	gui.Enabled = true
	legend.Visible = false
	render()
end

function SettingsUI.close()
	gui.Enabled = false
end

-- v2 (Figma): phone landscape = left of the minimap (keeps the bottom-right free for the
-- Capture button); portrait and PC = centred under the minimap.
local function placeGear()
	local minimap = Registry.find("Minimap")
	local scale = UITheme.scale()
	local size = 120 * scale
	local bottom = Config.Margin + size
	if minimap and type(minimap.getBottom) == "function" then
		bottom = minimap.getBottom()
	end
	if minimap and type(minimap.getSize) == "function" then
		size = minimap.getSize()
	end
	if UITheme.device() == "phone" and not UITheme.isPortrait() then
		gearZone.Position = UDim2.new(1, -(Config.Margin + math.round(size) + 6), 0, math.round(bottom - 44 * scale - 2))
	else
		gearZone.Position = UDim2.new(1, -(Config.Margin + math.round(size / 2 - 22 * scale)), 0, math.round(bottom + 6))
	end
	gearGui.Enabled = UITheme.inRun()
end

-- Gear glyph drawn in code (8 teeth around a disc with a hole).
local function gearGlyph(parent: Instance, size: number)
	local h = UITheme.new("Frame", { Name = "Glyph", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1 }, parent)
	for i = 0, 3 do
		local tooth = UITheme.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0.28, 0, 1, 0), Rotation = i * 45, BorderSizePixel = 0 }, h)
		UITheme.paint(tooth, "BackgroundColor3", "TextDim")
		UITheme.corner(tooth, 2)
	end
	local disc = UITheme.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.74, 0.74), BorderSizePixel = 0 }, h)
	UITheme.paint(disc, "BackgroundColor3", "TextDim")
	UITheme.round(disc)
	UITheme.stroke(disc, 1.5, "Outline")
	local hole = UITheme.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.34, 0.34), BorderSizePixel = 0 }, h)
	UITheme.paint(hole, "BackgroundColor3", "Neutral")
	UITheme.round(hole)
	UITheme.stroke(hole, 1.5, "Outline")
end

function SettingsUI.start()
	gearGui = UITheme.screen("COHUE_SettingsGear", 13, Enum.ScreenInsets.DeviceSafeInsets)
	gearZone = UITheme.zone(gearGui, "Gear", Vector2.new(1, 0), UDim2.new(1, -Config.Margin, 0, 130), UDim2.fromOffset(44, 44))
	local gearGloss = UITheme.glossy(gearZone, { name = "Gear", button = true, role = "Neutral", radius = -1, lip = 4, size = UDim2.fromOffset(44, 44) })
	gearGlyph(gearGloss.content, 26)
	local gear = gearGloss.root :: GuiButton
	gear.Activated:Connect(function()
		if gui.Enabled then
			SettingsUI.close()
		else
			SettingsUI.open()
		end
	end)

	gui = UITheme.screen("COHUE_Settings", 60)
	gui.Enabled = false
	local zone = UITheme.zone(gui, "Settings", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(340, 330))
	local panel = UITheme.panel(zone, { Size = UDim2.fromScale(1, 1) })
	UITheme.back(panel, 0.05)
	UITheme.label(panel, { size = UDim2.new(1, -60, 0, 36), position = UDim2.fromOffset(12, 4), role = "Title", font = "display", align = Enum.TextXAlignment.Left, text = S.Settings })
	local close = UITheme.button(panel, {
		name = "Close",
		size = UDim2.fromOffset(44, 44),
		position = UDim2.new(1, -4, 0, 4),
		anchor = Vector2.new(1, 0),
		role = "Title",
		font = "display",
		text = "X",
	})
	close.Activated:Connect(SettingsUI.close)

	local list = UITheme.new("ScrollingFrame", {
		Size = UDim2.new(1, -24, 1, -56),
		Position = UDim2.fromOffset(12, 52),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, panel)
	UITheme.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)

	toggleRow(list, 1, S.Colorblind, "colorblind")
	toggleRow(list, 2, S.ReduceFlashes, "reduceFlashes")
	local sizeRow = row(list, 3, S.TextSize)
	for i, v in Config.TextScales do
		local b = UITheme.button(sizeRow, {
			name = "Size" .. i,
			size = UDim2.fromOffset(52, 44),
			position = UDim2.new(1, -(3 - i) * 56, 0, 0),
			anchor = Vector2.new(1, 0),
			role = "Small",
		})
		b.Text = string.format("%d%%", math.floor(v * 100 + 0.5))
		b.Activated:Connect(function()
			UITheme.applySettings({ textScale = v })
			queueSend("textScale", v)
			render()
		end)
		sizeButtons[i] = b
	end
	toggleRow(list, 4, S.KeepHat, "keepHat")
	local langRow = row(list, 5, S.Language)
	for i, key in { "auto", "fr", "en" } do
		local b = UITheme.button(langRow, {
			name = key,
			size = UDim2.fromOffset(52, 44),
			position = UDim2.new(1, -(3 - i) * 56, 0, 0),
			anchor = Vector2.new(1, 0),
			role = "Small",
		})
		if key == "auto" then
			UITheme.setText(b, S.LangAuto)
		else
			b.Text = if key == "fr" then "FR" else "EN"
		end
		b.Activated:Connect(function()
			UITheme.setLanguage(if key == "auto" then nil else key :: any)
			render()
		end)
		langButtons[key] = b
	end
	local legendBtn = UITheme.button(list, {
		name = "LegendButton",
		size = UDim2.new(1, 0, 0, 44),
		role = "Body",
		text = S.Legend,
	})
	legendBtn.LayoutOrder = 6
	legend = UITheme.label(list, {
		name = "Legend",
		size = UDim2.new(1, 0, 0, 0),
		autoSize = Enum.AutomaticSize.Y,
		role = "Small",
		font = "body",
		wrap = true,
		align = Enum.TextXAlignment.Left,
		text = S.LegendText,
	})
	legend.LayoutOrder = 7
	legend.Visible = false
	legendBtn.Activated:Connect(function()
		legend.Visible = not legend.Visible
	end)

	UserInputService.InputBegan:Connect(function(input)
		if gui.Enabled and (input.KeyCode == Enum.KeyCode.ButtonB or input.KeyCode == Enum.KeyCode.Escape) then
			SettingsUI.close()
		end
	end)
	UITheme.changed:connect(function(reason: string)
		if reason == "phase" or reason == "device" or reason == "scale" then
			placeGear()
		end
		if gui.Enabled and (reason == "profile" or reason == "palette" or reason == "lang") then
			render()
		end
	end)
	placeGear()
	render()
end

return SettingsUI
