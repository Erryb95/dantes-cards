# The Wrathful: Filippo Argenti (fourth class)

Filippo Argenti, the Florentine knight of Inferno VIII. He is sunk in the Styx, where the wrathful tear at each other in
the mud. He grabs at Phlegyas' boat, Virgil shoves him back "with the other dogs", the whole swamp turns on him
("Get Filippo Argenti!"), and he sinks his teeth into himself.

- Class id `wrath`, display name **Wrathful**, hero id `filippo`.
- Set: *The Stygian Marsh*, `data/sets/wrath_styx.json`. Prefix `wr_`. 48 cards and 1 token.
- Art prompt list: `art_src/wrath_card_art.json`.

## Pitch
The self-wounding brawler. Where the others protect their pieces, the Wrathful hurt their own on purpose:
- a damaged Wrath minion hits much harder;
- a Frenzy minion pays you back the first time it is hurt;
- fights in the mud trade minions without spending attacks.

It is the most aggressive class, and it pays for that with its own health.

| class | plan |
|---|---|
| Pilgrim | guards, healing, card draw, the late game |
| Ferryman | souls and tokens, Venom, Last Breath, board clears |
| Wanderer | Ruse sequencing, copy and steal, transforms, tempo |
| **Wrathful** | Wrath and Frenzy minions set off by self-damage, fights, burn paid for with health |

