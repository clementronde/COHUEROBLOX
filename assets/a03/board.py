"""COHUE — A03, montage de la planche concept des ennemis et des boss (étape 2, porte 2).

    blender -b --factory-startup --python assets/a03/concept.py -- all assets/a03/review
    python assets/a03/board.py

Entrées : assets/a03/review/*.png et tris.json. Sortie : assets/a03/01-ennemis-boss-concept.jpg.
Mise en page : outils de A01 (assets/style/compose.py), comme la planche de A14.
"""

from __future__ import annotations

import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "assets", "style"))
import compose as C  # noqa: E402

REVIEW = os.path.join(HERE, "review")
OUT = os.path.join(HERE, "01-ennemis-boss-concept.jpg")
W, H = 2400, 8000
CAPTION = (70, 58, 82)
TEXT = C.font("Inter-Medium.ttf", 27)
LABEL = C.font("Inter-Medium.ttf", 21)


def r(name):
    return os.path.join(REVIEW, name)


def section(d, y, title):
    d.text((60, y), title, font=C.H2, fill=C.INK)
    return y + 70


def centered(d, x, y, text, fnt, fill):
    d.text((x - d.textlength(text, font=fnt) / 2, y), text, font=fnt, fill=fill)


def silhouette(name, size):
    im = Image.open(r(f"a03_silhouettes_{name}.png")).convert("RGBA")
    im = im.crop(im.getbbox())
    k = size / max(im.size)
    native = im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)
    return native


