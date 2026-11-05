"""COHUE — fond de run pour juger les maquettes d'interface (A08, concept v3, 5 nov. 2026).

Une arène tout en tenons (piste B d'A01) : sol en gros blocs, chemin de terre, sapins et feuillus en
lisière, une horde de gobelins en briques fines tournés vers un chevalier vu de dos, caméra de jeu à la
troisième personne. Ce n'est pas un décor du jeu : seulement un fond réaliste pour l'UI.

Utilisation (Blender 5.2) :
  blender -b --factory-startup --python docs/dossier/ui-assets/concept/run_scene.py -- <sortie.png> [largeur hauteur]
"""

from __future__ import annotations

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.normpath(os.path.join(HERE, "..", "..", "..", "..", "assets", "voxel")))

import boards as BD  # noqa: E402
import brick  # noqa: E402
import build as B  # noqa: E402
import cohue_voxel as cv  # noqa: E402
import lobby  # noqa: E402
import models as M  # noqa: E402
import studs as S  # noqa: E402


def rnd(*a) -> float:
    return lobby.hnoise(*a)


def arena():
    """Sol en blocs de 8 × 8 studs, tons d'herbe alternés, chemin de terre au milieu."""
    for ix in range(-9, 9):
        for iy in range(-4, 18):
            x, y = ix * 8 + 4, iy * 8 + 4
            path = abs(x) <= 4
            col = "Leather.l" if path else ("Leaf.d" if (ix + iy) % 3 else "Leaf")
            h = 2 + (1 if (not path and rnd(ix, iy, 5) > 0.82) else 0)
            S.block(f"G_{ix}_{iy}", (x, y, h / 2 - 2), (8, 8, h), col, jitter=0.03)


def edge_trees():
    for i in range(26):
        side = -1 if i % 2 else 1
        x = side * (30 + 26 * rnd(i, 1, 9))
        y = -6 + i * 5 + 4 * rnd(i, 2, 9)
        if rnd(i, 3, 9) > 0.45:
            S.pine(f"Pine{i}", (x, y, 0), height=12 + 8 * rnd(i, 4, 9), seed=i)
        else:
            S.tree(f"Tree{i}", (x, y, 0), height=10 + 5 * rnd(i, 5, 9), seed=i, autumn=(i % 5 == 0))


def horde(player=(0.0, 0.0)):
    brick.STUD_TEXTURE = True
    cv.to_blender = brick.to_blender
    bases = []
    for fn in (M.goblin_grunt, M.goblin_archer, M.goblin_shaman, M.goblin_bomber):
        vox, origin, _ = fn()
        ob = brick.to_blender(vox, origin, voxel=lobby.G4)
        ob.location = (0, -500, 0)
        bases.append(ob)
    placed = 0
    i = 0
    while placed < 64 and i < 400:
        i += 1
        x = (rnd(i, 11, 3) - 0.5) * 56
        y = 6 + 54 * rnd(i, 12, 3) ** 1.3
        if math.hypot(x - player[0], y - player[1]) < 7:
            continue
        kind = 0 if rnd(i, 13, 3) < 0.55 else int(1 + rnd(i, 14, 3) * 2.99)
        ob = bases[kind].copy()
        bases[kind].users_collection[0].objects.link(ob)
        theta = math.atan2(player[0] - x, -(player[1] - y)) + (rnd(i, 15, 3) - 0.5) * 0.6
        ob.location = (x, y, 0)
        ob.rotation_euler = (0, 0, theta)
        placed += 1


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = os.path.abspath(argv[0] if argv else os.path.join(HERE, "run_scene.png"))
    res = (int(argv[1]), int(argv[2])) if len(argv) > 2 else (1688, 780)
    sc = BD.fresh()
    B.diorama_light(sc, sun_elev=50, sun_az=-35, strength=4.6, world="9FD3F7", world_strength=1.0)
    lobby.painted_sky(sc)
    arena()
    edge_trees()
    for k, (x, y, z, s) in enumerate([(-90, 220, 30, 2.2), (110, 240, 40, 2.6), (10, 260, 55, 2.0)]):
        lobby.cumulus((x, y, z), s, k)
    horde()
    BD.dressed("Knight", 3, 0.0, y=0.0, rot=math.pi)
    aspect = res[0] / res[1]
    if aspect < 1:      # téléphone portrait : caméra plus haute, champ plus large
        B.camera(sc, (0, -15, 12), (0, 9, 0.0), lens=17)
    else:
        B.camera(sc, (0, -21, 12.5), (0, 18, 0.0), lens=24 if aspect > 1.9 else 28)
    B.render(sc, out, res=res, samples=32)
    print("rendered", out)


main()
