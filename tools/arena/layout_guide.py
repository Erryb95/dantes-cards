"""Draws art_src/arena/acheron_layout_guide.png: every board zone at the in-game coordinates (1920x1080 layout
scaled to 2560x1440). Checked by loading it as the board (see docs/ARENA_BRIEF.md)."""
import os
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
W, H = 2560, 1440
K = H / 1080

im = Image.new("RGB", (W, H), (30, 22, 18))
d = ImageDraw.Draw(im)


def rect(x0, y0, x1, y1, col, label, outline=None):
    d.rectangle((x0 * K, y0 * K, x1 * K, y1 * K), fill=col, outline=outline, width=4)
    d.text((x0 * K + 10, y0 * K + 8), label, fill=(255, 255, 255))


def circle(cx, cy, r, col, label):
    d.ellipse(((cx - r) * K, (cy - r) * K, (cx + r) * K, (cy + r) * K), fill=col)
    d.text(((cx - r) * K + 10, cy * K), label, fill=(255, 255, 255))


rect(0, 0, 1920, 420, (70, 50, 40), "FAR BANK (enemy side)")
rect(0, 524, 1920, 1080, (60, 55, 50), "NEAR BANK (player side)")
rect(0, 420, 1920, 524, (20, 40, 60), "RIVER ACHERON y 420-524 (calm water, shader ripples on top)")
rect(350, 254, 1570, 450, (90, 75, 60), "ENEMY MINION ZONE - LOW DETAIL", (200, 170, 120))
rect(350, 494, 1570, 690, (95, 85, 75), "PLAYER MINION ZONE - LOW DETAIL", (200, 170, 120))
circle(960, 150, 130, (120, 60, 40), "ENEMY HERO PLINTH")
circle(960, 808, 130, (120, 60, 40), "PLAYER HERO PLINTH")
circle(1140, 164, 60, (110, 90, 50), "power")
circle(1140, 822, 60, (110, 90, 50), "power")
rect(1620, 407, 1870, 537, (140, 110, 50), "END TURN SOCKET (oval)")
rect(1740, 250, 1860, 375, (80, 70, 90), "ENEMY DECK")
rect(1740, 570, 1860, 695, (80, 70, 90), "PLAYER DECK")
rect(1380, 10, 1900, 100, (40, 60, 90), "ENEMY MANA TRAY")
rect(1380, 980, 1900, 1070, (40, 60, 90), "PLAYER MANA TRAY")
rect(10, 10, 180, 80, (60, 60, 60), "menu button")
rect(90, 210, 240, 370, (100, 80, 60), "PROP: bell on gallows")
rect(50, 600, 290, 765, (100, 80, 60), "PROP: gate inscription tablet")
rect(560, 880, 1360, 1080, (110, 70, 50), "PLAYER HAND (covered by cards)")
rect(700, 0, 1220, 60, (110, 70, 50), "enemy hand")
im.save(os.path.join(ROOT, "art_src", "arena", "acheron_layout_guide.png"))
