extends Node
## Used by the intro scene's `--intro-shots=<dir>`: while the cinematic plays in real time, saves frames of every shot
## (at 35% and 78%, plus the card moments) as PNG for visual review. `--only=<shot id>` captures just that shot and
## jumps the cinematic to just before it.

var out_dir := ""
var only := ""
var player: IntroPlayer
var _todo: Array[Dictionary] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var tl := IntroTimeline.build()
	var n := 0
	for s in tl["shots"]:
		var st := float(s["start"])
		var d := float(s["dur"])
		var times: Array[float] = [st + d * 0.35, st + d * 0.78]
		if only != "" and only != String(s["id"]):
			n += 1
			continue
		match s["id"]:
			"gate":
				times = [st + 4.0, st + 8.0, st + 12.0, st + 16.5]
			"charon":
				times = [st + d * 0.3, st + d * 0.55, st + d * 0.8]
			"title":
				times = [st + 2.2, st + 4.6, st + 5.6, st + 7.0]
			"open":
				times = [1.0, 3.9]
			"story":
				times = [st + 3.0, st + 6.0, st + 9.0]
		for k in times.size():
			_todo.append({"t": times[k], "name": "%02d_%s_%s.png" % [n, s["id"], "abcdefgh"[k]]})
		n += 1
	if only != "" and not _todo.is_empty():
		player.seek(maxf(float(_todo[0]["t"]) - 5.0, 0.0))


func _process(_delta: float) -> void:
	if _todo.is_empty() or not is_instance_valid(player):
		return
	if player.time >= float(_todo[0]["t"]):
		var item: Dictionary = _todo.pop_front()
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(out_dir.path_join(item["name"]))
		print("shot ", item["name"], " t=", snappedf(player.time, 0.1))
