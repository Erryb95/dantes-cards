# Third-party assets

Only CC0 / OFL / MIT / Apache material (or verified commercial licences) ships with the game.

| Files | Source | Author | Licence |
|---|---|---|---|
| assets/fonts/Cinzel.ttf | Cinzel | Natanael Gama | OFL (assets/fonts/OFL_Cinzel.txt) |
| assets/fonts/IMFeEN*.ttf | IM Fell English | Igino Marini | OFL (assets/fonts/OFL_IMFellEnglish.txt) |
| assets/audio/music/{music_combat,music_boss,intro}/c*_0.ogg | Copied from Dante's Vengeance (folders music_combat, music_boss, music_intro): CC0 OpenGameArt loops and public-domain Musopen / SMCE recordings. Per-track sources are in audio/CREDITS_FPS_SOURCE.md | see that file | CC0 / Public Domain Mark |
| assets/audio/ui/*, assets/audio/sfx/{thunder,splash,wail,rubble,bell_far,sigh,bones,gust}_* | Copied from Dante's Vengeance; per-sound sources in audio/CREDITS_FPS_SOURCE.md | see that file | CC0 |
| assets/audio/sfx/{slam,thud}_* | [Impact Sounds](https://kenney.nl/assets/impact-sounds) | Kenney | CC0 1.0 |
| assets/audio/sfx/{title_sting,bell_funeral,quake_rumble,water_loop,thunder,limbo_drone}.ogg | OpenGameArt / Freesound CC0 (see audio/CREDITS_FPS_SOURCE.md and the FPS assets/CREDITS.md) | nene, aoristos, uagadugu, rubberduck, deleted_user_7146007, Umplix | CC0 |
| Card swish / tick / chime | Synthesised in code (scripts/core/sfx.gd) | - | Original |

## AI-generated art (disclosed)
Card, hero, arena and card-back images in assets/cards/ and assets/arenas/ are AI-generated on the owner's own ComfyUI
with **Qwen-Image 2512** (Apache-2.0) + the Lightning 4-step LoRA (Apache-2.0). Prompts: data/cards.json (`art`) and
the ComfyUI session's notes (status/cards_style.md). House style: hand-tinted Gustave Dore-style engraving, chosen by the
owner on 2026-10-25. Source files: art_src/dore_cards/; card -> image map: the "image" field in data/cards.json.
The painted UI parts in assets/ui/ (card frames, oval ring, name ribbon, parchment, gems, rarity cabochons) come from the
same ComfyUI setup (Qwen-Image 2512, alpha cut with BiRefNet, MIT); sources in art_src/ui/. Cards without a painting yet
show the Acheron arena image as a placeholder.

TODO before a store release: as in the FPS, the St Matthews Choir (SMCE) recordings that may be in `intro` carry a licence
set on archive.org by an uploader; get written confirmation from SMCE or swap those tracks.
