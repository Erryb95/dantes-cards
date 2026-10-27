extends Node
## Soak test of the real battle scene: AI vs AI with every animation and effect, game after game, watching for
## stalls. Script errors show up in the log.   Godot --headless --path . res://tests/view_soak.tscn -- --games=10
## Game g puts class g % classes on the player's side against the next class, cycling through each class's
## preconstructed decks; --class=<cls> keeps that class on the player's side.

var games := 10
var only := ""
var done := 0
var stalls := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--games="):
			games = int(a.substr(8))
		if a.begins_with("--class="):
			only = a.substr(8)
	Settings.fast_animations = true
	Engine.time_scale = 4.0
	_loop()


func _loop() -> void:
	for g in games:
		var cls := CardDB.classes()
		var mine: String = only if only != "" else cls[g % cls.size()]
		var others := CardDB.other_classes(mine)
		var theirs: String = others[g % others.size()]
		var my_decks := CardDB.class_decks(mine)
		var their_decks := CardDB.class_decks(theirs)
		Game.player_cards = CardDB.deck_list(my_decks[(g / cls.size()) % my_decks.size()].id)
		Game.player_hero = CardDB.class_hero(mine)
		Game.enemy_cards = CardDB.deck_list(their_decks[g % their_decks.size()].id)
		Game.enemy_hero = CardDB.class_hero(theirs)
		var battle: Node = load(Game.BATTLE).instantiate()
		battle.autoplay = true
		add_child(battle)
		var last_sig := ""
		var still := 0.0
		while not battle.over:
			await get_tree().create_timer(1.0).timeout
			# Mulligan: autoplay keeps the opening hand.
			if battle.get("_mull_waiting"):
				battle._confirm_mulligan()
			var sig := "%d|%d|%d|%d" % [battle.st.turn if "turn" in battle.st else 0, battle.queue.size(),
				battle.st.sides[0].hero.health, battle.st.sides[1].hero.health]
			sig += "|%d|%d" % [battle.st.sides[0].hand.size(), battle.st.sides[1].hand.size()]
			still = still + 1.0 if sig == last_sig else 0.0
			last_sig = sig
			if still > 40.0:
				stalls += 1
				printerr("SOAK STALL game %d: playing=%s queue=%d current=%d sig=%s" % [g, battle.playing,
					battle.queue.size(), battle.st.current, sig])
				break
		done += 1
		print("SOAK game %d over: winner %d" % [g, battle.st.winner])
		battle.queue_free()
		await get_tree().process_frame
	Engine.time_scale = 1.0
	print("VIEW SOAK: %d games, %d stalls" % [done, stalls])
	get_tree().quit()
