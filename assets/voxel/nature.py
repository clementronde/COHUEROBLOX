"""COHUE — décor naturel des maquettes (5 nov. 2026, A01).

Retour de Clément : « j'aime que la map soit plus naturelle et que les éléments interactifs soient en
briques ». Le décor (sol, falaises, arbres, buissons, rochers, îlots) est donc lisse et peint ; seuls les
éléments avec lesquels on interagit (portail, pads, stations) restent en briques (brick.py).

Style du décor naturel :
- formes douces et arrondies, sans briques ni tenons ;
- feuillage en grosses boules un peu bosselées, peint en dégradé : sombre dessous, clair dessus ;
- rochers à facettes (ombrage plat), mousse sur le dessus ;
- couleurs tirées de la palette COHUE 16, avec des fondus doux entre ses tons (autorisés pour le décor
  naturel seulement).

Tout se construit avec bmesh dans Blender 5.2 ; les couleurs sont par sommet (attribut « Color »).
"""

from __future__ import annotations

import math

from cohue_voxel import tone


def h3(x: float, y: float, z: float, s: int = 0) -> float:
    n = (int(math.floor(x * 7.0)) * 374761393 + int(math.floor(y * 7.0)) * 668265263
         + int(math.floor(z * 7.0)) * 2246822519 + s * 1442695041) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def mixc(a, b, t: float):
    t = max(0.0, min(1.0, t))
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def smoothstep(a: float, b: float, x: float) -> float:
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def nature_material():
    import bpy

    mat = bpy.data.materials.get("COHUE_Nature")
    if mat:
        return mat
    mat = bpy.data.materials.new("COHUE_Nature")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Color"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.9                   # mat, peint
    return mat


def mesh_object(name, verts, faces, cols, loc=(0, 0, 0), rot=0.0, smooth=True, smooth_faces=None):
    """Objet Blender à partir de listes (couleurs sRGB par sommet)."""
    import bpy

    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    attr = me.color_attributes.new("Color", "FLOAT_COLOR", "POINT")
    attr.data.foreach_set("color_srgb", [v for c in cols for v in (c[0], c[1], c[2], 1.0)])
    me.color_attributes.active_color = attr
    me.color_attributes.render_color_index = me.color_attributes.find("Color")
    for i, p in enumerate(me.polygons):
        p.use_smooth = smooth if smooth_faces is None else smooth_faces(i)
    me.materials.append(nature_material())
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = (0, 0, rot)
    return ob


def bm_object(name, bm, colfn, loc=(0, 0, 0), rot=0.0, smooth=True):
    verts = [tuple(v.co) for v in bm.verts]
    faces = [tuple(v.index for v in f.verts) for f in bm.faces]
    bm.free()
    cols = [colfn(*v) for v in verts]
    return mesh_object(name, verts, faces, cols, loc, rot, smooth)


def _blob(bm, bmesh, center, radius, squash=0.85, seed=0, bump=0.08, subdiv=2):
    res = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=radius)
    for v in res["verts"]:
        k = 1.0 + bump * (h3(v.co.x / radius, v.co.y / radius, v.co.z / radius, seed) - 0.5) * 2
        v.co.x *= k
        v.co.y *= k
        v.co.z *= k * squash
        v.co.x += center[0]
        v.co.y += center[1]
        v.co.z += center[2]
    return res["verts"]


def tree(name, loc, height=12.0, seed=0, autumn=False, rot=0.0):
    """Feuillu peint : tronc conique un peu tordu, 5 à 7 boules de feuillage, dégradé vertical."""
    import bmesh

    bm = bmesh.new()
    trunk_h = height * 0.55
    r0 = 0.12 * height ** 0.9 * 0.5
    lean = (h3(seed, 1, 2) - 0.5) * height * 0.12
    res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=8, radius1=r0 * 1.6,
                                radius2=r0 * 0.7, depth=trunk_h)
    for v in res["verts"]:
        t = (v.co.z + trunk_h / 2) / trunk_h
        v.co.z += trunk_h / 2
        v.co.x += lean * t * t
    trunk_top = (lean, 0.0, trunk_h)
    trunk = bm_object(name + "_Trunk", bm, lambda x, y, z: mixc(tone("Bark.d"), tone("Bark"), z / trunk_h),
                      loc, rot, smooth=True)
    bm = bmesh.new()
    crown_r = height * 0.32
    n = 5 + seed % 3
    lo_z = trunk_top[2] + crown_r * 0.3
    for i in range(n):
        a = i / n * math.tau + seed
        d = crown_r * (0.55 if i else 0.0)
        cz = lo_z + crown_r * (0.35 + 0.5 * h3(i, seed, 3)) + (crown_r * 0.45 if i == 0 else 0)
        rr = crown_r * (0.62 + 0.25 * h3(seed, i, 4))
        _blob(bm, bmesh, (trunk_top[0] + d * math.cos(a), d * math.sin(a), cz), rr, seed=seed + i)
    top = lo_z + crown_r * 1.7
    if autumn:
        dark, mid, light = tone("Ember.d"), tone("Ember"), tone("Gold")
    else:
        dark, mid, light = tone("Leaf.dd"), tone("Leaf"), tone("Leaf.l")

    def leaf(x, y, z):
        t = (z - (lo_z - crown_r * 0.4)) / (top - (lo_z - crown_r * 0.4))
        c = mixc(dark, mid, smoothstep(0.0, 0.55, t))
        return mixc(c, light, smoothstep(0.6, 1.0, t) * 0.8)

    crown = bm_object(name + "_Crown", bm, leaf, loc, rot, smooth=True)
    return trunk, crown


