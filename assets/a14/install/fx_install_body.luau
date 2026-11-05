--!nocheck
-- A14 : construit les modèles d'effets des armes dans ReplicatedStorage.Assets.FX (généré par
-- assets/a14/make_fx_install.py à partir de fx_install_body.luau). À lancer dans Studio, en mode édition,
-- APRÈS A14_weapons_install.luau (il a besoin des formes FX_* et des pièces de Assets.Weapons).
-- Effets v2 « naturels » (dossier 12, section 15, validés par Clément le 5 nov.) : particules douces à
-- textures intégrées à Roblox, rubans en Beam et Trail ; plus de pièces en pixels pour les projectiles rapides.
-- Relançable : il vide Weapons, Special, Shared et Enemies puis les reconstruit ; Shapes est gardé.
-- Règle « rien construit par script » : ces objets sont posés une fois dans la place ; WeaponFX ne fait que
-- les cloner et changer leurs propriétés (position, taille, transparence) et appeler :Emit().
--
-- Contrat lu par client/Controllers/WeaponFX.luau :
--   Assets.FX.Weapons.<WeaponId>.<Rôle>, Assets.FX.Special.<Nom>.<Rôle>, Assets.FX.Shared.<Rôle> : Model.
--   Rôles : Projectile, Impact, Area, Cone, Segment, Aura, Orbit, Turret, Fall, Telegraph.
--   Attributs du Model : Kind, Life (s), Height (studs au-dessus du sol), Spin (rad/s), Tilt (degrés, Cone).
--   « Anchor » (Part invisible, PrimaryPart) : posé au centre de l'effet ; porte les Attachments, Trails,
--   Beams, émetteurs et lumières.
--   Formes (MeshPart, Neon) : S (taille = Base x rayon x S), Base (taille pour un rayon de 1), C (centre pour
--   un rayon de 1), Fade0 / Fade1 (transparence au début / à la fin), Grow (taille de départ, 0..1),
--   Spin (rad/s), Life (vie propre, s), Fill (suit le remplissage de l'alerte), Shrink (se resserre de
--   Shrink x remplissage), Pulse (période, s).
--   « Zone » ou « Burn » (Part invisible) : S, Life ; ses ParticleEmitter (forme Disc) remplissent la zone.
--   Beams du coup d'épée (Cone) : attribut Layer (Halo, Glow, Edge, Core), Seg (1..3), W (largeur max, studs),
--   T (transparence) ; Attachments S0..S3 sur Anchor (S0 = départ du geste, S3 = tête).
--   Éclair (Segment) : Attachments P0..Pn et Tip ; Beams Glow<i> et Core<i> entre P(i-1) et P(i).
--   ParticleEmitter : Burst (nombre émis au départ), PerRadius (le nombre suit le rayon / 5),
--   Continuous (allumé pendant la vie), SizeR (la taille est en rayons : le code la multiplie par le rayon).
--   Pièce (Model cloné de Assets.Weapons, soudé à Anchor) : attribut Piece = nom, Offset (CFrame).
--   PointLight : HighOnly (allumée en qualité Haute seulement).
local RS = game:GetService("ReplicatedStorage")

-- @@DATA@@

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
local nodes: { [Instance]: boolean } = {}
for _, d in workspace:GetDescendants() do
	if d:IsA("MeshPart") and string.sub(d.Name, 1, 3) == "FX_" then
		if d.Parent and d.Parent ~= workspace then
			nodes[d.Parent] = true
		end
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
-- ménage de l'Import 3D : les Models "<Nom>_Node" vidés, puis le Model "Scene" s'il ne contient plus rien
local parents: { [Instance]: boolean } = {}
for n in nodes do
	if n.Parent and #n:GetDescendants() == 0 then
		if n.Parent ~= workspace then
			parents[n.Parent] = true
		end
		n:Destroy()
	end
end
for p in parents do
	if p.Parent and p:IsA("Model") and #p:GetDescendants() == 0 then
		p:Destroy()
	end
end

-- La v2 remplace tous les modèles d'effets (les formes restent)
for _, name in { "Weapons", "Special", "Shared", "Enemies" } do
	local old = FX:FindFirstChild(name)
	if old then
		old:Destroy()
	end
end

