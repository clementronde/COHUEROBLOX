--!strict
-- Run flow, timers, coop rules and player vitals (dossier 20 sections 1, 2, 6).
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
	mode = (if Run.SurvivalEnabled and Run.Mode == "Survival" then "Survival" else "Adventure") :: string,
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
	portal = nil :: Vector3?,
	wavesDone = {} :: { [number]: boolean },
	miniBossDone = {} :: { [number]: boolean },
	boostUntil = 0,
	boostMult = 1,
	finalWaveStart = nil :: number?,
	finalWaveSeconds = 0,
	nextCoinsAt = 0,
	survivalTier = 0,
	nextSurvivalElite = 0,
	nextSurvivalMiniBoss = 0,
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
	if state.phase == "Loadout" or state.phase == "Ended" or state.mode == "Survival" then
		return if state.phase == "Ended" then 0 else Run.StageSeconds
	end
	return math.max(0, Run.StageSeconds - (now() - state.stageStart))
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
		mode = state.mode,
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

local function bossIdFor(stage: number): string
	local world = Worlds[state.worldId]
	if state.tier >= 3 and stage >= 3 then
		return world.finalBoss
	end
	return world.boss
end

local function initPlayerForRun(r: PlayerRun)
	local player = r.player
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
	state.bossId = if state.mode == "Survival" then "" else bossIdFor(stage)
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
	state.survivalTier = 0

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
	state.nextCoinsAt = 0
	state.nextSurvivalElite = now() + Run.Survival.EliteEvery
	state.nextSurvivalMiniBoss = now() + Run.Survival.MiniBossEvery
	setPhase("Running")
	director({ active = true, densityMult = 1, hpMult = 1, damageMult = 1, finalWave = false })
	local world = Worlds[state.worldId]
	announce("StageStart", {
		fr = `{world.name.fr} — stage {stage}/{state.tier}`,
		en = `{world.name.en} — stage {stage}/{state.tier}`,
	}, 3)
	if runId == state.runId then
		Bus.StageStarted:fire(stage, state.worldId)
	end
end

local function startRun()
	state.runId += 1
	state.worldId = if Worlds[state.selectedWorld] then state.selectedWorld else Run.DefaultWorld
	state.tier = math.clamp(state.selectedTier, 1, 3)
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
		stageReached = state.stage,
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
	}
end

