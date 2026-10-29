class_name IntroTimeline
extends RefCounted
## Data of the opening cinematic (see "Opening cinematic" in docs/DESIGN.md). Pure data and layout, no nodes, so the headless intro test can
## validate it. Times are in seconds; cues and voices are relative to a shot.
##
## Shot kinds: "black" (no picture) and "video" (a clip of a Doré plate, played ping-pong, through a moving camera
## and the engraving shader; the plate itself is the first frame / fallback).
## cam_from / cam_to: camera of the shot at its start / end, Vector3(centre x, centre y, zoom) in texture uv. The picture
## fills the whole screen at any aspect (no letterbox): window() turns a camera into the visible uv rect, zoom 1 =
## the largest window of the screen's aspect that fits in the texture ("cover"), smaller = closer.
## The cameras were composed for a 2.39:1 frame, where zoom = window width; at 16:9 the same zoom shows the same
## width and more height, at 4:3 the sides are cropped.

## Music: public-domain recordings, cut to fit the cinematic (assets/intro/music/; the menu plays the whole pieces). MUSIC_FILE carries the quiet first half (forest, beasts,
## Virgil), MUSIC_FILE_2 takes over under the gate and swells through Charon into the title. Paths starting with res://
## are absolute, others are relative to res://assets/intro/.
const MUSIC_FILE := "res://assets/intro/music/score_a.ogg"
const MUSIC_FILE_2 := "res://assets/intro/music/score_b.ogg"
## Sounds that the game already ships in assets/audio/sfx/ are used from there.
const SFX_DIR := "res://assets/audio/sfx/"
## Music bed level (dB on the Music bus; the recordings are mastered to -16 LUFS) and how far it sinks under narration.
const MUSIC_DB := -6.0
const DUCK_DB := -8.0

const DIR := "res://assets/intro/"
## Cards, inscription and title keep the size they had in the 2.39:1 frame: their reference height is
## min(screen height, screen width / TEXT_ASPECT).
const TEXT_ASPECT := 2.39
const TEX_ASPECT := 2560.0 / 1408.0
const CROSSFADE := 1.4

## The story card. Plain modern English, not Longfellow: this is the game's own premise.
const STORY_CARD: Array[String] = [
	"Lost in a dark wood, a pilgrim must go down through Hell.",
	"Its souls and its guardians will stand against him, card by card.",
	"At the river Acheron, Charon is waiting.",
]
## Seconds between the story lines and from the start of the story shot to the first line.
const STORY_FIRST := 1.6
const STORY_STEP := 3.0

## Gate inscription: four of the nine lines of Canto III (Longfellow, upper-cased as carved). The narration
## (voice/v_c_gate.ogg) is the LibriVox reading cut down to the same four lines; INSCRIPTION_TIMES holds [start, end] of
## each line in seconds from the start of that file; the carving reveals each line letter by letter over that span.
const INSCRIPTION: Array[String] = [
	"THROUGH ME THE WAY IS TO THE CITY DOLENT;",
	"THROUGH ME THE WAY IS TO ETERNAL DOLE;",
	"THROUGH ME THE WAY AMONG THE PEOPLE LOST.",
	"ALL HOPE ABANDON, YE WHO ENTER IN!",
]
const INSCRIPTION_TIMES: Array[Vector2] = [
	Vector2(0.0, 3.0), Vector2(3.9, 6.6), Vector2(7.7, 10.5), Vector2(11.5, 14.3),
]
const TITLE := "DANTE'S INFERNO"
const TITLE_SUB := "THE CARD GAME"
## Seconds into the title shot: the sting starts the ignition of the letters, the thunder strikes the vermilion glint.
const TITLE_THUNDER := 5.2
const CHAPTER := "INFERNO  ·  CANTO I"


## The inscription in the shown language (in Italian, Dante's own lines; the carving keeps INSCRIPTION_TIMES).
static func inscription() -> Array[String]:
	var out: Array[String] = []
	for l in INSCRIPTION:
		out.append(Loc.t(l))
	return out


static func path(file: String) -> String:
	return file if file.begins_with("res://") else DIR + file


## A shot camera: centre (cx, cy) in texture uv and zoom (1 = cover the screen with the whole texture width or height).
static func win_c(cx: float, cy: float, zoom: float) -> Vector3:
	return Vector3(cx, cy, zoom)


