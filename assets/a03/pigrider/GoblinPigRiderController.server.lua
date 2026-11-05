--!strict
-- GoblinPigRiderController: place this Script directly inside the imported Enemy_GoblinPigRider Model.
-- Recreates the preview (chunky voxels, project style): pig trot with the goblin bouncing on the saddle +
-- CHARGE attack (pig rears, scrapes its hoof and snorts → lunges forward, goblin thrusts the spear) with VFX,
-- damage and knockback.
-- Colours come from the hex suffix of each MeshPart name (e.g. "pig_body_skin_pig_F4A3A8").
-- Export from the preview is always in REST pose (joints at 0, spear upright in the right mitten).
--
-- Model attributes:
--   Walking (bool, true) · AutoAttack (bool, true) · AttackEvery (number, 2.6)
--   Damage (number, 20)  · HitRadius (number, 5 studs) · Knockback (number, 45) · Height (number, 6 studs)
-- Trigger an attack from another script:  rider:SetAttribute("Attack", os.clock())

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local rider = script.Parent :: Model
for k, v in { Walking = true, AutoAttack = true, AttackEvery = 2.6, Damage = 20, HitRadius = 5, Knockback = 45, Height = 6 } do
	if rider:GetAttribute(k) == nil then rider:SetAttribute(k, v) end
end

local C = {
	STAR = Color3.fromHex("FFE14D"),
	ORANGE = Color3.fromHex("FF8A3D"),
	TRAIL = Color3.fromHex("FFF2C0"),
	DUST = { Color3.fromHex("C9A66B"), Color3.fromHex("A8865A") },
	EYE = Color3.fromHex("120C1F"),
	EYE_RAGE = Color3.fromHex("FF731A"),
}

-- ---------- Collect parts + colours ----------
local PREFIXES = { "pig_body", "pig_head", "pig_tail", "pig_leg_FL", "pig_leg_FR", "pig_leg_BL", "pig_leg_BR",
	"leg_L", "leg_R", "torso", "head", "arm_L", "arm_R", "spear" }
