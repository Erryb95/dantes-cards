class_name OptionsPanel
extends Control
## Modal options: volumes, fullscreen (desktop), animation speed. Saves on close.


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
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
	v.add_theme_constant_override("separation", 26)
	m.add_child(v)
	var title := UI.label("Options", 60, "title", UI.GOLD, 8, Color.BLACK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	v.add_child(_slider("Music", Settings.music_volume, func(x):
		Settings.music_volume = x
		Settings.apply()))
	v.add_child(_slider("Effects", Settings.sfx_volume, func(x):
		Settings.sfx_volume = x
		Settings.apply()
		Sfx.play("tick", -6.0)))
	if Settings.is_desktop():
		v.add_child(_toggle("Fullscreen", Settings.fullscreen, func(on):
			Settings.fullscreen = on
			Settings.apply()))
	v.add_child(_toggle("Fast animations", Settings.fast_animations, func(on): Settings.fast_animations = on))
	v.add_child(_cycle("Opponent", Settings.DIFFICULTY_NAMES, Settings.difficulty, func(i): Settings.difficulty = i))
	v.add_child(_toggle("Intro subtitles", Settings.subtitles, func(on): Settings.subtitles = on))
	if get_tree().current_scene and get_tree().current_scene.scene_file_path == Game.MENU:  # not mid-battle
		var intro := UI.button("Watch intro", 420)
		intro.pressed.connect(func():
			Settings.save()
			Game.play_intro())
		var ic := CenterContainer.new()
		ic.add_child(intro)
		v.add_child(ic)
	var close := UI.button("Done", 300)
	close.pressed.connect(_close)
	var cc := CenterContainer.new()
	cc.add_child(close)
	v.add_child(cc)


func _close() -> void:
	Settings.save()
	queue_free()


func _row(text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 30)
	var l := UI.label(text, 34, "title", UI.BONE)
	l.custom_minimum_size = Vector2(320, 0)
	h.add_child(l)
	return h


func _slider(text: String, value: float, on_change: Callable) -> HBoxContainer:
	var h := _row(text)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(420, 48)
	s.add_theme_stylebox_override("slider", UI.frame_box("slider_track", 14, 6, UI.box(Color(0.2, 0.1, 0.08), UI.GOLD_DARK, 2, 8)))
	if UiSkin.has("slider_grabber"):
		s.add_theme_icon_override("grabber", UI.scaled_tex("slider_grabber", 46))
		s.add_theme_icon_override("grabber_highlight", UI.scaled_tex("slider_grabber", 52))
	s.add_theme_stylebox_override("grabber_area", UI.box(UI.CRIMSON, UI.GOLD_DARK, 2, 8))
	s.add_theme_stylebox_override("grabber_area_highlight", UI.box(UI.CRIMSON.lightened(0.2), UI.GOLD, 2, 8))
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


func _toggle(text: String, value: bool, on_change: Callable) -> HBoxContainer:
	var h := _row(text)
	var b := CheckButton.new()
	b.button_pressed = value
	b.scale = Vector2(1.6, 1.6)
	b.toggled.connect(on_change)
	h.add_child(b)
	return h
