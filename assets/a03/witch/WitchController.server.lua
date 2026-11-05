--!strict
-- WitchController: place this Script directly inside the imported Enemy_WitchBroom Model.
-- FLYING · RANGED. Recreates the preview (chunky voxels, project style): hover bob + lazy figure-eight drift with
-- banking, dangling legs, hat lagging behind, sparkle trail from the bristles + POTION THROW attack (overhand lob
-- at the nearest player → glass smashes, toxic splash ring + bubbling puddle that poisons for a moment).
-- Colours come from the hex suffix of each MeshPart name (e.g. "hat_band_gold_E0A82E").
-- Export from the preview is always in REST pose (joints at 0, broom hovering 20 voxels up, potion in hand).
--
-- Model attributes:
--   Walking (bool, true = fly pattern) · AutoAttack (bool, true) · AttackEvery (number, 2.6)
--   Damage (number, 18) · HitRadius (number, 5 studs) · Range (number, 60 studs)
--   PoisonDps (number, 6) · PoisonTime (number, 1.9 s) · Height (number, 6.5 studs)
-- Trigger an attack from another script:  witch:SetAttribute("Attack", os.clock())

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

local witch = script.Parent :: Model
for k, v in { Walking = true, AutoAttack = true, AttackEvery = 2.6, Damage = 18, HitRadius = 5, Range = 60, PoisonDps = 6, PoisonTime = 1.9, Height = 6.5 } do
	if witch:GetAttribute(k) == nil then witch:SetAttribute(k, v) end
end
local function A(n: string): number return witch:GetAttribute(n) :: number end

local C = {
	MAGIC = Color3.fromHex("B46CFF"),
	TOXIC = { Color3.fromHex("7FE3A8"), Color3.fromHex("9BFF6A"), Color3.fromHex("3FD67A") },
	STAR = Color3.fromHex("FFE14D"),
	GLASS = Color3.fromHex("D8F6FF"),
	EYE = Color3.fromHex("120C1F"),
	EYE_RAGE = Color3.fromHex("B46CFF"),
}

