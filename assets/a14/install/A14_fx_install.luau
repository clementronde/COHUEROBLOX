--!nocheck
-- A14 : construit les modèles d'effets des armes dans ReplicatedStorage.Assets.FX (généré par
-- assets/a14/make_fx_install.py à partir de fx_install_body.luau). À lancer une fois dans Studio, en mode
-- édition, APRÈS A14_weapons_install.luau (il a besoin des formes FX_* et des pièces de Assets.Weapons).
-- Règle « rien construit par script » : ces objets sont posés une fois dans la place ; WeaponFX ne fait que
-- les cloner et changer leurs propriétés (position, taille, transparence) et appeler :Emit().
--
-- Contrat lu par client/Controllers/WeaponFX.luau :
--   Assets.FX.Weapons.<WeaponId>.<Rôle>, Assets.FX.Special.<Nom>.<Rôle>, Assets.FX.Shared.<Rôle> : Model.
--   Rôles : Projectile, Impact, Area, Cone, Segment, Aura, Orbit, Turret, Fall, Telegraph.
--   Attributs du Model : Kind, Life (s), Height (studs au-dessus du sol).
--   « Anchor » (Part invisible, PrimaryPart) porte les Attachments, Trails, émetteurs et lumières qui suivent.
--   Formes (MeshPart, Neon) : S (taille = Base x rayon x S), Base (taille pour un rayon de 1), C (centre pour
--   un rayon de 1), Fade0 / Fade1 (transparence au début / à la fin), Grow (taille de départ, 0..1),
--   Seg (segment du croissant), Spin (rad/s), Life (vie propre, s).
--   « Zone » (Part invisible) : S ; ses ParticleEmitter (forme Disc) remplissent la zone.
--   ParticleEmitter : Burst (nombre émis au départ), PerRadius (le nombre suit le rayon / 5),
--   Continuous (allumé pendant la vie).
--   Pièce (Model cloné de Assets.Weapons, soudé à Anchor) : attribut Piece = nom, Offset (CFrame).
--   PointLight : HighOnly (allumée en qualité Haute seulement).
local RS = game:GetService("ReplicatedStorage")

local ARC_SEGMENTS = 9
local ARC_CENTERS = {
	FX_ArcHalo1 = Vector3.new(0.8889, 0.0, -0.154),
	FX_ArcHalo2 = Vector3.new(0.7302, 0.0, -0.4195),
	FX_ArcHalo3 = Vector3.new(0.5154, 0.0, -0.6123),
	FX_ArcHalo4 = Vector3.new(0.2656, 0.0, -0.7278),
	FX_ArcHalo5 = Vector3.new(-0.0, 0.0, -0.766),
	FX_ArcHalo6 = Vector3.new(-0.2656, 0.0, -0.7278),
	FX_ArcHalo7 = Vector3.new(-0.5154, 0.0, -0.6123),
	FX_ArcHalo8 = Vector3.new(-0.7302, 0.0, -0.4195),
	FX_ArcHalo9 = Vector3.new(-0.8889, 0.0, -0.154),
	FX_ArcCore1 = Vector3.new(0.9427, 0.0, -0.1651),
	FX_ArcCore2 = Vector3.new(0.8084, 0.0, -0.4659),
	FX_ArcCore3 = Vector3.new(0.5894, 0.0, -0.7016),
	FX_ArcCore4 = Vector3.new(0.3101, 0.0, -0.8513),
	FX_ArcCore5 = Vector3.new(-0.0, 0.0, -0.9026),
	FX_ArcCore6 = Vector3.new(-0.3101, 0.0, -0.8513),
	FX_ArcCore7 = Vector3.new(-0.5894, 0.0, -0.7016),
	FX_ArcCore8 = Vector3.new(-0.8084, 0.0, -0.4659),
	FX_ArcCore9 = Vector3.new(-0.9427, 0.0, -0.1651),
}

local assets = RS:WaitForChild("Assets")
local weaponsFolder = assets:WaitForChild("Weapons")

local function folder(parent: Instance, name: string): Folder
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end

local FX = folder(assets, "FX")
local SHAPES = folder(FX, "Shapes")

