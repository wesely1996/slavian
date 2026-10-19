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
