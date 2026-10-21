class_name LocalData
extends RefCounted
## The game data for the local engine: client/data/game.json, written by the
## server's `npm run fixtures` exactly as the server reads data/ (defaults
## filled in), so the app plays by the same numbers offline.

const PATH := "res://data/game.json"

static var _cache: Dictionary = {}


## The data, keyed like the server's GameData (buildings, terrain, units…).
static func load_data() -> Dictionary:
	if _cache.is_empty():
		var text := FileAccess.get_file_as_string(PATH)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			_cache = parsed
		else:
			push_error("Local game data missing or broken: %s" % PATH)
	return _cache
