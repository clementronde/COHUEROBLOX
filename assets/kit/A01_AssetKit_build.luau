--!nocheck
-- COHUE — kit d'assets « tout en tenons » (A01, 5 nov. 2026), d'après les références de Clément
-- (canyon en tenons : sapins en plaques inclinées, falaises en gros blocs, dalles, pont de bois…).
-- Exécuté À L'ÉDITION par le MCP de Studio, section par section (« -- @section »). Jamais chargé par le
-- jeu. Résultat : Workspace.A01_AssetKit, une vitrine de Models que Clément déplace / copie dans sa map.
-- Chaque Model a son pivot au centre de sa base (il se pose au sol). Tenons : surfaces Studs sur toutes
-- les faces (Clément peut repasser Resurface). Couleurs : palette COHUE 16.

-- @header
local K = {}
shared.A01Kit = K
K.PAL = {
	["Leaf.l"] = "81D17C", Leaf = "3DBE4A", ["Leaf.d"] = "368545", Bark = "6E4227", ["Bark.l"] = "9E7F6B",
	["Leather.l"] = "CF9F71", Leather = "B5713A", ["Leather.d"] = "84533B", Cream = "FFE8B8", ["Cream.d"] = "B4A18D",
	Stone = "9C9488", ["Stone.l"] = "BFB6A4", ["Stone.d"] = "6F6566", Steel = "8EA6C2", ["Steel.d"] = "6B7693",
	["Steel.l"] = "B6C2CF", Tomato = "E63946", Ember = "FF7A1A", ["Ember.d"] = "B45926", ["Gold.d"] = "B48826",
	Gold = "FFC21A", ["Grape.l"] = "B08BEA", ["Tomato.l"] = "EE7A79",
}
K.ROCK = { "Cream.d", "Leather.l", "Stone.l", "Cream.d" }
local FACES = { "TopSurface", "BottomSurface", "FrontSurface", "BackSurface", "LeftSurface", "RightSurface" }

function K.color(key, j)
	local c = Color3.fromHex(K.PAL[key])
	j = j or 1
	return Color3.new(math.clamp(c.R * j, 0, 1), math.clamp(c.G * j, 0, 1), math.clamp(c.B * j, 0, 1))
end
-- Une Part du kit : plastique à tenons, ancrée ; key = couleur de la palette
function K.part(model, size, cf, key, collide, opts)
	opts = opts or {}
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = K.color(key, opts.j)
	p.Material = opts.neon and Enum.Material.Neon or Enum.Material.SmoothPlastic
	for _, f in FACES do p[f] = opts.neon and Enum.SurfaceType.Smooth or Enum.SurfaceType.Studs end
	p.CanCollide = collide ~= false
	p.CanTouch = false
	p.CastShadow = not opts.neon
	p.Name = opts.name or "Part"
	p.Parent = model
	return p
end
function K.model(name, category)
	local m = Instance.new("Model")
	m.Name = name
	m:SetAttribute("A01Kit", category)
	return m
end
-- Pose le Model : pivot au centre de la base (origine locale), puis rangé dans la vitrine
function K.place(m, parent, pos, note)
	m.WorldPivot = CFrame.new()
	if note then m:SetAttribute("Note", note) end
	m:PivotTo(CFrame.new(pos))
	m.Parent = parent
	return m
end
local function jit(rng) return 0.95 + 0.1 * rng:NextNumber() end
K.jit = jit

-- Sapin en plaques empilées, chacune tournée et inclinée (images 1-2)
function K.pine(name, o)
	local m = K.model(name, "Arbres")
	local rng = Random.new(o.seed)
	K.part(m, Vector3.new(o.trunkW, o.trunkH, o.trunkW), CFrame.new(0, o.trunkH / 2, 0), "Bark", true, { name = "Trunk", j = jit(rng) })
	local y = o.start
	for i = 0, o.tiers - 1 do
		local t = (o.tiers > 1) and i / (o.tiers - 1) or 0
		local w = o.w0 + (o.w1 - o.w0) * t
		local cf = CFrame.new(rng:NextNumber(-0.3, 0.3), y, rng:NextNumber(-0.3, 0.3))
			* CFrame.Angles(math.rad(rng:NextNumber(-o.tilt, o.tilt)), rng:NextNumber(0, math.pi / 2), math.rad(rng:NextNumber(-o.tilt, o.tilt)))
		K.part(m, Vector3.new(w, o.tierH, w), cf, (i % 2 == 0) and "Leaf.d" or "Leaf", false, { name = "Tier" .. i, j = jit(rng) })
		y += o.gap
	end
	K.part(m, Vector3.new(o.w1 * 0.5, o.tierH, o.w1 * 0.5), CFrame.new(0, y - o.gap * 0.35, 0) * CFrame.Angles(0, rng:NextNumber(0, 1.5), 0), "Leaf", false, { name = "Tip" })
	return m
