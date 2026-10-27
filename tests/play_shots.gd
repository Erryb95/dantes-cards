extends "res://tests/ui_smoke.gd"
## Plays the real battle through the input path like a person would, and saves a screenshot at each key moment
## (mulligan, hover, drag, aim, inspect, end turn, result) for a visual review.
##   Godot --path . res://tests/play_shots.tscn -- --out=<dir> [--class=<cls>]
## --class plays that class's first preconstructed deck (with a Ruse class, it also films a gold Ruse glow in hand and
## the inspect tips of a Ruse minion).

var out := "user://play_shots"
var _n := 0
var _ruse_shot := false
var _ruse_tip := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--class="):
			var cls := a.substr(8)
			Game.player_cards = CardDB.deck_list(CardDB.class_decks(cls)[0].id)
			Game.player_hero = CardDB.class_hero(cls)
	DirAccess.make_dir_recursive_absolute(out)
	battle = load("res://scenes/battle.tscn").instantiate()
	add_child(battle)
	_play()


func _snap(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_n += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [out, _n, name])


func _play() -> void:
	# Mulligan: mark one card, look, confirm.
	while not battle._mull_waiting:
		await get_tree().process_frame
	await get_tree().create_timer(0.8).timeout
	var c0: CardView = battle.hand_views[0][0]
	_mouse(c0.position, true)
	_mouse(c0.position, false)
	await get_tree().create_timer(0.4).timeout
	await _snap("mulligan")
	battle._confirm_mulligan()
	for turn in 6:
		await _idle()
		var st: BattleState = battle.st
		if turn == 0:
			await _snap("turn_start")
		# Hover the first card in hand.
		if not battle.hand_views[0].is_empty():
			var h: CardView = battle.hand_views[0][0]
			var grab: Vector2 = h.position + Vector2(-CardView.W, -CardView.H * 0.6) * h.scale.x * 0.4
			_move(grab)
			await get_tree().create_timer(0.5).timeout
			if turn == 1:
				await _snap("hover_card")
		for c in battle.hand_views[0].duplicate():
			var card := CardDB.card(c.card_id)
			if card.type != "minion" or not st.can_play(0, c.uid):
				continue
			var grab: Vector2 = c.position + Vector2(-CardView.W, -CardView.H * 0.6) * c.scale.x * 0.4
			if battle._pick_hand(grab) != c:
				continue
			var dest := Vector2(battle.V.x / 2, battle._board_y(0))
			_mouse(grab, true)
			for i in 10:
				_move(grab.lerp(dest, (i + 1) / 10.0))
				await get_tree().process_frame
			if turn == 2:
				await _snap("drag_card")
			_mouse(dest, false)
			if battle.mode == battle.Mode.AIM_BATTLECRY:
				var t: int = st.valid_targets(0, BattleState.target_type(card))[0]
				var v = battle.unit_views[t]
				_mouse(v.position, true)
				_mouse(v.position, false)
			await get_tree().create_timer(0.35).timeout
			if turn == 2:
				await _snap("summon")
			await _idle()
			if not _ruse_shot and battle.hand_views[0].any(func(h): return h.ruse and h.playable):
				_ruse_shot = true
				await get_tree().create_timer(0.4).timeout
				await _snap("ruse_glow")
		for m in battle.board_views[0].duplicate():
			var u = st.units.get(m.uid)
			if u == null or not st.can_attack(u):
				continue
			var target_uid: int = st.attack_targets(0)[0]
			var tp: Vector2 = battle.unit_views[target_uid].position
			_mouse(m.position, true)
			for i in 8:
				_move(m.position.lerp(tp, (i + 1) / 8.0))
				await get_tree().process_frame
			if turn >= 2 and not FileAccess.file_exists("%s/aim.flag" % out):
				FileAccess.open("%s/aim.flag" % out, FileAccess.WRITE)
				await _snap("aim")
			_mouse(tp, false)
			await get_tree().create_timer(0.25).timeout
			await _idle()
		# Inspect one of your Ruse minions (its tip explains the Ruse instead of "On Play").
		for m in battle.board_views[0]:
			if not _ruse_tip and battle._has_ruse(m.card_id):
				_ruse_tip = true
				_move(m.position)
				await get_tree().create_timer(0.9).timeout
				await _snap("inspect_ruse")
				_move(Vector2(10, 10))
				await get_tree().create_timer(0.2).timeout
		# Inspect an enemy minion by hovering it.
		if turn == 3 and not battle.board_views[1].is_empty():
			_move(battle.board_views[1][0].position)
			await get_tree().create_timer(0.9).timeout
			await _snap("inspect")
			_move(Vector2(10, 10))
		if st.winner != -1:
			break
		if turn == 4:
			await _snap("board_late")
		var p: Vector2 = battle.end_btn.position
		_mouse(p, true)
		_mouse(p, false)
		await get_tree().create_timer(0.3).timeout
	battle._show_result(0)
	await get_tree().create_timer(1.5).timeout
	await _snap("result")
	get_tree().quit()
