--!strict
-- Survivors-style camera (lead): high, angled, fixed yaw, follows the character, so the horde,
-- the weapons and the loot around the player are readable on a phone. The default Roblox camera
-- sat close behind the avatar and hid everything 20+ studs away.
-- Zoom: mouse wheel, gamepad shoulder buttons, pinch on touch. Q / R rotate in 45° steps.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CameraController = {}

local MIN_DIST, MAX_DIST = 28, 80
local DEFAULT_DIST = 48
local PITCH = math.rad(55) -- angle below the horizon
local FOLLOW_SHARPNESS = 12 -- higher = snappier follow
local YAW_SHARPNESS = 10

local distance = DEFAULT_DIST
local yaw = 0
local targetYaw = 0
local focus: Vector3? = nil
local enabled = true

local function clampDist(d: number): number
	return math.clamp(d, MIN_DIST, MAX_DIST)
end

function CameraController.setEnabled(on: boolean)
	enabled = on
	local cam = Workspace.CurrentCamera
	if cam then
		cam.CameraType = if on then Enum.CameraType.Scriptable else Enum.CameraType.Custom
	end
end

function CameraController.getYaw(): number
	return yaw
end

local function step(dt: number)
	if not enabled then
		return
	end
	local cam = Workspace.CurrentCamera
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not cam or not root or not root:IsA("BasePart") then
		return
	end
	if cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Scriptable
	end
	local target = root.Position
	local a = 1 - math.exp(-FOLLOW_SHARPNESS * dt)
	focus = if focus then focus:Lerp(target, a) else target
	yaw += (targetYaw - yaw) * (1 - math.exp(-YAW_SHARPNESS * dt))

	local f = focus :: Vector3
	local offset = CFrame.Angles(0, yaw, 0) * Vector3.new(0, math.sin(PITCH), math.cos(PITCH)) * distance
	cam.CFrame = CFrame.lookAt(f + offset, f)
end

function CameraController.start()
	local cam = Workspace.CurrentCamera
	if cam then
		cam.FieldOfView = 60
	end

	UserInputService.InputChanged:Connect(function(input, processed)
		if not processed and input.UserInputType == Enum.UserInputType.MouseWheel then
			distance = clampDist(distance - input.Position.Z * 4)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		-- Q / R rotate (E is the Ultimate key).
		if input.KeyCode == Enum.KeyCode.Q then
			targetYaw += math.rad(45)
		elseif input.KeyCode == Enum.KeyCode.R then
			targetYaw -= math.rad(45)
		elseif input.KeyCode == Enum.KeyCode.ButtonL1 then
			distance = clampDist(distance + 6)
		elseif input.KeyCode == Enum.KeyCode.ButtonR1 then
			distance = clampDist(distance - 6)
		end
	end)
	UserInputService.TouchPinch:Connect(function(_positions, scale, _velocity, state, processed)
		if processed then
			return
		end
		if state == Enum.UserInputState.Change and scale > 0 then
			distance = clampDist(distance / scale ^ 0.15)
		end
	end)

	RunService:BindToRenderStep("CohueCamera", Enum.RenderPriority.Camera.Value + 1, step)
end

return CameraController
