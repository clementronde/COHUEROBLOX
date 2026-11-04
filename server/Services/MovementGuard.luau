--!strict
-- MovementGuard (A06, domaine avatar) : contrôles de plausibilité serveur pour des personnages pilotés par
-- le client (mode classique). Design : docs/dossier/50-classes-avatar-mouvement.md section 7.
-- Vault fwjelaa : « Exploits and Anti-Cheat », « Detecting Movement Exploits - Speed Fly Noclip Teleport ».
--
-- Échantillon toutes les 0,25 s, déplacement horizontal seulement. La vitesse permise dépend de ce que le
-- serveur voit lui-même (jamais Humanoid.WalkSpeed) :
--   marche                 marche(classe) x (1 + MoveSpeed serveur)
--   bunny-hop              + 3 % par hop reçu (MoveEvent Hop) pendant que le serveur voit le joueur en l'air,
--                          au plus un hop par MinHopTime ; perdu après AirMemory au sol
--   glissade               vitesse suivie par le serveur : départ = course permise x boost de la classe, puis
--                          gain de pente seulement si le serveur voit une pente sous le joueur ; plafond de classe.
--                          Un saut en fin de glissade crédite le bonus correspondant.
-- Seau percé sur l'excès + contrôle de téléport + vol stationnaire (mode ombre). Un gel de réplication
-- (le serveur ne voit plus bouger le joueur, puis un rattrapage) est pris en compte : la distance permise
-- couvre le temps gelé. Sanction = recalage sur la dernière position valide au sol. Jamais de kick.
-- Valide aussi le remote MoveEvent et pose les attributs serveur Sliding / SlideCharge / HopChain / Airborne /
-- HeavyLandAt sur le Player (lecture seule pour les autres domaines).
--
-- Exemptions (mouvement causé par le serveur : tremplins, geysers, tyroliennes, téléports, recul) :
--   MovementGuard.exempt(player, seconds, reason?)
--   ou attribut serveur Player.MoveExemptUntil = workspace:GetServerTimeNow() + seconds
-- Lecture : getStrikes(player) -> number · getRunStrikes(player) -> number · getLastValidPosition(player) -> Vector3?
-- Règles v2 appliquées : docs/security/regles-v2.md §1 (S-01 vol, S-02 exemptions bornées, S-03 bonus
-- validés, S-08 SlideStart / Hop validés, S-14 ralentis appliqués).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Registry = require(Shared:WaitForChild("Registry"))
local Movement = require(Shared:WaitForChild("Config"):WaitForChild("Movement"))
local Heightmap = require(Shared:WaitForChild("Heightmap"))

local G = Movement.Guard

local IS_STUDIO = RunService:IsStudio()

type State = {
	lastPos: Vector3,
	lastValid: CFrame,
	bucket: number,
	bucketPeak: number,
	ratioPeak: number, -- pire pas / (vitesse permise x temps), Studio
	exemptUntil: number, -- os.clock()
	strikes: number,
	rubberBands: number,
	stall: number, -- s pendant lesquels le serveur n'a vu aucun déplacement
	-- bunny-hop : crédits gagnés par des hops reçus pendant qu'on voit le joueur en l'air, plafonnés par le temps
	hopCredits: number,
	chainStart: number,
	lastAirAt: number,
	lastHopAt: number,
	-- glissade : vitesse max plausible suivie par le serveur (départ + pente vue sous le joueur)
	slideUntil: number, -- > 0 = glissade en cours (attribut Sliding)
	slideSpeed: number,
	slideEntryBonus: number,
	slideSlopeGain: number,
	slideEndAt: number,
	lastSlideStart: number,
	slideProtectUntil: number, -- la glissade garde la chaîne de hops jusque-là
	padUntil: number, -- vitesse relevée après un tremplin
	padUsed: boolean, -- un tremplin par atterrissage
	lastValidSlideAt: number, -- dernière glissade validée (attribut Sliding)
	lastGroundAt: number, -- dernier sol vu par le serveur
	lastSpeed: number, -- vitesse horizontale mesurée par le serveur (studs/s)
	rebaseNext: boolean, -- prochain échantillon : accepter un déplacement causé par le serveur
	highSince: number?, -- trop haut au-dessus du sol depuis
	graceAnchor: Vector3?, -- grâce (recalage, apparition, téléport serveur) : point de départ imposé
	graceStart: number,
	settleUntil: number, -- après un déplacement serveur ou un recalage : positions en vol encore acceptées...
	settleFrom: Vector3?, -- ...si elles sont près de l'ancienne position
	graceKind: string, -- "spawn" | "band" (vitesse normale) ou "server" (déplacement serveur)
	pendingSlideJumpAt: number?, -- saut de glissade en attente d'être vu en l'air
	lastSupportAt: number, -- dernier sol ou appui vu (sonde par image)
	slideMemoryUntil: number, -- vitesse de fin de glissade permise jusque-là (seulement si un Hop a suivi)
	stallSpeed: number, -- vitesse répliquée pendant le gel (min)
	stallDir: Vector3, -- direction de cette vitesse
	lastHopCountAt: number,
	hopStats: { [string]: number }, -- Studio : Hop acceptés / refusés par raison
	pendingHopAt: number?, -- Hop reçu, en attente d'un atterrissage vu par le serveur
	pendingSlideAt: number?, -- SlideStart reçu, en attente d'une vitesse mesurée suffisante
	-- en l'air
	wasAirborne: boolean,
	landPeakY: number, -- pour l'atterrissage lourd
	airborneFor: number,
	airStartY: number,
	airTopY: number,
	airLowY: number,
	lastLog: number,
	dbg: string, -- dernier échantillon (Studio : CohueGuardDebug)
}

