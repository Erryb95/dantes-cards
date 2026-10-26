#!/usr/bin/env python3
"""Converts Wan card loops (mp4) into Ogg Theora files for the game: assets/cards/loops/<card id>.ogv.

A card animates in game when res://assets/cards/loops/<id>.ogv exists (see CardDB.art_loop). The source clips are
512x704 (the framing of assets/cards/art/<id>.jpg), 48 frames at 16 fps, seamless; this script keeps size and rate,
drops audio and re-encodes with libtheora.

Usage: python tools/cards/make_loops.py <source folder with <id>.mp4> [--out assets/cards/loops] [--quality 8]
                                        [--ffmpeg path/to/ffmpeg] [--only id,id]
Then run `godot --headless --import` so Godot writes the .ogv.import / .uid files.
"""
import argparse
import shutil
import subprocess
import sys
from pathlib import Path

DEFAULT_FFMPEG = "C:/Progetti/Tools/ffmpeg/bin/ffmpeg.exe"
SIZE_WARN_KB = 1500
MIN_QUALITY = 6


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src", type=Path, help="folder with <card id>.mp4 clips")
    ap.add_argument("--out", type=Path, default=Path(__file__).resolve().parents[2] / "assets/cards/loops")
    ap.add_argument("--quality", type=int, default=8, help="libtheora -q:v to start from (0-10); lowered per clip until it fits the size budget")
    ap.add_argument("--ffmpeg", default=shutil.which("ffmpeg") or DEFAULT_FFMPEG)
    ap.add_argument("--only", default="", help="comma-separated card ids (default: every mp4 in src)")
    args = ap.parse_args()

    only = {s for s in args.only.split(",") if s}
    clips = sorted(p for p in args.src.glob("*.mp4") if not only or p.stem in only)
    if not clips:
        print("no mp4 clips found in", args.src)
        return 1
    args.out.mkdir(parents=True, exist_ok=True)
    for clip in clips:
        dst = args.out / (clip.stem + ".ogv")
        # Start at the requested quality and step down until the file fits the size budget.
        q = args.quality
        while True:
            cmd = [args.ffmpeg, "-y", "-loglevel", "error", "-i", str(clip), "-an", "-vf", "fps=16",
                   "-c:v", "libtheora", "-q:v", str(q), "-pix_fmt", "yuv420p", str(dst)]
            subprocess.run(cmd, check=True)
            kb = dst.stat().st_size // 1024
            if kb <= SIZE_WARN_KB or q <= MIN_QUALITY:
                break
            q -= 1
        print(f"{dst.name}: {kb} KB (q:v {q})" + ("  (over budget)" if kb > SIZE_WARN_KB else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
