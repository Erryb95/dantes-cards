extends Node2D
## Frames of the minion landing VFX on a clean Acheron board (common, rare, epic power levels), plus the end-turn
## button with its aura, saved as a strip for review.
##   Godot --path . res://tests/landing_preview.tscn --resolution 1920x1080 -- --out=<dir>

func _ready() -> void:
	var out := "user://landing"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var board := Sprite2D.new()
	board.texture = load("res://assets/arenas/acheron_board.jpg")
	board.centered = false
	board.scale = Vector2(1920, 1080) / board.texture.get_size()
	add_child(board)
	var fx := Node2D.new()
	add_child(fx)
	await get_tree().create_timer(0.5).timeout
	var y := 640.0
	var shots := [0.05, 0.15, 0.3, 0.5, 0.8]
	var tints := [UI.EMBER, UI.RARITY.rare, UI.RARITY.epic]
	var t0 := 0.0
	for i in 3:
		var pos := Vector2(560 + i * 400, y)
		Fx.gather(fx, pos + Vector2(0, -60), tints[i], 160.0, 0.22, 20)
	await get_tree().create_timer(0.22).timeout
	for i in 3:
		var pos := Vector2(560 + i * 400, y)
		Fx.dust(fx, pos + Vector2(0, 10), 170.0, 18, Color(0.3, 0.26, 0.22, 0.4))
		Fx.landing(fx, pos, tints[i], 330.0 + i * 60.0, i * 0.5)
	for at in shots:
		await get_tree().create_timer(at - t0).timeout
		t0 = at
		get_viewport().get_texture().get_image().save_png("%s/land_%03d.png" % [out, int(at * 100)])
	get_tree().quit()
