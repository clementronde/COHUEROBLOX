--!strict
-- Visual clips sampled by the client renderers. Distances are in studs, angles in degrees.
-- The root pose works with both rigid meshes and the block-built fallback models.
type Walk = { stride: number, lift: number, sway: number, pitch: number, roll: number, float: number? }
type Attack = { recoil: number, reach: number, lift: number, tilt: number, twist: number }
export type Profile = { walk: Walk, attack: Attack, color: Color3, debris: string, style: string }

local function clip(walk: Walk, attack: Attack, color: Color3, debris: string, style: string): Profile
	return { walk = walk, attack = attack, color = color, debris = debris, style = style }
end

local rgb = Color3.fromRGB
local profiles: { [string]: Profile } = {
	GlandGrincheux = clip({ stride = 2.9, lift = .18, sway = .15, pitch = 8, roll = 11 },
		{ recoil = .22, reach = .56, lift = .10, tilt = -26, twist = 11 }, rgb(240, 165, 76), "Ball", "sweep"),
	ChampignonSauteur = clip({ stride = 4.1, lift = .52, sway = .06, pitch = 14, roll = 7 },
		{ recoil = .42, reach = .12, lift = .28, tilt = -21, twist = 7 }, rgb(255, 123, 124), "Ball", "burst"),
	HibouPlongeur = clip({ stride = 5.7, lift = .26, sway = .15, pitch = 5, roll = 13, float = .25 },
		{ recoil = .36, reach = .30, lift = .32, tilt = -24, twist = -12 }, rgb(211, 158, 255), "Wedge", "shot"),
	BogueBlindee = clip({ stride = 3.8, lift = .09, sway = .12, pitch = 10, roll = 7 },
		{ recoil = .36, reach = .72, lift = .04, tilt = -35, twist = 0 }, rgb(174, 225, 86), "Wedge", "burst"),
	MomiePQ = clip({ stride = 3.4, lift = .11, sway = .28, pitch = 4, roll = 15 },
		{ recoil = .20, reach = .52, lift = .18, tilt = -14, twist = -23 }, rgb(252, 230, 188), "Block", "sweep"),
	CactusCoureur = clip({ stride = 3.9, lift = .30, sway = .12, pitch = 17, roll = 5 },
		{ recoil = .46, reach = .20, lift = .18, tilt = -34, twist = -16 }, rgb(175, 255, 120), "Wedge", "burst"),
	VautourCaillou = clip({ stride = 6.2, lift = .19, sway = .23, pitch = 9, roll = 17, float = .32 },
		{ recoil = .46, reach = .42, lift = .20, tilt = -29, twist = 13 }, rgb(225, 179, 122), "Ball", "shot"),
	ScarabeeBlinde = clip({ stride = 2.3, lift = .07, sway = .10, pitch = 3, roll = 5 },
		{ recoil = .30, reach = .64, lift = .05, tilt = -16, twist = 16 }, rgb(92, 214, 251), "Wedge", "sweep"),
	CraieVivante = clip({ stride = 3.1, lift = .36, sway = .16, pitch = 12, roll = 18 },
		{ recoil = .22, reach = .54, lift = .34, tilt = -38, twist = 10 }, rgb(195, 229, 255), "Block", "burst"),
	CartableMordeur = clip({ stride = 4.6, lift = .36, sway = .07, pitch = 17, roll = 10 },
		{ recoil = .52, reach = .20, lift = .33, tilt = -39, twist = -7 }, rgb(255, 114, 195), "Wedge", "sweep"),
	SurveillantFantome = clip({ stride = 4.4, lift = .11, sway = .16, pitch = 3, roll = 6, float = .12 },
		{ recoil = .28, reach = .27, lift = .24, tilt = -12, twist = 13 }, rgb(131, 238, 255), "Ball", "shot"),
	CasierArmoire = clip({ stride = 4.6, lift = .17, sway = .17, pitch = 4, roll = 8 },
		{ recoil = .43, reach = .76, lift = .05, tilt = -25, twist = -21 }, rgb(123, 182, 242), "Block", "burst"),
	SoucheGeante = clip({ stride = 5.8, lift = .25, sway = .34, pitch = 8, roll = 8 },
		{ recoil = .58, reach = .75, lift = .40, tilt = -28, twist = 8 }, rgb(161, 232, 92), "Block", "burst"),
	ChameauTirelire = clip({ stride = 5.2, lift = .38, sway = .25, pitch = 10, roll = 6 },
		{ recoil = .65, reach = .86, lift = .58, tilt = -21, twist = -12 }, rgb(255, 211, 86), "Cylinder", "sweep"),
	PionSpectral = clip({ stride = 8, lift = .19, sway = .38, pitch = 3, roll = 8, float = .47 },
		{ recoil = .51, reach = .72, lift = .63, tilt = -17, twist = 30 }, rgb(165, 163, 255), "Wedge", "sweep"),
	Zombie = clip({ stride = 2.6, lift = .10, sway = .16, pitch = 4, roll = 6 },
		{ recoil = .28, reach = .51, lift = .07, tilt = -19, twist = -9 }, rgb(141, 216, 94), "Block", "burst"),
	Gobelin = clip({ stride = 3.4, lift = .17, sway = .08, pitch = 5, roll = 4 },
		{ recoil = .32, reach = .65, lift = .19, tilt = -23, twist = 24 }, rgb(255, 174, 65), "Wedge", "sweep"),
	GrandCheneRonchon = clip({ stride = 4.5, lift = .42, sway = .45, pitch = 4, roll = 4 },
		{ recoil = 1.1, reach = 1.40, lift = .70, tilt = -17, twist = 8 }, rgb(163, 245, 104), "Block", "burst"),
	PharaonGrillePain = clip({ stride = 4.8, lift = .39, sway = .25, pitch = 7, roll = 7 },
		{ recoil = .95, reach = 1.65, lift = .50, tilt = -20, twist = -9 }, rgb(255, 170, 62), "Block", "shot"),
	DirectriceEternelle = clip({ stride = 6.4, lift = .22, sway = .45, pitch = 5, roll = 5, float = .28 },
		{ recoil = .95, reach = 1.45, lift = .57, tilt = -14, twist = 23 }, rgb(160, 236, 255), "Wedge", "sweep"),
	Golem = clip({ stride = 4.9, lift = .17, sway = .12, pitch = 4, roll = 5 },
		{ recoil = .23, reach = .36, lift = .1, tilt = -15, twist = 2 }, rgb(173, 218, 109), "Block", "burst"),
	GrandBrouhaha = clip({ stride = 5.6, lift = .83, sway = .34, pitch = 7, roll = 10 },
		{ recoil = 1.20, reach = 1.75, lift = .92, tilt = -22, twist = -17 }, rgb(255, 136, 73), "Ball", "burst"),
}

