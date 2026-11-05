"""COHUE — A14, planche concept des armes et des effets (étape 2, porte 2), DA du 5 nov. (2e version).

Blender 5.2 en ligne de commande (rien n'est touché dans un Blender ouvert) :

    blender -b --factory-startup --python assets/a14/concept.py -- <vue[,vue]|all> <dossier de sortie>

Vues : lineup, swing, fireball, bomb, legend, sequence, dense. Écrit aussi <sortie>/sprites.json (les
sprites en pixels, pour les icônes que board.py exporte en PNG) et <sortie>/tris.json.

Direction artistique (Clément, 5 nov., « oui a tous ») :
- armes et pièces en jeu : sprite en pixels sur une grille de 32, contour Ink de 1 px, détails dans les
  pixels (reflets, gravures, gemme), épaissi de 2 à 5 pixels (la poignée et la garde plus épaisses) ; une
  maille fusionnée par arme ; pas de tenons ; une couleur dominante par arme ; le sprite sert aussi d'icône ;
- effets : lisses et lumineux (particules douces, rubans, anneaux Neon, étincelles), jamais en cubes ni en
  pixels : « des blocs pour ce qui existe, de la lumière pour ce qui se passe » ; le rouge reste aux ennemis.
Le décor, les gobelins et l'avatar restent ceux de A01 (briques à tenons) : ils servent de contexte.
"""

from __future__ import annotations

import json
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Euler, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.append(os.path.join(ROOT, "assets", "voxel"))

import boards as BD  # noqa: E402
import brick  # noqa: E402
import build as B  # noqa: E402
import cohue_voxel as cv  # noqa: E402
import models as M  # noqa: E402
import studs as S  # noqa: E402

pixel_to_blender = cv.to_blender   # maille gloutonne étanche de A01 (faces fusionnées, couleur par sommet)
brick.STUD_TEXTURE = True
cv.to_blender = brick.to_blender   # décor, gobelins et avatar de A01 : briques à tenons (contexte)
Vox = cv.Vox
PX = 0.125                         # un pixel du sprite = 0,125 stud (32 px = 4 studs)


# =============================================================================================
# Sprites en pixels


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


def broadsword() -> Sprite:
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
    s.shade()
    s.outline()
    return s


def longbow() -> Sprite:
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
    s.shade()
    s.outline()
    return s


def firestaff() -> Sprite:
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
    s.shade()
    s.outline()
    return s


def bombbag() -> Sprite:
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
    s.shade()
    s.outline()
    s.set(13, -2, "Gold!")                                         # mèches qui crépitent
    s.set(14, -2, "Gold!")
    s.set(20, -2, "Gold!")
    s.set(13, -1, "Leather")
    s.set(20, -1, "Leather")
    return s


def bomb() -> Sprite:
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
    s.shade()
    s.outline()
    s.rect(12, 0, 14, 0, "Gold!")                                  # étincelle en croix
    s.rect(13, -1, 13, 1, "Gold!")
    s.set(13, 0, "Cream!")
    return s


def arrow() -> Sprite:
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
    s.shade()
    s.outline()
    return s


SPRITES = {"Broadsword": broadsword, "Longbow": longbow, "FireStaff": firestaff, "BombBag": bombbag,
           "Bomb": bomb, "Arrow": arrow}

_mats: dict = {}


