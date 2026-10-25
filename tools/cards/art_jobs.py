"""Builds the card-art jobs from data/*.json and (optionally) runs them on ComfyUI, then imports the results.

  python tools/cards/art_jobs.py build            # writes art_src/cards/jobs.json (only missing images)
  python tools/cards/art_jobs.py run              # build + generate via tools/comfy/art.py + import
  python tools/cards/art_jobs.py import           # resize art_src/cards/*.png into assets/

House style (chosen by Enrico, 2026-10-25): s2 "dark baroque oil", Qwen-Image 2512 + Lightning 4-step, seed 777.
"""
import json
import os
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "art_src", "cards")
STYLE = ("dark baroque oil painting, extreme chiaroscuro, candle and hellfire light, rich glazes, visible brushwork, "
         "museum quality old master painting, crimson and gold against deep black")
TAIL = "no text, no letters, no watermark, no frame"
SEED = 777

# (name, prompt, w, h, destination relative to assets/, output size)
def jobs() -> list:
    cards = json.load(open(os.path.join(ROOT, "data", "cards.json"), encoding="utf-8"))
    arenas = json.load(open(os.path.join(ROOT, "data", "arenas.json"), encoding="utf-8"))
    out = []
    for c in cards["cards"]:
        subj = c["art"] + ", large central subject, strong rim light, clear silhouette"
        out.append(("card_" + c["id"], subj, 832, 1248, "cards/art/%s.jpg" % c["id"], (512, 768)))
    for h in cards["heroes"]:
        subj = h["art"] + ", head and shoulders, strong rim light, clear silhouette, dark background"
        out.append(("hero_" + h["id"], subj, 1024, 1024, "cards/heroes/%s.jpg" % h["id"], (512, 512)))
    for a in arenas["arenas"]:
        out.append(("arena_" + a["id"], a["art"] + ", atmospheric, low contrast in the centre", 1664, 928,
                    "arenas/" + a["backdrop"], (1920, 1080)))
    out.append(("card_back", "ornate symmetrical card back design, a golden circular emblem of nine concentric rings "
                "descending into a dark funnel, gold filigree on deep crimson velvet, centred, symmetrical",
                832, 1248, "cards/card_back.jpg", (512, 768)))
    return out


def build() -> str:
    os.makedirs(SRC, exist_ok=True)
    todo = []
    for name, subj, w, h, _dst, _size in jobs():
        if os.path.exists(os.path.join(SRC, name + ".png")):
            continue
        todo.append({"name": name, "prompt": "%s. %s. %s" % (subj, STYLE, TAIL), "seed": SEED, "w": w, "h": h})
    path = os.path.join(SRC, "jobs.json")
    json.dump(todo, open(path, "w", encoding="utf-8"), indent=1)
    print(len(todo), "jobs ->", path)
    return path


def import_art() -> None:
    from PIL import Image
    n = 0
    for name, _subj, _w, _h, dst, size in jobs():
        src = os.path.join(SRC, name + ".png")
        if not os.path.exists(src):
            continue
        out = os.path.join(ROOT, "assets", dst)
        if os.path.exists(out) and os.path.getmtime(out) >= os.path.getmtime(src):
            continue
        os.makedirs(os.path.dirname(out), exist_ok=True)
        im = Image.open(src).convert("RGB")
        # cover-crop to the target aspect, then resize
        tw, th = size
        sw, sh = im.size
        scale = max(tw / sw, th / sh)
        im = im.resize((round(sw * scale), round(sh * scale)), Image.LANCZOS)
        l, t = (im.width - tw) // 2, (im.height - th) // 2
        im.crop((l, t, l + tw, t + th)).save(out, quality=88)
        n += 1
    print("imported", n)


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "build"
    if mode in ("build", "run"):
        p = build()
        if mode == "run" and json.load(open(p, encoding="utf-8")):
            subprocess.check_call([sys.executable, os.path.join(ROOT, "tools", "comfy", "art.py"), "t2i", p])
    if mode in ("run", "import"):
        import_art()
