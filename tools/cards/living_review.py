#!/usr/bin/env python3
"""Review recordings of the living card art: a short mp4 per card and view, and its motion numbers.

For each card it records tests/living_preview.tscn with Godot's movie maker (no GPU job, the game's own renderer),
joins the frames into <out>/<id>_<view>.mp4 with ffmpeg and, for the "art" view (the whole picture, still on the left,
living on the right), measures the motion of the living picture:
  consecutive   mean change from one frame to the next (% of full scale): how busy it is
  area>10%      share of the picture whose peak change over the clip passes 10% (and 20%): how much of it lives
  mean peak     mean of each pixel's peak change over the clip
  faces         the strongest peak change inside the entry's "protect" shapes (95th percentile, %): faces must stay put
  still side    the same on the still picture (must be 0: a sanity check of the recording)
and compares them with the targets (TARGETS below, from Francesca's approved look).

Usage:
  python -I tools/cards/living_review.py <id>[,<id>...] [--out DIR] [--views art,zoom] [--seconds 4] [--level 2]
  python -I tools/cards/living_review.py <id> --out DIR --measure-only      (re-measure frames already recorded)
  python -I tools/cards/living_review.py --frames "<dir>/f*.png" [--box x0 y0 x1 y1]   (any frame sequence)
Godot is $DV_GODOT or C:/Progetti/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe; ffmpeg is $DV_FFMPEG,
C:/Progetti/Tools/ffmpeg/bin/ffmpeg.exe or the one on PATH. Every Godot run has a timeout. Frames are kept in
<out>/<id>_<view>/ (delete them when done).
"""
import argparse
import glob
import json
import math
import os
import shutil
import site
import subprocess
import sys
from pathlib import Path

sys.path.append(site.getusersitepackages())

import numpy as np  # noqa: E402
from PIL import Image, ImageDraw, ImageFilter  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
GODOT = os.environ.get("DV_GODOT", "C:/Progetti/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe")
FFMPEG = os.environ.get("DV_FFMPEG", "C:/Progetti/Tools/ffmpeg/bin/ffmpeg.exe")
ART_H = 1000  # tests/living_preview.gd ART_H: the "art" view's picture height; its top is at y = 40
SKIP = 6  # first frames left out of the measure (the scene settles)

# Motion targets for the "art" view at 30 fps (full level), from Francesca's approved look, which measures
# consecutive 0.38%, area>10% 30%, area>20% 15%, mean peak 9.6%, faces 0.0% for the lovers (and up to 16% for the
# small faces in the crowd, where the protection fades into the whirl). "low" barely reads as alive, "HIGH" is busy
# (consecutive) or too much of the picture (area) or a face that moves.
TARGETS = {
    "consecutive": (0.15, 0.8),
    "area10": (10.0, 50.0),
    "faces": (0.0, 16.0),
}


def ffmpeg_bin():
    if Path(FFMPEG).exists():
        return FFMPEG
    return shutil.which("ffmpeg")


def record(card, view, out, seconds, fps, level, timeout):
    d = Path(out) / f"{card}_{view}"
    if d.exists():
        shutil.rmtree(d)
    d.mkdir(parents=True)
    frames = int(seconds * fps) + SKIP
    cmd = [GODOT, "--path", str(ROOT), "res://tests/living_preview.tscn", "--resolution", "1920x1080",
           "--fixed-fps", str(fps), "--write-movie", str(d / "f.png"), "--quit-after", str(frames), "--",
           f"--what={view}", f"--card={card}"]
    if level is not None:
        cmd.append(f"--level={level}")
    log = Path(out) / f"{card}_{view}_godot.log"
    with open(log, "w", encoding="utf-8", errors="replace") as fh:
        subprocess.run(cmd, stdout=fh, stderr=subprocess.STDOUT, timeout=timeout, check=False)
    n = len(glob.glob(str(d / "f*.png")))
    if n < frames // 2:
        sys.exit(f"living review: {card} {view}: only {n} frames (see {log})")
    return d


