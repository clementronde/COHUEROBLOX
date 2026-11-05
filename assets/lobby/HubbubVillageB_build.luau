--!nocheck
-- COHUE — lobby « Hubbub Village », piste B (tout en tenons, formes naturelles) : le DÉCOR en Parts.
-- A01, 5 nov. 2026. Exécuté À L'ÉDITION par le MCP de Studio, section par section (« -- @section »).
-- Jamais chargé par le jeu : le résultat est un Model posé dans la place COHUE, enregistré par Ctrl+S.
-- Les tenons sont posés ensuite par Clément avec le plugin Resurface.
--
-- Même plan et mêmes tirages que la maquette Blender (assets/voxel/lobby.py, studs.py) : hnoise, vnoise
-- et le hachage de studs.py sont portés à l'identique. Seul le dessous de l'île est simplifié (couches
-- en escalier, pour garder peu de Parts).
-- Repère : plan en coordonnées « Blender » (x, y, z en studs ; arrivée au sud +y, portail au nord −y).
-- En Roblox : X = −x, Y = z, Z = y, autour du centre A.C.

-- @header
local A = {}
shared.A01B = A
A.C = Vector3.new(0, 16, 1100)
A.HX, A.HY = 56, 50
A.PAL = {
	["Leaf.l"] = "81D17C", Leaf = "3DBE4A", ["Leaf.d"] = "368545", Bark = "6E4227", ["Leather.l"] = "CF9F71",
	Leather = "B5713A", ["Leather.d"] = "84533B", Cream = "FFE8B8", ["Cream.d"] = "B4A18D", Stone = "9C9488",
	["Stone.l"] = "BFB6A4", Tomato = "E63946", Ember = "FF7A1A", ["Ember.d"] = "B45926", ["Gold.d"] = "B48826",
}
A.ROCK = { "Leather.l", "Cream.d", "Leather.l", "Stone.l" }   -- roche chaude, sable et rose
A.PLAZA = { 0, 2, 10 }
A.COURT = { 0, -19, 28, 8 }
A.POND = { 34, -11, 6.5, 5 }
A.STATIONS = { { -17, 27 }, { 18, 22 }, { -17, 10 }, { 17, 37 }, { -13, 42 }, { -37, 2 }, { 35, 4 }, { -34, -27 }, { 34, -27 }, { 16, -8 } }
A.KEEP = {}
for _, s in A.STATIONS do table.insert(A.KEEP, { s[1], s[2], 9 }) end
table.insert(A.KEEP, { 0, 44, 10 })
A.PATHS = {
	{ -9, 2, -26, 2, 2.5 }, { 9, 3, 29, 4, 2.5 }, { -7, -5, -28, -23, 2.5 }, { 7, -5, 28, -23, 2.5 },
	{ -3, 27, -11, 27, 2 }, { 3, 22, 11, 22, 2 }, { -4, 11, -12, 10, 2 }, { 7, -2, 14, -6, 2 },
}
A.PATCHES = { { -17, 27, 6.5, "Leather" }, { 18, 22, 6.5, "Leaf.d" }, { 16, -8, 5, "Leather" }, { 34, -27, 5, "Leather" }, { -34, -27, 8, "Stone.l" }, { -13, 42, 6, "Gold.d" } }

local band, bxor, rshift, lshift = bit32.band, bit32.bxor, bit32.rshift, bit32.lshift
local M32 = 0xFFFFFFFF
local function mul32(a, b)
	a, b = band(a, M32), band(b, M32)
	local ah, al = rshift(a, 16), band(a, 0xFFFF)
	local bh, bl = rshift(b, 16), band(b, 0xFFFF)
	return band(al * bl + lshift(band(ah * bl + al * bh, 0xFFFF), 16), M32)
end
local function trunc(v) return v >= 0 and math.floor(v) or math.ceil(v) end
A.trunc = trunc

