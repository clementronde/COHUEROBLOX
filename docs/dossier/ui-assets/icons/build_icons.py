"""COHUE — icônes d'interface en vraies briques (A08, concept v3 du 5 nov. 2026).

Chaque icône est une silhouette dessinée sur une grille (vue de face), extrudée en profondeur, puis
montée en briques à tenons avec les outils d'A01 (assets/voxel/brick.py) : mêmes briques, mêmes
tenons, même palette COHUE 16 que le monde du jeu. Rendu en vue de trois quarts, fond transparent.

Utilisation (Blender 5.2) :
  blender -b --factory-startup --python docs/dossier/ui-assets/icons/build_icons.py -- <dossier_sortie> [noms...]
Ensuite : python docs/dossier/ui-assets/icons/outline_icons.py <dossier_sortie> (contour Ink).
"""

from __future__ import annotations

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.normpath(os.path.join(HERE, "..", "..", "..", "..", "assets", "voxel")))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import brick  # noqa: E402
from cohue_voxel import Vox, hex_rgb  # noqa: E402

# Lettre de la grille -> couleur de la palette COHUE 16 (et ses tons .l / .d)
KEY = {
    "K": "Ink", "R": "Tomato", "r": "Tomato.d", "P": "Tomato.l",
    "C": "Cream", "c": "Cream.d", "S": "Stone", "s": "Stone.d", "Z": "Stone.l",
    "T": "Steel", "t": "Steel.d", "U": "Steel.l",
    "G": "Gold", "g": "Gold.d", "Y": "Gold.l",
    "E": "Ember", "e": "Ember.d", "H": "Ember.l",
    "B": "Bark", "L": "Leather", "l": "Leather.d",
    "M": "Lime", "m": "Lime.d", "F": "Leaf", "f": "Leaf.d",
    "O": "Royal", "o": "Royal.d", "Q": "Sky", "q": "Sky.d", "V": "Grape",
    "X": "Bubblegum", "x": "Bubblegum.d",
}

