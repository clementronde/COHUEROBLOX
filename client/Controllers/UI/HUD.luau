--!strict
-- Run HUD: vitals, level/XP, coins, timer, stage, boss arrow + bar, team, build, companion,
-- announcements (subtitles), downed/ghost overlay, ping feed. Design: docs/dossier/60-ui-ux.md section 3.
-- Listens: RunState, PlayerVitals, PlayerProgress, Coins, Build, CompanionState, BossState, Announce.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local UITheme = require(script.Parent:WaitForChild("UITheme"))

local Config = UITheme.Config
local S = UITheme.S
local M = Config.Margin

local HUD = {}

local LOCAL = Players.LocalPlayer

-- state ---------------------------------------------------------------------------------------
local run = {
	timeLeft = 600,
	stamp = 0,
	finalWave = 0,
	bossRevealed = false,
	bossPosition = nil :: Vector3?,
	worldId = "",
	tier = 1,
	stage = 1,
}
local bossSeenAt = -math.huge
local bossDefeated = false
local teamDowned: { [number]: boolean } = {}

-- instances (built in start) -------------------------------------------------------------------
local hudGui: ScreenGui
local topLeft: Frame
local topCenter: Frame
local bottomLeft: Frame
local buildBox: Frame
local hpBar: UITheme.Bar
local hpText: TextLabel
local shieldFill: Frame
local xpBar: UITheme.Bar
local levelText: TextLabel
local coinText: TextLabel
local companionText: TextLabel
local timerText: TextLabel
local timerScale: UIScale
local stageText: TextLabel
local arrowBox: Frame
local arrowHolder: Frame
local arrowDist: TextLabel
local bossBox: Frame
local bossName: TextLabel
local bossBar: UITheme.Bar
local bossPct: TextLabel
local bossPips: { Frame } = {}
local teamRows: { { frame: Frame, name: TextLabel, bar: UITheme.Bar, state: TextLabel } } = {}
local feedRows: { TextLabel } = {}
local weaponTiles: { Frame } = {}
local grimoireTiles: { Frame } = {}
local weaponsRow: Frame
local grimoiresRow: Frame
local downedGui: ScreenGui
local downedTitle: TextLabel
local downedHint: TextLabel
local reviveBar: UITheme.Bar
local vignetteGui: ScreenGui
local vignetteStroke: UIStroke
local vignetteTween: Tween?
local announceGui: ScreenGui
local announceBox: Frame
local announceText: TextLabel
local announceIcon: TextLabel

---------------------------------------------------------------------------- builders

local function listLayout(parent: Instance, horizontal: boolean, padding: number, align: Enum.HorizontalAlignment?)
	return UITheme.new("UIListLayout", {
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
	}, parent)
end

local function buildVitals(parent: Instance)
	local box = UITheme.panel(parent, { Name = "Vitals", Size = UDim2.fromOffset(212, 60), LayoutOrder = 1 })
	local badge = UITheme.new("Frame", { Name = "Level", Size = UDim2.fromOffset(36, 36), Position = UDim2.fromOffset(6, 6) }, box)
	UITheme.paint(badge, "BackgroundColor3", "Xp")
	UITheme.round(badge)
	UITheme.stroke(badge, 2, "Outline")
	levelText = UITheme.label(badge, { size = UDim2.fromScale(1, 1), role = "Title", font = "display", outline = true, text = "1" })
	UITheme.label(box, {
		size = UDim2.fromOffset(36, 14),
		position = UDim2.fromOffset(6, 43),
		role = "Tiny",
		color = "TextDim",
		text = S.Level,
	})
	hpBar = UITheme.bar(box, UDim2.fromOffset(158, 18), UDim2.fromOffset(48, 6), "Hp", "Hp")
	shieldFill = UITheme.new("Frame", {
		Name = "Shield",
		Size = UDim2.fromScale(0, 0.35),
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 2,
	}, hpBar.frame)
	UITheme.paint(shieldFill, "BackgroundColor3", "Shield")
	hpText = UITheme.label(hpBar.frame, { size = UDim2.fromScale(1, 1), role = "Small", outline = true, text = "", z = 3 })
	xpBar = UITheme.bar(box, UDim2.fromOffset(158, 7), UDim2.fromOffset(48, 28), "Xp", "Xp")
	local coin = UITheme.new("Frame", { Size = UDim2.fromOffset(12, 12), Position = UDim2.fromOffset(48, 41) }, box)
	UITheme.paint(coin, "BackgroundColor3", "Coin")
	UITheme.round(coin)
	UITheme.stroke(coin, 1, "Outline")
	coinText = UITheme.label(box, {
		size = UDim2.fromOffset(140, 16),
		position = UDim2.fromOffset(64, 39),
		role = "Small",
		align = Enum.TextXAlignment.Left,
		text = "0",
	})
