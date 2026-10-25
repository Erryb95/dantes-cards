"""Post-processes the Blender blockout renders for the ComfyUI paintover.

  python tools/arena/passes.py art_src/arena/blockout

Writes board_lineart.png (white lines on black: element borders from the ID pass + main clay edges) and
layout_check.png (clay with the game's layout guide on top, to eyeball the sockets).
"""
import os
import sys

import cv2
import numpy as np

d = sys.argv[1]
clay = cv2.imread(os.path.join(d, "board_clay.png"), cv2.IMREAD_GRAYSCALE)
ids = cv2.imread(os.path.join(d, "board_id.png"))
# The terrain regions (banks, riverbed, cliffs) blend into each other: their shared borders are not lines to paint.
h, w = ids.shape[:2]
flat = ids.copy()
# Sample the region colours at known layout points (cliff, far bank, near bank) rather than trusting ids.json,
# since the render's colour management shifts them.
for gx, gy in ((60, 900), (1880, 900), (960, 300), (960, 950)):
    c = ids[int(gy / 1080 * h), int(gx / 1920 * w)].astype(int)
    flat[np.all(np.abs(ids.astype(int) - c) < 8, axis=2)] = (40, 40, 40)
borders = (cv2.Canny(flat, 10, 30) > 0).astype(np.uint8) * 255
edges = cv2.Canny(cv2.GaussianBlur(clay, (5, 5), 0), 40, 110)
lines = cv2.max(cv2.dilate(borders, np.ones((3, 3), np.uint8)), edges)
cv2.imwrite(os.path.join(d, "board_lineart.png"), lines)
guide = cv2.imread(os.path.join(os.path.dirname(os.path.abspath(d)), "acheron_layout_guide.png"))
if guide is not None:
    guide = cv2.resize(guide, (clay.shape[1], clay.shape[0]))
    check = cv2.addWeighted(cv2.cvtColor(clay, cv2.COLOR_GRAY2BGR), 0.6, guide, 0.4, 0)
    cv2.imwrite(os.path.join(d, "layout_check.png"), check)
print("ok")
