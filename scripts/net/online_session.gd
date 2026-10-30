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
const JOIN_WAIT := 35.0 ## seconds to wait for START after joining (the server gives both players 30 s to join)
const HEARTBEAT_EVERY := 15.0 ## seconds between pings while searching or in a duel (a dead socket is noticed)
const PING_TIMEOUT := 5.0

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
	_load_sync_meta()
	if cloud_on():
		get_tree().auto_accept_quit = false # closing the window first saves to the account (_notification)
		_sync_t = 2.0 # the first sync shortly after launch


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


## This install's id for its own win and loss counters in the account's save (ProgressMerge.record_section). Unlike
## the device id it never changes on a sign-in or on Play as guest.
func install_id() -> String:
	var path := "user://online_install%s.txt" % _suffix()
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var id := f.get_as_text().strip_edges()
			if id.length() >= 10:
				return id
	var made := "in-" + Crypto.new().generate_random_bytes(8).hex_encode()
	if not Game.debug_run():
		var w := FileAccess.open(path, FileAccess.WRITE)
		if w != null:
			w.store_string(made)
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
	if linked.has("error") and not link_taken(linked):
		# A network failure or a refused token: say so. Signing into the provider's account now would create a new,
		# empty account for it and leave this guest account (and its cloud save) behind.
		return Loc.t("Could not link the %s account: %s") % [provider.capitalize(), str(linked.error)]
	if linked.has("error"):
		var a := await client.authenticate_provider(provider, token_value)
		if a.has("error"):
			return str(a.error)
		# Another account (the provider's own): its save and this install's are merged at the next sync step.
		_account_gen += 1
		_need_login_sync = true
		_synced = ""
		_sync_t = 0.5
		var fresh := _new_device_id()
		var l := await client.link_device(fresh)
		if l.has("error"):
			return Loc.t("Signed in, but this device could not be remembered (%s).") % str(l.error)
		_save_device_id(fresh)
		client.close_socket()
		await client.set_display_name(display_name(), avatar_url())
		var s := await client.connect_socket()
		if s.has("error"):
			return str(s.error)
	return ""


## True when a link was refused because the identity already belongs to another game account (Nakama answers 409
## AlreadyExists, "... ID is already in use"): then the install moves onto that account.
static func link_taken(r: Dictionary) -> bool:
	return int(r.get("code", 0)) == 409 or str(r.get("error", "")).to_lower().contains("already in use")


## Back to a guest: a fresh device account (the Google one stays on the server, for the next sign-in).
func play_as_guest() -> void:
	if state == State.IN_MATCH:
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_google_path()))
	_save_device_id(_new_device_id())
	client.close_socket()
	client.token = ""
	_account_gen += 1
	_synced = ""
	_sync_t = 0.5 # the new guest account gets this install's progress


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
		return Loc.t("Online play is not configured on this copy of the game.")
	while _connecting: # another caller is signing in already: share its result
		await get_tree().process_frame
	_connecting = true
	var err := await _connect_now()
	_connecting = false
	return err


var _connecting := false


func _connect_now() -> String:
	# An open socket works on the address in use: never switch addresses under it (that would close it).
	if not _endpoint_picked and not client.socket_open():
		await _pick_endpoint()
	if not client.session_fresh():
		# A new token over HTTP (the 2 h session is renewed after 100 min). An open socket keeps working with the one
		# it was opened with, so it is not closed while a search or a duel runs on it (that silently lost the duel's
		# seat, or left the search waiting on a dead ticket); idle, it reconnects with the new token below.
		var was := client.user_id
		var r := await client.authenticate_device(device_id())
		if r.has("error"):
			_endpoint_picked = false # the next try looks at both addresses again
			return str(r.error)
		if state == State.IDLE or client.user_id != was:
			client.close_socket()
		if client.user_id != was:
			# A sign-in (not the same account's renewal): merge with the account's save. A renewal needs no merge (a
			# refused upload merges anyway), and a merge every 100 min could reorder the decks under the deck builder.
			_account_gen += 1
			_need_login_sync = true
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
	ticket = ""
	state = State.CONNECTING
	status.emit(Loc.t("Connecting to the server..."))
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
		status.emit(Loc.t("Returning to your duel..."))
		await _join(str(active.match_id), {}, my_search)
		return
	state = State.SEARCHING
	status.emit(Loc.t("Searching for an opponent..."))
	var got := await client.matchmaker_add()
	if my_search != _search_id:
		if got != "":
			client.matchmaker_remove(got)
		return
	if state != State.SEARCHING: # matched in the same moment the ticket came back: it is used up
		return
	ticket = got
	if ticket == "":
		state = State.IDLE
		failed.emit(Loc.t("The server would not queue you: %s") % client.last_error)


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
	var mt := str(m.get("ticket", ""))
	if ticket != "" and mt != "" and mt != ticket:
		return # a cancelled search's ticket the server paired just before its removal: not this search
	ticket = ""
	var id := str(m.get("match_id", ""))
	if id == "":
		failed.emit(Loc.t("The match could not be created."))
		state = State.IDLE
		return
	status.emit(Loc.t("Opponent found!"))
	await _join(id, _deck_meta, _search_id)


