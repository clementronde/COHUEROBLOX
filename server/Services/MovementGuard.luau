--!strict
-- MovementGuard (avatar domain): server plausibility checks for client-owned characters (classic mode).
-- Design: docs/dossier/50-classes-avatar-mouvement.md section 6. Vault: "Exploits and Anti-Cheat",
-- "Detecting Movement Exploits - Speed Fly Noclip Teleport".
-- Horizontal leaky-bucket speed check + teleport step check + hover check (shadow mode by default).
-- Mitigation = rubber-band to the last grounded valid position. Never kicks. Logs with ping.
-- Also validates the MoveEvent remote and sets server attributes Sliding / HopChain / Airborne.
--
-- Exemptions (server-caused movement: jump pads, geysers, ziplines, teleports, knockback):
--   MovementGuard.exempt(player, seconds, reason?)            (contract request: add to section 4)
--   or set the server attribute Player.MoveExemptUntil = workspace:GetServerTimeNow() + seconds

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Registry = require(Shared:WaitForChild("Registry"))
local Config = Shared:WaitForChild("Config")
local Classes = require(Config:WaitForChild("Classes"))
local Movement = require(Config:WaitForChild("Movement"))
local Heightmap = require(Shared:WaitForChild("Heightmap"))

local G = Movement.Guard

-- Launches applied by the client that the server must tolerate (integration fix):
-- jump pads from the shared stage layout, and the sandstorm push (Worlds hazard pushSpeed = 6).
local PAD_RADIUS = 6 -- studs around a pad centre that start the grace window
local PAD_GRACE = 2.5 -- seconds: covers the launch arc onto the plateau
local SANDSTORM_PUSH = 8 -- studs/s added while CohueHazard == "Sandstorm" (pushSpeed + margin)

type State = {
	lastPos: Vector3,
	lastValid: CFrame,
	bucket: number,
	exemptUntil: number, -- os.clock()
	strikes: number,
	airborneFor: number,
	airStartY: number,
	lastLog: number,
	slideUntil: number,
	lastHopAt: number,
}

local MovementGuard = {}

local states: { [Player]: State } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local function refreshFilter()
	local exclude: { Instance } = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(exclude, p.Character)
		end
	end
	rayParams.FilterDescendantsInstances = exclude
end

local function getState(player: Player): State?
	return states[player]
end

-- Server-known max plausible horizontal speed (studs/s). Never reads Humanoid.WalkSpeed.
local function maxSpeed(player: Player): number
	local classId = player:GetAttribute("ClassId")
	local def = if type(classId) == "string" then Classes[classId] else nil
	local base = if def then def.walkSpeed else Movement.DefaultWalkSpeed

	local moveSpeed = 0
	local StatsService = Registry.find("StatsService")
	if StatsService then
		local ok, stats = pcall(StatsService.get, player)
		if ok and type(stats) == "table" and type(stats.MoveSpeed) == "number" then
			moveSpeed = math.max(0, stats.MoveSpeed)
		end
	end

	local slideBoost = if def and type(def.slideBoost) == "number" then def.slideBoost else Movement.SlideBoostDefault
	local burst = math.max(1 + Movement.BhopMaxBonus, Movement.SlideMaxMult, slideBoost * (1 + Movement.BhopMaxBonus))
	return base * (1 + moveSpeed) * burst
end

local function isExempt(player: Player, s: State, now: number): boolean
	if now < s.exemptUntil then
		return true
	end
	local untilServer = player:GetAttribute("MoveExemptUntil")
	return type(untilServer) == "number" and Workspace:GetServerTimeNow() < untilServer
end

local function log(player: Player, s: State, kind: string, data: string)
	local now = os.clock()
	if now - s.lastLog < G.LogEvery then
		return
	end
	s.lastLog = now
	warn(`[MovementGuard] {kind} {player.Name} ({player.UserId}) {data} ping={math.floor(player:GetNetworkPing() * 1000)}ms strikes={s.strikes}`)
end

local function rubberBand(character: Model, root: BasePart, s: State, player: Player)
	character:PivotTo(s.lastValid)
	root.AssemblyLinearVelocity = Vector3.zero
	s.lastPos = s.lastValid.Position
	s.bucket = 0
	s.airborneFor = 0
	s.exemptUntil = os.clock() + G.GraceAfterRubberBand + math.clamp(player:GetNetworkPing(), 0, G.PingCap)
end

local function grounded(root: BasePart, humanoid: Humanoid): boolean
	local reach = humanoid.HipHeight + root.Size.Y / 2 + 1.5
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), rayParams)
	return hit ~= nil and hit.Normal.Y >= Movement.GroundNormalMinY
end

