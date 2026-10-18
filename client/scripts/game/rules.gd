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