-- 2. Couleurs (palette COHUE) et textures intégrées à Roblox (rien à téléverser)
local C = {
	White = Color3.fromRGB(255, 248, 236), Cream = Color3.fromRGB(255, 232, 184), Gold = Color3.fromRGB(255, 194, 26),
	Amber = Color3.fromRGB(255, 176, 32), Butter = Color3.fromRGB(255, 226, 122), Ember = Color3.fromRGB(255, 122, 26),
	Sky = Color3.fromRGB(60, 200, 255), Ice = Color3.fromRGB(143, 227, 255), Frost = Color3.fromRGB(191, 239, 255),
	Royal = Color3.fromRGB(45, 107, 230), Grape = Color3.fromRGB(140, 82, 224), Lilac = Color3.fromRGB(192, 140, 255),
	Plum = Color3.fromRGB(75, 56, 102), Teal = Color3.fromRGB(46, 240, 192), Stone = Color3.fromRGB(156, 148, 136),
	Smoke = Color3.fromRGB(190, 184, 176), Ash = Color3.fromRGB(110, 106, 100), Dust = Color3.fromRGB(196, 170, 130),
}
local TEX = {
	Glow = "rbxasset://textures/particles/explosion01_implosion_main.dds", -- lueur ronde et douce
	Core = "rbxasset://textures/particles/explosion01_core_main.dds", -- boule de feu
	Shock = "rbxasset://textures/particles/explosion01_shockwave_main.dds", -- onde de choc (anneau doux)
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
}
local SHOCK_R = 1 / 0.29 -- l'anneau de la texture d'onde de choc est à 0,29 de sa largeur

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

local function seq(a: number, b: number?): NumberSequence
	return NumberSequence.new(a, b or a)
end

local function fade(a: number, b: number?): NumberSequence
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b or 1) })
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
	e.Size = p.Size or seq(1, 0)
	e.Transparency = p.Transparency or fade(0.1, 1)
	e.Lifetime = p.Lifetime or NumberRange.new(0.3, 0.5)
	e.Speed = p.Speed or NumberRange.new(4, 8)
	e.SpreadAngle = p.Spread or Vector2.new(180, 180)
	e.Rate = p.Rate or 0
	e.Rotation = p.Rotation or NumberRange.new(0, 360)
	e.RotSpeed = p.RotSpeed or NumberRange.new(-60, 60)
	e.Drag = p.Drag or 2
	e.Acceleration = p.Acceleration or Vector3.zero
	e.ZOffset = p.ZOffset or 0
	e.LockedToPart = p.Locked == true
	if p.Shape then
		e.Shape = p.Shape
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	end
	if p.Flat then
		-- posée à plat au sol : vitesse minuscule vers le haut, particule perpendiculaire à sa vitesse
		e.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
		e.EmissionDirection = Enum.NormalId.Top
		e.Speed = NumberRange.new(0.01)
		e.SpreadAngle = Vector2.zero
		e.Drag = 0
		e.Acceleration = Vector3.zero
		e.RotSpeed = NumberRange.new(-20, 20)
	elseif p.Streak then
		-- étincelle étirée dans le sens du mouvement
		e.Orientation = Enum.ParticleOrientation.VelocityParallel
		e.Squash = seq(p.Squash or 1.6)
		e.Rotation = NumberRange.new(0)
		e.RotSpeed = NumberRange.new(0)
	end
	e:SetAttribute("Burst", p.Burst or 0)
	e:SetAttribute("PerRadius", p.PerRadius == true)
	e:SetAttribute("Continuous", p.Continuous == true)
	e:SetAttribute("SizeR", p.SizeR == true)
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

local function trail(anchor: BasePart, tag: string, color: Color3, width: number, life: number, t0: number, color1: Color3?)
	local a0 = Instance.new("Attachment")
	a0.Name = "T0" .. tag
	a0.Position = Vector3.new(0, width / 2, 0)
	a0.Parent = anchor
	local a1 = Instance.new("Attachment")
	a1.Name = "T1" .. tag
	a1.Position = Vector3.new(0, -width / 2, 0)
	a1.Parent = anchor
	local t = Instance.new("Trail")
	t.Name = "Trail" .. tag
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Color = ColorSequence.new(color, color1 or color)
	t.LightEmission = 1
	t.LightInfluence = 0
	t.Lifetime = life
	t.Transparency = fade(t0, 1)
	t.WidthScale = NumberSequence.new(1, 0)
	t.FaceCamera = true
	t.Enabled = false
	t:SetAttribute("Trail", true)
	t.Parent = anchor
	return t
end

-- Traînée douce : un ruban large et peu opaque, un cœur fin et clair
local function softTrail(anchor: BasePart, color: Color3, width: number, life: number)
	trail(anchor, "Glow", color, width, life, 0.45)
	trail(anchor, "Core", C.White, width * 0.32, life * 0.7, 0.05, color)
end

