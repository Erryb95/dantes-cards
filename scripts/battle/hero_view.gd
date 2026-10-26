class_name HeroView
extends Node2D
## Hero portrait with health / armor gems, plus the hero-power button next to it.

const W := 176.0
const H := 210.0
const CARD_FX := preload("res://assets/shaders/card_fx.gdshader")

var uid := -1
var side := 0
var hero_id := ""
var health := 30
var armor := 0
var home := Vector2.ZERO
var busy := false
var power: Node2D
var power_ready := false:
	set(v):
		power_ready = v
		_refresh_power()
var power_used := false:
	set(v):
		power_used = v
		_refresh_power()

var _mat: ShaderMaterial
var _art_mat: ShaderMaterial
var _hp_l: Label
var _armor: Node2D
var _armor_l: Label
var _power_glow: Aura
var _power_face: Node2D
var _target_glow: Aura
var _t := 0.0


func setup(snap: Dictionary) -> HeroView:
	uid = snap.uid
	side = snap.side
	hero_id = snap.id
	health = snap.health
	_build()
	return self


func _build() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = CARD_FX
	material = _mat
	var def := CardDB.hero(hero_id)

	var shadow := Shapes.make(Shapes.Kind.ELLIPSE, Vector2(W + 24, H + 24), Color(0, 0, 0, 0.5))
	shadow.shade = false
	shadow.position = Vector2(6, 10)
	add_child(shadow)
	_target_glow = Aura.make(Vector2(W + 22, H + 22), true, 44.0)
	_target_glow.colors(Aura.TARGET)
	add_child(_target_glow)
	var plate := Shapes.make(Shapes.Kind.ELLIPSE, Vector2(W + 22, H + 22), Color(0.2, 0.12, 0.06), UI.GOLD_DARK, 4.0)
	add_child(plate)
	var art := TextureRect.new()
	art.texture = CardDB.hero_art(hero_id)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.position = Vector2(-W / 2, -H / 2)
	art.size = Vector2(W, H)
	_art_mat = ShaderMaterial.new()
	_art_mat.shader = CARD_FX
	_art_mat.set_shader_parameter("mask_mode", 1)
	art.material = _art_mat
	add_child(art)
	var ring: Node2D
	if UiSkin.has("hero_frame_oval"):
		ring = UiSkin.sprite("hero_frame_oval", Vector2(W, H) * Vector2(1.34, 1.3))
	else:
		ring = UI.portrait_frame(Vector2(W, H))
	if ring == null:
		ring = Shapes.make(Shapes.Kind.ELLIPSE, Vector2(W + 4, H + 4), Color.TRANSPARENT, UI.GOLD, 6.0)
	else:
		plate.visible = false
	add_child(ring)

	var hp: Node2D = UiSkin.sprite("gem_health", Vector2(84, 84)) if UiSkin.has("gem_health") else 		Shapes.make(Shapes.Kind.DROP, Vector2(62, 76), Color(0.75, 0.08, 0.06), Color(0.3, 0.02, 0.02), 3.0)
	hp.position = Vector2(W / 2 - 4, H / 2 - 30)
	add_child(hp)
	_hp_l = UI.raised(UI.label(str(health), 32, "title", UI.NUMBER, 8, Color(0.05, 0.02, 0.02)))
	_hp_l.size = Vector2(80, 56)
	_hp_l.position = hp.position + UI.gem_number_offset("gem_health", 84, 32) - _hp_l.size / 2
	_hp_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_l.use_parent_material = true
	add_child(_hp_l)

	_armor = Node2D.new()
	_armor.position = Vector2(W / 2 - 4, H / 2 - 100)
	_armor.use_parent_material = true
	add_child(_armor)
	if UiSkin.has("gem_armor"):
		_armor.add_child(UiSkin.sprite("gem_armor", Vector2(70, 70)))
	else:
		var sh := Shapes.make(Shapes.Kind.SHIELD, Vector2(56, 62), Color(0.55, 0.55, 0.6), Color(0.2, 0.2, 0.25), 3.0)
		_armor.add_child(sh)
	_armor_l = UI.raised(UI.label("0", 32, "title", UI.NUMBER, 7, Color.BLACK))
	_armor_l.size = Vector2(70, 50)
	_armor_l.position = UI.gem_number_offset("gem_armor", 70, 32) - _armor_l.size / 2
	_armor_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_armor_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_armor_l.use_parent_material = true
	_armor.add_child(_armor_l)
	_armor.visible = false

	_build_power(def)


