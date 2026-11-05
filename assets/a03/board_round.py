"""COHUE — A03, planche : trois gobelins ronds dans le style du fantôme (réponse au « j'aime pas ce style »).

    blender -b --factory-startup --python assets/a03/goblins_round.py -- assets/a03/review
    python assets/a03/board_round.py

Sortie : assets/a03/03-gobelins-ronds.jpg.
"""

from __future__ import annotations

import os

import board_ghoststyle as G  # noqa: E402  (mêmes polices et outils de mise en page)

C = G.C
OUT = os.path.join(G.HERE, "03-gobelins-ronds.jpg")


def main():
    im, d = C.canvas(G.W, 3200)
    C.header(d, "Trois gobelins ronds, dans le style de ton fantôme",
             "Voxels deux fois plus fins pour des formes rondes (tête en dôme, ventre rond), un seul accessoire chacun, "
             "yeux noirs à reflet, grand sourire à dents. Rendus Blender d'A03.", G.W)
    y = G.section(d, 200, "1. Ton fantôme et les trois propositions")
    crop = G.r("ghostenemy_crop.png")
    box = C.paste_fit(im, crop, (60, y, 520, y + 700))
    G.centered(d, (box[0] + box[2]) // 2, box[3] + 16, "Ton fantôme", G.NAME, C.INK)
    box = C.paste_fit(im, G.r("round_variants.png"), (560, y, G.W - 60, y + 700))
    y = G.labels_under(d, box, [("1. Bandana", "bandana rouge noué, petite massue", 0.13),
                                ("2. Capuche", "capuche rouge à pompon, il mord", 0.5),
                                ("3. Petite marmite", "marmite ronde en casque, cuillère", 0.87)])
    y = G.section(d, y, "2. De profil")
    box = C.paste_fit(im, G.r("round_profiles.png"), (60, y, G.W - 60, y + 855))
    y = box[3] + 40
    C.wrap(d, (60, y), "Les oreilles sont relevées en biais, le nez est pointu et le sourire montre les dents : avec "
           "une tête ronde et verte, de grandes oreilles à l'horizontale et de grands yeux, le gobelin rappelait un "
           "personnage très connu.", G.TEXT, C.INK, G.W - 120)
    im = im.crop((0, 0, G.W, y + 120))
    im.save(OUT, quality=88, optimize=True)
    print(OUT, im.size)


if __name__ == "__main__":
    main()
