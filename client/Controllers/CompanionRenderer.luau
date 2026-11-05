--!strict
-- Affiche les compagnons (CompanionSnapshot) et les cages de capture (CageState).
-- docs/dossier/40-compagnons.md §7 et §8. Règle « rien construit par script » (01-decisions-v2 §12) :
-- tout ce qui se voit est cloné depuis ReplicatedStorage.Assets (ArtLibrary). Gabarit absent :
-- avertissement une fois, rien d'affiché à la place. Seul un dossier de rangement est créé.
--
-- Gabarits : Companion_<espèce> (repli Enemy_<espèce>), FX_CaptureCage, FX_CaptureSuccess,
-- FX_CompanionStun, FX_CompanionHit (noms dans Config/Companions.Render).
-- Interpolation entre deux échantillons serveur, un seul BulkMoveTo par frame.
-- HUD : CompanionRenderer.getState() / onStateChanged(fn) (payload CompanionState).
--
-- Mode lobby (65-lobby.md §10, dossier 40 §8.1), client seul : hors run, le(s) compagnon(s) équipé(s)
-- (Profile.companions.equipped) suivent le joueur local et le reste de sa collection se promène dans
-- l'enclos (LobbyRole = "CritterPen"). Positions locales, aucun remote envoyé.
--
-- Personnalisation (A05-05, dossier 40 §8.2) : chapeau (Assets.Cosmetics.CompanionHats.<id>), couleur
-- (Config/Cosmetics def.color) et aura (Assets.FX.CompanionAuras.<id>) par compagnon. En run : attribut
-- CompanionLook<slot> du propriétaire (posé par CompanionService) ; au lobby : Profile.equipped.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Companions = require(Config:WaitForChild("Companions"))
local Enemies = require(Config:WaitForChild("Enemies"))
local Heightmap = require(Shared:WaitForChild("Heightmap"))
local Net = require(Shared:WaitForChild("Net"))
local ArtLibrary = require(Shared:WaitForChild("ArtLibrary"))

local NET = Companions.Net
local R = Companions.Render
local LOBBY = Companions.Lobby
local LOOK = Companions.Look
local FOLLOW = Companions.Follow
local HIDDEN = CFrame.new(0, -10000, 0)
local TWO_PI = math.pi * 2

export type State = { [string]: any } -- payload CompanionState (dossier 40 §7)

type Visual = {
	parts: { BasePart },
	offsets: { CFrame },
	height: number,
}

-- Personnalisation (A05-05) : chapeau et aura clonés, posés avec le corps.
type Dress = { hat: Visual?, aura: Visual? }

type Entry = {
	key: number,
	kind: number,
	body: Visual?,
	dress: Dress?,
	look: string, -- valeur de CompanionLook<slot> appliquée
	stun: Visual?,
	fromPos: Vector3,
	toPos: Vector3,
	fromYaw: number,
	toYaw: number,
	t0: number,
	lastSeen: number,
	stunned: boolean,
	evSeq: number,
	phase: number,
}

type CageView = {
	id: number,
	visual: Visual?,
	position: Vector3,
	expiresAt: number,
}

type Fx = { visual: Visual, untilT: number, cf: CFrame }

-- Créature du lobby : suiveur (slot 1 ou 2) ou promeneur de l'enclos (slot nil).
type LobbyPet = {
	species: string,
	body: Visual?,
	dress: Dress?,
	slot: number?,
	flying: boolean,
	pos: Vector3,
	yaw: number,
	goal: Vector3?,
	waitUntil: number,
	moving: boolean,
	phase: number,
}

type Roam = { cf: CFrame, halfX: number, halfZ: number, center: Vector3 }

local CompanionRenderer = {}

local container: Folder
local entries: { [number]: Entry } = {}
local cageViews: { [number]: CageView } = {}
local hitPool: { Fx } = {}
local hitNext = 1
local successes: { Fx } = {}
local state: State? = nil
local listeners: { (State) -> () } = {}
local warned: { [string]: boolean } = {}

local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

-- Lobby
local speciesKind: { [string]: number } = {}
local runPhase = "Loadout"
local collection: { owned: { [string]: any }, equipped: { string }, cosmetics: { [string]: any } }? = nil
local lobbyPets: { LobbyPet } = {}
local lobbySignature = ""
local lobbyShown = false
local roam: Roam? = nil
local nextPenSearch = 0

