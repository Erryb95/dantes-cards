#!/usr/bin/env python3
"""Progression / economy simulator for the card game (plain Python 3.12, no dependencies).

Simulates many virtual players (casual / regular / grinder) earning Obols, opening packs and (in some variants)
crafting cards, and compares alternative economies on the SAME players (common random numbers).

* Constants (prices, odds, pity, refunds, ...) are parsed from scripts/core/collection.gd, so they stay in sync.
* The card pool is read from data/cards.json + data/sets/*.json (rarity != token), the starters from data/decks.json.

Run:   python tools/sim/progression.py                  (full run, writes docs/ECONOMY_SIM.md)
       python tools/sim/progression.py --quick          (20 players, 3 s, for a smoke test)
       python tools/sim/progression.py --players 600 --seed 7
See docs/ECONOMY_SIM.md ("How to rerun") and the --help text for all options.
"""
from __future__ import annotations

import argparse
import concurrent.futures as cf
import glob
import json
import math
import os
import random
import re
import statistics
import sys
from dataclasses import dataclass, field, replace
from functools import lru_cache

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RARITIES = ["common", "rare", "epic", "legendary"]
CLASSES = ["pilgrim", "ferry"]
GAME_MINUTES = 7.0
CHECKPOINTS = [1, 3, 7, 14, 21, 28, 30, 42, 56, 60, 84, 90, 120, 180, 270, 365]
WEEKLY_MAX = 365

# --------------------------------------------------------------------------- data

def parse_collection_gd(path: str) -> dict:
    """Reads every `const NAME := <literal>` of collection.gd (numbers and JSON-compatible dict literals)."""
    text = open(path, encoding="utf-8").read()
    out = {}
    for m in re.finditer(r"^const\s+(\w+)\s*:=\s*(.+?)\s*(?:##.*)?$", text, re.M):
        name, lit = m.group(1), m.group(2).strip()
        lit = re.sub(r"\s+#.*$", "", lit)
        try:
            out[name] = json.loads(lit)
        except json.JSONDecodeError:
            pass  # PATH etc. (strings are valid JSON, anything exotic is skipped)
    need = ["PACK_PRICE", "PACK_SIZE", "WIN_REWARD", "LOSS_REWARD", "START_PACKS", "DECK_SIZE",
            "ODDS", "PITY_LEGENDARY", "MAX_COPIES", "REFUND"]
    missing = [n for n in need if n not in out]
    if missing:
        raise SystemExit("cannot parse %s from collection.gd" % missing)
    return out


def load_cards() -> list[dict]:
    cards = list(json.load(open(os.path.join(ROOT, "data", "cards.json"), encoding="utf-8"))["cards"])
    for f in sorted(glob.glob(os.path.join(ROOT, "data", "sets", "*.json"))):
        cards += json.load(open(f, encoding="utf-8"))["cards"]
    return cards


def load_decks() -> list[dict]:
    return json.load(open(os.path.join(ROOT, "data", "decks.json"), encoding="utf-8"))["decks"]


# --------------------------------------------------------------------------- crude card power score
# Only used to choose WHICH cards count as "the good ones" for the competitive-deck proxy. It is a
# transparent heuristic (stats over the mana curve + keyword/effect bonuses + a small rarity prior), not a
# balance model. The resulting lists are printed in the report so they can be sanity-checked by eye.
KEYWORD_VALUE = {"guard": 0.5, "swift": 1.0, "ward": 1.5, "drain": 1.5, "venom": 2.0, "rebirth": 1.5}
RARITY_PRIOR = {"common": 0.0, "rare": 0.5, "epic": 1.0, "legendary": 1.5}


def effect_value(e: dict) -> float:
    do, amt = e.get("do"), float(e.get("amount", 1) or 1)
    tgt = e.get("target") or ""
    aoe = 1.6 if tgt.startswith("all_") else 1.0
    v = {"damage": 0.9 * amt, "draw": 1.6 * amt, "freeze": 1.0, "heal": 0.3 * amt, "silence": 1.0,
         "summon": 1.4 * float(e.get("count", 1)), "ramp": 1.2 * amt, "give_card": 1.2 * float(e.get("count", 1)),
         "bounce": 1.0, "armor": 0.3 * amt, "destroy": 3.0, "mana": 1.0 * amt,
         "buff": 0.7 * (float(e.get("attack", 0)) + float(e.get("health", 0)))}.get(do, 1.0)
    return v * aoe


def power_score(c: dict) -> float:
    cost = float(c.get("cost", 0))
    eff = sum(effect_value(e) for e in c.get("effects", []))
    kw = sum(KEYWORD_VALUE.get(k, 1.0) for k in c.get("keywords", []))
    if c.get("type") == "minion":
        base = float(c.get("attack", 0)) + float(c.get("health", 0)) - (2.0 * cost + 1.0)
        return base + kw + eff + RARITY_PRIOR[c["rarity"]]
    return eff - 1.5 * cost + 1.0 + RARITY_PRIOR[c["rarity"]]


# --------------------------------------------------------------------------- economy variants

@dataclass(frozen=True)
class Econ:
    key: str
    label: str
    pack_price: int
    win: int
    loss: int
    odds: tuple  # (legendary, epic, rare)
    pity: int
    pack_size: int
    start_packs: int
    max_copies: tuple      # per rarity index
    dup_value: tuple       # value of a copy beyond the limit, per rarity index
    dup_to: str = "obols"  # 'obols' or 'ash'
    craft: tuple | None = None   # Ash cost per rarity index; None = no crafting
    dis: tuple | None = None     # voluntary disenchant value per rarity index
    quests: tuple = ()           # ((games_needed, reward), ...) per day
    first_win_bonus: int = 0
    protect: tuple = ()          # rarity indices with duplicate protection
    focus: bool = False          # crafting policy: disenchant the other class's cards until the first good deck
    notes: str = ""