-- Orientation d'une pièce : son axe « pointe » vers l'avant (-Z), sa face plate vers le haut.
local FLY_UP = CFrame.fromMatrix(Vector3.zero, Vector3.new(1, 0, 0), Vector3.new(0, 0, -1))     -- pointe +Y
local FLAT = FLY_UP                                                                              -- pièce à plat
local UPRIGHT = CFrame.new()                                                                     -- face caméra

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
	-- éclair blanc, halo coloré, étincelles étirées
	local m = newModel(parent, name, "impact", 0.4, 2.4)
	local a = m.PrimaryPart
	emitter(a, "Flash", { Color = C.White, Burst = 1, Size = seq(2.6, 0.4), Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.12, 0.16), Transparency = fade(0, 1) })
	emitter(a, "Halo", { Color = color, Burst = 1, Size = seq(3.8, 1.0), Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.18, 0.22), Transparency = fade(0.35, 1) })
	emitter(a, "Sparks", { Color = C.White, Color1 = color, Burst = n, Size = seq(0.45, 0), Streak = true,
		Speed = NumberRange.new(10, 18), Lifetime = NumberRange.new(0.16, 0.28), Acceleration = Vector3.new(0, -18, 0) })
	return m
end

local function lightShot(parent: Instance, color: Color3, width: number, trailLife: number)
	-- projectile rapide en lumière : tête claire (deux lueurs collées au projectile) et traînée douce
	local m = newModel(parent, "Projectile", "projectile", 0, 2.5)
	local a = m.PrimaryPart
	emitter(a, "Head", { Color = color, Rate = 60, Continuous = true, Locked = true, Size = seq(width * 2.6, width * 1.6),
		Speed = NumberRange.new(0), Lifetime = NumberRange.new(0.08, 0.1), Transparency = fade(0.25, 1) })
	emitter(a, "HeadCore", { Color = C.White, Rate = 60, Continuous = true, Locked = true, Size = seq(width * 1.2, width * 0.8),
		Speed = NumberRange.new(0), Lifetime = NumberRange.new(0.06, 0.08), Transparency = fade(0, 1) })
	softTrail(a, color, width, trailLife)
	return m
end

local function pieceShot(parent: Instance, pieceName: string, offset: CFrame, color: Color3, opts)
	-- objet lancé en pixel art (boomerang) : la pièce, une lueur douce derrière, une traînée
	opts = opts or {}
	local m = newModel(parent, "Projectile", "projectile", 0, opts.height or 2.5)
	piece(m, pieceName, offset, opts.scale)
	emitter(m.PrimaryPart, "Glow", { Color = color, Rate = 30, Continuous = true, Locked = true, Size = seq(opts.glow or 3, 1.5),
		Speed = NumberRange.new(0), Lifetime = NumberRange.new(0.1, 0.12), Transparency = fade(0.55, 1) })
	softTrail(m.PrimaryPart, color, opts.trailWidth or 0.9, opts.trailLife or 0.2)
	if opts.spin then
		m:SetAttribute("Spin", opts.spin)
	end
	return m
end

local function fireball(parent: Instance)
	-- boule de feu : tête très claire, flammes qui traînent, fumée légère, ruban chaud
	local m = newModel(parent, "Projectile", "projectile", 0, 2.5)
	local a = m.PrimaryPart
	emitter(a, "Head", { Color = C.Butter, Rate = 50, Continuous = true, Locked = true, Size = seq(4, 2.4),
		Speed = NumberRange.new(0), Lifetime = NumberRange.new(0.08, 0.1), Transparency = fade(0.2, 1) })
	emitter(a, "HeadCore", { Color = C.White, Rate = 50, Continuous = true, Locked = true, Size = seq(1.8, 1.2),
		Speed = NumberRange.new(0), Lifetime = NumberRange.new(0.06, 0.08), Transparency = fade(0, 1) })
	emitter(a, "Flames", { Texture = TEX.Core, Color = C.Butter, Color1 = C.Amber, LightEmission = 0.7, Rate = 45,
		Continuous = true, Size = seq(2.2, 0.6), Speed = NumberRange.new(0.5, 1.5), Lifetime = NumberRange.new(0.22, 0.36),
		Transparency = fade(0.1, 1), RotSpeed = NumberRange.new(-120, 120) })
	emitter(a, "Smoke", { Texture = TEX.Smoke, Color = C.Smoke, Color1 = C.Ash, LightEmission = 0, Brightness = 1, Rate = 10,
		Continuous = true, Size = seq(1.4, 2.6), Speed = NumberRange.new(0.5, 1), Lifetime = NumberRange.new(0.5, 0.8),
		Transparency = fade(0.6, 1), Acceleration = Vector3.new(0, 2, 0) })
	softTrail(a, C.Amber, 1.6, 0.22)
	light(a, C.Amber, 12, 2)
	return m
end

