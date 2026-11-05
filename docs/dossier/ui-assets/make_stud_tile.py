"""Turn the grey kek_stud texture into a transparent light/shadow tile.

Each pixel brighter than the flat grey becomes white with alpha, each darker
pixel becomes black with alpha. The tile then works with normal blending on
any coloured face, in Figma (image fill, TILE) and in Roblox (ImageLabel,
ScaleType Tile), without needing an overlay blend mode.
"""
import sys
import numpy as np
from PIL import Image

src, out_dir = sys.argv[1], sys.argv[2]
im = np.asarray(Image.open(src).convert("L"), dtype=np.float32)
base = float(np.median(im))

tile = im[0:128, 0:128]  # 2 x 2 studs, the grid period is 64 px
diff = tile - base
diff[np.abs(diff) < 3] = 0  # flatten the noise of the flat area

alpha = np.where(diff > 0, diff / (255 - base), -diff / base)
alpha = np.clip(alpha * 1.6, 0, 1)
rgb = np.where(diff[..., None] > 0, 255, 0) * np.ones((1, 1, 3))
rgba = np.dstack([rgb, alpha * 255]).astype(np.uint8)
Image.fromarray(rgba, "RGBA").save(f"{out_dir}/stud_tile_128.png")

# preview: the tile repeated on a few UI colours, at the UI scale (12 px studs)
colors = [(124, 214, 63), (255, 196, 46), (238, 72, 72), (140, 92, 230), (48, 160, 255), (40, 46, 72)]
pw, ph = 160, 48
prev = Image.new("RGB", (pw, ph * len(colors)), (0, 0, 0))
small = Image.fromarray(rgba, "RGBA").resize((24, 24), Image.LANCZOS)
for i, c in enumerate(colors):
    face = Image.new("RGBA", (pw, ph), c + (255,))
    for x in range(0, pw, 24):
        for y in range(0, ph, 24):
            face.alpha_composite(small, (x, y))
    prev.paste(face.convert("RGB"), (0, i * ph))
prev.resize((pw * 3, ph * len(colors) * 3), Image.NEAREST).save(f"{out_dir}/stud_tile_preview.png")
print("base grey", base, "alpha max", float(alpha.max()))
