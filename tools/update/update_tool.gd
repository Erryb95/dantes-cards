extends SceneTree
## Release tooling for in-game updates (docs/BUILD.md, "Updates"); tools/update/make_update.ps1 runs it.
##   $G --headless --path . -s res://tools/update/update_tool.gd -- <command> [--flag=value ...]
## Commands:
##   keygen   --private=<file outside the repo> [--public=res://config/update_public_key.pem] [--bits=3072]
##            Makes the signing key pair once. Refuses to overwrite a private key. Never prints a key.
##   apk-base --apk=<apk> --out=<pck> [--tmp=<dir>]
##            The base pack of a released APK: the files Android runs (assets/, as listed by its assets.sparsepck)
##            in a plain PCK, which --export-patch can compare against (a sparse pack cannot be).
##   pck-list --pck=<pck or exe> [--all]
##            The files of a pack (or an exe with one embedded): count, size, and every file the pack removes.
##   check    --pck=<patch> : fails when the patch removes a file the game needs (config/*.cfg, the public key).
##   manifest --dir=<release folder> --version=<v> --key=<private key> [--code=<android version code>]
##            [--full-required --reason=<text>] [--out=<dir>/update.json]
##            Writes the signed update.json for the patch-<base>-to-<version>-<platform>.pck files in the folder,
##            then checks it with the committed public key.
##   verify   --in=<update.json> [--dir=<folder with the packs>] : the signature and every pack's size and SHA-256.

const Boot := preload("res://scripts/core/update_boot.gd")
const REPO := "https://github.com/Erryb95/dantes-cards"


func _initialize() -> void:
	var args := {}
	var cmd := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "true"
		elif cmd == "":
			cmd = a
	var err := 1
	match cmd:
		"keygen": err = _keygen(args)
		"apk-base": err = _apk_base(args)
		"pck-list": err = _pck_list(args)
		"check": err = _check(args)
		"manifest": err = _manifest(args)
		"verify": err = _verify(args)
		_: printerr("update_tool: unknown command '%s' (see the header of tools/update/update_tool.gd)" % cmd)
	quit(err)


func _keygen(a: Dictionary) -> int:
	var priv := str(a.get("private", ""))
	var pub := str(a.get("public", Boot.PUBLIC_KEY))
	if priv == "" or priv.begins_with("res://") or ProjectSettings.globalize_path(priv).begins_with(ProjectSettings.globalize_path("res://")):
		printerr("keygen: --private must be a file outside the repository")
		return 1
	if FileAccess.file_exists(priv):
		printerr("keygen: %s exists: not overwritten (delete it by hand to make a new pair, and ship the new public key in a full build)" % priv)
		return 1
	var key := Crypto.new().generate_rsa(int(a.get("bits", "3072")))
	if key.save(priv) != OK or key.save(pub, true) != OK:
		printerr("keygen: could not write the keys")
		return 1
	print("keygen: private key written to %s, public key to %s" % [priv, pub])
	return 0