local function explosion(parent: Instance, name: string, opts)
	-- explosion : onde de choc posée au sol, éclair, boules de feu qui gonflent, fumée, braises ; jamais de rouge
	opts = opts or {}
	local m = newModel(parent, name, "area", opts.life or 0.55, 0.08)
	local a = m.PrimaryPart
	local hot, warm = opts.hot or C.Butter, opts.warm or C.Amber
	emitter(a, "Shock", { Texture = TEX.Shock, Flat = true, Color = warm, Burst = 2, SizeR = true,
		Size = seq(0.3 * SHOCK_R, 1.05 * SHOCK_R), Lifetime = NumberRange.new(0.32, 0.36), Transparency = fade(0, 1), Brightness = 3 })
	emitter(a, "Flash", { Color = C.White, Burst = 1, SizeR = true, Size = seq(1.1, 0.2), Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.14, 0.16), Transparency = fade(0, 1) })
	local z = zone(m, 0.5)
	emitter(z, "Fireballs", { Texture = TEX.Core, Color = hot, Color1 = warm, LightEmission = 0.7, Burst = opts.fire or 7,
		PerRadius = true, SizeR = true, Size = seq(0.45, 0.9), Speed = NumberRange.new(2, 5), Spread = Vector2.new(60, 60),
		Lifetime = NumberRange.new(0.35, 0.55), Transparency = fade(0.05, 1), Acceleration = Vector3.new(0, 6, 0),
		RotSpeed = NumberRange.new(-90, 90), Shape = Enum.ParticleEmitterShape.Disc })
	if opts.smoke ~= false then
		emitter(z, "Smoke", { Texture = TEX.Smoke, Color = C.Smoke, Color1 = C.Ash, LightEmission = 0, Brightness = 1,
			Burst = opts.smoke or 5, PerRadius = true, SizeR = true, Size = seq(0.5, 0.95), Speed = NumberRange.new(2, 4),
			Spread = Vector2.new(40, 40), Lifetime = NumberRange.new(0.9, 1.3), Transparency = fade(0.45, 1),
			Acceleration = Vector3.new(0, 3, 0), Shape = Enum.ParticleEmitterShape.Disc })
	end
	emitter(z, "Embers", { Color = hot, Color1 = C.White, Burst = opts.embers or 12, PerRadius = true, Streak = true,
		Size = seq(0.4, 0), Speed = NumberRange.new(14, 22), Spread = Vector2.new(75, 75), Lifetime = NumberRange.new(0.3, 0.5),
		Acceleration = Vector3.new(0, -25, 0), Shape = Enum.ParticleEmitterShape.Disc })
	if opts.burn then
		local b = zone(m, 0.8)
		b.Name = "Burn"
		b:SetAttribute("Life", opts.burn)
		emitter(b, "Flames", { Texture = TEX.Fire, Color = C.Gold, Color1 = C.Ember, Rate = 18, Continuous = true,
			Size = seq(1.4, 0.2), Speed = NumberRange.new(1, 2), Lifetime = NumberRange.new(0.35, 0.5),
			Spread = Vector2.new(10, 10), Shape = Enum.ParticleEmitterShape.Disc, Acceleration = Vector3.new(0, 4, 0) })
		m:SetAttribute("Life", math.max(m:GetAttribute("Life"), opts.burn))
	end
	light(a, warm, 18, opts.lightBrightness or 3)
	return m
end

local function wave(parent: Instance, name: string, color: Color3, opts)
	-- onde : onde de choc douce au sol (une ou deux), éclair, poussière ou étincelles selon l'arme
	opts = opts or {}
	local m = newModel(parent, name, "area", opts.life or 0.45, 0.08)
	local a = m.PrimaryPart
	emitter(a, "Shock", { Texture = TEX.Shock, Flat = true, Color = color, Burst = opts.shocks or 2, SizeR = true,
		Size = seq((opts.grow or 0.25) * SHOCK_R, 1.05 * SHOCK_R), Lifetime = NumberRange.new(0.3, 0.34),
		Transparency = fade(0, 1), Brightness = 3 })
	if opts.flash then
		emitter(a, "Flash", { Color = C.White, Burst = 1, SizeR = true, Size = seq(opts.flash, 0.2), Speed = NumberRange.new(0),
			Lifetime = NumberRange.new(0.12, 0.15), Transparency = fade(0.1, 1) })
	end
	local z = zone(m, 0.8)
	if opts.dust then
		emitter(z, "Dust", { Texture = TEX.Smoke, Color = opts.dust, Color1 = C.Smoke, LightEmission = 0, Brightness = 1,
			Burst = 6, PerRadius = true, SizeR = true, Size = seq(0.35, 0.7), Speed = NumberRange.new(2, 4),
			Spread = Vector2.new(70, 70), Lifetime = NumberRange.new(0.6, 0.9), Transparency = fade(0.4, 1),
			Acceleration = Vector3.new(0, 2, 0), Shape = Enum.ParticleEmitterShape.Disc })
	end
	if opts.mist then
		emitter(z, "Mist", { Texture = TEX.Smoke, Color = opts.mist, Color1 = C.Frost, LightEmission = 0.4, Brightness = 1.5,
			Burst = 6, PerRadius = true, SizeR = true, Size = seq(0.3, 0.45), Speed = NumberRange.new(1, 2),
			Spread = Vector2.new(80, 80), Lifetime = NumberRange.new(0.7, 1.0), Transparency = fade(0.5, 1),
			Shape = Enum.ParticleEmitterShape.Disc })
	end
	emitter(z, "Sparks", { Color = opts.sparkColor or C.White, Color1 = color, Burst = opts.sparks or 10, PerRadius = true,
		Streak = true, Size = seq(0.4, 0), Speed = NumberRange.new(12, 20), Spread = Vector2.new(80, 80),
		Lifetime = NumberRange.new(0.22, 0.38), Acceleration = Vector3.new(0, opts.gravity or -15, 0),
		Shape = Enum.ParticleEmitterShape.Disc })
	light(a, color, 16, 2.5)
	return m
