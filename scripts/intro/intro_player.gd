class_name IntroPlayer
extends Control
## Plays the intro cinematic described by IntroTimeline: full-screen Doré plates / Wan clips (cover, no letterbox, any
## aspect) through a moving camera + engraving shader, narration, music, subtitles over the image, title cards.
## Skippable by holding Esc / Space / gamepad A, or by pressing and holding a mouse button / a finger anywhere, for 1 s
## (ring indicator bottom-right).
## Headless tests drive it with step(dt) (autoplay = false).

signal finished(skipped: bool)

const SKIP_HOLD := 1.0
const SHADER := preload("res://scripts/intro/intro_shot.gdshader")
const EMBER_SPARK := preload("res://scripts/intro/ember_spark.tres")

var tl: Dictionary
var time := 0.0
var autoplay := true
var done := false
var skipped := false
var skip_progress := 0.0
## Tests set this to simulate a held skip key.
var skip_held_override := false
var _mouse_down := false
var _touches := {}                    # finger index -> true while down

var stage: Control          # the whole screen (pictures, embers, title)
var textframe: Control      # centred 2.39:1 box that sizes the cards and the inscription as before (no bars)
var subtitles: IntroSubtitles
var ring: SkipRing
var _black: ColorRect
var _text: Control
var gate_text: GateInscription
var title_fx: TitleReveal
var _embers: CPUParticles2D
var _states: Array[Dictionary] = []   # per shot: {rect, mat, video, active}
var _voice_i := 0
var _cue_i := 0
var _live: Array[Dictionary] = []     # playing audio: {player, base_db, t0, fade_in, t_out, fade_out}
var _voice_active := {}               # voice id -> {end}
var _ending := -1.0
var _hint_t := 1.0                    # the skip hint shows from here for 3 s; input renews it
var _duck := 1.0                      # linear gain applied to cues marked "duck" while narration speaks
var _voice_len := {}                  # voice id -> seconds (from the stream)
var _shake_seed := 0.0


func _ready() -> void:
	if tl.is_empty():
		tl = IntroTimeline.build()
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not (get_parent() is CanvasLayer or get_parent() is Window):
		set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	stage = Control.new()
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	for shot in tl["shots"]:
		_states.append(_make_state(shot))
	_embers = _make_embers()
	stage.add_child(_embers)
	textframe = Control.new()
	textframe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(textframe)
	_text = Control.new()
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_text.draw.connect(_draw_text)
	textframe.add_child(_text)
	gate_text = GateInscription.new()
	textframe.add_child(gate_text)
	title_fx = TitleReveal.new()
	stage.add_child(title_fx)
	subtitles = IntroSubtitles.new()
	add_child(subtitles)
	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 0)  # fades in only when the cinematic is skipped
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_black)
	ring = SkipRing.new()
	add_child(ring)
	resized.connect(_layout)
	if get_parent() is CanvasLayer or get_parent() is Window:
		get_viewport().size_changed.connect(_fit)
		_fit()
	_layout()
	var gate: Dictionary = IntroTimeline.shot_by_id(tl["shots"], "gate")
	if gate.is_empty():
		gate_text.voice_t = -1000.0
		gate_text.shot_end = -1000.0
	else:
		for v in tl["voices"]:
			if v["id"] == "gate":
				gate_text.voice_t = float(v["t"])
		gate_text.shot_end = float(gate["start"]) + float(gate["dur"])
	var title: Dictionary = IntroTimeline.shot_by_id(tl["shots"], "title")
	title_fx.shot_start = float(title.get("start", -1000.0))
	title_fx.shot_dur = float(title.get("dur", 0.0))
	for v in tl["voices"]:
		var path: String = IntroTimeline.DIR + String(v["file"])
		if ResourceLoader.exists(path):
			_voice_len[v["id"]] = (load(path) as AudioStream).get_length()
	set_process(autoplay)
	set_process_input(true)


func _make_state(shot: Dictionary) -> Dictionary:
	var st := {"rect": null, "mat": null, "video": null, "active": false, "tex": null, "win": Rect2(0, 0, 1, 1)}
	if shot["kind"] == "black":
		return st
	var r := ColorRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.color = Color.WHITE
	r.visible = false
	var m := ShaderMaterial.new()
	m.shader = SHADER
	r.material = m if OS.get_environment("DV_NOSHADER") == "" else null
	var plate: String = IntroTimeline.DIR + String(shot["plate"])
	if ResourceLoader.exists(plate):
		st["tex"] = load(plate)
	m.set_shader_parameter("tex", st["tex"])
	m.set_shader_parameter("mist", float(shot.get("mist", 0.0)))
	m.set_shader_parameter("flicker", float(shot.get("flicker", 0.0)))
	m.set_shader_parameter("ember", float(shot.get("ember", 0.0)))
	stage.add_child(r)
	st["rect"] = r
	st["mat"] = m
	return st


