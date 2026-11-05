--!strict
-- Sons et musiques du client (A10-03, A10-04, A10-05). Design : docs/dossier/90-son.md.
-- Réglages et correspondance événement -> nom : shared/Config/Sounds.luau.
--
-- Rien n'est construit ici (décisions v2 §12) : chaque son est un objet Sound posé par Clément dans
-- ReplicatedStorage.Assets.Sounds (ou SoundService). On le trouve par son nom, on le clone en pool
-- (dossier COHUE_SoundPool sous SoundService) et on le rejoue. Un nom manquant est signalé une fois.
--
-- - Un pool de clones par son, réutilisé (aucune allocation par lecture une fois le pool rempli).
-- - Limite de sons simultanés globale (Config.MaxVoices) et par catégorie (Music, Ambience,
--   Weapons, KO, Creatures, UI) ; une catégorie pleine coupe le plus ancien ou ignore le nouveau.
-- - Volume final = volume de l'objet x événement x catégorie x réglage joueur (music / sfx) x master.
-- - Musique : une piste par contexte (lobby, monde, boss, Overtime), fondus enchaînés dans une
--   boucle à Config.MusicHz sans allocation. Overtime : la piste accélère et des couches entrent
--   avec l'intensité (secondes d'Overtime du RunState).
-- - Écoute seule les remotes du contrat (RunState, Announce, PlayerProgress, Coins, CardOffer,
--   PlayerVitals, BossState, CompanionState, ...). Les sons d'armes et d'ennemis passent par l'API
--   (SoundController.weapon / SoundController.enemy), appelée par les renderers qui décodent déjà
--   les snapshots (contract requests A10).
--
-- API : play(key, position?) · playSound(name, category, position?, volume?) ·
--   weapon(weaponId, "Fire"|"Hit", position?) · enemy(kind, "KO"|"Attack"|"Spawn", position?) ·
--   getVolume(group) · setVolume(group, value) · volumeChanged (Signal: group, value) ·
--   setMusicOverride(name?) · hasSound(name)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ConfigFolder = Shared:WaitForChild("Config")
local Cfg = require(ConfigFolder:WaitForChild("Sounds"))
local Enemies = require(ConfigFolder:WaitForChild("Enemies"))
local Net = require(Shared:WaitForChild("Net"))
local Registry = require(Shared:WaitForChild("Registry"))
local Signal = require(Shared:WaitForChild("Signal"))

type Category = Cfg.Category
type Group = Cfg.Group

type Voice = {
	sound: Sound,
	category: Category,
	startAt: number,
	endAt: number,
}

type Track = {
	name: string,
	category: Category,
	sound: Sound?,
	fade: number, -- 0..1, suit target
	target: number,
	fadeSeconds: number,
	gain: number, -- multiplicateur (Overtime)
	speed: number, -- multiplicateur de PlaybackSpeed (Overtime)
	baseVolume: number,
	baseSpeed: number,
}

local SoundController = {}
SoundController.volumeChanged = Signal.new()

local localPlayer = Players.LocalPlayer
local rng = Random.new()

local holder: Folder? = nil
local templates: { [string]: Sound } = {}
local warned: { [string]: boolean } = {}

local pools: { [string]: { Voice } } = {}
local categoryVoices: { [string]: { Voice } } = {}
local allVoices: { Voice } = {}
local lastPlayed: { [string]: number } = {}

-- Noms construits (armes, ennemis) : patternKey -> id -> nom trouvé ou false. Vidé quand un son arrive.
local resolved: { [string]: { [any]: string | false } } = {}

local volumes: { [Group]: number } = table.clone(Cfg.Volumes.Default)

local tracks: { [string]: Track } = {}
local musicOverride: string? = nil
local desiredMusic: string? = nil
local desiredAmbience: string? = nil
local overtimeSeconds = 0

-- Dernier état connu (pour détecter les changements dans les remotes « état »).
local runState: { [string]: any }? = nil
local bossId: string? = nil
local bossMusic: string? = nil
local lastTelegraphAt: number? = nil
local prevLevel: number? = nil
local prevXp: number? = nil
local prevCoins: number? = nil
local prevHp: number? = nil
local prevDowned = false
local cardOpen = false
local prevCompanionStage: number? = nil
local prevUltimate: number? = nil
local prevCaptureState: string? = nil

