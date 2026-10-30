# Balance log

## 2026-10-30: the AI values card draw, Spoils of Troy, one-hit Ruse, the Ferryman's Host

**Method.** As on 2026-10-29: `tests/card_flow.gd` (Hard vs Hard, every cross-class pair of preconstructed decks, every
deal from both seats, 150 games per pair, 1350 per deck) and `tests/ai_duel.gd --levels` (the starters, 200 games per
pair of classes). card_flow now also prints the first player's win rate and each deck's win rate against every
opponent deck (the same deals as `ai_duel.gd --decks`, so it doubles as the matrix); both tools take `--hand=`,
`--ramp=`, `--draw=` (the AI's values) and `--patch=` (ai_duel reads card_flow's patch format), so the "before" runs
used the new code with the old values and the old cards. A patch that adds a card back changes the deck's list order,
and with it the shuffles: such runs are equivalent samples, not the same deals.

**AI** (`scripts/battle/ai.gd`, `evaluate`). Three terms:
- a bonus for each card a move draws, by the hand size when the decision began (3 / 3 / 2.5 / 1.5 / 0.75 points with
  0-4 cards in hand, none from 5 on), so a Draw spell is cast when the hand runs low and not while it is full;
- each Mana Crystal is worth 1.5 (Stars Again's crystal counted for nothing);
- the last two cards in hand are worth a little more (3 and 2.75 instead of 2.5).
A steeper hand curve (3.5 / 3 / 2.75, or 5.5 / 4.5 / 3.5) cut the 0-1 card turns more, but by sitting on cards: turns
ending with 2+ mana unspent and a playable card rose to 9-26% for the aggro decks (from 5-9%), and Virgil's Wrathful
lesson was no longer won on time (the player AI kept cheap minions and spent Centaur Arrows on the hero). The mild
curve keeps those within 1-3 points of before. AI alone (same cards, 40 games per pair): Stars Again cast in 56% of the
games it is held (was 40%), Past the Pillars 85% (73%); the 0-1 card share barely moves (the Malebranche Raid 40 ->
37%, the others within 1 point): the decks, not the AI, decide how often a hand runs dry. Hard vs Easy 80.8 -> 80.6%,
Hard vs Medium 59.8 -> 61.2% (1200 games each; with every change below: 79.6% and 61.9%).

**Cards.**
- *Spoils of Troy* costs 3 (was 2): played in 71% of the games it is drawn (88%).
- *Ruse as one hit*: a Ruse that makes a damage effect bigger now replaces it (`"unless_ruse"` on the plain effect, see
  CARD_SCHEMA.md), so a Ward blocks all of it: Tongue of Flame "Deal 1 damage. Ruse: Deal 3 damage instead.",
  Beacon Keeper "On Play: Deal 1 damage. Ruse: Deal 2 damage instead.", Wandering Flames "Deal 1 damage to all enemy
  minions. Ruse: Deal 2 damage instead." (same totals; Italian texts updated).

**Decks** (existing cards only).
- *The Ferryman's Host* (starter): -1 Ephialtes, -1 Plutus, -1 Medusa's Gaze, -1 Rain of Burning Sand; +1 Socrates,
  +1 Thaïs, +1 Lost Path, +1 Strength of the Earth. Single swaps of a strong card for a draw minion made the deck
  stronger (Ephialtes -> Socrates 56%, two such swaps 59-61% at 60 games per pair): it took two of its board clears
  out to bring it down. It still beats the Wanderer's Crew 64% and loses to the Pilgrim decks (43-45%).
- *The Mad Flight*: -1 Curio, -1 Diomedes; +1 Circe's Draught, +1 Ulysses, the Schemer (answers to the Pilgrim's big
  Guards).

**Numbers** (before -> after; late01 = own turns from turn 6 on that start with 0-1 cards; hand = at the start of
turn 10; win = against the decks of the other three classes, 1350 games each, about +/-1.4%):

