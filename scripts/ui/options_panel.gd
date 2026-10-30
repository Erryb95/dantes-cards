class_name OptionsPanel
extends Control
## Modal options: volumes, fullscreen and V-Sync (desktop), frame limit, FPS counter, animation speed. Saves on close.
## Laid out on one grid: two columns of rows ROW_H tall, ROW_GAP apart, each row a label LABEL_W wide (its letters
## centred on the row's height) and a control CONTROL_W wide; the page plates (Watch intro, How to Play, Credits) sit in
## the controls' column, so every plate and slider in a column shares the same left and right edges.

const ROW_H := 92.0 ## every row, slider or plate (a plate with 34 px letters needs 91 px: its margins and the line)
const ROW_GAP := 12
const LABEL_W := 290.0
const LABEL_GAP := 30
const CONTROL_W := 400.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100 # above the scene's Node2D layers (the main menu's floating cards)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.frame_box("panel_frame_filled", 96, 56,
		UI.box(Color(0.09, 0.05, 0.04, 0.97), UI.GOLD, 3, 14, Color(0, 0, 0, 0.7), 30)))
	center.add_child(panel)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 44)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	m.add_child(v)
	var title := UI.banner("Options", 54, UI.GOLD, 0.0, 0.0, 1.8) # the heading on the charred banner
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(title)
	# Two columns, so every row fits a phone-height screen: sound and screen on the left, the game on the right.
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 64)
	v.add_child(cols)
	var left := _column(cols, "Left")
	var right := _column(cols, "Right")
	left.add_child(_slider("Music", Settings.music_volume, func(x):
		Settings.music_volume = x
		Settings.apply()))
	left.add_child(_slider("Effects", Settings.sfx_volume, func(x):
		Settings.sfx_volume = x
		Settings.apply()
		Sfx.play("tick", -6.0)))
	if Settings.is_desktop():
		left.add_child(_toggle("Fullscreen", Settings.fullscreen, func(on):
			Settings.fullscreen = on
			Settings.apply()))
	left.add_child(_cycle("Frame limit", Settings.FRAME_LIMIT_NAMES, Settings.FRAME_LIMITS.find(Settings.frame_limit),
		func(i):
			Settings.frame_limit = Settings.FRAME_LIMITS[i]
			Settings.apply()))
	if Settings.is_desktop():
		left.add_child(_toggle("V-Sync", Settings.vsync, func(on):
			Settings.vsync = on
			Settings.apply()))
	left.add_child(_toggle("Show FPS", Settings.show_fps, func(on):
		Settings.show_fps = on
		Settings.apply()))
	left.add_child(_update_row())
	right.add_child(_cycle("Opponent", Settings.DIFFICULTY_NAMES, Settings.difficulty, func(i): Settings.difficulty = i))
	right.add_child(_toggle("Fast animations", Settings.fast_animations, func(on): Settings.fast_animations = on))
	right.add_child(_toggle("Intro subtitles", Settings.subtitles, func(on): Settings.subtitles = on))
	var in_menu: bool = get_tree().current_scene != null and get_tree().current_scene.scene_file_path == Game.MENU
	if in_menu: # not mid-battle: a new language rebuilds the screen
		var names: Array = Loc.LANGS.map(func(l): return Loc.NAMES[l])
		right.add_child(_cycle("Language", names, maxi(0, Loc.LANGS.find(Loc.lang())), func(i):
			Settings.language = Loc.LANGS[i]
			Settings.apply_language()
			Settings.save()
			get_tree().reload_current_scene.call_deferred()))
	var plates: Array = [] # the three page plates share one letter size
	if in_menu:
		var intro := UI.button("Watch intro", CONTROL_W, ROW_H)
		intro.pressed.connect(func():
			Settings.save()
			Game.play_intro())
		plates.append(intro)
	plates.append(HowToPlayPanel.open_button(self))
	plates.append(CreditsPanel.open_button(self))
	for b in plates: # in the controls' column, under the switches, with no label of their own
		var h := _row("")
		_fit_control(b)
		h.add_child(b)
		right.add_child(h)
	UI.even_text(plates)
	var close := UI.button("Done", 300)
	close.pressed.connect(_close)
	var cc := CenterContainer.new()
	cc.add_child(close)
	v.add_child(cc)


## The game's version (the update's, when one runs) and Check for updates; the answer opens over the panel
## (UpdatePrompt), with Remove updates when an update is installed.
func _update_row() -> HBoxContainer:
	var h := _row(Loc.t("Version %s") % Updater.current_version())
	var b := UI.button("Check for updates", CONTROL_W, ROW_H)
	b.name = "CheckUpdates"
	b.pressed.connect(func(): _check_updates(b))
	h.add_child(b)
	return h


