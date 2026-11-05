"""COHUE — A03, gobelin en formes lisses (5 nov. 2026).

Retour de Clément : les gobelins en voxels sont « trop pixelisés ». Ici, le même gobelin (tête ronde, oreilles relevées
en biais, nez pointu, sourire à dents, petite marmite en casque, cuillère en bois) en formes lisses, deux finitions :
- arrondie (ombrage doux, beaucoup de segments) : figurine en vinyle, personnage Roblox ;
- low poly (facettes plates, peu de segments).

    blender -b --factory-startup --python assets/a03/goblin_smooth.py -- <dossier de sortie>
"""

from __future__ import annotations

import importlib.util
import math
import os
import sys

import bpy
from mathutils import Euler, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("a03_concept", os.path.join(HERE, "concept.py"))
K = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(K)
B, A14, S, cv = K.B, K.A14, K.S, K.cv

HEX = {
    "skin": "8FD13F", "skin_d": "6C923E", "red": "E63946", "red_d": "A42F43", "ink": "1C1726",
    "glint": "FFFFFF", "cheek": "EF7A79", "mouth": "37274D", "tooth": "FFE8B8", "wood": "B5713A",
    "wood_d": "6E4227", "shoe": "6E4227",
}
_mats: dict = {}


def mat(key):
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new("A03_" + key)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = B.hexcol(HEX[key])
    bsdf.inputs["Roughness"].default_value = 0.42
    if key == "glint":
        bsdf.inputs["Emission Color"].default_value = B.hexcol("FFFFFF")
        bsdf.inputs["Emission Strength"].default_value = 3.0
    _mats[key] = m
    return m