## The directory of a pack: {"version", "flags", "files": [{"path", "offset", "size", "md5", "flags"}]}; {} if not one.
## Reads plain packs and packs embedded at the end of an executable (Godot's PCK format 2 to 4).
static func read_pck(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var base := 0
	if f.get_32() != 0x43504447: # "GDPC"
		f.seek(f.get_length() - 4)
		if f.get_32() != 0x43504447:
			return {}
		f.seek(f.get_length() - 12)
		var size := f.get_64()
		base = f.get_length() - 12 - size
		f.seek(base)
		if f.get_32() != 0x43504447:
			return {}
	var ver := f.get_32()
	f.get_32() # engine major, minor, patch
	f.get_32()
	f.get_32()
	var flags := 0
	var dir_at := -1
	if ver >= 2:
		flags = f.get_32()
		f.get_64() # file base
		if ver >= 3:
			dir_at = f.get_64()
	if ver < 2 or ver > 4 or (flags & 1) != 0: # an encrypted directory is not read
		return {}
	if dir_at >= 0:
		f.seek(base + dir_at)
	else:
		f.seek(f.get_position() + 64)
	var n := f.get_32()
	var files := []
	for i in n:
		var l := f.get_32()
		var p := f.get_buffer(l).get_string_from_utf8()
		var off := f.get_64()
		var sz := f.get_64()
		var md5 := f.get_buffer(16).hex_encode()
		var fl := f.get_32()
		files.append({"path": p, "offset": off, "size": sz, "md5": md5, "flags": fl})
	return {"version": ver, "flags": flags, "files": files}


func _pck_list(a: Dictionary) -> int:
	var d := read_pck(str(a.get("pck", "")))
	if d.is_empty():
		printerr("pck-list: not a pack: " + str(a.get("pck", "")))
		return 1
	var total := 0
	var removed := []
	for e in d.files:
		total += int(e.size)
		if int(e.flags) & 2:
			removed.append(e.path)
		if a.has("all"):
			print("%10d  %s%s" % [e.size, e.path, "  (removed)" if int(e.flags) & 2 else ""])
	print("pck-list: %d files, %.1f MB, format %d" % [d.files.size(), total / 1048576.0, d.version])
	for p in removed:
		print("  removes " + str(p))
	return 0


## Files a patch must never remove: the server settings and the update key (a patch built in a checkout without
## config/online.local.cfg would delete it from the players' game).
func _check(a: Dictionary) -> int:
	var d := read_pck(str(a.get("pck", "")))
	if d.is_empty():
		printerr("check: not a pack: " + str(a.get("pck", "")))
		return 1
	var bad := 0
	for e in d.files:
		var p := str(e.path).trim_prefix("res://")
		if int(e.flags) & 2 and (p.begins_with("config/") or p == "project.binary" or p.begins_with("scripts/core/update_boot")):
			printerr("check: the patch removes %s (export it from the checkout that has it)" % p)
			bad += 1
		if p.begins_with("scripts/core/update_boot") or p == "config/update_public_key.pem":
			printerr("check: the patch changes %s, which runs before updates: this release needs a full download" % p)
			bad += 1
	print("check: %s, %d files" % ["ok" if bad == 0 else "FAILED", d.files.size()])
	return 0 if bad == 0 else 1


func _apk_base(a: Dictionary) -> int:
	var apk := str(a.get("apk", ""))
	var out := str(a.get("out", ""))
	var tmp := str(a.get("tmp", out + ".files"))
	var z := ZIPReader.new()
	if apk == "" or out == "" or z.open(apk) != OK:
		printerr("apk-base: cannot open --apk=" + apk)
		return 1
	var sparse := tmp.path_join("assets.sparsepck")
	DirAccess.make_dir_recursive_absolute(tmp)
	var sf := FileAccess.open(sparse, FileAccess.WRITE)
	sf.store_buffer(z.read_file("assets/assets.sparsepck"))
	sf.close()
	var d := read_pck(sparse)
	if d.is_empty():
		printerr("apk-base: the APK has no readable assets/assets.sparsepck")
		return 1
	var pk := PCKPacker.new()
	if pk.pck_start(out) != OK:
		printerr("apk-base: cannot write " + out)
		return 1
	var n := 0
	var temps: Array[String] = []
	for e in d.files:
		if int(e.flags) & 2:
			continue
		var p := str(e.path).trim_prefix("res://")
		var data := z.read_file("assets/" + p)
		if data.size() != int(e.size):
			printerr("apk-base: assets/%s is %d bytes in the APK, %d in its directory" % [p, data.size(), e.size])
			return 1
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_MD5)
		ctx.update(data)
		if ctx.finish().hex_encode() != str(e.md5):
			printerr("apk-base: assets/%s does not match its directory's MD5" % p)
			return 1
		var t := tmp.path_join("f%05d" % n)
		var w := FileAccess.open(t, FileAccess.WRITE)
		w.store_buffer(data)
		w.close()
		temps.append(t)
		pk.add_file("res://" + p, t)
		n += 1
	var err := pk.flush()
	z.close()
	for t in temps:
		DirAccess.remove_absolute(t)
	DirAccess.remove_absolute(sparse)
	DirAccess.remove_absolute(tmp)
	if err != OK:
		printerr("apk-base: writing the pack failed (%s)" % error_string(err))
		return 1
	print("apk-base: %d files from %s in %s" % [n, apk.get_file(), out])
	return 0


