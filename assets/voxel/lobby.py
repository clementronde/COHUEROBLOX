"""COHUE — maquette du lobby compact « Hubbub Village », refonte du 5 nov. 2026 (A01).

Style (5 nov., deux retours de Clément) : carte naturelle (sol lisse, arbres peints, rochers à facettes,
nature.py) et éléments interactifs en briques à tenons (brick.py). Les tenons seront posés en jeu par le
plugin de Clément. La première version de la maquette était en voxels ; la grille de modélisation des
éléments interactifs reste la même.

Remplace le premier lobby en Parts (refusé par Clément : « beaucoup trop AI slop »). Principes :
- un seul héros : la tête de gobelin géante en pierre, endormie, dont la bouche est le portail ;
- éléments interactifs en briques à tenons (tête 0,5, stations et props 0,25) ; décor naturel lisse ;
- aucun panneau écrit : chaque station se lit à ses objets (blagues montrées, pas écrites) ;
- île flottante naturelle : collines douces, chemins de terre, falaise de rochers, forêt en lisière.

Rendus (Blender 5.2 en ligne de commande) :
    blender -b --factory-startup --python assets/voxel/lobby.py -- <dossier_de_sortie> [vue ...]

Repère du monde (studs, Z en haut) : arrivée au sud (+Y), portail au nord (-Y), centre de la place
en (0, 2). Chaque modèle de station regarde vers -Y dans son repère local (convention du guide) et
est tourné à la pose.
"""

from __future__ import annotations

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.append(HERE)

from cohue_voxel import Vox, tone  # noqa: E402

G1, G2, G4 = 1.0, 0.5, 0.25   # grains : terrain, grands props, stations et petits props

# ---------------------------------------------------------------------------------------------
# Bruit déterministe (aucun aléatoire : la maquette se reconstruit à l'identique)


def hnoise(x: int, y: int, s: int = 0) -> float:
    n = (x * 374761393 + y * 668265263 + s * 1442695041) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def vnoise(x: float, y: float, cell: float, s: int = 0) -> float:
    gx, gy = x / cell, y / cell
    x0, y0 = math.floor(gx), math.floor(gy)
    tx, ty = gx - x0, gy - y0
    tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
    a, b = hnoise(x0, y0, s), hnoise(x0 + 1, y0, s)
    c, d = hnoise(x0, y0 + 1, s), hnoise(x0 + 1, y0 + 1, s)
    return a + (b - a) * tx + (c - a) * ty + (a - b - c + d) * tx * ty


def seg_dist(px, py, a, b):
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - ax - t * dx, py - ay - t * dy)


def carve_ell(v: Vox, cx, cy, cz, rx, ry, rz, zmin=None):
    def inside(x, y, z):
        if zmin is not None and z < zmin:
            return False
        return ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 + ((z + 0.5 - cz) / rz) ** 2 <= 1.0
    v.c = {k: c for k, c in v.c.items() if not inside(*k)}
    return v


def paint_near(v: Vox, p0, p1, col, r=1.0):
    """Repeint les voxels existants à moins de r d'un segment (fissures, mousse)."""
    ax, ay, az = p0
    bx, by, bz = p1
    d = (bx - ax, by - ay, bz - az)
    dd = sum(c * c for c in d) or 1.0
    for (x, y, z) in list(v.c):
        px, py, pz = x + 0.5, y + 0.5, z + 0.5
        t = max(0.0, min(1.0, ((px - ax) * d[0] + (py - ay) * d[1] + (pz - az) * d[2]) / dd))
        q = (ax + t * d[0] - px, ay + t * d[1] - py, az + t * d[2] - pz)
        if q[0] * q[0] + q[1] * q[1] + q[2] * q[2] <= r * r:
            v.c[(x, y, z)] = col
    return v


def taper(v: Vox, p0, p1, r0, r1, col, steps=None):
    """Forme effilée (oreille, défense, flamme) : boîtes dont le demi-côté passe de r0 à r1."""
    n = steps or int(max(abs(p1[i] - p0[i]) for i in range(3))) + 1
    for i in range(n + 1):
        t = i / n
        c = [p0[k] + (p1[k] - p0[k]) * t for k in range(3)]
        r = r0 + (r1 - r0) * t
        lo = [math.floor(c[k] - r + 0.5) for k in range(3)]
        hi = [max(lo[k], math.floor(c[k] + r - 0.5)) for k in range(3)]
        v.box(lo[0], hi[0], lo[1], hi[1], lo[2], hi[2], col)
    return v


def pennant(v: Vox, x, y, h, col, length=12, side=1):
    """Mât et fanion effilé (couleur de la classe). Grain 0,25."""
    v.box(x, x, y, y, 0, h, "Bark")
    for i in range(length):
        hh = max(0, round(3.0 * (1 - i / length)))
        xi = x + side * (1 + i)
        v.box(xi, xi, y, y, h - 4 - hh, h - 4 + hh, col)
    return v


# ---------------------------------------------------------------------------------------------
# Plan (studs, repère du monde)

HX, HY, RC = 56, 50, 16          # demi-largeur, demi-profondeur, rayon des coins de l'île
PLAZA = (0.0, 2.0, 10.0)          # centre et rayon de la place
COURT = (0.0, -19.0, 28.0, 8.0)   # parvis du portail (ellipse)
PADS = {"Solo": (-17.0, -20.0, 3.5, 1), "Public": (0.0, -15.0, 6.5, 4), "Friends": (17.0, -20.0, 5.0, 2)}

STATIONS = {   # nom : (x, y, rotation en degrés pour que l'avant local -Y regarde le chemin)
    "Knight": (-17.0, 27.0, 90.0),
    "Archer": (18.0, 22.0, -90.0),
    "Mage": (-17.0, 10.0, 90.0),
    "Crates": (17.0, 37.0, -90.0),
    "Haystack": (-13.0, 42.0, 0.0),
    "Pen": (-37.0, 2.0, 0.0),
    "Shop": (35.0, 4.0, -90.0),
    "Hall": (-34.0, -27.0, 112.0),
    "Quest": (34.0, -27.0, -112.0),
    "Campfire": (16.0, -8.0, 0.0),
}

PATHS = [  # chemins secondaires : (départ, arrivée, demi-largeur)
    ((-9.0, 2.0), (-26.0, 2.0), 2.5),     # place -> enclos
    ((9.0, 3.0), (29.0, 4.0), 2.5),       # place -> boutique
    ((-7.0, -5.0), (-28.0, -23.0), 2.5),  # place -> panthéon
    ((7.0, -5.0), (28.0, -23.0), 2.5),    # place -> quêtes
    ((-3.0, 27.0), (-11.0, 27.0), 2.0),   # avenue -> Knight
    ((3.0, 22.0), (11.0, 22.0), 2.0),     # avenue -> Archer
    ((-4.0, 11.0), (-12.0, 10.0), 2.0),   # place -> tour du Mage
    ((7.0, -2.0), (14.0, -6.0), 2.0),     # place -> feu de camp
]

PATCHES = [  # sols des stations : (x, y, rayon, couleur)
    (-17.0, 27.0, 6.5, "Leather"),     # cour d'armes en terre battue
    (18.0, 22.0, 6.5, "Leaf.d"),       # herbe piétinée du pas de tir
    (16.0, -8.0, 5.0, "Leather"),      # feu de camp
    (34.0, -27.0, 5.0, "Leather"),     # tableau des quêtes
    (-34.0, -27.0, 8.0, "Stone.l"),    # parvis du panthéon
    (-13.0, 42.0, 6.0, "Gold.d"),      # paille tombée autour de la meule
]

KEEP_FLAT = [(x, y, 9.0) for (x, y, _) in STATIONS.values()] + [(0.0, 44.0, 10.0)]


def main_path_x(py: float) -> float:
    return 2.5 * math.sin((py - 10.0) / 8.0)


def edge_dist(px: float, py: float) -> float:
    """Distance au bord de l'île (positive dedans), bord rond et irrégulier."""
    qx, qy = abs(px) - HX + RC, abs(py) - HY + RC
    out = math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - RC
    return -out + (vnoise(px, py, 9, 1) - 0.5) * 5.0


