"""Génère assets/install/A01_finalize.luau à partir de assets/voxel/manifest.json.

    python assets/install/make_finalize.py

Le script Luau produit se lance dans Studio (barre de commande ou MCP) APRÈS l'Import 3D des GLB de
assets/voxel/glb/. Il range les MeshParts importés dans ReplicatedStorage.Assets (Creatures, Equipment,
Weapons, FX), construit les Accessories (Handle, attache R15, attributs d'échelle, cœur Neon) et affiche
la liste nom;MeshId;taille à reporter dans assets/*.csv.
"""

import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
MAN = json.load(open(os.path.join(ROOT, "assets", "voxel", "manifest.json"), encoding="utf-8"))

# Tailles des parties du corps de l'avatar R15 par défaut (mesurées dans Studio le 4 nov. 2026)
REF = {
    "Head": (1.159, 1.182, 1.161),
    "UpperTorso": (1.943, 1.698, 1.004),
    "RightUpperArm": (1.001, 1.242, 1.002),
    "LeftUpperArm": (1.001, 1.242, 1.002),
    "LeftLowerArm": (1.001, 1.118, 1.002),
}
FOLDER = {"enemy": "Creatures", "accessory": "Equipment", "weapon": "Weapons", "fx": "FX"}


def v3(t):
    return "Vector3.new(%s)" % ", ".join(f"{x:g}" for x in t)


rows = []
for r in MAN:
    kind = r["kind"]
    entry = [f'name = "{r["name"]}"', f'folder = "{FOLDER[kind]}"', f"offset = {v3(r['attach_from_center'])}"]
    if kind == "accessory":
        entry.append(f'attach = "{r["attach"]}"')
        entry.append(f'part = "{r["part"]}"')
        entry.append(f"refSize = {v3(REF[r['part']])}")
        rot = r.get("attach_rot", [0, 0, 0])
        entry.append(f"rot = {v3(rot)}")
        if r.get("also"):
            entry.append(f'also = "{r["also"]}"')
    if r.get("neon_core_from_center"):
        entry.append(f"core = {v3(r['neon_core_from_center'])}")
        entry.append(f"coreSize = {r['neon_core_size']}")
    if kind == "fx":
        entry.append("neon = true")
    rows.append("\t{ " + ", ".join(entry) + " },")

lua = '''--!strict
-- A01 : finalisation après l'Import 3D (généré par assets/install/make_finalize.py, ne pas éditer).
-- Range les MeshParts importés dans ReplicatedStorage.Assets et construit les Accessories de classe.
local RS = game:GetService("ReplicatedStorage")
local ITEMS = {
%s
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
	table.insert(report, ("%%s;%%s;%%.3f,%%.3f,%%.3f"):format(it.name, mesh.MeshId, mesh.Size.X, mesh.Size.Y, mesh.Size.Z))
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
print(table.concat(report, "\\n"))
return table.concat(report, "\\n")
''' % "\n".join(rows)

out = os.path.join(HERE, "A01_finalize.luau")
open(out, "w", encoding="utf-8").write(lua)
print(out, len(rows), "entrées")
