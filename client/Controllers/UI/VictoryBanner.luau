--!strict
-- Victory banner (Figma L08 / P08 / C08), plain module started by HUD.
-- After the last world's boss: gold ribbon + two equal-weight choices. Keep going = the one green
-- Go (endless Overtime, chase the KO record); Cash out = gold (end the run, bank the loot).
-- Server rule (RunManager A04-02): Cash out happens when every active player stands 2 s in the
-- gold portal. So "Keep going" just closes the banner, and "Cash out" closes it and guides the
-- player to the portal (arrow + distance + team hold progress from RunState.cashOutProgress).
-- Listens (via HUD): RunState { victory, cashOutPosition, cashOutProgress }. Keys: C / K, gamepad A.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local UITheme = require(script.Parent:WaitForChild("UITheme"))

local Config = UITheme.Config
local S = UITheme.S
local V = Config.Victory

local VictoryBanner = {}

local LOCAL = Players.LocalPlayer

local scrimGui: ScreenGui
local gui: ScreenGui
local zone: Frame
local body: Frame
local choices: Frame
local koLine: TextLabel
local newBest: UITheme.Pill
local keepBtn: UITheme.Gloss
local cashBtn: UITheme.Gloss
local guideGui: ScreenGui
local guideZone: Frame
local guideArrow: Frame
local guideText: TextLabel
local guideBar: UITheme.Bar

local shownForRun = false -- banner shown once per victory
local open = false
local guiding = false
local portal: Vector3? = nil
local guideConn: RBXScriptConnection? = nil

local function close()
	open = false
	gui.Enabled = false
	scrimGui.Enabled = false
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
		GuiService.SelectedObject = nil
	end
end

local lastDist = -1
local function guideStep()
	local target = portal
	local camera = Workspace.CurrentCamera
	if not target or not camera then
		return
	end
	local rel = camera.CFrame:VectorToObjectSpace(target - camera.CFrame.Position)
	guideArrow.Rotation = math.deg(math.atan2(rel.X, -rel.Z)) - 90
	local character = LOCAL.Character
	-- lihfolk-ignore: findfirstchild-chain -- fwjelaa-ignore: findfirstchild-chain (nil-checked below)
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local d = math.floor((target - root.Position).Magnitude)
		if d ~= lastDist then
			lastDist = d
			UITheme.setText(guideText, S.CashOutPortal, { n = d })
		end
	end
end

local function setGuide(on: boolean)
	guiding = on and portal ~= nil
	guideGui.Enabled = guiding and UITheme.inRun()
	if guiding and not guideConn then
		guideConn = RunService.RenderStepped:Connect(guideStep)
	elseif not guiding and guideConn then
		guideConn:Disconnect()
		guideConn = nil
	end
end

local function renderKo()
	local progress = UITheme.last("PlayerProgress")
	local kills = if type(progress) == "table" then tonumber(progress.kills) else nil
	kills = kills or tonumber(LOCAL:GetAttribute("RunKills")) or 0
	UITheme.setText(koLine, S.KoRun, { n = UITheme.short(kills or 0) })
	local profile = UITheme.profile()
	local best = if profile then tonumber(profile.bestKills) else nil
	newBest.frame.Visible = best ~= nil and best > 0 and (kills or 0) > best
end

local function layout()
	local portrait = UITheme.isPortrait()
	local l = choices:FindFirstChildOfClass("UIListLayout")
	if l then
		l.FillDirection = if portrait then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal
	end
	guideZone.Position = if portrait then UDim2.new(0.5, 0, 0, 180) else UDim2.new(0.5, 0, 0, 96)
end

local function openBanner()
	open = true
	renderKo()
	layout()
	gui.Enabled = UITheme.inRun()
	scrimGui.Enabled = gui.Enabled
	UITheme.pop(body, 0.9)
	if UserInputService.PreferredInput == Enum.PreferredInput.Gamepad then
		GuiService.SelectedObject = keepBtn.root
	end
end

