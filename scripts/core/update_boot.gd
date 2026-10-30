extends Node
## The first autoload: mounts the installed update (a signed patch pack in user://patches/) before any other game script
## or scene is loaded, so the patched autoloads, scripts, scenes, data and textures are the ones the game runs.
##
## An update is a PCK patch over one full build (its "base"): the files that changed since that build. The folder holds
## the signed manifest it came with (update.json, as downloaded) and the pack it names. Each start checks, before
## loading anything: the manifest's RSA signature against the public key the build shipped with
## (config/update_public_key.pem), that the manifest has a patch for this build's version, platform and engine, and that
## the pack's size and SHA-256 are the signed ones. Anything else (a newer or older full build installed over it, a
## damaged file, a pack that kept the game from starting MAX_FAILED_STARTS times in a row) is deleted, and the game
## runs as installed.
##
## This script, and the public key, are read before any update is mounted: an update cannot change them. A change
## here ships as a full build (tools/update/make_update.ps1 refuses a patch that touches them). It names no class_name
## script, so mounting happens before any of them is compiled. Updater (scripts/core/updater.gd) checks for, downloads
## and installs updates; it uses the static functions below for every check, so both agree on what is valid.

const PUBLIC_KEY := "res://config/update_public_key.pem"
const DIR := "user://patches/"
const MANIFEST := "update.json"
const STATE := "boot.cfg" ## [boot] starts: the starts with this update that never reached START_OK seconds
const MAX_FAILED_STARTS := 3
const START_OK := 20.0 ## seconds of running that make a start a good one
const FORMAT := 1 ## of update.json
## Platforms with updates. Not the Web (the page is the update) and not iOS (no downloaded code in App Store apps).
const PLATFORMS := ["windows", "linux", "macos", "android"]

var loaded_version := "" ## the update mounted at this start ("" = none: the game runs as installed)
var loaded_file := "" ## its pack's file name
var status := "" ## why no update was mounted (the log, Options)


func _init() -> void:
	if not enabled():
		return
	var dir := patch_dir()
	var state := ConfigFile.new()
	state.load(dir + STATE)
	var starts := int(state.get_value("boot", "starts", 0))
	var res := pick_installed(dir, public_key(), base_version(), platform(), engine_version())
	if res.is_empty():
		status = "none"
		clean(dir, [])
		return
	if starts >= MAX_FAILED_STARTS:
		status = "removed after %d failed starts" % starts
		push_warning("Updates: %s did not start %d times in a row: removed" % [res.version, starts])
		clean(dir, [])
		return
	clean(dir, [MANIFEST, STATE, str(res.entry.file)]) # older packs, half downloads
	state.set_value("boot", "starts", starts + 1)
	state.set_value("boot", "version", res.version)
	state.save(dir + STATE)
	if not ProjectSettings.load_resource_pack(dir + str(res.entry.file), true):
		status = "could not mount " + str(res.entry.file)
		push_warning("Updates: " + status)
		return
	loaded_version = str(res.version)
	loaded_file = str(res.entry.file)
	print("Updates: running %s over the installed %s" % [loaded_version, base_version()])


func _ready() -> void:
	if loaded_version == "":
		return
	await get_tree().create_timer(START_OK).timeout
	var state := ConfigFile.new()
	state.load(patch_dir() + STATE)
	state.set_value("boot", "starts", 0)
	state.save(patch_dir() + STATE)


## The game's version: the mounted update's, else the installed build's.
func game_version() -> String:
	return loaded_version if loaded_version != "" else base_version()


## Updates apply to this run: an exported game on a platform that has them. A debug build may point them at another
## folder (`-- --update-dir=<dir>`, tests and trials only).
static func enabled() -> bool:
	return OS.has_feature("template") and platform() in PLATFORMS


## The version of the installed full build (project.godot: updates never change it, the settings are read at start).
static func base_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0"))


static func platform() -> String:
	return OS.get_name().to_lower()


static func engine_version() -> String:
	var v := Engine.get_version_info()
	return "%d.%d.%d" % [v.major, v.minor, v.patch]


## Where updates are installed: user://patches/, or `--update-dir=<dir>` in a debug build.
static func patch_dir() -> String:
	if OS.is_debug_build():
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--update-dir=") and a.length() > 13:
				return a.substr(13).replace("\\", "/").trim_suffix("/") + "/"
	return DIR


static func public_key() -> CryptoKey:
	var k := CryptoKey.new()
	if not FileAccess.file_exists(PUBLIC_KEY) or k.load_from_string(FileAccess.get_file_as_string(PUBLIC_KEY), true) != OK:
		return null
	return k


## The installed update this build may mount: {"version", "entry": the manifest's patch entry} or {} when there is
## none, its manifest is not signed by `key`, has no patch for this base / platform / engine, or the pack is missing
## or not the signed one.
static func pick_installed(dir: String, key: CryptoKey, base: String, plat: String, engine: String) -> Dictionary:
	if key == null or not FileAccess.file_exists(dir + MANIFEST):
		return {}
	var m := open_signed(FileAccess.get_file_as_string(dir + MANIFEST), key)
	if m.is_empty():
		return {}
	var entry := select_patch(m, base, plat, engine)
	if entry.is_empty() or not newer(str(m.version), base):
		return {}
	if not file_matches(dir + str(entry.file), int(entry.size), str(entry.sha256)):
		return {}
	return {"version": str(m.version), "entry": entry}


