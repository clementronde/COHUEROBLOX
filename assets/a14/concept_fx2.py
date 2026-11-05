"""COHUE — A14, planche concept des effets « naturels » (v2, 5 nov. 2026).

Clément (5 nov.) : « il faut que les effets soient plus naturels, plus Megabonk, là c'est trop pixel ».
Référence : sa capture `.claude/refs/jeu-reference-5nov/1-run-neige.webp` (coup d'arme en grand ruban
lumineux, cœur blanc, bords doux et saturés, beaucoup de lumière).

Ce rendu n'utilise que ce que Roblox sait afficher sans rien téléverser :
- les textures de particules intégrées à Roblox (copiées depuis le client local dans out/rbxtex, jamais dans
  le dépôt) : lueur ronde (explosion01_implosion_main), boule de feu (explosion01_core_main), onde de choc
  (explosion01_shockwave_main), fumée (smoke_main), flammes (fire_main), étoile (sparkles_main) ;
- des rubans à bords doux, comme un Beam courbe avec la lueur ronde étirée en texture ;
- aucun anneau Neon plat, aucune pièce en pixels en vol (les armes tenues restent en pixel art).

    blender -b --factory-startup --python assets/a14/concept_fx2.py -- <vue[,vue]|all> <dossier de sortie>
"""

from __future__ import annotations

import math
import os
import random
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.append(HERE)

import concept as C  # noqa: E402

B, BD, M = C.B, C.BD, C.M
TEX_DIR = os.path.join(HERE, "out", "rbxtex")

GLOW = "explosion01_implosion_main"
CORE = "explosion01_core_main"
SHOCK = "explosion01_shockwave_main"
SMOKE = "smoke_main"
FIRE = "fire_main"
STAR = "sparkles_main"

_tex_mats: dict = {}


