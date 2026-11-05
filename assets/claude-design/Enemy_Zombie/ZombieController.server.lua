--!strict
-- ZombieController: place this Script directly inside the imported Enemy_Zombie Model.
-- Recreates the preview (ghost-style chunky voxels): limping shamble with arms reaching
-- forward, and a lunging double-claw swipe with toxic VFX + damage.
-- Colours come from the hex suffix of each MeshPart name (e.g. "head_skin_zombie_9CC98A").
-- Export from the preview is always in REST pose (zero joint rotation, arms out to the sides).
--
-- Model attributes:
--   Walking (bool, true) · AutoAttack (bool, true) · AttackEvery (number, 2.4)
--   Damage (number, 12)  · HitRadius (number, 4 studs) · Height (number, 5.4 studs)
-- Trigger an attack from another script:  zombie:SetAttribute("Attack", os.clock())

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local zombie = script.Parent :: Model
for k, v in { Walking = true, AutoAttack = true, AttackEvery = 2.4, Damage = 12, HitRadius = 4, Height = 5.4 } do
	if zombie:GetAttribute(k) == nil then zombie:SetAttribute(k, v) end
end

local C = {
	SLASH = Color3.fromHex("C8FF7A"),
	TOXIC = { Color3.fromHex("9CFF57"), Color3.fromHex("4BD12E"), Color3.fromHex("E6FF9C") },
	CLOUD = Color3.fromHex("4BD12E"),
	RING = { Color3.fromHex("9CFF57"), Color3.fromHex("3FBF2A") },
	EYE = Color3.fromHex("120C1F"),
	EYE_RAGE = Color3.fromHex("59FF26"),
}

