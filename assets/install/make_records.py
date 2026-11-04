"""Écrit les fiches des meshes A01 téléversés : CSV et .model.json (format Rojo).

    python assets/install/make_records.py

Entrées : assets/install/a01_ids.txt (sortie de A01_finalize.luau dans Studio) et assets/voxel/manifest.json.
Sorties : assets/a01-meshes.csv, lignes gobelins de assets/creatures.csv, assets/{creatures,equipment,
weapons,fx}/*.model.json.
"""

import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.dirname(HERE)
MAN = {r["name"]: r for r in json.load(open(os.path.join(ASSETS, "voxel", "manifest.json"), encoding="utf-8"))}
REF = {
    "Head": [1.159, 1.182, 1.161],
    "UpperTorso": [1.943, 1.698, 1.004],
    "RightUpperArm": [1.001, 1.242, 1.002],
    "LeftUpperArm": [1.001, 1.242, 1.002],
    "LeftLowerArm": [1.001, 1.118, 1.002],
}
FOLDER = {"enemy": "creatures", "accessory": "equipment", "weapon": "weapons", "fx": "fx"}
PINK = [1.0, 95 / 255, 176 / 255]
EMBER = [1.0, 122 / 255, 26 / 255]

ids = {}
for line in open(os.path.join(HERE, "a01_ids.txt"), encoding="utf-8").read().splitlines()[1:]:
    if line.strip():
        name, mesh, size = line.split(";")
        ids[name] = (mesh, [float(x) for x in size.split(",")])


def rot_matrix(rx, ry, rz):
    """Matrice de CFrame.Angles(rx, ry, rz) (ordre X puis Y puis Z, en degrés)."""
    rx, ry, rz = (math.radians(a) for a in (rx, ry, rz))
    cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
    rxm = [[1, 0, 0], [0, cx, -sx], [0, sx, cx]]
    rym = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    rzm = [[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]]

    def mul(a, b):
        return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]

    return [[round(v, 6) for v in row] for row in mul(mul(rxm, rym), rzm)]


def meshpart(mesh, size, extra=None):
    props = {"MeshId": mesh, "Size": size, "InitialSize": size, "Color": [1, 1, 1], "Anchored": True,
             "CanCollide": False, "CanQuery": False, "CanTouch": False, "CastShadow": False}
    props.update(extra or {})
    return {"className": "MeshPart", "properties": props}


def core_child(offset, size):
    return {"name": "NeonCore", "className": "Part",
            "properties": {"Size": [size] * 3, "Material": "Neon", "Color": EMBER, "Anchored": False,
                           "CanCollide": False, "CanQuery": False, "CanTouch": False, "Massless": True,
                           "CastShadow": False},
            "children": [{"name": "Weld", "className": "Weld",
                          "properties": {"C0": {"position": offset, "orientation": rot_matrix(0, 0, 0)}}}]}


def write(folder, name, data):
    d = os.path.join(ASSETS, folder)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, name + ".model.json"), "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1)
        f.write("\n")


rows = ["name,kind,folder,mesh,sx,sy,sz,tris,attach,attach_offset,attach_rot,ref_part"]
for name, (mesh, size) in ids.items():
    m = MAN[name]
    kind = m["kind"]
    off = m["attach_from_center"]
    if kind == "accessory":
        variants = [(name, m["attach"], False)]
        if m.get("also"):
            variants = [(name + "_R", m["attach"], False), (name + "_L", m["also"], True)]
        for acc_name, att, flip in variants:
            rot = m.get("attach_rot", [0, 0, 0])
            ry = 180 if flip else 0
            part = m["part"].replace("Right", "Left") if flip else m["part"]
            handle = meshpart(mesh, size, {"Anchored": False, "Massless": True})
            handle["name"] = "Handle"
            handle["attributes"] = {"RefPartName": part, "RefPartSize": {"Vector3": REF[m["part"]]}}
            # att.CFrame = CFrame.new(offset) * CFrame.Angles(rot) * CFrame.Angles(0, ry, 0)
            r1 = rot_matrix(*rot)
            r2 = rot_matrix(0, ry, 0)
            rr = [[round(sum(r1[i][k] * r2[k][j] for k in range(3)), 6) for j in range(3)] for i in range(3)]
            handle["children"] = [{"name": att, "className": "Attachment",
                                   "properties": {"CFrame": {"position": off, "orientation": rr}}}]
            if m.get("neon_core_from_center"):
                handle["children"].append(core_child(m["neon_core_from_center"], m["neon_core_size"]))
            write("equipment", acc_name, {"className": "Accessory", "children": [handle]})
    else:
        extra = {"Material": "Neon", "Color": PINK} if kind == "fx" else {}
        data = meshpart(mesh, size, extra)
        data["attributes"] = {"GripOffset": {"Vector3": off}}
        if m.get("neon_core_from_center"):
            data["children"] = [core_child(m["neon_core_from_center"], m["neon_core_size"])]
        write(FOLDER[kind], name, data)
    rows.append(",".join(str(x) for x in [name, kind, FOLDER[kind], mesh, *size, m["tris"], m.get("attach", ""),
                                          " ".join(map(str, off)), " ".join(map(str, m.get("attach_rot", [0, 0, 0]))),
                                          m.get("part", "")]))

with open(os.path.join(ASSETS, "a01-meshes.csv"), "w", encoding="utf-8") as f:
    f.write("\n".join(rows) + "\n")

# Lignes gobelins dans creatures.csv (sans doublon)
cpath = os.path.join(ASSETS, "creatures.csv")
lines = open(cpath, encoding="utf-8").read().splitlines()
lines = [ln for ln in lines if not ln.startswith("Enemy_Goblin")]
for name, (mesh, size) in ids.items():
    if name.startswith("Enemy_Goblin"):
        lines.append(f"{name},{mesh},,{size[0]:.3f},{size[1]:.3f},{size[2]:.3f}")
with open(cpath, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
print(len(rows) - 1, "fiches")
