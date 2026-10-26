class_name ArenaAcheron
extends ArenaProps
## Living props of the Acheron arena: Charon's boat crossing the river, the bell of the Gate,
## and the carved inscription. Drawn in code (silhouettes + additive light) so they sit on any backdrop; when the
## painted props exist (assets/arenas/props/*.png, ARENA_BRIEF.md) they replace the silhouettes, and a brazier and a
## skull pile join in. The river itself is the battle view's water shader (divider kind "river").

var _boat_faces_right := false

var boat: Node2D
var _lantern: Sprite2D
var _reflect: Sprite2D
var _boat_x := 0.0
var _boat_dir := -1.0
var _wake_t := 0.0
var _bob := 0.0

var bell: Node2D
var _bell_body: Node2D
var _bell_swing := 0.0
var _bell_vel := 0.0

var brazier: Node2D
var _flame: CPUParticles2D
var _flare := 0.0
var _brazier_light: PointLight2D
var skulls: Node2D
var _rattle := 0.0


func setup(p_view: Node2D, p_arena: Dictionary = {}) -> ArenaProps:
	view = p_view
	arena = p_arena
	_build_boat()
	if not corner_props(arena):
		return self # the boat on the river only
	_build_bell()
	if ResourceLoader.exists(PROPS + "brazier.png"):
		_build_brazier()
	if ResourceLoader.exists(PROPS + "skulls.png"):
		skulls = Node2D.new()
		add_child(skulls)
		skulls.add_child(_painted("skulls", 220.0))
	return self


## A painted prop sprite `width` px wide, or null when it isn't there. Hides the code silhouette it replaces.
func _painted(name: String, width: float) -> Sprite2D:
	if not ResourceLoader.exists(PROPS + name + ".png"):
		return null
	var sp := Sprite2D.new()
	sp.texture = load(PROPS + name + ".png")
	var k := width / sp.texture.get_size().x
	sp.scale = Vector2(k, k)
	return sp


func _hide_silhouette(node: Node, keep: Array) -> void:
	for c in node.get_children():
		if c is CanvasItem and not keep.has(c):
			(c as CanvasItem).visible = false


# ---------------------------------------------------------------- boat

func _build_boat() -> void:
	boat = Node2D.new()
	add_child(boat)
	_reflect = Sprite2D.new()
	_reflect.texture = UI.dot_texture()
	_reflect.material = _add_mat()
	_reflect.modulate = Color(1.0, 0.55, 0.2, 0.45)
	_reflect.scale = Vector2(0.5, 1.6)
	_reflect.position = Vector2(34, 34)
	boat.add_child(_reflect)
	var hull := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 21:
		var k := float(i) / 20.0
		pts.append(Vector2(lerpf(-95, 95, k), 6 + sin(k * PI) * 16))
	pts.append(Vector2(110, -14))
	pts.append(Vector2(-112, -12))
	hull.polygon = pts
	hull.color = Color(0.04, 0.025, 0.02, 0.95)
	boat.add_child(hull)
	# Hooded ferryman with his oar.
	var fig := Polygon2D.new()
	fig.polygon = PackedVector2Array([Vector2(-18, -12), Vector2(-14, -60), Vector2(-8, -84), Vector2(2, -92),
		Vector2(12, -84), Vector2(16, -60), Vector2(22, -12)])
	fig.color = Color(0.03, 0.02, 0.02, 0.97)
	boat.add_child(fig)
	var oar := Line2D.new()
	oar.points = PackedVector2Array([Vector2(-40, 30), Vector2(30, -100)])
	oar.width = 5.0
	oar.default_color = Color(0.05, 0.03, 0.02)
	oar.name = "Oar"
	boat.add_child(oar)
	var eyes := Sprite2D.new()
	eyes.texture = UI.dot_texture()
	eyes.material = _add_mat()
	eyes.modulate = Color(1.0, 0.25, 0.05, 0.9)
	eyes.scale = Vector2(0.22, 0.1)
	eyes.position = Vector2(4, -80)
	boat.add_child(eyes)
	var pole := Line2D.new()
	pole.points = PackedVector2Array([Vector2(70, -12), Vector2(80, -70)])
	pole.width = 3.0
	pole.default_color = Color(0.06, 0.04, 0.03)
	boat.add_child(pole)
	_lantern = Sprite2D.new()
	_lantern.texture = UI.dot_texture()
	_lantern.material = _add_mat()
	_lantern.modulate = Color(1.0, 0.7, 0.3)
	_lantern.position = Vector2(84, -72)
	boat.add_child(_lantern)
	var core := Sprite2D.new()
	core.texture = UI.dot_texture()
	core.material = _add_mat()
	core.modulate = Color(1.0, 0.95, 0.7)
	core.scale = Vector2(0.18, 0.18)
	core.position = _lantern.position
	boat.add_child(core)
	boat.scale = Vector2(0.95, 0.95)
	boat.modulate.a = 1.0
	var painted := _painted("boat", 320.0)
	if painted != null:
		# The painting faces right (the code silhouette faces left), and its lantern hangs where _lantern glows.
		_boat_faces_right = true
		_hide_silhouette(boat, [_reflect, _lantern, core])
		painted.position = Vector2(0, -42)
		boat.add_child(painted)
		boat.move_child(painted, 1)
		boat.move_child(_lantern, -1)
	boat.add_child(_light(_lantern.position, Color(1.0, 0.7, 0.35), 1.1, 2.6))


