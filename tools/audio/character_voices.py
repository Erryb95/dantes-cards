"""Every character's own voice: a play sound and a death sound for each minion, a start and a defeat sound per hero.

    python -I tools/audio/character_voices.py pool  [--src <voices_src>]      # scan + analyse the source clips
    python -I tools/audio/character_voices.py build [--src <voices_src>] [--only id,id] [--dry]
    python -I tools/audio/character_voices.py check                          # uniqueness report on the outputs
    python -I tools/audio/character_voices.py reel  --out <dir> [--src ...]   # review reel for the owner

No voices are spoken: the sounds are non-verbal vocalisations (grunts, sighs, laughs, gasps, cries, growls, barks,
hisses...) from CC0 / public-domain packs, each pack downloaded with its licence checked on its page (meta.json next to
the files: OpenGameArt pages whose licence field offers CC0, Freesound HQ previews of sounds whose page says CC0,
an itch.io CC0 pack). The downloaded files are untrusted data: this script only reads them through ffmpeg and never
runs anything from them. Run it with `python -I` (the user site is added back for numpy only).

pool   splits every source file into its separate vocalisations (silence detection), measures each one (duration,
       loudness, median pitch and how much of it is voiced, spectral centroid, flatness ~ roughness) and tags it from
       the pack, file name, Freesound title / tags and the search it came from: art_src/voices/pool.json.
build  maps each character to a voice archetype (name, art prompt, flavour, keywords, class, circle, rarity; hand
       overrides in data/voices.json), picks source clips per slot (never the same clip twice while unused ones fit)
       and a deterministic per-card treatment from the card id (rubberband pitch with formants kept for people and
       shifted for creatures, tempo, EQ tilt, room echo, chorus / vibrato for shades and old men, a quiet layer of the
       card's school from assets/audio/sfx, fades, trimming), loudness-normalises to -18 LUFS (ebur128, limiter at
       -1 dBFS) and writes mono Ogg Vorbis files: assets/audio/voices/<id>_play.ogg, <id>_death.ogg,
       hero_<id>.ogg, hero_<id>_defeat.ogg. Also writes assets/audio/voices/SOURCES.md (per-file sources),
       art_src/voices/voices.csv (every character: archetype, sources, processing) and the voices block of
       assets/CREDITS.md.
check  fingerprints every output (24 log-spaced band energies, loudness envelope and centroid trajectory) and
       reports the closest pairs; it fails on identical files or on two characters closer than the threshold.
"""
import argparse
import csv
import glob
import hashlib
import json
import math
import os
import random
import re
import shutil
import site
import subprocess
import sys
import tempfile

try:
    import numpy as np
except ImportError:  # python -I drops the user site, where numpy lives on this PC
    sys.path.append(site.getusersitepackages())
    import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FFMPEG = r"C:\Progetti\Tools\ffmpeg\bin\ffmpeg.exe"
DEFAULT_SRC = os.path.join(os.environ.get("LOCALAPPDATA", ""), "Temp", "claude", "C--Progetti-DantesCards",
                           "428763e6-f537-4bb5-8147-13d1af5d851d", "scratchpad", "voices_src")
POOL = os.path.join(ROOT, "art_src", "voices", "pool.json")
OUT = os.path.join(ROOT, "assets", "audio", "voices")
SFX = os.path.join(ROOT, "assets", "audio", "sfx")
OVERRIDES = os.path.join(ROOT, "data", "voices.json")
SR = 44100
TARGET_LUFS = -18.0
QUALITY = "1"  # libvorbis q1 mono: ~45 kbit/s, plenty for a one-second vocal
AUDIO_EXT = (".wav", ".flac", ".ogg", ".mp3", ".aif", ".aiff")


# ====================================================================== helpers

