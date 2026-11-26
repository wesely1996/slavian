class_name Terrain
extends RefCounted
## How terrain ids from data/terrain.json look on the map: a natural ground
## colour and a height (0 water, 1 peaks) the ground shader lights as relief
## (MapGround). Features (trees, peaks) are drawn over it by MapFeatures.

const COLORS := {
	"plains": Color("#87924f"),
	"forest": Color("#56683a"),
	"hills": Color("#8e8657"),
	"wooded_hills": Color("#6f7646"),
	"mountain": Color("#7b766c"),
	"swamp": Color("#5b6447"),
	"lake": Color("#3d6f86"),
	"holy_city": Color("#a69a72"),
	"ocean": Color("#2c5571"),
	"dark_forest": Color("#33412e"),
	"ice": Color("#c4ced2"),
	"steppe": Color("#ad9d67"),
	"hallowed": Color("#8d8174"),
	# A mountain city's hex: dressed stone in the mountain.
	"mountain_city": Color("#8f8778"),
	# The enemy lands beyond the edge (enemy-lands.json).
	"frozen_bog": Color("#6f7f80"),
	"barrow_field": Color("#6d6a58"),
	"salt_flat": Color("#cfc6a8"),
	"kurgan_ridge": Color("#9a8458"),
	"vineyard": Color("#7c6a4a"),
	"olive_grove": Color("#77804f"),
	"mill_meadow": Color("#93a05c"),
	"abbey_orchard": Color("#6c7c45"),
	"rift": Color("#24201f"),
	# Enemy lands not yet seen.
	"fog": Color("#3a3f46"),
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
	"wooded_hills": 0.62,
	"mountain": 1.0,
	"mountain_city": 0.85,
	"frozen_bog": 0.2,
	"barrow_field": 0.45,
	"salt_flat": 0.26,
	"kurgan_ridge": 0.55,
	"vineyard": 0.5,
	"olive_grove": 0.36,
	"mill_meadow": 0.27,
	"abbey_orchard": 0.33,
	"rift": 0.05,
	"fog": 0.3,
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
