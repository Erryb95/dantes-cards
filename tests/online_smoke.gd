extends Node
## Two online clients in one process against the REAL server (not part of run_tests: it needs the network).
## They sign in with their own device accounts, matchmake, join with their decks, mulligan, play a few turns with
## Easy-AI moves through the server's ordered stream, chat, drop and rejoin one client (RESYNC), and one concedes;
## both must see the same game at every step (checksums) and the same END.
##
##   Godot --headless --path . res://tests/online_smoke.tscn -- --online-config=<path to online.local.cfg> [--turns=6]
##
## Exit code 0 when everything held, 1 otherwise. The server key is never printed.

const TIMEOUT := 120.0

var clients: Array[OnlineSession] = []
var syncs: Array[DuelSync] = [null, null]
var ends: Array = [{}, {}]
var errors: Array = [[], []]
var waiting := [false, false] ## an action / end turn was sent and its echo is not back yet
var chats: Array = [[], []]
var fails := 0
var turns_wanted := 6
var log_resync := true


var bot_idle_turn := -1 ## `--bot`: on this turn number of its own, the bot does nothing (the rope burns, it times out)


func _ready() -> void:
	var bot := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--turns="):
			turns_wanted = int(a.substr(8))
		elif a == "--bot":
			bot = true
		elif a.begins_with("--idle-turn="):
			bot_idle_turn = int(a.substr(12))
	if bot:
		_run_bot()
	else:
		_run()


## `--bot`: one client only, an opponent for a real game window on this PC (`-- --online-profile=N`). It queues,
## plays Easy-AI moves to the end of the duel (sitting out turn `--idle-turn`, so the rope shows), then quits.
func _run_bot() -> void:
	var s := OnlineSession.new(903)
	s.name = "Bot"
	add_child(s)
	clients.append(s)
	clients.append(s)
	s.failed.connect(func(m): _fail("bot: %s" % m))
	var cls: String = CardDB.classes()[1 % CardDB.classes().size()]
	s.search(cls, CardDB.deck_list(str(CardDB.class_decks(cls)[0].id)))
	if not await _wait_until(func(): return s.in_match() and not s.start.is_empty(), 90.0, "the bot is matched"):
		_finish()
		return
	syncs[0] = DuelSync.new()
	syncs[0].setup(s.start, s.user_id())
	syncs[0].build()
	print("bot matched against ", syncs[0].opponent_name())
	await s.open_chat()
	await get_tree().create_timer(4.0).timeout
	s.send(DuelSync.OP_MULLIGAN, {"replace": []})
	await get_tree().create_timer(5.0).timeout # the other side's battle has joined the chat by now
	await s.send_chat({"emote": "greetings"})
	await get_tree().create_timer(1.5).timeout
	await s.send_chat({"msg": "Good luck, pilgrim! [b]no bbcode[/b]"})
	var chatted := false
	var t := 0.0
	var idle_turn_seen := -1
	while ends[0].is_empty() and t < 900.0:
		await get_tree().process_frame
		t += maxf(get_process_delta_time(), 0.001)
		_pump_one(0)
		var sy := syncs[0]
		if not chatted and sy.st.turn >= 4:
			chatted = true
			s.send_chat({"emote": "well_played"})
		if (sy.st.turn == bot_idle_turn or sy.st.turn == bot_idle_turn + 1) and sy.st.current == 0:
			idle_turn_seen = sy.st.turn
			continue
		if not waiting[0] and sy.st.current == 0 and not sy.st.in_mulligan() and not sy.pending() and sy.st.winner == -1:
			await get_tree().create_timer(0.7).timeout
			_maybe_act(0)
	print("bot END: ", ends[0])
	_finish()


