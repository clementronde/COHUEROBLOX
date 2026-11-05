"""COHUE — portraits d'équipiers pour les maquettes (A08, concept v3.2).

En jeu, le portrait sera la vignette Roblox du joueur (Players:GetUserThumbnailAsync, HeadShot) dans un
cadre à la couleur de l'équipier. Pour les maquettes : la tête du mannequin d'A01 avec le casque de
classe (palier 1), en briques, fond transparent.

  blender -b --factory-startup --python docs/dossier/ui-assets/concept/avatars.py -- <dossier_sortie>
"""

from __future__ import annotations

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.normpath(os.path.join(HERE, "..", "..", "..", "..", "assets", "voxel")))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import boards as BD  # noqa: E402
import brick  # noqa: E402
import build as B  # noqa: E402
import cohue_voxel as cv  # noqa: E402

cv.to_blender = brick.to_blender
BD.cv.to_blender = brick.to_blender
B.cv.to_blender = brick.to_blender


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = os.path.abspath(argv[0] if argv else os.path.join(HERE, "avatars"))
    os.makedirs(out, exist_ok=True)
    for cls in ("Knight", "Archer", "Mage"):
        sc = BD.fresh()
        B.diorama_light(sc, sun_elev=45, sun_az=-30, strength=4.2, world="DDE8FF", world_strength=1.1)
        BD.dressed(cls, 1, 0.0, y=0.0, rot=0.0)
        target = Vector((0.0, 0.0, 5.25))
        yaw, el = math.radians(16), math.radians(10)
        d = Vector((math.sin(yaw) * math.cos(el), -math.cos(yaw) * math.cos(el), math.sin(el)))
        B.camera(sc, tuple(target + d * 20), tuple(target), ortho=3.4)
        B.render(sc, os.path.join(out, f"avatar_{cls.lower()}.png"), res=(256, 256), transparent=True, samples=32)
        print("rendered", cls)


main()
