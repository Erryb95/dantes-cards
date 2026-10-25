# Dante's Inferno card game (working title): project rules

A 2D collectible-card / deckbuilder game in **Godot 4.7.2 (GDScript)** set in Dante's Inferno. It targets
Windows / Mac / Linux / Android / iOS / Web from one project. Its sister project is the FPS "Dante's Vengeance"
in `C:\Progetti\Dante's Vengange` (sic), which is paused. Reuse its rules and assets where they fit.

## Language
- Code, comments and in-game text are in **English**: plain, modern and readable (no archaic Longfellow phrasing in the
  UI or on cards). Flavour quotes may cite Dante with a modern English paraphrase.
- Talk to the user (Enrico) in **Italian**.

## Direction (decided 2026-10-25)
- **Hearthstone-level presentation:**
  - juicy card animations: hover, lift, tilt-drag, a slam on play, attack lunges, damage pops, burn-away death;
  - an interactive board, particles and screen shake.
  - All of it is 2D + shaders, no 3D models.
- **Mode first:** single-player against the AI (roguelike run through the circles of Hell, Slay-the-Spire style). PvP comes
  later, if at all.
- **Card art:** AI-generated 2D on the owner's ComfyUI (Qwen-Image 2512, Apache-2.0). The style is chosen from a style board.
  Legendary cards may get animated art (Wan video loops).
- **Characters:** the Commedia has hundreds of named figures. Inferno alone has 100+ sinners plus the guardians:
  Charon, Minos, Cerberus, Plutus, Phlegyas, the Furies, Medusa, the Minotaur, the Centaurs, the Harpies, Geryon,
  the Malebranche, the Giants and Lucifer. That is plenty for many sets.

## Rules carried over from the FPS
- Every Godot command gets a `timeout`. Never `export APPDATA`, never `taskkill /IM`, never paste secrets.
- **Licences:**
  - CC0 / OFL / MIT / Apache only (or a verified commercial licence); credits go in `assets/CREDITS.md`.
  - No non-commercial models.
  - Hunyuan3D is not used: its licence excludes the EU.
  - Never lie about AI use.
- **ComfyUI:**
  - Its URL is in `C:\Servers\comfy_url.txt`; never write it in the repo.
  - The gate is `C:\Servers\comfy_gate.txt` (its first line must start with "open").
  - Use one model family at a time, POST /free between families, and respect `output/status/gpu.txt`.
  - The client is `tools/comfy/comfy.py` in the FPS repo (copy it).
- **Workflow:**
  - Run headless tests before every commit.
  - Use cheap models (sonnet / haiku) for routine work and the best model for design.
  - Use git worktrees for parallel agents.
  - Trigger CI builds only when the user asks.
- **Reusable from the FPS:**
  - the Doré plates (`art_src/dore`);
  - the public-domain music (assets/audio/music);
  - CC0 SFX;
  - settings / menu / save code (`scripts/core/settings.gd`, `scripts/ui/menu`);
  - the AudioDirector.
