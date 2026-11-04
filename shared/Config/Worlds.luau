--!strict
-- Worlds (docs/dossier/20-run-mondes-boss.md section 3). Ids: ARCHITECTURE.md section 3.
-- Layout numbers drive Heightmap.generateLayout (shared, deterministic) and StageService (parts).

local Types = require(script.Parent.Parent.Types)

export type Hazard = {
	id: "Fog" | "Sandstorm" | "Blackout",
	label: Types.LocalizedText,
	firstAt: number, -- seconds since stage start
	every: number,
	duration: number,
	warn: number, -- announce this many seconds before
	viewDistance: number?,
	pushSpeed: number?, -- studs/s (Sandstorm)
	revealRadius: number?, -- Blackout: enemies visible this close to a player
	lampRadius: number?,
}

export type World = {
	id: string,
	name: Types.LocalizedText,
	size: number, -- square side, centred on the origin
	roster: { Swarm: number, Jumper: number, Shooter: number, Armored: number },
	swarmVariant: number?,
	armoredVariant: number?,
	miniBoss: number,
	boss: string, -- Bosses id (stage 1 and Enraged stage 2)
	finalBoss: string, -- stage 3 of Tier 3
	hazard: Hazard,
	unlock: { kind: "Free" | "TrialShrines" | "ClearTier", count: number?, world: string?, tier: number? },
	-- Layout
	plateaus: number,
	plateauHeight: { number }, -- min, max
	plateauSize: { number },
	hills: number,
	cliffs: number, -- plateaus with no ramp, reached by a jump pad
	decor: number, -- trees / ruins / props
	lamps: number,
	-- Palette
	ground: { Color3 },
	groundMaterial: Enum.Material,
	cliff: Color3,
	top: Color3,
	ramp: Color3,
	decorA: Color3,
	decorB: Color3,
	projectile: Color3,
	sky: { ambient: Color3, fog: Color3, clock: number },
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local Worlds: { [string]: World } = {
	BoisGrognon = {
		id = "BoisGrognon",
		name = { en = "Grumpy Woods", fr = "Grumpy Woods" },
		size = 560,
		roster = { Swarm = 1, Jumper = 2, Shooter = 3, Armored = 4 },
		swarmVariant = 21,
		armoredVariant = 22,
		miniBoss = 13,
		boss = "GrandCheneRonchon",
		finalBoss = "GrandBrouhaha",
		hazard = {
			id = "Fog",
			label = { en = "Fog rolls in!", fr = "Fog rolls in!" },
			firstAt = 90,
			every = 100,
			duration = 30,
			warn = 3,
			viewDistance = 55,
		},
		unlock = { kind = "Free" },
		plateaus = 14,
		plateauHeight = { 6, 16 },
		plateauSize = { 24, 56 },
		hills = 4,
		cliffs = 3,
		decor = 70,
		lamps = 0,
		ground = { rgb(110, 175, 70), rgb(98, 160, 62) },
		groundMaterial = Enum.Material.Grass,
		cliff = rgb(125, 100, 75),
		top = rgb(120, 190, 80),
		ramp = rgb(150, 120, 85),
		decorA = rgb(60, 140, 60),
		decorB = rgb(110, 80, 50),
		projectile = rgb(255, 120, 40),
		sky = { ambient = rgb(120, 130, 110), fog = rgb(200, 215, 200), clock = 14 },
	},
	DunesCroustillantes = {
		id = "DunesCroustillantes",
		name = { en = "Crunchy Dunes", fr = "Crunchy Dunes" },
		size = 640,
		roster = { Swarm = 5, Jumper = 6, Shooter = 7, Armored = 8 },
		miniBoss = 14,
		boss = "PharaonGrillePain",
		finalBoss = "GrandBrouhaha",
		hazard = {
			id = "Sandstorm",
			label = { en = "Sandstorm!", fr = "Sandstorm!" },
			firstAt = 120,
			every = 120,
			duration = 20,
			warn = 3,
			viewDistance = 90,
			pushSpeed = 6,
		},
		unlock = { kind = "TrialShrines", count = 10 },
		plateaus = 12,
		plateauHeight = { 4, 10 },
		plateauSize = { 30, 64 },
		hills = 3,
		cliffs = 2,
		decor = 55,
		lamps = 0,
		ground = { rgb(232, 200, 140), rgb(222, 188, 128) },
		groundMaterial = Enum.Material.Sand,
		cliff = rgb(200, 150, 95),
		top = rgb(238, 210, 150),
		ramp = rgb(215, 175, 115),
		decorA = rgb(190, 160, 120),
		decorB = rgb(80, 160, 70),
		projectile = rgb(255, 60, 200),
		sky = { ambient = rgb(150, 130, 100), fog = rgb(230, 200, 150), clock = 13 },
	},
	RecreFantome = {
		id = "RecreFantome",
		name = { en = "Haunted Recess", fr = "Haunted Recess" },
		size = 520,
		roster = { Swarm = 9, Jumper = 10, Shooter = 11, Armored = 12 },
		swarmVariant = 20,
		miniBoss = 15,
		boss = "DirectriceEternelle",
		finalBoss = "GrandBrouhaha",
		hazard = {
			id = "Blackout",
			label = { en = "Power cut!", fr = "Power cut!" },
			firstAt = 150,
			every = 110,
			duration = 20,
			warn = 3,
			revealRadius = 20,
			lampRadius = 22,
		},
		unlock = { kind = "ClearTier", world = "DunesCroustillantes", tier = 2 },
		plateaus = 12,
		plateauHeight = { 8, 14 },
		plateauSize = { 24, 48 },
		hills = 2,
		cliffs = 3,
		decor = 50,
		lamps = 12,
		ground = { rgb(90, 90, 105), rgb(82, 82, 98) },
		groundMaterial = Enum.Material.Asphalt,
		cliff = rgb(150, 110, 90),
		top = rgb(170, 70, 60),
		ramp = rgb(120, 120, 135),
		decorA = rgb(230, 200, 80),
		decorB = rgb(60, 120, 200),
		projectile = rgb(80, 255, 140),
		sky = { ambient = rgb(70, 75, 110), fog = rgb(40, 45, 70), clock = 21 },
	},
}

return Worlds
