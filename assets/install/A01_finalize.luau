--!strict
-- A01 : finalisation après l'Import 3D (généré par assets/install/make_finalize.py, ne pas éditer).
-- Range les MeshParts importés dans ReplicatedStorage.Assets et construit les Accessories de classe.
local RS = game:GetService("ReplicatedStorage")
local ITEMS = {
	{ name = "Enemy_GoblinGrunt", folder = "Creatures", offset = Vector3.new(0, -1.875, -0) },
	{ name = "Enemy_GoblinArcher", folder = "Creatures", offset = Vector3.new(0, -1.75, -0) },
	{ name = "Enemy_GoblinShaman", folder = "Creatures", offset = Vector3.new(0, -2.125, -0) },
	{ name = "Enemy_GoblinBomber", folder = "Creatures", offset = Vector3.new(0, -1.75, -0) },
	{ name = "FX_CaptureRing", folder = "FX", offset = Vector3.new(0, -0.25, -0), neon = true },
	{ name = "FX_CaptureIcon", folder = "FX", offset = Vector3.new(0, -1, -0), neon = true },
	{ name = "Knight_Helm", folder = "Equipment", offset = Vector3.new(0, -0, 0.125), attach = "HatAttachment", part = "Head", refSize = Vector3.new(1.159, 1.182, 1.161), rot = Vector3.new(0, 0, 0) },
	{ name = "Knight_Pauldron", folder = "Equipment", offset = Vector3.new(-0.375, -0.25, -0), attach = "RightShoulderAttachment", part = "RightUpperArm", refSize = Vector3.new(1.001, 1.242, 1.002), rot = Vector3.new(0, 0, 0), also = "LeftShoulderAttachment" },
	{ name = "Knight_Cape", folder = "Equipment", offset = Vector3.new(0, 0.5, -0.5), attach = "BodyBackAttachment", part = "UpperTorso", refSize = Vector3.new(1.943, 1.698, 1.004), rot = Vector3.new(0, 0, 0) },
	{ name = "Archer_Hood", folder = "Equipment", offset = Vector3.new(0.125, 0.375, -0.5), attach = "HatAttachment", part = "Head", refSize = Vector3.new(1.159, 1.182, 1.161), rot = Vector3.new(0, 0, 0) },
	{ name = "Archer_Bracer", folder = "Equipment", offset = Vector3.new(0, -0.875, -0), attach = "LeftGripAttachment", part = "LeftLowerArm", refSize = Vector3.new(1.001, 1.118, 1.002), rot = Vector3.new(-90, 0, 0) },
	{ name = "Archer_Quiver", folder = "Equipment", offset = Vector3.new(-0.125, -0.625, -0.5), attach = "BodyBackAttachment", part = "UpperTorso", refSize = Vector3.new(1.943, 1.698, 1.004), rot = Vector3.new(0, 0, 0) },
	{ name = "Mage_Hat", folder = "Equipment", offset = Vector3.new(0, -0.875, -0), attach = "HatAttachment", part = "Head", refSize = Vector3.new(1.159, 1.182, 1.161), rot = Vector3.new(0, 0, 0) },
	{ name = "Mage_Orb", folder = "Equipment", offset = Vector3.new(0.5, -1.75, -0), attach = "LeftShoulderAttachment", part = "LeftUpperArm", refSize = Vector3.new(1.001, 1.242, 1.002), rot = Vector3.new(0, 0, 0), core = Vector3.new(0, -0.25, -0), coreSize = 0.5 },
	{ name = "Mage_Cape", folder = "Equipment", offset = Vector3.new(0, 0.5, -0.625), attach = "BodyBackAttachment", part = "UpperTorso", refSize = Vector3.new(1.943, 1.698, 1.004), rot = Vector3.new(0, 0, 0) },
	{ name = "Weapon_Broadsword", folder = "Weapons", offset = Vector3.new(0, -1.5, 0.25) },
	{ name = "Weapon_Longbow", folder = "Weapons", offset = Vector3.new(0, -0.375, -0.25) },
	{ name = "Weapon_FireStaff", folder = "Weapons", offset = Vector3.new(0.125, -0.875, -0), core = Vector3.new(0.125, 2.125, -0), coreSize = 0.5 },
	{ name = "Weapon_QuakeHammer", folder = "Weapons", offset = Vector3.new(0, -0.625, 0.125) },
	{ name = "Weapon_ThrowingDagger", folder = "Weapons", offset = Vector3.new(0, -0.5, -0.125) },
	{ name = "Weapon_HolyBell", folder = "Weapons", offset = Vector3.new(0, 0.25, -0) },
	{ name = "Weapon_SpinningAxe", folder = "Weapons", offset = Vector3.new(0.375, -0.375, 0.125) },
	{ name = "Weapon_BeastWhip", folder = "Weapons", offset = Vector3.new(0.25, -1.125, 0.25) },
}
local PINK = Color3.fromRGB(255, 95, 176)
local EMBER = Color3.fromRGB(255, 122, 26)
local assets = RS:FindFirstChild("Assets") or Instance.new("Folder")
assets.Name = "Assets"
assets.Parent = RS
local function folder(name: string): Folder
	local f = assets:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = assets
	end
	return f :: Folder
