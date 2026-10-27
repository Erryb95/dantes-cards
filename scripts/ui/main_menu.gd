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

	# Play, with Virgil's medallion (Learn to Play) beside it: the lessons are one press away without a sixth plate.
	var play_row := HBoxContainer.new()
	play_row.add_theme_constant_override("separation", 18)
	play_row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(play_row)
	var play := UI.button("Play", 460, 96)
	play.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	play.add_theme_font_size_override("font_size", 44)
	play.pressed.connect(func(): Game.go(Game.DECK_SELECT))
	play_row.add_child(play)
	var learn := _learn_medallion()
	learn.pressed.connect(func(): Game.go(Game.LESSONS))
	play_row.add_child(learn)
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
	# The player's plaque in the top-right corner: avatar, name, record; it opens the profile.
	_add_profile_plaque()

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
	_offer_rejoin()


## On launch: an online duel this player left running (a crash, a closed window) can be rejoined while the server
## still holds the seat. Asked once per run; tests and tooling never go online.
func _offer_rejoin() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--google-signin": # debug: the profile with Google's sign-in code on top (screenshots)
			var p := ProfilePanel.open(self)
			GoogleSignInPanel.open.call_deferred(p)
			return
		if a.begins_with("--online-quick="): # debug: straight into an online search with this premade deck
			var deck := CardDB.deck(a.substr(15))
			if not deck.is_empty():
				OnlineOverlay.open.call_deferred(self, CardDB.deck_class(deck), CardDB.deck_list(str(deck.id)))
			return
	if Game.debug_run() or not Online.configured() or Online.rejoin_checked or Online.in_match():
		return
	Online.rejoin_checked = true
	var id := await Online.check_rejoin()
	if id == "" or not is_inside_tree() or get_node_or_null("Dialog") != null:
		return
	UI.dialog(self, "Your duel is still on", "You left an online duel before it ended. Go back to it?",
		[["Rejoin", func(): OnlineOverlay.open(self, "", [], id)], ["Not now", null]])


## Learn to Play as a round medallion: Virgil's face on the bronze disc, its name on a small red ribbon across the
## foot. A button as tall as the Play plate.
func _learn_medallion() -> Button:
	const D := 108.0 ## the disc
	const W := 290.0 ## the ribbon
	var b := Button.new()
	b.name = "LearnToPlay"
	b.tooltip_text = "Virgil's lessons and How to Play"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(W, D + 26.0)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	var x := (W - D) / 2.0
	var glow := TextureRect.new() # warm lamplight behind the medallion
	glow.texture = UI.dot_texture()
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.size = Vector2(D, D) * 1.7
	glow.position = Vector2(x, 0) + (Vector2(D, D) - glow.size) / 2.0
	glow.modulate = Color(1.0, 0.62, 0.25, 0.3)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(glow)
	if UiSkin.has("power_disc"):
		b.add_child(UiSkin.rect("power_disc", Vector2(D, D), Vector2(x, 0)))
	var face := TextureRect.new() # his face in a circle inside the disc's bronze rim
	face.texture = Virgil.art(1.0)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	face.size = Vector2(D, D) * 0.84
	face.position = Vector2(x, 0) + Vector2(D, D) * 0.08
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = Virgil.CARD_FX
	m.set_shader_parameter("mask_mode", 1)
	face.material = m
	b.add_child(face)
	var rib := UI.ribbon("Learn to Play", W, 30, UI.GOLD)
	rib.position = Vector2(0, D - rib.size.y * 0.45)
	b.add_child(rib)
	b.resized.connect(func(): b.pivot_offset = b.size / 2)
	b.mouse_entered.connect(func():
		Sfx.play("ui_hover", -10.0)
		b.create_tween().tween_property(b, "scale", Vector2.ONE * 1.05, 0.08))
	b.mouse_exited.connect(func(): b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.08))
	b.button_down.connect(func(): b.create_tween().tween_property(b, "scale", Vector2.ONE * 0.96, 0.06))
	b.pressed.connect(func(): Sfx.play("ui_confirm", -6.0))
	return b


