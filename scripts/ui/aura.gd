class_name Aura
extends ColorRect
## Animated highlight around a card or a portrait (assets/shaders/aura.gdshader), centred on the parent's origin.
## Fades in and out instead of popping; the colour presets carry the meaning (playable, selected, target).

const SHADER := preload("res://assets/shaders/aura.gdshader")
const PLAYABLE := [Color(0.85, 1.0, 0.7), Color(0.1, 0.85, 0.3)]
const SELECTED := [Color(1.0, 0.95, 0.7), Color(1.0, 0.5, 0.08)]
const TARGET := [Color(1.0, 0.75, 0.55), Color(0.95, 0.12, 0.04)]
const MAGIC := [Color(0.85, 0.9, 1.0), Color(0.35, 0.45, 1.0)]
const RUSE := [Color(1.0, 0.97, 0.72), Color(0.95, 0.72, 0.12)] ## a playable card whose Ruse is live

var on := false
var _mat: ShaderMaterial
var _tween: Tween


## `shape_size` is the card/oval size in px; `margin` how far the fire reaches beyond it.
static func make(shape_size: Vector2, ellipse: bool = false, margin: float = 42.0, corner: float = 18.0) -> Aura:
	var a := Aura.new()
	a._mat = ShaderMaterial.new()
	a._mat.shader = SHADER
	a.material = a._mat
	a.size = shape_size + Vector2(margin, margin) * 2.0
	a.position = -a.size / 2
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	a._mat.set_shader_parameter("shape", 1 if ellipse else 0)
	a._mat.set_shader_parameter("rect_size", a.size)
	a._mat.set_shader_parameter("margin", margin)
	a._mat.set_shader_parameter("corner", corner)
	a._mat.set_shader_parameter("seed", randf())
	a._mat.set_shader_parameter("strength", 0.0)
	a.visible = false
	a.colors(PLAYABLE)
	return a


func colors(preset: Array) -> void:
	_mat.set_shader_parameter("core_color", preset[0])
	_mat.set_shader_parameter("edge_color", preset[1])


func set_on(v: bool, preset: Array = []) -> void:
	if not preset.is_empty():
		colors(preset)
	if v == on:
		return
	on = v
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if v:
		visible = true
	_tween = create_tween()
	_tween.tween_method(_set_strength, float(_mat.get_shader_parameter("strength")), 1.0 if v else 0.0,
		0.25 if v else 0.2)
	if not v:
		_tween.tween_callback(hide)


func _set_strength(s: float) -> void:
	_mat.set_shader_parameter("strength", s)
