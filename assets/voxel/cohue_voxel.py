"""COHUE — outil voxel (A01, direction artistique).

Le cœur (palette, grille de voxels, maillage glouton) est du Python pur, testable hors de Blender.
La construction, l'export GLB et les rendus utilisent bpy (Blender 5.2).

Conventions (voir docs/dossier/80-direction-artistique.md) :
- 1 unité Blender = 1 stud ; un voxel = VOXEL = 0,25 stud (4 voxels par stud).
- Z vers le haut, le modèle regarde vers -Y (l'avant dans Roblox après l'export glTF +Y up).
- Un voxel (x, y, z) occupe [x, x+1[ × [y, y+1[ × [z, z+1[ en unités de voxel.
- Symétrie gauche/droite autour du plan x = 0 : la colonne x a pour miroir -1-x.
- Couleurs : clés de la palette COHUE 16, avec suffixes de ton ".l" (clair), ".d" (ombre), ".dd" (ombre
  profonde). Les couleurs vont dans les couleurs par sommet (aucune texture).
"""

from __future__ import annotations

import json
import math
from collections import defaultdict

VOXEL = 0.25

# Palette COHUE 16 (sRGB). Ne pas ajouter de couleur hors de cette liste : utiliser les tons.
PALETTE: dict[str, str] = {
    "Ink": "1C1726",       # contours, yeux, coutures
    "Plum": "4B3866",      # ombres froides, tissu sombre
    "Bark": "6E4227",      # bois sombre, cuir foncé
    "Leather": "B5713A",   # cuir, bois clair, corde
    "Cream": "FFE8B8",     # blancs chauds, dents, papier, reflets des yeux
    "Stone": "9C9488",     # pierre, os, gris neutre chaud
    "Steel": "8EA6C2",     # métal
    "Gold": "FFC21A",      # or, élites, pièces (réservé aux bordures et récompenses)
    "Ember": "FF7A1A",     # orange, feu
    "Tomato": "E63946",    # rouge, danger, tissu gobelin
    "Bubblegum": "FF5FB0", # rose : capture (réservé) et gags
    "Grape": "8C52E0",     # violet, magie
    "Royal": "2D6BE6",     # bleu roi (Knight)
    "Sky": "3FD0F5",       # cyan : eau, XP, magie froide
    "Leaf": "3DBE4A",      # vert feuillage (Archer, forêt)
    "Lime": "A6E03A",      # peau des gobelins
}

LIGHT_HEX = "FFF4D8"   # lumière chaude du diorama
SHADOW_HEX = "2A1C3D"  # ombre violette froide

TONE_MIX = {"": None, "l": ("light", 0.35), "d": ("shadow", 0.35), "dd": ("shadow", 0.60)}

# Teinte cuite par direction de face (n'empêche pas la fusion gloutonne : même valeur pour toute la face).
# Clé : (axe, sens) ; axe 0 = X, 1 = Y, 2 = Z.
FACE_TONE = {
    (2, 1): ("light", 0.12),    # dessus : un peu de lumière chaude
    (2, -1): ("shadow", 0.40),  # dessous : ombre
    (1, 1): ("shadow", 0.08),   # dos (+Y)
    (1, -1): None,              # face avant
    (0, 1): None,
    (0, -1): ("shadow", 0.04),
}


def hex_rgb(h: str) -> tuple[float, float, float]:
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))  # type: ignore[return-value]


def rgb_hex(c) -> str:
    return "".join(f"{max(0, min(255, round(v * 255))):02X}" for v in c[:3])


def mix(a, b, t: float):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


LIGHT = hex_rgb(LIGHT_HEX)
SHADOW = hex_rgb(SHADOW_HEX)


def _apply(c, rule):
    if not rule:
        return c
    kind, t = rule
    return mix(c, LIGHT if kind == "light" else SHADOW, t)