-- 1. Formes lisses importées (FX_Ring, FX_RingThick, FX_RingDashed, FX_Disc, FX_ArcHalo*, FX_ArcCore*)
for _, d in workspace:GetDescendants() do
	if d:IsA("MeshPart") and string.sub(d.Name, 1, 3) == "FX_" then
		local old = SHAPES:FindFirstChild(d.Name)
		if old then
			old:Destroy()
		end
		d.Anchored = true
		d.CanCollide = false
		d.CanQuery = false
		d.CanTouch = false
		d.CastShadow = false
		d.Material = Enum.Material.Neon
		d.Color = Color3.new(1, 1, 1)
		d:SetAttribute("Base", d.Size)
		if ARC_CENTERS[d.Name] then
			d:SetAttribute("C", ARC_CENTERS[d.Name])
		end
		d.Parent = SHAPES
	end
end

-- 2. Couleurs (palette COHUE) et textures intégrées à Roblox (rien à téléverser)
local C = {
	White = Color3.fromRGB(255, 248, 236), Cream = Color3.fromRGB(255, 232, 184), Gold = Color3.fromRGB(255, 194, 26),
	Ember = Color3.fromRGB(255, 122, 26), Sky = Color3.fromRGB(63, 208, 245), Royal = Color3.fromRGB(45, 107, 230),
	Grape = Color3.fromRGB(140, 82, 224), Plum = Color3.fromRGB(75, 56, 102), Leaf = Color3.fromRGB(61, 190, 74),
	Stone = Color3.fromRGB(156, 148, 136), Smoke = Color3.fromRGB(190, 184, 176), Ink = Color3.fromRGB(42, 28, 61),
	Tomato = Color3.fromRGB(230, 57, 70),
}
local TEX = {
	Glow = "rbxasset://textures/particles/forcefield_glow_main.dds",
	Spark = "rbxasset://textures/particles/sparkles_main.dds",
	FireSpark = "rbxasset://textures/particles/fire_sparks_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Shock = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
	Core = "rbxasset://textures/particles/explosion01_core_main.dds",
}

-- 3. Briques de construction
local function newModel(parent: Instance, name: string, kind: string, life: number, height: number?): Model
	local old = parent:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local m = Instance.new("Model")
	m.Name = name
	m:SetAttribute("Kind", kind)
	m:SetAttribute("Life", life)
	m:SetAttribute("Height", height or 0.08)
	local a = Instance.new("Part")
	a.Name = "Anchor"
	a.Size = Vector3.new(0.2, 0.2, 0.2)
	a.Transparency = 1
	a.Anchored = true
	a.CanCollide = false
	a.CanQuery = false
	a.CanTouch = false
	a.CastShadow = false
	a.Parent = m
	m.PrimaryPart = a
	m.Parent = parent
	return m
end

local function shape(m: Model, name: string, color: Color3, props: { [string]: any }): MeshPart
	local src = SHAPES:FindFirstChild(name)
	assert(src, "forme manquante : " .. name)
	local p = src:Clone()
	p.Color = color
	p.Transparency = props.Fade0 or 0
	if props.Matte then
		p.Material = Enum.Material.SmoothPlastic
	end
	for k, v in props do
		p:SetAttribute(k, v)
	end
	if p:GetAttribute("S") == nil then
		p:SetAttribute("S", 1)
	end
	p.Parent = m
	return p
end

local function zone(m: Model, s: number): Part
	local z = Instance.new("Part")
	z.Name = "Zone"
	z.Size = Vector3.new(2, 0.2, 2)
	z.Transparency = 1
	z.Anchored = true
	z.CanCollide = false
	z.CanQuery = false
	z.CanTouch = false
	z.CastShadow = false
	z:SetAttribute("S", s)
	z.Parent = m
	return z
end

