# Build

`G=C:/Progetti/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe` (always run it with a `timeout`).

```sh
timeout 300 $G --headless --path . -s res://tests/run_tests.gd        # rules + AI soak
timeout 240 $G --headless --path . res://tests/ui_smoke.tscn          # input smoke test
timeout 300 $G --headless --path . res://tests/menu_smoke.tscn        # menu dialogs, pack opening, deck problems
timeout 300 $G --headless --path . res://tests/intro_test.tscn        # opening cinematic data + player + skip
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
arena toy and the divider after s seconds).
Headless runs, `--autoplay`, `--snap=`, `--shots=`, `--out=`, `--intro-shots=` and any scene or script under
`res://tests/` are debug runs (`Game.debug_run()`): no intro, no coach tips, and nothing is written to the player's
settings, progress or collection.

Art depth maps (parallax): `python -I tools/cards/make_depth.py [--sheet <out.png>]` writes assets/cards/depth/<id>.png
(and depth/heroes/<id>.png) for new or changed art only, with Depth Anything V2 **Small** (Apache-2.0; never the
CC-BY-NC Base / Large / Giant) from `C:/Progetti/Tools/depth/da2_small_onnx/model.onnx` (onnx-community export), then
run `--import`. A card without a depth map just has no parallax. Preview:
`timeout 60 $G --path . res://tests/depth_preview.tscn --resolution 1920x1080 -- --out=<file.png> [--board] [--sweep=h]`
(also writes <file>_flat.png). Effect lights (scripts/battle/fx_light.gd) can be switched off with `DV_NOFXLIGHT=1`.

Arena art: `python tools/arena/import_arena.py` fetches new boards / mists / props from the ComfyUI PC and lists what
is still missing (`--force` re-imports).
Board blockouts (Blender 5.2, always with a `timeout`):
`timeout 1500 blender -b -P tools/blender/board_blockout.py -- art_src/arena/blockout_<id> --arena=<id>`, then
`python tools/arena/passes.py art_src/arena/blockout_<id>` and `python tools/arena/upload_blockout.py <id>`
(uploads only, never queues a job).

Intro: `-- --intro` plays the cinematic even if it was seen, `-- --no-intro` never; screenshots of every shot:
`$G --path . res://scenes/intro.tscn -- --intro-shots=<dir> [--only=<shot id>] [--shot-size=2400x1080]`.
The intro is never played in headless runs. Settings: `user://settings.cfg` (`[game] intro_seen`).
