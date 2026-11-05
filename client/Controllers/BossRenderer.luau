--!strict
-- Boss visuals and stage FX (dossier 20 section 8). Étape 4 (dossier 13 §6, §9) : rien n'est fabriqué ici.
--   * Boss model: clone of Assets.Creatures.<Bosses.List[].asset> (posé à sa taille finale, pivot aux
--     pieds, avant vers -Z), interpolated between BossState samples (10 Hz). Missing: warned once,
--     not drawn. Une ancienne maille seule (v1) est encore mise à BOSS_MESH_HEIGHT.
--   * Ground telegraphs: Assets.FX.Enemies.Telegraphs.Circle / Ring / Line (EnemyAttackFX : zone +
--     remplissage qui grandit jusqu'à l'impact, couleur posée par le code). Same shape params as
--     the server hit test.
--   * Weak points (bell / gongs) : Assets.FX.Bosses.WeakPoint when usable; the boss tints gold while vulnerable.
--   * Revealed Arche: Assets.FX.Bosses.ArcheBeam (pivot au pied du pilier), visible across the map.
--   * Stage hazards from Workspace attributes: fog, sandstorm (pushes the local character),
--     blackout. Jump pads from the shared layout (the local client applies the launch).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Bosses = require(Config:WaitForChild("Bosses"))
local Enemies = require(Config:WaitForChild("Enemies"))
local Worlds = require(Config:WaitForChild("Worlds"))
local Heightmap = require(Shared:WaitForChild("Heightmap"))
local Net = require(Shared:WaitForChild("Net"))
local Motion = require(script.Parent.EnemyMotion)
local Effects = require(script.Parent.EnemyAttackFX)
local ArtLibrary = require(Shared:WaitForChild("ArtLibrary"))

local HIDDEN = CFrame.new(0, -10000, 0)
local GOLD = Color3.fromRGB(255, 205, 60)
local PAD_RADIUS = 3.5
local PAD_SIDE_SPEED = 22

type Piece = { parts: { BasePart }, offsets: { CFrame } }
type TelegraphEntry = { data: { [string]: any }, tg: Effects.Telegraph }

local BossRenderer = {}

local container: Folder
local bossParts: { BasePart } = {}
local bossOffsets: { CFrame } = {}
local bossColors: { Color3 } = {}
local bossKey = ""
local bossFrom = Vector3.zero
local bossTo = Vector3.zero
local bossT0 = 0
local bossVisible = false
local bossTint = false
local bossStride = 0
local bossWalkWeight = 0
local castStart = -math.huge
local castHit = -math.huge
local castTarget: Vector3? = nil
local castDirection: Vector3? = nil
local lastState: { [string]: any }? = nil

local telegraphs: { TelegraphEntry } = {}
local weakMarkers: { Piece } = {}

local archeBeam: Piece? = nil
local runState: { [string]: any } = {}

local savedLighting: { [string]: any }? = nil
local currentHazard = ""
local padCooldown = 0

local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

local warned: { [string]: boolean } = {}

local function warnOnce(key: string, text: string)
	if not warned[key] then
		warned[key] = true
		warn(text)
	end
end