end

local function makeTile(parent: Instance, size: number, order: number): Frame
	local tile = UITheme.icon(parent, "?", size, "Slot" .. order)
	tile.LayoutOrder = order
	local lvl = UITheme.label(tile, {
		name = "Lvl",
		size = UDim2.fromOffset(18, 14),
		position = UDim2.new(1, 2, 1, 2),
		anchor = Vector2.new(1, 1),
		role = "Tiny",
		font = "display",
		outline = true,
		z = 3,
	})
	lvl.Text = ""
	return tile
end

local function buildBuild(): Frame
	local box = UITheme.new("Frame", {
		Name = "Build",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(212, 62),
		LayoutOrder = 2,
	}, nil)
	listLayout(box, false, 4)
	weaponsRow = UITheme.new("Frame", { Name = "Weapons", BackgroundTransparency = 1, Size = UDim2.fromOffset(212, 32), LayoutOrder = 1 }, box)
	listLayout(weaponsRow, true, 4)
	grimoiresRow = UITheme.new("Frame", { Name = "Grimoires", BackgroundTransparency = 1, Size = UDim2.fromOffset(212, 24), LayoutOrder = 2 }, box)
	listLayout(grimoiresRow, true, 3)
	for i = 1, 6 do
		weaponTiles[i] = makeTile(weaponsRow, 30, i)
		weaponTiles[i].Visible = false
	end
	for i = 1, 8 do
		grimoireTiles[i] = makeTile(grimoiresRow, 22, i)
		grimoireTiles[i].Visible = false
	end
	return box
end

