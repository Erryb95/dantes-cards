"""Builds the card-art jobs from data/*.json and (optionally) runs them on ComfyUI, then imports the results.

  python tools/cards/art_jobs.py build            # writes art_src/cards/jobs.json (only missing images)
  python tools/cards/art_jobs.py run              # build + generate via tools/comfy/art.py + import
  python tools/cards/art_jobs.py import           # resize art_src/cards/*.png into assets/
  python tools/cards/art_jobs.py dore             # import the Dore batch (art_src/dore_cards) per card "image"
  python tools/cards/art_jobs.py v2               # download output/dantes_cards_v2/<id>_s777_00001_.png for the set cards
                                                  # still missing art (list: art_src/new_card_art.json) and import them

House style (final, Enrico 2026-10-25): hand-tinted Dore engraving (dantes_00133_). The ComfyUI session runs the GPU;
this game session only imports (`dore`).
"""
import json
import os
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "art_src", "cards")
STYLE = ("masterpiece 19th century wood engraving in the style of Gustave Dore, dense fine crosshatching, dramatic "
         "chiaroscuro, hand-tinted with glowing ember orange and deep crimson highlights on black and white, epic composition")
TAIL = "no text, no letters, no watermark, no frame"
SEED = 777

# (name, prompt, w, h, destination relative to assets/, output size)
def jobs() -> list:
    cards = json.load(open(os.path.join(ROOT, "data", "cards.json"), encoding="utf-8"))
    arenas = json.load(open(os.path.join(ROOT, "data", "arenas.json"), encoding="utf-8"))
    out = []
    for c in cards["cards"]:
        if "art" not in c:
            continue
        subj = c["art"] + ", large central subject, strong rim light, clear silhouette"
        out.append(("card_" + c["id"], subj, 832, 1248, "cards/art/%s.jpg" % c["id"], (512, 768)))
    for h in cards["heroes"]:
        if "art" not in h:
            continue
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


def run_jobs(path: str) -> None:
    """Keeps up to comfy.MAX_QUEUED of our jobs queued (the rule is <= 4 per agent) and saves each as it lands."""
    import time
    sys.path.insert(0, os.path.join(ROOT, "tools", "comfy"))
    import comfy
    todo = json.load(open(path, encoding="utf-8"))
    owner = "dantescards-art"
    comfy.acquire(owner, "qwen")
    inflight = {}
    try:
        while todo or inflight:
            while todo and len(inflight) < comfy.MAX_QUEUED:
                j = todo.pop(0)
                wf = comfy.workflow_t2i(j["prompt"], j["seed"], j["w"], j["h"])
                pid = json.loads(comfy._req("/prompt", {"prompt": wf, "client_id": comfy.CLIENT_ID}))["prompt_id"]
                inflight[pid] = (j, time.time())
            time.sleep(3)
            for pid in list(inflight):
                j, t0 = inflight[pid]
                hist = json.loads(comfy._req("/history/" + pid)).get(pid)
                if not hist:
                    q = json.loads(comfy._req("/queue"))
                    ids = {e[1] for e in q["queue_running"] + q["queue_pending"]}
                    if pid not in ids and time.time() - t0 > 30:
                        print("lost from queue, resubmitting", j["name"], flush=True)
                        del inflight[pid]
                        todo.insert(0, j)
                    continue
                st = hist.get("status", {})
                if st.get("status_str") == "error":
                    print("Error", j["name"], json.dumps(st.get("messages", []))[-300:], flush=True)
                    del inflight[pid]
                    continue
                if not st.get("completed"):
                    continue
                for o in hist.get("outputs", {}).values():
                    for im in o.get("images", []):
                        data = comfy._req("/view?" + __import__("urllib.parse").parse.urlencode(
                            {"filename": im["filename"], "subfolder": im["subfolder"], "type": im["type"]}))
                        out = os.path.join(SRC, j["name"] + ".png")
                        open(out, "wb").write(data)
                        print("saved", out, "%.0fs" % (time.time() - t0), flush=True)
                del inflight[pid]
                comfy.touch(owner)
    finally:
        comfy.release(owner)


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


DORE = os.path.join(ROOT, "art_src", "dore_cards")


def import_dore() -> None:
    """Imports the hand-tinted Dore batch (made by the ComfyUI session) using each card's "image" field."""
    from PIL import Image
    cards = json.load(open(os.path.join(ROOT, "data", "cards.json"), encoding="utf-8"))
    todo = [(c["image"], "cards/art/%s.jpg" % c["id"], (512, 704), 0.5) for c in cards["cards"] if c.get("image")]
    todo += [(h["image"], "cards/heroes/%s.jpg" % h["id"], (512, 512), 0.3) for h in cards["heroes"] if h.get("image")]
    n = 0
    for img, dst, (tw, th), focus in todo:
        src = os.path.join(DORE, img + "_00001_.png")
        if not os.path.exists(src):
            print("missing", src)
            continue
        im = Image.open(src).convert("RGB")
        sw, sh = im.size
        scale = max(tw / sw, th / sh)
        im = im.resize((round(sw * scale), round(sh * scale)), Image.LANCZOS)
        l = (im.width - tw) // 2
        t = int(min(max(im.height * focus - th / 2, 0), im.height - th))
        out = os.path.join(ROOT, "assets", dst)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        im.crop((l, t, l + tw, t + th)).save(out, quality=88)
        n += 1
    print("imported", n)


def _fit(src: str, dst: str, size=(512, 704), focus=0.45) -> None:
    from PIL import Image
    tw, th = size
    with Image.open(src) as f:  # closed even when a truncated file raises, so it can be deleted
        im = f.convert("RGB")
    scale = max(tw / im.width, th / im.height)
    im = im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)
    l = (im.width - tw) // 2
    t = int(min(max(im.height * focus - th / 2, 0), im.height - th))
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    im.crop((l, t, l + tw, t + th)).save(dst, quality=88)


def import_v2() -> None:
    """Fetches the second card batch from the ComfyUI PC (read-only /view requests) and imports what exists."""
    import urllib.parse
    import urllib.request
    base = open(r"C:\Servers\comfy_url.txt", encoding="utf-8").readline().strip().rstrip("/")
    todo = json.load(open(os.path.join(ROOT, "art_src", "new_card_art.json"), encoding="utf-8"))
    src_dir = os.path.join(ROOT, "art_src", "dore_cards_v2")
    os.makedirs(src_dir, exist_ok=True)
    got = missing = 0
    for c in todo:
        dst = os.path.join(ROOT, "assets", "cards", "art", c["id"] + ".jpg")
        if os.path.exists(dst):
            continue
        name = c["id"] + "_s777_00001_.png"
        src = os.path.join(src_dir, name)
        if not os.path.exists(src):
            q = urllib.parse.urlencode({"subfolder": "dantes_cards_v2", "type": "output", "filename": name})
            try:
                data = urllib.request.urlopen(base + "/view?" + q, timeout=60).read()
            except Exception:  # noqa: BLE001 - not generated yet
                missing += 1
                continue
            open(src, "wb").write(data)
        try:
            _fit(src, dst)
        except OSError:  # still being written on the PC when we fetched it: drop it and retry next run
            os.remove(src)
            if os.path.exists(dst):
                os.remove(dst)
            missing += 1
            continue
        got += 1
    print("imported", got, "still missing", missing)


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "build"
    if mode in ("build", "run"):
        p = build()
        if mode == "run" and json.load(open(p, encoding="utf-8")):
            run_jobs(p)
    if mode in ("run", "import"):
        import_art()
    if mode == "dore":
        import_dore()
    if mode == "v2":
        import_v2()
