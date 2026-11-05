--!strict
-- BatController: place this Script directly inside the imported Enemy_Bat Model.
-- Recreates the preview (chunky voxels, project style): flapping flight (2-segment wings,
-- bobbing body, dangling feet) + sonic screech attack (rear back → lunge + wing slam →
-- 3 growing sonic rings travelling forward) with VFX + damage.
-- Colours come from the hex suffix of each MeshPart name (e.g. "body_fur_purple_6A4C9C").
-- Export from the preview is always in REST pose (joints at 0, wings straight out).
--
-- Model attributes:
--   Flying (bool, true) · AutoAttack (bool, true) · AttackEvery (number, 2.4)
--   Damage (number, 10) · HitRadius (number, 3 studs) · Height (number, 4 studs)
-- Trigger an attack from another script:  bat:SetAttribute("Attack", os.clock())

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local bat = script.Parent :: Model
for k, v in { Flying = true, AutoAttack = true, AttackEvery = 2.4, Damage = 10, HitRadius = 3, Height = 4 } do
	if bat:GetAttribute(k) == nil then bat:SetAttribute(k, v) end
end

local C = {
	WAVE = { Color3.fromHex("C08CFF"), Color3.fromHex("6EF3FF") },
	SPARK = Color3.fromHex("C08CFF"),
	EYE = Color3.fromHex("120C1F"),
	EYE_RAGE = Color3.fromHex("C08CFF"),
}

-- ---------- Collect parts + colours ----------
local PREFIXES = { "body", "wing_L_1", "wing_L_2", "wing_R_1", "wing_R_2", "leg_L", "leg_R" }
local groups: { [string]: { BasePart } } = {}
for _, n in PREFIXES do groups[n] = {} end
local eyes: { BasePart } = {}
local fur: BasePart? = nil
for _, d in bat:GetDescendants() do
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
		if d.Name:match("^body_eye_black") then table.insert(eyes, d) end
		if d.Name:match("^body_fur_") then fur = d end
	end
