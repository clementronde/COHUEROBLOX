"""COHUE — modèles voxel (A01). Chaque fonction renvoie (Vox, origine, meta).

Repère : unités de voxel (0,25 stud), Z en haut, le modèle regarde vers -Y, symétrie autour de x = 0
(colonne x <-> -1-x). La main droite du personnage est côté -X.

meta : {"kind": "enemy"|"accessory"|"fx"|"prop"|"blockout", ...}. Pour un accessoire, l'origine est le
point d'attache R15 (mesuré sur l'avatar R15 par défaut, voir 80-direction-artistique.md) et
meta["attach"] donne le nom de l'attache.
"""

from __future__ import annotations

from cohue_voxel import Vox

# Avatar R15 par défaut (mesuré dans Studio, en studs) : tête 1,16 x 1,18 x 1,16 ; HatAttachment au sommet
# de la tête ; torse 1,94 x 1,70 x 1,00 ; BodyBackAttachment à 0,21 sous le centre du torse, au dos ;
# bras 1,00 x 1,24 x 1,00 ; LeftShoulderAttachment au sommet du bras ; LeftGripAttachment 0,16 sous la main.


# =============================================================================================
# Gobelins (monde 1). Code couleur des rôles, commun à toutes les familles :
#   mêlée / essaim = rouge (Tomato) · tireur = vert/brun (Leaf, Leather) · soutien = violet (Grape)
#   kamikaze = orange (Ember) + bombe noire. La famille se lit à la silhouette et à la peau (Lime).


def goblin_base(name: str, tunic: str, skin: str = "Lime", legs: bool = True, belt: str = "Leather") -> Vox:
    v = Vox(name)
    if legs:
        v.box(1, 2, -2, 0, 0, 0, "Bark")           # chaussures, orteils vers l'avant
        v.box(1, 2, -1, 0, 1, 2, skin + ".d")      # jambes courtes
    v.box(0, 2, -2, 1, 3, 6, tunic)                # tunique
    v.box(0, 1, -3, -3, 4, 5, tunic)               # petit ventre
    v.box(0, 2, -2, 1, 3, 3, belt)                 # ceinture
    v.set(0, -3, 3, "Gold")                        # boucle
    v.box(3, 3, -1, 0, 4, 5, skin)                 # bras nus
    v.box(3, 3, -1, 0, 6, 6, tunic)                # manche
    v.box(3, 3, -2, -1, 3, 3, skin + ".d")         # main
    # Tête : grosse (42 % de la hauteur), coins arrondis
    v.box(0, 3, -3, 1, 7, 11, skin)
    v.carve(3, 3, -3, -3, 7, 7)
    v.carve(3, 3, 1, 1, 7, 7)
    v.carve(3, 3, 1, 1, 11, 11)
    # Oreilles en pointe horizontales : la signature de la famille (silhouette en T)
    v.box(4, 4, -1, 0, 8, 10, skin)
    v.box(5, 5, -1, 0, 9, 10, skin)
    v.box(6, 6, -1, -1, 10, 10, skin)
    v.box(4, 5, -1, -1, 9, 9, "Tomato.d")          # creux de l'oreille
    # Visage
    v.box(1, 2, -3, -3, 9, 10, "Cream")            # yeux (les pixels les plus clairs)
    v.set(1, -3, 9, "Ink")                         # pupilles qui louchent vers le nez
    v.box(1, 2, -4, -4, 11, 11, skin + ".d")       # sourcils froncés en avancée
    v.box(0, 0, -4, -4, 8, 9, skin)                # gros nez
    v.box(0, 0, -5, -5, 8, 8, skin)
    v.box(0, 2, -3, -3, 7, 7, "Ink")               # bouche
    v.mirror_x()
    v.set(0, -3, 7, "Cream")                       # une seule dent (asymétrie voulue)
    v.shade_rows(0, 0, "d", only={"Bark"})
    return v


def goblin_grunt():
    v = goblin_base("Enemy_GoblinGrunt", "Tomato")
    # Cocotte en fonte émaillée retournée en guise de casque : le dessus de la tête porte le rouge du
    # rôle (la caméra de jeu est haute, on voit surtout le dessus des ennemis).
    # Posée un voxel plus haut que le crâne : le bord crème ne couvre plus les yeux.
    v.box(-5, 4, -4, 2, 12, 12, "Cream")           # bord émaillé
    v.box(-4, 3, -3, 1, 13, 14, "Tomato")
    v.box(-1, 0, -2, 0, 15, 15, "Tomato.d")        # bouton du couvercle (fond de la cocotte)
    v.set(1, -3, 14, "Tomato.l")                   # reflet
    v.box(4, 6, -1, -1, 13, 13, "Ink")             # poignée sur le côté
    # Louche en bois brandie en diagonale (main droite, côté -X) : elle sort de la silhouette
    # au-delà de l'oreille, sinon Grunt et Bomber font la même tache noire à 64 px.
    v.line((-5, -2, 3), (-9, -2, 11), "Bark")
    v.box(-11, -9, -3, -1, 12, 13, "Steel")
    v.set(-10, -2, 13, "Steel.d")                  # creux de la louche
    return v, "bottom", {"kind": "enemy", "role": "swarm", "gag": "casserole et louche"}


