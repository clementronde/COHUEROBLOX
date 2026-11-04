--!strict
-- End of run: result, numbers, damage per weapon bars, quest progress bars, silver, Replay.
-- Design: docs/dossier/60-ui-ux.md section 10. Listens: RunSummary, phase. Sends: Replay().

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Registry = require(Shared:WaitForChild("Registry"))
local UITheme = require(script.Parent:WaitForChild("UITheme"))

local S = UITheme.S

local EndScreen = {}

type Row = { frame: Frame, name: TextLabel, value: TextLabel, bar: UITheme.Bar }

local gui: ScreenGui
local title: TextLabel
local subtitle: TextLabel
local statsLine: TextLabel
local damageRows: { Row } = {}
local questRows: { Row } = {}
local silver: TextLabel
local replayBtn: TextButton
local damageHeader: TextLabel
local questHeader: TextLabel
local summary: any = nil
local replaySentAt = -math.huge

local MAX_ROWS = 8

local function makeRow(parent: Instance, orderN: number, fill: string): Row
	local f = UITheme.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = orderN, Visible = false }, parent)
	local name = UITheme.label(f, {
		size = UDim2.new(0.38, 0, 1, 0),
		role = "Small",
		align = Enum.TextXAlignment.Left,
	})
	local bar = UITheme.bar(f, UDim2.new(0.42, 0, 0, 12), UDim2.new(0.39, 0, 0, 5), fill)
	local value = UITheme.label(f, {
		size = UDim2.new(0.18, 0, 1, 0),
		position = UDim2.fromScale(0.82, 0),
		role = "Small",
		align = Enum.TextXAlignment.Right,
	})
	return { frame = f, name = name, value = value, bar = bar }
end

local function render()
	local s = summary
	if type(s) ~= "table" then
		return
	end
	UITheme.setText(title, if s.victory then S.Victory else S.Defeat)
	UITheme.paint(title, "TextColor3", if s.victory then "Coin" else "Text")
	subtitle.Text = UITheme.format(UITheme.nameOf("Worlds", tostring(s.worldId or "")))
		.. " · "
		.. UITheme.format(S.Tier, { n = s.tier or 1 })
		.. " · "
		.. UITheme.format(S.Stage, { n = s.stageReached or 1 })

	local parts = {
		UITheme.format(S.Kills) .. " " .. UITheme.short(tonumber(s.kills) or 0),
		UITheme.format(S.LevelN, { n = s.level or 1 }),
		UITheme.format(S.Coins) .. " " .. UITheme.short(tonumber(s.coinsEarned) or 0),
		UITheme.format(S.Shrines) .. " " .. tostring(s.shrinesCompleted or 0),
		UITheme.format(S.Chests) .. " " .. tostring(s.chestsOpened or 0),
		UITheme.format(S.Revives) .. " " .. tostring(s.revives or 0),
	}
	if (tonumber(s.finalWaveSeconds) or 0) > 0 then
		table.insert(parts, UITheme.format(S.FinalWaveSec) .. " " .. tostring(math.floor(s.finalWaveSeconds)))
	end
	statsLine.Text = table.concat(parts, "  ·  ")

	-- Damage per weapon, sorted.
	local list = {}
	if type(s.damageByWeapon) == "table" then
		for id, dmg in s.damageByWeapon do
			local n = tonumber(dmg)
			if n and n > 0 then
				table.insert(list, { id = tostring(id), dmg = n })
			end
		end
	end
	table.sort(list, function(a, b)
		if a.dmg ~= b.dmg then
			return a.dmg > b.dmg
		end
		return a.id < b.id
	end)
	local maxDmg = if list[1] then list[1].dmg else 1
	damageHeader.Visible = #list > 0
	for i, row in damageRows do
		local e = list[i]
		row.frame.Visible = e ~= nil
		if e then
			UITheme.setText(row.name, UITheme.nameOf("Weapons", e.id))
			row.value.Text = UITheme.short(e.dmg)
			row.bar.set(e.dmg / maxDmg)
		end
	end

	local quests = if type(s.questsProgressed) == "table" then s.questsProgressed else {}
	questHeader.Visible = #quests > 0
	for i, row in questRows do
		local q = quests[i]
		row.frame.Visible = type(q) == "table"
		if type(q) == "table" then
			UITheme.setText(row.name, UITheme.nameOf("Quests", tostring(q.id)))
			local goal = math.max(1, tonumber(q.goal) or 1)
			local progress = tonumber(q.progress) or 0
			row.bar.set(progress / goal)
			if q.completed then
				UITheme.setText(row.value, S.QuestDone)
				UITheme.paint(row.value, "TextColor3", "Primary")
			else
				UITheme.setText(row.value, UITheme.short(progress) .. "/" .. UITheme.short(goal))
				UITheme.paint(row.value, "TextColor3", "Text")
			end
		end
	end

	local earned = tonumber(s.silverEarned)
	silver.Visible = earned ~= nil
	if earned then
		UITheme.setText(silver, S.Silver, { n = earned })
	end
