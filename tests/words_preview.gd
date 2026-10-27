extends Node
## Screenshots of every heading that has painted words (UI.word_tex), to check them in place.
##   Godot --path . res://tests/words_preview.tscn --resolution 1920x1080 -- --out=<dir>

var out := "user://words"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	Game.intro_played = true
	for scene in ["main_menu", "deck_select", "collection", "pack_opening"]:
		var s := _open("res://scenes/%s.tscn" % scene)
		await _wait(1.4)
		await _snap(scene)
		s.queue_free()
		await _wait(0.1)
	var b: Node = _open(Game.BATTLE)
	while not b._mull_waiting:
		await get_tree().process_frame
	await _wait(1.2)
	await _snap("mulligan")
	b._confirm_mulligan()
	for t in [["YOUR TURN", UI.GOLD, 96], ["ENEMY TURN", Color(0.9, 0.5, 0.4), 72]]:
		await _wait(2.4)
		b._show_banner(t[0], t[1], t[2])
		await _wait(0.45)
		await _snap(str(t[0]).to_lower().replace(" ", "_"))
	await _wait(1.6)
	b._open_pause()
	await _wait(0.5)
	await _snap("paused")
	get_tree().quit()


func _open(path: String) -> Node:
	var s: Node = load(path).instantiate()
	add_child(s)
	return s


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _snap(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
