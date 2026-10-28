#!/usr/bin/env python3
"""Masks for the living card art (data/living_art.json, ArtLiving, assets/shaders/living_art.gdshaderinc).

The authoring guide is docs/LIVING_ART.md. No GPU, no model: the masks are painted from plain shapes, the picture's own
colours and its depth map. All coordinates are UV of the full picture assets/cards/art/<id>.jpg (0..1, y down).

OUTPUT, per card listed in data/living_art.json (at the depth map's size: half the picture):
  assets/cards/living/<id>.png       the base mask, always:  R flow, G fire, B sway
  assets/cards/living/<id>_flow.png  the flow map, when a region gives a direction or a ripple:
                                     RG the flow's direction (0.5 = none), B ripple
  assets/cards/living/<id>_fx.png    the layer slots, when the entry has "layers": one channel per layer (R, G, B)
A file the recipe no longer needs is deleted. Then run `godot --headless --import` so Godot writes the .png.import.

THE ENTRY (data/living_art.json "cards" -> "<id>"): motion parameters (see ArtLiving.PARAMS and docs/LIVING_ART.md),
optional "layers" (at most 3 slots, each {"kind": K, "name": N (default K), ...its parameters, "color", "dir"}), and
the "mask" recipe:

  "mask": {
    "regions": [ REGION, ... ],   painted in order (a later region overrides an earlier one's direction)
    "figures": [ SHAPE, ... ],    no flow, fire or ripple here (the outline of a figure never bends)
    "still":   [ SHAPE, ... ],    no displacement at all (birds, weapons, crowns); light layers still shine
    "protect": [ SHAPE, ... ]     faces: black in every channel of every mask (a region with "over": true may light
                                  them again, light layers only: glowing eyes)
  }

  LAYER names a region can paint: "flow" (R: the paint drifts along the region's direction; the value is its speed
  share), "fire" (G), "sway" (B: hair, cloth, wings, leaves, with the entry's "wind"), "ripple" (the flow map's B:
  waves along the region's direction), or the "name" of one of the entry's layers. "layer" may be a list
  (["flow", "ripple"] for water).

  REGION = one or more SHAPES, times every FILTER, times "value" (default 1):
    shapes (union; any of them, each one or a list):
      "all": true                       the whole picture
      "rect": [x0, y0, x1, y1]
      "ellipse": [cx, cy, rx, ry]
      "poly": [[x, y], [x, y], ...]     at least 3 points
      "feather": 0.018                  blur of the shapes' edges, UV of the picture's height
      "grow": 0                         grow (+) or shrink (-) the shapes first, in mask pixels
      "minus": {shapes}                 a hole (the same shape keys, feathered alike)
    filters (each multiplies; [lo, hi] are soft thresholds, smoothstep from lo to hi):
      "bright": [lo, hi]  luminance above        "dark": [lo, hi]  luminance below (1 under lo, 0 over hi)
      "warm":   [lo, hi]  red - blue above       "cool": [lo, hi]  blue - red above
      "sat":    [lo, hi]  saturation above       "grey": [lo, hi]  saturation below
      "depth":  [lo, hi]  the depth map's band (near = 1, far = 0), soft by "depth_soft" (0.04)
      "ramp": {"from": [x, y], "to": [x, y]}     0 at "from" rising to 1 at "to" (a list of ramps multiplies)
      "soften": 2.0       blur of the colour / depth filters, mask pixels (default 2 when any is used)
    "op": "max" (default: the layer is at least this here) or "sub" (erase the layer here)
    direction (flow and ripple regions; the default is the entry's "wind", else [1, 0]):
      "dir": [x, y]                          a direction in the picture's pixels (y down): [0, 1] falls
      "vortex": [cx, cy], "spiral": 0.2, "turn": 1    round a centre (turn 1 clockwise on screen, -1 the other way)
      "toward": [x, y]  /  "away": [x, y]    into / out of a point
    "over": true        painted after "protect" and "still" (light layers only)

  SHAPE in figures / still / protect: [cx, cy, rx, ry] (an ellipse), [[x, y], ...] (a polygon) or {shapes}.

  Legacy keys (Francesca's recipe, kept exactly): "swirl": {"fade_y": [y0, y1]} (R everywhere but the figures,
  fading out toward the bottom), "flame": {"warm": [lo, hi], "bright": [lo, hi]} (G on warm bright paint),
  "sway": [{"ellipse": [cx, cy, rx, ry], "from": [x_root, x_tip]}] (B ramped along x). Without "regions" a recipe is
  read the old way (R and G on by default).

Usage:
  python -I tools/cards/living_mask.py [--only id,id] [--check] [--preview <dir or file.png>]
  python -I tools/cards/living_mask.py --grid id,id --preview <dir>   (the pictures with a UV grid, to read coordinates)
    --check    validate the entries and print what each mask covers, write nothing
    --preview  also save a sheet per card: the picture, the base mask over it (outlines: protect magenta, still cyan,
               figures white), the flow map (arrows, ripple cyan) and the layer slots (R / G / B with their names)
"""
import argparse
import json
import math
import site
import sys
from pathlib import Path

