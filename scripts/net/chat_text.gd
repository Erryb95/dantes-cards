class_name ChatText
extends RefCounted
## Chat text from the network is shown as plain text only: control and direction-override characters removed (line
## breaks and tabs become spaces), BBCode-like tags stripped (and never parsed: chat uses plain Labels), trimmed to
## MAX_LEN characters.

const MAX_LEN := 120
const _INVISIBLE := [0x200B, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069]

static var _tags: RegEx


static func clean(raw: String) -> String:
	var out := ""
	raw = raw.left(MAX_LEN * 8) # a flood from a modified client is cut before the per-character work
	for i in raw.length():
		var c := raw.unicode_at(i)
		if c < 32 or c == 127 or (c >= 0x80 and c < 0xA0) or c in _INVISIBLE:
			if c in [9, 10, 13]:
				out += " "
			continue
		out += char(c)
	if _tags == null:
		_tags = RegEx.create_from_string("\\[/?[A-Za-z][A-Za-z0-9_]*(=[^\\[\\]]{0,40})?\\]")
	out = _tags.sub(out, "", true)
	return out.strip_edges().left(MAX_LEN)
