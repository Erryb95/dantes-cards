# Living art: the authoring guide

Living art brings a card's still painting to life in the card shader: water runs, flames rise, smoke drifts, hair and
leaves sway, eyes glow, frost glints, ash falls. It costs no GPU job and no video. Each card's look comes from data:

- its entry in `data/living_art.json`;
- the masks that `tools/cards/living_mask.py` paints from the entry's recipe into `assets/cards/living/`.

The code is in three places:
- the shader: `assets/shaders/living_art.gdshaderinc`, included by `card_fx`;
- `ArtLiving` (`scripts/battle/art_living.gd`);
- CardDB: `living`, `living_mask`, `living_flowmap` and `living_fx`.

**Rule for authoring a card (phase 2):** you touch only two things:
- your own cards' entries in `data/living_art.json`;
- the files the tool writes for them: `assets/cards/living/<id>.png`, `<id>_flow.png`, `<id>_fx.png` and their
  `.import` files.

The shader, `ArtLiving`, CardDB and the tools are frozen, so everything you need must be in the vocabulary below. If it
is not, report it instead of patching.

The reference cards are worked examples of every common case. Read their entries next to their sheets:

| Card | What it shows |
|---|---|
| `mc_lucifer` | ice: ripple, glint, snow; glowing veins and eyes; wings |
| `phlegyas` | water: a flow with ripple, a boat and bodies as figures, moonlight, fog |
| `cd_capaneus` | fire rain, flames, smoke, firelight on armour |
| `minos` | a monster: glowing eyes over a protected face, smoke, side fires, a breathing chest |
| `pj_harpy_of_the_wood` | a forest: branches sway, fog in the far trees by a depth band, glowing wounds, trickling blood |

`francesca` is the original whirl, written in the legacy recipe format. Leave it alone.

## 1. Look at the card and choose its layers

Make the grid and look at the picture big. Name what would move in the real scene. Then pick at most **five or six
things** that move, and let the rest stay still. A few calm, true motions read better than everything wobbling.

```
python -I tools/cards/living_mask.py --grid <id> --preview <scratch dir>
```

This writes `<id>_grid.png`, the picture with a UV grid. Read every coordinate off it: x across, y down, both 0..1 of
the full picture.

**Where the picture is seen:**
- On the card face (the hand, the collection, the zoom), only about the **top 60 %** shows (y < 0.6). The name ribbon
  and the rules text cover the rest.
- The board portrait is an oval around y 0.15–0.55.