def tone(key: str):
    """'Leather' -> sRGB ; 'Leather.d' -> ombre ; 'Leather.l' -> clair ; 'Leather.dd' -> ombre profonde."""
    name, _, suffix = key.partition(".")
    if name not in PALETTE:
        raise KeyError(f"Couleur hors palette : {key}")
    return _apply(hex_rgb(PALETTE[name]), TONE_MIX[suffix])


def face_color(key: str, axis: int, side: int):
    return _apply(tone(key), FACE_TONE.get((axis, side)))


# ---------------------------------------------------------------------------------------------
# Grille de voxels


class Vox:
    """Grille creuse {(x, y, z): clé de couleur}. Bornes inclusives dans toutes les méthodes."""

    def __init__(self, name: str):
        self.name = name
        self.c: dict[tuple[int, int, int], str] = {}

    # Remplissage -----------------------------------------------------------------------------
    def set(self, x: int, y: int, z: int, col: str):
        self.c[(x, y, z)] = col
        return self

    def box(self, x0, x1, y0, y1, z0, z1, col: str):
        for x in range(min(x0, x1), max(x0, x1) + 1):
            for y in range(min(y0, y1), max(y0, y1) + 1):
                for z in range(min(z0, z1), max(z0, z1) + 1):
                    self.c[(x, y, z)] = col
        return self

    def ell(self, cx, cy, cz, rx, ry, rz, col: str, zmin=None, zmax=None):
        """Ellipsoïde voxelisé. Centre et rayons en unités de voxel (centre sur un coin si .0, sur un voxel si .5)."""
        for x in range(math.floor(cx - rx), math.ceil(cx + rx) + 1):
            for y in range(math.floor(cy - ry), math.ceil(cy + ry) + 1):
                for z in range(math.floor(cz - rz), math.ceil(cz + rz) + 1):
                    if zmin is not None and z < zmin or zmax is not None and z > zmax:
                        continue
                    dx = (x + 0.5 - cx) / rx
                    dy = (y + 0.5 - cy) / ry
                    dz = (z + 0.5 - cz) / rz
                    if dx * dx + dy * dy + dz * dz <= 1.0:
                        self.c[(x, y, z)] = col
        return self

    def cyl(self, cx, cy, z0, z1, r, col: str, ry=None):
        """Cylindre vertical (section elliptique si ry)."""
        ry = ry or r
        for z in range(z0, z1 + 1):
            for x in range(math.floor(cx - r), math.ceil(cx + r) + 1):
                for y in range(math.floor(cy - ry), math.ceil(cy + ry) + 1):
                    dx = (x + 0.5 - cx) / r
                    dy = (y + 0.5 - cy) / ry
                    if dx * dx + dy * dy <= 1.0:
                        self.c[(x, y, z)] = col
        return self

    def line(self, p0, p1, col: str, r: int = 0):
        """Segment voxelisé épais de r voxels autour de l'axe (cube)."""
        n = int(max(abs(p1[i] - p0[i]) for i in range(3))) or 1
        for s in range(n + 1):
            t = s / n
            px, py, pz = (round(p0[i] + (p1[i] - p0[i]) * t) for i in range(3))
            self.box(px - r, px + r, py - r, py + r, pz - r, pz + r, col)
        return self

    # Retouche --------------------------------------------------------------------------------
    def carve(self, x0, x1, y0, y1, z0, z1):
        for k in [k for k in self.c if min(x0, x1) <= k[0] <= max(x0, x1)
                  and min(y0, y1) <= k[1] <= max(y0, y1) and min(z0, z1) <= k[2] <= max(z0, z1)]:
            del self.c[k]
        return self

    def paint(self, x0, x1, y0, y1, z0, z1, col: str):
        """Repeint les voxels existants dans la boîte."""
        for k in self.c:
            if min(x0, x1) <= k[0] <= max(x0, x1) and min(y0, y1) <= k[1] <= max(y0, y1) \
                    and min(z0, z1) <= k[2] <= max(z0, z1):
                self.c[k] = col
        return self

    def paint_if(self, pred, col):
        """pred(x, y, z, couleur) -> bool ; col peut être une fonction (couleur) -> couleur."""
        for k, v in list(self.c.items()):
            if pred(k[0], k[1], k[2], v):
                self.c[k] = col(v) if callable(col) else col
        return self

    def shade_rows(self, z_from: int, z_to: int, suffix: str = "d", only=None):
        """Assombrit des rangées (fausse occlusion au pied, bande sous un rebord)."""
        def f(v):
            base = v.split(".")[0]
            return f"{base}.{suffix}" if suffix else base
        return self.paint_if(lambda x, y, z, v: z_from <= z <= z_to and (only is None or v.split(".")[0] in only), f)

    def mirror_x(self, keep_right: bool = True):
        """Recopie le côté x >= 0 (ou x < 0) sur l'autre côté."""
        src = {k: v for k, v in self.c.items() if (k[0] >= 0) == keep_right}
        for (x, y, z), v in src.items():
            self.c[(-1 - x, y, z)] = v
        return self

    def add(self, other: "Vox", dx=0, dy=0, dz=0):
        for (x, y, z), v in other.c.items():
            self.c[(x + dx, y + dy, z + dz)] = v
        return self

    def shift(self, dx=0, dy=0, dz=0):
        self.c = {(x + dx, y + dy, z + dz): v for (x, y, z), v in self.c.items()}
        return self

    def rot_z180(self):
        """Demi-tour autour de l'axe vertical passant par x = 0, y = 0 (plan de symétrie)."""
        self.c = {(-1 - x, -1 - y, z): v for (x, y, z), v in self.c.items()}
        return self

    def rot_x(self, quarter_turns: int = 1):
        """Quart(s) de tour autour de l'axe X (y, z) -> (-z-1, y)."""
        for _ in range(quarter_turns % 4):
            self.c = {(x, -1 - z, y): v for (x, y, z), v in self.c.items()}
        return self

    # Infos -----------------------------------------------------------------------------------
    def bounds(self):
        xs, ys, zs = zip(*self.c.keys())
        return (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))

    def size_studs(self, voxel: float = VOXEL):
        lo, hi = self.bounds()
        return tuple(round((hi[i] - lo[i] + 1) * voxel, 3) for i in range(3))

    def colors_used(self):
        return sorted({v.split(".")[0] for v in self.c.values()})

    def symmetry_error(self) -> float:
        """Part des voxels sans miroir de même couleur (0 = parfaitement symétrique)."""
        bad = sum(1 for (x, y, z), v in self.c.items() if self.c.get((-1 - x, y, z)) != v)
        return bad / max(1, len(self.c))


