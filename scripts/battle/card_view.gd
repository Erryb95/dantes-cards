class_name CardView
extends Node2D
## A full card (hand, play reveal, inspect, collection). Origin at the card centre; drawn at W x H when scale is 1.

const W := 250.0
const H := 360.0
const CARD_FX := preload("res://assets/shaders/card_fx.gdshader")

var uid := -1
var card_id := ""
var card: Dictionary = {}
var face_up := true
var playable := false:
	set(v):
		playable = v
		_update_glow()
var selected := false:
	set(v):
		selected = v
		_update_glow()
## The card's Ruse would go off if it were played now: its playable glow turns gold.
var ruse := false:
	set(v):
		ruse = v
		_update_glow()

## Animation helpers driven by the board.
var home := Vector2.ZERO
var home_rot := 0.0
var home_scale := 0.6
var dragging := false
var _last_pos := Vector2.ZERO
var _vel := Vector2.ZERO
## Fake-3D tilt: follows the pointer while it is over the card (`auto_tilt`, or `look` forced by the hand),
## leans into the motion while dragged, or sways gently (`sway`, for the inspect view).
var auto_tilt := true
var look := false
var sway := false
var hold_tilt := false ## keep `_tilt` as set from outside (previews / tests)
var _tilt := Vector2.ZERO
var _sway_t := randf() * 10.0
var _shadow: Control

var _mat: ShaderMaterial
var _mats: Array[ShaderMaterial] = [] ## every card_fx material on the card (the tilt / burn uniforms go to all)
var _art_mat: ShaderMaterial
var _depth := false ## the art has a depth map: the parallax follows the tilt (ArtDepth)
var _drift := Vector2.ZERO
var _face: Control
var _back: Control
var _glow: Aura
var _cost_label: Label
var _atk_label: Label
var _hp_label: Label
var _foil := -1.0
var _name_label: Label ## the name in engraved gold (always built)
var _name_painted: TextureRect ## the painted name, when the card has one (CardDB.name_tex)
var _name_painted_cap := 0.0 ## capital height (px at scale 1) of each name: which one reads better at the card's scale
var _name_label_cap := 0.0
var _name_scale := -1.0 ## the screen scale the name was last judged at
var _name_shows_painted := false
var _ruse_pulse := false ## the Ruse glow is breathing (its strength is driven here, not by the Aura's fade)

## Ruse ready: a deep, warm gold that breathes slowly, so it never reads as the green "playable" glow.
const RUSE_GLOW := [Color(1.0, 0.9, 0.5), Color(1.0, 0.5, 0.0)]

## Painted card names: the smallest height of their capitals, in screen px, that still reads (the gilded label takes
## over below it), the share of the painting's height those capitals take, and the brightness gain that brings the
## painted gold up to the gilded label's on the dark ribbon.
const NAME_MIN_CAP := 9.0
const NAME_CAP_K := 0.58
const NAME_GAIN := 1.5


func setup(p_card_id: String, p_uid: int = -1, p_face_up: bool = true) -> CardView:
	card_id = p_card_id
	uid = p_uid
	card = CardDB.card(card_id)
	face_up = p_face_up
	_build()
	return self


func _build() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = CARD_FX
	material = _mat

	_shadow = UI.panel(Vector2(W, H), UI.box(Color(0, 0, 0, 0.0), Color.TRANSPARENT, 0, 20,
		Color(0, 0, 0, 0.55), 18), Vector2(-W / 2 + 6, -H / 2 + 12))
	_shadow.use_parent_material = true
	add_child(_shadow)
	_glow = Aura.make(Vector2(W, H), false, 46.0, 20.0)
	add_child(_glow)

	_face = Control.new()
	_face.position = Vector2(-W / 2, -H / 2)
	_face.size = Vector2(W, H)
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.use_parent_material = true
	add_child(_face)
	_build_face()

	_back = Control.new()
	_back.position = Vector2(-W / 2, -H / 2)
	_back.size = Vector2(W, H)
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.use_parent_material = true
	add_child(_back)
	_build_back()
	set_face_up(face_up)
	var text_mat := ShaderMaterial.new()
	text_mat.shader = CARD_FX
	text_mat.set_shader_parameter("resample", false)
	_mats = [_mat, text_mat, _glow.material]
	_collect_mats(self, text_mat)
	_param("half_h", H / 2)


