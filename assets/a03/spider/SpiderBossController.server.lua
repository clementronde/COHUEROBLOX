--!strict
-- SpiderBossController: place this Script directly inside the imported Enemy_SpiderBoss Model.
-- GIGA BOSS (29 studs tall, 55 studs leg span, hairy). Recreates the preview (chunky voxels, project style):
-- 8-leg tetrapod walk (knee on every leg) + 3 attacks, cycled automatically:
--   1) IMPALE  (melee)  rears up, front claws stab the ground → venom shockwave + lingering venom pool (DoT)
--   2) WEB     (ranged) VOLLEY of 6 web balls fanned around the nearest player → 6 sticky nets that slow players
--   3) SPAWN   (summon) abdomen swells, drops egg sacs → they hatch into Spiderlings (8 legs with knees) that chase players
-- Colours come from the hex suffix of each MeshPart name (e.g. "abdomen_mark_red_E0412E").
-- Export from the preview is always in REST pose (all joints at 0 = standing pose).
--
-- Model attributes (defaults below). Trigger from another script:
--   spider:SetAttribute("Impale", os.clock()) · spider:SetAttribute("Web", os.clock()) · spider:SetAttribute("Spawn", os.clock())

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

local spider = script.Parent :: Model
for k, v in {
	Walking = true, AutoAttack = true, AttackEvery = 2.6, Height = 29,
	Damage = 60, HitRadius = 20, Knockback = 90, PoolDps = 12, PoolTime = 2.6,
	WebRange = 110, WebRadius = 10, WebSlow = 4, WebTime = 3, WebDamage = 10,
	SpawnCount = 5, MaxSpiderlings = 10, SpiderlingHP = 40, SpiderlingDamage = 8, SpiderlingSpeed = 16, SpiderlingLife = 25,
} do
	if spider:GetAttribute(k) == nil then spider:SetAttribute(k, v) end
end
local function A(name: string): number return spider:GetAttribute(name) :: number end

local C = {
	WARN = { Color3.fromHex("FF3B2E"), Color3.fromHex("FF7A3D") },
	VENOM = { Color3.fromHex("9BFF6A"), Color3.fromHex("3FD65A") },
	VENOM_LIGHT = Color3.fromHex("D6FFB0"),
	WEB = Color3.fromHex("F4F1FF"),
	EGG = Color3.fromHex("E8E2F0"),
	BABY = Color3.fromHex("553482"), BABY_ABD = Color3.fromHex("432868"), BABY_LEG = Color3.fromHex("8E66C4"), HAIR = Color3.fromHex("6D4C9A"),
	CLAW = Color3.fromHex("1E1430"), FANG = Color3.fromHex("F2EBD9"),
	MARK = Color3.fromHex("E0412E"),
	ROCK = { Color3.fromHex("6F6A63"), Color3.fromHex("8C867C"), Color3.fromHex("55514B") },
	DUST = { Color3.fromHex("C9A66B"), Color3.fromHex("A8865A"), Color3.fromHex("8A6D47") },
	CRACK = Color3.fromHex("221A12"),
	EYE = Color3.fromHex("120C1F"),
	EYE_RAGE = Color3.fromHex("FF2E1F"),
}