local function clamp01(v: number): number
	return if v ~= v then 0 else math.clamp(v, 0, 1)
end

local rootsPending = #Cfg.Folders -- pas d'alerte « manquant » avant d'avoir parcouru les dossiers

local function warnOnce(name: string)
	if warned[name] or rootsPending > 0 then
		return
	end
	warned[name] = true
	warn(`[SoundController] Sound "{name}" introuvable (ReplicatedStorage.Assets.Sounds ou SoundService)`)
end

---------------------------------------------------------------------------- templates

local function addTemplate(inst: Instance)
	if not inst:IsA("Sound") then
		return
	end
	if holder and inst:IsDescendantOf(holder) then
		return -- nos propres clones
	end
	if templates[inst.Name] == nil then
		templates[inst.Name] = inst
		table.clear(resolved)
	end
end

local function watchRoot(path: { string })
	local ok, service = pcall(game.GetService, game, path[1])
	local inst: Instance? = if ok then service else nil
	for i = 2, #path do
		if not inst then
			break
		end
		inst = inst:WaitForChild(path[i], 30)
	end
	if inst then
		for _, d in inst:GetDescendants() do
			addTemplate(d)
		end
		inst.DescendantAdded:Connect(addTemplate)
	else
		warn(`[SoundController] dossier de sons absent : {table.concat(path, ".")}`)
	end
	rootsPending -= 1
end

local function getTemplate(name: string): Sound?
	local t = templates[name]
	if t and t.Parent then
		return t
	end
	if t then
		templates[name] = nil -- détruit ou déplacé dans Studio
	end
	warnOnce(name)
	return nil
end

function SoundController.hasSound(name: string): boolean
	local t = templates[name]
	return t ~= nil and t.Parent ~= nil
end

---------------------------------------------------------------------------- volumes

local function categoryGain(category: Category): number
	local def = Cfg.Categories[category]
	if not def then
		return 0
	end
	return def.volume * (volumes[def.group] or 1) * volumes.master
end

local pendingSend: { [string]: number } = {}
local sendScheduled = false

local function queueSend(group: Group)
	if not Cfg.Volumes.Persist then
		return
	end
	pendingSend[Cfg.Volumes.SettingKeys[group]] = volumes[group]
	if sendScheduled then
		return
	end
	sendScheduled = true
	task.delay(Cfg.Volumes.SendDelay, function()
		sendScheduled = false
		local payload = pendingSend
		pendingSend = {}
		Net.event("UpdateSettings"):FireServer(payload)
	end)
end

function SoundController.getVolume(group: Group): number
	return volumes[group] or 1
end

function SoundController.setVolume(group: Group, value: number)
	if volumes[group] == nil or type(value) ~= "number" then
		return
	end
	local v = math.floor(clamp01(value) * 100 + 0.5) / 100
	if v == volumes[group] then
		return
	end
	volumes[group] = v -- musique : suit dans la boucle ; sons courts : à la prochaine lecture
	queueSend(group)
	SoundController.volumeChanged:fire(group, v)
end

-- Profile.settings (serveur) : appliqué sans renvoi.
local function applyProfileSettings(settings: any)
	if type(settings) ~= "table" then
		return
	end
	for group, key in Cfg.Volumes.SettingKeys do
		local v = settings[key]
		if type(v) == "number" and v == v then
			v = clamp01(v)
			if v ~= volumes[group] then
				volumes[group] = v
				SoundController.volumeChanged:fire(group, v)
			end
		end
	end
end

---------------------------------------------------------------------------- one-shots

local function listenerPosition(): Vector3?
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local camera = Workspace.CurrentCamera
	return if camera then camera.Focus.Position else nil
end

local function attenuation(position: Vector3): number
	local listener = listenerPosition()
	if not listener then
		return 1
	end
	local dx, dz = position.X - listener.X, position.Z - listener.Z
	local dist = math.sqrt(dx * dx + dz * dz)
	local p = Cfg.Positional
	if dist <= p.FullRadius then
		return 1
	elseif dist >= p.HearRadius then
		return 0
	end
	local t = (dist - p.FullRadius) / (p.HearRadius - p.FullRadius)
	return 1 + (p.MinFactor - 1) * t
end

local function countActive(list: { Voice }, now: number): number
	local n = 0
	for _, v in list do
		if v.endAt > now then
			n += 1
		end
	end
	return n
end

