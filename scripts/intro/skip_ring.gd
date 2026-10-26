class_name SkipRing
extends Control
## Bottom-right "hold to skip" ring: fills while Esc / Space / gamepad A / the mouse button / a finger is held,
## hint text fades in at the start and whenever a skip input is touched.

var progress := 0.0
var hint_alpha := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func set_state(p: float, hint: float) -> void:
	if not is_equal_approx(p, progress) or not is_equal_approx(hint, hint_alpha):
		progress = p
		hint_alpha = hint
		queue_redraw()


func _draw() -> void:
	if hint_alpha <= 0.01 and progress <= 0.0:
		return
	var touch := DisplayServer.is_touchscreen_available() and OS.has_feature("mobile")
	var r := size.y * (0.03 if touch else 0.022)
	var c := Vector2(size.x - r * 3.2, size.y - r * 2.8)
	var a := maxf(hint_alpha, 0.0)
	draw_arc(c, r, 0.0, TAU, 48, Color(IntroFonts.BONE.r, IntroFonts.BONE.g, IntroFonts.BONE.b, 0.22 * a), 2.0, true)
	if progress > 0.0:
		draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * progress, 48, IntroFonts.EMBER_HI, 3.0, true)
	var font := IntroFonts.body()
	var fs := int(size.y * (0.03 if touch else 0.019))
	if fs <= 0:
		return
	var txt := "Touch and hold to skip" if touch else "Hold Esc or the mouse button to skip"
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(c.x - r * 1.8 - w, c.y + fs * 0.3), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color(IntroFonts.BONE.r, IntroFonts.BONE.g, IntroFonts.BONE.b, 0.7 * a))