func _join(id: String, meta: Dictionary, my_search: int) -> void:
	state = State.JOINING
	match_id = id
	var r := await client.match_join(id, meta)
	if my_search != _search_id: # cancelled meanwhile
		client.match_leave(id)
		if match_id == id and state != State.IN_MATCH:
			match_id = ""
		return
	if r.has("error"):
		state = State.IDLE
		match_id = ""
		failed.emit(join_error_text(r))
		return
	# START (or RESYNC on a rejoin) follows when both players are in: the server waits JOIN_WAIT for the other one
	# (then sends END "no_show", which `_on_match_data` turns into a failure at once).
	var t := 0.0
	var told := false
	while state == State.JOINING and t < JOIN_WAIT and my_search == _search_id:
		await get_tree().process_frame
		t += maxf(get_process_delta_time(), 0.001)
		if t > 3.0 and not told:
			told = true
			status.emit(Loc.t("Waiting for your opponent to arrive..."))
	if state == State.IN_MATCH:
		return
	if match_id == id: # cancelled, or no START in time: never stay in a match nobody plays
		client.match_leave(id)
		match_id = ""
	if state == State.JOINING and my_search == _search_id:
		state = State.IDLE
		failed.emit(Loc.t("Your opponent never arrived. Try again."))


## A refused match join, said plainly. Nakama: code 4 = no such match, 5 = the match refused the join (its reason).
static func join_error_text(r: Dictionary) -> String:
	var code := int(r.get("code", -1))
	var why := str(r.get("error", ""))
	if code == 4 or why.to_lower().contains("not found") or why.to_lower().contains("is over"):
		return Loc.t("That duel has already ended.")
	if code == 5:
		return Loc.t("The duel would not let you in: %s.") % why
	return Loc.t("Could not join the duel: %s") % why


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
	var my_search := _search_id
	_reset_match()
	status.emit(Loc.t("Returning to your duel..."))
	var err := await ensure_connected()
	if my_search != _search_id: # cancelled while connecting: do not join behind the player's back
		return
	if err != "":
		failed.emit(err)
		return
	await _join(id, {}, my_search)


func _reset_match() -> void:
	match_id = ""
	start = {}
	resync = {}
	inbox.clear()
	chat_channel = ""


# ---------------------------------------------------------------- the match

func _on_match_data(op: int, data: Dictionary) -> void:
	data["_rx"] = Time.get_ticks_msec() # when it arrived (the turn timer counts from here)
	# Only the match this session is joining or playing: a search cancelled while its join was under way (or a duel
	# already left) must not start a duel behind the player's back, nor feed another match's moves into this one.
	var mid := str(data.get("_mid", ""))
	if not state in [State.JOINING, State.IN_MATCH] or (mid != "" and mid != match_id):
		return
	if op == DuelSync.S_END and state == State.JOINING: # the server gave up waiting for the other player
		state = State.IDLE
		match_id = ""
		failed.emit(Loc.t("Your opponent never arrived. Try again.") if str(data.get("reason", "")) == "no_show"
			else Loc.t("That duel has already ended."))
		return
	match op:
		DuelSync.S_START:
			if DuelSync.version_clash(data): # the other player runs another version: its rules may differ
				client.match_leave(match_id)
				match_id = ""
				state = State.IDLE
				failed.emit(Loc.t("Your opponent has another version of the game. You both need the latest update."))
				return
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
		failed.emit(Loc.t("The connection was lost (%s).") % reason)


