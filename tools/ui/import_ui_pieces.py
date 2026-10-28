"""Fetches the optional painted UI pieces from the ComfyUI PC (read-only /view requests) and installs them.

  python tools/ui/import_ui_pieces.py                      # the lists below: import what is new, list what is missing
  python tools/ui/import_ui_pieces.py --force              # re-import

Pieces: art_src/tutorial_art.json and art_src/deck_ui_art.json (one entry per piece, with where it goes). The ComfyUI
session paints them into output/dantes_ui as <id>_00001_.png, the words as word_<id>_00001_.png.
- "kind": "portrait" (or no kind, opaque): assets/ui/<id>.png at the listed size (UiSkin picks it up by name);
- "kind": "word": gilded lettering on flat black, keyed by tools/ui/make_words.py into assets/ui/words/<id>.png;
- "alpha": true: copied as is (already cut out) to assets/ui/<id>.png. Each one is wired where its "replaces" says.
A piece marked "unused" (with the reason) was compared in the game and left out; it is not installed.
Originals go to art_src/ui/pieces/ and art_src/ui/words/.
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


def main() -> None:
    base = open(r"C:\Servers\comfy_url.txt", encoding="utf-8").readline().strip().rstrip("/")
    import_pieces(base, "--force" in sys.argv)


if __name__ == "__main__":
    main()
