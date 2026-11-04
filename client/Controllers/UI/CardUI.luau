--!strict
-- Level-up cards v2 (Figma L04 / P04 / C04): 3 glossy rarity cards at the bottom, no pause in coop
-- (the player is slowed and invulnerable), 8 s ring, Reroll / Skip / Banish with uses left.
-- Rarity reads without colour: word in the header, 1-4 diamonds, frame thickness 3/4/5/6,
-- Legendary rays. Portrait phone: cards become 366x98 rows. Cards are inert 0.4 s after appearing.
-- Design: docs/dossier/60-ui-ux.md sections 0 and 4. Listens: CardOffer. Sends: CardChoice.
-- Input: InputController actions Card1-Card3 (via UIInput), touch / click, keys R / X / B on PC.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local UITheme = require(script.Parent:WaitForChild("UITheme"))
local UIInput = require(script.Parent:WaitForChild("UIInput"))

local Config = UITheme.Config
local S = UITheme.S
local C = Config.Cards

local CardUI = {}

type CardView = {
	root: TextButton,
	ink: UIStroke,
	shine: Frame,
	body: Frame,
	rarity: TextLabel,
	tag: UITheme.Pill,
	chipLip: Frame,
	chipFace: Frame,
	chipShine: Frame,
	initials: TextLabel,
	gems: Frame,
	rays: Frame?,
	title: TextLabel,
	desc: TextLabel,
	key: Frame,
	veil: Frame,
	banMark: TextLabel,
	banTag: UITheme.Pill,
	row: boolean,
}

type ActionBtn = { holder: Frame, gloss: UITheme.Gloss, count: TextLabel, key: Frame }

local gui: ScreenGui
local zone: Frame
local plate: Frame
local titleLabel: TextLabel
local topRow: Frame
local cardsWide: Frame
local cardsRows: Frame
local wideViews: { CardView } = {}
local rowViews: { CardView } = {}
local actions: { [string]: ActionBtn } = {}
local ringRight: UIGradient
local ringLeft: UIGradient
local ringDiscs: { Frame } = {}
local ringText: TextLabel

local offer: any = nil
local expiresAt = 0
local armedAt = 0
local locked = false
local banMode = false
local ringConn: RBXScriptConnection? = nil
local lastSecond = -1

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

---------------------------------------------------------------------------- helpers

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
			if type(def.desc) == "table" or type(def.desc) == "string" then
				desc = def.desc
			end
		end
	end
	if title == nil or title == "" then
		title = card.id or "?"
	end
	return title, desc or ""
end

local function initialsOf(text: string): string
	local caps = string.gsub(text, "[^%u]", "")
	if #caps >= 2 then
		return string.sub(caps, 1, 2)
	end
	local letters = string.gsub(text, "[^%a]", "")
	return string.upper(string.sub(letters, 1, 2))
end

local function list(parent: Instance, horizontal: boolean, padding: number, h: Enum.HorizontalAlignment?, v: Enum.VerticalAlignment?): UIListLayout
	return UITheme.new("UIListLayout", {
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = h or Enum.HorizontalAlignment.Center,
		VerticalAlignment = v or Enum.VerticalAlignment.Center,
	}, parent)
end

---------------------------------------------------------------------------- build

local function buildRing(parent: Instance)
	local size = C.RingSize
	local holder = UITheme.new("Frame", { Name = "Ring", Size = UDim2.fromOffset(size, size), LayoutOrder = 10, BorderSizePixel = 0 }, parent)
	UITheme.paint(holder, "BackgroundColor3", "Panel")
	UITheme.round(holder)
	UITheme.stroke(holder, 3, "Outline")
	-- Two clipped halves, each showing half of a disc whose UIGradient has a hard step at 0.5.
	local function half(xScale: number, discX: number): UIGradient
		local clip = UITheme.new("Frame", { BackgroundTransparency = 1, ClipsDescendants = true, Size = UDim2.fromScale(0.5, 1), Position = UDim2.fromScale(xScale, 0) }, holder)
		local disc = UITheme.new("Frame", { Size = UDim2.fromScale(2, 1), Position = UDim2.fromScale(discX, 0), BorderSizePixel = 0 }, clip)
		UITheme.paint(disc, "BackgroundColor3", "Shield")
		UITheme.round(disc)
		table.insert(ringDiscs, disc)
		return UITheme.new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.499, 0),
				NumberSequenceKeypoint.new(0.501, 1),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, disc)
	end
	ringLeft = half(0, 0)
	ringRight = half(0.5, -1)
	local inner = UITheme.new("Frame", { Size = UDim2.fromOffset(size - 12, size - 12), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 3, BorderSizePixel = 0 }, holder)
	UITheme.paint(inner, "BackgroundColor3", "Panel")
	UITheme.round(inner)
	ringText = UITheme.label(inner, { size = UDim2.fromScale(1, 1), role = "NumberM", font = "number", outline = true, z = 4 })