## The socket dropped during a duel: keep trying to come back (the server holds the seat for 30 s) and rejoin; the
## server's RESYNC then fills in what was missed.
func _reconnect() -> void:
	_reconnecting = true
	connection.emit(false)
	var t0 := Time.get_ticks_msec()
	var id := match_id
	var reason := "connection_lost"
	while state == State.IN_MATCH and match_id == id and (Time.get_ticks_msec() - t0) / 1000.0 < RECONNECT_FOR:
		if await ensure_connected() == "":
			var r := await client.match_join(id, {})
			if not (state == State.IN_MATCH and match_id == id): # the player left the duel meanwhile
				if not r.has("error"):
					client.match_leave(id)
				break
			if not r.has("error"):
				_reconnecting = false
				if chat_channel != "" and start.has("players"):
					chat_channel = ""
					open_chat()
				connection.emit(true)
				return
			if int(r.get("code", -1)) in [4, 5]: # no such match / the match refused: it is over, stop trying
				reason = "gone"
				break
		await get_tree().create_timer(2.0).timeout
	_reconnecting = false
	if state == State.IN_MATCH and match_id == id:
		inbox.append([DuelSync.S_END, {"winner": "", "loser": "", "reason": reason, "_mid": id}])


# ---------------------------------------------------------------- liveness (phones in the background, changed networks)

var _hb_t := 0.0
var _hb_busy := false


## While searching or in a duel: a ping every HEARTBEAT_EVERY seconds. A socket can look open long after it died (a
## phone that slept, Wi-Fi swapped for mobile data): with no pong it is dropped, which starts the rejoin (in a duel) or
## ends the search with a message (it would wait on a dead ticket for ever).
func _heartbeat(delta: float) -> void:
	if not state in [State.SEARCHING, State.IN_MATCH] or _reconnecting or _hb_busy or client == null \
			or not client.socket_open():
		_hb_t = 0.0
		return
	_hb_t += delta
	if _hb_t >= HEARTBEAT_EVERY:
		_hb_t = 0.0
		check_alive()


## Pings the server; no pong in PING_TIMEOUT seconds while the socket still looks open: drop it (see `_heartbeat`).
func check_alive() -> void:
	if _hb_busy or client == null or not client.socket_open():
		return
	_hb_busy = true
	var alive := await client.ping(PING_TIMEOUT)
	_hb_busy = false
	if not alive and client.socket_open():
		client.drop_socket(Loc.t("no answer from the server"))


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


# ---------------------------------------------------------------- cloud save (the progress follows the account)

signal sync_status_changed(text: String)
signal progress_applied ## the account's save replaced or completed this install's progress (menus refresh)

const SAVE_COLLECTION := "dantes_save"
const SAVE_KEY := "progress"
const SYNC_EVERY := 10.0 ## seconds between checks for changes (so at most one write every 10 s)
const PULL_EVERY := 30.0 ## seconds between reads of the account's save while the main menu is open
const RETRY_OFFLINE := 60.0

var sync_state := "" ## "", "syncing", "saved", "offline"
var _server_version := ""
var _server_blob := {} ## the account's save as last read or written
var _synced := "" ## ProgressMerge.canon of this install's data when it was last in step with the account
var _last_local := "" ## canon of the local data at the last check
var _local_changed_ms := 0 ## when the local progress last changed (saved_at_ms of the local blob)
var _need_login_sync := false
var _sync_t := 0.0
var _syncing := false
var _account_gen := 0 ## bumps on every switch of account: a sync step begun on the old one then leaves the flags alone
var _pull_now := false
var _pulled_ms := 0 ## ticks of the last read of the account's save
var _rec_base := {} ## "record" / "online" -> ProgressMerge.record_base at the last merge with the account ({} before it)
var _install := ""
var _quitting := false
var cloud_forced := false ## tests: sync even in a debug run (apply then writes no file)
var last_applied := {} ## tests: the last blob apply() would have put into the game


## The cloud save runs for real players with a configured server; tests and tooling never touch an account's save.
func cloud_on() -> bool:
	return configured() and (cloud_forced or not Game.debug_run())


func sync_text() -> String:
	match sync_state:
		"saved":
			return Loc.t("Saved to your account")
		"offline":
			return Loc.t("Offline: will sync later")
		"syncing":
			return Loc.t("Saving to your account...")
	return ""


func _set_sync(s: String) -> void:
	if s != sync_state:
		sync_state = s
		sync_status_changed.emit(sync_text())


func _sync_meta_path() -> String:
	return "user://cloud_sync%s.cfg" % _suffix()


func _load_sync_meta() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_sync_meta_path()) == OK:
		_local_changed_ms = int(cfg.get_value("sync", "local_changed_ms", 0))
		_last_local = str(cfg.get_value("sync", "last_local", ""))
		var rb: Variant = cfg.get_value("sync", "record_base", {})
		_rec_base = rb if rb is Dictionary else {}


