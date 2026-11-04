--!strict
-- Run HUD v2 ("Toy-block gloss", Figma screens L01-L11 / P01-P11 / C01-C11, validated 4 Nov 2026):
-- vitals (level, HP + shield extension, XP, coins), build (4 weapons + 4 Runes), team, ping feed,
-- run timer that turns into the red Overtime stopwatch, KO counter + personal best, boss arrow and
-- bar, announcements (subtitles), downed / ghost overlay. Also starts VictoryBanner and CaptureUI.
-- Design: docs/dossier/60-ui-ux.md section 0 (+ sections 3 and 14 for the update rules).
-- Listens: RunState (v2 fields overtime*, worldIndex/worldCount, victory), PlayerVitals,
-- PlayerProgress (level, xp, kills), Coins, Build, CompanionState, BossState, Announce, Profile.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local UITheme = require(script.Parent:WaitForChild("UITheme"))
local VictoryBanner = require(script.Parent:WaitForChild("VictoryBanner"))
local CaptureUI = require(script.Parent:WaitForChild("CaptureUI"))

local Config = UITheme.Config
local S = UITheme.S
local M = Config.Margin

local HUD = {}

local LOCAL = Players.LocalPlayer

-- state ---------------------------------------------------------------------------------------
local run = {
	phase = "",
	timeLeft = 600,
	stamp = 0,
	overtime = false,
	overtimeSeconds = 0,
	overtimeStep = nil :: number?,
	worldIndex = nil :: number?,
	worldCount = nil :: number?,
	bossRevealed = false,
	bossPosition = nil :: Vector3?,
	worldId = "",
	tier = 1,
	stage = 1,
}
local bossSeenAt = -math.huge
local bossDefeated = false
local teamDowned: { [number]: boolean } = {}
local kills = 0
local bestKills: number? = nil
local newBestShown = false

type Slot = { frame: Frame, icon: Frame, level: UITheme.Pill }
type TeamRow = { frame: Frame, avatar: TextLabel, name: TextLabel, bar: UITheme.Bar, state: UITheme.Pill }

-- instances (built in start) -------------------------------------------------------------------
local hudGui: ScreenGui
local topGui: ScreenGui
local leftZone: Frame
local bottomLeft: Frame
local timerZone: Frame
local koZone: Frame
local buildBox: Frame
local teamBox: Frame
local feedBox: Frame
local levelText: TextLabel
local levelBadge: GuiObject
local hpFill: Frame
local shieldFill: Frame
local hpText: TextLabel
local shieldText: TextLabel
local xpBar: UITheme.Bar
local coinText: TextLabel
local companionText: TextLabel
local timerChip: Frame
local timerStroke: UIStroke
local timerText: TextLabel
local clockIcon: Frame
local stopwatchIcon: Frame
local worldText: TextLabel
local overtimePill: UITheme.Pill
local dangerPill: UITheme.Pill
local koText: TextLabel
local bestText: TextLabel
local newBestPill: UITheme.Pill
local arrowBox: Frame
local arrowHolder: Frame
local arrowDist: TextLabel
local bossBox: Frame
local bossName: TextLabel
local bossBar: UITheme.Bar
local bossPct: TextLabel
local bossPips: { Frame } = {}
local teamRows: { TeamRow } = {}
local feedRows: { { frame: Frame, dot: Frame, text: TextLabel } } = {}
local weaponSlots: { Slot } = {}
local runeSlots: { Slot } = {}
local downedGui: ScreenGui
local downedPanel: Frame
local downedTitle: TextLabel
local downedSeconds: TextLabel
local downedSecondsCaption: TextLabel
local downedHint: TextLabel
local reviveText: TextLabel
local reviveBar: UITheme.Bar
local ghostPill: UITheme.Pill
local downedPanelStroke: UIStroke
local vignetteGui: ScreenGui
local vignetteStroke: UIStroke
local vignetteTween: Tween?
local announceGui: ScreenGui
local announceZone: Frame
local announceSlab: UITheme.Gloss
local announceText: TextLabel

local VITALS_W = 240

---------------------------------------------------------------------------- small helpers

local function list(parent: Instance, horizontal: boolean, padding: number, align: Enum.HorizontalAlignment?): UIListLayout
	return UITheme.new("UIListLayout", {
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}, parent)
end

local function holder(parent: Instance?, name: string, size: UDim2, order: number?): Frame
	return UITheme.new("Frame", {
		Name = name,
		Size = size,
		BackgroundTransparency = 1,
		LayoutOrder = order or 0,
	}, parent)
end

local function minimapSize(): number
	return (Config.Minimap.Size :: any)[UITheme.device()] or 120
end

local function worldsPerRun(): number
	local runCfg = UITheme.config("Run")
	return if runCfg and type(runCfg.WorldsPerRun) == "number" then runCfg.WorldsPerRun else 3
end

---------------------------------------------------------------------------- builders

