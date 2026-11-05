--!strict
-- Loadout screen: class + companion selection with locks and unlock hints, avatar preview, Play.
-- Design: docs/dossier/60-ui-ux.md section 9. Listens: Profile (via UITheme), RunState phase.
-- Sends: SelectLoadout(classId, companionId).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Registry = require(Shared:WaitForChild("Registry"))
local UITheme = require(script.Parent:WaitForChild("UITheme"))

local Config = UITheme.Config
local S = UITheme.S
local LOCAL = Players.LocalPlayer

local LoadoutUI = {}

type Cell = {
	id: string,
	button: TextButton,
	stroke: UIStroke,
	name: TextLabel,
	sub: TextLabel,
	badge: TextLabel,
	lock: Frame,
}

local bgGui: ScreenGui
local gui: ScreenGui
local grid: ScrollingFrame
local classCells: { Cell } = {}
local companionCells: { Cell } = {}
local tabClass: TextButton
local tabCompanion: TextButton
local playBtn: TextButton
local status: TextLabel
local selection: TextLabel
local viewport: ViewportFrame
local worldModel: WorldModel
local previewModel: Model? = nil
local spinConn: RBXScriptConnection? = nil

local tab = "Class"
local classId = "Cornu"
local companionId = "Braise"
local sentAt = -math.huge

---------------------------------------------------------------------------- data

local function unlocked(kind: string, id: string): boolean
	local p = UITheme.profile()
	if p and type(p.unlocks) == "table" and type(p.unlocks[kind]) == "table" then
		return p.unlocks[kind][id] == true
	end
	local free = if kind == "Class" then Config.Defaults.FreeClasses else Config.Defaults.FreeCompanions
	if kind == "Companion" then
		local comp = UITheme.config("Companions")
		if comp and type(comp.Eggs) == "table" and type(comp.Eggs.StarterLines) == "table" then
			free = comp.Eggs.StarterLines
		end
	end
	return table.find(free, id) ~= nil
end

local function questProgress(questId: string): (number?, number?)
	local p = UITheme.profile()
	if p and type(p.quests) == "table" then
		for _, q in p.quests do
			if type(q) == "table" and q.id == questId then
				return tonumber(q.progress), tonumber(q.goal)
			end
		end
	end
	return nil, nil
end

local function classHint(id: string): string
	local def = UITheme.def("Classes", id)
	local questId = if def and type(def.unlock) == "string" then def.unlock else nil
	if not questId or questId == "Free" then
		return UITheme.format(S.Locked)
	end
	local quest = UITheme.nameOf("Quests", questId)
	local text = UITheme.format(S.UnlockQuest, { q = UITheme.format(quest) })
	local progress, goal = questProgress(questId)
	if progress and goal then
		text ..= string.format(" (%s / %s)", UITheme.short(progress), UITheme.short(goal))
	end
	return text
end

local function companionName(line: string): any
	local def = UITheme.def("Companions", line)
	if def and type(def.stages) == "table" and type(def.stages[1]) == "table" and type(def.stages[1].name) == "table" then
		return def.stages[1].name
	end
	return line
end

local function order(configName: string, key: string, fallback: { string }): { string }
	local cfg = UITheme.config(configName)
	if cfg and type(cfg[key]) == "table" and #cfg[key] > 0 then
		return cfg[key]
	end
	return fallback
end

---------------------------------------------------------------------------- build

local function drawLock(parent: Instance): Frame
	local lock = UITheme.new("Frame", {
		Name = "Lock",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(16, 20),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 6),
		ZIndex = 4,
	}, parent)
	local shackle = UITheme.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(10, 12),
		Position = UDim2.fromOffset(3, 0),
		ZIndex = 4,
	}, lock)
	UITheme.corner(shackle, 5)
	UITheme.stroke(shackle, 2, "TextDim")
	local body = UITheme.new("Frame", {
		Size = UDim2.fromOffset(16, 11),
		Position = UDim2.fromOffset(0, 9),
		BorderSizePixel = 0,
		ZIndex = 5,
	}, lock)
	UITheme.paint(body, "BackgroundColor3", "TextDim")
	UITheme.corner(body, 2)
	return lock
end