# Silhouettes, vue de face, ligne du haut en premier. (profondeur en cellules)
ICONS: dict[str, tuple[int, list[str]]] = {
    "hp": (3, [
        "..RRR...RRR..",
        ".RPPRR.RRRRR.",
        "RRPRRRRRRRRRR",
        "RRPRRRRRRRRRR",
        "RRRRRRRRRRRRR",
        "RRRRRRRRRRRRr",
        ".RRRRRRRRRRr.",
        "..RRRRRRRRr..",
        "...RRRRRRr...",
        "....RRRRr....",
        ".....RRr.....",
        "......r......",
    ]),
    "coin": (2, [
        ".....tttttt.....",
        "...ttUUUUUUtt...",
        "..tUUTTTTTTUUt..",
        ".tUTTTTTTTTTTUt.",
        ".tUTTTTCCTTTTUt.",
        "tUTTTTCCCCTTTTUt",
        "tUTTCCCCCCCCTTUt",
        "tUTTTCCCCCCTTTUt",
        "tUTTTTCCCCTTTTUt",
        "tUTTTCCTTCCTTTUt",
        ".tUTTCTTTTCTTUt.",
        ".tUTTTTTTTTTTUt.",
        "..tUUTTTTTTUUt..",
        "...ttUUUUUUtt...",
        ".....tttttt.....",
    ]),
    "lock": (3, [
        "...SSSS...",
        "..SS..SS..",
        "..S....S..",
        "..S....S..",
        "GGGGGGGGGG",
        "GYYGGGGGGg",
        "GYGGKKGGGg",
        "GGGGKKGGGg",
        "GGGGKKGGGg",
        "GGGGGGGGGg",
        ".gggggggg.",
    ]),
    "capture_light": (3, [
        ".....CC.....",
        "....C..C....",
        "..CCCCCCCC..",
        ".CC.C..C.CC.",
        ".CMMCMMCMMC.",
        ".CMMCMMCMMC.",
        ".CKMCMMCMKC.",
        ".CMMCMMCMMC.",
        ".CmmCmmCmmC.",
        ".CCCCCCCCCC.",
        "cccccccccccc",
    ]),
    "ko": (3, [
        "M..............M",
        "MM...MMMMMM...MM",
        ".MMMMMMMMMMMMMM.",
        "..MMMMMMMMMMMM..",
        "..MMCCCMMCCCMM..",
        "..MCCKCMMCKCCM..",
        "..MCCKCMMCKCCM..",
        "..MMCCCMMCCCMM..",
        "..MMMMMMMMMMMM..",
        "..MMMKKKKKKMMM..",
        "...MMMMMMMMMM...",
        "....mmmmmmmm....",
    ]),
    "timer": (2, [
        ".....RR.....",
        "...RRRRRR...",
        "..RCCCCCCR..",
        ".RCCCCKCCCR.",
        "RCCCCCKCCCCr",
        "RCCCCCKCCCCr",
        "RCCCCCKKKCCr",
        "RCCCCCCCCCCr",
        "RCCCCCCCCCCr",
        ".rCCCCCCCCr.",
        "..rCCCCCCr..",
        "...rrrrrr...",
    ]),
    "sword": (2, [
        ".............U",
        "............UU",
        "...........UTt",
        "..........UTt.",
        ".........UTt..",
        "........UTt...",
        ".......UTt....",
        "..g...UTt.....",
        "..gG.UTt......",
        "...gGTt.......",
        "....GG........",
        "...BBgG.......",
        "..BB...g......",
        ".GB...........",
    ]),
    "lightning": (2, [
        ".....QQQQ",
        "....QCQQ.",
        "...QCQQ..",
        "..QCQQ...",
        ".QCQQQQQ.",
        "QQQQQQQq.",
        "....QQq..",
        "...QQq...",
        "..QQq....",
        ".QQq.....",
        "QQq......",
        "Qq.......",
    ]),
    "firestaff": (2, [
        ".........EE...",
        "........EEEE..",
        ".......EEHHEE.",
        ".......EHHCHE.",
        ".......EHCCHE.",
        "........EHHE..",
        ".........ee...",
        "........BB....",
        ".......BB.....",
        "......BB......",
        ".....BB.......",
        "....BB........",
        "...BB.........",
        "..BB..........",
        ".BB...........",
    ]),
    "jump": (2, [
        ".....CC.....",
        "....CCCC....",
        "...CCCCCC...",
        "..CCCCCCCC..",
        ".CCCCCCCCCC.",
        "CCCCCCCCCCCC",
        "....CCCC....",
        "....CCCC....",
        "....CCCC....",
        "....CCCC....",
        "....cccc....",
    ]),
    "slide": (2, [
        "CC....CC....",
        "CCC...CCC...",
        ".CCC...CCC..",
        "..CCC...CCC.",
        "...CCC...CCC",
        "..CCC...CCC.",
        ".CCC...CCC..",
        "CCC...CCC...",
        "CC....CC....",
    ]),
    "ping": (2, [
        "BBRRRRRRR...",
        "BBRRRRRRRR..",
        "BBRRRRRRRRR.",
        "BBRRRRRRRR..",
        "BBRRRRRRR...",
        "BBRR........",
        "BB..........",
        "BB..........",
        "BB..........",
        "BB..........",
        "BBB.........",
    ]),
    "capture": (3, [
        ".....XX.....",
        "....X..X....",
        "..XXXXXXXX..",
        ".XX.X..X.XX.",
        ".X..X..X..X.",
        ".X..X..X..X.",
        ".X..X..X..X.",
        ".X..X..X..X.",
        ".X..X..X..X.",
        ".XXXXXXXXXX.",
        "xxxxxxxxxxxx",
    ]),
    "settings": (2, [
        ".....SS.....",
        "..SS.SS.SS..",
        "..SSSSSSSS..",
        ".SSSSssSSSS.",
        "SSSSs..sSSSS",
        "SSSs....sSSS",
        "SSSs....sSSS",
        "SSSSs..sSSSS",
        ".SSSSssSSSS.",
        "..SSSSSSSS..",
        "..SS.SS.SS..",
        ".....SS.....",
    ]),
    "settings_light": (2, [
        ".....CC.....",
        "..CC.CC.CC..",
        "..CCCCCCCC..",
        ".CCCCccCCCC.",
        "CCCCc..cCCCC",
        "CCCc....cCCC",
        "CCCc....cCCC",
        "CCCCc..cCCCC",
        ".CCCCccCCCC.",
        "..CCCCCCCC..",
        "..CC.CC.CC..",
        ".....CC.....",
    ]),
    "rune_speed": (2, [
        "..SSSSSSS..",
        ".SZZZZZZZs.",
        "SZSSSSSSSSs",
        "SZSEESSSSSs",
        "SZSSEESSSSs",
        "SZSSSEESSSs",
        "SZSSSSEESSs",
        "SZSSSEESSSs",
        "SZSSEESSSSs",
        "SZSEESSSSSs",
        "SZSSSSSSSSs",
        ".sSSSSSSSs.",
        "..sssssss..",
    ]),
    "rune_damage": (2, [
        "..SSSSSSS..",
        ".SZZZZZZZs.",
        "SZSSSSSSSSs",
        "SZSRRSSRRSs",
        "SZSSRRRRSSs",
        "SZSSSRRSSSs",
        "SZSSRRRRSSs",
        "SZSRRSSRRSs",
        "SZSSSSSSSSs",
        ".sSSSSSSSs.",
        "..sssssss..",
    ]),
    "rune_area": (2, [
        "..SSSSSSS..",
        ".SZZZZZZZs.",
        "SZSSSSSSSSs",
        "SZSSQQQSSSs",
        "SZSQSSSQSSs",
        "SZSQSSSQSSs",
        "SZSQSSSQSSs",
        "SZSSQQQSSSs",
        "SZSSSSSSSSs",
        ".sSSSSSSSs.",
        "..sssssss..",
    ]),
    "sock": (3, [
        "...RRRR...",
        "...CCCC...",
        "...RRRR...",
        "...CCCC...",
        "...RRRR...",
        "...RRRR...",
        "..RRRRR...",
        ".RRRRRR...",
        "RRRRRRRRR.",
        "RRRRRRRRRR",
        ".rrrrrrrr.",
    ]),
    "lunchbox": (4, [
        "...cccc...",
        "...c..c...",
        ".OOOOOOOO.",
        "OOOOOOOOOO",
        "OCCCCCCCCo",
        "OOOOOOOOOo",
        "OOOOOOOOOo",
        "OOOOOOOOOo",
        ".oooooooo.",
    ]),
    "chalk": (2, [
        ".......QQ",
        "......QCC",
        ".....CCCc",
        "....CCCc.",
        "...CCCc..",
        "..CCCc...",
        ".CCCc....",
        "CCCc.....",
        "cc.......",
    ]),
    "exclaim": (3, [
        "...EEEE...",
        "...EHHE...",
        "...EHHE...",
        "...EEEE...",
        "...EEEE...",
        "....EE....",
        "....EE....",
        "..........",
        "...EEEE...",
        "...eeee...",
    ]),
    "gem": (3, [
        "...QQQQQQ...",
        "..QCCQQQQq..",
        ".QCQQQQQQQq.",
        "QQQQQQQQQQQq",
        ".qQQQQQQQQq.",
        "..qQQQQQQq..",
        "...qQQQQq...",
        "....qQQq....",
        ".....qq.....",
    ]),
    "oak": (3, [
        "...FFFFFFFF...",
        ".FFFFFFFFFFFF.",
        "FFFFFFFFFFFFFF",
        "FFfFFFFFFFFfFF",
        "fBBBBBBBBBBBBf",
        ".BBLLBBBBLLBB.",
        ".BBKKBBBBKKBB.",
        ".BBBBBBBBBBBB.",
        ".BBBKKKKKKBBB.",
        ".BBBBBBBBBBBB.",
        "..BBBBBBBBBB..",
        ".BB.BB..BB.BB.",
    ]),
    "trophy": (3, [
        ".GGGGGGGGGG.",
        "GGYYGGGGGGgG",
        "G.GYGGGGGg.G",
        "G.GYGGGGGg.G",
        ".GGYGGGGGgG.",
        "..GGGGGGgg..",
        "...gGGGgg...",
        "....gGGg....",
        ".....Gg.....",
        "....GGgg....",
        "...BBBBBB...",
        "...BBBBBB...",
    ]),
    "chest": (4, [
        ".BBBBBBBBBB.",
        "BLLLLLLLLLLB",
        "BLLLLLLLLLLB",
        "GGGGGGGGGGGG",
        "BLLLLGGLLLLB",
        "BLLLLGKLLLLB",
        "BLLLLLLLLLLB",
        "BllllllllllB",
        "GGGGGGGGGGGG",
    ]),
    "flame": (3, [
        ".....E......",
        "....EE......",
        "...EEE..E...",
        "...EEEE.EE..",
        "..EEEEEEEE..",
        "..EEHEEEEEE.",
        ".EEHHHEEEEE.",
        ".EEHCCHEEEE.",
        ".EHHCCHHEEe.",
        ".EHCCCCHHEe.",
        "..HCCCCCHe..",
        "...HHHHHe...",
    ]),
}


