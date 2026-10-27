class_name NakamaClient
extends Node
## A small Nakama client on Godot's own HTTPRequest and WebSocketPeer (no third-party SDK): device authentication,
## the account's display name, and the realtime socket with Nakama's JSON envelope protocol (matchmaker, matches,
## RPCs, chat). The socket is read every frame, which also answers the server's pings.
##
## Every call is awaitable and never throws: failures come back as {"error": "<plain message>"}, so the screens can
## show them. The server key and the session token never go into the log.

signal matched(data: Dictionary) ## matchmaker_matched: {match_id, ticket, users, self}
signal match_data(op: int, data: Dictionary) ## realtime match data, already decoded from base64 JSON
signal channel_message(msg: Dictionary) ## a chat message (content already parsed when it is JSON)
signal socket_closed(reason: String)
signal notice(envelope: Dictionary) ## any other unsolicited envelope (presence events, ...)

const HTTP_TIMEOUT := 8.0
const REPLY_TIMEOUT := 8.0

var config: OnlineConfig
var token := ""
var refresh_token := ""
var user_id := ""
var username := ""
var token_time := 0.0 ## Time.get_unix_time_from_system() when the token was issued

var _ws: WebSocketPeer
var _ws_open := false
var _cid := 0
var _replies := {} ## cid -> reply envelope


func _init(p_config: OnlineConfig = null) -> void:
	config = p_config if p_config != null else OnlineConfig.load_default()


func has_session() -> bool:
	return token != ""


## The session lasts 2 h on the server: refresh it a little before.
func session_fresh() -> bool:
	return token != "" and Time.get_unix_time_from_system() - token_time < 100 * 60


func socket_open() -> bool:
	return _ws != null and _ws_open and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN


# ---------------------------------------------------------------- HTTP

## One HTTP call; returns {"code": int, "body": Variant} or {"error": message}.
func http(method: int, path: String, body: Variant = null, basic := false, timeout := HTTP_TIMEOUT) -> Dictionary:
	if config == null or not config.configured():
		return {"error": "Online play is not configured."}
	var req := HTTPRequest.new()
	req.timeout = timeout
	if config.secure():
		req.set_tls_options(TLSOptions.client()) # the system's trusted certificates
	add_child(req)
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	if basic:
		headers.append("Authorization: Basic " + Marshalls.utf8_to_base64(config.server_key + ":"))
	elif token != "":
		headers.append("Authorization: Bearer " + token)
	var data := "" if body == null else JSON.stringify(body)
	var err := req.request(config.http_base() + path, headers, method, data)
	if err != OK:
		req.queue_free()
		return {"error": "Could not reach the server."}
	var res: Array = await req.request_completed
	req.queue_free()
	var result: int = res[0]
	var code: int = res[1]
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"error": "The server did not answer (%s)." % _http_result_name(result)}
	var text := (res[3] as PackedByteArray).get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text) if text != "" else {}
	return {"code": code, "body": parsed if parsed != null else {}}


static func _http_result_name(r: int) -> String:
	match r:
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CONNECTION_ERROR:
			return "no connection"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "unknown host"
		HTTPRequest.RESULT_TIMEOUT:
			return "timed out"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "secure connection failed"
	return "error %d" % r


## True when the server's healthcheck answers within `timeout` seconds (at the address in use).
func healthcheck(timeout := 4.0) -> bool:
	var r := await http(HTTPClient.METHOD_GET, "/healthcheck", null, false, timeout)
	return not r.has("error") and int(r.code) == 200


## Device authentication (the only kind the server accepts). True on success; else {"error"}.
func authenticate_device(device_id: String) -> Dictionary:
	var r := await http(HTTPClient.METHOD_POST, "/v2/account/authenticate/device?create=true", {"id": device_id}, true)
	if r.has("error"):
		return r
	if int(r.code) == 401:
		return {"error": "The server refused this game's key."}
	if int(r.code) != 200 or not (r.body is Dictionary) or not r.body.has("token"):
		return {"error": "Sign-in failed (%d)." % int(r.code)}
	_take_session(r.body)
	return {}


