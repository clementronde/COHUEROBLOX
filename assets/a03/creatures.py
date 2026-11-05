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

Relectures à l'aveugle du 5 nov. :
- tour 1 (7,2 et 6) : Grunt en lutin de Noël, zombie cyclope, fantôme crâne, boss totem ;
- tour 2 (7,1 et 7,0) : ressemblances avec des personnages connus (chapeau-champignon à pois du Shaman, tête
  brune à sourcils noirs du boss, zombie bleu aux yeux globuleux), « moustache » du Grunt, Archer brun confondu
  avec le Bomber orange, chapeaux tous plats, sac d'XP en cupcake, livres en sandwich.
Tour 3 (ce fichier) : cocotte haute à couvercle et louche en bois, bouche ouverte à dents ; capuche verte à
pointe ; théière violette ; zombie vert éteint ; trois livres décalés ; cercueil en bois clair dont le couvercle
soulevé laisse voir deux yeux dans le noir.
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
# couleur du rôle (la caméra est haute) : rouge mêlée, vert tireur, violet soutien, orange kamikaze, chacun
# avec une forme de chapeau différente vue de dessus (cocotte, capuche à pointe, théière, bonnet à lunettes).


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
    # Visage : sourcils froncés, gros nez entre les yeux, bouche ouverte sur deux rangées (pas une barre
    # noire sous le nez : elle faisait moustache)
    v.box(1, 3, -4, -4, 12, 12, skin + ".d")
    v.set(1, -4, 11, skin + ".d")                  # bout intérieur du sourcil, plus bas : l'air fâché
    v.box(0, 0, -5, -4, 9, 10, skin)               # gros nez (2 x 2 après le miroir)
    v.box(0, 1, -3, -3, 7, 8, "Plum.dd")           # bouche ouverte
    v.mirror_x()
    v.set(-2, -3, 8, "Cream")                      # deux dents du haut, de travers
    v.set(1, -3, 8, "Cream")
    v.box(-1, 0, -3, -3, 7, 7, "Tomato.d")         # langue
    return v


GOBLIN_EYES = [eye(2.6, -3, 10.5, 0.42, look=(-0.4, -0.2)), eye(-2.6, -3, 10.5, 0.42, look=(0.4, -0.2))]


def goblin_grunt():
    v = goblin_base("Enemy_GoblinGrunt", "Tomato")
    # Cocotte posée sur la tête, couvercle et bouton : parois Tomato, rebord Tomato.d, anses Ink à mi-hauteur
    v.box(-5, 4, -3, 2, 13, 15, "Tomato")
    v.box(-6, 5, -4, 3, 15, 15, "Tomato.d")        # rebord
    v.box(-4, 3, -2, 1, 16, 16, "Tomato.l")        # couvercle
    v.box(-1, 0, -1, 0, 17, 17, "Ink")             # bouton 2 x 2
    v.box(5, 6, -1, 0, 13, 14, "Ink")              # anses, collées aux parois
    v.box(-7, -6, -1, 0, 13, 14, "Ink")
    # Louche en bois tenue droite (main droite, -X) : le manche monte, se recourbe vers l'extérieur, et le
    # cuilleron rond pend au bout (vue de face, une forme en crosse : ni marteau ni arc)
    v.box(-8, -5, -1, 0, 4, 5, "Lime")             # bras tendu sur le côté
    v.box(-10, -9, -2, -1, 3, 6, "Lime.d")         # main
    v.box(-12, -11, -2, -1, 2, 14, "Bark")         # manche droit
    v.box(-14, -13, -2, -1, 15, 16, "Bark")        # crosse
    v.box(-12, -11, -2, -1, 15, 15, "Bark")
    v.ell(-15.5, -1.0, 12.0, 2.6, 2.6, 2.4, "Leather", zmin=10, zmax=14)   # cuilleron rond, sous la crosse
    v.carve(-17, -14, -3, 1, 14, 14)               # creux du cuilleron
    v.box(-17, -14, -3, 0, 13, 13, "Leather.d")
    return v, "bottom", {"kind": "enemy", "cell": 0.25, "eyes": GOBLIN_EYES, "label": "Goblin Grunt",
                         "role": "Mêlée · monde 1"}