def encode(d, mp4, fps):
    ff = ffmpeg_bin()
    if ff is None:
        print("  (no ffmpeg: frames only)")
        return None
    subprocess.run([ff, "-hide_banner", "-loglevel", "error", "-y", "-framerate", str(fps), "-start_number",
                    str(SKIP), "-i", str(Path(d) / "f%08d.png"), "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf",
                    "18", str(mp4)], check=True, timeout=600)
    return mp4


def load(files, box=None):
    frames = []
    for f in files:
        im = Image.open(f).convert("RGB")
        if box:
            im = im.crop(box)
        frames.append(np.asarray(im, np.float32) / 255.0)
    return np.stack(frames)


def motion(st):
    """Motion numbers of a frame stack (n, h, w, 3) in 0..1."""
    cons = np.abs(st[1:] - st[:-1]).mean() * 100
    peak = np.abs(st - st[0]).max(axis=0).mean(-1)
    return {"consecutive": float(cons), "area10": float((peak > 0.10).mean() * 100),
            "area20": float((peak > 0.20).mean() * 100), "mean_peak": float(peak.mean() * 100), "peak": peak}


def art_boxes(card, frame_w):
    """The still and the living picture in a frame of the "art" view (laid out for 1920x1080; the movie maker may
    record a smaller window, the stretch scales it), and the living one's size."""
    k = frame_w / 1920.0
    art = Image.open(ROOT / f"assets/cards/art/{card}.jpg")
    w = math.floor(ART_H * art.width / art.height + 0.5)
    xl = math.floor(1920 * 0.25 - w / 2 + 0.5)
    xr = math.floor(1920 * 0.75 - w / 2 + 0.5)

    def box(x):
        return (math.ceil(x * k) + 2, math.ceil(40 * k) + 2, math.floor((x + w) * k) - 2, math.floor((40 + ART_H) * k) - 2)
    bl, br = box(xl), box(xr)
    return bl, br, (br[2] - br[0] + 4, br[3] - br[1] + 4)


def face_masks(entry, size, crop_off=2, core=0.7):
    """One boolean mask per protect shape (an ellipse taken at `core` of its radii: the face itself, not the soft rim
    where the protection fades in), in the cropped picture's pixels."""
    w, h = size
    out = []
    for it in entry.get("mask", {}).get("protect", []):
        im = Image.new("L", (w, h), 0)
        dr = ImageDraw.Draw(im)
        if isinstance(it, list) and len(it) == 4 and all(isinstance(v, (int, float)) for v in it):
            cx, cy, rx, ry = it
            dr.ellipse([(cx - rx * core) * w, (cy - ry * core) * h, (cx + rx * core) * w, (cy + ry * core) * h], fill=255)
        elif isinstance(it, list):
            dr.polygon([(x * w, y * h) for x, y in it], fill=255)
        elif isinstance(it, dict):
            for e in (it["ellipse"] if it.get("ellipse") and isinstance(it["ellipse"][0], list)
                      else [it["ellipse"]] if "ellipse" in it else []):
                cx, cy, rx, ry = e
                dr.ellipse([(cx - rx * core) * w, (cy - ry * core) * h, (cx + rx * core) * w, (cy + ry * core) * h], fill=255)
            for p in (it["poly"] if it.get("poly") and isinstance(it["poly"][0][0], list)
                      else [it["poly"]] if "poly" in it else []):
                dr.polygon([(x * w, y * h) for x, y in p], fill=255)
            for r in (it["rect"] if it.get("rect") and isinstance(it["rect"][0], list)
                      else [it["rect"]] if "rect" in it else []):
                dr.rectangle([r[0] * w, r[1] * h, r[2] * w, r[3] * h], fill=255)
        m = np.asarray(im)[crop_off:h - crop_off, crop_off:w - crop_off] > 0
        out.append(m)
    return out