## The bot's version of _pump (one client).
func _pump_one(k: int) -> void:
	var s := clients[k]
	while true:
		var m := s.next_message()
		if m.is_empty():
			break
		match int(m[0]):
			DuelSync.S_ACTION, DuelSync.S_TURN, DuelSync.S_MULLIGAN:
				syncs[k].push(m[0], m[1])
			DuelSync.S_END:
				ends[k] = m[1]
			DuelSync.S_ERROR:
				waiting[k] = false
	while true:
		var n := syncs[k].pop()
		if n.is_empty():
			break
		syncs[k].apply(n[0], n[1])
		if n[0] == DuelSync.S_TURN or (n[0] == DuelSync.S_ACTION and str(n[1].get("from")) == s.user_id()):
			waiting[k] = false
	if syncs[k].st.winner != -1 and not _result_sent:
		_result_sent = true
		s.send(DuelSync.OP_RESULT, {"winner": syncs[k].winner_id()})


var _result_sent := false


func _fail(msg: String) -> void:
	fails += 1
	printerr("ONLINE FAIL: " + msg)


func _wait_until(cond: Callable, seconds: float, what: String) -> bool:
	var t := 0.0
	while not cond.call():
		if t > seconds:
			_fail("timed out: " + what)
			return false
		await get_tree().process_frame
		t += maxf(get_process_delta_time(), 0.001)
		_pump()
	return true


func _run() -> void:
	for k in 2:
		var s := OnlineSession.new(900 + k)
		s.name = "Client%d" % k
		add_child(s)
		clients.append(s)
		s.failed.connect(func(m): _fail("client %d: %s" % [k, m]))
		var log_chat: Array = chats[k]
		s.chat.connect(func(m): log_chat.append(m))
	if not clients[0].configured():
		_fail("online play is not configured (pass --online-config=<file>)")
		_finish()
		return
	# Matchmaking: both queue, the server pairs them and both join with their decks.
	var classes := CardDB.classes()
	for k in 2:
		var cls: String = classes[k % classes.size()]
		var deck: Dictionary = CardDB.class_decks(cls)[0]
		clients[k].search(cls, CardDB.deck_list(str(deck.id)))
	if not await _wait_until(func(): return clients[0].in_match() and clients[1].in_match() \
			and not clients[0].start.is_empty() and not clients[1].start.is_empty(), 40.0, "both clients get START"):
		_finish()
		return
	print("matched: ", clients[0].match_id, "  names ", clients[0].start.get("names"))
	for k in 2:
		syncs[k] = DuelSync.new()
		if not syncs[k].setup(clients[k].start, clients[k].user_id()):
			_fail("client %d cannot read START: %s" % [k, syncs[k].error])
			_finish()
			return
		syncs[k].build()
	_check_same("opening")
	if syncs[0].me == syncs[1].me:
		_fail("both clients think they are the same player")
	# Chat: both open the direct channel; each says hello.
	for k in 2:
		await clients[k].open_chat()
	for k in 2:
		if clients[k].chat_channel == "":
			_fail("client %d: no chat channel" % k)
	await clients[0].send_chat({"msg": "Greetings from the smoke test"})
	await _wait_until(func(): return not chats[1].is_empty(), 10.0, "client 1 receives the chat message")
	if not chats[1].is_empty():
		print("chat received: ", chats[1][0].get("content"))
	await _cloud_save_step(clients[0])
	await _cloud_session_step(clients[1])
	# The mulligan: both send theirs at once.
	for k in 2:
		var pick := BattleAI.new(0, BattleAI.Level.EASY).mulligan_choice(syncs[k].st)
		clients[k].send(DuelSync.OP_MULLIGAN, syncs[k].mulligan_payload(pick))
	if not await _wait_until(func(): return not syncs[0].st.in_mulligan() and not syncs[1].st.in_mulligan() \
			and syncs[0].st.turn >= 1, 45.0, "the mulligan ends and turn 1 starts"):
		_finish()
		return
	_check_same("after the mulligan")
	# Play turns with Easy-AI moves; one client drops and rejoins halfway, the other later through the session's own
	# reconnect.
	var dropped := false
	var auto_dropped := false
	var t := 0.0
	while syncs[0].st.turn < turns_wanted and syncs[0].st.winner == -1 and t < TIMEOUT:
		await get_tree().process_frame
		t += maxf(get_process_delta_time(), 0.001)
		_pump()
		if not dropped and syncs[0].st.turn >= 3:
			dropped = true
			await _drop_and_rejoin(1)
			await _session_steps(0)
		if not auto_dropped and syncs[0].st.turn >= 5:
			auto_dropped = true
			await _auto_rejoin(0)
		for k in 2:
			_maybe_act(k)
	if t >= TIMEOUT:
		_fail("the duel did not reach turn %d" % turns_wanted)
	await _wait_until(func(): return not waiting[0] and not waiting[1], 10.0, "the last echoes")
	_check_same("turn %d" % syncs[0].st.turn)
	# Client 0 concedes: both must get END with the reason.
	clients[0].send(DuelSync.OP_CONCEDE, {})
	await _wait_until(func(): return not ends[0].is_empty() and not ends[1].is_empty(), 15.0, "both get END")
	for k in 2:
		if ends[k].is_empty():
			continue
		print("END for client %d: reason %s, winner is %s" % [k, ends[k].get("reason"),
			"client 1" if str(ends[k].get("winner")) == clients[1].user_id() else str(ends[k].get("winner"))])
		if str(ends[k].get("reason")) != "concede" or str(ends[k].get("winner")) != clients[1].user_id():
			_fail("client %d: wrong END %s" % [k, ends[k]])
	# Coming back to the finished duel on a new socket (a rejoin) is refused, and the player is told it has ended.
	# (The same socket would simply be told it is already in.)
	clients[1].client.close_socket()
	await clients[1].ensure_connected()
	var late := await clients[1].client.match_join(clients[1].match_id, {})
	if not late.has("error") or OnlineSession.join_error_text(late) != "That duel has already ended.":
		_fail("joining a finished duel: %s -> %s" % [late, OnlineSession.join_error_text(late)])
	else:
		print("a finished duel refuses the join (code %d): \"%s\"" % [int(late.get("code", -1)),
			OnlineSession.join_error_text(late)])
	for k in 2:
		if not syncs[k].desyncs.is_empty():
			_fail("client %d desyncs: %s" % [k, syncs[k].desyncs])
	_finish()


