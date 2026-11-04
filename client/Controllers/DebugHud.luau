--!strict
-- Phase 0 perf gate readout: FPS and drawn enemy count (toggle with Balance.Debug.ShowStats).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Balance = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Balance"))
local EnemyRenderer = require(script.Parent:WaitForChild("EnemyRenderer"))

local DebugHud = {}

function DebugHud.start()
	if not Balance.Debug.ShowStats then
		return
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "DebugHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 4)
	label.Size = UDim2.fromOffset(220, 24)
	label.BackgroundTransparency = 0.4
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 14
	label.Text = "..."
	label.Parent = gui
	gui.Parent = playerGui

	local frames, elapsed = 0, 0
	RunService.PreRender:Connect(function(dt)
		frames += 1
		elapsed += dt
		if elapsed >= 0.5 then
			label.Text = `{math.round(frames / elapsed)} fps | {EnemyRenderer.getVisibleCount()} enemies`
			frames, elapsed = 0, 0
		end
	end)
end

return DebugHud
