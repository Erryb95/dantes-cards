extends Control
## Title screen.

var _showcase: Array[CardView] = []
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackdrop.new())
	Sfx.play_music("intro")
	Sfx.play_ambience("limbo_drone.ogg", -18.0)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = 120
	col.offset_right = 900
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 18)
	add_child(col)

	var title := UI.label("DANTE'S INFERNO", 92, "title", UI.GOLD, 14, Color(0.12, 0.01, 0.0))
	col.add_child(title)
	var sub := UI.label("THE CARD GAME", 40, "title", UI.BONE, 6, Color.BLACK)
	col.add_child(sub)
	var quote := UI.label("\"Abandon every hope, you who enter here.\"", 30, "italic", Color(0.85, 0.75, 0.62), 4, Color.BLACK)
	col.add_child(quote)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 40)
	col.add_child(spacer)

	var play := UI.button("Play", 460, 96)
	play.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	play.add_theme_font_size_override("font_size", 44)
	play.pressed.connect(func(): Game.go(Game.DECK_SELECT))
	col.add_child(play)
	var coll := UI.button("Collection", 460)
	coll.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	coll.pressed.connect(func(): Game.go(Game.COLLECTION))
	col.add_child(coll)
	var packs := UI.button("Open Packs (%d)" % Collection.packs if Collection.packs > 0 else "Open Packs", 460)
	packs.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	packs.pressed.connect(func(): Game.go(Game.PACKS))
	col.add_child(packs)
	var opts := UI.button("Options", 460)
	opts.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	opts.pressed.connect(func(): add_child(OptionsPanel.new()))
	col.add_child(opts)
	if Settings.is_desktop():
		var quit := UI.button("Quit", 460)
		quit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		quit.pressed.connect(func(): get_tree().quit())
		col.add_child(quit)
	var stats := UI.label("Victories %d   ·   Defeats %d" % [Game.stats.wins, Game.stats.losses], 26, "body",
		Color(0.8, 0.72, 0.6), 4, Color.BLACK)
	col.add_child(stats)

	var credit := UI.label("v%s  ·  card art AI-generated (Qwen-Image), music public domain" % ProjectSettings.get_setting(
		"application/config/version"), 18, "body", Color(0.6, 0.55, 0.5), 3, Color.BLACK)
	credit.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	credit.position = Vector2(24, -40)
	credit.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(credit)

	# A fan of legendary cards floating on the right.
	for id in ["minos", "francesca", "ugolino"]:
		var c := CardView.new().setup(id, -1, true)
		add_child(c)
		_showcase.append(c)
	for i in _showcase.size():
		_showcase[i].modulate.a = 0.0
		var t := _showcase[i].create_tween()
		t.tween_interval(0.3 + i * 0.25)
		t.tween_property(_showcase[i], "modulate:a", 1.0, 0.8)
	col.modulate.a = 0.0
	create_tween().tween_property(col, "modulate:a", 1.0, 1.0)


func _process(delta: float) -> void:
	_t += delta
	var vs := get_viewport_rect().size
	var cx := vs.x * 0.72
	for i in _showcase.size():
		var c := _showcase[i]
		var k := i - 1.0
		c.position = Vector2(cx + k * 210.0, vs.y * 0.5 + absf(k) * 40.0 + sin(_t * 0.8 + i) * 12.0)
		c.rotation = k * 0.16 + sin(_t * 0.6 + i * 2.0) * 0.03
		c.scale = Vector2.ONE * (0.95 if i == 1 else 0.82)
		c.z_index = 2 if i == 1 else 1
