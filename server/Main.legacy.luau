--!strict
-- Single server entry point. Two-phase boot: register + init (no yielding) for all, then start.
-- Services find each other through Registry.get("Name") inside functions, never at require time.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Registry = require(Shared:WaitForChild("Registry"))
local Types = require(Shared:WaitForChild("Types"))

local Services = script.Parent:WaitForChild("Services")

-- Fixed order (docs/ARCHITECTURE.md section 2). Missing services are skipped with a warning.
local ORDER = {
	"DataService",
	"ProgressionService",
	"MonetizationService",
	"StatsService",
	"RunManager",
	"StageService",
	"EnemyService",
	"BossService",
	"LootService",
	"ShrineService",
	"CompanionService",
	"CardService",
	"WeaponService",
	"PassiveService",
	"TraitService",
	"MovementGuard",
	"PingService",
	"MatchService",
}

Net.create()

local systems: { { name: string, system: Types.System } } = {}
for _, name in ORDER do
	local moduleScript = Services:FindFirstChild(name, true)
	if not moduleScript or not moduleScript:IsA("ModuleScript") then
		warn(`[Server] missing service {name}`)
		continue
	end
	local ok, result = pcall(require, moduleScript)
	if ok then
		Registry.register(name, result)
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
