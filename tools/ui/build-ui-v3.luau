-- COHUE — montage des gabarits d'UI v3 « vraies briques » dans la place (A08, 5 nov. 2026).
--
-- Règle de Clément : rien de visible n'est construit par script en jeu. Ce fichier est un outil
-- d'édition, comme A01_finalize.luau : on le lance UNE fois dans Studio (execute_luau, datamodel
-- Edit) sur la place COHUE ; il pose de vrais objets dans StarterGui et ReplicatedStorage.Assets.UI,
-- que Clément voit, modifie et sauvegarde. Les scripts du jeu ne font ensuite que les retrouver par
-- leur nom, changer leurs propriétés et les animer.
--
-- Relançable : il ne pose que ce qui manque (un écran absent de StarterGui, une pièce absente
-- d'Assets.UI). Pour refaire un écran déjà posé, que Clément a peut-être retouché, mettre son nom
-- dans REBUILD plus bas : l'ancien part d'abord dans ServerStorage (sauvegarde).
-- Maquettes : Figma 0Yq5m1skq5dzgOQXZ9bG6D, pages « Components v3 — briques » et « Run v3 — … ».
-- Mesures : pixels logiques du téléphone paysage (844 × 390) ; chaque zone porte un UIScale
-- « Scale » que le code règle selon l'appareil (×1,6 sur PC).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")

-- Images : shared/Config/UIAssets (vide tant que rien n'est téléversé).
local IMG: any = { Studs = "", Rays = "", Icons = {} }
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

---------------------------------------------------------------------------- palette COHUE 16
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

---------------------------------------------------------------------------- helpers
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

local function corner(parent: Instance, r: number)
	new("UICorner", { CornerRadius = UDim.new(0, r) }, parent)
end

local function ink(parent: Instance, thickness: number?, color: Color3?)
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

-- Bande claire du biseau en haut de la face (UIGradient : suit les coins arrondis).
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

-- Brique : racine = lèvre (ton .dd), Face = couleur + biseau, Studs = tenons en tuile, contour encre.
-- Le code la teinte avec UIKit.tint(brique, "Tomato") (couleurs de la racine, de la face et du biseau).
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

-- Piste de barre : fond encre translucide, contour, Fill (frame à remplir en échelle X).
local function track(parent: Instance, name: string, w: number, h: number, fillKey: string, withStuds: boolean?): Frame
	local t = new("Frame", {
		Name = name,
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, parent)
	corner(t, if h >= 16 then 6 else 3)
	ink(t, if h >= 16 then 3 else 2.5)
	local fill = new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0.72, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, t)
	fill:SetAttribute("Color", fillKey)
	bevel(fill, fillKey, h)
	if withStuds then
		new("ImageLabel", {
			Name = "Studs",
			Image = IMG.Studs or "",
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(24, 24),
			ImageTransparency = 0.55,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.new(1, 0, 0, 12),
			ZIndex = 3,
		}, fill)
	end
	return t
end

-- Étiquette brique à largeur automatique (NEW!, Lv 2 → 4, OVERTIME, NEW BEST!...).
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

local function slot(parent: Instance, name: string, size: number, order: number): Frame
	local s = brick(parent, name, size, size, "Cream", { lip = 5, radius = 6 })
	s.LayoutOrder = order
	image(s, "Icon", "", math.round(size * 0.82), { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -2), ZIndex = 3 })
	text(s, "Initials", "", math.round(size * 0.36), { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -2), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3, Visible = false })
	local lv = tag(s, "Level", "Lv1", "Gold", 14)
	lv.AnchorPoint = Vector2.new(1, 1)
	lv.Position = UDim2.new(1, 8, 1, 10)
	lv.ZIndex = 4
	return s
end

-- Touche clavier (« 1 », « R ») collée au coin d'une carte ou d'un bouton ; cachée sur tactile.
local function keycap(parent: Instance, key: string): Frame
	local k = brick(parent, "Key", 24, 24, "Cream", { lip = 3, radius = 5, stroke = 2 })
	k.Position = UDim2.fromOffset(-8, -8)
	k.ZIndex = 6
	k.Visible = false
	text(k, "Label", key, 15, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -2), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 7 })
	return k
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

-- Fenêtre de couleur : cadre de couleur + corps prune foncé (Inner), contour encre.
local function windowBody(parent: Instance, name: string, x: number, y: number, w: number, h: number, colorKey: string): Frame
	local body = new("Frame", { Name = name, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundColor3 = tone(colorKey), BorderSizePixel = 0 }, parent)
	body:SetAttribute("Color", colorKey)
	corner(body, 10)
	ink(body, 3)
	local inner = new("Frame", { Name = "Inner", Position = UDim2.fromOffset(5, 5), Size = UDim2.new(1, -10, 1, -10), BackgroundColor3 = tone("Plum.dd"), BorderSizePixel = 0 }, body)
	corner(inner, 7)
	return body
