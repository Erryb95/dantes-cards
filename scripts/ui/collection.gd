extends Control
## Card gallery with set filters and a sort plaque; click a card to see it large. A class filter shows the class's strip
## over the grid (hero, tagline, hero power, keywords, and a Class guide button for the whole guide: ClassInfoPanel);
## Neutral and Tokens get a short note. The sort (Settings.collection_sort) applies inside the filter; sorted by
## rarity, a painted divider names each rarity. Tokens always come last.

## [id, label on the plaque]: the plaque cycles through them in this order.
const SORTS := [["cost", "Cost"], ["rarity", "Rarity"], ["rarity_asc", "Low rarity"], ["name", "Name"],
	["owned", "Owned"]]
const SORT_FONT := 26
const GAP := 26.0
const SCALE := 0.72 ## the cards in the grid
const BAR_W := 26.0 ## the painted scroll bar right of the grid
const TAB_GAP := 14.0

var _body: VBoxContainer ## the card sections (one grid, or one per rarity)
var _scroll: ScrollContainer
var _sort := "cost"
var _sort_btn: Button
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
	_sort = Settings.collection_sort if SORTS.any(func(x): return x[0] == Settings.collection_sort) else "cost"
	_sort_btn = UI.button("", 360, 64)
	_sort_btn.name = "SortButton"
	_sort_btn.tooltip_text = "Change the order of the cards"
	_sort_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sort_btn.pressed.connect(_cycle_sort)
	top.add_child(_sort_btn)
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
	# The sort plaque takes the room the title and the count leave, within reason.
	var room := get_viewport_rect().size.x - 80.0 - back.custom_minimum_size.x - title.get_combined_minimum_size().x \
		- progress.get_combined_minimum_size().x - 20.0 * 4
	_sort_btn.custom_minimum_size.x = clampf(room, 280.0, 360.0)
	_update_sort_button()
	var filters := [["all", "All"]]
	for cls in CardDB.classes():
		filters.append([cls, CardDB.class_title(cls)])
	filters.append_array([["neutral", "Neutral"], ["token", "Tokens"]])
	# The filters get a row of their own under the title bar: squeezed beside the banner, a long class name on its
	# plate shrank to about 17 px. The row is as wide as the card grid under it (same left and right edges); the
	# plates narrow only when more classes arrive than that holds.
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", int(TAB_GAP))
	root.add_child(tabs)
	var fw := clampf((_grid_width(get_viewport_rect().size.x) - TAB_GAP * (filters.size() - 1)) / filters.size(),
		150.0, 320.0)
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
	_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.paint_scroll(scroll, int(BAR_W))
	root.add_child(scroll)
	# A little room above the first row, so the copies discs pinned over the cards' corners are not cut off; on the
	# left as much as the scroll bar takes on the right, so the grid is centred on the screen like the filters.
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_top", 18)
	pad.add_theme_constant_override("margin_left", int(BAR_W))
	scroll.add_child(pad)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(center)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 22)
	center.add_child(_body)
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


## The plaque shows the current order ("Sort: Cost").
func _update_sort_button() -> void:
	var label := ""
	for x in SORTS:
		if x[0] == _sort:
			label = x[1]
	_sort_btn.text = "Sort: " + label
	_sort_btn.add_theme_font_size_override("font_size", SORT_FONT)
	UI.fit_text(_sort_btn)


## Next order in SORTS (saved in the settings), the grid back at the top.
func _cycle_sort() -> void:
	var i := 0
	for k in SORTS.size():
		if SORTS[k][0] == _sort:
			i = k
	_sort = SORTS[(i + 1) % SORTS.size()][0]
	Settings.collection_sort = _sort
	Settings.save()
	_update_sort_button()
	_scroll.scroll_vertical = 0
	_fill()


## The sort key of a card under the current order: tokens last, then the order's own keys, then cost and name.
func _sort_key(c: Dictionary) -> Array:
	var token: bool = c.set == "token"
	var rank := Collection.RARITY_ORDER.find(str(c.get("rarity", "common"))) # 0 = legendary
	match _sort:
		"rarity":
			return [token, rank, c.cost, c.name]
		"rarity_asc":
			return [token, -rank, c.cost, c.name]
		"name":
			return [token, str(c.name).to_lower()]
		"owned":
			return [token, Collection.copies(c.id) == 0, c.cost, c.name]
	return [token, c.cost, c.name]


## The cards the current filter shows, in the current order.
func _visible_cards() -> Array:
	var cards := CardDB.all_cards().filter(func(c): return _filter == "all" or c.set == _filter)
	cards.sort_custom(func(a, b): return _sort_key(a) < _sort_key(b))
	return cards


## The grid's columns on a screen `w` px wide (inside the margins, the scroll bar and the room the grid keeps on its
## left to stay centred), and the width they take.
func _columns(w: float) -> int:
	return maxi(2, int((w - 80.0 - 2.0 * BAR_W + GAP) / (CardView.W * SCALE + GAP)))


func _grid_width(w: float) -> float:
	var cols := _columns(w)
	return cols * CardView.W * SCALE + (cols - 1) * GAP


## A rarity's heading over its cards: gilded capitals (tinted by the rarity) over a thin bronze rod.
func _divider(cap: String, key: String, room: float) -> Control:
	var v := VBoxContainer.new()
	v.name = "Divider_" + key
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tint: Color = UI.GOLD.lerp(UI.RARITY.get(key, UI.GOLD), 0.45)
	v.add_child(ClassInfoPanel.gilded(cap.to_upper(), 34, room, tint))
	if UiSkin.has("slider_track"):
		var rod := UiSkin.rect("slider_track", Vector2(room, 8))
		rod.custom_minimum_size = Vector2(room, 8)
		rod.modulate = Color(0.85, 0.75, 0.6)
		v.add_child(rod)
	return v


func _make_grid(columns: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", int(GAP))
	g.add_theme_constant_override("v_separation", int(GAP))
	return g


func _fill() -> void:
	for f in _tabs: # the filter that is on is lit, the others dimmed
		(_tabs[f] as Button).modulate = Color(1.15, 1.05, 0.85) if f == _filter else Color(0.72, 0.66, 0.6)
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	var s := SCALE
	var cols := _columns(size.x)
	var cards := _visible_cards()
	# Sorted by rarity, each rarity gets a divider and a grid of its own; otherwise it is one grid.
	var dividers := _sort in ["rarity", "rarity_asc"] and _filter != "token"
	var grid: GridContainer = null
	var group := ""
	for c in cards:
		var key: String = "token" if c.set == "token" else str(c.get("rarity", "common"))
		if grid == null or (dividers and key != group):
			group = key
			var section := VBoxContainer.new()
			section.add_theme_constant_override("separation", 14)
			_body.add_child(section)
			if dividers:
				var cap: String = "Tokens" if key == "token" else key.capitalize()
				var room := cols * (CardView.W * s + GAP) - GAP
				section.add_child(_divider(cap, key, room))
			grid = _make_grid(cols)
			section.add_child(grid)
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
		grid.add_child(slot)


## The card big over a veil, with its name, flavour and keyword tips (CardZoom); any press closes it.
func _show_zoom(id: String) -> void:
	if is_instance_valid(_zoom):
		_zoom.queue_free()
	_zoom = CardZoom.open(self, id)