-- ---------- Collect parts + colours ----------
local LEG_IDS = { "L1", "L2", "L3", "L4", "R1", "R2", "R3", "R4" }
local PREFIXES = { "head", "abdomen", "fang_L", "fang_R" }
for _, id in LEG_IDS do table.insert(PREFIXES, "femur_" .. id); table.insert(PREFIXES, "tibia_" .. id) end
local groups: { [string]: { BasePart } } = {}
for _, n in PREFIXES do groups[n] = {} end
local eyes: { BasePart } = {}
for _, d in spider:GetDescendants() do
	if d:IsA("BasePart") then
		d.Anchored, d.CanCollide = true, false
		local hex = d.Name:match("_(%x%x%x%x%x%x)$")
		if hex then
			d.Color = Color3.fromHex(hex)
			d.Material = if hex == "FFFFFF" or hex == "E0412E" then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
		for _, n in PREFIXES do
			if d.Name:sub(1, #n + 1) == n .. "_" then table.insert(groups[n], d) break end
		end
		if d.Name:match("^head_eye_black") then table.insert(eyes, d) end
	end
end
for _, n in PREFIXES do assert(#groups[n] > 0, "SpiderBossController: missing parts starting with " .. n .. "_") end

-- ---------- Scale + root frame (abdomen body mesh: 19 voxels tall, bottom at y=12, centre z=-12; total height 31 voxels) ----------
local function abdBounds()
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, p in groups.abdomen do
		if not p.Name:find("abdomen_purple") then continue end -- hair / hourglass stick out: measure the sac only
		local h = p.Size / 2
		lo = lo:Min(p.Position - h); hi = hi:Max(p.Position + h)
	end
	return lo, hi
end
do
	local lo, hi = abdBounds()
	spider:ScaleTo(spider:GetScale() * (A("Height") / 31) / ((hi.Y - lo.Y) / 19))
end
local lo, hi = abdBounds()
local U = (hi.Y - lo.Y) / 19 -- studs per voxel
-- A03 : l'Import 3D tourne le modèle de 180° (face vers -Z, côté droit vers -X). On retourne le repère pour que
-- le rig garde les conventions de l'aperçu (face vers +Z) : sans ça, les attaques partent derrière.
local rootCF = CFrame.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2) * groups.head[1].CFrame.Rotation
	* CFrame.Angles(0, math.pi, 0) * CFrame.new(0, -12 * U, 12 * U)

local restOf: { [BasePart]: CFrame } = {}
local restSize: { [BasePart]: Vector3 } = {}
for _, list in groups do for _, p in list do restOf[p] = rootCF:ToObjectSpace(p.CFrame); restSize[p] = p.Size end end

-- ---------- Rig (voxels, identical to the preview) ----------
local LEG_YAW, LEG_Z = { 0.6, 0.2, -0.25, -0.65 }, { 9, 6, 3, 0 } -- front → back
local HIP_Y, LF, LT, FA = 17, 13.5, 29.5, 0.8
local TB = -(math.asin((HIP_Y + LF * math.sin(FA) - 0.3) / LT) + FA)
local P = {
	body = CFrame.new(0, 18 * U, 0),
	waist = CFrame.new(0, 19 * U, -1 * U),
	fangL = CFrame.new(-2.5 * U, 15.5 * U, 12.5 * U), fangR = CFrame.new(2.5 * U, 15.5 * U, 12.5 * U),
}
local FANG_TIP = { L = Vector3.new(-1.5 * U, 10.5 * U, 12.5 * U), R = Vector3.new(1.5 * U, 10.5 * U, 12.5 * U) }
local MOUTH = Vector3.new(0, 14 * U, 13 * U)
local SPINNERET = Vector3.new(0, 19 * U, -24 * U)
local ABD_CENTRE = Vector3.new(0, 21 * U, -12 * U)
type Leg = { id: string, side: number, i: number, fwd: number, grp: number, hip: CFrame, knee: CFrame, tip: Vector3 }
local legs: { Leg } = {}
for _, id in LEG_IDS do
	local side = if id:sub(1, 1) == "L" then -1 else 1
	local i = tonumber(id:sub(2, 2)) :: number
	local yaw = if side > 0 then -LEG_YAW[i] else math.pi + LEG_YAW[i]
	local R = CFrame.Angles(0, yaw, 0)
	local hipPos = Vector3.new(6.5 * side, HIP_Y, LEG_Z[i]) * U
	local kneePos = hipPos + R:VectorToWorldSpace(Vector3.new(LF * math.cos(FA), LF * math.sin(FA), 0) * U)
	local tipPos = kneePos + R:VectorToWorldSpace(Vector3.new(LT * math.cos(FA + TB), LT * math.sin(FA + TB), 0) * U)
	table.insert(legs, {
		id = id, side = side, i = i, fwd = if side < 0 then 1 else -1,
		grp = if ((i - 1) % 2 == 0) == (side < 0) then 0 else 1, -- tetrapod groups: L1 R2 L3 R4 / R1 L2 R3 L4
		hip = CFrame.new(hipPos) * R, knee = CFrame.new(kneePos) * R, tip = tipPos,
	})
end

local function around(piv: CFrame, rx: number, ry: number, rz: number)
	return piv * CFrame.Angles(rx, ry, rz) * piv:Inverse()
end
local function place(name: string, xf: CFrame)
	for _, p in groups[name] do p.CFrame = rootCF * xf * restOf[p] end
end
-- abdomen swell: scale parts about the waist pivot
local function placeScaled(name: string, xf: CFrame, piv: CFrame, s: number)
	for _, p in groups[name] do
		local rel = piv:Inverse() * restOf[p]
		p.Size = restSize[p] * s
		p.CFrame = rootCF * xf * piv * (CFrame.new(rel.Position * s) * rel.Rotation)
	end
end
local function ease(k: number) k = math.clamp(k, 0, 1) return k * k * (3 - 2 * k) end
local function lerp(a: number, b: number, k: number) return a + (b - a) * k end

-- ---------- Pose: keyframed attack channels + additive walk / idle layers ----------
local CH = { "D", "bp", "by", "abx", "abs", "f1l", "f1k", "f1s", "f2l", "f2k", "f34l", "f34k", "fang", "eye", "glow" }
local REST = {}
for _, n in CH do REST[n] = 0 end
local function track(list)
	local prev, out = REST, {}
	for _, k in list do
		local p = table.clone(if k.reset then REST else prev)
		for _, n in CH do if k[n] ~= nil then p[n] = k[n] end end
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
	local o = {}
	for _, n in CH do o[n] = lerp(a.p[n], b.p[n], k) end
	return o
end
-- web volley: one head-snap per shot while the body sweeps left → right across the fan
local WEB_SHOTS = { 0.68, 0.8, 0.92, 1.04, 1.16, 1.28 }
local WEB_FAN = { { -0.62, 46 }, { -0.36, 60 }, { -0.12, 50 }, { 0.12, 64 }, { 0.36, 48 }, { 0.62, 58 } } -- angle, distance (voxels)
local WEB_KEYS = { { t = 0 }, { t = 0.55, D = -3, bp = -0.28, by = -0.5, abx = 0.18, f1l = 0.55, f1k = -0.35, f1s = -0.25, f2l = 0.15, fang = 0.75, eye = 1 } }
for i, s in WEB_SHOTS do
	local by = -0.5 + (i - 0.5) / 6
	table.insert(WEB_KEYS, { t = s - 0.05, bp = -0.18, by = by, fang = 0.75, D = -2 })
	table.insert(WEB_KEYS, { t = s + 0.01, e = "in", bp = 0.16, by = by, fang = 0.3, D = 0 })
end
table.insert(WEB_KEYS, { t = 1.6, bp = 0, by = 0, fang = 0.3 })
table.insert(WEB_KEYS, { t = 2.4, reset = true })
local ATTACKS = {
	Impale = { duration = 2.15, tr = track({
		{ t = 0 },
		{ t = 0.8, D = 4, bp = -0.55, abx = 0.4, f1l = 1.25, f1k = -0.7, f1s = 0.45, f2l = 0.45, f2k = -0.2, f34l = -0.25, f34k = 0.2, fang = 0.5, eye = 1 },
		{ t = 0.95, e = "in", D = -2, bp = 0.22, abx = -0.15, f1l = -0.35, f1k = 0.3, f1s = 0.6, f2l = 0, f2k = 0, f34l = 0.08, f34k = -0.08, fang = 0.15 },
		{ t = 1.35 },
		{ t = 2.15, reset = true },
	}) },
	Web = { duration = 2.4, tr = track(WEB_KEYS) },
	Spawn = { duration = 2.8, tr = track({
		{ t = 0 },
		{ t = 0.6, D = 1, abs = 0.16, abx = 0.08, eye = 1, glow = 1, f34l = 0.1 },
		{ t = 1.0, D = -4, abs = 0.1, abx = -0.42, bp = -0.12, f34l = 0.3, f34k = -0.25, f2l = 0.1 },
		{ t = 1.2, abs = 0.02 },
		{ t = 1.35, abs = 0.14 },
		{ t = 1.5, abs = 0.02 },
		{ t = 1.65, abs = 0.1 },
		{ t = 2.0, D = 0, abs = 0, abx = 0.05, bp = -0.2, f34l = 0, f34k = 0, f2l = 0.3, f1l = 0.5, f1k = -0.2, fang = 0.45, glow = 0.3 },
		{ t = 2.8, reset = true },
	}) },
}
local CYCLE = { "Impale", "Web", "Spawn" }

local function poseXf(c, w: number, ph: number, T: number)
	local xf: { [string]: CFrame } = {}
	local rig = CFrame.new(0, (c.D + math.sin(2 * ph) * 0.35 * w + math.sin(T * 1.6) * 0.18) * U, 0)
	local body = rig * around(P.body, c.bp + math.sin(2 * ph + 0.4) * 0.015 * w, c.by + math.sin(ph) * 0.03 * w, math.sin(ph) * 0.02 * w)
	xf.head = body
	xf.abdomen = body * around(P.waist, c.abx + math.sin(T * 1.6) * 0.03 + math.sin(2 * ph + 0.5) * 0.04 * w, -c.by * 0.3 + math.sin(ph - 0.6) * 0.06 * w, 0)
	local tw = math.max(0, math.sin(T * 2.3)) ^ 16 * 0.25
	xf.fang_L = body * around(P.fangL, 0, 0, -(c.fang + tw))
	xf.fang_R = body * around(P.fangR, 0, 0, c.fang + tw)
	for _, L in legs do
		local phi = ph + (if L.grp == 1 then math.pi else 0)
		local up = math.max(0, math.cos(phi))
		local lift, knee, swing = up * 0.3 * w, up * 0.1 * w, L.fwd * math.sin(phi) * 0.22 * w - c.by * 0.6
		lift += math.max(0, math.sin(T * 1.3 + (L.i - 1) * 1.7 + (if L.side > 0 then 2.3 else 0))) ^ 12 * 0.15 * (1 - w)
		if L.i == 1 then lift += c.f1l; knee += c.f1k; swing += L.fwd * c.f1s
		elseif L.i == 2 then lift += c.f2l; knee += c.f2k
		else lift += c.f34l; knee += c.f34k end
		local femur = body * around(L.hip, 0, swing, lift)
		xf["femur_" .. L.id] = femur
		xf["tibia_" .. L.id] = femur * around(L.knee, 0, 0, knee)
	end
	return xf
end
local function frontTips(xf: { [string]: CFrame })
	return { xf.tibia_L1:PointToWorldSpace(legs[1].tip), xf.tibia_R1:PointToWorldSpace(legs[5].tip) }
end
-- solve the impale knee so both front claws land on the ground, and predict the impact point (root space)
local HIT_LOCAL
do
	local tr = ATTACKS.Impale.tr
	local sp = tr[3].p
	local a, b = -1.5, 1.5
	for _ = 1, 30 do
		sp.f1k = (a + b) / 2
		local t = frontTips(poseXf(sp, 0, 0, 0))
		if math.min(t[1].Y, t[2].Y) > 0.5 * U then b = sp.f1k else a = sp.f1k end
	end
	tr[4].p.f1k = sp.f1k
	local t = frontTips(poseXf(sp, 0, 0, 0))
	HIT_LOCAL = Vector3.new((t[1].X + t[2].X) / 2, 0, (t[1].Z + t[2].Z) / 2)
end

-- ---------- VFX helpers ----------
local vfx = Instance.new("Folder"); vfx.Name = "SpiderBossVFX"; vfx.Parent = workspace
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
local warnParts: { Part } = {}
local function showWarning(center: Vector3)
	for i = 1, 52 do
		local c = cube(Vector3.new(1.2, 0.15, 0.6) * U, C.WARN[i % 2 + 1]); c.Transparency = 1
		warnParts[i] = c
	end
	local t0 = os.clock()
	task.spawn(function()
		while #warnParts > 0 do
			local k = math.clamp((os.clock() - t0) / 0.8, 0, 1)
			local r = lerp(15, 11.5, ease(k)) * U
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

local overlap = OverlapParams.new()
overlap.FilterDescendantsInstances = { spider, vfx }
overlap.FilterType = Enum.RaycastFilterType.Exclude
local function humanoidsIn(at: Vector3, radius: number): { [Humanoid]: BasePart }
	local out: { [Humanoid]: BasePart } = {}
	for _, part in workspace:GetPartBoundsInRadius(at, radius, overlap) do
		local char = part.Parent
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if hum and root and char.Name ~= "Spiderling" and not out[hum] then out[hum] = root :: BasePart end
	end
	return out
end
local function hurt(at: Vector3, radius: number, dmg: number, knock: number)
	for hum, root in humanoidsIn(at, radius) do
		hum:TakeDamage(dmg)
		if knock > 0 then
			local away = root.Position - at
			away = Vector3.new(away.X, 0, away.Z)
			away = if away.Magnitude > 0.01 then away.Unit else rootCF:VectorToWorldSpace(Vector3.zAxis) -- A03 : avant du rig = +Z
			root.AssemblyLinearVelocity = away * knock + Vector3.new(0, 35, 0)
		end
	end
end

-- ---------- 1) IMPALE ----------
local function venomPool(center: Vector3)
	local life = A("PoolTime")
	local s = 1.4 * U
	for i = -7, 7 do
		for j = -7, 7 do
			local x, z = i * s, j * s
			local r = math.sqrt(x * x + z * z)
			if r <= (9.5 + math.sin(math.atan2(z, x) * 4) * 0.75) * U then
				local p = cube(Vector3.new(s * 0.95, 0.1 * U, s * 0.95), C.VENOM[(i + j) % 2 + 1])
				p.CFrame = CFrame.new(center + Vector3.new(x, 0.08 * U, z)); p.Transparency = 1
				TweenService:Create(p, TweenInfo.new(0.3 * r / (9.5 * U) + 0.05), { Transparency = 0.35 }):Play()
				TweenService:Create(p, TweenInfo.new(0.6, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, life - 0.6), { Transparency = 1 }):Play()
				Debris:AddItem(p, life + 0.1)
			end
		end
	end
	task.spawn(function()
		local t = 0
		while t < life do
			burst(center + Vector3.new((math.random() - 0.5) * 16 * U, 0.3 * U, (math.random() - 0.5) * 16 * U), { C.VENOM[1], C.VENOM_LIGHT }, 4, 4 * U, 0.8, 0.7 * U, -2 * U, true, 20)
			hurt(center, 9.5 * U, A("PoolDps") * 0.5, 0)
			task.wait(0.5); t += 0.5
		end
	end)
end
local function impaleImpact(at: Vector3, tips: { Vector3 })
	hideWarning()
	local f = cube(Vector3.one * 0.1, C.VENOM[1]); f.Transparency = 1; f.Position = at + Vector3.new(0, 1.5 * U, 0)
	local l = Instance.new("PointLight"); l.Color, l.Range, l.Brightness = C.VENOM[1], 22 * U, 2.5; l.Parent = f
	TweenService:Create(l, TweenInfo.new(0.5), { Brightness = 0 }):Play()
	Debris:AddItem(f, 0.55)
	groundRing(at, 56, C.VENOM, 2 * U, 26 * U, 0.75, 1.4 * U, 0.6 * U)
	groundRing(at, 40, { Color3.new(1, 1, 1), C.VENOM_LIGHT }, 1.3 * U, 17 * U, 0.55, 0.9 * U, 0.5 * U)
	for _, tip in tips do
		local g = Vector3.new(tip.X, at.Y + 0.4 * U, tip.Z)
		burst(g, C.ROCK, 18, 35 * U, 1.6, 1.2 * U, 60 * U, false, 55)
		burst(g, { C.VENOM[1], Color3.new(1, 1, 1) }, 20, 25 * U, 0.8, 0.8 * U, 30 * U, true, 60)
	end
	burst(at + Vector3.new(0, 0.4 * U, 0), C.DUST, 34, 20 * U, 1.3, 1.4 * U, 10 * U, false, 85)
	for i = 1, 20 do
		local a, r = i / 20 * math.pi * 2 + (math.random() - 0.5) * 0.3, (3.5 + math.random() * 6.5) * U
		local c = cube(Vector3.new((3.5 + math.random() * 3.5) * U, 0.05 * U, (0.5 + math.random() * 0.3) * U), C.CRACK, false)
		c.CFrame = CFrame.new(at + Vector3.new(math.cos(a) * r, 0.04 * U, math.sin(a) * r)) * CFrame.Angles(0, -a, 0)
		TweenService:Create(c, TweenInfo.new(0.9, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 1.2), { Transparency = 1 }):Play()
		Debris:AddItem(c, 2.2)
	end
	venomPool(at)
	hurt(at, A("HitRadius"), A("Damage"), A("Knockback"))
end

-- ---------- 2) WEB ----------
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
local function webNet(center: Vector3)
	local life = A("WebTime")
	local rot = math.random() * 3
	local function bar(x0: number, z0: number, x1: number, z1: number)
		local L = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
		local c = cube(Vector3.new(L, 0.12 * U, 0.25 * U), C.WEB, false)
		c.CFrame = CFrame.new(center + Vector3.new((x0 + x1) / 2, 0.1 * U, (z0 + z1) / 2)) * CFrame.Angles(0, -math.atan2(z1 - z0, x1 - x0), 0)
		c.Transparency = 1
		TweenService:Create(c, TweenInfo.new(0.25), { Transparency = 0.1 }):Play()
		TweenService:Create(c, TweenInfo.new(0.6, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, life - 0.6), { Transparency = 1 }):Play()
		Debris:AddItem(c, life + 0.1)
	end
	local R = A("WebRadius")
	for k = 0, 11 do
		local a = k / 12 * math.pi * 2 + rot
		bar(0, 0, math.cos(a) * R, math.sin(a) * R)
	end
	for _, f in { 0.25, 0.5, 0.75, 0.96 } do
		for k = 0, 11 do
			local a0, a1 = k / 12 * math.pi * 2 + rot, (k + 1) / 12 * math.pi * 2 + rot
			local r = R * f * (0.92 + ((k * 7) % 5) * 0.03)
			bar(math.cos(a0) * r, math.sin(a0) * r, math.cos(a1) * r, math.sin(a1) * r)
		end
	end
	burst(center + Vector3.new(0, 0.5 * U, 0), { C.WEB, Color3.fromHex("D6D0EE") }, 26, 18 * U, 0.7, 0.8 * U, 20 * U, false, 80)
	-- sticky: damage + slow everyone inside, restore their speed afterwards
	for hum, _ in humanoidsIn(center, R) do
		hum:TakeDamage(A("WebDamage"))
		if hum:GetAttribute("SpiderWebbed") == nil then
			hum:SetAttribute("SpiderWebbed", hum.WalkSpeed)
			hum.WalkSpeed = A("WebSlow")
			task.delay(life, function()
				if hum.Parent then
					hum.WalkSpeed = hum:GetAttribute("SpiderWebbed") :: number
					hum:SetAttribute("SpiderWebbed", nil)
				end
			end)
		end
	end
