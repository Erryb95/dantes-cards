class_name OptionsPanel
extends Control
## Modal options: volumes, fullscreen and V-Sync (desktop), frame limit, FPS counter, animation speed. Saves on close.


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
	v.add_theme_constant_override("separation", 22)
	m.add_child(v)
	var title := UI.banner("Options", 54, UI.GOLD, 0.0, 0.0, 1.8) # the heading on the charred banner
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(title)
	# Two columns, so every row fits a phone-height screen: sound and screen on the left, the game on the right.
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 64)
	v.add_child(cols)
	var left := _column(cols)
	var right := _column(cols)
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
	right.add_child(_cycle("Opponent", Settings.DIFFICULTY_NAMES, Settings.difficulty, func(i): Settings.difficulty = i))
	right.add_child(_toggle("Fast animations", Settings.fast_animations, func(on): Settings.fast_animations = on))
	right.add_child(_toggle("Intro subtitles", Settings.subtitles, func(on): Settings.subtitles = on))
	if get_tree().current_scene and get_tree().current_scene.scene_file_path == Game.MENU:  # not mid-battle
		var intro := UI.button("Watch intro", 360)
		intro.pressed.connect(func():
			Settings.save()
			Game.play_intro())
		var ic := CenterContainer.new()
		ic.add_child(intro)
		right.add_child(ic)
	right.add_child(HowToPlayPanel.open_button(self))
	right.add_child(CreditsPanel.open_button(self))
	var close := UI.button("Done", 300)
	close.pressed.connect(_close)
	var cc := CenterContainer.new()
	cc.add_child(close)
	v.add_child(cc)


func _column(parent: Control) -> VBoxContainer:
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", 18)
	parent.add_child(c)
	return c


func _close() -> void:
	Settings.save()
	queue_free()


func _row(text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 30)
	var l := UI.label(text, 32, "title", UI.BONE)
	l.custom_minimum_size = Vector2(290, 0)
	h.add_child(l)
	return h


func _slider(text: String, value: float, on_change: Callable) -> HBoxContainer:
	var h := _row(text)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(340, 48)
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
	var b := UI.button(names[value], 300, 64)
	b.pressed.connect(func():
		var i := (names.find(b.text) + 1) % names.size()
		b.text = names[i]
		b.add_theme_font_size_override("font_size", 34)
		UI.fit_text(b)
		on_change.call(i))
	h.add_child(b)
	return h


## An On / Off switch on a painted plate: lit when on, dimmed when off.
func _toggle(text: String, value: bool, on_change: Callable) -> HBoxContainer:
	var h := _row(text)
	var b := UI.button("On" if value else "Off", 200, 60)
	b.toggle_mode = true
	b.button_pressed = value
	b.add_theme_font_size_override("font_size", 30)
	b.modulate = Color(1.1, 1.02, 0.88) if value else Color(0.68, 0.62, 0.58)
	b.toggled.connect(func(on: bool):
		b.text = "On" if on else "Off"
		b.modulate = Color(1.1, 1.02, 0.88) if on else Color(0.68, 0.62, 0.58)
		on_change.call(on))
	h.add_child(b)
	return h