-- ---------- Collect parts + colours ----------
local PREFIXES = { "broom", "leg_L", "leg_R", "torso", "head", "hat", "arm_L", "upperarm_R", "forearm_R", "potion" }
local groups: { [string]: { BasePart } } = {}
for _, n in PREFIXES do groups[n] = {} end
local eyes: { BasePart } = {}
for _, d in witch:GetDescendants() do
	if d:IsA("BasePart") then
		d.Anchored, d.CanCollide = true, false
		local hex = d.Name:match("_(%x%x%x%x%x%x)$")
		if hex then
			d.Color = Color3.fromHex(hex)
			d.Material = if hex == "FFFFFF" or hex == "7FE3A8" then Enum.Material.Neon
				elseif hex == "E0A82E" then Enum.Material.Metal
				elseif hex == "7A4E2C" then Enum.Material.Wood
				else Enum.Material.SmoothPlastic
		end
		for _, n in PREFIXES do
			if d.Name:sub(1, #n + 1) == n .. "_" then table.insert(groups[n], d) break end
		end
		if d.Name:match("^head_eye_black") then table.insert(eyes, d) end
	end
end
for _, n in PREFIXES do assert(#groups[n] > 0, "WitchController: missing parts starting with " .. n .. "_") end

-- ---------- Scale + root frame (broom = 29 voxels long along Z, from bristle tips z=-16 to hook z=12) ----------
local HOV = 20 -- broom hover height (voxels above the ground)
local function broomBounds()
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, p in groups.broom do
		local h = p.Size / 2
		lo = lo:Min(p.Position - h); hi = hi:Max(p.Position + h)
	end
	return lo, hi
end
do
	local lo, hi = broomBounds()
	local len = math.max(hi.X - lo.X, hi.Z - lo.Z)
	witch:ScaleTo(witch:GetScale() * (A("Height") / 28) / (len / 29))
end
local lo, hi = broomBounds()
local U = math.max(hi.X - lo.X, hi.Z - lo.Z) / 29 -- studs per voxel
-- broom bounds centre = (0, 0.5, -2) voxels rig-local → root = ground point under the seat
-- A03 : l'Import 3D tourne le modèle de 180° (face vers -Z, côté droit vers -X). On retourne le repère pour que
-- le rig garde les conventions de l'aperçu (face vers +Z) : sans ça, les attaques partent derrière.
local rootCF = CFrame.new((lo + hi) / 2) * groups.broom[1].CFrame.Rotation * CFrame.Angles(0, math.pi, 0) * CFrame.new(0, (-0.5 - HOV) * U, 2 * U)

local restOf: { [BasePart]: CFrame } = {}
local restT: { [BasePart]: number } = {}
for _, list in groups do for _, p in list do restOf[p] = rootCF:ToObjectSpace(p.CFrame); restT[p] = p.Transparency end end

-- Joint pivots in root space (voxels), identical to the preview rig (seat = (0, HOV, 0))
local P = {
	seat = CFrame.new(0, HOV * U, 0),
	legL = CFrame.new(-2.5 * U, HOV * U, 1.5 * U), legR = CFrame.new(2.5 * U, HOV * U, 1.5 * U),
	neck = CFrame.new(0, (HOV + 7) * U, 1 * U),
	hat = CFrame.new(0, (HOV + 15) * U, 1 * U),
	armL = CFrame.new(-4.5 * U, (HOV + 5.5) * U, 1 * U), armR = CFrame.new(4.5 * U, (HOV + 5.5) * U, 1 * U),
	elbowR = CFrame.new(6.5 * U, (HOV + 4.5) * U, 1 * U),
}
local POTION_C = Vector3.new(9 * U, (HOV + 7.5) * U, 1 * U) -- potion centre, rest root space
local BRISTLES = Vector3.new(0, HOV * U, -16 * U)
local TARGET = Vector3.new(0, 0, 44 * U)                    -- default landing point (no player in range)

local function around(piv: CFrame, rx: number, ry: number, rz: number)
	return piv * CFrame.Angles(rx, ry, rz) * piv:Inverse()
end
local function place(name: string, xf: CFrame)
	for _, p in groups[name] do p.CFrame = rootCF * xf * restOf[p] end
end
local function ease(k: number) k = math.clamp(k, 0, 1) return k * k * (3 - 2 * k) end
local function lerp(a: number, b: number, k: number) return a + (b - a) * k end

-- ---------- VFX ----------
local vfx = Instance.new("Folder"); vfx.Name = "WitchVFX"; vfx.Parent = workspace
local ground = rootCF.Position.Y

local function cube(size: Vector3, color: Color3, neon: boolean?): Part
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CastShadow = true, false, false, false
	p.Material = if neon == false then Enum.Material.SmoothPlastic else Enum.Material.Neon
	p.Color, p.Size = color, size
	p.Parent = vfx
	return p
end
local function burst(at: Vector3, colors: { Color3 }, count: number, speed: number, life: number, size: number, gravity: number, glow: boolean, spread: number?)
	local a = cube(Vector3.one * 0.1, colors[1]); a.Transparency = 1; a.Position = at
	for _, col in colors do
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(col)
		e.LightEmission = if glow then 1 else 0
		e.Rate = 0
		e.Speed = NumberRange.new(speed * 0.4, speed)
		e.SpreadAngle = Vector2.new(spread or 70, spread or 70)
		e.EmissionDirection = Enum.NormalId.Top
		e.Acceleration = Vector3.new(0, -gravity, 0)
		e.Lifetime = NumberRange.new(life * 0.6, life)
		e.Size = NumberSequence.new(size, 0)
		e.Transparency = NumberSequence.new(0, 1)
		e.RotSpeed = NumberRange.new(-200, 200)
		e.Parent = a
		e:Emit(math.ceil(count / #colors))
	end
	Debris:AddItem(a, life + 0.3)
	return a
end

local overlap = OverlapParams.new()
overlap.FilterDescendantsInstances = { witch, vfx }
overlap.FilterType = Enum.RaycastFilterType.Exclude
local function hurt(at: Vector3, radius: number, dmg: number)
	local hit: { [Humanoid]: boolean } = {}
	for _, part in workspace:GetPartBoundsInRadius(at, radius, overlap) do
		local hum = part.Parent and part.Parent:FindFirstChildOfClass("Humanoid")
		if hum and not hit[hum] then hit[hum] = true; hum:TakeDamage(dmg) end
	end
end
local function nearestPlayer(from: Vector3, range: number): BasePart?
	local best, bestD = nil, range
	for _, pl in Players:GetPlayers() do
		local char = pl.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if root and hum and hum.Health > 0 then
			local d = (root.Position - from).Magnitude
			if d < bestD then best, bestD = root, d end
		end
	end
	return best
end

local function setPotionVisible(on: boolean)
	for _, p in groups.potion do p.Transparency = if on then restT[p] else 1 end
end

local function splash(at: Vector3)
	-- flash (short range)
	local f = cube(Vector3.one * 0.1, C.TOXIC[2]); f.Transparency = 1; f.Position = at + Vector3.new(0, 2 * U, 0)
	local l = Instance.new("PointLight"); l.Color, l.Range, l.Brightness = C.TOXIC[2], 22 * U, 2; l.Parent = f
	TweenService:Create(l, TweenInfo.new(0.4), { Brightness = 0 }):Play()
	Debris:AddItem(f, 0.45)
	-- splash, sparkles, glass shards
	burst(at + Vector3.new(0, 0.5 * U, 0), C.TOXIC, 18, 30 * U, 0.7, 0.9 * U, 80 * U, false, 70)
	burst(at + Vector3.new(0, 1.5 * U, 0), { C.MAGIC, Color3.new(1, 1, 1) }, 10, 25 * U, 0.55, 0.7 * U, 40 * U, true, 80)
	burst(at + Vector3.new(0, 0.5 * U, 0), { C.GLASS }, 8, 35 * U, 0.5, 0.5 * U, 80 * U, true, 85)
	-- ground ring
	for i = 1, 32 do
		local a = i / 32 * math.pi * 2
		local c = cube(Vector3.new(1.2 * U, 0.5 * U, 0.5 * U), if i % 2 == 0 then C.TOXIC[2] else C.MAGIC)
		local function ringAt(r: number) return CFrame.new(at + Vector3.new(math.cos(a) * r, 0.4 * U, math.sin(a) * r)) * CFrame.Angles(0, -a, 0) end
		c.CFrame = ringAt(1 * U)
		TweenService:Create(c, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = ringAt(13 * U), Size = Vector3.new(0.2, 0.1, 0.5) * U, Transparency = 1,
		}):Play()
		Debris:AddItem(c, 0.5)
	end
	hurt(at, A("HitRadius"), A("Damage"))
	-- toxic puddle: bubbles + poison ticks
	local life = A("PoisonTime")
	local s = 1.5 * U
	for i = -4, 4 do
		for j = -4, 4 do
			local x, z = i * s, j * s
			if math.sqrt(x * x + z * z) <= (6.4 + math.sin(math.atan2(z, x) * 3) * 0.7) * U then
				local p = cube(Vector3.new(s * 0.95, 0.15 * U, s * 0.95), C.TOXIC[(i + j) % 2 + 1])
				p.CFrame = CFrame.new(at + Vector3.new(x, 0.1 * U, z)); p.Transparency = 0.35
				TweenService:Create(p, TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, life - 0.5), { Transparency = 1 }):Play()
				Debris:AddItem(p, life + 0.05)
			end
		end
	end
	task.spawn(function()
		local t = 0
		while t < life do
			burst(at + Vector3.new((math.random() - 0.5) * 8 * U, 0.3 * U, (math.random() - 0.5) * 8 * U), { C.TOXIC[2], C.MAGIC }, 3, 5 * U, 0.7, 0.5 * U, -3 * U, true, 20)
			hurt(at, 6.4 * U, A("PoisonDps") * 0.5)
			task.wait(0.5); t += 0.5
		end
	end)
end

local function throwPotion(from: Vector3)
	local target = nearestPlayer(from, A("Range"))
	local to = if target then Vector3.new(target.Position.X, ground, target.Position.Z) else rootCF:PointToWorldSpace(TARGET)
	to = Vector3.new(to.X, ground + 0.5 * U, to.Z)
	-- flying potion: glass bottle + cork
	local bottle = cube(Vector3.new(3, 3, 3) * U, C.TOXIC[1]); bottle.CFrame = CFrame.new(from)
	local cork = cube(Vector3.new(1, 1.5, 1) * U, Color3.fromHex("A8865A"), false)
	burst(from, { C.MAGIC, C.TOXIC[2] }, 10, 15 * U, 0.35, 0.5 * U, 0, true, 180)
	task.spawn(function()
		local t = 0
		while t < 0.55 do
			t += RunService.Heartbeat:Wait()
			local k = math.min(1, t / 0.55)
			local pos = from:Lerp(to, k) + Vector3.new(0, math.sin(k * math.pi) * 9 * U, 0)
			local cf = CFrame.new(pos) * CFrame.Angles(k * 12, k * 5, 0)
			bottle.CFrame = cf; cork.CFrame = cf * CFrame.new(0, 2.2 * U, 0)
			local s = cube(Vector3.one * 0.5 * U, if math.random() < 0.5 then C.TOXIC[2] else C.MAGIC); s.Position = pos
			TweenService:Create(s, TweenInfo.new(0.4), { Size = Vector3.one * 0.05, Transparency = 1 }):Play()
			Debris:AddItem(s, 0.42)
		end
		bottle:Destroy(); cork:Destroy()
		splash(to)
	end)
end

-- ---------- Attack state ----------
local attackT: number? = nil
local thrownDone = false
local function startAttack() if not attackT then attackT = 0; thrownDone = false end end
witch:GetAttributeChangedSignal("Attack"):Connect(startAttack)

-- ---------- Animation loop ----------
local T, nextAuto, wS, fxAcc = 0, 1.6, 0, 0
RunService.Heartbeat:Connect(function(dt)
	T += dt
	-- Attack = POTION THROW: wind-up 0.4 s (arm Z +1.3 / X −0.75, leans back, broom noses up, potion glows)
	-- ELBOW cocked back (Y +1.5) → overhand throw 0.14 s: shoulder leads (X → +1.45), elbow snaps open 40 ms later
	-- (Y → −0.2, release at 50 % of the snap = whip) → hold 0.25 s → recover 0.55 s (new potion pops in)
	local blend, aZ, aX, eY, lean, bPitch, hX, glow, pScale = 0, 0, 0, 0, 0, 0, 0, 0, 1
	local releaseNow = false
	if attackT then
		local t = attackT + dt
		attackT = t
		if t < 0.4 then
			local k = ease(t / 0.4)
			blend, aZ, aX, eY, lean, bPitch, hX, glow = k, 1.3 * k, -0.75 * k, 1.5 * k, -0.22 * k, -0.14 * k, -0.15 * k, k
		elseif t < 0.54 then
			local k, k2 = ease((t - 0.4) / 0.14), ease((t - 0.44) / 0.1)
			blend, aZ, aX, eY, lean, bPitch, hX, glow = 1, lerp(1.3, 0.55, k), lerp(-0.75, 1.45, k), lerp(1.5, -0.2, k2), lerp(-0.22, 0.25, k), lerp(-0.14, 0.1, k), lerp(-0.15, 0.12, k), 1 - k
			if not thrownDone and k2 >= 0.5 then thrownDone = true; releaseNow = true end
		elseif t < 0.79 then
			blend, aZ, aX, eY, lean, bPitch, hX = 1, 0.55, 1.45, -0.2, 0.25, 0.1, 0.12
		elseif t < 1.34 then
			local k = ease((t - 0.79) / 0.55)
			blend, aZ, aX, eY, lean, bPitch, hX = 1 - k, lerp(0.55, 0, k), lerp(1.45, 0, k), lerp(-0.2, 0, k), lerp(0.25, 0, k), lerp(0.1, 0, k), lerp(0.12, 0, k)
			pScale = math.clamp((k - 0.35) * 3, 0, 1)
		else attackT = nil end
	end

	-- flight: hover bob, figure-eight drift with banking, dangling legs, hat lagging behind
	wS += ((if witch:GetAttribute("Walking") then 1 else 0) - wS) * math.min(1, dt * 2)
	local w, f = wS, T * 0.9
	local rig = CFrame.new(math.sin(f) * 7 * U * w, math.sin(T * 2.2) * 0.7 * U, math.sin(2 * f) * 2 * U * w)
		* around(P.seat, bPitch + math.sin(T * 2.2 + 0.8) * 0.05 + math.cos(2 * f) * 0.04 * w, math.cos(f) * 0.22 * w, -math.cos(f) * 0.2 * w + math.sin(T * 1.3) * 0.04)
	local upper = rig * around(P.seat, lean + math.sin(T * 2.2 + 1.3) * 0.03, math.sin(T * 0.7) * 0.06 * (1 - blend), math.cos(f) * 0.08 * w)
	local head = upper * around(P.neck, hX + math.sin(T * 2.2 + 1.8) * 0.04, math.sin(T * 0.6) * 0.3 * (1 - blend) - math.cos(f) * 0.15 * w, math.sin(T * 1.7) * 0.05)
	local armR = upper * around(P.armR, aX + math.sin(T * 2.2) * 0.05 * (1 - blend), 0, aZ + math.sin(T * 1.9) * 0.06 * (1 - blend))
	local foreR = armR * around(P.elbowR, 0, eY - 0.35 * (1 - blend) + math.sin(T * 2.2 + 0.4) * 0.06 * (1 - blend), math.sin(T * 1.9 + 0.6) * 0.05 * (1 - blend))

	place("broom", rig)
	place("leg_L", rig * around(P.legL, 0.25 + math.sin(T * 2.6) * 0.18, 0, -0.08))
	place("leg_R", rig * around(P.legR, 0.25 + math.sin(T * 2.6 + 1.7) * 0.18, 0, 0.08))
	place("torso", upper)
	place("head", head)
	place("hat", head * around(P.hat, -lean * 0.6 - bPitch * 0.8 + math.sin(T * 2.2 + 2.4) * 0.07, 0, -math.cos(f) * 0.12 * w + math.sin(T * 2.6) * 0.05))
	place("arm_L", upper * around(P.armL, math.sin(T * 2.2 + 0.5) * 0.03, 0, 0))
	place("upperarm_R", armR)
	place("forearm_R", foreR)
	-- potion follows the hand; scaled about its centre while it pops back in
	local pc = POTION_C
	for _, p in groups.potion do
		local rel = restOf[p]
		local scaled = CFrame.new(pc + (rel.Position - pc) * math.max(pScale, 0.01)) * rel.Rotation
		p.CFrame = rootCF * foreR * scaled
	end
	if attackT and attackT > 0.79 and pScale > 0 and pScale < 0.2 then setPotionVisible(true) end

	local handPos = (rootCF * foreR):PointToWorldSpace(POTION_C)
	if releaseNow then setPotionVisible(false); throwPotion(handPos) end

	-- VFX: sparkle trail from the bristles, bubbles from the glowing potion
	fxAcc += dt
	if fxAcc > 0.06 then
		fxAcc = 0
		burst((rootCF * rig):PointToWorldSpace(BRISTLES), { if math.random() < 0.7 then C.MAGIC else C.STAR }, 1, 2 * U, 0.8, 0.5 * U, -1 * U, true, 180)
		if glow > 0.2 then burst(handPos, { C.TOXIC[2], C.MAGIC }, 2, 6 * U, 0.5, 0.45 * U, -4 * U, true, 25) end
	end

	for _, e in eyes do
		e.Color = C.EYE:Lerp(C.EYE_RAGE, blend)
		e.Material = if blend > 0.05 then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end

	if witch:GetAttribute("AutoAttack") and not attackT then
		nextAuto -= dt
		if nextAuto <= 0 then nextAuto = A("AttackEvery"); startAttack() end
	end
end)
