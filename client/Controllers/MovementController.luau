--!strict
-- MovementController (A06, domaine avatar) : couche de sensation au-dessus des contrôles Humanoid par défaut.
-- Design : docs/dossier/50-classes-avatar-mouvement.md section 4. Vault fwjelaa : « Custom Character
-- Controllers », « Input Responsiveness Buffering and Coyote Time », « Mover Constraints and Physics Controllers ».
--
-- Le déplacement reste aux contrôles Roblox (relatif à la caméra). Le saut est à nous : Humanoid.JumpHeight
-- est tenu à 0 (Espace / A / le bouton tactile Roblox ne sautent plus seuls, ce bouton se masque), et l'action
-- Jump de l'InputController lance un saut à la bonne vitesse verticale. Ça donne un contrôle exact du
-- tampon, du coyote time, du bunny-hop (appui neuf obligatoire : maintenir Saut ne relance pas) et du double saut.
--
-- Mécaniques : bunny-hop, saut tampon, coyote time, glissade (LinearVelocity Plane), glissade en pente,
-- conversion glissade -> saut, double saut, plané court, atterrissage lourd, gravité par classe (VectorForce),
-- ralenti de choix de carte (SlowMult / SlowUntil, base GetServerTimeNow), stat MoveSpeed (remote Build),
-- pas de dégâts de chute, onde d'atterrissage locale.
-- Un seul écrivain de Humanoid.WalkSpeed : marche(classe) x stat x bunny-hop x ralenti x contrecoup.
-- Poses de glissade / charge / atterrissage lourd : PlayerAnimator (démarré ici).
-- API : MovementController.isSliding() -> boolean · getHopBonus() -> number · getDebug() -> table

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Registry = require(Shared:WaitForChild("Registry"))
local M = require(Shared:WaitForChild("Config"):WaitForChild("Movement"))
local PlayerAnimator = require(script.Parent:WaitForChild("PlayerAnimator"))

type ClassMove = typeof(M.profile(nil))

local MovementController = {}

local player = Players.LocalPlayer
local HST = Enum.HumanoidStateType

-- ---------------------------------------------------------------- état

local prof: ClassMove = M.profile(nil)
local classId: string? = nil
local statMult = 1
local hopBonus = 0
local hopCount = 0

local humanoid: Humanoid? = nil
local root: BasePart? = nil
local charConns: { RBXScriptConnection } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local airborne = false
local landedAt = -math.huge
local leftGroundAt = -math.huge
local jumpPressedAt = -math.huge -- dernier appui non consommé (tampon)
local ourJumpAt = -math.huge
local jumpedSinceGrounded = false
local airJumpsLeft = 0
local glideLeft = 0
local peakY = 0
local landSlowUntil = 0
local landSlowMult = 1

local sliding = false
local slideVel = Vector3.zero
local slideFlatTime = 0
local slideAirTime = 0
local slideEndedAt = -math.huge
local slideExitSpeed = 0
local slideEntrySpeed = 0 -- vitesse au départ de la glissade (boost compris)
local slideEntryBonus = 0 -- bonus de bunny-hop au départ de la glissade
local slidePressedAt = -math.huge
local slideTouchMode = false
local slideAttachment: Attachment? = nil
local slideMover: LinearVelocity? = nil

local gravityAttachment: Attachment? = nil
local gravityForce: VectorForce? = nil

local moveEvent: RemoteEvent? = nil
local shockPool: { Part } = {}
local shockNext = 1

-- Journal de test (Studio seulement), lu par la BindableFunction LocalPlayer.CohueMoveDebug.
local IS_STUDIO = RunService:IsStudio()
local debugLog: { string } = {}
local function dlog(msg: string)
	if IS_STUDIO then
		table.insert(debugLog, string.format("%.3f %s", os.clock(), msg))
		if #debugLog > 300 then
			table.remove(debugLog, 1)
		end
	end
