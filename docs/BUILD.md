# Build

`G=C:/Progetti/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe` (always run it with a `timeout`).

```sh
timeout 300 $G --headless --path . -s res://tests/run_tests.gd        # rules + AI soak
timeout 120 $G --headless --path . -s res://tests/run_tests.gd -- --only=lessons   # just Virgil's lessons
timeout 900 $G --headless --path . -s res://tests/fuzz_rules.gd -- --games=200 --first=0   # rules fuzzer: invariants, replays, probes (shard with --first; --cards plays every card in odd spots; --game=N --verbose reruns one)
timeout 240 $G --headless --path . res://tests/ui_smoke.tscn          # input smoke test
timeout 300 $G --headless --path . res://tests/menu_smoke.tscn        # menu dialogs, pack opening, deck problems, lessons flow
timeout 300 $G --headless --path . res://tests/intro_test.tscn        # opening cinematic data + player + skip
timeout 3600 $G --headless --path . -s res://tests/card_flow.gd -- --games=60 [--deck=<id>] [--shard=i/k --out=f.json]  # per deck: hand size by turn, topdecking, unspent mana, fatigue, win rate (Hard vs Hard); --cards per-card play rates; --merge=a.json,b.json sums shards; --patch=f.json tries deck swaps
timeout 180 $G --path . res://tests/ink_centering.tscn --resolution 1920x1080 -- --out=<dir> --max=2   # text centred in its frames, on drawn pixels (needs a window)
timeout 900 $G --path . res://tests/rules_centering.tscn --resolution 1920x1080 -- --out=<dir> --max=2 # every card's rules text on its parchment, clear of the gems (needs a window)
timeout 600 $G --headless --path . --export-release "Windows Desktop" build/windows/DantesInfernoCards.exe
timeout 600 $G --headless --path . --export-debug   "Android"         build/android/DantesInfernoCards.apk
```

Android toolchain (installed 2026-10-25, portable, no admin):
- JDK 17 (Temurin): `C:/Progetti/Tools/jdk17`, set as `export/android/java_sdk_path` in the Godot editor settings
  (backup of the old file: `editor_settings-4.7.tres.bak_dantescards`).
- Android SDK: `%LOCALAPPDATA%/Android/Sdk` with cmdline-tools, platform-tools, build-tools 35.0.0, platforms android-35.
- The APK is signed with Godot's **debug** keystore: fine for installing on your own phone (`adb install -r ...`, or copy
  the file and open it). A store release needs a release keystore (not created yet).

Other presets (Linux, Web, macOS) are defined in `export_presets.cfg`. macOS / iOS need signing on a Mac.

Debug flags (after `--`): `--autoplay` (AI plays both sides), `--shots=<dir>` (battle screenshots every 3 s),
`--snap=<file.png> [--snap-delay=s]` (one screenshot of any scene). Battle only: `--arena=<id>` forces an arena (without
its painted board it is shown on the Acheron board), `--shot-every=s`, `--shot-count=N`, `--poke-toys=s` (taps every
arena toy and the divider after s seconds). `--offer-lessons` asks the first-launch "New to Hell?" question on the
title screen even in a debug run or for a player who was already asked.
Headless runs, `--autoplay`, `--snap=`, `--shots=`, `--out=`, `--intro-shots=` and any scene or script under
`res://tests/` are debug runs (`Game.debug_run()`): no intro, no coach tips, and nothing is written to the player's
settings, progress or collection.

## Updates (patch packs inside the game)

