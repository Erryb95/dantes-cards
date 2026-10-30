extends Node
## Times the heavy screens: how long a screen takes to open, to switch a filter, and what an idle frame costs.
##   Godot --path . res://tests/perf_probe.tscn --resolution 1920x1080 -- --what=collection|menu|decks|builder|battle
## Prints "PERF <what> <step> <ms>" lines; the frame times are the mean over 120 frames (vsync off).

var what := "collection"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--what="):
			what = a.substr(7)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	Game.intro_played = true
	for c in CardDB.all_cards(): # every card owned in memory (the save is not touched), so the grids are full
		Collection.owned[c.id] = maxi(int(Collection.owned.get(c.id, 0)), 2)
	await get_tree().process_frame
	if "--menu-first" in OS.get_cmdline_user_args() and what != "menu":
		# As in the game: the menu (its card shaders compiled, its fonts loaded) comes first.
		var m := await _open("menu", Game.MENU)
		await get_tree().create_timer(2.0).timeout
		m.queue_free()
		await get_tree().process_frame
	match what:
		"collection":
			await _collection()
		"menu":
			var m := await _open("menu", Game.MENU)
			await _idle("menu idle")
			m.queue_free()
			await get_tree().process_frame
			await _open("menu again", Game.MENU) # back from another screen: everything loaded once
		"decks":
			await _open("decks", Game.DECK_SELECT)
			await _idle("decks idle")
		"battle":
			Settings.fast_animations = false
			var b := await _open("battle", Game.BATTLE)
			await get_tree().create_timer(3.0).timeout
			await _idle("battle idle")
			var worst := 0.0
			var t := Time.get_ticks_usec()
			for i in 600: # ten seconds of the opening (mulligan, deals): the worst frame
				var f := Time.get_ticks_usec()
				await get_tree().process_frame
				worst = maxf(worst, (Time.get_ticks_usec() - f) / 1000.0)
			print("PERF battle worst frame %.1f over %.1f s" % [worst, (Time.get_ticks_usec() - t) / 1e6])
		"cards":
			await _cards()
		"cold":
			await _cold()
		"fitcheck": # the shipped text fits against a measurement in a window (the file is made headless)
			print("PERF fitcheck stale ", preload("res://tests/gen_card_fits.gd").stale().size())
		"builder":
			var b := await _open("builder", Game.DECK_BUILDER)
			await _idle("builder idle")
			for f in [["class", -1], ["neutral", -1], ["all", 3], ["all", -1]]:
				var t := Time.get_ticks_usec()
				b._set_filter = f[0]
				b._cost_filter = f[1]
				b._fill()
				await get_tree().process_frame
				_report("builder filter %s %d" % f, t)
	get_tree().quit()


func _open(label: String, path: String) -> Node:
	var t := Time.get_ticks_usec()
	var s: Node = load(path).instantiate()
	add_child(s)
	_report(label + " build", t)
	await get_tree().process_frame
	await get_tree().process_frame
	_report(label + " first frames", t)
	return s


func _collection() -> void:
	var t_open := Time.get_ticks_usec()
	var s := await _open("collection", Game.COLLECTION)
	await _idle("collection idle")
	while not s._faces.is_done():
		await get_tree().process_frame
	_report("collection all faces built", t_open)
	s._set_filter("all")
	await get_tree().process_frame
	var filters: Array = ["all"] + CardDB.classes() + ["neutral", "token", "all"]
	for f in filters:
		var t := Time.get_ticks_usec()
		s._set_filter(f)
		await get_tree().process_frame
		_report("filter " + str(f), t)
	for i in 5:
		var t := Time.get_ticks_usec()
		s._cycle_sort()
		await get_tree().process_frame
		_report("sort " + s._sort, t)
	await _idle("collection idle after")
	var sc: ScrollContainer = s._scroll
	var t0 := Time.get_ticks_usec()
	for i in 120:
		sc.scroll_vertical += 12
		await get_tree().process_frame
	print("PERF %s %s %.2f" % [what, "scroll frame", (Time.get_ticks_usec() - t0) / 120000.0])


