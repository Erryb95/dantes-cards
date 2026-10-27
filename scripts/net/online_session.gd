class_name OnlineSession
extends Node
## One player's online life: the device account, the connection, the matchmaker, the match it is in, and the match
## messages waiting for the battle. The autoload `Online` is one of these; the online smoke test runs two in one
## process (`profile` keeps their accounts apart).
##
## Flow: `search(cls, cards)` signs in (device auth, display name), opens the socket and queues for a duel. When the
## matchmaker pairs two players both join the server's match with their deck as join metadata; the match's START
## (101) emits `match_ready`, and from then on every match message waits in `inbox` (in arrival order) until the
## battle takes it with `next_message()`. `rejoin()` / `check_rejoin()` bring a player back into a running duel
## after a restart or a lost connection: the server answers the join with RESYNC (107).

signal status(text: String) ## searching progress, for the overlay
signal match_ready(start: Dictionary)
signal failed(message: String)
signal connection(up: bool) ## the socket dropped (false) or came back and rejoined the duel (true)
signal chat(msg: Dictionary) ## a chat message in this duel's channel: {user_id, name, content}

enum State { IDLE, CONNECTING, SEARCHING, JOINING, IN_MATCH }

const RECONNECT_FOR := 40.0 ## seconds of trying to come back after the socket drops in a duel (grace is 30 s)

var profile := 0
var config: OnlineConfig
var client: NakamaClient
var state := State.IDLE
var match_id := ""
var start := {} ## the match's START payload
var resync := {} ## the last RESYNC payload (a rejoin)
var inbox: Array = [] ## [op, data] since START, oldest first
var ticket := ""
var chat_channel := ""
var _search_id := 0 ## bumps on every search / cancel, so a stale await knows it was cancelled
var _deck_meta := {}
var _reconnecting := false
var rejoin_checked := false ## the main menu asked the server about a running duel once this run


func _init(p_profile: int = -1) -> void:
	profile = p_profile
	if profile < 0:
		profile = 0
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--online-profile="):
				profile = maxi(0, int(a.substr(17)))
	config = OnlineConfig.load_default()


func _ready() -> void:
	client = NakamaClient.new(config)
	client.name = "Nakama"
	add_child(client)
	client.matched.connect(_on_matched)
	client.match_data.connect(_on_match_data)
	client.socket_closed.connect(_on_socket_closed)
	client.channel_message.connect(_on_channel_message)


func configured() -> bool:
	return config.configured()


func user_id() -> String:
	return client.user_id


func in_match() -> bool:
	return state == State.IN_MATCH and match_id != ""


# ---------------------------------------------------------------- identity

func _suffix() -> String:
	return "" if profile == 0 else "_%d" % profile


## This install's device id (made once, kept under user://; each `--online-profile` has its own).
func device_id() -> String:
	var path := "user://online_device%s.txt" % _suffix()
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var id := f.get_as_text().strip_edges()
			if id.length() >= 10:
				return id
	var made := _new_device_id()
	_save_device_id(made)
	return made


static func _new_device_id() -> String:
	return "dc-" + Crypto.new().generate_random_bytes(16).hex_encode()


func _save_device_id(id: String) -> void:
	var w := FileAccess.open("user://online_device%s.txt" % _suffix(), FileAccess.WRITE)
	if w != null:
		w.store_string(id)


# ---------------------------------------------------------------- Google (and, later, other providers)

func _google_path() -> String:
	return "user://online_google%s.cfg" % _suffix()


func google_available() -> bool:
	return config.google_ready()


## The Google account this install is signed in with: {name, email}, or {} for a guest.
func google_account() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(_google_path()) != OK:
		return {}
	return {"name": str(cfg.get_value("google", "name", "")), "email": str(cfg.get_value("google", "email", ""))}


## Signs this install in with Google (an id_token from GoogleAuth). The guest account is linked to Google, so nothing
## is lost; when that Google account already has its own game account, this install moves onto it instead (it gets a
## new device id linked there, so later sign-ins land on the Google account). "" on success, else what went wrong.
func sign_in_google(id_token: String, info: Dictionary) -> String:
	var err := await sign_in_with("google", id_token)
	if err != "":
		return err
	var cfg := ConfigFile.new()
	cfg.set_value("google", "name", str(info.get("name", "")))
	cfg.set_value("google", "email", str(info.get("email", "")))
	cfg.save(_google_path())
	return ""


## The auth provider hook (Google now, Steam later): link the provider's identity to this install's account, or move
## the install onto the provider's own account when it already has one. "" on success, else what went wrong.
func sign_in_with(provider: String, token_value: String) -> String:
	var err := await ensure_connected()
	if err != "":
		return err
	var linked := await client.link_provider(provider, token_value)
	if linked.has("error"):
		var a := await client.authenticate_provider(provider, token_value)
		if a.has("error"):
			return str(a.error)
		var fresh := _new_device_id()
		var l := await client.link_device(fresh)
		if l.has("error"):
			return "Signed in, but this device could not be remembered (%s)." % str(l.error)
		_save_device_id(fresh)
		client.close_socket()
		await client.set_display_name(display_name(), avatar_url())
		var s := await client.connect_socket()
		if s.has("error"):
			return str(s.error)
	return ""