local function emitter(parent: Instance, name: string, p: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Enabled = false
	e.Texture = p.Texture or TEX.Glow
	e.Color = ColorSequence.new(p.Color or C.White, p.Color1 or p.Color or C.White)
	e.LightEmission = p.LightEmission or 1
	e.LightInfluence = 0
	e.Brightness = p.Brightness or 2
	e.Size = p.Size or NumberSequence.new(1, 0)
	e.Transparency = p.Transparency or NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = p.Lifetime or NumberRange.new(0.3, 0.5)
	e.Speed = p.Speed or NumberRange.new(4, 8)
	e.SpreadAngle = p.Spread or Vector2.new(180, 180)
	e.Rate = p.Rate or 0
	e.Rotation = p.Rotation or NumberRange.new(0, 360)
	e.RotSpeed = p.RotSpeed or NumberRange.new(-90, 90)
	e.Drag = p.Drag or 2
	e.Acceleration = p.Acceleration or Vector3.zero
	e.ZOffset = p.ZOffset or 0
	if p.Shape then
		e.Shape = p.Shape
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	end
	if p.Orientation then
		e.Orientation = p.Orientation
	end
	if p.Squash then
		e.Squash = p.Squash
	end
	e:SetAttribute("Burst", p.Burst or 0)
	e:SetAttribute("PerRadius", p.PerRadius == true)
	e:SetAttribute("Continuous", p.Continuous == true)
	e.Parent = parent
	return e
end

local function light(parent: Instance, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Enabled = false
	l:SetAttribute("HighOnly", true)
	l.Parent = parent
end

local function trail(anchor: BasePart, color: Color3, width: number, life: number, color1: Color3?)
	local a0 = Instance.new("Attachment")
	a0.Name = "T0"
	a0.Position = Vector3.new(0, width / 2, 0)
	a0.Parent = anchor
	local a1 = Instance.new("Attachment")
	a1.Name = "T1"
	a1.Position = Vector3.new(0, -width / 2, 0)
	a1.Parent = anchor
	local t = Instance.new("Trail")
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Color = ColorSequence.new(color, color1 or color)
	t.LightEmission = 1
	t.LightInfluence = 0
	t.Lifetime = life
	t.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	t.WidthScale = NumberSequence.new(1, 0.1)
	t.FaceCamera = true
	t.Enabled = false
	t.Parent = anchor
	return t
end

-- Orientation d'une pièce : son axe « pointe » vers l'avant (-Z), sa face plate vers le haut.
local FLY_UP = CFrame.fromMatrix(Vector3.zero, Vector3.new(1, 0, 0), Vector3.new(0, 0, -1))     -- pointe +Y (dague, lance)
local FLY_X = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 0, -1), Vector3.new(-1, 0, 0))     -- pointe +X (flèche, carreau)
local FLAT = FLY_UP                                                                              -- pièce à plat (hache, lame, boomerang)
local UPRIGHT = CFrame.new()                                                                     -- face à la caméra (bombe, météore, tourelle)

local function piece(m: Model, pieceName: string, offset: CFrame, scale: number?)
	local src = weaponsFolder:FindFirstChild(pieceName)
	assert(src, "pièce manquante dans Assets.Weapons : " .. pieceName)
	local p = src:Clone()
	p.Name = "Piece"
	if scale and scale ~= 1 then
		p:ScaleTo(scale)
	end
	p:SetAttribute("Piece", pieceName)
	p:SetAttribute("Offset", offset)
	p:PivotTo(m.PrimaryPart.CFrame * offset)
	for _, part in p:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.Massless = true
			local w = Instance.new("WeldConstraint")
			w.Part0 = m.PrimaryPart
			w.Part1 = part
			w.Parent = part
		end
	end
	p.Parent = m
	return p
end

-- 4. Recettes d'effets
local function impact(parent: Instance, name: string, color: Color3, n: number)
	local m = newModel(parent, name, "impact", 0.45, 2.4)
	emitter(m.PrimaryPart, "Flare", { Texture = TEX.Glow, Color = C.White, Burst = 1, Size = NumberSequence.new(2.4, 0),
		Speed = NumberRange.new(0), Lifetime = NumberRange.new(0.15, 0.2) })
	emitter(m.PrimaryPart, "Sparks", { Texture = TEX.Spark, Color = color, Burst = n, Size = NumberSequence.new(0.6, 0),
		Speed = NumberRange.new(8, 14), Lifetime = NumberRange.new(0.2, 0.35) })
	return m
end

