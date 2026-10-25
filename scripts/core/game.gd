extends Node
## Run state and scene flow: menu -> deck choice -> arena -> battle -> result.

const MENU := "res://scenes/main_menu.tscn"
const DECK_SELECT := "res://scenes/deck_select.tscn"
const BATTLE := "res://scenes/battle.tscn"
const COLLECTION := "res://scenes/collection.tscn"

var player_deck := "pilgrim"
var enemy_deck := "ferry"
var arena_id := "acheron"
var last_winner := -1
var stats := {"wins": 0, "losses": 0}

var _fade: ColorRect
var _layer: CanvasLayer


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_fade)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--snap="):
			_snap(a.substr(7))
	var cfg := ConfigFile.new()
	if cfg.load("user://progress.cfg") == OK:
		stats = cfg.get_value("run", "stats", stats)


## Debug: `-- --snap=file.png` saves one screenshot of the opening scene and quits.
func _snap(path: String) -> void:
	await get_tree().create_timer(3.0).timeout
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


func start_battle(deck_id: String) -> void:
	player_deck = deck_id
	enemy_deck = "ferry" if deck_id == "pilgrim" else "pilgrim"
	go(BATTLE)


func record_result(winner: int) -> void:
	last_winner = winner
	if winner == 0:
		stats.wins += 1
	elif winner == 1:
		stats.losses += 1
	var cfg := ConfigFile.new()
	cfg.set_value("run", "stats", stats)
	cfg.save("user://progress.cfg")


## Fades to black, swaps the scene, fades back in.
func go(path: String) -> void:
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, 0.35)
	await t.finished
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	var t2 := create_tween()
	t2.tween_property(_fade, "color:a", 0.0, 0.45)
	await t2.finished
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
