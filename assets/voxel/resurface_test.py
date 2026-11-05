"""COHUE — préparation du test Resurface (A01-02 bis, 5 nov. 2026).

Exporte un modèle en deux versions « briques », avec des UV à l'échelle de la cellule (une cellule = un
tenon), pour vérifier dans Studio que le plugin Resurface (MaterialVariant) pose bien un tenon par brique
et que la couleur par sommet survit :
- Fused  : maille fusionnée (comme en v1, sans ombrage cuit) — technique B du guide ;
- Bricks : briques chanfreinées sans tenons (brick.py, chanfrein appliqué) — technique A du guide.

    blender -b --factory-startup --python assets/voxel/resurface_test.py -- <dossier> [NomDuModele]

Sorties : <Nom>_Fused.glb, <Nom>_Bricks.glb (pour un import réel) et <Nom>_<variante>.json (aperçu
EditableMesh sans téléversement : sommets en axes Roblox, triangles, UV par coin en cellules, couleurs).
"""

from __future__ import annotations

import json
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.append(HERE)

import brick  # noqa: E402
import cohue_voxel as cv  # noqa: E402
import models as M  # noqa: E402


def box_uvs(ob, voxel: float, offset):
    """UV par coin : coordonnées dans le plan de la face (axe dominant de la normale), en cellules."""
    me = ob.data
    uv = me.uv_layers.get("UVMap") or me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        n = poly.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        u_ax, v_ax = [(1, 2), (0, 2), (0, 1)][ax]
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            uv.data[li].uv = (co[u_ax] / voxel + offset[u_ax], co[v_ax] / voxel + offset[v_ax])
    me.uv_layers.active = uv


def apply_modifiers(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    bpy.data.meshes.remove(old)
    return ob


def write_json(ob, path):
    """Triangles en axes Roblox (x, y, z) -> (-x, z, y), UV par coin, couleur par triangle (palette hex)."""
    me = ob.data
    me.calc_loop_triangles()
    uv = me.uv_layers.active.data
    col = me.color_attributes.get("Color")
    point = col.domain == "POINT"
    verts = [[round(-v.co.x, 4), round(v.co.z, 4), round(v.co.y, 4)] for v in me.vertices]
    pal, tris = {}, []
    for t in me.loop_triangles:
        li = t.loops[0]
        c = col.data[me.loops[li].vertex_index if point else li].color_srgb
        h = cv.rgb_hex(c)
        pal.setdefault(h, len(pal) + 1)
        tris.append([t.vertices[0], t.vertices[1], t.vertices[2],
                     [[round(uv[l].uv[0], 3), round(uv[l].uv[1], 3)] for l in t.loops], pal[h]])
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"v": verts, "t": tris, "p": list(pal)}, f, separators=(",", ":"))
    return len(tris)


def main(outdir, name="Enemy_GoblinGrunt"):
    os.makedirs(outdir, exist_ok=True)
    for ob in list(bpy.context.scene.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    fn = next(f for f in M.DELIVERABLES if f()[0].name == name)
    vox, origin, meta = fn()
    lo, hi = vox.bounds()
    o = ((lo[0] + hi[0] + 1) / 2, (lo[1] + hi[1] + 1) / 2, lo[2])     # origine « bottom »
    offset = tuple(v % 1.0 for v in o)
    report = {}
    # Fused : maille fusionnée, couleurs sans ombrage cuit (la lumière du jeu et les tenons font le relief)
    saved = dict(cv.FACE_TONE)
    cv.FACE_TONE.clear()
    fused = cv.to_blender(vox, "bottom", name=name + "_Fused")
    cv.FACE_TONE.update(saved)
    box_uvs(fused, cv.VOXEL, offset)
    # Bricks : briques chanfreinées, tenons absents (Resurface les pose)
    brick.STUD_TEXTURE = True
    bricks = brick.to_blender(vox, "bottom", name=name + "_Bricks")
    apply_modifiers(bricks)
    box_uvs(bricks, cv.VOXEL, offset)
    for ob in (fused, bricks):
        ob.data.materials.clear()
        ob.data.materials.append(cv.voxel_material())
        cv.export_glb(ob, os.path.join(outdir, ob.name + ".glb"))
        report[ob.name] = write_json(ob, os.path.join(outdir, ob.name + ".json"))
    print("RESURFACE_TEST", json.dumps(report))


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    main(os.path.abspath(argv[0]) if argv else os.path.join(HERE, "review", "resurface"), *argv[1:2])