class Builder:
    def __init__(self, root: Vector, smooth: bool):
        self.root = root
        self.smooth = smooth
        self.seg = 32 if smooth else 9
        self.ring = 16 if smooth else 6
        self.objs = []

    def _finish(self, ob, key, loc, scale, rot):
        ob.location = self.root + Vector(loc)
        ob.scale = scale
        ob.rotation_euler = Euler([math.radians(a) for a in rot])
        for p in ob.data.polygons:
            p.use_smooth = self.smooth
        ob.data.materials.append(mat(key))
        self.objs.append(ob)
        return ob

    def sphere(self, key, loc, scale, rot=(0, 0, 0)):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=self.seg, ring_count=self.ring, radius=1.0)
        return self._finish(bpy.context.active_object, key, loc, scale, rot)

    def cone(self, key, loc, r1, r2, depth, rot=(0, 0, 0), scale=(1, 1, 1)):
        bpy.ops.mesh.primitive_cone_add(vertices=self.seg, radius1=r1, radius2=r2, depth=depth)
        return self._finish(bpy.context.active_object, key, loc, scale, rot)

    def cyl(self, key, loc, r, depth, rot=(0, 0, 0), scale=(1, 1, 1)):
        bpy.ops.mesh.primitive_cylinder_add(vertices=self.seg, radius=r, depth=depth)
        return self._finish(bpy.context.active_object, key, loc, scale, rot)

    def torus(self, key, loc, R, r, rot=(0, 0, 0), scale=(1, 1, 1)):
        bpy.ops.mesh.primitive_torus_add(major_segments=self.seg, minor_segments=max(6, self.ring // 2),
                                         major_radius=R, minor_radius=r)
        return self._finish(bpy.context.active_object, key, loc, scale, rot)

    def box(self, key, loc, size, rot=(0, 0, 0)):
        bpy.ops.mesh.primitive_cube_add(size=1.0)
        ob = bpy.context.active_object
        bev = ob.modifiers.new("Bevel", "BEVEL")
        bev.width = min(size) * 0.25
        bev.segments = 3 if self.smooth else 1
        return self._finish(ob, key, loc, size, rot)


def goblin(root, smooth=True, yaw=0.0):
    """Gobelin de 4,5 studs, face vers -Y (Blender) = -Z (Roblox)."""
    g = Builder(Vector((0, 0, 0)), smooth)
    # Jambes et chaussures
    for sx in (1, -1):
        g.cyl("skin_d", (0.32 * sx, 0, 0.42), 0.17, 0.55)
        g.sphere("shoe", (0.32 * sx, -0.1, 0.13), (0.24, 0.32, 0.15))
    # Ventre rond (tunique), ceinture
    g.sphere("red", (0, 0, 1.2), (0.78, 0.66, 0.72))
    g.torus("wood_d", (0, 0, 1.02), 0.7, 0.07, scale=(1, 0.86, 1))
    # Bras et mains
    g.cyl("skin", (0.78, -0.05, 1.25), 0.15, 0.6, rot=(0, -18, 0))
    g.sphere("skin_d", (0.88, -0.1, 0.92), (0.18, 0.18, 0.18))
    g.cyl("skin", (-0.78, -0.05, 1.35), 0.15, 0.6, rot=(0, 30, 0))
    g.sphere("skin_d", (-0.95, -0.18, 1.08), (0.19, 0.19, 0.19))
    # Tête ronde, oreilles relevées en biais
    g.sphere("skin", (0, 0, 2.55), (1.02, 0.92, 0.9))
    for sx in (1, -1):
        g.cone("skin", (1.35 * sx, 0, 2.85), 0.36, 0.02, 1.15, rot=(0, 62 * sx, 0), scale=(1, 0.42, 1))
        g.cone("skin_d", (1.33 * sx, -0.08, 2.84), 0.2, 0.01, 0.85, rot=(0, 62 * sx, 0), scale=(1, 0.2, 1))
    # Visage : yeux noirs à reflet, sourcils en biais, nez pointu, joues, sourire à dents
    for sx in (1, -1):
        g.sphere("ink", (0.36 * sx, -0.8, 2.7), (0.17, 0.08, 0.22))
        g.sphere("glint", (0.31 * sx, -0.87, 2.8), (0.05, 0.02, 0.05))
        g.box("skin_d", (0.4 * sx, -0.84, 3.0), (0.32, 0.08, 0.08), rot=(0, 18 * sx, 0))
        g.sphere("cheek", (0.6 * sx, -0.72, 2.42), (0.13, 0.04, 0.07))
    g.cone("skin", (0, -1.0, 2.55), 0.13, 0.02, 0.42, rot=(-90, 0, 0))
    g.sphere("mouth", (0, -0.82, 2.2), (0.32, 0.08, 0.12))
    for x in (-0.16, 0.0, 0.16):
        g.box("tooth", (x, -0.89, 2.28), (0.07, 0.04, 0.08))
    # Petite marmite rouge en casque : corps, rebord, bouton, anses
    g.cyl("red", (0, 0, 3.45), 0.78, 0.5)
    g.torus("red_d", (0, 0, 3.22), 0.8, 0.07)
    g.sphere("red_d", (0, 0, 3.72), (0.72, 0.72, 0.1))
    g.sphere("ink", (0, 0, 3.85), (0.1, 0.1, 0.09))
    for sx in (1, -1):
        g.torus("ink", (0.86 * sx, 0, 3.45), 0.1, 0.035, rot=(90, 0, 0))
    # Cuillère en bois (main droite, -X)
    g.cyl("wood", (-0.98, -0.2, 1.75), 0.05, 1.5, rot=(8, 0, 0))
    g.sphere("wood", (-0.98, -0.3, 2.6), (0.2, 0.08, 0.27))
    # Rassemble sous un parent et place
    root_ob = bpy.data.objects.new("Goblin", None)
    bpy.context.scene.collection.objects.link(root_ob)
    for ob in g.objs:
        ob.parent = root_ob
    root_ob.location = root
    root_ob.rotation_euler = (0, 0, math.radians(yaw))
    return root_ob


def main(outdir):
    os.makedirs(outdir, exist_ok=True)
    sc = A14.fresh()
    K.light(sc)
    S.block("Plinth", (0, 0, -0.5), (30, 14, 1), "Leaf.d", jitter=0.0)
    goblin(Vector((-5.0, 0, 0)), smooth=True, yaw=12)
    goblin(Vector((0.0, 0, 0)), smooth=True, yaw=-35)
    goblin(Vector((5.0, 0, 0)), smooth=False, yaw=12)
    B.camera(sc, (0.0, -19.0, 4.6), (0.0, 0.0, 2.1), lens=46)
    A14.render(sc, os.path.join(outdir, "smooth_goblins.png"), res=(2400, 1000), samples=64)


if __name__ == "__main__":
    main(os.path.abspath(sys.argv[sys.argv.index("--") + 1]))
