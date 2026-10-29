class_name Loc
## The game's languages. English is the source: every string in the code and the data is written in English, and
## data/i18n/<lang>/ holds the other languages (see data/i18n/README.md):
##   strings_*.json  {"English text": "translated text", ...}: UI text, looked up whole (`t`). A format template is
##                   translated before it is filled in: Loc.t("%d cards") % n, never Loc.t("%d cards" % n).
##   data_*.json     {"cards": {id: {...}}, "heroes": {...}, "decks": {...}, "arenas": {...}, "lessons": {...}}: the
##                   translated fields of data entries, laid over the English entry (`localize`).
## Text is translated where it is made (UI.label, UI.button... call `t`), so a Control's text is always the shown text
## and every measurement of it (ink centring, fitting) measures what the player reads. Godot's own auto-translation
## is not used.

const LANGS: Array[String] = ["en", "it"]
const NAMES := {"en": "English", "it": "Italiano"}
const DIR := "res://data/i18n/"

static var _lang := "en"
static var _strings := {} ## English -> translated, for _lang (empty for English)
static var _shown := {} ## the translations themselves: a text translated twice (a helper of a helper) is not missing
static var _data := {} ## kind -> id -> translated fields, for _lang
static var missing := {} ## English text asked for with no translation (a language other than English): the audit lists it


## The language a setting stands for: "en", "it", or "" / "auto" for the device's language (English when the game has
## no translation for it).
static func resolve(choice: String) -> String:
	if choice in LANGS:
		return choice
	var dev := OS.get_locale_language()
	return dev if dev in LANGS else "en"


## Switches the game to language `lang` (an id of LANGS) and loads its texts. Card data is read again on its next use.
static func use(lang: String) -> void:
	_lang = lang if lang in LANGS else "en"
	_strings = {}
	_shown = {}
	_data = {}
	TranslationServer.set_locale(_lang)
	if _lang == "en":
		_reload_data()
		return
	var dir := DIR + _lang + "/"
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".json"):
			continue
		var j = JSON.parse_string(FileAccess.get_file_as_string(dir + f))
		if not j is Dictionary:
			push_error("Loc: cannot read " + dir + f)
			continue
		if f.begins_with("strings_"):
			for k in j:
				if not str(k).begins_with("_") and str(j[k]) != "":
					_strings[str(k)] = str(j[k])
					_shown[str(j[k])] = true
		elif f.begins_with("data_"):
			for kind in j:
				if str(kind).begins_with("_") or not j[kind] is Dictionary:
					continue
				if not _data.has(kind):
					_data[kind] = {}
				(_data[kind] as Dictionary).merge(j[kind], true)
				_mark_shown(j[kind])
	_reload_data()


static func _mark_shown(v) -> void:
	if v is String:
		_shown[v] = true
	elif v is Dictionary:
		for k in v:
			_mark_shown(v[k])
	elif v is Array:
		for x in v:
			_mark_shown(x)


static func _reload_data() -> void:
	CardDB.reload()
	Lessons.reload()


static func lang() -> String:
	return _lang


## `s` in the current language (itself when there is no translation, or the game is in English).
static func t(s: String) -> String:
	if _lang == "en":
		return s
	if _strings.has(s):
		return _strings[s]
	if _shown.has(s):
		return s
	if s.strip_edges() != "" and s.to_upper() != s.to_lower(): # some letters (not a number or a mark)
		missing[s] = true
	return s


## Every translated string, English -> translated (tests check the templates keep their %-placeholders).
static func strings() -> Dictionary:
	return _strings


## The translated fields of data entry `id` of `kind` ("cards", "heroes", "decks", "arenas", "lessons"), {} when none.
static func entry(kind: String, id: String) -> Dictionary:
	return (_data.get(kind, {}) as Dictionary).get(id, {})


## A copy of `src` (the English data entry `id` of `kind`) with its translated fields laid over it. Only text is
## replaced: a field the English entry lacks, or one that is not text there, keeps the English value.
static func localize(kind: String, id: String, src: Dictionary) -> Dictionary:
	var over := entry(kind, id)
	if over.is_empty():
		return src
	return _lay(src, over)


static func _lay(src, over):
	if src is Dictionary and over is Dictionary:
		var out: Dictionary = src.duplicate()
		for k in over:
			if out.has(k):
				out[k] = _lay(out[k], over[k])
		return out
	if src is Array and over is Array and (src as Array).size() == (over as Array).size():
		var out: Array = (src as Array).duplicate()
		for i in out.size():
			out[i] = _lay(out[i], over[i])
		return out
	if src is String and over is String and over != "":
		return over
	return src
