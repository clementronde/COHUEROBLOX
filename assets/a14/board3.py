"""COHUE — A14, planche de l'étape 3 : les 16 armes et leurs 16 fusions, en pixel art épaissi.

    python assets/a14/board3.py

Entrées : assets/a14/out/icons/*.png (rendus trois-quarts de export.py), assets/a14/out/manifest.json,
sprites de pixelweapons.py. Sorties : assets/a14/10-armes-et-fusions.jpg et les icônes PNG pour A08
(docs/dossier/ui-assets/icons/weapons/<Id>.png en trois-quarts, <Id>_flat.png à plat, 512 px).
"""

from __future__ import annotations

import json
import os
import shutil
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "assets", "style"))
sys.path.insert(0, HERE)
import compose as C  # noqa: E402
import pixelweapons as P  # noqa: E402

OUT = os.path.join(HERE, "out")
UI = os.path.join(ROOT, "docs", "dossier", "ui-assets", "icons", "weapons")
LABEL = C.font("Inter-Medium.ttf", 21)
SMALL = C.font("Inter-Regular.ttf", 18)
CAPTION = (70, 58, 82)

RUNE = {"Broadsword": "Area", "Longbow": "Attack Speed", "FireStaff": "Damage", "QuakeHammer": "Armor",
        "ThrowingDaggers": "Projectile", "HolyAura": "Vitality", "SpinningAxes": "Duration",
        "BeastWhip": "Agility", "LightningChain": "Crit", "FrostNova": "Cooldown", "Boomerang": "Magnet",
        "BombBag": "Projectile", "SpearThrow": "Damage", "MeteorRain": "Luck", "OrbitingBlades": "Area",
        "CrossbowTurret": "Duration"}
LABELS = {"Broadsword": "Broadsword", "Longbow": "Longbow", "FireStaff": "Fire Staff",
          "QuakeHammer": "Quake Hammer", "ThrowingDaggers": "Throwing Daggers", "HolyAura": "Holy Aura",
          "SpinningAxes": "Spinning Axes", "BeastWhip": "Beast Whip", "LightningChain": "Lightning Chain",
          "FrostNova": "Frost Nova", "Boomerang": "Boomerang", "BombBag": "Bomb Bag", "SpearThrow": "Spear Throw",
          "MeteorRain": "Meteor Rain", "OrbitingBlades": "Orbiting Blades", "CrossbowTurret": "Crossbow Turret"}
FUSION_LABELS = {"RoyalGreatsword": "Royal Greatsword", "StormBow": "Storm Bow", "SunStaff": "Sun Staff",
                 "MountainMaul": "Mountain Maul", "DaggerFlurry": "Dagger Flurry", "GrandChime": "Grand Chime",
                 "AxeTornado": "Axe Tornado", "RingmasterLash": "Ringmaster Lash", "ThunderWeb": "Thunder Web",
                 "BlizzardGlobe": "Blizzard Globe", "ComebackRang": "Comeback Rang", "ClusterSack": "Cluster Sack",
                 "CometJavelin": "Comet Javelin", "StarShower": "Star Shower", "BuzzsawHalo": "Buzzsaw Halo",
                 "SiegeBallista": "Siege Ballista"}


def flat(name, size=512):
    sp = P.SPRITES[name]().export()
    im = Image.new("RGBA", (sp["w"], sp["h"]), (0, 0, 0, 0))
    for x, y, hx, _ in sp["pixels"]:
        im.putpixel((x, y), tuple(int(hx[k:k + 2], 16) for k in (0, 2, 4)) + (255,))
    k = (size - 32) // max(im.size)
    big = im.resize((im.width * k, im.height * k), Image.NEAREST)
    can = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    can.alpha_composite(big, ((size - big.width) // 2, (size - big.height) // 2))
    return can, im


def deliver_icons():
    os.makedirs(UI, exist_ok=True)
    os.makedirs(os.path.join(HERE, "sprites"), exist_ok=True)
    for name in [*P.WEAPON_SPRITES, *[f().name for f in P.FUSION_SPRITES.values()], *P.PIECE_SPRITES]:
        can, native = flat(name)
        native.save(os.path.join(HERE, "sprites", f"{name}.png"))
        if name in P.PIECE_SPRITES:
            continue
        can.save(os.path.join(UI, f"{name}_flat.png"))
        shutil.copyfile(os.path.join(OUT, "icons", f"{name}.png"), os.path.join(UI, f"{name}.png"))


def main():
    deliver_icons()
    tris = {e["name"]: e["tris"] for e in json.load(open(os.path.join(OUT, "manifest.json"), encoding="utf-8"))}
    W = 2400
    cols, cw, ch = 4, 570, 340
    im, d = C.canvas(W, 6000)
    C.header(d, "Les 16 armes et leurs 16 fusions",
             "A14, étape 3. Pixel art épaissi (DA validée à la porte 2). À gauche l'arme, à droite sa fusion "
             "(arme niveau 8 + Rune niveau 5). Une maille par modèle ; triangles entre parenthèses.", W)
    y0 = 200
    for i, (wid, ffn) in enumerate(P.FUSION_SPRITES.items()):
        fname = ffn().name
        r, c = divmod(i, cols)
        x = 60 + c * (cw + 20)
        y = y0 + r * (ch + 110)
        d.rounded_rectangle((x, y, x + cw, y + ch + 90), radius=22, fill=(236, 224, 202))
        for k, name in enumerate((wid, fname)):
            icon = Image.open(os.path.join(OUT, "icons", f"{name}.png")).convert("RGBA").resize((260, 260))
            im.paste(icon, (x + 10 + k * 290, y + 12), icon)
            _can, native = flat(name)
            n2 = native.resize((native.width * 2, native.height * 2), Image.NEAREST)
            im.paste(n2, (x + 18 + k * 290, y + 262), n2)
        d.text((x + 278, y + 120), "→", font=C.H2, fill=C.INK)
        d.text((x + 20, y + ch + 2), f"{LABELS[wid]} ({tris[wid]})", font=LABEL, fill=C.INK)
        d.text((x + 310, y + ch + 2), f"{FUSION_LABELS[fname]} ({tris[fname]})", font=LABEL, fill=C.INK)
        d.text((x + 310, y + ch + 34), f"+ {RUNE[wid]} Rune", font=SMALL, fill=CAPTION)
    y = y0 + 4 * (ch + 110) + 20
    d.text((60, y), "Pièces en jeu (la dague, la hache, le boomerang, la lance, le météore et la lame reprennent "
           "le modèle de leur arme)", font=C.H3, fill=C.INK)
    y += 50
    x = 60
    for name in P.PIECE_SPRITES:
        can, native = flat(name, 260)
        im.paste(can, (x, y), can)
        d.text((x + 20, y + 262), f"{name} ({tris[name]})", font=LABEL, fill=C.INK)
        x += 320
    y += 320
    rules = ("Budget : 1 500 triangles visés, 2 500 au plus (budget arme du vault) ; les pièces nombreuses "
             "(lames, dagues) auront une version allégée à l'étape 4 si le test sur téléphone le demande. "
             "Le halo de Buzzsaw Halo et les éclairs autour des armes en jeu sont des effets de lumière, pas des pixels.")
    y = C.wrap(d, (60, y), rules, C.font("Inter-Medium.ttf", 25), C.INK, W - 120) + 30
    im = im.crop((0, 0, W, y))
    out = os.path.join(HERE, "10-armes-et-fusions.jpg")
    im.save(out, quality=88, optimize=True)
    print(out, im.size)


if __name__ == "__main__":
    main()