def make_vox(name: str, depth: int, rows: list[str]) -> Vox:
    v = Vox(name)
    h = len(rows)
    for r, line in enumerate(rows):
        for x, ch in enumerate(line):
            if ch == ".":
                continue
            for y in range(depth):
                v.set(x, y, h - 1 - r, KEY[ch])
    return v


def reset_scene():
    for coll in (bpy.data.objects, bpy.data.meshes, bpy.data.cameras, bpy.data.lights, bpy.data.worlds):
        for item in list(coll):
            coll.remove(item)
    sc = bpy.context.scene
    for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            continue
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = 512
    sc.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (*hex_rgb("C8D8FF"), 1.0)
    bg.inputs["Strength"].default_value = 0.9
    sc.world = world
    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = 3.2
    sun.color = hex_rgb("FFF4D8")
    sun.angle = math.radians(8)
    so = bpy.data.objects.new("Sun", sun)
    so.rotation_euler = (math.radians(40), math.radians(-28), math.radians(-25))
    sc.collection.objects.link(so)
    return sc


# Icônes tirées directement des modèles d'A01 (assets/voxel/models.py) : (fonction, inclinaison en degrés)
MODELS = {"capture_cage": ("capture_icon", 0.0), "axes": ("weapon_spinningaxe", -35.0)}


