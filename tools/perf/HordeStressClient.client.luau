--!strict
-- A13-01 : mesure de la horde par paliers (côté joueur). Va avec HordeStress.server.luau.
-- Procédure : docs/qa/mesure-horde.md. Outil de test, jamais dans le jeu publié.
--
-- Suit les attributs de Workspace posés par le serveur (A13PerfStep, A13PerfPhase). Pendant la
-- phase "measure" d'un palier, relève : FPS moyen, image la plus lente, 1 % des pires images,
-- mémoire totale et par catégorie, Stats.DataReceiveKbps, triangles et appels de rendu,
-- ennemis dessinés (EnemyRenderer). Écrit une ligne par palier dans la sortie, plus un tableau
-- Markdown à la fin. Sur téléphone, la sortie se lit dans la console (onglet Log, côté client).
-- Affiche aussi le dernier résultat en haut à gauche (petit texte de test, supprimé avec le script).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")

local function readStat(fn: () -> number): number
	local ok, v = pcall(fn)
	return if ok and type(v) == "number" then v else -1
end

local function tagMb(name: string): number
	return readStat(function()
		return Stats:GetMemoryUsageMbForTag((Enum.DeveloperMemoryTag :: any)[name])
	end)
end

-- EnemyRenderer est un ModuleScript du même VM client : require renvoie la même instance que le jeu.
local renderer: any = nil
task.spawn(function()
	local scripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
	local client = scripts:WaitForChild("Client", 30)
	local controllers = client and client:WaitForChild("Controllers", 30)
	local module = controllers and controllers:FindFirstChild("EnemyRenderer")
	if module and module:IsA("ModuleScript") then
		local ok, m = pcall(require, module)
		if ok then
			renderer = m
		end
	end
end)

local function drawnEnemies(): number
	if renderer and renderer.getVisibleCount then
		local ok, n = pcall(renderer.getVisibleCount)
		if ok and type(n) == "number" then
			return n
		end
	end
	return -1
end

-- Petit affichage de test (outil A13, pas une UI du jeu)
local label: TextLabel? = nil
do
	local gui = Instance.new("ScreenGui")
	gui.Name = "A13PerfReadout"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 100
	local text = Instance.new("TextLabel")
	text.Position = UDim2.fromOffset(8, 40)
	text.Size = UDim2.fromOffset(360, 60)
	text.BackgroundTransparency = 0.4
	text.BackgroundColor3 = Color3.new(0, 0, 0)
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.TextWrapped = true
	text.TextSize = 12
	text.Font = Enum.Font.Code
	text.Text = "A13 perf : en attente du serveur"
	text.Parent = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	label = text
end

local function show(text: string)
	print("[A13 client] " .. text)
	if label then
		label.Text = text
	end
end

type Row = {
	target: number,
	fps: number,
	worstMs: number,
	low1Fps: number,
	memMb: number,
	texMb: number,
	meshMb: number,
	heapMb: number,
	recvKbps: number,
	tris: number,
	draws: number,
	drawn: number,
}
local rows: { Row } = {}

-- Relevés en cours
local measuring = false
local currentStep = 0
local frameTimes: { number } = table.create(4096)
local frameN = 0
local secondAcc = 0
local samples = 0
local sums = { mem = 0, tex = 0, mesh = 0, heap = 0, recv = 0, tris = 0, draws = 0, drawn = 0 }

local function resetSums()
	frameN = 0
	secondAcc = 0
	samples = 0
	for k in sums do
		sums[k] = 0
	end
end

local function sampleSecond()
	samples += 1
	sums.mem += readStat(function()
		return Stats:GetTotalMemoryUsageMb()
	end)
	sums.tex += tagMb("GraphicsTexture")
	sums.mesh += tagMb("GraphicsMeshParts")
	sums.heap += tagMb("LuaHeap")
	sums.recv += readStat(function()
		return Stats.DataReceiveKbps
	end)
	sums.tris += readStat(function()
		return (Stats :: any).SceneTriangleCount
	end)
	sums.draws += readStat(function()
		return (Stats :: any).SceneDrawcallCount
	end)
	sums.drawn += drawnEnemies()
end

local function finishStep()
	if frameN == 0 or samples == 0 then
		return
	end
	local total, worst = 0, 0
	local sorted = table.create(frameN)
	for i = 1, frameN do
		local dt = frameTimes[i]
		total += dt
		worst = math.max(worst, dt)
		sorted[i] = dt
	end
	table.sort(sorted, function(a, b)
		return a > b
	end)
	-- 1 % low : FPS moyen sur le 1 % des images les plus lentes
	local k = math.max(1, frameN // 100)
	local slow = 0
	for i = 1, k do
		slow += sorted[i]
	end
	local row: Row = {
		target = currentStep,
		fps = frameN / total,
		worstMs = worst * 1000,
		low1Fps = k / slow,
		memMb = sums.mem / samples,
		texMb = sums.tex / samples,
		meshMb = sums.mesh / samples,
		heapMb = sums.heap / samples,
		recvKbps = sums.recv / samples,
		tris = sums.tris / samples,
		draws = sums.draws / samples,
		drawn = sums.drawn / samples,
	}
	table.insert(rows, row)
	show(string.format(
		"palier %d : %.0f FPS (1%% low %.0f, pire %.0f ms) | mém. %.0f Mo (tex %.0f, mailles %.0f, Lua %.0f) | reçu %.1f | %.0fk tris, %.0f appels | %.0f ennemis dessinés",
		row.target, row.fps, row.low1Fps, row.worstMs, row.memMb, row.texMb, row.meshMb, row.heapMb,
		row.recvKbps, row.tris / 1000, row.draws, row.drawn
	))
end

local function printTable()
	local lines = {
		"| Palier | FPS moyen | 1 % low | Pire image (ms) | Mémoire (Mo) | Textures | Mailles | Lua | DataReceiveKbps | Triangles | Appels de rendu | Ennemis dessinés |",
		"| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
	}
	for _, r in rows do
		table.insert(lines, string.format(
			"| %d | %.0f | %.0f | %.0f | %.0f | %.0f | %.0f | %.0f | %.1f | %.0f | %.0f | %.0f |",
			r.target, r.fps, r.low1Fps, r.worstMs, r.memMb, r.texMb, r.meshMb, r.heapMb,
			r.recvKbps, r.tris, r.draws, r.drawn
		))
	end
	print("[A13 client] fin. Tableau client :\n" .. table.concat(lines, "\n"))
end

local function onPhase()
	local phase = Workspace:GetAttribute("A13PerfPhase")
	local step = Workspace:GetAttribute("A13PerfStep")
	if measuring then
		finishStep()
		measuring = false
	end
	if phase == "measure" and type(step) == "number" then
		currentStep = step
		resetSums()
		measuring = true
	elseif phase == "warmup" and type(step) == "number" then
		show(`palier {step} : remplissage de la horde…`)
	elseif phase == "done" then
		printTable()
	end
end

Workspace:GetAttributeChangedSignal("A13PerfPhase"):Connect(onPhase)
onPhase()

RunService.PreRender:Connect(function(dt)
	if not measuring then
		return
	end
	frameN += 1
	frameTimes[frameN] = dt
	secondAcc += dt
	if secondAcc >= 1 then
		secondAcc -= 1
		sampleSecond()
	end
end)
