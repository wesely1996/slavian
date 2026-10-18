class_name Terrain
extends RefCounted
## Terrain types and their placeholder look. Colours are a muted earth
## palette (see PLAN.md §11.7); final art replaces them later.

enum Type {
	PLAINS, FOREST, HILLS, MOUNTAIN, SWAMP, LAKE, HOLY_CITY,
	OCEAN, DARK_FOREST, ICE, STEPPE, HALLOWED,
}

const INFO := {
	Type.PLAINS: {"name": "Plains", "color": Color("#c2b86f")},
	Type.FOREST: {"name": "Forest", "color": Color("#4f6b3a")},
	Type.HILLS: {"name": "Hills", "color": Color("#9a8455")},
	Type.MOUNTAIN: {"name": "Mountain", "color": Color("#6e675f")},
	Type.SWAMP: {"name": "Swamp", "color": Color("#5d6a4f")},
	Type.LAKE: {"name": "Lake", "color": Color("#4f7c8c")},
	Type.HOLY_CITY: {"name": "Holy City", "color": Color("#e8d9a8")},
	Type.OCEAN: {"name": "Ocean", "color": Color("#2f4f66")},
	Type.DARK_FOREST: {"name": "Dark Forest", "color": Color("#26372a")},
	Type.ICE: {"name": "Ice", "color": Color("#d6e2e6")},
	Type.STEPPE: {"name": "Steppe", "color": Color("#b59a62")},
	Type.HALLOWED: {"name": "Hallowed Lands", "color": Color("#a58d86")},
}

const EDGE_TYPES: Array[Type] = [Type.OCEAN, Type.DARK_FOREST, Type.ICE, Type.STEPPE, Type.HALLOWED]


static func display_name(type: Type) -> String:
	return INFO[type]["name"]


static func color(type: Type) -> Color:
	return INFO[type]["color"]


static func is_edge(type: Type) -> bool:
	return type in EDGE_TYPES
