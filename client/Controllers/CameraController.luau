--!strict
-- CameraController (A06, domaine avatar) : caméra 3e personne derrière le joueur, pensée mobile.
-- Design : docs/dossier/50-classes-avatar-mouvement.md section 3. Vault fwjelaa : « Camera Systems » 4 et 7,
-- « Camera Obstruction Handling - Occlusion Modes, Fades and Collision », « Touch Gestures - Pinch, Pan,
-- Swipe and Long Press ».
--
-- Caméra Scriptable (le module caméra par défaut ne fait plus rien), haute et dézoomée pour lire la horde.
-- Les armes tirent seules : la caméra sert à voir et à se déplacer (déplacement relatif à la caméra,
-- fait par les contrôles par défaut via CurrentCamera).
-- Rotation : glissé d'un doigt sur la moitié droite de l'écran, clic droit maintenu + souris,
-- stick droit (action Look), flèches gauche / droite. Zoom : pincement, molette, I / O, gâchettes hautes.
-- Collision : Spherecast depuis la tête vers la caméra, entrée immédiate, sortie lente ; troncs et poteaux
-- ignorés (ils ne font que passer devant). Personnage local estompé si la caméra est trop près.
-- Un seul propriétaire du FOV : base + ouverture avec la vitesse.
--
-- API (client) :
--   CameraController.getYaw() -> number              -- radians, 0 = regarde vers -Z
--   CameraController.setEnabled(on)                  -- off = rend la caméra à Roblox (Custom), ex. cinématique
--   CameraController.setSensitivity(mult)            -- réglage joueur (SettingsUI), 0.25..3
--   CameraController.setDistance(studs) / getDistance() · setPitch(degrees) / getPitch()
--   CameraController.shake(strength 0..1, seconds?)  -- secousse additive, ne dérive jamais

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Registry = require(Shared:WaitForChild("Registry"))
local Movement = require(Shared:WaitForChild("Config"):WaitForChild("Movement"))

local C = Movement.Camera

local CameraController = {}

local player = Players.LocalPlayer

local enabled = true
local sensitivity = 1
local yaw = 0
local pitch = math.rad(C.Pitch)
local targetDistance = C.Distance
local distance = C.Distance
local collisionDistance = math.huge -- distance libre actuelle (entrée immédiate, sortie lente)
local focus: Vector3? = nil
local fov = C.FieldOfView
local lastManualInput = -math.huge

local shakeUntil = 0
local shakeStart = 0
local shakeStrength = 0

local mouseRotating = false
local lastMousePos: Vector3? = nil

type TouchInfo = { last: Vector2 }
local touches: { [InputObject]: TouchInfo } = {}
local pinchStartDist = 0
local pinchStartZoom = 0

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local fadeParts: { BasePart } = {}
local fadeValue = 0
local fadeConn: RBXScriptConnection? = nil

-- Filtre des lancers : les personnages (copie gardée ici pour ne pas relire la propriété à chaque image),
-- et une liste réutilisée pour ignorer les obstacles fins.
local filterBase: { Instance } = {}
local filterWithProps: { Instance } = {}

-- ---------------------------------------------------------------- helpers

