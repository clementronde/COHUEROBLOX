--!strict
-- Réglages de la run (docs/dossier/01-decisions-v2.md section 2 ; détail : dossier 20 sections 1, 2, 6).
-- Courbe de densité, plafond technique d'ennemis vivants (Balance.MaxEnemies) et coop de base :
-- Config/Balance (chef de projet).

local Run = {
	-- Test en une seule place (ARCHITECTURE section 7). Lu par MatchService.
	UseLobbyPlace = false,

	DefaultWorld = "BoisGrognon",
	DefaultTier = 1,
	DefaultClass = "Knight",
	DefaultCompanion = "Braise",
	LoadoutTimeout = 45, -- seconds before a player without a loadout gets the default
	StudioLoadoutTimeout = 5,
	ReplayTimeout = 10,

	-- Run v2 : mondes enchaînés, 10:00 par monde, le boss tué ouvre le portail du monde suivant.
	-- WorldsPerRun reste un réglage : Clément doit encore confirmer l'enchaînement des 3 mondes.
	WorldsPerRun = 3,
	-- Monde joué à chaque étape. Vague 1 : aucun monde 2 ou 3 n'est construit, on rejoue le stage
	-- existant avec un paramètre de monde (WorldScaling). Vague 2 : ids des mondes 2 et 3.
	WorldChain = { "BoisGrognon", "BoisGrognon", "BoisGrognon" } :: { string },
	-- Force des ennemis par monde (index = monde 1..N ; au-delà, le dernier sert).
	WorldScaling = {
		{ hp = 1, damage = 1, speed = 1, density = 1, bossHp = 1 },
		{ hp = 1.8, damage = 1.35, speed = 1.05, density = 1.15, bossHp = 1.8 },
		{ hp = 3, damage = 1.8, speed = 1.1, density = 1.3, bossHp = 3 },
	} :: { { hp: number, damage: number, speed: number, density: number, bossHp: number } },

	-- Overtime : à 0:00 le chrono monte (+00:01...) et la difficulté grimpe sans plafond. Le boss
	-- reste tuable pour avancer. Après le boss du dernier monde, l'Overtime devient infini (Keep going).
	Overtime = {
		StepSeconds = 30,
		SpawnPerStep = 0.15, -- densité voulue +15 % par palier
		HpPerStep = 0.20, -- PV ennemis +20 % par palier
		DamagePerStep = 0.10, -- dégâts ennemis +10 % par palier
		ElitePointsPerStep = 0.03, -- part d'élites +3 points par palier
		Compound = false, -- false : +15 % x palier (linéaire) ; true : x1,15 ^ palier
		CoinsPerStep = 10, -- pièces de survie par palier et par joueur actif, x index du monde
		-- Au-delà du plafond technique (Balance.MaxEnemies), l'excès de densité devient des PV :
		-- PV x (densité voulue / plafond). Le joueur ne voit pas la différence, le téléphone tient.
		OverflowToHp = true,
		ValueCap = 1e9, -- PV et dégâts ennemis plafonnés (règles anti-triche §5.2 : jamais inf ni NaN)
	},
	-- Après le boss du dernier monde : portail doré « Cash out ». Tous les joueurs actifs dedans
	-- pendant HoldSeconds = fin de run, gains sauvés. Sinon on continue (Keep going).
	CashOut = {
		Radius = 10,
		HoldSeconds = 2,
	},

	-- Timers
	StageSeconds = 600,
	Waves = {
		{ timeLeft = 360, size = 40, boost = 1.3, boostSeconds = 45, spawnSeconds = 4 },
		{ timeLeft = 180, size = 60, boost = 1.3, boostSeconds = 45, spawnSeconds = 4 },
	},
	ArcheRevealRadius = 25,
	ArenaRadius = 60,
	ArenaStartSeconds = 20,
	FarmSeconds = 60, -- fenêtre après un boss (sauf le dernier) avant le téléport automatique
	PortalRadius = 8,
	-- Les portails (NEXT WORLD, CASH OUT) s'ouvrent à PortalOffset studs du centre de l'arène, là où
	-- le boss est mort, et n'acceptent personne pendant PortalGrace s : on ne part jamais par accident
	-- en tuant le boss au corps à corps.
	PortalOffset = 26,
	PortalGrace = 4,
	PhaseDensity = { Running = 1, Boss = 0.4, BossDefeated = 1, FinalWave = 1 } :: { [string]: number },
	DifficultyDensityShare = 0.5, -- Rune Cursed : densité x (1 + Difficulty moyenne x part)

	-- Player vitals
	Player = {
		BaseMaxHp = 100,
		DodgeCap = 0.6,
		ArmorK = 100, -- taken = amount * K / (K + armor)
		RegenInterval = 0.25,
		ContactHz = 15,
		ContactCooldown = 0.5,
		ContactMaxEnemies = 3,
		ContactHalfWidth = 1.5,
		ContactVerticalSlack = 2,
		EliteDamageMult = 1.5,
		-- S-05 : temps invulnérable (cartes, glissade, relève, apparition) plafonné à cette part du
		-- temps passé dans la run, + une grâce fixe pour les protections d'apparition.
		InvulnCapShare = 0.3,
		InvulnCapGrace = 10,
		-- S-01 (défense en profondeur) : un joueur à plus de AirHeight studs au-dessus du sol depuis
		-- plus de AirGroundAfter s est compté au sol pour les dégâts subis (contact, projectiles, boss).
		AirHeight = 3,
		AirGroundAfter = 1.5,
	},
	Coop = {
		DownedSeconds = 25,
		ReviveRadius = 6,
		ReviveSeconds = 3,
		ReviveDecay = 2, -- progress lost per second (x ReviveSeconds) when nobody is near
		ReviveHpFraction = 0.3,
		ReviveInvulnerable = 2,
		DownedSlow = 0.35,
		GhostShrineRate = 0.25, -- read by ShrineService (loot)
		GhostReturnHpFraction = 0.5, -- ghosts come back at the next stage
		GhostTransparency = 0.7,
	},
	VitalsMaxHz = 10,


	-- Spawn mix (seconds since stage start)
	FamilyUnlock = { Swarm = 0, Jumper = 30, Support = 75, Shooter = 120, Kamikaze = 150, Armored = 210 } :: { [string]: number },
	EliteFirstAt = 90,
	EliteEvery = 75,
	EliteChance = 0.005, -- part d'élites de base (hors Overtime)
	EliteMaxAlive = 4, -- hors Overtime ; en Overtime la part d'élites décide seule (sans plafond)
	EliteHpMult = 6,
	EliteSizeMult = 1.3,
	MiniBossAt = { 180, 420 },
	-- Variantes capturables (A03-03, dossier 40 §0-2). Marquées au spawn par EnemyService si
	-- CompanionService.isSpecies(kind) ; Enemies[].captureChance remplace Chance espèce par espèce.
	Capturable = {
		Chance = 0.004, -- par apparition ordinaire (≈ 5 à 8 par monde de 10 min)
		MiniBossChance = 0.25,
		HpMult = 2.5, -- « plus résistante »
		MaxAlive = 2, -- jamais plus de 2 à la fois : elles doivent rester rares et lisibles
		FirstAt = 60, -- secondes après le début du monde
	},

	-- Ancien mode Survie v1 : remplacé par l'Overtime infini après le dernier boss (Keep going).
	-- Les sélections de monde et de tier v1 (TierUnlock, SelectStage) n'ont plus d'effet sur la run.

	Debug = {
		AllowAnyStageInStudio = true,
		-- Studio seulement (jamais en ligne) : BindableFunction ServerStorage.CohueRunDebug pour les
		-- tests (barre de commande) : avancer le chrono, donner de l'XP, tuer le boss...
		StudioCommands = true,
	},
}

return Run
