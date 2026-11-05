--!strict
-- GoblinController: place this Script directly inside the imported Enemy_GoblinGrunt Model.
-- Recreates the preview (chunky voxels, project style): walk cycle + horizontal ladle swipe
-- (left → right as seen from the front) with VFX + damage.
-- Colours come from the hex suffix of each MeshPart name (e.g. "pot_pot_red_D63A2F").
-- Export from the preview is always in REST pose (joints at 0, ladle upright in the right mitten).
--
-- Model attributes:
--   Walking (bool, true) · AutoAttack (bool, true) · AttackEvery (number, 2.4)
--   Damage (number, 15)  · HitRadius (number, 4 studs) · Height (number, 4.5 studs)
-- Trigger an attack from another script:  goblin:SetAttribute("Attack", os.clock())

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local goblin = script.Parent :: Model
for k, v in { Walking = true, AutoAttack = true, AttackEvery = 2.4, Damage = 15, HitRadius = 4, Height = 4.5 } do
	if goblin:GetAttribute(k) == nil then goblin:SetAttribute(k, v) end
end

local C = {
	STAR = Color3.fromHex("FFE14D"),
	ORANGE = Color3.fromHex("FF8A3D"),
	TRAIL = Color3.fromHex("FFF2C0"),
	EYE = Color3.fromHex("120C1F"),
	EYE_RAGE = Color3.fromHex("FF731A"),
}

-- ---------- Collect parts + colours ----------
local PREFIXES = { "leg_L", "leg_R", "torso", "head", "pot", "arm_L", "arm_R", "ladle" }
local groups: { [string]: { BasePart } } = {}
for _, n in PREFIXES do groups[n] = {} end
local eyes: { BasePart } = {}
for _, d in goblin:GetDescendants() do
	if d:IsA("BasePart") then
		d.Anchored, d.CanCollide = true, false
		local hex = d.Name:match("_(%x%x%x%x%x%x)$")
		if hex then
			d.Color = Color3.fromHex(hex)
			d.Material = if hex == "B9C1C9" or hex == "4A5058" then Enum.Material.Metal
				elseif hex == "FFFFFF" then Enum.Material.Neon
				else Enum.Material.SmoothPlastic
		end
		for _, n in PREFIXES do
			if d.Name:sub(1, #n + 1) == n .. "_" then table.insert(groups[n], d) break end
		end
		if d.Name:match("^head_eye_black") then table.insert(eyes, d) end
	end
end
for _, n in PREFIXES do assert(#groups[n] > 0, "GoblinController: missing parts starting with " .. n .. "_") end

-- ---------- Scale + root frame (legs: 3 voxels tall, feet at y=0) ----------
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
	goblin:ScaleTo(goblin:GetScale() * ((goblin:GetAttribute("Height") :: number) / 20.85) / ((hi.Y - lo.Y) / 3))
end
local lo, hi = legBounds()
local U = (hi.Y - lo.Y) / 3 -- studs per voxel
local rootCF = CFrame.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2) * groups.torso[1].CFrame.Rotation * CFrame.new(0, 0, -0.5 * U)

local restOf: { [BasePart]: CFrame } = {}
for _, list in groups do for _, p in list do restOf[p] = rootCF:ToObjectSpace(p.CFrame) end end

-- Joint pivots in root space (voxels), identical to the preview rig
local P = {
	hip = CFrame.new(0, 3 * U, 0),
	legL = CFrame.new(-2 * U, 3 * U, 0), legR = CFrame.new(2 * U, 3 * U, 0),
	neck = CFrame.new(0, 8 * U, 0),
	armL = CFrame.new(-4.5 * U, 6.5 * U, 0), armR = CFrame.new(4.5 * U, 6.5 * U, 0),
}
local BOWL = Vector3.new(8 * U, 16.5 * U, 1 * U) -- ladle bowl centre, rest root space

local function around(piv: CFrame, rx: number, ry: number, rz: number)
	return piv * CFrame.Angles(rx, ry, rz) * piv:Inverse()
end
local function place(name: string, xf: CFrame)
	for _, p in groups[name] do p.CFrame = rootCF * xf * restOf[p] end
end
local function ease(k: number) k = math.clamp(k, 0, 1) return k * k * (3 - 2 * k) end
local function lerp(a: number, b: number, k: number) return a + (b - a) * k end

-- ---------- VFX ----------
local vfx = Instance.new("Folder"); vfx.Name = "GoblinVFX"; vfx.Parent = workspace

local function cube(size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CastShadow = true, false, false, false
	p.Material = Enum.Material.Neon
	p.Color, p.Size = color, size
	p.Parent = vfx
	return p
end

local function burst(at: Vector3, color: Color3, count: number, speed: number, life: number, size: number)
	local a = cube(Vector3.one * 0.1, color); a.Transparency = 1; a.Position = at
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.Rate = 0
	e.Speed = NumberRange.new(speed * 0.4, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, -40 * U, 0)
	e.Lifetime = NumberRange.new(life * 0.6, life)
	e.Size = NumberSequence.new(size, 0)
	e.Transparency = NumberSequence.new(0, 1)
	e.RotSpeed = NumberRange.new(-200, 200)
	e.Parent = a
	e:Emit(count)
	Debris:AddItem(a, life + 0.2)
	return a
end

local function impact(at: Vector3)
	-- small flash (kept short-range so it never washes out the goblin)
	local f = burst(at, C.STAR, 16, 30 * U, 0.7, 0.9 * U)
	burst(at, Color3.new(1, 1, 1), 6, 30 * U, 0.6, 0.7 * U)
	burst(at, C.ORANGE, 10, 25 * U, 0.5, 0.8 * U)
	local l = Instance.new("PointLight"); l.Color, l.Range, l.Brightness = C.STAR, 6 * U, 1.5; l.Parent = f
	TweenService:Create(l, TweenInfo.new(0.35), { Brightness = 0 }):Play()
	-- flat shockwave ring at bowl height
	for i = 1, 32 do
		local a = i / 32 * math.pi * 2
		local c = cube(Vector3.new(1.2 * U, 0.6 * U, 0.6 * U), if i % 2 == 0 then C.STAR else C.ORANGE)
		local function ringAt(r: number) return CFrame.new(at + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)) * CFrame.Angles(0, -a, 0) end
		c.CFrame = ringAt(1.2 * U)
		TweenService:Create(c, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = ringAt(12 * U), Size = Vector3.new(0.2, 0.1, 0.6) * U, Transparency = 1,
		}):Play()
		Debris:AddItem(c, 0.5)
	end
	-- damage
	local params = OverlapParams.new()
	params.FilterDescendantsInstances = { goblin, vfx }
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hit: { [Humanoid]: boolean } = {}
	for _, part in workspace:GetPartBoundsInRadius(at, goblin:GetAttribute("HitRadius") :: number, params) do
		local hum = part.Parent and part.Parent:FindFirstChildOfClass("Humanoid")
		if hum and not hit[hum] then hit[hum] = true; hum:TakeDamage(goblin:GetAttribute("Damage") :: number) end
	end