local function warnOnce(name: string)
	if not warned[name] then
		warned[name] = true
		warn(`[CompanionRenderer] template "{name}" missing in ReplicatedStorage.Assets (nothing drawn)`)
	end
end

local function cloneVisual(name: string, height: number?): Visual?
	local parts, offsets, h = ArtLibrary.cloneParts(name, height)
	if not parts or not offsets then
		return nil
	end
	for _, p in parts do
		p.CFrame = HIDDEN
		p.Parent = container
	end
	return { parts = parts, offsets = offsets, height = h or height or 0 }
end

local function destroyVisual(v: Visual?)
	if v then
		for _, p in v.parts do
			p:Destroy()
		end
	end
end

local function place(v: Visual?, cf: CFrame)
	if not v then
		return
	end
	for k, p in v.parts do
		table.insert(moveParts, p)
		table.insert(moveCFrames, cf * v.offsets[k])
	end
end

-- Personnalisation (A05-05, dossier 40 §8.2) -------------------------------------------------------
-- Chapeau : Assets.Cosmetics.CompanionHats.<id> (pivot au bas du chapeau), posé en haut du corps.
-- Couleur : def.color de Config/Cosmetics sur les pièces du corps marquées Tint = true (sinon toutes).
-- Aura : Assets.FX.CompanionAuras.<id> (pivot aux pieds), ses particules suivent le corps.
-- Objet absent : avertissement une fois, le compagnon reste dessiné sans cet ajout.

local function lookTemplate(group: string, folder: string, id: string): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local g = assets and assets:FindFirstChild(group)
	local f = g and g:FindFirstChild(folder)
	local t = f and f:FindFirstChild(id)
	if t and (t:IsA("Model") or t:IsA("BasePart")) then
		return t
	end
	warnOnce(`{group}.{folder}.{id}`)
	return nil
end

local function cloneDressPart(template: Instance, scale: number): Visual?
	local parts, offsets = ArtLibrary.clonePivoted(template, scale)
	if #parts == 0 then
		return nil
	end
	for _, p in parts do
		p.CFrame = HIDDEN
		p.Parent = container
	end
	return { parts = parts, offsets = offsets, height = 0 }
end

local function tint(body: Visual, color: Color3)
	local marked = false
	for _, p in body.parts do
		if p:GetAttribute(LOOK.TintAttribute) == true then
			marked = true
			p.Color = color
		end
	end
	if not marked then
		for _, p in body.parts do
			p.Color = color
		end
	end
end

-- Habille un corps fraîchement cloné selon une valeur CompanionLook ("" = rien).
local function dress(body: Visual?, look: string): Dress?
	if not body or look == "" then
		return nil
	end
	local hatId, colorId, auraId = LOOK.decode(look)
	local color = LOOK.color(colorId)
	if color then
		tint(body, color)
	end
	local scale = math.clamp(body.height / R.HatRefHeight, R.HatScaleMin, R.HatScaleMax)
	local hatT = if hatId then lookTemplate("Cosmetics", LOOK.HatFolder, hatId) else nil
	local auraT = if auraId then lookTemplate("FX", LOOK.AuraFolder, auraId) else nil
	return {
		hat = if hatT then cloneDressPart(hatT, scale) else nil,
		aura = if auraT then cloneDressPart(auraT, scale) else nil,
	}
end

local function undress(d: Dress?)
	if d then
		destroyVisual(d.hat)
		destroyVisual(d.aura)
	end
end

local function placeDressed(body: Visual?, d: Dress?, cf: CFrame)
	place(body, cf)
	if d and body then
		if d.hat then
			place(d.hat, cf * CFrame.new(0, body.height * (1 - R.HatSink), 0))
		end
		place(d.aura, cf)
	end
end

-- Compagnons -------------------------------------------------------------------------------------

local function bodyFor(kind: number): Visual?
	local def = Enemies[kind]
	if not def then
		return nil
	end
	local override = Companions.Species[def.name]
	local height = if override and override.height then override.height else def.height * R.HeightScale
	local v = cloneVisual(R.ModelPrefix .. def.name, height) or cloneVisual(R.EnemyPrefix .. def.name, height)
	if not v then
		warnOnce(R.EnemyPrefix .. def.name)
	end
	return v
