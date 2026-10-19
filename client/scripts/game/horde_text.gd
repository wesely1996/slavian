class_name HordeText
extends RefCounted
## Words and numbers for the horde AI (see server/src/sim/horde.ts and
## data/horde.json): raid or raze, ruins, camps and the Holy City.


## What rebuilding a ruin costs: a share of everything that stood.
static func rebuild_cost(data: Dictionary, plots: Dictionary) -> Dictionary:
	var sum := {"wood": 0.0, "stone": 0.0, "grain": 0.0, "iron": 0.0}
	for id in plots:
		var plot: Dictionary = plots[id]
		var building: Variant = plot.get("building")
		if building == null or not data.buildings.buildings.has(building):
			continue
		var def: Dictionary = data.buildings.buildings[building]
		for level in range(1, int(plot.level) + 1):
			var cost := Rules.level_cost(def, level)
			for kind in sum:
				sum[kind] += float(cost.get(kind, 0))
	var share := float(data.horde.ruins.rebuildCostShare)
	var result := {}
	for kind in sum:
		result[kind] = roundi(sum[kind] * share)
	return result


## "Razed: its faction burns what it takes, nothing nearby can stop it."
static func decision(battle: Dictionary) -> String:
	var choice: Variant = battle.get("decision")
	if not choice is Dictionary:
		return ""
	var reasons: Array = choice.get("reasons", [])
	var verb := "Razed" if choice.choice == "raze" else "Raided"
	return verb + (": " + ", ".join(PackedStringArray(reasons)) + "." if not reasons.is_empty() else ".")


## "Bandit camp of the Nomad Horde · 24 strong"
static func camp(camp_: Dictionary, faction: String) -> String:
	var kind := "Monster lair" if camp_.kind == "lair" else "Bandit camp"
	return "%s of the %s · %d strong" % [kind, faction, int(camp_.size)]


## "Sanctity 87 / 100"
static func sanctity(world: Dictionary, data: Dictionary) -> String:
	return "Sanctity %d / %d" % [int(world.get("sanctity", 0)), int(data.horde.holyCity.sanctity)]
