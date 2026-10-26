extends Control
## Choose a preconstructed deck (or one of your own); a random deck of the other class becomes the opponent.
##
## Every piece is painted: the class panels are bronze frames, the deck name sits on the red ribbon, the hero and
## the plan on a framed plaque, the switcher arrows on bronze discs, and every text is fitted to the room inside
## its frame. Sizes follow the screen width, so the panels never spill off a narrow (4:3) screen.

const PANEL_W := 700.0 ## widest a class panel gets
const PANEL_GAP := 50.0
const PANEL_PAD := 64.0 ## room the bronze frame's ornament takes on each side of the panel


func _ready() -> void:
	Sfx.play_ambience("") # menus play the music alone (an ambience loop would leak in from the battle)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackdrop.new())
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var title := UI.label("Choose your path", 58, "title", UI.GOLD, 10, Color.BLACK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	root.add_child(_header())
	var pw := _panel_width()
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(PANEL_GAP))
	root.add_child(row)
	for d in _panel_decks():
		row.add_child(_deck_panel(d, pw))
	root.add_child(_my_decks())
	var back := UI.button("Back", 280, 62)
	back.pressed.connect(func(): Game.go(Game.MENU))
	var bc := CenterContainer.new()
	bc.add_child(back)
	root.add_child(bc)


## The width of one class panel: as wide as PANEL_W, narrower on screens that cannot fit two of them.
func _panel_width() -> float:
	var w := get_viewport_rect().size.x
	return clampf((w - 100.0 - PANEL_GAP) / 2.0, 540.0, PANEL_W)


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
	plaque.add_theme_stylebox_override("panel", UI.frame_box("deck_row", 10, 0,
		UI.box(Color(0.08, 0.04, 0.035, 0.9), UI.GOLD_DARK, 2, 8)))
	var sb: StyleBox = plaque.get_theme_stylebox("panel")
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	var sub := UI.label("Next arena:  " + where, 26, "italic", UI.BONE, 4, Color.BLACK)
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fit_label(sub, minf(760.0, get_viewport_rect().size.x - 620.0), 18)
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


## One panel per class: the hero, and the preconstructed deck picked with the arrows (name, plan, three featured
## cards). Clicking the panel plays that deck; the opponent plays a random deck of the other class.
func _deck_panel(first: Dictionary, pw: float) -> Control:
	var cls := CardDB.deck_class(first)
	var list := CardDB.class_decks(cls)
	var hero := CardDB.hero(first.hero)
	var inner := pw - 2.0 * PANEL_PAD ## the room inside the frame's ornament
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(pw, 0)
	var normal := UI.frame_box("panel_frame_filled", 96, 0,
		UI.box(Color(0.08, 0.04, 0.035, 0.9), UI.GOLD_DARK, 3, 18, Color(0, 0, 0, 0.6), 24))
	var hover := UI.frame_box("panel_frame_filled", 96, 0,
		UI.box(Color(0.2, 0.06, 0.04, 0.95), UI.GOLD, 4, 18, Color(1.0, 0.45, 0.1, 0.5), 34), Color(1.3, 1.1, 0.9))
	for s in [normal, hover]:
		s.content_margin_left = PANEL_PAD
		s.content_margin_right = PANEL_PAD
		s.content_margin_top = 36
		s.content_margin_bottom = 40
	p.add_theme_stylebox_override("panel", normal)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_entered.connect(func():
		p.add_theme_stylebox_override("panel", hover)
		Sfx.play("ui_hover", -10.0))
	p.mouse_exited.connect(func(): p.add_theme_stylebox_override("panel", normal))
	p.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			Sfx.play("ui_confirm", -4.0)
			Game.start_battle(str(p.get_meta("deck"))))
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	# The hero, centred in the panel (scaled down a little so the panel stays short).
	var portrait := Control.new()
	portrait.custom_minimum_size = Vector2(inner, 176)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(portrait)
	var hv := HeroView.new().setup({"uid": -1, "side": 0, "id": first.hero, "health": hero.get("health", 30)})
	hv.position = Vector2(inner / 2, 90)
	hv.scale = Vector2(0.9, 0.9)
	hv.power.visible = false
	portrait.add_child(hv)
	# The deck's name on the painted ribbon; the text stays inside the ribbon's flat middle.
	var ribbon := Control.new()
	ribbon.custom_minimum_size = Vector2(inner, 78)
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ribbon)
	var rw := minf(inner + 40.0, 600.0)
	if UiSkin.has("name_ribbon"):
		ribbon.add_child(UiSkin.rect("name_ribbon", Vector2(rw, rw * 144.0 / 768.0), Vector2((inner - rw) / 2, -2)))
	var name := UI.label("", 36, "title", UI.BONE, 6, Color(0.12, 0.02, 0.02))
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name.size = Vector2(inner, rw * 144.0 / 768.0 * 0.78)
	name.position = Vector2(0, -2)
	name.set_meta("room", rw * 0.66) ## the ribbon's flat middle, between its folded tails
	ribbon.add_child(name)
	# The hero and the plan on a framed plaque.
	var plaque := PanelContainer.new()
	plaque.add_theme_stylebox_override("panel", UI.tip_box())
	plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(plaque)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 4)
	plaque.add_child(pv)
	var room := inner - 100.0 ## the plaque's margins
	var who := UI.label("%s  ·  %s: %s" % [hero.get("name", ""), hero.power.name, hero.power.text], 21, "italic",
		Color(0.92, 0.78, 0.5))
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	who.custom_minimum_size = Vector2(room, 0)
	_fit_wrapped(who, room, 2, 16)
	pv.add_child(who)
	var txt := UI.label("", 24, "body", UI.BONE)
	txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.custom_minimum_size = Vector2(room, 0)
	txt.set_meta("room", room)
	pv.add_child(txt)
	var cards := Control.new()
	cards.custom_minimum_size = Vector2(inner, 136)
	cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(cards)
	if list.size() > 1:
		# The deck switcher: bronze discs beside the portrait, so the panel keeps its size. A click on an arrow stays
		# on the arrow (it does not start the battle).
		for dir in [-1, 1]:
			var arrow := _arrow_button(dir)
			arrow.position = Vector2(inner / 2 + dir * minf(ARROW_DX, inner / 2 - ARROW_SIZE / 2) - ARROW_SIZE / 2,
				90 - ARROW_SIZE / 2)
			arrow.pressed.connect(func():
				var i := wrapi(list.find(CardDB.deck(str(p.get_meta("deck")))) + dir, 0, list.size())
				_show_deck(p, list[i], dir, name, txt, cards)
				_remember_deck(cls, str(list[i].id)))
			portrait.add_child(arrow)
	_show_deck(p, first, 0, name, txt, cards)
	return p