local function buildVitals(parent: Instance)
	local box = holder(parent, "Vitals", UDim2.fromOffset(VITALS_W, 70), 1)
	-- Level badge: glossy aqua slab (XP family), "LV" over the number.
	local badge = UITheme.glossy(box, { name = "Level", role = "Xp", size = UDim2.fromOffset(42, 46), radius = 11, lip = 5, position = UDim2.fromOffset(0, 2) })
	levelBadge = badge.root
	UITheme.label(badge.content, {
		name = "LV",
		size = UDim2.new(1, 0, 0, 14),
		position = UDim2.fromOffset(0, 1),
		role = "LabelS",
		color = "OnLight",
		text = S.Level,
	})
	levelText = UITheme.label(badge.content, {
		name = "Number",
		size = UDim2.new(1, 0, 0, 24),
		position = UDim2.fromOffset(0, 14),
		role = "NumberM",
		font = "number",
		outline = true,
		text = "1",
	})
	UITheme.heartIcon(box, 30).Position = UDim2.fromOffset(44, 1)
	-- HP track with the shield as a silver extension after the red fill.
	local track = UITheme.new("Frame", { Name = "Hp", Size = UDim2.fromOffset(180, 20), Position = UDim2.fromOffset(60, 6), BorderSizePixel = 0, ZIndex = 0 }, box)
	UITheme.paint(track, "BackgroundColor3", "PanelSunken")
	UITheme.back(track, 0.15)
	UITheme.round(track)
	UITheme.stroke(track, 2.5, "Outline")
	hpFill = UITheme.new("Frame", { Name = "Fill", Size = UDim2.fromScale(1, 1), BorderSizePixel = 0 }, track)
	UITheme.paint(hpFill, "BackgroundColor3", "Hp")
	UITheme.round(hpFill)
	local band = UITheme.new("Frame", { Name = "Band", Position = UDim2.fromOffset(3, 2), Size = UDim2.new(1, -6, 0.32, 0), BorderSizePixel = 0, BackgroundTransparency = 0.55 }, hpFill)
	UITheme.paint(band, "BackgroundColor3", "Shine")
	UITheme.round(band)
	shieldFill = UITheme.new("Frame", { Name = "Shield", Size = UDim2.fromScale(0, 1), BorderSizePixel = 0, Visible = false }, track)
	UITheme.paint(shieldFill, "BackgroundColor3", "Shield")
	UITheme.round(shieldFill)
	hpText = UITheme.label(track, { name = "Value", size = UDim2.new(1, -40, 1, 0), position = UDim2.fromOffset(22, 0), role = "LabelM", outline = true, text = "", z = 3 })
	shieldText = UITheme.label(track, {
		name = "ShieldValue",
		size = UDim2.fromOffset(40, 20),
		position = UDim2.new(1, -4, 0, 0),
		anchor = Vector2.new(1, 0),
		role = "LabelS",
		color = "Shield",
		align = Enum.TextXAlignment.Right,
		outline = true,
		text = "",
		z = 3,
	})
	xpBar = UITheme.glossBar(box, UDim2.fromOffset(180, 10), UDim2.fromOffset(60, 33), "Xp", "Xp")
	-- Coins
	local coin = UITheme.new("Frame", { Name = "Coin", Size = UDim2.fromOffset(16, 16), Position = UDim2.fromOffset(62, 49), BorderSizePixel = 0 }, box)
	UITheme.paint(coin, "BackgroundColor3", "Coin")
	UITheme.round(coin)
	UITheme.stroke(coin, 2, "Outline")
	local coinCore = UITheme.new("Frame", { Size = UDim2.fromOffset(6, 6), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BorderSizePixel = 0 }, coin)
	UITheme.paint(coinCore, "BackgroundColor3", "CoinLight")
	coinText = UITheme.label(box, {
		name = "Coins",
		size = UDim2.fromOffset(150, 20),
		position = UDim2.fromOffset(84, 47),
		role = "LabelM",
		color = "CoinLight",
		align = Enum.TextXAlignment.Left,
		outline = true,
		text = "0",
	})
end

local function makeSlot(parent: Instance, size: number, order: number): Slot
	local frame = UITheme.new("Frame", { Name = "Slot" .. order, Size = UDim2.fromOffset(size, size), LayoutOrder = order, BorderSizePixel = 0 }, parent)
	UITheme.paint(frame, "BackgroundColor3", "PanelLight")
	UITheme.back(frame, 0.05)
	UITheme.corner(frame, if size >= 40 then 11 else 9)
	UITheme.stroke(frame, 2.5, "Outline").Name = "Ink"
	local band = UITheme.new("Frame", { Name = "Band", Position = UDim2.fromOffset(3, 3), Size = UDim2.new(1, -6, 0.36, 0), BorderSizePixel = 0 }, frame)
	UITheme.paint(band, "BackgroundColor3", "Highlight")
	UITheme.corner(band, 6)
	local iconSize = math.round(size * 0.72)
	local icon = UITheme.icon(frame, "?", iconSize, "Icon")
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	local level = UITheme.pill(frame, { name = "Level", tone = "Premium", textColor = "OnLight", text = "" })
	level.frame.AnchorPoint = Vector2.new(1, 1)
	level.frame.Position = UDim2.new(1, 5, 1, 5)
	level.frame.Size = UDim2.fromOffset(0, 18)
	level.frame.ZIndex = 4
	local pad = level.frame:FindFirstChildOfClass("UIPadding")
	if pad then
		pad.PaddingLeft = UDim.new(0, 5)
		pad.PaddingRight = UDim.new(0, 5)
	end
	return { frame = frame, icon = icon, level = level }
end