local function makeCell(id: string, order_: number, onPick: (id: string) -> ()): Cell
	local b = Instance.new("TextButton")
	b.Name = id
	b.Text = ""
	b.LayoutOrder = order_
	b.BorderSizePixel = 0
	b.Visible = false
	b.Parent = grid
	UITheme.paint(b, "BackgroundColor3", "PanelLight")
	UITheme.corner(b, 10)
	local stroke = UITheme.stroke(b, 2, "Outline")
	local name = UITheme.label(b, {
		size = UDim2.new(1, -28, 0, 20),
		position = UDim2.fromOffset(8, 4),
		role = "Body",
		align = Enum.TextXAlignment.Left,
	})
	local sub = UITheme.label(b, {
		size = UDim2.new(1, -12, 0, 28),
		position = UDim2.fromOffset(8, 24),
		role = "Tiny",
		font = "body",
		color = "TextDim",
		align = Enum.TextXAlignment.Left,
		valign = Enum.TextYAlignment.Top,
		wrap = true,
	})
	local badge = UITheme.label(b, {
		size = UDim2.fromOffset(70, 14),
		position = UDim2.new(1, -6, 1, -4),
		anchor = Vector2.new(1, 1),
		role = "Tiny",
		color = "Xp",
		align = Enum.TextXAlignment.Right,
	})
	local lock = drawLock(b)
	b.Activated:Connect(function()
		onPick(id)
	end)
	return { id = id, button = b, stroke = stroke, name = name, sub = sub, badge = badge, lock = lock }
end

---------------------------------------------------------------------------- render

local function render()
	local p = UITheme.profile()
	for _, c in classCells do
		c.button.Visible = tab == "Class"
		local open = unlocked("Class", c.id)
		UITheme.setText(c.name, UITheme.nameOf("Classes", c.id))
		c.lock.Visible = not open
		c.button.BackgroundTransparency = if open then 0 else 0.5
		if open then
			local def = UITheme.def("Classes", c.id)
			local weapon = if def and type(def.startWeapon) == "string" then UITheme.format(UITheme.nameOf("Weapons", def.startWeapon)) else "?"
			UITheme.setText(c.sub, S.StartWeapon, { w = weapon })
		else
			UITheme.setText(c.sub, classHint(c.id)) -- rebuilt by render() on language change
		end
		local mastery = p and type(p.mastery) == "table" and tonumber(p.mastery[c.id])
		if mastery and mastery > 0 then
			UITheme.setText(c.badge, S.Mastery, { n = mastery })
		else
			UITheme.setText(c.badge, "")
		end
		UITheme.paint(c.stroke, "Color", if c.id == classId then "Primary" else "Outline")
		c.stroke.Thickness = if c.id == classId then 3 else 2
	end
	for _, c in companionCells do
		c.button.Visible = tab == "Companion"
		local open = unlocked("Companion", c.id)
		UITheme.setText(c.name, companionName(c.id))
		c.lock.Visible = not open
		c.button.BackgroundTransparency = if open then 0 else 0.5
		local def = UITheme.def("Companions", c.id)
		if open then
			UITheme.setText(c.sub, if def and type(def.affinity) == "table" then def.affinity else c.id)
		else
			UITheme.setText(c.sub, S.UnlockEgg)
		end
		local bond = p and type(p.bond) == "table" and tonumber(p.bond[c.id])
		if bond and bond > 0 then
			UITheme.setText(c.badge, S.Bond, { n = bond })
		else
			UITheme.setText(c.badge, "")
		end
		UITheme.paint(c.stroke, "Color", if c.id == companionId then "Primary" else "Outline")
		c.stroke.Thickness = if c.id == companionId then 3 else 2
	end
	UITheme.paint(tabClass, "BackgroundColor3", if tab == "Class" then "Primary" else "PanelLight")
	UITheme.paint(tabCompanion, "BackgroundColor3", if tab == "Companion" then "Primary" else "PanelLight")
	selection.Text = UITheme.format(UITheme.nameOf("Classes", classId)) .. "  +  " .. UITheme.format(companionName(companionId))
end

---------------------------------------------------------------------------- preview

