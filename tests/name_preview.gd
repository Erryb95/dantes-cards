extends Node2D
## The painted card names (CardDB.name_tex, assets/cards/names) on real cards, to review them before more are
## ordered: the cards that have one at hand size (top row, with a card that has none for comparison), then Francesca
## and Minos zoomed beside a card without one, and on the right one tilted and one burning half away.
##   Godot --path . res://tests/name_preview.tscn --resolution 1920x1080 -- --out=<file.png>

const PILOT := ["harpy", "francesca", "ugolino", "phlegyas", "cd_accorso", "pj_saint_lucy", "uh_wrathful_shade",
	"minos"]
const PLAIN := "pj_beatrice" ## no painted name: the gilded label, for comparison
const HAND := 0.62 ## BattleView.HAND_SCALE
const ZOOM := 1.9 ## CardZoom.open on a 1080 px tall screen

var _out := "user://name_preview.png"
var _frames := 0
var _burning: CardView


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.1, 0.09)
	bg.size = Vector2(1920, 1080)
	add_child(bg)
	var top: Array = PILOT + [PLAIN]
	for i in top.size():
		_card(top[i], Vector2(130 + i * 207, 150), HAND, "hand" if i < PILOT.size() else "hand, no painted name")
	var big := ["francesca", "minos", PLAIN]
	for i in big.size():
		_card(big[i], Vector2(270 + i * 495, 670), ZOOM, "zoom" if i < 2 else "zoom, no painted name")
	var tilted := _card("ugolino", Vector2(1730, 485), 0.95, "tilted")
	tilted.auto_tilt = false
	tilted.hold_tilt = true
	tilted._tilt = Vector2(0.3, -0.18)
	_burning = _card("uh_wrathful_shade", Vector2(1730, 855), 0.95, "burning")


func _card(id: String, at: Vector2, k: float, note: String) -> CardView:
	var c := CardView.new().setup(id, -1, true)
	c.position = at
	c.scale = Vector2(k, k)
	add_child(c)
	var l := UI.label("%s (%s)" % [id, note], 15, "body", Color(0.85, 0.8, 0.7), 0)
	l.size = Vector2(320, 20)
	l.position = at + Vector2(-160, CardView.H * k / 2.0 + 4.0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(l)
	return c


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 10:
		_burning._set_burn(0.45)
	if _frames == 50:
		get_viewport().get_texture().get_image().save_png(_out)
		get_tree().quit()
