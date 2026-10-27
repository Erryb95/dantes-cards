"""Validates data/cards.json + data/sets/*.json against docs/CARD_SCHEMA.md. Prints OK or the list of problems.

  python tools/cards/validate.py            # all sets
  python tools/cards/validate.py FILE...    # only these set files (still checked against the full id space)
"""
import glob
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SETS = {"neutral", "token"}  # plus every hero's class (data/cards.json "heroes"), added in load_all()
RARITY = {"common", "rare", "epic", "legendary", "token"}
KEYWORDS = {"guard", "swift", "ward", "drain", "venom", "rebirth"}
TRIGGERS = {"play", "death", "turn_end", "turn_start", "frenzy"}
OPS = {"damage", "heal", "draw", "buff", "summon", "bounce", "armor", "destroy", "freeze", "silence", "ramp", "give_card", "mana",
       "copy", "transform", "fight"}
CHOOSE = {"choose_any", "choose_enemy", "choose_minion", "choose_enemy_minion", "choose_friendly_minion"}
AUTO = {"own_hero", "enemy_hero", "self", "all_minions", "all_other_minions", "all_enemy_minions", "all_friendly_minions",
        "other_friendly_minions", "all_enemies", "random_enemy", "random_enemy_minion", "random_friendly_minion"}
NO_TARGET = {"draw", "summon", "ramp", "give_card", "mana"}
CIRCLES = {"dark_wood", "ante_inferno", "limbo", "lust", "gluttony", "greed", "wrath", "dis", "heresy", "violence",
           "malebolge", "cocytus"}
PREFIX = {"play": "On Play:", "death": "Last Breath:", "turn_end": "End of Turn:", "turn_start": "Start of Turn:",
          "frenzy": "Frenzy:"}
FIGHT_WITH = {"self", "random_enemy_minion", "random_friendly_minion", "all_friendly_minions"}


def load_all():
    files = [os.path.join(ROOT, "data", "cards.json")] + sorted(glob.glob(os.path.join(ROOT, "data", "sets", "*.json")))
    out = []
    for f in files:
        try:
            d = json.load(open(f, encoding="utf-8"))
        except Exception as e:  # noqa: BLE001
            print("BAD JSON", f, e)
            sys.exit(1)
        for c in d.get("cards", []):
            out.append((f, c))
        for h in d.get("heroes", []):
            if h.get("class"):
                SETS.add(h["class"])
    return out