def surface(px, py, e):
    """(sorte, couleur) du dessus du terrain."""
    plaza = math.hypot(px - PLAZA[0], py - PLAZA[1])
    if plaza <= PLAZA[2]:
        if plaza >= PLAZA[2] - 1 and hnoise(int(px), int(py), 3) > 0.35:
            return "plaza", "Stone"
        # grandes dalles irrégulières, pas de motif en cible
        return "plaza", "Stone" if vnoise(px, py, 3.5, 14) > 0.66 else "Stone.l"
    cx, cy, rx, ry = COURT
    if ((px - cx) / rx) ** 2 + ((py - cy) / ry) ** 2 <= 1.0 and py > -30:
        return "court", "Stone" if hnoise(int(px // 2), int(py // 2), 6) > 0.7 else "Stone.l"
    # avenue principale (arrivée -> place), qui ondule doucement
    if 9.0 <= py <= 47.0:
        d = abs(px - main_path_x(py))
        if d <= 5.0:
            if d > 4.0 and hnoise(int(px), int(py), 5) > 0.55:
                return "grass", "Leaf"     # l'herbe mord le bord du chemin
            return "path", "Leather" if vnoise(px, py, 4, 8) > 0.72 else "Leather.l"
    for a, b, hw in PATHS:
        d = seg_dist(px, py, a, b)
        if d <= hw:
            if d > hw - 1 and hnoise(int(px), int(py), 7) > 0.5:
                return "grass", "Leaf"
            return "path", "Leather.l"
    for x, y, r, col in PATCHES:
        if math.hypot(px - x, py - y) <= r + (vnoise(px, py, 3, 9) - 0.5) * 2.5:
            return "patch", col
    if vnoise(px, py, 11, 7) > 0.64:
        return "grass", "Leaf.d"
    return "grass", "Leaf"


def terrace(px, py, e, kind) -> int:
    """Petites buttes de 1 à 2 studs vers les bords (jamais sur un passage ni une station)."""
    if kind != "grass" or e > 13:
        return 0
    for x, y, r in KEEP_FLAT:
        if math.hypot(px - x, py - y) < r:
            return 0
    m = vnoise(px, py, 13, 2)
    if m > 0.72 and e < 9:
        return 2
    return 1 if m > 0.55 else 0


def ground():
    v = Vox("Lobby_Ground")
    for x in range(-HX - 4, HX + 4):
        for y in range(-HY - 4, HY + 4):
            px, py = x + 0.5, y + 0.5
            e = edge_dist(px, py)
            if e < 0:
                continue
            kind, col = surface(px, py, e)
            top = terrace(px, py, e, kind) - 1          # la surface du sol plat est à z = 0
            v.set(x, y, top, col)
            depth = 3 + int(min(e, 24) * 0.8 + 4 * vnoise(px, py, 6, 3))
            for z in range(top - 1, top - 1 - depth, -1):
                d = top - z
                if d <= 2:
                    c = "Bark"
                elif d <= 5:
                    c = "Leather.d" if d != 4 else "Leather"
                elif d <= 13:
                    c = "Stone" if d % 3 == 0 else "Stone.d"
                else:
                    c = "Stone.dd" if d % 3 else "Stone.d"
                v.set(x, y, z, c)
    return v


def cliff():
    """Falaise étagée au nord : elle encadre la tête, plus basse vers les côtés."""
    v = Vox("Lobby_Cliff")
    for x in range(-HX - 4, HX + 4):
        for y in range(-HY - 4, -30):
            h = cliff_column(x, y)
            for z in range(0, h):
                if z == h - 1:
                    c = "Leaf" if hnoise(x, y, 11) > 0.15 else "Leaf.d"
                elif z % 3 == 2:
                    c = "Stone"
                else:
                    c = "Stone.d"
                v.set(x, y, z, c)
    return v


# ---------------------------------------------------------------------------------------------
# Le héros : la tête de gobelin en pierre (grain 0,5, regarde vers -Y)


def sell(v: Vox, cx, cy, cz, rx, ry, rz, col, p=3.2, zmin=None):
    """Superellipsoïde : grands plans aux coins arrondis (pierre taillée, sans anneaux de sphère)."""
    for x in range(math.floor(cx - rx), math.ceil(cx + rx) + 1):
        for y in range(math.floor(cy - ry), math.ceil(cy + ry) + 1):
            for z in range(math.floor(cz - rz), math.ceil(cz + rz) + 1):
                if zmin is not None and z < zmin:
                    continue
                d = abs((x + 0.5 - cx) / rx) ** p + abs((y + 0.5 - cy) / ry) ** p + abs((z + 0.5 - cz) / rz) ** p
                if d <= 1.0:
                    v.c[(x, y, z)] = col
    return v


def stone_head():
    v = Vox("Lobby_StoneHead")
    sell(v, 0, 3, 34, 28, 20, 20, "Stone")                 # crâne en pierre taillée (28 studs de large)
    sell(v, 0, -3, 14, 27, 20, 15, "Stone", p=3.0, zmin=0)  # museau et mâchoire, jusqu'au sol
    v.box(-24, -15, -22, -18, 24, 30, "Stone")              # pommettes : deux plans nets
    v.box(14, 23, -22, -18, 24, 30, "Stone")
    # arcade sourcilière froncée : plus basse au centre, la droite un cran plus haute (il se méfie)
    for x in range(-27, 27):
        t = abs(x + 0.5) / 27
        top = 42 + round(6 * t) + (1 if x >= 0 else 0)
        v.box(x, x, -26, -19, top - 4, top, "Stone.d")
    # orbites dans l'ombre de l'arcade
    for xa, xb in ((-21, -9), (8, 20)):
        v.carve(xa, xb, -30, -18, 32, 39)
        v.box(xa, xb, -18, -17, 32, 39, "Stone.dd")
    v.box(-21, -9, -19, -19, 33, 39, "Stone.l")             # œil gauche : paupière close
    v.box(-20, -10, -20, -20, 33, 33, "Stone.dd")
    v.box(8, 20, -19, -19, 32, 35, "Cream.d")               # œil droit entrouvert
    v.box(8, 20, -20, -19, 36, 39, "Stone.l")               # paupière lourde
    v.box(12, 13, -20, -20, 32, 33, "Ink")                  # pupille baissée vers les joueurs
    # nez crochu qui tombe sur la bouche
    taper(v, (0, -22, 41), (0, -33, 28), 4.0, 2.0, "Stone")
    v.box(-5, 4, -31, -25, 25, 29, "Stone")
    v.box(-3, -2, -32, -32, 26, 27, "Stone.dd")
    v.box(1, 2, -32, -32, 26, 27, "Stone.dd")
    # bouche ouverte : le portail (15 × 12,5 studs), lèvres épaisses
    carve_ell(v, 0, -14, 0, 15, 30, 25, zmin=0)
    for (x, y, z), c in list(v.c.items()):
        if y > -21 and ((x + 0.5) / 17) ** 2 + ((y + 14.5) / 32) ** 2 + ((z + 0.5) / 27) ** 2 <= 1.0:
            v.c[(x, y, z)] = "Plum.dd"                     # gorge sombre
        elif y <= -18 and ((x + 0.5) / 17.5) ** 2 + ((z + 0.5) / 27.5) ** 2 <= 1.0:
            v.c[(x, y, z)] = "Stone.d"                     # lèvre
    v.box(-16, 15, 6, 8, 0, 25, "Plum.dd")
    # dents du haut, inégales (une ébréchée)
    taper(v, (-9, -21, 19), (-9, -21, 14), 1.5, 0.5, "Cream.d")
    taper(v, (0, -22, 25), (0, -22, 16), 2.0, 1.0, "Cream.d")
    v.carve(1, 2, -24, -20, 16, 17)
    taper(v, (8, -21, 20), (8, -21, 16), 1.2, 0.5, "Cream.d")
    # défenses du bas : une grande, une cassée
    taper(v, (-16, -24, 0), (-18, -28, 17), 2.5, 0.6, "Cream.d")
    taper(v, (15, -24, 0), (16, -26, 10), 2.2, 1.6, "Cream.d")
    v.paint(-20, -13, -30, -21, 0, 2, "Cream.dd")
    v.paint(12, 19, -30, -21, 0, 2, "Cream.dd")
    # oreilles effilées ; la droite tombe et porte une encoche, la gauche un anneau d'or
    for s, tip_z, droop in ((-1, 54, 0), (1, 45, 1)):
        n = 26
        for i in range(n + 1):
            t = i / n
            cx = s * (25 + 27 * t)
            cy = 1 + 4 * t
            cz = 40 + (tip_z - 40) * t - droop * 6 * t * t
            hz = 9 * (1 - t) + 0.6
            hy = 3.5 * (1 - t) + 1.2
            for y in range(round(cy - hy), round(cy + hy)):
                for z in range(round(cz - hz), round(cz + hz)):
                    inner = y <= round(cy - hy) + 1 and abs(z - cz) < hz * 0.6 and t < 0.85
                    v.set(round(cx), y, z, "Stone.d" if inner else "Stone")
    v.carve(36, 39, -6, 8, 46, 50)                         # encoche mordue
    ear = [k for k in v.c if k[0] == -36]
    low = min(z for (_, _, z) in ear)
    ey = min(y for (_, y, z) in ear if z == low)
    for dx, dz in [(0, 1), (0, 2), (0, 3), (1, 4), (2, 4), (3, 3), (3, 2), (3, 1)]:
        v.set(-37 + dx, ey, low - dz, "Gold.d")
    v.set(-37, ey, low, "Gold.d")
    # la langue : un tapis qui sort de la bouche jusqu'au pad Public
    v.box(-8, 7, -42, -6, 0, 1, "Tomato.d")
    v.ell(0, -42, 0, 8, 5, 2, "Tomato.d", zmin=0)
    v.box(-1, 0, -44, -10, 1, 1, "Tomato.dd")
    # fissures, mousse, pousse d'arbre sur le crâne
    paint_near(v, (-8, -17, 48), (2, -14, 54), "Stone.dd", 1.0)
    paint_near(v, (19, -17, 22), (25, -12, 14), "Stone.dd", 1.0)
    v.paint_if(lambda x, y, z, c: c == "Stone" and z > 50 and (x, y, z + 1) not in v.c
               and vnoise(x, y, 6, 12) > 0.5, "Leaf.dd")
    v.paint_if(lambda x, y, z, c: c == "Stone" and abs(x) > 28 and (x, y, z + 1) not in v.c
               and hnoise(x, y, 13) > 0.6, "Leaf.dd")
    v.box(5, 6, 6, 7, 53, 62, "Bark")
    v.ell(5.5, 6.5, 65, 5, 5, 4, "Leaf.d")
    v.ell(5.5, 6.5, 68, 3, 3, 2, "Leaf")
    v.shade_rows(0, 1, "d", only={"Stone"})
    return v


def portal_swirl():
    """Le tourbillon au fond de la gorge (objet séparé : il est lumineux). Grain 0,5."""
    v = Vox("Lobby_PortalSwirl")
    cols = ["Grape.d", "Royal.d", "Plum"]
    for x in range(-15, 15):
        for z in range(0, 25):
            dx, dz = (x + 0.5) / 14.5, (z + 0.5) / 24.5
            if dx * dx + dz * dz > 1.0:
                continue
            r = math.hypot(x + 0.5, (z + 0.5) * 0.6)
            a = math.atan2(z + 0.5, x + 0.5)
            band = int(a / math.pi * 3 + r / 3.2) % 3
            v.set(x, 4, z, cols[band])
    return v


def pad(n: int, r: float):
    """Pad de départ : dalle ronde avec n silhouettes incrustées (pas de texte). Grain 0,5."""
    v = Vox(f"Lobby_Pad{n}")
    R = r * 2
    v.cyl(0, 0, 0, 0, R, "Stone")
    v.paint_if(lambda x, y, z, c: math.hypot(x + 0.5, y + 0.5) > R - 1.2, "Stone.dd")
    spots = {1: [(0, 0)], 2: [(-2.5, 0), (2.5, 0)], 4: [(-4, -3), (4, -3), (-4, 3.5), (4, 3.5)]}[n]
    for sx, sy in spots:
        sx, sy = round(sx), round(sy)
        v.box(sx - 1, sx, sy - 2, sy - 1, 0, 0, "Cream.d")       # tête
        v.box(sx - 2, sx + 1, sy, sy + 1, 0, 0, "Cream.d")       # épaules
    return v


# ---------------------------------------------------------------------------------------------
# Stations (grain 0,25 sauf mention ; avant = -Y)


def knight_yard():
    v = Vox("Lobby_KnightYard")
    # râtelier d'armes au fond
    v.box(-21, -20, 8, 9, 0, 19, "Bark")
    v.box(-7, -6, 8, 9, 0, 19, "Bark")
    v.box(-21, -6, 8, 9, 18, 19, "Bark")
    v.box(-21, -6, 8, 9, 4, 4, "Bark.d")
    for i, (x, top) in enumerate([(-18, 17), (-15, 15), (-12, 17), (-9, 12)]):
        v.box(x, x, 6, 6, 3, top - 5, "Steel")
        v.box(x - 1, x + 1, 6, 6, top - 4, top - 4, "Bark.d")
        v.box(x, x, 6, 6, top - 3, top - 1, "Leather")
        v.set(x, 6, top, "Gold.d" if i == 0 else "Bark.d")
    # mannequin d'entraînement : sac de paille, cocotte en guise de casque, épée plantée
    v.box(9, 10, -1, 0, 0, 12, "Bark")
    v.ell(10, 0, 17, 5, 3.5, 6, "Leather")
    v.box(3, 17, -1, 0, 19, 20, "Leather.d")
    v.ell(10, 0, 26, 3.5, 3.5, 3.5, "Leather")
    for (x, z) in [(8, 26), (9, 27), (8, 27), (9, 26), (11, 26), (12, 27), (11, 27), (12, 26)]:
        v.set(x, -4, z, "Ink")                              # yeux en croix
    v.box(9, 12, -4, -4, 24, 24, "Bark.d")
    v.cyl(10, 0, 28, 31, 4.5, "Steel.d")
    v.box(5, 6, -1, 0, 30, 30, "Steel.dd")
    v.box(14, 15, -1, 0, 30, 30, "Steel.dd")
    v.line((15, -6, 13), (7, 3, 20), "Steel")
    v.box(15, 16, -7, -6, 12, 13, "Leather")
    # enclume sur une souche
    v.cyl(-12, -8, 0, 6, 4, "Bark")
    v.box(-15, -9, -10, -7, 8, 10, "Steel.dd")
    v.box(-14, -10, -10, -7, 7, 7, "Steel.dd")
    v.box(-18, -16, -9, -8, 9, 10, "Steel.dd")
    # bouclier posé contre la souche
    v.ell(-3, -12, 6, 4, 0.7, 5.5, "Royal.d", zmin=0)
    v.set(-3, -13, 6, "Gold.d")
    pennant(v, 20, 10, 40, "Royal.d")
    return v


def target(v: Vox, cx, cz, R, y=6):
    for x in range(math.floor(cx - R), math.ceil(cx + R) + 1):
        for z in range(math.floor(cz - R), math.ceil(cz + R) + 1):
            r = math.hypot(x + 0.5 - cx, z + 0.5 - cz)
            if r > R:
                continue
            ring = min(3, int(r / (R / 4)))
            v.set(x, y, z, ["Tomato", "Cream.d", "Tomato.d", "Cream.d"][ring])
            v.set(x, y + 1, z, "Leather.d")
    v.line((round(cx - R * 0.6), y + 2, 0), (round(cx - R * 0.4), y + 1, round(cz)), "Bark")
    v.line((round(cx + R * 0.6), y + 2, 0), (round(cx + R * 0.4), y + 1, round(cz)), "Bark")
    v.line((round(cx), y + 7, 0), (round(cx), y + 2, round(cz - 1)), "Bark")


def arrow(v: Vox, x, y, z, dy=-1, length=6, fly="Leaf.d"):
    v.box(x, x, min(y, y + dy * length), max(y, y + dy * length), z, z, "Bark")
    e = y + dy * length
    v.box(x - 1, x + 1, e, e, z, z, fly)
    v.box(x, x, e, e, z - 1, z + 1, fly)


def archer_range():
    v = Vox("Lobby_ArcherRange")
    target(v, -14, 10, 8)
    target(v, 2, 9, 6)
    target(v, 15, 7, 4.5)
    arrow(v, -11, 5, 13)
    arrow(v, -17, 5, 7)
    arrow(v, 16, 5, 8)
    # une carotte en plein dans le mille (le carquois de l'Archer en porte une)
    v.box(2, 2, -1, 5, 9, 9, "Ember")
    v.box(1, 3, 0, 1, 8, 10, "Ember")
    v.line((2, -2, 9), (1, -4, 11), "Leaf.d")
    v.line((2, -2, 9), (3, -4, 11), "Leaf.d")
    # flèches ratées plantées dans l'herbe
    for x, y in [(-20, -4), (9, 1), (21, 3)]:
        v.line((x, y, 0), (x + 1, y + 2, 4), "Bark")
        v.box(x + 1, x + 1, y + 2, y + 2, 4, 5, "Leaf.d")
    # tonneau de flèches et rondin qui marque la ligne de tir
    v.cyl(-20, -7, 0, 8, 3, "Bark")
    v.paint_if(lambda x, y, z, c: c == "Bark" and z in (2, 6) and math.hypot(x + 20.5, y + 7.5) > 2, "Bark.d")
    for dx, dy, h in [(-1, 0, 13), (0, -1, 12), (1, 1, 14)]:
        v.box(-20 + dx, -20 + dx, -7 + dy, -7 + dy, 9, h, "Bark")
        v.set(-20 + dx, -7 + dy, h + 1, "Leaf.d")
    v.box(-16, 16, -12, -11, 0, 1, "Bark")
    pennant(v, 22, -9, 36, "Leaf.d", side=-1)
    return v


def mage_tower():
    """Tour penchée au toit en chapeau de mage (le chapeau de la classe, en grand)."""
    v = Vox("Lobby_MageTower")
    for z in range(0, 42):
        lean = z // 12
        r = 13 if z < 14 else 12
        for x in range(-r - 1 + lean, r + 1 + lean):
            for y in range(-r - 1, r + 1):
                if math.hypot(x + 0.5 - lean, y + 0.5) > r:
                    continue
                if z < 14:
                    c = "Stone.dd" if hnoise(x // 2, z // 2, 21) > 0.75 or z == 0 else "Stone.d"
                elif z in (28, 29) or abs(x + 0.5 - lean) < 1 or abs(y + 0.5) < 1:
                    c = "Bark"
                else:
                    c = "Cream.d"
                v.set(x, y, z, c)
    lean = 3
    v.cyl(lean, 0, 42, 43, 16, "Grape.dd")                  # bord du chapeau
    for z in range(44, 68):
        t = (z - 44) / 24
        r = 14 * (1 - t) + 0.6
        off = lean + 10 * t * t                               # pointe pliée, comme le chapeau
        for x in range(math.floor(off - r), math.ceil(off + r) + 1):
            for y in range(math.floor(-r), math.ceil(r) + 1):
                if math.hypot(x + 0.5 - off, y + 0.5) <= r:
                    v.set(x, y, z, "Plum" if z in (46, 47) else "Grape.d")
    # porte et fenêtres (lumière chaude)
    v.carve(-3, 2, -14, -10, 0, 10)
    v.box(-3, 2, -11, -11, 0, 10, "Bark")
    v.set(1, -12, 5, "Gold.d")
    v.carve(0, 3, -14, -10, 32, 37)
    v.box(0, 3, -11, -11, 32, 37, "Gold.d")
    v.carve(11, 15, -2, 1, 20, 24)
    v.box(11, 11, -2, 1, 20, 24, "Gold.d")
    # chaudron qui bouillonne et pile de grimoires
    v.cyl(15, -16, 1, 6, 5, "Ink")
    v.cyl(15, -16, 6, 6, 4, "Leaf.d")
    v.set(14, -17, 7, "Leaf.d")
    v.set(17, -15, 8, "Leaf.d")
    for (x, y) in [(11, -20), (19, -20), (15, -11)]:
        v.box(x, x, y, y, 0, 1, "Ink")
    v.box(-12, -8, -19, -16, 0, 1, "Tomato.d")
    v.box(-11, -8, -18, -16, 2, 3, "Royal.d")
    v.box(-12, -9, -19, -17, 4, 4, "Leaf.dd")
    return v


def crate(v: Vox, x0, y0, z0, s, stripe, lock=True):
    x1, y1, z1 = x0 + s - 1, y0 + s - 1, z0 + s - 1
    for x in range(x0, x1 + 1):
        for y in range(y0, y1 + 1):
            for z in range(z0, z1 + 1):
                edges = (x in (x0, x1)) + (y in (y0, y1)) + (z in (z0, z1))
                c = "Bark" if edges >= 2 else "Leather.d"
                if z == z0 + s // 2 and edges >= 1:
                    c = stripe
                v.set(x, y, z, c)
    if lock:
        mx = x0 + s // 2
        v.box(mx - 1, mx, y0 - 1, y0 - 1, z0 + s // 2 - 2, z0 + s // 2, "Steel.d")
        v.set(mx, y0 - 1, z0 + s // 2 - 1, "Ink")


def crate_cart():
    """Les 5 classes à débloquer arrivent en caisses cadenassées. Quelque chose regarde dehors."""
    v = Vox("Lobby_ClassCrates")
    v.box(-20, 19, -10, 9, 8, 10, "Bark")
    v.box(-20, 19, -10, -10, 11, 12, "Leather.d")
    v.box(-20, 19, 9, 9, 11, 12, "Leather.d")
    for wx in (-12, 10):
        for wy in (-12, 11):
            for x in range(wx - 7, wx + 8):
                for z in range(0, 15):
                    r = math.hypot(x + 0.5 - wx, z + 0.5 - 7)
                    if r <= 7 and (r >= 5.5 or abs(x + 0.5 - wx) < 1 or abs(z + 0.5 - 7) < 1):
                        v.set(x, wy, z, "Bark.d")
            v.box(wx - 1, wx, wy, wy, 6, 7, "Steel.d")
    v.line((20, -6, 10), (34, -6, 3), "Bark")
    v.line((20, 5, 10), (34, 5, 3), "Bark")
    crate(v, -19, -9, 11, 14, "Tomato.d")
    crate(v, -3, -8, 11, 11, "Sky.d")
    crate(v, 9, -6, 11, 9, "Ember.d", lock=False)
    crate(v, -16, -6, 25, 9, "Steel.d")
    crate(v, -31, -15, 0, 10, "Gold.d")
    # bâche sur une caisse : une pointe dépasse (un chapeau ? une corne ?)
    v.paint_if(lambda x, y, z, c: -3 <= x <= 7 and -8 <= y <= 2 and z >= 17, "Plum.d")
    taper(v, (2, -3, 22), (4, -2, 30), 2.5, 0.5, "Plum.d")
    # des yeux dans le noir, par une planche cassée
    v.carve(10, 15, -6, -5, 15, 17)
    v.box(10, 15, -5, -5, 15, 17, "Ink")
    v.box(11, 11, -6, -6, 16, 16, "Cream")
    v.box(14, 14, -6, -6, 16, 16, "Cream")
    return v


def haystack():
    """Meule d'arrivée (grain 0,5) : on revient de run en tombant dedans. Deux jambes dépassent."""
    v = Vox("Lobby_Haystack")
    v.ell(0, 0, 0, 12, 10, 12, "Gold.d", zmin=0)
    v.paint_if(lambda x, y, z, c: hnoise(x // 2, z, 31) > 0.7, "Leather")
    v.paint_if(lambda x, y, z, c: z <= 1, "Leather.d")
    v.carve(-3, 2, -2, 1, 10, 13)
    v.line((-1, 0, 10), (-4, 0, 16), "Royal.d", r=1)
    v.line((1, 0, 10), (3, 0, 15), "Royal.d", r=1)
    v.box(-6, -3, -2, 1, 17, 18, "Leather")
    v.box(2, 5, -2, 1, 16, 17, "Leather")
    for x, y in [(-14, -4), (13, 3), (-9, 9), (11, -9), (4, 12)]:
        v.box(x, x + 1, y, y, 0, 0, "Gold.d")
    v.line((13, -3, 0), (8, -3, 12), "Bark")
    v.line((13, 1, 0), (8, 1, 12), "Bark")
    for i in range(1, 6):
        v.box(13 - i, 13 - i, -2, 0, round(i * 2.4), round(i * 2.4), "Bark")
    return v


def critter_pen():
    """Enclos des compagnons (grain 0,5). Une clôture a été mordue, la niche a son os."""
    v = Vox("Lobby_CritterPen")
    x0, x1, y0, y1 = -20, 19, -22, 21
    gate = range(-3, 3)
    broken = range(6, 12)
    for x in range(x0, x1 + 1):
        for y in range(y0, y1 + 1):
            if x not in (x0, x1) and y not in (y0, y1):
                continue
            if x == x1 and y in gate:
                continue
            if x == x0 and y in broken:
                if y == 6:
                    v.box(x, x, y, y, 0, 2, "Bark.d")
                continue
            post = (x - x0) % 6 == 0 and (y - y0) % 6 == 0 or (x in (x0, x1) and (y - y0) % 6 == 0) \
                or (y in (y0, y1) and (x - x0) % 6 == 0)
            if post:
                v.box(x, x, y, y, 0, 5, "Bark")
            else:
                v.set(x, y, 2, "Leather.d")
                v.set(x, y, 4, "Leather.d")
    for y in (-4, 3):
        v.box(x1, x1, y, y, 0, 8, "Bark")
    v.box(x1, x1, -4, 3, 8, 8, "Bark")
    v.box(x1, x1, -2, 1, 9, 9, "Cream.d")                  # un os en guise d'enseigne
    v.box(x1, x1, -3, -3, 9, 10, "Cream.d")
    v.box(x1, x1, 2, 2, 9, 10, "Cream.d")
    v.carve(-20, -20, 9, 9, 4, 4)                          # marque de dents dans la lisse
    # niche
    v.box(-17, -10, 13, 19, 0, 6, "Bark")
    v.carve(-15, -12, 13, 14, 0, 4)
    v.box(-15, -12, 14, 14, 0, 4, "Ink")
    for i in range(5):
        v.box(-18 + i, -9 - i, 12, 20, 7 + i, 7 + i, "Tomato.dd")
    v.box(-15, -12, 10, 10, 0, 0, "Cream.d")
    v.set(-16, 10, 0, "Cream.d")
    v.set(-11, 10, 0, "Cream.d")
    # abreuvoir et foin
    v.box(5, 13, 15, 18, 0, 2, "Bark")
    v.box(6, 12, 16, 17, 2, 2, "Sky.d")
    v.ell(12, -15, 0, 4, 3, 3, "Gold.d", zmin=0)
    return v


def glam_stall():
    """Boutique de Gob : étal rayé, chapeaux en vitrine, miroir, sac d'XP volée (grain 0,25)."""
    v = Vox("Lobby_GlamShop")
    v.box(-24, 23, -14, 13, 0, 0, "Bark.d")
    for x, y in [(-23, -13), (21, -13), (-23, 11), (21, 11)]:
        v.box(x, x + 1, y, y + 1, 1, 38, "Bark")
    v.box(-22, 21, 12, 13, 1, 30, "Leather.d")
    v.paint_if(lambda x, y, z, c: c == "Leather.d" and y >= 12 and z % 6 == 0, "Bark.d")
    for zs in (13, 23):
        v.box(-20, 19, 9, 11, zs, zs, "Bark")
    # chapeaux en vitrine
    v.cyl(-15, 10, 14, 19, 2, "Ink")
    v.cyl(-15, 10, 14, 14, 3, "Ink")
    v.box(-17, -14, 8, 8, 15, 15, "Tomato.d")
    for z in range(14, 21):
        r = 3 * (1 - (z - 14) / 7) + 0.5
        v.cyl(-6 + (z - 14) // 3, 10, z, z, r, "Grape.d")
    v.cyl(4, 10, 14, 16, 2.5, "Steel.d")
    v.box(1, 2, 10, 10, 16, 16, "Steel.dd")
    v.box(6, 7, 10, 10, 16, 16, "Steel.dd")
    for x in range(10, 16):
        v.box(x, x, 9, 11, 24, 25, "Gold.d")
    for x in (10, 12, 15):
        v.set(x, 9, 26, "Gold.d")
    v.cyl(-12, 10, 24, 26, 2.5, "Ember.d")
    v.set(-12, 10, 27, "Cream.d")
    # comptoir
    v.box(-20, 19, -12, -8, 1, 11, "Bark")
    v.paint_if(lambda x, y, z, c: c == "Bark" and y == -12 and 1 <= z <= 11 and x % 5 == 0, "Bark.d")
    v.box(-21, 20, -13, -7, 12, 12, "Leather")
    # auvent rayé qui descend vers l'avant, bord festonné
    for y in range(-20, 14):
        z = 34 + (y + 20) * 8 // 34
        for x in range(-26, 26):
            c = "Tomato.d" if (x // 4) % 2 == 0 else "Cream.d"
            v.set(x, y, z, c)
            v.set(x, y, z + 1, c)
    for x in range(-26, 26):
        if (x // 4) % 2 == 0:
            v.set(x, -20, 33, "Tomato.d")
    # enseigne : un haut-de-forme géant, pas de texte
    v.cyl(0, 6, 44, 44, 10, "Ink")
    v.cyl(0, 6, 45, 58, 6.5, "Ink")
    v.cyl(0, 6, 46, 48, 6.8, "Tomato.d")
    # miroir sur pied
    v.box(16, 23, -17, -16, 0, 24, "Bark")
    v.box(17, 22, -18, -18, 3, 22, "Steel.l")
    # sac d'XP volée qui déborde
    v.ell(-21, -19, 0, 4.5, 4, 6, "Leather", zmin=0)
    v.box(-22, -20, -20, -18, 6, 7, "Bark")
    for x, y, h in [(-15, -21, 3), (-17, -25, 2), (-13, -18, 3), (-22, -20, 9)]:
        v.box(x, x + 1, y, y + 1, h - 3 if h > 3 else 0, h, "Sky")
        v.set(x, y, h + 1, "Cream.d")
    return v


def hall_of_fame():
    """Podium et grande stèle d'ardoise pour les classements (grain 0,25)."""
    v = Vox("Lobby_HallOfFame")
    v.box(-28, 27, 14, 19, 0, 50, "Stone.d")
    carve_ell(v, -28, 16, 50, 6, 10, 6)
    carve_ell(v, 28, 16, 50, 6, 10, 6)
    v.box(-25, -2, 13, 13, 6, 45, "Plum.dd")
    v.box(1, 24, 13, 13, 6, 45, "Plum.dd")
    for z in range(40, 8, -4):
        for xa, xb in ((-23, -4), (3, 22)):
            v.box(xa, xb - (z % 8) // 2 * 3, 12, 12, z, z, "Plum.d")
    v.box(-28, 27, 14, 19, 0, 1, "Stone.dd")
    # coupe au sommet
    v.box(-1, 0, 16, 17, 51, 53, "Gold.d")
    v.ell(0, 17, 57, 4.5, 3.5, 4, "Gold.d", zmin=54)
    v.box(-6, -5, 16, 17, 56, 59, "Gold.d")
    v.box(5, 6, 16, 17, 56, 59, "Gold.d")
    carve_ell(v, 0, 17, 59, 3, 2.5, 2, zmin=58)
    # podium 1-2-3 (liseré or, acier, cuir)
    for (xa, xb, h, trim) in [(-6, 5, 16, "Gold.d"), (-20, -9, 10, "Steel.d"), (8, 19, 6, "Leather")]:
        v.box(xa, xb, -6, 5, 0, h, "Stone")
        v.box(xa, xb, -6, 5, h, h, trim)
        v.box(xa + 1, xb - 1, -5, 4, h, h, "Stone.l")
        v.box(xa, xb, -6, 5, 0, 0, "Stone.d")
    return v


def quest_board():
    """Tableau des quêtes sous un petit toit, avis de recherche, hibou facteur (grain 0,25)."""
    v = Vox("Lobby_QuestBoard")
    v.box(-22, -20, 0, 1, 0, 40, "Bark")
    v.box(19, 21, 0, 1, 0, 40, "Bark")
    v.box(-20, 19, 0, 1, 12, 34, "Leather.d")
    v.box(-20, 19, -1, 1, 11, 11, "Bark")
    v.box(-20, 19, -1, 1, 35, 35, "Bark")
    for i in range(6):
        v.box(-25, 24, -5 + i, 6 - i, 40 + i, 40 + i, "Bark.d")
    for (xa, xb, za, zb) in [(-17, -9, 23, 31), (-6, 1, 26, 32), (5, 15, 21, 31), (-15, -4, 14, 20), (-1, 6, 14, 19)]:
        v.box(xa, xb, -1, -1, za, zb, "Cream.d")
        for z in range(za + 1, zb - 1, 2):
            v.box(xa + 1, xb - 2 - (z % 3), -2, -2, z, z, "Stone.d")
        v.set((xa + xb) // 2, -2, zb, "Tomato.d")
    # avis de recherche : une tête de gobelin
    v.box(8, 12, -2, -2, 24, 27, "Lime.d")
    v.set(9, -3, 26, "Ink")
    v.set(11, -3, 26, "Ink")
    v.box(8, 12, -2, -2, 28, 28, "Tomato.d")
    # hibou facteur sur le toit
    v.ell(10, 0, 49, 3, 3, 4, "Leather")
    v.box(9, 11, -3, -3, 46, 49, "Cream.d")
    v.box(8, 9, -3, -3, 50, 51, "Cream")
    v.box(11, 12, -3, -3, 50, 51, "Cream")
    v.set(9, -4, 50, "Ink")
    v.set(11, -4, 50, "Ink")
    v.set(10, -4, 49, "Gold.d")
    v.box(8, 8, 0, 0, 53, 54, "Leather.d")
    v.box(12, 12, 0, 0, 53, 54, "Leather.d")
    v.box(13, 15, -1, 1, 45, 48, "Bark.d")
    v.box(14, 15, -1, -1, 49, 49, "Cream.d")
    for i, (x, y) in enumerate([(-14, -6), (-12, -7), (16, -5)]):
        v.box(x, x + 2, y, y + 1, 0, 1 + i % 2, "Cream.d")
    return v


def campfire():
    v = Vox("Lobby_Campfire")
    for k in range(9):
        a = k / 9 * math.tau
        x, y = round(7 * math.cos(a)), round(7 * math.sin(a))
        v.box(x - 1, x + 1, y - 1, y + 1, 0, 1 + k % 2, "Stone.d")
    v.line((-5, -2, 1), (5, 2, 1), "Bark", r=1)
    v.line((-3, 4, 1), (3, -4, 1), "Bark", r=1)
    v.box(-4, 3, -4, 3, 0, 0, "Ink.l")
    return v


def fire():
    v = Vox("Lobby_Fire")
    taper(v, (0, 0, 2), (0, 0, 10), 3.0, 0.5, "Ember")
    taper(v, (-2, 1, 2), (-3, 1, 7), 1.5, 0.5, "Ember")
    taper(v, (2, -1, 2), (3, -1, 8), 1.5, 0.5, "Gold")
    return v


def log_bench():
    v = Vox("Lobby_LogBench")
    v.box(-12, 11, -2, 1, 0, 3, "Bark")
    v.box(-12, -12, -2, 1, 0, 3, "Leather")
    v.box(11, 11, -2, 1, 0, 3, "Leather")
    return v


# ---------------------------------------------------------------------------------------------
# Végétation et fond (grain 0,5 ; nuages et îlots au grain 1)


def tree_round(r: int = 8, seed: int = 0):
    v = Vox(f"Lobby_TreeRound{r}_{seed}")
    h = r + 3
    v.box(-1, 0, -1, 0, 0, h + 2, "Bark")
    v.box(-2, 1, -2, 1, 0, 0, "Bark.d")
    v.ell(0, 0, h + r * 0.9, r, r, r * 0.8, "Leaf")
    v.ell(0.5 * (seed % 3 - 1), 0, h + r * 1.4, r * 0.6, r * 0.6, r * 0.45, "Leaf.l")
    v.ell(r * 0.55, r * 0.2 - seed % 2, h + r * 0.7, r * 0.55, r * 0.55, r * 0.5, "Leaf")
    v.paint_if(lambda x, y, z, c: c.startswith("Leaf") and z < h + r * 0.55, "Leaf.d")
    return v


def tree_pine(h: int = 28):
    v = Vox(f"Lobby_TreePine{h}")
    v.box(-1, 0, -1, 0, 0, 5, "Bark")
    z = 4
    r = h // 4
    while r >= 1:
        for k in range(3):
            rr = r - k * 0.6
            v.cyl(0, 0, z + k, z + k, rr, "Leaf.d" if k == 0 else "Leaf")
        z += 3
        r -= 1
    v.box(-1, 0, -1, 0, z, z + 1, "Leaf")
    return v


def bush(r: float = 3.5):
    v = Vox(f"Lobby_Bush{r}")
    v.ell(0, 0, 0, r, r * 0.9, r * 0.8, "Leaf", zmin=0)
    v.ell(r * 0.5, 0, 0, r * 0.7, r * 0.7, r * 0.6, "Leaf", zmin=0)
    v.paint_if(lambda x, y, z, c: z == 0, "Leaf.d")
    return v


def rock(r: float = 4.0, seed: int = 0):
    v = Vox(f"Lobby_Rock{r}_{seed}")
    v.ell(0, 0, 0, r, r * 0.75, r * 0.8, "Stone", zmin=0)
    v.ell(-r * 0.3, 0.5 * seed, r * 0.6, r * 0.6, r * 0.5, r * 0.4, "Stone.l", zmin=0)
    v.paint_if(lambda x, y, z, c: z == 0, "Stone.d")
    return v


def flowers(seed: int = 0):
    """Touffe basse de fleurs (grain 0,25) pour les jointures herbe / chemin."""
    v = Vox(f"Lobby_Flowers{seed}")
    v.ell(0, 0, 0, 4, 3, 1.6, "Leaf.d", zmin=0)
    cols = ["Cream.d", "Grape.d", "Tomato.d"]
    for i in range(4):
        x = round((hnoise(i, seed, 41) - 0.5) * 6)
        y = round((hnoise(seed, i, 42) - 0.5) * 4)
        v.set(x, y, 2, cols[(i + seed) % 3])
    return v


def cloud(seed: int = 0):
    v = Vox(f"Lobby_Cloud{seed}")
    for i in range(4):
        cx = (hnoise(i, seed, 51) - 0.5) * 26
        cy = (hnoise(seed, i, 52) - 0.5) * 8
        r = 6 + 4 * hnoise(i, i, seed)
        v.ell(cx, cy, 0, r, r * 0.8, r * 0.5, "Cream.l", zmin=-2)
    v.paint_if(lambda x, y, z, c: z <= -1, "Cream.d")
    return v


def islet(seed: int = 0):
    v = Vox(f"Lobby_Islet{seed}")
    for x in range(-5, 5):
        for y in range(-4, 4):
            e = min(x + 5, 4 - x, y + 4, 3 - y)
            if e == 0 and hnoise(x, y, seed) < 0.4:
                continue
            for z in range(-2 - e * 2, 0):
                v.set(x, y, z, "Leaf.d" if z == -1 else ("Bark" if z == -2 else "Stone.d"))
    v.box(0, 0, 0, 0, 0, 2, "Bark")
    v.ell(0.5, 0.5, 4, 2.5, 2.5, 2, "Leaf.d")
    return v


# ---------------------------------------------------------------------------------------------
# Carte naturelle (2e retour de Clément, 5 nov.) : sol lisse, chemins de terre, forêt, falaise de rochers

SE_P = 4.0   # bord de l'île : superellipse (carré aux coins très arrondis)


def se_point(theta: float):
    c, s_ = math.cos(theta), math.sin(theta)
    return (HX * math.copysign(abs(c) ** (2 / SE_P), c), HY * math.copysign(abs(s_) ** (2 / SE_P), s_))


def rho(px: float, py: float) -> float:
    """0 au centre, 1 sur le bord de l'île."""
    return ((abs(px) / HX) ** SE_P + (abs(py) / HY) ** SE_P) ** (1 / SE_P)


def _ss(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def flat_mask(px: float, py: float) -> float:
    """1 là où le sol reste plat (chemins, place, parvis, stations), 0 ailleurs, avec un fondu."""
    m = 0.0
    for x, y, r in KEEP_FLAT:
        m = max(m, 1 - _ss(r, r + 6, math.hypot(px - x, py - y)))
    if 8 <= py <= 48:
        m = max(m, 1 - _ss(5, 9, abs(px - main_path_x(py))))
    for a, b, hw in PATHS:
        m = max(m, 1 - _ss(hw, hw + 4, seg_dist(px, py, a, b)))
    m = max(m, 1 - _ss(PLAZA[2], PLAZA[2] + 5, math.hypot(px - PLAZA[0], py - PLAZA[1])))
    cx, cy, rx, ry = COURT
    m = max(m, 1 - _ss(1.0, 1.4, math.sqrt(((px - cx) / rx) ** 2 + ((py - cy) / ry) ** 2)))
    return m


def nat_height(px: float, py: float) -> float:
    r = rho(px, py)
    hills = 5.0 * _ss(0.55, 0.92, r) * (0.3 + 0.7 * vnoise(px, py, 15, 2))
    roll = 0.7 * (vnoise(px, py, 7, 3) - 0.5)
    return (hills + roll) * (1 - flat_mask(px, py))


def dirt_weight(px: float, py: float):
    """(poids de terre 0..1, poids de « clairière » pour la place et le parvis) avec des bords doux et
    un peu irréguliers."""
    wob = (vnoise(px, py, 2.5, 26) - 0.5) * 1.6
    w = 0.0
    if 8 <= py <= 48:
        w = max(w, 1 - _ss(3.6, 5.2, abs(px - main_path_x(py)) + wob))
    for a, b, hw in PATHS:
        w = max(w, 1 - _ss(hw - 1.2, hw + 0.4, seg_dist(px, py, a, b) + wob))
    clearing = 1 - _ss(PLAZA[2] - 1.5, PLAZA[2] + 0.5, math.hypot(px - PLAZA[0], py - PLAZA[1]) + wob)
    cx, cy, rx, ry = COURT
    clearing = max(clearing, 1 - _ss(0.85, 1.0, math.sqrt(((px - cx) / rx) ** 2 + ((py - cy) / ry) ** 2) + wob / 20))
    for x, y, r, col in PATCHES:
        if not col.startswith("Leaf"):
            clearing = max(clearing, 1 - _ss(r - 1.5, r + 0.5, math.hypot(px - x, py - y) + wob))
    return w, clearing


def nat_color(px: float, py: float):
    from nature import mixc

    g = mixc(tone("Leaf"), tone("Leaf.l"), 0.5 * vnoise(px, py, 9, 21))
    g = mixc(g, tone("Leaf.d"), 0.5 * _ss(0.55, 0.85, vnoise(px, py, 13, 22)))
    w, clearing = dirt_weight(px, py)
    path = mixc(tone("Leather.d"), tone("Bark"), 0.45 * vnoise(px, py, 5, 23))
    floor = mixc(tone("Leather"), tone("Leather.d"), 0.6 * vnoise(px, py, 4, 24))
    c = mixc(g, floor, clearing)
    return mixc(c, path, w * (1 - clearing * 0.6))


def natural_island():
    """Dessus lisse en anneaux qui suivent le bord, flanc rocheux qui se resserre en dessous."""
    import nature as N

    R, S = 110, 380
    edge = [se_point(j / S * math.tau) for j in range(S)]
    verts, cols = [], []

    def add(p, c):
        verts.append(p)
        cols.append(c)
        return len(verts) - 1

    add((0.0, 0.0, nat_height(0.0, 0.0)), nat_color(0.0, 0.0))
    for i in range(1, R + 1):
        r = i / R
        for j in range(S):
            px, py = edge[j][0] * r, edge[j][1] * r
            add((px, py, nat_height(px, py)), nat_color(px, py))

    def vid(i, j):
        return 0 if i == 0 else 1 + (i - 1) * S + (j % S)

    faces = [(0, vid(1, j), vid(1, j + 1)) for j in range(S)]
    faces += [(vid(i, j), vid(i + 1, j), vid(i + 1, j + 1), vid(i, j + 1)) for i in range(1, R) for j in range(S)]
    n_top = len(faces)
    prev = [vid(R, j) for j in range(S)]
    hb = [verts[k][2] for k in prev]
    levels = 16
    for k in range(1, levels + 1):
        t = k / levels
        ring = []
        for j in range(S):
            ex, ey = edge[j]
            bump = 0.93 + 0.1 * hnoise(j // 5, k, 31)
            shrink = 1.012 if k == 1 else (1 - t ** 1.6) * 0.96 * bump + 0.04
            z = hb[j] * max(0.0, 1 - k / 2) - 1.0 - (k - 1) * 1.5 - 6 * t * t
            if k == 1:
                c = tone("Leaf.d")
            elif k <= 3:
                c = tone("Bark")
            elif k <= 5:
                c = tone("Leather.d")
            else:
                c = tone("Stone.dd") if k % 3 == 0 else tone("Stone.d")
            ring.append(add((ex * shrink, ey * shrink, z), c))
        faces += [(prev[j], ring[j], ring[(j + 1) % S], prev[(j + 1) % S]) for j in range(S)]
        prev = ring
    bottom = add((0.0, 0.0, verts[prev[0]][2] - 4.0), tone("Stone.dd"))
    faces += [(prev[j], bottom, prev[(j + 1) % S]) for j in range(S)]
    return N.mesh_object("Lobby_NaturalGround", verts, faces, cols, smooth_faces=lambda i: i < n_top)


def natural_dressing():
    """Falaise de rochers derrière la tête, forêt en lisière, arbres et buissons, pierres de gué."""
    import nature as N

    # falaise : gros rochers à facettes sur l'arrière, plus hauts près de la tête (ils l'encadrent)
    for i, deg in enumerate(range(196, 346, 8)):
        th = math.radians(deg)
        ex, ey = se_point(th)
        x, y = ex * 0.9, ey * 0.9
        centre = 1 - abs(math.cos(th))
        sx = 6 + 3 * hnoise(i, 1, 81)
        N.rock(f"Lobby_Cliff{i}", (x, y, nat_height(x, y) - 1), (sx, 5 + 2 * hnoise(i, 2, 82), 5 + 9 * centre),
               seed=i, rot=th + math.pi / 2)
    # arbres et rochers placés à la main (plan de la v1)
    for kind, x, y, p in TREES:
        z = nat_height(x, y)
        rot = hnoise(x, y, 61) * math.tau
        seed = abs(x * 7 + y * 13)
        if kind == "round":
            N.tree(f"Lobby_Tree_{x}_{y}", (x, y, z), height=p * 1.7, seed=seed, autumn=seed % 5 == 0, rot=rot)
        elif kind == "pine":
            N.pine(f"Lobby_Pine_{x}_{y}", (x, y, z), height=p * 0.55, seed=seed, rot=rot)
        elif kind == "bush":
            N.bush(f"Lobby_Bush_{x}_{y}", (x, y, z), size=p * 0.8, seed=seed, rot=rot, flowers=seed % 2 == 0)
        else:
            N.rock(f"Lobby_Rock_{x}_{y}", (x, y, z), (p * 0.8, p * 0.65, p * 0.55), seed=seed, rot=rot)
    # forêt en lisière : dense sur les bords, rien sur les passages ni devant les stations
    n = 0
    for ring_r in (0.86, 0.95):
        for deg in range(0, 360, 5):
            th = math.radians(deg + (2.5 if ring_r > 0.9 else 0))
            ex, ey = se_point(th)
            x = ex * ring_r + (hnoise(deg, 3, 83) - 0.5) * 3
            y = ey * ring_r + (hnoise(deg, 4, 84) - 0.5) * 3
            if flat_mask(x, y) > 0.02 or (abs(x) < 30 and y < -22) or (abs(x) < 14 and y > 28):
                continue
            if any(math.hypot(x - sx, y - sy) < r + 6 for sx, sy, r in KEEP_FLAT):
                continue
            pick = hnoise(deg, int(ring_r * 100), 85)
            z = nat_height(x, y)
            rot = pick * math.tau
            n += 1
            if pick < 0.55:
                N.tree(f"Lobby_Forest{n}", (x, y, z), height=11 + 7 * hnoise(deg, 5, 86), seed=deg + n,
                       autumn=pick < 0.08, rot=rot)
            elif pick < 0.85:
                N.pine(f"Lobby_ForestPine{n}", (x, y, z), height=13 + 6 * hnoise(deg, 6, 87), seed=deg, rot=rot)
            else:
                N.bush(f"Lobby_ForestBush{n}", (x, y, z), size=2.5 + hnoise(deg, 7, 88), seed=deg, rot=rot,
                       flowers=True)
    # pierres de gué sur la place et le parvis
    for i in range(16):
        a = i / 16 * math.tau + 0.3
        r = 4.5 + 4.0 * hnoise(i, 8, 89)
        N.stepping_stone(f"Lobby_Stone{i}", (PLAZA[0] + r * math.cos(a), PLAZA[1] + r * math.sin(a), 0.0),
                         size=0.9 + 0.6 * hnoise(i, 9, 90), seed=i, rot=a)
    for i in range(10):
        x = -24 + i * 5.3 + (hnoise(i, 10, 91) - 0.5) * 2
        y = -24 + (hnoise(i, 11, 92) - 0.5) * 4
        if abs(x) < 9:
            continue
        N.stepping_stone(f"Lobby_CourtStone{i}", (x, y, 0.0), size=1.0 + 0.5 * hnoise(i, 12, 93), seed=20 + i)
    for i, (x, y, z, s_) in enumerate(ISLETS):
        N.islet(f"Lobby_Islet{i}", (x, y, z), size=6 * s_, seed=i)


# ---------------------------------------------------------------------------------------------
# Scène Blender : pose, personnages, caméras


def cliff_column(x: int, y: int) -> int:
    """Hauteur de la falaise (studs) sur la colonne (x, y), 0 hors falaise."""
    px, py = x + 0.5, y + 0.5
    yf = -34.0 - 4.0 * vnoise(px, 0, 6, 5)
    if abs(px) < 24:
        yf = -45.0
    if py >= int(yf):
        return 0
    e = edge_dist(px, py)
    if e < 0:
        return 0
    hc = int((7 + 9 * (1 - min(1.0, abs(px) / 56.0)) + 3 * vnoise(px, 0, 8, 6)) // 2 * 2)
    return max(0, min(hc, 3 + int((yf - py) * 2.0), 3 + int(e * 1.6)))


def ground_z(x: float, y: float) -> float:
    """Hauteur du sol (studs) à un point du monde, falaise comprise."""
    e = edge_dist(x, y)
    if e < 0:
        return 0.0
    kind, _ = surface(x, y, e)
    return float(max(terrace(x, y, e, kind), cliff_column(math.floor(x), math.floor(y))))


TREES = [  # (sorte, x, y, paramètre)
    ("round", -45, 36, 9), ("round", -38, 45, 6), ("pine", -51, 24, 30), ("bush", -41, 29, 4.0),
    ("pine", 44, 40, 34), ("round", 37, 45, 7), ("bush", 49, 31, 3.5), ("round", 49, 15, 9),
    ("rock", -50, -12, 4.0), ("bush", -48, -17, 3.0), ("pine", 51, -6, 26), ("rock", 47, -14, 3.5),
    ("pine", -46, -42, 28), ("pine", -37, -46, 24), ("pine", 44, -41, 30), ("pine", 35, -47, 22),
    ("bush", -45, -23, 3.5), ("bush", 45, -22, 3.0), ("rock", 41, -35, 3.0), ("rock", -24, -38, 3.0),
    ("round", -10, 18, 7), ("bush", 9, 30, 3.0), ("round", -25, 41, 8), ("round", 27, 44, 6),
    ("rock", -28, 36, 3.0), ("rock", 28, 28, 2.5), ("bush", -27, 18, 3.0), ("bush", 27, -13, 3.0),
    ("pine", -52, -28, 22), ("round", 52, -26, 7),
]
FLOWERS = [(-8, 36), (8, 26), (-25, -15), (25, -17), (-30, 14), (27, 15), (-14, 34), (-22, 21), (10, -27),
           (-10, -27)]
CLOUDS = [(-66, -20, -26, 1.0), (64, 30, -30, 1.0), (10, 66, -34, 1.0), (-46, 60, -22, 1.0), (74, -40, -24, 1.0),
          (-80, 12, -32, 1.0), (30, -70, -28, 1.0), (-20, -72, -36, 1.0)]
ISLETS = [(-96, -58, -8, 1.6), (94, 72, -16, 1.4), (118, -24, 2, 1.2), (-110, 40, -20, 1.3)]


def build_scene():
    import bpy

    import boards as BD
    import build as B
    import cohue_voxel as cv
    import models as M

    import brick

    cv.to_blender = brick.to_blender            # toute la scène passe en briques à tenons
    brick.OPTIONS.update({"Lobby_StoneHead": {"maxlen": 3}})
    sc = BD.fresh()
    B.diorama_light(sc, sun_elev=52, sun_az=-40, strength=5.0, world="9FD3F7", world_strength=1.0)
    painted_sky(sc)

    glow_mats = {}

    def glow(ob, strength):
        mat = glow_mats.get(strength)
        if not mat:
            mat = bpy.data.materials.new(f"Lobby_Glow_{strength}")
            mat.use_nodes = True
            nt = mat.node_tree
            bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
            vc = nt.nodes.new("ShaderNodeVertexColor")
            vc.layer_name = "Color"
            nt.links.new(vc.outputs["Color"], bsdf.inputs["Base Color"])
            nt.links.new(vc.outputs["Color"], bsdf.inputs["Emission Color"])
            bsdf.inputs["Emission Strength"].default_value = strength
            glow_mats[strength] = mat
        ob.data.materials.clear()
        ob.data.materials.append(mat)

    def put(vox, loc, rot=0.0, grain=G4, origin=(0, 0, 0), scale=1.0, strength=None):
        ob = cv.to_blender(vox, origin, voxel=grain)
        ob.location = loc
        ob.rotation_euler = (0, 0, math.radians(rot))
        if scale != 1.0:
            ob.scale = (scale, scale, scale)
        if strength:
            glow(ob, strength)
        return ob

    def model(fn, loc, rot=0.0):
        vox, origin, _ = fn()
        return put(vox, loc, rot, G4, origin)

    stats = {}

    def note(name, ob):
        stats[name] = ob["tris"]

    natural_island()                            # décor naturel (nature.py), pas de briques
    natural_dressing()
    note("head", put(stone_head(), (0, -40, 0), 180, G2))
    note("swirl", put(portal_swirl(), (0, -40, 0), 180, G2, strength=1.1))
    for name, (x, y, r, n) in PADS.items():
        note(f"pad_{name}", put(pad(n, r), (x, y, 0), grain=G2))

    st = STATIONS
    builders = {"Knight": (knight_yard, G4), "Archer": (archer_range, G4), "Mage": (mage_tower, G4),
                "Crates": (crate_cart, G4), "Haystack": (haystack, G2), "Pen": (critter_pen, G2),
                "Shop": (glam_stall, G4), "Hall": (hall_of_fame, G4), "Quest": (quest_board, G4),
                "Campfire": (campfire, G4)}
    for name, (fn, grain) in builders.items():
        x, y, rot = st[name]
        note(name, put(fn(), (x, y, 0), rot, grain))
    cx, cy, _ = st["Campfire"]
    note("fire", put(fire(), (cx, cy, 0), strength=3.0))
    for a in (150, 230, 310):
        r = math.radians(a)
        put(log_bench(), (cx + 4.6 * math.cos(r), cy + 4.6 * math.sin(r), 0), a + 90)

    for i, (x, y, z, s) in enumerate(CUMULUS):
        cumulus((x, y, z), s, i)

    # Joueurs (mannequins habillés) et gobelins
    BD.dressed("Knight", 3, 1.5, y=31.0, rot=0.0)
    BD.dressed("Archer", 1, -2.5, y=40.5, rot=math.radians(10))
    for i, cls in enumerate(("Archer", "Mage")):
        BD.dressed(cls, 2 + i, 15.5 + 2.6 * i, y=-19.0 - 1.2 * i, rot=math.radians(-59))
    BD.dressed("Mage", 1, 28.5, y=-1.0, rot=math.radians(90))
    BD.dressed("Archer", 3, 14.5, y=22.0, rot=math.radians(90))
    BD.dressed("Knight", 2, 13.0, y=-11.5, rot=math.radians(35))
    model(M.goblin_bomber, (34.0, 4.0, 0.25), -90)                 # Gob, derrière son comptoir
    model(M.goblin_grunt, (-45.5, 6.5, 0), -90)                    # mâchouille la clôture
    model(M.goblin_shaman, (-33.0, 8.0, 0), 180)                   # boit à l'abreuvoir
    model(M.goblin_archer, (-28.5, 2.0, 0), 90)                    # guette à la porte
    hx, hy, hrot = st["Hall"]
    a = math.radians(hrot)
    for (lx, ly, top) in [(0.0, 0.0, 17), (-14.5, -0.5, 11)]:
        wx = hx + 0.25 * (lx * math.cos(a) - ly * math.sin(a))
        wy = hy + 0.25 * (lx * math.sin(a) + ly * math.cos(a))
        model(M.mannequin, (wx, wy, top * 0.25), hrot)              # statues des meilleurs joueurs
    bloom(sc)
    return sc, stats


def bloom(sc, threshold=0.9, strength=0.5, size=0.5):
    """Bloom par le compositeur de Blender 5.2 (seul ce qui brille fleurit, comme le Neon en jeu)."""
    import bpy

    try:
        ng = bpy.data.node_groups.new("Lobby_Comp", "CompositorNodeTree")
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
    except Exception as ex:  # le rendu reste valable sans bloom
        print("bloom ignoré :", ex)


CUMULUS = [  # gros nuages peints (lisses) autour de l'île et à l'horizon
    (-150, -40, -30, 1.4), (150, 30, -36, 1.5), (20, 170, -44, 1.6), (-120, 140, -26, 1.1), (130, -150, -20, 1.3),
    (-170, -250, 6, 2.6), (190, -240, 14, 2.2), (-250, -120, 20, 2.0), (250, -60, 16, 1.8), (-250, 40, 10, 1.8),
]


def painted_sky(sc):
    """Ciel en dégradé (horizon clair, zénith bleu franc), comme un ciel peint."""
    import build as B

    nt = sc.world.node_tree
    bg = next(n for n in nt.nodes if n.type == "BACKGROUND")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = -0.6
    mr.inputs["From Max"].default_value = 0.7
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    els = ramp.color_ramp.elements
    els[0].position, els[0].color = 0.0, B.hexcol("5FA8EE")      # sous l'horizon : bleu moyen
    els[1].position, els[1].color = 1.0, B.hexcol("1F63D8")      # zénith : bleu franc
    for pos, col in ((0.46, "DDF1FF"), (0.62, "7FC2F7")):        # horizon clair puis bleu ciel
        e = els.new(pos)
        e.color = B.hexcol(col)
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], mr.inputs["Value"])
    nt.links.new(mr.outputs["Result"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 1.0
    # Le ciel s'affiche en entier mais éclaire peu : couleurs franches, ombres lisibles (comme en jeu)
    out = next(n for n in nt.nodes if n.type == "OUTPUT_WORLD")
    amb = nt.nodes.new("ShaderNodeBackground")
    nt.links.new(ramp.outputs["Color"], amb.inputs["Color"])
    amb.inputs["Strength"].default_value = 0.45
    lp = nt.nodes.new("ShaderNodeLightPath")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(lp.outputs["Is Camera Ray"], mix.inputs["Fac"])
    nt.links.new(amb.outputs["Background"], mix.inputs[1])
    nt.links.new(bg.outputs["Background"], mix.inputs[2])
    nt.links.new(mix.outputs["Shader"], out.inputs["Surface"])


def cumulus(center, scale, seed):
    """Nuage peint : boules lisses blanches (pas de briques dans le ciel)."""
    import bmesh
    import bpy

    import build as B

    mat = bpy.data.materials.get("Lobby_Cloud")
    if not mat:
        mat = bpy.data.materials.new("Lobby_Cloud")
        mat.use_nodes = True
        bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        bsdf.inputs["Base Color"].default_value = B.hexcol("FFFFFF")
        bsdf.inputs["Roughness"].default_value = 1.0
        bsdf.inputs["Emission Color"].default_value = B.hexcol("FFF4E6")
        bsdf.inputs["Emission Strength"].default_value = 0.35
    bm = bmesh.new()
    for i in range(8):
        r = (9 + 9 * hnoise(i, seed, 71)) * scale
        dx = (hnoise(seed, i, 72) - 0.5) * 50 * scale
        dy = (hnoise(i, i, 73 + seed) - 0.5) * 16 * scale
        dz = (r * 0.5) * hnoise(seed, seed, 74 + i)
        m = bmesh.ops.create_uvsphere(bm, u_segments=28, v_segments=14, radius=r)
        bmesh.ops.translate(bm, verts=m["verts"], vec=(dx, dy, dz))
    me = bpy.data.meshes.new(f"Lobby_Cumulus{seed}")
    bm.to_mesh(me)
    bm.free()
    for poly in me.polygons:
        poly.use_smooth = True
    me.materials.append(mat)
    ob = bpy.data.objects.new(me.name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = center
    ob.visible_shadow = False
    return ob


VIEWS = {  # nom : (position caméra, cible, focale, résolution)
    "overview": ((52, 132, 96), (0, -8, -2), 34, (2000, 1250)),
    "arrival": ((0, 54, 11), (0, -24, 12), 18, (1600, 900)),
    "portal": ((24, 4, 9), (-3, -32, 13), 24, (1600, 900)),
    "west": ((12, 20, 14), (-32, 6, 2), 26, (1600, 900)),
    "east": ((-2, 6, 12), (32, 14, 2), 26, (1600, 900)),
}


def render_views(outdir, names=None):
    import build as B

    sc, stats = build_scene()
    os.makedirs(outdir, exist_ok=True)
    for name in names or VIEWS:
        loc, target, lens, res = VIEWS[name]
        B.camera(sc, loc, target, lens=lens)
        B.render(sc, os.path.join(outdir, f"lobby_{name}.png"), res=res, samples=48)
    with open(os.path.join(outdir, "lobby_stats.txt"), "w", encoding="utf-8") as f:
        for k, t in stats.items():
            f.write(f"{k};{t}\n")
        f.write(f"total;{sum(stats.values())}\n")
    return stats


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = os.path.abspath(argv[0]) if argv else os.path.join(HERE, "review", "lobby")
    print(render_views(out, argv[1:] or None))
