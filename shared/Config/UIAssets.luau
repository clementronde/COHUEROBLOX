--!strict
-- Image ids of the v3 « vraies briques » UI (A08). Filled after the upload to Roblox (Studio,
-- upload_image on Clément's account); an empty string means "not uploaded yet" (the image stays
-- blank and the slot shows its initials).
-- Sources: docs/dossier/ui-assets/stud_tile_128.png and docs/dossier/ui-assets/icons/png/*.png.

local UIAssets = {}

UIAssets.Studs = "rbxassetid://127104067904758" -- 128 px tile, 2 x 2 studs, shown at 12 px per stud (TileSize 24 x 24)

UIAssets.Icons = {
	hp = "rbxassetid://109154522336200",
	coin = "rbxassetid://117531663059457",
	ko = "rbxassetid://103936025813811",
	timer = "rbxassetid://129968413209851",
	jump = "rbxassetid://80406411390583",
	slide = "rbxassetid://92786161464955",
	ping = "rbxassetid://134326836591126",
	capture_light = "rbxassetid://123963112261993",
	settings_light = "rbxassetid://131744361283528",
	lock = "rbxassetid://128011070958863",
	trophy = "rbxassetid://81133641478562",
	chest = "rbxassetid://134446381511588",
	flame = "rbxassetid://118310271758424",
	oak = "rbxassetid://86132696269873",
	exclaim = "rbxassetid://96346621009618",
	gem = "rbxassetid://135433100758411",
	sword = "rbxassetid://87831803675130",
	lightning = "rbxassetid://115944684309260",
	firestaff = "rbxassetid://117398619165505",
	axes = "rbxassetid://130978701370272",
	rune_damage = "rbxassetid://76956839751832",
	rune_area = "rbxassetid://109451588987178",
	rune_speed = "rbxassetid://75303906598413",
	sock = "rbxassetid://111804209933320",
	lunchbox = "rbxassetid://113495601008405",
	chalk = "rbxassetid://136864794726390",
	anvil = "rbxassetid://110871983854914",
	backpack = "rbxassetid://81471990140118",
	helm = "rbxassetid://72881695163649",
	coinbag = "rbxassetid://129634091163689",
	scroll = "rbxassetid://92879188401233",
	ticket = "rbxassetid://104371383449511",
	acorn = "rbxassetid://92760650156661",
	-- Armes en pixel art extrudé d'A14 (branche claude/a14-armes-5c1460, porte 2 pas encore validée).
	weapon_Broadsword = "rbxassetid://116914634788746",
	weapon_Longbow = "rbxassetid://116851472101165",
	weapon_FireStaff = "rbxassetid://116343240355149",
	weapon_BombBag = "rbxassetid://117724855752377",
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