local function projectile(parent: Instance, pieceName: string?, offset: CFrame, trailColor: Color3, opts)
	opts = opts or {}
	local m = newModel(parent, "Projectile", "projectile", 0, opts.height or 2.5)
	if pieceName then
		piece(m, pieceName, offset, opts.scale)
	end
	local t = trail(m.PrimaryPart, trailColor, opts.trailWidth or 0.5, opts.trailLife or 0.18, opts.trailColor1)
	t:SetAttribute("Trail", true)
	if opts.glow then
		emitter(m.PrimaryPart, "Glow", { Texture = TEX.Glow, Color = opts.glow, Rate = 30, Continuous = true,
			Size = NumberSequence.new(opts.glowSize or 2.2, 0.4), Speed = NumberRange.new(0), Lifetime = NumberRange.new(0.12, 0.16) })
	end
	if opts.fire then
		emitter(m.PrimaryPart, "Fire", { Texture = TEX.Fire, Color = opts.fire, Color1 = C.Ember, Rate = 40, Continuous = true,
			Size = NumberSequence.new(1.4, 0.2), Speed = NumberRange.new(0.5, 1.5), Lifetime = NumberRange.new(0.2, 0.35) })
		light(m.PrimaryPart, C.Ember, 10, 2)
	end
	if opts.spin then
		m:SetAttribute("Spin", opts.spin)
	end
	return m
end

local function ringBurst(parent: Instance, name: string, kind: string, color: Color3, opts)
	-- onde au sol : anneau épais qui grandit et s'efface, disque clair, étincelles, fumée, lumière
	opts = opts or {}
	local m = newModel(parent, name, kind, opts.life or 0.5, 0.08)
	shape(m, opts.ring or "FX_RingThick", color, { S = 1, Grow = opts.grow or 0.35, Fade0 = 0, Fade1 = 1 })
	if opts.fill ~= false then
		shape(m, "FX_Disc", opts.fillColor or color, { S = 0.98, Grow = 0.6, Fade0 = opts.fillAlpha or 0.75, Fade1 = 1 })
	end
	local z = zone(m, opts.zoneS or 0.7)
	if opts.flash then
		emitter(z, "Flash", { Texture = TEX.Glow, Color = C.White, Burst = 1, Size = NumberSequence.new(opts.flash, 0),
			Speed = NumberRange.new(0), Lifetime = NumberRange.new(0.18, 0.22), Shape = Enum.ParticleEmitterShape.Box })
		emitter(z, "Fireball", { Texture = TEX.Core, Color = opts.core or color, Burst = 3, Size = NumberSequence.new(opts.flash * 1.4, 0),
			Speed = NumberRange.new(1, 3), Lifetime = NumberRange.new(0.3, 0.45), Shape = Enum.ParticleEmitterShape.Box })
	end
	emitter(z, "Sparks", { Texture = TEX.Spark, Color = opts.sparkColor or C.White, Color1 = color, Burst = opts.sparks or 10,
		PerRadius = true, Size = NumberSequence.new(0.7, 0), Speed = NumberRange.new(10, 18), Lifetime = NumberRange.new(0.25, 0.4),
		Spread = Vector2.new(70, 70), Shape = Enum.ParticleEmitterShape.Disc, Acceleration = Vector3.new(0, -20, 0) })
	if opts.smoke then
		emitter(z, "Smoke", { Texture = TEX.Smoke, Color = C.Smoke, LightEmission = 0, Brightness = 1, Burst = opts.smoke, PerRadius = true,
			Size = NumberSequence.new(2.5, 4), Speed = NumberRange.new(1, 3), Lifetime = NumberRange.new(0.6, 0.9),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }),
			Shape = Enum.ParticleEmitterShape.Disc, Acceleration = Vector3.new(0, 3, 0) })
	end
	if opts.burn then
		local b = zone(m, 0.85)
		b.Name = "Burn"
		b:SetAttribute("Life", opts.burn)
		emitter(b, "Flames", { Texture = TEX.Fire, Color = C.Gold, Color1 = C.Ember, Rate = 18, Continuous = true,
			Size = NumberSequence.new(1.2, 0.2), Speed = NumberRange.new(1, 2), Lifetime = NumberRange.new(0.35, 0.5),
			Spread = Vector2.new(10, 10), Shape = Enum.ParticleEmitterShape.Disc, Acceleration = Vector3.new(0, 4, 0) })
		m:SetAttribute("Life", math.max(m:GetAttribute("Life"), opts.burn))
	end
	if opts.lingerDisc then
		shape(m, "FX_Disc", opts.lingerDisc, { S = 0.95, Grow = 1, Fade0 = 0.6, Fade1 = 1, Life = opts.lingerLife or 1 })
		m:SetAttribute("Life", math.max(m:GetAttribute("Life"), opts.lingerLife or 1))
	end
	light(m.PrimaryPart, color, 16, opts.lightBrightness or 3)
	return m