func _collect_mats(n: Node, text_mat: ShaderMaterial) -> void:
	for c in n.get_children():
		if (c is Label or c is RichTextLabel) and c.use_parent_material:
			c.use_parent_material = false
			c.material = text_mat
		elif c is CanvasItem and c.material is ShaderMaterial and c.material.shader == CARD_FX and not _mats.has(c.material):
			_mats.append(c.material)
		_collect_mats(c, text_mat)


func _param(n: String, v: Variant) -> void:
	for m in _mats:
		m.set_shader_parameter(n, v)


func _build_face() -> void:
	var is_spell: bool = card.get("type", "minion") == "spell"
	var rarity: String = card.get("rarity", "common")
	if UiSkin.has("card_border_spell" if is_spell else "card_border_minion"):
		_build_full_art(is_spell, rarity)
		return
	var frame_bg := Color(0.16, 0.10, 0.07) if not is_spell else Color(0.20, 0.06, 0.07)
	var frame_name := "card_frame_spell" if is_spell else "card_frame_minion"
	if UiSkin.has(frame_name):
		_face.add_child(UiSkin.rect(frame_name, Vector2(W, H)))
	else:
		var frame := UI.panel(Vector2(W, H), UI.box(frame_bg, UI.GOLD_DARK, 4, 20), Vector2.ZERO)
		frame.use_parent_material = true
		_face.add_child(frame)
		var inner := UI.panel(Vector2(W - 16, H - 16), UI.box(Color(0.07, 0.045, 0.035), UI.GOLD, 2, 15), Vector2(8, 8))
		inner.use_parent_material = true
		_face.add_child(inner)

	# Art: an oval for minions, a rounded panel for spells.
	var art := TextureRect.new()
	art.texture = CardDB.art(card_id)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_mat = ShaderMaterial.new()
	_art_mat.shader = CARD_FX
	art.material = _art_mat
	if is_spell:
		art.position = Vector2(20, 22)
		art.size = Vector2(W - 40, 182)
		art.texture = CardDB.art_framed(card_id, art.size.x / art.size.y, 0.45)
		_art_mat.set_shader_parameter("mask_mode", 2)
		_art_mat.set_shader_parameter("corner", 0.12)
	else:
		art.position = Vector2(30, 16)
		art.size = Vector2(W - 60, 200)
		art.texture = CardDB.art_framed(card_id, art.size.x / art.size.y)
		_art_mat.set_shader_parameter("mask_mode", 1)
	_depth = ArtDepth.setup_card(_art_mat, card_id, art.size.x / art.size.y, 0.45 if is_spell else 0.36, ArtDepth.CARD)
	ArtLiving.setup_card(_art_mat, card_id, art.size.x / art.size.y, 0.45 if is_spell else 0.36)
	if art.texture == null:
		art.texture = _placeholder()
	_face.add_child(art)
	if not is_spell:
		ArtLoop.attach(_face, _face, art, _art_mat, card_id, art.size.x / art.size.y, 0.36)
	if not is_spell and UiSkin.has("oval_ring"):
		_face.add_child(UiSkin.rect("oval_ring", art.size * Vector2(1.13, 1.1), art.position - art.size * Vector2(0.065, 0.05)))
	elif not is_spell:
		var ring := Shapes.make(Shapes.Kind.ELLIPSE, art.size + Vector2(6, 6), Color.TRANSPARENT, UI.GOLD, 5.0)
		ring.position = art.position + art.size / 2
		_face.add_child(ring)
	else:
		var rim := UI.panel(art.size + Vector2(6, 6), UI.box(Color(0, 0, 0, 0), UI.GOLD, 3, 16), art.position - Vector2(3, 3))
		rim.use_parent_material = true
		_face.add_child(rim)

	# Rules text box (parchment).
	if UiSkin.has("text_parchment"):
		_face.add_child(UiSkin.rect("text_parchment", Vector2(W - 24, 128), Vector2(12, 222)))
	else:
		var tb := UI.panel(Vector2(W - 36, 116), UI.box(Color(0.86, 0.78, 0.62), UI.GOLD_DARK, 2, 8,
			Color(0, 0, 0, 0.4), 4), Vector2(18, 226))
		tb.use_parent_material = true
		_face.add_child(tb)
	var txt := RichTextLabel.new()
	txt.bbcode_enabled = true
	txt.fit_content = false
	txt.scroll_active = false
	txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	txt.position = Vector2(26, 246)
	txt.size = Vector2(W - 52, 92)
	txt.use_parent_material = true
	var body := UI.font("body")
	var bold := FontVariation.new()
	bold.base_font = body
	bold.variation_embolden = 0.3
	txt.add_theme_font_override("normal_font", body)
	txt.add_theme_font_override("bold_font", bold)
	txt.add_theme_font_override("italics_font", UI.font("italic"))
	txt.add_theme_color_override("default_color", Color(0.12, 0.07, 0.04))
	var rules: String = card.get("text", "")
	var size := UI.fit_rules_size(rules, txt.size.x, txt.size.y, 21)
	if rules == "":
		rules = "[i]" + card.get("flavor", "") + "[/i]"
		size = UI.fit_rules_size(card.get("flavor", ""), txt.size.x, txt.size.y, 17)
		txt.add_theme_color_override("default_color", Color(0.3, 0.2, 0.12))
	txt.add_theme_font_size_override("normal_font_size", size)
	txt.add_theme_font_size_override("bold_font_size", size)
	txt.add_theme_font_size_override("italics_font_size", size)
	txt.text = UI.rules_bbcode(rules)
	txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_face.add_child(txt)

	# Name banner across the bottom of the art.
	if UiSkin.has("name_ribbon"):
		_face.add_child(UiSkin.rect("name_ribbon", Vector2(W + 24, 56), Vector2(-12, 188)))
	else:
		var banner := UI.panel(Vector2(W - 20, 40), UI.box(UI.CRIMSON.darkened(0.15), UI.GOLD, 3, 6,
			Color(0, 0, 0, 0.5), 6), Vector2(10, 196))
		banner.use_parent_material = true
		_face.add_child(banner)
	_add_name(Vector2(10, 196), W - 40)

	# Rarity gem.
	if rarity != "token" and UiSkin.has("rarity_" + rarity):
		_face.add_child(UiSkin.rect("rarity_" + rarity, Vector2(26, 26), Vector2(W / 2 - 13, 226)))
	elif rarity != "token":
		var gem := Shapes.make(Shapes.Kind.DIAMOND, Vector2(20, 26), UI.RARITY.get(rarity, Color.WHITE), UI.GOLD_DARK, 2.0)
		gem.position = Vector2(W / 2, 236)
		_face.add_child(gem)

	# Mana gem, attack and health.
	var mana_at := Vector2(26, 26)
	if UiSkin.has("gem_mana"):
		_face.add_child(UiSkin.rect("gem_mana", Vector2(76, 76), mana_at - Vector2(38, 38)))
	else:
		var mana := Shapes.make(Shapes.Kind.GEM, Vector2(64, 64), Color(0.12, 0.35, 0.85), UI.GOLD, 4.0)
		mana.position = mana_at
		_face.add_child(mana)
	_cost_label = _stat_label(str(int(card.get("cost", 0))), mana_at + UI.gem_number_offset("gem_mana", 76, 36), 36)
	_face.add_child(_cost_label)
	if not is_spell:
		var atk_at := Vector2(26, H - 28)
		var hp_at := Vector2(W - 26, H - 30)
		if UiSkin.has("gem_attack") and UiSkin.has("gem_health"):
			_face.add_child(UiSkin.rect("gem_attack", Vector2(74, 74), atk_at - Vector2(37, 37)))
			_face.add_child(UiSkin.rect("gem_health", Vector2(74, 74), hp_at - Vector2(37, 37)))
		else:
			var atk := Shapes.make(Shapes.Kind.SWORD, Vector2(60, 70), Color(0.85, 0.62, 0.2), Color(0.35, 0.2, 0.05), 3.0)
			atk.position = atk_at
			_face.add_child(atk)
			var hp := Shapes.make(Shapes.Kind.DROP, Vector2(58, 70), Color(0.75, 0.08, 0.06), Color(0.3, 0.02, 0.02), 3.0)
			hp.position = hp_at
			_face.add_child(hp)
		_atk_label = _stat_label(str(int(card.get("attack", 0))), atk_at + UI.gem_number_offset("gem_attack", 74, 34), 34)
		_face.add_child(_atk_label)
		_hp_label = _stat_label(str(int(card.get("health", 0))), hp_at + UI.gem_number_offset("gem_health", 74, 34), 34)
		_face.add_child(_hp_label)


