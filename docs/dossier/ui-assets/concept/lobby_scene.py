"""COHUE — fond de lobby pour les maquettes d'interface (A08, 5 nov. 2026).

Rend le lobby en tenons d'A01 (assets/voxel/lobby.py, style « studs ») vu depuis l'arrivée, à hauteur de
joueur, aux trois formats des maquettes. Ce n'est qu'un fond : le lobby réel est construit par A01 dans
Studio.

  blender -b --factory-startup --python docs/dossier/ui-assets/concept/lobby_scene.py -- <dossier_sortie>
"""

from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.normpath(os.path.join(HERE, "..", "..", "..", "..", "assets", "voxel")))

import build as B  # noqa: E402
import lobby  # noqa: E402

FORMATS = {  # nom : (résolution, position caméra, cible, focale)
    "lobby_landscape": ((1688, 780), (0, 46, 9), (0, -30, 10), 20),
    "lobby_pc": ((1920, 1080), (0, 46, 9), (0, -30, 10), 22),
    "lobby_portrait": ((780, 1688), (0, 40, 12), (0, -30, 8), 14),
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = os.path.abspath(argv[0] if argv else HERE)
    os.makedirs(out, exist_ok=True)
    sc, _ = lobby.build_scene("studs")
    for name, (res, loc, target, lens) in FORMATS.items():
        B.camera(sc, loc, target, lens=lens)
        B.render(sc, os.path.join(out, f"{name}.png"), res=res, samples=32)
        print("rendered", name)


main()
