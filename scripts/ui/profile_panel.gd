class_name ProfilePanel
extends Control
## The player's profile, painted, over a dim veil: the display name (an engraved name field with the gold-ink caret,
## checked live by Profile.problem, the rule or the error inked on parchment under it), the avatar (one hero portrait
## per class, CardDB.classes), and the record (victories, defeats, favourite class). Save keeps a valid name and the
## avatar in Settings (user://settings.cfg; never in a debug run); Back, Esc and the Android back gesture close it
## without saving: the modal is named "Dialog" with Back as its "cancel" (Game.back → UI.cancel_dialog).
## A player without a name is offered one ("Pilgrim4821") to keep or change; offline play never asks for it.
## On a phone the panel slides up while the on-screen keyboard is open, so the name field stays in sight.

signal saved

const HINT := "3 to 16 characters: letters, digits, spaces, _ and -."
const AVATAR := Vector2(96, 120) ## an avatar choice's portrait
const BIG := Vector2(176, 220) ## the chosen avatar, large

var field: LineEdit
var avatar := ""
var _hint: Label
var _panel: PanelContainer
var _center: CenterContainer
var _big: Control
var _big_holder: Control
var _hero_line: Label
var _choices := {} ## hero id -> its Button
var _lift := 0.0 ## how far the panel is slid up for the on-screen keyboard


## Opens the profile over `scene` (the screen that owns Esc / back). Returns the panel.
static func open(scene: Node) -> ProfilePanel:
	var old := scene.get_node_or_null("Dialog")
	if old != null:
		old.queue_free()
		scene.remove_child(old)
	var p := ProfilePanel.new()
	p.name = "Dialog"
	scene.add_child(p)
	return p


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100 # above the scene's Node2D layers (the main menu's floating cards)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_center = CenterContainer.new()
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)
	_panel = PanelContainer.new()
	var s := UI.frame_box("panel_frame_filled", 96, 0, UI.box(Color(0.09, 0.05, 0.04, 0.97), UI.GOLD, 3, 14,
		Color(0, 0, 0, 0.7), 30))
	s.content_margin_left = 84
	s.content_margin_right = 84
	s.content_margin_top = 52
	s.content_margin_bottom = 58
	_panel.add_theme_stylebox_override("panel", s)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_center.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	_panel.add_child(v)
	v.add_child(UI.banner("Profile", 52, UI.GOLD, 0.0, 0.0, 1.8)) # the heading on the charred banner

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 56)
	v.add_child(cols)
	avatar = Profile.avatar()
	cols.add_child(_left_column())
	cols.add_child(_right_column())

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	v.add_child(row)
	var save_b := UI.button("Save", 300, 76)
	save_b.name = "Save"
	save_b.pressed.connect(func(): save())
	row.add_child(save_b)
	var back := UI.button("Back", 300, 76)
	back.name = "Back"
	back.pressed.connect(close)
	row.add_child(back)
	UI.even_text([save_b, back])
	set_meta("cancel", back)
	_check(field.text)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)
	Sfx.play("page", -6.0)


## The chosen avatar large in its gilded ring, the hero's name under it, then the record inked on parchment.
func _left_column() -> Control:
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	left.custom_minimum_size.x = 300
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_big_holder = CenterContainer.new()
	_big_holder.custom_minimum_size = BIG * 1.22 # room for the ring, which overhangs the oval
	_big_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(_big_holder)
	_hero_line = UI.label("", 24, "italic", Color(0.95, 0.82, 0.55), 3, ClassInfoPanel.SHADE)
	_hero_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(_hero_line)
	_show_big()
	left.add_child(ClassInfoPanel.section("Record", 300))
	var sheet := PanelContainer.new()
	sheet.add_theme_stylebox_override("panel", UI.parchment_box(30, 16))
	sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(sheet)
	var grid := GridContainer.new()
	grid.name = "Record"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	sheet.add_child(grid)
	var fav := Game.favourite_class()
	for r in [["Victories", str(Game.stats.wins)], ["Defeats", str(Game.stats.losses)],
			["Favourite class", CardDB.class_title(fav) if fav != "" else "None yet"]]:
		grid.add_child(UI.label(r[0], 22, "italic", UI.INK))
		var val := UI.label(r[1], 22, "title", UI.INK_RED)
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		UI.fit_label(val, 120.0, 15)
		grid.add_child(val)
	return left


## The name field with the nib disc beside it, the rule (or what is wrong) on parchment under it, then the avatars.
func _right_column() -> Control:
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	right.custom_minimum_size.x = 600
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(ClassInfoPanel.section("Display name", 600))
	var nr := HBoxContainer.new()
	nr.add_theme_constant_override("separation", 10)
	right.add_child(nr)
	# A new player is offered a name, selected so that typing replaces it.
	field = UI.name_field(Profile.display_name() if Profile.has_name() else Profile.suggestion(), "Your name",
		Profile.MAX_LEN, 30)
	field.name = "NameField"
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	field.text_changed.connect(_check)
	field.text_submitted.connect(func(_t: String): field.release_focus()) # Enter / the phone's Done: the keyboard goes
	nr.add_child(field)
	var nib := UI.disc("Edit your name", Callable(), "icon_rename")
	nib.pressed.connect(func():
		field.grab_focus()
		field.select_all())
	nr.add_child(nib)
	var sheet := PanelContainer.new()
	sheet.add_theme_stylebox_override("panel", UI.parchment_box(26, 13))
	sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(sheet)
	_hint = UI.label(HINT, 23, "italic", UI.INK)
	_hint.name = "Hint"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(540, 0)
	sheet.add_child(_hint)
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	right.add_child(gap)
	right.add_child(ClassInfoPanel.section("Avatar", 600))
	# One portrait per class hero (any number of classes: the row wraps).
	var flow := HFlowContainer.new()
	flow.name = "Avatars"
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", 18)
	flow.add_theme_constant_override("v_separation", 12)
	right.add_child(flow)
	for h in Profile.avatars():
		flow.add_child(_choice(h))
	_mark_choice()
	return right


