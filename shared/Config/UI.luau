--!strict
-- UI tuning, palettes and player-facing strings (ui domain). Design: docs/dossier/60-ui-ux.md
-- section 0 (v2 "Toy-block gloss", Figma file 0Yq5m1skq5dzgOQXZ9bG6D, validated by Clément on
-- 4 Nov 2026). Sizes are logical pixels at UIScale 1 (reference phone 844 x 390).

type L = { fr: string, en: string }

local UI = {}

-- Decision v2: English only at launch. The French strings stay for later; nil = follow the locale.
UI.ForceLanguage = "en" :: string?

UI.Scale = {
	PhoneShortSide = 520, -- TouchEnabled and short side < this = phone (vault: Responsive UI)
	ReferenceShortSide = 420, -- scale = clamp(shortSide / ref, Min, Max)
	Min = 1,
	Max = 1.6, -- v2: 1.4 was too small on a 1080p screen (design review)
}

UI.TextScales = { 1, 1.15, 1.3 }

UI.Margin = 8
UI.MinTap = 44

-- Three fonts shipped with Roblox AND available in Figma (same render on both sides).
UI.Fonts = {
	Number = "rbxasset://fonts/families/LuckiestGuy.json", -- big numbers, banners
	Label = "rbxasset://fonts/families/FredokaOne.json", -- buttons, titles, pills
	Body = "rbxasset://fonts/families/Nunito.json", -- descriptions (Bold / ExtraBold)
}

-- Text styles of the Figma file. Old role names are kept as aliases for the other UI modules.
UI.TextSize = {
	Hero = 56,
	NumberXL = 40,
	NumberL = 30,
	NumberM = 22,
	TitleL = 22,
	TitleM = 16,
	LabelM = 15,
	LabelS = 14,
	BodyM = 14,
	BodyS = 14,
	-- aliases (v1 role names)
	Tiny = 14,
	Small = 14,
	Body = 14,
	Title = 16,
	Big = 22,
	Timer = 30,
	TimerUrgent = 30,
	Huge = 40,
}

-- Ink outline on text: at most 8 % of the size (above that it eats the next glyph).
UI.TextStrokeRatio = 0.08

