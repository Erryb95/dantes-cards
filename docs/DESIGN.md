# Dante's Inferno: The Card Game (design notes, v0.2)

## Structure

| Path | What |
|---|---|
| `data/cards.json` | every card and hero: stats, keywords, effects, rules text, flavour, art prompt |
| `data/sets/*.json` | expansion sets (loaded automatically); schema and balance guide in `docs/CARD_SCHEMA.md`, check with `python tools/cards/validate.py` |
| `data/decks.json` | the preconstructed decks (30 cards each, three per class; the first of each class is its starter): class, hero, name, plan text, 3 featured cards |
| `data/arenas.json` | arenas: name, circle, intro text, music, ambience, painted board / mist, divider kind, ambient particles, tints, tappable corner props (shown only with `"corner_props": true`; off everywhere since 2026-10-26: the board plus the middle animations is enough). Each match draws a random arena whose board is installed (never the previous one) |
| `scripts/battle/arena_props.gd` | `ArenaProps`: an arena's living layer built from its data (divider VFX, ambient, toys); `arena_acheron.gd` subclasses it for Charon's boat (the bell, brazier and skulls are corner props). Sockets: `scenes/arenas/standard.tscn` |
| `scripts/core/` | `CardDB` (static data access), autoloads `Settings`, `Sfx`, `Game` (scene flow + stats), `Collection` (owned cards, Obols, packs, custom decks in `user://collection.cfg`) |
| `scripts/battle/battle_state.gd` | **the rules**: pure logic, no nodes; every change goes out as an event |
| `scripts/battle/ai.gd` | the AI, one action at a time; three levels (Easy rules, Medium and Hard search) picked with `Settings.difficulty` in Options or on the deck screen; strength check `tests/ai_duel.gd`, card balance `tests/card_stats.gd` and `docs/BALANCE.md` |
| `scripts/battle/battle_view.gd` | the board: replays events as animations, handles input |
| `scripts/battle/{card,minion,hero}_view.gd` | the pieces; `fx.gd`, `shapes.gd`, `target_arrow.gd` for the juice |
| `scripts/battle/vfx.gd`, `vfx_data.gd`, `data/vfx.json` | per-card spell looks: 15 schools (colours, textures, sounds; default from the card's circle) x single-target "hit" patterns x board-wide "mass" patterns; every spell has a profile (tested). Staged as anticipation, travel, impact (shake, hit-stop), aftermath. Painted sprites `assets/vfx/vfx_*.png` via `tools/vfx/import_vfx.py`; review with `tests/vfx_preview.tscn -- --out=<dir> --spells` + `tools/vfx/contact_sheet.py` |
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
  thunder, title sting, water) are used from `assets/audio/sfx/`; the score is `assets/intro/music/score_a` + `score_b` (cut to fit; the menu plays whole pieces).

## Rules (v0.2)
- 30 health heroes; mana 1 to 10, refilled each turn; hand limit 10 (overdraw burns); board limit 7; fatigue.
- Mulligan: you start with 3 cards, the opponent with 4, and either can replace any of them.
- Hero power: 2 mana, once per turn. Dante: gain 2 Armor. Charon: 2 damage to the enemy hero. Ulysses: 1 damage to a
  minion.
- Keywords: **Guard** (must be attacked first), **Swift** (attacks at once), **Ward** (blocks the first
  damage), **Drain** (its damage heals your hero), **Venom** (destroys any minion it damages), **Rebirth**
  (returns once after dying).
- Triggers: **On Play**, **Last Breath**, **End of Turn**, **Start of Turn**, **Ruse** (On Play, but only if you
  already played another card this turn).
- Effects: damage, heal, draw, buff, summon, bounce, armor, destroy, freeze, silence, ramp, give_card, mana, copy, transform. Targets: `choose_*` are picked by the
  player; `all_*`, `own_hero`, `enemy_hero`, `random_enemy_minion` and `other_friendly_minions` resolve on their own.

- Decks (as in Hearthstone): exactly 30 cards, your class (Pilgrim, Ferryman or Wanderer) plus Neutral, at most 2 copies
  of a card and 1 of a legendary.
