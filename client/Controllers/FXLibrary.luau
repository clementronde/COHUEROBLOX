--!strict
-- Bibliothèque d'effets client (A07-01, dossier 12 §15). Module simple : pas dans la liste de
-- client/Main ; WeaponFX, EnemyAttackFX et CompanionRenderer le requièrent et appellent start()
-- (sans effet la 2e fois).
--
-- Rien n'est construit ici (décisions v2 §12) : les effets sont des objets posés par Clément dans
-- ReplicatedStorage.Assets.FX. Ce module :
--   * tient le réglage de qualité (Auto / Low / Medium / High), lu dans Profile.settings.fxQuality ;
--   * compte les particules vivantes (rafales :Emit + émetteurs continus suivis) et les effets actifs,
--     contre un budget global par palier (docs/qa/budgets-perf.md §7) ;
--   * coupe d'abord ce qui compte le moins : priorité Telegraph (jamais coupé) > Local (joueur local)
--     > Normal > Far (Normal à plus de FAR_DISTANCE studs du joueur local) > Ambient (auras, décor).
-- Sous le budget, rien ne change : une rafale demandée est émise en entier.
-- Il sait aussi cloner et mettre en pool un effet par chemin (take / give / play).
--
-- API :
--   start()                                    idempotent
--   getQuality() -> "Low" | "Medium" | "High"  palier en vigueur (Auto = palier détecté)
--   isAuto() -> boolean
--   setQuality("Auto" | "Low" | "Medium" | "High")   réglage local immédiat (l'écran de réglages l'appelle)
--   onQualityChanged(fn(quality))
--   tier() -> { particles, maxParticles, maxEffects }
--   domain("Enemy") -> { particles, limit }     facteurs d'un domaine (Auto = rendu d'avant A07-01)
--   emit(emitter, n, priority, position?) -> émis   rafale sous budget
--   canSpawn(priority, position?) -> boolean   un effet de plus (pièces) sous budget ?
--   addActive(delta)                           compte des effets actifs (pris +1, rendus -1)
--   track(parts, priority) -> Tracked          émetteurs continus d'un objet cloné (taux × qualité, coupés
--   untrack(tracked)                           sous pression) ; setTrackedPosition(tracked, position)
--   take(path) -> Model? / give(model)         clone en pool d'un effet Assets.FX.<path>
--   play(path, cframe, priority?, radius?) -> boolean   effet ponctuel : rafales Burst, rendu après Life
--   stats() -> { particles, effects, quality }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArtLibrary = require(Shared:WaitForChild("ArtLibrary"))
local Net = require(Shared:WaitForChild("Net"))

export type Quality = "Low" | "Medium" | "High"
export type Priority = "Telegraph" | "Local" | "Normal" | "Ambient"
export type Tier = { particles: number, maxParticles: number, maxEffects: number }
export type Domain = { particles: number, limit: number? }

type Tracked = {
	emitters: { ParticleEmitter },
	rates: { number },
	rank: number,
	position: Vector3?,
	cost: number, -- particules vivantes estimées quand allumé (Rate × Lifetime.Max)
	on: boolean,
}
export type TrackedHandle = Tracked

-- Budgets : docs/qa/budgets-perf.md §7. Low = chiffre du doc (≤ 600 particules vivantes) ; Medium et
-- High sont des hypothèses à mesurer (A13-01). maxEffects = somme des plafonds actuels des domaines
-- (WeaponFX + EnemyAttackFX + marge) : il ne coupe qu'en cas de débordement.
local TIERS: { [Quality]: Tier } = {
	Low = { particles = 0.5, maxParticles = 600, maxEffects = 200 },
	Medium = { particles = 0.8, maxParticles = 1000, maxEffects = 340 },
	High = { particles = 1, maxParticles = 1600, maxEffects = 600 },
}

-- Domaines dont le rendu n'avait pas de palier avant A07-01. En Auto ils gardent ce rendu (facteur 1,
-- plafond d'origine) ; un palier choisi par le joueur les baisse.
local DOMAINS: { [string]: { [Quality]: Domain } } = {
	Enemy = {
		Low = { particles = 0.6, limit = 12 },
		Medium = { particles = 1, limit = 18 },
		High = { particles = 1, limit = 18 },
	},
}
local AUTO_DOMAIN: Domain = { particles = 1, limit = nil }

