"""Fetches the optional painted UI pieces from the ComfyUI PC (read-only /view requests) and installs them.

  python tools/ui/import_ui_pieces.py                      # the lists below: import what is new, list what is missing
  python tools/ui/import_ui_pieces.py --force              # re-import
  python tools/ui/import_ui_pieces.py --names harpy,minos  # painted card names (see below)

Pieces: art_src/tutorial_art.json and art_src/deck_ui_art.json (one entry per piece, with where it goes). The ComfyUI
session paints them into output/dantes_ui as <id>_00001_.png, the words as word_<id>_00001_.png.
- "kind": "portrait" (or no kind, opaque): assets/ui/<id>.png at the listed size (UiSkin picks it up by name);
- "kind": "word": gilded lettering on flat black, keyed by tools/ui/make_words.py into assets/ui/words/<id>.png;
- "alpha": true: copied as is (already cut out) to assets/ui/<id>.png. Each one is wired where its "replaces" says.
A piece marked "unused" (with the reason) was compared in the game and left out; it is not installed.
Painted card names: output/dantes_ui/card_names/name_<card id>_00001_.png (gilded lettering on black, 1664 or 2048 px
wide strips), keyed like the words into assets/cards/names/<card id>.png, 160 px tall (CardDB.name_tex).
Originals go to art_src/ui/pieces/, art_src/ui/words/ and art_src/cards/names/.
"""
import io
import json
import os
import sys
import urllib.parse
import urllib.request

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_words  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LISTS = ["tutorial_art.json", "deck_ui_art.json"]
NAME_HEIGHT = 160


def fetch(base: str, sub: str, name: str) -> bytes | None:
    q = urllib.parse.urlencode({"subfolder": sub, "type": "output", "filename": name})
    try:
        return urllib.request.urlopen(base + "/view?" + q, timeout=60).read()
    except Exception:  # noqa: BLE001 - not painted (yet)
        return None


def import_pieces(base: str, force: bool) -> None:
    got, missing = [], []
    for lst in LISTS:
        for p in json.load(open(os.path.join(ROOT, "art_src", lst), encoding="utf-8"))["assets"]:
            pid, kind = p["id"], p.get("kind", "")
            if p.get("unused"):
                continue  # painted, compared in the game and left out (the reason is in the list)
            if kind == "word":
                out = os.path.join(ROOT, "assets", "ui", "words", pid + ".png")
                name = "word_%s_00001_.png" % pid
            else:
                out = os.path.join(ROOT, "assets", "ui", pid + ".png")
                name = "%s_00001_.png" % pid
            if os.path.exists(out) and not force:
                continue
            data = fetch(base, "dantes_ui", name)
            if data is None:
                missing.append(pid)
                continue
            if kind == "word":
                src = os.path.join(ROOT, "art_src", "ui", "words", pid + ".png")
                os.makedirs(os.path.dirname(src), exist_ok=True)
                open(src, "wb").write(data)
                make_words.make(src, pid, 220, os.path.dirname(out), os.path.dirname(src))
            else:
                src_dir = os.path.join(ROOT, "art_src", "ui", "pieces")
                os.makedirs(src_dir, exist_ok=True)
                open(os.path.join(src_dir, pid + ".png"), "wb").write(data)
                im = Image.open(io.BytesIO(data))
                im = im.convert("RGBA" if p.get("alpha") else "RGB")
                size = tuple(p.get("size", im.size))
                if im.size != size:
                    im = im.resize(size, Image.LANCZOS)
                im.save(out, optimize=True)
            got.append(pid)
    print("pieces: imported %d: %s" % (len(got), " ".join(got) or "-"))
    print("pieces: still missing %d: %s" % (len(missing), " ".join(missing) or "-"))


def import_names(base: str, ids: list, force: bool) -> None:
    got, missing = [], []
    out_dir = os.path.join(ROOT, "assets", "cards", "names")
    src_dir = os.path.join(ROOT, "art_src", "cards", "names")
    os.makedirs(src_dir, exist_ok=True)
    for cid in ids:
        if os.path.exists(os.path.join(out_dir, cid + ".png")) and not force:
            continue
        data = fetch(base, "dantes_ui/card_names", "name_%s_00001_.png" % cid)
        if data is None:
            missing.append(cid)
            continue
        src = os.path.join(src_dir, cid + ".png")
        open(src, "wb").write(data)
        make_words.make(src, cid, NAME_HEIGHT, out_dir, src_dir)
        got.append(cid)
    print("names: imported %d, still missing %d: %s" % (len(got), len(missing), " ".join(missing) or "-"))


def main() -> None:
    base = open(r"C:\Servers\comfy_url.txt", encoding="utf-8").readline().strip().rstrip("/")
    force = "--force" in sys.argv
    names = [a[len("--names="):] for a in sys.argv if a.startswith("--names=")]
    if "--names" in sys.argv:
        names.append(sys.argv[sys.argv.index("--names") + 1])
    if names:
        import_names(base, [i for n in names for i in n.split(",") if i], force)
    else:
        import_pieces(base, force)


if __name__ == "__main__":
    main()