end
local function fireWeb(xf: { [string]: CFrame }, i: number)
	local from = rootCF:PointToWorldSpace(xf.head:PointToWorldSpace(MOUTH))
	local a, d = WEB_FAN[i][1], WEB_FAN[i][2]
	local fan = Vector3.new(math.sin(a) * d * U, 0, math.cos(a) * d * U) -- root space
	local target = nearestPlayer(from, A("WebRange"))
	local to: Vector3
	if target then
		-- blanket the area around the player: same fan, re-centred on the target
		local centre = rootCF:PointToObjectSpace(target.Position)
		local off = fan - Vector3.new(0, 0, 55 * U)
		to = rootCF:PointToWorldSpace(Vector3.new(centre.X, 0, centre.Z) + off * 0.45)
	else
		to = rootCF:PointToWorldSpace(fan)
	end
	to = Vector3.new(to.X, ground, to.Z)
	local ballP = cube(Vector3.one * 2.2 * U, C.WEB, false); ballP.Shape = Enum.PartType.Ball; ballP.Position = from
	burst(from, { Color3.new(1, 1, 1) }, 10, 15 * U, 0.4, 0.5 * U, 10 * U, true, 40)
	task.spawn(function()
		local t = 0
		while t < 0.6 do
			t += RunService.Heartbeat:Wait()
			local k = math.min(1, t / 0.6)
			ballP.Position = from:Lerp(to, k) + Vector3.new(0, math.sin(k * math.pi) * 9 * U, 0)
			local s = cube(Vector3.one * 0.5 * U, C.WEB, false); s.Position = ballP.Position
			TweenService:Create(s, TweenInfo.new(0.35), { Size = Vector3.one * 0.05, Transparency = 1 }):Play()
			Debris:AddItem(s, 0.36)
		end
		ballP:Destroy()
		webNet(to)
	end)
