extends Control
## Choose your path: pick a deck from the library on the right (preconstructed decks and the player's own, filtered
## by class), see it in the showcase on the left (hero, name, plan, featured cards), then Play. The opponent plays a
## random preconstructed deck of the other class.
##
## Every piece is painted: bronze frames, the red name ribbon, framed plaques, bronze discs, engraved plates; every
## text is fitted to the room inside its frame. The library scrolls, so any number of decks fits.

const SHOW_W := 640.0 ## the showcase panel
const LIB_COLS := 2
const TILE := Vector2(380, 96)
const TILE_GAP := 14.0
const FRAME_PAD := 64.0 ## room the bronze frame's ornament takes on each side of a big panel
const ARROW_SIZE := 62.0
const FILTERS := [["all", "All decks"], ["pilgrim", "Pilgrim"], ["ferry", "Ferryman"]]
const CARD_FX := preload("res://assets/shaders/card_fx.gdshader")

var _entries: Array = [] ## every deck the library can show (see _all_entries)
var _selected := "" ## key of the deck in the showcase
var _filter := "all"
var _grid: GridContainer
var _scroll: ScrollContainer
var _tabs := {}
var _scroll_btns: Array = []
# Showcase parts, refilled by _show().
var _portrait: Control
var _hero: HeroView
var _name: Label
var _who: Label
var _txt: Label
var _cards: Control
var _play: Button
var _edit_btn: Button


func _ready() -> void:
	Sfx.play_ambience("") # menus play the music alone (an ambience loop would leak in from the battle)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackdrop.new())
	_entries = _all_entries()
	_filter = str(Settings.deck_choice.get("filter", "all"))
	_selected = str(Settings.deck_choice.get("selected", ""))
	if _find(_selected).is_empty():
		_selected = str(_entries[0].key) if not _entries.is_empty() else ""
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	var title := UI.label("Choose your path", 58, "title", UI.GOLD, 10, Color.BLACK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	root.add_child(_header())
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 36)
	row.custom_minimum_size = Vector2(0, _row_height())
	root.add_child(row)
	row.add_child(_showcase())
	row.add_child(_library())
	var back := UI.button("Back", 280, 62)
	back.pressed.connect(func(): Game.go(Game.MENU))
	var bc := CenterContainer.new()
	bc.add_child(back)
	root.add_child(bc)
	_refill()
	_show(_find(_selected), 0)


## Height of the showcase / library row: what the screen leaves under the title and header and above Back.
func _row_height() -> float:
	return minf(800.0, get_viewport_rect().size.y - 270.0)


# --- Decks -------------------------------------------------------------------------------------------------------

## Every deck as one shape: preconstructed ones first (by class, in file order), then the player's own.
func _all_entries() -> Array:
	var out := []
	for cls in ["pilgrim", "ferry"]:
		for d in CardDB.class_decks(cls):
			out.append({"key": "pre:" + str(d.id), "own": false, "id": str(d.id), "cls": cls, "name": str(d.name),
				"hero": str(d.hero), "text": str(d.get("text", "")), "featured": d.get("featured", []), "problem": ""})
	for i in Collection.decks.size():
		var d: Dictionary = Collection.decks[i]
		out.append({"key": "own:%d" % i, "own": true, "index": i, "cls": str(d.cls), "name": str(d.name),
			"hero": Collection.CLASS_HERO[d.cls], "text": _own_text(d), "featured": _own_featured(d),
			"problem": Collection.deck_problem(d)})
	return out


func _find(key: String) -> Dictionary:
	for e in _entries:
		if e.key == key:
			return e
	return {}


## A line about a deck the player built: its minions and spells, and average cost.
func _own_text(d: Dictionary) -> String:
	var n := Collection.deck_count(d.cards)
	if n == 0:
		return "An empty deck. Open it in the editor to fill it."
	var spells := 0
	var cost := 0
	for id in d.cards:
		var c := CardDB.card(id)
		var k := int(d.cards[id])
		cost += int(c.get("cost", 0)) * k
		if c.get("type", "minion") == "spell":
			spells += k
	return "Your own deck: %d minions and %d spells, average cost %.1f." % [n - spells, spells, float(cost) / n]