## Takes every waiting match message into the client's DuelSync and applies what is in order.
func _pump() -> void:
	for k in 2:
		var s := clients[k]
		while true:
			var m := s.next_message()
			if m.is_empty():
				break
			var op: int = m[0]
			var data: Dictionary = m[1]
			if syncs[k] == null:
				continue
			match op:
				DuelSync.S_ACTION, DuelSync.S_TURN, DuelSync.S_MULLIGAN:
					syncs[k].push(op, data)
				DuelSync.S_RESYNC:
					if log_resync:
						log_resync = false
						_describe_resync(data)
					# A move sent just before the drop may still arrive after the RESYNC: keep waiting for its echo
					# (a lost one times out in _maybe_act).
					for e in DuelSync.resync_events(data):
						syncs[k].push(e[0], e[1])
				DuelSync.S_END:
					ends[k] = data
				DuelSync.S_ERROR:
					errors[k].append(data)
					print("client %d got ERROR %s" % [k, data])
					waiting[k] = false
		if syncs[k] == null:
			continue
		while true:
			var n := syncs[k].pop()
			if n.is_empty():
				break
			var why := syncs[k].apply(n[0], n[1])
			if why != "":
				_fail("client %d: %s" % [k, why])
			if n[0] == DuelSync.S_TURN or (n[0] == DuelSync.S_ACTION and str(n[1].get("from")) == s_uid(k)):
				waiting[k] = false


func s_uid(k: int) -> String:
	return clients[k].user_id()


## The acting client picks an Easy-AI move from its own view and sends it (or ends its turn).
var _sent_at := [0, 0]


