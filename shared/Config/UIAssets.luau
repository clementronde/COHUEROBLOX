--!strict
-- Image ids of the v3 « vraies briques » UI (A08). Filled after the upload to Roblox (Studio,
-- upload_image on Clément's account); an empty string means "not uploaded yet" (the image stays
-- blank and the slot shows its initials).
-- Sources: docs/dossier/ui-assets/stud_tile_128.png and docs/dossier/ui-assets/icons/png/*.png.

local UIAssets = {}

UIAssets.Studs = "rbxassetid://127104067904758" -- 128 px tile, 2 x 2 studs, shown at 12 px per stud (TileSize 24 x 24)
UIAssets.Rays = "rbxassetid://101399456269039" -- docs/dossier/ui-assets/rays_512.png, sunburst behind the level-up window

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
	-- Armes en pixel art extrudé d'A14 (rendus docs/dossier/ui-assets/icons/weapons, contour A08).
	weapon_Broadsword = "rbxassetid://116914634788746",
	weapon_Longbow = "rbxassetid://116851472101165",
	weapon_FireStaff = "rbxassetid://116343240355149",
	weapon_BombBag = "rbxassetid://117724855752377",
	weapon_QuakeHammer = "rbxassetid://129279069512511",
	weapon_ThrowingDaggers = "rbxassetid://105200331865137",
	weapon_HolyAura = "rbxassetid://82274387370203",
	weapon_SpinningAxes = "rbxassetid://122741203835922",
	weapon_BeastWhip = "rbxassetid://139472413123738",
	weapon_LightningChain = "rbxassetid://131663047427967",
	weapon_FrostNova = "rbxassetid://93056821140647",
	weapon_Boomerang = "rbxassetid://124613776554214",
	weapon_SpearThrow = "rbxassetid://88775812801691",
	weapon_MeteorRain = "rbxassetid://93724733188322",
	weapon_OrbitingBlades = "rbxassetid://124547350401041",
	weapon_CrossbowTurret = "rbxassetid://75320981221089",
	-- Fusions (niveau 9, Weapons.FusionEnabled = false pour l'instant).
	weapon_AxeTornado = "rbxassetid://106537661846080",
	weapon_BlizzardGlobe = "rbxassetid://133962426450727",
	weapon_BuzzsawHalo = "rbxassetid://82154291157130",
	weapon_ClusterSack = "rbxassetid://109566099195331",
	weapon_ComebackRang = "rbxassetid://120288042444451",
	weapon_CometJavelin = "rbxassetid://98519935251644",
	weapon_DaggerFlurry = "rbxassetid://137597887905191",
	weapon_GrandChime = "rbxassetid://112399129063993",
	weapon_MountainMaul = "rbxassetid://135591239252265",
	weapon_RingmasterLash = "rbxassetid://129888085097790",
	weapon_RoyalGreatsword = "rbxassetid://120218457717883",
	weapon_SiegeBallista = "rbxassetid://70901096484700",
	weapon_StarShower = "rbxassetid://113222065948695",
	weapon_StormBow = "rbxassetid://131299802249571",
	weapon_SunStaff = "rbxassetid://125245020039626",
	weapon_ThunderWeb = "rbxassetid://78221736684231",
}

-- Weapon / Rune / item ids (Config.Weapons, Config.Grimoires, Config.Items) -> icon key above.
-- Every weapon and fusion uses A14's extruded pixel-art sprite.
UIAssets.ById = {
	Broadsword = "weapon_Broadsword",
	Longbow = "weapon_Longbow",
	FireStaff = "weapon_FireStaff",
	QuakeHammer = "weapon_QuakeHammer",
	ThrowingDaggers = "weapon_ThrowingDaggers",
	HolyAura = "weapon_HolyAura",
	SpinningAxes = "weapon_SpinningAxes",
	BeastWhip = "weapon_BeastWhip",
	LightningChain = "weapon_LightningChain",
	FrostNova = "weapon_FrostNova",
	Boomerang = "weapon_Boomerang",
	BombBag = "weapon_BombBag",
	SpearThrow = "weapon_SpearThrow",
	MeteorRain = "weapon_MeteorRain",
	OrbitingBlades = "weapon_OrbitingBlades",
	CrossbowTurret = "weapon_CrossbowTurret",
	AxeTornado = "weapon_AxeTornado",
	BlizzardGlobe = "weapon_BlizzardGlobe",
	BuzzsawHalo = "weapon_BuzzsawHalo",
	ClusterSack = "weapon_ClusterSack",
	ComebackRang = "weapon_ComebackRang",
	CometJavelin = "weapon_CometJavelin",
	DaggerFlurry = "weapon_DaggerFlurry",
	GrandChime = "weapon_GrandChime",
	MountainMaul = "weapon_MountainMaul",
	RingmasterLash = "weapon_RingmasterLash",
	RoyalGreatsword = "weapon_RoyalGreatsword",
	SiegeBallista = "weapon_SiegeBallista",
	StarShower = "weapon_StarShower",
	StormBow = "weapon_StormBow",
	SunStaff = "weapon_SunStaff",
	ThunderWeb = "weapon_ThunderWeb",
	Damage = "rune_damage",
	Area = "rune_area",
	AttackSpeed = "rune_speed",
	LuckySock = "sock",
	LunchBox = "lunchbox",
	ChalkStick = "chalk",
	Heal = "hp", -- level-up fallback offers
	Coins = "coin",
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