## The three showpiece cards of a deck the player built: the rarest, then the most expensive.
func _own_featured(d: Dictionary) -> Array:
	var rank := {"legendary": 3, "epic": 2, "rare": 1}
	var ids: Array = d.cards.keys()
	ids.sort_custom(func(a, b):
		var ca := CardDB.card(a)
		var cb := CardDB.card(b)
		var ra: int = rank.get(ca.get("rarity", "common"), 0)
		var rb: int = rank.get(cb.get("rarity", "common"), 0)
		if ra != rb:
			return ra > rb
		return int(ca.get("cost", 0)) > int(cb.get("cost", 0)))
	return ids.slice(0, 3)


func _play_entry(e: Dictionary) -> void:
	if e.is_empty() or e.problem != "":
		return
	Sfx.play("ui_confirm", -4.0)
	if e.own:
		var d: Dictionary = Collection.decks[e.index]
		Game.start_with(Collection.deck_cards(d.cards), e.hero, "ferry" if e.cls == "pilgrim" else "pilgrim")
	else:
		Game.start_battle(e.id)


func _remember() -> void:
	Settings.deck_choice["selected"] = _selected
	Settings.deck_choice["filter"] = _filter
	if not Game.debug_run(): # snapshots and tests never touch the player's settings
		Settings.save()


# --- Header ------------------------------------------------------------------------------------------------------

## The next arena on an engraved plaque, beside the opponent's strength (a click steps Easy > Medium > Hard, saved
## at once). The arena is drawn now (a different one from last match), so the player knows where the fight will be.
func _header() -> Control:
	var arena := CardDB.arena(Game.pick_arena())
	var where := str(arena.get("name", ""))
	if str(arena.get("circle", "")) != "":
		where += "  ·  " + str(arena.circle)
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 24)
	var plaque := PanelContainer.new()
	var sb := UI.frame_box("deck_row", 10, 0, UI.box(Color(0.08, 0.04, 0.035, 0.9), UI.GOLD_DARK, 2, 8))
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	plaque.add_theme_stylebox_override("panel", sb)
	var sub := UI.label("Next arena:  " + where, 26, "italic", UI.BONE, 4, Color.BLACK)
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fit_label(sub, 760.0, 18)
	plaque.add_child(sub)
	head.add_child(plaque)
	var diff := UI.button("Opponent: " + Settings.DIFFICULTY_NAMES[Settings.difficulty], 400, 60)
	diff.add_theme_font_size_override("font_size", 30)
	diff.pressed.connect(func():
		Settings.difficulty = (Settings.difficulty + 1) % Settings.DIFFICULTY_NAMES.size()
		Settings.save()
		diff.text = "Opponent: " + Settings.DIFFICULTY_NAMES[Settings.difficulty]
		diff.add_theme_font_size_override("font_size", 30)
		UI.fit_text(diff))
	head.add_child(diff)
	return head


# --- Showcase ----------------------------------------------------------------------------------------------------