local function endRun(victory: boolean)
	if state.phase == "Ended" or state.phase == "Loadout" then
		return
	end
	setPhase("Ended")
	director({ active = false, finalWave = false })
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
	announce(if victory then "Victory" else "Defeat", if victory
		then { fr = "Victoire !", en = "Victory!" }
		else { fr = "Défaite...", en = "Defeat..." }, 4)

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
		fr = `{r.player.DisplayName} est à terre !`,
		en = `{r.player.DisplayName} is down!`,
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
		fr = `{rescuer.DisplayName} relève {r.player.DisplayName} !`,
		en = `{rescuer.DisplayName} revived {r.player.DisplayName}!`,
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
		fr = `{r.player.DisplayName} devient un fantôme`,
		en = `{r.player.DisplayName} became a ghost`,
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
			r.reviveProgress = math.min(1, r.reviveProgress + dt / Run.Coop.ReviveSeconds)
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
		local firstId: number? = nil
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
						firstId = firstId or id
						if touching >= P.ContactMaxEnemies then
							break
						end
					end
				end
			end
		end
		if total > 0 then
			rec.contactReadyAt = t + P.ContactCooldown
			local taken = RunManager.damagePlayer(player, total, "Contact")
			local thorns = stat(statsOf(player), "Thorns", 0)
			if taken > 0 and thorns > 0 and firstId then
				safe(enemies.damage, firstId, taken * thorns, player)
			end
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
	safe(enemies.spawnAt, world.miniBoss, root.Position.X + math.cos(a) * 55, root.Position.Z + math.sin(a) * 55, { elite = true })
	announce("MiniBoss", { fr = "Un mini-boss approche !", en = "A mini-boss approaches!" }, 3)
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
		safe(boss.spawnBoss, state.bossId, arche, state.stage, state.tier, #runPlayers, state.stage == 2 or challenged)
	end
	if state.phase == "Running" then
		setPhase("Boss")
	end
	state.stateDirty = true
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
	if #runPlayers > 0 and #activePlayersList() == 0 then
		endRun(false)
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

	-- Director density
	local density = (Run.PhaseDensity[phase] or 1) * (if t < state.boostUntil then state.boostMult else 1)

	if state.mode == "Survival" then
		state.finalWaveSeconds = elapsed
		local tierNow = elapsed // Run.Survival.TierSeconds
		if tierNow > state.survivalTier then
			state.survivalTier = tierNow
			announce("SurvivalTier", { fr = `Palier {tierNow} !`, en = `Tier {tierNow}!` }, 2.5)
		end
		local k = state.survivalTier
		director({
			densityMult = density * (1 + Run.Survival.DensityPerTier * k),
			hpMult = Run.Survival.HpPerTier ^ k,
			damageMult = Run.Survival.DamagePerTier ^ k,
		})
		if t >= state.nextSurvivalElite then
			state.nextSurvivalElite = t + Run.Survival.EliteEvery
			local enemies = find("EnemyService")
			if enemies then
				safe(enemies.forceEliteSoon)
			end
		end
		if t >= state.nextSurvivalMiniBoss then
			state.nextSurvivalMiniBoss = t + Run.Survival.MiniBossEvery
			spawnMiniBoss()
		end
		if elapsed >= state.nextCoinsAt + 30 then
			state.nextCoinsAt += 30
			local loot = find("LootService")
			for _, player in activePlayersList() do
				if loot then
					safe(loot.addCoins, player, Run.Survival.CoinsPer30s)
				end
			end
		end
		return
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
				announce("Wave", { fr = "Vague renforcée !", en = "Wave incoming!" }, 3)
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
			announce("ArcheRevealed", { fr = "L'Arche du boss est trouvée !", en = "The boss Arch has been found!" }, 3)
		end
		if state.bossRevealed and not state.bossSpawned then
			if not state.arenaEnterAt and anyActiveNear(arche, Run.ArenaRadius) then
				state.arenaEnterAt = t
				state.stateDirty = true
				announce("ArenaCountdown", {
					fr = `Le combat commence dans {Run.ArenaStartSeconds} s`,
					en = `The fight starts in {Run.ArenaStartSeconds} s`,
				}, 3)
			end
			if state.arenaEnterAt and (allActiveNear(arche, Run.ArenaRadius) or t - state.arenaEnterAt >= Run.ArenaStartSeconds) then
				startBossFight()
			end
		end
	end

	-- Timer at zero: Final Wave
	if (phase == "Running" or phase == "Boss") and left <= 0 then
		setPhase("FinalWave")
		state.finalWaveStart = t
		state.nextCoinsAt = t + 30
		director({ finalWave = true })
		Bus.FinalWaveStarted:fire()
		announce("FinalWave", { fr = "VAGUE FINALE !", en = "FINAL WAVE!" }, 4)
	end
	if state.phase == "FinalWave" and state.finalWaveStart then
		state.finalWaveSeconds = t - state.finalWaveStart
		local blocks = state.finalWaveSeconds // 30
		director({ finalWave = true, hpMult = 1 + Run.FinalWaveHpRampPer30s * blocks })
		if t >= state.nextCoinsAt then
			state.nextCoinsAt += 30
			local loot = find("LootService")
			local amount = Run.FinalWaveCoinsPer30s * state.tier
			for _, player in activePlayersList() do
				if loot then
					safe(loot.addCoins, player, amount)
				end
			end
			announce("FinalWaveCoins", { fr = `+{amount} pièces de survie`, en = `+{amount} survival coins` }, 2)
		end
	else
		director({ densityMult = density })
	end

	-- Boss defeated: farm window, then portal.
	if state.phase == "BossDefeated" then
		local portal = state.portal
		local go = t >= state.farmEndsAt or (portal ~= nil and allActiveNear(portal, Run.PortalRadius))
		if go then
			if state.stage < state.tier then
				startStage(state.stage + 1)
			else
				endRun(true)
			end
		end
	end
end

local function onBossDefeated(_bossId: string, _stage: number)
	if state.phase == "Ended" or state.phase == "Loadout" then
		return
	end
	state.bossDefeated = true
	state.farmEndsAt = now() + Run.FarmSeconds
	state.finalWaveStart = nil
	setPhase("BossDefeated")
	director({ finalWave = false, hpMult = 1, densityMult = 1 })
	local arche = state.arche
	if arche then
		local portal = Vector3.new(arche.X, Heightmap.getY(arche.X, arche.Z), arche.Z)
		state.portal = portal
		local stageService = find("StageService")
		if stageService then
			safe(stageService.showPortal, portal)
			safe(stageService.stopHazard)
		end
	end
	local last = state.stage >= state.tier
	announce("Portal", if last
		then { fr = `Victoire ! Fin de la run dans {Run.FarmSeconds} s (ou entrez dans le portail)`, en = `Victory! Run ends in {Run.FarmSeconds} s (or step into the portal)` }
		else { fr = `Portail ouvert ! Stage suivant dans {Run.FarmSeconds} s`, en = `Portal open! Next stage in {Run.FarmSeconds} s` }, 4)
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
	Bus.PlayerDamaged:fire(player, taken)
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
	if progression then
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
				if not find("ProgressionService") then
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

function RunManager.start()
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