## The manifest inside a signed update.json ({"format": 1, "manifest": "<the manifest's JSON text>",
## "signature": "<base64 RSA signature of that text's SHA-256>"}), or {} when the text is not one, the signature is
## not `key`'s, or the manifest is not well formed (valid_manifest).
static func open_signed(text: String, key: CryptoKey) -> Dictionary:
	if key == null or text.length() > 256 * 1024:
		return {}
	var j = _parse(text)
	if not j is Dictionary or typeof(j.get("format")) != TYPE_FLOAT or int(j.format) != FORMAT:
		return {}
	if not j.get("manifest") is String or not j.get("signature") is String:
		return {}
	var body: String = j.manifest
	var sig := Marshalls.base64_to_raw(str(j.signature))
	if sig.size() < 128 or not Crypto.new().verify(HashingContext.HASH_SHA256, body.sha256_buffer(), sig, key):
		return {}
	var m = _parse(body)
	if not m is Dictionary or not valid_manifest(m):
		return {}
	return m


## JSON text's value, null when it is not JSON (quietly: a junk download is no error).
static func _parse(text: String) -> Variant:
	var j := JSON.new()
	return j.data if j.parse(text) == OK else null


## A signed update.json for manifest `m` (tools/update/update_tool.gd with the private key; tests with a throwaway one).
static func sign_manifest(m: Dictionary, key: CryptoKey) -> String:
	var body := JSON.stringify(m, "\t")
	var sig := Crypto.new().sign(HashingContext.HASH_SHA256, body.sha256_buffer(), key)
	return JSON.stringify({"format": FORMAT, "manifest": body, "signature": Marshalls.raw_to_base64(sig)}, "\t")


## Every field the game reads, of the right kind: "version" (dotted numbers), "engine", "full_required" (bool),
## "page" (a github.com page), "patches" (each with "base", "platform", "file" (a plain .pck name), "url" (an allowed
## https address), "size" and "sha256").
static func valid_manifest(m: Dictionary) -> bool:
	if not is_version(m.get("version")) or not m.get("engine") is String or not m.get("full_required") is bool:
		return false
	if not m.get("page") is String or not url_allowed(str(m.page)) or not m.get("patches") is Array:
		return false
	var hex := RegEx.create_from_string("^[0-9a-f]{64}$")
	var file := RegEx.create_from_string("^[A-Za-z0-9][A-Za-z0-9._-]*\\.pck$")
	for p in m.patches:
		if not p is Dictionary or not is_version(p.get("base")) or not p.get("platform") is String:
			return false
		if not p.get("file") is String or file.search(str(p.file)) == null or str(p.file).contains(".."):
			return false
		if not p.get("url") is String or not url_allowed(str(p.url)):
			return false
		if not typeof(p.get("size")) in [TYPE_INT, TYPE_FLOAT] or float(p.size) < 1.0 or not p.get("sha256") is String \
				or hex.search(str(p.sha256)) == null:
			return false
	return true


## Manifest `m`'s patch for a build of version `base` on `plat` with engine `engine`, or {} (no patch for it, or the
## update needs a full download).
static func select_patch(m: Dictionary, base: String, plat: String, engine: String) -> Dictionary:
	if bool(m.get("full_required", true)) or str(m.get("engine", "")) != engine:
		return {}
	for p in m.get("patches", []):
		if p is Dictionary and str(p.get("base")) == base and str(p.get("platform")) == plat:
			return p
	return {}


## Hosts the updater talks to: GitHub's release pages and the servers its downloads redirect to.
const HOSTS := ["github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com"]


## An https address on one of HOSTS (no user, no port).
static func url_allowed(url: String) -> bool:
	if not url.begins_with("https://"):
		return false
	var host := url.substr(8).get_slice("/", 0).get_slice("?", 0).get_slice("#", 0)
	return host in HOSTS


static func is_version(v) -> bool:
	return v is String and RegEx.create_from_string("^[0-9]{1,4}(\\.[0-9]{1,4}){0,3}$").search(v) != null


## Version `a` comes after `b` ("0.10.0" after "0.9.5").
static func newer(a: String, b: String) -> bool:
	var x := a.split(".")
	var y := b.split(".")
	for i in maxi(x.size(), y.size()):
		var p := int(x[i]) if i < x.size() else 0
		var q := int(y[i]) if i < y.size() else 0
		if p != q:
			return p > q
	return false


## File `path` is `size` bytes long with SHA-256 `sha256` (hex).
static func file_matches(path: String, size: int, sha256: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() != size:
		return false
	return file_sha256(f) == sha256


static func file_sha256(f: FileAccess) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	while f.get_position() < f.get_length():
		h.update(f.get_buffer(1 << 20))
	return h.finish().hex_encode()


## Deletes every file in `dir` (and its tmp/ folder) except those named in `keep`. A pack still mounted by this run
## may refuse (Windows): the next start deletes it.
static func clean(dir: String, keep: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if not f in keep:
			d.remove(f)
	var tmp := DirAccess.open(dir + "tmp")
	if tmp != null:
		for f in tmp.get_files():
			tmp.remove(f)
		d.remove("tmp")