## Back to a guest: a fresh device account (the Google one stays on the server, for the next sign-in).
func play_as_guest() -> void:
	if state == State.IN_MATCH:
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_google_path()))
	_save_device_id(_new_device_id())
	client.close_socket()
	client.token = ""


## The name the opponent sees: the profile's name when there is one, else "Pilgrim" and four digits of the device.
## A second test profile on the same PC (`--online-profile=N`) adds " N", so two windows can be told apart.
func display_name() -> String:
	var n := str(Profile.online().get("display_name", "")).strip_edges().left(24)
	if n == "":
		n = "Pilgrim%04d" % (absi(device_id().hash()) % 10000)
	return n + ("" if profile == 0 else " %d" % profile)


func avatar_url() -> String:
	return str(Profile.online().get("avatar_url", ""))


# ---------------------------------------------------------------- connection

## Signs in (when the session is missing or old) and opens the socket. "" when connected, else a message to show.
func ensure_connected() -> String:
	if not configured():
		return "Online play is not configured on this copy of the game."
	if not _endpoint_picked:
		await _pick_endpoint()
	if not client.session_fresh():
		client.close_socket()
		var r := await client.authenticate_device(device_id())
		if r.has("error"):
			_endpoint_picked = false # the next try looks at both addresses again
			return str(r.error)
		await client.set_display_name(display_name(), avatar_url())
	if not client.socket_open():
		var s := await client.connect_socket()
		if s.has("error"):
			_endpoint_picked = false
			return str(s.error)
	return ""


var _endpoint_picked := false


## The primary address (the public Funnel host) when its healthcheck answers within 4 s, else the fallback (the
## tailnet address) when that one does. With neither, the primary stays and its error is what the player sees.
func _pick_endpoint() -> void:
	var was := config.use_fallback
	config.use_fallback = false
	if await client.healthcheck(4.0):
		_endpoint_picked = true
	elif config.has_fallback():
		config.use_fallback = true
		if await client.healthcheck(4.0):
			_endpoint_picked = true
		else:
			config.use_fallback = false
	if config.use_fallback != was:
		client.token = "" # a session is per server address: sign in again there
		client.close_socket()
	print("Online: using the %s server address" % ("fallback" if config.use_fallback else "primary"))


# ---------------------------------------------------------------- matchmaking

## Queues for a duel with this deck. Progress comes through `status`, the end through `match_ready` or `failed`.
func search(cls: String, cards: Array) -> void:
	_search_id += 1
	var my_search := _search_id
	_deck_meta = DuelSync.deck_metadata(cls, cards, display_name())
	_reset_match()
	state = State.CONNECTING
	status.emit("Connecting to the server...")
	var err := await ensure_connected()
	if my_search != _search_id:
		return
	if err != "":
		state = State.IDLE
		failed.emit(err)
		return
	# A duel still running (a crash, a closed window) comes first: go back into it.
	var active := await client.rpc_call("dantes_active_match")
	if my_search != _search_id:
		return
	if str(active.get("match_id", "")) != "":
		status.emit("Returning to your duel...")
		await _join(str(active.match_id), {}, my_search)
		return
	state = State.SEARCHING
	status.emit("Searching for an opponent...")
	ticket = await client.matchmaker_add()
	if my_search != _search_id:
		if ticket != "":
			client.matchmaker_remove(ticket)
		return
	if ticket == "":
		state = State.IDLE
		failed.emit("The server would not queue you: %s" % client.last_error)


func cancel_search() -> void:
	_search_id += 1
	if ticket != "":
		client.matchmaker_remove(ticket)
	ticket = ""
	if state != State.IN_MATCH:
		state = State.IDLE


func _on_matched(m: Dictionary) -> void:
	if state != State.SEARCHING:
		return
	ticket = ""
	var id := str(m.get("match_id", ""))
	if id == "":
		failed.emit("The match could not be created.")
		state = State.IDLE
		return
	status.emit("Opponent found!")
	await _join(id, _deck_meta, _search_id)


func _join(id: String, meta: Dictionary, my_search: int) -> void:
	state = State.JOINING
	match_id = id
	var r := await client.match_join(id, meta)
	if my_search != _search_id:
		client.match_leave(id)
		return
	if r.has("error"):
		state = State.IDLE
		match_id = ""
		failed.emit("Could not join the duel: %s" % str(r.error))
		return
	# START (or RESYNC on a rejoin) follows; wait for it a little.
	var t := 0.0
	while state == State.JOINING and t < 10.0 and my_search == _search_id:
		await get_tree().process_frame
		t += maxf(get_process_delta_time(), 0.001)
	if state == State.JOINING and my_search == _search_id:
		state = State.IDLE
		client.match_leave(id)
		match_id = ""
		failed.emit("The duel did not start.")