sys.path.append(site.getusersitepackages())

import numpy as np  # noqa: E402
from PIL import Image, ImageDraw, ImageFilter, ImageFont  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "data/living_art.json"
OUT = ROOT / "assets/cards/living"
FEATHER = 0.018  # blur radius of every shape, in UV of the picture's height

# The layer kinds of the "layers" slots, as in ArtLiving.KINDS (keep the two in step): kind -> its parameters.
DISPLACE = {"sway": ["amount", "speed", "scale", "gust"], "haze": ["amount", "speed", "scale"],
            "breathe": ["amount", "speed", "center_x", "center_y"]}
LIGHT = {"glow": ["strength", "speed", "flicker", "spread", "flicker_scale"],
         "glint": ["strength", "density", "size", "speed", "bright"],
         "mist": ["strength", "speed", "scale", "softness"],
         "fall": ["density", "speed", "size", "streak", "flutter", "brightness", "blend", "life"],
         "flash": ["strength", "period"], "rays": ["strength", "speed", "scale"]}
KINDS = {**DISPLACE, **LIGHT}
LAYER_KEYS = {"name", "kind", "color", "dir", "center", "note"}
PARAM_KEYS = {"vortex", "swirl", "spiral", "churn", "period", "rise", "flicker", "glow", "haze", "sway", "wind",
              "embers", "ember_color", "flow", "ripple", "ripple_scale", "ripple_speed", "ripple_light"}
BASE = {"flow": 0, "fire": 1, "sway": 2}
SHAPE_KEYS = {"all", "rect", "ellipse", "poly", "feather", "grow", "minus"}
FILTER_KEYS = {"bright", "dark", "warm", "cool", "sat", "grey", "depth", "depth_soft", "ramp", "soften"}
REGION_KEYS = SHAPE_KEYS | FILTER_KEYS | {"layer", "value", "op", "dir", "vortex", "spiral", "turn", "toward",
                                          "away", "over", "note"}


class RecipeError(ValueError):
    pass


def _ellipse(size, e, scale=1.0):
    w, h = size
    cx, cy, rx, ry = e
    im = Image.new("L", size, 0)
    ImageDraw.Draw(im).ellipse([(cx - rx * scale) * w, (cy - ry * scale) * h, (cx + rx * scale) * w,
                                (cy + ry * scale) * h], fill=255)
    return im


def _soft(im, radius_uv, size):
    return np.asarray(im.filter(ImageFilter.GaussianBlur(radius_uv * size[1])), np.float32) / 255.0


def _smooth(lo, hi, x):
    t = np.clip((x - lo) / max(1e-6, hi - lo), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _blur(a, px):
    if px <= 0:
        return a
    im = Image.fromarray(np.clip(a * 255 + 0.5, 0, 255).astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.GaussianBlur(px)), np.float32) / 255.0


def _pair(v, what):
    if not (isinstance(v, list) and len(v) == 2 and all(isinstance(x, (int, float)) for x in v)):
        raise RecipeError("%s must be [a, b], got %r" % (what, v))
    return float(v[0]), float(v[1])


def _many(v, single_depth):
    """A shape value that is either one shape or a list of them (told apart by nesting depth)."""
    d, x = 0, v
    while isinstance(x, list) and x:
        d, x = d + 1, x[0]
    return [v] if d == single_depth else list(v)