def tex_mat(tex, tint, strength=3.0, opacity=1.0, emissive=True):
    """Particule Roblox : couleur = texture x Color ; alpha = alpha de la texture x (1 - Transparency).
    emissive = LightEmission 1 (lueur) ; sinon matière éclairée (fumée)."""
    key = (tex, tint, round(strength, 2), round(opacity, 2), emissive)
    if key in _tex_mats:
        return _tex_mats[key]
    mat = bpy.data.materials.new(f"A14_Tex_{len(_tex_mats)}")
    mat.use_nodes = True
    nt = mat.node_tree
    L = nt.links
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    img = bpy.data.images.load(os.path.join(TEX_DIR, tex + ".png"), check_existing=True)
    ti = nt.nodes.new("ShaderNodeTexImage")
    ti.image = img
    ti.extension = "CLIP"
    mix = nt.nodes.new("ShaderNodeVectorMath")   # texture x teinte (Color du ParticleEmitter)
    mix.operation = "MULTIPLY"
    L.new(ti.outputs["Color"], mix.inputs[0])
    mix.inputs[1].default_value = tuple(B.hexcol(tint))[:3]
    res = mix.outputs["Vector"]
    if emissive:
        bsdf.inputs["Base Color"].default_value = (0, 0, 0, 1)
        bsdf.inputs["Specular IOR Level"].default_value = 0.0
        L.new(res, bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = strength
    else:
        L.new(res, bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 1.0
        bsdf.inputs["Specular IOR Level"].default_value = 0.0
        L.new(res, bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 0.25
    m = nt.nodes.new("ShaderNodeMath")
    m.operation = "MULTIPLY"
    m.inputs[1].default_value = opacity
    L.new(ti.outputs["Alpha"], m.inputs[0])
    L.new(m.outputs["Value"], bsdf.inputs["Alpha"])
    for attr, val in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
        try:
            setattr(mat, attr, val)
        except Exception:
            pass
    _tex_mats[key] = mat
    return mat


def _quad_uv(name, w, h, roll):
    me = bpy.data.meshes.new(name)
    me.from_pydata([(-w / 2, -h / 2, 0), (w / 2, -h / 2, 0), (w / 2, h / 2, 0), (-w / 2, h / 2, 0)], [],
                   [(0, 1, 2, 3)])
    uv = me.uv_layers.new(name="UVMap")
    c, s = math.cos(roll), math.sin(roll)
    for i, (u, v) in enumerate(((0, 0), (1, 0), (1, 1), (0, 1))):
        du, dv = u - 0.5, v - 0.5
        uv.data[i].uv = (0.5 + du * c - dv * s, 0.5 + du * s + dv * c)
    return me


CAM = [Vector((0.0, 30.0, 25.0))]   # position de la caméra de jeu (posée par chaque vue avant les effets)


def cam_pos(player):
    px, py = player
    return Vector((px, py - 5.0 + 32.0 * math.cos(math.radians(42.0)), 2.5 + 32.0 * math.sin(math.radians(42.0))))


def ribbon_cam(points, widths, hexc, strength, across, along, name="A14_Beam"):
    """Beam ou Trail avec FaceCamera : la largeur du ruban est tournée vers la caméra (pas écrasée à plat)."""
    from mathutils import Vector as V
    verts, faces, uvs = [], [], []
    n = len(points)
    for i, (pt, w) in enumerate(zip(points, widths)):
        pt = V(pt)
        tan = V(points[min(i + 1, n - 1)]) - V(points[max(i - 1, 0)])
        side = tan.cross(CAM[0] - pt).normalized()
        verts += [pt + side * w * 0.5, pt - side * w * 0.5]
        uvs += [(i / (n - 1), 0.0), (i / (n - 1), 1.0)]
    for i in range(n - 1):
        a = 2 * i
        faces.append((a, a + 2, a + 3, a + 1))
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    uv = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        for li, vi in zip(poly.loop_indices, poly.vertices):
            uv.data[li].uv = uvs[vi]
    ob = C._link(bpy.data.objects.new(name, me))
    ob.data.materials.append(C.fx_material(hexc, strength, list(across), mode="ribbon", along=list(along)))
    return ob


def tsprite(loc, size, tex, tint, strength=3.0, opacity=1.0, roll=0.0, stretch=1.0, flat=False, emissive=True):
    """Une particule (billboard tourné vers la caméra) ou une forme posée à plat (flat)."""
    ob = C._link(bpy.data.objects.new("A14_P", _quad_uv("A14_P", size, size * stretch, roll)))
    ob.data.materials.append(tex_mat(tex, tint, strength, opacity, emissive))
    ob.location = loc
    if not flat:
        C.BILLBOARDS.append(ob)
    return ob


def puffs(rnd, center, n, spread, z, tex, tints, size, strength=3.0, opacity=1.0, emissive=True, rise=0.0):
    """Une rafale de particules autour de `center` (Emit(n) d'un ParticleEmitter)."""
    for k in range(n):
        a = rnd.uniform(0, math.tau)
        r = spread * math.sqrt(rnd.random())
        loc = (center[0] + math.cos(a) * r, center[1] + math.sin(a) * r, z + rnd.uniform(0, rise))
        tsprite(loc, rnd.uniform(*size), tex, rnd.choice(tints), strength, opacity * rnd.uniform(0.7, 1.0),
                roll=rnd.uniform(0, math.tau), emissive=emissive)


# =============================================================================================
# Effets


def slash(center, radius=12.0, facing=-90.0, half=75.0, h=2.2, edge="3CC8FF", glow="3CC8FF", tilt=8.0, flip=False):
    """Coup d'épée : ruban presque couché dans la direction de la frappe (incliné de 8° vers la caméra).
    Trois Beams FaceCamera (LightEmission 1) : halo large (Transparency 0,7), bord bleu ciel, cœur blanc étroit.
    Le geste a un sens : traîne effilée et transparente au départ, tête large et claire à l'arrivée."""
    n = 56
    a0, a1 = math.radians(facing - half), math.radians(facing + half)
    if flip:
        a0, a1 = a1, a0
    fx, fy = math.cos(math.radians(facing)), math.sin(math.radians(facing))
    lift = math.tan(math.radians(tilt))
    pts, w_halo, w_edge, w_core = [], [], [], []
    for i in range(n):
        u = i / (n - 1)
        a = a0 + (a1 - a0) * u
        body = (u ** 1.6) * (1.0 - max(0.0, (u - 0.85) / 0.15) ** 2)   # mince au départ, large vers la tête
        r = radius * (0.9 + 0.1 * body)
        x, y = center[0] + math.cos(a) * r, center[1] + math.sin(a) * r
        ahead = max(0.0, (x - center[0]) * fx + (y - center[1]) * fy)
        pts.append((x, y, h + ahead * lift))
        w_halo.append(0.3 + 9.0 * body)
        w_edge.append(0.15 + 5.0 * body)
        w_core.append(0.05 + 1.4 * body)
    plateau = ((0.0, 0.0), (0.15, 0.9), (0.5, 1.0), (0.85, 0.9), (1.0, 0.0))
    ribbon_cam(pts, w_halo, glow, 2.2, ((0.0, 0.0), (0.5, 0.3), (1.0, 0.0)),
               ((0.0, 0.0), (0.4, 0.3), (0.9, 1.0), (1.0, 0.4)), name="A14_SlashHalo")
    ribbon_cam([(q[0], q[1], q[2] + 0.01) for q in pts], w_edge, edge, 6.0,
               ((0.0, 0.0), (0.2, 0.6), (0.5, 0.65), (0.8, 0.6), (1.0, 0.0)),
               ((0.0, 0.0), (0.4, 0.35), (0.9, 1.0), (1.0, 0.4)), name="A14_SlashEdge")
    ribbon_cam([(q[0], q[1], q[2] + 0.02) for q in pts], w_core, C.WHITE, 16.0, plateau,
               ((0.0, 0.0), (0.45, 0.4), (0.92, 1.0), (1.0, 0.5)), name="A14_SlashCore")


def slash_upright(center, radius=10.0, facing=-90.0, half=75.0, h=2.4, edge="3CC8FF", glow="3CC8FF", tilt=25.0):
    """Variante A : croissant dressé, symétrique, incliné de 25° vers la caméra (plus grand à l'écran)."""
    n = 56
    a0, a1 = math.radians(facing - half), math.radians(facing + half)
    fx, fy = math.cos(math.radians(facing)), math.sin(math.radians(facing))
    lift = math.tan(math.radians(tilt))
    pts, w_halo, w_edge, w_core = [], [], [], []
    for i in range(n):
        u = i / (n - 1)
        a = a0 + (a1 - a0) * u
        bulge = math.sin(math.pi * u) ** 0.75
        r = radius * (0.95 + 0.05 * bulge)
        x, y = center[0] + math.cos(a) * r, center[1] + math.sin(a) * r
        ahead = max(0.0, (x - center[0]) * fx + (y - center[1]) * fy)
        pts.append((x, y, h + ahead * lift))
        w_halo.append(9.0 * bulge)
        w_edge.append(5.5 * bulge)
        w_core.append(1.5 * bulge)
    plateau = ((0.0, 0.0), (0.15, 0.9), (0.5, 1.0), (0.85, 0.9), (1.0, 0.0))
    ribbon_cam(pts, w_halo, glow, 2.2, ((0.0, 0.0), (0.5, 0.35), (1.0, 0.0)),
               ((0.0, 0.0), (0.3, 0.6), (0.85, 1.0), (1.0, 0.3)), name="A14_SlashHalo")
    ribbon_cam([(q[0], q[1], q[2] + 0.01) for q in pts], w_edge, edge, 6.0,
               ((0.0, 0.0), (0.2, 0.6), (0.5, 0.6), (0.8, 0.6), (1.0, 0.0)),
               ((0.0, 0.0), (0.25, 0.6), (0.85, 1.0), (1.0, 0.3)), name="A14_SlashEdge")
    ribbon_cam([(q[0], q[1], q[2] + 0.02) for q in pts], w_core, C.WHITE, 16.0, plateau,
               ((0.0, 0.0), (0.3, 0.7), (0.88, 1.0), (1.0, 0.4)), name="A14_SlashCore")


def hit(loc, color="4FC3FF", seed=0):
    """Impact : éclair blanc, halo coloré, quelques étincelles."""
    rnd = random.Random(seed)
    tsprite(loc, 4.5, GLOW, C.WHITE, 8.0)
    tsprite(loc, 7.0, GLOW, color, 4.0, opacity=0.8)
    for k in range(6):
        d = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-0.2, 0.9))).normalized()
        tsprite(Vector(loc) + d * rnd.uniform(0.6, 1.8), rnd.uniform(0.25, 0.5), STAR, C.WHITE, 6.0, roll=rnd.uniform(0, 6))


