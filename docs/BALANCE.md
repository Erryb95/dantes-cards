# Balance log

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
