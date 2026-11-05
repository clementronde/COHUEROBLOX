--!strict
-- OgreBossController: place this Script directly inside the imported Enemy_OgreBoss Model.
-- MINI BOSS (biggest enemy). Recreates the preview (chunky voxels, project style): heavy stomping
-- walk with footstep dust + telegraphed overhead GROUND SLAM with the studded wooden club (red danger ring during
-- the 0.6 s wind-up → slam → big shockwave, rocks, dust, cracks, camera-scale damage).
-- Colours come from the hex suffix of each MeshPart name (e.g. "club_wood_brown_7A4E2C").
-- Rig: hip → thigh → shin (KNEES) · shoulder → upper arm → forearm (ELBOWS) → club (wrist / grip).
-- Export from the preview is always in REST pose (all joints at 0: arms down, club pointing forward).
--
-- Model attributes:
--   Walking (bool, true) · AutoAttack (bool, true) · AttackEvery (number, 3)
--   Damage (number, 45)  · HitRadius (number, 10 studs) · Knockback (number, 75) · Height (number, 14.5 studs)
--   RiseOnSpawn (bool, true): undead spawn — the ogre claws its way out of the ground when the script starts
-- Trigger an attack from another script:  ogre:SetAttribute("Attack", os.clock())
-- Trigger the rise from the ground:        ogre:SetAttribute("Rise", os.clock())   (ground must be opaque: Terrain / Baseplate)

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local ogre = script.Parent :: Model
for k, v in { Walking = true, AutoAttack = true, AttackEvery = 3, Damage = 45, HitRadius = 10, Knockback = 75, Height = 14.5, RiseOnSpawn = true } do
	if ogre:GetAttribute(k) == nil then ogre:SetAttribute(k, v) end
end

local C = {
	WARN = { Color3.fromHex("FF3B2E"), Color3.fromHex("FF7A3D") },
	SHOCK = { Color3.fromHex("FFB13D"), Color3.fromHex("FF5A2E") },
	SHOCK2 = { Color3.new(1, 1, 1), Color3.fromHex("FFD27A") },
	ROCK = { Color3.fromHex("6F6A63"), Color3.fromHex("8C867C"), Color3.fromHex("55514B") },
	DUST = { Color3.fromHex("C9A66B"), Color3.fromHex("A8865A"), Color3.fromHex("8A6D47") },
	CRACK = Color3.fromHex("221A12"),
	TRAIL = { Color3.fromHex("FFD27A"), Color3.fromHex("FF8A3D") },
	EYE = Color3.fromHex("120C1F"),
	EYE_RAGE = Color3.fromHex("FF3826"),
	DIRT = { Color3.fromHex("4A3626"), Color3.fromHex("6B4F36"), Color3.fromHex("2E2118") },
	HOLE = { Color3.fromHex("1E140D"), Color3.fromHex("2A1C12") },
	MOTE = Color3.fromHex("9BFF6A"),
}