## An identity provider's sign-in: `provider` is Nakama's name for it ("google"; later "steam"), `token` what the
## provider gave (Google's id_token, a Steam session ticket). A new account when there is none. {} or {"error"}.
func authenticate_provider(provider: String, token_value: String) -> Dictionary:
	var r := await http(HTTPClient.METHOD_POST, "/v2/account/authenticate/%s?create=true" % provider,
		{"token": token_value}, true)
	if r.has("error"):
		return r
	if int(r.code) != 200 or not (r.body is Dictionary) or not r.body.has("token"):
		var why: Variant = r.body.get("message", r.code) if r.body is Dictionary else r.code
		return {"error": "The server refused the %s sign-in (%s)." % [provider.capitalize(), str(why)]}
	_take_session(r.body)
	return {}


## Links a provider's identity (or another device id) to the signed-in account. {} or {"error", "code"}.
func link_provider(provider: String, token_value: String) -> Dictionary:
	return await _link("/v2/account/link/%s" % provider, {"token": token_value})


func link_device(device_id: String) -> Dictionary:
	return await _link("/v2/account/link/device", {"id": device_id})


func _link(path: String, body: Dictionary) -> Dictionary:
	var r := await http(HTTPClient.METHOD_POST, path, body)
	if r.has("error"):
		return r
	if int(r.code) != 200:
		return {"error": str(r.body.get("message", "refused")) if r.body is Dictionary else "refused", "code": int(r.code)}
	return {}


func _take_session(body: Dictionary) -> void:
	token = str(body.token)
	refresh_token = str(body.get("refresh_token", ""))
	token_time = Time.get_unix_time_from_system()
	var claims := _jwt_claims(token)
	user_id = str(claims.get("uid", ""))
	username = str(claims.get("usn", ""))


func set_display_name(display_name: String, avatar_url := "") -> Dictionary:
	var body := {"display_name": display_name}
	if avatar_url != "":
		body["avatar_url"] = avatar_url
	var r := await http(HTTPClient.METHOD_PUT, "/v2/account", body)
	if r.has("error"):
		return r
	if int(r.code) != 200:
		return {"error": "The server did not take the name (%d)." % int(r.code)}
	return {}


static func _jwt_claims(jwt: String) -> Dictionary:
	var parts := jwt.split(".")
	if parts.size() < 2:
		return {}
	var p := parts[1].replace("-", "+").replace("_", "/")
	while p.length() % 4 != 0:
		p += "="
	var parsed: Variant = JSON.parse_string(Marshalls.base64_to_utf8(p))
	return parsed if parsed is Dictionary else {}


# ---------------------------------------------------------------- socket

## Opens the realtime socket with the current session. {} on success, else {"error"}.
func connect_socket() -> Dictionary:
	if token == "":
		return {"error": "Not signed in."}
	close_socket()
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 20
	_ws.outbound_buffer_size = 1 << 20
	var url := "%s/ws?lang=en&status=true&token=%s" % [config.ws_base(), token.uri_encode()]
	if _ws.connect_to_url(url, TLSOptions.client() if config.secure() else null) != OK:
		_ws = null
		return {"error": "Could not open the connection."}
	var t := 0.0
	while _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_CONNECTING and t < HTTP_TIMEOUT:
		await get_tree().process_frame
		t += get_process_delta_time()
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		close_socket()
		return {"error": "The live connection failed."}
	_ws_open = true
	return {}


func close_socket() -> void:
	if _ws != null:
		_ws.close()
	_ws = null
	_ws_open = false
	_replies.clear()