end

-- ---------------------------------------------------------------- aides

local function send(kind: string)
	if moveEvent then
		moveEvent:FireServer(kind)
	end
end

local function input(): any
	return Registry.find("InputController")
end

local function held(name: string): boolean
	local ic = input()
	return ic ~= nil and ic.isDown(name)
end

local function baseWalk(): number
	return M.walkSpeed(prof) * statMult
end

local function gravityMult(): number
	return prof.gravityMult or 1
end

local function gravity(): number
	return Workspace.Gravity * gravityMult()
end

local function slideTune(key: string, default: number): number
	local s = prof.slide
	local v = s and (s :: any)[key]
	return if type(v) == "number" then v else default
end

local function slowMult(): number
	local mult = player:GetAttribute("SlowMult")
	local untilT = player:GetAttribute("SlowUntil")
	local m = 1
	if type(mult) == "number" and type(untilT) == "number" and Workspace:GetServerTimeNow() < untilT then
		m = math.clamp(mult, 0.05, 1)
	end
	if os.clock() < landSlowUntil then
		m *= landSlowMult
	end
	return m
end

local function isAirState(state: Enum.HumanoidStateType): boolean
	return state == HST.Freefall or state == HST.Jumping
end

local function feetReach(h: Humanoid, r: BasePart): number
	return h.HipHeight + r.Size.Y / 2
end

local function verifiedGround(extraReach: number?): RaycastResult?
	local h, r = humanoid, root
	if not h or not r then
		return nil
	end
	local hit = Workspace:Raycast(r.Position, Vector3.new(0, -(feetReach(h, r) + M.GroundProbeExtra + (extraReach or 0)), 0), rayParams)
	if hit and hit.Normal.Y >= M.GroundNormalMinY then
		return hit
	end
	return nil
end

-- Vrai si le personnage touchera le sol dans moins de JumpBuffer secondes (un appui ici = saut tampon,
-- pas le double saut).
local function landingSoon(): boolean
	local h, r = humanoid, root
	if not h or not r then
		return false
	end
	local vy = r.AssemblyLinearVelocity.Y
	if vy >= 0 then
		return false
	end
	local reach = feetReach(h, r) + M.LandingSoonExtra + (-vy) * M.JumpBuffer
	return Workspace:Raycast(r.Position, Vector3.new(0, -reach, 0), rayParams) ~= nil
end

local function applyWalkSpeed()
	local h = humanoid
	if not h then
		return
	end
	local speed = baseWalk() * (1 + hopBonus) * slowMult()
	if math.abs(h.WalkSpeed - speed) > 0.01 then
		h.WalkSpeed = speed
	end
	if h.UseJumpPower then
		h.UseJumpPower = false
	end
	if h.JumpHeight ~= 0 then
		h.JumpHeight = 0 -- le saut passe par l'action Jump (voir en-tête)
	end
end

local function resetHops()
	if hopBonus > 0 or hopCount > 0 then
		dlog(`hopReset bonus={string.format("%.2f", hopBonus)} hops={hopCount}`)
		hopBonus = 0
		hopCount = 0
		send("HopReset")
	end
end

local function cameraShake(strength: number)
	local cam = Registry.find("CameraController")
	if cam and cam.shake then
		cam.shake(strength)
	end
end

-- ---------------------------------------------------------------- onde d'atterrissage (visuel seul)

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
	p.Color = Color3.fromRGB(255, 236, 200)
	p.Transparency = 1
	p.Size = Vector3.new(0.15, 1, 1)
	p.Parent = Workspace
	return p
end