local function sample(player: Player, dt: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		return
	end

	local pos = root.Position
	local s = getState(player)
	if not s then
		states[player] = {
			lastPos = pos,
			lastValid = root.CFrame,
			bucket = 0,
			exemptUntil = os.clock() + G.SpawnGrace,
			strikes = 0,
			airborneFor = 0,
			airStartY = pos.Y,
			lastLog = 0,
			slideUntil = 0,
			lastHopAt = 0,
		}
		return
	end

	-- NaN guard
	if pos.X ~= pos.X or pos.Y ~= pos.Y or pos.Z ~= pos.Z then
		rubberBand(character, root, s, player)
		return
	end

	local onGround = grounded(root, humanoid)
	player:SetAttribute("Airborne", not onGround)
	if s.slideUntil > 0 and os.clock() > s.slideUntil then
		s.slideUntil = 0
		player:SetAttribute("Sliding", false)
	end

	local now = os.clock()
	-- Standing on a jump pad starts a short exemption (the client applies the launch).
	local layout = Heightmap.getLayout()
	if layout then
		for _, pad in layout.pads do
			local dx, dz = pos.X - pad.x, pos.Z - pad.z
			if dx * dx + dz * dz < PAD_RADIUS * PAD_RADIUS then
				s.exemptUntil = math.max(s.exemptUntil, now + PAD_GRACE)
				break
			end
		end
	end
	-- Rebase only: exemptions, seats, anchored, server hitch.
	if isExempt(player, s, now) or root.Anchored or humanoid.SeatPart ~= nil or dt > G.HitchFactor * G.Interval then
		s.lastPos = pos
		s.bucket = 0
		s.airborneFor = 0
		if onGround then
			s.lastValid = root.CFrame
		end
		return
	end

	local vmax = maxSpeed(player)
	if Workspace:GetAttribute("CohueHazard") == "Sandstorm" then
		vmax += SANDSTORM_PUSH
	end
	local ping = math.clamp(player:GetNetworkPing(), 0, G.PingCap)
	local horizontal = Vector3.new(pos.X - s.lastPos.X, 0, pos.Z - s.lastPos.Z).Magnitude

	-- 1. Teleport: one step far beyond anything plausible, even with a lag burst.
	local teleportLimit = math.max(G.TeleportMinStuds, vmax * (dt + ping + 0.5) * 2)
	if horizontal > teleportLimit then
		s.strikes += 1
		log(player, s, "teleport", `step={math.floor(horizontal)} limit={math.floor(teleportLimit)}`)
		if G.Enforce then
			rubberBand(character, root, s, player)
		else
			s.lastPos = pos
		end
		return
	end

	-- 2. Speed: leaky bucket of excess distance, with ping slack.
	local allowed = vmax * G.SpeedMargin * dt + vmax * ping * 0.25 -- ping slack per sample
	local excess = math.max(0, horizontal - allowed)
	s.bucket = math.max(0, s.bucket + excess - G.LeakPerSecond * dt)
	if s.bucket > G.BucketMax then
		s.strikes += 1
		log(player, s, "speed", `step={string.format("%.1f", horizontal)} allowed={string.format("%.1f", allowed)} vmax={string.format("%.1f", vmax)}`)
		if G.Enforce then
			rubberBand(character, root, s, player)
			return
		end
		s.bucket = 0
	end

	-- 3. Hover: airborne without descending below take-off height (glide and climb do descend).
	if onGround then
		s.airborneFor = 0
		s.airStartY = pos.Y
	else
		if s.airborneFor == 0 then
			s.airStartY = s.lastPos.Y
		end
		s.airborneFor += dt
		if s.airborneFor > G.HoverLimit and (s.airStartY - pos.Y) < G.HoverDescend then
			s.strikes += 1
			log(player, s, "hover", `air={string.format("%.1f", s.airborneFor)}s`)
			if G.HoverEnforce then
				rubberBand(character, root, s, player)
				return
			end
			s.airborneFor = 0
		end
	end

	s.lastPos = pos
	-- Only grounded, plausible positions become rubber-band targets.
	if onGround and excess == 0 then
		s.lastValid = root.CFrame
	end
end

-- ---------------------------------------------------------------- API

-- Call before any server-caused movement (jump pads, geysers, ziplines, teleports, knockback).
function MovementGuard.exempt(player: Player, seconds: number, _reason: string?)
	local s = states[player]
	if s and type(seconds) == "number" then
		s.exemptUntil = math.max(s.exemptUntil, os.clock() + math.clamp(seconds, 0, 30))
	end
end

function MovementGuard.getStrikes(player: Player): number
	local s = states[player]
	return if s then s.strikes else 0
end

-- ---------------------------------------------------------------- MoveEvent (C->S)

local function onMoveEvent(player: Player, kind: any)
	if type(kind) ~= "string" then
		return
	end
	local s = states[player]
	if not s then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	local now = os.clock()
	if kind == "SlideStart" then
		-- Only from the ground (the server ray is lenient: 1.5 studs below the feet).
		if grounded(root, humanoid) then
			s.slideUntil = now + Movement.SlidingAttrTimeout
			player:SetAttribute("Sliding", true)
		end
	elseif kind == "SlideEnd" then
		s.slideUntil = 0
		player:SetAttribute("Sliding", false)
	elseif kind == "Hop" then
		if now - s.lastHopAt < Movement.HopMinInterval then
			return
		end
		s.lastHopAt = now
		local chain = player:GetAttribute("HopChain")
		player:SetAttribute("HopChain", (if type(chain) == "number" then chain else 0) + 1)
		local ProgressionService = Registry.find("ProgressionService")
		if ProgressionService then
			pcall(ProgressionService.recordStat, player, "Hops", 1)
		end
	elseif kind == "HopReset" then
		player:SetAttribute("HopChain", 0)
	end
end

-- ---------------------------------------------------------------- lifecycle

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function()
		states[player] = nil -- fresh state (with spawn grace) on the next sample
		player:SetAttribute("Sliding", false)
		player:SetAttribute("HopChain", 0)
		task.defer(refreshFilter)
	end)
	player.CharacterRemoving:Connect(function()
		task.defer(refreshFilter)
	end)
end

function MovementGuard.init()
	Net.onServerEvent("MoveEvent", Movement.MoveEventRate, onMoveEvent)
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		task.defer(refreshFilter)
	end)
end

function MovementGuard.start()
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	refreshFilter()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < G.Interval then
			return
		end
		local step = acc
		acc = 0
		for _, player in Players:GetPlayers() do
			local ok, err = pcall(sample, player, step)
			if not ok then
				warn(`[MovementGuard] sample failed for {player.Name}: {err}`)
			end
		end
	end)
end

return MovementGuard
