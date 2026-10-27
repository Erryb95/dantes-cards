extends Node
## Player options, saved to user://settings.cfg. Creates the Music / SFX buses at startup.

const PATH := "user://settings.cfg"
const SaveFile := preload("res://scripts/core/save_file.gd")
const DIFFICULTY_NAMES := ["Easy", "Medium", "Hard"]

var music_volume := 0.7
var sfx_volume := 0.9
var fullscreen := false
var fast_animations := false
var subtitles := true ## subtitles of the intro narration
var intro_seen := false ## the opening cinematic has been played (or skipped) once
var difficulty := 0 ## the opponent's BattleAI.Level: 0 Easy, 1 Medium, 2 Hard (new players start on Easy)
var coach_seen: Array = [] ## ids of the first-game tips already shown (scripts/battle/coach.gd)
var deck_choice := {} ## class -> id of the preconstructed deck last picked on Choose your path


func _ready() -> void:
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	load_settings()
	apply()


func load_settings(path: String = PATH) -> void:
	# A missing file keeps the defaults; a damaged one is set aside (SaveFile) and a value of the wrong type keeps its
	# default, so a bad settings file never stops the game from starting.
	var cfg := SaveFile.open(path, not Game.debug_run())
	music_volume = clampf(SaveFile.value(cfg, "audio", "music", music_volume), 0.0, 1.0)
	sfx_volume = clampf(SaveFile.value(cfg, "audio", "sfx", sfx_volume), 0.0, 1.0)
	fullscreen = SaveFile.value(cfg, "video", "fullscreen", fullscreen)
	fast_animations = SaveFile.value(cfg, "game", "fast_animations", fast_animations)
	subtitles = SaveFile.value(cfg, "game", "subtitles", subtitles)
	intro_seen = SaveFile.value(cfg, "game", "intro_seen", intro_seen)
	# Before three levels there was an on/off "easy opponent": off meant the search AI, now Hard.
	if cfg.has_section_key("game", "easy_opponent"):
		difficulty = 0 if SaveFile.value(cfg, "game", "easy_opponent", true) else 2
	difficulty = clampi(SaveFile.value(cfg, "game", "difficulty", difficulty), 0, DIFFICULTY_NAMES.size() - 1)
	coach_seen = SaveFile.value(cfg, "game", "coach_seen", coach_seen)
	deck_choice = SaveFile.value(cfg, "game", "deck_choice", deck_choice)


## Tests and tooling runs (`Game.debug_run()`) keep their changes in memory: the player's real settings are never written.
func save() -> void:
	if Game.debug_run():
		return
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("game", "fast_animations", fast_animations)
	cfg.set_value("game", "subtitles", subtitles)
	cfg.set_value("game", "intro_seen", intro_seen)
	cfg.set_value("game", "difficulty", difficulty)
	cfg.set_value("game", "coach_seen", coach_seen)
	cfg.set_value("game", "deck_choice", deck_choice)
	cfg.save(PATH)


func apply() -> void:
	_set_bus("Music", music_volume)
	_set_bus("SFX", sfx_volume)
	if is_desktop() and DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)


func _set_bus(bus: String, v: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i != -1:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.001)


func is_desktop() -> bool:
	return OS.has_feature("pc")


func is_mobile() -> bool:
	return OS.has_feature("mobile")


## Animation speed multiplier (1.0 normal).
func anim_speed() -> float:
	return 1.6 if fast_animations else 1.0