local MovementGuard = {}

local states: { [Player]: State } = {}
local runStrikes: { [number]: number } = {} -- par UserId : survit aux réapparitions et aux reconnexions ; remis à 0 au début de la run

-- Ping borné. En Studio, l'attribut Workspace.CohueTestPing (secondes) le remplace pour tester les branches
-- qui dépendent du ping (GetNetworkPing vaut 0 en Studio).
local function pingOf(player: Player): number
	local ping = player:GetNetworkPing()
	if IS_STUDIO then
		local test = Workspace:GetAttribute("CohueTestPing")
		if type(test) == "number" then
			ping = test
		end
	end
	return math.clamp(ping, 0, G.PingCap)
end

local function flatDist(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local function refreshFilter()
	local exclude: { Instance } = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(exclude, p.Character)
		end
	end
	rayParams.FilterDescendantsInstances = exclude
end

local function moveSpeedStat(player: Player): number
	local StatsService = Registry.find("StatsService")
	if StatsService then
		local ok, stats = pcall(StatsService.get, player)
		if ok and type(stats) == "table" and type(stats.MoveSpeed) == "number" and stats.MoveSpeed == stats.MoveSpeed then
			return math.max(0, stats.MoveSpeed)
		end
	end
	return 0
end

type Limits = { base: number, slideCap: number, maxPossible: number, boost: number, friction: number, gravity: number }

-- Vitesses de référence côté serveur (studs/s), depuis la classe et les stats serveur.
local function limits(player: Player): Limits
	local prof = Movement.profile(player:GetAttribute("ClassId"))
	local base = Movement.walkSpeed(prof) * (1 + moveSpeedStat(player))
	local slideCap = base * Movement.slideMaxMult(prof)
	local slide = prof.slide
	return {
		base = base,
		slideCap = slideCap,
		maxPossible = math.max(slideCap, base * (1 + Movement.BhopMaxBonus)),
		boost = if slide and slide.boost then slide.boost else Movement.SlideBoost,
		friction = if slide and slide.friction then slide.friction else Movement.SlideFriction,
		gravity = Workspace.Gravity * (prof.gravityMult or 1),
	}
end

-- Bonus de bunny-hop que le serveur accepte : au plus un hop reçu par crédit, et au plus un hop par MinHopTime.
local function hopBonusAllowed(s: State, now: number): number
	if s.hopCredits <= 0 then
		return 0
	end
	local byCredits = Movement.BhopGainPerHop * s.hopCredits
	local byTime = Movement.BhopGainPerHop * (now - s.chainStart) / G.MinHopTime
	return math.min(Movement.BhopMaxBonus, byCredits, byTime)
end

local function isExempt(player: Player, s: State, now: number): boolean
	if now < s.exemptUntil then
		return true
	end
	local untilServer = player:GetAttribute("MoveExemptUntil")
	return type(untilServer) == "number" and Workspace:GetServerTimeNow() < untilServer
end

local function log(player: Player, s: State, kind: string, data: string)
	local now = os.clock()
	if now - s.lastLog < G.LogEvery then
		return
	end
	s.lastLog = now
	warn(`[MovementGuard] {kind} {player.Name} ({player.UserId}) {data} ping={math.floor(pingOf(player) * 1000)}ms strikes={s.strikes}`)
end

local function addStrike(player: Player, s: State)
	s.strikes += 1
	runStrikes[player.UserId] = (runStrikes[player.UserId] or 0) + 1
end

local function rubberBand(character: Model, root: BasePart, s: State, player: Player)
	s.rubberBands += 1
	local now = os.clock()
	local ping = pingOf(player)
	s.settleFrom = root.Position -- positions envoyées avant le recalage, encore en vol
	s.settleUntil = now + G.TeleportSettle + ping
	character:PivotTo(s.lastValid)
	root.AssemblyLinearVelocity = Vector3.zero
	s.lastPos = s.lastValid.Position
	s.bucket = 0
	s.stall = 0
	s.airborneFor = 0
	s.exemptUntil = now + G.GraceAfterRubberBand + ping
	s.graceAnchor = s.lastValid.Position
	s.graceStart = now
	s.graceKind = "band"
end

-- Sol sous le joueur vu par le serveur (rayon indulgent : 1,5 stud sous les pieds).
local function groundHit(root: BasePart, humanoid: Humanoid): RaycastResult?
	local reach = humanoid.HipHeight + root.Size.Y / 2 + G.GroundReachExtra
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), rayParams)
	if hit and hit.Normal.Y >= Movement.GroundNormalMinY then
		return hit
	end
	return nil
