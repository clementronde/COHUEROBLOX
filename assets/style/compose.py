"""COHUE — montage des planches de référence (A01) à partir des rendus Blender et des captures Studio.

    python assets/style/compose.py

Entrées : assets/voxel/review/* (rendus de assets/voxel/boards.py), assets/style/captures/* (Studio).
Sorties : assets/style/01-palette-grain.png, 02-silhouettes-familles.png, 03-diorama-lumiere.png,
          04-equipement-paliers.png
"""

from __future__ import annotations

import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "assets", "voxel"))
import cohue_voxel as cv  # noqa: E402

REVIEW = os.path.join(ROOT, "assets", "voxel", "review")
CAPS = os.path.join(HERE, "captures")

PAPER = (246, 236, 217)
INK = cv.hex_rgb(cv.PALETTE["Ink"])
INK = tuple(round(c * 255) for c in INK)
MUTED = (110, 96, 120)

FONTS = os.path.expandvars(r"%LOCALAPPDATA%\Microsoft\Windows\Fonts")


def font(name, size):
    for path in (os.path.join(FONTS, name), os.path.join(r"C:\Windows\Fonts", name)):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.truetype(r"C:\Windows\Fonts\segoeuib.ttf", size)


TITLE = font("Gilroy-Black.ttf", 64)
H2 = font("Gilroy-ExtraBold.ttf", 34)
H3 = font("Gilroy-Bold.ttf", 26)
BODY = font("Inter-Medium.ttf", 22)
SMALL = font("Inter-Regular.ttf", 18)
MONO = font("Inter-SemiBold.ttf", 18)


def rgb(key):
    return tuple(round(c * 255) for c in cv.tone(key))


def canvas(w, h):
    im = Image.new("RGB", (w, h), PAPER)
    return im, ImageDraw.Draw(im)


def header(d, title, sub, w):
    d.text((60, 44), title, font=TITLE, fill=INK)
    d.text((62, 122), sub, font=BODY, fill=MUTED)
    d.rectangle((60, 168, w - 60, 172), fill=INK)


def paste_fit(im, src, box, align="center"):
    x0, y0, x1, y1 = box
    s = Image.open(src).convert("RGBA")
    k = min((x1 - x0) / s.width, (y1 - y0) / s.height)
    s = s.resize((max(1, int(s.width * k)), max(1, int(s.height * k))), Image.LANCZOS)
    x = x0 + ((x1 - x0) - s.width) // 2 if align == "center" else x0
    y = y0 + ((y1 - y0) - s.height) // 2
    im.paste(s, (x, y), s)
    return (x, y, x + s.width, y + s.height)


def wrap(d, xy, text, fnt, fill, width):
    words = text.split()
    line, y = "", xy[1]
    for w in words:
        t = (line + " " + w).strip()
        if d.textlength(t, font=fnt) > width:
            d.text((xy[0], y), line, font=fnt, fill=fill)
            y += fnt.size + 8
            line = w
        else:
            line = t
    if line:
        d.text((xy[0], y), line, font=fnt, fill=fill)
        y += fnt.size + 8
    return y


USAGE = {
    "Ink": "contours, yeux, coutures, bombe",
    "Plum": "ombres froides, tissu sombre",
    "Bark": "bois sombre, chaussures, bords",
    "Leather": "cuir, bois clair, cupule",
    "Cream": "yeux, dents, émail, papier",
    "Stone": "pierre, os, gris chaud",
    "Steel": "métal, armure Knight",
    "Gold": "accents ≤ 5 %, élites, pièces",
    "Ember": "rôle kamikaze, feu",
    "Tomato": "rôle mêlée, danger",
    "Bubblegum": "RÉSERVÉ : capture",
    "Grape": "rôle soutien, Mage",
    "Royal": "Knight",
    "Sky": "XP, magie froide (pas sur les ennemis)",
    "Leaf": "Archer, feuillage (décor en .d)",
    "Lime": "peau des gobelins",
}