func _idle(label: String) -> void:
	for i in 10:
		await get_tree().process_frame
	var t := Time.get_ticks_usec()
	for i in 120:
		await get_tree().process_frame
	print("PERF %s %s %.2f" % [what, label + " frame", (Time.get_ticks_usec() - t) / 120000.0])


func _report(label: String, t: int) -> void:
	print("PERF %s %s %.1f" % [what, label, (Time.get_ticks_usec() - t) / 1000.0])


## What a card face costs to build, piece by piece (warm: the second pass, every cache filled).
func _cards() -> void:
	var ids: Array = CardDB.all_cards().map(func(c): return c.id)
	for pass_i in 2:
		var t := Time.get_ticks_usec()
		var keep := []
		for id in ids:
			var v := CardView.new().setup(id, -1, true)
			keep.append(v)
		_report("pass %d setup %d cards" % [pass_i, ids.size()], t)
		t = Time.get_ticks_usec()
		var holder := Control.new()
		add_child(holder)
		for v in keep:
			holder.add_child(v)
		_report("pass %d add_child" % pass_i, t)
		t = Time.get_ticks_usec()
		await get_tree().process_frame
		_report("pass %d first frame" % pass_i, t)
		await _idle("pass %d idle" % pass_i)
		t = Time.get_ticks_usec()
		holder.queue_free()
		await get_tree().process_frame
		_report("pass %d free" % pass_i, t)
	var probes := {
		"art_framed": func(id): CardDB.art_framed(id, 0.7, 0.42),
		"depth": func(id): ArtDepth.setup_card(ShaderMaterial.new(), id, 0.7, 0.42, ArtDepth.CARD),
		"living": func(id): ArtLiving.setup_card(ShaderMaterial.new(), id, 0.7, 0.42),
		"loop": func(id):
			var f := Control.new()
			var a := TextureRect.new()
			f.add_child(a)
			ArtLoop.attach(f, f, a, ShaderMaterial.new(), id, 0.7, 0.42)
			f.free(),
		"art": func(id): CardDB.art(id),
		"has_art": func(id): CardDB.has_art(id),
		"crop_uv": func(id): CardDB.art_crop_uv(id, 0.7, 0.42),
		"art_depth": func(id): CardDB.art_depth(id),
		"living_has": func(id): ArtLiving.has(id),
		"bbcode": func(id): UI.rules_bbcode(str(CardDB.card(id).get("text", ""))),
		"skin_rect": func(id): UiSkin.rect("gem_mana", Vector2(74, 74)).free(),
		"stat_number": func(id): UI.stat_number("3", 36, Vector2.ZERO, Vector2(80, 64)).free(),
		"aura": func(id): Aura.make(Vector2(300, 420), false, 46.0, 20.0).free(),
	}
	for k in probes:
		var t := Time.get_ticks_usec()
		for id in ids:
			probes[k].call(id)
		_report("piece %s x%d" % [k, ids.size()], t)


## The cold cost of each piece of a card face (a fresh process: nothing cached yet), then a whole face once warm.
func _cold() -> void:
	var ids: Array = CardDB.all_cards().map(func(c): return c.id).slice(0, 60)
	var steps := [
		["art_size", func(id): CardDB.art_size(id)],
		["art_framed", func(id): CardDB.art_framed(id, 290.0 / 410.0, 0.42)],
		["depth", func(id): ArtDepth.setup_card(ShaderMaterial.new(), id, 0.7, 0.42, ArtDepth.CARD)],
		["living", func(id): ArtLiving.setup_card(ShaderMaterial.new(), id, 0.7, 0.42)],
		["face cold rest", func(id): CardView.new().setup(id, -1, true).free()],
		["face warm", func(id): CardView.new().setup(id, -1, true).free()],
	]
	for st in steps:
		var t := Time.get_ticks_usec()
		for id in ids:
			st[1].call(id)
		print("PERF cold %s per card %.2f ms" % [st[0], (Time.get_ticks_usec() - t) / 1000.0 / ids.size()])
