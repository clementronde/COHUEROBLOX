"""COHUE — A03, trois gobelins ronds et simples, dans le style lisse du fantôme de Clément (5 nov. 2026).

Retour de Clément sur les premiers gobelins « style fantôme » : trop carrés (trop Minecraft), et le design du gobelin
ne lui plaît pas. Ici : voxels deux fois plus fins (0,125 stud) pour des formes rondes comme le fantôme (tête en dôme,
ventre rond), un seul accessoire par gobelin, yeux noirs à reflet et petites joues.

    blender -b --factory-startup --python assets/a03/goblins_round.py -- <dossier de sortie>
"""

from __future__ import annotations

import importlib.util
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.append(os.path.join(os.path.dirname(HERE), "voxel"))

from cohue_voxel import Vox  # noqa: E402

CELL = 0.125


def taper(v: Vox, x0: int, x1: int, r0: float, r1: float, z0: float, z1: float, col: str, y=-0.5):
    """Corne effilée horizontale (oreille) de x0 à x1, rayon r0 -> r1, qui monte de z0 à z1."""
    n = max(1, x1 - x0)
    for x in range(x0, x1 + 1):
        t = (x - x0) / n
        r = r0 + (r1 - r0) * t
        zc = z0 + (z1 - z0) * t
        for yy in range(math.floor(y - r), math.ceil(y + r) + 1):
            for zz in range(math.floor(zc - r), math.ceil(zc + r) + 1):
                if ((yy + 0.5 - y) / r) ** 2 + ((zz + 0.5 - zc) / r) ** 2 <= 1.0:
                    v.set(x, yy, zz, col)


def front_cells(v: Vox, x: int, z: int):
    ys = [k[1] for k in v.c if k[0] == x and k[2] == z]
    return min(ys) if ys else None


def paint_front(v: Vox, cells, col):
    for (x, z) in cells:
        y = front_cells(v, x, z)
        if y is not None:
            v.set(x, y, z, col)


def round_base(name: str, tunic: str) -> Vox:
    v = Vox(name)
    skin = "Lime"
    # Jambes courtes et pieds
    v.box(1, 3, -1, 1, 1, 4, skin + ".d")
    v.box(1, 3, -3, 1, 0, 0, "Bark")
    # Ventre rond (tunique)
    v.ell(0, 0, 9.5, 6.0, 5.2, 6.0, tunic, zmin=4)
    v.ell(0, 0, 9.5, 6.05, 5.25, 1.2, "Bark", zmin=6, zmax=7)        # ceinture
    # Bras ronds et mains
    v.ell(6.5, -0.5, 10.0, 1.7, 1.7, 3.2, skin)
    v.ell(7.0, -1.0, 6.8, 1.6, 1.6, 1.4, skin + ".d")
    # Tête en dôme, grande (45 % de la hauteur)
    v.ell(0, -0.5, 22.0, 8.5, 7.5, 7.8, skin, zmin=14)
    # Oreilles longues et effilées, pointes relevées
    taper(v, 7, 15, 3.0, 1.0, 22.5, 27.5, skin)                      # oreilles larges, relevées d'environ 30°
    taper(v, 8, 13, 1.4, 0.5, 22.8, 25.8, skin + ".d", y=-2.0)
    v.mirror_x()
    # Visage : yeux noirs ovales (3 x 4), joues, petit nez rond, bouche ouverte à une dent
    face(v, skin)
    return v


def face(v: Vox, skin="Lime"):
    """Visage espiègle de gobelin : yeux noirs à reflet un peu plissés, sourcils en biais, nez pointu, grand
    sourire à trois dents. (Pas de grands yeux ronds de bébé : avec la tête ronde et verte, ça rappelait un
    personnage connu.)"""
    eye_l = [(x, z) for x in range(2, 5) for z in range(20, 23)] + [(3, 23), (4, 23)]
    eye_r = [(-1 - x, z) for (x, z) in eye_l]
    paint_front(v, eye_l + eye_r, "Ink")
    brow_l = [(2, 24), (3, 24), (4, 25), (5, 25)]
    paint_front(v, brow_l + [(-1 - x, z) for (x, z) in brow_l], skin + ".d")
    paint_front(v, [(5, 18), (6, 18), (-6, 18), (-7, 18)], "Tomato.l")
    grin = [(x, 16) for x in range(-4, 4)] + [(x, 15) for x in range(-3, 3)] + [(-5, 17), (4, 17)]
    paint_front(v, grin, "Plum.dd")
    paint_front(v, [(-3, 16), (0, 16), (2, 16)], "Cream")
    for (x, z, d) in ((-1, 19, 1), (0, 19, 1), (-1, 20, 1), (0, 20, 1), (-1, 19, 2), (0, 19, 2), (0, 18, 3),
                      (-1, 18, 3)):
        y = front_cells(v, x, z)
        if y is not None:
            v.set(x, y - 1, z, skin)                                       # nez pointu qui avance