def fireball(start, end, h=2.5, seed=1):
    """Boule de feu : tête très claire, flammes qui traînent, fumée légère derrière, ruban chaud."""
    rnd = random.Random(seed)
    s, e = Vector((start[0], start[1], h)), Vector((end[0], end[1], h))
    d = (e - s).normalized()
    s = e - d * 3.5
    ribbon_cam([tuple(s.lerp(e, t)) for t in (0.0, 0.3, 0.6, 0.85, 1.0)], [0.2, 0.8, 1.4, 1.7, 1.8], "FF9A2E", 3.5,
             ((0.0, 0.0), (0.5, 1.0), (1.0, 0.0)), ((0.0, 0.0), (0.6, 0.6), (1.0, 1.0)), name="A14_FireTrail")
    tsprite(e, 4.0, GLOW, "FFE27A", 6.0)
    tsprite(e, 1.9, GLOW, C.WHITE, 10.0)
    for k in range(9):
        t = rnd.uniform(0.0, 0.5)
        p = e - d * (t * 4.0) + Vector((rnd.uniform(-0.4, 0.4), rnd.uniform(-0.4, 0.4), rnd.uniform(-0.2, 0.5)))
        tsprite(p, 2.2 - t * 2.0, CORE, rnd.choice(("FFC21A", "FF7A1A", "FFE8B8")), 4.0, opacity=0.9 - t,
                roll=rnd.uniform(0, 6))
    for k in range(5):
        t = rnd.uniform(0.35, 1.0)
        p = e - d * (t * 6.0) + Vector((0, 0, rnd.uniform(0.2, 0.9)))
        tsprite(p, rnd.uniform(1.4, 2.4), SMOKE, "BEB8B0", opacity=0.45 * (1.1 - t), roll=rnd.uniform(0, 6), emissive=False)