## Visible uv rect of the texture for camera `cam` on a screen of aspect `screen_aspect` (cover, never outside 0..1).
## `keep` (uv x0, x1; the shot's "keep") is the horizontal span of the subjects: on screens narrower than
## 16:9 (16:10, 4:3) the window slides to keep it in view, or centres on it when it does not fit. Wider screens keep
## the composed camera exactly.
static func window(cam: Vector3, screen_aspect: float, keep := Vector2(-1.0, -1.0)) -> Rect2:
	var bw := 1.0
	var bh := TEX_ASPECT / screen_aspect
	if bh > 1.0:  # screen narrower than the texture: full height, sides cropped
		bh = 1.0
		bw = screen_aspect / TEX_ASPECT
	var w := bw * cam.z
	var h := bh * cam.z
	var x := cam.x - w * 0.5
	if keep.x >= 0.0 and screen_aspect < 1.75:
		if keep.y - keep.x <= w:
			x = clampf(x, keep.y - w, keep.x)
		else:
			x = (keep.x + keep.y - w) * 0.5
	return Rect2(clampf(x, 0.0, 1.0 - w), clampf(cam.y - h * 0.5, 0.0, 1.0 - h), w, h)


## Text reference height (cards, inscription, title, subtitles): the 2.39:1 frame height on 16:9 and wider
## screens, a similar share of the height on narrower ones.
static func text_height(w: float, h: float) -> float:
	return minf(h, maxf(w / TEXT_ASPECT, h * 0.744))


