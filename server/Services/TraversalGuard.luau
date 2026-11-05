--!strict
-- TraversalGuard (A06-07, domaine avatar) : exemptions de MovementGuard pour les tremplins, geysers et
-- tyroliennes posés par le level design. Module simple, appelé par MovementGuard à chaque image avant ses
-- échantillons (l'exemption est donc posée avant que le garde voie la montée). Design : dossier 50 §11.
--
-- Le client applique le mouvement (TraversalController) ; ici le serveur ne fait que constater, avec ses
-- propres positions, que le joueur est bien dans la zone d'un objet du serveur, puis appelle
-- MovementGuard.exempt pour la durée du trajet, et la termine dès qu'il le voit fini :
--   Tremplin / geyser : une fois par entrée dans la zone (tremplin) ou par éruption (geyser). Exemption =
--     temps de vol calculé + marge, au plus MaxFlight ; finie EndGrace après un sol vu (au moins MinFlight).
--   Tyrolienne : près de Start ; exemption = longueur / vitesse + marge ; finie dès que le joueur s'éloigne
--     du câble, n'avance pas le long du câble, ou arrive au bout.
-- Pendant l'exemption, MovementGuard borne toujours la distance à l'ancre (vitesse max x temps x 1,2 + 12
-- studs, S-02) : les vitesses de lancer et de tyrolienne sont plafonnées en dessous (Config.Movement.Traversal).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Movement = require(Shared:WaitForChild("Config"):WaitForChild("Movement"))
local Traversal = require(Shared:WaitForChild("Traversal"))

local T = Movement.Traversal
local IS_STUDIO = RunService:IsStudio()

export type GuardApi = {
	exempt: (Player, number, string?) -> (),
	endExempt: (Player, number?) -> (),
}

type Active = {
	kind: string, -- "pad" | "geyser" | "zipline"
	startedAt: number,
	zipline: Traversal.Zipline?,
}

type PState = {
	active: Active?,
	usedPad: Instance?,
	usedEruption: { [Instance]: number },
	rideEndedAt: number,
}

local TraversalGuard = {}

local states: { [Player]: PState } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local function stateOf(player: Player): PState
	local s = states[player]
	if not s then
		s = { active = nil, usedPad = nil, usedEruption = {}, rideEndedAt = -math.huge }
		states[player] = s
	end
	return s
end

local function pingOf(player: Player): number
	local ping = player:GetNetworkPing()
	if IS_STUDIO then
		local test = Workspace:GetAttribute("CohueTestPing")
		if type(test) == "number" then
			ping = test
		end
	end
	return math.clamp(ping, 0, Movement.Guard.PingCap)
end

local function grounded(character: Model, root: BasePart, humanoid: Humanoid): boolean
	rayParams.FilterDescendantsInstances = { character }
	local reach = humanoid.HipHeight + root.Size.Y / 2 + Movement.Guard.GroundReachExtra
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), rayParams)
	return hit ~= nil and hit.Normal.Y >= Movement.GroundNormalMinY
end

local function trace(player: Player, msg: string)
	if IS_STUDIO then
		print(`[TraversalGuard] {player.Name} {msg}`)
	end
end

local function launch(api: GuardApi, player: Player, s: PState, kind: string, height: number, now: number)
	local flight = Traversal.flightTime(height, Workspace.Gravity) + T.FlightSlack + pingOf(player)
	local prof = Movement.profile(player:GetAttribute("ClassId"))
	if prof.glide then
		flight += prof.glide.duration -- le plané rallonge la descente
	end
	api.exempt(player, math.min(flight, T.MaxFlight), kind)
	s.active = { kind = kind, startedAt = now, zipline = nil }
	trace(player, `{kind} h={height} exempt={string.format("%.1f", math.min(flight, T.MaxFlight))}s`)
end

local function finish(api: GuardApi, player: Player, s: PState, grace: number, why: string)
	local a = s.active
	if not a then
		return
	end
	s.active = nil
	if a.kind == "zipline" then
		s.rideEndedAt = os.clock()
	end
	api.endExempt(player, grace)
	trace(player, `{a.kind} end ({why})`)
end

