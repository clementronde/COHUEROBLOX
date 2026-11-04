--!strict
-- MovementController (avatar domain): client feel layer on top of the default Humanoid controls.
-- Design: docs/dossier/50-classes-avatar-mouvement.md section 4. Vault: "Custom Character Controllers",
-- "Input Responsiveness Buffering and Coyote Time", "Mover Constraints and Physics Controllers".
--
-- Bunny-hop, jump buffer, coyote time, slide (LinearVelocity Plane), double jump, glide, short wall
-- climb, low gravity (VectorForce), card-choice slow (SlowMult / SlowUntil, GetServerTimeNow base),
-- MoveSpeed stat (Build remote), no fall damage, landing shockwave (local visual).
-- One writer of Humanoid.WalkSpeed: base(class) x stat x bunny-hop x slow.
-- API: MovementController.isSliding() -> boolean · MovementController.getHopBonus() -> number

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Registry = require(Shared:WaitForChild("Registry"))
local Types = require(Shared:WaitForChild("Types"))
local Config = Shared:WaitForChild("Config")
local Classes = require(Config:WaitForChild("Classes"))
local M = require(Config:WaitForChild("Movement"))

local MovementController = {}

local player = Players.LocalPlayer
local HST = Enum.HumanoidStateType

-- ---------------------------------------------------------------- state

local def: Types.ClassDef? = nil
local statMult = 1
local hopBonus = 0
local hopCount = 0

local humanoid: Humanoid? = nil
local root: BasePart? = nil
local charConns: { RBXScriptConnection } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local landedAt = -math.huge
local leftGroundAt = -math.huge
local jumpPressedAt = -math.huge
local jumpedSinceGrounded = false
local airJumpsLeft = 0
local climbLeft = 0
local peakY = 0
local airTurn = 0
local lastAirTurn = 0
local lastYaw: number? = nil

local sliding = false
local slideVel = Vector3.zero
local slideFlatTime = 0
local slideAirTime = 0
local slideAttachment: Attachment? = nil
local slideMover: LinearVelocity? = nil

local gravityAttachment: Attachment? = nil
local gravityForce: VectorForce? = nil

local moveEvent: RemoteEvent? = nil
local shockPool: { Part } = {}
local shockNext = 1

-- ---------------------------------------------------------------- helpers

local function send(kind: string)
	if moveEvent then
		moveEvent:FireServer(kind)
	end
end

local function classNumber(key: string, default: number): number
	local v = def and def[key]
	return if type(v) == "number" then v else default
end

local function baseWalk(): number
	return if def then def.walkSpeed else M.DefaultWalkSpeed
end

local function slowMult(): number
	local mult = player:GetAttribute("SlowMult")
	local untilT = player:GetAttribute("SlowUntil")
	if type(mult) == "number" and type(untilT) == "number" and Workspace:GetServerTimeNow() < untilT then
		return math.clamp(mult, 0.05, 1)
	end
	return 1
end

local function gravityMult(): number
	return classNumber("gravityMult", 1)
end

local function verifiedGround(): RaycastResult?
	local h, r = humanoid, root
	if not h or not r then
		return nil
	end
	local reach = h.HipHeight + r.Size.Y / 2 + 0.6
	local hit = Workspace:Raycast(r.Position, Vector3.new(0, -reach, 0), rayParams)
	if hit and hit.Normal.Y >= M.GroundNormalMinY then
		return hit
	end
	return nil
end

local function cameraYaw(): number?
	local cam = Workspace.CurrentCamera
	if not cam then
		return nil
	end
	local look = cam.CFrame.LookVector
	return math.atan2(-look.X, -look.Z)
end

local function applyWalkSpeed()
	local h = humanoid
	if not h then
		return
	end
	local speed = baseWalk() * statMult * (1 + hopBonus) * slowMult()
	if math.abs(h.WalkSpeed - speed) > 0.01 then
		h.WalkSpeed = speed
	end
	local jump = if def then def.jumpHeight else M.DefaultJumpHeight
	if h.UseJumpPower then
		h.UseJumpPower = false
	end
	if math.abs(h.JumpHeight - jump) > 0.01 then
		h.JumpHeight = jump
	end
end

local function resetHops()
	if hopBonus > 0 or hopCount > 0 then
		hopBonus = 0
		hopCount = 0
		send("HopReset")
	end
end

-- ---------------------------------------------------------------- landing shockwave (visual only)

local function makeShockPart(): Part
	local p = Instance.new("Part")
	p.Name = "LandingShockwave"
	p.Shape = Enum.PartType.Cylinder
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(235, 240, 255)
	p.Transparency = 1
	p.Size = Vector3.new(0.15, 1, 1)
	p.Parent = Workspace
	return p
end

