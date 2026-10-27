extends Node2D
## Visual check of the art depth parallax (ArtDepth): cards held at strong tilts (flat, left, right, up, down), or with
## --board, board minions at the same views plus the two heroes. Saves <out> with the parallax on and <out>_flat.png
## with it off (same tilt, same over-scale), for a side-by-side comparison.
##   Godot --path . res://tests/depth_preview.tscn --resolution 1920x1080 -- --out=<file.png> [--cards=id,id,id]
##     [--board] [--scale=s] [--amount=k] [--sweep=h|v] [--no-tilt]
## --amount overrides the strength, to compare tunings; --sweep turns the columns into a sweep of the view from one
## side to the other (-0.32 .. 0.32), to read the motion as a film strip; --no-tilt keeps the cards flat (parallax only).

const VIEWS := [Vector2.ZERO, Vector2(-0.32, 0.0), Vector2(0.32, 0.0), Vector2(0.0, -0.3), Vector2(0.0, 0.3)]

var _out := "user://depth_preview.png"
var _frames := 0
var _arts: Array[ShaderMaterial] = []
var _views: Array[Vector2] = []


func _ready() -> void:
	var ids: Array = ["cd_guy_montfort", "uh_semiramis", "oar_strike"]
	var board := false
	var s := 0.82
	var amount := -1.0
	var views: Array = VIEWS
	var tilt := true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--cards="):
			ids = Array(a.substr(8).split(","))
		elif a == "--board":
			board = true
		elif a.begins_with("--scale="):
			s = float(a.substr(8))
		elif a.begins_with("--amount="):
			amount = float(a.substr(9))
		elif a == "--no-tilt":
			tilt = false
		elif a.begins_with("--sweep="):
			var axis := Vector2(1, 0) if a.substr(8) == "h" else Vector2(0, 1)
			views = [-0.32, -0.16, 0.0, 0.16, 0.32].map(func(k): return axis * k)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.1, 0.09)
	bg.size = Vector2(1920, 1080)
	add_child(bg)
	for r in ids.size():
		for i in views.size():
			var gap := maxf(360.0, CardView.W * s + 24.0) # big scales push the last columns off screen
			var at := Vector2(200 + i * gap, 1080.0 / ids.size() * (r + 0.5))
			var mat: ShaderMaterial
			if board:
				var snap := {"uid": 1 + r * 10 + i, "id": ids[r], "side": 0, "attack": 3, "health": 4, "max_health": 4,
					"keywords": [], "sleeping": false}
				var m := MinionView.new().setup(snap)
				m.position = at
				m.scale = Vector2(s, s)
				m.set_process(false) # the view is fed below
				add_child(m)
				mat = m._art_mat
			else:
				var c := CardView.new().setup(ids[r], -1, true)
				c.auto_tilt = false
				c.hold_tilt = true
				c._tilt = views[i] if tilt else Vector2.ZERO
				c.position = at
				c.scale = Vector2(s, s)
				add_child(c)
				c.set_process(false) # one update for the tilt uniforms; the parallax is fed below
				c.call_deferred("_process", 0.0)
				mat = c._art_mat
			if amount >= 0.0:
				mat.set_shader_parameter("depth_amount", amount)
			_arts.append(mat)
			_views.append(views[i])
	if board:
		for i in 2:
			var h := HeroView.new().setup({"uid": 100 + i, "side": 0, "id": ["dante", "charon"][i], "health": 30})
			h.position = Vector2(1830, 270 + i * 520)
			h.set_process(false)
			add_child(h)
			if amount >= 0.0:
				h._art_mat.set_shader_parameter("depth_amount", amount)
			_arts.append(h._art_mat)
			_views.append(Vector2(0.3, 0.0) if i == 0 else Vector2(-0.3, 0.0))


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 40:
		for i in _arts.size():
			ArtDepth.look(_arts[i], _views[i])
	elif _frames == 40:
		get_viewport().get_texture().get_image().save_png(_out)
		for m in _arts:
			ArtDepth.look(m, Vector2.ZERO)
	elif _frames == 44:
		get_viewport().get_texture().get_image().save_png(_out.get_basename() + "_flat.png")
		get_tree().quit()