end

local function setRing(frac: number)
	frac = math.clamp(frac, 0, 1)
	ringRight.Rotation = math.clamp(frac / 0.5, 0, 1) * 180
	ringLeft.Rotation = 180 + math.clamp((frac - 0.5) / 0.5, 0, 1) * 180
end

local function buildAction(parent: Instance, name: string, order: number, key: string): ActionBtn
	local holder = UITheme.new("Frame", { Name = name, BackgroundTransparency = 1, Size = UDim2.fromOffset(C.ButtonWidth + 4, C.ButtonHeight + 6), LayoutOrder = order }, parent)
	local gloss = UITheme.glossy(holder, {
		name = "Button",
		button = true,
		role = "Neutral",
		size = UDim2.fromOffset(C.ButtonWidth, C.ButtonHeight),
		position = UDim2.fromOffset(0, 4),
		radius = 13,
		lip = 5,
		text = "",
		textRole = "TitleM",
	})
	local badge = UITheme.label(holder, { name = "Count", size = UDim2.fromOffset(22, 22), position = UDim2.fromOffset(C.ButtonWidth - 14, -4), role = "LabelS", outline = true, z = 5 })
	badge.BackgroundTransparency = 0
	UITheme.paint(badge, "BackgroundColor3", "Danger")
	UITheme.round(badge)
	UITheme.stroke(badge, 2, "Outline").ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local cap = UITheme.keycap(holder, key)
	cap.Position = UDim2.fromOffset(-8, -6)
	cap.ZIndex = 5
	local b: ActionBtn = { holder = holder, gloss = gloss, count = badge, key = cap }
	actions[name] = b
	return b
end

