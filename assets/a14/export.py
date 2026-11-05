"""COHUE — A14, export des armes en pixel art (étape 3). Blender 5.2 en ligne de commande :

    blender -b --factory-startup --python assets/a14/export.py -- <glb|icons|boards|all> <dossier de sortie>

- glb    : un GLB par arme, fusion et pièce (objets « Body » et « Neon »), + manifest.json
           (triangles, taille Roblox, prise depuis le centre, Neon, couleur dominante) ;
- icons  : icônes 512 px en léger trois-quarts, fond transparent (pour A08) ;
- boards : rendus des 16 armes, des 16 fusions et des pièces, pour la planche et la relecture.

Repère : Blender +Z = Roblox +Y (l'arme pointe vers +Y), la prise est l'origine des mailles.
"""

from __future__ import annotations

import json
import math
import os
import sys

import bpy
from mathutils import Euler, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.append(HERE)

import concept as C  # noqa: E402  (scène, matériaux, place_weapon)
import pixelweapons as P  # noqa: E402

B = C.B
DOMINANT = {
    "Broadsword": "Royal", "Longbow": "Leaf", "FireStaff": "Ember", "QuakeHammer": "Stone",
    "ThrowingDaggers": "Plum", "HolyAura": "Cream", "SpinningAxes": "Steel", "BeastWhip": "Ember",
    "LightningChain": "Sky", "FrostNova": "Sky", "Boomerang": "Gold", "BombBag": "Grape",
    "SpearThrow": "Leather", "MeteorRain": "Ember", "OrbitingBlades": "Steel", "CrossbowTurret": "Leather",
}


def catalog():
    """(nom du modèle, fonction, type, id d'arme)."""
    out = []
    for wid, fn in P.WEAPON_SPRITES.items():
        out.append((fn().name if fn().name != wid else wid, fn, "weapon", wid))
    for wid, fn in P.FUSION_SPRITES.items():
        out.append((fn().name, fn, "fusion", wid))
    for name, fn in P.PIECE_SPRITES.items():
        out.append((name, fn, "piece", {"Bomb": "BombBag", "Arrow": "Longbow", "Bolt": "CrossbowTurret"}[name]))
    return out


def build(fn):
    """Crée Body (et Neon) à l'origine, dans une scène vide ; rend (objets, sprite)."""
    sp = fn()
    body, neon = sp.voxels()
    o = sp.origin()
    obs = []
    ob = C.pixel_to_blender(body, o, voxel=C.PX)
    ob.name = "Body"
    ob.data.materials.clear()
    ob.data.materials.append(C.weapon_material())
    obs.append(ob)
    if neon.c:
        nb = C.pixel_to_blender(neon, o, voxel=C.PX)
        nb.name = "Neon"
        nb.data.materials.clear()
        nb.data.materials.append(C.neon_material())
        obs.append(nb)
    return obs, sp


def bounds(obs):
    pts = [ob.matrix_world @ Vector(c) for ob in obs for c in ob.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


def export_glb(obs, path):
    for other in bpy.context.scene.objects:
        other.select_set(other in obs)
    bpy.context.view_layer.objects.active = obs[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_normals=True, export_texcoords=True,
                              export_materials="EXPORT", export_vertex_color="ACTIVE",
                              export_all_vertex_colors=False, export_animations=False)


def do_glb(outdir):
    gdir = os.path.join(outdir, "glb")
    os.makedirs(gdir, exist_ok=True)
    manifest = []
    for name, fn, kind, wid in catalog():
        C.fresh()
        obs, sp = build(fn)
        bpy.context.view_layer.update()
        lo, hi = bounds(obs)
        size = hi - lo
        ctr = (lo + hi) / 2
        rb_ctr = Vector((-ctr.x, ctr.z, ctr.y))                    # Blender -> Roblox (glTF Y-up, import)
        export_glb(obs, os.path.join(gdir, name + ".glb"))
        manifest.append({
            "name": name, "kind": kind, "weapon": wid,
            "tris": sum(ob["tris"] for ob in obs), "tris_neon": obs[1]["tris"] if len(obs) > 1 else 0,
            "size": [round(size.x, 3), round(size.z, 3), round(size.y, 3)],
            "grip_from_center": [round(-v, 4) for v in rb_ctr],
            "neon": len(obs) > 1, "dominant": DOMINANT.get(wid),
            "sprite_px": [sp.w, sp.h],
        })
        print(name, manifest[-1]["tris"], manifest[-1]["size"])
    with open(os.path.join(outdir, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1, ensure_ascii=False)


def do_icons(outdir):
    idir = os.path.join(outdir, "icons")
    os.makedirs(idir, exist_ok=True)
    for name, fn, kind, wid in catalog():
        if kind == "piece":
            continue
        sc = C.fresh()
        B.diorama_light(sc, sun_elev=40, sun_az=-30, strength=4.0, world="FFFFFF", world_strength=0.8)
        root = C.place_weapon(fn, (0, 0, 0), rot=Euler((math.radians(8), 0, math.radians(-22))))
        bpy.context.view_layer.update()
        lo, hi = bounds(list(root.children))
        mid = (lo + hi) / 2
        B.camera(sc, (mid.x, mid.y - 30.0, mid.z), (mid.x, mid.y, mid.z), ortho=max(hi.x - lo.x, hi.z - lo.z) * 1.12)
        sc.view_settings.view_transform = "Standard"
        B.render(sc, os.path.join(idir, f"{name}.png"), res=(512, 512), transparent=True, samples=32)


def lineup(fns, out, cols=8):
    """Les modèles en rangées, de trois quarts, sur une dalle claire, avec l'avatar pour l'échelle."""
    sc = C.fresh()
    B.diorama_light(sc, sun_elev=48, sun_az=-35, strength=4.8, world="8FC8F2", world_strength=1.0)
    rows = (len(fns) + cols - 1) // cols
    C.S.block("Plinth", (0, rows * 3.5, -0.5), (80, rows * 9 + 10, 1), "Stone.l", jitter=0.0)
    for i, fn in enumerate(fns):
        r, c = divmod(i, cols)
        root = C.place_weapon(fn, (0, 0, 0), rot=Euler((0, 0, math.radians(-25))))
        bpy.context.view_layer.update()
        lo, _hi = bounds(list(root.children))
        root.location = ((c - (cols - 1) / 2) * 5.2, r * 8.0, -lo.z + 0.02)
    B.place(C.M.mannequin, ((cols / 2 + 0.3) * 5.2, 0.0, 0), rot_z=math.radians(-20))
    depth = (rows - 1) * 8.0
    B.camera(sc, (0, -46 - depth * 0.2, 16 + depth * 0.9), (0, depth / 2, 1.5), lens=42)
    C.render(sc, out, res=(2400, 900 + 380 * (rows - 1)), samples=48)


def do_boards(outdir):
    bdir = os.path.join(outdir, "boards")
    os.makedirs(bdir, exist_ok=True)
    lineup(list(P.WEAPON_SPRITES.values()), os.path.join(bdir, "weapons.png"))
    lineup(list(P.FUSION_SPRITES.values()), os.path.join(bdir, "fusions.png"))
    lineup(list(P.PIECE_SPRITES.values()), os.path.join(bdir, "pieces.png"), cols=3)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:]
    which, outdir = argv[0], os.path.abspath(argv[1])
    os.makedirs(outdir, exist_ok=True)
    for step in (("glb", "icons", "boards") if which == "all" else which.split(",")):
        {"glb": do_glb, "icons": do_icons, "boards": do_boards}[step](outdir)
