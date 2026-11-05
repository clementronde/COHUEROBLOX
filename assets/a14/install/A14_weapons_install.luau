--!strict
-- A14 : rangement des armes en pixel art après l'Import 3D de A14_Weapons.glb (généré par
-- assets/a14/make_install.py, ne pas éditer). À lancer une fois dans Studio, en mode édition.
-- Réglages de l'Import 3D : Scale Unit = Studs, Upload to Roblox activé, Merge Meshes désactivé,
-- Use Imported Pivot activé, Ignore Vertex Colors désactivé.
-- Résultat : ReplicatedStorage.Assets.Weapons.<Nom> = Model { Body (MeshPart), Neon (MeshPart, si présent) },
-- pivot au point de prise, attributs Kind, WeaponId, Dominant, A14. Les modèles v1 de A01 (Weapon_*) ne
-- sont pas touchés. Un modèle A14 du même nom est remplacé.
local RS = game:GetService("ReplicatedStorage")
local ITEMS = {
	{ name = "Broadsword", kind = "weapon", weapon = "Broadsword", dominant = "Royal", neon = true },
	{ name = "Longbow", kind = "weapon", weapon = "Longbow", dominant = "Leaf", neon = true },
	{ name = "FireStaff", kind = "weapon", weapon = "FireStaff", dominant = "Ember", neon = true },
	{ name = "QuakeHammer", kind = "weapon", weapon = "QuakeHammer", dominant = "Stone", neon = true },
	{ name = "ThrowingDaggers", kind = "weapon", weapon = "ThrowingDaggers", dominant = "Plum", neon = true },
	{ name = "HolyAura", kind = "weapon", weapon = "HolyAura", dominant = "Cream", neon = true },
	{ name = "SpinningAxes", kind = "weapon", weapon = "SpinningAxes", dominant = "Steel", neon = false },
	{ name = "BeastWhip", kind = "weapon", weapon = "BeastWhip", dominant = "Ember", neon = true },
	{ name = "LightningChain", kind = "weapon", weapon = "LightningChain", dominant = "Sky", neon = true },
	{ name = "FrostNova", kind = "weapon", weapon = "FrostNova", dominant = "Sky", neon = true },
	{ name = "Boomerang", kind = "weapon", weapon = "Boomerang", dominant = "Gold", neon = false },
	{ name = "BombBag", kind = "weapon", weapon = "BombBag", dominant = "Grape", neon = true },
	{ name = "SpearThrow", kind = "weapon", weapon = "SpearThrow", dominant = "Leather", neon = false },
	{ name = "MeteorRain", kind = "weapon", weapon = "MeteorRain", dominant = "Ember", neon = true },
	{ name = "OrbitingBlades", kind = "weapon", weapon = "OrbitingBlades", dominant = "Steel", neon = true },
	{ name = "CrossbowTurret", kind = "weapon", weapon = "CrossbowTurret", dominant = "Leather", neon = true },
	{ name = "RoyalGreatsword", kind = "fusion", weapon = "Broadsword", dominant = "Royal", neon = true },
	{ name = "StormBow", kind = "fusion", weapon = "Longbow", dominant = "Leaf", neon = true },
	{ name = "SunStaff", kind = "fusion", weapon = "FireStaff", dominant = "Ember", neon = true },
	{ name = "MountainMaul", kind = "fusion", weapon = "QuakeHammer", dominant = "Stone", neon = true },
	{ name = "DaggerFlurry", kind = "fusion", weapon = "ThrowingDaggers", dominant = "Plum", neon = true },
	{ name = "GrandChime", kind = "fusion", weapon = "HolyAura", dominant = "Cream", neon = true },
	{ name = "AxeTornado", kind = "fusion", weapon = "SpinningAxes", dominant = "Steel", neon = false },
	{ name = "RingmasterLash", kind = "fusion", weapon = "BeastWhip", dominant = "Ember", neon = true },
	{ name = "ThunderWeb", kind = "fusion", weapon = "LightningChain", dominant = "Sky", neon = true },
	{ name = "BlizzardGlobe", kind = "fusion", weapon = "FrostNova", dominant = "Sky", neon = true },
	{ name = "ComebackRang", kind = "fusion", weapon = "Boomerang", dominant = "Gold", neon = true },
	{ name = "ClusterSack", kind = "fusion", weapon = "BombBag", dominant = "Grape", neon = true },
	{ name = "CometJavelin", kind = "fusion", weapon = "SpearThrow", dominant = "Leather", neon = true },
	{ name = "StarShower", kind = "fusion", weapon = "MeteorRain", dominant = "Ember", neon = true },
	{ name = "BuzzsawHalo", kind = "fusion", weapon = "OrbitingBlades", dominant = "Steel", neon = true },
	{ name = "SiegeBallista", kind = "fusion", weapon = "CrossbowTurret", dominant = "Leather", neon = true },
	{ name = "Bomb", kind = "piece", weapon = "BombBag", dominant = "Grape", neon = true },
	{ name = "Arrow", kind = "piece", weapon = "Longbow", dominant = "Leaf", neon = false },
	{ name = "Bolt", kind = "piece", weapon = "CrossbowTurret", dominant = "Leather", neon = false },
}

local assets = RS:FindFirstChild("Assets")
if not assets then
	assets = Instance.new("Folder")
	assets.Name = "Assets"
	assets.Parent = RS
end
local weapons = (assets :: Instance):FindFirstChild("Weapons")
if not weapons then
	weapons = Instance.new("Folder")
	weapons.Name = "Weapons"
	weapons.Parent = assets
end

local function findImported(name: string): MeshPart?
	for _, d in workspace:GetDescendants() do
		if d:IsA("MeshPart") and d.Name == name then
			return d
		end
	end
	return nil
end

local function prep(p: MeshPart, neon: boolean)
	p.Color = Color3.new(1, 1, 1) -- couleurs par sommet exactes
	p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
end

local containers: { [Instance]: boolean } = {}
local report = {}
local missing = {}
for _, it in ITEMS do
	local body = findImported(it.name)
	if not body then
		table.insert(missing, it.name)
		continue
	end
	local old = (weapons :: Instance):FindFirstChild(it.name)
	if old and old:GetAttribute("A14") then
		old:Destroy()
	end
	if body.Parent and body.Parent ~= workspace then
		containers[body.Parent] = true
	end
	local model = Instance.new("Model")
	model.Name = it.name
	prep(body, false)
	body.Name = "Body"
	body.Parent = model
	model.PrimaryPart = body
	if it.neon then
		local neon = findImported(it.name .. "_Neon")
		if neon then
			prep(neon, true)
			neon.Name = "Neon"
			neon.Parent = model
		else
			table.insert(missing, it.name .. "_Neon")
		end
	end
	model:SetAttribute("A14", true)
	model:SetAttribute("Kind", it.kind)
	model:SetAttribute("WeaponId", it.weapon)
	model:SetAttribute("Dominant", it.dominant)
	model:SetAttribute("GripOffset", Vector3.zero) -- le pivot du modèle est déjà le point de prise
	model:PivotTo(CFrame.new())
	model.Parent = weapons
	table.insert(report, string.format("%s;%s;%s", it.name, body.MeshId, tostring(body.Size)))
end
for c in containers do
	if c.Parent and #c:GetDescendants() == 0 then
		c:Destroy()
	end
end
print("A14 : " .. #report .. " modèles rangés dans ReplicatedStorage.Assets.Weapons")
print(table.concat(report, "\n"))
if #missing > 0 then
	warn("A14 : introuvables après l'import : " .. table.concat(missing, ", "))
end