end

-- Panneau latéral (inventaire, stats) : corps prune foncé, barre de titre prune à tenons.
local function sidePanel(parent: Instance, name: string, title: string, x: number, y: number, w: number, h: number): (Frame, Frame)
	local p = new("Frame", { Name = name, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundTransparency = 1 }, parent)
	new("UIScale", { Name = "PopScale", Scale = 1 }, p)
	local body = new("Frame", { Name = "Body", Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 1, -30), BackgroundColor3 = tone("Plum.dd"), BackgroundTransparency = 0.04, BorderSizePixel = 0 }, p)
	corner(body, 8)
	ink(body, 3)
	local header = brick(p, "Header", w, 38, "Plum", { lip = 5, radius = 8, studs = 0.3 })
	text(header, "Title", title, 18, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
	return p, body
end

-- Case d'inventaire : brique crème de 36 px + niveau ou nombre écrit dessous (« Lv4 », « x2 »).
local function cell(parent: Instance, i: number): Frame
	local c = new("Frame", { Name = "Cell" .. i, Size = UDim2.fromOffset(36, 50), BackgroundTransparency = 1, LayoutOrder = i }, parent)
	local s = brick(c, "Slot", 36, 36, "Cream", { lip = 4, radius = 6, stroke = 2.5 })
	image(s, "Icon", "", 30, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -2), ZIndex = 3 })
	text(s, "Initials", "", 15, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -2), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3, Visible = false })
	new("UIScale", { Name = "PopScale", Scale = 1 }, s)
	text(c, "Level", "Lv1", 14, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 34), TextXAlignment = Enum.TextXAlignment.Center })
	return c
end

---------------------------------------------------------------------------- sauvegarde
local backup = new("Folder", { Name = "A08_UIBackup_" .. os.date("!%Y%m%d_%H%M%S") })
local function park(inst: Instance?)
	if inst then
		inst.Parent = backup
	end
end

