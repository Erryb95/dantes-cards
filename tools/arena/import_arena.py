"""Fetches the painted Acheron board from the ComfyUI PC (read-only /view requests) and installs it.

  python tools/arena/import_arena.py

Sources: output/dantes_arena/<name>.png (made by the ComfyUI session, see docs/ARENA_BRIEF.md). Originals are kept in
art_src/arena/; the game reads assets/arenas/acheron_{board.jpg,frame.png,mist.png} and assets/arenas/props/*.png.
"""
import io
import json
import os
import urllib.parse
import urllib.request

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BASE = open(r"C:\Servers\comfy_url.txt", encoding="utf-8").readline().strip().rstrip("/")
# name -> (destination under assets/arenas, max size, keep alpha)
FILES = {
    "arena_acheron_board": ("acheron_board.jpg", (2560, 1440), False),
    "arena_acheron_frame": ("acheron_frame.png", (2560, 1440), True),
    "arena_acheron_mist": ("acheron_mist.png", (2560, 512), True),
    "prop_boat": ("props/boat.png", (768, 384), True),
    "prop_bell": ("props/bell.png", (384, 512), True),
    "prop_tablet": ("props/tablet.png", (512, 384), True),
    "prop_brazier": ("props/brazier.png", (384, 512), True),
    "prop_skulls": ("props/skulls.png", (512, 384), True),
}


def fetch(name: str) -> bytes | None:
    for fn in (name + ".png", name + "_s777.png", name + "_s777_00001_.png", name + "_00001_.png"):
        q = urllib.parse.urlencode({"subfolder": "dantes_arena", "type": "output", "filename": fn})
        try:
            return urllib.request.urlopen(BASE + "/view?" + q, timeout=60).read()
        except Exception:  # noqa: BLE001 - not there (yet)
            continue
    return None


def main() -> None:
    got = []
    for name, (dst, size, alpha) in FILES.items():
        out = os.path.join(ROOT, "assets", "arenas", dst)
        if os.path.exists(out):
            continue
        data = fetch(name)
        if data is None:
            continue
        os.makedirs(os.path.join(ROOT, "art_src", "arena"), exist_ok=True)
        open(os.path.join(ROOT, "art_src", "arena", name + ".png"), "wb").write(data)
        im = Image.open(io.BytesIO(data)).convert("RGBA" if alpha else "RGB")
        im.thumbnail(size, Image.LANCZOS)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        if alpha:
            im.save(out, optimize=True)
        else:
            im.save(out, quality=90)
        got.append(name)
    normal_src = os.path.join(ROOT, "art_src", "arena", "blockout", "board_normal_linear.png")
    normal_dst = os.path.join(ROOT, "assets", "arenas", "acheron_normal.png")
    if "arena_acheron_board" in got and os.path.exists(normal_src):
        # The painting follows the blockout's depth, so the blockout's normals light it correctly.
        board = Image.open(os.path.join(ROOT, "assets", "arenas", "acheron_board.jpg"))
        Image.open(normal_src).convert("RGB").resize(board.size, Image.LANCZOS).save(normal_dst)
    if got:
        p = os.path.join(ROOT, "data", "arenas.json")
        d = json.load(open(p, encoding="utf-8"))
        for a in d["arenas"]:
            if a["id"] == "acheron":
                for key, fn in (("board", "acheron_board.jpg"), ("frame", "acheron_frame.png"), ("mist", "acheron_mist.png"),
                        ("normal", "acheron_normal.png")):
                    if os.path.exists(os.path.join(ROOT, "assets", "arenas", fn)):
                        a[key] = fn
        json.dump(d, open(p, "w", encoding="utf-8", newline="\n"), indent=2, ensure_ascii=False)
    print("imported", len(got), " ".join(got))


if __name__ == "__main__":
    main()