- Preconstructed decks (`data/decks.json`), three per class, picked with the arrows on Choose your path (the last
  pick per class is saved in `Settings.deck_choice`); the opponent plays a random one of the other class
  (`Game.pick_enemy_deck`, never the same one twice in a row). Custom decks face a random one too.
  - Pilgrim: *The Pilgrim's Way* (starter, midrange guards and draw), *Cato's Vigil* (guards, Armor, removal),
    *The Noble School* (the poets of Limbo: draw, spells, Rebirth).
  - Ferryman: *The Ferryman's Host* (starter, souls, venom, clears), *The Serpent Pit* (cheap souls and Venom swarm),
    *The Malebranche Raid* (Swift aggro and burn).
  - Wanderer: *The Wanderer's Crew* (starter, Ruse minions, flame removal, the Trojan Horse and Circe), *The Wooden
    Horse* (tricks and tempo: hidden Achaeans, stolen cards, Sinon's bounce), *The Mad Flight* (Ruse spells and burn).
  - Deck balance: `ai_duel.gd -- --matrix --games=200` (Hard vs Hard, each deal from both seats; every pair of classes,
    `--class=<cls>` keeps the pairs with one class), `-- --deck=<id>` (one deck against every other class's decks) or
    `-- --decks=<a>,<b>`; aim for 40-60% in every pairing.

## The Wanderer: Ulysses (third class)
Ulysses, the false counsellor of Inferno XXVI, wrapped with Diomedes in a two-horned flame in the eighth bolgia.
The class is the trickster of the three: Dante has Armor, draw, guards and holy light; Charon has damage, Venom,
souls and board clears; Ulysses wins with timing, stolen knowledge and false appearances. Cards: `data/sets/ulysses_voyage.json`
(prefix `ul_`, 48 cards + 2 tokens), art list `art_src/ulysses_card_art.json`.
- **Hero power, Searing Word (2):** deal 1 damage to a minion. (A first draft copied a card from the enemy's deck
  every turn: it buried the slow Pilgrim decks in cards, about 75-80% wins, and did nothing against Ferryman aggro.
  The ping keeps the flame identity, answers small swarms and adds no reach to the face.)
- **Ruse:** a bonus that needs another card played earlier in the same turn (the Obol counts, the hero power does not).
  Cheap cards (0-1 mana) set it up; the class sequences its turn instead of just spending mana.
- **Copy / Steal:** Puccio, Spoils of Troy, the augurs and Simon Magus copy from the enemy's hand or deck; the Palladium
  steals the top of the enemy's deck and the Black Cherub a card from their hand; Capocchio summons a copy of an enemy
  minion.
- **Transform:** Circe's Draught and Circe turn minions into 1/1 Swine (no Last Breath, Ward does not help).
- **Disguise and replay:** weak-looking bodies with a payoff (Achaean in Hiding, Buoso Donati, the Trojan Horse: a 0/7
  Guard that releases three Achaean Raiders), bounce to replay On Play effects (Turn the Prow, the Distant Mountain).
- **Flame:** Tongue of Flame, Wandering Flames, Speech of Fire, the Two-Horned Flame and the Valley of Flames burn
  minions and, with Ruse, the enemy hero.
- Engine: `BattleState.ruse_active(side)`; events `ruse` (a Ruse went off), `copy` (before the card's `draw` event:
  where it came from), `steal` (`zone` hand: the victim's hand card `uid` must leave their hand; `zone` deck: the victim's
  deck count), `transform` (before the `death` + `summon` pair that replaces the minion).

Balance check: `run_tests.gd` plays 300 starter-deck games with alternating seats. At v0.2 it reports
Pilgrim 57% / Ferryman 43%; the random-deck soak is Pilgrim 58%, so the Ferryman class pool needs more power.

## Collection and packs (v0.2)
- 250 cards: core 27 + Pilgrim's Journey 35 + Infernal Host 35 + Upper Hell, City of Dis, Malebolge and Cocytus
  (35 neutral each) + The Last Voyage 48 (Ulysses).
- First run: you own the cards of the three starter decks and get 3 packs (the other preconstructed decks are played
  from Choose your path without owning their cards). Battles pay Obols (win 100, loss 25); a pack costs 100.
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
