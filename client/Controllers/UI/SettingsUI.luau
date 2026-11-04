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

local function placeGear()
	local minimap = Registry.find("Minimap")
	local top = Config.Margin + 120
	if minimap and type(minimap.getBottom) == "function" then
		top = minimap.getBottom() + Config.Margin
	end
	gearZone.Position = UDim2.new(1, -Config.Margin, 0, top)
	gearGui.Enabled = UITheme.inRun()
end

function SettingsUI.start()
	gearGui = UITheme.screen("COHUE_SettingsGear", 13)
	gearZone = UITheme.zone(gearGui, "Gear", Vector2.new(1, 0), UDim2.new(1, -Config.Margin, 0, 130), UDim2.fromOffset(44, 44))
	local gear = UITheme.button(gearZone, {
		name = "Gear",
		size = UDim2.fromOffset(44, 44),
		role = "Title",
		font = "display",
		text = "...",
		fill = "Panel",
	})
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
		if reason == "phase" or reason == "device" then
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