## The player's plaque: the avatar in its ring, the name (or "Choose your name" before there is one) over the record,
## and the pen nib. A press opens the profile; a save there redraws the plaque.
func _add_profile_plaque() -> void:
	var old := get_node_or_null("ProfilePlaque")
	if old != null:
		old.queue_free()
		remove_child(old)
	var b := Button.new()
	b.name = "ProfilePlaque"
	b.tooltip_text = "Your profile"
	b.focus_mode = Control.FOCUS_NONE
	for st in [["normal", Color.WHITE], ["hover", Color(1.35, 1.18, 0.9)], ["pressed", Color(0.85, 0.75, 0.65)]]:
		b.add_theme_stylebox_override(st[0], UI.plaque_box(18, 8, st[1]))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	UI.add_field(b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 20
	row.offset_right = -16
	row.offset_top = 10
	row.offset_bottom = -10
	b.add_child(row)
	var pm := MarginContainer.new() # room for the ring, which overhangs the oval
	pm.add_theme_constant_override("margin_left", 6)
	pm.add_theme_constant_override("margin_right", 6)
	pm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pm.add_child(ClassInfoPanel.portrait(Profile.avatar(), Vector2(56, 70)))
	row.add_child(pm)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.custom_minimum_size.x = 250
	row.add_child(v)
	var name_l: Label
	if Profile.has_name():
		name_l = ClassInfoPanel.gilded(Profile.display_name(), 30, 250.0)
	else:
		name_l = UI.label("Choose your name", 26, "italic", UI.BONE, 3, ClassInfoPanel.SHADE)
		UI.fit_label(name_l, 250.0, 16)
	name_l.name = "Name"
	v.add_child(name_l)
	var rec := UI.label("Victories %d  ·  Defeats %d" % [Game.stats.wins, Game.stats.losses], 20, "italic",
		Color(0.95, 0.82, 0.55), 3, ClassInfoPanel.SHADE)
	rec.name = "Record"
	UI.fit_label(rec, 250.0, 14)
	v.add_child(rec)
	if UiSkin.has("icon_rename"):
		var nib := UiSkin.rect("icon_rename", Vector2(40, 40))
		nib.custom_minimum_size = nib.size
		nib.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nib.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		row.add_child(nib)
	b.custom_minimum_size = Vector2(440, 96) # portrait 68 + name 250 + nib 40, the gaps and the frame
	b.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	b.offset_right = -24
	b.offset_top = 20
	b.offset_left = b.offset_right - b.custom_minimum_size.x
	b.offset_bottom = b.offset_top + b.custom_minimum_size.y
	b.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	b.mouse_entered.connect(func(): Sfx.play("ui_hover", -10.0))
	b.pressed.connect(func():
		Sfx.play("ui_confirm", -6.0)
		open_profile())
	add_child(b)
	# The cloud save's state in small letters under the plaque ("Saved to your account").
	var sync := UI.label(Online.sync_text(), 18, "italic", Color(0.86, 0.8, 0.7), 3, ClassInfoPanel.SHADE)
	sync.name = "SyncStatus"
	sync.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sync.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(sync) # goes with the plaque when it is rebuilt
	sync.position = Vector2(0, b.custom_minimum_size.y + 2)
	sync.size = Vector2(b.custom_minimum_size.x - 6, 26)
	if not Online.sync_status_changed.is_connected(_on_sync_status):
		Online.sync_status_changed.connect(_on_sync_status)
		Online.progress_applied.connect(_add_profile_plaque)


func _on_sync_status(text: String) -> void:
	var l := get_node_or_null("ProfilePlaque/SyncStatus") as Label
	if l != null:
		l.text = text


## Opens the profile panel over the title screen (Esc, back and Back close it).
func open_profile() -> ProfilePanel:
	var p := ProfilePanel.open(self)
	p.saved.connect(_add_profile_plaque)
	return p


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
