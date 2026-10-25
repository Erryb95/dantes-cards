class_name Shapes
extends Node2D
## Small vector shapes drawn in code: ellipse rings, gems, shields, drops, the damage splat.

enum Kind { ELLIPSE, GEM, SHIELD, DROP, SPLAT, DIAMOND, SWORD }

var kind := Kind.ELLIPSE
var size := Vector2(100, 100)
var fill := Color.TRANSPARENT
var line := Color.WHITE
var width := 4.0
var shade := true ## a darker lower half / highlight for a jewel look


static func make(p_kind: Kind, p_size: Vector2, p_fill: Color, p_line: Color = Color.TRANSPARENT, p_width: float = 0.0) -> Shapes:
	var s := Shapes.new()
	s.kind = p_kind
	s.size = p_size
	s.fill = p_fill
	s.line = p_line
	s.width = p_width
	s.use_parent_material = true
	return s


func _ellipse(rx: float, ry: float, n: int = 64) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _points() -> PackedVector2Array:
	var w := size.x * 0.5
	var h := size.y * 0.5
	match kind:
		Kind.ELLIPSE, Kind.GEM:
			return _ellipse(w, h)
		Kind.SHIELD:
			return PackedVector2Array([Vector2(-w, -h), Vector2(w, -h), Vector2(w, h * 0.15), Vector2(w * 0.55, h * 0.7),
				Vector2(0, h), Vector2(-w * 0.55, h * 0.7), Vector2(-w, h * 0.15)])
		Kind.DROP:
			var pts := PackedVector2Array()
			for i in 33:
				var a := PI * i / 32.0
				pts.append(Vector2(cos(a) * w, sin(a) * w * 1.0 + h - w))
			pts.append(Vector2(0, -h))
			return pts
		Kind.SPLAT:
			var pts := PackedVector2Array()
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			for i in 18:
				var a := TAU * i / 18.0
				var r := 1.0 if i % 2 == 0 else rng.randf_range(0.55, 0.72)
				pts.append(Vector2(cos(a) * w * r, sin(a) * h * r))
			return pts
		Kind.DIAMOND:
			return PackedVector2Array([Vector2(0, -h), Vector2(w, 0), Vector2(0, h), Vector2(-w, 0)])
		Kind.SWORD:
			return PackedVector2Array([Vector2(0, -h), Vector2(w * 0.28, -h * 0.55), Vector2(w * 0.28, h * 0.25),
				Vector2(w, h * 0.25), Vector2(w, h * 0.45), Vector2(w * 0.25, h * 0.45), Vector2(w * 0.25, h),
				Vector2(-w * 0.25, h), Vector2(-w * 0.25, h * 0.45), Vector2(-w, h * 0.45), Vector2(-w, h * 0.25),
				Vector2(-w * 0.28, h * 0.25), Vector2(-w * 0.28, -h * 0.55)])
	return PackedVector2Array()


func _draw() -> void:
	var pts := _points()
	if fill.a > 0.0:
		draw_colored_polygon(pts, fill)
		if shade and kind != Kind.SPLAT:
			# lower shadow + top highlight: cheap jewel shading
			var low := PackedVector2Array()
			for p in pts:
				low.append(Vector2(p.x * 0.92, maxf(p.y, 0.0) * 0.92 + size.y * 0.04))
			draw_colored_polygon(low, Color(0, 0, 0, 0.22))
			if kind == Kind.GEM or kind == Kind.ELLIPSE or kind == Kind.DIAMOND:
				var hi := PackedVector2Array()
				for p in pts:
					hi.append(Vector2(p.x * 0.55, p.y * 0.35 - size.y * 0.2))
				draw_colored_polygon(hi, Color(1, 1, 1, 0.16))
	if width > 0.0 and line.a > 0.0:
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, line, width, true)


func set_diameter(d: float) -> void:
	size = Vector2(d, d)
	width = maxf(2.0, 7.0 * (1.0 - d / 2400.0))
	queue_redraw()


func set_fill(c: Color) -> void:
	fill = c
	queue_redraw()


func set_line(c: Color) -> void:
	line = c
	queue_redraw()
