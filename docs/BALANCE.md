# Balance log

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
