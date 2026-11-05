--!strict
-- Lobby <-> run teleports (data domain). ONLY active when Config.Run.UseLobbyPlace == true.
-- Design: docs/dossier/70-donnees-progression-monetisation.md section 15.
-- Vault: "Teleporting and Multi-Place Games", "TeleportService - Engine Reference Card",
-- "Reserved and Private Servers in Practice", "Parties and Group Teleports", "MemoryStore Service".
--
-- Rules: run config travels through MemoryStore keyed by the reserved server id (never TeleportData);
-- TeleportOptions.ReservedServerId only (one routing field); profiles released before TeleportAsync
-- and re-acquired on TeleportInitFailed / watchdog; arrivals validated, default deny.

local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Progression = require(Config:WaitForChild("Progression"))
local Net = require(Shared:WaitForChild("Net"))
local Registry = require(Shared:WaitForChild("Registry"))

local PLACES = Progression.Places
local IS_STUDIO = RunService:IsStudio()
local CALL_BACKOFF = { 1, 2, 4, 8 }
local MAX_LATE_RETRIES = 2

export type RunConfig = {
	v: number,
	kind: string, -- "Run" | "VipRoom"
	worldId: string?,
	tier: number?,
	members: { number },
	loadouts: { [string]: { classId: string, companionId: string, companionId2: string? } }?,
	owner: number?,
	sourcePlaceId: number,
	createdAt: number,
}

local MatchService = {}

local active = false
local busy: { [Player]: boolean } = {}
local lateRetries: { [Player]: number } = {}
local teleportingSince: { [Player]: number } = {}

-- Run-server state
local runConfig: RunConfig? = nil
local arrived: { [number]: boolean } = {}
local arrivalLoadout: { [Player]: { classId: string, companionId: string, companionId2: string? } } = {}

local function readUseLobbyPlace(): boolean
	local module = Config:FindFirstChild("Run")
	if not module or not module:IsA("ModuleScript") then
		return false
	end
	local ok, run = pcall(require, module)
	return ok and type(run) == "table" and (run :: any).UseLobbyPlace == true
end

local function dataService(): any
	return Registry.get("DataService")
end

local function progression(): any
	return Registry.get("ProgressionService")
end

local function sendState(player: Player, state: string, fr: string?, en: string?)
	if player.Parent then
		Net.event("MatchState"):FireClient(player, {
			state = state,
			reason = if fr and en then { fr = fr, en = en } else nil,
		})
	end
end

---------------------------------------------------------------------------------------------------
-- MemoryStore (with a Studio-only in-memory fallback)
---------------------------------------------------------------------------------------------------
local memoryFallback: { [string]: any }? = nil
local hashMap: MemoryStoreHashMap? = nil

local function getMap(): MemoryStoreHashMap?
	if hashMap then
		return hashMap
	end
	local ok, map = pcall(function()
		return MemoryStoreService:GetHashMap(PLACES.RunConfigMap)
	end)
	if ok then
		hashMap = map
		return map
	end
	return nil
end

local function memSet(key: string, value: any, ttl: number): boolean
	if memoryFallback then
		memoryFallback[key] = value
		return true
	end
	local map = getMap()
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			-- lihfolk-ignore: datastore-setasync-player -- MemoryStore run ticket keyed by a fresh server GUID, not player data
			(map :: MemoryStoreHashMap):SetAsync(key, value, ttl)
		end)
		if ok and map then
			return true
		end
		if IS_STUDIO then
			warn(`[MatchService] MemoryStore unavailable in Studio ({err}): using an in-memory table`)
			memoryFallback = { [key] = value }
			return true
		end
		task.wait(attempt)
	end
	return false
end

local function memGet(key: string, attempts: number): any?
	if memoryFallback then
		return memoryFallback[key]
	end
	local map = getMap()
	for attempt = 1, attempts do
		local ok, value = pcall(function()
			return (map :: MemoryStoreHashMap):GetAsync(key)
		end)
		if ok and map then
			return value
		end
		task.wait(attempt)
	end
	return nil
end

local function memRemove(key: string)
	if memoryFallback then
		memoryFallback[key] = nil
		return
	end
	local map = getMap()
	if map then
		pcall(function()
			map:RemoveAsync(key)
		end)
	end