end

-- ---------- 3) SPAWN: eggs + Spiderlings ----------
-- Spiderling = mini copy of the boss: dome head with glowing eyes + fangs, hairy abdomen with hourglass,
-- 8 legs with knees (femur + tibia parts) animated with the same tetrapod gait, body bob + sway.
local BL = { yaw = { 0.7, 0.25, -0.25, -0.7 }, z = { 2, 1, 0, -1 }, hipY = 3.5, LF = 3.5, LT = 6.5, FA = 0.7 }
local BL_TB = -(math.asin((BL.hipY + BL.LF * math.sin(BL.FA) - 0.3) / BL.LT) + BL.FA)
type Baby = { model: Model, hum: Humanoid, root: BasePart, born: number, dir: number, hitCd: number, ph: number,
	bodyParts: { { part: BasePart, rel: CFrame } }, legs: { { femur: BasePart, tibia: BasePart, hip: CFrame, fwd: number, grp: number } } }
local spiderlings: { Baby } = {}
local rayParams = RaycastParams.new()
rayParams.FilterDescendantsInstances = { spider, vfx }
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function groundY(at: Vector3): number
	local r = workspace:Raycast(at + Vector3.new(0, 20, 0), Vector3.new(0, -80, 0), rayParams)
	return if r then r.Position.Y else ground
