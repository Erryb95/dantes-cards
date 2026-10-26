extends Node
## The deck choice screen with N fake saved decks (some incomplete), to check the "Your decks" strip.
##   Godot --path . res://tests/deck_select_preview.tscn --resolution 1920x1080 -- --decks=6 --out=<file.png>

func _ready() -> void:
	var n := 6
	var out := "user://deck_select_preview.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--decks="):
			n = int(a.substr(8))
		elif a.begins_with("--out="):
			out = a.substr(6)
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
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