---------------------------------------------------------------------------- COHUE_HUD
local function buildHud(): ScreenGui
	local gui = screen("COHUE_HUD", 10, true)

	-- Haut gauche : vitals, compagnon, équipiers, fil des pings (sous la barre Roblox).
	local tl = zone(gui, "TopLeft", Vector2.zero, UDim2.fromOffset(12, 64), Vector2.new(300, 300))
	list(tl, false, 10, nil, Enum.VerticalAlignment.Top)
	local vit = new("Frame", { Name = "Vitals", Size = UDim2.fromOffset(280, 62), BackgroundColor3 = tone("Plum.dd"), BackgroundTransparency = 0.1, BorderSizePixel = 0, LayoutOrder = 1 }, tl)
	corner(vit, 8)
	ink(vit, 3)
	local lv = brick(vit, "Level", 52, 52, "Sky", { lip = 6 })
	lv.Position = UDim2.fromOffset(5, 5)
	text(lv, "Label", "LV", 14, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 2), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
	text(lv, "Number", "1", 24, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 15), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
	new("UIScale", { Name = "PopScale", Scale = 1 }, lv)
	local hp = track(vit, "Hp", 184, 26, "Tomato", true)
	hp.Position = UDim2.fromOffset(88, 7)
	local shield = new("Frame", { Name = "Shield", Size = UDim2.fromScale(0, 1), BackgroundColor3 = tone("Steel.l"), BorderSizePixel = 0, Visible = false, ZIndex = 2 }, hp)
	shield:SetAttribute("Color", "Steel")
	text(hp, "Value", "100/100", 15, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4 })
	text(hp, "ShieldValue", "", 14, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 26, 0.5, 0), TextColor3 = tone("Steel.l"), ZIndex = 4 })
	image(vit, "Heart", "hp", 34, { Position = UDim2.fromOffset(58, 1), ZIndex = 5 })
	local xp = track(vit, "Xp", 112, 11, "Sky")
	xp.Position = UDim2.fromOffset(88, 42)
	image(vit, "Coin", "coin", 26, { Position = UDim2.fromOffset(206, 34) })
	text(vit, "Silver", "0", 18, { Position = UDim2.fromOffset(234, 34) })

	text(tl, "Companion", "", 15, { LayoutOrder = 2, Visible = false })

	local team = new("Frame", { Name = "Team", Size = UDim2.fromOffset(300, 36), BackgroundTransparency = 1, LayoutOrder = 3 }, tl)
	list(team, true, 10)
	for i = 1, 3 do
		local m = new("Frame", { Name = "Mate" .. i, Size = UDim2.fromOffset(88, 36), BackgroundTransparency = 1, LayoutOrder = i, Visible = false }, team)
		local p = new("ImageLabel", { Name = "Portrait", Size = UDim2.fromOffset(32, 32), BackgroundColor3 = tone("Cream.d"), BorderSizePixel = 0, Image = "", ScaleType = Enum.ScaleType.Crop }, m)
		corner(p, 5)
		ink(p, 3, tone("Royal")).Name = "Rim"
		text(p, "Initial", "", 16, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), TextXAlignment = Enum.TextXAlignment.Center })
		text(m, "Name", "Name", 14, { Position = UDim2.fromOffset(38, -3) })
		local b = track(m, "Bar", 48, 9, "Leaf")
		b.Position = UDim2.fromOffset(38, 20)
		local st = tag(m, "State", "DOWN", "Tomato", 14)
		st.Position = UDim2.fromOffset(36, 15)
		st.Visible = false
	end

	local feed = new("Frame", { Name = "Feed", Size = UDim2.fromOffset(300, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 4 }, tl)
	list(feed, false, 4, nil, Enum.VerticalAlignment.Top)
	for i = 1, 3 do
		local line = new("Frame", { Name = "Line" .. i, Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = INK, BackgroundTransparency = 0.2, BorderSizePixel = 0, LayoutOrder = i, Visible = false }, feed)
		corner(line, 6)
		ink(line, 2)
		new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 10) }, line)
		list(line, true, 6)
		local dot = new("Frame", { Name = "Dot", Size = UDim2.fromOffset(16, 16), BackgroundColor3 = tone("Leaf"), BorderSizePixel = 0, LayoutOrder = 1 }, line)
		corner(dot, 4)
		ink(dot, 2)
		text(line, "Text", "", 15, { LayoutOrder = 2 })
	end

	-- Haut centre : chrono (sans pastille), monde, Overtime, flèche et barre du boss.
	local tc = zone(gui, "TopCenter", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 4), Vector2.new(340, 170))
	list(tc, false, 2, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)
	local timer = new("Frame", { Name = "Timer", Size = UDim2.fromOffset(0, 36), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, LayoutOrder = 1 }, tc)
	list(timer, true, 6)
	new("UIScale", { Name = "PopScale", Scale = 1 }, timer)
	image(timer, "Clock", "timer", 30, { LayoutOrder = 1 })
	image(timer, "Stopwatch", "timer", 30, { LayoutOrder = 1, Visible = false, ImageColor3 = tone("Tomato.l") })
	text(timer, "Time", "10:00", 28, { LayoutOrder = 2 })
	local cap = new("Frame", { Name = "Caption", Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, LayoutOrder = 2 }, tc)
	list(cap, true, 6)
	text(cap, "World", "WORLD 1/3", 15, { LayoutOrder = 1 })
	tag(cap, "Overtime", "OVERTIME", "Tomato", 14).Visible = false
	local danger = tag(cap, "Danger", "DANGER 1", "Gold", 14)
	danger.LayoutOrder = 3
	danger.Visible = false
	local arrow = brick(tc, "BossArrow", 128, 36, "Tomato", { lip = 5, radius = 8 })
	arrow.LayoutOrder = 3
	arrow.Visible = false
	arrow.AutomaticSize = Enum.AutomaticSize.X
	local inner = new("Frame", { Name = "Row", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3 }, arrow)
	new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 5) }, inner)
	list(inner, true, 6)
	local holder = new("Frame", { Name = "Arrow", Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 1, LayoutOrder = 1 }, inner)
	for i, x in { -4, 4 } do
		local bar = new("Frame", { Size = UDim2.fromOffset(13, 5), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, x, 0.5, 0), Rotation = if i == 1 then -45 else 45, BackgroundColor3 = WHITE, BorderSizePixel = 0 }, holder)
		corner(bar, 2)
	end
	text(inner, "Distance", "BOSS 0 m", 15, { LayoutOrder = 2 })
	local boss = new("Frame", { Name = "BossBar", Size = UDim2.fromOffset(320, 52), BackgroundTransparency = 1, LayoutOrder = 4, Visible = false }, tc)
	image(boss, "Icon", "oak", 44, { Position = UDim2.fromOffset(0, 4) })
	text(boss, "Name", "BOSS", 16, { Position = UDim2.fromOffset(48, -2) })
	local bb = track(boss, "Bar", 270, 22, "Grape", true)
	bb.Position = UDim2.fromOffset(48, 26)
	text(bb, "Pct", "100%", 14, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4 })
	for i = 1, 4 do
		local pip = new("Frame", { Name = "Pip" .. i, Size = UDim2.fromOffset(8, 8), Position = UDim2.new(1, -10 * i - 2, 0, 6), Rotation = 45, BackgroundColor3 = tone("Tomato"), BorderSizePixel = 0, Visible = false }, boss)
		ink(pip, 1.5)
	end

	-- Haut droite : KO (le plus gros chiffre), record. La mini-carte est à droite (module Minimap).
	local tr = zone(gui, "TopRight", Vector2.new(1, 0), UDim2.new(1, -116, 0, 2), Vector2.new(220, 76))
	list(tr, false, 0, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Top)
	local koRow = new("Frame", { Name = "Ko", Size = UDim2.fromOffset(0, 46), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, LayoutOrder = 1 }, tr)
	list(koRow, true, 6, Enum.HorizontalAlignment.Right)
	new("UIScale", { Name = "PopScale", Scale = 1 }, koRow)
	image(koRow, "Icon", "ko", 44, { LayoutOrder = 1 })
	text(koRow, "Count", "0", 34, { LayoutOrder = 2 })
	local best = new("Frame", { Name = "Best", Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, LayoutOrder = 2 }, tr)
	list(best, true, 4, Enum.HorizontalAlignment.Right)
	text(best, "BestText", "BEST —", 15, { TextColor3 = tone("Gold"), LayoutOrder = 1 })
	local nb = tag(best, "NewBest", "NEW BEST!", "Tomato", 15)
	nb.LayoutOrder = 2
	nb.Visible = false

	-- Bas centre : armes (et Runes, rangée cachée par défaut en v3).
	local bc = zone(gui, "BottomCenter", Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -28), Vector2.new(360, 60))
	local build = new("Frame", { Name = "Build", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, bc)
	list(build, false, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom)
	local weapons = new("Frame", { Name = "Weapons", Size = UDim2.fromOffset(0, 50), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, LayoutOrder = 2 }, build)
	list(weapons, true, 10, Enum.HorizontalAlignment.Center)
	for i = 1, 6 do
		slot(weapons, "Slot" .. i, 46, i).Visible = i <= 4
	end
	local runes = new("Frame", { Name = "Runes", Size = UDim2.fromOffset(0, 38), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, LayoutOrder = 1, Visible = false }, build)
	list(runes, true, 8, Enum.HorizontalAlignment.Center)
	for i = 1, 6 do
		slot(runes, "Slot" .. i, 34, i).Visible = i <= 4
	end

	-- Annonces : couloir central, sous la rangée des équipiers.
	local an = zone(gui, "Announce", Vector2.new(0.5, 0), UDim2.new(0.5, 66, 0, 84), Vector2.new(272, 62))
	local banner = brick(an, "Banner", 272, 62, "Tomato", { lip = 6, radius = 8, studs = 0.32 })
	banner.Visible = false
	banner.AutomaticSize = Enum.AutomaticSize.X
	new("UIScale", { Name = "PopScale", Scale = 1 }, banner)
	local col = new("Frame", { Name = "Text", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3 }, banner)
	new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), PaddingBottom = UDim.new(0, 6) }, col)
	list(col, false, 0, Enum.HorizontalAlignment.Center)
	text(col, "Title", "OVERTIME!", 19, { LayoutOrder = 1, TextXAlignment = Enum.TextXAlignment.Center })
	text(col, "Line", "", 15, { LayoutOrder = 2, TextXAlignment = Enum.TextXAlignment.Center, Visible = false })
	return gui
