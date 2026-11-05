--!strict
-- Short client-only enemy attack effects. The server owns all hit checks.
-- A14 (dossier 12, section 14) : rien n'est construit ici. Les effets sont des modèles posés dans
-- ReplicatedStorage.Assets.FX.Enemies (Sweep, Burst, Shot, Land, Boss) ; ce module les clone en pool, les
-- place, les met à l'échelle du rayon, les teinte à la couleur du profil de l'ennemi et appelle :Emit().
-- Un modèle manquant est signalé une fois dans la sortie, puis ignoré.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Motion = require(script.Parent.EnemyMotion)
local ArtLibrary = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ArtLibrary"))
type Profile = Motion.Profile

type Shape = { part: BasePart, base: Vector3, s: number, grow: number, fade0: number, fade1: number }
type Inst = {
	model: Model,
	template: Model,
	anchor: BasePart,
	life: number,
	height: number,
	shapes: { Shape },
	zones: { { part: BasePart, s: number } },
	emitters: { { e: ParticleEmitter, n: number, perRadius: boolean } },
}
type Effect = { fx: Inst, start: number, base: CFrame, radius: number }

local Effects = {}
local HIDDEN = CFrame.new(0, -10000, 0)
local LIMIT = 18
local active: { Effect } = {}
local pools: { [Model]: { Inst } } = {}
local container: Folder? = nil
local root: Instance?
local warned: { [string]: boolean } = {}

local function num(i: Instance, name: string, default: number): number
	local v = i:GetAttribute(name)
	return if type(v) == "number" then v else default
end

local function template(name: string): Model?
	local m = root and root:FindFirstChild(name)
	if m and m:IsA("Model") then
		return m
	end
	if not warned[name] then
		warned[name] = true
		warn(`[EnemyAttackFX] modèle manquant : Assets.FX.Enemies.{name}`)
	end
	return nil
end

local function acquire(t: Model): Inst
	local pool = pools[t]
	local fx = pool and table.remove(pool)
	if fx then
		return fx
	end
	local model = t:Clone()
	model:PivotTo(HIDDEN)
	model.Parent = container
	local anchor = (model.PrimaryPart or model:FindFirstChild("Anchor")) :: BasePart
	local inst: Inst = {
		model = model,
		template = t,
		anchor = anchor,
		life = num(t, "Life", 0.4),
		height = num(t, "Height", 0.08),
		shapes = {},
		zones = {},
		emitters = {},
	}
	for _, c in model:GetChildren() do
		if c:IsA("BasePart") and c ~= anchor then
			if c.Name == "Zone" then
				table.insert(inst.zones, { part = c, s = num(c, "S", 1) })
			else
				local base = c:GetAttribute("Base")
				table.insert(inst.shapes, {
					part = c,
					base = if typeof(base) == "Vector3" then base else c.Size,
					s = num(c, "S", 1),
					grow = num(c, "Grow", 1),
					fade0 = num(c, "Fade0", c.Transparency),
					fade1 = num(c, "Fade1", c.Transparency),
				})
			end
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			table.insert(inst.emitters, { e = d, n = num(d, "Burst", 0), perRadius = d:GetAttribute("PerRadius") == true })
		end
	end
	return inst
end

local function release(effect: Effect)
	local fx = effect.fx
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

local function place(effect: Effect, u: number)
	local fx = effect.fx
	local e = 1 - (1 - math.clamp(u, 0, 1)) ^ 2
	fx.anchor.CFrame = effect.base
	for _, sh in fx.shapes do
		local k = sh.grow + (1 - sh.grow) * e
		local r = effect.radius * sh.s * k
		sh.part.Size = Vector3.new(sh.base.X * r, sh.base.Y, sh.base.Z * r)
		sh.part.CFrame = effect.base
		sh.part.Transparency = sh.fade0 + (sh.fade1 - sh.fade0) * math.clamp(u, 0, 1)
	end
	for _, z in fx.zones do
		z.part.Size = Vector3.new(2 * effect.radius * z.s, 0.2, 2 * effect.radius * z.s)
		z.part.CFrame = effect.base
	end
end

