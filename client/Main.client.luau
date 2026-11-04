--!strict
-- Single client entry point. Same two-phase boot as the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))

local Controllers = script.Parent:WaitForChild("Controllers")

local ORDER = {
	"EnemyRenderer",
	"DebugHud",
}

local systems: { { name: string, system: Types.System } } = {}
for _, name in ORDER do
	local moduleScript = Controllers:FindFirstChild(name)
	if not moduleScript or not moduleScript:IsA("ModuleScript") then
		warn(`[Client] missing controller {name}`)
		continue
	end
	local ok, result = pcall(require, moduleScript)
	if ok then
		table.insert(systems, { name = name, system = result :: Types.System })
	else
		warn(`[Client] require {name} failed: {result}`)
	end
end

for _, entry in systems do
	local init = entry.system.init
	if init then
		local ok, err = pcall(init)
		if not ok then
			warn(`[Client] {entry.name}.init failed: {err}`)
		end
	end
end

for _, entry in systems do
	local start = entry.system.start
	if start then
		task.spawn(start)
	end
end
