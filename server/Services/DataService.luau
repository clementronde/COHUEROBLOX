--!strict
-- Session-locked player profiles (data domain). Design: docs/dossier/70-donnees-progression-monetisation.md
-- sections 1-3 and 15. Vault: "Session Locking and Profile Libraries", "Saving Correctly - Autosave and
-- BindToClose", "Data Schema Design and Migrations", "DataStore Fundamentals".
--
-- The ONLY module that touches player data in DataStoreService.
-- * Lease + per-session fencing token written and checked inside the same UpdateAsync as the data.
-- * Autosave every Data.AutosaveSeconds (< lease / 3), per-player random offset + jitter; renews the lease.
-- * Leave: final save + release. Shutdown: parallel saves, waits for in-flight saves (25 s budget).
-- * A profile that failed to load is never saved. A "lost" session never writes again.
-- * Studio without API access: in-memory backend with a loud warning (never on live servers).
--
-- Cross-domain API (ARCHITECTURE section 4): getProfile(player) -> table?, waitForProfile(player, timeout) -> table?
-- getProfile returns a COPY (read-only view). Changes go through ProgressionService / MonetizationService.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Progression = require(Config:WaitForChild("Progression"))
local Net = require(Shared:WaitForChild("Net"))
local Registry = require(Shared:WaitForChild("Registry"))
local Bus = require(script.Parent.Parent:WaitForChild("Bus"))

local CFG = Progression.Data
local IS_STUDIO = RunService:IsStudio()
local CURRENT_SCHEMA = 1

export type LoadStatus = "loading" | "ready" | "locked" | "failed" | "left" | "released"
type SessionState = "active" | "lost" | "released"
type Session = {
	userId: number,
	key: string,
	token: string,
	data: { [string]: any },
	saveVersion: number,
	isNew: boolean,
	state: SessionState,
	saving: boolean,
	releasing: boolean,
	accountedAt: number,
}

local DataService = {}

local sessions: { [Player]: Session } = {}
local loadState: { [Player]: LoadStatus } = {}
local stateChanged = Instance.new("BindableEvent")
local inFlight = 0
local saveQueued: { [Player]: boolean } = {}
local lastSaveAt: { [Player]: number } = {}
local autosaveEpoch: { [Player]: number } = {}
local releaseHooks: { (Player) -> () } = {}

-- Runs synchronously before a final save (leave, teleport release, shutdown) while the profile is
-- still mutable, so buffered changes (batched kill counters...) land in the snapshot.
local function runReleaseHooks(player: Player)
	local session = sessions[player]
	if not session or session.state ~= "active" or session.releasing then
		return
	end
	for _, hook in releaseHooks do
		local ok, err = pcall(hook, player)
		if not ok then
			warn(`[DataService] release hook error: {err}`)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Backend: real DataStore, or (Studio only) an in-memory table with the same semantics
---------------------------------------------------------------------------------------------------
type Transform = (old: any, keyInfo: DataStoreKeyInfo?) -> (any, any, any)
type Backend = { name: string, update: (key: string, transform: Transform) -> any }

local backend: Backend? = nil
local backendReady = Instance.new("BindableEvent")

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value :: any do
		out[deepCopy(k)] = deepCopy(v)
	end
	return out :: any
end
DataService.deepCopy = deepCopy

local function realBackend(store: GlobalDataStore): Backend
	return {
		name = "DataStore",
		update = function(key: string, transform: Transform): any
			-- lihfolk-ignore: datastore-no-pcall -- every caller (tryClaim, save, releaseUnsaved) wraps backend.update in pcall
			return store:UpdateAsync(key, transform)
		end,
	}
end

local function memoryBackend(): Backend
	local memory: { [string]: any } = {}
	return {
		name = "Memory",
		update = function(key: string, transform: Transform): any
			local result = transform(deepCopy(memory[key]), nil)
			if result ~= nil then
				memory[key] = deepCopy(result)
				return result
			end
			return deepCopy(memory[key])
		end,
	}
end

