--!strict
-- Sons et musiques (A10, docs/dossier/90-son.md ; décisions v2 §8 et §12).
-- Rien n'est construit par script : chaque son est un objet `Sound` posé par Clément dans
-- `ReplicatedStorage.Assets.Sounds` (sous-dossiers libres) ou dans `SoundService`. Le
-- SoundController le trouve par son NOM, le clone (en pool) et le joue. Le SoundId, la hauteur et
-- les effets (EqualizerSoundEffect, etc.) se règlent sur l'objet dans Studio ; ici, seulement le
-- mixage et la correspondance événement -> nom. Un nom manquant est signalé une fois dans la sortie.

export type Category = "Music" | "Ambience" | "Weapons" | "KO" | "Creatures" | "UI"
export type Group = "master" | "music" | "sfx"

export type CategoryDef = {
	group: Group, -- réglage joueur qui pilote la catégorie (en plus de master)
	volume: number, -- volume de la catégorie (mixage)
	maxVoices: number, -- sons simultanés max de la catégorie
	steal: boolean, -- plein : coupe le plus ancien (true) ou ignore le nouveau (false)
}

export type Event = {
	sound: string, -- nom de l'objet Sound fourni par Clément
	category: Category,
	volume: number?, -- multiplicateur (défaut 1)
	pitchJitter: number?, -- variation aléatoire de PlaybackSpeed (+/-), contre la répétition
	cooldown: number?, -- secondes min entre deux lectures de cet événement
}

local Sounds = {}

-- Où chercher les objets Sound (dans cet ordre, récursif).
Sounds.Folders = {
	{ "ReplicatedStorage", "Assets", "Sounds" },
	{ "SoundService" },
} :: { { string } }

-- Sons simultanés max, toutes catégories (téléphones bas de gamme).
Sounds.MaxVoices = 24

Sounds.Categories = {
	Music = { group = "music", volume = 0.5, maxVoices = 6, steal = false },
	Ambience = { group = "music", volume = 0.35, maxVoices = 2, steal = false },
	Weapons = { group = "sfx", volume = 0.45, maxVoices = 8, steal = true },
	KO = { group = "sfx", volume = 0.5, maxVoices = 6, steal = true },
	Creatures = { group = "sfx", volume = 0.55, maxVoices = 4, steal = true },
	UI = { group = "sfx", volume = 0.7, maxVoices = 4, steal = true },
} :: { [Category]: CategoryDef }

-- A10-05 : réglages joueur (0..1). Clés de Profile.settings lues si elles existent.
Sounds.Volumes = {
	Default = { master = 1, music = 0.7, sfx = 1 } :: { [Group]: number },
	SettingKeys = { master = "masterVolume", music = "musicVolume", sfx = "sfxVolume" } :: { [Group]: string },
	-- true : envoyé par UpdateSettings (regroupé, max 1 envoi par SendDelay, sous la limite serveur
	-- de 2/s) et sauvé dans Profile.settings (dossier 70 §1, §16). false : réglage local à la session.
	Persist = true,
	SendDelay = 0.5,
}

-- Sons « positionnés » (KO, impacts) : atténués selon la distance au personnage (vue de dessus,
-- pas de stéréo). Au-delà de HearRadius, rien n'est joué.
Sounds.Positional = {
	FullRadius = 25, -- volume plein en dessous
	HearRadius = 90,
	MinFactor = 0.2, -- volume au bord de HearRadius
}

-- Fréquence de la boucle musique (fondus, Overtime). Pas d'allocation dans cette boucle.
Sounds.MusicHz = 15

Sounds.Music = {
	FadeSeconds = 1.5,
	Lobby = "Music_Lobby",
	Worlds = {
		BoisGrognon = "Music_BoisGrognon",
		DunesCroustillantes = "Music_DunesCroustillantes",
		RecreFantome = "Music_RecreFantome",
	} :: { [string]: string },
	-- Boss : "Music_Boss_<bossId>" s'il existe, sinon la musique commune.
	BossPrefix = "Music_Boss_",
	Boss = "Music_Boss",
}