func _build_power(def: Dictionary) -> void:
	power = Node2D.new()
	power.position = Vector2(W / 2 + 92, 14 if side == 0 else -14) # mirrored about the divider, like the board sockets
	add_child(power)
	_power_glow = Aura.make(Vector2(104, 104), true, 30.0)
	power.add_child(_power_glow)
	_power_face = Node2D.new()
	power.add_child(_power_face)
	var icon_name := "icon_shield" if hero_id == "dante" else "icon_obol"
	if UiSkin.has("power_disc") and UiSkin.has(icon_name):
		_power_face.add_child(UiSkin.sprite("power_disc", Vector2(106, 106)))
		_power_face.add_child(UiSkin.sprite(icon_name, Vector2(60, 60)))
	else:
		var disc := Shapes.make(Shapes.Kind.ELLIPSE, Vector2(98, 98), Color(0.3, 0.07, 0.05), UI.GOLD, 5.0)
		_power_face.add_child(disc)
		var icon_kind := Shapes.Kind.SHIELD if hero_id == "dante" else Shapes.Kind.DIAMOND
		var icon := Shapes.make(icon_kind, Vector2(44, 50), UI.GOLD.darkened(0.1), Color(0.25, 0.12, 0.03), 3.0)
		_power_face.add_child(icon)
	var cost: Node2D
	if UiSkin.has("gem_mana"):
		cost = UiSkin.sprite("gem_mana", Vector2(46, 46))
	else:
		cost = Shapes.make(Shapes.Kind.GEM, Vector2(38, 38), Color(0.12, 0.35, 0.85), UI.GOLD, 3.0)
	cost.position = Vector2(0, -50)
	_power_face.add_child(cost)
	var cl := UI.raised(UI.label(str(int(def.get("power", {}).get("cost", 2))), 24, "title", UI.NUMBER, 6, Color.BLACK))
	cl.size = Vector2(40, 34)
	cl.position = cost.position + UI.gem_number_offset("gem_mana", 46, 24) - cl.size / 2
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_power_face.add_child(cl)
	_refresh_power()


func _refresh_power() -> void:
	if _power_glow == null:
		return
	_power_glow.set_on(power_ready and not power_used)
	_power_face.modulate = Color(0.45, 0.42, 0.4) if power_used else Color.WHITE


func power_contains(global_point: Vector2) -> bool:
	return power.to_local(global_point).length() <= 52.0


## Flips the power disc when it is used (or refreshed at turn start).
func flip_power(used: bool) -> void:
	var t := create_tween()
	t.tween_property(_power_face, "scale:x", 0.0, 0.12)
	t.tween_callback(func(): power_used = used)
	t.tween_property(_power_face, "scale:x", 1.0, 0.12)


func set_health(hp: int, p_armor: int = -1) -> void:
	var old := health
	health = hp
	_hp_l.add_theme_color_override("font_color", UI.NUMBER if hp >= 30 else Color(1.0, 0.45, 0.4))
	# The number rolls to its new value and the gem thumps, instead of jumping.
	if old != hp and is_inside_tree():
		var t := _hp_l.create_tween()
		t.tween_method(func(v: float): _hp_l.text = str(roundi(v)), float(old), float(hp),
			clampf(absf(hp - old) * 0.06, 0.15, 0.6))
		_hp_l.pivot_offset = _hp_l.size / 2
		var p := _hp_l.create_tween()
		p.tween_property(_hp_l, "scale", Vector2(1.45, 1.45), 0.08)
		p.tween_property(_hp_l, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)
	else:
		_hp_l.text = str(hp)
	if p_armor >= 0:
		set_armor(p_armor)


func set_armor(a: int) -> void:
	armor = a
	_armor.visible = a > 0
	_armor_l.text = str(a)


func set_targeted(v: bool) -> void:
	_target_glow.set_on(v)


func _process(delta: float) -> void:
	_t += delta


func flash(color: Color = Color(1, 0.2, 0.1), duration: float = 0.4) -> void:
	_mat.set_shader_parameter("flash_color", color)
	_art_mat.set_shader_parameter("flash_color", color)
	create_tween().tween_method(_set_flash, 1.0, 0.0, duration)


func _set_flash(v: float) -> void:
	_mat.set_shader_parameter("flash", v)
	_art_mat.set_shader_parameter("flash", v)


func burn_away(duration: float = 1.6) -> void:
	var t := create_tween()
	t.tween_method(_set_burn, 0.0, 1.0, duration)
	await t.finished


func _set_burn(v: float) -> void:
	_mat.set_shader_parameter("burn", v)
	_art_mat.set_shader_parameter("burn", v)


func contains_point(global_point: Vector2) -> bool:
	var p := to_local(global_point)
	return pow(p.x / (W * 0.55), 2) + pow(p.y / (H * 0.55), 2) <= 1.0