function A.h(x, y, s)      -- hnoise de lobby.py
	local n = band(mul32(x, 374761393) + mul32(y, 668265263) + mul32(s, 1442695041), M32)
	n = mul32(bxor(n, rshift(n, 13)), 1274126177)
	return band(bxor(n, rshift(n, 16)), 0xFFFF) / 65535
end
function A.v(x, y, cell, s) -- vnoise de lobby.py
	local gx, gy = x / cell, y / cell
	local x0, y0 = math.floor(gx), math.floor(gy)
	local tx, ty = gx - x0, gy - y0
	tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
	local a, b, c, d = A.h(x0, y0, s), A.h(x0 + 1, y0, s), A.h(x0, y0 + 1, s), A.h(x0 + 1, y0 + 1, s)
	return a + (b - a) * tx + (c - a) * ty + (a - b - c + d) * tx * ty
end
function A.sh(...)          -- _h de studs.py
	local n = 2166136261
	for _, v in { ... } do
		n = mul32(bxor(n, band(trunc(v * 1000), M32)), 16777619)
	end
	n = bxor(n, rshift(n, 15))
	return band(n, 0xFFFF) / 65535
end
function A.ss(a, b, x) local t = math.clamp((x - a) / (b - a), 0, 1) return t * t * (3 - 2 * t) end
function A.rho(px, py) return ((math.abs(px) / A.HX) ^ 4 + (math.abs(py) / A.HY) ^ 4) ^ 0.25 end
function A.se(th)
	local c, s = math.cos(th), math.sin(th)
	return A.HX * math.sign(c) * math.abs(c) ^ 0.5, A.HY * math.sign(s) * math.abs(s) ^ 0.5
