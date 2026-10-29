extends Node2D
## Pack opening: tap the sealed pack to tear it open; five cards fly out face down with a glow that hints their
## rarity; tap each to reveal it (rare / epic / legendary get bigger and bigger effects). The "Drop rates" plaque
## opens the odds (DropRatesPanel); a revealed card also shows its rarity's chance under it.

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
	Sfx.play_ambience("") # menus play the music alone (an ambience loop would leak in from the battle)
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

	# The heading on the charred banner.
	var title := UI.banner("Open Packs", 50)
	title.position = Vector2(30, 16)
	ui.add_child(title)
	# Packs and Obols on an engraved plaque under the title, the Obols beside their coin.
	var purse := UI.plaque(28, 8)
	purse.position = Vector2(56, 128)
	ui.add_child(purse)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	purse.add_child(row)
	_count_label = UI.label("", 30, "title", UI.BONE, 4, Color(0.04, 0.01, 0.01))
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_count_label)
	var dot := UI.label("·", 30, "title", Color(0.8, 0.66, 0.45), 4, Color(0.04, 0.01, 0.01))
	dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(dot)
	if UiSkin.has("icon_obol"):
		var coin := UiSkin.rect("icon_obol", Vector2(44, 44))
		coin.custom_minimum_size = coin.size
		coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(coin)
	_obols_label = UI.label("", 30, "title", Color(1.0, 0.85, 0.5), 4, Color(0.04, 0.01, 0.01))
	_obols_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_obols_label)
	# The odds, one plaque away, on the right at the height of the purse.
	var rates := UI.button("Drop rates", 340, 64) # wide enough for the letters at the purse's size
	rates.name = "DropRatesButton"
	rates.add_theme_font_size_override("font_size", 30)
	UI.fit_text(rates)
	rates.position = Vector2(V.x - rates.custom_minimum_size.x - 56, 128)
	rates.pressed.connect(func(): DropRatesPanel.open(self))
	ui.add_child(rates)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 24)
	_buttons.position = Vector2(V.x / 2 - 520, V.y - 120)
	ui.add_child(_buttons)
	var back := UI.button("Back", 300, 80)
	back.pressed.connect(func(): Game.go(Game.MENU))
	_buttons.add_child(back)
	var buy := UI.button(Loc.t("Buy pack (%d)") % Collection.PACK_PRICE, 400, 80)
	buy.name = "Buy"
	buy.pressed.connect(_buy)
	_buttons.add_child(buy)
	var again := UI.button("Open next", 340, 80)
	again.name = "Next"
	again.pressed.connect(_next_pack)
	_buttons.add_child(again)
	UI.even_text([back, buy, again]) # one letter size along the row (each plate fitted alone, "Open next" set smaller)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.size = V
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_flash)
	_refresh()
	# Level with the purse: the two plates share their middle line (the purse sizes itself around its text, set now).
	purse.reset_size()
	rates.position.y = purse.position.y + (purse.size.y - rates.get_combined_minimum_size().y) / 2.0
	_spawn_pack()
	if "--autoplay" in OS.get_cmdline_user_args():
		_auto()


## Esc / the back gesture (Game.back): like Back (the cards of an opened pack are already in the collection).
func go_back() -> void:
	Game.go(Game.MENU)


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
	_count_label.text = Loc.t("Packs: %d") % Collection.packs
	_obols_label.text = Loc.t("%d Obols") % Collection.obols
	(_buttons.get_node("Buy") as Button).disabled = Collection.obols < Collection.PACK_PRICE
	(_buttons.get_node("Next") as Button).visible = _state == "done" and Collection.packs > 0
	# Keep the row centred under the table whether "Open next" shows or not.
	var w := 0.0
	var n := 0
	for b in _buttons.get_children():
		if b.visible:
			w += b.custom_minimum_size.x
			n += 1
	w += _buttons.get_theme_constant("separation") * maxi(0, n - 1)
	_buttons.position.x = (V.x - w) / 2.0


func _buy() -> void:
	if Collection.buy_pack():
		Sfx.play("coins", -2.0)
		Sfx.play("coin_pouch", -6.0)
		_refresh()
		# A new pack goes on the table only when it is free: bought while a pack was bursting open ("opening"), the
		# cards in flight were swept away and the screen hung in "reveal" with nothing left to reveal.
		if pack == null and _state in ["idle", "done"]:
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
		if ui.get_node_or_null("Empty") != null:
			return
		# The hint inked on a parchment sheet in the middle of the table.
		var holder := CenterContainer.new()
		holder.name = "Empty"
		holder.size = V
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ui.add_child(holder)
		var plate := PanelContainer.new()
		plate.add_theme_stylebox_override("panel", UI.tip_box())
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(plate)
		var l := UI.label("No packs left. Win battles to earn Obols." if Collection.obols < Collection.PACK_PRICE
			else "Buy a pack to continue.", 34, "italic", UI.INK)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		plate.add_child(l)
		UI.center_ink(l) # on the sheet's middle
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
	# The seal: Charon's painted obol stamped on the pack (the price of every pack), else a drawn wax seal.
	var seal: Node2D = UiSkin.sprite("icon_obol", Vector2(130, 130)) if UiSkin.has("icon_obol") else \
		Shapes.make(Shapes.Kind.ELLIPSE, Vector2(110, 110), UI.CRIMSON, UI.GOLD, 6.0)
	seal.use_parent_material = false
	pack.add_child(seal)
	# The call to action on the red ribbon hung under the pack.
	# "Tap" on a phone or tablet, "Click" on desktop (the same test as SkipRing).
	var touch := DisplayServer.is_touchscreen_available() and OS.has_feature("mobile")
	var hint := UI.ribbon("Tap to open" if touch else "Click to open", 540, 40)
	hint.position += Vector2(0, 300)
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
		_tag(v, Loc.t("+%d Obols") % d.refund, Color(1.0, 0.85, 0.5))
		Sfx.play("coin_spin", -8.0)
	_rate_note(v, d.rarity)
	if _cards.all(func(x): return x.revealed):
		_state = "done"
		_refresh()


## A small engraved plaque over a revealed card ("NEW", or the Obols a duplicate refunds).
func _tag(v: Node2D, text: String, color: Color) -> void:
	var holder := CenterContainer.new()
	holder.size = Vector2(320, 70)
	holder.position = Vector2(-160, -CardView.H / 2 - 74)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(UI.plaque_label(text, 36, "title", color, 0.0, 26, 6))
	v.add_child(holder)
	holder.scale = Vector2(0.3, 0.3)
	holder.pivot_offset = holder.size / 2
	holder.create_tween().tween_property(holder, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK)


## How likely this rarity was, in small letters under a revealed card ("Rare · 21%"), from the pack odds.
func _rate_note(v: Node2D, rarity: String) -> void:
	var l := UI.label("%s · %s" % [Loc.t(rarity.capitalize()), Collection.percent_text(Collection.drop_rates()[rarity])], 26,
		"title", RARITY_GLOW[rarity].lerp(UI.BONE, 0.35), 5, Color(0.04, 0.01, 0.01))
	l.name = "RateNote"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(CardView.W, 36)
	l.position = Vector2(-CardView.W / 2, CardView.H / 2 + 6)
	v.add_child(l)
	l.modulate.a = 0.0
	l.create_tween().tween_property(l, "modulate:a", 0.85, 0.4).set_delay(0.3)


## A legendary's name on the charred banner across the top of the table.
func _banner(text: String, color: Color) -> void:
	var l := UI.banner(text, 60, color)
	l.position = Vector2((V.x - l.size.x) / 2, 4)
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
