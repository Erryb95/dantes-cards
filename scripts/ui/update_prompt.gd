class_name UpdatePrompt
## The update's dialogs on the game's bronze panel (UI.dialog): "Update available" with Update / Later, the download's
## progress on a heated bronze rod with Cancel, then Restart now (desktop) or Close the game (phones), or the failure.
## A version that needs a full download offers its release page instead. Updater does the work.


## The title screen's check, once per session, a few seconds after it opens, silent when offline or up to date (and
## never in tests or tooling, unless a debug build is given a local update source).
static func auto_check(menu: Node) -> void:
	if Updater.checked or not Updater.available():
		return
	if Game.debug_run() and Updater.local_source() == "":
		return
	Updater.checked = true
	var u := Updater.new()
	u.name = "Updater"
	menu.add_child(u)
	await menu.get_tree().create_timer(2.5).timeout
	if not is_instance_valid(u):
		return
	var res := await u.check()
	if not is_instance_valid(u) or not u.is_inside_tree():
		return
	if not res.state in ["patch", "full"]:
		u.queue_free()
		return
	# Never over another question (Virgil's first-launch offer, a duel to rejoin): after it.
	for i in 120:
		if menu.get_node_or_null("Dialog") == null:
			break
		await menu.get_tree().create_timer(0.5).timeout
		if not is_instance_valid(u):
			return
	if menu.get_node_or_null("Dialog") == null:
		offer(menu, res, u)


## Shows check()'s answer `res` ("patch" or "full") over `parent`; `u` (in the tree) downloads.
static func offer(parent: Node, res: Dictionary, u: Updater) -> Control:
	var d: Control
	if res.state == "patch":
		d = UI.dialog(parent, "Update available", Loc.t("Version %s is ready to download (%s).") % [res.version,
			size_text(int(res.entry.size))], [["Update", func(): download(parent, res, u)], ["Later", null]])
	else:
		var page := str(res.get("page", Updater.RELEASES_URL))
		d = UI.dialog(parent, "A new version", Loc.t("Version %s needs a new download of the whole game. Its page opens in your browser.") % res.version,
			[["Open the page", func(): OS.shell_open(page if UpdateBoot.url_allowed(page) else Updater.RELEASES_URL)],
				["Later", null]])
	_debug_hooks(d, "offer")
	return d


## Downloads, checks and installs `res`'s patch, showing the progress; then the restart (or the failure).
static func download(parent: Node, res: Dictionary, u: Updater) -> void:
	if not is_instance_valid(u) or not is_instance_valid(parent):
		return
	var total := int(res.entry.size)
	var d := UI.dialog(parent, "Downloading the update", _progress_text(0, total), [["Cancel", func(): u.cancel()]])
	var text: Label = d.find_children("*", "Label", true, false)[1]
	var bar := ProgressBar.new()
	bar.name = "Progress"
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.custom_minimum_size = Vector2(600, 30)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("background", UI.frame_box("slider_track", 14, 6,
		UI.box(Color(0.2, 0.1, 0.08), UI.GOLD_DARK, 2, 8)))
	bar.add_theme_stylebox_override("fill", UI.frame_box("slider_track", 14, 6,
		UI.box(UI.CRIMSON, UI.GOLD_DARK, 2, 8), Color(1.5, 0.75, 0.45))) # heated metal, like the options' sliders
	var row: Control = d.find_children("*", "HBoxContainer", true, false)[-1]
	row.get_parent().add_child(bar)
	row.get_parent().move_child(bar, row.get_index())
	var on_progress := func(done: int, all: int):
		if is_instance_valid(bar):
			bar.value = clampf(float(done) / maxf(1.0, all), 0.0, 1.0)
			text.text = _progress_text(done, all)
	u.progress.connect(on_progress)
	_debug_hooks(d, "progress", false)
	var err: String = await u.download(res)
	if is_instance_valid(u) and u.progress.is_connected(on_progress):
		u.progress.disconnect(on_progress)
	if is_instance_valid(d) and not d.is_queued_for_deletion():
		d.queue_free()
		parent.remove_child(d)
	if err == "cancelled" or not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	if err != "":
		push_warning("Updates: the update was not installed (%s)" % err)
		UI.dialog(parent, "Update failed", "The update could not be installed. Try again later.", [["Close", null]])
		return
	var tree := parent.get_tree()
	var done: Control
	if OS.has_feature("pc"):
		done = UI.dialog(parent, "Update installed", "The game restarts to finish the update.",
			[["Restart now", func(): Updater.restart(tree)], ["Later", null]])
	else:
		done = UI.dialog(parent, "Update installed", "Close the game and open it again to finish the update.",
			[["Close the game", func(): tree.quit()], ["Later", null]])
	_debug_hooks(done, "installed")


## "3.2 MB" ("3,2 MB" in Italian).
static func size_text(bytes: int) -> String:
	var s := "%.1f MB" % maxf(0.1, bytes / 1048576.0)
	return s.replace(".", ",") if Loc.lang() == "it" else s


static func _progress_text(done: int, total: int) -> String:
	return Loc.t("%s of %s") % [size_text(done), size_text(total)]


## Debug builds: `--update-shots=<dir>` saves each dialog as <dir>/update_<what>.png, `--update-yes` presses its first
## choice (an unattended trial).
static func _debug_hooks(d: Control, what: String, press := true) -> void:
	if not OS.is_debug_build():
		return
	var shots := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--update-shots="):
			shots = a.substr(15)
	if shots == "" and not Updater.auto_yes():
		return
	await d.get_tree().create_timer(1.2).timeout
	if not is_instance_valid(d):
		return
	if shots != "":
		DirAccess.make_dir_recursive_absolute(shots)
		d.get_viewport().get_texture().get_image().save_png(shots.path_join("update_%s.png" % what))
	if press and Updater.auto_yes() and is_instance_valid(d) and not d.is_queued_for_deletion():
		(d.find_children("*", "Button", true, false)[0] as Button).pressed.emit()
