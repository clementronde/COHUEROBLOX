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
-- Lecture : MovementGuard.getStrikes(player) -> number

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
	warn(`[MovementGuard] {kind} {player.Name} ({player.UserId}) {data} ping={math.floor(player:GetNetworkPing() * 1000)}ms strikes={s.strikes}`)
end

local function rubberBand(character: Model, root: BasePart, s: State, player: Player)
	s.rubberBands += 1
	character:PivotTo(s.lastValid)
	root.AssemblyLinearVelocity = Vector3.zero
	s.lastPos = s.lastValid.Position
	s.bucket = 0
	s.stall = 0
	s.airborneFor = 0
	s.exemptUntil = os.clock() + G.GraceAfterRubberBand + math.clamp(player:GetNetworkPing(), 0, G.PingCap)
end

-- Sol sous le joueur vu par le serveur (rayon indulgent : 1,5 stud sous les pieds).
local function groundHit(root: BasePart, humanoid: Humanoid): RaycastResult?
	local reach = humanoid.HipHeight + root.Size.Y / 2 + 1.5
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), rayParams)
	if hit and hit.Normal.Y >= Movement.GroundNormalMinY then
		return hit
	end
	return nil
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

-- Glissade : la vitesse plausible monte seulement sur une pente vue par le serveur.
local function trackSlide(s: State, L: Limits, hit: RaycastResult?, dt: number)
	if s.slideUntil <= 0 or not hit then
		return
	end
	local n = hit.Normal
	local slopeSin = Vector3.new(n.X, 0, n.Z).Magnitude
	if slopeSin > Movement.SlideSlopeMin then
		local gain = L.gravity * Movement.SlideSlopeGain * slopeSin * dt * G.SlopeLeniency
		s.slideSpeed += gain
		s.slideSlopeGain += gain
	else
		-- Au plat, une glissade perd de la vitesse (frottement compté à moitié par prudence).
		local floor = L.base * (1 + s.slideEntryBonus)
		s.slideSpeed = math.max(floor, s.slideSpeed - L.friction * G.SlideFrictionLeniency * dt)
	end
	s.slideSpeed = math.min(s.slideSpeed, L.slideCap)
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
	player:SetAttribute("Airborne", not onGround)
	if s.slideUntil > 0 and now > s.slideUntil then
		endSlide(player, s, now)
	end
	trackAir(player, s, onGround, pos, now)
	local L = limits(player)
	trackSlide(s, L, hit, dt)

	-- Près d'un tremplin : vitesse permise relevée un moment (le client applique le lancer). Ce n'est pas
	-- une exemption : le téléport et le seau restent contrôlés.
	local layout = Heightmap.getLayout()
	if layout then
		for _, pad in layout.pads do
			local dx, dz = pos.X - pad.x, pos.Z - pad.z
			if dx * dx + dz * dz < G.PadRadius * G.PadRadius then
				s.padUntil = now + G.PadGrace
				break
			end
		end
	end
	-- Recaler la base seulement : exemptions (mouvement causé par le serveur), siège, ancré, à-coup serveur.
	-- La position valide n'avance pas pendant une exemption.
	if isExempt(player, s, now) or root.Anchored or humanoid.SeatPart ~= nil or dt > G.HitchFactor * G.Interval then
		s.lastPos = pos
		s.bucket = 0
		s.stall = 0
		s.airborneFor = 0
		return
	end
	local onPad = now < s.padUntil

	local bonus = hopBonusAllowed(s, now)
	local vlim = L.base * (1 + bonus)
	local sliding = s.slideUntil > 0 or now - s.slideEndAt <= G.SlideMemory
	if sliding then
		vlim = math.max(vlim, s.slideSpeed)
	end
	if onPad then
		vlim = math.max(vlim, G.PadMaxSpeed)
	end
	if Workspace:GetAttribute("CohueHazard") == "Sandstorm" then
		vlim += G.SandstormPush
	end
	local ping = math.clamp(player:GetNetworkPing(), 0, G.PingCap)
	local horizontal = Vector3.new(pos.X - s.lastPos.X, 0, pos.Z - s.lastPos.Z).Magnitude

	-- Temps couvert par cet échantillon : dt + le gel qui le précède (rattrapage de réplication).
	local span = dt + math.min(s.stall, G.StallCap)

	-- 1. Téléport : un pas très au-delà de tout ce qui est possible, même après un gel.
	local teleportLimit = math.max(G.TeleportMinStuds, L.maxPossible * (span + ping) * G.TeleportFactor)
	if horizontal > teleportLimit then
		s.strikes += 1
		log(player, s, "teleport", `step={math.floor(horizontal)} limit={math.floor(teleportLimit)}`)
		if G.Enforce then
			rubberBand(character, root, s, player)
		else
			s.lastPos = pos
			s.stall = 0
		end
		return
	end

	-- 2. Vitesse : seau percé de l'excès de distance.
	local allowed = vlim * G.Margin * span + G.SlackStuds + vlim * ping * G.JitterPing
	local excess = math.max(0, horizontal - allowed)
	s.bucket = math.max(0, s.bucket + excess - G.LeakPerSecond * dt)
	s.bucketPeak = math.max(s.bucketPeak, s.bucket)
	if IS_STUDIO then
		s.ratioPeak = math.max(s.ratioPeak, horizontal / math.max(vlim * span, 0.01))
		s.dbg = string.format("step=%.2f allowed=%.2f vlim=%.1f bonus=%.2f credits=%d slide=%s/%.1f bucket=%.1f ground=%s", horizontal, allowed, vlim, bonus, s.hopCredits, tostring(sliding), s.slideSpeed, s.bucket, tostring(onGround))
	end
	local v = root.AssemblyLinearVelocity
	if horizontal < G.StallMoveStuds and Vector3.new(v.X, 0, v.Z).Magnitude > G.StallMinVelocity then
		s.stall += dt -- immobile pour le serveur mais en mouvement d'après la vitesse : réplication gelée
	else
		s.stall = 0
	end
	if s.bucket > G.BucketMax then
		s.strikes += 1
		log(player, s, "speed", `step={string.format("%.1f", horizontal)} allowed={string.format("%.1f", allowed)} vlim={string.format("%.1f", vlim)} bonus={string.format("%.2f", bonus)}`)
		if G.Enforce then
			rubberBand(character, root, s, player)
			return
		end
		s.bucket = 0
	end

	-- 3. Vol stationnaire et vol : en l'air longtemps sans amplitude verticale (un bunny-hop oscille de
	-- plusieurs studs, le plané descend), ou monté bien plus haut qu'un saut de la classe. Mode ombre par défaut.
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
		local prof = Movement.profile(player:GetAttribute("ClassId"))
		local jumps = 1 + (prof.airJumps or 0) * Movement.AirJumpMult
		local flyLimit = Movement.jumpHeight(prof) * jumps + G.FlyMargin
		local hovering = s.airborneFor > G.HoverLimit and (s.airTopY - s.airLowY) < G.HoverRange
		local flying = pos.Y - s.airStartY > flyLimit
		if hovering or flying then
			s.strikes += 1
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
	end
