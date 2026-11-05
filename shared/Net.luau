--!strict
-- The one list of remotes (doc 12.3). The server creates them; clients wait for them.
-- Server boot: Net.create() -> every service init() -> Net.publish() -> every service start().
-- Payload formats: docs/ARCHITECTURE.md section 6. A domain may add internal remotes in its own
-- shared/NetDefs/<Domain>.luau (returns { [name]: class }); names must be unique.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

type RemoteClass = "RemoteEvent" | "UnreliableRemoteEvent"

local FOLDER_NAME = "Remotes"

local DEFINITIONS: { [string]: RemoteClass } = {
	-- run domain (EnemyService, RunManager, BossService)
	EnemySnapshot = "UnreliableRemoteEvent",
	RunState = "RemoteEvent",
	Announce = "RemoteEvent",
	PlayerVitals = "RemoteEvent",
	RunSummary = "RemoteEvent",
	Replay = "RemoteEvent", -- client -> server
	BossState = "RemoteEvent",
	-- combat domain
	PlayerProgress = "RemoteEvent",
	Build = "RemoteEvent",
	CardOffer = "RemoteEvent",
	CardChoice = "RemoteEvent", -- client -> server
	WeaponFx = "UnreliableRemoteEvent",
	-- loot domain
	LootSnapshot = "UnreliableRemoteEvent",
	Coins = "RemoteEvent",
	ShrineState = "RemoteEvent",
	ShrineOffer = "RemoteEvent",
	ShrineChoice = "RemoteEvent", -- client -> server
	-- companion domain
	CompanionState = "RemoteEvent",
	CompanionSnapshot = "UnreliableRemoteEvent",
	CompanionUltimate = "RemoteEvent", -- client -> server
	-- ui domain
	Ping = "RemoteEvent", -- client -> server
	PingBroadcast = "RemoteEvent",
	-- data domain
	Profile = "RemoteEvent",
	SelectLoadout = "RemoteEvent", -- client -> server
	EquipCosmetic = "RemoteEvent", -- client -> server
	UpdateSettings = "RemoteEvent", -- client -> server
}

-- Merge per-domain extras from shared/NetDefs.
local netDefs = script.Parent:FindFirstChild("NetDefs")
if netDefs then
	for _, module in netDefs:GetChildren() do
		if module:IsA("ModuleScript") then
			local extra = (require :: any)(module) :: { [string]: RemoteClass }
			for name, class in extra do
				assert(DEFINITIONS[name] == nil, `Remote "{name}" defined twice ({module.Name})`)
				DEFINITIONS[name] = class
			end
		end
	end
end

local Net = {}

local serverFolder: Folder? = nil
-- Remotes qui ont un handler serveur (Net.onServerEvent). Les autres reçoivent un écouteur
-- « puits » au publish (audit S-11).
local handled: { [string]: true } = {}
-- Appels client -> serveur sur un remote serveur -> client, par joueur (S-11). Un client normal
-- n'en fait jamais : un compte > 0 signale un client modifié.
local strayCalls: { [Player]: number } = {}
local STRAY_WARN_AT = 20

function Net.create()
	assert(RunService:IsServer(), "Net.create is server-only")
	assert(serverFolder == nil, "Net.create called twice")
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	for name, class in DEFINITIONS do
		local remote = Instance.new(class :: any)
		remote.Name = name
		remote.Parent = folder
	end
	serverFolder = folder
end

-- Parent the folder only after every service has wired its handlers.
-- S-11 : chaque remote sans handler reçoit un écouteur qui jette l'appel et le compte, pour que
-- Roblox ne mette pas les appels en file et qu'on repère les clients modifiés.
function Net.publish()
	assert(serverFolder, "Net.create must run first")
	for _, remote in serverFolder:GetChildren() do
		if not handled[remote.Name] and (remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent")) then
			local name = remote.Name;
			(remote :: any).OnServerEvent:Connect(function(player: Player)
				if handled[name] then
					return -- handler branché après publish (start()) : appel légitime
				end
				local n = (strayCalls[player] or 0) + 1
				strayCalls[player] = n
				if n == STRAY_WARN_AT then
					warn(`[Net] {player.UserId} : {n} appels sur des remotes serveur -> client (dernier : {name})`)
				end
			end)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		strayCalls[player] = nil
	end)
	serverFolder.Parent = ReplicatedStorage
end

-- Appels d'un joueur sur des remotes serveur -> client (S-11 ; signal possible pour la quarantaine).
function Net.getStrayCalls(player: Player): number
	return strayCalls[player] or 0
end

local function get(name: string): Instance
	assert(DEFINITIONS[name], `Unknown remote "{name}"`)
	if RunService:IsServer() then
		assert(serverFolder, "Net.create must run first")
		local remote = serverFolder:FindFirstChild(name)
		assert(remote, `Remote "{name}" missing`)
		return remote
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME):WaitForChild(name)
end

function Net.event(name: string): RemoteEvent
	return get(name) :: RemoteEvent
end

function Net.unreliable(name: string): UnreliableRemoteEvent
	return get(name) :: UnreliableRemoteEvent
end

-- Rate-limited server handler (token bucket per player). The handler still has to
-- check the type and range of every argument: the only trusted value is `player`.
function Net.onServerEvent(name: string, perSecond: number, handler: (player: Player, ...any) -> ())
	local remote = Net.event(name)
	handled[name] = true
	local buckets: { [Player]: { tokens: number, last: number } } = {}
	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)
	remote.OnServerEvent:Connect(function(player, ...)
		local now = os.clock()
		local bucket = buckets[player]
		if not bucket then
			bucket = { tokens = perSecond, last = now }
			buckets[player] = bucket
		end
		bucket.tokens = math.min(perSecond, bucket.tokens + (now - bucket.last) * perSecond)
		bucket.last = now
		if bucket.tokens < 1 then
			return
		end
		bucket.tokens -= 1
		handler(player, ...)
	end)
end

return Net