## Full-art layout (Enrico 2026-10-25): the painting fills the card inside a thin painted border; name ribbon,
## rules text in light ink on a dark fade at the bottom, painted gems in the corners.
func _build_full_art(is_spell: bool, rarity: String) -> void:
	var art := TextureRect.new()
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.position = Vector2(5, 5)
	art.size = Vector2(W - 10, H - 10)
	art.texture = CardDB.art_framed(card_id, art.size.x / art.size.y, 0.42)
	if art.texture == null:
		art.texture = _placeholder()
	_art_mat = ShaderMaterial.new()
	_art_mat.shader = CARD_FX
	_art_mat.set_shader_parameter("mask_mode", 2)
	_art_mat.set_shader_parameter("corner", 0.07)
	_depth = ArtDepth.setup_card(_art_mat, card_id, art.size.x / art.size.y, 0.42, ArtDepth.CARD)
	ArtLiving.setup_card(_art_mat, card_id, art.size.x / art.size.y, 0.42)
	art.material = _art_mat
	_face.add_child(art)
	ArtLoop.attach(_face, _face, art, _art_mat, card_id, art.size.x / art.size.y, 0.42)

	# Dark fade under the text so light ink stays readable on any painting.
	var fade := TextureRect.new()
	var g := GradientTexture2D.new()
	g.width = 4
	g.height = 128
	g.fill_from = Vector2(0, 0)
	g.fill_to = Vector2(0, 1)
	var gr := Gradient.new()
	var tint := Color(0.16, 0.02, 0.03) if is_spell else Color(0.03, 0.015, 0.01)
	gr.set_color(0, Color(tint, 0.0))
	gr.set_color(1, Color(tint, 0.94))
	gr.add_point(0.3, Color(tint, 0.8))
	g.gradient = gr
	fade.texture = g
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.position = Vector2(5, 168)
	fade.size = Vector2(W - 10, H - 173)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.use_parent_material = true
	_face.add_child(fade)
	_face.add_child(UiSkin.rect("card_border_spell" if is_spell else "card_border_minion", Vector2(W, H)))

	# Name ribbon.
	var ry := 196.0
	if UiSkin.has("name_ribbon"):
		_face.add_child(UiSkin.rect("name_ribbon", Vector2(W + 20, 54), Vector2(-10, ry - 6)))
	_add_name(Vector2(10, ry), W - 64)

	# Rules text plate (Enrico: "anche sulle carte le scritte sono da disegnare"): a bronze cartouche on minions,
	# whose concave lower corners leave room for the attack and health gems, an unrolled scroll on spells.
	var plate := "card_text_plate_spell" if is_spell else "card_text_plate_minion"
	var painted := UiSkin.has(plate)
	if painted:
		if is_spell:
			_face.add_child(UiSkin.rect(plate, Vector2(W - 2, 116), Vector2(1, ry + 44)))
		else:
			_face.add_child(UiSkin.rect(plate, Vector2(W - 18, 104), Vector2(9, ry + 44)))
	if rarity != "token" and UiSkin.has("rarity_" + rarity):
		_face.add_child(UiSkin.rect("rarity_" + rarity, Vector2(24, 24), Vector2(W / 2 - 12, ry + 36)))

	# Rules text: dark ink on the plate, or light ink on the fade when the plate art is missing.
	var txt := RichTextLabel.new()
	txt.bbcode_enabled = true
	txt.scroll_active = false
	txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Inside the plate; on minions the box narrows so lines stay clear of the attack and health gems in the
	# lower corners, on spells it stays between the scroll's rolled ends.
	if painted:
		txt.position = Vector2(38, ry + 68) if is_spell else Vector2(50, ry + 61)
		txt.size = Vector2(W - 76, 72) if is_spell else Vector2(W - 100, 60)
	else:
		txt.position = Vector2(20 if is_spell else 44, ry + 58)
		txt.size = Vector2(W - 40 if is_spell else W - 88, 72 if is_spell else 66)
	txt.use_parent_material = true
	var body := UI.font("body")
	var bold := FontVariation.new()
	bold.base_font = body
	bold.variation_embolden = 0.4
	txt.add_theme_font_override("normal_font", body)
	txt.add_theme_font_override("bold_font", bold)
	txt.add_theme_font_override("italics_font", UI.font("italic"))
	if painted:
		txt.add_theme_color_override("default_color", Color(0.12, 0.07, 0.04))
	else:
		txt.add_theme_color_override("default_color", Color(0.96, 0.92, 0.84))
		txt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		txt.add_theme_constant_override("outline_size", 5)
	var rules: String = card.get("text", "")
	var size := UI.fit_rules_size(rules, txt.size.x, txt.size.y, 20)
	if rules == "":
		rules = "[i]" + card.get("flavor", "") + "[/i]"
		size = UI.fit_rules_size(card.get("flavor", ""), txt.size.x, txt.size.y, 17)
		txt.add_theme_color_override("default_color", Color(0.3, 0.2, 0.12) if painted else Color(0.85, 0.78, 0.66))
	for k in ["normal_font_size", "bold_font_size", "italics_font_size"]:
		txt.add_theme_font_size_override(k, size)
	txt.text = UI.rules_bbcode(rules)
	txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_face.add_child(txt)

	# Gems.
	var mana_at := Vector2(28, 28)
	_face.add_child(UiSkin.rect("gem_mana", Vector2(74, 74), mana_at - Vector2(37, 37)))
	_cost_label = _stat_label(str(int(card.get("cost", 0))), mana_at + UI.gem_number_offset("gem_mana", 76, 36), 36)
	_face.add_child(_cost_label)
	if not is_spell:
		var atk_at := Vector2(28, H - 28)
		var hp_at := Vector2(W - 28, H - 30)
		_face.add_child(UiSkin.rect("gem_attack", Vector2(72, 72), atk_at - Vector2(36, 36)))
		_face.add_child(UiSkin.rect("gem_health", Vector2(72, 72), hp_at - Vector2(36, 36)))
		_atk_label = _stat_label(str(int(card.get("attack", 0))), atk_at + UI.gem_number_offset("gem_attack", 74, 34), 34)
		_face.add_child(_atk_label)
		_hp_label = _stat_label(str(int(card.get("health", 0))), hp_at + UI.gem_number_offset("gem_health", 74, 34), 34)
		_face.add_child(_hp_label)