const ARROW_SIZE := 70.0
const ARROW_DX := 230.0 ## arrow centres from the panel's middle, clear of the hero portrait


## A round switcher button: the painted bronze disc with an engraved arrow (-1 = previous, 1 = next).
func _arrow_button(dir: int) -> Button:
	var b := Button.new()
	b.text = "‹" if dir < 0 else "›"
	b.tooltip_text = "Previous deck" if dir < 0 else "Next deck"
	b.size = Vector2(ARROW_SIZE, ARROW_SIZE)
	b.custom_minimum_size = b.size
	b.pivot_offset = b.size / 2
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", UI.font("title"))
	b.add_theme_font_size_override("font_size", 52)
	b.add_theme_color_override("font_color", Color(0.22, 0.09, 0.03))
	b.add_theme_color_override("font_hover_color", Color(0.35, 0.05, 0.02))
	b.add_theme_color_override("font_pressed_color", Color(0.12, 0.04, 0.02))
	b.add_theme_color_override("font_shadow_color", Color(1.0, 0.9, 0.62, 0.35))
	b.add_theme_constant_override("shadow_offset_y", 2)
	for st in [["normal", Color(0.95, 0.9, 0.82)], ["hover", Color(1.2, 1.08, 0.9)], ["pressed", Color(0.75, 0.62, 0.5)]]:
		var r := int(ARROW_SIZE / 2)
		b.add_theme_stylebox_override(st[0], UI.frame_box("power_disc", 0, 0,
			UI.box(Color(0.1, 0.04, 0.03, 0.88), UI.GOLD_DARK, 3, r), st[1]))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.mouse_entered.connect(func():
		Sfx.play("ui_hover", -10.0)
		b.create_tween().tween_property(b, "scale", Vector2.ONE * 1.12, 0.09))
	b.mouse_exited.connect(func(): b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.09))
	b.pressed.connect(func(): Sfx.play("ui_confirm", -8.0))
	return b


## Puts deck `d` on its class panel: the name (shrunk to fit the ribbon), the plan (shrunk to fit three lines), the
## featured cards (they slide in from the side the player cycled toward).
func _show_deck(p: Control, d: Dictionary, step: int, title: Label, txt: Label, cards: Control) -> void:
	p.set_meta("deck", str(d.id))
	title.text = d.name
	title.add_theme_font_size_override("font_size", 36)
	_fit_label(title, float(title.get_meta("room")), 22)
	txt.text = d.text
	txt.add_theme_font_size_override("font_size", 24)
	_fit_wrapped(txt, float(txt.get_meta("room")), 3, 17)
	for c in cards.get_children():
		c.queue_free()
	var ids: Array = d.get("featured", [])
	var mid := cards.custom_minimum_size.x / 2
	var spread := minf(120.0, cards.custom_minimum_size.x / 4)
	for i in ids.size():
		var c := CardView.new().setup(ids[i], -1, true)
		c.scale = Vector2(0.37, 0.37)
		var at := Vector2(mid + (i - 1) * spread, 70 + absf(i - 1) * 7)
		c.position = at
		c.rotation = (i - 1) * 0.12
		cards.add_child(c)
		if step != 0:
			c.position = at + Vector2(90 * step, 0)
			c.modulate.a = 0.0
			var t := c.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			t.tween_property(c, "position", at, 0.28).set_delay(0.04 * i)
			t.tween_property(c, "modulate:a", 1.0, 0.18).set_delay(0.04 * i)


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