end
local function makeSpiderling(at: Vector3, dir: number)
	if #spiderlings >= A("MaxSpiderlings") then return end
	local m = Instance.new("Model"); m.Name = "Spiderling"
	local function part(size: Vector3, color: Color3, neon: boolean?): Part
		local q = Instance.new("Part")
		q.Anchored, q.CanCollide, q.CanQuery, q.CastShadow = true, false, true, true
		q.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
		q.Size, q.Color = size, color
		q.Parent = m
		return q
	end
	local bodyParts = {}
	local function bodyPart(size: Vector3, color: Color3, rel: CFrame, neon: boolean?): Part
		local q = part(size * U, color, neon); table.insert(bodyParts, { part = q, rel = rel }); return q
	end
	-- body-local voxels: head centre (0,4,2), abdomen centre (0,4.5,-4)
	local root = bodyPart(Vector3.new(5, 3, 5), C.BABY, CFrame.new(0, 0, 2 * U)); root.Name = "HumanoidRootPart"
	bodyPart(Vector3.new(7, 6, 7), C.BABY_ABD, CFrame.new(0, 0.5 * U, -4 * U))
	bodyPart(Vector3.new(2, 1, 2), C.MARK, CFrame.new(0, 3.6 * U, -3.5 * U), true)
	for _, s in { -1, 1 } do
		bodyPart(Vector3.one, C.VENOM[1], CFrame.new(s * U, 0, 4.6 * U), true)
		bodyPart(Vector3.new(1, 1.6, 1), C.FANG, CFrame.new(s * U, -1.8 * U, 4.2 * U))
	end
	for _, o in { { -2.5, 3.2, -5 }, { 2.5, 3.2, -3 }, { 0, 3.8, -6 }, { -3.8, 1.5, -2.5 }, { 3.8, 1, -5.5 }, { 1.5, 3.6, -1.5 } } do
		bodyPart(Vector3.one, C.HAIR, CFrame.new(o[1] * U, o[2] * U, o[3] * U))
	end
	local legs = {}
	for _, side in { -1, 1 } do
		for i = 1, 4 do
			local yaw = if side > 0 then -BL.yaw[i] else math.pi + BL.yaw[i]
			table.insert(legs, {
				femur = part(Vector3.new(BL.LF, 1, 1) * U, C.BABY_LEG), tibia = part(Vector3.new(BL.LT, 1, 1) * U, C.BABY_LEG),
				hip = CFrame.new(2 * side * U, (BL.hipY - 4) * U, BL.z[i] * U) * CFrame.Angles(0, yaw, 0),
				fwd = if side < 0 then 1 else -1, grp = if ((i - 1) % 2 == 0) == (side < 0) then 0 else 1,
			})
		end
	end
	m.PrimaryPart = root
	local hum = Instance.new("Humanoid")
	hum.MaxHealth, hum.Health = A("SpiderlingHP"), A("SpiderlingHP")
	hum.Parent = m
	m.Parent = workspace
	root.CFrame = CFrame.new(at)
	table.insert(spiderlings, { model = m, hum = hum, root = root, born = os.clock(), dir = dir, hitCd = 0, ph = math.random() * 6, bodyParts = bodyParts, legs = legs })
