extends Control
## Title screen.

var _showcase: Array[CardView] = []
var _t := 0.0


func _ready() -> void:
	if Game.intro_due():  # first launch: the opening cinematic comes first, then this scene again
		get_tree().change_scene_to_file.call_deferred(Game.INTRO)
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackdrop.new())
	Sfx.play_music("intro")
	Sfx.play_ambience("") # the music alone (Enrico picks background sounds himself)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = 120
	col.offset_right = 900
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 18)
	add_child(col)

	# The logo engraved on its painted cartouche (the text sits on the plate's dark centre panel).
	var title := UI.label("DANTE'S INFERNO", 80, "title", UI.GOLD, 14, Color(0.12, 0.01, 0.0))
	if UiSkin.has("title_plate"):
		var logo := Control.new()
		logo.custom_minimum_size = Vector2(780, 173)
		logo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		logo.add_child(UiSkin.rect("title_plate", logo.custom_minimum_size))
		title.position = Vector2(125, 48)
		title.size = Vector2(555, 80)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		UI.fit_label(title, 530.0, 40)
		logo.add_child(title)
		var word := UI.word_tex("DANTE'S INFERNO")
		if word != null: # the painted lettering in the label's place
			title.visible = false
			var wr := UI.word_rect(word, Vector2(540, 84))
			wr.position = Vector2(125, 48) + (Vector2(555, 80) - wr.size) / 2.0
			logo.add_child(wr)
		col.add_child(logo)
	else:
		col.add_child(title)
	# The subtitle on the charred banner under the logo.
	var sub := UI.banner("THE CARD GAME", 40, UI.BONE)
	sub.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(sub)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	col.add_child(spacer)

	var play := UI.button("Play", 460, 96)
	play.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	play.add_theme_font_size_override("font_size", 44)
	play.pressed.connect(func(): Game.go(Game.DECK_SELECT))
	col.add_child(play)
	var learn := UI.button("Learn to Play", 460)
	learn.name = "LearnToPlay"
	learn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	learn.pressed.connect(func(): Game.go(Game.LESSONS))
	col.add_child(learn)
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
	# The record, engraved on a plaque as wide as the buttons.
	var stats := UI.plaque_label("Victories %d   ·   Defeats %d" % [Game.stats.wins, Game.stats.losses], 26, "title",
		Color(0.95, 0.86, 0.68), 400.0)
	stats.name = "Record"
	stats.custom_minimum_size = Vector2(460, 64)
	stats.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(stats)

	# The version engraved on a small plaque in the bottom-right corner (what made the art and the music is in the credits).
	var credit := UI.plaque_label("v%s" % ProjectSettings.get_setting("application/config/version"), 20, "body",
		Color(0.86, 0.8, 0.7), 0.0, 20, 5)
	credit.name = "Credit"
	credit.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT) # the FPS counter (Options) sits bottom-left
	credit.offset_right = -16
	credit.offset_bottom = -12
	credit.grow_horizontal = Control.GROW_DIRECTION_BEGIN
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
	if Lessons.offer_due():
		# A new player, once: Virgil offers his lessons when the title screen has settled.
		get_tree().create_timer(1.1).timeout.connect(offer_lessons)


## The first-launch question: Virgil offers to teach the game. Asked once ever (a skip or Esc counts as an answer);
## the lessons stay under Learn to Play.
func offer_lessons() -> void:
	if not is_inside_tree() or get_node_or_null("Dialog") != null:
		return
	Settings.lessons_offered = true
	Settings.save()
	var first := str(Lessons.all()[0].id) if not Lessons.all().is_empty() else ""
	Virgil.dialog(self, "New to Hell?",
		"I am Virgil. Let me show you the way: a few short lessons teach the whole game. You can find them later under Learn to Play.",
		[["Begin the lessons", func(): Game.start_lesson(first)], ["Not now", null]])


## Esc / the back gesture (Game.back) on the title screen: a phone leaves the game, as its other apps do; a desktop
## stays (Quit is one click away, and a stray Esc should not close the game).
func go_back() -> void:
	if OS.has_feature("mobile"):
		get_tree().quit()


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