## The deck each class panel shows first: the one the player last picked, else the class's starter.
func _panel_decks() -> Array:
	var out := []
	for cls in ["pilgrim", "ferry"]:
		var list := CardDB.class_decks(cls)
		if list.is_empty():
			continue
		var d := CardDB.deck(str(Settings.deck_choice.get(cls, "")))
		out.append(d if not d.is_empty() and CardDB.deck_class(d) == cls else list[0])
	return out


func _remember_deck(cls: String, id: String) -> void:
	Settings.deck_choice[cls] = id
	if not Game.debug_run(): # snapshots and tests never touch the player's settings
		Settings.save()


## "Your decks": the saved decks in a strip that scrolls sideways once they no longer fit (bronze arrow discs, a
## drag, or the mouse wheel), each with its Edit plate; the two new-deck buttons stay fixed on the right.
const CHIP_W := 280.0
const EDIT_W := 124.0 ## wide enough for the painted plate
const CHIP_GAP := 18.0


func _my_decks() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	if not Collection.decks.is_empty():
		var strip := HBoxContainer.new()
		strip.add_theme_constant_override("separation", int(CHIP_GAP))
		for i in Collection.decks.size():
			strip.add_child(_deck_chip(i))
		var scroll := ScrollContainer.new()
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER # the arrows scroll it
		var step := CHIP_W + EDIT_W + 4.0 + CHIP_GAP
		var full := Collection.decks.size() * step - CHIP_GAP
		var room := get_viewport_rect().size.x - 2 * 520.0 - 2 * ARROW_SIZE
		# Whole chips only: the strip is as wide as the chips that fit, never cutting one in half.
		var fit := maxi(1, int((room + CHIP_GAP) / step))
		scroll.custom_minimum_size = Vector2(minf(full, fit * step - CHIP_GAP), 66)
		scroll.add_child(strip)
		# The vertical mouse wheel scrolls the strip sideways.
		scroll.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				scroll.scroll_horizontal += 120 * (1 if e.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
				scroll.accept_event())
		var overflow := full > scroll.custom_minimum_size.x + 1.0
		if overflow:
			var l := _arrow_button(-1)
			l.pressed.connect(func(): scroll.scroll_horizontal -= int(step))
			row.add_child(l)
		row.add_child(scroll)
		if overflow:
			var r := _arrow_button(1)
			r.pressed.connect(func(): scroll.scroll_horizontal += int(step))
			row.add_child(r)
	var news := HBoxContainer.new()
	news.add_theme_constant_override("separation", 14)
	for c in [["pilgrim", "+ Pilgrim"], ["ferry", "+ Ferryman"]]:
		var n := UI.button(c[1], 240, 60)
		n.add_theme_font_size_override("font_size", 22)
		n.tooltip_text = "New %s deck" % ("Pilgrim" if c[0] == "pilgrim" else "Ferryman")
		n.pressed.connect(_edit.bind(-1, c[0]))
		news.add_child(n)
	row.add_child(news)
	return row


## One saved deck: its name (play it; an incomplete deck opens the editor instead) and an Edit plate.
func _deck_chip(i: int) -> Control:
	var d: Dictionary = Collection.decks[i]
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 4)
	var problem := Collection.deck_problem(d)
	var b := UI.button(str(d.name), CHIP_W, 60)
	b.add_theme_font_size_override("font_size", 22)
	b.tooltip_text = ("Pilgrim" if d.cls == "pilgrim" else "Ferryman") + (" deck" if problem == "" else " deck: " + problem)
	if problem != "":
		b.modulate = Color(0.75, 0.62, 0.58) # incomplete: dimmed, opens the editor
	b.pressed.connect(func():
		if Collection.deck_problem(d) == "":
			Sfx.play("ui_confirm", -4.0)
			Game.start_with(Collection.deck_cards(d.cards), Collection.CLASS_HERO[d.cls],
				"ferry" if d.cls == "pilgrim" else "pilgrim")
		else:
			_edit(i, d.cls))
	chip.add_child(b)
	var e := UI.button("Edit", EDIT_W, 60)
	e.add_theme_font_size_override("font_size", 20)
	e.pressed.connect(_edit.bind(i, d.cls))
	chip.add_child(e)
	return chip


func _edit(index: int, cls: String) -> void:
	Game.edit_deck = index
	Game.new_deck_cls = cls
	Game.go(Game.DECK_BUILDER)