end
-- place every part of a spiderling: base = ground point + heading, body bobs/sways, legs scuttle with knees
local function poseSpiderling(b: Baby, base: CFrame, running: boolean)
	local ph = b.ph
	local bodyCF = base * CFrame.new(0, (4 + math.abs(math.sin(ph)) * 0.35) * U, 0)
		* CFrame.Angles(math.sin(2 * ph) * 0.05, math.sin(ph) * 0.08, math.sin(ph) * 0.06)
	for _, bp in b.bodyParts do bp.part.CFrame = bodyCF * bp.rel end
	local amp = if running then 1 else 0.3
	for _, L in b.legs do
		local phi = ph + (if L.grp == 1 then math.pi else 0)
		local up = math.max(0, math.cos(phi))
		local hipCF = bodyCF * L.hip * CFrame.Angles(0, L.fwd * math.sin(phi) * 0.4 * amp, up * 0.55 * amp + BL.FA)
		L.femur.CFrame = hipCF * CFrame.new(BL.LF / 2 * U, 0, 0)
		local kneeCF = hipCF * CFrame.new(BL.LF * U, 0, 0) * CFrame.Angles(0, 0, BL_TB + up * 0.25 * amp)
		L.tibia.CFrame = kneeCF * CFrame.new(BL.LT / 2 * U, 0, 0)
	end