# ---------------------------------------------------------------------------------------------
# Maillage glouton (faces visibles fusionnées par couleur et par plan)


def greedy_quads(cells: dict):
    """Retourne une liste de (coins[4] en unités de voxel, clé couleur, axe, sens).

    Une face est visible si la case voisine est vide (peu importe sa couleur). Les faces
    coplanaires de même couleur sont fusionnées en rectangles."""
    if not cells:
        return []
    xs, ys, zs = zip(*cells.keys())
    lo = (min(xs), min(ys), min(zs))
    hi = (max(xs), max(ys), max(zs))
    quads = []
    for d in range(3):
        u, v = (d + 1) % 3, (d + 2) % 3
        for side in (1, -1):
            for s in range(lo[d], hi[d] + 1):
                mask = {}
                for i in range(lo[u], hi[u] + 1):
                    for j in range(lo[v], hi[v] + 1):
                        p = [0, 0, 0]
                        p[d], p[u], p[v] = s, i, j
                        col = cells.get(tuple(p))
                        if col is None:
                            continue
                        n = list(p)
                        n[d] += side
                        if tuple(n) not in cells:
                            mask[(i, j)] = col
                used = set()
                for j in range(lo[v], hi[v] + 1):
                    for i in range(lo[u], hi[u] + 1):
                        col = mask.get((i, j))
                        if col is None or (i, j) in used:
                            continue
                        w = 1
                        while mask.get((i + w, j)) == col and (i + w, j) not in used:
                            w += 1
                        h = 1
                        while all(mask.get((i + k, j + h)) == col and (i + k, j + h) not in used for k in range(w)):
                            h += 1
                        for k in range(w):
                            for m in range(h):
                                used.add((i + k, j + m))
                        plane = s + 1 if side > 0 else s
                        corners = []
                        for du, dv in ((0, 0), (w, 0), (w, h), (0, h)):
                            c = [0, 0, 0]
                            c[d], c[u], c[v] = plane, i + du, j + dv
                            corners.append(tuple(c))
                        if side < 0:
                            corners.reverse()
                        quads.append((corners, col, d, side))
    return quads