-- Semantic colour tokens (Figma collection "Color"). Triplets: <Role> = face, <Role>Light = gloss
-- band, <Role>Lip = darker lip. "Colorblind" overrides only what changes (Okabe-Ito).
local hex = Color3.fromHex
UI.Palettes = {
	Default = {
		-- surfaces and text
		Panel = hex("#1F2B49"),
		PanelLight = hex("#2B3A60"),
		PanelSunken = hex("#0E1424"),
		Highlight = hex("#3C4E7C"),
		Outline = hex("#0E1424"), -- navy ink, never pure black
		Shine = hex("#FFFFFF"),
		Text = hex("#FFFFFF"),
		TextDim = hex("#DCE3F5"),
		TextMuted = hex("#B8C4E3"),
		OnLight = hex("#0E1424"),
		-- actions
		Primary = hex("#62D93D"),
		PrimaryLight = hex("#C2FF85"),
		PrimaryLip = hex("#2D8A1E"),
		Neutral = hex("#3C4E7C"),
		NeutralLight = hex("#6E80AE"),
		NeutralLip = hex("#161F36"),
		Danger = hex("#FF4757"),
		DangerLight = hex("#FF9A9A"),
		DangerLip = hex("#B81E3A"),
		Premium = hex("#FFC22E"),
		PremiumLight = hex("#FFE58A"),
		PremiumLip = hex("#B8820A"),
		Info = hex("#3B87FF"),
		InfoLight = hex("#93C5FF"),
		InfoLip = hex("#1D4FBF"),
		Slide = hex("#22D39B"),
		SlideLight = hex("#95F7D5"),
		SlideLip = hex("#128A68"),
		Capture = hex("#FF5CB0"),
		CaptureLight = hex("#FFB0DC"),
		CaptureLip = hex("#B82A78"),
		-- stats
		Hp = hex("#FF4757"),
		HpLight = hex("#FF9A9A"),
		HpLip = hex("#B81E3A"),
		Shield = hex("#DDEBFA"),
		ShieldLight = hex("#FFFFFF"),
		ShieldLip = hex("#7D96B8"),
		Xp = hex("#2EDDF5"), -- same cyan as the XP gem in the world
		XpLight = hex("#A5F6FF"),
		XpLip = hex("#0B8FAD"),
		Coin = hex("#FFC22E"),
		CoinLight = hex("#FFE58A"),
		CoinLip = hex("#B8820A"),
		Ko = hex("#FF8A1F"),
		KoLight = hex("#FFC27A"),
		KoLip = hex("#B8540A"),
		Warning = hex("#FFC22E"), -- timer under 1:00
		Overtime = hex("#FF4757"),
		Boss = hex("#B81E3A"),
		Ultimate = hex("#FFC22E"),
		Revive = hex("#22D39B"),
		ReviveLight = hex("#95F7D5"),
		ReviveLip = hex("#128A68"),
		Downed = hex("#FF8A1F"),
		Ghost = hex("#B8C4E3"),
		-- minimap
		MapSelf = hex("#FFFFFF"),
		MapAlly = hex("#22D39B"),
		MapShrine = hex("#3B87FF"),
		MapChest = hex("#FFC22E"),
		MapBoss = hex("#FF4757"),
		MapCapture = hex("#FF5CB0"),
		-- rarity
		Common = hex("#BCC5D6"),
		CommonLight = hex("#F2F5FA"),
		CommonLip = hex("#77829A"),
		Rare = hex("#3B87FF"),
		RareLight = hex("#93C5FF"),
		RareLip = hex("#1D4FBF"),
		Epic = hex("#A75CFF"),
		EpicLight = hex("#DBADFF"),
		EpicLip = hex("#6A2DBF"),
		Legendary = hex("#FFC22E"),
		LegendaryLight = hex("#FFE58A"),
		LegendaryLip = hex("#B8820A"),
		-- pings
		PingBoss = hex("#FF4757"),
		PingShrine = hex("#3B87FF"),
		PingHelp = hex("#FF8A1F"),
		PingChest = hex("#FFC22E"),
		PingRegroup = hex("#22D39B"),
		PingThanks = hex("#FF5CB0"),
	},
	Colorblind = {
		Overtime = hex("#D55E00"),
		Slide = hex("#009E73"),
		SlideLight = hex("#5FD1B0"),
		SlideLip = hex("#006249"),
		Capture = hex("#CC79A7"),
		CaptureLight = hex("#E8B5D2"),
		CaptureLip = hex("#8C4A70"),
		Revive = hex("#009E73"),
		ReviveLight = hex("#5FD1B0"),
		ReviveLip = hex("#006249"),
		Downed = hex("#E69F00"),
		MapAlly = hex("#009E73"),
		MapShrine = hex("#0072B2"),
		MapChest = hex("#F0E442"),
		MapBoss = hex("#D55E00"),
		MapCapture = hex("#CC79A7"),
		Common = hex("#E6E6E6"),
		CommonLight = hex("#FFFFFF"),
		CommonLip = hex("#8E8E8E"),
		Rare = hex("#56B4E9"),
		RareLight = hex("#A9DAF5"),
		RareLip = hex("#2A7DB0"),
		Epic = hex("#D55E00"),
		EpicLight = hex("#FF9A5C"),
		EpicLip = hex("#8F3F00"),
		Legendary = hex("#F0E442"),
		LegendaryLight = hex("#FFF8A8"),
		LegendaryLip = hex("#A89C10"),
		PingBoss = hex("#D55E00"),
		PingShrine = hex("#0072B2"),
		PingHelp = hex("#E69F00"),
		PingChest = hex("#F0E442"),
		PingRegroup = hex("#009E73"),
		PingThanks = hex("#CC79A7"),
	},
}

