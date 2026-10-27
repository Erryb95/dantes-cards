# Dante's Inferno: The Card Game (design notes, v0.2)

## Structure

| Path | What |
|---|---|
| `data/cards.json` | every card and hero: stats, keywords, effects, rules text, flavour, art prompt |
| `data/sets/*.json` | expansion sets (loaded automatically); schema and balance guide in `docs/CARD_SCHEMA.md`, check with `python tools/cards/validate.py` |
| `data/decks.json` | the preconstructed decks (30 cards each, three per class; the first of each class is its starter): class, hero, name, plan text, 3 featured cards |
| `data/arenas.json` | arenas: name, circle, intro text, music, ambience (an Sfx loop; empty on every arena since 2026-10-27: Enrico picks the backgrounds himself), painted board / mist, divider kind, ambient particles, tints, tappable corner props (shown only with `"corner_props": true`; off everywhere since 2026-10-26: the board plus the middle animations is enough). Each match draws a random arena whose board is installed (never the previous one; the first match is always the Acheron) |
| `scripts/battle/arena_props.gd` | `ArenaProps`: an arena's living layer built from its data (divider VFX, ambient, toys); `arena_acheron.gd` subclasses it for Charon's boat (the bell, brazier and skulls are corner props). Sockets: `scenes/arenas/standard.tscn` |
| `scripts/core/` | `CardDB` (static data access), autoloads `Settings`, `Sfx`, `Game` (scene flow + stats), `Collection` (owned cards, Obols, packs, custom decks in `user://collection.cfg`) |
| `scripts/battle/battle_state.gd` | **the rules**: pure logic, no nodes; every change goes out as an event |
| `scripts/battle/ai.gd` | the AI, one action at a time; three levels (Easy rules, Medium and Hard search) picked with `Settings.difficulty` in Options or on the deck screen; strength check `tests/ai_duel.gd`, card balance `tests/card_stats.gd` and `docs/BALANCE.md` |
| `scripts/battle/battle_view.gd` | the board: replays events as animations, handles input |
| `scripts/battle/{card,minion,hero}_view.gd` | the pieces; `fx.gd`, `shapes.gd`, `target_arrow.gd` for the juice |
| `scripts/battle/vfx.gd`, `vfx_data.gd`, `data/vfx.json` | per-card spell looks: 15 schools (colours, textures, sounds; default from the card's circle) x single-target "hit" patterns x board-wide "mass" patterns; every spell has a profile (tested). Staged as anticipation, travel, impact (shake, hit-stop), aftermath. Painted sprites `assets/vfx/vfx_*.png` via `tools/vfx/import_vfx.py`; review with `tests/vfx_preview.tscn -- --out=<dir> --spells` + `tools/vfx/contact_sheet.py` |
| `scripts/ui/` | main menu, deck select, deck builder, pack opening, collection, options, credits (`credits_panel.gd`, from Options; keep it in step with `assets/CREDITS.md`), shared look (`ui.gd`, incl. the painted `UI.dialog`), the deck name's gold-ink caret (`ink_caret.gd`), painted skin loader (`ui_skin.gd`), the class plaque / class guide (`class_info_panel.gd`, from `CardDB.class_info`), a card shown big (`card_zoom.gd`), the mana curve (`mana_curve.gd`) |
| `data/lessons.json`, `scripts/tutorial/` | Virgil's lessons: the lesson data (schema at its top), `Lessons` (progress, rewards, setting a lesson's match up), `LessonAI` (the opponent's scripted turns), `LessonGuide` (Virgil's lines, pointer and arrows on the board, which actions a step allows), `Virgil` (his portrait, his dialog); the screen is `scripts/ui/lessons.gd`, How to Play `scripts/ui/how_to_play.gd` |
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
- 30 health heroes; mana 1 to 10, refilled each turn; hand limit 10 (an overdraw, or a card added to a full hand, burns); board limit 7; fatigue.
- Mulligan: you start with 3 cards, the opponent with 4, and either can replace any of them.
- Hero power: 2 mana, once per turn. Dante: gain 2 Armor. Charon: 2 damage to the enemy hero. Ulysses: 1 damage to a
  minion. Filippo Argenti: 1 damage to a minion and +1 Attack.
