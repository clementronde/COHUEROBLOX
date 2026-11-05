"""COHUE — construction, export et rendus des modèles voxel dans Blender 5.2 (A01).

Dans Blender (console ou MCP) :
    import sys; sys.path.append(r"<repo>/assets/voxel")
    import importlib, build; importlib.reload(build); build.export_all()

En ligne de commande :
    blender -b --factory-startup --python assets/voxel/build.py -- export
"""

from __future__ import annotations

import importlib
import json
import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.append(HERE)

import cohue_voxel as cv  # noqa: E402
import models as M  # noqa: E402

importlib.reload(cv)
importlib.reload(M)

GLB_DIR = os.path.join(HERE, "glb")
LUAU_DIR = os.path.join(HERE, "luau")
SCENE = "COHUE_A01"


# ---------------------------------------------------------------------------------------------
# Scène de travail (on ne touche jamais à la scène de l'utilisateur)


def work_scene(name: str = SCENE):
    sc = bpy.data.scenes.get(name) or bpy.data.scenes.new(name)
    if bpy.context.window:
        bpy.context.window.scene = sc
    sc.unit_settings.system = "NONE"          # 1 unité = 1 stud
    sc.view_settings.view_transform = "Standard"  # couleurs de palette fidèles (pas d'AgX)
    try:
        sc.view_settings.look = "None"
    except TypeError:
        pass
    return sc


def collection(name: str, sc=None):
    sc = sc or bpy.context.scene
    col = bpy.data.collections.get(name)
    if not col:
        col = bpy.data.collections.new(name)
    if col.name not in sc.collection.children:
        sc.collection.children.link(col)
    return col


def clear(col):
    for ob in list(col.objects):
        me = ob.data if ob.type == "MESH" else None
        bpy.data.objects.remove(ob, do_unlink=True)
        if me and me.users == 0:
            bpy.data.meshes.remove(me)


# ---------------------------------------------------------------------------------------------
# Export


def roblox_offsets(vox, origin):
    """Position du point d'origine (attache) par rapport au centre de la boîte englobante, en studs,
    dans les axes Roblox (export glTF +Y up puis import Roblox : (x, y, z) Blender -> (-x, z, y))."""
    lo, hi = vox.bounds()
    if origin == "bottom":
        o = ((lo[0] + hi[0] + 1) / 2, (lo[1] + hi[1] + 1) / 2, lo[2])
    elif origin == "center":
        o = tuple((lo[i] + hi[i] + 1) / 2 for i in range(3))
    else:
        o = origin
    centre = [((lo[i] + hi[i] + 1) / 2 - o[i]) * cv.VOXEL for i in range(3)]
    rb_centre = (-centre[0], centre[2], centre[1])
    return [round(-c, 4) for c in rb_centre]


