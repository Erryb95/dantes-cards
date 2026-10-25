class_name UiSkin
## Optional painted UI / VFX textures (assets/ui/*.png|jpg, assets/vfx/*.png|jpg). Every caller keeps a code-drawn
## fallback, so the game runs with any subset of the art present.

static var _cache := {}


static func tex(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	var t: Texture2D = null
	for dir in ["res://assets/ui/", "res://assets/vfx/"]:
		for ext in [".png", ".jpg"]:
			if t == null and ResourceLoader.exists(dir + name + ext):
				t = load(dir + name + ext)
	_cache[name] = t
	return t


static func has(name: String) -> bool:
	return tex(name) != null


## A TextureRect filling `size` at `pos` (top-left), ignoring the mouse.
static func rect(name: String, size: Vector2, pos: Vector2 = Vector2.ZERO) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex(name)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.size = size
	r.position = pos
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.use_parent_material = true
	return r


## A centred sprite scaled to `size` pixels.
static func sprite(name: String, size: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex(name)
	if s.texture != null:
		s.scale = size / s.texture.get_size()
	s.use_parent_material = true
	return s
