"""Lays out the frames saved by tests/vfx_preview.tscn: one row per card, frames left to right (cropped to the
board), so every card's effect can be reviewed at a glance.

  python tools/vfx/contact_sheet.py <frames dir> <out.png> [frames per row] [cards per sheet]

With more cards than fit one sheet, writes out_1.png, out_2.png ...
"""
import glob
import os
import sys
from collections import defaultdict

from PIL import Image, ImageDraw

src, out = sys.argv[1], sys.argv[2]
per_row = int(sys.argv[3]) if len(sys.argv) > 3 else 8
per_sheet = int(sys.argv[4]) if len(sys.argv) > 4 else 1000
cards = defaultdict(list)
for f in sorted(glob.glob(os.path.join(src, "*_[0-9][0-9].png"))):
    cards[os.path.basename(f)[:-7]].append(f)
TW, TH = 480, 180
items = list(cards.items())
chunks = [items[i:i + per_sheet] for i in range(0, len(items), per_sheet)]
for n, chunk in enumerate(chunks, 1):
    sheet = Image.new("RGB", (TW * per_row + 160, TH * len(chunk)), (12, 10, 10))
    d = ImageDraw.Draw(sheet)
    for row, (cid, frames) in enumerate(chunk):
        step = max(1, len(frames) // per_row)
        for col, f in enumerate(frames[::step][:per_row]):
            im = Image.open(f).convert("RGB").crop((0, 0, 960, 360)).resize((TW, TH), Image.LANCZOS)
            sheet.paste(im, (160 + col * TW, row * TH))
        d.text((6, row * TH + 8), cid, fill=(255, 220, 120))
    name = out if len(chunks) == 1 else out.replace(".png", "_%d.png" % n)
    sheet.save(name)
print("%d cards -> %s (%d sheets)" % (len(items), out, len(chunks)))
