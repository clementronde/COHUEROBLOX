--!strict
-- Run flow, timers, coop rules and player vitals (dossier 20 sections 1, 2, 6).
-- Run v2 (A04-02, décisions v2 section 2) : Run.WorldsPerRun mondes enchaînés (Run.WorldChain),
-- 10:00 par monde ; le boss tué ouvre le portail du monde suivant. À 0:00, Overtime : le chrono
-- monte et toutes les Run.Overtime.StepSeconds la difficulté grimpe sans plafond (densité, PV,
-- dégâts, part d'élites). Après le boss du dernier monde : Victory, portail doré Cash out, ou on
-- continue (Keep going = Overtime infini). Fin : tout le monde à terre / fantôme, ou Cash out.
-- La phase "FinalWave" du contrat (Types.RunPhase) porte l'Overtime ; RunState dit `overtime`.
-- Single server state machine (Types.RunPhase); every delayed step checks the run id so a stale
-- timer from an old run never fires into a new one (vault: "Arena Rounds with Teams and
-- Spectating End to End"). All player damage goes through damagePlayer (vault: "Downed, Revive
-- and Bleed-Out States": one damage core, lethal damage downs instead of killing).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Run = require(Config:WaitForChild("Run"))
local Classes = require(Config:WaitForChild("Classes"))
local Worlds = require(Config:WaitForChild("Worlds"))
local Balance = require(Config:WaitForChild("Balance"))
local Heightmap = require(Shared:WaitForChild("Heightmap"))
local Net = require(Shared:WaitForChild("Net"))
local Registry = require(Shared:WaitForChild("Registry"))
local Types = require(Shared:WaitForChild("Types"))
local Bus = require(script.Parent.Parent:WaitForChild("Bus"))

local MAIN_DT = 0.1
local CONTACT_DT = 1 / Run.Player.ContactHz

type PlayerRun = {
	player: Player,
	ready: boolean,
	classId: string,
	companionId: string,
	inRun: boolean,
	hp: number,
	maxHp: number,
	shield: number,
	shieldCap: number,
	downedUntil: number?, -- os.clock
	ghost: boolean,
	reviveProgress: number,
	invulnUntil: number,
	contactReadyAt: number,
	revives: number,
	replay: boolean,
	dirty: boolean,
	lastVitals: number,
	joinedAt: number,
	ghostParts: { [BasePart]: number },
}

local RunManager = {}

local records: { [Player]: PlayerRun } = {}
local runPlayers: { Player } = {}

local state = {
	phase = "Loadout" :: Types.RunPhase,
	runId = 0,
	worldId = Run.DefaultWorld,
	tier = Run.DefaultTier,
	selectedWorld = Run.DefaultWorld,
	selectedTier = Run.DefaultTier,
	stage = 1,
	stageStart = 0,
	bossId = "",
	bossRevealed = false,
	arche = nil :: Vector3?,
	arenaEnterAt = nil :: number?,
	bossSpawned = false,
	bossDefeated = false,
	farmEndsAt = 0,
	portalOpensAt = 0, -- les portails n'acceptent personne avant (Run.PortalGrace)
	portal = nil :: Vector3?,
	wavesDone = {} :: { [number]: boolean },
	miniBossDone = {} :: { [number]: boolean },
	boostUntil = 0,
	boostMult = 1,
	-- Overtime (finalWave* : noms du contrat RunState, lus par le HUD)
	finalWaveStart = nil :: number?, -- os.clock du début de l'Overtime
	finalWaveSeconds = 0, -- secondes d'Overtime (chrono qui monte)
	overtimeStep = 0, -- paliers d'escalade atteints
	overtimeFrozen = false, -- boss tué (hors dernier monde) : l'escalade s'arrête jusqu'au portail
	coinsStep = 0, -- dernier palier payé en pièces de survie
	victory = false, -- boss du dernier monde tué
	cashOut = nil :: Vector3?, -- portail doré après la victoire
	cashOutHold = 0,
	cashedOut = false,
	firstReplayAt = nil :: number?,
	stateDirty = true,
	firstJoinAt = nil :: number?,
}

local remotes: { [string]: RemoteEvent } = {}
local queryBuffer: { number } = {}

-- Helpers ------------------------------------------------------------------------------------

local function find(name: string): any
	return Registry.find(name)
end

local function safe(fn: any, ...: any): (boolean, any)
	if type(fn) ~= "function" then
		return false, nil
	end
	return pcall(fn, ...)
end

local function now(): number
	return os.clock()
end

local function rootOf(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") then
		return root, hum
	end
	return nil, hum
end

local function feetY(root: BasePart, hum: Humanoid?): number
	return root.Position.Y - (if hum then hum.HipHeight else 2) - root.Size.Y / 2
end

local function statsOf(player: Player): { [string]: number }?
	local stats = find("StatsService")
	if not stats then
		return nil
	end
	local ok, block = safe(stats.get, player)
	if ok and type(block) == "table" then
		return block :: any
	end
	return nil
end

local function stat(block: { [string]: number }?, name: string, default: number): number
	local v = block and block[name]
	return if type(v) == "number" and v == v then v else default
end

local function announce(kind: string, text: Types.LocalizedText, duration: number)
	remotes.Announce:FireAllClients({ kind = kind, text = text, duration = duration })
end

local function isActiveRecord(r: PlayerRun?): boolean
	return r ~= nil and r.inRun and r.downedUntil == nil and not r.ghost
end

local function teleport(player: Player, position: Vector3)
	local character = player.Character
	if not character then
		return
	end
	player:SetAttribute("MoveExemptUntil", Workspace:GetServerTimeNow() + 2)
	local guard = find("MovementGuard")
	if guard then
		safe(guard.exempt, player, 2, "RunTeleport")
	end
	character:PivotTo(CFrame.new(position + Vector3.new(0, 4, 0)))
end

local function spawnPointFor(index: number): Vector3
	local stageService = find("StageService")
	if stageService then
		local ok, list = safe(stageService.getSpawnPoints, "Player")
		if ok and type(list) == "table" and #list > 0 then
			return list[(index - 1) % #list + 1]
		end
	end
	return Vector3.new(index * 4, Heightmap.getY(index * 4, 0), 0)
end

local function setLifeAttributes(r: PlayerRun)
	r.player:SetAttribute("Downed", r.downedUntil ~= nil)
	r.player:SetAttribute("Ghost", r.ghost)
	r.player:SetAttribute("RunHp", math.floor(r.hp))
	r.player:SetAttribute("RunMaxHp", math.floor(r.maxHp))
end

local function setGhostLook(r: PlayerRun, on: boolean)
	local character = r.player.Character
	if on and character then
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
				r.ghostParts[d] = d.Transparency
				d.Transparency = math.max(d.Transparency, Run.Coop.GhostTransparency)
			end
		end
	else
		for part, original in r.ghostParts do
			if part.Parent then
				part.Transparency = original
			end
		end
		table.clear(r.ghostParts)
	end
end

local function getRecord(player: Player): PlayerRun
	local r = records[player]
	if not r then
		r = {
			player = player,
			ready = false,
			classId = Run.DefaultClass,
			companionId = Run.DefaultCompanion,
			inRun = false,
			hp = Run.Player.BaseMaxHp,
			maxHp = Run.Player.BaseMaxHp,
			shield = 0,
			shieldCap = 0,
			downedUntil = nil,
			ghost = false,
			reviveProgress = 0,
			invulnUntil = 0,
			contactReadyAt = 0,
			revives = 0,
			replay = false,
			dirty = true,
			lastVitals = 0,
			joinedAt = now(),
			ghostParts = {},
		}
		records[player] = r
	end
	return r
end

local function refreshMaxHp(r: PlayerRun)
	local maxHp = stat(statsOf(r.player), "MaxHp", Run.Player.BaseMaxHp)
	if maxHp <= 0 then
		maxHp = Run.Player.BaseMaxHp
	end
	if maxHp ~= r.maxHp then
		if maxHp > r.maxHp and r.downedUntil == nil and not r.ghost then
			r.hp += maxHp - r.maxHp
		end
		r.maxHp = maxHp
		r.hp = math.min(r.hp, maxHp)
		r.dirty = true
	end
end

local function clearSlow(player: Player)
	player:SetAttribute("SlowMult", 1)
	player:SetAttribute("SlowUntil", 0)
end

-- Remotes payloads ---------------------------------------------------------------------------

local function timeLeft(): number
	if state.phase == "Loadout" then
		return Run.StageSeconds
	end
	if state.phase == "Ended" or state.finalWaveStart ~= nil or state.victory then
		return 0
	end
	return math.max(0, Run.StageSeconds - (now() - state.stageStart))
end

local function worldCount(): number
	return math.max(1, math.floor(Run.WorldsPerRun))
end

local function sendRunState(target: Player?)
	local payload = {
		phase = state.phase,
		timeLeft = timeLeft(),
		worldId = state.worldId,
		tier = state.tier,
		stage = state.stage,
		bossRevealed = state.bossRevealed,
		bossPosition = if state.bossRevealed then state.arche else nil,
		finalWaveSeconds = state.finalWaveSeconds,
		-- Run v2 (A04-02)
		worldIndex = state.stage,
		worldCount = worldCount(),
		overtime = state.finalWaveStart ~= nil,
		overtimeSeconds = state.finalWaveSeconds,
		overtimeStep = state.overtimeStep,
		victory = state.victory,
		cashOutPosition = state.cashOut,
		cashOutProgress = if state.victory then math.clamp(state.cashOutHold / Run.CashOut.HoldSeconds, 0, 1) else nil,
		arenaCountdown = if state.arenaEnterAt and not state.bossSpawned
			then math.max(0, Run.ArenaStartSeconds - (now() - state.arenaEnterAt))
			else nil,
		farmTimeLeft = if state.phase == "BossDefeated" then math.max(0, state.farmEndsAt - now()) else nil,
		portalPosition = state.portal,
	}
	if target then
		remotes.RunState:FireClient(target, payload)
	else
		remotes.RunState:FireAllClients(payload)
	end
end

local function vitalsOf(r: PlayerRun)
	return {
		hp = math.max(0, r.hp),
		maxHp = r.maxHp,
		shield = r.shield,
		downed = r.downedUntil ~= nil,
		downedTimeLeft = if r.downedUntil then math.max(0, r.downedUntil - now()) else nil,
		ghost = r.ghost,
		reviveProgress = if r.downedUntil then r.reviveProgress else nil,
	}
end

local function sendVitals(force: boolean)
	local t = now()
	local anyDirty = force
	for _, p in runPlayers do
		local r = records[p]
		if r and r.dirty then
			anyDirty = true
		end
	end
	if not anyDirty then
		return
	end
	local team = {}
	for _, p in runPlayers do
		local r = records[p]
		if r then
			team[tostring(p.UserId)] = { hp = math.max(0, r.hp), maxHp = r.maxHp, downed = r.downedUntil ~= nil, ghost = r.ghost }
		end
	end
	for _, p in runPlayers do
		local r = records[p]
		if r and (force or t - r.lastVitals >= 1 / Run.VitalsMaxHz) then
			local payload: { [string]: any } = vitalsOf(r)
			payload.team = team
			remotes.PlayerVitals:FireClient(p, payload)
			r.lastVitals = t
			r.dirty = false
			setLifeAttributes(r)
		end
	end
end

-- Phase changes ------------------------------------------------------------------------------

local function setPhase(phase: Types.RunPhase)
	if state.phase ~= phase then
		state.phase = phase
		state.stateDirty = true
	end
end

local function director(opts: { [string]: any })
	local enemies = find("EnemyService")
	if enemies and enemies.setDirector then
		enemies.setDirector(opts)
	end
end

local function worldIdFor(index: number): string
	local id = Run.WorldChain[math.clamp(index, 1, math.max(1, #Run.WorldChain))]
	return if id and Worlds[id] then id else Run.DefaultWorld
end

-- Id de classe jouable : un id v1 sans équivalent v2 (Astrel, Cristallin) ou inconnu devient la
-- classe par défaut, pour que stats, équipement et résumé parlent de la même classe.
local function playableClass(classId: string): string
	return if Classes[classId] then classId else Run.DefaultClass
end

local function initPlayerForRun(r: PlayerRun)
	local player = r.player
	r.classId = playableClass(r.classId)
	r.inRun = true
	r.downedUntil = nil
	r.ghost = false
	r.reviveProgress = 0
	r.shield = 0
	r.revives = 0
	r.replay = false
	setGhostLook(r, false)
	clearSlow(player)
	local stats = find("StatsService")
	if stats then
		safe(stats.resetRun, player, r.classId)
	end
	local traits = find("TraitService")
	if traits then
		safe(traits.applyClass, player, r.classId)
	end
	-- Late joiners never get Bus.RunStarted: attach their companion now (review finding 4).
	-- At run start this runs before RunStarted, which recreates every companion anyway.
	local companions = find("CompanionService")
	if companions and companions.ensure and state.phase ~= "Loadout" then
		safe(companions.ensure, player)
	end
	r.maxHp = 0
	refreshMaxHp(r)
	r.hp = r.maxHp
	r.invulnUntil = now() + 2
	r.dirty = true
	if not table.find(runPlayers, player) then
		table.insert(runPlayers, player)
	end
end

local function startStage(stage: number)
	local runId = state.runId
	state.stage = stage
	state.worldId = worldIdFor(stage)
	state.bossId = Worlds[state.worldId].boss
	state.bossRevealed = false
	state.arenaEnterAt = nil
	state.bossSpawned = false
	state.bossDefeated = false
	state.portal = nil
	table.clear(state.wavesDone)
	table.clear(state.miniBossDone)
	state.boostUntil = 0
	state.finalWaveStart = nil
	state.finalWaveSeconds = 0
	state.overtimeStep = 0
	state.overtimeFrozen = false
	state.coinsStep = 0

	local boss = find("BossService")
	if boss then
		safe(boss.despawn)
	end
	local stageService = find("StageService")
	local seed = math.random(1, 2 ^ 30)
	if stageService then
		safe(stageService.buildStage, state.worldId, stage, seed, state.bossId)
		local ok, arche = safe(stageService.getArche)
		state.arche = if ok then arche else nil
	else
		Heightmap.load(Heightmap.makeKey(state.worldId, stage, seed, state.bossId))
		local layout = Heightmap.getLayout()
		state.arche = if layout then Vector3.new(layout.arche.x, 0, layout.arche.z) else nil
	end
	local enemies = find("EnemyService")
	if enemies and enemies.beginStage then
		safe(enemies.beginStage, state.worldId, state.tier, stage)
	end

	-- Ghosts and downed players come back for the new stage.
	for index, player in runPlayers do
		local r = records[player]
		if r then
			if r.ghost or r.downedUntil then
				r.hp = math.max(r.hp, r.maxHp * Run.Coop.GhostReturnHpFraction)
			end
			r.downedUntil = nil
			r.ghost = false
			r.reviveProgress = 0
			setGhostLook(r, false)
			clearSlow(player)
			r.invulnUntil = now() + 3
			r.dirty = true
			teleport(player, spawnPointFor(index))
		end
	end

	state.stageStart = now()
	setPhase("Running")
	director({ active = true, densityMult = 1, hpMult = 1, damageMult = 1, eliteShare = Run.EliteChance, eliteMaxAlive = Run.EliteMaxAlive })
	local world = Worlds[state.worldId]
	announce("StageStart", {
		en = `World {stage}/{worldCount()} — {world.name.en}`,
		fr = `World {stage}/{worldCount()} — {world.name.en}`,
	}, 3)
	if runId == state.runId then
		Bus.StageStarted:fire(stage, state.worldId)
	end
end

local function startRun()
	state.runId += 1
	-- v2 : la run part toujours du monde 1 de Run.WorldChain (la sélection v1 monde/tier est ignorée).
	state.worldId = worldIdFor(1)
	state.tier = 1
	state.victory = false
	state.cashOut = nil
	state.cashOutHold = 0
	state.cashedOut = false
	state.firstReplayAt = nil
	table.clear(runPlayers)
	for _, player in Players:GetPlayers() do
		local r = getRecord(player)
		local progression = find("ProgressionService")
		if progression then
			local ok, classId, companionId = safe(progression.getLoadout, player)
			if ok and type(classId) == "string" then
				r.classId = classId
			end
			if ok and type(companionId) == "string" then
				r.companionId = companionId
			end
		end
		initPlayerForRun(r)
	end
	if #runPlayers == 0 then
		return
	end
	Bus.RunStarted:fire(table.clone(runPlayers), state.worldId, state.tier)
	startStage(1)
end

local function buildSummary(r: PlayerRun, victory: boolean): Types.RunSummary
	local player = r.player
	local stats = find("StatsService")
	local loot = find("LootService")
	local companion = find("CompanionService")
	local damageByWeapon: { [string]: number } = {}
	if stats and stats.getDamageByWeapon then
		local ok, map = safe(stats.getDamageByWeapon, player)
		if ok and type(map) == "table" then
			damageByWeapon = map
		end
	end
	local level, kills = 1, 0
	if stats then
		local ok, lv = safe(stats.getLevel, player)
		if ok and type(lv) == "number" then
			level = lv
		end
		-- KO comptés par StatsService (A04-03), seule source de vérité
		local okKills, n = safe(stats.getKills, player)
		if okKills and type(n) == "number" then
			kills = n
		end
	end
	local coins, chests = 0, r.player:GetAttribute("RunChestsOpened") or 0
	if loot then
		local ok, runStats = safe(loot.getRunStats, player)
		if ok and type(runStats) == "table" then
			coins = runStats.coinsEarned or 0
			chests = runStats.chestsOpened or chests
		else
			local okCoins, c = safe(loot.getCoins, player)
			coins = if okCoins and type(c) == "number" then c else 0
		end
	end
	local companionStage = 1
	if companion then
		local ok, cs = safe(companion.getState, player)
		if ok and type(cs) == "table" and type(cs.stage) == "number" then
			companionStage = cs.stage
		end
	end
	return {
		victory = victory,
		worldId = state.worldId,
		tier = state.tier,
		stageReached = state.stage, -- v2 : index du monde atteint
		kills = kills,
		damageByWeapon = damageByWeapon,
		finalWaveSeconds = math.floor(state.finalWaveSeconds),
		coinsEarned = coins,
		chestsOpened = chests :: number,
		shrinesCompleted = (r.player:GetAttribute("RunShrines") or 0) :: number,
		revives = r.revives,
		classId = r.classId,
		companionId = r.companionId,
		companionStage = companionStage,
		level = level,
		-- Champs v2 en plus du contrat Types.RunSummary (contract request A04)
		worldsCleared = (if state.victory then worldCount() else state.stage - 1) :: any,
		cashedOut = state.cashedOut :: any,
	} :: any
end

local function endRun(victory: boolean)
	if state.phase == "Ended" or state.phase == "Loadout" then
		return
	end
	setPhase("Ended")
	director({ active = false })
	local boss = find("BossService")
	if boss then
		safe(boss.despawn)
	end
	local enemies = find("EnemyService")
	if enemies then
		safe(enemies.clearAll)
	end
	local stageService = find("StageService")
	if stageService then
		safe(stageService.stopHazard)
	end
	if state.cashedOut then
		announce("CashOut", { en = "Cashed out! Rewards saved.", fr = "Cashed out! Rewards saved." }, 4)
	elseif victory then
		announce("Victory", { en = "Victory!", fr = "Victory!" }, 4)
	else
		announce("Defeat", { en = "Defeat...", fr = "Defeat..." }, 4)
	end

	local summaries: { [Player]: Types.RunSummary } = {}
	local progression = find("ProgressionService")
	for _, player in runPlayers do
		local r = records[player]
		if r then
			local summary = buildSummary(r, victory)
			if progression then
				local ok, result = safe(progression.grantRunRewards, player, summary)
				if ok and type(result) == "table" then
					summary = result
				end
			end
			summaries[player] = summary
		end
	end
	Bus.RunEnded:fire(summaries)
	for player, summary in summaries do
		if player.Parent then
			remotes.RunSummary:FireClient(player, summary)
		end
	end
	state.stateDirty = true
end

local function resetToLoadout()
	state.runId += 1
	setPhase("Loadout")
	director({ active = false })
	local boss = find("BossService")
	if boss then
		safe(boss.despawn)
	end
	local enemies = find("EnemyService")
	if enemies then
		safe(enemies.clearAll)
	end
	local stageService = find("StageService")
	if stageService then
		safe(stageService.clear)
	end
	table.clear(runPlayers)
end

-- Downed / revive / ghost --------------------------------------------------------------------

local function goDown(r: PlayerRun)
	r.hp = 0
	r.shield = 0
	r.downedUntil = now() + Run.Coop.DownedSeconds
	r.reviveProgress = 0
	r.dirty = true
	RunManager.setSlow(r.player, Run.Coop.DownedSlow, Run.Coop.DownedSeconds)
	setLifeAttributes(r)
	Bus.PlayerDowned:fire(r.player)
	announce("Downed", {
		en = `{r.player.DisplayName} is down!`,
		fr = `{r.player.DisplayName} is down!`,
	}, 2.5)
end

local function revive(r: PlayerRun, rescuer: Player)
	r.downedUntil = nil
	r.reviveProgress = 0
	r.hp = math.max(1, r.maxHp * Run.Coop.ReviveHpFraction)
	r.invulnUntil = now() + Run.Coop.ReviveInvulnerable
	r.dirty = true
	clearSlow(r.player)
	setLifeAttributes(r)
	local rr = records[rescuer]
	if rr then
		rr.revives += 1
	end
	Bus.PlayerRevived:fire(r.player, rescuer)
	announce("Revived", {
		en = `{rescuer.DisplayName} revived {r.player.DisplayName}!`,
		fr = `{rescuer.DisplayName} revived {r.player.DisplayName}!`,
	}, 2)
end

local function becomeGhost(r: PlayerRun)
	r.downedUntil = nil
	r.ghost = true
	r.reviveProgress = 0
	r.dirty = true
	clearSlow(r.player)
	setGhostLook(r, true)
	setLifeAttributes(r)
	Bus.PlayerDied:fire(r.player)
	announce("Died", {
		en = `{r.player.DisplayName} became a ghost`,
		fr = `{r.player.DisplayName} became a ghost`,
	}, 2.5)
end

local function stepCoop(dt: number)
	local t = now()
	for _, player in runPlayers do
		local r = records[player]
		if not r or not r.downedUntil then
			continue
		end
		local root = rootOf(player)
		local rescuer: Player? = nil
		if root then
			for _, other in runPlayers do
				local ro = records[other]
				if other ~= player and isActiveRecord(ro) then
					local oroot = rootOf(other)
					if oroot and (oroot.Position - root.Position).Magnitude <= Run.Coop.ReviveRadius then
						rescuer = other
						break
					end
				end
			end
		end
		local before = r.reviveProgress
		if rescuer then
			-- Cleric / Blessing : relève plus vite (PassiveService.reviveSpeed)
			local speed = 1
			local passives = find("PassiveService")
			if passives and passives.reviveSpeed then
				local ok, v = safe(passives.reviveSpeed, rescuer)
				speed = if ok and type(v) == "number" and v > 0 then v else 1
			end
			r.reviveProgress = math.min(1, r.reviveProgress + dt * speed / Run.Coop.ReviveSeconds)
		else
			r.reviveProgress = math.max(0, r.reviveProgress - dt * Run.Coop.ReviveDecay / Run.Coop.ReviveSeconds)
		end
		if r.reviveProgress ~= before then
			r.dirty = true
		end
		if rescuer and r.reviveProgress >= 1 then
			revive(r, rescuer)
		elseif t >= (r.downedUntil :: number) then
			becomeGhost(r)
		end
	end
end

-- Contact damage (15 Hz) ---------------------------------------------------------------------

local function stepContact()
	local enemies = find("EnemyService")
	if not enemies or not enemies._contactInfo then
		return
	end
	local t = now()
	local P = Run.Player
	for _, player in runPlayers do
		local r = records[player]
		if not isActiveRecord(r) or t < (r :: PlayerRun).contactReadyAt then
			continue
		end
		local root, hum = rootOf(player)
		if not root then
			continue
		end
		local rec = r :: PlayerRun
		local pos = root.Position
		local feet = feetY(root, hum)
		local n = enemies.queryRadius(pos.X, pos.Z, P.ContactHalfWidth + 4.5, queryBuffer)
		local total, touching = 0, 0
		for k = 1, n do
			local id = queryBuffer[k]
			local radius, height, damage, harmless = enemies._contactInfo(id)
			if radius and not harmless then
				local ex, ez = enemies.getPosition(id)
				if ex and ez then
					local dx, dz = ex - pos.X, ez - pos.Z
					local reach = radius + P.ContactHalfWidth
					local ey = Heightmap.getY(ex, ez)
					if dx * dx + dz * dz <= reach * reach and feet <= ey + height + P.ContactVerticalSlack and feet >= ey - P.ContactVerticalSlack - 4 then
						total += damage
						touching += 1
						if touching >= P.ContactMaxEnemies then
							break
						end
					end
				end
			end
		end
		if total > 0 then
			rec.contactReadyAt = t + P.ContactCooldown
			-- Les épines (Guardian, objets) sont rendues par PassiveService sur Bus.PlayerDamaged.
			RunManager.damagePlayer(player, total, "Contact")
		end
	end
end

-- Main tick ----------------------------------------------------------------------------------

local function anyActiveNear(position: Vector3, radius: number): boolean
	for _, player in runPlayers do
		if isActiveRecord(records[player]) then
			local root = rootOf(player)
			if root then
				local d = Vector3.new(root.Position.X - position.X, 0, root.Position.Z - position.Z).Magnitude
				if d <= radius then
					return true
				end
			end
		end
	end
	return false
end

local function allActiveNear(position: Vector3, radius: number): boolean
	local any = false
	for _, player in runPlayers do
		if isActiveRecord(records[player]) then
			any = true
			local root = rootOf(player)
			if not root then
				return false
			end
			local d = Vector3.new(root.Position.X - position.X, 0, root.Position.Z - position.Z).Magnitude
			if d > radius then
				return false
			end
		end
	end
	return any
end

local function activePlayersList(): { Player }
	local out = {}
	for _, player in runPlayers do
		if isActiveRecord(records[player]) then
			table.insert(out, player)
		end
	end
	return out
end

local function spawnMiniBoss()
	local enemies = find("EnemyService")
	local list = activePlayersList()
	if not enemies or #list == 0 then
		return
	end
	local root = rootOf(list[math.random(#list)])
	if not root then
		return
	end
	local a = math.random() * math.pi * 2
	local world = Worlds[state.worldId]
	local ok, id = safe(enemies.spawnAt, world.miniBoss, root.Position.X + math.cos(a) * 55, root.Position.Z + math.sin(a) * 55, { elite = true })
	if ok and id then
		announce("MiniBoss", { en = "A mini-boss approaches!", fr = "A mini-boss approaches!" }, 3)
	end
end

local function startBossFight()
	if state.bossSpawned or not state.arche then
		return
	end
	state.bossSpawned = true
	local arche = state.arche :: Vector3
	-- Late players are brought to the arena edge.
	for index, player in runPlayers do
		local r = records[player]
		local root = rootOf(player)
		if isActiveRecord(r) and root then
			local d = Vector3.new(root.Position.X - arche.X, 0, root.Position.Z - arche.Z).Magnitude
			if d > Run.ArenaRadius then
				local a = index / math.max(1, #runPlayers) * math.pi * 2
				local x, z = arche.X + math.cos(a) * (Run.ArenaRadius - 10), arche.Z + math.sin(a) * (Run.ArenaRadius - 10)
				teleport(player, Vector3.new(x, Heightmap.getY(x, z), z))
			end
		end
	end
	local boss = find("BossService")
	if boss then
		-- An accepted boss-challenge vote (ShrineService) enrages the boss (review finding 12).
		local shrines = find("ShrineService")
		local challenged = false
		if shrines and shrines.isBossChallengeActive then
			local ok, active = safe(shrines.isBossChallengeActive)
			challenged = ok and active == true
		end
		-- v2 : pas d'escalade automatique ; seul le défi d'autel (ShrineService) rend le boss furieux.
		safe(boss.spawnBoss, state.bossId, arche, state.stage, state.tier, #runPlayers, challenged)
	end
	if state.phase == "Running" then
		setPhase("Boss")
	end
	state.stateDirty = true
end

-- Overtime ------------------------------------------------------------------------------------

local startOvertime: (t: number, silent: boolean?) -> ()
local stepOvertime: (t: number) -> ()
local updateDirector: (t: number) -> ()

-- Facteur d'un palier : 1 + p x k (linéaire) ou (1 + p) ^ k (Run.Overtime.Compound).
local function overtimeFactor(perStep: number, k: number): number
	if Run.Overtime.Compound then
		return (1 + perStep) ^ k
	end
	return 1 + perStep * k
end

-- Difficulté moyenne des joueurs de la run (Rune Cursed, tirelire gourmande).
local function averageDifficulty(): number
	local total, n = 0, 0
	for _, player in runPlayers do
		total += math.max(0, stat(statsOf(player), "Difficulty", 0))
		n += 1
	end
	return if n > 0 then total / n else 0
end

function startOvertime(t: number, silent: boolean?)
	if state.finalWaveStart ~= nil then
		return
	end
	state.finalWaveStart = t
	state.finalWaveSeconds = 0
	state.overtimeStep = 0
	state.coinsStep = 0
	state.overtimeFrozen = false
	setPhase("FinalWave")
	Bus.FinalWaveStarted:fire()
	if not silent then
		announce("Overtime", { en = "OVERTIME! Enemies get stronger every 30 s", fr = "OVERTIME! Enemies get stronger every 30 s" }, 4)
	end
end

function stepOvertime(t: number)
	local start = state.finalWaveStart
	if not start or state.overtimeFrozen then
		return
	end
	state.finalWaveSeconds = t - start
	local k = state.finalWaveSeconds // Run.Overtime.StepSeconds
	if k > state.overtimeStep then
		state.overtimeStep = k
		state.stateDirty = true
		announce("OvertimeStep", { en = `Overtime level {k}!`, fr = `Overtime level {k}!` }, 2)
	end
	-- Pièces de survie, une fois par palier atteint
	if state.overtimeStep > state.coinsStep then
		state.coinsStep = state.overtimeStep
		local loot = find("LootService")
		local amount = Run.Overtime.CoinsPerStep * state.stage
		if loot and amount > 0 then
			for _, player in activePlayersList() do
				safe(loot.addCoins, player, amount)
			end
		end
	end
end

function updateDirector(t: number)
	local phase = state.phase
	local k = state.overtimeStep
	local O = Run.Overtime
	local difficulty = averageDifficulty()
	local density = (Run.PhaseDensity[phase] or 1)
		* (if t < state.boostUntil then state.boostMult else 1)
		* overtimeFactor(O.SpawnPerStep, k)
		* (1 + difficulty * Run.DifficultyDensityShare)
	local inOvertime = state.finalWaveStart ~= nil
	director({
		densityMult = density,
		hpMult = overtimeFactor(O.HpPerStep, k) * (1 + difficulty),
		damageMult = overtimeFactor(O.DamagePerStep, k),
		eliteShare = Run.EliteChance + O.ElitePointsPerStep * k,
		eliteMaxAlive = if inOvertime and k > 0 then math.huge else Run.EliteMaxAlive,
	})
end

local function stepRun(dt: number)
	local phase = state.phase
	if phase == "Loadout" then
		local players = Players:GetPlayers()
		if #players == 0 then
			return
		end
		local timeout = if RunService:IsStudio() then Run.StudioLoadoutTimeout else Run.LoadoutTimeout
		local allReady = true
		for _, player in players do
			local r = getRecord(player)
			if not r.ready and now() - r.joinedAt >= timeout then
				r.ready = true -- default loadout
			end
			if not r.ready then
				allReady = false
			end
		end
		if allReady then
			startRun()
		end
		return
	end
	if phase == "Ended" then
		if state.firstReplayAt then
			local all = true
			for _, player in Players:GetPlayers() do
				if not getRecord(player).replay then
					all = false
				end
			end
			if all or now() - state.firstReplayAt >= Run.ReplayTimeout then
				startRun()
			end
		end
		return
	end

	-- Tous les joueurs de la run sont partis (un retardataire peut rester sur l'écran de choix) :
	-- on ne laisse pas l'Overtime grimper dans le vide.
	if #runPlayers == 0 then
		resetToLoadout()
		return
	end

	local t = now()
	local elapsed = t - state.stageStart

	-- Vitals upkeep: max hp follows stats, regen.
	for _, player in runPlayers do
		local r = records[player]
		if r and isActiveRecord(r) then
			refreshMaxHp(r)
			local regen = stat(statsOf(player), "Regen", 0)
			if regen > 0 and r.hp < r.maxHp then
				r.hp = math.min(r.maxHp, r.hp + regen * dt)
				r.dirty = true
			end
		end
	end
	stepCoop(dt)

	-- Wipe: nobody left standing.
	-- Everyone down or ghost: no one can revive anyone, so the run ends now.
	-- Après la victoire (Keep going), la run reste gagnée : seuls les gains de l'Overtime s'arrêtent.
	if #runPlayers > 0 and #activePlayersList() == 0 then
		endRun(state.victory)
		return
	end

	-- Hazards
	local stageService = find("StageService")
	if stageService and phase ~= "BossDefeated" then
		local ok, event = safe(stageService.updateHazard, elapsed)
		local world = Worlds[state.worldId]
		if ok and event == "warn" then
			announce("Hazard", world.hazard.label, world.hazard.warn)
		end
	end

	local left = Run.StageSeconds - elapsed

	-- Waves at 6:00 and 3:00 remaining
	if phase == "Running" or phase == "Boss" then
		for index, wave in Run.Waves do
			if not state.wavesDone[index] and left <= wave.timeLeft then
				state.wavesDone[index] = true
				state.boostUntil = t + wave.boostSeconds
				state.boostMult = wave.boost
				local enemies = find("EnemyService")
				if enemies then
					local size = wave.size * (1 + Balance.DensityPerExtraPlayer * (#runPlayers - 1))
					safe(enemies.burst, math.floor(size), wave.spawnSeconds)
				end
				announce("Wave", { en = "Wave incoming!", fr = "Wave incoming!" }, 3)
			end
		end
		for index, at in Run.MiniBossAt do
			if not state.miniBossDone[index] and elapsed >= at then
				state.miniBossDone[index] = true
				spawnMiniBoss()
			end
		end
	end

	-- Arche reveal and arena
	local arche = state.arche
	if arche and not state.bossDefeated then
		if not state.bossRevealed and anyActiveNear(arche, Run.ArcheRevealRadius) then
			state.bossRevealed = true
			state.stateDirty = true
			Bus.BossRevealed:fire(arche)
			announce("ArcheRevealed", { en = "The boss Arch has been found!", fr = "The boss Arch has been found!" }, 3)
		end
		if state.bossRevealed and not state.bossSpawned then
			if not state.arenaEnterAt and anyActiveNear(arche, Run.ArenaRadius) then
				state.arenaEnterAt = t
				state.stateDirty = true
				announce("ArenaCountdown", {
					en = `The fight starts in {Run.ArenaStartSeconds} s`,
					fr = `The fight starts in {Run.ArenaStartSeconds} s`,
				}, 3)
			end
			if state.arenaEnterAt and (allActiveNear(arche, Run.ArenaRadius) or t - state.arenaEnterAt >= Run.ArenaStartSeconds) then
				startBossFight()
			end
		end
	end

	-- Chrono à zéro : Overtime (le boss reste tuable pour avancer)
	if (phase == "Running" or phase == "Boss") and left <= 0 then
		startOvertime(t)
	end
	stepOvertime(t)

	-- Directeur : densité de phase et de vague, escalade d'Overtime, Rune Cursed
	updateDirector(t)

	-- Boss tué (hors dernier monde) : fenêtre de farm, puis portail vers le monde suivant.
	if state.phase == "BossDefeated" and not state.victory then
		local portal = state.portal
		local go = t >= state.farmEndsAt
			or (portal ~= nil and t >= state.portalOpensAt and allActiveNear(portal, Run.PortalRadius))
		if go then
			startStage(state.stage + 1)
		end
	end

	-- Après la victoire : Cash out quand tous les joueurs actifs sont dans le portail doré.
	local cashOut = state.cashOut
	if state.victory and cashOut then
		if t >= state.portalOpensAt and allActiveNear(cashOut, Run.CashOut.Radius) then
			state.cashOutHold += dt
			state.stateDirty = true
			if state.cashOutHold >= Run.CashOut.HoldSeconds then
				state.cashedOut = true
				endRun(true)
			end
		elseif state.cashOutHold > 0 then
			state.cashOutHold = 0
			state.stateDirty = true
		end
	end
end

local function onBossDefeated(_bossId: string, _stage: number)
	if state.phase == "Ended" or state.phase == "Loadout" or state.victory then
		return
	end
	state.bossDefeated = true
	state.portalOpensAt = now() + Run.PortalGrace
	local arche = state.arche
	local portal: Vector3? = nil
	if arche then
		local x, z = arche.X, arche.Z + Run.PortalOffset
		portal = Vector3.new(x, Heightmap.getY(x, z), z)
	end
	local stageService = find("StageService")
	if stageService then
		safe(stageService.stopHazard)
	end
	local last = state.stage >= worldCount()
	if last then
		-- Victoire : portail doré Cash out ; sinon on continue (Keep going = Overtime infini).
		state.victory = true
		state.cashOut = portal
		state.cashOutHold = 0
		if portal and stageService then
			safe(stageService.showCashOut, portal)
		end
		announce("Victory", {
			en = "VICTORY! Step into the gold portal to Cash out, or keep going for more KOs",
			fr = "VICTORY! Step into the gold portal to Cash out, or keep going for more KOs",
		}, 6)
		if state.finalWaveStart then
			setPhase("FinalWave")
			state.overtimeFrozen = false
		else
			startOvertime(now(), true) -- la bannière Victory reste à l'écran
		end
	else
		state.farmEndsAt = now() + Run.FarmSeconds
		state.overtimeFrozen = true
		setPhase("BossDefeated")
		state.portal = portal
		if portal and stageService then
			safe(stageService.showPortal, portal)
		end
		announce("Portal", {
			en = `Portal open! Next world in {Run.FarmSeconds} s (or step into the portal)`,
			fr = `Portal open! Next world in {Run.FarmSeconds} s (or step into the portal)`,
		}, 4)
	end
	state.stateDirty = true
end

-- Public API (ARCHITECTURE section 4) --------------------------------------------------------

function RunManager.getPhase(): Types.RunPhase
	return state.phase
end

function RunManager.getTimeLeft(): number
	return timeLeft()
end

function RunManager.getRunPlayers(): { Player }
	return table.clone(runPlayers)
end

function RunManager.getLoadout(player: Player): (string, string)
	local r = records[player]
	if r then
		return r.classId, r.companionId
	end
	return Run.DefaultClass, Run.DefaultCompanion
end

-- dodge -> armor -> shield -> hp; returns damage actually taken (shield + hp).
function RunManager.damagePlayer(player: Player, amount: number, _source: string): number
	local r = records[player]
	if not isActiveRecord(r) or type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return 0
	end
	local rec = r :: PlayerRun
	if now() < rec.invulnUntil then
		return 0
	end
	-- Knight / Valor : parade d'un coup toutes les 8 s (PassiveService)
	local passives = find("PassiveService")
	if passives and passives.tryBlock then
		local ok, blocked = safe(passives.tryBlock, player, amount, _source)
		if ok and blocked == true then
			return 0
		end
	end
	local block = statsOf(player)
	local dodge = math.clamp(stat(block, "Dodge", 0), 0, Run.Player.DodgeCap)
	if dodge > 0 and math.random() < dodge then
		return 0
	end
	local armor = math.max(0, stat(block, "Armor", 0))
	local dmg = amount * Run.Player.ArmorK / (Run.Player.ArmorK + armor)
	local taken = 0
	if rec.shield > 0 then
		local absorbed = math.min(rec.shield, dmg)
		rec.shield -= absorbed
		dmg -= absorbed
		taken += absorbed
	end
	if dmg > 0 then
		local hpLoss = math.min(rec.hp, dmg)
		rec.hp -= dmg
		taken += hpLoss
	end
	rec.dirty = true
	Bus.PlayerDamaged:fire(player, taken, _source)
	if rec.hp <= 0 then
		goDown(rec)
	end
	return taken
end

function RunManager.healPlayer(player: Player, amount: number)
	local r = records[player]
	if not isActiveRecord(r) or type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return
	end
	local rec = r :: PlayerRun
	rec.hp = math.min(rec.maxHp, rec.hp + amount)
	rec.dirty = true
end

function RunManager.isDowned(player: Player): boolean
	local r = records[player]
	return r ~= nil and r.downedUntil ~= nil
end

function RunManager.isActive(player: Player): boolean
	return isActiveRecord(records[player]) and (state.phase ~= "Loadout" and state.phase ~= "Ended")
end

function RunManager.setInvulnerable(player: Player, seconds: number)
	local r = records[player]
	if r and type(seconds) == "number" and seconds == seconds then
		r.invulnUntil = math.max(r.invulnUntil, now() + math.clamp(seconds, 0, 30))
	end
end

-- Sets Player attributes SlowMult (number) and SlowUntil (Workspace:GetServerTimeNow() based),
-- read by the avatar domain's MovementController. The strongest active slow wins.
function RunManager.setSlow(player: Player, multiplier: number, seconds: number)
	if type(multiplier) ~= "number" or type(seconds) ~= "number" or multiplier ~= multiplier or seconds ~= seconds then
		return
	end
	local serverNow = Workspace:GetServerTimeNow()
	local currentUntil = player:GetAttribute("SlowUntil")
	local currentMult = player:GetAttribute("SlowMult")
	local mult = math.clamp(multiplier, 0, 1)
	local untilT = serverNow + math.clamp(seconds, 0, 60)
	if type(currentUntil) == "number" and currentUntil > serverNow and type(currentMult) == "number" then
		if currentMult < mult then
			-- A stronger slow is running: keep it, extend only if ours lasts longer at its strength.
			return
		end
		untilT = math.max(untilT, if currentMult == mult then currentUntil else untilT)
	end
	player:SetAttribute("SlowMult", mult)
	player:SetAttribute("SlowUntil", untilT)
end

function RunManager.getRunInfo(): { worldId: string, tier: number, stage: number }
	return { worldId = state.worldId, tier = state.tier, stage = state.stage }
end

-- Extra (contract request): shield points absorbed before hp, capped.
function RunManager.addShield(player: Player, amount: number, cap: number?)
	local r = records[player]
	if not isActiveRecord(r) or type(amount) ~= "number" or amount ~= amount then
		return
	end
	local rec = r :: PlayerRun
	local limit = if type(cap) == "number" then cap else rec.maxHp
	rec.shield = math.clamp(rec.shield + amount, 0, math.max(limit, rec.shield))
	rec.dirty = true
end

-- Extra (combat, même agent) : PV / PV max du joueur (Rage du Barbarian). 1 hors run.
function RunManager.getHpFraction(player: Player): number
	local r = records[player]
	if not r or r.maxHp <= 0 then
		return 1
	end
	return math.clamp(r.hp / r.maxHp, 0, 1)
end

-- Extra: true while a player is a ghost (ShrineService may also read the Ghost attribute).
function RunManager.isGhost(player: Player): boolean
	local r = records[player]
	return r ~= nil and r.ghost
end

-- Run-domain internal (BossService, StageService).
function RunManager._announce(kind: string, text: Types.LocalizedText, duration: number)
	announce(kind, text, duration)
end

-- Lifecycle ----------------------------------------------------------------------------------

local function onCharacterAdded(player: Player, character: Model)
	local hum = character:WaitForChild("Humanoid", 10)
	if hum and hum:IsA("Humanoid") then
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	local r = records[player]
	if r and r.inRun and state.phase ~= "Loadout" and state.phase ~= "Ended" then
		task.defer(function()
			local index = table.find(runPlayers, player) or 1
			teleport(player, spawnPointFor(index))
			if r.ghost then
				setGhostLook(r, true)
			end
		end)
	end
end

local function onReady(player: Player)
	local r = getRecord(player)
	local progression = find("ProgressionService")
	-- Un joueur déjà dans la run garde sa classe jusqu'à la fin (résumé = classe jouée).
	if progression and not r.inRun then
		local ok, classId, companionId = safe(progression.getLoadout, player)
		if ok and type(classId) == "string" then
			r.classId = classId
		end
		if ok and type(companionId) == "string" then
			r.companionId = companionId
		end
	end
	r.ready = true
	-- Late joiner: enter the running run at the stage spawn.
	if not r.inRun and state.phase ~= "Loadout" and state.phase ~= "Ended" then
		initPlayerForRun(r)
		teleport(player, spawnPointFor(#runPlayers))
		state.stateDirty = true
	end
end

function RunManager.init()
	for _, name in { "RunState", "Announce", "PlayerVitals", "RunSummary" } do
		remotes[name] = Net.event(name)
	end

	-- Loadout choice is handled by the data domain; we only note that the player is ready.
	Net.onServerEvent("SelectLoadout", 4, function(player: Player, classId: unknown, companionId: unknown)
		if type(classId) ~= "string" or type(companionId) ~= "string" or #classId > 40 or #companionId > 40 then
			return
		end
		task.delay(0.2, function()
			if player.Parent then
				local r = getRecord(player)
				-- Sans domaine data (test isolé) : seuls les ids de classe connus sont acceptés.
				if not find("ProgressionService") and not r.inRun and Classes[classId] then
					r.classId, r.companionId = classId, companionId
				end
				onReady(player)
			end
		end)
	end)

	Net.onServerEvent("SelectStage", 4, function(player: Player, worldId: unknown, tier: unknown)
		if type(worldId) ~= "string" or not Worlds[worldId] then
			return
		end
		if type(tier) ~= "number" or tier ~= math.floor(tier) or tier < 1 or tier > 3 then
			return
		end
		if state.phase ~= "Loadout" and state.phase ~= "Ended" then
			return
		end
		local allowed = worldId == Run.DefaultWorld and tier == 1
		local progression = find("ProgressionService")
		-- Data domain names it isWorldUnlocked(player, worldId, tier) (integration fix).
		local isUnlocked = progression and (progression.isStageUnlocked or progression.isWorldUnlocked)
		if isUnlocked then
			local ok, result = safe(isUnlocked, player, worldId, tier)
			allowed = allowed or (ok and result == true)
		elseif RunService:IsStudio() and Run.Debug.AllowAnyStageInStudio then
			allowed = true
		end
		if allowed then
			state.selectedWorld = worldId
			state.selectedTier = tier
			state.stateDirty = true
		end
	end)

	Net.onServerEvent("Replay", 2, function(player: Player)
		if state.phase ~= "Ended" then
			return
		end
		getRecord(player).replay = true
		state.firstReplayAt = state.firstReplayAt or now()
	end)

	Bus.ChestOpened:connect(function(player: Player)
		if typeof(player) == "Instance" and player:IsA("Player") then
			player:SetAttribute("RunChestsOpened", ((player:GetAttribute("RunChestsOpened") or 0) :: number) + 1)
		end
	end)
	Bus.ShrineCompleted:connect(function(players: { Player })
		if type(players) == "table" then
			for _, p in players do
				if typeof(p) == "Instance" and p:IsA("Player") then
					p:SetAttribute("RunShrines", ((p:GetAttribute("RunShrines") or 0) :: number) + 1)
				end
			end
		end
	end)
	Bus.RunStarted:connect(function(players: { Player })
		for _, p in players do
			p:SetAttribute("RunChestsOpened", 0)
			p:SetAttribute("RunShrines", 0)
		end
	end)
	Bus.BossDefeated:connect(onBossDefeated)

	Players.PlayerAdded:Connect(function(player)
		getRecord(player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		task.defer(sendRunState, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local i = table.find(runPlayers, player)
		if i then
			table.remove(runPlayers, i)
		end
		records[player] = nil
		if #Players:GetPlayers() <= 1 and state.phase ~= "Loadout" then
			task.defer(function()
				if #Players:GetPlayers() == 0 then
					resetToLoadout()
				end
			end)
		end
	end)
end

-- Commandes de test (Studio seulement, Run.Debug.StudioCommands). En Play, barre de commande
-- réglée sur la vue Server (bouton Client/Server de l'onglet Test), puis :
--   game.ServerStorage.CohueRunDebug:Invoke("state")
--   :Invoke("skip", 590)        avance le chrono du monde de 590 s
--   :Invoke("xp", 500)          donne 500 XP à chaque joueur de la run
--   :Invoke("weapon", "Longbow", 8)   ajoute / monte une arme
--   :Invoke("rune", "Damage", 5)      ajoute / monte une Rune
--   :Invoke("arche")            téléporte l'équipe à l'Arche (boss)
--   :Invoke("killboss")         inflige des dégâts énormes au boss
--   :Invoke("world", 3)         saute au monde 3
--   :Invoke("class", "Cleric")  change la classe de l'équipe pour la suite de la run (test)
-- Rien de tout ça n'existe hors Studio : aucun remote, aucun accès client.
local function installStudioCommands()
	if not (RunService:IsStudio() and Run.Debug.StudioCommands) then
		return
	end
	local fn = Instance.new("BindableFunction")
	fn.Name = "CohueRunDebug"
	fn.OnInvoke = function(cmd: string, a: any, b: any): any
		local stats = find("StatsService")
		if cmd == "skip" and type(a) == "number" then
			state.stageStart -= a
			if state.finalWaveStart then
				state.finalWaveStart -= a
			end
			local enemies = find("EnemyService")
			if enemies and enemies._debugSkip then
				enemies._debugSkip(a)
			end
			return timeLeft()
		elseif cmd == "xp" and type(a) == "number" and stats then
			for _, p in runPlayers do
				stats.addXp(p, a)
			end
			return true
		elseif cmd == "weapon" and type(a) == "string" and stats then
			for _, p in runPlayers do
				stats.upgradeWeapon(p, a, if type(b) == "number" then b else 1, 0)
			end
			return true
		elseif cmd == "rune" and type(a) == "string" and stats then
			for _, p in runPlayers do
				stats.upgradeGrimoire(p, a, if type(b) == "number" then b else 1)
			end
			return true
		elseif cmd == "arche" and state.arche then
			local arche = state.arche :: Vector3
			for i, p in runPlayers do
				local x, z = arche.X + i * 4, arche.Z + 12
				teleport(p, Vector3.new(x, Heightmap.getY(x, z), z))
			end
			return true
		elseif cmd == "killboss" then
			local boss = find("BossService")
			local enemies = find("EnemyService")
			local entity = boss and (boss :: any)._entityId and (boss :: any)._entityId()
			if entity and enemies then
				return enemies.damage(entity, 1e9, runPlayers[1])
			end
			return "no boss"
		elseif cmd == "class" and type(a) == "string" then
			local traits = find("TraitService")
			for _, p in runPlayers do
				local rec = records[p]
				if rec then
					rec.classId = a
				end
				if stats then
					stats.resetRun(p, a)
				end
				if traits then
					safe(traits.applyClass, p, a)
				end
			end
			return if stats and runPlayers[1] then stats.getClass(runPlayers[1]) else nil
		elseif cmd == "world" and type(a) == "number" then
			startStage(math.clamp(math.floor(a), 1, worldCount()))
			return state.stage
		end
		local kills = {}
		for _, p in runPlayers do
			kills[p.Name] = if stats then stats.getKills(p) else 0
		end
		return {
			phase = state.phase,
			world = state.stage,
			worldId = state.worldId,
			timeLeft = timeLeft(),
			overtime = state.finalWaveStart ~= nil,
			overtimeSeconds = state.finalWaveSeconds,
			overtimeStep = state.overtimeStep,
			victory = state.victory,
			cashedOut = state.cashedOut,
			kills = kills,
			enemies = (find("EnemyService") and find("EnemyService").getCount()) or 0,
		}
	end
	fn.Parent = game:GetService("ServerStorage")
end

function RunManager.start()
	installStudioCommands()
	for _, player in Players:GetPlayers() do
		getRecord(player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
	end
	local mainAcc, contactAcc, stateAcc = 0, 0, 0
	RunService.Heartbeat:Connect(function(dt)
		contactAcc += dt
		if contactAcc >= CONTACT_DT then
			contactAcc = math.min(contactAcc - CONTACT_DT, CONTACT_DT)
			stepContact()
		end
		mainAcc += dt
		stateAcc += dt
		if mainAcc >= MAIN_DT then
			local step = mainAcc
			mainAcc = 0
			local before = state.phase
			stepRun(math.min(step, 0.5))
			if state.phase ~= before then
				state.stateDirty = true
			end
			sendVitals(false)
		end
		if state.stateDirty or stateAcc >= 1 then
			state.stateDirty = false
			local full = stateAcc >= 1
			stateAcc = if full then 0 else stateAcc
			sendRunState()
			if full then
				sendVitals(true)
			end
		end
	end)
end

return RunManager
