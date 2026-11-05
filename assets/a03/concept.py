"""COHUE — A03, planche concept des ennemis et des boss (étape 2, porte 2), DA du 5 nov.

Blender 5.2 en ligne de commande (rien n'est touché dans un Blender ouvert) :

    blender -b --factory-startup --python assets/a03/concept.py -- <vue[,vue]|all> <dossier de sortie>

Vues : lineup, boss, compare, horde_grass, horde_sand, silhouettes.

Reprend les outils de A01 (grille, briques, tenons en texture, lumière) et de A14 (rendu, bloom, télégraphe
ennemi), sans les modifier. Les modèles sont dans creatures.py.
Caméra de jeu : valeurs de shared/Config/Movement.luau (Distance 32, Pitch 42°, FieldOfView 70 vertical,
FocusHeight 2,5, FocusAhead 5).
"""

from __future__ import annotations

import importlib.util
import json
import math
import os
import random
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
for p in (os.path.join(ROOT, "assets", "voxel"), os.path.join(ROOT, "assets", "a14"), HERE):
    if p not in sys.path:
        sys.path.append(p)

# Outils de A14 chargés sous un autre nom (son fichier s'appelle aussi concept.py). En l'important, A14 passe
# les modèles de A01 en briques à tenons (brick.STUD_TEXTURE, cv.to_blender = brick.to_blender).
_spec = importlib.util.spec_from_file_location("a14_concept", os.path.join(ROOT, "assets", "a14", "concept.py"))
A14 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(A14)

import boards as BD  # noqa: E402
import brick  # noqa: E402
import build as B  # noqa: E402
import cohue_voxel as cv  # noqa: E402
import models as M  # noqa: E402
import studs as S  # noqa: E402

import creatures as C  # noqa: E402

VOXEL_V1 = A14.pixel_to_blender      # maille voxel v1 lisse de A01 (celle qui est dans COHUE aujourd'hui)
GOLD = cv.PALETTE["Gold"]

# Caméra de jeu (Config/Movement.Camera)
CAM_DISTANCE, CAM_PITCH, CAM_FOV, FOCUS_HEIGHT, FOCUS_AHEAD, ROOT_HEIGHT = 32.0, 42.0, 70.0, 2.5, 5.0, 3.0


# =============================================================================================
# Matériaux des yeux (lisses : les seules surfaces sans tenons d'un personnage)

_eye_mats: dict = {}


def eye_material(hexc: str, rough: float = 0.25):
    if hexc in _eye_mats:
        return _eye_mats[hexc]
    mat = bpy.data.materials.new(f"A03_Eye_{hexc}")
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = B.hexcol(hexc)
    bsdf.inputs["Roughness"].default_value = rough
    _eye_mats[hexc] = mat
    return mat


def _sphere(name, radius, scale, loc, mat, parent):
    me = A14._sphere_mesh(name, radius, 20, 12)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for poly in me.polygons:
        poly.use_smooth = True
    me.materials.append(mat)
    ob.scale = scale
    ob.location = loc
    ob.parent = parent
    return ob


# =============================================================================================
# Pose d'une créature : briques (une maille, tenons en texture) + yeux lisses


_templates: dict = {}


def _origin(vox):
    lo, hi = vox.bounds()
    return ((lo[0] + hi[0] + 1) / 2, (lo[1] + hi[1] + 1) / 2, lo[2])


def fused_to_blender(vox, origin, name, cell):
    """Technique B du guide DA (§9) : la maille fusionnée de A01 (faces de même couleur regroupées, environ
    550 à 800 triangles pour un ennemi), sans ombrage cuit, avec les tenons en texture comme Resurface en jeu.
    C'est ce que la horde affichera vraiment."""
    saved = dict(cv.FACE_TONE)
    cv.FACE_TONE.clear()                 # plus d'ombrage cuit par face : la vraie lumière fait le relief
    try:
        ob = VOXEL_V1(vox, origin, name=name, voxel=cell)
    finally:
        cv.FACE_TONE.update(saved)
    o = _origin(vox)
    ob.data.materials.clear()
    ob.data.materials.append(S.stud_material(1.0 / cell, tuple(v % 1.0 for v in o)))
    return ob