## A hero portrait to pick as avatar (the hero's name as its tooltip).
func _choice(hero_id: String) -> Button:
	var b := Button.new()
	b.name = hero_id
	b.custom_minimum_size = AVATAR * 1.22
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "%s (%s)" % [CardDB.hero(hero_id).get("name", hero_id), CardDB.class_title(CardDB.hero_class(hero_id))]
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	var glow := TextureRect.new() # an ember glow behind the chosen one
	glow.name = "Glow"
	glow.texture = UI.dot_texture()
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.size = b.custom_minimum_size * 1.25
	glow.position = -b.custom_minimum_size * 0.125
	glow.modulate = Color(1.0, 0.6, 0.2, 0.75)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(glow)
	var p := ClassInfoPanel.portrait(hero_id, AVATAR)
	p.position = AVATAR * 0.11
	b.add_child(p)
	b.resized.connect(func(): b.pivot_offset = b.size / 2)
	b.mouse_entered.connect(func():
		Sfx.play("ui_hover", -12.0)
		b.create_tween().tween_property(b, "scale", Vector2.ONE * 1.06, 0.08))
	b.mouse_exited.connect(func(): b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.08))
	b.pressed.connect(func(): pick(hero_id))
	_choices[hero_id] = b
	return b


## Makes `hero_id` the avatar shown (saved with Save).
func pick(hero_id: String) -> void:
	if not _choices.has(hero_id):
		return
	Sfx.play("ui_confirm", -8.0)
	avatar = hero_id
	_mark_choice()
	_show_big()


func _mark_choice() -> void:
	for h in _choices:
		var b: Button = _choices[h]
		b.get_node("Glow").visible = h == avatar
		b.modulate = Color.WHITE if h == avatar else Color(0.62, 0.58, 0.55)


func _show_big() -> void:
	if _big != null:
		_big.queue_free()
	_big = ClassInfoPanel.portrait(avatar, BIG)
	var m := MarginContainer.new() # the portrait's ring overhangs it: keep it centred in the holder
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(_big)
	_big = m
	_big_holder.add_child(m)
	var hero := CardDB.hero(avatar)
	_hero_line.text = str(hero.get("name", ""))
	UI.fit_label(_hero_line, 300.0, 16)
	m.pivot_offset = BIG / 2
	m.scale = Vector2.ONE * 0.9
	m.create_tween().tween_property(m, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Shows the rule under the field while `text` is a valid name, else what is wrong with it, in red ink.
func _check(text: String) -> bool:
	var why := Profile.problem(text)
	_hint.text = HINT if why == "" else why
	_hint.add_theme_color_override("font_color", UI.INK if why == "" else UI.INK_RED)
	return why == ""


## Keeps a valid name (cleaned: trimmed, single spaces) and the avatar, writes the settings and closes. An invalid
## name is refused: the error stays in red under the field and the field shakes. Returns whether it saved.
func save() -> bool:
	if not _check(field.text):
		Sfx.play("ui_back", -8.0)
		var x := field.position.x
		var t := field.create_tween()
		for d in [10.0, -8.0, 5.0, 0.0]:
			t.tween_property(field, "position:x", x + d, 0.04)
		return false
	Settings.player_name = Profile.clean(field.text)
	Settings.player_avatar = avatar
	Settings.save() # a debug run keeps it in memory only
	saved.emit()
	close()
	return true


func close() -> void:
	if is_queued_for_deletion():
		return
	field.release_focus()
	queue_free()


## On a phone, slides the panel up while the on-screen keyboard covers the name field (Godot does not pan for it).
func _process(_delta: float) -> void:
	if not is_instance_valid(field):
		return
	var want := 0.0
	var kb := DisplayServer.virtual_keyboard_get_height() if DisplayServer.has_feature(
		DisplayServer.FEATURE_VIRTUAL_KEYBOARD) else 0
	if kb > 0 and field.has_focus():
		var vs := get_viewport_rect().size
		var win := DisplayServer.window_get_size()
		var top_of_kb := vs.y - kb * vs.y / maxf(1.0, float(win.y))
		var bottom := field.get_global_rect().end.y + _lift + 24.0
		want = maxf(0.0, bottom - top_of_kb)
	if absf(want - _lift) > 0.5:
		_lift = lerpf(_lift, want, 0.35)
		_center.offset_top = -_lift
		_center.offset_bottom = -_lift