local function resolveBackend()
	local okStore, store = pcall(function()
		return DataStoreService:GetDataStore(CFG.StoreName)
	end)
	if IS_STUDIO then
		local okProbe, probeErr = false, store
		if okStore then
			okProbe, probeErr = pcall(function()
				return (store :: GlobalDataStore):GetAsync("__probe")
			end)
		end
		if not okProbe then
			warn(
				`[DataService] DataStore unavailable in Studio ({probeErr}). Using an IN-MEMORY store:`
					.. " nothing is saved, leaderboards are off. Enable Studio API access to test real saves."
			)
			backend = memoryBackend()
			backendReady:Fire()
			return
		end
	elseif not okStore then
		-- Live server: never fall back. Retry until the service answers.
		while not okStore do
			warn(`[DataService] GetDataStore failed, retrying: {store}`)
			task.wait(5)
			okStore, store = pcall(function()
				return DataStoreService:GetDataStore(CFG.StoreName)
			end)
		end
	end
	backend = realBackend(store :: GlobalDataStore)
	backendReady:Fire()
end

local function waitBackend(): Backend
	while not backend do
		backendReady.Event:Wait()
	end
	return backend :: Backend
end

function DataService.isMemoryBackend(): boolean
	return backend ~= nil and (backend :: Backend).name == "Memory"
end

-- Studio-only isolated key: ServerStorage attribute TestProfileKey = "fresh1" -> TEST_fresh1_<UserId>.
local function testKey(): string?
	if not IS_STUDIO then
		return nil
	end
	local test = ServerStorage:GetAttribute("TestProfileKey")
	if type(test) == "string" and test ~= "" and #test <= 20 then
		return test
	end
	return nil
end

function DataService.isTestSession(): boolean
	return IS_STUDIO and (testKey() ~= nil or DataService.isMemoryBackend())
end

local function keyFor(userId: number): string
	local test = testKey()
	if test then
		return `TEST_{test}_{userId}`
	end
	return `User_{userId}`
end

---------------------------------------------------------------------------------------------------
-- Schema v1, migrations, reconcile
---------------------------------------------------------------------------------------------------
local function newProfile(): { [string]: any }
	local now = os.time()
	return {
		schema = CURRENT_SCHEMA,
		createdAt = now,
		lastJoinAt = now,
		sessions = 0,
		playSeconds = 0,
		silver = 0,
		questTokens = 0,
		silverEarnedTotal = 0,
		stats = {},
		questsDone = {},
		unlocks = { Weapon = {}, Grimoire = {}, Item = {}, Companion = {} },
		shop = { grimoireSlots = 0, banish = 0, skip = 0, reroll = 0 },
		mastery = {}, -- [classId] = level 1..20 (derived from masteryXp, stored for readers)
		masteryXp = {}, -- [classId] = total xp
		bond = {}, -- [line] = level 1..30
		bondXp = {}, -- [line] = total xp
		bondEggs = {}, -- [line] = true once its EggAtLevel egg was given
		companionStartTech = {}, -- [line] = tech id chosen (validated by bond level)
		eggs = 0,
		eggsHatched = 0,
		cosmetics = {},
		equipped = {},
		settings = { keepHat = false, colorblind = false, reduceFlashes = false, textScale = 1 },
		loadout = { classId = Progression.DefaultLoadout.classId, companionId = Progression.DefaultLoadout.companionId },
		weekly = { week = -1, done = false, bestSeconds = 0, everDone = false },
		boards = { week = -1, kills = 0, bestFinalWave = 0 },
		receipts = {},
		receiptOrder = {},
		purchaseLog = {},
		vipRoomId = "",
		flags = { boardBanned = false },
	}
end

-- STEPS[n] upgrades data from schema n to n + 1. Deterministic, no yields, never edited after release.
local STEPS: { [number]: (any) -> any } = {}

-- Fills fields missing from data (additive, never overwrites a valid value). Unknown keys are kept.
local function reconcile(data: { [string]: any }, template: { [string]: any })
	for k, v in template do
		local current = data[k]
		if current == nil then
			data[k] = deepCopy(v)
		elseif type(v) == "table" and type(current) ~= "table" then
			warn(`[DataService] field {k} had type {type(current)}, reset to default`)
			data[k] = deepCopy(v)
		elseif type(v) == "table" and next(v) ~= nil and #v == 0 then
			reconcile(current, v)
		elseif type(v) ~= "table" and type(current) ~= type(v) then
			warn(`[DataService] field {k} had type {type(current)}, reset to default`)
			data[k] = v
		end
	end
end

