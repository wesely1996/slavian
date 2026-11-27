class_name EdgeWallText
## Walls along hex edges as the client sees them (map.walls rows: [aq, ar,
## bq, br, kind, status, tier, ownerAccountId, completesAt]; data/field.json
## edgeWalls): which stand where, what the next tier costs, and the
## gatehouse a fort has merged with.


## The walls on the edges of `cell`: {other hex: {kind, status, tier, ownerAccountId, completesAt}}.
static func walls_at(walls: Array, cell: Vector2i) -> Dictionary:
	var out := {}
	for w in walls:
		var a := Vector2i(int(w[0]), int(w[1]))
		var b := Vector2i(int(w[2]), int(w[3]))
		if a != cell and b != cell:
			continue
		out[b if a == cell else a] = entry(w)
	return out


static func entry(w: Array) -> Dictionary:
	return {"kind": String(w[4]), "status": String(w[5]), "tier": int(w[6]), "ownerAccountId": w[7], "completesAt": w[8]}


## "Palisade", "Timber-and-stone wall", "Stone wall".
static func tier_name(data: Dictionary, tier: int) -> String:
	var tiers: Array = data.field.edgeWalls.tiers
	return UI.t(String(tiers[clampi(tier, 1, tiers.size()) - 1].name))


static func kind_name(data: Dictionary, kind: String, tier: int) -> String:
	if kind == "gate":
		return UI.t("Gatehouse (%s)") % tier_name(data, tier).to_lower()
	return tier_name(data, tier)


## What a wall (or gatehouse) at `tier` costs and takes: {cost, seconds}.
static func tier_cost(data: Dictionary, kind: String, tier: int) -> Dictionary:
	return {"cost": LocalEdgeWalls.tier_cost(data, kind, tier), "seconds": LocalEdgeWalls.tier_seconds(data, kind, tier)}


## Why no wall can go between a and b from `home` ("" if one can).
static func problem(data: Dictionary, terrain: Dictionary, rivers: Array, home: Vector2i, a: Vector2i, b: Vector2i, in_zone := false) -> String:
	var range_ := int(data.field.edgeWalls.range)
	if not in_zone and mini(HexMath.distance(a, home), HexMath.distance(b, home)) > range_:
		return UI.t("Walls go within %d hexes of your village") % range_
	for end in [a, b]:
		var type: String = terrain.get(end, "")
		var def: Dictionary = data.terrain.terrain.get(type, {})
		if type == "" or def.get("enemy", false) or def.get("moveCost") == null:
			return UI.t("No wall can stand there")
	for e in RiverText.edges_at(rivers, a):
		if e.other == b and e.crossing != "standing":
			return UI.t("A river already guards that edge")
	return ""


## The gatehouse a fort has merged with: its owner's, standing on an edge
## of its hex (the strongest), as the fort's outermost wall ring
## (LocalEdgeWalls.fort_gatehouse). {} for none; else {other, tier, ...}.
static func fort_gatehouse(walls: Array, fort: Dictionary) -> Dictionary:
	if fort.get("kind", "fort") != "fort" or fort.get("status") != "standing":
		return {}
	var cell := Vector2i(int(fort.q), int(fort.r))
	var best := {}
	var around := walls_at(walls, cell)
	for other in around:
		var w: Dictionary = around[other]
		if w.kind == "gate" and w.status != "building" and w.ownerAccountId == fort.get("ownerAccountId") and (best.is_empty() or int(w.tier) > int(best.tier)):
			best = w.duplicate()
			best.other = other
	return best


## How long a horde takes to tear it down, in game hours.
static func break_hours(data: Dictionary, kind: String, tier: int) -> float:
	return LocalEdgeWalls.break_hours(data, {"gate": kind == "gate", "tier": tier})
