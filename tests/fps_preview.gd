extends Node
## The options panel and the FPS counter on the main menu, for a look.
##   Godot --path . res://tests/fps_preview.tscn --resolution 1920x1080 -- --out=<dir>

var out := "user://fps"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	Game.intro_played = true
	Settings.show_fps = true
	Settings.apply()
	var s: Node = load(Game.MENU).instantiate()
	add_child(s)
	await get_tree().create_timer(1.6).timeout
	await _snap("menu_fps")
	s.add_child(OptionsPanel.new())
	await get_tree().create_timer(0.6).timeout
	await _snap("options")
	get_tree().quit()


func _snap(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
