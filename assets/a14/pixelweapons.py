"""COHUE — A14, les armes en pixel art (DA du 5 nov. validée à la porte 2).

Chaque arme est un sprite en pixels (grille de 32 au plus, y vers le bas), contour Ink de 1 px, volume dans
les pixels, une couleur dominante, un accent Neon (clé finie par « ! »). Le même sprite donne :
- le modèle 3D (épaissi, maille gloutonne de A01) : concept.py / export.py dans Blender ;
- l'icône PNG : board.py, sans Blender.

Ce module n'importe pas bpy : on peut dessiner et prévisualiser les sprites avec Python seul
(python assets/a14/pixelweapons.py <dossier> écrit une planche des sprites).
"""

from __future__ import annotations

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.append(os.path.join(os.path.dirname(os.path.dirname(HERE)), "assets", "voxel"))

import cohue_voxel as cv  # noqa: E402

Vox = cv.Vox


class Sprite:
    """Grille de pixels {(x, y): clé de palette}, y vers le bas. Une clé finie par « ! » est du Neon."""

    def __init__(self, name: str, w: int, h: int, grip=(0.0, 0.0)):
        self.name, self.w, self.h = name, w, h
        self.px: dict[tuple[int, int], str] = {}
        self.depth: dict[str, int] = {}       # épaisseur (pixels) par clé de base ; défaut 2
        self.grip = grip                      # point de prise (pixels) : origine du modèle
        self.fixed: set = set()               # pixels peints à la main : l'ombrage auto n'y touche pas

    def set(self, x, y, key, fixed=True):
        if -2 <= x <= self.w + 1 and -2 <= y <= self.h + 1:   # une marge d un pixel pour le contour
            self.px[(x, y)] = key
            if fixed:
                self.fixed.add((x, y))
            else:
                self.fixed.discard((x, y))

    def rect(self, x0, y0, x1, y1, key, fixed=False):
        for x in range(min(x0, x1), max(x0, x1) + 1):
            for y in range(min(y0, y1), max(y0, y1) + 1):
                self.set(x, y, key, fixed)

    def ell(self, cx, cy, rx, ry, key, fixed=False):
        for x in range(math.floor(cx - rx), math.ceil(cx + rx) + 1):
            for y in range(math.floor(cy - ry), math.ceil(cy + ry) + 1):
                if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0:
                    self.set(x, y, key, fixed)

    def line(self, p0, p1, key, fixed=False):
        n = max(abs(p1[0] - p0[0]), abs(p1[1] - p0[1]), 1)
        for i in range(n + 1):
            t = i / n
            self.set(round(p0[0] + (p1[0] - p0[0]) * t), round(p0[1] + (p1[1] - p0[1]) * t), key, fixed)

    def recolor(self, mapping):
        """Change des couleurs de base (le suffixe de ton et le Neon sont gardés)."""
        for p, key in list(self.px.items()):
            neon = key.endswith("!")
            base, _, tone = key.rstrip("!").partition(".")
            if base in mapping:
                self.px[p] = mapping[base] + ("." + tone if tone else "") + ("!" if neon else "")
        return self

    def clear(self, x, y):
        self.px.pop((x, y), None)
        self.fixed.discard((x, y))

    def thick(self, p0, p1, r, key, fixed=False):
        """Trait épais (disques de rayon r le long du segment)."""
        n = max(int(math.hypot(p1[0] - p0[0], p1[1] - p0[1]) * 2), 1)
        for i in range(n + 1):
            t = i / n
            self.ell(p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t, r, r, key, fixed)

    def ring(self, cx, cy, r0, r1, key, fixed=False, keep=None):
        """Anneau entre r0 et r1 ; keep(angle en degrés) filtre les secteurs."""
        for x in range(math.floor(cx - r1) - 1, math.ceil(cx + r1) + 2):
            for y in range(math.floor(cy - r1) - 1, math.ceil(cy + r1) + 2):
                r = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
                a = math.degrees(math.atan2(y + 0.5 - cy, x + 0.5 - cx)) % 360
                if r0 <= r <= r1 and (keep is None or keep(a)):
                    self.set(x, y, key, fixed)

    def shade(self):
        """Volume en pixels : reflet clair sur les bords haut et gauche, ombre sur les bords bas et droit."""
        out = dict(self.px)
        for (x, y), key in self.px.items():
            if (x, y) in self.fixed or "." in key or key.endswith("!"):
                continue
            up = (x, y - 1) not in self.px
            left = (x - 1, y) not in self.px
            down = (x, y + 1) not in self.px
            right = (x + 1, y) not in self.px
            if up or left:
                out[(x, y)] = key + ".l"
            elif down or right:
                out[(x, y)] = key + ".d"
        self.px = out

    def outline(self, key="Ink"):
        """Contour de 1 px (voisins en croix)."""
        add = {}
        for (x, y) in self.px:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                p = (x + dx, y + dy)
                if p not in self.px:
                    add[p] = key
        self.px.update(add)

    def depth_of(self, key: str) -> int:
        if key == "Ink":
            return 0
        return self.depth.get(key.rstrip("!").split(".")[0], 2)

    def voxels(self):
        """(corps, Neon) en Vox : x vers la droite, z vers le haut, épaisseur centrée sur y = 0."""
        body, neon = Vox(self.name), Vox(self.name + "_Neon")
        for (x, y), key in self.px.items():
            d = self.depth_of(key)
            if key == "Ink":                  # le contour prend l'épaisseur du voisin le plus épais
                d = max([self.depth_of(self.px.get((x + a, y + b), "Ink"))
                         for a, b in ((1, 0), (-1, 0), (0, 1), (0, -1))] + [1])
            target = neon if key.endswith("!") else body
            col = key.rstrip("!")
            z = self.h - 1 - y
            for k in range(d):
                target.set(x, k - d // 2, z, col)
        return body, neon

    def origin(self):
        """Origine en unités de voxel : le point de prise."""
        gx, gy = self.grip
        return (gx + 0.5, 0.0, self.h - 1 - gy + 0.5)

    def export(self):
        """Pixels pour l'icône PNG ; le contour peut déborder de la grille d'un pixel : on recadre."""
        x0 = min(x for x, _ in self.px)
        y0 = min(y for _, y in self.px)
        x1 = max(x for x, _ in self.px)
        y1 = max(y for _, y in self.px)
        return {"w": x1 - x0 + 1, "h": y1 - y0 + 1,
                "pixels": [[x - x0, y - y0, cv.rgb_hex(cv.tone(k.rstrip("!"))), k.endswith("!")]
                           for (x, y), k in self.px.items()]}


def broadsword(raw=False) -> Sprite:
    """Knight. Couleur dominante : bleu roi. Large lame d'acier à gorge, garde aux bouts relevés, gemme Neon
    Sky, poignée tressée, pommeau en canard de bain (gag)."""
    s = Sprite("Broadsword", 32, 32, grip=(15.5, 24.5))
    s.depth.update({"Steel": 2, "Royal": 3, "Leather": 3, "Gold": 4, "Ember": 4, "Sky": 3, "Cream": 2})
    s.rect(15, 1, 16, 1, "Steel")                                  # pointe
    s.rect(14, 2, 17, 2, "Steel")
    s.rect(13, 3, 18, 3, "Steel")
    s.rect(12, 4, 19, 20, "Steel")                                 # lame de 8 px
    s.rect(15, 5, 16, 19, "Steel.d", fixed=True)                   # gorge
    s.rect(13, 4, 13, 18, "Steel.l", fixed=True)                   # fil clair
    for y in (6, 7, 12):                                           # reflets
        s.set(14, y, "Cream")
    s.set(17, 9, "Steel.l")
    s.set(17, 10, "Steel.l")
    s.rect(6, 21, 25, 23, "Royal")                                 # garde
    s.rect(5, 18, 7, 20, "Royal")                                  # bouts relevés
    s.rect(24, 18, 26, 20, "Royal")
    s.rect(5, 17, 6, 17, "Royal")
    s.rect(25, 17, 26, 17, "Royal")
    s.rect(9, 22, 22, 22, "Royal.d", fixed=True)                   # gravure
    for x in (8, 23):
        s.set(x, 22, "Gold")                                       # rivets
    s.rect(14, 20, 17, 23, "Royal")
    s.rect(15, 21, 16, 22, "Sky!")                                 # gemme Neon
    s.set(15, 21, "Cream!")
    s.rect(14, 24, 17, 27, "Leather")                              # poignée tressée
    for y in (24, 26):
        s.set(14, y, "Leather.d")
        s.set(16, y, "Leather.d")
    for y in (25, 27):
        s.set(15, y, "Leather.d")
        s.set(17, y, "Leather.d")
    s.ell(13.5, 29.0, 2.0, 1.9, "Gold")                            # canard : tête
    s.ell(17.0, 30.0, 3.2, 1.6, "Gold")                            # corps
    s.rect(20, 28, 20, 29, "Gold")                                 # queue
    s.rect(10, 29, 11, 29, "Ember")                                # bec
    s.set(11, 30, "Ember")
    s.set(13, 28, "Ink")                                           # œil
    s.rect(15, 30, 17, 30, "Gold.d", fixed=True)                   # aile
    if raw:                                                        # base d'une fusion
        return s
    s.shade()
    s.outline()
    return s


def longbow(raw=False) -> Sprite:
    """Archer. Couleur dominante : vert feuille. Arc en D peint en vert, poignée en cuir à bagues d'or, corde
    Neon, flèche encochée, une feuille qui pousse au bout du haut (gag)."""
    s = Sprite("Longbow", 32, 32, grip=(8.0, 15.5))
    s.depth.update({"Leaf": 2, "Leather": 3, "Gold": 3, "Cream": 1, "Steel": 2, "Bark": 2})
    for y in range(2, 30):
        u = (y - 15.5) / 13.5
        xc = round(7 + 7 * u * u)
        w = 3 if abs(u) < 0.6 else 2
        s.rect(xc, y, xc + w - 1, y, "Leaf")
    s.rect(14, 1, 16, 1, "Leaf")                                   # bouts recourbés
    s.rect(14, 30, 16, 30, "Leaf")
    s.set(17, 1, "Leaf.d")
    s.set(17, 30, "Leaf.d")
    for y in range(4, 28, 4):                                      # veinures peintes
        u = (y - 15.5) / 13.5
        s.set(round(7 + 7 * u * u) + 1, y, "Leaf.d")
    s.rect(6, 12, 10, 19, "Leather")                               # poignée
    s.rect(6, 12, 10, 12, "Gold")
    s.rect(6, 19, 10, 19, "Gold")
    for y in (14, 16):
        s.rect(6, y, 10, y, "Leather.d", fixed=True)
    s.rect(18, 2, 18, 29, "Cream!")                                # corde Neon
    s.line((4, 15), (18, 15), "Bark")                              # flèche encochée
    s.rect(0, 15, 3, 15, "Steel")                                  # pointe
    s.rect(1, 14, 2, 16, "Steel")
    s.set(0, 15, "Steel.l")
    s.line((15, 14), (19, 12), "Gold")                             # empennage
    s.line((15, 16), (19, 18), "Gold")
    s.ell(11.0, 1.6, 2.6, 1.5, "Leaf")                             # la feuille qui pousse
    s.line((9, 2), (13, 1), "Leaf.d", fixed=True)                  # nervure
    s.set(14, 2, "Bark")
    if raw:                                                        # base d'une fusion
        return s
    s.shade()
    s.outline()
    return s


def firestaff(raw=False) -> Sprite:
    """Mage. Couleur dominante : braise. Bâton noueux, griffe d'or qui tient une grosse flamme-cristal Neon
    (forme de goutte), une guimauve grillée piquée sur une brindille (gag)."""
    s = Sprite("FireStaff", 32, 32, grip=(15.5, 21.5))
    s.depth.update({"Bark": 2, "Gold": 3, "Ember": 4, "Cream": 4, "Leather": 4, "Stone": 2})
    for y in range(13, 32):
        dx = 1 if 20 <= y <= 25 else 0
        s.rect(15 + dx, y, 16 + dx, y, "Bark")
    for (x, y) in ((14, 17), (18, 23), (14, 28)):                  # nœuds
        s.set(x, y, "Bark")
    s.rect(15, 30, 16, 31, "Stone")                                # embout
    s.rect(11, 12, 20, 13, "Gold")                                 # coupe
    s.rect(10, 7, 11, 11, "Gold")                                  # griffes
    s.rect(20, 7, 21, 11, "Gold")
    s.set(11, 6, "Gold")
    s.set(20, 6, "Gold")
    for y in range(0, 13):                                         # flamme-cristal en goutte
        for x in range(10, 22):
            dy = y + 0.5 - 7.5
            w = 4.2 if dy > 0 else 4.2 * (1 + dy / 8.0)
            if abs(x + 0.5 - 16) <= w - abs(dy) * 0.15:
                s.set(x, y, "Ember!")
    for y in range(4, 11):                                         # cœur doré puis blanc
        for x in range(14, 18):
            if abs(x + 0.5 - 16) <= 1.6 - (0.25 if y < 6 else 0):
                s.set(x, y, "Gold!")
    s.rect(15, 7, 16, 9, "Cream!")
    s.line((18, 19), (23, 15), "Bark")                             # brindille
    s.rect(23, 10, 27, 14, "Cream")                                # grosse guimauve
    s.rect(23, 10, 27, 10, "Leather")                              # dessus grillé
    s.rect(27, 11, 27, 14, "Leather.l", fixed=True)
    s.set(27, 10, "Bark.d")
    s.set(23, 10, "Leather.l")
    if raw:                                                        # base d'une fusion
        return s
    s.shade()
    s.outline()
    return s


def bombbag(raw=False) -> Sprite:
    """Bomb Bag (porteur et icône). Couleur dominante : raisin. Un sac de toile ventru, épaules, col serré
    par une cordelette d'or, ouverture en pointes de tissu d'où dépassent deux bombes, une pièce cousue,
    un air grognon (gag)."""
    s = Sprite("BombBag", 32, 32, grip=(16.0, 12.0))
    s.depth.update({"Grape": 5, "Gold": 5, "Ink": 4, "Cream": 5, "Leather": 2, "Plum": 5, "Steel": 4})
    s.ell(12.8, 4.6, 3.4, 3.4, "Ink")                              # bombes, derrière l'ouverture
    s.ell(19.6, 4.0, 2.9, 2.9, "Ink")
    for (x, y) in ((11, 3), (12, 2), (11, 4), (18, 2), (19, 2)):    # reflets
        s.set(x, y, "Cream")
    s.rect(12, 0, 13, 0, "Steel")
    s.set(20, 0, "Steel")
    s.ell(16.0, 23.0, 12.2, 8.6, "Grape")                          # panse ventrue
    s.rect(6, 28, 25, 30, "Grape")
    for k, (x0, x1) in enumerate(((11, 20), (10, 21), (9, 22), (8, 23))):   # épaules
        s.rect(x0, 11 + k, x1, 11 + k, "Grape")
    s.rect(12, 9, 19, 10, "Grape.d", fixed=True)                   # col serré
    s.rect(10, 7, 21, 8, "Grape")                                  # ouverture évasée
    for x in (9, 10, 13, 14, 17, 18, 21, 22):                      # pointes de tissu
        s.set(x, 6, "Grape")
    s.rect(11, 10, 20, 10, "Gold")                                 # cordelette et nœud
    s.rect(21, 10, 22, 11, "Gold")
    s.set(23, 12, "Gold")
    s.set(22, 13, "Gold")
    s.rect(8, 25, 11, 28, "Plum", fixed=True)                      # pièce cousue
    for (x, y) in ((8, 25), (10, 25), (11, 26), (11, 28), (9, 28), (8, 27)):
        s.set(x, y, "Cream")
    s.rect(10, 18, 12, 20, "Cream")                                # visage grognon
    s.rect(19, 18, 21, 20, "Cream")
    s.rect(11, 19, 12, 20, "Ink")
    s.rect(19, 19, 20, 20, "Ink")
    s.line((9, 16), (12, 17), "Plum")
    s.line((22, 16), (19, 17), "Plum")
    s.rect(14, 24, 18, 24, "Ink")
    s.set(13, 25, "Ink")
    s.set(19, 25, "Ink")
    for (x, y) in ((24, 17), (25, 20), (25, 23)):                  # coutures sur le flanc
        s.set(x, y, "Grape.d")
    if raw:                                                        # base d'une fusion
        return s
    s.shade()
    s.outline()
    s.set(13, -2, "Gold!")                                         # mèches qui crépitent
    s.set(14, -2, "Gold!")
    s.set(20, -2, "Gold!")
    s.set(13, -1, "Leather")
    s.set(20, -1, "Leather")
    return s


def bomb(raw=False) -> Sprite:
    """Pièce : la bombe du joueur, ronde, gros reflet blanc, bande raisin fine, longue mèche, étincelle Neon."""
    s = Sprite("Bomb", 18, 20, grip=(8.5, 12.5))
    s.depth.update({"Ink": 6, "Grape": 6, "Steel": 3, "Leather": 2, "Cream": 6, "Gold": 2})
    for k, w in enumerate((4, 8, 10, 12, 12, 14, 14, 14, 14, 12, 12, 10, 8, 4)):   # rond
        s.rect(9 - w // 2, 6 + k, 8 + w // 2, 6 + k, "Ink")
    s.rect(2, 13, 15, 13, "Grape")                                 # bande raisin
    s.rect(4, 8, 6, 8, "Cream")                                    # gros reflet
    s.rect(3, 9, 4, 10, "Cream")
    s.set(5, 9, "Steel.l")
    s.rect(7, 4, 10, 5, "Steel")                                   # capuchon
    s.set(9, 3, "Leather")                                         # mèche
    s.set(10, 2, "Leather")
    s.set(11, 2, "Leather")
    if raw:                                                        # base d'une fusion
        return s
    s.shade()
    s.outline()
    s.rect(12, 0, 14, 0, "Gold!")                                  # étincelle en croix
    s.rect(13, -1, 13, 1, "Gold!")
    s.set(13, 0, "Cream!")
    return s


def arrow(raw=False) -> Sprite:
    """Pièce : la flèche, grosse pointe d'acier en triangle, hampe claire, empennage or."""
    s = Sprite("Arrow", 32, 11, grip=(16.0, 5.0))
    s.depth.update({"Steel": 3, "Leather": 2, "Gold": 2})
    s.rect(6, 4, 27, 5, "Leather")                                 # hampe
    for x in range(0, 7):                                          # pointe en triangle
        h = round(x * 0.55)
        s.rect(x, 5 - h, x, 4 + h, "Steel")
    s.rect(1, 4, 5, 4, "Steel.l", fixed=True)                      # fil clair
    for k in range(5):                                             # empennage
        s.set(22 + k, 3 - k // 2, "Gold")
        s.set(22 + k, 6 + k // 2, "Gold")
        s.set(23 + k, 3 - k // 2, "Gold")
        s.set(23 + k, 6 + k // 2, "Gold")
    s.rect(28, 4, 29, 5, "Leather.d")                              # encoche
    if raw:                                                        # base d'une fusion
        return s
    s.shade()
    s.outline()
    return s


def quakehammer(raw=False) -> Sprite:
    """Guardian. Couleur dominante : pierre. Grosse tête de pierre aux faces d'acier, fissures de lave Neon,
    un pansement en croix collé dessus (gag), manche gainé de cuir."""
    s = Sprite("QuakeHammer", 32, 32, grip=(15.5, 24.0))
    s.depth.update({"Stone": 6, "Steel": 6, "Cream": 6, "Ember": 6, "Bark": 3, "Leather": 4, "Gold": 4})
    s.rect(15, 13, 16, 31, "Bark")                                 # manche
    s.rect(14, 21, 17, 27, "Leather")                              # gaine
    for y in (22, 24, 26):
        s.rect(14, y, 17, y, "Leather.d", fixed=True)
    s.rect(14, 30, 17, 31, "Steel")                                # embout
    s.rect(8, 2, 23, 12, "Stone")                                  # tête
    s.rect(4, 3, 7, 11, "Steel")                                   # faces de frappe
    s.rect(24, 3, 27, 11, "Steel")
    for (x, y) in ((8, 2), (23, 2), (8, 12), (23, 12)):
        s.clear(x, y)
    s.rect(13, 12, 18, 13, "Gold")                                 # bague
    s.line((10, 4), (12, 7), "Ember!")                             # fissures de lave
    s.line((12, 7), (11, 10), "Ember!")
    s.line((21, 10), (22, 7), "Ember!")
    s.set(23, 6, "Ember!")
    s.rect(14, 6, 19, 7, "Cream", fixed=True)                      # pansement en croix
    s.rect(16, 4, 17, 9, "Cream", fixed=True)
    for (x, y) in ((15, 6), (18, 7), (16, 5), (17, 8)):
        s.set(x, y, "Leather.l")
    if raw:                                                        # base d'une fusion
        return s
    s.shade()
    s.outline()
    return s


def throwingdagger(raw=False) -> Sprite:
    """Rogue. Couleur dominante : prune. Deux dagues en feuille (on lit le pluriel), garde et poignée prune,
    gemme Neon raisin, un petit nœud de ruban au pommeau (gag). La dague de devant sert de pièce en vol."""
    s = Sprite("ThrowingDaggers", 32, 32, grip=(15.5, 22.5))
    s.depth.update({"Steel": 2, "Plum": 3, "Grape": 3, "Cream": 2})
    s.thick((20, 19), (25, 4), 1.4, "Steel.d")                     # seconde dague, derrière
    s.thick((19, 21), (21, 19), 1.2, "Plum.d")
    for y, w in zip(range(2, 18), (2, 2, 4, 4, 4, 6, 6, 6, 6, 6, 6, 4, 4, 4, 4, 4)):   # lame en feuille
        s.rect(16 - w // 2, y, 15 + w // 2, y, "Steel")
    s.rect(15, 5, 15, 15, "Steel.l", fixed=True)
    s.set(14, 8, "Cream")
    s.rect(10, 18, 21, 19, "Plum")                                 # garde
    s.set(9, 17, "Plum")
    s.set(22, 17, "Plum")
    s.rect(14, 20, 17, 26, "Plum")                                 # poignée
    for y in (21, 23, 25):
        s.rect(14, y, 17, y, "Ink", fixed=True)
    s.rect(14, 27, 17, 29, "Grape!")                               # gemme au pommeau
    s.set(15, 27, "Cream!")
    s.rect(18, 27, 19, 28, "Grape")                                # ruban noué d'un côté
    s.line((19, 29), (22, 31), "Grape")
    s.line((20, 28), (23, 28), "Grape")
    if raw:                                                        # base d'une fusion
        return s
    s.shade()
    s.outline()
    return s


def holybell(raw=False) -> Sprite:
    """Cleric (Holy Aura). Couleur dominante : crème et or. Clochette de cantine en porcelaine, bord doré,
    battant Neon Sky, deux éclats dorés qui « sonnent » (gag)."""
    s = Sprite("HolyAura", 32, 32, grip=(15.5, 5.5))
    s.depth.update({"Cream": 6, "Gold": 6, "Leather": 3, "Sky": 4, "Bark": 3})
    s.rect(14, 1, 17, 8, "Leather")                                # manche
    s.rect(14, 1, 17, 1, "Bark")
    s.rect(13, 9, 18, 10, "Gold")                                  # bague
    for y in range(11, 26):                                        # cloche évasée
        w = 8 + round((y - 11) * 0.95)
        s.rect(16 - w // 2, y, 15 + w // 2, y, "Cream")
    s.rect(7, 16, 24, 16, "Gold", fixed=True)                      # filet doré
    s.rect(15, 19, 16, 23, "Gold", fixed=True)                     # croix gravée
    s.rect(13, 20, 18, 21, "Gold", fixed=True)
    s.rect(5, 26, 26, 27, "Gold")                                  # bord doré
    s.ell(15.5, 29.5, 2.2, 1.8, "Sky!")                            # battant Neon
    s.set(15, 29, "Cream!")
    for (x, y) in ((24, 7), (26, 5), (6, 7), (4, 5)):              # « ding »
        s.set(x, y, "Gold!")
    if raw:                                                        # base d'une fusion
        return s
    s.shade()
    s.outline()
    return s


def spinningaxe(raw=False) -> Sprite:
    """Barbarian. Couleurs : acier et cuir. Hache de jet au fer en croissant, un smiley gravé (gag), pointe
    arrière, bagues d'or. Sert aussi de pièce en orbite."""
    s = Sprite("SpinningAxes", 32, 32, grip=(16.5, 24.0))
    s.depth.update({"Steel": 3, "Leather": 3, "Bark": 3, "Gold": 4})
    s.rect(16, 4, 17, 31, "Leather")                               # manche
    for y in range(22, 30, 2):
        s.rect(16, y, 17, y, "Bark", fixed=True)
    for y in range(2, 19):                                         # fer large et barbu
        u = (y - 2) / 16.0
        edge = 3 + round(3 * (1 - math.sin(math.pi * u)))          # tranchant presque droit
        neck = 12 if 6 <= y <= 13 else 9 + round(3 * abs(u - 0.5) * 2) if False else 12
        s.rect(edge, y, 15, y, "Steel")
        s.set(edge, y, "Steel.l")
    for y in (2, 3, 17, 18):                                       # le fer se resserre vers le manche
        s.rect(12, y, 13, y, "Steel")
    s.rect(18, 8, 19, 12, "Steel")                                 # talon court
    s.rect(15, 1, 18, 2, "Gold")                                   # bagues
    s.rect(15, 18, 18, 19, "Gold")
    s.rect(8, 7, 8, 8, "Ink")                                      # smiley gravé au centre du fer
    s.rect(11, 7, 11, 8, "Ink")
    for (x, y) in ((7, 11), (8, 12), (9, 13), (10, 13), (11, 12), (12, 11)):
        s.set(x, y, "Ink")
    if raw:                                                        # base d'une fusion
        return s
    s.shade()
    s.outline()
    return s


def beastwhip(raw=False) -> Sprite:
    """Tamer. Couleur dominante : braise et crème (cirque). Manche rayé, lanière de cuir en S qui claque,
    claquoir jaune au bout et une empreinte de patte sur le manche (gag du dompteur)."""
    s = Sprite("BeastWhip", 32, 32, grip=(7.0, 24.0))
    s.depth.update({"Leather": 2, "Ember": 3, "Cream": 3, "Gold": 3, "Bark": 3})
    s.rect(5, 17, 8, 30, "Ember")                                  # manche rayé (14 px)
    for y in range(18, 30, 3):
        s.rect(5, y, 8, y, "Cream", fixed=True)
    s.rect(4, 30, 9, 31, "Gold")                                   # pommeau
    s.rect(4, 15, 9, 16, "Gold")
    pts = [(7, 14), (9, 9), (14, 6), (19, 8), (21, 13), (24, 17), (28, 16), (30, 12)]
    for a, b in zip(pts, pts[1:]):                                 # lanière en S, 3 px
        s.thick(a, b, 1.3, "Leather")
    for (x, y) in ((11, 7), (17, 7), (22, 15)):                    # tresse
        s.set(x, y, "Leather.d")
    s.ell(30.0, 9.5, 1.8, 2.2, "Gold!")                            # claquoir
    s.set(30, 8, "Cream!")
    s.set(6, 21, "Bark")                                           # empreinte de patte
    s.set(7, 21, "Bark")
    s.set(5, 20, "Bark")
    s.set(8, 20, "Bark")
    if raw:                                                        # base d'une fusion
        return s
    s.shade()
    s.outline()
    return s


def lightningrod(raw=False) -> Sprite:
    """Lightning Chain (pool). Couleur dominante : ciel électrique. Paratonnerre de poche : tige d'acier,
    bobine de cuivre, boule d'acier d'où jaillissent deux éclairs Neon."""
    s = Sprite("LightningChain", 32, 32, grip=(15.5, 22.0))
    s.depth.update({"Steel": 3, "Ember": 4, "Sky": 2, "Gold": 4, "Cream": 2})
    s.rect(15, 10, 16, 29, "Steel")                                # tige
    for y in range(13, 26, 2):                                     # bobine de cuivre
        s.rect(14, y, 17, y, "Ember.d", fixed=True)
    s.rect(13, 28, 18, 31, "Gold")                                 # socle
    s.ell(15.5, 6.5, 4.0, 4.0, "Steel")                            # boule
    s.set(14, 4, "Cream")
    s.set(13, 5, "Steel.l")
    for pts in (((19, 5), (22, 4), (21, 2), (25, 0)), ((12, 5), (9, 3), (10, 1), (6, 0)),
                ((18, 9), (22, 11), (21, 13), (26, 15))):
        for a, b in zip(pts, pts[1:]):                             # éclairs Neon
            s.line(a, b, "Sky!")
    s.set(25, 0, "Cream!")
    s.set(6, 0, "Cream!")
    s.set(26, 15, "Cream!")
    if raw:                                                        # base d'une fusion
        return s
    s.shade()
    s.outline()
    return s


def snowglobe(raw=False) -> Sprite:
    """Frost Nova (pool). Couleur dominante : glace. Boule à neige : verre bleu glace, flocon Neon au centre,
    neige, socle prune à filet doré."""
    s = Sprite("FrostNova", 32, 32, grip=(15.5, 26.0))
    s.depth.update({"Sky": 6, "Plum": 6, "Gold": 6, "Cream": 6})
    s.ell(15.5, 13.0, 11.0, 11.0, "Sky")                           # globe
    s.rect(8, 23, 23, 26, "Plum")                                  # socle
    s.rect(6, 27, 25, 30, "Plum")
    s.rect(6, 27, 25, 27, "Gold", fixed=True)
    s.rect(14, 28, 17, 29, "Gold", fixed=True)
    for k in range(-4, 5):                                         # flocon Neon
        s.set(15 + k if k <= 0 else 16 + k - 1, 13, "Cream!")
        s.set(15, 13 + k, "Cream!")
    for k in (-3, -2, 2, 3):
        s.set(15 + k, 13 + k, "Cream!")
        s.set(15 + k, 13 - k, "Cream!")
    for (x, y) in ((8, 16), (22, 9), (11, 7), (20, 18), (24, 14), (9, 11), (18, 6)):   # neige
        s.set(x, y, "Cream")
    for (x, y) in ((8, 6), (7, 7), (7, 8), (9, 5), (10, 4)):       # reflet du verre
        s.set(x, y, "Cream")
    if raw:                                                        # base d'une fusion
        return s
    s.shade()
    s.outline()
    return s


def boomerang(raw=False) -> Sprite:
    """Boomerang (pool). Couleur dominante : or. Boomerang en V peint, bouts braise, bande crème au coude.
    Sert aussi de pièce en vol."""
    s = Sprite("Boomerang", 32, 32, grip=(15.5, 9.0))
    s.depth.update({"Gold": 2, "Ember": 2, "Cream": 2})
    for (p0, p1) in (((15, 7), (9, 15)), ((9, 15), (4, 26)), ((15, 7), (22, 14)), ((22, 14), (28, 25))):
        s.thick(p0, p1, 2.5, "Gold")                               # chevron aux bras courbes
    s.thick((4, 26), (5, 24), 2.3, "Ember")                        # bouts peints
    s.thick((28, 25), (27, 23), 2.3, "Ember")
    s.thick((13, 8), (17, 8), 1.4, "Cream")                        # bande au coude
    for (x, y) in ((8, 17), (6, 21), (23, 16), (25, 20)):          # motifs
        s.set(x, y, "Ember")
    if raw:                                                        # base d'une fusion
        return s
    s.shade()
    s.outline()
    return s


def spear(raw=False) -> Sprite:
    """Spear Throw (pool). Couleurs : bois clair et acier. Grande pointe en feuille, collier d'or, plumes,
    poignée gainée. Sert aussi de pièce en vol."""
    s = Sprite("SpearThrow", 32, 32, grip=(15.5, 22.0))
    s.depth.update({"Steel": 2, "Leather": 2, "Gold": 3, "Sky": 2, "Bark": 3})
    for y, w in zip(range(0, 11), (2, 2, 4, 4, 6, 6, 6, 6, 4, 4, 2)):   # pointe en feuille
        s.rect(16 - w // 2, y, 15 + w // 2, y, "Steel")
    s.rect(15, 2, 15, 9, "Steel.l", fixed=True)
    s.rect(14, 11, 17, 12, "Gold")                                 # collier
    s.rect(15, 13, 16, 31, "Leather")                              # hampe
    s.rect(14, 19, 17, 25, "Bark")                                 # poignée
    for y in (20, 22, 24):
        s.rect(14, y, 17, y, "Bark.d", fixed=True)
    s.line((17, 13), (21, 17), "Sky")                              # plumes
    s.line((17, 14), (20, 18), "Sky")
    s.line((14, 13), (11, 17), "Sky")
    s.set(21, 18, "Sky.l")
    s.set(11, 18, "Sky.l")
    s.rect(15, 30, 16, 31, "Steel")
    if raw:                                                        # base d'une fusion
        return s
    s.shade()
    s.outline()
    return s


def meteor(raw=False) -> Sprite:
    """Meteor Rain (pool). Couleur dominante : braise. Rocher fendu de lave Neon, queue de flammes en pixels.
    Sert aussi de pièce qui tombe."""
    s = Sprite("MeteorRain", 32, 32, grip=(20.0, 20.0))
    s.depth.update({"Stone": 6, "Ember": 4, "Gold": 3, "Cream": 2})
    for k in range(9):                                             # queue de flammes
        t = k / 8
        cx, cy = 18 - 14 * t, 18 - 14 * t
        s.ell(cx, cy, 5.2 - 4.0 * t, 5.2 - 4.0 * t, "Ember" if k < 6 else "Gold")
    for k in range(5):
        t = k / 5
        s.ell(17 - 9 * t, 17 - 9 * t, 2.6 - 1.8 * t, 2.6 - 1.8 * t, "Gold")
    s.ell(20.5, 20.5, 7.5, 7.0, "Stone")                           # rocher
    for (x, y) in ((17, 18), (23, 22), (20, 25), (24, 17)):        # cratères
        s.set(x, y, "Stone.d")
    s.line((18, 16), (21, 20), "Ember!")                           # fissures de lave
    s.line((21, 20), (25, 22), "Ember!")
    s.line((21, 20), (19, 25), "Ember!")
    s.set(17, 15, "Cream")
    if raw:                                                        # base d'une fusion
        return s
    s.shade()
    s.outline()
    return s


def sawblade(raw=False) -> Sprite:
    """Orbiting Blades (pool). Couleur dominante : acier bleuté. Trois lames en croissant autour d'un moyeu
    doré à cœur Neon, pointes vers l'avant (sens de rotation). Une lame sert de pièce en orbite."""
    s = Sprite("OrbitingBlades", 32, 32, grip=(15.5, 15.5))
    s.depth.update({"Steel": 2, "Sky": 3, "Gold": 3, "Cream": 2})
    for k in range(3):                                             # 3 lames en croissant
        a0 = math.radians(k * 120)
        for t in range(0, 26):
            a = a0 + math.radians(t * 4.0)
            r = 4.5 + t * 0.42
            w = 2.4 - t * 0.07
            s.ell(15.5 + math.cos(a) * r, 15.5 + math.sin(a) * r, w, w, "Steel")
        for t in range(4, 26, 2):                                  # fil Sky sur le bord avant
            a = a0 + math.radians(t * 4.0 + 6)
            r = 4.5 + t * 0.42 + 1.2
            s.set(round(15.5 + math.cos(a) * r - 0.5), round(15.5 + math.sin(a) * r - 0.5), "Sky")
    s.ell(15.5, 15.5, 4.2, 4.2, "Gold")                            # moyeu
    s.ell(15.5, 15.5, 2.2, 2.2, "Sky!")
    s.set(15, 14, "Cream!")
    if raw:                                                        # base d'une fusion
        return s
    s.shade()
    s.outline()
    return s


def crossbowturret(raw=False) -> Sprite:
    """Crossbow Turret (pool). Couleurs : cuir et acier. Arbalète sur trépied, arcs d'acier, carreau chargé,
    viseur Neon Sky, bagues d'or."""
    s = Sprite("CrossbowTurret", 32, 32, grip=(16.0, 26.0))
    s.depth.update({"Leather": 4, "Bark": 3, "Steel": 3, "Gold": 4, "Sky": 3, "Cream": 1})
    s.thick((16, 18), (7, 30), 0.9, "Bark")                        # trépied
    s.thick((16, 18), (25, 30), 0.9, "Bark")
    s.rect(15, 18, 16, 30, "Bark")
    s.rect(11, 15, 20, 18, "Leather")                              # tourelle
    s.rect(11, 18, 20, 18, "Gold", fixed=True)
    s.rect(3, 11, 27, 13, "Leather")                               # fût
    s.rect(24, 4, 25, 20, "Steel")                                 # arc d'acier
    s.set(23, 3, "Steel")
    s.set(23, 21, "Steel")
    s.line((23, 4), (18, 12), "Cream")                             # corde
    s.line((18, 12), (23, 20), "Cream")
    s.rect(18, 11, 30, 11, "Bark.d", fixed=True)                   # carreau chargé
    s.rect(29, 10, 30, 12, "Steel")
    s.rect(8, 9, 10, 10, "Sky!")                                   # viseur
    s.rect(4, 11, 5, 13, "Gold")
    if raw:                                                        # base d'une fusion
        return s
    s.shade()
    s.outline()
    return s


def bolt(raw=False) -> Sprite:
    """Pièce : carreau de la tourelle (court, pointe d'acier, ailettes d'or)."""
    s = Sprite("Bolt", 20, 8, grip=(10.0, 3.5))
    s.depth.update({"Steel": 2, "Bark": 2, "Gold": 2})
    s.rect(4, 3, 16, 4, "Bark")
    for x in range(0, 4):
        h = round(x * 0.7)
        s.rect(x, 4 - h, x, 3 + h, "Steel")
    s.rect(14, 1, 17, 2, "Gold")
    s.rect(14, 5, 17, 6, "Gold")
    if raw:                                                        # base d'une fusion
        return s
    s.shade()
    s.outline()
    return s


# =============================================================================================
# Fusions (dossier 12, section 3) : la même arme en version ultime, plus riche, plus dorée, un détail en plus


def _fusion(base, name, depth=None):
    s = base(raw=True)
    s.name = name
    if depth:
        s.depth.update(depth)
    return s


def _done(s):
    s.shade()
    s.outline()
    return s


def royalgreatsword() -> Sprite:
    """Royal Greatsword (Broadsword + Area Rune) : lame élargie bordée d'or, garde en couronne, gemme d'or,
    et le canard porte une couronne (gag)."""
    s = _fusion(broadsword, "RoyalGreatsword")
    for y in range(4, 21):                                         # lame plus large, fil d'or
        s.set(11, y, "Gold", fixed=False)
        s.set(20, y, "Gold", fixed=False)
    s.rect(12, 3, 19, 3, "Steel")
    for (x, y) in ((8, 18), (11, 16), (14, 17), (17, 17), (20, 16), (23, 18)):   # couronne de la garde
        s.rect(x, y, x + 1, y + 2, "Gold")
    s.rect(14, 20, 17, 23, "Royal")
    s.rect(15, 21, 16, 22, "Gold!")
    s.set(15, 21, "Cream!")
    for (x, y) in ((12, 26), (13, 25), (14, 26), (15, 25), (16, 26)):    # couronne du canard
        s.set(x, y, "Gold")
    return _done(s)


def stormbow() -> Sprite:
    """Storm Bow (Longbow + Attack Speed Rune) : branches couleur d'orage, nuages aux bouts, corde et
    flèche-éclair Neon."""
    s = _fusion(longbow, "StormBow", {"Stone": 3, "Sky": 2})
    s.recolor({"Leaf": "Royal", "Leather": "Plum"})
    s.recolor({"Bark": "Sky"})
    for (cx, cy) in ((15.5, 1.5), (15.5, 30.0)):                   # nuages aux bouts
        s.ell(cx, cy, 3.4, 2.0, "Cream")
        s.ell(cx + 2.5, cy - 0.5, 2.2, 1.6, "Cream")
    for x in range(1, 18, 3):                                      # flèche-éclair
        s.set(x, 14 if (x // 3) % 2 else 16, "Sky!")
    s.rect(18, 2, 18, 29, "Sky!")
    s.set(18, 15, "Cream!")
    return _done(s)


def sunstaff() -> Sprite:
    """Sun Staff (Fire Staff + Damage Rune) : un petit soleil Neon à rayons, griffes d'or, guimauve dorée."""
    s = _fusion(firestaff, "SunStaff", {"Gold": 4})
    s.recolor({"Ember": "Gold"})
    s.ell(15.5, 6.0, 4.6, 4.6, "Gold!")
    s.ell(15.5, 6.0, 2.4, 2.4, "Cream!")
    for a in range(0, 360, 45):                                    # rayons
        r0, r1 = 5.4, 7.6
        for r in (r0, r1):
            x = round(15.5 + math.cos(math.radians(a)) * r - 0.5)
            y = round(6.0 + math.sin(math.radians(a)) * r - 0.5)
            s.set(x, y, "Gold!")
    s.rect(23, 10, 27, 14, "Gold")                                 # guimauve dorée
    s.rect(23, 10, 27, 10, "Leather")
    return _done(s)


def mountainmaul() -> Sprite:
    """Mountain Maul (Quake Hammer + Armor Rune) : tête élargie en montagne, deux pics de pierre nets, faces
    d'or, lave Neon, deux pansements, une petite fleur au sommet (gag)."""
    s = _fusion(quakehammer, "MountainMaul")
    s.rect(4, 2, 27, 12, "Stone")                                  # tête élargie de 4 px
    s.rect(0, 3, 3, 11, "Steel")
    s.rect(28, 3, 31, 11, "Steel")
    for x0 in (8, 19):                                             # deux pics nets (3 x 5)
        for k in range(5):
            w = 3 - k // 2
            s.rect(x0 + (3 - w) // 2, 1 - k, x0 + (3 - w) // 2 + w - 1, 1 - k, "Stone")
    s.line((10, 4), (12, 7), "Ember!")
    s.line((12, 7), (11, 10), "Ember!")
    s.line((21, 10), (22, 7), "Ember!")
    s.line((6, 5), (7, 9), "Ember!")
    s.rect(14, 6, 19, 7, "Cream", fixed=True)
    s.rect(16, 4, 17, 9, "Cream", fixed=True)
    s.rect(24, 8, 26, 9, "Cream", fixed=True)                      # second pansement
    s.set(20, -5, "Leaf")                                          # fleur au sommet d'un pic
    s.set(20, -6, "Gold")
    s.recolor({"Steel": "Gold"})
    return _done(s)


def daggerflurry() -> Sprite:
    """Dagger Flurry (Throwing Daggers + Projectile Rune) : trois lames en éventail sur une seule garde dorée,
    un seul pommeau, rubans de trois couleurs."""
    s = Sprite("DaggerFlurry", 32, 32, grip=(15.5, 22.5))
    s.depth.update({"Steel": 2, "Plum": 3, "Grape": 3, "Gold": 3, "Sky": 2, "Cream": 2})
    for ang in (-22, 22):                                          # lames de côté
        a = math.radians(ang)
        tip = (15.5 + math.sin(a) * 15, 17 - math.cos(a) * 15)
        s.thick((15.5, 16), tip, 1.5, "Steel")
        s.thick((15.5 + math.sin(a) * 4, 13), tip, 0.5, "Steel.l", fixed=True)
    for y, w in zip(range(1, 18), (2, 2, 4, 4, 4, 6, 6, 6, 6, 6, 6, 6, 4, 4, 4, 4, 4)):   # lame centrale
        s.rect(16 - w // 2, y, 15 + w // 2, y, "Steel")
    s.rect(15, 4, 15, 15, "Gold", fixed=True)                      # fil d'or
    s.rect(8, 17, 23, 19, "Gold")                                  # garde dorée commune
    s.rect(14, 20, 17, 26, "Grape")                                # poignée
    for y in (21, 23, 25):
        s.rect(14, y, 17, y, "Ink", fixed=True)
    s.rect(14, 27, 17, 29, "Grape!")
    s.set(15, 27, "Cream!")
    s.line((18, 28), (24, 26), "Sky")                              # rubans
    s.line((18, 29), (25, 30), "Gold")
    s.line((13, 29), (8, 31), "Grape")
    return _done(s)


def grandchime() -> Sprite:
    """Grand Chime (Holy Aura + Vitality Rune) : grande cloche dorée à double bord, cœur Neon, plus de
    « ding »."""
    s = _fusion(holybell, "GrandChime", {"Gold": 6})
    s.recolor({"Cream": "Gold", "Leather": "Cream"})
    for y in range(11, 26):
        w = 10 + round((y - 11) * 1.15)
        s.rect(16 - w // 2, y, 15 + w // 2, y, "Gold")
    s.rect(3, 26, 28, 27, "Cream")
    s.rect(5, 23, 26, 23, "Cream", fixed=True)
    s.rect(14, 18, 17, 21, "Sky!")                                 # cœur Neon
    s.set(13, 18, "Sky!")
    s.set(18, 18, "Sky!")
    for (x, y) in ((25, 9), (27, 7), (29, 5), (6, 9), (4, 7), (2, 5)):
        s.set(x, y, "Gold!")
    return _done(s)


def axetornado() -> Sprite:
    """Axe Tornado (Spinning Axes + Duration Rune) : hache à double fer, toujours souriante, deux tourbillons
    de vent de chaque côté."""
    s = _fusion(spinningaxe, "AxeTornado", {"Sky": 2})
    for y in range(2, 19):                                         # second fer, en miroir
        u = (y - 2) / 16.0
        edge = 31 - (3 + round(3 * (1 - math.sin(math.pi * u))))
        s.rect(18, y, edge, y, "Steel")
        s.set(edge, y, "Steel.l")
    s.rect(21, 7, 21, 8, "Ink")                                    # second smiley
    s.rect(24, 7, 24, 8, "Ink")
    for (x, y) in ((20, 11), (21, 12), (22, 13), (23, 13), (24, 12), (25, 11)):
        s.set(x, y, "Ink")
    s.ring(16.0, 34.0, 9.5, 11.0, "Sky", keep=lambda a: 205 <= a <= 335)    # arcs de tourbillon
    s.ring(16.0, 37.0, 12.5, 14.0, "Sky", keep=lambda a: 215 <= a <= 325)
    return _done(s)


def ringmasterlash() -> Sprite:
    """Ringmaster Lash (Beast Whip + Agility Rune) : manche rayé or et raisin, lanière plus longue qui fait
    une boucle, claquoir étoile Neon, trois étoiles groupées."""
    s = _fusion(beastwhip, "RingmasterLash")
    s.recolor({"Ember": "Grape", "Cream": "Gold"})
    s.ring(21.0, 21.0, 3.2, 4.6, "Leather")                        # boucle
    s.thick((24, 17), (22, 18), 1.2, "Leather")
    for (x, y) in ((25, 26), (28, 28), (26, 30)):                  # étoiles groupées
        for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
            s.set(x + dx, y + dy, "Gold!")
    return _done(s)


def thunderweb() -> Sprite:
    """Thunder Web (Lightning Chain + Crit Rune) : tige dorée, boule d'acier, toile d'éclairs Neon ramifiés."""
    s = _fusion(lightningrod, "ThunderWeb")
    s.recolor({"Steel": "Gold"})
    s.ell(15.5, 6.5, 4.0, 4.0, "Steel")
    for pts in (((11, 9), (6, 11), (7, 14), (2, 16)), ((20, 2), (24, 6), (28, 5)), ((7, 2), (3, 5), (1, 3)),
                ((22, 11), (25, 9), (29, 10))):
        for a, b in zip(pts, pts[1:]):
            s.line(a, b, "Sky!")
    for (x, y) in ((2, 16), (28, 5), (1, 3), (29, 10)):
        s.set(x, y, "Cream!")
    return _done(s)


def blizzardglobe() -> Sprite:
    """Blizzard Globe (Frost Nova + Cooldown Rune) : globe plus grand qui dépasse du socle doré, deux
    stalactites de glace en haut, flocon d'or Neon, tempête de neige."""
    s = Sprite("BlizzardGlobe", 32, 32, grip=(15.5, 27.0))
    s.depth.update({"Sky": 6, "Gold": 6, "Cream": 6, "Plum": 6})
    s.ell(15.5, 12.0, 13.0, 12.5, "Sky")
    s.ell(15.5, 1.2, 8.0, 2.4, "Cream")                            # tas de neige sur le globe
    s.ell(12.0, 0.4, 3.0, 1.6, "Cream")
    s.rect(9, 24, 22, 27, "Gold")                                  # socle doré
    s.rect(6, 28, 25, 31, "Gold")
    s.rect(6, 28, 25, 28, "Plum", fixed=True)
    for k in range(-5, 6):                                         # flocon d'or Neon
        s.set(15 + k, 12, "Gold!")
        s.set(15, 12 + k, "Gold!")
    for k in (-4, -3, 3, 4):
        s.set(15 + k, 12 + k, "Gold!")
        s.set(15 + k, 12 - k, "Gold!")
    s.set(15, 12, "Cream!")
    for a in range(0, 360, 24):                                    # tempête qui tourne
        r = 7.5 + (a % 48) / 16
        s.set(round(15.5 + math.cos(math.radians(a)) * r), round(12 + math.sin(math.radians(a)) * r), "Cream")
    for (x, y) in ((6, 6), (5, 8), (7, 5)):
        s.set(x, y, "Cream")
    return _done(s)


def comebackrang() -> Sprite:
    """Comeback Rang (Boomerang + Magnet Rune) : le même boomerang en V, plus épais, liseré Neon cyan sur le
    bord intérieur, un petit cristal cyan au sommet (il revient toujours)."""
    s = Sprite("ComebackRang", 32, 32, grip=(15.5, 9.0))
    s.depth.update({"Gold": 3, "Ember": 3, "Cream": 3, "Sky": 3})
    for (p0, p1) in (((15, 7), (9, 15)), ((9, 15), (4, 26)), ((15, 7), (22, 14)), ((22, 14), (28, 25))):
        s.thick(p0, p1, 3.4, "Gold")                               # bras plus épais
    s.thick((4, 26), (5, 23), 3.0, "Ember")
    s.thick((28, 25), (27, 22), 3.0, "Ember")
    for (p0, p1) in (((15, 11), (11, 17)), ((11, 17), (7, 25)), ((16, 11), (20, 17)), ((20, 17), (25, 25))):
        s.line(p0, p1, "Sky!")                                     # liseré Neon intérieur
    s.rect(14, 3, 17, 5, "Sky!")                                   # cristal au sommet
    s.set(15, 3, "Cream!")
    for (x, y) in ((8, 19), (23, 18)):
        s.set(x, y, "Ember")
    return _done(s)


def clustersack() -> Sprite:
    """Cluster Sack (Bomb Bag + Projectile Rune) : trois mini-bombes de plus dépassent de l'ouverture, pièces
    dorées cousues sur les épaules."""
    s = _fusion(bombbag, "ClusterSack")
    for (x0, y0) in ((4, 3), (24, 3), (16, -3)):                   # mini-bombes 4 x 4
        s.rect(x0, y0 + 1, x0 + 3, y0 + 3, "Ink")
        s.rect(x0 + 1, y0, x0 + 2, y0 + 4, "Ink")
        s.set(x0 + 1, y0 + 1, "Cream")
        s.set(x0 + 2, y0 - 1, "Gold!")
    s.rect(7, 14, 9, 16, "Gold", fixed=True)
    s.rect(22, 14, 24, 16, "Gold", fixed=True)
    return _done(s)


def cometjavelin() -> Sprite:
    """Comet Javelin (Spear Throw + Damage Rune) : pointe d'or, hampe bleu roi, queue de comète Neon."""
    s = _fusion(spear, "CometJavelin", {"Gold": 3, "Royal": 2})
    s.recolor({"Steel": "Gold", "Leather": "Royal", "Sky": "Cream"})
    for k, y in enumerate(range(12, 30, 2)):                       # queue de comète
        s.set(18 + k // 2, y, "Sky!")
        s.set(13 - k // 2, y + 1, "Sky!")
    s.ell(15.5, 4.5, 1.6, 2.2, "Cream!")
    return _done(s)


def starshower() -> Sprite:
    """Star Shower (Meteor Rain + Luck Rune) : le même météore en feu, roche dorée et souriante, couronné de
    trois petites étoiles Neon."""
    s = _fusion(meteor, "StarShower", {"Gold": 5})
    s.recolor({"Stone": "Gold", "Ember": "Ember"})
    s.rect(18, 19, 18, 20, "Ink")                                  # visage content
    s.rect(22, 19, 22, 20, "Ink")
    s.rect(18, 23, 22, 23, "Ink")
    s.set(17, 22, "Ink")
    s.set(23, 22, "Ink")
    for (cx, cy) in ((14, 13), (21, 10), (27, 14)):                # couronne de 3 étoiles 5 x 5
        for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1), (2, 0), (-2, 0), (0, -2), (0, 2)):
            if abs(dx) + abs(dy) <= 2:
                s.set(cx + dx, cy + dy, "Gold!")
        s.set(cx, cy, "Cream!")
    return _done(s)


def buzzsawhalo() -> Sprite:
    """Buzzsaw Halo (Orbiting Blades + Area Rune) : six lames en croissant, anneau doré de 2 px, gros cœur
    Neon ; le halo lumineux autour est un effet en jeu."""
    s = Sprite("BuzzsawHalo", 32, 32, grip=(15.5, 15.5))
    s.depth.update({"Steel": 2, "Gold": 3, "Sky": 3, "Cream": 2})
    for k in range(6):
        a0 = math.radians(k * 60)
        for t in range(0, 22):
            a = a0 + math.radians(t * 3.6)
            r = 6.0 + t * 0.42
            w = 2.0 - t * 0.06
            s.ell(15.5 + math.cos(a) * r, 15.5 + math.sin(a) * r, w, w, "Steel")
    s.ring(15.5, 15.5, 5.0, 7.0, "Gold")                           # anneau doré
    s.ell(15.5, 15.5, 4.2, 4.2, "Sky!")                            # gros cœur Neon
    s.ell(15.5, 15.5, 1.6, 1.6, "Cream!")
    return _done(s)


def siegeballista() -> Sprite:
    """Siege Ballista (Crossbow Turret + Duration Rune) : baliste sur affût à roues, arcs dorés, gros carreau."""
    s = _fusion(crossbowturret, "SiegeBallista", {"Gold": 4, "Bark": 4})
    for (x, y) in list(s.px):                                      # on retire le trépied
        if y >= 19:
            s.clear(x, y)
    s.rect(6, 19, 25, 22, "Bark")                                  # affût
    for cx in (9.5, 22.5):                                         # roues
        s.ring(cx, 26.0, 2.0, 4.6, "Leather")
        s.ell(cx, 26.0, 1.4, 1.4, "Gold")
    s.recolor({"Steel": "Gold"})
    s.rect(18, 10, 31, 12, "Bark.d", fixed=True)                   # gros carreau
    s.rect(30, 9, 31, 13, "Steel")
    return _done(s)


FUSION_SPRITES = {
    "Broadsword": royalgreatsword, "Longbow": stormbow, "FireStaff": sunstaff, "QuakeHammer": mountainmaul,
    "ThrowingDaggers": daggerflurry, "HolyAura": grandchime, "SpinningAxes": axetornado,
    "BeastWhip": ringmasterlash, "LightningChain": thunderweb, "FrostNova": blizzardglobe,
    "Boomerang": comebackrang, "BombBag": clustersack, "SpearThrow": cometjavelin, "MeteorRain": starshower,
    "OrbitingBlades": buzzsawhalo, "CrossbowTurret": siegeballista,
}


WEAPON_SPRITES = {
    "Broadsword": broadsword, "Longbow": longbow, "FireStaff": firestaff, "QuakeHammer": quakehammer,
    "ThrowingDaggers": throwingdagger, "HolyAura": holybell, "SpinningAxes": spinningaxe,
    "BeastWhip": beastwhip, "LightningChain": lightningrod, "FrostNova": snowglobe, "Boomerang": boomerang,
    "BombBag": bombbag, "SpearThrow": spear, "MeteorRain": meteor, "OrbitingBlades": sawblade,
    "CrossbowTurret": crossbowturret,
}
PIECE_SPRITES = {"Bomb": bomb, "Arrow": arrow, "Bolt": bolt}
SPRITES = {**WEAPON_SPRITES, **PIECE_SPRITES, **{fn().name: fn for fn in FUSION_SPRITES.values()}}


def preview(path, names=None, scale=8, cols=8):
    """Planche des sprites à plat (Python seul, PIL)."""
    from PIL import Image, ImageDraw

    names = names or list(SPRITES)
    cell = 36 * scale
    rows = (len(names) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell, rows * (cell + 30)), (246, 236, 217, 255))
    d = ImageDraw.Draw(sheet)
    for i, name in enumerate(names):
        sp = SPRITES[name]().export()
        im = Image.new("RGBA", (sp["w"], sp["h"]), (0, 0, 0, 0))
        for x, y, hx, _ in sp["pixels"]:
            im.putpixel((x, y), tuple(int(hx[k:k + 2], 16) for k in (0, 2, 4)) + (255,))
        im = im.resize((sp["w"] * scale, sp["h"] * scale), Image.NEAREST)
        ox = (i % cols) * cell + (cell - im.width) // 2
        oy = (i // cols) * (cell + 30) + (cell - im.height) // 2
        sheet.alpha_composite(im, (ox, oy))
        d.text(((i % cols) * cell + 8, (i // cols) * (cell + 30) + cell + 4), name, fill=(28, 23, 38))
    sheet.save(path)
    return path


if __name__ == "__main__":
    print(preview(sys.argv[1] if len(sys.argv) > 1 else "pixelweapons.png"))
