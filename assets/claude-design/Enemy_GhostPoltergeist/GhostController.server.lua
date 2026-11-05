--!strict
-- GhostController — place this Script directly inside the imported Ghost Model.
-- Recreates the preview: flight (bob, sway, flapping arms, waving tail) and the
-- charged energy-orb attack with VFX. Colours are read from the hex suffix of
-- each MeshPart name (e.g. "arm_R_ghost_white_F3F1FF").
--
-- Attributes on the Model (editable in Studio):
--   Flying      (bool, default true)
--   AutoAttack  (bool, default true)
--   AttackEvery (number, default 2.2 seconds)
-- Trigger an attack from another script:  ghost:SetAttribute("Attack", os.clock())

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local ghost = script.Parent :: Model
local FRONT = Vector3.new(0, 0, 1) -- face direction in body space; use -1 if the orb fires backwards

local C = {
	ORB = Color3.fromHex("B26BFF"),
	CYAN = Color3.fromHex("6EF3FF"),
	LILAC = Color3.fromHex("D59BFF"),
	WISP = Color3.fromHex("8F7CFF"),
	EYE_GLOW = Color3.fromHex("B259FF"),
}

for k, v in { Flying = true, AutoAttack = true, AttackEvery = 2.2 } do
	if ghost:GetAttribute(k) == nil then ghost:SetAttribute(k, v) end
end

-- ---------- Collect parts + apply hex colours ----------
local bodyParts: { BasePart } = {}
local eyeParts: { BasePart } = {}
local armR: BasePart?, armL: BasePart?
local tails: { BasePart } = {}

for _, d in ghost:GetDescendants() do
	if d:IsA("BasePart") then
		d.Anchored = true
		d.CanCollide = false
		local hex = d.Name:match("_(%x%x%x%x%x%x)$")
		if hex then
			d.Color = Color3.fromHex(hex)
			d.Material = if hex == "FFFFFF" then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
		if d.Name:match("^body_") then
			table.insert(bodyParts, d)
			if d.Name:match("eye_black") then table.insert(eyeParts, d) end
		elseif d.Name:match("^arm_R") then armR = d
		elseif d.Name:match("^arm_L") then armL = d
		else
			local i = d.Name:match("^tail_(%d)")
			if i then tails[tonumber(i) :: number] = d end
		end
	end