local function buildPreview()
	if previewModel then
		previewModel:Destroy()
		previewModel = nil
	end
	local character = LOCAL.Character
	if not character then
		return
	end
	local ok, clone = pcall(function()
		local was = character.Archivable
		character.Archivable = true
		local c = character:Clone()
		character.Archivable = was
		return c
	end)
	if not ok or not clone then
		return
	end
	local model = clone :: Model
	for _, d in model:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	model:PivotTo(CFrame.new(0, 3, 0))
	model.Parent = worldModel
	previewModel = model
	local cam = viewport.CurrentCamera
	if cam then
		cam.CFrame = CFrame.lookAt(Vector3.new(0, 4, -9), Vector3.new(0, 3, 0))
	end
end

local function setSpin(on: boolean)
	if on and not spinConn and not UITheme.flashesReduced() then
		local angle = 0
		spinConn = RunService.RenderStepped:Connect(function(dt)
			angle += dt * 0.6
			if previewModel then
				previewModel:PivotTo(CFrame.new(0, 3, 0) * CFrame.Angles(0, angle, 0))
			end
		end)
	elseif not on and spinConn then
		spinConn:Disconnect()
		spinConn = nil
	end
end

---------------------------------------------------------------------------- open / close

local function setInputEnabled(enabled: boolean)
	local ic = Registry.find("InputController")
	if ic and type(ic.setEnabled) == "function" then
		ic.setEnabled(enabled)
	end
end

local isOpen = false
local function refresh()
	local open = UITheme.phase() == "Loadout"
	if open == isOpen then
		return
	end
	isOpen = open
	gui.Enabled = open
	bgGui.Enabled = open
	setInputEnabled(not open)
	if open then
		UITheme.setText(status, "")
		buildPreview()
		render()
	end
	setSpin(open)
end

-- Lobby v3 (A09, 65-lobby.md §2) : quand ses gabarits sont posés dans la place, le hub (PLAY, barre
-- des menus, menu Classes) remplace cet écran. LobbyController n'est pas encore dans l'ordre de
-- client/Main.client.luau (demande au lead) : on le lance d'ici. Sans gabarits, l'ancien écran reste.
local function startLobby(): boolean
	local StarterGui = game:GetService("StarterGui")
	local template = StarterGui:FindFirstChild("COHUE_Lobby") or LOCAL:WaitForChild("PlayerGui"):WaitForChild("COHUE_Lobby", 3)
	if not template then
		return false
	end
	local folder = script.Parent.Parent:FindFirstChild("Lobby")
	local module = folder and folder:FindFirstChild("LobbyController")
	if not module or not module:IsA("ModuleScript") then
		warn("[LoadoutUI] COHUE_Lobby est posé mais Controllers.Lobby.LobbyController manque : ancien écran de choix")
		return false
	end
	local ok, controller = pcall(require, module)
	if not ok or type(controller) ~= "table" or type(controller.start) ~= "function" then
		warn(`[LoadoutUI] LobbyController : {controller}`)
		return false
	end
	Registry.register("LobbyController", controller)
	task.spawn(controller.start)
	return true
end

