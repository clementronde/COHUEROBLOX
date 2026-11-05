--!strict
-- Run HUD v3 « vraies briques » (Figma Run v3 L01-L11 / P01-P11 / C01-C11, validé le 5 nov. 2026).
-- Rien n'est fabriqué ici : le HUD est posé dans la place (StarterGui.COHUE_HUD, COHUE_Downed,
-- COHUE_Vignette, montés par tools/ui/build-ui-v3.luau). Ce module retrouve les objets par leur nom,
-- écrit les valeurs, recolore et anime. Un objet absent est signalé dans la sortie (UIKit), jamais recréé.
-- Contenu : vitals (niveau, vie + bouclier, XP, Silver), équipiers, fil des pings, chrono → Overtime,
-- KO + record, flèche et barre du boss, annonces, armes, panneau À terre / fantôme.
-- Écoute : RunState, PlayerVitals, PlayerProgress, Coins, Build, CompanionState, BossState, Announce, Profile.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local UITheme = require(script.Parent:WaitForChild("UITheme"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))
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

type Slot = { frame: Frame, icon: ImageLabel, initials: TextLabel?, level: UIKit.Tag }
type TeamRow = { frame: Frame, portrait: ImageLabel, rim: UIStroke?, avatar: TextLabel, name: TextLabel, bar: UIKit.Bar, state: UIKit.Tag, userId: number? }

-- instances (posées dans la place, retrouvées dans bind) ---------------------------------------
local hudGui: ScreenGui
local leftZone: Frame
local timerZone: Frame
local koZone: Frame
local buildZone: Frame
local announceZone: Frame
local buildBox: Frame
local teamBox: Frame
local feedBox: Frame
local levelText: TextLabel
local levelBadge: GuiObject
local hpFill: Frame
local shieldFill: Frame
local hpText: TextLabel
local shieldText: TextLabel
local xpBar: UIKit.Bar
local coinText: TextLabel
local companionText: TextLabel
local timerChip: Frame
local timerText: TextLabel
local clockIcon: GuiObject
local stopwatchIcon: GuiObject
local worldText: TextLabel
local overtimePill: UIKit.Tag
local dangerPill: UIKit.Tag
local koText: TextLabel
local bestText: TextLabel
local newBestPill: UIKit.Tag
local arrowBox: Frame
local arrowHolder: Frame
local arrowDist: TextLabel
local bossBox: Frame
local bossName: TextLabel
local bossBar: UIKit.Bar
local bossPct: TextLabel
local bossPips: { Frame } = {}
local teamRows: { TeamRow } = {}
local feedRows: { { frame: Frame, dot: Frame, text: TextLabel } } = {}
local weaponSlots: { Slot } = {}
local runeSlots: { Slot } = {}
local downedGui: ScreenGui
local downedHeader: Frame
local downedTitle: TextLabel
local downedSeconds: TextLabel
local downedHint: TextLabel
local reviveText: TextLabel
local reviveBar: UIKit.Bar
local ghostPill: UIKit.Tag
local downedPanelStroke: UIStroke
local vignetteGui: ScreenGui
local vignetteStroke: UIStroke
local vignetteTween: Tween?
local announceBanner: Frame
local announceText: TextLabel
local announceLine: TextLabel?

---------------------------------------------------------------------------- small helpers

local function minimapSize(): number
	return (Config.Minimap.Size :: any)[UITheme.device()] or 120
end

local function worldsPerRun(): number
	local runCfg = UITheme.config("Run")
	return if runCfg and type(runCfg.WorldsPerRun) == "number" then runCfg.WorldsPerRun else 3
end

-- Portrait d'équipier : vignette Roblox (HeadShot), mise en cache ; l'initiale reste en secours.
local headshots: { [number]: string } = {}
local function setHeadshot(row: TeamRow, userId: number)
	if row.userId == userId then
		return
	end
	row.userId = userId
	local cached = headshots[userId]
	if cached then
		row.portrait.Image = cached
		row.avatar.Visible = cached == ""
		return
	end
	row.portrait.Image = ""
	row.avatar.Visible = true
	task.spawn(function()
		local ok, img = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		headshots[userId] = if ok then img else ""
		if row.userId == userId and ok then
			row.portrait.Image = img
			row.avatar.Visible = false
		end
	end)
