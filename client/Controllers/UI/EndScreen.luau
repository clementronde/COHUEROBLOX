--!strict
-- End of run v2 (Figma L09 / P09 / C09). Left: title, KO (very big), personal best, weekly rank.
-- Right: damage per weapon (sorted bars + value), rewards (Silver, capture, quest steps), then
-- Play again (the only green Go) and Lobby (only when a lobby remote exists). Portrait: one column.
-- Design: docs/dossier/60-ui-ux.md sections 0 and 10. Listens: RunSummary, phase. Sends: Replay().
-- Contract requests: RunSummary.weeklyRank (data), RunSummary.captured (companion), ReturnToLobby (data).

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Registry = require(Shared:WaitForChild("Registry"))
local UITheme = require(script.Parent:WaitForChild("UITheme"))

local S = UITheme.S

local EndScreen = {}

type Row = { frame: Frame, icon: Frame, name: TextLabel, bar: UITheme.Bar, value: TextLabel }
type Reward = { frame: Frame, text: TextLabel }

local scrimGui: ScreenGui
local gui: ScreenGui
local zone: Frame
local panel: Frame
local panelList: UIListLayout
local leftCol: Frame
local rightCol: Frame
local title: TextLabel
local subtitle: TextLabel
local koText: TextLabel
local bestText: TextLabel
local newBest: UITheme.Pill
local rankChip: Frame
local rankText: TextLabel
local damageHeader: TextLabel
local damageRows: { Row } = {}
local rewardsHeader: TextLabel
local rewards: { [string]: Reward } = {}
local playBtn: UITheme.Gloss
local lobbyBtn: UITheme.Gloss
local summary: any = nil
local replaySentAt = -math.huge

local MAX_ROWS = 6

local function list(parent: Instance, horizontal: boolean, padding: number, h: Enum.HorizontalAlignment?): UIListLayout
	return UITheme.new("UIListLayout", {
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = h or Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}, parent)
end

local function autoFrame(parent: Instance, name: string, order: number): Frame
	return UITheme.new("Frame", { Name = name, BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, LayoutOrder = order }, parent)
end

local function lobbyRemote(): RemoteEvent?
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local r = remotes and remotes:FindFirstChild("ReturnToLobby")
	return if r and r:IsA("RemoteEvent") then r else nil
end

local function makeRow(parent: Instance, order: number): Row
	local f = UITheme.new("Frame", { Name = "Row" .. order, BackgroundTransparency = 1, Size = UDim2.fromOffset(380, 26), LayoutOrder = order, Visible = false }, parent)
	list(f, true, 8)
	local icon = UITheme.icon(f, "?", 24, "Icon")
	icon.LayoutOrder = 1
	local name = UITheme.label(f, { name = "Name", size = UDim2.fromOffset(124, 26), role = "LabelS", align = Enum.TextXAlignment.Left })
	name.LayoutOrder = 2
	local holder = UITheme.new("Frame", { Name = "BarHolder", BackgroundTransparency = 1, Size = UDim2.fromOffset(160, 14), LayoutOrder = 3 }, f)
	local bar = UITheme.glossBar(holder, UDim2.fromOffset(160, 12), UDim2.fromOffset(0, 1), "Info")
	local value = UITheme.label(f, { name = "Value", size = UDim2.fromOffset(48, 26), role = "LabelS", color = "TextDim", align = Enum.TextXAlignment.Left })
	value.LayoutOrder = 4
	return { frame = f, icon = icon, name = name, bar = bar, value = value }
end