def build_template(fn, fused=False):
    """Construit une fois chaque modèle (maille partagée par toutes ses copies).
    fused = False : briques chanfreinées (rendu de référence) ; True : maille fusionnée du jeu."""
    key = (fn, fused)
    if key in _templates:
        return _templates[key]
    vox, origin, meta = fn()
    cell = meta["cell"]
    if fused:
        body = fused_to_blender(vox, origin, vox.name + "_B", cell)
    else:
        body = brick.to_blender(vox, origin, name=vox.name, voxel=cell)
    o = _origin(vox)
    parts = []
    for k, e in enumerate(meta["eyes"]):
        x, y, z = e["c"]
        if y is None:
            y = C.front_y(vox, x, z)
        r, d = e["r"], e["d"]
        center = Vector(((x - o[0]) * cell, (y - o[1]) * cell, (z - o[2]) * cell))
        sz = e.get("sz", 1.0)
        if e["ink"]:
            parts.append(("sclera", r, (1, d, sz), center, cv.PALETTE["Ink"]))
            parts.append(("glint", r * 0.3, (1, 0.5, 1), center + Vector((-0.3 * r, -r * d * 0.95, 0.45 * r * sz)),
                          "FFF8EC"))
            parts.append(("glint", r * 0.13, (1, 0.5, 1), center + Vector((0.2 * r, -r * d * 0.9, 0.0)),
                          "FFF8EC"))
        else:
            parts.append(("sclera", r, (1, d, sz), center, "FFF8EC"))
            lx, lz = e["look"]
            pr = r * e["p"]
            pc = center + Vector((lx * (r - pr) * 0.9, -r * d * 0.82, lz * (r - pr) * 0.9))
            parts.append(("pupil", pr, (1, 0.45, 1), pc, cv.PALETTE["Ink"]))
            parts.append(("glint", pr * 0.33, (1, 0.5, 1), pc + Vector((-0.35 * pr, -pr * 0.3, 0.4 * pr)), "FFF8EC"))
            lid = e.get("lid", 0.0)
            if lid > 0:                  # paupière lourde de la couleur de la peau, sur le haut de l'oeil
                skin = "".join(f"{round(c * 255):02X}" for c in cv.tone(meta.get("skin", "Sky.dd")))
                parts.append(("lid", r * 1.1, (1, d * 1.25, lid * 1.05),
                              center + Vector((0, -r * 0.02, r * (1 - lid))), skin))
    _templates[key] = (body, parts, meta)
    body.location = (0, -10000, 0)       # le modèle d'origine reste hors champ
    return _templates[key]


def place(fn, loc, rot_z=0.0, scale=1.0, elite=False, lean=0.0, fused=False):
    """Copie d'un modèle (même maille) avec ses yeux. Retourne l'objet du corps."""
    body, parts, meta = build_template(fn, fused)
    ob = body.copy()
    bpy.context.scene.collection.objects.link(ob)
    for k, (kind, r, sc, center, hexc) in enumerate(parts):
        _sphere(f"{ob.name}_{kind}{k}", r, sc, center, eye_material(hexc), ob)
    lift = meta.get("float", 0.0) * scale
    ob.location = (loc[0], loc[1], loc[2] + lift)
    ob.rotation_euler = (lean, 0, rot_z)
    ob.scale = (scale, scale, scale)
    if elite:
        dims = Vector(C_size(fn)) * scale
        r = max(dims.x, dims.y) * 0.55
        A14.disc((loc[0], loc[1]), r, loc[2] + 0.06, GOLD, 2.2,
                 [(0.0, 0.0), (0.78, 0.0), (0.84, 1.0), (0.95, 1.0), (1.0, 0.0)])
        crown = bpy.data.objects.new("Crown", A14._sphere_mesh("Crown", 0.45, 4, 2))
        bpy.context.scene.collection.objects.link(crown)
        crown.data.materials.append(A14._solid_glow(GOLD, 2.0))
        crown.scale = (1.4, 1.4, 1.0)
        crown.location = (loc[0], loc[1], loc[2] + lift + dims.z + 0.7)
    return ob


_sizes: dict = {}


def C_size(fn):
    if fn not in _sizes:
        vox, _, meta = fn()
        _sizes[fn] = vox.size_studs(meta["cell"])
    return _sizes[fn]


