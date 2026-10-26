class_name IntroSubtitles
extends Control
## Verse subtitles for the cinematic: bone serif lines in the shared SubtitleStyle (soft outline + feathered dark pool, no box). Respects Settings.subtitles (on/off); a bigger size on phones.

const SIZES: Array[float] = [0.03, 0.037, 0.046]  # fraction of the viewport height

var lines: Array[String] = []
var alpha := 0.0
var _target := 0.0
var _font: Font


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = IntroFonts.body()


func show_lines(l: Array) -> void:
	lines.clear()
	for s in l:
		lines.append(String(s))
	_target = 1.0
	queue_redraw()


func hide_lines() -> void:
	_target = 0.0


func enabled() -> bool:
	return Settings.subtitles


func _process(delta: float) -> void:
	var a := move_toward(alpha, _target, delta * 3.0)
	if a != alpha:
		alpha = a
		queue_redraw()
	if alpha <= 0.0 and _target <= 0.0 and not lines.is_empty():
		lines.clear()


func _draw() -> void:
	if lines.is_empty() or alpha <= 0.0 or not enabled():
		return
	var vp := size
	# sized against the old 2.39:1 frame height, so the text does not grow on taller screens
	var ref_h := IntroTimeline.text_height(vp.x, vp.y)
	var fs := int(round(ref_h * SIZES[2 if Settings.is_mobile() else 1]))
	if fs <= 0:
		return
	var lh := fs * 1.32
	var block := lh * lines.size()
	var bottom := vp.y - maxf(vp.y * 0.055, fs * 1.4)
	var y0 := bottom - block + lh * 0.78
	var widest := 0.0
	for l in lines:
		widest = maxf(widest, _font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var pc := Vector2(vp.x * 0.5, y0 - lh * 0.78 + block * 0.5)
	var ps := Vector2(widest + fs * 6.0, block + fs * 3.2)
	draw_texture_rect(IntroSubtitleStyle.pool(), Rect2(pc - ps * 0.5, ps), false, Color(1, 1, 1, alpha))
	for i in lines.size():
		IntroSubtitleStyle.draw_line_centered(self, _font, lines[i], vp.x * 0.5, y0 + i * lh, fs, IntroSubtitleStyle.TEXT, alpha)
