class_name ArenaProps
extends Node2D
## The living layer of an arena, built from its data/arenas.json entry: the middle divider VFX (stream, wind,
## ember crack, frost crack), the ambient particles, and the tappable toys painted as separate props
## (assets/arenas/props/<arena>_<name>.png). Arenas whose behaviour really differs subclass it ("props_script",
## e.g. ArenaAcheron with Charon's boat). Positions are in 1920x1080 layout units, like the board sockets.
##
## Prop entry: {"name", "pos": [x, y] (centre), "width", "pivot": top|bottom|center, "motion": swing|sway|rattle|
## flap|pulse, "idle": sway amplitude (rad), "flame": {"at": [fx, fy] (fraction of the prop size from its centre),
## "color": fire|gold|green|cold, "size", "wind", "spread"}, "glow": {"at", "color": [r,g,b], "size", "idle", "pair",
## "light"}, "burst": embers|motes|
## leaves|pages|souls|frost|snow|dust, "sfx": [name, db, pitch], "shake", "ring": [r,g,b], "flare_divider": bool}
const PROPS := "res://assets/arenas/props/"
## Arena lights only reach canvas items on this layer: the backdrop, board and river (not cards or UI).
const LIGHT_MASK := 2
const CRACK_SHADER := preload("res://assets/shaders/crack.gdshader")
const WIND_SHADER := preload("res://assets/shaders/wind.gdshader")
const HAZE_SHADER := preload("res://assets/shaders/heat_haze.gdshader")
const FLAME_COLORS := {
	"fire": [Color(1.0, 0.85, 0.4, 0.9), Color(0.8, 0.15, 0.02, 0.0), Color(1.0, 0.55, 0.2)],
	"gold": [Color(1.0, 0.92, 0.6, 0.9), Color(0.9, 0.5, 0.1, 0.0), Color(1.0, 0.8, 0.45)],
	"green": [Color(0.75, 1.0, 0.5, 0.9), Color(0.1, 0.5, 0.1, 0.0), Color(0.6, 1.0, 0.45)],
	"cold": [Color(0.8, 0.95, 1.0, 0.9), Color(0.2, 0.4, 1.0, 0.0), Color(0.6, 0.85, 1.0)],
}

var view: Node2D ## the battle view (fx layer, ripples, sounds, shake)
var arena: Dictionary
var V := Vector2(1920, 1080)
var river_y := 472.0
var ky := 1.0
## Dev preview of an arena whose painted props are missing: draw a marker where each toy goes.
var placeholders := false

var _t := 0.0
var _toys: Array[Dictionary] = []
var _band: ColorRect ## the divider (crack or wind) when it isn't the battle view's water shader
var _band_mat: ShaderMaterial
var _band_h := 110.0
var _haze: ColorRect
var _band_fx: Array[CPUParticles2D] = []
var _flares: Array[Vector4] = [Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO]
var _flare_i := 0
var _auto_flare := 3.0
var _gust := 0.0
var _wind_time := 0.0
var _edge_souls: Array[CPUParticles2D] = []


## The props node for an arena: its "props_script" subclass, or the data-driven base.
static func make(p_arena: Dictionary) -> ArenaProps:
	var path := str(p_arena.get("props_script", ""))
	if path != "" and ResourceLoader.exists(path):
		return load(path).new()
	return ArenaProps.new()


func setup(p_view: Node2D, p_arena: Dictionary = {}) -> ArenaProps:
	view = p_view
	arena = p_arena
	_build_divider()
	for p in arena.get("props", []):
		_build_toy(p)
	return self


func divider() -> Dictionary:
	return arena.get("divider", {})


func divider_kind() -> String:
	return str(divider().get("kind", "river"))


