class_name MinionView
extends Node2D
## A minion on the board: oval portrait, attack / health, keyword dressing (guard shield, ward bubble...).

const W := 116.0
const H := 148.0
const CARD_FX := preload("res://assets/shaders/card_fx.gdshader")

var uid := -1
var card_id := ""
var side := 0
var attack := 0
var health := 0
var max_health := 0
var base_attack := 0
var base_health := 0
var keywords: Array = []
var sleeping := true
var can_attack := false:
	set(v):
		can_attack = v
		_refresh_glow()
var home := Vector2.ZERO
var busy := false ## set while it lunges, so layout does not fight the animation

var _mat: ShaderMaterial
var _art_mat: ShaderMaterial
var _ring: Node2D
var _glow: Aura
var _rage: Aura ## Wrath: the ember fire around a damaged Wrath minion
var _embers: CPUParticles2D
var raging := false
var _guard: Node2D
var _frost: Sprite2D
var _ward: Node2D
var _atk_l: Label
var _hp_l: Label
var _zzz: Control
var _icons: Node2D
var _t := 0.0
var _shadow: Node2D
var _depth := false ## the portrait has a depth map (ArtDepth): a small parallax on hover and while it lunges
var _view := Vector2.ZERO


func setup(snap: Dictionary) -> MinionView:
	uid = snap.uid
	card_id = snap.id
	side = snap.side
	var card := CardDB.card(card_id)
	base_attack = int(card.get("attack", 0))
	base_health = int(card.get("health", 1))
	_build()
	apply(snap)
	return self