## A big bronze-framed panel `w` px wide.
func _big_panel(w: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(w, 0)
	var s := UI.frame_box("panel_frame_filled", 96, 0,
		UI.box(Color(0.08, 0.04, 0.035, 0.9), UI.GOLD_DARK, 3, 18, Color(0, 0, 0, 0.6), 24))
	s.content_margin_left = FRAME_PAD
	s.content_margin_right = FRAME_PAD
	s.content_margin_top = 40
	s.content_margin_bottom = 44
	p.add_theme_stylebox_override("panel", s)
	return p


## The selected deck: hero, name on the ribbon, hero power and plan on a plaque, featured cards, Play (and Edit for
## the player's own decks).
func _showcase() -> Control:
	var inner := SHOW_W - 2.0 * FRAME_PAD
	var p := _big_panel(SHOW_W)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	_portrait = Control.new()
	_portrait.custom_minimum_size = Vector2(inner, 170)
	v.add_child(_portrait)
	# The deck's name on the painted ribbon; the text stays inside the ribbon's flat middle.
	var ribbon := Control.new()
	ribbon.custom_minimum_size = Vector2(inner, 76)
	v.add_child(ribbon)
	var rw := inner + 40.0
	var rh := rw * 144.0 / 768.0
	if UiSkin.has("name_ribbon"):
		ribbon.add_child(UiSkin.rect("name_ribbon", Vector2(rw, rh), Vector2(-20, -2)))
	_name = UI.label("", 36, "title", UI.BONE, 6, Color(0.12, 0.02, 0.02))
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.size = Vector2(inner, rh * 0.78)
	_name.position = Vector2(0, -2)
	_name.set_meta("room", rw * 0.64) ## the ribbon's flat middle, between its folded tails
	ribbon.add_child(_name)
	# Hero power and plan on a framed plaque.
	var plaque := PanelContainer.new()
	plaque.add_theme_stylebox_override("panel", UI.tip_box())
	plaque.custom_minimum_size = Vector2(0, 144)
	v.add_child(plaque)
	var pv := VBoxContainer.new()
	pv.alignment = BoxContainer.ALIGNMENT_CENTER
	pv.add_theme_constant_override("separation", 4)
	plaque.add_child(pv)
	var room := inner - 100.0 ## the plaque's margins
	_who = UI.label("", 21, "italic", Color(0.92, 0.78, 0.5))
	_who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_who.custom_minimum_size = Vector2(room, 0)
	pv.add_child(_who)
	_txt = UI.label("", 24, "body", UI.BONE)
	_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_txt.custom_minimum_size = Vector2(room, 0)
	pv.add_child(_txt)
	_cards = Control.new()
	_cards.custom_minimum_size = Vector2(inner, 130)
	v.add_child(_cards)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	v.add_child(buttons)
	_play = UI.button("Play", 280, 64)
	_play.add_theme_font_size_override("font_size", 38)
	_play.pressed.connect(func(): _play_entry(_find(_selected)))
	buttons.add_child(_play)
	_edit_btn = UI.button("Edit", 170, 64)
	_edit_btn.add_theme_font_size_override("font_size", 28)
	_edit_btn.pressed.connect(func():
		var e := _find(_selected)
		if not e.is_empty() and e.own:
			_edit(e.index, e.cls))
	buttons.add_child(_edit_btn)
	return p


## Puts deck `e` in the showcase: hero, name (shrunk to fit the ribbon), hero power and plan (shrunk to fit), the
## featured cards (they slide in from the side the selection moved toward).
func _show(e: Dictionary, step: int) -> void:
	if e.is_empty():
		_play.disabled = true
		_edit_btn.visible = false
		return
	var inner := _portrait.custom_minimum_size.x
	var hero := CardDB.hero(e.hero)
	if _hero == null or str(_hero.get_meta("id", "")) != e.hero:
		if _hero != null:
			_hero.queue_free()
		_hero = HeroView.new().setup({"uid": -1, "side": 0, "id": e.hero, "health": hero.get("health", 30)})
		_hero.set_meta("id", e.hero)
		_hero.position = Vector2(inner / 2, 90)
		_hero.scale = Vector2(0.9, 0.9)
		_hero.power.visible = false
		_portrait.add_child(_hero)
	_name.text = e.name
	_name.add_theme_font_size_override("font_size", 36)
	_fit_label(_name, float(_name.get_meta("room")), 22)
	var room := _who.custom_minimum_size.x
	_who.text = "%s  ·  %s: %s" % [hero.get("name", ""), hero.power.name, hero.power.text]
	_who.add_theme_font_size_override("font_size", 21)
	_fit_wrapped(_who, room, 2, 16)
	_txt.text = e.text if e.problem == "" else "Incomplete: %s. Open it in the editor to finish it." % e.problem
	_txt.add_theme_color_override("font_color", UI.BONE if e.problem == "" else Color(1.0, 0.55, 0.45))
	_txt.add_theme_font_size_override("font_size", 24)
	_fit_wrapped(_txt, room, 3, 17)
	for c in _cards.get_children():
		c.queue_free()
	var ids: Array = e.featured
	var mid := inner / 2
	for i in ids.size():
		var c := CardView.new().setup(ids[i], -1, true)
		c.scale = Vector2(0.37, 0.37)
		var at := Vector2(mid + (i - 1) * 120.0, 66 + absf(i - 1) * 7)
		c.position = at
		c.rotation = (i - 1) * 0.12
		_cards.add_child(c)
		if step != 0:
			c.position = at + Vector2(90 * step, 0)
			c.modulate.a = 0.0
			var t := c.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			t.tween_property(c, "position", at, 0.28).set_delay(0.04 * i)
			t.tween_property(c, "modulate:a", 1.0, 0.18).set_delay(0.04 * i)
	_play.disabled = e.problem != ""
	_edit_btn.visible = e.own


# --- Library -----------------------------------------------------------------------------------------------------

## The deck library: class filters on engraved plates, then a scrolling grid of deck tiles and the new-deck tiles.
func _library() -> Control:
	var inner := LIB_COLS * TILE.x + (LIB_COLS - 1) * TILE_GAP
	var p := _big_panel(inner + 2.0 * FRAME_PAD)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 12)
	v.add_child(top)
	for f in FILTERS:
		var b := UI.button(f[1], 210 if f[0] == "all" else 190, 56)
		b.add_theme_font_size_override("font_size", 24)
		b.pressed.connect(func():
			_filter = f[0]
			_remember()
			_refill())
		_tabs[f[0]] = b
		top.add_child(b)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER # wheel, drag and the bronze discs scroll it
	# Whole rows only, so no tile is cut in half at the bottom edge.
	var room := _row_height() - 84.0 - 56.0 - ARROW_SIZE - 24.0
	var rows := maxi(2, int((room + TILE_GAP) / (TILE.y + TILE_GAP)))
	_scroll.custom_minimum_size = Vector2(inner + 12.0, rows * (TILE.y + TILE_GAP) - TILE_GAP + 8.0)
	v.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = LIB_COLS
	_grid.position = Vector2(6, 4)
	_grid.add_theme_constant_override("h_separation", int(TILE_GAP))
	_grid.add_theme_constant_override("v_separation", int(TILE_GAP))
	_scroll.add_child(_grid)
	# Bronze discs to scroll a long library, shown only when it overflows.
	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 24)
	nav.custom_minimum_size = Vector2(0, ARROW_SIZE)
	v.add_child(nav)
	for dir in [-1, 1]:
		var a := _arrow_button(dir)
		a.rotation = PI / 2 # containers reset rotation, so the disc sits in a plain holder
		a.tooltip_text = "Scroll up" if dir < 0 else "Scroll down"
		var holder := Control.new()
		holder.custom_minimum_size = a.size
		a.pressed.connect(func():
			var t := _scroll.create_tween()
			t.tween_property(_scroll, "scroll_vertical", _scroll.scroll_vertical + dir * int(TILE.y + TILE_GAP) * 2,
				0.2).set_ease(Tween.EASE_OUT))
		holder.add_child(a)
		nav.add_child(holder)
		_scroll_btns.append(a)
	_scroll.resized.connect(_update_scroll_btns)
	return p


