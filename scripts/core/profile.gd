class_name Profile
## The player's profile: display name and avatar (a hero portrait), kept in Settings.player_name /
## Settings.player_avatar (user://settings.cfg, [profile]). Rules for a display name live here, so the profile panel,
## the settings loader and (later) the online client agree on them. No network code: `online()` is what the coming
## Nakama client will sync as the account's display_name / avatar_url.

const MIN_LEN := 3
const MAX_LEN := 16

static var _allowed: RegEx
static var _spaces: RegEx


## `raw` trimmed, with each run of spaces made one space (what a name is saved as).
static func clean(raw: String) -> String:
	if _spaces == null:
		_spaces = RegEx.create_from_string("\\s+")
	return _spaces.sub(raw.strip_edges(), " ", true)


## Why `raw` cannot be a display name (a short sentence for the player), or "" when it can (once cleaned): 3 to 16
## characters; letters (any alphabet, accents too), digits, spaces, "_" and "-".
static func problem(raw: String) -> String:
	var n := clean(raw)
	if n.length() < MIN_LEN:
		return "A name needs at least %d characters." % MIN_LEN
	if n.length() > MAX_LEN:
		return "A name can have at most %d characters." % MAX_LEN
	if _allowed == null:
		_allowed = RegEx.create_from_string("^[\\p{L}\\p{M}\\p{N} _-]+$")
	if _allowed.search(n) == null:
		return "Use only letters, digits, spaces, _ and -."
	return ""


static func valid(raw: String) -> bool:
	return problem(raw) == ""


## A name to offer a new player ("Pilgrim4821"): valid, and theirs to change.
static func suggestion() -> String:
	return "Pilgrim%04d" % randi_range(1000, 9999)


## The player's name, or "" while they have not chosen one (offline play never needs it; online play will).
static func display_name() -> String:
	return Settings.player_name


static func has_name() -> bool:
	return Settings.player_name != ""


## Every hero a player can wear as avatar: one per class (CardDB.classes), in data order.
static func avatars() -> Array[String]:
	var out: Array[String] = []
	for cls in CardDB.classes():
		var h := CardDB.class_hero(cls)
		if h != "":
			out.append(h)
	return out


## The avatar's hero id: the saved one while it is still a class hero, else the first class's hero.
static func avatar() -> String:
	var all := avatars()
	if all.has(Settings.player_avatar):
		return Settings.player_avatar
	return all[0] if not all.is_empty() else ""


## What the online client will sync for this player (Nakama's account fields).
static func online() -> Dictionary:
	return {"display_name": display_name(), "avatar_url": "hero:" + avatar()}