local function buildBuild(): Frame
	local box = holder(nil, "Build", UDim2.fromOffset(VITALS_W, 92), 3)
	list(box, false, 7).VerticalAlignment = Enum.VerticalAlignment.Top
	local weaponsRow = holder(box, "Weapons", UDim2.fromOffset(VITALS_W, 46), 1)
	list(weaponsRow, true, 7)
	local runesRow = holder(box, "Runes", UDim2.fromOffset(VITALS_W, 36), 2)
	list(runesRow, true, 7)
	for i = 1, 6 do
		weaponSlots[i] = makeSlot(weaponsRow, 44, i)
		weaponSlots[i].frame.Visible = false
	end
	for i = 1, 6 do
		runeSlots[i] = makeSlot(runesRow, 34, i)
		runeSlots[i].frame.Visible = false
	end
	return box
end

local function buildTeam(parent: Instance)
	teamBox = holder(parent, "Team", UDim2.fromOffset(VITALS_W, 0), 4)
	teamBox.AutomaticSize = Enum.AutomaticSize.Y
	list(teamBox, false, 4).VerticalAlignment = Enum.VerticalAlignment.Top
	for i = 1, Config.Hud.TeamMax do
		local row = UITheme.chip(teamBox, { Name = "Mate" .. i, Size = UDim2.fromOffset(176, 28), LayoutOrder = i, Visible = false })
		UITheme.back(row, 0.25)
		local avatar = UITheme.label(row, {
			name = "Avatar",
			size = UDim2.fromOffset(20, 20),
			position = UDim2.fromOffset(4, 4),
			role = "LabelS",
			color = "OnLight",
		})
		avatar.BackgroundTransparency = 0
		UITheme.paint(avatar, "BackgroundColor3", "MapAlly")
		UITheme.corner(avatar, 6)
		local name = UITheme.label(row, {
			name = "Name",
			size = UDim2.fromOffset(60, 28),
			position = UDim2.fromOffset(30, 0),
			role = "LabelS",
			align = Enum.TextXAlignment.Left,
			outline = true,
		})
		local bar = UITheme.glossBar(row, UDim2.fromOffset(76, 10), UDim2.fromOffset(94, 9), "Hp")
		local state = UITheme.pill(row, { name = "State", tone = "Downed", text = "" })
		state.frame.Position = UDim2.fromOffset(92, 3)
		state.frame.Visible = false
		teamRows[i] = { frame = row, avatar = avatar, name = name, bar = bar, state = state }
	end
end

local function buildFeed(parent: Instance)
	feedBox = holder(parent, "Feed", UDim2.fromOffset(VITALS_W, 0), 5)
	feedBox.AutomaticSize = Enum.AutomaticSize.Y
	list(feedBox, false, 4).VerticalAlignment = Enum.VerticalAlignment.Top
	for i = 1, Config.Hud.FeedMax do
		local row = UITheme.chip(feedBox, { Name = "Line" .. i, Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = i, Visible = false })
		UITheme.back(row, 0.3)
		UITheme.new("UIPadding", { PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 10) }, row)
		list(row, true, 6)
		local dot = UITheme.new("Frame", { Name = "Dot", Size = UDim2.fromOffset(18, 18), BorderSizePixel = 0, LayoutOrder = 1 }, row)
		UITheme.round(dot)
		UITheme.stroke(dot, 2, "Outline")
		UITheme.paint(dot, "BackgroundColor3", "PingRegroup")
		local text = UITheme.label(row, { name = "Text", size = UDim2.new(0, 0, 1, 0), autoSize = Enum.AutomaticSize.X, role = "LabelS", align = Enum.TextXAlignment.Left })
		text.LayoutOrder = 2
		feedRows[i] = { frame = row, dot = dot, text = text }
	end
end