def _meta(v: Vox, label: str, role: str):
    glints = []
    for x in (2, -5):
        y = front_cells(v, x, 22)
        glints.append((x, (y if y is not None else -7) - 0.3, 22))
    return {"kind": "enemy", "cell": CELL, "eyes": [], "glints": glints, "glint_r": 0.09, "label": label,
            "role": role}


def goblin_bandana():
    v = round_base("Goblin_Bandana", "Tomato")
    # Bandana rouge noué autour du dôme, noeud qui pend derrière
    v.ell(0, -0.5, 26.5, 8.6, 7.6, 1.6, "Tomato", zmin=25, zmax=28)
    v.ell(0, -0.5, 22.0, 8.0, 7.0, 7.3, "Lime", zmin=25, zmax=28)    # garde le visage dégagé sous le bandeau
    v.ell(0, -0.5, 26.5, 8.6, 7.6, 1.6, "Tomato", zmin=26, zmax=27)
    v.box(-1, 0, 7, 9, 24, 26, "Tomato")
    v.box(-2, 1, 9, 10, 21, 23, "Tomato.d")
    # Petite massue en bois, ronde (main droite, -X)
    v.box(-8, -7, -2, -1, 6, 15, "Bark")
    v.ell(-7.5, -1.5, 17.5, 2.2, 2.2, 3.2, "Leather")
    return v, "bottom", _meta(v, "Bandana", "mêlée, massue")


def goblin_hood():
    v = round_base("Goblin_Hood", "Ember")
    # Capuche rouge qui couvre le dôme, oreilles qui sortent sur les côtés, pompon sur le dessus
    v.ell(0, 0.0, 23.0, 9.2, 8.3, 8.4, "Tomato", zmin=22)
    v.ell(0, -1.6, 21.0, 7.6, 7.0, 7.4, "Lime", zmin=14, zmax=27)    # le visage dans l'ouverture de la capuche
    taper(v, 7, 15, 3.0, 1.0, 22.5, 27.5, "Lime")
    taper(v, -16, -8, 1.0, 3.0, 27.5, 22.5, "Lime")
    v.ell(0, 0.5, 31.5, 1.8, 1.8, 1.8, "Cream")                      # pompon
    face(v)
    return v, "bottom", _meta(v, "Capuche", "mêlée, sans arme : il mord")


def goblin_pot():
    v = round_base("Goblin_Pot", "Tomato")
    # Petite marmite ronde en casque (dôme rouge, rebord sombre, bouton), cuillère en bois
    v.ell(0, -0.5, 26.0, 8.4, 7.4, 5.0, "Tomato", zmin=26)
    v.ell(0, -0.5, 26.0, 9.0, 8.0, 0.8, "Tomato.d", zmin=26, zmax=26)
    v.box(-1, 0, -1, 0, 31, 32, "Ink")
    v.box(-8, -7, -2, -1, 6, 16, "Bark")
    v.ell(-7.5, -1.5, 18.0, 1.9, 1.4, 2.6, "Leather")
    v.ell(-7.5, -2.3, 18.4, 1.2, 0.6, 1.8, "Leather.d")
    return v, "bottom", _meta(v, "Petite marmite", "mêlée, cuillère")


VARIANTS = [goblin_bandana, goblin_hood, goblin_pot]


if __name__ == "__main__":
    import bpy  # noqa: F401

    _spec = importlib.util.spec_from_file_location("a03_ghoststyle", os.path.join(HERE, "ghoststyle.py"))
    G = importlib.util.module_from_spec(_spec)
    _spec.loader.exec_module(G)
    K, B, A14, S = G.K, G.B, G.A14, G.S

    argv = sys.argv[sys.argv.index("--") + 1:]
    outdir = os.path.abspath(argv[0])
    os.makedirs(outdir, exist_ok=True)

    # Trois gobelins de trois-quarts face
    sc = A14.fresh()
    G.plinth(sc, 40, 18)
    for k, fn in enumerate(VARIANTS):
        G.place(fn, (-8.0 + k * 8.0, 0, 0), rot_z=math.radians(-18 + 18 * k))
    B.camera(sc, (0.0, -27.0, 7.0), (0.0, 0.0, 2.2), lens=48)
    A14.render(sc, os.path.join(outdir, "round_variants.png"), res=(2400, 900), samples=64)

    # Les mêmes de profil et de dos
    K._templates.clear()
    sc = A14.fresh()
    G.plinth(sc, 40, 18)
    for k, fn in enumerate(VARIANTS):
        G.place(fn, (-8.0 + k * 8.0, 0, 0), rot_z=math.radians(-100))
    B.camera(sc, (0.0, -27.0, 7.0), (0.0, 0.0, 2.2), lens=48)
    A14.render(sc, os.path.join(outdir, "round_profiles.png"), res=(2400, 900), samples=48)
