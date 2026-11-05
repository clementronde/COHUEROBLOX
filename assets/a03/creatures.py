"""COHUE — A03, ennemis et boss dans la DA du 5 nov. (briques fines à tenons, gros yeux ronds).

Python pur (testable hors de Blender), mêmes conventions que assets/voxel/models.py (A01) :
- unités de cellule ; une cellule = une brique de 1 × 1 et un tenon ;
- Z en haut, le modèle regarde vers -Y, symétrie autour de x = 0 (colonne x <-> -1-x) ;
- la main droite du personnage est côté -X ;
- couleurs : palette COHUE 16 et ses tons (.l, .d, .dd).

Chaque fonction renvoie (Vox, origine, meta). meta["cell"] = taille de la cellule en studs (0,25 pour la horde,
0,5 pour les mini-boss et les boss). meta["eyes"] = les yeux, qui ne sont pas des briques : ce sont les seules
surfaces lisses d'un personnage (guide DA, règle 4), posées en sphères aplaties par concept.py (et en MeshPart
séparée en jeu, sans tenons). Un oeil = dict(c=(x, y, z) en cellules, r=rayon en studs, d=profondeur relative,
look=(dx, dz) direction de la pupille, p=rayon de la pupille relatif, ink=True pour un oeil noir à reflet
blanc (fantômes : un oeil blanc disparaîtrait sur le corps crème), sz=étirement vertical, lid=paupière).

Relecture à l'aveugle du 5 nov. (7,2 et 6 sur 10) : le Grunt faisait lutin de Noël (bord crème), le zombie
cyclope, le fantôme crâne, le boss totem. Corrigé ici : cocotte à lèvre Tomato.d, zombie en Γ à deux yeux
inégaux, fantôme en cloche à bas ondulé et yeux ovales, cercueil à couvercle débordant entrouvert.
"""

from __future__ import annotations

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.append(os.path.join(os.path.dirname(HERE), "voxel"))

from cohue_voxel import Vox  # noqa: E402


def eye(x, y, z, r, look=(0.0, 0.0), p=0.45, d=0.45, ink=False, sz=1.0, lid=0.0):
    """y = None : posé sur la face avant du modèle à cette hauteur (calculé par concept.py).
    sz : étirement vertical (ovale) ; lid : part du haut de l'oeil cachée par une paupière (0 à 1)."""
    return {"c": (x, y, z), "r": r, "look": look, "p": p, "d": d, "ink": ink, "sz": sz, "lid": lid}


def front_paint(v: Vox, x: int, z: int, col: str):
    """Repeint la cellule la plus en avant (y minimal) de la colonne (x, z)."""
    ys = [k[1] for k in v.c if k[0] == x and k[2] == z]
    if ys:
        v.set(x, min(ys), z, col)