def place_v1(fn, loc, rot_z=0.0):
    """Gobelin v1 tel qu'il est dans COHUE : maille voxel lisse, ombrage cuit par face, sans tenons."""
    vox, origin, meta = fn()
    ob = VOXEL_V1(vox, origin, name=vox.name + "_v1")
    ob.location = loc
    ob.rotation_euler = (0, 0, rot_z)
    return ob


# =============================================================================================
# Décor


def ground(sc, kind="grass", half=6, seed=0):
    rnd = random.Random(seed)
    # Sol d'arène calme (guide DA §4) : un seul ton par sol, ±3 % d'un bloc à l'autre, sans dalles claires
    base = {"grass": ("Leaf.d", "Leaf.d"), "sand": ("Leather.l", "Leather.l"), "grave": ("Leaf.d", "Leaf.d")}[kind]
    for i in range(-half, half):
        for j in range(-half - 3, half):
            cx, cy = i * 8 + 4, j * 8 + 4
            col = base[0] if rnd.random() < 0.86 else base[1]
            S.block(f"Ground_{i}_{j}", (cx, cy, -0.5), (8, 8, 1), col, jitter=0.03)


def edge_dressing(seed=0, spread=46):
    rnd = random.Random(seed)
    for k in range(16):
        side = rnd.choice((-1, 1))
        x = side * rnd.uniform(spread * 0.55, spread)
        y = rnd.uniform(-70, 10)
        if k % 3 == 0:
            S.rock(f"Rock_{k}", (x, y, 0), size=rnd.uniform(2, 3.5), seed=k)
        elif k % 3 == 1:
            S.pine(f"Pine_{k}", (x, y, 0), height=rnd.uniform(12, 18), seed=k)
        else:
            S.bush(f"Bush_{k}", (x, y, 0), size=2.4, seed=k)


def light(sc):
    B.diorama_light(sc, sun_elev=55, sun_az=-35, strength=4.6, world="A9D8F5", world_strength=0.95)


def game_camera(sc, player):
    """Caméra 3e personne du jeu, derrière le joueur qui regarde vers -Y."""
    px, py = player
    focus = Vector((px, py - FOCUS_AHEAD, ROOT_HEIGHT + FOCUS_HEIGHT))
    a = math.radians(CAM_PITCH)
    loc = focus + Vector((0, math.cos(a) * CAM_DISTANCE, math.sin(a) * CAM_DISTANCE))
    cam = B.camera(sc, tuple(loc), tuple(focus))
    cam.data.sensor_fit = "VERTICAL"
    cam.data.angle_y = math.radians(CAM_FOV)
    return cam


def tombstones(seed=3, n=10, spread=40):
    rnd = random.Random(seed)
    for k in range(n):
        x = rnd.choice((-1, 1)) * rnd.uniform(12, spread)
        y = rnd.uniform(-40, 12)
        S.block(f"Tomb_{k}", (x, y, 1.2), (2.2, 0.8, 2.4), "Stone.l", rnd.uniform(-0.3, 0.3),
                ((rnd.random() - 0.5) * 14, (rnd.random() - 0.5) * 10))


# =============================================================================================
# Vues


def view_lineup(out):
    """Les trois familles de face, de trois quarts haut, avec l'avatar pour l'échelle."""
    sc = A14.fresh()
    light(sc)
    S.block("Plinth", (0, 0, -0.5), (44, 20, 1), "Leaf.d", jitter=0.0)
    BD.dressed("Knight", 3, -10.0, y=1.0, rot=math.radians(-12))
    place(C.goblin_grunt, (-3.5, 0, 0), rot_z=math.radians(12))
    place(C.zombie_runner, (3.0, 0, 0), rot_z=math.radians(-42))   # de trois-quarts : on voit le Γ
    place(C.ghost_poltergeist, (9.5, 0, 0), rot_z=math.radians(-14))
    B.camera(sc, (0.0, -30.0, 9.0), (0.0, 0.0, 2.6), lens=40)
    A14.render(sc, out, res=(2400, 900), samples=64)


