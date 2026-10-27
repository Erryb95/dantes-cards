class_name DuelChat
extends Control
## The mini chat of an online duel, in the bottom-left corner (clear of the board, the hand and the mana): a bronze
## "Chat" plate with an unread badge opens a parchment panel with the last messages (each with its sender), a text
## field with the gold-ink caret (Enter or Send sends; the phone's keyboard opens on it), a row of quick emotes and
## Mute. While the panel is closed new messages show for a few seconds above the plate, then fade.
##
## Transport: Nakama's direct-message channel between the two players (OnlineSession.open_chat / send_chat), content
## {"msg": text} or {"emote": id}. Emotes also pop up as a speech bubble by the sender's hero. Safety: at most 120
## characters, control characters and BBCode tags stripped (shown as plain text, never parsed), 1 message a second
## and 5 per 10 s from this player; Mute hides the opponent's messages and emotes.

signal emote_shown(side: int, text: String) ## the battle draws the bubble by the hero of `side` (0 me, 1 opponent)
signal send_requested(content: Dictionary) ## the battle sends it (OnlineSession.send_chat)

const MAX_LEN := ChatText.MAX_LEN
const KEEP := 6 ## messages kept in the panel
const FADE_AFTER := 6.0
const EMOTES := [["greetings", "Greetings"], ["well_played", "Well played"], ["thanks", "Thanks"], ["oops", "Oops"],
	["good_game", "Good game"]]

var my_id := ""
var names := {} ## user id -> display name
var muted := false
var _open := false
var _log: Array = [] ## [name, text, mine]
var _unread := 0
var _sent_at: Array[float] = [] ## when this player's last messages went out (rate limit)
var _panel: PanelContainer
var _lines: VBoxContainer
var _field: LineEdit
var _toggle: Button
var _badge: Label
var _peek: VBoxContainer ## the closed-panel preview of new messages
var _mute_b: Button
var _note: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := get_viewport_rect().size
	_toggle = UI.button("Chat", 150, 56)
	_toggle.name = "ChatToggle"
	_toggle.add_theme_font_size_override("font_size", 24)
	_toggle.pressed.connect(toggle)
	_toggle.position = Vector2(20, v.y - 76)
	add_child(_toggle)
	# The unread count on a red wax seal at the plate's corner.
	var seal := PanelContainer.new()
	seal.add_theme_stylebox_override("panel", UI.box(Color(0.62, 0.08, 0.04), UI.GOLD_DARK, 2, 17))
	seal.custom_minimum_size = Vector2(34, 34)
	seal.position = Vector2(128, -12)
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seal.visible = false
	_toggle.add_child(seal)
	_badge = UI.label("", 20, "title", UI.BONE, 3, Color(0.25, 0.02, 0.0))
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seal.add_child(_badge)
	_peek = VBoxContainer.new()
	_peek.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_peek.add_theme_constant_override("separation", 4)
	_peek.position = Vector2(20, v.y - 90)
	_peek.resized.connect(func(): _peek.position.y = get_viewport_rect().size.y - 90 - _peek.size.y)
	add_child(_peek)
	_build_panel(v)


