class_name TitleReveal
extends Control
## DANTE'S INFERNO / THE CARD GAME: smoke rises in the dark, the letters ignite one after another (white-hot flash, a burst of
## ember sparks, then they settle to bone), a rule is drawn under them, and when the thunder strikes a vermilion
## glint sweeps across the title with a short deep-red pulse. Nothing here ever fills the screen with grey: every
## light is additive on black. "THE CARD GAME" fades in under the rule once the title has lit.

const BONE := Color(0.93, 0.88, 0.76)
const HOT := Color(1.0, 0.93, 0.78)
const VERMILION := Color(1.0, 0.2, 0.07)
const FIRST := 1.3          # seconds into the title shot: first letter ignites
const STEP := 0.15          # between letters
const GLINT_S := 1.1        # duration of the vermilion sweep

var shot_start := 0.0
var shot_dur := 9.0
var _now := 0.0
var _font: Font
var _fs := 0
var _xs := PackedFloat32Array()
var _smoke: ColorRect
var _smoke_mat: ShaderMaterial
var _add: Control
var _halo: GradientTexture2D
var _bursts: Array[CPUParticles2D] = []
var _fired := {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = IntroFonts.caps()
	_halo = GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.45, Color(1, 1, 1, 0.3))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	_halo.gradient = g
	_halo.fill = GradientTexture2D.FILL_RADIAL
	_halo.fill_from = Vector2(0.5, 0.5)
	_halo.fill_to = Vector2(1.0, 0.5)
	_halo.width = 128
	_halo.height = 128
	_smoke = ColorRect.new()
	_smoke.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_smoke.set_anchors_preset(Control.PRESET_FULL_RECT)
	_smoke_mat = ShaderMaterial.new()
	_smoke_mat.shader = preload("res://scripts/intro/intro_smoke.gdshader")
	_smoke.material = _smoke_mat
	add_child(_smoke)
	_add = Control.new()
	_add.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add.set_anchors_preset(Control.PRESET_FULL_RECT)
	var am := CanvasItemMaterial.new()
	am.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_add.material = am
	_add.draw.connect(_draw_add)
	add_child(_add)
	for i in IntroTimeline.TITLE.length():
		_bursts.append(_make_burst())


func _make_burst() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = 14
	p.lifetime = 1.5
	p.one_shot = true
	p.explosiveness = 0.92
	p.emitting = false
	p.direction = Vector2(0, -1)
	p.spread = 70.0
	p.gravity = Vector2(0, -30)
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 190.0
	p.damping_min = 40.0
	p.damping_max = 90.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.5
	p.texture = preload("res://scripts/intro/ember_spark.tres")
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 0.97, 0.8, 1))
	grad.add_point(0.25, Color(1, 0.6, 0.2, 0.95))
	grad.set_color(grad.get_point_count() - 1, Color(0.55, 0.08, 0.0, 0))
	p.color_ramp = grad
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = m
	add_child(p)
	return p


func set_state(now: float) -> void:
	_now = now
	var t := now - shot_start
	visible = t >= -0.1 and t <= shot_dur + 0.1
	if not visible:
		return
	var amt := smoothstep(0.2, 2.5, t) * (1.0 - smoothstep(6.3, shot_dur - 0.4, t))
	_smoke_mat.set_shader_parameter("amount", amt)
	_smoke_mat.set_shader_parameter("time", now)
	_smoke_mat.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
	_smoke_mat.set_shader_parameter("band_y", 0.52)
	queue_redraw()
	_add.queue_redraw()
	_fire_bursts(t)


