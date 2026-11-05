--!strict
-- A13-01 : mesure de la horde par paliers (côté serveur). Outil de test, jamais dans le jeu publié.
-- Procédure complète : docs/qa/mesure-horde.md.
--
-- Usage (Studio) : copier ce script dans ServerScriptService (un Script), et
-- HordeStressClient.client.luau dans StarterPlayer.StarterPlayerScripts (un LocalScript).
-- Play, lancer une run solo, attendre : le script prend la main dès que des ennemis existent.
-- Il ne fait rien hors Studio, sauf si ALLOW_LIVE est mis à true pour le test sur téléphone
-- (place privée seulement, puis retirer le script).
--
-- À chaque palier : Balance.Debug.ForceAlive = palier (et MaxEnemies monté si besoin, voir QA-01),
-- joueurs invulnérables, WARMUP s d'attente, puis MEASURE s de relevés :
--   ennemis vivants réels, Heartbeat serveur (Hz moyen, pire image), mémoire serveur,
--   Stats.DataSendKbps serveur, et l'estimation du débit EnemySnapshot par joueur
--   (même règle que EnemyService.send : 80 studs à chaque tick, 160 studs un tick sur 3).
-- Le palier en cours est publié dans les attributs de Workspace (A13PerfStep, A13PerfPhase)
-- pour le script client, qui relève FPS, mémoire et réseau côté joueur.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")

local ALLOW_LIVE = false
local STEPS = { 100, 150, 200, 250, 300, 400 }
local WARMUP = 8 -- s : le temps que la horde se remplisse (10 apparitions par tick) et rattrape le joueur
local MEASURE = 20 -- s de relevés par palier
local START_TIMEOUT = 180 -- s pour lancer une run

if not RunService:IsStudio() and not ALLOW_LIVE then
	warn("[A13] HordeStress : hors Studio, rien à faire (ALLOW_LIVE = false)")
	return
end

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared:WaitForChild("Config"):WaitForChild("Balance")) :: any
local Registry = require(Shared:WaitForChild("Registry"))

-- Même format que shared/EnemyCodec.luau (en-tête 7 octets, 7 octets par ennemi).
local HEADER, RECORD = 7, 7
local PER_CHUNK = (Balance.ChunkMaxBytes - HEADER) // RECORD

local function snapshotBytes(n: number): number
	return math.max(1, math.ceil(n / PER_CHUNK)) * HEADER + n * RECORD
end

local function log(text: string)
	print("[A13] " .. text)
end

local function readStat(fn: () -> number): number
	local ok, v = pcall(fn)
	return if ok and type(v) == "number" then v else -1
end

local function luaHeapMb(): number
	return readStat(function()
		return Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.LuaHeap)
	end)
end

-- Attente : les services sont chargés et une run fait apparaître des ennemis.
local enemies: any = nil
local deadline = os.clock() + START_TIMEOUT
while os.clock() < deadline do
	enemies = Registry.find("EnemyService")
	if enemies and enemies.getCount() > 0 then
		break
	end
	task.wait(1)
end
if not (enemies and enemies.getCount() > 0) then
	warn("[A13] HordeStress : aucun ennemi après " .. START_TIMEOUT .. " s. Lance une run, puis relance Play.")
	return
end

local run: any = Registry.find("RunManager")
local savedForce = Balance.Debug.ForceAlive
local savedMax = Balance.MaxEnemies
local queryOut: { number } = {}

-- Relevés du Heartbeat serveur
local hbFrames, hbTime, hbWorst = 0, 0, 0
local hbConn = RunService.Heartbeat:Connect(function(dt)
	hbFrames += 1
	hbTime += dt
	if dt > hbWorst then
		hbWorst = dt
	end
end)

-- Garde les joueurs en vie pendant la mesure : l'invulnérabilité de RunManager est plafonnée
-- (anti-triche, 30 s max et une part du temps de run), donc on soigne aussi 5 fois par seconde.
local protecting = true
local function protectPlayers(seconds: number)
	if not run then
		return
	end
	for _, player in Players:GetPlayers() do
		pcall(run.setInvulnerable, player, seconds, "A13Perf")
	end
end
task.spawn(function()
	while protecting do
		if run then
			for _, player in Players:GetPlayers() do
				pcall(run.healPlayer, player, 1e6)
			end
		end
		task.wait(0.2)
	end
end)

