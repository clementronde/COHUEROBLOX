"""COHUE — A03, exemples de gobelins dans le style du fantôme de Clément (5 nov. 2026).

Style choisi par Clément pour tous les ennemis : celui de son « Voxel Ghost » fait avec Claude Design, c'est-à-dire
des voxels lisses en SmoothPlastic, sans tenons ni texture, deux tons par couleur, et des yeux noirs avec un petit
reflet blanc (Neon).

    blender -b --factory-startup --python assets/a03/ghoststyle.py -- <dossier de sortie>

Rend : grunt (3 vues), eyes (3 variantes d'yeux), goblins (les 4 gobelins), horde (70 gobelins à la caméra du jeu).
Reprend les modèles de creatures.py et la scène de concept.py (A03), sans les modifier.
"""

from __future__ import annotations

import importlib.util
import math
import os
import random
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("a03_concept", os.path.join(HERE, "concept.py"))
K = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(K)

C, B, BD, S, cv, A14 = K.C, K.B, K.BD, K.S, K.cv, K.A14

# --------------------------------------------------------------------------------------------
# Matière lisse (SmoothPlastic) : couleurs par sommet, sans tenons

_smooth = None


def smooth_material():
    global _smooth
    if _smooth:
        return _smooth
    mat = bpy.data.materials.new("A03_SmoothPlastic")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Color"
    nt.links.new(vc.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.5
    _smooth = mat
    return mat


def smoothen(fn):
    """Remplace la matière à tenons de la maille fusionnée par la matière lisse."""
    body, parts, meta = K.build_template(fn, fused=True)
    body.data.materials.clear()
    body.data.materials.append(smooth_material())
    return body


# --------------------------------------------------------------------------------------------
# Variantes d'yeux sur les gobelins : noirs à reflet (comme le fantôme), blancs ronds, noirs avec joues

EYE_CELLS = ((2, 3), (-4, -3))       # colonnes x des deux yeux (2 de large, 3 de haut : ovales, pas des lunettes)


def ghost_eyes(base, cheeks=False):
    def fn():
        vox, origin, meta = base()
        meta = dict(meta)
        glints = []
        for (x0, x1) in EYE_CELLS:
            vox.box(x0, x1, -3, -3, 9, 11, "Ink")
            vox.box(x0, x1, -4, -4, 9, 11, "Ink")             # l'oeil dépasse d'un voxel, comme sur le fantôme
            glints.append((x0, -4, 11))
        if cheeks:
            vox.box(3, 4, -3, -3, 8, 8, "Tomato.l")
            vox.box(-5, -4, -3, -3, 8, 8, "Tomato.l")
        meta["eyes"] = []
        meta["glints"] = glints
        return vox, origin, meta
    fn.__name__ = base.__name__ + ("_ghost_cheeks" if cheeks else "_ghost")
    return fn


_wrapped: dict = {}


def wrapped(base, cheeks=False):
    key = (base, cheeks)
    if key not in _wrapped:
        _wrapped[key] = ghost_eyes(base, cheeks)
    return _wrapped[key]


def place(fn, loc, rot_z=0.0, scale=1.0, elite=False):
    smoothen(fn)
    ob = K.place(fn, loc, rot_z=rot_z, scale=scale, elite=elite, fused=True)
    vox, origin, meta = fn()
    o = K._origin(vox)
    cell = meta["cell"]
    for (x, y, z) in meta.get("glints", []):
        g = bpy.data.objects.new("Glint", A14._sphere_mesh("Glint", meta.get("glint_r", cell * 0.42), 4, 2))
        bpy.context.scene.collection.objects.link(g)
        g.data.materials.append(A14._solid_glow("FFFFFF", 3.0))
        g.scale = (1, 0.4, 1)
        g.location = ((x + 0.5 - o[0]) * cell, (y - o[1]) * cell - 0.02, (z + 0.5 - o[2]) * cell)
        g.parent = ob
    return ob


# --------------------------------------------------------------------------------------------
# Vues


def plinth(sc, w=44, d=20):
    K.light(sc)
    S.block("Plinth", (0, 0, -0.5), (w, d, 1), "Leaf.d", jitter=0.0)


def view_grunt(out):
    """Le Grunt dans le style du fantôme : de face, de trois-quarts, de profil."""
    sc = A14.fresh()
    plinth(sc)
    fn = wrapped(C.goblin_grunt)
    for k, (x, a) in enumerate(((-9.0, 0), (0.0, -35), (9.0, -90))):
        place(fn, (x, 0, 0), rot_z=math.radians(a))
    B.camera(sc, (0.0, -30.0, 8.0), (0.0, 0.0, 2.4), lens=42)
    A14.render(sc, out, res=(2400, 900), samples=64)


def view_eyes(out):
    """Trois têtes : yeux noirs à reflet (comme le fantôme), yeux blancs ronds, yeux noirs et joues roses."""
    sc = A14.fresh()
    plinth(sc, 30, 14)
    place(wrapped(C.goblin_grunt), (-8.0, 0, 0), rot_z=math.radians(8))
    place(C.goblin_grunt, (0.0, 0, 0), rot_z=math.radians(0))
    place(wrapped(C.goblin_grunt, cheeks=True), (8.0, 0, 0), rot_z=math.radians(-8))
    B.camera(sc, (0.0, -33.0, 7.5), (0.0, 0.0, 2.6), lens=50)
    A14.render(sc, out, res=(2400, 900), samples=64)


def view_goblins(out):
    sc = A14.fresh()
    plinth(sc)
    for k, base in enumerate(C.GOBLINS):
        place(wrapped(base), (-9.0 + k * 6.0, 0, 0), rot_z=math.radians(10 - 6 * k))
    B.camera(sc, (0.0, -30.0, 9.0), (0.0, 0.0, 2.6), lens=40)
    A14.render(sc, out, res=(2400, 900), samples=64)


def view_horde(out):
    sc = A14.fresh()
    K.light(sc)
    K.ground(sc, "grass", half=13, seed=5)
    K.edge_dressing(seed=4)
    player = (0.0, 6.0)
    BD.dressed("Knight", 3, player[0], y=player[1], rot=0.0)
    kinds = [C.goblin_grunt] * 34 + [C.goblin_archer] * 14 + [C.goblin_shaman] * 10 + [C.goblin_bomber] * 12
    random.Random(7).shuffle(kinds)
    rnd = random.Random(9)
    for k, (x, y) in enumerate(K.horde_points()):
        face = math.atan2(player[0] - x, -(player[1] - y))
        elite = k in (5, 23)
        place(wrapped(kinds[k]), (x, y, 0), rot_z=face + rnd.uniform(-0.3, 0.3), scale=1.3 if elite else 1.0,
              elite=elite)
    K.game_camera(sc, player)
    A14.render(sc, out, res=(1600, 900), samples=48)


VIEWS = {"grunt": view_grunt, "eyes": view_eyes, "goblins": view_goblins, "horde": view_horde}

if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:]
    outdir = os.path.abspath(argv[0])
    which = argv[1].split(",") if len(argv) > 1 else list(VIEWS)
    os.makedirs(outdir, exist_ok=True)
    for name in which:
        K._templates.clear()
        cam = bpy.data.cameras.get("A01_Cam")
        if cam:
            cam.sensor_fit = "AUTO"
        VIEWS[name](os.path.join(outdir, f"ghoststyle_{name}.png"))