end
-- A03 : la copie de Claude Design définissait updateSpiderlings deux fois ; la 2e (sans pattes, avec PivotTo) masquait
-- celle-ci et laissait les pièces des bébés à l'origine du monde. Seule cette version, animée, est gardée.
local function updateSpiderlings(dt: number)
	for idx = #spiderlings, 1, -1 do
		local b = spiderlings[idx]
		local age = os.clock() - b.born
		if b.hum.Health <= 0 or age > A("SpiderlingLife") or not b.model.Parent then
			if b.model.Parent then
				burst(b.root.Position, { C.BABY_LEG, C.VENOM[1] }, 12, 15 * U, 0.5, 0.7 * U, 20 * U, true, 180)
				b.model:Destroy()
			end
			table.remove(spiderlings, idx)
			continue
		end
		local pos = b.root.Position
		local target = if age > 0.8 then nearestPlayer(pos, 200) else nil
		local moving = true
		if target then
			local d = target.Position - pos
			b.dir = math.atan2(d.X, d.Z)
			if Vector3.new(d.X, 0, d.Z).Magnitude < 4.5 then
				moving = false
				b.hitCd -= dt
				if b.hitCd <= 0 then
					b.hitCd = 0.8
					local hum = target.Parent and target.Parent:FindFirstChildOfClass("Humanoid")
					if hum then hum:TakeDamage(A("SpiderlingDamage")) end
				end
			end
		end
		b.ph += dt * (if moving then 18 else 6)
		local np = if moving then pos + Vector3.new(math.sin(b.dir), 0, math.cos(b.dir)) * A("SpiderlingSpeed") * dt else pos
		poseSpiderling(b, CFrame.new(np.X, groundY(np), np.Z) * CFrame.Angles(0, b.dir, 0) * CFrame.new(0, 0, -2 * U), moving)
	end
end
local eggParts: { Part } = {}
local function dropEgg(xf: { [string]: CFrame }, i: number)
	local from = rootCF:PointToWorldSpace(xf.abdomen:PointToWorldSpace(SPINNERET))
	local a = math.pi + (i - 3) * 0.45
	local land = from + rootCF:VectorToWorldSpace(Vector3.new(math.sin(a), 0, math.cos(a)) * 8 * U)
	land = Vector3.new(land.X, groundY(land) + 2.5 * U, land.Z)
	local e = cube(Vector3.one * 5 * U, C.EGG, false); e.Shape = Enum.PartType.Ball; e.Position = from; e.Size = Vector3.one * 1.5 * U
	TweenService:Create(e, TweenInfo.new(0.5, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), { Position = land, Size = Vector3.one * 5 * U }):Play()
	burst(from, { C.VENOM[1] }, 6, 8 * U, 0.5, 0.5 * U, 10 * U, true, 180)
	eggParts[i] = e
end
local function hatch(i: number)
	local e = eggParts[i]
	if not e then return end
	local at = e.Position
	burst(at, { C.EGG, C.VENOM[1] }, 14, 20 * U, 0.6, 0.8 * U, 30 * U, true, 90)
	e:Destroy(); eggParts[i] = nil
	local s = if i % 2 == 0 then 1 else -1
	local fwd = rootCF:VectorToWorldSpace(Vector3.zAxis) -- A03 : avant du rig = +Z (le LookVector de Roblox regarde derrière)
	local look = math.atan2(fwd.X, fwd.Z)
	for _ = 1, math.max(1, math.floor(A("SpawnCount") / 5 + 0.5)) do
		makeSpiderling(Vector3.new(at.X, groundY(at), at.Z), look + s * 2.2)
	end
end
-- ---------- Abdomen glow light (Spawn) ----------
local glowHolder = cube(Vector3.one * 0.1, C.MARK); glowHolder.Transparency = 1
local glowLight = Instance.new("PointLight"); glowLight.Color, glowLight.Range, glowLight.Brightness = C.MARK, 20 * U, 0; glowLight.Parent = glowHolder

-- ---------- Attack state ----------
local attackKind: string? = nil
local attackT = 0
local evIndex = 1
local hitPoint = Vector3.zero
local cycleI = 0
local lastXf: { [string]: CFrame } = {}
local EVENTS: { [string]: { { any } } } = {
	Impale = { { 0.94, function() local t = frontTips(lastXf); impaleImpact(hitPoint, { rootCF:PointToWorldSpace(t[1]), rootCF:PointToWorldSpace(t[2]) }) end } },
	Web = {},
	Spawn = {},
}
for i, s in WEB_SHOTS do
	table.insert(EVENTS.Web, { s, function() fireWeb(lastXf, i) end })
end
for i = 1, 5 do
	table.insert(EVENTS.Spawn, { 1.05 + (i - 1) * 0.14, function() dropEgg(lastXf, i) end })