func _maybe_act(k: int) -> void:
	var sy := syncs[k]
	if waiting[k] and Time.get_ticks_msec() - _sent_at[k] > 8000:
		print("client %d: no echo in 8 s, deciding again" % k)
		waiting[k] = false
	if waiting[k] or sy == null or sy.st.winner != -1 or sy.st.in_mulligan() or sy.st.current != 0 or sy.pending():
		return
	if not clients[k].in_match() or not clients[k].client.socket_open():
		return
	var act: Dictionary = BattleAI.new(0, BattleAI.Level.EASY).next_action(sy.st)
	var probe := sy.st.clone(1)
	waiting[k] = true
	_sent_at[k] = Time.get_ticks_msec()
	if act.do == "end" or not BattleAI.apply(probe, 0, act):
		clients[k].send(DuelSync.OP_END_TURN, {})
		return
	match act.do:
		"play":
			clients[k].send(DuelSync.OP_ACTION, sy.play_payload(act.uid, act.target, act.index))
		"attack":
			clients[k].send(DuelSync.OP_ACTION, sy.attack_payload(act.attacker, act.target))
		"power":
			clients[k].send(DuelSync.OP_ACTION, sy.power_payload(act.target))


## Client k loses its socket and comes back: the server's RESYNC must rebuild the same game from scratch.
func _drop_and_rejoin(k: int) -> void:
	print("dropping client %d at turn %d" % [k, syncs[k].st.turn])
	var before := clients[k].resync
	clients[k].client.close_socket() # a deliberate close: no automatic reconnect
	await get_tree().create_timer(1.0).timeout
	var err := await clients[k].ensure_connected()
	if err != "":
		_fail("client %d could not reconnect: %s" % [k, err])
		return
	var r := await clients[k].client.match_join(clients[k].match_id, {})
	if r.has("error"):
		_fail("client %d could not rejoin: %s" % [k, r.error])
		return
	await _wait_until(func(): return clients[k].resync != before and not clients[k].resync.is_empty(), 10.0,
		"client %d gets RESYNC" % k)
	# A fresh copy rebuilt only from RESYNC must match the live one once both have applied the same seqs.
	var fresh := DuelSync.new()
	if not fresh.setup(clients[k].resync.get("start", {}), clients[k].user_id()):
		_fail("RESYNC start unreadable: %s" % fresh.error)
		return
	fresh.build()
	for e in DuelSync.resync_events(clients[k].resync):
		fresh.push(e[0], e[1])
	while true:
		var n := fresh.pop()
		if n.is_empty():
			break
		fresh.apply(n[0], n[1])
	await _wait_until(func(): return syncs[k].last_seq >= fresh.last_seq, 10.0, "the live copy catches up")
	if syncs[k].last_seq == fresh.last_seq and fresh.st.checksum() != syncs[k].st.checksum():
		_fail("the game rebuilt from RESYNC differs from the live one")
	else:
		print("RESYNC rebuild matches the live game (seq %d)" % fresh.last_seq)


## In the middle of the duel: the server answers a ping (the heartbeat), the app-resume check keeps a live socket, and
## renewing the 2 h session (after 100 min) keeps the duel's socket open: it used to close it without a word.
func _session_steps(k: int) -> void:
	var s := clients[k]
	if not await s.client.ping(5.0):
		_fail("client %d: no pong from the server" % k)
	s._notification(NOTIFICATION_APPLICATION_RESUMED)
	await _wait_until(func(): return not s._hb_busy, 8.0, "the resume check ends")
	if not s.client.socket_open():
		_fail("client %d: the resume check dropped a live socket" % k)
	var uid := s.user_id()
	s.client.token_time -= 101 * 60 # the session is now old enough to be renewed
	var err := await s.ensure_connected()
	if err != "" or not s.client.session_fresh() or not s.client.socket_open() or s.user_id() != uid or not s.in_match():
		_fail("client %d: renewing the session broke the duel (%s, socket %s)" % [k, err, s.client.socket_open()])
	else:
		print("ping, resume check and session renewal kept the duel's socket")


