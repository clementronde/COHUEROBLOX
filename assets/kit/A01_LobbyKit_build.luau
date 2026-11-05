--!nocheck
-- COHUE — pièces du lobby en Parts « tout en tenons » (A01, 5 nov. 2026). Clément place lui-même.
-- Exécuté À L'ÉDITION par le MCP de Studio, section par section. Jamais chargé par le jeu.
-- Prérequis : la section @header de A01_AssetKit_build.luau (shared.A01Kit).
-- Repère local de chaque Model : Y en haut, AVANT vers −Z, pivot au centre de la base.
-- Résultat : Workspace.A01_AssetKit.Lobby.

-- @lobby_header
local K = shared.A01Kit
assert(K, "relancer d'abord la section @header de A01_AssetKit_build.luau")
for k, v in pairs({
	Plum = "4B3866", ["Plum.d"] = "3F2E58", ["Plum.dd"] = "37274D", Grape = "8C52E0", ["Grape.d"] = "6A3FA7",
	["Grape.dd"] = "51327E", Royal = "2D6BE6", ["Royal.d"] = "2C4FAB", Ink = "1C1726", Sky = "3FD0F5",
	["Sky.d"] = "3891B5", Lime = "8FD13F", ["Lime.d"] = "6C923E", ["Tomato.d"] = "A42F43", ["Tomato.dd"] = "752841",
	["Cream.dd"] = "7F6E6E", ["Stone.dd"] = "584C5B", ["Steel.dd"] = "525372", ["Leaf.dd"] = "325D42", ["Bark.d"] = "56352F",
}) do K.PAL[k] = v end
-- B(m, {sx,sy,sz}, {x,y,z}, couleur, o) ; o.r = {rx,ry,rz} en degrés, o.c = false sans collision, o.neon, o.n = nom
function K.B(m, s, p, key, o)
	o = o or {}
	local r = o.r or { 0, 0, 0 }
	local cf = CFrame.new(p[1], p[2], p[3]) * CFrame.Angles(math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))
	return K.part(m, Vector3.new(s[1], s[2], s[3]), cf, key, o.c ~= false, { neon = o.neon, name = o.n, j = o.j })