def goblin_archer():
    v = goblin_base("Enemy_GoblinArcher", "Leather")
    # Capuche verte (tireur) : le dessus et le dos de la tête, pointe qui tombe dans le dos
    v.box(-5, 4, -3, 2, 13, 14, "Leaf.d")
    v.box(-5, 4, 3, 3, 8, 13, "Leaf.d")
    v.box(-6, -6, -3, 2, 12, 13, "Leaf.d")
    v.box(5, 5, -3, 2, 12, 13, "Leaf.d")
    v.box(-5, 4, -4, -4, 13, 13, "Leaf.dd")        # bord de la capuche
    v.box(-1, 0, 4, 4, 9, 13, "Leaf.d")            # pointe qui tombe dans le dos
    v.box(-1, 0, 5, 5, 6, 9, "Leaf.d")
    v.box(-1, 0, 6, 6, 5, 6, "Leaf.dd")
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
    # Théière violette en guise de chapeau (soutien) : panse ronde, couvercle, bec et anse
    v.ell(0, -0.5, 13.0, 5.0, 4.3, 3.0, "Grape", zmin=13, zmax=15)
    v.box(-2, 1, -2, 1, 16, 16, "Grape.l")         # couvercle
    v.box(-1, 0, -1, 0, 17, 17, "Grape.d")         # bouton
    v.box(5, 6, -2, -1, 14, 14, "Grape")           # bec vers l'avant et le côté
    v.box(7, 8, -3, -2, 15, 15, "Grape")
    v.box(8, 9, -3, -2, 16, 16, "Grape.d")
    v.box(-6, -6, -1, 0, 13, 13, "Grape.d")        # anse, collée à la panse
    v.box(-6, -6, -1, 0, 15, 15, "Grape.d")
    v.box(-8, -7, -1, 0, 13, 15, "Grape.d")
    # Bâton de berger en bois, la crosse enroulée vers l'extérieur (main droite, -X)
    v.box(-9, -6, -2, -1, 4, 5, "Lime")            # bras tendu
    v.box(-11, -10, -3, -2, 0, 13, "Bark")
    v.box(-13, -12, -3, -2, 14, 15, "Bark")
    v.box(-11, -10, -3, -2, 14, 14, "Bark")
    v.box(-15, -14, -3, -2, 11, 14, "Bark")
    return v, "bottom", {"kind": "enemy", "cell": 0.25, "eyes": GOBLIN_EYES, "label": "Goblin Shaman",
                         "role": "Soutien · monde 1"}


def goblin_bomber():
    v = goblin_base("Enemy_GoblinBomber", "Ember")
    # Bonnet d'aviateur orange (kamikaze), lunettes noires remontées sur le front
    v.box(-5, 4, -3, 2, 13, 14, "Ember")
    v.box(-5, 4, -4, -4, 13, 13, "Ember.d")
    v.box(-4, -1, -5, -5, 13, 14, "Bark.d")
    v.box(0, 3, -5, -5, 13, 14, "Bark.d")
    v.box(-3, -2, -6, -6, 13, 14, "Ink")
    v.box(1, 2, -6, -6, 13, 14, "Ink")
    v.box(-6, -6, -1, 0, 10, 12, "Ember.d")        # rabats sur les oreilles
    v.box(5, 5, -1, 0, 10, 12, "Ember.d")
    # Grosse bombe tenue à bout de bras (main droite, -X) : un gros rond noir hors de la silhouette
    v.ell(-10, -1, 6.5, 3.4, 3.2, 3.4, "Ink", zmin=3)
    v.paint_if(lambda x, y, z, c: c == "Ink" and z == 6, "Steel.d")
    v.box(-11, -10, -2, -1, 10, 10, "Steel")       # bouchon
    v.box(-11, -10, -2, -1, 11, 12, "Bark")        # mèche
    v.box(-11, -10, -3, -2, 13, 14, "Gold")        # étincelle
    return v, "bottom", {"kind": "enemy", "cell": 0.25, "eyes": GOBLIN_EYES, "label": "Goblin Bomber",
                         "role": "Kamikaze · monde 1"}