-- ---------- Collect parts + colours ----------
local PREFIXES = { "thigh_L", "thigh_R", "shin_L", "shin_R", "torso", "head", "upperarm_L", "upperarm_R", "forearm_L", "forearm_R", "club" }
local groups: { [string]: { BasePart } } = {}
for _, n in PREFIXES do groups[n] = {} end
local eyes: { BasePart } = {}
for _, d in ogre:GetDescendants() do
	if d:IsA("BasePart") then
		d.Anchored, d.CanCollide = true, false
		local hex = d.Name:match("_(%x%x%x%x%x%x)$")
		if hex then
			d.Color = Color3.fromHex(hex)
			d.Material = if hex == "A9B1B8" then Enum.Material.Metal
				elseif hex == "FFFFFF" then Enum.Material.Neon
				elseif hex == "7A4E2C" or hex == "5A3820" then Enum.Material.Wood
				else Enum.Material.SmoothPlastic
		end
		for _, n in PREFIXES do
			if d.Name:sub(1, #n + 1) == n .. "_" then table.insert(groups[n], d) break end
		end
		if d.Name:match("^head_eye_black") then table.insert(eyes, d) end
	end
end
for _, n in PREFIXES do assert(#groups[n] > 0, "OgreBossController: missing parts starting with " .. n .. "_") end

-- ---------- Scale + root frame (legs = thigh + shin: 8 voxels tall, feet at y=0; hair tuft top = 34 voxels) ----------
local function legBounds()
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, n in { "thigh_L", "shin_L", "thigh_R", "shin_R" } do
		for _, p in groups[n] do
			local h = p.Size / 2
			lo = lo:Min(p.Position - h); hi = hi:Max(p.Position + h)
		end
	end
	return lo, hi
end
do
	local lo, hi = legBounds()
	ogre:ScaleTo(ogre:GetScale() * ((ogre:GetAttribute("Height") :: number) / 34) / ((hi.Y - lo.Y) / 8))
end
local lo, hi = legBounds()
local U = (hi.Y - lo.Y) / 8 -- studs per voxel
-- A03 : l'Import 3D tourne le modèle de 180° (face vers -Z, côté droit vers -X). On retourne le repère pour que
-- le rig garde les conventions de l'aperçu (face vers +Z) : sans ça, les attaques partent derrière.
local rootCF = CFrame.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2) * groups.torso[1].CFrame.Rotation
	* CFrame.Angles(0, math.pi, 0) * CFrame.new(0, 0, -0.5 * U)

local restOf: { [BasePart]: CFrame } = {}
for _, list in groups do for _, p in list do restOf[p] = rootCF:ToObjectSpace(p.CFrame) end end

-- Joint pivots in root space (voxels), identical to the preview rig
local P = {
	hip = CFrame.new(0, 8 * U, 0),
	hipL = CFrame.new(-4 * U, 8 * U, 0), hipR = CFrame.new(4 * U, 8 * U, 0),
	kneeL = CFrame.new(-4 * U, 4 * U, 0), kneeR = CFrame.new(4 * U, 4 * U, 0),
	neck = CFrame.new(0, 22.3 * U, 1.5 * U),
	shoulderL = CFrame.new(-10 * U, 22.5 * U, 0), shoulderR = CFrame.new(10 * U, 22.5 * U, 0),
	elbowL = CFrame.new(-10 * U, 17 * U, 0), elbowR = CFrame.new(10 * U, 17 * U, 0),
	wrist = CFrame.new(10 * U, 12 * U, 0),
}
local CLUB_HEAD = Vector3.new(12 * U, 12 * U, 16 * U) -- club head centre, rest root space

local function around(piv: CFrame, rx: number, ry: number, rz: number)
	return piv * CFrame.Angles(rx, ry, rz) * piv:Inverse()
end
local function place(name: string, xf: CFrame)
	for _, p in groups[name] do p.CFrame = rootCF * xf * restOf[p] end
end
local function ease(k: number) k = math.clamp(k, 0, 1) return k * k * (3 - 2 * k) end
local function lerp(a: number, b: number, k: number) return a + (b - a) * k end

-- ---------- Pose system (same as the preview) ----------
-- One param vector per frame = keyframed track (idle / attack / rise) + additive walk & breathing layers.
local IX = { D = 1, ux = 2, uy = 3, uz = 4, hx = 5, hy = 6, hz = 7, hipL = 8, kneeL = 9, hipR = 10, kneeR = 11,
	sLx = 12, sLz = 13, eL = 14, sRx = 15, sRz = 16, eR = 17, wR = 18, eye = 19 }
-- idle: soft knees, left elbow relaxed, club resting back over the right shoulder (elbow flexed)
local IDLE = { 0, 0.12, 0, 0, 0, 0, 0, -0.08, 0.14, -0.08, 0.14, 0, -0.1, -0.3, -0.15, 0.08, -1.5, -0.42, 0 }
local function track(list)
	local prev, out = IDLE, {}
	for _, k in list do
		local p = table.clone(if k.reset then IDLE else prev)
		for n, i in IX do if k[n] ~= nil then p[i] = k[n] end end
		prev = p
		table.insert(out, { t = k.t, e = k.e, p = p })
	end
	return out
end
local function sample(tr, t: number)
	local i = 1
	while i < #tr - 1 and t >= tr[i + 1].t do i += 1 end
	local a, b = tr[i], tr[i + 1]
	local k = math.clamp((t - a.t) / (b.t - a.t), 0, 1)
	k = if b.e == "in" then k * k else ease(k)
	local p = table.create(#IDLE, 0)
	for j = 1, #IDLE do p[j] = lerp(a.p[j], b.p[j], k) end
	return p
end
-- ATTACK — overhead GROUND SLAM: wind-up 0.6 s → slam 0.15 s (accelerating, deep squat) → hold 0.45 s → recover 0.7 s
local ATTACK = track({
	{ t = 0 },
	{ t = 0.6, ux = -0.05, uy = 0.25, hx = -0.1, hipL = -0.15, kneeL = 0.3, hipR = -0.15, kneeR = 0.3, sLx = -0.6, sLz = -0.6, eL = -0.9, sRx = -2.7, sRz = 0.15, eR = -1.3, wR = 0.18, eye = 1 },
	{ t = 0.75, e = "in", ux = 0.57, uy = -0.1, hx = -0.2, hipL = -0.6, kneeL = 1.1, hipR = -0.6, kneeR = 1.1, sLx = 0.3, sLz = -0.35, eL = -0.5, sRx = -0.7, sRz = 0.1, eR = -0.15, wR = 0.68 },
	{ t = 1.2 },
	{ t = 1.9, reset = true },
})
local ATK_END = 1.9
-- RISE — undead spawn: both hands burst out → slam the ground in front → push the body out with the arms
-- (elbows load then extend) → legs come out → kneels on one knee (club planted) → looks up → stands → roars → idle
local RISE = track({
	{ t = 0, D = -52, ux = 0.3, hx = 0.35, hz = 0.4, hipL = -0.3, kneeL = 0.6, hipR = -0.3, kneeR = 0.6, sLx = -3.0, sLz = -0.3, eL = -0.2, sRx = -3.0, sRz = 0.3, eR = -0.2, wR = 1.33, eye = 1 },
	{ t = 0.9 },
	{ t = 1.15, D = -26 },
	{ t = 1.45, D = -24, sLz = -0.55, sRz = 0.55, hz = 0.3 },
	{ t = 1.75, D = -20, ux = 0.5, hx = 0.3, sLx = -1.9, sLz = -0.3, eL = -0.3, sRx = -1.9, sRz = 0.3, eR = -0.3, wR = 1.7 },
	{ t = 2.05, D = -15, ux = 0.6, sLx = -1.5, eL = -0.9, sRx = -1.5, eR = -0.9, wR = 1.8 },
	{ t = 2.35, D = -9, ux = 0.7, sLx = -0.9, eL = -0.15, sRx = -0.9, eR = -0.15, wR = 0.35, hz = 0.15 },
	{ t = 2.65, D = -5, ux = 0.55, hipL = -1.2, kneeL = 1.4, hipR = -0.3, kneeR = 1.4, sLx = -0.6, eL = -0.1, sRx = -0.6, eR = -0.1, wR = 0.15 },
	{ t = 3.0, D = 0, ux = 0.35, uz = 0.05, hx = 0.3, hz = 0.15, hipL = -1.4, kneeL = 1.5, hipR = 0, kneeR = 1.5, sLx = -0.5, sLz = -0.15, eL = -0.7, sRx = -0.4, sRz = 0.15, eR = -0.6, wR = 1.05 },
	{ t = 3.5, hx = -0.15, hz = 0, uz = 0 },
	{ t = 3.9, ux = 0.5, hipL = -0.9, kneeL = 1.0, hipR = -0.4, kneeR = 0.9, sLx = -0.3, eL = -0.4, wR = 1.0 },
	{ t = 4.3, D = 0, ux = -0.25, hx = -0.35, hipL = -0.08, kneeL = 0.25, hipR = -0.08, kneeR = 0.25, sLx = -0.5, sLz = -0.9, eL = -1.0, sRx = -2.2, sRz = 0.3, eR = -0.6, wR = -0.3 },
	{ t = 5.0 },
	{ t = 5.7, reset = true },
})
local RISE_END = 5.8

local function poseXf(p, rx: number)
	local function ext(hp: number, kn: number) return 4 * math.cos(hp) + 4 * math.cos(hp + kn) end -- planted feet
	local rig = CFrame.new(rx * U, (math.max(ext(p[8], p[9]), ext(p[10], p[11])) - 8 + p[1]) * U, 0)
	local upper = rig * around(P.hip, p[2], p[3], p[4])
	local thighL, thighR = rig * around(P.hipL, p[8], 0, 0), rig * around(P.hipR, p[10], 0, 0)
	local uaL, uaR = upper * around(P.shoulderL, p[12], 0, p[13]), upper * around(P.shoulderR, p[15], 0, p[16])
	local faR = uaR * around(P.elbowR, p[17], 0, 0)
	return {
		thigh_L = thighL, shin_L = thighL * around(P.kneeL, p[9], 0, 0),
		thigh_R = thighR, shin_R = thighR * around(P.kneeR, p[11], 0, 0),
		torso = upper, head = upper * around(P.neck, p[5], p[6], p[7]),
		upperarm_L = uaL, forearm_L = uaL * around(P.elbowL, p[14], 0, 0),
		upperarm_R = uaR, forearm_R = faR, club = faR * around(P.wrist, p[18], 0, 0),
	}
end
-- natural heavy walk: thigh swing, knee folds on the swinging leg, weight shift over the stance leg,
-- shoulders counter-twist, left arm swings opposite with a lag and bends its elbow going forward, club bobs
local function walkAdd(p, ph: number, w: number)
	local s, c, sa = math.sin(ph), math.cos(ph), math.sin(ph - 0.3)
	p[8] += -0.45 * s * w; p[10] += 0.45 * s * w
	p[9] += math.max(0, c) ^ 1.2 * 0.85 * w; p[11] += math.max(0, -c) ^ 1.2 * 0.85 * w
	p[2] += math.abs(s) * 0.03 * w; p[3] += s * 0.08 * w; p[4] += -c * 0.07 * w
	p[5] += math.sin(2 * ph - 0.8) * 0.04 * w; p[6] += -s * 0.05 * w; p[7] += c * 0.045 * w
	p[12] += sa * 0.4 * w; p[14] += -math.max(0, -sa) * 0.35 * w
	p[15] += -math.sin(ph - 0.5) * 0.1 * w; p[17] += math.sin(2 * ph) * 0.04 * w; p[18] += math.sin(2 * ph - 1) * 0.05 * w
	return c * 0.35 * w
end
-- solve the slam wrist so the club head lands on the ground, and predict the impact point
local HIT_LOCAL
do
	local sp = ATTACK[3].p
	local lo, hi = -0.5, 1.8
	for _ = 1, 30 do
		sp[IX.wR] = (lo + hi) / 2
		if poseXf(sp, 0).club:PointToWorldSpace(CLUB_HEAD).Y > 2.5 * U then lo = sp[IX.wR] else hi = sp[IX.wR] end
	end
	ATTACK[4].p[IX.wR] = sp[IX.wR]
	local hp = poseXf(sp, 0).club:PointToWorldSpace(CLUB_HEAD)
	HIT_LOCAL = Vector3.new(hp.X, 0, hp.Z)
end

-- ---------- VFX ----------
local vfx = Instance.new("Folder"); vfx.Name = "OgreBossVFX"; vfx.Parent = workspace

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

local function groundRing(center: Vector3, n: number, colors: { Color3 }, r0: number, r1: number, dur: number, w: number, h: number)
	for i = 1, n do
		local a = i / n * math.pi * 2
		local c = cube(Vector3.new(w, h, 0.5 * U), colors[i % #colors + 1])
		local function at(r: number) return CFrame.new(center + Vector3.new(math.cos(a) * r, h / 2, math.sin(a) * r)) * CFrame.Angles(0, -a, 0) end
		c.CFrame = at(r0)
		TweenService:Create(c, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = at(r1), Size = Vector3.new(0.15 * U, 0.08 * U, 0.5 * U), Transparency = 1,
		}):Play()
		Debris:AddItem(c, dur + 0.05)
	end
end

-- Telegraph: pulsing red ring on the ground during the wind-up (gives players time to dodge)
local warnParts: { Part } = {}
local function showWarning(center: Vector3)
	for i = 1, 36 do
		local c = cube(Vector3.new(1.25, 0.2, 0.67) * U, C.WARN[i % 2 + 1])
		c.Transparency = 1
		warnParts[i] = c
	end
	local t0 = os.clock()
	task.spawn(function()
		while #warnParts > 0 do
			local k = math.clamp((os.clock() - t0) / 0.6, 0, 1)
			local r = lerp(12.1, 8.75, ease(k)) * U
			local pulse = 0.55 + math.sin(os.clock() * 22) * 0.25
			for i, c in warnParts do
				local a = i / #warnParts * math.pi * 2
				c.CFrame = CFrame.new(center + Vector3.new(math.cos(a) * r, 0.1 * U, math.sin(a) * r)) * CFrame.Angles(0, -a, 0)
				c.Transparency = 1 - pulse * math.min(1, k * 3)
			end
			RunService.Heartbeat:Wait()
		end
	end)
end
local function hideWarning()
	for _, c in warnParts do c:Destroy() end
	table.clear(warnParts)
end

local function impact(at: Vector3)
	hideWarning()
	-- flash at ground level (short range so the ogre stays readable)
	local f = cube(Vector3.one * 0.1, C.SHOCK[1]); f.Transparency = 1; f.Position = at + Vector3.new(0, 0.7 * U, 0)
	local l = Instance.new("PointLight"); l.Color, l.Range, l.Brightness = C.SHOCK[1], 18 * U, 2; l.Parent = f
	TweenService:Create(l, TweenInfo.new(0.45), { Brightness = 0 }):Play()
	Debris:AddItem(f, 0.5)
	-- double shockwave
	groundRing(at, 40, C.SHOCK, 1.7 * U, 24 * U, 0.6, 1.4 * U, 0.67 * U)
	groundRing(at, 30, C.SHOCK2, 1 * U, 15 * U, 0.43, 0.9 * U, 0.5 * U)
	-- debris
	burst(at, C.ROCK, 26, 40 * U, 1.6, 1.3 * U, 75 * U, false, 55)
	burst(at, C.DUST, 30, 22 * U, 1.3, 1.6 * U, 12 * U, false, 85)
	burst(at + Vector3.new(0, 1.6 * U, 0), { C.SHOCK[1], Color3.new(1, 1, 1) }, 18, 30 * U, 0.6, 0.8 * U, 40 * U, true, 60)
	-- cracks
	for i = 1, 14 do
		local a, r = i / 14 * math.pi * 2 + (math.random() - 0.5) * 0.3, (2 + math.random() * 5) * U
		local c = cube(Vector3.new((3 + math.random() * 3) * U, 0.07 * U, (0.5 + math.random() * 0.35) * U), C.CRACK, false)
		c.CFrame = CFrame.new(at + Vector3.new(math.cos(a) * r, 0.05 * U, math.sin(a) * r)) * CFrame.Angles(0, -a, 0)
		TweenService:Create(c, TweenInfo.new(0.8, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 1.0), { Transparency = 1 }):Play()
		Debris:AddItem(c, 1.9)
	end
	-- damage + knockback
	local params = OverlapParams.new()
	params.FilterDescendantsInstances = { ogre, vfx }
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hit: { [Humanoid]: boolean } = {}
	for _, part in workspace:GetPartBoundsInRadius(at, ogre:GetAttribute("HitRadius") :: number, params) do
		local char = part.Parent
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and not hit[hum] then
			hit[hum] = true
			hum:TakeDamage(ogre:GetAttribute("Damage") :: number)
			local root = (char :: Instance):FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local away = root.Position - at
				away = Vector3.new(away.X, 0, away.Z)
				away = if away.Magnitude > 0.01 then away.Unit else Vector3.new(0, 0, 1)
				root.AssemblyLinearVelocity = away * (ogre:GetAttribute("Knockback") :: number) + Vector3.new(0, 30, 0)
			end
		end
	end
end

local function footDust(at: Vector3)
	burst(at, { C.DUST[1], C.DUST[2] }, 6, 8 * U, 0.6, 0.6 * U, 4 * U, false, 85)
end

-- ---------- Attack state ----------
local attackT: number? = nil
local hitDone = false
local hitPoint = Vector3.zero
local riseT: number? = nil
local function startAttack()
	if attackT or riseT then return end
	attackT = 0; hitDone = false
	hitPoint = rootCF:PointToWorldSpace(HIT_LOCAL)
	showWarning(hitPoint)
end
ogre:GetAttributeChangedSignal("Attack"):Connect(startAttack)

-- ---------- Rise from the ground (undead spawn) · VFX ----------
local hole: { Part } = {}
local riseCracks: { Part } = {}
local holeC = rootCF.Position
local glow: PointLight? = nil
local riseEv, moteAcc, dirtAcc = 1, 0, 0
local lastArmL, lastArmR, lastShinR = CFrame.identity, CFrame.identity, CFrame.identity
local function holeR(a: number) return (9.6 + math.sin(a * 3) + math.sin(a * 5 + 1) * 0.6) * U end
local function holePt(rMax: number)
	local a, r = math.random() * math.pi * 2, math.random() * rMax
	return holeC + rootCF:VectorToWorldSpace(Vector3.new(math.cos(a) * r, 0.4 * U, math.sin(a) * r))
end
local function makeHole()
	for _, p in hole do p:Destroy() end
	table.clear(hole)
	holeC = rootCF.Position
	local s = 1.7 * U
	for i = -7, 7 do
		for j = -7, 7 do
			local x, z = i * s, j * s
			if math.sqrt(x * x + z * z) <= holeR(math.atan2(z, x)) then
				local p = cube(Vector3.new(s, 0.17 * U, s), C.HOLE[(i + j) % 2 + 1], false)
				p.CFrame = rootCF * CFrame.new(x, 0.08 * U, z); p.Transparency = 1
				table.insert(hole, p)
			end
		end
	end
	for i = 1, 26 do
		local a, sz = i / 26 * math.pi * 2 + (math.random() - 0.5) * 0.4, (0.8 + math.random() * 1.2) * U
		local r = holeR(a) + (0.4 + math.random() * 1.6) * U
		local p = cube(Vector3.new(sz, sz * 0.8, sz), C.DIRT[i % 3 + 1], false)
		p.CFrame = rootCF * CFrame.new(math.cos(a) * r, sz * 0.4, math.sin(a) * r) * CFrame.Angles(0, math.random() * 3, 0); p.Transparency = 1
		table.insert(hole, p)
	end
	for _, p in hole do TweenService:Create(p, TweenInfo.new(0.7), { Transparency = 0 }):Play() end
	-- cracks radiating from the hole during the rumble
	for i = 1, 14 do
		local a = i / 14 * math.pi * 2 + (math.random() - 0.5) * 0.3
		local function at(L: number) local r = holeR(a) + L / 2 return rootCF * CFrame.new(math.cos(a) * r, 0.05 * U, math.sin(a) * r) * CFrame.Angles(0, -a, 0) end
		local c = cube(Vector3.new(0.8 * U, 0.07 * U, 0.5 * U), C.CRACK, false)
		c.CFrame = at(0.8 * U)
		TweenService:Create(c, TweenInfo.new(0.9), { Size = Vector3.new(6.6 * U, 0.07 * U, 0.5 * U), CFrame = at(6.6 * U) }):Play()
		TweenService:Create(c, TweenInfo.new(0.8, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 2.2), { Transparency = 1 }):Play()
		Debris:AddItem(c, 3.1)
	end
	local g = cube(Vector3.one * 0.1, C.MOTE); g.Transparency = 1; g.Position = holeC + Vector3.new(0, 2.5 * U, 0)
	local l = Instance.new("PointLight"); l.Color, l.Range, l.Brightness = C.MOTE, 25 * U, 0; l.Parent = g
	glow = l
	Debris:AddItem(g, RISE_END + 1)
end
local function burstDirt(power: number, n: number)
	burst(holeC + Vector3.new(0, 0.5 * U, 0), C.DIRT, n, 40 * U * power, 1.4, 1.2 * U, 75 * U, false, 45)
	burst(holeC + Vector3.new(0, 0.5 * U, 0), { C.ROCK[1], C.ROCK[3] }, math.ceil(n / 3), 45 * U * power, 1.4, 1.4 * U, 75 * U, false, 35)
	if glow then glow.Brightness += 1.5 * power end
end
local function handDirt()
	for _, hx in { { lastArmL, -11 }, { lastArmR, 11 } } do
		local p = (rootCF * hx[1]):PointToWorldSpace(Vector3.new(hx[2] * U, 12 * U, 0))
		burst(Vector3.new(p.X, holeC.Y + 0.4 * U, p.Z), C.DIRT, 14, 25 * U, 0.9, 0.8 * U, 75 * U, false, 50)
	end
end
local function kneeDust()
	local p = (rootCF * lastShinR):PointToWorldSpace(Vector3.new(4 * U, 4 * U, 0))
	burst(Vector3.new(p.X, holeC.Y + 0.3 * U, p.Z), { C.DUST[1], C.DUST[2] }, 16, 14 * U, 0.7, 0.8 * U, 8 * U, false, 88)
end
local function roar()
	groundRing(holeC, 40, C.SHOCK, 1.7 * U, 24 * U, 0.6, 1.4 * U, 0.67 * U)
	groundRing(holeC, 30, C.SHOCK2, 1 * U, 15 * U, 0.43, 0.9 * U, 0.5 * U)
	burst(holeC + Vector3.new(0, 0.5 * U, 0), { C.DUST[1], C.DUST[2] }, 24, 25 * U, 0.8, 1.2 * U, 8 * U, false, 88)
end
local RISE_EV = {
	{ 1.15, function() burstDirt(1, 46) end }, { 1.75, handDirt },
	{ 2.05, function() burstDirt(0.4, 12) end }, { 2.35, function() burstDirt(0.6, 18) end },
	{ 2.65, function() burstDirt(0.5, 14) end }, { 3.0, kneeDust },
	{ 3.9, function() burstDirt(0.2, 8) end }, { 4.3, roar },
}
local function startRise()
	if riseT or attackT then return end
	makeHole()
	riseT, riseEv, moteAcc, dirtAcc = 0, 1, 0, 0
end
local function riseFx(t: number, dt: number)
	if t < 1.15 then
		dirtAcc += dt
		if dirtAcc > 0.06 then dirtAcc = 0; burst(holePt(8 * U), C.DIRT, 2, 14 * U, 0.7, 0.6 * U, 75 * U, false, 30) end
		if glow then glow.Brightness = math.max(glow.Brightness * 0.9, 2.5 * math.min(1, t / 0.9)) end
	elseif glow then glow.Brightness = math.max(0, glow.Brightness - dt * 1.5) end
	if t < 3.0 then
		moteAcc += dt
		if moteAcc > 0.08 then moteAcc = 0; burst(holePt(8 * U), { C.MOTE }, 2, 6 * U, 1.3, 0.5 * U, -6 * U, true, 20) end
	end
	while riseEv <= #RISE_EV and t >= RISE_EV[riseEv][1] do RISE_EV[riseEv][2](); riseEv += 1 end
end
local function endRise()
	if glow then TweenService:Create(glow, TweenInfo.new(0.4), { Brightness = 0 }):Play() end
	for _, p in hole do
		TweenService:Create(p, TweenInfo.new(2.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
		Debris:AddItem(p, 2.6)
	end
	table.clear(hole)
end
ogre:GetAttributeChangedSignal("Rise"):Connect(startRise)

-- ---------- Animation loop ----------
local T, nextAuto, prevStep, wS = 0, 1.6, 0, 0
RunService.Heartbeat:Connect(function(dt)
	T += dt
	local p, trem, roarK = nil, 0, 0
	local trail, hitNow = false, false
	if riseT then
		local t = riseT + dt
		riseT = t
		p = sample(RISE, t); riseFx(t, dt)
		trem = if t > 0.9 and t < 2.65 then 1 else 0
		roarK = if t > 4.3 and t < 5.0 then 1 else 0
		if t >= RISE_END then riseT = nil; endRise(); nextAuto = 1.5 end
	elseif attackT then
		local t = attackT + dt
		attackT = t
		p = sample(ATTACK, t)
		trail = t > 0.6 and t < 0.76
		if not hitDone and t >= 0.74 then hitDone = true; hitNow = true end
		if t >= ATK_END then attackT = nil end
	else
		p = table.clone(IDLE)
	end

	wS += ((if ogre:GetAttribute("Walking") and not riseT and not attackT then 1 else 0) - wS) * math.min(1, dt * 4)
	local ph = T * 3.6
	local rx = walkAdd(p, ph, wS)
	local br, jit = math.sin(T * 2), trem * (math.sin(T * 37) + math.sin(T * 23.3)) * 0.5
	p[IX.ux] += br * 0.025; p[IX.hx] += math.sin(T * 2 + 0.6) * 0.03
	p[IX.hz] += math.sin(T * 1.5) * 0.04 + roarK * math.sin(T * 32) * 0.07
	p[IX.sLz] -= br * 0.04; p[IX.sRz] += br * 0.03; p[IX.eL] -= br * 0.04
	p[IX.D] += jit * 0.3; p[IX.uz] += jit * 0.04; p[IX.sLz] += jit * 0.12; p[IX.eL] += jit * 0.15

	local xf = poseXf(p, rx)
	for name, cf in xf do place(name, cf) end
	lastArmL, lastArmR, lastShinR = xf.forearm_L, xf.forearm_R, xf.shin_R

	-- footstep dust when the swinging foot lands
	local step = math.sign(math.cos(ph))
	if wS > 0.5 and step ~= prevStep then
		local left = step < 0
		footDust((rootCF * (if left then xf.shin_L else xf.shin_R)):PointToWorldSpace(Vector3.new((if left then -4 else 4) * U, 0.3 * U, 0.5 * U)))
	end
	prevStep = step

	if trail then
		local hp = (rootCF * xf.club):PointToWorldSpace(CLUB_HEAD)
		for i = 1, 2 do
			local cb = cube(Vector3.one * 1.8 * U, C.TRAIL[i])
			cb.Position = hp + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 1.2 * U
			TweenService:Create(cb, TweenInfo.new(0.25), { Size = Vector3.one * 0.1, Transparency = 1 }):Play()
			Debris:AddItem(cb, 0.27)
		end
	end
	if hitNow then impact(hitPoint) end

	local eb = p[IX.eye]
	for _, e in eyes do
		e.Color = C.EYE:Lerp(C.EYE_RAGE, eb)
		e.Material = if eb > 0.05 then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end

	if ogre:GetAttribute("AutoAttack") and not attackT and not riseT then
		nextAuto -= dt
		if nextAuto <= 0 then nextAuto = ogre:GetAttribute("AttackEvery") :: number; startAttack() end
	end
end)

if ogre:GetAttribute("RiseOnSpawn") then startRise() end