local function buildTeam(parent: Instance)
	local team = UITheme.new("Frame", {
		Name = "Team",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(212, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 4,
	}, parent)
	listLayout(team, false, 4)
	for i = 1, Config.Hud.TeamMax do
		local row = UITheme.panel(team, { Name = "Mate" .. i, Size = UDim2.fromOffset(170, 24), LayoutOrder = i, Visible = false })
		local name = UITheme.label(row, {
			size = UDim2.fromOffset(70, 24),
			position = UDim2.fromOffset(6, 0),
			role = "Small",
			align = Enum.TextXAlignment.Left,
		})
		local bar = UITheme.bar(row, UDim2.fromOffset(46, 6), UDim2.fromOffset(78, 9), "MapAlly")
		local state = UITheme.label(row, {
			size = UDim2.fromOffset(44, 24),
			position = UDim2.fromOffset(126, 0),
			role = "Tiny",
			color = "Warning",
			align = Enum.TextXAlignment.Left,
		})
		teamRows[i] = { frame = row, name = name, bar = bar, state = state }
	end
end

local function buildFeed(parent: Instance)
	local feed = UITheme.new("Frame", {
		Name = "Feed",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(212, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 5,
	}, parent)
	listLayout(feed, false, 2)
	for i = 1, Config.Hud.FeedMax do
		local l = UITheme.label(feed, {
			name = "Line" .. i,
			size = UDim2.fromOffset(212, 18),
			role = "Small",
			align = Enum.TextXAlignment.Left,
			outline = true,
		})
		l.LayoutOrder = i
		l.Visible = false
		feedRows[i] = l
	end
end

local function buildTopCenter(parent: Instance)
	topCenter = UITheme.zone(parent, "TopCenter", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, M), UDim2.fromOffset(300, 150))
	listLayout(topCenter, false, 2, Enum.HorizontalAlignment.Center)
	timerText = UITheme.label(topCenter, {
		name = "Timer",
		size = UDim2.fromOffset(220, 34),
		role = "Timer",
		font = "display",
		outline = true,
		text = "10:00",
	})
	timerText.LayoutOrder = 1
	timerScale = UITheme.new("UIScale", { Name = "UrgentScale" }, timerText)
	stageText = UITheme.label(topCenter, {
		name = "Stage",
		size = UDim2.fromOffset(300, 16),
		role = "Tiny",
		color = "TextDim",
		outline = true,
	})
	stageText.LayoutOrder = 2

	arrowBox = UITheme.new("Frame", { Name = "BossArrow", BackgroundTransparency = 1, Size = UDim2.fromOffset(80, 50), LayoutOrder = 3, Visible = false }, topCenter)
	arrowHolder = UITheme.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(36, 36),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
	}, arrowBox)
	for i, x in { -6, 6 } do
		local bar = UITheme.new("Frame", {
			Size = UDim2.fromOffset(20, 7),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, x, 0.5, 0),
			Rotation = if i == 1 then -45 else 45,
			BorderSizePixel = 0,
		}, arrowHolder)
		UITheme.paint(bar, "BackgroundColor3", "MapBoss")
		UITheme.stroke(bar, 1, "Outline")
		UITheme.corner(bar, 3)
	end
	arrowDist = UITheme.label(arrowBox, {
		size = UDim2.fromOffset(80, 14),
		position = UDim2.fromOffset(0, 36),
		role = "Tiny",
		outline = true,
	})

	bossBox = UITheme.new("Frame", { Name = "BossBar", BackgroundTransparency = 1, Size = UDim2.fromOffset(280, 38), LayoutOrder = 4, Visible = false }, topCenter)
	bossName = UITheme.label(bossBox, { size = UDim2.fromOffset(280, 18), role = "Body", outline = true })
	bossBar = UITheme.bar(bossBox, UDim2.fromOffset(280, 14), UDim2.fromOffset(0, 20), "Boss")
	bossPct = UITheme.label(bossBar.frame, { size = UDim2.fromScale(1, 1), role = "Tiny", outline = true, z = 3 })
	for i = 1, 4 do
		local pip = UITheme.new("Frame", {
			Size = UDim2.fromOffset(8, 8),
			Position = UDim2.new(1, -10 * i, 0, 5),
			Rotation = 45,
			BorderSizePixel = 0,
			Visible = false,
		}, bossBox)
		UITheme.paint(pip, "BackgroundColor3", "Boss")
		UITheme.stroke(pip, 1, "Outline")
		bossPips[i] = pip
	end
end

local function buildDowned()
	vignetteGui = UITheme.screen("COHUE_Vignette", 24, Enum.ScreenInsets.None)
	vignetteGui.Enabled = false
	local ring = UITheme.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -60, 1, -60),
	}, vignetteGui)
	vignetteStroke = UITheme.stroke(ring, 60, "Danger")
	vignetteStroke.Transparency = 0.6

	downedGui = UITheme.screen("COHUE_Downed", 25)
	downedGui.Enabled = false
	local zone = UITheme.zone(downedGui, "Center", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.42), UDim2.fromOffset(300, 100))
	local box = UITheme.panel(zone, { Size = UDim2.fromScale(1, 1) })
	downedTitle = UITheme.label(box, {
		size = UDim2.new(1, -16, 0, 34),
		position = UDim2.fromOffset(8, 6),
		role = "Big",
		font = "display",
		color = "Warning",
		outline = true,
	})
	downedHint = UITheme.label(box, {
		size = UDim2.new(1, -16, 0, 32),
		position = UDim2.fromOffset(8, 40),
		role = "Small",
		wrap = true,
	})
	reviveBar = UITheme.bar(box, UDim2.new(1, -32, 0, 10), UDim2.fromOffset(16, 80), "Revive")
end