# =============================================================================================
# Monde 2 : Zombie Runner, la ballerine. Silhouette en Γ : buste voûté, tête basse et en avant, bras tendus à
# l'horizontale, genoux pliés. Peau vert éteint (Leaf.d), haillons Plum. Noeud Tomato sur le dessus.


def zombie_runner():
    v = Vox("Enemy_ZombieRunner")
    skin = "Leaf.d"
    v.box(1, 2, -2, 0, 0, 0, "Grape.l")            # chaussons de danse
    v.box(1, 2, 0, 1, 1, 1, skin)                  # mollets en arrière
    v.box(1, 2, -1, 0, 2, 3, skin)                 # genoux pliés en avant
    v.box(0, 2, -1, 1, 4, 4, "Plum")               # short
    # Buste voûté, haillons Plum déchirés
    v.box(0, 2, -1, 1, 5, 6, "Plum")
    v.box(0, 2, -2, 0, 7, 8, "Plum")
    v.box(0, 2, -3, -1, 9, 9, "Plum")
    v.set(2, 1, 5, skin)                           # accrocs
    v.set(1, -2, 7, skin)
    # Bras tendus à l'horizontale, 2 x 2, sur 7 briques ; mains qui pendent
    v.box(3, 4, -2, -1, 8, 9, "Plum")
    v.box(3, 4, -9, -3, 8, 9, skin)
    v.box(3, 4, -11, -10, 7, 9, "Leaf.dd")
    v.mirror_x()
    # Tutu évasé (deux couches) : la ballerine se lit de haut et de face
    v.ell(0, -0.2, 4.5, 5.3, 4.6, 0.6, "Grape.l", zmin=4, zmax=4)
    v.ell(0, -0.2, 5.5, 4.3, 3.7, 0.6, "Grape.l", zmin=5, zmax=5)
    for (x, y) in ((5, 0), (-6, 0), (0, 4), (-1, -5), (3, -4), (-4, 3)):
        v.carve(x, x, y, y, 4, 4)
    # Tête plus petite, basse et en avant du buste (Γ de profil)
    v.box(-3, 2, -9, -4, 10, 14, skin)
    v.carve(2, 2, -9, -9, 14, 14)
    v.carve(-3, -3, -9, -9, 14, 14)
    v.box(-2, 1, -10, -10, 10, 11, "Plum.dd")      # bouche qui pend, ouverte
    v.set(1, -10, 11, "Cream")                     # une dent
    v.box(-2, 1, -10, -10, 9, 9, skin)             # menton tombé
    # Chignon et noeud de danseuse Tomato sur le dessus
    v.box(-1, 0, -7, -6, 15, 16, "Plum")
    v.box(-4, -2, -7, -6, 15, 16, "Tomato")
    v.box(1, 3, -7, -6, 15, 16, "Tomato")
    eyes = [eye(-1.5, -9, 12.7, 0.46, look=(0.3, 0.3)),                      # oeil grand ouvert
            eye(1.6, -9, 12.4, 0.36, look=(-0.3, -0.35), p=0.55, lid=0.5)]    # oeil mi-clos
    return v, "bottom", {"kind": "enemy", "cell": 0.25, "eyes": eyes, "label": "Zombie Runner",
                         "role": "Sauteur · monde 2", "skin": "Leaf.d"}


# =============================================================================================
# Monde 3 : Poltergeist. Dôme plein, corps en cloche, bas ondulé ; flotte à 1 stud. Lance ses livres.


