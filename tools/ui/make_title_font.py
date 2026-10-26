"""Builds assets/fonts/CinzelTitle.ttf: a static instance of the Cinzel variable font at a heavier weight, with
overlapping contours merged (fontTools instancer + skia-pathops).

  python tools/ui/make_title_font.py [weight]     # default 600

Why: Cinzel's glyphs are drawn from overlapping contours, which Godot's MSDF renderer turns into spikes and specks,
and the fake bold (FontVariation.variation_embolden) smears the serifs. A real weight with merged outlines renders
cleanly in MSDF at any scale. Cinzel is SIL OFL 1.1 with no Reserved Font Name; the instance keeps the licence
(assets/fonts/OFL_Cinzel.txt) and is renamed "Cinzel Title" so it is not mistaken for the upstream font.
"""
import os
import sys

from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "assets", "fonts", "Cinzel.ttf")
DST = os.path.join(ROOT, "assets", "fonts", "CinzelTitle.ttf")


def main() -> None:
    weight = float(sys.argv[1]) if len(sys.argv) > 1 else 600.0
    font = TTFont(SRC)
    inst = instancer.instantiateVariableFont(font, {"wght": weight}, overlap=instancer.OverlapMode.REMOVE)
    name = inst["name"]
    for rec in name.names:
        if rec.nameID in (1, 4, 16):
            rec.string = "Cinzel Title"
        elif rec.nameID == 6:
            rec.string = "CinzelTitle-Regular"
    inst.save(DST)
    print("wrote", DST, "weight", weight)


if __name__ == "__main__":
    main()