def run(cmd: list, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", check=check)


def decode(path: str, sr: int = 16000, t0: float = 0.0, dur: float = 0.0) -> "np.ndarray":
    cmd = [FFMPEG, "-hide_banner", "-loglevel", "error"]
    if t0 > 0:
        cmd += ["-ss", "%.3f" % t0]
    if dur > 0:
        cmd += ["-t", "%.3f" % dur]
    cmd += ["-i", path, "-ac", "1", "-ar", str(sr), "-f", "f32le", "-"]
    r = subprocess.run(cmd, capture_output=True, check=True)
    return np.frombuffer(r.stdout, dtype=np.float32).copy()


def h01(*parts) -> float:
    """A stable number in [0, 1) from the parts (the per-card dice)."""
    d = hashlib.sha1("|".join(str(p) for p in parts).encode("utf-8")).digest()
    return int.from_bytes(d[:8], "big") / float(1 << 64)


def rng_for(*parts) -> random.Random:
    return random.Random(int(h01(*parts) * (1 << 53)))


# ====================================================================== analysis

def frames(x: "np.ndarray", n: int, hop: int) -> "np.ndarray":
    if len(x) < n:
        x = np.pad(x, (0, n - len(x)))
    cnt = 1 + (len(x) - n) // hop
    idx = np.arange(n)[None, :] + hop * np.arange(cnt)[:, None]
    return x[idx]


def segments(x: "np.ndarray", sr: int) -> list:
    """The separate vocalisations in a file: runs louder than (peak - 32 dB), gaps under 0.15 s merged."""
    hop = sr // 100
    fr = frames(x, hop * 2, hop)
    rms = np.sqrt(np.mean(fr * fr, axis=1) + 1e-12)
    db = 20 * np.log10(rms)
    if db.max() < -50:
        return []
    th = max(db.max() - 32.0, -55.0)
    on = db > th
    segs, start, gap = [], None, 0
    for i, v in enumerate(on):
        if v:
            if start is None:
                start = i
            gap = 0
        elif start is not None:
            gap += 1
            if gap > 15:
                segs.append((start, i - gap))
                start, gap = None, 0
    if start is not None:
        segs.append((start, len(on) - 1 - gap))
    out = []
    for a, b in segs:
        t0 = max(0.0, a / 100.0 - 0.03)
        t1 = min(len(x) / sr, b / 100.0 + 0.12)
        if t1 - t0 >= 0.22:
            out.append((round(t0, 3), round(t1, 3)))
    return out


def features(x: "np.ndarray", sr: int) -> dict:
    n, hop = 1024, 256
    fr = frames(x, n, hop) * np.hanning(n)[None, :]
    rms = np.sqrt(np.mean(fr * fr, axis=1) + 1e-12)
    loud = rms > rms.max() * 0.1
    spec = np.abs(np.fft.rfft(fr, axis=1)) ** 2 + 1e-12
    freqs = np.fft.rfftfreq(n, 1.0 / sr)
    cent = (spec * freqs[None, :]).sum(1) / spec.sum(1)
    flat = np.exp(np.mean(np.log(spec), 1)) / np.mean(spec, 1)
    # YIN pitch on the loud frames: d(tau) = sum over a fixed window W of (x[j] - x[j + tau])^2
    raw = frames(x, n, hop)
    W = n // 2
    sq = np.cumsum(np.pad(raw * raw, ((0, 0), (1, 0))), axis=1)
    e0 = sq[:, W:W + 1] - sq[:, :1]
    et = sq[:, W:W + W] - sq[:, :W]  # energy of x[tau:tau+W] for tau = 0..W-1
    r = np.fft.irfft(np.conj(np.fft.rfft(raw[:, :W], 2 * n, axis=1)) * np.fft.rfft(raw, 2 * n, axis=1), axis=1)[:, :W]
    d = np.maximum(e0 + et - 2 * r, 0.0)
    d[:, 0] = 0
    cs = np.cumsum(d[:, 1:], axis=1)
    taus = np.arange(1, W)
    cm = np.ones_like(d)
    cm[:, 1:] = d[:, 1:] * taus[None, :] / np.maximum(cs, 1e-12)
    lo, hi = int(sr / 1100), min(W - 1, int(sr / 55))
    f0s = []
    for i in np.nonzero(loud)[0]:
        row = cm[i, lo:hi]
        below = np.nonzero(row < 0.2)[0]
        if len(below):
            j = below[0]
            while j + 1 < len(row) and row[j + 1] < row[j]:
                j += 1
            f0s.append(sr / (lo + j))
    voiced = len(f0s) / max(1, int(loud.sum()))
    peak = float(20 * np.log10(np.max(np.abs(x)) + 1e-9))
    w = rms[loud]
    return {
        "f0": round(float(np.median(f0s)), 1) if len(f0s) >= 3 else 0.0,
        "voiced": round(float(voiced), 2),
        "cent": round(float(np.sum(cent[loud] * w) / np.sum(w)), 0),
        "flat": round(float(np.sum(flat[loud] * w) / np.sum(w)), 3),
        "peak_db": round(peak, 1),
        "rms_db": round(float(20 * np.log10(np.sqrt(np.mean(x * x)) + 1e-9)), 1),
    }


# ====================================================================== tagging

# (regex on "<pack> <file> <title> <tags> <search tags>", categories). Every rule that matches adds its categories.
RULES = [
    # human men
    (r"\bmale[_ ]?grunt|man grunt|male_effort|male effort|strain|\bheave|\blift", ["m_grunt"]),
    (r"male_death|male death|man dying|death.*male|male.*dying|dying man|\bmale_scream|man scream", ["m_death"]),
    (r"male_pain|male pain|man groan|male moan|male hurt|man hurt|men.*pain|hurt.*male|grunts-male|man-hurt|pain-sounds|hurt-sound", ["m_pain"]),
    (r"male_old|old man|old_man|elderly|old-man", ["m_old"]),
    (r"male_old_laugh|old man laugh", ["m_old", "m_laugh"]),
    (r"male_sigh|man sigh", ["m_sigh"]),
    (r"male_gasp|male gasp", ["m_gasp"]),
    (r"male_laugh\b|man laugh|male chuckle|male_laugh$", ["m_laugh"]),
    (r"male_laugh_evil|evil laugh|evil-laugh|sinister-laugh|evil-laughter|maniacal", ["m_laugh_evil"]),
    (r"male_yell|male yell|gruntyelling|yell", ["m_yell"]),
    (r"male_warcry|battle cry|war cry|warcry", ["m_warcry"]),
    (r"male_cough|man cough|\bcough", ["m_cough"]),
    (r"male_hum|male hum", ["m_hum"]),
    (r"male_chant|chant|monk", ["m_chant"]),
    (r"male_breath|breathing heavy|breathing-tired|panting", ["m_breath"]),
    (r"male_young|young man|boy scream", ["m_young"]),
    (r"male_choke|choking|gurgle|drowning", ["m_choke"]),
    (r"male_growl|man growl", ["m_growl"]),
    (r"male_burp|burp|male_gulp|gulp|male_eat|man eating|\beat_\d|eating", ["m_eat"]),
    (r"male_hmph|hmph|sneer", ["m_hmph"]),
    (r"5-hit-sounds-dying|death-sounds-0|male-dead-voice|hurt-death-sound", ["m_death"]),
    (r"15-vocal-male|jumping-man|5-pillager", ["m_grunt"]),
    # women
    (r"female_sigh|woman sigh|female sigh", ["f_sigh"]),
    (r"female_gasp|female gasp|girl gasp", ["f_gasp"]),
    (r"female_scream|woman scream|female-scream|female-high-pitched|girly-scream", ["f_scream"]),
    (r"female_pain|female moan|woman groan|female hurt|female-hurt", ["f_pain"]),
    (r"female_cry|woman cry|\bsob", ["f_cry"]),
    (r"female_laugh\b|female laugh|woman giggle|giggl", ["f_laugh"]),
    (r"female_laugh_evil|witch|cackle|evil-screech", ["f_witch"]),
    (r"female_grunt|female grunt|woman effort", ["f_grunt"]),
    (r"female_death|female death", ["f_death"]),
    (r"female_hum|woman hum", ["f_hum"]),
    (r"female_breath|female breath", ["f_breath"]),
    (r"female_sing|soprano|singing", ["f_sing"]),
    (r"female_whisper|woman whisper", ["f_whisper"]),
    (r"female_old|old woman", ["f_old"]),
    # groups, choirs, spirits
    (r"crowd_angry|crowd angry|crowd shout|crowd_fight|men grunting|crowd_gasp", ["crowd"]),
    (r"choir_male|male choir", ["choir_m"]),
    (r"\bchoir\b|choir_holy|angelic|choir_|choir ah", ["choir"]),
    (r"\bwhisper", ["whisper"]),
    (r"ghost|ghast|spectral|wraith", ["ghost"]),
    (r"zombie|undead|ghoul|zomby", ["zombie"]),
    (r"horror-breathing|horrorbreathing|ghost-breath|ghostbreath", ["ghost_breath"]),
    # creatures
    (r"demon|devil|\bhell\b|hellish|dracula", ["demon"]),
    (r"demon_laugh|demon laugh", ["demon_laugh"]),
    (r"goblin|\bimp\b|tiny-creatures|tiny-vicious|\bcute_|\bgoblins", ["goblin"]),
    (r"monster_big|monster roar deep|deep-monster|troll|ogre|giant|minotaur|big-scary", ["monster_big"]),
    (r"giant", ["giant"]),
    (r"dragon", ["dragon"]),
    (r"monster_death|monster death|creature death|\bdie_\d|dyeing", ["monster_death"]),
    (r"monster_scream|monster scream|banshee", ["monster_scream"]),
    (r"creature|beast|monster|snarl|growl|\broar", ["creature"]),
    (r"insect|\bbug_|alien", ["insect"]),
    (r"slime|burble|slimy", ["slime"]),
    # animals
    (r"dog_bark|dog bark|barking|\bbark", ["dog_bark"]),
    (r"dog_growl|dog growl|dog-growl|dog-snarl|dog-grunt", ["dog_growl"]),
    (r"dog_whimper|whimper|dog_yelp|yelp", ["dog_yelp"]),
    (r"dog_pup|puppy", ["dog_pup", "dog_bark"]),
    (r"dog_demon|hellhound", ["dog_growl", "demon"]),
    (r"wolf_howl|wolf howl|\bhowl", ["wolf_howl"]),
    (r"wolf_growl|wolf growl|wolf-monster", ["wolf_growl"]),
    (r"\blion\b|lion roar|lion growl", ["lion"]),
    (r"big_cat|leopard|panther|tiger|jaguar", ["big_cat"]),
    (r"cat_hiss|cat hiss", ["cat_hiss"]),
    (r"horse_neigh|neigh|whinny", ["horse_neigh"]),
    (r"horse_snort|horse snort|snort", ["horse_snort"]),
    (r"\bbull\b|bellow|cow moo|\bmoo|\bcow\b|\byak", ["bull"]),
    (r"\bpig\b|pig grunt|pig squeal|\bboar|\bswine|\boink", ["pig"]),
    (r"snake|hiss|rattlesnake|serpent|cobra", ["snake"]),
    (r"\bcrow\b|crow caw|raven|\bcaw", ["crow"]),
    (r"\bowl\b|owl hoot", ["owl"]),
    (r"raptor|hawk|eagle|vulture|falcon", ["raptor"]),
    (r"\bbat\b|bat screech|bat-screech", ["bat"]),
    (r"seagull|\bgull", ["gull"]),
    (r"goat|sheep|\bbaa\b|bleat", ["goat"]),
    (r"camel", ["camel"]),
    (r"elephant", ["elephant"]),
    (r"\bbear\b|bear-growl|bear roar|bear growl", ["bear"]),
    (r"monkey|\bape\b|gorilla|chimp", ["ape"]),
    (r"frog|croak", ["frog"]),
    (r"\bwings?\b|flap|flutter", ["wings"]),
    (r"parrot|swan|rooster|\bbird", ["bird"]),
    # objects and elements
    (r"wood_creak|wood creak|creak", ["wood_creak"]),
    (r"\bship\b|rope creak|ship creak|\bboat", ["ship"]),
    (r"tree creak|\btree\b|branch", ["tree"]),
    (r"leaves|rustle|\breed", ["leaves"]),
    (r"stone grind|stone_roll|stone rolling|boulder|\brock", ["stone"]),
    (r"\bharp\b|lyre|pluck", ["harp"]),
    (r"\bchime|bell chime", ["chime"]),
    (r"shimmer|sparkle|magic", ["shimmer"]),
    (r"\bwhip", ["whip"]),
    (r"chain", ["chains"]),
    (r"\bmud\b|squelch|25-cc0-mud", ["mud"]),
    (r"bubbl|bubbles gurgle", ["bubbles"]),
    (r"\bice\b|ice crack|freez", ["ice"]),
    (r"\bfire\b|flame|fire whoosh|fire burst", ["fire"]),
    (r"steam", ["steam"]),
    (r"\bhorn\b|war horn|horn blow", ["horn"]),
    (r"\bcoins?\b", ["coins"]),
    (r"sword|unsheath", ["sword"]),
    (r"hooves|gallop|trot", ["hooves"]),
    (r"\bwaves?\b|wave crash|\bsea\b", ["wave"]),
    (r"\bwind\b|whirlwind|tornado", ["wind"]),
    (r"rumble|thunder|earthquake", ["rumble"]),
    (r"sizzle", ["sizzle"]),
    (r"\bpage|book", ["page"]),
    (r"flute", ["flute"]),
    (r"\bdrum", ["drum"]),
    (r"heartbeat", ["heart"]),
    (r"bite|crunch|chew", ["bite"]),
    (r"slurp", ["slurp"]),
]

# Freesound searches name exactly what was asked for: the search tag decides first (its categories are trusted more).
QUERY_CATS = {
    "female_sigh": ["f_sigh"], "female_gasp": ["f_gasp"], "female_scream": ["f_scream"], "female_pain": ["f_pain"],
    "female_cry": ["f_cry"], "female_laugh": ["f_laugh"], "female_grunt": ["f_grunt"], "female_death": ["f_death"],
    "female_hum": ["f_hum"], "female_breath": ["f_breath"], "female_laugh_evil": ["f_witch"], "female_old": ["f_old"],
    "female_sing": ["f_sing"], "female_whisper": ["f_whisper"],
    "male_grunt": ["m_grunt"], "male_death": ["m_death"], "male_old": ["m_old"], "male_old_laugh": ["m_old", "m_laugh"],
    "male_sigh": ["m_sigh"], "male_gasp": ["m_gasp"], "male_laugh": ["m_laugh"], "male_laugh_evil": ["m_laugh_evil"],
    "male_yell": ["m_yell"], "male_scream": ["m_death"], "male_pain": ["m_pain"], "male_cough": ["m_cough"],
    "male_hum": ["m_hum"], "male_chant": ["m_chant"], "male_warcry": ["m_warcry"], "male_breath": ["m_breath"],
    "male_young": ["m_young"], "male_choke": ["m_choke"], "male_growl": ["m_growl"], "male_burp": ["m_eat"],
    "male_gulp": ["m_eat"], "male_eat": ["m_eat"], "male_hmph": ["m_hmph"],
    "crowd_angry": ["crowd"], "crowd_gasp": ["crowd"], "crowd_fight": ["crowd"], "choir_male": ["choir_m"],
    "choir": ["choir"], "choir_holy": ["choir"], "whisper": ["whisper"], "ghost": ["ghost"], "zombie": ["zombie"],
    "dog_bark": ["dog_bark"], "dog_growl": ["dog_growl"], "dog_bark_big": ["dog_bark"], "dog_whimper": ["dog_yelp"],
    "dog_yelp": ["dog_yelp"], "dog_pup": ["dog_pup"], "wolf_howl": ["wolf_howl"], "wolf_growl": ["wolf_growl"],
    "lion": ["lion"], "big_cat": ["big_cat"], "cat_hiss": ["cat_hiss"], "horse_neigh": ["horse_neigh"],
    "horse_snort": ["horse_snort"], "bull": ["bull"], "pig": ["pig"], "snake": ["snake"], "crow": ["crow"],
    "owl": ["owl"], "raptor": ["raptor"], "bat": ["bat"], "gull": ["gull"], "goat": ["goat"], "camel": ["camel"],
    "elephant": ["elephant"], "bear": ["bear"], "ape": ["ape"], "frog": ["frog"], "wings": ["wings"],
    "wings_big": ["wings"], "bird": ["bird"],
    "giant": ["monster_big", "giant"], "dragon": ["dragon", "monster_big"], "monster_big": ["monster_big"],
    "demon": ["demon"], "demon_laugh": ["demon_laugh", "demon"], "creature": ["creature"],
    "monster_death": ["monster_death"], "goblin": ["goblin"], "monster_scream": ["monster_scream"],
    "dog_demon": ["dog_growl", "demon"], "insect": ["insect"],
    "wood_creak": ["wood_creak"], "ship": ["ship", "wood_creak"], "tree": ["tree", "wood_creak"],
    "leaves": ["leaves"], "stone": ["stone"], "stone_roll": ["stone"], "harp": ["harp"], "chime": ["chime"],
    "shimmer": ["shimmer"], "whip": ["whip"], "chains": ["chains"], "mud": ["mud"], "bubbles": ["bubbles"],
    "ice": ["ice"], "fire": ["fire"], "steam": ["steam"], "horn": ["horn"], "coins": ["coins"], "sword": ["sword"],
    "hooves": ["hooves"], "wave": ["wave"], "wind": ["wind"], "rumble": ["rumble"], "sizzle": ["sizzle"],
    "page": ["page"], "quill": ["page"], "flute": ["flute"], "drum": ["drum"], "heart": ["heart"], "bite": ["bite"],
    "slurp": ["slurp"],
}
# Packs whose whole content is one kind (base categories, before the file-name rules).
PACK_CATS = {
    "16-monster-growls": ["creature"], "7-ghast-sounds": ["ghost"], "big-scary-troll-sounds": ["monster_big"],
    "cc0-deep-monster-roar": ["monster_big"], "ghost": ["ghost"], "ghost-breath": ["ghost_breath"],
    "ghost-monster-voice-moaning-growling": ["ghost"], "ghostmonster-sounds": ["ghost", "creature"],
    "high-pitch-scream-sounds2": ["monster_scream"], "horror-breathing": ["ghost_breath"], "hungry-ghoul": ["zombie"],
    "insect-or-alien-scream": ["insect"], "monster-snarls": ["creature"], "monster-sound-effects-2": ["creature"],
    "monster-sound-effects-pack": ["creature"], "monster-sound-pack-volume-1": ["creature"],
    "osare-minotaur-sounds": ["monster_big", "bull"], "silent-beast-growls4": ["creature"],
    "slimy-monster-or-murder-sounds9": ["slime", "creature"], "some-kind-of-beings-sounds7": ["creature"],
    "tiny-creatures-sounds": ["goblin"], "tiny-vicious-creature": ["goblin"], "undead-moans": ["zombie"],
    "wolf-monster-sound": ["wolf_growl"], "zombie-moans": ["zombie"], "zombie-pain": ["zombie", "m_pain"],
    "zombie-skeleton-monster-voice-effects": ["zombie"], "zombies-sound-pack": ["zombie"],
    "zombie-moans-01-by-emopreben": ["zombie"], "zomby-sfx-pack": ["zombie"], "zombie-noises-and-moans": ["zombie"],
    "grunts-male-death-and-pain": ["m_pain"], "male-gruntyelling-sounds": ["m_yell"],
    "15-vocal-male-strainhurtpainjump-sounds": ["m_grunt"], "man-hurt-sounds": ["m_pain"],
    "hurt-sound-effects": ["m_pain"], "pain-sounds-by-emopreben": ["m_pain"], "5-hit-sounds-dying": ["m_death"],
    "death-sounds-0": ["m_death"], "old-man-cough": ["m_old", "m_cough"], "sick-noises": ["m_cough"],
    "breathing-tired": ["m_breath"], "male-dead-voice": ["m_death"], "5-pillager-sounds": ["m_grunt"],
    "jumping-man-sounds": ["m_grunt"], "evil-laugh": ["m_laugh_evil"], "evil-laugh-2": ["m_laugh_evil"],
    "evil-laughter": ["m_laugh_evil"], "sinister-laugh": ["m_laugh_evil"],
    "hurt-death-sound-effect-for-character": ["m_death"], "female-hurt-grunts-groans": ["f_pain"],
    "female-scream-1": ["f_scream"], "female-high-pitched-scream-sfx": ["f_scream"], "girly-scream": ["f_scream"],
    "evil-cackle-laugh-1": ["f_witch"], "evil-cackle-laugh-2": ["f_witch"], "evil-screech-1": ["f_witch"],
    "ghostly-cackle-laugh-1": ["f_witch", "ghost"], "witch-cackle": ["f_witch"], "maniacal-laughter-pack-1": ["m_laugh_evil"],
    "group-giggling": ["f_laugh", "crowd"], "dog-barking-mono": ["dog_bark"], "dog-growl": ["dog_growl"],
    "dog-grunt": ["dog_growl"], "dog-snarl-grunt-grumble": ["dog_growl"], "dog-sounds": ["dog_bark"],
    "bear-growls": ["bear"], "gorilla-sounds": ["ape"], "camel-groan": ["camel"], "donkey-bray": ["horse_neigh"],
    "boar-0": ["pig"], "sheep-baa": ["goat"], "crow": ["crow"], "crow-caw": ["crow"], "crows-singing": ["crow"],
    "vulture-imitation": ["raptor"], "peacock-scream": ["bird"], "bat-screeches": ["bat"], "cat-purr-meow": ["cat_hiss"],
    "fantasy-desert-ride-able-camel": ["camel"], "frog-croaks": ["frog"], "yak-imitation": ["bull"],
    "small-dino-raspy-calls": ["raptor", "creature"], "t-rex-calls": ["monster_big", "dragon"],
    "goblins-sound-pack": ["goblin"], "25-cc0-mud-sfx": ["mud"], "40-cc0-water-splash-slime-sfx": ["slime"],
    "steam-release-sounds": ["steam"], "retro-monster-roar": ["creature"], "mutant-frog": ["frog", "creature"],
    "squeaky-rat": ["goblin"], "horse-trotting": ["hooves"], "creepy-incoherent-chanting": ["m_chant"],
    "ghostly-humming": ["ghost", "f_hum"], "background-voices": ["crowd"], "do-you-remember-laughter": ["crowd"],
}
# Stormyman's monsters: monster -> categories; mood -> play / death.
ITCH_MONSTER = {"Dragon": ["dragon", "monster_big"], "Zombie": ["zombie"], "Skeleton": ["zombie"],
                "Witch": ["f_witch"], "Bat": ["bat", "goblin"], "Rat": ["goblin"], "Dracula": ["demon", "demon_laugh"],
                "Slime": ["slime"]}
DEATHY = re.compile(r"death|dying|die_|dyeing|hurt|pain|scream|cry|sob|wail|groan|moan|whimper|yelp|choke|gurgle|sad|scared|drown")
PLAYISH = re.compile(r"attack|grunt|growl|roar|bark|laugh|yell|taunt|warcry|battle|hum|sigh|snarl|hiss|neigh|snort|anger|triumph|chuckle|cackle|caw|call|effort|gasp|breath|chant|sing|choir|eat|burp|bellow|howl")
# The non-vocal categories never voice anyone on their own (they are layers).
LAYER_ONLY = {"wood_creak", "ship", "tree", "leaves", "stone", "harp", "chime", "shimmer", "whip", "chains", "mud",
              "bubbles", "ice", "fire", "steam", "horn", "coins", "sword", "hooves", "wave", "wind", "rumble", "sizzle",
              "page", "flute", "drum", "heart", "bite", "slurp", "wings"}


# Never used: words (the game has no speech), children, anything sexual, toys / cartoons / robots, and the
# non-vocal or animal recordings that a people search brought back. Matched on the file name, title and tags.
REJECT = re.compile(
    r"\b(help|hello|hey|yes|yeah|no|nope|okay|ok|say|says|saying|said|speech|speak|speaking|talk|talking|word|words|"
    r"phrase|sentence|count|counting|numbers?|dialog|dialogue|narrat\w*|voice ?over|voiceover|voice line|lines?|"
    r"fuck\w*|shit|bitch|damn|god|jesus|please|sorry|stop|c'mon|come on|lets|let's|gonna|wanna|what|why|who|where|"
    r"mom|dad|mama|papa|affirmative|negative|roger|germans|rich|diaper|punk|pretties|amazing|nice|cheers|"
    r"bravo|hooray|hurray|wow|ouch|ouchie|oops|i'm|im|don't|dont|il|ich|tu|vas|kid|kids|baby|babies|child|children|"
    r"toddler|little girl|young girl|boy|boys|infant|orgasm\w*|horny|sexy|sex|sexual|erotic|porn\w*|pleasure|"
    r"robot\w*|robotic|beep|ukulele|clock|handclap|clap|siren|steps|footsteps|paper|sofa|scratching|sms|meow\w*|"
    r"chicken|rhinoceros|monkey|fart\w*|splash|spade|kiss|duck|whistle|chord|vomit\w*|cartoon|clown|joker|"
    r"kamala|evp|alien|toy|laughing bag|level up|rpg heal|heal|drill sergeant|wedding|epiphany|tiffany|"
    r"vozhombre\w*|dance\d*|so dance\d*|flee|mujer llorando s)\b|\"|youandme|dorklaugh|mac_sms|ich_koennt|"
    r"spidefaht|il sait|to war")
REJECT_PACKS = {"background-voices", "group-giggling"}  # crowd talk; a giggling group no character needs
# Guns, vehicles, game UI and the like are never layered under a voice.
REJECT_NOISE = re.compile(r"\b(gun|guns|gunshot|gunfire|rifle|pistol|shotgun|ar15|ar-15|9mm|mg|cal|bullet|firearm|"
                          r"machine gun|assault|crossbow|camera|car|cars|train|airhorn|party|honk\w*|radio|electro\w*|"
                          r"electricity|ui|item|pickup|correct|error|teleport|portal|8-bit|powerup|kick|punch\w*|"
                          r"vinyl|trashcan|plastic|pressure plate|slot machine|jaw|jews|saw|dinosaur|stomach|"
                          r"planetary|ultrasound|bass|inception|chair|bed|unlocking|nose|channel|weapon|slice|"
                          r"stingers?|stabs?|gore|gut|swing|clarinet|chord|landing|energy|bisagra|nut|desert eagle|"
                          r"50ae|leg bells|synthetic|didgeridoo|piano|bonk|collision|dice|lasso|drums?|snare|"
                          r"wardrobe|ferris|scuttle|spider|metal gear|unpause|fuse|snapcracklepop|door|gate|"
                          r"staking|event\d*|playerhurt\d*|you will die|diiii\w*|yaaa\w*|dinner|405win|elaine|"
                          r"wiggle|rip|tear|flesh|dramatic horn|ambience|gallop|loop\w*|bowed|shot|shots|shooting|"
                          r"sneez\w*|trolley|sms\w*|husband|latin|emmanuelmarroncles\w*|gemid\w*|splatter|spiting|"
                          r"harp metal)\b")
FEMALE_TITLE = re.compile(r"\b(girl|girls|girly|woman|women|female|lady|ladies|she|her|mujer|femme|frau)\b")
MALE_TITLE = re.compile(r"\b(man|men|male|guy|guys|he|his|hombre|homme|mann)\b")
# A Freesound clip counts for an element only when its own title names it.
ELEMENT_WORDS = {
    "fire": r"fire|flame|burn|blaze|torch|lighter", "ice": r"ice|frost|freez|crack|glass", "wave": r"wave|sea|ocean|surf",
    "wind": r"wind|storm|gale|myrsky|whirl|tornado", "rumble": r"rumbl|thunder|earthquake", "stone": r"stone|rock|piedra|stein|boulder",
    "wood_creak": r"creak", "ship": r"creak|rope|ship|boat", "tree": r"tree|branch|twig|kvist|snap",
    "leaves": r"leaves|rustle|bush|reed", "harp": r"harp|lyre", "chime": r"chime|bell|ding", "shimmer": r"shimmer|sparkle",
    "whip": r"whip", "chains": r"chain", "mud": r"mud|squelch|swamp|bog", "bubbles": r"bubbl|gurgl",
    "steam": r"steam|hiss|boil", "horn": r"horn", "coins": r"coin|money", "sword": r"sword|blade|unsheath",
    "hooves": r"hoof|hooves|gallop|horse", "sizzle": r"sizzl|acid|extinguish|hiss", "page": r"page|book",
    "flute": r"flute", "drum": r"drum|wood block", "heart": r"heart", "bite": r"bite|crunch|nom|chew|munch",
    "slurp": r"slurp|sip|swallow|drink", "wings": r"wing|flap", "insect": r"bee|wasp|fly|flies|buzz|insect|beetle|hornet",
    # animals and creatures: the title must name the beast (searches return plenty of other things)
    "dog_bark": r"dog|bark|hound", "dog_growl": r"dog|growl|snarl|hound", "dog_yelp": r"dog|yelp|whine|whimper|puppy",
    "dog_pup": r"pupp|pup\b|dog", "wolf_howl": r"wolf|lobo|howl", "wolf_growl": r"wolf|lobo",
    "lion": r"lion", "big_cat": r"tiger|jaguar|leopard|panther|cougar|puma|lynx", "cat_hiss": r"hiss|cat",
    "horse_neigh": r"neigh|whinny|mule|cavall|horse$|^horse\b(?!.*gallop)", "horse_snort": r"snort",
    "bull": r"bull|cow|moo|cattle|bison|bovine|bellow|yak", "pig": r"pig|oink|hog|boar|swine",
    "snake": r"snake|serpent|reptile|cobra|viper|rattle|hiss", "crow": r"crow|raven|caw|squawk", "owl": r"owl|hoot",
    "raptor": r"hawk|eagle|falcon|vulture|aguila", "bat": r"\bbat\b|screech", "gull": r"gull", "goat": r"goat|sheep|baa|bleat|ewe",
    "camel": r"camel", "elephant": r"elephant|mastodon", "bear": r"bear", "ape": r"\bape|gorilla|chimp", "frog": r"frog|croak|toad",
    "bird": r"bird|parrot|swan|rooster|peacock",
    "creature": r"monster|creature|beast|roar|growl|snarl|ogre|troll", "monster_big": r"monster|creature|beast|roar|ogre|troll|giant|minotaur",
    "giant": r"giant|monster|roar", "dragon": r"dragon|drag[oó]n", "demon": r"demon|devil|hell|monster|growl",
    "demon_laugh": r"laugh|cackle|muahaha", "goblin": r"goblin|imp\b|imp ", "monster_death": r"monster|creature|beast|death|dying|die\b",
    "monster_scream": r"scream|screech|shriek", "zombie": r"zombie|groan|undead|ghoul|moan|hellpig",
    "ghost": r"ghost|spectral|banshee|wail|moan|haunt|spirit|phantom|wooo", "whisper": r"whisper|shh|breath",
    "choir": r"choir|vox|chant|choral|singing|angel", "choir_m": r"choir|vox|om\b|chant", "crowd": r"crowd|group|mob|people",
}


def tag_clip(pack: str, rel: str, meta: dict) -> tuple:
    text = " ".join([pack, rel.replace("\\", "/").replace("_", " ") + " " + rel, meta.get("title", ""),
                     " ".join(meta.get("tags", [])), " ".join(meta.get("tags_query", []))]).lower()
    if pack in REJECT_PACKS or REJECT.search(os.path.basename(rel).lower().replace("_", " ")):
        return [], text
    if pack.startswith("fs-"):
        # Freesound titles and tags describe the content: anything off the list above is never used, and an
        # ambiguous "moan" from a woman is kept only when its tags say pain.
        said = " ".join([meta.get("title", ""), " ".join(meta.get("tags", []))]).lower().replace("_", " ")
        if REJECT.search(said):
            return [], text
        if "female_pain" in meta.get("tags_query", []) and "moan" in said and not re.search(r"pain|hurt|injur|wound", said):
            return [], text
    cats = []
    if pack.startswith("fs-"):
        title = meta.get("title", "").lower().replace("_", " ")
        if REJECT_NOISE.search(title):
            return [], text
        for t in meta.get("tags_query", []):
            for c in QUERY_CATS.get(t, []):
                if c in ELEMENT_WORDS and not re.search(ELEMENT_WORDS[c], title):
                    continue  # e.g. a gunshot that a "fire burst" search returned
                if c.startswith("m_") and FEMALE_TITLE.search(title) or c.startswith("f_") and MALE_TITLE.search(title):
                    continue  # the title says the other voice
                cats.append(c)
    elif pack == "itch-goofy-scary-monsters":
        mon = rel.replace("\\", "/").split("/")[1] if "/" in rel.replace("\\", "/") else ""
        if mon not in ITCH_MONSTER:
            return [], text  # the clown, cashier and narrator do not fit the game
        cats += ITCH_MONSTER[mon]
    else:
        cats += PACK_CATS.get(pack, [])
    base = list(cats)
    if not pack.startswith("fs-"):
        for rx, cs in RULES:
            if re.search(rx, text):
                cats += cs
    # A creature pack's "yell" or "laugh" is still the creature's: no person categories from its file names.
    if base and not any(is_person(c) for c in base):
        cats = [c for c in cats if not is_person(c)]
    # A person or an animal is never a generic "creature" because its file says growl or death.
    if any(is_person(c) or c in ANIMAL for c in cats):
        cats = [c for c in cats if c not in ("creature", "monster_death", "monster_scream") or c in base]
    if any(c in ("creature", "monster_big", "zombie", "demon", "goblin", "ghost", "dragon", "slime") for c in cats) \
            and DEATHY.search(text) and "monster_death" not in cats and not any(is_person(c) for c in base):
        cats.append("monster_death")
    seen = []
    for c in cats:
        if c not in seen:
            seen.append(c)
    return seen, text


ANIMAL = {"dog_bark", "dog_growl", "dog_yelp", "dog_pup", "wolf_howl", "wolf_growl", "lion", "big_cat", "cat_hiss",
          "horse_neigh", "horse_snort", "bull", "pig", "snake", "crow", "owl", "raptor", "bat", "gull", "goat", "camel",
          "elephant", "bear", "ape", "frog", "bird"}


def is_person(c: str) -> bool:
    return c.startswith("m_") or c.startswith("f_")


def scan_files(src: str) -> list:
    """(pack slug, file path relative to the pack, meta) for every audio file; one file per sound (a pack's wav /
    ogg / mp3 copies of the same sound count once, the best format kept); never the macOS resource forks."""
    out = []
    best = {".wav": 0, ".flac": 0, ".aif": 1, ".aiff": 1, ".ogg": 2, ".mp3": 3}
    for top in sorted(os.listdir(src)):
        d = os.path.join(src, top)
        if not os.path.isdir(d):
            continue
        packs = [os.path.join(d, p) for p in sorted(os.listdir(d))] if top == "freesound" else [d]
        for pd in packs:
            mp = os.path.join(pd, "meta.json")
            if not os.path.exists(mp):
                continue
            meta = json.load(open(mp, encoding="utf-8"))
            lic = meta.get("license", [])
            if "CC0" not in lic and "PD" not in lic:
                continue
            slug = meta.get("slug", os.path.basename(pd))
            stems = {}
            for dp, dn, fn in os.walk(pd):
                if "__MACOSX" in dp:
                    continue
                for f in fn:
                    ext = os.path.splitext(f)[1].lower()
                    if ext not in AUDIO_EXT or f.startswith("._"):
                        continue
                    rel = os.path.relpath(os.path.join(dp, f), pd)
                    stem = os.path.splitext(f)[0].lower()
                    if stem not in stems or best[ext] < best[os.path.splitext(stems[stem])[1].lower()]:
                        stems[stem] = rel
            comp = re.compile(r"all[_ -]?mix|_all$|compilation|full[_ -]?pack")
            for rel in sorted(stems.values()):
                if len(stems) > 3 and comp.search(os.path.splitext(os.path.basename(rel))[0].lower()):
                    continue  # a compilation of the pack's single files
                out.append((slug, os.path.relpath(pd, src), rel, meta))
    return out


def shape(y: "np.ndarray", sr: int) -> "np.ndarray":
    """A small level-independent picture of a segment (band profile + envelope) to spot the same recording twice."""
    n, hop = 512, 160
    fr = frames(y, n, hop) * np.hanning(n)[None, :]
    spec = np.abs(np.fft.rfft(fr, axis=1)) ** 2 + 1e-10
    freqs = np.fft.rfftfreq(n, 1.0 / sr)
    edges = np.geomspace(80, 5000, 13)  # under an mp3's cut-off, so an mp3 and a flac of one sound look the same
    bands = np.log10(np.array([spec[:, (freqs >= edges[i]) & (freqs < edges[i + 1])].sum(1).mean() for i in range(12)]))
    bands -= bands.mean()
    rms = np.sqrt(spec.sum(1))
    env = np.array([s.mean() for s in np.array_split(rms, 10)])
    env /= env.max() + 1e-9
    return np.concatenate([bands, env * 2.0])


def same_sound(v: "np.ndarray", dur: float, seen: list) -> bool:
    for d, w in seen:
        if abs(d - dur) <= 0.12 * max(d, dur) and float(np.sqrt(((v - w) ** 2).sum())) < 0.8:
            return True
    return False


def cmd_pool(a) -> None:
    files = scan_files(a.src)
    # single files before compilations ("all_mix"), so a compilation's segments are the duplicates that get dropped
    files.sort(key=lambda f: (f[0], "mix" in f[2].lower() or "all" in os.path.basename(f[2]).lower(), f[2]))
    packs, clips, shapes = {}, [], []
    for i, (slug, pdir, rel, meta) in enumerate(files):
        packs[slug] = {"title": meta.get("title", slug), "author": meta.get("author", "?"),
                       "license": meta.get("license", []), "url": meta.get("url", ""), "dir": pdir.replace("\\", "/")}
        cats, text = tag_clip(slug, rel, meta)
        if not cats:
            continue
        path = os.path.join(a.src, pdir, rel)
        try:
            x = decode(path)
        except subprocess.CalledProcessError:
            print("  cannot decode", path)
            continue
        if len(x) < 1600:
            continue
        segs = segments(x, 16000)[:14]
        for k, (t0, t1) in enumerate(segs):
            y = x[int(t0 * 16000): int(t1 * 16000)]
            f = features(y, 16000)
            if f["peak_db"] < -40:
                continue
            v = shape(y, 16000)
            if same_sound(v, t1 - t0, shapes):
                continue  # the same recording again (a pack's mp3 and flac of one sound, a compilation, a re-upload)
            shapes.append((t1 - t0, v))
            kind = "both"
            if DEATHY.search(text) and not PLAYISH.search(text):
                kind = "death"
            elif PLAYISH.search(text) and not DEATHY.search(text):
                kind = "play"
            cid = hashlib.sha1(("%s/%s#%d" % (slug, rel, k)).encode("utf-8")).hexdigest()[:10]
            clips.append(dict({"id": cid, "pack": slug, "file": rel.replace("\\", "/"), "seg": k, "t0": t0,
                               "dur": round(t1 - t0, 3), "cats": cats, "kind": kind,
                               "name": os.path.splitext(os.path.basename(rel))[0][:60]}, **f))
        if i % 50 == 0:
            print("%d/%d files, %d clips" % (i, len(files), len(clips)))
    os.makedirs(os.path.dirname(POOL), exist_ok=True)
    json.dump({"src_hint": "voices_src (downloaded packs, see each pack's meta.json)", "packs": packs, "clips": clips},
              open(POOL, "w", encoding="utf-8"), indent=0, ensure_ascii=False)
    count = {}
    for c in clips:
        for k in c["cats"]:
            count[k] = count.get(k, 0) + 1
    print("pool: %d clips from %d files, %d packs" % (len(clips), len(files), len(packs)))
    print(", ".join("%s %d" % kv for kv in sorted(count.items())))


# ====================================================================== characters and archetypes

CIRCLE_SCHOOL = {  # scripts/battle/vfx_data.gd CIRCLE_SCHOOL
    "dark_wood": "thorn", "ante_inferno": "holy", "limbo": "soul", "lust": "wind", "gluttony": "water",
    "greed": "gold", "wrath": "blood", "heresy": "fire", "dis": "shadow", "violence": "fire",
    "malebolge": "pitch", "cocytus": "ice",
}
# The quiet element layer per school: sound names in assets/audio/sfx (already in the game, CC0, credited) or
# "pool:<category>" for a clip from the voice pool.
SCHOOL_LAYER = {
    "fire": ["spell_fire", "pool:fire"], "ice": ["ice", "glass", "pool:ice"], "water": ["splash", "pool:wave"],
    "soul": ["wail", "sigh"], "shadow": ["whoosh", "gust"], "wind": ["gust", "pool:wind"],
    "blood": ["splash", "pool:mud"], "stone": ["rubble"], "gold": ["coins", "coin_pouch"], "word": ["page"],
    "thorn": ["pool:leaves", "pool:tree", "bones"], "pitch": ["pool:bubbles", "pool:mud", "pool:sizzle"],
    "venom": ["pool:snake", "pool:sizzle"], "holy": ["magic", "pool:chime", "pool:shimmer"],
    "judgment": ["bell_far", "chain"],
}
# room presets: ffmpeg aecho in_gain:out_gain:delays:decays
ROOMS = {
    "dry": None,
    "room": "0.9:0.6:28|47:0.22|0.12",
    "stone": "0.9:0.55:45|80|125:0.25|0.16|0.08",
    "hall": "0.85:0.6:70|130|190:0.3|0.2|0.12",
    "cave": "0.85:0.55:95|170|260:0.34|0.24|0.14",
    "ether": "0.8:0.6:120|230|350|470:0.38|0.3|0.2|0.12",
}
P, D = "play", "death"
# name: play / death categories (best first), pitch range in semitones, formant (preserved = the same person, only
# higher or lower; shifted = the body grows or shrinks), room, extra fx, f0 range that fits the voice (Hz),
# optional second layer per slot ("with_play" / "with_death": categories, gain dB, pitch, delay s), group size.
ARCH = {
    "man": dict(play=["m_grunt", "m_hmph", "m_laugh", "m_yell", "m_breath", "m_sigh", "m_growl"],
                death=["m_death", "m_pain"], pitch=(-2.0, 1.5), formant="preserved", room="room", f0=(70, 260)),
    "man_young": dict(play=["m_young", "m_yell", "m_laugh", "m_grunt", "m_hmph"], death=["m_death", "m_pain"],
                      pitch=(0.5, 3.0), formant="preserved", room="room", f0=(90, 320)),
    "man_old": dict(play=["m_old", "m_cough", "m_sigh", "m_hum", "m_hmph", "m_laugh"],
                    death=["m_old", "m_pain", "m_death", "m_sigh"], pitch=(-3.0, 0.0), formant="preserved",
                    room="room", fx=["vibrato"], f0=(60, 240)),
    "warrior": dict(play=["m_warcry", "m_yell", "m_grunt", "m_growl"], death=["m_death", "m_pain"],
                    pitch=(-3.0, 0.5), formant="preserved", room="hall", f0=(70, 280)),
    "king": dict(play=["m_laugh", "m_hmph", "m_warcry", "m_hum", "m_laugh_evil"], death=["m_death", "m_pain"],
                 pitch=(-3.0, 0.0), formant="preserved", room="hall", f0=(60, 240)),
    "scholar": dict(play=["m_hum", "m_hmph", "m_sigh", "m_laugh", "m_cough"], death=["m_sigh", "m_pain", "m_death"],
                    pitch=(-1.5, 1.5), formant="preserved", room="stone", f0=(70, 260)),
    "cleric": dict(play=["m_chant", "choir_m", "m_hum", "m_hmph"], death=["m_pain", "m_old", "m_death"],
                   pitch=(-3.0, 0.0), formant="preserved", room="hall", f0=(60, 260)),
    "glutton": dict(play=["m_eat", "m_grunt", "m_breath"], death=["m_choke", "m_pain", "m_death"],
                    pitch=(-3.0, 0.0), formant="preserved", room="room", f0=(60, 240)),
    "brawler": dict(play=["m_growl", "m_yell", "m_grunt", "m_warcry"], death=["m_pain", "m_death"],
                    pitch=(-2.5, 1.0), formant="preserved", room="room", f0=(70, 300)),
    "mud_sinner": dict(play=["m_choke", "m_growl", "m_grunt"], death=["m_choke", "m_death", "m_pain"],
                       pitch=(-3.0, 0.0), formant="preserved", room="room", layer="pool:mud", f0=(60, 280)),
    "trickster": dict(play=["m_laugh_evil", "m_laugh", "m_hmph"], death=["m_pain", "m_death"],
                      pitch=(-1.5, 2.0), formant="preserved", room="room", f0=(70, 320)),
    "madman": dict(play=["m_laugh_evil", "m_yell", "m_growl"], death=["m_death", "m_pain"],
                   pitch=(-2.0, 1.5), formant="preserved", room="stone", f0=(70, 340)),
    "damned": dict(play=["zombie", "m_pain", "m_grunt", "m_breath"], death=["m_death", "zombie", "m_pain"],
                   pitch=(-2.5, 1.0), formant="preserved", room="stone", f0=(60, 300)),
    "sailor": dict(play=["m_grunt", "m_yell", "m_warcry", "m_hmph"], death=["m_death", "m_pain"],
                   pitch=(-2.0, 1.5), formant="preserved", room="room", layer="pool:wave", f0=(70, 280)),
    "crowd_m": dict(play=["m_grunt", "m_yell", "m_warcry", "m_growl", "m_laugh"], death=["m_death", "m_pain"],
                    pitch=(-2.0, 1.5), formant="preserved", room="stone", group=3, f0=(60, 300)),
    "woman": dict(play=["f_sigh", "f_gasp", "f_hum", "f_laugh", "f_breath"], death=["f_death", "f_cry", "f_pain", "f_scream"],
                  pitch=(-1.5, 1.5), formant="preserved", room="room", f0=(150, 600)),
    "queen": dict(play=["f_laugh", "f_hum", "f_sigh", "f_gasp"], death=["f_cry", "f_death", "f_pain", "f_sigh"],
                  pitch=(-2.0, 0.5), formant="preserved", room="hall", f0=(140, 600)),
    "witch": dict(play=["f_witch", "f_laugh"], death=["f_scream", "f_death", "f_pain"], pitch=(-2.0, 1.0),
                  formant="preserved", room="stone", f0=(130, 900)),
    "siren": dict(play=["f_sing", "f_hum", "f_sigh"], death=["f_sing", "f_cry", "f_sigh"], pitch=(-1.0, 2.0),
                  formant="preserved", room="ether", f0=(150, 1000)),
    "warrior_woman": dict(play=["f_grunt", "f_scream", "f_gasp"], death=["f_pain", "f_death", "f_scream"],
                          pitch=(-1.5, 1.0), formant="preserved", room="hall", f0=(140, 700)),
    "furies": dict(play=["f_scream", "f_witch"], death=["f_scream", "f_death", "f_pain"], pitch=(-2.0, 2.0),
                   formant="preserved", room="cave", group=3, f0=(130, 1100)),
    "harpy": dict(play=["f_scream", "raptor", "bat", "f_witch"], death=["raptor", "f_scream", "f_death"],
                  pitch=(0.0, 3.0), formant="shifted", room="stone", layer="pool:wings"),
    "medusa": dict(play=["f_witch", "f_sigh", "f_gasp"], death=["f_scream", "f_death"], pitch=(-2.0, 0.0),
                   formant="preserved", room="stone", with_play=(["snake"], -4.0, 0.0, 0.0),
                   with_death=(["snake"], -6.0, -2.0, 0.1), f0=(130, 900)),
    "demon": dict(play=["demon", "demon_laugh", "creature", "goblin"], death=["monster_death", "creature", "demon"],
                  pitch=(-4.0, 1.0), formant="shifted", room="cave"),
    "imp": dict(play=["goblin", "creature", "bat", "demon_laugh"], death=["monster_death", "goblin", "creature"],
                pitch=(1.0, 5.0), formant="shifted", room="stone"),
    "demon_lord": dict(play=["monster_big", "demon", "demon_laugh", "dragon"], death=["monster_death", "monster_big"],
                       pitch=(-6.0, -2.0), formant="shifted", room="cave"),
    "giant": dict(play=["giant", "monster_big", "creature"], death=["monster_death", "monster_big", "giant"],
                  pitch=(-8.0, -3.0), formant="shifted", room="hall"),
    "giant_man": dict(play=["m_grunt", "m_yell", "m_warcry", "m_growl"], death=["m_death", "m_pain"],
                      pitch=(-9.0, -5.0), formant="shifted", room="hall", with_play=(["monster_big"], -9.0, -3.0, 0.0)),
    "shade": dict(play=["ghost", "whisper", "ghost_breath", "m_sigh", "f_sigh"], death=["ghost", "m_sigh", "f_sigh", "whisper"],
                  pitch=(-3.0, 2.0), formant="preserved", room="ether", fx=["chorus", "soft"]),
    "shade_angry": dict(play=["zombie", "ghost", "m_growl"], death=["zombie", "ghost", "monster_death"],
                        pitch=(-3.0, 1.0), formant="preserved", room="cave", fx=["soft"]),
    "mud_creature": dict(play=["slime", "creature", "zombie"], death=["slime", "monster_death", "zombie"],
                         pitch=(-5.0, -1.0), formant="shifted", room="room", layer="pool:mud"),
    "dog": dict(play=["dog_bark", "dog_growl"], death=["dog_yelp", "dog_growl"], pitch=(-2.0, 2.0),
                formant="shifted", room="room"),
    "hellhound": dict(play=["dog_growl", "dog_bark"], death=["dog_yelp", "dog_growl"], pitch=(-6.0, -2.0),
                      formant="shifted", room="cave", with_play=(["creature", "demon"], -8.0, -3.0, 0.0)),
    "wolf": dict(play=["wolf_growl", "wolf_howl", "dog_growl"], death=["dog_yelp", "wolf_howl", "dog_growl"],
                 pitch=(-2.0, 1.0), formant="shifted", room="stone"),
    "lion": dict(play=["lion", "big_cat"], death=["lion", "big_cat", "bear"], pitch=(-2.0, 1.0), formant="shifted",
                 room="stone"),
    "leopard": dict(play=["big_cat", "cat_hiss", "lion"], death=["big_cat", "cat_hiss", "lion"], pitch=(0.0, 3.0),
                    formant="shifted", room="room"),
    "horse": dict(play=["horse_neigh", "horse_snort"], death=["horse_neigh", "horse_snort"], pitch=(-2.0, 1.0),
                  formant="shifted", room="room"),
    "centaur": dict(play=["horse_neigh", "horse_snort"], death=["horse_neigh", "horse_snort"], pitch=(-2.0, 1.0),
                    formant="shifted", room="stone", with_play=(["m_warcry", "m_yell", "m_grunt"], -3.0, -1.0, 0.05),
                    with_death=(["m_death", "m_pain"], -2.0, -1.0, 0.0)),
    "bull": dict(play=["bull", "monster_big"], death=["bull", "monster_death"], pitch=(-4.0, -1.0), formant="shifted",
                 room="cave"),
    "serpent": dict(play=["snake"], death=["snake"], pitch=(-3.0, 2.0), formant="shifted", room="stone"),
    "serpent_man": dict(play=["m_pain", "m_grunt", "m_growl"], death=["m_death", "m_pain"], pitch=(-2.0, 1.0),
                        formant="preserved", room="stone", with_play=(["snake"], -3.0, 0.0, 0.08),
                        with_death=(["snake"], -3.0, -2.0, 0.15)),
    "pig": dict(play=["pig"], death=["pig"], pitch=(-1.0, 2.0), formant="shifted", room="room"),
    "bird_fire": dict(play=["raptor", "bird", "crow"], death=["raptor", "bird", "crow"], pitch=(-1.0, 2.0),
                      formant="shifted", room="hall", layer="pool:fire"),
    "dragon_beast": dict(play=["dragon", "monster_big"], death=["monster_death", "dragon"], pitch=(-5.0, -1.0),
                         formant="shifted", room="cave", layer="pool:wings"),
    "angel": dict(play=["choir", "f_sing", "choir_m"], death=["choir", "f_sing", "ghost"], pitch=(-1.0, 2.0),
                  formant="preserved", room="ether", layer="pool:shimmer"),
    "fallen_angel": dict(play=["choir_m", "choir", "m_hum"], death=["ghost", "choir_m", "m_sigh"], pitch=(-5.0, -2.0),
                         formant="shifted", room="cave", layer="pool:wings"),
}
DEFAULT_LEN = {P: (0.4, 1.2), D: (0.5, 1.5)}  # seconds, the echo tail included


def school_of(card: dict, vfx: dict) -> str:
    return vfx.get(card["id"], {}).get("school", CIRCLE_SCHOOL.get(card.get("circle", ""), "fire"))


def characters() -> list:
    cards = json.load(open(os.path.join(ROOT, "data", "cards.json"), encoding="utf-8"))
    allc = list(cards["cards"])
    for f in sorted(glob.glob(os.path.join(ROOT, "data", "sets", "*.json"))):
        allc += json.load(open(f, encoding="utf-8"))["cards"]
    vfx = json.load(open(os.path.join(ROOT, "data", "vfx.json"), encoding="utf-8"))["cards"]
    out = []
    for h in cards["heroes"]:
        out.append({"id": h["id"], "kind": "hero", "name": h["name"], "rarity": "hero", "cost": 10,
                    "text": (h["name"] + " " + h.get("class_style", "")).lower(), "school": "", "keywords": [],
                    "set": h["class"], "circle": ""})
    for c in allc:
        if c.get("type") != "minion":
            continue
        out.append({"id": c["id"], "kind": "minion", "name": c["name"], "rarity": c.get("rarity", "common"),
                    "cost": int(c.get("cost", 1)), "keywords": c.get("keywords", []), "set": c.get("set", ""),
                    "circle": c.get("circle", ""), "school": school_of(c, vfx),
                    "text": " ".join([c["name"], c.get("art", ""), c.get("flavor", "")]).lower()})
    return out


def has(t: str, words: str) -> bool:
    return re.search(r"\b(%s)" % words, t) is not None


DEMON_NAMES = ("calcabrina|barbariccia|farfarello|cagnazzo|draghignazzo|graffiacane|libicocco|scarmiglione|"
               "rubicante|malacoda")


def auto_archetype(ch: dict) -> str:
    """The archetype from the card's own words (name first, then art prompt and flavour)."""
    n, t = ch["name"].lower(), ch["text"]
    if has(n, "harp"):
        return "harpy"
    if has(n, "furies"):
        return "furies"
    if has(t, "centaur"):
        return "centaur"
    if has(n, "serpent|snake"):
        return "serpent"
    if has(t, "turning into|merging with|twisting into|turn into|became a serpent|wrapped in serpent|serpent coils"):
        return "serpent_man"
    if has(n, "hellhound|cerberus"):
        return "hellhound"
    if has(n, "hound|greyhound|dog|pup\\b"):
        return "dog"
    if has(n, "angel|messenger"):
        return "fallen_angel" if has(t, "fallen") else "angel"
    if has(t, "demon|imp\\b|devil|cherub") or has(n, DEMON_NAMES):
        if ch["rarity"] == "legendary" or has(t, "chief|large horned"):
            return "demon_lord"
        if ch["cost"] <= 1 or has(t, "small|imp\\b"):
            return "imp"
        return "demon"
    if has(n, "giant|colossus|briareus|antaeus|nimrod|typhon|ephialtes"):
        return "mud_creature" if has(t, "mud") else "giant"
    if has(n, "wolf"):
        return "wolf"
    if has(n, "lion"):
        return "lion"
    if has(n, "leopard"):
        return "leopard"
    if has(n, "horse"):
        return "horse"
    if has(n, "swine|pig"):
        return "pig"
    if has(n, "phoenix"):
        return "bird_fire"
    if has(n, "minotaur|bull"):
        return "bull"
    if has(n, "mud dweller|mud soul|mire hulk|colossus"):
        return "mud_creature"
    female = has(t, "woman|women|queen|she\\b|her\\b|maiden|princess|siren|sorceress|witch|wife|mother|amazon|"
                    "francesca|beatrice|camilla|electra|dido|helen|cleopatra|semiramis|tha.s|circe|medusa|deidamia|"
                    "penthesilea|erichtho|noblewoman")
    if female and not has(n, "paolo|brothers|jason|venedico|tristan|achilles|hector|ulysses|filippo|dante|tydeus"):
        if has(t, "witch|sorceress|enchantress|medusa"):
            return "medusa" if has(t, "serpents for hair") else "witch"
        if has(t, "siren|sings|heaven|serene|white gown"):
            return "siren"
        if has(t, "amazon|warrior woman|bow sprinting|with a bow|spear"):
            return "warrior_woman"
        if has(t, "queen|princess|crown|noblewoman"):
            return "queen"
        return "woman"
    if has(n, "shade|soul|souls") or has(t, "ghostly|translucent|ghost"):
        if has(t, "angry|rage|wrath|hatred|fist|strikes|biting") or ch["set"] == "wrath":
            return "shade_angry"
        return "shade"
    if has(t, "mud|swamp|black water|choke|gurgle"):
        return "mud_sinner" if not has(t, "fist|brawl|fight|wrestl|punch|shove|roar") else "brawler"
    if has(n, "philosophers|pagans|companions|oarsmen|friars|mob|throng|brothers|sullen|crowd"):
        return "crowd_m"
    if has(t, "pope|bishop|friar|monk|mitre"):
        return "cleric"
    if has(t, "glutton|belly|swollen|bloated|gorged|cup up to his mouth"):
        return "glutton"
    if has(t, "sailor|oars|ship|galley|sea\\b"):
        return "sailor"
    if has(t, "mad\\b|maddened|wild-eyed|grinning"):
        return "madman"
    if has(t, "old|elderly|white-haired|grey-bearded|aged|seer|augur|blind|bald old"):
        return "man_old"
    if has(t, "fist|brawl|fight|wrestl|punch|shove|thug|furious|rage|roaring|swagger") or ch["set"] == "wrath":
        return "brawler"
    if has(t, "king|emperor|sultan|crowned|general|tyrant|ruler|lord|captain"):
        return "king"
    if has(t, "knight|warrior|soldier|sword|commander|armou?r|conqueror|warlord|spear|charges"):
        return "warrior"
    if has(t, "thief|liar|lie|flatter|forged|trick|fraud|hypocrit|sly|barrator|usurer|coins|purse|sold"):
        return "trickster"
    if has(t, "poet|scholar|scroll|book|astrolabe|sorcerer|alchemist|teacher|grammarian|jurist|philosopher"):
        return "scholar"
    if has(t, "young|youth|boy"):
        return "man_young"
    if has(t, "sinner|naked|tar\\b|pitch|boiling|burning|frozen|ice|nailed|wound|stumps|severed"):
        return "damned"
    return "man"


def load_overrides() -> dict:
    if not os.path.exists(OVERRIDES):
        return {}
    return json.load(open(OVERRIDES, encoding="utf-8")).get("characters", {})


def spec_for(ch: dict, ov: dict) -> dict:
    """The character's archetype spec: ARCH[arch] with the hand override's fields on top."""
    o = ov.get(ch["id"], {})
    arch = o.get("arch") or auto_archetype(ch)
    if arch not in ARCH:
        raise SystemExit("%s: unknown archetype %s" % (ch["id"], arch))
    s = dict(ARCH[arch])
    for k, v in o.items():
        if k not in ("arch", "note"):
            s[k] = v
    s["arch"] = arch
    s["custom"] = bool(o)
    s["note"] = o.get("note", "")
    return s


# ====================================================================== selection

ORDER = {"hero": 0, "legendary": 1, "epic": 2, "rare": 3, "common": 4, "token": 5}
FEMALE_ARCH = {"woman", "queen", "witch", "siren", "warrior_woman", "furies", "medusa"}


class Picker:
    def __init__(self, pool: dict):
        self.clips = pool["clips"]
        self.packs = pool["packs"]
        self.by_cat = {}
        for c in self.clips:
            for k in c["cats"]:
                self.by_cat.setdefault(k, []).append(c)
        self.uses = {}      # clip id -> number of characters it voices
        self.pitches = {}   # clip id -> pitches it was used at

    def pick(self, who: str, slot: str, cats: list, spec: dict, avoid: set, kind: str = "",
             layer: bool = False) -> dict:
        best, best_s = None, -1e9
        f0r = spec.get("f0")
        female = spec["arch"] in FEMALE_ARCH
        male = spec.get("formant") == "preserved" and not female and spec["arch"] not in ("shade", "angel", "siren")
        for rank, cat in enumerate(cats):
            for c in self.by_cat.get(cat, []):
                if c["id"] in avoid:
                    continue
                s = 3.0 - 0.45 * rank
                if kind and c["kind"] not in (kind, "both"):
                    s -= 1.2
                d = c["dur"]
                lo = 0.35 if slot.startswith(P) else 0.45
                if d < lo:
                    s -= 1.5 * (lo - d) / lo + 0.4
                if d > 4.5:
                    s -= 0.4
                if c["peak_db"] < -24:
                    s -= 0.5
                if not layer and c["voiced"] >= 0.45 and c["f0"] > 0:
                    if f0r and not (f0r[0] * 0.8 <= c["f0"] <= f0r[1] * 1.25):
                        s -= 1.0
                    if female and c["f0"] < 145:
                        s -= 2.5
                    if male and c["f0"] > 330 and not cat.startswith("m_young"):
                        s -= 1.5
                u = self.uses.get(c["id"], 0)
                s -= (0.6 if layer else 2.6) * u
                s += 0.9 * h01(who, slot, c["id"])
                if s > best_s:
                    best, best_s = c, s
        if best is None and avoid:  # every fitting clip is already in this character: a layer may repeat one
            return self.pick(who, slot, cats, spec, set(), kind, layer)
        if best is None:
            raise SystemExit("%s %s: no clip in %s" % (who, slot, cats))
        self.uses[best["id"]] = self.uses.get(best["id"], 0) + 1
        return best


def sfx_variant(name: str, r: random.Random) -> str:
    files = sorted(glob.glob(os.path.join(SFX, name + "_[0-9].*")) + glob.glob(os.path.join(SFX, name + ".ogg")))
    files = [f for f in files if not f.endswith(".import")]
    return r.choice(files) if files else ""


def fit_pitch(p: float, clip: dict, spec: dict) -> float:
    """Keep a person's voice inside the archetype's pitch range (a high grunt goes down for a big man)."""
    f0r = spec.get("f0")
    if not f0r or clip["f0"] <= 0 or clip["voiced"] < 0.45 or spec.get("formant") != "preserved":
        return p
    f = clip["f0"] * 2 ** (p / 12.0)
    if f < f0r[0]:
        p += 12 * math.log2(f0r[0] / f)
    elif f > f0r[1]:
        p -= 12 * math.log2(f / f0r[1])
    return max(-6.0, min(6.0, p))


def plan_slot(ch: dict, spec: dict, slot: str, pk: Picker, avoid: set) -> dict:
    """One output (play or death): its voice layers, element layers and treatment, all from the card's dice."""
    r = rng_for(ch["id"], slot)
    cats = spec.get(slot, ARCH[spec["arch"]][slot])
    main = pk.pick(ch["id"], slot, cats, spec, avoid, kind=slot)
    avoid.add(main["id"])
    lo, hi = spec["pitch"]
    p = lo + (hi - lo) * r.random()
    if ch["kind"] == "minion":
        p += max(-1.0, min(1.0, -0.22 * (ch["cost"] - 4)))
        if "guard" in ch["keywords"]:
            p -= 0.4
    p = fit_pitch(p, main, spec)
    for q in pk.pitches.get(main["id"], []):  # a shared clip is never at a similar pitch twice
        if abs(q - p) < 2.5:
            p = q + (2.5 if p >= q else -2.5) * (1 if abs(q + 2.5) < 9 else -1)
    pk.pitches.setdefault(main["id"], []).append(round(p, 2))
    tempo = 0.94 + 0.12 * r.random()
    if "swift" in ch["keywords"]:
        tempo += 0.05
    if "guard" in ch["keywords"]:
        tempo -= 0.03
    voices = [dict(clip=main["id"], pitch=round(p, 2), tempo=round(tempo, 3), gain=0.0, delay=0.0,
                   formant=spec["formant"])]
    for g in range(1, int(spec.get("group", 1))):
        c = pk.pick(ch["id"], slot + "#%d" % g, cats, spec, avoid, kind=slot)
        avoid.add(c["id"])
        gp = fit_pitch(p + r.choice([-1, 1]) * (2.0 + 2.0 * r.random()), c, spec)
        voices.append(dict(clip=c["id"], pitch=round(gp, 2), tempo=round(tempo * (0.95 + 0.1 * r.random()), 3),
                           gain=round(-2.5 - 2.5 * r.random(), 1), delay=round(0.05 + 0.08 * g * r.random() + 0.04 * g, 3),
                           formant=spec["formant"]))
    w = spec.get("with_" + slot)
    if w:
        c = pk.pick(ch["id"], slot + "+with", w[0], spec, avoid, layer=True)
        avoid.add(c["id"])
        voices.append(dict(clip=c["id"], pitch=round(w[2] + (r.random() - 0.5), 2), tempo=round(tempo, 3),
                           gain=float(w[1]), delay=float(w[3]), formant="shifted"))
    layers = []
    al = spec.get("layer_" + slot, spec.get("layer"))
    if al:
        layers.append(_layer(ch, slot + "+arch", al, r, pk, avoid, -8.0 - 3.0 * r.random()))
    big = ch["rarity"] in ("legendary", "epic", "hero")
    if ch.get("school") and r.random() < (0.95 if big else (0.55 if slot == P else 0.4)) and not spec.get("no_school"):
        opts = SCHOOL_LAYER.get(ch["school"], [])
        if opts:
            layers.append(_layer(ch, slot + "+school", r.choice(opts), r, pk, avoid, -17.0 + 5.0 * r.random()))
    for extra in spec.get("extra_" + slot, []):
        layers.append(_layer(ch, slot + "+extra", extra[0], r, pk, avoid, float(extra[1]),
                             delay=float(extra[2]) if len(extra) > 2 else 0.0))
    lmin, lmax = DEFAULT_LEN[slot]
    if big:
        lmax += 0.15
    lmax = float(spec.get("len_" + slot, lmax))
    rooms = list(ROOMS)
    room = spec["room"]
    if not spec.get("custom") and r.random() < 0.3:  # a neighbouring room now and then
        i = rooms.index(room)
        room = rooms[max(1, min(len(rooms) - 1, i + r.choice([-1, 1])))]
    eq = [("lowshelf", 180, round(-3 + 6 * r.random(), 1)), ("highshelf", 3800, round(-4 + 7 * r.random(), 1)),
          ("peak", int(500 + 2500 * r.random()), round(-4 + 8 * r.random(), 1))]
    fx = list(spec.get("fx", []))
    if ch.get("school") == "ice" and "shiver" not in fx and slot == D:
        fx.append("shiver")
    return dict(voices=voices, layers=layers, room=room, eq=eq, fx=fx, lmin=lmin, lmax=lmax,
                fade=round(0.12 + 0.12 * r.random(), 3))


# A pool category with no clip left falls back to one of the game's own sounds.
LAYER_FALLBACK = {"shimmer": "magic", "chime": "glass", "fire": "spell_fire", "ice": "ice", "wave": "water_loop",
                  "wind": "gust", "stone": "rubble", "rumble": "rubble", "mud": "splash", "bubbles": "splash",
                  "wings": "whoosh", "harp": "magic", "horn": "bell_far", "whip": "whoosh", "bite": "bones",
                  "sizzle": "spell_fire", "leaves": "card_slide", "tree": "bones", "wood_creak": "lock",
                  "insect": "whoosh", "crow": "whoosh", "gull": "gust", "dog_bark": "growl", "dog_growl": "growl",
                  "bull": "growl", "snake": "whoosh"}


def _layer(ch: dict, slot: str, what: str, r: random.Random, pk: Picker, avoid: set, gain: float,
           delay: float = 0.0) -> dict:
    if what.startswith("pool:") and not pk.by_cat.get(what[5:]):
        what = LAYER_FALLBACK.get(what[5:], "whoosh")
    if what.startswith("pool:"):
        c = pk.pick(ch["id"], slot, [what[5:]], {"arch": "layer", "formant": "shifted"}, avoid, layer=True)
        avoid.add(c["id"])
        return dict(clip=c["id"], gain=round(gain, 1), pitch=round(-2 + 4 * r.random(), 2), delay=delay)
    f = sfx_variant(what, r)
    if not f:
        raise SystemExit("%s: no game sound %s" % (ch["id"], what))
    return dict(sfx=os.path.relpath(f, ROOT).replace("\\", "/"), gain=round(gain, 1),
                pitch=round(-2 + 4 * r.random(), 2), delay=delay)


def outputs_for(ch: dict) -> dict:
    if ch["kind"] == "hero":
        return {P: "hero_%s.ogg" % ch["id"], D: "hero_%s_defeat.ogg" % ch["id"]}
    return {P: "%s_play.ogg" % ch["id"], D: "%s_death.ogg" % ch["id"]}


def plan_all(pool: dict) -> list:
    ov = load_overrides()
    chars = characters()
    chars.sort(key=lambda c: (ORDER.get(c["rarity"], 6), c["id"]))
    pk = Picker(pool)
    plans = []
    for ch in chars:
        spec = spec_for(ch, ov)
        avoid = set()
        slots = {s: plan_slot(ch, spec, s, pk, avoid) for s in (P, D)}
        plans.append({"ch": ch, "spec": spec, "slots": slots, "files": outputs_for(ch)})
    return plans


# ====================================================================== rendering

def clip_path(src: str, pool: dict, c: dict) -> str:
    return os.path.join(src, pool["packs"][c["pack"]]["dir"], c["file"])


def rb(pitch: float, tempo: float, formant: str) -> str:
    return "rubberband=pitch=%.5f:tempo=%.4f:formant=%s:pitchq=quality:transients=mixed" % (
        2 ** (pitch / 12.0), tempo, formant)


MIX_RMS = -20.0  # dBFS every input is levelled to before the plan's gains
_sfx_rms = {}


def level(rms_db: float) -> float:
    return max(-12.0, min(24.0, MIX_RMS - rms_db))


def sfx_rms(path: str, dur: float) -> float:
    key = (path, round(dur, 2))
    if key not in _sfx_rms:
        x = decode(path, 16000, 0.0, dur)
        _sfx_rms[key] = 20 * math.log10(math.sqrt(float(np.mean(x * x))) + 1e-9) if len(x) else MIX_RMS
    return _sfx_rms[key]


def render(slot: dict, src: str, pool: dict, clips: dict, out_path: str, tmp: str) -> dict:
    main = clips[slot["voices"][0]["clip"]]
    tempo = slot["voices"][0]["tempo"]
    length = max(slot["lmin"], min(slot["lmax"] - 0.12, main["dur"] / tempo))
    total = round(min(length + 0.25, slot["lmax"]), 3)
    cmd = [FFMPEG, "-hide_banner", "-loglevel", "error", "-y"]
    chains, labels = [], []
    n = 0
    for v in slot["voices"]:
        c = clips[v["clip"]]
        read = min(c["dur"], total * v["tempo"] + 0.05)
        cmd += ["-ss", "%.3f" % c["t0"], "-t", "%.3f" % read, "-i", clip_path(src, pool, c)]
        # every input is first levelled to the same RMS, so the gains in the plan are real balances
        chains.append("[%d:a]aformat=channel_layouts=mono,aresample=%d,highpass=f=70,%s,volume=%.1fdB,adelay=%d:all=1[v%d]"
                      % (n, SR, rb(v["pitch"], v["tempo"], v.get("formant", "preserved")),
                         v["gain"] + level(c["rms_db"]), int(v["delay"] * 1000), n))
        labels.append("[v%d]" % n)
        n += 1
    for lay in slot["layers"]:
        if "clip" in lay:
            c = clips[lay["clip"]]
            cmd += ["-ss", "%.3f" % c["t0"], "-t", "%.3f" % min(c["dur"], total + 0.05), "-i", clip_path(src, pool, c)]
            rms = c["rms_db"]
        else:
            path = os.path.join(ROOT, lay["sfx"])
            cmd += ["-t", "%.3f" % (total + 0.05), "-i", path]
            rms = sfx_rms(path, total)
        chains.append("[%d:a]aformat=channel_layouts=mono,aresample=%d,%s,highpass=f=120,volume=%.1fdB,adelay=%d:all=1,"
                      "afade=t=out:st=%.3f:d=0.25[v%d]"
                      % (n, SR, rb(lay["pitch"], 1.0, "shifted"), lay["gain"] + level(rms), int(lay["delay"] * 1000),
                         max(0.0, total - 0.3), n))
        labels.append("[v%d]" % n)
        n += 1
    post = []
    for kind, f, g in slot["eq"]:
        if kind == "lowshelf":
            post.append("lowshelf=f=%d:g=%.1f" % (f, g))
        elif kind == "highshelf":
            post.append("highshelf=f=%d:g=%.1f" % (f, g))
        else:
            post.append("equalizer=f=%d:t=q:w=1.2:g=%.1f" % (f, g))
    for fx in slot["fx"]:
        if fx == "vibrato":
            post.append("vibrato=f=5.2:d=0.06")
        elif fx == "chorus":
            post.append("chorus=0.7:0.8:40|65:0.35|0.3:0.3|0.45:2.0|1.3")
        elif fx == "soft":
            post.append("lowpass=f=4200")
        elif fx == "shiver":
            post.append("tremolo=f=9:d=0.25")
        elif fx == "muffle":
            post.append("lowpass=f=1500")
        elif fx == "radio":
            post.append("highpass=f=400,lowpass=f=2600")
        elif fx == "bright":
            post.append("highshelf=f=6000:g=3")
        elif fx == "deep":
            post.append("lowshelf=f=120:g=4")
        elif fx == "flanger":
            post.append("flanger=delay=2:depth=3:regen=20:speed=0.4")
        elif fx == "reverse_tail":
            pass
    if ROOMS.get(slot["room"]):
        post.append("aecho=" + ROOMS[slot["room"]])
    post.append("highpass=f=75:p=2")  # nothing under the voice that a phone speaker would only waste
    post.append("apad=pad_dur=0.6,atrim=0:%.3f,afade=t=in:d=0.006,afade=t=out:st=%.3f:d=%.3f"
                % (total, max(0.0, total - slot["fade"]), slot["fade"]))
    graph = ";".join(chains) + ";" + "".join(labels) + "amix=inputs=%d:normalize=0:duration=longest," % len(labels) \
        + ",".join(post) + "[out]"
    raw = os.path.join(tmp, "raw.wav")
    run(cmd + ["-filter_complex", graph, "-map", "[out]", "-ac", "1", "-ar", str(SR), "-c:a", "pcm_f32le", raw])
    lufs = measure_lufs(raw)
    gain = TARGET_LUFS - lufs
    run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-i", raw, "-af",
         "volume=%.2fdB,alimiter=limit=0.89:attack=2:release=40:level=false" % gain,
         "-ac", "1", "-ar", str(SR), "-c:a", "libvorbis", "-q:a", QUALITY, "-map_metadata", "-1", out_path])
    return {"length": total, "lufs_in": round(lufs, 1), "gain": round(gain, 1)}