local groups: { [string]: { BasePart } } = {}
for _, n in PREFIXES do groups[n] = {} end
local eyes: { BasePart } = {}
for _, d in rider:GetDescendants() do
	if d:IsA("BasePart") then
		d.Anchored, d.CanCollide = true, false
		local hex = d.Name:match("_(%x%x%x%x%x%x)$")
		if hex then
			d.Color = Color3.fromHex(hex)
			d.Material = if hex == "B9C1C9" then Enum.Material.Metal
				elseif hex == "FFFFFF" then Enum.Material.Neon
				elseif hex == "7A4E2C" then Enum.Material.Wood
				else Enum.Material.SmoothPlastic
		end
		for _, n in PREFIXES do
			if d.Name:sub(1, #n + 1) == n .. "_" then table.insert(groups[n], d) break end
		end
		if d.Name:find("eye_black") then table.insert(eyes, d) end
	end
end
for _, n in PREFIXES do assert(#groups[n] > 0, "GoblinPigRiderController: missing parts starting with " .. n .. "_") end

-- ---------- Scale + root frame (pig legs: 4 voxels tall, hooves at y=0; goblin dome top = 26 voxels) ----------
local LEG_NAMES = { "pig_leg_FL", "pig_leg_FR", "pig_leg_BL", "pig_leg_BR" }
local function legBounds()
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, n in LEG_NAMES do
		for _, p in groups[n] do
			local h = p.Size / 2
			lo = lo:Min(p.Position - h); hi = hi:Max(p.Position + h)
		end
	end
	return lo, hi
end
do
	local lo, hi = legBounds()
	rider:ScaleTo(rider:GetScale() * ((rider:GetAttribute("Height") :: number) / 26) / ((hi.Y - lo.Y) / 4))
end
local lo, hi = legBounds()
local U = (hi.Y - lo.Y) / 4 -- studs per voxel
-- A03 : l'Import 3D tourne le modèle de 180° (face vers -Z, côté droit vers -X). On retourne le repère pour que
-- le rig garde les conventions de l'aperçu (face vers +Z) : sans ça, les attaques partent derrière.
local rootCF = CFrame.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2) * groups.pig_body[1].CFrame.Rotation * CFrame.Angles(0, math.pi, 0)

local restOf: { [BasePart]: CFrame } = {}
for _, list in groups do for _, p in list do restOf[p] = rootCF:ToObjectSpace(p.CFrame) end end

-- Joint pivots in root space (voxels), identical to the preview rig
local P = {
	body = CFrame.new(0, 8 * U, 0),
	pigHead = CFrame.new(0, 9 * U, 8 * U),
	tail = CFrame.new(0, 10 * U, -8.5 * U),
	pig_leg_FL = CFrame.new(-3 * U, 4 * U, 5 * U), pig_leg_FR = CFrame.new(3 * U, 4 * U, 5 * U),
	pig_leg_BL = CFrame.new(-3 * U, 4 * U, -5 * U), pig_leg_BR = CFrame.new(3 * U, 4 * U, -5 * U),
	legL = CFrame.new(-5 * U, 13 * U, 0), legR = CFrame.new(5 * U, 13 * U, 0),
	hip = CFrame.new(0, 13 * U, 0),
	neck = CFrame.new(0, 18 * U, 0),
	armL = CFrame.new(-4.5 * U, 16.5 * U, 0), armR = CFrame.new(4.5 * U, 16.5 * U, 0),
}
local TIP = Vector3.new(8 * U, 34.5 * U, 0)     -- spear point, rest root space
local SNOUT = Vector3.new(0, 8 * U, 17.5 * U)    -- snout front, rest root space

local function around(piv: CFrame, rx: number, ry: number, rz: number)
	return piv * CFrame.Angles(rx, ry, rz) * piv:Inverse()
end
local function place(name: string, xf: CFrame)
	for _, p in groups[name] do p.CFrame = rootCF * xf * restOf[p] end
end
local function ease(k: number) k = math.clamp(k, 0, 1) return k * k * (3 - 2 * k) end
local function lerp(a: number, b: number, k: number) return a + (b - a) * k end

-- ---------- VFX ----------
local vfx = Instance.new("Folder"); vfx.Name = "GoblinPigRiderVFX"; vfx.Parent = workspace

local function cube(size: Vector3, color: Color3, neon: boolean?): Part
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CastShadow = true, false, false, false
	p.Material = if neon == false then Enum.Material.SmoothPlastic else Enum.Material.Neon
	p.Color, p.Size = color, size
	p.Parent = vfx
	return p
end

local function burst(at: Vector3, color: Color3, count: number, speed: number, life: number, size: number, glow: boolean, gravity: number?, spread: number?)
	local a = cube(Vector3.one * 0.1, color); a.Transparency = 1; a.Position = at
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(color)
	e.LightEmission = if glow then 1 else 0
	e.Rate = 0
	e.Speed = NumberRange.new(speed * 0.4, speed)
	e.SpreadAngle = Vector2.new(spread or 180, spread or 180)
	e.EmissionDirection = Enum.NormalId.Top
	e.Acceleration = Vector3.new(0, -(gravity or 40) * U, 0)
	e.Lifetime = NumberRange.new(life * 0.6, life)
	e.Size = NumberSequence.new(size, 0)
	e.Transparency = NumberSequence.new(0, 1)
	e.RotSpeed = NumberRange.new(-200, 200)
	e.Parent = a
	e:Emit(count)
	Debris:AddItem(a, life + 0.2)
	return a
end

local function hoofDust(at: Vector3, n: number)
	burst(Vector3.new(at.X, rootCF.Position.Y + 0.5 * U, at.Z), C.DUST[math.random(1, 2)], n, 12 * U, 0.6, 0.7 * U, false, 10, 60)
end

local function impact(at: Vector3)
	-- stars + shards + short-range flash (never washes out the model)
	local f = burst(at, C.STAR, 16, 30 * U, 0.7, 0.9 * U, true)
	burst(at, Color3.new(1, 1, 1), 6, 30 * U, 0.6, 0.7 * U, true)
	burst(at, C.ORANGE, 10, 25 * U, 0.5, 0.8 * U, true)
	hoofDust(at, 14)
	local l = Instance.new("PointLight"); l.Color, l.Range, l.Brightness = C.STAR, 7 * U, 1.5; l.Parent = f
	TweenService:Create(l, TweenInfo.new(0.35), { Brightness = 0 }):Play()
	-- vertical ring facing forward: the spear pierces through it
	local right, up = rootCF.RightVector, rootCF.UpVector
	for i = 1, 32 do
		local a = i / 32 * math.pi * 2
		local dir = right * math.cos(a) + up * math.sin(a)
		local c = cube(Vector3.new(0.4 * U, 1.2 * U, 0.6 * U), if i % 2 == 0 then C.STAR else C.ORANGE)
		local function ringAt(r: number) return CFrame.lookAt(at + dir * r, at + dir * r + rootCF.LookVector) * CFrame.Angles(0, 0, a) end
		c.CFrame = ringAt(0.8 * U)
		TweenService:Create(c, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = ringAt(8.5 * U), Size = Vector3.new(0.2, 0.15, 0.6) * U, Transparency = 1,
		}):Play()
		Debris:AddItem(c, 0.5)
	end
	-- damage + forward knockback
	local params = OverlapParams.new()
	params.FilterDescendantsInstances = { rider, vfx }
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hit: { [Humanoid]: boolean } = {}
	for _, part in workspace:GetPartBoundsInRadius(at, rider:GetAttribute("HitRadius") :: number, params) do
		local char = part.Parent
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and not hit[hum] then
			hit[hum] = true
			hum:TakeDamage(rider:GetAttribute("Damage") :: number)
			local root = (char :: Instance):FindFirstChild("HumanoidRootPart") :: BasePart?
			-- A03 : l'avant du rig est +Z, donc l'inverse du LookVector de Roblox
			if root then root.AssemblyLinearVelocity = -rootCF.LookVector * (rider:GetAttribute("Knockback") :: number) + Vector3.new(0, 25, 0) end
		end
	end