func _process(_delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		while _ws != null and _ws.get_available_packet_count() > 0:
			var text := _ws.get_packet().get_string_from_utf8()
			var env: Variant = JSON.parse_string(text)
			if env is Dictionary:
				_dispatch(env)
	elif state == WebSocketPeer.STATE_CLOSED:
		var why := _ws.get_close_reason()
		var was_open := _ws_open
		_ws = null
		_ws_open = false
		if was_open:
			socket_closed.emit(why if why != "" else "connection lost")


func _dispatch(env: Dictionary) -> void:
	if env.has("cid"):
		_replies[str(env.cid)] = env
		return
	if env.has("match_data"):
		var md: Dictionary = env.match_data
		var raw := str(md.get("data", ""))
		var parsed: Variant = JSON.parse_string(Marshalls.base64_to_utf8(raw)) if raw != "" else {}
		match_data.emit(int(md.get("op_code", 0)), parsed if parsed is Dictionary else {})
	elif env.has("matchmaker_matched"):
		matched.emit(env.matchmaker_matched)
	elif env.has("channel_message"):
		var m: Dictionary = env.channel_message
		var content: Variant = m.get("content", "")
		if content is String:
			var p: Variant = JSON.parse_string(content)
			if p is Dictionary:
				m["content"] = p
		channel_message.emit(m)
	else:
		notice.emit(env)


## Sends an envelope and waits for its reply (matched by cid). The reply envelope, or {"error"} (also when the server
## answered with an error: its message is kept).
func request(env: Dictionary, timeout := REPLY_TIMEOUT) -> Dictionary:
	if not socket_open():
		return {"error": "Not connected."}
	_cid += 1
	var cid := str(_cid)
	env["cid"] = cid
	_ws.send_text(JSON.stringify(env))
	var t := 0.0
	while not _replies.has(cid) and t < timeout and socket_open():
		await get_tree().process_frame
		t += maxf(get_process_delta_time(), 0.001)
	if not _replies.has(cid):
		return {"error": "The server did not answer in time." if socket_open() else "Connection lost."}
	var reply: Dictionary = _replies[cid]
	_replies.erase(cid)
	if reply.has("error"):
		var e: Dictionary = reply.error
		return {"error": str(e.get("message", "Server error")), "code": int(e.get("code", 0))}
	return reply


## Sends an envelope without waiting for a reply.
func send(env: Dictionary) -> bool:
	if not socket_open():
		return false
	_ws.send_text(JSON.stringify(env))
	return true


func rpc_call(id: String, payload: Dictionary = {}) -> Dictionary:
	var r := await request({"rpc": {"id": id, "payload": JSON.stringify(payload)}})
	if r.has("error"):
		return r
	var p: Variant = JSON.parse_string(str(r.get("rpc", {}).get("payload", "{}")))
	return p if p is Dictionary else {}


## Joins the matchmaker for a duel; the ticket, or "" (with the error in `last_error`).
var last_error := ""


func matchmaker_add() -> String:
	var r := await request({"matchmaker_add": {"min_count": 2, "max_count": 2, "query": "*",
		"string_properties": {"mode": "duel"}}})
	if r.has("error"):
		last_error = str(r.error)
		return ""
	return str(r.get("matchmaker_ticket", {}).get("ticket", ""))


func matchmaker_remove(ticket: String) -> void:
	if ticket != "":
		await request({"matchmaker_remove": {"ticket": ticket}}, 4.0)


## Joins match `match_id` with string `metadata`. {} on success, else {"error"} with the server's reason.
func match_join(match_id: String, metadata: Dictionary = {}) -> Dictionary:
	var body := {"match_id": match_id}
	if not metadata.is_empty():
		body["metadata"] = metadata
	var r := await request({"match_join": body})
	if r.has("error"):
		return r
	return r.get("match", {})


func match_leave(match_id: String) -> void:
	send({"match_leave": {"match_id": match_id}})


func match_send(match_id: String, op: int, data: Dictionary) -> bool:
	return send({"match_data_send": {"match_id": match_id, "op_code": str(op),
		"data": Marshalls.utf8_to_base64(JSON.stringify(data)), "reliable": true}})


# ---------------------------------------------------------------- chat (direct messages)

## Joins the direct-message channel with `other_user`; its channel id, or "".
func chat_join(other_user: String) -> String:
	var r := await request({"channel_join": {"target": other_user, "type": 2, "persistence": false, "hidden": true}})
	if r.has("error"):
		last_error = str(r.error)
		return ""
	return str(r.get("channel", {}).get("id", ""))


func chat_send(channel_id: String, content: Dictionary) -> Dictionary:
	return await request({"channel_message_send": {"channel_id": channel_id, "content": JSON.stringify(content)}})


func chat_leave(channel_id: String) -> void:
	if channel_id != "":
		send({"channel_leave": {"channel_id": channel_id}})