func _build_panel(v: Vector2) -> void:
	_panel = PanelContainer.new()
	_panel.name = "ChatPanel"
	_panel.add_theme_stylebox_override("panel", UI.parchment_box(26, 18))
	_panel.custom_minimum_size = Vector2(470, 0)
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_panel.add_child(col)
	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override("separation", 2)
	_lines.custom_minimum_size = Vector2(0, 128)
	col.add_child(_lines)
	_note = UI.label("", 18, "italic", UI.INK_RED)
	_note.visible = false
	col.add_child(_note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	_field = UI.name_field("", "Say something...", MAX_LEN, 22)
	_field.name = "ChatField"
	_field.select_all_on_focus = false
	_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	_field.text_submitted.connect(func(_t: String): _send_text())
	row.add_child(_field)
	var send := UI.button("Send", 130, 56)
	send.add_theme_font_size_override("font_size", 22)
	send.pressed.connect(_send_text)
	row.add_child(send)
	var emotes := HFlowContainer.new()
	emotes.add_theme_constant_override("h_separation", 6)
	emotes.add_theme_constant_override("v_separation", 4)
	col.add_child(emotes)
	var plates: Array[Button] = [send]
	for e in EMOTES:
		var b := UI.button(e[1], 206, 52) # the painted plate (52 px and up)
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(_send_emote.bind(e[0]))
		emotes.add_child(b)
		plates.append(b)
	_mute_b = UI.button("Mute", 206, 52)
	_mute_b.add_theme_font_size_override("font_size", 20)
	plates.append(_mute_b)
	plates.append(_toggle)
	for b in plates:
		b.focus_mode = Control.FOCUS_NONE # Enter and Space belong to the text field, never to a plate
	_mute_b.pressed.connect(func():
		muted = not muted
		_mute_b.text = "Unmute" if muted else "Mute"
		_redraw())
	emotes.add_child(_mute_b)
	_panel.reset_size()
	_panel.position = Vector2(20, v.y - 90 - _panel.size.y)
	_panel.resized.connect(func(): _panel.position.y = get_viewport_rect().size.y - 90 - _panel.size.y)


func toggle() -> void:
	_open = not _open
	_panel.visible = _open
	_peek.visible = not _open
	if _open:
		_unread = 0
		_badge.get_parent().visible = false
		_redraw()
	else:
		_field.release_focus()


func is_open() -> bool:
	return _open


## Plain text only (ChatText): no control characters, no BBCode tags, at most MAX_LEN characters, trimmed.
static func clean(raw: String) -> String:
	return ChatText.clean(raw)


## True when this player may send now (1 a second, 5 in 10 s); else says why under the field.
func _may_send() -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	_sent_at = _sent_at.filter(func(t): return now - t < 10.0)
	if not _sent_at.is_empty() and now - _sent_at.back() < 1.0 or _sent_at.size() >= 5:
		_note.text = "Not so fast."
		_note.visible = true
		return false
	_note.visible = false
	_sent_at.append(now)
	return true


func _send_text() -> void:
	var text := clean(_field.text)
	if text == "" or not _may_send():
		return
	_field.text = ""
	send_requested.emit({"msg": text})


func _send_emote(id: String) -> void:
	if not _may_send():
		return
	send_requested.emit({"emote": id})


static func emote_text(id: String) -> String:
	for e in EMOTES:
		if e[0] == id:
			return e[1]
	return ""


## A message from the server (the channel echoes this player's own too).
func receive(m: Dictionary) -> void:
	var mine := str(m.get("user_id", "")) == my_id
	if muted and not mine:
		return
	var c: Variant = m.get("content", {})
	if not (c is Dictionary):
		return
	var who := str(names.get(str(m.get("user_id", "")), m.get("name", "")))
	who = clean(who).left(24)
	var text := ""
	if c.has("emote"):
		text = emote_text(str(c.emote))
		if text == "":
			return
		emote_shown.emit(0 if mine else 1, text)
	else:
		text = clean(str(c.get("msg", "")))
	if text == "":
		return
	_log.append([who, text, mine])
	while _log.size() > KEEP:
		_log.pop_front()
	if _open:
		_redraw()
	elif not mine:
		_unread += 1
		_badge.text = str(mini(_unread, 9))
		_badge.get_parent().visible = true
		_peek_line(who, text)
	if not mine:
		Sfx.play("tick", -8.0)


func _redraw() -> void:
	for c in _lines.get_children():
		c.queue_free()
	for e in _log:
		if muted and not e[2]:
			continue
		_lines.add_child(_line(e[0], e[1], e[2]))


func _line(who: String, text: String, mine: bool) -> Label:
	var l := UI.label("%s:  %s" % [who, text], 20, "body", UI.INK if not mine else Color(0.3, 0.18, 0.06))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(418, 0)
	if not mine:
		l.add_theme_color_override("font_color", UI.INK_RED.darkened(0.1))
	return l


## Closed panel: the message shows on a parchment slip above the Chat plate, then fades.
func _peek_line(who: String, text: String) -> void:
	var p := UI.parchment_label("%s:  %s" % [who, text], 20, "italic", UI.INK, 430.0, 20, 8)
	_peek.add_child(p)
	while _peek.get_child_count() > 3:
		_peek.get_child(0).queue_free()
	var t := p.create_tween()
	t.tween_interval(FADE_AFTER)
	t.tween_property(p, "modulate:a", 0.0, 1.0)
	t.tween_callback(p.queue_free)


var _lift := 0.0 ## how far the panel is raised above a phone's on-screen keyboard


## On a phone the open panel rises above the on-screen keyboard while its field is being typed in.
func _process(_delta: float) -> void:
	if not _open:
		return
	var want := 0.0
	var kb := DisplayServer.virtual_keyboard_get_height() if DisplayServer.has_feature(
		DisplayServer.FEATURE_VIRTUAL_KEYBOARD) else 0
	if kb > 0 and _field.has_focus():
		var vs := get_viewport_rect().size
		var win := DisplayServer.window_get_size()
		want = kb * vs.y / maxf(1.0, float(win.y)) - 70.0
		want = maxf(0.0, want)
	if absf(want - _lift) > 0.5:
		_lift = lerpf(_lift, want, 0.35)
		_panel.position.y = get_viewport_rect().size.y - 90 - _panel.size.y - _lift


## Esc / back: closes the panel first (the battle asks before opening its pause menu).
func close_if_open() -> bool:
	if _open:
		toggle()
		return true
	return false
