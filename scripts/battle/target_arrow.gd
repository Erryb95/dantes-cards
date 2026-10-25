class_name TargetArrow
extends Node2D
## The targeting arrow: a curved chain of animated chevrons with a big head and a reticle on valid targets.

var from := Vector2.ZERO
var to := Vector2.ZERO
var valid := false
var _t := 0.0


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
		var a := 0.35 + 0.65 * k
		var chev := PackedVector2Array([p + dir * s, p - dir * s * 0.4 + side * s, p - dir * s * 0.1,
			p - dir * s * 0.4 - side * s])
		draw_colored_polygon(chev, Color(0, 0, 0, a * 0.5))
		var inner := PackedVector2Array()
		for q in chev:
			inner.append(p + (q - p) * 0.72)
		draw_colored_polygon(inner, Color(col.r, col.g, col.b, a))
	var dir := (to - _point(0.95)).normalized()
	var side := Vector2(-dir.y, dir.x)
	var head := PackedVector2Array([to + dir * 18.0, to - dir * 34.0 + side * 30.0, to - dir * 22.0, to - dir * 34.0 - side * 30.0])
	draw_colored_polygon(head, Color(0, 0, 0, 0.6))
	var ih := PackedVector2Array()
	for q in head:
		ih.append(to + (q - to) * 0.8)
	draw_colored_polygon(ih, col)
	if valid:
		var r := 46.0 + sin(_t * 8.0) * 4.0
		draw_arc(to, r, 0, TAU, 48, Color(1, 0.3, 0.1, 0.9), 5.0, true)
		for i in 4:
			var a := i * PI / 2 + _t * 1.5
			draw_line(to + Vector2(cos(a), sin(a)) * (r - 12), to + Vector2(cos(a), sin(a)) * (r + 12),
				Color(1, 0.5, 0.2), 4.0, true)
