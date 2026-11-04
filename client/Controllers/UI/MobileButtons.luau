--!strict
-- Bottom-right touch buttons: Jump, Slide, Ultimate (circular charge gauge), Ping.
-- On keyboard/gamepad only the Ultimate gauge stays, as a display with its key hint.
-- Design: docs/dossier/60-ui-ux.md section 8. Listens: CompanionState.
-- Input: UIInput.bindButton -> InputController.bindButton (engine UIButton binding), else
-- InputController.trigger, else fallbacks (Ultimate -> CompanionRenderer.requestUltimate / remote).

local TweenService = game:GetService("TweenService")

local UITheme = require(script.Parent:WaitForChild("UITheme"))
local UIInput = require(script.Parent:WaitForChild("UIInput"))

local Config = UITheme.Config
local MB = Config.Mobile
local S = UITheme.S

local MobileButtons = {}

local gui: ScreenGui
local zone: Frame
local buttons: { [string]: TextButton } = {}
local strokes: { [string]: UIStroke } = {}
local ultFill: Frame
local ultGlow: UIStroke
local ultTween: Tween?
local hintLabel: TextLabel
local charge = 0
local stunned = false

local ZONE_W, ZONE_H = 220, 240

local function roundButton(name: string, size: number, x: number, y: number, label: any): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = ""
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	b.AnchorPoint = Vector2.new(1, 1)
	b.Size = UDim2.fromOffset(size, size)
	b.Position = UDim2.new(1, x, 1, y)
	b.Parent = zone
	UITheme.paint(b, "BackgroundColor3", "Panel")
	UITheme.back(b, 0.3)
	UITheme.round(b)
	strokes[name] = UITheme.stroke(b, 2, "PanelLight")
	UITheme.label(b, {
		name = "Caption",
		size = UDim2.new(1, -6, 0, 18),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		role = if size >= 64 then "Small" else "Tiny",
		outline = true,
		text = label,
		z = 4,
	})
	buttons[name] = b
	return b
end

-- Final pass: push apart any overlapping buttons using their real rectangles (vault: Responsive UI s6).
local function separate()
	local list = {}
	for _, b in buttons do
		if b.Visible then
			table.insert(list, b)
		end
	end
	for _ = 1, 3 do
		local moved = false
		for i = 1, #list do
			for j = i + 1, #list do
				local a, b = list[i], list[j]
				local ac = a.AbsolutePosition + a.AbsoluteSize / 2
				local bc = b.AbsolutePosition + b.AbsoluteSize / 2
				local need = (a.AbsoluteSize.X + b.AbsoluteSize.X) / 2 + Config.Margin
				local d = (bc - ac).Magnitude
				if d < need and d > 0 then
					local push = (bc - ac).Unit * (need - d) / UITheme.scale()
					b.Position += UDim2.fromOffset(math.round(push.X), math.round(push.Y))
					moved = true
				end
			end
		end
		if not moved then
			break
		end
	end
end

local function renderCharge()
	local c = math.clamp(charge, 0, 1)
	ultFill.Size = UDim2.fromScale(1, c)
	local full = c >= 1 and not stunned
	ultGlow.Thickness = if full then 4 else 2
	UITheme.paint(ultGlow, "Color", if full then "Ultimate" else "PanelLight")
	if full and not ultTween and not UITheme.flashesReduced() then
		-- Slow glow (0.5 Hz), never a flash.
		local t = TweenService:Create(ultGlow, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.5 })
		t:Play()
		ultTween = t
	elseif (not full or UITheme.flashesReduced()) and ultTween then
		ultTween:Cancel()
		ultTween = nil
		ultGlow.Transparency = 0
	end
	buttons.Ultimate.BackgroundTransparency = if stunned then 0.6 else 0.3
end

local function layout()
	local touch = UITheme.isTouch()
	gui.Enabled = UITheme.inRun()
	for name, b in buttons do
		b.Visible = touch or name == "Ultimate"
		b.Active = touch
	end
	buttons.Jump.Visible = touch and MB.ShowJump
	local ult = buttons.Ultimate
	if touch then
		ult.Position = UDim2.new(1, -MB.EdgeX - (MB.Jump - MB.Small) / 2, 1, -MB.EdgeY - MB.Jump - MB.Gap)
		hintLabel.Visible = false
	else
		ult.Position = UDim2.new(1, -MB.EdgeX, 1, -MB.EdgeY)
		local hints = (MB.KeyHints :: any)[UITheme.inputName()]
		local key = UIInput.hint("Ultimate", if hints then hints.Ultimate else nil)
		hintLabel.Visible = key ~= nil
		hintLabel.Text = key or ""
	end
	task.defer(separate)
end

function MobileButtons.start()
	gui = UITheme.screen("COHUE_Mobile", 15)
	zone = UITheme.zone(gui, "Buttons", Vector2.new(1, 1), UDim2.fromScale(1, 1), UDim2.fromOffset(ZONE_W, ZONE_H))

	local jumpX, jumpY = -MB.EdgeX, -MB.EdgeY
	local jump = roundButton("Jump", MB.Jump, jumpX, jumpY, S.Jump)
	local slide = roundButton("Slide", MB.Small, jumpX - MB.Jump - MB.Gap, jumpY - (MB.Jump - MB.Small) / 2, S.Slide)
	local ult = roundButton("Ultimate", MB.Small, 0, 0, S.Ultimate)
	local ping = roundButton("Ping", MB.Ping, jumpX - MB.Jump - MB.Gap - (MB.Small - MB.Ping) / 2, jumpY - MB.Jump - MB.Gap, S.Ping)

	-- Ultimate charge: rounded fill rising from the bottom of the button (no CanvasGroup: memory).
	ultFill = UITheme.new("Frame", {
		Name = "Charge",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(1, 0),
		BorderSizePixel = 0,
		BackgroundTransparency = 0.35,
		ZIndex = 2,
	}, ult)
	UITheme.paint(ultFill, "BackgroundColor3", "Ultimate")
	UITheme.round(ultFill)
	ultGlow = strokes.Ultimate
	hintLabel = UITheme.label(ult, {
		name = "Key",
		size = UDim2.fromOffset(24, 18),
		position = UDim2.new(0, -4, 0, -4),
		role = "Small",
		font = "display",
		outline = true,
		z = 5,
	})
	UITheme.paint(hintLabel, "TextColor3", "Ultimate")

	UIInput.bindButton("Jump", jump)
	UIInput.bindButton("Slide", slide)
	UIInput.bindButton("Ultimate", ult)
	UIInput.bindButton("Ping", ping)

	layout()
	renderCharge()
	UITheme.changed:connect(function(reason: string)
		if reason == "device" or reason == "phase" then
			layout()
		elseif reason == "motion" then
			renderCharge()
		end
	end)
	UITheme.watch("CompanionState", function(c)
		if type(c) ~= "table" then
			return
		end
		local newCharge = tonumber(c.ultimateCharge) or 0
		-- Accept either a 0..1 fraction or a 0..100 value.
		if newCharge > 1.0001 then
			newCharge /= 100
		end
		local newStunned = c.stunned == true
		if math.abs(newCharge - charge) > 0.005 or newStunned ~= stunned then
			charge = newCharge
			stunned = newStunned
			renderCharge()
		end
	end)
end

return MobileButtons
