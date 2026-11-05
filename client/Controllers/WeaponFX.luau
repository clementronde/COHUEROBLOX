--!strict
-- Draws weapon visuals from WeaponFx events (WeaponFxCodec). Cosmetic only (dossier 10, section 10).
-- A14 (dossier 12, section 9) : rien n'est construit ici. Chaque effet est un modèle posé dans la place
-- (ReplicatedStorage.Assets.FX, armes en pixel art dans Assets.Weapons) ; ce module les clone (en pool),
-- les place, change leur taille et leur transparence, et déclenche leurs particules. Un modèle manquant est
-- signalé une fois dans la sortie, puis ignoré : on ne le remplace jamais par une Part.
-- Qualité : téléphone = Basse (moins de pièces, pas de traînées ni de lumières, moitié des particules).
-- Les télégraphes (zones de gameplay) ne sont jamais coupés (vault : VFX Performance Budgets and Culling).
-- Il accroche aussi l'arme de départ de la classe dans la main de chaque joueur (décision du 5 nov.).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Weapons = require(Config:WaitForChild("Weapons"))
local Classes = require(Config:WaitForChild("Classes"))
local Codec = require(Shared:WaitForChild("WeaponFxCodec"))
local Heightmap = require(Shared:WaitForChild("Heightmap"))
local Net = require(Shared:WaitForChild("Net"))

local HIDDEN = CFrame.new(0, -10000, 0)
local KIND = Codec.Kind
local PROJ_HEIGHT = 2.5
local FALL_HEIGHT = 18
local HELD_SCALE = 1.4 -- l'arme tenue un peu surdimensionnée reste lisible à la caméra dézoomée
-- Dans la poignée R15, +Y pointe vers l'avant et +Z vers le haut : 70° autour de X dressent l'arme
-- (lame vers le haut, un peu en avant) et tournent sa face de sprite vers l'arrière, côté caméra.
local DEFAULT_HOLD = CFrame.Angles(math.rad(70), 0, 0)

type Tier = {
	maxProj: number,
	maxAreas: number,
	maxSegments: number,
	maxAttach: number,
	particles: number, -- facteur sur les rafales
	trails: boolean,
	lights: boolean,
	fade: boolean,
}

local TIERS: { [string]: Tier } = {
	Low = { maxProj = 60, maxAreas = 12, maxSegments = 16, maxAttach = 24, particles = 0.5, trails = false, lights = false, fade = false },
	Medium = { maxProj = 150, maxAreas = 28, maxSegments = 40, maxAttach = 48, particles = 0.8, trails = true, lights = false, fade = true },
	High = { maxProj = 300, maxAreas = 56, maxSegments = 80, maxAttach = 96, particles = 1, trails = true, lights = true, fade = true },
}

-- Informations lues une fois sur chaque clone (attributs posés par assets/a14/install/A14_fx_install.luau)
type ShapeInfo = {
	part: BasePart,
	base: Vector3,
	s: number,
	c: Vector3,
	grow: number,
	fade0: number,
	fade1: number,
	seg: number,
	spin: number,
	life: number,
	fill: boolean,
	shrink: number,
	pulse: number,
}
type BeamInfo = { beam: Beam, seg: number, w: number, t: number }
type BurstInfo = { e: ParticleEmitter, n: number, perRadius: boolean, sizeR: NumberSequence? }
type FxInst = {
	model: Model,
	template: Model,
	anchor: BasePart,
	kind: string,
	life: number,
	height: number,
	spin: number,
	tilt: number,
	shapes: { ShapeInfo },
	beams: { BeamInfo },
	zones: { { part: BasePart, s: number, life: number } },
	bursts: { BurstInfo },
	continuous: { ParticleEmitter },
	lights: { PointLight },
	trails: { Trail },
	piece: Model?,
	pieceOffset: CFrame,
	attachments: { [string]: Attachment },
}

type ProjEntry = {
	fx: FxInst,
	visual: number,
	x0: number,
	z0: number,
	vx: number,
	vz: number,
	t0: number,
	life: number,
	slot: number,
	boomerang: boolean,
	outTime: number,
	x: number,
	z: number,
	last: number,
	trailOn: boolean,
}

type AreaEntry = {
	fx: FxInst?,
	tele: FxInst?,
	fall: FxInst?,
	visual: number,
	x: number,
	z: number,
	radius: number,
	dir: number,
	half: number,
	t0: number,
	delay: number,
	started: boolean,
	flip: boolean,
}

