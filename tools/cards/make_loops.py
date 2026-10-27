#!/usr/bin/env python3
"""Converts Wan card loops (mp4) into Ogg Theora files for the game: assets/cards/loops/<card id>.ogv.

A card animates in game when res://assets/cards/loops/<id>.ogv exists (see CardDB.art_loop). The source clips are
512x704 (the framing of assets/cards/art/<id>.jpg) at 16 fps; this script keeps size and rate, drops audio, closes the
loop and re-encodes with libtheora. A "_vN" suffix on the clip name is dropped from the card id (minos_v3.mp4 -> minos).

The seam: the first --xfade frames are blended with the clip's tail (out[i] = tail[i] -> head[i]), and the tail itself
is dropped, so the loop's end flows into its start.
- Clips generated with the last frame locked to the first barely move (Wan holds the picture still), so the loops are
  made from first-frame-only clips (81 frames) whose end differs from the start: use --xfade 16 (one second).
- The old locked clips (48 frames) only hitch at the seam: --xfade 6 is enough.

Usage: python tools/cards/make_loops.py <source folder with <id>.mp4> [--out assets/cards/loops] [--quality 8]
                                        [--ffmpeg path/to/ffmpeg] [--only id,id]
Then run `godot --headless --import` so Godot writes the .ogv.import / .uid files.
"""
import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

DEFAULT_FFMPEG = "C:/Progetti/Tools/ffmpeg/bin/ffmpeg.exe"
SIZE_WARN_KB = 1500
MIN_QUALITY = 6
XFADE = 16


def smooth_seam(ffmpeg: str, clip: Path, work: Path, xfade: int = XFADE) -> Path:
    """Returns a folder of PNG frames with the loop seam crossfaded (see the module docstring)."""
    raw = work / "raw"
    out = work / "out"
    raw.mkdir()
    out.mkdir()
    subprocess.run([ffmpeg, "-y", "-loglevel", "error", "-i", str(clip), "-vf", "fps=16", str(raw / "%04d.png")],
                   check=True)
    frames = sorted(raw.glob("*.png"))
    n = len(frames)
    if n <= 3 * xfade:
        for i, f in enumerate(frames):
            shutil.copy(f, out / ("%04d.png" % i))
        return out
    for i in range(n - xfade):
        im = Image.open(frames[i]).convert("RGB")
        if i < xfade:
            tail = Image.open(frames[n - xfade + i]).convert("RGB")
            im = Image.blend(tail, im, (i + 1) / (xfade + 1))
        im.save(out / ("%04d.png" % i))
    return out


def card_id(clip: Path) -> str:
    return re.sub(r"_v\d+$", "", clip.stem)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src", type=Path, help="folder with <card id>.mp4 clips")
    ap.add_argument("--out", type=Path, default=Path(__file__).resolve().parents[2] / "assets/cards/loops")
    ap.add_argument("--quality", type=int, default=8, help="libtheora -q:v to start from (0-10); lowered per clip until it fits the size budget")
    ap.add_argument("--ffmpeg", default=shutil.which("ffmpeg") or DEFAULT_FFMPEG)
    ap.add_argument("--only", default="", help="comma-separated card ids (default: every mp4 in src)")
    ap.add_argument("--xfade", type=int, default=XFADE, help="frames blended across the loop seam (see the docstring)")
    args = ap.parse_args()

    only = {s for s in args.only.split(",") if s}
    clips = sorted(p for p in args.src.glob("*.mp4") if not only or card_id(p) in only)
    if not clips:
        print("no mp4 clips found in", args.src)
        return 1
    args.out.mkdir(parents=True, exist_ok=True)
    for clip in clips:
        dst = args.out / (card_id(clip) + ".ogv")
        work = Path(tempfile.mkdtemp(prefix="loop_"))
        frames = smooth_seam(args.ffmpeg, clip, work, args.xfade)
        # Start at the requested quality and step down until the file fits the size budget.
        q = args.quality
        while True:
            cmd = [args.ffmpeg, "-y", "-loglevel", "error", "-framerate", "16", "-i", str(frames / "%04d.png"),
                   "-an", "-c:v", "libtheora", "-q:v", str(q), "-pix_fmt", "yuv420p", str(dst)]
            subprocess.run(cmd, check=True)
            kb = dst.stat().st_size // 1024
            if kb <= SIZE_WARN_KB or q <= MIN_QUALITY:
                break
            q -= 1
        shutil.rmtree(work, ignore_errors=True)
        print(f"{dst.name}: {kb} KB (q:v {q})" + ("  (over budget)" if kb > SIZE_WARN_KB else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
