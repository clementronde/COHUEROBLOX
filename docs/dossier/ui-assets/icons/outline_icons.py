"""Contour Ink épais autour des icônes rendues par build_icons.py, puis recadrage carré.

Le contour sombre détache l'icône du décor coloré, comme les icônes des packs d'UI « stud ».
Utilisation : python outline_icons.py <dossier_rendus> [<dossier_sortie>] [taille=256]
"""
import glob
import os
import sys

from PIL import Image, ImageFilter

INK = (0x1C, 0x17, 0x26)

src = sys.argv[1]
dst = sys.argv[2] if len(sys.argv) > 2 else os.path.join(src, "outlined")
size = int(sys.argv[3]) if len(sys.argv) > 3 else 256
os.makedirs(dst, exist_ok=True)

for path in sorted(glob.glob(os.path.join(src, "*.png"))):
    im = Image.open(path).convert("RGBA")
    box = im.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
    if not box:
        continue
    im = im.crop(box)
    w, h = im.size
    side = int(max(w, h) * 1.16)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.alpha_composite(im, ((side - w) // 2, (side - h) // 2))
    alpha = canvas.getchannel("A").point(lambda a: 255 if a > 40 else 0)
    radius = max(3, round(side * 0.05))   # ≈ 2,5 px de contour à 40 px d'affichage
    grown = alpha.filter(ImageFilter.MaxFilter(radius * 2 + 1))
    ink = Image.new("RGBA", canvas.size, INK + (0,))
    ink.putalpha(grown)
    out = Image.alpha_composite(ink, canvas).resize((size, size), Image.LANCZOS)
    out.save(os.path.join(dst, os.path.basename(path)))
    print(os.path.basename(path), side)
