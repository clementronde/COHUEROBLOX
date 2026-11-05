--!strict
-- Level-up window v3 « vraies briques » (Figma L04 / L04b / L04c ; dossier 60, section 0.0 bis).
-- The world pales and freezes, rays turn behind a centred window: 3 offers, Reroll / Skip / Banish
-- with their charges, inventory on the left, stats on the right (the stat the selected offer
-- changes lights up in green with its future value). Picking flies the icon into its cell.
-- Coop: the chooser sees a countdown in the title bar; the others see « SAM LEVELED UP! ».
--
-- Template: StarterGui.COHUE_LevelUp + COHUE_Freeze, ReplicatedStorage.Assets.UI.LevelUpFreeze
-- (tools/ui/build-ui-v3.luau). This module finds, fills and animates them; it builds nothing.
-- Listens: CardOffer, Build, PlayerProgress, optional LevelUpPause (A04). Sends: CardChoice.
-- Input: hover (mouse) or focus (gamepad) selects, click / A picks; touch: tap selects, tap again
-- picks; Card1-3 actions (UIInput) pick at once; keys R / X / B on PC. Cards ignore input 0.4 s
-- after they appear. The real global pause belongs to A04 (contract request LevelUpPause): until
-- it exists the server keeps its 8 s offer and the countdown shows in the title bar.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local UITheme = require(script.Parent:WaitForChild("UITheme"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))
local UIInput = require(script.Parent:WaitForChild("UIInput"))

local Config = UITheme.Config
local S = UITheme.S
local C = Config.Cards
local LOCAL = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)

local CardUI = {}

type OfferView = {
	root: Frame,
	pop: UIScale,
	select: Frame,
	icon: ImageLabel,
	initials: TextLabel,
	title: TextLabel,
	line: TextLabel,
	tag: UIKit.Tag,
	rarity: TextLabel,
	key: Frame,
	keyLabel: TextLabel,
	veil: Frame,
	banTag: UIKit.Tag,
	confirm: UIKit.Tag,
	hit: TextButton,
}

type ActionView = { root: Frame, pop: UIScale, label: TextLabel, count: UIKit.Tag, key: Frame, hit: TextButton, color: string }
type CellView = { frame: Frame, slot: Frame, icon: ImageLabel, initials: TextLabel, level: TextLabel, pop: UIScale }
type RowView = { frame: Frame, glow: Frame, name: TextLabel, value: TextLabel, up: Frame }

---------------------------------------------------------------------------- template
local gui: ScreenGui
local freeze: ScreenGui
local zone: Frame
local zoneScale: UIScale
local window: Frame
local windowPop: UIScale
local inventory: Frame
local inventoryPop: UIScale
local stats: Frame
local statsPop: UIScale
local titleLabel: TextLabel
local timerBox: Frame
local timerText: TextLabel
local timeBar: UIKit.Bar
local frozenLine: TextLabel
local offers: { OfferView } = {}
local actions: { [string]: ActionView } = {}
local weaponCells: { CellView } = {}
local runeCells: { CellView } = {}
local itemCells: { CellView } = {}
local rows: { RowView } = {}
local moreLabel: TextLabel
local scrim: Frame
local rays: ImageLabel
local waitBox: Frame
local waitPop: UIScale
local waitTitle: TextLabel
local waitPortrait: ImageLabel
local waitInitial: TextLabel
local waitLine1: TextLabel
local waitLine2: TextLabel
local waitBar: UIKit.Bar
local statics: { { label: TextLabel, key: string } } = {}
local scrimAlpha = 0.72
local raysAlpha = 0.8

---------------------------------------------------------------------------- state
local offer: any = nil
local expiresAt = 0
local total = 0
local armedAt = 0
local locked = false
local banMode = false
local selected = 1
local touchArmed: number? = nil
local lastSecond = -1
local windowShown = false
local openGen = 0
local flyingUntil = 0
local pause: any = nil -- last active LevelUpPause payload
local pauseEndsAt = 0
local pauseTotal = 0
local waitUserId: number? = nil
local freezeOn = false
local cc: ColorCorrectionEffect? = nil
local stepConn: RBXScriptConnection? = nil

local KIND_CONFIG: { [string]: string } = {
	NewWeapon = "Weapons",
	WeaponUp = "Weapons",
	NewGrimoire = "Grimoires",
	GrimoireUp = "Grimoires",
	NewRune = "Grimoires",
	RuneUp = "Grimoires",
	CompanionTech = "Companions",
	CompanionTechUp = "Companions",
	CompanionTreat = "Companions",
}

local LAND = { size = Vector2.new(760, 396), inv = UDim2.fromOffset(0, 38), win = UDim2.fromOffset(190, 0), stats = UDim2.fromOffset(580, 38) }
local PORT = { size = Vector2.new(380, 700), inv = UDim2.fromOffset(0, 396), win = UDim2.fromOffset(0, 0), stats = UDim2.fromOffset(200, 396) }

