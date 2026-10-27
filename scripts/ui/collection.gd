extends Control
## Card gallery with set filters; click a card to see it large. A class filter shows the class's strip over the grid
## (hero, tagline, hero power, keywords, and a Class guide button for the whole guide: ClassInfoPanel); Neutral and
## Tokens get a short note.

var _grid: GridContainer
var _filter := "all"
var _zoom: Control
var _tabs := {} ## filter -> Button
var _class_bar: Control ## holds the strip about the filtered class (empty on "All")


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
	# The heading on the charred banner (it overhangs the bar a little, so the bar keeps the buttons' height).
	var title := UI.banner("Collection", 38, UI.GOLD, 0.0, 64.0, 1.8)
	top.add_child(title)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(gap)
	var owned_n := 0
	var total := 0
	for c in CardDB.all_cards():
		if c.get("set", "") != "token":
			total += 1
			owned_n += int(Collection.copies(c.id) > 0)
	# Cards owned out of the whole pool, engraved on a plaque.
	var progress := UI.plaque_label("%d / %d cards" % [owned_n, total], 28, "title", UI.BONE, 0.0, 24, 8)
	progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(progress)
	var filters := [["all", "All"]]
	for cls in CardDB.classes():
		filters.append([cls, CardDB.class_title(cls)])
	filters.append_array([["neutral", "Neutral"], ["token", "Tokens"]])
	# The filters get a row of their own under the title bar: squeezed beside the banner, a long class name on its
	# plate shrank to about 17 px. The plates narrow only when more classes arrive than the screen holds.
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 14)
	root.add_child(tabs)
	var fw := clampf((get_viewport_rect().size.x - 80.0 - 14.0 * (filters.size() - 1)) / filters.size(), 150.0, 230.0)
	for f in filters:
		var b := UI.button(f[1], fw, 60)
		b.add_theme_font_size_override("font_size", 26)
		b.pressed.connect(_set_filter.bind(f[0]))
		tabs.add_child(b)
		_tabs[f[0]] = b
	UI.even_text(_tabs.values())
	_class_bar = VBoxContainer.new()
	root.add_child(_class_bar)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.paint_scroll(scroll)
	root.add_child(scroll)
	# A little room above the first row, so the copies discs pinned over the cards' corners are not cut off.
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_top", 18)
	scroll.add_child(pad)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(center)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 26)
	_grid.add_theme_constant_override("v_separation", 26)
	center.add_child(_grid)
	resized.connect(_fill)
	_set_filter(_filter)


## Esc / the back gesture (Game.back): closes the enlarged card, else like Back.
func go_back() -> void:
	if is_instance_valid(_zoom) and not _zoom.is_queued_for_deletion():
		_zoom.queue_free()
		_zoom = null
	else:
		Game.go(Game.MENU)


func _set_filter(f: String) -> void:
	_filter = f
	for c in _class_bar.get_children():
		_class_bar.remove_child(c)
		c.queue_free()
	var w := get_viewport_rect().size.x - 80.0
	if f in CardDB.classes():
		_class_bar.add_child(ClassInfoPanel.strip(f, w, true))
	elif ClassInfoPanel.NOTES.has(f):
		_class_bar.add_child(ClassInfoPanel.note_strip(f, w))
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


## The card big over a veil, with its name, flavour and keyword tips (CardZoom); any press closes it.
func _show_zoom(id: String) -> void:
	if is_instance_valid(_zoom):
		_zoom.queue_free()
	_zoom = CardZoom.open(self, id)