def board_palette():
    W, H = 2400, 1640
    im, d = canvas(W, H)
    header(d, "Palette COHUE 16 et grain voxel",
           "1 voxel = 0,25 stud (4 par stud)  ·  16 couleurs, 3 tons chacune + ombre profonde  ·  "
           "aucune texture : couleurs par sommet", W)
    x0, y = 60, 200
    d.text((x0 + 360, y), "clair .l", font=SMALL, fill=MUTED)
    d.text((x0 + 470, y), "base", font=SMALL, fill=MUTED)
    d.text((x0 + 560, y), "ombre .d", font=SMALL, fill=MUTED)
    d.text((x0 + 660, y), ".dd", font=SMALL, fill=MUTED)
    y += 34
    for name, hx in cv.PALETTE.items():
        d.text((x0, y + 14), name, font=H3, fill=INK)
        d.text((x0 + 190, y + 18), "#" + hx, font=MONO, fill=MUTED)
        for i, suf in enumerate(("l", "", "d", "dd")):
            key = name + ("." + suf if suf else "")
            cx = x0 + 360 + i * 100
            d.rectangle((cx, y + 6, cx + 84, y + 58), fill=rgb(key))
        d.text((x0 + 770, y + 18), USAGE[name], font=SMALL, fill=INK)
        if name == "Bubblegum":
            d.rectangle((x0 - 14, y + 4, x0 - 8, y + 60), fill=rgb("Bubblegum"))
        y += 80
    # Colonne de droite : échelle
    rx = 1240
    d.text((rx, 200), "Échelle (vue de face, orthographique)", font=H2, fill=INK)
    paste_fit(im, os.path.join(REVIEW, "scale.png"), (rx, 250, W - 60, 760))
    notes = [
        "Règle noir/crème : 1 stud = 4 voxels.",
        "Avatar R15 par défaut : 5,46 studs (Knight au palier 3 ici).",
        "Gobelin d'essaim : 3,5 studs, tête = 42 % de la hauteur.",
        "Élite : même maille x 1,25, couronne or (EnemyRenderer).",
    ]
    yy = 790
    for n in notes:
        yy = wrap(d, (rx, yy), "•  " + n, BODY, INK, W - 60 - rx)
    yy += 24
    d.text((rx, yy), "Hiérarchie de saturation", font=H2, fill=INK)
    yy += 56
    tiers = [("À ramasser (XP, pièces)", ["Sky", "Gold"]), ("Joueur et capture", ["Royal", "Bubblegum"]),
             ("Ennemis", ["Lime", "Tomato", "Grape", "Ember"]), ("Décor (tons .d / .dd)", ["Leaf.d", "Bark", "Leather.d", "Stone.d"])]
    for label, keys in tiers:
        for i, k in enumerate(keys):
            d.rectangle((rx + i * 62, yy, rx + i * 62 + 50, yy + 50), fill=rgb(k))
        d.text((rx + 270, yy + 12), label, font=BODY, fill=INK)
        yy += 66
    yy += 10
    d.text((rx, yy), "Tons cuits par face", font=H2, fill=INK)
    yy += 52
    wrap(d, (rx, yy), "Dessus : +12 % de lumière chaude (#FFF4D8). Dessous : 40 % d'ombre violette (#2A1C3D). "
         "Dos : 8 % d'ombre. Même valeur sur toute la face, donc la fusion des faces reste possible.",
         BODY, INK, W - 60 - rx)
    im.save(os.path.join(HERE, "01-palette-grain.png"), optimize=True)