-- ---------- Collect parts + colours ----------
local groups: { [string]: { BasePart } } = {}
local PREFIXES = { "leg_L", "leg_R", "torso", "head", "arm_L", "arm_R" }
for _, n in PREFIXES do groups[n] = {} end
local eyes: { BasePart } = {}
for _, d in zombie:GetDescendants() do
	if d:IsA("BasePart") then
		d.Anchored, d.CanCollide = true, false
		local hex = d.Name:match("_(%x%x%x%x%x%x)$")
		if hex then
			d.Color = Color3.fromHex(hex)
			d.Material = if hex == "FFFFFF" then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
		for _, n in PREFIXES do
			if d.Name:sub(1, #n + 1) == n .. "_" then table.insert(groups[n], d) break end
		end
		if d.Name:match("^head_eye_black") then table.insert(eyes, d) end
	end
end
for _, n in PREFIXES do assert(#groups[n] > 0, "ZombieController: missing parts starting with " .. n .. "_") end

-- ---------- Scale + root frame (legs: 4 voxels tall, feet at y=0) ----------
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
	zombie:ScaleTo(zombie:GetScale() * ((zombie:GetAttribute("Height") :: number) / 19) / ((hi.Y - lo.Y) / 4))
end
local lo, hi = legBounds()
local U = (hi.Y - lo.Y) / 4 -- studs per voxel
local rootCF = CFrame.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2) * groups.torso[1].CFrame.Rotation * CFrame.new(0, 0, -0.5 * U)

local restOf: { [BasePart]: CFrame } = {}
for _, list in groups do for _, p in list do restOf[p] = rootCF:ToObjectSpace(p.CFrame) end end

-- Joint pivots in root space (voxel units, same as the preview rig)
local P = {
	hip = CFrame.new(0, 4 * U, 0),
	legL = CFrame.new(-2 * U, 4 * U, 0), legR = CFrame.new(2 * U, 4 * U, 0),
	neck = CFrame.new(0, 10 * U, 0),
	armL = CFrame.new(-4.5 * U, 8.5 * U, 0), armR = CFrame.new(4.5 * U, 8.5 * U, 0),
}
local HAND_R, HAND_L = Vector3.new(9.5 * U, 7 * U, 0), Vector3.new(-9.5 * U, 7 * U, 0)

local function around(piv: CFrame, rx: number, ry: number, rz: number)
	return piv * CFrame.Angles(rx, ry, rz) * piv:Inverse()
end
local function place(name: string, xf: CFrame)
	for _, p in groups[name] do p.CFrame = rootCF * xf * restOf[p] end
end
local function ease(k: number) k = math.clamp(k, 0, 1) return k * k * (3 - 2 * k) end
local function lerp(a: number, b: number, k: number) return a + (b - a) * k end

-- ---------- VFX ----------
local vfx = Instance.new("Folder"); vfx.Name = "ZombieVFX"; vfx.Parent = workspace

local function cube(size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CastShadow = true, false, false, false
	p.Material = Enum.Material.Neon
	p.Color, p.Size = color, size
	p.Parent = vfx
	return p
end

local function emitter(parent: Instance, color: Color3, speed: number, life: number, size: number, gravity: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.Rate = 0
	e.Speed = NumberRange.new(speed * 0.4, speed)
	e.SpreadAngle = Vector2.new(60, 60)
	e.EmissionDirection = Enum.NormalId.Front
	e.Acceleration = Vector3.new(0, -gravity, 0)
	e.Lifetime = NumberRange.new(life * 0.6, life)
	e.Size = NumberSequence.new(size, 0)
	e.Transparency = NumberSequence.new(0, 1)
	e.RotSpeed = NumberRange.new(-180, 180)
	e.Parent = parent
	return e
end

local function impact(at: Vector3, fwd: Vector3)
	local right = Vector3.new(fwd.Z, 0, -fwd.X)
	local look = CFrame.lookAt(at, at + fwd)
	-- three diagonal claw slashes
	for k = -1, 1 do
		local s = cube(Vector3.new(0.5 * U, 6 * U, 0.3 * U), C.SLASH)
		s.CFrame = look * CFrame.new(k * 1.1 * U, k * 0.25 * U, 0) * CFrame.Angles(0, 0, math.rad(45))
		TweenService:Create(s, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.05, 7 * U, 0.05), Transparency = 1,
		}):Play()
		Debris:AddItem(s, 0.35)
	end
	-- toxic burst
	local a = cube(Vector3.one * 0.1, C.SLASH); a.Transparency = 1; a.CFrame = look
	for _, col in C.TOXIC do emitter(a, col, 25 * U, 0.7, 0.7 * U, 35 * U):Emit(10) end
	local l = Instance.new("PointLight"); l.Color, l.Range, l.Brightness = C.SLASH, 8 * U, 1.5; l.Parent = a
	TweenService:Create(l, TweenInfo.new(0.4), { Brightness = 0 }):Play()
	-- toxic ground ring
	local ground = Vector3.new(at.X, rootCF.Position.Y + 0.4 * U, at.Z)
	for i = 1, 28 do
		local ang = i / 28 * math.pi * 2
		local c = cube(Vector3.new(0.8 * U, 0.4 * U, 0.4 * U), C.RING[i % 2 + 1])
		local function ringAt(r: number) return CFrame.new(ground + Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r)) * CFrame.Angles(0, -ang, 0) end
		c.CFrame = ringAt(0.8 * U)
		TweenService:Create(c, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = ringAt(9 * U), Size = Vector3.new(0.1, 0.05, 0.4) * U, Transparency = 1,
		}):Play()
		Debris:AddItem(c, 0.55)
	end
	-- lingering poison cloud
	local cloudAnchor = cube(Vector3.one * 0.1, C.CLOUD); cloudAnchor.Transparency = 1; cloudAnchor.Position = ground
	local cloud = emitter(cloudAnchor, C.CLOUD, 3 * U, 1.0, 1.4 * U, -3 * U)
	cloud.EmissionDirection = Enum.NormalId.Top
	cloud.SpreadAngle = Vector2.new(40, 40)
	cloud.Rate = 25
	task.delay(1.2, function() cloud.Enabled = false end)
	Debris:AddItem(a, 1); Debris:AddItem(cloudAnchor, 2.4)
	-- damage
	local params = OverlapParams.new()
	params.FilterDescendantsInstances = { zombie, vfx }
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hit: { [Humanoid]: boolean } = {}
	for _, part in workspace:GetPartBoundsInRadius(at, zombie:GetAttribute("HitRadius") :: number, params) do
		local hum = part.Parent and part.Parent:FindFirstChildOfClass("Humanoid")
		if hum and not hit[hum] then hit[hum] = true; hum:TakeDamage(zombie:GetAttribute("Damage") :: number) end
	end
	_ = right
