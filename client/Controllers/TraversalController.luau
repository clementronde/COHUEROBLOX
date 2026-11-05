--!strict
-- TraversalController (A06-07, domaine avatar) : tremplins, geysers et tyroliennes côté client.
-- Démarré par MovementController (module simple, pas dans l'ordre de démarrage). Design : dossier 50 §11.
--
-- Le client applique le mouvement (personnage piloté par le client, mode classique) ; le serveur
-- (TraversalGuard) voit le joueur dans la même zone et exempte MovementGuard pour la durée du trajet.
--   Tremplin : entrer dans la zone lance une fois (relancer = ressortir de la zone).
--   Geyser   : pendant une éruption, lance une fois par éruption. Allume les effets « Eruption... » de l'objet.
--   Tyrolienne : s'approcher de Start accroche ; LinearVelocity le long du câble jusqu'à End ; Saut = lâcher.
-- API : TraversalController.isRiding() -> boolean · drop() · start(movementController)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Movement = require(Shared:WaitForChild("Config"):WaitForChild("Movement"))
local Traversal = require(Shared:WaitForChild("Traversal"))

local T = Movement.Traversal

local TraversalController = {}

local player = Players.LocalPlayer
local mc: any = nil -- MovementController (externalLaunch, getBaseWalk)

local usedPad: Instance? = nil -- tremplin déjà utilisé, tant qu'on n'est pas ressorti de sa zone
local usedEruption: { [Instance]: number } = {}
local fxState: { [Instance]: boolean } = {}

local ride: Traversal.Zipline? = nil
local rideT = 0
local rideEndedAt = -math.huge
local rideMover: LinearVelocity? = nil
local rideAttachment: Attachment? = nil

local function rootAndHumanoid(): (BasePart?, Humanoid?)
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	local r = h and h.RootPart
	if not h or not r or h.Health <= 0 then
		return nil, nil
	end
	return r, h
end

-- Effets de l'objet nommés « Eruption... » (ParticleEmitter, Beam, Light, Sound), allumés pendant l'éruption.
local function setEruptionFx(inst: Instance, on: boolean)
	if fxState[inst] == on then
		return
	end
	fxState[inst] = on
	for _, d in inst:GetDescendants() do
		if string.sub(d.Name, 1, 8) == "Eruption" then
			if d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Light") or d:IsA("Trail") then
				d.Enabled = on
			elseif d:IsA("Sound") then
				if on then
					d:Play()
				else
					d:Stop()
				end
			end
		end
	end
end

-- ---------------------------------------------------------------- tyrolienne

local function releaseRide()
	local z = ride
	ride = nil
	rideEndedAt = os.clock()
	local lv = rideMover
	if lv then
		lv.Enabled = false
	end
	local r, h = rootAndHumanoid()
	if h then
		h.PlatformStand = false
	end
	if r and z and mc then
		-- Lâcher à une vitesse que MovementGuard accepte de nouveau sans exemption.
		local speed = math.min(z.speed, mc.getBaseWalk() * T.ZiplineReleaseMult)
		local flat = Vector3.new(z.dir.X, 0, z.dir.Z)
		local v = if flat.Magnitude > 1e-3 then flat.Unit * speed else Vector3.zero
		r.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
	end
end

local function ensureMover(r: BasePart): LinearVelocity
	local lv = rideMover
	if lv and lv.Parent == r then
		return lv
	end
	if rideAttachment then
		rideAttachment:Destroy()
	end
	if lv then
		lv:Destroy()
	end
	local att = Instance.new("Attachment")
	att.Name = "CohueZiplineAttachment"
	att.Parent = r
	local mover = Instance.new("LinearVelocity")
	mover.Name = "CohueZipline"
	mover.Attachment0 = att
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	mover.ForceLimitsEnabled = true
	mover.ForceLimitMode = Enum.ForceLimitMode.Magnitude
	mover.MaxForce = r.AssemblyMass * 4000
	mover.Enabled = false
	mover.Parent = r
	rideAttachment = att
	rideMover = mover
	return mover
end

local function startRide(z: Traversal.Zipline, r: BasePart, h: Humanoid)
	if mc then
		mc.cancelSlide()
	end
	ride = z
	rideT = 0
	h.PlatformStand = true
	local lv = ensureMover(r)
	lv.MaxForce = r.AssemblyMass * 4000
	lv.VectorVelocity = z.dir * z.speed
	lv.Enabled = true
end

local function updateRide(dt: number, r: BasePart)
	local z = ride :: Traversal.Zipline
	rideT += z.speed * dt / z.length
	if rideT >= 1 then
		releaseRide()
		return
	end
	local target = z.a + (z.b - z.a) * rideT - Vector3.new(0, T.ZiplineHang, 0)
	local lv = rideMover
	if lv then
		lv.VectorVelocity = z.dir * z.speed + (target - r.Position) * T.ZiplineCorrect
	end
end

-- ---------------------------------------------------------------- image par image

local function step(dt: number)
	local r, h = rootAndHumanoid()
	local set = Traversal.get()
	local serverNow = Workspace:GetServerTimeNow()

	-- Effets d'éruption, visibles même sans personnage.
	for _, g in set.geysers do
		local on = Traversal.eruption(g, serverNow)
		setEruptionFx(g.inst, on)
	end

	if not r or not h then
		if ride then
			ride = nil
			rideEndedAt = os.clock()
		end
		return
	end
	if ride then
		updateRide(dt, r)
		return
	end
	local pos = r.Position

	-- Tremplins : une fois par entrée dans la zone.
	local onPad: Instance? = nil
	for _, pad in set.pads do
		if Traversal.inZone(pos, pad.top, pad.radius, 0, 0) then
			onPad = pad.inst
			if usedPad ~= pad.inst and mc then
				usedPad = pad.inst
				mc.externalLaunch(pad.height, pad.forward)
			end
			break
		end
	end
	if not onPad then
		usedPad = nil
	end

	-- Geysers : une fois par éruption.
	for _, g in set.geysers do
		local on, index = Traversal.eruption(g, serverNow)
		if on and usedEruption[g.inst] ~= index and Traversal.inZone(pos, g.top, g.radius, 0, 0) and mc then
			usedEruption[g.inst] = index
			mc.externalLaunch(g.height, Vector3.zero)
		end
	end

	-- Tyroliennes : s'accrocher près de Start.
	if os.clock() - rideEndedAt >= T.ZiplineCooldown then
		local hand = pos + Vector3.new(0, T.ZiplineHang, 0)
		for _, z in set.ziplines do
			if (hand - z.a).Magnitude <= T.ZiplineGrab then
				startRide(z, r, h)
				break
			end
		end
	end
end

-- ---------------------------------------------------------------- API

function TraversalController.isRiding(): boolean
	return ride ~= nil
end

-- Lâcher la tyrolienne (action Saut pendant le trajet).
function TraversalController.drop()
	if ride then
		releaseRide()
	end
end

function TraversalController.start(movementController: any)
	mc = movementController
	player.CharacterRemoving:Connect(function()
		ride = nil
		rideEndedAt = os.clock()
		rideMover, rideAttachment = nil, nil -- détruits avec le personnage
	end)
	RunService.PreSimulation:Connect(step)
end

return TraversalController
