extends Node
## Soak test of the real battle scene: AI vs AI with every animation and effect, game after game, watching for
## stalls. Script errors show up in the log.   Godot --headless --path . res://tests/view_soak.tscn -- --games=10

var games := 10
var done := 0
var stalls := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--games="):
			games = int(a.substr(8))
	Settings.fast_animations = true
	Engine.time_scale = 4.0
	_loop()


func _loop() -> void:
	for g in games:
		Game.player_cards = CardDB.deck_list("pilgrim" if g % 2 == 0 else "ferry")
		Game.player_hero = "dante" if g % 2 == 0 else "charon"
		Game.enemy_cards = CardDB.deck_list("ferry" if g % 2 == 0 else "pilgrim")
		Game.enemy_hero = "charon" if g % 2 == 0 else "dante"
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