end

-- Appui large pour les contrôles de vol : sphère sous le root, n'importe quelle surface, autres joueurs
-- compris (debout au bord d'un plateau, ou sur la tête d'un coéquipier, n'est pas voler).
local supportParams = RaycastParams.new()
supportParams.FilterType = Enum.RaycastFilterType.Exclude
supportParams.RespectCanCollide = true

local function supported(character: Model, root: BasePart, humanoid: Humanoid): boolean
	supportParams.FilterDescendantsInstances = { character }
	local reach = humanoid.HipHeight + root.Size.Y / 2 + G.GroundReachExtra
	return Workspace:Spherecast(root.Position, G.SupportRadius, Vector3.new(0, -reach, 0), supportParams) ~= nil
end

local function newState(root: BasePart): State
	local pos = root.Position
	return {
		lastPos = pos,
		lastValid = root.CFrame,
		bucket = 0,
		bucketPeak = 0,
		ratioPeak = 0,
		exemptUntil = os.clock() + G.SpawnGrace,
		strikes = 0,
		rubberBands = 0,
		stall = 0,
		hopCredits = 0,
		chainStart = 0,
		lastAirAt = -math.huge,
		lastHopAt = -math.huge,
		slideUntil = 0,
		slideSpeed = 0,
		slideEntryBonus = 0,
		slideSlopeGain = 0,
		slideEndAt = -math.huge,
		lastSlideStart = -math.huge,
		slideProtectUntil = -math.huge,
		padUntil = 0,
		padUsed = false,
		lastValidSlideAt = -math.huge,
		lastGroundAt = os.clock(),
		lastSpeed = 0,
		rebaseNext = false,
		highSince = nil,
		graceAnchor = pos, -- apparition : la grâce part d'ici (RunManager téléporte ensuite via exempt)
		graceStart = os.clock(),
		settleUntil = 0,
		settleFrom = nil,
		graceKind = "spawn",
		pendingSlideJumpAt = nil,
		lastSupportAt = os.clock(),
		slideMemoryUntil = 0,
		stallSpeed = 0,
		stallDir = Vector3.zero,
		lastHopCountAt = -math.huge,
		hopStats = {},
		pendingHopAt = nil,
		pendingSlideAt = nil,
		wasAirborne = false,
		landPeakY = pos.Y,
		airborneFor = 0,
		airStartY = pos.Y,
		airTopY = pos.Y,
		airLowY = pos.Y,
		lastLog = 0,
		dbg = "",
	}
end

local MAX_CREDITS = math.ceil(Movement.BhopMaxBonus / Movement.BhopGainPerHop - 1e-6)

-- Fin de glissade. Comme le client, un saut en fin de glissade garde le bonus d'entrée et convertit seulement
-- l'élan gagné en pente (le boost de départ ne compte pas : sinon glisser en boucle au plat ferait monter le
-- bonus permis). Le hop du saut lui-même arrive par l'événement Hop, qui vérifie le temps en l'air.
local function endSlide(player: Player, s: State, now: number)
	if s.slideUntil > 0 then
		s.slideUntil = 0
		s.slideEndAt = now
		local L = limits(player)
		local gain = Movement.BhopGainPerHop
		local slopeBonus = s.slideSlopeGain / math.max(L.base, 1)
		local target = s.slideEntryBonus + slopeBonus
		local credits = math.min(math.ceil(target / gain - 1e-6), MAX_CREDITS)
		if credits > s.hopCredits then
			if s.hopCredits <= 0 then
				s.chainStart = now - G.MinHopTime
			end
			s.hopCredits = credits
			-- La part gagnée en pente arrive d'un coup : elle ne passe pas par la limite de temps.
			s.chainStart = math.min(s.chainStart, now - math.ceil(slopeBonus / gain - 1e-6) * G.MinHopTime)
		end
		s.slideProtectUntil = math.min(s.slideProtectUntil, now)
	end
	player:SetAttribute("Sliding", false)
	player:SetAttribute("SlideCharge", false)
	player:SetAttribute("SlidePose", false)
end

-- Suivi en l'air : crédits de bunny-hop, chute pour l'atterrissage lourd.
local function trackAir(player: Player, s: State, onGround: boolean, pos: Vector3, now: number)
	if not onGround then
		if not s.wasAirborne then
			s.landPeakY = pos.Y
		end
		s.landPeakY = math.max(s.landPeakY, pos.Y)
		s.lastAirAt = now
	elseif s.wasAirborne then
		local prof = Movement.profile(player:GetAttribute("ClassId"))
		if prof.heavyLanding and s.landPeakY - pos.Y >= G.HeavyFall then
			player:SetAttribute("HeavyLandAt", Workspace:GetServerTimeNow())
		end
	end
	s.wasAirborne = not onGround
	-- Au sol depuis trop longtemps : la chaîne de hops est perdue. Une glissade lancée juste après un saut la
	-- garde un temps limité (enchaîner des glissades au sol ne la prolonge pas).
	if onGround and s.hopCredits > 0 and now - math.max(s.lastAirAt, s.slideProtectUntil) > G.AirMemory then
		s.hopCredits = 0
		player:SetAttribute("HopChain", 0)
	end
