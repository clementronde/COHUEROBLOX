--!strict
-- Single server entry point. Two-phase boot: init (no yielding) for all, then start.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Types = require(Shared:WaitForChild("Types"))

local Services = script.Parent:WaitForChild("Services")

-- Fixed order. Add services here as they are written (WeaponService, LootService, ...).
local ORDER = {
	"EnemyService",
}

Net.create()

local systems: { { name: string, system: Types.System } } = {}
for _, name in ORDER do
	local moduleScript = Services:FindFirstChild(name)
	if not moduleScript or not moduleScript:IsA("ModuleScript") then
		warn(`[Server] missing service {name}`)
		continue
	end
	local ok, result = pcall(require, moduleScript)
	if ok then
		table.insert(systems, { name = name, system = result :: Types.System })
	else
		warn(`[Server] require {name} failed: {result}`)
	end
end

for _, entry in systems do
	local init = entry.system.init
	if init then
		local ok, err = pcall(init)
		if not ok then
			warn(`[Server] {entry.name}.init failed: {err}`)
		end
	end
end

Net.publish()

for _, entry in systems do
	local start = entry.system.start
	if start then
		task.spawn(start)
	end
end