def weapon_material():
    mat = bpy.data.materials.get("A14_Pixel")
    if mat:
        return mat
    mat = bpy.data.materials.new("A14_Pixel")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Color"
    nt.links.new(vc.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.5
    return mat


def neon_material(strength=1.15):   # Neon qui garde sa teinte (braise reste orange)
    key = ("neon", strength)
    if key in _mats:
        return _mats[key]
    mat = bpy.data.materials.new("A14_PixelNeon")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Color"
    bsdf.inputs["Base Color"].default_value = (0, 0, 0, 1)
    nt.links.new(vc.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = strength
    _mats[key] = mat
    return mat


def place_weapon(fn, loc, rot=(0, 0, 0), scale=1.0, stats=None):
    """Pose une arme en pixels épaissis, origine au point de prise. Rend l'objet racine."""
    sp = fn()
    body, neon = sp.voxels()
    o = sp.origin()
    root = bpy.data.objects.new(sp.name + "_Root", None)
    bpy.context.scene.collection.objects.link(root)
    obs = [pixel_to_blender(body, o, voxel=PX)]
    obs[0].data.materials.clear()
    obs[0].data.materials.append(weapon_material())
    if neon.c:
        ob = pixel_to_blender(neon, o, voxel=PX)
        ob.data.materials.clear()
        ob.data.materials.append(neon_material())
        obs.append(ob)
    for ob in obs:
        ob.parent = root
    root.location = loc
    root.rotation_euler = rot
    root.scale = (scale, scale, scale)
    if stats is not None:
        stats[sp.name] = sum(ob["tris"] for ob in obs)
    return root


def aim_euler(direction, roll=0.0):
    """Rotation qui envoie +Z (la pointe de l'arme) vers `direction`, avec un roulis autour de la lame."""
    q = Vector((0, 0, 1)).rotation_difference(Vector(direction).normalized())
    return (q @ Euler((0, 0, roll)).to_quaternion()).to_euler()


# =============================================================================================
# Effets lisses et lumineux


BILLBOARDS: list = []


def _ramp(nt, stops, name="ramp"):
    r = nt.nodes.new("ShaderNodeValToRGB")
    r.label = name
    els = r.color_ramp.elements
    els[0].position, els[0].color = stops[0][0], (stops[0][1],) * 3 + (stops[0][1],)
    els[1].position, els[1].color = stops[-1][0], (stops[-1][1],) * 3 + (stops[-1][1],)
    for pos, a in stops[1:-1]:
        e = els.new(pos)
        e.color = (a, a, a, a)
    r.color_ramp.interpolation = "EASE"
    return r


def _color_ramp(nt, color_stops):
    cr = nt.nodes.new("ShaderNodeValToRGB")
    els = cr.color_ramp.elements
    els[0].position, els[0].color = color_stops[0][0], B.hexcol(color_stops[0][1])
    els[1].position, els[1].color = color_stops[-1][0], B.hexcol(color_stops[-1][1])
    for pos, hx in color_stops[1:-1]:
        els.new(pos).color = B.hexcol(hx)
    return cr


def fx_material(hexc, strength, stops, mode="radial", dashes=0, along=None, color_stops=None, matte=False):
    """Matériau d'effet : émission (lumière) et alpha calculés sur les UV.
    radial : alpha selon la distance au centre (0 au centre, 1 au bord) ; ribbon : alpha = across(v) x along(u)."""
    key = (hexc, strength, tuple(stops), mode, dashes, tuple(along or ()), tuple(color_stops or ()), matte)
    if key in _mats:
        return _mats[key]
    mat = bpy.data.materials.new(f"A14_FX_{len(_mats)}")
    mat.use_nodes = True
    nt = mat.node_tree
    L = nt.links
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    if matte:
        bsdf.inputs["Base Color"].default_value = B.hexcol(hexc)
        bsdf.inputs["Roughness"].default_value = 0.6
    else:
        bsdf.inputs["Base Color"].default_value = (0, 0, 0, 1)
        bsdf.inputs["Specular IOR Level"].default_value = 0.0
    bsdf.inputs["Emission Color"].default_value = B.hexcol(hexc)
    bsdf.inputs["Emission Strength"].default_value = strength
    uvn = nt.nodes.new("ShaderNodeUVMap")
    if mode == "radial":
        sub = nt.nodes.new("ShaderNodeVectorMath")
        sub.operation = "SUBTRACT"
        sub.inputs[1].default_value = (0.5, 0.5, 0.0)
        L.new(uvn.outputs["UV"], sub.inputs[0])
        ln = nt.nodes.new("ShaderNodeVectorMath")
        ln.operation = "LENGTH"
        L.new(sub.outputs["Vector"], ln.inputs[0])
        mul = nt.nodes.new("ShaderNodeMath")
        mul.operation = "MULTIPLY"
        mul.inputs[1].default_value = 2.0
        L.new(ln.outputs["Value"], mul.inputs[0])
        ramp = _ramp(nt, stops)
        L.new(mul.outputs["Value"], ramp.inputs["Fac"])
        alpha = ramp.outputs["Alpha"]
        if dashes:
            grad = nt.nodes.new("ShaderNodeTexGradient")
            grad.gradient_type = "RADIAL"
            L.new(sub.outputs["Vector"], grad.inputs["Vector"])
            m2 = nt.nodes.new("ShaderNodeMath")
            m2.operation = "MULTIPLY"
            m2.inputs[1].default_value = float(dashes)
            L.new(grad.outputs["Fac"], m2.inputs[0])
            fr = nt.nodes.new("ShaderNodeMath")
            fr.operation = "FRACT"
            L.new(m2.outputs["Value"], fr.inputs[0])
            lt = nt.nodes.new("ShaderNodeMath")
            lt.operation = "LESS_THAN"
            lt.inputs[1].default_value = 0.58
            L.new(fr.outputs["Value"], lt.inputs[0])
            m3 = nt.nodes.new("ShaderNodeMath")
            m3.operation = "MULTIPLY"
            L.new(alpha, m3.inputs[0])
            L.new(lt.outputs["Value"], m3.inputs[1])
            alpha = m3.outputs["Value"]
        if color_stops:
            cr = _color_ramp(nt, color_stops)
            L.new(mul.outputs["Value"], cr.inputs["Fac"])
            L.new(cr.outputs["Color"], bsdf.inputs["Emission Color"])
    else:
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        L.new(uvn.outputs["UV"], sep.inputs[0])
        across = _ramp(nt, stops, "across")
        L.new(sep.outputs["Y"], across.inputs["Fac"])
        al = _ramp(nt, along or [(0.0, 1.0), (1.0, 1.0)], "along")
        L.new(sep.outputs["X"], al.inputs["Fac"])
        m = nt.nodes.new("ShaderNodeMath")
        m.operation = "MULTIPLY"
        L.new(across.outputs["Alpha"], m.inputs[0])
        L.new(al.outputs["Alpha"], m.inputs[1])
        alpha = m.outputs["Value"]
        if color_stops:
            cr = _color_ramp(nt, color_stops)
            L.new(sep.outputs["Y"], cr.inputs["Fac"])
            L.new(cr.outputs["Color"], bsdf.inputs["Emission Color"])
    L.new(alpha, bsdf.inputs["Alpha"])
    for attr, val in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
        try:
            setattr(mat, attr, val)
        except Exception:
            pass
    _mats[key] = mat
    return mat


def _quad(name, w, h):
    me = bpy.data.meshes.new(name)
    me.from_pydata([(-w / 2, -h / 2, 0), (w / 2, -h / 2, 0), (w / 2, h / 2, 0), (-w / 2, h / 2, 0)], [],
                   [(0, 1, 2, 3)])
    uv = me.uv_layers.new(name="UVMap")
    for i, co in enumerate(((0, 0), (1, 0), (1, 1), (0, 1))):
        uv.data[i].uv = co
    return me


def _link(ob):
    bpy.context.scene.collection.objects.link(ob)
    ob.visible_shadow = False
    return ob


def sprite(loc, size, hexc, strength, stops=((0.0, 1.0), (0.35, 0.7), (1.0, 0.0)), stretch=1.0, color_stops=None):
    """Particule douce (ParticleEmitter en jeu) : plan tourné vers la caméra, halo radial."""
    ob = _link(bpy.data.objects.new("A14_Sprite", _quad("A14_Sprite", size, size * stretch)))
    ob.data.materials.append(fx_material(hexc, strength, list(stops), color_stops=color_stops))
    ob.location = loc
    BILLBOARDS.append(ob)
    return ob


def disc(center, radius, z, hexc, strength, stops, dashes=0, color_stops=None, matte=False):
    """Plan horizontal (anneau Neon, zone au sol, onde de choc) : profil radial."""
    ob = _link(bpy.data.objects.new("A14_Disc", _quad("A14_Disc", radius * 2, radius * 2)))
    ob.data.materials.append(fx_material(hexc, strength, list(stops), dashes=dashes, color_stops=color_stops,
                                         matte=matte))
    ob.location = (center[0], center[1], z)
    return ob


def ribbon(points, widths, hexc, strength, across, along, color_stops=None, name="A14_Ribbon"):
    """Ruban (Trail ou Beam en jeu) : bande qui suit `points` ; u le long, v en travers (0 = bord extérieur)."""
    verts, faces, uvs = [], [], []
    n = len(points)
    for i, (p, w) in enumerate(zip(points, widths)):
        p = Vector(p)
        q = Vector(points[min(i + 1, n - 1)]) - Vector(points[max(i - 1, 0)])
        side = Vector((-q.y, q.x, 0)).normalized()
        verts += [p + side * w * 0.5, p - side * w * 0.5]
        uvs += [(i / (n - 1), 0.0), (i / (n - 1), 1.0)]
    for i in range(n - 1):
        a = 2 * i
        faces.append((a, a + 2, a + 3, a + 1))
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    uv = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        for li, vi in zip(poly.loop_indices, poly.vertices):
            uv.data[li].uv = uvs[vi]
    ob = _link(bpy.data.objects.new(name, me))
    ob.data.materials.append(fx_material(hexc, strength, list(across), mode="ribbon", along=list(along),
                                         color_stops=color_stops))
    return ob


def _sphere_mesh(name, radius, u=12, v=8):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=radius)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    return me


def _solid_glow(hexc, strength):
    key = ("solid", hexc, strength)
    mat = _mats.get(key)
    if not mat:
        mat = bpy.data.materials.new("A14_Glow")
        mat.use_nodes = True
        bsdf = next(nd for nd in mat.node_tree.nodes if nd.type == "BSDF_PRINCIPLED")
        bsdf.inputs["Base Color"].default_value = (0, 0, 0, 1)
        bsdf.inputs["Emission Color"].default_value = B.hexcol(hexc)
        bsdf.inputs["Emission Strength"].default_value = strength
        _mats[key] = mat
    return mat


def streak(loc, direction, length, width, hexc, strength):
    """Étincelle : capsule lumineuse étirée dans la direction du mouvement."""
    ob = _link(bpy.data.objects.new("A14_Streak", _sphere_mesh("A14_Streak", 0.5, 8, 6)))
    ob.data.materials.append(_solid_glow(hexc, strength))
    ob.location = loc
    ob.scale = (width, width, length)
    ob.rotation_euler = Vector((0, 0, 1)).rotation_difference(Vector(direction).normalized()).to_euler()
    return ob


def glow_ball(loc, radius, hexc, strength, matte=False):
    ob = _link(bpy.data.objects.new("A14_Ball", _sphere_mesh("A14_Ball", radius, 16, 10)))
    if matte:
        mat = bpy.data.materials.new("A14_Matte")
        mat.use_nodes = True
        bsdf = next(nd for nd in mat.node_tree.nodes if nd.type == "BSDF_PRINCIPLED")
        bsdf.inputs["Base Color"].default_value = B.hexcol(hexc)
        bsdf.inputs["Roughness"].default_value = 0.45
        ob.visible_shadow = True
    else:
        mat = _solid_glow(hexc, strength)
    ob.data.materials.append(mat)
    ob.location = loc
    return ob


def point_light(loc, hexc, power):
    data = bpy.data.lights.new("A14_Light", "POINT")
    data.energy = power
    data.color = cv.hex_rgb(hexc)
    data.shadow_soft_size = 0.8
    ob = bpy.data.objects.new("A14_Light", data)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    return ob


HX = dict(cv.PALETTE)
WHITE = "FFF8EC"


def swing(center, radius=8.0, half=70.0, height=2.9):
    """Coup du Broadsword : grand croissant de lumière, bord extérieur blanc, corps Sky qui se fond vers
    l'intérieur ; la fin du geste est opaque, le début s'efface (Beam à dégradé en jeu)."""
    pts, widths = [], []
    n = 40
    for i in range(n + 1):
        u = i / n
        th = math.radians(-half + 2 * half * u)
        thick = 0.7 + 4.6 * math.sin(math.pi * min(1.0, u * 1.06)) ** 0.7
        r = radius - thick / 2
        pts.append((center[0] - math.sin(th) * r, center[1] - math.cos(th) * r, height))
        widths.append(thick)
    halo = ribbon([(x, y, z - 0.05) for x, y, z in pts], [w * 1.5 + 1.0 for w in widths], HX["Sky"], 1.1,
                  across=[(0.0, 0.0), (0.3, 0.6), (0.7, 0.45), (1.0, 0.0)],
                  along=[(0.0, 0.0), (0.6, 0.6), (1.0, 1.0)], name="A14_SwingHalo")
    core = ribbon(pts, widths, HX["Sky"], 1.8,
                  across=[(0.0, 1.0), (0.12, 1.0), (0.45, 0.7), (1.0, 0.0)],
                  along=[(0.0, 0.25), (0.5, 0.8), (0.9, 1.0), (1.0, 1.0)],
                  color_stops=[(0.0, WHITE), (0.2, "D6F6FF"), (0.45, "8EE6FF"), (1.0, HX["Sky"])])
    return core


def hit_spark(loc, away, seed=0):
    """Impact de mêlée : éclat blanc, halo Sky, étincelles qui partent à l'opposé du joueur."""
    rnd = random.Random(seed)
    sprite(loc, 2.6, WHITE, 9.0, stops=((0.0, 1.0), (0.12, 0.9), (0.3, 0.25), (1.0, 0.0)))
    sprite(loc, 3.4, HX["Sky"], 1.0, stops=((0.0, 0.6), (0.4, 0.25), (1.0, 0.0)))
    for k in range(7):
        d = (Vector(away) + Vector((rnd.uniform(-0.7, 0.7), rnd.uniform(-0.7, 0.7), rnd.uniform(0.0, 0.8)))).normalized()
        streak(Vector(loc) + d * rnd.uniform(0.6, 1.3), d, rnd.uniform(0.5, 0.9), 0.07,
               WHITE if k % 2 else HX["Sky"], 6.0 if k % 2 else 1.2)


def fireball(start, end, height=2.5, seed=1):
    """Boule de feu : cœur blanc-or, halo braise, longue traînée qui s'éteint, petites flammes douces."""
    rnd = random.Random(seed)
    s = Vector((start[0], start[1], height))
    e = Vector((end[0], end[1], height))
    d = (e - s).normalized()
    glow_ball(e, 0.42, "FFF2C4", 14.0)
    sprite(e, 1.9, HX["Gold"], 1.3, stops=((0.0, 1.0), (0.3, 0.8), (1.0, 0.0)))
    sprite(e, 3.6, HX["Ember"], 1.1, stops=((0.0, 0.8), (0.4, 0.35), (1.0, 0.0)))
    pts = [e - d * (k * 0.45) + Vector((0, 0, 0.05 * math.sin(k))) for k in range(13)]
    ribbon([tuple(p) for p in pts], [1.3 - k * 0.08 for k in range(13)], HX["Ember"], 1.2,
           across=[(0.0, 0.0), (0.3, 0.8), (0.5, 1.0), (0.7, 0.8), (1.0, 0.0)],
           along=[(0.0, 1.0), (0.4, 0.6), (1.0, 0.0)],
           color_stops=[(0.0, HX["Ember"]), (0.5, "FFD27A"), (1.0, HX["Ember"])])
    for k in range(1, 9):
        p = e - d * (0.5 + k * 0.6) + Vector((rnd.uniform(-0.3, 0.3), rnd.uniform(-0.3, 0.3), rnd.uniform(0, 0.5)))
        sprite(p, 1.1 - k * 0.08, HX["Gold"] if k < 3 else HX["Ember"], 1.2)
    point_light(e + Vector((0, 0, 0.3)), "FF9A3C", 450)


def blast(center, radius, seed=3, flames=0):
    """Explosion du joueur (Ember) : flash blanc, boule de feu douce, onde de choc en anneau, sol brûlant,
    étincelles, fumée douce. Disparaît en 0,5 s en jeu."""
    rnd = random.Random(seed)
    cx, cy = center
    disc(center, radius + 0.2, 0.05, "2A1C3D", 0.0, [(0.0, 0.0), (0.9, 0.0), (0.95, 0.5), (1.0, 0.0)], matte=True)
    disc(center, radius, 0.06, HX["Ember"], 1.4,
         [(0.0, 0.0), (0.66, 0.0), (0.8, 0.95), (0.95, 1.0), (1.0, 0.0)],
         color_stops=[(0.0, HX["Ember"]), (0.9, "FF9A3C"), (1.0, HX["Ember"])])
    disc(center, radius * 0.95, 0.04, HX["Ember"], 1.0, [(0.0, 0.5), (0.6, 0.28), (1.0, 0.0)])
    glow_ball((cx, cy, 1.4), 0.9, "FFF2C4", 12.0)
    sprite((cx, cy, 1.5), 4.0, WHITE, 4.0, stops=((0.0, 1.0), (0.3, 0.75), (1.0, 0.0)))
    sprite((cx, cy, 1.6), 7.5, HX["Ember"], 1.15, stops=((0.0, 0.9), (0.45, 0.5), (1.0, 0.0)))
    for k in range(16):
        a = rnd.uniform(0, math.tau)
        d = Vector((math.cos(a), math.sin(a), rnd.uniform(0.3, 1.2))).normalized()
        streak(Vector((cx, cy, 1.2)) + d * rnd.uniform(1.4, radius * 0.75), d, rnd.uniform(0.6, 1.2), 0.08,
               WHITE if k % 3 == 0 else HX["Ember"], 6.0 if k % 3 == 0 else 1.3)
    for k in range(6):
        a = rnd.uniform(0, math.tau)
        rr = rnd.uniform(0.8, radius * 0.5)
        sprite((cx + math.cos(a) * rr, cy + math.sin(a) * rr, rnd.uniform(2.6, 4.2)), rnd.uniform(2.2, 3.0),
               "B8B0A8", 0.25, stops=((0.0, 0.55), (0.5, 0.35), (1.0, 0.0)))
    for k in range(flames):
        a = rnd.uniform(0, math.tau)
        rr = rnd.uniform(0.6, radius * 0.8)
        p = Vector((cx + math.cos(a) * rr, cy + math.sin(a) * rr, 0.45))
        sprite(p, 0.9, HX["Ember"], 1.2, stretch=1.5)
        sprite(p + Vector((0, 0, 0.35)), 0.5, HX["Gold"], 1.3, stretch=1.4)
    point_light((cx, cy, 2.2), "FF8A2A", 1300)


def telegraph(center, radius, progress=0.6, dashes=16):
    """Alerte du joueur : anneau Neon Gold en pointillé (fine ligne sombre dessous pour le sable), disque doré
    qui se remplit jusqu'à l'impact, bord blanc du remplissage."""
    disc(center, radius + 0.15, 0.05, "2A1C3D", 0.0, [(0.0, 0.0), (0.9, 0.0), (0.95, 0.45), (1.0, 0.0)], matte=True)
    disc(center, radius, 0.08, HX["Gold"], 1.5, [(0.0, 0.0), (0.86, 0.0), (0.9, 1.0), (0.97, 1.0), (1.0, 0.0)],
         dashes=dashes)
    disc(center, radius, 0.05, HX["Gold"], 0.9, [(0.0, 0.1), (0.9, 0.08), (1.0, 0.0)])
    r = max(0.3, radius * progress)
    disc(center, r, 0.06, HX["Gold"], 1.0, [(0.0, 0.22), (0.85, 0.3), (1.0, 0.0)])
    disc(center, r, 0.07, WHITE, 3.0, [(0.0, 0.0), (0.88, 0.0), (0.94, 0.95), (1.0, 0.0)])


def danger(center, radius, progress=0.6):
    """Danger ennemi : rouge Tomato, sans Neon (peu lumineux) : bord net, zone translucide, remplissage."""
    disc(center, radius + 0.2, 0.05, "2A1C3D", 0.0, [(0.0, 0.0), (0.9, 0.0), (0.95, 0.5), (1.0, 0.0)], matte=True)
    disc(center, radius, 0.07, HX["Tomato"], 0.25, [(0.0, 0.0), (0.85, 0.0), (0.9, 1.0), (0.98, 1.0), (1.0, 0.0)],
         matte=True)
    disc(center, radius, 0.05, "B8202E", 0.1, [(0.0, 0.4), (0.9, 0.45), (1.0, 0.0)], matte=True)
    disc(center, radius * progress, 0.06, HX["Tomato"], 0.2, [(0.0, 0.6), (0.9, 0.65), (1.0, 0.0)], matte=True)


def enemy_shot(loc, direction):
    """Tir ennemi : boule Tomato mate et lente, courte traînée sombre (pas de Neon)."""
    glow_ball(loc, 0.95, HX["Tomato"], 0.0, matte=True)
    d = Vector(direction).normalized()
    pts = [Vector(loc) - d * (k * 0.55) for k in range(7)]
    ribbon([tuple(p) for p in pts], [1.6 - k * 0.2 for k in range(7)], HX["Tomato"], 0.3,
           across=[(0.0, 0.0), (0.5, 0.6), (1.0, 0.0)], along=[(0.0, 0.7), (1.0, 0.0)])


def bomb_flight(start, target, t=0.55, peak=6.5, seed=5):
    """Bombe en cloche (pièce en pixels tournée vers la caméra), mèche qui crépite, petites bouffées douces."""
    rnd = random.Random(seed)
    s = Vector((start[0], start[1], 3.0))
    e = Vector((target[0], target[1], 0.8))

    def at(u):
        p = s.lerp(e, u)
        p.z += peak * 4 * u * (1 - u)
        return p

    p = at(t)
    root = place_weapon(bomb, p, rot=(0, 0, 0))
    root["face_camera"] = True
    sprite(p + Vector((0.4, 0, 1.0)), 0.9, HX["Gold"], 8.0)
    for k in range(1, 8):
        u = t - k * 0.05
        if u <= 0:
            break
        sprite(at(u) + Vector((rnd.uniform(-0.1, 0.1), 0, 0)), 0.9 - k * 0.07, "D8D0C6", 0.4,
               stops=((0.0, 0.6), (0.5, 0.35), (1.0, 0.0)))
    return root


# =============================================================================================
# Scène : arène calme en gros blocs (A01), gobelins, joueur


def bloom(sc, threshold=0.85, strength=0.7, size=0.6):
    try:
        ng = bpy.data.node_groups.new("A14_Comp", "CompositorNodeTree")
        ng.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
        rl = ng.nodes.new("CompositorNodeRLayers")
        gl = ng.nodes.new("CompositorNodeGlare")
        for value in ("Bloom", "BLOOM"):
            try:
                gl.inputs["Type"].default_value = value
                break
            except Exception:
                continue
        gl.inputs["Threshold"].default_value = threshold
        gl.inputs["Strength"].default_value = strength
        gl.inputs["Size"].default_value = size
        out = ng.nodes.new("NodeGroupOutput")
        ng.links.new(rl.outputs["Image"], gl.inputs["Image"])
        ng.links.new(gl.outputs["Image"], out.inputs[0])
        sc.compositing_node_group = ng
    except Exception as ex:
        print("bloom ignoré :", ex)


def fresh():
    BILLBOARDS.clear()
    return BD.fresh()


def arena(seed=0):
    sc = fresh()
    B.diorama_light(sc, sun_elev=50, sun_az=-35, strength=4.6, world="A9D8F5", world_strength=0.9)
    rnd = random.Random(seed)
    for i in range(-6, 6):
        for j in range(-8, 5):
            cx, cy = i * 8 + 4, j * 8 + 4
            col = "Leaf.d" if rnd.random() < 0.86 else "Leaf"
            if abs(cx + 0.35 * cy) < 5:
                col = "Leather.l"
            S.block(f"Ground_{i}_{j}", (cx, cy, -0.5), (8, 8, 1), col, jitter=0.03)
    for k in range(10):
        cx = rnd.uniform(-40, 40)
        cy = rnd.uniform(-62, -40)
        h = rnd.choice((1, 2, 3))
        S.block(f"Terrace_{k}", (cx, cy, h / 2), (rnd.choice((6, 8, 10)), rnd.choice((6, 8)), h),
                "Leaf" if k % 2 else "Leaf.d", yaw=rnd.uniform(-0.2, 0.2))
    for k in range(9):
        x = rnd.choice((-1, 1)) * rnd.uniform(18, 34)
        y = rnd.uniform(-55, 10)
        if k % 3 == 0:
            S.rock(f"Rock_{k}", (x, y, 0), size=rnd.uniform(2, 3.5), seed=k)
        elif k % 3 == 1:
            S.pine(f"Pine_{k}", (x, y, 0), height=rnd.uniform(12, 16), seed=k)
        else:
            S.bush(f"Bush_{k}", (x, y, 0), size=2.4, seed=k)
    return sc


def ground_split(sc):
    """Sol coupé en deux (herbe, sable) : on teste les couleurs sur les deux."""
    for i in range(-4, 4):
        for j in range(-4, 4):
            cx, cy = i * 8 + 4, j * 8 + 4
            S.block(f"Split_{i}_{j}", (cx, cy, -0.5), (8, 8, 1), "Leaf.d" if cx < 0 else "Leather.l", jitter=0.03)


R_GRIP = Vector((-1.5, 0.125, 2.3))   # main droite du mannequin (studs, pieds à z 0)
HELD_SCALE = 1.7                      # arme tenue un peu surdimensionnée : lisible à la caméra dézoomée
HELD = {                              # face plate du sprite vers la caméra (placée derrière le joueur)
    "sword": Euler((0.25, math.radians(-38), 0)),   # lame levée vers la droite de l écran
    "staff": Euler((0.15, math.radians(-6), 0)),
    "bow": Euler((0.15, math.radians(8), 0)),
}
L_GRIP = Vector((1.5, 0.125, 2.3))


def horde(points, kinds, seed=7, hit=()):
    rnd = random.Random(seed)
    for k, (x, y) in enumerate(points):
        fn = kinds[k % len(kinds)]
        ob = B.place(fn, (x, y, 0), rot_z=math.pi + rnd.uniform(-0.35, 0.35))[0]
        if k in hit:
            ob.rotation_euler.x = -0.24
            ob.location.z = 0.3


def game_camera(sc, player, dist=17.0, height=24.0, look=8.0, side=4.0, lens=30):
    px, py = player
    return B.camera(sc, (px + side, py + dist, height), (px - 1.0, py - look, 0.0), lens=lens)


def face_camera(sc):
    """Particules tournées vers la caméra (comme un ParticleEmitter) ; bombes en vol face à la caméra."""
    cam = sc.camera
    for ob in BILLBOARDS:
        c = ob.constraints.new("TRACK_TO")
        c.target = cam
        c.track_axis = "TRACK_Z"
        c.up_axis = "UP_Y"
    for ob in bpy.context.scene.objects:
        if ob.get("face_camera"):
            d = cam.location - ob.location
            ob.rotation_euler = (0, 0, math.atan2(d.y, d.x) + math.pi / 2)


def render(sc, out, res=(1600, 900), samples=48):
    face_camera(sc)
    bloom(sc)
    sc.view_settings.view_transform = "Standard"
    B.render(sc, out, res=res, samples=samples)
    print("rendu :", out)


# =============================================================================================
# Vues


def view_lineup(out):
    """Les 4 armes et les 2 pièces, de trois quarts : on voit l'épaisseur du pixel art."""
    sc = fresh()
    B.diorama_light(sc, sun_elev=48, sun_az=-35, strength=4.8, world="8FC8F2", world_strength=1.0)
    S.block("Plinth", (0, 0, -0.5), (70, 26, 1), "Stone.l", jitter=0.0)
    stats = {}
    yaw = Euler((0, 0, math.radians(-28)))
    place_weapon(broadsword, (-9.5, 0, 0.95), rot=yaw, stats=stats)
    place_weapon(longbow, (-5.6, 0, 2.05), rot=yaw, stats=stats)
    place_weapon(firestaff, (-1.8, 0, 1.45), rot=yaw, stats=stats)
    place_weapon(bombbag, (2.4, 0, 2.5), rot=yaw, stats=stats)
    place_weapon(bomb, (6.0, 0, 0.8), rot=yaw, stats=stats)
    place_weapon(arrow, (8.8, -1.0, 2.2), rot=Euler((0, math.radians(90), math.radians(-28))), stats=stats)
    B.place(M.mannequin, (12.6, 2.0, 0), rot_z=math.radians(-20))
    B.camera(sc, (1.5, -40, 5.0), (1.5, 0, 2.3), lens=52)
    render(sc, out, res=(2400, 760), samples=64)
    with open(os.path.join(os.path.dirname(out), "tris.json"), "w", encoding="utf-8") as f:
        json.dump(stats, f, indent=1)


def view_swing(out):
    player = (0.0, 6.0)
    hits = [(-5.4, 1.6), (-1.0, -1.2), (3.6, 0.2)]

    def scene(full):
        sc = arena(1)
        BD.dressed("Knight", 3, player[0], y=player[1])
        place_weapon(broadsword, Vector((player[0], player[1], 0)) + R_GRIP, rot=HELD["sword"], scale=HELD_SCALE)
        swing(player, radius=8.0, half=70.0)
        for k, (x, y) in enumerate(hits):
            d = Vector((x - player[0], y - player[1], 0)).normalized()
            hit_spark((x + d.x * 0.2, y + d.y * 0.2, 2.6), d, seed=k)
        pts = list(hits)
        if full:
            pts += [(-9, -12), (-4, -14), (1.5, -13), (7, -12), (-7, -18), (-1, -19), (5, -18), (11, -15),
                    (-13, -6), (13, -5), (-3, -24), (3, -23), (9, -21), (-10, -22)]
        horde(pts, [M.goblin_grunt, M.goblin_grunt, M.goblin_archer, M.goblin_shaman], hit=(0, 1, 2))
        return sc

    sc = scene(False)
    B.camera(sc, (-3.0, -11.0, 15.0), (-0.5, 2.5, 1.0), lens=30)
    render(sc, out.replace(".png", "_hero.png"))
    sc = scene(True)
    game_camera(sc, player, side=9.0)
    render(sc, out.replace(".png", "_game.png"))


def view_fireball(out):
    sc = arena(2)
    BD.dressed("Mage", 3, 0.0, y=8.0)
    place_weapon(firestaff, Vector((0, 8, 0)) + R_GRIP + Vector((0, -0.2, 0.2)), rot=HELD["staff"], scale=HELD_SCALE)
    fireball(start=(0.0, 6.0), end=(0.0, 1.5), seed=2)
    blast((0.0, -8.0), 5.0, seed=4, flames=7)
    horde([(0.0, -8.0), (1.8, -10.2)], [M.goblin_grunt, M.goblin_archer], seed=9, hit=(0, 1))
    B.camera(sc, (18.0, -1.0, 7.0), (0.0, -1.0, 1.6), lens=28)
    render(sc, out.replace(".png", "_hero.png"))
    sc = arena(2)
    player = (2.0, 7.0)
    BD.dressed("Mage", 3, player[0], y=player[1])
    place_weapon(firestaff, Vector((player[0], player[1], 0)) + R_GRIP + Vector((0, -0.2, 0.2)),
                 rot=HELD["staff"], scale=HELD_SCALE)
    fireball(start=(player[0] - 0.5, player[1] - 2), end=(-0.6, -1.5), seed=2)
    blast((-4.5, -9.0), 5.0, seed=4, flames=7)
    pts = [(-4.5, -9.0), (-2.2, -7.8), (-7.0, -10.4), (2, -13), (6, -14), (9, -10), (3, -19),
           (-11, -15), (-10, -21), (7, -21), (-1, -24), (11, -18), (-6, -25)]
    horde(pts, [M.goblin_grunt, M.goblin_archer, M.goblin_grunt, M.goblin_bomber], seed=9, hit=(0, 1, 2))
    game_camera(sc, player)
    render(sc, out.replace(".png", "_game.png"))


def view_bomb(out):
    sc = arena(3)
    BD.dressed("Archer", 3, 4.0, y=8.0)
    place_weapon(longbow, Vector((4, 8, 0)) + L_GRIP + Vector((0.2, -0.2, 0.3)), rot=HELD["bow"], scale=HELD_SCALE)
    telegraph((-2.0, -4.0), 6.0, progress=0.6)
    bomb_flight((4.5, 7.0), (-2.0, -4.0), t=0.74)
    horde([(-1.0, -3.0), (-6.5, -9.5)], [M.goblin_grunt, M.goblin_archer], seed=3)
    B.camera(sc, (14.0, -10.0, 11.0), (-0.5, -2.0, 2.6), lens=28)
    render(sc, out.replace(".png", "_hero.png"))
    sc = arena(3)
    player = (0.0, 7.0)
    BD.dressed("Archer", 3, player[0], y=player[1])
    place_weapon(longbow, Vector((player[0], player[1], 0)) + L_GRIP + Vector((0.2, -0.2, 0.3)),
                 rot=HELD["bow"], scale=HELD_SCALE)
    target = (-5.0, -5.0)
    telegraph(target, 6.0, progress=0.6)
    bomb_flight((player[0] + 0.5, player[1] - 1), target, t=0.55)
    blast((7.0, -10.0), 6.0, seed=8)
    pts = [(-3.4, -7.4), (-7.6, -3.6), (7.0, -10.0), (9.2, -8.4), (5.2, -11.8), (-12, -12),
           (0, -17), (13, -3), (-6, -18), (11, -18), (-2, -23), (5, -22)]
    horde(pts, [M.goblin_grunt, M.goblin_grunt, M.goblin_archer, M.goblin_bomber], seed=11, hit=(2, 3, 4))
    game_camera(sc, player)
    render(sc, out.replace(".png", "_game.png"))


def view_sequence(out):
    """La même bombe en 4 temps : l'alerte se remplit (mouvement), puis le coup flashe et disparaît."""
    frames = [(0.15, 0.3, False), (0.55, 0.62, False), (0.95, 0.94, False), (1.0, 1.0, True)]
    for k, (progress, t, boom) in enumerate(frames):
        sc = fresh()
        B.diorama_light(sc, sun_elev=52, sun_az=-40, strength=4.8, world="A9D8F5", world_strength=0.9)
        ground_split(sc)
        horde([(1.2, 0.8)], [M.goblin_grunt], seed=2, hit=(0,) if boom else ())
        if boom:
            blast((0.0, 0.0), 5.0, seed=21)
        else:
            telegraph((0.0, 0.0), 5.0, progress=progress)
            bomb_flight((9.0, 9.0), (0.0, 0.0), t=t, peak=7.0)
        B.camera(sc, (12.0, -11.0, 11.0), (1.5, 1.5, 2.0), lens=30)
        render(sc, out.replace(".png", f"_{k}.png"), res=(900, 700), samples=32)


def view_dense(out):
    """Test téléphone : une horde dense (70 gobelins) et cinq effets en même temps."""
    rnd = random.Random(42)
    sc = arena(4)
    player = (0.0, 6.0)
    BD.dressed("Knight", 3, player[0], y=player[1])
    place_weapon(broadsword, Vector((player[0], player[1], 0)) + R_GRIP, rot=HELD["sword"], scale=HELD_SCALE)
    swing(player, radius=8.0, half=70.0)
    blast((-8.0, -9.0), 5.0, seed=5, flames=6)
    telegraph((7.0, -6.0), 6.0, progress=0.55)
    bomb_flight((0.5, 5.0), (7.0, -6.0), t=0.6)
    for (x, y) in ((-6.0, -14.0), (5.0, -16.0), (12.0, -10.0)):
        sx, sy = x + (player[0] - x) * 0.45, y + (player[1] - y) * 0.45
        enemy_shot((sx, sy, 2.4), (player[0] - x, player[1] - y, 0))
    pts = []
    while len(pts) < 70:
        x, y = rnd.uniform(-20, 20), rnd.uniform(-30, 1.5)
        if math.hypot(x - player[0], y - player[1]) < 7.0:
            continue
        if any(math.hypot(x - a, y - b) < 1.9 for a, b in pts):
            continue
        pts.append((x, y))
    kinds = [M.goblin_grunt] * 5 + [M.goblin_archer] * 2 + [M.goblin_shaman, M.goblin_bomber]
    horde(pts, kinds, seed=13)
    game_camera(sc, player, dist=19.0, height=27.0, look=9.0, side=6.0, lens=30)
    render(sc, out, res=(1600, 900), samples=48)


def view_legend(out):
    """Le sens au sol, chaque zone à cheval sur l'herbe et le sable."""
    sc = fresh()
    B.diorama_light(sc, sun_elev=52, sun_az=-40, strength=4.8, world="A9D8F5", world_strength=0.9)
    ground_split(sc)
    telegraph((0.0, -12.0), 5.0, progress=0.6)
    blast((0.0, 0.0), 5.0, seed=12)
    danger((0.0, 11.0), 5.0, progress=0.6)                          # l'ennemi vise le joueur
    BD.dressed("Knight", 3, 0.5, y=11.5)
    enemy_shot((1.6, 15.8, 2.4), (-0.25, -1, 0))                    # tiré par le gobelin archer, à droite
    horde([(1.5, -11.0), (-1.0, 1.5), (2.2, 19.5)], [M.goblin_grunt, M.goblin_grunt, M.goblin_archer], seed=5)
    B.camera(sc, (24.0, 0.0, 24.0), (0.0, 0.0, 0.0), lens=34)
    render(sc, out, res=(2400, 800), samples=48)


def view_icons(out):
    """Icônes pour A08 : chaque arme en léger trois-quarts de face, fond transparent, carré de 512 px.
    Écrit <dossier>/icons/<Id>.png (le contour encre de l'interface est posé par A08)."""
    from mathutils import Vector as V

    outdir = os.path.join(os.path.dirname(out), "icons")
    os.makedirs(outdir, exist_ok=True)
    for name in ("Broadsword", "Longbow", "FireStaff", "BombBag"):
        sc = fresh()
        B.diorama_light(sc, sun_elev=40, sun_az=-30, strength=4.0, world="FFFFFF", world_strength=0.8)
        root = place_weapon(SPRITES[name], (0, 0, 0), rot=Euler((math.radians(8), 0, math.radians(-22))))
        bpy.context.view_layer.update()
        pts = []
        for ob in root.children:
            pts += [ob.matrix_world @ V(c) for c in ob.bound_box]
        lo = V((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
        hi = V((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
        mid = (lo + hi) / 2
        size = max(hi.x - lo.x, hi.z - lo.z) * 1.12
        B.camera(sc, (mid.x, mid.y - 30.0, mid.z), (mid.x, mid.y, mid.z), ortho=size)
        sc.view_settings.view_transform = "Standard"
        B.render(sc, os.path.join(outdir, f"{name}.png"), res=(512, 512), transparent=True, samples=32)


def export_sprites(outdir):
    with open(os.path.join(outdir, "sprites.json"), "w", encoding="utf-8") as f:
        json.dump({name: fn().export() for name, fn in SPRITES.items()}, f)


VIEWS = {"lineup": view_lineup, "swing": view_swing, "fireball": view_fireball, "bomb": view_bomb,
         "legend": view_legend, "sequence": view_sequence, "dense": view_dense,
         "icons": view_icons,
         "sprites": lambda out: None}   # sprites.json seulement


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:]
    which, outdir = argv[0], os.path.abspath(argv[1])
    os.makedirs(outdir, exist_ok=True)
    export_sprites(outdir)
    for name in ([v for v in VIEWS if v not in ("sprites", "icons")] if which == "all" else which.split(",")):
        VIEWS[name](os.path.join(outdir, f"a14_{name}.png"))