def explosion(center, r=5.0, seed=3, scorch=True):
    """Explosion (image au milieu de sa vie) : boules de feu qui gonflent et montent, petit éclair blanc au
    cœur, onde de choc orange au sol, fumée qui se forme au-dessus, braises projetées."""
    rnd = random.Random(seed)
    cx, cy = center
    tsprite((cx, cy, 0.12), 2.3 * r, SHOCK, "FFB020", 4.0, opacity=2.6, flat=True)
    tsprite((cx, cy, 0.10), 1.3 * r, GLOW, "FFB020", 2.0, opacity=0.5, flat=True)
    for k in range(16):
        a = rnd.uniform(0, math.tau)
        rr = rnd.uniform(0, r * 0.5)
        z = rnd.uniform(0.8, 4.0)
        tsprite((cx + math.cos(a) * rr, cy + math.sin(a) * rr, z), rnd.uniform(0.8, 1.3) * r, CORE,
                rnd.choice(("FFE27A", "FFC21A", "FFF0C8")), 2.6 + 0.4 * (4.0 - z), opacity=1.0, roll=rnd.uniform(0, 6))
    tsprite((cx, cy, 2.0), 0.55 * r, GLOW, C.WHITE, 5.0, opacity=0.8)
    for k in range(8):
        a = rnd.uniform(0, math.tau)
        rr = rnd.uniform(0.2, 0.6) * r
        tsprite((cx + math.cos(a) * rr, cy + math.sin(a) * rr, rnd.uniform(4.0, 6.5)), rnd.uniform(0.5, 0.8) * r, SMOKE,
                rnd.choice(("6E6A64", "8C8780")), opacity=0.75, roll=rnd.uniform(0, 6), emissive=False)
    for k in range(18):
        d = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(0.2, 1.2))).normalized()
        tsprite(Vector((cx, cy, 1.2)) + d * rnd.uniform(r * 0.6, r * 1.2), rnd.uniform(0.3, 0.55), GLOW,
                rnd.choice(("FFC21A", "FFE8B8")), 8.0, stretch=rnd.uniform(1.5, 2.5), roll=rnd.uniform(0, 6))


