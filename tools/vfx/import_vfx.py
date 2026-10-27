"""Fetches the painted VFX sprites from the ComfyUI PC (read-only /view requests) and installs them for Vfx.

  python tools/vfx/import_vfx.py            # import what is new, list what is still missing
  python tools/vfx/import_vfx.py --force    # re-import

Sources: output/dantes_vfx/vfx_<name>_00001_.png on the ComfyUI PC (1024x1024, emissive on pure black, made by the
image session with Qwen-Image). They are drawn with additive blending, so black is transparent and no alpha is
needed: each is scaled to 512 px and saved as assets/vfx/vfx_<name>.png. Originals go to art_src/vfx/.
"""
import io
import os
import sys
import urllib.parse
import urllib.request

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BASE = open(r"C:\Servers\comfy_url.txt", encoding="utf-8").readline().strip().rstrip("/")
NAMES = ["flame_tongue", "fireball", "lava_crack", "ice_shard", "frost_star", "venom_glob", "serpent_coil",
         "light_beam", "angel_feather", "halo_ring", "soul_wisp", "skull_wisp", "whirlwind", "gust_streak",
         "water_splash", "claw_rake", "gold_coin", "glyph_ring", "judgment_sigil", "chain_glow", "blood_burst",
         "page_glow",
         # second batch: deaths, casting runes, more hits, heal / buff
         "death_ice_shards", "death_soul", "death_stone", "death_venom", "death_ash", "death_shadow", "death_blood",
         "rune_fire", "rune_ice", "rune_holy", "rune_shadow", "rune_venom", "rune_soul",
         "lightning", "thorn_vines", "thorn_spike", "pitch_splash", "flaming_arrow", "ground_fissure",
         "blood_column", "water_column", "sunburst", "shadow_burst", "fire_explosion",
         "heal_swirl", "holy_shield", "buff_aura", "snowflake", "wind_ribbon",
         # third batch: legendary signatures and keyword / action moments
         "leg_nicholas", "leg_capaneus", "leg_old_man_crete", "leg_malacoda", "leg_nimrod", "leg_typhon",
         "leg_ruggieri", "leg_alberigo", "leg_lucifer", "leg_homer", "leg_cato", "leg_beatrice", "leg_achilles",
         "leg_semiramis", "leg_caesar", "leg_francesca", "leg_ugolino", "leg_minos",
         "drain_siphon", "rebirth_flare", "venom_fangs", "ward_shatter", "ice_encase", "silence_lock",
         "trigger_spark", "draw_glow", "mana_burst", "hero_death", "card_burn", "summon_pillar",
         # fourth batch: the Wrathful (Fight clash, Wrath waking, legendary signatures)
         "mud_splash", "rage_embers", "leg_red_towers", "leg_filippo", "leg_tydeus", "leg_athamas"]


def fetch(name: str) -> bytes | None:
    for i in range(5, 0, -1):
        q = urllib.parse.urlencode({"subfolder": "dantes_vfx", "type": "output",
                                    "filename": "vfx_%s_%05d_.png" % (name, i)})
        try:
            return urllib.request.urlopen(BASE + "/view?" + q, timeout=60).read()
        except Exception:  # noqa: BLE001 - not painted (yet)
            continue
    return None


def main() -> None:
    force = "--force" in sys.argv
    got, missing = [], []
    for name in NAMES:
        out = os.path.join(ROOT, "assets", "vfx", "vfx_%s.png" % name)
        if os.path.exists(out) and not force:
            continue
        data = fetch(name)
        if data is None:
            missing.append(name)
            continue
        os.makedirs(os.path.join(ROOT, "art_src", "vfx"), exist_ok=True)
        open(os.path.join(ROOT, "art_src", "vfx", "vfx_%s.png" % name), "wb").write(data)
        im = Image.open(io.BytesIO(data)).convert("RGB")
        im.thumbnail((512, 512), Image.LANCZOS)
        im.save(out, optimize=True)
        got.append(name)
    print("imported %d: %s" % (len(got), " ".join(got) or "-"))
    print("still missing %d: %s" % (len(missing), " ".join(missing) or "-"))


if __name__ == "__main__":
    main()