func _stat_label(text: String, center: Vector2, size: int) -> Label:
	var l := UI.raised(UI.label(text, size, "title", UI.NUMBER, 8, Color(0.05, 0.02, 0.02)))
	l.size = Vector2(80, 60)
	l.position = center - l.size / 2
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.use_parent_material = true
	return l


## The card's name on the ribbon in engraved gold, in the 40 px band at `at` (W - 20 wide), at most `room` px wide.
## Names over 22 letters drop their epithet ("Minos, Judge of the Damned" → "Minos").
## A card with a painted name (CardDB.name_tex) shows that instead, whole, fitted in the same band, as long as its
## capitals are big enough to read on screen (`_update_name`); below NAME_MIN_CAP px (a long name at hand size) the gilded
## label, which shortens long names, takes over. Both are always built, so the card copes with any subset of painted names.
func _add_name(at: Vector2, room: float) -> void:
	var nm: String = card.get("name", card_id)
	var short := nm.split(",")[0] if nm.length() > 22 else nm
	var box := Vector2(W - 20, 40)
	var name_l := UI.label(short, _fit_size(short, room, 22, "title"), "title", UI.GOLD, 4, Color(0.1, 0.02, 0.02))
	name_l.position = at
	name_l.size = box
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Engraved gold through the card's own shader, so the name tilts and burns away with the card.
	var f := name_l.get_theme_font("font")
	var fs := name_l.get_theme_font_size("font_size")
	var base := (box.y - f.get_height(fs)) / 2.0 + f.get_ascent(fs)
	var m := ShaderMaterial.new()
	m.shader = CARD_FX
	m.set_shader_parameter("resample", false)
	m.set_shader_parameter("gild", true)
	m.set_shader_parameter("gild_base", base)
	m.set_shader_parameter("gild_top", base - fs * 0.7)
	name_l.material = m
	_face.add_child(name_l)
	_name_label = name_l
	_name_label_cap = fs * 0.7 # Cinzel's capitals stand about 0.7 em
	var painted := CardDB.name_tex(card_id)
	if painted != null:
		_add_painted_name(painted, at, room)
		_apply_name_mode(true)