## The session's own path: its socket dies under it (drop_socket, as the heartbeat does), it reconnects and rejoins by
## itself, and the RESYNC's clock is the server's remaining time (rope included, never more than turn + rope).
func _auto_rejoin(k: int) -> void:
	var s := clients[k]
	var before := s.resync
	var ups := []
	var on_conn := func(up: bool): ups.append(up)
	s.connection.connect(on_conn)
	print("client %d: socket dropped at turn %d, the session rejoins" % [k, syncs[k].st.turn])
	s.client.drop_socket("smoke test drop")
	await _wait_until(func(): return ups.has(true), 30.0, "client %d reconnects by itself" % k)
	s.connection.disconnect(on_conn)
	if not ups.has(false):
		_fail("client %d: the drop was not reported" % k)
	if not await _wait_until(func(): return s.resync != before and not s.resync.is_empty(), 10.0,
			"client %d gets RESYNC after its own rejoin" % k):
		return
	var clock := DuelSync.resync_clock(s.resync)
	var left := int(clock[0]) - int(s.resync.get("_rx", 0))
	var limit := syncs[k].turn_ms + syncs[k].rope_ms
	if str(s.resync.get("phase")) == "play" and (left <= 0 or left > limit):
		_fail("RESYNC clock out of range: %d ms (limit %d)" % [left, limit])
	else:
		print("rejoined by itself; RESYNC clock %d ms left (phase %s, roped %s)" % [left, s.resync.get("phase"),
			s.resync.get("roped")])


## The cloud save on a test account: write a progress blob, read it back the same, and a write over a version that
## moved on must be refused as a conflict (the client then re-reads and merges).
func _cloud_save_step(s: OnlineSession) -> void:
	var c := s.client
	var data := {"collection": {"owned": {"virgil": 1}, "obols": 123, "packs": 2, "pity": 4, "opened": 6, "decks": []},
		"record": {"wins": 1, "losses": 2}, "online": {"wins": 0, "losses": 0, "draws": 0},
		"profile": {"name": "Smoke", "avatar": ""}, "settings": {"lessons": {"basics": "done"}, "coach_seen": ["mana"],
			"lessons_offered": true, "intro_seen": true}}
	var b := ProgressMerge.blob(data, int(Time.get_unix_time_from_system() * 1000.0))
	var before := await c.storage_read(OnlineSession.SAVE_COLLECTION, OnlineSession.SAVE_KEY)
	var w := await c.storage_write(OnlineSession.SAVE_COLLECTION, OnlineSession.SAVE_KEY, b,
		str(before.get("version", "")))
	if w.has("error"):
		_fail("cloud save write: %s" % w.error)
		return
	var r := await c.storage_read(OnlineSession.SAVE_COLLECTION, OnlineSession.SAVE_KEY)
	if r.has("error") or not ProgressMerge.same(r.get("value", {}), b):
		_fail("cloud save read back differs")
		return
	var stale := await c.storage_write(OnlineSession.SAVE_COLLECTION, OnlineSession.SAVE_KEY, b,
		str(before.version) if before.has("version") and str(before.version) != "" else "*")
	if not stale.get("conflict", false):
		_fail("a write over a newer save was not refused as a conflict (%s)" % stale)
		return
	var merged := ProgressMerge.merge(b, r.value)
	if not ProgressMerge.same(merged, b):
		_fail("merging a save with itself changed it")
		return
	print("cloud save: written, read back the same, stale write refused as a conflict")


