"""Builds the game's music from whole public-domain recordings (no cuts, no loops).

  python tools/audio/build_music.py [--src <music_src dir>]

Sources: the full movements downloaded for the sister project (Dante's Vengeance, art_src/music_src/<piece>/source.*,
each with its meta.json). Every piece is kept complete: it is only loudness-normalised (ffmpeg loudnorm, two-pass,
linear, so the orchestral dynamics stay intact) and encoded to Ogg Vorbis. Output: assets/audio/music/<playlist>/cN_0.ogg,
the names Sfx.play_music() scans. Credits: assets/CREDITS.md.
"""
import argparse
import json
import os
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FFMPEG = r"C:\Progetti\Tools\ffmpeg\bin\ffmpeg.exe"
DEFAULT_SRC = r"C:\Progetti\Dante's Vengange\art_src\music_src"

# playlist folder -> pieces, in play order (the game shuffles the start point, then plays them in turn)
PLAYLISTS = {
    "intro": ["brahms-requiem-2-denn-alles", "cherubini-introitus", "tchaikovsky6-iv-finale", "suk-meditation"],
    "music_combat": ["cherubini-dies-irae", "beethoven-coriolan", "mozart40-i", "tchaikovsky6-iii"],
    "music_boss": ["brahms4-iv", "beethoven-egmont", "brahms-tragic-overture"],
}
TARGET = {"I": -18.0, "TP": -1.5, "LRA": 20.0}
QUALITY = "0.5"  # libvorbis quality, about 72 kbit/s stereo


def source(src: str, piece: str) -> str:
    folder = os.path.join(src, piece)
    for f in os.listdir(folder):
        if f.startswith("source."):
            return os.path.join(folder, f)
    raise FileNotFoundError(folder)


def measure(path: str) -> dict:
    af = "loudnorm=I=%(I)s:TP=%(TP)s:LRA=%(LRA)s:print_format=json" % TARGET
    r = subprocess.run([FFMPEG, "-hide_banner", "-nostats", "-i", path, "-af", af, "-f", "null", "-"],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    m = re.search(r"\{[^{}]*\"input_i\"[^{}]*\}", r.stderr, re.S)
    if not m:
        raise RuntimeError("loudnorm measure failed for " + path)
    return json.loads(m.group(0))


def encode(path: str, out: str, m: dict) -> None:
    af = ("loudnorm=I=%(I)s:TP=%(TP)s:LRA=%(LRA)s" % TARGET
          + ":measured_I=%s:measured_TP=%s:measured_LRA=%s:measured_thresh=%s:offset=%s:linear=true"
          % (m["input_i"], m["input_tp"], m["input_lra"], m["input_thresh"], m["target_offset"]))
    subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-i", path, "-af", af, "-ar", "44100",
                    "-c:a", "libvorbis", "-q:a", QUALITY, "-map_metadata", "-1", out], check=True)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=DEFAULT_SRC)
    args = ap.parse_args()
    manifest = {}
    for playlist, pieces in PLAYLISTS.items():
        folder = os.path.join(ROOT, "assets", "audio", "music", playlist)
        os.makedirs(folder, exist_ok=True)
        for f in os.listdir(folder):  # old cut clips and their import files
            if re.fullmatch(r"c\d+_0\.ogg(\.import)?", f):
                os.remove(os.path.join(folder, f))
        for i, piece in enumerate(pieces, 1):
            src = source(args.src, piece)
            out = os.path.join(folder, "c%d_0.ogg" % i)
            encode(src, out, measure(src))
            meta = json.load(open(os.path.join(args.src, piece, "meta.json"), encoding="utf-8"))
            manifest["%s/c%d_0.ogg" % (playlist, i)] = {
                "piece": piece, "composer": meta.get("composer", ""), "title": meta.get("title", ""),
                "performer": meta.get("performer", ""), "licence": meta.get("recording_licence", ""),
                "source": meta.get("source_item", "")}
            print("%-12s c%d_0.ogg  %-28s %5.1f MB" % (playlist, i, piece, os.path.getsize(out) / 1e6), flush=True)
    with open(os.path.join(ROOT, "assets", "audio", "music", "playlists.json"), "w", encoding="utf-8",
              newline="\n") as f:
        json.dump(manifest, f, indent=1, ensure_ascii=False)
        f.write("\n")


if __name__ == "__main__":
    sys.exit(main())