-- Second channel for rarity: word, diamond count and frame thickness (never change with the palette).
UI.Rarity = {
	Common = { gems = 1, stroke = 3, name = { fr = "Commun", en = "Common" } :: L },
	Rare = { gems = 2, stroke = 4, name = { fr = "Rare", en = "Rare" } :: L },
	Epic = { gems = 3, stroke = 5, name = { fr = "Épique", en = "Epic" } :: L },
	Legendary = { gems = 4, stroke = 6, name = { fr = "Légendaire", en = "Legendary" } :: L },
}

UI.Hud = {
	TimerHz = 4,
	UrgentSeconds = 60,
	BossBarLinger = 3,
	AnnounceMin = 2,
	AnnounceMax = 6,
	TeamMax = 3,
	FeedMax = 3,
	FeedSeconds = 6,
	OvertimeStepSeconds = 30, -- fallback when RunState has no overtimeStep (Run.Overtime.StepSeconds)
}

UI.Cards = {
	Width = 150,
	Height = 188,
	RowWidth = 366, -- portrait phone: cards become rows
	RowHeight = 98,
	Gap = 12,
	ButtonWidth = 100,
	ButtonHeight = 48,
	RingSize = 48,
	WarnSeconds = 3,
	ArmSeconds = 0.4, -- cards ignore taps this long after they appear (no accidental pick)
}

UI.Minimap = {
	Size = { phone = 120, tablet = 120, desktop = 120 }, -- logical px, x UIScale
	RangeStuds = 120,
	Hz = 10,
	LongPress = 0.5,
	MaxMarkers = 48,
}

UI.Ping = {
	Kinds = { "Boss", "Shrine", "Help", "Chest", "Regroup", "Thanks" },
	Defs = {
		Boss = { glyph = "!", color = "PingBoss", life = 8, label = { fr = "Boss ici !", en = "Boss here!" } :: L },
		Shrine = { glyph = "*", color = "PingShrine", life = 6, label = { fr = "Autel", en = "Shrine" } :: L },
		Help = { glyph = "+", color = "PingHelp", life = 6, label = { fr = "À l'aide !", en = "Help!" } :: L },
		Chest = { glyph = "#", color = "PingChest", life = 6, label = { fr = "Coffre", en = "Chest" } :: L },
		Regroup = { glyph = "o", color = "PingRegroup", life = 6, label = { fr = "On se regroupe", en = "Regroup" } :: L },
		Thanks = { glyph = "<3", color = "PingThanks", life = 3, label = { fr = "Merci !", en = "Thanks!" } :: L },
	},
	MaxRange = 300, -- server check: studs from the sender's root part
	ClientRange = 290,
	PerSecond = 3, -- Net.onServerEvent token bucket
	WindowSeconds = 10,
	WindowMax = 6,
	PoolSize = 8,
	HoldForWheel = 0.3,
	WheelTimeout = 5,
	Context = { Boss = 40, Shrine = 15, Chest = 10 },
}

UI.Shrine = {
	ShowRadius = 14,
}

UI.Mobile = {
	Jump = 84,
	Action = 68, -- Slide, Capture
	Ping = 52,
	Gap = 12,
	EdgeX = 8, -- from the safe-area edge
	EdgeY = 8,
	LabelHeight = 18,
	ShowJump = true, -- TODO(avatar): hide the default Roblox jump button if we keep ours
}

UI.Victory = {
	BannerSeconds = 0, -- 0 = stays until the player picks
	CashOutKey = Enum.KeyCode.C,
	KeepGoingKey = Enum.KeyCode.K,
}

UI.Capture = {
	-- Optional remote (companion domain, contract request): CaptureState { state, progress, seconds, name }.
	RemoteName = "CaptureState",
	HoldSeconds = 2,
	ResultSeconds = 2.5,
}

