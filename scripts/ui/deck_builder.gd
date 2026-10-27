extends Control
## Deck builder: 30 cards from your class and the neutrals, max 2 copies (1 for legendaries), only cards you own.
## Click a card to add it, click a row in the list to take it out.

const S := 0.58 ## card scale in the grid
const COST_FILTERS := [-1, 0, 1, 2, 3, 4, 5, 6, 7]
const GEM := 58.0 ## the painted mana gems of the cost filter
const TAG_H := 44.0 ## the plaque under each card ("1 / 2", "Locked")
const LIT := Color(1.15, 1.05, 0.85) ## a filter that is on
const DIM := Color(0.72, 0.66, 0.6) ## a filter that is off

var deck := {}
var _index := -1
var _grid: GridContainer
var _list: VBoxContainer
var _count: Label
var _problem: Label
var _problem_plate: PanelContainer
var _name: LineEdit
var _curve: Control
var _play: Button
var _cost_filter := -1
var _set_filter := "all" ## all / class / neutral
var _show_unowned := true
var _badges := {} ## id -> Label
var _views := {} ## id -> CardView
var _set_tabs := {} ## set filter -> Button
var _cost_tabs := {} ## cost filter -> Button
var _own_tab: Button
var _hover_tips: Control ## keyword tips beside the card under the pointer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackdrop.new())
	Sfx.play_ambience("") # menus play the music alone (an ambience loop would leak in from the battle)
	_index = Game.edit_deck
	if _index >= 0 and _index < Collection.decks.size():
		deck = Collection.decks[_index].duplicate(true)
	else:
		_index = -1
		var cls_title := CardDB.class_title(Game.new_deck_cls)
		var mine := Collection.decks.filter(func(d): return d.cls == Game.new_deck_cls).size()
		deck = {"name": "%s Deck %d" % [cls_title, mine + 1], "cls": Game.new_deck_cls, "cards": {}}

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
	var back := UI.button("Back", 170, 60)
	back.pressed.connect(func(): Game.go(Game.DECK_SELECT))
	top.add_child(back)
	var cls_name := CardDB.class_title(deck.cls)
	for f in [["all", "All"], ["class", cls_name], ["neutral", "Neutral"]]:
		var b := _small_button(f[1], 190)
		b.pressed.connect(func():
			_set_filter = f[0]
			_fill())
		top.add_child(b)
		_set_tabs[f[0]] = b
	_own_tab = _small_button("Owned only", 250)
	_own_tab.toggle_mode = true
	_own_tab.toggled.connect(func(on: bool):
		_show_unowned = not on
		_fill())
	top.add_child(_own_tab)
	# The cost filter: a plate for "any cost", then the painted mana gems of the card frames, the chosen one lit.
	var costs := HBoxContainer.new()
	costs.add_theme_constant_override("separation", 10)
	left.add_child(costs)
	for c in COST_FILTERS:
		var b := _small_button("Any cost", 190) if c == -1 else _gem_button("7+" if c == 7 else str(c))
		b.pressed.connect(func():
			_cost_filter = c
			_fill())
		costs.add_child(b)
		_cost_tabs[c] = b
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.paint_scroll(scroll)
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
	right.custom_minimum_size = Vector2(540, 0)
	# The content stays on the panel's dark field, clear of the frame's carved border.
	var rs := UI.frame_box("panel_frame_filled", 96, 0,
		UI.box(Color(0.07, 0.035, 0.03, 0.92), UI.GOLD_DARK, 3, 16, Color(0, 0, 0, 0.6), 20))
	rs.content_margin_left = 44
	rs.content_margin_right = 44
	rs.content_margin_top = 52
	rs.content_margin_bottom = 56
	right.add_theme_stylebox_override("panel", rs)
	root.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	right.add_child(rv)
	# The deck's name: a framed inscription field with a Rename plate beside it, so it reads as editable.
	var nr := HBoxContainer.new()
	nr.add_theme_constant_override("separation", 8)
	rv.add_child(nr)
	_name = LineEdit.new()
	_name.text = deck.name
	_name.placeholder_text = "Name your deck"
	_name.max_length = 24
	_name.select_all_on_focus = true
	_name.caret_blink = true
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.add_theme_font_override("font", UI.font("title"))
	_name.add_theme_font_size_override("font_size", 26)
	_name.add_theme_color_override("font_color", UI.GOLD)
	_name.add_theme_color_override("font_placeholder_color", UI.BONE.darkened(0.45))
	_name.add_theme_color_override("caret_color", UI.GOLD)
	_name.add_theme_color_override("selection_color", Color(0.55, 0.32, 0.08, 0.75))
	_name.add_theme_color_override("font_selected_color", Color(1.0, 0.95, 0.8))
	# An engraved name plate: the bronze frame around the painted field, lit while it is being edited.
	_name.add_theme_stylebox_override("normal", UI.plaque_box(18, 8))
	_name.add_theme_stylebox_override("focus", UI.plaque_box(18, 8, Color(1.45, 1.25, 0.9)))
	_name.custom_minimum_size = Vector2(0, 60)
	UI.add_field(_name)
	_name.text_changed.connect(func(t: String): deck.name = t)
	_name.text_submitted.connect(func(_t: String): _name.release_focus())
	nr.add_child(_name)
	var ren := _small_button("Rename", 196)
	ren.pressed.connect(func():
		_name.grab_focus()
		_name.select_all())
	nr.add_child(ren)
	var hero := CardDB.hero(CardDB.class_hero(deck.cls))
	# Hero line with the card count on its right, so the count never crowds the bottom of the deck list.
	# Both engraved on a plaque like the name's.
	var hp := UI.plaque(18, 4)
	rv.add_child(hp)
	var hr := HBoxContainer.new()
	hr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp.add_child(hr)
	var hl := UI.label("%s  ·  %s" % [hero.get("name", ""), cls_name], 24, "italic", UI.BONE, 3, Color.BLACK)
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hr.add_child(hl)
	_count = UI.label("", 32, "title", UI.BONE, 5, Color.BLACK)
	hr.add_child(_count)
	# The mana curve on a plaque: bronze rods standing on the mana gems of each cost.
	var cp := UI.plaque(18, 10)
	rv.add_child(cp)
	_curve = Control.new()
	_curve.custom_minimum_size = Vector2(0, 132)
	_curve.draw.connect(_draw_curve)
	cp.add_child(_curve)
	var ls := ScrollContainer.new()
	ls.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ls.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.paint_scroll(ls, 22)
	rv.add_child(ls)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	ls.add_child(_list)
	# Why the deck cannot be played yet, on a plaque shown only while there is a reason.
	_problem_plate = UI.plaque(18, 4)
	_problem_plate.visible = false
	rv.add_child(_problem_plate)
	_problem = UI.label("", 20, "italic", Color(1.0, 0.6, 0.45), 3, Color.BLACK)
	_problem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_problem.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_problem.custom_minimum_size = Vector2(400, 0)
	_problem_plate.add_child(_problem)
	var r1 := HBoxContainer.new()
	r1.alignment = BoxContainer.ALIGNMENT_CENTER
	r1.add_theme_constant_override("separation", 6)
	rv.add_child(r1)
	var fill := _small_button("Auto-fill", 170 if _index >= 0 else 220)
	fill.pressed.connect(func():
		Collection.autofill(deck)
		Sfx.play("swish_long", -6.0)
		_refresh())
	r1.add_child(fill)
	var clear := _small_button("Clear", 135 if _index >= 0 else 170)
	clear.pressed.connect(func():
		deck.cards.clear()
		_refresh())
	r1.add_child(clear)
	if _index >= 0:
		var del := _small_button("Delete", 135)
		del.pressed.connect(_delete)
		r1.add_child(del)
	var r2 := HBoxContainer.new()
	r2.alignment = BoxContainer.ALIGNMENT_CENTER
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
		Game.start_with(Collection.deck_cards(deck.cards), CardDB.class_hero(deck.cls)))
	r2.add_child(_play)

	resized.connect(_fill)
	if "--autoplay" in OS.get_cmdline_user_args():
		Collection.autofill(deck)
	_fill()
	if _index < 0:
		_name.call_deferred("grab_focus") # a new deck starts by naming it (the text is selected: typing replaces it)


