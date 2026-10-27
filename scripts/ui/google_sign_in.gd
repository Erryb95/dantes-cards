class_name GoogleSignInPanel
extends Control
## "Sign in with Google", painted: Google's device flow shows a short code; the player opens google.com/device on any
## phone or computer, enters it and approves. The page and the code are inked big on parchment, with Copy code, Open
## the page and Cancel; "Waiting for Google..." until the approval comes back, then the account is linked
## (OnlineSession.sign_in_google) and the panel says who is signed in. Refusals (a Google account that is not a test
## player while the app is in testing, an expired code) are said plainly; Play as guest stays available.
##
## Opened over a "Dialog" (the profile): while it is up, that dialog's "cancel" (Esc, the back gesture) is our Cancel.

signal finished(ok: bool)

var _auth: GoogleAuth
var _sheet: VBoxContainer
var _row: HBoxContainer
var _status: Label
var _dots := 0.0
var _waiting := false
var _host: Control
var _host_cancel: Variant = null


static func open(host: Control) -> GoogleSignInPanel:
	var p := GoogleSignInPanel.new()
	p._host = host
	host.add_child(p)
	return p


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 10
	if _host != null and _host.has_meta("cancel"):
		_host_cancel = _host.get_meta("cancel")
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	center.add_child(v)
	v.add_child(UI.banner("Sign in with Google", 50, UI.GOLD, 0.0, 0.0, 1.8))
	var paper := PanelContainer.new()
	paper.add_theme_stylebox_override("panel", UI.parchment_box(70, 36))
	paper.custom_minimum_size = Vector2(820, 0)
	paper.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(paper)
	_sheet = VBoxContainer.new()
	_sheet.add_theme_constant_override("separation", 10)
	paper.add_child(_sheet)
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 20)
	v.add_child(_row)
	_auth = GoogleAuth.new(Online.config)
	add_child(_auth)
	_start()


func _line(text: String, size: int, kind := "italic", color := UI.INK) -> Label:
	var l := UI.label(text, size, kind, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(680, 0)
	_sheet.add_child(l)
	return l


func _clear() -> void:
	for c in _sheet.get_children():
		c.queue_free()


func _buttons(list: Array) -> void:
	for c in _row.get_children():
		c.queue_free()
	var made: Array[Button] = []
	for b in list:
		var btn := UI.button(b[0], 280, 72)
		btn.add_theme_font_size_override("font_size", 28)
		btn.pressed.connect(b[1])
		_row.add_child(btn)
		made.append(btn)
	if made.is_empty():
		return
	UI.even_text(made)
	if _host != null:
		_host.set_meta("cancel", made[-1])


func _start() -> void:
	_clear()
	_status = _line("Asking Google for a code...", 30)
	_buttons([["Cancel", _close.bind(false)]])
	var r := await _auth.begin()
	if not is_inside_tree():
		return
	if r.has("error"):
		_fail(str(r.error))
		return
	_clear()
	_line("On any phone or computer, open", 28)
	_line(_auth.verification_url.replace("https://", "").replace("www.", ""), 40, "title", UI.INK_RED)
	_line("and enter this code:", 28)
	var code := _line(_auth.user_code, 76, "title", UI.INK_RED)
	code.name = "Code"
	_status = _line("Waiting for Google", 28)
	if Settings.is_desktop():
		DisplayServer.clipboard_set(_auth.user_code)
	_buttons([["Copy code", func():
			DisplayServer.clipboard_set(_auth.user_code)
			Sfx.play("tick", -6.0)], ["Open the page", func(): OS.shell_open(_auth.verification_url)],
		["Cancel", _close.bind(false)]])
	_waiting = true
	var got := await _auth.wait()
	_waiting = false
	if not is_inside_tree() or got.has("cancelled"):
		return
	if got.has("error"):
		_fail(str(got.error))
		return
	_clear()
	_status = _line("Linking your account...", 30)
	_buttons([])
	var err := await Online.sign_in_google(str(got.id_token), got)
	if not is_inside_tree():
		return
	if err != "":
		_fail(err)
		return
	_clear()
	_line("Signed in as", 28)
	var who := str(got.get("name", "")) if str(got.get("name", "")) != "" else str(got.get("email", ""))
	_line(who, 40, "title", UI.INK_RED)
	Sfx.play("ui_confirm", -4.0)
	_buttons([["Done", _close.bind(true)]])


func _fail(message: String) -> void:
	_clear()
	_line(message, 28, "italic", UI.INK_RED)
	Sfx.play("ui_back", -6.0)
	_buttons([["Try again", _start], ["Close", _close.bind(false)]])


func _process(delta: float) -> void:
	if _waiting and _status != null and is_instance_valid(_status):
		_dots += delta
		_status.text = "Waiting for Google" + ".".repeat(int(_dots * 2.0) % 4)


func _close(ok: bool) -> void:
	_auth.cancel()
	if _host != null:
		if _host_cancel != null and is_instance_valid(_host_cancel):
			_host.set_meta("cancel", _host_cancel)
	finished.emit(ok)
	queue_free()