## The session's own sync (what a player's game does), on a test account. A debug run writes no file: apply() only
## keeps the blob. 1) After a sign-in the account's older save is merged with this install's: the merged save is on
## the server. 2) Nothing changed: no write. 3) Another device wrote meanwhile: our write is refused, the session
## reads, merges and writes again, and both devices' cards are on the account.
func _cloud_session_step(s: OnlineSession) -> void:
	var c := s.client
	var away := {"collection": {"owned": {"smoke_far_card": 2}, "obols": 50, "packs": 1, "pity": 3, "opened": 3,
		"decks": [{"cls": "smoke", "name": "From the other device", "cards": []}]},
		"record": {"wins": 4, "losses": 1}, "online": {"wins": 0, "losses": 0, "draws": 0},
		"profile": {"name": "Far", "avatar": ""}, "settings": {"lessons": {}, "coach_seen": [],
			"lessons_offered": true, "intro_seen": true}}
	var before := await c.storage_read(OnlineSession.SAVE_COLLECTION, OnlineSession.SAVE_KEY)
	var w := await c.storage_write(OnlineSession.SAVE_COLLECTION, OnlineSession.SAVE_KEY,
		ProgressMerge.blob(away, 1000), "")
	if w.has("error") or before.has("error"):
		_fail("cloud session: could not seed the account's save")
		return
	s._sync_t = 1e9 # only the steps below sync, not the session's own timer
	s.cloud_forced = true
	s._need_login_sync = true
	s.last_applied = {}
	await s.cloud_sync()
	var local := s.gather()
	local.saved_at_ms = s._local_changed_ms
	var expected := ProgressMerge.merge(local, ProgressMerge.blob(away, 1000))
	var r := await c.storage_read(OnlineSession.SAVE_COLLECTION, OnlineSession.SAVE_KEY)
	if s.sync_state != "saved" or r.has("error") or not ProgressMerge.same(r.get("value", {}), expected):
		_fail("cloud session: the merged save is not on the account (%s)" % s.sync_state)
		s.cloud_forced = false
		return
	if not (r.value.data.collection.owned as Dictionary).has("smoke_far_card"):
		_fail("cloud session: the other device's card was lost")
	if not ProgressMerge.same(expected, local) and s.last_applied.is_empty():
		_fail("cloud session: the account had more than this install but nothing was applied")
	# 2) No change: no write.
	await s.cloud_sync()
	var r2 := await c.storage_read(OnlineSession.SAVE_COLLECTION, OnlineSession.SAVE_KEY)
	if str(r2.get("version", "")) != str(r.version):
		_fail("cloud session: a sync without changes wrote the save again")
	# 3) Another device writes; our next upload is refused, re-read, merged and written.
	var other: Dictionary = (r.value as Dictionary).duplicate(true)
	other.data.collection.owned["smoke_second_card"] = 1
	other.saved_at_ms = int(r.value.saved_at_ms) + 1
	var w2 := await c.storage_write(OnlineSession.SAVE_COLLECTION, OnlineSession.SAVE_KEY, other, str(r.version))
	if w2.has("error"):
		_fail("cloud session: the other device's write failed")
	s._synced = "pretend this install changed" # forces an upload over the stale version
	await s.cloud_sync()
	var r3 := await c.storage_read(OnlineSession.SAVE_COLLECTION, OnlineSession.SAVE_KEY)
	var owned3: Dictionary = r3.get("value", {}).get("data", {}).get("collection", {}).get("owned", {})
	if s.sync_state != "saved" or not owned3.has("smoke_second_card") or not owned3.has("smoke_far_card"):
		_fail("cloud session: the version conflict was not merged (%s)" % s.sync_state)
	s.cloud_forced = false
	print("cloud session: login merge, no-change skip and conflict re-merge OK")


func _describe_resync(d: Dictionary) -> void:
	var keys := d.keys()
	keys.sort()
	var evs: Array = d.get("events", [])
	print("RESYNC keys: ", keys, "  events: ", evs.size())
	if not evs.is_empty():
		print("  first event: ", JSON.stringify(evs[0]).left(300))
		print("  last event: ", JSON.stringify(evs[-1]).left(300))


func _check_same(when: String) -> void:
	var a := syncs[0].st.checksum()
	var b := syncs[1].st.checksum()
	if a != b:
		_fail("the two games differ %s (%s / %s)" % [when, a, b])
	else:
		print("same game %s: %s" % [when, a])


func _finish() -> void:
	for s in clients:
		s.leave_match()
		s.client.close_socket()
	await get_tree().create_timer(0.3).timeout
	print("ONLINE SMOKE: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