end
for i = 1, 5 do
	table.insert(EVENTS.Spawn, { 1.9 + (i - 1) * 0.06, function() hatch(i) end })
end
local function startAttack(kind: string?)
	if attackKind then return end
	if not kind then cycleI += 1; kind = CYCLE[(cycleI - 1) % #CYCLE + 1] end
	attackKind, attackT, evIndex = kind, 0, 1
	if kind == "Impale" then hitPoint = rootCF:PointToWorldSpace(HIT_LOCAL); showWarning(hitPoint) end
end
for _, k in CYCLE do spider:GetAttributeChangedSignal(k):Connect(function() startAttack(k) end) end

-- ---------- Animation loop ----------
local T, nextAuto, wS, fxAcc = 0, 2.0, 0, 0
local prevUp = { 0, 0 }
RunService.Heartbeat:Connect(function(dt)
	T += dt
	local c = REST
	if attackKind then
		local def = ATTACKS[attackKind]
		attackT += dt
		c = sample(def.tr, attackT)
	end
	wS += ((if spider:GetAttribute("Walking") and not attackKind then 1 else 0) - wS) * math.min(1, dt * 3)
	local ph = T * 4.2
	local xf = poseXf(c, wS, ph, T)
	lastXf = xf
	for name, cf in xf do
		if name == "abdomen" then placeScaled(name, cf, P.waist, 1 + c.abs + math.sin(T * 1.6) * 0.01) else place(name, cf) end
	end

	if attackKind then
		local ev = EVENTS[attackKind]
		while evIndex <= #ev and attackT >= ev[evIndex][1] do ev[evIndex][2](); evIndex += 1 end
		fxAcc += dt
		if attackKind == "Impale" and attackT < 0.8 and fxAcc > 0.1 then
			fxAcc = 0
			burst(rootCF:PointToWorldSpace(xf.fang_L:PointToWorldSpace(FANG_TIP.L)), { C.VENOM[1] }, 1, 2 * U, 0.7, 0.5 * U, 40 * U, true, 10)
			burst(rootCF:PointToWorldSpace(xf.fang_R:PointToWorldSpace(FANG_TIP.R)), { C.VENOM[1] }, 1, 2 * U, 0.7, 0.5 * U, 40 * U, true, 10)
		elseif attackKind == "Impale" and attackT > 0.8 and attackT < 0.96 then
			for _, tp in frontTips(xf) do
				local q = cube(Vector3.one * 1.6 * U, if math.random() < 0.5 then C.VENOM[1] else C.VENOM_LIGHT)
				q.Position = rootCF:PointToWorldSpace(tp)
				TweenService:Create(q, TweenInfo.new(0.25), { Size = Vector3.one * 0.1, Transparency = 1 }):Play()
				Debris:AddItem(q, 0.27)
			end
		elseif attackKind == "Web" and attackT < 1.3 and fxAcc > 0.05 then
			fxAcc = 0
			local m = rootCF:PointToWorldSpace(xf.head:PointToWorldSpace(MOUTH))
			burst(m, { Color3.new(1, 1, 1) }, 2, 3 * U, 0.4, 0.4 * U, 0, true, 180)
		elseif attackKind == "Spawn" and attackT > 0.2 and attackT < 1.7 and fxAcc > 0.08 then
			fxAcc = 0
			burst(rootCF:PointToWorldSpace(xf.abdomen:PointToWorldSpace(ABD_CENTRE + Vector3.new(0, 8 * U, 0))), { C.VENOM[1] }, 2, 4 * U, 0.8, 0.5 * U, -3 * U, true, 60)
		end
		if attackT >= ATTACKS[attackKind].duration then attackKind = nil end
	end

	-- abdomen glow (Spawn)
	glowHolder.Position = rootCF:PointToWorldSpace(xf.abdomen:PointToWorldSpace(ABD_CENTRE))
	glowLight.Brightness = c.glow * (2 + math.sin(T * 18) * 0.6)

	-- footfalls: dust under each tetrapod group as it lands
	for g = 0, 1 do
		local up = if math.cos(ph + (if g == 1 then math.pi else 0)) > 0 then 1 else 0
		if wS > 0.5 and prevUp[g + 1] == 1 and up == 0 then
			for _, L in legs do
				if L.grp == g then
					local f = rootCF:PointToWorldSpace(xf["tibia_" .. L.id]:PointToWorldSpace(L.tip))
					burst(Vector3.new(f.X, ground + 0.3 * U, f.Z), { C.DUST[1], C.DUST[2] }, 5, 8 * U, 0.7, 0.8 * U, 4 * U, false, 85)
				end
			end
		end
		prevUp[g + 1] = up
	end

	updateSpiderlings(dt)

	for _, e in eyes do
		e.Color = C.EYE:Lerp(C.EYE_RAGE, c.eye)
		e.Material = if c.eye > 0.05 then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end

	if spider:GetAttribute("AutoAttack") and not attackKind then
		nextAuto -= dt
		if nextAuto <= 0 then nextAuto = A("AttackEvery"); startAttack(nil) end
	end
end)