end

---------------------------------------------------------------------------------------------------
-- Teleport sequence: release -> TeleportAsync (retries) -> reacquire on failure
---------------------------------------------------------------------------------------------------
local function reacquire(player: Player, reasonFr: string, reasonEn: string)
	teleportingSince[player] = nil
	lateRetries[player] = nil
	busy[player] = nil
	if player.Parent then
		local ok = dataService().reacquire(player)
		if ok then
			sendState(player, "Failed", reasonFr, reasonEn)
		end
	end
end

local function teleportCall(placeId: number, group: { Player }, options: TeleportOptions?): boolean
	for try = 1, #CALL_BACKOFF do
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(placeId, group, options)
		end)
		if ok then
			return true
		end
		warn(`[MatchService] TeleportAsync try {try} failed: {err}`)
		task.wait(CALL_BACKOFF[try])
	end
	return false
end

-- Releases every profile, then teleports. Re-acquires everyone on failure. Yields.
local function releaseAndTeleport(group: { Player }, placeId: number, options: TeleportOptions?): boolean
	local released: { Player } = {}
	for _, p in group do
		if p.Parent and dataService().releaseForTeleport(p) then
			table.insert(released, p)
		else
			for _, r in released do
				reacquire(r, "Un coéquipier n'a pas pu sauvegarder : départ annulé.", "A teammate couldn't save: departure cancelled.")
			end
			for _, other in group do
				busy[other] = nil
				sendState(other, "Failed", "Sauvegarde impossible : réessaie.", "Couldn't save: please try again.")
			end
			return false
		end
	end
	for _, p in released do
		sendState(p, "Teleporting")
		teleportingSince[p] = os.clock()
	end
	if not teleportCall(placeId, released, options) then
		for _, p in released do
			reacquire(p, "La téléportation a échoué : réessaie.", "Teleport failed: please try again.")
		end
		return false
	end
	-- Watchdog: still here after the window => the hop failed silently.
	for _, p in released do
		local since = teleportingSince[p]
		task.delay(PLACES.TeleportWatchdog, function()
			if p.Parent and teleportingSince[p] == since then
				reacquire(p, "La téléportation n'a pas abouti.", "The teleport did not complete.")
			end
		end)
	end
	return true
end

local function onTeleportInitFailed(player: Player, result: Enum.TeleportResult, message: string, placeId: number, options: TeleportOptions)
	if not active or not teleportingSince[player] then
		return
	end
	local used = lateRetries[player] or 0
	local retryable = result == Enum.TeleportResult.Flooded or result == Enum.TeleportResult.Failure
	local progressionService = Registry.find("ProgressionService")
	if progressionService then
		pcall(progressionService.logCustom, player, "TeleportFail", 1, { result.Name })
	end
	if not retryable or used >= MAX_LATE_RETRIES then
		warn(`[MatchService] {player.Name} stays here: {result.Name} {message}`)
		reacquire(player, "La téléportation a échoué : tu restes ici.", "Teleport failed: you stay here.")
		return
	end
	lateRetries[player] = used + 1
	task.wait(if result == Enum.TeleportResult.Flooded then 10 else 2)
	if player.Parent and teleportingSince[player] then
		teleportingSince[player] = os.clock() -- restart the watchdog window
		local since = teleportingSince[player]
		-- The event's options already target the same destination (ReservedServerId included).
		if not teleportCall(placeId, { player }, options) then
			reacquire(player, "La téléportation a échoué : tu restes ici.", "Teleport failed: you stay here.")
			return
		end
		task.delay(PLACES.TeleportWatchdog, function()
			if player.Parent and teleportingSince[player] == since then
				reacquire(player, "La téléportation n'a pas abouti.", "The teleport did not complete.")
			end
		end)
	end
end

