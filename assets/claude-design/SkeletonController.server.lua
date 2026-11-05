--!strict
-- SkeletonController: place this Script directly inside the imported Enemy_Skeleton Model.
-- Recreates the preview (chunky voxels, project style): stiff walk with chattering jaw +
-- diagonal overhead sword slash (right → left as seen from the front) with VFX + damage.
-- Colours come from the hex suffix of each MeshPart name (e.g. "head_bone_white_EDE6D3").
-- Export from the preview is always in REST pose (joints at 0, sword upright in the right mitten).
--
-- Model attributes:
--   Walking (bool, true) · AutoAttack (bool, true) · AttackEvery (number, 2.4)
--   Damage (number, 18)  · HitRadius (number, 4 studs) · Height (number, 5 studs)
-- Trigger an attack from another script:  skeleton:SetAttribute("Attack", os.clock())

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local skeleton = script.Parent :: Model
for k, v in { Walking = true, AutoAttack = true, AttackEvery = 2.4, Damage = 18, HitRadius = 4, Height = 5 } do
	if skeleton:GetAttribute(k) == nil then skeleton:SetAttribute(k, v) end
end

local C = {
	SOUL = Color3.fromHex("6EF3FF"),
	WHITE = Color3.new(1, 1, 1),
	BONE = Color3.fromHex("EDE6D3"),
	BONE_SHADE = Color3.fromHex("BFB49A"),
	EYE = Color3.fromHex("120C1F"),
	EYE_RAGE = Color3.fromHex("6EF3FF"),
}

