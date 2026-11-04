--!strict
-- PlayerAnimator (A06, animations du joueur) : poses procédurales posées par-dessus l'Animator,
-- pour tous les personnages visibles (le sien et ceux des autres joueurs). Pas d'asset à publier.
-- Démarré par MovementController (pas dans l'ordre de boot). Design : dossier 50, section 4.5.
--
--   Glissade      buste penché en arrière, bassin abaissé, jambes vers l'avant (attribut serveur Sliding ;
--                 le joueur local lit MovementController.isSliding() pour ne pas attendre le serveur)
--   Charge        Barbarian (attribut SlideCharge) : penché en avant, épaule devant
--   Atterrissage  accroupi bref après un atterrissage lourd (attribut serveur HeavyLandAt, ou appel local)
--
-- Les poses multiplient le Transform des articulations (Motor6D ou AnimationConstraint) en PreSimulation,
-- après l'Animator : elles ne s'accumulent pas et disparaissent seules si ce module s'arrête. Rig R15 seulement.
-- API : PlayerAnimator.start() · PlayerAnimator.heavyLand(player, strength 0..1)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PlayerAnimator = {}

local localPlayer = Players.LocalPlayer

-- Réglages des poses (visuels, propres à ce module).
local POSE = {
	SlideLean = math.rad(62), -- buste vers l'arrière
	SlideDrop = 1.35, -- studs : bassin abaissé
	SlideWaist = math.rad(-22), -- haut du corps qui se redresse pour regarder devant
	SlideNeck = math.rad(-14),
	SlideArm = math.rad(-35), -- bras un peu écartés vers l'arrière (équilibre)
	ChargeLean = math.rad(-24), -- Barbarian : vers l'avant
	ChargeDrop = 0.55,
	ChargeWaist = math.rad(-12),
	LandDrop = 0.9, -- accroupi d'atterrissage lourd, à force 1
	LandWaist = math.rad(-26),
	LandTime = 0.32, -- s
	BlendIn = 16, -- netteté d'entrée dans la pose
	BlendOut = 10,
}

-- Articulation animée : Motor6D, ou AnimationConstraint sur les avatars à articulations mises à jour.
-- Les deux ont une propriété Transform écrite par l'Animator.
type Joint = any

type Rig = {
	character: Model,
	root: Joint?,
	waist: Joint?,
	neck: Joint?,
	leftShoulder: Joint?,
	rightShoulder: Joint?,
	slide: number, -- 0..1
	charge: number,
	landAt: number,
	landStrength: number,
}

local rigs: { [Player]: Rig } = {}
local movement: any = nil -- MovementController (joueur local)

local function motor(character: Model, partName: string, jointName: string): Joint?
	local part = character:FindFirstChild(partName)
	local m = part and part:FindFirstChild(jointName)
	if m and (m:IsA("Motor6D") or m:IsA("AnimationConstraint")) then
		return m
	end
	return nil
end

local function bind(player: Player, character: Model)
	-- Les articulations arrivent avec l'apparence : on attend le bas du torse.
	local lower = character:WaitForChild("LowerTorso", 10)
	if not lower or player.Character ~= character then
		return
	end
	rigs[player] = {
		character = character,
		root = motor(character, "LowerTorso", "Root"),
		waist = motor(character, "UpperTorso", "Waist"),
		neck = motor(character, "Head", "Neck"),
		leftShoulder = motor(character, "LeftUpperArm", "LeftShoulder"),
		rightShoulder = motor(character, "RightUpperArm", "RightShoulder"),
		slide = 0,
		charge = 0,
		landAt = -math.huge,
		landStrength = 0,
	}
end

local function watch(player: Player)
	player.CharacterAdded:Connect(function(character)
		rigs[player] = nil
		task.spawn(bind, player, character)
	end)
	player.CharacterRemoving:Connect(function()
		rigs[player] = nil
	end)
	player:GetAttributeChangedSignal("HeavyLandAt"):Connect(function()
		if player ~= localPlayer then
			PlayerAnimator.heavyLand(player, 1)
		end
	end)
	if player.Character then
		task.spawn(bind, player, player.Character)
	end
end

local function approach(current: number, target: number, dt: number): number
	local k = if target > current then POSE.BlendIn else POSE.BlendOut
	return current + (target - current) * (1 - math.exp(-k * dt))
end

local function step(dt: number)
	local now = os.clock()
	for player, rig in rigs do
		if not rig.character.Parent or not rig.root then
			continue
		end
		local sliding: boolean
		if player == localPlayer and movement then
			sliding = movement.isSliding()
		else
			sliding = player:GetAttribute("Sliding") == true
		end
		local charging = sliding and player:GetAttribute("SlideCharge") == true
		rig.slide = approach(rig.slide, if sliding and not charging then 1 else 0, dt)
		rig.charge = approach(rig.charge, if charging then 1 else 0, dt)

		local land = 0
		local age = now - rig.landAt
		if age >= 0 and age < POSE.LandTime then
			-- montée rapide, retour amorti
			local t = age / POSE.LandTime
			land = rig.landStrength * (if t < 0.2 then t / 0.2 else 1 - (t - 0.2) / 0.8)
		end

		local s, c = rig.slide, rig.charge
		if s < 0.001 and c < 0.001 and land < 0.001 then
			continue
		end
		local drop = POSE.SlideDrop * s + POSE.ChargeDrop * c + POSE.LandDrop * land
		local lean = POSE.SlideLean * s + POSE.ChargeLean * c
		local root = rig.root
		root.Transform *= CFrame.new(0, -drop, 0) * CFrame.Angles(lean, 0, 0)
		local waist = rig.waist
		if waist then
			waist.Transform *= CFrame.Angles(POSE.SlideWaist * s + POSE.ChargeWaist * c + POSE.LandWaist * land, 0, 0)
		end
		local neck = rig.neck
		if neck then
			neck.Transform *= CFrame.Angles(POSE.SlideNeck * s, 0, 0)
		end
		if s > 0.001 then
			local arm = CFrame.Angles(POSE.SlideArm * s, 0, 0)
			local ls, rs = rig.leftShoulder, rig.rightShoulder
			if ls then
				ls.Transform *= arm * CFrame.Angles(0, 0, math.rad(-18) * s)
			end
			if rs then
				rs.Transform *= arm * CFrame.Angles(0, 0, math.rad(18) * s)
			end
		end
	end
end

-- Accroupi d'atterrissage lourd. Le joueur local l'appelle tout de suite (MovementController) ;
-- les autres le reçoivent par l'attribut serveur HeavyLandAt.
function PlayerAnimator.heavyLand(player: Player, strength: number)
	local rig = rigs[player]
	if rig then
		rig.landAt = os.clock()
		rig.landStrength = math.clamp(strength, 0, 1)
	end
end

function PlayerAnimator.start(movementController: any)
	movement = movementController
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		rigs[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	RunService.PreSimulation:Connect(step)
end

return PlayerAnimator
