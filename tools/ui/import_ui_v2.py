"""Fetches the painted UI v2 batch from the ComfyUI PC (read-only /view requests) into art_src/ui_v2 and assets/ui.
  python tools/ui/import_ui_v2.py
The images were made by the ComfyUI session (Qwen-Image 2512, cut out with BiRefNet) at the sizes the game uses."""
import io
import os
import urllib.parse
import urllib.request

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
NAMES = ["minion_frame", "minion_frame_legendary", "hero_frame_oval", "guard_frame", "frozen_overlay", "icon_venom",
         "icon_drain", "icon_deathrattle", "icon_trigger", "icon_rebirth", "arrow_head", "arrow_segment",
         "target_reticle", "panel_frame", "tooltip_frame", "deck_row", "slider_track", "slider_grabber", "turn_banner",
         # progression art, painted ahead of the features that will use it (crafting currency, quests, ranks)
         "icon_ash", "icon_quest", "icon_wrath"] + ["rank_%d" % i for i in range(1, 10)]
## Alternative card backs: saved as jpg next to the default back (assets/cards/card_back.jpg).
BACKS = ["card_back_dis", "card_back_cocytus", "card_back_paradise"]


def main() -> None:
    base = open(r"C:\Servers\comfy_url.txt", encoding="utf-8").readline().strip().rstrip("/")
    src_dir = os.path.join(ROOT, "art_src", "ui_v2")
    os.makedirs(src_dir, exist_ok=True)
    got, missing = [], []
    for n in NAMES:
        q = urllib.parse.urlencode({"subfolder": "dantes_ui_v2", "type": "output", "filename": n + ".png"})
        try:
            data = urllib.request.urlopen(base + "/view?" + q, timeout=60).read()
        except Exception:  # noqa: BLE001 - not there (yet)
            missing.append(n)
            continue
        open(os.path.join(src_dir, n + ".png"), "wb").write(data)
        open(os.path.join(ROOT, "assets", "ui", n + ".png"), "wb").write(data)
        got.append(n)
    for n in BACKS:
        q = urllib.parse.urlencode({"subfolder": "dantes_ui_v2", "type": "output", "filename": n + ".png"})
        try:
            data = urllib.request.urlopen(base + "/view?" + q, timeout=60).read()
        except Exception:  # noqa: BLE001 - not there (yet)
            missing.append(n)
            continue
        open(os.path.join(src_dir, n + ".png"), "wb").write(data)
        Image.open(io.BytesIO(data)).convert("RGB").save(os.path.join(ROOT, "assets", "cards", n + ".jpg"), quality=90)
        got.append(n)
    print("imported", len(got), "missing", missing)


if __name__ == "__main__":
    main()