func _save_sync_meta() -> void:
	if Game.debug_run():
		return
	var cfg := ConfigFile.new()
	cfg.set_value("sync", "local_changed_ms", _local_changed_ms)
	cfg.set_value("sync", "last_local", _last_local)
	cfg.set_value("sync", "record_base", _rec_base)
	cfg.save(_sync_meta_path())


static func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


## This install's progress as the account's save blob.
func gather() -> Dictionary:
	var data := {
		"collection": {"owned": Collection.owned.duplicate(), "obols": Collection.obols, "packs": Collection.packs,
			"pity": Collection.packs_since_legendary, "opened": Collection.opened_total,
			"decks": Collection.decks.duplicate(true), "deleted_decks": Collection.deck_tombs.duplicate()},
		"record": _section("record", {"wins": int(Game.stats.wins), "losses": int(Game.stats.losses),
			"class_games": Game.class_games.duplicate()}),
		"online": _section("online", record()),
		"profile": {"name": Settings.player_name, "avatar": Settings.player_avatar},
		"settings": {"lessons": Settings.lessons.duplicate(), "lessons_offered": Settings.lessons_offered,
			"intro_seen": Settings.intro_seen, "coach_seen": Settings.coach_seen.duplicate(),
			"difficulty": Settings.difficulty, "deck_choice": Settings.deck_choice.duplicate(true),
			"fast_animations": Settings.fast_animations, "subtitles": Settings.subtitles}}
	return ProgressMerge.blob(data, _local_changed_ms)


func _section(sec: String, totals: Dictionary) -> Dictionary:
	if _install == "":
		_install = install_id()
	return ProgressMerge.record_section(totals, _rec_base.get(sec, {}), _install)


## After a merge with the account: this install counts its own games from what the merged save holds.
func _adopt_record_base(merged: Dictionary) -> void:
	if _install == "":
		_install = install_id()
	var d: Dictionary = merged.get("data", {})
	_rec_base = {"record": ProgressMerge.record_base(d.get("record", {}), _install),
		"online": ProgressMerge.record_base(d.get("online", {}), _install)}


## Puts a save blob's progress into the game and its files (a backup of each file is kept first: <file>.bak).
## In a debug run (tests) nothing is written: the blob is only kept in `last_applied`.
func apply(b: Dictionary) -> void:
	if Game.debug_run():
		last_applied = b.duplicate(true)
		progress_applied.emit()
		return
	for f in ["user://collection.cfg", "user://settings.cfg", "user://progress.cfg", _record_path()]:
		if FileAccess.file_exists(f):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(f), ProjectSettings.globalize_path(f + ".bak"))
	var d: Dictionary = b.get("data", {})
	var col: Dictionary = d.get("collection", {})
	var owned := {}
	for id in col.get("owned", {}):
		if not CardDB.card(str(id)).is_empty():
			owned[str(id)] = maxi(0, int(col.owned[id]))
	Collection.owned = owned
	Collection.obols = maxi(0, int(col.get("obols", Collection.obols)))
	Collection.packs = maxi(0, int(col.get("packs", Collection.packs)))
	Collection.packs_since_legendary = maxi(0, int(col.get("pity", 0)))
	Collection.opened_total = maxi(0, int(col.get("opened", 0)))
	var decks := []
	for dk in col.get("decks", []):
		var clean: Dictionary = Collection._clean_deck(dk)
		if not clean.is_empty():
			decks.append(clean)
	Collection.decks = decks
	Collection.deck_tombs = ProgressMerge.merge_tombs(col.get("deleted_decks", {}), Collection.deck_tombs)
	Collection.save()
	var rec: Dictionary = d.get("record", {})
	Game.stats = {"wins": maxi(0, int(rec.get("wins", 0))), "losses": maxi(0, int(rec.get("losses", 0)))}
	var cg := {}
	for c in rec.get("class_games", {}):
		cg[str(c)] = int(rec.class_games[c])
	Game.class_games = cg
	Game._save_progress("stats", Game.stats)
	Game._save_progress("class_games", Game.class_games)
	var onl: Dictionary = d.get("online", {})
	var cfg := ConfigFile.new()
	for k in ["wins", "losses", "draws"]:
		cfg.set_value("record", k, maxi(0, int(onl.get(k, 0))))
	cfg.save(_record_path())
	var prof: Dictionary = d.get("profile", {})
	Settings.player_name = str(prof.get("name", Settings.player_name))
	Settings.player_avatar = str(prof.get("avatar", Settings.player_avatar))
	var st: Dictionary = d.get("settings", {})
	if st.get("lessons") is Dictionary:
		Settings.lessons = st.lessons
	Settings.lessons_offered = bool(st.get("lessons_offered", Settings.lessons_offered))
	Settings.intro_seen = bool(st.get("intro_seen", Settings.intro_seen))
	if st.get("coach_seen") is Array:
		Settings.coach_seen = st.coach_seen
	Settings.difficulty = clampi(int(st.get("difficulty", Settings.difficulty)), 0, Settings.DIFFICULTY_NAMES.size() - 1)
	if st.get("deck_choice") is Dictionary:
		Settings.deck_choice = st.deck_choice
	Settings.fast_animations = bool(st.get("fast_animations", Settings.fast_animations))
	Settings.subtitles = bool(st.get("subtitles", Settings.subtitles))
	Settings.save()
	progress_applied.emit()