func _small_button(text: String, w: float) -> Button:
	var b := UI.button(text, w, 56)
	b.add_theme_font_size_override("font_size", 24)
	return b


## A cost filter: the painted mana gem with its number raised on it, like the cost on a card.
func _gem_button(text: String) -> Button:
	var b := Button.new()
	# "7+": Cinzel's "+" is a hairline cross that vanished under the dark rim on a small window, so the digit is
	# set a little left and the "+" is drawn as a bold cross beside it (_draw_plus).
	var plus := text.ends_with("+")
	b.text = text.trim_suffix("+")
	b.custom_minimum_size = Vector2(GEM, GEM)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", UI.font("title"))
	b.add_theme_font_size_override("font_size", 28)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, UI.NUMBER)
	b.add_theme_constant_override("outline_size", 7)
	b.add_theme_color_override("font_outline_color", Color(0, 0.02, 0.08))
	if plus:
		var mark := Control.new()
		mark.size = Vector2(GEM, GEM)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.draw.connect(func(): _draw_plus(mark, Vector2(GEM / 2 + 10, GEM / 2), 6.0, 3.0, 2.0))
		b.add_child(mark)
	var fallback := UI.box(Color(0.1, 0.16, 0.32), Color(0.5, 0.65, 0.95), 2, int(GEM / 2))
	for st in [["normal", Color.WHITE], ["hover", Color(1.25, 1.2, 1.1)], ["pressed", Color(0.8, 0.8, 0.85)]]:
		var sb := UI.frame_box("gem_mana", 0, 0, fallback, st[1])
		sb.content_margin_top = 4 # Cinzel's digits sit high in the line box
		if plus:
			sb.content_margin_right = 14 # the digit sits left, the drawn "+" right
		b.add_theme_stylebox_override(st[0], sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pivot_offset = b.custom_minimum_size / 2
	b.mouse_entered.connect(func():
		Sfx.play("ui_hover", -12.0)
		b.create_tween().tween_property(b, "scale", Vector2.ONE * 1.08, 0.08))
	b.mouse_exited.connect(func(): b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.08))
	b.pressed.connect(func(): Sfx.play("ui_confirm", -8.0))
	return b