## Retints the battle view's shared layers (fog, wisps, ambient particles) for this arena. Call after they exist.
func dress() -> void:
	var tint: Dictionary = arena.get("tint", {})
	var fog := view.bg_layer.get_node_or_null("Fog") as ColorRect
	if fog != null and tint.has("fog"):
		(fog.material as ShaderMaterial).set_shader_parameter("fog_color", _col(tint.fog))
		(fog.material as ShaderMaterial).set_shader_parameter("density", float(tint.get("fog_density", 0.35)))
	if tint.has("wisps"):
		var c := _col(tint.wisps)
		for w in view._wisps:
			w.modulate = Color(c.r, c.g, c.b, w.modulate.a)
	var em := view.bg_layer.get_node_or_null("Embers") as CPUParticles2D
	if em != null:
		_style_ambient(em, str(arena.get("ambient", "embers")))


func _col(a) -> Color:
	if a is Array:
		return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]) if a.size() > 3 else 1.0)
	return Color.WHITE


func _add_mat() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m


func _ramp(a: Color, b: Color, mid: float = -1.0, mid_c: Color = Color.WHITE) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, a)
	g.set_color(1, b)
	if mid >= 0.0:
		g.add_point(mid, mid_c)
	return g


func _tex(name: String) -> Texture2D:
	return UiSkin.tex(name) if UiSkin.has(name) else UI.dot_texture()


## A warm 2D light. It only touches the arena layer (cards and UI live on other canvas layers), and it reads the
## board's normal map when one is set.
func _light(pos: Vector2, color: Color, energy: float, size: float) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = UI.dot_texture()
	l.texture_scale = size * 4.0
	l.color = color
	l.energy = energy
	l.height = 60.0
	l.position = pos
	l.range_item_cull_mask = LIGHT_MASK
	return l


# ---------------------------------------------------------------- ambient particles

## The battle view's full-screen "Embers" emitter, restyled: embers rising (default), motes floating (Limbo),
## dust blown sideways (Lust), hot embers (Dis) or snow falling (Cocytus).
func _style_ambient(em: CPUParticles2D, kind: String) -> void:
	em.set_meta("ambient", kind)
	match kind:
		"motes":
			em.amount = 60
			em.lifetime = 12.0
			em.preprocess = 12.0
			em.direction = Vector2.UP
			em.spread = 180.0
			em.gravity = Vector2(4, -3)
			em.initial_velocity_min = 4.0
			em.initial_velocity_max = 18.0
			em.scale_amount_min = 0.05
			em.scale_amount_max = 0.14
			em.color_ramp = _ramp(Color(0.9, 1.0, 0.75, 0.0), Color(0.8, 0.9, 0.6, 0.0), 0.5, Color(0.95, 1.0, 0.8, 0.7))
		"dust":
			em.amount = 90
			em.lifetime = 7.0
			em.preprocess = 7.0
			em.direction = Vector2.RIGHT
			em.spread = 15.0
			em.gravity = Vector2(40, -4)
			em.initial_velocity_min = 60.0
			em.initial_velocity_max = 160.0
			em.scale_amount_min = 0.04
			em.scale_amount_max = 0.12
			em.color_ramp = _ramp(Color(0.85, 0.75, 0.95, 0.0), Color(0.7, 0.6, 0.85, 0.0), 0.3, Color(0.9, 0.82, 1.0, 0.6))
		"embers_hot":
			em.amount = 120
			em.initial_velocity_max = 110.0
			em.scale_amount_max = 0.26
			em.color_ramp = _ramp(Color(1.0, 0.45, 0.1, 0.0), Color(0.8, 0.1, 0.02, 0.0), 0.2, Color(1.0, 0.55, 0.15, 1.0))
		"snow":
			em.amount = 110
			em.lifetime = 16.0
			em.preprocess = 16.0
			em.direction = Vector2.DOWN
			em.spread = 20.0
			em.gravity = Vector2(10, 14)
			em.initial_velocity_min = 25.0
			em.initial_velocity_max = 60.0
			em.scale_amount_min = 0.05
			em.scale_amount_max = 0.16
			em.color_ramp = _ramp(Color(0.85, 0.95, 1.0, 0.0), Color(0.8, 0.9, 1.0, 0.0), 0.15, Color(0.92, 0.97, 1.0, 0.85))