end

local function setOpen(open: boolean)
	gui.Enabled = open
	local ic = Registry.find("InputController")
	if ic and type(ic.setEnabled) == "function" then
		ic.setEnabled(not open and UITheme.phase() ~= "Loadout")
	end
	if open then
		replayBtn.Active = true
		replayBtn.AutoButtonColor = true
		UITheme.pop(replayBtn, 0.8)
	end
end

function EndScreen.start()
	gui = UITheme.screen("COHUE_End", 50, Enum.ScreenInsets.DeviceSafeInsets)
	gui.Enabled = false
	local zone = UITheme.zone(gui, "End", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(640, 350))
	local panel = UITheme.panel(zone, { Size = UDim2.fromScale(1, 1) })
	UITheme.back(panel, 0.05)

	title = UITheme.label(panel, { size = UDim2.new(1, 0, 0, 40), position = UDim2.fromOffset(0, 6), role = "Huge", font = "display", outline = true })
	subtitle = UITheme.label(panel, { size = UDim2.new(1, 0, 0, 16), position = UDim2.fromOffset(0, 46), role = "Small", color = "TextDim" })
	statsLine = UITheme.label(panel, {
		size = UDim2.new(1, -24, 0, 34),
		position = UDim2.fromOffset(12, 64),
		role = "Small",
		wrap = true,
	})

	local scroll = UITheme.new("ScrollingFrame", {
		Size = UDim2.new(1, -24, 0, 172),
		Position = UDim2.fromOffset(12, 100),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, panel)
	UITheme.new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
	damageHeader = UITheme.label(scroll, { size = UDim2.new(1, 0, 0, 20), role = "Body", align = Enum.TextXAlignment.Left, text = S.DamageByWeapon })
	damageHeader.LayoutOrder = 0
	for i = 1, MAX_ROWS do
		damageRows[i] = makeRow(scroll, i, "Hp")
	end
	questHeader = UITheme.label(scroll, { size = UDim2.new(1, 0, 0, 20), role = "Body", align = Enum.TextXAlignment.Left, text = S.Quests })
	questHeader.LayoutOrder = 100
	for i = 1, MAX_ROWS do
		questRows[i] = makeRow(scroll, 100 + i, "Xp")
	end

	silver = UITheme.label(panel, {
		size = UDim2.new(0.5, -12, 0, 56),
		position = UDim2.new(0, 12, 1, -64),
		role = "Title",
		color = "Coin",
		align = Enum.TextXAlignment.Left,
	})
	replayBtn = UITheme.button(panel, {
		name = "Replay",
		size = UDim2.fromOffset(240, 56),
		position = UDim2.new(1, -12, 1, -8),
		anchor = Vector2.new(1, 1),
		role = "Big",
		font = "display",
		fill = "Primary",
		outline = true,
		text = S.Replay,
	})
	replayBtn.Activated:Connect(function()
		if os.clock() - replaySentAt < 1 then
			return
		end
		replaySentAt = os.clock()
		replayBtn.Active = false
		replayBtn.AutoButtonColor = false
		Net.event("Replay"):FireServer()
		task.delay(1, function()
			replayBtn.Active = true
			replayBtn.AutoButtonColor = true
		end)
	end)

	UITheme.watch("RunSummary", function(s)
		if type(s) ~= "table" then
			return
		end
		summary = s
		render()
		setOpen(true)
	end)
	UITheme.changed:connect(function(reason: string)
		if reason == "phase" then
			local phase = UITheme.phase()
			if gui.Enabled and (phase == "Loadout" or phase == "Running") then
				setOpen(false)
			end
		elseif reason == "lang" and gui.Enabled then
			render()
		end
	end)
end

return EndScreen
