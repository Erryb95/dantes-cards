# Dante's Inferno: The Card Game (design notes, v0.2)

## Structure

| Path | What |
|---|---|
| `data/cards.json` | every card and hero: stats, keywords, effects, rules text, flavour, art prompt |
| `data/sets/*.json` | expansion sets (loaded automatically); schema and balance guide in `docs/CARD_SCHEMA.md`, check with `python tools/cards/validate.py` |
| `data/decks.json` | the two starter decks (30 cards each) |
| `data/arenas.json` | arenas: name, circle, intro text, music, ambience, painted board / mist, divider kind, ambient particles, tints, tappable props. Each match draws a random arena whose board is installed (never the previous one) |
| `scripts/battle/arena_props.gd` | `ArenaProps`: an arena's living layer built from its data (divider VFX, ambient, toys); `arena_acheron.gd` subclasses it for Charon's boat and the bell. Sockets: `scenes/arenas/standard.tscn` |
| `scripts/core/` | `CardDB` (static data access), autoloads `Settings`, `Sfx`, `Game` (scene flow + stats), `Collection` (owned cards, Obols, packs, custom decks in `user://collection.cfg`) |
| `scripts/battle/battle_state.gd` | **the rules**: pure logic, no nodes; every change goes out as an event |
| `scripts/battle/ai.gd` | greedy AI that returns one action at a time |
| `scripts/battle/battle_view.gd` | the board: replays events as animations, handles input |
| `scripts/battle/{card,minion,hero}_view.gd` | the pieces; `fx.gd`, `shapes.gd`, `target_arrow.gd` for the juice |
| `scripts/ui/` | main menu, deck select, deck builder, pack opening, collection, options, shared look (`ui.gd`), painted skin loader (`ui_skin.gd`) |
| `scripts/intro/`, `scenes/intro.tscn` | the opening cinematic (see "Opening cinematic" below) |
| `assets/shaders/` | `card_fx` (art mask, hit flash, burn-away dissolve, legendary foil), `river`, `fog`, `crack` (Dis embers / Cocytus frost), `wind` (Lust), `heat_haze` |
| `tools/cards/art_jobs.py` | builds the ComfyUI jobs from the data and imports the results |
| `tests/` | `run_tests.gd` (rules, 300-game starter soak, 400-game random-deck soak over the whole pool), `ui_smoke.tscn` (drives the real board with input events) |

The view never changes game values. It queues `BattleState.event` dictionaries and plays them one by one;
input is accepted only while the queue is empty. This is what keeps the animations in sync with the rules,
and it is the seam for PvP later (events over the network).

## Opening cinematic (about 95 s)
Recycled from the sister FPS (which keeps its own story and title). Doré's public-domain Inferno plates, animated by
Wan 2.2 clips or by procedural "living engraving" loops, run through a camera + engraving shader (`intro_shot.gdshader`),
with LibriVox narration of Longfellow's translation as subtitles, public-domain music and CC0 sound.
Shots (`IntroTimeline.build()`): black + bell + "INFERNO · CANTO I", the dark wood (Inferno I 1-3), the panther, the lion,
Virgil's offer to guide the pilgrim, the Gate of Hell (four lines of the inscription carved letter by letter), Charon
on the Acheron (the first opponent), the story card, the title "DANTE'S INFERNO / THE CARD GAME".
Story card: "Lost in a dark wood, a pilgrim must go down through Hell. / Its souls and its guardians will stand against
him, card by card. / At the river Acheron, Charon is waiting."
- **Flow:** the main menu starts `scenes/intro.tscn` when `Game.intro_due()` (first launch: `Settings.intro_seen` is false,
  not headless, no `--no-intro` / `--snap=` / `--shots=` / `--autoplay`); the end or a skip sets `intro_seen` and goes to the
  menu. Options > "Watch intro" plays it again. Options > "Intro subtitles" toggles the verses.
