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

<!-- voices:begin (tools/audio/character_voices.py) -->

### Character voices (assets/audio/voices/)

Non-verbal vocal sounds (no speech, no AI audio), cut, pitched, layered and loudness-normalised by tools/audio/character_voices.py. Every source below is CC0 (for packs offered under several licences the CC0 option is used); each output file's exact sources are in assets/audio/voices/SOURCES.md.

| Source | Author | Licence | Files |
|---|---|---|---|
| [25 CC0 mud sfx](https://opengameart.org/content/25-cc0-mud-sfx) | rubberduck | CC0 | 51 |
| [40 CC0 water / splash / slime SFX](https://opengameart.org/content/40-cc0-water-splash-slime-sfx) | rubberduck | CC0 | 8 |
| [5 Hit Sounds + Dying](https://opengameart.org/content/5-hit-sounds-dying) | TinyWorlds | CC0 | 5 |
| [5 Pillager Sounds](https://opengameart.org/content/5-pillager-sounds) | StarNinjas | CC0 | 3 |
| [7 Ghast Sounds](https://opengameart.org/content/7-ghast-sounds) | StarNinjas | CC0 | 6 |
| [80 CC0 creature SFX](https://opengameart.org/content/80-cc0-creature-sfx) | rubberduck | CC0 | 8 |
| [80 CC0 creture SFX #2](https://opengameart.org/content/80-cc0-creture-sfx-2) | rubberduck | CC0 | 3 |
| [Big scary troll sounds](https://opengameart.org/content/big-scary-troll-sounds) | Darsycho | CC0 | 1 |
| [Boar](https://opengameart.org/content/boar-0) | fvcalderan | CC0 | 1 |
| [Breathing Tired](https://opengameart.org/content/breathing-tired) | mikeask | CC0 | 1 |
| [Cat Purr & Meow](https://opengameart.org/content/cat-purr-meow) | Kerzoven | CC0 | 1 |
| [Creepy Incoherent Chanting](https://opengameart.org/content/creepy-incoherent-chanting) | OwlishMedia | CC0 | 5 |
| [Death sounds](https://opengameart.org/content/death-sounds-0) | Exewin | CC0 | 11 |
| [Dog Growl](https://opengameart.org/content/dog-growl) | bonebrah | CC0 | 1 |
| [Dog Grunt](https://opengameart.org/content/dog-grunt) | qubodup | CC0 | 1 |
| [Donkey Bray](https://opengameart.org/content/donkey-bray) | StarNinjas | CC0 | 2 |
| [Evil Laugh 2](https://opengameart.org/content/evil-laugh-2) | AntumDeluge | CC0 | 1 |
| [Evil laughter](https://opengameart.org/content/evil-laughter) | qubodup | CC0 | 2 |
| [Female high-pitched scream SFX](https://opengameart.org/content/female-high-pitched-scream-sfx) | WuxiaScrub | CC0 | 1 |
| [Female Hurt Grunts & Groans](https://opengameart.org/content/female-hurt-grunts-groans) | Nocturnal_Vanguard | CC0 | 7 |
| [Female Scream 1](https://opengameart.org/content/female-scream-1) | Nocturnal_Vanguard | CC0 | 1 |
| [Ghost](https://opengameart.org/content/ghost) | Ogrebane | CC0 | 1 |
| [Ghost breath](https://opengameart.org/content/ghost-breath) | qubodup | CC0 | 1 |
| [Ghost Monster Voice Moaning & Growling](https://opengameart.org/content/ghost-monster-voice-moaning-growling) | qubodup | CC0 | 4 |
| [Ghostly Humming](https://opengameart.org/content/ghostly-humming) | Nocturnal_Vanguard | CC0 | 3 |
| [Ghostmonster sounds](https://opengameart.org/content/ghostmonster-sounds) | iletzy | CC0 | 3 |
| [Girly Scream](https://opengameart.org/content/girly-scream) | Ferk | CC0 | 1 |
| [Goblins Sound Pack](https://opengameart.org/content/goblins-sound-pack) | artisticdude | CC0 | 1 |
| [Gorilla Sounds](https://opengameart.org/content/gorilla-sounds) | AntumDeluge | CC0 | 1 |
| [grunts of male death and pain](https://opengameart.org/content/grunts-male-death-and-pain) | thebardofblasphemy | CC0 | 10 |
| [Hungry ghoul](https://opengameart.org/content/hungry-ghoul) | Darsycho | CC0 | 3 |
| [Hurt / Death sound effect for character](https://opengameart.org/content/hurt-death-sound-effect-for-character) | Badre-Eddine | CC0 | 7 |
| [Hurt Sound Effects](https://opengameart.org/content/hurt-sound-effects) | EZduzziteh | CC0 | 2 |
| [Goofy Sounds for Scary Monsters](https://stormyman.itch.io/goofy-sounds-for-scary-monsters) | Stormyman (Christopher Hahn) | CC0 | 24 |
| [Male dead voice](https://opengameart.org/content/male-dead-voice) | mieki256 | CC0 | 29 |
| [Male Grunt/Yelling sounds](https://opengameart.org/content/male-gruntyelling-sounds) | HaelDB | CC0 | 37 |
| [Man hurt sounds](https://opengameart.org/content/man-hurt-sounds) | Aharabada | CC0 | 5 |
| [Maniacal Laughter Pack 1](https://opengameart.org/content/maniacal-laughter-pack-1) | Nocturnal_Vanguard | CC0 | 5 |
| [Old Man Cough](https://opengameart.org/content/old-man-cough) | AntumDeluge | CC0 | 3 |
| [Osare Minotaur Sounds](https://opengameart.org/content/osare-minotaur-sounds) | Brandon Morris (submitted by HaelDB) | CC0 | 1 |
| [Pain sounds by EmoPreben](https://opengameart.org/content/pain-sounds-by-emopreben) | EmoPreben | CC0 | 5 |
| [Sick Noises](https://opengameart.org/content/sick-noises) | frosty ham | CC0 | 3 |
| [Sinister Laugh](https://opengameart.org/content/sinister-laugh) | WeaponGuy | CC0 | 2 |
| [Steam release sounds](https://opengameart.org/content/steam-release-sounds) | bart | CC0 | 5 |
| [T-rex Calls](https://opengameart.org/content/t-rex-calls) | CaveboyTup | CC0 | 2 |
| [Tiny creatures sounds](https://opengameart.org/content/tiny-creatures-sounds) | fvcalderan | CC0 | 2 |
| [Tiny vicious creature](https://opengameart.org/content/tiny-vicious-creature) | Darsycho | CC0 | 1 |
| [Wolf Monster Sound](https://opengameart.org/content/wolf-monster-sound) | CaveboyTup | CC0 | 1 |
| [Yak Imitation](https://opengameart.org/content/yak-imitation) | AntumDeluge | CC0 | 1 |
| [Zombie moans](https://opengameart.org/content/zombie-moans) | Darsycho | CC0 | 3 |
| [Zombie Pain](https://opengameart.org/content/zombie-pain) | Vinrax | CC0 | 1 |
| [Zombie / Skeleton / Monster Voice Effects](https://opengameart.org/content/zombie-skeleton-monster-voice-effects) | ArcadeParty | CC0 | 6 |
| [Zombies Sound Pack](https://opengameart.org/content/zombies-sound-pack) | artisticdude | CC0 | 4 |
| Freesound: [sighing](https://freesound.org/people/12125065/sounds/449463/) | 12125065 | CC0 | 1 |
| Freesound: [05 Horn.wav](https://freesound.org/people/15HPanska_Ruttner_Jan/sounds/461679/) | 15HPanska_Ruttner_Jan | CC0 | 1 |
| Freesound: [red-tailed-hawk-flying-away.wav](https://freesound.org/people/1888software/sounds/575525/) | 1888software | CC0 | 1 |
| Freesound: [bell ding 1.wav](https://freesound.org/people/5ro4/sounds/611113/) | 5ro4 | CC0 | 3 |
| Freesound: [Die.wav](https://freesound.org/people/89o/sounds/434129/) | 89o | CC0 | 1 |
| Freesound: [Wing Flap 1.wav](https://freesound.org/people/_stubb/sounds/389634/) | _stubb | CC0 | 1 |
| Freesound: [Animal Dog Bark And Growl 01.wav](https://freesound.org/people/abhisheky948/sounds/625501/) | abhisheky948 | CC0 | 2 |
| Freesound: [female sigh (edit)](https://freesound.org/people/AbrahamMast/sounds/501339/) | AbrahamMast | CC0 | 2 |
| Freesound: [A single scream of a young male](https://freesound.org/people/akridiy/sounds/759458/) | akridiy | CC0 | 1 |
| Freesound: [Male Scream](https://freesound.org/people/aldenroth2/sounds/272023/) | aldenroth2 | CC0 | 1 |
| Freesound: [Stone Scrape 2](https://freesound.org/people/alegemaate/sounds/667283/) | alegemaate | CC0 | 1 |
| Freesound: [MendozaaSigh_mixdown.wav](https://freesound.org/people/alex6100/sounds/449477/) | alex6100 | CC0 | 1 |
| Freesound: [Evil demonic laugh](https://freesound.org/people/amnesia12/sounds/522132/) | amnesia12 | CC0 | 1 |
| Freesound: [Wing Flap (Flag Flapping) 5a](https://freesound.org/people/ani_music/sounds/244982/) | ani_music | CC0 | 2 |
| Freesound: [Freeze sound effect FX](https://freesound.org/people/antonsoederberg/sounds/685253/) | antonsoederberg | CC0 | 1 |
| Freesound: [Rolling Stone](https://freesound.org/people/anturium.studio/sounds/844378/) | anturium.studio | CC0 | 1 |
| Freesound: [Big Roar.wav](https://freesound.org/people/AnusProductions/sounds/429083/) | AnusProductions | CC0 | 1 |
| Freesound: [Monster.wav](https://freesound.org/people/anwul/sounds/185366/) | anwul | CC0 | 1 |
| Freesound: [WomanScream.wav](https://freesound.org/people/Archeos/sounds/261419/) | Archeos | CC0 | 1 |
| Freesound: [Male Death Scream 1.mp3](https://freesound.org/people/areischen/sounds/432057/) | areischen | CC0 | 1 |
| Freesound: [Major Effort and Fear](https://freesound.org/people/Artistic_Dragonborn/sounds/838820/) | Artistic_Dragonborn | CC0 | 1 |
| Freesound: [question noise.wav](https://freesound.org/people/AuDRoger/sounds/471205/) | AuDRoger | CC0 | 1 |
| Freesound: [Studio roar](https://freesound.org/people/AugustSandberg/sounds/265554/) | AugustSandberg | CC0 | 1 |
| Freesound: [Grunt 3](https://freesound.org/people/aulix24/sounds/795468/) | aulix24 | CC0 | 1 |
| Freesound: [Crack and Crunch](https://freesound.org/people/Aurelon/sounds/422623/) | Aurelon | CC0 | 2 |
| Freesound: [Chihuahua Puppy Whine](https://freesound.org/people/AustinXYZ/sounds/350593/) | AustinXYZ | CC0 | 1 |
| Freesound: [Thunder Bucket.wav](https://freesound.org/people/BaDoink/sounds/563338/) | BaDoink | CC0 | 1 |
| Freesound: [Demon Giant Howl.wav](https://freesound.org/people/Bananaboatman33/sounds/257635/) | Bananaboatman33 | CC0 | 1 |
| Freesound: [Hawk 2.wav](https://freesound.org/people/basedMedia/sounds/548118/) | basedMedia | CC0 | 1 |
| Freesound: [4th dimension banshee death.aif](https://freesound.org/people/batchku/sounds/10347/) | batchku | CC0 | 1 |
| Freesound: [Gasp Male](https://freesound.org/people/bertiehs/sounds/271245/) | bertiehs | CC0 | 1 |
| Freesound: [Lyre harp single note](https://freesound.org/people/Biggertigger2006/sounds/722897/) | Biggertigger2006 | CC0 | 1 |
| Freesound: [few small branches snapping, close up, high frequency,H6.wav](https://freesound.org/people/Bini_trns/sounds/354103/) | Bini_trns | CC0 | 2 |
| Freesound: [Horse Snort.wav](https://freesound.org/people/black_trillium/sounds/397236/) | black_trillium | CC0 | 2 |
| Freesound: [Male Death Sound](https://freesound.org/people/Blankened/sounds/554443/), [MaleDeathSound12.wav](https://freesound.org/people/Blankened/sounds/577033/) | Blankened | CC0 | 2 |
| Freesound: [Girl sighs](https://freesound.org/people/BlueSiren/sounds/377736/) | BlueSiren | CC0 | 1 |
| Freesound: [Choking](https://freesound.org/people/Bowesy/sounds/522163/) | Bowesy | CC0 | 3 |
| Freesound: [FemaleGrunt3.wav](https://freesound.org/people/BranndyBottle/sounds/464673/) | BranndyBottle | CC0 | 1 |
| Freesound: [Short cough / choke](https://freesound.org/people/Breviceps/sounds/444723/), [Video Game SFX - Drowning sound](https://freesound.org/people/Breviceps/sounds/445971/), [Disgusting Chewing.wav](https://freesound.org/people/Breviceps/sounds/447916/), [Creaking Wood](https://freesound.org/people/Breviceps/sounds/456814/) | Breviceps | CC0 | 4 |
| Freesound: [belch.wav](https://freesound.org/people/C-V/sounds/521535/) | C-V | CC0 | 1 |
| Freesound: [15-WolfCrying.wav](https://freesound.org/people/cazadordoblekatana/sounds/429109/) | cazadordoblekatana | CC0 | 1 |
| Freesound: [mancough.wav](https://freesound.org/people/cbmontes/sounds/554705/) | cbmontes | CC0 | 1 |
| Freesound: [Ding.wav](https://freesound.org/people/chennes/sounds/376807/) | chennes | CC0 | 3 |
| Freesound: [Hurt  1 - (Male)](https://freesound.org/people/Christopherderp/sounds/342229/), [Hurt 2 - (Male)](https://freesound.org/people/Christopherderp/sounds/342230/), [Hurt 3 - (Male)](https://freesound.org/people/Christopherderp/sounds/342231/), [Cheesy Death Noise - (Male)](https://freesound.org/people/Christopherderp/sounds/342232/) | Christopherderp | CC0 | 4 |
| Freesound: [Transition,action,jump,pitch-shift,short,shimmer,whoosh,positive,soft.wav](https://freesound.org/people/CJDeets/sounds/449645/) | CJDeets | CC0 | 3 |
| Freesound: [Evil Laugh](https://freesound.org/people/ckvoiceover/sounds/401332/), [Man Coughing](https://freesound.org/people/ckvoiceover/sounds/401334/) | ckvoiceover | CC0 | 2 |
| Freesound: [Scream](https://freesound.org/people/claracarpintero/sounds/219856/) | claracarpintero | CC0 | 1 |
| Freesound: [Hard Candy / Bone Crunch](https://freesound.org/people/clif_creates/sounds/392883/) | clif_creates | CC0 | 1 |
| Freesound: [Old Men Moan.wav](https://freesound.org/people/cmilo1269/sounds/491944/) | cmilo1269 | CC0 | 1 |
| Freesound: [tree_creak_1](https://freesound.org/people/Comradar/sounds/797991/), [tree_creak_3](https://freesound.org/people/Comradar/sounds/797993/) | Comradar | CC0 | 2 |
| Freesound: [sh sound effect (voice shh)](https://freesound.org/people/connerdrake98/sounds/701175/) | connerdrake98 | CC0 | 1 |
| Freesound: [HIS_hissing_cat_snake.wav](https://freesound.org/people/CrownieYT/sounds/447636/) | CrownieYT | CC0 | 1 |
| Freesound: [BubbleNoise.wav](https://freesound.org/people/d4nhardt/sounds/688550/) | d4nhardt | CC0 | 1 |
| Freesound: [Hmm reflexion male voice thinking](https://freesound.org/people/daalvinz/sounds/394231/) | daalvinz | CC0 | 1 |
| Freesound: [hmmmm](https://freesound.org/people/DAN2008/sounds/165011/) | DAN2008 | CC0 | 1 |
| Freesound: [Woman Screaming](https://freesound.org/people/DanJFilms/sounds/845164/) | DanJFilms | CC0 | 1 |
| Freesound: [exalacion3.wav](https://freesound.org/people/Darkech/sounds/391880/) | Darkech | CC0 | 1 |
| Freesound: [Laughing (male)](https://freesound.org/people/dastudiospr/sounds/529818/) | dastudiospr | CC0 | 3 |
| Freesound: [gasp.ogg](https://freesound.org/people/deleted_user_12367688/sounds/677540/) | deleted_user_12367688 | CC0 | 1 |
| Freesound: [Laugh_male_quiet.wav](https://freesound.org/people/deleted_user_2104797/sounds/166141/), [Laugh_old_man_6.wav](https://freesound.org/people/deleted_user_2104797/sounds/166150/), [Bird Flap B 05.wav](https://freesound.org/people/deleted_user_2104797/sounds/330967/) | deleted_user_2104797 | CC0 | 5 |
| Freesound: [Grunting effort pushing something.wav](https://freesound.org/people/DeqstersLab/sounds/680135/) | DeqstersLab | CC0 | 4 |
| Freesound: [burstscream.mp3](https://freesound.org/people/doctorsex/sounds/699909/) | doctorsex | CC0 | 1 |
| Freesound: [Mmmm!](https://freesound.org/people/doggo_mcdoggo/sounds/368592/) | doggo_mcdoggo | CC0 | 2 |
| Freesound: [Breathless Coughing_2](https://freesound.org/people/Drkvixn91/sounds/317439/), [Echoing Laughter](https://freesound.org/people/Drkvixn91/sounds/317479/) | Drkvixn91 | CC0 | 5 |
| Freesound: [GruntM.ogg](https://freesound.org/people/egomassive/sounds/536751/), [MoanM.ogg](https://freesound.org/people/egomassive/sounds/536798/) | egomassive | CC0 | 2 |
| Freesound: [Male Attack Grunt](https://freesound.org/people/elynch0901/sounds/464485/) | elynch0901 | CC0 | 1 |
| Freesound: [Burp Monster Zombie groan moan](https://freesound.org/people/EricsSoundschmiede/sounds/463721/) | EricsSoundschmiede | CC0 | 1 |
| Freesound: [Bubbles.wav](https://freesound.org/people/erkanozan/sounds/51745/) | erkanozan | CC0 | 1 |
| Freesound: [Pyorremyrsky.mp3](https://freesound.org/people/ertzsi/sounds/620533/) | ertzsi | CC0 | 5 |
| Freesound: [Hmm question.wav](https://freesound.org/people/esperar/sounds/170768/), [OneHmm-question.wav](https://freesound.org/people/esperar/sounds/170779/) | esperar | CC0 | 2 |
| Freesound: [57aguila.wav](https://freesound.org/people/fabianacarmonas/sounds/491462/) | fabianacarmonas | CC0 | 1 |
| Freesound: [BREATHING.mp3](https://freesound.org/people/fmarcond/sounds/656753/) | fmarcond | CC0 | 1 |
| Freesound: [cry.wav](https://freesound.org/people/galora/sounds/319019/) | galora | CC0 | 1 |
| Freesound: [satisfiedSigh.wav](https://freesound.org/people/garynoden/sounds/334061/) | garynoden | CC0 | 1 |
| Freesound: [dogs-howling-yelping-distance-far-08.wav](https://freesound.org/people/Gerent/sounds/558726/) | Gerent | CC0 | 2 |
| Freesound: [bubble1.wav](https://freesound.org/people/Godowan/sounds/235264/), [wings2.wav](https://freesound.org/people/Godowan/sounds/240469/), [wings.wav](https://freesound.org/people/Godowan/sounds/240476/) | Godowan | CC0 | 3 |
| Freesound: [Hmmmm! (Male)](https://freesound.org/people/GotSka81/sounds/275808/) | GotSka81 | CC0 | 1 |
| Freesound: [Eagle s.mp3](https://freesound.org/people/GrayEpic/sounds/697363/) | GrayEpic | CC0 | 1 |
| Freesound: [Dog death cry - video game quality / bad-ish quality](https://freesound.org/people/greyfeather/sounds/724927/) | greyfeather | CC0 | 1 |
| Freesound: [Small Dog Cry](https://freesound.org/people/haulaway/sounds/735365/) | haulaway | CC0 | 1 |
| Freesound: [hum1.wav](https://freesound.org/people/henriquedesa/sounds/251706/) | henriquedesa | CC0 | 1 |
| Freesound: [Eris, Pain, Shout Long, Cry, Wail_2.wav](https://freesound.org/people/hisoul/sounds/520267/), [Zisa, Pain to Death, Groan Long, Whisper, Hoarse, Bizarre_1.wav](https://freesound.org/people/hisoul/sounds/520274/) | hisoul | CC0 | 2 |
| Freesound: [fire-whoosh.wav](https://freesound.org/people/hnhnh/sounds/244926/) | hnhnh | CC0 | 8 |
| Freesound: [Grunting In Gas Mask](https://freesound.org/people/Hoggington/sounds/536599/) | Hoggington | CC0 | 1 |
| Freesound: [Bubbles](https://freesound.org/people/hotpin7/sounds/840042/) | hotpin7 | CC0 | 1 |
| Freesound: [WindHowl4](https://freesound.org/people/Huglex/sounds/848579/) | Huglex | CC0 | 6 |
| Freesound: [growling.wav](https://freesound.org/people/hy96/sounds/48176/) | hy96 | CC0 | 1 |
| Freesound: [Suspiro Tristeza.wav](https://freesound.org/people/IanLyanx/sounds/446768/) | IanLyanx | CC0 | 1 |
| Freesound: [groans.wav](https://freesound.org/people/iggy1345/sounds/103072/) | iggy1345 | CC0 | 2 |
| Freesound: [man scream.ogg](https://freesound.org/people/insanity54/sounds/203594/) | insanity54 | CC0 | 1 |
| Freesound: [inhale](https://freesound.org/people/inseedee/sounds/394732/) | inseedee | CC0 | 1 |
| Freesound: [poujade_eva_2020_2021_RoarOfLion(son2).wav](https://freesound.org/people/iut_Paris8/sounds/567803/) | iut_Paris8 | CC0 | 1 |
| Freesound: [Male long groan.mp3](https://freesound.org/people/Ivan_Bjorkman/sounds/457449/), [Male long groan hIgher reverb.mp3](https://freesound.org/people/Ivan_Bjorkman/sounds/457450/) | Ivan_Bjorkman | CC0 | 2 |
| Freesound: [Dog_Bark.wav](https://freesound.org/people/ivolipa/sounds/328729/) | ivolipa | CC0 | 1 |
| Freesound: [bushhit.wav](https://freesound.org/people/j1987/sounds/106113/), [bushmovement.wav](https://freesound.org/people/j1987/sounds/106114/), [carrotnom.wav](https://freesound.org/people/j1987/sounds/106392/) | j1987 | CC0 | 3 |
| Freesound: [Cow - Moan 2 - 96kHz.wav](https://freesound.org/people/JarredGibb/sounds/233146/), [Pig - Multiple Snorts 4 - 96kHz.wav](https://freesound.org/people/JarredGibb/sounds/233181/), [Pig - Multiple Snorts 3 (2 pigs) - 96kHz.wav](https://freesound.org/people/JarredGibb/sounds/233182/) | JarredGibb | CC0 | 3 |
| Freesound: [Screeching Creature 1_4](https://freesound.org/people/Joao_Janz/sounds/482364/) | Joao_Janz | CC0 | 1 |
| Freesound: [Middle Ages War Cry.wav](https://freesound.org/people/joelcarrsound/sounds/521830/), [Middle Ages War Cry 3.wav](https://freesound.org/people/joelcarrsound/sounds/521831/), [Middle Ages War Cry 2.wav](https://freesound.org/people/joelcarrsound/sounds/521832/) | joelcarrsound | CC0 | 3 |
| Freesound: [Water Bubbling or Gargling](https://freesound.org/people/Jofae/sounds/363150/) | Jofae | CC0 | 1 |
| Freesound: [Injury scream](https://freesound.org/people/joseppujol/sounds/221543/), [Wounded man scream](https://freesound.org/people/joseppujol/sounds/221544/), [Yell EEEH](https://freesound.org/people/joseppujol/sounds/221546/) | joseppujol | CC0 | 3 |
| Freesound: [2 hmm ovejita.wav.wav](https://freesound.org/people/Julalvr/sounds/429923/) | Julalvr | CC0 | 1 |
| Freesound: [ahogarse.wav](https://freesound.org/people/juliandmc4/sounds/443560/), [grito ira.wav](https://freesound.org/people/juliandmc4/sounds/443653/) | juliandmc4 | CC0 | 2 |
| Freesound: [Enemy hurt 1](https://freesound.org/people/K27K_Mike/sounds/853659/) | K27K_Mike | CC0 | 1 |
| Freesound: [Male Groan in Exhaustion](https://freesound.org/people/kanyonwyvern/sounds/736662/) | kanyonwyvern | CC0 | 1 |
| Freesound: [Eagle Cry.wav](https://freesound.org/people/kaydinhamby/sounds/381200/) | kaydinhamby | CC0 | 1 |
| Freesound: [evil laugh.wav](https://freesound.org/people/kintana24/sounds/478934/) | kintana24 | CC0 | 2 |
| Freesound: [Panic-stricken screaming #2](https://freesound.org/people/Klangkobold/sounds/547964/) | Klangkobold | CC0 | 1 |
| Freesound: [rumble.wav](https://freesound.org/people/kovrov/sounds/105308/) | kovrov | CC0 | 1 |
| Freesound: [bark yelp dog small int.flac](https://freesound.org/people/kyles/sounds/452180/) | kyles | CC0 | 1 |
| Freesound: [Gurgling Water](https://freesound.org/people/L.i.Z.e.L.l.E_%2B/sounds/707862/) | L.i.Z.e.L.l.E_+ | CC0 | 1 |
| Freesound: [05-Hmm1.mp3](https://freesound.org/people/lauracarolina09/sounds/445872/), [20- Hmm2Hombre 2.wav](https://freesound.org/people/lauracarolina09/sounds/445934/) | lauracarolina09 | CC0 | 2 |
| Freesound: [01C#0_Om-Elo.wav](https://freesound.org/people/livepiano/sounds/420917/) | livepiano | CC0 | 1 |
| Freesound: [Basic Fire whoosh](https://freesound.org/people/LookIMadeAThing/sounds/260554/), [Basic Fire whoosh 3](https://freesound.org/people/LookIMadeAThing/sounds/260584/) | LookIMadeAThing | CC0 | 15 |
| Freesound: [enemy death.mp3](https://freesound.org/people/Loyalty_Freak_Music/sounds/407474/) | Loyalty_Freak_Music | CC0 | 1 |
| Freesound: [monster bite](https://freesound.org/people/LucasDuff/sounds/467701/) | LucasDuff | CC0 | 1 |
| Freesound: [Bird - Pajaro 5.ogg](https://freesound.org/people/Lunevix/sounds/581314/) | Lunevix | CC0 | 1 |
| Freesound: [Horse ](https://freesound.org/people/madklown/sounds/184503/) | madklown | CC0 | 2 |
| Freesound: [Wooden Creak](https://freesound.org/people/Mafon2/sounds/377552/) | Mafon2 | CC0 | 1 |
| Freesound: [muahaha Evil Laughter](https://freesound.org/people/ManuelGraf/sounds/332627/) | ManuelGraf | CC0 | 1 |
| Freesound: [man-screaming.wav](https://freesound.org/people/mariateresa_garcia/sounds/219719/) | mariateresa_garcia | CC0 | 1 |
| Freesound: [sigh.mp3](https://freesound.org/people/mariiao2/sounds/240689/) | mariiao2 | CC0 | 1 |
| Freesound: [Giant Insect Monster roaring sound](https://freesound.org/people/Mastersoundboy2005/sounds/726877/), [Demonic horse whinny sound effect](https://freesound.org/people/Mastersoundboy2005/sounds/769937/) | Mastersoundboy2005 | CC0 | 3 |
| Freesound: [Stein Aufschlag mit langem Decay 10.wav](https://freesound.org/people/mbezzola/sounds/105287/) | mbezzola | CC0 | 1 |
| Freesound: [female evil laughter.wav](https://freesound.org/people/Me_Is_Chaos/sounds/275652/) | Me_Is_Chaos | CC0 | 1 |
| Freesound: [ManlySounds01.wav](https://freesound.org/people/melisandepope/sounds/557134/), [Haha01.wav](https://freesound.org/people/melisandepope/sounds/572606/) | melisandepope | CC0 | 2 |
| Freesound: [fadein_choir.wav](https://freesound.org/people/metmass/sounds/123077/), [fadein_choir_v2.wav](https://freesound.org/people/metmass/sounds/123078/) | metmass | CC0 | 2 |
| Freesound: [male_hurt9.ogg](https://freesound.org/people/micahlg/sounds/413186/) | micahlg | CC0 | 1 |
| Freesound: [exasperation_3.wav](https://freesound.org/people/Mickael_Leroi/sounds/402124/), [exasperation_1.wav](https://freesound.org/people/Mickael_Leroi/sounds/402126/) | Mickael_Leroi | CC0 | 2 |
| Freesound: [Hooded Crow: Panic Cawing](https://freesound.org/people/Mish7913/sounds/741365/) | Mish7913 | CC0 | 1 |
| Freesound: [Female scream 02](https://freesound.org/people/missozzy/sounds/169811/) | missozzy | CC0 | 1 |
| Freesound: [Dog bark2.wav](https://freesound.org/people/MisterTood/sounds/9032/) | MisterTood | CC0 | 1 |
| Freesound: [Woman Exasperated Sigh, Breathe Out](https://freesound.org/people/monsterthing/sounds/663651/) | monsterthing | CC0 | 1 |
| Freesound: [The Rustle of a Bush](https://freesound.org/people/Montacue/sounds/178615/) | Montacue | CC0 | 1 |
| Freesound: [Voice_AdultMale_PainGrunts_09.wav](https://freesound.org/people/MrFossy/sounds/547209/) | MrFossy | CC0 | 1 |
| Freesound: [Barking 4.wav](https://freesound.org/people/Mrthenoronha/sounds/420447/) | Mrthenoronha | CC0 | 1 |
| Freesound: [Stone Push](https://freesound.org/people/msavioti/sounds/558216/) | msavioti | CC0 | 1 |
| Freesound: [Demonic Woman Scream.wav](https://freesound.org/people/nick121087/sounds/333832/) | nick121087 | CC0 | 1 |
| Freesound: [Scary Monster Roar #2](https://freesound.org/people/NicknameLarry/sounds/489901/) | NicknameLarry | CC0 | 1 |
| Freesound: [Laugh](https://freesound.org/people/Nicolas4677/sounds/446584/) | Nicolas4677 | CC0 | 1 |
| Freesound: [Evil Laugh_1.wav](https://freesound.org/people/NinjaSharkStudios/sounds/646307/) | NinjaSharkStudios | CC0 | 1 |
| Freesound: [Piedras en reja 03.08.22 10.09 am.wav](https://freesound.org/people/NZ_A2/sounds/647077/) | NZ_A2 | CC0 | 1 |
| Freesound: [Horse(snort)_3.wav](https://freesound.org/people/o_ciz/sounds/475483/) | o_ciz | CC0 | 2 |
| Freesound: [laugh7.wav](https://freesound.org/people/ondrosik/sounds/207797/) | ondrosik | CC0 | 2 |
| Freesound: [Inhale_10115a.wav](https://freesound.org/people/otherthings/sounds/65620/) | otherthings | CC0 | 1 |
| Freesound: [Zombie Groan 0](https://freesound.org/people/OwNathan/sounds/754438/), [Zombie Groan 3](https://freesound.org/people/OwNathan/sounds/754441/) | OwNathan | CC0 | 2 |
| Freesound: [moving stone platform.wav](https://freesound.org/people/patchytherat/sounds/530988/) | patchytherat | CC0 | 1 |
| Freesound: [Slap With Male Moan.wav](https://freesound.org/people/Paul368/sounds/264064/) | Paul368 | CC0 | 1 |
| Freesound: [Mixed Whip Crack 1.wav](https://freesound.org/people/peterbullmusic/sounds/351267/) | peterbullmusic | CC0 | 1 |
| Freesound: [harp pluck grave](https://freesound.org/people/PhonosUPF/sounds/490841/), [harp pluck 3](https://freesound.org/people/PhonosUPF/sounds/490979/) | PhonosUPF | CC0 | 2 |
| Freesound: [Horse](https://freesound.org/people/poodaddy69/sounds/521246/) | poodaddy69 | CC0 | 2 |
| Freesound: [A_Character_Effort09](https://freesound.org/people/Potapooo/sounds/714591/) | Potapooo | CC0 | 1 |
| Freesound: [evil man laughing.wav](https://freesound.org/people/ptrmax/sounds/134720/) | ptrmax | CC0 | 1 |
| Freesound: [Grunt.wav](https://freesound.org/people/punisherman/sounds/370036/) | punisherman | CC0 | 1 |
| Freesound: [dyingBeast](https://freesound.org/people/QuantumFellow/sounds/734841/) | QuantumFellow | CC0 | 1 |
| Freesound: [Goblin Snarl](https://freesound.org/people/qubodup/sounds/442815/), [Goblin Scream](https://freesound.org/people/qubodup/sounds/442816/), [Goblin Growl](https://freesound.org/people/qubodup/sounds/442817/), [Dragon Hurt](https://freesound.org/people/qubodup/sounds/442966/), [Strong Double Cough](https://freesound.org/people/qubodup/sounds/743360/) | qubodup | CC0 | 5 |
| Freesound: [WAIL PAD 9.wav](https://freesound.org/people/QVL/sounds/609691/) | QVL | CC0 | 1 |
| Freesound: [Death cry](https://freesound.org/people/randbsoundbites/sounds/795690/), [A male sigh](https://freesound.org/people/randbsoundbites/sounds/799579/) | randbsoundbites | CC0 | 2 |
| Freesound: [Female Laugh.wav](https://freesound.org/people/rdneubauer/sounds/93775/) | rdneubauer | CC0 | 1 |
| Freesound: [yell laugh.wav](https://freesound.org/people/Reitanna/sounds/235119/), [hiss.wav](https://freesound.org/people/Reitanna/sounds/241562/), [long sigh.wav](https://freesound.org/people/Reitanna/sounds/242907/), [YEOW!.wav](https://freesound.org/people/Reitanna/sounds/324856/), [hiss2.wav](https://freesound.org/people/Reitanna/sounds/343927/), [hiss3.wav](https://freesound.org/people/Reitanna/sounds/343928/), [four coughs.wav](https://freesound.org/people/Reitanna/sounds/343986/), [crazy crying.wav](https://freesound.org/people/Reitanna/sounds/344030/) | Reitanna | CC0 | 8 |
| Freesound: [Death sound (male)](https://freesound.org/people/Replix/sounds/173126/) | Replix | CC0 | 1 |
| Freesound: [Hurt_Dying](https://freesound.org/people/Rickplayer/sounds/533840/) | Rickplayer | CC0 | 1 |
| Freesound: [old man cough](https://freesound.org/people/riippumattog/sounds/848383/), [cough choking on spit](https://freesound.org/people/riippumattog/sounds/866631/) | riippumattog | CC0 | 2 |
| Freesound: [Bubbles 004.wav](https://freesound.org/people/ristooooo1/sounds/539819/) | ristooooo1 | CC0 | 1 |
| Freesound: [Scream RM.mp3](https://freesound.org/people/RobertaMotta/sounds/359130/) | RobertaMotta | CC0 | 1 |
| Freesound: [Angry Grunt](https://freesound.org/people/Rocotilos/sounds/341489/) | Rocotilos | CC0 | 1 |
| Freesound: [Wood Creak Single V1](https://freesound.org/people/Rudmer_Rotteveel/sounds/502505/) | Rudmer_Rotteveel | CC0 | 1 |
| Freesound: [Sounds For Earthquakes - Wood 2.wav](https://freesound.org/people/RutgerMuller/sounds/51122/) | RutgerMuller | CC0 | 1 |
| Freesound: [Kvist 1.wav](https://freesound.org/people/Ryding/sounds/94356/) | Ryding | CC0 | 1 |
| Freesound: [thunder4.wav](https://freesound.org/people/saha213131/sounds/690194/) | saha213131 | CC0 | 1 |
| Freesound: [Renill de cavall / Horse Neigh](https://freesound.org/people/Salsero_classic/sounds/826753/) | Salsero_classic | CC0 | 2 |
| Freesound: [Man sighs in frustration.m4a](https://freesound.org/people/sandralaughs/sounds/519201/) | sandralaughs | CC0 | 2 |
| Freesound: [Laughter](https://freesound.org/people/schots/sounds/452749/) | schots | CC0 | 1 |
| Freesound: [Snake hissing.mp3](https://freesound.org/people/schreibsel/sounds/540162/) | schreibsel | CC0 | 1 |
| Freesound: [Whip Crack.m4a](https://freesound.org/people/SciFiSounds/sounds/529925/) | SciFiSounds | CC0 | 1 |
| Freesound: [Rotten Zombie Death](https://freesound.org/people/scorpion67890/sounds/151710/), [Male Death 4](https://freesound.org/people/scorpion67890/sounds/396801/) | scorpion67890 | CC0 | 2 |
| Freesound: [Small dog.wav](https://freesound.org/people/ScouseMouseJB/sounds/351876/) | ScouseMouseJB | CC0 | 2 |
| Freesound: [lion.wav](https://freesound.org/people/SGAK/sounds/467762/) | SGAK | CC0 | 1 |
| Freesound: [horse neigh shortened.wav](https://freesound.org/people/shadoWisp/sounds/269571/) | shadoWisp | CC0 | 2 |
| Freesound: [lion.wav](https://freesound.org/people/shakezerz/sounds/684527/) | shakezerz | CC0 | 1 |
| Freesound: [Woooooo_TreasureIsland](https://freesound.org/people/sierra721/sounds/718952/) | sierra721 | CC0 | 1 |
| Freesound: [Mysterious Sparkle Flourish](https://freesound.org/people/SkySpeira/sounds/844398/) | SkySpeira | CC0 | 3 |
| Freesound: [Lighter.mp3](https://freesound.org/people/SomeoneCool15/sounds/423777/) | SomeoneCool15 | CC0 | 6 |
| Freesound: [Horn at parade](https://freesound.org/people/SoundsAreGr8/sounds/340972/) | SoundsAreGr8 | CC0 | 1 |
| Freesound: [Heavy Breath - 1.wav](https://freesound.org/people/SpaceJoe/sounds/485684/) | SpaceJoe | CC0 | 1 |
| Freesound: [Acid Bubbling.wav](https://freesound.org/people/spookymodem/sounds/202094/), [Goblin Cackle.wav](https://freesound.org/people/spookymodem/sounds/202096/), [Goblin Death.wav](https://freesound.org/people/spookymodem/sounds/249813/) | spookymodem | CC0 | 9 |
| Freesound: [anger](https://freesound.org/people/ssierra1202/sounds/391939/), [huh? - male voice](https://freesound.org/people/ssierra1202/sounds/391967/) | ssierra1202 | CC0 | 2 |
| Freesound: [Man dies](https://freesound.org/people/starkvind/sounds/559975/) | starkvind | CC0 | 1 |
| Freesound: [Seagull single call](https://freesound.org/people/steaq/sounds/263786/) | steaq | CC0 | 1 |
| Freesound: [Man screams in pain.mp3](https://freesound.org/people/stuxer/sounds/401210/) | stuxer | CC0 | 1 |
| Freesound: [ghost moan.mp3](https://freesound.org/people/SuperGirl71/sounds/319186/) | SuperGirl71 | CC0 | 1 |
| Freesound: [Girl_Scream_Short.wav](https://freesound.org/people/tcrocker68/sounds/235590/), [Girl_Scream_FollowingScreams.wav](https://freesound.org/people/tcrocker68/sounds/235591/), [Girl_Scream.wav](https://freesound.org/people/tcrocker68/sounds/235592/) | tcrocker68 | CC0 | 4 |
| Freesound: [Male Death Scream](https://freesound.org/people/Thanra/sounds/178313/) | Thanra | CC0 | 1 |
| Freesound: [cig_extinguish.wav](https://freesound.org/people/the_semen_incident/sounds/155660/), [demon_belch.wav](https://freesound.org/people/the_semen_incident/sounds/56905/) | the_semen_incident | CC0 | 10 |
| Freesound: [breath taken aback.flac](https://freesound.org/people/TheCurlyOne/sounds/434550/) | TheCurlyOne | CC0 | 1 |
| Freesound: [Reptiles - Snake; Mexican Black Kingsnake, Short Hiss and Lunge](https://freesound.org/people/TheKingOfGeeks360/sounds/846337/), [Reptiles - Snake; Timber Rattlesnake, Rattle, Close Perspective](https://freesound.org/people/TheKingOfGeeks360/sounds/855914/), [Horses - Snort; Distant](https://freesound.org/people/TheKingOfGeeks360/sounds/868302/), [Mules - Mule; Neigh and Short Bray, Take 2](https://freesound.org/people/TheKingOfGeeks360/sounds/868304/) | TheKingOfGeeks360 | CC0 | 6 |
| Freesound: [woman sigh](https://freesound.org/people/threadzz/sounds/384992/) | threadzz | CC0 | 1 |
| Freesound: [Generic roar 2.wav](https://freesound.org/people/Tmd17/sounds/411756/) | Tmd17 | CC0 | 1 |
| Freesound: [Girl Screaming_01.wav](https://freesound.org/people/tomattka/sounds/400183/), [Girl's Laugh](https://freesound.org/people/tomattka/sounds/402395/) | tomattka | CC0 | 2 |
| Freesound: [wings flapping.wav](https://freesound.org/people/tommy_mooney/sounds/386706/) | tommy_mooney | CC0 | 1 |
| Freesound: [Defeated_Hellpig.wav](https://freesound.org/people/TomRonaldmusic/sounds/607202/) | TomRonaldmusic | CC0 | 1 |
| Freesound: [11-suspiro 2.wav](https://freesound.org/people/Tomycatts/sounds/429326/) | Tomycatts | CC0 | 1 |
| Freesound: [Male_Scream_9.wav](https://freesound.org/people/tonsil5/sounds/416546/), [Zombie Pain 2.wav](https://freesound.org/people/tonsil5/sounds/555423/) | tonsil5 | CC0 | 6 |
| Freesound: [gasp.mp3](https://freesound.org/people/Topschool/sounds/360469/) | Topschool | CC0 | 1 |
| Freesound: [Large Wings Flapping - Foley.wav](https://freesound.org/people/tothrec2/sounds/596541/) | tothrec2 | CC0 | 3 |
| Freesound: [Tunnel laugh](https://freesound.org/people/TreyHolton/sounds/252018/) | TreyHolton | CC0 | 1 |
| Freesound: [Grunt Sound Hurrrr](https://freesound.org/people/uigi/sounds/640259/) | uigi | CC0 | 1 |
| Freesound: [Man Dying](https://freesound.org/people/Under7dude/sounds/163442/) | Under7dude | CC0 | 1 |
| Freesound: [Human_groan_female 02.mp3](https://freesound.org/people/Vaporpup/sounds/570115/), [jaguar_growl_roar.wav](https://freesound.org/people/Vaporpup/sounds/571287/) | Vaporpup | CC0 | 2 |
| Freesound: [Weird crazy laugh](https://freesound.org/people/vibritherabjit123/sounds/652030/) | vibritherabjit123 | CC0 | 1 |
| Freesound: [GROANING.wav](https://freesound.org/people/vmgraw/sounds/257706/), [GRUNT 2.wav](https://freesound.org/people/vmgraw/sounds/257709/), [GRUNT 1.wav](https://freesound.org/people/vmgraw/sounds/257710/) | vmgraw | CC0 | 4 |
| Freesound: [Hmm RTS Select Male NPC](https://freesound.org/people/VSE00/sounds/867879/) | VSE00 | CC0 | 1 |
| Freesound: [Bite (Apple)](https://freesound.org/people/wadaltmon/sounds/275015/) | wadaltmon | CC0 | 1 |
| Freesound: [Dog.wav](https://freesound.org/people/Weak_Hero/sounds/612858/) | Weak_Hero | CC0 | 1 |
| Freesound: [grunting](https://freesound.org/people/Wellorok/sounds/758044/) | Wellorok | CC0 | 2 |
| Freesound: [Ice crackles under pressure](https://freesound.org/people/Wigglesworth/sounds/838106/) | Wigglesworth | CC0 | 1 |
| Freesound: [Steam/hiss](https://freesound.org/people/wubitog/sounds/234782/) | wubitog | CC0 | 2 |
| Freesound: [Pig_Grunt_02.flac](https://freesound.org/people/wwstudioswastaken/sounds/612679/), [ice_cracking_01.flac](https://freesound.org/people/wwstudioswastaken/sounds/624163/) | wwstudioswastaken | CC0 | 2 |
| Freesound: [Short Oww](https://freesound.org/people/Xcallono/sounds/457280/) | Xcallono | CC0 | 1 |
| Freesound: [Bird_Cherp_42.wav](https://freesound.org/people/xFromarge1/sounds/509321/) | xFromarge1 | CC0 | 1 |
| Freesound: [Snake Hiss](https://freesound.org/people/xoiziox/sounds/553374/) | xoiziox | CC0 | 1 |
| Freesound: [Spooky Singing Choir](https://freesound.org/people/xSylviaMoonx/sounds/147881/) | xSylviaMoonx | CC0 | 1 |
| Freesound: [UGGGGHHHH...](https://freesound.org/people/yehdawgo/sounds/720074/) | yehdawgo | CC0 | 1 |
| Freesound: [Man Scream1.wav](https://freesound.org/people/Yu_De/sounds/445008/) | Yu_De | CC0 | 1 |
| Freesound: [Fire Burst Flash](https://freesound.org/people/Za-Games/sounds/539972/) | Za-Games | CC0 | 7 |
| Freesound: [Hisss 2.m4a](https://freesound.org/people/Zeval34/sounds/578484/) | Zeval34 | CC0 | 2 |
| Freesound: [z-moo01.wav](https://freesound.org/people/Zozzy/sounds/59245/) | Zozzy | CC0 | 1 |

<!-- voices:end -->

## AI-generated art (disclosed)
Card, hero, arena and card-back images in assets/cards/ and assets/arenas/ are AI-generated on the owner's own ComfyUI
with **Qwen-Image 2512** (Apache-2.0) + the Lightning 4-step LoRA (Apache-2.0). Prompts: data/cards.json (`art`) and
the ComfyUI session's notes (status/cards_style.md). House style: hand-tinted Gustave Dore-style engraving, chosen by the
owner on 2026-10-25. Source files: art_src/dore_cards/; card -> image map: the "image" field in data/cards.json.
The painted UI parts in assets/ui/ (card borders, ribbon, gems, rarity cabochons, button plate, end-turn seal, power disc,
icons, card text plates, the headline lettering in assets/ui/words/, Virgil's portrait, the deck tags and class
emblem frame, the app icon in assets/icon.png and assets/app_icon/) and
the painted VFX sprites in assets/vfx/ (every file not named k_*) come from the
same ComfyUI setup (Qwen-Image 2512, alpha cut with BiRefNet, MIT); sources in art_src/ui/ (the lettering on black is
keyed to alpha by tools/ui/make_words.py). The vfx_*.png spell sprites
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
