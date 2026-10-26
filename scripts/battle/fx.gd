class_name Fx
## One-shot visual effects: particle bursts, damage splats, shockwaves, projectiles.

const SUMMON_SHADER := preload("res://assets/shaders/summon_circle.gdshader")
const LANDING_GROUND := preload("res://assets/shaders/landing_ground.gdshader")
const LANDING_GLOW := preload("res://assets/shaders/landing_glow.gdshader")


static func burst(parent: Node, pos: Vector2, color: Color, amount: int = 24, speed: float = 260.0,
		life: float = 0.7, size: float = 10.0, gravity: float = 300.0, spread: float = 180.0,
		tex_name: String = "") -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = pos
	p.texture = _tex(tex_name)
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
	var px := 64.0 if p.texture == UI.dot_texture() else p.texture.get_width() * 0.25
	p.scale_amount_min = size / px * 0.5
	p.scale_amount_max = size / px * 1.4
	if p.texture != UI.dot_texture():
		p.angle_min = -180.0
		p.angle_max = 180.0
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
static func dust(parent: Node, pos: Vector2, width: float = 140.0, amount: int = 30,
		tint: Color = Color(0.6, 0.5, 0.4, 0.55)) -> void:
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
	ramp.set_color(0, tint)
	ramp.set_color(1, Color(tint.r * 0.5, tint.g * 0.5, tint.b * 0.5, 0.0))
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
	core.texture = _tex("k_magic_05")
	core.scale = Vector2(1.1, 1.1) if core.texture == UI.dot_texture() else Vector2.ONE * 110.0 / core.texture.get_width()
	core.modulate = Color(color.r * 1.5, color.g * 1.5, color.b * 1.5)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	core.material = add
	orb.add_child(core)
	var trail := CPUParticles2D.new()
	trail.texture = _tex("k_star_04")
	trail.amount = 60
	trail.lifetime = 0.45
	trail.local_coords = false
	trail.initial_velocity_min = 10.0
	trail.initial_velocity_max = 50.0
	trail.spread = 180.0
	trail.gravity = Vector2(0, -40)
	var dot := trail.texture == UI.dot_texture()
	trail.scale_amount_min = 0.25 if dot else 0.06
	trail.scale_amount_max = 0.6 if dot else 0.16
	trail.angle_min = -180.0
	trail.angle_max = 180.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color.r * 1.3, color.g * 1.3, color.b * 1.3, 0.9))
	ramp.set_color(1, Color(color.r, color.g * 0.4, color.b * 0.2, 0.0))
	trail.color_ramp = ramp
	trail.material = add
	orb.add_child(trail)
	var mid := (from + to) / 2 + Vector2(0, -minf(260.0, from.distance_to(to) * 0.35))
	var t := orb.create_tween()
	t.tween_method(Fx._bezier.bind(orb, from, mid, to), 0.0, 1.0, duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	core.create_tween().tween_property(core, "rotation", TAU * 1.5, duration)
	await t.finished
	flash(parent, "k_flare_01", to, 340.0, 0.4, Color(color.r * 1.3, color.g * 1.3, color.b * 1.3), 0.0)
	sparks(parent, to, color, 18)
	core.visible = false
	trail.emitting = false
	flash(parent, "fire_burst", to, 220.0, 0.45, Color(color.r * 1.2, color.g * 1.2, color.b * 1.2))
	burst(parent, to, color, 28, 320.0, 0.55, 12.0, 200.0)
	parent.get_tree().create_timer(0.6).timeout.connect(orb.queue_free)


static func _bezier(k: float, node: Node2D, a: Vector2, m: Vector2, b: Vector2) -> void:
	node.position = a.lerp(m, k).lerp(m.lerp(b, k), k)


static func _tex(name: String) -> Texture2D:
	if name != "" and UiSkin.has(name):
		return UiSkin.tex(name)
	return UI.dot_texture()


## Streaking sparks aligned to their velocity (Kenney spark textures), for hits and impacts.
static func sparks(parent: Node, pos: Vector2, color: Color, amount: int = 20, speed: float = 520.0) -> void:
	var p := burst(parent, pos, color, amount, speed, 0.45, 26.0, 700.0, 180.0, "k_spark_04")
	p.particle_flag_align_y = true
	p.angle_min = 0.0
	p.angle_max = 0.0
	p.damping_min = 10.0
	p.damping_max = 40.0


## Slow rising, spinning smoke that grows as it fades (normal blend, so it darkens the board).
static func smoke(parent: Node, pos: Vector2, tint: Color = Color(0.25, 0.22, 0.2, 0.7), size: float = 180.0,
		amount: int = 8) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.texture = _tex("k_smoke_04")
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 0.8
	p.lifetime = 1.6
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = size * 0.2
	p.direction = Vector2.UP
	p.spread = 40.0
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 90.0
	p.gravity = Vector2(0, -30)
	p.angular_velocity_min = -60.0
	p.angular_velocity_max = 60.0
	p.angle_min = -180.0
	p.angle_max = 180.0
	var k := size / p.texture.get_width()
	p.scale_amount_min = k * 0.6
	p.scale_amount_max = k
	var grow := Curve.new()
	grow.max_value = 2.0
	grow.add_point(Vector2(0, 0.5))
	grow.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.set_color(0, tint)
	ramp.set_color(1, Color(tint.r, tint.g, tint.b, 0.0))
	p.color_ramp = ramp
	p.z_index = 55
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


## A slash stroke oriented along `dir`, stretched as it fades.
static func slash(parent: Node, pos: Vector2, dir: Vector2, size: float = 300.0, tint: Color = Color.WHITE) -> void:
	if not UiSkin.has("k_slash_02"):
		return
	var s := Sprite2D.new()
	s.texture = UiSkin.tex("k_slash_02")
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = mat
	s.modulate = tint
	s.position = pos
	s.rotation = dir.angle() + PI * 0.5 + randf_range(-0.3, 0.3)
	s.z_index = 66
	var base := size / s.texture.get_width()
	s.scale = Vector2(base * 0.5, base * 0.3)
	parent.add_child(s)
	var t := s.create_tween().set_parallel(true)
	t.tween_property(s, "scale", Vector2(base * 1.1, base), 0.12).set_ease(Tween.EASE_OUT)
	t.tween_property(s, "modulate:a", 0.0, 0.25).set_delay(0.1)
	t.chain().tween_callback(s.queue_free)


## A magic circle lying flat on the board (squashed for a tabletop perspective), spinning in and out.
static func rune(parent: Node, pos: Vector2, color: Color, size: float = 360.0, duration: float = 1.1,
		name: String = "k_magic_01") -> void:
	if not UiSkin.has(name):
		return
	var holder := Node2D.new()
	holder.position = pos
	holder.scale = Vector2(1.0, 0.42)
	holder.z_index = 4
	var s := Sprite2D.new()
	s.texture = UiSkin.tex(name)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = mat
	s.modulate = Color(color.r * 1.3, color.g * 1.3, color.b * 1.3, 0.0)
	var base := size / s.texture.get_width()
	s.scale = Vector2.ONE * base * 0.6
	holder.add_child(s)
	parent.add_child(holder)
	var t := s.create_tween().set_parallel(true)
	t.tween_property(s, "scale", Vector2.ONE * base, duration * 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(s, "rotation", PI * 0.8, duration)
	t.tween_property(s, "modulate:a", 1.0, duration * 0.2)
	t.tween_property(s, "modulate:a", 0.0, duration * 0.5).set_delay(duration * 0.5)
	t.chain().tween_callback(holder.queue_free)


## A summoning circle on the board under a landing minion (assets/shaders/summon_circle.gdshader): rune rings,
## a star and a shock ring lying flat on the table, a pillar of light and rising embers. `power` 0..1 scales it up
## for expensive and legendary minions.
static func summon(parent: Node, pos: Vector2, color: Color, size: float = 340.0, duration: float = 1.1,
		power: float = 0.0) -> void:
	var holder := Node2D.new()
	holder.position = pos
	holder.scale = Vector2(1.0, 0.42)
	holder.z_index = 4
	parent.add_child(holder)
	var circle := ColorRect.new()
	var mat := ShaderMaterial.new()
	mat.shader = SUMMON_SHADER
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("hot", color.lerp(Color(1, 0.97, 0.85), 0.75))
	mat.set_shader_parameter("seed", randf() * 10.0)
	circle.material = mat
	circle.size = Vector2(size, size)
	circle.position = -circle.size / 2
	circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(circle)
	var t := holder.create_tween()
	t.tween_method(func(v: float): mat.set_shader_parameter("t", v), 0.0, 1.0, duration)
	t.tween_callback(holder.queue_free)
	# Pillar of light: a tall soft beam that shoots up and thins out.
	var beam := Sprite2D.new()
	beam.texture = UI.dot_texture()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	beam.material = add
	beam.modulate = Color(color.r * 1.2, color.g * 1.2, color.b * 1.2, 0.0)
	beam.position = pos + Vector2(0, -size * 0.25)
	beam.scale = Vector2(size / 64.0 * 0.35, size / 64.0 * (1.2 + power))
	beam.z_index = 6
	parent.add_child(beam)
	var b := beam.create_tween().set_parallel(true)
	b.tween_property(beam, "modulate:a", 0.55 + 0.3 * power, duration * 0.12)
	b.tween_property(beam, "scale:x", size / 64.0 * 0.05, duration * 0.6).set_delay(duration * 0.1)
	b.tween_property(beam, "modulate:a", 0.0, duration * 0.45).set_delay(duration * 0.2)
	b.chain().tween_callback(beam.queue_free)
	var e := burst(parent, pos, color, 24 + int(power * 40), 240.0 + power * 260.0, 1.2, 9.0, -160.0, 70.0)
	e.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	e.emission_rect_extents = Vector2(size * 0.35, 10)


## A minion slamming onto the board: the stone cracks around it with hellfire glowing up through the seams (in the
## rarity colour), a dust ring rolls out, stone chips fly and fall back, and for big minions embers rise from the
## cracks. Lies flat on the table like the summoning circle. `power` 0..1 grows it with the minion's cost.
static func landing(parent: Node, pos: Vector2, glow: Color, size: float = 300.0, power: float = 0.0,
		z: int = 0) -> void:
	var holder := Node2D.new()
	holder.position = pos
	holder.scale = Vector2(1.0, 0.4)
	holder.z_index = z # 0 on the table layer: drawn over the board, under the minions
	parent.add_child(holder)
	var mats: Array[ShaderMaterial] = []
	for shader in [LANDING_GROUND, LANDING_GLOW]:
		var r := ColorRect.new()
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("glow", glow)
		m.set_shader_parameter("seed", randf() * 10.0)
		m.set_shader_parameter("power", power)
		r.material = m
		r.size = Vector2(size, size)
		r.position = -r.size / 2
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(r)
		mats.append(m)
	# Both layers must share the crack pattern.
	mats[1].set_shader_parameter("seed", mats[0].get_shader_parameter("seed"))
	var duration := 1.0 + 0.5 * power
	var t := holder.create_tween()
	t.tween_method(func(v: float):
		for m in mats:
			m.set_shader_parameter("t", v), 0.0, 1.0, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	t.tween_callback(holder.queue_free)
	_debris(parent, pos, size * 0.3, 10 + int(power * 14))
	if power > 0.25:
		# Embers rising from the cracks.
		var e := burst(parent, pos, glow, 10 + int(power * 26), 160.0 + power * 120.0, 1.3, 7.0, -120.0, 60.0)
		e.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		e.emission_rect_extents = Vector2(size * 0.3, 12)


## Stone chips thrown up by an impact; they arc and drop back with gravity.
static func _debris(parent: Node, pos: Vector2, radius: float, amount: int) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.75
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(radius, 10)
	p.direction = Vector2.UP
	p.spread = 70.0
	p.initial_velocity_min = 160.0
	p.initial_velocity_max = 420.0
	p.gravity = Vector2(0, 1400)
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.scale_amount_min = 3.0 # no texture: each particle is a 1 px square scaled up into a chip
	p.scale_amount_max = 8.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.32, 0.28, 0.25, 1.0))
	ramp.set_color(1, Color(0.2, 0.17, 0.15, 0.0))
	ramp.add_point(0.75, Color(0.25, 0.22, 0.2, 1.0))
	p.color_ramp = ramp
	p.z_index = 12
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


## Embers drawn in to a point from all around, like a soul taking shape (plays while a minion drops in).
static func gather(parent: Node, pos: Vector2, color: Color, radius: float = 170.0, duration: float = 0.25,
		amount: int = 26) -> void:
	for i in amount:
		var s := Sprite2D.new()
		s.texture = UI.dot_texture()
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		s.material = add
		var ang := randf() * TAU
		var from := pos + Vector2(cos(ang), sin(ang) * 0.45) * radius * randf_range(0.7, 1.2)
		s.position = from
		s.scale = Vector2.ONE * randf_range(0.12, 0.22)
		s.modulate = Color(color.r * 1.4, color.g * 1.4, color.b * 1.4, 0.0)
		s.z_index = 14
		parent.add_child(s)
		var d := duration * randf_range(0.7, 1.0)
		var t := s.create_tween().set_parallel(true)
		t.tween_property(s, "position", pos, d).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		t.tween_property(s, "modulate:a", 0.9, d * 0.4)
		t.tween_property(s, "scale", Vector2.ONE * 0.05, d).set_ease(Tween.EASE_IN)
		t.chain().tween_callback(s.queue_free)
