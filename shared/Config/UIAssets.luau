--!strict
-- Image ids of the v3 « vraies briques » UI (A08). Filled after the upload to Roblox (Studio,
-- upload_image on Clément's account); an empty string means "not uploaded yet" (the image stays
-- blank and the slot shows its initials).
-- Sources: docs/dossier/ui-assets/stud_tile_128.png and docs/dossier/ui-assets/icons/png/*.png.

local UIAssets = {}

UIAssets.Studs = "" -- 128 px tile, 2 x 2 studs, shown at 12 px per stud (TileSize 24 x 24)

UIAssets.Icons = {
	hp = "",
	coin = "",
	ko = "",
	timer = "",
	jump = "",
	slide = "",
	ping = "",
	capture_light = "",
	settings_light = "",
	lock = "",
	trophy = "",
	chest = "",
	flame = "",
	oak = "",
	exclaim = "",
	gem = "",
	sword = "",
	lightning = "",
	firestaff = "",
	axes = "",
	rune_damage = "",
	rune_area = "",
	rune_speed = "",
	sock = "",
	lunchbox = "",
	chalk = "",
	anvil = "",
	backpack = "",
	helm = "",
	coinbag = "",
	scroll = "",
	ticket = "",
	acorn = "",
	-- Armes en pixel art extrudé d'A14 (branche claude/a14-armes-5c1460, porte 2 pas encore validée).
	weapon_Broadsword = "",
	weapon_Longbow = "",
	weapon_FireStaff = "",
	weapon_BombBag = "",
}

-- Weapon / Rune / item ids (Config.Weapons, Config.Grimoires, Config.Items) -> icon key above.
-- A14 will deliver the extruded pixel-art weapon sprites; they replace these entries.
UIAssets.ById = {
	Broadsword = "weapon_Broadsword",
	Longbow = "weapon_Longbow",
	FireStaff = "weapon_FireStaff",
	BombBag = "weapon_BombBag",
	LightningChain = "lightning",
	SpinningAxes = "axes",
	Damage = "rune_damage",
	Area = "rune_area",
	AttackSpeed = "rune_speed",
	LuckySock = "sock",
	LunchBox = "lunchbox",
	ChalkStick = "chalk",
}

function UIAssets.icon(key: string?): string
	if not key then
		return ""
	end
	local direct = (UIAssets.Icons :: any)[key]
	if type(direct) == "string" then
		return direct
	end
	local mapped = (UIAssets.ById :: any)[key]
	return if type(mapped) == "string" then ((UIAssets.Icons :: any)[mapped] or "") else ""
end

return UIAssets
