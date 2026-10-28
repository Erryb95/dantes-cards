class_name CardDB
## Static access to data/cards.json, decks.json and arenas.json (no autoload, so headless tests can use it).

static var _cards: Dictionary = {}
static var _heroes: Dictionary = {}
static var _classes: Array[String] = [] ## class ids in data order, one per hero
static var _decks: Array = []
static var _arenas: Array = []
static var _loaded := false
static var _framed := {}
static var _loops := {}
static var _depths := {}
static var _names := {}
static var _living := {} ## card id -> its living-art entry (data/living_art.json "cards")


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var c: Dictionary = _read("res://data/cards.json")
	for card in c.get("cards", []):
		_cards[card.id] = card
	for h in c.get("heroes", []):
		_heroes[h.id] = h
		if str(h.get("class", "")) != "" and not h["class"] in _classes:
			_classes.append(str(h["class"]))
	for f in DirAccess.get_files_at("res://data/sets"):
		if f.ends_with(".json"):
			for card in _read("res://data/sets/" + f).get("cards", []):
				_cards[card.id] = card
	_decks = _read("res://data/decks.json").get("decks", [])
	_arenas = _read("res://data/arenas.json").get("arenas", [])
	_living = _read("res://data/living_art.json").get("cards", {})


static func _read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("CardDB: cannot open " + path)
		return {}
	var data = JSON.parse_string(f.get_as_text())
	return data if data is Dictionary else {}


static func card(id: String) -> Dictionary:
	_ensure()
	return _cards.get(id, {})


static func hero(id: String) -> Dictionary:
	_ensure()
	return _heroes.get(id, {})


## Every playable class (one hero each: data/cards.json "heroes", each with its "class"), in data order.
static func classes() -> Array[String]:
	_ensure()
	return _classes


## The hero of class `cls` ("" when there is none).
static func class_hero(cls: String) -> String:
	_ensure()
	for h in _heroes.values():
		if h.get("class", "") == cls:
			return str(h.id)
	return ""


## The class's display name ("Pilgrim", "Ferryman"...).
static func class_title(cls: String) -> String:
	return str(hero(class_hero(cls)).get("class_name", cls.capitalize()))


## What a player needs to know about class `cls`, from its hero's entry in data/cards.json: "title" (Pilgrim...),
## "hero" (id), "hero_name", "tagline" (one line), "style" (two or three sentences), "keywords" (ids of UI.KEYWORD_HELP
## that define the class), "tips" (short play tips), "power" (the hero power: name, cost, text) and "power_icon".
static func class_info(cls: String) -> Dictionary:
	var h := hero(class_hero(cls))
	return {
		"title": class_title(cls),
		"hero": str(h.get("id", "")),
		"hero_name": str(h.get("name", "")),
		"tagline": str(h.get("class_tagline", "")),
		"style": str(h.get("class_style", "")),
		"keywords": h.get("class_keywords", []),
		"tips": h.get("class_tips", []),
		"power": h.get("power", {}),
		"power_icon": str(h.get("power_icon", "")),
	}


## The class a hero leads.
static func hero_class(hero_id: String) -> String:
	return str(hero(hero_id).get("class", ""))


## Every class but `cls` (the possible opponents).
static func other_classes(cls: String) -> Array[String]:
	var out: Array[String] = []
	for c in classes():
		if c != cls:
			out.append(c)
	return out


static func all_cards() -> Array:
	_ensure()
	return _cards.values()


## Ids of every epic and legendary minion and spell, sorted (the title screen's rotating showcase). Tokens, heroes
## and anything of lower rarity are left out; the set is read from the data, so new cards join by themselves.
static func showcase_ids() -> Array[String]:
	_ensure()
	var out: Array[String] = []
	for c in _cards.values():
		if str(c.get("rarity", "")) in ["epic", "legendary"] and str(c.get("type", "minion")) in ["minion", "spell"]:
			out.append(str(c.id))
	out.sort()
	return out


static func decks() -> Array:
	_ensure()
	return _decks


static func deck(id: String) -> Dictionary:
	_ensure()
	for d in _decks:
		if d.id == id:
			return d
	return {}


## A preconstructed deck's class (one of classes()).
static func deck_class(d: Dictionary) -> String:
	return str(d.get("cls", d.get("id", "")))


## The preconstructed decks of a class, in file order (the first one is the class's original starter).
static func class_decks(cls: String) -> Array:
	_ensure()
	return _decks.filter(func(d): return deck_class(d) == cls)


static func arenas() -> Array:
	_ensure()
	return _arenas


static func arena(id: String) -> Dictionary:
	_ensure()
	for a in _arenas:
		if a.id == id:
			return a
	return {}


## True when the arena exists and its painted board is installed (arenas without a board are skipped by the draw).
static func arena_ready(id: String) -> bool:
	# "draft": true keeps a painted board out of the draw until its art passes review (still forceable with --arena).
	return arena_painted(id) and not arena(id).get("draft", false)


## The arena's painted board is installed (draft or not).
static func arena_painted(id: String) -> bool:
	var a := arena(id)
	return not a.is_empty() and a.has("board") and ResourceLoader.exists("res://assets/arenas/" + str(a.board))