func _layout_ambient() -> void:
	var em := view.bg_layer.get_node_or_null("Embers") as CPUParticles2D
	if em == null or not em.has_meta("ambient"):
		return
	match str(em.get_meta("ambient")):
		"motes", "dust":
			em.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
			em.position = Vector2(V.x / 2 - (300.0 if em.get_meta("ambient") == "dust" else 0.0), V.y / 2)
			em.emission_rect_extents = Vector2(V.x / 2 + 300.0, V.y / 2)
		"snow":
			em.position = Vector2(V.x / 2 - 100.0, -30.0)
			em.emission_rect_extents = Vector2(V.x / 2 + 200.0, 10.0)


# ---------------------------------------------------------------- divider

func _build_divider() -> void:
	var d := divider()
	match divider_kind():
		"stream":
			# The water itself is the battle view's river shader (so ripples work); add glints on it.
			var g := _band_particles("k_star_04", 22, 2.4, Color(0.85, 1.0, 0.9, 0.0), Color(0.9, 1.0, 0.95, 0.9))
			g.gravity = Vector2(18, 0)
			g.initial_velocity_min = 8.0
			g.initial_velocity_max = 20.0
			g.direction = Vector2.RIGHT
			g.spread = 5.0
			g.scale_amount_min = 0.03
			g.scale_amount_max = 0.07
			g.angular_velocity_min = -90.0
			g.angular_velocity_max = 90.0
		"wind":
			_band_h = float(d.get("height", 150))
			_band = ColorRect.new()
			_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_band_mat = ShaderMaterial.new()
			_band_mat.shader = WIND_SHADER
			_band.material = _band_mat
			add_child(_band)
			# Thin streaks racing across with the current.
			var s := _band_particles("k_trace_02", 26, 1.6, Color(0.95, 0.9, 1.0, 0.0), Color(0.95, 0.92, 1.0, 0.5))
			s.direction = Vector2.RIGHT
			s.spread = 3.0
			s.gravity = Vector2.ZERO
			s.initial_velocity_min = 700.0
			s.initial_velocity_max = 1100.0
			s.particle_flag_align_y = true
			s.scale_amount_min = 0.12
			s.scale_amount_max = 0.3
			s.material = _add_mat()
			# The souls of the lustful, whirled round at both edges of the board.
			for side in 2:
				var w := CPUParticles2D.new()
				w.texture = _tex("k_smoke_07")
				w.amount = 14
				w.lifetime = 5.0
				w.preprocess = 5.0
				w.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
				w.emission_sphere_radius = 120.0
				w.gravity = Vector2.ZERO
				w.direction = Vector2.UP
				w.spread = 180.0
				w.initial_velocity_min = 10.0
				w.initial_velocity_max = 30.0
				w.orbit_velocity_min = 0.12 if side == 0 else -0.16
				w.orbit_velocity_max = 0.2 if side == 0 else -0.24
				w.angular_velocity_min = -60.0
				w.angular_velocity_max = 60.0
				w.angle_min = -180.0
				w.angle_max = 180.0
				w.scale_amount_min = 0.25
				w.scale_amount_max = 0.5
				w.color_ramp = _ramp(Color(0.75, 0.7, 0.95, 0.0), Color(0.7, 0.65, 0.9, 0.0), 0.4, Color(0.8, 0.75, 1.0, 0.22))
				w.material = _add_mat()
				add_child(w)
				_edge_souls.append(w)
		"embers", "frost":
			var hot := divider_kind() == "embers"
			_band_h = float(d.get("height", 120))
			if hot:
				# Heat shimmer rising off the crack (drawn first: it wobbles the board under the crack's glow).
				_haze = ColorRect.new()
				_haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
				var hm := ShaderMaterial.new()
				hm.shader = HAZE_SHADER
				_haze.material = hm
				add_child(_haze)
			_band = ColorRect.new()
			_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_band_mat = ShaderMaterial.new()
			_band_mat.shader = CRACK_SHADER
			_band.material = _band_mat
			add_child(_band)
			if hot:
				_band_mat.set_shader_parameter("core_color", Color(1.0, 0.85, 0.45, 1.0))
				_band_mat.set_shader_parameter("glow_color", Color(1.0, 0.32, 0.06, 0.8))
				_band_mat.set_shader_parameter("flow_speed", 0.5)
				var sp := _band_particles("k_spark_01", 70, 2.6, Color(1.0, 0.8, 0.4, 0.0), Color(1.0, 0.55, 0.15, 1.0))
				sp.direction = Vector2.UP
				sp.spread = 18.0
				sp.gravity = Vector2(6, -40)
				sp.initial_velocity_min = 30.0
				sp.initial_velocity_max = 110.0
				sp.scale_amount_min = 0.02
				sp.scale_amount_max = 0.06
				sp.material = _add_mat()
				sp.color_ramp = _ramp(Color(1.0, 0.9, 0.5, 1.0), Color(0.8, 0.15, 0.02, 0.0), 0.3, Color(1.0, 0.55, 0.15, 1.0))
			else:
				_band_mat.set_shader_parameter("core_color", Color(0.8, 0.93, 1.0, 0.5))
				_band_mat.set_shader_parameter("glow_color", Color(0.3, 0.55, 1.0, 0.3))
				_band_mat.set_shader_parameter("rime_color", Color(0.75, 0.9, 1.0, 0.3))
				_band_mat.set_shader_parameter("core_width", 0.022)
				_band_mat.set_shader_parameter("glow_width", 0.09)
				_band_mat.set_shader_parameter("flow_speed", 0.12)
				_band_mat.set_shader_parameter("glint_amount", 0.9)
				_band_mat.set_shader_parameter("rime_amount", 0.8)
				_band_mat.set_shader_parameter("intensity", 0.7)
				_band_mat.set_shader_parameter("angular", 0.85)
				_band_mat.set_shader_parameter("seed", 11.0)
				# Cold mist creeping along the crack (normal blend: it veils the ice).
				var m := _band_particles("k_smoke_07", 16, 9.0, Color(0.75, 0.88, 1.0, 0.0), Color(0.8, 0.9, 1.0, 0.0))
				m.color_ramp = _ramp(Color(0.75, 0.88, 1.0, 0.0), Color(0.8, 0.9, 1.0, 0.0), 0.5, Color(0.8, 0.92, 1.0, 0.16))
				m.material = null
				m.direction = Vector2.RIGHT
				m.spread = 20.0
				m.gravity = Vector2(4, -2)
				m.initial_velocity_min = 8.0
				m.initial_velocity_max = 22.0
				m.scale_amount_min = 0.9
				m.scale_amount_max = 1.6
				m.angular_velocity_min = -8.0
				m.angular_velocity_max = 8.0
				m.angle_min = -180.0
				m.angle_max = 180.0
	if _band_mat != null:
		_band_mat.set_shader_parameter("flares", _flares)