func _make_embers() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = 70
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(600, 4)
	p.direction = Vector2(0.15, -1)
	p.spread = 25.0
	p.gravity = Vector2(10, 0)
	p.initial_velocity_min = 22.0
	p.initial_velocity_max = 62.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.5
	p.texture = EMBER_SPARK
	p.color = Color(1.0, 0.55, 0.2, 0.9)
	var grad := Gradient.new()
	grad.set_offset(0, 0.0)
	grad.set_color(0, Color(1, 1, 1, 0))
	grad.add_point(0.15, Color(1, 0.8, 0.5, 1))
	grad.add_point(0.7, Color(1, 0.4, 0.1, 0.7))
	grad.set_color(1, Color(0.6, 0.1, 0.0, 0))
	p.color_ramp = grad
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	p.modulate.a = 0.0
	return p


## Under a CanvasLayer the anchors have nothing to resolve against: follow the viewport by hand.
func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size


func _layout() -> void:
	var w := size.x
	var h := size.y
	stage.position = Vector2.ZERO
	stage.size = Vector2(w, h)
	# cards / inscription: the box the old 2.39:1 frame had (same text size on 16:9 and wider), centred, nothing drawn
	var fh := IntroTimeline.text_height(w, h)
	var fw := minf(w, fh * IntroTimeline.TEXT_ASPECT)
	textframe.position = Vector2((w - fw) * 0.5, (h - fh) * 0.5)
	textframe.size = Vector2(fw, fh)
	if _embers:
		_embers.position = Vector2(w * 0.5, h + 10.0)
		_embers.emission_rect_extents = Vector2(w * 0.5, 4.0)
	for st in _states:
		if st["mat"]:
			(st["mat"] as ShaderMaterial).set_shader_parameter("aspect", w / maxf(h, 1.0))


func _input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventJoypadButton:
		_hint_t = time
	elif event is InputEventMouseButton:
		_hint_t = time
		if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_mouse_down = (event as InputEventMouseButton).pressed
	elif event is InputEventScreenTouch:
		_hint_t = time
		if (event as InputEventScreenTouch).pressed:
			_touches[(event as InputEventScreenTouch).index] = true
		else:
			_touches.erase((event as InputEventScreenTouch).index)


## True while a skip input is held: Esc, Space, gamepad A, the left mouse button or a finger.
func skip_held() -> bool:
	return skip_held_override or _mouse_down or not _touches.is_empty() or Input.is_key_pressed(KEY_ESCAPE) \
		or Input.is_key_pressed(KEY_SPACE) or Input.is_joy_button_pressed(0, JOY_BUTTON_A)


func _process(delta: float) -> void:
	step(delta)


## Advances the cinematic by dt seconds (called from _process, or directly by tests).
func step(dt: float) -> void:
	if done:
		return
	# Skip hold.
	if skip_held() and _ending < 0.0:
		skip_progress = minf(skip_progress + dt / SKIP_HOLD, 1.0)
		_hint_t = time
		if skip_progress >= 1.0:
			skipped = true
			_ending = 0.8
	else:
		skip_progress = maxf(skip_progress - dt * 2.0, 0.0)
	var hint := clampf(1.0 - (time - _hint_t - 3.0) / 1.0, 0.0, 1.0) * clampf((time - 1.0) / 1.0, 0.0, 1.0)
	ring.set_state(skip_progress, hint)

	if _ending >= 0.0:
		_ending -= dt
		var k := clampf(_ending / 0.8, 0.0, 1.0)
		_black.color.a = 1.0 - k
		for l in _live:
			if is_instance_valid(l["player"]):
				(l["player"] as AudioStreamPlayer).volume_db = linear_to_db(maxf(k, 0.0001)) + float(l["base_db"])
		if _ending <= 0.0:
			_finish()
		return

	time += dt
	_fire_cues()
	_update_voices()
	_update_ducking(dt)
	_update_audio()
	_update_shots()
	_text.queue_redraw()
	_update_text_fx()
	if time >= float(tl["total"]):
		_finish()


func _update_text_fx() -> void:
	var gi := _shot_index("gate")
	var ga := 0.0
	if gi >= 0 and _states[gi]["active"]:
		ga = (_states[gi]["mat"] as ShaderMaterial).get_shader_parameter("fade")
	gate_text.set_state(time, ga)
	title_fx.set_state(time)