## Lights the filters that are on and dims the others.
func _mark_filters() -> void:
	for f in _set_tabs:
		(_set_tabs[f] as Button).modulate = LIT if f == _set_filter else DIM
	for c in _cost_tabs:
		(_cost_tabs[c] as Button).modulate = LIT if c == _cost_filter else (DIM if c == -1 else Color(0.62, 0.62, 0.68))
	_own_tab.modulate = DIM if _show_unowned else LIT


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
	_mark_filters()
	for c in _grid.get_children():
		c.queue_free()
	_badges.clear()
	_views.clear()
	_hide_tips()
	var w := size.x - 480 - 100
	_grid.columns = maxi(2, int(w / (CardView.W * S + 18)))
	for c in _pool():
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(CardView.W * S, CardView.H * S + TAG_H + 4)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		var v := CardView.new().setup(c.id, -1, true)
		v.scale = Vector2(S, S)
		v.position = Vector2(CardView.W * S / 2, CardView.H * S / 2)
		slot.add_child(v)
		# The copies in the deck (or Locked) engraved on a small plaque under the card.
		var holder := CenterContainer.new()
		holder.size = Vector2(CardView.W * S, TAG_H)
		holder.position = Vector2(0, CardView.H * S + 4)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tag := UI.plaque_label("", 22, "title", UI.BONE, 0.0, 16, 4)
		tag.custom_minimum_size = Vector2(124, 0)
		holder.add_child(tag)
		slot.add_child(holder)
		_badges[c.id] = tag.get_node("Text")
		_views[c.id] = v
		var id: String = c.id
		slot.mouse_entered.connect(func():
			v.create_tween().tween_property(v, "scale", Vector2(S, S) * 1.06, 0.1)
			_show_tips(id, slot))
		slot.mouse_exited.connect(func():
			v.create_tween().tween_property(v, "scale", Vector2(S, S), 0.1)
			_hide_tips())
		slot.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_add(id)
			elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
				_remove(id))
		_grid.add_child(slot)
	_refresh()


