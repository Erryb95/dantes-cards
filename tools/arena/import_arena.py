"""Fetches the painted arena boards and props from the ComfyUI PC (read-only /view requests) and installs them.

  python tools/arena/import_arena.py            # import what is new, list what is still missing
  python tools/arena/import_arena.py --force    # re-import files that are already installed

Sources: output/dantes_arena/ on the ComfyUI PC (made by the image session, see docs/ARENA_BRIEF.md):
  arena_<id>_board*.png  2560x1440 opaque   -> assets/arenas/<id>_board.jpg
  arena_<id>_frame*.png  2560x1440 alpha    -> assets/arenas/<id>_frame.png   (optional)
  arena_<id>_mist*.png   2560x512 alpha     -> assets/arenas/<id>_mist.png
  prop_<id>_<name>*.png  alpha              -> assets/arenas/props/<id>_<name>.png  (names from data/arenas.json)
The Acheron keeps its first names (prop_boat, prop_bell, ...). Originals are kept in art_src/arena/. When a file has
several takes (name_00001_, name_00002_ ...) the newest is used. Re-run it whenever the image session paints more.
"""
import io
import json
import os
import sys
import urllib.parse
import urllib.request

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BASE = open(r"C:\Servers\comfy_url.txt", encoding="utf-8").readline().strip().rstrip("/")
SUBFOLDER = "dantes_arena"
ARENAS_JSON = os.path.join(ROOT, "data", "arenas.json")
PROP_MAX = (768, 768)
# The Acheron's files predate the per-arena naming: name -> (destination under assets/arenas, max size, keep alpha)
LEGACY = {
    "arena_acheron_board": ("acheron_board.jpg", (2560, 1440), False),
    "arena_acheron_frame": ("acheron_frame.png", (2560, 1440), True),
    "arena_acheron_mist": ("acheron_mist.png", (2560, 512), True),
    "prop_boat": ("props/boat.png", (768, 384), True),
    "prop_bell": ("props/bell.png", (384, 512), True),
    "prop_tablet": ("props/tablet.png", (512, 384), True),
    "prop_brazier": ("props/brazier.png", (384, 512), True),
    "prop_skulls": ("props/skulls.png", (512, 384), True),
}


def wanted(arenas: list) -> dict:
    """Every file the game can use: legacy Acheron names plus board / frame / mist / props per arena."""
    files = dict(LEGACY)
    for a in arenas:
        aid = a["id"]
        if aid == "acheron":
            continue
        files["arena_%s_board" % aid] = ("%s_board.jpg" % aid, (2560, 1440), False)
        files["arena_%s_frame" % aid] = ("%s_frame.png" % aid, (2560, 1440), True)
        files["arena_%s_mist" % aid] = ("%s_mist.png" % aid, (2560, 512), True)
        for p in a.get("props", []):
            files["prop_%s_%s" % (aid, p["name"])] = ("props/%s_%s.png" % (aid, p["name"]), PROP_MAX, True)
    return files


def _get(fn: str) -> bytes | None:
    q = urllib.parse.urlencode({"subfolder": SUBFOLDER, "type": "output", "filename": fn})
    try:
        return urllib.request.urlopen(BASE + "/view?" + q, timeout=60).read()
    except Exception:  # noqa: BLE001 - not there (yet)
        return None


def history_names() -> list[str]:
    """Filenames ComfyUI reports in output/dantes_arena (finds takes with unusual suffixes)."""
    try:
        h = json.loads(urllib.request.urlopen(BASE + "/history?max_items=1000", timeout=60).read())
    except Exception:  # noqa: BLE001 - history is only a hint
        return []
    out = []
    for v in h.values():
        for o in v.get("outputs", {}).values():
            for im in o.get("images", []):
                if im.get("subfolder", "").replace("\\", "/") == SUBFOLDER and im.get("type") == "output":
                    out.append(im["filename"])
    return out