def export_all(fns=None):
    """Exporte les livrables. À lancer en ligne de commande (voir l'en-tête) : scène vierge, aucun
    risque pour un Blender ouvert."""
    sc = bpy.context.scene
    for ob in list(sc.objects):
        if ob.name in ("Cube", "Camera", "Light"):
            bpy.data.objects.remove(ob, do_unlink=True)
    col = collection("A01_Export", sc)
    clear(col)
    os.makedirs(GLB_DIR, exist_ok=True)
    os.makedirs(LUAU_DIR, exist_ok=True)
    manifest = []
    for fn in fns or M.DELIVERABLES:
        vox, origin, meta = fn()
        ob = cv.to_blender(vox, origin, collection=col)
        path = os.path.join(GLB_DIR, vox.name + ".glb")
        cv.export_glb(ob, path)
        with open(os.path.join(LUAU_DIR, vox.name + ".json"), "w", encoding="utf-8") as f:
            f.write(cv.luau_mesh(vox, origin))
        size = vox.size_studs()
        if "neon_core_at" in meta:
            meta = {**meta, "neon_core_from_center": roblox_offsets(vox, tuple(meta["neon_core_at"]))}
        manifest.append({
            "name": vox.name,
            "tris": ob["tris"],
            "voxels": len(vox.c),
            # Taille Roblox (X, Y, Z) = Blender (X, Z, Y)
            "size": [size[0], size[2], size[1]],
            "attach_from_center": roblox_offsets(vox, origin),
            "colors": vox.colors_used(),
            "glb_bytes": os.path.getsize(path),
            **meta,
        })
    with open(os.path.join(HERE, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1, ensure_ascii=False)
    # Aperçus Studio seulement (pas de GLB) : décor et ébauches
    for fn in M.PROPS + M.BLOCKOUTS:
        vox, origin, meta = fn()
        with open(os.path.join(LUAU_DIR, vox.name + ".json"), "w", encoding="utf-8") as f:
            f.write(cv.luau_mesh(vox, origin))
    with open(os.path.join(LUAU_DIR, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False)
    return manifest


# ---------------------------------------------------------------------------------------------
# Lumière et rendus


def hexcol(h, a=1.0):
    r, g, b = cv.hex_rgb(h)
    # sRGB -> linéaire pour les entrées de nœuds
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in (r, g, b)]
    return (*lin, a)


def diorama_light(sc, sun_elev=38, sun_az=-35, strength=3.2, world="F3E3C8", world_strength=0.9):
    """Lumière « diorama » : soleil chaud bas, ciel ambiant crème, ombres douces."""
    col = collection("A01_Light", sc)
    clear(col)
    sun_data = bpy.data.lights.get("A01_Sun") or bpy.data.lights.new("A01_Sun", "SUN")
    sun_data.energy = strength
    sun_data.color = cv.hex_rgb("FFE2B0")
    sun_data.angle = math.radians(4)
    sun = bpy.data.objects.new("A01_Sun", sun_data)
    sun.rotation_euler = (math.radians(90 - sun_elev), 0, math.radians(sun_az))
    col.objects.link(sun)
    w = sc.world or bpy.data.worlds.new("A01_World")
    sc.world = w
    w.use_nodes = True
    bg = next(n for n in w.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = hexcol(world)
    bg.inputs[1].default_value = world_strength
    sc.render.engine = "BLENDER_EEVEE"
    ee = sc.eevee
    for attr, val in (("use_shadows", True), ("shadow_ray_count", 2), ("use_raytracing", True),
                      ("fast_gi_distance", 2.0), ("use_fast_gi", True)):
        if hasattr(ee, attr):
            try:
                setattr(ee, attr, val)
            except Exception:
                pass
    return sun


def camera(sc, loc, target, ortho=None, lens=50, dof=None):
    cam_data = bpy.data.cameras.get("A01_Cam") or bpy.data.cameras.new("A01_Cam")
    cam = bpy.data.objects.get("A01_Cam") or bpy.data.objects.new("A01_Cam", cam_data)
    if cam.name not in sc.collection.objects:
        sc.collection.objects.link(cam)
    from mathutils import Vector

    cam.location = loc
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    if ortho:
        cam_data.type = "ORTHO"
        cam_data.ortho_scale = ortho
    else:
        cam_data.type = "PERSP"
        cam_data.lens = lens
    cam_data.dof.use_dof = bool(dof)
    if dof:
        cam_data.dof.focus_distance = dof[0]
        cam_data.dof.aperture_fstop = dof[1]
    cam_data.clip_end = 2000
    sc.camera = cam
    return cam


def place(fn, loc, rot_z=0.0, col=None, name=None):
    vox, origin, meta = fn() if callable(fn) else fn
    ob = cv.to_blender(vox, origin, name=name, collection=col)
    ob.location = loc
    ob.rotation_euler = (0, 0, rot_z)
    return ob, vox, meta


def render(sc, path, res=(1600, 900), transparent=False, samples=32):
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = transparent
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA" if transparent else "RGB"
    if hasattr(sc.eevee, "taa_render_samples"):
        sc.eevee.taa_render_samples = samples
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True, scene=sc.name)
    return path


def silhouette_mode(sc, on: bool):
    """Rendu en aplat noir (test de silhouette) via Workbench."""
    if on:
        sc.render.engine = "BLENDER_WORKBENCH"
        sh = sc.display.shading
        sh.light = "FLAT"
        sh.color_type = "SINGLE"
        sh.single_color = (0.02, 0.02, 0.03)
        sh.show_shadows = False
        sh.show_cavity = False
        sh.show_object_outline = False
    else:
        sc.render.engine = "BLENDER_EEVEE"


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not argv or argv[0] == "export":
        for row in export_all():
            print(row["name"], row["tris"], row["size"], row["attach_from_center"])