end
-- Feuillu : tronc, deux branches, feuillage en cubes tournés
function K.tree(name, o)
	local m = K.model(name, "Arbres")
	local rng = Random.new(o.seed)
	local th = o.h * 0.5
	K.part(m, Vector3.new(o.trunkW, th, o.trunkW), CFrame.new(0, th / 2, 0), "Bark", true, { name = "Trunk" })
	for k = 0, 1 do
		local a = rng:NextNumber(0, math.pi * 2)
		K.part(m, Vector3.new(0.7, o.h * 0.22, 0.7), CFrame.new(math.cos(a) * 0.9, th * (0.75 + 0.12 * k), math.sin(a) * 0.9) * CFrame.Angles(0, -a, math.rad(35)), "Bark", false, { name = "Branch" })
	end
	local cols = o.autumn and { "Ember.d", "Ember", "Gold.d" } or { "Leaf.d", "Leaf", "Leaf.l" }
	for i = 0, o.blobs - 1 do
		local a = i / o.blobs * math.pi * 2 + rng:NextNumber(0, 0.6)
		local d = (i == 0) and 0 or o.h * 0.22
		local s = o.h * ((i == 0) and 0.4 or 0.32) * (0.85 + 0.3 * rng:NextNumber())
		local cy = th + o.h * (0.15 + 0.12 * rng:NextNumber()) + ((i == 0) and o.h * 0.14 or 0)
		K.part(m, Vector3.new(s, s * 0.8, s), CFrame.new(math.cos(a) * d, cy, math.sin(a) * d)
			* CFrame.Angles(math.rad(rng:NextNumber(-12, 12)), rng:NextNumber(0, math.pi), math.rad(rng:NextNumber(-12, 12))),
			cols[i % 3 + 1], false, { name = "Leaves", j = jit(rng) })
	end
	return m
end
-- Buisson de plaques basses
function K.bush(name, o)
	local m = K.model(name, "Arbres")
	local rng = Random.new(o.seed)
	for i = 0, o.n - 1 do
		local w = o.w * (1 - 0.22 * i)
		K.part(m, Vector3.new(w, o.t, w), CFrame.new(rng:NextNumber(-0.4, 0.4), o.t / 2 + i * o.t * 0.8, rng:NextNumber(-0.4, 0.4))
			* CFrame.Angles(math.rad(rng:NextNumber(-15, 15)), rng:NextNumber(0, math.pi / 2), math.rad(rng:NextNumber(-15, 15))),
			(i % 2 == 0) and "Leaf.d" or "Leaf", false, { name = "Leaves", j = jit(rng) })
	end
	return m
