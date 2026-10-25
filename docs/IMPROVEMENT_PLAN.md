# Improvement plan after v0.1 (review of 2026-10-25)

Benchmarks: Hearthstone (juice, board toys, voice), Marvel Snap (mobile-first, 3-minute games, readable cards),
Legends of Runeterra (clarity, keyword UX, champions that level up), Slay the Spire (run structure, rewards, relics),
Inscryption (atmosphere, a diegetic board), Gwent (art-led premium and animated cards).

## Where v0.1 stands
**Strong:** the Doré art and the arena backdrop already carry the identity. The rules, AI, tests and event-driven
animations are solid, and both platforms build.

**Weak:**
- **Placeholder UI:** generic StyleBox frames, vector sword and drop gems, flat bell and tablet, rounded "beds".
- **Phone layout:** too small on a phone.
- **Shallow loop:** one fight and no progression.
- **Weak feedback:** effects and sounds are shallow, and some effects are crude.

## Phase 0: defects seen in the screenshots (½ day)
1. END TURN glows green during the mulligan (the glow is visible by default before the first refresh).
2. Area effects use a shockwave scaled to about 60x, which draws a huge flat ring over the screen. Redraw it by
   radius with a thin line.
3. The mulligan title overlaps Charon's portrait and health. Dim the heroes harder or move the title.
4. The result screen is never captured by the screenshot tool (it quits too early). This is a tool fix.
5. Hand cards are cut off at the bottom and their names are unreadable on a phone (see Phase 2).

## Phase 1: AAA look (2-3 sessions, mostly art from the ComfyUI session)
| Item | How | Who |
|---|---|---|
| Ornate card frames per rarity and type (minion oval, spell arch) | Doré-engraved gold frame PNG, 9-slice or full overlay with alpha | ComfyUI → me |
| Painted gems: mana, attack, health, armor, rarity | Five small icon sheets with alpha (BiRefNet rmbg) | ComfyUI |
| Hero power icons (Dante shield, Charon coin) and a painted END TURN button with states | Icons and button art | ComfyUI |
| Diegetic board: stone ledges or wooden jetties on the two shores instead of UI panels | Two alpha strips painted to match the backdrop | ComfyUI |
| Board toys: painted bell, inscription stone, Charon's boat sprite (replacing the code silhouettes) | Alpha props + a Wan loop for the boat | ComfyUI |
| Real 3D-like card tilt (perspective shader on the hand card and on inspect) | A SubViewport per hovered card + a vertex-skew shader | me |
| Legendary entrances: a short cut-in (art pan, name, sting) | Tween + shader | me |
| Animated legendaries (Minos, Francesca, Ugolino) | Wan 2.2 loops, played on the board and in the hand | ComfyUI → me |
| Golden / foil premium versions of cards | Shader (already have foil sweep) + gold frame variant | me |

## Phase 2: mobile first (1-2 sessions)
- **Layout:** pick one of the two options below (Enrico decides).
  - Keep landscape: scale the UI to the shorter side, show hand cards at 0.8 with a big tap-to-zoom, and give minions
    1.3x hit areas.
  - **Portrait layout** like Marvel Snap and Hearthstone mobile: two lanes, bigger cards.
- **Gestures:** long-press zoom everywhere; haptics on play and hit (Input.vibrate_handheld).
- **Performance:** 60 fps on a mid-range Android, profiling the burn shader and particles. Compress the textures
  (ETC2) and keep the APK under 80 MB.
- **Lifecycle:** handle pause / resume and save the battle on app switch.

## Phase 3: the game loop (the biggest gap vs. the market) (3-4 sessions)
- **Run map** (Slay-the-Spire style) through the circles. Each circle is an arena with its own boss and board toys:
  - Dark Wood (the three beasts: lion, panther, she-wolf);
  - Acheron (Charon);
  - Limbo;
  - Minos;
  - the Lustful (Francesca);
  - Cerberus;
  - Plutus;
  - Styx (Phlegyas);
  - Dis (the Furies);
  - ... down to Lucifer.
- **Rewards:** after each win, pick 1 of 3 cards. Add relics ("Virgil's Lantern", "Beatrice's Grace"), gold, and a
  shop / rest-site (remove or upgrade a card).
- **Deck builder** and a collection that unlocks cards as you go.
- **Champion-style legendaries** that level up (Runeterra): e.g. Virgil upgrades after you draw 5 cards.
- **New keywords** that fit the contrapasso theme: Rebirth, Frenzy, Silence, "Contrapasso" (punishes the mechanic
  the enemy uses).
- **AI:** difficulty levels and one-turn lookahead (simulate a clone of BattleState).

## Phase 4: feel and audio (1-2 sessions)
- **Per-card sounds:** play, attack and death (CC0 libraries: Kenney, Sonniss GDC bundles, Freesound CC0).
- **Hit-stop** (a 60-90 ms freeze on big hits), damage-scaled shake, and number counters that roll.
- **Music:** combat and boss layers, and a victory stinger. Keep public-domain recordings only.
- **Voice lines:** short ones for heroes and legendaries. Recorded or public-domain only, no AI voices.
- **Onboarding:** a 3-step tutorial fight with Virgil guiding (the Hearthstone "Jaina vs Illidan" pattern).

## Phase 5: product (later)
- **Localisation:** Italian (Dante's original lines as flavour), English, Spanish.
- **Accessibility:** colour-blind palettes, text size, reduced motion.
- **Retention:** achievements, daily trials, cloud save.
- **Store:** release keystore and Play Store listing, Steam page (macOS/iOS need a Mac for signing).
- **PvP:** only if the single-player loop is proven. The event-driven BattleState is already the right seam.

## Suggested order for tonight
Phase 0 (all) → Phase 1 frames + gems + board strips (ask ComfyUI now; it runs in parallel) → Phase 3 run map
skeleton with 3 stops (Dark Wood → Acheron → Limbo) and the card-reward screen.
