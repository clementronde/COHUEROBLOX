--!strict
-- LobbyController (A09) : le hub entre deux runs. HUD du lobby (PLAY, barre des 8 menus, argent,
-- réglages), choix du mode (Solo / Friends / Public) et fenêtres des menus.
-- Gabarits : StarterGui.COHUE_Lobby, COHUE_ModeSelect, COHUE_LobbyMenus, posés une fois dans la
-- place par tools/ui/build-lobby.luau. Règle de Clément : ce module ne fabrique rien de visible ;
-- il retrouve les objets par leur nom, les remplit, les montre et les anime.
-- Spec : docs/dossier/65-lobby.md §2 (HUD), §2.2 (flux PLAY), §6 (menus).
-- Écoute : RunState (phase), Profile (argent, classes débloquées, loadout), via UITheme.
-- Envoie : SelectLoadout(classId, companionId), une intention : le serveur valide et lance la run.
-- Lancé par LoadoutUI tant que client/Main.client.luau ne le liste pas (demande au lead).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Registry = require(Shared:WaitForChild("Registry"))
local UIFolder = script.Parent.Parent:WaitForChild("UI")
local UIKit = require(UIFolder:WaitForChild("UIKit"))
local UITheme = require(UIFolder:WaitForChild("UITheme"))

local LOCAL = Players.LocalPlayer

local LobbyController = {}

local BAR_ORDER = { "Classes", "Critters", "Upgrades", "Inventory", "Quests", "Ranks", "Pass", "Shop" }
local MODE_ORDER = { "Solo", "Friends", "Public" }
-- Phases où la run tourne (Types.RunPhase) ; « Loadout » = attente au lobby.
local RUN_PHASES: { [string]: boolean } = { Running = true, Boss = true, BossDefeated = true, FinalWave = true }
local SOLO_COUNTDOWN = 3
local SEND_COOLDOWN = 2
-- Ids du domaine data (v1) : seuls acceptés par SelectLoadout. Config.Classes les résout en v2
-- (Cornu -> Knight). Repli si le profil n'est pas encore arrivé.
local DEFAULT_CLASS = "Cornu"
local DEFAULT_COMPANION = "Braise"
local NUMBER_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
}

type ClassEntry = { dataId: string, def: any, tile: Frame }

local lobbyGui: ScreenGui? = nil
local modesGui: ScreenGui? = nil
local menusGui: ScreenGui? = nil
local status: UIKit.Tag? = nil
local classTiles: { ClassEntry } = {}

local openName: string? = nil -- "Modes" ou le nom d'un menu
local inRun = false -- ce joueur est dans la run en cours (pas seulement « une run tourne »)
local lastPhase: string? = nil
local sentAt = -math.huge
local countdownId = 0
local pickedClass: string? = nil -- id data (v1) choisi dans le menu Classes

---------------------------------------------------------------------------- petites aides