func _process(delta: float) -> void:
	_heartbeat(delta)
	if not cloud_on() or _syncing:
		return
	_sync_t -= delta
	if _sync_t > 0.0:
		return
	_sync_t = SYNC_EVERY
	cloud_sync()


## One sync step: notice local changes, sign in when needed, merge with the account's save after a sign-in, and
## upload what the account does not have yet. Never blocks play: failures only set the status.
func cloud_sync() -> void:
	if _syncing or not cloud_on():
		return
	_syncing = true
	var local := gather()
	var now_canon := ProgressMerge.canon(local.data)
	if now_canon != _last_local:
		_last_local = now_canon
		_local_changed_ms = _now_ms()
		_save_sync_meta()
		local.saved_at_ms = _local_changed_ms
	if not client.session_fresh():
		if await ensure_connected() != "":
			_set_sync("offline")
			_sync_t = RETRY_OFFLINE
			_syncing = false
			return
	var gen := _account_gen
	if _need_login_sync or _synced == "":
		await _merge_with_account(local, gen)
	elif now_canon != _synced:
		await _push(local, gen)
	elif _pull_due():
		await _pull(local, gen)
	if gen == _account_gen:
		await _send_reports()
	_syncing = false


## Asks for a read of the account's save soon (the main menu opened, the app came back from the background), so
## progress made on another device meanwhile shows here without restarting the game.
func request_pull() -> void:
	_pull_now = true
	_sync_t = minf(_sync_t, 0.5)


## A read is due when one was asked for or PULL_EVERY has passed, and only on the main menu, out of any duel: a merge
## elsewhere could change the decks under the deck builder or the collection on screen.
func _pull_due() -> bool:
	if state != State.IDLE:
		return false
	var s := get_tree().current_scene
	if s == null or s.scene_file_path != Game.MENU:
		return false
	return _pull_now or Time.get_ticks_msec() - _pulled_ms >= int(PULL_EVERY * 1000.0)


## Reads the account's save; when another device wrote it since this install last did, merges it in.
func _pull(local: Dictionary, gen: int) -> void:
	_pull_now = false
	_pulled_ms = Time.get_ticks_msec()
	var got := await client.storage_read(SAVE_COLLECTION, SAVE_KEY)
	if gen != _account_gen:
		return
	if got.has("error"):
		_set_sync("offline")
		return
	if str(got.get("version", "*")) != _server_version:
		await _merge_with_account(local, gen, got)


## After a sign-in: read the account's save, merge it with this install's, apply what changed here, write what changed
## there. A write refused because the save moved on meanwhile reads, merges and writes again (once).
func _merge_with_account(local: Dictionary, gen: int, read := {}) -> void:
	_set_sync("syncing")
	for attempt in 2:
		var got := read
		if attempt > 0 or read.is_empty():
			got = await client.storage_read(SAVE_COLLECTION, SAVE_KEY)
		if gen != _account_gen: # the player switched accounts meanwhile: the next step merges with the new one
			return
		if got.has("error"):
			_set_sync("offline")
			return
		var server: Dictionary = got.get("value", {})
		# No save yet: "*" writes only if there still is none, so two devices creating it at once cannot overwrite
		# each other (the second one's write is refused, and it reads, merges and writes again).
		_server_version = str(got.version) if got.has("version") else "*"
		_server_blob = server
		var merged := ProgressMerge.merge(local, server)
		_adopt_record_base(merged)
		if not ProgressMerge.same(merged, local):
			apply(merged)
			_last_local = ProgressMerge.canon(gather().data)
			_local_changed_ms = int(merged.get("saved_at_ms", _now_ms()))
			_save_sync_meta()
		if not server.is_empty() and ProgressMerge.same(merged, server):
			_synced = _last_local
			_need_login_sync = false
			_set_sync("saved")
			return
		var w := await client.storage_write(SAVE_COLLECTION, SAVE_KEY, merged, _server_version)
		if gen != _account_gen:
			return
		if not w.has("error"):
			_server_version = str(w.version)
			_server_blob = merged
			_synced = _last_local
			_need_login_sync = false
			_set_sync("saved")
			return
		if not w.get("conflict", false):
			_set_sync("offline")
			return
		local = gather() # someone else wrote meanwhile: read again and merge on top of it
	_set_sync("offline")


