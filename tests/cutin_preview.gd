extends Node
## Visual check of the legendary entrance: loads a battle, plays the cut-in and saves a screenshot mid-way.
##   Godot --path . res://tests/cutin_preview.tscn -- --out=<file.png> [--card=<id>]

func _ready() -> void:
	var out := "user://cutin.png"
	var id := "mc_lucifer"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--card="):
			id = a.substr(7)
	var battle: Node = load(Game.BATTLE).instantiate()
	add_child(battle)
	await get_tree().create_timer(4.0).timeout
	battle._legendary_cutin(id)
	await get_tree().create_timer(0.9).timeout
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