def mesh_data(vox: Vox, origin, voxel: float = VOXEL):
    """Sommets (studs, Z up), triangles et couleurs par coin, prêts pour Blender ou EditableMesh.

    origin : "bottom" (centre du dessous), "center", ou un point (x, y, z) en unités de voxel."""
    lo, hi = vox.bounds()
    if origin == "bottom":
        o = ((lo[0] + hi[0] + 1) / 2, (lo[1] + hi[1] + 1) / 2, lo[2])
    elif origin == "center":
        o = tuple((lo[i] + hi[i] + 1) / 2 for i in range(3))
    else:
        o = origin
    quads = greedy_quads(vox.c)
    lines = _corner_lines(quads)
    verts, index = [], {}
    faces, colors = [], []

    def vid(p, d, side):
        key = (p, d, side)  # sommets séparés par direction : ombrage plat garanti
        if key not in index:
            index[key] = len(verts)
            verts.append(tuple(round((p[i] - o[i]) * voxel, 5) for i in range(3)))
        return index[key]

    for corners, col, d, side in quads:
        # Mode étanche : on insère dans chaque arête les coins des faces voisines qui tombent dessus
        # (jonctions en T), sinon la maille a des fentes topologiques et des points qui scintillent.
        poly, edge_of, extras = [], [], []
        for i in range(4):
            a, b = corners[i], corners[(i + 1) % 4]
            inner = _points_between(lines, a, b)
            poly.append(a)
            edge_of.append(-1)                    # coin
            poly.extend(inner)
            edge_of.extend([i] * len(inner))      # point posé sur l'arête i
            extras.append(len(inner))
        rgb = face_color(col, d, side)
        ids = [vid(p, d, side) for p in poly]
        n = len(ids)
        # Choix du sommet d'éventail sans triangle plat (n - 2 triangles) :
        #  - un coin dont les deux arêtes voisines n'ont aucun point ajouté ;
        #  - sinon un point ajouté seul sur son arête ;
        #  - sinon le centre du rectangle (n triangles).
        apex = None
        for k in range(n):
            if edge_of[k] == -1:
                ci = sum(1 for j in range(k) if edge_of[j] == -1)
                if extras[ci] == 0 and extras[(ci - 1) % 4] == 0:
                    apex = k
                    break
        if apex is None:
            apex = next((k for k in range(n) if edge_of[k] >= 0 and extras[edge_of[k]] == 1), None)
        if apex is not None:
            for j in range(1, n - 1):
                a, b = (apex + j) % n, (apex + j + 1) % n
                faces.append([ids[apex], ids[a], ids[b]])
                colors.append(rgb)
        else:
            ctr = tuple(sum(c[k] for c in corners) / 4 for k in range(3))
            cid = vid(ctr, d, side)
            for j in range(n):
                faces.append([cid, ids[j], ids[(j + 1) % n]])
                colors.append(rgb)
    return {"verts": verts, "tris_idx": faces, "colors": colors, "tris": len(faces)}


