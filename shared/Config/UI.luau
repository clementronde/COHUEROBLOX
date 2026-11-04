--!strict
-- UI tuning, palettes and player-facing strings (ui domain). Design: docs/dossier/60-ui-ux.md.
-- Sizes are logical pixels at UIScale 1 (reference phone 844 x 390).

type L = { fr: string, en: string }

local UI = {}

UI.Scale = {
	PhoneShortSide = 520, -- TouchEnabled and short side < this = phone (vault: Responsive UI)
	ReferenceShortSide = 420, -- scale = clamp(shortSide / ref, Min, Max)
	Min = 1,
	Max = 1.4,
}

UI.TextScales = { 1, 1.15, 1.3 }

UI.Margin = 8
UI.MinTap = 44

UI.Fonts = {
	Body = "rbxasset://fonts/families/BuilderSans.json",
	Display = "FredokaOne", -- Font.fromName
}

UI.TextSize = {
	Tiny = 12,
	Small = 13,
	Body = 14,
	Title = 18,
	Big = 22,
	Timer = 28,
	TimerUrgent = 40,
	Huge = 34,
}

-- Semantic colour tokens. "Colorblind" overrides only what changes (Okabe-Ito based).
UI.Palettes = {
	Default = {
		Panel = Color3.fromRGB(28, 34, 48),
		PanelLight = Color3.fromRGB(44, 52, 72),
		Text = Color3.fromRGB(255, 255, 255),
		TextDim = Color3.fromRGB(180, 188, 204),
		Outline = Color3.fromRGB(10, 12, 18),
		Primary = Color3.fromRGB(90, 200, 120),
		Danger = Color3.fromRGB(255, 74, 61),
		Warning = Color3.fromRGB(255, 160, 40),
		Hp = Color3.fromRGB(240, 86, 74),
		Shield = Color3.fromRGB(90, 210, 255),
		Xp = Color3.fromRGB(182, 140, 255),
		Coin = Color3.fromRGB(255, 212, 71),
		Revive = Color3.fromRGB(80, 200, 220),
		Boss = Color3.fromRGB(200, 50, 60),
		Ultimate = Color3.fromRGB(255, 190, 60),
		MapSelf = Color3.fromRGB(255, 255, 255),
		MapAlly = Color3.fromRGB(76, 217, 100),
		MapShrine = Color3.fromRGB(60, 140, 255),
		MapChest = Color3.fromRGB(255, 212, 71),
		MapBoss = Color3.fromRGB(255, 59, 48),
		Common = Color3.fromRGB(170, 176, 186),
		Rare = Color3.fromRGB(60, 150, 255),
		Epic = Color3.fromRGB(180, 90, 255),
		Legendary = Color3.fromRGB(255, 190, 40),
		PingBoss = Color3.fromRGB(255, 59, 48),
		PingShrine = Color3.fromRGB(60, 140, 255),
		PingHelp = Color3.fromRGB(255, 150, 40),
		PingChest = Color3.fromRGB(255, 212, 71),
		PingRegroup = Color3.fromRGB(76, 217, 100),
		PingThanks = Color3.fromRGB(255, 130, 190),
	},
	Colorblind = {
		MapAlly = Color3.fromRGB(0, 158, 115),
		MapShrine = Color3.fromRGB(0, 114, 178),
		MapChest = Color3.fromRGB(240, 228, 66),
		MapBoss = Color3.fromRGB(213, 94, 0),
		Common = Color3.fromRGB(230, 230, 230),
		Rare = Color3.fromRGB(86, 180, 233),
		Epic = Color3.fromRGB(213, 94, 0),
		Legendary = Color3.fromRGB(240, 228, 66),
		Hp = Color3.fromRGB(213, 94, 0),
		Primary = Color3.fromRGB(0, 158, 115),
		PingBoss = Color3.fromRGB(213, 94, 0),
		PingShrine = Color3.fromRGB(0, 114, 178),
		PingHelp = Color3.fromRGB(230, 159, 0),
		PingChest = Color3.fromRGB(240, 228, 66),
		PingRegroup = Color3.fromRGB(0, 158, 115),
		PingThanks = Color3.fromRGB(204, 121, 167),
	},
}

-- Second channel for rarity: diamond count and border thickness (never changes between palettes).
UI.Rarity = {
	Common = { gems = 1, stroke = 2, name = { fr = "Commun", en = "Common" } :: L },
	Rare = { gems = 2, stroke = 3, name = { fr = "Rare", en = "Rare" } :: L },
	Epic = { gems = 3, stroke = 4, name = { fr = "Épique", en = "Epic" } :: L },
	Legendary = { gems = 4, stroke = 4, name = { fr = "Légendaire", en = "Legendary" } :: L },
}