local function shockwave(position: Vector3, strength: number)
	if #shockPool == 0 then
		return
	end
	local p = shockPool[shockNext]
	shockNext = shockNext % #shockPool + 1
	local radius = M.ShockwaveMaxRadius * math.clamp(strength, 0.4, 1)
	p.Size = Vector3.new(0.15, 1, 1)
	p.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	p.Transparency = 0.3
	TweenService:Create(p, TweenInfo.new(M.ShockwaveTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.15, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
end

-- ---------------------------------------------------------------- slide

local function endSlide()
	if not sliding then
		return
	end
	sliding = false
	if slideMover then
		slideMover:Destroy()
		slideMover = nil
	end
	if slideAttachment then
		slideAttachment:Destroy()
		slideAttachment = nil
	end
	send("SlideEnd")
end

local function slideCap(): number
	return baseWalk() * statMult * M.SlideMaxMult
end

local function startSlide()
	local h, r = humanoid, root
	if sliding or not h or not r or h.Health <= 0 then
		return
	end
	if not verifiedGround() then
		return
	end
	local v = r.AssemblyLinearVelocity
	local flat = Vector3.new(v.X, 0, v.Z)
	if flat.Magnitude < M.SlideMinSpeed then
		return
	end
	local boost = classNumber("slideBoost", M.SlideBoostDefault)
	local speed = math.min(math.max(flat.Magnitude, h.WalkSpeed) * boost, slideCap())
	slideVel = flat.Unit * speed
	slideFlatTime = 0
	slideAirTime = 0

	local att = Instance.new("Attachment")
	att.Name = "SlideAttachment"
	att.Parent = r
	local lv = Instance.new("LinearVelocity")
	lv.Name = "SlideVelocity"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	lv.PrimaryTangentAxis = Vector3.xAxis
	lv.SecondaryTangentAxis = Vector3.zAxis
	lv.PlaneVelocity = Vector2.new(slideVel.X, slideVel.Z)
	lv.ForceLimitsEnabled = true
	lv.ForceLimitMode = Enum.ForceLimitMode.Magnitude
	lv.MaxForce = r.AssemblyMass * 2000
	lv.Parent = r
	slideAttachment = att
	slideMover = lv
	sliding = true
	send("SlideStart")
end

local function updateSlide(dt: number)
	local h, r, lv = humanoid, root, slideMover
	if not h or not r or not lv then
		endSlide()
		return
	end
	local InputController = Registry.find("InputController")
	local held = InputController == nil or InputController.isDown("Slide")
	local ground = verifiedGround()
	if ground then
		slideAirTime = 0
		local n = ground.Normal
		local horizontal = Vector3.new(n.X, 0, n.Z)
		local slopeSin = horizontal.Magnitude
		if slopeSin > 0.08 then
			slideVel += horizontal.Unit * (Workspace.Gravity * gravityMult() * M.SlideSlopeGain * slopeSin * dt)
		else
			slideFlatTime += dt
		end
		-- Friction always applies; slopes beat it.
		local speed = slideVel.Magnitude
		if speed > 0 then
			slideVel = slideVel.Unit * math.max(0, speed - M.SlideFriction * dt)
		end
	else
		slideAirTime += dt
		if slideAirTime > 0.3 then
			endSlide()
			return
		end
	end
	-- Light steering toward the stick.
	local wish = h.MoveDirection
	local speed = slideVel.Magnitude
	if wish.Magnitude > 0.1 and speed > 0 then
		local dir = slideVel.Unit:Lerp(Vector3.new(wish.X, 0, wish.Z).Unit, math.min(1, 2 * dt))
		if dir.Magnitude > 1e-3 then
			slideVel = dir.Unit * speed
		end
	end
	speed = math.min(slideVel.Magnitude, slideCap())
	if speed > 0 then
		slideVel = slideVel.Unit * speed
	end
	if not held or speed < h.WalkSpeed * M.SlideEndMult or slideFlatTime > M.SlideMaxFlatTime then
		endSlide()
		return
	end
	lv.PlaneVelocity = Vector2.new(slideVel.X, slideVel.Z)
	h:Move(slideVel.Unit) -- keep the Humanoid agreeing with the mover (vault: Mover Constraints section 2)
end

-- ---------------------------------------------------------------- jumps

local function forceJump()
	local h = humanoid
	if not h or h.Health <= 0 then
		return
	end
	jumpedSinceGrounded = true
	jumpPressedAt = -math.huge
	h:ChangeState(HST.Jumping)
end

local function airJump()
	local h, r = humanoid, root
	if not h or not r then
		return
	end
	airJumpsLeft -= 1
	local g = Workspace.Gravity * gravityMult()
	local vy = math.sqrt(2 * g * h.JumpHeight)
	local v = r.AssemblyLinearVelocity
	r.AssemblyLinearVelocity = Vector3.new(v.X, vy, v.Z)
	peakY = r.Position.Y
end

local function isAirState(state: Enum.HumanoidStateType): boolean
	return state == HST.Freefall or state == HST.Jumping
end

local function onJumpAction(pressed: boolean)
	local h = humanoid
	if not pressed or not h or h.Health <= 0 then
		return
	end
	local state = h:GetState()
	if not isAirState(state) then
		h.Jump = true -- grounded: touch/UI buttons need this; keyboard already does it
		return
	end
	local now = os.clock()
	if not jumpedSinceGrounded and now - leftGroundAt <= M.CoyoteTime then
		forceJump()
	elseif airJumpsLeft > 0 then
		airJump()
	else
		jumpPressedAt = now -- jump buffer: fires on landing
	end
end

local function onStateChanged(old: Enum.HumanoidStateType, new: Enum.HumanoidStateType)
	local r = root
	local now = os.clock()
	if new == HST.Jumping then
		jumpedSinceGrounded = true
		local window = classNumber("bhopWindow", M.BhopWindow)
		local maxBonus = M.BhopMaxBonus
		if sliding then
			-- Jump at the bottom of a slope converts the slide's momentum.
			local converted = slideVel.Magnitude / math.max(1, baseWalk() * statMult) - 1
			hopBonus = math.clamp(converted, hopBonus, maxBonus)
			endSlide()
			send("Hop")
		elseif now - landedAt <= window then
			hopCount += 1
			local turned = (def and def.bhopNoTurn == true) or lastAirTurn >= M.BhopMinTurnDeg
			if turned then
				hopBonus = math.min(maxBonus, hopBonus + M.BhopGainPerHop)
			end
			send("Hop")
		end
		airTurn = 0
		lastYaw = cameraYaw()
		if r then
			peakY = r.Position.Y
		end
	elseif new == HST.Freefall then
		if old ~= HST.Jumping and not jumpedSinceGrounded then
			leftGroundAt = now -- walked off a ledge: coyote clock
			airTurn = 0
			lastYaw = cameraYaw()
		end
		if r and old ~= HST.Jumping then
			peakY = r.Position.Y
		end
	elseif new == HST.Landed then
		landedAt = now
		lastAirTurn = airTurn
		jumpedSinceGrounded = false
		leftGroundAt = -math.huge
		if verifiedGround() then
			airJumpsLeft = classNumber("airJumps", 0)
			climbLeft = classNumber("climbTime", 0)
		end
		local h = humanoid
		if r and h then
			local fall = peakY - r.Position.Y
			if fall >= M.ShockwaveMinFall then
				local feet = r.Position - Vector3.new(0, h.HipHeight + r.Size.Y / 2 - 0.1, 0)
				shockwave(feet, fall / (M.ShockwaveMinFall * 3))
			end
		end
		if now - jumpPressedAt <= M.JumpBuffer then
			task.defer(forceJump)
		end
	elseif new == HST.Running and isAirState(old) then
		-- Some landings go straight to Running.
		landedAt = now
		lastAirTurn = airTurn
		jumpedSinceGrounded = false
		if now - jumpPressedAt <= M.JumpBuffer then
			task.defer(forceJump)
		end
	end
end

-- ---------------------------------------------------------------- per-frame

local function wallAhead(): boolean
	local h, r = humanoid, root
	if not h or not r then
		return false
	end
	local look = r.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		return false
	end
	local hit = Workspace:Raycast(r.Position, flat.Unit * M.ClimbProbe, rayParams)
	if not hit or math.abs(hit.Normal.Y) >= 0.3 then
		return false
	end
	return h.MoveDirection:Dot(-hit.Normal) > 0.3
end

local function step(dt: number)
	local h, r = humanoid, root
	if not h or not r or h.Health <= 0 then
		return
	end
	applyWalkSpeed()

	-- Low gravity: constant upward force = mass * g * (1 - mult).
	local gf = gravityForce
	if gf then
		gf.Force = Vector3.new(0, r.AssemblyMass * Workspace.Gravity * (1 - gravityMult()), 0)
	end

	if sliding then
		updateSlide(dt)
	end

	local state = h:GetState()
	local airborne = isAirState(state)
	local now = os.clock()

	if airborne then
		peakY = math.max(peakY, r.Position.Y)
		local yaw = cameraYaw()
		if yaw and lastYaw then
			local d = yaw - lastYaw
			d = (d + math.pi) % (2 * math.pi) - math.pi
			airTurn += math.abs(math.deg(d))
		end
		lastYaw = yaw

		local InputController = Registry.find("InputController")
		local jumpHeld = InputController ~= nil and InputController.isDown("Jump")
		local v = r.AssemblyLinearVelocity
		if jumpHeld and climbLeft > 0 and wallAhead() then
			climbLeft -= dt
			r.AssemblyLinearVelocity = Vector3.new(v.X, M.ClimbSpeed, v.Z)
		elseif jumpHeld and def and def.glide == true and v.Y < -M.GlideFallSpeed then
			r.AssemblyLinearVelocity = Vector3.new(v.X, -M.GlideFallSpeed, v.Z)
		end
	else
		-- Bunny-hop bonus is lost after the window on the ground, or without move input.
		if hopBonus > 0 or hopCount > 0 then
			local window = classNumber("bhopWindow", M.BhopWindow)
			if (now - landedAt > window and not sliding) or h.MoveDirection.Magnitude < 0.1 then
				resetHops()
			end
		end
	end
end

-- ---------------------------------------------------------------- character binding

local function unbindCharacter()
	endSlide()
	for _, c in charConns do
		c:Disconnect()
	end
	table.clear(charConns)
	if gravityForce then
		gravityForce:Destroy()
		gravityForce = nil
	end
	if gravityAttachment then
		gravityAttachment:Destroy()
		gravityAttachment = nil
	end
	humanoid = nil
	root = nil
end

local function refreshGravity()
	local r = root
	if gravityMult() < 1 and r then
		if not gravityForce then
			local att = Instance.new("Attachment")
			att.Name = "LowGravityAttachment"
			att.Parent = r
			local vf = Instance.new("VectorForce")
			vf.Name = "LowGravity"
			vf.Attachment0 = att
			vf.RelativeTo = Enum.ActuatorRelativeTo.World
			vf.ApplyAtCenterOfMass = true
			vf.Force = Vector3.zero
			vf.Parent = r
			gravityAttachment = att
			gravityForce = vf
		end
	elseif gravityForce then
		gravityForce:Destroy()
		gravityForce = nil
		if gravityAttachment then
			gravityAttachment:Destroy()
			gravityAttachment = nil
		end
	end
end

local function refreshClass()
	local classId = player:GetAttribute("ClassId")
	def = if type(classId) == "string" then Classes[classId] else nil
	airJumpsLeft = classNumber("airJumps", 0)
	climbLeft = classNumber("climbTime", 0)
	refreshGravity()
	applyWalkSpeed()
end

local function bindCharacter(character: Model)
	unbindCharacter()
	local h = character:WaitForChild("Humanoid", 10)
	if not h or not h:IsA("Humanoid") or player.Character ~= character then
		return
	end
	local r = h.RootPart or character:WaitForChild("HumanoidRootPart", 10)
	if not r or not r:IsA("BasePart") or player.Character ~= character then
		return
	end
	humanoid = h
	root = r
	rayParams.FilterDescendantsInstances = { character }

	-- No fall damage / trips (state edits run on the owning client).
	h:SetStateEnabled(HST.FallingDown, false)
	h:SetStateEnabled(HST.Ragdoll, false)

	hopBonus = 0
	hopCount = 0
	landedAt = -math.huge
	leftGroundAt = -math.huge
	jumpPressedAt = -math.huge
	jumpedSinceGrounded = false
	peakY = r.Position.Y

	table.insert(charConns, h.StateChanged:Connect(onStateChanged))
	table.insert(charConns, h.Died:Connect(endSlide))
	refreshClass()
end

-- ---------------------------------------------------------------- lifecycle

function MovementController.isSliding(): boolean
	return sliding
end

function MovementController.getHopBonus(): number
	return hopBonus
end

function MovementController.init()
	for _ = 1, 2 do
		table.insert(shockPool, makeShockPart())
	end
end

function MovementController.start()
	local InputController = Registry.find("InputController")
	if InputController then
		InputController.onAction("Jump", onJumpAction)
		InputController.onAction("Slide", function(pressed: boolean)
			if pressed then
				startSlide()
			end
		end)
	else
		warn("[MovementController] InputController missing: slide/double jump disabled")
	end

	player:GetAttributeChangedSignal("ClassId"):Connect(refreshClass)
	player.CharacterAdded:Connect(bindCharacter)
	player.CharacterRemoving:Connect(unbindCharacter)
	if player.Character then
		task.spawn(bindCharacter, player.Character)
	end

	RunService.PreSimulation:Connect(step)

	-- Remotes last (they may wait for the server folder).
	moveEvent = Net.event("MoveEvent")
	Net.event("Build").OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" or type(payload.stats) ~= "table" then
			return
		end
		local ms = payload.stats.MoveSpeed
		if type(ms) == "number" and ms == ms then
			statMult = 1 + math.clamp(ms, -0.9, 5)
		end
	end)
end

return MovementController
