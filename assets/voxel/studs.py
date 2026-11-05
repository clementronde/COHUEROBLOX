"""COHUE — variante « tout en tenons, formes naturelles » (5 nov. 2026, A01).

Proposée à Clément après ses références « canyon en tenons » : une seule matière (plastique à tenons) pour
tout le jeu, le naturel venant des formes (falaises en gros blocs décalés, sapins en plaques inclinées,
eau, herbe en terrasses). Le décor est en gros blocs de 1 à 8 studs ; les éléments interactifs restent en
petites briques fines (brick.py), qui se distinguent par l'échelle et la couleur.

Les tenons sont une **texture** projetée en boîte (un tenon par stud du bloc), comme le plugin Resurface
les pose en jeu sur les Parts et, par MaterialVariant, sur les mailles. Textures : assets/voxel/tex/.
"""

from __future__ import annotations

import math
import os

from cohue_voxel import tone

HERE = os.path.dirname(os.path.abspath(__file__))
TEX = os.path.join(HERE, "tex")
_mats: dict = {}


def _h(*a) -> float:
    n = 2166136261
    for v in a:
        n = ((n ^ (int(v * 1000) & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF
    n ^= n >> 15
    return (n & 0xFFFF) / 65535.0


def stud_material(scale: float = 1.0, offset=(0.0, 0.0, 0.0), roughness: float = 0.5):
    """Matériau « plastique à tenons » : couleur par sommet × texture de tenons, relief par bump.
    scale = tenons par unité Blender (1 pour un bloc en studs, 4 pour des briques de 0,25)."""
    import bpy

    key = (round(scale, 3), tuple(round(o, 3) for o in offset))
    if key in _mats:
        return _mats[key]
    mat = bpy.data.materials.new(f"COHUE_Studs_{key[0]}_{key[1]}")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = roughness
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (scale, scale, scale)
    mp.inputs["Location"].default_value = offset
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    col = nt.nodes.new("ShaderNodeTexImage")
    col.image = bpy.data.images.load(os.path.join(TEX, "stud_color.png"), check_existing=True)
    col.image.colorspace_settings.name = "Non-Color"
    hgt = nt.nodes.new("ShaderNodeTexImage")
    hgt.image = bpy.data.images.load(os.path.join(TEX, "stud_height.png"), check_existing=True)
    hgt.image.colorspace_settings.name = "Non-Color"
    for t in (col, hgt):
        t.projection = "BOX"
        t.projection_blend = 0.0
        nt.links.new(mp.outputs["Vector"], t.inputs["Vector"])
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Color"
    mul = nt.nodes.new("ShaderNodeVectorMath")
    mul.operation = "MULTIPLY"
    nt.links.new(vc.outputs["Color"], mul.inputs[0])
    nt.links.new(col.outputs["Color"], mul.inputs[1])
    gain = nt.nodes.new("ShaderNodeVectorMath")
    gain.operation = "SCALE"
    gain.inputs["Scale"].default_value = 1.07
    nt.links.new(mul.outputs["Vector"], gain.inputs[0])
    nt.links.new(gain.outputs["Vector"], bsdf.inputs["Base Color"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.45
    bump.inputs["Distance"].default_value = 0.04 / scale
    nt.links.new(hgt.outputs["Color"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    _mats[key] = mat
    return mat


def apply(ob, scale=1.0, offset=(0.0, 0.0, 0.0)):
    ob.data.materials.clear()
    ob.data.materials.append(stud_material(scale, offset))
    return ob


def block(name, center, size, color, yaw=0.0, tilt=(0.0, 0.0), jitter=0.04):
    """Un bloc (une Part dans Studio) : géométrie de 0 à size depuis un coin, pour que les tenons tombent
    sur la grille du bloc, puis posé par son centre."""
    import bpy
    from mathutils import Euler, Vector

    sx, sy, sz = size
    verts = [(0, 0, 0), (sx, 0, 0), (sx, sy, 0), (0, sy, 0), (0, 0, sz), (sx, 0, sz), (sx, sy, sz), (0, sy, sz)]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    base = tone(color)
    j = 1.0 - jitter + 2 * jitter * _h(center[0], center[1], center[2])
    c = (min(1, base[0] * j), min(1, base[1] * j), min(1, base[2] * j), 1.0)
    attr = me.color_attributes.new("Color", "FLOAT_COLOR", "POINT")
    attr.data.foreach_set("color_srgb", list(c) * 8)
    me.color_attributes.active_color = attr
    me.materials.append(stud_material(1.0))
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    rot = Euler((math.radians(tilt[0]), math.radians(tilt[1]), yaw), "XYZ")
    ob.rotation_euler = rot
    half = Vector((sx / 2, sy / 2, sz / 2))
    half.rotate(rot)
    ob.location = Vector(center) - half
    return ob


def pine(name, loc, height=14.0, seed=0):
    """Sapin en plaques empilées, chacune un peu tournée et inclinée (image 1-2 de Clément)."""
    x, y, z = loc
    th = height * 0.22
    block(name + "_Trunk", (x, y, z + th / 2), (1.0, 1.0, th), "Bark")
    tiers = 4
    for i in range(tiers):
        w = height * (0.42 - 0.08 * i)
        hz = z + th + i * height * 0.17 + height * 0.06
        yaw = _h(seed, i, 1) * math.pi
        tilt = ((_h(seed, i, 2) - 0.5) * 16, (_h(seed, i, 3) - 0.5) * 16)
        col = "Leaf.d" if i % 2 == 0 else "Leaf"
        block(f"{name}_Tier{i}", (x, y, hz), (w, w, height * 0.13), col, yaw, tilt)
    block(name + "_Top", (x, y, z + th + tiers * height * 0.17 + height * 0.05),
          (height * 0.1, height * 0.1, height * 0.12), "Leaf")


def tree(name, loc, height=12.0, seed=0, autumn=False):
    """Feuillu en cubes : tronc, deux branches, 5 cubes de feuillage tournés."""
    x, y, z = loc
    th = height * 0.5
    block(name + "_Trunk", (x, y, z + th / 2), (1.2, 1.2, th), "Bark")
    for k in range(2):
        a = _h(seed, k, 4) * math.tau
        block(f"{name}_Branch{k}", (x + 0.9 * math.cos(a), y + 0.9 * math.sin(a), z + th * (0.75 + 0.15 * k)),
              (0.6, 0.6, 2.2), "Bark", a, (0, 35))
    cols = ["Ember.d", "Ember", "Gold.d"] if autumn else ["Leaf.d", "Leaf", "Leaf.l"]
    for i in range(5):
        a = i / 5 * math.tau + seed
        d = 0 if i == 0 else height * 0.2
        s = height * (0.36 - 0.05 * (i > 0)) * (0.85 + 0.3 * _h(seed, i, 5))
        cz = z + th + height * (0.18 + 0.12 * _h(seed, i, 6)) + (height * 0.12 if i == 0 else 0)
        block(f"{name}_Leaves{i}", (x + d * math.cos(a), y + d * math.sin(a), cz), (s, s, s * 0.8),
              cols[i % 3], _h(seed, i, 7) * math.pi, ((_h(seed, i, 8) - 0.5) * 20, (_h(seed, i, 9) - 0.5) * 20))


def bush(name, loc, size=2.5, seed=0):
    x, y, z = loc
    for i in range(3):
        a = i / 3 * math.tau + seed
        s = size * (0.6 + 0.3 * _h(seed, i, 10))
        block(f"{name}_{i}", (x + size * 0.35 * math.cos(a), y + size * 0.35 * math.sin(a), z + s * 0.35),
              (s, s, s * 0.7), "Leaf" if i % 2 else "Leaf.d", _h(seed, i, 11) * math.pi)


def rock(name, loc, size=3.0, seed=0, color="Stone.l"):
    x, y, z = loc
    block(name, (x, y, z + size * 0.25), (size, size * 0.8, size * 0.7), color, _h(seed, 1, 12) * math.pi,
          ((_h(seed, 2, 13) - 0.5) * 18, (_h(seed, 3, 14) - 0.5) * 18))


def slab(name, loc, size=2.0, seed=0, color="Leather.l"):
    x, y, z = loc
    block(name, (x, y, z), (size, size * (0.8 + 0.3 * _h(seed, 4, 15)), 0.5), color, _h(seed, 5, 16) * math.pi / 2,
          ((_h(seed, 6, 17) - 0.5) * 6, 0))


def mushroom(name, loc, seed=0):
    """Champignon rouge à pois (gag de décor des images de Clément), en blocs."""
    x, y, z = loc
    block(name + "_Stem", (x, y, z + 0.6), (0.8, 0.8, 1.2), "Cream")
    block(name + "_Cap", (x, y, z + 1.5), (2.2, 2.2, 0.9), "Tomato", _h(seed, 6, 18) * math.pi)


def water(name, center, rx, ry, z):
    """Plan d'eau (en jeu : eau du Terrain de Roblox)."""
    import bmesh
    import bpy

    import build as B

    mat = bpy.data.materials.get("COHUE_Water")
    if not mat:
        mat = bpy.data.materials.new("COHUE_Water")
        mat.use_nodes = True
        bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        bsdf.inputs["Base Color"].default_value = B.hexcol("2FA8D0")
        bsdf.inputs["Roughness"].default_value = 0.06
        bsdf.inputs["Emission Color"].default_value = B.hexcol("3FD0F5")
        bsdf.inputs["Emission Strength"].default_value = 0.15
    bm = bmesh.new()
    n = 40
    vs = [bm.verts.new((rx * math.cos(i / n * math.tau), ry * math.sin(i / n * math.tau), 0)) for i in range(n)]
    bm.faces.new(vs)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = (center[0], center[1], z)
    return ob
