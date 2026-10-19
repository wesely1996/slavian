class_name Art
extends RefCounted
## Art by id. client/art/art.json maps each id ("terrain/forest",
## "settlement/village_3", "unit/archer") to a file; point an id at your own
## file (SVG or PNG) to replace that piece of art (docs/art-style.md).
## Missing art gives null, and callers draw their placeholder instead.

const MANIFEST := "res://art/art.json"

static var _paths: Dictionary = {}
static var _cache: Dictionary = {}


static func paths() -> Dictionary:
	if _paths.is_empty():
		var text := FileAccess.get_file_as_string(MANIFEST)
		var parsed: Variant = JSON.parse_string(text) if text != "" else null
		_paths = parsed if parsed is Dictionary else {}
	return _paths


static func ids() -> Array:
	var out := paths().keys()
	out.sort()
	return out


static func path(id: String) -> String:
	return String(paths().get(id, ""))


static func has(id: String) -> bool:
	return path(id) != "" and ResourceLoader.exists(path(id))


static func texture(id: String) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var file := path(id)
	var tex: Texture2D = null
	if file != "" and ResourceLoader.exists(file):
		tex = load(file) as Texture2D
	_cache[id] = tex
	return tex


## The look of a settlement by its Elder's Hall level (five stages).
static func settlement_id(hall_level: int) -> String:
	return "settlement/village_%d" % clampi(ceili(maxi(hall_level, 1) / 2.0), 1, 5)
