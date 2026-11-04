--!strict
-- Level-up cards without pause: 3 cards at the bottom, 8 s ring, pick / banish / skip / reroll.
-- Design: docs/dossier/60-ui-ux.md section 4. Listens: CardOffer. Sends: CardChoice.
-- Input: InputController actions Card1-Card3 (via UIInput), touch/click on the cards.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local UITheme = require(script.Parent:WaitForChild("UITheme"))
local UIInput = require(script.Parent:WaitForChild("UIInput"))

local Config = UITheme.Config
local S = UITheme.S
local C = Config.Cards

local CardUI = {}

type CardView = {
	button: TextButton,
	stroke: UIStroke,
	gems: Frame,
	icon: Frame,
	title: TextLabel,
	desc: TextLabel,
	level: TextLabel,
	tag: TextLabel,
	key: TextLabel,
	banMark: TextLabel,
}

local gui: ScreenGui
local views: { CardView } = {}
local rerollBtn: TextButton
local skipBtn: TextButton
local banBtn: TextButton
local hintText: TextLabel
local ringRight: UIGradient
local ringLeft: UIGradient
local ringDiscs: { Frame } = {}
local ringText: TextLabel

local offer: any = nil
local expiresAt = 0
local locked = false
local banMode = false
local ringConn: RBXScriptConnection? = nil
local lastSecond = -1

local KEY_HINTS = {
	KeyboardAndMouse = { "1", "2", "3" },
	Gamepad = { "D-Left", "D-Down", "D-Right" },
}

---------------------------------------------------------------------------- text helpers

local CONFIG_FOR_KIND: { [string]: string } = {
	NewWeapon = "Weapons",
	WeaponUp = "Weapons",
	NewGrimoire = "Grimoires",
	GrimoireUp = "Grimoires",
	CompanionTech = "Companions",
	CompanionTechUp = "Companions",
	CompanionTreat = "Companions",
}

local function cardTexts(card: any): (any, any)
	local configName = CONFIG_FOR_KIND[card.kind]
	local title: any = card.title
	local desc: any = card.desc
	if configName and type(card.id) == "string" then
		local def = UITheme.def(configName, card.id)
		if def then
			if type(def.name) == "table" then
				title = def.name
			end
			if type(def.desc) == "table" then
				desc = def.desc
			end
		end
	end
	if title == nil or title == "" then
		title = card.id or "?"
	end
	return title, desc or ""
end

---------------------------------------------------------------------------- build

local function buildRing(parent: Instance)
	local size = C.RingSize
	local holder = UITheme.new("Frame", {
		Name = "Ring",
		Size = UDim2.fromOffset(size, size),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 2),
	}, parent)
	UITheme.paint(holder, "BackgroundColor3", "Outline")
	UITheme.round(holder)
	-- Two clipped halves, each showing half of a disc whose UIGradient has a hard step at 0.5.
	local function half(xScale: number, discX: number): UIGradient
		local clip = UITheme.new("Frame", {
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Size = UDim2.fromScale(0.5, 1),
			Position = UDim2.fromScale(xScale, 0),
		}, holder)
		local disc = UITheme.new("Frame", {
			Size = UDim2.fromScale(2, 1),
			Position = UDim2.fromScale(discX, 0),
			BorderSizePixel = 0,
		}, clip)
		UITheme.paint(disc, "BackgroundColor3", "Primary")
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
	local inner = UITheme.new("Frame", {
		Size = UDim2.fromOffset(size - 10, size - 10),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 3,
	}, holder)
	UITheme.paint(inner, "BackgroundColor3", "Panel")
	UITheme.round(inner)
	ringText = UITheme.label(inner, { size = UDim2.fromScale(1, 1), role = "Body", font = "display", z = 4 })
end

local function setRing(frac: number)
	frac = math.clamp(frac, 0, 1)
	ringRight.Rotation = math.clamp(frac / 0.5, 0, 1) * 180
	ringLeft.Rotation = 180 + math.clamp((frac - 0.5) / 0.5, 0, 1) * 180
end