end

-- ---------- Attack state ----------
local attackT: number? = nil
local hitDone = false
local function startAttack() if not attackT then attackT = 0; hitDone = false end end
rider:GetAttributeChangedSignal("Attack"):Connect(startAttack)

-- ---------- Animation loop ----------
local T, nextAuto, wS, fxAcc = 0, 1.6, 0, 0
RunService.Heartbeat:Connect(function(dt)
	T += dt
	-- Attack = CHARGE: wind-up 0.4 s (pig rears, scrapes FR hoof, snorts; spear couched arm X +1.15)
	-- → dash 0.14 s (14 voxels forward, head down → up) → hold 0.25 s → recover 0.55 s
	local idleArm = -0.1 + math.sin(T * 3) * 0.04
	local blend, dash, bPitch, hDown, lean, twist, armX, paw, lArm = 0, 0, 0, 0, 0, 0, idleArm, 0, 0
	local trail, hitNow = false, false
	if attackT then
		local t = attackT + dt
		attackT = t
		if t < 0.4 then
			local k = ease(t / 0.4)
			blend, dash, bPitch, hDown, lean, twist, armX, paw, lArm = k, -2 * k, -0.12 * k, 0.35 * k, -0.15 * k, -0.35 * k, lerp(idleArm, 1.15, k), k, k
		elseif t < 0.54 then
			local k = ease((t - 0.4) / 0.14)
			blend, dash, bPitch, hDown, lean, twist, armX, lArm = 1, lerp(-2, 14, k), lerp(-0.12, 0.1, k), lerp(0.35, -0.15, k), lerp(-0.15, 0.2, k), lerp(-0.35, 0.15, k), 1.15, 1
			trail = true
			if not hitDone and k >= 0.7 then hitDone = true; hitNow = true end
		elseif t < 0.79 then
			blend, dash, bPitch, hDown, lean, twist, armX, lArm = 1, 14, 0.1, -0.15, 0.2, 0.15, 1.15, 1
		elseif t < 1.34 then
			local k = ease((t - 0.79) / 0.55)
			blend, dash, bPitch, hDown, lean, twist, armX, lArm = 1 - k, lerp(14, 0, k), lerp(0.1, 0, k), lerp(-0.15, 0, k), lerp(0.2, 0, k), lerp(0.15, 0, k), lerp(1.15, idleArm, k), 1 - k
		else attackT = nil end
	end

	wS += ((if rider:GetAttribute("Walking") then 1 else 0) - wS) * math.min(1, dt * 4)
	local w = wS * (1 - blend)
	local ph = T * 8
	local s, br = math.sin(ph), math.sin(T * 2.4)

	-- pig trot: diagonal pairs, little hop, body sway, head bob, curly tail wiggle
	local rig = CFrame.new(0, math.abs(s) * 0.5 * U * w, dash * U)
	local body = rig * around(P.body, bPitch + math.sin(2 * ph) * 0.03 * w + br * 0.01, 0, s * 0.035 * w)
	local legA = s * 0.5 * w
	local fr = -legA + (if paw > 0 then -0.6 * paw + math.sin(T * 28) * 0.45 * paw else 0)
	local legs = {
		pig_leg_FL = body * around(P.pig_leg_FL, legA, 0, 0), pig_leg_BR = body * around(P.pig_leg_BR, legA, 0, 0),
		pig_leg_FR = body * around(P.pig_leg_FR, fr, 0, 0), pig_leg_BL = body * around(P.pig_leg_BL, -legA, 0, 0),
	}
	local pigHead = body * around(P.pigHead, hDown + math.sin(2 * ph + 0.6) * 0.07 * w + br * 0.03, math.sin(T * 0.9) * 0.1 * (1 - blend), 0)

	-- goblin rider: bounces with a lag on the saddle, counter-rolls, holds the reins
	local upper = body * CFrame.new(0, math.abs(math.sin(ph - 0.5)) * 0.6 * w * U, 0)
		* around(P.hip, 0.05 + lean + math.sin(2 * ph - 0.7) * 0.05 * w + br * 0.015, twist + s * 0.06 * w, -s * 0.04 * w)
	local armR = upper * around(P.armR, armX + math.sin(2 * ph - 0.4) * 0.06 * w, 0, math.sin(T * 2.6) * 0.05 * (1 - blend))
	local dangle = math.sin(2 * ph - 0.5) * 0.06 * w

	place("pig_body", body)
	for n, xf in legs do place(n, xf) end
	place("pig_head", pigHead)
	place("pig_tail", body * around(P.tail, math.sin(T * 7) * 0.2, 0, math.sin(T * 14) * 0.5))
	place("leg_L", body * around(P.legL, 0, 0, -dangle))
	place("leg_R", body * around(P.legR, 0, 0, dangle))
	place("torso", upper)
	place("head", upper * around(P.neck, -lean * 0.4, -twist * 0.4, math.sin(T * 3.5) * 0.05))
	place("arm_L", upper * around(P.armL, lerp(-0.7, 0.3, lArm) + math.sin(2 * ph) * 0.08 * w, 0, lerp(-0.15, -0.6, lArm) - br * 0.05))
	place("arm_R", armR)
	place("spear", armR)

	-- VFX: hoof scrape + snorts during the wind-up, hoof dust + speed lines during the dash, spear trail
	fxAcc += dt
	if paw > 0.2 and fxAcc > 0.09 then
		fxAcc = 0
		hoofDust((rootCF * legs.pig_leg_FR):PointToWorldSpace(Vector3.new(3 * U, 0, 5 * U)), 3)
		burst((rootCF * pigHead):PointToWorldSpace(SNOUT), Color3.new(1, 1, 1), 2, 6 * U, 0.45, 0.6 * U, false, -4, 30)
	end
	local tip = (rootCF * armR):PointToWorldSpace(TIP)
	if trail then
		for i = 1, 2 do
			local c = cube(Vector3.one * 0.9 * U, if i == 1 then C.TRAIL else C.STAR)
			c.Position = tip + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 0.8 * U
			TweenService:Create(c, TweenInfo.new(0.28), { Size = Vector3.one * 0.1, Transparency = 1 }):Play()
			Debris:AddItem(c, 0.3)
		end
		for _, n in LEG_NAMES do
			local hp = P[n].Position
			hoofDust((rootCF * legs[n]):PointToWorldSpace(Vector3.new(hp.X, 0, hp.Z)), 1)
		end
		local side = if math.random() < 0.5 then -1 else 1
		local line = cube(Vector3.new(0.3 * U, 0.3 * U, 7 * U), Color3.new(1, 1, 1))
		line.CFrame = rootCF * body * CFrame.new(side * (7 + math.random() * 3) * U, (6 + math.random() * 8) * U, 0)
		TweenService:Create(line, TweenInfo.new(0.22), { CFrame = line.CFrame * CFrame.new(0, 0, -6 * U), Transparency = 1 }):Play()
		Debris:AddItem(line, 0.24)
	end
	if hitNow then impact(tip) end

	for _, e in eyes do
		e.Color = C.EYE:Lerp(C.EYE_RAGE, blend)
		e.Material = if blend > 0.05 then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end

	if rider:GetAttribute("AutoAttack") and not attackT then
		nextAuto -= dt
		if nextAuto <= 0 then nextAuto = rider:GetAttribute("AttackEvery") :: number; startAttack() end
	end
end)
