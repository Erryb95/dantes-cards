extends Control
## Deck builder: 30 cards from your class and the neutrals, max 2 copies (1 for legendaries), only cards you own.
## Click a card to add it, click a row in the list to take it out.

const S := 0.58 ## card scale in the grid
const COST_FILTERS := [-1, 0, 1, 2, 3, 4, 5, 6, 7]

var deck := {}
var _index := -1
var _grid: GridContainer
var _list: VBoxContainer
var _count: Label
var _problem: Label
var _name: LineEdit
var _curve: Control
var _play: Button
var _cost_filter := -1
var _set_filter := "all" ## all / class / neutral
var _show_unowned := true
var _badges := {} ## id -> Label
var _views := {} ## id -> CardView


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackdrop.new())
	_index = Game.edit_deck
	if _index >= 0 and _index < Collection.decks.size():
		deck = Collection.decks[_index].duplicate(true)
	else:
		_index = -1
		deck = {"name": "New Deck", "cls": Game.new_deck_cls, "cards": {}}

	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 30
	root.offset_right = -30
	root.offset_top = 20
	root.offset_bottom = -20
	root.add_theme_constant_override("separation", 24)
	add_child(root)

	# Left: filters and the card grid.
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 12)
	root.add_child(left)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	left.add_child(top)
	var back := UI.button("Back", 160, 60)
	back.pressed.connect(func(): Game.go(Game.DECK_SELECT))
	top.add_child(back)
	var cls_name := "Pilgrim" if deck.cls == "pilgrim" else "Ferryman"
	for f in [["all", "All"], ["class", cls_name], ["neutral", "Neutral"]]:
		var b := _small_button(f[1], 170)
		b.pressed.connect(func():
			_set_filter = f[0]
			_fill())
		top.add_child(b)
	var own := _small_button("Owned only", 200)
	own.toggle_mode = true
	own.toggled.connect(func(on: bool):
		_show_unowned = not on
		_fill())
	top.add_child(own)
	var costs := HBoxContainer.new()
	costs.add_theme_constant_override("separation", 8)
	left.add_child(costs)
	for c in COST_FILTERS:
		var b := _small_button("Any" if c == -1 else ("7+" if c == 7 else str(c)), 90 if c == -1 else 64)
		b.pressed.connect(func():
			_cost_filter = c
			_fill())
		costs.add_child(b)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 18)
	_grid.add_theme_constant_override("v_separation", 22)
	center.add_child(_grid)

	# Right: the deck.
	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(460, 0)
	right.add_theme_stylebox_override("panel", UI.box(Color(0.07, 0.035, 0.03, 0.92), UI.GOLD_DARK, 3, 16,
		Color(0, 0, 0, 0.6), 20))
	root.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	right.add_child(rv)
	_name = LineEdit.new()
	_name.text = deck.name
	_name.max_length = 24
	_name.add_theme_font_override("font", UI.font("title"))
	_name.add_theme_font_size_override("font_size", 34)
	_name.add_theme_color_override("font_color", UI.GOLD)
	_name.add_theme_stylebox_override("normal", UI.box(Color(0, 0, 0, 0.35), UI.GOLD_DARK, 2, 8))
	_name.add_theme_stylebox_override("focus", UI.box(Color(0, 0, 0, 0.5), UI.GOLD, 2, 8))
	_name.text_changed.connect(func(t: String): deck.name = t)
	rv.add_child(_name)
	var hero := CardDB.hero(Collection.CLASS_HERO[deck.cls])
	var hl := UI.label("%s  ·  %s" % [hero.get("name", ""), cls_name], 24, "italic", UI.BONE, 3, Color.BLACK)
	rv.add_child(hl)
	_curve = Control.new()
	_curve.custom_minimum_size = Vector2(0, 90)
	_curve.draw.connect(_draw_curve)
	rv.add_child(_curve)
	var ls := ScrollContainer.new()
	ls.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ls.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(ls)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	ls.add_child(_list)
	_count = UI.label("", 34, "title", UI.BONE, 5, Color.BLACK)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(_count)
	_problem = UI.label("", 20, "italic", Color(1.0, 0.6, 0.45), 3, Color.BLACK)
	_problem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_problem.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(_problem)
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 10)
	rv.add_child(r1)
	var fill := _small_button("Auto-fill", 210)
	fill.pressed.connect(func():
		Collection.autofill(deck)
		Sfx.play("swish_long", -6.0)
		_refresh())
	r1.add_child(fill)
	var clear := _small_button("Clear", 100)
	clear.pressed.connect(func():
		deck.cards.clear()
		_refresh())
	r1.add_child(clear)
	if _index >= 0:
		var del := _small_button("Delete", 120)
		del.pressed.connect(_delete)
		r1.add_child(del)
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 10)
	rv.add_child(r2)
	var save := UI.button("Save", 200, 70)
	save.pressed.connect(func():
		_save()
		Game.go(Game.DECK_SELECT))
	r2.add_child(save)
	_play = UI.button("Play", 220, 70)
	_play.pressed.connect(func():
		_save()
		Game.start_with(Collection.deck_cards(deck.cards), Collection.CLASS_HERO[deck.cls],
			"ferry" if deck.cls == "pilgrim" else "pilgrim"))
	r2.add_child(_play)

	resized.connect(_fill)
	if "--autoplay" in OS.get_cmdline_user_args():
		Collection.autofill(deck)
	_fill()


