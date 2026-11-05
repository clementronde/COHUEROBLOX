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
W, H = 2400, 9000
CAPTION = (70, 58, 82)
TEXT = C.font("Inter-Medium.ttf", 30)
NAME = C.font("Gilroy-Bold.ttf", 36)
LABEL = C.font("Inter-Medium.ttf", 27)
H2 = C.font("Gilroy-ExtraBold.ttf", 44)


def r(name):
    return os.path.join(REVIEW, name)


def section(d, y, title):
    d.text((60, y), title, font=H2, fill=C.INK)
    return y + 80


def centered(d, x, y, text, fnt, fill):
    d.text((x - d.textlength(text, font=fnt) / 2, y), text, font=fnt, fill=fill)


def labels_under(d, box, items):
    bw = box[2] - box[0]
    for name, sub, fx in items:
        x = box[0] + int(bw * fx)
        centered(d, x, box[3] + 16, name, NAME, C.INK)
        centered(d, x, box[3] + 62, sub, LABEL, CAPTION)
    return box[3] + 120


def silhouette(name, size):
    im = Image.open(r(f"a03_silhouettes_{name}.png")).convert("RGBA")
    im = im.crop(im.getbbox())
    k = size / max(im.size)
    return im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)


def main():
    tris = json.load(open(r("tris.json"), encoding="utf-8"))
    im, d = C.canvas(W, H)
    C.header(d, "Ennemis et boss : planche concept",
             "A03, étape 2 (porte 2), DA du 5 nov. : briques fines à tenons, gros yeux ronds lisses, couleurs "
             "saturées. Rendus Blender ; le Knight de A01 donne l'échelle.", W)

    # 1. Les trois familles
    y = section(d, 200, "1. Trois familles, trois silhouettes")
    box = C.paste_fit(im, r("a03_lineup.png"), (60, y, W - 60, y + 855))
    y = labels_under(d, box, [("Avatar", "échelle : 5,5 studs", 0.15),
                              ("Goblin Grunt", "mêlée · monde 1", 0.385),
                              ("Zombie Runner", "sauteur · monde 2", 0.605),
                              ("Poltergeist", "tireur · monde 3", 0.835)])
    d.text((60, y), "En noir, de face et de profil, à 64 px (taille réelle)", font=NAME, fill=C.INK)
    y += 60
    x = 60
    for key, name in (("goblin_grunt", "T, grandes oreilles"), ("zombie_runner", "Γ, bras tendus"),
                      ("ghost_poltergeist", "cloche, sans pieds"), ("boss_hungry_coffin", "cercueil sur mains")):
        d.rounded_rectangle((x, y, x + 545, y + 170), radius=20, fill=(255, 250, 240))
        front, side = silhouette(key, 64), silhouette(key + "_side", 64)
        im.paste(front, (x + 36, y + 100 - front.height), front)
        im.paste(side, (x + 130, y + 100 - side.height), side)
        d.text((x + 36, y + 116), name, font=LABEL, fill=C.INK)
        x += 570
    y += 230

    # 2. Le boss
    y = section(d, y, "2. Le boss du monde 2 : The Hungry Coffin")
    box = C.paste_fit(im, r("a03_boss.png"), (60, y, W - 60, y + 1283))
    y = C.wrap(d, (60, box[3] + 20),
               "Un cercueil affamé en bois clair, debout sur quatre mains de zombie. Le couvercle s'ouvre sur ses "
               "charnières dorées : dans le noir, deux gros yeux et des dents ; la langue pend sur une serviette nouée. "
               "Fourchette et couteau. 16 studs, briques de 0,5. Au sol, son attaque Lid Chomp : le télégraphe "
               "ennemi, rouge mat, se remplit jusqu'au coup (le rouge est réservé aux ennemis, règle de A14).",
               TEXT, C.INK, W - 120) + 50

    # 3. Gobelins
    y = section(d, y, "3. Les 4 gobelins d'A01, refaits dans la DA actuelle")
    box = C.paste_fit(im, r("a03_goblins.png"), (60, y, W - 60, y + 855))
    y = labels_under(d, box, [("Grunt", "mêlée : cocotte, louche", 0.165),
                              ("Archer", "tireur : capuche à pointe, arc", 0.42),
                              ("Shaman", "soutien : théière violette", 0.635),
                              ("Bomber", "kamikaze : bonnet orange, bombe", 0.835)])
    box = C.paste_fit(im, r("a03_compare.png"), (360, y, W - 360, y + 630))
    g = tris["Enemy_GoblinGrunt"]
    y = labels_under(d, box, [("v1 voxel", "dans COHUE aujourd'hui", 0.21),
                              ("v2, maille du jeu", f"{g['fused_tris_v1_style']} triangles + yeux", 0.5),
                              ("v2, briques", f"{g['bricks_tris_sans_chanfrein']} triangles", 0.79)])
    y = C.wrap(d, (60, y),
               "Mêmes formes et mêmes gags qu'en v1 ; la tête grossit, les yeux deviennent ronds et lisses, les "
               "tenons arrivent, le dessus de la tête porte la couleur du rôle. En jeu, la horde utilise la maille "
               "fusionnée (moins de 1 000 triangles avec les yeux) ; les briques chanfreinées coûtent 5 fois plus et "
               "restent aux boss.", TEXT, C.INK, W - 120) + 50

    # 4. Test de lisibilité
    y = section(d, y, "4. Test de lisibilité : la horde du monde 1 à la caméra du jeu")
    gap = 30
    cw = (W - 120 - gap) // 2
    ch = int(cw * 9 / 16)
    C.paste_fit(im, r("a03_horde_grass.png"), (60, y, 60 + cw, y + ch))
    C.paste_fit(im, r("a03_horde_sand.png"), (60 + cw + gap, y, W - 60, y + ch))
    y = labels_under(d, (60, y, 60 + cw, y + ch), [("Sur l'herbe", "", 0.5)]) - 40
    labels_under(d, (60 + cw + gap, y - ch - 80, W - 60, y - 80), [("Sur le sable", "", 0.5)])
    y = C.wrap(d, (60, y),
               "70 gobelins des 4 rôles (34 Grunts, 14 Archers, 10 Shamans, 12 Bombers) en maille du jeu, dont 2 "
               "élites (anneau et couronne or) et 1 capturable (anneau et cage roses, devant le joueur), avec de "
               "l'XP au sol et deux tirs ennemis à liseré crème. Caméra de Config/Movement : 32 studs derrière le joueur, 42° sous l'horizon, champ vertical "
               "de 70°. Le rôle se lit sur le dessus : cocotte rouge, capuche vert sombre à pointe, théière "
               "violette, bonnet orange à lunettes.",
               TEXT, C.INK, W - 120) + 30
    box = C.paste_fit(im, r("a03_horde_w23.png"), (60, y, 60 + cw, y + ch))
    C.wrap(d, (box[2] + 40, y + 10),
           "Mondes 2 et 3 sur leurs sols. À gauche, 30 Zombie Runners (peau grise) sur l'herbe sombre du "
           "cimetière ; à droite, 30 Poltergeists sur le bitume de la cour, près d'une marelle crème.",
           TEXT, C.INK, W - box[2] - 100)
    y = box[3] + 40
    d.text((60, y), "À la taille d'un écran de téléphone (640 px de large, sans agrandissement) :", font=NAME,
           fill=C.INK)
    y += 60
    x = 60
    for name in ("a03_horde_grass.png", "a03_horde_sand.png", "a03_horde_w23.png"):
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
        ("Gros yeux lisses sur une MeshPart à part, sans tenons : blancs à pupille Ink ; ovales Ink à reflet "
         "blanc sur les fantômes (un oeil blanc disparaît sur le corps crème).", "Ink"),
        ("La famille se lit à la silhouette (T, Γ, cloche), le rôle à la couleur et à la forme du dessus : "
         "rouge mêlée et sauteur, vert tireur, violet soutien, orange kamikaze.", "Tomato"),
        ("Un gag par ennemi, montré par un objet : cocotte et louche, théière, tutu et chaussons, pile de "
         "livres, serviette et couverts.", "Grape"),
        ("Écart au guide DA à valider : peau des zombies grise (Stone.d) au lieu de Sky.d. En bleu, le zombie "
         "rappelait un monstre bleu connu ; en vert, un dinosaure connu.", "Stone"),
        ("Pas de Neon sur un ennemi ordinaire : il est réservé aux élites (or), à la capture (rose) et aux "
         "effets.", "Gold"),
    ]
    for text, key in rules:
        d.rounded_rectangle((62, y + 8, 88, y + 34), radius=6, fill=C.rgb(key))
        y = C.wrap(d, (110, y), text, TEXT, C.INK, W - 180) + 12

    # 6. Question
    y += 30
    d.rounded_rectangle((60, y, W - 60, y + 190), radius=24, fill=(28, 23, 38))
    d.text((100, y + 30), "À valider (porte 2)", font=H2, fill=(255, 255, 255))
    C.wrap(d, (100, y + 100), "Ce style pour les 21 modèles, et les 4 gobelins d'A01 refaits comme en section 3 "
           "(sinon on garde la v1 voxel).", TEXT, (255, 255, 255), W - 200)
    y += 230
    im = im.crop((0, 0, W, min(H, y + 20)))
    im.save(OUT, quality=88, optimize=True)
    print(OUT, im.size, os.path.getsize(OUT))


if __name__ == "__main__":
    main()
