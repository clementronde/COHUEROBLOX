--!strict
-- XP gems, run coins, pots, chests and the wandering merchant (docs/dossier/30-butin-autels.md).
-- Everything is server data (no Parts here). Clients draw from LootSnapshot (LootCodec):
-- deltas at 10 Hz when something changed, plus a full repair snapshot every second.
-- Pickups and walk-in opens are server point tests against HumanoidRootPart positions;
-- clients only send intents (LootInteract, MerchantBuy), validated here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Loot = require(Config:WaitForChild("Loot"))
local Enemies = require(Config:WaitForChild("Enemies"))
local Codec = require(Shared:WaitForChild("LootCodec"))
local Heightmap = require(Shared:WaitForChild("Heightmap"))
local Net = require(Shared:WaitForChild("Net"))
local Registry = require(Shared:WaitForChild("Registry"))
local Types = require(Shared:WaitForChild("Types"))
local Bus = require(script.Parent.Parent:WaitForChild("Bus"))

local DT = 1 / Loot.SimHz
local MAX_ID = 65535
local K = Codec.Kind
local S = Codec.State
local RARITIES = Loot.RarityOrder
local RUNNING_PHASES = { Running = true, Boss = true, BossDefeated = true, FinalWave = true }
local FAMILY_ALIAS: { [string]: string } = {
	swarm = "Swarm",
	essaim = "Swarm",
	jumper = "Jumper",
	jumpers = "Jumper",
	sauteur = "Jumper",
	sauteurs = "Jumper",
	shooter = "Shooter",
	shooters = "Shooter",
	tireur = "Shooter",
	tireurs = "Shooter",
	armored = "Armored",
	armoured = "Armored",
	blinde = "Armored",
	blindes = "Armored",
}

type Entity = {
	id: number,
	kind: number, -- LootCodec.Kind
	x: number,
	z: number,
	value: number, -- xp or coins
	owner: Player?, -- instanced chests: only the owner sees and opens it
	chestKind: string?,
	paid: boolean,
}

type MerchantSlot = { slot: number, kind: string, itemId: string?, rarity: string, price: number, sold: boolean }

type PlayerState = {
	coins: number,
	coinFrac: number,
	coinsEarned: number,
	chestsOpened: number,
	chestsBought: number, -- this stage
	merchantStock: { MerchantSlot }?,
	coinsDirty: boolean,
}

type Pos = { player: Player, x: number, z: number, active: boolean, magnet2: number, xpGain: number, lootBonus: number }

local LootService = {}

-- World state
local all: { [number]: Entity } = {}
local gems: { [number]: Entity } = {}
local coinsOnGround: { [number]: Entity } = {}
local pots: { [number]: Entity } = {}
local chests: { [number]: Entity } = {}
local gemCount = 0
local coinCount = 0
local merchant: Entity? = nil
local merchantMovedAt = 0
local nextId = 1

local states: { [Player]: PlayerState } = {}
local stage = 1
local tier = 1
local stageStart = 0
local stageActive = false
local simTick = 0
local rng = Random.new()

-- Pending deltas (parallel arrays, cleared every tick)
local dCount = 0
local dIds: { number } = {}
local dXs: { number } = {}
local dZs: { number } = {}
local dFlags: { number } = {}
local dOwners: { Player | false } = {}

-- Reused send buffers
local sIds: { number } = {}
local sXs: { number } = {}
local sZs: { number } = {}
local sFlags: { number } = {}

-- Per-tick reusable player positions
local positions: { Pos } = {}
local posCount = 0
local xpPending: { [Player]: number } = {}
local coinPending: { [Player]: number } = {}

local snapshotRemote: UnreliableRemoteEvent
local coinsRemote: RemoteEvent
local merchantOfferRemote: RemoteEvent
local rewardRemote: RemoteEvent

local itemsByRarity: { [string]: { string } }? = nil
local warned: { [string]: boolean } = {}

-- Helpers ---------------------------------------------------------------------

local function warnOnce(key: string, message: string)
	if not warned[key] then
		warned[key] = true
		warn(`[LootService] {message}`)
	end
end

-- Cross-domain calls never break the loot tick.
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

local function record(player: Player, key: string, amount: number)
	local progression = Registry.find("ProgressionService")
	if progression then
		safeCall("ProgressionService.recordStat", progression.recordStat, player, key, amount)
	end
end