def measure_art(card, d, entry, out):
    files = sorted(glob.glob(str(Path(d) / "f*.png")))[SKIP:]
    left, right, size = art_boxes(card, Image.open(files[0]).width)
    st = load(files, right)
    m = motion(st)
    still = motion(load(files[:: max(1, len(files) // 12)], left))
    faces = []
    # Light painted over a face on purpose ("over": glowing eyes) is not motion of the face: left out of the measure.
    lit = np.zeros(m["peak"].shape, bool)
    fx = ROOT / f"assets/cards/living/{card}_fx.png"
    if fx.exists():
        im = Image.open(fx).convert("L").point(lambda v: 255 if v > 4 else 0).filter(ImageFilter.MaxFilter(5))
        lit = np.asarray(im.resize((size[0], size[1]), Image.NEAREST))[2:size[1] - 2, 2:size[0] - 2] > 0
        lit = lit[: m["peak"].shape[0], : m["peak"].shape[1]]
    for fm in face_masks(entry, size):
        fm = fm[: m["peak"].shape[0], : m["peak"].shape[1]] & ~lit
        if fm.any():
            faces.append(float(np.percentile(m["peak"][fm], 95) * 100))
    m["faces"] = max(faces) if faces else 0.0
    m["faces_each"] = faces
    m["still_side"] = still["mean_peak"]
    # A heat map of where it moves (peak change), next to the picture, for the review.
    heat = np.clip(m["peak"] * 4.0, 0, 1)
    pic = st[0]
    hm = np.stack([heat, heat * 0.6, 1 - heat], -1) * 0.75 + pic * 0.25
    sheet = np.concatenate([pic, hm], 1)
    Image.fromarray((sheet * 255).astype(np.uint8)).resize((sheet.shape[1] // 2, sheet.shape[0] // 2)).save(
        Path(out) / f"{card}_heat.png")
    return m


def verdict(m):
    notes = []
    for key, (lo, hi) in TARGETS.items():
        v = m[key]
        if v < lo:
            notes.append(f"{key} low")
        elif v > hi:
            notes.append(f"{key} HIGH")
    if m.get("still_side", 0) > 0.05:
        notes.append("the still side moves: the recording is not clean")
    return "ok" if not notes else ", ".join(notes)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cards", nargs="?", default="")
    ap.add_argument("--out", default=str(Path(os.environ.get("TEMP", ".")) / "living_review"))
    ap.add_argument("--views", default="art,zoom")
    ap.add_argument("--seconds", type=float, default=4.0)
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--level", type=int, default=None)
    ap.add_argument("--timeout", type=int, default=300)
    ap.add_argument("--measure-only", action="store_true")
    ap.add_argument("--frames", default="")
    ap.add_argument("--box", type=int, nargs=4, default=None)
    a = ap.parse_args()
    if a.frames:
        m = motion(load(sorted(glob.glob(a.frames)), tuple(a.box) if a.box else None))
        print("consecutive %.2f%%  area>10%% %.1f%%  area>20%% %.1f%%  mean peak %.2f%%" % (
            m["consecutive"], m["area10"], m["area20"], m["mean_peak"]))
        return
    if not a.cards:
        ap.error("name a card (or --frames)")
    entries = json.loads((ROOT / "data/living_art.json").read_text(encoding="utf-8"))["cards"]
    Path(a.out).mkdir(parents=True, exist_ok=True)
    for card in a.cards.split(","):
        entry = entries.get(card, {})
        if not entry:
            print(f"living review: {card} has no entry in data/living_art.json (recording the still painting)")
        for view in a.views.split(","):
            d = Path(a.out) / f"{card}_{view}"
            if not a.measure_only:
                d = record(card, view, a.out, a.seconds, a.fps, a.level, a.timeout)
                mp4 = encode(d, Path(a.out) / f"{card}_{view}.mp4", a.fps)
                if mp4:
                    print(f"{card} {view}: {mp4}")
            if view == "art":
                m = measure_art(card, d, entry, a.out)
                faces = " ".join("%.1f" % f for f in m["faces_each"])
                print("%s motion: consecutive %.2f%%  area>10%% %.1f%%  area>20%% %.1f%%  mean peak %.2f%%  "
                      "faces %.1f%% [%s]  still side %.2f%%  -> %s" % (
                          card, m["consecutive"], m["area10"], m["area20"], m["mean_peak"], m["faces"], faces,
                          m["still_side"], verdict(m)))
                print(f"  heat map: {Path(a.out) / (card + '_heat.png')}")


if __name__ == "__main__":
    main()