def board_silhouettes():
    W, H = 2400, 1700
    im, d = canvas(W, H)
    header(d, "Silhouettes par famille, couleur par rôle",
           "La famille se lit à la silhouette et à la peau ; le rôle à la couleur du dessus de la tête et des "
           "vêtements. Silhouettes à la taille réelle de 64 px.", W)
    roles = [("Mêlée / essaim", "Tomato"), ("Tireur", "Leaf.d"), ("Soutien", "Grape"), ("Kamikaze", "Ember")]
    x = 520
    for label, k in roles:
        d.rectangle((x, 196, x + 40, 236), fill=rgb(k))
        d.text((x + 52, 202), label, font=BODY, fill=INK)
        x += 330
    rows = [
        ("Gobelins", "Monde 1 · livrés", "Silhouette en T : grandes oreilles horizontales. Peau Lime. Tête = 42 %.",
         ["Enemy_GoblinGrunt", "Enemy_GoblinArcher", "Enemy_GoblinShaman", "Enemy_GoblinBomber"],
         ["Grunt", "Archer", "Shaman", "Bomber"]),
        ("Zombies", "Monde 2 · ébauches", "Bras tendus devant, dos voûté, tête en avant. Peau Sky.d (bleu-vert).",
         ["Blockout_ZombieShambler", "Blockout_ZombieRunner", "Blockout_ZombieBloater", "Blockout_Gravedigger"],
         ["Shambler", "Runner", "Bloater", "Gravedigger"]),
        ("Fantômes", "Monde 3 · ébauches", "Dôme + bas ondulé, flottent à 1 stud du sol. Corps Cream (jamais cyan : c'est la couleur de l'XP).",
         ["Blockout_Wisp", "Blockout_Poltergeist", "Blockout_Banshee", "Blockout_HauntedArmor"],
         ["Wisp", "Poltergeist", "Banshee", "Haunted Armor"]),
    ]
    y = 270
    for fam, status, rule, names, labels in rows:
        d.text((60, y + 20), fam, font=H2, fill=INK)
        d.text((60, y + 64), status, font=SMALL, fill=MUTED)
        wrap(d, (60, y + 100), rule, SMALL, INK, 400)
        x = 500
        for n, lab in zip(names, labels):
            paste_fit(im, os.path.join(REVIEW, "creatures", n + ".png"), (x, y, x + 330, y + 330))
            sil = Image.open(os.path.join(REVIEW, "creatures", n + "_sil.png")).convert("RGBA")
            d.rectangle((x + 340, y + 150, x + 340 + 64, y + 150 + 64), fill=(255, 255, 255))
            im.paste(sil, (x + 340, y + 150), sil)
            big = sil.resize((128, 128), Image.NEAREST)
            im.paste(big, (x + 340 - 32, y + 10), big)
            d.text((x + 10, y + 335), lab, font=H3, fill=INK)
            x += 470
        y += 460
    im.save(os.path.join(HERE, "02-silhouettes-familles.png"), optimize=True)


def board_diorama():
    W, H = 2400, 1500
    im, d = canvas(W, H)
    header(d, "Diorama voxel bien éclairé",
           "Cible d'ambiance (rendu Blender) et vérification en jeu (captures Studio, 100 gobelins, caméra "
           "3e personne à 26 studs).", W)
    paste_fit(im, os.path.join(REVIEW, "diorama.png"), (60, 200, 1560, 1050), align="left")
    d.text((60, 1070), "Tuile de forêt flottante : coupe de terrain visible (herbe, terre, roche), lumière basse et "
           "chaude, ombres violettes, décor en tons d'ombre.", font=BODY, fill=INK)
    rx = 1600
    d.text((rx, 200), "Le décor reste plus calme", font=H2, fill=INK)
    paste_fit(im, os.path.join(CAPS, "studio_horde_sol-vif.jpg"), (rx, 250, W - 60, 620))
    d.text((rx, 625), "Avant : sol au ton de base, la horde se fond dedans", font=SMALL, fill=MUTED)
    paste_fit(im, os.path.join(CAPS, "studio_horde_sol-calme.jpg"), (rx, 670, W - 60, 1040))
    d.text((rx, 1045), "Après : sol en ton d'ombre (.dd), la horde ressort", font=SMALL, fill=MUTED)
    y = 1130
    d.text((60, y), "Recette de lumière proposée (à régler par A02, monde par monde)", font=H2, fill=INK)
    y += 54
    rec = ("ClockTime 15,6 · Brightness 2,6 · Ambient #60526F · OutdoorAmbient #9680A0 · ColorShift_Top #FFD6A0 · "
           "Atmosphere Density 0,32, Haze 1,4, Color #FFE4C4, Decay #96A0E6 · ColorCorrection Saturation +0,12, "
           "Contrast +0,06 · Bloom Intensity 0,6, Threshold 0,9 (seul le Neon fleurit) · DepthOfField FarIntensity "
           "0,35, FocusDistance = distance caméra (≈ 30), InFocusRadius 24.")
    wrap(d, (60, y), rec, BODY, INK, W - 120)
    im.save(os.path.join(HERE, "03-diorama-lumiere.png"), optimize=True)