def base_econ(g: dict) -> Econ:
    mc = tuple(int(g["MAX_COPIES"][r]) for r in RARITIES)
    rf = tuple(int(g["REFUND"][r]) for r in RARITIES)
    o = g["ODDS"]
    return Econ("A", "A  Current", g["PACK_PRICE"], g["WIN_REWARD"], g["LOSS_REWARD"],
                (o["legendary"], o["epic"], o["rare"]), g["PITY_LEGENDARY"], g["PACK_SIZE"], g["START_PACKS"],
                mc, rf)


HS_CRAFT = (40, 100, 400, 1600)
HS_DIS = (5, 20, 100, 400)
QUESTS = ((1, 50), (3, 75), (5, 100))   # play 1 / 3 / 5 games in a day -> 50 / 75 / 100 Obols
FIRST_WIN = 50
HALF_QUESTS = ((1, 25), (3, 40), (5, 50))
HALF_FIRST_WIN = 25


def build_variants(g: dict, tuned_craft=(30, 80, 250, 700), tuned_dis=(5, 20, 80, 300)) -> list[Econ]:
    a = base_econ(g)
    ash = dict(dup_to="ash", dis=HS_DIS, dup_value=HS_DIS)
    v = [a,
         replace(a, key="A60", label="A2  Cheaper pack (60 Obols)", pack_price=60),
         replace(a, key="A4", label="A4  Refunds halved (2/10/50/200 Obols)", dup_value=tuple(x // 2 for x in a.dup_value)),
         replace(a, key="A5", label="A5  Refunds quartered (1/5/25/100 Obols)", dup_value=tuple(x // 4 for x in a.dup_value)),
         replace(a, key="Adp", label="A3  Duplicate protection (epic + legendary)", protect=(2, 3)),
         replace(a, key="B-HS", label="B1  Crafting, Hearthstone ratios (craft 40/100/400/1600)",
                 craft=HS_CRAFT, **ash),
         replace(a, key="B-T", label="B2  Crafting, tuned for 202 cards (craft %s, disenchant %s)" % (
             "/".join(map(str, tuned_craft)), "/".join(map(str, tuned_dis))),
                 craft=tuned_craft, dis=tuned_dis, dup_value=tuned_dis, dup_to="ash"),
         replace(a, key="C", label="C  Daily quests + first win of the day (on A)", quests=QUESTS,
                 first_win_bonus=FIRST_WIN),
         replace(a, key="D", label="D  B2 + C (crafting and daily quests)", craft=tuned_craft, dis=tuned_dis,
                 dup_value=tuned_dis, dup_to="ash", quests=QUESTS, first_win_bonus=FIRST_WIN),
         replace(a, key="E", label="E  D + duplicate protection", craft=tuned_craft, dis=tuned_dis,
                 dup_value=tuned_dis, dup_to="ash", quests=QUESTS, first_win_bonus=FIRST_WIN, protect=(2, 3)),
         replace(a, key="F", label="F  Candidate: win 50 / loss 10, half-size quests, B2 crafting, duplicate protection",
                 win=50, loss=10, craft=tuned_craft, dis=tuned_dis, dup_value=tuned_dis, dup_to="ash",
                 quests=HALF_QUESTS, first_win_bonus=HALF_FIRST_WIN, protect=(2, 3)),
         ]
    # focus policy rows (crafting variants only): same economy, a player who disenchants the other class
    foc = [replace(x, key=x.key + "+F", label=x.label.split("  ")[0] + "f  " + x.label.split("  ")[0] + " played with the focus policy",
                   focus=True) for x in v if x.craft]
    return v + foc


@dataclass(frozen=True)
class Profile:
    key: str
    games: int
    win_rate: float
    active_prob: float = 1.0   # chance that the player plays at all on a given day (1.0 = every day)


PROFILES = [Profile("casual", 5, 0.45), Profile("regular", 12, 0.50), Profile("grinder", 30, 0.55)]


# --------------------------------------------------------------------------- the world (static card data)

class World:
    def __init__(self):
        g = parse_collection_gd(os.path.join(ROOT, "scripts", "core", "collection.gd"))
        self.consts = g
        all_cards = [c for c in load_cards() if c.get("rarity") in RARITIES]
        # stable order: by file order
        self.cards = all_cards
        self.n = len(all_cards)
        self.idx = {c["id"]: i for i, c in enumerate(all_cards)}
        self.rar = [RARITIES.index(c["rarity"]) for c in all_cards]
        self.set = [c.get("set", "") for c in all_cards]
        self.score = [power_score(c) for c in all_cards]
        self.by_rar = [[i for i in range(self.n) if self.rar[i] == r] for r in range(4)]
        self.maxc = [int(g["MAX_COPIES"][RARITIES[r]]) for r in self.rar]
        self.total_playset = sum(self.maxc)
        # starter decks are always owned
        self.start = [0] * self.n
        for d in load_decks():
            for cid, n in d["cards"].items():
                if cid in self.idx:
                    i = self.idx[cid]
                    self.start[i] = max(self.start[i], int(n))
        # competitive-deck proxy lists per class (class cards + neutral)
        self.lists = []
        self.member = [[] for _ in range(self.n)]   # card -> [(class k, kind)]
        for k, cls in enumerate(CLASSES):
            pool = [i for i in range(self.n) if self.set[i] in (cls, "neutral")]
            rank = lambda i: -self.score[i]
            leg = sorted([i for i in pool if self.rar[i] == 3], key=rank)[:5]
            epic = sorted([i for i in pool if self.rar[i] == 2], key=rank)[:8]
            cr = sorted([i for i in pool if self.rar[i] <= 1], key=rank)[:30]
            cr_craft = sorted(cr, key=lambda i: (-self.rar[i], -self.score[i]))
            self.lists.append({"leg": leg, "epic": epic, "cr": cr, "cr_craft": cr_craft, "pool": pool})
            for i in leg:
                self.member[i].append((k, "leg"))
            for i in epic:
                self.member[i].append((k, "epic"))
            for i in cr:
                self.member[i].append((k, "cr"))
        # wishlist for stage 2 (full collection): per class: own class + neutral first, rarity desc, power desc
        self.wish = []
        for k, cls in enumerate(CLASSES):
            self.wish.append(sorted(range(self.n), key=lambda i: (
                0 if self.set[i] in (cls, "neutral") else 1, -self.rar[i], -self.score[i])))


@lru_cache(maxsize=1)
def world() -> World:
    return World()


# competitive deck proxy thresholds (30 cards = 1 + 2*2 + 25)
NEED_LEG, NEED_EPIC_SLOTS, NEED_CR_SLOTS = 1, 4, 25


# --------------------------------------------------------------------------- one player

class Player:
    def __init__(self, e: Econ, prof: Profile, seed: int, cls: int):
        self.w = world()
        self.e = e
        self.prof = prof
        self.rng = random.Random(seed * 7919 + 13)         # pack rolls
        self.play = random.Random(seed * 104729 + 7)       # games, wins
        self.cls = cls
        w = self.w
        self.owned = [0] * w.n
        self.unique = 0
        self.playset = 0
        self.legs = 0
        self.epics = 0
        self.leg_have = [0, 0]
        self.epic_slots = [0, 0]
        self.cr_slots = [0, 0]
        for i, n in enumerate(w.start):
            if n:
                self.add(i, n)
        self.obols = 0
        self.ash = 0
        self.packs = e.start_packs
        self.pity = 0
        self.opened = 0
        self.crafted = [0, 0, 0, 0]
        self.dup_total = 0           # value of copies beyond the limit (Obols or Ash)
        self.dup_count = 0
        self.rolled_leg = 0
        self.rolled_epic = 0
        self.first_leg = None
        self.first_epic = None
        self.income = 0
        self.games = 0
        self.hours = 0.0
        self.wptr = 0
        self.focus_active = e.focus
        self.day = 0
        self.hook = None             # called after every pack / craft (exact milestone timing inside a day)
        self.first_new_leg = None    # packs opened when the first legendary / epic NOT in the collection came out
        self.first_new_epic = None
        self.start_unique = self.unique
        self.start_legs = self.legs
        if self.focus_active:
            self.focus_sweep()

    # ----- collection bookkeeping
    def add(self, i: int, d: int) -> None:
        w = self.w
        old = self.owned[i]
        new = old + d
        self.owned[i] = new
        mc = w.maxc[i]
        self.playset += min(new, mc) - min(old, mc)
        if (old > 0) != (new > 0):
            s = 1 if new > 0 else -1
            self.unique += s
            if w.rar[i] == 3:
                self.legs += s
            elif w.rar[i] == 2:
                self.epics += s
        for k, kind in w.member[i]:
            if kind == "leg":
                self.leg_have[k] += (new > 0) - (old > 0)
            elif kind == "epic":
                self.epic_slots[k] += min(new, 2) - min(old, 2)
            else:
                self.cr_slots[k] += min(new, 2) - min(old, 2)

    def comp(self, k: int) -> bool:
        return (self.leg_have[k] >= NEED_LEG and self.epic_slots[k] >= NEED_EPIC_SLOTS
                and self.cr_slots[k] >= NEED_CR_SLOTS)

    def competitive(self) -> bool:
        return self.comp(0) or self.comp(1)

    # ----- packs
    def roll_rarity(self) -> int:
        o_leg, o_epic, o_rare = self.e.odds
        x = self.rng.random()
        if x < o_leg:
            return 3
        if x < o_leg + o_epic:
            return 2
        if x < o_leg + o_epic + o_rare:
            return 1
        return 0

    def open_pack(self) -> None:
        e, w, rng = self.e, self.w, self.rng
        self.packs -= 1
        self.opened += 1
        rs = [self.roll_rarity() for _ in range(e.pack_size)]
        if max(rs) == 0:
            rs[-1] = 1
        self.pity += 1
        if 3 in rs:
            self.pity = 0
        elif self.pity >= e.pity:
            rs[0] = 3
            self.pity = 0
        for r in rs:
            ids = w.by_rar[r]
            if r in e.protect:
                cand = [i for i in ids if self.owned[i] < w.maxc[i]]
                if cand:
                    ids = cand
            i = ids[rng.randrange(len(ids))]
            if r == 3:
                self.rolled_leg += 1
                if self.first_leg is None:
                    self.first_leg = self.day
            elif r == 2:
                self.rolled_epic += 1
                if self.first_epic is None:
                    self.first_epic = self.day
            if self.owned[i] >= w.maxc[i]:
                v = e.dup_value[r]
                self.dup_total += v
                self.dup_count += 1
                if e.dup_to == "ash":
                    self.ash += v
                else:
                    self.obols += v
            else:
                if self.owned[i] == 0 and r >= 2:
                    if r == 3 and self.first_new_leg is None:
                        self.first_new_leg = (self.day, self.opened)
                    if self.first_new_epic is None:
                        self.first_new_epic = (self.day, self.opened)
                self.add(i, 1)
                if self.focus_active:
                    self.focus_one(i)
        if self.hook:
            self.hook()

    # ----- crafting (Ash) policy
    def focus_one(self, i: int) -> None:
        s = self.w.set[i]
        if s in CLASSES and s != CLASSES[self.cls] and self.owned[i] > 0:
            n = self.owned[i]
            self.ash += n * self.e.dis[self.w.rar[i]]
            self.add(i, -n)

    def focus_sweep(self) -> None:
        for i in range(self.w.n):
            if self.owned[i]:
                self.focus_one(i)

    def next_target(self):
        w, k, o = self.w, self.cls, self.owned
        if not self.comp(k):
            L = w.lists[k]
            if self.leg_have[k] < NEED_LEG:
                for i in L["leg"]:
                    if o[i] == 0:
                        return i
            if self.epic_slots[k] < NEED_EPIC_SLOTS:
                for i in L["epic"]:
                    if o[i] < 2:
                        return i
            for i in L["cr_craft"]:
                if o[i] < 2:
                    return i
        wish = w.wish[k]
        while self.wptr < len(wish):
            i = wish[self.wptr]
            if o[i] < w.maxc[i]:
                return i
            self.wptr += 1
        return None

    def craft_step(self) -> None:
        e = self.e
        if not e.craft:
            return
        while True:
            if self.focus_active and self.comp(self.cls):
                self.focus_active = False
            t = self.next_target()
            if t is None:
                return
            cost = e.craft[self.w.rar[t]]
            if self.ash < cost:
                return
            self.ash -= cost
            self.crafted[self.w.rar[t]] += 1
            self.add(t, 1)
            if self.hook:
                self.hook()

    # ----- one day of play
    def day_income(self) -> int:
        e, p, pl = self.e, self.prof, self.play
        if pl.random() >= p.active_prob:
            return 0
        g = max(1, round(p.games * (1.0 + pl.uniform(-0.3, 0.3))))
        wins = pl.binomialvariate(g, p.win_rate)
        inc = wins * e.win + (g - wins) * e.loss
        for need, reward in e.quests:
            if g >= need:
                inc += reward
        if wins > 0:
            inc += e.first_win_bonus
        self.games += g
        self.hours += g * GAME_MINUTES / 60.0
        self.income += inc
        return inc

    def spend(self) -> None:
        e, full = self.e, self.w.total_playset
        while True:
            while self.packs > 0 and self.playset < full:
                self.open_pack()
            if self.playset >= full:
                return   # nothing left to win (a pack at that point refunds about its own price)
            if self.obols >= e.pack_price:
                self.obols -= e.pack_price
                self.packs += 1
                continue
            self.craft_step()
            break


def snapshot(p: Player) -> tuple:
    return (p.obols, p.opened, p.unique, p.playset, p.legs, p.epics, int(p.competitive()), p.dup_total, p.ash,
            p.rolled_leg)


def simulate(e: Econ, prof: Profile, seed: int, horizon: int) -> dict:
    w = world()
    p = Player(e, prof, seed, cls=seed % 2)
    ms = {"d50": None, "d90": None, "d100": None, "p100": None, "comp": None, "leg9": None, "leg18": None,
          "h_comp": None, "g_comp": None, "packs_comp": None, "leg9p": None, "leg18p": None}
    snaps = {}
    n_u = w.n
    cps = set(CHECKPOINTS) | set(range(7, WEEKLY_MAX + 1, 7))

    def check(day):
        if ms["d50"] is None and p.unique >= 0.5 * n_u:
            ms["d50"] = day
        if ms["d90"] is None and p.unique >= 0.9 * n_u:
            ms["d90"] = day
        if ms["d100"] is None and p.unique >= n_u:
            ms["d100"] = day
        if ms["p100"] is None and p.playset >= w.total_playset:
            ms["p100"] = day
        pass
        if ms["leg9"] is None and p.legs >= len(w.by_rar[3]) // 2:
            ms["leg9"] = day
        if ms["leg18"] is None and p.legs >= len(w.by_rar[3]):
            ms["leg18"] = day

    def hook():
        if ms["leg9p"] is None and p.legs >= len(w.by_rar[3]) // 2:
            ms["leg9p"] = p.opened
        if ms["leg18p"] is None and p.legs >= len(w.by_rar[3]):
            ms["leg18p"] = p.opened
        if ms["comp"] is None and p.competitive():
            ms["comp"] = p.day
            ms["h_comp"] = p.hours
            ms["g_comp"] = p.games
            ms["packs_comp"] = p.opened

    p.hook = hook
    p.day = 0
    p.spend()
    check(0)
    snaps[0] = snapshot(p)
    last = snaps[0]
    day = 0
    while day < horizon:
        day += 1
        p.day = day
        p.obols += p.day_income()
        p.spend()
        check(day)
        if day in cps:
            last = snapshot(p)
            snaps[day] = last
        if ms["p100"] is not None and ms["comp"] is not None and ms["d100"] is not None:
            break
    # after completion the collection stays complete: fill the remaining checkpoints with the final state
    final = snapshot(p)
    for c in cps:
        if c not in snaps and c > day:
            snaps[c] = final
    return {"ms": ms, "snaps": snaps, "income": p.income, "hours": p.hours, "games": p.games,
            "opened": p.opened, "rolled_leg": p.rolled_leg, "rolled_epic": p.rolled_epic,
            "first_leg": p.first_leg, "first_epic": p.first_epic, "new_leg": p.first_new_leg, "new_epic": p.first_new_epic, "dup_total": p.dup_total,
            "dup_count": p.dup_count, "days": day, "crafted": p.crafted, "start_unique": p.start_unique,
            "start_legs": p.start_legs, "ash_left": p.ash}


# --------------------------------------------------------------------------- batch + stats

def run_cell(args):
    e, prof, n, seed, horizon = args
    return e.key, prof.key, [simulate(e, prof, seed * 100003 + i, horizon) for i in range(n)]


def pct(vals, q):
    """q-quantile of values where None = never (treated as +inf)."""
    xs = sorted(math.inf if v is None else v for v in vals)
    if not xs:
        return None
    pos = q * (len(xs) - 1)
    lo, hi = math.floor(pos), math.ceil(pos)
    a, b = xs[lo], xs[hi]
    if a == b:
        return a
    return a + (b - a) * (pos - lo) if b != math.inf else math.inf


def fmt_days(v, horizon):
    if v is None or v == math.inf:
        return ">%d" % horizon
    return "%d" % round(v)


def med(vals):
    vals = [v for v in vals if v is not None]
    return statistics.median(vals) if vals else 0


MAX_SECONDS = 1800  # a whole run may take this long at most (main sets it from --max-seconds)


def run_all(variants, profiles, players, seed, horizon, workers):
    """Runs every (variant, profile) cell in a process pool. A run that outlives MAX_SECONDS stops: its workers are
    terminated and the script exits with an error, so a stuck cell can never leave processes burning the CPU (one
    once ran for a day after the agent that started it had finished)."""
    jobs = [(e, p, players, seed, horizon) for e in variants for p in profiles]
    res = {}
    ex = cf.ProcessPoolExecutor(max_workers=workers)
    try:
        for ek, pk, runs in ex.map(run_cell, jobs, timeout=MAX_SECONDS):
            res[(ek, pk)] = runs
    except cf.TimeoutError:
        for proc in list(getattr(ex, "_processes", {}).values()):
            proc.terminate()
        ex.shutdown(wait=False, cancel_futures=True)
        sys.exit("progression.py: gave up after %d s (a cell is stuck); workers terminated" % MAX_SECONDS)
    ex.shutdown()
    return res


# --------------------------------------------------------------------------- report

def lists_table(w: World) -> str:
    out = ["| Class | Role | Top cards (power score order) |", "|---|---|---|"]
    for k, cls in enumerate(CLASSES):
        L = w.lists[k]
        nm = lambda ids: ", ".join(w.cards[i]["name"] for i in ids)
        out.append("| %s | legendary (own 1 of 5) | %s |" % (cls, nm(L["leg"])))
        out.append("| %s | epic (4 slots of 8) | %s |" % (cls, nm(L["epic"])))
        out.append("| %s | common/rare (25 slots of 30) | %s |" % (cls, nm(L["cr"])))
    return "\n".join(out)


def table(title_cols, rows):
    head = "| " + " | ".join(title_cols) + " |\n|" + "|".join(["---"] + ["---:"] * (len(title_cols) - 1)) + "|\n"
    return head + "\n".join("| " + " | ".join(r) + " |" for r in rows) + "\n"


def metric_table(res, variants, profiles, horizon, fn, header="Variant"):
    rows = []
    for e in variants:
        rows.append([e.label] + [fn(res[(e.key, p.key)]) for p in profiles])
    return table([header] + [p.key for p in profiles], rows)


def ms_median(key, horizon):
    return lambda runs: fmt_days(pct([r["ms"][key] for r in runs], 0.5), horizon)


def ms_range(key, horizon):
    return lambda runs: "%s (%s-%s)" % (fmt_days(pct([r["ms"][key] for r in runs], 0.5), horizon),
                                        fmt_days(pct([r["ms"][key] for r in runs], 0.1), horizon),
                                        fmt_days(pct([r["ms"][key] for r in runs], 0.9), horizon))


def pack_facts(w, variants) -> str:
    """Per-pack facts that do not depend on the player: legendary rate and the refund of a pack of duplicates."""
    out = ["## Pack facts\n",
           "Monte Carlo over 40000 packs with the real pack rules (pity and guaranteed rare included), "
           "for a player who already owns everything.\n"]
    rows = []
    seen = set()
    for e in variants:
        sig = (e.pack_price, e.dup_value, e.protect)
        if sig in seen or e.quests or e.focus:
            continue
        seen.add(sig)
        pl = Player(e, PROFILES[0], 1, 0)
        for i in range(w.n):
            pl.owned[i] = w.maxc[i]
        n = 40000
        for _ in range(n):
            pl.packs = 1
            pl.open_pack()
        leg, epic = pl.rolled_leg / n, pl.rolled_epic / n
        refund = pl.dup_total / n
        rows.append([e.label, "%.1f" % (1 / leg), "%.2f" % epic, "%.0f" % refund,
                     "%.0f%%" % (100 * refund / e.pack_price)])
    out.append(table(["Variant", "Packs per legendary", "Epics per pack", "Value of a pack of duplicates",
                      "as % of pack price"], rows))
    out.append("In the current economy a pack of duplicates refunds about as much as it costs, so once the "
               "collection is mostly complete the remaining packs are almost free: completion speeds up with "
               "time (a snowball), see the trajectories.\n")
    return "\n".join(out)


def build_report(w, variants, profiles, res, args, extra_sections: dict) -> str:
    g = w.consts
    H = args.horizon
    main = [e for e in variants if not e.focus]
    foc = [e for e in variants if e.focus]
    o = []
    o.append("# Economy and progression simulation\n")
    o.append("Generated by `tools/sim/progression.py` (seed %d, %d simulated players per profile and variant, "
             "horizon %d days). Do not edit by hand: rerun the script (see the end of this file). The "
             "recommendation text comes from `tools/sim/economy_recommendation.md`.\n" % (args.seed, args.players, H))
    o.append(extra_sections.get("rec", ""))
    o.append("## What is simulated\n")
    o.append("Constants parsed from `scripts/core/collection.gd`: pack price %d Obols, %d cards per pack, win %d / loss "
             "%d Obols, %d start packs, odds legendary %.1f%% / epic %.1f%% / rare %.1f%% per slot (at least one rare, "
             "legendary pity at %d packs), max copies %s, refund for a copy beyond the limit %s. The pool is the %d "
             "collectible cards (%s). The two starter decks are owned from day 0 (%d unique cards, of which %d "
             "legendary).\n" % (
        g["PACK_PRICE"], g["PACK_SIZE"], g["WIN_REWARD"], g["LOSS_REWARD"], g["START_PACKS"],
        100 * g["ODDS"]["legendary"], 100 * g["ODDS"]["epic"], 100 * g["ODDS"]["rare"], g["PITY_LEGENDARY"],
        g["MAX_COPIES"], g["REFUND"], w.n, ", ".join("%d %s" % (len(w.by_rar[r]), RARITIES[r]) for r in range(4)),
        sum(1 for n in w.start if n), sum(1 for i, n in enumerate(w.start) if n and w.rar[i] == 3)))
    o.append("**Players.** Each plays every day (games per day jittered +-30%%, wins binomial), a game lasts %.0f "
             "minutes, and they spend every Obol on packs as soon as they can. "
             "%s. The same virtual player index uses the same dice in every variant (common random numbers), so "
             "differences between variants are economy effects, not luck.\n" % (
        GAME_MINUTES, "; ".join("**%s**: %d games/day at %d%% wins (%.0f Obols/day from games, %.1f h/day)" % (
            p.key, p.games, round(100 * p.win_rate),
            p.games * (p.win_rate * g["WIN_REWARD"] + (1 - p.win_rate) * g["LOSS_REWARD"]),
            p.games * GAME_MINUTES / 60) for p in profiles)))
    o.append("**Milestones.** Collection %% is *unique cards owned* out of %d. \"Full playset\" means every card at its "
             "copy limit (%d copies). The **competitive deck proxy** (`comp.`) is deliberately simple: for at least one "
             "class (class cards + neutral), the player owns (a) at least 1 of the 5 best legendaries, (b) 4 copy-slots "
             "(max 2 per card) among the 8 best epics, and (c) 25 copy-slots (max 2 per card) among the 30 best "
             "commons/rares. That is exactly a 30-card deck (1 + 4 + 25) built from the top of the class pool. 'Best' "
             "is a crude power score (stats vs the mana curve, keyword and effect bonuses, small rarity prior; see the "
             "lists in the appendix), so read the proxy as a pacing yardstick, not as a statement about the meta. "
             "Crafting players first craft what the proxy lacks (legendary, then epics, then rares, then commons), "
             "then everything else of their class, then the rest. Players with crafting pick one class at the start "
             "(half of them each); players without crafting get credit for whichever class is ready.\n" % (
        w.n, w.total_playset))
    o.append("**Variants.**\n")
    for e in main:
        bits = ["pack %d" % e.pack_price]
        if e.craft:
            bits.append("craft %s Ash, disenchant %s, duplicates become Ash" % ("/".join(map(str, e.craft)),
                                                                                "/".join(map(str, e.dis))))
        else:
            bits.append("duplicates refund %s Obols" % "/".join(map(str, e.dup_value)))
        if (e.win, e.loss) != (w.consts["WIN_REWARD"], w.consts["LOSS_REWARD"]):
            bits.append("win %d / loss %d Obols" % (e.win, e.loss))
        if e.quests:
            bits.append("3 daily quests (play 1 / 3 / 5 games: %s Obols) + %d first-win bonus" % (
                " / ".join(str(r) for _, r in e.quests), e.first_win_bonus))
        if e.protect:
            bits.append("duplicate protection on epic and legendary pulls (a pull is a card you do not yet have "
                        "at the limit, until you own them all)")
        o.append("- **%s**: %s" % (e.label, "; ".join(bits)))
    o.append("\n'Focus policy' rows (labelled `Xf`) are the same crafting economies played by someone who "
             "disenchants every card of the other class (and the starter deck of that class) until the first "
             "competitive deck exists, then goes back to collecting.\n")

    def sect(title, fn, rows=main, note=""):
        o.append("## " + title + "\n")
        if note:
            o.append(note + "\n")
        o.append(metric_table(res, rows, profiles, H, fn))

    o.append("# Results\n")
    sect("Days to a competitive deck (median, 10th-90th percentile)", ms_range("comp", H),
         note="Day 0 = the moment you start (3 start packs opened). '>%d' = most players never got there." % H)
    sect("Days to 50% of the collection (unique cards, median)", ms_median("d50", H))
    sect("Days to 90% of the collection (unique cards, median, 10th-90th percentile)", ms_range("d90", H))
    sect("Days to 100% of the unique cards (median, 10th-90th percentile)", ms_range("d100", H))
    sect("Days to a full playset (all copies at the limit; median, 10th-90th percentile)", ms_range("p100", H))
    sect("Days to own half (9) of the 18 legendaries (median)", ms_median("leg9", H))
    sect("Days to own all 18 legendaries (median)", ms_median("leg18", H))
    sect("Packs opened until the first NEW legendary / NEW epic comes out of a pack (median; start decks excluded)",
         lambda r: "%s / %s" % (fmt_days(pct([x["new_leg"][1] if x["new_leg"] else None for x in r], 0.5), H),
                                fmt_days(pct([x["new_epic"][1] if x["new_epic"] else None for x in r], 0.5), H)))

    def pk(key):
        return lambda r: "%s" % fmt_days(pct([x["ms"][key] for x in r], 0.5), H)
    sect("Packs opened until 9 of the 18 legendaries are owned (median; packs bought with refunds included)", pk("leg9p"))
    sect("Packs opened until all 18 legendaries are owned (median)", pk("leg18p"))
    o.append(pack_facts(w, main))

    def packs_to_comp(runs):
        return "%d" % med([r["ms"]["packs_comp"] for r in runs if r["ms"]["comp"] is not None]) \
            if any(r["ms"]["comp"] is not None for r in runs) else "-"
    sect("Packs opened by the time the first competitive deck exists (median of those who got there)",
         packs_to_comp)

    def hours_to_comp(runs):
        xs = [r["ms"]["h_comp"] for r in runs]
        v = pct(xs, 0.5)
        return ">%d h" % math.ceil(max(r["hours"] for r in runs)) if v is None or v == math.inf else "%.1f h" % v
    sect("Hours of play until the first competitive deck (median)", hours_to_comp)

    def income_hour(runs):
        h = sum(r["hours"] for r in runs)
        return "%.0f" % (sum(r["income"] for r in runs) / h)
    def packs_hour(runs):
        h = sum(r["hours"] for r in runs)
        return "%.2f" % (sum(r["income"] for r in runs) / h / 100.0)
    sect("Obols earned per hour of play (from games, quests and bonuses; Obols per hour / packs per hour at 100)",
         lambda r: "%s / %s" % (income_hour(r), packs_hour(r)),
         note="Pack-equivalents use the base 100 Obol price. Duplicate refunds are not counted as income here.")

    def per_day(runs):
        d = sum(r["days"] for r in runs)
        v = sum(r["income"] for r in runs) / d
        return "%.0f / %.1f" % (v, v / 100.0)
    sect("Obols earned per active day, before duplicate refunds (Obols / packs at 100)", per_day,
         note="Computed over the days each player was simulated (until the collection was complete).")

    def dupe_share(runs):
        return "%.0f%%" % (100.0 * sum(r["dup_total"] for r in runs) / max(1, sum(r["income"] + 0 for r in runs) +
                                                                          sum(r["dup_total"] for r in runs)))
    sect("Duplicate refunds / Ash from duplicates as a share of total currency earned (whole run, until the "
         "collection is complete)", dupe_share)

    if foc:
        o.append("## Focus policy: days to a competitive deck\n")
        o.append("Compare with the same variant without focus above. (Collection percentages of these rows are not "
                 "meaningful because the player disenchants cards on purpose.)\n")
        rows = []
        for e in main:
            if e.craft:
                f = next(x for x in foc if x.key == e.key + "+F")
                rows.append([e.label.split("  ")[0] + "  same economy, collector policy"] +
                            [ms_range("comp", H)(res[(e.key, p.key)]) for p in profiles])
                rows.append([f.label] + [ms_range("comp", H)(res[(f.key, p.key)]) for p in profiles])
        o.append(table(["Variant"] + [p.key for p in profiles], rows))

    # trajectories of the current economy
    o.append("## Trajectory of the current economy (A), median per checkpoint\n")
    o.append("A player who completes the collection stops being simulated; later rows repeat the final state "
             "(so 'Obols unspent' there is just what was left over).\n")
    for p in profiles:
        runs = res[("A", p.key)]
        rows = []
        for d in [0, 1, 3, 7, 14, 28, 56, 84, 120, 180, 270, 365]:
            sn = [r["snaps"].get(d) for r in runs]
            sn = [s for s in sn if s]
            if not sn:
                continue
            m = lambda j: statistics.median([s[j] for s in sn])
            rows.append(["%d" % d, "%.0f" % m(0), "%.0f" % m(1), "%.0f" % m(2),
                         "%.0f%%" % (100 * m(2) / w.n), "%.0f%%" % (100 * m(3) / w.total_playset), "%.0f" % m(4),
                         "%.0f" % m(5), "%.0f%%" % (100 * sum(s[6] for s in sn) / len(sn)), "%.0f" % m(7)])
        o.append("### %s (%d games/day, %d%% wins)\n" % (p.key, p.games, round(100 * p.win_rate)))
        o.append(table(["Day", "Obols unspent", "Packs opened", "Unique", "% unique", "% playset", "Legendaries",
                        "Epics", "Competitive", "Refunds so far"], rows))

    o.append("## Trajectory of every variant: median % unique cards and % competitive at selected days\n")
    cols = [7, 14, 30, 60, 90, 180, 365]
    for p in profiles:
        rows = []
        for e in main:
            runs = res[(e.key, p.key)]
            cells = []
            for d in cols:
                sn = [r["snaps"].get(d) for r in runs]
                sn = [s for s in sn if s]
                cells.append("%.0f%% / %.0f%%" % (100 * statistics.median([s[2] for s in sn]) / w.n,
                                                  100 * sum(s[6] for s in sn) / len(sn)))
            rows.append([e.label.split("  ")[0] + " " + e.label.split("  ", 1)[1][:34]] + cells)
        o.append("### %s\n" % p.key)
        o.append(table(["Variant (unique % / competitive %)"] + ["day %d" % d for d in cols], rows))

    if "sweep" in extra_sections:
        o.append(extra_sections["sweep"])
    o.append("## Appendix: the 'best card' lists used by the competitive proxy\n")
    o.append(lists_table(w) + "\n")
    o.append("## How to rerun\n")
    o.append("```sh\npython tools/sim/progression.py                       # full run (about %s), rewrites this "
             "file and the weekly CSV\npython tools/sim/progression.py --quick               # smoke test, 20 "
             "players\npython tools/sim/progression.py --players 600 --seed 7 --out docs/ECONOMY_SIM.md\n"
             "python tools/sim/progression.py --sweep                # also run the craft-cost sensitivity table\n"
             "```\n" % args.runtime_hint)
    o.append("Edit `PROFILES`, `QUESTS`, `build_variants()` or the `--tuned-craft` / `--tuned-dis` options to test "
             "other economies. The game constants are re-read from `scripts/core/collection.gd` on every run, "
             "and the card pool from `data/`.\n")
    o.append("## Caveats\n")
    o.append("- Win rate is fixed per profile and does not depend on the collection (a real player with a better "
             "deck wins more, which speeds everything up a little). There is no AI difficulty curve, no retention "
             "model (players never quit) and no skipped days.\n"
             "- The power score is a crude proxy; the card pool is not yet balance-tested. Treat 'competitive' "
             "days as relative between variants, not as a promise.\n"
             "- Players are rational spenders (all Obols into packs at once, optimal-ish crafting). Real players "
             "hoard, mis-craft and quit, so real progression is slower and more varied.\n"
             "- After a player's collection is complete the simulation stops; later checkpoints use the final state.\n")
    return "\n".join(o)


def weekly_csv(res, variants, profiles, w):
    lines = ["variant,profile,day,obols_unspent,packs_opened,unique,pct_unique,pct_playset,legendaries,epics,"
             "pct_players_competitive,refunds_or_ash_from_dupes"]
    for e in variants:
        for p in profiles:
            runs = res[(e.key, p.key)]
            for d in [0] + list(range(7, WEEKLY_MAX + 1, 7)):
                sn = [r["snaps"].get(d) for r in runs]
                sn = [s for s in sn if s]
                if not sn:
                    continue
                m = lambda j: statistics.median([s[j] for s in sn])
                lines.append("%s,%s,%d,%.0f,%.0f,%.0f,%.1f,%.1f,%.1f,%.1f,%.1f,%.0f" % (
                    e.key, p.key, d, m(0), m(1), m(2), 100 * m(2) / w.n, 100 * m(3) / w.total_playset, m(4), m(5),
                    100 * sum(s[6] for s in sn) / len(sn), m(7)))
    return "\n".join(lines) + "\n"


def sweep_section(g, args, profiles) -> str:
    """Two sensitivity tables: craft-cost level, and game reward x quest size (both with several hundred sims)."""
    a = base_econ(g)
    H = args.horizon
    n = args.sweep_players
    o = []
    # ---- 1. craft costs
    variants = []
    for scale in (2.0, 1.0, 0.75, 0.5, 0.35):
        craft = tuple(max(1, round(c * scale)) for c in HS_CRAFT)
        for dis in (HS_DIS, (5, 20, 80, 300)):
            variants.append(replace(a, key="S%.2f/%s" % (scale, dis), label="craft x%.2f = %s, disenchant %s" % (
                scale, "/".join(map(str, craft)), "/".join(map(str, dis))), craft=craft, dis=dis, dup_value=dis,
                dup_to="ash"))
    res = run_all(variants, profiles, n, args.seed + 1, H, args.workers)
    o.append("## Sensitivity 1: craft costs (current rewards, no quests, no protection)\n")
    o.append("Cells: median days to a competitive deck / to 90%% unique / to a full playset. %d players per cell.\n" % n)
    rows = []
    for e in variants:
        rows.append([e.label] + ["%s / %s / %s" % tuple(
            fmt_days(pct([r["ms"][k] for r in res[(e.key, p.key)]], 0.5), H) for k in ("comp", "d90", "p100"))
            for p in profiles])
    o.append(table(["Crafting costs"] + [p.key for p in profiles], rows))
    # ---- 2. game rewards x quest size
    variants = []
    for w_, l_ in ((100, 25), (60, 15), (50, 10), (40, 10)):
        for qn, q, fw in (("no quests", (), 0), ("half quests", HALF_QUESTS, HALF_FIRST_WIN),
                          ("full quests", QUESTS, FIRST_WIN)):
            variants.append(replace(a, key="R%d/%d/%s" % (w_, l_, qn), label="win %d / loss %d, %s" % (w_, l_, qn),
                                    win=w_, loss=l_, craft=(30, 80, 250, 700), dis=(5, 20, 80, 300),
                                    dup_value=(5, 20, 80, 300), dup_to="ash", quests=q, first_win_bonus=fw,
                                    protect=(2, 3)))
    res = run_all(variants, profiles, n, args.seed + 2, H, args.workers)
    o.append("## Sensitivity 2: game rewards and quest size (B2 crafting + duplicate protection)\n")
    o.append("Half quests = 25 / 40 / 50 Obols + 25 first-win bonus; full quests = 50 / 75 / 100 + 50. Cells: median "
             "days to a competitive deck / 90%% unique / full playset, then Obols earned per active day. %d players per "
             "cell.\n" % n)
    rows = []
    for e in variants:
        cells = []
        for p in profiles:
            rr = res[(e.key, p.key)]
            cells.append("%s / %s / %s ; %d/day" % (
                *[fmt_days(pct([r["ms"][k] for r in rr], 0.5), H) for k in ("comp", "d90", "p100")],
                round(sum(r["income"] for r in rr) / sum(r["days"] for r in rr))))
        rows.append([e.label] + cells)
    o.append(table(["Rewards"] + [p.key for p in profiles], rows))
    return "\n".join(o)


def main():
    global MAX_SECONDS
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--players", type=int, default=400, help="simulated players per profile and variant")
    ap.add_argument("--seed", type=int, default=2026)
    ap.add_argument("--horizon", type=int, default=1000, help="max simulated days per player")
    ap.add_argument("--out", default=os.path.join(ROOT, "docs", "ECONOMY_SIM.md"))
    ap.add_argument("--csv", default=os.path.join(ROOT, "docs", "economy_sim_weekly.csv"))
    ap.add_argument("--quick", action="store_true", help="20 players, write to a scratch file only")
    ap.add_argument("--sweep", action="store_true", help="add the craft-cost sensitivity table")
    ap.add_argument("--sweep-players", type=int, default=150)
    # Half the cores: the game, its tests and other tools share the machine.
    ap.add_argument("--workers", type=int, default=max(1, (os.cpu_count() or 2) // 2))
    ap.add_argument("--max-seconds", type=int, default=MAX_SECONDS, help="stop (and kill the workers) after this long")
    ap.add_argument("--tuned-craft", default="30,80,250,700", help="craft costs C,R,E,L of variant B2/D/E")
    ap.add_argument("--tuned-dis", default="5,20,80,300", help="disenchant values C,R,E,L of variant B2/D/E")
    ap.add_argument("--print-only", action="store_true", help="print the report instead of writing files")
    args = ap.parse_args()
    MAX_SECONDS = args.max_seconds
    args.runtime_hint = "3 minutes on 20 logical cores"
    if args.quick:
        args.players, args.sweep_players = 20, 20
        args.print_only = True
    w = world()
    g = w.consts
    tc = tuple(int(x) for x in args.tuned_craft.split(","))
    td = tuple(int(x) for x in args.tuned_dis.split(","))
    variants = build_variants(g, tc, td)
    res = run_all(variants, PROFILES, args.players, args.seed, args.horizon, args.workers)
    extra = {}
    rec = os.path.join(ROOT, "tools", "sim", "economy_recommendation.md")
    if os.path.exists(rec):
        extra["rec"] = open(rec, encoding="utf-8").read()
    if args.sweep:
        extra["sweep"] = sweep_section(g, args, PROFILES)
    report = build_report(w, variants, PROFILES, res, args, extra)
    if args.print_only:
        sys.stdout.write(report)
        return
    open(args.out, "w", encoding="utf-8", newline="\n").write(report)
    open(args.csv, "w", encoding="utf-8", newline="\n").write(weekly_csv(res, variants, PROFILES, w))
    print("wrote", args.out, "and", args.csv)


if __name__ == "__main__":
    main()