def front_y(v: Vox, x: float, z: float) -> float:
    """Plan de la face avant (en cellules) sous un point (x, z), pour poser un oeil."""
    xi, zi = int(x // 1), int(z // 1)
    ys = [k[1] for k in v.c if k[0] == xi and k[2] == zi]
    return float(min(ys)) if ys else 0.0


# =============================================================================================
# Monde 1 : les gobelins, refaits en briques (formes et gags de la v1 d'A01 gardés, tête plus grosse,
# yeux ronds). Silhouette en T : grandes oreilles horizontales. Peau Lime ; le dessus de la tête porte la
# couleur du rôle (la caméra est haute) : rouge mêlée, brun tireur, violet soutien, orange kamikaze.


def goblin_base(name: str, tunic: str, belt: str = "Bark", legs: bool = True) -> Vox:
    v = Vox(name)
    skin = "Lime"
    if legs:
        v.box(1, 2, -2, 0, 0, 0, "Bark")           # chaussures
        v.box(1, 2, -1, 0, 1, 2, skin + ".d")      # jambes courtes
    v.box(0, 2, -2, 1, 3, 6, tunic)                # tunique
    v.box(0, 1, -3, -3, 4, 5, tunic)               # petit ventre
    v.box(0, 2, -2, 1, 3, 3, belt)                 # ceinture
    v.box(3, 4, -1, 0, 4, 5, skin)                 # bras nus, 2 x 2
    v.box(3, 4, -1, 0, 6, 6, tunic)                # manche
    v.box(3, 4, -2, -1, 3, 3, skin + ".d")         # main
    # Tête : 10 cellules de large (2,5 studs), 6 de haut, coins arrondis
    v.box(0, 4, -3, 2, 7, 12, skin)
    for (x, y, z) in ((4, -3, 7), (4, 2, 7), (4, -3, 12), (4, 2, 12)):
        v.carve(x, x, y, y, z, z)
    # Oreilles en pointe horizontales, 4 briques de long, épaisses de 2 : la signature de la famille
    v.box(5, 6, -1, 0, 9, 11, skin)
    v.box(7, 8, -1, 0, 10, 11, skin)
    v.box(5, 6, -1, -1, 10, 10, skin + ".d")       # creux de l'oreille
    # Visage : sourcils froncés au-dessus des yeux ronds, gros nez, bouche à une dent
    v.box(1, 3, -4, -4, 12, 12, skin + ".d")
    v.set(1, -4, 11, skin + ".d")                  # bout intérieur du sourcil, plus bas : l'air fâché
    v.box(0, 0, -5, -4, 8, 9, skin)                # gros nez (2 x 2 après le miroir)
    v.box(0, 2, -3, -3, 7, 7, "Ink")               # bouche
    v.mirror_x()
    v.set(0, -3, 7, "Cream")                       # une seule dent (asymétrie voulue)
    return v


GOBLIN_EYES = [eye(2.4, -3, 10.2, 0.44, look=(-0.4, -0.2)), eye(-2.4, -3, 10.2, 0.44, look=(0.4, -0.2))]


def goblin_grunt():
    v = goblin_base("Enemy_GoblinGrunt", "Tomato")
    # Cocotte retournée en casque : parois droites Tomato, lèvre Tomato.d, anses en acier
    v.box(-6, 5, -4, 3, 13, 13, "Tomato.d")        # lèvre (le bord de la cocotte, posé sur la tête)
    v.box(-5, 4, -3, 2, 14, 15, "Tomato")
    v.box(-8, -7, -1, 0, 14, 15, "Steel")          # anses 2 x 2
    v.box(6, 7, -1, 0, 14, 15, "Steel")
    # Louche en bois brandie (main droite, -X) : manche épais de 2, cuilleron creux de 4 x 4
    for dx in (0, -1):
        for dy in (0, 1):
            v.line((-5 + dx, -2 + dy, 3), (-10 + dx, -2 + dy, 12), "Bark")
    v.box(-14, -11, -4, -1, 12, 13, "Steel")
    v.carve(-13, -12, -3, -2, 13, 13)
    v.box(-13, -12, -3, -2, 12, 12, "Steel.d")
    return v, "bottom", {"kind": "enemy", "cell": 0.25, "eyes": GOBLIN_EYES, "label": "Goblin Grunt",
                         "role": "Mêlée · monde 1"}


def goblin_archer():
    v = goblin_base("Enemy_GoblinArcher", "Leaf.d")
    # Capuche brune (tireur) : le dessus et le dos de la tête, les oreilles passent dessous
    v.box(-5, 4, -3, 2, 13, 14, "Leather")
    v.box(-5, 4, 3, 3, 8, 13, "Leather")
    v.box(-6, -6, -3, 2, 12, 13, "Leather")
    v.box(5, 5, -3, 2, 12, 13, "Leather")
    v.box(-5, 4, -4, -4, 13, 13, "Leather.d")      # bord de la capuche
    v.box(-1, 0, 1, 2, 15, 16, "Leather")          # pointe
    # Grand arc tenu de côté (+X), tourné vers la caméra : une parenthèse qui sort de la silhouette
    for z in range(1, 17):
        x = 7 + round(2.2 * math.sin(math.pi * (z - 1) / 15))
        v.box(x, x + 1, -2, -1, z, z, "Bark")
    v.box(7, 7, -2, -2, 2, 15, "Cream")            # corde
    # Carquois dans le dos, flèches à ventouse rouges qui dépassent de l'épaule
    v.box(-4, -3, 2, 3, 3, 9, "Bark")
    v.box(-4, -4, 2, 2, 10, 12, "Leather.l")
    v.box(-3, -3, 3, 3, 10, 11, "Leather.l")
    v.box(-5, -4, 1, 2, 13, 13, "Tomato")
    v.box(-3, -2, 3, 4, 12, 12, "Tomato")
    return v, "bottom", {"kind": "enemy", "cell": 0.25, "eyes": GOBLIN_EYES, "label": "Goblin Archer",
                         "role": "Tireur · monde 1"}


def goblin_shaman():
    v = goblin_base("Enemy_GoblinShaman", "Grape", belt="Gold", legs=False)
    v.box(-3, 2, -2, 1, 0, 2, "Grape")             # robe jusqu'au sol, évasée
    v.box(-4, 3, -3, 2, 0, 0, "Grape.d")
    # Chapeau-champignon violet à pois crème (rôle soutien) : large, il se lit de haut
    v.box(-7, 6, -5, 4, 13, 13, "Grape.d")
    v.box(-6, 5, -4, 3, 14, 14, "Grape")
    v.box(-4, 3, -3, 2, 15, 15, "Grape")
    for (x, y, z) in ((-6, -3, 14), (4, -2, 14), (-1, 0, 15), (1, 1, 15), (-4, 1, 15)):
        v.box(x, x + 1, y, y + 1, z, z, "Cream")
    # Bâton noueux (main droite, -X) surmonté d'un gland (clin d'oeil à la faune de la forêt)
    v.box(-6, -5, -3, -2, 0, 14, "Bark")
    v.box(-7, -4, -4, -1, 15, 15, "Leather.d")
    v.box(-7, -4, -4, -1, 16, 17, "Leather")
    return v, "bottom", {"kind": "enemy", "cell": 0.25, "eyes": GOBLIN_EYES, "label": "Goblin Shaman",
                         "role": "Soutien · monde 1"}


def goblin_bomber():
    v = goblin_base("Enemy_GoblinBomber", "Ember")
    # Bonnet d'aviateur orange (kamikaze), lunettes remontées sur le front
    v.box(-5, 4, -3, 2, 13, 14, "Ember")
    v.box(-5, 4, -4, -4, 13, 13, "Ember.d")
    v.box(-4, -2, -5, -5, 13, 14, "Steel")
    v.box(1, 3, -5, -5, 13, 14, "Steel")
    v.box(-3, -2, -6, -6, 13, 14, "Steel.l")
    v.box(1, 2, -6, -6, 13, 14, "Steel.l")
    # Grosse bombe tenue à bout de bras (main droite, -X) : un gros rond noir hors de la silhouette
    v.ell(-10, -1, 6.5, 3.4, 3.2, 3.4, "Ink", zmin=3)
    v.paint_if(lambda x, y, z, c: c == "Ink" and z == 6, "Steel.d")
    v.box(-11, -10, -2, -1, 10, 10, "Steel")       # bouchon
    v.box(-11, -10, -2, -1, 11, 12, "Bark")        # mèche
    v.box(-11, -10, -3, -2, 13, 14, "Gold")        # étincelle
    # Sac d'XP volée dans la main gauche (le gag : il vole ton XP)
    v.box(4, 6, -3, -1, 1, 3, "Leather")
    v.box(4, 6, -3, -1, 4, 4, "Sky")
    return v, "bottom", {"kind": "enemy", "cell": 0.25, "eyes": GOBLIN_EYES, "label": "Goblin Bomber",
                         "role": "Kamikaze · monde 1"}


# =============================================================================================
# Monde 2 : Zombie Runner, la ballerine. Silhouette en Γ : buste penché, tête basse en avant, bras tendus
# à l'horizontale. Peau Sky.dd mate, haillons Plum. Noeud Tomato sur le dessus : il frappe au contact.


def zombie_runner():
    v = Vox("Enemy_ZombieRunner")
    skin = "Sky.dd"
    v.box(1, 2, -1, 0, 1, 3, skin)                 # jambes fines
    v.box(1, 2, -2, 0, 0, 0, "Grape.l")            # chaussons de danse
    v.box(0, 2, -1, 1, 3, 4, "Plum")               # short
    # Buste penché en avant, haillons Plum
    v.box(0, 2, -1, 1, 5, 6, "Plum")
    v.box(0, 2, -2, 0, 7, 8, "Plum")
    v.box(0, 2, -3, -1, 9, 9, "Plum")
    # Bras tendus à l'horizontale, 2 x 2, mains qui pendent
    v.box(3, 4, -2, -1, 8, 9, "Plum")
    v.box(3, 4, -9, -3, 8, 9, skin)
    v.box(3, 4, -11, -10, 7, 9, "Sky.d")
    v.mirror_x()
    v.set(-1, 1, 5, skin)                          # accrocs
    v.set(2, -2, 7, skin)
    # Tutu évasé (deux couches) : la ballerine se lit de haut et de face
    v.ell(0, -0.2, 4.5, 5.3, 4.6, 0.6, "Grape.l", zmin=4, zmax=4)
    v.ell(0, -0.2, 5.5, 4.3, 3.7, 0.6, "Grape.l", zmin=5, zmax=5)
    for (x, y) in ((5, 0), (-6, 0), (0, 4), (-1, -5), (3, -4), (-4, 3)):
        v.carve(x, x, y, y, 4, 4)
    # Tête carrée, basse et en avant du buste (Γ de profil)
    v.box(-4, 3, -9, -3, 10, 14, skin)
    v.carve(3, 3, -9, -9, 14, 14)
    v.carve(-4, -4, -9, -9, 14, 14)
    v.box(-2, 1, -10, -10, 10, 11, "Ink")          # bouche ouverte qui gémit
    v.set(1, -10, 11, "Cream")                     # une dent
    # Chignon et noeud de danseuse Tomato sur le dessus
    v.box(-1, 0, -6, -5, 15, 16, "Plum")
    v.box(-4, -2, -6, -5, 15, 16, "Tomato")
    v.box(1, 3, -6, -5, 15, 16, "Tomato")
    eyes = [eye(-1.9, -9, 12.5, 0.52, look=(0.3, 0.3)),                      # gros oeil grand ouvert
            eye(2.1, -9, 12.2, 0.38, look=(-0.3, -0.35), p=0.55, lid=0.45)]   # petit oeil mi-clos
    return v, "bottom", {"kind": "enemy", "cell": 0.25, "eyes": eyes, "label": "Zombie Runner",
                         "role": "Sauteur · monde 2", "skin": "Sky.dd"}


# =============================================================================================
# Monde 3 : Poltergeist. Dôme plein, corps en cloche, bas ondulé ; flotte à 1 stud. Lance ses livres.


def ghost_poltergeist():
    v = Vox("Enemy_Poltergeist")
    body = "Cream"
    v.ell(0, 0, 7.0, 4.5, 4.1, 4.6, body, zmin=7)                # dôme plein
    for z in range(1, 7):                                         # corps en cloche, un peu plus large en bas
        r = 4.5 + (7 - z) * 0.1
        v.ell(0, 0, z + 0.5, r, r * 0.9, 0.6, body, zmin=z, zmax=z)
    for (x, y, z) in list(v.c):                                   # bas ondulé : six pointes tout autour
        if z == 1:
            a = math.atan2(y + 0.5, x + 0.5)
            if math.cos(6 * a) > -0.1:
                v.set(x, y, 0, body + ".d")
    for (x, z) in ((-1, 4), (0, 4), (-1, 5), (0, 5)):
        front_paint(v, x, z, "Plum")                              # petite bouche ronde
    # Bras 2 x 2 : le gauche (+X) levé tient deux livres de classe, le droit s'agite
    v.box(5, 6, -1, 0, 4, 7, body)
    v.box(6, 7, -1, 0, 8, 10, body)
    v.box(-7, -6, -1, 0, 4, 6, body)
    v.box(-8, -7, -1, 0, 7, 8, body)
    v.box(2, 11, -3, 2, 11, 11, "Leaf.d")                         # livre du dessous
    v.box(3, 10, -3, -3, 11, 11, "Cream.d")                       # tranche des pages
    v.box(3, 10, -3, 2, 12, 12, "Cream.d")
    v.box(2, 11, -3, 2, 13, 13, "Leather")                        # livre du dessus : brun, lisible sur l'herbe
    v.box(3, 10, -3, -3, 13, 13, "Cream.d")
    v.box(2, 11, -3, 2, 14, 14, "Leather")
    eyes = [eye(-1.9, None, 8.6, 0.42, d=0.35, ink=True, sz=1.45),
            eye(1.9, None, 8.6, 0.42, d=0.35, ink=True, sz=1.45)]
    return v, "bottom", {"kind": "enemy", "cell": 0.25, "eyes": eyes, "label": "Poltergeist",
                         "role": "Tireur · monde 3", "float": 1.0}


# =============================================================================================
# Boss du monde 2 : The Hungry Coffin. Briques de 0,5 stud. Cercueil debout sur quatre mains de zombie :
# couvercle clair qui déborde, entrouvert en mâchoire sur une doublure capitonnée Plum ; serviette à
# carreaux nouée, fourchette et couteau géants.


def boss_hungry_coffin():
    v = Vox("Boss_HungryCoffin")
    side, lid = "Bark.d", "Leather"
    z0, top, shoulder = 6, 33, 25

    def hw_at(z):
        if z <= shoulder:
            return 3.5 + 3.5 * (z - z0) / (shoulder - z0)
        return 7 - 3 * (z - shoulder) / (top - shoulder)

    for z in range(z0, top + 1):
        w = int(round(hw_at(z)))
        v.box(-w, w - 1, -2, 3, z, z, side)                       # caisse
        v.box(-w - 1, w, -3, -3, z, z, lid)                       # couvercle clair qui déborde d'une brique
    w = int(round(hw_at(top)))
    v.box(-w, w - 1, -2, 3, top, top, lid)                        # le dessus de la couleur du couvercle
    # Bouche : le couvercle s'entrouvre ; dedans, la doublure capitonnée Plum, dents carrées, langue
    v.carve(-6, 5, -3, -1, 15, 21)
    for x in range(-6, 6):
        for z in range(15, 22):
            v.set(x, 0, z, "Plum.l" if (x // 2 + z // 2) % 2 == 0 else "Plum")
    for x in range(-6, 6, 2):
        v.box(x, x, -3, -2, 21, 21, "Cream")                      # dents du haut
        v.box(x + 1, x + 1, -3, -2, 15, 15, "Cream")              # dents du bas
    v.box(-6, 5, -4, -4, 22, 22, lid)                             # lèvre du couvercle, en avant (il s'ouvre)
    v.box(-2, 1, -2, -1, 16, 16, "Tomato")                        # langue
    v.box(-2, 1, -4, -3, 14, 15, "Tomato")
    v.box(-1, 0, -5, -5, 12, 14, "Tomato.d")
    for x in (7, -8):                                             # charnières dorées au coin de la mâchoire
        v.box(x, x, -3, -2, 20, 22, "Gold")
    # Sourcils Ink épais, au-dessus des yeux
    v.box(-6, -2, -4, -4, 29, 30, "Ink")
    v.box(1, 5, -4, -4, 29, 30, "Ink")
    v.box(-2, -2, -4, -4, 28, 28, "Ink")
    v.box(1, 1, -4, -4, 28, 28, "Ink")
    # Serviette à carreaux nouée sous la mâchoire, pointes du noeud qui dépassent sur les côtés
    for i, z in enumerate(range(7, 15)):
        w = min(2 + i, int(round(hw_at(z))))
        for x in range(-w, w):
            edge = x in (-w, w - 1) or z == 14
            v.set(x, -4, z, "Tomato" if edge else "Cream")
    v.box(-8, -7, -2, -1, 14, 15, "Cream")
    v.box(6, 7, -2, -1, 14, 15, "Cream")
    # Poignées dorées 1 x 4 sur les côtés
    for z in (11, 18):
        w = int(round(hw_at(z)))
        v.box(w, w, -1, 2, z, z, "Gold")
        v.box(-w - 1, -w - 1, -1, 2, z, z, "Gold")
    # Quatre mains de zombie en guise de pattes : manchette Plum, trois doigts écartés et un pouce
    for sx in (1, -1):
        for sy in (-1, 1):
            bx = 2 if sx > 0 else -3
            by = -2 if sy < 0 else 2
            for k in range(5):
                z = z0 - 1 - k
                x, y = bx + sx * ((k + 1) // 2), by + sy * ((k + 1) // 2)
                v.box(min(x, x + sx), max(x, x + sx), min(y, y + sy), max(y, y + sy), z, z,
                      "Plum" if k < 2 else "Sky.d")
            hx, hy = bx + sx * 3, by + sy * 3
            v.box(min(hx, hx + 2 * sx), max(hx, hx + 2 * sx), min(hy, hy + 2 * sy), max(hy, hy + 2 * sy), 0, 0,
                  "Sky.d")
            for f in (0, 2):
                v.box(min(hx + 3 * sx, hx + 4 * sx), max(hx + 3 * sx, hx + 4 * sx), hy + sy * f, hy + sy * f, 0, 0,
                      "Sky.d")
            v.box(hx + sx, hx + sx, min(hy + 3 * sy, hy + 4 * sy), max(hy + 3 * sy, hy + 4 * sy), 0, 0, "Sky.d")
    # Bras qui tiennent la fourchette (gauche, +X) et le couteau (droite, -X), manchettes Plum
    v.box(7, 9, 0, 1, 16, 17, "Sky.d")
    v.box(7, 8, 0, 1, 16, 17, "Plum")
    v.box(10, 11, -1, 1, 15, 18, "Sky.d")
    v.box(-10, -8, 0, 1, 16, 17, "Sky.d")
    v.box(-9, -8, 0, 1, 16, 17, "Plum")
    v.box(-12, -11, -1, 1, 15, 18, "Sky.d")
    v.box(11, 11, -2, -2, 10, 27, "Steel")
    v.box(9, 13, -2, -2, 28, 28, "Steel")
    for x in (9, 11, 13):
        v.box(x, x, -2, -2, 29, 32, "Steel.l")
    v.box(-12, -12, -2, -2, 11, 19, "Bark")
    v.box(-13, -11, -2, -2, 20, 20, "Steel.d")
    v.box(-13, -12, -2, -2, 21, 30, "Steel.l")
    v.set(-12, -2, 31, "Steel.l")
    eyes = [eye(3.0, -3, 26.0, 1.3, look=(-0.2, -0.35), p=0.42),
            eye(-3.0, -3, 26.0, 1.3, look=(0.2, -0.35), p=0.42)]
    return v, "bottom", {"kind": "boss", "cell": 0.5, "eyes": eyes, "label": "The Hungry Coffin",
                         "role": "Boss · monde 2"}


ALL = [goblin_grunt, zombie_runner, ghost_poltergeist, boss_hungry_coffin]
GOBLINS = [goblin_grunt, goblin_archer, goblin_shaman, goblin_bomber]


if __name__ == "__main__":
    for fn in ALL + GOBLINS[1:]:
        vox, origin, meta = fn()
        print(f"{vox.name:22s} cellules {len(vox.c):5d}  taille {vox.size_studs(meta['cell'])} studs  "
              f"couleurs {vox.colors_used()}")