## Rebuilds the tiles for the current filter.
func _refill() -> void:
	for f in _tabs:
		var on: bool = f == _filter
		(_tabs[f] as Button).modulate = Color(1.15, 1.05, 0.85) if on else Color(0.72, 0.66, 0.6)
	for c in _grid.get_children():
		c.queue_free()
	for e in _entries:
		if _filter == "all" or e.cls == _filter:
			_grid.add_child(_tile(e))
	for cls in ["pilgrim", "ferry"]:
		if _filter == "all" or _filter == cls:
			_grid.add_child(_new_tile(cls))
	_scroll.scroll_vertical = 0
	_update_scroll_btns.call_deferred()


func _update_scroll_btns() -> void:
	if _grid == null:
		return
	var rows := ceili(float(_grid.get_child_count()) / LIB_COLS)
	var overflow := rows * (TILE.y + TILE_GAP) - TILE_GAP > _scroll.size.y + 1.0
	for b in _scroll_btns:
		b.modulate.a = 1.0 if overflow else 0.0
		b.disabled = not overflow


const TILE_FIELD := Color(0.55, 0.45, 0.4)
const TILE_FIELD_ON := Color(0.95, 0.62, 0.42)


## The tile's resting frame: lit gold when it is the deck in the showcase.
func _tile_style(on: bool) -> StyleBox:
	return UI.frame_box("deck_row", 10, 0, UI.box(Color(0.1, 0.05, 0.04, 0.92), UI.GOLD_DARK if not on else UI.GOLD,
		2, 8), Color(1.5, 1.3, 0.9) if on else Color(0.95, 0.9, 0.85))


