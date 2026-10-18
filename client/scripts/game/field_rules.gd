class_name FieldRules
extends RefCounted
## The ground for field battles (see server/src/sim/field.ts and
## scheduler/field.ts): ambush cover, choke points and forts.


static func passable(data: Dictionary, terrain: Dictionary, cell: Vector2i) -> bool:
	var id: Variant = terrain.get(cell)
	return id != null and data.terrain.terrain.get(id, {}).get("moveCost") != null


static func is_choke_point(data: Dictionary, terrain: Dictionary, cell: Vector2i) -> bool:
	if not passable(data, terrain, cell):
		return false
	var blocked := 0
	for n in HexMath.neighbors(cell):
		if not passable(data, terrain, n):
			blocked += 1
	return blocked >= int(data.field.choke.minBlockedNeighbors)


static func is_cover(data: Dictionary, terrain_id: String) -> bool:
	return terrain_id in data.field.ambush.terrain


## What the hex gives an army holding it, one line each.
static func ground(data: Dictionary, terrain: Dictionary, cell: Vector2i, fort: Dictionary, world_speed: float) -> PackedStringArray:
	var lines := PackedStringArray()
	var id: String = terrain.get(cell, "")
	if is_cover(data, id):
		var prep := float(data.field.ambush.prepMinutes) * 60.0 / world_speed
		lines.append("Ambush ground: +%d%% attack in the first round if your army is here %s before the horde." % [
			roundi(float(data.field.ambush.bonus) * 100.0), TimeUtil.format_duration(prep)])
	if is_choke_point(data, terrain, cell):
		lines.append("Choke point: the horde strikes at %d%%; Hold the Line adds +%d%% defense." % [
			roundi(float(data.field.choke.attackerFactor) * 100.0), roundi(float(data.field.choke.holdTheLineDefense) * 100.0)])
	if not fort.is_empty():
		var bonus := roundi(float(data.field.fort.defenseBonus) * 100.0)
		lines.append("Fort: +%d%% defense." % bonus if fort.status == "standing" else "Fort being built (+%d%% defense when done)." % bonus)
	if lines.is_empty():
		lines.append("Open ground: no help from the land.")
	return lines


## Why `village` can't build a fort on `cell` ("" if it can).
static func fort_problem(data: Dictionary, village: Dictionary, cell: Vector2i, terrain_id: String, taken: bool) -> String:
	var range_ := int(data.field.fort.range)
	var distance := HexMath.distance(cell, Vector2i(int(village.q), int(village.r)))
	if distance == 0 or distance > range_:
		return "Forts go within %d hexes of %s." % [range_, village.name]
	if terrain_id == "holy_city" or data.terrain.terrain.get(terrain_id, {}).get("moveCost") == null:
		return "No fort can stand here."
	if taken:
		return "Something already stands here."
	return ""
