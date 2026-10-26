extends Control
## Choose a preconstructed deck (or one of your own); a random deck of the other class becomes the opponent.


func _ready() -> void:
	Sfx.play_ambience("") # menus play the music alone (an ambience loop would leak in from the battle)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackdrop.new())
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 14)
	add_child(root)
	var title := UI.label("Choose your path", 70, "title", UI.GOLD, 10, Color.BLACK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	# The arena is drawn now (a different one from last match), so the player knows where the fight will be.
	var arena := CardDB.arena(Game.pick_arena())
	var where := str(arena.get("name", ""))
	if str(arena.get("circle", "")) != "":
		where += "  ·  " + str(arena.circle)
	var sub := UI.label("Next arena: " + where, 30, "italic", UI.BONE, 5, Color.BLACK)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# The opponent's strength sits beside the arena line; a click steps Easy > Medium > Hard (saved at once).
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 36)
	head.add_child(sub)
	var diff := UI.button("Opponent: " + Settings.DIFFICULTY_NAMES[Settings.difficulty], 440, 60)
	diff.pressed.connect(func():
		Settings.difficulty = (Settings.difficulty + 1) % Settings.DIFFICULTY_NAMES.size()
		Settings.save()
		diff.text = "Opponent: " + Settings.DIFFICULTY_NAMES[Settings.difficulty]
		diff.add_theme_font_size_override("font_size", 34)
		UI.fit_text(diff))
	head.add_child(diff)
	root.add_child(head)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 60)
	root.add_child(row)
	for d in _panel_decks():
		row.add_child(_deck_panel(d))
	root.add_child(_my_decks())
	var back := UI.button("Back", 300, 64)
	back.pressed.connect(func(): Game.go(Game.MENU))
	var bc := CenterContainer.new()
	bc.add_child(back)
	root.add_child(bc)


## One panel per class: the hero, and the preconstructed deck picked with the arrows (name, plan, three featured
## cards). Clicking the panel plays that deck; the opponent plays a random deck of the other class.
func _deck_panel(first: Dictionary) -> Control:
	var cls := CardDB.deck_class(first)
	var list := CardDB.class_decks(cls)
	var hero := CardDB.hero(first.hero)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(700, 0)
	var normal := UI.frame_box("panel_frame_filled", 96, 44,
		UI.box(Color(0.08, 0.04, 0.035, 0.9), UI.GOLD_DARK, 3, 18, Color(0, 0, 0, 0.6), 24))
	var hover := UI.frame_box("panel_frame_filled", 96, 44,
		UI.box(Color(0.2, 0.06, 0.04, 0.95), UI.GOLD, 4, 18, Color(1.0, 0.45, 0.1, 0.5), 34), Color(1.3, 1.1, 0.9))
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
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var portrait := Control.new()
	portrait.custom_minimum_size = Vector2(0, 210)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(portrait)
	var hv := HeroView.new().setup({"uid": -1, "side": 0, "id": first.hero, "health": hero.get("health", 30)})
	hv.position = Vector2(350, 105)
	hv.power.visible = false
	portrait.add_child(hv)
	var name := UI.label("", 46, "title", UI.GOLD, 8, Color.BLACK)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name)
	for line in [str(hero.get("name", "")), "Power: %s - %s" % [hero.power.name, hero.power.text]]:
		var hn := UI.label(line, 23, "italic", Color(0.85, 0.78, 0.65))
		hn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(hn)
	var txt := UI.label("", 26, "body", UI.BONE)
	txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.custom_minimum_size = Vector2(620, 0)
	v.add_child(txt)
	var cards := Control.new()
	cards.custom_minimum_size = Vector2(0, 160)
	cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(cards)
	if list.size() > 1:
		# The deck switcher: arrows beside the portrait, so the panel keeps its size. A click on an arrow stays on
		# the arrow (it does not start the battle).
		for dir in [-1, 1]:
			var arrow := _arrow_button(dir)
			arrow.position = Vector2(350 + dir * ARROW_DX - ARROW_SIZE / 2, 105 - ARROW_SIZE / 2)
			arrow.pressed.connect(func():
				var i := wrapi(list.find(CardDB.deck(str(p.get_meta("deck")))) + dir, 0, list.size())
				_show_deck(p, list[i], dir, name, txt, cards)
				_remember_deck(cls, str(list[i].id)))
			portrait.add_child(arrow)
	_show_deck(p, first, 0, name, txt, cards)
	return p


const ARROW_SIZE := 64.0
const ARROW_DX := 240.0 ## arrow centres from the panel's middle, clear of the hero portrait


