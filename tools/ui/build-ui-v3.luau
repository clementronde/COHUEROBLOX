-- COHUE — montage des gabarits d'UI v3 « vraies briques » dans la place (A08, 5 nov. 2026).
--
-- Règle de Clément : rien de visible n'est construit par script en jeu. Ce fichier est un outil
-- d'édition, comme A01_finalize.luau : on le lance UNE fois dans Studio (execute_luau, datamodel
-- Edit) sur la place COHUE ; il pose de vrais objets dans StarterGui et ReplicatedStorage.Assets.UI,
-- que Clément voit, modifie et sauvegarde. Les scripts du jeu ne font ensuite que les retrouver par
-- leur nom, changer leurs propriétés et les animer.
--
-- Relançable : les anciens gabarits du même nom partent d'abord dans ServerStorage (sauvegarde).
-- Maquettes : Figma 0Yq5m1skq5dzgOQXZ9bG6D, pages « Components v3 — briques » et « Run v3 — … ».
-- Mesures : pixels logiques du téléphone paysage (844 × 390) ; chaque zone porte un UIScale
-- « Scale » que le code règle selon l'appareil (×1,6 sur PC).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")

-- Images : shared/Config/UIAssets (vide tant que rien n'est téléversé).
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

---------------------------------------------------------------------------- pièces réutilisées
local function buildKit(): Folder
	local kit = new("Folder", { Name = "UI" })
	-- Brique de bouton (le code change Label et la couleur avec UIKit.tint).
	local b = brick(kit, "Button", 168, 48, "Leaf", { lip = 6, radius = 8, studs = 0.32 })
	text(b, "Label", "BUTTON", 18, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -3), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
	tag(kit, "Tag", "NEW!", "Tomato", 15)
	slot(kit, "Slot", 46, 1)
	brick(kit, "Brick", 120, 60, "Royal", { lip = 6, radius = 8, studs = 0.3 })
	track(kit, "Track", 180, 18, "Leaf", true)
	return kit
end

---------------------------------------------------------------------------- montage
local assets = ReplicatedStorage:FindFirstChild("Assets") or new("Folder", { Name = "Assets" }, ReplicatedStorage)
park(assets:FindFirstChild("UI"))
for _, n in { "COHUE_HUD", "COHUE_Downed", "COHUE_Vignette" } do
	park(StarterGui:FindFirstChild(n))
end
backup.Parent = ServerStorage

local made = {}
local kit = buildKit()
kit.Parent = assets
table.insert(made, kit:GetFullName())
task.wait()
local hud = buildHud()
hud.Parent = StarterGui
table.insert(made, hud:GetFullName())
task.wait()
local downed, vig = buildDowned()
downed.Parent = StarterGui
vig.Parent = StarterGui
table.insert(made, downed:GetFullName())
table.insert(made, vig:GetFullName())

local missing = 0
for _, v in IMG.Icons or {} do
	if v == "" then
		missing += 1
	end
end
return {
	made = made,
	backup = backup:GetFullName(),
	imagesMissing = missing,
	studsImage = IMG.Studs ~= "",
}