end
for _, n in PREFIXES do assert(#groups[n] > 0, "BatController: missing parts starting with " .. n .. "_") end
assert(fur, "BatController: missing body_fur_* mesh")

-- ---------- Scale + root frame ----------
-- body_fur bounding box = 11 voxels wide, 13 tall (y 0..13 incl. ears), centred on x/z.
-- Total height feet → ears = 15 voxels.
do
	local U0 = (fur :: BasePart).Size.X / 11
	bat:ScaleTo(bat:GetScale() * ((bat:GetAttribute("Height") :: number) / 15) / U0)
end
local U = (fur :: BasePart).Size.X / 11 -- studs per voxel
local rootCF = (fur :: BasePart).CFrame * CFrame.new(0, -6.5 * U, 0) -- bottom centre of the body

local restOf: { [BasePart]: CFrame } = {}
for _, list in groups do for _, p in list do restOf[p] = rootCF:ToObjectSpace(p.CFrame) end end

-- Joint pivots in root space (voxels), identical to the preview rig
local P = {
	wR1 = CFrame.new(5.5 * U, 6 * U, 0), wL1 = CFrame.new(-5.5 * U, 6 * U, 0),
	wR2 = CFrame.new(10.5 * U, 6 * U, 0), wL2 = CFrame.new(-10.5 * U, 6 * U, 0),
	legL = CFrame.new(-2 * U, 0, 0), legR = CFrame.new(2 * U, 0, 0),
}
local MOUTH = Vector3.new(0, 4 * U, 5 * U)

local function around(piv: CFrame, rx: number, ry: number, rz: number)
	return piv * CFrame.Angles(rx, ry, rz) * piv:Inverse()
end
local function place(name: string, xf: CFrame)
	for _, p in groups[name] do p.CFrame = rootCF * xf * restOf[p] end
end
local function ease(k: number) k = math.clamp(k, 0, 1) return k * k * (3 - 2 * k) end
local function lerp(a: number, b: number, k: number) return a + (b - a) * k end

-- ---------- VFX ----------
local vfx = Instance.new("Folder"); vfx.Name = "BatVFX"; vfx.Parent = workspace

local function cube(size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CastShadow = true, false, false, false
	p.Material = Enum.Material.Neon
	p.Color, p.Size = color, size
	p.Parent = vfx
	return p
end

local function burst(at: Vector3, colors: { Color3 }, count: number, speed: number, life: number, size: number)
	local a = cube(Vector3.one * 0.1, colors[1]); a.Transparency = 1; a.Position = at
	for _, col in colors do
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(col)
		e.LightEmission = 1
		e.Rate = 0
		e.Speed = NumberRange.new(speed * 0.4, speed)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Acceleration = Vector3.new(0, -25 * U, 0)
		e.Lifetime = NumberRange.new(life * 0.6, life)
		e.Size = NumberSequence.new(size, 0)
		e.Transparency = NumberSequence.new(0, 1)
		e.RotSpeed = NumberRange.new(-200, 200)
		e.Parent = a
		e:Emit(math.ceil(count / #colors))
	end
	Debris:AddItem(a, life + 0.2)
	return a
end

local WAVE_LIFE, WAVE_SPEED = 0.6, 40 * U -- studs/s (preview: 3.2 m/s at 0.08 m/voxel)
local hitThisAttack: { [Humanoid]: boolean } = {}

local function damageAt(p: Vector3)
	local params = OverlapParams.new()
	params.FilterDescendantsInstances = { bat, vfx }
	params.FilterType = Enum.RaycastFilterType.Exclude
	for _, part in workspace:GetPartBoundsInRadius(p, bat:GetAttribute("HitRadius") :: number, params) do
		local hum = part.Parent and part.Parent:FindFirstChildOfClass("Humanoid")
		if hum and not hitThisAttack[hum] then hitThisAttack[hum] = true; hum:TakeDamage(bat:GetAttribute("Damage") :: number) end
	end
end

local function fireWave(origin: Vector3, dir: Vector3, isLast: boolean)
	local cubes: { Part } = {}
	for i = 1, 22 do cubes[i] = cube(Vector3.new(0.9, 0.45, 0.45) * U, C.WAVE[i % 2 + 1]) end
	task.spawn(function()
		local t = 0
		while t < WAVE_LIFE do
			t += RunService.Heartbeat:Wait()
			local k = math.min(t / WAVE_LIFE, 1)
			local r = (1.25 + k * 6.9) * U
			local p = origin + dir * (t * WAVE_SPEED)
			local frame = CFrame.lookAt(p, p + dir)
			for i, c in cubes do
				local a = (i / #cubes) * math.pi * 2
				c.CFrame = frame * CFrame.new(math.cos(a) * r, math.sin(a) * r, 0) * CFrame.Angles(0, 0, a)
				c.Size = Vector3.new(0.9 * (1 - k) + 0.2, 0.45 * (1 - k) + 0.12, 0.45) * U
				c.Transparency = k * k
			end
			damageAt(p)
		end
		for _, c in cubes do c:Destroy() end
		if isLast then
			local endP = origin + dir * (WAVE_LIFE * WAVE_SPEED)
			local f = burst(endP, { C.WAVE[1], C.WAVE[2], Color3.new(1, 1, 1) }, 30, 30 * U, 0.8, 0.6 * U)
			local l = Instance.new("PointLight"); l.Color, l.Range, l.Brightness = C.SPARK, 8 * U, 1.5; l.Parent = f
			TweenService:Create(l, TweenInfo.new(0.35), { Brightness = 0 }):Play()
		end
	end)
end

-- ---------- Attack state ----------
local attackT: number? = nil
local fired = 0
local function startAttack() if not attackT then attackT = 0; fired = 0; table.clear(hitThisAttack) end end
bat:GetAttributeChangedSignal("Attack"):Connect(startAttack)

-- ---------- Animation loop ----------
local T, nextAuto = 0, 1.4
RunService.Heartbeat:Connect(function(dt)
	T += dt
	local pitch, dz, dy, w1, w2, blend = 0, 0, 0, 0, 0, 0
	local charge, fireIdx = false, 0
	if attackT then
		local t = attackT + dt
		attackT = t
		if t < 0.4 then
			local k = ease(t / 0.4); pitch = -0.4 * k; dz = -0.15 / 0.08 * U * k; dy = 0.06 / 0.08 * U * k; w1 = 0.75 * k; w2 = 0.35 * k; blend = k
			charge = true
		elseif t < 0.55 then
			local k = ease((t - 0.4) / 0.15)
			pitch = lerp(-0.4, 0.3, k); dz = lerp(-0.15, 0.15, k) / 0.08 * U; dy = lerp(0.06, 0, k) / 0.08 * U
			w1 = lerp(0.75, -0.7, k); w2 = lerp(0.35, -0.5, k); blend = 1
			if fired == 0 and k >= 0.5 then fired = 1; fireIdx = 1 end
		elseif t < 0.85 then
			pitch, dz, w1, w2, blend = 0.3, 0.15 / 0.08 * U, -0.7, -0.5, 1
			if fired == 1 and t > 0.6 then fired = 2; fireIdx = 2 end
			if fired == 2 and t > 0.68 then fired = 3; fireIdx = 3 end
		elseif t < 1.4 then
			local k = ease((t - 0.85) / 0.55)
			pitch = lerp(0.3, 0, k); dz = lerp(0.15, 0, k) / 0.08 * U; w1 = lerp(-0.7, 0, k); w2 = lerp(-0.5, 0, k); blend = 1 - k
		else attackT = nil end
	end

	local flyOn = if bat:GetAttribute("Flying") then 1 else 0
	local f = flyOn * (1 - blend)
	local fl = math.sin(T * 9)
	local flap1 = (0.15 + fl * 0.65) * f + w1
	local flap2 = math.sin(T * 9 - 0.7) * 0.45 * f + w2
	local M = U / 0.08 -- metres in the preview → studs here
	local rig = CFrame.new(math.sin(T * 0.8) * 0.2 * M * flyOn, (-fl * 0.04 * f + math.sin(T * 1.6) * 0.06) * M + dy, dz)
		* CFrame.Angles(0.1 * (1 - blend) + math.sin(T * 9 + 0.5) * 0.04 * f + pitch, math.sin(T * 0.6) * 0.15 * (1 - blend), math.sin(T * 1.1) * 0.06 * (1 - blend))

	local wR1 = rig * around(P.wR1, 0, -0.12 * f, flap1)
	local wL1 = rig * around(P.wL1, 0, 0.12 * f, -flap1)
	place("body", rig)
	place("wing_R_1", wR1)
	place("wing_L_1", wL1)
	place("wing_R_2", wR1 * around(P.wR2, 0, -0.1 * f, flap2))
	place("wing_L_2", wL1 * around(P.wL2, 0, 0.1 * f, -flap2))
	place("leg_L", rig * around(P.legL, 0.3 + math.sin(T * 9 + 1) * 0.15 * f, 0, 0))
	place("leg_R", rig * around(P.legR, 0.3 + math.sin(T * 9 + 1.3) * 0.15 * f, 0, 0))

	local mouth = (rootCF * rig):PointToWorldSpace(MOUTH)
	if charge and math.random() < 0.5 then
		local off = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit * 5 * U
		local s = cube(Vector3.one * 0.5 * U, C.SPARK); s.Position = mouth + off
		TweenService:Create(s, TweenInfo.new(0.17), { Position = mouth, Size = Vector3.one * 0.05, Transparency = 1 }):Play()
		Debris:AddItem(s, 0.2)
	end
	if fireIdx > 0 then
		local dir = (rootCF * rig):VectorToWorldSpace(Vector3.new(0, 0, 1))
		dir = Vector3.new(dir.X, dir.Y * 0.4, dir.Z).Unit
		fireWave(mouth, dir, fireIdx == 3)
	end

	for _, e in eyes do
		e.Color = C.EYE:Lerp(C.EYE_RAGE, blend)
		e.Material = if blend > 0.05 then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end

	if bat:GetAttribute("AutoAttack") and not attackT then
		nextAuto -= dt
		if nextAuto <= 0 then nextAuto = bat:GetAttribute("AttackEvery") :: number; startAttack() end
	end
end)