end

function MovementGuard.getStrikes(player: Player): number
	local s = states[player]
	return if s then s.strikes else 0
end

-- ---------------------------------------------------------------- MoveEvent (C->S)

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
	if kind == "SlideStart" then
		-- Depuis le sol seulement, et pas en rafale. La vitesse plausible part de la course actuelle x boost.
		local cooled = now - s.slideEndAt >= Movement.SlideCooldown * G.SlideCooldownSlack
		if now - s.lastSlideStart >= G.SlideMinInterval and cooled and s.slideUntil == 0 and groundHit(root, humanoid) then
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
			player:SetAttribute("Sliding", true)
			player:SetAttribute("SlideCharge", prof.slide ~= nil and prof.slide.charge == true)
		end
	elseif kind == "SlideEnd" then
		endSlide(player, s, now)
	elseif kind == "Hop" then
		if now - s.lastHopAt < Movement.HopMinInterval then
			return
		end
		s.lastHopAt = now
		-- Un hop ne crédite le bonus que si le serveur a vu le joueur en l'air récemment.
		if now - s.lastAirAt > G.AirMemory + G.HopAirSlack then
			return -- pas vu en l'air : ni crédit, ni statistique
		end
		if s.hopCredits <= 0 then
			s.chainStart = now - G.MinHopTime
		end
		s.hopCredits = math.min(s.hopCredits + 1, MAX_CREDITS)
		local chain = player:GetAttribute("HopChain")
		player:SetAttribute("HopChain", (if type(chain) == "number" then chain else 0) + 1)
		local ProgressionService = Registry.find("ProgressionService")
		if ProgressionService then
			pcall(ProgressionService.recordStat, player, "Hops", 1)
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
		player:SetAttribute("HopChain", 0)
		task.defer(refreshFilter)
	end)
	player.CharacterRemoving:Connect(function()
		task.defer(refreshFilter)
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
	if IS_STUDIO then
		-- Point d'inspection pour les tests MCP : état du garde par joueur.
		local bf = Instance.new("BindableFunction")
		bf.Name = "CohueGuardDebug"
		bf.OnInvoke = function(cmd: any): any
			local out = {}
			for p, st in states do
				if cmd == "reset" then
					st.bucketPeak, st.ratioPeak, st.strikes, st.rubberBands = 0, 0, 0, 0
				end
				out[p.Name] = { strikes = st.strikes, rubberBands = st.rubberBands, bucket = st.bucket, bucketPeak = st.bucketPeak, ratioPeak = st.ratioPeak, credits = st.hopCredits, last = st.dbg }
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