def goblin_archer():
    v = goblin_base("Enemy_GoblinArcher", "Leather", belt="Bark")
    # Capuche vert sombre à pointe (couleur du rôle « tireur » sur le dessus), oreilles dessous
    v.box(-4, 3, -3, 2, 12, 12, "Leaf.d")
    v.box(-4, 3, 2, 2, 7, 11, "Leaf.d")
    v.box(-5, -5, -3, 1, 11, 12, "Leaf.d")
    v.box(4, 4, -3, 1, 11, 12, "Leaf.d")
    v.box(-1, 0, 3, 3, 9, 12, "Leaf.d")
    v.box(-1, 0, 4, 4, 8, 10, "Leaf.dd")
    v.box(-1, 0, -1, 1, 13, 13, "Leaf.d")          # pointe de capuche
    v.box(-4, 3, -4, -4, 12, 12, "Leaf.dd")        # bord de capuche
    # Grand arc vertical tenu à gauche (+X) : trait lisible de loin
    for (y, z0, z1) in ((-1, 1, 2), (-2, 3, 4), (-3, 5, 9), (-2, 10, 11), (-1, 12, 13)):
        v.box(5, 5, y, y, z0, z1, "Bark")
    v.box(5, 5, 0, 0, 2, 12, "Cream")              # corde
    # Carquois à la hanche avec flèches à ventouse
    v.box(-4, -3, 1, 2, 2, 5, "Bark")
    v.box(-4, -4, 1, 1, 6, 7, "Leather")
    v.set(-4, 1, 8, "Tomato")
    v.box(-3, -3, 2, 2, 6, 6, "Leather")
    v.set(-3, 2, 7, "Tomato")
    return v, "bottom", {"kind": "enemy", "role": "ranged", "gag": "flèches à ventouse"}


def goblin_shaman():
    v = goblin_base("Enemy_GoblinShaman", "Grape", legs=False, belt="Gold")
    # Robe jusqu'au sol, évasée
    v.box(-3, 2, -2, 1, 0, 2, "Grape")
    v.box(-4, 3, -3, 2, 0, 0, "Grape.d")
    v.box(-3, 2, -3, -3, 1, 2, "Grape")
    v.box(-1, 0, -3, -3, 0, 2, "Grape.d")          # fente de la robe
    # Peintures de guerre sous les yeux
    v.box(-3, 2, -3, -3, 8, 8, "Grape.l")
    v.set(0, -3, 8, "Lime")
    v.set(-1, -3, 8, "Lime")
    # Chapeau en cupule de gland (clin d'œil au Gland Grincheux) + tige
    v.box(-5, 4, -4, 2, 11, 11, "Bark.d")          # bord de la cupule
    v.box(-5, 4, -4, 2, 12, 12, "Leather")         # écailles : bandes larges, pas de damier
    v.box(-4, 3, -3, 1, 13, 13, "Leather.d")
    v.box(-3, 2, -2, 0, 14, 14, "Leather")         # dôme
    v.box(-1, 0, -1, -1, 15, 16, "Bark.d")         # tige
    # Bâton à champignon (main droite, côté -X)
    v.line((-5, -2, 0), (-5, -2, 13), "Bark")
    v.ell(-4.5, -1.5, 15.5, 2.6, 2.6, 1.6, "Grape", zmin=14)   # champignon magique violet (rôle soutien)
    for (x, y, z) in ((-6, -3, 16), (-3, -1, 16), (-5, 0, 15), (-4, -3, 15)):
        if (x, y, z) in v.c:
            v.set(x, y, z, "Cream")
    v.box(-5, -5, -2, -2, 14, 14, "Cream")
    return v, "bottom", {"kind": "enemy", "role": "support", "gag": "chapeau de gland, bâton champignon"}


def goblin_bomber():
    v = goblin_base("Enemy_GoblinBomber", "Ember")
    # Bonnet d'aviateur orange (rôle kamikaze sur le dessus) et grosses lunettes
    v.box(-4, 3, -3, 1, 12, 12, "Ember")
    v.box(-4, 3, -2, 1, 11, 11, "Ember.d")
    v.box(-4, 3, -4, -4, 9, 10, "Steel")
    v.box(-3, -2, -5, -5, 9, 10, "Sky.l")
    v.box(1, 2, -5, -5, 9, 10, "Sky.l")
    v.box(-4, -4, -3, 0, 10, 10, "Steel.d")
    v.box(3, 3, -3, 0, 10, 10, "Steel.d")
    # Bombe énorme portée à bout de bras sur le côté droit (-X) : un gros rond noir qui sort de la
    # silhouette, la mèche loin du visage ; le bonnet orange reste visible sur le dessus.
    v.ell(-8, -1, 4.5, 3.2, 3.0, 3.2, "Ink", zmin=1)
    v.paint_if(lambda x, y, z, c: c == "Ink" and z == 4, "Steel.d")             # cerclage
    v.box(-9, -8, -2, -1, 8, 8, "Steel")             # bouchon
    v.line((-8, -1, 9), (-7, -2, 11), "Bark")        # mèche
    v.box(-7, -6, -2, -2, 12, 12, "Gold")            # étincelle
    v.set(-6, -3, 13, "Ember")
    v.set(-10, -4, 6, "Steel")                       # reflet
    # Sac d'XP volée dans la main gauche (le gag : il vole ton XP)
    v.box(4, 5, -2, -1, 2, 4, "Leather")
    v.box(4, 5, -2, -1, 5, 5, "Sky")
    v.set(5, -2, 6, "Sky.l")
    return v, "bottom", {"kind": "enemy", "role": "exploder", "gag": "vole ton XP"}


# =============================================================================================
# Marqueur de capture (variante capturable) : anneau au sol + cage flottante. Une seule couleur,
# rendue en Neon rose dans Studio (Bubblegum est réservé à la capture).