end
-- Rocher : 2 à 5 blocs décalés et un peu inclinés
function K.rock(name, o)
	local m = K.model(name, "Roche")
	local rng = Random.new(o.seed)
	for i = 0, o.n - 1 do
		local s = o.s * (1 - 0.18 * i) * (0.85 + 0.3 * rng:NextNumber())
		local sz = Vector3.new(s, s * (0.6 + 0.4 * rng:NextNumber()), s * (0.7 + 0.3 * rng:NextNumber()))
		local off = (i == 0) and Vector3.zero or Vector3.new(rng:NextNumber(-1, 1) * o.s * 0.45, 0, rng:NextNumber(-1, 1) * o.s * 0.45)
		K.part(m, sz, CFrame.new(off + Vector3.new(0, sz.Y / 2 - 0.2 + ((i > 0 and i % 2 == 0) and sz.Y * 0.5 or 0), 0))
			* CFrame.Angles(math.rad(rng:NextNumber(-8, 8)), rng:NextNumber(0, math.pi / 2), math.rad(rng:NextNumber(-8, 8))),
			K.ROCK[(o.seed + i) % #K.ROCK + 1], true, { name = "Rock", j = jit(rng) })
	end
	return m
end
-- Mur de falaise : colonnes de blocs décalés, coiffées d'herbe qui déborde (images 1-2)
function K.cliff(name, o)
	local m = K.model(name, "Roche")
	local rng = Random.new(o.seed)
	local x = -o.w / 2
	local i = 0
	while x < o.w / 2 - 0.5 do
		local cw = math.min(rng:NextInteger(3, 6), o.w / 2 - x)
		local ch = o.h + rng:NextInteger(-3, 2)
		local front = rng:NextNumber(0, 1.5)
		local y = 0
		local k = 0
		while y < ch do
			local bh = math.min(rng:NextInteger(3, 6), ch - y)
			local dz = front + rng:NextNumber(-0.6, 0.6)
			local dx = rng:NextNumber(-0.4, 0.4)
			K.part(m, Vector3.new(cw + rng:NextNumber(0, 0.6), bh, o.d + dz), CFrame.new(x + cw / 2 + dx, y + bh / 2, -dz / 2),
				K.ROCK[(i + k) % #K.ROCK + 1], true, { name = "Block", j = jit(rng) })
			y += bh
			k += 1
		end
		-- herbe sur le dessus, qui déborde vers l'avant ; parfois une lèvre qui tombe
		K.part(m, Vector3.new(cw + 1, 1, o.d + front + 1), CFrame.new(x + cw / 2, ch + 0.5, -(front + 1) / 2 + 0.5), "Leaf.l", true, { name = "Grass", j = jit(rng) })
		if rng:NextNumber() > 0.45 then
			K.part(m, Vector3.new(cw * 0.8, 0.8, 1.6), CFrame.new(x + cw / 2, ch - 0.1, -o.d / 2 - front - 0.9) * CFrame.Angles(math.rad(-25), 0, 0), "Leaf", false, { name = "GrassLip" })
		end
		x += cw
		i += 1
	end
	return m
end
-- Dalle de gué / de chemin
function K.slab(name, o)
	local m = K.model(name, "Roche")
	K.part(m, Vector3.new(o.x, 1, o.z), CFrame.new(0, 0.5, 0) * CFrame.Angles(math.rad(o.tilt or 0), 0, 0), o.key or "Stone.l", true, { name = "Slab" })
	return m
end
-- Champignon rouge à pois
function K.mushroom(m, x, z, s, seed)
	local rng = Random.new(seed)
	K.part(m, Vector3.new(0.8 * s, 1.4 * s, 0.8 * s), CFrame.new(x, 0.7 * s, z), "Cream", false, { name = "Stem" })
	local cap = CFrame.new(x, 1.7 * s, z) * CFrame.Angles(0, rng:NextNumber(0, 1.5), math.rad(rng:NextNumber(-8, 8)))
	K.part(m, Vector3.new(2.6 * s, 1 * s, 2.6 * s), cap, "Tomato", false, { name = "Cap" })
	for _, d in { { -0.7, 0.55, -0.6 }, { 0.6, 0.55, 0.5 }, { 0.1, 0.55, 0.1 }, { 1.31, 0.1, -0.3 }, { -1.31, 0.05, 0.4 } } do
		local size = (math.abs(d[1]) > 1.2) and Vector3.new(0.1, 0.5 * s, 0.5 * s) or Vector3.new(0.5 * s, 0.1, 0.5 * s)
		K.part(m, size, cap * CFrame.new(d[1] * s, d[2] * s, d[3] * s), "Cream", false, { name = "Spot" })
	end
end
return "kit header ok"

-- @nature
local K = shared.A01Kit
local kit = workspace:FindFirstChild("A01_AssetKit")
if kit then kit:Destroy() end
kit = Instance.new("Folder")
kit.Name = "A01_AssetKit"
kit:SetAttribute("Note", "Kit d'assets A01 (5 nov. 2026) : Models à déplacer ou copier dans la map. Pivot au centre de la base. Aucun script.")
local function shelf(name) local f = Instance.new("Folder") f.Name = name f.Parent = kit return f end
local trees, rocks = shelf("Arbres"), shelf("Roche")
local O = Vector3.new(220, 8, 720)        -- vitrine sur la dalle grise, à l'est du village v1
local x = 0
for _, spec in {
	{ "Pine_Small", { seed = 1, trunkH = 3, trunkW = 0.8, tiers = 4, w0 = 5, w1 = 1.6, tierH = 1.2, gap = 1.4, start = 1.8, tilt = 12 } },
	{ "Pine_Medium", { seed = 2, trunkH = 6, trunkW = 1, tiers = 5, w0 = 8, w1 = 2, tierH = 1.6, gap = 2, start = 3.2, tilt = 14 } },
	{ "Pine_Large", { seed = 3, trunkH = 9, trunkW = 1.4, tiers = 6, w0 = 11, w1 = 2.5, tierH = 2, gap = 2.6, start = 4.2, tilt = 14 } },
	{ "Pine_Tall", { seed = 4, trunkH = 18, trunkW = 1.2, tiers = 4, w0 = 6.5, w1 = 2, tierH = 1.6, gap = 2.1, start = 12.5, tilt = 10 } },
	{ "Pine_Wide", { seed = 5, trunkH = 2, trunkW = 1, tiers = 6, w0 = 10, w1 = 2.5, tierH = 1.5, gap = 1.3, start = 1, tilt = 20 } },
} do
	K.place(K.pine(spec[1], spec[2]), trees, O + Vector3.new(x, 0, 0))
	x += 22
end
K.place(K.tree("Tree_Round", { seed = 6, h = 14, trunkW = 1.4, blobs = 5 }), trees, O + Vector3.new(x, 0, 0)); x += 22
K.place(K.tree("Tree_Autumn", { seed = 7, h = 13, trunkW = 1.3, blobs = 5, autumn = true }), trees, O + Vector3.new(x, 0, 0)); x += 20
K.place(K.bush("Bush_Small", { seed = 8, n = 2, w = 3.5, t = 1.2 }), trees, O + Vector3.new(x, 0, 0)); x += 12
K.place(K.bush("Bush_Large", { seed = 9, n = 3, w = 5.5, t = 1.6 }), trees, O + Vector3.new(x, 0, 0))
-- Roche
x = 0
local R = O + Vector3.new(0, 0, 40)
K.place(K.rock("Rock_Small", { seed = 10, n = 2, s = 2.5 }), rocks, R + Vector3.new(x, 0, 0)); x += 12
K.place(K.rock("Rock_Medium", { seed = 11, n = 3, s = 4 }), rocks, R + Vector3.new(x, 0, 0)); x += 14
K.place(K.rock("Rock_Large", { seed = 12, n = 5, s = 6 }), rocks, R + Vector3.new(x, 0, 0)); x += 22
K.place(K.cliff("Cliff_Wall_Long", { seed = 13, w = 20, h = 14, d = 6 }), rocks, R + Vector3.new(x, 0, 0)); x += 30
K.place(K.cliff("Cliff_Wall_Short", { seed = 14, w = 12, h = 9, d = 5 }), rocks, R + Vector3.new(x, 0, 0)); x += 22
K.place(K.cliff("Cliff_Pillar", { seed = 15, w = 6, h = 18, d = 6 }), rocks, R + Vector3.new(x, 0, 0)); x += 16
for i, s in { { "Slab_Square", 4, 4, 0 }, { "Slab_Long", 5, 3, 3 }, { "Slab_Small", 3, 3, -4 } } do
	K.place(K.slab(s[1], { x = s[2], z = s[3], tilt = s[4], key = (i == 2) and "Cream.d" or "Stone.l" }), rocks, R + Vector3.new(x, 0, 0)); x += 9
end
kit.Parent = workspace
local n = 0
for _, d in kit:GetDescendants() do if d:IsA("BasePart") then n += 1 end end
return ("nature ok : %d Parts"):format(n)

-- @props
local K = shared.A01Kit
local kit = workspace.A01_AssetKit
local props = kit:FindFirstChild("Objets") or Instance.new("Folder")
props.Name = "Objets"
props:ClearAllChildren()
local walls = kit:FindFirstChild("Muraille") or Instance.new("Folder")
walls.Name = "Muraille"
walls:ClearAllChildren()
local O = Vector3.new(220, 8, 790)
local x = 0
-- Champignons
local m = K.model("Mushroom_Red", "Objets")
K.mushroom(m, 0, 0, 1, 1)
K.place(m, props, O + Vector3.new(x, 0, 0)); x += 8
m = K.model("Mushroom_Group", "Objets")
K.mushroom(m, 0, 0, 1.3, 2); K.mushroom(m, 2.4, 1.2, 0.8, 3); K.mushroom(m, -1.8, 1.6, 0.6, 4)
K.place(m, props, O + Vector3.new(x, 0, 0)); x += 12
-- Pont de bois (16 de long, 5 de large)
m = K.model("Bridge_Wood", "Objets")
local rng = Random.new(20)
for i = 0, 15 do
	K.part(m, Vector3.new(0.9, 0.5, 5), CFrame.new(-7.5 + i, 2.25, 0) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-2, 2))), "Leather", true, { name = "Plank", j = K.jit(rng) })
end
for _, zz in { -2, 2 } do
	K.part(m, Vector3.new(16, 0.8, 0.8), CFrame.new(0, 1.6, zz), "Bark", true, { name = "Beam" })
	K.part(m, Vector3.new(16, 0.5, 0.5), CFrame.new(0, 5, zz * 1.15), "Bark", false, { name = "Rail" })
	for _, xx in { -7.5, -2.5, 2.5, 7.5 } do
		K.part(m, Vector3.new(0.8, 5.4, 0.8), CFrame.new(xx, 2.7, zz * 1.15), "Bark", true, { name = "Post" })
	end
end
K.place(m, props, O + Vector3.new(x + 8, 0, 0)); x += 24
-- Clôture (8 de long)
m = K.model("Fence_Wood", "Objets")
for _, xx in { -3.75, 0, 3.75 } do K.part(m, Vector3.new(0.6, 3, 0.6), CFrame.new(xx, 1.5, 0), "Bark", true, { name = "Post" }) end
K.part(m, Vector3.new(8, 0.4, 0.3), CFrame.new(0, 1.2, 0), "Leather", true, { name = "Rail" })
K.part(m, Vector3.new(8, 0.4, 0.3), CFrame.new(0, 2.3, 0) * CFrame.Angles(0, 0, math.rad(2)), "Leather", true, { name = "Rail" })
K.place(m, props, O + Vector3.new(x, 0, 0)); x += 12
-- Lampadaire (lanterne Neon or)
m = K.model("Lamp_Post", "Objets")
K.part(m, Vector3.new(0.6, 7, 0.6), CFrame.new(0, 3.5, 0), "Bark", true, { name = "Post" })
K.part(m, Vector3.new(1.6, 0.4, 0.4), CFrame.new(0.6, 6.8, 0), "Bark", false, { name = "Arm" })
K.part(m, Vector3.new(1.1, 0.3, 1.1), CFrame.new(1.2, 6.45, 0), "Bark", false, { name = "Cap" })
K.part(m, Vector3.new(0.8, 1, 0.8), CFrame.new(1.2, 5.8, 0), "Gold", false, { name = "Light", neon = true })
local light = Instance.new("PointLight")
light.Color, light.Range, light.Brightness = Color3.fromHex("FFD58A"), 12, 1.2
light.Parent = m.Light
K.place(m, props, O + Vector3.new(x, 0, 0)); x += 8
-- Caisse, tonneau, bûches
m = K.model("Crate", "Objets")
K.part(m, Vector3.new(3, 3, 3), CFrame.new(0, 1.5, 0), "Leather", true, { name = "Box" })
for _, a in { 1, -1 } do
	K.part(m, Vector3.new(0.4, 3.9, 0.3), CFrame.new(0, 1.5, -1.55) * CFrame.Angles(0, 0, math.rad(45 * a)), "Bark", false, { name = "Brace" })
end
K.place(m, props, O + Vector3.new(x, 0, 0)); x += 7
m = K.model("Barrel", "Objets")
K.part(m, Vector3.new(2.4, 3.2, 1.6), CFrame.new(0, 1.6, 0), "Leather", true, { name = "Body" })
K.part(m, Vector3.new(1.6, 3.2, 2.4), CFrame.new(0, 1.6, 0), "Leather", true, { name = "Body" })
for _, yy in { 0.7, 2.5 } do
	K.part(m, Vector3.new(2.5, 0.35, 1.7), CFrame.new(0, yy, 0), "Bark", false, { name = "Hoop" })
	K.part(m, Vector3.new(1.7, 0.35, 2.5), CFrame.new(0, yy, 0), "Bark", false, { name = "Hoop" })
end
K.place(m, props, O + Vector3.new(x, 0, 0)); x += 7
m = K.model("Log_Pile", "Objets")
for i, p in { { -0.7, 0.6 }, { 0.7, 0.6 }, { 0, 1.75 } } do
	K.part(m, Vector3.new(6, 1.2, 1.2), CFrame.new(0, p[2], p[1]) * CFrame.Angles(0, math.rad((i - 2) * 4), 0), "Leather.d", true, { name = "Log" })
	K.part(m, Vector3.new(0.1, 0.8, 0.8), CFrame.new(3.03, p[2], p[1]) * CFrame.Angles(0, math.rad((i - 2) * 4), 0), "Leather.l", false, { name = "Rings" })
end
K.place(m, props, O + Vector3.new(x, 0, 0)); x += 10
m = K.model("Flower_Patch", "Objets")
rng = Random.new(21)
for i = 1, 7 do
	local px, pz = rng:NextNumber(-1.6, 1.6), rng:NextNumber(-1.6, 1.6)
	local h = rng:NextNumber(0.6, 1.3)
	K.part(m, Vector3.new(0.2, h, 0.2), CFrame.new(px, h / 2, pz), "Leaf.d", false, { name = "Stem" })
	K.part(m, Vector3.new(0.6, 0.4, 0.6), CFrame.new(px, h + 0.2, pz) * CFrame.Angles(0, rng:NextNumber(0, 1.5), 0), ({ "Cream", "Grape.l", "Tomato.l", "Gold" })[i % 4 + 1], false, { name = "Flower" })
end
K.place(m, props, O + Vector3.new(x, 0, 0))
-- Muraille de château (pierre bleu-gris)
x = 0
local W = O + Vector3.new(0, 0, 40)
m = K.model("Wall_Stone", "Muraille")
rng = Random.new(22)
for row = 0, 5 do
	local off = (row % 2 == 0) and 0 or 1.5
	local bx = -6 - off
	while bx < 6 do
		local w = math.min(3, 6 - bx)
		local x0 = math.max(bx, -6)
		local ww = bx + w - x0
		if ww > 0.2 then
			K.part(m, Vector3.new(ww, 1, 2), CFrame.new(x0 + ww / 2, row + 0.5, 0), (rng:NextNumber() > 0.5) and "Steel" or "Steel.d", true, { name = "Brick", j = K.jit(rng) })
		end
		bx += w
	end
end
K.part(m, Vector3.new(12.4, 0.6, 2.6), CFrame.new(0, 6.3, 0), "Steel.l", true, { name = "Cap" })
for _, xx in { -4.5, 0, 4.5 } do K.part(m, Vector3.new(2, 1.4, 2.4), CFrame.new(xx, 7.3, 0), "Steel", true, { name = "Merlon" }) end
K.place(m, walls, W + Vector3.new(x + 6, 0, 0)); x += 18
m = K.model("Wall_Pillar", "Muraille")
K.part(m, Vector3.new(3, 9, 3), CFrame.new(0, 4.5, 0), "Steel.d", true, { name = "Pillar" })
K.part(m, Vector3.new(3.6, 0.8, 3.6), CFrame.new(0, 9.4, 0), "Steel.l", true, { name = "Cap" })
K.part(m, Vector3.new(1.2, 1.2, 0.3), CFrame.new(0, 6.5, -1.55), "Gold", false, { name = "Window", neon = true })
K.place(m, walls, W + Vector3.new(x, 0, 0))
props.Parent, walls.Parent = kit, kit
local n = 0
for _, d in kit:GetDescendants() do if d:IsA("BasePart") then n += 1 end end
return ("props ok : kit total %d Parts, %d Models"):format(n, #kit.Arbres:GetChildren() + #kit.Roche:GetChildren() + #props:GetChildren() + #walls:GetChildren())