## The painted name `tex` fitted inside the ribbon's band (keeping its shape, a small margin all round) and centred on
## it. Its own CARD_FX material (gild off: the gold is painted), so _collect_mats tilts, burns and dissolves it with
## the card exactly like the set name.
func _add_painted_name(tex: Texture2D, at: Vector2, room: float) -> void:
	const MARGIN := Vector2(4, 4)
	var box := Vector2(W - 20, 40)
	var fit := Vector2(room, box.y) - MARGIN * 2.0
	var k := minf(fit.x / tex.get_width(), fit.y / tex.get_height())
	var r := TextureRect.new()
	r.name = "PaintedName"
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.size = Vector2(tex.get_width(), tex.get_height()) * k
	r.position = at + (box - r.size) / 2.0
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS # a 160 px painting shrunk to ~30 px
	var m := ShaderMaterial.new()
	m.shader = CARD_FX
	m.set_shader_parameter("gild", false)
	m.set_shader_parameter("name_gain", NAME_GAIN) # the painted gold is dimmer than the gilded label: lift it
	r.material = m
	_face.add_child(r)
	_name_painted = r
	_name_painted_cap = r.size.y * NAME_CAP_K


## The painted name or the gilded label, whichever reads better at the card's size on screen: the painted one when
## its capitals are at least NAME_MIN_CAP px tall (a little more to switch to it than to stay on it, so a hovering
## card does not flicker), or when it is no smaller than the label's; else the label. The switch is a quick fade.
func _update_name() -> void:
	if _name_painted == null:
		return
	var s := get_global_transform().y.length()
	var vp := get_viewport()
	if vp != null:
		s *= vp.get_final_transform().y.length()
	if s < 0.01 or absf(s - _name_scale) < 0.02 * maxf(_name_scale, 0.01):
		return
	var first := _name_scale < 0.0
	_name_scale = s
	var need := NAME_MIN_CAP * (0.92 if _name_shows_painted else 1.08)
	var painted := _name_painted_cap * s >= need or _name_painted_cap >= _name_label_cap
	if painted != _name_shows_painted or first:
		_apply_name_mode(painted, not first)