end
local function findImported(name: string): MeshPart?
	for _, d in workspace:GetDescendants() do
		if d:IsA("MeshPart") and d.Name == name then
			return d
		end
	end
	return nil
end
local function prep(p: MeshPart)
	p.Color = Color3.new(1, 1, 1) -- couleurs par sommet exactes
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.PivotOffset = CFrame.new()
end
local function addCore(handle: BasePart, offset: Vector3, size: number)
	local core = Instance.new("Part")
	core.Name = "NeonCore"
	core.Size = Vector3.one * size
	core.Material = Enum.Material.Neon
	core.Color = EMBER
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.Massless = true
	core.CastShadow = false
	core.CFrame = handle.CFrame * CFrame.new(offset)
	local weld = Instance.new("Weld")
	weld.Part0 = handle
	weld.Part1 = core
	weld.C0 = CFrame.new(offset)
	weld.Parent = core
	core.Parent = handle
end
local function accessory(it: any, mesh: MeshPart, accName: string, attName: string, flip: boolean)
	local handle = mesh:Clone()
	prep(handle)
	handle.Anchored = false
	handle.Massless = true
	handle.Name = "Handle"
	handle:SetAttribute("RefPartName", if flip then string.gsub(it.part, "Right", "Left") else it.part)
	handle:SetAttribute("RefPartSize", it.refSize)
	local att = Instance.new("Attachment")
	att.Name = attName
	local r = it.rot
	att.CFrame = CFrame.new(it.offset) * CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
		* (if flip then CFrame.Angles(0, math.pi, 0) else CFrame.identity)
	att.Parent = handle
	if it.core then
		addCore(handle, it.core, it.coreSize)
	end
	local acc = Instance.new("Accessory")
	acc.Name = accName
	handle.Parent = acc
	local old = folder("Equipment"):FindFirstChild(accName)
	if old then
		old:Destroy()
	end
	acc.Parent = folder("Equipment")
end
local report = { "name;MeshId;size" }
for _, it in ITEMS do
	local mesh = findImported(it.name)
	if not mesh then
		warn("A01 : maille importée introuvable : " .. it.name)
		continue
	end
	table.insert(report, ("%s;%s;%.3f,%.3f,%.3f"):format(it.name, mesh.MeshId, mesh.Size.X, mesh.Size.Y, mesh.Size.Z))
	if it.folder == "Equipment" then
		if it.also then
			accessory(it, mesh, it.name .. "_R", it.attach, false)
			accessory(it, mesh, it.name .. "_L", it.also, true)
		else
			accessory(it, mesh, it.name, it.attach, false)
		end
	else
		local p = mesh:Clone()
		prep(p)
		if it.neon then
			p.Material = Enum.Material.Neon
			p.Color = PINK
		end
		p:SetAttribute("GripOffset", it.offset)
		if it.core then
			addCore(p, it.core, it.coreSize)
		end
		local old = folder(it.folder):FindFirstChild(it.name)
		if old then
			old:Destroy()
		end
		p.Parent = folder(it.folder)
	end
end
print(table.concat(report, "\n"))
return table.concat(report, "\n")