local function stopOldest(list: { Voice }, now: number): boolean
	local oldest: Voice? = nil
	for _, v in list do
		if v.endAt > now and (oldest == nil or v.startAt < oldest.startAt) then
			oldest = v
		end
	end
	if oldest then
		oldest.sound:Stop()
		oldest.endAt = 0
		return true
	end
	return false
end

-- Joue l'objet Sound `name` dans `category`. Renvoie false si rien n'est joué (son manquant,
-- limites atteintes, trop loin, volume nul).
function SoundController.playSound(name: string, category: Category, position: Vector3?, volume: number?, pitchJitter: number?): boolean
	local def = Cfg.Categories[category]
	if not def then
		return false
	end
	local template = getTemplate(name)
	local folder = holder
	if not template or not folder then
		return false
	end
	local gain = (volume or 1) * categoryGain(category)
	if position then
		gain *= attenuation(position)
	end
	if gain <= 0.001 then
		return false
	end

	local now = os.clock()
	local catList = categoryVoices[category]
	if not catList then
		catList = {}
		categoryVoices[category] = catList
	end
	if countActive(allVoices, now) >= Cfg.MaxVoices then
		if not def.steal or not stopOldest(catList, now) then
			return false
		end
	end
	if countActive(catList, now) >= def.maxVoices then
		if not def.steal or not stopOldest(catList, now) then
			return false
		end
	end

	local pool = pools[name]
	if not pool then
		pool = {}
		pools[name] = pool
	end
	local voice: Voice? = nil
	for _, v in pool do
		if v.endAt <= now then
			voice = v
			break
		end
	end
	if not voice then
		if #pool < def.maxVoices then
			local clone = template:Clone()
			clone.Looped = false
			clone.PlayOnRemove = false
			clone.Playing = false
			clone.Parent = folder
			local v: Voice = { sound = clone, category = category, startAt = 0, endAt = 0 }
			table.insert(pool, v)
			table.insert(catList, v)
			table.insert(allVoices, v)
			voice = v
		else
			-- Pool plein pour ce son : on relance le plus ancien.
			local oldest = pool[1]
			for _, v in pool do
				if v.startAt < oldest.startAt then
					oldest = v
				end
			end
			voice = oldest
		end
	end

	local v = voice :: Voice
	local s = v.sound
	local jitter = pitchJitter or 0
	s:Stop()
	s.Volume = template.Volume * gain
	s.PlaybackSpeed = template.PlaybackSpeed * (1 + jitter * (rng:NextNumber() * 2 - 1))
	s.TimePosition = 0
	s:Play()
	local length = s.TimeLength
	if length <= 0 then
		length = 1.5 -- pas encore chargé
	end
	v.startAt = now
	v.endAt = now + length / math.max(s.PlaybackSpeed, 0.05)
	return true
end

-- Joue l'événement `key` de Config.Sounds.Events.
function SoundController.play(key: string, position: Vector3?): boolean
	local event = Cfg.Events[key]
	if not event then
		warnOnce("event:" .. key)
		return false
	end
	local now = os.clock()
	if event.cooldown then
		local last = lastPlayed[key]
		if last and now - last < event.cooldown then
			return false
		end
	end
	lastPlayed[key] = now
	return SoundController.playSound(event.sound, event.category, position, event.volume, event.pitchJitter)
end

-- Premier nom existant des motifs Config.Patterns[patternKey], en cache.
local function resolve(patternKey: string, id: any, name: string, family: string?): string?
	local cache = resolved[patternKey]
	if not cache then
		cache = {}
		resolved[patternKey] = cache
	end
	local hit = cache[id]
	if hit ~= nil then
		return if hit then hit else nil
	end
	local patterns = Cfg.Patterns[patternKey]
	local found: string | false = false
	if patterns then
		for _, pattern in patterns do
			local withId = string.gsub(pattern, "{id}", name)
			local candidate = string.gsub(withId, "{family}", family or "")
			if SoundController.hasSound(candidate) then
				found = candidate
				break
			end
		end
		if not found then
			local first = string.gsub(patterns[1], "{id}", name)
			warnOnce(first)
		end
	end
	cache[id] = found
	return if found then found else nil
end

