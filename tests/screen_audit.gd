extends Node
## Screenshots of the screens and overlays the plain `--snap` cannot reach (options, pause, banners, damage numbers,
## the legendary cut-in, the result, the collection zoom, the pack reveal, a filled deck), for the painted-UI audit.
##   Godot --path . res://tests/screen_audit.tscn --resolution 1920x1080 -- --out=<dir> --what=<mode>
## Modes: menu_options, builder, collection_zoom, packs_reveal, packs_empty, deck_tip, battle (several shots).

var out := "user://audit"
var what := "battle"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--what="):
			what = a.substr(7)
	DirAccess.make_dir_recursive_absolute(out)
	Settings.fast_animations = false
	match what:
		"menu_options":
			var s := _open("res://scenes/main_menu.tscn")
			await _wait(1.6)
			s.add_child(OptionsPanel.new())
			await _wait(0.5)
			await _snap("menu_options")
		"builder":
			Game.edit_deck = -1
			Game.new_deck_cls = "pilgrim"
			var s := _open("res://scenes/deck_builder.tscn")
			await _wait(0.6)
			Collection.autofill(s.deck)
			s._refresh()
			s._problem.text = "Your deck can hold at most two copies of a card."
			s._problem_plate.visible = true
			s._name.release_focus()
			await _wait(0.6)
			await _snap("builder")
		"collection_zoom":
			var s := _open("res://scenes/collection.tscn")
			await _wait(0.8)
			s._show_zoom("francesca")
			await _wait(0.6)
			await _snap("collection_zoom")
		"packs_reveal":
			Collection.packs = maxi(Collection.packs, 1)
			var s := _open("res://scenes/pack_opening.tscn")
			await _wait(0.8)
			await s._open()
			for c in s._cards:
				s._reveal(c)
			await _wait(0.5)
			s._banner("MINOS", Color(1.0, 0.6, 0.15))
			await _wait(0.6)
			await _snap("packs_reveal")
		"packs_empty":
			Collection.packs = 0
			Collection.obols = 0
			_open("res://scenes/pack_opening.tscn")
			await _wait(1.2)
			await _snap("packs_empty")
		"deck_tip":
			# A library disc's tooltip (the discs only show when the library overflows, so one is forced on).
			var s := _open("res://scenes/deck_select.tscn")
			await _wait(1.2)
			var b: Button = s._scroll_btns[1]
			b.modulate.a = 1.0
			b.disabled = false
			b.mouse_filter = Control.MOUSE_FILTER_STOP
			b.tooltip_text = "Scroll down"
			var holder: Control = b.get_parent()
			holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var at := b.get_global_transform() * (b.size / 2)
			for k in 3:
				get_viewport().warp_mouse(at)
				var e := InputEventMouseMotion.new()
				e.position = at + Vector2(k, 0)
				e.global_position = e.position
				Input.parse_input_event(e)
				await _wait(0.2)
			await _wait(1.4)
			await _snap("deck_tip")
		_:
			await _battle()
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


func _battle() -> void:
	var b: Node = _open(Game.BATTLE)
	await _wait(0.9)
	await _snap("b_arena_intro")
	while not b._mull_waiting:
		await get_tree().process_frame
	b._confirm_mulligan()
	# The first turn banner, once it has popped in.
	var t := 0.0
	while t < 8.0 and b.banner.modulate.a < 0.95:
		await get_tree().process_frame
		t += get_process_delta_time()
	await _wait(0.2)
	await _snap("b_turn_banner")
	await _wait(2.5)
	var h: Node2D = b.heroes[1]
	Fx.number(b.fx_layer, h.position, "-7", Color(0.75, 0.05, 0.03), true)
	Fx.number(b.fx_layer, b.heroes[0].position, "+4", UI.HEAL, false)
	b._toast(b.heroes[0].position + Vector2(-420, 0), "Not enough mana", Color(1.0, 0.86, 0.7))
	await _wait(0.25)
	await _snap("b_numbers")
	await _wait(1.5)
	b._show_hero_tip(b.heroes[1])
	await _wait(0.3)
	await _snap("b_hero_tip")
	b._hide_inspect()
	b._legendary_cutin("minos")
	await _wait(0.75)
	await _snap("b_cutin")
	await _wait(1.5)
	b._open_pause()
	await _wait(0.4)
	await _snap("b_pause")
	b._pause_dim.add_child(OptionsPanel.new())
	await _wait(0.4)
	await _snap("b_pause_options")
	b._pause_dim.queue_free()
	b._show_result(1)
	await _wait(1.4)
	await _snap("b_defeat")