def _corner_lines(quads):
    """Pour chaque droite parallèle à un axe, les coordonnées des coins qui s'y trouvent (triées)."""
    lines: dict = {}
    pts = {c for corners, *_ in quads for c in corners}
    for p in pts:
        for k in range(3):
            key = (k,) + tuple(p[j] for j in range(3) if j != k)
            lines.setdefault(key, set()).add(p[k])
    return {key: sorted(v) for key, v in lines.items()}


def _points_between(lines, a, b):
    k = next(i for i in range(3) if a[i] != b[i])
    key = (k,) + tuple(a[j] for j in range(3) if j != k)
    lo, hi = sorted((a[k], b[k]))
    inner = [t for t in lines.get(key, ()) if lo < t < hi]
    if a[k] > b[k]:
        inner.reverse()
    out = []
    for t in inner:
        p = list(a)
        p[k] = t
        out.append(tuple(p))
    return out


# ---------------------------------------------------------------------------------------------
# Blender (bpy requis à partir d'ici)


def to_blender(vox: Vox, origin="bottom", name: str | None = None, collection=None, voxel: float = VOXEL):
    import bpy

    data = mesh_data(vox, origin, voxel)
    name = name or vox.name
    me = bpy.data.meshes.new(name)
    me.from_pydata(data["verts"], [], data["tris_idx"])
    me.update()
    for p in me.polygons:
        p.use_smooth = False
    attr = me.color_attributes.new("Color", "BYTE_COLOR", "CORNER")
    flat = []
    for poly in me.polygons:
        c = data["colors"][poly.index]
        for _ in poly.loop_indices:
            flat.extend((c[0], c[1], c[2], 1.0))
    attr.data.foreach_set("color_srgb", flat)
    me.color_attributes.active_color = attr
    me.color_attributes.render_color_index = me.color_attributes.find("Color")
    uv = me.uv_layers.new(name="UVMap")  # UV neutre : Roblox attend un jeu d'UV, la couleur est par sommet
    uv.data.foreach_set("uv", [0.5] * (2 * len(me.loops)))
    me.materials.append(voxel_material())
    ob = bpy.data.objects.new(name, me)
    (collection or bpy.context.scene.collection).objects.link(ob)
    ob["tris"] = data["tris"]
    return ob


def voxel_material():
    import bpy

    mat = bpy.data.materials.get("COHUE_Voxel")
    if mat:
        return mat
    mat = bpy.data.materials.new("COHUE_Voxel")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Color"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.85
    return mat


def export_glb(ob, path: str):
    """Exporte un objet de la scène courante. À lancer dans un Blender en ligne de commande
    (build.py) : forcer le contexte d'une autre scène dans un Blender ouvert l'a fait planter."""
    import bpy

    vl = bpy.context.view_layer
    for other in bpy.context.scene.objects:
        other.select_set(other == ob)
    vl.objects.active = ob
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_normals=True,
        export_texcoords=True,
        export_materials="EXPORT",
        export_vertex_color="ACTIVE",
        export_all_vertex_colors=False,
        export_animations=False,
    )


def luau_mesh(vox: Vox, origin="bottom", voxel: float = VOXEL) -> str:
    """Données compactes pour un aperçu EditableMesh dans Studio (axes convertis en Y up, -Z avant)."""
    data = mesh_data(vox, origin, voxel)
    # Blender (x, y, z) Z up, avant -Y  ->  Roblox (-x, z, y) : rotation propre (pas de miroir),
    # l'avant -Y devient l'avant -Z et la main droite du personnage (-X Blender) passe en +X.
    # C'est ce que donne l'export glTF +Y up suivi de l'import Roblox (à vérifier, voir A01-02).
    v = [(-x, z, y) for (x, y, z) in data["verts"]]
    pal = {}
    cols = []
    for c in data["colors"]:
        h = rgb_hex(c)
        pal.setdefault(h, len(pal) + 1)
        cols.append(pal[h])
    return json.dumps({"v": v, "t": data["tris_idx"], "c": cols, "p": list(pal.keys())}, separators=(",", ":"))
