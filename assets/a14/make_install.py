"""COHUE — A14 : génère le script Studio qui range les armes après l'Import 3D de A14_Weapons.glb.

    python assets/a14/make_install.py

Entrée : assets/a14/out/manifest.json (export.py). Sortie : assets/a14/install/A14_weapons_install.luau.
"""

from __future__ import annotations

import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "install", "A14_weapons_install.luau")

HEAD = '''--!strict
-- A14 : rangement des armes en pixel art après l'Import 3D de A14_Weapons.glb (généré par
-- assets/a14/make_install.py, ne pas éditer). À lancer une fois dans Studio, en mode édition.
-- Réglages de l'Import 3D : Scale Unit = Studs, Upload to Roblox activé, Merge Meshes désactivé,
-- Use Imported Pivot activé, Ignore Vertex Colors désactivé.
-- Résultat : ReplicatedStorage.Assets.Weapons.<Nom> = Model { Body (MeshPart), Neon (MeshPart, si présent) },
-- pivot au point de prise, attributs Kind, WeaponId, Dominant, A14. Les modèles v1 de A01 (Weapon_*) ne
-- sont pas touchés. Un modèle A14 du même nom est remplacé.
local RS = game:GetService("ReplicatedStorage")
'''

BODY = '''
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
	-- l'Import 3D range chaque maille dans un Model "<Nom>_Node" dont le pivot est l'origine du nœud
	-- glTF, c'est-à-dire le point de prise ; la MeshPart elle-même a son pivot au centre de sa boîte
	local grip = body.CFrame
	if body.Parent and body.Parent ~= workspace then
		containers[body.Parent] = true
		if body.Parent:IsA("Model") then
			grip = (body.Parent :: Model):GetPivot()
		end
	end
	local model = Instance.new("Model")
	model.Name = it.name
	prep(body, false)
	body.Name = "Body"
	body.PivotOffset = body.CFrame:ToObjectSpace(grip)
	body.Parent = model
	model.PrimaryPart = body
	if it.neon then
		local neon = findImported(it.name .. "_Neon")
		if neon then
			if neon.Parent and neon.Parent ~= workspace then
				containers[neon.Parent] = true
			end
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
	model:SetAttribute("GripOffset", Vector3.zero) -- le pivot du modèle est le point de prise (PivotOffset)
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
print(table.concat(report, "\\n"))
if #missing > 0 then
	warn("A14 : introuvables après l'import : " .. table.concat(missing, ", "))
end
'''


def lua_str(v):
    return '"' + str(v).replace('"', '\\"') + '"'


def main():
    manifest = json.load(open(os.path.join(HERE, "out", "manifest.json"), encoding="utf-8"))
    lines = ["local ITEMS = {"]
    for e in manifest:
        lines.append("\t{ name = %s, kind = %s, weapon = %s, dominant = %s, neon = %s }," % (
            lua_str(e["name"]), lua_str(e["kind"]), lua_str(e["weapon"]), lua_str(e["dominant"] or ""),
            "true" if e["neon"] else "false"))
    lines.append("}")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(HEAD + "\n".join(lines) + "\n" + BODY)
    print(OUT, len(manifest), "modèles")


if __name__ == "__main__":
    main()
