-- COHUE — pose des gabarits d'UI du lobby dans la place (A09, 5 nov. 2026).
--
-- Règle de Clément : rien de visible n'est construit par script en jeu. Ce fichier est un outil
-- d'édition, comme tools/ui/build-ui-v3.luau (A08) : on le lance UNE fois dans Studio
-- (execute_luau, datamodel Edit) sur la place COHUE ; il pose de vrais objets dans StarterGui, que
-- Clément voit, modifie et sauvegarde. Le jeu ne fait ensuite que les retrouver par leur nom
-- (client/Controllers/Lobby/LobbyController.luau), les remplir, les montrer et les animer.
--
-- Écrans posés :
--   COHUE_Lobby       HUD du hub : PLAY, barre des 8 menus, argent (haut gauche), réglages (haut droite)
--   COHUE_ModeSelect  « PLAY WITH... » : Solo / Friends / Public, et le décompte du Solo
--   COHUE_LobbyMenus  une fenêtre par menu (Classes, Critters, Upgrades, Inventory, Quests, Ranks,
--                     Pass, Shop). Classes a ses 8 tuiles ; les autres sont provisoires (COMING SOON)
--
-- Relançable : il ne pose que les écrans absents. Pour refaire un écran déjà posé (que Clément a
-- peut-être retouché), mettre son nom dans REBUILD : l'ancien part d'abord dans ServerStorage.
-- Maquettes : Figma A09 cdIWE7AH9ScXZ0uzzLyv4b (page « 02 · Screens v3 (briques) ») et composants
-- Lobby/* de A08 (0Yq5m1skq5dzgOQXZ9bG6D). Spec : docs/dossier/65-lobby.md §2 et §6.
-- Mesures : pixels logiques du téléphone paysage (844 × 390) ; chaque zone porte un UIScale
-- « Scale » que le code règle selon l'appareil (UITheme.adoptScale), comme les écrans de A08.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")

-- Images : shared/Config/UIAssets (A08). Vide tant que rien n'est téléversé.
local IMG: any = { Studs = "", Icons = {} }
do
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local cfg = shared and shared:FindFirstChild("Config")
	local mod = cfg and cfg:FindFirstChild("UIAssets")
	if mod and mod:IsA("ModuleScript") then
		local ok, res = pcall(require, mod)
		if ok then
			IMG = res
		end
	end
end
local function icon(key: string): string
	return (IMG.Icons and IMG.Icons[key]) or ""
end

---------------------------------------------------------------------------- palette COHUE 16 (= UIKit)
local PAL = {
	Ink = "1C1726", Cream = "FFE8B8", Tomato = "E63946", Leaf = "3DBE4A", Gold = "FFC21A",
	Royal = "2D6BE6", Sky = "3FD0F5", Grape = "8C52E0", Ember = "FF7A1A", Bubblegum = "FF5FB0",
	Stone = "9C9488", Steel = "8EA6C2", Bark = "6E4227", Leather = "B5713A", Plum = "4B3866", Lime = "8FD13F",
}
local LIGHT = Color3.fromHex("FFF4D8")
local SHADOW = Color3.fromHex("2A1C3D")
local function tone(key: string): Color3
	local name, suffix = key:match("^(%a+)%.?(%a*)$")
	local c = Color3.fromHex(PAL[name])
	if suffix == "l" then
		return c:Lerp(LIGHT, 0.35)
	elseif suffix == "d" then
		return c:Lerp(SHADOW, 0.35)
	elseif suffix == "dd" then
		return c:Lerp(SHADOW, 0.6)
	end
	return c
end
local INK = tone("Ink")
local WHITE = Color3.new(1, 1, 1)
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json")
local CENTER = Enum.TextXAlignment.Center

-- Couleur de chaque menu = couleur de sa zone (65-lobby.md §2) : bouton de la barre, en-tête de la
-- fenêtre et bâtiment. Pass passe en Bubblegum : en « ciel », il aurait la couleur de Classes.
local MENUS = {
	{ id = "Classes", label = "Classes", title = "CLASSES", icon = "helm", color = "Sky" },
	{ id = "Critters", label = "Critters", title = "CRITTERS", icon = "acorn", color = "Lime", line = "Your critters will hang out here." },
	{ id = "Upgrades", label = "Upgrades", title = "UPGRADES", icon = "anvil", color = "Grape", line = "Spend silver to get stronger." },
	{ id = "Inventory", label = "Inventory", title = "INVENTORY", icon = "backpack", color = "Steel", line = "Everything you own, in one bag." },
	{ id = "Quests", label = "Quests", title = "QUESTS", icon = "scroll", color = "Royal", line = "Finish quests, unlock new classes." },
	{ id = "Ranks", label = "Ranks", title = "RANKS", icon = "trophy", color = "Gold", line = "Who knocked out the most goblins?" },
	{ id = "Pass", label = "Pass", title = "PASS", icon = "ticket", color = "Bubblegum", line = "Season rewards, just for playing." },
	{ id = "Shop", label = "Shop", title = "SHOP", icon = "coinbag", color = "Ember", line = "Hats, styles and silly stuff." },
}

local MODES = {
	{ id = "Solo", title = "SOLO", line = "Just you", color = "Royal", people = 1 },
	{ id = "Friends", title = "FRIENDS", line = "Invite friends", color = "Leaf", people = 2 },
	{ id = "Public", title = "PUBLIC", line = "Up to 4 players", color = "Gold", people = 4 },
}

---------------------------------------------------------------------------- briques de base (comme A08)
local function new(class: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(class)
	for k, v in props do
		(inst :: any)[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function corner(parent: Instance, r: number): UICorner
	return new("UICorner", { CornerRadius = UDim.new(0, r) }, parent)
end

local function ink(parent: Instance, thickness: number?, color: Color3?): UIStroke
	return new("UIStroke", {
		Name = "Ink",
		Thickness = thickness or 3,
		Color = color or INK,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, parent)
end

-- Texte : Fredoka One blanc, contour encre ≈ 13 % de la taille.
local function text(parent: Instance, name: string, s: string, size: number, props: { [string]: any }?): TextLabel
	local t = new("TextLabel", {
		Name = name,
		Text = s,
		FontFace = FONT,
		TextSize = size,
		TextColor3 = WHITE,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, size + 4),
		AutomaticSize = Enum.AutomaticSize.X,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
	new("UIStroke", {
		Name = "Ink",
		Thickness = math.max(1.5, math.floor(size * 0.13 * 10 + 0.5) / 10),
		Color = INK,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, t)
	if props then
		for k, v in props do
			(t :: any)[k] = v
		end
	end
	return t
end

local function image(parent: Instance, name: string, key: string, size: number, props: { [string]: any }?): ImageLabel
	local i = new("ImageLabel", {
		Name = name,
		Image = icon(key),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		ScaleType = Enum.ScaleType.Fit,
	}, parent)
	i:SetAttribute("IconKey", key)
	if props then
		for k, v in props do
			(i :: any)[k] = v
		end
	end
	return i
end

local function bevel(face: Frame, colorKey: string, height: number)
	local b = math.clamp(3 / math.max(height, 6), 0.02, 0.4)
	new("UIGradient", {
		Name = "Bevel",
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, tone(colorKey .. ".l")),
			ColorSequenceKeypoint.new(b, tone(colorKey .. ".l")),
			ColorSequenceKeypoint.new(math.min(b + 0.001, 0.999), tone(colorKey)),
			ColorSequenceKeypoint.new(1, tone(colorKey)),
		}),
	}, face)
end

local function studs(parent: Instance, lip: number, opacity: number)
	new("ImageLabel", {
		Name = "Studs",
		Image = IMG.Studs or "",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(24, 24),
		ImageTransparency = 1 - opacity,
		Position = UDim2.fromOffset(3, 3),
		Size = UDim2.new(1, -6, 1, -lip - 5),
		ZIndex = 2,
	}, parent)
end

type BrickOpts = { lip: number?, radius: number?, studs: number?, stroke: number? }

-- Brique (même structure que A08, recolorable par UIKit.tint) : racine = lèvre (.dd), Face + biseau.
local function brick(parent: Instance?, name: string, w: number, h: number, colorKey: string, o: BrickOpts?): Frame
	local opts: BrickOpts = o or {}
	local lip = opts.lip or 6
	local r = opts.radius or 6
	local root = new("Frame", {
		Name = name,
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = tone(colorKey .. ".dd"),
		BorderSizePixel = 0,
	}, parent)
	root:SetAttribute("Color", colorKey)
	corner(root, r)
	if (opts.stroke or 3) > 0 then
		ink(root, opts.stroke or 3)
	end
	local face = new("Frame", {
		Name = "Face",
		Size = UDim2.new(1, 0, 1, -lip),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, root)
	corner(face, r)
	bevel(face, colorKey, h - lip)
	if opts.studs then
		studs(root, lip, opts.studs)
	end
	return root
end

-- Étiquette brique à largeur automatique (UIKit.tag la pilote : Label + setTone).
local function tag(parent: Instance?, name: string, s: string, colorKey: string, size: number?): Frame
	local f = new("Frame", {
		Name = name,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, parent)
	f:SetAttribute("Color", colorKey)
	corner(f, 5)
	ink(f, 2.5)
	bevel(f, colorKey, 24)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 1), PaddingBottom = UDim.new(0, 3) }, f)
	text(f, "Label", s, size or 15)
	return f
end

local function list(parent: Instance, horizontal: boolean, padding: number, hAlign: Enum.HorizontalAlignment?, vAlign: Enum.VerticalAlignment?)
	new("UIListLayout", {
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Center,
	}, parent)
end

-- Zone : cadre transparent ancré à un point de l'écran, avec son UIScale « Scale » (réglé par le code).
local function zone(parent: Instance, name: string, anchor: Vector2, pos: UDim2, size: Vector2): Frame
	local z = new("Frame", {
		Name = name,
		AnchorPoint = anchor,
		Position = pos,
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
	}, parent)
	new("UIScale", { Name = "Scale", Scale = 1 }, z)
	return z
end

local function screen(name: string, order: number, enabled: boolean, insets: Enum.ScreenInsets?): ScreenGui
	return new("ScreenGui", {
		Name = name,
		DisplayOrder = order,
		Enabled = enabled,
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ScreenInsets = insets or Enum.ScreenInsets.DeviceSafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		AutoLocalize = false,
	})
end

local function popScale(parent: Instance)
	new("UIScale", { Name = "PopScale", Scale = 1 }, parent)
end

-- Cible invisible qui reçoit les clics, les touchers et la sélection manette.
local function hit(parent: Instance): TextButton
	return new("TextButton", {
		Name = "Hit",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 9,
		Selectable = true,
	}, parent)
end

-- Touche clavier collée au coin d'un bouton ; cachée sur tactile (le code l'affiche au clavier).
local function keycap(parent: Instance, key: string, w: number?): Frame
	local k = brick(parent, "Key", w or 24, 24, "Cream", { lip = 3, radius = 5, stroke = 2 })
	k.Position = UDim2.fromOffset(-8, -8)
	k.ZIndex = 6
	k.Visible = false
	text(k, "Label", key, if w then 13 else 15, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -2), TextXAlignment = CENTER, ZIndex = 7 })
	return k
end

-- Anneau de sélection (doré), autour d'une brique, derrière son contour encre.
local function selectRing(parent: Instance, radius: number)
	local sel = new("Frame", { Name = "Select", Position = UDim2.fromOffset(-4, -4), Size = UDim2.new(1, 8, 1, 8), BackgroundTransparency = 1, Visible = false, ZIndex = 0 }, parent)
	corner(sel, radius + 3)
	new("UIStroke", { Name = "Ring", Thickness = 3.5, Color = tone("Gold.l"), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, sel)
end

-- Fenêtre de couleur : cadre de couleur + corps prune foncé (Inner), contour encre (comme A08).
local function windowBody(parent: Instance, name: string, x: number, y: number, w: number, h: number, colorKey: string): Frame
	local body = new("Frame", { Name = name, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundColor3 = tone(colorKey), BorderSizePixel = 0 }, parent)
	body:SetAttribute("Color", colorKey)
	corner(body, 10)
	ink(body, 3)
	local inner = new("Frame", { Name = "Inner", Position = UDim2.fromOffset(5, 5), Size = UDim2.new(1, -10, 1, -10), BackgroundColor3 = tone("Plum.dd"), BorderSizePixel = 0 }, body)
	corner(inner, 7)
	return body
end

-- Bouton de fermeture v3 : brique rouge de 44 px, croix blanche cerclée d'encre.
local function closeButton(parent: Instance): Frame
	local b = brick(parent, "Close", 44, 44, "Tomato", { lip = 5, radius = 8, studs = 0.25 })
	b.AnchorPoint = Vector2.new(1, 0)
	b.Position = UDim2.new(1, -6, 0, 2)
	b.ZIndex = 4
	popScale(b)
	local cross = new("Frame", { Name = "Cross", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -3), Size = UDim2.fromOffset(24, 24), BackgroundTransparency = 1, ZIndex = 5 }, b)
	for i, rot in { 45, -45 } do
		local bar = new("Frame", {
			Name = "Bar" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(24, 6),
			Rotation = rot,
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			ZIndex = 5,
		}, cross)
		corner(bar, 3)
		ink(bar, 2)
	end
	hit(b)
	return b
end

-- Fond assombri plein écran ; le toucher ferme la fenêtre (le code branche Activated).
local function scrim(gui: ScreenGui)
	new("TextButton", {
		Name = "Scrim",
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		ZIndex = 0,
	}, gui)
end

-- Sous une fenêtre : capte les touchers sur son corps, pour qu'ils n'atteignent pas le Scrim.
local function blocker(parent: Instance)
	new("TextButton", {
		Name = "Blocker",
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
	}, parent)
end

-- Silhouette de joueur (tête + épaules) pour les briques de mode.
local function person(parent: Instance, n: number)
	local p = new("Frame", { Name = "Person" .. n, Size = UDim2.fromOffset(24, 34), BackgroundTransparency = 1, LayoutOrder = n, ZIndex = 3 }, parent)
	local head = new("Frame", { Name = "Head", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(15, 15), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 3 }, p)
	corner(head, 8)
	ink(head, 2)
	local body = new("Frame", { Name = "Body", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.fromOffset(24, 16), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 3 }, p)
	corner(body, 8)
	ink(body, 2)
end

---------------------------------------------------------------------------- sauvegarde
local backup = new("Folder", { Name = "A09_LobbyUIBackup_" .. os.date("!%Y%m%d_%H%M%S") })
local function park(inst: Instance?)
	if inst then
		inst.Parent = backup
	end
end

---------------------------------------------------------------------------- COHUE_Lobby
-- Bouton de la barre : tuile sombre cerclée de la couleur du menu, grosse icône qui dépasse en
-- haut, libellé ajusté (15 px au plus), pastille rouge (cachée), touche 1-8 au clavier.
local function barButton(parent: Instance, i: number, m: any): Frame
	local b = new("Frame", { Name = m.id, Size = UDim2.fromOffset(66, 60), BackgroundColor3 = tone("Plum.dd"), BackgroundTransparency = 0.05, BorderSizePixel = 0, LayoutOrder = i }, parent)
	b:SetAttribute("Menu", m.id)
	b:SetAttribute("Color", m.color)
	corner(b, 8)
	ink(b, 3)
	popScale(b)
	local rim = new("Frame", { Name = "Rim", Position = UDim2.fromOffset(3, 3), Size = UDim2.new(1, -6, 1, -6), BackgroundTransparency = 1 }, b)
	corner(rim, 6)
	new("UIStroke", { Name = "Edge", Thickness = 2.5, Color = tone(m.color), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, rim)
	image(b, "Icon", m.icon, 46, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -16), ZIndex = 3 })
	local label = text(b, "Label", m.label, 15, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -3),
		Size = UDim2.new(1, -6, 0, 18),
		AutomaticSize = Enum.AutomaticSize.None,
		TextScaled = true,
		TextXAlignment = CENTER,
		ZIndex = 3,
	})
	new("UITextSizeConstraint", { MaxTextSize = 15, MinTextSize = 10 }, label)
	local badge = tag(b, "Badge", "1", "Tomato", 14)
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Position = UDim2.new(1, -2, 0, 2)
	badge.ZIndex = 5
	badge.Visible = false
	keycap(b, tostring(i))
	hit(b)
	return b
end

local function buildLobby(): ScreenGui
	local gui = screen("COHUE_Lobby", 12, true)

	-- Bas centre : PLAY (seule action verte), puis la barre des 8 menus (entre joystick et Saut).
	local bottom = zone(gui, "Bottom", Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -8), Vector2.new(556, 140))
	local status = tag(bottom, "Status", "WAITING FOR PLAYERS...", "Gold", 16)
	status.AnchorPoint = Vector2.new(0.5, 1)
	status.Position = UDim2.new(0.5, 0, 0, -6)
	status.Visible = false
	local play = brick(bottom, "Play", 220, 58, "Leaf", { lip = 6, radius = 10, studs = 0.32 })
	play.AnchorPoint = Vector2.new(0.5, 0)
	play.Position = UDim2.new(0.5, 0, 0, 0)
	popScale(play)
	text(play, "Label", "PLAY", 32, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -3), TextXAlignment = CENTER, ZIndex = 3 })
	keycap(play, "ENTER", 52)
	hit(play)
	local bar = new("Frame", { Name = "Bar", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.fromOffset(556, 60), BackgroundTransparency = 1 }, bottom)
	list(bar, true, 4, Enum.HorizontalAlignment.Center)
	for i, m in MENUS do
		barButton(bar, i, m)
	end

	-- Haut gauche : l'argent gagné en run (les Robux n'apparaissent que sur les boutons de prix).
	local tl = zone(gui, "TopLeft", Vector2.zero, UDim2.fromOffset(12, 8), Vector2.new(220, 44))
	local silver = new("Frame", { Name = "Silver", Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = tone("Plum.dd"), BackgroundTransparency = 0.1, BorderSizePixel = 0 }, tl)
	corner(silver, 8)
	ink(silver, 3)
	new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 12) }, silver)
	list(silver, true, 6)
	image(silver, "Icon", "coin", 32, { LayoutOrder = 1 })
	text(silver, "Amount", "0", 20, { LayoutOrder = 2 })

	-- Haut droite : réglages (ouvre SettingsUI de A08).
	local tr = zone(gui, "TopRight", Vector2.new(1, 0), UDim2.new(1, -12, 0, 8), Vector2.new(46, 46))
	local gear = brick(tr, "Settings", 46, 46, "Stone", { lip = 5, radius = 8, studs = 0.25 })
	popScale(gear)
	image(gear, "Icon", "settings_light", 30, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -3), ZIndex = 3 })
	hit(gear)
	return gui
end

---------------------------------------------------------------------------- COHUE_ModeSelect
local function modeChoice(parent: Instance, i: number, m: any): Frame
	local b = brick(parent, m.id, 156, 136, m.color, { lip = 7, radius = 10, studs = 0.3 })
	b.LayoutOrder = i
	popScale(b)
	selectRing(b, 10)
	text(b, "Title", m.title, 24, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), TextXAlignment = CENTER, ZIndex = 3 })
	local people = new("Frame", { Name = "People", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 2), Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, ZIndex = 3 }, b)
	list(people, true, 3, Enum.HorizontalAlignment.Center)
	for n = 1, m.people do
		person(people, n)
	end
	text(b, "Line", m.line, 15, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -13), TextXAlignment = CENTER, ZIndex = 3 })
	keycap(b, tostring(i))
	hit(b)
	return b
end

local function buildModes(): ScreenGui
	local gui = screen("COHUE_ModeSelect", 30, false, Enum.ScreenInsets.None)
	gui.IgnoreGuiInset = true
	scrim(gui)
	local z = zone(gui, "Center", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), Vector2.new(540, 252))
	local win = new("Frame", { Name = "Window", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, z)
	popScale(win)
	blocker(win)
	windowBody(win, "Body", 0, 26, 540, 226, "Grape")
	local head = brick(win, "Header", 540, 54, "Grape", { lip = 6, radius = 8, studs = 0.4 })
	text(head, "Title", "PLAY WITH...", 28, { Position = UDim2.fromOffset(16, 6), ZIndex = 3 })
	closeButton(head)

	local modes = new("Frame", { Name = "Modes", Position = UDim2.fromOffset(16, 74), Size = UDim2.fromOffset(508, 140), BackgroundTransparency = 1 }, win)
	list(modes, true, 14, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)
	for i, m in MODES do
		modeChoice(modes, i, m)
	end

	-- Décompte du Solo (3 s) : remplace les modes, avec CANCEL.
	local cd = new("Frame", { Name = "Countdown", Position = UDim2.fromOffset(16, 74), Size = UDim2.fromOffset(508, 140), BackgroundTransparency = 1, Visible = false }, win)
	local num = text(cd, "Number", "3", 64, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -6), TextXAlignment = CENTER })
	popScale(num)
	text(cd, "Line", "Starting your run...", 18, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 66), TextXAlignment = CENTER, TextColor3 = tone("Cream") })
	local cancel = brick(cd, "Cancel", 150, 44, "Stone", { lip = 5, radius = 8, studs = 0.25 })
	cancel.AnchorPoint = Vector2.new(0.5, 1)
	cancel.Position = UDim2.new(0.5, 0, 1, 0)
	popScale(cancel)
	text(cancel, "Label", "CANCEL", 18, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -3), TextXAlignment = CENTER, ZIndex = 3 })
	hit(cancel)

	-- Ligne d'état sous les modes (invitation envoyée, etc.).
	text(win, "Status", "", 15, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 222), TextXAlignment = CENTER, TextColor3 = tone("Cream"), Visible = false })
	return gui
end

---------------------------------------------------------------------------- COHUE_LobbyMenus
local function classTile(parent: Instance, i: number): Frame
	local t = brick(parent, "Tile" .. i, 134, 88, "Royal", { lip = 5, radius = 8, studs = 0.22 })
	t.LayoutOrder = i
	popScale(t)
	selectRing(t, 8)
	image(t, "Icon", "", 48, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 3), ZIndex = 3 })
	text(t, "Name", "Class", 17, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), TextXAlignment = CENTER, ZIndex = 3 })
	image(t, "Lock", "lock", 26, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 4), ZIndex = 4, Visible = false })
	local picked = tag(t, "Picked", "PICKED", "Leaf", 13)
	picked.Position = UDim2.fromOffset(-6, -9)
	picked.ZIndex = 5
	picked.Visible = false
	hit(t)
	return t
end

local function menuWindow(parent: Instance, m: any): Frame
	local w = new("Frame", { Name = m.id, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(600, 300), BackgroundTransparency = 1, Visible = false }, parent)
	w:SetAttribute("Color", m.color)
	popScale(w)
	blocker(w)
	windowBody(w, "Body", 0, 26, 600, 274, m.color)
	local head = brick(w, "Header", 600, 54, m.color, { lip = 6, radius = 8, studs = 0.4 })
	image(head, "Icon", m.icon, 46, { Position = UDim2.fromOffset(8, -4), ZIndex = 4 })
	text(head, "Title", m.title, 28, { Position = UDim2.fromOffset(60, 6), ZIndex = 3 })
	closeButton(head)
	local content = new("Frame", { Name = "Content", Position = UDim2.fromOffset(20, 72), Size = UDim2.fromOffset(560, 212), BackgroundTransparency = 1 }, w)

	if m.id == "Classes" then
		-- 8 tuiles (4 × 2) remplies par le code d'après Config.Classes ; cadenas sur les classes à débloquer.
		local grid = new("Frame", { Name = "Tiles", Size = UDim2.fromOffset(560, 184), BackgroundTransparency = 1 }, content)
		new("UIGridLayout", {
			CellSize = UDim2.fromOffset(134, 88),
			CellPadding = UDim2.fromOffset(8, 8),
			FillDirectionMaxCells = 4,
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}, grid)
		for i = 1, 8 do
			classTile(grid, i)
		end
		text(content, "Hint", "Tap a class to pick it.", 16, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), TextXAlignment = CENTER, TextColor3 = tone("Cream") })
	else
		-- Provisoire : le menu viendra en vague 2 (65-lobby.md §6).
		local soon = tag(content, "Soon", "COMING SOON", "Gold", 22)
		soon.AnchorPoint = Vector2.new(0.5, 0.5)
		soon.Position = UDim2.new(0.5, 0, 0.5, -20)
		text(content, "Line", m.line or "", 18, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 14), TextXAlignment = CENTER, TextColor3 = tone("Cream") })
	end
	return w
end

local function buildMenus(): ScreenGui
	local gui = screen("COHUE_LobbyMenus", 30, false, Enum.ScreenInsets.None)
	gui.IgnoreGuiInset = true
	scrim(gui)
	local z = zone(gui, "Center", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), Vector2.new(600, 300))
	for _, m in MENUS do
		menuWindow(z, m)
	end
	return gui
end

---------------------------------------------------------------------------- montage
local SCREENS: { { name: string, build: () -> ScreenGui } } = {
	{ name = "COHUE_Lobby", build = buildLobby },
	{ name = "COHUE_ModeSelect", build = buildModes },
	{ name = "COHUE_LobbyMenus", build = buildMenus },
}

-- Écrans à refaire même s'ils existent déjà (l'ancien part dans ServerStorage).
local REBUILD: { [string]: boolean } = {}

local made: { string } = {}
local kept: { string } = {}
for _, s in SCREENS do
	local old = StarterGui:FindFirstChild(s.name)
	if old and not REBUILD[s.name] then
		table.insert(kept, s.name)
		continue
	end
	park(old)
	local gui = s.build()
	gui.Parent = StarterGui
	table.insert(made, gui:GetFullName())
	task.wait()
end

local backupPath: string? = nil
if #backup:GetChildren() > 0 then
	backup.Parent = ServerStorage
	backupPath = backup:GetFullName()
end

local missingIcons = {}
for _, m in MENUS do
	if icon(m.icon) == "" then
		table.insert(missingIcons, m.icon)
	end
end
return {
	made = made,
	kept = kept,
	backup = backupPath,
	missingIcons = missingIcons,
	studsImage = (IMG.Studs or "") ~= "",
}