---------------------------------------------------------------------------- helpers
local function reduced(): boolean
	return UITheme.flashesReduced()
end

local function tween(obj: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

-- « Clic de brique » : la brique s'enfonce puis remonte avec un rebond.
local function press(pop: UIScale)
	if reduced() then
		return
	end
	pop.Scale = 0.92
	tween(pop, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
end

local function isRune(kind: any): boolean
	return kind == "NewGrimoire" or kind == "GrimoireUp" or kind == "NewRune" or kind == "RuneUp"
end

local function isWeapon(kind: any): boolean
	return kind == "NewWeapon" or kind == "WeaponUp"
end

local function build(): any
	local b = UITheme.last("Build")
	return if type(b) == "table" then b else {}
end

local function runesOf(b: any): any
	return b.runes or b.grimoires
end

local function levelIn(list: any, id: string): number
	if type(list) == "table" then
		for _, e in list do
			if type(e) == "table" and e.id == id then
				return tonumber(e.level) or 1
			end
		end
	end
	return 0
end

local function upper(value: any, args: { [string]: any }?): string
	return string.upper(UITheme.format(value, args))
end

local function initialsOf(text: string): string
	local caps = string.gsub(text, "[^%u]", "")
	if #caps >= 2 then
		return string.sub(caps, 1, 2)
	end
	local letters = string.gsub(text, "[^%a]", "")
	return string.upper(string.sub(letters, 1, 2))
end

local function cardTexts(card: any): (any, any)
	local configName = KIND_CONFIG[card.kind]
	local title: any = card.title
	local desc: any = card.desc
	if configName and type(card.id) == "string" then
		local def = UITheme.def(configName, card.id)
		if def then
			if type(def.name) == "table" or type(def.name) == "string" then
				title = def.name
			end
			-- Upgrades keep the server text (it says what changes); the others take the translated
			-- config text (the companion server sends its French text for new techs).
			local isUp = string.sub(tostring(card.kind), -2) == "Up"
			if (not isUp or desc == nil or desc == "") and (type(def.desc) == "table" or type(def.desc) == "string") then
				desc = def.desc
			end
		end
	end
	if title == nil or title == "" then
		title = card.id or "?"
	end
	return title, desc or ""
end

---------------------------------------------------------------------------- stats
local function fmtNum(n: number): string
	if math.abs(n - math.round(n)) < 1e-6 then
		return tostring(math.round(n))
	end
	return string.format("%.1f", n)
end

local function statValue(stat: string, v: number): string
	if stat == "Regen" then
		return fmtNum(v) .. "/s"
	elseif stat == "CritChance" or stat == "Dodge" or stat == "Thorns" then
		return tostring(math.round(v * 100)) .. "%"
	elseif stat == "Cooldown" then
		local p = math.round(v * 100)
		return if p == 0 then "0%" else "-" .. tostring(p) .. "%"
	end
	local def = (Config.Stats :: any)[stat]
	if def and def.pct then
		local p = math.round(v * 100)
		return if p > 0 then "+" .. tostring(p) .. "%" else tostring(p) .. "%"
	elseif stat == "Amount" or stat == "Bounces" then
		local n = math.round(v)
		return if n > 0 then "+" .. tostring(n) else tostring(n)
	end
	return fmtNum(v)
end

local function statName(stat: string): string
	local short = (Config.StatShort :: any)[stat]
	if short then
		return UITheme.format(short)
	end
	local def = (Config.Stats :: any)[stat]
	return if def then UITheme.format(def.name) else stat
end

-- Stat changes of a Rune offer (from its current level to the offered one). Weapons change no stat.
local function previewDeltas(card: any): { [string]: number }
	local out: { [string]: number } = {}
	if type(card) ~= "table" or not isRune(card.kind) or type(card.id) ~= "string" then
		return out
	end
	local cfg = UITheme.config("Grimoires")
	local def = cfg and type(cfg.Defs) == "table" and cfg.Defs[card.id]
	if not def or type(cfg.valueAt) ~= "function" then
		return out
	end
	local from = levelIn(runesOf(build()), card.id)
	local to = tonumber(card.level) or (from + 1)
	local keys: { [string]: boolean } = {}
	for stat in def.perLevel or {} do
		keys[stat] = true
	end
	for stat in def.byLevel or {} do
		keys[stat] = true
	end
	for stat in keys do
		local ok, d = pcall(function()
			return cfg.valueAt(def, stat, to) - cfg.valueAt(def, stat, from)
		end)
		if ok and type(d) == "number" and d ~= 0 then
			out[stat] = d
		end
	end
	return out
end

local function renderStats()
	local b = build()
	local cur: any = if type(b.stats) == "table" then b.stats else {}
	local cfg = UITheme.config("Grimoires")
	local base: any = if cfg and type(cfg.BaseStats) == "table" then cfg.BaseStats else {}
	local caps: any = if cfg and type(cfg.StatCaps) == "table" then cfg.StatCaps else {}
	local card = if offer and type(offer.cards) == "table" and not banMode then offer.cards[selected] else nil
	local deltas = previewDeltas(card)

	local portrait = UITheme.isPortrait()
	local limit = math.min(#rows, if portrait then C.PortraitRows else #C.StatRows)
	local listed: { string } = {}
	for i = 1, limit do
		listed[i] = C.StatRows[i]
	end
	-- A changed stat that is not listed takes the place of the last rows that do not change.
	local extra: { string } = {}
	for stat in deltas do
		if not table.find(listed, stat) then
			table.insert(extra, stat)
		end
	end
	table.sort(extra)
	local free: { number } = {}
	for i = limit, 1, -1 do
		if deltas[listed[i]] == nil then
			table.insert(free, i)
		end
	end
	for k, stat in extra do
		local i = free[k]
		if i then
			listed[i] = stat
		end
	end

	for i, row in rows do
		local stat = listed[i]
		row.frame.Visible = stat ~= nil
		if stat then
			local now = tonumber(cur[stat]) or tonumber(base[stat]) or 0
			local d = deltas[stat]
			row.name.Text = statName(stat)
			if d then
				local future = now + d
				local cap = tonumber(caps[stat])
				if cap and future > cap then
					future = cap
				end
				if stat == "MaxHp" then
					future = math.floor(future + 0.5)
				end
				row.value.Text = statValue(stat, future)
			else
				row.value.Text = statValue(stat, now)
			end
			row.glow.Visible = d ~= nil
			row.up.Visible = d ~= nil and d > 0
		end
	end
	local hidden = #C.StatRows - limit
	moreLabel.Visible = portrait and hidden > 0
	moreLabel.Text = UITheme.format(S.MoreStats, { n = hidden })
end

---------------------------------------------------------------------------- inventory
local function fillCell(c: CellView, configName: string, entry: any, under: string)
	local img = UIKit.icon(entry.id)
	c.icon.Image = img
	c.icon.Visible = img ~= ""
	c.initials.Text = initialsOf(UITheme.format(UITheme.nameOf(configName, entry.id)))
	c.initials.Visible = img == ""
	c.level.Text = under
	c.level.Visible = true
	UIKit.tint(c.slot, "Cream")
end

local function emptyCell(c: CellView)
	c.icon.Visible = false
	c.initials.Visible = false
	c.level.Visible = false
	UIKit.tint(c.slot, "Plum")
end

local function fillSlots(cells: { CellView }, entries: any, count: number, configName: string)
	local n = if type(entries) == "table" then #entries else 0
	local shown = math.clamp(math.max(count, n), 0, #cells)
	for i, c in cells do
		c.frame.Visible = i <= shown
		local e = if type(entries) == "table" then entries[i] else nil
		if type(e) == "table" and type(e.id) == "string" then
			fillCell(c, configName, e, "Lv" .. tostring(e.level or 1))
		else
			emptyCell(c)
		end
	end
end

local function renderInventory()
	local b = build()
	local wCount = tonumber(b.weaponSlots) or 0
	local rCount = tonumber(b.runeSlots or b.grimoireSlots) or 0
	fillSlots(weaponCells, b.weapons, wCount, "Weapons")
	fillSlots(runeCells, runesOf(b), rCount, "Grimoires")
	-- Objets : seulement ceux qu'on a ; « +N » dans la dernière case s'il y en a trop.
	local items = if type(b.items) == "table" then b.items else {}
	local limit = math.min(#itemCells, if wCount > 4 or rCount > 4 then 4 else C.ItemsShown)
	local overflow = #items > limit
	for i, c in itemCells do
		local e = items[i]
		c.frame.Visible = i <= math.min(#items, limit)
		if overflow and i == limit then
			emptyCell(c)
			c.initials.Text = "+" .. tostring(#items - limit + 1)
			c.initials.Visible = true
		elseif type(e) == "table" and type(e.id) == "string" then
			fillCell(c, "Items", e, "x" .. tostring(e.count or 1))
		else
			emptyCell(c)
		end
	end
end

---------------------------------------------------------------------------- offers
local function renderActions()
	local touch = UITheme.isTouch()
	for name, field in { Reroll = "reroll", Skip = "skip", Banish = "banish" } do
		local a = actions[name]
		local n = tonumber(offer and offer[field]) or 0
		local cancel = name == "Banish" and banMode
		a.count.label.Text = tostring(n)
		a.count.frame.Visible = not cancel
		a.key.Visible = not touch
		local usable = offer ~= nil and not locked and (n > 0 or cancel)
		UIKit.tint(a.root, if usable then a.color else "Plum")
		a.label.TextTransparency = if usable then 0 else 0.45
		a.hit.Active = usable
		a.hit.Selectable = usable
		if name == "Banish" then
			a.label.Text = upper(if cancel then S.Cancel else S.Ban)
		else
			a.label.Text = upper(if name == "Reroll" then S.Reroll else S.Skip)
		end
	end
	actions.Reroll.root.Visible = not banMode
	actions.Skip.root.Visible = not banMode
end

local function renderSelection(animate: boolean)
	for i, v in offers do
		local on = offer ~= nil and i == selected and not banMode
		v.select.Visible = on
		v.confirm.frame.Visible = on and touchArmed == i
		v.veil.Visible = banMode
		v.banTag.frame.Visible = banMode
		local target = if on then 1.03 else 1
		if animate and not reduced() then
			tween(v.pop, 0.12, { Scale = target })
		else
			v.pop.Scale = target
		end
	end
	renderStats()
end

local function fillOffer(v: OfferView, card: any, i: number)
	v.root.Visible = type(card) == "table"
	if type(card) ~= "table" then
		return
	end
	local rarity = UITheme.rarityToken(if type(card.rarity) == "string" then card.rarity else nil)
	UIKit.tint(v.root, (C.Rarity :: any)[rarity] or "Royal")
	v.rarity.Text = upper((Config.Rarity :: any)[rarity].name)
	local title, desc = cardTexts(card)
	v.title.Text = UITheme.format(title)
	v.line.Text = UITheme.format(desc)
	local img = UIKit.icon(if type(card.id) == "string" then card.id else nil)
	v.icon.Image = img
	v.icon.Visible = img ~= ""
	v.initials.Text = initialsOf(v.title.Text)
	v.initials.Visible = img == ""

	local kind = tostring(card.kind)
	if string.sub(kind, 1, 9) == "Companion" then
		v.tag.setTone("Sky")
		v.tag.label.Text = UITheme.format(S.CompanionTag)
		v.tag.frame.Visible = true
	elseif string.sub(kind, 1, 3) == "New" then
		v.tag.setTone("Tomato")
		v.tag.label.Text = UITheme.format(S.NewTag)
		v.tag.frame.Visible = true
	elseif kind == "Heal" or kind == "Coins" then
		v.tag.frame.Visible = false
	else
		local b = build()
		local from = if isWeapon(kind) then levelIn(b.weapons, card.id) elseif isRune(kind) then levelIn(runesOf(b), card.id) else 0
		v.tag.setTone("Plum")
		v.tag.label.Text = UITheme.format(S.LevelFromTo, { a = math.max(from, 1), b = card.level or (from + 1) })
		v.tag.frame.Visible = true
	end

	local touch = UITheme.isTouch()
	v.key.Visible = not touch
	v.keyLabel.Text = if touch then tostring(i) else (UIInput.hint("Card" .. i, tostring(i)) or tostring(i))
	v.hit.Active = not locked
end

local function render()
	local cards = if offer and type(offer.cards) == "table" then offer.cards else {}
	local progress = UITheme.last("PlayerProgress")
	local level = if type(progress) == "table" then progress.level else nil
	titleLabel.Text = if level then UITheme.format(S.LevelTitle, { n = level }) else UITheme.format(S.LevelUp)
	for i, v in offers do
		fillOffer(v, cards[i], i)
	end
	if type(cards[selected]) ~= "table" then
		selected = 1
	end
	timerBox.Visible = total > 0
	timeBar.frame.Visible = total > 0
	frozenLine.Visible = pause ~= nil and #Players:GetPlayers() > 1
	renderActions()
	renderInventory()
	renderSelection(false)
end

---------------------------------------------------------------------------- layout
local function layout()
	if not zone then
		return
	end
	local portrait = UITheme.isPortrait()
	local L = if portrait then PORT else LAND
	zone.Size = UDim2.fromOffset(L.size.X, L.size.Y)
	inventory.Position = L.inv
	window.Position = L.win
	stats.Position = L.stats
	-- Tout doit tenir dans la zone sûre : échelle de l'appareil, réduite si l'écran est petit.
	local avail = gui.AbsoluteSize
	local fit = math.min((avail.X - 24) / L.size.X, (avail.Y - 12) / L.size.Y)
	zoneScale.Scale = math.clamp(math.min(UITheme.scale(), fit), 0.5, 2)
	if offer then
		renderStats()
	end
end

---------------------------------------------------------------------------- freeze effect
local function step(dt: number)
	if freezeOn and not reduced() then
		rays.Rotation = (rays.Rotation + dt * 6) % 360
	end
	if offer and total > 0 then
		local left = expiresAt - os.clock()
		timeBar.set(left / total)
		local sec = math.max(0, math.ceil(left))
		if sec ~= lastSecond then
			lastSecond = sec
			timerText.Text = UITheme.format(S.Seconds, { n = sec })
			timerText.TextColor3 = if left <= C.WarnSeconds then UIKit.tone("Tomato.l") else WHITE
		end
		if left <= -1 then
			-- The server auto-picks at expiry and should send `closed`; never leave a stale offer up.
			CardUI.close()
		end
	end
	if waitBox.Visible and pauseTotal > 0 then
		local left = math.max(0, pauseEndsAt - os.clock())
		waitBar.set(left / pauseTotal)
		waitLine2.Text = UITheme.format(S.FrozenBack, { n = math.ceil(left) })
	end
end

local function setFreeze(on: boolean)
	if on == freezeOn then
		return
	end
	freezeOn = on
	if on then
		freeze.Enabled = true
		scrim.BackgroundTransparency = 1
		rays.ImageTransparency = 1
		tween(scrim, 0.2, { BackgroundTransparency = scrimAlpha })
		tween(rays, 0.35, { ImageTransparency = raysAlpha })
		if not cc then
			local fx = UIKit.clone("LevelUpFreeze")
			if fx and fx:IsA("ColorCorrectionEffect") then
				fx.Parent = Workspace.CurrentCamera
				cc = fx
			end
		end
		local fx = cc
		if fx then
			tween(fx, 0.25, {
				Saturation = tonumber(fx:GetAttribute("Saturation")) or -0.7,
				Brightness = tonumber(fx:GetAttribute("Brightness")) or 0.06,
				Contrast = tonumber(fx:GetAttribute("Contrast")) or -0.12,
			})
		end
		if not stepConn then
			stepConn = RunService.RenderStepped:Connect(step)
		end
	else
		tween(scrim, 0.15, { BackgroundTransparency = 1 })
		tween(rays, 0.15, { ImageTransparency = 1 })
		local fx = cc
		cc = nil
		if fx then
			tween(fx, 0.2, { Saturation = 0, Brightness = 0, Contrast = 0 })
			task.delay(0.25, function()
				fx:Destroy()
			end)
		end
		task.delay(0.2, function()
			if not freezeOn then
				freeze.Enabled = false
				if stepConn then
					stepConn:Disconnect()
					stepConn = nil
				end
			end
		end)
	end
end

---------------------------------------------------------------------------- show / hide
local function clearSelection()
	local sel = GuiService.SelectedObject
	if sel and sel:IsDescendantOf(gui) then
		GuiService.SelectedObject = nil
	end
end

-- Coop : un équipier choisit, je n'ai pas d'offre -> fenêtre « SAM LEVELED UP! ».
local function waitingFor(): number?
	if not pause or offer or windowShown or not UITheme.inRun() then
		return nil
	end
	local choosers = if type(pause.choosers) == "table" then pause.choosers else {}
	for _, id in choosers do
		local uid = tonumber(if type(id) == "table" then id.userId else id)
		if uid and uid ~= LOCAL.UserId then
			return uid
		end
	end
	return nil
end

local function fillWait(uid: number)
	local p = Players:GetPlayerByUserId(uid)
	local name = if p then p.DisplayName else "?"
	waitTitle.Text = upper(S.MateLeveled, { name = name })
	waitLine1.Text = UITheme.format(S.MatePicking, { name = name })
	-- Sans fin annoncée, pas de compte à rebours (ni ligne « Back in 12s », ni barre).
	waitLine2.Visible = pauseTotal > 0
	waitBar.frame.Visible = pauseTotal > 0
	if waitUserId ~= uid then
		waitUserId = uid
		waitInitial.Text = string.upper(string.sub(name, 1, 1))
		waitInitial.Visible = true
		waitPortrait.Image = ""
		task.spawn(function()
			local ok, img = pcall(function()
				return Players:GetUserThumbnailAsync(uid, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
			end)
			if ok and waitUserId == uid then
				waitPortrait.Image = img
				waitInitial.Visible = false
			end
		end)
	end
end

local function refresh()
	local uid = waitingFor()
	local showWait = uid ~= nil
	if showWait then
		fillWait(uid :: number)
		if not waitBox.Visible then
			waitBox.Visible = true
			if not reduced() then
				waitPop.Scale = 0.86
				tween(waitPop, 0.24, { Scale = 1 }, Enum.EasingStyle.Back)
			end
		end
	else
		waitBox.Visible = false
		waitUserId = nil
	end
	local any = windowShown or showWait
	gui.Enabled = any
	setFreeze(any)
	UITheme.setFlag("cardsOpen", any)
end

local function openWindow()
	windowShown = true
	openGen += 1
	window.Visible = true
	inventory.Visible = true
	stats.Visible = true
	layout()
	refresh()
	if not reduced() then
		windowPop.Scale = 0.86
		tween(windowPop, 0.24, { Scale = 1 }, Enum.EasingStyle.Back)
		inventoryPop.Scale = 0.9
		statsPop.Scale = 0.9
		tween(inventoryPop, 0.28, { Scale = 1 }, Enum.EasingStyle.Back)
		tween(statsPop, 0.28, { Scale = 1 }, Enum.EasingStyle.Back)
		for i, v in offers do
			v.pop.Scale = 0.8
			task.delay(0.04 * i, function()
				tween(v.pop, 0.2, { Scale = if i == selected then 1.03 else 1 }, Enum.EasingStyle.Back)
			end)
		end
	end
	if UserInputService.PreferredInput == Enum.PreferredInput.Gamepad then
		GuiService.SelectedObject = offers[selected].hit
	end
end

local function closeWindow()
	local gen = openGen
	local function done()
		if openGen ~= gen or offer then
			return
		end
		windowShown = false
		window.Visible = false
		inventory.Visible = false
		stats.Visible = false
		clearSelection()
		refresh()
	end
	local delay = math.max(0, flyingUntil - os.clock())
	if reduced() then
		task.delay(delay, done)
		return
	end
	task.delay(delay, function()
		if openGen ~= gen or offer then
			return
		end
		tween(windowPop, 0.12, { Scale = 0.9 })
		tween(inventoryPop, 0.12, { Scale = 0.9 })
		tween(statsPop, 0.12, { Scale = 0.9 })
		task.delay(0.12, done)
	end)
end

---------------------------------------------------------------------------- pick animation
local function targetCell(card: any): CellView?
	if type(card) ~= "table" or type(card.id) ~= "string" then
		return nil
	end
	local b = build()
	local cells: { CellView }, list: any
	if isWeapon(card.kind) then
		cells, list = weaponCells, b.weapons
	elseif isRune(card.kind) then
		cells, list = runeCells, runesOf(b)
	else
		return nil
	end
	local n = if type(list) == "table" then #list else 0
	local index = n + 1
	if type(list) == "table" then
		for i, e in list do
			if type(e) == "table" and e.id == card.id then
				index = i
				break
			end
		end
	end
	local c = cells[index]
	return if c and c.frame.Visible then c else nil
end

-- L'icône choisie vole dans sa case d'inventaire (clone de l'icône de la carte).
local function fly(index: number)
	local card = offer and type(offer.cards) == "table" and offer.cards[index]
	local v = offers[index]
	local target = targetCell(card)
	if reduced() or not v or not target or not v.icon.Visible then
		return
	end
	local scale = math.max(zoneScale.Scale, 0.01)
	local origin = zone.AbsolutePosition
	local function centre(obj: GuiObject, k: number): (UDim2, UDim2)
		local c = (obj.AbsolutePosition + obj.AbsoluteSize / 2 - origin) / scale
		local s = obj.AbsoluteSize * k / scale
		return UDim2.fromOffset(c.X, c.Y), UDim2.fromOffset(s.X, s.Y)
	end
	local ghost = v.icon:Clone()
	ghost.Name = "Flying"
	ghost.AnchorPoint = Vector2.new(0.5, 0.5)
	ghost.ZIndex = 20
	ghost.Position, ghost.Size = centre(v.icon, 1)
	ghost.Parent = zone
	local toPos, toSize = centre(target.slot, 0.83)
	tween(ghost, C.FlySeconds, { Position = toPos, Size = toSize }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	flyingUntil = os.clock() + C.FlySeconds + 0.15
	local image = v.icon.Image
	local level = tonumber(card.level) or 1
	task.delay(C.FlySeconds, function()
		ghost:Destroy()
		target.icon.Image = image
		target.icon.Visible = true
		target.initials.Visible = false
		target.level.Text = "Lv" .. tostring(level)
		target.level.Visible = true
		UIKit.tint(target.slot, "Cream")
		target.pop.Scale = 1.3
		tween(target.pop, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
end

---------------------------------------------------------------------------- network
local function send(action: string, index: number?)
	if not offer or locked then
		return
	end
	locked = true
	local id = offer.offerId
	if action == "pick" and index then
		fly(index)
	end
	Net.event("CardChoice"):FireServer(id, action, index)
	renderActions()
	-- If the server refuses (no charges left), unlock so the player can still pick.
	task.delay(1, function()
		if offer and offer.offerId == id and locked then
			locked = false
			renderActions()
		end
	end)
end

local function onOffer(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if payload.closed then
		if offer ~= nil and (payload.offerId == nil or payload.offerId == offer.offerId) then
			CardUI.close()
		end
		return
	end
	if type(payload.cards) ~= "table" or not UITheme.inRun() then
		return
	end
	local isNew = offer == nil
	offer = payload
	locked = false
	banMode = false
	touchArmed = nil
	total = math.max(0, tonumber(payload.expiresIn) or 0)
	expiresAt = os.clock() + total
	lastSecond = -1
	if isNew then
		selected = 1
		armedAt = os.clock() + C.ArmSeconds
		flyingUntil = 0
	end
	render()
	if isNew then
		openWindow()
	else
		-- Reroll : nouvelles cartes, petit rebond.
		for _, v in offers do
			press(v.pop)
		end
	end
end

local function onPause(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if payload.active then
		pause = payload
		pauseTotal = math.max(0, tonumber(payload.endsIn) or 0)
		pauseEndsAt = os.clock() + pauseTotal
	else
		pause = nil
	end
	if offer then
		frozenLine.Visible = pause ~= nil and #Players:GetPlayers() > 1
	end
	refresh()
end

---------------------------------------------------------------------------- public
function CardUI.isOpen(): boolean
	return offer ~= nil
end

function CardUI.close()
	if not offer then
		return
	end
	offer = nil
	banMode = false
	locked = false
	touchArmed = nil
	closeWindow()
end

function CardUI.select(index: number)
	if not offer or banMode or type(offer.cards) ~= "table" or offer.cards[index] == nil or selected == index then
		return
	end
	selected = index
	if touchArmed ~= index then
		touchArmed = nil
	end
	renderSelection(true)
end

function CardUI.choose(index: number)
	if not offer or locked or type(offer.cards) ~= "table" or offer.cards[index] == nil then
		return
	end
	if os.clock() < armedAt then
		return -- inert window: a thumb that was already on the screen must not pick a card
	end
	press(offers[index].pop)
	if banMode then
		banMode = false
		send("ban", index)
		renderSelection(true)
	else
		selected = index
		send("pick", index)
	end
end

-- Toucher : 1er toucher = sélection (« TAP AGAIN »), 2e = choix. Souris et manette : choix direct.
local function onCardTap(index: number)
	if not offer or locked or os.clock() < armedAt then
		return
	end
	if not banMode and UITheme.isTouch() and touchArmed ~= index then
		selected = index
		touchArmed = index
		press(offers[index].pop)
		renderSelection(true)
		return
	end
	CardUI.choose(index)
end

function CardUI.reroll()
	if offer and (tonumber(offer.reroll) or 0) > 0 then
		press(actions.Reroll.pop)
		send("reroll")
	end
end

function CardUI.skip()
	if offer and (tonumber(offer.skip) or 0) > 0 then
		press(actions.Skip.pop)
		send("skip")
	end
end

function CardUI.toggleBan()
	if not offer or locked then
		return
	end
	if banMode then
		banMode = false
	elseif (tonumber(offer.banish) or 0) > 0 then
		banMode = true
		touchArmed = nil
	else
		return
	end
	press(actions.Banish.pop)
	renderActions()
	renderSelection(true)
end

---------------------------------------------------------------------------- binding
local missing = 0
local function need(root: Instance?, path: string): any
	local found = UIKit.find(root, path)
	if found == nil then
		missing += 1
	end
	return found
end

local function bindCell(c: Frame?): CellView
	return {
		frame = c :: Frame,
		slot = need(c, "Slot"),
		icon = need(c, "Slot.Icon"),
		initials = need(c, "Slot.Initials"),
		level = need(c, "Level"),
		pop = need(c, "Slot.PopScale"),
	}
end

local function bind(): boolean
	local g = UIKit.screen("COHUE_LevelUp")
	local f = UIKit.screen("COHUE_Freeze")
	if not g or not f then
		return false
	end
	gui = g
	freeze = f
	zone = need(g, "Center")
	zoneScale = need(g, "Center.Scale")
	window = need(g, "Center.Window")
	windowPop = need(g, "Center.Window.PopScale")
	inventory = need(g, "Center.Inventory")
	inventoryPop = need(g, "Center.Inventory.PopScale")
	stats = need(g, "Center.Stats")
	statsPop = need(g, "Center.Stats.PopScale")
	titleLabel = need(window, "Header.Title")
	timerBox = need(window, "Header.Timer")
	timerText = need(window, "Header.Timer.Seconds")
	timeBar = UIKit.bar(need(window, "TimeBar"))
	frozenLine = need(window, "Frozen")
	for i = 1, 3 do
		local root = need(window, "Offers.Offer" .. i)
		offers[i] = {
			root = root,
			pop = need(root, "PopScale"),
			select = need(root, "Select"),
			icon = need(root, "Icon"),
			initials = need(root, "Initials"),
			title = need(root, "Title"),
			line = need(root, "Line"),
			tag = UIKit.tag(need(root, "Tag")),
			rarity = need(root, "Rarity"),
			key = need(root, "Key"),
			keyLabel = need(root, "Key.Label"),
			veil = need(root, "Veil"),
			banTag = UIKit.tag(need(root, "BanTag")),
			confirm = UIKit.tag(need(root, "Confirm")),
			hit = need(root, "Hit"),
		}
	end
	for name, color in { Reroll = "Royal", Skip = "Stone", Banish = "Tomato" } do
		local root = need(window, "Actions." .. name)
		actions[name] = {
			root = root,
			pop = need(root, "PopScale"),
			label = need(root, "Label"),
			count = UIKit.tag(need(root, "Count")),
			key = need(root, "Key"),
			hit = need(root, "Hit"),
			color = color,
		}
	end
	local body = need(inventory, "Body")
	for i = 1, 6 do
		weaponCells[i] = bindCell(need(body, "Weapons.Cell" .. i))
		runeCells[i] = bindCell(need(body, "Runes.Cell" .. i))
	end
	for i = 1, 8 do
		itemCells[i] = bindCell(need(body, "Items.Cell" .. i))
	end
	local sbody = need(stats, "Body")
	for i = 1, #C.StatRows do
		local r = UIKit.find(sbody, "Row" .. i)
		if not r then
			break -- the template has fewer rows than the config: show what fits
		end
		table.insert(rows, { frame = r, glow = need(r, "Glow"), name = need(r, "Name"), value = need(r, "Right.Value"), up = need(r, "Right.Up") })
	end
	moreLabel = need(sbody, "More")
	scrim = need(f, "Scrim")
	rays = need(f, "Rays")
	waitBox = need(g, "Center.Wait")
	waitPop = need(waitBox, "PopScale")
	waitTitle = need(waitBox, "Header.Title")
	waitPortrait = need(waitBox, "Portrait")
	waitInitial = need(waitBox, "Portrait.Initial")
	waitLine1 = need(waitBox, "Body.Line1")
	waitLine2 = need(waitBox, "Body.Line2")
	waitBar = UIKit.bar(need(waitBox, "Body.Bar"))
	statics = {
		{ label = need(inventory, "Header.Title"), key = "Inventory" },
		{ label = need(stats, "Header.Title"), key = "StatsTitle" },
		{ label = need(body, "WeaponsTitle"), key = "WeaponsTitle" },
		{ label = need(body, "RunesTitle"), key = "RunesTitle" },
		{ label = need(body, "ItemsTitle"), key = "ItemsTitle" },
		{ label = frozenLine, key = "FrozenChoose" },
	}
	if missing > 0 or #rows == 0 then
		return false
	end
	scrimAlpha = scrim.BackgroundTransparency
	raysAlpha = rays.ImageTransparency
	return true
end

local function setStatics()
	for _, s in statics do
		s.label.Text = UITheme.format((S :: any)[s.key])
	end
	for _, v in offers do
		v.banTag.label.Text = UITheme.format(S.BanTag)
		v.confirm.label.Text = UITheme.format(S.TapAgain)
	end
end

function CardUI.start()
	if not bind() then
		warn("[CardUI] gabarit v3 absent ou incomplet : lancer tools/ui/build-ui-v3.luau dans Studio (place COHUE). Fenêtre de niveau inactive.")
		return
	end
	gui.Enabled = false
	freeze.Enabled = false
	window.Visible = false
	inventory.Visible = false
	stats.Visible = false
	waitBox.Visible = false
	setStatics()

	for i, v in offers do
		v.hit.Activated:Connect(function()
			onCardTap(i)
		end)
		v.hit.MouseEnter:Connect(function()
			if not UITheme.isTouch() then
				CardUI.select(i)
			end
		end)
		v.hit.SelectionGained:Connect(function()
			CardUI.select(i)
		end)
	end
	actions.Reroll.hit.Activated:Connect(CardUI.reroll)
	actions.Skip.hit.Activated:Connect(CardUI.skip)
	actions.Banish.hit.Activated:Connect(CardUI.toggleBan)

	for i = 1, 3 do
		UIInput.onAction("Card" .. i, function(pressed: boolean)
			if pressed then
				CardUI.choose(i)
			end
		end)
	end
	-- PC shortcuts R / X / B (not S: WASD stays on the character).
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not offer then
			return
		end
		if input.KeyCode == Enum.KeyCode.R then
			CardUI.reroll()
		elseif input.KeyCode == Enum.KeyCode.X then
			CardUI.skip()
		elseif input.KeyCode == Enum.KeyCode.B then
			CardUI.toggleBan()
		end
	end)

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	layout()
	UITheme.changed:connect(function(reason: string)
		if reason == "phase" then
			if not UITheme.inRun() then
				pause = nil
				CardUI.close()
				refresh()
			end
		elseif reason == "device" or reason == "scale" then
			layout()
			if offer then
				render()
			end
		elseif reason == "lang" or reason == "palette" then
			setStatics()
			if offer then
				render()
			end
		end
	end)
	UITheme.watch("CardOffer", onOffer)
	UITheme.watch("Build", function()
		if offer then
			renderInventory()
			renderStats()
		end
	end)

	-- Optional remote (A04): hooked if it exists or appears later; nothing waits on it.
	local function hook(r: Instance)
		if r.Name == C.PauseRemote and r:IsA("RemoteEvent") then
			r.OnClientEvent:Connect(onPause)
		end
	end
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes") -- published by Net once the server is wired
		local r = remotes:FindFirstChild(C.PauseRemote)
		if r then
			hook(r)
		else
			remotes.ChildAdded:Connect(hook)
		end
	end)
end

return CardUI