def view_boss(out):
    """The Hungry Coffin, son télégraphe « Lid Chomp » sous le joueur, deux Runners pour l'échelle."""
    sc = A14.fresh()
    light(sc)
    ground(sc, "grass", half=9, seed=2)
    rnd = random.Random(3)
    for k, (x, y) in enumerate(((-16, 8), (-11, 14), (13, 10), (19, 4), (-22, -2), (24, 16))):
        S.block(f"Tomb_{k}", (x, y, 1.2), (2.4, 0.9, 2.6), "Stone.l", rnd.uniform(-0.3, 0.3),
                ((rnd.random() - 0.5) * 16, (rnd.random() - 0.5) * 10))
    S.pine("Pine_a", (-28, 20, 0), height=16, seed=1)
    S.pine("Pine_b", (30, 24, 0), height=18, seed=2)
    place(C.boss_hungry_coffin, (0, 0, 0), rot_z=math.radians(10), lean=math.radians(5))
    player = (9.0, -16.0)
    BD.dressed("Knight", 3, player[0], y=player[1], rot=math.atan2(-player[0], player[1]))
    A14.danger(player, 8.0, progress=0.62)
    place(C.zombie_runner, (-9.5, -9.0, 0), rot_z=math.radians(-25))
    place(C.zombie_runner, (16.5, -6.0, 0), rot_z=math.radians(40))
    B.camera(sc, (-6.0, -48.0, 17.0), (2.0, -4.0, 6.5), lens=36)
    A14.render(sc, out, res=(2400, 1350), samples=64)


def view_compare(out):
    """Goblin Grunt : v1 voxel (dans COHUE aujourd'hui) contre v2 en briques à gros yeux ronds."""
    sc = A14.fresh()
    light(sc)
    S.block("Plinth", (0, 0, -0.5), (28, 12, 1), "Leaf.d", jitter=0.0)
    place_v1(M.goblin_grunt, (-6.0, 0, 0), rot_z=math.radians(14))
    place(C.goblin_grunt, (0.0, 0, 0), rot_z=math.radians(14), fused=True)
    place(C.goblin_grunt, (6.0, 0, 0), rot_z=math.radians(14))
    B.camera(sc, (0.0, -24.0, 7.5), (0.0, 0.0, 2.1), lens=44)
    A14.render(sc, out, res=(2400, 900), samples=64)


def horde_points(n=70, player=(0.0, 6.0), seed=42):
    rnd = random.Random(seed)
    pts = []
    while len(pts) < n:
        a = rnd.uniform(-math.pi, math.pi)
        rr = 4.5 + rnd.random() ** 1.6 * 22.0         # serrés près du joueur, plus clairsemés au loin
        if rnd.random() < 0.85:                       # la plupart devant le joueur (dans le champ)
            a = rnd.uniform(-math.pi * 0.9, -math.pi * 0.1)
        x, y = player[0] + math.cos(a) * rr, player[1] + math.sin(a) * rr
        if any(math.hypot(x - p, y - q) < 1.9 for p, q in pts):
            continue
        pts.append((x, y))
    return pts


def view_horde(out, kind, fused=True):
    """La horde du monde 1 à la caméra du jeu : 70 gobelins des 4 rôles (34 Grunts, 14 Archers, 10 Shamans,
    12 Bombers), dont 2 élites. Maille fusionnée du jeu (technique B) : c'est le rendu qu'aura la horde.
    Le vrai risque est de distinguer les 4 rôles d'une même famille sur son sol (relecture du 5 nov.)."""
    sc = A14.fresh()
    light(sc)
    ground(sc, kind, half=13, seed=5)
    edge_dressing(seed=4)
    player = (0.0, 6.0)
    BD.dressed("Knight", 3, player[0], y=player[1], rot=0.0)   # dos à la caméra, face à la horde
    kinds = [C.goblin_grunt] * 34 + [C.goblin_archer] * 14 + [C.goblin_shaman] * 10 + [C.goblin_bomber] * 12
    random.Random(7).shuffle(kinds)
    rnd = random.Random(9)
    for k, (x, y) in enumerate(horde_points()):
        face = math.atan2(player[0] - x, -(player[1] - y))   # regarde le joueur (avant = -Y)
        elite = k in (5, 23)
        place(kinds[k], (x, y, 0), rot_z=face + rnd.uniform(-0.3, 0.3), scale=1.3 if elite else 1.0, elite=elite,
              fused=fused)
        if k == 11:                                   # un capturable : anneau rose au sol (Bubblegum, réservé)
            A14.disc((x, y), 2.0, 0.07, cv.PALETTE["Bubblegum"], 2.4,
                     [(0.0, 0.0), (0.74, 0.0), (0.8, 1.0), (0.93, 1.0), (1.0, 0.0)])
    # Ce qui entoure la horde en jeu : XP au sol (Neon cyan), deux tirs ennemis (Tomato mat)
    xr = random.Random(21)
    for _ in range(14):
        a, rr = xr.uniform(0, math.tau), xr.uniform(2.5, 9.0)
        gem = bpy.data.objects.new("XP", A14._sphere_mesh("XP", 0.32, 4, 2))
        bpy.context.scene.collection.objects.link(gem)
        gem.data.materials.append(A14._solid_glow(cv.PALETTE["Sky"], 2.2))
        gem.location = (player[0] + math.cos(a) * rr, player[1] - 3 + math.sin(a) * rr, 0.45)
    for (sx, sy) in ((-7.0, -10.0), (8.0, -12.0)):
        tx, ty = sx + (player[0] - sx) * 0.55, sy + (player[1] - sy) * 0.55
        A14.enemy_shot((tx, ty, 2.0), (player[0] - sx, player[1] - sy, 0))
    game_camera(sc, player)
    A14.render(sc, out, res=(1600, 900), samples=48)


