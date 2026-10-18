class_name ArmyText
extends RefCounted
## Words and positions for armies (see server armyView).

const ORDERS := {
	"support": "Support: stands guard there and fights its battles until called home.",
	"reinforce": "Reinforce: joins the battle there, then comes home.",
	"harass": "Harass (mostly cavalry): strikes one round hard, takes few losses, rides home.",
	"hold": "Hold: digs in on a hex and fights every horde whose road runs through it.",
}


static func units_text(units: Dictionary, defs: Dictionary) -> String:
	var parts := PackedStringArray()
	for unit in units:
		if int(units[unit]) > 0:
			parts.append("%s ×%d" % [defs.get(unit, {"name": unit}).name, int(units[unit])])
	return ", ".join(parts) if not parts.is_empty() else "no one"


## "Supporting Vesna · arrives in 3m", from the point of view of its owner.
static func status(army: Dictionary, target_name: String, now: float) -> String:
	var verb: String = {"support": "Supporting", "reinforce": "Reinforcing", "harass": "Harassing", "hold": "Marching to hold"}.get(army.orders, "Marching to")
	match army.status:
		"marching":
			return "%s %s · arrives in %s" % [verb, target_name, TimeUtil.format_duration(TimeUtil.parse_iso(army.arrivesAt) - now)]
		"stationed":
			return ("Holding %s" if army.orders == "hold" else "Standing guard at %s") % target_name
		"engaged":
			return "Fighting at %s" % target_name
		"returning":
			return "Coming home from %s · %s" % [target_name, TimeUtil.format_duration(TimeUtil.parse_iso(army.returnsAt) - now)]
	return "Back from %s" % target_name


## Where it is headed: a village's name, or the hex it holds.
static func target_name(army: Dictionary, village_name: Callable) -> String:
	if army.get("targetVillageId") == null and army.get("target") is Array:
		return "(%d, %d)" % [int(army.target[0]), int(army.target[1])]
	return village_name.call(army.targetVillageId)


## The hex an army holds (Vector2i.MAX for village armies).
static func held_hex(army: Dictionary) -> Vector2i:
	if army.get("targetVillageId") == null and army.get("target") is Array:
		return Vector2i(int(army.target[0]), int(army.target[1]))
	return Vector2i.MAX


## Where it is on the road ({} when not moving), like CaravanMath.progress.
static func progress(army: Dictionary, now: float) -> Dictionary:
	if army.status == "marching":
		return CaravanMath.progress({"status": "outbound", "departsAt": army.departsAt, "path": army.path}, now)
	if army.status == "returning" and army.leavesAt != null:
		return CaravanMath.progress({"status": "returning", "arrivesAt": army.leavesAt, "path": army.path}, now)
	return {}


## Armies that joined a battle, from its round logs: "Ola's village (+18% pincer)".
static func reinforcements(battle: Dictionary, village_name: Callable) -> String:
	var parts := PackedStringArray()
	for round in battle.get("rounds", []):
		for joined in round.get("joined", []):
			var text: String = village_name.call(joined.villageId)
			var bonus := roundi(float(joined.bonus) * 100.0)
			if bonus > 0:
				text += " (+%d%% %s)" % [bonus, "harassment" if joined.orders == "harass" else "pincer"]
			parts.append(text)
	return ", ".join(parts)