end

local function slash(parent: Instance)
	-- coup d'épée « ruban couché » : quatre couches de Beams FaceCamera (halo, lueur, bord, cœur blanc),
	-- trois segments chacune entre S0..S3 ; WeaponFX les pose sur l'arc, règle largeurs et transparences
	local m = newModel(parent, "Cone", "slash", 0.28, 2.2)
	m:SetAttribute("Tilt", 8)
	local a = m.PrimaryPart
	local at = {}
	for i = 0, 3 do
		local x = Instance.new("Attachment")
		x.Name = "S" .. i
		x.Parent = a
		at[i] = x
	end
	local layers = {
		{ "Halo", C.Sky, 9.0, 0.82 },
		{ "Glow", C.Sky, 6.0, 0.62 },
		{ "Edge", C.Ice, 3.6, 0.35 },
		{ "Core", C.White, 1.3, 0.0 },
	}
	for _, L in layers do
		for i = 1, 3 do
			local b = Instance.new("Beam")
			b.Name = L[1] .. i
			b.Attachment0 = at[i - 1]
			b.Attachment1 = at[i]
			b.Color = ColorSequence.new(L[2])
			b.LightEmission = 1
			b.LightInfluence = 0
			b.FaceCamera = true
			b.Segments = 12
			b.Width0 = L[3]
			b.Width1 = L[3]
			b.Transparency = seq(L[4])
			b.Texture = ""
			b:SetAttribute("Layer", L[1])
			b:SetAttribute("Seg", i)
			b:SetAttribute("W", L[3])
			b:SetAttribute("T", L[4])
			b.Parent = a
		end
	end
	emitter(at[3], "HeadSparks", { Color = C.White, Color1 = C.Sky, Burst = 8, Streak = true, Size = seq(0.4, 0),
		Speed = NumberRange.new(10, 16), Lifetime = NumberRange.new(0.18, 0.28), Acceleration = Vector3.new(0, -15, 0) })
	return m
end

local function segment(parent: Instance, color: Color3, points: number)
	-- éclair : n segments fins (le code les décale en zigzag), halo peu opaque + cœur blanc fin
	local m = newModel(parent, "Segment", "segment", 0.16, 2.5)
	local a = m.PrimaryPart
	local pts = {}
	for i = 0, points do
		local at = Instance.new("Attachment")
		at.Name = "P" .. i
		at.Parent = a
		pts[i] = at
	end
	for i = 1, points do
		for _, spec in { { "Glow", color, 1.4, 0.6 }, { "Core", C.White, 0.3, 0 } } do
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
			b.Transparency = seq(spec[4])
			b.Segments = 1
			b.Texture = ""
			b.Parent = a
		end
	end
	local tip = Instance.new("Attachment")
	tip.Name = "Tip"
	tip.Parent = a
	emitter(tip, "Flare", { Color = C.White, Color1 = color, Burst = 1, Size = seq(3, 0.5), Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.12, 0.16), Transparency = fade(0, 1) })
	emitter(tip, "Sparks", { Color = C.White, Color1 = color, Burst = 6, Streak = true, Size = seq(0.35, 0),
		Speed = NumberRange.new(8, 14), Lifetime = NumberRange.new(0.15, 0.25) })
	return m
end

