class_name RiverText
extends RefCounted
## Rivers along hex edges and their bridges (server sim/land.ts, db/rivers.ts).
## Game.rivers holds [aq, ar, bq, br, crossing], crossing being "none",
## "building" or "standing".


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
static func bridge_problem(data: Dictionary, home: Vector2i, a: Vector2i, b: Vector2i) -> String:
	var range_ := int(data.field.bridge.range)
	if mini(HexMath.distance(a, home), HexMath.distance(b, home)) > range_:
		return "Bridges go within %d hexes of your village" % range_
	return ""


## Roads between neighbouring hexes: [aq, ar, bq, br, status] in Game.roads.
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


## Why no road can be built from a to b from `home`, or "".
static func road_problem(data: Dictionary, terrain: Dictionary, rivers: Array, home: Vector2i, a: Vector2i, b: Vector2i) -> String:
	var range_ := int(data.field.road.range)
	if mini(HexMath.distance(a, home), HexMath.distance(b, home)) > range_:
		return "Roads go within %d hexes of your village" % range_
	for end in [a, b]:
		var type: String = terrain.get(end, "")
		if type == "" or data.terrain.terrain.get(type, {}).get("moveCost") == null:
			return "No road can run there"
	for e in edges_at(rivers, a):
		if e.other == b and e.crossing != "standing":
			return "A river lies between; build a bridge first"
	return ""
