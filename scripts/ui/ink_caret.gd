class_name InkCaret
extends Control
## The painted caret of a LineEdit: a tapered stroke of gold ink with a soft ember glow that breathes in and out
## (the engine's caret is a flat bar that blinks), and a gilded ink underline under the selected text in place of
## the engine's flat selection box. `InkCaret.attach(line_edit)` hides the engine's caret and selection and adds one.
## The LineEdit must be left-aligned.

const INK := Color(1.0, 0.8, 0.42) ## the gold of the stroke
const RIM := Color(0.16, 0.06, 0.02, 0.9) ## the dark edge that keeps it legible on the bronze field
const GLOW := Color(1.0, 0.55, 0.15, 0.35)

var _le: LineEdit
var _t := 0.0


## Hides `le`'s own caret and selection box and paints this one over it.
static func attach(le: LineEdit) -> InkCaret:
	le.add_theme_color_override("caret_color", Color(0, 0, 0, 0))
	le.add_theme_color_override("selection_color", Color(0, 0, 0, 0))
	var c := InkCaret.new()
	c._le = le
	c.name = "InkCaret"
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	le.add_child(c, false, Node.INTERNAL_MODE_BACK)
	return c


func _process(delta: float) -> void:
	_t += delta
	visible = _le.has_focus() and _le.editable
	if visible:
		queue_redraw()


func _draw() -> void:
	var font := _le.get_theme_font("font")
	var fs := _le.get_theme_font_size("font_size")
	var sb := _le.get_theme_stylebox("focus" if _le.has_focus() else "normal")
	var left := sb.get_margin(SIDE_LEFT) + _le.get_scroll_offset()
	var mid := size.y / 2.0
	var h := font.get_height(fs) * 0.92
	var room := Rect2(sb.get_margin(SIDE_LEFT) - 2.0, 0, size.x - sb.get_margin(SIDE_LEFT) - sb.get_margin(SIDE_RIGHT) + 4.0,
		size.y)
	# The selection: a tapered gold underline under the selected letters (lit like the caret, never a flat box).
	if _le.has_selection():
		var a := left + _x_of(font, fs, _le.get_selection_from_column())
		var b := left + _x_of(font, fs, _le.get_selection_to_column())
		a = clampf(a, room.position.x, room.end.x)
		b = clampf(b, room.position.x, room.end.x)
		if b - a > 2.0:
			_stroke(Vector2(a, mid + h * 0.42), Vector2(b, mid + h * 0.42), 3.0, 0.9)
	# The caret: breathes between half and full strength instead of blinking off.
	var x := left + _x_of(font, fs, _le.get_caret_column())
	if x < room.position.x or x > room.end.x:
		return
	var k := 0.55 + 0.45 * (0.5 + 0.5 * cos(_t * TAU / 1.1))
	draw_texture_rect(UI.dot_texture(), Rect2(x - h * 0.35, mid - h * 0.7, h * 0.7, h * 1.4), false,
		Color(GLOW, GLOW.a * k))
	_stroke(Vector2(x, mid - h / 2.0), Vector2(x, mid + h / 2.0), 3.4, k)


## The width of the first `col` characters.
func _x_of(font: Font, fs: int, col: int) -> float:
	return font.get_string_size(_le.text.substr(0, col), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


## A pen stroke from `a` to `b`: pointed at both ends, `w` px at its widest, a dark rim under gold ink.
func _stroke(a: Vector2, b: Vector2, w: float, alpha: float) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	for pass_ in [[w / 2.0 + 1.4, Color(RIM, RIM.a * alpha)], [w / 2.0, Color(INK, alpha)]]:
		var half: float = pass_[0]
		var pts := PackedVector2Array()
		for i in 9: # one side, swelling in the middle like a nib stroke
			var t := i / 8.0
			pts.append(a.lerp(b, t) + n * half * sin(t * PI) + (-d if i == 0 else d if i == 8 else Vector2.ZERO) * 1.0)
		for i in range(7, 0, -1):
			var t := i / 8.0
			pts.append(a.lerp(b, t) - n * half * sin(t * PI))
		draw_colored_polygon(pts, pass_[1])
		pts.append(pts[0])
		draw_polyline(pts, pass_[1], 1.0, true) # polygons are not antialiased: a smooth edge around it
	# A brighter bead of wet ink along the middle.
	draw_line(a.lerp(b, 0.3), a.lerp(b, 0.7), Color(1.0, 0.95, 0.75, 0.7 * alpha), 1.0, true)