end

-- Glissade : la vitesse plausible monte seulement en descendant une pente vue par le serveur (gain x
-- cos entre le déplacement observé et la pente descendante), perd toujours du frottement, et continue de
-- décroître après la fin de la glissade. Le gain de pente est plafonné à ce que le plafond de classe permet.
local function trackSlide(s: State, L: Limits, hit: RaycastResult?, move: Vector3, dt: number)
	local active = s.slideUntil > 0
	if not active and s.slideSpeed <= 0 then
		return
	end
	local floor = L.base * (1 + s.slideEntryBonus)
	if active and hit then
		local n = hit.Normal
		local downhill = Vector3.new(n.X, 0, n.Z)
		local slopeSin = downhill.Magnitude
		local flatMove = Vector3.new(move.X, 0, move.Z)
		if slopeSin > Movement.SlideSlopeMin and flatMove.Magnitude > 0.05 then
			local along = math.max(0, flatMove.Unit:Dot(downhill.Unit))
			local room = math.max(0, L.slideCap - floor - s.slideSlopeGain)
			local gain = math.min(room, L.gravity * Movement.SlideSlopeGain * slopeSin * along * dt * G.SlopeLeniency)
			s.slideSpeed += gain
			s.slideSlopeGain += gain
		end
	end
	s.slideSpeed = math.max(if active then floor else 0, s.slideSpeed - L.friction * G.SlideFrictionLeniency * dt)
	s.slideSpeed = math.min(s.slideSpeed, L.slideCap)
end

-- Glissade acceptée (au sol, recharge et vitesse déjà vérifiées). L'attribut Sliding n'est posé qu'une fois
-- par SlideValidateInterval (Shadowstep, poses, charge) ; entre deux, la glissade est suivie pour la vitesse.
local function acceptSlide(player: Player, s: State, now: number)
	local L = limits(player)
	local prof = Movement.profile(player:GetAttribute("ClassId"))
	local maxFlat = if prof.slide and prof.slide.maxFlatTime then prof.slide.maxFlatTime else Movement.SlideMaxFlatTime
	if now - s.lastAirAt <= G.AirMemory then
		s.slideProtectUntil = now + maxFlat + G.SlideProtectExtra
	end
	s.lastSlideStart = now
	s.slideUntil = now + Movement.SlidingAttrTimeout
	s.slideEntryBonus = hopBonusAllowed(s, now)
	s.slideSlopeGain = 0
	s.slideSpeed = math.min(L.base * (1 + s.slideEntryBonus) * L.boost * G.SlideStartSlack, L.slideCap)
	-- Visuel et charge à chaque glissade acceptée ; l'attribut de gameplay Sliding (Shadowstep) au plus une
	-- fois par SlideValidateInterval (S-08).
	player:SetAttribute("SlidePose", true)
	player:SetAttribute("SlideCharge", prof.slide ~= nil and prof.slide.charge == true)
	if now - s.lastValidSlideAt >= G.SlideValidateInterval then
		s.lastValidSlideAt = now
		player:SetAttribute("Sliding", true)
	end
end

-- Conditions d'une glissade : au sol vu par le serveur, recharge complète, intervalle, vitesse mesurée.
local function slideReady(s: State, now: number, grounded: boolean): boolean
	return s.slideUntil == 0
		and grounded
		and now - s.slideEndAt >= Movement.SlideCooldown * G.SlideCooldownSlack
		and now - s.lastSlideStart >= G.SlideMinInterval
		and s.lastSpeed >= Movement.SlideMinSpeed * G.SlideMinMeasured
end