def capture_ring():
    v = Vox("FX_CaptureRing")
    r_out, r_in = 7, 5
    for x in range(-r_out, r_out):
        for y in range(-r_out, r_out):
            d = max(abs(x + 0.5), abs(y + 0.5))
            if r_in < d <= r_out and not (abs(x + 0.5) > r_out - 1 and abs(y + 0.5) > r_out - 1):
                v.set(x, y, 0, "Bubblegum")
    for x, y in ((-1, -7), (0, -7), (-1, 6), (0, 6), (-7, -1), (-7, 0), (6, -1), (6, 0)):
        v.set(x, y, 1, "Bubblegum")               # crans de visée
    return v, "bottom", {"kind": "fx", "material": "Neon", "color": "Bubblegum"}


def capture_icon():
    v = Vox("FX_CaptureIcon")
    v.box(-2, 1, -2, 1, 0, 0, "Bubblegum")          # socle
    v.box(-2, 1, -2, 1, 5, 5, "Bubblegum")          # toit
    for x in (-2, 1):
        for y in (-2, 1):
            v.box(x, x, y, y, 1, 4, "Bubblegum")    # barreaux d'angle
    v.box(-1, 0, -2, -2, 1, 4, "Bubblegum")         # barreaux de face
    v.carve(-1, 0, -2, -2, 2, 3)
    v.box(-1, 0, -1, 0, 6, 6, "Bubblegum")          # anneau
    v.carve(-1, 0, -1, 0, 6, 6)
    v.box(-1, 0, -1, -1, 6, 7, "Bubblegum")
    v.box(-1, 0, 0, 0, 6, 7, "Bubblegum")
    return v, "bottom", {"kind": "fx", "material": "Neon", "color": "Bubblegum"}


# =============================================================================================
# Équipement des classes. Palier 1 (niveau 10) = tête, palier 2 (niveau 20) = épaules/bras,
# palier 3 (niveau 30) = dos. Les pièces se cumulent : l'équipement grandit.
# Grosses pièces : environ 1,4 fois la partie du corps couverte, pour lire la classe de loin.

HEAD_TOP_TO_CENTER = 2.4   # le centre de la tête est 0,59 stud (2,4 voxels) sous HatAttachment


def knight_helm():
    """Bassinet ouvert : le visage du joueur reste visible. Plumet ridiculement court."""
    v = Vox("Knight_Helm")
    # Origine = HatAttachment (sommet de la tête). La tête occupe x -3..2, y -3..2, z -5..-1.
    v.box(0, 3, -4, 3, -4, 1, "Steel")             # coque 2 x 2 x 1,5 studs
    v.carve(0, 2, -3, 2, -4, 0)                    # creux pour la tête
    v.carve(0, 2, -4, -4, -4, -1)                  # ouverture du visage
    v.paint(0, 3, -4, 3, -4, -4, "Steel.d")        # rebord bas (repeint, pas ajouté)
    v.box(0, 3, -5, -5, 0, 0, "Steel.d")           # visière du front en avancée
    v.box(0, 0, -5, -5, -3, -1, "Steel.d")         # nasal (2 voxels de large après miroir)
    v.box(0, 0, -2, 1, 2, 2, "Royal")              # crête
    v.box(0, 0, 0, 0, 3, 3, "Royal.l")             # plumet minuscule
    v.set(3, -2, -2, "Gold")                       # rivets
    v.set(3, 1, -2, "Gold")
    v.mirror_x()
    return v, (0, 0, 0), {"kind": "accessory", "attach": "HatAttachment", "part": "Head", "tier": 1, "class": "Knight"}


def knight_pauldron():
    """Une épaulière ; la même maille sert aux deux épaules (demi-tour vertical pour la gauche)."""
    v = Vox("Knight_Pauldron")
    # Origine = RightShoulderAttachment (sommet du bras droit). Le bras droit est côté -X dans Blender :
    # l'extérieur est donc -X. Le dessin est symétrique avant/arrière, d'où le demi-tour possible.
    # Bleu roi (le casque est en acier) : les épaulières se détachent du casque vues de dos.
    v.box(-4, 1, -3, 2, 0, 1, "Royal")             # plaque haute
    v.box(-5, 0, -3, 2, -1, -1, "Royal.d")         # lame 2
    v.box(-5, -2, -3, 2, -2, -2, "Steel.d")        # lame 3 tombante, en acier
    v.box(-3, -1, -1, 0, 2, 2, "Steel")            # bosse centrale
    v.box(-2, -2, -1, 0, 3, 3, "Gold")             # un seul rivet or
    return v, (0, 0, 1), {"kind": "accessory", "attach": "RightShoulderAttachment", "part": "RightUpperArm",
                          "also": "LeftShoulderAttachment", "tier": 2, "class": "Knight"}