func _build() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = CARD_FX
	material = _mat

	var shadow := Shapes.make(Shapes.Kind.ELLIPSE, Vector2(W + 10, H + 10), Color(0, 0, 0, 0.45))
	shadow.shade = false
	shadow.position = Vector2(6, 10)
	add_child(shadow)
	_shadow = shadow
	if UiSkin.has("guard_frame"):
		# The painted shield behind the portrait; its hole (66% x 64%) sits at 45% of its height.
		_guard = UiSkin.sprite("guard_frame", Vector2(W / 0.66, H / 0.64) * 0.98)
		_guard.position = Vector2(0, H / 0.64 * 0.98 * 0.05)
	else:
		_guard = Shapes.make(Shapes.Kind.SHIELD, Vector2(W + 34, H + 30), Color(0.32, 0.28, 0.25), Color(0.75, 0.62, 0.4), 4.0)
		_guard.position = Vector2(0, 6)
	add_child(_guard)
	# Wrath: while a Wrath minion is damaged, ember fire licks round its portrait with an angry pulse (under the
	# playable / target aura, so that one still reads on top).
	_rage = Aura.make(Vector2(W + 2, H + 2), true, 40.0)
	_rage.colors(Aura.RAGE)
	_rage.set_speed(1.8)
	add_child(_rage)
	_glow = Aura.make(Vector2(W + 4, H + 4), true, 36.0)
	add_child(_glow)

	var art := TextureRect.new()
	art.texture = CardDB.art_framed(card_id, W / H, 0.34)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.position = Vector2(-W / 2, -H / 2)
	art.size = Vector2(W, H)
	_art_mat = ShaderMaterial.new()
	_art_mat.shader = CARD_FX
	_art_mat.set_shader_parameter("mask_mode", 1)
	_depth = ArtDepth.setup_card(_art_mat, card_id, W / H, 0.34, ArtDepth.MINION)
	ArtLiving.setup_card(_art_mat, card_id, W / H, 0.34)
	art.material = _art_mat
	if art.texture == null:
		var g := GradientTexture2D.new()
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.4)
		g.fill_to = Vector2(1.0, 1.0)
		var gr := Gradient.new()
		gr.set_color(0, Color(0.5, 0.15, 0.05))
		gr.set_color(1, Color(0.05, 0.02, 0.02))
		g.gradient = gr
		art.texture = g
	add_child(art)
	ArtLoop.attach(self, self, art, _art_mat, card_id, W / H, 0.34)
	_embers = _make_embers()
	add_child(_embers)
	var legendary: bool = CardDB.card(card_id).get("rarity", "") == "legendary"
	_ring = UI.portrait_frame(Vector2(W, H), legendary)
	if _ring == null:
		_ring = Shapes.make(Shapes.Kind.ELLIPSE, Vector2(W + 2, H + 2), Color.TRANSPARENT,
			UI.RARITY.legendary if legendary else UI.GOLD, 6.0 if legendary else 5.0)
	add_child(_ring)
	if UiSkin.has("ward_bubble"):
		# The painted bubble (black background) drawn additively, so only its light shows.
		_ward = UiSkin.sprite("ward_bubble", Vector2(W + 80, H + 80))
		_ward.use_parent_material = false
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_ward.material = add
	else:
		_ward = Shapes.make(Shapes.Kind.ELLIPSE, Vector2(W + 22, H + 22), Color(1.0, 0.85, 0.35, 0.18), Color(1.0, 0.9, 0.5, 0.9), 3.0)
		_ward.shade = false
	_ward.set_meta("base", _ward.scale)
	add_child(_ward)

	_icons = Node2D.new()
	_icons.position = Vector2(0, H / 2 - 6)
	_icons.use_parent_material = true
	add_child(_icons)

	var painted := UiSkin.has("gem_attack") and UiSkin.has("gem_health")
	var atk: Node2D = UiSkin.sprite("gem_attack", Vector2(64, 64)) if painted else 		Shapes.make(Shapes.Kind.SWORD, Vector2(50, 58), Color(0.85, 0.62, 0.2), Color(0.35, 0.2, 0.05), 3.0)
	atk.position = Vector2(-W / 2 + 12, H / 2 - 22)
	add_child(atk)
	_atk_l = _stat(atk.position + UI.gem_number_offset("gem_attack", 64))
	var hp: Node2D = UiSkin.sprite("gem_health", Vector2(62, 62)) if painted else 		Shapes.make(Shapes.Kind.DROP, Vector2(48, 58), Color(0.75, 0.08, 0.06), Color(0.3, 0.02, 0.02), 3.0)
	hp.position = Vector2(W / 2 - 12, H / 2 - 24)
	add_child(hp)
	_hp_l = _stat(hp.position + UI.gem_number_offset("gem_health", 62))

	# Asleep (can't attack yet): the painted smoke z's, or the letters without the painting.
	if UiSkin.has("icon_sleep"):
		_zzz = UiSkin.rect("icon_sleep", Vector2(63, 48), Vector2(W / 2 - 40, -H / 2 - 30))
		_zzz.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	else:
		_zzz = UI.label("z z", 28, "italic", Color(0.8, 0.85, 1.0, 0.9), 5, Color(0, 0, 0.1))
		_zzz.position = Vector2(W / 2 - 40, -H / 2 - 30)
		_zzz.use_parent_material = true
	add_child(_zzz)


func _stat(center: Vector2) -> Label:
	var l := UI.stat_number("0", 30, center, Vector2(70, 52))
	l.use_parent_material = true
	add_child(l)
	return l


func apply(snap: Dictionary) -> void:
	attack = int(snap.get("attack", attack))
	health = int(snap.get("health", snap.get("hp", health)))
	max_health = int(snap.get("max_health", max_health))
	if snap.has("keywords"):
		keywords = snap.keywords
	if snap.has("sleeping"):
		sleeping = snap.sleeping
	if snap.has("rage"):
		set_raging(int(snap.rage) > 0)
	_refresh()


## Wrath on or off: the ember aura and sparks, a warm tint, and the Attack number in ember orange.
func set_raging(v: bool) -> void:
	if v == raging:
		return
	raging = v
	_rage.set_on(v)
	_embers.emitting = v
	_tint()
	_refresh()


## Rising sparks over a raging portrait (painted flame motes, additive), off until Wrath wakes.
func _make_embers() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = Fx._tex("k_flame_05")
	p.amount = 14
	p.lifetime = 1.3
	p.emitting = false
	p.position = Vector2(0, H * 0.32)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(W * 0.38, 10)
	p.direction = Vector2.UP
	p.spread = 18.0
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 90.0
	p.gravity = Vector2(0, -30)
	var px := 64.0 if p.texture == UI.dot_texture() else p.texture.get_width() * 0.25
	p.scale_amount_min = 7.0 / px
	p.scale_amount_max = 22.0 / px
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.75, 0.35, 0.9))
	ramp.add_point(0.5, Color(1.0, 0.3, 0.05, 0.7))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.5, 0.02, 0.0, 0.0))
	p.color_ramp = ramp
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	return p


