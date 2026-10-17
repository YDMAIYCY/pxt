"""Regenerate the home-page quick-action icons from the supplied key art.

The three supplied images are app-icon style art: a pastel rounded square with a
3D glyph. They ship with a wide white margin, so this script crops to the
coloured square, adds a transparent outer radius that matches the app's tile
(`AppRadii.cardSmall = 18` on a `52dp` art box => 0.3462), and writes a
512x512 RGBA PNG into `assets/images/`.

Run:
    python tools/build_quick_icons.py
"""

import os
import numpy as np
from PIL import Image, ImageDraw

CLIP = r"C:\Users\28304\.workbuddy\clipboard-images"
PROJ = r"D:\app project\pxt"
DEST = os.path.join(PROJ, "assets", "images")

SIZE = 512
RATIO = 18 / 52  # EClaw tile corner radius relative to the 52dp art box

JOBS = {
    "quick_camera.png": "clipboard-2026-10-16T13-46-32-756Z-0bf8050f.png",
    "quick_import.png": "clipboard-2026-10-16T13-46-32-757Z-bb5ed3f1.png",
    "quick_interview.png": "clipboard-2026-10-16T13-46-32-758Z-ea34335b.png",
}


def tight_square(im, sat_thresh=18, min_run=30):
    a = np.asarray(im.convert("RGB")).astype(int)
    sat = a.max(axis=2) - a.min(axis=2)
    strong = sat > sat_thresh
    rows = np.where(strong.sum(axis=1) > min_run)[0]
    cols = np.where(strong.sum(axis=0) > min_run)[0]
    y0, y1, x0, x1 = int(rows.min()), int(rows.max()), int(cols.min()), int(cols.max())
    cy, cx = (y0 + y1) / 2, (x0 + x1) / 2
    half = max(y1 - y0, x1 - x0) / 2 + 1
    return im.crop((int(cx - half), int(cy - half), int(cx + half), int(cy + half)))


def with_corner_alpha(im, size, ratio):
    art = im.convert("RGBA").resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size * 4 - 1, size * 4 - 1), radius=int(size * 4 * ratio), fill=255
    )
    mask = mask.resize((size, size), Image.LANCZOS)
    art.putalpha(mask)
    return art


for out_name, src_name in JOBS.items():
    src = os.path.join(CLIP, src_name)
    im = Image.open(src)
    art = with_corner_alpha(tight_square(im), SIZE, RATIO)
    dest = os.path.join(DEST, out_name)
    art.save(dest, optimize=True)
    print(f"{out_name:22s} {im.size} -> {art.size} {os.path.getsize(dest)/1024:.1f} KB")