def knight_cape():
    """Cape bleu roi, liseré or, blason absurde : un canard couronné."""
    v = Vox("Knight_Cape")
    # Origine = BodyBackAttachment (dos, 0,21 sous le centre du torse). Le haut de la cape est au col.
    top = 4
    for z in range(-9, top + 1):
        back = 1 + (0 if z >= 0 else (-z + 2) // 4)    # la cape s'écarte du corps en descendant
        half = 4 if z >= 0 else 5
        v.box(-half, half - 1, back, back, z, z, "Royal")
    v.box(-5, 4, 1, 3, -9, -9, "Gold")             # liseré bas
    for x in range(-5, 5, 2):
        v.carve(x, x, 1, 4, -9, -9)                # bas découpé en créneaux
    v.box(-4, 3, 1, 1, top, top, "Gold")           # col
    v.box(-4, -3, 0, 0, top, top, "Gold")          # agrafes
    v.box(2, 3, 0, 0, top, top, "Gold")
    # Canard couronné (or + bec orange), sur la face extérieure
    duck = [(-1, 0), (0, 0), (1, 0), (-2, -1), (-1, -1), (0, -1), (1, -1), (2, -1), (-1, -2), (0, -2), (1, -2),
            (0, 1), (1, 1), (0, 2), (1, 2)]
    for dx, dz in duck:
        v.set(dx, 2, -3 + dz, "Gold")
    v.set(2, 2, -1, "Ember")                       # bec
    v.set(1, 2, -1, "Ink")                         # œil
    v.set(0, 2, 0, "Gold.l")
    v.set(1, 2, 0, "Gold.l")                       # couronne
    return v, (0, 0, 0), {"kind": "accessory", "attach": "BodyBackAttachment", "part": "UpperTorso", "tier": 3, "class": "Knight"}


def archer_hood():
    """Capuche verte à longue pointe, visage dégagé, gland en broche."""
    v = Vox("Archer_Hood")
    v.box(0, 3, -4, 3, -5, 1, "Leaf")
    v.carve(0, 2, -3, 2, -5, 0)
    v.carve(0, 2, -4, -4, -5, -1)                  # visage
    v.paint(0, 3, -4, 3, -5, -5, "Leather")        # ourlet
    v.paint(0, 3, -4, -4, -1, -1, "Leaf.d")        # bord du visage, en creux
    v.carve(3, 3, -4, -4, 1, 1)                    # coins arrondis : ce n'est pas un casque
    v.carve(3, 3, 3, 3, 1, 1)
    v.box(0, 2, -3, 2, 2, 2, "Leaf")               # dôme
    v.mirror_x()
    v.box(-1, 0, -3, -1, 3, 3, "Leaf")             # pointe de capuche qui monte et part en avant
    v.box(-1, 0, -3, -2, 4, 4, "Leaf.l")
    v.box(-1, 0, -4, -4, 4, 5, "Leaf.l")
    # Courte queue dans le dos (s'arrête au-dessus du carquois)
    v.box(-2, 1, 4, 4, -2, 1, "Leaf")
    v.box(-1, 0, 5, 5, -3, 0, "Leaf.d")
    # Broche en gland sur la joue gauche (+X)
    v.set(4, -3, -3, "Bark")
    v.set(4, -3, -4, "Leather")
    v.set(4, -2, -4, "Leather")
    return v, (0, 0, 0), {"kind": "accessory", "attach": "HatAttachment", "part": "Head", "tier": 1, "class": "Archer"}


def archer_bracer():
    """Brassard de cuir sur l'avant-bras gauche, cible brodée sur l'extérieur."""
    v = Vox("Archer_Bracer")
    # Origine = LeftGripAttachment (0,16 sous le centre de la main) ; l'avant-bras va de z 1 à 5.
    # Le bras gauche est côté +X dans Blender : l'extérieur est +X.
    v.box(-3, 2, -3, 2, 1, 5, "Leather")
    v.carve(-2, 1, -2, 1, 1, 5)                    # creux de l'avant-bras (1 stud)
    v.paint(-3, 2, -3, 2, 5, 5, "Leather.d")
    v.paint(-3, 2, -3, 2, 1, 1, "Leather.d")
    v.paint(-3, 2, -3, 2, 5, 5, "Leaf")            # revers vert en haut (pas de rayures)
    v.box(-2, 1, 3, 3, 2, 4, "Tomato")             # cible brodée sur le dos (+Y : visible de la caméra)
    v.box(-1, 0, 3, 3, 2, 4, "Cream")
    v.box(-1, 0, 3, 3, 3, 3, "Tomato.d")
    v.set(-4, -1, 3, "Gold")                       # boucle côté intérieur
    # Les attaches Grip des mains R15 sont tournées de -90° sur X : l'attache de la poignée doit l'être aussi.
    return v, (0, 0, 0), {"kind": "accessory", "attach": "LeftGripAttachment", "part": "LeftLowerArm", "tier": 2,
                          "class": "Archer", "attach_rot": [-90, 0, 0]}


def archer_quiver():
    """Carquois droit dans le dos ; une des flèches est une carotte."""
    v = Vox("Archer_Quiver")
    # Origine = BodyBackAttachment. Carquois droit dans le dos, côté épaule droite (-X).
    v.box(-4, -1, 1, 3, -5, 3, "Leather")
    v.box(-4, -1, 1, 3, -5, -5, "Bark")            # fond
    v.paint(-4, -1, 1, 3, 3, 3, "Leather.d")       # col du carquois
    v.paint(-4, -1, 1, 1, -1, -1, "Gold")          # cerclage (face visible)
    v.paint(-4, -1, 3, 3, -1, -1, "Gold")
    # Flèches à empennage bien visible au-dessus de l'épaule ; une des flèches est une carotte
    for dx, fl in ((-4, "Tomato"), (-1, "Leaf")):
        v.box(dx, dx, 2, 2, 4, 6, "Bark")
        v.box(dx, dx, 1, 3, 7, 8, fl)
    v.box(-3, -2, 2, 2, 4, 6, "Ember")             # la carotte
    v.box(-3, -2, 2, 2, 7, 7, "Ember.l")
    v.box(-3, -2, 1, 3, 8, 8, "Leaf")
    v.line((-1, 1, 3), (3, 1, -3), "Bark")         # sangle en travers du dos
    return v, (0, 0, 0), {"kind": "accessory", "attach": "BodyBackAttachment", "part": "UpperTorso", "tier": 3, "class": "Archer"}


def mage_hat():
    """Chapeau pointu violet à bord large, pointe qui retombe, étoiles cousues."""
    v = Vox("Mage_Hat")
    # Origine = HatAttachment. Le bandeau descend de 2 voxels autour du crâne.
    v.ell(0, 0, -1.5, 5.6, 5.6, 0.5, "Grape.d")    # bord large (une couche, z -2)
    v.box(-4, 3, -4, 3, -2, 0, "Grape")
    v.carve(-3, 2, -3, 2, -2, -1)                  # creux du crâne
    v.paint(-4, 3, -4, 3, -1, -1, "Gold")          # ruban
    for z, r in ((1, 3), (2, 3), (3, 2), (4, 2), (5, 2), (6, 1), (7, 1)):
        v.box(-r, r - 1, -r, r - 1, z, z, "Grape")
    v.box(-1, 0, 0, 1, 8, 8, "Grape")              # la pointe part vers l'arrière
    v.box(-1, 0, 2, 3, 8, 8, "Grape")
    v.box(-1, 0, 4, 4, 7, 7, "Grape.l")
    v.box(-1, 0, 5, 5, 6, 6, "Gold")               # grelot au bout
    for (x, y, z) in ((2, -3, 2), (-2, -2, 4), (1, -2, 5)):
        v.set(x, y, z, "Gold")                     # étoiles
    v.set(-3, -3, 1, "Cream")
    return v, (0, 0, 0), {"kind": "accessory", "attach": "HatAttachment", "part": "Head", "tier": 1, "class": "Mage"}


def mage_orb():
    """Orbe de feu dans une cage violette, flotte au-dessus de l'épaule gauche."""
    v = Vox("Mage_Orb")
    v.box(-1, 0, -1, 0, -1, 0, "Ember")            # cœur (doublé d'un cube Neon dans Studio)
    for x in range(-4, 4):
        for y in range(-4, 4):
            d = ((x + 0.5) ** 2 + (y + 0.5) ** 2) ** 0.5
            if 2.3 < d <= 3.6:
                v.set(x, y, 0, "Grape")            # anneau horizontal (rond, pas un cadre)
    for x in range(-4, 4):
        for z in range(-4, 4):
            d = ((x + 0.5) ** 2 + (z + 0.5) ** 2) ** 0.5
            if 2.3 < d <= 3.6 and (x, -1, z) not in v.c:
                v.set(x, -1, z, "Gold")            # anneau vertical
    v.box(-1, 0, -1, -1, 4, 4, "Gold.l")           # petite flamme au sommet
    v.set(-1, -1, 5, "Ember")
    # Origine = LeftShoulderAttachment ; l'orbe flotte 1 stud au-dessus et 1,25 stud vers l'extérieur,
    # hors du bord du chapeau.
    return v, (-5, 0, -4), {"kind": "accessory", "attach": "LeftShoulderAttachment", "part": "LeftUpperArm", "tier": 2,
                            "class": "Mage", "neon_core": "Ember", "neon_core_at": [0, 0, 0], "neon_core_size": 0.5}


def mage_cape():
    """Cape évasée jusqu'au genou, haut col pointu, ciel étoilé."""
    v = Vox("Mage_Cape")
    top = 4
    for z in range(-9, top + 1):
        back = 1 + (0 if z >= -2 else (-z - 1) // 4)
        half = 4 + (0 if z >= -4 else (-z - 3) // 3)
        v.box(-half, half - 1, back, back, z, z, "Plum")
    v.box(-5, 4, 1, 1, top + 1, top + 2, "Grape")  # haut col
    v.box(-5, -5, 0, 0, top + 1, top + 3, "Grape")
    v.box(4, 4, 0, 0, top + 1, top + 3, "Grape")
    v.box(-4, 3, 0, 0, top, top, "Gold")
    stars = [(-3, -1), (2, -3), (-1, -6), (3, -8), (-4, -8), (0, -5), (-2, -3)]
    for sx, sz in stars:
        for k in [k for k in v.c if k[0] == sx and k[2] == sz]:
            v.c[(k[0], k[1] + 1, k[2])] = "Gold"
    v.paint_if(lambda x, y, z, c: z == -9 and c == "Plum", "Grape")
    return v, (0, 0, 0), {"kind": "accessory", "attach": "BodyBackAttachment", "part": "UpperTorso", "tier": 3, "class": "Mage"}


# =============================================================================================
# Armes de départ (A01-05). Origine = centre de la prise ; l'arme pointe vers +Z (Blender), soit +Y
# dans Roblox. Lame ou manche épais d'au moins 2 voxels pour rester lisible de loin.

WEAPON = {"kind": "weapon"}


def weapon_broadsword():
    """Knight : épée large ; le pommeau est un canard (clin d'œil à la cape)."""
    v = Vox("Weapon_Broadsword")
    v.box(-1, 0, -1, 0, -2, 1, "Leather")          # prise
    v.box(-1, 0, -1, 0, -1, -1, "Leather.d")
    v.box(-4, 3, -1, 0, 2, 2, "Royal")             # garde
    v.box(-4, -4, -1, 0, 3, 3, "Royal.l")
    v.box(3, 3, -1, 0, 3, 3, "Royal.l")
    v.box(-2, 1, -1, -1, 3, 14, "Steel")           # lame 1 x 0,25 stud
    v.box(-1, 0, -1, -1, 15, 15, "Steel")          # pointe
    v.box(-1, 0, 0, 0, 3, 13, "Steel.d")           # gorge au dos de la lame
    v.box(-1, 0, -2, 0, -4, -3, "Gold")            # pommeau-canard
    v.set(-1, -3, -3, "Ember")                     # bec
    v.set(0, -2, -3, "Ink")                        # œil
    return v, (0, 0, 0), {**WEAPON, "class": "Knight", "weapon": "Broadsword", "gag": "pommeau en canard"}


def weapon_longbow():
    """Archer : arc long ; une feuille pousse au bout de la branche."""
    v = Vox("Weapon_Longbow")
    arc = [(-1, -9, -6), (-2, -5, -3), (-2, -2, 2), (-2, 3, 5), (-1, 6, 9)]
    for y, z0, z1 in arc:
        v.box(0, 0, y, y, z0, z1, "Bark")
        v.box(-1, -1, y, y, z0, z1, "Bark")
    v.box(-1, 0, -3, -2, -1, 1, "Leaf")            # poignée enroulée
    v.box(-1, 0, 0, 0, -9, 9, "Cream")             # corde
    v.box(-1, 0, -1, -1, 10, 10, "Leaf")           # la feuille qui pousse
    v.set(0, -2, 11, "Leaf.l")
    return v, (0, -2, 0), {**WEAPON, "class": "Archer", "weapon": "Longbow", "gag": "une feuille pousse au bout"}


def weapon_firestaff():
    """Mage : bâton de feu ; une guimauve grille sous la flamme."""
    v = Vox("Weapon_FireStaff")
    v.box(-1, 0, -1, 0, -8, 9, "Bark")
    v.box(-1, 0, -1, 0, -8, -8, "Bark.d")
    v.box(-2, 1, -2, 1, 10, 10, "Gold")            # griffe
    for x, y in ((-2, -2), (1, -2), (-2, 1), (1, 1)):
        v.set(x, y, 11, "Gold")
        v.set(x, y, 12, "Gold")
    v.box(-1, 0, -1, 0, 11, 13, "Ember")           # cristal de feu (cube Neon dans Studio)
    v.box(-1, 0, -1, 0, 14, 14, "Gold.l")
    v.box(1, 2, -1, 0, 7, 8, "Cream")              # la guimauve piquée sur une branche
    v.set(1, -1, 9, "Bark")
    v.set(1, 0, 8, "Leather.l")                    # côté grillé
    return v, (0, 0, 0), {**WEAPON, "class": "Mage", "weapon": "FireStaff", "gag": "guimauve qui grille",
                           "neon_core_at": [0, 0, 12], "neon_core_size": 0.5}


def weapon_quakehammer():
    """Guardian : marteau sismique ; un pansement sur la tête du marteau."""
    v = Vox("Weapon_QuakeHammer")
    v.box(-1, 0, -1, 0, -8, 7, "Bark")
    v.box(-1, 0, -1, 0, -8, -8, "Steel.d")
    v.box(-4, 3, -2, 1, 8, 12, "Stone")            # tête 2 x 1 x 1,25 studs
    v.paint(-4, 3, -2, 1, 8, 8, "Stone.d")
    v.box(-5, -5, -2, 1, 8, 12, "Steel")           # faces de frappe
    v.box(4, 4, -2, 1, 8, 12, "Steel")
    v.box(-2, 1, -3, -3, 10, 10, "Cream")          # pansement en croix
    v.box(-1, 0, -3, -3, 9, 11, "Cream")
    return v, (0, 0, 0), {**WEAPON, "class": "Guardian", "weapon": "QuakeHammer", "gag": "pansement sur le marteau"}


def weapon_throwingdagger():
    """Rogue : dague de lancer (projectile) ; ruban rouge noué au pommeau."""
    v = Vox("Weapon_ThrowingDagger")
    v.box(-1, 0, -1, 0, -1, 0, "Plum")             # prise
    v.box(-2, 1, -1, 0, 1, 1, "Steel.d")           # garde
    v.box(-1, 0, -1, -1, 2, 5, "Steel")            # lame
    v.set(-1, -1, 6, "Steel.l")
    v.box(0, 1, 0, 0, -2, -2, "Tomato")            # ruban
    v.set(1, 1, -3, "Tomato")
    return v, (0, 0, 0), {**WEAPON, "class": "Rogue", "weapon": "ThrowingDaggers", "gag": "ruban noué"}


def weapon_holybell():
    """Cleric : l'Aura sacrée sonne avec une cloche de cantine en porcelaine."""
    # Clochette à main : manche en haut (la prise), cloche évasée vers le bas, battant qui dépasse.
    v = Vox("Weapon_HolyBell")
    v.box(-1, 0, -1, 0, -1, 4, "Leather")          # manche
    v.box(-1, 0, -1, 0, 5, 5, "Leather.d")         # bouton du manche
    v.box(-1, 0, -1, 0, -2, -2, "Gold")            # bague
    for z, r in ((-3, 2), (-4, 2), (-5, 3), (-6, 3), (-7, 4)):
        v.box(-r, r - 1, -r, r - 1, z, z, "Cream")
    v.carve(-3, 2, -3, 2, -7, -6)                  # creux de la cloche
    v.paint(-4, 3, -4, 3, -7, -7, "Gold")          # bord doré
    v.box(-1, 0, -1, 0, -8, -6, "Sky")             # battant
    return v, (0, 0, 0), {**WEAPON, "class": "Cleric", "weapon": "HolyAura", "gag": "cloche de cantine"}


def weapon_spinningaxe():
    """Barbarian : hache de jet ; un smiley gravé sur le fer."""
    v = Vox("Weapon_SpinningAxe")
    v.box(-1, 0, -1, 0, -5, 5, "Bark")
    v.box(-1, 0, -1, 0, -5, -5, "Tomato")          # bout de manche peint
    v.box(1, 4, -1, 0, 2, 6, "Steel")              # fer
    v.box(5, 5, -1, 0, 1, 7, "Steel.l")            # tranchant
    v.box(-3, -2, -1, 0, 3, 5, "Steel.d")          # contre-poids
    v.set(2, -2, 5, "Ink")                         # smiley gravé
    v.set(4, -2, 5, "Ink")
    v.box(2, 4, -2, -2, 3, 3, "Ink")
    return v, (0, 0, 0), {**WEAPON, "class": "Barbarian", "weapon": "SpinningAxes", "gag": "smiley gravé"}


def weapon_beastwhip():
    """Tamer : fouet enroulé ; un pompon de cirque au bout."""
    v = Vox("Weapon_BeastWhip")
    v.box(-1, 0, -1, 0, -4, 1, "Leather")          # manche
    v.box(-1, 0, -1, 0, 2, 2, "Ember")
    v.box(-1, 0, -1, 0, -5, -5, "Ember")
    # lanière enroulée en anneaux carrés autour du manche
    for z in (2, 4, 6):
        for x in range(-3, 3):
            for y in range(-3, 3):
                if max(abs(x + 0.5), abs(y + 0.5)) == 2.5:
                    v.set(x, y, z, "Bark" if z != 4 else "Leather.d")
    v.line((2, -3, 7), (3, -4, 10), "Bark")
    v.box(3, 4, -5, -4, 11, 12, "Tomato")          # pompon
    v.set(4, -5, 13, "Gold")
    return v, (0, 0, 0), {**WEAPON, "class": "Tamer", "weapon": "BeastWhip", "gag": "pompon de cirque"}


WEAPONS = [weapon_broadsword, weapon_longbow, weapon_firestaff, weapon_quakehammer, weapon_throwingdagger,
           weapon_holybell, weapon_spinningaxe, weapon_beastwhip]


# =============================================================================================
# Ébauches (planche des silhouettes uniquement, pas des livrables)


def zombie_base(name, rag, skin="Sky.d"):
    v = Vox(name)
    v.box(1, 2, -1, 0, 0, 3, "Plum")               # jambes en haillons
    v.box(1, 2, -2, 0, 0, 0, "Bark")
    v.box(0, 2, -1, 1, 4, 8, rag)                  # torse voûté
    v.box(0, 2, -2, 0, 9, 9, rag)
    v.box(3, 3, -7, -1, 8, 8, skin)                # bras tendus devant (signature)
    v.box(0, 2, -4, 0, 10, 13, skin)               # tête basse, en avant
    v.box(1, 1, -5, -5, 11, 12, "Cream")
    v.set(1, -5, 11, "Ink")
    v.box(0, 1, -5, -5, 10, 10, "Ink")
    v.mirror_x()
    return v


def zombie_shambler():
    v = zombie_base("Blockout_ZombieShambler", "Tomato.d")
    return v, "bottom", {"kind": "blockout"}


def zombie_runner():
    v = Vox("Blockout_ZombieRunner")
    v.box(1, 1, -1, 0, 0, 4, "Plum")
    v.box(-2, -2, 1, 2, 0, 4, "Plum")
    v.box(-2, 1, -2, 0, 5, 9, "Leaf.d")
    v.box(-2, 1, -5, -2, 10, 13, "Sky.d")          # tête projetée en avant (il court)
    v.box(2, 2, -6, -1, 8, 8, "Sky.d")
    v.box(-3, -3, 1, 4, 7, 7, "Sky.d")
    v.box(0, 0, -6, -6, 11, 12, "Cream")
    return v, "bottom", {"kind": "blockout"}


def zombie_bloater():
    v = Vox("Blockout_ZombieBloater")
    v.ell(0, 0, 6, 6, 5, 6, "Ember.d")
    v.ell(0, -1, 14, 2.5, 2.5, 2.5, "Sky.d")
    v.box(-5, -4, -1, 0, 0, 1, "Plum")
    v.box(3, 4, -1, 0, 0, 1, "Plum")
    v.box(-1, 0, -6, -6, 5, 7, "Ink")              # nombril
    return v, "bottom", {"kind": "blockout"}


def zombie_gravedigger():
    v = zombie_base("Blockout_Gravedigger", "Grape.d")
    v.box(-4, 3, -5, 1, 14, 14, "Ink")             # chapeau haut-de-forme
    v.box(-3, 2, -4, 0, 15, 18, "Ink")
    v.line((5, -3, 0), (5, -3, 14), "Bark")        # pelle
    v.box(4, 6, -4, -2, 0, 3, "Steel")
    return v, "bottom", {"kind": "blockout"}


def ghost_base(name, body="Cream", h=12):
    v = Vox(name)
    v.ell(0, 0, h - 4, 4, 4, 4.5, body, zmin=h - 6)
    for z in range(2, h - 5):
        r = 4 if z > 5 else 3
        v.box(-r, r - 1, -3, 2, z, z, body)
    for x in range(-3, 3):
        if x % 2 == 0:
            v.box(x, x, -2, 1, 0, 1, body.split(".")[0] + ".d")  # bas ondulé
    v.box(-3, -2, -4, -4, h - 5, h - 3, "Ink")
    v.box(1, 2, -4, -4, h - 5, h - 3, "Ink")
    return v


def ghost_wisp():
    v = Vox("Blockout_Wisp")
    v.ell(0, 0, 4, 2.5, 2.5, 3, "Cream")
    v.box(-1, 0, -1, 0, 7, 9, "Grape.l")
    v.box(0, 0, -3, -3, 4, 5, "Ink")
    v.box(-2, -2, -3, -3, 4, 5, "Ink")
    return v, "bottom", {"kind": "blockout"}


def ghost_poltergeist():
    v = ghost_base("Blockout_Poltergeist")
    v.box(5, 8, -1, 2, 10, 10, "Leather")          # une chaise de classe à bout de bras
    v.box(5, 5, -1, -1, 6, 9, "Leather")
    v.box(8, 8, 2, 2, 6, 9, "Leather")
    v.box(5, 8, 2, 2, 10, 13, "Leather")
    v.box(-8, -6, -1, 1, 9, 10, "Tomato")          # un livre
    return v, "bottom", {"kind": "blockout"}


def ghost_banshee():
    v = ghost_base("Blockout_Banshee", "Cream", h=14)
    v.box(-5, 4, 1, 4, 3, 14, "Plum")              # longue chevelure
    v.box(-1, 0, -5, -5, 6, 8, "Ink")              # bouche qui crie
    return v, "bottom", {"kind": "blockout"}


def ghost_armor():
    v = Vox("Blockout_HauntedArmor")
    v.box(1, 2, -1, 0, 0, 4, "Steel.d")
    v.box(0, 3, -2, 1, 5, 10, "Steel")
    v.box(4, 4, -1, 0, 5, 10, "Steel.d")
    v.box(0, 2, -2, 1, 11, 14, "Steel")
    v.box(1, 1, -3, -3, 12, 12, "Gold.l")          # yeux qui brillent
    v.mirror_x()
    v.box(-6, -6, -4, -4, 2, 15, "Steel.l")        # lance
    return v, "bottom", {"kind": "blockout"}


# =============================================================================================
# Décor (planche diorama) : bosquet, rocher, île de forêt avec coupe de terrain


def prop_tree(seed: int = 0):
    # Décor = tons calmes : feuillage en ombre (.d) avec un dessus au ton de base, jamais .l.
    v = Vox(f"Prop_Tree{seed}")
    v.box(-1, 0, -1, 0, 0, 7, "Bark")
    v.box(-2, 1, -2, 1, 0, 0, "Bark.d")
    v.ell(0, 0, 11, 5 + seed % 2, 5, 4, "Leaf.d")
    v.ell(0, 0, 14.5, 3.5, 3.5, 2.5, "Leaf")
    v.paint_if(lambda x, y, z, c: c == "Leaf.d" and z <= 8, "Leaf.dd")
    return v, "bottom", {"kind": "prop"}


def prop_rock():
    v = Vox("Prop_Rock")
    v.ell(0, 0, 0, 4, 3, 3.5, "Stone", zmin=0)
    v.ell(-1, 0, 3, 2.5, 2, 1.5, "Stone.l", zmin=3)
    v.paint_if(lambda x, y, z, c: z == 0, "Stone.d")
    return v, "bottom", {"kind": "prop"}


def island(w=48, d=40):
    """Tuile de forêt flottante avec coupe de terrain visible (signature diorama)."""
    v = Vox("Diorama_Island")
    hw, hd = w // 2, d // 2
    for x in range(-hw, hw):
        for y in range(-hd, hd):
            edge = min(x + hw, hw - 1 - x, y + hd, hd - 1 - y)
            depth = 7 + min(edge, 8)                      # île épaisse qui s'affine dessous
            for z in range(-depth, 1):
                if z == 0:
                    # herbe au ton d'ombre, quelques grandes plaques au ton de base (pas de mouchetis)
                    patch = ((x // 6) * 5 + (y // 5) * 3) % 7 == 0
                    c = "Leaf" if patch else "Leaf.d"
                elif z >= -1:
                    c = "Bark"
                elif z >= -4:
                    c = "Leather.d"
                else:
                    c = "Stone.d"
                v.set(x, y, z, c)
    for y in range(-hd, hd):
        wob = 1 if (y // 6) % 2 else 0                       # chemin qui serpente par paliers
        for x in range(-3 + wob, 3 + wob):
            v.set(x, y, 0, "Leather.d")
        v.set(-4 + wob, y, 0, "Bark")                         # bordure sombre
        v.set(3 + wob, y, 0, "Bark")
    return v, (0, 0, 0), {"kind": "prop"}


def mannequin():
    """Silhouette neutre à l'échelle de l'avatar R15 par défaut (5,5 studs), pour les rendus seulement.

    Repères (voxels, pied à z 0) : HatAttachment (0, 0, 22) ; BodyBackAttachment (0, 2, 13) ;
    ShoulderAttachment (±6, 0, 17) ; LeftGripAttachment (6, 0, 9)."""
    v = Vox("Ref_Avatar")
    v.box(-4, 3, -2, 1, 0, 8, "Stone")             # jambes
    v.box(-1, 0, -2, -2, 0, 8, "Stone.d")
    v.box(-4, 3, -2, 1, 9, 16, "Stone.l")          # torse 2 studs
    v.box(4, 7, -2, 1, 9, 16, "Stone")             # bras (gauche = +X)
    v.box(-8, -5, -2, 1, 9, 16, "Stone")
    v.box(-3, 2, -3, 2, 17, 21, "Cream.d")         # tête
    v.box(-2, -1, -4, -4, 19, 19, "Ink")
    v.box(0, 1, -4, -4, 19, 19, "Ink")
    return v, "bottom", {"kind": "ref"}


ENEMIES = [goblin_grunt, goblin_archer, goblin_shaman, goblin_bomber]
FX = [capture_ring, capture_icon]
EQUIPMENT = [knight_helm, knight_pauldron, knight_cape, archer_hood, archer_bracer, archer_quiver,
             mage_hat, mage_orb, mage_cape]
BLOCKOUTS = [zombie_shambler, zombie_runner, zombie_bloater, zombie_gravedigger,
             ghost_wisp, ghost_poltergeist, ghost_banshee, ghost_armor]
PROPS = [lambda: prop_tree(0), lambda: prop_tree(1), prop_rock]
DELIVERABLES = ENEMIES + FX + EQUIPMENT + WEAPONS