def fetch(name: str, known: list[str]) -> tuple[bytes, str] | None:
    """The newest take of `name`: exact name, seeded names, numbered takes, or any history file starting with it."""
    cands = [n for n in known if n.startswith(name) and n.endswith(".png")
             and not n[len(name):len(name) + 1].isalpha()]  # prop_lust_rock must not match prop_lust_rocks
    numbered = []
    for i in range(12, 0, -1):
        numbered += [name + "_%05d_.png" % i, name + "_s777_%05d_.png" % i]
    for fn in sorted(set(cands), reverse=True) + [name + ".png", name + "_s777.png"] + numbered:
        data = _get(fn)
        if data is not None:
            return data, fn
    return None


def install(data: bytes, out: str, size: tuple, alpha: bool) -> str | None:
    im = Image.open(io.BytesIO(data))
    if alpha:
        if im.mode not in ("RGBA", "LA", "PA") and "transparency" not in im.info:
            return "no alpha channel"
        im = im.convert("RGBA")
        if im.getchannel("A").getextrema()[0] == 255:
            return "alpha channel is fully opaque"
    else:
        im = im.convert("RGB")
    im.thumbnail(size, Image.LANCZOS)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    if alpha:
        im.save(out, optimize=True)
    else:
        im.save(out, quality=90)
    return None


def main() -> None:
    force = "--force" in sys.argv
    d = json.load(open(ARENAS_JSON, encoding="utf-8"))
    files = wanted(d["arenas"])
    known = history_names()
    got, missing, rejected = [], [], []
    for name, (dst, size, alpha) in files.items():
        out = os.path.join(ROOT, "assets", "arenas", dst)
        if os.path.exists(out) and not force:
            continue
        r = fetch(name, known)
        if r is None:
            missing.append(name)
            continue
        data, fn = r
        why = install(data, out, size, alpha)
        if why is not None:
            rejected.append("%s (%s: %s)" % (name, fn, why))
            continue
        os.makedirs(os.path.join(ROOT, "art_src", "arena"), exist_ok=True)
        open(os.path.join(ROOT, "art_src", "arena", name + ".png"), "wb").write(data)
        got.append(name)
    normal_src = os.path.join(ROOT, "art_src", "arena", "blockout", "board_normal_linear.png")
    normal_dst = os.path.join(ROOT, "assets", "arenas", "acheron_normal.png")
    if "arena_acheron_board" in got and os.path.exists(normal_src):
        # The painting follows the blockout's depth, so the blockout's normals light it correctly.
        board = Image.open(os.path.join(ROOT, "assets", "arenas", "acheron_board.jpg"))
        Image.open(normal_src).convert("RGB").resize(board.size, Image.LANCZOS).save(normal_dst)
    # Point arenas.json at the Acheron's optional layers once they exist (the other arenas name theirs already).
    for a in d["arenas"]:
        if a["id"] == "acheron":
            for key, fn in (("board", "acheron_board.jpg"), ("frame", "acheron_frame.png"),
                            ("mist", "acheron_mist.png"), ("normal", "acheron_normal.png")):
                if os.path.exists(os.path.join(ROOT, "assets", "arenas", fn)) and a.get(key) != fn:
                    a[key] = fn
    with open(ARENAS_JSON, encoding="utf-8") as f:
        before = f.read()
    after = json.dumps(d, indent=2, ensure_ascii=False) + "\n"
    if json.loads(before) != json.loads(after):
        open(ARENAS_JSON, "w", encoding="utf-8", newline="\n").write(after)
    print("imported %d: %s" % (len(got), " ".join(got) or "-"))
    if rejected:
        print("rejected %d: %s" % (len(rejected), "; ".join(rejected)))
    optional = {n for n in missing if n.endswith("_frame") or n in ("prop_tablet", "arena_acheron_mist")}
    need = [n for n in missing if n not in optional]
    print("still missing %d: %s" % (len(need), " ".join(need) or "-"))
    if optional:
        print("optional, not painted: %s" % " ".join(sorted(optional)))


if __name__ == "__main__":
    main()
