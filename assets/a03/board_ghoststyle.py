"""COHUE — A03, planche d'exemples : un gobelin dans le style du fantôme de Clément.

    blender -b --factory-startup --python assets/a03/ghoststyle.py -- assets/a03/review
    python assets/a03/board_ghoststyle.py [capture du fantôme]

Sortie : assets/a03/02-gobelin-style-fantome.jpg.
"""

from __future__ import annotations

import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "assets", "style"))
import compose as C  # noqa: E402

REVIEW = os.path.join(HERE, "review")
OUT = os.path.join(HERE, "02-gobelin-style-fantome.jpg")
W, H = 2400, 6000
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
        if sub:
            centered(d, x, box[3] + 62, sub, LABEL, CAPTION)
    return box[3] + 120


def main(ghost_capture=None):
    im, d = C.canvas(W, H)
    C.header(d, "Un gobelin dans le style de ton fantôme",
             "Voxels lisses (SmoothPlastic), sans tenons ni texture, deux tons par couleur, yeux noirs à reflet "
             "blanc. Rendus Blender des modèles d'A03, pour montrer le style à demander à Claude Design.", W)

    y = section(d, 200, "1. Ton fantôme et le Goblin Grunt dans le même style")
    if ghost_capture and os.path.exists(ghost_capture):
        g = Image.open(ghost_capture).convert("RGB")
        gw, gh = g.size
        g = g.crop((int(gw * 0.40), int(gh * 0.30), int(gw * 0.60), int(gh * 0.68)))
        crop = r("ghostenemy_crop.png")
        g.save(crop)
        box = C.paste_fit(im, crop, (60, y, 560, y + 700))
        centered(d, (box[0] + box[2]) // 2, box[3] + 16, "Ton fantôme (Ghostenemy)", NAME, C.INK)
        box = C.paste_fit(im, r("ghoststyle_grunt.png"), (600, y, W - 60, y + 700))
    else:
        box = C.paste_fit(im, r("ghoststyle_grunt.png"), (60, y, W - 60, y + 855))
    y = labels_under(d, box, [("De face", "", 0.17), ("De trois-quarts", "", 0.5), ("De profil", "", 0.83)])

    y = section(d, y, "2. Trois choix d'yeux")
    box = C.paste_fit(im, r("ghoststyle_eyes.png"), (60, y, W - 60, y + 855))
    y = labels_under(d, box, [("A. Noirs à reflet", "comme ton fantôme (recommandé)", 0.12),
                              ("B. Blancs et ronds", "pupille noire, comme la planche d'A03", 0.5),
                              ("C. Noirs et joues roses", "encore plus mignon", 0.88)])

    y = section(d, y, "3. Les 4 gobelins du monde 1, yeux A")
    box = C.paste_fit(im, r("ghoststyle_goblins.png"), (60, y, W - 60, y + 855))
    y = labels_under(d, box, [("Grunt", "mêlée : cocotte, louche", 0.165), ("Archer", "tireur : capuche, arc", 0.42),
                              ("Shaman", "soutien : théière", 0.635), ("Bomber", "kamikaze : bonnet, bombe", 0.835)])

    y = section(d, y, "4. Dans la horde, à la caméra du jeu")
    cw = 1500
    ch = int(cw * 9 / 16)
    box = C.paste_fit(im, r("ghoststyle_horde.png"), (60, y, 60 + cw, y + ch))
    small = Image.open(r("ghoststyle_horde.png")).convert("RGB").resize((640, 360), Image.LANCZOS)
    im.paste(small, (box[2] + 60, y))
    d.rectangle((box[2] + 57, y - 3, box[2] + 703, y + 363), outline=C.INK, width=3)
    C.wrap(d, (box[2] + 60, y + 390), "À la taille d'un écran de téléphone. Le rôle se lit au chapeau : cocotte "
           "rouge, capuche verte, théière violette, bonnet orange.", TEXT, C.INK, W - box[2] - 120)
    y = box[3] + 40
    im = im.crop((0, 0, W, min(H, y + 20)))
    im.save(OUT, quality=88, optimize=True)
    print(OUT, im.size)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else None)
