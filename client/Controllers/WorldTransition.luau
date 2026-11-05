--!strict
-- Fondu entre deux mondes (docs/dossier/21-tuiles-assemblage.md section 7, A02-08).
-- Écoute les attributs de Workspace posés par server/Services/WorldPortals :
--   CohueTransition = "NextWorld" pendant le fondu, "" ensuite ; CohueTransitionWorld = monde suivant.
-- Pilote l'écran fait main StarterGui.WorldTransition (ScreenGui > Frame "Fade" > TextLabel "Title").
-- Rien n'est fabriqué ici : si l'écran manque, c'est signalé une fois et la transition reste sèche.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Worlds = require(Shared:WaitForChild("Config"):WaitForChild("Worlds"))

local ATTR = "CohueTransition" -- WorldPortals.Attribute
local ATTR_WORLD = "CohueTransitionWorld" -- WorldPortals.AttributeWorld
local FADE_IN = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_OUT = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local WorldTransition = {}

local warned = false
local tweens: { Tween } = {}

local function stopTweens()
	for _, tw in tweens do
		tw:Cancel()
	end
	table.clear(tweens)
end

local function play(target: Instance, info: TweenInfo, props: { [string]: any }): Tween
	local tw = TweenService:Create(target, info, props)
	table.insert(tweens, tw)
	tw:Play()
	return tw
end

local function screen(): (ScreenGui?, Frame?, TextLabel?)
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local gui = playerGui and playerGui:FindFirstChild("WorldTransition")
	local fade = gui and gui:FindFirstChild("Fade")
	if not (gui and gui:IsA("ScreenGui") and fade and fade:IsA("Frame")) then
		if not warned then
			warned = true
			warn("[WorldTransition] écran StarterGui.WorldTransition (Frame Fade) absent : pas de fondu")
		end
		return nil, nil, nil
	end
	local title = fade:FindFirstChild("Title", true)
	return gui, fade, if title and title:IsA("TextLabel") then title else nil
end

local function onChanged()
	local gui, fade, title = screen()
	if not (gui and fade) then
		return
	end
	stopTweens()
	if Workspace:GetAttribute(ATTR) == "NextWorld" then
		local worldId = Workspace:GetAttribute(ATTR_WORLD)
		local world = if type(worldId) == "string" then Worlds[worldId] else nil
		if title then
			title.Text = if world then world.name.en else ""
			title.TextTransparency = 1
			play(title, FADE_IN, { TextTransparency = 0 })
		end
		fade.BackgroundTransparency = 1
		gui.Enabled = true
		play(fade, FADE_IN, { BackgroundTransparency = 0 })
	elseif gui.Enabled then
		if title then
			play(title, FADE_OUT, { TextTransparency = 1 })
		end
		local tw = play(fade, FADE_OUT, { BackgroundTransparency = 1 })
		tw.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed then
				gui.Enabled = false
			end
		end)
	end
end

function WorldTransition.init() end

function WorldTransition.start()
	Players.LocalPlayer:WaitForChild("PlayerGui")
	Workspace:GetAttributeChangedSignal(ATTR):Connect(onChanged)
	if Workspace:GetAttribute(ATTR) == "NextWorld" then
		onChanged()
	end
end

return WorldTransition
