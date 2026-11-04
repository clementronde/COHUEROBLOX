--!strict
-- Per-player run build: XP/level, weapons, grimoires, items, final StatBlock (dossier 10, sections 1-4).
-- Cross-domain API (ARCHITECTURE.md section 4): get, addStat, addXp, getLevel, getBuild, grantItem, resetRun.
-- Combat-internal API (used by CardService / WeaponService / PassiveService): see "Domain API" below.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Cards = require(Config:WaitForChild("Cards"))
local Classes = require(Config:WaitForChild("Classes"))
local Grimoires = require(Config:WaitForChild("Grimoires"))
local Items = require(Config:WaitForChild("Items"))
local Weapons = require(Config:WaitForChild("Weapons"))
local Net = require(Shared:WaitForChild("Net"))
local Registry = require(Shared:WaitForChild("Registry"))
local Types = require(Shared:WaitForChild("Types"))
local Bus = require(script.Parent.Parent:WaitForChild("Bus"))

type StatBlock = Types.StatBlock
type WeaponEntry = { id: string, level: number, bonus: number }
type GrimoireEntry = { id: string, level: number }
type ItemEntry = { id: string, count: number }
type TempBoost = { stat: string, value: number, expires: number }

export type RunState = {
	classId: string,
	level: number,
	xp: number,
	weapons: { WeaponEntry },
	grimoires: { GrimoireEntry },
	items: { ItemEntry },
	itemCount: { [string]: number },
	boosts: { [string]: number },
	temps: { TempBoost },
	banish: number,
	skip: number,
	reroll: number,
	weaponSlots: number,
	grimoireSlots: number,
	banished: { [string]: boolean },
	stats: StatBlock,
	statsDirty: boolean,
	buildDirty: boolean,
	progressDirty: boolean,
	damageByWeapon: { [string]: number },
}

local SEND_PERIOD = 0.2 -- Build / PlayerProgress coalesced at 5 Hz

local StatsService = {}

local states: { [Player]: RunState } = {}
local baseBlock: StatBlock = table.freeze(table.clone(Grimoires.BaseStats)) :: any
local buildRemote: RemoteEvent
local progressRemote: RemoteEvent

local function isFiniteNumber(v: unknown): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function computeStats(s: RunState): StatBlock
	local out: { [string]: number } = table.clone(Grimoires.BaseStats)
	-- Grimoires
	for _, g in s.grimoires do
		local def = Grimoires.Defs[g.id]
		if def then
			for stat in out do
				local v = Grimoires.valueAt(def, stat, g.level)
				if v ~= 0 then
					out[stat] += v
				end
			end
		end
	end
	-- Items (sums, then mults)
	for _, it in s.items do
		local def = Items.Defs[it.id]
		if def and def.stats then
			for stat, v in def.stats do
				if out[stat] ~= nil then
					out[stat] += v * it.count
				end
			end
		end
	end
	-- Class passive
	local passive = Weapons.Passives[s.classId]
	if passive then
		local perLevel = passive.perLevel :: { [string]: number }?
		if perLevel then
			for stat, v in perLevel do
				if out[stat] ~= nil then
					out[stat] += v * s.level
				end
			end
		end
		local flat = passive.flat :: { [string]: number }?
		if flat then
			for stat, v in flat do
				if out[stat] ~= nil then
					out[stat] += v
				end
			end
		end
	end
	-- Shrine boosts and timed boosts
	for stat, v in s.boosts do
		if out[stat] ~= nil then
			out[stat] += v
		end
	end
	for _, t in s.temps do
		if out[t.stat] ~= nil then
			out[t.stat] += t.value
		end
	end
	-- Multipliers
	for _, it in s.items do
		local def = Items.Defs[it.id]
		if def and def.mult then
			for stat, m in def.mult do
				if out[stat] ~= nil then
					out[stat] *= m ^ it.count
				end
			end
		end
	end
	-- Caps
	for stat, cap in Grimoires.StatCaps do
		if out[stat] ~= nil and out[stat] > cap then
			out[stat] = cap
		end
	end
	out.MaxHp = math.max(1, math.floor(out.MaxHp + 0.5))
	return out :: any