func _apply_name_mode(painted: bool, fade := false) -> void:
	_name_shows_painted = painted
	var shown: Array = [_name_painted, _name_label]
	for i in 2:
		var n: CanvasItem = shown[i]
		var a := 1.0 if (i == 0) == painted else 0.0
		if fade and is_inside_tree():
			create_tween().tween_property(n, "modulate:a", a, 0.12)
		else:
			n.modulate.a = a


static func _fit_size(text: String, width: float, max_size: int, kind: String) -> int:
	var f := UI.font(kind)
	var s := max_size
	while s > 12 and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > width:
		s -= 1
	return s


func _build_back() -> void:
	var tex: Texture2D = null
	if ResourceLoader.exists("res://assets/cards/card_back.jpg"):
		tex = load("res://assets/cards/card_back.jpg")
	# The painted back inside the same carved border as the card faces (the deck pile, the enemy hand, a card being
	# flipped). The flat red frame and gold line are only the fallback when either painting is missing.
	var painted := tex != null and UiSkin.has("card_border_minion")
	if not painted:
		var frame := UI.panel(Vector2(W, H), UI.box(Color(0.25, 0.04, 0.04), UI.GOLD_DARK, 5, 20), Vector2.ZERO)
		frame.use_parent_material = true
		_back.add_child(frame)
	if tex != null:
		var img := TextureRect.new()
		img.texture = tex
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		var inset := 5.0 if painted else 10.0
		img.position = Vector2(inset, inset)
		img.size = Vector2(W, H) - Vector2(inset, inset) * 2.0
		var m := ShaderMaterial.new()
		m.shader = CARD_FX
		m.set_shader_parameter("mask_mode", 2)
		m.set_shader_parameter("corner", 0.07 if painted else 0.1)
		img.material = m
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_back.add_child(img)
	else:
		for i in 9:
			var r := Shapes.make(Shapes.Kind.ELLIPSE, Vector2(200 - i * 20, 200 - i * 20), Color.TRANSPARENT,
				UI.GOLD.darkened(i * 0.07), 3.0)
			r.position = Vector2(W / 2, H / 2)
			_back.add_child(r)
	if painted:
		_back.add_child(UiSkin.rect("card_border_minion", Vector2(W, H)))
		return
	var rim := UI.panel(Vector2(W - 20, H - 20), UI.box(Color(0, 0, 0, 0), UI.GOLD, 3, 14), Vector2(10, 10))
	rim.use_parent_material = true
	_back.add_child(rim)