local function makeReward(parent: Instance, key: string, order: number, token: string)
	local chip = UITheme.chip(parent, { Name = key, Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = order, Visible = false })
	UITheme.paint(chip, "BackgroundColor3", "PanelLight")
	UITheme.back(chip, 0)
	UITheme.new("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 10) }, chip)
	list(chip, true, 5)
	local dot = UITheme.new("Frame", { Name = "Dot", Size = UDim2.fromOffset(16, 16), BorderSizePixel = 0, LayoutOrder = 1 }, chip)
	UITheme.paint(dot, "BackgroundColor3", token)
	UITheme.round(dot)
	UITheme.stroke(dot, 2, "Outline")
	local text = UITheme.label(chip, { name = "Text", size = UDim2.new(0, 0, 1, 0), autoSize = Enum.AutomaticSize.X, role = "LabelS" })
	text.LayoutOrder = 2
	rewards[key] = { frame = chip, text = text }
end

local function layout()
	local portrait = UITheme.isPortrait()
	panelList.FillDirection = if portrait then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal
	panelList.HorizontalAlignment = if portrait then Enum.HorizontalAlignment.Center else Enum.HorizontalAlignment.Left
	local leftList = leftCol:FindFirstChildOfClass("UIListLayout")
	if leftList then
		leftList.HorizontalAlignment = if portrait then Enum.HorizontalAlignment.Center else Enum.HorizontalAlignment.Left
	end
	for _, row in damageRows do
		row.frame.Size = UDim2.fromOffset(if portrait then 330 else 380, 26)
		local holder = row.bar.frame.Parent :: Frame
		holder.Size = UDim2.fromOffset(if portrait then 110 else 160, 14)
		row.bar.frame.Size = UDim2.fromOffset(if portrait then 110 else 160, 12)
	end
end

local function clockPlus(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d", s // 60, s % 60)
end

local function render()
	local s = summary
	if type(s) ~= "table" then
		return
	end
	UITheme.setText(title, if s.victory then S.Victory else S.Defeat)
	UITheme.paint(title, "TextColor3", if s.victory then "Legendary" else "Text")
	local world = tonumber(s.worldsCleared) or tonumber(s.stageReached) or 1
	local ot = tonumber(s.overtimeSeconds) or tonumber(s.finalWaveSeconds) or 0
	if ot > 0 then
		UITheme.setText(subtitle, S.EndSub, { w = world, t = clockPlus(ot), l = s.level or 1 })
	else
		UITheme.setText(subtitle, S.EndSubNoOvertime, { w = world, l = s.level or 1 })
	end

	local kills = tonumber(s.kills) or 0
	koText.Text = UITheme.short(kills)
	local profile = UITheme.profile()
	local best = tonumber(s.bestKills) or (if profile then tonumber(profile.bestKills) else nil)
	local isNew = s.newBest == true or (best ~= nil and best > 0 and kills > best)
	newBest.frame.Visible = isNew
	bestText.Visible = not isNew
	if best then
		UITheme.setText(bestText, S.Best, { n = UITheme.short(best) })
	else
		UITheme.setText(bestText, S.BestUnknown)
	end
	local rank = tonumber(s.weeklyRank)
	rankChip.Visible = rank ~= nil
	if rank then
		rankText.Text = "#" .. tostring(rank)
	end

	-- Damage per weapon, sorted.
	local entries = {}
	if type(s.damageByWeapon) == "table" then
		for id, dmg in s.damageByWeapon do
			local n = tonumber(dmg)
			if n and n > 0 then
				table.insert(entries, { id = tostring(id), dmg = n })
			end
		end
	end
	table.sort(entries, function(a, b)
		if a.dmg ~= b.dmg then
			return a.dmg > b.dmg
		end
		return a.id < b.id
	end)
	local maxDmg = if entries[1] then entries[1].dmg else 1
	damageHeader.Visible = #entries > 0
	for i, row in damageRows do
		local e = entries[i]
		row.frame.Visible = e ~= nil
		if e then
			local name = UITheme.nameOf("Weapons", e.id)
			UITheme.setText(row.name, name)
			UITheme.setIcon(row.icon, UITheme.format(name))
			row.value.Text = UITheme.short(e.dmg)
			row.bar.set(e.dmg / maxDmg)
		end
	end

	local silver = tonumber(s.silverEarned)
	rewards.Silver.frame.Visible = silver ~= nil and silver > 0
	if silver then
		UITheme.setText(rewards.Silver.text, S.Silver, { n = UITheme.short(silver) })
	end
	local captured = s.captured
	rewards.Captured.frame.Visible = captured ~= nil
	if captured ~= nil then
		local capName = if type(captured) == "table" and captured.name ~= nil then captured.name else captured
		UITheme.setText(rewards.Captured.text, S.CaptureJoins, { name = UITheme.format(capName) })
	end
	local quests = if type(s.questsProgressed) == "table" then #s.questsProgressed else 0
	rewards.Quests.frame.Visible = quests > 0
	UITheme.setText(rewards.Quests.text, S.QuestSteps, { n = quests })
	rewardsHeader.Visible = rewards.Silver.frame.Visible or rewards.Captured.frame.Visible or rewards.Quests.frame.Visible
	lobbyBtn.root.Visible = lobbyRemote() ~= nil
end

local function setOpen(open: boolean)
	gui.Enabled = open
	scrimGui.Enabled = open
	local ic = Registry.find("InputController")
	if ic and type(ic.setEnabled) == "function" then
		ic.setEnabled(not open and UITheme.phase() ~= "Loadout")
	end
	if open then
		playBtn.setEnabled(true)
		UITheme.pop(panel, 0.9)
		if UserInputService.PreferredInput == Enum.PreferredInput.Gamepad then
			GuiService.SelectedObject = playBtn.root
		end
	elseif GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
		GuiService.SelectedObject = nil
	end
end

local function replay()
	if not gui.Enabled or os.clock() - replaySentAt < 1 then
		return
	end
	replaySentAt = os.clock()
	playBtn.setEnabled(false)
	Net.event("Replay"):FireServer()
	task.delay(1, function()
		playBtn.setEnabled(true)
	end)
end

local function lobby()
	local r = lobbyRemote()
	if gui.Enabled and r then
		r:FireServer()
	end
end

function EndScreen.start()
	scrimGui = UITheme.screen("COHUE_EndScrim", 49, Enum.ScreenInsets.None)
	scrimGui.Enabled = false
	local scrim = UITheme.new("Frame", { Name = "Scrim", Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, BackgroundTransparency = 0.3 }, scrimGui)
	UITheme.paint(scrim, "BackgroundColor3", "Outline")

	gui = UITheme.screen("COHUE_End", 50, Enum.ScreenInsets.DeviceSafeInsets)
	gui.Enabled = false
	zone = UITheme.zone(gui, "End", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(720, 330))
	panel = UITheme.popup(zone, { Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY })
	UITheme.new("UIPadding", { PaddingLeft = UDim.new(0, 22), PaddingRight = UDim.new(0, 22), PaddingTop = UDim.new(0, 18), PaddingBottom = UDim.new(0, 18) }, panel)
	UITheme.new("UIScale", { Name = "PopScale" }, panel)
	panelList = list(panel, true, 24)
	panelList.VerticalAlignment = Enum.VerticalAlignment.Top

	-- Left: result
	leftCol = autoFrame(panel, "Summary", 1)
	list(leftCol, false, 6).VerticalAlignment = Enum.VerticalAlignment.Top
	title = UITheme.label(leftCol, { name = "Title", size = UDim2.new(0, 0, 0, 34), autoSize = Enum.AutomaticSize.X, role = "NumberL", font = "number", outline = true })
	title.LayoutOrder = 1
	subtitle = UITheme.label(leftCol, { name = "Sub", size = UDim2.new(0, 0, 0, 18), autoSize = Enum.AutomaticSize.X, role = "BodyS", font = "body", color = "TextMuted" })
	subtitle.LayoutOrder = 2
	local koRow = autoFrame(leftCol, "Ko", 3)
	list(koRow, true, 8)
	UITheme.koIcon(koRow, 44).LayoutOrder = 1
	koText = UITheme.label(koRow, { name = "Count", size = UDim2.new(0, 0, 0, 46), autoSize = Enum.AutomaticSize.X, role = "NumberXL", font = "number", outline = true })
	koText.LayoutOrder = 2
	local ko = UITheme.label(koRow, { name = "Suffix", size = UDim2.new(0, 0, 0, 46), autoSize = Enum.AutomaticSize.X, role = "TitleM", color = "Ko", outline = true, text = S.Ko })
	ko.LayoutOrder = 3
	local bestRow = autoFrame(leftCol, "Best", 4)
	list(bestRow, true, 6)
	bestText = UITheme.label(bestRow, { name = "BestText", size = UDim2.new(0, 0, 0, 20), autoSize = Enum.AutomaticSize.X, role = "LabelM", color = "CoinLight", outline = true })
	newBest = UITheme.pill(bestRow, { name = "NewBest", tone = "Premium", textColor = "OnLight", text = S.NewBest })
	rankChip = UITheme.new("Frame", { Name = "Rank", Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 5, BorderSizePixel = 0, Visible = false }, leftCol)
	UITheme.paint(rankChip, "BackgroundColor3", "PanelSunken")
	UITheme.back(rankChip, 0.2)
	UITheme.corner(rankChip, 14)
	UITheme.new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 12) }, rankChip)
	list(rankChip, true, 8)
	rankText = UITheme.label(rankChip, { name = "Rank", size = UDim2.new(0, 0, 1, 0), autoSize = Enum.AutomaticSize.X, role = "NumberM", font = "number", color = "Legendary", outline = true })
	rankText.LayoutOrder = 1
	local rankCol = autoFrame(rankChip, "Caption", 2)
	list(rankCol, false, 0)
	UITheme.label(rankCol, { name = "Week", size = UDim2.new(0, 0, 0, 16), autoSize = Enum.AutomaticSize.X, role = "LabelS", text = S.RankWeek, align = Enum.TextXAlignment.Left }).LayoutOrder = 1
	UITheme.label(rankCol, { name = "Reset", size = UDim2.new(0, 0, 0, 16), autoSize = Enum.AutomaticSize.X, role = "BodyS", font = "body", color = "TextMuted", text = S.RankReset, align = Enum.TextXAlignment.Left }).LayoutOrder = 2

	-- Right: details
	rightCol = autoFrame(panel, "Details", 2)
	list(rightCol, false, 7).VerticalAlignment = Enum.VerticalAlignment.Top
	damageHeader = UITheme.label(rightCol, { name = "DamageHeader", size = UDim2.new(0, 0, 0, 16), autoSize = Enum.AutomaticSize.X, role = "LabelS", color = "TextMuted", text = S.DamageByWeapon, align = Enum.TextXAlignment.Left })
	damageHeader.LayoutOrder = 0
	for i = 1, MAX_ROWS do
		damageRows[i] = makeRow(rightCol, i)
	end
	rewardsHeader = UITheme.label(rightCol, { name = "RewardsHeader", size = UDim2.new(0, 0, 0, 16), autoSize = Enum.AutomaticSize.X, role = "LabelS", color = "TextMuted", text = S.Rewards, align = Enum.TextXAlignment.Left })
	rewardsHeader.LayoutOrder = 20
	local rewardRow = UITheme.new("Frame", { Name = "Rewards", BackgroundTransparency = 1, Size = UDim2.fromOffset(380, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 21 }, rightCol)
	local rl = list(rewardRow, true, 6)
	rl.Wraps = true
	makeReward(rewardRow, "Silver", 1, "Coin")
	makeReward(rewardRow, "Captured", 2, "Capture")
	makeReward(rewardRow, "Quests", 3, "Xp")
	local actionsRow = autoFrame(rightCol, "Actions", 30)
	list(actionsRow, true, 10)
	playBtn = UITheme.glossy(actionsRow, { name = "PlayAgain", button = true, role = "Primary", size = UDim2.fromOffset(200, 58), radius = 16, lip = 6, text = S.Replay, textRole = "TitleL" })
	playBtn.root.LayoutOrder = 1
	lobbyBtn = UITheme.glossy(actionsRow, { name = "Lobby", button = true, role = "Neutral", size = UDim2.fromOffset(110, 46), radius = 13, lip = 5, text = S.Lobby, textRole = "TitleM" })
	lobbyBtn.root.LayoutOrder = 2
	;(playBtn.root :: GuiButton).Activated:Connect(replay)
	;(lobbyBtn.root :: GuiButton).Activated:Connect(lobby)
	playBtn.root.NextSelectionRight = lobbyBtn.root
	lobbyBtn.root.NextSelectionLeft = playBtn.root

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not gui.Enabled then
			return
		end
		if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
			replay()
		elseif input.KeyCode == Enum.KeyCode.L then
			lobby() -- not Escape: Roblox keeps it for its own menu
		end
	end)

	layout()
	UITheme.watch("RunSummary", function(s)
		if type(s) ~= "table" then
			return
		end
		summary = s
		layout()
		render()
		setOpen(true)
	end)
	UITheme.changed:connect(function(reason: string)
		if reason == "phase" then
			local phase = UITheme.phase()
			if gui.Enabled and (phase == "Loadout" or phase == "Running") then
				setOpen(false)
			end
		elseif (reason == "lang" or reason == "profile") and gui.Enabled then
			render()
		elseif reason == "device" then
			layout()
		end
	end)
end

return EndScreen
