--!strict
-- InputController (A06, domaine avatar) : possède l'Input Action System du jeu.
-- Design : docs/dossier/50-classes-avatar-mouvement.md section 6. Vault fwjelaa : « Input - UserInputService
-- and ContextActionService » section 5, « Server Authority and Input Migration 2026 ».
--
-- Un InputContext « Gameplay » (Priority 1000, Sink = false), une InputAction par action, une liaison par
-- touche. Les boutons tactiles (MobileButtons, A08) se branchent sur les mêmes actions via bindButton
-- (InputBinding.UIButton) : appui = pressed true, relâché = false, l'action part à l'appui.
-- Le déplacement reste aux contrôles Roblox par défaut (relatif à la caméra). Le saut, lui, passe par
-- l'action Jump : MovementController met Humanoid.JumpHeight à 0, donc Espace / A / le bouton Roblox
-- par défaut ne font plus rien seuls (le bouton par défaut se masque tout seul).
--
-- API (client) :
--   InputController.onAction(name, fn: (pressed: boolean) -> ()) -> Connection   (Connection.disconnect())
--   InputController.isDown(name) -> boolean
--   InputController.bindButton(name, button: GuiButton) -> InputBinding?   -- méthode recommandée pour l'UI
--   InputController.trigger(name, pressed)                                  -- repli pour du code (tests, gestes)
--   InputController.getHint(name) -> string?                                -- touche / bouton pour l'appareil courant
--   InputController.getVector(name) -> Vector2                              -- actions analogiques (Look)
--   InputController.getContext() -> InputContext
--   InputController.setEnabled(enabled)                                     -- coupe tout pendant un menu plein écran
-- Actions booléennes : Jump, Slide, Capture, Ultimate, Card1, Card2, Card3, Ping,
--   CameraLeft, CameraRight, ZoomIn, ZoomOut.
-- Action analogique : Look (Direction2D, stick droit), lue par CameraController.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

export type Connection = { disconnect: () -> () }

type ActionSpec = {
	keys: { Enum.KeyCode },
	kind: "Bool" | "Direction2D",
	-- Texte d'aide par appareil (clavier / manette). Le tactile n'a pas de texte : le bouton suffit.
	hint: { Keyboard: string?, Gamepad: string? }?,
}

local InputController = {}

local K = Enum.KeyCode
local SPECS: { [string]: ActionSpec } = {
	Jump = { kind = "Bool", keys = { K.Space, K.ButtonA }, hint = { Keyboard = "Space", Gamepad = "A" } },
	Slide = { kind = "Bool", keys = { K.LeftShift, K.LeftControl, K.C, K.ButtonB, K.ButtonR2 }, hint = { Keyboard = "Shift", Gamepad = "B" } },
	Capture = { kind = "Bool", keys = { K.F, K.ButtonX }, hint = { Keyboard = "F", Gamepad = "X" } },
	Ultimate = { kind = "Bool", keys = { K.E, K.ButtonY }, hint = { Keyboard = "E", Gamepad = "Y" } },
	Card1 = { kind = "Bool", keys = { K.One, K.KeypadOne, K.DPadLeft }, hint = { Keyboard = "1", Gamepad = "Left" } },
	Card2 = { kind = "Bool", keys = { K.Two, K.KeypadTwo, K.DPadDown }, hint = { Keyboard = "2", Gamepad = "Down" } },
	Card3 = { kind = "Bool", keys = { K.Three, K.KeypadThree, K.DPadRight }, hint = { Keyboard = "3", Gamepad = "Right" } },
	Ping = { kind = "Bool", keys = { K.G, K.DPadUp }, hint = { Keyboard = "G", Gamepad = "Up" } }, -- + clic molette (plus bas)
	CameraLeft = { kind = "Bool", keys = { K.Left } },
	CameraRight = { kind = "Bool", keys = { K.Right } },
	ZoomIn = { kind = "Bool", keys = { K.I, K.ButtonR1 } },
	ZoomOut = { kind = "Bool", keys = { K.O, K.ButtonL1 } },
	Look = { kind = "Direction2D", keys = { K.Thumbstick2 } },
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
	if (down[name] == true) == pressed then
		return -- dédoublonnage (deux liaisons, ou IAS + trigger)
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

-- Relie un GuiButton (bouton tactile) à une action par InputBinding.UIButton : appuyer sur le bouton
-- déclenche l'action comme la touche. Une fois par bouton.
function InputController.bindButton(name: string, button: GuiButton): InputBinding?
	local action = actions[name]
	if not action or SPECS[name].kind ~= "Bool" then
		warn(`[InputController] bindButton: unknown action "{name}"`)
		return nil
	end
	local binding = Instance.new("InputBinding")
	binding.Name = `UI_{button.Name}`
	binding.UIButton = button
	binding.Parent = action
	return binding
end

-- Repli pour l'entrée pilotée par code (tests, gestes, compagnon). Appelle directement les écouteurs.
function InputController.trigger(name: string, pressed: boolean)
	local spec = SPECS[name]
	if not spec or spec.kind ~= "Bool" then
		warn(`[InputController] trigger: unknown action "{name}"`)
		return
	end
	dispatch(name, pressed == true)
end

function InputController.isDown(name: string): boolean
	return down[name] == true
end

-- Valeur d'une action analogique (Vector2.zero si absente ou contexte coupé).
function InputController.getVector(name: string): Vector2
	local action = actions[name]
	if not enabled or not action or SPECS[name].kind ~= "Direction2D" then
		return Vector2.zero
	end
	local ok, value = pcall(function()
		return action:GetState()
	end)
	if ok and typeof(value) == "Vector2" then
		return value
	end
	return Vector2.zero
end

local function deviceName(): string
	local p = UserInputService.PreferredInput
	if p == Enum.PreferredInput.Gamepad then
		return "Gamepad"
	elseif p == Enum.PreferredInput.Touch then
		return "Touch"
	end
	return "Keyboard"
end

-- Texte à afficher pour l'action sur l'appareil courant (nil en tactile ou sans aide prévue).
function InputController.getHint(name: string): string?
	local spec = SPECS[name]
	local hint = spec and spec.hint
	if not hint then
		return nil
	end
	local device = deviceName()
	if device == "Gamepad" then
		return hint.Gamepad
	elseif device == "Keyboard" then
		return hint.Keyboard
	end
	return nil
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
	-- Créé par le client sous ReplicatedStorage : local, non répliqué.
	local folder = Instance.new("Folder")
	folder.Name = "CohueInput"

	local ctx = Instance.new("InputContext")
	ctx.Name = "Gameplay"
	ctx.Priority = 1000
	ctx.Sink = false -- les contrôles par défaut gardent le déplacement (WASD, stick gauche)
	ctx.Parent = folder

	for name, spec in SPECS do
		local action = Instance.new("InputAction")
		action.Name = name
		action.Type = if spec.kind == "Direction2D" then Enum.InputActionType.Direction2D else Enum.InputActionType.Bool
		action.Parent = ctx
		for _, key in spec.keys do
			local binding = Instance.new("InputBinding")
			binding.Name = key.Name
			binding.KeyCode = key
			binding.Parent = action
		end
		if spec.kind == "Bool" then
			action.Pressed:Connect(function()
				dispatch(name, true)
			end)
			action.Released:Connect(function()
				dispatch(name, false)
			end)
		end
		actions[name] = action
	end

	context = ctx
	folder.Parent = ReplicatedStorage

	-- Ping au clic molette (PC). Pas un KeyCode : par UserInputService.
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