local function migrate(data: any): { [string]: any }
	if type(data) ~= "table" then
		error("profile is not a table")
	end
	local version = tonumber(data.schema) or 1
	if version > CURRENT_SCHEMA then
		-- Written by a newer release: refuse, or the next save would drop fields we do not know.
		error(`profile schema {version} is newer than this server ({CURRENT_SCHEMA})`)
	end
	while version < CURRENT_SCHEMA do
		local step = STEPS[version]
		if not step then
			error(`missing migration step from schema {version}`)
		end
		data = step(data)
		version += 1
		data.schema = version
	end
	reconcile(data, newProfile())
	return data
end

---------------------------------------------------------------------------------------------------
-- Claim / save / release (fenced)
---------------------------------------------------------------------------------------------------
local function newLease(token: string): { [string]: any }
	return {
		Token = token,
		JobId = game.JobId,
		PlaceId = game.PlaceId,
		ExpiresAt = os.time() + CFG.LeaseSeconds,
		Studio = if IS_STUDIO then true else nil,
	}
end

local function passThrough(keyInfo: DataStoreKeyInfo?, userId: number): (any, any)
	if keyInfo then
		return keyInfo:GetUserIds(), keyInfo:GetMetadata()
	end
	return { userId }, nil
end

-- One claim attempt. Returns outcome ("claimed" | "locked" | "malformed" | "error"), record, lockedUntil.
local function tryClaim(key: string, userId: number, token: string): (string, any, number?)
	local store = waitBackend()
	local outcome, lockedUntil = "error", nil :: number?
	local ok, result = pcall(function()
		return store.update(key, function(old: any, keyInfo: DataStoreKeyInfo?)
			outcome, lockedUntil = "error", nil -- reset: the transform can run several times
			if old ~= nil and type(old) ~= "table" then
				outcome = "malformed"
				return nil
			end
			local record = old or { SaveVersion = 0 }
			local held = record.Session
			if type(held) == "table" and held.Token ~= token then
				local expires = tonumber(held.ExpiresAt) or 0
				-- Studio leases may be taken over by another Studio session (vault: the 90 s Studio trap).
				local studioTakeover = IS_STUDIO and held.Studio == true
				if expires > os.time() and not studioTakeover then
					outcome, lockedUntil = "locked", expires
					return nil
				end
			end
			record.Session = newLease(token)
			outcome = "claimed"
			local userIds, metadata = passThrough(keyInfo, userId)
			return record, userIds, metadata
		end)
	end)
	if not ok then
		warn(`[DataService] claim error for {key}: {result}`)
		return "error", nil, nil
	end
	return outcome, result, lockedUntil
end

-- Drops our lease without writing data (load refused after the claim).
local function releaseUnsaved(key: string, userId: number, token: string)
	local store = waitBackend()
	pcall(function()
		store.update(key, function(old: any, keyInfo: DataStoreKeyInfo?)
			if type(old) ~= "table" or type(old.Session) ~= "table" or old.Session.Token ~= token then
				return nil
			end
			old.Session = nil
			local userIds, metadata = passThrough(keyInfo, userId)
			return old, userIds, metadata
		end)
	end)
end

local function notify(player: Player, kind: string, fr: string, en: string)
	if player.Parent then
		pcall(function()
			Net.event("DataNotice"):FireClient(player, { kind = kind, text = { fr = fr, en = en } })
		end)
	end
end

local function accountPlayTime(session: Session)
	local now = os.clock()
	local elapsed = math.max(0, now - session.accountedAt)
	session.accountedAt = now
	session.data.playSeconds = (tonumber(session.data.playSeconds) or 0) + math.floor(elapsed)
end

-- Writes data (and optionally clears the lease). Fenced by the token. "saved" | "lost" | "error".
local function save(session: Session, release: boolean): string
	if session.state ~= "active" then
		return "lost"
	end
	while session.saving do -- one write per profile at a time, in order
		task.wait(0.1)
	end
	if session.state ~= "active" then
		return if session.state == "released" then "saved" else "lost"
	end
	session.saving = true
	accountPlayTime(session)
	local snapshot = deepCopy(session.data) -- consistent instant; gameplay keeps mutating the live table
	local size = #HttpService:JSONEncode(snapshot)
	if size > CFG.SizeWarnChars then
		warn(`[DataService] profile {session.key} is {size} chars (limit 4,194,304)`)
	end
	local store = waitBackend()
	local result = "error"
	local writtenVersion = session.saveVersion
	local ok, err = pcall(function()
		store.update(session.key, function(old: any, keyInfo: DataStoreKeyInfo?)
			result = "error"
			if type(old) ~= "table" or type(old.Session) ~= "table" or old.Session.Token ~= session.token then
				result = "lost" -- someone else owns this key now: never write
				return nil
			end
			writtenVersion = math.max(tonumber(old.SaveVersion) or 0, session.saveVersion) + 1
			old.Data = snapshot
			old.SaveVersion = writtenVersion
			old.SavedAt = os.time()
			old.Session = if release then nil else newLease(session.token)
			result = "saved"
			local userIds, metadata = passThrough(keyInfo, session.userId)
			return old, userIds, metadata
		end)
	end)
	session.saving = false
	if not ok then
		warn(`[DataService] save error for {session.key}: {err}`)
		return "error"
	end
	if result == "lost" then
		session.state = "lost"
		return "lost"
	end
	if result == "saved" then
		session.saveVersion = writtenVersion
		if release then
			session.state = "released"
		end
	end
	return result
