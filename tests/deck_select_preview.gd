extends Node
## The deck choice screen with N fake saved decks (some incomplete), to check the "Your decks" strip.
##   Godot --path . res://tests/deck_select_preview.tscn --resolution 1920x1080 -- --decks=6 --out=<file.png>
## `--show=<deck id>,<deck id>` puts those preconstructed decks on the class panels (as if the player had picked them);
## `--cycle` clicks each panel's next-deck arrow before the shot and prints CYCLE lines.

func _ready() -> void:
	var n := 6
	var out := "user://deck_select_preview.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--decks="):
			n = int(a.substr(8))
		elif a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--show="):
			for id in a.substr(7).split(","):
				Settings.deck_choice[CardDB.deck_class(CardDB.deck(id))] = id
	var full: Dictionary = CardDB.deck("pilgrim").get("cards", {})
	Collection.decks.clear()
	for i in n:
		var cls := "pilgrim" if i % 2 == 0 else "ferry"
		var cards: Dictionary = full.duplicate() if i % 3 != 2 else {}
		if cls == "ferry":
			cards = CardDB.deck("ferry").get("cards", {}).duplicate() if i % 3 != 2 else {}
		Collection.decks.append({"name": ["Lions of Violence", "Charon's Toll", "Draft", "The Long Way Down",
			"Venom", "Guards of Limbo", "Test", "Aggro Souls"][i % 8], "cls": cls, "cards": cards})
	var scene: Node = load("res://scenes/deck_select.tscn").instantiate()
	add_child(scene)
	await get_tree().create_timer(1.5).timeout
	if "--cycle" in OS.get_cmdline_user_args():
		await _cycle(scene)
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()


## `--cycle`: clicks every panel's "next deck" arrow through the real input path and checks the panel moved to the
## next deck of its class without starting a battle.
func _cycle(scene: Node) -> void:
	for b in scene.find_children("*", "Button", true, false):
		if b.text != ">":
			continue
		var panel: Control = b.get_parent()
		while not panel.has_meta("deck"):
			panel = panel.get_parent()
		var before := str(panel.get_meta("deck"))
		for pressed in [true, false]:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.pressed = pressed
			e.position = b.get_global_rect().get_center()
			e.global_position = e.position
			Input.parse_input_event(e)
			await get_tree().process_frame
		var list := CardDB.class_decks(CardDB.deck_class(CardDB.deck(before)))
		var want := str(list[wrapi(list.find(CardDB.deck(before)) + 1, 0, list.size())].id)
		var now := str(panel.get_meta("deck"))
		print("CYCLE: %s -> %s (%s)" % [before, now, "ok" if now == want else "FAIL, expected " + want])
	await get_tree().create_timer(0.6).timeout
	print("CYCLE: still on Choose your path: %s" % (get_tree().current_scene == self))