So the motion that matters lives in the upper part. Motion at the bottom (Lucifer's ice, for example) is a bonus, and
it is never enough by itself.

| In the picture | Layer | Notes |
|---|---|---|
| a river, the Styx, the sea, a boiling river, pitch | `flow` + `ripple` | flow drifts the paint along its direction; ripple adds rolling wave crests |
| a still lake, ice with water | `ripple` only (flow 0) + `glint` | Cocytus: crests and sparkle, no drift |
| lava, blood or molten cracks | `flow` (slow) + a `glow` layer | warm filter, so only the bright red paint pulses |
| flames | `fire` | rise, flicker, glow and haze are entry keys |
| smoke, clouds, fog | `flow` (slow, with a `bright` or `dark` filter) or a `mist` layer | flow moves the painted clouds; mist lays a moving veil over them |
| ash, fire rain, sparks, snow, rain | a `fall` layer | `streak` gives rain and fire rain, `flutter` gives snow and ash, `life` makes sparks blink out; `dir` [0, -1] makes them rise |
| eyes, lamps, the moon, a lighthouse, a brazier | a `glow` layer | over a protected face, paint it with `"over": true` |
| hair, cloth, capes, feathers, wings | `sway` | hair and cloth flutter down the entry's `wind`, ramped from root to tip |
| branches, leaves, a second wind | a `sway` layer | own speed, scale, gust and direction; it must have a `name` |
| sun shafts | a `rays` layer | parallel shafts along `dir`; never a halo or a cross |
| lightning | a `flash` layer | rare double strokes; one card in ten at most |
| heat over a fire or lava | `fire` haze, or a `haze` layer | full level only |
| a chest or a monster breathing | a `breathe` layer | a slow swell around `center` |
| a whirlpool or a vortex | `flow` with `"vortex"` | or the legacy whirl (`swirl`, as on Francesca) |

**Never animate:**
- faces;
- text or lettering;
- crisp outlines that would wobble: weapons, crowns, architecture, boats, horses' legs.

**No religious or esoteric symbols.** Rays are parallel shafts, glints are round points, and nothing draws halos,
crosses, stars or sigils.

## 2. Write the entry

```json
"phlegyas": {
  "note": "one line: what moves",
  "period": 1.8, "flow": 0.014,
  "ripple": 0.0022, "ripple_scale": 130, "ripple_speed": 2.4, "ripple_light": 0.25,
  "sway": 0.003, "wind": [1.0, -0.2],
  "layers": [ {"name": "moon", "kind": "glow", "strength": 0.35, ...}, ... ],
  "mask": { "regions": [...], "figures": [...], "still": [...], "protect": [...] }
}
```

### Entry keys (ArtLiving.PARAMS)

UV is a fraction of the picture's height.

| Key | Default | Meaning |
|---|---|---|
| `period` | 2.0 | seconds per flow cycle: the drift resets, cross-faded, every period, so the picture never tears |
| `flow` | 0 | flow speed where the flow mask is 1, in UV per second. Water 0.010–0.016, smoke and clouds 0.006–0.012 |
| `ripple` | 0 | the ripple's lift, in UV: 0.0012–0.0025 |
| `ripple_scale` | 140 | crests per picture height × 2π (140 puts a crest about every 32 px of a 704 px picture) |
| `ripple_speed` | 2.5 | how fast the crests roll, in radians per second |
| `ripple_light` | 0.15 | how much the crests shimmer: 0.15–0.3 |
| `rise` | 0 | the flames' upward flow, in UV per second: 0.010–0.02 |
| `flicker` | 0 | the trembling of the firelight: 0.3–0.55 |
| `glow` | 0 | the flames' breathing light: 0.08–0.14 |
| `haze` | 0 | heat shimmer over the flames, in UV: 0.0012–0.002 (full level only) |
| `sway` | 0 | the flutter of the `sway` paint, in UV: 0.002–0.004 |
| `wind` | [1, 0] | the direction the sway runs; also the default direction of flow regions and of mist and sway layers |
| `swirl`, `vortex`, `spiral`, `churn`, `embers`, `ember_color` | | the legacy whirl and its sparks (Francesca). `embers` turn round `vortex`; elsewhere use a `fall` layer |
| `note` | | free text: what the card does |

### Layers (at most 3; ArtLiving.KINDS)

Each layer is `{"kind": K, "name": N, ...parameters, "color": [r, g, b], "dir": [x, y]}`.
- `name` defaults to the kind, but a `sway` layer must have its own `name`.
- `dir` is a direction in the picture's pixels, with y down.

| Kind | Parameters (defaults) | Colour | Use |
|---|---|---|---|
| `glow` | strength 0.35, speed 1.2 (rad/s), flicker 0.3 (0 = smooth breath, 1 = trembling), spread 4 (phase change across the picture, so lamps do not pulse in step), flicker_scale 8 | [1, 0.55, 0.2] | eyes, lamps, lava, cracks, the moon |
| `glint` | strength 0.8, density 0.35, size 0.010, speed 0.5 (twinkles/s), bright 0.45 (the paint luminance where glints show) | [0.85, 0.95, 1] | ice, frost, water and metal sparkle |
| `mist` | strength 0.35, speed 0.02 (UV/s), scale 3 (puffs per height), softness 0.2 | [0.6, 0.6, 0.62] | smoke (a dark colour), fog (a pale one); `dir` defaults to the wind |
| `fall` | density 0.4, speed 0.12 (UV/s), size 0.006, streak 0 (length ×), flutter 0, brightness 1, blend 0 (0 adds light, 1 paints the colour), life 0 (blinks per second; 0 = steady) | [1, 0.6, 0.25] | snow: size 0.0035, flutter 0.8, speed 0.035. Fire rain: streak 5, speed 0.28, density 0.2. Rain: streak 9, size 0.0018, speed 0.6. Sparks: dir [0, -1], life 0.6 |
| `flash` | strength 0.6, period 7 (s on average) | [0.85, 0.9, 1] | lightning on the sky and the bolt |
| `rays` | strength 0.12, speed 0.15, scale 9 (shafts across) | [1, 0.8, 0.5] | sun shafts along `dir` |
| `sway` | amount 0.004 (UV), speed 2.4, scale 34, gust 0.35 | | branches: amount 0.006, speed 1.0, scale 14, gust 0.6 |
| `haze` | amount 0.0015, speed 1.6, scale 30 | | heat shimmer without fire (full level only) |
| `breathe` | amount 0.006, speed 1.4, `center` [x, y] | | a chest, wings: 0.04–0.06 reads on a 0.1 UV region |

Kinds that move the paint are `sway`, `haze`, `breathe`, `flow` and `ripple`. Kinds that only light it are `glow`,
`glint`, `mist`, `fall`, `flash` and `rays`.

## 3. The mask recipe

The full vocabulary is also at the top of `tools/cards/living_mask.py`. Regions are painted in order.

### Region

```json
{"layer": "flow" | "fire" | "sway" | "ripple" | "<layer name>" | ["flow", "ripple"],
 <shapes>, <filters>, "value": 1.0, "op": "max" | "sub", <direction>, "over": false, "note": "..."}
```

**Shapes.** A region takes the union of its shapes. Each key takes one shape or a list:
- `"all": true`;
- `"rect": [x0, y0, x1, y1]`;
- `"ellipse": [cx, cy, rx, ry]`;
- `"poly": [[x, y], ...]`.

Shape options:
- `"feather"` (0.018 UV): how soft the edge is;
- `"grow"` (mask pixels, + or −);
- `"minus": {shapes}`: cuts a hole.

**Filters** multiply the region by the picture's own paint. Each `[lo, hi]` is a soft threshold:
- `bright`: luminance;
- `dark`: below the luminance;
- `warm`: red − blue;
- `cool`: blue − red;
- `sat`: saturation;
- `grey`: low saturation;
- `depth`: a band of the depth map (near = 1, far = 0), softened by `depth_soft` (0.04).

They are blurred by `soften` (2 px). There is also a ramp: `"ramp": {"from": [x, y], "to": [x, y]}` is 0 at `from`
and 1 at `to`. Hair and branches ramp from root to tip.

**Direction**, for `flow` and `ripple`:
- `"dir": [x, y]`;
- `"vortex": [cx, cy]`, with `"turn"` (1 is clockwise) and `"spiral"` (0.2);
- `"toward": [x, y]` or `"away": [x, y]`.

A later region overrides an earlier one's direction where it covers it.

**The value.** For `flow`, the value is also the speed share: clouds at 0.4, water at 1.

**Ripple.** Ripple crests always lie across the picture, as on water seen from the side. The direction only drifts
them.

**`"op": "sub"`** erases the layer there, for example ripple across a body at the waterline.

**`"over": true`** paints after protection. Only light layers can use it, for eyes in a protected face.

### Global lists

Each item is an ellipse `[cx, cy, rx, ry]`, a polygon `[[x, y], ...]` or `{shapes}`.

| List | What it keeps out |
|---|---|
| `figures` | flow, fire and ripple: bodies, boats and rocks in the water; anything the flow must go around |
| `still` | every displacement, sway layers included (light layers still shine): the moon, weapons, a serpent's head |
| `protect` | everything, in every mask. **Every face** in or near moving paint, even small ones in a crowd. A protect ellipse is solid inside its outline and fades out within 25 % beyond it |

Run the check, then the preview:

```
python -I tools/cards/living_mask.py --only <id> --check
python -I tools/cards/living_mask.py --only <id> --preview <scratch dir>
```

The check validates the entry and prints what each layer covers, with warnings. The preview writes the masks and
`<id>_mask.png`, a sheet with four panels:
1. the picture;
2. the base mask (R flow, G fire, B sway), with outlines: protect magenta, still cyan, figures white;
3. the flow map: yellow arrows, red flow, cyan ripple;
4. the layer slots (R / G / B with their names).

Fix the shapes until the sheet is right. Then run
`timeout 300 <godot> --headless --path . --import`, so Godot imports the new pngs.

## 4. Record, measure, judge

```
python -I tools/cards/living_review.py <id> --out <scratch dir>/living_review
```

The script runs `tests/living_preview.tscn` through Godot's movie maker. It writes:
- `<id>_art.mp4`: the whole picture, still on the left and living on the right;
- `<id>_zoom.mp4`: the card as the collection's zoom shows it;
- `<id>_heat.png`: where the picture moves;
- the motion numbers, with a verdict against the targets.

Options:
- `--level 1` reviews the lite level;
- `--views art` skips the zoom;
- `--measure-only` re-measures frames already recorded.

Delete the frame folders when done.

| Number | Francesca (approved) | Target | Meaning |
|---|---|---|---|
| consecutive | 0.38 % | 0.15–0.8 % | the mean change from one frame to the next: how busy it is |
| area>10% | 30 % | 10–50 % | the share of the picture that visibly lives |
| faces | 0 % (lovers) | ≤ 16 %, main faces ≈ 0 | the 95th percentile of the peak change inside the protect shapes' cores. Light painted over a face on purpose (`over`) is left out |

The reference cards at the full level, measured over 4 s:

| Card | consecutive | area>10% | faces | notes |
|---|---|---|---|---|
| `mc_lucifer` | 0.46 % | 52 % | 0 % | snow covers the whole picture |
| `phlegyas` | 0.23 % | 11 % | 0 % | |
| `cd_capaneus` | 0.50 % | 43 % | 0 % | |
| `minos` | 0.10 % | 11 % | 0 % | |
| `pj_harpy_of_the_wood` | 0.10 % | 14 % | 0 % | |

The numbers only guide you. **Watch the mp4.** Ask three questions:
- Does it read as alive from a metre away?
- Is anything wobbling that should be solid?
- Is any face, outline or lettering bending?

Slow layers (mist, sway, breathe) score a low "consecutive" and can still be right: `minos` and the harpy are slow on
purpose. Particles over the whole picture raise "area" (Lucifer's snow). Judge those by eye.

## 5. Pitfalls we hit

- **The hidden bottom.** Lucifer's rippling ice sits mostly under the card's rules text. Check the zoom mp4: the motion
  you want people to see must be in the top 60 %.
- **Ripple direction.** Ripple crests that run along the flow look like a grid. The ripple now always lies across the
  picture, and the flow only drifts it. Use `ripple_light` ≤ 0.3, or the crests turn into stripes.
- **Glow filters.** A wide warm filter on skin made a whole chest pulse. Keep glow filters tight: warm ≥ 0.25 and
  bright ≥ 0.35 for cracks and veins. Use ellipses for eyes and lamps.
- **Clouds and branches.** Flowing clouds dragged the dark branches in front of them. Add a `bright` filter to the
  cloud region, and keep the moon `still`.
- **Small faces.** A small face in a crowd needs its own protect ellipse. Paint flowing next to a face still drags
  the face's colours a few pixels outward at its rim, so keep strong flows a little away from faces.
- **Figures.** Without `figures` around boats and bodies, water drifts straight through them.
- **Fire filters.** Fire on `"all": true` with a warm / bright filter also catches warm skin and gold. Cut it with
  `figures` or a `sub` region.
- **Particle density.** Particles over the whole picture read as busy above density 0.35, and above 0.2 for streaks.
  On a small hand card each particle is never drawn below a pixel; it grows fainter instead.
- **Particle direction.** `fall` with no `dir` falls straight down. Fire rain on Capaneus follows the painted drops,
  [-0.33, 1].
- **Layer names.** A `sway` layer needs a `name`: the base `sway` already uses the word.
- **Frame size.** The movie maker records at the window's size (1600x900 on this PC); the review tool scales its
  boxes to it.
- **Line endings.** Keep `data/living_art.json` valid JSON with LF line endings. Python's `write_text` on Windows
  writes CRLF.
- **Merges.** Parallel agents all edit one file. Add each entry as its own block. When merging, keep both sides.

## 6. Per-card checklist

1. Make the grid. Name the five or six things that move and leave the rest still.
2. Write the entry: a `note`, the motion keys, at most 3 `layers` and the `mask` regions.
3. Protect every face. Make figures of bodies, boats and rocks in moving paint. Make `still` the crisp props in
   moving areas.
4. Run `living_mask.py --only <id> --check`: no errors, no surprising warnings.
5. Run `living_mask.py --only <id> --preview <dir>`, look at the sheet and fix the shapes.
6. Run `godot --headless --import`.
7. Run `living_review.py <id>`, watch both mp4s and read the numbers:
   - consecutive in 0.15–0.8 % (or slow on purpose);
   - area 10–50 %;
   - main faces ≈ 0.
8. Run `living_review.py <id> --level 1 --views art`. The lite level must still look right: no haze, fewer
   particles.
9. Check that nothing symbolic appeared and that no lettering bends.
10. Commit only your entry and your `assets/cards/living/<id>*` files, with their `.import` files.

## 7. Performance

- **Cards without living art.** Every other card skips all of this on one uniform test, `living_level == 0`.
- **What a living card costs.**
  - Texture taps per art pixel: the base mask, one or two art taps (the flow cross-fade), and the flow map and layer
    mask when the card has them.
  - Noise calls per pixel, only where a mask is non-zero:
    - ripple: 3;
    - glow: 2;
    - mist: 4 fbm, or 1 at lite;
    - fall: 2 cell layers, or 1 at lite;
    - glint: 1 cell;
    - fire: 1–4.
- **Branches.** The layer kind is a uniform, so its branch is coherent on every GPU, the Compatibility / GLES3
  renderer included.
- **Lite level** (the 30 fps frame limit): no heat haze, no `haze` layers, no embers, one layer of falling
  particles, single-octave noise for fire and mist.
- **Masks.** Each is 256x352 RGB, lossless: 1–60 KB on disk, about 270 KB in memory, and loaded only when the card
  is shown.
- **Budget.** Keep three layers at most (the format enforces it). Prefer one `fall` layer per card, and avoid `mist`
  over the whole picture.