end

local function setState(player: Player, status: LoadStatus)
	loadState[player] = status
	stateChanged:Fire(player)
end

local function saveWithRetries(player: Player, release: boolean, attempts: number): boolean
	local session = sessions[player]
	if not session or session.state ~= "active" then
		return session ~= nil and session.state == "released" and release
	end
	inFlight += 1
	local result = "error"
	local delay = 1
	for attempt = 1, attempts do
		local okCall, r = pcall(save, session, release)
		result = if okCall then r else "error"
		if result ~= "error" then
			break
		end
		if attempt < attempts then
			task.wait(delay * (0.5 + math.random()))
			delay = math.min(delay * 2, 8)
		end
	end
	inFlight -= 1
	lastSaveAt[player] = os.clock()
	if result == "lost" then
		notify(
			player,
			"Lost",
			"Ta partie a été ouverte sur un autre serveur. Reconnecte-toi pour continuer en sécurité.",
			"Your data was opened on another server. Rejoin to keep playing safely."
		)
	end
	return result == "saved"
end

---------------------------------------------------------------------------------------------------
-- Loading
---------------------------------------------------------------------------------------------------
local function startAutosave(player: Player)
	local epoch = (autosaveEpoch[player] or 0) + 1
	autosaveEpoch[player] = epoch
	task.spawn(function()
		task.wait(math.random() * CFG.AutosaveSeconds) -- per-player offset: no synchronized bursts
		while player.Parent and autosaveEpoch[player] == epoch do
			local session = sessions[player]
			if not session or session.state ~= "active" then
				break
			end
			if not session.releasing then
				saveWithRetries(player, false, 1) -- a failed autosave waits for the next cycle
			end
			task.wait(CFG.AutosaveSeconds + math.random() * CFG.AutosaveJitter)
		end
	end)
end

-- Claims and loads. Returns status and a session (only when "ready").
local function loadSession(player: Player): (LoadStatus, Session?)
	local userId = player.UserId
	local key = keyFor(userId)
	local token = HttpService:GenerateGUID(false)
	if IS_STUDIO and ServerStorage:GetAttribute("SimulateLoadFailure") == true then
		warn("[DataService] SimulateLoadFailure is set: load fails on purpose")
		return "failed", nil
	end
	local started = os.clock()
	local errors = 0
	local attempt = 0
	local warned = false
	while true do
		attempt += 1
		if not player.Parent then
			return "left", nil
		end
		local outcome, record, lockedUntil = tryClaim(key, userId, token)
		if outcome == "claimed" and type(record) == "table" then
			if not player.Parent then
				releaseUnsaved(key, userId, token)
				return "left", nil
			end
			local isNew = record.Data == nil
			local okMigrate, data = pcall(function()
				return if isNew then newProfile() else migrate(record.Data)
			end)
			if not okMigrate then
				warn(`[DataService] migrate failed for {key}: {data}`)
				releaseUnsaved(key, userId, token) -- never overwrite data we cannot read
				return "failed", nil
			end
			local session: Session = {
				userId = userId,
				key = key,
				token = token,
				data = data,
				saveVersion = tonumber(record.SaveVersion) or 0,
				isNew = isNew,
				state = "active",
				saving = false,
				releasing = false,
				accountedAt = os.clock(),
			}
			return "ready", session
		elseif outcome == "malformed" then
			return "failed", nil
		elseif outcome == "locked" then
			if not warned then
				warned = true
				local left = if lockedUntil then lockedUntil - os.time() else CFG.LeaseSeconds
				warn(`[DataService] {key} held by another server, lease ends in {left} s`)
				notify(
					player,
					"Waiting",
					"Ta sauvegarde se termine sur un autre serveur…",
					"Your save is finishing on another server…"
				)
			end
			if os.clock() - started > CFG.LockedWaitSeconds then
				return "locked", nil
			end
		else
			errors += 1
			if errors >= CFG.ErrorClaimAttempts then
				return "failed", nil
			end
		end
		task.wait(math.min(8, attempt * 1.5) + math.random()) -- backoff with jitter
	end
