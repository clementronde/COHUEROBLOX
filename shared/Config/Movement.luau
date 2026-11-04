--!strict
-- Réglages du mouvement, de la caméra et de MovementGuard (A06, domaine avatar).
-- Design : docs/dossier/50-classes-avatar-mouvement.md sections 4 à 7. Tous les nombres du domaine sont ici.
--
-- Profils de classe : `Movement.profile(classId)`, lu par MovementController (client) et MovementGuard
-- (serveur) à partir de l'attribut serveur `Player.ClassId`. La classe donne les stats de mouvement,
-- jamais l'apparence de l'avatar.
-- Deux sources, sans doublon : `Config/Classes` (A04) donne les nombres de base et les drapeaux
-- (walkSpeed, jumpHeight, airJumps, glide + glideSeconds, heavyLanding, slideBoost) ; `Movement.Classes`
-- ci-dessous ne donne que les réglages fins du mouvement (vitesse de plané, contrecoup d'atterrissage,
-- gravité, frottement de glissade...). Une classe inconnue reçoit le profil normal.

export type Glide = {
	fallSpeed: number, -- studs/s de chute max en planant
	duration: number, -- secondes de plané par saut (recharge à l'atterrissage)
}

export type HeavyLanding = {
	minFall: number, -- studs de chute pour déclencher l'atterrissage lourd
	slowMult: number, -- vitesse de marche pendant le contrecoup
	slowTime: number, -- secondes de contrecoup
	shake: number, -- 0..1, secousse de caméra
}

export type SlideTuning = {
	boost: number?, -- multiplicateur de vitesse au départ
	friction: number?, -- studs/s² perdus au plat
	endMult: number?, -- fin sous ce multiple de la marche
	maxFlatTime: number?, -- secondes sans pente avant la fin
	maxMult: number?, -- plafond, multiple de la marche
	steer: number?, -- vitesse de braquage (1/s)
	charge: boolean?, -- glissade de charge (Barbarian) : attribut serveur SlideCharge
}

export type ClassMove = {
	walkSpeed: number?,
	jumpHeight: number?,
	gravityMult: number?, -- 1 = normale, > 1 = tombe plus vite
	airJumps: number?,
	glide: Glide?,
	heavyLanding: HeavyLanding?,
	slide: SlideTuning?,
}

local Movement = {
	-- Valeurs de base (lobby, avant la run, classe inconnue)
	DefaultWalkSpeed = 16,
	DefaultJumpHeight = 7.2,

	-- Saut (le saut est piloté par MovementController : Humanoid.JumpHeight reste à 0)
	JumpBuffer = 0.12, -- s : appui en l'air juste avant l'atterrissage = saut à l'atterrissage
	CoyoteTime = 0.10, -- s : saut encore permis après avoir quitté un rebord
	AirJumpMult = 0.9, -- hauteur du double saut, x hauteur du saut

	-- Bunny-hop
	BhopWindow = 0.15, -- s après l'atterrissage pour relancer (appui neuf obligatoire, pas maintenu)
	BhopGainPerHop = 0.03, -- +3 % par hop réussi
	BhopMaxBonus = 0.6, -- plafond +60 %
	BhopKeepSpeed = 0.7, -- un hop ne compte que si la vitesse au sol est >= 70 % de la marche actuelle

	-- Glissade
	SlideMinSpeed = 6, -- studs/s horizontaux, sinon il faut une direction au stick
	SlideBoost = 1.2,
	SlideFriction = 12, -- studs/s² au plat
	SlideSlopeGain = 0.6, -- part de g x sin(pente) gagnée en descente
	SlideSlopeMin = 0.08, -- sin(pente) en dessous = plat
	SlideMaxMult = 2.2, -- plafond, x marche de base
	SlideEndMult = 0.55, -- fin sous ce multiple de la marche de base
	SlideMaxFlatTime = 1.6,
	SlideSteer = 2.5,
	SlideAirEnd = 0.3, -- s en l'air avant la fin de la glissade
	SlideCooldown = 0.35, -- s entre la fin d'une glissade et la suivante
	SlideBuffer = 0.15, -- s : Glisser pressé en l'air juste avant l'atterrissage = glissade à l'atterrissage
	SlideJumpGrace = 0.2, -- s après la fin d'une glissade où un saut convertit encore l'élan
	LandIgnoreAfterJump = 0.15, -- s : un retour au sol aussi tôt après notre saut n'est pas un atterrissage
	CoyoteIgnoreAfterJump = 0.1, -- s : une chute aussi tôt après notre saut n'ouvre pas le coyote time
	HopResetDelay = 0.2, -- s après un saut avant de pouvoir perdre le bonus au sol
	GroundProbeExtra = 0.6, -- studs sous les pieds pour le rayon de sol client
	LandProbeExtra = 2, -- studs de plus à l'état Landed (le personnage est encore un peu au-dessus du sol)
	LandingSoonExtra = 0.3, -- studs de marge pour « touchera le sol dans JumpBuffer »
	SlideTouchTap = true, -- tactile : un appui lance toute la glissade (relâcher ne l'arrête pas)

	-- Atterrissage (visuel local)
	ShockwaveMinFall = 18,
	ShockwaveMaxRadius = 12,
	ShockwaveTime = 0.35,
	LandShakeMinFall = 18, -- secousse légère pour tout le monde au-dessus de cette chute
	GroundNormalMinY = 0.55,

	-- Signaux au serveur (remote MoveEvent)
	MoveEventRate = 10, -- par seconde et par joueur
	SlidingAttrTimeout = 2.5, -- s avant que le serveur efface Sliding de lui-même
	HopMinInterval = 0.2, -- s entre deux hops comptés

	-- Réglages fins par classe (ids de 01-decisions-v2.md section 3). Les nombres de base et les drapeaux
	-- viennent de Config/Classes (A04) : voir Movement.profile.
	Classes = {
		Mage = { glide = { fallSpeed = 6, duration = 1.1 } }, -- vitesse du plané ; durée : glideSeconds d'A04
		Guardian = {
			gravityMult = 1.2, -- tombe plus vite : sauts courts, atterrissages lourds
			heavyLanding = { minFall = 8, slowMult = 0.6, slowTime = 0.25, shake = 0.7 },
		},
		Barbarian = {
			-- glissade qui charge : plus longue, braque mieux (boost : slideBoost d'A04)
			slide = { friction = 6, endMult = 0.5, maxFlatTime = 2.2, maxMult = 2.4, steer = 4, charge = true },
		},
	} :: { [string]: ClassMove },
	HeavyLandingDefault = { minFall = 8, slowMult = 0.6, slowTime = 0.25, shake = 0.7 } :: HeavyLanding,
	GlideFallSpeedDefault = 6,

	-- Croissance du trait (lu par TraitService, domaine A04). Gardé tel quel en attendant que A04
	-- remplace TraitService par l'équipement voxel ; à déplacer chez A04 à ce moment-là.
	Trait = {
		StageLevels = { 10, 20, 30 },
		StageScale = { 1.0, 1.15, 1.3, 1.45 },
		AvatarScaleMin = 0.6,
		AvatarScaleMax = 1.6,
		AppearanceTimeout = 6,
	},

	-- Caméra 3e personne (CameraController)
	Camera = {
		FieldOfView = 70,
		SpeedFov = 8, -- degrés ajoutés à pleine vitesse
		SpeedFovFrom = 1.15, -- multiple de la marche où le FOV commence à s'ouvrir
		FovSharpness = 6,

		Distance = 32, -- studs derrière le point visé (testé : 217 ennemis lisibles, anneau autour du joueur visible)
		MinDistance = 14,
		MaxDistance = 48,
		Pitch = 42, -- degrés sous l'horizon (30 = plus de profondeur, 46 = plus vue de dessus)
		MinPitch = 8,
		MaxPitch = 70,
		FocusHeight = 2.5, -- au-dessus du HumanoidRootPart
		FocusAhead = 5, -- studs : la caméra avance d'autant, le joueur est un peu sous le centre

		FollowSharpness = 20, -- suivi horizontal (plus haut = plus collé)
		FollowSharpnessY = 8, -- suivi vertical plus doux (sauts)
		ZoomSharpness = 12,

		-- Sensibilités
		TouchDegreesPerScreen = 260, -- yaw pour un glissé de toute la hauteur de l'écran
		TouchPitchMult = 0.6,
		TouchZoneMinX = 0.5, -- seule la moitié droite de l'écran tourne la caméra
		MouseDegreesPerPixel = 0.3, -- x sensibilité du jeu (CameraController.setSensitivity), pas celle de Roblox
		GamepadYawSpeed = 220, -- degrés/s stick à fond
		GamepadPitchSpeed = 120,
		GamepadDeadzone = 0.15,
		GamepadCurve = 2, -- exposant de la courbe de réponse
		KeyYawSpeed = 150, -- flèches gauche / droite
		WheelStep = 3,
		ZoomStep = 6, -- I / O, gâchettes hautes
		PinchPower = 1,

		-- Recentrage automatique derrière la course (tactile et manette seulement)
		AutoFollow = { Touch = true, Gamepad = true, Mouse = false, Delay = 1.0, Rate = 1.2, MaxAngle = 75, MinSpeed = 6 },

		-- Pas de caméra dans les murs
		CollisionRadius = 0.6,
		CollisionMargin = 0.3,
		CollisionMinDistance = 2,
		CollisionOutSharpness = 4, -- ressort lent quand l'obstacle disparaît
		ThinPropStuds = 3, -- un obstacle dont la 2e plus grande dimension est sous ça (tronc, poteau) est ignoré
		FadeDistance = 5, -- sous cette distance, le personnage local devient transparent

		ShakeMaxAngle = 1.6, -- degrés
		ShakeFrequency = 22,
		ShakeTime = 0.3,
	},

	-- MovementGuard (vérification serveur, mode classique)
	Guard = {
		Interval = 0.25, -- s entre deux échantillons
		Margin = 1.06, -- marge sur la vitesse plausible
		SlackStuds = 0.6, -- studs tolérés par échantillon (gigue de réplication)
		JitterPing = 0.25, -- part du ping ajoutée en studs x vitesse
		PingCap = 1,
		AirMemory = 0.7, -- s : le bonus de bunny-hop reste permis tant qu'un échantillon en l'air est aussi récent
		MinHopTime = 0.4, -- s : un hop crédité au plus par MinHopTime (vol le plus court d'un hop légitime ~0,47 s)
		HopAirSlack = 0.5, -- s ajoutées à AirMemory pour accepter un Hop reçu juste au décollage
		SlideMemory = 0.8, -- s après la fin d'une glissade où son plafond reste permis
		SlideMinInterval = 0.6, -- s entre deux SlideStart acceptés (chaîne glissade-saut légitime : ~0,65 s)
		SlideStartSlack = 1.1, -- marge sur la vitesse de départ de glissade calculée par le serveur
		SlopeLeniency = 1.5, -- le gain de pente vu à 4 Hz est majoré (le joueur a pu passer sur plus raide)
		SlideFrictionLeniency = 0.8, -- part du frottement de glissade appliquée par le serveur, en continu
		StallMoveStuds = 0.2, -- en dessous, l'échantillon compte comme « gelé » (rattrapage réseau ensuite)
		StallCap = 1.5, -- s de gel max pris en compte
		BucketMax = 20, -- studs d'excès cumulé avant recalage
		CreditSeconds = 0.5, -- un pas court laisse au plus ça de course en avance (positions répliquées par paquets)
		LeakPerSecond = 1.5,
		TeleportMinStuds = 45,
		TeleportFactor = 2.5,
		HitchFactor = 3, -- échantillon ignoré si dt > HitchFactor x Interval
		GraceAfterRubberBand = 0.6,
		SpawnGrace = 3,
		HoverLimit = 3.5, -- s en l'air...
		HoverRange = 2, -- ...avec moins de 2 studs d'amplitude verticale = vol stationnaire
		FlyMargin = 8, -- studs au-dessus de la plus haute hauteur de saut de la classe = vol
		HoverEnforce = true, -- vol stationnaire, vol, montée trop rapide, trop haut trop longtemps : recalage
		Enforce = true, -- false = log seulement pour vitesse et téléport aussi
		LogEvery = 5,
		HeavyFall = 8, -- chute mesurée par le serveur pour l'attribut HeavyLandAt (classes à atterrissage lourd)
		PadRadius = 6, -- studs autour d'un tremplin du plan partagé
		PadGrace = 2.5, -- s de vitesse relevée après un tremplin (le client applique le lancer)
		PadMaxSpeed = 30, -- studs/s permis pendant cette grâce (lancer latéral 22 + marche) ; téléport toujours contrôlé
		SandstormPush = 8, -- studs/s ajoutés pendant la tempête de sable (pushSpeed 6 + marge)
		SlideCooldownSlack = 0.6, -- part de SlideCooldown exigée entre SlideEnd et SlideStart reçus (gigue réseau)
		SlideProtectExtra = 0.3, -- s : une glissade lancée juste après un saut garde la chaîne de hops maxFlatTime + ça
		StallMinVelocity = 2, -- studs/s : le gel ne compte que si la vitesse répliquée dit que le joueur bouge
		-- Règles v2 (docs/security/regles-v2.md §1)
		FlyHeight = 12, -- studs de root au-dessus de Heightmap.getY, hors sol vu par le serveur...
		FlyTime = 2, -- ...pendant plus de ça : recalage (S-01)
		RiseMargin = 1.2, -- montée par échantillon <= vitesse de saut de la classe x ça x temps (S-01)
		RiseSlackStuds = 1,
		ExemptBoundFactor = 3, -- pendant une exemption, pas <= vitesse max x temps x ça + portée de lancement (S-02)
		ExemptLaunchStuds = 12,
		SlideValidateInterval = 1.5, -- s entre deux glissades validées (attribut Sliding, Shadowstep) (S-08)
		SlidePendDefer = 0.5, -- s : un SlideStart trop lent pour le serveur attend ça qu'il voie la vitesse
		SlideMinMeasured = 0.8, -- part de SlideMinSpeed exigée sur la vitesse mesurée par le serveur
		HopLandWindow = 0.3, -- s : un Hop n'est crédité que si le serveur a vu le sol aussi récemment (S-08)...
		HopLandDefer = 0.5, -- ...ou le voit dans ce délai après le Hop (positions répliquées en retard sur l'événement)
		SlideHopGrace = 0.35, -- s : la vitesse de fin de glissade reste permise seulement si un Hop suit d'aussi près
		TeleportSettle = 0.5, -- s (+ ping) après un déplacement serveur sans juger les positions en vol
		GraceSpeedFactor = 1.2, -- grâce (recalage, apparition, téléport serveur) : distance à l'ancre <= vitesse max x temps x ça
		StallBreachStuds = 5, -- excès sur un rattrapage après gel : strike immédiat au-delà
		StallDirDot = 0.5, -- le rattrapage doit aller dans la direction de la vitesse répliquée pendant le gel
		SupportRadius = 1.2, -- rayon de la sphère d'appui (bord de plateau, tête d'un coéquipier)
		GroundReachExtra = 1.5, -- studs sous les pieds pour le rayon de sol serveur
	},
}

local profileCache: { [string]: ClassMove } = {}
local EMPTY: ClassMove = {}

-- Profil résolu d'une classe : nombres de base et drapeaux de Config/Classes (A04), réglages fins de
-- Movement.Classes. Mis en cache par id. Ne renvoie jamais nil.
function Movement.profile(classId: any): ClassMove
	if type(classId) ~= "string" then
		return EMPTY
	end
	local cached = profileCache[classId]
	if cached then
		return cached
	end
	local okClasses, Classes = pcall(function()
		return (require :: any)(script.Parent:WaitForChild("Classes", 5))
	end)
	local def = if okClasses and type(Classes) == "table" then Classes[classId] else nil
	if type(def) ~= "table" then
		def = nil
	end
	local id = if def and type(def.id) == "string" then def.id else classId
	local tune: ClassMove = Movement.Classes[id] or EMPTY
	local p: ClassMove = {
		walkSpeed = if def and type(def.walkSpeed) == "number" then def.walkSpeed else tune.walkSpeed,
		jumpHeight = if def and type(def.jumpHeight) == "number" then def.jumpHeight else tune.jumpHeight,
		gravityMult = tune.gravityMult,
		airJumps = if def and type(def.airJumps) == "number" then def.airJumps else tune.airJumps,
		glide = tune.glide,
		heavyLanding = tune.heavyLanding,
		slide = tune.slide,
	}
	if def and def.glide == true then
		local base = tune.glide
		p.glide = {
			fallSpeed = if base then base.fallSpeed else Movement.GlideFallSpeedDefault,
			duration = if type(def.glideSeconds) == "number" then def.glideSeconds elseif base then base.duration else 1.1,
		}
	end
	if def and def.heavyLanding == true and not p.heavyLanding then
		p.heavyLanding = Movement.HeavyLandingDefault
	end
	if def and type(def.slideBoost) == "number" then
		local slide = table.clone(tune.slide or {})
		slide.boost = def.slideBoost
		p.slide = slide
	end
	profileCache[classId] = p
	return p
end

function Movement.walkSpeed(p: ClassMove): number
	return p.walkSpeed or Movement.DefaultWalkSpeed
end

function Movement.jumpHeight(p: ClassMove): number
	return p.jumpHeight or Movement.DefaultJumpHeight
end

function Movement.slideMaxMult(p: ClassMove): number
	local s = p.slide
	return if s and s.maxMult then s.maxMult else Movement.SlideMaxMult
end

return Movement
