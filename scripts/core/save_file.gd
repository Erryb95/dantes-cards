extends RefCounted
## SaveFile: safe reading of the player's save files (user://*.cfg). A damaged file never crashes the game and is never
## silently destroyed: a file that cannot be parsed is copied aside to "<path>.bad" before the game starts over, and
## a value of the wrong type falls back to its default. The autoloads preload it (`const SaveFile := preload(...)`),
## so it works before the editor has registered any class name.


## The ConfigFile at `path`: empty when the file is missing (a first run) or unreadable. An unreadable file is copied
## to "<path>.bad" when `keep_bad` is true (the next save would overwrite it); tests and tooling pass false.
static func open(path: String, keep_bad: bool = true) -> ConfigFile:
	var cfg := ConfigFile.new()
	if not FileAccess.file_exists(path):
		return cfg
	var err := cfg.load(path)
	if err == OK:
		return cfg
	push_warning("SaveFile: %s is damaged (error %d), starting from defaults" % [path, err])
	if keep_bad:
		DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".bad"))
	return ConfigFile.new()


## The value of section/key, or `fallback` when it is missing or of another type (an int and a float stand in for
## each other, so a hand-edited "1" for 1.0 still loads).
static func value(cfg: ConfigFile, section: String, key: String, fallback: Variant) -> Variant:
	if not cfg.has_section_key(section, key):
		return fallback
	var v: Variant = cfg.get_value(section, key)
	var want := typeof(fallback)
	if typeof(v) == want:
		return v
	if want == TYPE_FLOAT and typeof(v) == TYPE_INT:
		return float(v)
	if want == TYPE_INT and typeof(v) == TYPE_FLOAT:
		return int(v)
	return fallback