## A looping emitter spread along the divider (laid out in _layout_divider).
func _band_particles(tex: String, amount: int, life: float, c0: Color, c1: Color) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = _tex(tex)
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.color_ramp = _ramp(c0, Color(c1.r, c1.g, c1.b, 0.0), 0.3, c1)
	p.material = _add_mat()
	add_child(p)
	_band_fx.append(p)
	return p


## The divider spans the board between its carved side frames ("span": [x0, x1] in layout units), not the dark
## side bands of screens wider than the board.
func _span() -> Vector2:
	var sp: Array = divider().get("span", [150, 1770])
	return Vector2(maxf(0.0, V.x / 2 + (float(sp[0]) - 960.0) * ky), minf(V.x, V.x / 2 + (float(sp[1]) - 960.0) * ky))


func _layout_divider() -> void:
	var h := _band_h * ky
	var sp := _span()
	if _band != null:
		_band.position = Vector2(sp.x, river_y - h / 2)
		_band.size = Vector2(sp.y - sp.x, h)
		_band_mat.set_shader_parameter("aspect", _band.size.x / h)
	if _haze != null:
		var hh := 240.0 * ky
		_haze.position = Vector2(sp.x, river_y - hh * 0.55)
		_haze.size = Vector2(sp.y - sp.x, hh)
	for p in _band_fx:
		p.position = Vector2((sp.x + sp.y) / 2, river_y)
		p.emission_rect_extents = Vector2((sp.y - sp.x) / 2 * 0.92, 10.0 * ky)
	if not _edge_souls.is_empty():
		var half := minf(960.0 * ky, V.x / 2)
		_edge_souls[0].position = Vector2(V.x / 2 - half + 150.0 * ky, river_y - 40.0 * ky)
		_edge_souls[1].position = Vector2(V.x / 2 + half - 150.0 * ky, river_y + 40.0 * ky)