## Jumps the cinematic to `t` seconds (debug `--intro-from=`): voices and cues that lie before `t` are skipped.
func seek(t: float) -> void:
	time = t
	while _cue_i < tl["cues"].size() and float(tl["cues"][_cue_i]["t"]) < t:
		_cue_i += 1
	while _voice_i < tl["voices"].size() and float(tl["voices"][_voice_i]["t"]) < t:
		_voice_i += 1


func _finish() -> void:
	if done:
		return
	done = true
	for l in _live:
		if is_instance_valid(l["player"]):
			(l["player"] as AudioStreamPlayer).stop()
			(l["player"] as AudioStreamPlayer).queue_free()
	_live.clear()
	for st in _states:
		if st["video"] and is_instance_valid(st["video"]):
			(st["video"] as VideoStreamPlayer).stop()
	finished.emit(skipped)


# --- audio ------------------------------------------------------------------------------------

## The game has Music and SFX buses only: narration and ambience follow the effects volume.
func _bus(name: String) -> StringName:
	if AudioServer.get_bus_index(name) >= 0:
		return StringName(name)
	if name in ["Voice", "Ambience"] and AudioServer.get_bus_index("SFX") >= 0:
		return &"SFX"
	return &"Master"


func _play(file: String, bus: String, db: float, fade_in: float, loop: bool, dur: float, fade_out: float, duck := false) -> AudioStreamPlayer:
	var path := IntroTimeline.path(file)
	if not ResourceLoader.exists(path):
		return null
	var stream := load(path) as AudioStream
	if loop and stream is AudioStreamOggVorbis:
		stream = (stream as AudioStreamOggVorbis).duplicate()
		(stream as AudioStreamOggVorbis).loop = true
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = _bus(bus)
	p.volume_db = db if fade_in <= 0.0 else -60.0
	add_child(p)
	p.play()
	_live.append({"player": p, "base_db": db, "t0": time, "fade_in": fade_in,
		"t_out": time + dur if dur > 0.0 else INF, "fade_out": fade_out, "duck": duck})
	return p


func _fire_cues() -> void:
	var cues: Array = tl["cues"]
	while _cue_i < cues.size() and float(cues[_cue_i]["t"]) <= time:
		var c: Dictionary = cues[_cue_i]
		_cue_i += 1
		_play(String(c["file"]), String(c["bus"]), float(c["db"]), float(c.get("fade_in", 0.0)),
			bool(c.get("loop", false)), float(c.get("dur", 0.0)), float(c.get("fade_out", 0.0)), bool(c.get("duck", false)))


## Music / ambience / low effects sink by IntroTimeline.DUCK_DB while a narration line is speaking (fast attack,
## slow release), so the human voice always sits clearly on top of the score.
func _update_ducking(dt: float) -> void:
	var speaking := false
	for k in _voice_active:
		var va: Dictionary = _voice_active[k]
		if time >= float(va["start"]) - 0.2 and time <= float(va["end"]) + 0.1:
			speaking = true
	var target := db_to_linear(IntroTimeline.DUCK_DB) if speaking else 1.0
	var rate := (1.0 - db_to_linear(IntroTimeline.DUCK_DB)) / (0.35 if speaking else 1.6)
	_duck = move_toward(_duck, target, rate * dt)


func _update_audio() -> void:
	for i in range(_live.size() - 1, -1, -1):
		var l: Dictionary = _live[i]
		var p: AudioStreamPlayer = l["player"]
		if not is_instance_valid(p):
			_live.remove_at(i)
			continue
		var gain := 1.0
		if float(l["fade_in"]) > 0.0:
			gain = minf(gain, clampf((time - float(l["t0"])) / float(l["fade_in"]), 0.0, 1.0))
		if time > float(l["t_out"]):
			var fo := maxf(float(l["fade_out"]), 0.01)
			gain = minf(gain, clampf(1.0 - (time - float(l["t_out"])) / fo, 0.0, 1.0))
			if gain <= 0.0:
				p.stop()
		if bool(l.get("duck", false)):
			gain *= _duck
		if float(l["fade_in"]) > 0.0 or time > float(l["t_out"]) or bool(l.get("duck", false)):
			p.volume_db = float(l["base_db"]) + linear_to_db(maxf(gain, 0.0001))
		if not p.playing:
			p.queue_free()
			_live.remove_at(i)


