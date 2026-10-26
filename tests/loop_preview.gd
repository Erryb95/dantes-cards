extends Node2D
## Visual check of the looping legendary art: cards (face up, tilted, face down) and board minions.
##   Godot --path . res://tests/loop_preview.tscn -- --snap=<file.png> --snap-delay=3
## (the Game autoload's --snap saves the screenshot and quits; run twice with different delays to see the frames change)


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.1, 0.09)
	bg.size = Vector2(1920, 1080)
	add_child(bg)
	var ids := ["francesca", "ugolino", "minos", "cd_capaneus"]
	for i in ids.size():
		var c := CardView.new().setup(ids[i], -1, true)
		c.position = Vector2(260 + i * 420, 330)
		c.scale = Vector2(1.5, 1.5)
		add_child(c)
		if i == 3:
			c.auto_tilt = false
			c.hold_tilt = true
			c._tilt = Vector2(0.25, -0.15)
	var back := CardView.new().setup("ih_nimrod", -1, false)
	back.position = Vector2(260, 830)
	back.scale = Vector2(0.9, 0.9)
	add_child(back)
	var up := CardView.new().setup("ih_nimrod", -1, true)
	up.position = Vector2(560, 830)
	up.scale = Vector2(0.9, 0.9)
	add_child(up)
	var still := CardView.new().setup("mc_lucifer", -1, true) # no loop yet: stays a still
	still.position = Vector2(860, 830)
	still.scale = Vector2(0.9, 0.9)
	add_child(still)
	for i in 3:
		var id: String = ["francesca", "ugolino", "ih_malacoda"][i]
		var m := MinionView.new().setup({"uid": i, "id": id, "side": 0, "attack": 5, "health": 6, "max_health": 6,
			"keywords": [], "sleeping": false})
		m.position = Vector2(1250 + i * 190, 830)
		m.scale = Vector2(1.4, 1.4)
		add_child(m)
