--!strict
-- Shrines (docs/dossier/30-butin-autels.md section 6): Charge, Golden, Trial, BossChallenge,
-- Prankster, PiggyBank, RecessBell, TeamTotem.
-- Charging = standing in the circle; the server tests player positions at 10 Hz.
-- Clients send only ShrineChoice(offerId, index) and ShrineInteract(shrineId), validated here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Shrines = require(Config:WaitForChild("Shrines"))
local Loot = require(Config:WaitForChild("Loot"))
local Net = require(Shared:WaitForChild("Net"))
local Registry = require(Shared:WaitForChild("Registry"))
local Bus = require(script.Parent.Parent:WaitForChild("Bus"))

local DT = 1 / Shrines.SimHz
local RARITIES = Loot.RarityOrder
local RUNNING_PHASES = { Running = true, Boss = true, BossDefeated = true, FinalWave = true }

export type ShrineStateName = "Idle" | "Charging" | "Active" | "Done" | "Failed" | "Locked"

type Shrine = {
	id: number,
	kind: string,
	position: Vector3,
	state: ShrineStateName,
	progress: number, -- 0..1
	chargers: number, -- effective chargers in the circle (ghosts count GhostWeight)
	activeEnds: number, -- Trial / RecessBell / vote end time
	uses: { [Player]: number }, -- Prankster
}

type Choice = { stat: string, value: number, rarity: string }

type Offer = {
	id: number,
	player: Player,
	kind: "Stat" | "Vote",
	shrineId: number,
	choices: { Choice },
	expires: number,
}

local ShrineService = {}

local shrines: { Shrine } = {}
local byId: { [number]: Shrine } = {}
local nextShrineId = 1
local offers: { [number]: Offer } = {}
local nextOfferId = 1
local votes: { [Player]: boolean } = {}
local voteShrine: Shrine? = nil
local bossChallengeActive = false
local trialEnemyIds: { [number]: boolean } = {} -- every trial enemy of the stage
local trialAlive: { [number]: { [number]: boolean } } = {} -- shrineId -> alive enemy ids
local bell = { x = 0, z = 0, untilTime = -math.huge }
local runToken = 0
local allChargedReported = false
local stageActive = false
local dirty = true
local lastStateSent = 0
local rng = Random.new()
local warned: { [string]: boolean } = {}
local queryOut: { number } = {}

local stateRemote: RemoteEvent
local offerRemote: RemoteEvent
local gagRemote: RemoteEvent

-- Helpers ---------------------------------------------------------------------

local function warnOnce(key: string, message: string)
	if not warned[key] then
		warned[key] = true
		warn(`[ShrineService] {message}`)
	end
end

local function safeCall(label: string, fn: any, ...: any): (boolean, any)
	if type(fn) ~= "function" then
		return false, nil
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		warnOnce(label, `{label} failed: {result}`)
	end
	return ok, result
end