# ---------------------------------------------------------------- bell

func _build_bell() -> void:
	bell = Node2D.new()
	add_child(bell)
	var beam := Line2D.new()
	beam.points = PackedVector2Array([Vector2(-60, -70), Vector2(60, -70)])
	beam.width = 10.0
	beam.default_color = Color(0.12, 0.08, 0.05)
	bell.add_child(beam)
	for x in [-50, 50]:
		var post := Line2D.new()
		post.points = PackedVector2Array([Vector2(x, -70), Vector2(x, 70)])
		post.width = 8.0
		post.default_color = Color(0.1, 0.07, 0.05)
		bell.add_child(post)
	_bell_body = Node2D.new()
	_bell_body.position = Vector2(0, -66)
	bell.add_child(_bell_body)
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([Vector2(-8, 4), Vector2(8, 4), Vector2(16, 20), Vector2(20, 52), Vector2(30, 66),
		Vector2(-30, 66), Vector2(-20, 52), Vector2(-16, 20)])
	body.color = Color(0.42, 0.3, 0.14)
	_bell_body.add_child(body)
	var shine := Polygon2D.new()
	shine.polygon = PackedVector2Array([Vector2(-10, 14), Vector2(-4, 14), Vector2(-8, 58), Vector2(-16, 58)])
	shine.color = Color(0.85, 0.65, 0.35, 0.5)
	_bell_body.add_child(shine)
	var clapper := Polygon2D.new()
	clapper.polygon = PackedVector2Array([Vector2(-4, 60), Vector2(4, 60), Vector2(5, 74), Vector2(-5, 74)])
	clapper.color = Color(0.2, 0.14, 0.08)
	_bell_body.add_child(clapper)
	var painted := _painted("bell", 170.0)
	if painted != null:
		# The painting has the gallows and the bell in one piece: swing it gently from the top beam.
		_hide_silhouette(bell, [_bell_body])
		_hide_silhouette(_bell_body, [])
		painted.offset = Vector2(0, painted.texture.get_size().y / 2)
		painted.position = Vector2(0, -94)
		_bell_body.position = Vector2.ZERO
		_bell_body.add_child(painted)


func _build_brazier() -> void:
	brazier = Node2D.new()
	add_child(brazier)
	var sp := _painted("brazier", 130.0)
	brazier.add_child(sp)
	_flame = CPUParticles2D.new()
	_flame.texture = UI.dot_texture()
	_flame.material = _add_mat()
	_flame.amount = 40
	_flame.lifetime = 0.9
	_flame.position = Vector2(0, -sp.texture.get_size().y * sp.scale.y * 0.3)
	_flame.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_flame.emission_rect_extents = Vector2(26, 4)
	_flame.direction = Vector2.UP
	_flame.spread = 12.0
	_flame.gravity = Vector2(0, -90)
	_flame.initial_velocity_min = 30.0
	_flame.initial_velocity_max = 70.0
	_flame.scale_amount_min = 0.25
	_flame.scale_amount_max = 0.55
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.85, 0.4, 0.9))
	g.set_color(1, Color(0.8, 0.15, 0.02, 0.0))
	_flame.color_ramp = g
	brazier.add_child(_flame)
	_brazier_light = _light(_flame.position, Color(1.0, 0.55, 0.2), 1.3, 3.2)
	brazier.add_child(_brazier_light)


# ---------------------------------------------------------------- layout / update