local function pop(obj: Instance?)
	local s = obj and obj:FindFirstChild("PopScale")
	if not s or not s:IsA("UIScale") then
		return
	end
	if UITheme.flashesReduced() then
		s.Scale = 1
		return
	end
	s.Scale = 0.9
	TweenService:Create(s, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- Branche la cible « Hit » d'un bouton posé : petit rebond, puis l'action.
local function onPress(root: Instance?, fn: () -> ())
	local hit = root and root:FindFirstChild("Hit")
	if hit and hit:IsA("GuiButton") then
		hit.Activated:Connect(function()
			pop(root)
			fn()
		end)
	end
end

local function adoptScales(gui: ScreenGui?)
	if not gui then
		return
	end
	for _, d in gui:GetDescendants() do
		if d:IsA("UIScale") and d.Name == "Scale" then
			UITheme.adoptScale(d)
		end
	end
end

local function setVisible(obj: any, on: boolean)
	if obj and obj:IsA("GuiObject") then
		obj.Visible = on
	end
end

local function setStatus(s: string?)
	local st = status
	if not st or not st.frame then
		return
	end
	if s and s ~= "" and st.label then
		st.label.Text = s
		st.frame.Visible = true
	else
		st.frame.Visible = false
	end
end

local function setModeStatus(s: string?)
	local line = UIKit.find(modesGui, "Center.Window.Status")
	if line then
		line.Text = s or ""
		line.Visible = s ~= nil and s ~= ""
	end
end

-- Touches clavier (1-8, ENTER) : visibles seulement quand on joue au clavier.
local function showKeycaps()
	local keyboard = UserInputService.KeyboardEnabled and not UserInputService.TouchEnabled
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch or string.find(last.Name, "Gamepad") then
		keyboard = false
	elseif last == Enum.UserInputType.Keyboard or string.find(last.Name, "Mouse") then
		keyboard = true
	end
	for _, gui in { lobbyGui, modesGui } do
		if gui then
			for _, d in gui:GetDescendants() do
				if d.Name == "Key" and d:IsA("GuiObject") then
					d.Visible = keyboard
				end
			end
		end
	end
end

---------------------------------------------------------------------------- profil

local function profile(): { [string]: any }?
	return UITheme.profile()
end

local function classUnlocked(dataId: string, def: any): boolean
	local p = profile()
	if p and type(p.unlocks) == "table" and type(p.unlocks.Class) == "table" then
		return p.unlocks.Class[dataId] == true
	end
	return type(def) == "table" and def.unlock == "Free"
end

local function currentClass(): string
	if pickedClass then
		return pickedClass
	end
	local p = profile()
	if p and type(p.loadout) == "table" and type(p.loadout.classId) == "string" then
		return p.loadout.classId
	end
	return DEFAULT_CLASS
end

local function currentCompanion(): string
	local p = profile()
	if p and type(p.loadout) == "table" and type(p.loadout.companionId) == "string" then
		return p.loadout.companionId
	end
	return DEFAULT_COMPANION
end

local function renderSilver()
	local amount = UIKit.find(lobbyGui, "TopLeft.Silver.Amount")
	if amount then
		local p = profile()
		amount.Text = UITheme.short(tonumber(p and p.silver) or 0)
	end
end

---------------------------------------------------------------------------- menu Classes

-- Les classes v2 dans l'ordre de Config.Classes, chacune avec son id data (v1) : la liste des ids
-- data vient de Config.UI.Defaults.ClassOrder ; Config.Classes résout l'ancien id vers la classe v2.
local function classList(): { { dataId: string, def: any } }
	local classes = UITheme.config("Classes")
	local out: { { dataId: string, def: any } } = {}
	if type(classes) ~= "table" then
		return out
	end
	local seen: { [any]: boolean } = {}
	for _, dataId in UITheme.Config.Defaults.ClassOrder do
		local def = classes[dataId]
		if type(def) == "table" and not seen[def] then
			seen[def] = true
			table.insert(out, { dataId = dataId, def = def })
		end
	end
	table.sort(out, function(a, b)
		return (tonumber(a.def.order) or 99) < (tonumber(b.def.order) or 99)
	end)
	return out
end

local function renderClasses()
	local classes = UITheme.config("Classes")
	local chosenDef = if type(classes) == "table" then classes[currentClass()] else nil
	for _, c in classTiles do
		local open = classUnlocked(c.dataId, c.def)
		local t = c.tile
		UIKit.tint(t, if open then "Royal" else "Stone")
		local name = t:FindFirstChild("Name")
		if name and name:IsA("TextLabel") then
			name.Text = UITheme.format(c.def.name)
		end
		local icon = t:FindFirstChild("Icon")
		if icon and icon:IsA("ImageLabel") then
			icon.Image = UIKit.icon(if type(c.def.startWeapon) == "string" then c.def.startWeapon else nil)
			icon.ImageTransparency = if open then 0 else 0.45
		end
		setVisible(t:FindFirstChild("Lock"), not open)
		local chosen = chosenDef ~= nil and c.def == chosenDef
		setVisible(t:FindFirstChild("Select"), chosen)
		setVisible(t:FindFirstChild("Picked"), chosen)
	end
end

local function pickClass(c: ClassEntry)
	local hint = UIKit.find(menusGui, "Center.Classes.Content.Hint")
	local name = UITheme.format(c.def.name)
	if classUnlocked(c.dataId, c.def) then
		pickedClass = c.dataId
		if hint then
			hint.Text = name .. " picked! Press PLAY to go."
		end
	elseif hint then
		hint.Text = name .. " is locked: finish its quest to unlock it."
	end
	renderClasses()
end

local function setupClasses()
	local tiles = UIKit.find(menusGui, "Center.Classes.Content.Tiles")
	if not tiles then
		return
	end
	local list = classList()
	for i = 1, 8 do
		local tile = tiles:FindFirstChild("Tile" .. i)
		if tile and tile:IsA("Frame") then
			local entry = list[i]
			tile.Visible = entry ~= nil
			if entry then
				local c: ClassEntry = { dataId = entry.dataId, def = entry.def, tile = tile }
				table.insert(classTiles, c)
				onPress(tile, function()
					pickClass(c)
				end)
			end
		end
	end
end

---------------------------------------------------------------------------- fenêtres

local function closeAll()
	openName = nil
	countdownId += 1 -- annule un décompte en cours
	if menusGui then
		menusGui.Enabled = false
	end
	if modesGui then
		modesGui.Enabled = false
	end
end

local function openMenu(name: string)
	if name == "Settings" then
		closeAll()
		local settingsUI = Registry.find("SettingsUI")
		if settingsUI and type(settingsUI.open) == "function" then
			settingsUI.open()
		end
		return
	end
	local center = menusGui and menusGui:FindFirstChild("Center")
	local win = center and center:FindFirstChild(name)
	if not menusGui or not center or not win then
		return
	end
	closeAll()
	for _, w in center:GetChildren() do
		if w:IsA("GuiObject") then
			w.Visible = w == win
		end
	end
	openName = name
	if name == "Classes" then
		renderClasses()
	end
	menusGui.Enabled = true
	pop(win)
end

local function showCountdown(on: boolean)
	setVisible(UIKit.find(modesGui, "Center.Window.Modes"), not on)
	setVisible(UIKit.find(modesGui, "Center.Window.Countdown"), on)
end

local function openModes()
	if not modesGui then
		return
	end
	closeAll()
	showCountdown(false)
	setModeStatus(nil)
	openName = "Modes"
	modesGui.Enabled = true
	pop(UIKit.find(modesGui, "Center.Window"))
end

---------------------------------------------------------------------------- PLAY

local function applyVisibility()
	if lobbyGui then
		lobbyGui.Enabled = not inRun
	end
	if inRun then
		closeAll()
		setStatus(nil)
	end
end

-- Envoie l'intention « prêt » avec la classe choisie. Le serveur valide la classe et le compagnon,
-- puis lance la run (Loadout) ou fait entrer le joueur dans la run en cours (retardataire).
local function sendReady(): boolean
	if os.clock() - sentAt < SEND_COOLDOWN then
		return false
	end
	sentAt = os.clock()
	Net.event("SelectLoadout"):FireServer(currentClass(), currentCompanion())
	closeAll()
	local phase = UITheme.phase()
	if RUN_PHASES[phase] then
		inRun = true
		applyVisibility()
	else
		setStatus(if #Players:GetPlayers() > 1 then "WAITING FOR PLAYERS..." else "GET READY!")
	end
	return true
end

local function startSolo()
	countdownId += 1
	local id = countdownId
	showCountdown(true)
	setModeStatus(nil)
	local num = UIKit.find(modesGui, "Center.Window.Countdown.Number")
	task.spawn(function()
		for n = SOLO_COUNTDOWN, 1, -1 do
			if id ~= countdownId then
				return
			end
			if num then
				num.Text = tostring(n)
				pop(num)
			end
			task.wait(1)
		end
		if id == countdownId and not sendReady() then
			showCountdown(false)
		end
	end)
end

local function inviteFriends()
	task.spawn(function()
		local ok, can = pcall(function()
			return SocialService:CanSendGameInviteAsync(LOCAL)
		end)
		if ok and can then
			pcall(function()
				SocialService:PromptGameInvite(LOCAL)
			end)
			setModeStatus("Friends who join you here can hop in with PUBLIC.")
		else
			setModeStatus("Invites are not available here.")
		end
	end)
end

local function chooseMode(mode: string)
	if mode == "Solo" then
		startSolo()
	elseif mode == "Friends" then
		inviteFriends()
	elseif mode == "Public" then
		sendReady()
	end
end

---------------------------------------------------------------------------- phase de la run

-- Qui est dans la run ? Au passage Loadout -> run (ou Ended -> run, Replay), le serveur prend tous
-- les joueurs (RunManager.startRun). Un joueur qui arrive pendant une run reste au lobby tant qu'il
-- n'a pas appuyé sur PLAY.
local function onRunState(state: any)
	if type(state) ~= "table" or type(state.phase) ~= "string" then
		return
	end
	local phase = state.phase
	if phase == lastPhase then
		return
	end
	local before = lastPhase
	lastPhase = phase
	if phase == "Loadout" then
		inRun = false
		sentAt = -math.huge
	elseif RUN_PHASES[phase] and (before == "Loadout" or before == "Ended") then
		inRun = true
	elseif phase == "Ended" and before == nil then
		inRun = false
	end
	applyVisibility()
end

---------------------------------------------------------------------------- démarrage

local started = false

function LobbyController.start()
	if started then
		return -- lancé par LoadoutUI, et un jour par Main.client : une seule fois
	end
	started = true
	lobbyGui = UIKit.screen("COHUE_Lobby")
	modesGui = UIKit.screen("COHUE_ModeSelect")
	menusGui = UIKit.screen("COHUE_LobbyMenus")
	if not lobbyGui then
		return
	end
	for _, gui in { lobbyGui, modesGui, menusGui } do
		adoptScales(gui)
	end
	if modesGui then
		modesGui.Enabled = false
	end
	if menusGui then
		menusGui.Enabled = false
	end

	-- HUD du hub
	status = UIKit.tag(UIKit.find(lobbyGui, "Bottom.Status"))
	setStatus(nil)
	onPress(UIKit.find(lobbyGui, "Bottom.Play"), openModes)
	for _, name in BAR_ORDER do
		local b = UIKit.find(lobbyGui, "Bottom.Bar." .. name)
		setVisible(b and b:FindFirstChild("Badge"), false) -- pastilles : vague 2 (quêtes, compagnons, améliorations)
		onPress(b, function()
			openMenu(name)
		end)
	end
	onPress(UIKit.find(lobbyGui, "TopRight.Settings"), function()
		openMenu("Settings")
	end)

	-- Choix du mode
	if modesGui then
		local scrim = modesGui:FindFirstChild("Scrim")
		if scrim and scrim:IsA("GuiButton") then
			scrim.Activated:Connect(closeAll)
		end
		onPress(UIKit.find(modesGui, "Center.Window.Header.Close"), closeAll)
		onPress(UIKit.find(modesGui, "Center.Window.Countdown.Cancel"), function()
			countdownId += 1
			showCountdown(false)
		end)
		for _, mode in MODE_ORDER do
			onPress(UIKit.find(modesGui, "Center.Window.Modes." .. mode), function()
				chooseMode(mode)
			end)
		end
	end

	-- Fenêtres des menus
	if menusGui then
		local scrim = menusGui:FindFirstChild("Scrim")
		if scrim and scrim:IsA("GuiButton") then
			scrim.Activated:Connect(closeAll)
		end
		for _, name in BAR_ORDER do
			onPress(UIKit.find(menusGui, "Center." .. name .. ".Header.Close"), closeAll)
		end
		setupClasses()
	end

	-- Clavier : ENTRÉE = PLAY, 1-8 = menus, 1-3 = modes, Échap / B = fermer.
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or inRun then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Escape or key == Enum.KeyCode.ButtonB then
			if openName then
				closeAll()
			end
			return
		end
		local n = NUMBER_KEYS[key]
		if openName == "Modes" then
			if n and MODE_ORDER[n] then
				pop(UIKit.find(modesGui, "Center.Window.Modes." .. MODE_ORDER[n]))
				chooseMode(MODE_ORDER[n])
			end
		elseif openName == nil then
			if key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter then
				pop(UIKit.find(lobbyGui, "Bottom.Play"))
				openModes()
			elseif n and BAR_ORDER[n] then
				openMenu(BAR_ORDER[n])
			end
		end
	end)
	UserInputService.LastInputTypeChanged:Connect(showKeycaps)
	showKeycaps()

	UITheme.changed:connect(function(reason: string)
		if reason == "profile" then
			renderSilver()
			if openName == "Classes" then
				renderClasses()
			end
		end
	end)
	UITheme.watch("RunState", onRunState)
	renderSilver()
	applyVisibility()
end

return LobbyController