-- Ambiances en boucle par monde (catégorie Ambience), jouées pendant toute la run.
Sounds.Ambience = {
	BoisGrognon = "Amb_BoisGrognon",
	DunesCroustillantes = "Amb_DunesCroustillantes",
	RecreFantome = "Amb_RecreFantome",
} :: { [string]: string }

-- A10-04 : musique dynamique d'Overtime. Intensité 0..1 = secondes d'Overtime / RampSeconds.
-- La piste principale accélère un peu ; les couches (même tempo, même longueur, calées sur la
-- piste principale) entrent en fondu quand l'intensité passe leur seuil.
Sounds.Overtime = {
	Track = "Music_Overtime",
	RampSeconds = 240,
	SpeedFrom = 1,
	SpeedTo = 1.1,
	VolumeFrom = 0.85,
	VolumeTo = 1.1,
	Layers = {
		{ sound = "Music_Overtime_Layer2", from = 0.25 },
		{ sound = "Music_Overtime_Layer3", from = 0.6 },
	} :: { { sound: string, from: number } },
	LayerFadeSeconds = 2,
	ResyncTolerance = 0.15, -- secondes de décalage tolérées entre une couche et la piste principale
}

-- Noms construits (armes, ennemis) : on essaie dans l'ordre, le premier qui existe gagne.
-- {id} = id d'arme (Config.Weapons) ou nom d'ennemi (Config.Enemies, champ name),
-- {family} = famille d'ennemi (Swarm, Jumper, Shooter, Armored, MiniBoss, Boss).
-- Résolu une fois par id puis gardé en cache.
Sounds.Patterns = {
	WeaponFire = { "Weapon_{id}_Fire", "Weapon_Default_Fire" },
	WeaponHit = { "Weapon_{id}_Hit", "Weapon_Default_Hit" },
	EnemyKO = { "KO_{id}", "KO_{family}", "KO_Default" },
	EnemyAttack = { "Creature_{id}_Attack", "Creature_{family}_Attack" },
	EnemySpawn = { "Creature_{id}_Spawn", "Creature_{family}_Spawn" },
} :: { [string]: { string } }
Sounds.PatternEvents = {
	WeaponFire = { category = "Weapons", volume = 1, pitchJitter = 0.06, cooldown = 0.05 },
	WeaponHit = { category = "Weapons", volume = 0.8, pitchJitter = 0.08, cooldown = 0.04 },
	EnemyKO = { category = "KO", volume = 1, pitchJitter = 0.1, cooldown = 0.03 },
	EnemyAttack = { category = "Creatures", volume = 1, pitchJitter = 0.08, cooldown = 0.25 },
	EnemySpawn = { category = "Creatures", volume = 0.8, pitchJitter = 0.08, cooldown = 0.5 },
} :: { [string]: { category: Category, volume: number, pitchJitter: number, cooldown: number } }

