"""COHUE — A14, montage de la planche concept des armes et des effets (porte 2) et export des icônes.

    python assets/a14/board.py

Entrées : assets/a14/review/*.png et sprites.json (rendus et sprites de assets/a14/concept.py).
Sorties : assets/a14/09-armes-effets-concept.jpg (la planche) ;
          assets/a14/sprites/<Arme>.png (icône 32 px) et <Arme>@8x.png (256 px, pixels nets) pour A08.
"""

from __future__ import annotations

import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "assets", "style"))
import compose as C  # noqa: E402  (polices, papier, collage : outils de A01)

REVIEW = os.path.join(HERE, "review")
SPRITES = os.path.join(HERE, "sprites")
OUT = os.path.join(HERE, "09-armes-effets-concept.jpg")
W, H = 2400, 9000
CAPTION = (70, 58, 82)
TEXT = C.font("Inter-Medium.ttf", 27)
LABEL = C.font("Inter-Medium.ttf", 21)


def r(name):
    return os.path.join(REVIEW, name)


def pill(d, xy, text):
    x, y = xy
    tw = d.textlength(text, font=C.MONO)
    d.rounded_rectangle((x, y, x + tw + 24, y + 32), radius=10, fill=(28, 23, 38))
    d.text((x + 12, y + 5), text, font=C.MONO, fill=(255, 255, 255))


def section(d, y, title):
    d.text((60, y), title, font=C.H2, fill=C.INK)
    return y + 56


def centered(d, x, y, text, fnt, fill):
    d.text((x - d.textlength(text, font=fnt) / 2, y), text, font=fnt, fill=fill)


def icons():
    """Icônes PNG (fond transparent) à partir des sprites : 32 px natif et x8 pour A08."""
    os.makedirs(SPRITES, exist_ok=True)
    out = {}
    for name, s in json.load(open(r("sprites.json"), encoding="utf-8")).items():
        im = Image.new("RGBA", (s["w"], s["h"]), (0, 0, 0, 0))
        for x, y, hx, _neon in s["pixels"]:
            im.putpixel((x, y), tuple(int(hx[k:k + 2], 16) for k in (0, 2, 4)) + (255,))
        im.save(os.path.join(SPRITES, f"{name}.png"))
        big = im.resize((s["w"] * 8, s["h"] * 8), Image.NEAREST)
        big.save(os.path.join(SPRITES, f"{name}@8x.png"))
        out[name] = big
    return out