## A flash running out along the crack from `p` (screen position).
func flare_divider(p: Vector2, strength: float = 1.0) -> void:
	if _band_mat == null:
		return
	var uv := Vector2((p.x - _band.position.x) / maxf(_band.size.x, 1.0), 0.5)
	_flares[_flare_i] = Vector4(uv.x, uv.y, Time.get_ticks_msec() / 1000.0, strength)
	_flare_i = (_flare_i + 1) % 4
	_band_mat.set_shader_parameter("flares", _flares)


func _touch_divider(p: Vector2) -> bool:
	var kind := divider_kind()
	if kind == "river" or kind == "stream":
		return false # the battle view's water ripples
	var sp := _span()
	if absf(p.y - river_y) > maxf(_band_h * 0.5, 60.0) * ky or p.x < sp.x or p.x > sp.y:
		return false
	match kind:
		"wind":
			_gust = 1.0
			_band_mat.set_shader_parameter("gust_x", p.x / V.x)
			Sfx.play("gust", -10.0, 1.1)
			_streak_burst(p)
		"embers":
			flare_divider(p, 1.0)
			Sfx.play("spell_fire", -14.0, 0.8)
			Fx.sparks(view.fx_layer, p, UI.EMBER, 18, 420.0)
			Fx.burst(view.fx_layer, p, UI.EMBER, 26, 260.0, 1.2, 9.0, -160.0, 50.0)
			view.shake(2.0)
		"frost":
			flare_divider(p, 1.0)
			Sfx.play("ice", -10.0, 1.1)
			Fx.burst(view.fx_layer, p, Color(0.7, 0.9, 1.0), 16, 240.0, 0.9, 22.0, 120.0, 180.0, "k_star_04")
			Fx.smoke(view.fx_layer, p, Color(0.75, 0.88, 1.0, 0.35), 160.0, 5)
	return true


func _streak_burst(p: Vector2) -> void:
	var s := CPUParticles2D.new()
	s.texture = _tex("k_trace_02")
	s.position = p
	s.amount = 14
	s.one_shot = true
	s.explosiveness = 0.8
	s.lifetime = 0.7
	s.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	s.emission_rect_extents = Vector2(40, 40 * ky)
	s.direction = Vector2.RIGHT
	s.spread = 6.0
	s.gravity = Vector2.ZERO
	s.initial_velocity_min = 900.0
	s.initial_velocity_max = 1500.0
	s.particle_flag_align_y = true
	s.scale_amount_min = 0.2
	s.scale_amount_max = 0.45
	s.color_ramp = _ramp(Color(1, 1, 1, 0.9), Color(0.85, 0.8, 1.0, 0.0))
	s.material = _add_mat()
	s.z_index = 50
	view.fx_layer.add_child(s)
	s.emitting = true
	s.finished.connect(s.queue_free)


# ---------------------------------------------------------------- toys