end
assert(#bodyParts > 0 and armR and armL and #tails == 4, "GhostController: expected body_*, arm_R, arm_L, tail_1..4")

-- Main body mesh = the largest body part
local body = bodyParts[1]
for _, p in bodyParts do if p.Size.Magnitude > body.Size.Magnitude then body = p end end
ghost.PrimaryPart = body

local U = body.Size.Y / 13 -- studs per voxel (body is 13 voxels tall)
local baseCF = body.CFrame
local function rest(p: BasePart) return baseCF:ToObjectSpace(p.CFrame) end

-- Rest offsets + pivots in body space
local restOf: { [BasePart]: CFrame } = {}
for _, p in bodyParts do restOf[p] = rest(p) end
restOf[armR :: BasePart] = rest(armR :: BasePart)
restOf[armL :: BasePart] = rest(armL :: BasePart)
for _, t in tails do restOf[t] = rest(t) end

local function shoulder(p: BasePart, side: number) -- inner edge of the arm
	return restOf[p] * CFrame.new(-side * p.Size.X / 2, 0, 0)
end
local pivR, pivL = shoulder(armR :: BasePart, 1), shoulder(armL :: BasePart, -1)
local tailPiv: { CFrame } = {}
for i, t in tails do tailPiv[i] = CFrame.new((restOf[t] * CFrame.new(0, t.Size.Y / 2, 0)).Position) end

local function aroundPivot(piv: CFrame, rot: CFrame) return piv * rot * piv:Inverse() end
local function smooth(k: number) k = math.clamp(k, 0, 1) return k * k * (3 - 2 * k) end

-- ---------- VFX helpers ----------
local vfx = Instance.new("Folder")
vfx.Name = "GhostVFX"
vfx.Parent = workspace

local function neonCube(size: number, color: Color3): Part
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CastShadow = true, false, false, false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = Vector3.one * size
	p.Parent = vfx
	return p
end

local function emitter(parent: Instance, color: Color3, rate: number, speed: number, life: number, size: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.Rate = rate
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Lifetime = NumberRange.new(life * 0.6, life)
	e.Size = NumberSequence.new(size, 0)
	e.Transparency = NumberSequence.new(0, 1)
	e.Parent = parent
	return e
end

-- Tail wisps
local wispAtt = Instance.new("Attachment")
wispAtt.Parent = tails[4]
local wisps = emitter(wispAtt, C.WISP, 16, 2 * U, 0.7, 0.6 * U)
wisps.Acceleration = Vector3.new(0, -1.5 * U, 0)

-- ---------- Attack ----------
local attackT: number? = nil
local attacking = false

local function explode(pos: Vector3, dir: Vector3)
	local flash = neonCube(0.1, C.ORB)
	flash.Transparency = 1
	flash.Position = pos
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = C.ORB, 18 * U, 8
	light.Parent = flash
	TweenService:Create(light, TweenInfo.new(0.5), { Brightness = 0 }):Play()
	local burst = emitter(flash, C.ORB, 0, 35 * U, 0.8, 1.2 * U)
	burst.Acceleration = Vector3.new(0, -30 * U, 0)
	burst:Emit(30)
	local burst2 = emitter(flash, C.CYAN, 0, 30 * U, 0.6, 0.9 * U)
	burst2:Emit(16)

	-- Voxel shockwave ring facing the shot direction
	local ringCF = CFrame.lookAt(pos, pos + dir)
	for i = 1, 28 do
		local a = (i / 28) * math.pi * 2
		local c = neonCube(0.8 * U, if i % 2 == 0 then C.ORB else C.CYAN)
		local function at(r: number) return ringCF * CFrame.new(math.cos(a) * r, math.sin(a) * r, 0) * CFrame.Angles(0, 0, a) end
		c.CFrame = at(1.5 * U)
		TweenService:Create(c, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = at(10.5 * U), Size = Vector3.one * 0.1 * U, Transparency = 1,
		}):Play()
		Debris:AddItem(c, 0.55)
	end
	Debris:AddItem(flash, 1)
end

local function attack()
	if attacking then return end
	attacking = true
	attackT = 0

	local orb = neonCube(2 * U, C.ORB)
	local core = neonCube(1 * U, Color3.new(1, 1, 1))
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = C.ORB, 14 * U, 0
	light.Parent = orb
	local charge = emitter(orb, C.CYAN, 40, 4 * U, 0.25, 0.5 * U)
	local trail = emitter(orb, C.LILAC, 0, 3 * U, 0.45, 0.8 * U)

	-- charge: follow hands, grow
	local t0 = os.clock()
	while os.clock() - t0 < 0.55 do
		local k = (os.clock() - t0) / 0.55
		local hands = body.CFrame * CFrame.new(0, -1.5 * U, 9.5 * U * FRONT.Z)
		orb.CFrame = hands * CFrame.Angles(k * 6, k * 8, 0)
		core.CFrame = hands * CFrame.Angles(0, -k * 10, 0)
		orb.Size = Vector3.one * (0.4 + 1.6 * k) * U
		light.Brightness = 4 * k
		RunService.Heartbeat:Wait()
	end

	-- fire
	charge.Enabled = false
	trail.Rate = 80
	local dir = body.CFrame:VectorToWorldSpace(FRONT)
	dir = Vector3.new(dir.X, 0, dir.Z).Unit
	local pos = orb.Position
	local travelled, speed, range = 0, 42 * U, 23 * U
	while travelled < range do
		local dt = RunService.Heartbeat:Wait()
		travelled += speed * dt
		local p = pos + dir * travelled + Vector3.new(0, math.sin(travelled / U * 0.6) * 0.04 * U, 0)
		orb.CFrame = CFrame.new(p) * CFrame.Angles(os.clock() * 3, os.clock() * 4, 0)
		core.CFrame = CFrame.new(p) * CFrame.Angles(0, -os.clock() * 6, 0)
	end

	explode(orb.Position, dir)
	orb:Destroy()
	core:Destroy()
	task.wait(0.7)
	attacking = false
	attackT = nil
end

ghost:GetAttributeChangedSignal("Attack"):Connect(function() task.spawn(attack) end)

-- ---------- Animation loop (fly + attack pose) ----------
local T, nextAuto = 0, 1.2
RunService.Heartbeat:Connect(function(dt)
	T += dt
	local f = if ghost:GetAttribute("Flying") then 1 else 0
	wisps.Enabled = f == 1

	-- attack pose amount (arms thrust forward, ghost leans back)
	local reach = 0
	if attackT then
		attackT += dt
		reach = if attackT < 0.55 then smooth(attackT / 0.55) else 1 - smooth((attackT - 0.7) / 0.5)
	end

	-- body: bob, side drift, roll, lean, yaw
	local bodyCF = baseCF
		* CFrame.new(math.sin(T * 0.7) * 2.5 * U * f, math.sin(T * 2) * 0.9 * U * f, 0)
		* CFrame.Angles(
			(0.08 + math.sin(T * 2 + 1) * 0.03) * f - 0.12 * reach,
			math.sin(T * 0.5) * 0.12 * f,
			(math.sin(T * 1.3) * 0.06 - math.cos(T * 0.7) * 0.08) * f
		)
	for _, p in bodyParts do p.CFrame = bodyCF * restOf[p] end

	-- arms: flap while flying, swing forward while attacking
	local flap = math.sin(T * 2.6) * 0.18 * f
	local zR, zL = 0.15 + flap + 0.35 * reach, -0.15 - flap - 0.35 * reach
	local a = armR :: BasePart
	a.CFrame = bodyCF * aroundPivot(pivR, CFrame.Angles(0, -1.25 * reach * FRONT.Z, zR)) * restOf[a]
	a = armL :: BasePart
	a.CFrame = bodyCF * aroundPivot(pivL, CFrame.Angles(0, 1.25 * reach * FRONT.Z, zL)) * restOf[a]

	-- tail: chained wave, each segment trails slightly behind
	local chain = CFrame.identity
	for i, t in tails do
		local rx = (0.12 + math.sin(T * 2 - (i - 1) * 0.7) * 0.1) * f * FRONT.Z
		local rz = math.sin(T * 2.6 - (i - 1) * 0.8) * 0.2 * f
		chain = chain * aroundPivot(tailPiv[i], CFrame.Angles(rx, 0, rz))
		t.CFrame = bodyCF * chain * restOf[t]
	end

	-- eyes glow during attack
	for _, e in eyeParts do
		e.Color = Color3.fromHex("120C1F"):Lerp(C.EYE_GLOW, reach)
		e.Material = if reach > 0.05 then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end

	-- auto attack
	if ghost:GetAttribute("AutoAttack") and not attacking then
		nextAuto -= dt
		if nextAuto <= 0 then
			nextAuto = ghost:GetAttribute("AttackEvery") :: number
			task.spawn(attack)
		end
	end
end)
