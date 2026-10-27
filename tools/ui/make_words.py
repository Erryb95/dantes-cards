"""Painted headline words: keys gilded lettering painted on flat black (Qwen-Image) into a transparent PNG.

    python tools/ui/make_words.py <painted.png> <slug> [--height 220]

Writes assets/ui/words/<slug>.png (and keeps the painting in art_src/ui/words/). The letters are found as the
bright pixels, closed and hole-filled so their dark engraved lines stay opaque; outside them the black fades out
with the paint's own brightness, so the soft edges and the hatched drop shadow stay soft. The result is trimmed to
the letters with a small margin and scaled to `height` px.
"""
import argparse
import os
import shutil

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def key(img: Image.Image) -> Image.Image:
    rgb = np.asarray(img.convert("RGB")).astype(np.float32)
    lum = rgb.max(axis=2)
    soft = np.clip((lum - 14.0) / 50.0, 0.0, 1.0)  # the paint's own fade into the black
    # The letters: bright paint, closed over the engraved lines and with the counters' dark hatching filled.
    solid = lum > 60.0
    solid = ndimage.binary_closing(solid, structure=np.ones((7, 7)), iterations=1)
    # Fill the small holes (engraved lines inside a stroke), not the counters of O, R, A...
    holes, n = ndimage.label(ndimage.binary_fill_holes(solid) & ~solid)
    if n:
        sizes = ndimage.sum(np.ones_like(lum), holes, index=np.arange(1, n + 1))
        small = np.concatenate([[False], sizes < 1200.0])
        solid = solid | small[holes]
    solid = ndimage.binary_erosion(solid, iterations=1)
    solid_a = np.asarray(Image.fromarray((solid * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2)))
    alpha = np.maximum(soft, solid_a / 255.0)
    out = np.dstack([rgb, alpha * 255.0]).clip(0, 255).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def trim(img: Image.Image, pad: int = 10) -> Image.Image:
    a = np.asarray(img)[:, :, 3]
    ys, xs = np.where(a > 8)
    box = (max(0, xs.min() - pad), max(0, ys.min() - pad), min(img.width, xs.max() + pad + 1),
           min(img.height, ys.max() + pad + 1))
    return img.crop(box)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("slug")
    ap.add_argument("--height", type=int, default=220)
    a = ap.parse_args()
    src_dir = os.path.join(ROOT, "art_src", "ui", "words")
    out_dir = os.path.join(ROOT, "assets", "ui", "words")
    os.makedirs(src_dir, exist_ok=True)
    os.makedirs(out_dir, exist_ok=True)
    shutil.copyfile(a.src, os.path.join(src_dir, a.slug + ".png"))
    img = trim(key(Image.open(a.src)))
    if img.height > a.height:
        img = img.resize((round(img.width * a.height / img.height), a.height), Image.LANCZOS)
    img.save(os.path.join(out_dir, a.slug + ".png"), optimize=True)
    print(a.slug, img.size)


if __name__ == "__main__":
    main()