local function buildAnnounce()
	announceGui = UITheme.screen("COHUE_Announce", 30)
	local zone = UITheme.zone(announceGui, "Banner", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 100), UDim2.fromOffset(520, 48))
	announceBox = UITheme.panel(zone, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(0, 44),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = false,
	})
	UITheme.new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, announceBox)
	listLayout(announceBox, true, 8).VerticalAlignment = Enum.VerticalAlignment.Center
	announceIcon = UITheme.label(announceBox, { size = UDim2.fromOffset(20, 40), role = "Big", font = "display", outline = true })
	announceIcon.LayoutOrder = 1
	announceText = UITheme.label(announceBox, {
		size = UDim2.fromOffset(0, 40),
		autoSize = Enum.AutomaticSize.X,
		role = "Big",
		font = "display",
		outline = true,
	})
	announceText.LayoutOrder = 2
	local limit = UITheme.new("UITextSizeConstraint", { MaxTextSize = 40, MinTextSize = 12 }, announceText)
	limit.Name = "Limit"
end

---------------------------------------------------------------------------- layout per device

local function layout()
	local device = UITheme.device()
	if device == "phone" then
		buildBox.Parent = topLeft
		buildBox.LayoutOrder = 3
	else
		buildBox.Parent = bottomLeft
	end
end

---------------------------------------------------------------------------- updates

local function setStageText()
	local world = UITheme.nameOf("Worlds", run.worldId)
	stageText.Text = UITheme.format(world)
		.. " · "
		.. UITheme.format(S.Tier, { n = run.tier })
		.. " · "
		.. UITheme.format(S.Stage, { n = run.stage })
end

local lastTimerText = ""
local urgent = false
local function updateTimer()
	local phase = UITheme.phase()
	local elapsed = os.clock() - run.stamp
	local text: string
	local isUrgent = false
	if phase == "FinalWave" then
		text = UITheme.format(S.FinalWave, { t = UITheme.clock(run.finalWave + elapsed) })
		UITheme.paint(timerText, "TextColor3", "Warning")
	else
		local left = math.max(0, run.timeLeft - elapsed)
		text = UITheme.clock(left)
		isUrgent = left < Config.Hud.UrgentSeconds and (phase == "Running" or phase == "Boss")
		UITheme.paint(timerText, "TextColor3", if isUrgent then "Danger" else "Text")
	end
	if isUrgent ~= urgent then
		urgent = isUrgent
		timerScale.Scale = if isUrgent then Config.TextSize.TimerUrgent / Config.TextSize.Timer else 1
		if isUrgent then
			UITheme.pop(timerText, 0.8)
		end
	end
	if text ~= lastTimerText then
		lastTimerText = text
		timerText.Text = text
	end
end

local arrowConn: RBXScriptConnection? = nil
local lastDist = -1
local function arrowStep()
	local camera = Workspace.CurrentCamera
	local target = run.bossPosition
	if not camera or not target then
		return
	end
	local rel = camera.CFrame:VectorToObjectSpace(target - camera.CFrame.Position)
	arrowHolder.Rotation = math.deg(math.atan2(rel.X, -rel.Z))
	local character = LOCAL.Character
	-- lihfolk-ignore: findfirstchild-chain (nil-checked below)
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local d = math.floor((target - root.Position).Magnitude)
		if d ~= lastDist then
			lastDist = d
			arrowDist.Text = UITheme.format(S.Distance, { n = d })
		end
	end
end

local function refreshArrow()
	local show = run.bossRevealed and run.bossPosition ~= nil and UITheme.inRun() and not bossDefeated
	arrowBox.Visible = show
	if show and not arrowConn then
		arrowConn = RunService.RenderStepped:Connect(arrowStep)
	elseif not show and arrowConn then
		arrowConn:Disconnect()
		arrowConn = nil
	end
end