-- Clone d'un objet d'effet de Assets.FX (point faible, pilier de l'Arche), rangé caché dans le dossier.
local function clonePiece(path: string): Piece?
	local t = ArtLibrary.fx(path)
	if not t then
		warnOnce(path, `[BossRenderer] objet manquant : Assets.FX.{path} (dossier 13 §9.2)`)
		return nil
	end
	local parts, offsets = ArtLibrary.clonePivoted(t)
	for _, p in parts do
		p.CFrame = HIDDEN
		p.Parent = container
	end
	return { parts = parts, offsets = offsets }
end

-- Boss model -------------------------------------------------------------------------------------

local function clearBoss()
	for _, part in bossParts do
		part:Destroy()
	end
	table.clear(bossParts)
	table.clear(bossOffsets)
	table.clear(bossColors)
	bossKey = ""
	bossVisible = false
	bossTint = false
	bossStride, bossWalkWeight = 0, 0
	castStart, castHit = -math.huge, -math.huge
	castTarget, castDirection = nil, nil
end

local BOSS_MESH_HEIGHT = 18 -- studs ; seulement pour une ancienne maille seule (v1)

local function buildBoss(bossId: string)
	clearBoss()
	bossKey = bossId -- même absent, on ne le recherche pas à chaque BossState
	local def = Bosses.List[bossId]
	local enemy = def and Enemies[def.kind]
	local name = (def and def.asset) or (enemy and enemy.asset) or ("Boss_" .. bossId)
	local template = ArtLibrary.find(name)
	if not template then
		-- Ancien nom v1 (Boss_<id>), tant que Clément n'a pas posé le modèle v2.
		name = "Boss_" .. bossId
		template = ArtLibrary.find(name)
	end
	if not template then
		warnOnce(name, `[BossRenderer] modèle manquant : Assets.Creatures.{name} (dossier 13 §9.1) ; boss non dessiné`)
		return
	end
	if template:IsA("Model") and template.PrimaryPart then
		local parts, offsets = ArtLibrary.clonePivoted(template)
		for k, p in parts do
			p.CFrame = HIDDEN
			p.Parent = container
			table.insert(bossParts, p)
			table.insert(bossOffsets, offsets[k])
			table.insert(bossColors, p.Color)
		end
		return
	end
	-- Le nom de recherche, pas template.Name : un ancien modèle (EnemyVisualMeshes) ne se retrouve qu'avec le préfixe Boss_.
	local mesh = ArtLibrary.clonePart(name, BOSS_MESH_HEIGHT)
	if mesh then
		mesh.CFrame = HIDDEN
		mesh.Parent = container
		table.insert(bossParts, mesh)
		local yawAttr = template:GetAttribute("FaceYaw")
		local yaw = if type(yawAttr) == "number" then math.rad(yawAttr) elseif bossId == "GrandCheneRonchon" then math.pi else 0
		table.insert(bossOffsets, CFrame.new(0, mesh.Size.Y / 2, 0) * CFrame.Angles(0, yaw, 0))
		table.insert(bossColors, mesh.Color)
	end
end

-- Telegraphs -----------------------------------------------------------------------------------

local function clearTelegraphs()
	for _, t in telegraphs do
		Effects.giveTelegraph(t.tg)
	end
	table.clear(telegraphs)
end

local function setTelegraphs(list: { { [string]: any } })
	clearTelegraphs()
	for _, data in list do
		if typeof(data.position) ~= "Vector3" or type(data.radius) ~= "number" then
			continue
		end
		local shape = if data.kind == "Line" then "Line" elseif data.kind == "Ring" then "Ring" else "Circle"
		local tg = Effects.takeTelegraph(shape)
		if tg then
			table.insert(telegraphs, { data = data, tg = tg })
		end
	end
end

local function hideWeakMarkers(from: number)
	for k = from, #weakMarkers do
		for _, p in weakMarkers[k].parts do
			p.CFrame = HIDDEN
		end
	end
end

local function onBossState(payload: unknown)
	if type(payload) ~= "table" then
		return
	end
	local p = payload :: { [string]: any }
	if p.removed or p.defeated then
		clearBoss()
		clearTelegraphs()
		hideWeakMarkers(1)
		lastState = nil
		return
	end
	if type(p.bossId) ~= "string" then
		return
	end
	if p.bossId ~= bossKey then
		buildBoss(p.bossId)
	end
	if typeof(p.position) == "Vector3" then
		local now = os.clock()
		if not bossVisible then
			bossFrom = p.position
		else
			local a = math.clamp((now - bossT0) / (1 / Bosses.SendHz), 0, 1)
			bossFrom = bossFrom:Lerp(bossTo, a)
		end
		bossTo = p.position
		bossT0 = now
		bossVisible = true
	end
	if type(p.telegraphs) == "table" then
		setTelegraphs(p.telegraphs)
		local cast = p.telegraphs[1]
		if cast and type(cast.start) == "number" and type(cast.at) == "number" then
			if cast.start > castStart + .05 then
				castStart, castHit = cast.start, cast.at
			end
			castTarget = if typeof(cast.position) == "Vector3" then cast.position else nil
			castDirection = if typeof(cast.dir) == "Vector3" then cast.dir else nil
		end
	end
	local tint = p.vulnerable == true
	if tint ~= bossTint then
		bossTint = tint
		for k, part in bossParts do
			part.Color = if tint then bossColors[k]:Lerp(GOLD, 0.5) else bossColors[k]
		end
	end
	lastState = p
	-- Weak points
	local points = if type(p.weakPoints) == "table" then p.weakPoints else {}
	for k, wp in points do
		local marker = weakMarkers[k]
		if not marker then
			marker = clonePiece("Bosses.WeakPoint")
			if not marker then
				break
			end
			weakMarkers[k] = marker
		end
		local at = if typeof(wp.position) == "Vector3" and wp.ready then CFrame.new(wp.position + Vector3.new(0, 0.15, 0)) else nil
		for j, part in marker.parts do
			part.CFrame = if at then at * marker.offsets[j] else HIDDEN
		end
	end
	hideWeakMarkers(#points + 1)
end

-- Hazards --------------------------------------------------------------------------------------

local function saveLighting()
	if savedLighting then
		return
	end
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	savedLighting = {
		FogStart = Lighting.FogStart,
		FogEnd = Lighting.FogEnd,
		FogColor = Lighting.FogColor,
		Brightness = Lighting.Brightness,
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		AtmosphereDensity = if atmosphere then atmosphere.Density else nil,
	}
end

local function restoreLighting()
	local s = savedLighting
	if not s then
		return
	end
	Lighting.FogStart = s.FogStart
	Lighting.FogEnd = s.FogEnd
	Lighting.FogColor = s.FogColor
	Lighting.Brightness = s.Brightness
	Lighting.Ambient = s.Ambient
	Lighting.OutdoorAmbient = s.OutdoorAmbient
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere and s.AtmosphereDensity then
		atmosphere.Density = s.AtmosphereDensity
	end
	savedLighting = nil
end

local function applyHazard()
	local hazard = Workspace:GetAttribute("CohueHazard")
	local id = if type(hazard) == "string" then hazard else ""
	if id == currentHazard then
		return
	end
	restoreLighting()
	currentHazard = id
	if id == "" then
		return
	end
	local layout = Heightmap.getLayout()
	local world = layout and Worlds[layout.worldId]
	if not world then
		return
	end
	saveLighting()
	local hz = world.hazard
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if id == "Fog" or id == "Sandstorm" then
		local view = hz.viewDistance or 60
		Lighting.FogColor = if id == "Sandstorm" then Color3.fromRGB(220, 180, 120) else world.sky.fog
		Lighting.FogStart = view * 0.3
		Lighting.FogEnd = view
		if atmosphere then
			atmosphere.Density = 0.75 -- Atmosphere overrides FogEnd when present
		end
	elseif id == "Blackout" then
		Lighting.Brightness = 0.2
		Lighting.Ambient = Color3.fromRGB(15, 15, 30)
		Lighting.OutdoorAmbient = Color3.fromRGB(20, 20, 35)
	end
end

local function localRoot(): (BasePart?, Humanoid?)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") then
		return root, hum
	end
	return nil, hum
end

local function stepLocalCharacter(dt: number)
	local root, hum = localRoot()
	if not root or not hum or hum.Health <= 0 then
		return
	end
	-- Sandstorm push
	if currentHazard == "Sandstorm" then
		local layout = Heightmap.getLayout()
		local world = layout and Worlds[layout.worldId]
		local angle = Workspace:GetAttribute("CohueHazardAngle")
		if world and type(angle) == "number" then
			local push = (world.hazard.pushSpeed or 6) * dt
			root.CFrame += Vector3.new(math.cos(angle) * push, 0, math.sin(angle) * push)
		end
	end
	-- Jump pads
	local layout = Heightmap.getLayout()
	if layout and os.clock() >= padCooldown then
		local p = root.Position
		local feet = p.Y - hum.HipHeight - root.Size.Y / 2
		for _, pad in layout.pads do
			local dx, dz = p.X - pad.x, p.Z - pad.z
			if dx * dx + dz * dz <= PAD_RADIUS * PAD_RADIUS and feet <= pad.y + 2.5 then
				local up = math.sqrt(2 * Workspace.Gravity * (pad.h + 6))
				root.AssemblyLinearVelocity = Vector3.new(pad.dirX * PAD_SIDE_SPEED, up, pad.dirZ * PAD_SIDE_SPEED)
				padCooldown = os.clock() + 1
				break
			end
		end
	end
end

-- Frame ------------------------------------------------------------------------------------------

local function render(dt: number)
	applyHazard()
	stepLocalCharacter(dt)
	local n = 0
	local now = os.clock()

	local serverNow = Workspace:GetServerTimeNow()
	-- Boss
	if bossVisible and #bossParts > 0 then
		local a = math.clamp((now - bossT0) / (1 / Bosses.SendHz), 0, 1)
		local pos = bossFrom:Lerp(bossTo, a)
		local delta = bossTo - bossFrom
		local dir = Vector3.new(delta.X, 0, delta.Z)
		local speed = if a < 1 then dir.Magnitude * Bosses.SendHz else 0
		local st = lastState
		local casting = serverNow >= castStart and serverNow < castHit
		local striking = serverNow >= castHit and serverNow < castHit + .52
		if casting or striking then
			local target = castTarget or pos
			local aim = castDirection or (target - pos)
			if Vector3.new(aim.X, 0, aim.Z).Magnitude > .15 then
				dir = Vector3.new(aim.X, 0, aim.Z)
			end
		end
		if dir.Magnitude < .05 then
			local root = localRoot()
			dir = if root then Vector3.new(root.Position.X - pos.X, 0, root.Position.Z - pos.Z) else -Vector3.zAxis
		end
		local base = if dir.Magnitude > .05 then CFrame.lookAt(pos, pos + dir) else CFrame.new(pos)
		local profile = Motion.profiles[bossKey]
		local gesture = 0
		if st and st.stunned and not (casting or striking) then
			base *= CFrame.Angles(0, 0, math.rad(math.sin(now * 20) * 4))
		elseif profile then
			local weight = if casting or striking or (st and st.rooted) then 0 else math.clamp(speed / 5, 0, 1)
			bossWalkWeight += (weight - bossWalkWeight) * math.min(dt * 12, 1)
			bossStride = (bossStride + math.min(speed, 19) * dt) % profile.walk.stride
			if casting then
				local progress = math.clamp((serverNow - castStart) / math.max(.05, castHit - castStart), 0, 1)
				base *= Motion.charge(profile, progress, 1)
				gesture = -progress
			elseif striking then
				local progress = (serverNow - castHit) / .52
				base *= Motion.strike(profile, progress, 1)
				gesture = math.sin(math.pi * progress)
			else
				local walk = Motion.walk(profile, bossStride, bossWalkWeight, now, 1)
				base *= walk
			end
		end
		for k, part in bossParts do
			local offset = bossOffsets[k]
			-- Pièce mobile nommée dans le modèle (règle de la Directrice, louche...) : elle suit le geste.
			if gesture ~= 0 and (part.Name == "Ruler" or part.Name == "Arm") then
				offset *= CFrame.Angles(math.rad(-45 * gesture), 0, math.rad(22 * gesture))
			end
			n += 1
			moveParts[n] = part
			moveCFrames[n] = base * offset
		end
	end

	-- Telegraphs (fill grows from start to impact)
	for _, t in telegraphs do
		local d = t.data
		local pos: Vector3 = d.position
		local start = if type(d.start) == "number" then d.start else serverNow
		local hitAt = if type(d.at) == "number" then d.at else serverNow
		local u = math.clamp((serverNow - start) / math.max(0.05, hitAt - start), 0, 1)
		local y = Heightmap.getY(pos.X, pos.Z) + 0.12
		local color = if typeof(d.color) == "Color3" then d.color else Bosses.Colors.Normal
		if d.kind == "Line" then
			if typeof(d.dir) ~= "Vector3" or type(d.length) ~= "number" then
				continue
			end
			local dir = Vector3.new(d.dir.X, 0, d.dir.Z)
			if dir.Magnitude < 1e-3 then
				continue
			end
			Effects.placeLine(t.tg, Vector3.new(pos.X, y, pos.Z), dir.Unit, d.radius, d.length, u, color)
		else
			local inner = if type(d.inner) == "number" then d.inner else 0
			Effects.placeDisc(t.tg, CFrame.new(pos.X, y, pos.Z), d.radius, inner, u, color)
		end
	end

	-- Revealed Arche beam
	local beam = archeBeam
	if beam then
		local showBeam = runState.bossRevealed == true
			and typeof(runState.bossPosition) == "Vector3"
			and (runState.phase == "Running" or runState.phase == "FinalWave")
		local at: CFrame? = nil
		if showBeam then
			local p: Vector3 = runState.bossPosition
			at = CFrame.new(p.X, Heightmap.getY(p.X, p.Z), p.Z)
		end
		for k, part in beam.parts do
			n += 1
			moveParts[n] = part
			moveCFrames[n] = if at then at * beam.offsets[k] else HIDDEN
		end
	end

	for i = n + 1, #moveParts do
		moveParts[i] = nil :: any
		moveCFrames[i] = nil :: any
	end
	if n > 0 then
		-- PERF-06 : personne n'écoute le CFrame de ces pièces.
		Workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function BossRenderer.init()
	container = Instance.new("Folder") -- dossier de rangement vide : invisible
	container.Name = "ClientBoss"
	container.Parent = Workspace
	archeBeam = clonePiece("Bosses.ArcheBeam")
end

function BossRenderer.start()
	Net.event("BossState").OnClientEvent:Connect(onBossState)
	Net.event("RunState").OnClientEvent:Connect(function(payload: unknown)
		if type(payload) == "table" then
			runState = payload :: { [string]: any }
			if runState.phase == "Ended" or runState.phase == "Loadout" then
				clearBoss()
				clearTelegraphs()
			end
		end
	end)
	RunService.PreRender:Connect(render)
end

return BossRenderer