end

local function metaBonuses(player: Player): { weaponSlots: number, grimoireSlots: number, banish: number, skip: number, reroll: number }
	local d = Cards.DefaultMeta
	local result = { weaponSlots = d.weaponSlots, grimoireSlots = d.grimoireSlots, banish = d.banish, skip = d.skip, reroll = d.reroll }
	local progression = Registry.find("ProgressionService")
	if progression and progression.getMetaBonuses then
		local ok, meta = pcall(progression.getMetaBonuses, player)
		if ok and type(meta) == "table" then
			for key in result do
				local v = (meta :: any)[key]
				if isFiniteNumber(v) then
					(result :: any)[key] = math.max(0, math.floor(v))
				end
			end
		end
	end
	return result
end

local function buildPayload(s: RunState)
	local weapons = table.create(#s.weapons)
	for i, w in s.weapons do
		weapons[i] = { id = w.id, level = w.level }
	end
	local grimoires = table.create(#s.grimoires)
	for i, g in s.grimoires do
		grimoires[i] = { id = g.id, level = g.level }
	end
	local items = table.create(#s.items)
	for i, it in s.items do
		items[i] = { id = it.id, count = it.count }
	end
	return weapons, grimoires, items
end

local function sendBuild(player: Player, s: RunState)
	local weapons, grimoires, items = buildPayload(s)
	buildRemote:FireClient(player, {
		weapons = weapons,
		grimoires = grimoires,
		items = items,
		stats = StatsService.get(player),
		banish = s.banish,
		skip = s.skip,
		reroll = s.reroll,
		weaponSlots = s.weaponSlots,
		grimoireSlots = s.grimoireSlots,
	})
end

local function sendProgress(player: Player, s: RunState)
	progressRemote:FireClient(player, {
		level = s.level,
		xp = s.xp,
		xpNext = Cards.xpToNext(s.level),
	})
end

local function markStats(s: RunState)
	s.statsDirty = true
	s.buildDirty = true
end

-- Public API (cross-domain) ------------------------------------------------------------

-- Final stats. Returns a cached table: read it, never write to it.
function StatsService.get(player: Player): StatBlock
	local s = states[player]
	if not s then
		return baseBlock
	end
	if s.statsDirty then
		s.stats = table.freeze(computeStats(s)) :: any
		s.statsDirty = false
	end
	return s.stats
end

-- Permanent bonus for the rest of the run (shrines, team totem...). `source` is for logs.
function StatsService.addStat(player: Player, stat: string, value: number, source: string)
	local s = states[player]
	if not s or type(stat) ~= "string" or Grimoires.BaseStats[stat] == nil or not isFiniteNumber(value) then
		return
	end
	local _ = source
	s.boosts[stat] = (s.boosts[stat] or 0) + value
	markStats(s)
end

-- `amount` is final: LootService already applied XpGain and the coop share.
function StatsService.addXp(player: Player, amount: number)
	local s = states[player]
	if not s or not isFiniteNumber(amount) or amount <= 0 then
		return
	end
	s.xp += math.min(amount, 1e6)
	s.progressDirty = true
	local gained = false
	while s.level < Cards.Xp.MaxLevel do
		local need = Cards.xpToNext(s.level)
		if s.xp < need then
			break
		end
		s.xp -= need
		s.level += 1
		gained = true
		Bus.PlayerLeveledUp:fire(player, s.level)
	end
	if s.level >= Cards.Xp.MaxLevel then
		s.xp = 0
	end
	if gained then
		markStats(s) -- per-level passives
	end
end

function StatsService.getLevel(player: Player): number
	local s = states[player]
	return if s then s.level else 1
end

function StatsService.getBuild(player: Player): {
	weapons: { { id: string, level: number } },
	grimoires: { { id: string, level: number } },
	items: { { id: string, count: number } },
}
	local s = states[player]
	if not s then
		return { weapons = {}, grimoires = {}, items = {} }
	end
	local weapons, grimoires, items = buildPayload(s)
	return { weapons = weapons, grimoires = grimoires, items = items }
end

function StatsService.grantItem(player: Player, itemId: string)
	local s = states[player]
	if not s or type(itemId) ~= "string" or not Items.Defs[itemId] then
		return
	end
	local count = s.itemCount[itemId]
	if count then
		s.itemCount[itemId] = count + 1
		for _, it in s.items do
			if it.id == itemId then
				it.count += 1
				break
			end
		end
	else
		s.itemCount[itemId] = 1
		table.insert(s.items, { id = itemId, count = 1 })
	end
	markStats(s)
end

-- Nouveau build de run : arme de départ de la classe, emplacements méta, contrôles de tirage.
-- `classId` peut être un id v1 (domaine data) : Config/Classes le résout vers la classe v2.
function StatsService.resetRun(player: Player, classId: string)
	local def = Classes[classId]
	if not def then
		warn(`[StatsService] classe inconnue {classId}, Knight par défaut`)
		def = Classes.Knight
	end
	classId = def.id
	local passive = Weapons.Passives[classId]
	local startWeapon = def.startWeapon
	if not Weapons.Defs[startWeapon] then
		warn(`[StatsService] arme de départ inconnue {startWeapon} pour {classId}`)
		startWeapon = Weapons.Order[1]
	end
	local meta = metaBonuses(player)
	local extraSlots = if passive and passive.extraWeaponSlots then passive.extraWeaponSlots :: number else 0
	local s: RunState = {
		classId = classId,
		level = 1,
		xp = 0,
		weapons = { { id = startWeapon, level = 1, bonus = 0 } },
		grimoires = {},
		items = {},
		itemCount = {},
		boosts = {},
		temps = {},
		banish = meta.banish,
		skip = meta.skip,
		reroll = meta.reroll,
		weaponSlots = math.clamp(meta.weaponSlots + extraSlots, 1, Cards.MaxSlots),
		grimoireSlots = math.clamp(meta.grimoireSlots, 1, Cards.MaxSlots),
		banished = {},
		stats = baseBlock,
		statsDirty = true,
		buildDirty = true,
		progressDirty = true,
		damageByWeapon = {},
	}
	states[player] = s
	local weaponService = Registry.find("WeaponService")
	if weaponService and weaponService.resetPlayer then
		weaponService.resetPlayer(player)
	end
	local passiveService = Registry.find("PassiveService")
	if passiveService and passiveService.resetPlayer then
		passiveService.resetPlayer(player)
	end
end

-- RunSummary.damageByWeapon (read by RunManager). Returns a copy.
function StatsService.getDamageByWeapon(player: Player): { [string]: number }
	local s = states[player]
	if not s then
		return {}
	end
	local out = {}
	for k, v in s.damageByWeapon do
		out[k] = math.floor(v)
	end
	return out
end

-- Domain API (combat only) -------------------------------------------------------------

function StatsService.getState(player: Player): RunState?
	return states[player]
end

function StatsService.getClass(player: Player): string?
	local s = states[player]
	return if s then s.classId else nil
end

function StatsService.getItemCount(player: Player, itemId: string): number
	local s = states[player]
	return if s then s.itemCount[itemId] or 0 else 0
end

function StatsService.getWeaponLevel(player: Player, weaponId: string): number
	local s = states[player]
	if s then
		for _, w in s.weapons do
			if w.id == weaponId then
				return w.level
			end
		end
	end
	return 0
end

function StatsService.getWeaponBonus(player: Player, weaponId: string): number
	local s = states[player]
	if s then
		for _, w in s.weapons do
			if w.id == weaponId then
				return w.bonus
			end
		end
	end
	return 0
end

function StatsService.getGrimoireLevel(player: Player, grimoireId: string): number
	local s = states[player]
	if s then
		for _, g in s.grimoires do
			if g.id == grimoireId then
				return g.level
			end
		end
	end
	return 0
end

-- Adds levels to a weapon (adds it if new and a slot is free). `toLevel` caps the result.
function StatsService.upgradeWeapon(player: Player, weaponId: string, toLevel: number, bonus: number): boolean
	local s = states[player]
	if not s or not Weapons.Defs[weaponId] then
		return false
	end
	toLevel = math.clamp(toLevel, 1, Weapons.FusionLevel)
	for _, w in s.weapons do
		if w.id == weaponId then
			local before = w.level
			w.level = math.max(w.level, toLevel)
			w.bonus += bonus
			s.buildDirty = true
			-- Quest counter for Q_Fusion_* (review finding 13).
			if before < Weapons.FusionLevel and w.level >= Weapons.FusionLevel then
				local prog = Registry.find("ProgressionService")
				if prog and prog.recordStat then
					pcall(prog.recordStat, player, "WeaponsFused", 1)
				end
			end
			return true
		end
	end
	if #s.weapons >= s.weaponSlots then
		return false
	end
	table.insert(s.weapons, { id = weaponId, level = toLevel, bonus = bonus })
	s.buildDirty = true
	return true
end

function StatsService.upgradeGrimoire(player: Player, grimoireId: string, toLevel: number): boolean
	local s = states[player]
	local def = Grimoires.Defs[grimoireId]
	if not s or not def then
		return false
	end
	toLevel = math.clamp(toLevel, 1, def.maxLevel)
	for _, g in s.grimoires do
		if g.id == grimoireId then
			g.level = math.max(g.level, toLevel)
			markStats(s)
			return true
		end
	end
	if #s.grimoires >= s.grimoireSlots then
		return false
	end
	table.insert(s.grimoires, { id = grimoireId, level = toLevel })
	markStats(s)
	return true
end

-- Spends one draw control ("banish" | "skip" | "reroll"). Returns false if none left.
function StatsService.useCharge(player: Player, kind: string): boolean
	local s = states[player]
	if not s then
		return false
	end
	if kind == "banish" and s.banish > 0 then
		s.banish -= 1
	elseif kind == "skip" and s.skip > 0 then
		s.skip -= 1
	elseif kind == "reroll" and s.reroll > 0 then
		s.reroll -= 1
	else
		return false
	end
	s.buildDirty = true
	return true
end

function StatsService.banishId(player: Player, id: string)
	local s = states[player]
	if s then
		s.banished[id] = true
	end
end

function StatsService.addTimedStat(player: Player, stat: string, value: number, seconds: number)
	local s = states[player]
	if not s or Grimoires.BaseStats[stat] == nil or not isFiniteNumber(value) or not isFiniteNumber(seconds) then
		return
	end
	table.insert(s.temps, { stat = stat, value = value, expires = os.clock() + seconds })
	markStats(s)
end

function StatsService.recordDamage(player: Player, key: string, amount: number)
	local s = states[player]
	if s then
		s.damageByWeapon[key] = (s.damageByWeapon[key] or 0) + amount
	end
end

-- Lifecycle -------------------------------------------------------------------------------

function StatsService.init()
	buildRemote = Net.event("Build")
	progressRemote = Net.event("PlayerProgress")
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

function StatsService.start()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < SEND_PERIOD then
			return
		end
		acc = 0
		local now = os.clock()
		for player, s in states do
			-- Expire timed boosts
			for i = #s.temps, 1, -1 do
				if s.temps[i].expires <= now then
					table.remove(s.temps, i)
					markStats(s)
				end
			end
			if s.buildDirty then
				s.buildDirty = false
				sendBuild(player, s)
			end
			if s.progressDirty then
				s.progressDirty = false
				sendProgress(player, s)
			end
		end
	end)
end

return StatsService