local function onRunState(state: any)
	if type(state) ~= "table" then
		return
	end
	if type(state.timeLeft) == "number" then
		run.timeLeft = state.timeLeft
	end
	if type(state.finalWaveSeconds) == "number" then
		run.finalWave = state.finalWaveSeconds
	end
	run.stamp = os.clock()
	local stageChanged = state.worldId ~= run.worldId or state.tier ~= run.tier or state.stage ~= run.stage
	if type(state.worldId) == "string" then
		run.worldId = state.worldId
	end
	if type(state.tier) == "number" then
		run.tier = state.tier
	end
	-- A new run (Replay keeps stage 1) must also reset the boss bar (review finding 10).
	if state.phase == "Loadout" or (state.phase == "Running" and run.phase == "Ended") then
		bossDefeated = false
	end
	if type(state.stage) == "number" then
		if state.stage ~= run.stage then
			bossDefeated = false
		end
		run.stage = state.stage
	end
	if stageChanged then
		setStageText()
	end
	if state.phase == "BossDefeated" then
		bossDefeated = true
		bossBox.Visible = false
	end
	run.bossRevealed = state.bossRevealed == true
	run.bossPosition = if typeof(state.bossPosition) == "Vector3" then state.bossPosition else run.bossPosition
	if not run.bossRevealed then
		run.bossPosition = nil
	end
	updateTimer()
	refreshArrow()
end

local function onVitals(v: any)
	if type(v) ~= "table" then
		return
	end
	if type(v.team) == "table" then
		HUD.setTeam(v.team)
		-- RunManager sends own vitals and team in the same payload: only stop if there is no own hp.
		if v.hp == nil then
			return
		end
	end
	local hp = tonumber(v.hp) or 0
	local maxHp = math.max(1, tonumber(v.maxHp) or 1)
	local shield = tonumber(v.shield) or 0
	hpBar.set(hp / maxHp)
	local text = string.format("%d / %d", math.ceil(hp), math.ceil(maxHp))
	if hpText.Text ~= text then
		hpText.Text = text
	end
	shieldFill.Visible = shield > 0
	if shield > 0 then
		shieldFill.Size = UDim2.fromScale(math.clamp(shield / maxHp, 0, 1), 0.35)
	end

	local downed = v.downed == true
	local ghost = v.ghost == true
	downedGui.Enabled = (downed or ghost) and UITheme.inRun()
	vignetteGui.Enabled = downed and UITheme.inRun()
	if downed then
		local left = math.max(0, math.ceil(tonumber(v.downedTimeLeft) or 0))
		UITheme.setText(downedTitle, S.DownedTimer, { s = left })
		UITheme.setText(downedHint, S.DownedHint)
		reviveBar.frame.Visible = true
		reviveBar.set(tonumber(v.reviveProgress) or 0)
		if not vignetteTween and not UITheme.flashesReduced() then
			-- Slow breathing (0.4 Hz, far under the 3 Hz flash limit).
			local tween = TweenService:Create(
				vignetteStroke,
				TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Transparency = 0.8 }
			)
			tween:Play()
			vignetteTween = tween
		end
	else
		if vignetteTween then
			vignetteTween:Cancel()
			vignetteTween = nil
			vignetteStroke.Transparency = 0.6
		end
		if ghost then
			UITheme.setText(downedTitle, S.Ghost)
			UITheme.setText(downedHint, S.GhostHint)
			reviveBar.frame.Visible = false
		end
	end
end

local feedEntries: { { text: any, args: { [string]: any }?, at: number } } = {}

local function renderFeed()
	for i, row in feedRows do
		local entry = feedEntries[i]
		row.Visible = entry ~= nil
		if entry then
			UITheme.setText(row, entry.text, entry.args)
		end
	end
end

-- Add a line to the left feed (pings, teammate downed). Public: PingUI calls it.
function HUD.feed(text: any, args: { [string]: any }?)
	table.insert(feedEntries, 1, { text = text, args = args, at = os.clock() })
	while #feedEntries > Config.Hud.FeedMax do
		table.remove(feedEntries)
	end
	renderFeed()
	task.delay(Config.Hud.FeedSeconds, function()
		local now = os.clock()
		for i = #feedEntries, 1, -1 do
			if now - feedEntries[i].at >= Config.Hud.FeedSeconds - 0.05 then
				table.remove(feedEntries, i)
			end
		end
		renderFeed()
	end)
end

