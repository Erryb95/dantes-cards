extends Control
## Card gallery with set filters; click a card to see it large.

var _grid: GridContainer
var _filter := "all"
var _zoom: Control
var _tabs := {} ## filter -> Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackdrop.new())
	Sfx.play_ambience("") # menus play the music alone (an ambience loop would leak in from the battle)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 40
	root.offset_right = -40
	root.offset_top = 24
	root.offset_bottom = -24
	root.add_theme_constant_override("separation", 16)
	add_child(root)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 20)
	root.add_child(top)
	var back := UI.button("Back", 200, 64)
	back.pressed.connect(func(): Game.go(Game.MENU))
	top.add_child(back)
	var title := UI.label("Collection", 56, "title", UI.GOLD, 8, Color.BLACK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var owned_n := 0
	var total := 0
	for c in CardDB.all_cards():
		if c.get("set", "") != "token":
			total += 1
			owned_n += int(Collection.copies(c.id) > 0)
	# Cards owned out of the whole pool, engraved on a plaque.
	var progress := UI.plaque_label("%d / %d" % [owned_n, total], 28, "title", UI.BONE, 0.0, 24, 8)
	progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(progress)
	for f in [["all", "All"], ["pilgrim", "Pilgrim"], ["ferry", "Ferryman"], ["neutral", "Neutral"], ["token", "Tokens"]]:
		var b := UI.button(f[1], 180, 64)
		b.add_theme_font_size_override("font_size", 26)
		b.pressed.connect(_set_filter.bind(f[0]))
		top.add_child(b)
		_tabs[f[0]] = b
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.paint_scroll(scroll)
	root.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 26)
	_grid.add_theme_constant_override("v_separation", 26)
	center.add_child(_grid)
	resized.connect(_fill)
	_fill()


func _set_filter(f: String) -> void:
	_filter = f
	_fill()


func _fill() -> void:
	for f in _tabs: # the filter that is on is lit, the others dimmed
		(_tabs[f] as Button).modulate = Color(1.15, 1.05, 0.85) if f == _filter else Color(0.72, 0.66, 0.6)
	for c in _grid.get_children():
		c.queue_free()
	var s := 0.72
	_grid.columns = maxi(2, int((size.x - 80) / (CardView.W * s + 26)))
	var cards := CardDB.all_cards().filter(func(c): return _filter == "all" or c.set == _filter)
	cards.sort_custom(func(a, b): return [a.set == "token", a.cost, a.name] < [b.set == "token", b.cost, b.name])
	for c in cards:
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(CardView.W * s, CardView.H * s)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		var v := CardView.new().setup(c.id, -1, true)
		v.scale = Vector2(s, s)
		v.position = slot.custom_minimum_size / 2
		slot.add_child(v)
		if c.set != "token":
			var n := Collection.copies(c.id)
			if n == 0:
				v.modulate = Color(0.32, 0.3, 0.3)
			else:
				# The copies owned, engraved on a bronze disc pinned to the card's top-right corner.
				var badge := Control.new()
				badge.size = Vector2(54, 54)
				badge.position = Vector2(slot.custom_minimum_size.x - 40, -14)
				badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
				if UiSkin.has("power_disc"):
					badge.add_child(UiSkin.rect("power_disc", badge.size))
				var count := UI.label("x%d" % n, 22, "title", UI.GOLD, 5, Color.BLACK)
				if UiSkin.has("power_disc"):
					UI.engraved(count)
				count.size = badge.size
				count.position.y = 1
				count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				badge.add_child(count)
				slot.add_child(badge)
		slot.mouse_entered.connect(func():
			v.create_tween().tween_property(v, "scale", Vector2(s, s) * 1.06, 0.1)
			Sfx.play("tick", -16.0))
		slot.mouse_exited.connect(func(): v.create_tween().tween_property(v, "scale", Vector2(s, s), 0.1))
		slot.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_show_zoom(c.id))
		_grid.add_child(slot)


func _show_zoom(id: String) -> void:
	if _zoom != null:
		_zoom.queue_free()
	_zoom = ColorRect.new()
	(_zoom as ColorRect).color = Color(0, 0, 0, 0.75)
	_zoom.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_zoom)
	var vs := get_viewport_rect().size
	var c := CardView.new().setup(id, -1, true)
	c.position = Vector2(vs.x * 0.4, vs.y / 2)
	c.scale = Vector2(0.6, 0.6)
	_zoom.add_child(c)
	c.create_tween().tween_property(c, "scale", Vector2(1.9, 1.9) * minf(1.0, vs.y / 1080.0), 0.18).set_trans(Tween.TRANS_BACK)
	var card := CardDB.card(id)
	# The name and flavour on a framed plate beside the card.
	var w := minf(620.0, vs.x * 0.34)
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", UI.tip_box())
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.custom_minimum_size = Vector2(w, 0)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 14)
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(pv)
	var name_l := UI.label(str(card.get("name", "")), 34, "title", UI.GOLD, 4, Color.BLACK)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pv.add_child(name_l)
	var flavor := str(card.get("flavor", ""))
	if flavor != "":
		var info := UI.label(flavor, 28, "italic", UI.BONE, 3, Color.BLACK)
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size = Vector2(w - 100, 0)
		pv.add_child(info)
	var holder := CenterContainer.new()
	holder.position = Vector2(vs.x * 0.58, 0)
	holder.size = Vector2(w + 40, vs.y)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(plate)
	_zoom.add_child(holder)
	Sfx.play("page", -6.0)
	_zoom.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_zoom.queue_free()
			_zoom = null)
