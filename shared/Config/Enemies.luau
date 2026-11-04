--!strict
-- Enemy definitions. Kind ids must stay in 1..31 (packed into 5 bits on the wire).

local Types = require(script.Parent.Parent.Types)

local Enemies: { [number]: Types.EnemyDef } = {
	[1] = {
		id = 1,
		name = "GlandGrincheux", -- swarm (doc 9.1)
		hp = 10,
		speed = 10,
		radius = 1.2,
		height = 2.4,
		color = Color3.fromRGB(150, 105, 60),
	},
	[2] = {
		id = 2,
		name = "ChampignonSauteur",
		hp = 18,
		speed = 8,
		radius = 1.4,
		height = 2.8,
		color = Color3.fromRGB(200, 60, 60),
	},
}

return Enemies