function Effects.emit(profile: Profile, origin: Vector3, facing: Vector3, mode: string, radius: number)
	if not root then
		return
	end
	if #active >= LIMIT then
		release(table.remove(active, 1) :: Effect)
	end
	local shoot = mode == "shot"
	local name = if mode == "boss" then "Boss"
		elseif mode == "land" then "Land"
		elseif shoot then "Shot"
		elseif profile.style == "burst" then "Burst"
		else "Sweep"
	local t = template(name)
	if not t then
		return
	end
	local fx = acquire(t)
	local r = math.clamp(radius, 0.7, if mode == "boss" then 10 else 4)
	local forward = if facing.Magnitude > 0.01 then facing.Unit else -Vector3.zAxis
	local pos = if shoot or name == "Sweep" then origin else Vector3.new(origin.X, origin.Y + fx.height, origin.Z)
	local effect: Effect = { fx = fx, start = os.clock(), base = CFrame.lookAt(pos, pos + forward), radius = r }
	-- teinte du profil : les formes mates et les particules prennent la couleur de l'ennemi
	local light = profile.color:Lerp(Color3.new(1, 1, 1), 0.45)
	for _, sh in fx.shapes do
		sh.part.Color = profile.color
	end
	place(effect, 0)
	for _, em in fx.emitters do
		em.e.Color = ColorSequence.new(light, profile.color)
		local k = if em.perRadius then math.clamp(r / 3, 0.5, 3) else 1
		if em.n > 0 then
			em.e:Emit(math.max(1, math.floor(em.n * k + 0.5)))
		end
	end
	table.insert(active, effect)
end