-- ---------- Collect parts + colours ----------
local PREFIXES = { "leg_L", "leg_R", "torso", "head", "jaw", "arm_L", "arm_R", "sword" }
local groups: { [string]: { BasePart } } = {}
for _, n in PREFIXES do groups[n] = {} end
local eyes: { BasePart } = {}
for _, d in skeleton:GetDescendants() do
	if d:IsA("BasePart") then
		d.Anchored, d.CanCollide = true, false
		local hex = d.Name:match("_(%x%x%x%x%x%x)$")
		if hex then
			d.Color = Color3.fromHex(hex)
			d.Material = if hex == "B9C1C9" then Enum.Material.Metal
				elseif hex == "FFFFFF" then Enum.Material.Neon
				else Enum.Material.SmoothPlastic
		end
		for _, n in PREFIXES do
			if d.Name:sub(1, #n + 1) == n .. "_" then table.insert(groups[n], d) break end
		end
		if d.Name:match("^head_eye_black") then table.insert(eyes, d) end
	end
end
for _, n in PREFIXES do assert(#groups[n] > 0, "SkeletonController: missing parts starting with " .. n .. "_") end

-- ---------- Scale + root frame (legs: 4 voxels tall, feet at y=0; skull top = 19 voxels) ----------
local function legBounds()
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, n in { "leg_L", "leg_R" } do
		for _, p in groups[n] do
			local h = p.Size / 2
			lo = lo:Min(p.Position - h); hi = hi:Max(p.Position + h)
		end
	end
	return lo, hi
end
do
	local lo, hi = legBounds()
	skeleton:ScaleTo(skeleton:GetScale() * ((skeleton:GetAttribute("Height") :: number) / 19) / ((hi.Y - lo.Y) / 4))
end
local lo, hi = legBounds()
local U = (hi.Y - lo.Y) / 4 -- studs per voxel
local rootCF = CFrame.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2) * groups.torso[1].CFrame.Rotation * CFrame.new(0, 0, -0.5 * U)

local restOf: { [BasePart]: CFrame } = {}
for _, list in groups do for _, p in list do restOf[p] = rootCF:ToObjectSpace(p.CFrame) end end

-- Joint pivots in root space (voxels), identical to the preview rig
local P = {
	hip = CFrame.new(0, 4 * U, 0),
	legL = CFrame.new(-2 * U, 4 * U, 0), legR = CFrame.new(2 * U, 4 * U, 0),
	neck = CFrame.new(0, 10 * U, 0),
	jaw = CFrame.new(0, 12 * U, -2 * U),
	armL = CFrame.new(-4.5 * U, 8.5 * U, 0), armR = CFrame.new(4.5 * U, 8.5 * U, 0),
}
local TIP = Vector3.new(8 * U, 20 * U, 0) -- sword tip, rest root space
local MID = Vector3.new(8 * U, 16 * U, 0) -- mid-blade (impact point)

local function around(piv: CFrame, rx: number, ry: number, rz: number)
	return piv * CFrame.Angles(rx, ry, rz) * piv:Inverse()
end
local function place(name: string, xf: CFrame)
	for _, p in groups[name] do p.CFrame = rootCF * xf * restOf[p] end
end
local function ease(k: number) k = math.clamp(k, 0, 1) return k * k * (3 - 2 * k) end
local function lerp(a: number, b: number, k: number) return a + (b - a) * k end

-- ---------- VFX ----------
local vfx = Instance.new("Folder"); vfx.Name = "SkeletonVFX"; vfx.Parent = workspace

local function cube(size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CastShadow = true, false, false, false
	p.Material = Enum.Material.Neon
	p.Color, p.Size = color, size
	p.Parent = vfx
	return p
end

local function burst(at: Vector3, color: Color3, count: number, speed: number, life: number, size: number, gravity: number, glow: boolean)
	local a = cube(Vector3.one * 0.1, color); a.Transparency = 1; a.Position = at
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(color)
	e.LightEmission = if glow then 1 else 0
	e.Rate = 0
	e.Speed = NumberRange.new(speed * 0.4, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, -gravity, 0)
	e.Lifetime = NumberRange.new(life * 0.6, life)
	e.Size = NumberSequence.new(size, 0)
	e.Transparency = NumberSequence.new(0, 1)
	e.RotSpeed = NumberRange.new(-250, 250)
	e.Parent = a
	e:Emit(count)
	Debris:AddItem(a, life + 0.2)
	return a
end

local function impact(at: Vector3, fwd: Vector3)
	-- bone shards (fall with gravity) + soul sparks
	burst(at, C.BONE, 10, 25 * U, 1.1, 0.6 * U, 80 * U, false)
	burst(at, C.BONE_SHADE, 8, 25 * U, 1.1, 0.5 * U, 80 * U, false)
	local f = burst(at, C.SOUL, 10, 30 * U, 0.5, 0.6 * U, 20 * U, true)
	burst(at, C.WHITE, 6, 30 * U, 0.45, 0.5 * U, 20 * U, true)
	local l = Instance.new("PointLight"); l.Color, l.Range, l.Brightness = C.SOUL, 6 * U, 1.5; l.Parent = f
	TweenService:Create(l, TweenInfo.new(0.35), { Brightness = 0 }):Play()
	-- vertical soul ring facing forward
	local frame = CFrame.lookAt(at, at + fwd)
	for i = 1, 24 do
		local a = i / 24 * math.pi * 2
		local c = cube(Vector3.new(0.95, 0.47, 0.47) * U, if i % 2 == 0 then C.SOUL else C.WHITE)
		local function ringAt(r: number) return frame * CFrame.new(math.cos(a) * r, math.sin(a) * r, 0) * CFrame.Angles(0, 0, a) end
		c.CFrame = ringAt(1.4 * U)
		TweenService:Create(c, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = ringAt(9.5 * U), Size = Vector3.new(0.15, 0.1, 0.47) * U, Transparency = 1,
		}):Play()
		Debris:AddItem(c, 0.5)
	end
	-- damage
	local params = OverlapParams.new()
	params.FilterDescendantsInstances = { skeleton, vfx }
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hit: { [Humanoid]: boolean } = {}
	for _, part in workspace:GetPartBoundsInRadius(at, skeleton:GetAttribute("HitRadius") :: number, params) do
		local hum = part.Parent and part.Parent:FindFirstChildOfClass("Humanoid")
		if hum and not hit[hum] then hit[hum] = true; hum:TakeDamage(skeleton:GetAttribute("Damage") :: number) end
	end
end

-- ---------- Attack state ----------
local attackT: number? = nil
local hitDone = false
local function startAttack() if not attackT then attackT = 0; hitDone = false end end
skeleton:GetAttributeChangedSignal("Attack"):Connect(startAttack)

-- ---------- Animation loop ----------
local T, nextAuto = 0, 1.4
RunService.Heartbeat:Connect(function(dt)
	T += dt
	-- Attack = diagonal overhead slash: sword goes back over the shoulder (arm X -0.8, yaw +0.6),
	-- then down and across (arm X +1.7, yaw -0.7).
	local idle = -0.1 + math.sin(T * 3.2) * 0.04
	local ax, az, yaw, lean, blend = idle, 0, 0, 0, 0
	local trail, hitNow, charge = false, false, false
	if attackT then
		local t = attackT + dt
		attackT = t
		if t < 0.35 then local k = ease(t / 0.35); ax = lerp(idle, -0.8, k); az = 0.25 * k; yaw = 0.6 * k; lean = -0.08 * k; blend = k; charge = true
		elseif t < 0.5 then
			local k = ease((t - 0.35) / 0.15)
			ax = lerp(-0.8, 1.7, k); az = lerp(0.25, 0.1, k); yaw = lerp(0.6, -0.7, k); lean = lerp(-0.08, 0.18, k); blend = 1
			trail = true
			if not hitDone and k >= 0.55 then hitDone = true; hitNow = true end
		elseif t < 0.75 then ax, az, yaw, lean, blend = 1.7, 0.1, -0.7, 0.18, 1
		elseif t < 1.3 then
			local k = ease((t - 0.75) / 0.55); ax = lerp(1.7, idle, k); az = lerp(0.1, 0, k); yaw = lerp(-0.7, 0, k); lean = lerp(0.18, 0, k); blend = 1 - k
		else attackT = nil end
	end

	local walking = skeleton:GetAttribute("Walking") == true
	local w = (if walking then 1 else 0) * (1 - blend)
	local ph = T * 6
	local rig = CFrame.new(0, math.abs(math.sin(ph)) * 0.4 * U * w, 0)
	local upper = rig * around(P.hip, 0.05 + lean + math.sin(T * 2.2) * 0.015, math.sin(ph) * 0.07 * w + yaw, math.sin(ph) * 0.05 * w)
	local head = upper * around(P.neck, -lean * 0.4, -yaw * 0.35, math.sin(T * 2.5) * 0.06)
	local jawOpen = math.max(0, math.sin(T * 16)) * 0.16 * (if walking then 1 else 0.5) * (1 - blend) + blend * 0.35
	local armR = upper * around(P.armR, ax + math.sin(ph) * 0.08 * w, 0, az + math.sin(T * 2.6) * 0.05 * (1 - blend))

	place("leg_L", rig * around(P.legL, math.sin(ph) * 0.5 * w, 0, 0))
	place("leg_R", rig * around(P.legR, -math.sin(ph) * 0.5 * w, 0, 0))
	place("torso", upper)
	place("head", head)
	place("jaw", head * around(P.jaw, jawOpen, 0, 0))
	place("arm_L", upper * around(P.armL, -math.sin(ph) * 0.5 * w, 0, -math.sin(T * 2.6) * 0.1 - blend * 0.3))
	place("arm_R", armR)
	place("sword", armR)

	local armWorld = rootCF * armR
	if trail then
		local tip, mid = armWorld:PointToWorldSpace(TIP), armWorld:PointToWorldSpace(MID)
		for i, p in { tip, tip:Lerp(mid, 0.5) } do
			local c = cube(Vector3.one * (if i == 1 then 0.8 else 0.95) * U, if i == 1 then C.WHITE else C.SOUL)
			c.Position = p
			TweenService:Create(c, TweenInfo.new(0.28), { Size = Vector3.one * 0.05, Transparency = 1 }):Play()
			Debris:AddItem(c, 0.3)
		end
	end
	if charge and math.random() < 0.4 then
		local eye = (rootCF * head):PointToWorldSpace(Vector3.new((if math.random() < 0.5 then -2.5 else 2.5) * U, 15 * U, 4.6 * U))
		local c = cube(Vector3.one * 0.4 * U, C.SOUL); c.Position = eye
		TweenService:Create(c, TweenInfo.new(0.35), { Position = eye + Vector3.new(0, 2.4 * U, 0), Size = Vector3.one * 0.05, Transparency = 1 }):Play()
		Debris:AddItem(c, 0.4)
	end
	if hitNow then
		local fwd = rootCF:VectorToWorldSpace(Vector3.new(0, 0, 1))
		impact(armWorld:PointToWorldSpace(MID), Vector3.new(fwd.X, 0, fwd.Z).Unit)
	end

	for _, e in eyes do
		e.Color = C.EYE:Lerp(C.EYE_RAGE, blend)
		e.Material = if blend > 0.05 then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end

	if skeleton:GetAttribute("AutoAttack") and not attackT then
		nextAuto -= dt
		if nextAuto <= 0 then nextAuto = skeleton:GetAttribute("AttackEvery") :: number; startAttack() end
	end
end)