def _book(v: Vox, x0, x1, y0, y1, z, cover):
    v.box(x0, x1, y0, y1, z, z, "Cream")                          # pages
    v.box(x0, x0, y0, y1, z, z, cover + ".d")                     # dos du livre
    v.box(x0, x1, y0, y1, z + 1, z + 1, cover)                    # couverture


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
        front_paint(v, x, z, "Ink")                               # petite bouche ronde (« bouh »)
    # Bras 2 x 2 : le gauche (+X) levé porte trois livres décalés, le droit s'agite
    v.box(5, 6, -1, 0, 4, 6, body)
    v.box(6, 7, -1, 0, 7, 8, body)
    v.box(-7, -6, -1, 0, 4, 6, body)
    v.box(-8, -7, -1, 0, 7, 8, body)
    _book(v, 3, 11, -3, 2, 9, "Plum")
    _book(v, 4, 12, -3, 2, 11, "Bark")
    _book(v, 2, 10, -3, 2, 13, "Leather")                         # le dessus est brun (tireur), lisible sur l'herbe
    eyes = [eye(-1.9, None, 8.6, 0.42, d=0.35, ink=True, sz=1.45),
            eye(1.9, None, 8.6, 0.42, d=0.35, ink=True, sz=1.45)]
    return v, "bottom", {"kind": "enemy", "cell": 0.25, "eyes": eyes, "label": "Poltergeist",
                         "role": "Tireur · monde 3", "float": 1.0}


# =============================================================================================
# Boss du monde 2 : The Hungry Coffin. Briques de 0,5 stud. Cercueil en bois clair, debout sur quatre mains de
# zombie. Le haut du couvercle est soulevé : dans le noir, deux gros yeux blancs, des dents sur les bords, une
# langue qui pend sur la serviette à carreaux. Fourchette et couteau. Pas de visage peint sur le bois.