function HUD.setTeam(team: { [any]: any })
	local i = 0
	for key, info in team do
		local userId = tonumber(key)
		if userId and userId ~= LOCAL.UserId and type(info) == "table" and i < #teamRows then
			i += 1
			local row = teamRows[i]
			row.frame.Visible = true
			local player = Players:GetPlayerByUserId(userId)
			local name = if player then player.DisplayName else tostring(userId)
			if row.name.Text ~= name then
				row.name.Text = name
			end
			local maxHp = math.max(1, tonumber(info.maxHp) or 1)
			row.bar.set((tonumber(info.hp) or 0) / maxHp)
			local downed = info.downed == true
			if info.ghost == true then
				UITheme.setText(row.state, S.Ghost)
				UITheme.paint(row.state, "TextColor3", "TextDim")
			elseif downed then
				UITheme.setText(row.state, S.Downed)
				UITheme.paint(row.state, "TextColor3", "Warning")
			else
				UITheme.setText(row.state, "")
			end
			if downed and not teamDowned[userId] then
				HUD.feed(S.TeammateDowned, { name = name })
			end
			teamDowned[userId] = downed
		end
	end
	for j = i + 1, #teamRows do
		teamRows[j].frame.Visible = false
	end
end

local function fillTiles(tiles: { Frame }, list: any, slots: number, configName: string)
	local count = if type(list) == "table" then #list else 0
	local shown = math.max(slots, count)
	for i, tile in tiles do
		local entry = if type(list) == "table" then list[i] else nil
		tile.Visible = i <= shown
		-- lihfolk-ignore: findfirstchild-chain (both nil-checked below)
		local lvl = tile:FindFirstChild("Lvl") :: TextLabel?
		local letters = tile:FindFirstChild("Letters") :: TextLabel?
		if type(entry) == "table" and type(entry.id) == "string" then
			UITheme.setIcon(tile, UITheme.format(UITheme.nameOf(configName, entry.id)))
			tile.BackgroundTransparency = 0
			if lvl then
				lvl.Text = tostring(entry.level or 1)
			end
		else
			tile.BackgroundTransparency = 0.7
			tile.BackgroundColor3 = UITheme.color("PanelLight")
			if lvl then
				lvl.Text = ""
			end
			if letters then
				letters.Text = ""
			end
		end
	end
end

local function onBuild(b: any)
	if type(b) ~= "table" then
		return
	end
	fillTiles(weaponTiles, b.weapons, tonumber(b.weaponSlots) or 0, "Weapons")
	fillTiles(grimoireTiles, b.grimoires, tonumber(b.grimoireSlots) or 0, "Grimoires")
end

local function onProgress(p: any)
	if type(p) ~= "table" then
		return
	end
	local lvl = tostring(p.level or 1)
	if levelText.Text ~= lvl then
		levelText.Text = lvl
		UITheme.pop(levelText.Parent :: GuiObject)
	end
	local need = math.max(1, tonumber(p.xpNext) or 1)
	xpBar.set((tonumber(p.xp) or 0) / need)
end

local function onCoins(c: any)
	if type(c) == "table" and type(c.coins) == "number" then
		local text = UITheme.short(c.coins)
		if coinText.Text ~= text then
			coinText.Text = text
		end
	end
end

local companion: any = nil
local function renderCompanion()
	if type(companion) ~= "table" then
		companionText.Visible = false
		return
	end
	companionText.Visible = true
	local name = UITheme.format(companion.name or companion.line)
	local text = name .. " · " .. UITheme.format(S.LevelN, { n = companion.level or 1 })
	if companion.stunned then
		text ..= " (" .. UITheme.format(S.Stunned) .. ")"
	end
	companionText.Text = text
	UITheme.paint(companionText, "TextColor3", if companion.stunned then "TextDim" else "Text")
end

local function onBoss(b: any)
	if type(b) ~= "table" or bossDefeated then
		return
	end
	-- Despawn / defeat payloads carry no name or hp: hide instead of flashing a raw id at 0 %.
	if b.removed or b.defeated then
		bossBox.Visible = false
		return
	end
	bossSeenAt = os.clock()
	bossBox.Visible = UITheme.inRun()
	UITheme.setText(bossName, b.name or b.bossId or "")
	local frac = math.clamp(tonumber(b.hpFrac) or 0, 0, 1)
	bossBar.set(frac)
	bossPct.Text = string.format("%d%%", math.ceil(frac * 100))
	local phaseN = tonumber(b.phase) or 1
	for i, pip in bossPips do
		pip.Visible = i <= phaseN
	end
	if typeof(b.position) == "Vector3" then
		run.bossPosition = b.position
	end