local function buildCard(parent: Instance, i: number): CardView
	local b = Instance.new("TextButton")
	b.Name = "Card" .. i
	b.Text = ""
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	b.Size = UDim2.fromOffset(C.Width, C.Height)
	b.Position = UDim2.fromOffset((i - 1) * (C.Width + C.Gap), 52)
	b.Parent = parent
	UITheme.paint(b, "BackgroundColor3", "Panel")
	UITheme.back(b, 0.05)
	UITheme.corner(b, 12)
	local stroke = UITheme.stroke(b, 2, "Common")
	local gems = UITheme.gems(b, 7)
	gems.Position = UDim2.fromOffset(8, 6)
	local key = UITheme.label(b, {
		size = UDim2.fromOffset(50, 14),
		position = UDim2.new(1, -6, 0, 5),
		anchor = Vector2.new(1, 0),
		role = "Tiny",
		color = "TextDim",
		align = Enum.TextXAlignment.Right,
	})
	local tag = UITheme.label(b, {
		size = UDim2.new(1, 0, 0, 14),
		position = UDim2.fromOffset(0, 20),
		role = "Tiny",
		color = "Shield",
		text = S.Companion,
	})
	local icon = UITheme.icon(b, "?", 32)
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 22)
	local title = UITheme.label(b, {
		size = UDim2.new(1, -12, 0, 18),
		position = UDim2.fromOffset(6, 57),
		role = "Body",
	})
	local desc = UITheme.label(b, {
		size = UDim2.new(1, -12, 0, 16),
		position = UDim2.fromOffset(6, 75),
		role = "Tiny",
		font = "body",
		color = "TextDim",
	})
	local level = UITheme.label(b, {
		size = UDim2.new(1, -12, 0, 16),
		position = UDim2.fromOffset(6, 92),
		role = "Tiny",
		color = "Xp",
	})
	local banMark = UITheme.label(b, {
		size = UDim2.fromScale(1, 1),
		role = "Huge",
		font = "display",
		color = "Danger",
		outline = true,
		text = "X",
		z = 5,
	})
	banMark.Visible = false
	b.Activated:Connect(function()
		CardUI.choose(i)
	end)
	return {
		button = b,
		stroke = stroke,
		gems = gems,
		icon = icon,
		title = title,
		desc = desc,
		level = level,
		tag = tag,
		key = key,
		banMark = banMark,
	}
end

---------------------------------------------------------------------------- render

local function renderButtons()
	if not offer then
		return
	end
	local reroll = tonumber(offer.reroll) or 0
	local skip = tonumber(offer.skip) or 0
	local banish = tonumber(offer.banish) or 0
	UITheme.setText(rerollBtn, S.Reroll, { n = reroll })
	UITheme.setText(skipBtn, S.Skip, { n = skip })
	if banMode then
		UITheme.setText(banBtn, S.Cancel)
	else
		UITheme.setText(banBtn, S.Ban, { n = banish })
	end
	rerollBtn.Visible = not banMode
	skipBtn.Visible = not banMode
	hintText.Visible = banMode
	rerollBtn.Active = reroll > 0 and not locked
	rerollBtn.AutoButtonColor = rerollBtn.Active
	skipBtn.Active = skip > 0 and not locked
	skipBtn.AutoButtonColor = skipBtn.Active
	rerollBtn.TextTransparency = if reroll > 0 then 0 else 0.6
	skipBtn.TextTransparency = if skip > 0 then 0 else 0.6
	banBtn.TextTransparency = if banish > 0 or banMode then 0 else 0.6
	for _, v in views do
		v.banMark.Visible = banMode and v.button.Visible
	end
end