local function aura(parent: Instance, color: Color3)
	-- aura permanente : flaque de lumière douce, anneau qui pulse, poussière lumineuse qui monte
	local m = newModel(parent, "Aura", "aura", 0, 0.1)
	shape(m, "FX_Disc", color, { S = 1, Fade0 = 0.86, Fade1 = 0.86 })
	shape(m, "FX_RingThick", color, { S = 1, Fade0 = 0.7, Fade1 = 0.7, Pulse = 0.8 })
	shape(m, "FX_Ring", C.Cream, { S = 1, Fade0 = 0.45, Fade1 = 0.45 })
	local z = zone(m, 0.85)
	emitter(z, "Motes", { Color = C.Cream, Color1 = color, Rate = 8, Continuous = true, Size = seq(0.5, 0),
		Speed = NumberRange.new(1, 2), Lifetime = NumberRange.new(0.7, 1.1), Spread = Vector2.new(10, 10),
		Shape = Enum.ParticleEmitterShape.Disc, Acceleration = Vector3.new(0, 3, 0), Transparency = fade(0.2, 1) })
	return m
end

local function orbit(parent: Instance, pieceName: string, color: Color3, scale: number?)
	-- objet en orbite (pixel art) avec une traînée douce
	local m = newModel(parent, "Orbit", "orbit", 0, 2)
	piece(m, pieceName, FLAT, scale)
	softTrail(m.PrimaryPart, color, 0.8, 0.14)
	return m
end

local function telegraph(parent: Instance)
	-- alerte du joueur : anneau or-orangé épais, un second anneau qui se resserre jusqu'à l'impact, voile léger
	local m = newModel(parent, "Telegraph", "telegraph", 0, 0.06)
	shape(m, "FX_RingThick", C.Amber, { S = 1, Fade0 = 0.35, Fade1 = 0.35 })
	shape(m, "FX_Ring", C.Butter, { S = 1, Shrink = 0.55, Fade0 = 0.2, Fade1 = 0.1 })
	shape(m, "FX_Disc", C.Amber, { S = 1, Fade0 = 0.9, Fade1 = 0.84 })
	return m
end

local function fallBomb(parent: Instance)
	-- bombe (pixel art) qui tombe pendant l'alerte : mèche lumineuse et traînée
	local m = newModel(parent, "Fall", "fall", 0, 0.8)
	piece(m, "Bomb", UPRIGHT, 1)
	emitter(m.PrimaryPart, "Fuse", { Color = C.Butter, Color1 = C.Amber, Rate = 30, Continuous = true, Size = seq(1.2, 0),
		Speed = NumberRange.new(1, 3), Lifetime = NumberRange.new(0.15, 0.25), Transparency = fade(0.1, 1) })
	softTrail(m.PrimaryPart, C.Amber, 1.0, 0.25)
	return m
end

local function fallMeteor(parent: Instance)
	-- météore : roc de feu (lueur, flammes, cœur blanc), colonne de fumée derrière
	local m = newModel(parent, "Fall", "fall", 0, 0.8)
	local a = m.PrimaryPart
	emitter(a, "Glow", { Color = C.Amber, Rate = 40, Continuous = true, Locked = true, Size = seq(6.5, 4),
		Speed = NumberRange.new(0), Lifetime = NumberRange.new(0.08, 0.1), Transparency = fade(0.3, 1) })
	emitter(a, "Core", { Color = C.White, Rate = 40, Continuous = true, Locked = true, Size = seq(2.8, 1.8),
		Speed = NumberRange.new(0), Lifetime = NumberRange.new(0.06, 0.08), Transparency = fade(0, 1) })
	emitter(a, "Flames", { Texture = TEX.Core, Color = C.Butter, Color1 = C.Gold, LightEmission = 0.7, Rate = 50,
		Continuous = true, Size = seq(3.2, 1), Speed = NumberRange.new(0.5, 2), Lifetime = NumberRange.new(0.25, 0.4),
		Transparency = fade(0.05, 1), RotSpeed = NumberRange.new(-120, 120) })
	emitter(a, "Smoke", { Texture = TEX.Smoke, Color = C.Smoke, Color1 = C.Ash, LightEmission = 0, Brightness = 1, Rate = 16,
		Continuous = true, Size = seq(2, 3.4), Speed = NumberRange.new(0.5, 1), Lifetime = NumberRange.new(0.6, 0.9),
		Transparency = fade(0.5, 1) })
	softTrail(a, C.Amber, 2.4, 0.3)
	light(a, C.Amber, 16, 3)
	return m
end

-- 5. Les effets des 16 armes
local W = folder(FX, "Weapons")
local function weapon(id: string): Folder
	return folder(W, id)
end

slash(weapon("Broadsword"))

lightShot(weapon("Longbow"), C.Teal, 0.7, 0.22)
impact(weapon("Longbow"), "Impact", C.Teal, 6)

