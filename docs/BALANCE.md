# Balance log

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
