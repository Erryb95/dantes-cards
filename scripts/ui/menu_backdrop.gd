class_name MenuBackdrop
extends Control
## Full-screen animated background for the menus: arena art with a slow push-in, fog, embers.

var _art: TextureRect
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var base := ColorRect.new()
	base.color = Color(0.03, 0.015, 0.012)
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)
	_art = TextureRect.new()
	var path := "res://assets/arenas/acheron.jpg"
	if ResourceLoader.exists(path):
		_art.texture = load(path)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art.modulate = Color(0.55, 0.5, 0.5)
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)
	var fog := ColorRect.new()
	fog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fm := ShaderMaterial.new()
	fm.shader = preload("res://assets/shaders/fog.gdshader")
	fm.set_shader_parameter("density", 0.5)
	fm.set_shader_parameter("vignette", 0.95)
	fog.material = fm
	add_child(fog)
	var embers := CPUParticles2D.new()
	embers.texture = UI.dot_texture()
	embers.amount = 90
	embers.lifetime = 10.0
	embers.preprocess = 10.0
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.direction = Vector2.UP
	embers.spread = 20.0
	embers.gravity = Vector2(10, -10)
	embers.initial_velocity_min = 25.0
	embers.initial_velocity_max = 80.0
	embers.scale_amount_min = 0.05
	embers.scale_amount_max = 0.22
	var er := Gradient.new()
	er.set_color(0, Color(1.0, 0.55, 0.15, 0.0))
	er.add_point(0.2, Color(1.0, 0.6, 0.2, 0.9))
	er.set_color(er.get_point_count() - 1, Color(0.8, 0.2, 0.05, 0.0))
	embers.color_ramp = er
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	embers.material = add
	embers.name = "Embers"
	add_child(embers)
	resized.connect(_on_resized)
	_on_resized()


func _on_resized() -> void:
	var e: CPUParticles2D = get_node("Embers")
	e.position = Vector2(size.x / 2, size.y + 20)
	e.emission_rect_extents = Vector2(size.x / 2, 10)
	_art.pivot_offset = size / 2


func _process(delta: float) -> void:
	_t += delta
	var s := 1.04 + 0.03 * sin(_t * 0.07)
	_art.scale = Vector2(s, s)
