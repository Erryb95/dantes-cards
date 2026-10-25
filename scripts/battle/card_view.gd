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

## Animation helpers driven by the board.
var home := Vector2.ZERO
var home_rot := 0.0
var home_scale := 0.6
var dragging := false
var _last_pos := Vector2.ZERO
var _vel := Vector2.ZERO

var _mat: ShaderMaterial
var _art_mat: ShaderMaterial
var _face: Control
var _back: Control
var _glow: Panel
var _glow_t := 0.0
var _cost_label: Label
var _foil := -1.0


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

	var shadow := UI.panel(Vector2(W, H), UI.box(Color(0, 0, 0, 0.0), Color.TRANSPARENT, 0, 20,
		Color(0, 0, 0, 0.55), 18), Vector2(-W / 2 + 6, -H / 2 + 12))
	shadow.use_parent_material = true
	add_child(shadow)
	_glow = UI.panel(Vector2(W + 8, H + 8), UI.box(Color(0, 0, 0, 0), UI.PLAYABLE, 4, 22, UI.PLAYABLE, 26),
		Vector2(-W / 2 - 4, -H / 2 - 4))
	_glow.visible = false
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


func _build_face() -> void:
	var is_spell: bool = card.get("type", "minion") == "spell"
	var rarity: String = card.get("rarity", "common")
	var frame_bg := Color(0.16, 0.10, 0.07) if not is_spell else Color(0.20, 0.06, 0.07)
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
	if art.texture == null:
		art.texture = _placeholder()
	_face.add_child(art)
	if not is_spell:
		var ring := Shapes.make(Shapes.Kind.ELLIPSE, art.size + Vector2(6, 6), Color.TRANSPARENT, UI.GOLD, 5.0)
		ring.position = art.position + art.size / 2
		_face.add_child(ring)
	else:
		var rim := UI.panel(art.size + Vector2(6, 6), UI.box(Color(0, 0, 0, 0), UI.GOLD, 3, 16), art.position - Vector2(3, 3))
		rim.use_parent_material = true
		_face.add_child(rim)

	# Rules text box (parchment).
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
	var size := 21 if rules.length() < 40 else 19
	if rules == "":
		rules = "[i]" + card.get("flavor", "") + "[/i]"
		size = 17
		txt.add_theme_color_override("default_color", Color(0.3, 0.2, 0.12))
	txt.add_theme_font_size_override("normal_font_size", size)
	txt.add_theme_font_size_override("bold_font_size", size)
	txt.add_theme_font_size_override("italics_font_size", size)
	txt.text = UI.rules_bbcode(rules)
	txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_face.add_child(txt)

	# Name banner across the bottom of the art.
	var banner := UI.panel(Vector2(W - 20, 40), UI.box(UI.CRIMSON.darkened(0.15), UI.GOLD, 3, 6,
		Color(0, 0, 0, 0.5), 6), Vector2(10, 196))
	banner.use_parent_material = true
	_face.add_child(banner)
	var nm: String = card.get("name", card_id)
	var short := nm.split(",")[0] if nm.length() > 22 else nm
	var name_l := UI.label(short, _fit_size(short, W - 40, 22, "title"), "title", UI.BONE, 4, Color(0.1, 0.02, 0.02))
	name_l.position = Vector2(10, 196)
	name_l.size = Vector2(W - 20, 40)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_l.use_parent_material = true
	_face.add_child(name_l)

	# Rarity gem.
	if rarity != "token":
		var gem := Shapes.make(Shapes.Kind.DIAMOND, Vector2(20, 26), UI.RARITY.get(rarity, Color.WHITE), UI.GOLD_DARK, 2.0)
		gem.position = Vector2(W / 2, 236)
		_face.add_child(gem)

	# Mana gem, attack and health.
	var mana := Shapes.make(Shapes.Kind.GEM, Vector2(64, 64), Color(0.12, 0.35, 0.85), UI.GOLD, 4.0)
	mana.position = Vector2(26, 26)
	_face.add_child(mana)
	_cost_label = _stat_label(str(int(card.get("cost", 0))), mana.position, 40)
	_face.add_child(_cost_label)
	if not is_spell:
		var atk := Shapes.make(Shapes.Kind.SWORD, Vector2(60, 70), Color(0.85, 0.62, 0.2), Color(0.35, 0.2, 0.05), 3.0)
		atk.position = Vector2(26, H - 28)
		_face.add_child(atk)
		_face.add_child(_stat_label(str(int(card.get("attack", 0))), atk.position + Vector2(0, 4), 38))
		var hp := Shapes.make(Shapes.Kind.DROP, Vector2(58, 70), Color(0.75, 0.08, 0.06), Color(0.3, 0.02, 0.02), 3.0)
		hp.position = Vector2(W - 26, H - 30)
		_face.add_child(hp)
		_face.add_child(_stat_label(str(int(card.get("health", 0))), hp.position + Vector2(0, 6), 38))