## Frozen wins over raging (blue cold); raging alone warms the whole piece a little.
func _tint() -> void:
	if frozen:
		modulate = Color(0.75, 0.88, 1.15)
	elif raging:
		modulate = Color(1.12, 0.93, 0.88)
	else:
		modulate = Color.WHITE


func _refresh() -> void:
	_atk_l.text = str(attack)
	_hp_l.text = str(health)
	UI.center_ink(_atk_l)
	UI.center_ink(_hp_l)
	var atk_col := UI.HEAL if attack > base_attack else UI.NUMBER
	if raging:
		atk_col = Color(1.0, 0.55, 0.22) # the Wrath bonus burns in ember orange
	_atk_l.add_theme_color_override("font_color", atk_col)
	var hp_col := UI.NUMBER
	if health < max_health:
		hp_col = Color(1.0, 0.35, 0.3)
	elif health > base_health:
		hp_col = UI.HEAL
	_hp_l.add_theme_color_override("font_color", hp_col)
	_guard.visible = keywords.has("guard")
	_ward.visible = keywords.has("ward")
	_zzz.visible = sleeping and not keywords.has("swift")
	for c in _icons.get_children():
		c.queue_free()
	# Painted keyword medallions along the bottom of the frame.
	var icons: Array[String] = []
	if keywords.has("venom"):
		icons.append("icon_venom")
	if keywords.has("drain"):
		icons.append("icon_drain")
	if keywords.has("rebirth"):
		icons.append("icon_rebirth")
	var ons: Array = CardDB.card(card_id).get("effects", []).map(func(e): return e.get("on", ""))
	if "death" in ons:
		icons.append("icon_deathrattle")
	if "turn_end" in ons or "turn_start" in ons:
		icons.append("icon_trigger")
	if "frenzy" in ons:
		icons.append("icon_frenzy" if UiSkin.has("icon_frenzy") else "icon_trigger") # Frenzy: the torn claw marks
	if int(CardDB.card(card_id).get("wrath", 0)) > 0:
		icons.append("icon_rage" if UiSkin.has("icon_rage") else "icon_ash") # Wrath: the fist over the coals
	for i in icons.size():
		var s: Node2D = UiSkin.sprite(icons[i], Vector2(40, 40)) if UiSkin.has(icons[i]) else 			Shapes.make(Shapes.Kind.DIAMOND, Vector2(22, 28), Color(0.45, 0.4, 0.5), Color(0.1, 0.05, 0.02), 2.0)
		s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS # 512 px medallions shrunk to 40
		s.position = Vector2((i - (icons.size() - 1) / 2.0) * 36, 0)
		_icons.add_child(s)
	_refresh_glow()


var targetable := false:
	set(v):
		targetable = v
		_refresh_glow()


func _refresh_glow() -> void:
	if _glow:
		_glow.set_on(can_attack or targetable, Aura.TARGET if targetable else Aura.PLAYABLE)


var frozen := false


func set_frozen(v: bool) -> void:
	frozen = v
	_art_mat.set_shader_parameter("desat", 0.6 if v else 0.0)
	_tint()
	if UiSkin.has("frozen_overlay"):
		if _frost == null:
			_frost = UiSkin.sprite("frozen_overlay", Vector2(W, H) * 1.18)
			_frost.use_parent_material = false
			add_child(_frost)
			# Over the portrait ring but under the ward, the keyword icons and the stat gems, which must still read.
			move_child(_frost, _ring.get_index() + 1)
			_frost.set_meta("base", _frost.scale)
		_frost.visible = v
		if v:
			_frost.scale = Vector2.ZERO
			_frost.create_tween().tween_property(_frost, "scale", _frost.get_meta("base"), 0.25) 				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if v:
		flash(Color(0.6, 0.85, 1.0), 0.5)


func set_sleeping(v: bool) -> void:
	sleeping = v
	_refresh()


