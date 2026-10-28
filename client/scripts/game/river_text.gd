class_name RiverText
extends RefCounted
## Rivers along hex edges and their bridges (server sim/land.ts, db/rivers.ts).
## Game.rivers holds [aq, ar, bq, br, crossing, size], crossing being "none",
## "building" or "standing", and size 1 from a river's source, +1 for each
## river that joined it above.


## Terrain a river flows into and never runs along (server mapgen WATER).
const WATER := ["lake", "ocean"]


## How big the river is along an edge (1 when the server didn't say).
static func size_of(edge: Array) -> int:
	return int(edge[5]) if edge.size() > 5 else 1


## The river edges along `cell`: [{"other": Vector2i, "crossing": String}].
static func edges_at(rivers: Array, cell: Vector2i) -> Array:
	var out := []
	for e in rivers:
		var a := Vector2i(int(e[0]), int(e[1]))
		var b := Vector2i(int(e[2]), int(e[3]))
		if a == cell:
			out.append({"other": b, "crossing": String(e[4])})
		elif b == cell:
			out.append({"other": a, "crossing": String(e[4])})
	return out


## Index into HexMath.DIRECTIONS of the step from a to b (-1 if not neighbours).
static func direction(a: Vector2i, b: Vector2i) -> int:
	return HexMath.DIRECTIONS.find(b - a)


## Why a bridge can't be built over the edge a-b from `home`, or "".
static func bridge_problem(data: Dictionary, home: Vector2i, a: Vector2i, b: Vector2i, terrain := {}) -> String:
	# Rivers on older maps could run along a lake: no bridge leads onto water.
	if String(terrain.get(a, "")) in WATER or String(terrain.get(b, "")) in WATER:
		return UI.t("A bridge needs land on both banks")
	var range_ := int(data.field.bridge.range)
	if mini(HexMath.distance(a, home), HexMath.distance(b, home)) > range_:
		return UI.t("Bridges go within %d hexes of your village") % range_
	return ""


## Roads between neighbouring hexes: [aq, ar, bq, br, status, level] in
## Game.roads (status "building", "standing" or "upgrading": standing at
## `level` while it is improved to the next).
## The neighbours of `cell` a road runs to: {Vector2i: status}.
static func roads_at(roads: Array, cell: Vector2i) -> Dictionary:
	var out := {}
	for e in roads:
		var a := Vector2i(int(e[0]), int(e[1]))
		var b := Vector2i(int(e[2]), int(e[3]))
		if a == cell:
			out[b] = String(e[4])
		elif b == cell:
			out[a] = String(e[4])
	return out


## The level of each road from `cell`: {Vector2i: level} (1 for roads
## from before road levels).
static func road_levels_at(roads: Array, cell: Vector2i) -> Dictionary:
	var out := {}
	for e in roads:
		var a := Vector2i(int(e[0]), int(e[1]))
		var b := Vector2i(int(e[2]), int(e[3]))
		var level := int(e[5]) if e.size() > 5 else 1
		if a == cell:
			out[b] = level
		elif b == cell:
			out[a] = level
	return out


## The share of the march a road of each level takes, as "50% · 35% · 25%".
static func road_speeds(data: Dictionary) -> String:
	var parts := PackedStringArray()
	for level in data.field.road.levels:
		parts.append("%d%%" % roundi(float(level.factor) * 100.0))
	return " · ".join(parts)


## Why no road can be built from a to b from `home`, or "".
static func road_problem(data: Dictionary, terrain: Dictionary, rivers: Array, home: Vector2i, a: Vector2i, b: Vector2i) -> String:
	var range_ := int(data.field.road.range)
	if mini(HexMath.distance(a, home), HexMath.distance(b, home)) > range_:
		return UI.t("Roads go within %d hexes of your village") % range_
	for end in [a, b]:
		var type: String = terrain.get(end, "")
		if type == "" or data.terrain.terrain.get(type, {}).get("moveCost") == null:
			return UI.t("No road can run there")
	for e in edges_at(rivers, a):
		if e.other == b and e.crossing != "standing":
			return UI.t("A river lies between; build a bridge first")
	return ""