end
function A.seg(px, py, ax, ay, bx, by)
	local dx, dy = bx - ax, by - ay
	local t = math.clamp(((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy), 0, 1)
	return math.sqrt((px - ax - t * dx) ^ 2 + (py - ay - t * dy) ^ 2)
end
function A.mainx(py) return 2.5 * math.sin((py - 10) / 8) end
function A.flat(px, py)
	local m = 0
	for _, k in A.KEEP do m = math.max(m, 1 - A.ss(k[3], k[3] + 6, math.sqrt((px - k[1]) ^ 2 + (py - k[2]) ^ 2))) end
	if py >= 8 and py <= 48 then m = math.max(m, 1 - A.ss(5, 9, math.abs(px - A.mainx(py)))) end
	for _, p in A.PATHS do m = math.max(m, 1 - A.ss(p[5], p[5] + 4, A.seg(px, py, p[1], p[2], p[3], p[4]))) end
	m = math.max(m, 1 - A.ss(A.PLAZA[3], A.PLAZA[3] + 5, math.sqrt((px - A.PLAZA[1]) ^ 2 + (py - A.PLAZA[2]) ^ 2)))
	local c = A.COURT
	m = math.max(m, 1 - A.ss(1.0, 1.4, math.sqrt(((px - c[1]) / c[3]) ^ 2 + ((py - c[2]) / c[4]) ^ 2)))
	return m
end
function A.height(px, py)
	local r = A.rho(px, py)
	local hills = 5 * A.ss(0.55, 0.92, r) * (0.3 + 0.7 * A.v(px, py, 15, 2))
	local roll = 0.7 * (A.v(px, py, 7, 3) - 0.5)
	return (hills + roll) * (1 - A.flat(px, py))
end
function A.round(v) return math.floor(v + 0.5) end
function A.dirt(px, py)
	local wob = (A.v(px, py, 2.5, 26) - 0.5) * 1.6
	local w = 0
	if py >= 8 and py <= 48 then w = math.max(w, 1 - A.ss(3.6, 5.2, math.abs(px - A.mainx(py)) + wob)) end
	for _, p in A.PATHS do w = math.max(w, 1 - A.ss(p[5] - 1.2, p[5] + 0.4, A.seg(px, py, p[1], p[2], p[3], p[4]) + wob)) end
	local cl = 1 - A.ss(A.PLAZA[3] - 1.5, A.PLAZA[3] + 0.5, math.sqrt((px - A.PLAZA[1]) ^ 2 + (py - A.PLAZA[2]) ^ 2) + wob)
	local c = A.COURT
	cl = math.max(cl, 1 - A.ss(0.85, 1.0, math.sqrt(((px - c[1]) / c[3]) ^ 2 + ((py - c[2]) / c[4]) ^ 2) + wob / 20))
	for _, p in A.PATCHES do
		if string.sub(p[4], 1, 4) ~= "Leaf" then
			cl = math.max(cl, 1 - A.ss(p[3] - 1.5, p[3] + 0.5, math.sqrt((px - p[1]) ^ 2 + (py - p[2]) ^ 2) + wob))
		end
	end
	return w, cl
end
function A.inPond(px, py)
	local p = A.POND
	return ((px - p[1]) / p[3]) ^ 2 + ((py - p[2]) / p[4]) ^ 2 <= 1
end

-- Construction ----------------------------------------------------------------------------------
function A.root()
	local m = workspace:FindFirstChild("HubbubVillageB")
	if not m then
		m = Instance.new("Model")
		m.Name = "HubbubVillageB"
		m:SetAttribute("Note", "Lobby piste B (tout en tenons), décor en Parts posé à l'édition par A01 le 5 nov. 2026. Tenons : plugin Resurface. Aucun script.")
		m.Parent = workspace
	end
	return m
end
function A.zone(name)
	local root = A.root()
	local z = root:FindFirstChild(name)
	if z then z:Destroy() end
	z = Instance.new("Folder")
	z.Name = name
	return z, root
end
function A.color(key, j)
	local c = Color3.fromHex(A.PAL[key])
	j = j or 1
	return Color3.new(math.min(1, c.R * j), math.min(1, c.G * j), math.min(1, c.B * j))
end
local function newPart(parent, size, cf, color, collide)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = collide ~= false
	p.CanTouch = false
	p.Parent = parent
	return p
end
-- Boîte alignée, bornes en studs dans le repère du plan : [x0, x1) × [y0, y1) × [z0, z1)
function A.box(parent, x0, x1, y0, y1, z0, z1, key, collide, j)
	local c = A.C + Vector3.new(-(x0 + x1) / 2, (z0 + z1) / 2, (y0 + y1) / 2)
	return newPart(parent, Vector3.new(x1 - x0, z1 - z0, y1 - y0), CFrame.new(c), A.color(key, j), collide)
end
-- Bloc tourné comme studs.block : centre et taille dans le repère du plan, lacet (rad), inclinaisons (degrés)
local function rot(v, tx, ty, tz)          -- X puis Y puis Z (Euler XYZ de Blender)
	local x, y, z = v.X, v.Y, v.Z
	local c, s = math.cos(tx), math.sin(tx)
	y, z = y * c - z * s, y * s + z * c
	c, s = math.cos(ty), math.sin(ty)
	x, z = x * c + z * s, -x * s + z * c
	c, s = math.cos(tz), math.sin(tz)
	x, y = x * c - y * s, x * s + y * c
	return Vector3.new(x, y, z)
end
local function P(v) return Vector3.new(-v.X, v.Z, v.Y) end
function A.block(parent, cx, cy, cz, sx, sy, sz, key, yaw, tiltX, tiltY, collide)
	yaw, tiltX, tiltY = yaw or 0, math.rad(tiltX or 0), math.rad(tiltY or 0)
	local j = 0.96 + 0.08 * A.sh(cx, cy, cz)
	local vx = P(rot(Vector3.new(1, 0, 0), tiltX, tiltY, yaw))
	local vy = P(rot(Vector3.new(0, 0, 1), tiltX, tiltY, yaw))
	local cf = CFrame.fromMatrix(A.C + Vector3.new(-cx, cz, cy), vx, vy)
	return newPart(parent, Vector3.new(sx, sz, sy), cf, A.color(key, j), collide)
end
-- Fusion gloutonne 2D : cells[x][y] = clé ; renvoie des rectangles {x0, y0, dx, dy, clé}
function A.rects(cells, xmin, xmax, ymin, ymax)
	local used, out = {}, {}
	local function get(x, y) local col = cells[x] return col and col[y] end
	for y = ymin, ymax do
		for x = xmin, xmax do
			local k = get(x, y)
			if k and not (used[x] and used[x][y]) then
				local dx = 1
				while get(x + dx, y) == k and not (used[x + dx] and used[x + dx][y]) do dx += 1 end
				local dy = 1
				while true do
					local ok = true
					for i = 0, dx - 1 do
						if get(x + i, y + dy) ~= k or (used[x + i] and used[x + i][y + dy]) then ok = false break end
					end
					if not ok then break end
					dy += 1
				end
				for i = 0, dx - 1 do
					used[x + i] = used[x + i] or {}
					for jj = 0, dy - 1 do used[x + i][y + jj] = true end
				end
				table.insert(out, { x, y, dx, dy, k })
			end
		end
	end
	return out
end
-- Arbres et props (studs.py)
function A.pine(parent, x, y, z, height, seed)
	local m = Instance.new("Model")
	m.Name = "Pine"
	local th = height * 0.22
	A.block(m, x, y, z + th / 2, 1, 1, th, "Bark")
	for i = 0, 3 do
		local w = height * (0.42 - 0.08 * i)
		local hz = z + th + i * height * 0.17 + height * 0.06
		A.block(m, x, y, hz, w, w, height * 0.13, (i % 2 == 0) and "Leaf.d" or "Leaf", A.sh(seed, i, 1) * math.pi,
			(A.sh(seed, i, 2) - 0.5) * 16, (A.sh(seed, i, 3) - 0.5) * 16, false)
	end
	A.block(m, x, y, z + th + 4 * height * 0.17 + height * 0.05, height * 0.1, height * 0.1, height * 0.12, "Leaf", 0, 0, 0, false)
	m.Parent = parent
end
function A.tree(parent, x, y, z, height, seed, autumn)
	local m = Instance.new("Model")
	m.Name = autumn and "AutumnTree" or "Tree"
	local th = height * 0.5
	A.block(m, x, y, z + th / 2, 1.2, 1.2, th, "Bark")
	for k = 0, 1 do
		local a = A.sh(seed, k, 4) * math.pi * 2
		A.block(m, x + 0.9 * math.cos(a), y + 0.9 * math.sin(a), z + th * (0.75 + 0.15 * k), 0.6, 0.6, 2.2, "Bark", a, 0, 35, false)
	end
	local cols = autumn and { "Ember.d", "Ember", "Gold.d" } or { "Leaf.d", "Leaf", "Leaf.l" }
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2 + seed
		local d = (i == 0) and 0 or height * 0.2
		local s = height * (0.36 - 0.05 * ((i > 0) and 1 or 0)) * (0.85 + 0.3 * A.sh(seed, i, 5))
		local cz = z + th + height * (0.18 + 0.12 * A.sh(seed, i, 6)) + ((i == 0) and height * 0.12 or 0)
		A.block(m, x + d * math.cos(a), y + d * math.sin(a), cz, s, s, s * 0.8, cols[i % 3 + 1], A.sh(seed, i, 7) * math.pi,
			(A.sh(seed, i, 8) - 0.5) * 20, (A.sh(seed, i, 9) - 0.5) * 20, false)
	end
	m.Parent = parent
end
function A.bush(parent, x, y, z, size, seed)
	local m = Instance.new("Model")
	m.Name = "Bush"
	for i = 0, 2 do
		local a = i / 3 * math.pi * 2 + seed
		local s = size * (0.6 + 0.3 * A.sh(seed, i, 10))
		A.block(m, x + size * 0.35 * math.cos(a), y + size * 0.35 * math.sin(a), z + s * 0.35, s, s, s * 0.7,
			(i % 2 == 1) and "Leaf" or "Leaf.d", A.sh(seed, i, 11) * math.pi, 0, 0, false)
	end
	m.Parent = parent
end
function A.rock(parent, x, y, z, size, seed, key)
	A.block(parent, x, y, z + size * 0.25, size, size * 0.8, size * 0.7, key, A.sh(seed, 1, 12) * math.pi,
		(A.sh(seed, 2, 13) - 0.5) * 18, (A.sh(seed, 3, 14) - 0.5) * 18).Name = "Rock"
end
function A.slab(parent, x, y, z, size, seed, key)
	A.block(parent, x, y, z, size, size * (0.8 + 0.3 * A.sh(seed, 4, 15)), 0.5, key, A.sh(seed, 5, 16) * math.pi / 2,
		(A.sh(seed, 6, 17) - 0.5) * 6, 0).Name = "Slab"
end
function A.mushroom(parent, x, y, z, seed)
	local m = Instance.new("Model")
	m.Name = "Mushroom"
	A.block(m, x, y, z + 0.6, 0.8, 0.8, 1.2, "Cream")
	A.block(m, x, y, z + 1.5, 2.2, 2.2, 0.9, "Tomato", A.sh(seed, 6, 18) * math.pi)
	m.Parent = parent
end
return "header ok"

-- @ground
-- Île : couche du dessus (herbe, chemins, clairières, fond de mare) en terrasses d'un stud, terre
-- dessous jusqu'à z = −3, puis 5 couches de roche en escalier qui se resserrent sous l'île.
local A = shared.A01B
local zone, root = A.zone("Ground")
local tops, soil = {}, {}
local layers = { {}, {}, {}, {}, {} }
local X0, X1, Y0, Y1 = -A.HX - 2, A.HX + 1, -A.HY - 2, A.HY + 1
for x = X0, X1 do
	tops[x], soil[x] = {}, {}
	for k = 1, 5 do layers[k][x] = {} end
	for y = Y0, Y1 do
		local px, py = x + 0.5, y + 0.5
		local r = A.rho(px, py)
		if r <= 1 - 0.03 * A.h(x // 2, y // 2, 95) then
			local h = A.round(A.height(px, py))
			local w, cl = A.dirt(px, py)
			local top
			if A.inPond(px, py) then
				h, top = -2, "Leather.d"
			elseif w > 0.5 then
				top = "Leather.l"
			elseif cl > 0.5 then
				top = "Leather"
			else
				top = (A.v(px, py, 10, 96) > 0.55) and "Leaf.l" or "Leaf"
			end
			tops[x][y] = h .. "|" .. top
			if h - 1 > -3 then
				soil[x][y] = h .. "|" .. ((A.h(x // 5, y // 5, 120) > 0.5) and "Leather.l" or "Cream.d")
			end
			for k = 1, 5 do
				if r < 1 - 0.13 * k - 0.04 * A.h(x // 3, y // 3, 140 + k) then
					layers[k][x][y] = A.ROCK[math.floor(A.h(x // 7, y // 7, 130 + k) * 4) % 4 + 1]
				end
			end
		end
	end
end
local n = 0
local function flush()
	n += 1
	if n % 250 == 0 then task.wait() end
end
for _, r in A.rects(tops, X0, X1, Y0, Y1) do
	local h, key = string.match(r[5], "^(-?%d+)|(.+)$")
	h = tonumber(h)
	A.box(zone, r[1], r[1] + r[3], r[2], r[2] + r[4], h - 1, h, key).Name = "Top"
	flush()
end
for _, r in A.rects(soil, X0, X1, Y0, Y1) do
	local h, key = string.match(r[5], "^(-?%d+)|(.+)$")
	h = tonumber(h)
	A.box(zone, r[1], r[1] + r[3], r[2], r[2] + r[4], -3, h - 1, key).Name = "Soil"
	flush()
end
for k = 1, 5 do
	for _, r in A.rects(layers[k], X0, X1, Y0, Y1) do
		A.box(zone, r[1], r[1] + r[3], r[2], r[2] + r[4], -3 - 3 * k, -3 - 3 * (k - 1), r[5]).Name = "Rock" .. k
		flush()
	end
end
zone.Parent = root
return "ground parts = " .. #zone:GetChildren()

-- @cliff
-- Falaise en gros blocs décalés derrière la tête, coiffés d'herbe par endroits, blocs qui débordent.
local A = shared.A01B
local zone, root = A.zone("Cliff")
local i = 0
for deg = 194, 347, 5 do
	local th = math.rad(deg)
	local ex, ey = A.se(th)
	local cx, cy = A.trunc(ex * 0.9), A.trunc(ey * 0.9)
	local centre = 1 - math.abs(math.cos(th))
	local sx = 3 + A.trunc(4 * A.h(i, 1, 97))
	local sy = 3 + A.trunc(3 * A.h(i, 2, 98))
	local hz = 5 + A.trunc(12 * centre + 5 * A.h(i, 3, 99))
	A.box(zone, cx - sx, cx + sx, cy - sy, cy + sy, 0, hz, A.ROCK[i % 4 + 1]).Name = "Block"
	if A.h(i, 4, 100) > 0.35 then
		A.box(zone, cx - sx, cx + sx, cy - sy, cy + sy, hz, hz + 1, "Leaf.l").Name = "GrassCap"
	end
	for k = 0, 2 do
		local bw = 2 + A.trunc(3 * A.h(i, k, 102))
		local bh = 2 + A.trunc(4 * A.h(k, i, 103))
		local bz = A.trunc((hz - bh) * A.h(i, k, 104))
		local bxo = cx - sx + A.trunc((2 * sx - bw) * A.h(k, i, 105))
		local out = 1 + A.trunc(2 * A.h(i, k, 106))
		local y0 = (cy < 0) and (cy + sy) or (cy - sy - out)
		A.box(zone, bxo, bxo + bw, y0, y0 + out, bz, bz + bh, A.ROCK[(i + k + 1) % 4 + 1]).Name = "Ledge"
	end
	i += 1
end
zone.Parent = root
return "cliff parts = " .. #zone:GetChildren()

-- @forest
-- Arbres placés à la main (plan v1) et forêt en lisière : dense sur les bords, rien sur les passages.
local A = shared.A01B
local zone, root = A.zone("Forest")
local TREES = {
	{ "round", -45, 36, 9 }, { "round", -38, 45, 6 }, { "pine", -51, 24, 30 }, { "bush", -41, 29, 4.0 },
	{ "pine", 44, 40, 34 }, { "round", 37, 45, 7 }, { "bush", 49, 31, 3.5 }, { "round", 49, 15, 9 },
	{ "rock", -50, -12, 4.0 }, { "bush", -48, -17, 3.0 }, { "pine", 51, -6, 26 }, { "rock", 47, -14, 3.5 },
	{ "pine", -46, -42, 28 }, { "pine", -37, -46, 24 }, { "pine", 44, -41, 30 }, { "pine", 35, -47, 22 },
	{ "bush", -45, -23, 3.5 }, { "bush", 45, -22, 3.0 }, { "rock", 41, -35, 3.0 }, { "rock", -24, -38, 3.0 },
	{ "round", -10, 18, 7 }, { "bush", 9, 30, 3.0 }, { "round", -25, 41, 8 }, { "round", 27, 44, 6 },
	{ "rock", -28, 36, 3.0 }, { "rock", 28, 28, 2.5 }, { "bush", -27, 18, 3.0 }, { "bush", 27, -13, 3.0 },
	{ "pine", -52, -28, 22 }, { "round", 52, -26, 7 },
}
local ROCK3 = { "Leather.l", "Cream.d", "Leather.l" }
for _, t in TREES do
	local kind, x, y, p = t[1], t[2], t[3], t[4]
	local z = A.round(A.height(x, y))
	local seed = math.abs(x * 7 + y * 13)
	if kind == "round" then
		A.tree(zone, x, y, z, p * 1.7, seed, seed % 5 == 0)
	elseif kind == "pine" then
		A.pine(zone, x, y, z, p * 0.6, seed)
	elseif kind == "bush" then
		A.bush(zone, x, y, z, p * 0.8, seed)
	else
		A.rock(zone, x, y, z, p, seed, ROCK3[seed % 3 + 1])
	end
end
task.wait()
local n = 0
for _, ringR in { 0.86, 0.95 } do
	for deg = 0, 355, 5 do
		local th = math.rad(deg + ((ringR > 0.9) and 2.5 or 0))
		local ex, ey = A.se(th)
		local x = ex * ringR + (A.h(deg, 3, 83) - 0.5) * 3
		local y = ey * ringR + (A.h(deg, 4, 84) - 0.5) * 3
		local skip = A.flat(x, y) > 0.02 or (math.abs(x) < 30 and y < -22) or (math.abs(x) < 14 and y > 28) or A.inPond(x, y)
		if not skip then
			for _, k in A.KEEP do
				if math.sqrt((x - k[1]) ^ 2 + (y - k[2]) ^ 2) < k[3] + 6 then skip = true break end
			end
		end
		if not skip then
			local pick = A.h(deg, A.trunc(ringR * 100), 85)
			local z = A.round(A.height(x, y))
			n += 1
			if pick < 0.6 then
				A.pine(zone, x, y, z, 12 + 8 * A.h(deg, 6, 87), deg + n)
			elseif pick < 0.85 then
				A.tree(zone, x, y, z, 10 + 6 * A.h(deg, 5, 86), deg + n, pick < 0.66)
			elseif pick < 0.93 then
				A.bush(zone, x, y, z, 2.5 + A.h(deg, 7, 88), deg)
			else
				A.mushroom(zone, x, y, z, deg)
			end
			if n % 20 == 0 then task.wait() end
		end
	end
end
zone.Parent = root
return ("forest models = %d"):format(#zone:GetChildren())

-- @props
-- Mare (eau du Terrain), pierres de gué, dalles de la place, îlots flottants.
local A = shared.A01B
local zone, root = A.zone("Props")
local p = A.POND
workspace.Terrain:FillCylinder(CFrame.new(A.C + Vector3.new(-p[1], -1.3, p[2])), 1.4, 5.6, Enum.Material.Water)
for i = 0, 5 do
	local t = (i + 0.5) / 6
	A.slab(zone, p[1] - p[3] + 2 * p[3] * t, p[2] + math.sin(t * 3) * 1.5, -0.5, 1.8, i, A.ROCK[i % 3 + 1])
end
for i = 0, 9 do
	local a = i / 10 * math.pi * 2 + 0.3
	local r = 5 + 3.5 * A.h(i, 8, 89)
	A.slab(zone, A.PLAZA[1] + r * math.cos(a), A.PLAZA[2] + r * math.sin(a), 0.05, 1.6, i, "Stone.l")
end
local ISLETS = { { -96, -58, -8, 1.6 }, { 94, 72, -16, 1.4 }, { 118, -24, 2, 1.2 }, { -110, 40, -20, 1.3 } }
for i, s in ISLETS do
	local k = i - 1
	local yaw = A.h(k, 1, 101) * 3
	local m = Instance.new("Model")
	m.Name = "Islet"
	A.block(m, s[1], s[2], s[3], 8 * s[4], 7 * s[4], 1, "Leaf.l", yaw, 0, 0, false)
	A.block(m, s[1], s[2], s[3] - 3 * s[4], 6 * s[4], 5 * s[4], 5 * s[4], A.ROCK[k % 3 + 1], yaw, 0, 0, false)
	A.pine(m, s[1], s[2], s[3] + 0.5, 7 * s[4], k)
	m.Parent = zone
end
zone.Parent = root
return ("props = %d"):format(#zone:GetChildren())