end

local function swing(parent: Instance)
	-- croissant du coup de taille : 9 segments (halo Sky, cœur blanc), le code en montre 7 pour 140°
	local m = newModel(parent, "Cone", "cone", 0.3, 2.6)
	for i = 1, ARC_SEGMENTS do
		shape(m, "FX_ArcHalo" .. i, C.Sky, { S = 1, Seg = i, Fade0 = 0.35, Fade1 = 1, C = ARC_CENTERS["FX_ArcHalo" .. i] })
		shape(m, "FX_ArcCore" .. i, C.White, { S = 1, Seg = i, Fade0 = 0, Fade1 = 1, C = ARC_CENTERS["FX_ArcCore" .. i] })
	end
	local z = zone(m, 0.9)
	emitter(z, "Sparks", { Texture = TEX.Spark, Color = C.White, Color1 = C.Sky, Burst = 10, PerRadius = true,
		Size = NumberSequence.new(0.6, 0), Speed = NumberRange.new(10, 16), Lifetime = NumberRange.new(0.2, 0.3),
		Spread = Vector2.new(40, 40), Shape = Enum.ParticleEmitterShape.Disc })
	return m
end

local function segment(parent: Instance, color: Color3, coreWidth: number, glowWidth: number)
	-- éclair : 3 rayons blancs fins et 3 halos colorés entre P0..P3 ; le code décale P1 et P2 en zigzag
	local m = newModel(parent, "Segment", "segment", 0.16, 2.5)
	local a = m.PrimaryPart
	local pts = {}
	for i = 0, 3 do
		local at = Instance.new("Attachment")
		at.Name = "P" .. i
		at.Parent = a
		pts[i] = at
	end
	for i = 1, 3 do
		for _, spec in { { "Glow", color, glowWidth, 0.35 }, { "Core", C.White, coreWidth, 0 } } do
			local b = Instance.new("Beam")
			b.Name = spec[1] .. i
			b.Attachment0 = pts[i - 1]
			b.Attachment1 = pts[i]
			b.Color = ColorSequence.new(spec[2])
			b.Width0 = spec[3]
			b.Width1 = spec[3]
			b.LightEmission = 1
			b.LightInfluence = 0
			b.FaceCamera = true
			b.Transparency = NumberSequence.new(spec[4])
			b.Segments = 1
			b.Parent = a
		end
	end
	local tip = Instance.new("Attachment")
	tip.Name = "Tip"
	tip.Parent = a
	emitter(tip, "Flare", { Texture = TEX.Glow, Color = C.White, Color1 = color, Burst = 1, Size = NumberSequence.new(2.2, 0),
		Speed = NumberRange.new(0), Lifetime = NumberRange.new(0.12, 0.16) })
	emitter(tip, "Sparks", { Texture = TEX.Spark, Color = color, Burst = 5, Size = NumberSequence.new(0.5, 0),
		Speed = NumberRange.new(8, 12), Lifetime = NumberRange.new(0.15, 0.25) })
	return m
end

local function aura(parent: Instance, color: Color3)
	local m = newModel(parent, "Aura", "aura", 0, 0.1)
	shape(m, "FX_Disc", color, { S = 1, Fade0 = 0.8, Fade1 = 0.8 })
	shape(m, "FX_Ring", color, { S = 1, Fade0 = 0.1, Fade1 = 0.1, Pulse = 0.5 })
	local z = zone(m, 0.85)
	emitter(z, "Motes", { Texture = TEX.Spark, Color = C.Cream, Color1 = color, Rate = 6, Continuous = true,
		Size = NumberSequence.new(0.6, 0), Speed = NumberRange.new(1, 2), Lifetime = NumberRange.new(0.6, 1),
		Spread = Vector2.new(10, 10), Shape = Enum.ParticleEmitterShape.Disc, Acceleration = Vector3.new(0, 3, 0) })
	return m