def boss_hungry_coffin():
    v = Vox("Boss_HungryCoffin")
    side, lid, rim = "Leather.d", "Leather", "Leather.l"
    z0, top, shoulder = 6, 33, 26

    def hw_at(z):
        if z <= shoulder:
            return 3.5 + 3.5 * (z - z0) / (shoulder - z0)
        return 7 - 3 * (z - shoulder) / (top - shoulder)

    for z in range(z0, top + 1):
        w = int(round(hw_at(z)))
        v.box(-w, w - 1, -2, 3, z, z, side)                       # caisse
        v.box(-w, w - 1, -3, -3, z, z, lid)                       # couvercle
        v.set(-w, -3, z, rim)                                     # liseré clair du couvercle
        v.set(w - 1, -3, z, rim)
    w = int(round(hw_at(top)))
    v.box(-w, w - 1, -3, 3, top, top, rim)                        # sommet plat
    v.box(-3, 2, -3, -3, z0, z0, rim)                             # pied
    # Le haut du couvercle est soulevé et avancé (mâchoire du haut) ; dessous, l'intérieur sombre
    v.carve(-6, 5, -3, -1, 17, 28)
    for x in range(-6, 6):
        for z in range(17, 29):
            v.set(x, 0, z, "Plum.dd")                             # fond du cercueil, dans le noir
    for z in range(17, 29):
        v.set(-6, -1, z, "Plum.d")
        v.set(5, -1, z, "Plum.d")
    for z in range(29, top + 1):
        w = int(round(hw_at(z)))
        v.carve(-w, w - 1, -3, -3, z, z)
        v.box(-w, w - 1, -5, -4, z, z, lid)                       # couvercle soulevé, en avant
        v.set(-w, -5, z, rim)
        v.set(w - 1, -5, z, rim)
    for x in range(-6, 6, 2):
        v.box(x, x, -5, -4, 28, 28, "Cream")                      # dents du haut, sous le couvercle
        v.box(x + 1, x + 1, -3, -2, 17, 17, "Cream")              # dents du bas, sur le bord de la caisse
    v.box(-2, 1, -2, -1, 17, 17, "Tomato")                        # langue qui pend par-dessus le bord
    v.box(-2, 1, -4, -3, 14, 17, "Tomato")
    v.box(-1, 0, -5, -5, 12, 14, "Tomato.d")
    # Serviette Cream à carreaux Tomato de 2 x 2, en pointe, nouée sous la mâchoire
    for i, z in enumerate(range(7, 16)):
        wn = min(1 + i, int(round(hw_at(z))))
        for x in range(-wn, wn):
            check = ((x + 8) // 2 + z // 2) % 2 == 0
            v.set(x, -4, z, "Tomato" if check else "Cream")
    v.box(-8, -7, -2, -1, 15, 16, "Cream")                        # pointes du noeud sur les côtés
    v.box(6, 7, -2, -1, 15, 16, "Cream")
    # Poignées Steel 1 x 4 sur les flancs
    for z in (11, 20):
        w = int(round(hw_at(z)))
        v.box(w, w, -1, 2, z, z, "Steel")
        v.box(-w - 1, -w - 1, -1, 2, z, z, "Steel")
    # Quatre mains de zombie en guise de pattes : manchette Plum, trois doigts écartés et un pouce
    for sx in (1, -1):
        for sy in (-1, 1):
            bx = 2 if sx > 0 else -3
            by = -2 if sy < 0 else 2
            for k in range(5):
                z = z0 - 1 - k
                x, y = bx + sx * ((k + 1) // 2), by + sy * ((k + 1) // 2)
                v.box(min(x, x + sx), max(x, x + sx), min(y, y + sy), max(y, y + sy), z, z,
                      "Plum" if k < 2 else "Leaf.d")
            hx, hy = bx + sx * 3, by + sy * 3
            v.box(min(hx, hx + 2 * sx), max(hx, hx + 2 * sx), min(hy, hy + 2 * sy), max(hy, hy + 2 * sy), 0, 0,
                  "Leaf.d")
            for f in (0, 2):
                v.box(min(hx + 3 * sx, hx + 4 * sx), max(hx + 3 * sx, hx + 4 * sx), hy + sy * f, hy + sy * f, 0, 0,
                      "Leaf.d")
            v.box(hx + sx, hx + sx, min(hy + 3 * sy, hy + 4 * sy), max(hy + 3 * sy, hy + 4 * sy), 0, 0, "Leaf.d")
    # Bras qui tiennent la fourchette (gauche, +X) et le couteau (droite, -X), manchettes Plum
    v.box(7, 9, 0, 1, 16, 17, "Leaf.d")
    v.box(7, 8, 0, 1, 16, 17, "Plum")
    v.box(10, 11, -1, 1, 15, 18, "Leaf.d")
    v.box(-10, -8, 0, 1, 16, 17, "Leaf.d")
    v.box(-9, -8, 0, 1, 16, 17, "Plum")
    v.box(-12, -11, -1, 1, 15, 18, "Leaf.d")
    v.box(11, 11, -2, -2, 10, 27, "Steel")
    v.box(9, 13, -2, -2, 28, 28, "Steel")
    for x in (9, 11, 13):
        v.box(x, x, -2, -2, 29, 32, "Steel")
    v.box(-12, -12, -2, -2, 11, 19, "Steel.d")
    v.box(-13, -11, -2, -2, 20, 20, "Steel.d")
    v.box(-13, -12, -2, -2, 21, 30, "Steel")
    v.set(-12, -2, 31, "Steel")
    # Deux gros yeux blancs qui regardent depuis le noir
    eyes = [eye(2.9, -1.2, 23.0, 1.2, look=(-0.15, -0.4), p=0.45),
            eye(-2.9, -1.2, 23.0, 1.2, look=(0.15, -0.4), p=0.45)]
    return v, "bottom", {"kind": "boss", "cell": 0.5, "eyes": eyes, "label": "The Hungry Coffin",
                         "role": "Boss · monde 2"}


ALL = [goblin_grunt, zombie_runner, ghost_poltergeist, boss_hungry_coffin]
GOBLINS = [goblin_grunt, goblin_archer, goblin_shaman, goblin_bomber]


if __name__ == "__main__":
    for fn in ALL + GOBLINS[1:]:
        vox, origin, meta = fn()
        print(f"{vox.name:22s} cellules {len(vox.c):5d}  taille {vox.size_studs(meta['cell'])} studs  "
              f"couleurs {vox.colors_used()}")