local function sample(player: Player, dt: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		local dead = states[player]
		if dead and dead.slideUntil > 0 then
			endSlide(player, dead, os.clock())
		end
		return
	end

	local s = states[player]
	if not s then
		states[player] = newState(root)
		return
	end

	local pos = root.Position
	if pos.X ~= pos.X or pos.Y ~= pos.Y or pos.Z ~= pos.Z then
		rubberBand(character, root, s, player)
		return
	end

	local now = os.clock()
	local hit = groundHit(root, humanoid)
	local onGround = hit ~= nil
	if onGround then
		s.lastGroundAt = now
	end
	player:SetAttribute("Airborne", not onGround)
	if s.slideUntil > 0 and now > s.slideUntil then
		endSlide(player, s, now)
	end
	trackAir(player, s, onGround, pos, now)
	local L = limits(player)
	trackSlide(s, L, hit, pos - s.lastPos, dt)

	-- Près d'un tremplin : vitesse permise relevée un moment (le client applique le lancer). Ce n'est pas
	-- une exemption : le téléport et le seau restent contrôlés.
	local layout = Heightmap.getLayout()
	if layout then
		local nearPad = false
		for _, pad in layout.pads do
			local dx, dz = pos.X - pad.x, pos.Z - pad.z
			if dx * dx + dz * dz < G.PadRadius * G.PadRadius then
				nearPad = true
				break
			end
		end
		if nearPad and not s.padUsed then
			s.padUntil = now + G.PadGrace -- une fois par atterrissage
			s.padUsed = true
		elseif not nearPad and onGround and now >= s.padUntil then
			s.padUsed = false
		end
	end
	-- Exemptions (mouvement causé par le serveur, grâce après recalage ou apparition), siège, ancré,
	-- à-coup serveur : pas de seau, mais le déplacement reste borné (S-02). Le déplacement imposé par le
	-- serveur lui-même (exempt() ou MoveExemptUntil posés juste avant un PivotTo) est accepté une fois.
	-- La position valide n'avance pas pendant une exemption.
	if isExempt(player, s, now) or root.Anchored or humanoid.SeatPart ~= nil or dt > G.HitchFactor * G.Interval then
		local pingE = pingOf(player)
		local graceTime = now - s.graceStart + dt + pingE
		if s.rebaseNext then
			-- Déplacement imposé par le serveur (exempt() ou MoveExemptUntil juste avant un PivotTo) : la nouvelle
			-- position devient l'ancre et la position valide ; l'ancienne reste acceptée le temps que les positions
			-- du client encore en vol arrivent.
			s.rebaseNext = false
			s.settleFrom = s.lastPos
			s.settleUntil = now + G.TeleportSettle + pingE
			s.graceAnchor = pos
			s.graceStart = now
			s.graceKind = "server"
			s.lastValid = root.CFrame
		else
			-- Distance cumulée depuis l'ancre : réécrire sa position à chaque image ne déplace pas la base.
			-- Apparition et recalage : vitesse normale (A11) ; déplacement serveur : vitesse max + lancement.
			local anchor = s.graceAnchor or s.lastPos
			local bound
			if s.graceKind == "server" then
				bound = L.maxPossible * graceTime * G.GraceSpeedFactor + G.ExemptLaunchStuds
			else
				bound = L.base * (1 + hopBonusAllowed(s, now)) * G.Margin * graceTime + G.SlackStuds
			end
			local ok = flatDist(pos, anchor) <= bound
			local from = s.settleFrom
			if not ok and from and now < s.settleUntil then
				ok = flatDist(pos, from) <= L.base * (1 + hopBonusAllowed(s, now)) * G.Margin * graceTime + G.SlackStuds
			end
			if not ok then
				addStrike(player, s)
				log(player, s, "exempt-step", `fromAnchor={math.floor(flatDist(pos, anchor))} bound={math.floor(bound)} kind={s.graceKind}`)
				if G.Enforce then
					rubberBand(character, root, s, player)
					return
				end
			end
		end
		s.lastPos = pos
		s.bucket = 0
		s.stall = 0
		s.airborneFor = 0
		s.highSince = nil
		s.lastSupportAt = now -- un long trajet imposé par le serveur ne compte pas comme du vol
		return
	end
	s.graceAnchor = nil
	local onPad = now < s.padUntil

	local bonus = hopBonusAllowed(s, now)
	local vlim = L.base * (1 + bonus)
	local sliding = s.slideUntil > 0 or now < s.slideMemoryUntil
	if sliding then
		vlim = math.max(vlim, s.slideSpeed)
	end
	if onPad then
		vlim = math.max(vlim, G.PadMaxSpeed)
	end
	-- Ralentis (à terre, choix de carte) appliqués aussi par le serveur (S-14).
	local slowMult = player:GetAttribute("SlowMult")
	local slowUntil = player:GetAttribute("SlowUntil")
	if type(slowMult) == "number" and type(slowUntil) == "number" and Workspace:GetServerTimeNow() < slowUntil then
		vlim *= math.clamp(slowMult, 0.05, 1)
	end
	if Workspace:GetAttribute("CohueHazard") == "Sandstorm" then
		vlim += G.SandstormPush
	end
	local ping = pingOf(player)
	local horizontal = Vector3.new(pos.X - s.lastPos.X, 0, pos.Z - s.lastPos.Z).Magnitude

	-- Temps couvert par cet échantillon : dt + le gel qui le précède (rattrapage de réplication).
	local span = dt + math.min(s.stall, G.StallCap)
	-- Rattrapage après un gel : autant que la vitesse répliquée pendant le gel, et dans sa direction.
	local catchUp = 0
	local moveFlat = Vector3.new(pos.X - s.lastPos.X, 0, pos.Z - s.lastPos.Z)
	if s.stall > 0 and horizontal > 0.05 and moveFlat.Unit:Dot(s.stallDir) >= G.StallDirDot then
		catchUp = math.min(s.stallSpeed, vlim) * math.min(s.stall, G.StallCap) * G.Margin
	end
	s.lastSpeed = horizontal / span
	local pendingSlide = s.pendingSlideAt
	if pendingSlide then
		if now - pendingSlide > G.SlidePendDefer then
			s.pendingSlideAt = nil
		elseif slideReady(s, now, onGround or now - s.lastGroundAt <= G.HopLandWindow) then
			s.pendingSlideAt = nil
			acceptSlide(player, s, now)
			vlim = math.max(vlim, s.slideSpeed)
		end
	end

	-- 1. Téléport : un pas très au-delà de tout ce qui est possible, même après un gel.
	local teleportLimit = math.max(G.TeleportMinStuds, L.maxPossible * (span + ping) * G.TeleportFactor)
	if horizontal > teleportLimit then
		addStrike(player, s)
		log(player, s, "teleport", `step={math.floor(horizontal)} limit={math.floor(teleportLimit)}`)
		if G.Enforce then
			rubberBand(character, root, s, player)
		else
			s.lastPos = pos
			s.stall = 0
		end
		return
	end

	-- 2. Vitesse : seau de distance. Un pas plus court que permis laisse un crédit (au plus CreditSeconds de
	-- course) : les positions répliquées arrivent par paquets, un pas court précède souvent un pas long.
	-- Le ping agrandit le seau (une fois), pas chaque pas.
	local allowed = vlim * G.Margin * dt + G.SlackStuds + catchUp
	local delta = horizontal - allowed
	local excess = math.max(0, delta)
	local stalledBreach = s.stall > 0 and excess > G.StallBreachStuds
	local credit = vlim * G.CreditSeconds
	if delta > 0 then
		s.bucket = math.max(-credit, s.bucket + delta - G.LeakPerSecond * dt)
	else
		s.bucket = math.max(-credit, s.bucket + delta)
	end
	s.bucketPeak = math.max(s.bucketPeak, s.bucket)
	if IS_STUDIO then
		s.ratioPeak = math.max(s.ratioPeak, horizontal / math.max(vlim * span, 0.01))
		s.dbg = string.format("step=%.2f allowed=%.2f vlim=%.1f bonus=%.2f credits=%d slide=%s/%.1f bucket=%.1f ground=%s", horizontal, allowed, vlim, bonus, s.hopCredits, tostring(sliding), s.slideSpeed, s.bucket, tostring(onGround))
	end
	local v = root.AssemblyLinearVelocity
	local flatV = Vector3.new(v.X, 0, v.Z)
	if horizontal < G.StallMoveStuds and flatV.Magnitude > G.StallMinVelocity then
		-- immobile pour le serveur mais en mouvement d'après la vitesse : réplication gelée
		s.stallSpeed = if s.stall > 0 then math.min(s.stallSpeed, flatV.Magnitude) else flatV.Magnitude
		s.stallDir = flatV.Unit
		s.stall += dt
	else
		s.stall = 0
	end
	if s.bucket > G.BucketMax + vlim * ping * G.JitterPing * 4 or stalledBreach then
		addStrike(player, s)
		log(player, s, "speed", `step={string.format("%.1f", horizontal)} allowed={string.format("%.1f", allowed)} vlim={string.format("%.1f", vlim)} bonus={string.format("%.2f", bonus)}`)
		if G.Enforce then
			rubberBand(character, root, s, player)
			return
		end
		s.bucket = 0
	end

	-- 3. Vertical (S-01). Montée par échantillon bornée par la vitesse de saut de la classe ; et pas plus de
	-- FlyHeight au-dessus du sol du plan pendant plus de FlyTime sans que le rayon serveur voie un sol.
	local prof = Movement.profile(player:GetAttribute("ClassId"))
	if not onPad then
		local rise = pos.Y - s.lastPos.Y
		local v0 = math.sqrt(2 * L.gravity * Movement.jumpHeight(prof))
		local riseLimit = v0 * span * G.RiseMargin + G.RiseSlackStuds
		if rise > riseLimit then
			addStrike(player, s)
			log(player, s, "rise", `rise={string.format("%.1f", rise)} limit={string.format("%.1f", riseLimit)}`)
			if G.HoverEnforce then
				rubberBand(character, root, s, player)
				return
			end
		end
		local aboveGround = pos.Y - Heightmap.getY(pos.X, pos.Z)
		if not onGround and layout and aboveGround > G.FlyHeight and not supported(character, root, humanoid) then
			s.highSince = s.highSince or now
			if now - (s.highSince :: number) > G.FlyTime then
				addStrike(player, s)
				log(player, s, "high", `above={string.format("%.1f", aboveGround)} for={string.format("%.1f", now - (s.highSince :: number))}s`)
				s.highSince = nil
				if G.HoverEnforce then
					rubberBand(character, root, s, player)
					return
				end
			end
		else
			s.highSince = nil
		end
	else
		s.highSince = nil
	end

	if onPad then
		s.lastSupportAt = now
	elseif now - s.lastSupportAt > G.MaxAirTime then
		addStrike(player, s)
		log(player, s, "airtime", `air={string.format("%.1f", now - s.lastSupportAt)}s`)
		s.lastSupportAt = now
		if G.HoverEnforce then
			rubberBand(character, root, s, player)
			return
		end
	end

	-- 4. Vol stationnaire et vol : en l'air longtemps sans amplitude verticale (un bunny-hop oscille de
	-- plusieurs studs, le plané descend), ou monté bien plus haut qu'un saut de la classe.
	if onGround or onPad then
		s.airborneFor = 0
		s.airStartY = pos.Y
	else
		if s.airborneFor == 0 then
			s.airStartY = s.lastPos.Y
			s.airTopY = math.max(pos.Y, s.lastPos.Y)
			s.airLowY = math.min(pos.Y, s.lastPos.Y)
		end
		s.airborneFor += dt
		s.airTopY = math.max(s.airTopY, pos.Y)
		s.airLowY = math.min(s.airLowY, pos.Y)
		local jumps = 1 + (prof.airJumps or 0) * Movement.AirJumpMult
		local flyLimit = Movement.jumpHeight(prof) * jumps + G.FlyMargin
		local hovering = s.airborneFor > G.HoverLimit
			and (s.airTopY - s.airLowY) < G.HoverRange
			and not supported(character, root, humanoid)
		local flying = pos.Y - s.airStartY > flyLimit
		if hovering or flying then
			addStrike(player, s)
			log(player, s, if flying then "fly" else "hover", `air={string.format("%.1f", s.airborneFor)}s rise={string.format("%.1f", pos.Y - s.airStartY)} range={string.format("%.1f", s.airTopY - s.airLowY)}`)
			if G.HoverEnforce then
				rubberBand(character, root, s, player)
				return
			end
			s.airborneFor = 0
		end
	end

	s.lastPos = pos
	-- Seules les positions au sol et plausibles deviennent des cibles de recalage.
	if onGround and excess == 0 then
		s.lastValid = root.CFrame
	end