-- Octets par seconde d'EnemySnapshot pour un joueur, d'après les ennemis dans ses rayons.
local function snapshotRate(player: Player): (number, number, number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return 0, 0, 0
	end
	local p = root.Position
	local near = enemies.queryRadius(p.X, p.Z, Balance.InterestRadiusNear, queryOut)
	local far = enemies.queryRadius(p.X, p.Z, Balance.InterestRadiusFar, queryOut)
	local every = Balance.FarSendEveryNTicks
	local perCycle = (every - 1) * snapshotBytes(near) + snapshotBytes(far)
	return perCycle / every * Balance.SimHz, near, far
end

Workspace:SetAttribute("A13PerfPhase", "start")
log(`début : {#STEPS} paliers, {WARMUP} s d'attente + {MEASURE} s de mesure chacun, {#Players:GetPlayers()} joueur(s)`)

type Row = {
	target: number,
	alive: number,
	hz: number,
	worstMs: number,
	memMb: number,
	heapMb: number,
	sendKbps: number,
	snapKBs: number,
	near: number,
	far: number,
}
local rows: { Row } = {}

for _, target in STEPS do
	Balance.MaxEnemies = math.max(savedMax, target)
	Balance.Debug.ForceAlive = target
	protectPlayers(WARMUP + MEASURE + 5)
	Workspace:SetAttribute("A13PerfStep", target)
	Workspace:SetAttribute("A13PerfPhase", "warmup")
	task.wait(WARMUP)

	Workspace:SetAttribute("A13PerfPhase", "measure")
	hbFrames, hbTime, hbWorst = 0, 0, 0
	local samples = 0
	local aliveSum, memSum, heapSum, sendSum, snapSum, nearSum, farSum = 0, 0, 0, 0, 0, 0, 0
	local measureEnd = os.clock() + MEASURE
	while os.clock() < measureEnd do
		task.wait(1)
		samples += 1
		aliveSum += enemies.getCount()
		memSum += readStat(function()
			return Stats:GetTotalMemoryUsageMb()
		end)
		heapSum += luaHeapMb()
		sendSum += readStat(function()
			return Stats.DataSendKbps
		end)
		-- débit du joueur le plus chargé
		local worstRate, worstNear, worstFar = 0, 0, 0
		for _, player in Players:GetPlayers() do
			local rate, near, far = snapshotRate(player)
			if rate > worstRate then
				worstRate, worstNear, worstFar = rate, near, far
			end
		end
		snapSum += worstRate
		nearSum += worstNear
		farSum += worstFar
	end

	local row: Row = {
		target = target,
		alive = aliveSum / samples,
		hz = if hbTime > 0 then hbFrames / hbTime else 0,
		worstMs = hbWorst * 1000,
		memMb = memSum / samples,
		heapMb = heapSum / samples,
		sendKbps = sendSum / samples,
		snapKBs = snapSum / samples / 1000,
		near = nearSum / samples,
		far = farSum / samples,
	}
	table.insert(rows, row)
	log(string.format(
		"palier %d : %.0f vivants | Heartbeat %.1f Hz, pire %.1f ms | mém. %.0f Mo (Lua %.0f) | envoi %.1f | EnemySnapshot %.1f Ko/s (%.0f à 80, %.0f à 160)",
		row.target, row.alive, row.hz, row.worstMs, row.memMb, row.heapMb, row.sendKbps, row.snapKBs, row.near, row.far
	))
	if row.alive < target * 0.9 then
		warn(`[A13] palier {target} : la horde n'atteint pas le palier ({math.floor(row.alive)}). Voir mesure-horde.md, « Si le compte ne monte pas ».`)
	end
end

-- Retour à l'état d'avant
Balance.Debug.ForceAlive = savedForce
Balance.MaxEnemies = savedMax
hbConn:Disconnect()
protecting = false
Workspace:SetAttribute("A13PerfPhase", "done")

-- Tableau Markdown à coller dans le rapport A13-01
local lines = {
	"| Palier | Vivants | Heartbeat serveur (Hz) | Pire image serveur (ms) | Mémoire serveur (Mo) | Lua (Mo) | DataSendKbps serveur | EnemySnapshot pire joueur (Ko/s) |",
	"| --- | --- | --- | --- | --- | --- | --- | --- |",
}
for _, r in rows do
	table.insert(lines, string.format(
		"| %d | %.0f | %.1f | %.1f | %.0f | %.0f | %.1f | %.1f |",
		r.target, r.alive, r.hz, r.worstMs, r.memMb, r.heapMb, r.sendKbps, r.snapKBs
	))
end
log("fin. Tableau serveur :\n" .. table.concat(lines, "\n"))
