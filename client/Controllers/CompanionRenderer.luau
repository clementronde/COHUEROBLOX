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
local HIDDEN = CFrame.new(0, -10000, 0)
local TWO_PI = math.pi * 2

export type State = { [string]: any } -- payload CompanionState (dossier 40 §7)

type Visual = {
	parts: { BasePart },
	offsets: { CFrame },
	height: number,
}

type Entry = {
	key: number,
	kind: number,
	body: Visual?,
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
		destroyVisual(e.stun)
		entries[key] = nil
	end
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

-- Frame ------------------------------------------------------------------------------------------

local function render()
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
		place(e.body, cf)
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
	Net.event("CompanionState").OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		state = payload
		for _, fn in listeners do
			task.spawn(fn, payload)
		end
	end)
	RunService.RenderStepped:Connect(render)
end

return CompanionRenderer
