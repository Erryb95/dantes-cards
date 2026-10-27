class_name ArtLiving
## Living art: a legendary's still painting brought to life in the card shader (card_fx + living_art.gdshaderinc). The
## whirl, flames, smoke, hair and cloth of the picture move; faces, figures and shapes that must keep their outline stay
## put (the card's mask). Data-driven: a card comes alive when data/living_art.json lists it and its mask
## (assets/cards/living/<id>.png, from tools/cards/living_mask.py) is installed; every other card is untouched.
## Hooked next to ArtDepth wherever card art is drawn (CardView: hand, collection, zoom, play reveal; MinionView: the
## board portrait). Pure setup: the motion runs on the GPU from TIME, so there is nothing to update per frame.
##
## Quality: `level()` is FULL, LITE when the frame limit is 30 (no heat haze, no embers, cheaper noise), and
## DV_LIVING=0/1/2 forces it (0 = off, the still painting, to compare).

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
}

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


## True when card `id` has living art installed (an entry and its mask).
static func has(id: String) -> bool:
	return not CardDB.living(id).is_empty() and CardDB.has_art(id) and CardDB.living_mask(id) != null


## The shader uniforms for a living-art entry (every key of PARAMS, typed, defaults filled in).
static func params(entry: Dictionary) -> Dictionary:
	var out := {}
	for key in PARAMS:
		var uniform_name: String = PARAMS[key][0]
		var fallback = PARAMS[key][1]
		var v = entry.get(key, null)
		if fallback is Vector2:
			out[uniform_name] = Vector2(float(v[0]), float(v[1])) if v is Array and v.size() >= 2 else fallback
		elif fallback is Color:
			out[uniform_name] = Color(float(v[0]), float(v[1]), float(v[2])) if v is Array and v.size() >= 3 else fallback
		else:
			out[uniform_name] = float(v) if v is float or v is int else fallback
	return out


## Brings the framed art of `card_id` to life on `mat` (`aspect` / `focus_y` as given to CardDB.art_framed). Returns
## false, leaving `mat` as it was, when the card has no living art or it is switched off.
static func setup_card(mat: ShaderMaterial, card_id: String, aspect: float, focus_y: float) -> bool:
	var lv := level()
	if lv == OFF or not has(card_id):
		return false
	var r := CardDB.art_crop_uv(card_id, aspect, focus_y)
	var art := CardDB.art(card_id)
	var u := params(CardDB.living(card_id))
	for k in u:
		mat.set_shader_parameter(k, u[k])
	mat.set_shader_parameter("living_mask", CardDB.living_mask(card_id))
	mat.set_shader_parameter("living_rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
	mat.set_shader_parameter("living_aspect", float(art.get_width()) / art.get_height())
	mat.set_shader_parameter("living_level", lv)
	return true