| deck | win | late01 | hand at turn 10 | unspent mana |
|---|---|---|---|---|
| pilgrim (starter) | 49.7 -> 50.5 | 10% -> 10% | 3.2 -> 3.3 | 0.53 -> 0.52 |
| ferry (starter) | 54.1 -> 51.3 | 24% -> 17% | 2.2 -> 2.8 | 1.43 -> 1.09 |
| ulysses (starter) | 49.0 -> 47.9 | 21% -> 22% | 2.7 -> 2.9 | 1.33 -> 1.34 |
| wrath (starter) | 47.3 -> 46.0 | 16% -> 17% | 2.8 -> 2.8 | 1.14 -> 1.20 |
| pilgrim_vigil | 47.2 -> 45.1 | 21% -> 21% | 3.9 -> 4.0 | 1.33 -> 1.40 |
| pilgrim_poets | 49.8 -> 51.9 | 7% -> 7% | 3.7 -> 3.9 | 0.44 -> 0.42 |
| ferry_serpents | 48.7 -> 49.3 | 28% -> 28% | 1.4 -> 1.4 | 1.29 -> 1.30 |
| ferry_raid | 49.6 -> 49.6 | 39% -> 36% | 1.1 -> 1.2 | 1.58 -> 1.59 |
| ulysses_horse | 50.7 -> 49.4 | 18% -> 18% | 2.6 -> 2.6 | 1.11 -> 1.12 |
| ulysses_flight | 47.4 -> 52.0 | 16% -> 16% | 3.4 -> 3.7 | 1.11 -> 1.15 |
| wrath_brawl | 52.9 -> 54.4 | 15% -> 14% | 2.7 -> 2.8 | 1.54 -> 1.52 |
| wrath_pride (aggro) | 53.8 -> 52.5 | 16% -> 15% | 1.5 -> 1.5 | 1.26 -> 1.30 |

Stars Again is cast in 52% of the games it is held (39%), Past the Pillars 84% (77%).

