class_name TurnRope
extends Node2D
## The burning rope of an online turn (Hearthstone's): in the last seconds of a turn a twisted fuse runs along the
## river to the End Turn seal and burns down toward it, a flame and sparks at its end. `left` is the part still
## unburnt (1 = whole, 0 = gone); the battle sets it from the turn clock. Drawn in code, no textures.

var from := Vector2.ZERO ## the far end, where it starts burning
var to := Vector2.ZERO ## the End Turn seal's edge
var left := 1.0:
	set(v):
		left = clampf(v, 0.0, 1.0)
		queue_redraw()
var _sparks: Array = [] ## [pos, vel, life]
var _t := 0.0

const ROPE := Color(0.55, 0.38, 0.2)
const ROPE_DARK := Color(0.3, 0.18, 0.08)
const ASH := Color(0.16, 0.13, 0.12, 0.8)


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	var tip := from.lerp(to, 1.0 - left)
	if left > 0.0 and randf() < 0.7:
		_sparks.append([tip + Vector2(randf_range(-4, 4), -4), Vector2(randf_range(-60, 60), randf_range(-150, -50)),
			randf_range(0.35, 0.8)])
	for s in _sparks:
		s[2] -= delta
		s[1].y += 220.0 * delta
		s[0] += s[1] * delta
	_sparks = _sparks.filter(func(s): return s[2] > 0.0)
	queue_redraw()


func _draw() -> void:
	var tip := from.lerp(to, 1.0 - left)
	var length := from.distance_to(to)
	if length < 1.0:
		return
	var dir := (to - from) / length
	var n := Vector2(-dir.y, dir.x)
	# The ash already burnt: a thin grey trail.
	draw_line(from, tip, ASH, 3.0, true)
	# The rope: a thick strand with its twist drawn as slanted dark bands.
	if left > 0.0:
		draw_line(tip, to, ROPE_DARK, 13.0, true)
		draw_line(tip, to, ROPE, 9.0, true)
		var step := 14.0
		var d := (1.0 - left) * length
		d = ceilf(d / step) * step
		while d < length:
			var p := from + dir * d
			draw_line(p - n * 5.0 - dir * 3.0, p + n * 5.0 + dir * 3.0, ROPE_DARK, 2.5, true)
			d += step
		# The flame at the burning end.
		var flick := 1.0 + 0.25 * sin(_t * 23.0) + 0.15 * sin(_t * 37.0)
		draw_circle(tip, 22.0 * flick, Color(1.0, 0.35, 0.05, 0.25))
		draw_circle(tip + Vector2(0, -4), 13.0 * flick, Color(1.0, 0.55, 0.1, 0.7))
		draw_circle(tip + Vector2(0, -6), 7.0 * flick, Color(1.0, 0.9, 0.5, 0.95))
	for s in _sparks:
		var a: float = clampf(s[2] / 0.5, 0.0, 1.0)
		draw_circle(s[0], 2.5, Color(1.0, 0.7, 0.25, a))
