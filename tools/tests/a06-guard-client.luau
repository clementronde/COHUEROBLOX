-- A06 — test MovementGuard, partie CLIENT (à lancer EN PREMIER, en Play, avec execute_luau datamodel "Client").
-- Mode d'emploi complet : docs/dossier/50-classes-avatar-mouvement.md §10.
--
-- Installe un « coureur » qui attend l'ordre du serveur (attribut serveur Player.A06TestStep = "<scénario>#<n>",
-- posé par tools/tests/a06-guard-server.luau) puis joue le scénario avec les vraies entrées du jeu :
-- déplacement par Humanoid:Move (après les contrôles Roblox), Saut / Glisser par LocalPlayer.CohueMoveDebug
-- ("trigger", action, pressed), donc par InputController puis MovementController, comme un joueur.
-- Rien n'est truqué côté mouvement : seuls les appuis sont pilotés par le script.
-- Relancer ce fichier remplace le coureur précédent. Mesures côté client du dernier scénario (hops, bonus,
-- vitesse) : attribut local LocalPlayer.A06TestClient (non répliqué), à relire au besoin avec
--   return game.Players.LocalPlayer:GetAttribute("A06TestClient")   (datamodel Client)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local dbg = player:WaitForChild("CohueMoveDebug", 10) :: BindableFunction?
if not dbg then
	return "ERREUR : LocalPlayer.CohueMoveDebug absent (MovementController non démarré, ou pas en Studio)"
end

-- Un seul coureur : le marqueur du précédent est détruit, ses connexions avec.
local old = player:FindFirstChild("A06TestRunner")
if old then
	old:Destroy()
end
local marker = Instance.new("Folder")
marker.Name = "A06TestRunner"
marker.Parent = player

local alive = true
local moveDir = Vector3.zero
local BIND = "A06TestMove"
pcall(RunService.UnbindFromRenderStep, RunService, BIND)

-- Après les contrôles Roblox (priorité Input) : notre Move écrase le leur à chaque image.
RunService:BindToRenderStep(BIND, Enum.RenderPriority.Character.Value + 1, function()
	if moveDir.Magnitude > 0 then
		local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if h then
			h:Move(moveDir, false)
		end
	end
end)

local function state(): any
	return (dbg :: BindableFunction):Invoke("state")
end
local function press(name: string)
	(dbg :: BindableFunction):Invoke("trigger", name, false)
	;(dbg :: BindableFunction):Invoke("trigger", name, true)
end
local function release(name: string)
	(dbg :: BindableFunction):Invoke("trigger", name, false)
end
local function root(): BasePart?
	local c = player.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local stats = { hops = 0, maxBonus = 0, maxSpeed = 0, slides = 0, airJumps = 0, glideTime = 0 }
local function track()
	local s = state()
	if s.hopBonus > stats.maxBonus then
		stats.maxBonus = s.hopBonus
	end
	if s.speed > stats.maxSpeed then
		stats.maxSpeed = s.speed
	end
	return s
end
local function frame()
	RunService.Heartbeat:Wait()
	if not alive then
		error("A06 runner stopped", 0)
	end
	return track()
end
local function waitFor(seconds: number)
	local t0 = os.clock()
	while os.clock() - t0 < seconds do
		frame()
	end
end
-- Attend le décollage puis l'atterrissage (drapeau airborne de MovementController). false si délai dépassé.
local function waitLanding(timeout: number): boolean
	local t0 = os.clock()
	local wasAir = state().airborne
	while os.clock() - t0 < timeout do
		local s = frame()
		if s.airborne then
			wasAir = true
		elseif wasAir then
			return true
		end
	end
	return false
end
-- Relance à l'image même de l'atterrissage (bien dans la fenêtre de 0,15 s) : n hops.
local function hopChain(n: number)
	for _ = 1, n do
		if not waitLanding(3) then
			return
		end
		press("Jump")
		stats.hops += 1
	end
	waitLanding(3)
end

local SCENARIOS: { [string]: () -> () } = {}

-- 22 hops : bonus au plafond (+60 %, 25,6 studs/s).
SCENARIOS.bhop = function()
	moveDir = Vector3.xAxis
	waitFor(0.6)
	press("Jump")
	hopChain(22)
	waitFor(0.5)
