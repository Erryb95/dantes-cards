#!/usr/bin/env python3
"""Depth maps for the card art, for the parallax in assets/shaders/card_fx.gdshader (CardDB.art_depth).

For every assets/cards/art/<id>.jpg it writes assets/cards/depth/<id>.png, and for every assets/cards/heroes/<id>.jpg
assets/cards/depth/heroes/<id>.png: 8-bit greyscale at half the picture's size (256x352 for a 512x704 card), near =
white, normalised per picture and smoothed so the parallax bends the painting instead of tearing it.

Model: Depth Anything V2 Small (Apache-2.0; only the Small size is: Base / Large / Giant are CC-BY-NC, never use them),
ONNX export from onnx-community/depth-anything-v2-small (Apache-2.0), run on the CPU with onnxruntime. The model lives
outside the repo (DEFAULT_MODEL); see assets/CREDITS.md.

Re-runnable: a picture is skipped when its depth map exists and tools/cards/depth_manifest.json records the same source
hash and settings version, so new art (a new class) only costs its own images.

Usage (run with -I: the model is downloaded data; the script adds the user site-packages where onnxruntime lives):
    python -I tools/cards/make_depth.py [--model path/to/model.onnx] [--only id,id] [--force]
                                        [--sheet out.png [--sheet-count 12]]
Then run `godot --headless --import` so Godot writes the .png.import files.
"""
import argparse
import hashlib
import json
import site
import sys
import time
from pathlib import Path

sys.path.append(site.getusersitepackages())  # onnxruntime is a user install; -I leaves it off the path

import numpy as np  # noqa: E402
from PIL import Image, ImageFilter  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MODEL = "C:/Progetti/Tools/depth/da2_small_onnx/model.onnx"
MANIFEST = ROOT / "tools/cards/depth_manifest.json"
VERSION = 1  # bump when the processing below changes, to rebuild every map
SHORT_SIDE = 518  # the model's training resolution (multiple of 14)
MEAN = np.array([0.485, 0.456, 0.406], np.float32)
STD = np.array([0.229, 0.224, 0.225], np.float32)
LOW_PCT, HIGH_PCT = 2.0, 98.0  # per-image normalisation range (ignores a few outliers)
BLUR = 2.2  # Gaussian radius at the output size, in pixels
GAMMA = 0.9  # < 1 lifts the middle a little so figures separate from the far background


def jobs() -> list[tuple[str, Path, Path]]:
    out = []
    for p in sorted((ROOT / "assets/cards/art").glob("*.jpg")):
        out.append((p.stem, p, ROOT / "assets/cards/depth" / (p.stem + ".png")))
    for p in sorted((ROOT / "assets/cards/heroes").glob("*.jpg")):
        out.append(("hero:" + p.stem, p, ROOT / "assets/cards/depth/heroes" / (p.stem + ".png")))
    return out


def sha1(path: Path) -> str:
    return hashlib.sha1(path.read_bytes()).hexdigest()


def model_input(img: Image.Image) -> np.ndarray:
    w, h = img.size
    s = SHORT_SIDE / min(w, h)
    tw, th = (round(w * s / 14) * 14, round(h * s / 14) * 14)
    x = np.asarray(img.convert("RGB").resize((tw, th), Image.BICUBIC), np.float32) / 255.0
    x = (x - MEAN) / STD
    return x.transpose(2, 0, 1)[None]


def depth_map(session, img: Image.Image) -> Image.Image:
    pred = session.run(None, {"pixel_values": model_input(img)})[0][0]  # relative disparity: larger = nearer
    lo, hi = np.percentile(pred, [LOW_PCT, HIGH_PCT])
    d = np.clip((pred - lo) / max(hi - lo, 1e-6), 0.0, 1.0) ** GAMMA
    out_size = (img.size[0] // 2, img.size[1] // 2)
    im = Image.fromarray((d * 255.0 + 0.5).astype(np.uint8), "L").resize(out_size, Image.BICUBIC)
    # A median drops speckles in the engraving hatching, the blur rounds depth edges so the parallax never tears.
    return im.filter(ImageFilter.MedianFilter(3)).filter(ImageFilter.GaussianBlur(BLUR))


def contact_sheet(pairs: list[tuple[Path, Path]], out: Path) -> None:
    cw, ch = 256, 352
    cols = 4
    rows = (len(pairs) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cw * 2, rows * ch), (20, 10, 10))
    for i, (src, dep) in enumerate(pairs):
        x, y = (i % cols) * cw * 2, (i // cols) * ch
        sheet.paste(Image.open(src).convert("RGB").resize((cw, ch)), (x, y))
        sheet.paste(Image.open(dep).convert("RGB").resize((cw, ch)), (x + cw, y))
    sheet.save(out)
    print("sheet:", out)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--only", default="", help="comma-separated ids (hero ids as hero:<id>)")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--sheet", default="", help="also write a contact sheet of art / depth pairs to this file")
    ap.add_argument("--sheet-count", type=int, default=12)
    a = ap.parse_args()

    manifest = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {}
    only = {s.strip() for s in a.only.split(",") if s.strip()}
    todo = []
    for key, src, dst in jobs():
        if only and key not in only:
            continue
        h = sha1(src)
        if not a.force and dst.exists() and manifest.get(key) == {"src": h, "v": VERSION}:
            continue
        todo.append((key, src, dst, h))
    print(f"{len(todo)} depth maps to make")
    if todo:
        import onnxruntime as ort
        opts = ort.SessionOptions()
        opts.log_severity_level = 3
        session = ort.InferenceSession(a.model, opts, providers=["CPUExecutionProvider"])
        t0 = time.time()
        for i, (key, src, dst, h) in enumerate(todo):
            dst.parent.mkdir(parents=True, exist_ok=True)
            depth_map(session, Image.open(src)).save(dst, optimize=True)
            manifest[key] = {"src": h, "v": VERSION}
            if (i + 1) % 20 == 0 or i + 1 == len(todo):
                print(f"  {i + 1}/{len(todo)}  {time.time() - t0:.0f}s")
                MANIFEST.write_text(json.dumps(manifest, indent=1, sort_keys=True) + "\n")
    # Forget pictures that were deleted.
    keys = {k for k, _, _ in jobs()}
    for k in [k for k in manifest if k not in keys]:
        del manifest[k]
    MANIFEST.write_text(json.dumps(manifest, indent=1, sort_keys=True) + "\n")

    if a.sheet:
        all_jobs = [(s, d) for _, s, d in jobs() if d.exists()]
        step = max(1, len(all_jobs) // a.sheet_count)
        contact_sheet(all_jobs[::step][: a.sheet_count], Path(a.sheet))
    return 0


if __name__ == "__main__":
    sys.exit(main())
