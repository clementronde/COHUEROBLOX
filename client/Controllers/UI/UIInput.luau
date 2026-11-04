--!strict
-- UI side of input (helper, not booted). The avatar domain's InputController owns the Input Action
-- System; UI only listens to actions and drives them from touch buttons.
-- Expected InputController API (all optional, checked at call time):
--   onAction(name, fn(pressed: boolean))   listen to Jump, Slide, Ultimate, Card1-3, Ping
--   bindButton(name, button: GuiButton)    engine UIButton binding for a touch button (preferred)
--   trigger(name, pressed: boolean)        drive an action from code (InputAction:Fire)
--   getHint(name) -> string?               key/button text for the current device
-- Fallbacks when InputController is missing: UserInputService keys, or remotes (Ultimate).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Registry = require(Shared:WaitForChild("Registry"))

local UIInput = {}

local FALLBACK_KEYS: { [string]: { Enum.KeyCode | Enum.UserInputType } } = {
	Card1 = { Enum.KeyCode.One, Enum.KeyCode.KeypadOne },
	Card2 = { Enum.KeyCode.Two, Enum.KeyCode.KeypadTwo },
	Card3 = { Enum.KeyCode.Three, Enum.KeyCode.KeypadThree },
	Ping = { Enum.UserInputType.MouseButton3, Enum.KeyCode.DPadUp },
}

local function controller(): any
	return Registry.find("InputController")
end

local fallbackHandlers: { [string]: { (pressed: boolean) -> () } } = {}
local fallbackConnected = false

local function matches(name: string, input: InputObject): boolean
	local list = FALLBACK_KEYS[name]
	if not list then
		return false
	end
	for _, k in list do
		if k == input.KeyCode or k == input.UserInputType then
			return true
		end
	end
	return false
end

local function connectFallback()
	if fallbackConnected then
		return
	end
	fallbackConnected = true
	local function dispatch(input: InputObject, gameProcessed: boolean, pressed: boolean)
		if gameProcessed then
			return
		end
		for name, handlers in fallbackHandlers do
			if matches(name, input) then
				for _, fn in handlers do
					task.spawn(fn, pressed)
				end
			end
		end
	end
	UserInputService.InputBegan:Connect(function(input, gp)
		dispatch(input, gp, true)
	end)
	UserInputService.InputEnded:Connect(function(input, gp)
		dispatch(input, gp, false)
	end)
end

-- Listen to an action. fn receives pressed (true) / released (false).
function UIInput.onAction(name: string, fn: (pressed: boolean) -> ())
	local ic = controller()
	if ic and type(ic.onAction) == "function" then
		ic.onAction(name, function(pressed: any)
			-- Accept either a boolean or no argument (treated as a press).
			fn(if pressed == nil then true else pressed == true)
		end)
		return
	end
	if FALLBACK_KEYS[name] then
		local list = fallbackHandlers[name]
		if not list then
			list = {}
			fallbackHandlers[name] = list
		end
		table.insert(list, fn)
		connectFallback()
	end
end

local function fallbackPress(name: string, pressed: boolean)
	if name == "Ultimate" then
		if pressed then
			Net.event("CompanionUltimate"):FireServer()
		end
	elseif name == "Jump" then
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and pressed then
			humanoid.Jump = true
		end
	end
	-- Slide has no fallback: it only exists in the avatar domain.
	-- UI listeners registered through the fallback path (Ping, Card1-3) still hear the button.
	local handlers = fallbackHandlers[name]
	if handlers then
		for _, fn in handlers do
			task.spawn(fn, pressed)
		end
	end
end

-- Drive an action from a UI control (touch button). Returns how it was routed.
function UIInput.press(name: string, pressed: boolean): string
	local ic = controller()
	if ic and type(ic.trigger) == "function" then
		ic.trigger(name, pressed)
		return "trigger"
	end
	fallbackPress(name, pressed)
	return "fallback"
end

-- Wire a touch button to an action. Prefers the engine UIButton binding; else press/release events.
-- onPress (optional) runs locally too (e.g. visual feedback).
function UIInput.bindButton(name: string, button: GuiButton, onPress: ((pressed: boolean) -> ())?): string
	local ic = controller()
	if ic and type(ic.bindButton) == "function" then
		local ok = pcall(ic.bindButton, name, button)
		if ok then
			if onPress then
				button.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
						onPress(true)
					end
				end)
			end
			return "bindButton"
		end
	end
	local held = false
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			if not held then
				held = true
				UIInput.press(name, true)
				if onPress then
					onPress(true)
				end
			end
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			if held then
				held = false
				UIInput.press(name, false)
				if onPress then
					onPress(false)
				end
			end
		end
	end)
	return "events"
end

function UIInput.hint(name: string, fallback: string?): string?
	local ic = controller()
	if ic and type(ic.getHint) == "function" then
		local ok, text = pcall(ic.getHint, name)
		if ok and type(text) == "string" and text ~= "" then
			return text
		end
	end
	return fallback
end

return UIInput
