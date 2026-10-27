extends "res://tests/ui_smoke.gd"
## Screenshots of the battle's crowded and edge states for the painted-UI audit: a full hand (and the card burned
## from it), the hover tips of the outermost hand cards, a full board on both sides, the inspect card of the outermost
## minions, a minion with many keyword tips, the player's hero tip, fatigue, and the pause menu during the enemy turn.
##   Godot --path . res://tests/state_shots.tscn --resolution 1920x1080 -- --out=<dir>

var out := "user://state_shots"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	battle = load("res://scenes/battle.tscn").instantiate()
	add_child(battle)
	_shoot()


func _snap(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])


func _settle(extra: float = 0.3) -> void:
	var t := 0.0
	while (battle.playing or not battle.queue.is_empty()) and t < 20.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	await get_tree().create_timer(extra).timeout


func _shoot() -> void:
	await _idle()
	var st: BattleState = battle.st
	# A full hand: draw up to the limit, then one more, which burns.
	st.draw(0, BattleState.MAX_HAND - st.sides[0].hand.size())
	await _settle()
	st.draw(0, 1)
	await get_tree().create_timer(0.75).timeout
	await _snap("hand_burn")
	await _settle()
	await _snap("hand_full")
	for which in [0, -1]:
		var c: CardView = battle.hand_views[0][which]
		_move(c.position + Vector2(0, -CardView.H * 0.6) * c.scale.x * 0.4)
		await get_tree().create_timer(0.6).timeout
		await _snap("hand_hover_%s" % ("left" if which == 0 else "right"))
	_move(Vector2(battle.V.x / 2, battle.V.y * 0.4))
	# A full board on both sides, with keyword-heavy minions at the ends.
	var mine := ["mc_lucifer", "ul_potiphars_wife", "pj_ovid", "francesca", "geryon", "paolo", "cd_frederick_ii"]
	var theirs := ["cd_nicholas_iii", "plutus", "limbo_philosophers", "phlegyas", "minos", "ih_typhon", "mc_ruggieri"]
	for i in BattleState.MAX_BOARD:
		st._summon(0, mine[i])
		st._summon(1, theirs[i])
	await _settle(0.6)
	var frozen: BattleState.Unit = st.units[battle.board_views[0][-1].uid]
	frozen.frozen = true
	st._emit_status(frozen)
	await _settle(0.4)
	await _snap("board_full")
	for pick in [[1, 0, "enemy_left"], [1, -1, "enemy_right"], [0, 0, "mine_left"], [0, -1, "mine_right"]]:
		var m: Node2D = battle.board_views[pick[0]][pick[1]]
		_move(m.position)
		await get_tree().create_timer(0.9).timeout
		await _snap("inspect_" + pick[2])
		_move(Vector2(150, battle.V.y * 0.55)) # an empty spot, off every minion
		await get_tree().create_timer(0.2).timeout
	battle._show_hero_tip(battle.heroes[0])
	await get_tree().create_timer(0.3).timeout
	await _snap("hero_tip_mine")
	battle._hide_inspect()
	# Fatigue: the deck runs dry.
	st.sides[0].deck.clear()
	battle._set_deck_count(0, 0)
	st.draw(0, 1)
	await get_tree().create_timer(0.3).timeout
	await _snap("fatigue")
	await _settle()
	# Pause during the enemy turn: nothing may move underneath it.
	if not battle._my_turn():
		printerr("STATE SHOTS: not the player's turn before End Turn (current=%d queue=%d playing=%s)" % [st.current,
			battle.queue.size(), battle.playing])
	battle._end_turn()
	var waited := 0.0
	while battle._end_label.text != "ENEMY TURN" and waited < 10.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	await get_tree().create_timer(0.8).timeout
	battle._open_pause()
	var hp := [st.sides[0].hero.health, st.sides[1].hand.size(), st.turn]
	await get_tree().create_timer(4.0).timeout
	await _snap("pause_enemy_turn")
	if [st.sides[0].hero.health, st.sides[1].hand.size(), st.turn] != hp:
		printerr("STATE SHOTS: the enemy kept playing under the pause menu")
	battle._ask_concede(battle._pause_dim, battle._pause_dim.get_child(0))
	await get_tree().create_timer(0.4).timeout
	await _snap("concede")
	get_tree().quit()