function VictoryBanner.cashOut()
	close()
	setGuide(true)
end

function VictoryBanner.keepGoing()
	close()
	setGuide(false)
end

-- Called by HUD for every RunState.
function VictoryBanner.onRunState(state: any)
	if type(state) ~= "table" then
		return
	end
	if state.phase == "Loadout" or state.phase == "Ended" or state.victory ~= true then
		if state.victory ~= true then
			shownForRun = false
		end
		if open then
			close()
		end
		portal = nil
		setGuide(false)
		return
	end
	portal = if typeof(state.cashOutPosition) == "Vector3" then state.cashOutPosition else portal
	local p = tonumber(state.cashOutProgress)
	guideBar.frame.Visible = p ~= nil and p > 0
	guideBar.set(p or 0)
	if not shownForRun then
		shownForRun = true
		openBanner()
	end
	if guiding then
		setGuide(true)
	end
end

local function choice(parent: Instance, order: number, role: string, text: any, caption: any): UITheme.Gloss
	local col = UITheme.new("Frame", { Name = "Choice" .. order, BackgroundTransparency = 1, Size = UDim2.fromOffset(224, 86), LayoutOrder = order }, parent)
	local btn = UITheme.glossy(col, {
		name = "Button",
		button = true,
		role = role,
		size = UDim2.fromOffset(220, 58),
		position = UDim2.fromOffset(2, 0),
		radius = 16,
		lip = 6,
		text = text,
		textRole = "TitleL",
	})
	UITheme.label(col, {
		name = "Caption",
		size = UDim2.new(1, 0, 0, 20),
		position = UDim2.fromOffset(0, 64),
		role = "BodyS",
		font = "body",
		color = "TextMuted",
		text = caption,
	})
	return btn
end

