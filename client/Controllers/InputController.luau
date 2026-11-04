--!strict
-- InputController (avatar domain): owns the Input Action System for the whole game.
-- Design: docs/dossier/50-classes-avatar-mouvement.md section 5. Vault: "Input - UserInputService and
-- ContextActionService" section 5, "Server Authority and Input Migration 2026" section 4.
--
-- Movement itself stays on the default Roblox controls. Our context does NOT sink, so Space / ButtonA
-- still reach the default jump.
--
-- API (client):
--   InputController.onAction(name, fn: (pressed: boolean) -> ()) -> Connection   (Connection.disconnect())
--   InputController.getContext() -> InputContext
--   InputController.bindButton(name, button: GuiButton) -> InputBinding?   -- recommended for mobile buttons
--   InputController.trigger(name, pressed)                                  -- fallback for code-driven input
--   InputController.isDown(name) -> boolean
--   InputController.setEnabled(enabled)                                     -- off while a full-screen menu is open
-- Actions: Jump, Slide, Ultimate, Card1, Card2, Card3, Ping.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

export type Connection = { disconnect: () -> () }

type ActionSpec = { keys: { Enum.KeyCode } }

local InputController = {}

local K = Enum.KeyCode
local SPECS: { [string]: ActionSpec } = {
	Jump = { keys = { K.Space, K.ButtonA } },
	Slide = { keys = { K.LeftControl, K.LeftShift, K.ButtonB } },
	Ultimate = { keys = { K.E, K.ButtonY } },
	Card1 = { keys = { K.One, K.DPadLeft } },
	Card2 = { keys = { K.Two, K.DPadDown } },
	Card3 = { keys = { K.Three, K.DPadRight } },
	Ping = { keys = { K.G, K.DPadUp } }, -- + middle mouse button below (UserInputService)
}

local context: InputContext? = nil
local actions: { [string]: InputAction } = {}
local listeners: { [string]: { (boolean) -> () } } = {}
local down: { [string]: boolean } = {}
local enabled = true

local function dispatch(name: string, pressed: boolean)
	if pressed and not enabled then
		return
	end
	if down[name] == pressed then
		return -- dedupe (two bindings, or IAS + trigger)
	end
	down[name] = pressed
	local list = listeners[name]
	if not list then
		return
	end
	for _, fn in table.clone(list) do
		local ok, err = pcall(fn, pressed)
		if not ok then
			warn(`[InputController] {name} listener failed: {err}`)
		end
	end
end

function InputController.onAction(name: string, fn: (pressed: boolean) -> ()): Connection
	assert(SPECS[name], `Unknown input action "{name}"`)
	local list = listeners[name]
	if not list then
		list = {}
		listeners[name] = list
	end
	table.insert(list, fn)
	return {
		disconnect = function()
			local current = listeners[name]
			local i = current and table.find(current, fn)
			if current and i then
				table.remove(current, i)
			end
		end,
	}
end

function InputController.getContext(): InputContext
	assert(context, "InputController.init has not run")
	return context
end

-- Links a GuiButton (mobile button) to an action through InputBinding.UIButton: pressing the button
-- drives the same InputAction as the key. Call once per button.
function InputController.bindButton(name: string, button: GuiButton): InputBinding?
	local action = actions[name]
	if not action then
		warn(`[InputController] bindButton: unknown action "{name}"`)
		return nil
	end
	local binding = Instance.new("InputBinding")
	binding.Name = `UI_{button.Name}`
	binding.UIButton = button
	binding.Parent = action
	return binding
end

-- Fallback for code-driven input (gestures, tests, companion). Calls the listeners directly.
function InputController.trigger(name: string, pressed: boolean)
	if not SPECS[name] then
		warn(`[InputController] trigger: unknown action "{name}"`)
		return
	end
	dispatch(name, pressed == true)
end

function InputController.isDown(name: string): boolean
	return down[name] == true
end

function InputController.setEnabled(value: boolean)
	enabled = value
	if context then
		context.Enabled = value
	end
	if not value then
		for name, isDown in down do
			if isDown then
				dispatch(name, false)
			end
		end
	end
end

function InputController.init()
	-- Created by the client under ReplicatedStorage: local only, not replicated.
	local folder = Instance.new("Folder")
	folder.Name = "CohueInput"

	local ctx = Instance.new("InputContext")
	ctx.Name = "Gameplay"
	ctx.Priority = 1000
	ctx.Sink = false -- default controls keep Space / ButtonA for jumping
	ctx.Parent = folder

	for name, spec in SPECS do
		local action = Instance.new("InputAction")
		action.Name = name
		action.Type = Enum.InputActionType.Bool
		action.Parent = ctx
		for _, key in spec.keys do
			local binding = Instance.new("InputBinding")
			binding.Name = key.Name
			binding.KeyCode = key
			binding.Parent = action
		end
		action.Pressed:Connect(function()
			dispatch(name, true)
		end)
		action.Released:Connect(function()
			dispatch(name, false)
		end)
		actions[name] = action
	end

	context = ctx
	folder.Parent = ReplicatedStorage

	-- Ping on the mouse wheel button (PC). Not a KeyCode, so through UserInputService.
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.UserInputType == Enum.UserInputType.MouseButton3 then
			dispatch("Ping", true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton3 then
			dispatch("Ping", false)
		end
	end)
end

return InputController
