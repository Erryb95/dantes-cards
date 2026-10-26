extends Node
## Headless checks of the opening cinematic. Run: Godot --headless --path . res://tests/intro_test.tscn
## The timeline builds and every file it references exists, the narration subtitles are exact Longfellow (searched in
## tests/data/longfellow_inferno_excerpt.txt), narration fits its shot and never overlaps, every picture covers the screen
## at phone / desktop aspects, the story card fits, the player runs to the end by itself, and holding any skip input
## (key, mouse button, finger) for 1 s ends it early.
## Prints "INTRO TESTS OK" or exits with code 1. Nothing here waits for the real intro: the player is stepped by hand.

const TEXT_PATH := "res://tests/data/longfellow_inferno_excerpt.txt"

var _failed: Array[String] = []
var _count := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	await _run()
	print("INTRO checks: %d" % _count)
	if _failed.is_empty():
		print("INTRO TESTS OK")
		get_tree().quit(0)
	else:
		print("INTRO TESTS FAILED: ", ", ".join(_failed))
		get_tree().quit(1)


func check(name: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failed.append(name)
		print("INTRO %-44s FAIL %s" % [name, detail])


## Collapses whitespace and removes the curly quotes of the Gutenberg text.
static func norm(s: String) -> String:
	var t := s.replace("“", "").replace("”", "").replace("’", "'").replace("‘", "'")
	var re := RegEx.new()
	re.compile("\\s+")
	return re.sub(t, " ", true).strip_edges()


func _new_player(host: Control) -> IntroPlayer:
	var p := IntroPlayer.new()
	p.autoplay = false
	host.add_child(p)
	return p


func _run() -> void:
	var tl := IntroTimeline.build()
	var total := float(tl["total"])
	check("duration 70..120 s", total >= 70.0 and total <= 120.0, "%.1f" % total)
	var ids: Array[String] = []
	for s in tl["shots"]:
		ids.append(String(s["id"]))
	check("shot order", ids == ["open", "forest", "panther", "lion", "virgil", "gate", "charon", "story", "title"], str(ids))
	check("has voices / cues", tl["voices"].size() == 4 and tl["cues"].size() >= 8)
	var last_t := -1.0
	for c in tl["cues"]:
		check("cues sorted " + String(c["id"]), float(c["t"]) >= last_t)
		last_t = float(c["t"])

	for f in IntroTimeline.files(tl):
		check("file exists " + f.trim_prefix(IntroTimeline.DIR), ResourceLoader.exists(f))
	for f in ["res://assets/fonts/Cinzel.ttf", "res://assets/fonts/IMFeENrm28P.ttf"]:
		check("font exists " + f.get_file(), ResourceLoader.exists(f))

	# Every picture covers the screen at any aspect (no letterbox): windows stay inside the texture.
	for asp in [4.0 / 3.0, 16.0 / 10.0, 16.0 / 9.0, 20.0 / 9.0, 21.0 / 9.0]:
		for s in tl["shots"]:
			if s.has("cam_from"):
				for cam in [s["cam_from"], s["cam_to"]]:
					var w := IntroTimeline.window(cam, asp, s.get("keep", Vector2(-1, -1)))
					var ok := w.position.x >= -0.0001 and w.position.y >= -0.0001 and w.end.x <= 1.0001 and w.end.y <= 1.0001
					ok = ok and absf(w.size.x * IntroTimeline.TEX_ASPECT / w.size.y - asp) < 0.01
					check("cover window %s @%.2f" % [s["id"], asp], ok, str(w))

	# Subtitles = exact Longfellow.
	var raw := FileAccess.get_file_as_string(TEXT_PATH)
	check("Longfellow excerpt readable", raw.length() > 5000)
	var book := norm(raw)
	for v in tl["voices"]:
		var lines: Array = v["lines"]
		if v.get("inscription", false):  # a cut-down reading of the gate: the lines are not consecutive, check each one
			for l in lines:
				check("line exact: " + String(l).left(30), book.contains(norm(String(l))))
		else:
			check("verse exact: " + String(v["id"]), book.contains(norm(" ".join(PackedStringArray(lines)))))
	# The gate inscription is the same text as the narration, line for line.
	for v in tl["voices"]:
		if v["id"] == "gate":
			var lines: Array = v["lines"]
			check("inscription line count", IntroTimeline.INSCRIPTION.size() == lines.size() and IntroTimeline.INSCRIPTION_TIMES.size() == lines.size())
			for i in mini(lines.size(), IntroTimeline.INSCRIPTION.size()):
				check("inscription = narration line %d" % i, String(IntroTimeline.INSCRIPTION[i]) == String(lines[i]).to_upper(),
					String(IntroTimeline.INSCRIPTION[i]))
	var gate_len := (load(IntroTimeline.DIR + "voice/v_c_gate.ogg") as AudioStream).get_length()
	var prev_end := -1.0
	for sp in IntroTimeline.INSCRIPTION_TIMES:
		check("inscription line timing ordered", sp.x >= prev_end - 0.01 and sp.y > sp.x and sp.y <= gate_len + 0.05, str(sp))
		prev_end = sp.y

	# Card game wording: title and story.
	check("title is Dante's Inferno", IntroTimeline.TITLE == "DANTE'S INFERNO" and IntroTimeline.TITLE_SUB == "THE CARD GAME")
	check("story card has 3 lines", IntroTimeline.STORY_CARD.size() == 3)
	for l in IntroTimeline.STORY_CARD:
		check("story line avoids FPS wording", not String(l).to_lower().contains("vengeance"))
		for sz in [Vector2(1920, 1080), Vector2(2400, 1080), Vector2(1728, 1080), Vector2(1440, 1080)]:
			var fh := IntroTimeline.text_height(sz.x, sz.y)
			var fw := minf(sz.x, fh * IntroTimeline.TEXT_ASPECT)
			var w := IntroFonts.body().get_string_size(String(l), HORIZONTAL_ALIGNMENT_LEFT, -1, int(fh * 0.058)).x
			check("story line fits %dx%d" % [sz.x, sz.y], w < fw * 0.94, "%d of %d" % [w, fw])
	var story := IntroTimeline.shot_by_id(tl["shots"], "story")
	check("story shot long enough", float(story["dur"]) >= IntroTimeline.STORY_FIRST + 3.0 * IntroTimeline.STORY_STEP)
	check("title ends the film", is_equal_approx(total, float(tl["shots"][tl["shots"].size() - 1]["start"]) + 9.0))

	# Narration fits inside its shot and never overlaps another line.
	var spans: Array[Vector2] = []
	for v in tl["voices"]:
		var path: String = IntroTimeline.DIR + String(v["file"])
		var len := (load(path) as AudioStream).get_length()
		var shot := IntroTimeline.shot_by_id(tl["shots"], v["shot"])
		var t0 := float(v["t"])
		check("voice has length " + String(v["id"]), len > 1.0, str(len))
		check("voice inside shot " + String(v["id"]), t0 >= float(shot["start"]) and t0 + len <= float(shot["start"]) + float(shot["dur"]) - 0.4,
			"%.1f+%.1f vs %.1f" % [t0, len, float(shot["start"]) + float(shot["dur"])])
		for sp in spans:
			check("no voice overlap " + String(v["id"]), t0 >= sp.y + 0.3 or t0 + len <= sp.x - 0.3)
		spans.append(Vector2(t0, t0 + len))

	# The first launch plays the intro only when it was never seen; headless runs never do.
	check("headless: intro not due", not Game.intro_due())

	# Player runs to the end, on a phone-shaped (20:9) and a desktop-shaped host.
	for host_size in [Vector2(2400, 1080), Vector2(1280, 720)]:
		var host := Control.new()
		host.size = host_size
		add_child(host)
		var p := _new_player(host)
		var res := {"done": false, "skipped": true}
		p.finished.connect(func(s: bool) -> void:
			res["done"] = true
			res["skipped"] = s)
		await get_tree().process_frame
		var saw_sub := false
		var min_duck := 1.0
		var saw_free := false
		var t := 0.0
		while not res["done"] and t < total + 5.0:
			p.step(0.1)
			t += 0.1
			if p.subtitles.lines.size() > 0:
				saw_sub = true
			min_duck = minf(min_duck, p._duck)
			if t > 5.0 and p._duck > 0.99:
				saw_free = true
			if int(t * 10.0) % 20 == 0:
				await get_tree().process_frame
		var tag := "%dx%d " % [host_size.x, host_size.y]
		check(tag + "player finishes by itself", res["done"] and not res["skipped"], str(res))
		check(tag + "player time ~ total", absf(p.time - total) < 0.5, "%.2f vs %.2f" % [p.time, total])
		check(tag + "subtitles were shown", saw_sub)
		check(tag + "music ducks ~8 dB under narration", absf(linear_to_db(min_duck) - IntroTimeline.DUCK_DB) < 0.6, str(linear_to_db(min_duck)))
		check(tag + "music comes back between lines", saw_free)
		host.queue_free()
		await get_tree().process_frame

	# Skip: hold for 1 s, with a key (override), the mouse button and a finger.
	for kind in ["key", "mouse", "touch"]:
		var host2 := Control.new()
		host2.size = Vector2(1280, 720)
		add_child(host2)
		var p2 := _new_player(host2)
		var res2 := {"done": false, "skipped": false}
		p2.finished.connect(func(s: bool) -> void:
			res2["done"] = true
			res2["skipped"] = s)
		await get_tree().process_frame
		for i in 30:
			p2.step(0.1)
		check(kind + ": no skip without input", not res2["done"] and not p2.skip_held())
		_press(p2, kind, true)
		check(kind + ": press counts as held", p2.skip_held())
		for i in 5:
			p2.step(0.1)
		check(kind + ": half hold: ring ~0.5, not finished", absf(p2.skip_progress - 0.5) < 0.12 and not res2["done"], str(p2.skip_progress))
		_press(p2, kind, false)
		check(kind + ": release is not held", not p2.skip_held())
		for i in 10:
			p2.step(0.1)
		check(kind + ": released: ring drains", p2.skip_progress < 0.1)
		_press(p2, kind, true)
		for i in 24:
			p2.step(0.1)
		check(kind + ": full hold skips", res2["done"] and res2["skipped"], str(res2))
		check(kind + ": skip ended early", p2.time < total - 20.0)
		host2.queue_free()
		await get_tree().process_frame


## Feeds a skip input straight to the player's _input, as the engine would.
func _press(p: IntroPlayer, kind: String, down: bool) -> void:
	match kind:
		"key":
			p.skip_held_override = down
		"mouse":
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.pressed = down
			p._input(e)
		"touch":
			var e := InputEventScreenTouch.new()
			e.index = 0
			e.pressed = down
			p._input(e)