function VictoryBanner.start()
	scrimGui = UITheme.screen("COHUE_VictoryScrim", 44, Enum.ScreenInsets.None)
	scrimGui.Enabled = false
	local scrim = UITheme.new("Frame", { Name = "Scrim", Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, BackgroundTransparency = 0.5 }, scrimGui)
	UITheme.paint(scrim, "BackgroundColor3", "Outline")

	gui = UITheme.screen("COHUE_Victory", 45)
	gui.Enabled = false
	zone = UITheme.zone(gui, "Victory", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(540, 300))
	UITheme.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, -10) }, zone)
	-- Ribbon: gold glossy slab with two tails (the tails are plain lip-coloured blocks behind it).
	local ribbonHolder = UITheme.new("Frame", { Name = "Ribbon", BackgroundTransparency = 1, Size = UDim2.fromOffset(420, 76), LayoutOrder = 1, ZIndex = 2 }, zone)
	for i, x in { 0, 350 } do
		local tail = UITheme.new("Frame", { Name = "Tail" .. i, Size = UDim2.fromOffset(70, 52), Position = UDim2.fromOffset(x, 20), BorderSizePixel = 0 }, ribbonHolder)
		UITheme.paint(tail, "BackgroundColor3", "PremiumLip")
		UITheme.corner(tail, 6)
		UITheme.stroke(tail, 3, "Outline")
	end
	local ribbon = UITheme.glossy(ribbonHolder, { name = "Slab", role = "Premium", size = UDim2.fromOffset(340, 68), position = UDim2.fromOffset(40, 4), radius = 18, lip = 7 })
	UITheme.label(ribbon.content, { name = "Title", size = UDim2.fromScale(1, 1), role = "NumberXL", font = "number", outline = true, text = S.Victory })

	body = UITheme.popup(zone, { Name = "Body", Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, LayoutOrder = 2 })
	UITheme.new("UIPadding", { PaddingTop = UDim.new(0, 22), PaddingBottom = UDim.new(0, 16), PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 20) }, body)
	UITheme.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 10) }, body)
	UITheme.new("UIScale", { Name = "PopScale" }, body)
	local sub = UITheme.label(body, { name = "Sub", size = UDim2.fromOffset(300, 0), autoSize = Enum.AutomaticSize.Y, role = "BodyM", font = "heavy", color = "TextDim", wrap = true, text = S.VictorySub })
	sub.LayoutOrder = 1
	local koRow = UITheme.new("Frame", { Name = "Ko", BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2 }, body)
	UITheme.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8) }, koRow)
	UITheme.koIcon(koRow, 28).LayoutOrder = 1
	koLine = UITheme.label(koRow, { name = "Text", size = UDim2.new(0, 0, 1, 0), autoSize = Enum.AutomaticSize.X, role = "NumberM", font = "number", outline = true })
	koLine.LayoutOrder = 2
	newBest = UITheme.pill(koRow, { name = "NewBest", tone = "Premium", textColor = "OnLight", text = S.NewBest })
	newBest.frame.LayoutOrder = 3
	choices = UITheme.new("Frame", { Name = "Choices", BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, LayoutOrder = 3 }, body)
	UITheme.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 16) }, choices)
	cashBtn = choice(choices, 1, "Premium", S.CashOut, S.CashOutCaption)
	keepBtn = choice(choices, 2, "Primary", S.KeepGoing, S.KeepGoingCaption)
	local hint = UITheme.label(body, { name = "Hint", size = UDim2.fromOffset(320, 18), role = "BodyS", font = "body", color = "TextMuted", text = S.CashOutHold })
	hint.LayoutOrder = 4
	;(cashBtn.root :: GuiButton).Activated:Connect(VictoryBanner.cashOut)
	;(keepBtn.root :: GuiButton).Activated:Connect(VictoryBanner.keepGoing)
	cashBtn.root.NextSelectionRight = keepBtn.root
	keepBtn.root.NextSelectionLeft = cashBtn.root

	-- Portal guide (after Cash out): chip under the timer, arrow + distance + team hold bar.
	guideGui = UITheme.screen("COHUE_CashOutGuide", 12, Enum.ScreenInsets.DeviceSafeInsets)
	guideGui.Enabled = false
	guideZone = UITheme.zone(guideGui, "Guide", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 96), UDim2.fromOffset(240, 60))
	local chip = UITheme.chip(guideZone, { Name = "Chip", Size = UDim2.fromOffset(0, 32), AutomaticSize = Enum.AutomaticSize.X, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0) })
	UITheme.paint(chip:WaitForChild("Ink"), "Color", "Premium")
	UITheme.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 10) }, chip)
	UITheme.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6) }, chip)
	guideArrow = UITheme.new("Frame", { Name = "Arrow", BackgroundTransparency = 1, Size = UDim2.fromOffset(22, 22), LayoutOrder = 1 }, chip)
	for i, x in { -4, 4 } do
		local bar = UITheme.new("Frame", { Size = UDim2.fromOffset(13, 5), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, x, 0.5, 0), Rotation = if i == 1 then -45 else 45, BorderSizePixel = 0 }, guideArrow)
		UITheme.paint(bar, "BackgroundColor3", "Premium")
		UITheme.corner(bar, 2)
	end
	guideText = UITheme.label(chip, { name = "Text", size = UDim2.new(0, 0, 1, 0), autoSize = Enum.AutomaticSize.X, role = "LabelS", outline = true })
	guideText.LayoutOrder = 2
	guideBar = UITheme.glossBar(guideZone, UDim2.fromOffset(180, 12), UDim2.new(0.5, -90, 0, 40), "Premium", "Hold")
	guideBar.frame.Visible = false

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not open then
			return
		end
		if input.KeyCode == V.CashOutKey then
			VictoryBanner.cashOut()
		elseif input.KeyCode == V.KeepGoingKey then
			VictoryBanner.keepGoing()
		end
	end)
	UITheme.changed:connect(function(reason: string)
		if reason == "device" then
			layout()
		elseif reason == "phase" then
			if not UITheme.inRun() then
				close()
				setGuide(false)
			end
		end
	end)
	layout()
end

return VictoryBanner