-- Télégraphes ennemis (dossier 13 §9.2, étape 4) ---------------------------------------------------
-- Objets posés par Clément dans Assets.FX.Enemies.Telegraphs : Circle, Ring, Line. Contrat :
--   * un Model, pivot au centre, au sol ;
--   * `Zone` : l'étendue totale ; `Fill` : grandit jusqu'à l'impact ; `Safe` (Ring) : la zone sûre ;
--   * Circle et Ring : le code met les deux grands axes de chaque pièce au diamètre voulu (l'axe le
--     plus fin reste l'épaisseur : un disque Cylinder couché marche aussi) ;
--   * Line : X = largeur, Z = longueur (le pivot est au milieu de la ligne) ;
--   * couleur de Zone et Fill posée par le code (Tomato danger, Grape invocation, Gold point faible) ;
--     transparences et matériaux viennent du modèle.
-- Utilisé par BossRenderer (attaques de boss) et ici pour les mini-boss (mode "slam").
export type Telegraph = {
	template: Instance,
	parts: { BasePart },
	offsets: { CFrame },
	roles: { string },
	bases: { Vector3 },
}

local telegraphPools: { [Instance]: { Telegraph } } = {}
local telegraphWarned: { [string]: boolean } = {}

local function ensureContainer(): Folder
	local folder = container
	if not folder then
		folder = Instance.new("Folder") -- dossier de rangement vide : invisible
		folder.Name = "ClientEnemyAttackFX"
		folder.Parent = Workspace
		container = folder
	end
	return folder
end

function Effects.takeTelegraph(shape: string): Telegraph?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local fx = assets and assets:FindFirstChild("FX")
	local enemies = fx and fx:FindFirstChild("Enemies")
	local folder = enemies and enemies:FindFirstChild("Telegraphs")
	local t = folder and folder:FindFirstChild(shape)
	if not t then
		if not telegraphWarned[shape] then
			telegraphWarned[shape] = true
			warn(`[EnemyAttackFX] télégraphe manquant : Assets.FX.Enemies.Telegraphs.{shape}`)
		end
		return nil
	end
	local pool = telegraphPools[t]
	local reused = pool and table.remove(pool)
	if reused then
		return reused
	end
	local parent = ensureContainer()
	local parts, offsets = ArtLibrary.clonePivoted(t)
	local tg: Telegraph = { template = t, parts = parts, offsets = offsets, roles = {}, bases = {} }
	for k, p in parts do
		tg.roles[k] = p.Name
		tg.bases[k] = p.Size
		p.CFrame = HIDDEN
		p.Parent = parent
	end
	return tg
end

function Effects.giveTelegraph(tg: Telegraph)
	for _, p in tg.parts do
		p.CFrame = HIDDEN
	end
	local pool = telegraphPools[tg.template]
	if not pool then
		pool = {}
		telegraphPools[tg.template] = pool
	end
	table.insert(pool, tg)
end

local function fitDisc(part: BasePart, base: Vector3, diameter: number)
	local d = math.max(0.1, diameter)
	if base.X <= base.Y and base.X <= base.Z then
		part.Size = Vector3.new(base.X, d, d)
	elseif base.Y <= base.Z then
		part.Size = Vector3.new(d, base.Y, d)
	else
		part.Size = Vector3.new(d, d, base.Z)
	end
end

-- Place un télégraphe de cercle ou d'anneau : centre au sol, rayon, rayon intérieur, avancement u (0..1).
function Effects.placeDisc(tg: Telegraph, center: CFrame, radius: number, inner: number, u: number, color: Color3?)
	local grown = inner + (radius - inner) * math.clamp(u, 0, 1)
	for k, p in tg.parts do
		local role = tg.roles[k]
		local d = if role == "Fill" then grown * 2 elseif role == "Safe" then inner * 2 else radius * 2
		if role == "Safe" and inner <= 0 then
			p.CFrame = HIDDEN
			continue
		end
		fitDisc(p, tg.bases[k], d)
		if color and (role == "Zone" or role == "Fill") then
			p.Color = color
		end
		p.CFrame = center * tg.offsets[k]
	end
end

-- Place un télégraphe de ligne : origine au sol, direction (unitaire), largeur, longueur, avancement u.
function Effects.placeLine(tg: Telegraph, origin: Vector3, dir: Vector3, width: number, length: number, u: number, color: Color3?)
	local filled = math.max(0.1, length * math.clamp(u, 0, 1))
	for k, p in tg.parts do
		local role = tg.roles[k]
		local l = if role == "Fill" then filled else length
		local base = tg.bases[k]
		p.Size = Vector3.new(math.max(0.1, width), base.Y, l)
		if color and (role == "Zone" or role == "Fill") then
			p.Color = color
		end
		local mid = origin + dir * (l / 2)
		p.CFrame = CFrame.lookAt(mid, mid + dir) * tg.offsets[k]
	end
end

-- Télégraphe d'attaque de mini-boss (mode "slam") : affiché `windup` s, puis rendu au pool.
type Slam = { tg: Telegraph, start: number, ends: number, center: CFrame, radius: number, inner: number }
local slams: { Slam } = {}

function Effects.slam(shape: string, position: Vector3, radius: number, inner: number, windup: number, color: Color3)
	local tg = Effects.takeTelegraph(if shape == "Ring" then "Ring" else "Circle")
	if not tg then
		return
	end
	local now = os.clock()
	local s: Slam = { tg = tg, start = now, ends = now + math.max(0.1, windup), center = CFrame.new(position + Vector3.new(0, 0.12, 0)), radius = radius, inner = inner }
	Effects.placeDisc(tg, s.center, radius, inner, 0, color)
	table.insert(slams, s)
end

local initialized = false

function Effects.init()
	if initialized then
		return
	end
	initialized = true
	ensureContainer()
	local assets = ReplicatedStorage:WaitForChild("Assets", 10)
	local fx = assets and assets:FindFirstChild("FX")
	root = fx and fx:FindFirstChild("Enemies")
	if not root then
		warn("[EnemyAttackFX] ReplicatedStorage.Assets.FX.Enemies introuvable : aucun effet d'attaque ennemie")
	end
	RunService.PreRender:Connect(function()
		local now = os.clock()
		for i = #active, 1, -1 do
			local effect = active[i]
			local u = (now - effect.start) / effect.fx.life
			if u >= 1 then
				release(effect)
				table.remove(active, i)
				continue
			end
			place(effect, u)
		end
		for i = #slams, 1, -1 do
			local s = slams[i]
			if now >= s.ends then
				Effects.giveTelegraph(s.tg)
				table.remove(slams, i)
				continue
			end
			Effects.placeDisc(s.tg, s.center, s.radius, s.inner, (now - s.start) / (s.ends - s.start), nil)
		end
	end)
end

return Effects