## A round arrow button for the deck switcher (-1 = previous, 1 = next).
func _arrow_button(dir: int) -> Button:
	var b := Button.new()
	b.text = "<" if dir < 0 else ">"
	b.tooltip_text = "Previous deck" if dir < 0 else "Next deck"
	b.size = Vector2(ARROW_SIZE, ARROW_SIZE)
	b.custom_minimum_size = b.size
	b.pivot_offset = b.size / 2
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", UI.font("title"))
	b.add_theme_font_size_override("font_size", 40)
	b.add_theme_color_override("font_color", UI.GOLD)
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.7))
	b.add_theme_color_override("font_pressed_color", Color(1.0, 0.75, 0.4))
	var r := int(ARROW_SIZE / 2)
	b.add_theme_stylebox_override("normal", UI.box(Color(0.1, 0.04, 0.03, 0.88), UI.GOLD_DARK, 3, r, Color(0, 0, 0, 0.6), 8))
	b.add_theme_stylebox_override("hover", UI.box(Color(0.32, 0.08, 0.05, 0.95), UI.GOLD, 3, r, Color(1.0, 0.45, 0.1, 0.5), 16))
	b.add_theme_stylebox_override("pressed", UI.box(Color(0.45, 0.1, 0.05, 1.0), UI.GOLD, 4, r, Color(1.0, 0.5, 0.1, 0.6), 20))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.mouse_entered.connect(func():
		Sfx.play("ui_hover", -10.0)
		b.create_tween().tween_property(b, "scale", Vector2.ONE * 1.12, 0.09))
	b.mouse_exited.connect(func(): b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.09))
	b.pressed.connect(func(): Sfx.play("ui_confirm", -8.0))
	return b


## Puts deck `d` on its class panel: the name (shrunk to fit), the plan, the featured cards (they slide in from the
## side the player cycled toward).
func _show_deck(p: Control, d: Dictionary, step: int, title: Label, txt: Label, cards: Control) -> void:
	p.set_meta("deck", str(d.id))
	title.text = d.name
	var px := 46
	var font := title.get_theme_font("font")
	while px > 30 and font.get_string_size(d.name, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > 600.0:
		px -= 2
	title.add_theme_font_size_override("font_size", px)
	txt.text = d.text
	for c in cards.get_children():
		c.queue_free()
	var ids: Array = d.get("featured", [])
	for i in ids.size():
		var c := CardView.new().setup(ids[i], -1, true)
		c.scale = Vector2(0.44, 0.44)
		var at := Vector2(350 + (i - 1) * 125, 80 + absf(i - 1) * 8)
		c.position = at
		c.rotation = (i - 1) * 0.12
		cards.add_child(c)
		if step != 0:
			c.position = at + Vector2(90 * step, 0)
			c.modulate.a = 0.0
			var t := c.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			t.tween_property(c, "position", at, 0.28).set_delay(0.04 * i)
			t.tween_property(c, "modulate:a", 1.0, 0.18).set_delay(0.04 * i)


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


## "Your decks": the saved decks in a strip that scrolls sideways once they no longer fit (drag, or the mouse
## wheel), each with its pen button; the two new-deck buttons stay fixed on the right.
const DECKS_MAX_W := 1240.0 ## widest the saved-deck strip gets before it scrolls
const CHIP_W := 300.0
const EDIT_W := 124.0 ## wide enough for the painted plate
const CHIP_GAP := 22.0


func _my_decks() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	if not Collection.decks.is_empty():
		var strip := HBoxContainer.new()
		strip.add_theme_constant_override("separation", int(CHIP_GAP))
		for i in Collection.decks.size():
			strip.add_child(_deck_chip(i))
		var scroll := ScrollContainer.new()
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		var full := Collection.decks.size() * (CHIP_W + EDIT_W + 4.0 + CHIP_GAP) - CHIP_GAP
		scroll.custom_minimum_size = Vector2(minf(full, DECKS_MAX_W), 80)
		scroll.add_child(strip)
		var bar := scroll.get_h_scroll_bar()
		bar.custom_minimum_size.y = 8
		bar.add_theme_stylebox_override("scroll", UI.box(Color(0, 0, 0, 0.45), Color.TRANSPARENT, 0, 4))
		bar.add_theme_stylebox_override("grabber", UI.box(UI.GOLD_DARK, Color.TRANSPARENT, 0, 4))
		bar.add_theme_stylebox_override("grabber_highlight", UI.box(UI.GOLD, Color.TRANSPARENT, 0, 4))
		bar.add_theme_stylebox_override("grabber_pressed", UI.box(UI.GOLD, Color.TRANSPARENT, 0, 4))
		# The vertical mouse wheel scrolls the strip sideways.
		scroll.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				scroll.scroll_horizontal += 120 * (1 if e.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
				scroll.accept_event())
		row.add_child(scroll)
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


## One saved deck: its name (play it; an incomplete deck opens the editor instead) and a pen button to edit it.
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
