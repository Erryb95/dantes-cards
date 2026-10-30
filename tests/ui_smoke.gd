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


## The shipped text fits (data/card_text_fit.json) match a fresh measurement of every card text in every language.
func _card_fits() -> void:
	var stale: Array = preload("res://tests/gen_card_fits.gd").stale()
	if not stale.is_empty():
		_fail("data/card_text_fit.json is out of date for %d texts (run tests/gen_card_fits.tscn), e.g. %s"
			% [stale.size(), stale[0]])


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


## Every killer school's death through the battle view's queue (DeathFx): one enemy minion staged and killed per
## school, then a clear of four at once; each view must be gone afterwards and nothing may error.
func _deaths() -> void:
	var uid := 9800
	var shown := 0
	for school in VfxData.SCHOOLS:
		var how := "venom" if school == "venom" else "effect"
		var killer := ""
		for c in CardDB.all_cards():
			if DeathStyle.killer_school(c.id, how) == school:
				killer = c.id
				break
		if killer == "":
			_fail("no card kills with %s" % school)
			continue
		var batch: Array = []
		for k in (4 if school == "fire" else 1):
			uid += 1
			var snap := {"uid": uid, "id": "lost_pilgrim", "side": 1, "is_hero": false, "attack": 1, "health": 1,
				"max_health": 1, "armor": 0, "keywords": [], "sleeping": false, "frozen": false, "silenced": false}
			var m := MinionView.new().setup(snap)
			battle.board_layer.add_child(m)
			battle.board_views[1].append(m)
			battle.unit_views[uid] = m
			batch.append(m)
		battle._layout_board(1)
		for m in batch:
			battle.queue.append({"t": "damage", "uid": m.uid, "amount": 1, "hp": 0, "armor": 0, "source": -1,
				"src": killer})
		for m in batch:
			battle.queue.append({"t": "death", "uid": m.uid, "side": 1, "killer": killer, "how": how, "by": -1})
		var t := 0.0
		while (not battle.queue.is_empty() or battle.playing) and t < 10.0:
			await get_tree().process_frame
			t += get_process_delta_time()
		await get_tree().create_timer(1.2).timeout
		for m in batch:
			if is_instance_valid(m):
				_fail("the %s death left its minion behind" % school)
			else:
				shown += 1
	print("UI SMOKE: %d deaths played in %d killer schools" % [shown, VfxData.SCHOOLS.size()])


## Opens the battle in every arena (one without its painted board on the Acheron stand-in) and taps each of its
## toys and its divider, so every arena's VFX and reactions run at least once.
func _arenas() -> void:
	for a in CardDB.arenas():
		battle.queue_free()
		Game.force_arena = a.id
		battle = load("res://scenes/battle.tscn").instantiate()
		add_child(battle)
		await get_tree().process_frame
		if battle.arena.get("id", "") != a.id:
			_fail("arena %s did not open" % a.id)
			continue
		var pts: Array[Vector2] = battle.props.toy_points()
		for p in pts:
			battle._board_touch(p)
		for i in 30:
			await get_tree().process_frame
		print("UI SMOKE: arena %s ok (%d touch points%s)" % [a.id, pts.size(),
			", stand-in board" if battle._arena_standin else ""])
	Game.force_arena = ""


## The characters' own sounds in the battle: both heroes announced themselves, the minions played above spoke,
## a batch of tokens speaks once, a death cries, and a character without a file falls back (no error).
func _voices() -> void:
	var heard: Array[String] = Sfx.char_log
	if not heard.any(func(n): return n.begins_with("hero_")):
		_fail("no hero start sound was played (%s)" % [heard])
	if not heard.any(func(n): return n.ends_with("_play")):
		_fail("no minion play sound was played (%s)" % [heard])
	print("UI SMOKE: character sounds in the battle: %s" % ", ".join(heard.slice(0, 12)))
	Sfx.char_log.clear()
	battle._summon_voice_ms = -100000
	battle._summon_voice("lost_soul", false)
	battle._summon_voice("lost_soul", false) # same batch: silent
	battle._summon_voice("harpy", false) # still the same batch
	if Sfx.char_log.size() != 1:
		_fail("a batch of summoned tokens played %d sounds" % Sfx.char_log.size())
	battle._death_voice_ms.clear()
	if not battle._death_voice("cerberus") or Sfx.char_log[-1] != "cerberus_death":
		_fail("Cerberus' death cry did not play")
	if battle._summon_voice("no_such_card", true) or battle._death_voice("no_such_card"):
		_fail("a character without a sound file must fall back to the generic sounds")
	for id in ["dante", "charon", "ulysses", "filippo"]:
		battle._hero_voice(id, true)
	print("UI SMOKE: character sounds ok (%d played)" % Sfx.char_log.size())


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
			# Grab the card by its visible left edge: in the fan the right half is under the next card.
			var grab: Vector2 = c.position + Vector2(-CardView.W, -CardView.H * 0.6) * c.scale.x * 0.4
			if battle._pick_hand(grab) != c:
				_fail("cannot grab %s by its visible corner" % c.card_id)
				continue
			await _drag(grab, Vector2(battle.V.x / 2, battle._board_y(0)))
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
	if battle.st.winner == -1:
		await _idle()
	await _deaths()
	_voices()
	await _arenas()
	_card_fits()
	print("UI SMOKE: played %d minions, %d failures" % [played, fails])
	get_tree().quit(1 if fails > 0 or played == 0 else 0)