func _small_button(text: String, w: float) -> Button:
	var b := UI.button(text, w, 56)
	b.add_theme_font_size_override("font_size", 24)
	return b


func _pool() -> Array:
	var out := []
	for c in CardDB.all_cards():
		var s: String = c.get("set", "")
		if s == "token" or not Collection.fits_class(c.id, deck.cls):
			continue
		if _set_filter == "class" and s != deck.cls or _set_filter == "neutral" and s != "neutral":
			continue
		if _cost_filter >= 0 and (int(c.cost) != _cost_filter if _cost_filter < 7 else int(c.cost) < 7):
			continue
		if not _show_unowned and Collection.copies(c.id) == 0:
			continue
		out.append(c)
	out.sort_custom(func(a, b): return [int(a.set == "neutral"), a.cost, a.name] < [int(b.set == "neutral"), b.cost, b.name])
	return out


func _fill() -> void:
	for c in _grid.get_children():
		c.queue_free()
	_badges.clear()
	_views.clear()
	var w := size.x - 460 - 100
	_grid.columns = maxi(2, int(w / (CardView.W * S + 18)))
	for c in _pool():
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(CardView.W * S, CardView.H * S + 30)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		var v := CardView.new().setup(c.id, -1, true)
		v.scale = Vector2(S, S)
		v.position = Vector2(CardView.W * S / 2, CardView.H * S / 2)
		slot.add_child(v)
		var badge := UI.label("", 24, "title", UI.BONE, 5, Color.BLACK)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.size = Vector2(CardView.W * S, 30)
		badge.position = Vector2(0, CardView.H * S + 2)
		slot.add_child(badge)
		_badges[c.id] = badge
		_views[c.id] = v
		var id: String = c.id
		slot.mouse_entered.connect(func(): v.create_tween().tween_property(v, "scale", Vector2(S, S) * 1.06, 0.1))
		slot.mouse_exited.connect(func(): v.create_tween().tween_property(v, "scale", Vector2(S, S), 0.1))
		slot.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_add(id)
			elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
				_remove(id))
		_grid.add_child(slot)
	_refresh()


func _limit(id: String) -> int:
	return mini(Collection.max_copies(id), Collection.copies(id))


func _add(id: String) -> void:
	var have := int(deck.cards.get(id, 0))
	if Collection.deck_count(deck.cards) >= Collection.DECK_SIZE or have >= _limit(id):
		Sfx.play("ui_back", -8.0)
		if _views.has(id):
			var v: CardView = _views[id]
			var t := v.create_tween()
			t.tween_property(v, "rotation", 0.06, 0.05)
			t.tween_property(v, "rotation", -0.06, 0.08)
			t.tween_property(v, "rotation", 0.0, 0.05)
		return
	deck.cards[id] = have + 1
	Sfx.play("card_place", -6.0)
	_refresh()


