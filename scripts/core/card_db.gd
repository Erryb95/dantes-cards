class_name CardDB
## Static access to data/cards.json, decks.json and arenas.json (no autoload, so headless tests can use it).

static var _cards: Dictionary = {}
static var _heroes: Dictionary = {}
static var _decks: Array = []
static var _arenas: Array = []
static var _loaded := false
static var _framed := {}


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var c: Dictionary = _read("res://data/cards.json")
	for card in c.get("cards", []):
		_cards[card.id] = card
	for h in c.get("heroes", []):
		_heroes[h.id] = h
	_decks = _read("res://data/decks.json").get("decks", [])
	_arenas = _read("res://data/arenas.json").get("arenas", [])


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


static func all_cards() -> Array:
	_ensure()
	return _cards.values()


static func decks() -> Array:
	_ensure()
	return _decks


static func deck(id: String) -> Dictionary:
	_ensure()
	for d in _decks:
		if d.id == id:
			return d
	return {}


static func arenas() -> Array:
	_ensure()
	return _arenas


static func arena(id: String) -> Dictionary:
	_ensure()
	for a in _arenas:
		if a.id == id:
			return a
	return {}


## Expands a deck's {id: count} map into a flat list of card ids.
static func deck_list(deck_id: String) -> Array[String]:
	var out: Array[String] = []
	var cards: Dictionary = deck(deck_id).get("cards", {})
	for id in cards:
		for i in int(cards[id]):
			out.append(id)
	return out


static func art(id: String) -> Texture2D:
	return _tex("res://assets/cards/art/%s.jpg" % id)


## The card art cropped to `aspect` (w / h), centred on the upper part of the picture where faces usually are.
static func art_framed(id: String, aspect: float, focus_y: float = 0.36) -> Texture2D:
	var tex := art(id)
	if tex == null:
		return null
	var sz := tex.get_size()
	var w := sz.x
	var h := w / aspect
	if h > sz.y:
		h = sz.y
		w = h * aspect
	# A real cropped texture (not an AtlasTexture) so shader UVs stay 0..1 for the oval mask.
	var key := "%s@%.3f@%.2f" % [id, aspect, focus_y]
	if _framed.has(key):
		return _framed[key]
	var img := tex.get_image()
	if img == null:
		return tex
	if img.is_compressed():
		img.decompress()
	var r := Rect2i(int((sz.x - w) / 2), int(clampf(sz.y * focus_y - h / 2, 0, sz.y - h)), int(w), int(h))
	var out := ImageTexture.create_from_image(img.get_region(r))
	_framed[key] = out
	return out


static func hero_art(id: String) -> Texture2D:
	return _tex("res://assets/cards/heroes/%s.jpg" % id)


static func _tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null