func _build_toy(p: Dictionary) -> void:
	var tex_path := PROPS + str(arena.get("id", "")) + "_" + str(p.get("name", "")) + ".png"
	var has_art := ResourceLoader.exists(tex_path)
	if not has_art and not placeholders:
		return # no painted prop yet: the board stays clean rather than showing a floating flame
	var width := float(p.get("width", 160))
	var root := Node2D.new()
	root.name = "Toy_" + str(p.get("name", ""))
	add_child(root)
	var body := Node2D.new()
	root.add_child(body)
	var size := Vector2(width, width * float(p.get("aspect", 1.3)))
	var art: Node2D
	if has_art:
		var sp := Sprite2D.new()
		sp.texture = load(tex_path)
		var k := width / sp.texture.get_size().x
		sp.scale = Vector2(k, k)
		size = sp.texture.get_size() * k
		art = sp
	else:
		art = Shapes.make(Shapes.Kind.ELLIPSE, size * 0.9, Color(1, 1, 1, 0.06), Color(1, 0.9, 0.6, 0.5), 3.0)
		(art as Shapes).use_parent_material = false
	var pivot := str(p.get("pivot", "center"))
	var pv := Vector2(0, -size.y / 2) if pivot == "top" else (Vector2(0, size.y / 2) if pivot == "bottom" else Vector2.ZERO)
	body.position = pv
	art.position = -pv
	body.add_child(art)
	var toy := {"data": p, "root": root, "body": body, "size": size, "art_pos": -pv, "angle": 0.0, "vel": 0.0,
		"kick": 0.0, "seed": randf() * 10.0, "glow_k": 0.0}
	if p.has("flame"):
		_toy_flame(toy, p.flame)
	if p.has("glow"):
		# A glow that flares on a tap: a lantern's glass, or a pair of eyes ("pair": half the gap, in prop widths).
		var gd: Dictionary = p.glow
		var at: Vector2 = toy.art_pos + _at(gd.get("at", [0, 0]), size)
		var pair := float(gd.get("pair", 0.0)) * size.x
		var glows: Array[Sprite2D] = []
		for i in (2 if pair > 0.0 else 1):
			var g := Sprite2D.new()
			g.texture = UI.dot_texture()
			g.material = _add_mat()
			g.modulate = _col(gd.get("color", [1.0, 0.2, 0.1]))
			g.modulate.a = 0.0
			var gs := float(gd.get("size", 0.3))
			g.scale = Vector2(gs, gs * (0.6 if pair > 0.0 else 1.0))
			g.position = at + Vector2(pair * (-1.0 if i == 0 else 1.0), 0)
			body.add_child(g)
			glows.append(g)
		toy["glow"] = glows
		if bool(gd.get("light", false)):
			var l := _light(at, _col(gd.get("color", [1.0, 0.8, 0.5])), 1.0, 2.2)
			body.add_child(l)
			toy["glow_light"] = l
	_toys.append(toy)


func _at(a, size: Vector2) -> Vector2:
	return Vector2(float(a[0]) * size.x, float(a[1]) * size.y) if a is Array else Vector2.ZERO


func _toy_flame(toy: Dictionary, fd: Dictionary) -> void:
	var cols: Array = FLAME_COLORS.get(str(fd.get("color", "fire")), FLAME_COLORS.fire)
	var size: Vector2 = toy.size
	var k := float(fd.get("size", 1.0))
	var f := CPUParticles2D.new()
	f.texture = UI.dot_texture()
	f.material = _add_mat()
	f.amount = int(40 * clampf(k, 0.4, 2.0))
	f.lifetime = 0.9
	f.position = toy.art_pos + _at(fd.get("at", [0, -0.3]), size)
	f.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	f.emission_rect_extents = Vector2(float(fd.get("spread", 0.15)) * size.x, 4)
	f.direction = Vector2.UP
	f.spread = 12.0
	f.gravity = Vector2(float(fd.get("wind", 0.0)), -90)
	f.initial_velocity_min = 30.0 * k
	f.initial_velocity_max = 70.0 * k
	f.scale_amount_min = 0.25 * k
	f.scale_amount_max = 0.55 * k
	f.color_ramp = _ramp(cols[0], cols[1])
	toy.body.add_child(f)
	toy["flame"] = f
	toy["flame_k"] = k
	var l := _light(f.position, cols[2], 1.1, 2.4 * k)
	toy.body.add_child(l)
	toy["light"] = l


func _toy_hit(toy: Dictionary, p: Vector2) -> bool:
	var root: Node2D = toy.root
	var lp := root.to_local(p)
	var half: Vector2 = toy.size * 0.5
	if toy.data.has("hit"):
		half = _at(toy.data.hit, toy.size)
	return absf(lp.x) < half.x and absf(lp.y) < half.y


