# Card schema (for designers and generator agents)

Cards live in `data/cards.json` (core set) and `data/sets/*.json` (expansions). Each set file has the shape
`{"set_name": "...", "cards": [ ... ]}`. After editing, run `python tools/cards/validate.py`: it must print `OK`.

## Fields
| field | values |
|---|---|
| `id` | unique snake_case, ascii, e.g. `brunetto_latini` |
| `name` | modern English, max 28 chars (e.g. "Brunetto Latini", "Capaneus, the Defiant") |
| `set` | class: `pilgrim` (Dante's class), `ferry` (Charon's class), `neutral` (anyone), `token` (only summoned) |
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
| `freeze` | - | the target can't attack during its next turn |
| `silence` | - | remove keywords and card effects from a minion |
| `ramp` | `amount` | gain empty mana crystals (no target) |
| `give_card` | `card`, `count` | add copies of a card id to your hand (no target) |

**Targets**
- **Picked by the player:** `choose_any`, `choose_enemy` (enemy hero or minion), `choose_minion`,
  `choose_enemy_minion`, `choose_friendly_minion`.
- **Automatic:** `own_hero`, `enemy_hero`, `self` (the minion itself), `all_minions`, `all_enemy_minions`,
  `all_friendly_minions`, `other_friendly_minions`, `all_enemies` (enemy hero + minions), `random_enemy`,
  `random_enemy_minion`, `random_friendly_minion`.
- `draw`, `summon`, `ramp` and `give_card` take no target.

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
- **Prefixes:** `On Play: Deal 2 damage.`, `Last Breath: Summon a 2/2 Shade.`, `End of Turn: Gain +1 Attack.`
- **Capitals:** keywords capitalised (Guard, Swift, Ward, Drain, Venom, Rebirth, Freeze, Silence).
- **Keyword-only cards:** the text is just the keywords: `Guard. Drain.`