def frost_nova(center, r=7.0, seed=5):
    """Nova de glace : anneau creux cyan glacé (centre transparent), qui s'élargit et s'efface en 0,25 s ;
    brume légère sur le bord ; étincelles bleutées étirées vers l'extérieur (lueur intégrée)."""
    rnd = random.Random(seed)
    cx, cy = center
    tsprite((cx, cy, 0.10), r / 0.29, SHOCK, "3FC8FF", 2.2, opacity=2.6, flat=True)
    C.disc(center, r * 1.06, 0.13, "3FC8FF", 2.4, [(0.0, 0.0), (0.74, 0.0), (0.88, 0.7), (0.95, 0.7), (1.0, 0.0)])
    C.disc(center, r * 1.02, 0.14, "BFEFFF", 3.0, [(0.0, 0.0), (0.9, 0.0), (0.95, 0.5), (1.0, 0.0)])
    for k in range(12):
        a = k / 12 * math.tau + rnd.uniform(-0.12, 0.12)
        rr = r * rnd.uniform(0.95, 1.08)
        tsprite((cx + math.cos(a) * rr, cy + math.sin(a) * rr, rnd.uniform(0.4, 1.2)), rnd.uniform(1.8, 2.6), SMOKE,
                rnd.choice(("BFEFFF", "8FE3FF")), 0.7, opacity=0.4, roll=rnd.uniform(0, 6))
    for k in range(18):
        a = k / 18 * math.tau + rnd.uniform(-0.15, 0.15)
        rr = r * rnd.uniform(1.05, 1.45)
        p = Vector((cx + math.cos(a) * rr, cy + math.sin(a) * rr, rnd.uniform(0.6, 2.0)))
        ob = tsprite(p, rnd.uniform(0.35, 0.6), GLOW, rnd.choice(("8FE3FF", "3FC8FF", "BFEFFF")), 6.0, stretch=3.2)
        ob["radial"] = (math.cos(a), math.sin(a))


def _jag(rnd, a, b, k, amp):
    a, b = Vector(a), Vector(b)
    side = Vector((-(b - a).y, (b - a).x, 0)).normalized()
    out = []
    for i in range(k):
        t = i / k
        out.append(tuple(a.lerp(b, t) + side * (0 if i == 0 else rnd.uniform(-amp, amp))
                         + Vector((0, 0, 0 if i == 0 else rnd.uniform(-0.25, 0.25)))))
    return out


