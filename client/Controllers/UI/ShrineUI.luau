--!strict
-- Shrine offer (3 stat choices) and the charge pill of the nearest charging shrine.
-- Design: docs/dossier/60-ui-ux.md section 5. Listens: ShrineOffer, ShrineState. Sends: ShrineChoice.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Registry = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Registry"))
local UITheme = require(script.Parent:WaitForChild("UITheme"))

local Config = UITheme.Config
local S = UITheme.S

local ShrineUI = {}

type Choice = { button: TextButton, stroke: UIStroke, gems: Frame, text: TextLabel }

local gui: ScreenGui
local zone: Frame
local panel: Frame
local choices: { Choice } = {}
local pill: Frame
local pillText: TextLabel
local offer: any = nil
local sent = false
local shrines: { any } = {}

local function cardsOpen(): boolean
	local cardUI = Registry.find("CardUI")
	return cardUI ~= nil and type(cardUI.isOpen) == "function" and cardUI.isOpen()
end

-- Sit above the level cards when both are open, else at the bottom.
local function place()
	local bottom = if cardsOpen() then Config.Cards.Height + 52 + 2 * Config.Margin else Config.Margin
	zone.Position = UDim2.new(0.5, 0, 1, -bottom)
end

local function render()
	panel.Visible = offer ~= nil
	if not offer then
		return
	end
	for i, c in choices do
		local data = offer.choices[i]
		c.button.Visible = type(data) == "table"
		if type(data) == "table" then
			local rarity = if (Config.Rarity :: any)[data.rarity] then data.rarity else "Common"
			UITheme.paint(c.stroke, "Color", rarity)
			c.stroke.Thickness = (Config.Rarity :: any)[rarity].stroke
			UITheme.setGems(c.gems, rarity)
			c.text.Text = UITheme.statText(tostring(data.stat), tonumber(data.value) or 0)
			c.button.BackgroundTransparency = if sent then 0.5 else 0.05
		end
	end
end

local function onOffer(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if payload.closed then
		if offer and payload.offerId == offer.offerId then
			offer = nil
			render()
		end
		return
	end
	if type(payload.choices) ~= "table" then
		return
	end
	offer = payload
	sent = false
	place()
	render()
	UITheme.pop(panel, 0.9)
end

local function choose(i: number)
	if not offer or sent or offer.choices[i] == nil then
		return
	end
	sent = true
	Net.event("ShrineChoice"):FireServer(offer.offerId, i)
	-- No close message in the contract for a resolved shrine offer: hide after sending.
	local id = offer.offerId
	render()
	task.delay(0.3, function()
		if offer and offer.offerId == id then
			offer = nil
			render()
		end
	end)
end

local function updatePill()
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local best: any = nil
	local bestD = Config.Shrine.ShowRadius
	if root and root:IsA("BasePart") and UITheme.inRun() then
		for _, s in shrines do
			if type(s) == "table" and s.state == "Charging" and typeof(s.position) == "Vector3" then
				local d = (s.position - root.Position).Magnitude
				if d < bestD then
					bestD = d
					best = s
				end
			end
		end
	end
	pill.Visible = best ~= nil and offer == nil
	if best then
		local chargers = best.chargers
		local n = if type(chargers) == "table" then #chargers else (tonumber(chargers) or 1)
		UITheme.setText(pillText, S.ShrineCharge, {
			p = math.floor(math.clamp(tonumber(best.progress) or 0, 0, 1) * 100),
			n = n,
		})
	end
end

function ShrineUI.start()
	gui = UITheme.screen("COHUE_Shrine", 21)
	zone = UITheme.zone(gui, "Shrine", Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -Config.Margin), UDim2.fromOffset(400, 110))
	panel = UITheme.panel(zone, { Size = UDim2.fromScale(1, 1), Visible = false })
	UITheme.label(panel, {
		size = UDim2.new(1, 0, 0, 24),
		position = UDim2.fromOffset(0, 4),
		role = "Body",
		color = "Shield",
		text = S.ShrineTitle,
	})
	for i = 1, 3 do
		local b = Instance.new("TextButton")
		b.Name = "Choice" .. i
		b.Text = ""
		b.BorderSizePixel = 0
		b.Size = UDim2.fromOffset(120, 70)
		b.Position = UDim2.fromOffset(10 + (i - 1) * 130, 32)
		b.Parent = panel
		UITheme.paint(b, "BackgroundColor3", "PanelLight")
		UITheme.corner(b, 10)
		local stroke = UITheme.stroke(b, 2, "Common")
		local gems = UITheme.gems(b, 6)
		gems.Position = UDim2.fromOffset(6, 4)
		local text = UITheme.label(b, {
			size = UDim2.new(1, -10, 0, 44),
			position = UDim2.fromOffset(5, 20),
			role = "Small",
			wrap = true,
		})
		b.Activated:Connect(function()
			choose(i)
		end)
		choices[i] = { button = b, stroke = stroke, gems = gems, text = text }
	end
	pill = UITheme.panel(zone, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -Config.Cards.Height - 60),
		Size = UDim2.fromOffset(240, 26),
		Visible = false,
	})
	pillText = UITheme.label(pill, { size = UDim2.fromScale(1, 1), role = "Small", color = "Shield" })

	UITheme.changed:connect(function(reason: string)
		if reason == "phase" and not UITheme.inRun() then
			offer = nil
			render()
		elseif reason == "lang" then
			render()
		end
	end)
	UITheme.watch("ShrineOffer", onOffer)
	UITheme.watch("ShrineState", function(payload)
		if type(payload) == "table" and type(payload.shrines) == "table" then
			shrines = payload.shrines
		end
	end)
	UITheme.watch("CardOffer", function()
		task.defer(place)
	end)

	-- Pill: 4 Hz, text only rewritten through setText when values change.
	while true do
		task.wait(0.25)
		updatePill()
	end
end

return ShrineUI