func _remove(id: String) -> void:
	var have := int(deck.cards.get(id, 0))
	if have <= 1:
		deck.cards.erase(id)
	else:
		deck.cards[id] = have - 1
	Sfx.play("card_slide", -8.0)
	_refresh()


func _refresh() -> void:
	for id in _badges:
		var own := Collection.copies(id)
		var lim := Collection.max_copies(id)
		var used := int(deck.cards.get(id, 0))
		var b: Label = _badges[id]
		var v: CardView = _views[id]
		if own == 0:
			b.text = "Locked"
			b.add_theme_color_override("font_color", Color(0.6, 0.55, 0.5))
			v.modulate = Color(0.35, 0.33, 0.33)
		else:
			b.text = "%d / %d" % [used, mini(own, lim)]
			b.add_theme_color_override("font_color", UI.GOLD if used > 0 else UI.BONE)
			v.modulate = Color(0.6, 0.6, 0.6) if used >= mini(own, lim) else Color.WHITE
	for c in _list.get_children():
		c.queue_free()
	var ids: Array = deck.cards.keys()
	ids.sort_custom(func(a, b): return [CardDB.card(a).cost, CardDB.card(a).name] < [CardDB.card(b).cost, CardDB.card(b).name])
	for id in ids:
		var c := CardDB.card(id)
		var row := Button.new()
		row.custom_minimum_size = Vector2(0, 46)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.text = "  %d   %s%s" % [c.cost, c.name, "   x%d" % deck.cards[id] if int(deck.cards[id]) > 1 else ""]
		row.add_theme_font_override("font", UI.font("title"))
		row.add_theme_font_size_override("font_size", 22)
		var rc: Color = {"common": UI.BONE, "rare": Color(0.55, 0.75, 1.0), "epic": Color(0.85, 0.6, 1.0),
			"legendary": Color(1.0, 0.7, 0.3)}.get(c.rarity, UI.BONE)
		row.add_theme_color_override("font_color", rc)
		row.add_theme_color_override("font_hover_color", Color.WHITE)
		row.add_theme_stylebox_override("normal", UI.box(Color(0.16, 0.06, 0.05, 0.85), UI.GOLD_DARK, 1, 6))
		row.add_theme_stylebox_override("hover", UI.box(Color(0.3, 0.08, 0.05, 0.95), UI.GOLD, 2, 6))
		row.add_theme_stylebox_override("pressed", UI.box(Color(0.1, 0.03, 0.02, 0.95), UI.GOLD, 2, 6))
		row.pressed.connect(_remove.bind(id))
		_list.add_child(row)
	var n := Collection.deck_count(deck.cards)
	_count.text = "%d / %d" % [n, Collection.DECK_SIZE]
	_count.add_theme_color_override("font_color", UI.GOLD if n == Collection.DECK_SIZE else UI.BONE)
	var p := Collection.deck_problem(deck)
	_problem.text = "" if p == "" or n < Collection.DECK_SIZE else p
	_play.disabled = p != ""
	_curve.queue_redraw()


func _draw_curve() -> void:
	var counts := [0, 0, 0, 0, 0, 0, 0, 0]
	for id in deck.cards:
		counts[clampi(int(CardDB.card(id).cost), 0, 7)] += int(deck.cards[id])
	var top: int = maxi(4, counts.max())
	var w := _curve.size.x / 8.0
	var f := UI.font("title")
	for i in 8:
		var h: float = (_curve.size.y - 26) * counts[i] / float(top)
		var r := Rect2(i * w + 6, _curve.size.y - 24 - h, w - 12, h)
		_curve.draw_rect(r, UI.GOLD.darkened(0.2))
		_curve.draw_string(f, Vector2(i * w, _curve.size.y - 2), "7+" if i == 7 else str(i), HORIZONTAL_ALIGNMENT_CENTER,
			w, 20, UI.BONE)


func _save() -> void:
	if deck.name.strip_edges() == "":
		deck.name = "Unnamed Deck"
	if _index >= 0:
		Collection.decks[_index] = deck
	else:
		Collection.decks.append(deck)
		_index = Collection.decks.size() - 1
		Game.edit_deck = _index
	Collection.save()


func _delete() -> void:
	Collection.decks.remove_at(_index)
	Collection.save()
	Game.go(Game.DECK_SELECT)