end

-- 3 glissades au plat (maintenues 1 s, recharge respectée), puis glissade -> saut -> 6 hops.
SCENARIOS.slide = function()
	moveDir = Vector3.xAxis
	waitFor(0.6)
	for _ = 1, 3 do
		press("Slide")
		stats.slides += 1
		waitFor(1.0)
		release("Slide")
		waitFor(0.7)
	end
	press("Slide")
	stats.slides += 1
	waitFor(0.45)
	press("Jump") -- saut de glissade
	release("Slide")
	hopChain(6)
	waitFor(0.5)
end

-- Haut de la rampe de 24° : glissade maintenue jusqu'en bas, saut, puis 10 hops.
SCENARIOS.slope = function()
	moveDir = Vector3.xAxis
	local course = Workspace:FindFirstChild("CohueA06Test")
	local flat = course and course:FindFirstChild("Flat")
	local bottomX = if flat and flat:IsA("BasePart") then flat.Position.X - flat.Size.X / 2 else math.huge
	waitFor(0.3)
	press("Slide")
	stats.slides += 1
	local t0 = os.clock()
	while os.clock() - t0 < 4 do
		frame()
		local r = root()
		if r and r.Position.X >= bottomX + 1 then
			break
		end
	end
	press("Jump") -- l'élan de la pente devient du bonus
	release("Slide")
	hopChain(10)
	waitFor(0.5)
end

-- Rogue : à chaque atterrissage un hop, au sommet le double saut. 8 cycles.
SCENARIOS.doublejump = function()
	moveDir = Vector3.xAxis
	waitFor(0.6)
	press("Jump")
	for _ = 1, 8 do
		-- sommet du saut : vitesse verticale qui passe sous 2 studs/s
		local t0 = os.clock()
		while os.clock() - t0 < 2 do
			frame()
			local r = root()
			if r and r.AssemblyLinearVelocity.Y < 2 then
				break
			end
		end
		press("Jump")
		stats.airJumps += 1
		if not waitLanding(3) then
			break
		end
		press("Jump")
		stats.hops += 1
	end
	waitLanding(3)
	waitFor(0.5)
end

-- Mage (optionnel) : saut, Saut maintenu en descente (plané), 6 fois.
SCENARIOS.glide = function()
	moveDir = Vector3.xAxis
	waitFor(0.6)
	for _ = 1, 6 do
		press("Jump")
		local t0 = os.clock()
		while os.clock() - t0 < 3 do
			frame()
			local r = root()
			if r and r.AssemblyLinearVelocity.Y < 0 and r.AssemblyLinearVelocity.Y > -7 then
				stats.glideTime += 1 / 60
			end
			if not state().airborne and os.clock() - t0 > 0.2 then
				break
			end
		end
		release("Jump")
		waitFor(0.3)
	end
end

local function run(name: string)
	local fn = SCENARIOS[name]
	if not fn then
		player:SetAttribute("A06TestClient", `unknown scenario {name}`)
		return
	end
	for k in stats do
		stats[k] = 0
	end
	local ok, err = pcall(fn)
	moveDir = Vector3.zero
	release("Jump")
	release("Slide")
	player:SetAttribute(
		"A06TestClient",
		string.format(
			"%s ok=%s hops=%d maxBonus=%.2f maxSpeed=%.1f slides=%d airJumps=%d glide=%.2fs %s",
			name,
			tostring(ok),
			stats.hops,
			stats.maxBonus,
			stats.maxSpeed,
			stats.slides,
			stats.airJumps,
			stats.glideTime,
			if ok then "" else tostring(err)
		)
	)
end

local conn = player:GetAttributeChangedSignal("A06TestStep"):Connect(function()
	local step = player:GetAttribute("A06TestStep")
	if type(step) == "string" and step ~= "" then
		local name = string.match(step, "^([%w_]+)")
		if name then
			task.spawn(run, name)
		end
	end
end)
marker.Destroying:Connect(function()
	alive = false
	conn:Disconnect()
	moveDir = Vector3.zero
	pcall(RunService.UnbindFromRenderStep, RunService, BIND)
end)

return "A06 runner prêt : lancer maintenant tools/tests/a06-guard-server.luau (datamodel Server)"