local function buildTimer(parent: Instance)
	timerZone = UITheme.zone(parent, "Timer", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 4), UDim2.fromOffset(260, 160))
	list(timerZone, false, 4, Enum.HorizontalAlignment.Center).VerticalAlignment = Enum.VerticalAlignment.Top
	timerChip = UITheme.chip(timerZone, { Name = "Chip", Size = UDim2.fromOffset(0, 46), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 1 })
	timerStroke = timerChip:WaitForChild("Ink") :: UIStroke
	UITheme.new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 12) }, timerChip)
	list(timerChip, true, 6)
	clockIcon = UITheme.clockIcon(timerChip, 28, false)
	clockIcon.LayoutOrder = 1
	stopwatchIcon = UITheme.clockIcon(timerChip, 28, true)
	stopwatchIcon.LayoutOrder = 1
	stopwatchIcon.Visible = false
	timerText = UITheme.label(timerChip, { name = "Time", size = UDim2.new(0, 0, 1, 0), autoSize = Enum.AutomaticSize.X, role = "NumberL", font = "number", outline = true, text = "10:00" })
	timerText.LayoutOrder = 2
	UITheme.new("UIScale", { Name = "PopScale" }, timerChip)

	local caption = holder(timerZone, "Caption", UDim2.fromOffset(0, 22), 2)
	caption.AutomaticSize = Enum.AutomaticSize.X
	list(caption, true, 4)
	worldText = UITheme.label(caption, { name = "World", size = UDim2.new(0, 0, 1, 0), autoSize = Enum.AutomaticSize.X, role = "LabelS", color = "TextDim", outline = true })
	worldText.LayoutOrder = 1
	overtimePill = UITheme.pill(caption, { name = "Overtime", tone = "Danger", text = S.Overtime })
	overtimePill.frame.LayoutOrder = 2
	overtimePill.frame.Visible = false
	dangerPill = UITheme.pill(caption, { name = "DangerStep", tone = "Ko", text = S.Danger, args = { n = 1 } })
	dangerPill.frame.LayoutOrder = 3
	dangerPill.frame.Visible = false

	-- Boss arrow: red-rimmed chip, a chevron that turns toward the boss, distance.
	arrowBox = UITheme.chip(timerZone, { Name = "BossArrow", Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 3, Visible = false })
	local ink = arrowBox:WaitForChild("Ink") :: UIStroke
	UITheme.paint(ink, "Color", "MapBoss")
	UITheme.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 10) }, arrowBox)
	list(arrowBox, true, 6)
	arrowHolder = holder(arrowBox, "Arrow", UDim2.fromOffset(22, 22), 1)
	for i, x in { -4, 4 } do
		local bar = UITheme.new("Frame", {
			Size = UDim2.fromOffset(13, 5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, x, 0.5, 0),
			Rotation = if i == 1 then -45 else 45,
			BorderSizePixel = 0,
		}, arrowHolder)
		UITheme.paint(bar, "BackgroundColor3", "MapBoss")
		UITheme.corner(bar, 2)
	end
	arrowDist = UITheme.label(arrowBox, { name = "Distance", size = UDim2.new(0, 0, 1, 0), autoSize = Enum.AutomaticSize.X, role = "LabelS", outline = true })
	arrowDist.LayoutOrder = 2

	bossBox = holder(timerZone, "BossBar", UDim2.fromOffset(260, 40), 4)
	bossBox.Visible = false
	bossName = UITheme.label(bossBox, { name = "Name", size = UDim2.fromOffset(260, 18), role = "LabelM", outline = true })
	bossBar = UITheme.glossBar(bossBox, UDim2.fromOffset(260, 16), UDim2.fromOffset(0, 21), "Boss")
	bossPct = UITheme.label(bossBar.frame, { name = "Pct", size = UDim2.fromScale(1, 1), role = "LabelS", outline = true, z = 3 })
	for i = 1, 4 do
		local pip = UITheme.new("Frame", {
			Size = UDim2.fromOffset(8, 8),
			Position = UDim2.new(1, -10 * i, 0, 5),
			Rotation = 45,
			BorderSizePixel = 0,
			Visible = false,
		}, bossBox)
		UITheme.paint(pip, "BackgroundColor3", "Hp")
		UITheme.stroke(pip, 1.5, "Outline")
		bossPips[i] = pip
	end
end

local function buildKo(parent: Instance)
	koZone = UITheme.zone(parent, "Ko", Vector2.new(1, 0), UDim2.new(1, -M, 0, 4), UDim2.fromOffset(200, 76))
	list(koZone, false, 3, Enum.HorizontalAlignment.Right).VerticalAlignment = Enum.VerticalAlignment.Top
	local chip = UITheme.chip(koZone, { Name = "Chip", Size = UDim2.fromOffset(0, 46), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 1 })
	UITheme.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 12) }, chip)
	list(chip, true, 6)
	UITheme.koIcon(chip, 34).LayoutOrder = 1
	koText = UITheme.label(chip, { name = "Count", size = UDim2.new(0, 0, 1, 0), autoSize = Enum.AutomaticSize.X, role = "NumberL", font = "number", outline = true, text = "0" })
	koText.LayoutOrder = 2
	local suffix = UITheme.label(chip, { name = "Suffix", size = UDim2.new(0, 0, 1, 0), autoSize = Enum.AutomaticSize.X, role = "LabelM", color = "Ko", outline = true, text = S.Ko })
	suffix.LayoutOrder = 3
	UITheme.new("UIScale", { Name = "PopScale" }, chip)
	local best = holder(koZone, "Best", UDim2.fromOffset(0, 22), 2)
	best.AutomaticSize = Enum.AutomaticSize.X
	list(best, true, 4)
	bestText = UITheme.label(best, { name = "BestText", size = UDim2.new(0, 0, 1, 0), autoSize = Enum.AutomaticSize.X, role = "LabelS", color = "CoinLight", outline = true, text = S.BestUnknown })
	newBestPill = UITheme.pill(best, { name = "NewBest", tone = "Premium", textColor = "OnLight", text = S.NewBest })
	newBestPill.frame.Visible = false
end

