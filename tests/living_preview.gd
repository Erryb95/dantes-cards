extends Node
## Visual check of the living card art (ArtLiving). Record it with Godot's movie maker, e.g. 5 s at 30 fps:
##   Godot --path . res://tests/living_preview.tscn --resolution 1920x1080 --fixed-fps 30 --write-movie <dir>/f.png
##     --quit-after 170 -- --what=zoom|places|side|collection [--card=<id>] [--level=0|1|2]
## zoom: the card opened as the collection's zoom (CardZoom.open); places: the card at every size it appears (zoom,
## collection, hand, board portrait, a tilted hand card); side: the still (left) and the living art (right) at zoom
## size; art: the whole picture, still (left) and living (right), each ART_H px tall centred in its half of a
## 1920x1080 frame (what tools/cards/living_review.py measures); collection: the Collection screen on the card's
## class, legendaries first. --level forces ArtLiving's level.
## --frozen stops the cards' own motion (tilt, parallax drift, foil sweep), so a measure sees only the living art.
## Without --write-movie, `--snap=<file.png> [--snap-delay=s]` (the Game autoload) saves one frame.

const ART_H := 1000 ## the "art" view: each picture's height in pixels, its top at y = 40

var card := "francesca"
var what := "zoom"
var frozen := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--card="):
			card = a.substr(7)
		elif a.begins_with("--what="):
			what = a.substr(7)
		elif a == "--frozen":
			frozen = true
		elif a.begins_with("--level="):
			ArtLiving.forced = int(a.substr(8))
	Settings.fast_animations = false
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.1, 0.09)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var vs := root.get_viewport_rect().size
	match what:
		"zoom":
			CardZoom.open(root, card)
		"side":
			var keep := ArtLiving.forced
			for i in 2:
				ArtLiving.forced = ArtLiving.OFF if i == 0 else (keep if keep >= 0 else ArtLiving.FULL)
				var c := CardView.new().setup(card, -1, true)
				c.auto_tilt = false
				c.position = Vector2(vs.x * (0.3 + 0.4 * i), vs.y / 2)
				c.scale = Vector2.ONE * 1.9 * minf(1.0, vs.y / 1080.0)
				root.add_child(c)
				if frozen:
					c.set_process(false)
				var l := UI.label("Still" if i == 0 else "Living art", 30, "title", UI.BONE)
				l.position = Vector2(vs.x * (0.3 + 0.4 * i) - 120, 16)
				l.size = Vector2(240, 40)
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				root.add_child(l)
			ArtLiving.forced = keep
		"art":
			var tex := CardDB.art(card)
			var sz := Vector2(roundf(ART_H * float(tex.get_width()) / tex.get_height()), ART_H)
			for i in 2:
				var r := TextureRect.new()
				r.texture = tex
				r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				r.stretch_mode = TextureRect.STRETCH_SCALE
				r.size = sz
				r.position = Vector2(roundf(vs.x * (0.25 + 0.5 * i) - sz.x / 2), 40)
				if i == 1:
					var mat := ShaderMaterial.new()
					mat.shader = preload("res://assets/shaders/card_fx.gdshader")
					ArtLiving.setup_card(mat, card, float(tex.get_width()) / tex.get_height(), 0.5)
					r.material = mat
				root.add_child(r)
				var l := UI.label("Still" if i == 0 else "Living art", 24, "title", UI.BONE)
				l.position = Vector2(vs.x * (0.25 + 0.5 * i) - 120, 4)
				l.size = Vector2(240, 34)
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				root.add_child(l)
		"places":
			var big := CardView.new().setup(card, -1, true)
			big.auto_tilt = false
			big.position = Vector2(400, vs.y / 2)
			big.scale = Vector2(1.9, 1.9)
			root.add_child(big)
			var coll := CardView.new().setup(card, -1, true)
			coll.auto_tilt = false
			coll.position = Vector2(900, 300)
			coll.scale = Vector2(1.0, 1.0)
			root.add_child(coll)
			var hand := CardView.new().setup(card, -1, true)
			hand.auto_tilt = false
			hand.position = Vector2(1240, 300)
			hand.scale = Vector2(0.62, 0.62)
			root.add_child(hand)
			var tilted := CardView.new().setup(card, -1, true)
			tilted.auto_tilt = false
			tilted.hold_tilt = true
			tilted._tilt = Vector2(0.22, -0.12)
			tilted.position = Vector2(1620, 300)
			tilted.scale = Vector2(0.9, 0.9)
			root.add_child(tilted)
			for i in 2:
				var m := MinionView.new().setup({"uid": i + 1, "id": card, "side": 0, "attack": 5, "health": 6,
					"max_health": 6, "keywords": [], "sleeping": false})
				m.position = Vector2(1000 + i * 420, 820)
				m.scale = Vector2.ONE * (1.0 if i == 0 else 1.6)
				root.add_child(m)
		"collection":
			layer.queue_free()
			Settings.collection_sort = "rarity"
			var s: Node = load("res://scenes/collection.tscn").instantiate()
			Collection.owned[card] = 1
			add_child(s)
			await get_tree().create_timer(0.5).timeout
			s._set_filter(CardDB.card(card).get("set", "all"))
