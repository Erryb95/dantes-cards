class_name OnlineOverlay
extends Control
## The online search, painted: "Online duel" on the charred banner, a parchment with your name, what is happening
## ("Searching for an opponent...") and the time spent, and Cancel. When the server pairs you, a versus splash shows
## both heroes and names, then the battle opens. Errors (no server, a refused key, a timeout) are inked on the same
## parchment with Try again / Close. Esc and the Android back gesture press Cancel / Close (it is a "Dialog").
##
## `rejoin_id`: go back into that running duel instead of searching (the main menu's offer on launch).

const INK := Color(0.2, 0.1, 0.04)
const INK_RED := Color(0.5, 0.08, 0.04)

var cls := ""
var cards: Array = []
var rejoin_id := ""
var _status: Label
var _clock: Label
var _who: Label
var _sheet: PanelContainer
var _row: HBoxContainer
var _body: VBoxContainer
var _t0 := 0
var _searching := false
var _leaving := false


static func open(parent: Node, p_cls: String, p_cards: Array, p_rejoin := "") -> OnlineOverlay:
	var o := OnlineOverlay.new()
	o.cls = p_cls
	o.cards = p_cards
	o.rejoin_id = p_rejoin
	parent.add_child(o)
	return o


func _ready() -> void:
	name = "Dialog" # Game.back() presses its "cancel" button
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_body = VBoxContainer.new()
	_body.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_theme_constant_override("separation", 26)
	center.add_child(_body)
	_build_search()
	Online.status.connect(_on_status)
	Online.match_ready.connect(_on_match_ready)
	Online.failed.connect(_on_failed)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.2)
	_start()


func _exit_tree() -> void:
	for s in [[Online.status, _on_status], [Online.match_ready, _on_match_ready], [Online.failed, _on_failed]]:
		if (s[0] as Signal).is_connected(s[1]):
			(s[0] as Signal).disconnect(s[1])


func _build_search() -> void:
	for c in _body.get_children():
		c.queue_free()
	_body.add_child(UI.banner("Online duel", 58, UI.GOLD, 0.0, 0.0, 1.8))
	_sheet = PanelContainer.new()
	_sheet.add_theme_stylebox_override("panel", UI.parchment_box(70, 40))
	_sheet.custom_minimum_size = Vector2(760, 0)
	_sheet.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_body.add_child(_sheet)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	_sheet.add_child(v)
	_who = UI.label("You walk as  " + Online.display_name(), 30, "title", INK)
	_who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_who)
	_status = UI.label("", 34, "italic", INK)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(620, 0)
	v.add_child(_status)
	_clock = UI.label("", 30, "title", INK_RED)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_clock)
	var rec := Online.record()
	if rec.wins + rec.losses + rec.draws > 0:
		var r := UI.label("Online record:  %d won  ·  %d lost" % [rec.wins, rec.losses] +
			("  ·  %d drawn" % rec.draws if rec.draws > 0 else ""), 24, "italic", INK)
		r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(r)
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 24)
	_body.add_child(_row)
	_buttons([["Cancel", _cancel]])


func _buttons(list: Array) -> void:
	for c in _row.get_children():
		c.queue_free()
	var made: Array[Button] = []
	for b in list:
		var btn := UI.button(b[0], 300, 76)
		btn.add_theme_font_size_override("font_size", 30)
		btn.pressed.connect(b[1])
		_row.add_child(btn)
		made.append(btn)
	UI.even_text(made)
	set_meta("cancel", made[-1])


func _start() -> void:
	_t0 = Time.get_ticks_msec()
	_searching = true
	_clock.text = "0:00"
	if not Online.configured():
		_on_failed("Online play is not set up on this copy of the game: it has no server settings " +
			"(config/online.local.cfg).")
		return
	if rejoin_id != "":
		_status.text = "Returning to your duel..."
		Online.rejoin(rejoin_id)
	else:
		_status.text = "Connecting to the server..."
		Online.search(cls, cards)


func _process(_delta: float) -> void:
	if _searching and _clock != null:
		var s := (Time.get_ticks_msec() - _t0) / 1000
		_clock.text = "%d:%02d" % [s / 60, s % 60]


func _on_status(text: String) -> void:
	if _status != null and _searching:
		_status.text = text


func _on_failed(message: String) -> void:
	if _leaving:
		return
	_searching = false
	_status.text = message
	_status.add_theme_color_override("font_color", INK_RED)
	_clock.text = ""
	Sfx.play("ui_back", -6.0)
	_buttons([["Try again", _retry], ["Close", _cancel]])


func _retry() -> void:
	_status.add_theme_color_override("font_color", INK)
	_buttons([["Cancel", _cancel]])
	_start()


func _cancel() -> void:
	if _leaving:
		return
	_leaving = true
	_searching = false
	Online.cancel_search()
	Sfx.play("ui_back", -6.0)
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.15)
	t.tween_callback(queue_free)


## Paired: both heroes face each other with their names, then the battle opens.
func _on_match_ready(start: Dictionary) -> void:
	if _leaving:
		return
	_searching = false
	var sync := DuelSync.new()
	if not sync.setup(start, Online.user_id()):
		Online.leave_match()
		_on_failed("The duel could not start: %s" % sync.error)
		return
	set_meta("cancel", Button.new()) # no way back from here: the duel is on
	Sfx.play("title_sting", -6.0, 1.0, 0.0)
	for c in _body.get_children():
		c.queue_free()
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 60)
	_body.add_child(row)
	var sides := [_fighter(sync, sync.me), null, _fighter(sync, 1 - sync.me)]
	sides[1] = UI.banner("VS", 90, UI.GOLD, 260.0, 0.0, 1.8)
	sides[1].size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for i in 3:
		row.add_child(sides[i])
		sides[i].modulate.a = 0.0
		var t := (sides[i] as Control).create_tween()
		t.tween_interval(0.15 * i)
		t.tween_property(sides[i], "modulate:a", 1.0, 0.35)
	var sub := UI.plaque_label("%s goes first" % ("You" if sync.first == sync.me else str(sync.names[sync.first])),
		28, "italic", UI.BONE)
	var sc := CenterContainer.new()
	sc.add_child(sub)
	_body.add_child(sc)
	await get_tree().create_timer(2.8).timeout
	if is_inside_tree():
		Game.start_online(sync)


func _fighter(sync: DuelSync, canon: int) -> Control:
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 14)
	var pc := CenterContainer.new()
	pc.add_child(ClassInfoPanel.portrait(str(sync.heroes[canon]), Vector2(250, 320)))
	v.add_child(pc)
	var n := str(sync.names[canon])
	if n == "":
		n = "You" if canon == sync.me else "Opponent"
	var plate := UI.plaque_label(n, 36, "title", UI.GOLD, 360.0)
	var c := CenterContainer.new()
	c.add_child(plate)
	v.add_child(c)
	var cls_l := UI.label(CardDB.class_title(str(sync.classes[canon])), 26, "italic", UI.BONE, 3, Color.BLACK)
	cls_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cls_l)
	return v