local function wrapAngle(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

local function clampPitch()
	pitch = math.clamp(pitch, math.rad(C.MinPitch), math.rad(C.MaxPitch))
end

local function clampZoom(d: number): number
	return math.clamp(d, C.MinDistance, C.MaxDistance)
end

local function rotate(dYawDeg: number, dPitchDeg: number)
	yaw = wrapAngle(yaw + math.rad(dYawDeg))
	pitch += math.rad(dPitchDeg)
	clampPitch()
	lastManualInput = os.clock()
end

local function inputController(): any
	return Registry.find("InputController")
end

local function deviceKind(): string
	local p = UserInputService.PreferredInput
	if p == Enum.PreferredInput.Touch then
		return "Touch"
	elseif p == Enum.PreferredInput.Gamepad then
		return "Gamepad"
	end
	return "Mouse"
end

local function refreshFilter()
	table.clear(filterBase)
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(filterBase, p.Character)
		end
	end
	rayParams.FilterDescendantsInstances = filterBase
end

local function refreshFadeParts(character: Model?)
	table.clear(fadeParts)
	fadeValue = 0
	if not character then
		return
	end
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(fadeParts, d)
		end
	end
end

local function setFade(value: number)
	value = math.floor(value * 10 + 0.5) / 10 -- par paliers : pas d'écriture à chaque image
	if value == fadeValue then
		return
	end
	fadeValue = value
	for _, part in fadeParts do
		if part.Parent then
			part.LocalTransparencyModifier = value
		end
	end
end

-- Un obstacle « fin » (tronc, poteau, lampadaire) ne tire pas la caméra : sa 2e plus grande dimension est petite.
local function isThinProp(part: BasePart): boolean
	if part:IsA("Terrain") then
		return false
	end
	local s = part.Size
	local a, b, c = s.X, s.Y, s.Z
	-- 2e plus grande des trois
	local second = math.max(math.min(a, b), math.min(math.max(a, b), c))
	return second <= C.ThinPropStuds
end

-- Distance libre entre l'origine (dans la tête du personnage) et la caméra voulue.
local function freeDistance(origin: Vector3, dir: Vector3, want: number): number
	local ignoring = false
	local result = want
	for _ = 1, 4 do
		local hit = Workspace:Spherecast(origin, C.CollisionRadius, dir * want, rayParams)
		if not hit then
			break
		end
		local part = hit.Instance
		if part:IsA("BasePart") and isThinProp(part) then
			if not ignoring then
				ignoring = true
				table.clear(filterWithProps)
				table.move(filterBase, 1, #filterBase, 1, filterWithProps)
			end
			table.insert(filterWithProps, part)
			rayParams.FilterDescendantsInstances = filterWithProps
		else
			result = math.max(hit.Distance - C.CollisionMargin, C.CollisionMinDistance)
			break
		end
	end
	if ignoring then
		rayParams.FilterDescendantsInstances = filterBase
	end
	return result
end

-- ---------------------------------------------------------------- input

local function screenSize(): Vector2
	local cam = Workspace.CurrentCamera
	return if cam then cam.ViewportSize else Vector2.new(1280, 720)
end

local function cameraTouchCount(): number
	local n = 0
	for _ in touches do
		n += 1
	end
	return n
end

local function pinchDistance(): number
	local a: Vector2?, b: Vector2? = nil, nil
	for _, info in touches do
		if not a then
			a = info.last
		elseif not b then
			b = info.last
		end
	end
	if a and b then
		return (a - b).Magnitude
	end
	return 0
end

local function onInputBegan(input: InputObject, processed: boolean)
	if not enabled then
		return
	end
	local t = input.UserInputType
	if t == Enum.UserInputType.Touch then
		if processed then
			return -- doigt posé sur un bouton ou sur le joystick
		end
		local size = screenSize()
		if input.Position.X < size.X * C.TouchZoneMinX then
			return -- moitié gauche : déplacement
		end
		touches[input] = { last = Vector2.new(input.Position.X, input.Position.Y) }
		if cameraTouchCount() == 2 then
			pinchStartDist = pinchDistance()
			pinchStartZoom = targetDistance
		end
	elseif t == Enum.UserInputType.MouseButton2 and not processed then
		mouseRotating = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
	end
end

local function onInputChanged(input: InputObject, processed: boolean)
	if not enabled then
		return
	end
	local t = input.UserInputType
	if t == Enum.UserInputType.Touch then
		local info = touches[input]
		if not info then
			return
		end
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		local delta = pos - info.last
		info.last = pos
		local n = cameraTouchCount()
		if n == 1 then
			local k = C.TouchDegreesPerScreen / math.max(screenSize().Y, 1) * sensitivity
			rotate(-delta.X * k, delta.Y * k * C.TouchPitchMult)
		elseif n == 2 and pinchStartDist > 1 then
			local ratio = pinchDistance() / pinchStartDist
			if ratio > 0.05 then
				targetDistance = clampZoom(pinchStartZoom / ratio ^ C.PinchPower)
			end
		end
	elseif t == Enum.UserInputType.MouseMovement then
		-- Delta de l'événement (curseur verrouillé) ; repli sur l'écart de position quand le delta est nul
		-- (bureau à distance, certains pavés tactiles, entrées injectées par les tests).
		local pos = input.Position
		local d = input.Delta
		if d.Magnitude < 1e-4 and lastMousePos then
			d = pos - lastMousePos
		end
		lastMousePos = pos
		if mouseRotating then
			local k = C.MouseDegreesPerPixel * sensitivity
			rotate(-d.X * k, d.Y * k)
		end
	elseif t == Enum.UserInputType.MouseWheel and not processed then
		targetDistance = clampZoom(targetDistance - input.Position.Z * C.WheelStep)
	end
end

local function onInputEnded(input: InputObject, _processed: boolean)
	local t = input.UserInputType
	if t == Enum.UserInputType.Touch then
		if touches[input] then
			touches[input] = nil
			if cameraTouchCount() == 2 then
				pinchStartDist = pinchDistance()
				pinchStartZoom = targetDistance
			end
		end
	elseif t == Enum.UserInputType.MouseButton2 then
		if mouseRotating then
			mouseRotating = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end
end

local function pollDevices(dt: number)
	local ic = inputController()
	if not ic then
		return
	end
	local stick: Vector2 = ic.getVector("Look")
	local mag = stick.Magnitude
	if mag > C.GamepadDeadzone then
		local scaled = ((mag - C.GamepadDeadzone) / (1 - C.GamepadDeadzone)) ^ C.GamepadCurve
		local dir = stick / mag
		rotate(-dir.X * scaled * C.GamepadYawSpeed * sensitivity * dt, -dir.Y * scaled * C.GamepadPitchSpeed * sensitivity * dt)
	end
	local key = (if ic.isDown("CameraLeft") then 1 else 0) - (if ic.isDown("CameraRight") then 1 else 0)
	if key ~= 0 then
		rotate(key * C.KeyYawSpeed * dt, 0)
	end
end

-- Recentrage doux derrière la course, seulement en tactile / manette, sans entrée caméra récente,
-- et surtout quand on court vers l'avant (pas de spirale en courant de côté).
local function autoFollow(dt: number, flatVel: Vector3)
	local af = C.AutoFollow
	local kind = deviceKind()
	if not (af :: any)[kind] or os.clock() - lastManualInput < af.Delay then
		return
	end
	local speed = flatVel.Magnitude
	if speed < af.MinSpeed then
		return
	end
	local velYaw = math.atan2(-flatVel.X, -flatVel.Z)
	local diff = wrapAngle(velYaw - yaw)
	local maxA = math.rad(af.MaxAngle)
	if math.abs(diff) > maxA then
		return
	end
	local weight = 1 - math.abs(diff) / maxA
	yaw = wrapAngle(yaw + diff * weight * (1 - math.exp(-af.Rate * dt)))
end

-- ---------------------------------------------------------------- frame

local function step(dt: number)
	if not enabled then
		return
	end
	local cam = Workspace.CurrentCamera
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not cam or not root then
		return
	end
	if cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Scriptable
	end

	pollDevices(dt)

	local vel = root.AssemblyLinearVelocity
	local flatVel = Vector3.new(vel.X, 0, vel.Z)
	autoFollow(dt, flatVel)

	-- Suivi : horizontal serré, vertical doux (les sauts ne secouent pas l'image).
	local target = root.Position + Vector3.new(0, C.FocusHeight, 0)
	local f = focus or target
	local aXZ = 1 - math.exp(-C.FollowSharpness * dt)
	local aY = 1 - math.exp(-C.FollowSharpnessY * dt)
	f = Vector3.new(f.X + (target.X - f.X) * aXZ, f.Y + (target.Y - f.Y) * aY, f.Z + (target.Z - f.Z) * aXZ)
	if (target - f).Magnitude > 60 then
		f = target -- téléport / réapparition : pas de long travelling
	end
	focus = f

	distance += (targetDistance - distance) * (1 - math.exp(-C.ZoomSharpness * dt))

	local rot = CFrame.fromOrientation(-pitch, yaw, 0)
	local look = rot.LookVector
	local flatForward = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	local desired = f - look * distance + flatForward * C.FocusAhead

	-- Collision depuis la tête réelle (toujours dans le personnage, exclu du lancer).
	local origin = root.Position + Vector3.new(0, C.FocusHeight, 0)
	local toCam = desired - origin
	local want = toCam.Magnitude
	local finalPos = desired
	if want > 0.01 then
		local dir = toCam / want
		local free = freeDistance(origin, dir, want)
		if free < collisionDistance then
			collisionDistance = free -- entrée immédiate
		else
			collisionDistance += (free - collisionDistance) * (1 - math.exp(-C.CollisionOutSharpness * dt))
		end
		local d = math.min(collisionDistance, want)
		finalPos = origin + dir * d
	end

	local camCF = CFrame.lookAt(finalPos, finalPos + look)

	-- Secousse additive (recalculée de zéro à chaque image : aucune dérive).
	local now = os.clock()
	if now < shakeUntil then
		local life = (shakeUntil - now) / math.max(shakeUntil - shakeStart, 1e-3)
		local amp = math.rad(C.ShakeMaxAngle) * shakeStrength * life
		local w = C.ShakeFrequency
		camCF *= CFrame.Angles(math.sin(now * w) * amp, math.sin(now * w * 1.3 + 1.7) * amp * 0.6, 0)
	end
	cam.CFrame = camCF
	cam.Focus = CFrame.new(f) -- détail de rendu et streaming autour du joueur

	-- FOV : un seul propriétaire, s'ouvre avec la vitesse.
	local ratio = flatVel.Magnitude / Movement.DefaultWalkSpeed
	local open = math.clamp((ratio - C.SpeedFovFrom) / math.max(Movement.SlideMaxMult - C.SpeedFovFrom, 0.1), 0, 1)
	local wantFov = C.FieldOfView + C.SpeedFov * open
	fov += (wantFov - fov) * (1 - math.exp(-C.FovSharpness * dt))
	cam.FieldOfView = fov

	-- Estompe le personnage local si la caméra est collée à lui.
	local camDist = (finalPos - origin).Magnitude
	if camDist < C.FadeDistance then
		setFade(math.clamp(1 - (camDist - 1) / (C.FadeDistance - 1), 0, 0.9))
	elseif fadeValue ~= 0 then
		setFade(0)
	end
end

-- ---------------------------------------------------------------- API

function CameraController.getYaw(): number
	return yaw
end

function CameraController.setEnabled(on: boolean)
	enabled = on
	local cam = Workspace.CurrentCamera
	if cam then
		cam.CameraType = if on then Enum.CameraType.Scriptable else Enum.CameraType.Custom
	end
	if not on then
		table.clear(touches)
		if mouseRotating then
			mouseRotating = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
		setFade(0)
	end
end

function CameraController.setSensitivity(mult: number)
	if type(mult) == "number" and mult == mult then
		sensitivity = math.clamp(mult, 0.25, 3)
	end
end

function CameraController.setDistance(studs: number)
	if type(studs) == "number" and studs == studs then
		targetDistance = clampZoom(studs)
	end
end

function CameraController.getDistance(): number
	return targetDistance
end

-- Angle sous l'horizon, en degrés (borné par MinPitch / MaxPitch).
function CameraController.setPitch(degrees: number)
	if type(degrees) == "number" and degrees == degrees then
		pitch = math.rad(degrees)
		clampPitch()
	end
end

function CameraController.getPitch(): number
	return math.deg(pitch)
end

function CameraController.shake(strength: number, seconds: number?)
	local now = os.clock()
	local s = math.clamp(strength, 0, 1)
	-- La plus forte des secousses en cours gagne (pas d'empilement).
	if now < shakeUntil and s <= shakeStrength * (shakeUntil - now) / math.max(shakeUntil - shakeStart, 1e-3) then
		return
	end
	shakeStrength = s
	shakeStart = now
	shakeUntil = now + (seconds or C.ShakeTime)
end

-- ---------------------------------------------------------------- lifecycle

local function onCharacter(character: Model)
	focus = nil
	collisionDistance = math.huge
	-- Derrière le personnage à l'apparition.
	task.defer(function()
		local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 10)
		if root and root:IsA("BasePart") then
			local look = root.CFrame.LookVector
			yaw = math.atan2(-look.X, -look.Z)
		end
		refreshFadeParts(character)
	end)
	if fadeConn then
		fadeConn:Disconnect()
	end
	fadeConn = character.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			table.insert(fadeParts, d)
			d.LocalTransparencyModifier = fadeValue
		end
	end)
	task.defer(refreshFilter)
end

function CameraController.start()
	-- Pas de verrouillage Maj (Maj sert à glisser) : réglage de place StarterPlayer.EnableMouseLockOption = false.
	local cam = Workspace.CurrentCamera
	if cam then
		cam.FieldOfView = C.FieldOfView
	end

	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputChanged:Connect(onInputChanged)
	UserInputService.InputEnded:Connect(onInputEnded)
	UserInputService.WindowFocusReleased:Connect(function()
		-- Alt-Tab clic droit enfoncé : ne pas laisser le curseur verrouillé ni les doigts « posés ».
		table.clear(touches)
		if mouseRotating then
			mouseRotating = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end)

	local ic = inputController()
	if ic then
		ic.onAction("ZoomIn", function(pressed: boolean)
			if pressed then
				targetDistance = clampZoom(targetDistance - C.ZoomStep)
			end
		end)
		ic.onAction("ZoomOut", function(pressed: boolean)
			if pressed then
				targetDistance = clampZoom(targetDistance + C.ZoomStep)
			end
		end)
	end

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
	Players.PlayerAdded:Connect(function(p)
		p.CharacterAdded:Connect(function()
			task.defer(refreshFilter)
		end)
	end)
	for _, p in Players:GetPlayers() do
		if p ~= player then
			p.CharacterAdded:Connect(function()
				task.defer(refreshFilter)
			end)
		end
	end
	Players.PlayerRemoving:Connect(function()
		task.defer(refreshFilter)
	end)

	RunService:BindToRenderStep("CohueCamera", Enum.RenderPriority.Camera.Value + 1, step)
end

return CameraController
