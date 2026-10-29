class_name GoogleAuth
extends Node
## Google sign-in with the OAuth 2.0 device authorization flow (the game's client is a "TVs and Limited Input
## devices" client, so it works the same on a PC and on a phone): ask Google for a code, show it with the page to
## enter it on (any browser, any device), then poll until the player has approved; the answer carries the id_token
## that the Nakama server accepts. The client id and secret come from OnlineConfig and are never printed.
##
## An auth provider: `begin()` then `wait()`, both awaitable; `cancel()` stops the waiting. A future Steam provider
## gives the same two steps (a ticket instead of a code) to OnlineSession.sign_in_with().

const DEVICE_URL := "https://oauth2.googleapis.com/device/code"
const TOKEN_URL := "https://oauth2.googleapis.com/token"
const SCOPE := "openid email profile"

var config: OnlineConfig
var user_code := ""
var verification_url := ""
var _device_code := ""
var _interval := 5.0
var _expires_at := 0.0
var _cancelled := false


func _init(p_config: OnlineConfig = null) -> void:
	config = p_config


## Asks Google for a code. {} on success (`user_code`, `verification_url` set), else {"error"}.
func begin() -> Dictionary:
	_cancelled = false
	var r := await _post(DEVICE_URL, {"client_id": config.google_client_id, "scope": SCOPE})
	if r.has("error"):
		return r
	var b: Dictionary = r.body
	if int(r.code) != 200 or not b.has("device_code"):
		return {"error": _google_error(b, Loc.t("Google did not give a sign-in code."))}
	_device_code = str(b.device_code)
	user_code = str(b.get("user_code", ""))
	verification_url = str(b.get("verification_url", b.get("verification_uri", "https://www.google.com/device")))
	_interval = maxf(1.0, float(b.get("interval", 5)))
	_expires_at = Time.get_unix_time_from_system() + float(b.get("expires_in", 1800))
	return {}


## Polls until the player approves (or refuses, or the code expires). {"id_token", "name", "email"} or {"error"}
## ({"cancelled": true} after cancel()).
func wait() -> Dictionary:
	while not _cancelled:
		await get_tree().create_timer(_interval).timeout
		if _cancelled:
			break
		if Time.get_unix_time_from_system() > _expires_at:
			return {"error": Loc.t("The sign-in code expired. Try again.")}
		var r := await _post(TOKEN_URL, {"client_id": config.google_client_id,
			"client_secret": config.google_client_secret, "device_code": _device_code,
			"grant_type": "urn:ietf:params:oauth:grant-type:device_code"})
		if r.has("error"):
			continue # a network hiccup: keep polling until the code expires
		var b: Dictionary = r.body
		if b.has("id_token"):
			var claims := NakamaClient._jwt_claims(str(b.id_token))
			return {"id_token": str(b.id_token), "name": str(claims.get("name", "")),
				"email": str(claims.get("email", ""))}
		match str(b.get("error", "")):
			"authorization_pending":
				continue
			"slow_down":
				_interval += 5.0
			"access_denied":
				return {"error": Loc.t("Google sign-in was refused. While the game is in testing only its listed test " +
					"players can sign in with Google; you can still play as a guest.")}
			"expired_token":
				return {"error": Loc.t("The sign-in code expired. Try again.")}
			_:
				return {"error": _google_error(b, Loc.t("Google sign-in failed."))}
	return {"cancelled": true}


func cancel() -> void:
	_cancelled = true


func _google_error(b: Dictionary, fallback: String) -> String:
	var e := str(b.get("error", ""))
	var d := str(b.get("error_description", ""))
	if e == "":
		return fallback
	if e in ["invalid_client", "unauthorized_client"]:
		return Loc.t("This copy of the game is not allowed to use Google sign-in (%s).") % e
	return "%s (%s%s)" % [fallback, e, (": " + d) if d != "" else ""]


## A form POST; {"code", "body": Dictionary} or {"error"}.
func _post(url: String, form: Dictionary) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = 10.0
	add_child(req)
	var parts := PackedStringArray()
	for k in form:
		parts.append("%s=%s" % [k, str(form[k]).uri_encode()])
	var err := req.request(url, PackedStringArray(["Content-Type: application/x-www-form-urlencoded"]),
		HTTPClient.METHOD_POST, "&".join(parts))
	if err != OK:
		req.queue_free()
		return {"error": Loc.t("Could not reach Google.")}
	var res: Array = await req.request_completed
	req.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		return {"error": Loc.t("Could not reach Google.")}
	var parsed: Variant = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	return {"code": res[1], "body": parsed if parsed is Dictionary else {}}