end

local function removeEntry(key: number)
	local e = entries[key]
	if e then
		destroyVisual(e.body)
		undress(e.dress)
		destroyVisual(e.stun)
		entries[key] = nil
	end
end

-- Aspect publié par le serveur sur le propriétaire (CompanionService, attribut CompanionLook<slot>).
local function lookOf(userId: number, slot: number): string
	local owner = Players:GetPlayerByUserId(userId)
	local v = owner and owner:GetAttribute(LOOK.AttributePrefix .. slot)
	return if type(v) == "string" then v else ""
end

-- (Re)habille une entrée quand son aspect change : corps recloné pour retrouver ses couleurs d'origine.
local function applyLook(e: Entry, look: string)
	if e.look == look then
		return
	end
	local old = e.look
	e.look = look
	undress(e.dress)
	e.dress = nil
	if old ~= "" then
		-- l'ancien aspect a pu teindre le corps : nouveau clone, couleurs d'origine
		destroyVisual(e.body)
		e.body = bodyFor(e.kind)
	end
	e.dress = dress(e.body, look)
end

local function spawnHit(x: number, z: number)
	if #hitPool == 0 then
		return
	end
	local fx = hitPool[hitNext]
	hitNext = hitNext % #hitPool + 1
	fx.cf = CFrame.new(x, Heightmap.getY(x, z), z)
	fx.untilT = os.clock() + R.HitSeconds
end

local function onSnapshot(b: buffer)
	if typeof(b) ~= "buffer" or buffer.len(b) < NET.HeaderBytes then
		return
	end
	local count = buffer.readu8(b, 4)
	if buffer.len(b) < NET.HeaderBytes + count * NET.RecordBytes then
		return
	end
	local now = os.clock()
	local scale = NET.PositionScale
	local o = NET.HeaderBytes
	for _ = 1, count do
		local userId = buffer.readf64(b, o)
		local slot = buffer.readu8(b, o + 8)
		local kind = buffer.readu8(b, o + 9)
		local pos = Vector3.new(buffer.readi16(b, o + 10) / scale, buffer.readi16(b, o + 12) / scale, buffer.readi16(b, o + 14) / scale)
		local yaw = buffer.readu8(b, o + 16) / 256 * TWO_PI
		local flags = buffer.readu8(b, o + 17)
		local evSeq = buffer.readu8(b, o + 18)
		local evKind = buffer.readu8(b, o + 19)
		local evX = buffer.readi16(b, o + 20) / scale
		local evZ = buffer.readi16(b, o + 22) / scale
		o += NET.RecordBytes

		local key = userId * 4 + slot
		local e = entries[key]
		if e and e.kind ~= kind then
			removeEntry(key)
			e = nil
		end
		if not e then
			local fresh: Entry = {
				key = key,
				kind = kind,
				body = bodyFor(kind),
				dress = nil,
				look = "",
				stun = nil,
				fromPos = pos,
				toPos = pos,
				fromYaw = yaw,
				toYaw = yaw,
				t0 = now,
				lastSeen = now,
				stunned = false,
				evSeq = evSeq,
				phase = math.random() * TWO_PI,
			}
			entries[key] = fresh
			e = fresh
		end
		local entry = e :: Entry
		applyLook(entry, lookOf(userId, slot))
		-- Repart de la position affichée actuelle vers le nouvel échantillon.
		local alpha = math.clamp((now - entry.t0) / R.InterpDelay, 0, 1)
		entry.fromPos = entry.fromPos:Lerp(entry.toPos, alpha)
		entry.fromYaw = entry.fromYaw + (((entry.toYaw - entry.fromYaw + math.pi) % TWO_PI) - math.pi) * alpha
		entry.toPos = pos
		entry.toYaw = yaw
		entry.t0 = now
		entry.lastSeen = now
		local stunned = bit32.band(flags, NET.StunnedBit) ~= 0
		if stunned and not entry.stun then
			entry.stun = cloneVisual(R.StunTemplate)
			if not entry.stun then
				warnOnce(R.StunTemplate)
			end
		elseif not stunned and entry.stun then
			destroyVisual(entry.stun)
			entry.stun = nil
		end
		entry.stunned = stunned
		if evSeq ~= entry.evSeq then
			entry.evSeq = evSeq
			if evKind ~= NET.EvNone then
				spawnHit(evX, evZ)
			end
		end
	end