local function buildDowned()
	-- Under the HUD (DisplayOrder 9 < 10) so the vitals stay readable (Figma L10).
	vignetteGui = UITheme.screen("COHUE_Vignette", 9, Enum.ScreenInsets.None)
	vignetteGui.Enabled = false
	local ring = UITheme.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -40, 1, -40),
	}, vignetteGui)
	vignetteStroke = UITheme.stroke(ring, 46, "Downed")
	vignetteStroke.Transparency = 0.45

	downedGui = UITheme.screen("COHUE_Downed", 25)
	downedGui.Enabled = false
	local zone = UITheme.zone(downedGui, "Center", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.42), UDim2.fromOffset(300, 150))
	downedPanel = UITheme.popup(zone, { Size = UDim2.fromScale(1, 1) })
	downedPanelStroke = downedPanel:WaitForChild("Ink") :: UIStroke
	UITheme.paint(downedPanelStroke, "Color", "Downed")
	downedTitle = UITheme.label(downedPanel, { name = "Title", size = UDim2.new(1, -16, 0, 34), position = UDim2.fromOffset(8, 8), role = "NumberL", font = "number", color = "Downed", outline = true })
	local secRow = holder(downedPanel, "Seconds", UDim2.new(1, 0, 0, 26), 0)
	secRow.Position = UDim2.fromOffset(0, 44)
	list(secRow, true, 6, Enum.HorizontalAlignment.Center)
	downedSeconds = UITheme.label(secRow, { name = "N", size = UDim2.new(0, 0, 1, 0), autoSize = Enum.AutomaticSize.X, role = "NumberM", font = "number", outline = true })
	downedSeconds.LayoutOrder = 1
	downedSecondsCaption = UITheme.label(secRow, { name = "Caption", size = UDim2.new(0, 0, 1, 0), autoSize = Enum.AutomaticSize.X, role = "BodyM", font = "heavy", color = "TextDim", text = S.DownedSeconds })
	downedSecondsCaption.LayoutOrder = 2
	reviveBar = UITheme.glossBar(downedPanel, UDim2.new(1, -40, 0, 16), UDim2.fromOffset(20, 76), "Revive")
	reviveText = UITheme.label(downedPanel, { name = "Revive", size = UDim2.new(1, -16, 0, 18), position = UDim2.fromOffset(8, 96), role = "LabelS", color = "ReviveLight", outline = true })
	downedHint = UITheme.label(downedPanel, { name = "Hint", size = UDim2.new(1, -24, 0, 34), position = UDim2.fromOffset(12, 114), role = "BodyS", font = "body", color = "TextMuted", wrap = true })
	ghostPill = UITheme.pill(downedPanel, { name = "Back", tone = "PanelLight", text = S.GhostBack })
	ghostPill.frame.AnchorPoint = Vector2.new(0.5, 0)
	ghostPill.frame.Position = UDim2.new(0.5, 0, 0, 104)
	ghostPill.frame.Visible = false
end

local function buildAnnounce()
	announceGui = UITheme.screen("COHUE_Announce", 30)
	announceZone = UITheme.zone(announceGui, "Banner", Vector2.new(0.5, 0), UDim2.new(0.5, 20, 0, 56), UDim2.fromOffset(440, 52))
	announceSlab = UITheme.glossy(announceZone, {
		name = "Slab",
		role = "Danger",
		size = UDim2.fromOffset(0, 44),
		anchor = Vector2.new(0.5, 0),
		position = UDim2.fromScale(0.5, 0),
		radius = 16,
		lip = 5,
	})
	local root = announceSlab.root
	root.AutomaticSize = Enum.AutomaticSize.X
	root.Visible = false
	announceSlab.face.AutomaticSize = Enum.AutomaticSize.X
	announceSlab.content.AutomaticSize = Enum.AutomaticSize.X
	announceSlab.content.Size = UDim2.new(0, 0, 1, 0)
	UITheme.new("UIPadding", { PaddingLeft = UDim.new(0, 22), PaddingRight = UDim.new(0, 22) }, announceSlab.content)
	announceText = UITheme.label(announceSlab.content, {
		name = "Text",
		size = UDim2.new(0, 0, 1, 0),
		autoSize = Enum.AutomaticSize.X,
		role = "TitleM",
		outline = true,
	})
	UITheme.new("UIScale", { Name = "PopScale" }, root)
end

---------------------------------------------------------------------------- layout per device

local function layout()
	local device = UITheme.device()
	local portrait = UITheme.isPortrait()
	local scale = UITheme.scale()
	local mm = minimapSize()
	if portrait then
		-- P01: KO in the Roblox bar row (right), timer under it, left column under the timer.
		koZone.Position = UDim2.new(1, -M, 0, 2)
		timerZone.Position = UDim2.new(0.5, math.round(-30 * scale), 0, math.round(52 * scale))
		leftZone.Position = UDim2.fromOffset(M, math.round(66 * scale))
		announceZone.Position = UDim2.new(0.5, 0, 0.5, -60)
	else
		-- L01 / C01: timer centred in the Roblox bar row, KO left of the minimap, left column under the bar.
		koZone.Position = UDim2.new(1, -(M + math.round((mm + 8) * scale)), 0, 4)
		timerZone.Position = UDim2.new(0.5, 0, 0, 4)
		leftZone.Position = UDim2.fromOffset(M, M)
		announceZone.Position = UDim2.new(0.5, math.round(20 * scale), 0, math.round(56 * scale))
	end
	if device == "phone" then
		buildBox.Parent = leftZone
		buildBox.LayoutOrder = 3
	else
		buildBox.Parent = bottomLeft
		buildBox.LayoutOrder = 1
	end
	-- During the 8 s card offer (phone), the build, team and feed step aside (Figma L04 / P04).
	local cardsOpen = UITheme.flag("cardsOpen") == true and device == "phone"
	buildBox.Visible = not cardsOpen
	teamBox.Visible = not cardsOpen
	feedBox.Visible = not cardsOpen
end

---------------------------------------------------------------------------- updates

