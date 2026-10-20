class_name Terrain
extends RefCounted
## How terrain ids from data/terrain.json look on the map: a natural ground
## colour and a height (0 water, 1 peaks) the ground shader lights as relief
## (MapGround). Features (trees, peaks) are drawn over it by MapFeatures.

const COLORS := {
	"plains": Color("#87924f"),
	"forest": Color("#56683a"),
	"hills": Color("#8e8657"),
	"mountain": Color("#7b766c"),
	"swamp": Color("#5b6447"),
	"lake": Color("#3d6f86"),
	"holy_city": Color("#a69a72"),
	"ocean": Color("#2c5571"),
	"dark_forest": Color("#33412e"),
	"ice": Color("#c4ced2"),
	"steppe": Color("#ad9d67"),
	"hallowed": Color("#8d8174"),
}
const HEIGHTS := {
	"ocean": 0.0,
	"lake": 0.02,
	"swamp": 0.16,
	"plains": 0.25,
	"steppe": 0.28,
	"holy_city": 0.3,
	"forest": 0.32,
	"dark_forest": 0.36,
	"hallowed": 0.38,
	"ice": 0.5,
	"hills": 0.6,
	"mountain": 1.0,
}
const UNKNOWN_COLOR := Color("#ff00ff")


static func color(id: String) -> Color:
	return COLORS.get(id, UNKNOWN_COLOR)


static func height(id: String) -> float:
	return HEIGHTS.get(id, 0.3)


static func is_water(id: String) -> bool:
	return id == "lake" or id == "ocean"


## Name from the server's terrain data when loaded, else derived from the id.
static func display_name(id: String, data: Dictionary = {}) -> String:
	var defs: Dictionary = data.get("terrain", {}).get("terrain", {})
	if defs.has(id):
		return UI.t(defs[id].name)
	return id.capitalize()
