class_name TargetArrow
extends Node2D
## The targeting arrow: a curved chain of painted ember links that crawls toward the pointer, a barbed iron head, and
## a turning rune reticle on valid targets (assets/ui/arrow_*.png, target_reticle.png). Falls back to drawn chevrons
## when the paintings are missing.

const LINK_LEN := 62.0 ## px along the curve per painted chain piece
const LINK_H := 30.0

var from := Vector2.ZERO
var to := Vector2.ZERO
var valid := false
var _t := 0.0
var _link: Texture2D
var _head: Texture2D
var _reticle: Texture2D


func _ready() -> void:
	_link = UiSkin.tex("arrow_segment")
	_head = UiSkin.tex("arrow_head")
	_reticle = UiSkin.tex("target_reticle")


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _point(k: float) -> Vector2:
	var mid := (from + to) / 2 + Vector2(0, -minf(220.0, from.distance_to(to) * 0.3))
	return from.lerp(mid, k).lerp(mid.lerp(to, k), k)


func _draw() -> void:
	var len := from.distance_to(to)
	if len < 20.0:
		return
	if _link == null or _head == null:
		_draw_plain(len)
		return
	# A soft ember trail under the chain, so the arrow reads over any painting.
	var pts := PackedVector2Array()
	for i in 25:
		pts.append(_point(i / 24.0 * 0.92))
	var hue := Color(1.0, 0.45, 0.12) if valid else Color(0.85, 0.75, 0.6)
	draw_polyline(pts, Color(hue.r, hue.g, hue.b, 0.18), 26.0, true)
	draw_polyline(pts, Color(hue.r, hue.g, hue.b, 0.35), 10.0, true)
	draw_polyline(pts, Color(1.0, 0.9, 0.7, 0.5), 3.0, true)
	# Ember links: dim and small at the source, hot and full size near the head, crawling forward.
	var tint := Color(1.5, 1.15, 0.9) if valid else Color(1.0, 0.92, 0.82)
	var n := int(len * 1.15 / LINK_LEN)
	var off := fmod(_t * 1.6, 1.0)
	for i in n:
		var k := (float(i) + off) / maxf(n, 1)
		if k > 0.9:
			continue
		var p := _point(k)
		var q := _point(minf(k + 0.02, 1.0))
		var s := 0.55 + 0.45 * k
		draw_set_transform(p, (q - p).angle(), Vector2(s, s))
		draw_texture_rect(_link, Rect2(-LINK_LEN / 2, -LINK_H / 2, LINK_LEN, LINK_H), false,
			Color(tint.r, tint.g, tint.b, 0.6 + 0.4 * k))
	# The reticle first, then the head on top of it so the point stays readable.
	if valid and _reticle != null:
		var r := 150.0 + sin(_t * 6.0) * 8.0
		draw_set_transform(to, _t * 0.9, Vector2.ONE)
		draw_texture_rect(_reticle, Rect2(-r / 2, -r / 2, r, r), false, Color(1.2, 0.9, 0.8, 0.8))
	var dir := (to - _point(0.9)).angle()
	var hs := 1.15 + (0.08 * sin(_t * 10.0) if valid else 0.0)
	draw_set_transform(to, dir, Vector2(hs, hs))
	draw_texture_rect(_head, Rect2(-86, -50, 100, 100), false, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_plain(len: float) -> void:
	var col := Color(1.0, 0.35, 0.15) if valid else Color(0.95, 0.85, 0.7)
	var step := 34.0
	var n := int(len / step)
	var off := fmod(_t * 90.0, step) / len
	for i in n:
		var k := float(i) / maxf(n, 1) + off
		if k > 0.93:
			continue
		var p := _point(k)
		var dir := (_point(minf(k + 0.01, 1.0)) - p).normalized()
		var side := Vector2(-dir.y, dir.x)
		var s := 9.0 + 7.0 * k
		var chev := PackedVector2Array([p + dir * s, p - dir * s * 0.4 + side * s, p - dir * s * 0.1,
			p - dir * s * 0.4 - side * s])
		draw_colored_polygon(chev, Color(col.r, col.g, col.b, 0.35 + 0.65 * k))
	var dir2 := (to - _point(0.95)).normalized()
	var side2 := Vector2(-dir2.y, dir2.x)
	draw_colored_polygon(PackedVector2Array([to + dir2 * 18.0, to - dir2 * 34.0 + side2 * 30.0, to - dir2 * 22.0,
		to - dir2 * 34.0 - side2 * 30.0]), col)