end

---------------------------------------------------------------------------- COHUE_Downed + COHUE_Vignette
local function buildDowned(): (ScreenGui, ScreenGui)
	local vig = screen("COHUE_Vignette", 9, false, Enum.ScreenInsets.None)
	local ring = new("Frame", { Name = "Ring", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -40, 1, -40) }, vig)
	new("UIStroke", { Name = "Edge", Thickness = 46, Color = tone("Tomato"), Transparency = 0.45 }, ring)

	local gui = screen("COHUE_Downed", 25, false)
	local z = zone(gui, "Center", Vector2.new(0.5, 0.5), UDim2.new(0.5, 0, 0.5, 30), Vector2.new(300, 160))
	local panel = new("Frame", { Name = "Panel", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, z)
	local body = new("Frame", { Name = "Body", Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 1, -42), BackgroundColor3 = tone("Plum.dd"), BackgroundTransparency = 0.04, BorderSizePixel = 0 }, panel)
	corner(body, 8)
	ink(body, 3)
	local rimF = new("Frame", { Name = "RimFrame", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, body)
	corner(rimF, 8)
	new("UIStroke", { Name = "Rim", Thickness = 4, Color = tone("Tomato"), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, rimF)
	local secs = new("Frame", { Name = "Seconds", Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1 }, body)
	list(secs, true, 6, Enum.HorizontalAlignment.Center)
	text(secs, "N", "18", 22, { LayoutOrder = 1 })
	text(secs, "Caption", "s to get revived", 17, { LayoutOrder = 2 })
	local rb = track(body, "ReviveBar", 252, 18, "Leaf", true)
	rb.Position = UDim2.fromOffset(24, 50)
	text(body, "Revive", "", 15, { Position = UDim2.fromOffset(24, 76), TextColor3 = tone("Leaf.l") })
	text(body, "Hint", "", 14, { Position = UDim2.fromOffset(16, 76), Size = UDim2.new(1, -32, 0, 36), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = true, TextColor3 = tone("Cream"), Visible = false })
	local back = tag(body, "Back", "BACK AT THE NEXT WORLD", "Sky", 15)
	back.AnchorPoint = Vector2.new(0.5, 0)
	back.Position = UDim2.new(0.5, 0, 0, 78)
	back.Visible = false
	local header = brick(panel, "Header", 300, 52, "Tomato", { lip = 6, radius = 8, studs = 0.4 })
	text(header, "Title", "DOWNED!", 26, { Position = UDim2.fromOffset(16, 8), ZIndex = 3 })
	return gui, vig
end

---------------------------------------------------------------------------- COHUE_LevelUp + COHUE_Freeze
-- Figma L04 / L04b / L04c (Run v3 — Phone landscape). Composition en 760 × 396 logiques :
-- inventaire à gauche, fenêtre « LEVEL 13! » au centre, stats à droite. Le code (CardUI) règle
-- l'échelle pour que tout tienne dans la zone sûre, et range les panneaux en colonne en portrait.
local RARITY_COLOR = { Common = "Cream", Rare = "Royal", Epic = "Grape", Legendary = "Gold" }

local function offerCard(parent: Instance, i: number): Frame
	local c = brick(parent, "Offer" .. i, 344, 70, RARITY_COLOR.Rare, { lip = 5, radius = 8, studs = 0.22 })
	c.LayoutOrder = i
	new("UIScale", { Name = "PopScale", Scale = 1 }, c)
	-- Anneau de sélection, autour de la carte (derrière le contour encre).
	local sel = new("Frame", { Name = "Select", Position = UDim2.fromOffset(-4, -4), Size = UDim2.new(1, 8, 1, 8), BackgroundTransparency = 1, Visible = false, ZIndex = 0 }, c)
	corner(sel, 11)
	new("UIStroke", { Name = "Ring", Thickness = 3.5, Color = tone("Gold.l"), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, sel)
	image(c, "Icon", "", 58, { Position = UDim2.fromOffset(4, 3), ZIndex = 4 })
	text(c, "Initials", "", 26, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(33, 31), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4, Visible = false })
	text(c, "Title", "Spinning Axes", 19, { Position = UDim2.fromOffset(70, 5), Size = UDim2.fromOffset(186, 24), AutomaticSize = Enum.AutomaticSize.None, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3 })
	text(c, "Line", "2 axes orbit around you", 15, {
		Position = UDim2.fromOffset(70, 31),
		Size = UDim2.fromOffset(196, 32),
		AutomaticSize = Enum.AutomaticSize.None,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 3,
	})
	local t = tag(c, "Tag", "NEW!", "Tomato", 15)
	t.AnchorPoint = Vector2.new(1, 0)
	t.Position = UDim2.new(1, -8, 0, 6)
	t.ZIndex = 4
	text(c, "Rarity", "RARE", 14, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -10, 1, -9), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3 })
	keycap(c, tostring(i))
	local veil = new("Frame", { Name = "Veil", Size = UDim2.new(1, 0, 1, -5), BackgroundColor3 = tone("Tomato.dd"), BackgroundTransparency = 0.3, BorderSizePixel = 0, Visible = false, ZIndex = 5 }, c)
	corner(veil, 8)
	local ban = tag(c, "BanTag", "TAP TO BANISH", "Tomato", 16)
	ban.AnchorPoint = Vector2.new(0.5, 0.5)
	ban.Position = UDim2.new(0.5, 0, 0.5, -3)
	ban.ZIndex = 6
	ban.Visible = false
	local again = tag(c, "Confirm", "TAP AGAIN", "Leaf", 15)
	again.AnchorPoint = Vector2.new(0.5, 0.5)
	again.Position = UDim2.new(0.5, 0, 1, -2)
	again.ZIndex = 6
	again.Visible = false
	hit(c)
	return c