end

local function orbit(parent: Instance, pieceName: string, trailColor: Color3, scale: number?)
	local m = newModel(parent, "Orbit", "orbit", 0, 2)
	piece(m, pieceName, FLAT, scale)
	local t = trail(m.PrimaryPart, trailColor, 0.6, 0.12)
	t:SetAttribute("Trail", true)
	return m
end

local function telegraph(parent: Instance)
	-- alerte du joueur : anneau Gold en pointillé, disque doré qui se remplit, bord blanc ; jamais coupé
	local m = newModel(parent, "Telegraph", "telegraph", 0, 0.06)
	shape(m, "FX_Ring", C.Ink, { S = 1.03, Fade0 = 0.55, Fade1 = 0.55, Matte = true })
	shape(m, "FX_RingDashed", C.Gold, { S = 1, Fade0 = 0, Fade1 = 0, Spin = 0.6 })
	shape(m, "FX_Disc", C.Gold, { S = 1, Fade0 = 0.88, Fade1 = 0.88 })
	shape(m, "FX_Disc", C.Gold, { S = 1, Fill = true, Fade0 = 0.75, Fade1 = 0.6 })
	shape(m, "FX_Ring", C.White, { S = 1, Fill = true, Fade0 = 0.1, Fade1 = 0 })
	return m
end

local function fall(parent: Instance, pieceName: string, scale: number?, glow: Color3?)
	-- pièce qui tombe du ciel pendant le télégraphe (météore, bombe)
	local m = newModel(parent, "Fall", "fall", 0, 0.8)
	piece(m, pieceName, UPRIGHT, scale)
	local t = trail(m.PrimaryPart, glow or C.Ember, 1.2, 0.25, C.Gold)
	t:SetAttribute("Trail", true)
	if glow then
		emitter(m.PrimaryPart, "Glow", { Texture = TEX.Fire, Color = C.Gold, Color1 = glow, Rate = 30, Continuous = true,
			Size = NumberSequence.new(2.4, 0.4), Speed = NumberRange.new(0.5, 1), Lifetime = NumberRange.new(0.15, 0.25) })
	end
	return m
end

-- 5. Les effets des 16 armes
local W = folder(FX, "Weapons")
local function weapon(id: string): Folder
	return folder(W, id)
end

swing(weapon("Broadsword"))

projectile(weapon("Longbow"), "Arrow", FLY_X, C.Cream, { trailWidth = 0.35 })
impact(weapon("Longbow"), "Impact", C.Leaf, 6)

projectile(weapon("FireStaff"), nil, CFrame.new(), C.Ember, { glow = C.Gold, fire = C.Gold, trailWidth = 1.1, trailLife = 0.25, trailColor1 = C.Ember })
ringBurst(weapon("FireStaff"), "Area", "area", C.Ember, { flash = 4, smoke = 6, sparks = 14, burn = 2, core = C.Gold })

ringBurst(weapon("QuakeHammer"), "Area", "area", C.Cream, { grow = 0.15, smoke = 10, sparks = 8, fillAlpha = 0.85, life = 0.45 })

projectile(weapon("ThrowingDaggers"), "ThrowingDaggers", FLY_UP, C.Grape, { trailWidth = 0.3, scale = 0.6 })
impact(weapon("ThrowingDaggers"), "Impact", C.White, 5)

aura(weapon("HolyAura"), C.Gold)

orbit(weapon("SpinningAxes"), "SpinningAxes", C.Cream, 0.7)

ringBurst(weapon("BeastWhip"), "Area", "area", C.Ember, { ring = "FX_Ring", grow = 0.6, fill = false, sparks = 12, sparkColor = C.Gold, life = 0.3 })

segment(weapon("LightningChain"), C.Sky, 0.18, 0.9)

ringBurst(weapon("FrostNova"), "Area", "area", C.Sky, { grow = 0.2, sparks = 16, sparkColor = C.White, fillColor = C.White, lingerDisc = C.Sky, lingerLife = 1 })

projectile(weapon("Boomerang"), "Boomerang", FLAT, C.Gold, { spin = 18, trailWidth = 0.8, scale = 0.8 })

