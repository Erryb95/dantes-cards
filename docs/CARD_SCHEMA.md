# Card schema (for designers and generator agents)

Cards live in `data/cards.json` (core set) and `data/sets/*.json` (expansions). Each set file has the shape
`{"set_name": "...", "cards": [ ... ]}`. After editing, run `python tools/cards/validate.py`: it must print `OK`.

## Fields
| field | values |
|---|---|
| `id` | unique snake_case, ascii, e.g. `brunetto_latini` |
| `name` | modern English, max 28 chars (e.g. "Brunetto Latini", "Capaneus, the Defiant") |
| `set` | class: `pilgrim` (Dante's class), `ferry` (Charon's class), `ulysses` (Ulysses' class), `neutral` (anyone), `token` (only summoned). A class is any hero's `class` in `data/cards.json` |
| `type` | `minion` or `spell` |
| `rarity` | `common`, `rare`, `epic`, `legendary` (`token` for tokens) |
| `cost` | 0..10 |
| `attack`, `health` | minions only; health >= 1 |
| `keywords` | optional list: `guard`, `swift`, `ward`, `drain`, `venom`, `rebirth` |
| `effects` | optional list of effect objects (below) |
| `text` | rules text shown on the card, **must match the effects exactly**, modern plain English |
| `flavor` | one short line, modern English paraphrase of Dante (no archaic Longfellow) |
| `circle` | where it comes from: `dark_wood`, `ante_inferno`, `limbo`, `lust`, `gluttony`, `greed`, `wrath`, `dis`, `heresy`, `violence`, `malebolge`, `cocytus` |
| `art` | image subject for the painter, 1 sentence, concrete and visual, no style words, no text |

## Effects
`{"on": TRIGGER, "do": OP, "target": TARGET, ...params}`

**Triggers (`on`)**
| trigger | text prefix |
|---|---|
| `play` | `On Play:` for minions (spells just state the effect) |
| `death` | `Last Breath:` |
| `turn_end` | `End of Turn:` |
| `turn_start` | `Start of Turn:` |

**Ops (`do`) and their params**
| op | params | meaning |
|---|---|---|
| `damage` | `amount` | deal damage |
| `heal` | `amount` | restore health (not above max) |
| `draw` | `amount` | draw cards (no target) |
| `buff` | `attack`, `health`, optional `keywords` | permanent +X/+Y and keywords |
| `summon` | `card` (a minion id, tokens defined in the same file with `set: token`), `count` | summon for yourself (no target) |
| `bounce` | - | return a minion to its owner's hand |
| `armor` | `amount` | target must be `own_hero` |
| `destroy` | - | destroy a minion |
| `freeze` | - | the target loses its next attack; it thaws at the end of its owner's turn once the freeze has cost it an attack (frozen after attacking or while asleep, it stays frozen through its next turn) |
| `silence` | - | remove keywords and card effects from a minion (stat changes stay, a freeze stays) |
| `ramp` | `amount` | gain empty mana crystals (no target) |
| `give_card` | `card`, `count` | add copies of a card id to your hand (no target); a card that does not fit in a full hand burns |
| `mana` | `amount` | gain mana this turn only, up to 10 (no target; Charon's Obol) |
| `copy` | `from` (`enemy_hand` / `enemy_deck`, random cards, never the same card twice) or a minion target; `count`; `steal` (the cards leave the enemy: the top of the deck, or a random hand card); `to`: `hand` (default) or `board` (summon the copy) | add copies to your hand. Hand limit applies: a copy that does not fit burns, and nothing is stolen without room for it. Text: "Copy ... into your hand", "Steal ...", "Summon a copy of ..." |
| `transform` | `card` (a minion id) | the target becomes a fresh copy of that card in the same place: no Last Breath, Ward does not stop it |

**Targets**
- **Picked by the player:** `choose_any`, `choose_enemy` (enemy hero or minion), `choose_minion`,
  `choose_enemy_minion`, `choose_friendly_minion`.
- **Automatic:** `own_hero`, `enemy_hero`, `self` (the minion itself), `all_minions`, `all_enemy_minions`,
  `all_friendly_minions`, `other_friendly_minions`, `all_enemies` (enemy hero + minions), `random_enemy`,
  `random_enemy_minion`, `random_friendly_minion`.
- `draw`, `summon`, `ramp`, `give_card`, `mana` and `copy` with `from` take no target.

**Ruse** (Ulysses): an effect with `"ruse": true` (on `play` only) resolves only when its owner already played another
card this turn (the hero power does not count; the Obol does). Text: `Ruse: Draw a card.` (minions too: no `On Play:`).
A Ruse effect may share the card's `choose_*` target (`Deal 1 damage. Ruse: Deal 2 more.`), otherwise it uses an
automatic target, so the player is never asked to aim at something that will not happen.

**Rules**
- At most **one** `choose_*` target per card, and only on `play` effects.
- `death`, `turn_end` and `turn_start` effects must use automatic targets.

## Balance guide (stat budget)
A vanilla minion has attack + health ≈ 2 x cost + 1 (1-mana 2/1, 2-mana 2/3 or 3/2, 3-mana 3/4, 4-mana 4/5,
5-mana 5/6, 6-mana 6/7, 7-mana 7/8).
- Each keyword costs about 1 stat point (Guard can be "free" on defensive bodies).
- Strong effects cost 2-4 points.
- Spells:
  - 1 mana: 2 damage;
  - 2 mana: 3 damage to a minion, or draw 2;
  - 4 mana: 2 damage to all enemy minions, or 4 damage + something;
  - 6+: board clears.
- Legendaries can break the curve by about 2 points but must be interesting, not just big.
- Curve per 30-card set:
  - 1 cost: 4, 2: 6, 3: 6, 4: 5, 5: 4, 6: 2, 7+: 3;
  - about 70% minions;
  - rarity 15 common / 8 rare / 4 epic / 3 legendary.

## Text style
- **Prefixes:** `On Play: Deal 2 damage.`, `Last Breath: Summon a 2/2 Shade.`, `End of Turn: Gain +1 Attack.`, `Ruse: Gain +1/+1.`
- **Capitals:** keywords capitalised (Guard, Swift, Ward, Drain, Venom, Rebirth, Freeze, Silence).
- **Keyword-only cards:** the text is just the keywords: `Guard. Drain.`
- **Mana:** `mana` is "Gain 1 Mana this turn only."; `ramp` is "Gain an empty Mana Crystal." ("Gain 2 empty Mana Crystals.").
- **Same effect, same words:** `damage` on `choose_any` is "Deal 2 damage." (no "to any target"); narrower targets say
  so ("to a minion", "to an enemy minion", "to an enemy").
