--!strict
-- Draws server enemies from binary snapshots (doc 12.2, dossier 20 section 8).
-- Étape 4 (dossier 13 §6 et §9.1) : rien n'est fabriqué ici. Chaque espèce clone le modèle
-- Assets.Creatures.<Config/Enemies.asset> posé par Clément (Root invisible en PrimaryPart, Body,
-- Eyes, LOD), à sa taille finale ; les élites le clonent à x1,3 avec Assets.FX.Enemies.EliteRing et
-- EliteCrown. Un modèle manquant est signalé une fois et remplacé par Assets.Creatures.Enemy_Placeholder
-- s'il existe (sinon rien n'est dessiné). Les modèles riggés de Codex (avec des os) gardent
-- EnemyRigMotion ; les anciennes mailles seules (v1) gardent leur mise à l'échelle LEGACY_SCALE.
-- Pooled by (kind, LOD, elite), interpolated between samples, all moved in one BulkMoveTo per frame.
-- LOD: full model < 80 studs, the model's `LOD` mesh < 150, Assets.FX.Enemies.Impostor beyond.
-- Enemy projectiles clone Assets.FX.Enemies.Projectiles.<Enemies[].projectile> (bosses :
-- Assets.FX.Bosses.<fxFolder>.<attack.projectile>), replayed in closed form from their launch data.
-- Bosses are drawn by BossRenderer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Bosses = require(Config:WaitForChild("Bosses"))
local Enemies = require(Config:WaitForChild("Enemies"))
local Run = require(Config:WaitForChild("Run"))
local Worlds = require(Config:WaitForChild("Worlds"))
local Codec = require(Shared:WaitForChild("EnemyCodec"))
local Heightmap = require(Shared:WaitForChild("Heightmap"))
local Net = require(Shared:WaitForChild("Net"))
local Motion = require(script.Parent.EnemyMotion)
local Effects = require(script.Parent.EnemyAttackFX)
local RigMotion = require(script.Parent.EnemyRigMotion)
local ArtLibrary = require(Shared:WaitForChild("ArtLibrary"))

