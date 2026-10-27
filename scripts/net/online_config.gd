class_name OnlineConfig
extends RefCounted
## Where the online server is: `res://config/online.local.cfg` (shipped with the build, never committed: it holds the
## server key), then `user://online.cfg` on top of it. Both are plain INI files:
##
##     [online]
##     server_key = <the Nakama server key>
##     host = 100.80.41.96
##     port = 7450
##     scheme = http          ; http -> ws, https -> wss
##
## Values may be quoted or bare; `;` and `#` start a comment. A missing key means online play is not configured.

const RES_PATH := "res://config/online.local.cfg"
const USER_PATH := "user://online.cfg"

var server_key := ""
var host := ""
var port := 7350
var scheme := "http"


static func load_default() -> OnlineConfig:
	var c := OnlineConfig.new()
	c.read(RES_PATH)
	c.read(USER_PATH)
	for a in OS.get_cmdline_user_args(): # tests and tools: `-- --online-config=<path>`
		if a.begins_with("--online-config="):
			c.read(a.substr(16))
	return c


func configured() -> bool:
	return server_key != "" and host != ""


func http_base() -> String:
	return "%s://%s:%d" % [scheme, host, port]


func ws_base() -> String:
	return "%s://%s:%d" % ["wss" if scheme == "https" else "ws", host, port]


## Reads one INI file over the current values (a missing file changes nothing).
func read(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var section := ""
	for raw in f.get_as_text().split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with(";") or line.begins_with("#"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2).strip_edges().to_lower()
			continue
		if section != "online" or not "=" in line:
			continue
		var k := line.get_slice("=", 0).strip_edges().to_lower()
		var v := line.substr(line.find("=") + 1).strip_edges()
		if v.begins_with("\"") and v.ends_with("\"") and v.length() >= 2:
			v = v.substr(1, v.length() - 2)
		else:
			for mark in [" ;", " #"]:
				if mark in v:
					v = v.get_slice(mark, 0).strip_edges()
		match k:
			"server_key":
				server_key = v
			"host":
				host = v
			"port":
				if v.is_valid_int():
					port = int(v)
			"scheme":
				scheme = "https" if v.to_lower() in ["https", "wss"] else "http"