def check(cards, only=None):
    errs = []
    ids = {}
    for f, c in cards:
        cid = c.get("id", "?")
        if cid in ids:
            errs.append(f"{cid}: duplicate id (also in {os.path.basename(ids[cid])})")
        ids[cid] = f
    by_id = {c.get("id"): c for _, c in cards}
    for f, c in cards:
        if only and os.path.abspath(f) not in only:
            continue
        cid = c.get("id", "?")
        e = lambda m: errs.append(f"{os.path.basename(f)} {cid}: {m}")  # noqa: E731
        if not re.fullmatch(r"[a-z0-9_]+", cid):
            e("id must be snake_case ascii")
        if not c.get("name") or len(c["name"]) > 28:
            e("name missing or longer than 28 chars")
        if c.get("set") not in SETS:
            e(f"set must be one of {sorted(SETS)}")
        if c.get("type") not in ("minion", "spell"):
            e("type must be minion or spell")
        if c.get("rarity") not in RARITY:
            e("bad rarity")
        if (c.get("set") == "token") != (c.get("rarity") == "token"):
            e("tokens need set=token and rarity=token")
        cost = c.get("cost")
        if not isinstance(cost, int) or not 0 <= cost <= 10:
            e("cost must be an int 0..10")
        if c.get("type") == "minion":
            if not isinstance(c.get("attack"), int) or c["attack"] < 0:
                e("minion needs int attack >= 0")
            if not isinstance(c.get("health"), int) or c["health"] < 1:
                e("minion needs int health >= 1")
        else:
            if "attack" in c or "health" in c or c.get("keywords"):
                e("spells have no attack/health/keywords")
        for k in c.get("keywords", []):
            if k not in KEYWORDS:
                e(f"unknown keyword {k}")
        if "wrath" in c:  # Wrath (Filippo Argenti's class): the Attack a minion gains while damaged
            w = c["wrath"]
            if c.get("type") != "minion" or not isinstance(w, int) or w < 1:
                e("wrath must be an int >= 1 on a minion")
            elif f"Wrath: +{w} Attack." not in c.get("text", ""):
                e(f"text must contain 'Wrath: +{w} Attack.'")
        chooses = set()
        effects = c.get("effects", [])
        if c.get("type") == "spell" and not effects:
            e("spell without effects")
        for ef in effects:
            on = ef.get("on", "play")
            op = ef.get("do")
            tgt = ef.get("target", "")
            if on not in TRIGGERS:
                e(f"bad trigger {on}")
            if c.get("type") == "spell" and on != "play":
                e("spell effects must be on play")
            if op not in OPS:
                e(f"bad op {op}")
                continue
            if ef.get("ruse") and on != "play":
                e("ruse only on play effects")
            if op == "copy" and ef.get("from"):
                if ef["from"] not in ("enemy_hand", "enemy_deck"):
                    e("copy from must be enemy_hand or enemy_deck")
                if tgt:
                    e("copy from a zone takes no target")
            elif op in NO_TARGET:
                if tgt:
                    e(f"{op} takes no target")
            else:
                if tgt in CHOOSE:
                    chooses.add(tgt)
                    if on != "play":
                        e("choose_* only on play effects")
                elif tgt not in AUTO:
                    e(f"bad target '{tgt}' for {op}")
            if op == "armor" and tgt != "own_hero":
                e("armor must target own_hero")
            if op in ("damage", "heal", "armor", "ramp", "mana") and not isinstance(ef.get("amount"), int):
                e(f"{op} needs int amount")
            if op == "draw" and not isinstance(ef.get("amount", 1), int):
                e("draw amount must be int")
            if op == "buff":
                if not isinstance(ef.get("attack", 0), int) or not isinstance(ef.get("health", 0), int):
                    e("buff attack/health must be ints")
                for k in ef.get("keywords", []):
                    if k not in KEYWORDS:
                        e(f"buff gives unknown keyword {k}")
            if op == "fight":
                if ef.get("with", "self") not in FIGHT_WITH:
                    e(f"fight 'with' must be one of {sorted(FIGHT_WITH)}")
                if ef.get("with", "self") == "self" and c.get("type") != "minion":
                    e("a spell's fight needs 'with' (it has no minion of its own)")
            if op == "transform" and by_id.get(ef.get("card"), {}).get("type") != "minion":
                e("transform must name a minion card")
            if op in ("summon", "give_card"):
                ref = by_id.get(ef.get("card"))
                if ref is None:
                    e(f"{op} refers to unknown card {ef.get('card')}")
                elif op == "summon" and ref.get("type") != "minion":
                    e("summon must refer to a minion")
            if on in PREFIX and on != "play" and PREFIX[on] not in c.get("text", ""):
                e(f"text must contain '{PREFIX[on]}'")
            if ef.get("ruse") and "Ruse:" not in c.get("text", ""):
                e("ruse effect needs 'Ruse:' in text")
            if on == "play" and not ef.get("ruse") and c.get("type") == "minion" and "On Play:" not in c.get("text", ""):
                e("minion play effect needs 'On Play:' in text")
        if len(chooses) > 1:
            e("at most one choose_* target (several effects may share it)")
        if c.get("set") != "token":
            if not c.get("text") and (effects or c.get("keywords")):
                e("missing text")
            if not c.get("flavor"):
                e("missing flavor")
            if c.get("circle") not in CIRCLES and "image" not in c:
                e(f"circle must be one of {sorted(CIRCLES)}")
            if not c.get("art") and not c.get("image"):
                e("missing art subject")
        for k in c.get("keywords", []):
            if k.capitalize() not in c.get("text", ""):
                e(f"text must mention keyword {k.capitalize()}")
    return errs


if __name__ == "__main__":
    only = {os.path.abspath(p) for p in sys.argv[1:]} or None
    errs = check(load_all(), only)
    if errs:
        print("\n".join(errs))
        print(f"{len(errs)} problems")
        sys.exit(1)
    print("OK")