def measure_lufs(path: str) -> float:
    r = run([FFMPEG, "-hide_banner", "-nostats", "-i", path, "-af", "ebur128=framelog=quiet", "-f", "null", "-"],
            check=False)
    m = re.findall(r"I:\s+(-?[\d.]+) LUFS", r.stderr)
    v = float(m[-1]) if m else -70.0
    if v <= -69.0:  # too short for the gated measure: fall back to RMS (about the same scale for a vocal)
        x = decode(path, 16000)
        v = 20 * math.log10(math.sqrt(float(np.mean(x * x))) + 1e-9) - 0.7
    return v


def describe(slot: dict, clips: dict, pool: dict) -> str:
    parts = []
    for v in slot["voices"]:
        c = clips[v["clip"]]
        parts.append("%s %+0.1fst x%.2f %s%s" % (c["name"], v["pitch"], v["tempo"], v.get("formant", "")[0],
                                                 (" %+0.0fdB @%.2fs" % (v["gain"], v["delay"])) if v["gain"] or v["delay"] else ""))
    for lay in slot["layers"]:
        nm = clips[lay["clip"]]["name"] if "clip" in lay else os.path.basename(lay["sfx"])
        parts.append("layer %s %+0.0fdB" % (nm, lay["gain"]))
    parts.append("room " + slot["room"])
    if slot["fx"]:
        parts.append("fx " + "+".join(slot["fx"]))
    parts.append("eq " + " ".join("%s%d%+.0f" % (k[0], f, g) for k, f, g in slot["eq"]))
    return "; ".join(parts)