def view_silhouettes(out):
    """Silhouettes noires de face et de profil (test à 64 px, guide DA règle 10) : deux images par modèle."""
    for fn in C.ALL + C.GOBLINS[1:]:
        for side, cam in (("", (0, -60)), ("_side", (60, 0))):
            sc = A14.fresh()
            _templates.clear()
            place(fn, (0, 0, 0))
            w, d, h = C_size(fn)
            lift = fn()[2].get("float", 0.0)
            size = max(w, d, h + lift) * 1.08
            B.camera(sc, (cam[0], cam[1], (h + lift) / 2), (0, 0, (h + lift) / 2), ortho=size)
            B.silhouette_mode(sc, True)
            B.render(sc, out.replace(".png", f"_{fn.__name__}{side}.png"), res=(512, 512), transparent=True,
                     samples=1)
            B.silhouette_mode(sc, False)


def view_goblins(out):
    """Les 4 gobelins du monde 1 refaits, en maille du jeu (technique B)."""
    sc = A14.fresh()
    light(sc)
    S.block("Plinth", (0, 0, -0.5), (44, 20, 1), "Leaf.d", jitter=0.0)
    for k, fn in enumerate(C.GOBLINS):
        place(fn, (-9.0 + k * 6.0, 0, 0), rot_z=math.radians(10 - 6 * k), fused=True)
    B.camera(sc, (0.0, -30.0, 9.0), (0.0, 0.0, 2.6), lens=40)
    A14.render(sc, out, res=(2400, 900), samples=64)


def tris_report(out):
    stats = {}
    for fn in C.ALL + C.GOBLINS[1:]:
        vox, origin, meta = fn()
        verts, faces, vcols, o = brick.mesh_lists(vox, origin, meta["cell"])
        stats[vox.name] = {"bricks_tris_sans_chanfrein": sum(2 if len(f) == 4 else 1 for f in faces),
                           "fused_tris_v1_style": cv.mesh_data(vox, origin, meta["cell"])["tris"],
                           "size_studs": vox.size_studs(meta["cell"])}
    with open(out, "w", encoding="utf-8") as f:
        json.dump(stats, f, indent=1)


VIEWS = {"lineup": view_lineup, "boss": view_boss, "compare": view_compare, "goblins": view_goblins,
         "horde_grass": lambda o: view_horde(o, "grass"), "horde_sand": lambda o: view_horde(o, "sand"),
         "horde_bricks": lambda o: view_horde(o, "grass", fused=False),
         "silhouettes": view_silhouettes}


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:]
    which, outdir = argv[0], os.path.abspath(argv[1])
    os.makedirs(outdir, exist_ok=True)
    tris_report(os.path.join(outdir, "tris.json"))
    for name in (list(VIEWS) if which == "all" else which.split(",")):
        _templates.clear()
        cam_data = bpy.data.cameras.get("A01_Cam")
        if cam_data:                     # la caméra de jeu (champ vertical) ne doit pas déborder sur la vue suivante
            cam_data.sensor_fit = "AUTO"
        VIEWS[name](os.path.join(outdir, f"a03_{name}.png"))
