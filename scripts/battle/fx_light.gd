class_name FxLight
## Light thrown by spell effects onto the board, the cards and the minions around them: a soft additive PointLight2D
## in the effect's school colour that swells and dies away (or rides a missile). Fire, holy, judgment and lightning
## light the table strongly; venom or wind barely. At most MAX lights live at once (the oldest is dropped), and none
## exist between effects, so a quiet board pays nothing for lighting. The effects' own additive sprites are unshaded
## (Vfx._add, Fx materials, vfx_live / aura shaders): only the painted board, cards and portraits catch the light.

const MAX := 4
const TEX_SIZE := 128
## How strongly each school lights its surroundings (0 = not at all).
const SCHOOL := {
	"fire": 1.0, "pitch": 0.85, "judgment": 1.0, "holy": 1.0, "gold": 0.75, "soul": 0.6, "shadow": 0.65,
	"ice": 0.55, "word": 0.55, "stone": 0.45, "blood": 0.35, "venom": 0.4, "water": 0.35, "wind": 0.3, "thorn": 0.25,
}

## Off switch (a low-end setting, or DV_NOFXLIGHT=1 to compare with and without).
static var enabled := OS.get_environment("DV_NOFXLIGHT") == ""
static var _active: Array[PointLight2D] = []
static var _tex: GradientTexture2D


## The light's falloff: a smooth radial gradient (bright core, long soft tail), shared by every light.
static func texture() -> Texture2D:
	if _tex == null:
		_tex = GradientTexture2D.new()
		_tex.width = TEX_SIZE
		_tex.height = TEX_SIZE
		_tex.fill = GradientTexture2D.FILL_RADIAL
		_tex.fill_from = Vector2(0.5, 0.5)
		_tex.fill_to = Vector2(1.0, 0.5)
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.18, 0.45, 0.75, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1), Color(0.8, 0.8, 0.8), Color(0.36, 0.36, 0.36),
			Color(0.08, 0.08, 0.08), Color(0, 0, 0)])
		_tex.gradient = g
	return _tex


## A light at `pos` (in `parent`'s space) of `radius` px that rises to `energy` (scaled by the school) in `rise` s,
## then fades out over `life` s and frees itself. `life` <= 0 keeps it lit until `release` (for a moving missile).
## Returns null when the school casts no light.
static func add(parent: Node, pos: Vector2, s: Dictionary, radius: float, energy: float, life: float,
		rise: float = 0.05) -> PointLight2D:
	var k: float = SCHOOL.get(s.get("name", ""), 0.4)
	if not enabled or k <= 0.0 or parent == null or not parent.is_inside_tree():
		return null
	_active = _active.filter(func(l): return is_instance_valid(l) and l.is_inside_tree())
	while _active.size() >= MAX:
		release(_active.pop_front(), 0.08) # the oldest gives way quickly instead of popping off
	var l := PointLight2D.new()
	l.texture = texture()
	l.texture_scale = radius * 2.0 / TEX_SIZE
	l.color = (s.color as Color).lerp(s.hot, 0.3)
	l.blend_mode = Light2D.BLEND_MODE_ADD
	l.energy = 0.0
	l.position = pos
	l.height = radius * 0.35 # for normal-mapped art: the light hangs above the table
	parent.add_child(l)
	_active.append(l)
	var t := l.create_tween()
	l.set_meta("tween", t)
	t.tween_property(l, "energy", energy * k, rise)
	if life > 0.0:
		t.tween_property(l, "energy", 0.0, life).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		t.tween_callback(l.queue_free)
	return l


## Fades a held light out and frees it.
static func release(l, life: float = 0.3) -> void: # untyped: the light may already be freed
	if not is_instance_valid(l):
		return
	var light: PointLight2D = l
	_active.erase(light)
	if light.has_meta("tween"):
		(light.get_meta("tween") as Tween).kill()
	var t := light.create_tween()
	t.tween_property(light, "energy", 0.0, life)
	t.tween_callback(light.queue_free)


## A flickering light (lightning): a few random pulses, then out.
static func flicker(parent: Node, pos: Vector2, s: Dictionary, radius: float, energy: float, pulses: int = 3) -> void:
	var l := add(parent, pos, s, radius, energy, 0.0, 0.02)
	if l == null:
		return
	var k: float = SCHOOL.get(s.get("name", ""), 0.4)
	(l.get_meta("tween") as Tween).kill()
	var t := l.create_tween()
	l.set_meta("tween", t)
	for i in pulses:
		t.tween_property(l, "energy", energy * k * randf_range(0.2, 0.45), 0.04)
		t.tween_property(l, "energy", energy * k * randf_range(0.8, 1.15), 0.03)
	t.tween_property(l, "energy", 0.0, 0.28)
	t.tween_callback(l.queue_free)


## Lights alive now (tests / debugging).
static func active_count() -> int:
	_active = _active.filter(func(l): return is_instance_valid(l) and l.is_inside_tree())
	return _active.size()