local function isFiniteNumber(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function validInt(v: any, lo: number, hi: number): boolean
	return isFiniteNumber(v) and v % 1 == 0 and v >= lo and v <= hi
end

local function record(player: Player, key: string, amount: number)
	local progression = Registry.find("ProgressionService")
	if progression then
		safeCall("ProgressionService.recordStat", progression.recordStat, player, key, amount)
	end
end

local function isRunning(): boolean
	local run = Registry.find("RunManager")
	if not run then
		return stageActive
	end
	local ok, phase = safeCall("RunManager.getPhase", run.getPhase)
	return ok and RUNNING_PHASES[phase] == true
end

local function runPlayers(): { Player }
	local run = Registry.find("RunManager")
	if run then
		local ok, list = safeCall("RunManager.getRunPlayers", run.getRunPlayers)
		if ok and type(list) == "table" then
			return list
		end
	end
	return Players:GetPlayers()
end

-- "Active" (alive, not downed), "Downed", or "Ghost" (dead spectator, vision 5.2).
local function lifeState(player: Player): string
	local run = Registry.find("RunManager")
	if not run then
		return "Active"
	end
	local ok, active = safeCall("RunManager.isActive", run.isActive, player)
	if ok and active == true then
		return "Active"
	end
	local ok2, downed = safeCall("RunManager.isDowned", run.isDowned, player)
	if ok2 and downed == true then
		return "Downed"
	end
	return "Ghost"
end

local function activeRunPlayers(): { Player }
	local list: { Player } = {}
	for _, player in runPlayers() do
		if lifeState(player) == "Active" then
			table.insert(list, player)
		end
	end
	return list
end

local function rootPosition(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function inCircle(s: Shrine, p: Vector3, extra: number): boolean
	local dx, dz = p.X - s.position.X, p.Z - s.position.Z
	local r = Shrines.Radius + extra
	return dx * dx + dz * dz <= r * r and math.abs(p.Y - s.position.Y) <= Shrines.VerticalTolerance + extra
end

local function luckOf(player: Player): number
	local stats = Registry.find("StatsService")
	if not stats then
		return 0
	end
	local ok, block = safeCall("StatsService.get", stats.get, player)
	local v = ok and type(block) == "table" and block.Luck
	return if isFiniteNumber(v) then v else 0
end

local function addStat(player: Player, stat: string, value: number, source: string)
	local stats = Registry.find("StatsService")
	if stats then
		safeCall("StatsService.addStat", stats.addStat, player, stat, value, source)
	end
end

local function rollRarity(base: { number }, luck: number): number
	local weights = Loot.rarityWeights(base, luck)
	local r = rng:NextNumber()
	for i = 1, 4 do
		r -= weights[i]
		if r <= 0 then
			return i
		end
	end
	return 1
end

-- Piecewise-linear coop speed (vision 5.2): 1 -> x1, 2 -> x1.5, 3+ -> x2.
local function coopSpeed(effective: number): number
	local curve = Shrines.CoopSpeed
	if effective <= curve[1][1] then
		return curve[1][2]
	end
	for i = 1, #curve - 1 do
		local a, b = curve[i], curve[i + 1]
		if effective <= b[1] then
			return a[2] + (b[2] - a[2]) * (effective - a[1]) / (b[1] - a[1])
		end
	end
	return curve[#curve][2]
end

local function markDirty()
	dirty = true
end

-- State broadcast (per player: the Prankster price depends on that player's uses).
local function sendState()
	dirty = false
	lastStateSent = os.clock()
	for _, player in Players:GetPlayers() do
		local list = table.create(#shrines)
		for _, s in shrines do
			local entry: { [string]: any } = {
				id = s.id,
				kind = s.kind,
				position = s.position,
				state = s.state,
				progress = s.progress,
				chargers = s.chargers,
			}
			if s.kind == "Prankster" then
				entry.cost = Shrines.PranksterCost + Shrines.PranksterCostStep * (s.uses[player] or 0)
			end
			table.insert(list, entry)
		end
		stateRemote:FireClient(player, { shrines = list })
	end
end

-- Offers ---------------------------------------------------------------------

local function closeOffer(offer: Offer)
	offers[offer.id] = nil
	if offer.player.Parent then
		offerRemote:FireClient(offer.player, { offerId = offer.id, closed = true })
	end
end

local function sendOffer(player: Player, kind: "Stat" | "Vote", s: Shrine, choices: { Choice }, timeout: number)
	local id = nextOfferId
	nextOfferId += 1
	offers[id] = {
		id = id,
		player = player,
		kind = kind,
		shrineId = s.id,
		choices = choices,
		expires = os.clock() + timeout,
	}
	offerRemote:FireClient(player, {
		offerId = id,
		kind = kind,
		shrineKind = s.kind,
		choices = choices,
		expiresIn = timeout,
	})
end

local function rollStatChoices(player: Player, golden: boolean): { Choice }
	local pool: { string } = {}
	for stat in Shrines.StatPool do
		table.insert(pool, stat)
	end
	table.sort(pool)
	local luck = luckOf(player)
	local choices: { Choice } = {}
	for _ = 1, math.min(Shrines.ChoiceCount, #pool) do
		local stat = table.remove(pool, rng:NextInteger(1, #pool)) :: string
		local r = if golden then 4 else rollRarity(Shrines.ChoiceRarity, luck)
		table.insert(choices, { stat = stat, value = Shrines.StatPool[stat][r], rarity = RARITIES[r] })
	end
	return choices
end

local function resolveVote()
	local s = voteShrine
	if not s then
		return
	end
	voteShrine = nil
	local voters = activeRunPlayers()
	local yes = 0
	for _, player in voters do
		if votes[player] then
			yes += 1
		end
	end
	for _, offer in offers do
		if offer.kind == "Vote" then
			closeOffer(offer)
		end
	end
	table.clear(votes)
	if #voters > 0 and yes * 2 > #voters then
		bossChallengeActive = true
		s.state = "Done"
		for _, player in voters do
			record(player, "BossChallengesAccepted", 1)
		end
		Bus.ShrineCompleted:fire(voters, s.kind)
	else
		s.state = "Idle" -- refused: can be charged again
		s.progress = 0
	end
	markDirty()
end

local function onChoice(player: Player, offerId: any, index: any)
	if not validInt(offerId, 1, nextOfferId) or not validInt(index, 1, 3) then
		return
	end
	local offer = offers[offerId]
	if not offer or offer.player ~= player or index > #offer.choices then
		return
	end
	closeOffer(offer)
	if offer.kind == "Stat" then
		local c = offer.choices[index]
		addStat(player, c.stat, c.value, "Shrine")
	else
		votes[player] = index == 1
		-- Resolve early once every active player has voted.
		local voters = activeRunPlayers()
		local n = 0
		for _, p in voters do
			if votes[p] ~= nil then
				n += 1
			end
		end
		if n >= #voters then
			resolveVote()
		end
	end
end

local function expireOffers(now: number)
	for _, offer in offers do
		if now >= offer.expires then
			if offer.kind == "Stat" then
				-- Auto-pick the rarest choice.
				local best = offer.choices[1]
				for _, c in offer.choices do
					if (table.find(RARITIES, c.rarity) or 0) > (table.find(RARITIES, best.rarity) or 0) then
						best = c
					end
				end
				addStat(offer.player, best.stat, best.value, "Shrine")
			end
			closeOffer(offer)
		end
	end
	if voteShrine and now >= voteShrine.activeEnds then
		resolveVote()
	end
end

-- Completion per kind ----------------------------------------------------------

local function checkAllCharged()
	if allChargedReported then
		return
	end
	local total, done = 0, 0
	for _, s in shrines do
		if s.kind == "Charge" or s.kind == "Golden" then
			total += 1
			if s.state == "Done" then
				done += 1
			end
		end
	end
	if total > 0 and done == total then
		allChargedReported = true
		for _, player in activeRunPlayers() do
			record(player, "AllShrinesCharged", 1)
		end
	end
end

local function completeTrial(s: Shrine)
	s.state = "Done"
	trialAlive[s.id] = nil
	local loot = Registry.find("LootService")
	if loot then
		safeCall("LootService.spawnChest", loot.spawnChest, s.position.X, s.position.Z, "Shrine", nil)
	end
	local players = activeRunPlayers()
	for _, player in players do
		record(player, "TrialShrinesCompleted", 1)
	end
	Bus.ShrineCompleted:fire(players, s.kind)
	markDirty()
end

local function startTrial(s: Shrine)
	local enemyService = Registry.find("EnemyService")
	local nPlayers = math.max(1, #activeRunPlayers())
	local count = Shrines.TrialEnemies + Shrines.TrialEnemiesPerExtraPlayer * (nPlayers - 1)
	local alive: { [number]: boolean } = {}
	local spawned = 0
	if enemyService and type(enemyService.spawnAt) == "function" then
		for i = 1, count do
			local a = (i / count) * math.pi * 2
			local x = s.position.X + math.cos(a) * Shrines.TrialSpawnRadius
			local z = s.position.Z + math.sin(a) * Shrines.TrialSpawnRadius
			local ok, id = safeCall(
				"EnemyService.spawnAt",
				enemyService.spawnAt,
				Shrines.TrialEnemyKind,
				x,
				z,
				{ elite = true }
			)
			if ok and isFiniteNumber(id) then
				alive[id] = true
				trialEnemyIds[id] = true
				spawned += 1
			end
		end
	else
		warnOnce("spawnAt", "EnemyService.spawnAt missing: trial shrines complete at once")
	end
	if spawned == 0 then
		completeTrial(s)
		return
	end
	s.state = "Active"
	s.activeEnds = os.clock() + Shrines.TrialTimeLimit
	trialAlive[s.id] = alive
	markDirty()
end

local function startVote(s: Shrine)
	if voteShrine then
		return
	end
	s.state = "Active"
	s.activeEnds = os.clock() + Shrines.VoteDuration
	voteShrine = s
	table.clear(votes)
	local choices: { Choice } = {
		{ stat = "Yes", value = 1, rarity = "Legendary" },
		{ stat = "No", value = 0, rarity = "Common" },
	}
	for _, player in activeRunPlayers() do
		sendOffer(player, "Vote", s, choices, Shrines.VoteDuration)
	end
	markDirty()
end

local function ringBell(s: Shrine, chargers: { Player })
	s.state = "Active"
	s.activeEnds = os.clock() + Shrines.BellDuration
	bell.x, bell.z = s.position.X, s.position.Z
	bell.untilTime = s.activeEnds
	for _, player in chargers do
		record(player, "RecessBellsRung", 1)
	end
	Bus.ShrineCompleted:fire(chargers, s.kind)
	task.spawn(function()
		local enemyService = Registry.find("EnemyService")
		while os.clock() < bell.untilTime and enemyService do
			local n = 0
			local ok, result = safeCall(
				"EnemyService.queryRadius",
				enemyService.queryRadius,
				bell.x,
				bell.z,
				Shrines.BellRadius,
				queryOut
			)
			if ok and isFiniteNumber(result) then
				n = result
			end
			for i = 1, n do
				safeCall("EnemyService.applyStatus", enemyService.applyStatus, queryOut[i], "Knockback", {
					towardX = bell.x,
					towardZ = bell.z,
					distance = Shrines.BellPullDistance,
				})
			end
			task.wait(Shrines.BellPullEvery)
		end
		s.state = "Done"
		markDirty()
	end)
end

local function activateTotem(s: Shrine, chargers: { Player })
	s.state = "Done"
	local token = runToken
	local team = activeRunPlayers()
	for _, player in team do
		for stat, value in Shrines.TotemBuff do
			addStat(player, stat, value, "TeamTotem")
		end
		record(player, "TeamTotemsActivated", 1)
	end
	Bus.ShrineCompleted:fire(chargers, s.kind)
	task.delay(Shrines.TotemDuration, function()
		if token ~= runToken then
			return -- a new run reset the stats already
		end
		for _, player in team do
			if player.Parent then
				for stat, value in Shrines.TotemBuff do
					addStat(player, stat, -value, "TeamTotem")
				end
			end
		end
	end)
	markDirty()
end

local function breakPiggy(s: Shrine, chargers: { Player })
	s.state = "Done"
	local loot = Registry.find("LootService")
	local stage = 1
	if loot then
		local ok, st = safeCall("LootService._getStage", loot._getStage)
		if ok and isFiniteNumber(st) then
			stage = st
		end
	end
	local coins = math.round(Shrines.PiggyCoins * (1 + Shrines.PiggyStageBonus * (stage - 1)))
	for _, player in runPlayers() do
		if loot then
			safeCall("LootService.addCoins", loot.addCoins, player, coins)
		end
		addStat(player, "LootBonus", Shrines.PiggyLootBonus, "PiggyBank")
		addStat(player, "Difficulty", Shrines.PiggyDifficulty, "PiggyBank")
	end
	for _, player in chargers do
		record(player, "PiggyBanksBroken", 1)
	end
	Bus.ShrineCompleted:fire(chargers, s.kind)
	markDirty()
end

local function complete(s: Shrine, chargers: { Player })
	s.progress = 1
	if s.kind == "Charge" or s.kind == "Golden" then
		s.state = "Done"
		local golden = s.kind == "Golden"
		for _, player in chargers do
			sendOffer(player, "Stat", s, rollStatChoices(player, golden), Shrines.OfferTimeout)
			record(player, "ShrinesCharged", 1)
			if golden then
				record(player, "GoldenShrinesCharged", 1)
			end
		end
		Bus.ShrineCompleted:fire(chargers, s.kind)
		checkAllCharged()
		markDirty()
	elseif s.kind == "Trial" then
		startTrial(s)
	elseif s.kind == "BossChallenge" then
		startVote(s)
	elseif s.kind == "PiggyBank" then
		breakPiggy(s, chargers)
	elseif s.kind == "RecessBell" then
		ringBell(s, chargers)
	elseif s.kind == "TeamTotem" then
		activateTotem(s, chargers)
	end
end

-- Tick -----------------------------------------------------------------------

local function chargeStep(now: number)
	local players = runPlayers()
	for _, s in shrines do
		local def = Shrines.Kinds[s.kind]
		if s.state == "Active" and s.kind == "Trial" then
			local alive = trialAlive[s.id]
			local enemyService = Registry.find("EnemyService")
			local left = 0
			if alive then
				for id in alive do
					local ok, isAlive = true, false
					if enemyService then
						ok, isAlive = safeCall("EnemyService.isAlive", enemyService.isAlive, id)
					end
					if ok and isAlive == true then
						left += 1
					else
						alive[id] = nil
					end
				end
			end
			if left == 0 then
				completeTrial(s)
			elseif now >= s.activeEnds then
				s.state = "Failed"
				trialAlive[s.id] = nil
				markDirty()
			end
		elseif (s.state == "Idle" or s.state == "Charging") and def and def.chargeTime > 0 then
			local effective = 0
			local activeIn: { Player } = {}
			for _, player in players do
				local p = rootPosition(player)
				if p and inCircle(s, p, 0) then
					local life = lifeState(player)
					if life == "Active" then
						effective += 1
						table.insert(activeIn, player)
					elseif life == "Ghost" then
						effective += Shrines.GhostWeight
					end
				end
			end
			if def.minPlayers and #activeIn < def.minPlayers then
				effective = 0
			end
			local speed = coopSpeed(effective)
			local before, beforeState, beforeChargers = s.progress, s.state, s.chargers
			s.chargers = effective
			if speed > 0 then
				s.progress = math.min(1, s.progress + DT * speed / def.chargeTime)
				s.state = "Charging"
			else
				s.progress = math.max(0, s.progress - DT / Shrines.DecayTime)
				s.state = if s.progress > 0 then "Charging" else "Idle"
			end
			if s.progress >= 1 and #activeIn > 0 then
				complete(s, activeIn)
			elseif s.progress >= 1 then
				s.progress = 0.99 -- only ghosts in the circle: wait for a living player
			end
			if s.progress ~= before or s.state ~= beforeState or s.chargers ~= beforeChargers then
				markDirty()
			end
		end
	end
end

local function step()
	local now = os.clock()
	if isRunning() then
		chargeStep(now)
	end
	expireOffers(now)
	if dirty and now - lastStateSent >= 1 / Shrines.StateMaxPerSecond then
		sendState()
	end
end

-- Interaction (Prankster) -----------------------------------------------------

local function onInteract(player: Player, shrineId: any)
	if not validInt(shrineId, 1, nextShrineId) or not isRunning() then
		return
	end
	local s = byId[shrineId]
	if not s or s.kind ~= "Prankster" or lifeState(player) ~= "Active" then
		return
	end
	local p = rootPosition(player)
	if not p or not inCircle(s, p, Shrines.InteractRange) then
		return
	end
	local loot = Registry.find("LootService")
	if not loot then
		return
	end
	local uses = s.uses[player] or 0
	local cost = Shrines.PranksterCost + Shrines.PranksterCostStep * uses
	local ok, paid = safeCall("LootService.spendCoins", loot.spendCoins, player, cost)
	if not ok or paid ~= true then
		return
	end
	s.uses[player] = uses + 1
	safeCall("LootService._grantRandomItem", loot._grantRandomItem, player, Shrines.PranksterRarity, "Prankster")
	-- Team gag: screen / camera / light only. The avatar is never changed (design rule).
	local gag = Shrines.Gags[rng:NextInteger(1, #Shrines.Gags)]
	for _, target in runPlayers() do
		if target.Parent then
			gagRemote:FireClient(target, { gag = gag, duration = Shrines.GagDuration, by = player.UserId })
		end
	end
	record(player, "PranksterUses", 1)
	Bus.ShrineCompleted:fire({ player }, s.kind)
	markDirty()
end

-- Stage lifecycle --------------------------------------------------------------

local function clearShrines()
	table.clear(shrines)
	table.clear(byId)
	for _, offer in offers do
		closeOffer(offer)
	end
	table.clear(votes)
	table.clear(trialEnemyIds)
	table.clear(trialAlive)
	voteShrine = nil
	bell.untilTime = -math.huge
	allChargedReported = false
	markDirty()
end

local function spawnShrines(stage: number)
	clearShrines()
	bossChallengeActive = false
	local nPlayers = #runPlayers()
	local plan: { string } = {}
	for _, kind in Shrines.SpawnOrder do
		local def = Shrines.Kinds[kind]
		local skip = kind == "TeamTotem" and nPlayers < (def.minPlayers or 2)
		if def and not skip then
			for _ = 1, def.count do
				table.insert(plan, kind)
			end
		end
	end
	local loot = Registry.find("LootService")
	local points: { Vector3 } = {}
	if loot then
		local ok, list = safeCall("LootService._spawnPoints", loot._spawnPoints, "Shrine", #plan, os.time() + stage * 104729)
		if ok and type(list) == "table" then
			points = list
		end
	end
	for i, kind in plan do
		local p = points[i]
		if not p then
			break
		end
		if kind == "Charge" and rng:NextNumber() < Shrines.GoldenChance then
			kind = "Golden"
		end
		local s: Shrine = {
			id = nextShrineId,
			kind = kind,
			position = p,
			state = "Idle",
			progress = 0,
			chargers = 0,
			activeEnds = 0,
			uses = {},
		}
		nextShrineId += 1
		table.insert(shrines, s)
		byId[s.id] = s
	end
	stageActive = true
	markDirty()
end

-- Public API -------------------------------------------------------------------

-- ARCHITECTURE.md section 4 (Minimap).
function ShrineService.getShrines(): { { id: number, kind: string, position: Vector3, state: string } }
	local out = table.create(#shrines)
	for _, s in shrines do
		table.insert(out, { id = s.id, kind = s.kind, position = s.position, state = s.state })
	end
	return out
end

-- Extra (see report): BossService can read it to spawn the second boss.
function ShrineService.isBossChallengeActive(): boolean
	return bossChallengeActive
end

-- Domain-internal (LootService).
function ShrineService._xpMultiplierAt(x: number, z: number): number
	if os.clock() > bell.untilTime + Shrines.BellXpGrace then
		return 1
	end
	local dx, dz = x - bell.x, z - bell.z
	if dx * dx + dz * dz <= Shrines.BellRadius * Shrines.BellRadius then
		return Shrines.BellXpMult
	end
	return 1
end

function ShrineService._isTrialEnemy(id: number): boolean
	return trialEnemyIds[id] == true
end

-- Lifecycle ------------------------------------------------------------------

function ShrineService.init()
	stateRemote = Net.event("ShrineState")
	offerRemote = Net.event("ShrineOffer")
	gagRemote = Net.event("ShrineGag")
	Net.onServerEvent("ShrineChoice", 5, onChoice)
	Net.onServerEvent("ShrineInteract", 4, onInteract)

	Bus.RunStarted:connect(function()
		runToken += 1
		bossChallengeActive = false
		clearShrines()
	end)
	Bus.StageStarted:connect(function(stage: number)
		spawnShrines(if isFiniteNumber(stage) then stage else 1)
	end)
	Bus.RunEnded:connect(function()
		runToken += 1
		stageActive = false
		clearShrines()
	end)
	Bus.PlayerDied:connect(function(player: Player)
		votes[player] = nil
	end)

	Players.PlayerAdded:Connect(markDirty)
	Players.PlayerRemoving:Connect(function(player)
		votes[player] = nil
		for _, offer in offers do
			if offer.player == player then
				offers[offer.id] = nil
			end
		end
		for _, s in shrines do
			s.uses[player] = nil
		end
	end)
end

function ShrineService.start()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < DT then
			return
		end
		acc = math.min(acc - DT, DT)
		step()
	end)
	if not Registry.find("RunManager") then
		task.wait(2.5)
		if not stageActive then
			warnOnce("standalone", "RunManager missing: spawning test shrines")
			spawnShrines(1)
		end
	end
end

return ShrineService