type SegEntry = { fx: FxInst, t0: number, life: number }

type AttachEntry = {
	fxs: { FxInst },
	visual: number,
	slot: number,
	fixed: boolean,
	mode: string, -- "orbit" | "aura" | "turret"
	x: number,
	z: number,
	radius: number,
	count: number,
	spin: number,
	t0: number,
	life: number,
}

local WeaponFX = {}

local tier: Tier = TIERS.Medium
local container: Folder
local fxRoot: Instance?
local weaponsRoot: Instance?
local pools: { [Model]: { FxInst } } = {}
local projs: { [number]: ProjEntry } = {}
local projCount = 0
local areas: { AreaEntry } = {}
local segs: { SegEntry } = {}
local attaches: { AttachEntry } = {}
local slotCache: { [number]: Player } = {}
local latestTick = 0
local warned: { [string]: boolean } = {}
local rng = Random.new()

local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}
local moveN = 0
local pendingBursts: { { fx: FxInst, radius: number } } = {} -- rafales après le placement de l'image

-- Noms des visuels spéciaux (Codec.Visual -> dossier Assets.FX.Special.<Nom>)
local SPECIAL: { [number]: string } = {}
for name, id in Codec.Visual do
	SPECIAL[id] = name
end

-- Qualité ----------------------------------------------------------------------------------------

local function detectTier(): Tier
	-- Heuristic (vault: Mobile and Low-End Optimization): touch without keyboard = phone/tablet.
	local camera = Workspace.CurrentCamera
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		local short = if camera then math.min(camera.ViewportSize.X, camera.ViewportSize.Y) else 400
		return if short < 500 then TIERS.Low else TIERS.Medium
	end
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel
	end)
	if ok and level ~= Enum.SavedQualitySetting.Automatic then
		local v = (level :: Enum.SavedQualitySetting).Value
		if v <= 4 then
			return TIERS.Low
		elseif v <= 7 then
			return TIERS.Medium
		end
	end
	return TIERS.High
end

-- Modèles ----------------------------------------------------------------------------------------

local function warnOnce(key: string, msg: string)
	if not warned[key] then
		warned[key] = true
		warn("[WeaponFX] " .. msg)
	end
end

local function folderFor(visual: number): Instance?
	local root = fxRoot
	if not root then
		return nil
	end
	local def = Weapons.ByIndex[visual]
	if def then
		local w = root:FindFirstChild("Weapons")
		return w and w:FindFirstChild(def.id)
	end
	local name = SPECIAL[visual]
	local sp = root:FindFirstChild("Special")
	return name and sp and sp:FindFirstChild(name) or nil
end

local function templateFor(visual: number, role: string, quiet: boolean?): Model?
	local f = folderFor(visual)
	local m = f and f:FindFirstChild(role)
	if not m and role == "Telegraph" and fxRoot then
		local shared = (fxRoot :: Instance):FindFirstChild("Shared")
		m = shared and shared:FindFirstChild("Telegraph")
	end
	if m and m:IsA("Model") then
		return m
	end
	if not quiet then
		warnOnce(visual .. role, `modèle manquant : Assets.FX pour le visuel {visual}, rôle {role}`)
	end
	return nil
end

local function num(i: Instance, name: string, default: number): number
	local v = i:GetAttribute(name)
	return if type(v) == "number" then v else default
end