---------------------------------------------------------------------------------------------------
-- Lobby side
---------------------------------------------------------------------------------------------------
-- Starts a run for a group of players in this lobby server. Yields. Returns success.
function MatchService.startRun(group: { Player }, worldId: string, tier: number): boolean
	if not active or PLACES.RunPlaceId == 0 then
		return false
	end
	local ps = progression()
	local members: { number } = {}
	local loadouts: { [string]: { classId: string, companionId: string, companionId2: string? } } = {}
	for _, p in group do
		if not p.Parent or busy[p] or not dataService().canMutate(p) then
			return false
		end
		if not ps.isWorldUnlocked(p, worldId, tier) then
			return false
		end
		local classId, companionId = ps.getLoadout(p)
		table.insert(members, p.UserId)
		local second = ps.getCompanionLoadout(p)[2] -- Tamer : 2e compagnon (A12-01)
		loadouts[tostring(p.UserId)] = { classId = classId, companionId = companionId, companionId2 = second }
	end
	for _, p in group do
		busy[p] = true
		sendState(p, "Preparing")
	end
	local reservedServerId = HttpService:GenerateGUID(false) -- server-side only, never sent to clients
	local config: RunConfig = {
		v = 1,
		kind = "Run",
		worldId = worldId,
		tier = tier,
		members = members,
		loadouts = loadouts,
		sourcePlaceId = game.PlaceId,
		createdAt = os.time(),
	}
	if not memSet(reservedServerId, config, PLACES.RunConfigTtl) then
		for _, p in group do
			busy[p] = nil
			sendState(p, "Failed", "Serveur de partie indisponible : réessaie.", "Match server unavailable: please try again.")
		end
		return false -- nothing was released
	end
	local options = Instance.new("TeleportOptions")
	options.ReservedServerId = reservedServerId
	return releaseAndTeleport(group, PLACES.RunPlaceId, options)
end

local function onMatchRequest(player: Player, worldId: any, tier: any)
	if not active then
		return
	end
	if type(worldId) ~= "string" or #worldId > 32 or type(tier) ~= "number" or tier ~= math.floor(tier) then
		return
	end
	if tier < 1 or tier > Progression.MaxTier or busy[player] then
		return
	end
	-- TODO party UI: groups of friends present in this server go through startRun with all members.
	MatchService.startRun({ player }, worldId, tier)
end

-- VIP pass: personal persistent reserved server of the lobby place (free private room).
function MatchService.openVipRoom(player: Player): boolean
	if not active or PLACES.LobbyPlaceId == 0 or busy[player] then
		return false
	end
	local monetization = Registry.find("MonetizationService")
	if not monetization or not monetization.isVip(player) then
		return false
	end
	local roomId: string? = nil
	dataService().mutate(player, function(d)
		if type(d.vipRoomId) ~= "string" or d.vipRoomId == "" then
			d.vipRoomId = HttpService:GenerateGUID(false)
		end
		roomId = d.vipRoomId
	end)
	if not roomId then
		return false
	end
	busy[player] = true
	local ticket: RunConfig = {
		v = 1,
		kind = "VipRoom",
		members = { player.UserId },
		owner = player.UserId,
		sourcePlaceId = game.PlaceId,
		createdAt = os.time(),
	}
	if not memSet(roomId :: string, ticket, PLACES.RunConfigTtl) then
		busy[player] = nil
		return false
	end
	local options = Instance.new("TeleportOptions")
	options.ReservedServerId = roomId :: string
	return releaseAndTeleport({ player }, PLACES.LobbyPlaceId, options)
end

---------------------------------------------------------------------------------------------------
-- Run-server side
---------------------------------------------------------------------------------------------------
local function isReservedServer(): boolean
	return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
end

-- RunManager reads world/tier from here in lobby mode (contract request). Nil otherwise.
function MatchService.getRunConfig(): { worldId: string, tier: number, members: { number } }?
	local config = runConfig
	if not config or config.kind ~= "Run" or not config.worldId or not config.tier then
		return nil
	end
	return { worldId = config.worldId, tier = config.tier, members = table.clone(config.members) }
end

local function admit(player: Player)
	local config = runConfig
	local join = player:GetJoinData()
	local fromLobby = PLACES.LobbyPlaceId ~= 0 and join.SourcePlaceId == PLACES.LobbyPlaceId
	if not config or not fromLobby or not table.find(config.members, player.UserId) then
		player:Kick("Rejoins depuis le lobby. / Please join from the lobby.") -- default deny
		return
	end
	arrived[player.UserId] = true
	if config.loadouts then
		local l = config.loadouts[tostring(player.UserId)]
		if type(l) == "table" then
			arrivalLoadout[player] = { classId = l.classId, companionId = l.companionId, companionId2 = l.companionId2 }
		end
	end
