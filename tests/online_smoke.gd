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


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--turns="):
			turns_wanted = int(a.substr(8))
	_run()


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
	# The mulligan: both send theirs at once.
	for k in 2:
		var pick := BattleAI.new(0, BattleAI.Level.EASY).mulligan_choice(syncs[k].st)
		clients[k].send(DuelSync.OP_MULLIGAN, syncs[k].mulligan_payload(pick))
	if not await _wait_until(func(): return not syncs[0].st.in_mulligan() and not syncs[1].st.in_mulligan() \
			and syncs[0].st.turn >= 1, 45.0, "the mulligan ends and turn 1 starts"):
		_finish()
		return
	_check_same("after the mulligan")
	# Play turns with Easy-AI moves; one client drops and rejoins halfway.
	var dropped := false
	var t := 0.0
	while syncs[0].st.turn < turns_wanted and syncs[0].st.winner == -1 and t < TIMEOUT:
		await get_tree().process_frame
		t += maxf(get_process_delta_time(), 0.001)
		_pump()
		if not dropped and syncs[0].st.turn >= 3:
			dropped = true
			await _drop_and_rejoin(1)
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
					for e in DuelSync.resync_events(data):
						syncs[k].push(e[0], e[1])
					waiting[k] = false
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
func _maybe_act(k: int) -> void:
	var sy := syncs[k]
	if waiting[k] or sy == null or sy.st.winner != -1 or sy.st.in_mulligan() or sy.st.current != 0 or sy.pending():
		return
	if not clients[k].in_match() or not clients[k].client.socket_open():
		return
	var act: Dictionary = BattleAI.new(0, BattleAI.Level.EASY).next_action(sy.st)
	var probe := sy.st.clone(1)
	waiting[k] = true
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