local function buildCard(parent: Instance, i: number, row: boolean): CardView
	local w = if row then C.RowWidth else C.Width
	local h = if row then C.RowHeight else C.Height
	local root = Instance.new("TextButton")
	root.Name = "Card" .. i
	root.Text = ""
	root.AutoButtonColor = false
	root.BorderSizePixel = 0
	root.Size = UDim2.fromOffset(w, h)
	root.LayoutOrder = i
	root.Parent = parent
	UITheme.corner(root, 16)
	local ink = UITheme.stroke(root, 3, "Outline")
	ink.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local shine = UITheme.new("Frame", { Name = "HeaderShine", Position = UDim2.fromOffset(5, 3), Size = UDim2.new(1, -10, 0, 9), BorderSizePixel = 0 }, root)
	UITheme.corner(shine, 6)
	local rarity = UITheme.label(root, { name = "Rarity", size = UDim2.fromOffset(100, 18), position = UDim2.fromOffset(12, 4), role = "LabelS", color = "OnLight", align = Enum.TextXAlignment.Left })
	local tag = UITheme.pill(root, { name = "Tag", tone = "Primary", text = S.New })
	tag.frame.AnchorPoint = Vector2.new(1, 0)
	tag.frame.Position = UDim2.new(1, -7, 0, 2)
	tag.frame.ZIndex = 3
	local body = UITheme.new("Frame", { Name = "Body", BorderSizePixel = 0 }, root)
	UITheme.paint(body, "BackgroundColor3", "Panel")
	UITheme.corner(body, 11)
	-- Icon chip: lip disc, face disc, shine, initials (A08-07 will put the real icon here).
	local chipSize = if row then 56 else 58
	local chipHolder = UITheme.new("Frame", { Name = "Chip", BackgroundTransparency = 1, Size = UDim2.fromOffset(chipSize, chipSize) }, root)
	local rays: Frame? = nil
	if not row then
		local r = UITheme.new("Frame", { Name = "Rays", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(100, 100), ZIndex = 1 }, chipHolder)
		for k = 0, 11 do
			local ray = UITheme.new("Frame", {
				Name = "Ray" .. k,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(7, 48),
				Rotation = k * 30,
				BorderSizePixel = 0,
				BackgroundTransparency = 0.55,
			}, r)
			UITheme.paint(ray, "BackgroundColor3", "Legendary")
			UITheme.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, ray)
		end
		rays = r
	end
	local chipLip = UITheme.new("Frame", { Name = "Lip", Size = UDim2.fromOffset(chipSize, chipSize), BorderSizePixel = 0, ZIndex = 2 }, chipHolder)
	UITheme.round(chipLip)
	UITheme.stroke(chipLip, 2.5, "Outline")
	local chipFace = UITheme.new("Frame", { Name = "Face", Size = UDim2.fromOffset(chipSize, chipSize - 5), BorderSizePixel = 0, ZIndex = 3 }, chipHolder)
	UITheme.round(chipFace)
	local chipShine = UITheme.new("Frame", { Name = "Shine", Position = UDim2.fromOffset(math.round(chipSize * 0.14), 3), Size = UDim2.fromOffset(math.round(chipSize * 0.72), math.round(chipSize * 0.33)), BorderSizePixel = 0, ZIndex = 4 }, chipHolder)
	UITheme.round(chipShine)
	local glint = UITheme.new("Frame", { Name = "Glint", Position = UDim2.fromOffset(math.round(chipSize * 0.24), 7), Size = UDim2.fromOffset(4, 4), BorderSizePixel = 0, ZIndex = 5 }, chipHolder)
	UITheme.paint(glint, "BackgroundColor3", "Shine")
	local initials = UITheme.label(chipHolder, { name = "Initials", size = UDim2.new(1, 0, 1, -5), role = "TitleL", outline = true, z = 6 })
	local gems = UITheme.gems(root, 8)
	local title = UITheme.label(root, { name = "Title", role = "TitleM", outline = true, wrap = true })
	title.TextTruncate = Enum.TextTruncate.AtEnd
	local desc = UITheme.label(root, { name = "Desc", role = "BodyS", font = "body", color = "TextDim", wrap = true })
	desc.TextTruncate = Enum.TextTruncate.AtEnd
	local key = UITheme.keycap(root, tostring(i))
	key.ZIndex = 6
	local veil = UITheme.new("Frame", { Name = "BanVeil", BorderSizePixel = 0, BackgroundTransparency = 0.45, Visible = false, ZIndex = 7 }, root)
	UITheme.paint(veil, "BackgroundColor3", "DangerLip")
	UITheme.corner(veil, 11)
	local banMark = UITheme.label(root, { name = "BanMark", role = "Hero", font = "number", color = "DangerLight", outline = true, text = "×", z = 8 })
	banMark.Visible = false
	local banTag = UITheme.pill(root, { name = "BanTag", tone = "Danger", text = S.BanTag })
	banTag.frame.AnchorPoint = Vector2.new(0.5, 1)
	banTag.frame.ZIndex = 8
	banTag.frame.Visible = false

	if row then
		body.Position = UDim2.fromOffset(4, 24)
		body.Size = UDim2.new(1, -8, 1, -28)
		chipHolder.Position = UDim2.fromOffset(14, 32)
		gems.Position = UDim2.fromOffset(110, 4)
		title.Position = UDim2.fromOffset(84, 30)
		title.Size = UDim2.new(1, -96, 0, 22)
		title.TextWrapped = false
		title.TextXAlignment = Enum.TextXAlignment.Left
		desc.Position = UDim2.fromOffset(84, 54)
		desc.Size = UDim2.new(1, -96, 0, 36)
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.TextYAlignment = Enum.TextYAlignment.Top
		key.Visible = false
		veil.Position = UDim2.fromOffset(4, 24)
		veil.Size = UDim2.new(1, -8, 1, -28)
		banMark.Size = UDim2.fromOffset(56, 56)
		banMark.Position = UDim2.fromOffset(14, 32)
		banTag.frame.Position = UDim2.new(0.5, 0, 1, -8)
	else
		body.Position = UDim2.fromOffset(4, 27)
		body.Size = UDim2.new(1, -8, 1, -31)
		chipHolder.Position = UDim2.new(0.5, -chipSize / 2, 0, 37)
		gems.AnchorPoint = Vector2.new(0.5, 0)
		gems.Position = UDim2.new(0.5, 0, 0, 98)
		title.Position = UDim2.fromOffset(8, 114)
		title.Size = UDim2.new(1, -16, 0, 22)
		desc.Position = UDim2.fromOffset(8, 138)
		desc.Size = UDim2.new(1, -16, 0, 36)
		desc.TextYAlignment = Enum.TextYAlignment.Top
		key.AnchorPoint = Vector2.new(0.5, 0.5)
		key.Position = UDim2.new(0.5, 0, 1, 2)
		veil.Position = UDim2.fromOffset(4, 27)
		veil.Size = UDim2.new(1, -8, 1, -31)
		banMark.Size = UDim2.fromOffset(60, 60)
		banMark.Position = UDim2.new(0.5, -30, 0, 36)
		banTag.frame.Position = UDim2.new(0.5, 0, 1, -10)
	end
	root.SelectionImageObject = UITheme.focusRing(16)
	root.Activated:Connect(function()
		CardUI.choose(i)
	end)
	return {
		root = root,
		ink = ink,
		shine = shine,
		body = body,
		rarity = rarity,
		tag = tag,
		chipLip = chipLip,
		chipFace = chipFace,
		chipShine = chipShine,
		initials = initials,
		gems = gems,
		rays = rays,
		title = title,
		desc = desc,
		key = key,
		veil = veil,
		banMark = banMark,
		banTag = banTag,
		row = row,
	}
