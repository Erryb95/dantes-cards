extends Node2D
## Visual check of the card tilt: renders cards at fixed tilts and saves a screenshot.
##   Godot --path . res://tests/tilt_preview.tscn -- --out=<file.png>

var _out := "user://tilt_preview.png"
var _frames := 0
var _cards: Array[CardView] = []
const TILTS := [Vector2.ZERO, Vector2(0.32, 0.0), Vector2(-0.32, 0.0), Vector2(0.0, 0.3), Vector2(0.25, -0.25)]


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.1, 0.09)
	bg.size = Vector2(1920, 1080)
	add_child(bg)
	var ids := ["mc_lucifer", "pj_beatrice", "cd_minotaur", "ih_whip_demon", "cd_rain_of_fire"]
	for i in TILTS.size():
		var c := CardView.new().setup(ids[i], -1, true)
		c.auto_tilt = false
		c.hold_tilt = true
		c._tilt = TILTS[i]
		c.position = Vector2(220 + i * 370, 540)
		c.scale = Vector2(1.2, 1.2)
		add_child(c)
		c.playable = i % 2 == 0
		c.selected = i == 1
		_cards.append(c)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 50:
		get_viewport().get_texture().get_image().save_png(_out)
		get_tree().quit()
