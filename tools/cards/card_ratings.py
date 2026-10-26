"""Turns tests/card_stats.gd runs into data/card_ratings.json: how much each card lifts its side's win rate over
its class average, used by the deck builder's Auto-fill to pick the strongest owned cards.

  Godot --headless --path . -s res://tests/card_stats.gd -- --games=250 --first=N --raw > <dir>/N.txt   (shards)
  python tools/cards/card_ratings.py <dir>

Rating = mostly the win rate of decks holding the card, minus its class average (pilgrim / ferry / neutral), plus
a quarter of the same edge measured on games where it was played. The "played" rate alone misleads: cheap freezes
and armor get cast when the AI is already losing. Each edge is shrunk toward 0 for cards seen in few games. Ramp
cards read low because the AI rarely plays them; their rating is floored at 0.
"""
import glob
import json
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SHRINK_PLAYED = 30  # games of evidence that count as half the measured edge
SHRINK_DECKED = 200


def main() -> None:
    src = sys.argv[1]
    played, won, decked, dwon = {}, {}, {}, {}
    for f in glob.glob(os.path.join(src, "*.txt")):
        for line in open(f, encoding="utf-8", errors="replace"):
            if line.startswith("RAW "):
                _, cid, p, w, dk, dw = line.split()[:6]
                played[cid] = played.get(cid, 0) + int(p)
                won[cid] = won.get(cid, 0) + int(w)
                decked[cid] = decked.get(cid, 0) + int(dk)
                dwon[cid] = dwon.get(cid, 0) + int(dw)
    cards = {}
    for f in [os.path.join(ROOT, "data", "cards.json")] + glob.glob(os.path.join(ROOT, "data", "sets", "*.json")):
        d = json.load(open(f, encoding="utf-8"))
        for c in d["cards"] if isinstance(d, dict) else d:
            cards[c["id"]] = c
    by_set = {}
    for cid, p in played.items():
        s = cards.get(cid, {}).get("set", "neutral")
        a = by_set.setdefault(s, [0, 0, 0, 0])
        a[0] += p
        a[1] += won[cid]
        a[2] += decked[cid]
        a[3] += dwon[cid]
    out = {}
    for cid, p in sorted(played.items()):
        c = cards.get(cid)
        if c is None or c.get("set") == "token" or p == 0:
            continue
        b = by_set[c["set"]]
        played_edge = (won[cid] / p - b[1] / b[0]) * p / (p + SHRINK_PLAYED)
        dk = decked[cid]
        decked_edge = (dwon[cid] / dk - b[3] / b[2]) * dk / (dk + SHRINK_DECKED) if dk else 0.0
        edge = decked_edge + 0.25 * played_edge
        if any(e.get("do") in ("ramp", "mana") for e in c.get("effects", [])):
            edge = max(edge, 0.0)
        out[cid] = round(edge, 4)
    path = os.path.join(ROOT, "data", "card_ratings.json")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write('{\n  "_doc": "Win-rate edge of each card over its class average (tools/cards/card_ratings.py). Used by Auto-fill.",\n')
        f.write('  "ratings": {\n')
        f.write(",\n".join('    "%s": %s' % (k, v) for k, v in out.items()))
        f.write("\n  }\n}\n")
    print("%d cards rated from %d shards -> %s" % (len(out), len(glob.glob(os.path.join(src, "*.txt"))), path))
    best = sorted(out.items(), key=lambda kv: -kv[1])
    print("best:", best[:6])
    print("worst:", best[-6:])


if __name__ == "__main__":
    main()
