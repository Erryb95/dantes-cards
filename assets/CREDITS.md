# Third-party assets

Only CC0 / OFL / MIT / Apache material (or verified commercial licences) ships with the game.

| Files | Source | Author | Licence |
|---|---|---|---|
| assets/intro/plates/* | Grayscale crops of the best scans found on [Wikimedia Commons](https://commons.wikimedia.org/wiki/Category:Gustave_Dor%C3%A9_-_Inferno) of Doré's Inferno plates (1870 Berlin edition scanned by the National Library of Poland, via Commons, and other Commons scans), downscaled to 1600x880. Copied from Dante's Vengeance, where every scan and its Commons page is listed (docs/art/dore_plates.json) | Gustave Dore (1832-1883) | Public domain |
| assets/intro/voice/* | [LibriVox, The Divine Comedy (Longfellow), Inferno Canto I and III](https://librivox.org/the-divine-comedy-by-dante-alighieri/), cut and loudness-normalised (v_c_gate.ogg is cut down to four lines of the gate inscription). Human narration, no synthetic voice | Reader: Cori Samuel | Public domain (LibriVox) |
| assets/intro/video/s2_forest, s3a_panther, s3b_lion, s5_gate (.ogv) | **AI-generated motion, disclosed.** Wan 2.2 I2V A14B (Q4_K_M GGUF, lightx2v 4-step LoRAs) image-to-video on the owner's PC, from the public-domain Dore plates (stable range, played ping-pong); upscaled 2x with [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) (realesr-animevideov3), then the static regions take the high frequencies of the plate scan. Re-encoded for this game with ffmpeg / libtheora to 1600x880 | Wan: Apache 2.0; Real-ESRGAN code and released weights: BSD-3-Clause; ncnn-vulkan port: MIT |
| assets/intro/video/s4_virgil, s6_charon (.ogv) | 12 s seamless loops: the public-domain Dore plate itself, displaced inside hand-painted masks (hair, foliage, clouds, water, mist) with procedural sinusoid motion (OpenCV + NumPy). No AI pixels. Re-encoded to 1600x880 with ffmpeg / libtheora | Public domain plates; tools Apache 2.0 / BSD |
| assets/intro/audio/bell_ambient.ogg | [ambientBell](https://freesound.org/people/Divinux/sounds/198416/) | Divinux | CC0 |
| assets/intro/audio/wind_loop.ogg | [Wind spinning sound](https://freesound.org/people/xXx_JPMC_xXx/sounds/361222/) | xXx_JPMC_xXx | CC0 |
| assets/intro/audio/growl_beast.ogg, roar_lion.ogg | [80 CC0 creature SFX](https://opengameart.org/content/80-cc0-creature-sfx) and [#2](https://opengameart.org/content/80-cc0-creture-sfx-2) | rubberduck | CC0 |
| assets/intro/music/score_a.ogg, score_b.ogg (the intro score, cut to fit the cinematic) | c1: Tchaikovsky, Symphony No. 6, I (Musopen Kickstarter orchestra recording, Public Domain Mark 1.0); c5: Brahms, Ein deutsches Requiem II (St Matthews Choir, SMCE, live recording; CC0 as set by the uploader, see the TODO at the end of this file). Sources in audio/CREDITS_FPS_SOURCE.md | Musopen / SMCE | Public domain / CC0 |
| assets/fonts/Cinzel.ttf | Cinzel | Natanael Gama | OFL (assets/fonts/OFL_Cinzel.txt) |
| assets/fonts/CinzelTitle.ttf | Cinzel Title: static 600-weight instance of Cinzel with merged outlines (tools/ui/make_title_font.py) | Natanael Gama (modified) | OFL (assets/fonts/OFL_Cinzel.txt) |
| assets/fonts/IMFeEN*.ttf | IM Fell English | Igino Marini | OFL (assets/fonts/OFL_IMFellEnglish.txt) |
| assets/audio/music/intro/c1_0.ogg (whole piece, loudness-normalised by tools/audio/build_music.py) | Brahms: Ein deutsches Requiem - II. Denn alles Fleisch, es ist wie Gras | St Matthews Choir (SMCE | CC0 1.0 (set by the performing choir on archive.org), https://archive.org/details/BrahmsRequiem |
| assets/audio/music/intro/c2_0.ogg (whole piece, loudness-normalised by tools/audio/build_music.py) | Cherubini: Requiem in C minor - Introitus (Requiem aeternam) | St Matthews Choir (SMCE | CC0 1.0 (set by the performing choir on archive.org), https://archive.org/details/CherubiniRequiemInCMinor2011 |
| assets/audio/music/intro/c3_0.ogg (whole piece, loudness-normalised by tools/audio/build_music.py) | Tchaikovsky: Symphony No. 6 'Pathetique' - IV. Finale: Adagio lamentoso | Musopen Kickstarter orchestra recordings (2011-2012) | Public Domain Mark 1.0, https://archive.org/details/musopen-dvd |
| assets/audio/music/intro/c4_0.ogg (whole piece, loudness-normalised by tools/audio/build_music.py) | Josef Suk: Meditation on the Old Czech Chorale 'St Wenceslas' (string quartet) | Musopen Kickstarter orchestra recordings (2011-2012) | Public Domain Mark 1.0, https://archive.org/details/musopen-dvd |
| assets/audio/music/music_combat/c1_0.ogg (whole piece, loudness-normalised by tools/audio/build_music.py) | Cherubini: Requiem in C minor - Dies irae | St Matthews Choir (SMCE | CC0 1.0 (set by the performing choir on archive.org), https://archive.org/details/CherubiniRequiemInCMinor2011 |
| assets/audio/music/music_combat/c2_0.ogg (whole piece, loudness-normalised by tools/audio/build_music.py) | Beethoven: Coriolan Overture, Op. 62 | Musopen Kickstarter orchestra recordings (2011-2012) | Public Domain Mark 1.0, https://archive.org/details/musopen-dvd |
| assets/audio/music/music_combat/c3_0.ogg (whole piece, loudness-normalised by tools/audio/build_music.py) | Mozart: Symphony No. 40 in G minor, K. 550 - I. Molto allegro | Musopen Kickstarter orchestra recordings (2011-2012) | Public Domain Mark 1.0, https://archive.org/details/musopen-dvd |
| assets/audio/music/music_combat/c4_0.ogg (whole piece, loudness-normalised by tools/audio/build_music.py) | Tchaikovsky: Symphony No. 6 'Pathetique' - III. Allegro molto vivace | Musopen Kickstarter orchestra recordings (2011-2012) | Public Domain Mark 1.0, https://archive.org/details/musopen-dvd |
| assets/audio/music/music_boss/c1_0.ogg (whole piece, loudness-normalised by tools/audio/build_music.py) | Brahms: Symphony No. 4 - IV. Allegro energico e passionato | Musopen Kickstarter orchestra recordings (2011-2012) | Public Domain Mark 1.0, https://archive.org/details/musopen-dvd |
| assets/audio/music/music_boss/c2_0.ogg (whole piece, loudness-normalised by tools/audio/build_music.py) | Beethoven: Egmont Overture, Op. 84 | Musopen Kickstarter orchestra recordings (2011-2012) | Public Domain Mark 1.0, https://archive.org/details/musopen-dvd |
| assets/audio/music/music_boss/c3_0.ogg (whole piece, loudness-normalised by tools/audio/build_music.py) | Brahms: Tragic Overture, Op. 81 | Musopen Kickstarter orchestra recordings (2011-2012) | Public Domain Mark 1.0, https://archive.org/details/musopen-dvd |
| assets/audio/ui/*, assets/audio/sfx/{thunder,splash,wail,rubble,bell_far,sigh,bones,gust}_* | Copied from Dante's Vengeance; per-sound sources in audio/CREDITS_FPS_SOURCE.md | see that file | CC0 |
| assets/audio/sfx/wind_ghost_loop.ogg | Copied from Dante's Vengeance (amb_funnel_wind c2): [Wind_and_Ghost.mp3](https://freesound.org/people/Andrastos87/sounds/636440/) | Andrastos87 | CC0 |
| assets/audio/sfx/cold_wind_loop.ogg | Copied from Dante's Vengeance (amb_funnel_wind c1, low-passed): [Air Rush (longer).wav](https://freesound.org/people/Henrythetrain/sounds/138430/) | Henrythetrain | CC0 |
| assets/audio/sfx/fire_loop.ogg | Copied from Dante's Vengeance (amb_fire c1): [Fire Crackling](https://opengameart.org/content/fire-crackling) | AntumDeluge | CC0 |
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
icons, card text plates, the headline lettering in assets/ui/words/, the app icon in assets/icon.png and assets/app_icon/) and the painted VFX sprites in assets/vfx/ (every file not named k_*) come from the
same ComfyUI setup (Qwen-Image 2512, alpha cut with BiRefNet, MIT); sources in art_src/ui/. The vfx_*.png spell sprites
are emissive paintings on black, drawn with additive blending (no alpha cut); sources in art_src/vfx/,
imported by tools/vfx/import_vfx.py.
The looping animations of some legendary cards (assets/cards/loops/*.ogv, 3 s, silent) are AI-generated: Wan 2.2
image-to-video (Apache-2.0) on the owner's ComfyUI, made from the card's own AI art above. A card animates when its
loop file exists; tools/cards/make_loops.py converts the Wan mp4 clips to Ogg Theora.
The depth maps in assets/cards/depth/ (greyscale, used only for the art's parallax) are estimated by an AI model from the
card and hero art above: **Depth Anything V2 Small** ([model card](https://huggingface.co/depth-anything/Depth-Anything-V2-Small),
Apache-2.0; only the Small size is Apache, Base / Large / Giant are CC-BY-NC and are not used), run as the ONNX export
[onnx-community/depth-anything-v2-small](https://huggingface.co/onnx-community/depth-anything-v2-small) (Apache-2.0) with
onnxruntime (MIT) on the CPU by tools/cards/make_depth.py, then normalised and blurred. The model is not shipped.
The opening cinematic (assets/intro/) is made of Gustave Dore's public-domain plates. Four of its clips (forest, panther,
lion, gate) were animated with the AI video model Wan 2.2 (Apache-2.0) on the owner's PC; the other two clips, the
plates and the narration are not AI (the narration is a human LibriVox recording). Cards without a painting yet
show the Acheron arena image as a placeholder.

TODO before a store release: as in the FPS, the St Matthews Choir (SMCE) recordings that may be in `intro` carry a licence
set on archive.org by an uploader; get written confirmation from SMCE or swap those tracks.