-- Événements de jeu -> son. Clé = nom utilisé par le code (SoundController.play(key)).
Sounds.Events = {
	-- Ramassage, progression
	XpPickup = { sound = "SFX_XpPickup", category = "KO", volume = 0.5, pitchJitter = 0.12, cooldown = 0.06 },
	CoinPickup = { sound = "SFX_CoinPickup", category = "KO", volume = 0.7, pitchJitter = 0.08, cooldown = 0.08 },
	LevelUp = { sound = "SFX_LevelUp", category = "UI", cooldown = 0.3 },
	ChestOpen = { sound = "SFX_ChestOpen", category = "UI" },
	-- Cartes
	CardOffer = { sound = "UI_CardOffer", category = "UI", cooldown = 0.3 },
	CardPick = { sound = "UI_CardPick", category = "UI", cooldown = 0.2 },
	-- Interface
	Click = { sound = "UI_Click", category = "UI", volume = 0.8, cooldown = 0.05 },
	Purchase = { sound = "UI_Purchase", category = "UI" },
	Notify = { sound = "UI_Notify", category = "UI", cooldown = 0.5 },
	QuestComplete = { sound = "UI_QuestComplete", category = "UI" },
	EggHatch = { sound = "UI_EggHatch", category = "UI" },
	Ping = { sound = "UI_Ping", category = "UI", cooldown = 0.2 },
	-- Joueur
	PlayerHurt = { sound = "SFX_PlayerHurt", category = "KO", volume = 0.7, pitchJitter = 0.08, cooldown = 0.35 },
	PlayerDowned = { sound = "SFX_PlayerDowned", category = "UI" },
	-- Autels, compagnon, capture
	ShrineReward = { sound = "SFX_ShrineReward", category = "UI" },
	CompanionEvolve = { sound = "SFX_CompanionEvolve", category = "UI" },
	UltimateReady = { sound = "SFX_UltimateReady", category = "UI", cooldown = 1 },
	CaptureCharge = { sound = "SFX_CaptureCharge", category = "UI", cooldown = 0.3 },
	CaptureSuccess = { sound = "SFX_CaptureSuccess", category = "UI" },
	-- Boss
	BossRoar = { sound = "Creature_Boss_Roar", category = "Creatures", cooldown = 2 },
	BossTelegraph = { sound = "Creature_Boss_Telegraph", category = "Creatures", volume = 0.8, cooldown = 0.4 },
	BossDefeated = { sound = "Stinger_BossDefeated", category = "Music" },
	-- Fin de run (petits jingles, pas en boucle)
	Victory = { sound = "Stinger_Victory", category = "Music" },
	Defeat = { sound = "Stinger_Defeat", category = "Music" },
	-- Annonces (remote Announce)
	AnnounceStage = { sound = "Announce_StageStart", category = "UI" },
	AnnounceWave = { sound = "Announce_Wave", category = "UI" },
	AnnounceMiniBoss = { sound = "Announce_MiniBoss", category = "UI" },
	AnnounceArche = { sound = "Announce_ArcheRevealed", category = "UI" },
	AnnounceCountdown = { sound = "Announce_Countdown", category = "UI", cooldown = 0.8 },
	AnnounceOvertime = { sound = "Announce_Overtime", category = "UI" },
	AnnounceOvertimeStep = { sound = "Announce_OvertimeStep", category = "UI" },
	AnnounceHazard = { sound = "Announce_Hazard", category = "UI" },
	AnnouncePortal = { sound = "Announce_Portal", category = "UI" },
	AnnounceDowned = { sound = "Announce_TeammateDowned", category = "UI" },
	AnnounceRevived = { sound = "Announce_Revived", category = "UI" },
} :: { [string]: Event }

-- Remote Announce : kind -> clé d'événement (Victory / Defeat / CashOut passent par les jingles).
Sounds.AnnounceKinds = {
	StageStart = "AnnounceStage",
	Wave = "AnnounceWave",
	MiniBoss = "AnnounceMiniBoss",
	ArcheRevealed = "AnnounceArche",
	ArenaCountdown = "AnnounceCountdown",
	Overtime = "AnnounceOvertime",
	OvertimeStep = "AnnounceOvertimeStep",
	Hazard = "AnnounceHazard",
	Portal = "AnnouncePortal",
	Downed = "AnnounceDowned",
	Died = "AnnounceDowned",
	Revived = "AnnounceRevived",
	Victory = "Victory",
	CashOut = "Victory",
	Defeat = "Defeat",
} :: { [string]: string }

-- Clic automatique sur tout GuiButton du PlayerGui. Un bouton peut le couper (attribut
-- NoClickSound = true) ou le remplacer (attribut ClickSound = "<clé d'événement>").
Sounds.AutoClick = true

return Sounds