end

-- Announcements: one at a time, queued (vault: HUD Design popup arbitration).
local queue: { any } = {}
local announcing = false
local function nextAnnounce()
	if announcing then
		return
	end
	local a = table.remove(queue, 1)
	if not a then
		announceBox.Visible = false
		return
	end
	announcing = true
	local kind = tostring(a.kind or "")
	local danger = kind == "Boss" or kind == "BossRevealed" or kind == "FinalWave"
	local info = kind == "Stage" or kind == "Portal"
	announceIcon.Visible = danger or info
	announceIcon.Text = if danger then "!" elseif info then "»" else ""
	UITheme.paint(announceIcon, "TextColor3", if danger then "Danger" else "Shield")
	UITheme.setText(announceText, a.text or "")
	announceBox.Visible = true
	UITheme.pop(announceBox, 0.9)
	local d = math.clamp(tonumber(a.duration) or 3, Config.Hud.AnnounceMin, Config.Hud.AnnounceMax)
	task.delay(d, function()
		announcing = false
		nextAnnounce()
	end)
end

local function onAnnounce(a: any)
	if type(a) ~= "table" then
		return
	end
	table.insert(queue, a)
	if #queue > 4 then
		table.remove(queue, 1)
	end
	nextAnnounce()
end

local function refreshVisibility()
	local inRun = UITheme.inRun()
	hudGui.Enabled = inRun
	announceGui.Enabled = inRun
	if not inRun then
		downedGui.Enabled = false
		vignetteGui.Enabled = false
	end
	refreshArrow()
end

---------------------------------------------------------------------------- lifecycle

function HUD.start()
	hudGui = UITheme.screen("COHUE_HUD", 10)
	topLeft = UITheme.zone(hudGui, "TopLeft", Vector2.zero, UDim2.fromOffset(M, M), UDim2.fromOffset(220, 320))
	listLayout(topLeft, false, 6)
	buildVitals(topLeft)
	companionText = UITheme.label(topLeft, {
		name = "Companion",
		size = UDim2.fromOffset(212, 16),
		role = "Small",
		align = Enum.TextXAlignment.Left,
		outline = true,
	})
	companionText.LayoutOrder = 2
	companionText.Visible = false
	buildTeam(topLeft)
	buildFeed(topLeft)
	bottomLeft = UITheme.zone(hudGui, "BottomLeft", Vector2.new(0, 1), UDim2.new(0, M, 1, -M), UDim2.fromOffset(220, 62))
	buildBox = buildBuild()
	-- Desktop/tablet tiles a bit larger.
	buildTopCenter(hudGui)
	buildDowned()
	buildAnnounce()
	layout()
	setStageText()
	refreshVisibility()

	UITheme.changed:connect(function(reason: string)
		if reason == "device" then
			layout()
		elseif reason == "phase" then
			refreshVisibility()
		elseif reason == "lang" then
			setStageText()
			renderCompanion()
			lastTimerText = ""
			updateTimer()
		end
	end)

	UITheme.watch("RunState", onRunState)
	UITheme.watch("PlayerVitals", onVitals)
	UITheme.watch("PlayerProgress", onProgress)
	UITheme.watch("Coins", onCoins)
	UITheme.watch("Build", onBuild)
	UITheme.watch("CompanionState", function(c)
		companion = c
		renderCompanion()
	end)
	UITheme.watch("BossState", onBoss)
	UITheme.watch("Announce", onAnnounce)

	-- 4 Hz: timer text (only rewritten when the second changes) and boss bar linger.
	local period = 1 / Config.Hud.TimerHz
	while true do
		task.wait(period)
		if UITheme.inRun() then
			updateTimer()
			if bossBox.Visible and os.clock() - bossSeenAt > Config.Hud.BossBarLinger then
				bossBox.Visible = false
			end
		end
	end
end

return HUD