local Motion = {}
Motion.profiles = profiles

local function pose(x: number, y: number, z: number, pitch: number, yaw: number, roll: number): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(math.rad(pitch), math.rad(yaw), math.rad(roll))
end

function Motion.walk(profile: Profile, distance: number, strength: number, now: number, scale: number): (CFrame, number)
	local w = profile.walk
	local step = distance * (math.pi * 2 / w.stride)
	local side = math.sin(step) * strength
	local beat = (1 - math.cos(step * 2)) * .5 * strength
	local float = (w.float or 0) * (.75 + math.sin(now * 3.4) * .25)
	return pose(w.sway * side * scale, (beat * w.lift + float) * scale, 0,
		w.pitch * (beat - strength * .25), 0, w.roll * side), side
end

function Motion.charge(profile: Profile, u: number, scale: number): CFrame
	local p = profile.attack
	local ready = u * u * (3 - 2 * u)
	return pose(0, -p.lift * ready * .45 * scale, p.recoil * ready * scale,
		-p.tilt * .48 * ready, -p.twist * .58 * ready, 0)
end

function Motion.strike(profile: Profile, t: number, scale: number): CFrame
	local p = profile.attack
	local punch = if t < .14 then math.sin(t / .14 * math.pi * .5) else math.max(0, 1 - (t - .14) / .86) ^ 2
	return pose(0, p.lift * punch * scale, -p.reach * punch * scale,
		p.tilt * punch, p.twist * punch, -p.twist * .20 * punch)
end

function Motion.air(profile: Profile, u: number, scale: number, height: number?): CFrame
	local p = profile.attack
	local arc = math.sin(math.pi * u)
	return pose(0, arc * (height or 7), 0, (8 + p.tilt * u) * arc, p.twist * arc * scale, 0)
end

return Motion
