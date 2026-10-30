class_name Updater
extends Node
## Checks for, downloads and installs updates (the mounting happens at the next start: UpdateBoot,
## scripts/core/update_boot.gd, which also defines what a valid update is).
##
## Every release on GitHub carries update.json, the signed manifest (docs/BUILD.md, "Updates"). The check reads the
## latest release's one, so it is one small request; it is silent when offline. A newer version with a patch for this
## build gives "patch": the pack is downloaded into the updates folder's tmp/, checked (size, SHA-256), moved into
## place with its manifest, and runs from the next start. A newer version without one (another engine, a change only
## a full build can carry, a build too old for the patches) gives "full": the release page, for a new download.
## Only https addresses on UpdateBoot.HOSTS are fetched, redirects included (each one is checked).
##
## Debug builds only, for tests and trials: `-- --update-source=<dir>` reads update.json and the packs from a local
## folder instead of GitHub (the manifest must still be signed), `--update-dir=<dir>` installs there instead of
## user://patches/ (UpdateBoot reads it too), `--update-yes` answers Update and Restart by itself.

const MANIFEST_URL := "https://github.com/Erryb95/dantes-cards/releases/latest/download/update.json"
const RELEASES_URL := "https://github.com/Erryb95/dantes-cards/releases/latest"
const CHECK_TIMEOUT := 12.0 ## seconds for the whole manifest request
const STALL_TIMEOUT := 30.0 ## a download with no new bytes for this long is given up
const MAX_MANIFEST := 256 * 1024
const MAX_HOPS := 6 ## redirects followed

signal progress(done: int, total: int)

static var checked := false ## the title screen's automatic check ran in this session
static var installed := "" ## the version installed in this session (it runs from the next start)

var _http: HTTPRequest
var _cancel := false
var _busy := false
var _waiting := false ## a request is out (request_completed still to come)


## Updates can be checked here: an exported game (UpdateBoot.enabled), or a debug build given a local source.
static func available() -> bool:
	return UpdateBoot.enabled() or local_source() != ""


## `--update-source=<dir>` (debug builds only): the folder standing for the release.
static func local_source() -> String:
	if not OS.is_debug_build():
		return ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--update-source=") and a.length() > 16:
			return a.substr(16).replace("\\", "/").trim_suffix("/") + "/"
	return ""


## `--update-yes` (debug builds only): the prompts answer themselves (an unattended trial).
static func auto_yes() -> bool:
	return OS.is_debug_build() and "--update-yes" in OS.get_cmdline_user_args()


## The version the player has: the update mounted at start, else the installed build's.
static func current_version() -> String:
	return UpdateBoot.game_version()


## What a verified manifest `m` means for a build of version `base` that runs version `current` (`base` or the
## update over it): {"state": "latest"}, {"state": "patch", "version", "entry"} or {"state": "full", "version",
## "page"}.
static func decide(m: Dictionary, current: String, base: String, plat: String, engine: String) -> Dictionary:
	var v := str(m.get("version", ""))
	if not UpdateBoot.newer(v, current) or (installed != "" and not UpdateBoot.newer(v, installed)):
		return {"state": "latest"}
	var entry := UpdateBoot.select_patch(m, base, plat, engine)
	if not entry.is_empty():
		return {"state": "patch", "version": v, "entry": entry}
	return {"state": "full", "version": v, "page": str(m.get("page", RELEASES_URL))}


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.max_redirects = 0 # followed by hand, each address checked
	add_child(_http)


## Asks the release for its manifest: decide()'s answer, or {"state": "error"} (offline, no answer, a manifest that
## is not signed or not readable). A release with no update.json counts as "latest".
func check() -> Dictionary:
	var text := ""
	var src := local_source()
	if src != "":
		if not FileAccess.file_exists(src + UpdateBoot.MANIFEST):
			return {"state": "latest"}
		text = FileAccess.get_file_as_string(src + UpdateBoot.MANIFEST)
	else:
		if not UpdateBoot.enabled():
			return {"state": "unavailable"}
		var r := await _fetch(MANIFEST_URL, "", MAX_MANIFEST, CHECK_TIMEOUT)
		if r.code == 404:
			return {"state": "latest"}
		if not r.ok:
			return {"state": "error"}
		text = (r.body as PackedByteArray).get_string_from_utf8()
	var m := UpdateBoot.open_signed(text, UpdateBoot.public_key())
	if m.is_empty():
		push_warning("Updates: the manifest is not signed or not readable: ignored")
		return {"state": "error"}
	var res := decide(m, current_version(), UpdateBoot.base_version(), UpdateBoot.platform(), UpdateBoot.engine_version())
	res["text"] = text
	return res


## Downloads the patch of check()'s answer `res`, checks it and installs it (it runs from the next start). "" when
## installed, else what went wrong (the folder keeps the update that was there).
func download(res: Dictionary) -> String:
	if _busy:
		return "busy"
	_busy = true
	_cancel = false
	var err := await _download(res)
	_busy = false
	return err


## Stops a download (the half file is deleted).
func cancel() -> void:
	_cancel = true
	_abort(HTTPRequest.RESULT_CANT_CONNECT)


## Ends the request that is out as `result` (cancel_request alone never reports back).
func _abort(result: int) -> void:
	if _http != null and _waiting:
		_http.cancel_request()
		_http.request_completed.emit(result, 0, PackedStringArray(), PackedByteArray())