telegraph(folder(FX, "Shared"))
fall(weapon("BombBag"), "Bomb", 1)
ringBurst(weapon("BombBag"), "Area", "area", C.Ember, { flash = 5, smoke = 8, sparks = 16, core = C.Gold })

projectile(weapon("SpearThrow"), "SpearThrow", FLY_UP, C.Cream, { trailWidth = 0.45 })
impact(weapon("SpearThrow"), "Impact", C.White, 6)

fall(weapon("MeteorRain"), "MeteorRain", 1.2, C.Ember)
ringBurst(weapon("MeteorRain"), "Area", "area", C.Ember, { flash = 6, smoke = 10, sparks = 20, burn = 2, core = C.Gold })

orbit(weapon("OrbitingBlades"), "OrbitingBlades", C.Sky, 0.45)

do
	local t = newModel(weapon("CrossbowTurret"), "Turret", "turret", 0, 0)
	piece(t, "CrossbowTurret", UPRIGHT, 0.9)
	emitter(t.PrimaryPart, "Dust", { Texture = TEX.Smoke, Color = C.Smoke, LightEmission = 0, Brightness = 1, Burst = 8,
		Size = NumberSequence.new(1.6, 2.6), Speed = NumberRange.new(3, 5), Lifetime = NumberRange.new(0.4, 0.6),
		Spread = Vector2.new(80, 80) })
end
projectile(weapon("CrossbowTurret"), "Bolt", FLY_X, C.Cream, { trailWidth = 0.3 })
impact(weapon("CrossbowTurret"), "Impact", C.White, 4)

-- 6. Effets des passifs et des objets (Codec.Visual)
local SP = folder(FX, "Special")
ringBurst(folder(SP, "Parry"), "Area", "area", C.Royal, { ring = "FX_Ring", grow = 0.5, fill = false, sparks = 8, sparkColor = C.White, life = 0.3 })
do
	local m = newModel(folder(SP, "Blessing"), "Area", "area", 0.8, 0.1)
	local z = zone(m, 0.8)
	emitter(z, "Crosses", { Texture = TEX.Spark, Color = C.Gold, Color1 = C.Cream, Burst = 8, Size = NumberSequence.new(0.9, 0),
		Speed = NumberRange.new(2, 4), Lifetime = NumberRange.new(0.6, 0.8), Spread = Vector2.new(10, 10),
		Shape = Enum.ParticleEmitterShape.Disc, Acceleration = Vector3.new(0, 4, 0) })
end
projectile(folder(SP, "Ghost"), nil, CFrame.new(), C.Cream, { glow = C.White, glowSize = 2.6, trailWidth = 1.2, trailLife = 0.3 })
ringBurst(folder(SP, "Whistle"), "Area", "area", C.White, { ring = "FX_Ring", grow = 0.2, fill = false, sparks = 6, life = 0.4 })
ringBurst(folder(SP, "Megaphone"), "Area", "area", C.Gold, { ring = "FX_Ring", grow = 0.2, fillAlpha = 0.9, sparks = 10, life = 0.4 })
ringBurst(folder(SP, "Thorns"), "Area", "area", C.Stone, { ring = "FX_RingThick", grow = 0.3, fill = false, sparks = 8, sparkColor = C.Cream, life = 0.3 })
do
	local m = newModel(folder(SP, "Shadowstep"), "Area", "area", 0.6, 0.1)
	local z = zone(m, 0.6)
	emitter(z, "Smoke", { Texture = TEX.Smoke, Color = C.Plum, Color1 = C.Grape, LightEmission = 0.3, Burst = 10,
		Size = NumberSequence.new(2, 3.4), Speed = NumberRange.new(2, 4), Lifetime = NumberRange.new(0.4, 0.6),
		Shape = Enum.ParticleEmitterShape.Disc, Acceleration = Vector3.new(0, 4, 0) })
end
segment(folder(SP, "ChainBolt"), C.Gold, 0.14, 0.7)
ringBurst(folder(SP, "MiniBomb"), "Area", "area", C.Ember, { flash = 2.5, smoke = 3, sparks = 8, core = C.Gold, life = 0.35 })

print("A14 : effets posés dans ReplicatedStorage.Assets.FX (Weapons, Special, Shared, Shapes)")