fireball(weapon("FireStaff"))
explosion(weapon("FireStaff"), "Area", { burn = 2 })

wave(weapon("QuakeHammer"), "Area", C.Cream, { grow = 0.15, dust = C.Dust, sparks = 6, sparkColor = C.Cream, flash = 0.6 })

lightShot(weapon("ThrowingDaggers"), C.Lilac, 0.55, 0.18)
impact(weapon("ThrowingDaggers"), "Impact", C.Lilac, 5)

aura(weapon("HolyAura"), C.Gold)

orbit(weapon("SpinningAxes"), "SpinningAxes", C.Cream, 0.7)

wave(weapon("BeastWhip"), "Area", C.Amber, { grow = 0.5, shocks = 1, sparks = 12, sparkColor = C.Butter, life = 0.3 })

segment(weapon("LightningChain"), C.Sky, 10)

wave(weapon("FrostNova"), "Area", C.Ice, { grow = 0.2, mist = C.Frost, sparks = 14, sparkColor = C.Frost, gravity = -4, life = 0.5 })

pieceShot(weapon("Boomerang"), "Boomerang", FLAT, C.Gold, { spin = 18, trailWidth = 1.0, scale = 0.8 })

telegraph(folder(FX, "Shared"))
fallBomb(weapon("BombBag"))
explosion(weapon("BombBag"), "Area", {})

lightShot(weapon("SpearThrow"), C.Butter, 0.8, 0.3)
impact(weapon("SpearThrow"), "Impact", C.Butter, 6)

fallMeteor(weapon("MeteorRain"))
explosion(weapon("MeteorRain"), "Area", { burn = 2, fire = 9, embers = 16 })

orbit(weapon("OrbitingBlades"), "OrbitingBlades", C.Sky, 0.45)

do
	local t = newModel(weapon("CrossbowTurret"), "Turret", "turret", 0, 0)
	piece(t, "CrossbowTurret", UPRIGHT, 0.9)
	emitter(t.PrimaryPart, "Dust", { Texture = TEX.Smoke, Color = C.Smoke, LightEmission = 0, Brightness = 1, Burst = 8,
		Size = seq(1.6, 2.6), Speed = NumberRange.new(3, 5), Lifetime = NumberRange.new(0.4, 0.6),
		Spread = Vector2.new(80, 80), Transparency = fade(0.4, 1) })
end
lightShot(weapon("CrossbowTurret"), C.Cream, 0.5, 0.16)
impact(weapon("CrossbowTurret"), "Impact", C.Cream, 4)

-- 6. Effets des passifs et des objets (Codec.Visual)
local SP = folder(FX, "Special")
wave(folder(SP, "Parry"), "Area", C.Royal, { grow = 0.5, shocks = 1, sparks = 8, flash = 0.5, life = 0.3 })
do
	local m = newModel(folder(SP, "Blessing"), "Area", "area", 0.8, 0.1)
	local z = zone(m, 0.8)
	emitter(z, "Motes", { Color = C.Gold, Color1 = C.Cream, Burst = 10, Size = seq(0.6, 0), Speed = NumberRange.new(2, 4),
		Lifetime = NumberRange.new(0.6, 0.8), Spread = Vector2.new(10, 10), Shape = Enum.ParticleEmitterShape.Disc,
		Acceleration = Vector3.new(0, 4, 0) })
end
lightShot(folder(SP, "Ghost"), C.Frost, 1.0, 0.3)
wave(folder(SP, "Whistle"), "Area", C.White, { grow = 0.2, shocks = 1, sparks = 6, life = 0.4 })
wave(folder(SP, "Megaphone"), "Area", C.Gold, { grow = 0.2, sparks = 10, life = 0.4 })
wave(folder(SP, "Thorns"), "Area", C.Stone, { grow = 0.3, shocks = 1, sparks = 8, sparkColor = C.Cream, life = 0.3 })
do
	local m = newModel(folder(SP, "Shadowstep"), "Area", "area", 0.6, 0.1)
	local z = zone(m, 0.6)
	emitter(z, "Smoke", { Texture = TEX.Smoke, Color = C.Plum, Color1 = C.Grape, LightEmission = 0.3, Burst = 10,
		Size = seq(2, 3.4), Speed = NumberRange.new(2, 4), Lifetime = NumberRange.new(0.4, 0.6),
		Shape = Enum.ParticleEmitterShape.Disc, Acceleration = Vector3.new(0, 4, 0) })
end
segment(folder(SP, "ChainBolt"), C.Gold, 6)
explosion(folder(SP, "MiniBomb"), "Area", { life = 0.4, fire = 4, smoke = 3, embers = 8, lightBrightness = 2 })