## On launch: is there a duel to go back to? Its match id, or "" (also when offline or not configured).
func check_rejoin() -> String:
	if not configured():
		return ""
	if await ensure_connected() != "":
		return ""
	var r := await client.rpc_call("dantes_active_match")
	return str(r.get("match_id", ""))


## Goes back into duel `id` (from check_rejoin): the server answers with RESYNC, then `match_ready` fires.
func rejoin(id: String) -> void:
	_search_id += 1
	_reset_match()
	status.emit("Returning to your duel...")
	var err := await ensure_connected()
	if err != "":
		failed.emit(err)
		return
	await _join(id, {}, _search_id)


func _reset_match() -> void:
	match_id = ""
	start = {}
	resync = {}
	inbox.clear()
	chat_channel = ""


# ---------------------------------------------------------------- the match

func _on_match_data(op: int, data: Dictionary) -> void:
	data["_rx"] = Time.get_ticks_msec() # when it arrived (the turn timer counts from here)
	match op:
		DuelSync.S_START:
			start = data
			inbox.clear()
			state = State.IN_MATCH
			match_ready.emit(start)
		DuelSync.S_RESYNC:
			resync = data
			var fresh := state != State.IN_MATCH
			if data.get("start") is Dictionary:
				start = data.start
			state = State.IN_MATCH
			inbox.append([op, data])
			if fresh:
				match_ready.emit(start)
		_:
			if state == State.IN_MATCH:
				inbox.append([op, data])


## The oldest match message the battle has not taken yet, or [].
func next_message() -> Array:
	return inbox.pop_front() if not inbox.is_empty() else []


func send(op: int, data: Dictionary = {}) -> bool:
	if match_id == "":
		return false
	return client.match_send(match_id, op, data)


## The duel is over (or abandoned): leave the match and its chat.
func leave_match() -> void:
	if chat_channel != "":
		client.chat_leave(chat_channel)
	if match_id != "":
		client.match_leave(match_id)
	_reset_match()
	state = State.IDLE


func _on_socket_closed(reason: String) -> void:
	if state == State.IN_MATCH and not _reconnecting:
		_reconnect()
	elif state in [State.SEARCHING, State.CONNECTING, State.JOINING]:
		_search_id += 1
		state = State.IDLE
		failed.emit("The connection was lost (%s)." % reason)


## The socket dropped during a duel: keep trying to come back (the server holds the seat for 30 s) and rejoin; the
## server's RESYNC then fills in what was missed.
func _reconnect() -> void:
	_reconnecting = true
	connection.emit(false)
	var t0 := Time.get_ticks_msec()
	var id := match_id
	while state == State.IN_MATCH and match_id == id and (Time.get_ticks_msec() - t0) / 1000.0 < RECONNECT_FOR:
		if await ensure_connected() == "":
			var r := await client.match_join(id, {})
			if not r.has("error"):
				_reconnecting = false
				if chat_channel != "" and start.has("players"):
					chat_channel = ""
					open_chat()
				connection.emit(true)
				return
		await get_tree().create_timer(2.0).timeout
	_reconnecting = false
	if state == State.IN_MATCH and match_id == id:
		inbox.append([DuelSync.S_END, {"winner": "", "loser": "", "reason": "connection_lost"}])


# ---------------------------------------------------------------- chat

## Opens the direct-message channel with the opponent (after START). Chat is optional: a refusal only logs.
func open_chat() -> void:
	var players: Array = start.get("players", [])
	if players.size() != 2 or chat_channel != "":
		return
	var other := str(players[1] if str(players[0]) == user_id() else players[0])
	var id := await client.chat_join(other)
	if id == "":
		push_warning("Online chat: the channel was refused (%s)." % client.last_error)
	chat_channel = id


func send_chat(content: Dictionary) -> bool:
	if chat_channel == "":
		return false
	var r := await client.chat_send(chat_channel, content)
	if r.has("error"):
		push_warning("Online chat: a message was refused (%s)." % str(r.error))
		return false
	return true


func _on_channel_message(m: Dictionary) -> void:
	if chat_channel == "" or str(m.get("channel_id", "")) != chat_channel:
		return
	chat.emit({"user_id": str(m.get("sender_id", "")), "name": str(m.get("username", "")),
		"content": m.get("content", {})})


# ---------------------------------------------------------------- record (apart from the games against the AI)

func _record_path() -> String:
	return "user://online_record%s.cfg" % _suffix()


func record() -> Dictionary:
	var cfg := ConfigFile.new()
	cfg.load(_record_path())
	return {"wins": int(cfg.get_value("record", "wins", 0)), "losses": int(cfg.get_value("record", "losses", 0)),
		"draws": int(cfg.get_value("record", "draws", 0))}


## Counts a finished duel: "win", "loss" or "draw".
func record_result(outcome: String) -> void:
	if Game.debug_run(): # screenshots and tests never touch the record
		return
	var cfg := ConfigFile.new()
	cfg.load(_record_path())
	var k := {"win": "wins", "loss": "losses"}.get(outcome, "draws") as String
	cfg.set_value("record", k, int(cfg.get_value("record", k, 0)) + 1)
	cfg.save(_record_path())