end

---------------------------------------------------------------------------- bind (gabarits posés)

local function bindSlot(frame: Frame): Slot
	return {
		frame = frame,
		icon = UIKit.find(frame, "Icon"),
		-- lihfolk-ignore: findfirstchild-chain -- fwjelaa-ignore: findfirstchild-chain (optional child, typed nil-able and checked)
		initials = frame:FindFirstChild("Initials") :: TextLabel?,
		level = UIKit.tag(UIKit.find(frame, "Level")),
	}
end

local function bind(): boolean
	local gui = UIKit.screen("COHUE_HUD")
	local downed = UIKit.screen("COHUE_Downed")
	local vig = UIKit.screen("COHUE_Vignette")
	if not (gui and downed and vig) then
		return false
	end
	hudGui = gui
	downedGui = downed
	vignetteGui = vig

	leftZone = UIKit.find(gui, "TopLeft")
	timerZone = UIKit.find(gui, "TopCenter")
	koZone = UIKit.find(gui, "TopRight")
	buildZone = UIKit.find(gui, "BottomCenter")
	announceZone = UIKit.find(gui, "Announce")
	for _, z in { leftZone, timerZone, koZone, buildZone, announceZone } do
		-- lihfolk-ignore: findfirstchild-chain -- fwjelaa-ignore: findfirstchild-chain (optional child, typed nil-able and checked)
		UITheme.adoptScale(z and z:FindFirstChild("Scale") :: UIScale?)
	end

	-- vitals
	levelBadge = UIKit.find(leftZone, "Vitals.Level")
	levelText = UIKit.find(leftZone, "Vitals.Level.Number")
	hpFill = UIKit.find(leftZone, "Vitals.Hp.Fill")
	shieldFill = UIKit.find(leftZone, "Vitals.Hp.Shield")
	hpText = UIKit.find(leftZone, "Vitals.Hp.Value")
	shieldText = UIKit.find(leftZone, "Vitals.Hp.ShieldValue")
	xpBar = UIKit.bar(UIKit.find(leftZone, "Vitals.Xp"))
	coinText = UIKit.find(leftZone, "Vitals.Silver")
	companionText = UIKit.find(leftZone, "Companion")

	-- équipiers
	teamBox = UIKit.find(leftZone, "Team")
	for i = 1, Config.Hud.TeamMax do
		local m = UIKit.find(teamBox, "Mate" .. i) :: Frame?
		if m then
			local portrait = UIKit.find(m, "Portrait") :: ImageLabel
			teamRows[i] = {
				frame = m,
				portrait = portrait,
				-- lihfolk-ignore: findfirstchild-chain -- fwjelaa-ignore: findfirstchild-chain (optional child, typed nil-able and checked)
				rim = portrait and portrait:FindFirstChild("Rim") :: UIStroke?,
				avatar = UIKit.find(portrait, "Initial"),
				name = UIKit.find(m, "Name"),
				bar = UIKit.bar(UIKit.find(m, "Bar")),
				state = UIKit.tag(UIKit.find(m, "State")),
			}
		end
	end

	-- fil des pings
	feedBox = UIKit.find(leftZone, "Feed")
	for i = 1, Config.Hud.FeedMax do
		local line = UIKit.find(feedBox, "Line" .. i) :: Frame?
		if line then
			feedRows[i] = { frame = line, dot = UIKit.find(line, "Dot"), text = UIKit.find(line, "Text") }
		end
	end

	-- chrono, monde, Overtime, boss
	timerChip = UIKit.find(timerZone, "Timer")
	timerText = UIKit.find(timerChip, "Time")
	clockIcon = UIKit.find(timerChip, "Clock")
	stopwatchIcon = UIKit.find(timerChip, "Stopwatch")
	worldText = UIKit.find(timerZone, "Caption.World")
	overtimePill = UIKit.tag(UIKit.find(timerZone, "Caption.Overtime"))
	dangerPill = UIKit.tag(UIKit.find(timerZone, "Caption.Danger"))
	arrowBox = UIKit.find(timerZone, "BossArrow")
	arrowHolder = UIKit.find(arrowBox, "Row.Arrow")
	arrowDist = UIKit.find(arrowBox, "Row.Distance")
	bossBox = UIKit.find(timerZone, "BossBar")
	bossName = UIKit.find(bossBox, "Name")
	bossBar = UIKit.bar(UIKit.find(bossBox, "Bar"))
	bossPct = UIKit.find(bossBox, "Bar.Pct")
	for i = 1, 4 do
		-- lihfolk-ignore: findfirstchild-chain -- fwjelaa-ignore: findfirstchild-chain (optional child, typed nil-able and checked)
		local pip = bossBox and bossBox:FindFirstChild("Pip" .. i) :: Frame?
		if pip then
			bossPips[i] = pip
		end
	end

	-- KO et record
	local koRow = UIKit.find(koZone, "Ko")
	koText = UIKit.find(koRow, "Count")
	bestText = UIKit.find(koZone, "Best.BestText")
	newBestPill = UIKit.tag(UIKit.find(koZone, "Best.NewBest"))

	-- armes (et Runes)
	buildBox = UIKit.find(buildZone, "Build")
	for i = 1, 6 do
		local w = UIKit.find(buildBox, "Weapons.Slot" .. i) :: Frame?
		if w then
			weaponSlots[i] = bindSlot(w)
		end
		local r = UIKit.find(buildBox, "Runes.Slot" .. i) :: Frame?
		if r then
			runeSlots[i] = bindSlot(r)
		end
	end

	-- annonces
	announceBanner = UIKit.find(announceZone, "Banner")
	announceText = UIKit.find(announceBanner, "Text.Title")
	announceLine = UIKit.find(announceBanner, "Text.Line")

	-- À terre / fantôme
	local center = UIKit.find(downed, "Center")
	-- lihfolk-ignore: findfirstchild-chain -- fwjelaa-ignore: findfirstchild-chain (optional child, typed nil-able and checked)
	UITheme.adoptScale(center and center:FindFirstChild("Scale") :: UIScale?)
	downedHeader = UIKit.find(center, "Panel.Header")
	downedTitle = UIKit.find(downedHeader, "Title")
	downedPanelStroke = UIKit.find(center, "Panel.Body.RimFrame.Rim")
	downedSeconds = UIKit.find(center, "Panel.Body.Seconds.N")
	reviveBar = UIKit.bar(UIKit.find(center, "Panel.Body.ReviveBar"))
	reviveText = UIKit.find(center, "Panel.Body.Revive")
	downedHint = UIKit.find(center, "Panel.Body.Hint")
	ghostPill = UIKit.tag(UIKit.find(center, "Panel.Body.Back"))
	vignetteStroke = UIKit.find(vig, "Ring.Edge")
	return true