end

local function analyticsLoad(player: Player, status: string)
	local progression = Registry.find("ProgressionService")
	if progression and type(progression.logCustom) == "function" then
		pcall(progression.logCustom, player, "DataLoad", 1, { status })
	end
end

local function activate(player: Player, session: Session)
	sessions[player] = session
	setState(player, "ready")
	startAutosave(player)
	Bus.ProfileLoaded:fire(player)
	if session.isNew then
		-- The claim only wrote the lease; write the new profile soon so a crash keeps the defaults.
		DataService.saveSoon(player)
	end
end

local function onPlayerAdded(player: Player)
	if loadState[player] ~= nil then
		return
	end
	setState(player, "loading")
	local status, session = loadSession(player)
	if status == "left" then
		loadState[player] = nil
		return
	end
	if not player.Parent then
		if session then
			sessions[player] = session
			saveWithRetries(player, true, 2)
			sessions[player] = nil
		end
		loadState[player] = nil
		return
	end
	task.spawn(analyticsLoad, player, status)
	if status ~= "ready" or not session then
		setState(player, status)
		if status == "locked" then
			player:Kick(
				"Ta sauvegarde se termine encore sur un autre serveur : reviens dans une minute. / Your data is still saving on another server. Please rejoin in a minute."
			)
		else
			player:Kick(
				"Tes données n'ont pas pu se charger. Rien n'a été modifié : reconnecte-toi. / Your data couldn't load. Nothing was changed; please rejoin."
			)
		end
		return
	end
	session.data.sessions = (tonumber(session.data.sessions) or 0) + 1
	session.data.lastJoinAt = os.time()
	activate(player, session)
end

local function onPlayerRemoving(player: Player)
	saveQueued[player] = nil
	autosaveEpoch[player] = (autosaveEpoch[player] or 0) + 1
	runReleaseHooks(player)
	local session = sessions[player]
	if session and session.state == "active" then
		saveWithRetries(player, true, CFG.FinalSaveAttempts) -- final write + release the lease
	end
	sessions[player] = nil
	loadState[player] = nil
	lastSaveAt[player] = nil
	autosaveEpoch[player] = nil
	stateChanged:Fire(player)
end

---------------------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------------------

-- Read-only copy of the loaded profile (nil if not loaded, released or lost).
-- Compatibility view: equipped.TraitTint = n when the loadout class wears its free tint "Tint_<class>_Base<n>".
function DataService.getProfile(player: Player): { [string]: any }?
	local session = sessions[player]
	if not session or session.state ~= "active" then
		return nil
	end
	local copy = deepCopy(session.data)
	local equipped = copy.equipped
	local loadout = copy.loadout
	if type(equipped) == "table" and type(loadout) == "table" and type(loadout.classId) == "string" then
		local tint = equipped[`Tint:{loadout.classId}`]
		if type(tint) == "string" then
			local n = tonumber(string.match(tint, "_Base(%d)$"))
			if n then
				equipped.TraitTint = n
			end
		end
	end
	return copy
end

-- Yields until the profile is loaded (or failed, or timeout). Returns getProfile(player).
function DataService.waitForProfile(player: Player, timeout: number): { [string]: any }?
	local deadline = os.clock() + math.max(0, timeout)
	while player.Parent and os.clock() < deadline do
		local s = loadState[player]
		if s == "ready" then
			return DataService.getProfile(player)
		elseif s == "failed" or s == "locked" then
			return nil
		end
		local fired = false
		local conn = stateChanged.Event:Connect(function()
			fired = true
		end)
		local waitUntil = math.min(deadline, os.clock() + 0.5)
		while not fired and os.clock() < waitUntil do
			task.wait(0.05)
		end
		conn:Disconnect()
	end
	if loadState[player] == "ready" then
		return DataService.getProfile(player)
	end
	return nil
end

-- Internal (data domain only) -------------------------------------------------------------------

-- Registers a hook run before every final save (see runReleaseHooks).
function DataService.addReleaseHook(hook: (Player) -> ())
	table.insert(releaseHooks, hook)