local function setWorldText()
	local n = run.worldIndex or run.stage
	local m = run.worldCount or worldsPerRun()
	UITheme.setText(worldText, S.World, { n = n, m = m })
end

local function inOvertime(): boolean
	return run.overtime or run.phase == "FinalWave"
end

local function plusClock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("+%02d:%02d", s // 60, s % 60)
end

local lastTimerText = ""
local urgent = false
local overtimeShown = false
local lastStep = -1
local function updateTimer()
	local elapsed = os.clock() - run.stamp
	local text: string
	local isUrgent = false
	local ot = inOvertime()
	if ot then
		local seconds = run.overtimeSeconds + elapsed
		text = plusClock(seconds)
		local step = run.overtimeStep or math.floor(seconds / Config.Hud.OvertimeStepSeconds)
		if step ~= lastStep then
			lastStep = step
			dangerPill.frame.Visible = step > 0
			UITheme.setText(dangerPill.label, S.Danger, { n = step })
		end
	else
		local left = math.max(0, run.timeLeft - elapsed)
		text = UITheme.clock(left)
		isUrgent = left < Config.Hud.UrgentSeconds and (run.phase == "Running" or run.phase == "Boss")
	end
	if ot ~= overtimeShown then
		overtimeShown = ot
		clockIcon.Visible = not ot
		stopwatchIcon.Visible = ot
		worldText.Visible = not ot
		overtimePill.frame.Visible = ot
		dangerPill.frame.Visible = ot and lastStep > 0
		UITheme.paint(timerStroke, "Color", if ot then "Overtime" else "Outline")
		timerStroke.Thickness = if ot then 3 else 2.5
		UITheme.paint(timerText, "TextColor3", if ot then "Overtime" else "Text")
		if ot then
			UITheme.pop(timerChip, 0.85)
		end
	end
	if not ot and isUrgent ~= urgent then
		urgent = isUrgent
		UITheme.paint(timerText, "TextColor3", if isUrgent then "Warning" else "Text")
		if isUrgent then
			UITheme.pop(timerChip, 0.85) -- one pop at 1:00, never a blink
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
	arrowHolder.Rotation = math.deg(math.atan2(rel.X, -rel.Z)) - 90
	local character = LOCAL.Character
	-- lihfolk-ignore: findfirstchild-chain -- fwjelaa-ignore: findfirstchild-chain (nil-checked below)
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local d = math.floor((target - root.Position).Magnitude)
		if d ~= lastDist then
			lastDist = d
			UITheme.setText(arrowDist, S.BossDistance, { n = d })
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
	if type(state.phase) == "string" then
		if state.phase == "Loadout" or (state.phase == "Running" and run.phase == "Ended") then
			bossDefeated = false
		end
		run.phase = state.phase
	end
	if type(state.timeLeft) == "number" then
		run.timeLeft = state.timeLeft
	end
	-- v2 (RunManager A04-02): overtime / overtimeSeconds / overtimeStep; v1 fallback finalWaveSeconds.
	run.overtime = state.overtime == true
	if type(state.overtimeSeconds) == "number" then
		run.overtimeSeconds = state.overtimeSeconds
	elseif type(state.finalWaveSeconds) == "number" then
		run.overtimeSeconds = state.finalWaveSeconds
	end
	run.overtimeStep = if type(state.overtimeStep) == "number" then state.overtimeStep else nil
	run.stamp = os.clock()
	local changed = state.worldIndex ~= run.worldIndex or state.stage ~= run.stage or state.worldCount ~= run.worldCount
	run.worldIndex = if type(state.worldIndex) == "number" then state.worldIndex else nil
	run.worldCount = if type(state.worldCount) == "number" then state.worldCount else nil
	if type(state.worldId) == "string" then
		run.worldId = state.worldId
	end
	if type(state.tier) == "number" then
		run.tier = state.tier
	end
	if type(state.stage) == "number" then
		if state.stage ~= run.stage then
			bossDefeated = false
		end
		run.stage = state.stage
	end
	if changed then
		setWorldText()
	end
	if state.phase == "BossDefeated" or state.victory == true then
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
	VictoryBanner.onRunState(state)
end

local function setDowned(v: any)
	local downed = v.downed == true
	local ghost = v.ghost == true
	downedGui.Enabled = (downed or ghost) and UITheme.inRun()
	vignetteGui.Enabled = downed and UITheme.inRun()
	if downed then
		UITheme.setText(downedTitle, S.DownedTitle)
		UITheme.paint(downedTitle, "TextColor3", "Downed")
		UITheme.paint(downedPanelStroke, "Color", "Downed")
		local left = math.max(0, math.ceil(tonumber(v.downedTimeLeft) or 0))
		downedSeconds.Text = tostring(left)
		downedSeconds.Parent.Visible = true
		reviveBar.frame.Visible = true
		local progress = math.clamp(tonumber(v.reviveProgress) or 0, 0, 1)
		reviveBar.set(progress)
		reviveText.Visible = progress > 0
		UITheme.setText(reviveText, S.ReviveBy, { p = math.floor(progress * 100) })
		UITheme.setText(downedHint, S.DownedHint)
		downedHint.Position = UDim2.fromOffset(12, 114)
		ghostPill.frame.Visible = false
		if not vignetteTween and not UITheme.flashesReduced() then
			-- Slow breathing (0.4 Hz, far under the 3 Hz flash limit). Static with Reduce flashes.
			local tween = TweenService:Create(
				vignetteStroke,
				TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Transparency = 0.7 }
			)
			tween:Play()
			vignetteTween = tween
		end
	else
		if vignetteTween then
			vignetteTween:Cancel()
			vignetteTween = nil
			vignetteStroke.Transparency = 0.45
		end
		if ghost then
			UITheme.setText(downedTitle, S.GhostTitle)
			UITheme.paint(downedTitle, "TextColor3", "Ghost")
			UITheme.paint(downedPanelStroke, "Color", "Ghost")
			downedSeconds.Parent.Visible = false
			reviveBar.frame.Visible = false
			reviveText.Visible = false
			UITheme.setText(downedHint, S.GhostHint)
			downedHint.Position = UDim2.fromOffset(12, 48)
			ghostPill.frame.Visible = true
		end
	end
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
	local shield = math.max(0, tonumber(v.shield) or 0)
	-- HP and shield share the track: red fill, then a silver extension (total capped at the track).
	local total = math.max(maxHp, hp + shield)
	local hpFrac = math.clamp(hp / total, 0, 1)
	local shFrac = math.clamp(shield / total, 0, 1 - hpFrac)
	hpFill.Size = UDim2.fromScale(hpFrac, 1)
	hpFill.Visible = hpFrac > 0.005
	shieldFill.Visible = shFrac > 0.005
	if shFrac > 0.005 then
		shieldFill.Position = UDim2.fromScale(hpFrac, 0)
		shieldFill.Size = UDim2.fromScale(shFrac, 1)
	end
	local text = string.format("%d / %d", math.ceil(hp), math.ceil(maxHp))
	if hpText.Text ~= text then
		hpText.Text = text
	end
	local sText = if shield > 0 then "+" .. tostring(math.ceil(shield)) else ""
	if shieldText.Text ~= sText then
		shieldText.Text = sText
	end
	setDowned(v)