- Keywords: **Guard** (must be attacked first), **Swift** (attacks at once), **Ward** (blocks the first
  damage), **Drain** (its damage heals your hero), **Venom** (destroys any minion it damages), **Rebirth**
  (returns once after dying, like Hearthstone's Reborn: a new minion with 1 Health and 1 max Health, its printed
  Attack and keywords, no buffs and no Rebirth; healing cannot raise it).
- **Copies** follow Hearthstone. A minion copied onto the board (Capocchio) is a new minion with the original's state
  as it is now: Attack, Health and max Health (buffs, debuffs, damage), the keywords it has now (a broken Ward or a used
  Rebirth stays gone, a gained one comes along), Silence and Freeze (frozen while asleep, the copy stays frozen through
  its owner's next turn). It is asleep unless it has Swift. A copy into the hand (Forged Will, the augurs) is the
  printed card, like Zola's copy in Hearthstone: a card in hand has no damage or buffs here. Diomedes' "Summon a copy of
  this minion" goes off as he enters, while he is still as printed, so a plain summon of the card is the same copy.
- Triggers: **On Play**, **Last Breath**, **End of Turn**, **Start of Turn**, **Ruse** (On Play, but only if you
  already played another card this turn), **Frenzy** (the first time the minion takes damage and survives).
- **Wrath: +N Attack** (a minion property): while the minion is damaged it has +N Attack. **Fight**: two minions deal
  damage equal to their Attack to each other (not an attack). Rules in `docs/HERO_WRATH.md`.
- **Freeze** costs a minion one attack (the Hearthstone rule): a Frozen minion can't attack, and it thaws at the end
  of its owner's turn only if the freeze took that turn's attack from it (it was awake and had not attacked). Frozen
  after it attacked (a Last Breath such as Ruggieri's or Cassius's set off by its own attack) or while still asleep,
  it stays frozen through its owner's next turn (`BattleState._freeze_spent`).
- **Silence** removes a minion's card text and keywords; stat changes stay and a Frozen minion stays frozen.
- Effects: damage, heal, draw, buff, summon, bounce, armor, destroy, freeze, silence, ramp, give_card, mana, copy, transform. Targets: `choose_*` are picked by the
  player; `all_*`, `own_hero`, `enemy_hero`, `random_enemy_minion` and `other_friendly_minions` resolve on their own.

- Decks (as in Hearthstone): exactly 30 cards, your class (Pilgrim, Ferryman, Wanderer or Wrathful) plus Neutral, at most 2 copies
  of a card and 1 of a legendary.
- Preconstructed decks (`data/decks.json`), three per class, picked on Choose your path (the last pick and the
  library filter are saved in `Settings.deck_choice`); the opponent plays a random one of the other class
  (`Game.pick_enemy_deck`, never the same one twice in a row). Custom decks face a random one too.
- **First match:** the intro ends "At the river Acheron, Charon is waiting.", so on a fresh profile (`Game.first_match()`:
  no win or loss recorded yet) the arena is the Acheron and the opponent plays Charon's starter, *The Ferryman's Host*
  (a player who picks the Ferryman faces another class, still at the Acheron).
  - Pilgrim: *The Pilgrim's Way* (starter, midrange guards and draw), *Cato's Vigil* (guards, Armor, removal),
    *The Noble School* (the poets of Limbo: draw, spells, Rebirth).
  - Ferryman: *The Ferryman's Host* (starter, souls, venom, clears), *The Serpent Pit* (cheap souls and Venom swarm),
    *The Malebranche Raid* (Swift aggro and burn).
  - Wanderer: *The Wanderer's Crew* (starter, Ruse minions, flame removal, the Trojan Horse and Circe), *The Wooden
    Horse* (tricks and tempo: hidden Achaeans, stolen cards, Sinon's bounce), *The Mad Flight* (Ruse spells and burn).
  - Wrathful: *The Wrath of the Styx* (starter, Wrath minions set off by Spite and self-pings, Filippo, the Red Towers,
    Athamas), *The Mud Brawl* (Frenzy, fights and sweeps, Tydeus), *Spite and Pride* (aggro: health-costing Florentines,
    Swift riders, burn).
  - Deck balance: `ai_duel.gd -- --matrix --games=200` (Hard vs Hard, each deal from both seats; every pair of classes,
    `--class=<cls>` keeps the pairs with one class), `-- --deck=<id>` (one deck against every other class's decks) or
    `-- --decks=<a>,<b>`; aim for 40-60% in every pairing.

## The Wanderer: Ulysses (third class)
Ulysses, the false counsellor of Inferno XXVI, wrapped with Diomedes in a two-horned flame in the eighth bolgia.
The class is the trickster of the three: Dante has Armor, draw, guards and holy light; Charon has damage, Venom,
souls and board clears; Ulysses wins with timing, stolen knowledge and false appearances. Cards: `data/sets/ulysses_voyage.json`
(prefix `ul_`, 48 cards + 2 tokens, plus the legendary Ulysses, the Schemer, kept under its old id `mc_ulysses`), art list
`art_src/ulysses_card_art.json`.
- **Hero power, Searing Word (2):** deal 1 damage to a minion. (A first draft copied a card from the enemy's deck
  every turn: it buried the slow Pilgrim decks in cards, about 75-80% wins, and did nothing against Ferryman aggro.
  The ping keeps the flame identity, answers small swarms and adds no reach to the face.)
- **Ruse:** a bonus that needs another card played earlier in the same turn (the Obol counts, the hero power does not).
  Cheap cards (0-1 mana) set it up; the class sequences its turn instead of just spending mana.
- **Copy / Steal:** Puccio, Spoils of Troy, the augurs and Simon Magus copy from the enemy's hand or deck; the Palladium
  steals the top of the enemy's deck and the Black Cherub a card from their hand; Capocchio summons a copy of an enemy
  minion as it is now (buffs, damage, Silence, Freeze; see "Copies" under Rules); Ulysses, the Schemer sends an
  enemy minion back to its owner's hand and, with Ruse, keeps a copy of it.
- **Transform:** Circe's Draught and Circe turn minions into 1/1 Swine (no Last Breath, Ward does not help).
- **Disguise and replay:** weak-looking bodies with a payoff (Achaean in Hiding, Buoso Donati, the Trojan Horse: a 0/6
  Guard that releases three Achaean Raiders), bounce to replay On Play effects (Turn the Prow, the Distant Mountain).
- **Flame:** Tongue of Flame, Wandering Flames, Speech of Fire, the Two-Horned Flame and the Valley of Flames burn
  minions and, with Ruse, the enemy hero.
- Engine: `BattleState.ruse_active(side)`; events `ruse` (a Ruse went off), `copy` (before the card's `draw` event:
  where it came from), `steal` (`zone` hand: the victim's hand card `uid` must leave their hand; `zone` deck: the victim's
  deck count), `transform` (before the `death` + `summon` pair that replaces the minion).
- View (`battle_view.gd`): a stolen card leaves the victim's hand (or deck pile) and flies across the river, where the
  thief's copy picks it up; other copies fly in from the enemy hand, the enemy deck or the copied minion. A Ruse flashes
  gold with a "Ruse" plaque (on the minion, or on the spell as it is cast), and playable Ruse cards glow gold instead of
  green while `ruse_active(0)`. A transform is a swirl and a puff of smoke, and the new form pops up in the same slot
  (no death, no slam). Review: `tests/vfx_preview.tscn -- --cards=ul_black_cherub,ul_palladium,ul_circes_draught [--enemy]`,
  `tests/play_shots.tscn -- --class=ulysses`; `view_soak.gd` reports hand / board desyncs.

## The Wrathful: Filippo Argenti (fourth class)
Filippo Argenti, the Florentine knight sunk in the Styx (Inferno VIII), who bites himself in rage. The self-wounding
brawler: **Wrath** minions hit harder while damaged, **Frenzy** minions pay back their first wound, **fights** trade
minions without attacking, and burn and bodies are paid for with the hero's own health. Hero power **Spite** (2): deal 1
damage to a minion and give it +1 Attack. Cards: `data/sets/wrath_styx.json` (prefix `wr_`, 48 cards + 1 token; the
neutral Filippo Argenti and Wrathful Shade moved in, ids kept), art list `art_src/wrath_card_art.json`. Full design,
rules, card list and AI notes: `docs/HERO_WRATH.md`.
- Engine: `Unit.wrath` / `Unit.rage` (`_update_wrath`, `_refresh_wrath` at every cleanup), Frenzy queue
  (`_hurt`, `_fire_frenzies` at the end of the cleanup), `_fight`; target `all_other_minions`. Events `wrath`
  (`on`, `attack`), `frenzy`, `fight` (`a`, `b`).
- View: a damaged Wrath minion burns with an ember aura (`Aura.RAGE`, breathing) and rising sparks, its Attack in ember
  orange; Wrath waking flares red with a "Wrath" plaque; Frenzy rakes claws with a "Frenzy" plaque; a fight is both
  minions rushing to clash halfway in a spray of mud. Review: `tests/wrath_shots.tscn -- --out=<dir>`.

Balance check: `run_tests.gd` plays 300 starter-deck games with alternating seats. At v0.2 it reports
Pilgrim 57% / Ferryman 43%; the random-deck soak is Pilgrim 58%, so the Ferryman class pool needs more power.

## Choose your path and class info
- **Library** (`deck_select.gd`): decks are physical decks, grouped by class. Each class has a plaque (hero portrait,
  class name, tagline, an "i" disc for the class guide) over its decks and a New deck slot. A deck is a stack of
  cards (its gilded edges show under the face; fewer for a thin deck) whose face is its key card's painting, with a
  corner tag (Starter / Premade / Custom), its card count on a bronze disc (red when not playable) and its name on an
  engraved plaque. The selected deck lifts and burns with a gold aura; a click on it again plays it. Class filters
  above (emblem plates once the names no longer fit); the library scrolls, the bronze discs step a class or a row.
- **Showcase**: hero power (disc, name, text) | hero | mana curve, the name ribbon, the class tagline and the plan
  inked on parchment, the three key cards (hover lifts one and shows it big beside the panel with its keyword tips;
  a tap keeps it until the next press), View cards (the whole list on a painted panel, each card zoomable, view only),
  Class guide, Play, Edit (own decks).
- **Class info** (`ClassInfoPanel`, text only from `CardDB.class_info` / `data/cards.json`): `strip()` (the class
  plaque; with `full` also the hero power and tappable keyword chips, used over the Collection grid on a class
  filter), `guide()` (portrait, tagline, hero power, playstyle on parchment, keywords with their help, tips), `open()`
  (the guide as a modal "Dialog": Esc, back, Close or a press outside closes it). Neutral and Tokens get a note strip.
- Review: `tests/screen_audit.tscn -- --what=deck_peek|deck_list|deck_list_zoom|deck_guide|collection_class|collection_guide|collection_neutral --cls=<class>`;
  optional painted pieces are listed in `art_src/deck_ui_art.json`.

## Learning the game: Virgil's lessons and How to Play
- **Virgil's lessons** (Learn to Play on the title screen, `scenes/lessons.tscn`): four short scripted matches, Virgil
  as the guide. 1 The Ferryman (mana, playing minions, attacking, ending the turn), 2 The Wrathful Knight (spells, hero
  power, Armor, Guard), 3 The Two-Horned Flame (Ward, Drain, Venom, Rebirth, Swift, reading card text), 4 The Trial (a
  real match against the Easy AI with the starter deck, opening-hand choice, light coach hints). Lessons 1-3 use fixed
  hands dealt in order, a weakened opponent hero and an opponent that plays a script (`LessonAI`, then passes or plays
  as Easy), so each plays out as taught.
- Each line of Virgil sits on a painted plate beside his portrait, placed where it covers the fewest pieces; a gold
  ring marks what he points at, a red one the target, and a ghost arrow shows the drag. A step either waits for a tap,
  asks for one action (only that action is allowed; anything else gets "Not yet" and the line comes back), or leaves
  free play until the turn ends or the match is won. Text may say `{tap}`: tap or click by device.
- Any lesson can be played again, in any order; the pause menu restarts it, skips it (on to the next one; its reward
  stays to be won) or leaves it. The first win pays a small reward (50 Obols each, a pack for the Trial). Lessons never
  count in the win record. Progress: `Settings.lessons` (id → done / skipped).
- **First launch**: after the intro, on the first title screen of a new player (no match played, never asked), Virgil
  asks "New to Hell?": Begin the lessons or Not now (asked once; `Settings.lessons_offered`).
- **How to Play** (`HowToPlayPanel`): the rules reference, from the title screen's lessons, Options and the battle's
  pause menu. Chapters: The Goal, Your Turn, Combat, Keywords (every keyword with a minion that has it, from
  `UI.KEYWORD_HELP`), Classes (`ClassInfoPanel.guide()` for every class in `CardDB.classes()`), Decks.
- **In normal matches** the first time a keyword shows up on the board its tip shows once, coach style (coach ids
  `kw_<keyword>`).
- Optional painted pieces (Virgil's portrait, the headings as painted words) are listed in `art_src/tutorial_art.json`.
- Review: `tests/screen_audit.tscn -- --what=lessons|howto|offer|lesson|lesson_pause [--lesson=<id>] [--steps=0,3]`.

## Title screen, info surfaces and the profile
- **Title screen**: the stack is Play, Collection, Open Packs, Options, Quit. Learn to Play is Virgil's round medallion
  (his face on the bronze disc, its name on a red ribbon) beside Play. The player plaque in the top-right corner shows
  the avatar, the name ("Choose your name" before there is one) and the record, and opens the profile.
- **Info is inked on parchment**: every tooltip and info bubble (keyword tips, the engine's tooltips, the card zoom,
  the coach, Credits, a refused action, the result, dialog texts, deck hints) sits on the painted parchment with its
  thin bronze rule (`UI.tip_box` / `UI.parchment_box` / `UI.parchment_label`), in dark-brown ink (`UI.INK`) with
  keyword names and headings in dark crimson (`UI.INK_RED`). Never bone letters on a black box. Combat callouts on the
  board (damage numbers, the Wrath / Frenzy / Ruse plaques) keep their own look.
- **Profile** (`ProfilePanel`, rules in `Profile`): the display name (3-16 characters: letters of any alphabet,
  digits, spaces, `_`, `-`; trimmed to single spaces; no word filter), checked live with
  the rule or the error inked under the field; the avatar, one hero per class; the record (victories, defeats,
  favourite class = most matches finished, `Game.class_games`). Save / Back; Esc and the back gesture close it without
  saving. A new player is offered "Pilgrim1234"; offline play never asks for a name. Saved as `Settings.player_name` /
  `player_avatar` (`[profile]` in settings.cfg); `Profile.online()` is what the coming Nakama client syncs as
  display_name / avatar_url. On a phone the panel slides up above the on-screen keyboard.
- Review: `tests/screen_audit.tscn -- --what=menu|profile|profile_error [--named]`; optional painted pieces in
  `art_src/profile_ui_art.json`.

## Collection and packs (v0.2)
- 296 cards: core 27 + Pilgrim's Journey 35 + Infernal Host 35 + Upper Hell (33: Filippo Argenti and the Wrathful
  Shade moved to the Wrathful), City of Dis (35 neutral), Malebolge and Cocytus (34 neutral: Ulysses, the Schemer moved
  to the Wanderer) + The Last Voyage 49 (Ulysses) + The Stygian Marsh 48 (Filippo Argenti).
- First run: you own the cards of the starter decks (one per class) and get 3 packs (the other preconstructed decks are played
  from Choose your path without owning their cards). Battles pay Obols (win 100, loss 25); a pack costs 100.
- A pack holds 5 cards: per slot legendary 1.5%, epic 5.5%, rare 21%; at least one rare; a legendary within
  20 packs. Copies beyond the deck limit refund Obols (5 / 20 / 100 / 400).
- Pack odds are shown, never typed: `Collection.drop_rates()` (from `ODDS`, common = the rest) feeds the pack screen's
  "Drop rates" plaque (`DropRatesPanel`, a parchment sheet with the per-slot chances, the pack rules and the pity
  counter "N / 20") and the small "Rare · 21%" note under each revealed card. Review: `screen_audit --what=packs_rates`.
- Collection sort: a cycling plaque in the title bar (Cost, Rarity, Low rarity, Name, Owned; tokens always last), kept in
  `Settings.collection_sort`; applies inside the class filter, and the two rarity orders put a painted divider per
  rarity. Review: `screen_audit --what=collection_sort --sort=<id> --filter=<set>`.
- Deck builder: owned cards only; Auto-fill completes a deck along a mana curve. Back asks before dropping unsaved
  changes, Delete asks before removing a deck; a saved deck is the one Choose your path shows next.
- Saves (`user://collection.cfg`, `progress.cfg`, `settings.cfg`) are read through `scripts/core/save_file.gd`: a file
  that cannot be parsed is copied to `<file>.bad` and the game starts from defaults; a value of the wrong type keeps
  its default and a malformed custom deck is dropped. Test and tooling runs only read them.

## Online duels (1v1 against another player)
- **Server:** Nakama 3.41, instance "dantes-cards" (modules and protocol in `server/nakama/`). The match
  `dantes_match` is an authoritative **relay**: it orders and times the players' moves but does not run the rules.
  Both clients run the same deterministic `BattleState` and apply the same ordered stream.
- **Client, no SDK:** `scripts/net/nakama_client.gd` (`NakamaClient`: device auth over HTTP, display name and avatar,
  the realtime socket on Godot's `WebSocketPeer` with Nakama's JSON envelopes: matchmaker, match join / data, RPC,
  chat). `scripts/net/online_session.gd` (`OnlineSession`, the autoload `Online`): device id, sign-in, search, join,
  rejoin, reconnect after a drop, the match inbox, the online record (`user://online_record.cfg`, apart from the AI
  record). `scripts/net/duel_sync.gd` (`DuelSync`): builds the canonical game from START and applies MULLIGAN / TURN /
  ACTION strictly by `seq`. `scripts/net/online_config.gd`: where the server is (see BUILD.md).
- **One game, two seats:** side 0 of the canonical game is the match's `players[0]`. Each client still shows itself
  at the bottom: `BattleState.flip` keeps `sides` in local order (`sides[0]` = me) while `start` deals, shuffles and
  hands out uids in canonical order, so uids and the random stream match on both machines; every later rule is
  relative to the acting side. `BattleState.checksum()` fingerprints the game (random state included) in canonical
  order. Tested by `run_tests.gd` (`_test_online_mirror`: random duels through serialized moves on a flipped and an
  unflipped client, same checksum after every message, same events once sides are mapped back, same winner).
- **Moves:** op 1 ACTION `{t: "play", hand_uid, target, index}`, `{t: "attack", attacker, target}`,
  `{t: "power", target}`, each with `ck` (the sender's checksum just before it: a mismatch is reported as a desync);
  op 2 END_TURN, op 3 CONCEDE, op 4 RESULT `{winner: user id or ""}` (both clients, when the rules end the game),
  op 6 MULLIGAN `{replace: [hand indices]}`. A move is not applied when it is made: it is applied when the server's
  echo (102 / 103 / 108) comes back in order, on both machines at once. The board waits for the echo (about 50 ms on
  the tailnet) and the opponent's moves animate at the AI's pace.
- **Flow:** Choose your path > **Play online** (header) plays the selected deck: `OnlineOverlay` (painted search with
  your name, the time spent and Cancel; errors inked on the same parchment with Try again) > a versus splash (both
  heroes and names, who goes first) > the battle (the arena is drawn from the match seed, the same for both). The
  mulligan is simultaneous (30 s, a timer under End Turn). Online battles show both names by the heroes, the turn
  clock under End Turn and the burning rope (`TurnRope`) along the river for the last 15 s of either turn, the
  opponent's connection (dropped: a countdown of their 30 s grace; back: a note), Concede in the pause menu (op 3).
  The pause menu does not hold an online duel. The result names the reason (fallen, conceded, left, time limit,
  desync) and offers Find another duel / Main Menu; it pays Obols like any battle.
- **Rejoin:** the title screen asks the server (`dantes_active_match`) once per run and offers Rejoin; a search also
  goes back into a running duel first. A dropped socket in a duel retries for 40 s and rejoins; the server's RESYNC
  (107) lists every event since the start, `DuelSync` drops what it already applied, and a fresh battle replays the
  missed moves at 6x speed. The clock after a rejoin is the server's `remaining_ms` (it already includes the rope);
  replayed TURNs keep that clock. A match the server no longer has (or that refuses the join) stops the retries at
  once ("The duel ended while you were away", not counted in the record). While searching or in a duel the session
  pings the server every 15 s, and at once when a phone comes back from the background or a move gets no echo: a
  socket that looks open but does not answer is dropped, which starts the rejoin. Renewing the 2 h session (after
  100 min) never closes a socket a search or a duel is using. Only messages of the match being joined or played are
  taken (`_mid`); a search cancelled while its join was under way leaves the match. A RESULT that could not be sent
  (socket down) is sent again after the rejoin. The server's END decides the result screen (a desync is a draw).
- **Mini chat** (`scripts/battle/duel_chat.gd`, `DuelChat`): Nakama's direct-message channel between the two players
  (`channel_join` type 2, not persistent, hidden; content `{"msg"}` or `{"emote"}`; left with the match). A Chat plate
  bottom left with an unread seal opens a parchment panel: the last messages with their senders, the gold-ink name
  field (Enter or Send; the phone keyboard), quick emotes (Greetings, Well played, Thanks, Oops, Good game; also a
  speech bubble by the hero) and Mute (hides the opponent's messages and emotes). Closed, new messages show on
  parchment slips that fade. Plain text only (`ChatText.clean`: no control characters, BBCode stripped and never
  parsed, 120 characters), 1 message a second and 5 per 10 s. No word filter (Enrico's call).
- **Accounts:** a device account by default ("Playing as a guest"). **Sign in with Google** (Profile, when the config
  has the Google client): Google's device-code flow (`scripts/net/google_auth.gd`, `GoogleAuth`; the client is a
  "TVs and Limited Input devices" one, so it works on phones too) shows google.com/device and a code on parchment
  (Copy code, Open the page; the code is also put on the clipboard on a desktop), polls for the id_token, then links
  Google to the guest account (`/v2/account/link/google`, nothing lost); when that Google account already has its own
  game account the install signs into it and gets a fresh device id linked there. "Play as guest" starts a new guest.
  While the consent screen is in testing only its listed test users can sign in (the refusal says so). A future Steam
  provider plugs into the same hook: `OnlineSession.sign_in_with("steam", ticket)` links the identity to the guest
  account or moves the install onto that account (`NakamaClient.link_provider` / `authenticate_provider`); it only
  needs a Steam ticket source in place of `GoogleAuth`, plus the app id and publisher key on the server.
- **Progress on the account (cloud save):** the account (guest or Google) keeps one storage object, collection
  `dantes_save`, key `progress` (owner read/write only), value `{version, saved_at_ms, data}` with the collection
  (owned copies, Obols, packs, pity, packs opened, custom decks), the AI record and games per class, the online
  record, the profile name and avatar, and the settings that belong to the player (lessons, intro and coach tips seen,
  difficulty, deck choice, fast animations, subtitles; never volumes, window, frame limit or vsync).
  `OnlineSession.cloud_sync` runs 2 s after launch and then checks every 10 s (a finished duel within 1 s; at most one
  write each 10 s), uploads only when the progress changed, and makes one last upload when the window closes
  (at most 3 s). After every sign-in (launch, Google, a new guest) it reads the account's save and merges
  (`scripts/net/progress_merge.gd`, `ProgressMerge.merge`, pure and unit-tested): an empty account takes this
  install's; a fresh install takes the account's; otherwise the newer save wins field by field but nothing earned is
  lost (cards united with the most copies, the larger packs / pity / opened / records, decks and lessons united).
  A deleted or renamed deck leaves a tombstone (`deleted_decks`, "cls|name" -> time) and decks carry `saved_ms`: a
  deck comes back from another save only if it was saved after its tombstone, and the copy saved last wins. The
  first write of an account's save uses version "*" (only if there is none yet).
  Applying a merge first copies each save file to `<file>.bak`. Writes carry the version last read; a refused write
  (someone else saved meanwhile) reads, merges and writes again. An upload keeps the account's cards and decks this
  build does not know (`keep_foreign`), so an older build never erases a newer one's. Linking Google to the guest
  keeps the same account, so the save goes with it; signing into a Google account that has its own save merges the
  two. The status shows under the profile plaque ("Saved to your account" / "Offline: will sync later"); failures
  never block play. Tests and debug runs never touch an account's save or the local files. **Limit:** the client
  writes the save, so a cheater can edit it (Obols, cards); a server-authoritative economy (packs opened and Obols
  granted by server RPCs) is the later fix, needed before any trading or ranked rewards.

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
- **Back:** Esc (desktop) or the Android back gesture closes an open dialog, Credits, Options or How to Play, else steps back one
  menu screen (`go_back()` on the scene, routed by `Game.back()`); on the title screen a phone leaves the game. The
  battle and the intro ignore it.

## Next (roadmap)
1. Paintings for the 175 new cards (list in `art_src/new_card_art.json`, made on the ComfyUI PC).
2. Run map (Slay-the-Spire style) through the circles: Limbo, Minos, the Lustful, Cerberus...; card rewards
   after each win; deck building between fights.
3. More keywords (Frenzy), weapons for heroes, secrets ("Judgements").
4. Animated legendary art (Wan video loops), per-card sounds, voice lines.
5. Proper release keystore for Android; store icons; iOS / macOS signing.