end

---------------------------------------------------------------------------- render

local function renderActions()
	if not offer then
		return
	end
	local touch = UITheme.isTouch()
	for name, field in { Reroll = "reroll", Skip = "skip", Ban = "banish" } do
		local a = actions[name]
		local n = tonumber(offer[field]) or 0
		a.count.Text = tostring(n)
		a.count.Visible = not (name == "Ban" and banMode)
		a.key.Visible = not touch
		local usable = (n > 0 or (name == "Ban" and banMode)) and not locked
		a.gloss.setEnabled(usable)
		local label = a.gloss.label
		if label then
			if name == "Ban" then
				UITheme.setText(label, if banMode then S.Cancel else S.Ban)
			else
				UITheme.setText(label, if name == "Reroll" then S.Reroll else S.Skip)
			end
		end
	end
	actions.Reroll.holder.Visible = not banMode
	actions.Skip.holder.Visible = not banMode
end

local function renderView(v: CardView, card: any, hint: string?)
	v.root.Visible = type(card) == "table"
	if type(card) ~= "table" then
		return
	end
	local rarity = UITheme.rarityToken(if type(card.rarity) == "string" then card.rarity else nil)
	local def = (Config.Rarity :: any)[rarity]
	UITheme.paint(v.root, "BackgroundColor3", rarity)
	UITheme.paint(v.shine, "BackgroundColor3", rarity .. "Light")
	UITheme.paint(v.chipLip, "BackgroundColor3", rarity .. "Lip")
	UITheme.paint(v.chipFace, "BackgroundColor3", rarity)
	UITheme.paint(v.chipShine, "BackgroundColor3", rarity .. "Light")
	-- Frame thickness is the rarity's 3rd channel: the body inset grows with the rarity.
	local t = def.stroke
	local top = if v.row then 24 else 27
	v.body.Position = UDim2.fromOffset(t, top)
	v.body.Size = UDim2.new(1, -2 * t, 1, -top - t)
	v.veil.Position = v.body.Position
	v.veil.Size = v.body.Size
	UITheme.setText(v.rarity, def.name)
	v.rarity.Text = string.upper(v.rarity.Text)
	UITheme.setGems(v.gems, rarity)
	if v.rays then
		v.rays.Visible = rarity == "Legendary"
	end
	local title, desc = cardTexts(card)
	UITheme.setText(v.title, title)
	UITheme.setText(v.desc, desc)
	v.initials.Text = initialsOf(UITheme.format(title))
	local kind = tostring(card.kind)
	if string.sub(kind, 1, 9) == "Companion" then
		v.tag.setTone("Info")
		UITheme.setText(v.tag.label, S.Companion)
		v.tag.frame.Visible = true
	elseif string.sub(kind, 1, 3) == "New" then
		v.tag.setTone("Primary")
		UITheme.setText(v.tag.label, S.New)
		v.tag.frame.Visible = true
	elseif kind == "Heal" or kind == "Coins" then
		v.tag.frame.Visible = false
	else
		v.tag.setTone("Panel")
		UITheme.setText(v.tag.label, S.LevelN, { n = card.level or 1 })
		v.tag.frame.Visible = true
	end
	v.key.Visible = not v.row and hint ~= nil
	if hint then
		-- lihfolk-ignore: findfirstchild-chain -- fwjelaa-ignore: findfirstchild-chain (nil-checked on the next line)
		local kt = v.key:FindFirstChild("Text") :: TextLabel?
		if kt then
			kt.Text = hint
		end
	end
	v.veil.Visible = banMode
	v.banMark.Visible = banMode
	v.banTag.frame.Visible = banMode
	v.root.Active = not locked
