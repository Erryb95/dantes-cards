extends Node
## Player options, saved to user://settings.cfg. Creates the Music / SFX buses at startup.

const PATH := "user://settings.cfg"

var music_volume := 0.7
var sfx_volume := 0.9
var fullscreen := false
var fast_animations := false
var subtitles := true ## subtitles of the intro narration
var intro_seen := false ## the opening cinematic has been played (or skipped) once
var easy_opponent := false ## the AI plays by simple rules instead of searching for the best line
var coach_seen: Array = [] ## ids of the first-game tips already shown (scripts/battle/coach.gd)


func _ready() -> void:
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	load_settings()
	apply()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	music_volume = cfg.get_value("audio", "music", music_volume)
	sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
	fullscreen = cfg.get_value("video", "fullscreen", fullscreen)
	fast_animations = cfg.get_value("game", "fast_animations", fast_animations)
	subtitles = cfg.get_value("game", "subtitles", subtitles)
	intro_seen = cfg.get_value("game", "intro_seen", intro_seen)
	easy_opponent = cfg.get_value("game", "easy_opponent", easy_opponent)
	coach_seen = cfg.get_value("game", "coach_seen", coach_seen)


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("game", "fast_animations", fast_animations)
	cfg.set_value("game", "subtitles", subtitles)
	cfg.set_value("game", "intro_seen", intro_seen)
	cfg.set_value("game", "easy_opponent", easy_opponent)
	cfg.set_value("game", "coach_seen", coach_seen)
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
