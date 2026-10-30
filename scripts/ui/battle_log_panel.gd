class_name BattleLogPanel
extends Control
## The whole match history (BattleLog) over the battle: a sheet of parchment per turn in a painted scroll, each turn
## headed "Turn 7 — Enrico" on an engraved plaque, each action a portrait (BattlePanels.make_icon) beside its line and
## what it caused, in its side's ink. Opened from the log strip's disc and from the result screens; Done, a press
## outside, Esc or the Android back gesture closes it. It is built when opened (nothing runs while the match plays)
## and follows the log while it stays open.

const MARGIN := 80.0
const ICON := 64.0

var history: BattleLog
var _list: VBoxContainer
var _scroll: ScrollContainer
var _w := 900.0
var _dirty := false


static func open(parent: Node, p_log: BattleLog) -> BattleLogPanel:
	var old := parent.get_node_or_null("BattleLog")
	if old != null:
		old.queue_free()
	var p := BattleLogPanel.new()
	p.history = p_log
	parent.add_child(p)
	return p


func _ready() -> void:
	name = "BattleLog"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 105
	var vs := get_viewport_rect().size
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close())
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	var s := UI.frame_box("panel_frame_filled", 96, 0,
		UI.box(Color(0.09, 0.05, 0.04, 0.97), UI.GOLD, 3, 14, Color(0, 0, 0, 0.7), 30))
	s.content_margin_left = MARGIN
	s.content_margin_right = MARGIN
	s.content_margin_top = 60
	s.content_margin_bottom = 70
	panel.add_theme_stylebox_override("panel", s)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	v.add_child(UI.banner("Battle log", 44, UI.GOLD, 0.0, 0.0, 1.8))
	_w = clampf(vs.x - 2.0 * MARGIN - 160.0, 700.0, 1100.0)
	_scroll = ScrollContainer.new()
	_scroll.name = "Turns"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(_w + 30.0, clampf(vs.y - 60.0 - 70.0 - 80.0 - 12.0 - 76.0 - 12.0 - 70.0, 420.0, 900.0))
	UI.paint_scroll(_scroll, 22)
	v.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_scroll.add_child(_list)
	var done := UI.button("Done", 300, 76)
	done.pressed.connect(close)
	var dc := CenterContainer.new()
	dc.add_child(done)
	v.add_child(dc)
	_fill()
	if history != null:
		history.entry_added.connect(_on_log)
		history.entry_changed.connect(_on_log)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)


func close() -> void:
	queue_free()


func _on_log(_e: Dictionary) -> void:
	if not _dirty:
		_dirty = true
		_refill.call_deferred()


func _refill() -> void:
	_dirty = false
	var bottom := _scroll.scroll_vertical >= int(_scroll.get_v_scroll_bar().max_value - _scroll.size.y) - 8
	for c in _list.get_children():
		c.free()
	_fill(bottom)


## Every turn of the log, oldest first, scrolled to the newest.
func _fill(to_end: bool = true) -> void:
	var groups: Array = history.groups() if history != null else []
	if groups.is_empty():
		var empty := UI.parchment_label("Nothing has happened yet.", 28, "italic", UI.INK, 0.0, 40, 16)
		_list.add_child(empty)
	for g in groups:
		var head := CenterContainer.new()
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.custom_minimum_size = Vector2(_w, 0)
		var tint := UI.GOLD if int(g.turn) == 0 or int(g.side) == 0 else Color(1.0, 0.72, 0.6)
		var plate := UI.plaque_label("", 28, "title", tint, 0.0, 40, 8)
		(plate.get_node("Text") as Label).text = history.turn_title(int(g.turn), int(g.side))
		head.add_child(plate)
		_list.add_child(head)
		var sheet := PanelContainer.new()
		sheet.add_theme_stylebox_override("panel", UI.parchment_box(44, 24))
		sheet.custom_minimum_size = Vector2(_w, 0)
		sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 14)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sheet.add_child(col)
		for e in g.entries:
			col.add_child(_row(e))
		_list.add_child(sheet)
	if to_end:
		_scroll_to_end.call_deferred()


func _scroll_to_end() -> void:
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


## One action: its portrait, its line in the side's ink, what it caused under it.
func _row(e: Dictionary) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := BattlePanels.make_icon(e, ICON)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(icon)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var inner := _w - 88.0 - ICON - 18.0
	var head := UI.label("", 28, "title", BattlePanels.side_ink(int(e.side)))
	head.text = history.headline(e) + ("   · " + Loc.t("Ruse") if e.ruse else "")
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.custom_minimum_size = Vector2(inner, 0)
	v.add_child(head)
	for t in history.lines(e):
		var l := UI.label("", 25, "italic", UI.INK)
		l.text = t
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(inner, 0)
		v.add_child(l)
	return h