end

local function actionButton(parent: Instance, name: string, label: string, colorKey: string, key: string, order: number): Frame
	local b = brick(parent, name, 110, 48, colorKey, { lip = 6, radius = 8, studs = 0.3 })
	b.LayoutOrder = order
	new("UIScale", { Name = "PopScale", Scale = 1 }, b)
	text(b, "Label", label, 19, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -3), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
	local count = tag(b, "Count", "1", "Gold", 15)
	count.AnchorPoint = Vector2.new(1, 0)
	count.Position = UDim2.new(1, 8, 0, -12)
	count.ZIndex = 4
	keycap(b, key)
	hit(b)
	return b
end

local function invSection(parent: Instance, name: string, title: string, cells: number, order: number)
	text(parent, name .. "Title", title, 14, { TextColor3 = tone("Gold"), LayoutOrder = order })
	local grid = new("Frame", { Name = name, Size = UDim2.fromOffset(164, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order + 1 }, parent)
	new("UIGridLayout", {
		CellSize = UDim2.fromOffset(36, 50),
		CellPadding = UDim2.fromOffset(6, 2),
		FillDirectionMaxCells = 4,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)
	for i = 1, cells do
		cell(grid, i).Visible = i <= 4
	end
end

-- Petit chevron vers le haut (deux barres), comme la flèche du boss.
local function chevron(parent: Instance, name: string, colorKey: string): Frame
	local h = new("Frame", { Name = name, Size = UDim2.fromOffset(12, 12), BackgroundTransparency = 1, Visible = false, LayoutOrder = 1 }, parent)
	for i, x in { -3, 3 } do
		local bar = new("Frame", { Size = UDim2.fromOffset(9, 4), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, x, 0.5, 0), Rotation = if i == 1 then -45 else 45, BackgroundColor3 = tone(colorKey), BorderSizePixel = 0 }, h)
		corner(bar, 2)
	end
	return h
end

local STAT_ROWS = {
	{ "Max HP", "100" }, { "Regen", "0.2/s" }, { "Armor", "3" }, { "Damage", "+16%" }, { "Attack Speed", "+7%" }, { "Projectiles", "+1" },
	{ "Area", "+8%" }, { "Cooldown", "-4%" }, { "Crit", "5%" }, { "Luck", "3" }, { "Magnet", "9" }, { "Move Speed", "+4%" },
}

local function buildLevelUp(): (ScreenGui, ScreenGui)
	-- Fond : le jeu pâlit (voile crème) et des rayons tournent derrière la fenêtre. Plein écran,
	-- encoches comprises. La désaturation vient d'Assets.UI.LevelUpFreeze (ColorCorrection).
	local fz = screen("COHUE_Freeze", 19, false, Enum.ScreenInsets.None)
	fz.IgnoreGuiInset = true
	new("Frame", { Name = "Scrim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = LIGHT, BackgroundTransparency = 0.72, BorderSizePixel = 0, ZIndex = 1 }, fz)
	local rays = new("ImageLabel", {
		Name = "Rays",
		Image = IMG.Rays or "",
		ImageColor3 = LIGHT,
		ImageTransparency = 0.8,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.5, 1.5),
		ZIndex = 2,
	}, fz)
	new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width }, rays)

	local gui = screen("COHUE_LevelUp", 20, false)
	local z = zone(gui, "Center", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), Vector2.new(760, 396))

	-- Inventaire (gauche).
	local _, ib = sidePanel(z, "Inventory", "INVENTORY", 0, 38, 180, 304)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 12) }, ib)
	list(ib, false, 1, nil, Enum.VerticalAlignment.Top)
	invSection(ib, "Weapons", "WEAPONS", 6, 1)
	invSection(ib, "Runes", "RUNES", 6, 3)
	invSection(ib, "Items", "ITEMS", 8, 5)

	-- Fenêtre (centre).
	local win = new("Frame", { Name = "Window", Position = UDim2.fromOffset(190, 0), Size = UDim2.fromOffset(380, 372), BackgroundTransparency = 1 }, z)
	new("UIScale", { Name = "PopScale", Scale = 1 }, win)
	windowBody(win, "Body", 0, 26, 380, 346, "Sky")
	local head = brick(win, "Header", 380, 54, "Sky", { lip = 6, radius = 8, studs = 0.4 })
	text(head, "Title", "LEVEL 13!", 30, { Position = UDim2.fromOffset(16, 6), ZIndex = 3 })
	local timer = new("Frame", { Name = "Timer", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 9), Size = UDim2.fromOffset(0, 32), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Visible = false, ZIndex = 3 }, head)
	list(timer, true, 4, Enum.HorizontalAlignment.Right)
	image(timer, "Clock", "timer", 28, { LayoutOrder = 1, ZIndex = 3 })
	text(timer, "Seconds", "12s", 22, { LayoutOrder = 2, ZIndex = 3 })
	local tb = track(win, "TimeBar", 352, 9, "Tomato")
	tb.Position = UDim2.fromOffset(14, 57)
	tb.Visible = false
	local offers = new("Frame", { Name = "Offers", Position = UDim2.fromOffset(18, 72), Size = UDim2.fromOffset(344, 226), BackgroundTransparency = 1 }, win)
	list(offers, false, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)
	for i = 1, 3 do
		offerCard(offers, i)
	end
	local acts = new("Frame", { Name = "Actions", Position = UDim2.fromOffset(14, 310), Size = UDim2.fromOffset(352, 50), BackgroundTransparency = 1 }, win)
	list(acts, true, 10, Enum.HorizontalAlignment.Center)
	actionButton(acts, "Reroll", "REROLL", "Royal", "R", 1)
	actionButton(acts, "Skip", "SKIP", "Stone", "X", 2)
	actionButton(acts, "Banish", "BANISH", "Tomato", "B", 3)
	text(win, "Frozen", "Everyone is frozen while you choose", 15, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 3), TextXAlignment = Enum.TextXAlignment.Center, Visible = false })

	-- Stats (droite).
	local _, sb = sidePanel(z, "Stats", "STATS", 580, 38, 180, 304)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 12) }, sb)
	list(sb, false, 1, nil, Enum.VerticalAlignment.Top)
	for i, row in STAT_ROWS do
		local r = new("Frame", { Name = "Row" .. i, Size = UDim2.fromOffset(164, 20), BackgroundTransparency = 1, LayoutOrder = i }, sb)
		local glow = new("Frame", { Name = "Glow", Position = UDim2.fromOffset(-4, 0), Size = UDim2.new(1, 8, 1, 0), BackgroundColor3 = tone("Leaf"), BorderSizePixel = 0, Visible = false }, r)
		corner(glow, 4)
		ink(glow, 2)
		text(r, "Name", row[1], 15, { Position = UDim2.fromOffset(2, -2), ZIndex = 2 })
		local right = new("Frame", { Name = "Right", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -2, 0, -2), Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, ZIndex = 2 }, r)
		list(right, true, 3, Enum.HorizontalAlignment.Right)
		chevron(right, "Up", "Cream")
		text(right, "Value", row[2], 15, { LayoutOrder = 2, ZIndex = 2 })
	end
	text(sb, "More", "+6 more", 14, { TextColor3 = tone("Cream"), LayoutOrder = 99, Visible = false })

	-- Coop, les autres attendent (L04c) : portrait, « SAM LEVELED UP! », barre du temps.
	local wait = new("Frame", { Name = "Wait", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(380, 172), BackgroundTransparency = 1, Visible = false }, z)
	new("UIScale", { Name = "PopScale", Scale = 1 }, wait)
	local wbody = windowBody(wait, "Body", 20, 50, 352, 118, "Sky")
	local whead = brick(wait, "Header", 352, 50, "Sky", { lip = 6, radius = 8, studs = 0.4 })
	whead.Position = UDim2.fromOffset(20, 12)
	text(whead, "Title", "SAM LEVELED UP!", 24, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 18, 0, 8), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
	local portrait = new("ImageLabel", { Name = "Portrait", Size = UDim2.fromOffset(58, 58), BackgroundColor3 = tone("Cream.d"), BorderSizePixel = 0, Image = "", ScaleType = Enum.ScaleType.Crop, ZIndex = 5 }, wait)
	corner(portrait, 6)
	ink(portrait, 4, tone("Grape")).Name = "Rim"
	text(portrait, "Initial", "", 24, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })
	text(wbody, "Line1", "Sam is picking an upgrade.", 16, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 2 })
	text(wbody, "Line2", "Everyone is frozen. Back in 12s", 16, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 48), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = tone("Gold"), ZIndex = 2 })
	local wbar = track(wbody, "Bar", 288, 14, "Tomato")
	wbar.AnchorPoint = Vector2.new(0.5, 0)
	wbar.Position = UDim2.new(0.5, 0, 0, 80)
	wbar.ZIndex = 2
	return gui, fz
