extends Node
## The deck choice screen with N fake saved decks (some incomplete), to check the deck library.
##   Godot --path . res://tests/deck_select_preview.tscn --resolution 1920x1080 -- --decks=6 --out=<file.png>
## `--show=<deck id>` shows that preconstructed deck (as if the player had picked it); `--filter=<all|pilgrim|ferry>`
## sets the library filter; `--pick` clicks the third deck tile before the shot and prints PICK lines.

func _ready() -> void:
	var n := 6
	var out := "user://deck_select_preview.png"
	Settings.deck_choice = {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--decks="):
			n = int(a.substr(8))
		elif a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--show="):
			Settings.deck_choice["selected"] = "pre:" + a.substr(7)
		elif a.begins_with("--filter="):
			Settings.deck_choice["filter"] = a.substr(9)
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
	if "--pick" in OS.get_cmdline_user_args():
		await _pick(scene)
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()


## `--pick`: clicks the third deck tile through the real input path and checks the showcase moved to it without
## starting a battle.
func _pick(scene: Node) -> void:
	var tiles := scene.find_children("*", "Button", true, false).filter(func(b): return b.has_meta("key"))
	var b: Button = tiles[2]
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = b.get_global_rect().get_center()
		e.global_position = e.position
		Input.parse_input_event(e)
		await get_tree().process_frame
	var want := str(b.get_meta("key"))
	print("PICK: %s (%s)" % [scene._selected, "ok" if scene._selected == want else "FAIL, expected " + want])
	await get_tree().create_timer(0.6).timeout
	print("PICK: still on Choose your path: %s" % (scene.is_inside_tree()))
