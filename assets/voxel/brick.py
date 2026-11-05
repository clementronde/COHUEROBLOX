"""COHUE — style « briques à tenons » (refonte du 5 nov. 2026, A01).

Transforme une grille Vox en briques chanfreinées posées en quinconce, avec un tenon sur chaque dessus
de brique visible. On garde la modélisation sur grille (les mêmes fonctions de models.py et lobby.py),
seul le rendu change :
- une cellule de la grille = un tenon (largeur d'une brique de 1) ;
- les briques font 1 cellule de large et 1 à L cellules de long, alternées en X puis en Y d'une couche à
  l'autre, joints décalés d'une rangée sur l'autre (appareil de maçonnerie) ;
- chaque brique est un bloc chanfreiné (le chanfrein dessine le joint et accroche la lumière) ;
- tenon : cylindre de 60 % de la cellule, haut de 18 %, seulement sur les dessus libres ;
- couleur unie par brique, avec ±4 % de variation d'une brique à l'autre (pas de dégradé peint).

Utilisation : brick.to_blender a la même signature que cohue_voxel.to_blender, on peut donc la brancher
à sa place (lobby.build_scene le fait).
"""

from __future__ import annotations

import math

from cohue_voxel import VOXEL, tone

STUD_R = 0.30      # rayon du tenon (fraction de cellule)
STUD_H = 0.18      # hauteur du tenon
BEVEL = 0.07       # chanfrein des briques (fraction de cellule)
SEGMENTS = 10      # côtés d'un tenon

# Réglages par modèle (nom du Vox) : longueur maxi des briques, couleurs sans tenons (dalles lisses)
OPTIONS: dict[str, dict] = {}

# Tenons en texture (comme Resurface en jeu) plutôt qu'en géométrie : voir studs.py
STUD_TEXTURE = False


def _h(*a) -> float:
    n = 2166136261
    for v in a:
        n = ((n ^ (int(v) & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF
    n ^= n >> 15
    return (n & 0xFFFF) / 65535.0


def make_bricks(vox, maxlen: int = 3, smooth=frozenset()):
    """Liste de briques (x0, y0, z, lx, ly, couleur, tenons) en unités de cellule."""
    cells = vox.c

    def hidden(x, y, z):
        return ((x + 1, y, z) in cells and (x - 1, y, z) in cells and (x, y + 1, z) in cells
                and (x, y - 1, z) in cells and (x, y, z + 1) in cells and (x, y, z - 1) in cells)

    visible = {k for k in cells if not hidden(*k)}
    used: set = set()
    bricks = []
    for k in sorted(visible, key=lambda k: (k[2], k[1], k[0]) if k[2] % 2 == 0 else (k[2], k[0], k[1])):
        if k in used:
            continue
        x, y, z = k
        col = cells[k]
        along_x = z % 2 == 0
        row = y if along_x else x
        pos = x if along_x else y
        shift = (row + 2 * z) % maxlen          # joints décalés d'une rangée sur l'autre
        n = 1
        while n < maxlen and (pos + n + shift) % maxlen != 0:
            nk = (x + n, y, z) if along_x else (x, y + n, z)
            if nk not in visible or nk in used or cells[nk] != col:
                break
            n += 1
        members = [(x + i, y, z) if along_x else (x, y + i, z) for i in range(n)]
        used.update(members)
        studs = [m for m in members if (m[0], m[1], z + 1) not in cells and col not in smooth]
        lx, ly = (n, 1) if along_x else (1, n)
        bricks.append((x, y, z, lx, ly, col, studs))
    return bricks


def mesh_lists(vox, origin, voxel: float = VOXEL):
    opt = OPTIONS.get(vox.name, {})
    lo, hi = vox.bounds()
    if origin == "bottom":
        o = ((lo[0] + hi[0] + 1) / 2, (lo[1] + hi[1] + 1) / 2, lo[2])
    elif origin == "center":
        o = tuple((lo[i] + hi[i] + 1) / 2 for i in range(3))
    else:
        o = origin
    verts, faces, vcols = [], [], []
    ring = [(math.cos(i / SEGMENTS * math.tau), math.sin(i / SEGMENTS * math.tau)) for i in range(SEGMENTS)]
    for (x, y, z, lx, ly, col, studs) in make_bricks(vox, opt.get("maxlen", 3), opt.get("smooth", frozenset())):
        base = tone(col)
        j = 0.96 + 0.08 * _h(x, y, z, 7)
        c = (min(1.0, base[0] * j), min(1.0, base[1] * j), min(1.0, base[2] * j), 1.0)
        x0, y0, z0 = (x - o[0]) * voxel, (y - o[1]) * voxel, (z - o[2]) * voxel
        x1, y1, z1 = x0 + lx * voxel, y0 + ly * voxel, z0 + voxel
        b = len(verts)
        verts += [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
                  (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
        faces += [(b, b + 3, b + 2, b + 1), (b + 4, b + 5, b + 6, b + 7), (b, b + 1, b + 5, b + 4),
                  (b + 1, b + 2, b + 6, b + 5), (b + 2, b + 3, b + 7, b + 6), (b + 3, b, b + 4, b + 7)]
        vcols += [c] * 8
        for (sx, sy, _) in ([] if STUD_TEXTURE else studs):
            cx, cy = (sx + 0.5 - o[0]) * voxel, (sy + 0.5 - o[1]) * voxel
            r, h = STUD_R * voxel, STUD_H * voxel
            b = len(verts)
            for (ux, uy) in ring:
                verts.append((cx + ux * r, cy + uy * r, z1))
            for (ux, uy) in ring:
                verts.append((cx + ux * r, cy + uy * r, z1 + h))
            verts.append((cx, cy, z1 + h))
            vcols += [c] * (2 * SEGMENTS + 1)
            for i in range(SEGMENTS):
                i2 = (i + 1) % SEGMENTS
                faces.append((b + i, b + i2, b + SEGMENTS + i2, b + SEGMENTS + i))
                faces.append((b + SEGMENTS + i, b + SEGMENTS + i2, b + 2 * SEGMENTS))
    return verts, faces, vcols, o


def brick_material():
    import bpy

    mat = bpy.data.materials.get("COHUE_Brick")
    if mat:
        return mat
    mat = bpy.data.materials.new("COHUE_Brick")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Color"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.42                  # plastique de jouet, pas mat
    return mat


def to_blender(vox, origin="bottom", name: str | None = None, collection=None, voxel: float = VOXEL):
    import bpy

    verts, faces, vcols, o = mesh_lists(vox, origin, voxel)
    name = name or vox.name
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    attr = me.color_attributes.new("Color", "FLOAT_COLOR", "POINT")
    attr.data.foreach_set("color_srgb", [v for c in vcols for v in c])   # tons de palette en sRGB
    me.color_attributes.active_color = attr
    me.color_attributes.render_color_index = me.color_attributes.find("Color")
    if STUD_TEXTURE:
        import studs

        me.materials.append(studs.stud_material(1.0 / voxel, tuple(v % 1.0 for v in o)))
    else:
        me.materials.append(brick_material())
    ob = bpy.data.objects.new(name, me)
    (collection or bpy.context.scene.collection).objects.link(ob)
    mod = ob.modifiers.new("Joints", "BEVEL")
    mod.width = BEVEL * voxel
    mod.segments = 1
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(40)
    ob["tris"] = sum(2 if len(f) == 4 else 1 for f in faces)
    return ob
