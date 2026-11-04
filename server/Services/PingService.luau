--!strict
-- Team pings (ui domain). Design: docs/dossier/60-ui-ux.md section 7.3.
-- Ping (C->S): (kind: string, position: Vector3). Validated, rate limited, then broadcast as
-- PingBroadcast { userId, kind, position } to the players of the sender's run.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Registry = require(Shared:WaitForChild("Registry"))
local UIConfig = require(Shared:WaitForChild("Config"):WaitForChild("UI"))

local PC = UIConfig.Ping
local MAX_COORD = 100000

local PingService = {}

local validKinds: { [string]: boolean } = {}
for _, kind in PC.Kinds do
	validKinds[kind] = true
end

-- Sliding window per player on top of Net's token bucket.
local history: { [Player]: { number } } = {}

local function finite(n: number): boolean
	return n == n and math.abs(n) < MAX_COORD
end

local function allowed(player: Player): boolean
	local now = os.clock()
	local list = history[player]
	if not list then
		list = {}
		history[player] = list
	end
	local i = 1
	while i <= #list do
		if now - list[i] > PC.WindowSeconds then
			table.remove(list, i)
		else
			i += 1
		end
	end
	if #list >= PC.WindowMax then
		return false
	end
	table.insert(list, now)
	return true
end

local function recipients(sender: Player): { Player }
	local runManager = Registry.find("RunManager")
	if runManager and type(runManager.getRunPlayers) == "function" then
		local ok, list = pcall(runManager.getRunPlayers)
		if ok and type(list) == "table" and table.find(list, sender) then
			return list
		end
	end
	return Players:GetPlayers() -- single-place test mode / not in a run
end

local function onPing(player: Player, kind: any, position: any)
	if type(kind) ~= "string" or not validKinds[kind] then
		return
	end
	if typeof(position) ~= "Vector3" then
		return
	end
	local pos = position :: Vector3
	if not (finite(pos.X) and finite(pos.Y) and finite(pos.Z)) then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	if (pos - root.Position).Magnitude > PC.MaxRange then
		return
	end
	if not allowed(player) then
		return
	end
	local prog = Registry.find("ProgressionService")
	if prog and prog.recordStat then
		pcall(prog.recordStat, player, "PingsSent", 1) -- review finding 13
	end
	local payload = { userId = player.UserId, kind = kind, position = pos }
	local remote = Net.event("PingBroadcast")
	for _, target in recipients(player) do
		if target.Parent == Players then
			remote:FireClient(target, payload)
		end
	end
end

function PingService.init()
	Net.onServerEvent("Ping", PC.PerSecond, onPing)
	Players.PlayerRemoving:Connect(function(player)
		history[player] = nil
	end)
end

return PingService