def main():
    ic = icons()
    im, d = C.canvas(W, H)
    C.header(d, "Armes et effets : planche concept",
             "A14, étape 2 (porte 2), DA du 5 nov. : armes en pixel art épaissi, effets lisses et lumineux. "
             "Rendus Blender ; décor et gobelins de A01 pour le contexte.", W)

    # 1. Les modèles
    y = section(d, 200, "1. Les armes : un sprite en pixels, épaissi en 3D, qui sert aussi d'icône")
    box = C.paste_fit(im, r("a14_lineup.png"), (60, y, W - 60, y + 740))
    labels = [("Broadsword", "Knight · bleu roi", 0.105), ("Longbow", "Archer · vert", 0.25),
              ("Fire Staff", "Mage · braise", 0.39), ("Bomb Bag", "Pool · raisin", 0.535),
              ("Bomb", "pièce en jeu", 0.665), ("Arrow", "pièce en jeu", 0.765), ("Avatar R15", "échelle", 0.895)]
    bw = box[2] - box[0]
    for name, sub, fx in labels:
        x = box[0] + int(bw * fx)
        centered(d, x, box[3] - 104, name, C.H3, C.INK)
        centered(d, x, box[3] - 66, sub, LABEL, CAPTION)
    y = box[3] + 30
    d.text((60, y), "Les mêmes sprites à plat (32 × 32 px, contour sombre de 1 px) : icônes de la barre "
           "d'armes et de l'inventaire", font=C.H3, fill=C.INK)
    y += 50
    x = 60
    for name in ("Broadsword", "Longbow", "FireStaff", "BombBag", "Bomb", "Arrow"):
        icon = ic[name]
        k = min(300 / icon.width, 300 / icon.height)
        icon = icon.resize((int(icon.width * k), int(icon.height * k)), Image.NEAREST)
        d.rounded_rectangle((x, y, x + 340, y + 340), radius=24, fill=(232, 220, 198))
        im.paste(icon, (x + (340 - icon.width) // 2, y + (340 - icon.height) // 2), icon)
        native = Image.open(os.path.join(SPRITES, f"{name}.png")).convert("RGBA")
        x2 = native.resize((native.width * 2, native.height * 2), Image.NEAREST)
        im.paste(native, (x + 20, y + 360), native)
        im.paste(x2, (x + 80, y + 360), x2)
        x += 380
    d.text((60, y + 432), "Sous chaque icône : taille réelle (32 px) et double (64 px), comme dans la barre d'armes.",
           font=LABEL, fill=CAPTION)
    y += 490

    # 2. Les effets
    y = section(d, y, "2. Les effets : de la lumière, jamais de cubes ni de pixels")
    rows = [
        ("Broadsword · coup de taille", "a14_swing",
         "Grand croissant de lumière : bord blanc, corps Sky, halo. La fin du geste est pleine, le début "
         "s'efface. Éclat blanc et étincelles sur chaque gobelin touché. En jeu : Beam à dégradé et ParticleEmitter."),
        ("Fire Staff · boule de feu", "a14_fireball",
         "Cœur blanc-or, halo braise, traînée qui s'éteint. À l'impact : flash blanc, onde de choc orange au sol, "
         "étincelles, fumée douce, petites flammes de brûlure pendant 2 s."),
        ("Bomb Bag · alerte puis explosion", "a14_bomb",
         "La bombe (pièce en pixels) vole en cloche. Au sol : anneau Gold en pointillé ; un disque doré à bord "
         "blanc grandit jusqu'à l'impact. Puis explosion orange : la couleur et la forme changent."),
    ]
    gap = 30
    cw = (W - 120 - gap) // 2
    ch = int(cw * 9 / 16)
    for title, base, text in rows:
        d.text((60, y), title, font=C.H3, fill=C.INK)
        y += 42
        C.paste_fit(im, r(base + "_hero.png"), (60, y, 60 + cw, y + ch))
        pill(d, (74, y + 14), "vue rapprochée")
        C.paste_fit(im, r(base + "_game.png"), (60 + cw + gap, y, W - 60, y + ch))
        pill(d, (74 + cw + gap, y + 14), "vue de jeu")
        y = C.wrap(d, (60, y + ch + 14), text, TEXT, C.INK, W - 120) + 40

    # 3. Le sens au sol
    y = section(d, y, "3. Le sens au sol : même règle partout, sur l'herbe comme sur le sable")
    box = C.paste_fit(im, r("a14_legend.png"), (60, y, W - 60, y + 760))
    bw = box[2] - box[0]
    for name, sub, fx in (("Alerte du joueur", "anneau Gold en pointillé, se remplit jusqu'à l'impact", 0.17),
                          ("Coup du joueur", "onde orange pleine, flash blanc, disparaît vite", 0.5),
                          ("Danger ennemi", "rouge Tomato mat ; ici il vise le joueur, tiré par le gobelin à droite", 0.83)):
        x = box[0] + int(bw * fx)
        centered(d, x, box[3] + 14, name, C.H3, C.INK)
        centered(d, x, box[3] + 52, sub, LABEL, CAPTION)
    y = box[3] + 110
    d.text((60, y), "La même bombe en quatre temps : l'alerte se remplit, puis le coup éclate", font=C.H3,
           fill=C.INK)
    y += 46
    fw = (W - 120 - 3 * 20) // 4
    fh = int(fw * 7 / 9)
    for k, cap in enumerate(("0,1 s : la bombe part", "0,4 s : le disque grandit", "0,7 s : il est plein",
                             "0,8 s : impact")):
        x0 = 60 + k * (fw + 20)
        C.paste_fit(im, r(f"a14_sequence_{k}.png"), (x0, y, x0 + fw, y + fh))
        centered(d, x0 + fw // 2, y + fh + 12, cap, LABEL, C.INK)
    y += fh + 90

    # 4. Test téléphone
    y = section(d, y, "4. Test de lisibilité : 70 gobelins et 4 effets en même temps")
    big_w = 1600
    box = C.paste_fit(im, r("a14_dense.png"), (60, y, 60 + big_w, y + int(big_w * 9 / 16)))  # noqa
    C.wrap(d, (box[2] + 50, y + 10), "Croissant blanc, explosion orange, alerte Gold en pointillé, tirs "
           "ennemis en grosses boules rouges mates. Armes tenues 1,4 fois plus grandes, face plate vers la "
           "caméra.", TEXT, C.INK, W - box[2] - 110)
    y = box[3] + 30
    d.text((60, y), "À la taille d'un écran de téléphone (640 px de large, sans agrandissement) :", font=C.H3,
           fill=C.INK)
    y += 46
    x = 60
    for name in ("a14_dense.png", "a14_swing_game.png", "a14_bomb_game.png"):
        small = Image.open(r(name)).convert("RGB").resize((640, 360), Image.LANCZOS)
        im.paste(small, (x, y))
        d.rectangle((x - 3, y - 3, x + 643, y + 363), outline=C.INK, width=3)
        x += 680
    y += 420

    # 5. Règles
    d.rectangle((60, y, W - 60, y + 3), fill=C.INK)
    y = section(d, y + 24, "5. À généraliser aux 16 armes, aux 16 fusions et aux attaques ennemies")
    rules = [
        ("Armes et pièces : sprite de 24 à 32 px, contour sombre de 1 px, reflets et gravures dans les pixels, "
         "épaissi de 2 à 6 px (garde et poignée plus épaisses), une maille par arme, pas de tenons.", "Steel"),
        ("Une couleur dominante par arme ; un petit accent Neon ; accents Gold au niveau 8 ; le sprite est "
         "aussi l'icône de l'arme.", "Royal"),
        ("Effets : lumière seulement (ParticleEmitter à textures douces, Beam, Trail, anneaux Neon et bloom, "
         "étincelles). « Des blocs pour ce qui existe, de la lumière pour ce qui se passe. »", "Sky"),
        ("Au sol : Gold en pointillé = alerte du joueur, orange plein = coup du joueur, rouge = ennemis.", "Gold"),
        ("Téléphone : pas de lumière ni de traînée en qualité Basse, 12 particules par rafale au plus, rien "
         "au-delà de 80 studs.", "Leaf"),
    ]
    for text, key in rules:
        d.rounded_rectangle((62, y + 6, 84, y + 28), radius=5, fill=C.rgb(key))
        y = C.wrap(d, (104, y), text, TEXT, C.INK, W - 170) + 10
    im = im.crop((0, 0, W, min(H, y + 40)))
    im.save(OUT, quality=88, optimize=True)
    print(OUT, im.size, os.path.getsize(OUT))


if __name__ == "__main__":
    main()