## The keyword tips of the card under the pointer, beside its slot (right of it, or left near the screen edge).
func _show_tips(id: String, slot: Control) -> void:
	_hide_tips()
	var col := UI.tip_column(CardDB.card(id))
	if col == null:
		return
	col.top_level = true
	col.z_index = 50
	add_child(col)
	_hover_tips = col
	var r := slot.get_global_rect()
	var vs := get_viewport_rect().size
	var w := col.get_combined_minimum_size().x
	var x := r.end.x + 10.0 if r.end.x + 10.0 + w < vs.x - 16.0 else r.position.x - 10.0 - w
	col.position = Vector2(x, r.position.y)
	await get_tree().process_frame
	if is_instance_valid(col): # laid out now: keep the whole column on screen
		col.position.y = clampf(r.position.y, 16.0, maxf(16.0, vs.y - col.size.y - 16.0))


func _hide_tips() -> void:
	if _hover_tips != null and is_instance_valid(_hover_tips):
		_hover_tips.queue_free()
	_hover_tips = null


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
		row.text = "%s%s" % [c.name, "   x%d" % deck.cards[id] if int(deck.cards[id]) > 1 else ""]
		row.add_theme_font_override("font", UI.font("title"))
		row.add_theme_font_size_override("font_size", 22)
		var rc: Color = {"common": UI.BONE, "rare": Color(0.55, 0.75, 1.0), "epic": Color(0.85, 0.6, 1.0),
			"legendary": Color(1.0, 0.7, 0.3)}.get(c.rarity, UI.BONE)
		row.add_theme_color_override("font_color", rc)
		row.add_theme_color_override("font_hover_color", Color.WHITE)
		row.add_theme_constant_override("outline_size", 4)
		row.add_theme_color_override("font_outline_color", Color(0.04, 0.01, 0.01))
		for st in [["normal", UI.box(Color(0.16, 0.06, 0.05, 0.85), UI.GOLD_DARK, 1, 6), Color.WHITE],
				["hover", UI.box(Color(0.3, 0.08, 0.05, 0.95), UI.GOLD, 2, 6), Color(1.4, 1.2, 0.9)],
				["pressed", UI.box(Color(0.1, 0.03, 0.02, 0.95), UI.GOLD, 2, 6), Color(0.8, 0.7, 0.6)]]:
			var sb := UI.frame_box("deck_row", 10, 8, st[1], st[2])
			sb.content_margin_left = 56 # room for the cost gem
			row.add_theme_stylebox_override(st[0], sb)
		# The cost on a painted mana gem at the left end of the tile.
		var gem := Control.new()
		gem.position = Vector2(10, 4)
		gem.size = Vector2(38, 38)
		gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if UiSkin.has("gem_mana"):
			gem.add_child(UiSkin.rect("gem_mana", gem.size))
		var cost := UI.raised(UI.label(str(int(c.cost)), 20, "title", UI.NUMBER, 5, Color(0, 0.02, 0.08)))
		cost.size = gem.size
		cost.position = Vector2(0, 0.0625 * 20)
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		gem.add_child(cost)
		row.add_child(gem)
		if UiSkin.has("deck_row"):
			# Hearthstone-style tile: a strip of the card's painting behind the name, darkened on the left for the text.
			var strip := TextureRect.new()
			strip.texture = CardDB.art_framed(id, 4.5, 0.4)
			strip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			strip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			strip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			strip.offset_left = 4
			strip.offset_right = -4
			strip.offset_top = 4
			strip.offset_bottom = -4
			strip.modulate = Color(0.55, 0.5, 0.48)
			strip.show_behind_parent = true
			strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(strip)
		row.pressed.connect(_remove.bind(id))
		_list.add_child(row)
	var n := Collection.deck_count(deck.cards)
	_count.text = "%d / %d" % [n, Collection.DECK_SIZE]
	_count.add_theme_color_override("font_color", UI.GOLD if n == Collection.DECK_SIZE else UI.BONE)
	var p := Collection.deck_problem(deck)
	_problem.text = "" if p == "" or n < Collection.DECK_SIZE else p
	_problem_plate.visible = _problem.text != ""
	_play.disabled = p != ""
	_curve.queue_redraw()