def pine(name, loc, height=14.0, seed=0, rot=0.0):
    """Sapin peint : 4 cônes empilés, dégradé du pied (sombre) à la pointe (claire)."""
    import bmesh

    bm = bmesh.new()
    res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=8, radius1=height * 0.05,
                                radius2=height * 0.04, depth=height * 0.25)
    for v in res["verts"]:
        v.co.z += height * 0.125
    trunk = bm_object(name + "_Trunk", bm, lambda x, y, z: tone("Bark.d"), loc, rot)
    bm = bmesh.new()
    tiers = 4
    for i in range(tiers):
        r = height * (0.3 - 0.06 * i)
        d = height * 0.32
        z0 = height * (0.18 + 0.19 * i)
        res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=10, radius1=r, radius2=0.0, depth=d)
        for v in res["verts"]:
            v.co.z += z0 + d / 2
            k = 1.0 + 0.1 * (h3(v.co.x, v.co.y, v.co.z, seed + i) - 0.5)
            v.co.x *= k
            v.co.y *= k

    def col(x, y, z):
        t = z / height
        return mixc(mixc(tone("Leaf.dd"), tone("Leaf.d"), smoothstep(0.1, 0.5, t)), tone("Leaf"), smoothstep(0.5, 1.0, t))

    crown = bm_object(name + "_Crown", bm, col, loc, rot, smooth=False)
    return trunk, crown


def bush(name, loc, size=3.0, seed=0, rot=0.0, flowers=False):
    import bmesh

    bm = bmesh.new()
    for i in range(3):
        a = i / 3 * math.tau + seed
        _blob(bm, bmesh, (size * 0.45 * math.cos(a), size * 0.45 * math.sin(a), size * 0.35),
              size * (0.55 + 0.15 * h3(i, seed, 5)), squash=0.75, seed=seed + i)
    dots = []
    if flowers:
        for i in range(7):
            a = h3(i, seed, 6) * math.tau
            dots.append((size * 0.7 * math.cos(a), size * 0.7 * math.sin(a), size * (0.45 + 0.3 * h3(seed, i, 7))))
    fcol = [tone("Cream"), tone("Grape.l"), tone("Tomato.l")][seed % 3]

    def col(x, y, z):
        for d in dots:
            if (x - d[0]) ** 2 + (y - d[1]) ** 2 + (z - d[2]) ** 2 < (size * 0.18) ** 2:
                return fcol
        return mixc(tone("Leaf.dd"), tone("Leaf"), smoothstep(0.0, size * 0.9, z))

    return bm_object(name, bm, col, loc, rot, smooth=True)


def rock(name, loc, scale=(3.0, 2.5, 2.0), seed=0, rot=0.0, moss=True, sink=0.25):
    """Rocher à facettes (ombrage plat), mousse sur le dessus."""
    import bmesh

    bm = bmesh.new()
    res = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
    for v in res["verts"]:
        k = 1.0 + 0.32 * (h3(v.co.x, v.co.y, v.co.z, seed) - 0.5)
        v.co.x *= k * scale[0]
        v.co.y *= k * scale[1]
        v.co.z = v.co.z * k * scale[2] + scale[2] * (1 - sink)
    zmax = scale[2] * (2 - sink)

    def col(x, y, z):
        t = z / zmax
        c = mixc(tone("Stone.dd"), tone("Stone"), smoothstep(0.0, 0.7, t))
        c = mixc(c, tone("Stone.l"), smoothstep(0.7, 1.0, t) * 0.6)
        if moss and t > 0.82 and h3(x, y, 1.0, seed + 9) > 0.35:
            c = tone("Leaf.d")
        return c

    return bm_object(name, bm, col, loc, rot, smooth=False)


def stepping_stone(name, loc, size=1.4, seed=0, rot=0.0):
    return rock(name, loc, (size, size * 0.8, 0.22), seed, rot, moss=False, sink=0.6)


def islet(name, loc, size=6.0, seed=0):
    """Îlot flottant : rocher en cône, chapeau d'herbe, un arbre."""
    import bmesh

    bm = bmesh.new()
    res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=9, radius1=0.2 * size,
                                radius2=size, depth=size * 1.3)
    for v in res["verts"]:
        k = 1.0 + 0.25 * (h3(v.co.x / size, v.co.y / size, v.co.z / size, seed) - 0.5)
        v.co.x *= k
        v.co.y *= k
        v.co.z -= size * 0.65
    base = bm_object(name + "_Rock", bm, lambda x, y, z: mixc(tone("Stone.dd"), tone("Bark"),
                                                                smoothstep(-size * 1.2, 0.0, z)), loc, smooth=False)
    bm = bmesh.new()
    _blob(bm, bmesh, (0, 0, 0.1), size * 1.02, squash=0.18, seed=seed)
    cap = bm_object(name + "_Grass", bm, lambda x, y, z: tone("Leaf"), loc, smooth=True)
    tree(name + "_Tree", (loc[0], loc[1], loc[2] + 0.2), height=size * 1.4, seed=seed)
    return base, cap
