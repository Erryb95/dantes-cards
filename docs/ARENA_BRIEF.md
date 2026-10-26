# Arena brief: the Shore of the Acheron (v2, painted board)

Enrico wants the arena to be serious work: a **game board** like Hearthstone's, not a landscape behind the cards.
The layout guide is `art_src/arena/acheron_layout_guide.png` (2560x1440). It shows every zone at the real
in-game coordinates; the 1920x1080 layout is scaled x1.333.

## What a Hearthstone board does (and ours should too)
- **Viewpoint:** a tabletop seen from about 55-60 degrees above, not a horizon view. The play area reads as a
  surface the cards lie on.
- **Detail:** the two minion zones are calm and low-contrast. All the detail and the interactive toys sit around
  the edges, in a carved frame.
- **Fixed sockets:** hero portraits sit in fixed sockets (plinths), with a socket for the hero power. There is a
  socket for the end-turn button, niches for the decks and trays for the mana crystals.
- **Lighting:** light pools on the centre; the edges and corners fall into darkness (vignette) so cards and VFX pop.

## Composition (Doré hand-tinted engraving, the same house style as the cards)
- **Far bank (top, enemy side, y 0-420):**
  - a muddy grey shore;
  - the far crowd of naked souls waiting, small and in the distance at the top edge;
  - Charon's landing stage.
- **The Acheron (middle band, y 420-524 in 1080 units):**
  - dark, calm water running left to right;
  - keep it smooth, because the river shader adds ripples on top.
- **Near bank (bottom, player side, y 524-1080):** dark wet stone and pebbles, the rock the pilgrim stands on.
- **Frame:**
  - rough cliff rock and carved stone around all four edges;
  - the Gate of Hell's stonework could form the top corners;
  - roots and bones in the lower corners.
- **Sockets (painted into the board, empty inside):**
  - two round stone **hero plinths** (radius about 128), at the top centre (960,143) and the bottom centre (960,801),
    mirrored about the divider (y 472);
  - a smaller round **power socket** (radius 52) beside each, at (1140,129) and (1140,815);
  - an oval **end-turn recess** of about 250x130 at (1745,472), sitting on the river's right edge like a stone
    landing;
  - two **deck niches** carved in the right cliff, at (1800,312) and (1800,632);
  - two **mana trays** of about 520x90, at the top right and the bottom right.
- **Interactive toy spots** (props that react to taps, painted separately, see layer D):
  - left cliff top (90-240, 210-370): the bell on its gallows;
  - left middle (50-290, 600-765): the gate inscription tablet;
  - right bottom corner: a brazier;
  - left bottom corner: a pile of skulls.

## Layers to paint (one image each, seed 777)
| Layer | Size | Alpha | Notes |
|---|---|---|---|
| `arena_acheron_board` | 2560x1440 | opaque | The whole board: banks, river, frame and sockets. Low detail in the two minion zones (350-1570 x 254-450 and 494-690). No props, no people near the centre. |
| `arena_acheron_frame` | 2560x1440 | transparent centre | Optional: only the carved/cliff frame and the sockets, so it can sit above the river shader for depth. |
| `arena_acheron_mist` | 2560x512 | alpha | Soft fog band, tileable left-right, drifted over the river by code. |
| D `prop_boat` | 768x384 | alpha | Charon's boat side-on, with Charon poling and the lantern lit; it crosses the river. |
| D `prop_bell` | 384x512 | alpha | A bronze bell hanging from a wooden gallows. |
| D `prop_tablet` | 512x384 | alpha | A stone tablet with carved lines (no readable letters). |
| D `prop_brazier` | 384x512 | alpha | An iron brazier with coals (its flame is code VFX). |
| D `prop_skulls` | 512x384 | alpha | A pile of skulls and bones. |

## The other boards (same sockets, same layers)
Limbo, Lust, Dis and Cocytus reuse this layout exactly: `arena_<id>_board` (2560x1440), `arena_<id>_mist`
(2560x512 alpha) and `prop_<id>_<name>` (alpha) per `data/arenas.json`. The middle divider is painted calm and the
code adds its life: Limbo's stream (water shader), Lust's wind (`wind.gdshader` + streaks + whirling souls at the
edges), Dis's ember crack (`crack.gdshader` + heat haze + sparks) and Cocytus's frost crack (rime, glints, cold mist).
Flames on props (the tomb, the torch) are code VFX: paint them unlit.

Each board has its own 3D blockout (same orthographic camera at 55 degrees, same sockets and socket ID colours,
mirrored socket pairs built from one mesh, perfectly flat minion zones, detail on the frame only) in
`art_src/arena/blockout_<id>/`, made by `tools/blender/board_blockout.py --arena=<id>` + `tools/arena/passes.py`;
`tools/arena/upload_blockout.py [--tag=<tag>] <id>` sends the passes to the ComfyUI PC as
`<id>_<tag>_board_<pass>.png` (id, clay, depth, lineart, normal; tag `bo` by default, `bo2` for the symmetric
orthographic blockouts). The Acheron's stays in `art_src/arena/blockout/`.
- Limbo: flat meadow, a thin stream sunk along the middle (no banks), the stepped walls and towers of the Noble
  Castle only along the top edge (the enemy hero stands in the gate), soft grassy hillocks at the sides.
- Lust: flat rock plateau, a slightly lower smooth wind channel across the middle, jagged cliffs and spires only
  on the left, right and top frame.
- Dis: flat paving, one straight ember crack (shallow groove), iron walls on the top and side edges, open tombs on
  the side frames.
- Cocytus: flat ice, one thin straight crack, sinners in ice blocks on the side frames, Lucifer's wings fanning
  out along the top edge.

## Phones (20:9)
- **Wider screens:** they show extra width at the sides. Either paint the board 3200x1440 with the 2560 centre as
  the safe area, or keep 2560 wide, and the game will extend the edges with a dark vignette.
- **Safe area:** everything important stays inside the centre 2560x1440.

## Don'ts
- No text or letters, no modern objects.
- No strong perspective vanishing point in the middle: the cards must not look like they float above a horizon.
- No bright highlights inside the minion zones.