func _manifest(a: Dictionary) -> int:
	var dir := str(a.get("dir", "")).trim_suffix("/")
	var ver := str(a.get("version", ""))
	if dir == "" or not Boot.is_version(ver):
		printerr("manifest: needs --dir and --version")
		return 1
	var tag := "v" + ver
	var key := CryptoKey.new()
	if key.load(str(a.get("key", ""))) != OK: # the private key: read, never printed
		printerr("manifest: cannot read the private key at --key")
		return 1
	var full := a.has("full-required")
	var patches := []
	var re := RegEx.create_from_string("^patch-([0-9.]+)-to-" + ver.replace(".", "\\.") + "-([a-z]+)\\.pck$")
	for f in DirAccess.get_files_at(dir):
		var m := re.search(f)
		if m == null:
			continue
		var path := dir.path_join(f)
		var fa := FileAccess.open(path, FileAccess.READ)
		patches.append({"base": m.get_string(1), "platform": m.get_string(2), "file": f,
			"url": "%s/releases/download/%s/%s" % [REPO, tag, f], "size": fa.get_length(), "sha256": Boot.file_sha256(fa)})
	if patches.is_empty() and not full:
		print("manifest: no patch-*-to-%s-*.pck in %s: every older build is told to download the full game" % [ver, dir])
	var info := Engine.get_version_info()
	var m := {"version": ver, "version_code": int(a.get("code", "0")),
		"engine": "%d.%d.%d" % [info.major, info.minor, info.patch], "full_required": full,
		"reason": str(a.get("reason", "")), "page": "%s/releases/tag/%s" % [REPO, tag],
		"published": Time.get_date_string_from_system(true), "patches": [] if full else patches}
	if not Boot.valid_manifest(m):
		printerr("manifest: the manifest is not well formed (see UpdateBoot.valid_manifest)")
		return 1
	var text := Boot.sign_manifest(m, key)
	if Boot.open_signed(text, Boot.public_key()).is_empty():
		printerr("manifest: the private key does not match %s: the game would ignore this update" % Boot.PUBLIC_KEY)
		return 1
	var out := str(a.get("out", dir.path_join("update.json")))
	var w := FileAccess.open(out, FileAccess.WRITE)
	w.store_string(text)
	w.close()
	print("manifest: %s for %s, %d patches%s" % [out, ver, m.patches.size(), " (full download required)" if full else ""])
	for p in m.patches:
		print("  %s  over %s on %s, %.1f MB" % [p.file, p.base, p.platform, p.size / 1048576.0])
	return 0


func _verify(a: Dictionary) -> int:
	var path := str(a.get("in", ""))
	var m := Boot.open_signed(FileAccess.get_file_as_string(path), Boot.public_key())
	if m.is_empty():
		printerr("verify: %s is not signed with the committed key, or not well formed" % path)
		return 1
	var bad := 0
	var dir := str(a.get("dir", path.get_base_dir()))
	for p in m.patches:
		if not Boot.file_matches(dir.path_join(str(p.file)), int(p.size), str(p.sha256)):
			printerr("verify: %s is missing or not the signed file" % p.file)
			bad += 1
	print("verify: %s %s (engine %s%s), %d patches%s" % [path.get_file(), m.version, m.engine,
		", full download required" if m.full_required else "", m.patches.size(), ", all match" if bad == 0 else ""])
	return 0 if bad == 0 else 1