UI.Settings = {
	SendDelay = 0.5,
}

UI.Defaults = {
	FreeClasses = { "Cornu", "Plumeline", "Mecano" },
	FreeCompanions = { "Braise", "Ronce", "Maree" },
	ClassOrder = { "Cornu", "Plumeline", "Mecano", "Felyne", "Rocailleux", "Sporelin", "Ecaille", "Astrel", "Cristallin", "Tentaculos" },
	CompanionOrder = { "Braise", "Ronce", "Maree", "Volt", "Givre", "Echo" },
}

-- Stat display names (Types.StatName) and whether the value is a percent.
UI.Stats = {
	Damage = { pct = true, name = { fr = "Dégâts", en = "Damage" } :: L },
	AttackSpeed = { pct = true, name = { fr = "Vitesse d'attaque", en = "Attack speed" } :: L },
	Amount = { pct = false, name = { fr = "Projectiles", en = "Projectiles" } :: L },
	Size = { pct = true, name = { fr = "Taille", en = "Size" } :: L },
	Duration = { pct = true, name = { fr = "Durée", en = "Duration" } :: L },
	Cooldown = { pct = true, name = { fr = "Recharge", en = "Cooldown" } :: L },
	CritChance = { pct = true, name = { fr = "Chance critique", en = "Crit chance" } :: L },
	CritDamage = { pct = true, name = { fr = "Dégâts critiques", en = "Crit damage" } :: L },
	Luck = { pct = false, name = { fr = "Chance", en = "Luck" } :: L },
	XpGain = { pct = true, name = { fr = "Gain d'XP", en = "XP gain" } :: L },
	Magnet = { pct = false, name = { fr = "Aimant", en = "Magnet" } :: L },
	MaxHp = { pct = false, name = { fr = "PV max", en = "Max HP" } :: L },
	Armor = { pct = false, name = { fr = "Armure", en = "Armor" } :: L },
	Regen = { pct = false, name = { fr = "Régénération", en = "Regen" } :: L },
	MoveSpeed = { pct = true, name = { fr = "Vitesse", en = "Move speed" } :: L },
	Dodge = { pct = true, name = { fr = "Esquive", en = "Dodge" } :: L },
	Thorns = { pct = true, name = { fr = "Épines", en = "Thorns" } :: L },
	Bounces = { pct = false, name = { fr = "Rebonds", en = "Bounces" } :: L },
	Difficulty = { pct = true, name = { fr = "Difficulté", en = "Difficulty" } :: L },
	LootBonus = { pct = true, name = { fr = "Butin", en = "Loot" } :: L },
}

