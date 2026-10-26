class_name GateInscription
extends Control
## The nine lines over the Gate of Hell (Canto III), carved into the rock letter by letter in step with the
## narration: each letter ignites white-hot, cools to ember orange and stays glowing in its groove. Chiselled look =
## dark upper-left lip + pale lower-right edge + ember fill, plus an additive bloom pass and sparks at the chisel.
## Drawn in the player's 2.39:1 text box (over the full-screen picture); the player feeds it time and the shot alpha through set_state().

const COOL := Color(0.95, 0.46, 0.15)
const HOT := Color(1.0, 0.9, 0.7)
const HEAT_S := 2.6          # seconds a freshly carved letter takes to cool down
const LEAD := 0.25           # carving starts this long before the word is spoken

var voice_t := 0.0           # absolute time the narration of the gate starts
var shot_end := 0.0          # absolute end of the gate shot (the text sinks out with the crossfade)
var _now := 0.0
var _alpha := 0.0
var _font: Font
var _fs := 0
var _xs: Array[PackedFloat32Array] = []   # per line: x offset of every prefix (len+1 entries), line width last
var _widths: Array[float] = []
var _bloom: Control
var _sparks: CPUParticles2D
var _halo: GradientTexture2D


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = IntroFonts.caps()
	_halo = GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.4, Color(1, 1, 1, 0.35))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	_halo.gradient = g
	_halo.fill = GradientTexture2D.FILL_RADIAL
	_halo.fill_from = Vector2(0.5, 0.5)
	_halo.fill_to = Vector2(1.0, 0.5)
	_halo.width = 128
	_halo.height = 128
	_bloom = Control.new()
	_bloom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bloom.set_anchors_preset(Control.PRESET_FULL_RECT)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_bloom.material = add
	_bloom.draw.connect(_draw_bloom)
	add_child(_bloom)
	_sparks = CPUParticles2D.new()
	_sparks.amount = 36
	_sparks.lifetime = 1.6
	_sparks.emitting = false
	_sparks.direction = Vector2(0.2, -1.0)
	_sparks.spread = 55.0
	_sparks.gravity = Vector2(0, -26)
	_sparks.initial_velocity_min = 18.0
	_sparks.initial_velocity_max = 70.0
	_sparks.scale_amount_min = 0.5
	_sparks.scale_amount_max = 1.3
	_sparks.texture = preload("res://scripts/intro/ember_spark.tres")
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 0.95, 0.75, 1))
	grad.add_point(0.35, Color(1, 0.55, 0.15, 0.9))
	grad.set_color(grad.get_point_count() - 1, Color(0.5, 0.08, 0.0, 0))
	_sparks.color_ramp = grad
	var sm := CanvasItemMaterial.new()
	sm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_sparks.material = sm
	add_child(_sparks)


func set_state(now: float, alpha: float) -> void:
	_now = now
	_alpha = alpha
	visible = alpha > 0.001 and now >= voice_t - 1.0
	if visible:
		queue_redraw()
		_bloom.queue_redraw()


## Seconds after voice start at which letter `ci` of line `li` is carved.
func letter_time(li: int, ci: int) -> float:
	var span: Vector2 = IntroTimeline.INSCRIPTION_TIMES[li]
	var n := maxi(String(IntroTimeline.INSCRIPTION[li]).length() - 1, 1)
	return span.x - LEAD + (span.y - span.x + LEAD) * float(ci) / float(n)


