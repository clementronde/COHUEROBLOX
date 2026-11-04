--!nocheck
-- A01 — Construction du lobby « Hubbub Village » dans la place COHUE, À L'ÉDITION (barre de commande
-- ou MCP Studio). Ce fichier n'est PAS chargé par le jeu : il pose une fois des objets (Parts,
-- SurfaceGui, ProximityPrompt sans script, mannequins équipés) qui sont ensuite sauvegardés dans la
-- place. Plan : docs/dossier/65-lobby.md (A09, validé par Clément). Style : 80-direction-artistique.md.
-- Chaque section « -- @zone » se lance après l'EN-TÊTE ; relancer une section remplace sa zone.

-- @header ---------------------------------------------------------------------------------------
local ROOT_NAME = "HubbubVillage"
local C = Vector3.new(0, 16, 800) -- centre de la place du village, sol à y = 16 ; nord = -Z
local PAL = {
	Ink = "1C1726", Plum = "4B3866", Bark = "6E4227", Leather = "B5713A", Cream = "FFE8B8", Stone = "9C9488",
	Steel = "8EA6C2", Gold = "FFC21A", Ember = "FF7A1A", Tomato = "E63946", Bubblegum = "FF5FB0", Grape = "8C52E0",
	Royal = "2D6BE6", Sky = "3FD0F5", Leaf = "3DBE4A", Lime = "8FD13F",
}
local LIGHT, SHADOW = Color3.fromHex("FFF4D8"), Color3.fromHex("2A1C3D")
local MIX = { l = { LIGHT, 0.35 }, d = { SHADOW, 0.35 }, dd = { SHADOW, 0.6 } }
local function col(key)
	local name, suf = string.match(key, "^(%a+)%.?(%a*)$")
	local c = Color3.fromHex(PAL[name])
	local m = MIX[suf]
	return if m then c:Lerp(m[1], m[2]) else c
end
local root = workspace:FindFirstChild(ROOT_NAME)
if not root then
	root = Instance.new("Model")
	root.Name = ROOT_NAME
	root.Parent = workspace
end
local function zone(name)
	local z = root:FindFirstChild(name)
	if z then z:Destroy() end
	z = Instance.new("Model")
	z.Name = name
	z.Parent = root
	return z
end
-- Boîte en coordonnées village (studs) : x0..x1, y0..y1 (0 = sol), z0..z1.
local function box(parent, name, x0, x1, y0, y1, z0, z1, key, o)
	o = o or {}
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = if o.neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.Color = col(key)
	p.Size = Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0))
	p.CFrame = CFrame.new(C + Vector3.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
	p.CanCollide = o.collide ~= false
	p.CanQuery = o.query ~= false
	p.CanTouch = false
	p.CastShadow = o.shadow ~= false and not o.neon
	if o.transparency then p.Transparency = o.transparency end
	p.Parent = parent
	return p
end
-- Texte en anglais sur une face (police du lobby : Fredoka One, comme les menus de A09).
local function sign(part, face, text, key)
	local g = Instance.new("SurfaceGui")
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 30
	g.LightInfluence = 0.2
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextScaled = true
	t.Font = Enum.Font.FredokaOne
	t.TextColor3 = col(key or "Ink")
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.06, 0)
	pad.PaddingRight = UDim.new(0.06, 0)
	pad.PaddingTop = UDim.new(0.12, 0)
	pad.PaddingBottom = UDim.new(0.12, 0)
	pad.Parent = t
	t.Parent = g
	g.Parent = part
	return g
end
-- Disque voxel (bandes de `step` studs) : cx, cz, rayon, y0, y1.
local function disc(parent, name, cx, cz, r, y0, y1, keyA, keyB, step)
	step = step or 4
	local i = 0
	for dz = -r, r - step, step do
		local zc = dz + step / 2
		local hw = math.floor(math.sqrt(math.max(0, r * r - zc * zc)) / 2 + 0.5) * 2
		if hw > 0 then
			i += 1
			box(parent, name, cx - hw, cx + hw, y0, y1, cz + dz, cz + dz + step, if i % 2 == 0 then keyB else keyA)
		end
	end
end
-- Invite sans script (A09 branchera LobbyService dessus).
local function prompt(parent, name, action, object, dist)
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = action
	p.ObjectText = object or ""
	p.MaxActivationDistance = dist or 7
	p.HoldDuration = 0
	p.RequiresLineOfSight = false
	p.Parent = parent
	return p
end
-- Mannequin R15 figé (pas de script), couleur unie, regard vers `faceDir` (vecteur x, z).
local Players = game:GetService("Players")
local function mannequin(parent, name, x, y, z, faceDir, key)
	local d = Instance.new("HumanoidDescription")
	for _, k in { "HeadColor", "TorsoColor", "LeftArmColor", "RightArmColor", "LeftLegColor", "RightLegColor" } do
		d[k] = col(key)
	end
	local r = Players:CreateHumanoidModelFromDescription(d, Enum.HumanoidRigType.R15)
	r.Name = name
	for _, s in r:GetDescendants() do
		if s:IsA("LuaSourceContainer") then s:Destroy() end
	end
	local pos = C + Vector3.new(x, y + 3.19, z)
	r:PivotTo(CFrame.lookAt(pos, pos + Vector3.new(faceDir.X, 0, faceDir.Y)))
	for _, b in r:GetDescendants() do
		if b:IsA("BasePart") then b.Anchored = true end
	end
	r.Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	r.Parent = parent
	return r
