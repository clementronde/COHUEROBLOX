--!strict
-- Single client entry point. Same two-phase boot as the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Registry = require(Shared:WaitForChild("Registry"))
local Types = require(Shared:WaitForChild("Types"))

local Controllers = script.Parent:WaitForChild("Controllers")

-- Fixed order (docs/ARCHITECTURE.md section 2). Searched recursively under Controllers.
local ORDER = {
	"CameraController",
	"InputController",
	"MovementController",
	"EnemyRenderer",
	"BossRenderer",
	"WeaponFX",
	"LootRenderer",
	"ShrineFX",
	"CompanionRenderer",
	"UITheme",
	"HUD",
	"CardUI",
	"ShrineUI",
	"Minimap",
	"PingUI",
	"MobileButtons",
	"LoadoutUI",
	"EndScreen",
	"SettingsUI",
	"SoundController",
	"WorldTransition",
	"DebugHud",
}

local systems: { { name: string, system: Types.System } } = {}
for _, name in ORDER do
	local moduleScript = Controllers:FindFirstChild(name, true)
	if not moduleScript or not moduleScript:IsA("ModuleScript") then
		warn(`[Client] missing controller {name}`)
		continue
	end
	local ok, result = pcall(require, moduleScript)
	if ok then
		Registry.register(name, result)
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
