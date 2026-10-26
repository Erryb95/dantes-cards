extends Node2D
## Pack opening: tap the sealed pack to tear it open; five cards fly out face down with a glow that hints their
## rarity; tap each to reveal it (rare / epic / legendary get bigger and bigger effects).

const RARITY_GLOW := {"common": Color(0.75, 0.7, 0.62), "rare": Color(0.3, 0.6, 1.0), "epic": Color(0.75, 0.35, 1.0),
	"legendary": Color(1.0, 0.6, 0.15)}

var V := Vector2(1920, 1080)
var cam: Camera2D
var fx: Node2D
var ui: CanvasLayer
var pack: Node2D
var _pack_t := 0.0
var _state := "idle" ## idle -> opening -> reveal -> done
var _cards: Array = [] ## [{view, data, glow, revealed}]
var _shake := 0.0
var _count_label: Label
var _obols_label: Label
var _buttons: HBoxContainer
var _flash: ColorRect


func _ready() -> void:
	V = get_viewport_rect().size
	cam = Camera2D.new()
	cam.position = V / 2
	add_child(cam)
	var bd := MenuBackdrop.new()
	var bl := CanvasLayer.new()
	bl.layer = -1
	add_child(bl)
	bl.add_child(bd)
	fx = Node2D.new()
	fx.z_index = 50
	add_child(fx)
	ui = CanvasLayer.new()
	add_child(ui)
	Sfx.play_music("intro")

	var title := UI.label("Open Packs", 64, "title", UI.GOLD, 10, Color.BLACK)
	title.position = Vector2(60, 30)
	ui.add_child(title)
	_count_label = UI.label("", 34, "title", UI.BONE, 6, Color.BLACK)
	_count_label.position = Vector2(64, 110)
	ui.add_child(_count_label)
	_obols_label = UI.label("", 30, "body", Color(1.0, 0.85, 0.5), 5, Color.BLACK)
	_obols_label.position = Vector2(64, 158)
	ui.add_child(_obols_label)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 24)
	_buttons.position = Vector2(V.x / 2 - 520, V.y - 120)
	ui.add_child(_buttons)
	var back := UI.button("Back", 300, 80)
	back.pressed.connect(func(): Game.go(Game.MENU))
	_buttons.add_child(back)
	var buy := UI.button("Buy pack (%d)" % Collection.PACK_PRICE, 380, 80)
	buy.name = "Buy"
	buy.pressed.connect(_buy)
	_buttons.add_child(buy)
	var again := UI.button("Open next", 300, 80)
	again.name = "Next"
	again.pressed.connect(_next_pack)
	_buttons.add_child(again)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.size = V
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_flash)
	_refresh()
	_spawn_pack()
	if "--autoplay" in OS.get_cmdline_user_args():
		_auto()


## Debug / smoke test: opens a pack and reveals every card on its own.
func _auto() -> void:
	await get_tree().create_timer(0.8).timeout
	if pack == null:
		Collection.packs += 1
		_spawn_pack()
		await get_tree().create_timer(0.6).timeout
	await _open()
	for c in _cards:
		await get_tree().create_timer(0.45).timeout
		_reveal(c)


func _refresh() -> void:
	_count_label.text = "Packs: %d" % Collection.packs
	_obols_label.text = "Obols: %d" % Collection.obols
	(_buttons.get_node("Buy") as Button).disabled = Collection.obols < Collection.PACK_PRICE
	(_buttons.get_node("Next") as Button).visible = _state == "done" and Collection.packs > 0


func _buy() -> void:
	if Collection.buy_pack():
		Sfx.play("coins", -2.0)
		Sfx.play("coin_pouch", -6.0)
		_refresh()
		if pack == null and _state != "reveal":
			_next_pack()