local function renderCards()
	local hints = (KEY_HINTS :: any)[UITheme.inputName()]
	local cards = if offer and type(offer.cards) == "table" then offer.cards else {}
	for i, v in views do
		local card = cards[i]
		v.button.Visible = type(card) == "table"
		if type(card) == "table" then
			local rarity = if type(card.rarity) == "string" and (Config.Rarity :: any)[card.rarity] then card.rarity else "Common"
			UITheme.paint(v.stroke, "Color", rarity)
			v.stroke.Thickness = (Config.Rarity :: any)[rarity].stroke
			UITheme.setGems(v.gems, rarity)
			local title, desc = cardTexts(card)
			UITheme.setText(v.title, title)
			UITheme.setText(v.desc, desc)
			UITheme.setIcon(v.icon, UITheme.format(title))
			local kind = tostring(card.kind)
			if string.sub(kind, 1, 3) == "New" or kind == "CompanionTech" then
				UITheme.setText(v.level, S.New)
			elseif kind == "Heal" or kind == "Coins" then
				UITheme.setText(v.level, "")
			else
				UITheme.setText(v.level, S.LevelN, { n = card.level or 1 })
			end
			v.tag.Visible = string.sub(kind, 1, 9) == "Companion"
			v.key.Text = if hints then hints[i] else ""
			v.button.BackgroundTransparency = if locked then 0.5 else 0.05
		end
	end
	renderButtons()
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
end

local function ringStep()
	local total = math.max(0.1, tonumber(offer and offer.expiresIn) or 8)
	local left = expiresAt - os.clock()
	setRing(left / total)
	local sec = math.max(0, math.ceil(left))
	if sec ~= lastSecond then
		lastSecond = sec
		ringText.Text = tostring(sec)
		local token = if left <= C.WarnSeconds then "Warning" else "Primary"
		for _, d in ringDiscs do
			UITheme.paint(d, "BackgroundColor3", token)
		end
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
	lastSecond = -1
	renderCards()
	gui.Enabled = UITheme.inRun()
	if isNew then
		for _, v in views do
			UITheme.pop(v.button, 0.85)
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
	renderCards()
	-- If the server refuses (no charges left), unlock so the player can still pick.
	task.delay(1, function()
		if offer and offer.offerId == id and locked then
			locked = false
			renderCards()
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
	if banMode then
		banMode = false
		send("ban", index)
	else
		send("pick", index)
	end
end

function CardUI.start()
	gui = UITheme.screen("COHUE_Cards", 20)
	gui.Enabled = false
	local width = 3 * C.Width + 2 * C.Gap
	local zone = UITheme.zone(
		gui,
		"Cards",
		Vector2.new(0.5, 1),
		UDim2.new(0.5, 0, 1, -Config.Margin),
		UDim2.fromOffset(width, C.Height + 52)
	)
	local bw = 104
	rerollBtn = UITheme.button(zone, { name = "Reroll", size = UDim2.fromOffset(bw, 44), position = UDim2.fromOffset(0, 0), role = "Small" })
	skipBtn = UITheme.button(zone, { name = "Skip", size = UDim2.fromOffset(bw, 44), position = UDim2.fromOffset(bw + 8, 0), role = "Small" })
	banBtn = UITheme.button(zone, { name = "Ban", size = UDim2.fromOffset(bw, 44), position = UDim2.fromOffset(2 * (bw + 8), 0), role = "Small" })
	hintText = UITheme.label(zone, {
		size = UDim2.fromOffset(2 * bw + 8, 44),
		role = "Small",
		color = "Warning",
		outline = true,
		wrap = true,
		text = S.BanHint,
	})
	hintText.Visible = false
	buildRing(zone)
	for i = 1, 3 do
		views[i] = buildCard(zone, i)
	end

	rerollBtn.Activated:Connect(function()
		if offer and (tonumber(offer.reroll) or 0) > 0 then
			send("reroll")
		end
	end)
	skipBtn.Activated:Connect(function()
		if offer and (tonumber(offer.skip) or 0) > 0 then
			send("skip")
		end
	end)
	banBtn.Activated:Connect(function()
		if not offer or locked then
			return
		end
		if banMode then
			banMode = false
		elseif (tonumber(offer.banish) or 0) > 0 then
			banMode = true
		end
		renderButtons()
	end)

	for i = 1, 3 do
		UIInput.onAction("Card" .. i, function(pressed: boolean)
			if pressed then
				CardUI.choose(i)
			end
		end)
	end

	UITheme.changed:connect(function(reason: string)
		if reason == "phase" then
			if offer and not UITheme.inRun() then
				hide()
			end
		elseif reason == "device" or reason == "lang" then
			if offer then
				renderCards()
			end
		end
	end)
	UITheme.watch("CardOffer", onOffer)
end

return CardUI
