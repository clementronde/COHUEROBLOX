-- A06 — test MovementGuard, partie SERVEUR (à lancer APRÈS tools/tests/a06-guard-client.luau, en Play,
-- avec execute_luau datamodel "Server"). Mode d'emploi : docs/dossier/50-classes-avatar-mouvement.md §10.
--
-- Pour chaque latence de PINGS et chaque scénario de SCENARIOS :
--   1. pose Workspace.CohueTestPing (ping vu par MovementGuard) et, si LAG, la latence de réplication simulée
--      de Studio (settings().Network.IncomingReplicationLag) ;
--   2. donne la classe du scénario (attribut serveur ClassId ; remis à la fin) ;
--   3. amène le joueur sur une piste de test (plat de 600 studs + rampe de 24°, loin du monde, retirée à la
--      fin) par le chemin prévu pour les déplacements serveur (MoveExemptUntil juste avant PivotTo) ;
--   4. remet à zéro les compteurs du garde (ServerScriptService.CohueGuardDebug "reset") ;
--   5. donne l'ordre au coureur client (attribut Player.A06TestStep) et mesure pendant le scénario ;
--   6. relit CohueGuardDebug : strikes et recalages doivent rester à 0.
-- Verdict par ligne : PASS (0 strike, 0 recalage, mécanique bien jouée), FAIL (strike ou recalage),
-- INVALID (le scénario n'a pas eu lieu : coureur client absent, personnage bloqué...).
-- Durée : ≈ 18 s par scénario. Un appel par latence si execute_luau coupe les appels longs.

-- ------------------------------------------------------------ réglages (à modifier avant de lancer)
local SCENARIOS = { "bhop", "slide", "slope", "doublejump" } -- + "glide" (Mage), optionnel
local PINGS = { 0, 0.15 } -- secondes ; ex. { 0 } puis { 0.15 } en deux appels
local LAG = true -- applique aussi la latence de réplication simulée de Studio (si accessible)
local ORIGIN = Vector3.new(4000, 300, 4000) -- début du plat, loin du monde

-- ------------------------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local CLASS = { bhop = "Knight", slide = "Knight", slope = "Knight", doublejump = "Rogue", glide = "Mage" }
local DURATION = { bhop = 15, slide = 13, slope = 11, doublejump = 12, glide = 12 }

local guard = ServerScriptService:FindFirstChild("CohueGuardDebug")
if not guard or not guard:IsA("BindableFunction") then
	return "ERREUR : ServerScriptService.CohueGuardDebug absent (MovementGuard non démarré, ou pas en Studio)"
end
local player = Players:GetPlayers()[1]
if not player then
	return "ERREUR : aucun joueur (lancer Play, pas Run)"
end

-- ------------------------------------------------------------ piste
local old = Workspace:FindFirstChild("CohueA06Test")
if old then
	old:Destroy()
end
local course = Instance.new("Folder")
course.Name = "CohueA06Test"
local function slab(name: string, size: Vector3, cf: CFrame)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Material = Enum.Material.SmoothPlastic
	p.Color = Color3.fromRGB(120, 130, 140)
	p.TopSurface = Enum.SurfaceType.Smooth
	p.Parent = course
	return p
end
local FLAT_LEN = 600
slab("Flat", Vector3.new(FLAT_LEN, 2, 40), CFrame.new(ORIGIN + Vector3.new(FLAT_LEN / 2, -1, 0)))
-- Rampe de 24° qui descend vers +X et finit au niveau du plat.
local ANGLE = math.rad(24)
local RAMP_RUN = 70 -- studs horizontaux
local normal = Vector3.new(math.sin(ANGLE), math.cos(ANGLE), 0)
local topMid = ORIGIN + Vector3.new(-RAMP_RUN / 2, RAMP_RUN / 2 * math.tan(ANGLE), 0)
slab("Ramp", Vector3.new(RAMP_RUN / math.cos(ANGLE) + 1, 2, 40), CFrame.new(topMid - normal) * CFrame.Angles(0, 0, -ANGLE))
course.Parent = Workspace

local function startFor(name: string): Vector3
	if name == "slope" then
		local x = -RAMP_RUN + 4
		return ORIGIN + Vector3.new(x, -x * math.tan(ANGLE) + 4, 0)
	end
	return ORIGIN + Vector3.new(6, 4, 0)
end

-- ------------------------------------------------------------ aides
local originalClass = player:GetAttribute("ClassId")
local lagApplied = "non"
local function setLag(seconds: number)
	if not LAG then
		return
	end
	local ok = pcall(function()
		(settings() :: any).Network.IncomingReplicationLag = seconds
	end)
	lagApplied = if ok then "oui" else "inaccessible (seul CohueTestPing est appliqué)"
end

local function character(): (Model?, Humanoid?, BasePart?)
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	local r = h and h.RootPart
	return c, h, r
end

-- Déplacement serveur prévu par MovementGuard : MoveExemptUntil posé juste avant PivotTo, sans céder entre les deux.
local function bring(pos: Vector3): boolean
	pcall(player.RequestStreamAroundAsync, player, pos, 5)
	local c, _, r = character()
	if not c or not r then
		return false
	end
	player:SetAttribute("MoveExemptUntil", Workspace:GetServerTimeNow() + 2.5)
	c:PivotTo(CFrame.lookAt(pos, pos + Vector3.xAxis))
	r.AssemblyLinearVelocity = Vector3.zero
	return true
end

local function runScenario(name: string, ping: number, n: number): string
	Workspace:SetAttribute("CohueTestPing", ping)
	setLag(ping)
	player:SetAttribute("ClassId", CLASS[name] or "Knight")
	player:SetAttribute("A06TestStep", "")
	task.wait(0.3)
	if not bring(startFor(name)) then
		return `{name} ping={ping} INVALID pas de personnage`
	end
	task.wait(3.5) -- exemption finie, positions stabilisées
	local _, _, r0 = character()
	if not r0 or math.abs(r0.Position.X - startFor(name).X) > 8 then
		return `{name} ping={ping} INVALID personnage pas sur la piste`
	end
	local before = guard:Invoke() -- recalages et strikes de la mise en place (pour info)
	local mine = before[player.Name] or {}
	guard:Invoke("reset")

	-- Mesures serveur pendant le scénario.
	local standY = r0.Position.Y
	local maxSpeed, maxRise, slides, maxAir = 0, 0, 0, 0
	local lastPose = false
	local airSince: number? = nil
	local winPos, winT = r0.Position, os.clock()
	player:SetAttribute("A06TestStep", `{name}#{n}`)
	local t0 = os.clock()
	while os.clock() - t0 < (DURATION[name] or 12) do
		RunService.Heartbeat:Wait()
		local _, _, r = character()
		if r then
			local now = os.clock()
			local p = r.Position
			if now - winT >= 0.25 then
				local flat = Vector3.new(p.X - winPos.X, 0, p.Z - winPos.Z).Magnitude
				maxSpeed = math.max(maxSpeed, flat / (now - winT))
				winPos, winT = p, now
			end
			maxRise = math.max(maxRise, p.Y - standY)
			if p.Y > standY + 0.5 then
				airSince = airSince or now
				maxAir = math.max(maxAir, now - (airSince :: number))
			else
				airSince = nil
			end
			local pose = player:GetAttribute("SlidePose") == true
			if pose and not lastPose then
				slides += 1
			end
			lastPose = pose
		end
	end
	player:SetAttribute("A06TestStep", "")
	task.wait(0.3)
	local after = (guard:Invoke() :: any)[player.Name] or {}
	local hops = after.hops or {}

	local played: boolean
	if name == "bhop" then
		played = (hops.ok or 0) >= 15 and maxSpeed >= 22
	elseif name == "slide" then
		played = slides >= 3
	elseif name == "slope" then
		played = slides >= 1 and maxSpeed >= 26
	elseif name == "doublejump" then
		played = maxRise >= 10
	elseif name == "glide" then
		played = maxAir >= 0.9
	else
		played = false
	end
	local clean = (after.strikes or 0) == 0 and (after.rubberBands or 0) == 0
	local verdict = if not clean then "FAIL" elseif played then "PASS" else "INVALID"
	return string.format(
		"%-10s ping=%3dms %-7s strikes=%d recalages=%d seauPic=%.1f/20 ratioPic=%.2f | hops ok=%d rate=%d noAir=%d noLand=%d | serveur: vmax=%.1f montée=%.1f glissades=%d air=%.2fs | mise en place: strikes=%d",
		name,
		math.floor(ping * 1000 + 0.5),
		verdict,
		after.strikes or -1,
		after.rubberBands or -1,
		after.bucketPeak or -1,
		after.ratioPeak or -1,
		hops.ok or 0,
		hops.rate or 0,
		hops.noAir or 0,
		hops.noLand or 0,
		maxSpeed,
		maxRise,
		slides,
		maxAir,
		mine.strikes or 0
	)
end

local lines = {}
local n = 0
local okRun, err = pcall(function()
	for _, ping in PINGS do
		for _, name in SCENARIOS do
			n += 1
			table.insert(lines, runScenario(name, ping, n))
		end
	end
end)
if not okRun then
	table.insert(lines, `ERREUR pendant le test : {err}`)
end

-- Remise en état : classe, ping, latence, piste ; le joueur revient près de son point de départ du lobby.
Workspace:SetAttribute("CohueTestPing", nil)
setLag(0)
player:SetAttribute("ClassId", originalClass)
player:SetAttribute("A06TestStep", nil)
local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
if spawn then
	bring(spawn.Position + Vector3.new(0, 4, 0))
end
task.wait(0.5)
course:Destroy()

local fails, invalid = 0, 0
for _, l in lines do
	if string.find(l, " FAIL ") then
		fails += 1
	elseif string.find(l, "INVALID") then
		invalid += 1
	end
end
table.insert(lines, 1, string.format("A06 MovementGuard : %d scénarios, %d FAIL, %d INVALID ; latence Studio simulée : %s", n, fails, invalid, lagApplied))
return table.concat(lines, "\n")