-- Rang de priorité : 1 = Telegraph (jamais coupé) … 5 = Ambient. Part du budget utilisable par rang.
local RANK: { [string]: number } = { Telegraph = 1, Local = 2, Normal = 3, Far = 4, Ambient = 5 }
local SHARE = { 1, 1, 0.85, 0.6, 0.5 }
local FAR_RANK = 4
local FAR_DISTANCE = 120 -- studs (à plat) du joueur local : un effet Normal plus loin passe Far
local RELIGHT = 0.8 -- un émetteur coupé se rallume sous 80 % de sa part (pas de clignotement)
local TRACK_HZ = 4

-- Rafales en cours : seaux de 0,1 s sur 6,4 s (une rafale compte jusqu'à Lifetime.Max).
local BUCKET = 0.1
local NB = 64

local HIDDEN = CFrame.new(0, -10000, 0)

local FXLibrary = {}

local started = false
local auto = true
local quality: Quality = "Medium"
local current: Tier = TIERS.Medium
local listeners: { (Quality) -> () } = {}

local buckets: { number } = table.create(NB, 0)
local cursor = -1
local liveBursts = 0
local liveContinuous = 0
local activeEffects = 0
local tracked: { Tracked } = {}
local trackClock = 0

local container: Folder? = nil
local pools: { [Instance]: { Model } } = {}
local templates: { [Model]: Instance } = {}
local playing: { { model: Model, untilT: number } } = {}
local warned: { [string]: boolean } = {}

local viewPos: Vector3? = nil
local viewAt = -1

-- Qualité ----------------------------------------------------------------------------------------

-- Palier détecté (repris tel quel de WeaponFX avant A07-01) : tactile sans clavier = téléphone ou
-- tablette ; sinon le niveau graphique enregistré de Roblox.
local function detect(): Quality
	local camera = Workspace.CurrentCamera
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		local short = if camera then math.min(camera.ViewportSize.X, camera.ViewportSize.Y) else 400
		return if short < 500 then "Low" else "Medium"
	end
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel
	end)
	if ok and level ~= Enum.SavedQualitySetting.Automatic then
		local v = (level :: Enum.SavedQualitySetting).Value
		if v <= 4 then
			return "Low"
		elseif v <= 7 then
			return "Medium"
		end
	end
	return "High"
end

local function retuneTracked()
	for _, h in tracked do
		for k, e in h.emitters do
			e.Rate = h.rates[k] * current.particles
		end
		local was = h.cost
		h.cost = 0
		for _, e in h.emitters do
			h.cost += e.Rate * e.Lifetime.Max
		end
		if h.on then
			liveContinuous += h.cost - was
		end
	end
end

local function apply(q: Quality)
	local changed = q ~= quality
	quality = q
	current = TIERS[q]
	retuneTracked()
	if changed then
		for _, fn in listeners do
			task.spawn(fn, q)
		end
	end
end

function FXLibrary.getQuality(): Quality
	return quality
end

function FXLibrary.isAuto(): boolean
	return auto
end

function FXLibrary.setQuality(name: string)
	if name == "Auto" then
		auto = true
		apply(detect())
	elseif TIERS[name :: Quality] then
		auto = false
		apply(name :: Quality)
	end
end

function FXLibrary.onQualityChanged(fn: (Quality) -> ())
	table.insert(listeners, fn)
end

function FXLibrary.tier(): Tier
	return current
end

function FXLibrary.domain(name: string): Domain
	local d = DOMAINS[name]
	if auto or not d then
		return AUTO_DOMAIN
	end
	return d[quality]
end

-- Budget -----------------------------------------------------------------------------------------

local function prune(now: number)
	local idx = math.floor(now / BUCKET)
	if idx == cursor then
		return
	end
	if cursor < 0 or idx - cursor >= NB then
		for k = 1, NB do
			buckets[k] = 0
		end
		liveBursts = 0
	else
		for i = cursor + 1, idx do
			local k = i % NB + 1
			liveBursts -= buckets[k]
			buckets[k] = 0
		end
	end
	cursor = idx
end