**First player.** The first player (3 cards; the second has 4 and Charon's Obol) wins 53.7% of the 8100 Hard vs Hard
games before and 54.9% after; between the four starters 51.8% and 53.9% (900 games each, +/-1.7%). Not changed.

**Matrix.** Pairs worse than 35/65 before: the Mad Flight vs the Pilgrim's Way 27% (now 38%), Cato's Vigil vs the Mud
Brawl 31% (29%) and vs Spite and Pride 31% (33%), the Pilgrim's Way vs Spite and Pride 33% (34%), the Malebranche Raid
vs Cato's Vigil 34% (34%), the Wrath of the Styx vs the Noble School 35% (35%). The Vigil's are the old polarised pairs:
one Three Beasts Overcome for a Cut the Thread lifts it to 39% and 49% against the Wrathful but to 75% against the
Ferryman's Host and 56% overall, so the Vigil is left as it is. The Wanderer's Crew against the Ferryman's Host is
36% (41% before).

## 2026-10-29: card flow (running out of cards late)

**Question.** Late in a match the hand often feels empty: the player's play, or the decks?

**Method.** New probe `tests/card_flow.gd` (Hard vs Hard, every cross-class pair of preconstructed decks, every deal
from both seats, the same deals as `ai_duel.gd --decks`): hand size at the start of each of the deck's own turns,
the share of turns from turn 6 on that start with 0-1 cards (`late01`), unspent mana from turn 5 on, fatigue, cards
drawn and given, the win rate against the other classes, and with `--cards` each card's play rate, its win rate when
played and how often it was stuck in hand. `--patch` tried swaps without touching `data/`. Before: 100 games per pair
(900 per deck); after: 150 per pair (1350 per deck, about +/-1.4% per deck).

**Diagnosis: the decks.** Games are long (10-12 rounds for the midrange decks), the decks were built low
(average cost 2.1-3.2) and the starters had 2-6 cards of card draw. A starter was down to its last card around its turn 9-10
(0.3-0.4 cards left at the end of turn 10) and started 26-36% of its turns from turn 6 on with 0-1 cards; the
Hearthstone norm is aggro empty by turns 6-7 and closing the game, midrange and control still holding 2-4 cards at
turn 10. The AI is not the cause: it leaves 2+ mana unspent with a playable card in hand on only 1-6% of its late
turns (the Wrathful decks 9-23%: they hold self-damage cards), so it spends its mana much like a player who curves
out.
If anything it hoards pure draw spells: `evaluate` (`scripts/battle/ai.gd`) counts every card in hand as 2.5 points,
so a 4-mana "Draw 2" scores below any minion (Stars Again is played in only about half the games it is drawn, Past
the Pillars in three quarters). A human who holds cards back has more of them in hand, but loses the tempo.

**What changed** (existing cards only, no card text or stats changed). Draw minions over vanilla bodies: Thaïs (a
1-mana cantrip) for the 1-drops, Soul on the Shore (draws when it dies), Vitaliano del Dente (draws every turn),
Calchas (copies a card every turn); Ruse and self-damage draw where it fits the plan (Past the Pillars, The Furies'
Nails, Old Companions). Where a deck got too strong or weak, a power card moved:
- *The Pilgrim's Way* (starter): -2 Lost Pilgrim, -1 Brunetto Latini; +2 Thaïs, +1 Vitaliano del Dente.
- *The Ferryman's Host* (starter): -2 Banner Chaser; +2 Soul on the Shore.
- *The Wanderer's Crew* (starter): -1 Ithacan Sailor, -1 Buoso Donati; +1 Past the Pillars, +1 Calchas.
- *The Wrath of the Styx* (starter): -2 Mud Brawler, -1 Brawl in the Mud, -1 Mire Hulk; +2 The Furies' Nails, +2 Geri
  del Bello.
- *Cato's Vigil*: -1 Manto, -1 The Sullen; +1 Archbishop Ruggieri, +1 Thaïs.
- *The Noble School*: -1 Dante's Courage, -1 Reed of Humility; +1 Vitaliano del Dente, +1 Thaïs.
- *The Serpent Pit*: -2 Whip Demon, -2 Banner Chaser, -1 Dionysius; +2 Soul on the Shore, +2 Cocytus Chill, +1 Thaïs.
- *The Malebranche Raid*: -2 Brutus, -1 Graffiacane; +2 Francesco d'Accorso (Swift, draws), +1 The She-Wolf.
- *The Wooden Horse*: -1 Caiaphas, -1 The Sweet Siren; +1 Calchas, +1 Old Companions.
- *The Mad Flight*: -1 False Beacon, -1 Past the Pillars; +1 Thorn Jab, +1 Spoils of Troy.
- *The Mud Brawl*: -1 Butting Heads, -1 Storm Across the Styx, -1 Brawl in the Mud; +1 The Furies' Nails, +2 Geri del
  Bello.
- *Spite and Pride* (aggro): unchanged.

**Single cards swing a deck a lot** (one copy, Hard vs Hard): Spoils of Troy +10-13 points when it replaced a weak card
(Mad Flight 45 -> 56%, the Wanderer's Crew 47 -> 60%); Capaneus +9.5 and Lucan +9 in the Noble School; Vitaliano del
Dente plus Fallen Angel of Dis put the Ferryman's Host at 68-74%; Archbishop Ruggieri plus Old Man of Crete put
Cato's Vigil at 60-62%. Pure draw spells barely move a deck in AI games (the AI rarely casts them).

**Numbers** (`late01` = turns from turn 6 on that start with 0-1 cards; hand = cards at the start of turn 10; win =
against the decks of the other three classes):

| deck | late01 before -> after | hand at turn 10 | first 0-1 card turn (share of games) | win before -> after |
|---|---|---|---|---|
| pilgrim (starter) | 27% -> 10% | 2.1 -> 3.2 | 10.1 (42%) -> 10.7 (20%) | 47.6 -> 49.7 |
| ferry (starter) | 31% -> 24% | 1.9 -> 2.2 | 10.5 (64%) -> 11.0 (52%) | 51.3 -> 54.1 |
| ulysses (starter) | 36% -> 21% | 1.9 -> 2.7 | 10.3 (60%) -> 10.9 (41%) | 48.6 -> 49.0 |
| wrath (starter) | 26% -> 16% | 1.9 -> 2.8 | 10.5 (51%) -> 11.2 (33%) | 49.2 -> 47.3 |
| pilgrim_vigil | 20% -> 21% | 3.8 -> 3.9 | 13.7 (41%) -> 13.3 (44%) | 46.3 -> 47.2 |
| pilgrim_poets | 20% -> 7% | 2.7 -> 3.7 | 10.8 (36%) -> 11.5 (17%) | 53.2 -> 49.8 |
| ferry_serpents | 38% -> 28% | 1.2 -> 1.4 | 8.5 (62%) -> 9.3 (53%) | 40.1 -> 48.7 |
| ferry_raid (aggro) | 40% -> 39% | 1.1 -> 1.1 | 7.4 (51%) -> 7.3 (51%) | 56.1 -> 49.6 |
| ulysses_horse | 28% -> 18% | 2.1 -> 2.6 | 10.3 (44%) -> 10.7 (33%) | 52.3 -> 50.7 |
| ulysses_flight | 17% -> 16% | 3.3 -> 3.4 | 12.0 (32%) -> 11.5 (31%) | 50.7 -> 47.4 |
| wrath_brawl | 18% -> 15% | 2.6 -> 2.7 | 12.0 (42%) -> 11.4 (32%) | 51.9 -> 52.9 |
| wrath_pride (aggro) | 14% -> 16% | 1.5 -> 1.5 | 8.7 (20%) -> 8.6 (22%) | 52.7 -> 53.8 |

The baseline was already outside the old 49-53% band (the Serpent Pit 40%, the Raid 56%): later passes had moved it.
Unspent mana from turn 5 on fell for the starters (Pilgrim 1.19 -> 0.53, Wanderer 2.13 -> 1.33, Wrathful 1.79 ->
1.14). Game length is unchanged (aggro 7.7 rounds, midrange 10-11, Cato's Vigil 13.7; 18% of the Vigil's games reach
fatigue).

**Open.**
- The Ferryman's Host still topdecks the most of the starters (24%) and is the strongest of them (54%): more draw
  there needs a power card out.
- Spite and Pride against the Pilgrim decks (68%) and Cato's Vigil against the Wrathful (39%) are old polarised pairs.
- AI proposal: value cards in hand by how few there are (the first ones worth more than 2.5) and count the draw of a
  spell, so it casts draw spells and keeps a card or two when its hand is nearly empty.

## 2026-10-27: Hearthstone copies and Reborn, Easy behind Guards

**Rules.** Capocchio's copy keeps the minion's current state (buffs, damage, keywords now, Silence, Freeze); Rebirth
brings a minion back as a new 1/1-Health minion (max Health 1, no buffs). Capocchio is in no preconstructed deck, and
the old "damaged" Rebirth body never got healed in the AI games: Hard vs Hard is unchanged to the game (starters
Pilgrim / Ferryman 112-88, Pilgrim / Wanderer 96-104, Ferryman / Wanderer 120-80 of 200; The Noble School, the
Rebirth deck, 50.8% against the six other-class decks at 100 games each, before and after).

**Easy AI.** Easy no longer throws a minion into a Guard when it dies and the Guard lives (a 1/1 into a 6/9), unless
its other ready attackers then finish the Guard and that pays (a Venom or Drain Guard, or lethal behind it). It stays
clearly the weakest level. `ai_duel.gd --levels=A,B --classes=X,Y`, 200 games each (every deal from both seats),
Easy's win rate before -> after:

| classes | Easy vs Medium | Easy vs Hard | random decks: vs Medium | random decks: vs Hard |
|---|---|---|---|---|
| Pilgrim / Ferryman | 36% -> 38% | 32% -> 33% | 41% -> 42% | 31% -> 29% |
| Pilgrim / Wanderer | 29% -> 29% | 24% -> 24% | 37% -> 35% | 25% -> 24% |
| Ferryman / Wanderer | 29% -> 31% | 17% -> 20% | 34% -> 33% | 21% -> 22% |

Medium vs Hard is unchanged (39%, 41%, 37%); the moves are within the +/-3.5% noise of 200 games.

## 2026-10-27: the Wrathful (Filippo Argenti), fourth class

**Method.** As for the Wanderer: `tests/ai_duel.gd --deck=<id>` (one Wrathful deck against every deck of the other
three classes, Hard vs Hard, every deal from both seats), probes at 20-40 games per pairing, per-card win rates with
`--decks=a,b`, the final run at 100 games per pairing. No card of the other classes changed; only the two neutral
cards that moved into the class (Filippo Argenti, Wrathful Shade) left the neutral pool.

**What moved the numbers.**
- The first draft sat at 48-57% per deck. Once its cheap enabler was made reliable (Gnawing Spite as a 0-mana
  cantrip) and two Wrath bodies were buffed, the starter reached 61-63%, even with Spite cut from +2 to +1 Attack:
  75-83% against Pilgrim, 25-35% against the Malebranche Raid.
- Wrath is cheap to switch on (the hero power, any trade the minion survives, every sweeper), so a Wrath minion is
  priced as if it were always raging, minus about 1 Attack. The fixes were mostly 1 Attack off the Wrath bodies
  (Wrathful Shade 1/3, Stygian Brute 2/4, Tower Watchman 1/5, Drowned Knight 3/5, Rancorous Shade 2/5, Mire Hulk 4/6,
  Colossus of Mud 4/8), Gnawing Spite to 1 mana, Marsh Warden's Armor 3 -> 2 and Filippo 3/6.
  Cutting health instead would have deepened the Raid matchup.
- The late Wrath bodies (Colossus 86%, Filippo 83% of games won when played against Pilgrim) were what buried the
  Pilgrim; Rabble-Rouser and Geri del Bello were the weakest cards against the Raid and left the starter for a second
  Stirring the Mud and a Brawl in the Mud, which sweep tokens and wake the deck's own Wrath at once.
- Spite and Pride won only 18-20% against the Ferryman's face pings and sweepers while its self-damage cards (Signal
  Fires, Gnawing Spite) were in it; two Black Guelph Brawlers and a second Back With the Other Dogs took their place.
- Tried and reverted: The Eternal Fire as 3-mana minion removal (Spite and Pride fell to 47%, Pilgrim unchanged);
  Adimari Captain 5/6.

**Final matrix** (row deck's win rate, 100 games per pairing):

| Wrathful deck | pilgrim | pilgrim_vigil | pilgrim_poets | ferry | ferry_serpents | ferry_raid | ulysses | ulysses_horse | ulysses_flight | overall |
|---|---|---|---|---|---|---|---|---|---|---|
| wrath (The Wrath of the Styx) | 53% | 48% | 39% | 49% | 76% | 33% | 55% | 48% | 46% | 49.7% |
| wrath_brawl (The Mud Brawl) | 53% | 68% | 36% | 52% | 74% | 42% | 69% | 49% | 29% | 52.4% |
| wrath_pride (Spite and Pride) | 64% | 80% | 57% | 37% | 53% | 40% | 42% | 53% | 50% | 52.9% |

Per class (row deck's average): the starter 46.7% against Pilgrim, 52.7% against Ferryman, 49.7% against the
Wanderer; the Mud Brawl 52.3 / 56.0 / 49.0; Spite and Pride 67.0 / 43.3 / 48.3.

**Open.** Every deck is inside 47-55% overall, but the class is more polarised than the Wanderer: 11 of 27 cells are
outside 40-60 (the Wanderer: 3 of 18).
- The Serpent Pit cannot race the big Wrath health pools (74-76%).
- The Raid's Venom, Silence and Swift tokens beat the self-damaging starter (33%).
- Spite and Pride runs over the Pilgrim (67% on average, 80% against Cato's Vigil: a slow Guard deck with no early
  sweeper) and loses to the Ferryman's face pings (43%).
- The Mud Brawl wins its fights against the Wanderer's Crew (69%) and Cato's Vigil (68%) but cannot catch the Mad
  Flight's tempo (29%) or the Poets' value (36%).
Further Wrathful cuts cost the Ferryman matchups first; the next lever is probably the Pilgrim's early answers.

## 2026-10-27: the Wanderer (Ulysses), third class

**Method.** `tests/ai_duel.gd` generalised to every pair of classes (`--matrix`, `--class=`, `--deck=`), Hard vs Hard, each
deal played from both seats; tuning runs at 40-60 games per pairing in parallel copies of the project, the final run
at 100 games per pairing (+/-5% per cell, +/-3% per deck against a class). No Pilgrim, Ferryman or neutral card was
changed, so the Pilgrim / Ferryman matrix is untouched (49.6% at 100 games).

**What moved the numbers.**
- The first draft won about 70% overall: 80% against Pilgrim, 42% against Ferryman. Every Pilgrim deck lost 80-95%.
- The first hero power (copy a random card from the enemy's deck every turn) buried the slow Pilgrim decks in cards.
  Swapping it changed little on its own (a face ping: Pilgrim 77%, Ferryman 52%), but a ping restricted to minions
  (*Searing Word*) took 11 points off the Pilgrim matchup without touching Ferryman: it answers Ferryman's swarms and
  adds no reach.
- The class was polarised: wide boards (Achaean Raiders, Last Breath bodies) and copy / steal effects (which scale with
  the opponent's card quality) beat Pilgrim, which has few sweepers and many expensive minions; Ferryman's Venom and
  board clears beat them. Fixes: Raiders 3/2 -> 2/2, a general trim of the cheap minions, cheaper Guards
  (Gilded Hypocrite 3 mana 2/5) and Wandering Flames in every deck, fewer copy cards and no bounce-to-replay in the
  decks (Turn the Prow is close to a dead card in AI hands: 15% when played against Ferryman).

**Final matrix** (row deck's win rate):

| Ulysses deck | pilgrim | pilgrim_vigil | pilgrim_poets | ferry | ferry_serpents | ferry_raid | vs Pilgrim | vs Ferryman |
|---|---|---|---|---|---|---|---|---|
| ulysses (The Wanderer's Crew) | 50% | 50% | 47% | 43% | 63% | 46% | 49.0% | 50.7% |
| ulysses_horse (The Wooden Horse) | 51% | 64% | 50% | 49% | 55% | 41% | 55.0% | 48.3% |
| ulysses_flight (The Mad Flight) | 47% | 57% | 56% | 54% | 60% | 39% | 53.3% | 51.0% |

The Malebranche Raid (Swift aggro) is the Wanderer's hardest matchup (39-46%), the Serpent Pit its easiest.
The Hard AI fires the Ruse on about 60% of the Ruse cards it plays (Easy: about 50%).

## 2026-10-27: variety pass on near-duplicate cards

**What changed.** Near-duplicates (same effects, same or near cost) got a twist each, built from existing effects only:
Silence (Serpent's Kiss, Veil of Stillness, Sealed Tomb), Freeze (Frozen Tears, Rope Belt), Deal 2 (Burning Rain,
Boiling Pitch, Thorn Jab), Armor (Hidden Shield), bounce (Demon's Lash, Led Back to the Dark Wood, Gate of Dis),
board damage (Rain of Burning Sand, Three Beasts Overcome, Gale of the Lustful, Winter of Cocytus, Earth Swallows the
Seer), mana (Sinon's Lie, Ascent of the Mountain), Cut the Thread, and the minions Dido, Medusa (Gate Guardian),
Francesco d'Accorso, Socrates, Priscian, Wrathful Shade and Beacon Keeper. One card per cluster keeps the plain effect
(Silencing Word, Bitter Chill, Burning Sand, Walls of Dis, Turned Back at the Gate, Rain of Fire, Hoarded Coin,
Fury's Lash, Michael Scot, Guido, Virgil). Ulysses, the Schemer left the neutrals: it is now a Wanderer legendary
(same id `mc_ulysses`) whose Ruse keeps a copy of the minion it sends back.
Decks: the Malebranche Raid plays Burning Sand instead of Boiling Pitch (now minion-only), the Ferryman's Host one
Burning Sand instead of Burning Rain (now random), so both keep their old reach.
Merge note: the Wrathful class (merged first) had already moved the Wrathful Shade into it as a 1/3 with Wrath +3, so
that version is kept and this pass's neutral 3/4 "End of Turn: 1 damage to ALL minions" is dropped.

**Tuning.** The first draft lifted Cato's Vigil from 50% to 64% against the Ferryman (Cut the Thread at 5 mana, a 1-mana
Veil with draw, +3 Armor on the Three Beasts). Cut the Thread is back at 6, Veil costs 2, the Three Beasts give 2 Armor,
and the Ferryman's Host keeps a plain Burning Sand. Single-change tests showed no one card did it: the Vigil got a
little from each.

**Matrix** (Hard vs Hard, 100 games per cell, row deck's win rate; before -> after):

| row deck | vs ferry | vs ferry_serpents | vs ferry_raid | vs ulysses | vs ulysses_horse | vs ulysses_flight |
|---|---|---|---|---|---|---|
| pilgrim | 52 -> 52 | 44 -> 44 | 47 -> 49 | 50 -> 45 | 49 -> 51 | 56 -> 56 |
| pilgrim_vigil | 54 -> 59 | 45 -> 55 | 50 -> 56 | 52 -> 46 | 34 -> 35 | 48 -> 48 |
| pilgrim_poets | 52 -> 58 | 63 -> 57 | 41 -> 39 | 51 -> 59 | 49 -> 46 | 49 -> 47 |
| ferry | | | | 57 -> 61 | 51 -> 51 | 47 -> 52 |
| ferry_serpents | | | | 37 -> 35 | 45 -> 42 | 44 -> 44 |
| ferry_raid | | | | 54 -> 53 | 59 -> 56 | 63 -> 66 |

Class against class: Pilgrim vs Ferryman 49.8% -> 52.1%, Pilgrim vs Wanderer 48.7% -> 48.1%, Ferryman vs Wanderer
50.8% -> 51.1%. The cells outside 40-60% were already there before the pass (Vigil vs Wooden Horse, Serpent Pit vs
Wanderer's Crew, Raid vs Mad Flight; Ferryman's Host vs Wanderer's Crew is 61% at 300 games both before and after).