local function getState(player: Player): PlayerState
	local st = states[player]
	if not st then
		st = {
			coins = 0,
			coinFrac = 0,
			coinsEarned = 0,
			chestsOpened = 0,
			chestsBought = 0,
			merchantStock = nil,
			coinsDirty = true,
		}
		states[player] = st
	end
	return st
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

local function isActive(player: Player): boolean
	local run = Registry.find("RunManager")
	if not run then
		return true
	end
	local ok, active = safeCall("RunManager.isActive", run.isActive, player)
	return ok and active == true
end

local function rootPosition(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function statsOf(player: Player): Types.StatBlock?
	local stats = Registry.find("StatsService")
	if not stats then
		return nil
	end
	local ok, block = safeCall("StatsService.get", stats.get, player)
	if ok and type(block) == "table" then
		return block
	end
	return nil
end

local function statValue(block: Types.StatBlock?, stat: Types.StatName): number
	local v = block and block[stat]
	return if isFiniteNumber(v) then v :: number else 0
end

local function allocId(): number?
	for _ = 1, MAX_ID do
		local id = nextId
		nextId = nextId % MAX_ID + 1
		if all[id] == nil then
			return id
		end
	end
	return nil
end

local function pushDelta(e: Entity, state: number)
	dCount += 1
	dIds[dCount] = e.id
	dXs[dCount] = e.x
	dZs[dCount] = e.z
	dFlags[dCount] = Codec.packFlags(e.kind, state)
	dOwners[dCount] = e.owner or false
end

local function baseState(e: Entity): number
	return if e.paid then S.Paid else 0
end

local function newEntity(kind: number, x: number, z: number, value: number, owner: Player?): Entity?
	local id = allocId()
	if not id then
		return nil
	end
	local e: Entity = { id = id, kind = kind, x = x, z = z, value = value, owner = owner, paid = false }
	all[id] = e
	return e
end

local function removeEntity(e: Entity, state: number)
	all[e.id] = nil
	if gems[e.id] then
		gems[e.id] = nil
		gemCount -= 1
	elseif coinsOnGround[e.id] then
		coinsOnGround[e.id] = nil
		coinCount -= 1
	end
	pots[e.id] = nil
	chests[e.id] = nil
	pushDelta(e, state)
end

local function stageMult(bonus: number): number
	return 1 + bonus * (stage - 1)
end

local function chestCost(player: Player): number
	local st = getState(player)
	return math.round(Loot.ChestBaseCost * stageMult(Loot.ChestStageCostBonus) * Loot.ChestCostGrowth ^ st.chestsBought)
end

-- Items ----------------------------------------------------------------------

local function loadItems(): { [string]: { string } }
	if itemsByRarity then
		return itemsByRarity
	end
	local result: { [string]: { string } } = { Common = {}, Rare = {}, Epic = {}, Legendary = {} }
	local module = Config:FindFirstChild("Items")
	if module and module:IsA("ModuleScript") then
		local ok, data = pcall(require :: any, module)
		if ok and type(data) == "table" then
			for key, def in data do
				if type(def) == "table" then
					local id = if type(def.id) == "string" then def.id elseif type(key) == "string" then key else nil
					local rarity = def.rarity
					if id and type(rarity) == "string" and result[rarity] then
						table.insert(result[rarity], id)
					end
				end
			end
		end
	else
		warnOnce("items", "Config.Items missing: chests give fallback coins")
	end
	for _, list in result do
		table.sort(list)
	end
	itemsByRarity = result
	return result
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

-- Picks an unlocked item of that rarity, falling back to lower rarities.
local function pickItem(player: Player, rarityIndex: number): (string?, number)
	local items = loadItems()
	local progression = Registry.find("ProgressionService")
	for r = rarityIndex, 1, -1 do
		local list = items[RARITIES[r]]
		local candidates: { string } = {}
		for _, id in list do
			local allowed = true
			if progression and type(progression.isUnlocked) == "function" then
				local ok, unlocked = pcall(progression.isUnlocked, player, "Item", id)
				allowed = not ok or unlocked == true
			end
			if allowed then
				table.insert(candidates, id)
			end
		end
		if #candidates > 0 then
			return candidates[rng:NextInteger(1, #candidates)], r
		end
	end
	return nil, rarityIndex
end

-- Coins ----------------------------------------------------------------------

local function sendCoins(player: Player)
	local st = getState(player)
	st.coinsDirty = false
	coinsRemote:FireClient(player, { coins = st.coins, chestCost = chestCost(player) })
end

-- Rolls one item (or fallback coins) for a player and tells the client. Returns the item id.
function LootService._grantRandomItem(player: Player, rarityTable: string, source: string): string?
	local base = Loot.ChestRarity[rarityTable] or Loot.ChestRarity.Normal
	local luck = statValue(statsOf(player), "Luck")
	local rarityIndex = rollRarity(base, luck)
	local itemId, gotRarity = pickItem(player, rarityIndex)
	local stats = Registry.find("StatsService")
	if itemId and stats then
		safeCall("StatsService.grantItem", stats.grantItem, player, itemId)
		rewardRemote:FireClient(player, { source = source, itemId = itemId, rarity = RARITIES[gotRarity] })
		return itemId
	end
	local coins = Loot.ItemFallbackCoins[rarityIndex] or 5
	LootService.addCoins(player, coins)
	rewardRemote:FireClient(player, { source = source, rarity = RARITIES[rarityIndex], coins = coins })
	return nil
end

local function openChest(player: Player, e: Entity)
	local kind = e.chestKind or "Normal"
	removeEntity(e, S.Removed)
	local n = Loot.ChestItems[kind] or 1
	for _ = 1, n do
		LootService._grantRandomItem(player, kind, "Chest:" .. kind)
	end
	local st = getState(player)
	st.chestsOpened += 1
	record(player, "ChestsOpened", 1)
	Bus.ChestOpened:fire(player, kind)
end

-- Merging / dropping --------------------------------------------------------

local function nearestIn(set: { [number]: Entity }, x: number, z: number, radius: number): Entity?
	local best: Entity? = nil
	local bestD2 = radius * radius
	for _, e in set do
		local dx, dz = e.x - x, e.z - z
		local d2 = dx * dx + dz * dz
		if d2 <= bestD2 then
			bestD2 = d2
			best = e
		end
	end
	return best
end

local function gemKind(value: number): number
	return K.GemSmall + Loot.gemTier(value) - 1
end

local function coinKind(value: number): number
	return if value >= Loot.CoinPileValue then K.CoinPile else K.Coin
end

local function mergeInto(e: Entity, value: number, isGem: boolean)
	e.value += value
	local kind = if isGem then gemKind(e.value) else coinKind(e.value)
	if kind ~= e.kind then
		e.kind = kind
		pushDelta(e, 0) -- update: same id, new look
	end
end

-- Vacuum: every gem on the ground flies to this player (pot result).
local function vacuum(player: Player)
	for _, e in gems do
		xpPending[player] = (xpPending[player] or 0) + e.value
		removeEntity(e, S.Collected)
	end
end

-- Spawning stage content --------------------------------------------------------

-- Spawn points from StageService, else a seeded scatter around the map centre.
function LootService._spawnPoints(kind: string, n: number, seed: number): { Vector3 }
	local out: { Vector3 } = {}
	local stageService = Registry.find("StageService")
	if stageService then
		local ok, list = safeCall("StageService.getSpawnPoints", stageService.getSpawnPoints, kind)
		if ok and type(list) == "table" then
			local pool: { Vector3 } = {}
			for _, p in list do
				if typeof(p) == "Vector3" then
					table.insert(pool, p)
				end
			end
			local shuffle = Random.new(seed)
			for i = #pool, 2, -1 do
				local j = shuffle:NextInteger(1, i)
				pool[i], pool[j] = pool[j], pool[i]
			end
			for i = 1, math.min(n, #pool) do
				out[i] = pool[i]
			end
			if #out > 0 then
				return out
			end
		end
	end
	local scatter = Random.new(seed)
	for i = 1, n do
		local a = scatter:NextNumber() * math.pi * 2
		local r = Loot.FallbackMinRadius + scatter:NextNumber() * (Loot.FallbackMaxRadius - Loot.FallbackMinRadius)
		local x, z = math.cos(a) * r, math.sin(a) * r
		out[i] = Vector3.new(x, Heightmap.getY(x, z), z)
	end
	return out
end

-- Envoi complet en cours, un paquet par tick (PERF-09, voir sendFull).
local fullQueue: { [Player]: { chunks: { buffer }, nextIndex: number } } = {}

local function clearWorld()
	for _, e in all do
		pushDelta(e, S.Removed)
	end
	table.clear(all)
	table.clear(gems)
	table.clear(coinsOnGround)
	table.clear(pots)
	table.clear(chests)
	table.clear(fullQueue) -- un ensemble capturé avant le nettoyage ferait réapparaître le butin
	gemCount, coinCount = 0, 0
	merchant = nil
end

local function spawnStageContent()
	local seed = os.time() + stage * 7919
	for _, p in LootService._spawnPoints("Pot", Loot.PotsPerStage, seed) do
		local e = newEntity(K.Pot, p.X, p.Z, 0, nil)
		if e then
			pots[e.id] = e
			pushDelta(e, 0)
		end
	end
	local chestPoints = LootService._spawnPoints("Chest", Loot.ChestsPerStage, seed + 1)
	for _, player in runPlayers() do
		for _, p in chestPoints do
			local e = newEntity(K.ChestNormal, p.X, p.Z, 0, player)
			if e then
				e.chestKind = "Normal"
				e.paid = true
				chests[e.id] = e
				pushDelta(e, S.Paid)
			end
		end
	end
end

local function placeMerchant()
	local points = LootService._spawnPoints("Merchant", 8, os.time() + simTick)
	local p = points[rng:NextInteger(1, #points)]
	local current = merchant
	if current then
		current.x, current.z = p.X, p.Z
		pushDelta(current, 0)
	else
		local e = newEntity(K.Merchant, p.X, p.Z, 0, nil)
		if e then
			merchant = e
			pushDelta(e, 0)
		end
	end
	merchantMovedAt = os.clock()
end

-- Tick ----------------------------------------------------------------------

local function gatherPositions()
	posCount = 0
	for _, player in runPlayers() do
		local p = rootPosition(player)
		if p then
			posCount += 1
			local entry = positions[posCount]
			if not entry then
				entry = { player = player, x = 0, z = 0, active = false, magnet2 = 0, xpGain = 0, lootBonus = 0 }
				positions[posCount] = entry
			end
			local block = statsOf(player)
			local magnet = math.clamp(Loot.BaseMagnet + statValue(block, "Magnet"), 0, Loot.MaxMagnet)
			entry.player = player
			entry.x, entry.z = p.X, p.Z
			entry.active = isActive(player)
			entry.magnet2 = magnet * magnet
			entry.xpGain = statValue(block, "XpGain")
			entry.lootBonus = statValue(block, "LootBonus")
		end
	end
end

local function awardXp()
	local stats = Registry.find("StatsService")
	for player, amount in xpPending do
		-- XP share (vision 5.2): allies within XpShareRadius get XpShareRatio, the picker keeps 100 %.
		local picker: Pos? = nil
		for i = 1, posCount do
			if positions[i].player == player then
				picker = positions[i]
			end
		end
		local final: { [Player]: number } = {}
		local pickerGain = if picker then picker.xpGain else 0
		final[player] = amount * (1 + pickerGain)
		if picker then
			local r2 = Loot.XpShareRadius * Loot.XpShareRadius
			for i = 1, posCount do
				local q = positions[i]
				if q.player ~= player and q.active then
					local dx, dz = q.x - picker.x, q.z - picker.z
					if dx * dx + dz * dz <= r2 then
						final[q.player] = (final[q.player] or 0) + amount * Loot.XpShareRatio * (1 + q.xpGain)
					end
				end
			end
		end
		if stats then
			for target, xp in final do
				safeCall("StatsService.addXp", stats.addXp, target, math.round(xp * 100) / 100)
			end
		end
	end
	table.clear(xpPending)
end

local function awardCoins()
	for player, amount in coinPending do
		local bonus = 0
		for i = 1, posCount do
			if positions[i].player == player then
				bonus = positions[i].lootBonus
			end
		end
		local st = getState(player)
		local total = amount * (1 + math.max(bonus, 0)) + st.coinFrac
		local whole = math.floor(total)
		st.coinFrac = total - whole
		if whole > 0 then
			LootService.addCoins(player, whole)
			record(player, "CoinsCollected", whole)
		end
	end
	table.clear(coinPending)
end

local function breakPot(e: Entity, player: Player)
	removeEntity(e, S.Removed)
	record(player, "PotsBroken", 1)
	local total = 0
	for _, row in Loot.PotTable do
		total += row.weight
	end
	local r = rng:NextNumber() * total
	for _, row in Loot.PotTable do
		r -= row.weight
		if r <= 0 then
			local amount = rng:NextInteger(row.min, math.max(row.min, row.max))
			if row.result == "Coins" then
				LootService.dropCoins(e.x + rng:NextNumber(-1, 1), e.z + rng:NextNumber(-1, 1), amount)
			elseif row.result == "Xp" then
				LootService.dropXp(e.x, e.z, amount)
			elseif row.result == "Vacuum" then
				vacuum(player)
			end
			return
		end
	end
end

local function pickupStep()
	for _, e in gems do
		for i = 1, posCount do
			local p = positions[i]
			if p.active then
				local dx, dz = e.x - p.x, e.z - p.z
				if dx * dx + dz * dz <= p.magnet2 then
					xpPending[p.player] = (xpPending[p.player] or 0) + e.value
					removeEntity(e, S.Collected)
					break
				end
			end
		end
	end
	for _, e in coinsOnGround do
		for i = 1, posCount do
			local p = positions[i]
			if p.active then
				local dx, dz = e.x - p.x, e.z - p.z
				if dx * dx + dz * dz <= p.magnet2 then
					coinPending[p.player] = (coinPending[p.player] or 0) + e.value
					removeEntity(e, S.Collected)
					break
				end
			end
		end
	end
	local pot2 = Loot.PotBreakRadius * Loot.PotBreakRadius
	for _, e in pots do
		for i = 1, posCount do
			local p = positions[i]
			if p.active then
				local dx, dz = e.x - p.x, e.z - p.z
				if dx * dx + dz * dz <= pot2 then
					breakPot(e, p.player)
					break
				end
			end
		end
	end
	local open2 = Loot.ChestAutoOpenRadius * Loot.ChestAutoOpenRadius
	for _, e in chests do
		if not e.paid and e.owner then
			for i = 1, posCount do
				local p = positions[i]
				if p.player == e.owner and p.active then
					local dx, dz = e.x - p.x, e.z - p.z
					if dx * dx + dz * dz <= open2 then
						openChest(p.player, e)
					end
					break
				end
			end
		end
	end
end

local function sendTo(player: Player, mode: number, n: number)
	for _, chunk in Codec.encode(simTick, mode, sIds, sXs, sZs, sFlags, n) do
		snapshotRemote:FireClient(player, chunk)
	end
end

local function sendDeltas()
	if dCount == 0 then
		return
	end
	local r2 = Loot.InterestRadius * Loot.InterestRadius
	for _, player in Players:GetPlayers() do
		local p = rootPosition(player)
		if p then
			local n = 0
			for i = 1, dCount do
				local owner = dOwners[i]
				if owner == false or owner == player then
					local dx, dz = dXs[i] - p.X, dZs[i] - p.Z
					if dx * dx + dz * dz <= r2 then
						n += 1
						sIds[n], sXs[n], sZs[n], sFlags[n] = dIds[i], dXs[i], dZs[i], dFlags[i]
					end
				end
			end
			if n > 0 then
				sendTo(player, Codec.Mode.Delta, n)
			end
		end
	end
	dCount = 0
end

-- PERF-09 : l'ensemble complet est capturé en une fois (tous ses paquets portent le même tick, le
-- client le reconstitue), puis envoyé à raison d'UN paquet par tick et par joueur. Sur un réseau
-- mobile, 5 paquets non fiables partis d'un coup se perdaient ensemble. 5 paquets = 0,5 s, bien
-- avant l'envoi complet suivant (FullSyncEvery = 10 ticks) ; un ensemble pas fini est remplacé.

local function sendFull()
	local r2 = Loot.InterestRadius * Loot.InterestRadius
	for _, player in Players:GetPlayers() do
		local p = rootPosition(player)
		if p then
			local n = 0
			for _, e in all do
				if e.owner == nil or e.owner == player then
					local dx, dz = e.x - p.X, e.z - p.Z
					if dx * dx + dz * dz <= r2 then
						n += 1
						sIds[n], sXs[n], sZs[n], sFlags[n] = e.id, e.x, e.z, Codec.packFlags(e.kind, baseState(e))
					end
				end
			end
			fullQueue[player] = { chunks = Codec.encode(simTick, Codec.Mode.Full, sIds, sXs, sZs, sFlags, n), nextIndex = 1 }
		end
	end
end

local function drainFull()
	for player, q in fullQueue do
		local chunk = q.chunks[q.nextIndex]
		if chunk and player.Parent then
			snapshotRemote:FireClient(player, chunk)
			q.nextIndex += 1
		end
		if not player.Parent or q.nextIndex > #q.chunks then
			fullQueue[player] = nil
		end
	end
end

local function step()
	simTick += 1
	-- Gel coop du passage de niveau (RunManager) : aimant, ramassage, coffres et marchand s'arrêtent ;
	-- les clients reçoivent toujours l'état.
	if isRunning() and not Workspace:GetAttribute("RunFrozen") then
		gatherPositions()
		pickupStep()
		awardXp()
		awardCoins()
		local now = os.clock()
		if stageActive then
			if merchant == nil and now - stageStart >= Loot.MerchantAppearAt then
				placeMerchant()
			elseif merchant and now - merchantMovedAt >= Loot.MerchantMoveEvery then
				placeMerchant()
			end
		end
	end
	sendDeltas()
	if simTick % Loot.FullSyncEvery == 0 then
		sendFull()
	end
	drainFull()
	for player, st in states do
		if st.coinsDirty and player.Parent then
			sendCoins(player)
		end
	end
end

-- Client intents -------------------------------------------------------------

local function validId(v: any): boolean
	return isFiniteNumber(v) and v % 1 == 0 and v >= 1 and v <= MAX_ID
end

local function withinRange(player: Player, x: number, z: number, range: number): boolean
	local p = rootPosition(player)
	if not p then
		return false
	end
	local dx, dz = p.X - x, p.Z - z
	return dx * dx + dz * dz <= range * range
end

local function buildMerchantStock(player: Player): { MerchantSlot }
	local stock: { MerchantSlot } = {}
	local luck = statValue(statsOf(player), "Luck")
	local base = Loot.ChestRarity[Loot.MerchantRarity] or Loot.ChestRarity.Normal
	local priceMult = stageMult(Loot.MerchantStagePriceBonus)
	for slot = 1, Loot.MerchantItemSlots do
		local itemId, r = pickItem(player, rollRarity(base, luck))
		if itemId then
			table.insert(stock, {
				slot = slot,
				kind = "Item",
				itemId = itemId,
				rarity = RARITIES[r],
				price = math.round(Loot.MerchantPrices[r] * priceMult),
				sold = false,
			})
		end
	end
	table.insert(stock, {
		slot = Loot.MerchantItemSlots + 1,
		kind = "Heal",
		itemId = nil,
		rarity = "Common",
		price = math.round(Loot.MerchantHealPrice * priceMult),
		sold = false,
	})
	return stock
end

local function sendMerchantOffer(player: Player)
	local m = merchant
	local st = getState(player)
	if not m or not st.merchantStock then
		return
	end
	merchantOfferRemote:FireClient(player, { merchantId = m.id, name = Loot.MerchantName, offers = st.merchantStock })
end

local function onInteract(player: Player, id: any)
	if not validId(id) or not isRunning() or not isActive(player) or Workspace:GetAttribute("RunFrozen") then
		return
	end
	local e = all[id]
	if not e or (e.owner ~= nil and e.owner ~= player) then
		return
	end
	if e.kind == K.Merchant then
		if not withinRange(player, e.x, e.z, Loot.MerchantRange + Loot.InteractSlack) then
			return
		end
		local st = getState(player)
		if not st.merchantStock then
			st.merchantStock = buildMerchantStock(player)
		end
		sendMerchantOffer(player)
		return
	end
	if not chests[id] or e.owner ~= player then
		return
	end
	if not withinRange(player, e.x, e.z, Loot.InteractRange + Loot.InteractSlack) then
		return
	end
	if e.paid then
		local cost = chestCost(player)
		if not LootService.spendCoins(player, cost) then
			return
		end
		getState(player).chestsBought += 1
		getState(player).coinsDirty = true -- next chest price changed
		record(player, "ChestsBought", 1)
	end
	openChest(player, e)
end

local function onMerchantBuy(player: Player, slot: any)
	if not isFiniteNumber(slot) or slot % 1 ~= 0 or slot < 1 or slot > Loot.MerchantItemSlots + 1 then
		return
	end
	local m = merchant
	if not m or not isRunning() or not isActive(player) then
		return
	end
	if not withinRange(player, m.x, m.z, Loot.MerchantRange + Loot.InteractSlack) then
		return
	end
	local st = getState(player)
	local stock = st.merchantStock
	if not stock then
		return
	end
	local entry: MerchantSlot? = nil
	for _, s in stock do
		if s.slot == slot then
			entry = s
		end
	end
	if not entry or entry.sold then
		return
	end
	-- Check, deduct and mark in one non-yielding step (no dupes from spamming).
	if not LootService.spendCoins(player, entry.price) then
		return
	end
	entry.sold = true
	if entry.kind == "Heal" then
		local run = Registry.find("RunManager")
		local block = statsOf(player)
		local maxHp = statValue(block, "MaxHp")
		if run then
			safeCall("RunManager.healPlayer", run.healPlayer, player, math.max(1, maxHp * Loot.MerchantHealFraction))
		end
	elseif entry.itemId then
		local stats = Registry.find("StatsService")
		if stats then
			safeCall("StatsService.grantItem", stats.grantItem, player, entry.itemId)
		end
		rewardRemote:FireClient(player, { source = "Merchant", itemId = entry.itemId, rarity = entry.rarity })
	end
	record(player, "MerchantPurchases", 1)
	sendMerchantOffer(player)
end

-- Bus handlers ---------------------------------------------------------------

local function familyOf(def: any): string
	local family = def and def.family
	if type(family) == "string" then
		return FAMILY_ALIAS[string.lower(family)] or family
	end
	return "Swarm"
end

local function onEnemyKilled(id: number, kind: number, x: number, z: number, _killer: Player?, isElite: boolean)
	if not isRunning() or not isFiniteNumber(x) or not isFiniteNumber(z) then
		return
	end
	local def = (Enemies :: any)[kind]
	local family = familyOf(def)
	local xp = if def and isFiniteNumber(def.xp) then def.xp else (Loot.XpByFamily[family] or Loot.DefaultXp)
	if isElite then
		xp *= Loot.EliteXpMult
	end
	local shrines = Registry.find("ShrineService")
	local trialEnemy = false
	if shrines then
		local ok, mult = safeCall("ShrineService._xpMultiplierAt", shrines._xpMultiplierAt, x, z)
		if ok and isFiniteNumber(mult) then
			xp *= mult
		end
		local ok2, isTrial = safeCall("ShrineService._isTrialEnemy", shrines._isTrialEnemy, id)
		trialEnemy = ok2 and isTrial == true
	end
	LootService.dropXp(x, z, xp)

	local tierMult = 1 + Loot.CoinTierBonus * (tier - 1)
	if isElite then
		LootService.dropCoins(x + 1, z, math.round(Loot.EliteCoins * tierMult))
		if not trialEnemy then -- trial shrines give their own chest
			LootService.spawnChest(x, z, "Elite", nil)
		end
	else
		local row = Loot.CoinsByFamily[family] or Loot.CoinsByFamily.Swarm
		if rng:NextNumber() < row.chance then
			LootService.dropCoins(x, z, math.max(1, math.round(row.amount * tierMult)))
		end
	end
end

local function startStage(newStage: number)
	stage = newStage
	clearWorld()
	for _, st in states do
		st.chestsBought = 0
		st.merchantStock = nil
		st.coinsDirty = true
	end
	stageStart = os.clock()
	stageActive = true
	spawnStageContent()
end

local function onRunStarted(_players: { Player }, _worldId: string, newTier: number)
	tier = if isFiniteNumber(newTier) then newTier else 1
	for _, st in states do
		st.coins, st.coinFrac, st.coinsEarned, st.chestsOpened = 0, 0, 0, 0
		st.coinsDirty = true
	end
	clearWorld()
end

local function onBossDefeated(_bossId: string, _stage: number)
	local shrines = Registry.find("ShrineService")
	local doubled = false
	if shrines then
		local ok, active = safeCall("ShrineService.isBossChallengeActive", shrines.isBossChallengeActive)
		doubled = ok and active == true
	end
	for _, player in runPlayers() do
		local p = rootPosition(player)
		if p and isActive(player) then
			local a = rng:NextNumber() * math.pi * 2
			local ox, oz = math.cos(a) * Loot.BossChestOffset, math.sin(a) * Loot.BossChestOffset
			LootService.spawnChest(p.X + ox, p.Z + oz, "Boss", player)
			if doubled then
				LootService.spawnChest(p.X - ox, p.Z - oz, "Boss", player)
			end
		end
	end
end

-- Public API (ARCHITECTURE.md section 4) -------------------------------------

function LootService.dropXp(x: number, z: number, amount: number)
	if not isFiniteNumber(x) or not isFiniteNumber(z) or not isFiniteNumber(amount) or amount <= 0 then
		return
	end
	if gemCount >= Loot.GemMergeThreshold then
		local target = nearestIn(gems, x, z, Loot.GemMergeRadius)
		if not target and gemCount >= Loot.MaxGems then
			local _, first = next(gems)
			target = first
		end
		if target then
			mergeInto(target, amount, true)
			return
		end
	end
	local e = newEntity(gemKind(amount), x, z, amount, nil)
	if e then
		gems[e.id] = e
		gemCount += 1
		pushDelta(e, 0)
	end
end

function LootService.dropCoins(x: number, z: number, amount: number)
	if not isFiniteNumber(x) or not isFiniteNumber(z) or not isFiniteNumber(amount) or amount <= 0 then
		return
	end
	amount = math.max(1, math.round(amount))
	if coinCount >= Loot.CoinMergeThreshold then
		local target = nearestIn(coinsOnGround, x, z, Loot.CoinMergeRadius)
		if not target and coinCount >= Loot.MaxCoins then
			local _, first = next(coinsOnGround)
			target = first
		end
		if target then
			mergeInto(target, amount, false)
			return
		end
	end
	local e = newEntity(coinKind(amount), x, z, amount, nil)
	if e then
		coinsOnGround[e.id] = e
		coinCount += 1
		pushDelta(e, 0)
	end
end

-- Free chest. owner nil = one instanced copy per active run player (vision 5.2).
function LootService.spawnChest(x: number, z: number, kind: "Normal" | "Elite" | "Boss" | "Shrine", owner: Player?)
	if not isFiniteNumber(x) or not isFiniteNumber(z) then
		return
	end
	local codecKind = Codec.ChestKindOf[kind]
	if not codecKind then
		return
	end
	local owners: { Player } = {}
	if owner then
		owners[1] = owner
	else
		for _, player in runPlayers() do
			if isActive(player) then
				table.insert(owners, player)
			end
		end
	end
	for _, player in owners do
		local e = newEntity(codecKind, x, z, 0, player)
		if e then
			e.chestKind = kind
			chests[e.id] = e
			pushDelta(e, 0)
		end
	end
end

function LootService.addCoins(player: Player, amount: number)
	if not isFiniteNumber(amount) or amount <= 0 then
		return
	end
	local st = getState(player)
	local whole = math.floor(amount)
	st.coins += whole
	st.coinsEarned += whole
	st.coinsDirty = true
end

function LootService.getCoins(player: Player): number
	local st = states[player]
	return if st then st.coins else 0
end

function LootService.spendCoins(player: Player, amount: number): boolean
	if not isFiniteNumber(amount) or amount < 0 then
		return false
	end
	local st = getState(player)
	if st.coins < amount then
		return false
	end
	st.coins -= amount
	st.coinsDirty = true
	return true
end

-- Extra (not in section 4 yet, see report): run totals for RunManager's RunSummary.
function LootService.getRunStats(player: Player): { coinsEarned: number, chestsOpened: number }
	local st = states[player]
	return { coinsEarned = if st then st.coinsEarned else 0, chestsOpened = if st then st.chestsOpened else 0 }
end

-- Domain-internal: ShrineService uses these.
function LootService._getStage(): number
	return stage
end

function LootService._chestCost(player: Player): number
	return chestCost(player)
end

-- Lifecycle ------------------------------------------------------------------

function LootService.init()
	snapshotRemote = Net.unreliable("LootSnapshot")
	coinsRemote = Net.event("Coins")
	merchantOfferRemote = Net.event("MerchantOffer")
	rewardRemote = Net.event("LootReward")
	Net.onServerEvent("LootInteract", 5, onInteract)
	Net.onServerEvent("MerchantBuy", 5, onMerchantBuy)

	Bus.EnemyKilled:connect(onEnemyKilled)
	Bus.RunStarted:connect(onRunStarted)
	Bus.StageStarted:connect(function(newStage: number, _worldId: string)
		startStage(if isFiniteNumber(newStage) then newStage else 1)
	end)
	Bus.BossDefeated:connect(onBossDefeated)
	Bus.RunEnded:connect(function()
		stageActive = false
		clearWorld()
	end)

	Players.PlayerAdded:Connect(function(player)
		getState(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		for _, e in chests do
			if e.owner == player then
				all[e.id] = nil
				chests[e.id] = nil
			end
		end
		states[player] = nil
		fullQueue[player] = nil
		xpPending[player] = nil
		coinPending[player] = nil
	end)
end

function LootService.start()
	for _, player in Players:GetPlayers() do
		getState(player)
	end
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < DT then
			return
		end
		acc = math.min(acc - DT, DT)
		step()
	end)
	-- Standalone test (no RunManager): start stage 1 by itself.
	if not Registry.find("RunManager") then
		task.wait(2)
		if not stageActive then
			warnOnce("standalone", "RunManager missing: starting a test stage")
			startStage(1)
		end
	end
end

return LootService
