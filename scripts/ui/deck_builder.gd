extends Control
## Deck builder: 30 cards from your class and the neutrals, max 2 copies (1 for legendaries), only cards you own.
## Click a card to add it, click a row in the list to take it out.

const S := 0.58 ## card scale in the grid
const COST_FILTERS := [-1, 0, 1, 2, 3, 4, 5, 6, 7]
const GEM := 58.0 ## the painted mana gems of the cost filter
const TAG_H := 44.0 ## the plaque under each card ("1 / 2", "Locked")
const SIDE_W := 540.0 ## the deck panel on the right
const SIDE_PAD := 44.0 ## its content's margin left and right, inside the carved frame
const FIELD_PAD := 26.0 ## the text's inset in the name field and the hero plaque (clear of their bronze frames)
const TAB_W := 190.0 ## Back, the set filters and "Any cost": one width, so the two filter rows share their columns
const ROW_GAP := 12.0 ## between the plates of a row
const CARD_GAP := 14.0 ## the least gap between the cards of the grid (the grid is spread to fill its width)
const BAR_W := 26.0 ## the painted scroll bar beside the grid
const LIT := Color(1.15, 1.05, 0.85) ## a filter that is on
const DIM := Color(0.72, 0.66, 0.6) ## a filter that is off

var deck := {}
var _index := -1
var _grid: GridContainer
var _grid_scroll: ScrollContainer
var _right: Control
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
var _saved := {} ## the deck as it was saved (or as a new deck started): leaving asks first when `deck` differs


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
	top.add_theme_constant_override("separation", int(ROW_GAP))
	left.add_child(top)
	_saved = deck.duplicate(true)
	var back := UI.button("Back", TAB_W, 60)
	back.pressed.connect(_leave)
	top.add_child(back)
	var cls_name := CardDB.class_title(deck.cls)
	for f in [["all", "All"], ["class", cls_name], ["neutral", "Neutral"]]:
		var b := _small_button(f[1], TAB_W)
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
	# The cost filter: a plate for "any cost" (under Back, as wide), then the painted mana gems of the card frames, the
	# chosen one lit; the first gem starts where "All" does above it.
	var costs := HBoxContainer.new()
	costs.add_theme_constant_override("separation", int(ROW_GAP))
	left.add_child(costs)
	for c in COST_FILTERS:
		var b := _small_button("Any cost", TAB_W) if c == -1 else _gem_button("7+" if c == 7 else str(c))
		b.pressed.connect(func():
			_cost_filter = c
			_fill())
		costs.add_child(b)
		_cost_tabs[c] = b
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.paint_scroll(scroll, int(BAR_W))
	left.add_child(scroll)
	_grid_scroll = scroll
	# The grid starts at the filters' left edge and is spread to end at the scroll bar (_fill sets its gap).
	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_grid.add_theme_constant_override("h_separation", int(CARD_GAP))
	_grid.add_theme_constant_override("v_separation", 22)
	scroll.add_child(_grid)

	# Right: the deck.
	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(SIDE_W, 0)
	_right = right
	# The content stays on the panel's dark field, clear of the frame's carved border.
	var rs := UI.frame_box("panel_frame_filled", 96, 0,
		UI.box(Color(0.07, 0.035, 0.03, 0.92), UI.GOLD_DARK, 3, 16, Color(0, 0, 0, 0.6), 20))
	rs.content_margin_left = SIDE_PAD
	rs.content_margin_right = SIDE_PAD
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
	# An engraved name plate (UI.name_field): the bronze frame around the painted field, lit while it is being edited.
	_name = UI.name_field(deck.name, "Name your deck", 24)
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The letters further in than the shared field's 18 px: a long name ran right up to the bronze frame.
	for st in ["normal", "focus"]:
		var fs := _name.get_theme_stylebox(st)
		fs.content_margin_left = FIELD_PAD
		fs.content_margin_right = FIELD_PAD
	_name.text_changed.connect(func(t: String):
		deck.name = t
		_fit_name())
	_name.resized.connect(_fit_name)
	_name.text_submitted.connect(func(_t: String): _name.release_focus())
	nr.add_child(_name)
	# Rename: a bronze disc with an engraved pen nib (the Rename plate took almost half the row, and a long name
	# shrank to 16 px and still ran under the frame).
	var ren := _disc("Rename the deck", _draw_nib, "icon_rename")
	ren.pressed.connect(func():
		_name.grab_focus()
		_name.select_all())
	nr.add_child(ren)
	var hero := CardDB.hero(CardDB.class_hero(deck.cls))
	# Hero line with the card count on its right, so the count never crowds the bottom of the deck list.
	# Both engraved on a plaque like the name's.
	var hp := UI.plaque(FIELD_PAD, 4) # the hero's name starts under the deck's name
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
	# Why the deck cannot be played yet, inked in red on a parchment sheet shown only while there is a reason.
	_problem_plate = PanelContainer.new()
	_problem_plate.add_theme_stylebox_override("panel", UI.parchment_box(26, 12))
	_problem_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_problem_plate.visible = false
	rv.add_child(_problem_plate)
	_problem = UI.label("", 21, "italic", UI.INK_RED)
	_problem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_problem.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_problem.custom_minimum_size = Vector2(400, 0)
	_problem_plate.add_child(_problem)
	UI.center_ink(_problem) # on the sheet's middle
	# The two rows of plates span the panel's width, edge to edge: Auto-fill starts where Save does and the last plate
	# (Clear, or the Delete disc) ends where Play does.
	var row_w := SIDE_W - 2.0 * SIDE_PAD
	var half := floorf((row_w - ROW_GAP) / 2.0)
	var r1 := HBoxContainer.new()
	r1.alignment = BoxContainer.ALIGNMENT_CENTER
	r1.add_theme_constant_override("separation", int(ROW_GAP))
	rv.add_child(r1)
	var small := half if _index < 0 else floorf((row_w - 60.0 - 2.0 * ROW_GAP) / 2.0) # beside the 60 px Delete disc
	var fill := _small_button("Auto-fill", small)
	fill.pressed.connect(func():
		Collection.autofill(deck)
		Sfx.play("swish_long", -6.0)
		_refresh())
	r1.add_child(fill)
	var clear := _small_button("Clear", row_w - small - ROW_GAP if _index < 0 else small)
	clear.pressed.connect(func():
		deck.cards.clear()
		_refresh())
	r1.add_child(clear)
	UI.even_text([fill, clear]) # one letter size on the row (Auto-fill shrinks on its narrower plate beside Delete)
	if _index >= 0:
		# Delete on a bronze disc with an engraved cross (as a third plate the row left each label about 56 px).
		var del := _disc("Delete this deck", _draw_cross, "icon_delete")
		del.pressed.connect(_delete)
		r1.add_child(del)
	var r2 := HBoxContainer.new()
	r2.alignment = BoxContainer.ALIGNMENT_CENTER
	r2.add_theme_constant_override("separation", int(ROW_GAP))
	rv.add_child(r2)
	var save := UI.button("Save", half, 70)
	save.pressed.connect(func():
		_save()
		Game.go(Game.DECK_SELECT))
	r2.add_child(save)
	_play = UI.button("Play", row_w - half - ROW_GAP, 70)
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