func _download(res: Dictionary) -> String:
	var entry: Dictionary = res.entry
	var dir := UpdateBoot.patch_dir()
	DirAccess.make_dir_recursive_absolute(dir + "tmp")
	var part := dir + "tmp/" + str(entry.file) + ".part"
	var size := int(entry.size)
	var src := local_source()
	var got := ""
	if src != "":
		got = await _copy_local(src + str(entry.file), part, size)
	else:
		var r := await _fetch(str(entry.url), part, size + 1024, 0.0, size)
		got = "" if r.ok else ("cancelled" if _cancel else "download")
	if got != "":
		DirAccess.remove_absolute(part)
		return got
	if not UpdateBoot.file_matches(part, size, str(entry.sha256)):
		DirAccess.remove_absolute(part)
		return "corrupt"
	# In place: the pack first, then its manifest (until the manifest is replaced the old update stays valid).
	var pck := dir + str(entry.file)
	if FileAccess.file_exists(pck):
		DirAccess.remove_absolute(pck)
	if DirAccess.rename_absolute(part, pck) != OK:
		DirAccess.remove_absolute(part)
		return "write"
	var tmp := dir + "tmp/" + UpdateBoot.MANIFEST
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return "write"
	f.store_string(str(res.text))
	f.close()
	if FileAccess.file_exists(dir + UpdateBoot.MANIFEST):
		DirAccess.remove_absolute(dir + UpdateBoot.MANIFEST)
	if DirAccess.rename_absolute(tmp, dir + UpdateBoot.MANIFEST) != OK:
		return "write"
	var state := ConfigFile.new() # a new update gets its own MAX_FAILED_STARTS
	state.set_value("boot", "starts", 0)
	state.save(dir + UpdateBoot.STATE)
	# Older packs go now when they can (one mounted by this run stays until the next start cleans it).
	var keep := [UpdateBoot.MANIFEST, UpdateBoot.STATE, str(entry.file), UpdateBoot.loaded_file]
	var d := DirAccess.open(dir)
	if d != null:
		for name in d.get_files():
			if not name in keep:
				d.remove(name)
	installed = str(res.version)
	return ""


## Debug source: copies the pack in steps, so the progress shows as it would for a download.
func _copy_local(from: String, to: String, size: int) -> String:
	var a := FileAccess.open(from, FileAccess.READ)
	var b := FileAccess.open(to, FileAccess.WRITE)
	if a == null or b == null:
		return "download"
	var step := maxi(1, size / 40)
	while a.get_position() < a.get_length():
		if _cancel:
			return "cancelled"
		b.store_buffer(a.get_buffer(step))
		progress.emit(b.get_position(), size)
		await get_tree().create_timer(0.03).timeout
	b.close()
	return ""


## Removes the installed update: the game runs as installed from the next start. True when something was removed.
static func remove_updates() -> bool:
	var dir := UpdateBoot.patch_dir()
	var had := FileAccess.file_exists(dir + UpdateBoot.MANIFEST) or UpdateBoot.loaded_version != ""
	UpdateBoot.clean(dir, [])
	installed = ""
	return had


## An update is mounted or waiting for the next start.
static func has_update() -> bool:
	return UpdateBoot.loaded_version != "" or FileAccess.file_exists(UpdateBoot.patch_dir() + UpdateBoot.MANIFEST)


## A GET of `url` following up to MAX_HOPS redirects, each on an allowed https host: {"ok", "code", "body"} (`to_file`
## "": the body in memory, at most `max_body` bytes). `timeout` 0: no limit but the stall one. `total` > 0 reports
## progress.
func _fetch(url: String, to_file: String, max_body: int, timeout: float, total: int = 0) -> Dictionary:
	for hop in MAX_HOPS:
		print_verbose("Updates: GET " + url.get_slice("?", 0))
		if not UpdateBoot.url_allowed(url) or _cancel:
			return {"ok": false, "code": 0}
		_http.download_file = to_file
		_http.body_size_limit = max_body
		_http.timeout = timeout
		if _http.request(url, ["User-Agent: DantesInfernoCards/" + current_version()]) != OK:
			return {"ok": false, "code": 0}
		var watch := _watch(total)
		_waiting = true
		var r: Array = await _http.request_completed # result, code, headers, body
		_waiting = false
		watch.set_meta("done", true)
		var code: int = r[1]
		if code in [301, 302, 303, 307, 308]:
			url = ""
			for h in r[2]:
				if str(h).to_lower().begins_with("location:"):
					url = str(h).substr(9).strip_edges()
			continue
		var ok: bool = r[0] == HTTPRequest.RESULT_SUCCESS and code == 200
		return {"ok": ok, "code": code, "body": r[3]}
	return {"ok": false, "code": 0}


## Reports progress and gives up a stalled download, until the returned node's "done" meta is set.
func _watch(total: int) -> Node:
	var w := Node.new()
	add_child(w)
	_watch_loop(w, total)
	return w


func _watch_loop(w: Node, total: int) -> void:
	var last := -1
	var still := 0.0
	while is_instance_valid(w) and not w.has_meta("done"):
		await get_tree().create_timer(0.1).timeout
		if not is_instance_valid(w) or w.has_meta("done"):
			break
		var n := _http.get_downloaded_bytes()
		if total > 0:
			progress.emit(n, total)
			if n == last:
				still += 0.1
				if still >= STALL_TIMEOUT:
					_abort(HTTPRequest.RESULT_TIMEOUT)
			else:
				still = 0.0
			last = n
	if is_instance_valid(w):
		w.queue_free()


## Restarts the game with the same arguments (desktop), so the update runs. Elsewhere the player reopens it.
static func restart(tree: SceneTree) -> void:
	if OS.has_feature("pc"):
		var args := OS.get_cmdline_args()
		var user := OS.get_cmdline_user_args()
		if not user.is_empty():
			args.append("--")
			args.append_array(user)
		OS.set_restart_on_exit(true, args)
	tree.quit()
