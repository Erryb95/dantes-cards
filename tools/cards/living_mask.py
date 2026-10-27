#!/usr/bin/env python3
"""Masks for the living card art (data/living_art.json, ArtLiving, assets/shaders/living_art.gdshaderinc).

For every card in data/living_art.json it writes assets/cards/living/<id>.png (RGB, the depth map's size: half the
picture), painted from the entry's "mask" recipe and the picture itself. No GPU, no model: plain shapes and colour.
  R  the whirl: everywhere but the figures, faded out toward the bottom ("swirl": {"fade_y": [y0, y1]}),
  G  the flames: warm, bright paint ("flame": {"warm": [lo, hi] of red - blue, "bright": [lo, hi] of luminance}),
     outside the figures,
  B  the hair and cloth that sway ("sway": ellipses [cx, cy, rx, ry], each ramped from 0 at its root to 1 at its tip
     along x: "from": [x_root, x_tip]),
and then
  "still"   ellipses taken out of R and G (shapes that must keep their outline, such as birds),
  "protect" ellipses black in every channel (faces: nothing may bend them).
"figures" are polygons the whirl and the flames go around. Every shape is feathered, so the motion fades in softly.
All coordinates are UV of the full picture (0..1, y down).

Usage: python -I tools/cards/living_mask.py [--only id,id] [--preview out.png]
Then run `godot --headless --import` so Godot writes the .png.import files.
"""
import argparse
import json
import site
import sys
from pathlib import Path

sys.path.append(site.getusersitepackages())

import numpy as np  # noqa: E402
from PIL import Image, ImageDraw, ImageFilter  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "data/living_art.json"
OUT = ROOT / "assets/cards/living"
FEATHER = 0.018  # blur radius of every shape, in UV of the picture's height


def _ellipse(size, e, scale=1.0):
    w, h = size
    cx, cy, rx, ry = e
    im = Image.new("L", size, 0)
    ImageDraw.Draw(im).ellipse([(cx - rx * scale) * w, (cy - ry * scale) * h, (cx + rx * scale) * w,
                                (cy + ry * scale) * h], fill=255)
    return im


def _soft(im, radius_uv, size):
    return np.asarray(im.filter(ImageFilter.GaussianBlur(radius_uv * size[1])), np.float32) / 255.0


def _smooth(lo, hi, x):
    t = np.clip((x - lo) / max(1e-6, hi - lo), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def build(card_id, recipe):
    depth = ROOT / f"assets/cards/depth/{card_id}.png"
    art = Image.open(ROOT / f"assets/cards/art/{card_id}.jpg").convert("RGB")
    size = Image.open(depth).size if depth.exists() else (art.width // 2, art.height // 2)
    w, h = size
    rgb = np.asarray(art.resize(size, Image.LANCZOS), np.float32) / 255.0
    ys = (np.arange(h, dtype=np.float32)[:, None] + 0.5) / h
    xs = (np.arange(w, dtype=np.float32)[None, :] + 0.5) / w

    fig = Image.new("L", size, 0)
    for poly in recipe.get("figures", []):
        ImageDraw.Draw(fig).polygon([(x * w, y * h) for x, y in poly], fill=255)
    # Grown a little before the feather, so the flow fades out before it reaches an outline (no ghost of the edge).
    figure = _soft(fig.filter(ImageFilter.MaxFilter(5)), FEATHER * 1.4, size)

    sw = recipe.get("swirl", {})
    fade = sw.get("fade_y", [1.0, 1.0])
    r = (1.0 - _smooth(fade[0], fade[1], ys)) * np.ones_like(xs) * (1.0 - figure)

    fl = recipe.get("flame", {})
    warm_lo, warm_hi = fl.get("warm", [0.12, 0.34])
    br_lo, br_hi = fl.get("bright", [0.22, 0.55])
    warm = _smooth(warm_lo, warm_hi, rgb[..., 0] - rgb[..., 2])
    lum = rgb @ np.array([0.3, 0.59, 0.11], np.float32)
    g = warm * _smooth(br_lo, br_hi, lum)
    g = np.asarray(Image.fromarray((g * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2.0)), np.float32) / 255
    g *= 1.0 - figure

    b = np.zeros((h, w), np.float32)
    for s in recipe.get("sway", []):
        e = s["ellipse"]
        x0, x1 = s.get("from", [e[0] - e[2], e[0] + e[2]])
        ramp = _smooth(min(x0, x1), max(x0, x1), xs) if x1 >= x0 else 1.0 - _smooth(x1, x0, xs)
        b = np.maximum(b, _soft(_ellipse(size, e), FEATHER, size) * ramp)

    still = np.zeros((h, w), np.float32)
    for e in recipe.get("still", []):
        still = np.maximum(still, _soft(_ellipse(size, e, 1.15), FEATHER, size))
    r *= 1.0 - still
    g *= 1.0 - still * 0.85  # a bird over the fire may glow with it, but must not ripple

    protect = np.zeros((h, w), np.float32)
    for e in recipe.get("protect", []):
        protect = np.maximum(protect, _soft(_ellipse(size, e, 1.25), FEATHER, size))
    keep = 1.0 - protect
    out = np.stack([r * keep, g * keep, b * keep], -1)
    return Image.fromarray(np.clip(out * 255 + 0.5, 0, 255).astype(np.uint8), "RGB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--preview", default="", help="also save the mask over the picture, for checking the shapes")
    a = ap.parse_args()
    cards = json.loads(DATA.read_text(encoding="utf-8"))["cards"]
    only = [s for s in a.only.split(",") if s]
    OUT.mkdir(parents=True, exist_ok=True)
    for card_id, entry in cards.items():
        if only and card_id not in only:
            continue
        mask = build(card_id, entry.get("mask", {}))
        mask.save(OUT / f"{card_id}.png", optimize=True)
        print("living mask:", card_id, mask.size)
        if a.preview:
            art = Image.open(ROOT / f"assets/cards/art/{card_id}.jpg").convert("RGB").resize(mask.size)
            over = Image.blend(art, mask, 0.6)
            sheet = Image.new("RGB", (mask.width * 3, mask.height))
            sheet.paste(art, (0, 0))
            sheet.paste(mask, (mask.width, 0))
            sheet.paste(over, (mask.width * 2, 0))
            sheet.save(a.preview if len(cards) == 1 or only else a.preview.replace(".png", f"_{card_id}.png"))


if __name__ == "__main__":
    main()