end

-- Cages ------------------------------------------------------------------------------------------

local function spawnSuccess(position: Vector3)
	local v = cloneVisual(R.CageSuccessTemplate)
	if not v then
		warnOnce(R.CageSuccessTemplate)
		return
	end
	table.insert(successes, { visual = v, untilT = os.clock() + R.SuccessSeconds, cf = CFrame.new(position) })
end

local function onCageState(payload: any)
	if type(payload) ~= "table" or type(payload.cages) ~= "table" then
		return
	end
	local myId = Players.LocalPlayer.UserId
	local now = os.clock()
	local seen: { [number]: boolean } = {}
	for _, c in payload.cages do
		if type(c) ~= "table" or type(c.id) ~= "number" then
			continue
		end
		local mine = type(c.done) == "table" and table.find(c.done, myId) ~= nil
		local view = cageViews[c.id]
		if mine then
			-- Capturée par le joueur local : éclat de réussite, la cage disparaît pour lui.
			if view then
				spawnSuccess(view.position)
				destroyVisual(view.visual)
				cageViews[c.id] = nil
			end
			continue
		end
		seen[c.id] = true
		local position = Vector3.new(tonumber(c.x) or 0, tonumber(c.y) or 0, tonumber(c.z) or 0)
		if not view then
			local visual = cloneVisual(R.CageTemplate)
			if not visual then
				warnOnce(R.CageTemplate)
			end
			view = { id = c.id, visual = visual, position = position, expiresAt = 0 }
			cageViews[c.id] = view
		end
		local v = view :: CageView
		v.position = position
		v.expiresAt = now + (tonumber(c.expiresIn) or 0)
	end
	for id, view in cageViews do
		if not seen[id] then
			destroyVisual(view.visual)
			cageViews[id] = nil
		end
	end
end

-- Lobby ------------------------------------------------------------------------------------------