local function record(n: number, life: number, now: number)
	local idx = math.floor((now + math.clamp(life, BUCKET, (NB - 2) * BUCKET)) / BUCKET) + 1
	local k = idx % NB + 1
	buckets[k] += n
	liveBursts += n
end

local function localPosition(now: number): Vector3?
	if now - viewAt < 0.1 then
		return viewPos
	end
	viewAt = now
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		viewPos = root.Position
	else
		local camera = Workspace.CurrentCamera
		viewPos = if camera then camera.Focus.Position else nil
	end
	return viewPos
end

local function rankOf(priority: string, position: Vector3?, now: number): number
	local r = RANK[priority] or RANK.Normal
	if r == RANK.Normal and position then
		local here = localPosition(now)
		if here then
			local dx, dz = position.X - here.X, position.Z - here.Z
			if dx * dx + dz * dz > FAR_DISTANCE * FAR_DISTANCE then
				return FAR_RANK
			end
		end
	end
	return r
end

local function liveParticles(): number
	return liveBursts + liveContinuous
end

-- Rafale de n particules sous le budget. Renvoie le nombre émis (n sous le budget, moins au-delà,
-- jamais rien de coupé pour un Telegraph).
function FXLibrary.emit(emitter: ParticleEmitter, n: number, priority: Priority, position: Vector3?): number
	if n <= 0 then
		return 0
	end
	local now = os.clock()
	prune(now)
	local r = rankOf(priority, position, now)
	local count = n
	if r > 1 then
		local room = math.floor(current.maxParticles * SHARE[r]) - liveParticles()
		if room < count then
			count = math.max(0, room)
		end
	end
	if count > 0 then
		emitter:Emit(count)
		record(count, emitter.Lifetime.Max, now)
	end
	return count
end

function FXLibrary.canSpawn(priority: Priority, position: Vector3?): boolean
	local r = rankOf(priority, position, os.clock())
	return r == 1 or activeEffects < current.maxEffects * SHARE[r]
end

function FXLibrary.addActive(delta: number)
	activeEffects = math.max(0, activeEffects + delta)
end

-- Émetteurs continus -----------------------------------------------------------------------------

local function setOn(h: Tracked, on: boolean)
	if h.on == on then
		return
	end
	h.on = on
	liveContinuous += if on then h.cost else -h.cost
	for _, e in h.emitters do
		e.Enabled = on
	end
end

-- Suit les ParticleEmitter (Enabled = true au départ) des pièces d'un objet cloné : taux × qualité,
-- coupés quand les particules vivantes dépassent la part de leur priorité.
function FXLibrary.track(parts: { BasePart }, priority: Priority): Tracked
	local h: Tracked = { emitters = {}, rates = {}, rank = RANK[priority] or RANK.Ambient, position = nil, cost = 0, on = false }
	for _, part in parts do
		local list: { Instance } = part:GetDescendants()
		table.insert(list, part)
		for _, d in list do
			if d:IsA("ParticleEmitter") and d.Enabled then
				table.insert(h.emitters, d)
				table.insert(h.rates, d.Rate)
				d.Rate *= current.particles
				h.cost += d.Rate * d.Lifetime.Max
				d.Enabled = false
			end
		end
	end
	table.insert(tracked, h)
	setOn(h, true)
	return h
end

function FXLibrary.untrack(h: Tracked?)
	if not h then
		return
	end
	setOn(h, false)
	local i = table.find(tracked, h)
	if i then
		table.remove(tracked, i)
	end
end

function FXLibrary.setTrackedPosition(h: Tracked, position: Vector3)
	h.position = position
end

local function stepTracked(now: number)
	prune(now)
	for _, h in tracked do
		local r = if h.rank == RANK.Normal and h.position then rankOf("Normal", h.position, now) else h.rank
		if r == 1 then
			setOn(h, true)
			continue
		end
		local cap = current.maxParticles * SHARE[r]
		if h.on and liveParticles() > cap then
			setOn(h, false)
		elseif not h.on and liveParticles() + h.cost < cap * RELIGHT then
			setOn(h, true)
		end
	end
end

-- Clone en pool ----------------------------------------------------------------------------------

local function ensureContainer(): Folder
	local folder = container
	if not folder then
		folder = Instance.new("Folder") -- dossier de rangement vide : invisible
		folder.Name = "COHUE_FXLibrary"
		folder.Parent = Workspace
		container = folder
	end
	return folder