## The mana curve: for each cost a bronze rod as tall as the copies at that cost (the count engraved above it),
## standing on the mana gem of that cost.
func _draw_curve() -> void:
	var counts := [0, 0, 0, 0, 0, 0, 0, 0]
	for id in deck.cards:
		counts[clampi(int(CardDB.card(id).cost), 0, 7)] += int(deck.cards[id])
	var top: int = maxi(4, counts.max())
	var w := _curve.size.x / 8.0
	var f := UI.font("title")
	var gem := 36.0
	var base := _curve.size.y - gem ## the rods stand on the gems
	var tall := base - 24.0 ## room left for the count above the tallest rod
	# The bars are strips of the gilded button plate turned upright: its gold field between the bronze rims.
	var rod: Texture2D = UI.upright_tex("menu_plate", 22) if UiSkin.has("menu_plate") else null
	for i in 8:
		var cx := i * w + w / 2
		if counts[i] > 0:
			var h: float = maxf(10.0, tall * counts[i] / float(top))
			var r := Rect2(cx - 11, base - h + 2, 22, h)
			if rod != null:
				var src := Rect2(0, 24, 22, rod.get_height() - 48) # the plain middle, without the scrollwork ends
				_curve.draw_texture_rect_region(rod, r, src)
				_curve.draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Color(1.0, 0.85, 0.5, 0.8)) # the cut top edge
			else:
				_curve.draw_rect(r, UI.GOLD.darkened(0.2))
			var at := Vector2(cx - w / 2, r.position.y - 5)
			_curve.draw_string_outline(f, at, str(counts[i]), HORIZONTAL_ALIGNMENT_CENTER, w, 19, 4, Color(0.04, 0.01, 0.01))
			_curve.draw_string(f, at, str(counts[i]), HORIZONTAL_ALIGNMENT_CENTER, w, 19, UI.BONE)
		var g := Rect2(cx - gem / 2, base, gem, gem)
		if UiSkin.has("gem_mana"):
			_curve.draw_texture_rect(UiSkin.tex("gem_mana"), g, false,
				Color.WHITE if counts[i] > 0 else Color(0.55, 0.55, 0.62))
		# The last gem is "7+": the digit a little left and a bold drawn "+" (Cinzel's own is a hairline).
		var fs := 19
		var at := Vector2(g.position.x - (4.0 if i == 7 else 0.0), g.get_center().y + fs * 0.36)
		_curve.draw_string_outline(f, at, str(i), HORIZONTAL_ALIGNMENT_CENTER, gem, fs, 5, Color(0, 0.02, 0.08))
		_curve.draw_string(f, at, str(i), HORIZONTAL_ALIGNMENT_CENTER, gem, fs, UI.NUMBER)
		if i == 7:
			_draw_plus(_curve, g.get_center() + Vector2(7, 0), 4.0, 2.0, 1.5)


## A bold "+" centred at `c` (arms `arm` px from the centre, `thick` px wide) in the gem digits' colour, ringed in
## their dark outline: Cinzel's own "+" is too thin to read on a small gem.
static func _draw_plus(ci: CanvasItem, c: Vector2, arm: float, thick: float, rim: float) -> void:
	for pass_ in [[rim, Color(0, 0.02, 0.08)], [0.0, UI.NUMBER]]:
		var o: float = pass_[0]
		ci.draw_rect(Rect2(c.x - arm - o, c.y - thick / 2 - o, 2 * (arm + o), thick + 2 * o), pass_[1])
		ci.draw_rect(Rect2(c.x - thick / 2 - o, c.y - arm - o, thick + 2 * o, 2 * (arm + o)), pass_[1])


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