## The opening: Inferno I 1-3 in the dark wood, the beasts that bar the way, Virgil's offer to guide him, the Gate of
## Hell, Charon on the Acheron (the first opponent), then the story card and the title. About 98 s.
## "keep" (uv x0, x1) = subjects that stay in view on screens narrower than 16:9.
static func build() -> Dictionary:
	var shots: Array[Dictionary] = [
		{"id": "open", "kind": "black", "dur": 4.5},
		{"id": "forest", "kind": "video", "dur": 17.0, "plate": "plates/s2_forest.jpg",
			"video": "video/s2_forest.ogv", "cam_from": win_c(0.5, 0.5, 0.96), "cam_to": win_c(0.47, 0.54, 0.76),
			"keep": Vector2(0.42, 0.6), "mist": 0.55},
		{"id": "panther", "kind": "video", "dur": 6.5, "plate": "plates/s3a_panther.jpg",
			"video": "video/s3a_panther.ogv", "cam_from": win_c(0.5, 0.55, 0.95), "cam_to": win_c(0.36, 0.55, 0.62),
			"keep": Vector2(0.2, 0.55), "mist": 0.2},
		{"id": "lion", "kind": "video", "dur": 6.0, "plate": "plates/s3b_lion.jpg",
			"video": "video/s3b_lion.ogv", "cam_from": win_c(0.55, 0.4, 0.98), "cam_to": win_c(0.74, 0.34, 0.56),
			"keep": Vector2(0.55, 0.9), "mist": 0.45},
		{"id": "virgil", "kind": "video", "dur": 14.0, "plate": "plates/s4_virgil.jpg",
			"video": "video/s4_virgil.ogv", "cam_from": win_c(0.55, 0.35, 0.92), "cam_to": win_c(0.58, 0.32, 0.66),
			"keep": Vector2(0.4, 0.75), "mist": 0.5},
		{"id": "gate", "kind": "video", "dur": 23.0, "plate": "plates/s5_gate.jpg",
			"video": "video/s5_gate.ogv", "cam_from": win_c(0.5, 0.5, 1.0), "cam_to": win_c(0.45, 0.42, 0.74),
			"mist": 0.4, "ember": 0.25, "flicker": 0.5},
		{"id": "charon", "kind": "video", "dur": 15.0, "plate": "plates/s6_charon.jpg",
			"video": "video/s6_charon.ogv", "cam_from": win_c(0.5, 0.35, 1.0), "cam_to": win_c(0.6, 0.3, 0.72),
			"mist": 0.2, "ember": 0.2, "flicker": 0.2, "keep": Vector2(0.32, 0.74),
			"eyes": {"a": Vector2(0.5715, 0.279), "b": Vector2(0.5925, 0.277), "r": 0.0034, "at": 3.2}},
		{"id": "story", "kind": "black", "dur": STORY_FIRST + STORY_STEP * 3.0 + 0.4},
		{"id": "title", "kind": "black", "dur": 9.0},
	]
	var t := 0.0
	for s in shots:
		s["start"] = t
		t += float(s["dur"]) - (CROSSFADE if s["kind"] != "black" else 0.0)
	var total := 0.0
	for s in shots:
		total = maxf(total, float(s["start"]) + float(s["dur"]))

	# Narration: LibriVox readings of Longfellow's translation (public domain). The lines are exact Longfellow and
	# double as subtitles.
	var voice := {
		"forest": {"at": 2.5, "file": "voice/v_a_forest.ogg", "lines": [
			"Midway upon the journey of our life",
			"I found myself within a forest dark,",
			"For the straightforward pathway had been lost."]},
		"virgil": {"at": 2.0, "file": "voice/v_b_virgil.ogg", "lines": [
			"Therefore I think and judge it for thy best",
			"Thou follow me, and I will be thy guide,",
			"And lead thee hence through the eternal place,"]},
		"gate": {"at": 2.5, "file": "voice/v_c_gate.ogg", "inscription": true, "lines": [
			"Through me the way is to the city dolent;",
			"Through me the way is to eternal dole;",
			"Through me the way among the people lost.",
			"All hope abandon, ye who enter in!"]},
		"charon": {"at": 2.5, "file": "voice/v_d_charon.ogg", "lines": [
			"Woe unto you, ye souls depraved!",
			"Hope nevermore to look upon the heavens;"]},
	}
	var voices: Array[Dictionary] = []
	for k in voice:
		var v: Dictionary = voice[k].duplicate()
		var shot_id: String = v.get("shot", k)
		v["id"] = k
		v["shot"] = shot_id
		v["t"] = float(shot_by_id(shots, shot_id)["start"]) + float(v["at"])
		voices.append(v)

	# Sound cues (music, ambience, one-shots). `shot` + `at` -> absolute time `t`; `dur` (s after t) starts the fade-out,
	# or `until` = [shot id, offset] computes it. `duck`: the cue sinks DUCK_DB while narration is speaking.
	var cues_rel: Array[Dictionary] = [
		{"shot": "open", "at": 0.0, "file": MUSIC_FILE, "bus": "Music", "db": MUSIC_DB, "fade_in": 4.0,
			"until": ["gate", 1.0], "fade_out": 6.0, "id": "music", "duck": true},
		{"shot": "virgil", "at": 9.0, "file": MUSIC_FILE_2, "bus": "Music", "db": MUSIC_DB, "fade_in": 6.0,
			"until": ["title", 3.0], "fade_out": 6.0, "id": "music2", "duck": true},
		{"shot": "open", "at": 0.6, "file": SFX_DIR + "bell_funeral.ogg", "bus": "SFX", "db": -8.0, "id": "bell"},
		{"shot": "open", "at": 0.0, "file": "audio/wind_loop.ogg", "bus": "Ambience", "db": -10.0, "fade_in": 4.0,
			"until": ["charon", 1.0], "fade_out": 4.0, "loop": true, "id": "wind", "duck": true},
		{"shot": "panther", "at": 0.9, "file": "audio/growl_beast.ogg", "bus": "SFX", "db": -6.0, "id": "growl"},
		{"shot": "lion", "at": 0.4, "file": "audio/roar_lion.ogg", "bus": "SFX", "db": -5.0, "id": "roar"},
		{"shot": "gate", "at": 2.0, "file": "audio/bell_ambient.ogg", "bus": "SFX", "db": -14.0, "id": "bell_gate", "duck": true},
		{"shot": "charon", "at": 0.0, "file": SFX_DIR + "water_loop.ogg", "bus": "Ambience", "db": -12.0, "fade_in": 2.5,
			"dur": 12.0, "fade_out": 3.0, "loop": true, "id": "water", "duck": true},
		{"shot": "title", "at": 1.0, "file": SFX_DIR + "title_sting.ogg", "bus": "Music", "db": -4.0, "id": "sting"},
		{"shot": "title", "at": TITLE_THUNDER, "file": SFX_DIR + "thunder.ogg", "bus": "SFX", "db": -2.0, "id": "thunder"},
	]
	var cues: Array[Dictionary] = []
	for c in cues_rel:
		var cc := c.duplicate()
		var st := float(shot_by_id(shots, c["shot"])["start"])
		cc["t"] = st + float(c["at"])
		if c.has("until"):
			cc["dur"] = float(shot_by_id(shots, c["until"][0])["start"]) + float(c["until"][1]) - float(cc["t"])
		cues.append(cc)
	# The player fires cues in list order: keep them sorted by time.
	cues.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))
	return {"shots": shots, "voices": voices, "cues": cues, "total": total}


static func shot_by_id(shots: Array, id: String) -> Dictionary:
	for s in shots:
		if s["id"] == id:
			return s
	return {}


## Every res:// file the timeline references.
static func files(tl: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for s in tl["shots"]:
		for k in ["plate", "video"]:
			if s.has(k):
				out.append(path(String(s[k])))
	for v in tl["voices"]:
		out.append(DIR + String(v["file"]))
	for c in tl["cues"]:
		out.append(path(String(c["file"])))
	return out