end

local function applyArrivalLoadout(player: Player)
	local l = arrivalLoadout[player]
	if l then
		arrivalLoadout[player] = nil
		progression().setLoadout(player, l.classId, l.companionId, l.companionId2) -- re-validated (classe, collection)
	end
end

local function startRunServer()
	local key = game.PrivateServerId
	local value = memGet(key, 5)
	if type(value) == "table" and type(value.members) == "table" then
		runConfig = value :: any
	else
		warn("[MatchService] no run config for this reserved server: arrivals will be refused")
	end
	local Bus = require(script.Parent.Parent:WaitForChild("Bus")) :: any
	Bus.ProfileLoaded:connect(applyArrivalLoadout)
	Players.PlayerAdded:Connect(admit)
	for _, p in Players:GetPlayers() do
		task.spawn(admit, p)
	end
	-- Remove the config once everyone arrived, or after the arrival window (keep the cached copy).
	task.spawn(function()
		local deadline = os.clock() + PLACES.ArrivalWindow
		while os.clock() < deadline do
			local config = runConfig
			if config then
				local all = true
				for _, userId in config.members do
					if not arrived[userId] then
						all = false
						break
					end
				end
				if all then
					break
				end
			end
			task.wait(1)
		end
		memRemove(key)
	end)
end

-- Back to the lobby after a run (rewards already granted by grantRunRewards). Yields.
function MatchService.returnToLobby(players: { Player }): boolean
	if not active or PLACES.LobbyPlaceId == 0 then
		return false
	end
	local group: { Player } = {}
	for _, p in players do
		if p.Parent and not busy[p] then
			busy[p] = true
			table.insert(group, p)
		end
	end
	if #group == 0 then
		return false
	end
	return releaseAndTeleport(group, PLACES.LobbyPlaceId, nil)
end

function MatchService.isActive(): boolean
	return active
end

---------------------------------------------------------------------------------------------------
-- Groupes Solo / Party (place unique, 65-lobby §2.2 et §10 demande 2)
---------------------------------------------------------------------------------------------------
-- Le client envoie MatchMode(mode) avant SelectLoadout. RunManager lit getMode au départ :
-- Solo part seul (et personne ne le rejoint en retardataire) ; Party et Public gardent le
-- regroupement de Run.Lobby.StartDelay s. Sans MatchMode reçu : "Party" (comportement d'avant).
local MODES = { Solo = true, Party = true, Public = true }
local modes: { [Player]: string } = {}

local function onMatchMode(player: Player, mode: any)
	if type(mode) == "string" and MODES[mode] then
		modes[player] = mode
	end
end

function MatchService.getMode(player: Player): string
	return modes[player] or "Party"
end

---------------------------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------------------------
function MatchService.init()
	active = readUseLobbyPlace()
	-- The remote handler is always wired (Net requires handlers before publish); it no-ops when inactive.
	Net.onServerEvent("MatchRequest", 1, onMatchRequest)
	Net.onServerEvent("MatchMode", 4, onMatchMode)
	Players.PlayerRemoving:Connect(function(player)
		modes[player] = nil
	end)
	if not active then
		return
	end
	TeleportService.TeleportInitFailed:Connect(onTeleportInitFailed)
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
		lateRetries[player] = nil
		teleportingSince[player] = nil
		arrivalLoadout[player] = nil
	end)
end

function MatchService.start()
	if not active then
		return
	end
	if PLACES.LobbyPlaceId == 0 or PLACES.RunPlaceId == 0 then
		warn("[MatchService] UseLobbyPlace is on but place ids are 0 (Config.Progression.Places): teleports disabled")
	end
	if isReservedServer() and (PLACES.RunPlaceId == 0 or game.PlaceId == PLACES.RunPlaceId or game.PlaceId == PLACES.LobbyPlaceId) then
		startRunServer()
	end
end

return MatchService