end

-- ---------- Attack state ----------
local attackT: number? = nil
local hitDone = false
local function startAttack() if not attackT then attackT = 0; hitDone = false end end
goblin:GetAttributeChangedSignal("Attack"):Connect(startAttack)

-- ---------- Animation loop ----------
local T, nextAuto = 0, 1.4
RunService.Heartbeat:Connect(function(dt)
	T += dt
	-- Attack = horizontal swipe: ladle tilted forward (arm X +1.5) and the upper body yaws
	-- from -1.0 (wind-up, ladle on the left) to +0.95 (follow-through, ladle on the right).
	local idle = -0.15 + math.sin(T * 3.5) * 0.05
	local ax, yaw, lean, blend = idle, 0, 0, 0
	local trail, hitNow = false, false
	if attackT then
		local t = attackT + dt
		attackT = t
		if t < 0.35 then local k = ease(t / 0.35); ax = lerp(idle, 1.5, k); yaw = -1.0 * k; lean = -0.06 * k; blend = k
		elseif t < 0.5 then
			local k = ease((t - 0.35) / 0.15); ax = 1.5; yaw = lerp(-1.0, 0.95, k); lean = lerp(-0.06, 0.12, k); blend = 1
			trail = true
			if not hitDone and k >= 0.5 then hitDone = true; hitNow = true end
		elseif t < 0.75 then ax, yaw, lean, blend = 1.5, 0.95, 0.12, 1
		elseif t < 1.3 then
			local k = ease((t - 0.75) / 0.55); ax = lerp(1.5, idle, k); yaw = lerp(0.95, 0, k); lean = lerp(0.12, 0, k); blend = 1 - k
		else attackT = nil end
	end

	local w = (if goblin:GetAttribute("Walking") then 1 else 0) * (1 - blend)
	local ph = T * 7
	local rig = CFrame.new(0, math.abs(math.sin(ph)) * 0.5 * U * w, 0)
	local upper = rig * around(P.hip, 0.08 + lean + math.sin(T * 2.2) * 0.015, math.sin(ph) * 0.08 * w + yaw, 0)
	local head = upper * around(P.neck, -lean * 0.4, -yaw * 0.35, math.sin(T * 3.5) * 0.05)
	local armR = upper * around(P.armR, ax, 0, math.sin(T * 2.6) * 0.06 * (1 - blend))

	place("leg_L", rig * around(P.legL, math.sin(ph) * 0.55 * w, 0, 0))
	place("leg_R", rig * around(P.legR, -math.sin(ph) * 0.55 * w, 0, 0))
	place("torso", upper)
	place("head", head)
	place("pot", head)
	place("arm_L", upper * around(P.armL, -math.sin(ph) * 0.5 * w, 0, -math.sin(T * 2.6) * 0.12 - blend * 0.3))
	place("arm_R", armR)
	place("ladle", armR)

	local bowl = (rootCF * armR):PointToWorldSpace(BOWL)
	if trail then
		for i = 1, 2 do
			local s = cube(Vector3.one * U, if i == 1 then C.TRAIL else C.STAR)
			s.Position = bowl + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * U
			TweenService:Create(s, TweenInfo.new(0.3), { Size = Vector3.one * 0.1, Transparency = 1 }):Play()
			Debris:AddItem(s, 0.32)
		end
	end
	if hitNow then impact(bowl) end

	for _, e in eyes do
		e.Color = C.EYE:Lerp(C.EYE_RAGE, blend)
		e.Material = if blend > 0.05 then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end

	if goblin:GetAttribute("AutoAttack") and not attackT then
		nextAuto -= dt
		if nextAuto <= 0 then nextAuto = goblin:GetAttribute("AttackEvery") :: number; startAttack() end
	end
end)