How it works: docs/DESIGN.md, "In-game updates". Every release on GitHub must carry `update.json` (the game reads the
latest release's), the full downloads, and one patch per kept base and platform
(`patch-<base>-to-<version>-<windows|android>.pck`).

Once (done 2026-10-30): the signing key pair. The private key never goes in the repository, a log or a chat:
```sh
timeout 300 $G --headless --path . -s res://tools/update/update_tool.gd -- keygen --private=C:/Servers/dantes_update_key.pem
```
(it refuses to overwrite; a new pair needs a full build, since the shipped public key checks every update).

Each release, from the main checkout (it has config/online.local.cfg; a patch exported without it would delete it
from the players' game, and `check` refuses such a patch):
1. Bump `config/version` in project.godot and `version/name` + `version/code` in the Android preset; commit.
2. Run the tests (`run_tests`, `ui_smoke`, `menu_smoke`).
3. `powershell -ExecutionPolicy Bypass -File tools/update/make_update.ps1` (add `-FullRequired -Reason "..."` when
   the release must be a full download, `-Bases 0.9.4,0.9.5` to choose the bases, `-SkipExport` to reuse the builds
   already in build/). It exports the exe and the APK, keeps them as this version's base in
   `build/update_bases/<version>/` (back that folder up), exports a patch over every earlier base whose engine and
   guarded files (project.godot, export_presets.cfg, update_boot.gd, the public key: version lines aside) did not
   change, checks each patch, writes `build/release/<version>/update.json` signed with the private key and verifies
   it with the committed public key. Every Godot run in it has a timeout.
4. Publish with the `gh release create` line it prints (all files of `build/release/<version>/`).

The first release with the updater (0.9.4) has no earlier base: it is a full download, and its own base makes 0.9.5
onwards a patch. A base lost from `build/update_bases/` can be rebuilt from its release: put its exe (from the zip)
and APK in `build/update_bases/<v>/`, run
`timeout 900 $G --headless --path . -s res://tools/update/update_tool.gd -- apk-base --apk=build/update_bases/<v>/DantesInfernoCards.apk --out=build/update_bases/<v>/android.pck`
and write its `base.json` (`{"version", "engine", "commit", "code"}`). The exe works as a base as it is (its pack is
embedded); a sparse APK pack does not, hence `apk-base`.

Tool commands (all `$G --headless --path . -s res://tools/update/update_tool.gd -- <command>`, with a timeout):
`pck-list --pck=<pck or exe> [--all]` (files, and the ones a patch removes), `check --pck=<patch>`,
`manifest --dir=<release folder> --version=<v> --code=<n> --key=<private key> [--full-required --reason=<text>]`,
`verify --in=<update.json>`, `apk-base --apk=<apk> --out=<pck>`.

Trial without GitHub (debug builds only; release builds ignore these flags, and the manifest must still be signed):
export a base with `--export-debug "Windows Desktop" <dir>/DantesInfernoCards.exe`, change something, export
`--export-patch "Windows Desktop" <srv>/patch-<base>-to-<v>-windows.pck --patches <dir>/DantesInfernoCards.exe`, sign
it with `manifest --dir=<srv> --version=<v> ...`, then run
`<dir>/DantesInfernoCards.exe -- --update-source=<srv> --update-dir=<folder> --update-yes --update-shots=<shots>`:
it offers, downloads, installs and restarts by itself (`--update-shots` saves each dialog). `--update-dir` alone runs
the installed update from that folder. Tests: `run_tests.gd -- --only=updates` (signatures, tampering, hashes, stale
bases, cleaning; a throwaway key).

## Online play
The server settings live in **`config/online.local.cfg`** (gitignored, never committed; the exports pack it through
`config/*.cfg` in every preset's `include_filter`). `user://online.cfg` overrides it per install, and
`-- --online-config=<path>` reads one more file (tests, a worktree without the file). INI, values bare or quoted:

```ini
[online]
server_key = <Nakama server key>
host = complexserver.tail05d1ab.ts.net   ; the public Tailscale Funnel host
port = 8443
scheme = https             ; https -> the socket is wss (system CA certificates, TLSOptions.client())
fallback_host = 100.80.41.96              ; optional: the tailnet address, tried when the first one
fallback_port = 7450                      ;   does not answer its healthcheck within 4 s
fallback_scheme = http
google_client_id = ...     ; optional: Google sign-in (device-code flow); no id, no Google button
google_client_secret = ...
```

Without a `server_key` (or host) the game runs offline and Play online says that online play is not set up. The key
is never printed in the log.

Tests (the online smoke is not part of run_tests: it needs the live server):
```sh
timeout 120 $G --headless --path . -s res://tests/run_tests.gd -- --only=online   # the mirror test alone
timeout 300 $G --headless --path . res://tests/online_smoke.tscn -- --online-config=C:/Progetti/DantesCards/config/online.local.cfg
```
The smoke runs two clients in one process (device accounts of profiles 900 / 901): matchmaking, START, chat, the
mulligan, a few turns of Easy-AI moves with the checksums compared, one client dropped and rejoined (the RESYNC
rebuild must match), a ping, the app-resume check and a session renewal that must keep the duel's socket, the other
client's socket dropped under it so the session rejoins by itself (the RESYNC clock must be within turn + rope), a
concession and END on both, and a late join of the finished duel refused as "That duel has already ended." It also checks the cloud save on the test accounts: a progress
blob written and read back the same, a stale write refused as a version conflict, and the session's own sync (merge
after sign-in, no write without changes, re-merge after a conflict). In debug runs `OnlineSession.apply` writes no
file (the blob goes to `last_applied`), and the sync only runs when a test sets `cloud_forced`.

Two players on one PC: every `-- --online-profile=N` has its own device id (`user://online_device_N.txt`, so its own
account) and record; its name gets " N". Run two windows, e.g.
`$G --path . -- --online-profile=1` and `$G --path . -- --online-profile=2`, and press Play online in both.
Debug: `--online-quick=<deck id>` opens the search at once from the title screen, `--online-shots=<dir>` saves the
search and versus screens, `--chat-open` opens the battle's chat panel, `--google-signin` opens the profile with
Google's sign-in code (it asks Google for a real code); with `--shots=<dir>` (autoplay) an Easy AI plays the online
battle through the server. A
bot opponent: `timeout 900 $G --headless --path . res://tests/online_smoke.tscn -- --bot [--idle-turn=4]` (it sits
out turn 4 or 5, so the rope burns).

Character voices (assets/audio/voices/, see "Character voices" in docs/DESIGN.md), always with `python -I`
(the source packs are untrusted downloads: the tool only reads them through ffmpeg):
```sh
python -I tools/audio/character_voices.py pool  [--src <voices_src>]   # split + measure + tag the source clips -> art_src/voices/pool.json
python -I tools/audio/character_voices.py build [--only id,id] [--dry] # render the .ogg files, SOURCES.md, art_src/voices/voices.csv, the CREDITS.md block
python -I tools/audio/character_voices.py check                       # identical files / fingerprint distance under 1.0 fail
python -I tools/audio/character_voices.py reel --out <dir>            # review reel: heroes, legendaries, 12 minions (+ list, + CSV)
python -I tools/audio/character_voices.py arch                        # the archetype of every character (* = data/voices.json)
```
The sources (one folder per pack with its `meta.json`: page URL, author, licence checked on the page) were downloaded on
2026-10-28 outside the repo, by default into the session scratchpad (`voices_src`); `--src` points elsewhere. Only
CC0 sources are read (OpenGameArt pages whose licence field offers CC0, Freesound HQ previews of sounds whose page
says CC0, Stormyman's itch.io pack), and the game's own CC0 sfx are used as element layers. Every output's sources:
assets/audio/voices/SOURCES.md. After a build run `--import`.

Art depth maps (parallax): `python -I tools/cards/make_depth.py [--sheet <out.png>]` writes assets/cards/depth/<id>.png
(and depth/heroes/<id>.png) for new or changed art only, with Depth Anything V2 **Small** (Apache-2.0; never the
CC-BY-NC Base / Large / Giant) from `C:/Progetti/Tools/depth/da2_small_onnx/model.onnx` (onnx-community export), then
run `--import`. A card without a depth map just has no parallax. Preview:
`timeout 60 $G --path . res://tests/depth_preview.tscn --resolution 1920x1080 -- --out=<file.png> [--board] [--sweep=h]`
(also writes <file>_flat.png). Effect lights (scripts/battle/fx_light.gd) can be switched off with `DV_NOFXLIGHT=1`.

Living art (data/living_art.json, ArtLiving; the authoring guide is docs/LIVING_ART.md):
`python -I tools/cards/living_mask.py [--only id] [--check] [--preview <dir>]` paints each listed card's masks into
assets/cards/living/<id>.png (+ <id>_flow.png, <id>_fx.png when the recipe needs them; no GPU), then run `--import`;
`--grid id --preview <dir>` saves the picture with a UV grid for reading coordinates. Review:
`python -I tools/cards/living_review.py <id>[,id] --out <dir> [--views art,zoom] [--level 1]` records each view with
the movie maker (every Godot run has a timeout), writes <id>_<view>.mp4 and <id>_heat.png and prints the motion
numbers against the targets. By hand (`--what=zoom|places|side|art|collection`, `--frozen` stops the tilt / drift /
foil, `--level=0|1|2`):
`timeout 300 $G --path . res://tests/living_preview.tscn --fixed-fps 30 --write-movie <dir>/f.png --quit-after 180 -- --what=zoom`
(the frames are f00000000.png...; join them with ffmpeg). `DV_LIVING=0` shows the still paintings.

Painted UI pieces (art_src/tutorial_art.json, deck_ui_art.json): `python tools/ui/import_ui_pieces.py` fetches them
from the ComfyUI PC (read-only) and installs them.

Arena art: `python tools/arena/import_arena.py` fetches new boards / mists / props from the ComfyUI PC and lists what
is still missing (`--force` re-imports).
Board blockouts (Blender 5.2, always with a `timeout`):
`timeout 1500 blender -b -P tools/blender/board_blockout.py -- art_src/arena/blockout_<id> --arena=<id>`, then
`python tools/arena/passes.py art_src/arena/blockout_<id>` and `python tools/arena/upload_blockout.py <id>`
(uploads only, never queues a job).

Deaths review (one kill per killer school, a trade, Venom, Rebirth, a clear at full and lite level, a hero's
defeat; captioned): `timeout 900 $G --path . res://tests/death_preview.tscn --resolution 1280x720 --write-movie <file.avi>
--fixed-fps 30 [-- --only=<segment,...>] [--fast]`, then `ffmpeg -i <file.avi> -c:v libx264 -crf 20 -pix_fmt yuv420p <file.mp4>`.

Intro: `-- --intro` plays the cinematic even if it was seen, `-- --no-intro` never; screenshots of every shot:
`$G --path . res://scenes/intro.tscn -- --intro-shots=<dir> [--only=<shot id>] [--shot-size=2400x1080]`.
The intro is never played in headless runs. Settings: `user://settings.cfg` (`[game] intro_seen`).