## Expands a deck's {id: count} map into a flat list of card ids.
static func deck_list(deck_id: String) -> Array[String]:
	var out: Array[String] = []
	var cards: Dictionary = deck(deck_id).get("cards", {})
	for id in cards:
		for i in int(cards[id]):
			out.append(id)
	return out


## The card's art, or the Acheron landscape as a placeholder until its painting arrives.
static func art(id: String) -> Texture2D:
	var t := _tex("res://assets/cards/art/%s.jpg" % id)
	return t if t != null else _tex("res://assets/arenas/acheron.jpg")


static func has_art(id: String) -> bool:
	return ResourceLoader.exists("res://assets/cards/art/%s.jpg" % id)


## The part of a picture of size `sz` that `art_framed` keeps for `aspect` (w / h): centred horizontally, around
## `focus_y` vertically (0 top .. 1 bottom).
static func _crop_rect(sz: Vector2, aspect: float, focus_y: float) -> Rect2i:
	var w := sz.x
	var h := w / aspect
	if h > sz.y:
		h = sz.y
		w = h * aspect
	return Rect2i(int((sz.x - w) / 2), int(clampf(sz.y * focus_y - h / 2, 0, sz.y - h)), int(w), int(h))


## The card art cropped to `aspect` (w / h), centred on the upper part of the picture where faces usually are.
static func art_framed(id: String, aspect: float, focus_y: float = 0.36) -> Texture2D:
	var tex := art(id)
	if tex == null:
		return null
	# A real cropped texture (not an AtlasTexture) so shader UVs stay 0..1 for the oval mask.
	var key := "%s@%.3f@%.2f" % [tex.resource_path, aspect, focus_y]
	if _framed.has(key):
		return _framed[key]
	var img := tex.get_image()
	if img == null:
		return tex
	if img.is_compressed():
		img.decompress()
	var out := ImageTexture.create_from_image(img.get_region(_crop_rect(tex.get_size(), aspect, focus_y)))
	_framed[key] = out
	return out


## The same crop as `art_framed`, as a UV rectangle (x, y, w, h in 0..1) of the full picture. The card shader's `crop`
## uniform takes it, so a card's looping video (same framing as the still) is cropped exactly like the still.
static func art_crop_uv(id: String, aspect: float, focus_y: float = 0.36) -> Rect2:
	var sz := art(id).get_size()
	var r := _crop_rect(sz, aspect, focus_y)
	return Rect2(Vector2(r.position) / sz, Vector2(r.size) / sz)


## The card's looping art (a legendary's Wan animation, same framing as its still), or null when it has none, the
## platform cannot play video, or video is switched off. Data-driven: a card animates when
## res://assets/cards/loops/<id>.ogv exists. Cached; the stream is shared by every view of the card.
static func art_loop(id: String) -> VideoStream:
	if _loops.has(id):
		return _loops[id]
	var stream: VideoStream = null
	var path := "res://assets/cards/loops/%s.ogv" % id
	# A card with living art (the painting animated in the shader) never plays its loop, even with the living art off.
	if not living(id).is_empty():
		_loops[id] = null
		return null
	# Headless runs (tests, servers) have nothing to show; DV_NOVIDEO=1 turns the loops off (same switch as the intro).
	if DisplayServer.get_name() != "headless" and OS.get_environment("DV_NOVIDEO") == "" 			and ClassDB.class_exists("VideoStreamPlayer") and ResourceLoader.exists(path):
		var res = load(path)
		if res is VideoStream:
			stream = res
	_loops[id] = stream
	return stream


## The card's living-art entry (data/living_art.json: motion parameters and the mask recipe, see ArtLiving), or {}
## for a card whose painting stays still.
static func living(id: String) -> Dictionary:
	_ensure()
	return _living.get(id, {})


## The living art's mask (assets/cards/living/<id>.png, written by tools/cards/living_mask.py), or null.
static func living_mask(id: String) -> Texture2D:
	return _tex("res://assets/cards/living/%s.png" % id)


## The hero's portrait, or the Acheron landscape (like a card without its painting) until it arrives.
static func hero_art(id: String) -> Texture2D:
	var t := _tex("res://assets/cards/heroes/%s.jpg" % id)
	return t if t != null else _tex("res://assets/arenas/acheron.jpg")


## The card art's depth map (near = white, made by tools/cards/make_depth.py from the full picture), or null when the
## card has none yet: then the art simply has no parallax. Cached. Pair it with `art_crop_uv` for a framed picture.
static func art_depth(id: String) -> Texture2D:
	return _depth("res://assets/cards/depth/%s.png" % id)


## The card's name as painted gilded lettering (assets/cards/names/<id>.png, keyed on transparency by
## tools/ui/import_ui_pieces.py), or null when it has none: then CardView sets the name in the title font. Cached.
static func name_tex(id: String) -> Texture2D:
	if not _names.has(id):
		_names[id] = _tex("res://assets/cards/names/%s.png" % id)
	return _names[id]


## The hero portrait's depth map, or null.
static func hero_depth(id: String) -> Texture2D:
	return _depth("res://assets/cards/depth/heroes/%s.png" % id)


static func _depth(path: String) -> Texture2D:
	if not _depths.has(path):
		_depths[path] = _tex(path)
	return _depths[path]


static func _tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null
