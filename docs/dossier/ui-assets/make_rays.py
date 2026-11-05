"""Sunburst behind the level-up window (A08, UI v3).

White wedges on a transparent background, fading toward the centre and the edge.
Roblox tints it (ImageColor3) and rotates it slowly; Figma uses it as an image fill.
Usage: python make_rays.py <out.png>
"""
import sys
import numpy as np
from PIL import Image

N = 512
RAYS = 16
out = sys.argv[1]

y, x = np.mgrid[0:N, 0:N].astype(np.float32)
c = (N - 1) / 2
dx, dy = x - c, y - c
r = np.hypot(dx, dy) / c  # 0 at the centre, 1 at the edge
a = (np.arctan2(dy, dx) / (2 * np.pi) * RAYS) % 1.0  # 0..1 inside each ray period

# Wedge = first half of each period; 1 px of soft edge (anti-aliasing): at radius R pixels,
# one pixel is RAYS / (2 pi R) of a period.
soft = RAYS / (2 * np.pi * np.maximum(r * c, 1))
wedge = np.clip((0.25 - np.abs(a - 0.25)) / soft + 0.5, 0, 1)

fade = np.clip((r - 0.12) / 0.25, 0, 1) * np.clip((1.0 - r) / 0.35, 0, 1)
alpha = (wedge * fade * 255).astype(np.uint8)

img = np.zeros((N, N, 4), dtype=np.uint8)
img[..., :3] = 255
img[..., 3] = alpha
Image.fromarray(img, "RGBA").save(out, optimize=True)
print(out, N, RAYS)
