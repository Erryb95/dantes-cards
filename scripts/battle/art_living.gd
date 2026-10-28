class_name ArtLiving
## Living art: a card's still painting brought to life in the card shader (card_fx + living_art.gdshaderinc). Water
## flows, flames rise, smoke drifts, hair and leaves sway, eyes and lamps glow, frost glints, ash falls; faces, figures
## and shapes that must keep their outline stay put (the card's masks). Data-driven: a card comes alive when
## data/living_art.json lists it and its masks (assets/cards/living/<id>.png, plus <id>_flow.png / <id>_fx.png when the
## recipe needs them, from tools/cards/living_mask.py) are installed; every other card is untouched. Authoring guide:
## docs/LIVING_ART.md.
## Hooked next to ArtDepth wherever card art is drawn (CardView: hand, collection, zoom, play reveal; MinionView: the
## board portrait). Pure setup: the motion runs on the GPU from TIME, so there is nothing to update per frame.
##
## Quality: `level()` is FULL, LITE when the frame limit is 30 (no heat haze, no embers, one layer of falling
## particles, cheaper noise), and DV_LIVING=0/1/2 forces it (0 = off, the still painting, to compare).

enum { OFF, LITE, FULL }

## Entry key -> shader uniform, with the value used when the entry leaves it out.
const PARAMS := {
	"vortex": ["living_vortex", Vector2(0.5, 0.3)],
	"swirl": ["living_swirl", 0.0],
	"spiral": ["living_spiral", 0.2],
	"churn": ["living_churn", 0.0],
	"period": ["living_period", 2.0],
	"rise": ["living_rise", 0.0],
	"flicker": ["living_flicker", 0.0],
	"glow": ["living_glow", 0.0],
	"haze": ["living_haze", 0.0],
	"sway": ["living_sway", 0.0],
	"wind": ["living_wind", Vector2(1, 0)],
	"embers": ["living_embers", 0.0],
	"ember_color": ["living_ember_color", Color(1.0, 0.62, 0.25)],
	"flow": ["living_flow_speed", 0.0],
	"ripple": ["living_ripple", 0.0],
	"ripple_scale": ["living_ripple_scale", 140.0],
	"ripple_speed": ["living_ripple_speed", 2.5],
	"ripple_light": ["living_ripple_light", 0.15],
}

## Entry keys that are not shader parameters.
const OTHER_KEYS := ["mask", "layers", "note"]

## The layer kinds of the "layers" slots (at most MAX_LAYERS per card): kind -> [shader id, parameter defaults in the
## order they fill the slot's two vec4 (s.xyzw, t.xyzw), default colour, default direction (null = the entry's wind)].
## The shader's comments and docs/LIVING_ART.md say what each one does.
const KINDS := {
	"glow": [1, {"strength": 0.35, "speed": 1.2, "flicker": 0.3, "spread": 4.0, "flicker_scale": 8.0},
		Color(1.0, 0.55, 0.2), Vector2(0, 1)],
	"glint": [2, {"strength": 0.8, "density": 0.35, "size": 0.010, "speed": 0.5, "bright": 0.45},
		Color(0.85, 0.95, 1.0), Vector2(0, 1)],
	"mist": [3, {"strength": 0.35, "speed": 0.02, "scale": 3.0, "softness": 0.2}, Color(0.6, 0.6, 0.62), null],
	"fall": [4, {"density": 0.4, "speed": 0.12, "size": 0.006, "streak": 0.0, "flutter": 0.0, "brightness": 1.0,
		"blend": 0.0, "life": 0.0}, Color(1.0, 0.6, 0.25), Vector2(0, 1)],
	"flash": [5, {"strength": 0.6, "period": 7.0}, Color(0.85, 0.9, 1.0), Vector2(0, 1)],
	"rays": [6, {"strength": 0.12, "speed": 0.15, "scale": 9.0}, Color(1.0, 0.8, 0.5), Vector2(0.3, 1)],
	"sway": [7, {"amount": 0.004, "speed": 2.4, "scale": 34.0, "gust": 0.35}, Color(1, 1, 1), null],
	"haze": [8, {"amount": 0.0015, "speed": 1.6, "scale": 30.0}, Color(1, 1, 1), Vector2(0, -1)],
	"breathe": [9, {"amount": 0.006, "speed": 1.4, "center_x": 0.5, "center_y": 0.5}, Color(1, 1, 1), Vector2(0, 1)],
}
const MAX_LAYERS := 3
## Keys of a "layers" item that are not kind parameters.
const LAYER_KEYS := ["name", "kind", "color", "dir", "center", "note"]

static var forced := -1 ## tests / previews: a level to use instead of level()


## How much of the living art runs here.
static func level() -> int:
	if forced >= 0:
		return forced
	var env := OS.get_environment("DV_LIVING")
	if env != "":
		return clampi(int(env), OFF, FULL)
	var tree := Engine.get_main_loop() as SceneTree
	var settings: Node = tree.root.get_node_or_null("Settings") if tree != null else null
	if settings != null and int(settings.get("frame_limit")) == 30:
		return LITE
	return FULL


## True when card `id` has living art installed (an entry and its masks).
static func has(id: String) -> bool:
	var e := CardDB.living(id)
	if e.is_empty() or not CardDB.has_art(id) or CardDB.living_mask(id) == null:
		return false
	return e.get("layers", []).is_empty() or CardDB.living_fx(id) != null