func _update_voices() -> void:
	var voices: Array = tl["voices"]
	while _voice_i < voices.size() and float(voices[_voice_i]["t"]) <= time:
		var v: Dictionary = voices[_voice_i]
		_voice_i += 1
		_play(String(v["file"]), "Voice", 0.0, 0.0, false, 0.0, 0.0)
		var len: float = _voice_len.get(v["id"], 6.0)
		_voice_active[v["id"]] = {"start": time, "end": time + len, "v": v}
		if not bool(v.get("inscription", false)):
			subtitles.show_lines(v["lines"])
	for k in _voice_active.keys():
		if time > float(_voice_active[k]["end"]) + 0.5:
			if not bool(_voice_active[k]["v"].get("inscription", false)):
				subtitles.hide_lines()
			_voice_active.erase(k)


# --- picture ----------------------------------------------------------------------------------

func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func _update_shots() -> void:
	var shots: Array = tl["shots"]
	var xf := IntroTimeline.CROSSFADE
	var emb_alpha := 0.0
	for i in shots.size():
		var shot: Dictionary = shots[i]
		var st: Dictionary = _states[i]
		if shot["kind"] == "black":
			continue
		var s := float(shot["start"])
		var d := float(shot["dur"])
		var on := time >= s - 0.6 and time <= s + d
		if on and not st["active"]:
			_activate(shot, st)
		elif not on and st["active"]:
			_deactivate(st)
		if not st["active"]:
			continue
		var r: ColorRect = st["rect"]
		var m: ShaderMaterial = st["mat"]
		r.visible = time >= s
		var a := _ease((time - s) / xf)
		if i + 1 < shots.size() and shots[i + 1]["kind"] == "black":
			a = minf(a, 1.0 - _ease((time - (s + d - xf)) / xf))
		if i > 0 and shots[i - 1]["kind"] != "black":
			pass
		m.set_shader_parameter("fade", a)
		m.set_shader_parameter("time", time)
		var u := (time - s) / d
		var cf: Vector3 = shot["cam_from"]
		var ct: Vector3 = shot["cam_to"]
		var e := _ease(u) * 0.55 + u * 0.45  # eased but never fully stalls
		var keep: Vector2 = shot.get("keep", Vector2(-1.0, -1.0))
		var win := IntroTimeline.window(cf.lerp(ct, e), stage.size.x / maxf(stage.size.y, 1.0), keep)
		win.position += Vector2(sin(time * 0.37 + i), cos(time * 0.29 + i * 2.0)) * 0.0015 * win.size.x
		var exposure := 0.86
		var red := 0.0
		win.position.x = clampf(win.position.x, 0.0, 1.0 - win.size.x)
		win.position.y = clampf(win.position.y, 0.0, 1.0 - win.size.y)
		st["win"] = win
		m.set_shader_parameter("window", Vector4(win.position.x, win.position.y, win.size.x, win.size.y))
		m.set_shader_parameter("red", red)
		m.set_shader_parameter("exposure", exposure)
		if shot.has("eyes"):
			var ey: Dictionary = shot["eyes"]
			var k := _ease((time - s - float(ey["at"])) / 3.2) * a
			# the coals catch in two stuttering steps before they settle
			k *= 1.0 - 0.25 * (1.0 - _ease((time - s - float(ey["at"]) - 1.0) / 1.0)) * (0.5 + 0.5 * sin(time * 23.0))
			var ea: Vector2 = ey["a"]
			var eb: Vector2 = ey["b"]
			m.set_shader_parameter("coal_a", Vector4(ea.x, ea.y, float(ey["r"]), k))
			m.set_shader_parameter("coal_b", Vector4(eb.x, eb.y, float(ey["r"]), k * 0.94))
		if OS.get_environment("DV_DEBUG") != "" and int(time * 10.0) % 20 == 0:
			print("shot ", shot["id"], " fade=", a, " vis=", r.visible, " rect=", r.size, " win=", win, " tex=", st["tex"], " video=", st["video"])
		if st["video"]:
			var tex: Texture2D = (st["video"] as VideoStreamPlayer).get_video_texture()
			if OS.get_environment("DV_DEBUG") != "" and int(time * 10.0) % 20 == 0:
				print("  video playing=", (st["video"] as VideoStreamPlayer).is_playing(), " tex=", tex, " pos=", (st["video"] as VideoStreamPlayer).stream_position)
			if tex:
				m.set_shader_parameter("tex", tex)
		emb_alpha = maxf(emb_alpha, a * float(shot.get("ember", 0.0)) * 1.6)
	var si := _shot_index("story")  # story card (when present): keep sparks drifting over the black
	if si >= 0 and time >= float(shots[si]["start"]):
		emb_alpha = 0.6
	_embers.modulate.a = move_toward(_embers.modulate.a, minf(emb_alpha, 1.0), 0.02)
	_embers.emitting = _embers.modulate.a > 0.01


