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
	var verb := UI.t("Razed") if choice.choice == "raze" else UI.t("Raided")
	return verb + (": " + ", ".join(PackedStringArray(reasons)) + "." if not reasons.is_empty() else ".")


## "Bandit camp of the Nomad Horde · 24 strong"
static func camp(camp_: Dictionary, faction: String) -> String:
	var kind := UI.t("Monster lair") if camp_.kind == "lair" else UI.t("Bandit camp")
	return UI.t("%s of the %s · %d strong") % [kind, UI.t(faction), int(camp_.size)]


## "Sanctity 87 / 100"
static func sanctity(world: Dictionary, data: Dictionary) -> String:
	return UI.t("Sanctity %d / %d") % [int(world.get("sanctity", 0)), int(data.horde.holyCity.sanctity)]


## "Ambushed near (2, -1): lost Wood 200" / "Beat off an ambush near (2, -1)".
static func ambush(report: Variant) -> String:
	if not report is Dictionary:
		return ""
	var where := "(%d, %d)" % [int(report.q), int(report.r)]
	if report.beatenOff:
		return UI.t("Its escort beat off an ambush near %s") % where
	var parts := PackedStringArray()
	for kind in ["wood", "stone", "grain", "iron"]:
		if int(report.lost.get(kind, 0)) > 0:
			parts.append(UI.t("%s %d") % [UI.resource_name(kind), int(report.lost[kind])])
	return UI.t("Ambushed near %s: lost %s") % [where, ", ".join(parts) if not parts.is_empty() else UI.t("nothing")]


## "Cleared the lair at (3, 1): 9 fell, we lost 2." for an army storming a camp.
static func assault(battle: Dictionary, lost: Dictionary) -> String:
	var where := UI.t("the camp at (%d, %d)") % [int(battle.q), int(battle.r)]
	if battle.status == "cleared":
		return UI.t("Cleared %s: %d fell, we lost %d.") % [where, int(lost.attacker), int(lost.defender)]
	return UI.t("Driven off from %s: %d of them fell, we lost %d.") % [where, int(lost.attacker), int(lost.defender)]
