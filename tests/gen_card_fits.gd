extends Node
## Writes data/card_text_fit.json: CardView.rules_fit's results for every card text in every language, so a card face
## is built without measuring its text (tens of ms per card). Run it after a card text, a translation, a font or the
## card layout changes (run_tests.gd checks the file matches):
##   Godot --headless --path . res://tests/gen_card_fits.tscn
## (a scene, not a -s script: the text measuring needs the autoloads.) ui_smoke.tscn checks the file is current.


func _ready() -> void:
	var fits := measure_all()
	var f := FileAccess.open(CardView.FITS_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(fits, "", true))
	f.close()
	print("card fits: %d texts" % fits.size())
	Loc.use("en")
	get_tree().quit()


## Every card text in every language -> its measured fit.
static func measure_all() -> Dictionary:
	var fits := {}
	for lang in Loc.LANGS:
		Loc.use(lang)
		for c in CardDB.all_cards():
			var src := CardView.rules_source(c)
			var is_spell: bool = c.get("type", "minion") == "spell"
			var key := CardView.fit_key(src[0], is_spell, src[1], src[2])
			if not fits.has(key):
				fits[key] = CardView.measure_rules_fit(src[0], is_spell, src[1], src[2])
	return fits


## The texts whose shipped fit differs from a fresh measurement (or is missing): empty when the file is current.
static func stale() -> Array:
	var shipped := {}
	if FileAccess.file_exists(CardView.FITS_PATH):
		var j = JSON.parse_string(FileAccess.get_file_as_string(CardView.FITS_PATH))
		if j is Dictionary:
			shipped = j
	var out := []
	var fresh := measure_all()
	Settings.apply_language() # back to the language the run uses
	for k in fresh:
		var a: Array = shipped.get(k, [])
		var b: Array = fresh[k]
		var same := a.size() == b.size()
		for i in mini(a.size(), b.size()):
			same = same and is_equal_approx(float(a[i]), float(b[i]))
		if not same:
			out.append(k)
	return out