end

---------------------------------------------------------------------------- pièces réutilisées
-- Chaque pièce d'Assets.UI se pose seule : une relance n'ajoute que celles qui manquent.
local KIT: { { name: string, build: (Folder) -> () } } = {
	{
		name = "Button",
		build = function(kit)
			-- Brique de bouton (le code change Label et la couleur avec UIKit.tint).
			local b = brick(kit, "Button", 168, 48, "Leaf", { lip = 6, radius = 8, studs = 0.32 })
			text(b, "Label", "BUTTON", 18, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -3), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
		end,
	},
	{
		name = "Tag",
		build = function(kit)
			tag(kit, "Tag", "NEW!", "Tomato", 15)
		end,
	},
	{
		name = "Slot",
		build = function(kit)
			slot(kit, "Slot", 46, 1)
		end,
	},
	{
		name = "Brick",
		build = function(kit)
			brick(kit, "Brick", 120, 60, "Royal", { lip = 6, radius = 8, studs = 0.3 })
		end,
	},
	{
		name = "Track",
		build = function(kit)
			track(kit, "Track", 180, 18, "Leaf", true)
		end,
	},
	{
		-- Le monde pâlit pendant le choix de niveau : CardUI la clone dans la caméra et l'anime
		-- jusqu'à ses attributs (Saturation -0,7, Brightness 0,06, Contrast -0,12).
		name = "LevelUpFreeze",
		build = function(kit)
			local cc = new("ColorCorrectionEffect", { Name = "LevelUpFreeze", Saturation = 0, Brightness = 0, Contrast = 0 }, kit)
			cc:SetAttribute("Saturation", -0.7)
			cc:SetAttribute("Brightness", 0.06)
			cc:SetAttribute("Contrast", -0.12)
		end,
	},
}