end

function DataService.getStatus(player: Player): LoadStatus?
	return loadState[player]
end

-- True when the profile can be changed and saved right now.
function DataService.canMutate(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.state == "active" and not session.releasing
end

-- Live table, READ-ONLY, for the data domain's hot paths. Nil when no session.
function DataService.peek(player: Player): { [string]: any }?
	local session = sessions[player]
	return if session then session.data else nil
end

-- Synchronous mutation. fn must not yield, so related changes are atomic for any save snapshot.
function DataService.mutate(player: Player, fn: (data: { [string]: any }) -> ()): boolean
	if not DataService.canMutate(player) then
		return false
	end
	local session = sessions[player] :: Session
	local ok, err = pcall(fn, session.data)
	if not ok then
		warn(`[DataService] mutate error for {session.key}: {err}`)
		return false
	end
	return true
end

-- SaveNowAsync equivalent: yields, returns true only when the current state is durably written.
function DataService.saveNow(player: Player): boolean
	local session = sessions[player]
	if not session or session.state ~= "active" or session.releasing then
		return false
	end
	return saveWithRetries(player, false, 2)
end

-- Debounced save after something valuable (purchase in shop, quest, run rewards).
function DataService.saveSoon(player: Player)
	if saveQueued[player] then
		return
	end
	saveQueued[player] = true
	local since = os.clock() - (lastSaveAt[player] or -math.huge)
	local delay = math.max(CFG.SaveSoonMin, CFG.SaveSoonSpacing - since)
	task.delay(delay, function()
		saveQueued[player] = nil
		if player.Parent and DataService.canMutate(player) then
			saveWithRetries(player, false, 2)
		end
	end)
end

-- Final save + lease release before a teleport (MatchService). After success the profile is
-- "released": no writes or purchases on this server until reacquire().
function DataService.releaseForTeleport(player: Player): boolean
	local session = sessions[player]
	if not session or session.state ~= "active" or session.releasing then
		return false
	end
	runReleaseHooks(player)
	session.releasing = true -- blocks mutations before the snapshot
	local ok = saveWithRetries(player, true, 3)
	session.releasing = false
	if ok and session.state == "released" then
		autosaveEpoch[player] = (autosaveEpoch[player] or 0) + 1
		setState(player, "released")
		return true
	end
	return false
end

-- Claims the profile again after a failed teleport (TeleportInitFailed, watchdog). Yields.
function DataService.reacquire(player: Player): boolean
	if not player.Parent or loadState[player] ~= "released" then
		return loadState[player] == "ready"
	end
	setState(player, "loading")
	local status, session = loadSession(player)
	if status == "ready" and session and player.Parent then
		activate(player, session)
		return true
	end
	if session then
		releaseUnsaved(session.key, session.userId, session.token)
	end
	if player.Parent then
		setState(player, if status == "locked" then "locked" else "failed")
		player:Kick(
			"Tes données n'ont pas pu être rechargées après la téléportation : reconnecte-toi. / Your data couldn't reload after the teleport; please rejoin."
		)
	end
	return false
end

---------------------------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------------------------
function DataService.init()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		task.spawn(onPlayerRemoving, player)
	end)
	game:BindToClose(function()
		if IS_STUDIO then
			-- Studio: save but do not hold the window open. Leftover Studio leases are taken over.
			for _, p in Players:GetPlayers() do
				runReleaseHooks(p)
				task.spawn(saveWithRetries, p, true, 1)
			end
			task.wait(1)
			return
		end
		for _, p in Players:GetPlayers() do -- parallel: sequential saves do not fit in 30 s
			runReleaseHooks(p)
			task.spawn(saveWithRetries, p, true, 3)
		end
		local started = os.clock()
		task.wait(0.5) -- let spawned and PlayerRemoving saves register as in flight
		while inFlight > 0 and os.clock() - started < CFG.ShutdownBudget do
			task.wait(0.1)
		end
		if inFlight > 0 then
			warn(`[DataService] shutdown ended with {inFlight} saves still running`)
		end
	end)
end

function DataService.start()
	resolveBackend()
	for _, p in Players:GetPlayers() do -- players who joined before start
		task.spawn(onPlayerAdded, p)
	end
end

DataService.CurrentSchema = CURRENT_SCHEMA
DataService._newProfile = newProfile
DataService._migrate = migrate

return DataService