func _placeholder() -> Texture2D:
	var g := GradientTexture2D.new()
	g.width = 128
	g.height = 192
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.35)
	g.fill_to = Vector2(1.1, 1.0)
	var gr := Gradient.new()
	gr.set_color(0, Color(0.55, 0.18, 0.06))
	gr.set_color(1, Color(0.04, 0.02, 0.02))
	g.gradient = gr
	return g


func set_face_up(v: bool) -> void:
	face_up = v
	_face.visible = v
	_back.visible = not v
	_update_glow()


func set_cost(cost: int) -> void:
	_cost_label.text = str(cost)


## A minion's live numbers (the inspect view of a minion in play): raised values green, damaged health red, as on
## the board.
func set_stats(attack: int, health: int, max_health: int) -> void:
	if _atk_label == null:
		return
	_atk_label.text = str(attack)
	_hp_label.text = str(health)
	_atk_label.add_theme_color_override("font_color", UI.HEAL if attack > int(card.get("attack", 0)) else UI.NUMBER)
	var hp_col := UI.NUMBER
	if health < max_health:
		hp_col = Color(1.0, 0.35, 0.3)
	elif health > int(card.get("health", 0)):
		hp_col = UI.HEAL
	_hp_label.add_theme_color_override("font_color", hp_col)


func _update_glow() -> void:
	if _glow == null:
		return
	var preset: Array = Aura.SELECTED if selected else (RUSE_GLOW if ruse else Aura.PLAYABLE)
	_glow.set_on(face_up and (playable or selected), preset)
	# The gold fire also licks faster than the green.
	_glow.material.set_shader_parameter("speed", 1.5 if ruse and not selected else 1.0)


## The Ruse glow breathes (strength 0.95 to 1.5, about a 2.6 s cycle) once the Aura has faded it in; it settles
## back to the steady 1.0 when the Ruse is no longer live.
func _tick_ruse_glow(delta: float) -> void:
	var pulse := ruse and playable and not selected and face_up and _glow.on
	var fading := _glow._tween != null and _glow._tween.is_running()
	if not _glow.on:
		_ruse_pulse = false # the Aura fades it out on its own
		return
	if fading or (not pulse and not _ruse_pulse):
		return
	var cur: float = _glow.material.get_shader_parameter("strength")
	var want := 1.0
	if pulse:
		want = 1.22 + 0.28 * sin(Time.get_ticks_msec() / 1000.0 * 2.4)
	cur = lerpf(cur, want, minf(1.0, delta * 6.0))
	_glow.material.set_shader_parameter("strength", cur)
	_ruse_pulse = pulse or absf(cur - 1.0) > 0.01
	if not _ruse_pulse:
		_glow.material.set_shader_parameter("strength", 1.0)


