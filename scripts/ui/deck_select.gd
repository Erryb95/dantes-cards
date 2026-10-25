extends Control
## Choose a starter deck; the other one becomes the opponent.

const FEATURED := {"pilgrim": ["homer", "hector", "virgils_counsel"], "ferry": ["minos", "wasps_and_hornets", "gatekeeper_demon"]}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackdrop.new())
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 30)
	add_child(root)
	var title := UI.label("Choose your path", 70, "title", UI.GOLD, 10, Color.BLACK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	var arena := CardDB.arena(Game.arena_id)
	var sub := UI.label("First arena: " + str(arena.get("name", "")), 30, "italic", UI.BONE, 5, Color.BLACK)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(sub)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 60)
	root.add_child(row)
	for d in CardDB.decks():
		row.add_child(_deck_panel(d))
	var back := UI.button("Back", 300, 70)
	back.pressed.connect(func(): Game.go(Game.MENU))
	var bc := CenterContainer.new()
	bc.add_child(back)
	root.add_child(bc)


func _deck_panel(d: Dictionary) -> Control:
	var hero := CardDB.hero(d.hero)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(700, 620)
	var normal := UI.box(Color(0.08, 0.04, 0.035, 0.9), UI.GOLD_DARK, 3, 18, Color(0, 0, 0, 0.6), 24)
	var hover := UI.box(Color(0.2, 0.06, 0.04, 0.95), UI.GOLD, 4, 18, Color(1.0, 0.45, 0.1, 0.5), 34)
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
	v.add_theme_constant_override("separation", 12)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var portrait := Control.new()
	portrait.custom_minimum_size = Vector2(0, 250)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(portrait)
	var hv := HeroView.new().setup({"uid": -1, "side": 0, "id": d.hero, "health": hero.get("health", 30)})
	hv.position = Vector2(350, 125)
	hv.power.visible = false
	portrait.add_child(hv)
	var name := UI.label(d.name, 46, "title", UI.GOLD, 8, Color.BLACK)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name)
	var hn := UI.label(str(hero.get("name", "")) + "  ·  Power: " + str(hero.power.name) + " - " + str(hero.power.text),
		24, "italic", Color(0.85, 0.78, 0.65))
	hn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hn)
	var txt := UI.label(d.text, 26, "body", UI.BONE)
	txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.custom_minimum_size = Vector2(620, 0)
	v.add_child(txt)
	var cards := Control.new()
	cards.custom_minimum_size = Vector2(0, 170)
	cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(cards)
	var ids: Array = FEATURED.get(d.id, [])
	for i in ids.size():
		var c := CardView.new().setup(ids[i], -1, true)
		c.scale = Vector2(0.44, 0.44)
		c.position = Vector2(350 + (i - 1) * 125, 85 + absf(i - 1) * 8)
		c.rotation = (i - 1) * 0.12
		cards.add_child(c)
	return p