def board_equipment():
    W, H = 2400, 2100
    im, d = canvas(W, H)
    header(d, "Équipement des classes : 3 paliers cumulés",
           "Niveau 10 : pièce de tête · niveau 20 : épaules ou bras · niveau 30 : grande pièce de dos (vue de la "
           "caméra de jeu). L'avatar reste visible.", W)
    pieces = {
        "Knight": ["Bassinet ouvert + plumet minuscule", "Épaulières (même maille, demi-tour à gauche)", "Cape au canard couronné"],
        "Archer": ["Capuche à pointe, broche en gland", "Brassard brodé d'une cible", "Carquois dont une flèche est une carotte"],
        "Mage": ["Chapeau pointu à grelot", "Orbe de feu en cage (cœur Neon)", "Cape étoilée à haut col"],
    }
    colw = (W - 360) // 6
    for i, t in enumerate(("Niveau 10", "", "Niveau 20", "", "Niveau 30", "")):
        if t:
            d.text((340 + i * colw + 10, 196), t, font=H2, fill=INK)
    y = 250
    for cls in ("Knight", "Archer", "Mage"):
        d.text((60, y + 200), cls, font=TITLE, fill=INK)
        for t in range(3):
            for s, side in enumerate(("front", "back")):
                x = 340 + (t * 2 + s) * colw
                paste_fit(im, os.path.join(REVIEW, "equipment", f"{cls}_T{t + 1}_{side}.png"), (x, y, x + colw - 10, y + 520))
            x = 340 + t * 2 * colw
            wrap(d, (x + 10, y + 525), pieces[cls][t], SMALL, INK, 2 * colw - 30)
        y += 610
    im.save(os.path.join(HERE, "04-equipement-paliers.png"), optimize=True)


def board_lobby_bricks():
    """Planche 6 : le lobby compact en briques à tenons (rendus de assets/voxel/lobby.py)."""
    src = os.path.join(ROOT, "assets", "voxel", "review", "lobby_brick")
    W, H = 2400, 1680
    im, d = canvas(W, H)
    header(d, "Briques à tenons : le lobby en maquette",
           "Style choisi par Clément le 5 nov. 2026. Rendu Blender (EEVEE), mêmes modèles que la version voxel "
           "refusée ; seul le rendu change (assets/voxel/brick.py).", W)
    paste_fit(im, os.path.join(src, "lobby_arrival.png"), (60, 200, 1460, 990), align="left")
    d.text((60, 1000), "Ce que voit le joueur à l'arrivée : la tête de gobelin (le portail) au bout de l'avenue.",
           font=BODY, fill=INK)
    paste_fit(im, os.path.join(src, "lobby_overview.png"), (1500, 200, W - 60, 790))
    d.text((1500, 800), "Vue d'ensemble : île flottante, coupe en strates", font=SMALL, fill=MUTED)
    paste_fit(im, os.path.join(src, "lobby_portal.png"), (1500, 840, W - 60, 1320))
    d.text((1500, 1330), "Le portail de près : briques chanfreinées, joints décalés", font=SMALL, fill=MUTED)
    paste_fit(im, os.path.join(src, "lobby_west.png"), (60, 1050, 740, 1440), align="left")
    paste_fit(im, os.path.join(src, "lobby_east.png"), (770, 1050, 1450, 1440), align="left")
    d.text((60, 1450), "Tour du Mage, cour du Knight, enclos · Pas de tir, boutique de Gob, feu de camp",
           font=SMALL, fill=MUTED)
    y = 1510
    d.text((60, y), "Ce qu'on garde des exemples", font=H2, fill=INK)
    rules = ("Tout est monté en briques chanfreinées, joints décalés · sol = plaque à tenons, une couleur par zone · "
             "chemins et places en dalles lisses · falaises en strates de plaques · arbres en plaques empilées · "
             "personnages en briques fines avec de gros yeux ronds · ciel peint bleu franc et cumulus · "
             "accents Neon seulement sur ce qui compte (portail, capture, butin). À éviter : rochers ou arbres "
             "réalistes au milieu des briques, arbres par défaut de Roblox, sol gris de Studio.")
    wrap(d, (60, y + 50), rules, BODY, INK, W - 120)
    im.save(os.path.join(HERE, "06-lobby-briques.png"), optimize=True)


if __name__ == "__main__":
    if sys.argv[1:] == ["lobby"]:
        board_lobby_bricks()
    else:
        board_palette()
        board_silhouettes()
        board_diorama()
        board_equipment()
    print("ok")
