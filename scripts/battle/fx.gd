class_name Fx
## One-shot visual effects: particle bursts, damage splats, shockwaves, projectiles.


static func burst(parent: Node, pos: Vector2, color: Color, amount: int = 24, speed: float = 260.0,
		life: float = 0.7, size: float = 10.0, gravity: float = 300.0, spread: float = 180.0) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = pos
	p.texture = UI.dot_texture()
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = life
	p.spread = spread
	p.direction = Vector2.UP
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, gravity)
	p.damping_min = 40.0
	p.damping_max = 120.0
	p.scale_amount_min = size / 64.0 * 0.5
	p.scale_amount_max = size / 64.0 * 1.4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color.r * 1.4, color.g * 1.4, color.b * 1.4, 1.0))
	ramp.set_color(1, Color(color.r, color.g * 0.5, color.b * 0.3, 0.0))
	p.color_ramp = ramp
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	p.z_index = 50
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


## A painted additive VFX sprite (assets/vfx/<name>, black background) that pops, spins a little and fades.
## Returns false when the texture is missing so callers keep their particle fallback.
static func flash(parent: Node, name: String, pos: Vector2, size: float, duration: float = 0.45,
		tint: Color = Color.WHITE, spin: float = 0.4) -> bool:
	if not UiSkin.has(name):
		return false
	var s := Sprite2D.new()
	s.texture = UiSkin.tex(name)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = mat
	s.modulate = tint
	s.position = pos
	s.rotation = randf_range(-PI, PI) if spin > 0.0 else 0.0
	s.z_index = 65
	var base := size / s.texture.get_size().x
	s.scale = Vector2.ONE * base * 0.4
	parent.add_child(s)
	var t := s.create_tween().set_parallel(true)
	t.tween_property(s, "scale", Vector2.ONE * base, duration * 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(s, "rotation", s.rotation + spin, duration)
	t.tween_property(s, "modulate:a", 0.0, duration * 0.6).set_delay(duration * 0.4)
	t.chain().tween_callback(s.queue_free)
	return true


## Dust ring when a minion slams down.
static func dust(parent: Node, pos: Vector2, width: float = 140.0, amount: int = 30) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.texture = UI.dot_texture()
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.9
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(width * 0.5, 8)
	p.direction = Vector2.UP
	p.spread = 90.0
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 220.0
	p.damping_min = 200.0
	p.damping_max = 300.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.6, 0.5, 0.4, 0.55))
	ramp.set_color(1, Color(0.3, 0.25, 0.2, 0.0))
	p.color_ramp = ramp
	p.z_index = 5
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


## A splat with a number that pops and fades (damage red, heal green).
static func number(parent: Node, pos: Vector2, text: String, color: Color, splat: bool = true) -> void:
	var root := Node2D.new()
	root.position = pos
	root.z_index = 80
	parent.add_child(root)
	if splat:
		var s := Shapes.make(Shapes.Kind.SPLAT, Vector2(118, 110), color, color.darkened(0.6), 3.0)
		s.shade = false
		s.use_parent_material = false
		s.rotation = randf() * TAU
		root.add_child(s)
	var l := UI.label(text, 54, "title", Color.WHITE if splat else color, 10, Color(0.08, 0.02, 0.02))
	l.size = Vector2(140, 80)
	l.position = -l.size / 2
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(l)
	root.scale = Vector2(0.2, 0.2)
	var t := root.create_tween()
	t.tween_property(root, "scale", Vector2(1.15, 1.15), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(root, "scale", Vector2.ONE, 0.08)
	t.tween_interval(0.55)
	t.set_parallel(true)
	t.tween_property(root, "modulate:a", 0.0, 0.35)
	t.tween_property(root, "position:y", pos.y - 40.0, 0.35)
	t.set_parallel(false)
	t.tween_callback(root.queue_free)


## A thin expanding ring (grown by radius, so the line stays thin), with a soft inner flash.
static func shockwave(parent: Node, pos: Vector2, color: Color, radius: float = 300.0, duration: float = 0.5) -> void:
	var ring := Shapes.make(Shapes.Kind.ELLIPSE, Vector2(40, 40), Color.TRANSPARENT, color, 7.0)
	ring.use_parent_material = false
	ring.shade = false
	ring.position = pos
	ring.z_index = 60
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	ring.material = mat
	parent.add_child(ring)
	var glow := Sprite2D.new()
	glow.texture = UI.dot_texture()
	glow.material = mat
	glow.modulate = Color(color.r, color.g, color.b, 0.5)
	glow.position = pos
	glow.z_index = 59
	parent.add_child(glow)
	var t := ring.create_tween().set_parallel(true)
	t.tween_method(ring.set_diameter, 40.0, radius * 2.0, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(ring, "modulate:a", 0.0, duration).set_ease(Tween.EASE_IN)
	t.tween_property(glow, "scale", Vector2.ONE * radius / 90.0, duration * 0.6)
	t.tween_property(glow, "modulate:a", 0.0, duration * 0.6)
	t.chain().tween_callback(ring.queue_free)
	t.tween_callback(glow.queue_free)


## A glowing orb with a particle trail flying along an arc; awaitable (returns on impact).
static func projectile(parent: Node, from: Vector2, to: Vector2, color: Color, duration: float = 0.38) -> void:
	var orb := Node2D.new()
	orb.z_index = 70
	orb.position = from
	parent.add_child(orb)
	var core := Sprite2D.new()
	core.texture = UI.dot_texture()
	core.scale = Vector2(1.1, 1.1)
	core.modulate = Color(color.r * 1.5, color.g * 1.5, color.b * 1.5)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	core.material = add
	orb.add_child(core)
	var trail := CPUParticles2D.new()
	trail.texture = UI.dot_texture()
	trail.amount = 60
	trail.lifetime = 0.45
	trail.local_coords = false
	trail.initial_velocity_min = 10.0
	trail.initial_velocity_max = 50.0
	trail.spread = 180.0
	trail.gravity = Vector2(0, -40)
	trail.scale_amount_min = 0.25
	trail.scale_amount_max = 0.6
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color.r * 1.3, color.g * 1.3, color.b * 1.3, 0.9))
	ramp.set_color(1, Color(color.r, color.g * 0.4, color.b * 0.2, 0.0))
	trail.color_ramp = ramp
	trail.material = add
	orb.add_child(trail)
	var mid := (from + to) / 2 + Vector2(0, -minf(260.0, from.distance_to(to) * 0.35))
	var t := orb.create_tween()
	t.tween_method(Fx._bezier.bind(orb, from, mid, to), 0.0, 1.0, duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	await t.finished
	core.visible = false
	trail.emitting = false
	flash(parent, "fire_burst", to, 220.0, 0.45, Color(color.r * 1.2, color.g * 1.2, color.b * 1.2))
	burst(parent, to, color, 28, 320.0, 0.55, 12.0, 200.0)
	parent.get_tree().create_timer(0.6).timeout.connect(orb.queue_free)


static func _bezier(k: float, node: Node2D, a: Vector2, m: Vector2, b: Vector2) -> void:
	node.position = a.lerp(m, k).lerp(m.lerp(b, k), k)