func _process(delta: float) -> void:
	_tick_ruse_glow(delta)
	_update_name()
	# Velocity tilt while dragged: lean into the motion like a real card.
	_vel = _vel.lerp((position - _last_pos) / maxf(delta, 0.001), 0.25)
	_last_pos = position
	var target := Vector2.ZERO
	var lift := 0.0
	var hovered := false
	if dragging:
		rotation = lerp_angle(rotation, clampf(_vel.x * 0.0002, -0.25, 0.25), 0.3)
		target = (_vel * 0.0006).limit_length(0.5)
		lift = 1.0
	elif face_up and (look or (auto_tilt and is_visible_in_tree() and contains_point(get_global_mouse_position()))):
		var m := to_local(get_global_mouse_position()) / Vector2(W / 2, H / 2)
		# A hand card lifted under the pointer leans gently: the pointer sits at its bottom edge, and a full lean
		# would push that edge off the screen.
		target = m.clamp(-Vector2.ONE, Vector2.ONE) * (0.13 if look else 0.32)
		lift = 0.5
		hovered = true
	elif sway:
		_sway_t += delta
		target = Vector2(sin(_sway_t * 0.9) * 0.14, cos(_sway_t * 0.7) * 0.09)
	if not hold_tilt:
		_tilt = _tilt.lerp(target, minf(1.0, delta * 12.0))
	if not hold_tilt and _tilt.length() < 0.002 and target == Vector2.ZERO:
		_tilt = Vector2.ZERO
	_param("tilt", _tilt)
	if _depth:
		_update_parallax(delta, hovered)
	if _tilt != Vector2.ZERO:
		var xf := get_global_transform()
		_param("card_center", xf.origin)
		_param("card_x", xf.x)
		_param("card_y", xf.y)
	# The shadow drifts away from the light as the card lifts.
	var off := Vector2(6, 12).lerp(Vector2(26, 46), lift)
	_shadow.position = _shadow.position.lerp(Vector2(-W / 2, -H / 2) + off, minf(1.0, delta * 10.0))
	if card.get("rarity", "") == "legendary" and face_up:
		_foil += delta * 0.35
		if _foil > 1.6:
			_foil = -0.6
		_art_mat.set_shader_parameter("shine", clampf(_foil, -1.0, 1.2) if _foil >= 0.0 else -1.0)


## The art's depth parallax follows the tilt, so the painting reads as a window with depth. Under a resting pointer, on
## the inspect view and on a big zoomed card it also drifts gently, so the depth shows without moving anything.
func _update_parallax(delta: float, hovered: bool) -> void:
	var drift := Vector2.ZERO
	if face_up and not dragging and (hovered or sway or get_global_transform().get_scale().x >= 1.4):
		_sway_t += delta if not sway else 0.0 # `sway` already advances it
		drift = Vector2(sin(_sway_t * 1.3), cos(_sway_t * 1.05)) * 0.07
	_drift = _drift.lerp(drift, minf(1.0, delta * 4.0))
	ArtDepth.look(_art_mat, _tilt + _drift)


## Burns the card away (spells after casting, cards burned from a full hand).
func burn_away(duration: float = 0.7) -> void:
	var t := create_tween().set_parallel(true)
	t.tween_method(_set_burn, 0.0, 1.0, duration)
	await t.finished
	queue_free()


func _set_burn(v: float) -> void:
	_param("burn", v)


## The dissolve's progress by hand: 0 whole, 1 gone (the title screen's showcase burns cards away and raises new ones).
func set_burn(v: float) -> void:
	_param("burn", v)


## The colours of the dissolve's glowing rim (a spell burns away in its school's colours).
func set_burn_colors(edge: Color, hot: Color) -> void:
	_param("burn_edge", edge)
	_param("burn_hot", hot)


func contains_point(global_point: Vector2) -> bool:
	var p := to_local(global_point)
	return absf(p.x) <= W / 2 and absf(p.y) <= H / 2