func _next_pack() -> void:
	for c in _cards:
		var v: Node2D = c.view
		var t := v.create_tween().set_parallel(true)
		t.tween_property(v, "position", Vector2(V.x + 400, v.position.y), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		t.chain().tween_callback(v.queue_free)
		if is_instance_valid(c.glow):
			c.glow.queue_free()
	_cards.clear()
	_state = "idle"
	_spawn_pack()


func _spawn_pack() -> void:
	_refresh()
	if Collection.packs <= 0:
		var l := UI.label("No packs left. Win battles to earn Obols." if Collection.obols < Collection.PACK_PRICE
			else "Buy a pack to continue.", 36, "italic", UI.BONE, 6, Color.BLACK)
		l.name = "Empty"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size = Vector2(V.x, 60)
		l.position = Vector2(0, V.y / 2 - 30)
		ui.add_child(l)
		return
	var old := ui.get_node_or_null("Empty")
	if old:
		old.queue_free()
	pack = Node2D.new()
	pack.position = Vector2(V.x / 2, V.y / 2)
	add_child(pack)
	var glow := Sprite2D.new()
	glow.texture = UI.dot_texture()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = add
	glow.modulate = Color(1.0, 0.5, 0.15, 0.6)
	glow.scale = Vector2(9, 11)
	glow.name = "Glow"
	pack.add_child(glow)
	var body := CardView.new().setup("lost_pilgrim", -1, false)
	body.scale = Vector2(1.25, 1.25)
	body.set_process(false)
	pack.add_child(body)
	var seal := Shapes.make(Shapes.Kind.ELLIPSE, Vector2(110, 110), UI.CRIMSON, UI.GOLD, 6.0)
	seal.use_parent_material = false
	pack.add_child(seal)
	var hint := UI.label("Tap to open", 40, "title", UI.BONE, 8, Color.BLACK)
	hint.size = Vector2(500, 60)
	hint.position = Vector2(-250, 260)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pack.add_child(hint)
	pack.scale = Vector2(0.3, 0.3)
	pack.modulate.a = 0.0
	var t := pack.create_tween().set_parallel(true)
	t.tween_property(pack, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(pack, "modulate:a", 1.0, 0.3)
	Sfx.play("swish_long", -6.0, 0.8)


func _process(delta: float) -> void:
	_pack_t += delta
	if pack != null and _state == "idle":
		pack.rotation = sin(_pack_t * 1.4) * 0.04
		pack.position.y = V.y / 2 + sin(_pack_t * 2.0) * 10.0
		(pack.get_node("Glow") as Sprite2D).modulate.a = 0.45 + 0.2 * sin(_pack_t * 3.0)
	if _shake > 0.1:
		cam.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
		_shake = lerpf(_shake, 0.0, minf(1.0, delta * 8.0))
	else:
		cam.offset = Vector2.ZERO
	for c in _cards:
		if not c.revealed and is_instance_valid(c.glow):
			c.glow.modulate.a = 0.5 + 0.3 * sin(_pack_t * 4.0 + c.view.position.x)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var p: Vector2 = get_canvas_transform().affine_inverse() * event.position
	if _state == "idle" and pack != null and p.distance_to(pack.position) < 320.0:
		_open()
	elif _state == "reveal":
		for c in _cards:
			if not c.revealed and c.view.contains_point(p):
				_reveal(c)
				break


func _slots() -> Array:
	# A pentagon of cards: two on top, three below (like opening a real pack on a table).
	var cx := V.x / 2
	var cy := V.y / 2 - 20
	return [Vector2(cx - 240, cy - 190), Vector2(cx + 240, cy - 190), Vector2(cx - 440, cy + 170),
		Vector2(cx, cy + 190), Vector2(cx + 440, cy + 170)]


func _open() -> void:
	_state = "opening"
	var result := Collection.open_pack()
	_refresh()
	# Charge up, then burst.
	var t := pack.create_tween()
	t.tween_property(pack, "scale", Vector2(1.12, 0.92), 0.12)
	t.tween_property(pack, "scale", Vector2(0.92, 1.1), 0.12)
	t.tween_property(pack, "scale", Vector2(1.2, 1.2), 0.18)
	Sfx.play("rubble", -6.0, 1.3)
	Sfx.play("pack_open", -2.0)
	await t.finished
	_shake = 14.0
	_screen_flash(Color(1.0, 0.8, 0.5), 0.5)
	Sfx.play("thunder", -6.0, 1.2)
	Fx.shockwave(fx, pack.position, UI.GOLD, 900.0, 0.7)
	Fx.burst(fx, pack.position, UI.EMBER, 90, 900.0, 1.4, 16.0, 200.0)
	Fx.flash(fx, "holy_light", pack.position, 900.0, 0.9)
	pack.queue_free()
	pack = null
	var slots := _slots()
	for i in result.size():
		var d: Dictionary = result[i]
		var v := CardView.new().setup(d.id, -1, false)
		v.position = Vector2(V.x / 2, V.y / 2)
		v.scale = Vector2(0.2, 0.2)
		v.z_index = 10
		var glow := Sprite2D.new()
		glow.texture = UI.dot_texture()
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		glow.material = add
		glow.modulate = RARITY_GLOW[d.rarity]
		var gs: float = {"common": 4.0, "rare": 5.5, "epic": 6.5, "legendary": 8.0}[d.rarity]
		glow.scale = Vector2(gs, gs * 1.3)
		glow.position = slots[i]
		glow.z_index = 5
		add_child(glow)
		add_child(v)
		var tt := v.create_tween().set_parallel(true)
		tt.tween_property(v, "position", slots[i], 0.45).set_delay(i * 0.07).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tt.tween_property(v, "scale", Vector2(0.8, 0.8), 0.45).set_delay(i * 0.07)
		tt.tween_property(v, "rotation", randf_range(-0.08, 0.08), 0.45).set_delay(i * 0.07)
		_cards.append({"view": v, "data": d, "glow": glow, "revealed": false})
	Sfx.play("swish_long", -4.0, 1.1)
	Sfx.play("pack_take", -4.0)
	await get_tree().create_timer(0.8).timeout
	_state = "reveal"


func _reveal(c: Dictionary) -> void:
	c.revealed = true
	var v: CardView = c.view
	var d: Dictionary = c.data
	var col: Color = RARITY_GLOW[d.rarity]
	var t := v.create_tween()
	t.tween_property(v, "scale:x", 0.0, 0.12)
	t.tween_callback(v.set_face_up.bind(true))
	Sfx.play("card_flip", -4.0)
	t.tween_property(v, "scale:x", 0.8, 0.12)
	t.tween_property(v, "scale", Vector2(0.92, 0.92), 0.1)
	t.tween_property(v, "scale", Vector2(0.85, 0.85), 0.2).set_trans(Tween.TRANS_BACK)
	await get_tree().create_timer(0.24).timeout
	match d.rarity:
		"common":
			Sfx.play("card_place", -4.0)
			Fx.burst(fx, v.position, col, 20, 220.0, 0.6, 9.0, 0.0)
		"rare":
			Sfx.play("chime", -6.0, 1.1)
			Sfx.play("gem", -4.0)
			Fx.burst(fx, v.position, col, 50, 420.0, 0.9, 12.0, 0.0)
			Fx.shockwave(fx, v.position, col, 300.0, 0.5)
			_shake = 4.0
		"epic":
			Sfx.play("chime", -2.0, 0.85)
			Sfx.play("gem", -2.0, 0.8)
			Sfx.play("wail", -14.0, 1.3)
			Fx.burst(fx, v.position, col, 80, 600.0, 1.1, 14.0, 0.0)
			Fx.shockwave(fx, v.position, col, 500.0, 0.6)
			_shake = 8.0
			_screen_flash(col, 0.35)
		"legendary":
			Sfx.play("thunder", 0.0, 0.9)
			Sfx.play("title_sting", -4.0, 1.0, 0.0)
			Fx.burst(fx, v.position, col, 140, 900.0, 1.6, 16.0, 100.0)
			Fx.shockwave(fx, v.position, col, 900.0, 0.9)
			Fx.flash(fx, "holy_light", v.position, 900.0, 1.2)
			_shake = 18.0
			_screen_flash(col, 0.6)
			_banner(str(CardDB.card(d.id).get("name", "")).split(",")[0].to_upper(), col)
	if is_instance_valid(c.glow):
		var gt: Tween = c.glow.create_tween()
		gt.tween_property(c.glow, "modulate:a", 0.0, 0.6)
		gt.tween_callback(c.glow.queue_free)
	if d.new:
		_tag(v, "NEW", Color(0.5, 1.0, 0.5))
	elif d.refund > 0:
		_tag(v, "+%d obols" % d.refund, Color(1.0, 0.85, 0.5))
		Sfx.play("coin_spin", -8.0)
	if _cards.all(func(x): return x.revealed):
		_state = "done"
		_refresh()


func _tag(v: Node2D, text: String, color: Color) -> void:
	var l := UI.label(text, 40, "title", color, 8, Color.BLACK)
	l.size = Vector2(300, 50)
	l.position = Vector2(-150, -CardView.H / 2 - 56)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	l.scale = Vector2(0.3, 0.3)
	l.pivot_offset = l.size / 2
	l.create_tween().tween_property(l, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK)


func _banner(text: String, color: Color) -> void:
	var l := UI.label(text, 90, "title", color, 14, Color.BLACK)
	l.size = Vector2(V.x, 120)
	l.position = Vector2(0, 40)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.pivot_offset = l.size / 2
	l.scale = Vector2(1.6, 1.6)
	ui.add_child(l)
	var t := l.create_tween()
	t.tween_property(l, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK)
	t.tween_interval(1.6)
	t.tween_property(l, "modulate:a", 0.0, 0.6)
	t.tween_callback(l.queue_free)


func _screen_flash(color: Color, duration: float) -> void:
	_flash.color = Color(color.r, color.g, color.b, 0.6)
	_flash.create_tween().tween_property(_flash, "color:a", 0.0, duration)
