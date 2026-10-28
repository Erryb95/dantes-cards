extends Node
## Sound effects and music. play("slam") picks a random assets/audio/sfx/slam_N.ogg (or slam.ogg);
## a few short card sounds (swish, tick, chime) are synthesised at startup. play_char("<id>_play") plays a
## character's own sound from assets/audio/voices/ (false when it has none).

const SFX_DIR := "res://assets/audio/sfx/"
const UI_DIR := "res://assets/audio/ui/"
const MUSIC_DIR := "res://assets/audio/music/"
## Every character's own sound (tools/audio/character_voices.py): <id>_play, <id>_death, hero_<id>, hero_<id>_defeat.
const CHAR_DIR := "res://assets/audio/voices/"
const VOICES := 12

var _cache := {}
var _char := {} ## name -> AudioStream, or null when the character has no file (the caller falls back)
var _char_last := {} ## name -> msec it last started (the same sound asked twice at once plays once)
var _char_players: Array[AudioStreamPlayer] = [] ## their own players: a burst of effects never cuts a voice off
var _char_next := 0
## The character sounds played, newest last (tests read it; capped).
var char_log: Array[String] = []
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer
var _music_list: Array[String] = []
var _music_i := 0
var _switch_pending := false ## another playlist was asked for while a piece was playing
var _ambience: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_char_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	_music.finished.connect(_next_track)
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = "SFX"
	add_child(_ambience)
	_cache["swish"] = [_synth_swish(0.16, 2400.0)]
	_cache["swish_long"] = [_synth_swish(0.32, 1500.0)]
	_cache["tick"] = [_synth_tone(1800.0, 0.04, 0.5)]
	_cache["chime"] = [_synth_chime()]


func _variants(name: String) -> Array:
	if _cache.has(name):
		return _cache[name]
	var out := []
	for dir in [SFX_DIR, UI_DIR]:
		for ext in [".ogg", ".wav"]:
			if ResourceLoader.exists(dir + name + ext):
				out.append(load(dir + name + ext))
		var i := 0
		while true:
			var base: String = dir + "%s_%d" % [name, i]
			if ResourceLoader.exists(base + ".ogg"):
				out.append(load(base + ".ogg"))
			elif ResourceLoader.exists(base + ".wav"):
				out.append(load(base + ".wav"))
			else:
				break
			i += 1
	_cache[name] = out
	return out


func play(name: String, volume_db: float = 0.0, pitch: float = 1.0, pitch_var: float = 0.06) -> void:
	var v := _variants(name)
	if v.is_empty():
		return
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = v[randi() % v.size()]
	p.volume_db = volume_db
	p.pitch_scale = maxf(0.1, pitch + randf_range(-pitch_var, pitch_var))
	p.play()


## The stream of a character sound, null when it has none.
func char_stream(name: String) -> AudioStream:
	if not _char.has(name):
		var path := CHAR_DIR + name + ".ogg"
		_char[name] = load(path) if ResourceLoader.exists(path) else null
	return _char[name]


func has_char(name: String) -> bool:
	return char_stream(name) != null


## Plays a character's own sound on the SFX bus (so the effects volume applies). False when the character has no
## such file: the caller then plays its generic sound instead.
func play_char(name: String, volume_db: float = -3.0, pitch: float = 1.0) -> bool:
	var s := char_stream(name)
	if s == null:
		return false
	var now := Time.get_ticks_msec()
	if now - int(_char_last.get(name, -100000)) < 250:
		return true # already sounding (two events for the same thing)
	_char_last[name] = now
	var p := _char_players[_char_next]
	_char_next = (_char_next + 1) % _char_players.size()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()
	char_log.append(name)
	if char_log.size() > 64:
		char_log.remove_at(0)
	return true


## Plays the playlist in assets/audio/music/<folder>/ (whole pieces, cN_0.ogg). A piece is never cut: when the
## screen asks for another playlist, the current piece plays to its end and the next one comes from the new list.
func play_music(folder: String) -> void:
	var list: Array[String] = []
	var i := 1
	while ResourceLoader.exists(MUSIC_DIR + "%s/c%d_0.ogg" % [folder, i]):
		list.append(MUSIC_DIR + "%s/c%d_0.ogg" % [folder, i])
		i += 1
	if list.is_empty() or list == _music_list:
		return
	_music_list = list
	_music_i = randi() % list.size()
	if _music.playing:
		_switch_pending = true
		return
	_start_track()


func _start_track() -> void:
	var s: AudioStream = load(_music_list[_music_i])
	_music.stream = s
	_music.volume_db = -6.0
	_music.play()


func _next_track() -> void:
	if _music_list.is_empty():
		return
	if _switch_pending:
		_switch_pending = false # start the new playlist where play_music() put it
	else:
		_music_i = (_music_i + 1) % _music_list.size()
	_start_track()


## Holds the current piece (the intro has its own score) and resumes it from the same point.
func pause_music(paused: bool) -> void:
	_music.stream_paused = paused


func stop_music(fade: float = 1.0) -> void:
	_music_list = []
	var t := create_tween()
	t.tween_property(_music, "volume_db", -60.0, fade)
	t.tween_callback(_music.stop)


func play_ambience(file: String, volume_db: float = -14.0) -> void:
	if file == "" or not ResourceLoader.exists(SFX_DIR + file):
		_ambience.stop()
		return
	var s = load(SFX_DIR + file)
	if s is AudioStreamOggVorbis:
		s.loop = true
	_ambience.stream = s
	_ambience.volume_db = volume_db
	_ambience.play()


# ---------------------------------------------------------------- synthesis (generated in code, no licence)

func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = 44100
	w.data = data
	return w


## Band-passed noise with a falling centre: the "card through the air" swish.
func _synth_swish(length: float, f0: float) -> AudioStreamWAV:
	var n := int(44100 * length)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var hp := 0.0
	for i in n:
		var t := float(i) / n
		var env := sin(PI * pow(t, 0.6)) * (1.0 - t * 0.4)
		var cutoff := f0 * (1.0 - 0.6 * t)
		var a := clampf(cutoff / 44100.0 * TAU, 0.0, 1.0)
		var noise := randf_range(-1.0, 1.0)
		lp += a * (noise - lp)
		hp = lp - hp * 0.0
		out[i] = (lp - 0.5 * hp * 0.0) * env * 1.6
	return _wav(out)


func _synth_tone(freq: float, length: float, vol: float) -> AudioStreamWAV:
	var n := int(44100 * length)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / 44100.0
		out[i] = sin(TAU * freq * t) * exp(-t * 60.0) * vol
	return _wav(out)


func _synth_chime() -> AudioStreamWAV:
	var n := int(44100 * 0.9)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / 44100.0
		var s := 0.0
		for h in [[880.0, 1.0], [1320.0, 0.5], [1760.0, 0.3], [2637.0, 0.15]]:
			s += sin(TAU * h[0] * t) * h[1]
		out[i] = s * exp(-t * 4.5) * 0.28
	return _wav(out)