-- Anciennes mailles v1 (une MeshPart seule, pas à l'échelle finale) : dessinées 1,3 fois plus grandes
-- que la hauteur de gameplay. Les modèles A03 (avec PrimaryPart) sont posés à leur taille : pas d'échelle.
local LEGACY_SCALE = 1.3

local SAMPLE_DT = 1 / Balance.SimHz
local HIDDEN = CFrame.new(0, -10000, 0)
local LOD_NEAR = 80
local LOD_FAR = 150
local LOD_HYST = 6
local GOLD = Color3.fromRGB(255, 200, 40)
local FROZEN = Color3.fromRGB(150, 210, 255)

local BIT_ELITE = 1
local BIT_ACTION = 2
local BIT_STOPPED = 4

-- ground[k] = true : pièce posée au sol (anneau d'élite), qui ne suit pas le balancement du corps.
type Model = { parts: { BasePart }, offsets: { CFrame }, colors: { Color3 }, ground: { [number]: boolean }, rig: RigMotion.Rig? }

type Entry = {
	kind: number,
	elite: boolean,
	lod: number,
	model: Model,
	fromX: number,
	fromZ: number,
	toX: number,
	toZ: number,
	t0: number,
	span: number,
	lastTick: number,
	state: number,
	actionStart: number,
	aimAt: number,
	strikeAt: number,
	stride: number,
	walkWeight: number,
	tinted: boolean,
	faceX: number,
	faceZ: number,
	marker: Marker?,
}

-- Aura + icône d'une variante capturable (A03-03) : gabarits FX_CaptureRing / FX_CaptureIcon.
type Marker = { parts: { BasePart }, offsets: { CFrame } }

type Shot = { parts: { BasePart }, offsets: { CFrame }, template: Instance }

type Projectile = {
	id: number,
	shot: Shot,
	x: number,
	y: number,
	z: number,
	dx: number,
	dz: number,
	speed: number,
	t0: number,
	ends: number,
}

-- Ce que le renderer sait du modèle d'une espèce (lu une fois).
type Visual = {
	template: Instance?,
	mode: "pivot" | "rig" | "legacy" | "none",
	height: number, -- hauteur dessinée (sans le x1,3 des élites)
	radius: number,
	float: number,
	hasLod: boolean,
}

local EnemyRenderer = {}

local entries: { [number]: Entry } = {}
local pools: { [number]: { Model } } = {}
local projectiles: { [number]: Projectile } = {}
local shotPools: { [Instance]: { Shot } } = {}
local latestTick = 0
local visibleCount = 0
local container: Folder

-- Variantes capturables (remote EnemyCapturable, A03-03 ; hors EnemyCodec pour garder 7 octets)
local capturableIds: { [number]: boolean } = {}
local markerPools: { [number]: { Marker } } = {}
local markerMissing = false

local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

local warned: { [string]: boolean } = {}

local function warnOnce(key: string, text: string)
	if not warned[key] then
		warned[key] = true
		warn(text)
	end
end

local function prepPart(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
end

-- Models ---------------------------------------------------------------------------------------

local visuals: { [number]: Visual } = {}

local function numAttr(i: Instance, name: string): number?
	local v = i:GetAttribute(name)
	return if type(v) == "number" and v == v then v else nil
end

local function visualOf(kind: number): Visual
	local v = visuals[kind]
	if v then
		return v
	end
	local def = Enemies[kind]
	local name = def.asset or ("Enemy_" .. def.name)
	local template = ArtLibrary.find(name)
	if not template then
		warnOnce(name, `[EnemyRenderer] modèle manquant : Assets.Creatures.{name} (dossier 13 §9.1) ; Enemy_Placeholder à la place s'il existe`)
		template = ArtLibrary.find("Enemy_Placeholder")
		if not template then
			warnOnce("Enemy_Placeholder", "[EnemyRenderer] Assets.Creatures.Enemy_Placeholder manquant : les ennemis sans modèle ne sont pas dessinés")
		end
	end
	local mode: "pivot" | "rig" | "legacy" | "none" = "none"
	local height = def.height * LEGACY_SCALE
	if template then
		if template:IsA("Model") and template:FindFirstChildWhichIsA("Bone", true) then
			mode = "rig"
			height = numAttr(template, "VisualHeight") or height
		elseif template:IsA("Model") and template.PrimaryPart then
			mode = "pivot"
			height = numAttr(template, "Height") or template:GetExtentsSize().Y
		elseif template:IsA("BasePart") or template:FindFirstChildWhichIsA("BasePart", true) then
			mode = "legacy"
			height = numAttr(template, "Height") or height
		end
	end
	v = {
		template = template,
		mode = mode,
		height = height,
		radius = (template and numAttr(template, "Radius")) or def.radius,
		float = (template and numAttr(template, "Float")) or 0,
		hasLod = template ~= nil and mode == "pivot" and template:FindFirstChild("LOD", true) ~= nil,
	}
	visuals[kind] = v
	return v
end

-- Ancienne maille seule (v1), mise à l'échelle pour mesurer `height` studs.
local function cloneLegacyMesh(template: Instance, height: number): BasePart?
	local source: BasePart? = nil
	if template:IsA("BasePart") then
		source = template
	else
		source = template:FindFirstChildWhichIsA("BasePart", true)
	end
	if not source then
		return nil
	end
	local part = source:Clone()
	part:ClearAllChildren()
	prepPart(part)
	if height > 0 and part.Size.Y > 0 then
		part.Size = part.Size * (height / part.Size.Y)
	end
	return part
end

local function poolKey(kind: number, lod: number, elite: boolean): number
	return kind * 16 + lod * 2 + (if elite then 1 else 0)
end

-- Clone d'un objet d'effet (anneau, couronne, imposteur) avec ses décalages depuis son pivot.
local function addFx(m: Model, path: string, scale: number, at: CFrame, onGround: boolean, color: Color3?): boolean
	local t = ArtLibrary.fx(path)
	if not t then
		warnOnce(path, `[EnemyRenderer] objet manquant : Assets.FX.{path} (dossier 13 §9.2)`)
		return false
	end
	local parts, offsets = ArtLibrary.clonePivoted(t, scale)
	for k, p in parts do
		if color then
			p.Color = color
		end
		p.CFrame = HIDDEN
		p.Parent = container
		table.insert(m.parts, p)
		table.insert(m.offsets, at * offsets[k])
		table.insert(m.colors, p.Color)
		if onGround then
			m.ground[#m.parts] = true
		end
	end
	return #parts > 0
end

local function fxWidth(path: string): number
	local t = ArtLibrary.fx(path)
	if not t then
		return 1
	end
	local size = if t:IsA("BasePart") then t.Size elseif t:IsA("Model") then t:GetExtentsSize() else Vector3.one
	return math.max(0.1, size.X, size.Z)
end

local function buildModel(kind: number, lod: number, elite: boolean): Model
	local def = Enemies[kind]
	local vis = visualOf(kind)
	local m: Model = { parts = {}, offsets = {}, colors = {}, ground = {} }
	local s = if elite and def.family ~= "MiniBoss" then Run.EliteSizeMult else 1
	local function add(part: BasePart, offset: CFrame)
		part.CFrame = HIDDEN
		part.Parent = container
		table.insert(m.parts, part)
		table.insert(m.offsets, offset)
		table.insert(m.colors, part.Color)
	end
	local template = vis.template
	local lifted = CFrame.new(0, vis.float * s, 0)

	if lod == 3 then
		-- Imposteur lointain : un objet plat teinté à la couleur de l'espèce (or pour une élite).
		local width = vis.radius * 1.6 * s
		if not addFx(m, "Enemies.Impostor", width / fxWidth("Enemies.Impostor"), CFrame.identity, true, if elite then GOLD else def.color) then
			lod = 2 -- sans imposteur : le LOD moyen
		else
			return m
		end
	end

	if template and vis.mode == "pivot" then
		local parts, offsets = ArtLibrary.clonePivoted(template, s)
		local useLod = lod == 2 and vis.hasLod
		for k, p in parts do
			local isLod = p.Name == "LOD"
			if isLod ~= useLod then
				p:Destroy()
				continue
			end
			if isLod then
				p.Transparency = 0
			end
			add(p, lifted * offsets[k])
		end
	elseif template and vis.mode == "rig" and template:IsA("Model") then
		-- Modèle riggé de Codex : os animés de près, pose de repos figée à mi-distance.
		local source = template:FindFirstChildWhichIsA("MeshPart", true)
		if source then
			local part = source:Clone()
			local scaleModel = Instance.new("Model") -- conteneur invisible, le temps de ScaleTo
			part.Parent = scaleModel
			scaleModel:ScaleTo(vis.height * s / part.Size.Y)
			part.Parent = nil
			scaleModel:Destroy()
			local floor = part.Position - Vector3.yAxis * (part.Size.Y * .5)
			local yaw = math.rad((template:GetAttribute("FaceYaw") :: number?) or 0)
			local facing = CFrame.new(floor) * CFrame.Angles(0, -yaw, 0)
			local rig = RigMotion.bind(part, facing)
			if lod == 1 then
				m.rig = rig
			else
				RigMotion.apply(rig, def.name, 0, 0, 0, 0, os.clock())
			end
			prepPart(part)
			part.Name = def.name
			add(part, facing:ToObjectSpace(part.CFrame))
		end
	elseif template and vis.mode == "legacy" then
		local mesh = cloneLegacyMesh(template, vis.height * s)
		if mesh then
			add(mesh, lifted * CFrame.new(0, mesh.Size.Y / 2, 0))
		end
	end

	if elite then
		local r = vis.radius * s
		addFx(m, "Enemies.EliteRing", r * 3 / fxWidth("Enemies.EliteRing"), CFrame.new(0, 0.05, 0), true, nil)
		if lod == 1 then
			addFx(m, "Enemies.EliteCrown", s, CFrame.new(0, (vis.float + vis.height + 0.8) * s, 0), false, nil)
		end
	end
	return m
end

local function acquire(kind: number, lod: number, elite: boolean): Model
	local pool = pools[poolKey(kind, lod, elite)]
	local m = pool and table.remove(pool)
	return m or buildModel(kind, lod, elite)
end

local function pushPool(key: number, m: Model)
	local pool = pools[key]
	if not pool then
		pool = {}
		pools[key] = pool
	end
	table.insert(pool, m)
end

local function acquireMarker(kind: number, elite: boolean): Marker?
	if markerMissing then
		return nil
	end
	local pool = markerPools[poolKey(kind, 1, elite)]
	local reused = pool and table.remove(pool)
	if reused then
		return reused
	end
	local vis = visualOf(kind)
	local s = if elite then Run.EliteSizeMult else 1
	local parts, offsets = ArtLibrary.cloneCaptureMarker((vis.float + vis.height) * s, vis.radius * s * 1.6)
	if not parts or not offsets then
		markerMissing = true
		warn("[EnemyRenderer] gabarits FX_CaptureRing / FX_CaptureIcon manquants : variantes capturables sans aura")
		return nil
	end
	for _, part in parts do
		part.CFrame = HIDDEN
		part.Parent = container
	end
	return { parts = parts, offsets = offsets }
end

local function releaseMarker(e: Entry)
	local mk = e.marker
	if not mk then
		return
	end
	e.marker = nil
	for _, part in mk.parts do
		part.CFrame = HIDDEN
	end
	local key = poolKey(e.kind, 1, e.elite)
	local pool = markerPools[key]
	if not pool then
		pool = {}
		markerPools[key] = pool
	end
	table.insert(pool, mk)
end

local function release(e: Entry)
	releaseMarker(e)
	local m = e.model
	for k, part in m.parts do
		part.CFrame = HIDDEN -- moving is cheaper than reparenting
		if e.tinted then
			part.Color = m.colors[k]
		end
	end
	e.tinted = false
	pushPool(poolKey(e.kind, e.lod, e.elite), m)
end

local function setTint(e: Entry, on: boolean)
	if e.tinted == on then
		return
	end
	e.tinted = on
	for k, part in e.model.parts do
		part.Color = if on then e.model.colors[k]:Lerp(FROZEN, 0.6) else e.model.colors[k]
	end
end

-- Pré-chauffe des pools (PERF-05) ----------------------------------------------------------------
-- Au changement de monde : les pools des espèces qui n'en font plus partie sont détruits, et ceux du
-- nouveau roster sont remplis quelques modèles par image (pas d'à-coup à la 1re apparition).
local PREWARM_PER_FRAME = 4
type Job = { kind: number, lod: number, elite: boolean, left: number }
local prewarmJobs: { Job } = {}
local warmedLayout: any = nil

local function rosterKinds(world: Worlds.World): ({ [number]: boolean }, { number })
	local set: { [number]: boolean } = {}
	local swarm: { number } = {}
	for family, kind in world.roster :: any do
		if type(kind) == "number" then
			set[kind] = true
			if family == "Swarm" then
				table.insert(swarm, kind)
			end
		end
	end
	for family, variant in world.variants or {} do
		set[variant.kind] = true
		if family == "Swarm" then
			table.insert(swarm, variant.kind)
		end
	end
	set[world.miniBoss] = true
	return set, swarm
end

local function startPrewarm(layout: any)
	table.clear(prewarmJobs)
	local world = layout and Worlds[layout.worldId]
	if not world then
		return
	end
	local set, swarm = rosterKinds(world)
	-- Les pools des espèces hors du nouveau monde ne servent plus : on les détruit.
	for key, pool in pools do
		local kind = key // 16
		if not set[kind] then
			for _, m in pool do
				for _, p in m.parts do
					p:Destroy()
				end
			end
			pools[key] = nil
		end
	end
	local isSwarm: { [number]: boolean } = {}
	for _, kind in swarm do
		isSwarm[kind] = true
		table.insert(prewarmJobs, { kind = kind, lod = 1, elite = false, left = 30 })
		table.insert(prewarmJobs, { kind = kind, lod = 2, elite = false, left = 20 })
		table.insert(prewarmJobs, { kind = kind, lod = 1, elite = true, left = 4 })
	end
	for kind in set do
		if not isSwarm[kind] and Enemies[kind] and not Enemies[kind].isBoss then
			local n = if Enemies[kind].family == "MiniBoss" then 1 else 10
			table.insert(prewarmJobs, { kind = kind, lod = 1, elite = false, left = n })
			table.insert(prewarmJobs, { kind = kind, lod = 2, elite = false, left = math.ceil(n / 2) })
		end
	end
end

local function stepPrewarm()
	local layout = Heightmap.getLayout()
	if layout ~= warmedLayout then
		warmedLayout = layout
		startPrewarm(layout)
	end
	local budget = PREWARM_PER_FRAME
	while budget > 0 and #prewarmJobs > 0 do
		local job = prewarmJobs[#prewarmJobs]
		local key = poolKey(job.kind, job.lod, job.elite)
		local have = pools[key] and #pools[key] or 0
		if have >= job.left then
			table.remove(prewarmJobs)
			continue
		end
		pushPool(key, buildModel(job.kind, job.lod, job.elite))
		budget -= 1
	end
end

-- Snapshots ------------------------------------------------------------------------------------

local function onSnapshot(payload: unknown)
	if typeof(payload) ~= "buffer" then
		return
	end
	local header = Codec.readHeader(payload)
	if not header or header.tick < latestTick then
		return -- malformed, or older than what we already drew
	end
	latestTick = header.tick
	local tick = header.tick
	local now = os.clock()

	-- Ennemis retirés (morts, nettoyés) : effacés tout de suite.
	Codec.forEachRemoved(payload, header, function(id)
		local e = entries[id]
		if e then
			release(e)
			entries[id] = nil
		end
		capturableIds[id] = nil
	end)

	Codec.forEach(payload, header, function(id, x, z, flags)
		local kind, st = Codec.unpackFlags(flags)
		local def = Enemies[kind]
		if not def or def.isBoss then
			return
		end
		local elite = bit32.band(st, BIT_ELITE) ~= 0
		local e = entries[id]
		if e and (e.kind ~= kind or e.elite ~= elite) then
			release(e)
			entries[id] = nil
			e = nil
		end
		if not e then
			entries[id] = {
				kind = kind,
				elite = elite,
				lod = 2,
				model = acquire(kind, 2, elite),
				fromX = x,
				fromZ = z,
				toX = x,
				toZ = z,
				t0 = now,
				span = SAMPLE_DT,
				lastTick = tick,
				state = st,
				actionStart = if bit32.band(st, BIT_ACTION) ~= 0 then now else 0,
				aimAt = -math.huge,
				strikeAt = -math.huge,
				stride = id % 13,
				walkWeight = 0,
				tinted = false,
				faceX = 0,
				faceZ = -1,
			}
		elseif tick > e.lastTick then
			-- L'écart entre deux échantillons d'un ennemi varie (PERF-01 : 1, 4 ou 8 ticks) :
			-- on interpole sur l'écart réel.
			local a = math.clamp((now - e.t0) / e.span, 0, 1)
			e.fromX = e.fromX + (e.toX - e.fromX) * a
			e.fromZ = e.fromZ + (e.toZ - e.fromZ) * a
			e.toX, e.toZ = x, z
			e.t0 = now
			e.span = math.max(SAMPLE_DT, (tick - e.lastTick) * SAMPLE_DT)
			e.lastTick = tick
			if bit32.band(st, BIT_ACTION) ~= 0 and bit32.band(e.state, BIT_ACTION) == 0 and now - e.aimAt > .22 then
				e.actionStart = now
			end
			e.state = st
		end
	end)
end

-- Projectiles ----------------------------------------------------------------------------------

local bossByKind: { [number]: Bosses.Boss } = {}
for _, b in Bosses.List do
	bossByKind[b.kind] = b
end

local shotTemplates: { [number]: Instance | false } = {}

local function shotTemplate(style: number): Instance?
	local hit = shotTemplates[style]
	if hit ~= nil then
		return if hit then hit else nil
	end
	local kind, slot = Codec.unpackStyle(style)
	local path: string? = nil
	local boss = bossByKind[kind]
	if boss and slot > 0 then
		local attack = boss.attacks[slot]
		if attack and attack.projectile and boss.fxFolder then
			path = `Bosses.{boss.fxFolder}.{attack.projectile}`
		end
	else
		local def = Enemies[kind]
		if def and def.projectile then
			path = `Enemies.Projectiles.{def.projectile}`
		end
	end
	local found = if path then ArtLibrary.fx(path) else nil
	if path and not found then
		warnOnce(path, `[EnemyRenderer] tir manquant : Assets.FX.{path} ; Default à la place`)
	end
	found = found or ArtLibrary.fx("Enemies.Projectiles.Default")
	if not found then
		warnOnce("Projectiles.Default", "[EnemyRenderer] Assets.FX.Enemies.Projectiles.Default manquant : tirs ennemis invisibles")
	end
	shotTemplates[style] = found or false
	return found
end

local function takeShot(style: number): Shot?
	local t = shotTemplate(style)
	if not t then
		return nil
	end
	local pool = shotPools[t]
	local reused = pool and table.remove(pool)
	if reused then
		return reused
	end
	local parts, offsets = ArtLibrary.clonePivoted(t)
	for _, p in parts do
		p.CFrame = HIDDEN
		p.Parent = container
	end
	return { parts = parts, offsets = offsets, template = t }
end

local function giveShot(shot: Shot)
	for _, p in shot.parts do
		p.CFrame = HIDDEN
	end
	local pool = shotPools[shot.template]
	if not pool then
		pool = {}
		shotPools[shot.template] = pool
	end
	table.insert(pool, shot)
end

local function onProjectiles(payload: unknown)
	if typeof(payload) ~= "buffer" then
		return
	end
	local spawns, removed = Codec.decodeProjectiles(payload)
	if not spawns or not removed then
		return
	end
	for _, p in spawns do
		local old = projectiles[p.id]
		if old then
			giveShot(old.shot)
			projectiles[p.id] = nil
		end
		local shot = takeShot(p.style)
		if shot then
			projectiles[p.id] = {
				id = p.id,
				shot = shot,
				x = p.x,
				y = p.y,
				z = p.z,
				dx = math.cos(p.angle),
				dz = math.sin(p.angle),
				speed = p.speed,
				t0 = p.t0,
				ends = p.t0 + p.life,
			}
		end
	end
	for _, id in removed do
		local pr = projectiles[id]
		if pr then
			giveShot(pr.shot)
			projectiles[id] = nil
		end
	end
end

-- Frame ------------------------------------------------------------------------------------------

local function viewerPosition(): Vector3
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local camera = Workspace.CurrentCamera
	return if camera then camera.Focus.Position else Vector3.zero
end

-- Blackout (PERF-08) : grille des lampes, construite une fois par carte. Chaque case de LAMP_CELL
-- studs garde les lampes dont le disque la touche ; un ennemi ne teste que les lampes de sa case.
local LAMP_CELL = 16
local lampGrid: { [number]: { number } } = {}
local lampGridLayout: any = nil
local lampGridRadius = 0

local function lampKey(cx: number, cz: number): number
	return (cx + 32768) * 65536 + (cz + 32768)
end

local function ensureLampGrid(layout: any, lr: number)
	if layout == lampGridLayout and lr == lampGridRadius then
		return
	end
	lampGridLayout, lampGridRadius = layout, lr
	table.clear(lampGrid)
	for idx, l in layout.lamps do
		for cx = (l.x - lr) // LAMP_CELL, (l.x + lr) // LAMP_CELL do
			for cz = (l.z - lr) // LAMP_CELL, (l.z + lr) // LAMP_CELL do
				local key = lampKey(cx, cz)
				local cell = lampGrid[key]
				if not cell then
					cell = {}
					lampGrid[key] = cell
				end
				table.insert(cell, idx)
			end
		end
	end
end

local function blackoutVisible(x: number, z: number, viewer: Vector3, hazard: Worlds.Hazard): boolean
	local reveal = hazard.revealRadius or 20
	local dx, dz = x - viewer.X, z - viewer.Z
	if dx * dx + dz * dz <= reveal * reveal then
		return true
	end
	local layout = Heightmap.getLayout()
	if layout then
		local lr = hazard.lampRadius or 22
		ensureLampGrid(layout, lr)
		local cell = lampGrid[lampKey(x // LAMP_CELL, z // LAMP_CELL)]
		if cell then
			local lamps = layout.lamps
			for _, idx in cell do
				local l = lamps[idx]
				local lx, lz = x - l.x, z - l.z
				if lx * lx + lz * lz <= lr * lr then
					return true
				end
			end
		end
	end
	return false
end

local function onAttackVisual(payload: unknown)
	if typeof(payload) ~= "buffer" then
		return
	end
	local cue = Codec.decodeAttack(payload)
	if not cue then
		return
	end
	local def = Enemies[cue.kind]
	if not def then
		return
	end
	local id, mode, position, direction, radius = cue.id, cue.mode, cue.position, cue.direction, cue.radius
	local now = os.clock()
	local entry = if id ~= 0 then entries[id] else nil
	local facing = if direction.Magnitude > .01 then direction.Unit
		elseif entry then Vector3.new(entry.faceX, 0, entry.faceZ) else -Vector3.zAxis
	if mode == "slam" then
		-- Télégraphe d'une attaque de mini-boss (contract request 5)
		if entry then
			entry.aimAt = now
			entry.actionStart = now
			entry.faceX, entry.faceZ = facing.X, facing.Z
		end
		Effects.slam(def.slamShape or "Self", position, radius, if def.slamShape == "Ring" then def.slamInner or 0 else 0, math.max(def.slamWindup or 1, 1), Bosses.Colors.Normal)
		return
	end
	local profile = Motion.profiles[def.name]
	if not profile then
		return
	end
	if entry and entry.kind == cue.kind then
		if mode == "aim" then
			entry.aimAt = now
			entry.actionStart = now
		elseif now - entry.strikeAt < .15 then
			return -- simultaneous contact from multiple players
		else
			entry.strikeAt = now
		end
		entry.faceX, entry.faceZ = facing.X, facing.Z
	end
	if mode == "aim" then
		return
	end
	local viewer = viewerPosition()
	if (position - viewer).Magnitude > (if mode == "boss" then 135 else 82) then
		return
	end
	if mode ~= "boss" and Workspace:GetAttribute("CohueHazard") == "Blackout" then
		local layout = Heightmap.getLayout()
		local world = layout and Worlds[layout.worldId]
		local hazard = world and world.hazard
		if hazard and not blackoutVisible(position.X, position.Z, viewer, hazard) then
			return
		end
	end
	if mode == "contact" and profile.style ~= "burst" then
		position += Vector3.yAxis * radius * .55 + facing * radius * .55
	end
	Effects.emit(profile, position, facing, mode, radius)
end

local function render(dt: number)
	stepPrewarm()
	local now = os.clock()
	local staleBefore = latestTick - Balance.ClientStaleTicks
	local viewer = viewerPosition()
	local blackout: Worlds.Hazard? = nil
	if Workspace:GetAttribute("CohueHazard") == "Blackout" then
		local layout = Heightmap.getLayout()
		local world = layout and Worlds[layout.worldId]
		blackout = world and world.hazard
	end
	local n = 0
	local drawn = 0
	for id, e in entries do
		if e.lastTick < staleBefore then
			release(e)
			entries[id] = nil
			continue
		end
		local a = math.clamp((now - e.t0) / e.span, 0, 1)
		local x = e.fromX + (e.toX - e.fromX) * a
		local z = e.fromZ + (e.toZ - e.fromZ) * a
		local vx, vz = x - viewer.X, z - viewer.Z
		local dist = math.sqrt(vx * vx + vz * vz)

		-- LOD with hysteresis
		local lod = e.lod
		local want = if dist < LOD_NEAR then 1 elseif dist < LOD_FAR then 2 else 3
		if want ~= lod then
			local edge = if want < lod then (if lod == 2 then LOD_NEAR else LOD_FAR) - LOD_HYST
				else (if lod == 1 then LOD_NEAR else LOD_FAR) + LOD_HYST
			if (want < lod and dist < edge) or (want > lod and dist > edge) then
				release(e)
				e.lod = want
				e.model = acquire(e.kind, want, e.elite)
			end
		end

		local def = Enemies[e.kind]
		local hidden = blackout ~= nil and not blackoutVisible(x, z, viewer, blackout)
		setTint(e, bit32.band(e.state, BIT_STOPPED) ~= 0)

		local y = Heightmap.getY(x, z)
		local profile = Motion.profiles[def.name]
		local stopped = bit32.band(e.state, BIT_STOPPED) ~= 0
		local acting = bit32.band(e.state, BIT_ACTION) ~= 0
		local dx, dz = e.toX - e.fromX, e.toZ - e.fromZ
		local distance = math.sqrt(dx * dx + dz * dz)
		local speed = if distance < def.speed * e.span * 3 and a < 1 then distance / e.span else 0
		local striking = now - e.strikeAt
		if speed > .2 and not acting and not stopped and striking >= .38 then
			e.faceX, e.faceZ = dx / distance, dz / distance
		end
		local pos = Vector3.new(x, y, z)
		local base = if hidden then HIDDEN else CFrame.lookAt(pos, pos + Vector3.new(e.faceX, 0, e.faceZ))
		local modelBase = base
		local windupPose, strikePose = 0, 0
		if not hidden and e.lod <= 2 and not stopped and profile then
			local scale = if e.elite then Run.EliteSizeMult else 1
			local weight = if acting or striking < .38 then 0 else math.clamp(speed / def.speed, 0, 1)
			e.walkWeight += (weight - e.walkWeight) * math.min(dt * 13, 1)
			e.stride = (e.stride + speed * dt / scale) % profile.walk.stride
			if striking < .38 then
				strikePose = striking / .38
				modelBase *= Motion.strike(profile, strikePose, scale)
			elseif acting then
				local elapsed = now - e.actionStart
				local leaping = def.family == "Jumper" or def.leapAir ~= nil
				local windup = if leaping then def.leapWindup or .4
					elseif def.slamShape then def.slamWindup or 1
					else def.shotWindup or .6
				if leaping and elapsed > windup then
					local travel = math.clamp((elapsed - windup) / (def.leapAir or .8), 0, 1)
					modelBase *= Motion.air(profile, travel, scale, nil)
				else
					windupPose = math.clamp(elapsed / windup, 0, 1)
					modelBase *= Motion.charge(profile, windupPose, scale)
				end
			elseif e.lod == 1 then
				modelBase *= Motion.walk(profile, e.stride, e.walkWeight, now + id, scale)
			end
		end
		local m = e.model
		if m.rig and profile and not hidden then
			local phase = e.stride * (2 * math.pi / profile.walk.stride)
			local weight = if stopped or acting or striking < .38 then 0 else e.walkWeight
			RigMotion.apply(m.rig, def.name, phase, weight, windupPose, strikePose, now)
		end
		for k, part in m.parts do
			n += 1
			moveParts[n] = part
			moveCFrames[n] = if hidden then HIDDEN else (if m.ground[k] then base else modelBase) * m.offsets[k]
		end
		local wantsMarker = capturableIds[id] == true and e.lod <= 2
		if wantsMarker and not e.marker then
			e.marker = acquireMarker(e.kind, e.elite)
		elseif not wantsMarker and e.marker then
			releaseMarker(e)
		end
		local mk = e.marker
		if mk then
			for k, part in mk.parts do
				n += 1
				moveParts[n] = part
				moveCFrames[n] = if hidden then HIDDEN else base * mk.offsets[k]
			end
		end
		if not hidden then
			drawn += 1
		end
	end

	-- Enemy projectiles (closed form from launch data), facing their direction (avant = -Z)
	local serverNow = Workspace:GetServerTimeNow()
	for id, p in projectiles do
		if serverNow >= p.ends then
			giveShot(p.shot)
			projectiles[id] = nil
			continue
		end
		local t = math.max(0, serverNow - p.t0)
		local at = Vector3.new(p.x + p.dx * p.speed * t, p.y, p.z + p.dz * p.speed * t)
		local cf = CFrame.lookAt(at, at + Vector3.new(p.dx, 0, p.dz))
		for k, part in p.shot.parts do
			n += 1
			moveParts[n] = part
			moveCFrames[n] = cf * p.shot.offsets[k]
		end
	end

	for i = n + 1, #moveParts do
		moveParts[i] = nil :: any
		moveCFrames[i] = nil :: any
	end
	if n > 0 then
		-- PERF-06 : personne n'écoute le CFrame de ces pièces.
		Workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameNotChanged)
	end
	visibleCount = drawn
end

function EnemyRenderer.getVisibleCount(): number
	return visibleCount
end

function EnemyRenderer.init()
	container = Instance.new("Folder") -- dossier de rangement vide : invisible
	Effects.init()
	container.Name = "ClientEnemies"
	container.Parent = Workspace
end

function EnemyRenderer.start()
	Net.unreliable("EnemySnapshot").OnClientEvent:Connect(onSnapshot)
	Net.unreliable("EnemyAttackVisual").OnClientEvent:Connect(onAttackVisual)
	Net.event("EnemyProjectiles").OnClientEvent:Connect(onProjectiles)
	Net.event("EnemyCapturable").OnClientEvent:Connect(function(id: unknown, on: unknown)
		if type(id) == "number" then
			capturableIds[id] = if on == true then true else nil
		end
	end)
	RunService.PreRender:Connect(render)
end

return EnemyRenderer