end

local feedEntries: { { text: any, args: { [string]: any }?, color: string?, at: number } } = {}

local function renderFeed()
	for i, row in feedRows do
		local entry = feedEntries[i]
		row.frame.Visible = entry ~= nil
		if entry then
			UITheme.setText(row.text, entry.text, entry.args)
			UITheme.paint(row.dot, "BackgroundColor3", entry.color or "PingRegroup")
		end
	end
end

-- Add a line to the left feed (pings, teammate downed). Public: PingUI calls it.
-- color: optional palette token for the dot (PingBoss, PingHelp...).
function HUD.feed(text: any, args: { [string]: any }?, color: string?)
	table.insert(feedEntries, 1, { text = text, args = args, color = color, at = os.clock() })
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
				row.avatar.Text = string.upper(string.sub(name, 1, 1))
			end
			local maxHp = math.max(1, tonumber(info.maxHp) or 1)
			row.bar.set((tonumber(info.hp) or 0) / maxHp)
			local downed = info.downed == true
			local ghost = info.ghost == true
			row.bar.frame.Visible = not downed and not ghost
			row.state.frame.Visible = downed or ghost
			UITheme.paint(row.avatar, "BackgroundColor3", if ghost then "Ghost" else "MapAlly")
			if ghost then
				row.state.setTone("PanelLight")
				UITheme.setText(row.state.label, S.Ghost)
			elseif downed then
				row.state.setTone("Downed")
				local left = tonumber(info.downedTimeLeft)
				UITheme.setText(row.state.label, if left then "+ " .. UITheme.format(S.Downed) .. " " .. tostring(math.ceil(left)) .. "s" else "+ " .. UITheme.format(S.Downed))
			end
			if downed and not teamDowned[userId] then
				HUD.feed(S.TeammateDowned, { name = name }, "Downed")
			end
			teamDowned[userId] = downed
		end
	end
	for j = i + 1, #teamRows do
		teamRows[j].frame.Visible = false
	end
end