-- Écrans de StarterGui, posés par groupe (un écran et son fond vont ensemble).
local SCREENS: { { names: { string }, build: () -> { ScreenGui } } } = {
	{
		names = { "COHUE_HUD" },
		build = function()
			return { buildHud() }
		end,
	},
	{
		names = { "COHUE_Downed", "COHUE_Vignette" },
		build = function()
			local a, b = buildDowned()
			return { a, b }
		end,
	},
	{
		names = { "COHUE_LevelUp", "COHUE_Freeze" },
		build = function()
			local a, b = buildLevelUp()
			return { a, b }
		end,
	},
}

---------------------------------------------------------------------------- montage
-- Écrans ou pièces à refaire même s'ils existent déjà (« COHUE_HUD », « Kit » pour tout Assets.UI).
local REBUILD: { [string]: boolean } = {}

local made: { string } = {}
local kept: { string } = {}

local assets = ReplicatedStorage:FindFirstChild("Assets") or new("Folder", { Name = "Assets" }, ReplicatedStorage)
local kit = assets:FindFirstChild("UI")
if kit and REBUILD.Kit then
	park(kit)
	kit = nil
end
if not kit then
	kit = new("Folder", { Name = "UI" }, assets)
end
for _, piece in KIT do
	if kit:FindFirstChild(piece.name) then
		table.insert(kept, "Assets.UI." .. piece.name)
	else
		piece.build(kit)
		table.insert(made, "Assets.UI." .. piece.name)
	end
end
task.wait()

for _, group in SCREENS do
	local missingOne = REBUILD[group.names[1]] == true
	for _, n in group.names do
		if not StarterGui:FindFirstChild(n) then
			missingOne = true
		end
	end
	if not missingOne then
		table.insert(kept, table.concat(group.names, " + "))
		continue
	end
	for _, n in group.names do
		park(StarterGui:FindFirstChild(n))
	end
	for _, gui in group.build() do
		gui.Parent = StarterGui
		table.insert(made, gui:GetFullName())
	end
	task.wait()
end

local backupPath: string? = nil
if #backup:GetChildren() > 0 then
	backup.Parent = ServerStorage
	backupPath = backup:GetFullName()
end

local missing = 0
for _, v in IMG.Icons or {} do
	if v == "" then
		missing += 1
	end
end
return {
	made = made,
	kept = kept,
	backup = backupPath,
	imagesMissing = missing,
	studsImage = IMG.Studs ~= "",
	raysImage = (IMG.Rays or "") ~= "",
}