local function playPattern(patternKey: string, id: any, name: string, family: string?, position: Vector3?): boolean
	local sound = resolve(patternKey, id, name, family)
	local ev = Cfg.PatternEvents[patternKey]
	if not sound or not ev then
		return false
	end
	local now = os.clock()
	local last = lastPlayed[sound]
	if last and now - last < ev.cooldown then
		return false
	end
	lastPlayed[sound] = now
	return SoundController.playSound(sound, ev.category, position, ev.volume, ev.pitchJitter)
end

-- Tir ou impact d'arme. weaponId = id de Config.Weapons.
function SoundController.weapon(weaponId: string, action: "Fire" | "Hit", position: Vector3?): boolean
	return playPattern(if action == "Hit" then "WeaponHit" else "WeaponFire", weaponId, weaponId, nil, position)
end

local ENEMY_PATTERN = { KO = "EnemyKO", Attack = "EnemyAttack", Spawn = "EnemySpawn" }

-- KO, attaque ou apparition d'un ennemi. kind = index de Config.Enemies (EnemyCodec).
function SoundController.enemy(kind: number, action: "KO" | "Attack" | "Spawn", position: Vector3?): boolean
	local def = Enemies[kind]
	local patternKey = ENEMY_PATTERN[action]
	if not def or not patternKey then
		return false
	end
	return playPattern(patternKey, kind, def.name, def.family, position)
end

---------------------------------------------------------------------------- music (A10-04)

local function getTrack(name: string, category: Category): Track
	local t = tracks[name]
	if not t then
		local newTrack: Track = {
			name = name,
			category = category,
			sound = nil,
			fade = 0,
			target = 0,
			fadeSeconds = Cfg.Music.FadeSeconds,
			gain = 1,
			speed = 1,
			baseVolume = 1,
			baseSpeed = 1,
		}
		t = newTrack
		tracks[name] = newTrack
	end
	return t :: Track
end

local function trackSound(t: Track): Sound?
	local s = t.sound
	if s and s.Parent then
		return s
	end
	local template = getTemplate(t.name)
	if not template or not holder then
		return nil
	end
	local clone = template:Clone()
	clone.Looped = true
	clone.Playing = false
	clone.PlayOnRemove = false
	clone.Parent = holder
	t.sound = clone
	t.baseVolume = template.Volume
	t.baseSpeed = template.PlaybackSpeed
	return clone
end

local function chooseMusic()
	local music: string? = nil
	local ambience: string? = nil
	local st = runState
	local phase = if st then st.phase else "Loadout"
	if musicOverride then
		music = musicOverride
	elseif phase == "Loadout" or phase == nil then
		music = Cfg.Music.Lobby
	elseif phase ~= "Ended" and st then
		local world = st.worldId
		ambience = if type(world) == "string" then Cfg.Ambience[world] else nil
		if phase == "Boss" then
			music = bossMusic or Cfg.Music.Boss
		elseif st.overtime == true and phase ~= "BossDefeated" then
			music = Cfg.Overtime.Track
		else
			music = if type(world) == "string" then Cfg.Music.Worlds[world] else nil
		end
	end
	desiredMusic = music
	desiredAmbience = ambience
	if music then
		getTrack(music, "Music")
	end
	if ambience then
		getTrack(ambience, "Ambience")
	end
	if music == Cfg.Overtime.Track then
		for _, layer in Cfg.Overtime.Layers do
			getTrack(layer.sound, "Music").fadeSeconds = Cfg.Overtime.LayerFadeSeconds
		end
	end
end

function SoundController.setMusicOverride(name: string?)
	musicOverride = name
	chooseMusic()
end

local function isLayer(name: string): number?
	for _, layer in Cfg.Overtime.Layers do
		if layer.sound == name then
			return layer.from
		end
	end
	return nil
end

