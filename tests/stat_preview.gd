extends Node2D
## Big close-ups of the stat numbers on their painted gems (hand card, minion, hero), with green guides through
## each gem's centre, to check the numbers sit where the gems are.
##   Godot --path . res://tests/stat_preview.tscn --resolution 1920x1080 -- --out=<file.png>

func _ready() -> void:
	var out := "user://stat_preview.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var bg := ColorRect.new()
	bg.color = Color(0.25, 0.25, 0.25)
	bg.size = Vector2(1920, 1080)
	add_child(bg)
	var card := CardView.new().setup("minos", -1, true)
	card.scale = Vector2(2.2, 2.2)
	card.position = Vector2(330, 540)
	add_child(card)
	var snap := {"uid": 7, "id": "minos", "side": 0, "is_hero": false, "attack": 6, "health": 6, "max_health": 6,
		"base_attack": 6, "base_health": 6, "keywords": [], "guard": false, "ward": false, "frozen": false,
		"can_attack": false, "sleeping": false, "silenced": false, "venom": false}
	var m := MinionView.new().setup(snap)
	m.scale = Vector2(2.6, 2.6)
	m.position = Vector2(960, 520)
	add_child(m)
	var hv := HeroView.new().setup({"uid": 1, "side": 0, "id": "dante", "health": 30})
	hv.scale = Vector2(2.4, 2.4)
	hv.position = Vector2(1560, 480)
	add_child(hv)
	await get_tree().create_timer(1.2).timeout
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