-- En run : phase de jeu, attribut InRun du joueur (s'il existe), ou compagnon local dans le snapshot.
local function localInRun(now: number): boolean
	local player = Players.LocalPlayer
	local attr = player:GetAttribute("InRun")
	if type(attr) == "boolean" then
		if attr then
			return true
		end
	elseif Companions.Capture.Phases[runPhase] then
		return true
	end
	local myId = player.UserId
	for _, e in entries do
		if e.key // 4 == myId and now - e.lastSeen <= R.StaleSeconds then
			return true
		end
	end
	return false
end

local function findRoam(): Roam?
	local village = Workspace:FindFirstChild("HubbubVillage")
	for _, inst in (village or Workspace):GetDescendants() do
		if inst:GetAttribute("LobbyRole") == LOBBY.PenRole and (inst:IsA("Model") or inst:IsA("BasePart")) then
			for _, name in LOBBY.RoamPartNames do
				local part = inst:FindFirstChild(name, true)
				if part and part:IsA("BasePart") then
					local cf = part.CFrame * CFrame.new(0, part.Size.Y / 2, 0)
					return { cf = cf, halfX = part.Size.X / 2, halfZ = part.Size.Z / 2, center = cf.Position }
				end
			end
			local cf: CFrame, size: Vector3
			if inst:IsA("Model") then
				cf, size = inst:GetBoundingBox()
			else
				local p = inst :: BasePart
				cf, size = p.CFrame, p.Size
			end
			local floor = cf * CFrame.new(0, -size.Y / 2, 0)
			return { cf = floor, halfX = size.X / 2, halfZ = size.Z / 2, center = floor.Position }
		end
	end
	return nil
end

local function randomRoamPoint(r: Roam): Vector3
	local hx = math.max(0, r.halfX - LOBBY.Margin)
	local hz = math.max(0, r.halfZ - LOBBY.Margin)
	return (r.cf * CFrame.new((math.random() * 2 - 1) * hx, 0, (math.random() * 2 - 1) * hz)).Position
end

local function clearLobby()
	for _, pet in lobbyPets do
		destroyVisual(pet.body)
		undress(pet.dress)
	end
	table.clear(lobbyPets)
	lobbySignature = ""
end

local function newPet(species: string, slot: number?, pos: Vector3): LobbyPet?
	local kind = speciesKind[species]
	if not kind then
		return nil -- espèce inconnue (ancien id v1) : ignorée
	end
	local body = bodyFor(kind)
	local c = collection
	-- Suiveurs : emplacement propre puis global ; enclos : emplacement propre seulement.
	local look = LOOK.encode(if c then c.cosmetics else nil, species, slot == nil)
	local override = Companions.Species[species]
	return {
		species = species,
		body = body,
		dress = dress(body, look),
		slot = slot,
		flying = override ~= nil and override.flying == true,
		pos = pos,
		yaw = math.random() * TWO_PI,
		goal = nil,
		waitUntil = os.clock() + math.random() * LOBBY.WaitMax,
		moving = false,
		phase = math.random() * TWO_PI,
	}
end

-- (Re)crée les créatures du lobby quand la collection ou l'équipement change.
local function rebuildLobby()
	local c = collection
	local equipped: { string } = if c and type(c.equipped) == "table" then c.equipped else {}
	local owned: { [string]: any } = if c and type(c.owned) == "table" then c.owned else {}
	-- Promeneurs : espèces possédées non équipées, les plus récentes d'abord.
	local pen: { string } = {}
	for species in owned do
		if type(species) == "string" and speciesKind[species] and not table.find(equipped, species) then
			table.insert(pen, species)
		end
	end
	table.sort(pen, function(a, b)
		local ea, eb = owned[a], owned[b]
		local ta = if type(ea) == "table" then tonumber(ea.at) or 0 else 0
		local tb = if type(eb) == "table" then tonumber(eb.at) or 0 else 0
		if ta ~= tb then
			return ta > tb
		end
		return a < b
	end)
	while #pen > LOBBY.MaxPenPets do
		table.remove(pen)
	end
	local signature = table.concat(equipped, ",") .. "|" .. table.concat(pen, ",") .. "|" .. (if roam then "pen" else "")
	-- Aspect (A05-05) : un changement de chapeau, de couleur ou d'aura refait les créatures.
	local looks = table.create(#equipped + #pen)
	for k, species in equipped do
		looks[k] = if type(species) == "string" then LOOK.encode(c and c.cosmetics, species) else ""
	end
	for _, species in pen do
		table.insert(looks, LOOK.encode(c and c.cosmetics, species, true))
	end
	signature ..= "|" .. table.concat(looks, ",")
	if signature == lobbySignature then
		return
	end
	clearLobby()
	lobbySignature = signature
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local start = if root and root:IsA("BasePart") then root.Position - Vector3.new(0, 3, 0) else Vector3.zero
	for slot, species in equipped do
		if slot <= 2 and type(species) == "string" then
			local pet = newPet(species, slot, start)
			if pet then
				table.insert(lobbyPets, pet)
			end
		end
	end
	local r = roam
	if r then
		for _, species in pen do
			local pet = newPet(species, nil, randomRoamPoint(r))
			if pet then
				table.insert(lobbyPets, pet)
			end
		end
	end
end

local function hopOffset(pet: LobbyPet, now: number): number
	return if pet.moving then math.abs(math.sin(now * R.HopHz * math.pi + pet.phase)) * R.HopHeight else 0
end

local function stepFollower(pet: LobbyPet, root: BasePart, dt: number)
	local p = root.Position
	local look = root.CFrame.LookVector
	local fx, fz = look.X, look.Z
	local len = math.sqrt(fx * fx + fz * fz)
	if len < 1e-3 then
		fx, fz = 0, -1
	else
		fx, fz = fx / len, fz / len
	end
	local side = if pet.slot == 1 then -1 else 1
	local y = p.Y - 3 + (if pet.flying then FOLLOW.FlyHeight else 0)
	local goal = Vector3.new(p.X - fx * FOLLOW.Behind + (-fz) * FOLLOW.Side * side, y, p.Z - fz * FOLLOW.Behind + fx * FOLLOW.Side * side)
	local delta = goal - pet.pos
	local flat = Vector3.new(delta.X, 0, delta.Z)
	local d = flat.Magnitude
	if d > FOLLOW.SnapDistance then
		pet.pos = goal
		pet.moving = false
		return
	end
	if d > 0.05 then
		local stepLen = math.min(d, FOLLOW.Speed * dt)
		local nx, nz = pet.pos.X + flat.X / d * stepLen, pet.pos.Z + flat.Z / d * stepLen
		pet.pos = Vector3.new(nx, pet.pos.Y + math.clamp(delta.Y, -30 * dt, 30 * dt), nz)
		if d > 0.5 then
			pet.yaw = math.atan2(-flat.X, -flat.Z)
		end
	else
		pet.pos = Vector3.new(pet.pos.X, pet.pos.Y + math.clamp(delta.Y, -30 * dt, 30 * dt), pet.pos.Z)
	end
	pet.moving = d > 0.3
end

local function stepWanderer(pet: LobbyPet, r: Roam, dt: number, now: number)
	if not pet.goal then
		if now >= pet.waitUntil then
			pet.goal = randomRoamPoint(r)
		end
		pet.moving = false
		return
	end
	local goal = pet.goal :: Vector3
	local flat = Vector3.new(goal.X - pet.pos.X, 0, goal.Z - pet.pos.Z)
	local d = flat.Magnitude
	if d < 0.2 then
		pet.goal = nil
		pet.waitUntil = now + LOBBY.WaitMin + math.random() * (LOBBY.WaitMax - LOBBY.WaitMin)
		pet.moving = false
		return
	end
	local stepLen = math.min(d, LOBBY.WanderSpeed * dt)
	pet.pos = Vector3.new(pet.pos.X + flat.X / d * stepLen, goal.Y, pet.pos.Z + flat.Z / d * stepLen)
	pet.yaw = math.atan2(-flat.X, -flat.Z)
	pet.moving = true
end

local function stepLobby(dt: number, now: number)
	local show = collection ~= nil and not localInRun(now)
	if not show then
		if lobbyShown then
			clearLobby()
			lobbyShown = false
		end
		return
	end
	if not roam and now >= nextPenSearch then
		nextPenSearch = now + LOBBY.PenSearchSeconds
		roam = findRoam()
		if roam then
			lobbySignature = "" -- l'enclos vient d'apparaître : refaire les promeneurs
		end
	end
	if not lobbyShown or lobbySignature == "" then
		rebuildLobby()
		lobbyShown = true
	end
	local character = Players.LocalPlayer.Character
	local rootInst = character and character:FindFirstChild("HumanoidRootPart")
	local root: BasePart? = if rootInst and rootInst:IsA("BasePart") then rootInst else nil
	local r = roam
	local penAwake = r ~= nil and root ~= nil and (root.Position - r.center).Magnitude <= LOBBY.PauseDistance
	for _, pet in lobbyPets do
		if pet.slot then
			if root then
				stepFollower(pet, root, dt)
				placeDressed(pet.body, pet.dress, CFrame.new(pet.pos.X, pet.pos.Y + hopOffset(pet, now), pet.pos.Z) * CFrame.Angles(0, pet.yaw, 0))
			end
		elseif penAwake and r then
			-- Loin de l'enclos : rien ne bouge (les pièces restent où elles sont, aucun déplacement).
			stepWanderer(pet, r, dt, now)
			placeDressed(pet.body, pet.dress, CFrame.new(pet.pos.X, pet.pos.Y + hopOffset(pet, now), pet.pos.Z) * CFrame.Angles(0, pet.yaw, 0))
		end
	end
end

local function onProfile(profile: any)
	if type(profile) ~= "table" or type(profile.companions) ~= "table" then
		return
	end
	local c = profile.companions
	collection = {
		owned = if type(c.owned) == "table" then c.owned else {},
		equipped = if type(c.equipped) == "table" then c.equipped else {},
		cosmetics = if type(profile.equipped) == "table" then profile.equipped else {},
	}
	if lobbyShown then
		rebuildLobby()
	end
end

-- Frame ------------------------------------------------------------------------------------------

local function render(dt: number)
	table.clear(moveParts)
	table.clear(moveCFrames)
	local now = os.clock()
	for key, e in entries do
		if now - e.lastSeen > R.StaleSeconds then
			removeEntry(key)
			continue
		end
		local alpha = math.clamp((now - e.t0) / R.InterpDelay, 0, 1)
		local pos = e.fromPos:Lerp(e.toPos, alpha)
		local yaw = e.fromYaw + (((e.toYaw - e.fromYaw + math.pi) % TWO_PI) - math.pi) * alpha
		local moving = (e.toPos - e.fromPos).Magnitude > 0.2
		local hop = if moving and not e.stunned then math.abs(math.sin(now * R.HopHz * math.pi + e.phase)) * R.HopHeight else 0
		local cf = CFrame.new(pos.X, pos.Y + hop, pos.Z) * CFrame.Angles(0, yaw, 0)
		placeDressed(e.body, e.dress, cf)
		if e.stun then
			local h = if e.body then e.body.height else 2
			place(e.stun, CFrame.new(pos.X, pos.Y + h + 0.5, pos.Z) * CFrame.Angles(0, now * 3, 0))
		end
	end
	for _, view in cageViews do
		local left = view.expiresAt - now
		local blinkOff = left < R.CageBlinkSeconds and math.floor(now * 6) % 2 == 0
		place(view.visual, if blinkOff then HIDDEN else CFrame.new(view.position))
	end
	for _, fx in hitPool do
		place(fx.visual, if now < fx.untilT then fx.cf else HIDDEN)
	end
	for k = #successes, 1, -1 do
		local fx = successes[k]
		if now >= fx.untilT then
			destroyVisual(fx.visual)
			table.remove(successes, k)
		else
			place(fx.visual, fx.cf)
		end
	end
	stepLobby(math.min(dt, 0.1), now)
	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- API --------------------------------------------------------------------------------------------

function CompanionRenderer.getState(): State?
	return state
end

function CompanionRenderer.onStateChanged(fn: (State) -> ())
	table.insert(listeners, fn)
end

-- Plus d'Ultime en v2 (dossier 40 §5.3) : gardé pour UIInput, sans effet.
function CompanionRenderer.requestUltimate() end

function CompanionRenderer.start()
	container = Instance.new("Folder")
	container.Name = "COHUE_Companions"
	container.Parent = Workspace

	for kind, def in Enemies do
		if type(kind) == "number" and def.family ~= "Boss" and def.isBoss ~= true then
			speciesKind[def.name] = kind
		end
	end

	for _ = 1, R.HitPool do
		local v = cloneVisual(R.HitTemplate)
		if not v then
			warnOnce(R.HitTemplate)
			break
		end
		table.insert(hitPool, { visual = v, untilT = 0, cf = HIDDEN })
	end

	Net.unreliable("CompanionSnapshot").OnClientEvent:Connect(onSnapshot)
	Net.event("CageState").OnClientEvent:Connect(onCageState)
	Net.event("Profile").OnClientEvent:Connect(onProfile)
	Net.event("RunState").OnClientEvent:Connect(function(payload: any)
		if type(payload) == "table" and type(payload.phase) == "string" then
			runPhase = payload.phase
		end
	end)
	Net.event("RunSummary").OnClientEvent:Connect(function()
		runPhase = "Ended"
	end)
	Net.event("CompanionState").OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		state = payload
		for _, fn in listeners do
			task.spawn(fn, payload)
		end
	end)
	-- Profile et RunState ont pu arriver avant nous (un événement en file ne va qu'au premier écouteur) :
	-- on relit la dernière valeur gardée par UITheme, s'il est là (lecture seule).
	local ui = script.Parent:FindFirstChild("UI")
	local themeModule = ui and ui:FindFirstChild("UITheme")
	if themeModule and themeModule:IsA("ModuleScript") then
		local ok, theme = pcall(require, themeModule)
		if ok and type(theme) == "table" and type((theme :: any).last) == "function" then
			local okP, profile = pcall((theme :: any).last, "Profile")
			if okP and collection == nil then
				onProfile(profile)
			end
			local okR, runState = pcall((theme :: any).last, "RunState")
			if okR and type(runState) == "table" and type(runState.phase) == "string" then
				runPhase = runState.phase
			end
		end
	end
	RunService.RenderStepped:Connect(render)
end

return CompanionRenderer