end
-- Boîte par ses bornes
function K.BB(m, x0, x1, y0, y1, z0, z1, key, o)
	return K.B(m, { x1 - x0, y1 - y0, z1 - z0 }, { (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2 }, key, o)
end
function K.lobbyShelf()
	local kit = workspace.A01_AssetKit
	local f = kit:FindFirstChild("Lobby")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Lobby"
		f.Parent = kit
	end
	return f
end
function K.replace(name)
	local old = K.lobbyShelf():FindFirstChild(name)
	if old then old:Destroy() end
	return K.model(name, "Lobby")
end
return "lobby header ok"

-- @portal
-- Tête de gobelin géante en pierre, endormie : la bouche est le portail (12 × 12 studs).
local K = shared.A01Kit
local B, BB = K.B, K.BB
local m = K.replace("Portal_GoblinHead")
local NC = { c = false }
-- masse : mâchoires, visage, crâne en gradins
BB(m, -14, -6, 0, 12, -10, 10, "Stone", { n = "JawL" })
BB(m, 6, 14, 0, 12, -10, 10, "Stone", { n = "JawR" })
BB(m, -14, 14, 12, 30, -10, 10, "Stone", { n = "Face" })
BB(m, -12, 12, 30, 33, -8, 9, "Stone", { n = "Skull" })
BB(m, -8, 8, 33, 35, -5, 7, "Stone", { n = "SkullTop" })
-- gorge sombre et tourbillon (Neon : surfaces lisses)
BB(m, -6, 6, 0, 12, 6, 10, "Plum.dd", { n = "Throat" })
BB(m, -6, -5.6, 0, 12, -10, 6, "Plum.dd", NC)
BB(m, 5.6, 6, 0, 12, -10, 6, "Plum.dd", NC)
BB(m, -6, 6, 11.6, 12, -10, 6, "Plum.dd", NC)
BB(m, -5.6, 5.6, 0, 11.6, 5.4, 6, "Grape.d", { c = false, neon = true, n = "PortalSwirl" })
BB(m, -4, 4, 1.5, 9.5, 5, 5.4, "Royal.d", { c = false, neon = true, n = "Swirl2" })
BB(m, -2, 2, 3.5, 7.5, 4.6, 5, "Grape.d", { c = false, neon = true, n = "Swirl3" })
-- lèvres, dents du haut inégales, défenses (une cassée), langue-tapis
BB(m, -7, 7, 11, 12.5, -11, -10, "Stone.d", { n = "Lip" })
BB(m, -7, -6, 0, 12.5, -11, -10, "Stone.d", { n = "Lip" })
BB(m, 6, 7, 0, 12.5, -11, -10, "Stone.d", { n = "Lip" })
BB(m, -4.5, -3, 9, 11, -10.6, -9.6, "Cream.d", NC)
BB(m, -1, 1, 8, 11, -10.6, -9.6, "Cream.d", NC)
BB(m, 3, 4.5, 9.5, 11, -10.6, -9.6, "Cream.d", NC)
BB(m, -6.5, -4.5, 0, 4, -11.5, -9.5, "Cream.d", { n = "TuskL" })
BB(m, -6.2, -4.8, 4, 7, -11.8, -10, "Cream.d", { n = "TuskL" })
BB(m, -6, -5, 7, 9.5, -12, -10.6, "Cream.d", { n = "TuskL" })
BB(m, 4.5, 6.5, 0, 4, -11.5, -9.5, "Cream.d", { n = "TuskR" })
BB(m, 4.8, 6.2, 4, 5.5, -11.6, -9.8, "Cream.d", { n = "TuskR" })
BB(m, -4, 4, 0, 0.6, -22, 5.4, "Tomato.d", { n = "Tongue" })
BB(m, -3, 3, 0, 0.6, -23, -22, "Tomato.d", { n = "Tongue" })
BB(m, -0.4, 0.4, 0.6, 0.7, -22, -10, "Tomato.dd", NC)
-- nez crochu, narines, joues
BB(m, -2.5, 2.5, 15, 23, -12.5, -10, "Stone", { n = "Nose" })
BB(m, -2, 2, 12.5, 16, -14, -12, "Stone", { n = "NoseTip" })
BB(m, -1.6, -0.6, 12.5, 13.1, -14.1, -13.4, "Stone.dd", NC)
BB(m, 0.6, 1.6, 12.5, 13.1, -14.1, -13.4, "Stone.dd", NC)
BB(m, -14, -8, 12, 17, -12, -10, "Stone", { n = "CheekL" })
BB(m, 8, 14, 12, 17, -12, -10, "Stone", { n = "CheekR" })
-- sourcils froncés (le droit plus haut : il se méfie), yeux (gauche fermé, droit entrouvert qui regarde en bas)
B(m, { 12, 3, 3 }, { -7, 25.5, -11.5 }, "Stone.d", { r = { 0, 0, -10 }, n = "BrowL" })
B(m, { 12, 3, 3 }, { 7, 26.2, -11.5 }, "Stone.d", { r = { 0, 0, 8 }, n = "BrowR" })
BB(m, -11.5, -3, 19, 23.5, -10.3, -10, "Stone.dd", NC)
BB(m, -11, -3.5, 20.5, 23, -10.8, -10.3, "Stone.l", { n = "LidL" })
BB(m, -11, -3.5, 20.2, 20.5, -10.9, -10.3, "Ink", NC)
BB(m, 3, 11.5, 19, 23.5, -10.3, -10, "Stone.dd", NC)
BB(m, 3.5, 11, 19.5, 21.5, -10.6, -10.3, "Cream.d", { c = false, n = "EyeR" })
BB(m, 3.3, 11.2, 21.5, 23.3, -11.2, -10.3, "Stone.l", { n = "LidR" })
BB(m, 5.5, 7, 19.5, 20.8, -10.8, -10.6, "Ink", { c = false, n = "Pupil" })
-- oreilles : la gauche pointe en l'air et porte un anneau d'or, la droite tombe
BB(m, -20, -14, 17, 27, -2, 3, "Stone", { n = "EarL" })
BB(m, -25, -20, 19.5, 26, -1.5, 2.5, "Stone", { n = "EarL" })
BB(m, -29, -25, 21.5, 25.5, -1, 2, "Stone", { n = "EarL" })
BB(m, -32, -29, 23, 25, -0.5, 1.5, "Stone", { n = "EarL" })
BB(m, -24, -15, 19, 25, -2.4, -2, "Stone.d", NC)
BB(m, -23.2, -22.8, 16.5, 19.5, 0.3, 0.7, "Gold.d", NC)
BB(m, -21.2, -20.8, 16.5, 19.5, 0.3, 0.7, "Gold.d", NC)
BB(m, -23.2, -20.8, 16.1, 16.5, 0.3, 0.7, "Gold.d", NC)
BB(m, 14, 20, 17, 27, -2, 3, "Stone", { n = "EarR" })
BB(m, 20, 25, 16, 23, -1.5, 2.5, "Stone", { n = "EarR" })
BB(m, 25, 29, 14, 20, -1, 2, "Stone", { n = "EarR" })
BB(m, 29, 31.5, 13, 16.5, -0.5, 1.5, "Stone", { n = "EarR" })
BB(m, 15, 24, 18, 25, -2.4, -2, "Stone.d", NC)
-- mousse, fissure, pousse d'arbre sur le crâne
BB(m, -6, 3, 35, 35.4, -5, 4, "Leaf.d", NC)
BB(m, -12, -8, 33, 33.4, -8, 0, "Leaf.d", NC)
BB(m, 8, 12, 33, 33.4, 0, 8, "Leaf.d", NC)
B(m, { 0.4, 5, 0.2 }, { -4, 27.5, -10.1 }, "Stone.dd", { r = { 0, 0, 25 }, c = false })
BB(m, 2, 3, 35, 40, 3, 4, "Bark", NC)
B(m, { 4, 3, 4 }, { 2.5, 41, 3.5 }, "Leaf", { r = { 0, 20, 0 }, c = false })
B(m, { 2.6, 2, 2.6 }, { 2.5, 43, 3.5 }, "Leaf.l", { r = { 0, 45, 0 }, c = false })
m:SetAttribute("Note", "Portail du lobby : la bouche (PortalSwirl, Neon) est la sortie vers la run. La langue mène au pad Public.")
K.place(m, K.lobbyShelf(), Vector3.new(240, 8, 885))

-- pads de départ (1, 2 et 4 silhouettes incrustées), une couleur par mode : Solo bleu, Friends vert, Public jaune
for _, spec in { { "Pad_Solo", 8, { { 0, 0 } }, 296, "Royal" }, { "Pad_Friends", 11, { { -1.8, 0 }, { 1.8, 0 } }, 313, "Lime" }, { "Pad_Public", 14, { { -2.2, -1.6 }, { 2.2, -1.6 }, { -2.2, 2 }, { 2.2, 2 } }, 334, "Gold" } } do
	local p = K.replace(spec[1])
	local s, col = spec[2], spec[5]
	BB(p, -s / 2, s / 2, 0, 0.6, -s / 2, s / 2, "Stone", { n = "Pad" })
	for _, e in { { -s / 2, s / 2, -s / 2, -s / 2 + 0.6 }, { -s / 2, s / 2, s / 2 - 0.6, s / 2 }, { -s / 2, -s / 2 + 0.6, -s / 2, s / 2 }, { s / 2 - 0.6, s / 2, -s / 2, s / 2 } } do
		BB(p, e[1], e[2], 0, 0.7, e[3], e[4], col .. ".d", { n = "Rim" })
	end
	-- silhouettes vues du devant : tête au fond (+Z), corps vers le joueur
	for _, f in spec[3] do
		BB(p, f[1] - 0.5, f[1] + 0.5, 0.6, 0.75, f[2] + 0.4, f[2] + 1.4, col, { c = false, n = "Head" })
		BB(p, f[1] - 1, f[1] + 1, 0.6, 0.75, f[2] - 1, f[2] + 0.2, col, { c = false, n = "Body" })
	end
	-- deux mâts à l'arrière, fanions tournés vers l'intérieur
	for _, side in { -1, 1 } do
		local x = side * (s / 2 - 0.3)
		BB(p, x - 0.3, x + 0.3, 0.6, 6.6, s / 2 - 0.6, s / 2, "Bark", { n = "Mast" })
		BB(p, x - 0.4, x + 0.4, 6.6, 7, s / 2 - 0.7, s / 2 + 0.1, col .. ".d", NC)
		local a, b = x - side * 0.3, x - side * 2.7
		BB(p, math.min(a, b), math.max(a, b), 4.8, 6.4, s / 2 - 0.4, s / 2 - 0.2, col, { c = false, n = "Pennant" })
	end
	p:SetAttribute("Note", "Pad de départ : " .. #spec[3] .. " joueur(s) max affiché(s). Zone à interroger par GetPartBoundsInBox (A09).")
	K.place(p, K.lobbyShelf(), Vector3.new(spec[4], 8, 885))
end
return "portal + pads ok"

-- @stations
-- Stations des classes : Knight (cour d'armes), Archer (pas de tir), Mage (tour au toit-chapeau),
-- et la charrette des 5 classes à débloquer.
local K = shared.A01Kit
local B, BB = K.B, K.BB
local NC = { c = false }
-- Knight
local m = K.replace("Station_Knight")
BB(m, -5, -4.4, 0, 5, 2, 2.6, "Bark", { n = "Rack" })
BB(m, -0.6, 0, 0, 5, 2, 2.6, "Bark", { n = "Rack" })
BB(m, -5, 0, 4.6, 5.2, 2, 2.6, "Bark", { n = "Rack" })
BB(m, -5, 0, 1, 1.4, 2, 2.6, "Bark.d", { n = "Rack" })
for i, x in { -4, -3, -2, -1.2 } do
	local top = ({ 4.85, 4.4, 4.85, 3.9 })[i]
	BB(m, x - 0.15, x + 0.15, 1.2, top - 1, 1.6, 1.8, "Steel", NC)
	BB(m, x - 0.5, x + 0.5, top - 1, top - 0.75, 1.55, 1.85, "Bark.d", NC)
	BB(m, x - 0.12, x + 0.12, top - 0.75, top - 0.25, 1.6, 1.8, "Leather", NC)
	BB(m, x - 0.2, x + 0.2, top - 0.25, top, 1.55, 1.85, (i == 1) and "Gold.d" or "Bark.d", NC)
end
BB(m, 2.8, 3.2, 0, 3, -0.2, 0.2, "Bark", { n = "Dummy" })
BB(m, 1.8, 4.2, 3, 6, -0.8, 0.8, "Leather", { n = "Dummy" })
BB(m, 0.8, 5.2, 5, 5.4, -0.25, 0.25, "Leather.d", NC)
BB(m, 2.3, 3.7, 6, 7.4, -0.7, 0.7, "Leather", { n = "DummyHead" })
BB(m, 2.1, 3.9, 7.4, 8.3, -0.9, 0.9, "Steel.d", { n = "Cocotte" })
BB(m, 1.7, 2.1, 7.9, 8.1, -0.2, 0.2, "Steel.dd", NC)
BB(m, 3.9, 4.3, 7.9, 8.1, -0.2, 0.2, "Steel.dd", NC)
for _, ex in { 2.65, 3.35 } do
	B(m, { 0.4, 0.1, 0.05 }, { ex, 6.9, -0.73 }, "Ink", { r = { 0, 0, 45 }, c = false })
	B(m, { 0.4, 0.1, 0.05 }, { ex, 6.9, -0.73 }, "Ink", { r = { 0, 0, -45 }, c = false })
end
BB(m, 2.6, 3.4, 6.35, 6.45, -0.75, -0.7, "Bark.d", NC)
B(m, { 0.25, 3, 0.15 }, { 3.6, 4.6, -1.1 }, "Steel", { r = { 30, 0, -35 }, c = false })
B(m, { 0.3, 0.8, 0.3 }, { 4.6, 5.9, -1.9 }, "Leather", { r = { 30, 0, -35 }, c = false })
BB(m, -3.6, -1.6, 0, 1.8, -3, -1, "Bark", { n = "Stump" })
BB(m, -3.4, -1.8, 1.8, 1.9, -2.8, -1.2, "Leather.l", NC)
BB(m, -3.2, -2, 1.9, 2.4, -2.4, -1.6, "Steel.dd", { n = "Anvil" })
BB(m, -3.6, -1.6, 2.4, 3, -2.5, -1.5, "Steel.dd", { n = "Anvil" })
BB(m, -4.3, -3.6, 2.6, 2.95, -2.2, -1.8, "Steel.dd", NC)
B(m, { 2.4, 3, 0.35 }, { -0.3, 1.45, -2.6 }, "Royal.d", { r = { -12, 0, 0 }, n = "Shield" })
B(m, { 0.6, 0.6, 0.2 }, { -0.3, 1.6, -2.85 }, "Gold.d", { r = { -12, 0, 0 }, c = false })
BB(m, 5.2, 5.5, 0, 9, 2, 2.3, "Bark", { n = "Pole" })
BB(m, 5.5, 7.5, 6.8, 8.8, 2.05, 2.25, "Royal.d", NC)
BB(m, 7.5, 8.7, 7.2, 8.4, 2.05, 2.25, "Royal.d", NC)
BB(m, 8.7, 9.5, 7.6, 8.0, 2.05, 2.25, "Royal.d", NC)
m:SetAttribute("ClassId", "Knight")
K.place(m, K.lobbyShelf(), Vector3.new(220, 8, 940))
-- Archer
m = K.replace("Station_Archer")
local function target(cx, cy, R)
	BB(m, cx - R, cx + R, cy - R, cy + R, 1.5, 1.9, "Cream.d", { n = "Target" })
	BB(m, cx - 0.7 * R, cx + 0.7 * R, cy - 0.7 * R, cy + 0.7 * R, 1.35, 1.5, "Tomato.d", NC)
	BB(m, cx - 0.45 * R, cx + 0.45 * R, cy - 0.45 * R, cy + 0.45 * R, 1.2, 1.35, "Cream.d", NC)
	BB(m, cx - 0.22 * R, cx + 0.22 * R, cy - 0.22 * R, cy + 0.22 * R, 1.05, 1.2, "Tomato", NC)
	B(m, { 0.3, cy + R * 0.3, 0.3 }, { cx - R * 0.6, (cy + R * 0.3) / 2, 2.2 }, "Bark", { r = { -10, 0, 0 } })
	B(m, { 0.3, cy + R * 0.3, 0.3 }, { cx + R * 0.6, (cy + R * 0.3) / 2, 2.2 }, "Bark", { r = { -10, 0, 0 } })
end
target(-4, 2.6, 1.6)
target(0.5, 2.3, 1.3)
target(4.3, 2, 1)
local function arrow(x, y)
	BB(m, x - 0.08, x + 0.08, y - 0.08, y + 0.08, -0.6, 1.5, "Bark", NC)
	BB(m, x - 0.3, x + 0.3, y - 0.02, y + 0.02, -0.6, -0.2, "Leaf.d", NC)
	BB(m, x - 0.02, x + 0.02, y - 0.3, y + 0.3, -0.6, -0.2, "Leaf.d", NC)
end
arrow(-3.4, 3.2)
arrow(-4.7, 2.0)
arrow(4.6, 1.7)
BB(m, 0.3, 0.7, 2.1, 2.5, -0.9, 1.05, "Ember", { c = false, n = "Carrot" })
B(m, { 0.15, 0.6, 0.15 }, { 0.4, 2.7, -1.1 }, "Leaf.d", { r = { 30, 0, 15 }, c = false })
B(m, { 0.15, 0.6, 0.15 }, { 0.6, 2.7, -1.1 }, "Leaf.d", { r = { 30, 0, -15 }, c = false })
for _, a in { { -5.5, -2 }, { 2.5, -1 }, { 5.8, 0.5 } } do
	B(m, { 0.15, 2.2, 0.15 }, { a[1], 0.8, a[2] }, "Bark", { r = { 20, 0, 10 }, c = false })
	B(m, { 0.5, 0.5, 0.1 }, { a[1] - 0.2, 1.8, a[2] + 0.4 }, "Leaf.d", { r = { 20, 0, 10 }, c = false })
end
B(m, { 2.2, 2.8, 1.5 }, { -5.5, 1.4, -3.2 }, "Leather", { n = "Barrel" })
B(m, { 1.5, 2.8, 2.2 }, { -5.5, 1.4, -3.2 }, "Leather", { n = "Barrel" })
for _, yy in { 0.6, 2.2 } do
	B(m, { 2.3, 0.3, 1.6 }, { -5.5, yy, -3.2 }, "Bark", NC)
	B(m, { 1.6, 0.3, 2.3 }, { -5.5, yy, -3.2 }, "Bark", NC)
end
for i, d in { { -0.3, -0.2 }, { 0.3, 0.2 }, { 0, 0.4 } } do
	B(m, { 0.15, 2.4, 0.15 }, { -5.5 + d[1], 3.6, -3.2 + d[2] }, "Bark", { r = { 0, 0, (i - 2) * 8 }, c = false })
	B(m, { 0.4, 0.4, 0.4 }, { -5.5 + d[1] - (i - 2) * 0.15, 4.85, -3.2 + d[2] }, "Leaf.d", NC)
end
BB(m, -4, 4, 0, 0.6, -4.6, -4, "Bark", { n = "ShootLine" })
BB(m, 5.4, 5.7, 0, 8, -3.6, -3.3, "Bark", { n = "Pole" })
BB(m, 5.7, 7.7, 6, 7.8, -3.55, -3.35, "Leaf.d", NC)
BB(m, 7.7, 8.8, 6.4, 7.4, -3.55, -3.35, "Leaf.d", NC)
m:SetAttribute("ClassId", "Archer")
K.place(m, K.lobbyShelf(), Vector3.new(240, 8, 940))
-- Mage
m = K.replace("Station_Mage")
BB(m, -3, 3, 0, 4, -3, 3, "Stone.d", { n = "TowerBase" })
BB(m, -2.2, -1.2, 1, 1.8, -3.1, -3, "Stone.dd", NC)
BB(m, 1, 2.4, 2.4, 3.2, -3.1, -3, "Stone.dd", NC)
B(m, { 5, 9, 5 }, { 0.3, 8.5, 0 }, "Cream.d", { r = { 0, 0, -3 }, n = "TowerBody" })
B(m, { 0.4, 9, 0.2 }, { 0.3, 8.5, -2.55 }, "Bark", { r = { 0, 0, -3 }, c = false })
B(m, { 0.2, 9, 0.4 }, { -2.24, 8.37, 0 }, "Bark", { r = { 0, 0, -3 }, c = false })
B(m, { 5.2, 0.5, 5.2 }, { 0.55, 9.5, 0 }, "Bark", { r = { 0, 0, -3 }, c = false })
B(m, { 8, 0.6, 8 }, { 0.9, 13.2, 0 }, "Grape.dd", { r = { 0, 10, -3 }, n = "HatBrim" })
B(m, { 6.6, 0.4, 6.6 }, { 0.95, 13.7, 0 }, "Plum", { r = { 0, 10, -3 }, c = false })
for i = 0, 4 do
	local s = 6.4 - 1.2 * i
	B(m, { s, 1.2, s }, { 0.9 + 0.3 * i, 14.1 + 1.2 * i, 0 }, "Grape.d", { r = { 0, 10 + 6 * i, -3 }, n = "Hat" })
end
B(m, { 1.2, 1.4, 1.2 }, { 3.4, 20.3, 0 }, "Grape.d", { r = { 0, 40, -25 }, n = "HatTip" })
BB(m, -1, 1, 0, 2.6, -3.2, -3, "Bark", { n = "Door" })
BB(m, 0.6, 0.8, 1.2, 1.4, -3.35, -3.2, "Gold.d", NC)
B(m, { 1, 1.2, 0.2 }, { 0.6, 10.8, -2.6 }, "Gold", { c = false, neon = true, n = "Window", r = { 0, 0, -3 } })
BB(m, 2.6, 5, 0.4, 2.2, -4.8, -2.4, "Ink", { n = "Cauldron" })
BB(m, 2.4, 5.2, 2.2, 2.5, -5, -2.2, "Ink", { n = "Cauldron" })
BB(m, 2.8, 4.8, 2.2, 2.4, -4.6, -2.6, "Leaf", { c = false, n = "Potion" })
BB(m, 3.2, 3.6, 2.5, 2.9, -3.9, -3.5, "Leaf", NC)
BB(m, 4.1, 4.4, 2.6, 2.9, -3.2, -2.9, "Leaf", NC)
for _, l in { { 2.7, -4.7 }, { 4.7, -4.7 }, { 3.7, -2.5 } } do BB(m, l[1] - 0.2, l[1] + 0.2, 0, 0.4, l[2] - 0.2, l[2] + 0.2, "Ink", NC) end
BB(m, -4.5, -3.3, 0, 0.4, -4.5, -3.6, "Tomato.d", { n = "Books" })
BB(m, -4.4, -3.4, 0.4, 0.8, -4.4, -3.7, "Royal.d", NC)
BB(m, -4.6, -3.5, 0.8, 1.1, -4.5, -3.6, "Leaf.dd", NC)
m:SetAttribute("ClassId", "Mage")
K.place(m, K.lobbyShelf(), Vector3.new(260, 8, 940))
-- Charrette des 5 classes à débloquer
m = K.replace("Station_LockedClasses")
BB(m, -5, 5, 1.6, 2.2, -2.2, 2.2, "Bark", { n = "CartBed" })
BB(m, -5, 5, 2.2, 2.8, -2.2, -1.9, "Leather.d", NC)
BB(m, -5, 5, 2.2, 2.8, 1.9, 2.2, "Leather.d", NC)
for _, w in { { -3, -2.5 }, { 3, -2.5 }, { -3, 2.5 }, { 3, 2.5 } } do
	B(m, { 2.8, 2.8, 0.4 }, { w[1], 1.4, w[2] }, "Bark.d", { n = "Wheel" })
	B(m, { 2.8, 2.8, 0.4 }, { w[1], 1.4, w[2] }, "Bark.d", { r = { 0, 0, 45 }, n = "Wheel" })
	B(m, { 0.7, 0.7, 0.6 }, { w[1], 1.4, w[2] }, "Steel.d", NC)
end
BB(m, 5, 8.5, 1.2, 1.5, -1.5, -1.2, "Bark", { n = "Handle" })
BB(m, 5, 8.5, 1.2, 1.5, 1.2, 1.5, "Bark", { n = "Handle" })
local function crate(x0, z0, y0, s, stripe, lock)
	BB(m, x0, x0 + s, y0, y0 + s, z0, z0 + s, "Leather.d", { n = "Crate" })
	for _, c in { { x0, z0 }, { x0 + s - 0.25, z0 }, { x0, z0 + s - 0.25 }, { x0 + s - 0.25, z0 + s - 0.25 } } do
		BB(m, c[1] - 0.02, c[1] + 0.27, y0, y0 + s, c[2] - 0.02, c[2] + 0.27, "Bark", NC)
	end
	BB(m, x0 - 0.05, x0 + s + 0.05, y0 + s / 2 - 0.15, y0 + s / 2 + 0.15, z0 - 0.05, z0 + s + 0.05, stripe, NC)
	if lock then
		local mx = x0 + s / 2
		BB(m, mx - 0.3, mx + 0.3, y0 + s / 2 - 0.9, y0 + s / 2 - 0.25, z0 - 0.25, z0, "Steel.d", NC)
		BB(m, mx - 0.08, mx + 0.08, y0 + s / 2 - 0.7, y0 + s / 2 - 0.5, z0 - 0.28, z0 - 0.25, "Gold.d", NC)
	end
end
crate(-4.6, -1.8, 2.8, 3.4, "Tomato.d", true)
crate(-0.9, -1.6, 2.8, 2.8, "Sky.d", false)
crate(2.2, -1.3, 2.8, 2.3, "Ember.d", false)
crate(-4.1, -1.3, 6.2, 2.4, "Steel.d", true)
crate(-8.2, -3.5, 0, 2.6, "Gold.d", true)
BB(m, -1.1, 2.1, 5.6, 5.9, -1.8, 1.4, "Plum.d", { c = false, n = "Tarp" })
BB(m, -1.15, -0.9, 4, 5.9, -1.8, 1.4, "Plum.d", NC)
BB(m, 1.85, 2.1, 4, 5.9, -1.8, 1.4, "Plum.d", NC)
B(m, { 0.8, 1.6, 0.8 }, { 0.5, 6.6, -0.2 }, "Plum.d", { r = { 0, 0, -15 }, c = false, n = "Mystery" })
BB(m, 2.6, 4.1, 4, 4.5, -1.35, -1.25, "Ink", NC)
BB(m, 2.8, 3.1, 4.1, 4.4, -1.4, -1.35, "Cream", { c = false, n = "Eyes" })
BB(m, 3.6, 3.9, 4.1, 4.4, -1.4, -1.35, "Cream", { c = false, n = "Eyes" })
K.place(m, K.lobbyShelf(), Vector3.new(285, 8, 940))
return "stations ok"

-- @services
-- Boutique de Gob, enclos des compagnons, panthéon, tableau des quêtes, meule d'arrivée, feu de camp.
local K = shared.A01Kit
local B, BB = K.B, K.BB
local NC = { c = false }
-- Boutique de Gob
local m = K.replace("Station_GobShop")
BB(m, -6, 6, 0, 0.4, -3.5, 3.5, "Bark.d", { n = "Floor" })
for _, p in { { -6, -3.5 }, { 5.5, -3.5 }, { -6, 3 }, { 5.5, 3 } } do BB(m, p[1], p[1] + 0.5, 0.4, 9.5, p[2], p[2] + 0.5, "Bark", { n = "Post" }) end
BB(m, -5.5, 5.5, 0.4, 7, 3, 3.4, "Leather.d", { n = "BackWall" })
for _, y in { 2.4, 4.4, 6.2 } do BB(m, -5.5, 5.5, y, y + 0.12, 2.95, 3, "Bark.d", NC) end
BB(m, -5, 5, 3.4, 3.6, 2, 3, "Bark", { n = "Shelf" })
BB(m, -5, 5, 5.6, 5.8, 2, 3, "Bark", { n = "Shelf" })
BB(m, -4.3, -3.3, 3.6, 3.75, 2.1, 3, "Ink", NC)
BB(m, -4.05, -3.55, 3.75, 4.6, 2.3, 2.8, "Ink", NC)
BB(m, -4.1, -3.5, 3.8, 3.95, 2.25, 2.85, "Tomato.d", NC)
BB(m, -2, -0.8, 3.6, 3.8, 2.1, 2.9, "Grape.d", NC)
BB(m, -1.8, -1, 3.8, 4.3, 2.3, 2.7, "Grape.d", NC)
BB(m, -1.6, -1.2, 4.3, 4.8, 2.4, 2.6, "Grape.d", NC)
BB(m, 0.6, 1.8, 3.6, 3.9, 2.2, 2.8, "Gold.d", NC)
for _, x in { 0.65, 1.1, 1.55 } do BB(m, x, x + 0.2, 3.9, 4.2, 2.2, 2.4, "Gold.d", NC) end
BB(m, 2.8, 4, 3.6, 4.3, 2.2, 2.8, "Steel.d", NC)
BB(m, 2.5, 2.8, 4, 4.15, 2.4, 2.6, "Steel.dd", NC)
BB(m, 4, 4.3, 4, 4.15, 2.4, 2.6, "Steel.dd", NC)
BB(m, -3.5, -2.3, 5.8, 6.5, 2.2, 2.8, "Ember.d", NC)
BB(m, -3.05, -2.75, 6.5, 6.8, 2.35, 2.65, "Cream", NC)
BB(m, -5, 5, 0.4, 3, -3, -2, "Bark", { n = "Counter" })
BB(m, -5.3, 5.3, 3, 3.3, -3.2, -1.8, "Leather", { n = "CounterTop" })
for _, x in { -3, 0, 3 } do BB(m, x - 0.06, x + 0.06, 0.6, 2.8, -3.05, -3, "Bark.d", NC) end
for i = 0, 7 do
	local x = -5.25 + i * 1.5
	B(m, { 1.5, 0.4, 8.6 }, { x, 9.5, -0.5 }, (i % 2 == 0) and "Tomato.d" or "Cream.d", { r = { -14, 0, 0 }, n = "Awning" })
	if i % 2 == 0 then BB(m, x - 0.75, x + 0.75, 7.9, 8.5, -4.9, -4.5, "Tomato.d", NC) end
end
BB(m, -2.5, 2.5, 10.4, 10.8, 0.5, 4.5, "Ink", { n = "SignHat" })
BB(m, -1.5, 1.5, 10.8, 13.8, 1, 4, "Ink", { n = "SignHat" })
BB(m, -1.6, 1.6, 11.2, 11.9, 0.9, 4.1, "Tomato.d", NC)
BB(m, 4.6, 6.4, 0.4, 6, -5, -4.6, "Bark", { n = "Mirror" })
BB(m, 4.8, 6.2, 0.8, 5.6, -5.1, -5, "Steel.l", { c = false, n = "MirrorGlass" })
BB(m, -6.6, -4.6, 0, 2.2, -5.4, -3.6, "Leather", { n = "XPSack" })
BB(m, -6, -5.2, 2.2, 2.6, -4.9, -4.1, "Bark", NC)
BB(m, -4.2, -3.7, 0, 1.1, -5.6, -5.1, "Sky", { c = false, n = "XPBottle" })
BB(m, -4.1, -3.8, 1.1, 1.3, -5.5, -5.2, "Cream.d", NC)
BB(m, -3.4, -2.9, 0, 0.9, -5, -4.5, "Sky", { c = false, n = "XPBottle" })
B(m, { 1.1, 0.5, 0.5 }, { -3.6, 0.25, -6.2 }, "Sky", { r = { 0, 30, 0 }, c = false, n = "XPBottle" })
m:SetAttribute("Note", "Boutique de Gob : le gobelin voleur d'XP vend des chapeaux. Le comptoir porte le ShopPrompt (A09).")
K.place(m, K.lobbyShelf(), Vector3.new(220, 8, 985))
-- Enclos des compagnons
m = K.replace("Station_CritterPen")
local W, D = 10, 8
local function post(x, z, h, key) BB(m, x - 0.3, x + 0.3, 0, h or 3, z - 0.3, z + 0.3, key or "Bark", { n = "Post" }) end
local function rail(x0, x1, z0, z1)
	for _, y in { 1.2, 2.3 } do BB(m, x0, x1, y - 0.2, y + 0.2, z0, z1, "Leather", { n = "Rail" }) end
end
for _, x in { -W, -6, -2, 2, 6, W } do post(x, -D) end
for _, x in { -W, -6, 6, W } do post(x, D) end
post(2, D, 1.4, "Bark.d")
for _, z in { -4, 0, 4 } do post(-W, z); post(W, z) end
rail(-W, -2, -D - 0.15, -D + 0.15); rail(2, W, -D - 0.15, -D + 0.15)
rail(-W, -2, D - 0.15, D + 0.15); rail(6, W, D - 0.15, D + 0.15)
rail(-W - 0.15, -W + 0.15, -D, D); rail(W - 0.15, W + 0.15, -D, D)
BB(m, -2.4, -1.6, 0, 4.5, -D - 0.4, -D + 0.4, "Bark", { n = "GatePost" })
BB(m, 1.6, 2.4, 0, 4.5, -D - 0.4, -D + 0.4, "Bark", { n = "GatePost" })
BB(m, -2.4, 2.4, 4.5, 5, -D - 0.4, -D + 0.4, "Bark", { n = "GateBar" })
BB(m, -1.2, 1.2, 5.2, 5.6, -D - 0.1, -D + 0.1, "Cream.d", { c = false, n = "BoneSign" })
for _, x in { -1.5, 1.5 } do BB(m, x - 0.3, x + 0.3, 5, 5.8, -D - 0.1, -D + 0.1, "Cream.d", NC) end
BB(m, -8, -4, 0, 3, 3.5, 7.5, "Bark", { n = "Doghouse" })
BB(m, -6.8, -5.2, 0, 2, 3.4, 3.5, "Ink", NC)
B(m, { 2.9, 0.4, 4.6 }, { -7.1, 3.7, 5.5 }, "Tomato.dd", { r = { 0, 0, 35 }, n = "Roof" })
B(m, { 2.9, 0.4, 4.6 }, { -4.9, 3.7, 5.5 }, "Tomato.dd", { r = { 0, 0, -35 }, n = "Roof" })
BB(m, -6.6, -5.4, 0, 0.25, 2.2, 2.5, "Cream.d", { c = false, n = "Bone" })
for _, x in { -6.8, -5.2 } do BB(m, x - 0.2, x + 0.2, 0, 0.3, 2.1, 2.6, "Cream.d", NC) end
BB(m, 2, 6, 0, 1, 4, 5.5, "Bark", { n = "Trough" })
BB(m, 2.2, 5.8, 1, 1.05, 4.2, 5.3, "Sky.d", { c = false, n = "Water" })
BB(m, 5, 7.4, 0, 1.2, -4, -2, "Gold.d", { n = "Hay" })
BB(m, 5.4, 7, 1.2, 1.8, -3.6, -2.4, "Gold.d", NC)
m:SetAttribute("Note", "Enclos des compagnons : les créatures capturées s'y promènent (rendu client). CrittersPrompt sur le portail (A09).")
K.place(m, K.lobbyShelf(), Vector3.new(250, 8, 985))
-- Panthéon (classements)
m = K.replace("Station_HallOfFame")
BB(m, -7, 7, 0, 11, 2, 3.2, "Stone.d", { n = "Stele" })
BB(m, -6.3, -0.4, 1, 10.3, 1.8, 2, "Plum.dd", { c = false, n = "BoardWeekly" })
BB(m, 0.4, 6.3, 1, 10.3, 1.8, 2, "Plum.dd", { c = false, n = "BoardAllTime" })
for row = 0, 5 do
	local y = 9.2 - row * 1.4
	BB(m, -6, -1.2 - (row % 2) * 0.8, y, y + 0.15, 1.7, 1.8, "Plum.d", NC)
	BB(m, 0.7, 5.5 - (row % 3) * 0.6, y, y + 0.15, 1.7, 1.8, "Plum.d", NC)
end
BB(m, -7.5, 7.5, 11, 11.6, 1.6, 3.6, "Stone", { n = "Cap" })
BB(m, -0.8, 0.8, 11.6, 12, 2, 2.8, "Gold.d", NC)
BB(m, -0.3, 0.3, 12, 12.8, 2.2, 2.6, "Gold.d", NC)
BB(m, -1.1, 1.1, 12.8, 14.2, 1.8, 3, "Gold.d", { c = false, n = "Trophy" })
BB(m, -1.6, -1.1, 13.1, 13.9, 2.25, 2.55, "Gold.d", NC)
BB(m, 1.1, 1.6, 13.1, 13.9, 2.25, 2.55, "Gold.d", NC)
for i, p in { { -2, 2, 3, "Gold.d" }, { -6, -2, 2, "Steel.d" }, { 2, 6, 1.2, "Leather" } } do
	BB(m, p[1], p[2], 0, p[3], -3, 0, "Stone", { n = "StatueSlot" .. i })
	BB(m, p[1], p[2], p[3], p[3] + 0.2, -3, 0, p[4], NC)
end
m:SetAttribute("Note", "Panthéon : BoardWeekly / BoardAllTime reçoivent les SurfaceGui (A09) ; StatueSlot1..3 : statues du top 3.")
K.place(m, K.lobbyShelf(), Vector3.new(282, 8, 985))
-- Tableau des quêtes
m = K.replace("Station_QuestBoard")
BB(m, -5, -4.5, 0, 8, 0, 0.5, "Bark", { n = "Post" })
BB(m, 4.5, 5, 0, 8, 0, 0.5, "Bark", { n = "Post" })
BB(m, -4.5, 4.5, 2.5, 7.5, 0, 0.4, "Leather.d", { n = "Board" })
BB(m, -4.6, 4.6, 7.5, 7.8, -0.1, 0.5, "Bark", NC)
BB(m, -4.6, 4.6, 2.2, 2.5, -0.1, 0.5, "Bark", NC)
B(m, { 11, 0.4, 2.2 }, { 0, 8.6, -0.5 }, "Bark.d", { r = { -20, 0, 0 }, n = "Roof" })
B(m, { 11, 0.4, 2.2 }, { 0, 8.6, 1.3 }, "Bark.d", { r = { 20, 0, 0 }, n = "Roof" })
for i, p in { { -4, -1.6, 5, 7.1 }, { -1.2, 1.2, 5.4, 7.2 }, { 1.6, 4, 4.6, 6.9 }, { -3.6, -0.8, 2.8, 4.6 }, { -0.4, 2.2, 2.8, 4.4 } } do
	BB(m, p[1], p[2], p[3], p[4], -0.1, 0, "Cream.d", { c = false, n = "Note" .. i })
	BB(m, (p[1] + p[2]) / 2 - 0.12, (p[1] + p[2]) / 2 + 0.12, p[4] - 0.3, p[4] - 0.06, -0.15, -0.1, "Tomato", NC)
	if i ~= 3 then
		for k = 1, 2 do
			local y = p[3] + (p[4] - p[3]) * (0.3 * k)
			BB(m, p[1] + 0.25, p[2] - 0.25 - 0.4 * (k - 1), y, y + 0.1, -0.13, -0.1, "Stone.d", NC)
		end
	end
end
BB(m, 2.3, 3.3, 5.2, 6.1, -0.15, -0.1, "Lime.d", { c = false, n = "WantedGoblin" })
BB(m, 2.45, 2.65, 5.75, 5.95, -0.18, -0.15, "Ink", NC)
BB(m, 2.95, 3.15, 5.75, 5.95, -0.18, -0.15, "Ink", NC)
BB(m, 2.3, 3.3, 6.1, 6.3, -0.15, -0.1, "Tomato.d", NC)
BB(m, 2.4, 3.6, 9.2, 10.8, -0.2, 0.8, "Leather", { n = "Owl" })
BB(m, 2.6, 3.4, 9.3, 10.4, -0.3, -0.2, "Cream.d", NC)
BB(m, 2.45, 2.95, 10.2, 10.7, -0.35, -0.25, "Cream", NC)
BB(m, 3.05, 3.55, 10.2, 10.7, -0.35, -0.25, "Cream", NC)
BB(m, 2.62, 2.8, 10.3, 10.5, -0.4, -0.35, "Ink", NC)
BB(m, 3.2, 3.38, 10.3, 10.5, -0.4, -0.35, "Ink", NC)
BB(m, 2.9, 3.1, 9.95, 10.2, -0.45, -0.3, "Gold.d", NC)
BB(m, 2.45, 2.7, 10.8, 11.2, 0, 0.3, "Leather.d", NC)
BB(m, 3.3, 3.55, 10.8, 11.2, 0, 0.3, "Leather.d", NC)
BB(m, 3.6, 4.2, 9.2, 10, 0, 0.6, "Bark.d", { c = false, n = "MailBag" })
BB(m, 3.75, 4.05, 10, 10.3, 0.1, 0.5, "Cream.d", NC)
m:SetAttribute("Note", "Tableau des quêtes : la Board reçoit le SurfaceGui des quêtes (A09). Le hibou facteur garde le courrier.")
K.place(m, K.lobbyShelf(), Vector3.new(305, 8, 985))
-- Meule d'arrivée : on revient de run en tombant dedans
m = K.replace("Arrival_Haystack")
BB(m, -5, 5, 0, 2.5, -4.5, 4.5, "Gold.d", { n = "Hay" })
BB(m, -4, 4, 2.5, 4.5, -3.5, 3.5, "Gold.d", { n = "Hay" })
BB(m, -2.6, 2.6, 4.5, 6, -2.2, 2.2, "Gold.d", { n = "Hay" })
for _, s in { { -4.8, 1.2 }, { 1, 0.6 }, { -1.5, 3.2 } } do BB(m, s[1], s[1] + 2.5, s[2], s[2] + 0.25, -4.55, -4.5, "Leather", NC) end
B(m, { 0.9, 2.6, 0.9 }, { -0.8, 6.8, 0 }, "Royal.d", { r = { 0, 0, 15 }, n = "Legs" })
B(m, { 0.9, 2.4, 0.9 }, { 0.8, 6.6, 0.2 }, "Royal.d", { r = { 0, 0, -12 }, n = "Legs" })
B(m, { 1.1, 0.7, 1.6 }, { -1.2, 8.2, -0.2 }, "Leather", { r = { 0, 0, 15 }, c = false })
B(m, { 1.1, 0.7, 1.6 }, { 1.1, 7.9, 0 }, "Leather", { r = { 0, 0, -12 }, c = false })
for _, z in { -0.8, 0.8 } do B(m, { 0.25, 7, 0.25 }, { 5.8, 3.4, z }, "Bark", { r = { 0, 0, 15 }, n = "Ladder" }) end
for k = 0, 3 do
	local y = 1 + 1.5 * k
	BB(m, 6.5 - (y - 3.4) * 0.27 - 0.6 - 0.12, 6.5 - (y - 3.4) * 0.27 - 0.6 + 0.12, y - 0.1, y + 0.1, -0.8, 0.8, "Bark", NC)
end
for _, b in { { -6.4, -1 }, { 5.6, 3.6 }, { -2, 5.6 }, { 3.2, -5.4 } } do BB(m, b[1], b[1] + 0.8, 0, 0.3, b[2], b[2] + 0.4, "Gold.d", NC) end
m:SetAttribute("Note", "Arrivée : point d'apparition et de retour de run (LobbyRole Arrival, A09).")
K.place(m, K.lobbyShelf(), Vector3.new(326, 8, 985))
-- Feu de camp
m = K.replace("Campfire")
for k = 0, 7 do
	local a = k / 8 * math.pi * 2
	B(m, { 0.9, 0.6, 0.9 }, { 2.6 * math.cos(a), 0.3, 2.6 * math.sin(a) }, "Stone.d", { r = { 0, k * 20, 0 }, n = "Stone" })
end
B(m, { 3.2, 0.6, 0.6 }, { 0, 0.4, 0 }, "Bark", { r = { 0, 30, 0 }, n = "Log" })
B(m, { 3.2, 0.6, 0.6 }, { 0, 0.5, 0 }, "Bark", { r = { 0, -30, 0 }, n = "Log" })
local fire = B(m, { 1.2, 1.6, 1.2 }, { 0, 1.3, 0 }, "Ember", { c = false, neon = true, n = "Fire" })
B(m, { 0.7, 1.2, 0.7 }, { 0.1, 2.4, 0.1 }, "Gold", { c = false, neon = true, n = "Fire", r = { 0, 45, 0 } })
local pl = Instance.new("PointLight")
pl.Color, pl.Range, pl.Brightness = Color3.fromHex("FFB060"), 14, 1.5
pl.Parent = fire
for _, a in { 150, 230, 310 } do
	local r = math.rad(a)
	local cx, cz = 4.6 * math.cos(r), 4.6 * math.sin(r)
	B(m, { 4, 1, 1 }, { cx, 0.5, cz }, "Bark", { r = { 0, -(a + 90), 0 }, n = "Bench" })
end
K.place(m, K.lobbyShelf(), Vector3.new(345, 8, 985))
local n = 0
for _, d in workspace.A01_AssetKit.Lobby:GetDescendants() do if d:IsA("BasePart") then n += 1 end end
return ("services ok : lobby %d Parts, %d Models"):format(n, #workspace.A01_AssetKit.Lobby:GetChildren())