end

local function render()
	local cards = if offer and type(offer.cards) == "table" then offer.cards else {}
	local touch = UITheme.isTouch()
	local portrait = UITheme.isPortrait()
	cardsWide.Visible = not portrait
	cardsRows.Visible = portrait
	for i = 1, 3 do
		local hint = if touch then nil else UIInput.hint("Card" .. i, tostring(i))
		renderView(wideViews[i], cards[i], hint)
		renderView(rowViews[i], cards[i], nil)
	end
	renderActions()
end

local function layout()
	local portrait = UITheme.isPortrait()
	-- Portrait: the title goes on its own line above the buttons.
	titleLabel.Parent = if portrait then plate else topRow
	local w = if portrait then C.RowWidth + 16 else 3 * C.Width + 2 * C.Gap + 24
	zone.Size = UDim2.fromOffset(w, if portrait then 440 else 280)
	zone.Position = UDim2.new(0.5, 0, 1, -2)
end

local function stopRing()
	if ringConn then
		ringConn:Disconnect()
		ringConn = nil
	end
end

local function hide()
	offer = nil
	banMode = false
	locked = false
	gui.Enabled = false
	stopRing()
	UITheme.setFlag("cardsOpen", false)
end

local function ringStep()
	local total = math.max(0.1, tonumber(offer and offer.expiresIn) or 8)
	local left = expiresAt - os.clock()
	setRing(left / total)
	local sec = math.max(0, math.ceil(left))
	if sec ~= lastSecond then
		lastSecond = sec
		ringText.Text = tostring(sec)
		local token = if left <= C.WarnSeconds then "Ko" else "Shield"
		for _, d in ringDiscs do
			UITheme.paint(d, "BackgroundColor3", token)
		end
		UITheme.paint(ringText, "TextColor3", if left <= C.WarnSeconds then "KoLight" else "Text")
	end
	if left <= -1 then
		-- The server auto-picks at expiry and should send `closed`; never leave a stale offer up.
		hide()
	end
end