local function shockwave(position: Vector3, radius: number)
	if #shockPool == 0 then
		return
	end
	local p = shockPool[shockNext]
	shockNext = shockNext % #shockPool + 1
	p.Size = Vector3.new(0.15, 1, 1)
	p.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	p.Transparency = 0.3
	TweenService:Create(p, TweenInfo.new(M.ShockwaveTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.15, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
end

-- ---------------------------------------------------------------- glissade

local function slideCap(): number
	return baseWalk() * M.slideMaxMult(prof)
end

-- silent : fin par un saut, le Hop qui suit suffit au serveur (une remote de moins par saut de glissade).
local function endSlide(silent: boolean?)
	if not sliding then
		return
	end
	sliding = false
	slideEndedAt = os.clock()
	slideExitSpeed = slideVel.Magnitude
	if slideMover then
		slideMover.Enabled = false
	end
	dlog(`slideEnd speed={string.format("%.1f", slideExitSpeed)}`)
	if not silent then
		send("SlideEnd")
	end
end

local function startSlide()
	local h, r, lv = humanoid, root, slideMover
	if sliding or not h or not r or not lv or h.Health <= 0 then
		return
	end
	local now = os.clock()
	if now - slideEndedAt < M.SlideCooldown then
		return
	end
	if not verifiedGround() then
		return
	end
	local v = r.AssemblyLinearVelocity
	local flat = Vector3.new(v.X, 0, v.Z)
	local wish = Vector3.new(h.MoveDirection.X, 0, h.MoveDirection.Z)
	local dir: Vector3
	if flat.Magnitude >= M.SlideMinSpeed then
		dir = flat.Unit
	elseif wish.Magnitude > 0.1 then
		dir = wish.Unit -- démarrage à l'arrêt : la direction du stick suffit
	else
		return
	end
	local speed = math.min(math.max(flat.Magnitude, h.WalkSpeed) * slideTune("boost", M.SlideBoost), slideCap() * slowMult())
	slideVel = dir * speed
	slideEntrySpeed = speed
	slideEntryBonus = hopBonus
	slideFlatTime = 0
	slideAirTime = 0
	slidePressedAt = -math.huge
	lv.PlaneVelocity = Vector2.new(slideVel.X, slideVel.Z)
	lv.MaxForce = r.AssemblyMass * 2000
	lv.Enabled = true
	sliding = true
	slideTouchMode = M.SlideTouchTap and UserInputService.PreferredInput == Enum.PreferredInput.Touch
	dlog(`slideStart speed={string.format("%.1f", speed)}`)
	send("SlideStart")
end

local function updateSlide(dt: number)
	local h, r, lv = humanoid, root, slideMover
	if not h or not r or not lv then
		endSlide()
		return
	end
	local ground = verifiedGround()
	if ground then
		slideAirTime = 0
		local n = ground.Normal
		local horizontal = Vector3.new(n.X, 0, n.Z)
		local slopeSin = horizontal.Magnitude
		if slopeSin > M.SlideSlopeMin then
			-- La pente pousse vers le bas : g x part x sin(pente).
			slideVel += horizontal.Unit * (gravity() * M.SlideSlopeGain * slopeSin * dt)
		else
			slideFlatTime += dt
		end
		local speed = slideVel.Magnitude
		if speed > 0 then
			slideVel = slideVel.Unit * math.max(0, speed - slideTune("friction", M.SlideFriction) * dt)
		end
	else
		slideAirTime += dt
		if slideAirTime > M.SlideAirEnd then
			endSlide()
			return
		end
	end
	-- Braquage vers le stick (relatif à la caméra).
	local wish = h.MoveDirection
	local speed = slideVel.Magnitude
	if wish.Magnitude > 0.1 and speed > 0 then
		local flatWish = Vector3.new(wish.X, 0, wish.Z).Unit
		local dir = slideVel.Unit:Lerp(flatWish, math.min(1, slideTune("steer", M.SlideSteer) * dt))
		if dir.Magnitude > 1e-3 then
			slideVel = dir.Unit * speed
		end
	end
	speed = math.min(slideVel.Magnitude, slideCap() * slowMult()) -- ralenti (choix de carte, à terre) compris
	if speed > 0 then
		slideVel = slideVel.Unit * speed
	end
	local released = not slideTouchMode and not held("Slide")
	local tooSlow = speed < baseWalk() * slideTune("endMult", M.SlideEndMult)
	if released or tooSlow or slideFlatTime > slideTune("maxFlatTime", M.SlideMaxFlatTime) then
		endSlide()
		return
	end
	lv.PlaneVelocity = Vector2.new(slideVel.X, slideVel.Z)
	h:Move(slideVel.Unit) -- l'Humanoid suit le mover (vault : Mover Constraints section 2)
end

-- ---------------------------------------------------------------- sauts

local function feetPosition(): Vector3?
	local h, r = humanoid, root
	if not h or not r then
		return nil
	end
	return r.Position - Vector3.new(0, feetReach(h, r) - 0.1, 0)
end

local function launch(heightMult: number)
	local h, r = humanoid, root
	if not h or not r then
		return
	end
	local vy = math.sqrt(2 * gravity() * M.jumpHeight(prof) * heightMult)
	ourJumpAt = os.clock()
	jumpedSinceGrounded = true
	jumpPressedAt = -math.huge
	airborne = true
	peakY = r.Position.Y
	h:ChangeState(HST.Jumping)
	local v = r.AssemblyLinearVelocity
	r.AssemblyLinearVelocity = Vector3.new(v.X, vy, v.Z)
end

-- Saut depuis le sol (ou coyote). Décide du bunny-hop :
--   * relance dans la fenêtre après l'atterrissage, en gardant sa vitesse : +3 % ;
--   * saut pendant une glissade (ou moins de SlideJumpGrace après) : le bonus d'entrée de la glissade
--     plus l'élan gagné ou perdu pendant la glissade. Au plat ça conserve le bonus (le boost de départ ne
--     compte pas, sinon glisser-sauter remplacerait le timing), en pente ça convertit la vitesse gagnée.
local function groundJump()
	local h, r = humanoid, root
	if not h or not r or h.Health <= 0 then
		return
	end
	local now = os.clock()
	local base = math.max(baseWalk(), 1)
	if sliding or now - slideEndedAt <= M.SlideJumpGrace then
		local speed = if sliding then slideVel.Magnitude else slideExitSpeed
		endSlide(true)
		slideEndedAt = -math.huge -- grâce consommée
		local delta = (speed - slideEntrySpeed) / base
		local bonus = slideEntryBonus + delta
		if delta >= -0.02 then
			bonus += M.BhopGainPerHop -- élan gardé : compte comme un hop
		end
		hopBonus = math.clamp(bonus, 0, M.BhopMaxBonus)
		hopCount += 1
		dlog(`slideJump speed={string.format("%.1f", speed)} entry={string.format("%.1f", slideEntrySpeed)} bonus={string.format("%.2f", hopBonus)}`)
		send("Hop")
	elseif now - landedAt <= M.BhopWindow then
		local v = r.AssemblyLinearVelocity
		local flat = Vector3.new(v.X, 0, v.Z).Magnitude
		if flat >= h.WalkSpeed * M.BhopKeepSpeed then
			hopCount += 1
			local wasMax = hopBonus >= M.BhopMaxBonus - 1e-6
			hopBonus = math.min(M.BhopMaxBonus, hopBonus + M.BhopGainPerHop)
			if not wasMax and hopBonus >= M.BhopMaxBonus - 1e-6 then
				local feet = feetPosition()
				if feet then
					shockwave(feet, 5) -- plafond atteint
				end
			end
			dlog(`hop dtLand={string.format("%.3f", now - landedAt)} bonus={string.format("%.2f", hopBonus)}`)
			send("Hop")
		else
			dlog(`hop blocked speed={string.format("%.1f", flat)}`) -- contre un mur : pas de gain
		end
	else
		dlog(`jump dtLand={string.format("%.3f", math.min(now - landedAt, 99))}`)
	end
	launch(1)
	applyWalkSpeed()
end

local function airJump()
	airJumpsLeft -= 1
	dlog("airJump")
	local feet = feetPosition()
	if feet then
		shockwave(feet, 3) -- petit anneau sous les pieds : le double saut se voit
	end
	launch(M.AirJumpMult)
end

local function onJumpAction(pressed: boolean)
	local h = humanoid
	if not pressed or not h or h.Health <= 0 then
		return
	end
	if h.SeatPart then
		h.Sit = false
		h.Jump = true
		return
	end
	local now = os.clock()
	local state = h:GetState()
	if state == HST.Swimming then
		h.Jump = true -- nage vers le haut (comportement Roblox), pas de saut piloté dans l'eau
		return
	end
	jumpPressedAt = now
	if not isAirState(state) then
		groundJump()
	elseif not jumpedSinceGrounded and now - leftGroundAt <= M.CoyoteTime then
		groundJump() -- coyote time
	elseif airJumpsLeft > 0 and not landingSoon() then
		airJump()
	end
	-- sinon : tampon, consommé à l'atterrissage
end

local function onSlideAction(pressed: boolean)
	local h = humanoid
	if not h or h.Health <= 0 then
		return
	end
	if not pressed then
		return -- la fin au relâchement est gérée par updateSlide (hors tactile)
	end
	if sliding then
		if slideTouchMode then
			endSlide() -- tactile : deuxième appui = stop
		end
		return
	end
	slidePressedAt = os.clock()
	if not isAirState(h:GetState()) then
		startSlide()
	end
end

-- ---------------------------------------------------------------- états

local function onLanded()
	local h, r = humanoid, root
	if not airborne or not h or not r then
		return
	end
	local now = os.clock()
	if now - ourJumpAt < M.LandIgnoreAfterJump then
		return -- l'Humanoid repasse parfois une image au sol juste après notre saut : pas un atterrissage
	end
	airborne = false
	landedAt = now
	jumpedSinceGrounded = false
	leftGroundAt = -math.huge
	-- À l'état Landed le personnage est encore un peu au-dessus du sol : rayon plus long. Le pas suivant
	-- recharge aussi (step), pour les sauts relancés à l'image même de l'atterrissage.
	if verifiedGround(M.LandProbeExtra) then
		airJumpsLeft = prof.airJumps or 0
		glideLeft = if prof.glide then prof.glide.duration else 0
	end

	local fall = peakY - r.Position.Y
	dlog(`land fall={string.format("%.1f", fall)} speed={string.format("%.1f", Vector3.new(r.AssemblyLinearVelocity.X, 0, r.AssemblyLinearVelocity.Z).Magnitude)}`)
	local feet = r.Position - Vector3.new(0, feetReach(h, r) - 0.1, 0)
	local hl = prof.heavyLanding
	if hl and fall >= hl.minFall then
		landSlowUntil = now + hl.slowTime
		landSlowMult = hl.slowMult
		PlayerAnimator.heavyLand(player, math.clamp(fall / (hl.minFall * 2), 0.5, 1))
		shockwave(feet, M.ShockwaveMaxRadius * math.clamp(fall / (hl.minFall * 3), 0.5, 1))
		cameraShake(hl.shake * math.clamp(fall / (hl.minFall * 2), 0.5, 1))
	elseif fall >= M.ShockwaveMinFall then
		shockwave(feet, M.ShockwaveMaxRadius * math.clamp(fall / (M.ShockwaveMinFall * 3), 0.4, 1))
		cameraShake(0.35)
	end

	-- Entrées tamponnées : le saut d'abord, sinon la glissade (Glisser maintenu ou pressé juste avant).
	if now - jumpPressedAt <= M.JumpBuffer then
		task.defer(groundJump)
	elseif held("Slide") or now - slidePressedAt <= M.SlideBuffer then
		task.defer(startSlide)
	end
end

local function onStateChanged(old: Enum.HumanoidStateType, new: Enum.HumanoidStateType)
	local r = root
	local now = os.clock()
	if new == HST.Jumping or new == HST.Freefall then
		if not airborne then
			airborne = true
			if r then
				peakY = r.Position.Y
			end
			if new == HST.Freefall and not jumpedSinceGrounded and now - ourJumpAt > M.CoyoteIgnoreAfterJump then
				leftGroundAt = now -- quitté un rebord sans sauter : horloge du coyote time
			end
		end
	elseif new == HST.Landed or new == HST.Running or new == HST.RunningNoPhysics then
		if isAirState(old) or airborne then
			onLanded()
		end
	end
end

-- ---------------------------------------------------------------- image par image

local function step(dt: number)
	local h, r = humanoid, root
	if not h or not r or h.Health <= 0 then
		return
	end
	applyWalkSpeed()

	local gf = gravityForce
	if gf then
		gf.Force = Vector3.new(0, r.AssemblyMass * Workspace.Gravity * (1 - gravityMult()), 0)
	end

	if sliding then
		updateSlide(dt)
	end

	local state = h:GetState()
	local now = os.clock()
	if airborne and not isAirState(state) and now - ourJumpAt >= M.LandIgnoreAfterJump and verifiedGround() then
		onLanded() -- atterrissage que StateChanged a laissé passer (trop tôt après le saut)
	end
	if isAirState(state) then
		peakY = math.max(peakY, r.Position.Y)
		local glide = prof.glide
		if glide and glideLeft > 0 and held("Jump") then
			local v = r.AssemblyLinearVelocity
			if v.Y < -glide.fallSpeed then
				glideLeft -= dt
				r.AssemblyLinearVelocity = Vector3.new(v.X, -glide.fallSpeed, v.Z)
			end
		end
	else
		-- Recharge du double saut et du plané une fois vraiment au sol (rayon vérifié, normale du sol).
		local maxAir = prof.airJumps or 0
		local maxGlide = if prof.glide then prof.glide.duration else 0
		if (airJumpsLeft < maxAir or glideLeft < maxGlide) and now - ourJumpAt > M.HopResetDelay and verifiedGround() then
			airJumpsLeft = maxAir
			glideLeft = maxGlide
		end
	end
	if not isAirState(state) and (hopBonus > 0 or hopCount > 0) and now - ourJumpAt > M.HopResetDelay then
		-- Bonus perdu après la fenêtre au sol, ou sans entrée de déplacement.
		if (now - landedAt > M.BhopWindow and not sliding) or h.MoveDirection.Magnitude < 0.1 then
			resetHops()
		end
	end
end

-- ---------------------------------------------------------------- personnage

local function destroyMovers()
	for _, inst in { slideMover, slideAttachment, gravityForce, gravityAttachment } :: { Instance? } do
		if inst then
			inst:Destroy()
		end
	end
	slideMover, slideAttachment, gravityForce, gravityAttachment = nil, nil, nil, nil
end

local function unbindCharacter()
	endSlide()
	for _, c in charConns do
		c:Disconnect()
	end
	table.clear(charConns)
	destroyMovers()
	humanoid = nil
	root = nil
end

local function refreshGravity()
	local r = root
	if gravityMult() ~= 1 and r then
		if not gravityForce then
			local att = Instance.new("Attachment")
			att.Name = "CohueGravityAttachment"
			att.Parent = r
			local vf = Instance.new("VectorForce")
			vf.Name = "CohueGravity"
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

local function makeSlideMover(r: BasePart)
	local att = Instance.new("Attachment")
	att.Name = "CohueSlideAttachment"
	att.Parent = r
	local lv = Instance.new("LinearVelocity")
	lv.Name = "CohueSlide"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	lv.PrimaryTangentAxis = Vector3.xAxis
	lv.SecondaryTangentAxis = Vector3.zAxis
	lv.ForceLimitsEnabled = true
	lv.ForceLimitMode = Enum.ForceLimitMode.Magnitude
	lv.MaxForce = 0
	lv.Enabled = false
	lv.Parent = r
	slideAttachment = att
	slideMover = lv
end

local function refreshClass()
	local id = player:GetAttribute("ClassId")
	classId = if type(id) == "string" then id else nil
	prof = M.profile(classId)
	airJumpsLeft = prof.airJumps or 0
	glideLeft = if prof.glide then prof.glide.duration else 0
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

	-- Pas de dégâts de chute ni de chute à plat (les changements d'état se font sur le client propriétaire).
	h:SetStateEnabled(HST.FallingDown, false)
	h:SetStateEnabled(HST.Ragdoll, false)

	hopBonus = 0
	hopCount = 0
	airborne = false
	landedAt = -math.huge
	leftGroundAt = -math.huge
	jumpPressedAt = -math.huge
	jumpedSinceGrounded = false
	slideEndedAt = -math.huge
	landSlowUntil = 0
	peakY = r.Position.Y

	makeSlideMover(r)
	table.insert(charConns, h.StateChanged:Connect(onStateChanged))
	table.insert(charConns, h.Died:Connect(endSlide))
	refreshClass()
end

-- ---------------------------------------------------------------- API

function MovementController.isSliding(): boolean
	return sliding
end

function MovementController.getHopBonus(): number
	return hopBonus
end

-- Lecture pour les tests et le HUD de debug.
function MovementController.getDebug(): { [string]: any }
	local r = root
	local v = if r then r.AssemblyLinearVelocity else Vector3.zero
	return {
		classId = classId,
		speed = Vector3.new(v.X, 0, v.Z).Magnitude,
		walkSpeed = if humanoid then humanoid.WalkSpeed else 0,
		hopBonus = hopBonus,
		hopCount = hopCount,
		sliding = sliding,
		airborne = airborne,
		state = if humanoid then humanoid:GetState().Name else "none",
	}
end

function MovementController.init()
	for _ = 1, 3 do
		table.insert(shockPool, makeShockPart())
	end
end

function MovementController.start()
	local ic = input()
	if ic then
		ic.onAction("Jump", onJumpAction)
		ic.onAction("Slide", onSlideAction)
	else
		warn("[MovementController] InputController missing: jump and slide disabled")
	end

	player:GetAttributeChangedSignal("ClassId"):Connect(refreshClass)
	player.CharacterAdded:Connect(bindCharacter)
	player.CharacterRemoving:Connect(unbindCharacter)
	if player.Character then
		task.spawn(bindCharacter, player.Character)
	end

	RunService.PreSimulation:Connect(step)
	PlayerAnimator.start(MovementController)

	if IS_STUDIO then
		-- Point d'inspection pour les tests MCP : ("state") / ("log") / ("trigger", action, pressed) /
		-- ("cam", distance, pitch).
		local bf = Instance.new("BindableFunction")
		bf.Name = "CohueMoveDebug"
		bf.OnInvoke = function(cmd: any, a: any, b: any): any
			if cmd == "log" then
				local out = table.concat(debugLog, "\n")
				table.clear(debugLog)
				return out
			elseif cmd == "cam" then
				local cam = Registry.find("CameraController")
				if cam then
					cam.setDistance(a)
					cam.setPitch(b)
				end
				return true
			elseif cmd == "trigger" then
				local ic = input()
				if ic then
					ic.trigger(a, b == true)
				end
				return true
			end
			local d = MovementController.getDebug()
			local cam = Registry.find("CameraController")
			if cam then
				d.camYaw = math.deg(cam.getYaw())
				d.camDistance = cam.getDistance()
			end
			return d
		end
		bf.Parent = player
	end

	-- Remotes en dernier (elles peuvent attendre le dossier du serveur).
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