local function fillSlots(slots: { Slot }, entries: any, count: number, configName: string)
	local n = if type(entries) == "table" then #entries else 0
	local shown = math.clamp(math.max(count, n), 0, #slots)
	for i, slot in slots do
		local entry = if type(entries) == "table" then entries[i] else nil
		slot.frame.Visible = i <= shown
		-- lihfolk-ignore: findfirstchild-chain -- fwjelaa-ignore: findfirstchild-chain (nil-checked below)
		local ink = slot.frame:FindFirstChild("Ink") :: UIStroke?
		if type(entry) == "table" and type(entry.id) == "string" then
			UITheme.setIcon(slot.icon, UITheme.format(UITheme.nameOf(configName, entry.id)))
			slot.icon.Visible = true
			slot.level.frame.Visible = true
			slot.level.label.Text = tostring(entry.level or 1)
			UITheme.back(slot.frame, 0.05)
			if ink then
				UITheme.paint(ink, "Color", "Outline")
				ink.Transparency = 0
			end
		else
			-- Empty slot: faint frame (shape says "free", not only the colour).
			slot.icon.Visible = false
			slot.level.frame.Visible = false
			UITheme.back(slot.frame, 0.7)
			if ink then
				UITheme.paint(ink, "Color", "TextMuted")
				ink.Transparency = 0.45
			end
		end
	end
end

local function onBuild(b: any)
	if type(b) ~= "table" then
		return
	end
	fillSlots(weaponSlots, b.weapons, tonumber(b.weaponSlots) or 0, "Weapons")
	-- Runes are the v1 "grimoires" (same payload field until the combat domain renames it).
	fillSlots(runeSlots, b.runes or b.grimoires, tonumber(b.runeSlots or b.grimoireSlots) or 0, "Grimoires")
end

local function renderKo()
	local text = UITheme.short(kills)
	if koText.Text ~= text then
		koText.Text = text
	end
	local best = bestKills
	local isNew = best ~= nil and kills > best and best > 0
	if best == nil then
		UITheme.setText(bestText, S.BestUnknown)
	else
		UITheme.setText(bestText, S.Best, { n = UITheme.short(best) })
	end
	bestText.Visible = not isNew
	newBestPill.frame.Visible = isNew
	UITheme.paint(koText, "TextColor3", if isNew then "Coin" else "Text")
	if isNew and not newBestShown then
		newBestShown = true
		UITheme.pop(koText.Parent :: GuiObject, 0.8) -- one pop, then static
	end
end

local function onProgress(p: any)
	if type(p) ~= "table" then
		return
	end
	local lvl = tostring(p.level or 1)
	if levelText.Text ~= lvl then
		levelText.Text = lvl
		UITheme.pop(levelBadge)
	end
	local need = math.max(1, tonumber(p.xpNext) or 1)
	xpBar.set((tonumber(p.xp) or 0) / need)
	-- KO (server count, A04-03): PlayerProgress.kills, else the RunKills player attribute.
	local k = tonumber(p.kills)
	if k and k ~= kills then
		kills = k
		renderKo()
	end
end

local function onKillsAttribute()
	local k = tonumber(LOCAL:GetAttribute("RunKills"))
	if k and k ~= kills then
		kills = k
		renderKo()
	end
end

local function onProfile(p: any)
	if type(p) ~= "table" then
		return
	end
	-- Personal best KO in one run. Contract request (data domain): Profile.bestKills.
	local best = tonumber(p.bestKills)
		or (type(p.records) == "table" and tonumber(p.records.bestKills))
		or (type(p.stats) == "table" and tonumber(p.stats.bestKills))
		or nil
	if best ~= bestKills then
		bestKills = best
		renderKo()
	end
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
	UITheme.paint(companionText, "TextColor3", if companion.stunned then "TextMuted" else "Text")
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

-- Announcements: one at a time, queued (vault: HUD Design popup arbitration). Subtitles of audio cues.
local DANGER_KINDS = { Boss = true, BossRevealed = true, BossStart = true, FinalWave = true, Overtime = true, OvertimeStep = true, Defeat = true, Downed = true, Elite = true, MiniBoss = true, Hazard = true }
local GOLD_KINDS = { Victory = true, CashOut = true }
local queue: { any } = {}
local announcing = false
local function nextAnnounce()
	if announcing then
		return
	end
	local a = table.remove(queue, 1)
	if not a then
		announceSlab.root.Visible = false
		return
	end
	announcing = true
	local kind = tostring(a.kind or "")
	announceSlab.setRole(if DANGER_KINDS[kind] then "Danger" elseif GOLD_KINDS[kind] then "Premium" else "Info")
	UITheme.setText(announceText, a.text or "")
	announceSlab.root.Visible = true
	UITheme.pop(announceSlab.root, 0.9)
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
	topGui.Enabled = inRun
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
	-- Timer, KO and boss info sit in the Roblox bar row (right of Roblox's buttons): device insets only.
	topGui = UITheme.screen("COHUE_HUDTop", 10, Enum.ScreenInsets.DeviceSafeInsets)
	leftZone = UITheme.zone(hudGui, "TopLeft", Vector2.zero, UDim2.fromOffset(M, M), UDim2.fromOffset(VITALS_W + 8, 360))
	list(leftZone, false, 8).VerticalAlignment = Enum.VerticalAlignment.Top
	buildVitals(leftZone)
	companionText = UITheme.label(leftZone, {
		name = "Companion",
		size = UDim2.fromOffset(VITALS_W, 16),
		role = "LabelS",
		align = Enum.TextXAlignment.Left,
		outline = true,
	})
	companionText.LayoutOrder = 2
	companionText.Visible = false
	buildTeam(leftZone)
	buildFeed(leftZone)
	bottomLeft = UITheme.zone(hudGui, "BottomLeft", Vector2.new(0, 1), UDim2.new(0, M, 1, -M), UDim2.fromOffset(VITALS_W + 8, 96))
	buildBox = buildBuild()
	buildTimer(topGui)
	buildKo(topGui)
	buildDowned()
	buildAnnounce()
	VictoryBanner.start()
	CaptureUI.start()
	layout()
	setWorldText()
	renderKo()
	refreshVisibility()

	UITheme.changed:connect(function(reason: string)
		if reason == "device" or reason == "scale" or reason == "flags" then
			layout()
		elseif reason == "phase" then
			refreshVisibility()
		elseif reason == "lang" then
			setWorldText()
			renderCompanion()
			renderKo()
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
	UITheme.watch("Profile", onProfile)
	LOCAL:GetAttributeChangedSignal("RunKills"):Connect(onKillsAttribute)
	onKillsAttribute()

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
