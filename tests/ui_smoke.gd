extends Node
## Drives the real battle scene with synthetic pointer events (drag a card, attack, end turn) and checks the
## rules state reacts. Run: Godot --headless --path . res://tests/ui_smoke.tscn

var battle: Node2D
var fails := 0


func _ready() -> void:
	Settings.fast_animations = true
	battle = load("res://scenes/battle.tscn").instantiate()
	add_child(battle)
	_run()


func _idle() -> void:
	var t := 0.0
	while t < 30.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		if battle._mull_waiting:
			# Replace the first card through the real input path, then confirm.
			var c: CardView = battle.hand_views[0][0]
			_mouse(c.position, true)
			_mouse(c.position, false)
			if battle._mull_marks.is_empty():
				_fail("tapping a card in the mulligan did not mark it")
			battle._confirm_mulligan()
		if battle.queue.is_empty() and not battle.playing and battle.st.current == 0:
			await get_tree().create_timer(0.2).timeout
			if battle.queue.is_empty() and not battle.playing:
				return
	_fail("timed out waiting for the player's turn")


func _fail(msg: String) -> void:
	fails += 1
	printerr("UI FAIL: " + msg)


func _screen(world: Vector2) -> Vector2:
	return battle.get_canvas_transform() * world


func _mouse(pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = _screen(pos)
	battle._unhandled_input(e)


func _move(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = _screen(pos)
	battle._unhandled_input(e)


func _drag(a: Vector2, b: Vector2) -> void:
	_mouse(a, true)
	for i in 8:
		_move(a.lerp(b, (i + 1) / 8.0))
		await get_tree().process_frame
	_mouse(b, false)


func _run() -> void:
	var played := 0
	for turn in 4:
		await _idle()
		var st: BattleState = battle.st
		# Play every untargeted minion we can afford.
		for c in battle.hand_views[0].duplicate():
			var card := CardDB.card(c.card_id)
			if card.type != "minion" or not st.can_play(0, c.uid):
				continue
			var before: int = st.sides[0].board.size()
			await _drag(c.position, Vector2(battle.V.x / 2, battle._board_y(0)))
			if battle.mode == battle.Mode.AIM_BATTLECRY:
				var t: int = st.valid_targets(0, BattleState.target_type(card))[0]
				var v = battle.unit_views[t]
				_mouse(v.position, true)
				_mouse(v.position, false)
			await _idle()
			if st.sides[0].board.size() <= before and not st.sides[0].board.is_empty():
				_fail("dragging %s did not summon it" % c.card_id)
			else:
				played += 1
		# Attack with everything that can.
		for m in battle.board_views[0].duplicate():
			var u = st.units.get(m.uid)
			if u == null or not st.can_attack(u):
				continue
			var target_uid: int = st.attack_targets(0)[0]
			await _drag(m.position, battle.unit_views[target_uid].position)
			await _idle()
			if u.attacks_made == 0 and not u.dead:
				_fail("attack drag did nothing")
		if st.winner != -1:
			break
		var p: Vector2 = battle.end_btn.position
		_mouse(p, true)
		_mouse(p, false)
		await get_tree().create_timer(0.3).timeout
	print("UI SMOKE: played %d minions, %d failures" % [played, fails])
	get_tree().quit(1 if fails > 0 or played == 0 else 0)