func _metrics() -> void:
	var fs := maxi(int(minf(IntroTimeline.text_height(size.x, size.y), size.x / 2.1) * 0.14), 8)  # as in the old 2.39 frame, fits 4:3
	if fs == _fs and not _xs.is_empty():
		return
	_fs = fs
	_xs = PackedFloat32Array()
	for i in IntroTimeline.TITLE.length() + 1:
		_xs.append(_font.get_string_size(IntroTimeline.TITLE.left(i), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)


func _origin() -> Vector2:
	_metrics()
	var w := _xs[_xs.size() - 1]
	return Vector2((size.x - w) * 0.5, size.y * 0.5 + _fs * 0.3)


func _ignite_time(i: int) -> float:
	# light jitter so the ignition feels hand-lit, not metronomic
	return FIRST + i * STEP + 0.05 * sin(i * 12.9898)


func _letter_center(i: int) -> Vector2:
	var o := _origin()
	return Vector2(o.x + (_xs[i] + _xs[i + 1]) * 0.5, o.y - _fs * 0.34)


func _fire_bursts(t: float) -> void:
	_metrics()
	for i in IntroTimeline.TITLE.length():
		if IntroTimeline.TITLE[i] == " " or _fired.has(i):
			continue
		if t >= _ignite_time(i):
			_fired[i] = true
			var b := _bursts[i]
			b.position = _letter_center(i)
			b.restart()
			b.emitting = true


func _out_alpha(t: float) -> float:
	return 1.0 - smoothstep(shot_dur - 2.3, shot_dur - 0.5, t)


func _glint_pos(t: float) -> float:
	return (t - IntroTimeline.TITLE_THUNDER) / GLINT_S   # 0..1 across the title


func _draw() -> void:
	if size.x < 10.0:
		return
	var t := _now - shot_start
	var o := _origin()
	var out := _out_alpha(t)
	if out <= 0.0:
		return
	var tw := _xs[_xs.size() - 1]
	var gp := _glint_pos(t)
	# the thunder rattles the title for a moment
	var shake := Vector2.ZERO
	var th := t - IntroTimeline.TITLE_THUNDER
	if th > 0.0 and th < 0.7:
		var k := (1.0 - th / 0.7)
		shake = Vector2(sin(th * 97.0), cos(th * 83.0)) * k * k * _fs * 0.012
	for i in IntroTimeline.TITLE.length():
		var ch := IntroTimeline.TITLE.substr(i, 1)
		if ch == " ":
			continue
		var age := t - _ignite_time(i)
		if age < 0.0:
			continue
		var appear := clampf(age / 0.22, 0.0, 1.0)
		var heat := clampf(1.0 - age / 1.1, 0.0, 1.0)
		var col := BONE.lerp(HOT, heat * heat)
		# vermilion glint: gaussian around the sweep position
		var lx := (_xs[i] + _xs[i + 1]) * 0.5 / tw
		var gl := exp(-pow((lx - (gp * 1.5 - 0.25)) / 0.11, 2.0)) if gp > -0.2 and gp < 1.2 else 0.0
		col = col.lerp(Color(1.0, 0.55, 0.38), gl * 0.85)
		col.a = appear * out
		var p := o + Vector2(_xs[i], 0) + shake
		draw_string(_font, p + Vector2(_fs * 0.012, _fs * 0.016), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, Color(0, 0, 0, 0.7 * appear * out))
		draw_string(_font, p, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, col)
	_draw_subtitle(t, o, out, shake)


## "THE CARD GAME", widely tracked, under the rule: fades in when the rule is drawn.
func _draw_subtitle(t: float, o: Vector2, out: float, shake: Vector2) -> void:
	var start := FIRST + IntroTimeline.TITLE.length() * STEP + 0.4
	var a := smoothstep(start, start + 1.6, t) * out
	if a <= 0.0:
		return
	var sfs := maxi(int(_fs * 0.3), 8)
	var track := sfs * 0.42
	var sub := IntroTimeline.TITLE_SUB
	var widths := PackedFloat32Array()
	var total := 0.0
	for i in sub.length():
		var cw := _font.get_string_size(sub[i], HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x
		widths.append(cw)
		total += cw + (track if i < sub.length() - 1 else 0.0)
	var x := (size.x - total) * 0.5
	var y := o.y + _fs * 0.2 + sfs * 1.9
	for i in sub.length():
		if sub[i] != " ":
			draw_string(_font, Vector2(x, y) + shake + Vector2(sfs * 0.03, sfs * 0.04), sub[i], HORIZONTAL_ALIGNMENT_LEFT, -1,
				sfs, Color(0, 0, 0, 0.6 * a))
			draw_string(_font, Vector2(x, y) + shake, sub[i], HORIZONTAL_ALIGNMENT_LEFT, -1, sfs,
				Color(IntroFonts.BONE.r, IntroFonts.BONE.g, IntroFonts.BONE.b, 0.9 * a))
		x += widths[i] + track


func _draw_add() -> void:
	if size.x < 10.0:
		return
	var t := _now - shot_start
	var out := _out_alpha(t)
	if out <= 0.0:
		return
	var o := _origin()
	var tw := _xs[_xs.size() - 1]
	var gp := _glint_pos(t)
	for i in IntroTimeline.TITLE.length():
		var ch := IntroTimeline.TITLE.substr(i, 1)
		if ch == " ":
			continue
		var age := t - _ignite_time(i)
		if age < 0.0:
			continue
		var heat := clampf(1.0 - age / 1.3, 0.0, 1.0)
		var lx := (_xs[i] + _xs[i + 1]) * 0.5 / tw
		var gl := exp(-pow((lx - (gp * 1.5 - 0.25)) / 0.11, 2.0)) if gp > -0.2 and gp < 1.2 else 0.0
		var c := _letter_center(i)
		# ignition flare: a hot bloom that dies down in a second
		if heat > 0.0:
			var r := _fs * (0.3 + 0.55 * heat)
			_add.draw_texture_rect(_halo, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false,
				Color(1.0, 0.5, 0.15, 0.45 * heat * heat * out))
		# steady faint ember glow under every letter, stronger on the glint
		var rr := _fs * 0.75
		_add.draw_texture_rect(_halo, Rect2(c - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false,
			Color(0.9, 0.22, 0.06, (0.07 + 0.8 * gl) * out * clampf(age / 0.5, 0.0, 1.0)))
		if gl > 0.01:
			_add.draw_string(_font, o + Vector2(_xs[i], 0), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs,
				Color(VERMILION.r, VERMILION.g, VERMILION.b, 0.8 * gl * out))
	# the rule under the title is drawn from the centre outwards after the last letter
	var ry := o.y + _fs * 0.2
	var rk := smoothstep(FIRST + IntroTimeline.TITLE.length() * STEP, FIRST + IntroTimeline.TITLE.length() * STEP + 1.4, t)
	if rk > 0.0:
		var half := size.x * 0.2 * rk
		var cx := size.x * 0.5
		var rc := Color(IntroFonts.EMBER.r, IntroFonts.EMBER.g, IntroFonts.EMBER.b, 0.8 * out)
		_add.draw_line(Vector2(cx - half, ry), Vector2(cx - 12.0, ry), rc, 1.0)
		_add.draw_line(Vector2(cx + 12.0, ry), Vector2(cx + half, ry), rc, 1.0)
		IntroFonts.diamond(_add, Vector2(cx, ry), 4.0, rc)
	# vermilion pulse at the thunder: a deep red bloom around the title, dying in under a second, no flat fill
	var th := t - IntroTimeline.TITLE_THUNDER
	if th > -0.05 and th < 1.4:
		var k := clampf(1.0 - th / 1.4, 0.0, 1.0)
		k = k * k * smoothstep(-0.05, 0.05, th)
		var cc := Vector2(size.x * 0.5, o.y - _fs * 0.34)
		var rx := tw * 0.75
		var ry2 := _fs * 2.6
		_add.draw_texture_rect(_halo, Rect2(cc - Vector2(rx, ry2), Vector2(rx, ry2) * 2.0), false,
			Color(VERMILION.r, VERMILION.g, VERMILION.b, 0.38 * k * out))