func _poke(toy: Dictionary, p: Vector2) -> void:
	var d: Dictionary = toy.data
	var root: Node2D = toy.root
	var lp := root.to_local(p)
	match str(d.get("motion", "pulse")):
		"swing", "sway":
			toy.vel += (2.6 if d.get("motion") == "swing" else 1.6) * (1.0 if lp.x < 0 else -1.0)
		"rattle", "flap":
			toy.kick = 1.0
		_:
			var b: Node2D = toy.body
			var t := b.create_tween()
			t.tween_property(b, "scale", Vector2(1.08, 0.94), 0.08)
			t.tween_property(b, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	toy["flare"] = 1.0
	toy["glow_k"] = 1.0
	var sfx: Array = d.get("sfx", [])
	if not sfx.is_empty():
		Sfx.play(str(sfx[0]), float(sfx[1]) if sfx.size() > 1 else -6.0, float(sfx[2]) if sfx.size() > 2 else 1.0)
	if d.has("sfx2"):
		var s2: Array = d.sfx2
		Sfx.play(str(s2[0]), float(s2[1]) if s2.size() > 1 else -6.0, float(s2[2]) if s2.size() > 2 else 1.0)
	var c := root.position + Vector2(0, -toy.size.y * 0.2 * root.scale.y)
	_burst(str(d.get("burst", "")), c)
	if d.has("ring"):
		Fx.shockwave(view.fx_layer, c, _col(d.ring), 260.0 * root.scale.x, 0.8)
	if d.has("shake"):
		view.shake(float(d.shake))
	if bool(d.get("flare_divider", false)):
		for i in 3:
			flare_divider(Vector2(V.x * (0.2 + 0.3 * i), river_y), 1.2)
		_gust = 1.0


func _burst(kind: String, c: Vector2) -> void:
	var fx: Node = view.fx_layer
	match kind:
		"embers":
			Fx.burst(fx, c, UI.EMBER, 50, 320.0, 1.0, 12.0, -120.0)
		"motes":
			Fx.burst(fx, c, Color(0.9, 1.0, 0.7), 30, 160.0, 1.6, 9.0, -30.0)
			Fx.flash(fx, "k_light_02", c, 260.0, 0.7, Color(0.9, 1.0, 0.7, 0.6), 0.0)
		"leaves":
			Fx.burst(fx, c, Color(0.55, 0.7, 0.3), 16, 240.0, 1.4, 12.0, 160.0, 120.0, "k_twirl_01")
		"pages":
			Fx.burst(fx, c, Color(0.95, 0.88, 0.7), 12, 220.0, 1.6, 16.0, 90.0, 120.0, "k_magic_01")
			Fx.burst(fx, c, Color(1.0, 0.95, 0.75), 20, 140.0, 1.4, 8.0, -40.0)
		"souls":
			Fx.burst(fx, c, Color(0.7, 0.75, 1.0), 10, 260.0, 1.8, 40.0, -60.0, 180.0, "k_twirl_02")
			Fx.smoke(fx, c, Color(0.7, 0.68, 0.9, 0.35), 200.0, 6)
		"frost":
			Fx.burst(fx, c, Color(0.7, 0.9, 1.0), 18, 260.0, 0.9, 22.0, 200.0, 180.0, "k_star_04")
			Fx.sparks(fx, c, Color(0.75, 0.9, 1.0), 14, 380.0)
		"snow":
			Fx.burst(fx, c, Color(0.92, 0.97, 1.0), 60, 420.0, 1.8, 9.0, 60.0)
			Fx.smoke(fx, c, Color(0.8, 0.9, 1.0, 0.3), 260.0, 6)
		"dust":
			Fx.dust(fx, c, 120.0, 20)


func layout(p_v: Vector2, p_river_y: float, p_ky: float, _anchors: Dictionary = {}) -> void:
	V = p_v
	river_y = p_river_y
	ky = p_ky
	for toy in _toys:
		var pos: Array = toy.data.get("pos", [160, 300])
		var root: Node2D = toy.root
		root.position = V / 2 + (Vector2(float(pos[0]), float(pos[1])) - Vector2(960, 540)) * ky
		root.scale = Vector2(ky, ky)
	_layout_divider()
	_layout_ambient()


func _process(delta: float) -> void:
	_t += delta
	for toy in _toys:
		_tick_toy(toy, delta)
	if _band_mat != null:
		_band_mat.set_shader_parameter("now", Time.get_ticks_msec() / 1000.0)
		if divider_kind() == "wind":
			_gust = maxf(0.0, _gust - delta * 0.8)
			_wind_time += delta * (1.0 + _gust * 2.5)
			_band_mat.set_shader_parameter("time_offset", _wind_time)
			_band_mat.set_shader_parameter("gust", _gust)
			for s in _band_fx:
				s.speed_scale = 1.0 + _gust * 1.5
		elif divider_kind() == "embers":
			# Now and then the rift breathes out on its own.
			_auto_flare -= delta
			if _auto_flare <= 0.0:
				_auto_flare = randf_range(3.0, 7.0)
				flare_divider(Vector2(randf_range(0.15, 0.85) * V.x, river_y), 0.5)


func _tick_toy(toy: Dictionary, delta: float) -> void:
	var d: Dictionary = toy.data
	var b: Node2D = toy.body
	var idle := float(d.get("idle", 0.0))
	var sd: float = toy.seed
	match str(d.get("motion", "pulse")):
		"swing", "sway":
			var stiff := 30.0 if d.get("motion") == "swing" else 70.0
			toy.vel += -toy.angle * stiff * delta
			toy.vel *= 1.0 - 1.4 * delta
			toy.angle += toy.vel * delta
			b.rotation = toy.angle + idle * (sin(_t * 0.9 + sd) + 0.4 * sin(_t * 2.3 + sd * 2.0))
		"rattle":
			toy.kick = maxf(0.0, toy.kick - delta * 2.5)
			b.rotation = sin(_t * 60.0) * 0.04 * toy.kick + idle * sin(_t * 0.7 + sd)
		"flap":
			toy.kick = maxf(0.0, toy.kick - delta * 1.2)
			var f: float = sin((1.0 - toy.kick) * TAU * 2.0) * toy.kick
			b.scale = Vector2(1.0 - 0.18 * f, 1.0 + 0.06 * f)
			b.rotation = -0.12 * f + idle * sin(_t * 0.5 + sd)
		_:
			if idle > 0.0:
				b.rotation = idle * sin(_t * 0.7 + sd)
	var flare := maxf(0.0, float(toy.get("flare", 0.0)) - delta * 1.5)
	toy["flare"] = flare
	if toy.has("flame"):
		var f: CPUParticles2D = toy.flame
		var k: float = toy.flame_k
		f.speed_scale = 1.0 + flare * 1.5
		f.scale_amount_max = (0.55 + flare * 0.8) * k
		var l: PointLight2D = toy.light
		l.energy = (1.0 + 0.15 * sin(_t * 11.0 + sd) * sin(_t * 5.3)) * (1.0 + flare * 1.5)
	if toy.has("glow"):
		toy.glow_k = maxf(0.0, toy.glow_k - delta * 0.6)
		var base := float(d.glow.get("idle", 0.15))
		var flick := 0.9 + 0.1 * sin(_t * 13.0 + sd) * sin(_t * 7.3)
		var a: float = (base + (1.0 - base) * toy.glow_k) * flick
		for g in toy.glow:
			(g as Sprite2D).modulate.a = a
		if toy.has("glow_light"):
			(toy.glow_light as PointLight2D).energy = 0.4 + 1.4 * a


## Returns true when the touch hit a toy or the divider.
func touch(p: Vector2) -> bool:
	for toy in _toys:
		if _toy_hit(toy, p):
			_poke(toy, p)
			return true
	return _touch_divider(p)


## Screen points that hit each toy and the divider (debug `--poke-toys`, tests).
func toy_points() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for toy in _toys:
		out.append((toy.root as Node2D).position + Vector2(-8, 0))
	out.append(Vector2(V.x * 0.3, river_y))
	return out