end

-- ---------------------------------------------------------------- API

-- À appeler avant tout mouvement causé par le serveur (tremplin, geyser, tyrolienne, téléport, recul).
function MovementGuard.exempt(player: Player, seconds: number, _reason: string?)
	local s = states[player]
	if s and type(seconds) == "number" then
		s.exemptUntil = math.max(s.exemptUntil, os.clock() + math.clamp(seconds, 0, 30))
		s.rebaseNext = true -- le déplacement que le serveur va imposer est accepté une fois
	end
end

-- Strikes depuis le début de la run en cours (quarantaine du classement, regles-v2 §4.5).
function MovementGuard.getRunStrikes(player: Player): number
	return runStrikes[player.UserId] or 0
end

-- Dernière position au sol jugée valide par le serveur (reset de A04), ou nil.
function MovementGuard.getLastValidPosition(player: Player): Vector3?
	local s = states[player]
	return if s then s.lastValid.Position else nil
end

function MovementGuard.getStrikes(player: Player): number
	local s = states[player]
	return if s then s.strikes else 0
end

-- ---------------------------------------------------------------- MoveEvent (C->S)

local function creditHop(player: Player, s: State, hopAt: number)
	if hopAt - s.lastHopCountAt < G.MinHopTime then
		s.hopStats.rate = (s.hopStats.rate or 0) + 1
		return -- au plus un hop compté par MinHopTime
	end
	s.lastHopCountAt = hopAt
	s.hopStats.ok = (s.hopStats.ok or 0) + 1
	if s.hopCredits <= 0 then
		s.chainStart = hopAt - G.MinHopTime
	end
	s.hopCredits = math.min(s.hopCredits + 1, MAX_CREDITS)
	local chain = player:GetAttribute("HopChain")
	player:SetAttribute("HopChain", (if type(chain) == "number" then chain else 0) + 1)
	local ProgressionService = Registry.find("ProgressionService")
	if ProgressionService then
		pcall(ProgressionService.recordStat, player, "Hops", 1)
	end
