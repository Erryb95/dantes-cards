# Build

`G=C:/Progetti/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe` (always run it with a `timeout`).

```sh
timeout 300 $G --headless --path . -s res://tests/run_tests.gd        # rules + AI soak
timeout 240 $G --headless --path . res://tests/ui_smoke.tscn          # input smoke test
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
`--snap=<file.png> [--snap-delay=s]` (one screenshot of any scene).
Intro: `-- --intro` plays the cinematic even if it was seen, `-- --no-intro` never; screenshots of every shot:
`$G --path . res://scenes/intro.tscn -- --intro-shots=<dir> [--only=<shot id>] [--shot-size=2400x1080]`.
The intro is never played in headless runs. Settings: `user://settings.cfg` (`[game] intro_seen`).
