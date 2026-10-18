class_name Terrain
extends RefCounted
## Placeholder look for terrain ids from data/terrain.json. Colours are a
## muted earth palette (PLAN.md §11.7); final art replaces them later.

const COLORS := {
	"plains": Color("#c2b86f"),
	"forest": Color("#4f6b3a"),
	"hills": Color("#9a8455"),
	"mountain": Color("#6e675f"),
	"swamp": Color("#5d6a4f"),
	"lake": Color("#4f7c8c"),
	"holy_city": Color("#e8d9a8"),
	"ocean": Color("#2f4f66"),
	"dark_forest": Color("#26372a"),
	"ice": Color("#d6e2e6"),
	"steppe": Color("#b59a62"),
	"hallowed": Color("#a58d86"),
}
const UNKNOWN_COLOR := Color("#ff00ff")


static func color(id: String) -> Color:
	return COLORS.get(id, UNKNOWN_COLOR)


## Name from the server's terrain data when loaded, else derived from the id.
static func display_name(id: String, data: Dictionary = {}) -> String:
	var defs: Dictionary = data.get("terrain", {}).get("terrain", {})
	if defs.has(id):
		return defs[id].name
	return id.capitalize()