func _layout(fs: int) -> void:
	_fs = fs
	_xs.clear()
	_widths.clear()
	for l in IntroTimeline.INSCRIPTION:
		var xs := PackedFloat32Array()
		for i in l.length() + 1:
			xs.append(_font.get_string_size(l.left(i), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		_xs.append(xs)
		_widths.append(xs[xs.size() - 1])


## Top-left of line `li` and its font size: the block is centred in the upper part of the frame.
func _metrics() -> Dictionary:
	var fs := maxi(int(size.y * 0.043), 6)
	if fs != _fs or _xs.is_empty():
		_layout(fs)
	var lh := fs * 1.5
	var n := IntroTimeline.INSCRIPTION.size()
	var gaps := 2.0 * fs * 0.55
	var block := lh * n + gaps
	return {"fs": fs, "lh": lh, "top": size.y * 0.06, "block": block}


func _line_pos(li: int, m: Dictionary) -> Vector2:
	var tercet_gap := float(li / 3) * float(m["fs"]) * 0.55
	var fs: float = m["fs"]
	return Vector2((size.x - _widths[li]) * 0.5, float(m["top"]) + fs + float(m["lh"]) * li + tercet_gap)


func _heat(li: int, ci: int) -> float:
	var age := _now - voice_t - letter_time(li, ci)
	if age < 0.0:
		return -1.0
	return clampf(1.0 - age / (HEAT_S * (2.4 if li == IntroTimeline.INSCRIPTION.size() - 1 else 1.0)), 0.0, 1.0)


func _draw() -> void:
	if size.x < 10.0 or _alpha <= 0.001:
		return
	var m := _metrics()
	var fs: int = m["fs"]
	var t := _now - voice_t
	# Out with the crossfade into the next shot.
	var out := 1.0 - smoothstep(0.0, 1.0, (_now - (shot_end - 3.4)) / 2.2)
	var a := _alpha * out
	if a <= 0.001:
		return
	# Soft dark slab behind the block so the letters read on any part of the rock.
	var top: float = m["top"]
	var block: float = m["block"]
	var wmax := 0.0
	for w in _widths:
		wmax = maxf(wmax, w)
	var slab_a := smoothstep(-0.5, 2.5, t) * a * 0.5
	var pad := fs * 2.2
	draw_texture_rect(_halo, Rect2((size.x - wmax) * 0.5 - pad * 1.5, top - pad * 0.5, wmax + pad * 3.0, block + pad * 1.6),
		false, Color(0, 0, 0, slab_a))
	var flick := 0.93 + 0.07 * sin(_now * 3.1) * sin(_now * 1.3 + 1.0)
	var lip := Color(0, 0, 0, 0.8 * a)
	var edge := Color(0.78, 0.7, 0.58, 0.22 * a)
	var head := Vector2(-1, -1)
	for li in IntroTimeline.INSCRIPTION.size():
		var line: String = IntroTimeline.INSCRIPTION[li]
		var p := _line_pos(li, m)
		var xs := _xs[li]
		# characters that are already fully cooled are drawn as one string
		var settled := 0
		var shown := 0
		for ci in line.length():
			var h := _heat(li, ci)
			if h >= 0.0:
				shown = ci + 1
				if h <= 0.0 and settled == ci:
					settled = ci + 1
		if shown == 0:
			continue
		var sd := Vector2(fs * 0.04, fs * 0.05)
		if settled > 0:
			var txt := line.left(settled)
			draw_string(_font, p + sd, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, edge)
			draw_string(_font, p - sd, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, lip)
			draw_string(_font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(COOL.r, COOL.g, COOL.b, 0.93 * a * flick))
		for ci in range(settled, shown):
			var h := _heat(li, ci)
			var ch := line.substr(ci, 1)
			if ch == " ":
				continue
			var age := t - letter_time(li, ci)
			var appear := clampf(age / 0.18, 0.0, 1.0)
			var cp := p + Vector2(xs[ci], 0)
			var col := COOL.lerp(HOT, pow(h, 1.4))
			col.a = a * appear * flick * lerpf(0.93, 1.0, h)
			draw_string(_font, cp + sd, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(edge, edge.a * appear))
			draw_string(_font, cp - sd, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(lip, lip.a * appear))
			draw_string(_font, cp, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			if h > 0.7:
				head = cp + Vector2(xs[ci + 1] - xs[ci], 0) * 0.5 + Vector2(0, -fs * 0.35)
	# sparks follow the chisel while a line is being carved
	_sparks.emitting = head.x >= 0.0 and a > 0.2
	if head.x >= 0.0:
		_sparks.position = head


func _draw_bloom() -> void:
	if size.x < 10.0 or _alpha <= 0.001:
		return
	var m := _metrics()
	var fs: int = m["fs"]
	var out := 1.0 - smoothstep(0.0, 1.0, (_now - (shot_end - 3.4)) / 2.2)
	var a := _alpha * out
	if a <= 0.001:
		return
	var o := fs * 0.07
	var offs: Array[Vector2] = [Vector2(o, 0), Vector2(-o, 0), Vector2(0, o), Vector2(0, -o)]
	for li in IntroTimeline.INSCRIPTION.size():
		var line: String = IntroTimeline.INSCRIPTION[li]
		var p := _line_pos(li, m)
		var xs := _xs[li]
		var settled := 0
		var shown := 0
		for ci in line.length():
			var h := _heat(li, ci)
			if h >= 0.0:
				shown = ci + 1
				if h <= 0.0 and settled == ci:
					settled = ci + 1
		if shown == 0:
			continue
		# a faint steady glow in the groove of the whole carved part
		var base := line.left(shown)
		for d in offs:
			_bloom.draw_string(_font, p + d, base, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.9, 0.3, 0.06, 0.035 * a))
		for ci in range(settled, shown):
			var h := _heat(li, ci)
			if h <= 0.0:
				continue
			var ch := line.substr(ci, 1)
			if ch == " ":
				continue
			var cp := p + Vector2(xs[ci], 0)
			var col := Color(1.0, 0.55, 0.18, 0.2 * h * a)
			for d in offs:
				_bloom.draw_string(_font, cp + d * 1.6, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			if h > 0.8:
				var c := cp + Vector2(xs[ci + 1] - xs[ci], 0) * 0.5 + Vector2(0, -fs * 0.35)
				var r := fs * 2.4 * (0.6 + 0.4 * h)
				_bloom.draw_texture_rect(_halo, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false,
					Color(1.0, 0.5, 0.15, 0.42 * (h - 0.8) / 0.2 * a))
