# Balance log

## 2026-10-26: first pass on the 202 collectible cards

**Method.** `tests/card_stats.gd` (Hard AI against Hard AI, random legal decks from the whole pool, 4500 games split in
18 shards with `--first`/`--raw`). Two numbers per card:
- **played**: win rate of the side that played the card (biased: expensive cards are played in long games, reactive
  spells like Freeze are played when behind);
- **deck**: win rate of the side whose deck held it (unbiased but diluted, about +/-2.5% noise for a neutral card,
  +/-3.5% for a class card).

Both are read **against the card's own class average**, because in random decks the classes are far apart (see "Still
open"): Pilgrim cards average 40%, neutrals 50%, Ferryman cards 60%.

Only cost / attack / health changed; no rules text changed. Tokens untouched. The starter decks stay legal.

| Card | Before | After | Evidence (vs class average, before -> after) |
|---|---|---|---|
| The Nameless Bush (`cd_nameless_bush`) | 2 mana 2/4 Guard Rebirth | 2/3 | deck +5.5% -> +2.6%, played +13% -> +8%: the strongest neutral |
| Attila (`cd_attila`) | 5 mana 5/4 Swift | 6 mana 4/4 | deck +5.1% -> +4.6%: barely moved, its Last Breath sweep is the power (see "Still open") |
| Capaneus (`cd_capaneus`, legendary) | 6 mana 5/6 Ward | 4/5 | deck +4.3% -> +3.2% |
| Frederick II (`cd_frederick_ii`) | 5 mana 5/5 Ward, Freeze | 4/5 | deck +3.6% -> +2.2%, played +7% -> +2% |
| Wind of the Six Wings (`mc_six_wings`) | 8 mana | 9 mana | deck +4.2% -> +1.9% |
| Giacomo da Sant'Andrea (`cd_giacomo`) | 2 mana 3/2 Swift | 2/2 | deck +4.1% -> +2.5%, played +9% -> +4% |
| The Minotaur (`cd_minotaur`) | 6 mana 6/5 Swift | 5/5 | deck +3.7% -> +2.3% |
| Rubicante (`ih_rubicante`) | 5 mana 4/5 Ward | 3/5 | deck +4.7% -> +4.6% (Ferryman cards as a group got weaker, so the gap held) |
| Fallen Angel of Dis (`ih_gate_angel`) | 6 mana 4/5 Ward, Destroy | 7 mana 3/5 | deck +3.6% -> +4.5%, as above; raw deck win rate 63.7% -> 62.2% |
| Walls of Dis (`cd_walls_of_dis`) | 2 mana, Gain 3 Armor | 1 mana | deck -5.8% -> -6.2%: the AI still undervalues it (see below) |
| Hidden Shield (`uh_hidden_shield`) | 2 mana, Gain 3 Armor | 1 mana | same card as Walls of Dis; played -17% -> -9% |
| Frozen Tears (`mc_frozen_tears`) | 2 mana, Freeze a minion | 1 mana | deck -4.6% -> -3.6%, played -34% -> -26% |
| Bitter Chill (`uh_bitter_chill`) | 2 mana, Freeze a minion | 1 mana | same card as Frozen Tears; played -25% -> -17% |
| Rope Belt (`pj_rope_belt`) | 2 mana, Freeze a minion | 1 mana | played -25% -> -19%; also lifts Virgil's Wisdom, which makes two |
| Veil of Stillness (`pj_veil_of_stillness`) | 2 mana Silence | 1 mana | deck -4.7% -> -4.7%, played -16% -> -10% (the neutral Silencing Word costs 0) |
| Virgil's Wisdom (`pj_virgils_wisdom`) | 3 mana | 2 mana | deck -4.5% -> 0.0%, played -12% -> -2% |
| Phlegyas (`phlegyas`, Pilgrim starter) | 4 mana 4/3 Swift | 4/4 | deck -3.6% -> -1.1%, played -6% -> -1% |
| Statius (`pj_statius`) | 4 mana 3/4 Rebirth | 3/5 | deck -3.5% -> -2.1% |

**Result.** Random decks: Pilgrim 40.1% -> 41.7% of games. Starter decks (`ai_duel.gd --matchup`, Hard vs Hard, 320
games): Pilgrim 48.1% -> 50.6%.

## Still open
- **Class gap in random decks** (Ferryman about 58%): most Ferryman cards sit above the pool and Charon's power
  (2 damage to the hero) beats Dante's (2 Armor) in AI hands. The starter decks are even, so this only shows with
  custom decks. Next step: a look at the hero powers, or a wider pass on the Ferryman commons.
- **Attila**: its Last Breath (2 damage to all enemy minions) carries the card; stat cuts barely move it. Next step:
  1 damage, which changes the text.
- **Ramp cards** (Hoarded Coin, Sinon's Lie, Sulphur Vent): the search AI almost never plays them (its position score
  ignores mana crystals), so their numbers say nothing about the cards.
- **Armor spells** (Walls of Dis, Hidden Shield) stay low even at 1 mana: the AI scores a card in hand above 3 Armor.
- **Lucifer** (10 mana, legendary): deck +4.4%. Left alone as the set's showpiece.