## The shader uniforms for a living-art entry (every key of PARAMS, typed, defaults filled in).
static func params(entry: Dictionary) -> Dictionary:
	var out := {}
	for key in PARAMS:
		var uniform_name: String = PARAMS[key][0]
		var fallback = PARAMS[key][1]
		out[uniform_name] = _typed(entry.get(key, null), fallback)
	return out


## The uniforms of the entry's layer slots (living_k0..2, living_s0..2, living_t0..2, living_c0..2, living_d0..2);
## unused slots get kind 0.
static func slots(entry: Dictionary) -> Dictionary:
	var out := {}
	var layers: Array = entry.get("layers", [])
	var wind: Vector2 = _typed(entry.get("wind", null), Vector2(1, 0))
	for i in MAX_LAYERS:
		var kind := 0
		var s := Vector4.ZERO
		var t := Vector4.ZERO
		var col := Color(1, 1, 1)
		var dir := Vector2(0, 1)
		if i < layers.size() and layers[i] is Dictionary and KINDS.has(str(layers[i].get("kind", ""))):
			var item: Dictionary = layers[i]
			var spec: Array = KINDS[str(item.kind)]
			kind = spec[0]
			var vals: Array[float] = []
			var defaults: Dictionary = spec[1]
			for key in defaults:
				vals.append(float(_typed(item.get(key, null), defaults[key])))
			if str(item.kind) == "breathe" and item.get("center", null) is Array and item.center.size() >= 2:
				vals[2] = float(item.center[0])
				vals[3] = float(item.center[1])
			while vals.size() < 8:
				vals.append(0.0)
			s = Vector4(vals[0], vals[1], vals[2], vals[3])
			t = Vector4(vals[4], vals[5], vals[6], vals[7])
			col = _typed(item.get("color", null), spec[2])
			dir = _typed(item.get("dir", null), spec[3] if spec[3] != null else wind)
		out["living_k%d" % i] = kind
		out["living_s%d" % i] = s
		out["living_t%d" % i] = t
		out["living_c%d" % i] = col
		out["living_d%d" % i] = dir.normalized() if dir.length() > 0.0 else Vector2(0, 1)
	return out


static func _typed(v, fallback):
	if fallback is Vector2:
		return Vector2(float(v[0]), float(v[1])) if v is Array and v.size() >= 2 else fallback
	if fallback is Color:
		return Color(float(v[0]), float(v[1]), float(v[2])) if v is Array and v.size() >= 3 else fallback
	return float(v) if v is float or v is int else fallback


## What is wrong with a living-art entry (empty when it is valid): unknown keys, bad layers, regions naming a layer
## that is not there. tools/cards/living_mask.py checks the mask's shapes in depth; this is the game's own guard.
static func problems(entry: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key in entry:
		if not PARAMS.has(key) and key not in OTHER_KEYS and not str(key).begins_with("_"):
			out.append("unknown key %s" % key)
	var names := ["flow", "fire", "sway", "ripple"]
	var layers = entry.get("layers", [])
	if not layers is Array or layers.size() > MAX_LAYERS:
		out.append("layers must be a list of at most %d" % MAX_LAYERS)
		layers = []
	for item in layers:
		if not item is Dictionary or not KINDS.has(str(item.get("kind", ""))):
			out.append("layer %s: unknown kind" % str(item))
			continue
		var n := str(item.get("name", item.kind))
		if n in names:
			out.append("layer name %s used twice" % n)
		names.append(n)
		for key in item:
			if key not in LAYER_KEYS and not KINDS[item.kind][1].has(key):
				out.append("layer %s: unknown key %s" % [n, key])
	var mask = entry.get("mask", {})
	if not mask is Dictionary:
		out.append("mask must be an object")
		return out
	for r in mask.get("regions", []):
		var ls = r.get("layer", null) if r is Dictionary else null
		for l in (ls if ls is Array else [ls]):
			if str(l) not in names:
				out.append("region names layer %s, which the entry does not have" % str(l))
	return out


## Brings the framed art of `card_id` to life on `mat` (`aspect` / `focus_y` as given to CardDB.art_framed). Returns
## false, leaving `mat` as it was, when the card has no living art or it is switched off.
static func setup_card(mat: ShaderMaterial, card_id: String, aspect: float, focus_y: float) -> bool:
	var lv := level()
	if lv == OFF or not has(card_id):
		return false
	var entry := CardDB.living(card_id)
	var r := CardDB.art_crop_uv(card_id, aspect, focus_y)
	var art := CardDB.art(card_id)
	var u := params(entry)
	for k in u:
		mat.set_shader_parameter(k, u[k])
	mat.set_shader_parameter("living_mask", CardDB.living_mask(card_id))
	mat.set_shader_parameter("living_rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
	mat.set_shader_parameter("living_aspect", float(art.get_width()) / art.get_height())
	mat.set_shader_parameter("living_level", lv)
	var flowmap := CardDB.living_flowmap(card_id)
	var fx := CardDB.living_fx(card_id) if not entry.get("layers", []).is_empty() else null
	# Francesca (no flow map, no layers) keeps the original path exactly.
	mat.set_shader_parameter("living_ext", flowmap != null or fx != null)
	mat.set_shader_parameter("living_has_flowmap", flowmap != null)
	mat.set_shader_parameter("living_flowmap", flowmap)
	mat.set_shader_parameter("living_has_fx", fx != null)
	mat.set_shader_parameter("living_fx", fx)
	if fx != null:
		var sl := slots(entry)
		for k in sl:
			mat.set_shader_parameter(k, sl[k])
	return true