end
local Assets = game:GetService("ReplicatedStorage"):WaitForChild("Assets")
-- Habille un mannequin figé : chaque poignée est posée par calcul (attache du corps x inverse de
-- l'attache de la poignée). AddAccessory ne suffit pas à l'édition : dans COHUE il crée une
-- RigidConstraint que la physique ne résout pas hors jeu, et la pièce reste où elle était.
local function wear(rig, pieces)
	for _, n in pieces do
		local tpl = Assets.Equipment:FindFirstChild(n)
		if tpl then
			local acc = tpl:Clone()
			local h = acc.Handle
			local att = h:FindFirstChildOfClass("Attachment")
			local body = rig:FindFirstChild(att.Name, true)
			h.CFrame = body.WorldCFrame * att.CFrame:Inverse()
			h.Anchored = true
			for _, c in h:GetChildren() do
				if c:IsA("BasePart") then
					local w = c:FindFirstChildOfClass("Weld")
					if w then c.CFrame = h.CFrame * w.C0 end
					c.Anchored = true
				end
			end
			acc.Parent = rig
		end
	end
end
-- Allège un mannequin figé : de 236 à environ 30 objets (pas de physique, pas d'animation).
local STRIP = { AnimationConstraint = true, BallSocketConstraint = true, NoCollisionConstraint = true, Vector3Value = true,
	NumberValue = true, WrapTarget = true, BodyPartDescription = true, HumanoidDescription = true, Animator = true,
	BodyColors = true, Status = true, RigidConstraint = true, Attachment = true, Motor6D = true }
local function strip(rig)
	for _, d in rig:GetDescendants() do
		if STRIP[d.ClassName] and d.Parent then d:Destroy() end
	end
	for _, b in rig:GetDescendants() do
		if b:IsA("BasePart") then
			b.Anchored = true
			b.CanTouch = false
			b.CanQuery = b.Name == "UpperTorso"
		end
	end
end
-- @end header

-- @zone Ground : plateau à coupe de terrain visible (signature diorama), chemins, place, arrivée ----
do
	local g = zone("Ground")
	-- Plateau 244 x 232 studs, 8 studs d'épaisseur : herbe, terre, argile, roche (tons calmes du décor)
	box(g, "Grass", -122, 122, -1, 0, -116, 116, "Leaf.dd")
	box(g, "Soil", -122, 122, -2, -1, -116, 116, "Bark")
	box(g, "Clay", -122, 122, -5, -2, -116, 116, "Leather.d")
	box(g, "Rock", -122, 122, -8, -5, -116, 116, "Stone.d")
	-- Grandes plaques d'herbe au ton de base (pas de mouchetis)
	box(g, "GrassPatch", -120, -96, 0, 0.05, 40, 76, "Leaf.d", { shadow = false })
	box(g, "GrassPatch", 96, 120, 0, 0.05, 30, 70, "Leaf.d", { shadow = false })
	-- Avenue (24 studs) de l'arrivée au portail
	box(g, "Avenue", -12, 12, 0, 0.1, -38, 92, "Leather.d", { shadow = false })
	-- Chemins secondaires (16 studs)
	box(g, "PathPen", -56, -40, 0, 0.1, -2, 14, "Leather.d", { shadow = false })
	box(g, "PathShop", 40, 58, 0, 0.1, -4, 12, "Leather.d", { shadow = false })
	box(g, "PathHall", -46, -30, 0, 0.1, -40, -22, "Leather.d", { shadow = false })
	box(g, "PathQuests", 30, 46, 0, 0.1, -40, -22, "Leather.d", { shadow = false })
	-- Place centrale (rayon 40), mosaïque en bandes larges, flèche violette vers le portail
	disc(g, "Plaza", 0, 0, 40, 0, 0.15, "Stone.l", "Cream.d", 4)
	box(g, "PlazaArrow", -3, 3, 0.15, 0.25, -6, 22, "Grape.d", { shadow = false })
	box(g, "PlazaArrow", -9, 9, 0.15, 0.25, -12, -6, "Grape.d", { shadow = false })
	box(g, "PlazaArrow", -5, 5, 0.15, 0.25, -18, -12, "Grape.d", { shadow = false })
	box(g, "PlazaArrow", -1, 1, 0.15, 0.25, -22, -18, "Grape.d", { shadow = false })
	-- Arrivée : pad de 32 x 18, face au portail
	local pad = box(g, "ArrivalPad", -16, 16, 0, 0.3, 92, 110, "Cream.d")
	pad:SetAttribute("LobbyRole", "Arrival")
	box(g, "ArrivalRim", -17, 17, 0, 0.2, 91, 111, "Stone")
	-- Porte du village derrière l'arrivée (on « revient » d'une run par là)
	box(g, "GatePost", -18, -14, 0, 14, 112, 116, "Bark")
	box(g, "GatePost", 14, 18, 0, 14, 112, 116, "Bark")
	local lintel = box(g, "GateLintel", -19, 19, 14, 18, 112, 116, "Leather")
	sign(lintel, Enum.NormalId.Front, "HUBBUB VILLAGE", "Cream")
	sign(lintel, Enum.NormalId.Back, "HUBBUB VILLAGE", "Cream")
	box(g, "GateRoof", -20, 20, 18, 19, 111, 117, "Tomato.d")
	-- Panneau unique de l'arrivée
	box(g, "SignPost", 13, 14, 0, 7, 88, 89, "Bark")
	local s = box(g, "SignPortal", 9, 18, 5, 8, 88.6, 89, "Cream")
	sign(s, Enum.NormalId.Back, "PORTAL  ▲", "Grape.d")
end
-- @end zone

-- @zone HeroRow : 8 présentoirs de classes (3 gratuites équipées au palier 3, 5 verrouillées) --------
do
	local h = zone("HeroRow")
	local CLASSES = {
		{ id = "Knight", side = -1, z = 84, key = "Royal", weapon = "Broadsword", gear = { "Knight_Helm", "Knight_Pauldron_R", "Knight_Pauldron_L", "Knight_Cape" } },
		{ id = "Archer", side = 1, z = 84, key = "Leaf", weapon = "Longbow", gear = { "Archer_Hood", "Archer_Bracer", "Archer_Quiver" } },
		{ id = "Mage", side = -1, z = 70, key = "Grape", weapon = "Fire Staff", gear = { "Mage_Hat", "Mage_Orb", "Mage_Cape" } },
		{ id = "Guardian", side = 1, z = 70, key = "Stone", weapon = "Quake Hammer" },
		{ id = "Rogue", side = -1, z = 56, key = "Plum", weapon = "Throwing Daggers" },
		{ id = "Cleric", side = 1, z = 56, key = "Cream", weapon = "Holy Aura" },
		{ id = "Barbarian", side = -1, z = 42, key = "Tomato", weapon = "Spinning Axes" },
		{ id = "Tamer", side = 1, z = 42, key = "Leather", weapon = "Beast Whip" },
	}
	for _, c in CLASSES do
		local m = Instance.new("Model")
		m.Name = "Stand_" .. c.id
		m:SetAttribute("ClassId", c.id)
		m:SetAttribute("Locked", c.gear == nil)
		m.Parent = h
		local x, z, s = 24 * c.side, c.z, c.side
		box(m, "Socle", x - 4, x + 4, 0, 2, z - 4, z + 4, "Stone")
		box(m, "SocleTop", x - 3.5, x + 3.5, 2, 2.2, z - 3.5, z + 3.5, c.key .. ".d")
		-- Bannière de 12 studs à la couleur de la classe, côté extérieur, tournée vers l'avenue
		box(m, "BannerPole", x + 4.5 * s - 0.5, x + 4.5 * s + 0.5, 0, 14, z - 4.5, z - 3.5, "Bark")
		box(m, "BannerPole", x + 4.5 * s - 0.5, x + 4.5 * s + 0.5, 0, 14, z + 3.5, z + 4.5, "Bark")
		box(m, "BannerBar", x + 4.5 * s - 0.5, x + 4.5 * s + 0.5, 13, 14, z - 4.5, z + 4.5, "Bark")
		box(m, "Banner", x + 4.5 * s - 0.2, x + 4.5 * s + 0.2, 2, 13, z - 3.5, z + 3.5, c.key, { shadow = false })
		box(m, "BannerTip", x + 4.5 * s - 0.2, x + 4.5 * s + 0.2, 1, 2, z - 1, z + 1, c.key, { shadow = false })
		box(m, "BannerEmblem", x + 4.5 * s - 0.3 * s - 0.15, x + 4.5 * s - 0.3 * s + 0.15, 8, 11, z - 1.5, z + 1.5, if c.gear then "Cream" else "Stone.d", { shadow = false })
		-- Plaque sur la face du socle tournée vers l'avenue
		local px = x - 4 * s
		local plaque = box(m, "Plaque", px - 0.15, px + 0.15, 0.3, 1.8, z - 3.5, z + 3.5, "Cream")
		sign(plaque, if s < 0 then Enum.NormalId.Right else Enum.NormalId.Left,
			if c.gear then (c.id .. " · " .. c.weapon) else (c.id .. " · Quest to unlock"), "Ink")
		-- Mannequin tourné vers l'avenue
		local rig = mannequin(m, "Mannequin", x, 2.2, z, Vector2.new(-s, 0), if c.gear then "Stone.l" else "Stone.d")
		if c.gear then
			wear(rig, c.gear)
			strip(rig)
		else
			strip(rig)
			-- Cadenas voxel devant la poitrine
			local lx = x - 1.6 * s
			box(m, "Lock", lx - 0.3, lx + 0.3, 4.6, 6.0, z - 0.8, z + 0.8, "Gold.d")
			box(m, "LockShackle", lx - 0.2, lx + 0.2, 6.0, 6.8, z - 0.7, z - 0.4, "Steel")
			box(m, "LockShackle", lx - 0.2, lx + 0.2, 6.0, 6.8, z + 0.4, z + 0.7, "Steel")
			box(m, "LockShackle", lx - 0.2, lx + 0.2, 6.6, 7.0, z - 0.7, z + 0.7, "Steel")
			box(m, "LockHole", lx - 0.35 * s - 0.05, lx - 0.35 * s + 0.05, 5.0, 5.5, z - 0.15, z + 0.15, "Ink")
		end
		prompt(rig:FindFirstChild("UpperTorso"), "ClassPrompt", if c.gear then "Try on" else "See quest", c.id, 7)
	end
	-- Repère flottant de Hero Row : une épée voxel de 8 studs, tournée vers l'arrivée
	box(h, "IconSwordBlade", -0.6, 0.6, 18, 24, 63, 63.6, "Steel.l", { collide = false, query = false })
	box(h, "IconSwordTip", -0.3, 0.3, 24, 25, 63, 63.6, "Steel.l", { collide = false, query = false })
	box(h, "IconSwordGuard", -2.4, 2.4, 17.2, 18, 62.9, 63.7, "Royal", { collide = false, query = false })
	box(h, "IconSwordGrip", -0.4, 0.4, 15.4, 17.2, 63, 63.6, "Leather", { collide = false, query = false })
	box(h, "IconSwordPommel", -0.7, 0.7, 14.6, 15.4, 62.9, 63.7, "Gold", { collide = false, query = false })
end
-- @end zone

-- @zone PortalCourt : arche de 44 studs, tourbillon, pads Solo / Friends / Public, portier, bancs ------
do
	local p = zone("PortalCourt")
	box(p, "CourtFloor", -42, 42, 0, 0.2, -66, -36, "Stone.l", { shadow = false })
	box(p, "Dais", -30, 30, 0, 1, -66, -52, "Stone")
	box(p, "Pillar", -24, -16, 1, 44, -62, -54, "Stone")
	box(p, "Pillar", 16, 24, 1, 44, -62, -54, "Stone")
	box(p, "Lintel", -24, 24, 36, 44, -62, -54, "Stone")
	box(p, "ArchStep", -16, -12, 32, 36, -61, -55, "Stone.d")
	box(p, "ArchStep", 12, 16, 32, 36, -61, -55, "Stone.d")
	box(p, "ArchStep", -12, -8, 34, 36, -61, -55, "Stone.d")
	box(p, "ArchStep", 8, 12, 34, 36, -61, -55, "Stone.d")
	for _, y in { 9, 19, 29 } do
		box(p, "Band", -24.4, -15.6, y, y + 1.2, -62.4, -53.6, "Grape")
		box(p, "Band", 15.6, 24.4, y, y + 1.2, -62.4, -53.6, "Grape")
	end
	box(p, "LintelBand", -24.4, 24.4, 41, 42.2, -62.4, -53.6, "Grape")
	box(p, "Crown", -6, 6, 44, 47, -61, -55, "Grape.l")
	box(p, "CrownTop", -2, 2, 47, 50, -60, -56, "Grape")
	box(p, "Finial", -1, 1, 50, 52, -59, -57, "Gold")
	box(p, "PillarFoot", -25, -15, 1, 3, -63, -53, "Stone.d")
	box(p, "PillarFoot", 15, 25, 1, 3, -63, -53, "Stone.d")
	-- Violet bleuté (Grape.d / Royal.d) : sous le bloom, Grape pur vire au rose, réservé à la capture
	local swirl = box(p, "PortalSwirl", -16, 16, 1, 32, -58.3, -57.7, "Grape.d", { neon = true, collide = false, transparency = 0.25 })
	swirl:SetAttribute("LobbyRole", "PortalSwirl")
	box(p, "PortalCore", -9, 9, 8, 26, -58.6, -58.4, "Royal.d", { neon = true, collide = false, transparency = 0.1 })
	local PADS = { { "Solo", -26, 12, "SOLO" }, { "Friends", 0, 16, "FRIENDS" }, { "Public", 26, 16, "PUBLIC · 1-4" } }
	for _, d in PADS do
		local mode, x, dia, label = d[1], d[2], d[3], d[4]
		local m = Instance.new("Model")
		m.Name = "Pad_" .. mode
		m:SetAttribute("LobbyRole", "Pad")
		m:SetAttribute("Mode", mode)
		m.Parent = p
		local r, z = dia / 2, -42
		box(m, "Base", x - r, x + r, 0, 0.5, z - r + 2, z + r - 2, "Grape.d")
		box(m, "Base", x - r + 2, x + r - 2, 0, 0.5, z - r, z + r, "Grape.d")
		box(m, "Ring", x - r + 1.5, x + r - 1.5, 0.5, 0.6, z - r + 3, z + r - 3, "Grape.l", { shadow = false })
		box(m, "Ring", x - r + 3, x + r - 3, 0.5, 0.6, z - r + 1.5, z + r - 1.5, "Grape.l", { shadow = false })
		box(m, "Center", x - r + 3, x + r - 3, 0.6, 0.65, z - r + 3, z + r - 3, "Grape.d", { shadow = false })
		-- Boîte interrogée par le serveur (GetPartBoundsInBox, jamais Touched : 65-lobby.md §3.4)
		local zoneBox = box(m, "Zone", x - r, x + r, 0.5, 6.5, z - r, z + r, "Grape", { collide = false, query = false, transparency = 1, shadow = false })
		zoneBox:SetAttribute("LobbyRole", "PadZone")
		box(m, "SignPost", x - 0.5, x + 0.5, 0, 10, z - r - 2, z - r - 1, "Bark")
		local b = box(m, "Sign", x - 4.5, x + 4.5, 7, 10, z - r - 1, z - r - 0.6, "Cream")
		sign(b, Enum.NormalId.Back, label, "Grape.d")
	end
	-- Portier : un gobelin qui fait signe de passer (gardien prévu : Gland Grincheux, pas encore en voxel)
	local gob = Assets.Creatures.Enemy_GoblinGrunt:Clone()
	gob.Name = "Doorman"
	gob.CFrame = CFrame.new(C + Vector3.new(31, 1 + gob.Size.Y / 2, -50))
	gob.Parent = p
	box(p, "FlagPole", 33.5, 34, 1, 8, -50.25, -49.75, "Bark")
	box(p, "Flag", 34, 37, 5.5, 7.8, -50.15, -49.85, "Grape", { shadow = false })
	-- Bancs de la place, hors de l'axe arrivée -> portail
	local g = root:FindFirstChild("Ground")
	for _, bb in { { -34, -12 }, { -34, 8 }, { 34, -12 }, { 34, 8 } } do
		local bx, bz = bb[1], bb[2]
		box(g, "BenchSeat", bx - 1.2, bx + 1.2, 1.4, 1.9, bz - 3.5, bz + 3.5, "Bark")
		box(g, "BenchBack", bx + (if bx < 0 then -1.2 else 0.8), bx + (if bx < 0 then -0.8 else 1.2), 1.9, 3.4, bz - 3.5, bz + 3.5, "Leather")
		box(g, "BenchLeg", bx - 1, bx + 1, 0, 1.4, bz - 3, bz - 2.4, "Bark.d")
		box(g, "BenchLeg", bx - 1, bx + 1, 0, 1.4, bz + 2.4, bz + 3, "Bark.d")
	end
end
-- @end zone

-- @zone CritterPen + GlamShop -------------------------------------------------------------------------
do
	-- Critter Pen (-84, 6), 56 x 48, porte à l'est
	local pen = zone("CritterPen")
	pen:SetAttribute("LobbyRole", "CritterPen")
	box(pen, "Meadow", -112, -56, 0, 0.05, -18, 30, "Leaf.d", { shadow = false })
	local function post(x, z) box(pen, "FencePost", x - 0.5, x + 0.5, 0, 3.2, z - 0.5, z + 0.5, "Bark") end
	local function railX(x0, x1, z) for _, y in { 1.2, 2.4 } do box(pen, "FenceRail", x0, x1, y, y + 0.4, z - 0.2, z + 0.2, "Leather") end end
	local function railZ(z0, z1, x) for _, y in { 1.2, 2.4 } do box(pen, "FenceRail", x - 0.2, x + 0.2, y, y + 0.4, z0, z1, "Leather") end end
	for x = -112, -56, 8 do post(x, -18); post(x, 30) end
	for z = -10, 22, 8 do post(-112, z) end
	for _, z in { -10, -2, 14, 22 } do post(-56, z) end
	railX(-112, -56, -18); railX(-112, -56, 30); railZ(-18, 30, -112)
	railZ(-18, -2, -56); railZ(14, 30, -56)
	box(pen, "KioskFloor", -63, -57, 0, 0.3, 16, 24, "Cream.d")
	box(pen, "KioskPost", -63, -62, 0, 7, 16, 17, "Bark"); box(pen, "KioskPost", -58, -57, 0, 7, 16, 17, "Bark")
	box(pen, "KioskPost", -63, -62, 0, 7, 23, 24, "Bark"); box(pen, "KioskPost", -58, -57, 0, 7, 23, 24, "Bark")
	box(pen, "KioskRoof", -64, -56, 7, 8, 15, 25, "Leaf")
	box(pen, "KioskRoof", -63, -57, 8, 9, 16, 24, "Leaf.l")
	local counter = box(pen, "KioskCounter", -58, -56.6, 0, 3.4, 17, 23, "Leather")
	prompt(counter, "CrittersPrompt", "Critters", "Collection", 7)
	local s = box(pen, "SignNoFeed", -55.4, -55, 1.6, 5.2, -16, -6, "Cream")
	sign(s, Enum.NormalId.Right, "Do not feed the critters. They bite.", "Leaf.dd")
	box(pen, "SignPost", -55.6, -54.8, 0, 1.6, -11.4, -10.6, "Bark")
	box(pen, "Trough", -100, -94, 0, 1.2, 20, 23, "Bark"); box(pen, "Water", -99.5, -94.5, 1.2, 1.25, 20.5, 22.5, "Sky.d", { shadow = false })
	box(pen, "Hay", -106, -102, 0, 2.5, -12, -8, "Gold.d"); box(pen, "Hay", -105, -103, 2.5, 3.2, -11, -9, "Gold")
	box(pen, "IconPawPad", -86.5, -81.5, 18, 22, 5.5, 6.5, "Leaf.l", { collide = false, query = false })
	for _, t in { { -88, 22.5 }, { -85.5, 24 }, { -82.5, 24 }, { -80, 22.5 } } do
		box(pen, "IconPawToe", t[1] - 0.9, t[1] + 0.9, t[2], t[2] + 1.8, 5.5, 6.5, "Leaf.l", { collide = false, query = false })
	end
	box(pen, "IconPawCore", -85.5, -82.5, 18.6, 21, 5.3, 5.5, "Leaf.dd", { collide = false, query = false })
	-- Gob's Glam Shop (77, 4), 38 x 36, entrée à l'ouest
	local shop = zone("GlamShop")
	box(shop, "Floor", 58, 96, 0, 0.2, -14, 22, "Cream.d")
	box(shop, "WallN", 58, 96, 0, 14, -14, -12, "Cream")
	box(shop, "WallS", 58, 96, 0, 14, 20, 22, "Cream")
	box(shop, "WallE", 94, 96, 0, 14, -12, 20, "Cream")
	box(shop, "WallW", 58, 60, 0, 3, -12, -4, "Cream")
	box(shop, "WallW", 58, 60, 10, 14, -12, -4, "Cream")
	box(shop, "WallW", 58, 60, 0, 14, -4, 0, "Cream")
	box(shop, "WallW", 58, 60, 9, 14, 0, 8, "Cream")
	box(shop, "WallW", 58, 60, 0, 14, 8, 20, "Cream")
	for _, c in { { 57.5, -14.5 }, { 57.5, 21.5 }, { 95.5, -14.5 }, { 95.5, 21.5 } } do
		box(shop, "Corner", c[1] - 1, c[1] + 1, 0, 14, c[2] - 1, c[2] + 1, "Leather")
	end
	box(shop, "Window", 58.6, 59.4, 3, 10, -12, -4, "Sky.l", { transparency = 0.6, shadow = false })
	box(shop, "Roof", 56, 98, 14, 16, -16, 24, "Ember.d")
	box(shop, "Roof", 60, 94, 16, 18, -12, 20, "Ember")
	box(shop, "Roof", 66, 88, 18, 20, -6, 14, "Ember.l")
	local plate = box(shop, "ShopSign", 57.4, 58, 10, 13, -2, 10, "Ember")
	sign(plate, Enum.NormalId.Left, "Gob's Glam Shop", "Cream")
	local quip = box(shop, "QuipSign", 57.4, 57.8, 1, 3, 9, 15, "Cream")
	sign(quip, Enum.NormalId.Left, "I used to steal XP. Now I sell hats.", "Ember.d")
	box(shop, "Counter", 72, 76, 0, 3.4, 0, 10, "Leather")
	local top = box(shop, "CounterTop", 71.6, 76.4, 3.4, 3.8, -0.4, 10.4, "Cream")
	prompt(top, "ShopPrompt", "Shop", "Gob's Glam Shop", 8)
	local gob = Assets.Creatures.Enemy_GoblinBomber:Clone()
	gob.Name = "Gob"
	gob.CFrame = CFrame.lookAt(C + Vector3.new(80, 0.2 + gob.Size.Y / 2, 5), C + Vector3.new(60, 0.2 + gob.Size.Y / 2, 5))
	gob.Parent = shop
	for i, piece in { "Knight_Helm", "Mage_Hat", "Archer_Hood" } do
		local rig = mannequin(shop, "Showcase" .. i, 62, 0.2, -12 + i * 2.6 - 0.6, Vector2.new(-1, 0), "Cream.d")
		wear(rig, { piece })
		strip(rig)
	end
	box(shop, "IconHatBrim", 74, 80, 22, 22.8, 1, 7, "Ink", { collide = false, query = false })
	box(shop, "IconHatCrown", 75, 79, 22.8, 27.5, 2, 6, "Ink", { collide = false, query = false })
	box(shop, "IconHatBand", 74.9, 79.1, 23.2, 24.2, 1.9, 6.1, "Ember", { collide = false, query = false })
end
-- @end zone

-- @zone HallOfFame + QuestBoard -------------------------------------------------------------------------
do
	local NOQ = { collide = false, query = false }
	-- Tableau avec SurfaceGui « BoardGui » : Title, Subtitle, et un cadre vide (Rows / Notes) rempli par A09
	local function boardGui(part, title, subtitle, titleKey)
		local g = Instance.new("SurfaceGui")
		g.Name = "BoardGui"
		g.Face = Enum.NormalId.Back
		g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		g.PixelsPerStud = 30
		g.LightInfluence = 0.2
		local t = Instance.new("TextLabel")
		t.Name = "Title"; t.BackgroundTransparency = 1; t.Size = UDim2.fromScale(1, 0.16); t.Position = UDim2.fromScale(0, 0.03)
		t.Font = Enum.Font.FredokaOne; t.TextScaled = true; t.Text = title; t.TextColor3 = col(titleKey); t.Parent = g
		local y = 0.2
		if subtitle then
			local st = Instance.new("TextLabel")
			st.Name = "Subtitle"; st.BackgroundTransparency = 1; st.Size = UDim2.fromScale(1, 0.07); st.Position = UDim2.fromScale(0, 0.19)
			st.Font = Enum.Font.Nunito; st.TextScaled = true; st.Text = subtitle; st.TextColor3 = col("Cream.d"); st.Parent = g
			y = 0.28
		end
		local rows = Instance.new("Frame")
		rows.Name = "Rows"; rows.BackgroundTransparency = 1
		rows.Size = UDim2.fromScale(0.9, 0.95 - y); rows.Position = UDim2.fromScale(0.05, y); rows.Parent = g
		g.Parent = part
		return g
	end
	-- Hall of Fame (-73, -52)
	local hall = zone("HallOfFame")
	box(hall, "Floor", -100, -46, 0, 0.15, -76, -28, "Stone.l", { shadow = false })
	for _, b in { { "BoardWeekly", -96, -78, "WEEKLY KO", "Resets Monday 00:00 UTC" }, { "BoardAllTime", -72, -54, "ALL-TIME KO" } } do
		local m = Instance.new("Model")
		m.Name = b[1]
		m:SetAttribute("LobbyRole", "Leaderboard")
		m.Parent = hall
		local x0, x1 = b[2], b[3]
		box(m, "Post", x0, x0 + 1, 0, 16, -75, -74, "Bark"); box(m, "Post", x1 - 1, x1, 0, 16, -75, -74, "Bark")
		box(m, "Frame", x0, x1, 2, 16, -74.4, -73.6, "Gold.d")
		local panel = box(m, "Panel", x0 + 0.8, x1 - 0.8, 2.8, 15.2, -73.7, -73.3, "Plum.dd")
		boardGui(panel, b[4], b[5], "Gold.l")
		box(m, "Cap", x0 - 0.6, x1 + 0.6, 16, 17, -75, -73, "Gold")
	end
	for _, s in { { 1, -89, -85, 4.5, "Gold" }, { 2, -93, -89, 3.2, "Steel.l" }, { 3, -85, -81, 2.2, "Leather" } } do
		local step = box(hall, "Podium" .. s[1], s[2], s[3], 0, s[4], -64, -60, s[5])
		sign(step, Enum.NormalId.Back, tostring(s[1]), "Ink")
		local slot = box(hall, "StatueSlot" .. s[1], (s[2] + s[3]) / 2 - 0.5, (s[2] + s[3]) / 2 + 0.5, s[4], s[4] + 1, -62.5, -61.5, "Gold",
			{ collide = false, query = false, transparency = 1, shadow = false })
		slot:SetAttribute("LobbyRole", "StatueSlot")
	end
	box(hall, "Podium4", -75, -71, 0, 2, -64, -60, "Stone")
	local plaque = box(hall, "Plaque4", -75, -71, 0.2, 1.8, -59.9, -59.6, "Cream")
	sign(plaque, Enum.NormalId.Back, "Your statue here?", "Plum.d")
	local lectern = box(hall, "Lectern", -51, -49, 0, 3.6, -35, -33, "Gold.d")
	prompt(lectern, "LeaderboardsPrompt", "Leaderboards", "Hall of Fame", 7)
	box(hall, "IconTrophyBase", -75, -71, 18, 19, -54, -50, "Gold.d", NOQ)
	box(hall, "IconTrophyStem", -73.6, -72.4, 19, 21, -52.6, -51.4, "Gold", NOQ)
	box(hall, "IconTrophyCup", -75.5, -70.5, 21, 25, -54.5, -49.5, "Gold", NOQ)
	box(hall, "IconTrophyHandle", -77, -75.5, 22, 24, -52.5, -51.5, "Gold.d", NOQ)
	box(hall, "IconTrophyHandle", -70.5, -69, 22, 24, -52.5, -51.5, "Gold.d", NOQ)
	box(hall, "IconTrophyStar", -73.6, -72.4, 22.4, 23.6, -49.6, -49.4, "Cream", NOQ)
	-- Quest Board (73, -52)
	local q = zone("QuestBoard")
	box(q, "Floor", 46, 100, 0, 0.15, -76, -28, "Stone.l", { shadow = false })
	local qb = Instance.new("Model")
	qb.Name = "Board"
	qb:SetAttribute("LobbyRole", "QuestBoard")
	qb.Parent = q
	box(qb, "Post", 63, 64, 0, 16, -75, -74, "Bark"); box(qb, "Post", 82, 83, 0, 16, -75, -74, "Bark")
	box(qb, "Frame", 63, 83, 2, 14, -74.4, -73.6, "Sky.d")
	local cork = box(qb, "Cork", 63.8, 82.2, 2.8, 13.2, -73.7, -73.3, "Leather.l")
	local g = boardGui(cork, "QUESTS", nil, "Sky.dd")
	g.Rows.Name = "Notes"
	local header = box(qb, "Header", 66, 80, 14, 16.4, -74.6, -73.4, "Sky")
	sign(header, Enum.NormalId.Back, "QUEST BOARD", "Cream")
	box(qb, "Canopy", 61, 85, 16.4, 17.2, -76, -71.5, "Sky.d")
	for i, n in { { 66, 10 }, { 70.5, 9.5 }, { 75, 10.2 }, { 79, 9.6 }, { 67, 5.5 }, { 72, 6 }, { 77.5, 5.2 } } do
		box(qb, "Note", n[1] - 1.1, n[1] + 1.1, n[2] - 1.5, n[2] + 1.5, -73.3, -73.1, "Cream", { shadow = false })
		box(qb, "Pin", n[1] - 0.2, n[1] + 0.2, n[2] + 1.1, n[2] + 1.5, -73.1, -72.9, if i % 2 == 0 then "Tomato" else "Royal", { shadow = false })
	end
	box(qb, "OwlBody", 71.5, 74.5, 17.2, 20.6, -75, -72.4, "Plum")
	box(qb, "OwlBelly", 72, 74, 17.6, 19.6, -72.5, -72.2, "Cream.d")
	box(qb, "OwlEye", 71.9, 72.9, 19.6, 20.4, -72.5, -72.2, "Cream"); box(qb, "OwlEye", 73.1, 74.1, 19.6, 20.4, -72.5, -72.2, "Cream")
	box(qb, "OwlPupil", 72.2, 72.6, 19.8, 20.2, -72.25, -72.1, "Ink"); box(qb, "OwlPupil", 73.4, 73.8, 19.8, 20.2, -72.25, -72.1, "Ink")
	box(qb, "OwlBeak", 72.7, 73.3, 19.0, 19.6, -72.4, -71.9, "Ember")
	box(qb, "OwlTuft", 71.5, 72.3, 20.6, 21.4, -74, -73, "Plum.d"); box(qb, "OwlTuft", 73.7, 74.5, 20.6, 21.4, -74, -73, "Plum.d")
	box(qb, "OwlBag", 74.5, 75.4, 17.4, 18.8, -74.2, -72.8, "Leather")
	local ql = box(q, "Lectern", 49, 51, 0, 3.6, -35, -33, "Sky.d")
	prompt(ql, "QuestsPrompt", "Quests", "Quest Board", 7)
	box(q, "IconScroll", 70.5, 75.5, 19, 26, -52.4, -51.6, "Cream", NOQ)
	box(q, "IconScrollRoll", 70, 76, 25.6, 26.8, -52.8, -51.2, "Leather.l", NOQ)
	box(q, "IconScrollRoll", 70, 76, 18.2, 19.4, -52.8, -51.2, "Leather.l", NOQ)
	box(q, "IconBang", 72.5, 73.5, 21.8, 25, -51.6, -51.4, "Sky.d", NOQ)
	box(q, "IconBangDot", 72.5, 73.5, 20.2, 21.2, -51.6, -51.4, "Sky.d", NOQ)
end
-- @end zone

-- @zone Edge : ceinture d'arbres, falaises étagées au nord, deux maisonnettes ---------------------------
do
	local e = zone("Edge")
	local rng = Random.new(11)
	local function tree(x, z, big)
		local t = if big then 7 else 5
		local m = Instance.new("Model")
		m.Name = "Tree"
		m.Parent = e
		box(m, "Trunk", x - 1, x + 1, 0, t, z - 1, z + 1, "Bark")
		local w = if big then 5 else 4
		box(m, "Canopy", x - w, x + w, t, t + 5, z - w, z + w, "Leaf.d", { collide = false })
		box(m, "CanopyTop", x - w + 1.5, x + w - 1.5, t + 5, t + 7.5, z - w + 1.5, z + w - 1.5, "Leaf", { collide = false })
		box(m, "CanopyUnder", x - w + 1, x + w - 1, t - 1, t, z - w + 1, z + w - 1, "Leaf.dd", { collide = false, shadow = false })
	end
	for z = -84, 108, 12 do
		tree(-116 + rng:NextInteger(-1, 1), z, rng:NextNumber() < 0.5)
		tree(116 + rng:NextInteger(-1, 1), z, rng:NextNumber() < 0.5)
	end
	for x = -104, 104, 13 do
		if math.abs(x) > 26 then tree(x, 110 + rng:NextInteger(-1, 1), rng:NextNumber() < 0.5) end
	end
	for _, pt in { { -36, 86 }, { 38, 74 }, { -38, 52 }, { 40, 34 }, { -60, 60 }, { 62, 52 } } do tree(pt[1], pt[2], true) end
	local function cliff(x0, x1, z0, z1, h)
		box(e, "Cliff", x0, x1, 0, h - 1, z0, z1, "Stone.d")
		box(e, "CliffTop", x0, x1, h - 1, h, z0, z1, "Leaf.dd")
		box(e, "CliffBand", x0 - 0.1, x1 + 0.1, math.floor(h / 2), math.floor(h / 2) + 1, z0 - 0.1, z1 + 0.1, "Stone", { shadow = false })
	end
	cliff(-122, -60, -116, -92, 16)
	cliff(-60, -32, -116, -100, 10)
	cliff(-32, 32, -116, -104, 6)
	cliff(32, 60, -116, -100, 10)
	cliff(60, 122, -116, -92, 18)
	cliff(-122, -104, -92, -80, 8)
	cliff(104, 122, -92, -80, 9)
	local function house(x, z, faceSign)
		local m = Instance.new("Model")
		m.Name = "Cottage"
		m.Parent = e
		box(m, "Walls", x - 7, x + 7, 0, 8, z - 6, z + 6, "Cream")
		box(m, "Base", x - 7.5, x + 7.5, 0, 1, z - 6.5, z + 6.5, "Stone")
		box(m, "Roof", x - 8, x + 8, 8, 10, z - 7, z + 7, "Tomato.d")
		box(m, "Roof", x - 6, x + 6, 10, 12, z - 7, z + 7, "Tomato")
		box(m, "Roof", x - 3.5, x + 3.5, 12, 14, z - 7, z + 7, "Tomato.l")
		box(m, "Chimney", x + 3, x + 5, 10, 16, z + 2, z + 4, "Stone.d")
		local fx = x + 7 * faceSign
		box(m, "Door", fx - 0.2, fx + 0.2, 0, 5, z - 1.5, z + 1.5, "Bark")
		box(m, "Window", fx - 0.2, fx + 0.2, 4, 6.5, z + 2.5, z + 5, "Sky.l", { shadow = false })
		box(m, "Window", fx - 0.2, fx + 0.2, 4, 6.5, z - 5, z - 2.5, "Sky.l", { shadow = false })
	end
	house(-92, 92, 1)
	house(92, 92, -1)
end
-- @end zone
