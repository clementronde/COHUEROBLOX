"""COHUE — rendus des planches et des revues de modèles (A01). Blender 5.2 en ligne de commande :

    blender -b --factory-startup --python assets/voxel/boards.py -- <commande> <sortie.png>

Commandes : lineup_goblins, lineup_equipment, silhouettes, diorama, review:<NomDuModele>.
Les planches finales sont montées avec tools PIL (assets/style/compose.py).
"""

from __future__ import annotations

import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.append(HERE)

import build as B  # noqa: E402
import cohue_voxel as cv  # noqa: E402
import models as M  # noqa: E402

V = cv.VOXEL


def fresh():
    sc = bpy.context.scene
    for ob in list(sc.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    sc.view_settings.view_transform = "Standard"
    return sc


def ground(sc, w, d, col="Leaf", z=0.0, name="Ground"):
    v = cv.Vox(name)
    v.box(-w // 2, w // 2 - 1, -d // 2, d // 2 - 1, -1, -1, col)
    ob = cv.to_blender(v, (0, 0, 0))
    ob.location.z = z
    return ob


def equip(fn, anchor):
    """Pose une pièce d'équipement sur le mannequin (anchor en voxels du mannequin)."""
    vox, origin, meta = fn()
    ob = cv.to_blender(vox, origin)
    ob.location = (anchor[0] * V, anchor[1] * V, anchor[2] * V)
    return ob, meta


# Points d'attache sur le mannequin (voir models.mannequin)
HAT = (0, 0, 22)
BACK = (0, 2, 13)
R_SHOULDER = (-6, 0, 17)
L_SHOULDER = (6, 0, 17)
L_GRIP = (6, 0, 9)


def dressed(cls: str, tier: int, x: float, y: float = 0.0, rot: float = 0.0):
    """Mannequin + pièces cumulées jusqu'au palier donné. Retourne les objets."""
    obs = []
    man, _, _ = B.place(M.mannequin, (0, 0, 0), name=f"Avatar_{cls}_{tier}")
    obs.append(man)
    pieces = {
        "Knight": [(M.knight_helm, HAT), (M.knight_pauldron, R_SHOULDER), (M.knight_cape, BACK)],
        "Archer": [(M.archer_hood, HAT), (M.archer_bracer, L_GRIP), (M.archer_quiver, BACK)],
        "Mage": [(M.mage_hat, HAT), (M.mage_orb, L_SHOULDER), (M.mage_cape, BACK)],
    }[cls]
    for i, (fn, anchor) in enumerate(pieces[:tier]):
        ob, meta = equip(fn, anchor)
        obs.append(ob)
        if fn is M.knight_pauldron:   # épaule gauche : même maille, demi-tour vertical
            ob2, _ = equip(fn, L_SHOULDER)
            ob2.rotation_euler.z = math.pi
            obs.append(ob2)
    root = bpy.data.objects.new(f"Root_{cls}_{tier}", None)
    bpy.context.scene.collection.objects.link(root)
    for ob in obs:
        ob.parent = root
    root.location = (x, y, 0)
    root.rotation_euler.z = rot
    return root


def lineup_goblins(out):
    sc = fresh()
    ground(sc, 140, 48, "Leaf.d")
    B.diorama_light(sc, world="CFE9F5", world_strength=1.0)
    xs = [-10.5, -5.5, -0.5, 4.5]
    for x, fn in zip(xs, M.ENEMIES):
        ob, _, _ = B.place(fn, (x, 0, 0), rot_z=math.radians(-20))
    B.place(M.mannequin, (10.5, 0, 0), rot_z=math.radians(-20))
    B.camera(sc, (0, -34, 15), (0, 0, 2.0), lens=55)
    B.render(sc, out, res=(1800, 760))


def lineup_equipment(out):
    """Rangée avant : les 3 paliers de face ; rangée arrière : les mêmes de dos."""
    sc = fresh()
    ground(sc, 220, 120, "Cream.d")
    B.diorama_light(sc, world="F3E3C8")
    x0 = -21.0
    for row, (y, rot) in enumerate(((-4.0, -20.0), (5.0, 160.0))):
        x = x0
        for cls in ("Knight", "Archer", "Mage"):
            for tier in (1, 2, 3):
                dressed(cls, tier, x, y=y, rot=math.radians(rot))
                x += 4.6
            x += 2.4
    B.camera(sc, (0, -58, 26), (0, 0.5, 1.2), lens=50)
    B.render(sc, out, res=(2000, 1000))


def review(name, out):
    """Un modèle sous 4 angles + sa silhouette (fichiers <out>_front.png, etc.)."""
    fn = next(f for f in M.DELIVERABLES + M.BLOCKOUTS + [M.mannequin] if f()[0].name == name)
    sc = fresh()
    vox, origin, meta = fn()
    ob = cv.to_blender(vox, "center")
    sx, sy, sz = vox.size_studs()
    r = max(sx, sy, sz) * 2.4
    B.diorama_light(sc, world="F3E3C8")
    base = out[:-4]
    for tag, (dx, dy, dz) in {"front": (0, -1, 0.25), "threequarter": (-0.8, -0.8, 0.5),
                              "back": (0.3, 1, 0.35), "side": (1, 0, 0.2)}.items():
        n = math.sqrt(dx * dx + dy * dy + dz * dz)
        B.camera(sc, (dx / n * r, dy / n * r, dz / n * r), (0, 0, 0), lens=70)
        B.render(sc, f"{base}_{tag}.png", res=(700, 700), samples=24)
    B.silhouette_mode(sc, True)
    B.camera(sc, (-0.8 / 1.24 * r, -0.8 / 1.24 * r, 0.3 / 1.24 * r), (0, 0, 0), lens=70)
    B.render(sc, f"{base}_silhouette.png", res=(256, 256), transparent=True, samples=1)


def emissive(ob, hexc, strength=6.0):
    mat = bpy.data.materials.new(ob.name + "_Glow")
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = B.hexcol(hexc)
    bsdf.inputs["Emission Color"].default_value = B.hexcol(hexc)
    bsdf.inputs["Emission Strength"].default_value = strength
    ob.data.materials.clear()
    ob.data.materials.append(mat)


def glare(sc, threshold=0.85, mix=0.0):
    """Bloom par le compositeur (EEVEE 5.x n'a plus de case Bloom)."""
    try:
        sc.use_nodes = True
        nt = sc.node_tree
        for n in list(nt.nodes):
            nt.nodes.remove(n)
        rl = nt.nodes.new("CompositorNodeRLayers")
        gl = nt.nodes.new("CompositorNodeGlare")
        for attr, val in (("glare_type", "FOG_GLOW"), ("threshold", threshold), ("mix", mix), ("size", 7)):
            if hasattr(gl, attr):
                setattr(gl, attr, val)
        comp = nt.nodes.new("CompositorNodeComposite")
        nt.links.new(rl.outputs["Image"], gl.inputs["Image"])
        nt.links.new(gl.outputs["Image"], comp.inputs["Image"])
    except Exception as ex:  # l'API du compositeur change souvent : le rendu reste valable sans bloom
        print("glare ignoré :", ex)


def scale_board(out):
    """Échelle : avatar R15 (Knight palier 3), gobelins, règle de 1 stud = 4 voxels."""
    sc = fresh()
    ground(sc, 120, 24, "Cream.d")
    B.diorama_light(sc, world="F3E3C8", sun_elev=45, sun_az=-30)
    dressed("Knight", 3, -5.0, rot=0.0)
    B.place(M.goblin_grunt, (0.5, 0, 0))
    B.place(M.goblin_bomber, (5.0, 0, 0))
    elite = B.place(M.goblin_grunt, (10.0, 0, 0))[0]
    elite.scale = (1.25, 1.25, 1.25)
    ruler = cv.Vox("Ruler")
    for i in range(24):
        ruler.box(0, 0, 0, 0, i, i, "Ink" if (i // 4) % 2 == 0 else "Cream")
    r = cv.to_blender(ruler, "bottom")
    r.location = (-9.0, 0, 0)
    B.camera(sc, (0.5, -60, 3.0), (0.5, 0, 3.0), ortho=26)
    B.render(sc, out, res=(2000, 760))


def creatures(outdir):
    """Rendus couleur (3/4 face) et silhouettes des 12 créatures de la planche 2."""
    os.makedirs(outdir, exist_ok=True)
    fns = M.ENEMIES + M.BLOCKOUTS
    for fn in fns:
        sc = fresh()
        vox, origin, meta = fn()
        ob = cv.to_blender(vox, "bottom")
        sx, sy, sz = vox.size_studs()
        B.diorama_light(sc, world="F3E3C8")
        target = (0, 0, sz * 0.45)
        r = 13.0
        B.camera(sc, (-0.45 * r, -0.85 * r, 0.42 * r), target, ortho=5.2)
        B.render(sc, os.path.join(outdir, vox.name + ".png"), res=(600, 600), transparent=True, samples=32)
        B.silhouette_mode(sc, True)
        B.camera(sc, (0, -r, 0.15 * r), target, ortho=5.2)   # silhouette de face : la forme en T se lit
        B.render(sc, os.path.join(outdir, vox.name + "_sil.png"), res=(64, 64), transparent=True, samples=1)
        B.silhouette_mode(sc, False)


def equipment_views(outdir):
    """Chaque classe à chaque palier, de face et de dos (fond transparent)."""
    os.makedirs(outdir, exist_ok=True)
    for cls in ("Knight", "Archer", "Mage"):
        for tier in (1, 2, 3):
            for side, rot in (("front", -15.0), ("back", 165.0)):
                sc = fresh()
                B.diorama_light(sc, world="F3E3C8")
                dressed(cls, tier, 0.0, rot=math.radians(rot))
                B.camera(sc, (0, -30, 9), (0, 0, 3.1), ortho=8.4)
                B.render(sc, os.path.join(outdir, f"{cls}_T{tier}_{side}.png"), res=(520, 640), transparent=True, samples=32)


def diorama(out):
    """Planche 3 : tuile de forêt flottante, coupe de terrain, horde, joueur Knight, lumière chaude."""
    import random

    rnd = random.Random(4)
    sc = fresh()
    vox, origin, meta = M.island(44, 34)
    isl = cv.to_blender(vox, origin, voxel=1.0)              # terrain : grain de 1 stud
    B.diorama_light(sc, sun_elev=30, sun_az=-55, strength=3.6, world="BFA6D6", world_strength=0.75)
    # Décor : arbres et rochers au grain 0,5 (props agrandis x2), tons calmes
    for i in range(26):
        x = rnd.uniform(-20, 20)
        y = rnd.uniform(-15, 15)
        if abs(x) < 6:
            continue
        fn = M.prop_rock if i % 4 == 0 else (lambda s=i: M.prop_tree(s % 2))
        ob = B.place(fn, (x, y, 0), rot_z=rnd.uniform(0, 6.28))[0]
        ob.scale = (2, 2, 2)
    # Horde qui descend le chemin vers le joueur
    kinds = [M.goblin_grunt] * 4 + [M.goblin_archer] * 2 + [M.goblin_shaman, M.goblin_bomber, M.goblin_bomber]
    for i in range(34):
        x = rnd.uniform(-9, 9)
        y = rnd.uniform(-14.5, 1.5)
        ob = B.place(kinds[i % len(kinds)], (x, y, 0), rot_z=math.atan2(-(x - 0), -(y - 9)) + math.pi)[0]
    cap = B.place(M.goblin_grunt, (-3.5, -1.5, 0), rot_z=math.pi * 0.1)[0]
    ring = B.place(M.capture_ring, (-3.5, -1.5, 0.02))[0]
    emissive(ring, cv.PALETTE["Bubblegum"], 2.0)
    icon = B.place(M.capture_icon, (-3.5, -1.5, 4.9), rot_z=0.5)[0]
    emissive(icon, cv.PALETTE["Bubblegum"], 2.0)
    dressed("Knight", 3, 0.0, y=9.0, rot=0.0)                # le joueur fait face à la horde (-Y)
    # Vue 3/4 haute : on voit deux bords de la tuile et sa coupe de terrain (effet diorama)
    B.camera(sc, (34, 52, 36), (0, 1, -1.5), lens=50, dof=(66.0, 0.7))
    B.render(sc, out, res=(2200, 1240), samples=64)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:]
    cmd, out = argv[0], os.path.abspath(argv[1])
    if cmd.startswith("review:"):
        review(cmd.split(":", 1)[1], out)
    else:
        globals()[cmd](out)
