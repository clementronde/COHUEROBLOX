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


def fx_shape(name, r_in, r_out, segments=96, dashes=0, fill=0.6, height=0.04):
    """Forme lisse pour les effets (anneau, anneau en pointillé, disque) : rayon extérieur 1 stud, centrée,
    plate et épaisse de `height`. La couleur, le Neon et la transparence sont posés dans Studio."""
    import bmesh

    bm = bmesh.new()
    steps = []
    if dashes:
        per = segments // dashes
        for d in range(dashes):
            a0 = d * per
            steps.append([a0 + k for k in range(int(per * fill) + 1)])
    else:
        steps.append(list(range(segments + 1)))
    for run in steps:
        top_in, top_out, bot_in, bot_out = [], [], [], []
        for k in run:
            a = 2 * math.pi * k / segments
            c, s_ = math.cos(a), math.sin(a)
            for lst, r, z in ((top_out, r_out, height / 2), (top_in, r_in, height / 2),
                              (bot_out, r_out, -height / 2), (bot_in, r_in, -height / 2)):
                lst.append(bm.verts.new((c * r, s_ * r, z)))
        for i in range(len(run) - 1):
            if r_in > 0:
                bm.faces.new((top_in[i], top_out[i], top_out[i + 1], top_in[i + 1]))
                bm.faces.new((bot_in[i + 1], bot_out[i + 1], bot_out[i], bot_in[i]))
                bm.faces.new((top_in[i + 1], bot_in[i + 1], bot_in[i], top_in[i]))
            else:
                bm.faces.new((top_in[i], top_out[i], top_out[i + 1]))
                bm.faces.new((bot_in[i], bot_out[i + 1], bot_out[i]))
            bm.faces.new((top_out[i], bot_out[i], bot_out[i + 1], top_out[i + 1]))
        if dashes and r_in > 0:                                   # bouts des tirets
            bm.faces.new((top_in[0], bot_in[0], bot_out[0], top_out[0]))
            bm.faces.new((top_out[-1], bot_out[-1], bot_in[-1], top_in[-1]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


ARC_SEGMENTS = 9          # croissant de 180° en segments de 20° (on en montre 7 pour 140°)


def arc_segment(name, i, layer):
    """Segment i (0..8) du croissant du coup de taille, rayon extérieur 1. layer : « Halo » (bande entière)
    ou « Core » (bande fine sur le bord extérieur). Origine au centre de la boîte du segment ; rend
    (objet, centre en axes Roblox)."""
    import bmesh

    seg_deg = 180.0 / ARC_SEGMENTS
    steps = 8
    bm = bmesh.new()
    top, bot = [], []
    for k in range(steps + 1):
        g = (i * steps + k) / (ARC_SEGMENTS * steps)               # 0..1 sur tout le croissant
        a = math.radians(-90 + seg_deg * i + seg_deg * k / steps)
        thick = 0.1 + 0.36 * math.sin(math.pi * g) ** 0.8
        r_in = 1.0 - (thick if layer == "Halo" else thick * 0.4)
        r_out = 1.0
        d_out = Vector((math.sin(a), -math.cos(a), 0))             # centré sur -Y Blender = avant Roblox
        top.append((bm.verts.new(d_out * r_out + Vector((0, 0, 0.02))), bm.verts.new(d_out * r_in + Vector((0, 0, 0.02)))))
        bot.append((bm.verts.new(d_out * r_out - Vector((0, 0, 0.02))), bm.verts.new(d_out * r_in - Vector((0, 0, 0.02)))))
    for k in range(steps):
        (to0, ti0), (to1, ti1) = top[k], top[k + 1]
        (bo0, bi0), (bo1, bi1) = bot[k], bot[k + 1]
        bm.faces.new((ti0, to0, to1, ti1))
        bm.faces.new((bi1, bo1, bo0, bi0))
        bm.faces.new((to0, bo0, bo1, to1))
        bm.faces.new((ti1, bi1, bi0, ti0))
    bm.faces.new((top[0][1], bot[0][1], bot[0][0], top[0][0]))
    bm.faces.new((top[-1][0], bot[-1][0], bot[-1][1], top[-1][1]))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ctr = sum((v.co for v in me.vertices), Vector()) / len(me.vertices)
    for v in me.vertices:
        v.co -= ctr                                               # origine au centre du segment
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob, [round(-ctr.x, 4), round(ctr.z, 4), round(ctr.y, 4)]


FX_SHAPES = [("FX_Ring", 0.93, 1.0, 0), ("FX_RingThick", 0.72, 1.0, 0), ("FX_RingDashed", 0.9, 1.0, 16),
             ("FX_Disc", 0.0, 1.0, 0)]


def do_pack(outdir):
    """Un seul GLB pour l'Import 3D de Studio : toutes les armes, fusions et pièces, chaque maille nommée
    <Nom> (corps) ou <Nom>_Neon, origine à la prise (réglage « Use Imported Pivot »)."""
    C.fresh()
    obs = []
    for name, fn, kind, wid in catalog():
        made, _sp = build(fn)
        for ob in made:
            ob.name = name if ob.name.startswith("Body") else name + "_Neon"
            ob.data.name = ob.name
            obs.append(ob)
    for name, r_in, r_out, dashes in FX_SHAPES:                   # formes lisses des effets
        obs.append(fx_shape(name, r_in, r_out, dashes=dashes))
    arcs = {}
    for layer in ("Halo", "Core"):                                 # croissant du coup de taille
        for i in range(ARC_SEGMENTS):
            ob, ctr = arc_segment(f"FX_Arc{layer}{i + 1}", i, layer)
            obs.append(ob)
            arcs[ob.name] = ctr
    with open(os.path.join(outdir, "fx_shapes.json"), "w", encoding="utf-8") as f:
        json.dump({"arc_segments": ARC_SEGMENTS, "arc_centers": arcs}, f, indent=1)
    export_glb(obs, os.path.join(outdir, "A14_Weapons.glb"))
    print("pack :", len(obs), "mailles")


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
        {"glb": do_glb, "icons": do_icons, "boards": do_boards, "pack": do_pack}[step](outdir)