end

-- Sonde de sol à chaque image (un rayon par joueur) : les contacts au sol d'un bunny-hop durent ~0,05 s,
-- trop court pour l'échantillon à 4 Hz. Règle aussi les Hop en attente.
local function probeGround(player: Player, now: number)
	local s = states[player]
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not s or not humanoid or not root then
		return
	end
	local grounded = groundHit(root, humanoid) ~= nil
	if grounded then
		s.lastGroundAt = now
		s.lastSupportAt = now
		local pending = s.pendingHopAt
		if pending then
			s.pendingHopAt = nil
			creditHop(player, s, pending)
		end
	else
		if now - s.lastSupportAt > 1 and supported(character :: Model, root, humanoid) then
			s.lastSupportAt = now -- bord de plateau, tête d'un coéquipier : appuyé, pas en vol
		end
		if s.pendingHopAt and now - (s.pendingHopAt :: number) > G.HopLandDefer then
			s.pendingHopAt = nil
			s.hopStats.noLand = (s.hopStats.noLand or 0) + 1
		end
	end
	-- Saut de glissade : crédité (et son élan permis) seulement quand le serveur voit le joueur décoller.
	local slideJump = s.pendingSlideJumpAt
	if slideJump then
		if not grounded and now - slideJump <= G.SlideJumpDefer then
			s.pendingSlideJumpAt = nil
			s.slideMemoryUntil = now + G.SlideMemory
			s.lastAirAt = now
			creditHop(player, s, slideJump)
		elseif now - slideJump > G.SlideJumpDefer then
			s.pendingSlideJumpAt = nil
			s.hopStats.noAir = (s.hopStats.noAir or 0) + 1
		end
	end
end

