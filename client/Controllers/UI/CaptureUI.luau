--!strict
-- Capture prompt (Figma L07 / P07 / C07), plain module started by HUD.
-- A beaten Capturable leaves a cage for 10 s; staying 2 s inside without being hit captures it
-- (100 %, no randomness, nothing paid). The panel shows the 2 s bar with the seconds written
-- beside it, "OUCH! CAPTURE RESET" when hit, and the creature's name on success.
-- Data: the companion domain owns capture. Until its remote exists (contract request:
-- CaptureState { state = "Idle"|"Available"|"Capturing"|"Interrupted"|"Captured", progress: 0..1,
-- holdSeconds: number?, name: LocalizedText? }), other code can call CaptureUI.set(payload).
-- Sets the UI flag "captureAvailable" so MobileButtons shows the Capture button.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(script.Parent:WaitForChild("UITheme"))

local Config = UITheme.Config
local S = UITheme.S
local C = Config.Capture

local CaptureUI = {}

local gui: ScreenGui
local zone: Frame
local panel: Frame
local ink: UIStroke
local title: TextLabel
local barRow: Frame
local bar: UITheme.Bar
local seconds: TextLabel
local hint: TextLabel
local hideAt = 0

local function cageIcon(parent: Instance, size: number): Frame
	local h = UITheme.new("Frame", { Name = "Cage", Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1 }, parent)
	local dome = UITheme.new("Frame", { Name = "Dome", Size = UDim2.new(0.8, 0, 0.78, 0), Position = UDim2.fromScale(0.1, 0.06), BorderSizePixel = 0 }, h)
	UITheme.paint(dome, "BackgroundColor3", "Capture")
	UITheme.corner(dome, math.round(size * 0.3))
	UITheme.stroke(dome, 2.5, "Outline")
	for i, x in { 0.3, 0.5, 0.7 } do
		local b = UITheme.new("Frame", { Name = "Bar" .. i, AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.new(0, 2, 0.7, 0), Position = UDim2.fromScale(x, 0.12), BorderSizePixel = 0 }, h)
		UITheme.paint(b, "BackgroundColor3", "Outline")
	end
	local base = UITheme.new("Frame", { Name = "Base", Size = UDim2.new(1, 0, 0.16, 0), Position = UDim2.fromScale(0, 0.82), BorderSizePixel = 0 }, h)
	UITheme.paint(base, "BackgroundColor3", "Premium")
	UITheme.corner(base, 3)
	UITheme.stroke(base, 2, "Outline")
	return h
end

local function layout()
	if UITheme.isPortrait() then
		zone.AnchorPoint = Vector2.new(0, 0)
		zone.Position = UDim2.new(0, Config.Margin, 0.6, 22)
	else
		-- Above the player (3rd-person camera: hero around 70 % of the height).
		zone.AnchorPoint = Vector2.new(0.5, 1)
		zone.Position = UDim2.new(0.5, 0, 0.56, 0)
	end
end

-- Public: show a capture state. Also used by the companion domain if it prefers a direct call.
function CaptureUI.set(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local state = tostring(payload.state or "Idle")
	UITheme.setFlag("captureAvailable", state == "Available" or state == "Capturing")
	UITheme.setFlag("capturing", state == "Capturing")
	if state == "Idle" or state == "Available" then
		gui.Enabled = false
		return
	end
	local hold = tonumber(payload.holdSeconds) or C.HoldSeconds
	local progress = math.clamp(tonumber(payload.progress) or 0, 0, 1)
	if state == "Capturing" then
		UITheme.paint(ink, "Color", "Capture")
		UITheme.setText(title, S.Capturing)
		UITheme.paint(title, "TextColor3", "Text")
		barRow.Visible = true
		bar.set(progress)
		UITheme.setText(seconds, S.CaptureSeconds, { s = string.format("%.1f", progress * hold), t = hold })
		UITheme.setText(hint, S.CaptureHint)
	elseif state == "Interrupted" then
		UITheme.paint(ink, "Color", "Danger")
		UITheme.setText(title, S.CaptureReset)
		UITheme.paint(title, "TextColor3", "DangerLight")
		barRow.Visible = true
		bar.set(0)
		UITheme.setText(seconds, S.CaptureSeconds, { s = "0", t = hold })
		UITheme.setText(hint, S.CaptureRetry)
	elseif state == "Captured" then
		UITheme.paint(ink, "Color", "Legendary")
		UITheme.setText(title, S.Captured)
		UITheme.paint(title, "TextColor3", "Legendary")
		barRow.Visible = false
		UITheme.setText(hint, S.CaptureJoins, { name = UITheme.format(payload.name or "?") })
	end
	gui.Enabled = UITheme.inRun()
	if state ~= "Capturing" then
		local stamp = os.clock() + C.ResultSeconds
		hideAt = stamp
		task.delay(C.ResultSeconds, function()
			if hideAt == stamp then
				gui.Enabled = false
			end
		end)
	else
		hideAt = 0
	end
end

local function hookRemote(remote: Instance)
	if remote.Name == C.RemoteName and remote:IsA("RemoteEvent") then
		remote.OnClientEvent:Connect(CaptureUI.set)
	end
end

function CaptureUI.start()
	gui = UITheme.screen("COHUE_Capture", 22)
	gui.Enabled = false
	zone = UITheme.zone(gui, "Capture", Vector2.new(0.5, 1), UDim2.fromScale(0.5, 0.56), UDim2.fromOffset(300, 84))
	panel = UITheme.popup(zone, { Name = "Panel", Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY })
	ink = panel:WaitForChild("Ink") :: UIStroke
	UITheme.paint(ink, "Color", "Capture")
	UITheme.new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 16), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 10) }, panel)
	UITheme.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10) }, panel)
	cageIcon(panel, 40).LayoutOrder = 1
	local col = UITheme.new("Frame", { Name = "Text", BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, LayoutOrder = 2 }, panel)
	UITheme.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }, col)
	title = UITheme.label(col, { name = "Title", size = UDim2.new(0, 0, 0, 20), autoSize = Enum.AutomaticSize.X, role = "TitleM", outline = true, align = Enum.TextXAlignment.Left })
	title.LayoutOrder = 1
	barRow = UITheme.new("Frame", { Name = "BarRow", BackgroundTransparency = 1, Size = UDim2.fromOffset(220, 18), LayoutOrder = 2 }, col)
	bar = UITheme.glossBar(barRow, UDim2.fromOffset(150, 16), UDim2.fromOffset(0, 1), "Capture")
	seconds = UITheme.label(barRow, { name = "Seconds", size = UDim2.fromOffset(64, 18), position = UDim2.fromOffset(158, 0), role = "LabelM", align = Enum.TextXAlignment.Left, outline = true })
	hint = UITheme.label(col, { name = "Hint", size = UDim2.new(0, 0, 0, 18), autoSize = Enum.AutomaticSize.X, role = "BodyS", font = "body", color = "TextDim", align = Enum.TextXAlignment.Left })
	hint.LayoutOrder = 3

	layout()
	UITheme.changed:connect(function(reason: string)
		if reason == "device" then
			layout()
		elseif reason == "phase" and not UITheme.inRun() then
			gui.Enabled = false
			UITheme.setFlag("captureAvailable", false)
		end
	end)

	-- Optional remote: hooked if it exists now or appears later (never waits forever).
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local r = remotes:FindFirstChild(C.RemoteName)
		if r then
			hookRemote(r)
		else
			remotes.ChildAdded:Connect(hookRemote)
		end
	end
end

return CaptureUI
