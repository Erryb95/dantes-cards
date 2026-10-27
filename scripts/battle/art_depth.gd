class_name ArtDepth
## Depth parallax for card art: hooks a card_fx art material to its depth map (CardDB.art_depth, made by
## tools/cards/make_depth.py) and holds the tuning. The view then only feeds `parallax` (a view angle in radians, the
## same convention as the card's `tilt`) through `look`. Art without a depth map keeps a flat picture.

## UV shift per radian of view for a full depth step (0..1). Larger = deeper window.
const CARD := 0.16 ## hand / inspect / collection cards (the tilt itself reaches ~0.3 rad)
const MINION := 0.14 ## board portraits (no tilt; fed only on hover / attack)
const HERO := 0.12
## The depth that stays fixed against the frame: below it (background) slides with the view, above it (the figure)
## slides against it. 0.6 keeps faces almost still and lets the sky and the far landscape move.
const FOCUS := 0.6
## The largest view angle each kind of art is fed; the over-scale margin is sized from it so no edge ever shows.
const MAX_VIEW := 0.42


## Sets up `mat` for a card's framed art (`aspect` / `focus_y` as given to CardDB.art_framed). Returns false (and leaves
## the parallax off) when the card has no depth map.
static func setup_card(mat: ShaderMaterial, card_id: String, aspect: float, focus_y: float, amount: float) -> bool:
	var tex := CardDB.art_depth(card_id)
	if tex == null or not CardDB.has_art(card_id):
		return false
	var r := CardDB.art_crop_uv(card_id, aspect, focus_y)
	_apply(mat, tex, Vector4(r.position.x, r.position.y, r.size.x, r.size.y), aspect, amount)
	return true


## The same for a hero portrait drawn whole (TextureRect region UVs are in the picture's own 0..1 space).
static func setup_hero(mat: ShaderMaterial, hero_id: String, amount: float) -> bool:
	var tex := CardDB.hero_depth(hero_id)
	var art := CardDB.hero_art(hero_id)
	if tex == null or art == null:
		return false
	_apply(mat, tex, Vector4(0, 0, 1, 1), float(art.get_width()) / art.get_height(), amount)
	return true


static func _apply(mat: ShaderMaterial, tex: Texture2D, rect: Vector4, aspect: float, amount: float) -> void:
	mat.set_shader_parameter("depth_tex", tex)
	mat.set_shader_parameter("depth_rect", rect)
	mat.set_shader_parameter("art_aspect", aspect)
	mat.set_shader_parameter("depth_focus", FOCUS)
	mat.set_shader_parameter("depth_amount", amount)
	# The widest shift: the far background (depth 0) at the strongest view, on the wider of the two axes.
	mat.set_shader_parameter("depth_margin", FOCUS * MAX_VIEW * amount * maxf(1.0, aspect) + 0.004)


## Feeds a view angle (radians, +x seen from the left, +y from above), skipping redundant uniform writes.
static func look(mat: ShaderMaterial, view: Vector2) -> void:
	view = view.limit_length(MAX_VIEW)
	if view.length() < 0.001:
		view = Vector2.ZERO
	if mat.get_meta("par", Vector2(-9, -9)) != view:
		mat.set_meta("par", view)
		mat.set_shader_parameter("parallax", view)