local function stepMusic(dt: number)
	local ot = Cfg.Overtime
	local inOvertime = desiredMusic == ot.Track
	local intensity = if inOvertime then clamp01(overtimeSeconds / math.max(ot.RampSeconds, 1)) else 0
	local speed = ot.SpeedFrom + (ot.SpeedTo - ot.SpeedFrom) * intensity
	local mainTrack = if inOvertime then tracks[ot.Track] else nil
	local mainSound = if mainTrack then mainTrack.sound else nil

	for name, t in tracks do
		local layerFrom = isLayer(name)
		if layerFrom then
			t.target = if inOvertime and intensity >= layerFrom then 1 else 0
			t.speed = speed
		elseif name == desiredMusic or name == desiredAmbience then
			t.target = 1
			if name == ot.Track then
				t.gain = ot.VolumeFrom + (ot.VolumeTo - ot.VolumeFrom) * intensity
				t.speed = speed
			else
				t.gain = 1
				t.speed = 1
			end
		else
			t.target = 0
		end

		if t.fade ~= t.target then
			local step = dt / math.max(t.fadeSeconds, 0.01)
			if t.target > t.fade then
				t.fade = math.min(t.target, t.fade + step)
			else
				t.fade = math.max(t.target, t.fade - step)
			end
		end

		if t.fade > 0 or t.target > 0 then
			local s = trackSound(t)
			if s then
				if t.fade > 0 and not s.IsPlaying then
					if layerFrom and mainSound and mainSound.IsPlaying then
						s.TimePosition = mainSound.TimePosition
					end
					s:Play()
				end
				s.Volume = t.baseVolume * t.gain * t.fade * categoryGain(t.category)
				s.PlaybackSpeed = t.baseSpeed * t.speed
				-- Couches calées sur la piste principale (même longueur attendue).
				if layerFrom and mainSound and mainSound.IsPlaying and s.IsPlaying then
					if math.abs(s.TimePosition - mainSound.TimePosition) > ot.ResyncTolerance then
						s.TimePosition = mainSound.TimePosition
					end
				end
			end
		else
			local s = t.sound
			if s and s.IsPlaying then
				s:Stop()
			end
		end
	end
end

---------------------------------------------------------------------------- remotes

-- Passe par UITheme.watch (garde le dernier payload, pas de message perdu au démarrage) s'il est là.
local function watch(remoteName: string, handler: (payload: any) -> ())
	local ui = Registry.find("UITheme")
	if ui and type(ui.watch) == "function" then
		ui.watch(remoteName, handler)
		return
	end
	task.spawn(function()
		Net.event(remoteName).OnClientEvent:Connect(handler)
	end)
end

-- Remote hors contrat (peut ne pas exister encore) : écouté seulement s'il est publié.
local function watchOptional(remoteName: string, handler: (payload: any) -> ())
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("Remotes", 60)
		local remote = folder and folder:FindFirstChild(remoteName)
		if remote and remote:IsA("RemoteEvent") then
			remote.OnClientEvent:Connect(handler)
		end
	end)
end

local function onRunState(st: any)
	if type(st) ~= "table" then
		return
	end
	local prevPhase = if runState then runState.phase else nil
	runState = st
	if st.phase == "BossDefeated" and prevPhase ~= nil and prevPhase ~= "BossDefeated" then
		SoundController.play("BossDefeated")
	end
	local secs = st.overtimeSeconds or st.finalWaveSeconds
	overtimeSeconds = if type(secs) == "number" and st.overtime == true then secs else 0
	if st.phase ~= "Boss" then
		bossMusic = nil
	end
	chooseMusic()
end

local function onAnnounce(p: any)
	if type(p) ~= "table" or type(p.kind) ~= "string" then
		return
	end
	if p.kind == "Downed" and prevDowned then
		return -- son personnel déjà joué (PlayerVitals)
	end
	local key = Cfg.AnnounceKinds[p.kind]
	if key then
		SoundController.play(key)
	end
end

local function onProgress(p: any)
	if type(p) ~= "table" or type(p.level) ~= "number" or type(p.xp) ~= "number" then
		return
	end
	if prevLevel and p.level > prevLevel then
		SoundController.play("LevelUp")
	elseif prevXp and p.xp > prevXp and prevLevel == p.level then
		SoundController.play("XpPickup")
	end
	prevLevel, prevXp = p.level, p.xp
end

local function onCoins(p: any)
	local coins = if type(p) == "table" then p.coins else nil
	if type(coins) ~= "number" then
		return
	end
	if prevCoins and coins > prevCoins then
		SoundController.play("CoinPickup")
	end
	prevCoins = coins
end

local function onCardOffer(p: any)
	if type(p) ~= "table" then
		return
	end
	if p.closed then
		if cardOpen then
			SoundController.play("CardPick")
		end
		cardOpen = false
	else
		cardOpen = true
		SoundController.play("CardOffer")
	end
end

local function onVitals(p: any)
	if type(p) ~= "table" or type(p.hp) ~= "number" then
		return -- payload « team » seul
	end
	if prevHp and p.hp < prevHp - 0.5 and not p.downed then
		SoundController.play("PlayerHurt")
	end
	local downed = p.downed == true
	if downed and not prevDowned then
		SoundController.play("PlayerDowned")
	end
	prevHp, prevDowned = p.hp, downed