end

---------------------------------------------------------------------------- layout per device

local function layout()
	local device = UITheme.device()
	local portrait = UITheme.isPortrait()
	local scale = UITheme.scale()
	local mm = minimapSize()
	if portrait then
		-- P01 : chrono et KO sous l'encoche, puis vitals et mini-carte, puis équipiers ; armes au-dessus des boutons.
		timerZone.AnchorPoint = Vector2.new(0, 0)
		timerZone.Position = UDim2.fromOffset(M, math.round(52 * scale))
		koZone.Position = UDim2.new(1, -M, 0, math.round(48 * scale))
		leftZone.Position = UDim2.fromOffset(M, math.round(124 * scale))
		buildZone.Position = UDim2.new(0.5, 0, 1, -math.round(262 * scale))
		announceZone.Position = UDim2.new(0.5, 0, 0, math.round(330 * scale))
	else
		-- L01 / C01 : chrono centré dans la rangée de la barre Roblox, KO à gauche de la mini-carte,
		-- colonne gauche sous la barre, armes en bas au centre, annonces dans le couloir central.
		timerZone.AnchorPoint = Vector2.new(0.5, 0)
		timerZone.Position = UDim2.new(0.5, 0, 0, 4)
		koZone.Position = UDim2.new(1, -(M + math.round((mm + 14) * scale)), 0, 2)
		leftZone.Position = UDim2.fromOffset(M, math.round(64 * scale))
		buildZone.Position = UDim2.new(0.5, 0, 1, -math.round(24 * scale))
		announceZone.Position = UDim2.new(0.5, math.round(66 * scale), 0, math.round(84 * scale))
	end
	-- Pendant le passage de niveau (téléphone), armes, équipiers et fil s'effacent (Figma L04 / P04).
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
		timerText.TextColor3 = if ot then UIKit.tone("Tomato.l") else Color3.new(1, 1, 1)
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
		UIKit.tint(downedHeader, "Tomato")
		downedPanelStroke.Color = UIKit.tone("Tomato")
		local left = math.max(0, math.ceil(tonumber(v.downedTimeLeft) or 0))
		downedSeconds.Text = tostring(left)
		downedSeconds.Parent.Visible = true
		reviveBar.frame.Visible = true
		local progress = math.clamp(tonumber(v.reviveProgress) or 0, 0, 1)
		reviveBar.set(progress)
		reviveText.Visible = progress > 0
		UITheme.setText(reviveText, S.ReviveBy, { p = math.floor(progress * 100) })
		-- v3 : une seule information à la fois (le temps, puis qui relève) ; pas de phrase d'aide.
		downedHint.Visible = false
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
			UIKit.tint(downedHeader, "Plum")
			downedPanelStroke.Color = UIKit.tone("Plum")
			downedSeconds.Parent.Visible = false
			reviveBar.frame.Visible = false
			reviveText.Visible = false
			UITheme.setText(downedHint, S.GhostHint)
			downedHint.Visible = true
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
			setHeadshot(row, userId)
			local maxHp = math.max(1, tonumber(info.maxHp) or 1)
			row.bar.set((tonumber(info.hp) or 0) / maxHp)
			local downed = info.downed == true
			local ghost = info.ghost == true
			row.bar.frame.Visible = not downed and not ghost
			row.state.frame.Visible = downed or ghost
			if row.rim then
				row.rim.Color = UIKit.tone(if ghost then "Plum" elseif downed then "Tomato" else "Royal")
			end
			row.portrait.ImageTransparency = if ghost then 0.5 else 0
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
		if type(entry) == "table" and type(entry.id) == "string" then
			-- Icône en briques (shared/Config/UIAssets) ; sinon les initiales du nom en secours.
			local img = UIKit.icon(entry.id)
			slot.icon.Image = img
			slot.icon.Visible = img ~= ""
			if slot.initials then
				local name = UITheme.format(UITheme.nameOf(configName, entry.id))
				local initials = string.upper(string.sub(name, 1, 2))
				slot.initials.Text = initials
				slot.initials.Visible = img == ""
			end
			slot.level.frame.Visible = true
			slot.level.label.Text = "Lv" .. tostring(entry.level or 1)
			UIKit.tint(slot.frame, "Cream")
		else
			-- Emplacement libre : brique prune vide (la forme dit « libre », pas seulement la couleur).
			slot.icon.Visible = false
			if slot.initials then
				slot.initials.Visible = false
			end
			slot.level.frame.Visible = false
			UIKit.tint(slot.frame, "Plum")
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
		announceBanner.Visible = false
		return
	end
	announcing = true
	local kind = tostring(a.kind or "")
	UIKit.tint(announceBanner, if DANGER_KINDS[kind] then "Tomato" elseif GOLD_KINDS[kind] then "Gold" elseif kind == "Boss" then "Grape" else "Sky")
	UITheme.setText(announceText, a.text or "")
	if announceLine then
		announceLine.Visible = a.line ~= nil
		if a.line ~= nil then
			UITheme.setText(announceLine, a.line)
		end
	end
	announceBanner.Visible = true
	UITheme.pop(announceBanner, 0.9)
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
	if not inRun then
		downedGui.Enabled = false
		vignetteGui.Enabled = false
	end
	refreshArrow()
end

---------------------------------------------------------------------------- lifecycle

function HUD.start()
	if not bind() then
		warn("[HUD] gabarits v3 absents : lancer tools/ui/build-ui-v3.luau dans Studio (place COHUE). HUD inactif.")
		return
	end
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
