extends Node
## Pacing probe: AI vs AI on the real battle scene at normal animation speed, measuring how long the board stays busy
## (input blocked) after each action and how long the enemy's turns take, in game seconds (as seen at 1x speed).
##   Godot --headless --path . res://tests/pace_probe.tscn -- --games=3 [--class=<cls>] [--scale=4]
## Prints the slowest busy spans with the actions behind them, the per-action average, and the enemy turn lengths.

var games := 3
var only := ""
var scale := 4.0
var spans: Array[Dictionary] = [] ## {t, side, what}
var enemy_turns: Array[float] = []
var _pending: Array[String] = [] ## actions applied since the last busy span started
var _events: Array[String] = [] ## every event type behind them (shown for the slow spans)
var _busy_events := ""
var _busy := 0.0
var _busy_what := ""
var _busy_side := 0
var _enemy_t := -1.0
var _last_banner := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--games="):
			games = int(a.substr(8))
		elif a.begins_with("--class="):
			only = a.substr(8)
		elif a.begins_with("--scale="):
			scale = float(a.substr(8))
	Settings.fast_animations = false
	Engine.time_scale = scale
	_loop()


func _loop() -> void:
	for g in games:
		var cls := CardDB.classes()
		var mine: String = only if only != "" else cls[g % cls.size()]
		var others := CardDB.other_classes(mine)
		var theirs: String = others[g % others.size()]
		Game.player_cards = CardDB.deck_list(CardDB.class_decks(mine)[0].id)
		Game.player_hero = CardDB.class_hero(mine)
		Game.enemy_cards = CardDB.deck_list(CardDB.class_decks(theirs)[0].id)
		Game.enemy_hero = CardDB.class_hero(theirs)
		var battle: Node = load(Game.BATTLE).instantiate()
		battle.autoplay = true
		add_child(battle)
		battle.st.event.connect(_on_event.bind(battle))
		var start := 0.0
		while not battle.over:
			await get_tree().process_frame
			# The process delta is already scaled: summed, it gives game seconds as a player sees them at 1x speed
			# (only the AI's search, on a worker thread, runs in real time and so looks `scale` times shorter).
			var d := get_process_delta_time()
			start += d
			if battle.get("_mull_waiting"):
				battle._confirm_mulligan()
			_watch(battle, d)
			if start > 1500.0:
				printerr("PACE game %d did not end" % g)
				break
		if _busy > 0.0: # the last span runs into the result screen: close it here, not in the next game
			spans.append({"t": _busy, "side": _busy_side, "what": _busy_what + " (game over)", "events": _busy_events})
			_busy = 0.0
		_events.clear()
		_pending.clear()
		print("PACE game %d (%s vs %s): %.0f s, winner %d" % [g, mine, theirs, start, battle.st.winner])
		battle.queue_free()
		await get_tree().process_frame
	_report()
	Engine.time_scale = 1.0
	get_tree().quit()


func _on_event(ev: Dictionary, battle: Node) -> void:
	_events.append(str(ev.t) + (" " + str(ev.id) if ev.has("id") and ev.t != "play" else ""))
	match ev.t:
		"play":
			_pending.append("%s:play %s" % ["me" if ev.side == 0 else "ai", ev.id])
		"power":
			_pending.append("%s:power" % ("me" if ev.side == 0 else "ai"))
		"attack":
			var a = battle.st.units.get(ev.attacker)
			_pending.append("%s:attack" % ("me" if a != null and a.side == 0 else "ai"))
		"turn":
			_pending.append("turn %d" % ev.side)


func _watch(battle: Node, d: float) -> void:
	var busy: bool = battle.playing or not battle.queue.is_empty()
	if busy:
		if _busy == 0.0:
			_busy_what = ", ".join(_pending)
			_busy_side = battle.st.current
			_pending.clear()
			_busy_events = ", ".join(_events)
			_events.clear()
		_busy += d
	elif _busy > 0.0:
		spans.append({"t": _busy, "side": _busy_side, "what": _busy_what, "events": _busy_events})
		_busy = 0.0
	# Enemy turn: from the "ENEMY TURN" banner until "YOUR TURN" (what a player waits through).
	var b: String = battle.banner.text if battle.banner != null else ""
	if b != _last_banner and battle.banner.modulate.a > 0.5:
		_last_banner = b
		if b == "ENEMY TURN":
			_enemy_t = 0.0
		elif b == "YOUR TURN" and _enemy_t >= 0.0:
			enemy_turns.append(_enemy_t)
			_enemy_t = -1.0
	if _enemy_t >= 0.0:
		_enemy_t += d


func _report() -> void:
	var mine := spans.filter(func(s): return s.what.begins_with("me:") and not s.what.ends_with("(game over)"))
	var total := 0.0
	for s in mine:
		total += s.t
	print("PACE: %d busy spans after your own actions, average %.2f s" % [mine.size(), total / maxf(1.0, mine.size())])
	mine.sort_custom(func(a, b): return a.t > b.t)
	for s in mine.slice(0, 12):
		print("  %.2f s  %s" % [s.t, s.what])
		if s.t > 4.0:
			print("      events: %s" % s.events)
	var et := 0.0
	var emax := 0.0
	for t in enemy_turns:
		et += t
		emax = maxf(emax, t)
	print("PACE: %d enemy turns, average %.1f s, longest %.1f s" % [enemy_turns.size(), et / maxf(1.0, enemy_turns.size()),
		emax])