def slot_sources(slot: dict, clips: dict, pool: dict) -> list:
    out = []
    for item in slot["voices"] + slot["layers"]:
        if "clip" in item:
            c = clips[item["clip"]]
            pk = pool["packs"][c["pack"]]
            out.append({"pack": c["pack"], "title": pk["title"], "author": pk["author"], "url": pk["url"],
                        "license": "CC0", "file": c["file"], "t0": c["t0"], "dur": c["dur"]})
        else:
            out.append({"pack": "game-sfx", "title": "game sound " + os.path.basename(item["sfx"]),
                        "author": "see assets/CREDITS.md", "url": "", "license": "CC0", "file": item["sfx"],
                        "t0": 0.0, "dur": 0.0})
    return out


def cmd_build(a) -> None:
    pool = json.load(open(POOL, encoding="utf-8"))
    clips = {c["id"]: c for c in pool["clips"]}
    plans = plan_all(pool)
    only = set(a.only.split(",")) if a.only else None
    combos = {}
    for pl in plans:  # the uniqueness guarantee, by construction: no two characters share a source + parameter combo
        for s in (P, D):
            v = pl["slots"][s]["voices"][0]
            key = (v["clip"], round(v["pitch"], 0))
            if key in combos:
                raise SystemExit("combo clash: %s %s and %s" % (pl["ch"]["id"], s, combos[key]))
            combos[key] = "%s %s" % (pl["ch"]["id"], s)
    if a.dry:
        for pl in plans:
            print("%-26s %-13s | %s || %s" % (pl["ch"]["id"], pl["spec"]["arch"],
                                             describe(pl["slots"][P], clips, pool), describe(pl["slots"][D], clips, pool)))
        return
    os.makedirs(OUT, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix="dc_voices_")
    report = []
    try:
        for i, pl in enumerate(plans):
            ch = pl["ch"]
            for s in (P, D):
                path = os.path.join(OUT, pl["files"][s])
                if only and ch["id"] not in only:
                    continue
                pl.setdefault("render", {})[s] = render(pl["slots"][s], a.src, pool, clips, path, tmp)
            if i % 20 == 0:
                print("%d/%d %s" % (i, len(plans), ch["id"]))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    write_reports(plans, pool, clips)
    print("built %d characters" % len(plans))