-- 7. Attaques des ennemis (EnemyAttackFX) : couleur posée par le code selon le profil de l'ennemi,
-- peu lumineuses (le Neon et la lumière sont pour le joueur), formes mates
local EN = folder(FX, "Enemies")
do
	local m = newModel(EN, "Sweep", "enemy", 0.4, 1.2)
	local z = zone(m, 0.6)
	emitter(z, "Swipe", { LightEmission = 0.3, Burst = 6, Size = seq(1.1, 0), Speed = NumberRange.new(6, 9),
		Lifetime = NumberRange.new(0.2, 0.3), Spread = Vector2.new(35, 10), Shape = Enum.ParticleEmitterShape.Disc, Streak = true })
	emitter(z, "Debris", { LightEmission = 0.2, Burst = 5, Size = seq(0.5, 0), Speed = NumberRange.new(5, 9),
		Lifetime = NumberRange.new(0.3, 0.45), Acceleration = Vector3.new(0, -25, 0) })
end
do
	local m = newModel(EN, "Burst", "enemy", 0.4, 0.08)
	shape(m, "FX_Ring", C.White, { S = 1, Grow = 0.3, Fade0 = 0.3, Fade1 = 1, Matte = true })
	local z = zone(m, 0.6)
	emitter(z, "Dust", { Texture = TEX.Smoke, LightEmission = 0, Brightness = 1, Burst = 4, PerRadius = true,
		Size = seq(1.4, 2.4), Speed = NumberRange.new(2, 4), Lifetime = NumberRange.new(0.35, 0.5),
		Transparency = fade(0.55, 1), Shape = Enum.ParticleEmitterShape.Disc })
	emitter(z, "Debris", { LightEmission = 0.2, Burst = 6, Size = seq(0.5, 0), Speed = NumberRange.new(6, 10),
		Lifetime = NumberRange.new(0.3, 0.45), Spread = Vector2.new(60, 60), Acceleration = Vector3.new(0, -25, 0) })
end
do
	local m = newModel(EN, "Shot", "enemy", 0.3, 1.6)
	emitter(m.PrimaryPart, "Puff", { Texture = TEX.Smoke, LightEmission = 0.1, Brightness = 1, Burst = 3,
		Size = seq(1.2, 2), Speed = NumberRange.new(2, 4), Lifetime = NumberRange.new(0.2, 0.3), Spread = Vector2.new(25, 25) })
	emitter(m.PrimaryPart, "Debris", { LightEmission = 0.2, Burst = 4, Size = seq(0.4, 0), Speed = NumberRange.new(6, 10),
		Lifetime = NumberRange.new(0.15, 0.25), Spread = Vector2.new(25, 25) })
end
do
	local m = newModel(EN, "Land", "enemy", 0.45, 0.08)
	shape(m, "FX_RingThick", C.White, { S = 1, Grow = 0.25, Fade0 = 0.35, Fade1 = 1, Matte = true })
	local z = zone(m, 0.7)
	emitter(z, "Dust", { Texture = TEX.Smoke, LightEmission = 0, Brightness = 1, Burst = 6, PerRadius = true,
		Size = seq(1.6, 2.8), Speed = NumberRange.new(3, 5), Lifetime = NumberRange.new(0.4, 0.55),
		Transparency = fade(0.5, 1), Shape = Enum.ParticleEmitterShape.Disc })
end
do
	local m = newModel(EN, "Boss", "enemy", 0.6, 0.08)
	shape(m, "FX_RingThick", C.White, { S = 1, Grow = 0.2, Fade0 = 0.2, Fade1 = 1, Matte = true })
	shape(m, "FX_Disc", C.White, { S = 0.95, Grow = 0.5, Fade0 = 0.75, Fade1 = 1, Matte = true })
	local z = zone(m, 0.7)
	emitter(z, "Dust", { Texture = TEX.Smoke, LightEmission = 0, Brightness = 1, Burst = 10, PerRadius = true,
		Size = seq(2.5, 4.5), Speed = NumberRange.new(3, 6), Lifetime = NumberRange.new(0.5, 0.8),
		Transparency = fade(0.45, 1), Shape = Enum.ParticleEmitterShape.Disc })
	emitter(z, "Debris", { LightEmission = 0.2, Burst = 12, PerRadius = true, Size = seq(0.8, 0),
		Speed = NumberRange.new(10, 16), Lifetime = NumberRange.new(0.4, 0.6), Spread = Vector2.new(60, 60),
		Acceleration = Vector3.new(0, -30, 0), Shape = Enum.ParticleEmitterShape.Disc })
end

print("A14 : effets v2 posés dans ReplicatedStorage.Assets.FX (Weapons, Special, Shared, Enemies ; Shapes gardé)")