## A tile's painted body: the dark painted field inside the thin bronze frame, brighter when hovered.
func _tile_base() -> Button:
	var b := Button.new()
	b.custom_minimum_size = TILE
	b.focus_mode = Control.FOCUS_NONE
	b.pivot_offset = TILE / 2
	var fill := UI.box(Color(0.1, 0.05, 0.04, 0.92), UI.GOLD_DARK, 2, 8)
	b.add_theme_stylebox_override("normal", _tile_style(false))
	b.add_theme_stylebox_override("hover", UI.frame_box("deck_row", 10, 0, fill, Color(1.35, 1.2, 0.95)))
	b.add_theme_stylebox_override("pressed", UI.frame_box("deck_row", 10, 0, fill, Color(1.5, 1.3, 0.9)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if ResourceLoader.exists("res://assets/ui/panel_bg.jpg"):
		var bg := TextureRect.new()
		bg.name = "Field"
		bg.texture = load("res://assets/ui/panel_bg.jpg")
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.position = Vector2(5, 5)
		bg.size = TILE - Vector2(10, 10)
		bg.show_behind_parent = true
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.modulate = TILE_FIELD
		b.add_child(bg)
	b.mouse_entered.connect(func():
		Sfx.play("ui_hover", -12.0)
		b.create_tween().tween_property(b, "scale", Vector2.ONE * 1.03, 0.08))
	b.mouse_exited.connect(func(): b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.08))
	return b


## The hero's face in a small gilded oval at the left of a tile.
func _tile_portrait(b: Control, hero_id: String, dim: bool) -> void:
	var art := TextureRect.new()
	art.texture = CardDB.hero_art(hero_id)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.size = Vector2(60, 74)
	art.position = Vector2(22, (TILE.y - 74) / 2)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = CARD_FX
	m.set_shader_parameter("mask_mode", 1)
	art.material = m
	if dim:
		art.modulate = Color(0.45, 0.4, 0.38)
	b.add_child(art)
	if UiSkin.has("oval_ring"):
		var ring := UiSkin.rect("oval_ring", art.size * Vector2(1.2, 1.16), art.position - art.size * Vector2(0.1, 0.08))
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(ring)


## A label inside a tile, right of the portrait, shrunk to fit.
func _tile_label(b: Control, text: String, px: int, kind: String, color: Color, y: float, h: float) -> Label:
	var room := TILE.x - 112.0 - 22.0
	var l := UI.label(text, px, kind, color, 4 if kind == "title" else 3, Color(0.04, 0.01, 0.01))
	l.position = Vector2(112, y)
	l.size = Vector2(room, h)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fit_label(l, room, 15)
	b.add_child(l)
	return l


## One deck in the library. A click shows it in the showcase; a click on the deck already shown plays it.
func _tile(e: Dictionary) -> Button:
	var b := _tile_base()
	b.set_meta("key", e.key)
	_tile_portrait(b, e.hero, e.problem != "")
	_tile_label(b, e.name, 26, "title", UI.BONE if e.problem == "" else Color(0.75, 0.66, 0.6), 12, 40)
	var cls_name := "Pilgrim" if e.cls == "pilgrim" else "Ferryman"
	var sub := ("Your deck · " if e.own else "Starter deck · ") + cls_name
	var col := Color(0.86, 0.72, 0.48)
	if e.problem != "":
		sub = "Incomplete · " + e.problem
		col = Color(1.0, 0.5, 0.4)
	_tile_label(b, sub, 19, "italic", col, 50, 30)
	b.pressed.connect(func():
		if _selected == e.key:
			_play_entry(e)
			return
		var before := _entries.find(_find(_selected))
		_selected = e.key
		_remember()
		_show(e, 1 if _entries.find(e) > before else -1)
		_mark_selected())
	_mark_tile(b, e.key == _selected)
	return b


func _mark_tile(b: Button, on: bool) -> void:
	b.add_theme_stylebox_override("normal", _tile_style(on))
	var glow := b.get_node_or_null("Glow")
	if glow == null:
		glow = Panel.new()
		glow.name = "Glow"
		glow.size = TILE
		glow.show_behind_parent = true
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glow.add_theme_stylebox_override("panel", UI.box(Color(0, 0, 0, 0), Color(1.0, 0.78, 0.35, 0.9), 2, 8,
			Color(1.0, 0.5, 0.12, 0.55), 14))
		b.add_child(glow)
		b.move_child(glow, 0)
	glow.visible = on
	var field := b.get_node_or_null("Field")
	if field != null:
		field.modulate = TILE_FIELD_ON if on else TILE_FIELD


## Re-marks the selected tile without rebuilding the grid (keeps the scroll position).
func _mark_selected() -> void:
	for t in _grid.get_children():
		if t.has_meta("key"):
			_mark_tile(t, t.get_meta("key") == _selected)


## "New deck" tile of a class: opens the deck editor on an empty deck.
func _new_tile(cls: String) -> Button:
	var b := _tile_base()
	_tile_portrait(b, Collection.CLASS_HERO[cls], true)
	var plus := UI.label("+", 54, "title", UI.GOLD, 6, Color.BLACK)
	plus.position = Vector2(22, (TILE.y - 74) / 2)
	plus.size = Vector2(60, 74)
	plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(plus)
	_tile_label(b, "New deck", 26, "title", UI.GOLD, 12, 40)
	_tile_label(b, "Build a %s deck" % ("Pilgrim" if cls == "pilgrim" else "Ferryman"), 19, "italic",
		Color(0.86, 0.72, 0.48), 50, 30)
	b.pressed.connect(_edit.bind(-1, cls))
	return b


# --- Helpers -----------------------------------------------------------------------------------------------------

## A round button: the painted bronze disc with an engraved arrow (-1 = previous / up, 1 = next / down).
func _arrow_button(dir: int) -> Button:
	var b := Button.new()
	b.text = "‹" if dir < 0 else "›"
	b.size = Vector2(ARROW_SIZE, ARROW_SIZE)
	b.custom_minimum_size = b.size
	b.pivot_offset = b.size / 2
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", UI.font("title"))
	b.add_theme_font_size_override("font_size", 48)
	b.add_theme_color_override("font_color", Color(0.22, 0.09, 0.03))
	b.add_theme_color_override("font_hover_color", Color(0.35, 0.05, 0.02))
	b.add_theme_color_override("font_pressed_color", Color(0.12, 0.04, 0.02))
	b.add_theme_color_override("font_shadow_color", Color(1.0, 0.9, 0.62, 0.35))
	b.add_theme_constant_override("shadow_offset_y", 2)
	for st in [["normal", Color(0.95, 0.9, 0.82)], ["hover", Color(1.2, 1.08, 0.9)], ["pressed", Color(0.75, 0.62, 0.5)],
			["disabled", Color(0.95, 0.9, 0.82)]]:
		b.add_theme_stylebox_override(st[0], UI.frame_box("power_disc", 0, 0,
			UI.box(Color(0.1, 0.04, 0.03, 0.88), UI.GOLD_DARK, 3, int(ARROW_SIZE / 2)), st[1]))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.mouse_entered.connect(func(): Sfx.play("ui_hover", -10.0))
	b.pressed.connect(func(): Sfx.play("ui_confirm", -8.0))
	return b


## Shrinks a one-line label until its text fits `room` px.
func _fit_label(l: Label, room: float, min_size: int) -> void:
	var f := l.get_theme_font("font")
	var px := l.get_theme_font_size("font_size")
	while px > min_size and f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > room:
		px -= 1
	l.add_theme_font_size_override("font_size", px)


## Shrinks a wrapping label until its text takes at most `lines` lines of `room` px.
func _fit_wrapped(l: Label, room: float, lines: int, min_size: int) -> void:
	var f := l.get_theme_font("font")
	var px := l.get_theme_font_size("font_size")
	while px > min_size:
		var h := f.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_CENTER, room, px).y
		if h <= f.get_height(px) * lines + 2.0:
			break
		px -= 1
	l.add_theme_font_size_override("font_size", px)


func _edit(index: int, cls: String) -> void:
	Game.edit_deck = index
	Game.new_deck_cls = cls
	Game.go(Game.DECK_BUILDER)