func _process(delta: float) -> void:
	_t += delta
	# Lifted (lunging, dropping in) minions cast a farther, softer shadow.
	var lift := clampf((scale.x - 1.0) / 0.5, 0.0, 1.0)
	_shadow.position = Vector2(6, 10).lerp(Vector2(30, 56), lift)
	_shadow.modulate.a = 1.0 - 0.45 * lift
	if _ward.visible:
		_ward.scale = _ward.get_meta("base") * (1.0 + 0.025 * sin(_t * 3.0))
		_ward.modulate.a = 0.75 + 0.25 * sin(_t * 2.1)
	if _zzz.visible:
		_zzz.position.y = -H / 2 - 30 + sin(_t * 1.6) * 6.0
		_zzz.modulate.a = 0.6 + 0.4 * sin(_t * 1.6)
	if raging:
		_rage.breathe(_t, 0.45, 1.3)
	if _depth:
		_update_parallax(delta)


## A board portrait leans under the pointer like a card (pressed where the pointer is), and is seen from behind its swing while
## it lunges at a target; otherwise it is flat.
func _update_parallax(delta: float) -> void:
	var view := Vector2.ZERO
	if busy and position.distance_squared_to(home) > 16.0:
		view = ((position - home) / 260.0).limit_length(1.0) * 0.3
	elif is_visible_in_tree() and contains_point(get_global_mouse_position()):
		var m := (to_local(get_global_mouse_position()) / Vector2(W / 2, H / 2)).limit_length(1.0)
		view = m * 0.22 + Vector2(sin(_t * 1.3), cos(_t * 1.05)) * 0.05
	_view = _view.lerp(view, minf(1.0, delta * 8.0))
	ArtDepth.look(_art_mat, _view)


func flash(color: Color = Color(1, 0.2, 0.1), duration: float = 0.35) -> void:
	_mat.set_shader_parameter("flash_color", color)
	_art_mat.set_shader_parameter("flash_color", color)
	var t := create_tween()
	t.tween_method(_set_flash, 1.0, 0.0, duration)


func _set_flash(v: float) -> void:
	_mat.set_shader_parameter("flash", v)
	_art_mat.set_shader_parameter("flash", v)


func burn_away(duration: float = 0.8) -> void:
	_glow.set_on(false)
	_rage.set_on(false)
	_embers.emitting = false
	var t := create_tween()
	t.tween_method(_set_burn, 0.0, 1.0, duration)
	await t.finished


func _set_burn(v: float) -> void:
	_mat.set_shader_parameter("burn", v)
	_art_mat.set_shader_parameter("burn", v)


## The colours of the dissolve's glowing rim (frost for an ice giant, violet for a shade...).
func set_burn_colors(edge: Color, hot: Color) -> void:
	for m in [_mat, _art_mat]:
		m.set_shader_parameter("burn_edge", edge)
		m.set_shader_parameter("burn_hot", hot)


## One card_fx uniform on the whole piece (frame and portrait): DeathFx drives its dissolve through it.
func set_fx(param: String, value) -> void:
	_mat.set_shader_parameter(param, value)
	_art_mat.set_shader_parameter(param, value)


## A death begins (DeathFx): its dressing goes out (the glows, Wrath's fire, the frost and ward overlays).
func dying(fade: float) -> void:
	_glow.set_on(false)
	_rage.set_on(false)
	_embers.emitting = false
	for n in [_frost, _ward]:
		if n != null and n.visible:
			n.create_tween().tween_property(n, "modulate:a", 0.0, fade)


func contains_point(global_point: Vector2) -> bool:
	var p := to_local(global_point)
	return pow(p.x / (W * 0.55), 2) + pow(p.y / (H * 0.55), 2) <= 1.0


func break_ward() -> void:
	_ward.visible = true
	var t := create_tween().set_parallel(true)
	var base: Vector2 = _ward.get_meta("base")
	t.tween_property(_ward, "scale", base * 1.5, 0.3)
	t.tween_property(_ward, "modulate:a", 0.0, 0.3)
	await t.finished
	_ward.scale = base
	_ward.modulate.a = 1.0
	keywords.erase("ward")
	_refresh()