local function describe(model: Model, template: Model): FxInst
	local anchor = (model.PrimaryPart or model:FindFirstChild("Anchor")) :: BasePart
	local fx: FxInst = {
		model = model,
		template = template,
		anchor = anchor,
		kind = tostring(template:GetAttribute("Kind") or ""),
		life = num(template, "Life", 0.4),
		height = num(template, "Height", 0.08),
		spin = num(template, "Spin", 0),
		tilt = math.rad(num(template, "Tilt", 0)),
		shapes = {},
		beams = {},
		zones = {},
		bursts = {},
		continuous = {},
		lights = {},
		trails = {},
		piece = nil,
		pieceOffset = CFrame.new(),
		attachments = {},
	}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child ~= anchor then
			if child.Name == "Zone" or child.Name == "Burn" then
				table.insert(fx.zones, { part = child, s = num(child, "S", 1), life = num(child, "Life", 0) })
			else
				local base = child:GetAttribute("Base")
				local c = child:GetAttribute("C")
				table.insert(fx.shapes, {
					part = child,
					base = if typeof(base) == "Vector3" then base else child.Size,
					s = num(child, "S", 1),
					c = if typeof(c) == "Vector3" then c else Vector3.zero,
					grow = num(child, "Grow", 1),
					fade0 = num(child, "Fade0", child.Transparency),
					fade1 = num(child, "Fade1", child.Transparency),
					seg = num(child, "Seg", 0),
					spin = num(child, "Spin", 0),
					life = num(child, "Life", 0),
					fill = child:GetAttribute("Fill") == true,
					shrink = num(child, "Shrink", 0),
					pulse = num(child, "Pulse", 0),
				})
			end
		elseif child:IsA("Model") and child:GetAttribute("Piece") then
			fx.piece = child
			local off = child:GetAttribute("Offset")
			fx.pieceOffset = if typeof(off) == "CFrame" then off else CFrame.new()
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			if d:GetAttribute("Continuous") == true then
				table.insert(fx.continuous, d)
			end
			local n = num(d, "Burst", 0)
			if n > 0 then
				table.insert(fx.bursts, {
					e = d,
					n = n,
					perRadius = d:GetAttribute("PerRadius") == true,
					sizeR = if d:GetAttribute("SizeR") == true then d.Size else nil, -- taille en rayons
				})
			end
		elseif d:IsA("Beam") and d:GetAttribute("Layer") then
			table.insert(fx.beams, { beam = d, seg = num(d, "Seg", 1), w = num(d, "W", d.Width0), t = num(d, "T", 0) })
		elseif d:IsA("PointLight") then
			table.insert(fx.lights, d)
		elseif d:IsA("Trail") then
			table.insert(fx.trails, d)
		elseif d:IsA("Attachment") then
			fx.attachments[d.Name] = d
		end
	end
	return fx
end

local function acquire(template: Model): FxInst
	local pool = pools[template]
	local fx = pool and table.remove(pool)
	if fx then
		return fx
	end
	local model = template:Clone()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	model:PivotTo(HIDDEN)
	model.Parent = container
	return describe(model, template)
end

local function setActive(fx: FxInst, on: boolean)
	for _, e in fx.continuous do
		e.Enabled = on
	end
	for _, l in fx.lights do
		l.Enabled = on and tier.lights
	end
	for _, t in fx.trails do
		t.Enabled = false
		t:Clear()
	end
end

local function release(fx: FxInst?)
	if not fx then
		return
	end
	setActive(fx, false)
	fx.anchor.CFrame = HIDDEN
	for _, sh in fx.shapes do
		sh.part.CFrame = HIDDEN
	end
	for _, z in fx.zones do
		z.part.CFrame = HIDDEN
	end
	local pool = pools[fx.template]
	if not pool then
		pool = {}
		pools[fx.template] = pool
	end
	table.insert(pool, fx)
end