end

local function onBoss(p: any)
	if type(p) ~= "table" then
		return
	end
	if type(p.bossId) == "string" and p.bossId ~= bossId then
		bossId = p.bossId
		local specific = Cfg.Music.BossPrefix .. p.bossId
		bossMusic = if SoundController.hasSound(specific) then specific else Cfg.Music.Boss
		SoundController.play("BossRoar", if typeof(p.position) == "Vector3" then p.position else nil)
		chooseMusic()
	end
	local tele = p.telegraph
	if type(tele) == "table" and type(tele.at) == "number" and tele.at ~= lastTelegraphAt then
		lastTelegraphAt = tele.at
		SoundController.play("BossTelegraph", if typeof(tele.position) == "Vector3" then tele.position else nil)
	end
end

local function onCompanion(p: any)
	if type(p) ~= "table" then
		return
	end
	if type(p.stage) == "number" then
		if prevCompanionStage and p.stage > prevCompanionStage then
			SoundController.play("CompanionEvolve")
		end
		prevCompanionStage = p.stage
	end
	if type(p.ultimateCharge) == "number" then
		if prevUltimate and prevUltimate < 1 and p.ultimateCharge >= 1 then
			SoundController.play("UltimateReady")
		end
		prevUltimate = p.ultimateCharge
	end
end

local function onCapture(p: any)
	if type(p) ~= "table" or type(p.state) ~= "string" then
		return
	end
	if p.state ~= prevCaptureState then
		if p.state == "Capturing" then
			SoundController.play("CaptureCharge")
		elseif p.state == "Captured" then
			SoundController.play("CaptureSuccess")
		end
	end
	prevCaptureState = p.state
end

local function onProfile(p: any)
	if type(p) == "table" then
		applyProfileSettings(p.settings)
	end
end

---------------------------------------------------------------------------- UI clicks

local function hookButton(inst: Instance)
	if not inst:IsA("GuiButton") then
		return
	end
	inst.Activated:Connect(function()
		if inst:GetAttribute("NoClickSound") == true then
			return
		end
		local custom = inst:GetAttribute("ClickSound")
		SoundController.play(if type(custom) == "string" and Cfg.Events[custom] then custom else "Click")
	end)
end

local function hookClicks()
	local playerGui = localPlayer:WaitForChild("PlayerGui", 60)
	if not playerGui then
		return
	end
	for _, d in playerGui:GetDescendants() do
		hookButton(d)
	end
	playerGui.DescendantAdded:Connect(hookButton)
end

---------------------------------------------------------------------------- lifecycle

function SoundController.init()
	local folder = Instance.new("Folder") -- dossier de rangement vide (§12), reçoit les clones
	folder.Name = "COHUE_SoundPool"
	folder.Parent = SoundService
	holder = folder
	for _, path in Cfg.Folders do
		task.spawn(watchRoot, path)
	end
end

function SoundController.start()
	watch("Profile", onProfile)
	watch("RunState", onRunState)
	watch("Announce", onAnnounce)
	watch("PlayerProgress", onProgress)
	watch("Coins", onCoins)
	watch("CardOffer", onCardOffer)
	watch("PlayerVitals", onVitals)
	watch("BossState", onBoss)
	watch("CompanionState", onCompanion)
	watch("ShrineOffer", function()
		SoundController.play("ShrineReward")
	end)
	watch("LootReward", function()
		SoundController.play("ChestOpen")
	end)
	watch("EggHatched", function()
		SoundController.play("EggHatch")
	end)
	watch("DataNotice", function(p: any)
		SoundController.play(if type(p) == "table" and p.kind == "QuestDone" then "QuestComplete" else "Notify")
	end)
	watch("PingBroadcast", function(p: any)
		SoundController.play("Ping", if type(p) == "table" and typeof(p.position) == "Vector3" then p.position else nil)
	end)
	watchOptional("CaptureState", onCapture)

	if Cfg.AutoClick then
		task.spawn(hookClicks)
	end

	chooseMusic()
	local interval = 1 / math.max(Cfg.MusicHz, 1)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < interval then
			return
		end
		local step = acc
		acc = 0
		stepMusic(step)
	end)
end

return SoundController