def render_icon(name: str, depth: int, rows: list[str], out_dir: str, vox=None, tilt=0.0):
    sc = reset_scene()
    ob = brick.to_blender(vox or make_vox(name, depth, rows), origin="center", name=name)
    if tilt:
        ob.rotation_euler = (0.0, math.radians(tilt), 0.0)
    bpy.context.view_layer.update()
    pts = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    center = sum(pts, Vector()) / 8
    size = max((max(p[i] for p in pts) - min(p[i] for p in pts)) for i in range(3))
    cam = bpy.data.cameras.new("Cam")
    cam.type = "ORTHO"
    cam.ortho_scale = size * 1.18
    co = bpy.data.objects.new("Cam", cam)
    sc.collection.objects.link(co)
    yaw, el = math.radians(18), math.radians(24)
    direction = Vector((math.sin(yaw) * math.cos(el), -math.cos(yaw) * math.cos(el), math.sin(el)))
    co.location = center + direction * (size * 4)
    co.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
    sc.camera = co
    sc.render.filepath = os.path.join(out_dir, f"{name}.png")
    bpy.ops.render.render(write_still=True)
    print("rendered", name)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = os.path.abspath(argv[0] if argv else os.path.join(HERE, "render"))
    names = argv[1:] or (list(ICONS) + list(MODELS))
    os.makedirs(out_dir, exist_ok=True)
    for n in names:
        if n in MODELS:
            import models
            fn, tilt = MODELS[n]
            vox = getattr(models, fn)()[0]
            render_icon(n, 0, [], out_dir, vox=vox, tilt=tilt)
            continue
        depth, rows = ICONS[n]
        render_icon(n, depth, rows, out_dir)


main()
