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
| assets/audio/sfx/{card_slide,card_place,card_fan,card_shuffle,pack_open,pack_take}_* | [Casino Audio](https://kenney.nl/assets/casino-audio) | Kenney | CC0 1.0 |
| assets/audio/sfx/page_* | [RPG Audio](https://kenney.nl/assets/rpg-audio) | Kenney | CC0 1.0 |
| assets/audio/sfx/glass_* | [Interface Sounds](https://kenney.nl/assets/interface-sounds) | Kenney | CC0 1.0 |
| assets/audio/sfx/{coins,gem,spell,spell_fire,blade,roar,creature_die,chain,metal,lock}_* | [80 CC0 RPG SFX](https://opengameart.org/content/80-cc0-rpg-sfx) | rubberduck (OpenGameArt) | CC0 1.0 |
| assets/audio/sfx/{clash}_* | [Fantasy Weapons and Apparel SFX Library](https://opengameart.org/content/fantasy-weapons-and-apparel-sfx-library) | Vehicle (OpenGameArt) | CC0 1.0 |
| assets/audio/sfx/{coin_spin,coin_pouch,vial}_* | [Fantasy Accessory SFX Library](https://opengameart.org/content/fantasy-accessory-sfx-library) | Vehicle (OpenGameArt) | CC0 1.0 |
| assets/audio/sfx/ice_* | [Ice spells](https://opengameart.org/content/ice-spells) | bart (OpenGameArt) | CC0 1.0 |
| assets/audio/sfx/magic_* | [Magic spell SFX](https://opengameart.org/content/magic-spell-sfx) | JaggedStone (OpenGameArt) | CC0 1.0 |
| assets/audio/sfx/moan_* | [Ghost/monster voice moaning, growling](https://opengameart.org/content/ghost-monster-voice-moaning-growling) | qubodup (OpenGameArt) | CC0 1.0 |
| assets/audio/sfx/growl_* | [Monster sound effects pack](https://opengameart.org/content/monster-sound-effects-pack) | Ogrebane (OpenGameArt) | CC0 1.0 |
| assets/audio/sfx/whoosh_* | [Swishes sound pack](https://opengameart.org/content/swishes-sound-pack) | artisticdude (OpenGameArt) | CC0 1.0 |
| assets/audio/sfx/card_flip_* | [Book flip sounds](https://opengameart.org/content/book-flip-sounds) | Voltiment555 (OpenGameArt) | CC0 1.0 |
| assets/vfx/k_*.png | [Particle Pack](https://kenney.nl/assets/particle-pack) (white-on-alpha textures, some downscaled to 256 px) | Kenney | CC0 1.0 |
| Card swish / tick / chime | Synthesised in code (scripts/core/sfx.gd) | - | Original |

## AI-generated art (disclosed)
Card, hero, arena and card-back images in assets/cards/ and assets/arenas/ are AI-generated on the owner's own ComfyUI
with **Qwen-Image 2512** (Apache-2.0) + the Lightning 4-step LoRA (Apache-2.0). Prompts: data/cards.json (`art`) and
the ComfyUI session's notes (status/cards_style.md). House style: hand-tinted Gustave Dore-style engraving, chosen by the
owner on 2026-10-25. Source files: art_src/dore_cards/; card -> image map: the "image" field in data/cards.json.
The painted UI parts in assets/ui/ (card borders, ribbon, gems, rarity cabochons, button plate, end-turn seal, power disc,
icons) and the VFX sprites in assets/vfx/ come from the
same ComfyUI setup (Qwen-Image 2512, alpha cut with BiRefNet, MIT); sources in art_src/ui/. Cards without a painting yet
show the Acheron arena image as a placeholder.

TODO before a store release: as in the FPS, the St Matthews Choir (SMCE) recordings that may be in `intro` carry a licence
set on archive.org by an uploader; get written confirmation from SMCE or swap those tracks.