func _activate(shot: Dictionary, st: Dictionary) -> void:
	st["active"] = true
	var vpath: String = IntroTimeline.DIR + String(shot.get("video", ""))
	if shot.has("video") and ResourceLoader.exists(vpath) and OS.get_environment("DV_NOVIDEO") == "":
		var vp := VideoStreamPlayer.new()
		vp.stream = load(vpath)
		vp.loop = true
		vp.volume_db = -80.0
		vp.custom_minimum_size = Vector2(2, 2)
		vp.size = Vector2(2, 2)
		vp.modulate.a = 0.0
		stage.add_child(vp)
		vp.play()
		st["video"] = vp


func _deactivate(st: Dictionary) -> void:
	st["active"] = false
	(st["rect"] as ColorRect).visible = false
	if st["video"] and is_instance_valid(st["video"]):
		(st["video"] as VideoStreamPlayer).stop()
		(st["video"] as VideoStreamPlayer).queue_free()
	st["video"] = null


# --- overlay drawing ----------------------------------------------------------------------------

func _shot_index(id: String) -> int:
	for i in tl["shots"].size():
		if tl["shots"][i]["id"] == id:
			return i
	return -1


func _draw_text() -> void:
	var sz := textframe.size
	var shots: Array = tl["shots"]
	_draw_chapter(sz, shots)
	_draw_story(sz, shots)


func _centered(font: Font, txt: String, y: float, fs: int, col: Color, glow := 0.0) -> void:
	if fs <= 0:
		return
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := Vector2((textframe.size.x - w) * 0.5, y)
	if glow > 0.0:
		for j in 3:
			var o := float(j + 1) * fs * 0.03
			_text.draw_string(font, p + Vector2(0, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col.r, col.g, col.b, glow * 0.18))
			_text.draw_string(font, p + Vector2(o, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col.r, col.g, col.b, glow * 0.12))
			_text.draw_string(font, p + Vector2(-o, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col.r, col.g, col.b, glow * 0.12))
	_text.draw_string(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _rule(y: float, half: float, col: Color) -> void:
	var cx := textframe.size.x * 0.5
	_text.draw_line(Vector2(cx - half, y), Vector2(cx - 12.0, y), col, 1.0)
	_text.draw_line(Vector2(cx + 12.0, y), Vector2(cx + half, y), col, 1.0)
	IntroFonts.diamond(_text, Vector2(cx, y), 4.0, col)


func _draw_chapter(sz: Vector2, shots: Array) -> void:
	var s := float(shots[0]["start"]) + 3.2
	var a := _ease((time - s) / 1.8) * (1.0 - _ease((time - s - 4.2) / 1.8))
	if a <= 0.0:
		return
	var fs := int(sz.y * 0.075)
	_centered(IntroFonts.caps(), IntroTimeline.CHAPTER, sz.y * 0.5 + fs * 0.3, fs,
		Color(IntroFonts.BONE.r, IntroFonts.BONE.g, IntroFonts.BONE.b, a))
	_rule(sz.y * 0.5 + fs * 0.9, sz.x * 0.12, Color(IntroFonts.EMBER.r, IntroFonts.EMBER.g, IntroFonts.EMBER.b, a * 0.8))


func _draw_story(sz: Vector2, shots: Array) -> void:
	var si := _shot_index("story")
	if si < 0:
		return
	var s := float(shots[si]["start"])
	var d := float(shots[si]["dur"])
	if time < s or time > s + d:
		return
	var out := 1.0 - _ease((time - (s + d - 1.4)) / 1.4)
	var fs := int(sz.y * 0.058)
	var y := sz.y * 0.5 - fs * 1.6
	for i in IntroTimeline.STORY_CARD.size():
		var a := _ease((time - (s + IntroTimeline.STORY_FIRST + i * IntroTimeline.STORY_STEP)) / 1.4) * out
		if a > 0.0:
			_centered(IntroFonts.body(), IntroTimeline.STORY_CARD[i], y + i * fs * 1.9, fs,
				Color(IntroFonts.BONE.r, IntroFonts.BONE.g, IntroFonts.BONE.b, a))
	_rule(sz.y * 0.5 - fs * 2.7, sz.x * 0.1, Color(IntroFonts.EMBER.r, IntroFonts.EMBER.g, IntroFonts.EMBER.b,
		_ease((time - s - 0.8) / 1.5) * out * 0.7))