## Uploads this install's progress (it changed since the last sync), keeping what the account holds that this build
## cannot show.
func _push(local: Dictionary, gen: int) -> void:
	_set_sync("syncing")
	var out := ProgressMerge.keep_foreign(local, _server_blob,
		func(id: String) -> bool: return not CardDB.card(id).is_empty(),
		func(cls: String) -> bool: return cls in CardDB.classes())
	var w := await client.storage_write(SAVE_COLLECTION, SAVE_KEY, out, _server_version)
	if gen != _account_gen:
		return
	if w.has("error"):
		if w.get("conflict", false):
			await _merge_with_account(local, gen)
		else:
			_set_sync("offline")
		return
	_server_version = str(w.version)
	_server_blob = out
	_synced = ProgressMerge.canon(local.data)
	_set_sync("saved")


## Quitting: one last upload when something changed (at most 3 s), then the game closes.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED:
		# Back from the background (Android, iOS): the OS may have killed the socket without a word. Check it now
		# rather than at the next heartbeat; a dead one is dropped and the duel rejoins (RESYNC brings the clock back).
		_hb_t = 0.0
		if state in [State.SEARCHING, State.IN_MATCH] and not _reconnecting:
			check_alive()
		request_pull() # another device may have played meanwhile
		return
	if what == NOTIFICATION_WM_CLOSE_REQUEST and cloud_on() and not _quitting:
		_quitting = true
		get_tree().create_timer(3.0).timeout.connect(func(): get_tree().quit())
		if not _syncing and client.session_fresh():
			_sync_t = SYNC_EVERY
			await cloud_sync()
		get_tree().quit()


# ---------------------------------------------------------------- match statistics (anonymous, see the server's dantes_telemetry.lua)

const REPORT_QUEUE := "user://match_reports.json"
const REPORT_QUEUE_MAX := 100 ## the oldest reports go first when the server is out of reach for long
const REPORTS_PER_SYNC := 5


## Queues one finished match against the AI (or a lesson) for the server's statistics: classes, decks, the result,
## turns and length, never a name. Sent with the next sync steps; kept on disk until the server takes it.
func report_match(data: Dictionary) -> void:
	if not cloud_on():
		return
	var q := _report_queue()
	q.append(data)
	while q.size() > REPORT_QUEUE_MAX:
		q.pop_front()
	_save_report_queue(q)
	_sync_t = minf(_sync_t, 2.0)


func _report_queue() -> Array:
	if not FileAccess.file_exists(REPORT_QUEUE):
		return []
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(REPORT_QUEUE))
	return v if v is Array else []


func _save_report_queue(q: Array) -> void:
	var f := FileAccess.open(REPORT_QUEUE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(q))


## Sends a few queued reports (RPC dantes_report over HTTP). A server without the RPC yet, or out of reach, keeps them.
func _send_reports() -> void:
	var q := _report_queue()
	var sent := 0
	while not q.is_empty() and sent < REPORTS_PER_SYNC and client.session_fresh():
		var r := await client.http(HTTPClient.METHOD_POST, "/v2/rpc/dantes_report", JSON.stringify(q[0]))
		if r.has("error") or int(r.get("code", 0)) != 200:
			break
		q.pop_front()
		sent += 1
	if sent > 0:
		_save_report_queue(q)


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
	_sync_t = minf(_sync_t, 1.0) # a finished duel goes to the account soon
	var cfg := ConfigFile.new()
	cfg.load(_record_path())
	var k := {"win": "wins", "loss": "losses"}.get(outcome, "draws") as String
	cfg.set_value("record", k, int(cfg.get_value("record", k, 0)) + 1)
	cfg.save(_record_path())
