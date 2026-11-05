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
blanc (fantômes : un oeil blanc disparaîtrait sur le corps crème)).
"""

from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.append(os.path.join(os.path.dirname(HERE), "voxel"))

from cohue_voxel import Vox  # noqa: E402


def eye(x, y, z, r, look=(0.0, 0.0), p=0.45, d=0.45, ink=False):
    """y = None : posé sur la face avant du modèle à cette hauteur (calculé par concept.py)."""
    return {"c": (x, y, z), "r": r, "look": look, "p": p, "d": d, "ink": ink}


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
# Monde 1 : Goblin Grunt, refait en briques (formes et gags de la v1 d'A01 gardés, tête plus grosse,
# yeux ronds). Silhouette en T : grandes oreilles horizontales.


def goblin_grunt():
    v = Vox("Enemy_GoblinGrunt")
    skin = "Lime"
    v.box(1, 2, -2, 0, 0, 0, "Bark")               # chaussures, orteils vers l'avant
    v.box(1, 2, -1, 0, 1, 2, skin + ".d")          # jambes courtes
    v.box(0, 2, -2, 1, 3, 6, "Tomato")             # tunique (rôle mêlée)
    v.box(0, 1, -3, -3, 4, 5, "Tomato")            # petit ventre
    v.box(0, 2, -2, 1, 3, 3, "Leather")            # ceinture
    v.set(0, -3, 3, "Gold")                        # boucle
    v.box(3, 3, -1, 0, 4, 5, skin)                 # bras nus
    v.box(3, 3, -1, 0, 6, 6, "Tomato")             # manche
    v.box(3, 4, -2, -1, 3, 3, skin + ".d")         # main
    # Tête : 10 cellules de large (2,5 studs), 6 de haut, coins arrondis
    v.box(0, 4, -3, 2, 7, 12, skin)
    for (x, y, z) in ((4, -3, 7), (4, 2, 7), (4, -3, 12), (4, 2, 12), (3, -3, 12)):
        v.carve(x, x, y, y, z, z)
    # Oreilles en pointe horizontales : la signature de la famille
    v.box(5, 5, -1, 0, 9, 11, skin)
    v.box(6, 6, -1, 0, 10, 11, skin)
    v.box(7, 7, -1, -1, 10, 11, skin)
    v.box(8, 8, -1, -1, 11, 11, skin)
    v.box(5, 6, -1, -1, 10, 10, skin + ".d")       # creux de l'oreille
    # Visage : sourcils froncés au-dessus des yeux ronds, gros nez, bouche à une dent
    v.box(1, 3, -4, -4, 12, 12, skin + ".d")
    v.set(1, -4, 11, skin + ".d")                  # bout intérieur du sourcil, plus bas : l'air fâché
    v.box(0, 0, -4, -5, 8, 9, skin)                # gros nez (2 cellules de large après le miroir)
    v.box(0, 2, -3, -3, 7, 7, "Ink")               # bouche
    v.mirror_x()
    v.set(0, -3, 7, "Cream")                       # une seule dent (asymétrie voulue)
    # Cocotte retournée en casque : le dessus porte le rouge du rôle (la caméra voit surtout le dessus)
    v.box(-6, 5, -4, 3, 13, 13, "Cream")           # bord émaillé
    v.box(-5, 4, -3, 2, 14, 15, "Tomato")
    v.box(-1, 0, -1, 0, 16, 16, "Tomato.d")        # bouton du couvercle
    v.box(-8, -7, -1, 0, 14, 14, "Ink")            # poignées
    v.box(6, 7, -1, 0, 14, 14, "Ink")
    # Louche en bois brandie (main droite, -X) : elle sort de la silhouette au-dessus de l'oreille
    v.line((-5, -2, 3), (-10, -2, 12), "Bark")
    v.box(-12, -10, -3, -1, 13, 14, "Steel")
    v.set(-11, -2, 14, "Steel.d")
    eyes = [eye(2.4, -3, 10.2, 0.44, look=(-0.4, -0.2)), eye(-2.4, -3, 10.2, 0.44, look=(0.4, -0.2))]
    return v, "bottom", {"kind": "enemy", "cell": 0.25, "eyes": eyes, "label": "Goblin Grunt",
                         "role": "Mêlée · monde 1"}


# =============================================================================================
# Monde 2 : Zombie Runner, la ballerine. Silhouette en Γ : bras tendus devant, tête basse en avant.


def zombie_runner():
    v = Vox("Enemy_ZombieRunner")
    skin = "Sky.d"
    # Jambes fines et chaussons de danse
    v.box(1, 2, -1, 0, 1, 3, skin)
    v.box(1, 2, -2, 0, 0, 0, "Grape.l")
    v.set(1, -2, 1, "Grape.l")                     # ruban du chausson
    # Short et tutu évasé (deux couches) : rond et clair, il se lit de haut
    v.box(0, 2, -1, 1, 3, 4, "Plum")
    # Débardeur en lambeaux, buste voûté en avant
    v.box(0, 2, -1, 1, 6, 7, "Leaf.d")
    v.box(0, 2, -2, 0, 8, 9, "Leaf.d")
    # Bras tendus devant, qui s'écartent un peu (V vu de face) : la signature de la famille
    v.box(3, 4, -1, 0, 8, 9, "Leaf.d")
    v.box(3, 4, -4, -2, 8, 9, skin)
    v.box(4, 5, -7, -5, 8, 9, skin)
    v.box(5, 7, -9, -8, 7, 9, "Sky.dd")            # mains qui pendent
    v.set(6, -10, 7, "Sky.dd")
    v.mirror_x()
    v.ell(0, -0.2, 4.5, 5.3, 4.6, 0.6, "Grape.l", zmin=4, zmax=4)
    v.ell(0, -0.2, 5.5, 4.3, 3.7, 0.6, "Grape.l", zmin=5, zmax=5)
    for (x, y) in ((5, 0), (-6, 0), (0, 4), (-1, -5), (3, -4), (-4, 3)):
        v.carve(x, x, y, y, 4, 4)                  # bord festonné
    v.set(-3, 1, 6, skin)                          # accrocs
    v.set(2, -1, 7, skin)
    # Tête haute, qui penche d'un côté ; mâchoire qui pend ; un oeil rond, l'autre cousu en X
    v.box(-4, 3, -7, -1, 10, 13, skin)
    v.box(-5, 2, -7, -1, 14, 15, skin)
    v.box(-2, 1, -8, -8, 9, 9, skin)               # menton tombé en avant
    v.box(-2, 1, -7, -7, 10, 11, "Ink")            # bouche ouverte
    v.set(1, -7, 11, "Cream")                      # une dent
    for (x, z) in ((1, 12), (3, 12), (2, 13), (1, 14), (3, 14)):
        v.set(x, -8, z, "Ink")                     # oeil cousu
    v.box(-5, -4, -7, -6, 15, 15, "Ink")           # points de suture sur le crâne
    # Chignon Plum et noeud de danseuse Grape.l : le gag se lit de haut
    v.box(-2, -1, -4, -3, 16, 17, "Plum")
    v.box(-4, -3, -4, -3, 16, 16, "Grape.l")
    v.box(0, 1, -4, -3, 16, 16, "Grape.l")
    v.set(-4, -4, 17, "Grape.l")
    v.set(1, -4, 17, "Grape.l")
    eyes = [eye(-2.2, -7, 13.2, 0.56, look=(0.35, 0.3))]           # le gros oeil rond, pupille en l'air
    return v, "bottom", {"kind": "enemy", "cell": 0.25, "eyes": eyes, "label": "Zombie Runner",
                         "role": "Sauteur · monde 2"}


# =============================================================================================
# Monde 3 : Poltergeist. Dôme et bas ondulé, flotte ; lance des objets d'école.


def ghost_poltergeist():
    v = Vox("Enemy_Poltergeist")
    body = "Cream"
    v.ell(0, 0, 6.0, 4.6, 4.2, 4.4, body, zmin=6)                # dôme
    for z in range(1, 6):                                         # corps en goutte : il se resserre vers le bas
        r = 2.0 + (z - 1) * 0.65
        v.ell(0, 0, z + 0.5, r, r * 0.92, 0.6, body, zmin=z, zmax=z)
    v.box(-3, -2, -1, 0, 0, 0, body)                              # queue qui s'enroule sur le côté
    v.box(-4, -4, -1, 0, 1, 1, body)
    v.set(-5, -1, 2, body + ".d")
    for (x, z) in ((-1, 2), (0, 2), (-2, 3), (1, 3), (-2, 4), (1, 4), (-1, 5), (0, 5), (-1, 3), (0, 3),
                   (-1, 4), (0, 4)):
        front_paint(v, x, z, "Ink")                               # bouche en O (« bouh »)
    # Bras gauche (+X) levé en biais qui tient une pile de livres sur le côté, prête à être lancée ;
    # bras droit (-X) qui s'agite. Le dôme reste entier dans la silhouette.
    v.box(5, 5, -1, 0, 4, 6, body)
    v.box(6, 6, -1, 0, 7, 8, body)
    v.box(7, 7, -1, 0, 9, 10, body)
    v.box(-6, -6, -1, 0, 4, 6, body)
    v.box(-7, -7, -1, 0, 7, 8, body)
    v.box(3, 10, -2, 1, 11, 11, "Plum")                           # livres : le dessus est vert (rôle « tireur »)
    v.box(4, 9, -2, -2, 11, 11, "Cream")
    v.box(4, 10, -1, 2, 12, 12, "Leather")
    v.box(5, 9, -2, -2, 12, 12, "Cream")
    v.box(3, 9, -2, 1, 13, 13, "Leaf.d")
    v.box(4, 8, -3, -3, 13, 13, "Cream")
    v.set(6, 0, 14, "Gold")                                       # marque-page
    eyes = [eye(-2.2, None, 7.6, 0.5, d=0.35, ink=True), eye(2.2, None, 7.6, 0.5, d=0.35, ink=True)]
    return v, "bottom", {"kind": "enemy", "cell": 0.25, "eyes": eyes, "label": "Poltergeist",
                         "role": "Tireur · monde 3", "float": 1.0}


# =============================================================================================
# Boss du monde 2 : The Hungry Coffin. Briques de 0,5 stud. Cercueil debout sur quatre mains de zombie,
# couvercle en mâchoire, serviette nouée, fourchette et couteau géants.


def boss_hungry_coffin():
    v = Vox("Boss_HungryCoffin")
    wood, lid, trim = "Bark", "Leather", "Bark.d"
    z0, top, shoulder = 6, 33, 26
    # Cercueil hexagonal (vu de face) : 8 cellules de large en bas, 12 aux épaules, 9 en haut
    for z in range(z0, top + 1):
        if z <= shoulder:                                         # forme de cercueil bien marquée :
            hw = 3.5 + 3.5 * (z - z0) / (shoulder - z0)           # étroit aux pieds, large aux épaules,
        else:
            hw = 7 - 3 * (z - shoulder) / (top - shoulder)        # puis le haut qui se resserre
        w = int(round(hw))
        v.box(-w, w - 1, -2, 3, z, z, wood)                       # caisse
        v.box(-w, w - 1, -3, -3, z, z, lid)                       # couvercle
        v.set(-w, -3, z, trim)
        v.set(w - 1, -3, z, trim)
        v.set(-w, 4, z, trim)
        v.set(w - 1, 4, z, trim)
    v.box(-4, 3, -3, 4, top + 1, top + 1, trim)                   # chapeau du cercueil
    v.box(-4, 3, -3, 4, z0 - 1, z0 - 1, trim)
    # Bouche ouverte : intérieur sombre, dents carrées en haut et en bas, langue qui pend
    v.carve(-5, 4, -3, -2, 15, 21)
    v.box(-5, 4, -1, -1, 15, 21, "Plum.dd")
    for x in range(-5, 5):
        if x % 2 == 0:
            v.set(x, -3, 21, "Cream")
            v.set(x, -2, 21, "Cream")
        else:
            v.set(x, -3, 15, "Cream")
            v.set(x, -2, 15, "Cream")
    v.box(-2, 1, -2, -1, 16, 16, "Tomato")                        # langue qui pend par-dessus la lèvre
    v.box(-2, 1, -4, -4, 13, 15, "Tomato")
    v.box(-1, 0, -5, -5, 12, 13, "Tomato.d")
    # Serviette nouée sous la mâchoire (le gag : il a faim), en pointe vers le bas
    for i, z in enumerate(range(6, 13)):
        hw = min(1 + i, int(round(3.5 + 3.5 * (z - z0) / (shoulder - z0))))
        v.box(-hw, hw - 1, -4, -4, z, z, "Cream")
    v.box(-5, 4, -4, -4, 12, 12, "Cream.d")
    # Sourcils en planches, au-dessus des yeux
    v.box(-5, -2, -4, -4, 30, 30, trim)
    v.box(1, 4, -4, -4, 30, 30, trim)
    v.set(-2, -4, 29, trim)
    v.set(1, -4, 29, trim)
    # Poignées dorées sur les côtés, mousse sur les épaules, bouquet fané sur la tête
    for z in (12, 19, 26):
        w = int(round(3.5 + 3.5 * (z - z0) / (shoulder - z0)))
        v.box(w, w, 0, 1, z, z, "Gold")
        v.box(-w - 1, -w - 1, 0, 1, z, z, "Gold")
    v.box(-6, -4, -2, 2, 27, 27, "Leaf.d")
    v.box(4, 5, 0, 3, 28, 28, "Leaf.d")
    v.box(-1, 0, 0, 1, top + 2, top + 3, "Leaf.d")
    v.box(-2, 1, 0, 1, top + 4, top + 4, "Grape")
    v.set(1, 0, top + 5, "Grape.l")
    v.set(-2, 1, top + 5, "Cream")
    # Quatre mains de zombie en guise de pattes (Sky.d, manches Plum en haillons)
    for sx in (1, -1):
        for sy in (-1, 1):
            bx = 2 if sx > 0 else -3                              # départ du bras sous le cercueil
            by = -2 if sy < 0 else 2
            for k in range(5):                                    # bras 2 x 2 qui descend en s'écartant
                z = z0 - 1 - k
                x, y = bx + sx * ((k + 1) // 2), by + sy * ((k + 1) // 2)
                v.box(min(x, x + sx), max(x, x + sx), min(y, y + sy), max(y, y + sy), z, z,
                      "Plum" if k == 0 else "Sky.d")
            hx, hy = bx + sx * 3, by + sy * 3                     # paume à plat sur le sol
            v.box(min(hx, hx + 2 * sx), max(hx, hx + 2 * sx), min(hy, hy + 2 * sy), max(hy, hy + 2 * sy), 0, 0,
                  "Sky.d")
            for f in range(3):                                    # trois doigts vers l'extérieur
                v.set(hx + 3 * sx, hy + sy * f, 0, "Sky.d")
            v.set(hx + sx * f, hy + 3 * sy, 0, "Sky.d")           # pouce
    # Bras qui tiennent la fourchette (gauche, +X) et le couteau (droite, -X)
    v.box(6, 9, 0, 1, 16, 17, "Sky.d")
    v.box(6, 7, 0, 1, 16, 17, "Plum")
    v.box(10, 11, -1, 1, 15, 18, "Sky.d")
    v.box(-10, -7, 0, 1, 16, 17, "Sky.d")
    v.box(-8, -7, 0, 1, 16, 17, "Plum")
    v.box(-12, -11, -1, 1, 15, 18, "Sky.d")
    v.box(11, 11, -2, -2, 10, 27, "Steel")                        # manche de la fourchette
    v.box(10, 12, -2, -2, 28, 28, "Steel")
    for x in (9, 11, 13):
        v.box(x, x, -2, -2, 29, 32, "Steel.l")
    v.box(9, 13, -2, -2, 28, 28, "Steel")
    v.box(-12, -12, -2, -2, 11, 19, "Bark")                       # manche du couteau
    v.box(-13, -11, -2, -2, 20, 20, "Steel.d")
    v.box(-13, -12, -2, -2, 21, 30, "Steel.l")
    v.set(-12, -2, 31, "Steel.l")
    eyes = [eye(2.9, -3, 26.6, 1.25, look=(-0.2, -0.35), p=0.42), eye(-2.9, -3, 26.6, 1.25, look=(0.2, -0.35), p=0.42)]
    return v, "bottom", {"kind": "boss", "cell": 0.5, "eyes": eyes, "label": "The Hungry Coffin",
                         "role": "Boss · monde 2"}


ALL = [goblin_grunt, zombie_runner, ghost_poltergeist, boss_hungry_coffin]


if __name__ == "__main__":
    for fn in ALL:
        vox, origin, meta = fn()
        print(f"{vox.name:22s} cellules {len(vox.c):5d}  taille {vox.size_studs(meta['cell'])} studs  "
              f"couleurs {vox.colors_used()}")