## `anchors` (screen positions from the arena scene's sockets) override the edge-anchored defaults.
func layout(p_v: Vector2, p_river_y: float, p_ky: float, anchors: Dictionary = {}) -> void:
	V = p_v
	river_y = p_river_y
	ky = p_ky
	var left := minf(170.0, (V.x - 1220.0) / 4.0 + 40.0)
	var s := clampf((V.x - 1220.0) / 2.0 / 260.0, 0.55, 1.0) if anchors.is_empty() else ky
	if bell != null:
		bell.position = anchors.get("PropBell", Vector2(maxf(left, 90.0), 300 * ky))
		bell.scale = Vector2(s, s)
	if brazier != null:
		brazier.position = anchors.get("PropBrazier", Vector2(V.x - 90, 860 * ky))
		brazier.scale = Vector2(s, s)
	if skulls != null:
		skulls.position = anchors.get("PropSkulls", Vector2(maxf(left, 140.0), 960 * ky))
		skulls.scale = Vector2(s, s)
	if _boat_x == 0.0:
		_boat_x = V.x * 0.8


func _process(delta: float) -> void:
	_t += delta
	# Boat: slow crossing, turning at the edges.
	_boat_x += _boat_dir * 22.0 * delta
	# The boat stays on the painted river, turning before the board's edges.
	var half := 960.0 * ky - 230.0
	if _boat_x < V.x / 2 - half:
		_boat_dir = 1.0
	elif _boat_x > V.x / 2 + half:
		_boat_dir = -1.0
	_bob = sin(_t * 1.3) * 3.0
	boat.position = Vector2(_boat_x, river_y + 4 + _bob)
	boat.scale.x = absf(boat.scale.x) * ((1.0 if _boat_dir > 0 else -1.0) if _boat_faces_right else (-1.0 if _boat_dir > 0 else 1.0))
	boat.rotation = sin(_t * 0.9) * 0.025
	var flick := 0.85 + 0.15 * sin(_t * 13.0) * sin(_t * 7.3)
	_lantern.scale = Vector2.ONE * 1.25 * flick
	_reflect.modulate.a = 0.3 + 0.15 * flick
	var oar: Line2D = boat.get_node("Oar")
	var stroke := sin(_t * 1.1)
	oar.points = PackedVector2Array([Vector2(-40 + stroke * 20, 30), Vector2(30 + stroke * 8, -100)])
	_wake_t -= delta
	if _wake_t <= 0.0 and view != null:
		_wake_t = 3.2
		view.add_ripple(boat.position + Vector2(-_boat_dir * 50, 6), 0.45)
	# Bell: damped pendulum.
	if bell != null:
		_bell_vel += -_bell_swing * 30.0 * delta
		_bell_vel *= 1.0 - 1.2 * delta
		_bell_swing += _bell_vel * delta
		_bell_body.rotation = _bell_swing
	if _flame != null:
		_flare = maxf(0.0, _flare - delta * 1.5)
		_flame.speed_scale = 1.0 + _flare * 1.5
		_flame.scale_amount_max = 0.55 + _flare * 0.8
		_brazier_light.energy = (1.2 + 0.15 * sin(_t * 11.0) * sin(_t * 5.3)) * (1.0 + _flare * 1.5)
	if skulls != null and _rattle > 0.0:
		_rattle = maxf(0.0, _rattle - delta * 2.5)
		skulls.rotation = sin(_t * 60.0) * 0.04 * _rattle


## Returns true when the touch hit a prop.
func touch(p: Vector2) -> bool:
	var lb := bell.to_local(p) if bell != null else Vector2.INF
	if absf(lb.x) < 70 and absf(lb.y) < 80:
		_bell_vel += 2.6 * (1.0 if lb.x < 0 else -1.0)
		Sfx.play("bell_far", -4.0, 1.25)
		Fx.shockwave(view.fx_layer, bell.position + Vector2(0, -30), Color(1.0, 0.8, 0.45), 260.0, 0.8)
		return true
	if brazier != null and brazier.to_local(p).length() < 80:
		_flare = 1.0
		Sfx.play("thunder", -16.0, 1.8)
		Fx.burst(view.fx_layer, brazier.position + Vector2(0, -50), UI.EMBER, 50, 320.0, 1.0, 12.0, -120.0)
		return true
	if skulls != null and absf(skulls.to_local(p).x) < 110 and absf(skulls.to_local(p).y) < 80:
		_rattle = 1.0
		Sfx.play("bones", -6.0)
		return true
	var lbt := boat.to_local(p)
	if absf(lbt.x) < 120 and lbt.y > -110 and lbt.y < 40:
		Sfx.play("wail", -12.0, 0.6)
		_boat_dir = -_boat_dir
		view.add_ripple(boat.position, 1.0)
		view.shake(4.0)
		return true
	return false


func toy_points() -> Array[Vector2]:
	var out: Array[Vector2] = []
	if bell != null:
		out.append(bell.position + Vector2(-10, 0))
	if brazier != null:
		out.append(brazier.position)
	if skulls != null:
		out.append(skulls.position)
	out.append(boat.position + Vector2(0, -20))
	return out
