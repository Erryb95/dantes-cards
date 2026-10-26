extends Node
## Scene of the opening cinematic (scenes/intro.tscn). Plays IntroPlayer full screen, marks the intro as seen when it
## ends or is skipped, then goes to the main menu. Started by the main menu on the first launch and by "Watch intro".
##
## Debug flags (after `--`):
##   --intro-from=<s>           start at that second
##   --intro-shots=<dir>        play in real time and save key frames as PNG, then quit (see tests/intro_shots.gd);
##                              --only=<shot id> captures one shot, --shot-size=WxH plays windowed at that size

var player: IntroPlayer


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	Sfx.pause_music(true)  # "Watch intro" from the menu: its piece waits and resumes afterwards
	var layer := CanvasLayer.new()
	layer.layer = 50  # under the scene fade of Game (layer 100)
	add_child(layer)
	player = IntroPlayer.new()
	layer.add_child(player)
	if not Settings.is_mobile():
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	if args.has("intro-shots"):
		if args.has("shot-size"):
			var wh: PackedStringArray = String(args["shot-size"]).split("x")
			get_window().mode = Window.MODE_WINDOWED
			get_window().size = Vector2i(int(wh[0]), int(wh[1]))
		var cap: Node = load("res://tests/intro_shots.gd").new()
		cap.set("out_dir", args["intro-shots"])
		cap.set("only", args.get("only", ""))
		cap.set("player", player)
		add_child(cap)
		player.finished.connect(func(_s: bool) -> void: get_tree().quit())
		return
	player.finished.connect(_on_finished)
	if args.has("intro-from"):
		player.seek(float(args["intro-from"]))


## The intro has been seen (kept in the settings), then back to the main menu.
func _on_finished(_skipped: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Settings.intro_seen = true
	Game.intro_played = true
	Settings.save()
	Sfx.pause_music(false)
	Game.go(Game.MENU)
