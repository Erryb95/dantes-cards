# Balance log

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
