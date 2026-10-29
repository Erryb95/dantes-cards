# Translations

English is the source language: every text in the code and in `data/*.json` is written in English. Each other
language has a folder here (`it/` for Italian) read by `scripts/core/loc.gd` when the player picks it in Options
(or when the device is set to it).

- `strings_*.json`: `{"English text": "translation"}`. UI text, looked up whole. A template keeps every `%d`, `%s`
  or `%.1f` of the English, in the same order (a test checks). Keys starting with `_` are notes.
- `data_*.json`: `{"cards": {id: {...}}, "heroes": {...}, "decks": {...}, "arenas": {...}, "lessons": {...}}`. The
  translated text fields of a data entry, laid over the English entry by id. Only text fields that the English entry
  has are used; numbers, ids and effects always come from the English data. An array is used only when it has as
  many items as the English one.
- `GLOSSARY.md`: the words every translator must use the same way (keywords, game terms, names).

Code rules:
- `UI.label`, `UI.button`, `UI.banner`, `UI.name_field` (placeholder) and everything built on them translate their text.
- Any other text a player reads goes through `Loc.t(...)`: a `.text =` set directly, `draw_string`, a tooltip.
- A template is translated before it is filled in: `Loc.t("%d cards left") % n`, never `Loc.t("%d cards left" % n)`.
  Joined text is translated piece by piece, or better turned into one template.
- Ids, node names, file names and save keys are never translated.

Checking: `Godot --path . res://tests/screen_audit.tscn --resolution 1920x1080 -- --out=<dir> --what=<mode>
--lang=it` shoots a screen in Italian and writes the texts it showed with no translation to `<dir>/i18n_missing.txt`.