- **Skip:** hold Esc / Space / gamepad A, or press and hold the mouse button or a finger anywhere, for 1 s (a ring fills at
  the bottom right; the hint shows from second 1 and on every input).
- **Aspect:** the picture always covers the screen (no bars); on narrower screens the window slides to keep the subjects
  (`keep`); cards, inscription and title are sized on a 2.39:1 reference height. Checked at 16:9, 16:10, 20:9, 4:3.
- **Assets:** `assets/intro/` (video 1600x880 Theora, plates, voice, audio). The sounds the game already has (funeral bell,
  thunder, title sting, water) are used from `assets/audio/sfx/`; the score is `assets/audio/music/intro/c1_0` + `c5_0`.

## Rules (v0.2)
- 30 health heroes; mana 1 to 10, refilled each turn; hand limit 10 (overdraw burns); board limit 7; fatigue.
- Mulligan: you start with 3 cards, the opponent with 4, and either can replace any of them.
- Hero power: 2 mana, once per turn. Dante: gain 2 Armor. Charon: 2 damage to the enemy hero.
- Keywords: **Guard** (must be attacked first), **Swift** (attacks at once), **Ward** (blocks the first
  damage), **Drain** (its damage heals your hero), **Venom** (destroys any minion it damages), **Rebirth**
  (returns once after dying).
- Triggers: **On Play**, **Last Breath**, **End of Turn**, **Start of Turn**.
- Effects: damage, heal, draw, buff, summon, bounce, armor, destroy, freeze, silence, ramp, give_card. Targets: `choose_*` are picked by the
  player; `all_*`, `own_hero`, `enemy_hero`, `random_enemy_minion` and `other_friendly_minions` resolve on their own.

- Decks (as in Hearthstone): exactly 30 cards, your class (Pilgrim or Ferryman) plus Neutral, at most 2 copies
  of a card and 1 of a legendary.

Balance check: `run_tests.gd` plays 300 starter-deck games with alternating seats. At v0.2 it reports
Pilgrim 57% / Ferryman 43%; the random-deck soak is Pilgrim 58%, so the Ferryman class pool needs more power.

## Collection and packs (v0.2)
- 202 cards: core 27 + Pilgrim's Journey 35 + Infernal Host 35 + Upper Hell, City of Dis, Malebolge and Cocytus
  (35 neutral each).
- First run: you own the two starter decks and get 3 packs. Battles pay Obols (win 100, loss 25); a pack costs 100.
- A pack holds 5 cards: per slot legendary 1.5%, epic 5.5%, rare 21%; at least one rare; a legendary within
  20 packs. Copies beyond the deck limit refund Obols (5 / 20 / 100 / 400).
- Deck builder: owned cards only; Auto-fill completes a deck along a mana curve.

## Adding content
- **Card:** add an entry to `cards.json` and use it in a deck. Run `python tools/cards/art_jobs.py run`
  (it generates only the missing images), then run the tests.
- **Arena:** add an entry to `arenas.json` (fields documented at the top of `arena_props.gd`), paint the board with the
  standard socket layout (`docs/ARENA_BRIEF.md`) and run `python tools/arena/import_arena.py`. An arena without its
  board is never drawn; `-- --arena=<id>` previews it on the Acheron board.

## Controls
- **Desktop:** drag a card up to play it; drag from a minion to attack (or click it, then click the target).
  Right-click cancels. Hover a minion to inspect it.
- **Touch:** the same with your finger. A card you hold over the hand is shown at full size above your finger;
  tap-tap aiming works for attacks and targets.

## Next (roadmap)
1. Paintings for the 175 new cards (list in `art_src/new_card_art.json`, made on the ComfyUI PC).
2. Run map (Slay-the-Spire style) through the circles: Limbo, Minos, the Lustful, Cerberus...; card rewards
   after each win; deck building between fights.
3. More keywords (Frenzy), weapons for heroes, secrets ("Judgements").
4. Animated legendary art (Wan video loops), per-card sounds, voice lines.
5. Proper release keystore for Android; store icons; iOS / macOS signing.