**Weaknesses:**
- Self-damage leaves it low against aggro (Ferryman's Malebranche Raid).
- Silence and transforms erase Wrath.
- Ward and Freeze blunt it.
- It has little healing and little card draw (Signal Fires, The Furies' Nails, The Boat Rides Low and the Mud-Choked
  Soul all cost health or minion health).

## Mechanics (exact rules)
**Wrath: +N Attack.** A minion property (`"wrath": N` on the card).
- While the minion is damaged (health below its max health), its Attack includes +N.
- Damage that leaves it alive turns Wrath on at once. The bonus counts for anything later in the same card, such as
  the next fight of *The Mob Turns*.
- Healing it to full turns Wrath off. A health buff raises health and max health together, so a damaged minion stays
  damaged.
- **Silence** removes Wrath (the bonus goes, other stat changes stay).
- **Transform** gives the new card's own Wrath, undamaged.
- **Copies** come in fresh from the hand; a board copy is always consistent with its own damage.
- **Rebirth** returns the minion with 1 Health. If that is below its max Health, it is damaged, so Wrath is on at once.
- **Freeze:** a frozen minion keeps its Wrath Attack but cannot attack.
- **Ward:** the blocked hit does no damage, so it sets off nothing.
- **Venom:** the minion dies, so nothing happens.

Engine: `Unit.wrath` (the bonus) and `Unit.rage` (the part of `attack` that is Wrath right now). `_update_wrath(u)`
runs after damage, healing, buffs and Silence. Every cleanup ends with `_refresh_wrath()`. The invariant
`rage == (wrath if health < max_health else 0)` is checked after every step of every soak game. Event:
`{"t": "wrath", "uid", "on", "attack"}`.

**Frenzy:** a trigger (`"on": "frenzy"`, text `Frenzy: ...`).
- It fires the first time the minion takes damage and survives, and only once (`Unit.frenzied`).
- It is queued when the blow lands. It fires at the end of the cleanup, after the whole card, attack or effect that
  hurt it has resolved and the dead are gone.
- It does not fire if the minion was killed (Venom included), bounced, transformed or silenced in the meantime. A
  Ward-blocked hit is not damage.
- Frenzy effects use automatic targets (`self`, `random_enemy_minion`, ...), like Last Breath.
- Event: `{"t": "frenzy", "uid"}` before its effects.

**Fight:** an op, `{"do": "fight", "target": T, "with": W}`.
- Each target fights each minion named by `with` (`self` by default, or `random_enemy_minion`,
  `random_friendly_minion`, `all_friendly_minions`), one pair at a time.
- In a fight, both minions deal damage equal to their Attack to each other at once. A Wrath bonus set off by the
  fight itself does not add to that fight.
- A fight is not an attack: it uses no attack, ignores Guard and Swift, and never involves a hero.
- Venom and Drain work as in combat; Ward blocks the hit. A pair where either minion is already dead is skipped.
  *The Mob Turns* therefore stops when its target dies.
- Event: `{"t": "fight", "a", "b", "src"}` before the two damage events.

**Self-damage** uses the existing ops on `own_hero`, `choose_friendly_minion`, `all_friendly_minions`, `all_minions`
and the new automatic target `all_other_minions` (every minion but the source).

Keyword tips (`UI.KEYWORD_HELP`):
- **Wrath:** "While this minion is damaged, it has the extra Attack."
- **Frenzy:** "Does something the first time it takes damage and survives."
- **Fight:** "Two minions deal damage equal to their Attack to each other."

"Wrath:" and "Frenzy:" are bold in the rules text, like the other trigger words.

## Hero power: Spite (2)
"Deal 1 damage to a minion and give it +1 Attack."

- **On your own minion,** it is the class engine. It turns Wrath on (a Wrathful Shade goes from 2/3 to 6/2), sets off
  a Frenzy, and gives +1 Attack to anything. The cost is 1 Health on a minion.
- **On an enemy,** it is a 1-damage ping that kills x/1 tokens. It makes any survivor stronger, so it is a real choice,
  not a free removal.

It adds no reach to the face (like Searing Word). It needs a board, so the class must keep minions alive to use it,
and it rewards high-health Wrath bodies.

Alternatives considered:
- **"Gain +1 Attack and take 1 damage"** on the hero: there are no hero weapons.
- **"Deal 2 damage to your hero, draw a card":** card draw is not this class's identity, and it doubles the
  self-damage against aggro.

## Card list (48 + 1 token)
Rarity: 24 common, 13 rare, 7 epic, 4 legendary. Type: 34 minions, 14 spells.

Curve: 0: 1, 1: 6, 2: 12, 3: 11, 4: 9, 5: 5, 6: 2, 7+: 2 (the Wanderer's exact curve).

| cost | card | rarity | stats | text | source |
|---|---|---|---|---|---|
| 0 | Gnawing Spite | C | spell | Deal 1 damage to a friendly minion. Draw a card. | VIII 63 |
| 1 | Mud Brawler | C | 1/2 | Wrath: +2 Attack. | VII 112 |
| 1 | Adimari Bravo | C | 3/2 | On Play: Deal 2 damage to your hero. | Filippo's kin |
| 1 | Mud-Choked Soul | R | 1/3 | Frenzy: Draw a card. | VII 121 (the sullen) |
| 1 | Tearing Teeth | C | spell | Deal 3 damage to a minion. Deal 2 damage to your hero. | VII 114 |
| 1 | Stirring the Mud | C | spell | Deal 1 damage to all minions. | VII 118 |
| 1 | Signal Fires | C | spell | Draw a card. Deal 2 damage to your hero. | VIII 1-6 |
| 2 | Wrathful Shade | C | 2/3 | Wrath: +3 Attack. | (moved from Upper Hell) |
| 2 | Mud Wrestler | C | 2/3 | Frenzy: Gain +2/+2. | VII |
| 2 | Self-Gnawing Shade | C | 1/4 | Wrath: +2 Attack. On Play: Deal 1 damage to this minion. | VIII 63 |
| 2 | Black Guelph Brawler | R | 2/2 | On Play: Fight an enemy minion. | Florence |
| 2 | Rabble-Rouser | C | 2/2 | On Play: Deal 1 damage to a minion and give it +2 Attack. | VIII 61 |
| 2 | Florentine Hothead | R | 2/2 | Swift. Wrath: +2 Attack. | Florence |
| 2 | Marsh Warden | C | 1/4 | Guard. Frenzy: Gain 3 Armor. | VII |
| 2 | Mud-Caked Sinner | C | 2/2 | Last Breath: Summon a 1/2 Mud Soul. | VII 110 |
| 2 | Scornful Soul | R | 2/3 | Drain. Wrath: +2 Attack. | VIII 44 |
| 2 | Butting Heads | R | spell | Give a friendly minion +1 Attack. It fights a random enemy minion. | XXXII 50 (the Alberti) |
| 2 | The Furies' Nails | C | spell | Deal 2 damage to a friendly minion. Draw 2 cards. | IX 49 |
| 2 | The Boiling Spring | R | spell | Deal 1 damage to your minions. Give them +1 Attack. | VII 101 |
| 3 | Stygian Brute | C | 3/4 | Wrath: +2 Attack. | VII |
| 3 | Brawling Shade | C | 3/3 | Frenzy: Fight a random enemy minion. | VII |
| 3 | Mud Dweller | C | 2/4 | Frenzy: Summon a 1/2 Mud Soul. | VII |
| 3 | Rinier Pazzo, the Mad | R | 4/3 | Swift. On Play: Deal 2 damage to your hero. | XII 137 |
| 3 | Tower Watchman | C | 2/5 | Guard. Wrath: +2 Attack. | VIII 4 |
| 3 | Erichtho, the Witch | E | 3/3 | On Play: Give a friendly minion Rebirth. | IX 23 |
| 3 | The Silver-Shod Horse | E | 3/3 | Swift. Frenzy: Gain +2 Attack. | Filippo's horse (commentators) |
| 3 | The Mob Turns | E | spell | Choose an enemy minion. Your minions fight it, one at a time. | VIII 61 |
| 3 | Brawl in the Mud | C | spell | Deal 2 damage to all minions. | VII 112 |
| 3 | Back With the Other Dogs | R | spell | Destroy an enemy minion. Deal 4 damage to your hero. | VIII 42 |
| 3 | The Boat Rides Low | R | spell | Draw 2 cards. Deal 1 damage to your minions. | VIII 27 |
| 4 | Drowned Knight | C | 4/5 | Wrath: +2 Attack. | VIII |
| 4 | Adimari Captain | C | 5/5 | On Play: Deal 3 damage to your hero. | Filippo's kin |
| 4 | Marsh Champion | R | 4/4 | On Play: Fight an enemy minion. | VII |
| 4 | **The Red Towers of Dis** | L | 0/6 | Guard. Wrath: +4 Attack. End of Turn: Deal 1 damage to all minions. | VIII 70 |
| 4 | Rancorous Shade | E | 3/5 | Rebirth. Wrath: +3 Attack. | VII |
| 4 | Geri del Bello | R | 4/5 | Wrath: +2 Attack. Last Breath: Deal 2 damage to a random enemy. | XXIX 27 |
| 4 | The Muddy Mob | C | 2/2 | On Play: Summon two 1/2 Mud Souls. | VII 110 |
| 4 | Black Guelph Captain | R | 3/5 | Frenzy: Give your other minions +1 Attack. | Florence |
| 4 | The Eternal Fire | C | spell | Deal 5 damage. Deal 2 damage to your hero. | VIII 73 |
| 5 | **Filippo Argenti** | L | 3/7 | Wrath: +3 Attack. End of Turn: Deal 1 damage to this minion. Last Breath: Deal 2 damage to all enemies. | VIII 31-63 |
| 5 | Mire Hulk | C | 5/6 | Wrath: +3 Attack. | VII |
| 5 | The Alberti Brothers | R | 3/3 | Wrath: +2 Attack. On Play: Summon a copy of this minion. | XXXII 55 |
| 5 | The Wrathful Throng | E | 5/5 | On Play: Deal 1 damage to all other minions. | VII |
| 5 | Storm Across the Styx | E | spell | Deal 3 damage to all minions. Give your minions +2 Attack. | IX 64-72 |
| 6 | **Tydeus, the Spiteful** | L | 5/6 | On Play: Fight an enemy minion. Frenzy: Fight a random enemy minion. | XXXII 130 |
| 6 | The Gate Slams Shut | E | spell | Deal 4 damage to all enemy minions. Deal 4 damage to your hero. | VIII 115 |
| 7 | **Athamas, the Maddened** | L | 4/8 | Wrath: +4 Attack. On Play: Deal 2 damage to all minions. | XXX 4 |
| 7 | Colossus of Mud | C | 5/9 | Guard. Wrath: +4 Attack. | VII |
| token | Mud Soul | - | 1/2 | Wrath: +2 Attack. | |

**Figures that already had a card (not duplicated):**
- Phlegyas (Pilgrim, the boatman who carries Dante: he stays there);
- the Furies (Ferryman); Medusa (neutral and Ferryman); the fallen angels at the gate (Ferryman);
- the heavenly messenger (Pilgrim); the Walls and Gate of Dis (neutral); Plutus (Ferryman); the sullen (neutral);
- the Minotaur and Capaneus (neutral), who are also wrathful.

The class names their places and gestures instead: the signal fires, the boat riding low, the Furies' nails, the gate
slammed shut, the storm of the messenger's arrival. It adds wrathful figures from elsewhere in the Inferno who have
no card yet:
- Tydeus gnawing Menalippus' skull (XXXII);
- the Alberti brothers butting heads in the ice (XXXII);
- maddened Athamas (XXX);
- Geri del Bello, unavenged (XXIX);
- Rinier Pazzo (XII);
- Erichtho, named by Virgil in IX.

There is no religious or esoteric symbol in any effect or prompt.

**The existing cards:**
- **Filippo Argenti** (`uh_filippo_argenti`, a neutral rare in Upper Hell). Its painting shows a man in the black
  water biting his own forearm, which is Filippo himself (VIII 63). It moved into the class as its legendary, keeping
  its id (owned copies and the painting stay), its flavour, and its old Last Breath (2 damage to all enemies, which
  `run_tests` relies on). It gained Wrath +3 and the End of Turn self-bite, and became 5 mana 3/7.
- **Wrathful Shade** (`uh_wrathful_shade`, a neutral common, a fist rising from the water). It moved into the class
  as its plain Wrath two-drop (2/3, Wrath: +3 Attack). It was in no preconstructed deck.
- **The Sullen** stays neutral. It is in *Cato's Vigil*, and a passive Guard fits anyone.
- **Phlegyas** stays with the Pilgrim (see above).

## Decks
| deck | id | plan | featured |
|---|---|---|---|
| **The Wrath of the Styx** (starter) | `wrath` | Midrange Wrath: sturdy Wrath bodies, Spite and cheap self-pings (Gnawing Spite, Rabble-Rouser) to set them off, Tearing Teeth for removal, Filippo, the Red Towers and Athamas on top. | Filippo Argenti, The Red Towers of Dis, Athamas |
| **The Mud Brawl** | `wrath_brawl` | Board control by fighting: Frenzy minions that pay back damage, fighters and The Mob Turns, Stirring the Mud and the Storm to set everything off, Tydeus to finish. | Tydeus, The Mob Turns, Brawling Shade |
| **Spite and Pride** | `wrath_pride` | All-out aggro: cheap Florentines that cost health, Swift riders (Hothead, Rinier Pazzo, the Silver-Shod Horse, Jason, Brutus), burn to the face (The Eternal Fire). | The Silver-Shod Horse, Rinier Pazzo, The Eternal Fire |

Balance: see `docs/BALANCE.md` (the 2026-10-27 Wrathful entry).

## AI notes
- **Hard / Medium (search):**
  - `evaluate` already sees raging Attack (it is part of `attack`), so pinging your own Wrath minion with Spite scores
    as a gain, and pinging an enemy only when the blow kills.
  - `_unit_value` adds a latent value for an undamaged Wrath minion (0.35 per point of Wrath, plus a little per point
    of health). An unfired Frenzy counts like any other trigger (+2) until it fires.
  - The search tries every target of fights and of the hero power. Self-damage that would kill the AI's own hero
    scores as a loss.
- **Easy (rules):**
  - `_goad_target` aims "hurt a friendly minion" cards and Spite / the Rabble-Rouser. It picks an enemy that dies to
    the blow, else the friend that gains most (Wrath not raging, an unfired Frenzy) and survives.
  - `_best_fight` aims fights at an enemy that dies, preferring one the fighter survives. A fighter minion with
    nothing worth fighting is played without a target.
  - Easy never pays hero health it cannot afford.
- Known limits:
  - The search does not look past the end of the turn, so the Red Towers and Filippo's End of Turn self-bite are
    valued only through their stats and the trigger bonus.
  - The AI does not plan a Rebirth into a raging comeback.

## View
- **A damaged Wrath minion:**
  - an ember aura (the shared `Aura` shader, preset `Aura.RAGE`, faster flames) that breathes with an angry pulse
    (`Aura.breathe`);
  - flame motes rising over the portrait and a warm tint;
  - its Attack number in ember orange.
- **Wrath turning on:** a blood-red flare, an ember ring, rising sparks, a growl and a "Wrath" plaque. Turning off
  gives a puff of smoke.
- **Frenzy:** a claw rake, red sparks, a roar and a "Frenzy" plaque.
- **Fight:** both minions wind back and rush to meet halfway, clash (hit-stop on heavy blows) in a spray of mud and
  dust, then fall back to their slots.
- **Medallions:** a Wrath minion shows the smouldering-coals medallion (`icon_ash`), a Frenzy minion the trigger
  medallion.
- **Hero power icon:** `icon_ash` until `icon_wrath` is painted.
- `tests/view_soak.gd` also checks that every minion's Attack, Health and Wrath glow match the rules.

## Art
`art_src/wrath_card_art.json` has 49 entries, in the Wanderer list's format:
- 46 cards and the Mud Soul token. The two moved cards are already painted.
- `hero_filippo_face`, the hero portrait (rarity `hero`).
- `icon_wrath`, the power icon (rarity `icon`).

Until the paintings arrive:
- cards show the Acheron placeholder (`CardDB.art`);
- the hero portrait is a crop of the existing Filippo Argenti painting (`assets/cards/heroes/filippo.jpg`).
  `CardDB.hero_art` also falls back to the Acheron for any hero without a portrait.
- The hero's `image` is `hero_filippo_face_s777` for `art_jobs.py dore`.