local function onOffer(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if payload.closed then
		if offer == nil or payload.offerId == offer.offerId then
			hide()
		end
		return
	end
	if type(payload.cards) ~= "table" then
		return
	end
	local isNew = offer == nil
	offer = payload
	locked = false
	banMode = false
	expiresAt = os.clock() + (tonumber(payload.expiresIn) or 8)
	if isNew then
		armedAt = os.clock() + C.ArmSeconds
	end
	lastSecond = -1
	layout()
	render()
	gui.Enabled = UITheme.inRun()
	UITheme.setFlag("cardsOpen", gui.Enabled)
	if isNew then
		for i = 1, 3 do
			UITheme.pop(wideViews[i].root, 0.85)
			UITheme.pop(rowViews[i].root, 0.85)
		end
	end
	if not ringConn then
		ringConn = RunService.RenderStepped:Connect(ringStep)
	end
end

local function send(action: string, index: number?)
	if not offer or locked then
		return
	end
	locked = true
	local id = offer.offerId
	Net.event("CardChoice"):FireServer(id, action, index)
	render()
	-- If the server refuses (no charges left), unlock so the player can still pick.
	task.delay(1, function()
		if offer and offer.offerId == id and locked then
			locked = false
			render()
		end
	end)
end

---------------------------------------------------------------------------- public

function CardUI.isOpen(): boolean
	return offer ~= nil
end

function CardUI.choose(index: number)
	if not offer or locked or type(offer.cards) ~= "table" or offer.cards[index] == nil then
		return
	end
	if os.clock() < armedAt then
		return -- inert window: a thumb that was already on the screen must not pick a card
	end
	if banMode then
		banMode = false
		send("ban", index)
	else
		send("pick", index)
	end
end

function CardUI.reroll()
	if offer and (tonumber(offer.reroll) or 0) > 0 then
		send("reroll")
	end
end

function CardUI.skip()
	if offer and (tonumber(offer.skip) or 0) > 0 then
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
	end
	render()
end

function CardUI.start()
	gui = UITheme.screen("COHUE_Cards", 20)
	gui.Enabled = false
	zone = UITheme.zone(gui, "Cards", Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -2), UDim2.fromOffset(498, 280))
	plate = UITheme.new("Frame", {
		Name = "Plate",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BorderSizePixel = 0,
	}, zone)
	UITheme.paint(plate, "BackgroundColor3", "PanelSunken")
	UITheme.back(plate, 0.55)
	UITheme.corner(plate, 26)
	UITheme.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 10) }, plate)
	list(plate, false, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)

	titleLabel = UITheme.label(nil :: any, { name = "Title", size = UDim2.new(0, 0, 0, 30), autoSize = Enum.AutomaticSize.X, role = "NumberM", font = "number", color = "Legendary", outline = true, text = S.LevelUp })
	topRow = UITheme.new("Frame", { Name = "TopRow", BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 54), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 1 }, plate)
	list(topRow, true, 10)
	titleLabel.Parent = topRow
	local reroll = buildAction(topRow, "Reroll", 1, "R")
	local skip = buildAction(topRow, "Skip", 2, "X")
	local ban = buildAction(topRow, "Ban", 3, "B")
	buildRing(topRow)

	cardsWide = UITheme.new("Frame", { Name = "Cards", BackgroundTransparency = 1, Size = UDim2.fromOffset(0, C.Height + 8), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2 }, plate)
	list(cardsWide, true, C.Gap, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)
	cardsRows = UITheme.new("Frame", { Name = "Rows", BackgroundTransparency = 1, Size = UDim2.fromOffset(C.RowWidth, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Visible = false }, plate)
	list(cardsRows, false, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)
	for i = 1, 3 do
		wideViews[i] = buildCard(cardsWide, i, false)
		rowViews[i] = buildCard(cardsRows, i, true)
	end

	;(reroll.gloss.root :: GuiButton).Activated:Connect(CardUI.reroll)
	;(skip.gloss.root :: GuiButton).Activated:Connect(CardUI.skip)
	;(ban.gloss.root :: GuiButton).Activated:Connect(CardUI.toggleBan)

	for i = 1, 3 do
		UIInput.onAction("Card" .. i, function(pressed: boolean)
			if pressed then
				CardUI.choose(i)
			end
		end)
	end
	-- PC shortcuts R / X / B (not S: the player still walks with WASD during the 8 s offer).
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

	layout()
	UITheme.changed:connect(function(reason: string)
		if reason == "phase" then
			if offer and not UITheme.inRun() then
				hide()
			end
		elseif reason == "device" or reason == "lang" or reason == "palette" then
			layout()
			if offer then
				render()
			end
		end
	end)
	UITheme.watch("CardOffer", onOffer)
end

return CardUI