local function stepPlayer(api: GuardApi, player: Player, set: Traversal.Set, now: number, serverNow: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		states[player] = nil
		return
	end
	local s = stateOf(player)
	local pos = root.Position
	local ping = pingOf(player)
	local a = s.active

	-- Réarmement des tremplins, même pendant un vol : dès que le joueur sort de la zone exacte du client
	-- (le client relance à chaque nouvelle entrée, le serveur doit réarmer au moins aussi tôt que lui).
	if s.usedPad then
		local inBase = false
		for _, pad in set.pads do
			if Traversal.inZone(pos, pad.top, pad.radius, 0, 0) then
				inBase = true
				break
			end
		end
		if not inBase then
			s.usedPad = nil
		end
	end

	-- Trajet en cours : le finir dès qu'on le voit fini.
	if a then
		local elapsed = now - a.startedAt
		local z = a.zipline
		if z then
			local t, dist = Traversal.project(z, pos)
			local lag = T.ZiplineLagStart + ping
			local expected = math.max(0, (elapsed - lag) * z.speed / z.length)
			if dist > T.ZiplineOffLine then
				finish(api, player, s, T.EndGrace, "off cable")
			elseif t >= 0.98 then
				finish(api, player, s, T.EndGrace, "arrived")
			elseif elapsed > lag and t < expected * T.ZiplineProgressMin then
				finish(api, player, s, 0, "not moving along")
			end
		elseif elapsed >= T.MinFlight and grounded(character, root, humanoid) then
			finish(api, player, s, T.EndGrace, "landed")
		end
		return
	end

	-- Tremplins : une fois par entrée, sur la zone élargie (positions en retard) ; réarmement plus haut.
	for _, pad in set.pads do
		if s.usedPad ~= pad.inst and Traversal.inZone(pos, pad.top, pad.radius, T.ServerExtraRadius, T.ServerExtraHeight) then
			s.usedPad = pad.inst
			launch(api, player, s, "pad", pad.height, now)
			return
		end
	end

	-- Geysers : une fois par éruption, avec un peu de retard permis (positions en vol).
	for _, g in set.geysers do
		local _, index, phase = Traversal.eruption(g, serverNow)
		if phase < g.active + T.GeyserLateSlack + ping and s.usedEruption[g.inst] ~= index then
			if Traversal.inZone(pos, g.top, g.radius, T.ServerExtraRadius, T.ServerExtraHeight) then
				s.usedEruption[g.inst] = index
				launch(api, player, s, "geyser", g.height, now)
				return
			end
		end
	end

	-- Tyroliennes : près de Start, recharge respectée.
	if now - s.rideEndedAt >= T.ZiplineCooldown then
		local hand = pos + Vector3.new(0, T.ZiplineHang, 0)
		for _, z in set.ziplines do
			if (hand - z.a).Magnitude <= T.ZiplineGrab + T.ServerExtraRadius then
				local seconds = z.length / z.speed + T.FlightSlack + ping
				api.exempt(player, math.min(seconds, 30), "zipline")
				s.active = { kind = "zipline", startedAt = now, zipline = z }
				trace(player, `zipline len={math.floor(z.length)} exempt={string.format("%.1f", seconds)}s`)
				return
			end
		end
	end
end

-- Appelé par MovementGuard à chaque Heartbeat, avant ses échantillons.
function TraversalGuard.step(api: GuardApi)
	local set = Traversal.get()
	if #set.pads == 0 and #set.geysers == 0 and #set.ziplines == 0 and next(states) == nil then
		return
	end
	local now = os.clock()
	local serverNow = Workspace:GetServerTimeNow()
	for _, player in Players:GetPlayers() do
		local ok, err = pcall(stepPlayer, api, player, set, now, serverNow)
		if not ok then
			warn(`[TraversalGuard] step failed for {player.Name}: {err}`)
		end
	end
end

-- Trajet en cours (lecture pour les tests et d'autres contrôles du garde).
function TraversalGuard.getActive(player: Player): string?
	local s = states[player]
	local a = s and s.active
	return if a then a.kind else nil
end

function TraversalGuard.forget(player: Player)
	states[player] = nil
end

return TraversalGuard