def main():
    tris = json.load(open(r("tris.json"), encoding="utf-8"))
    im, d = C.canvas(W, H)
    C.header(d, "Ennemis et boss : planche concept",
             "A03, étape 2 (porte 2), DA du 5 nov. : briques fines à tenons, gros yeux ronds lisses, couleurs "
             "saturées. Rendus Blender ; avatar et équipement du Knight de A01 pour l'échelle.", W)

    # 1. Les trois familles
    y = section(d, 200, "1. Trois familles, trois silhouettes")
    box = C.paste_fit(im, r("a03_lineup.png"), (60, y, W - 60, y + 855))
    bw = box[2] - box[0]
    labels = [("Avatar R15", "échelle : 5,5 studs", 0.15),
              ("Goblin Grunt", "mêlée · monde 1 · cocotte en casque, louche", 0.385),
              ("Zombie Runner", "sauteur · monde 2 · tutu, chaussons, un oeil cousu", 0.61),
              ("Poltergeist", "tireur · monde 3 · flotte, lance ses livres", 0.845)]
    for name, sub, fx in labels:
        x = box[0] + int(bw * fx)
        centered(d, x, box[3] + 14, name, C.H3, C.INK)
        centered(d, x, box[3] + 54, sub, LABEL, CAPTION)
    y = box[3] + 120
    d.text((60, y), "Silhouettes en noir, de face : à 64 px (taille réelle) et à 128 px", font=C.H3, fill=C.INK)
    y += 56
    x = 60
    for key, name in (("goblin_grunt", "T à grandes oreilles"), ("zombie_runner", "Γ, bras tendus"),
                      ("ghost_poltergeist", "goutte, sans pieds"),
                      ("boss_hungry_coffin", "cercueil sur quatre mains")):
        d.rounded_rectangle((x, y, x + 540, y + 200), radius=20, fill=(255, 250, 240))
        small, big = silhouette(key, 64), silhouette(key, 128)
        im.paste(small, (x + 40, y + 140 - small.height), small)
        im.paste(big, (x + 150, y + 172 - big.height), big)
        d.text((x + 300, y + 80), name, font=LABEL, fill=C.INK)
        x += 570
    y += 250

    # 2. Le boss
    y = section(d, y, "2. Le boss du monde 2 : The Hungry Coffin")
    box = C.paste_fit(im, r("a03_boss.png"), (60, y, W - 60, y + 1283))
    y = C.wrap(d, (60, box[3] + 20),
               "Cercueil debout sur quatre mains de zombie ; le couvercle est une mâchoire, il porte une serviette "
               "nouée et tient une fourchette et un couteau. 19,5 studs, briques de 0,5. Sous le joueur, son "
               "attaque Lid Chomp : le télégraphe ennemi, rouge mat, se remplit jusqu'au coup (code couleur de A14 : "
               "le rouge est réservé aux ennemis).", TEXT, C.INK, W - 120) + 50

    # 3. Gobelins v1 contre v2
    y = section(d, y, "3. Les gobelins d'A01 : les refaire dans la DA actuelle")
    box = C.paste_fit(im, r("a03_compare.png"), (60, y, W - 60, y + 855))
    bw = box[2] - box[0]
    g = tris["Enemy_GoblinGrunt"]
    for name, sub, fx in (("v1 voxel", "dans COHUE aujourd'hui · 656 à 792 triangles", 0.215),
                          ("v2, maille du jeu", f"technique B : fusionnée, tenons en texture · {g['fused_tris_v1_style']} "
                           "triangles + yeux", 0.5),
                          ("v2, briques", f"référence de la planche · {g['bricks_tris_sans_chanfrein']:,} triangles "
                           "sans chanfrein".replace(",", " "), 0.79)):
        x = box[0] + int(bw * fx)
        centered(d, x, box[3] + 14, name, C.H3, C.INK)
        centered(d, x, box[3] + 54, sub, LABEL, CAPTION)
    y = C.wrap(d, (60, box[3] + 110),
               "Mêmes formes et mêmes gags qu'en v1 ; la tête grossit, les yeux deviennent ronds et lisses, les "
               "tenons arrivent. Les briques chanfreinées coûtent 5 fois plus de triangles : la horde utilise la "
               "maille fusionnée du milieu (moins de 1 000 triangles avec les yeux), les boss gardent les briques.",
               TEXT, C.INK, W - 120) + 50

    # 4. Test de lisibilité
    y = section(d, y, "4. Test de lisibilité : 70 ennemis à la caméra du jeu, sur l'herbe et sur le sable")
    gap = 30
    cw = (W - 120 - gap) // 2
    ch = int(cw * 9 / 16)
    C.paste_fit(im, r("a03_horde_grass.png"), (60, y, 60 + cw, y + ch))
    C.paste_fit(im, r("a03_horde_sand.png"), (60 + cw + gap, y, W - 60, y + ch))
    y = C.wrap(d, (60, y + ch + 16),
               "Caméra de Config/Movement : 32 studs derrière le joueur, 42° sous l'horizon, champ vertical de 70°. "
               "36 Grunts, 20 Runners et 14 Poltergeists, dont 2 élites (anneau et couronne or). Maille fusionnée "
               "du jeu. De haut, la couleur du rôle se lit sur le dessus : cocotte rouge, noeud violet, livres verts.",
               TEXT, C.INK, W - 120) + 30
    d.text((60, y), "À la taille d'un écran de téléphone (640 px de large, sans agrandissement) :", font=C.H3,
           fill=C.INK)
    y += 50
    x = 60
    for name in ("a03_horde_grass.png", "a03_horde_sand.png"):
        small = Image.open(r(name)).convert("RGB").resize((640, 360), Image.LANCZOS)
        im.paste(small, (x, y))
        d.rectangle((x - 3, y - 3, x + 643, y + 363), outline=C.INK, width=3)
        x += 680
    y += 420

    # 5. Règles
    d.rectangle((60, y, W - 60, y + 3), fill=C.INK)
    y = section(d, y + 24, "5. À généraliser aux 21 modèles")
    rules = [
        ("Horde : briques de 0,25 stud, une maille fusionnée par ennemi (moins de 800 triangles), tenons en "
         "texture (Resurface en jeu). Mini-boss et boss : briques de 0,5.", "Lime"),
        ("Gros yeux ronds et lisses, sur une MeshPart à part sans tenons : blancs à pupille Ink ; sur les "
         "fantômes, Ink à reflet blanc (un oeil blanc disparaît sur le corps crème).", "Ink"),
        ("La famille se lit à la silhouette (T, Γ, goutte), le rôle à la couleur du dessus : rouge mêlée, vert "
         "tireur, violet soutien, orange kamikaze.", "Tomato"),
        ("Un gag par ennemi, montré par un objet : cocotte et louche, tutu et chaussons, pile de livres, "
         "serviette et couverts.", "Grape"),
        ("Pas de Neon sur un ennemi ordinaire : il est réservé aux élites (or), à la capture (rose) et aux "
         "effets.", "Gold"),
    ]
    for text, key in rules:
        d.rounded_rectangle((62, y + 6, 84, y + 28), radius=5, fill=C.rgb(key))
        y = C.wrap(d, (104, y), text, TEXT, C.INK, W - 170) + 10
    im = im.crop((0, 0, W, min(H, y + 40)))
    im.save(OUT, quality=88, optimize=True)
    print(OUT, im.size, os.path.getsize(OUT))


if __name__ == "__main__":
    main()