def write_reports(plans: list, pool: dict, clips: dict) -> None:
    rows, used = [], {}
    md = ["# Character voice sources (generated by tools/audio/character_voices.py, do not edit)", "",
          "Every file is a non-verbal vocal sound made from CC0 recordings (no speech, no AI audio). Sources: "
          "OpenGameArt packs (CC0 option), Freesound HQ previews of CC0 sounds, an itch.io CC0 pack, and the game's own "
          "CC0 sounds in assets/audio/sfx. Processing: rubberband pitch / tempo, EQ, echo, layering, -18 LUFS.", "",
          "| File | Character | Archetype | Sources | Processing |", "|---|---|---|---|---|"]
    for pl in sorted(plans, key=lambda p: p["ch"]["id"]):
        ch = pl["ch"]
        row = {"id": ch["id"], "name": ch["name"], "kind": ch["kind"], "rarity": ch["rarity"],
               "archetype": pl["spec"]["arch"], "custom": "yes" if pl["spec"]["custom"] else ""}
        for s in (P, D):
            srcs = slot_sources(pl["slots"][s], clips, pool)
            for x in srcs:
                if x["pack"] != "game-sfx":
                    used.setdefault(x["pack"], set()).add(pl["files"][s])
            src_txt = "; ".join("%s (%s, %s) %s@%.2f" % (x["title"], x["author"], x["url"] or x["file"], x["file"], x["t0"])
                                if x["pack"] != "game-sfx" else x["file"] for x in srcs)
            md.append("| %s | %s | %s | %s | %s |" % (pl["files"][s], ch["name"], pl["spec"]["arch"],
                                                      src_txt.replace("|", "/"), describe(pl["slots"][s], clips, pool)))
            row[s + "_file"] = pl["files"][s]
            row[s + "_sources"] = src_txt
            row[s + "_processing"] = describe(pl["slots"][s], clips, pool)
        rows.append(row)
    open(os.path.join(OUT, "SOURCES.md"), "w", encoding="utf-8").write("\n".join(md) + "\n")
    adir = os.path.dirname(POOL)
    with open(os.path.join(adir, "voices.csv"), "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    credits = []
    for slug, files in sorted(used.items()):
        pk = pool["packs"][slug]
        credits.append({"pack": slug, "title": pk["title"], "author": pk["author"], "url": pk["url"],
                        "license": pk["license"], "files": len(files)})
    update_credits(credits)


CREDITS_MD = os.path.join(ROOT, "assets", "CREDITS.md")
BEGIN, END = "<!-- voices:begin (tools/audio/character_voices.py) -->", "<!-- voices:end -->"


def update_credits(credits: list) -> None:
    """The voices' rows in assets/CREDITS.md: one per OpenGameArt / itch.io pack, one per Freesound author."""
    lines = [BEGIN, "", "### Character voices (assets/audio/voices/)", "",
             "Non-verbal vocal sounds (no speech, no AI audio), cut, pitched, layered and loudness-normalised by "
             "tools/audio/character_voices.py. Every source below is CC0 (for packs offered under several licences the "
             "CC0 option is used); each output file's exact sources are in assets/audio/voices/SOURCES.md.", "",
             "| Source | Author | Licence | Files |", "|---|---|---|---|"]
    fs = {}
    for c in credits:
        if c["pack"].startswith("fs-"):
            fs.setdefault(c["author"], []).append(c)
            continue
        lines.append("| [%s](%s) | %s | CC0 | %d |" % (c["title"], c["url"], c["author"], c["files"]))
    for author, items in sorted(fs.items(), key=lambda kv: kv[0].lower()):
        links = ", ".join("[%s](%s)" % (i["title"].replace("|", "/").replace("[", "(").replace("]", ")"), i["url"])
                          for i in sorted(items, key=lambda i: i["url"]))
        lines.append("| Freesound: %s | %s | CC0 | %d |" % (links, author, sum(i["files"] for i in items)))
    lines += ["", END]
    text = open(CREDITS_MD, encoding="utf-8").read()
    block = "\n".join(lines)
    if BEGIN in text and END in text:
        text = text[:text.index(BEGIN)] + block + text[text.index(END) + len(END):]
    else:
        marker = "\n## AI-generated art"
        i = text.index(marker) if marker in text else len(text)
        text = text[:i].rstrip("\n") + "\n\n" + block + "\n" + text[i:]
    open(CREDITS_MD, "w", encoding="utf-8").write(text)


# ====================================================================== uniqueness check

def fingerprint(path: str) -> "np.ndarray":
    x = decode(path, 16000)
    n, hop = 512, 160
    fr = frames(x, n, hop) * np.hanning(n)[None, :]
    spec = np.abs(np.fft.rfft(fr, axis=1)) ** 2 + 1e-10
    rms = np.sqrt(spec.sum(1))
    act = rms > rms.max() * 0.05
    if act.sum() < 4:
        act[:] = True
    spec, rms = spec[act], rms[act]
    freqs = np.fft.rfftfreq(n, 1 / 16000.0)
    edges = np.geomspace(60, 7800, 25)
    bands = np.array([spec[:, (freqs >= edges[i]) & (freqs < edges[i + 1])].sum(1).mean() for i in range(24)])
    bands = np.log10(bands + 1e-10)
    bands -= bands.mean()
    env = np.array([seg.mean() if len(seg) else 0.0 for seg in np.array_split(rms, 12)])
    env /= env.max() + 1e-9
    cent = (spec * freqs[None, :]).sum(1) / spec.sum(1)
    ct = np.array([np.log2(seg.mean() + 1.0) if len(seg) else 0.0 for seg in np.array_split(cent, 8)])
    return np.concatenate([bands * 1.0, env * 2.0, (ct - ct.mean()) * 0.6, [ct.mean() * 0.5, len(x) / 16000.0 * 1.5]])


def cmd_check(a) -> int:
    files = sorted(glob.glob(os.path.join(OUT, "*.ogg")))
    hashes = {}
    bad = 0
    for f in files:
        h = hashlib.sha1(open(f, "rb").read()).hexdigest()
        if h in hashes:
            print("IDENTICAL:", os.path.basename(f), os.path.basename(hashes[h]))
            bad += 1
        hashes[h] = f
    fps = np.array([fingerprint(f) for f in files])
    dist = np.sqrt(((fps[:, None, :] - fps[None, :, :]) ** 2).sum(-1))
    np.fill_diagonal(dist, 1e9)
    names = [os.path.basename(f) for f in files]
    pairs = []
    for i in range(len(files)):
        j = int(np.argmin(dist[i]))
        if i < j or int(np.argmin(dist[j])) != i:
            pairs.append((float(dist[i, j]), names[i], names[j]))
    pairs.sort()
    print("closest pairs (fingerprint distance):")
    for d, x, y in pairs[:15]:
        print("  %.2f  %s  %s" % (d, x, y))
    nn = np.min(dist, axis=1)
    print("files %d, nearest-neighbour distance: min %.2f, median %.2f" % (len(files), nn.min(), float(np.median(nn))))
    close = [p for p in pairs if p[0] < a.threshold]
    for d, x, y in close:
        print("TOO CLOSE: %.2f %s %s" % (d, x, y))
    if a.json:
        json.dump({"min": float(nn.min()), "median": float(np.median(nn)), "closest": pairs[:30]},
                  open(a.json, "w", encoding="utf-8"), indent=1)
    if bad or close:
        print("CHECK FAILED")
        return 1
    print("CHECK OK")
    return 0


# ====================================================================== review reel

def cmd_reel(a) -> None:
    plans = {pl["ch"]["id"]: pl for pl in plan_all(json.load(open(POOL, encoding="utf-8")))}
    chars = [pl["ch"] for pl in plans.values()]
    heroes = [c["id"] for c in chars if c["kind"] == "hero"]
    legends = sorted(c["id"] for c in chars if c["rarity"] == "legendary")
    rest = sorted(c["id"] for c in chars if c["rarity"] not in ("legendary", "hero"))
    # a dozen assorted minions, one per archetype across the bestiary (the legendaries already cover the rest)
    want = ["serpent", "demon", "imp", "mud_creature", "crowd_m", "pig", "lion", "wolf", "angel", "woman",
            "shade_angry", "centaur", "hellhound", "furies", "harpy", "leopard"]
    extra = []
    for arch in want:
        ids = [i for i in rest if plans[i]["spec"]["arch"] == arch]
        if ids and len(extra) < 12:
            extra.append(ids[int(h01("reel", arch) * len(ids))])
    order = heroes + legends + extra
    os.makedirs(a.out, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix="dc_reel_")
    try:
        tick = os.path.join(tmp, "tick.wav")
        run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i",
             "sine=f=1800:d=0.05,afade=t=out:st=0.01:d=0.04,volume=-14dB", "-ar", str(SR), "-ac", "1", tick])
        gaps = {}
        for g in (0.25, 0.35, 0.9):
            gp = os.path.join(tmp, "gap%.2f.wav" % g)
            run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i",
                 "anullsrc=r=%d:cl=mono" % SR, "-t", "%.2f" % g, gp])
            gaps[g] = gp
        seq, lines, t = [], [], 0.0

        def dur(p):
            return len(decode(p, 16000)) / 16000.0
        for k, cid in enumerate(order, 1):
            pl = plans[cid]
            fp, fd = (os.path.join(OUT, pl["files"][s]) for s in (P, D))
            lines.append("%3d  %6.1f s  %-28s %-34s %s" % (k, t, cid, pl["ch"]["name"], pl["spec"]["arch"]))
            for p in (tick, gaps[0.25], fp, gaps[0.35], fd, gaps[0.9]):
                seq.append(p)
                t += dur(p)
        lst = os.path.join(tmp, "list.txt")
        with open(lst, "w", encoding="utf-8") as f:
            for i, p in enumerate(seq):
                f.write("file '%s'\n" % p.replace("\\", "/").replace("'", "'\\''"))
        reel = os.path.join(a.out, "voices_reel.ogg")
        run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-f", "concat", "-safe", "0", "-i", lst,
             "-ar", str(SR), "-ac", "1", "-c:a", "libvorbis", "-q:a", "4", reel])
        head = ["Dante's Inferno card game - character voices review reel (%s)" % os.path.basename(reel),
                "Each entry: a short tick, then the PLAY sound (summon / hero start), a pause, then the DEATH sound "
                "(hero defeat). Times are where the tick starts.", "",
                "  #   time    id                           name                               archetype"]
        open(os.path.join(a.out, "voices_reel.txt"), "w", encoding="utf-8").write("\n".join(head + lines) + "\n")
        shutil.copyfile(os.path.join(os.path.dirname(POOL), "voices.csv"), os.path.join(a.out, "voices_all.csv"))
        print("reel:", reel, "(%d entries, %.0f s)" % (len(order), t))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("pool")
    p.add_argument("--src", default=DEFAULT_SRC)
    b = sub.add_parser("build")
    b.add_argument("--src", default=DEFAULT_SRC)
    b.add_argument("--only", default="")
    b.add_argument("--dry", action="store_true")
    c = sub.add_parser("check")
    c.add_argument("--threshold", type=float, default=1.0)  # same clip, EQ + echo only: 0.7-1.0
    c.add_argument("--json", default="")
    r = sub.add_parser("reel")
    r.add_argument("--out", required=True)
    r.add_argument("--src", default=DEFAULT_SRC)
    s = sub.add_parser("arch")
    a = ap.parse_args()
    if a.cmd == "pool":
        cmd_pool(a)
    elif a.cmd == "build":
        cmd_build(a)
    elif a.cmd == "check":
        sys.exit(cmd_check(a))
    elif a.cmd == "reel":
        cmd_reel(a)
    elif a.cmd == "arch":
        ov = load_overrides()
        for ch in sorted(characters(), key=lambda c: (c["kind"] != "hero", c["id"])):
            sp = spec_for(ch, ov)
            print("%-26s %-34s %-10s %-14s %s" % (ch["id"], ch["name"][:34], ch["rarity"], sp["arch"],
                                                 "*" if sp["custom"] else ""))


if __name__ == "__main__":
    main()