class Card:
    def __init__(self, card_id):
        self.id = card_id
        art = Image.open(ROOT / f"assets/cards/art/{card_id}.jpg").convert("RGB")
        depth = ROOT / f"assets/cards/depth/{card_id}.png"
        self.size = Image.open(depth).size if depth.exists() else (art.width // 2, art.height // 2)
        w, h = self.size
        self.art = art.resize(self.size, Image.LANCZOS)
        self.rgb = np.asarray(self.art, np.float32) / 255.0
        self.lum = self.rgb @ np.array([0.3, 0.59, 0.11], np.float32)
        self.depth = (np.asarray(Image.open(depth).convert("L").resize(self.size, Image.BILINEAR), np.float32) / 255.0
                      if depth.exists() else None)
        self.ys = (np.arange(h, dtype=np.float32)[:, None] + 0.5) / h
        self.xs = (np.arange(w, dtype=np.float32)[None, :] + 0.5) / w
        self.ones = np.ones((h, w), np.float32)

    # --- shapes ---
    def shapes(self, spec, ellipse_scale=1.0):
        """The union of a spec's shapes, hard-edged (an L image), or None when it names none."""
        w, h = self.size
        im = Image.new("L", self.size, 0)
        dr = ImageDraw.Draw(im)
        found = False
        if spec.get("all"):
            dr.rectangle([0, 0, w, h], fill=255)
            found = True
        for r in _many(spec["rect"], 1) if "rect" in spec else []:
            if len(r) != 4:
                raise RecipeError("rect must be [x0, y0, x1, y1], got %r" % (r,))
            dr.rectangle([min(r[0], r[2]) * w, min(r[1], r[3]) * h, max(r[0], r[2]) * w, max(r[1], r[3]) * h],
                         fill=255)
            found = True
        for e in _many(spec["ellipse"], 1) if "ellipse" in spec else []:
            if len(e) != 4:
                raise RecipeError("ellipse must be [cx, cy, rx, ry], got %r" % (e,))
            cx, cy, rx, ry = e
            dr.ellipse([(cx - rx * ellipse_scale) * w, (cy - ry * ellipse_scale) * h,
                        (cx + rx * ellipse_scale) * w, (cy + ry * ellipse_scale) * h], fill=255)
            found = True
        for p in _many(spec["poly"], 2) if "poly" in spec else []:
            if len(p) < 3 or any(len(q) != 2 for q in p):
                raise RecipeError("poly needs at least 3 [x, y] points, got %r" % (p,))
            dr.polygon([(x * w, y * h) for x, y in p], fill=255)
            found = True
        if not found:
            return None
        grow = int(spec.get("grow", 0))
        if grow > 0:
            im = im.filter(ImageFilter.MaxFilter(2 * grow + 1))
        elif grow < 0:
            im = im.filter(ImageFilter.MinFilter(-2 * grow + 1))
        return im

    def shape_field(self, spec):
        im = self.shapes(spec)
        if im is None:
            raise RecipeError("a region needs a shape (all / rect / ellipse / poly): %r" % (spec,))
        f = _soft(im, float(spec.get("feather", FEATHER)), self.size) if not spec.get("all") or len(spec) > 1 \
            else self.ones.copy()
        if spec.get("all") and not any(k in spec for k in ("rect", "ellipse", "poly", "grow")):
            f = self.ones.copy()
        if "minus" in spec:
            hole = self.shapes(spec["minus"])
            if hole is None:
                raise RecipeError("minus needs a shape: %r" % (spec["minus"],))
            f *= 1.0 - _soft(hole, float(spec["minus"].get("feather", spec.get("feather", FEATHER))), self.size)
        return f

    def list_field(self, items, ellipse_scale, feather):
        """still / protect: ellipses [cx, cy, rx, ry], polygons [[x, y], ...] or shape dicts, each feathered on its
        own (the strongest wins)."""
        out = np.zeros((self.size[1], self.size[0]), np.float32)
        w, h = self.size
        for it in items:
            if isinstance(it, dict):
                im = self.shapes(it, ellipse_scale)
                if im is None:
                    raise RecipeError("empty shape %r" % (it,))
            elif isinstance(it, list) and len(it) == 4 and all(isinstance(v, (int, float)) for v in it):
                im = _ellipse(self.size, it, ellipse_scale)
            elif isinstance(it, list) and len(it) >= 3 and all(isinstance(q, list) and len(q) == 2 for q in it):
                im = Image.new("L", self.size, 0)
                ImageDraw.Draw(im).polygon([(x * w, y * h) for x, y in it], fill=255)
            else:
                raise RecipeError("a shape must be [cx, cy, rx, ry], [[x, y], ...] or {...}: %r" % (it,))
            out = np.maximum(out, _soft(im, feather, self.size))
        return out

    # --- filters ---
    def filter_field(self, spec):
        f = self.ones.copy()
        used = False
        r, g, b = self.rgb[..., 0], self.rgb[..., 1], self.rgb[..., 2]
        sat = self.rgb.max(-1) - self.rgb.min(-1)
        for key, val in (("bright", self.lum), ("warm", r - b), ("cool", b - r), ("sat", sat)):
            if key in spec:
                lo, hi = _pair(spec[key], key)
                f *= _smooth(lo, hi, val)
                used = True
        for key, val in (("dark", self.lum), ("grey", sat)):
            if key in spec:
                lo, hi = _pair(spec[key], key)
                f *= 1.0 - _smooth(lo, hi, val)
                used = True
        if "depth" in spec:
            if self.depth is None:
                raise RecipeError("%s has no depth map (assets/cards/depth/%s.png) for a depth band" % (self.id, self.id))
            lo, hi = _pair(spec["depth"], "depth")
            s = float(spec.get("depth_soft", 0.04))
            f *= _smooth(lo - s, lo + s, self.depth) * (1.0 - _smooth(hi - s, hi + s, self.depth))
            used = True
        if used:
            f = _blur(f, float(spec.get("soften", 2.0)))
        ramps = spec.get("ramp", [])
        for rp in [ramps] if isinstance(ramps, dict) else ramps:
            (x0, y0), (x1, y1) = _pair(rp.get("from"), "ramp from"), _pair(rp.get("to"), "ramp to")
            w, h = self.size
            dx, dy = (x1 - x0) * w, (y1 - y0) * h
            t = ((self.xs - x0) * w * dx + (self.ys - y0) * h * dy) / max(1e-6, dx * dx + dy * dy)
            f *= _smooth(0.0, 1.0, t)
        return f

    def region_field(self, spec):
        return np.clip(self.shape_field(spec) * self.filter_field(spec) * float(spec.get("value", 1.0)), 0.0, 1.0)

    # --- directions (in the picture's pixels) ---
    def direction(self, spec, wind):
        w, h = self.size
        if "vortex" in spec:
            cx, cy = _pair(spec["vortex"], "vortex")
            px, py = (self.xs - cx) * w * self.ones, (self.ys - cy) * h * self.ones
            rr = np.sqrt(px * px + py * py) + 1e-6
            turn = float(spec.get("turn", 1.0))
            sp = float(spec.get("spiral", 0.2))
            vx, vy = -py / rr * turn - px / rr * sp, px / rr * turn - py / rr * sp
        elif "toward" in spec or "away" in spec:
            key = "toward" if "toward" in spec else "away"
            cx, cy = _pair(spec[key], key)
            sgn = 1.0 if key == "toward" else -1.0
            px, py = (cx - self.xs) * w * self.ones, (cy - self.ys) * h * self.ones
            vx, vy = px * sgn, py * sgn
        else:
            ux, uy = _pair(spec.get("dir", wind), "dir")
            vx, vy = ux * self.ones, uy * self.ones
        n = np.sqrt(vx * vx + vy * vy) + 1e-9
        return vx / n, vy / n


def _layers(entry):
    out = {}
    layers = entry.get("layers", [])
    if not isinstance(layers, list) or len(layers) > 3:
        raise RecipeError("layers must be a list of at most 3")
    for i, it in enumerate(layers):
        k = it.get("kind") if isinstance(it, dict) else None
        if k not in KINDS:
            raise RecipeError("layer %d: unknown kind %r (one of %s)" % (i, k, ", ".join(KINDS)))
        name = it.get("name", k)
        if name in out or name in BASE or name == "ripple":
            raise RecipeError("layer name %r used twice (or clashes with flow / fire / sway / ripple)" % name)
        for key in it:
            if key not in LAYER_KEYS and key not in KINDS[k]:
                raise RecipeError("layer %s: unknown key %r (it takes %s)" % (name, key, ", ".join(KINDS[k])))
        out[name] = (i, k)
    return out


def check_entry(card_id, entry):
    for key in entry:
        if key not in PARAM_KEYS and key not in ("mask", "layers", "note") and not key.startswith("_"):
            raise RecipeError("unknown entry key %r" % key)
    layers = _layers(entry)
    for i, r in enumerate(entry.get("mask", {}).get("regions", [])):
        for key in r:
            if key not in REGION_KEYS:
                raise RecipeError("region %d: unknown key %r" % (i, key))
        names = r.get("layer")
        for n in names if isinstance(names, list) else [names]:
            if n not in BASE and n != "ripple" and n not in layers:
                raise RecipeError("region %d paints layer %r, which is not flow / fire / sway / ripple or a layer"
                                  % (i, n))
            if r.get("over") and (n in BASE or n == "ripple" or layers[n][1] in DISPLACE):
                raise RecipeError("region %d: 'over' is for light layers only (%r moves the paint)" % (i, n))
        if r.get("op", "max") not in ("max", "sub"):
            raise RecipeError("region %d: op must be max or sub" % i)
    return layers


def build(card_id, entry):
    """The masks of one card: (base RGB, flow map RGB or None, fx RGB or None, info dict)."""
    recipe = entry.get("mask", {})
    layers = check_entry(card_id, entry)
    c = Card(card_id)
    size, (w, h) = c.size, c.size
    rgb, xs, ys = c.rgb, c.xs, c.ys
    legacy = "regions" not in recipe
    wind = entry.get("wind", [1.0, 0.0])

    # Legacy channels (Francesca), computed exactly as before.
    fig = Image.new("L", size, 0)
    for poly in recipe.get("figures", []):
        if isinstance(poly, list) and len(poly) >= 3 and all(isinstance(q, list) and len(q) == 2 for q in poly):
            ImageDraw.Draw(fig).polygon([(x * w, y * h) for x, y in poly], fill=255)
        elif isinstance(poly, dict):
            s = c.shapes(poly)
            fig = Image.fromarray(np.maximum(np.asarray(fig), np.asarray(s)))
        elif isinstance(poly, list) and len(poly) == 4:
            fig = Image.fromarray(np.maximum(np.asarray(fig), np.asarray(_ellipse(size, poly))))
        else:
            raise RecipeError("a figure must be a polygon, an ellipse or {...}: %r" % (poly,))
    # Grown a little before the feather, so the flow fades out before it reaches an outline (no ghost of the edge).
    figure = _soft(fig.filter(ImageFilter.MaxFilter(5)), FEATHER * 1.4, size)
    zero = np.zeros((h, w), np.float32)
    r = zero.copy()
    g = zero.copy()
    if legacy or "swirl" in recipe:
        sw = recipe.get("swirl", {})
        fade = sw.get("fade_y", [1.0, 1.0])
        r = (1.0 - _smooth(fade[0], fade[1], ys)) * np.ones_like(xs) * (1.0 - figure)
    if legacy or "flame" in recipe:
        fl = recipe.get("flame", {})
        warm_lo, warm_hi = fl.get("warm", [0.12, 0.34])
        br_lo, br_hi = fl.get("bright", [0.22, 0.55])
        warm = _smooth(warm_lo, warm_hi, rgb[..., 0] - rgb[..., 2])
        lum = rgb @ np.array([0.3, 0.59, 0.11], np.float32)
        g = warm * _smooth(br_lo, br_hi, lum)
        g = np.asarray(Image.fromarray((g * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2.0)),
                       np.float32) / 255
        g *= 1.0 - figure
    b = zero.copy()
    for s in recipe.get("sway", []):
        e = s["ellipse"]
        x0, x1 = s.get("from", [e[0] - e[2], e[0] + e[2]])
        ramp = _smooth(min(x0, x1), max(x0, x1), xs) if x1 >= x0 else 1.0 - _smooth(x1, x0, xs)
        b = np.maximum(b, _soft(_ellipse(size, e), FEATHER, size) * ramp)

    # Regions.
    base = [zero.copy(), zero.copy(), zero.copy()]
    rip = zero.copy()
    dvx, dvy = zero.copy(), zero.copy()
    has_dir = False
    fx = [zero.copy() for _ in range(3)]
    over = []
    for spec in recipe.get("regions", []):
        f = c.region_field(spec)
        names = spec.get("layer")
        names = names if isinstance(names, list) else [names]
        sub = spec.get("op", "max") == "sub"
        if spec.get("over"):
            over.append((spec, f, names))
            continue
        for n in names:
            ch = base[BASE[n]] if n in BASE else rip if n == "ripple" else fx[layers[n][0]]
            if sub:
                ch *= 1.0 - f
            else:
                np.maximum(ch, f, out=ch)
            if n in ("flow", "ripple") and not sub:
                ux, uy = c.direction(spec, wind)
                dvx += (ux - dvx) * f
                dvy += (uy - dvy) * f
                has_dir = True
    for ch in (base[0], base[1], rip):
        ch *= 1.0 - figure
    r = np.maximum(r, base[0])
    g = np.maximum(g, base[1])
    b = np.maximum(b, base[2])

    still = c.list_field(recipe.get("still", []), 1.15, FEATHER)
    if not legacy:  # solid inside its own outline, fading out in the 15% beyond it (legacy: soft all through)
        still = np.clip(still * 2.0, 0.0, 1.0)
    r *= 1.0 - still
    g *= 1.0 - still * 0.85  # a bird over the fire may glow with it, but must not ripple
    rip *= 1.0 - still
    if not legacy:  # (Francesca's starlings sit outside her hair, so her recipe never needed it)
        b *= 1.0 - still
    for name, (i, k) in layers.items():
        if k in DISPLACE:
            fx[i] *= 1.0 - still

    protect = c.list_field(recipe.get("protect", []), 1.25, FEATHER)
    if not legacy:  # a face is black all over, the protection fading out in the 25% beyond its outline
        protect = np.clip(protect * 2.0, 0.0, 1.0)
    keep = 1.0 - protect
    rip *= keep
    for ch in fx:
        ch *= keep
    for spec, f, names in over:
        for n in names:
            ch = fx[layers[n][0]]
            if spec.get("op", "max") == "sub":
                ch *= 1.0 - f
            else:
                np.maximum(ch, f, out=ch)

    def img(chs):
        return Image.fromarray(np.clip(np.stack(chs, -1) * 255 + 0.5, 0, 255).astype(np.uint8), "RGB")

    out = np.stack([r * keep, g * keep, b * keep], -1)
    base_im = Image.fromarray(np.clip(out * 255 + 0.5, 0, 255).astype(np.uint8), "RGB")
    flow_im = None
    if has_dir or rip.max() > 0.0:
        n = np.sqrt(dvx * dvx + dvy * dvy)
        ok = n > 1e-3
        ux = np.where(ok, dvx / np.maximum(n, 1e-9), 0.0)
        uy = np.where(ok, dvy / np.maximum(n, 1e-9), 0.0)
        flow_im = img([ux * 0.5 + 0.5, uy * 0.5 + 0.5, rip])
    fx_im = img(fx) if layers else None
    info = {"card": c, "layers": layers, "protect": recipe.get("protect", []), "still": recipe.get("still", []),
            "figures": recipe.get("figures", []),
            "cover": {"flow": float((r * keep > 0.05).mean()), "fire": float((g * keep > 0.05).mean()),
                      "sway": float((b * keep > 0.05).mean()), "ripple": float((rip > 0.05).mean()),
                      **{n: float((fx[i] > 0.05).mean()) for n, (i, k) in layers.items()}}}
    return base_im, flow_im, fx_im, info


def warnings(card_id, entry, info):
    out = []
    cov = info["cover"]
    if cov["flow"] > 0 and float(entry.get("flow", 0)) == 0 and float(entry.get("swirl", 0)) == 0:
        out.append("flow is painted but the entry's flow and swirl are 0: it will not move")
    if cov["fire"] > 0 and not any(float(entry.get(k, 0)) for k in ("rise", "flicker", "glow", "haze")):
        out.append("fire is painted but rise / flicker / glow / haze are all 0")
    if cov["sway"] > 0 and float(entry.get("sway", 0)) == 0:
        out.append("sway is painted but the entry's sway is 0")
    if cov["ripple"] > 0 and float(entry.get("ripple", 0)) == 0 and float(entry.get("ripple_light", 0.15)) == 0:
        out.append("ripple is painted but the entry's ripple is 0")
    for n, (i, k) in info["layers"].items():
        if cov[n] == 0:
            out.append("layer %s (%s) covers nothing: no region paints it" % (n, k))
    if (cov["flow"] > 0.02 or cov["fire"] > 0.02 or cov["sway"] > 0.02) and not info["protect"]:
        out.append("no 'protect' shapes: is there really no face in the moving paint?")
    return out


def _outline(dr, items, size, color, scale=1.0):
    w, h = size
    for it in items:
        if isinstance(it, list) and len(it) == 4 and all(isinstance(v, (int, float)) for v in it):
            cx, cy, rx, ry = it
            dr.ellipse([(cx - rx * scale) * w, (cy - ry * scale) * h, (cx + rx * scale) * w, (cy + ry * scale) * h],
                       outline=color, width=2)
        elif isinstance(it, list) and len(it) >= 3:
            dr.line([(x * w, y * h) for x, y in it] + [(it[0][0] * w, it[0][1] * h)], fill=color, width=2)
        elif isinstance(it, dict):
            for e in _many(it["ellipse"], 1) if "ellipse" in it else []:
                _outline(dr, [e], size, color, scale)
            for p in _many(it["poly"], 2) if "poly" in it else []:
                _outline(dr, [p], size, color)
            for rc in _many(it["rect"], 1) if "rect" in it else []:
                dr.rectangle([rc[0] * w, rc[1] * h, rc[2] * w, rc[3] * h], outline=color, width=2)


def preview(card_id, entry, base_im, flow_im, fx_im, info, path, scale=1.5):
    c = info["card"]
    size = (int(c.size[0] * scale), int(c.size[1] * scale))
    art = c.art.resize(size, Image.LANCZOS)
    dim = Image.blend(art, Image.new("RGB", size, 0), 0.55)
    font = ImageFont.load_default()
    panels = []

    a = Image.blend(art, base_im.resize(size, Image.BILINEAR), 0.6)
    dr = ImageDraw.Draw(a)
    _outline(dr, info["figures"], size, (255, 255, 255))
    _outline(dr, info["still"], size, (0, 255, 255), 1.15)
    _outline(dr, info["protect"], size, (255, 0, 255), 1.25)
    panels.append((art, "picture"))
    panels.append((a, "base: R flow  G fire  B sway"))

    if flow_im is not None:
        fm = np.asarray(flow_im.resize(size, Image.BILINEAR), np.float32) / 255.0
        bm = np.asarray(base_im.resize(size, Image.BILINEAR), np.float32) / 255.0
        p = np.asarray(dim, np.float32) / 255.0
        p = p * (1 - fm[..., 2:3] * 0.7) + np.array([0.2, 0.9, 1.0]) * fm[..., 2:3] * 0.7
        p = p * (1 - bm[..., 0:1] * 0.5) + np.array([1.0, 0.3, 0.2]) * bm[..., 0:1] * 0.5
        fl = Image.fromarray(np.clip(p * 255, 0, 255).astype(np.uint8))
        dr = ImageDraw.Draw(fl)
        step = 22
        for y in range(step // 2, size[1], step):
            for x in range(step // 2, size[0], step):
                amt = max(bm[y, x, 0], fm[y, x, 2])
                if amt < 0.08:
                    continue
                vx, vy = fm[y, x, 0] * 2 - 1, fm[y, x, 1] * 2 - 1
                n = math.hypot(vx, vy)
                if n < 0.05:
                    continue
                L = 9 * (0.4 + 0.6 * amt)
                ex, ey = x + vx / n * L, y + vy / n * L
                dr.line([(x - vx / n * L * 0.5, y - vy / n * L * 0.5), (ex, ey)], fill=(255, 230, 60), width=2)
                dr.ellipse([ex - 2, ey - 2, ex + 2, ey + 2], fill=(255, 230, 60))
        panels.append((fl, "flow map: arrows, red flow, cyan ripple"))
    if fx_im is not None:
        f = Image.blend(dim, fx_im.resize(size, Image.BILINEAR), 0.7)
        names = sorted(info["layers"].items(), key=lambda kv: kv[1][0])
        label = "  ".join("%s %s(%s)" % ("RGB"[i], n, k) for n, (i, k) in names)
        panels.append((f, "fx: " + label))
    sheet = Image.new("RGB", (size[0] * len(panels), size[1] + 22), (16, 16, 16))
    dr = ImageDraw.Draw(sheet)
    for i, (im, label) in enumerate(panels):
        sheet.paste(im, (i * size[0], 22))
        dr.text((i * size[0] + 6, 5), label, fill=(255, 255, 150), font=font)
    dr.text((sheet.width - 150, 5), card_id, fill=(255, 255, 255), font=font)
    sheet.save(path)
    return path


def grid(card_id, path, scale=1.5):
    """The picture with a UV grid (lines every 0.05, numbers every 0.1), for reading coordinates off it."""
    art = Image.open(ROOT / f"assets/cards/art/{card_id}.jpg").convert("RGB")
    w, h = int(art.width * scale), int(art.height * scale)
    im = art.resize((w, h), Image.LANCZOS)
    dr = ImageDraw.Draw(im, "RGBA")
    font = ImageFont.load_default()
    for i in range(1, 20):
        t = i / 20
        major = i % 2 == 0
        col = (255, 255, 0, 150) if major else (255, 255, 255, 60)
        dr.line([(t * w, 0), (t * w, h)], fill=col, width=1)
        dr.line([(0, t * h), (w, t * h)], fill=col, width=1)
        if major:
            dr.text((t * w + 2, 2), "%.1f" % t, fill=(255, 255, 0, 255), font=font)
            dr.text((2, t * h + 2), "%.1f" % t, fill=(255, 255, 0, 255), font=font)
    im.save(path)
    return path


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--only", default="")
    ap.add_argument("--check", action="store_true", help="validate and report, write nothing")
    ap.add_argument("--preview", default="", help="a directory (or a .png for one card) for the review sheets")
    ap.add_argument("--grid", default="", help="card ids: save each picture with a UV grid to --preview's directory")
    a = ap.parse_args()
    if a.grid:
        d = Path(a.preview or ".")
        d = d.parent if d.suffix.lower() == ".png" else d
        d.mkdir(parents=True, exist_ok=True)
        for card_id in a.grid.split(","):
            print("grid:", grid(card_id, d / f"{card_id}_grid.png"))
        return
    cards = json.loads(DATA.read_text(encoding="utf-8"))["cards"]
    only = [s for s in a.only.split(",") if s]
    for s in only:
        if s not in cards:
            sys.exit("living mask: %s is not in data/living_art.json" % s)
    OUT.mkdir(parents=True, exist_ok=True)
    failed = False
    for card_id, entry in cards.items():
        if only and card_id not in only:
            continue
        try:
            base_im, flow_im, fx_im, info = build(card_id, entry)
        except (RecipeError, KeyError, TypeError) as e:
            print("living mask: %s: ERROR %s" % (card_id, e))
            failed = True
            continue
        cov = ", ".join("%s %.0f%%" % (k, v * 100) for k, v in info["cover"].items() if v > 0)
        print("living mask: %s %s  covers %s" % (card_id, base_im.size, cov or "nothing"))
        for wmsg in warnings(card_id, entry, info):
            print("  warning:", wmsg)
        if not a.check:
            base_im.save(OUT / f"{card_id}.png", optimize=True)
            for suffix, im in (("_flow", flow_im), ("_fx", fx_im)):
                p = OUT / f"{card_id}{suffix}.png"
                if im is not None:
                    im.save(p, optimize=True)
                else:
                    for stale in (p, p.with_name(p.name + ".import")):
                        if stale.exists():
                            stale.unlink()
        if a.preview:
            pv = Path(a.preview)
            if pv.suffix.lower() != ".png" or (len(only) != 1 and len(cards) != 1):
                pv = (pv if pv.suffix.lower() != ".png" else pv.parent) / f"{card_id}_mask.png"
            pv.parent.mkdir(parents=True, exist_ok=True)
            print("  preview:", preview(card_id, entry, base_im, flow_im, fx_im, info, pv))
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