end

-- ---------- Attack state ----------
local attackT: number? = nil
local hitDone = false
local function startAttack() if not attackT then attackT = 0; hitDone = false end end
zombie:GetAttributeChangedSignal("Attack"):Connect(startAttack)

-- ---------- Animation loop ----------
local T, nextAuto = 0, 1.4
RunService.Heartbeat:Connect(function(dt)
	T += dt
	local ph = T * 4
	local idleRx = 0.15 + math.sin(ph + 1) * 0.06
	local reach, rx, lean, blend, lunge = 1.35, idleRx, 0, 0, 0
	local trail = false
	if attackT then
		local t = attackT + dt
		attackT = t
		if t < 0.4 then local k = ease(t / 0.4); rx = lerp(idleRx, -1.0, k); reach = lerp(1.35, 1.0, k); lean = -0.1 * k; blend = k
		elseif t < 0.52 then
			local k = ease((t - 0.4) / 0.12); rx = lerp(-1.0, 0.25, k); reach = lerp(1.0, 1.4, k); lean = lerp(-0.1, 0.4, k); lunge = k; blend = 1
			trail = true
		elseif t < 0.8 then rx, reach, lean, lunge, blend = 0.25, 1.4, 0.4, 1, 1
		elseif t < 1.4 then
			local k = ease((t - 0.8) / 0.6); rx = lerp(0.25, idleRx, k); reach = lerp(1.4, 1.35, k); lean = lerp(0.4, 0, k); lunge = 1 - k; blend = 1 - k
		else attackT = nil end
	end

	local w = (if zombie:GetAttribute("Walking") then 1 else 0) * (1 - blend)
	local rig = CFrame.new(0, math.max(0, math.sin(ph)) * 0.5 * U * w, lunge * 2.75 * U)
	local upper = rig * around(P.hip, 0.14 + lean + math.sin(T * 1.8) * 0.02, math.sin(ph * 0.5) * 0.06 * w, math.sin(ph) * 0.09 * w)
	local armR = upper * around(P.armR, rx + math.sin(ph) * 0.05 * w, -reach, 0)
	local armL = upper * around(P.armL, rx - math.sin(ph) * 0.05 * w + 0.08, reach, 0)

	place("leg_L", rig * around(P.legL, math.sin(ph) * 0.45 * w, 0, 0))
	place("leg_R", rig * around(P.legR, -math.sin(ph) * 0.22 * w, 0, 0))
	place("torso", upper)
	place("head", upper * around(P.neck, -lean * 0.5 + math.sin(T * 2.3) * 0.04, 0, 0.16 + math.sin(T * 1.7) * 0.07))
	place("arm_R", armR)
	place("arm_L", armL)

	local hR, hL = (rootCF * armR):PointToWorldSpace(HAND_R), (rootCF * armL):PointToWorldSpace(HAND_L)
	if trail then
		for _, p in { hR, hL } do
			local s = cube(Vector3.one * 0.6 * U, C.SLASH); s.Position = p
			TweenService:Create(s, TweenInfo.new(0.2), { Size = Vector3.one * 0.05, Transparency = 1 }):Play()
			Debris:AddItem(s, 0.22)
		end
	end
	if attackT and attackT >= 0.52 and not hitDone then
		hitDone = true
		local fwd = rootCF:VectorToWorldSpace(Vector3.new(0, 0, 1))
		fwd = Vector3.new(fwd.X, 0, fwd.Z).Unit
		impact((hR + hL) / 2 + fwd * 3.1 * U, fwd)
	end

	for _, e in eyes do
		e.Color = C.EYE:Lerp(C.EYE_RAGE, blend)
		e.Material = if blend > 0.05 then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end

	if zombie:GetAttribute("AutoAttack") and not attackT then
		nextAuto -= dt
		if nextAuto <= 0 then nextAuto = zombie:GetAttribute("AttackEvery") :: number; startAttack() end
	end
end)