## Shrinks the name's letters (26 down to 16 px) so the whole name stays on its plate: a long name never runs under
## the bronze frame or scrolls half out of sight.
func _fit_name() -> void:
	var sb := _name.get_theme_stylebox("normal")
	var room := _name.size.x - sb.get_margin(SIDE_LEFT) - sb.get_margin(SIDE_RIGHT) - 8.0
	if room <= 0.0:
		return
	var f := _name.get_theme_font("font")
	var px := 26
	while px > 16 and f.get_string_size(_name.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > room:
		px -= 1
	_name.add_theme_font_size_override("font_size", px)


## Back (and Esc / the back gesture): straight to Choose your path when nothing changed, else asks whether to save.
func _leave() -> void:
	if deck.recursive_equal(_saved, 4):
		Game.go(Game.DECK_SELECT)
		return
	var shown: String = deck.name.strip_edges() if deck.name.strip_edges() != "" else "this deck"
	UI.dialog(self, "Leave without saving?", "Your changes to %s are not saved yet." % shown, [
		["Save", func():
			_save()
			Game.go(Game.DECK_SELECT)],
		["Discard", func(): Game.go(Game.DECK_SELECT)],
		["Keep editing", null]])


## Esc / the back gesture (Game.back): ends the naming first, then like Back.
func go_back() -> void:
	if _name.has_focus():
		_name.release_focus()
		return
	_leave()


## A round button: the painted bronze disc with `icon` (or a glyph drawn by `glyph`) engraved on it (UI.disc).
func _disc(tip: String, glyph: Callable, icon: String = "") -> Button:
	return UI.disc(tip, glyph, icon)


## A pen nib engraved at `c`, its point down-left: dark ink with a thin light edge below (like the discs' arrows).
static func _draw_nib(ci: CanvasItem, c: Vector2) -> void:
	var xf := Transform2D(PI / 4, Vector2(1.15, 1.15), 0.0, c + Vector2(2, -2))
	var body := PackedVector2Array([Vector2(-7, -14), Vector2(7, -14), Vector2(9, -3), Vector2(0, 15), Vector2(-9, -3)])
	for pass_ in [[Vector2(0, 2), Color(1.0, 0.9, 0.62, 0.35)], [Vector2.ZERO, Color(0.22, 0.09, 0.03)]]:
		var off: Vector2 = pass_[0]
		var pts := PackedVector2Array()
		for p in body:
			pts.append(xf * p + off)
		ci.draw_colored_polygon(pts, pass_[1])
		pts.append(pts[0])
		ci.draw_polyline(pts, pass_[1], 1.0, true) # polygons are not antialiased: a smooth edge around it
	# The slit and the breather hole, cut through the nib in the disc's bronze.
	var bronze := Color(0.75, 0.55, 0.3)
	ci.draw_line(xf * Vector2(0, 14), xf * Vector2(0, -1), bronze, 1.4, true)
	ci.draw_circle(xf * Vector2(0, -3), 2.2, bronze)
	# The stroke it has just written, under the point.
	ci.draw_line(c + Vector2(-13, 16), c + Vector2(4, 16), Color(0.22, 0.09, 0.03), 2.0, true)


## A cross engraved at `c` (Delete): two tapered strokes of dark ink with a thin light edge below.
static func _draw_cross(ci: CanvasItem, c: Vector2) -> void:
	for pass_ in [[Vector2(0, 2), Color(1.0, 0.9, 0.62, 0.35)], [Vector2.ZERO, Color(0.22, 0.09, 0.03)]]:
		for d in [Vector2(1, 1), Vector2(1, -1)]:
			var a: Vector2 = c - d * 11.0 + pass_[0]
			var b: Vector2 = c + d * 11.0 + pass_[0]
			var n := Vector2(-d.y, d.x).normalized()
			var pts := PackedVector2Array([a, a.lerp(b, 0.5) + n * 3.2, b, a.lerp(b, 0.5) - n * 3.2])
			ci.draw_colored_polygon(pts, pass_[1])
			pts.append(a)
			ci.draw_polyline(pts, pass_[1], 1.0, true)


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
		if plus:
			sb.content_margin_right = 14 # the digit sits left, the drawn "+" right
		b.add_theme_stylebox_override(st[0], sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	UI.center_ink(b) # the digit's ink on the gem's middle (left of the drawn "+" on "7+")
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
	# The grid's width: the scroll's, less its bar (estimated from the screen before the first layout).
	var w := _grid_scroll.size.x - BAR_W
	if _grid_scroll.size.x <= 0.0:
		w = size.x - 60.0 - 24.0 - maxf(SIDE_W, _right.get_combined_minimum_size().x) - BAR_W
	var cw := CardView.W * S
	var cols := maxi(2, int((w + CARD_GAP) / (cw + CARD_GAP)))
	_grid.columns = cols
	# The columns spread so the grid ends at the bar as it starts at the filters (within reason).
	var gap := clampf(floorf((w - cols * cw) / (cols - 1)), CARD_GAP, 2.0 * CARD_GAP)
	_grid.add_theme_constant_override("h_separation", int(gap))
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
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		UI.center_ink(cost) # the digit's ink on the gem's middle
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
	if ids.is_empty():
		_list.add_child(_empty_hint())
	var n := Collection.deck_count(deck.cards)
	_count.text = "%d / %d" % [n, Collection.DECK_SIZE]
	_count.add_theme_color_override("font_color", UI.GOLD if n == Collection.DECK_SIZE else UI.BONE)
	var p := Collection.deck_problem(deck)
	_problem.text = "" if p == "" or n < Collection.DECK_SIZE else p
	_problem_plate.visible = _problem.text != ""
	_play.disabled = p != ""
	_curve.queue_redraw()


## An empty deck's list: how to fill it, engraved on a plaque (instead of a bare dark well).
func _empty_hint() -> Control:
	var p := PanelContainer.new() # the hint inked on a parchment sheet
	p.add_theme_stylebox_override("panel", UI.parchment_box(30, 18))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var t := UI.label("Your deck is empty", 26, "title", UI.INK_RED)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var tap := UI.tap_word()
	var how := UI.label("%s a card on the left to add it, or let Auto-fill choose. %s a card in this list to take it out."
		% [tap, tap], 21, "italic", UI.INK)
	how.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.custom_minimum_size = Vector2(360, 0)
	v.add_child(how)
	return p


## The mana curve (ManaCurve.paint): a bronze rod per cost on its mana gem, the copies engraved above it.
func _draw_curve() -> void:
	ManaCurve.paint(_curve, _curve.size, ManaCurve.counts_of(deck.cards), 36.0)


## A bold "+" (see ManaCurve.draw_plus).
static func _draw_plus(ci: CanvasItem, c: Vector2, arm: float, thick: float, rim: float) -> void:
	ManaCurve.draw_plus(ci, c, arm, thick, rim)


func _save() -> void:
	if deck.name.strip_edges() == "":
		deck.name = "Unnamed Deck"
	Collection.stamp_deck(deck, Collection.decks[_index] if _index >= 0 and _index < Collection.decks.size() else {})
	if _index >= 0:
		Collection.decks[_index] = deck
	else:
		Collection.decks.append(deck)
		_index = Collection.decks.size() - 1
		Game.edit_deck = _index
	Collection.save()
	_saved = deck.duplicate(true)
	# Choose your path opens on the deck just saved (its library on a filter that shows it).
	Settings.deck_choice["selected"] = "own:%d" % _index
	if str(Settings.deck_choice.get("filter", "all")) not in ["all", deck.cls]:
		Settings.deck_choice["filter"] = deck.cls
	if not Game.debug_run(): # snapshots and tests never touch the player's settings
		Settings.save()


## Delete asks first: a deck is gone for good.
func _delete() -> void:
	var shown: String = deck.name.strip_edges() if deck.name.strip_edges() != "" else "This deck"
	UI.dialog(self, "Delete this deck?", "%s will be gone for good. Its cards stay in your collection." % shown, [
		["Delete", _delete_now],
		["Keep it", null]])


func _delete_now() -> void:
	Collection.delete_deck(_index)
	Collection.save()
	# The player's decks after it move up one place: keep Choose your path on the same deck (or the first one).
	var sel := str(Settings.deck_choice.get("selected", ""))
	if sel.begins_with("own:"):
		var i := int(sel.substr(4))
		Settings.deck_choice["selected"] = "" if i == _index else "own:%d" % (i - 1) if i > _index else sel
		if not Game.debug_run():
			Settings.save()
	Game.go(Game.DECK_SELECT)