func _stat_label(text: String, center: Vector2, size: int) -> Label:
	var l := UI.label(text, size, "title", Color.WHITE, 8, Color(0.05, 0.02, 0.02))
	l.size = Vector2(80, 60)
	l.position = center - l.size / 2
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.use_parent_material = true
	return l


static func _fit_size(text: String, width: float, max_size: int, kind: String) -> int:
	var f := UI.font(kind)
	var s := max_size
	while s > 12 and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > width:
		s -= 1
	return s


func _build_back() -> void:
	var frame := UI.panel(Vector2(W, H), UI.box(Color(0.25, 0.04, 0.04), UI.GOLD_DARK, 5, 20), Vector2.ZERO)
	frame.use_parent_material = true
	_back.add_child(frame)
	var tex: Texture2D = null
	if ResourceLoader.exists("res://assets/cards/card_back.jpg"):
		tex = load("res://assets/cards/card_back.jpg")
	if tex != null:
		var img := TextureRect.new()
		img.texture = tex
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img.position = Vector2(10, 10)
		img.size = Vector2(W - 20, H - 20)
		var m := ShaderMaterial.new()
		m.shader = CARD_FX
		m.set_shader_parameter("mask_mode", 2)
		m.set_shader_parameter("corner", 0.1)
		img.material = m
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_back.add_child(img)
	else:
		for i in 9:
			var r := Shapes.make(Shapes.Kind.ELLIPSE, Vector2(200 - i * 20, 200 - i * 20), Color.TRANSPARENT,
				UI.GOLD.darkened(i * 0.07), 3.0)
			r.position = Vector2(W / 2, H / 2)
			_back.add_child(r)
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


func _update_glow() -> void:
	if _glow == null:
		return
	_glow.visible = face_up and (playable or selected)
	var c := UI.GOLD if selected else UI.PLAYABLE
	var sb: StyleBoxFlat = _glow.get_theme_stylebox("panel")
	sb.border_color = c
	sb.shadow_color = c


func _process(delta: float) -> void:
	if _glow.visible:
		_glow_t += delta
		_glow.modulate.a = 0.65 + 0.35 * sin(_glow_t * 4.0)
	# Velocity tilt while dragged: lean into the motion like a real card.
	_vel = _vel.lerp((position - _last_pos) / maxf(delta, 0.001), 0.25)
	_last_pos = position
	if dragging:
		rotation = lerp_angle(rotation, clampf(_vel.x * 0.00035, -0.4, 0.4), 0.3)
		skew = lerpf(skew, clampf(-_vel.x * 0.00018, -0.22, 0.22), 0.3)
	else:
		skew = lerpf(skew, 0.0, 0.2)
	if card.get("rarity", "") == "legendary" and face_up:
		_foil += delta * 0.35
		if _foil > 1.6:
			_foil = -0.6
		_art_mat.set_shader_parameter("shine", clampf(_foil, -1.0, 1.2) if _foil >= 0.0 else -1.0)


## Burns the card away (spells after casting, cards burned from a full hand).
func burn_away(duration: float = 0.7) -> void:
	var t := create_tween().set_parallel(true)
	t.tween_method(_set_burn, 0.0, 1.0, duration)
	await t.finished
	queue_free()


func _set_burn(v: float) -> void:
	_mat.set_shader_parameter("burn", v)
	_art_mat.set_shader_parameter("burn", v)


func contains_point(global_point: Vector2) -> bool:
	var p := to_local(global_point)
	return absf(p.x) <= W / 2 and absf(p.y) <= H / 2