end

-- Clone d'un modèle d'effet Assets.FX.<path> (chemin pointé), pris dans le pool s'il y en a un.
-- Absent : avertissement une fois, nil. Compte un effet actif (give le rend).
function FXLibrary.take(path: string): Model?
	local t = ArtLibrary.fx(path)
	if not t or not t:IsA("Model") then
		if not warned[path] then
			warned[path] = true
			warn(`[FXLibrary] effet manquant : Assets.FX.{path}`)
		end
		return nil
	end
	local pool = pools[t]
	local model = pool and table.remove(pool)
	if not model then
		local m = t:Clone()
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.CastShadow = false
			end
		end
		m:PivotTo(HIDDEN)
		m.Parent = ensureContainer()
		templates[m] = t
		model = m
	end
	activeEffects += 1
	return model
end

function FXLibrary.give(model: Model)
	local t = templates[model]
	if not t then
		model:Destroy()
		return
	end
	model:PivotTo(HIDDEN)
	for _, d in model:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			d.Enabled = false
		end
	end
	local pool = pools[t]
	if not pool then
		pool = {}
		pools[t] = pool
	end
	table.insert(pool, model)
	FXLibrary.addActive(-1)
end

-- Effet ponctuel : pose le modèle, émet ses rafales (attribut Burst des ParticleEmitter, × qualité,
-- × rayon / 5 si PerRadius), le rend au pool après son attribut Life (1 s par défaut).
function FXLibrary.play(path: string, cframe: CFrame, priority: Priority?, radius: number?): boolean
	local prio: Priority = priority or "Normal"
	if not FXLibrary.canSpawn(prio, cframe.Position) then
		return false
	end
	local model = FXLibrary.take(path)
	if not model then
		return false
	end
	model:PivotTo(cframe)
	for _, d in model:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			local b = d:GetAttribute("Burst")
			if type(b) == "number" and b > 0 then
				local k = if d:GetAttribute("PerRadius") == true then math.clamp((radius or 5) / 5, 0.5, 3) else 1
				FXLibrary.emit(d, math.max(1, math.floor(b * k * current.particles + 0.5)), prio, cframe.Position)
			end
		end
	end
	local life = model:GetAttribute("Life")
	table.insert(playing, { model = model, untilT = os.clock() + (if type(life) == "number" then life else 1) })
	return true
end

function FXLibrary.stats(): { particles: number, effects: number, quality: Quality, auto: boolean }
	prune(os.clock())
	return { particles = liveParticles(), effects = activeEffects, quality = quality, auto = auto }
end

-- Démarrage --------------------------------------------------------------------------------------

local function onProfile(profile: any)
	local settings = type(profile) == "table" and profile.settings
	local v = type(settings) == "table" and settings.fxQuality
	if type(v) == "string" then
		FXLibrary.setQuality(v)
	end
end

function FXLibrary.start()
	if started then
		return
	end
	started = true
	quality = detect()
	current = TIERS[quality]
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for i = #playing, 1, -1 do
			local p = playing[i]
			if now >= p.untilT then
				FXLibrary.give(p.model)
				table.remove(playing, i)
			end
		end
		if now - trackClock >= 1 / TRACK_HZ then
			trackClock = now
			stepTracked(now)
		end
	end)
	-- Réglage joueur (Profile.settings.fxQuality ; la clé attend la contract request A07-01 côté
	-- ProgressionService.onUpdateSettings). Net.event peut céder : à part.
	task.spawn(function()
		Net.event("Profile").OnClientEvent:Connect(onProfile)
		-- Profile a pu arriver avant nous : dernière valeur gardée par UITheme (lecture seule).
		local controllers = script.Parent
		local ui = controllers and controllers:FindFirstChild("UI")
		local themeModule = ui and ui:FindFirstChild("UITheme")
		if themeModule and themeModule:IsA("ModuleScript") then
			local ok, theme = pcall(require, themeModule)
			if ok and type(theme) == "table" and type((theme :: any).last) == "function" then
				local okP, profile = pcall((theme :: any).last, "Profile")
				if okP then
					onProfile(profile)
				end
			end
		end
	end)
end

return FXLibrary