func _check_updates(b: Button) -> void:
	if not Updater.available():
		UI.dialog(self, "Updates", "Updates work in the installed game only.", [["Close", null]])
		return
	var u := get_node_or_null("Updater") as Updater
	if u == null:
		u = Updater.new()
		u.name = "Updater"
		add_child(u)
	b.disabled = true
	b.text = Loc.t("Checking...")
	var res := await u.check()
	if not is_instance_valid(b) or not is_inside_tree():
		return
	b.disabled = false
	b.text = Loc.t("Check for updates")
	UI.fit_text(b)
	if res.state in ["patch", "full"]:
		UpdatePrompt.offer(self, res, u)
		return
	var latest: bool = res.state == "latest"
	var choices := [["Close", null]]
	if Updater.has_update():
		choices.push_front(["Remove updates", _remove_updates])
	UI.dialog(self, "Up to date" if latest else "No answer", Loc.t("You have the latest version, %s.") % Updater.current_version()
		if latest else "The update server did not answer. Try again later.", choices)


func _remove_updates() -> void:
	Updater.remove_updates()
	var text := Loc.t("The game goes back to version %s when it starts again.") % UpdateBoot.base_version()
	if OS.has_feature("pc"):
		UI.dialog(self, "Updates removed", text, [["Restart now", func(): Updater.restart(get_tree())], ["Close", null]])
	else:
		UI.dialog(self, "Updates removed", text, [["Close", null]])


func _column(parent: Control, id: String) -> VBoxContainer:
	var c := VBoxContainer.new()
	c.name = id
	c.add_theme_constant_override("separation", ROW_GAP)
	parent.add_child(c)
	return c


func _close() -> void:
	Settings.save()
	queue_free()


## A grid row: the label (or the empty room of one), its letters centred on the row's height; the caller adds the
## control (`_fit_control`).
func _row(text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", LABEL_GAP)
	h.custom_minimum_size.y = ROW_H
	var l := UI.label(text, 32, "title", UI.BONE)
	l.custom_minimum_size = Vector2(LABEL_W, ROW_H)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if text != "":
		UI.fit_label(l, LABEL_W, 24) # a longer translation shrinks a little instead of pushing its control out
		UI.center_ink(l) # the letters on the row's middle, level with the plate's
	h.add_child(l)
	return h


## A control in the controls' column: CONTROL_W by ROW_H, whatever size it was made at.
func _fit_control(c: Control) -> void:
	c.custom_minimum_size = Vector2(CONTROL_W, ROW_H)
	c.size_flags_horizontal = Control.SIZE_FILL
	c.size_flags_vertical = Control.SIZE_FILL


func _slider(text: String, value: float, on_change: Callable) -> HBoxContainer:
	var h := _row(text)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	_fit_control(s)
	s.add_theme_stylebox_override("slider", UI.frame_box("slider_track", 14, 6, UI.box(Color(0.2, 0.1, 0.08), UI.GOLD_DARK, 2, 8)))
	if UiSkin.has("slider_grabber"):
		s.add_theme_icon_override("grabber", UI.scaled_tex("slider_grabber", 46))
		s.add_theme_icon_override("grabber_highlight", UI.scaled_tex("slider_grabber", 52))
	# The filled part of the track: the same bronze rod, glowing like heated metal.
	s.add_theme_stylebox_override("grabber_area", UI.frame_box("slider_track", 14, 6,
		UI.box(UI.CRIMSON, UI.GOLD_DARK, 2, 8), Color(1.5, 0.75, 0.45)))
	s.add_theme_stylebox_override("grabber_area_highlight", UI.frame_box("slider_track", 14, 6,
		UI.box(UI.CRIMSON.lightened(0.2), UI.GOLD, 2, 8), Color(1.7, 0.9, 0.55)))
	s.value_changed.connect(on_change)
	h.add_child(s)
	return h


## A plate button that steps through `names` on each click and reports the new index.
func _cycle(text: String, names: Array, value: int, on_change: Callable) -> HBoxContainer:
	var h := _row(text)
	var b := UI.button(names[value], CONTROL_W, ROW_H)
	var at := [value] # the shown choice (the text may be a translation of its name)
	b.pressed.connect(func():
		var i: int = (at[0] + 1) % names.size()
		at[0] = i
		b.text = Loc.t(names[i])
		b.add_theme_font_size_override("font_size", 34)
		UI.fit_text(b)
		on_change.call(i))
	h.add_child(b)
	return h


## An On / Off switch on a painted plate: lit when on, dimmed when off.
func _toggle(text: String, value: bool, on_change: Callable) -> HBoxContainer:
	var h := _row(text)
	var b := UI.button("On" if value else "Off", CONTROL_W, ROW_H) # the same plate as the cycle buttons
	b.toggle_mode = true
	b.button_pressed = value
	b.add_theme_font_size_override("font_size", 34)
	b.modulate = Color(1.1, 1.02, 0.88) if value else Color(0.68, 0.62, 0.58)
	b.toggled.connect(func(on: bool):
		b.text = Loc.t("On" if on else "Off")
		b.modulate = Color(1.1, 1.02, 0.88) if on else Color(0.68, 0.62, 0.58)
		on_change.call(on))
	h.add_child(b)
	return h