UI.Hud = {
	TimerHz = 4,
	UrgentSeconds = 60,
	BossBarLinger = 3,
	AnnounceMin = 2,
	AnnounceMax = 6,
	TeamMax = 3,
	FeedMax = 3,
	FeedSeconds = 5,
}

UI.Cards = {
	Width = 132,
	Height = 112,
	Gap = 8,
	RingSize = 40,
	WarnSeconds = 3,
}

UI.Minimap = {
	Size = { phone = 112, tablet = 140, desktop = 160 },
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
	Small = 64,
	Ping = 48,
	Gap = 12,
	EdgeX = 20,
	EdgeY = 24,
	ShowJump = true, -- TODO(avatar): hide the default Roblox jump button if we keep ours
	KeyHints = {
		KeyboardAndMouse = { Ultimate = "E" },
		Gamepad = { Ultimate = "Y" },
	},
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
	Level = { fr = "Nv", en = "Lv" },
	LevelN = { fr = "Nv {n}", en = "Lv {n}" },
	New = { fr = "NOUVEAU", en = "NEW" },
	Companion = { fr = "Compagnon", en = "Companion" },
	Stunned = { fr = "sonné", en = "stunned" },
	Tier = { fr = "Tier {n}", en = "Tier {n}" },
	Stage = { fr = "Stage {n}", en = "Stage {n}" },
	FinalWave = { fr = "VAGUE FINALE {t}", en = "FINAL WAVE {t}" },
	Downed = { fr = "À TERRE", en = "DOWNED" },
	DownedTimer = { fr = "À TERRE — {s} s", en = "DOWNED — {s} s" },
	DownedHint = { fr = "Un coéquipier doit rester 3 s près de toi", en = "A teammate must stay near you for 3 s" },
	Ghost = { fr = "FANTÔME", en = "GHOST" },
	GhostHint = { fr = "Tu peux encore charger les autels (25 %)", en = "You can still charge shrines (25%)" },
	TeammateDowned = { fr = "{name} est à terre !", en = "{name} is down!" },
	PingFeed = { fr = "{name} : {ping}", en = "{name}: {ping}" },
	Reroll = { fr = "Relancer ({n})", en = "Reroll ({n})" },
	Skip = { fr = "Passer ({n})", en = "Skip ({n})" },
	Ban = { fr = "Bannir ({n})", en = "Banish ({n})" },
	BanHint = { fr = "Touche une carte à bannir", en = "Tap a card to banish" },
	Cancel = { fr = "Annuler", en = "Cancel" },
	ShrineCharge = { fr = "Autel {p} % · {n} joueur(s)", en = "Shrine {p}% · {n} player(s)" },
	ShrineTitle = { fr = "Choisis un bonus d'autel", en = "Pick a shrine bonus" },
	Ultimate = { fr = "Ultime", en = "Ultimate" },
	Jump = { fr = "Saut", en = "Jump" },
	Slide = { fr = "Glisser", en = "Slide" },
	Ping = { fr = "Ping", en = "Ping" },
	Distance = { fr = "{n} m", en = "{n} m" },
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
	Victory = { fr = "VICTOIRE !", en = "VICTORY!" },
	Defeat = { fr = "FIN DE LA RUN", en = "RUN OVER" },
	Kills = { fr = "Ennemis vaincus", en = "Enemies defeated" },
	Coins = { fr = "Pièces", en = "Coins" },
	Shrines = { fr = "Autels", en = "Shrines" },
	Chests = { fr = "Coffres", en = "Chests" },
	Revives = { fr = "Relèves", en = "Revives" },
	FinalWaveSec = { fr = "Vague Finale (s)", en = "Final Wave (s)" },
	DamageByWeapon = { fr = "Dégâts par arme", en = "Damage per weapon" },
	Quests = { fr = "Quêtes avancées", en = "Quest progress" },
	QuestDone = { fr = "TERMINÉE", en = "DONE" },
	Silver = { fr = "Étoiles d'argent : +{n}", en = "Silver stars: +{n}" },
	Replay = { fr = "REJOUER", en = "PLAY AGAIN" },
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
		fr = "Flèche blanche : toi · Chevron vert : coéquipier (+ = à terre) · Losange bleu : autel · Carré jaune : coffre · Rond rouge ! : boss",
		en = "White arrow: you · Green chevron: teammate (+ = down) · Blue diamond: shrine · Yellow square: chest · Red circle !: boss",
	},
}

return UI
