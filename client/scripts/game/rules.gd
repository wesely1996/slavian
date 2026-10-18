class_name Rules
extends RefCounted
## Display-side copies of the building formulas in server/src/sim/village.ts.
## The server decides; these only preview costs and times.


static func level_cost(def: Dictionary, target_level: int) -> Dictionary:
	var factor := pow(def.costGrowth, target_level - 1)
	var cost := {}
	for kind in Ledger.KINDS:
		cost[kind] = roundi(def.cost[kind] * factor)
	return cost


static func build_seconds(def: Dictionary, target_level: int, world_speed: float) -> float:
	return def.buildSeconds * pow(def.timeGrowth, target_level - 1) / world_speed


## Level the building will reach once everything already queued completes.
static func planned_level(village: Dictionary, building: String) -> int:
	var level := int(village.levels.get(building, 0))
	for item in village.queue:
		if item.building == building:
			level = int(item.targetLevel)
	return level


## Units of a training batch finished by `at` (server/src/sim/training.ts).
static func finished_by(batch: Dictionary, at_unix: float) -> int:
	var elapsed_ms := (at_unix - TimeUtil.parse_iso(batch.startsAt)) * 1000.0
	return clampi(floori(elapsed_ms / float(batch.perUnitMs)), 0, int(batch.count))


## Units at home now: the settled garrison plus everything trained since.
static func garrison_at(village: Dictionary, at_unix: float) -> Dictionary:
	var units := {}
	for unit in village.get("garrison", {}):
		units[unit] = int(village.garrison[unit])
	for batch in village.get("training", []):
		var done := finished_by(batch, at_unix)
		if done > 0:
			units[batch.unit] = int(units.get(batch.unit, 0)) + done
	return units


static func unit_cost(def: Dictionary, count: int) -> Dictionary:
	var cost := {}
	for kind in Ledger.KINDS:
		cost[kind] = int(def.cost[kind]) * count
	return cost