-- Every UI string. Placeholders are named: {name}, {n}, {s}...
UI.Strings = {
	Level = { fr = "NV", en = "LV" },
	LevelN = { fr = "NV {n}", en = "LV {n}" },
	New = { fr = "NOUVEAU", en = "NEW" },
	Companion = { fr = "Compagnon", en = "Companion" },
	CompanionTag = { fr = "PET", en = "PET" }, -- short: fits next to LEGENDARY in a 150 px card header
	Stunned = { fr = "sonné", en = "stunned" },
	Tier = { fr = "Tier {n}", en = "Tier {n}" },
	Stage = { fr = "Stage {n}", en = "Stage {n}" },
	World = { fr = "MONDE {n} / {m}", en = "WORLD {n} / {m}" },
	Overtime = { fr = "OVERTIME", en = "OVERTIME" },
	Danger = { fr = "DANGER {n}", en = "DANGER {n}" },
	FinalWave = { fr = "VAGUE FINALE {t}", en = "FINAL WAVE {t}" },
	Ko = { fr = "KO", en = "KO" },
	Best = { fr = "RECORD {n}", en = "BEST {n}" },
	BestUnknown = { fr = "RECORD —", en = "BEST —" },
	NewBest = { fr = "NOUVEAU RECORD !", en = "NEW BEST!" },
	Downed = { fr = "À TERRE", en = "DOWNED" },
	DownedTitle = { fr = "À TERRE !", en = "DOWNED!" },
	DownedTimer = { fr = "À TERRE — {s} s", en = "DOWNED — {s} s" },
	DownedSeconds = { fr = "s pour être relevé", en = "s to be revived" },
	DownedHint = { fr = "Un coéquipier doit rester 3 s près de toi.", en = "A teammate must stay 3 s next to you." },
	ReviveBy = { fr = "Relève en cours · {p} %", en = "Being revived · {p}%" },
	Ghost = { fr = "FANTÔME", en = "GHOST" },
	GhostTitle = { fr = "MODE FANTÔME", en = "GHOST MODE" },
	GhostHint = { fr = "Tu peux encore aider : charge les autels (25 %) et pingue.", en = "You can still help: charge shrines (25% speed) and ping." },
	GhostBack = { fr = "RETOUR AU MONDE SUIVANT", en = "BACK AT THE NEXT WORLD" },
	TeammateDowned = { fr = "{name} est à terre !", en = "{name} is down!" },
	PingFeed = { fr = "{name} : {ping}", en = "{name}: {ping}" },
	LevelUp = { fr = "NIVEAU !", en = "LEVEL UP!" },
	Reroll = { fr = "Relancer", en = "Reroll" },
	Skip = { fr = "Passer", en = "Skip" },
	Ban = { fr = "Bannir", en = "Banish" },
	BanHint = { fr = "Touche une carte à bannir", en = "Tap a card to banish" },
	BanTag = { fr = "BANNIR", en = "TAP TO BANISH" },
	Cancel = { fr = "Annuler", en = "Cancel" },
	ShrineCharge = { fr = "Autel {p} % · {n} joueur(s)", en = "Shrine {p}% · {n} player(s)" },
	ShrineTitle = { fr = "Choisis un bonus d'autel", en = "Pick a shrine bonus" },
	Ultimate = { fr = "Ultime", en = "Ultimate" },
	Jump = { fr = "SAUT", en = "JUMP" },
	Slide = { fr = "GLISSER", en = "SLIDE" },
	Ping = { fr = "PING", en = "PING" },
	Capture = { fr = "CAPTURE", en = "CAPTURE" },
	Distance = { fr = "{n} m", en = "{n} m" },
	BossDistance = { fr = "BOSS {n} m", en = "BOSS {n} m" },
	-- Capture
	Capturing = { fr = "CAPTURE...", en = "CAPTURING..." },
	CaptureHint = { fr = "Reste dans la cage. Ne te fais pas toucher !", en = "Stay in the cage. Don't get hit!" },
	CaptureReset = { fr = "AÏE ! CAPTURE RATÉE", en = "OUCH! CAPTURE RESET" },
	CaptureRetry = { fr = "Touché. Retourne dans la cage.", en = "You got hit. Step back in to retry." },
	Captured = { fr = "CAPTURÉ !", en = "CAPTURED!" },
	CaptureJoins = { fr = "{name} rejoint ta collection", en = "{name} joins your collection" },
	CaptureSeconds = { fr = "{s} / {t} s", en = "{s} / {t} s" },
	-- Victory
	Victory = { fr = "VICTOIRE !", en = "VICTORY!" },
	VictorySub = { fr = "Le dernier boss est tombé ! Tous les mondes sont finis.", en = "The last boss is down! All worlds cleared." },
	CashOut = { fr = "Encaisser", en = "Cash out" },
	KeepGoing = { fr = "Continuer", en = "Keep going" },
	CashOutCaption = { fr = "Fin de la run, tu gardes tout.", en = "End the run, keep all your loot." },
	KeepGoingCaption = { fr = "Overtime sans fin. Bats ton record de KO.", en = "Endless Overtime. Chase the KO record." },
	CashOutPortal = { fr = "PORTAIL {n} m", en = "CASH OUT PORTAL {n} m" },
	CashOutHold = { fr = "Restez 2 s dans le portail doré, toute l'équipe", en = "Whole team: stand 2 s in the gold portal" },
	KoRun = { fr = "{n} KO", en = "{n} KO" },
	-- Loadout
	TabClass = { fr = "Classe", en = "Class" },
	TabCompanion = { fr = "Compagnon", en = "Companion" },
	Play = { fr = "JOUER", en = "PLAY" },
	Waiting = { fr = "En attente des autres joueurs…", en = "Waiting for other players…" },
	Locked = { fr = "Verrouillé", en = "Locked" },
	UnlockQuest = { fr = "Quête : {q}", en = "Quest: {q}" },
	UnlockEgg = { fr = "Dans un œuf gratuit gagné en jeu", en = "In a free egg earned in play" },
	Mastery = { fr = "Maîtrise {n}", en = "Mastery {n}" },
	Bond = { fr = "Lien {n}", en = "Bond {n}" },
	StartWeapon = { fr = "Arme : {w}", en = "Weapon: {w}" },
	ChooseLoadout = { fr = "Choisis ta classe et ton compagnon", en = "Choose your class and companion" },
	-- End screen
	Defeat = { fr = "FIN DE LA RUN", en = "RUN OVER" },
	EndSub = { fr = "Monde {w} · Overtime +{t} · Nv {l}", en = "World {w} · Overtime +{t} · Lv {l}" },
	EndSubNoOvertime = { fr = "Monde {w} · Nv {l}", en = "World {w} · Lv {l}" },
	Kills = { fr = "Ennemis vaincus", en = "Enemies defeated" },
	Coins = { fr = "Pièces", en = "Coins" },
	Shrines = { fr = "Autels", en = "Shrines" },
	Chests = { fr = "Coffres", en = "Chests" },
	Revives = { fr = "Relèves", en = "Revives" },
	FinalWaveSec = { fr = "Vague Finale (s)", en = "Final Wave (s)" },
	DamageByWeapon = { fr = "DÉGÂTS PAR ARME", en = "DAMAGE BY WEAPON" },
	Rewards = { fr = "GAINS", en = "REWARDS" },
	Quests = { fr = "Quêtes avancées", en = "Quest progress" },
	QuestDone = { fr = "TERMINÉE", en = "DONE" },
	QuestSteps = { fr = "+{n} étape(s) de quête", en = "+{n} quest step(s)" },
	Silver = { fr = "+{n} Silver", en = "+{n} Silver" },
	RankWeek = { fr = "cette semaine", en = "this week" },
	RankReset = { fr = "reset le lundi", en = "resets Monday" },
	Replay = { fr = "Rejouer", en = "Play again" },
	Lobby = { fr = "Lobby", en = "Lobby" },
	-- Settings
	Settings = { fr = "Réglages", en = "Settings" },
	Colorblind = { fr = "Mode daltonien", en = "Colorblind mode" },
	ReduceFlashes = { fr = "Réduire les flashs", en = "Reduce flashes" },
	TextSize = { fr = "Taille du texte", en = "Text size" },
	KeepHat = { fr = "Garder mon chapeau", en = "Keep my hat" },
	Language = { fr = "Langue", en = "Language" },
	LangAuto = { fr = "Auto", en = "Auto" },
	On = { fr = "Oui", en = "On" },
	Off = { fr = "Non", en = "Off" },
	Close = { fr = "Fermer", en = "Close" },
	Legend = { fr = "Légende de la carte", en = "Map legend" },
	LegendText = {
		fr = "Flèche blanche : toi · Chevron turquoise : coéquipier (+ = à terre) · Losange bleu : autel · Carré jaune : coffre · Étoile rose : capturable · Rond rouge ! : boss",
		en = "White arrow: you · Teal chevron: teammate (+ = down) · Blue diamond: shrine · Yellow square: chest · Pink star: capturable · Red circle !: boss",
	},
}

return UI