function LoadoutUI.start()
	if startLobby() then
		return
	end
	bgGui = UITheme.screen("COHUE_LoadoutBg", 39, Enum.ScreenInsets.None)
	local bg = UITheme.new("Frame", { Size = UDim2.fromScale(1, 1), BorderSizePixel = 0 }, bgGui)
	UITheme.paint(bg, "BackgroundColor3", "Panel")
	UITheme.back(bg, 0.1)

	gui = UITheme.screen("COHUE_Loadout", 40, Enum.ScreenInsets.DeviceSafeInsets)
	local zone = UITheme.zone(gui, "Loadout", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(700, 340))
	UITheme.label(zone, {
		size = UDim2.new(1, -60, 0, 26),
		role = "Title",
		font = "display",
		text = S.ChooseLoadout,
	})
	local gear = UITheme.button(zone, {
		name = "Settings",
		size = UDim2.fromOffset(44, 44),
		position = UDim2.new(1, 0, 0, -8),
		anchor = Vector2.new(1, 0),
		role = "Title",
		font = "display",
		text = "...",
	})
	gear.Activated:Connect(function()
		local settingsUI = Registry.find("SettingsUI")
		if settingsUI and type(settingsUI.open) == "function" then
			settingsUI.open()
		end
	end)

	viewport = UITheme.new("ViewportFrame", {
		Size = UDim2.fromOffset(240, 256),
		Position = UDim2.fromOffset(0, 34),
		BorderSizePixel = 0,
		Ambient = Color3.fromRGB(200, 200, 210),
		LightColor = Color3.new(1, 1, 1),
	}, zone)
	UITheme.paint(viewport, "BackgroundColor3", "PanelLight")
	UITheme.corner(viewport, 12)
	worldModel = UITheme.new("WorldModel", {}, viewport)
	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.Parent = viewport
	viewport.CurrentCamera = cam
	-- Pedestal
	UITheme.new("Part", {
		Anchored = true,
		Size = Vector3.new(4, 0.6, 4),
		Shape = Enum.PartType.Cylinder,
		CFrame = CFrame.new(0, -0.3, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(70, 80, 110),
	}, worldModel)
	selection = UITheme.label(zone, {
		size = UDim2.fromOffset(240, 40),
		position = UDim2.fromOffset(0, 296),
		role = "Body",
		wrap = true,
	})

	tabClass = UITheme.button(zone, { name = "TabClass", size = UDim2.fromOffset(140, 40), position = UDim2.fromOffset(252, 34), role = "Body", text = S.TabClass })
	tabCompanion = UITheme.button(zone, {
		name = "TabCompanion",
		size = UDim2.fromOffset(140, 40),
		position = UDim2.fromOffset(400, 34),
		role = "Body",
		text = S.TabCompanion,
	})
	tabClass.Activated:Connect(function()
		tab = "Class"
		render()
	end)
	tabCompanion.Activated:Connect(function()
		tab = "Companion"
		render()
	end)

	grid = UITheme.new("ScrollingFrame", {
		Size = UDim2.fromOffset(448, 206),
		Position = UDim2.fromOffset(252, 80),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, zone)
	UITheme.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(142, 66),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)

	local function pickClass(id: string)
		if unlocked("Class", id) then
			classId = id
			UITheme.setText(status, "")
		else
			UITheme.setText(status, classHint(id))
		end
		render()
	end
	local function pickCompanion(id: string)
		if unlocked("Companion", id) then
			companionId = id
			UITheme.setText(status, "")
		else
			UITheme.setText(status, S.UnlockEgg)
		end
		render()
	end
	for i, id in order("Classes", "Order", Config.Defaults.ClassOrder) do
		table.insert(classCells, makeCell(id, i, pickClass))
	end
	for i, id in order("Companions", "LineOrder", Config.Defaults.CompanionOrder) do
		table.insert(companionCells, makeCell(id, 100 + i, pickCompanion))
	end

	status = UITheme.label(zone, {
		size = UDim2.fromOffset(240, 48),
		position = UDim2.fromOffset(252, 292),
		role = "Small",
		color = "Warning",
		wrap = true,
		align = Enum.TextXAlignment.Left,
	})
	playBtn = UITheme.button(zone, {
		name = "Play",
		size = UDim2.fromOffset(200, 48),
		position = UDim2.fromOffset(500, 292),
		role = "Big",
		font = "display",
		fill = "Primary",
		outline = true,
		text = S.Play,
	})
	playBtn.Activated:Connect(function()
		if os.clock() - sentAt < 2 then
			return
		end
		if not unlocked("Class", classId) or not unlocked("Companion", companionId) then
			return
		end
		sentAt = os.clock()
		Net.event("SelectLoadout"):FireServer(classId, companionId)
		UITheme.setText(status, S.Waiting)
	end)

	gui.Enabled = false
	bgGui.Enabled = false
	UITheme.changed:connect(function(reason: string)
		if reason == "phase" then
			refresh()
		elseif reason == "profile" then
			local p = UITheme.profile()
			if p and type(p.loadout) == "table" then
				if type(p.loadout.classId) == "string" and unlocked("Class", p.loadout.classId) then
					classId = p.loadout.classId
				end
				if type(p.loadout.companionId) == "string" and unlocked("Companion", p.loadout.companionId) then
					companionId = p.loadout.companionId
				end
			end
			if isOpen then
				render()
			end
		elseif (reason == "lang" or reason == "palette") and isOpen then
			render()
		elseif reason == "motion" then
			setSpin(false)
			setSpin(isOpen)
		end
	end)
	LOCAL.CharacterAdded:Connect(function()
		if isOpen then
			task.wait(1)
			buildPreview()
		end
	end)
	refresh()
end

return LoadoutUI