def lightning(points, seed=7, color="3FD0F5"):
    """Éclair : 10 à 12 petits segments par saut (retirés toutes les 0,05 s en jeu), une fourche, cœur blanc
    fin + halo doux peu opaque (deux Beams), lueur aux points touchés."""
    rnd = random.Random(seed)
    pts = []
    for a, b in zip(points, points[1:]):
        pts += _jag(rnd, a, b, 11, 0.55)
    pts.append(tuple(Vector(points[-1])))
    soft = ((0.0, 0.0), (0.5, 1.0), (1.0, 0.0))
    ribbon_cam(pts, [2.2] * len(pts), color, 2.4, ((0.0, 0.0), (0.5, 0.4), (1.0, 0.0)), ((0.0, 1.0), (1.0, 1.0)),
             name="A14_BoltGlow")
    ribbon_cam(pts, [0.4] * len(pts), C.WHITE, 12.0, soft, ((0.0, 1.0), (1.0, 1.0)), name="A14_BoltCore")
    mid = Vector(pts[len(pts) // 3])
    fork = _jag(rnd, tuple(mid), tuple(mid + Vector((rnd.uniform(-3, 3), rnd.uniform(-3, -1), -0.6))), 5, 0.4)
    ribbon_cam(fork, [0.2] * len(fork), C.WHITE, 9.0, soft, ((0.0, 1.0), (1.0, 0.2)), name="A14_BoltFork")
    ribbon_cam(fork, [0.9] * len(fork), color, 2.0, ((0.0, 0.0), (0.5, 0.35), (1.0, 0.0)), ((0.0, 1.0), (1.0, 0.2)),
             name="A14_BoltForkGlow")
    for p in points[1:]:
        tsprite(p, 3.4, GLOW, color, 3.5, opacity=0.7)
        tsprite(p, 1.6, GLOW, C.WHITE, 9.0)


def streak_shot(start, end, color, head="FFF8EC", width=0.6, h=2.4):
    """Projectile en lumière : Trail long qui s'amincit (couleur saturée de l'arme), tête fine et claire."""
    s, e = Vector((start[0], start[1], h)), Vector((end[0], end[1], h))
    ribbon_cam([tuple(s.lerp(e, t)) for t in (0.0, 0.4, 0.75, 0.93, 1.0)],
               [0.02, width * 0.35, width * 0.75, width, width * 0.6], color, 4.5,
               ((0.0, 0.0), (0.5, 1.0), (1.0, 0.0)), ((0.0, 0.0), (0.5, 0.45), (1.0, 1.0)), name="A14_Shot")
    tsprite(e, width * 2.4, GLOW, color, 4.5, opacity=0.85)
    tsprite(e, width * 1.1, GLOW, head, 10.0, stretch=1.6)


def telegraph(center, r, progress=0.6):
    """Alerte du joueur : anneau or-orangé épais au bord dégradé (Transparency 0,4 au plus fort), un second
    anneau qui se resserre jusqu'à l'impact, un voile très léger dedans. Pas de disque plein."""
    C.disc(center, r, 0.07, "FFB020", 2.6, [(0.0, 0.0), (0.7, 0.0), (0.86, 0.6), (0.94, 0.6), (1.0, 0.0)])
    C.disc(center, r * (1.0 - 0.55 * progress), 0.06, "FFD45A", 2.6, [(0.0, 0.0), (0.8, 0.0), (0.9, 0.5), (1.0, 0.0)])
    C.disc(center, r, 0.05, "FFB020", 1.0, [(0.0, 0.08), (0.9, 0.12), (1.0, 0.0)])


def meteor(target, t=0.6, seed=9):
    """Météore : roc de feu (lueur, flammes, cœur blanc) qui tombe en diagonale avec une colonne de fumée."""
    rnd = random.Random(seed)
    tx, ty = target
    top = Vector((tx + 9.0, ty + 7.0, 20.0))
    end = Vector((tx, ty, 1.0))
    p = top.lerp(end, t)
    d = (end - top).normalized()
    tsprite(p, 6.5, GLOW, "FFB020", 5.0)
    tsprite(p, 3.0, GLOW, C.WHITE, 10.0)
    for k in range(10):
        q = p - d * rnd.uniform(0.3, 4.5) + Vector((rnd.uniform(-0.5, 0.5), rnd.uniform(-0.5, 0.5), rnd.uniform(-0.3, 0.3)))
        tsprite(q, rnd.uniform(2.0, 3.6), CORE, rnd.choice(("FFE27A", "FFC21A")), 4.0, opacity=0.9, roll=rnd.uniform(0, 6))
    for k in range(8):
        q = p - d * rnd.uniform(3.0, 10.0) + Vector((rnd.uniform(-0.8, 0.8), rnd.uniform(-0.8, 0.8), 0))
        tsprite(q, rnd.uniform(1.8, 3.2), SMOKE, rnd.choice(("8C8780", "BEB8B0")), opacity=0.4, roll=rnd.uniform(0, 6),
                emissive=False)


def holy_aura(center, r=6.0, seed=11):
    """Aura sacrée : flaque de lumière dorée, bord doux, poussière qui monte."""
    rnd = random.Random(seed)
    cx, cy = center
    tsprite((cx, cy, 0.07), 2.1 * r, GLOW, "FFC21A", 1.6, opacity=0.55, flat=True)
    tsprite((cx, cy, 0.09), 2.05 * r, SHOCK, "FFE8B8", 3.0, opacity=2.4, flat=True)
    for k in range(14):
        a = rnd.uniform(0, math.tau)
        rr = r * math.sqrt(rnd.random()) * 0.9
        tsprite((cx + math.cos(a) * rr, cy + math.sin(a) * rr, rnd.uniform(0.3, 3.5)), rnd.uniform(0.3, 0.6), GLOW,
                rnd.choice(("FFE8B8", "FFC21A")), 7.0)


# =============================================================================================
# Vues (caméra de jeu, comme en Play)


_bloom = C.bloom
C.bloom = lambda sc: _bloom(sc, threshold=0.95, strength=0.6, size=0.6)

GOBS = [M.goblin_grunt, M.goblin_grunt, M.goblin_archer, M.goblin_shaman, M.goblin_bomber]


def big_ground():
    C.S.block("A14_BigGround", (0.0, -40.0, -0.62), (420.0, 420.0, 1.0), "Leaf.d", jitter=0.0)


def ring_horde(rnd, player, n=40, keep=10.0, extra=()):
    pts = list(extra)
    while len(pts) < n + len(extra):
        x, y = player[0] + rnd.uniform(-30, 30), player[1] + rnd.uniform(-34, 12)
        if math.hypot(x - player[0], y - player[1]) < keep or any(math.hypot(x - a, y - b) < 2.2 for a, b in pts):
            continue
        pts.append((x, y))
    return pts


def crowd(rnd, n, player, box, keep=7.0, extra=()):
    pts = list(extra)
    while len(pts) < n + len(extra):
        x, y = rnd.uniform(box[0], box[1]), rnd.uniform(box[2], box[3])
        if math.hypot(x - player[0], y - player[1]) < keep or any(math.hypot(x - a, y - b) < 2.0 for a, b in pts):
            continue
        pts.append((x, y))
    return pts


def cam(sc, player, look=None):
    """Caméra du jeu (shared/Config/Movement.luau, Camera) : Distance 32, Pitch 42, FocusAhead 5, FocusHeight 2,5,
    FieldOfView 70 (vertical)."""
    px, py = player
    fx, fy, fz = px, py - 5.0, 2.5
    d, pitch = 32.0, math.radians(42.0)
    ob = B.camera(sc, (fx, fy + d * math.cos(pitch), fz + d * math.sin(pitch)), (fx, fy, fz), lens=30)
    cd = sc.camera.data
    cd.sensor_fit = "VERTICAL"
    cd.sensor_height = 24.0
    cd.lens = 12.0 / math.tan(math.radians(35.0))
    return ob


def view_melee_a(out):
    view_melee(out, upright=True)


def view_melee(out, upright=False):
    rnd = random.Random(1)
    sc = C.arena(1)
    player = (0.0, 4.0)
    CAM[0] = cam_pos(player)
    BD.dressed("Knight", 3, player[0], y=player[1])
    C.place_weapon(C.broadsword, Vector((player[0], player[1], 0)) + C.R_GRIP, rot=C.HELD["sword"], scale=C.HELD_SCALE)
    (slash_upright if upright else slash)(player)
    hits = [(-5.2, -0.6), (-0.6, -3.6), (4.6, -1.8)]
    for k, (x, y) in enumerate(hits):
        hit((x, y, 2.4), seed=k)
    chain = [(10.0, 2.0, 2.4), (13.5, -4.5, 2.2), (9.5, -10.0, 2.2), (15.0, -14.0, 2.2)]
    lightning(chain)
    big_ground()
    pts = ring_horde(rnd, player, 34, keep=11.0, extra=hits + [(c[0], c[1]) for c in chain[1:]])
    C.horde(pts, GOBS, seed=3, hit=tuple(range(6)))
    cam(sc, player)
    C.render(sc, out)


def view_fire(out):
    rnd = random.Random(2)
    sc = C.arena(2)
    player = (0.0, 6.0)
    CAM[0] = cam_pos(player)
    BD.dressed("Mage", 3, player[0], y=player[1])
    C.place_weapon(C.firestaff, Vector((player[0], player[1], 0)) + C.R_GRIP + Vector((0, -0.2, 0.2)),
                   rot=C.HELD["staff"], scale=C.HELD_SCALE)
    fireball((player[0] - 0.8, player[1] - 2.0), (-3.0, -1.0), seed=2)
    explosion((-8.0, -6.0), 6.0, seed=4)
    telegraph((8.0, -5.0), 6.0, progress=0.6)
    meteor((8.0, -5.0), t=0.55)
    big_ground()
    pts = ring_horde(rnd, player, 32, keep=12.0,
                     extra=[(-8.0, -6.5), (-6.0, -4.4), (-10.2, -7.6), (7.0, -4.0), (9.6, -6.4)])
    C.horde(pts, GOBS, seed=9, hit=(0, 1, 2))
    cam(sc, player)
    C.render(sc, out)


def view_frost(out):
    rnd = random.Random(3)
    sc = C.arena(3)
    player = (0.0, 2.0)
    CAM[0] = cam_pos(player)
    BD.dressed("Archer", 3, player[0], y=player[1])
    C.place_weapon(C.longbow, Vector((player[0], player[1], 0)) + C.L_GRIP + Vector((0.2, -0.2, 0.3)),
                   rot=C.HELD["bow"], scale=C.HELD_SCALE)
    frost_nova(player, 7.0)
    for k, (dx, dy) in enumerate(((-11.0, -14.0), (-4.0, -17.0), (4.0, -17.0), (11.0, -13.0))):
        sx, sy = player[0] + dx * 0.25, player[1] + dy * 0.25
        ex, ey = player[0] + dx * 1.0, player[1] + dy * 1.0
        if k % 2 == 0:
            streak_shot((sx, sy), (ex, ey), "2EF0C0", width=1.2)     # flèches : turquoise (le vert se perd sur l herbe)
        else:
            streak_shot((sx, sy), (ex, ey), "C08CFF", width=1.0)     # dagues : blanc lilas (le violet est aux sorciers ennemis)
    ring = [(player[0] + math.cos(a) * 8.6, player[1] + math.sin(a) * 8.6) for a in (0.4, 2.0, 2.9, 4.1, 5.3)]
    big_ground()
    pts = ring_horde(rnd, player, 32, keep=12.0, extra=ring)
    C.horde(pts, GOBS, seed=13, hit=(0, 1, 2, 3, 4))
    cam(sc, player, look=5.0)
    C.render(sc, out)


VIEWS = {"melee": view_melee, "melee_a": view_melee_a, "fire": view_fire, "frost": view_frost}


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:]
    which, outdir = argv[0], os.path.abspath(argv[1])
    os.makedirs(outdir, exist_ok=True)
    for name in (list(VIEWS) if which == "all" else which.split(",")):
        VIEWS[name](os.path.join(outdir, f"fx2_{name}.png"))