local function scaled(s: NumberSequence, k: number): NumberSequence
	local kps = table.create(#s.Keypoints)
	for i, kp in s.Keypoints do
		kps[i] = NumberSequenceKeypoint.new(kp.Time, kp.Value * k, kp.Envelope * k)
	end
	return NumberSequence.new(kps)
end

local function burst(fx: FxInst, radius: number)
	for _, b in fx.bursts do
		local k = if b.perRadius then math.clamp(radius / 5, 0.5, 3) else 1
		local n = math.max(1, math.floor(b.n * k * tier.particles + 0.5))
		local base = b.sizeR
		if base then
			b.e.Size = scaled(base, radius)
		end
		b.e:Emit(n)
	end
end

local function queue(part: BasePart, cf: CFrame)
	moveN += 1
	moveParts[moveN] = part
	moveCFrames[moveN] = cf
end

-- Pose un effet « au sol » : formes à l'échelle du rayon, zones, transparences selon u (0..1)
local function placeArea(fx: FxInst, base: CFrame, radius: number, u: number, progress: number?)
	local e = 1 - (1 - math.clamp(u, 0, 1)) ^ 2
	queue(fx.anchor, base) -- émetteurs posés au centre (onde de choc, éclair)
	for _, sh in fx.shapes do
		local life = if sh.life > 0 then sh.life / math.max(fx.life, 0.01) else 1
		local v = math.clamp(u / life, 0, 1)
		local k = if sh.shrink > 0 and progress then 1 - sh.shrink * progress
			elseif sh.fill and progress then math.max(progress, 0.05)
			elseif sh.grow < 1 then sh.grow + (1 - sh.grow) * e
			else 1
		local r = radius * sh.s * k
		sh.part.Size = Vector3.new(sh.base.X * r, sh.base.Y, sh.base.Z * r)
		local cf = base * CFrame.new(sh.c * r)
		if sh.spin ~= 0 then
			cf *= CFrame.Angles(0, os.clock() * sh.spin, 0)
		end
		queue(sh.part, cf)
		local tr = sh.fade0 + (sh.fade1 - sh.fade0) * (if tier.fade then v else 0)
		if sh.pulse > 0 then
			tr = math.clamp(tr + 0.25 * math.sin(os.clock() * math.pi * 2 / sh.pulse), 0, 1)
		end
		sh.part.Transparency = if v >= 1 and sh.life > 0 then 1 else tr
	end
	for _, z in fx.zones do
		z.part.Size = Vector3.new(2 * radius * z.s, 0.2, 2 * radius * z.s)
		queue(z.part, base)
		if z.life > 0 and u * fx.life >= z.life then
			for _, em in z.part:GetChildren() do
				if em:IsA("ParticleEmitter") then
					em.Enabled = false
				end
			end
		end
	end
end

local function groundY(x: number, z: number): number
	return Heightmap.getY(x, z)
end

local function playerFromSlot(slot: number): Player?
	local p = slotCache[slot]
	if p and p.Parent then
		return p
	end
	for _, other in Players:GetPlayers() do
		if other:GetAttribute("FxSlot") == slot then
			slotCache[slot] = other
			return other
		end
	end
	return nil
end

local function ownerPosition(slot: number): (number?, number?)
	local p = playerFromSlot(slot)
	local character = p and p.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local pos = root.Position
		return pos.X, pos.Z
	end
	return nil, nil
end

-- Évènements -------------------------------------------------------------------------------------

local function removeProj(id: number, impact: boolean)
	local e = projs[id]
	if not e then
		return
	end
	if impact then
		local tpl = templateFor(e.visual, "Impact", true)
		if tpl then
			local fx = acquire(tpl)
			fx.anchor.CFrame = CFrame.new(e.x, groundY(e.x, e.z) + fx.height, e.z)
			burst(fx, 1)
			table.insert(segs, { fx = fx, t0 = os.clock(), life = math.max(fx.life, 0.3) })
		end
	end
	release(e.fx)
	projs[id] = nil
	projCount -= 1
end

local function onProjectile(_scale: number, visual: number, id: number, x: number, z: number, p1: number, p2: number, p3: number, p4: number)
	if projs[id] then
		removeProj(id, false)
	end
	if projCount >= tier.maxProj then
		return
	end
	local tpl = templateFor(visual, "Projectile")
	if not tpl then
		return
	end
	local def = Weapons.ByIndex[visual]
	local boomerang = def ~= nil and def.fx.boomerang == true
	local life = p3 / 10
	local outRatio = 0
	if def and (def.base.life or 0) > 0 then
		outRatio = (def.base.outTime or 0) / def.base.life
	end
	local fx = acquire(tpl)
	setActive(fx, true)
	projs[id] = {
		fx = fx,
		visual = visual,
		x0 = x,
		z0 = z,
		vx = p1 / Codec.Scale,
		vz = p2 / Codec.Scale,
		t0 = os.clock(),
		life = life,
		slot = p4,
		boomerang = boomerang,
		outTime = life * outRatio,
		x = x,
		z = z,
		last = os.clock(),
		trailOn = false,
	}
	projCount += 1
end

local function onArea(_scale: number, visual: number, x: number, z: number, p1: number, p2: number, p3: number, p4: number)
	local delay = p4 / 10
	if #areas >= tier.maxAreas and delay <= 0 then
		return
	end
	local entry: AreaEntry = {
		fx = nil,
		tele = nil,
		fall = nil,
		visual = visual,
		x = x,
		z = z,
		radius = p1 / Codec.Scale,
		dir = p2 / 100,
		half = p3,
		t0 = os.clock(),
		delay = delay,
		started = false,
		flip = rng:NextNumber() < 0.5,
	}
	if delay > 0 then
		local t = templateFor(visual, "Telegraph")
		entry.tele = if t then acquire(t) else nil
		local f = templateFor(visual, "Fall", true)
		if f then
			entry.fall = acquire(f)
			setActive(entry.fall :: FxInst, true)
		end
	end
	table.insert(areas, entry)
end

local function onSegment(visual: number, x: number, z: number, p1: number, p2: number)
	if #segs >= tier.maxSegments then
		return
	end
	local tpl = templateFor(visual, "Segment")
	if not tpl then
		return
	end
	local fx = acquire(tpl)
	local x2, z2 = p1 / Codec.Scale, p2 / Codec.Scale
	local a = Vector3.new(x, groundY(x, z) + PROJ_HEIGHT, z)
	local b = Vector3.new(x2, groundY(x2, z2) + 1.5, z2)
	fx.anchor.CFrame = CFrame.new(a)
	local side = (b - a):Cross(Vector3.yAxis)
	side = if side.Magnitude > 0.01 then side.Unit else Vector3.xAxis
	-- autant de points que le modèle en porte (P0..Pn) : zigzag fin, petits écarts au hasard
	local n = 1
	while fx.attachments["P" .. (n + 1)] do
		n += 1
	end
	local amp = math.clamp((b - a).Magnitude * 0.05, 0.25, 0.7)
	for i = 0, n do
		local at = fx.attachments["P" .. i]
		if at then
			local t = i / n
			local jitter = if i == 0 or i == n then Vector3.zero
				else side * rng:NextNumber(-amp, amp) + Vector3.new(0, rng:NextNumber(-0.25, 0.25), 0)
			at.WorldPosition = a:Lerp(b, t) + jitter
		end
	end
	local tip = fx.attachments.Tip
	if tip then
		tip.WorldPosition = b
	end
	burst(fx, 1)
	table.insert(segs, { fx = fx, t0 = os.clock(), life = fx.life })
end

local function releaseAttach(e: AttachEntry)
	for _, fx in e.fxs do
		release(fx)
	end
	table.clear(e.fxs)
end

local function onAttach(visual: number, slot: number, x: number, z: number, p1: number, p2: number, p3: number, p4: number)
	local fixed = p3 >= 128
	local count = math.max(1, p3 % 128)
	local def = Weapons.ByIndex[visual]
	local mode = if fixed then "turret" elseif def and def.fx.orbit then "orbit" else "aura"
	local wanted = if mode == "orbit" then count else 1
	if not fixed then
		for i, e in attaches do
			if e.slot == slot and e.visual == visual and not e.fixed then
				if #e.fxs == wanted then
					-- Rafraîchissement d'une zone permanente : on garde l'angle (pas de saut)
					e.radius, e.count, e.spin = p1 / Codec.Scale, count, p4 / 20
					e.life = (os.clock() - e.t0) + p2 / 100
					return
				end
				releaseAttach(e)
				table.remove(attaches, i)
				break
			end
		end
	end
	if #attaches >= tier.maxAttach then
		return
	end
	local role = if mode == "orbit" then "Orbit" elseif mode == "turret" then "Turret" else "Aura"
	local tpl = templateFor(visual, role)
	if not tpl then
		return
	end
	local fxs = table.create(wanted)
	for k = 1, wanted do
		local fx = acquire(tpl)
		setActive(fx, true)
		fxs[k] = fx
	end
	if mode == "turret" then
		local fx = fxs[1]
		fx.anchor.CFrame = CFrame.new(x, groundY(x, z) + fx.height, z)
		burst(fx, 1)
	end
	table.insert(attaches, {
		fxs = fxs,
		visual = visual,
		slot = slot,
		fixed = fixed,
		mode = mode,
		x = x,
		z = z,
		radius = p1 / Codec.Scale,
		count = count,
		spin = p4 / 20,
		t0 = os.clock(),
		life = p2 / 100,
	})
end

local function onPacket(payload: unknown)
	if typeof(payload) ~= "buffer" then
		return
	end
	local b = payload :: buffer
	local ok, header = pcall(Codec.readHeader, b)
	if not ok or not header then
		return
	end
	-- events are one-shots: older ticks are still drawn unless clearly stale
	if header.tick + 30 < latestTick then
		return
	end
	latestTick = math.max(latestTick, header.tick)
	pcall(Codec.forEach, b, header.count, function(kind, scale, visual, a, x, z, p1, p2, p3, p4)
		if kind == KIND.Projectile then
			onProjectile(scale, visual, a, x, z, p1, p2, p3, p4)
		elseif kind == KIND.End then
			removeProj(a, true)
		elseif kind == KIND.Area then
			onArea(scale, visual, x, z, p1, p2, p3, p4)
		elseif kind == KIND.Segment then
			onSegment(visual, x, z, p1, p2)
		elseif kind == KIND.Attach then
			onAttach(visual, a, x, z, p1, p2, p3, p4)
		end
	end)
end

-- Image par image --------------------------------------------------------------------------------

-- Largeur du ruban le long du geste (u : 0 = départ, 1 = tête) : mince au départ, large vers la tête
local function slashBody(u: number): number
	local tip = math.max(0, (u - 0.85) / 0.15)
	return math.max(0.03, (u ^ 1.6) * (1 - tip * tip))
end

local TAIL_FADE = { 0.55, 0.2, 0 } -- les segments du départ sont plus transparents (traîne)

local function stepSlash(e: AreaEntry, fx: FxInst, base: CFrame, u: number)
	-- coup d'épée en ruban couché : S0..S3 posés sur l'arc (axe X = sens du geste), Beams courbés en arcs de
	-- cercle, largeur effilée, transparence qui monte avec la vie ; incliné de Tilt vers la caméra
	local half = math.rad(math.clamp(e.half, 10, 85))
	local a0, a1 = -half, half
	if e.flip then
		a0, a1 = a1, a0
	end
	local r = e.radius * 1.15
	local lift = math.tan(fx.tilt)
	local sign = if a1 > a0 then 1 else -1
	local nseg = 3
	local step = (a1 - a0) / nseg
	local curve = 4 / 3 * math.tan(math.abs(step) / 4) * r
	for k = 0, nseg do
		local at = fx.attachments["S" .. k]
		if at then
			local ang = a0 + step * k
			local dir = Vector3.new(math.sin(ang), 0, -math.cos(ang)) -- repère de base : avant = -Z
			local tan = Vector3.new(math.cos(ang), 0, math.sin(ang)) * sign
			local rr = r * (0.9 + 0.1 * slashBody(k / nseg))
			local p = dir * rr + Vector3.new(0, math.max(0, -dir.Z * rr) * lift, 0)
			at.CFrame = CFrame.fromMatrix(p, tan, Vector3.yAxis)
		end
	end
	local v = if tier.fade then math.clamp((u - 0.25) / 0.75, 0, 1) else 0
	for _, bi in fx.beams do
		local b = bi.beam
		local k0, k1 = (bi.seg - 1) / nseg, bi.seg / nseg
		b.Width0 = bi.w * slashBody(k0)
		b.Width1 = bi.w * slashBody(k1)
		b.CurveSize0 = curve
		b.CurveSize1 = curve
		local tail = TAIL_FADE[bi.seg] or 0
		local t0 = 1 - (1 - bi.t) * (1 - tail) * (1 - v)
		local t1 = 1 - (1 - bi.t) * (1 - (TAIL_FADE[bi.seg + 1] or 0)) * (1 - v)
		b.Transparency = NumberSequence.new(t0, t1)
	end
	queue(fx.anchor, base)
end

local function stepCone(e: AreaEntry, fx: FxInst, base: CFrame, u: number)
	if #fx.beams > 0 then
		stepSlash(e, fx, base, u)
		return
	end
	-- croissant : on montre les segments du milieu selon l'angle ; la fin du geste s'efface en dernier
	local total = 0
	for _, sh in fx.shapes do
		total = math.max(total, sh.seg)
	end
	local n = math.clamp(math.floor(2 * e.half / 20 + 0.5), 1, total)
	local first = math.floor((total - n) / 2) + 1
	for _, sh in fx.shapes do
		local k = sh.seg - first
		local r = e.radius * sh.s
		sh.part.Size = Vector3.new(sh.base.X * r, sh.base.Y, sh.base.Z * r)
		queue(sh.part, base * CFrame.new(sh.c * r))
		if k < 0 or k >= n then
			sh.part.Transparency = 1
		else
			local order = if e.flip then (n - 1 - k) else k -- 0 = début du geste
			local lag = if n > 1 then (1 - order / (n - 1)) * 0.6 else 0
			local v = math.clamp(u * 1.4 + lag - 0.2, 0, 1)
			sh.part.Transparency = if tier.fade then sh.fade0 + (1 - sh.fade0) * v else sh.fade0
		end
	end
	for _, z in fx.zones do
		z.part.Size = Vector3.new(2 * e.radius * z.s, 0.2, 2 * e.radius * z.s)
		queue(z.part, base * CFrame.new(0, 0, -e.radius * 0.7))
	end
end

local function stepAreas(now: number)
	for i = #areas, 1, -1 do
		local e = areas[i]
		local t = now - e.t0
		local y = groundY(e.x, e.z)
		if t < e.delay then
			local u = t / e.delay
			local tele = e.tele
			if tele then
				placeArea(tele, CFrame.new(e.x, y + tele.height, e.z), e.radius, u, u)
			end
			local fall = e.fall
			if fall then
				local h = FALL_HEIGHT * (1 - u)
				local cam = Workspace.CurrentCamera
				local p = Vector3.new(e.x + 4 * (1 - u), y + 0.8 + h, e.z + 4 * (1 - u))
				local yaw = 0
				if cam then
					local d = cam.CFrame.Position - p
					yaw = math.atan2(d.X, d.Z)
				end
				queue(fall.anchor, CFrame.new(p) * CFrame.Angles(0, yaw, 0))
				if not fall.trails[1] or fall.trails[1].Enabled ~= tier.trails then
					for _, tr in fall.trails do
						tr.Enabled = tier.trails
					end
				end
			end
			continue
		end
		if not e.started then
			e.started = true
			release(e.tele)
			e.tele = nil
			release(e.fall)
			e.fall = nil
			local cone = e.half > 0 and e.half < 180
			local tpl = templateFor(e.visual, if cone then "Cone" else "Area")
			if tpl then
				local fx = acquire(tpl)
				setActive(fx, true)
				e.fx = fx
				table.insert(pendingBursts, { fx = fx, radius = e.radius })
			end
		end
		local fx = e.fx
		if not fx then
			table.remove(areas, i)
			continue
		end
		local u = (t - e.delay) / math.max(fx.life, 0.05)
		if u >= 1 then
			release(fx)
			table.remove(areas, i)
			continue
		end
		local base = CFrame.new(e.x, y + fx.height, e.z)
		if e.half > 0 and e.half < 180 then
			local dx, dz = math.cos(e.dir), math.sin(e.dir)
			base = CFrame.lookAt(base.Position, base.Position + Vector3.new(dx, 0, dz))
			stepCone(e, fx, base, u)
		else
			placeArea(fx, base, e.radius, u)
		end
	end
end

local function onFrame()
	local now = os.clock()
	moveN = 0

	-- Projectiles
	for id, e in projs do
		local t = now - e.t0
		if t >= e.life then
			removeProj(id, false)
			continue
		end
		local dt = now - e.last
		e.last = now
		if e.boomerang and t >= e.outTime then
			local ox, oz = ownerPosition(e.slot)
			if ox and oz then
				local dx, dz = ox - e.x, oz - e.z
				local d = math.sqrt(dx * dx + dz * dz)
				if d < 2 then
					removeProj(id, false)
					continue
				end
				local sp = math.sqrt(e.vx * e.vx + e.vz * e.vz) * 1.2
				e.x += dx / d * sp * dt
				e.z += dz / d * sp * dt
			end
		else
			e.x = e.x0 + e.vx * t
			e.z = e.z0 + e.vz * t
		end
		local fx = e.fx
		local pos = Vector3.new(e.x, groundY(e.x, e.z) + fx.height, e.z)
		local cf = if e.vx ~= 0 or e.vz ~= 0 then CFrame.lookAt(pos, pos + Vector3.new(e.vx, 0, e.vz)) else CFrame.new(pos)
		if fx.spin ~= 0 then
			cf = CFrame.new(pos) * CFrame.Angles(0, t * fx.spin, 0)
		end
		queue(fx.anchor, cf)
		if not e.trailOn and tier.trails then
			e.trailOn = true -- la traînée s'allume une image après le placement (pas de trait depuis la cachette)
			for _, tr in fx.trails do
				task.defer(function()
					tr.Enabled = true
				end)
			end
		end
	end

	stepAreas(now)

	-- Segments et impacts (déjà placés : on les laisse vivre)
	for i = #segs, 1, -1 do
		local e = segs[i]
		if now - e.t0 >= e.life then
			release(e.fx)
			table.remove(segs, i)
		end
	end

	-- Effets attachés
	for i = #attaches, 1, -1 do
		local e = attaches[i]
		local t = now - e.t0
		if t >= e.life then
			releaseAttach(e)
			table.remove(attaches, i)
			continue
		end
		local cx, cz = e.x, e.z
		if not e.fixed then
			local ox, oz = ownerPosition(e.slot)
			if ox and oz then
				cx, cz = ox, oz
			end
		end
		local y = groundY(cx, cz)
		if e.mode == "orbit" then
			local n = #e.fxs
			for k, fx in e.fxs do
				local a = t * e.spin + (k - 1) / n * math.pi * 2
				local p = Vector3.new(cx + math.cos(a) * e.radius, y + fx.height, cz + math.sin(a) * e.radius)
				queue(fx.anchor, CFrame.new(p) * CFrame.Angles(0, -a - t * 12, 0))
				if tier.trails and fx.trails[1] and not fx.trails[1].Enabled then
					for _, tr in fx.trails do
						tr.Enabled = true
					end
				end
			end
		elseif e.mode == "aura" then
			local fx = e.fxs[1]
			placeArea(fx, CFrame.new(cx, y + fx.height, cz), e.radius, 0)
		else
			local fx = e.fxs[1]
			local cam = Workspace.CurrentCamera
			local yaw = 0
			if cam then
				local d = cam.CFrame.Position - Vector3.new(cx, y, cz)
				yaw = math.atan2(d.X, d.Z)
			end
			queue(fx.anchor, CFrame.new(cx, y + fx.height, cz) * CFrame.Angles(0, yaw, 0))
		end
	end

	if moveN > 0 then
		for k = moveN + 1, #moveParts do
			moveParts[k] = nil :: any
			moveCFrames[k] = nil :: any
		end
		Workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	for k, b in pendingBursts do
		burst(b.fx, b.radius)
		pendingBursts[k] = nil
	end
end

-- Arme tenue en main -----------------------------------------------------------------------------

local held: { [Player]: Model } = {}

local function dropHeld(player: Player)
	local m = held[player]
	if m then
		m:Destroy()
		held[player] = nil
	end
end

local function equipHeld(player: Player)
	dropHeld(player)
	local character = player.Character
	local classId = player:GetAttribute("ClassId")
	local root = weaponsRoot
	if not character or type(classId) ~= "string" or not root then
		return
	end
	local class = Classes[classId]
	if not class then
		return
	end
	local src = root:FindFirstChild(class.startWeapon)
	if not src or not src:IsA("Model") then
		warnOnce("held" .. class.startWeapon, `modèle manquant : Assets.Weapons.{class.startWeapon}`)
		return
	end
	local left = class.startWeapon == "Longbow" -- l'arc se tient à gauche
	local hand = character:FindFirstChild(if left then "LeftHand" else "RightHand")
	local grip = hand and hand:FindFirstChild(if left then "LeftGripAttachment" else "RightGripAttachment")
	if not hand or not hand:IsA("BasePart") or not grip or not grip:IsA("Attachment") then
		return
	end
	local m = src:Clone()
	m:ScaleTo(HELD_SCALE)
	local hold = src:GetAttribute("HoldCFrame")
	local offset = if typeof(hold) == "CFrame" then hold else DEFAULT_HOLD
	m:PivotTo(grip.WorldCFrame * offset)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.Massless = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			local w = Instance.new("WeldConstraint")
			w.Part0 = hand
			w.Part1 = d
			w.Parent = d
		end
	end
	m.Name = "HeldWeapon"
	m.Parent = character
	held[player] = m
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("RightHand", 10)
		equipHeld(player)
	end)
	player:GetAttributeChangedSignal("ClassId"):Connect(function()
		equipHeld(player)
	end)
	if player.Character then
		task.spawn(equipHeld, player)
	end
end

-- Cycle de vie -----------------------------------------------------------------------------------

function WeaponFX.init()
	tier = detectTier()
	container = Instance.new("Folder") -- dossier de rangement vide : invisible
	container.Name = "WeaponFX"
	container.Parent = Workspace
	local assets = ReplicatedStorage:WaitForChild("Assets", 10)
	fxRoot = assets and assets:FindFirstChild("FX")
	weaponsRoot = assets and assets:FindFirstChild("Weapons")
	if not fxRoot then
		warn("[WeaponFX] ReplicatedStorage.Assets.FX introuvable : aucun effet d'arme ne sera dessiné")
	end
end

function WeaponFX.start()
	Net.unreliable("WeaponFx").OnClientEvent:Connect(onPacket)
	Players.PlayerRemoving:Connect(function(player)
		for slot, p in slotCache do
			if p == player then
				slotCache[slot] = nil
			end
		end
		dropHeld(player)
	end)
	for _, p in Players:GetPlayers() do
		watchPlayer(p)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	RunService.RenderStepped:Connect(onFrame)
end

-- Debug / settings hook: "Low" | "Medium" | "High"
function WeaponFX.setQuality(name: string)
	local t = TIERS[name]
	if t then
		tier = t
	end
end

return WeaponFX
