extends Control
## Choose a starter deck; the other one becomes the opponent.

const FEATURED := {"pilgrim": ["francesca", "geryon", "virgils_counsel"], "ferry": ["minos", "harpies_flock", "cerberus"]}


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
	root.add_child(sub)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 60)
	root.add_child(row)
	for d in CardDB.decks():
		row.add_child(_deck_panel(d))
	root.add_child(_my_decks())
	var back := UI.button("Back", 300, 64)
	back.pressed.connect(func(): Game.go(Game.MENU))
	var bc := CenterContainer.new()
	bc.add_child(back)
	root.add_child(bc)


func _deck_panel(d: Dictionary) -> Control:
	var hero := CardDB.hero(d.hero)
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
			Game.start_battle(d.id))
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var portrait := Control.new()
	portrait.custom_minimum_size = Vector2(0, 210)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(portrait)
	var hv := HeroView.new().setup({"uid": -1, "side": 0, "id": d.hero, "health": hero.get("health", 30)})
	hv.position = Vector2(350, 105)
	hv.power.visible = false
	portrait.add_child(hv)
	var name := UI.label(d.name, 46, "title", UI.GOLD, 8, Color.BLACK)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name)
	for line in [str(hero.get("name", "")), "Power: %s - %s" % [hero.power.name, hero.power.text]]:
		var hn := UI.label(line, 23, "italic", Color(0.85, 0.78, 0.65))
		hn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(hn)
	var txt := UI.label(d.text, 26, "body", UI.BONE)
	txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.custom_minimum_size = Vector2(620, 0)
	v.add_child(txt)
	var cards := Control.new()
	cards.custom_minimum_size = Vector2(0, 160)
	cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(cards)
	var ids: Array = FEATURED.get(d.id, [])
	for i in ids.size():
		var c := CardView.new().setup(ids[i], -1, true)
		c.scale = Vector2(0.44, 0.44)
		c.position = Vector2(350 + (i - 1) * 125, 80 + absf(i - 1) * 8)
		c.rotation = (i - 1) * 0.12
		cards.add_child(c)
	return p


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