local function onMoveEvent(player: Player, kind: any)
	if type(kind) ~= "string" then
		return
	end
	local s = states[player]
	if not s then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	local now = os.clock()
	local run = Registry.find("RunManager")
	if (kind == "SlideStart" or kind == "Hop") and run and run.isDowned then
		local ok, downed = pcall(run.isDowned, player)
		if ok and downed then
			return -- à terre : ni glissade ni hop
		end
	end
	if kind == "SlideStart" then
		-- Au sol, recharge respectée, vitesse mesurée par le serveur suffisante (S-08). Si seule la vitesse
		-- manque (départ presque à l'arrêt, positions répliquées en retard), la glissade attend SlidePendDefer
		-- secondes que l'échantillon serveur la voie.
		-- Toujours mis en attente puis accepté dès que les conditions sont vues (positions en retard, recharge
		-- mesurée à la réception) ; abandonné après SlidePendDefer.
		if s.slideUntil == 0 then
			s.pendingSlideAt = now
			if slideReady(s, now, groundHit(root, humanoid) ~= nil or now - s.lastGroundAt <= G.HopLandWindow) then
				s.pendingSlideAt = nil
				acceptSlide(player, s, now)
			end
		end
	elseif kind == "SlideEnd" then
		s.pendingSlideAt = nil
		endSlide(player, s, now)
	elseif kind == "Hop" then
		if now - s.lastHopAt < Movement.HopMinInterval then
			return
		end
		s.lastHopAt = now
		-- Saut depuis une glissade (le client n'envoie pas SlideEnd dans ce cas) : la glissade se termine, et le
		-- hop n'est crédité, son élan permis, que lorsque le serveur voit ensuite le joueur décoller.
		if s.slideUntil > 0 or now - s.slideEndAt <= G.SlideHopGrace then
			s.pendingSlideAt = nil
			if s.slideUntil > 0 then
				endSlide(player, s, now)
			end
			s.pendingSlideJumpAt = now
			return
		end
		-- Sinon, un hop ne crédite le bonus que si le serveur a vu le joueur en l'air récemment...
		if now - s.lastAirAt > G.AirMemory + G.HopAirSlack then
			s.hopStats.noAir = (s.hopStats.noAir or 0) + 1
			return -- pas vu en l'air : ni crédit, ni statistique
		end
		-- ...puis au sol (S-08). Les positions répliquées peuvent arriver après l'événement : sans sol vu tout
		-- de suite, le hop attend HopLandDefer secondes que la sonde de sol (à chaque image) le voie.
		if now - s.lastGroundAt <= G.HopLandWindow or groundHit(root, humanoid) then
			creditHop(player, s, now)
		else
			if s.pendingHopAt then
				s.hopStats.noLand = (s.hopStats.noLand or 0) + 1 -- le précédent n'a jamais vu le sol
			end
			s.pendingHopAt = now
		end
	elseif kind == "HopReset" then
		s.hopCredits = 0
		player:SetAttribute("HopChain", 0)
	end
end

-- ---------------------------------------------------------------- cycle de vie

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function()
		states[player] = nil -- état neuf (avec la grâce d'apparition) au prochain échantillon
		player:SetAttribute("Sliding", false)
		player:SetAttribute("SlideCharge", false)
		player:SetAttribute("SlidePose", false)
		player:SetAttribute("HopChain", 0)
		task.defer(refreshFilter)
	end)
	player.CharacterRemoving:Connect(function()
		task.defer(refreshFilter)
	end)
	player:GetAttributeChangedSignal("MoveExemptUntil"):Connect(function()
		local s = states[player]
		if s then
			s.rebaseNext = true
		end
	end)
end

function MovementGuard.init()
	Net.onServerEvent("MoveEvent", Movement.MoveEventRate, onMoveEvent)
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		task.defer(refreshFilter)
	end)
end

function MovementGuard.start()
	local Bus = require(script.Parent.Parent:WaitForChild("Bus")) :: any
	Bus.RunStarted:connect(function()
		table.clear(runStrikes)
	end)
	if IS_STUDIO then
		-- Point d'inspection pour les tests MCP : état du garde par joueur.
		local bf = Instance.new("BindableFunction")
		bf.Name = "CohueGuardDebug"
		bf.OnInvoke = function(cmd: any): any
			local out = {}
			for p, st in states do
				if cmd == "reset" then
					st.bucketPeak, st.ratioPeak, st.strikes, st.rubberBands = 0, 0, 0, 0
					st.hopStats = {}
				end
				out[p.Name] = { strikes = st.strikes, rubberBands = st.rubberBands, bucket = st.bucket, bucketPeak = st.bucketPeak, ratioPeak = st.ratioPeak, credits = st.hopCredits, hops = st.hopStats, last = st.dbg }
			end
			return out
		end
		bf.Parent = game:GetService("ServerScriptService")
	end
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	refreshFilter()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		local clock = os.clock()
		for player in states do
			probeGround(player, clock)
		end
		acc += dt
		if acc < G.Interval then
			return
		end
		local stepDt = acc
		acc = 0
		for _, player in Players:GetPlayers() do
			local ok, err = pcall(sample, player, stepDt)
			if not ok then
				warn(`[MovementGuard] sample failed for {player.Name}: {err}`)
			end
		end
	end)
end

return MovementGuard
