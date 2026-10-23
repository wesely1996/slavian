class_name ArmyText
extends RefCounted
## Words and positions for armies (see server armyView).

## The orders, translated (English source, Serbian via .po).
static func order_text(order: String) -> String:
	return {
		"support": UI.t("Support: stands guard there and fights its battles until called home."),
		"reinforce": UI.t("Reinforce: joins the battle there, then comes home."),
		"harass": UI.t("Harass (mostly cavalry): strikes one round hard, takes few losses, rides home."),
		"hold": UI.t("Hold: digs in on a hex and fights every horde whose road runs through it."),
		"clear": UI.t("Clear: storms a camp or lair and carries its loot home."),
		"explore": UI.t("Explore: fights any guardians, searches the site for some hours and brings home what it finds. Scouts may go too."),
	}.get(order, order)


static func units_text(units: Dictionary, defs: Dictionary) -> String:
	var parts := PackedStringArray()
	for unit in units:
		if int(units[unit]) > 0:
			parts.append(UI.t("%s ×%d") % [UI.t(defs.get(unit, {"name": unit}).name), int(units[unit])])
	return ", ".join(parts) if not parts.is_empty() else UI.t("no one")


## "Supporting Vesna · arrives in 3m", from the point of view of its owner.
static func status(army: Dictionary, target_name: String, now: float) -> String:
	var verb: String = {
		"support": UI.t("Supporting"),
		"reinforce": UI.t("Reinforcing"),
		"harass": UI.t("Harassing"),
		"hold": UI.t("Marching to hold"),
		"clear": UI.t("Marching to clear the camp at"),
		"explore": UI.t("Marching to explore"),
	}.get(army.orders, UI.t("Marching to"))
	match army.status:
		"marching":
			return UI.t("%s %s · arrives in %s") % [verb, target_name, TimeUtil.format_duration(TimeUtil.parse_iso(army.arrivesAt) - now)]
		"stationed":
			if army.orders == "explore":
				return UI.t("Searching the site at %s") % target_name
			return (UI.t("Holding %s") if army.orders == "hold" else UI.t("Standing guard at %s")) % target_name
		"engaged":
			return UI.t("Fighting at %s") % target_name
		"returning":
			var loot := UI.t(" with loot") if army.get("loot") is Dictionary else ""
			return UI.t("Coming home from %s%s · %s") % [target_name, loot, TimeUtil.format_duration(TimeUtil.parse_iso(army.returnsAt) - now)]
	return UI.t("Back from %s") % target_name


## When it gets there and when it is home again: on the march, the arrival
## and then the way back (orders that end on their own: reinforce, harass,
## clear, explore) or that it stays until called home; standing, how far
## home is; coming home, when it is back.
static func timeline(army: Dictionary, target_name: String, now: float) -> String:
	var road := TimeUtil.parse_iso(army.arrivesAt) - TimeUtil.parse_iso(army.departsAt)
	match army.status:
		"marching":
			var there := UI.t("At %s in %s") % [target_name, TimeUtil.format_duration(TimeUtil.parse_iso(army.arrivesAt) - now)]
			if army.orders in ["reinforce", "harass", "clear", "explore"]:
				return there + UI.t(" · then home, %s on the road") % TimeUtil.format_duration(road)
			return there + UI.t(" · stays until called home (%s back)") % TimeUtil.format_duration(road)
		"stationed", "engaged":
			return UI.t("At %s · called home, it is back in %s") % [target_name, TimeUtil.format_duration(road)]
		"returning":
			return UI.t("Coming home · back in %s") % TimeUtil.format_duration(TimeUtil.parse_iso(army.returnsAt) - now)
	return UI.t("Home")


## Where it is headed: a village's name, or the hex it holds.
static func target_name(army: Dictionary, village_name: Callable) -> String:
	if army.get("targetVillageId") == null and army.get("target") is Array:
		if int(army.target[0]) == 0 and int(army.target[1]) == 0:
			return UI.t("the Holy City")
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
				text += UI.t(" (+%d%% %s)") % [bonus, UI.t("harassment") if joined.orders == "harass" else UI.t("pincer")]
			parts.append(text)
	return ", ".join(parts)


## The kind most of the army is made of (its icon on the map).
static func main_unit(army: Dictionary) -> String:
	var best := ""
	var most := 0
	for unit in army.get("units", {}):
		if int(army.units[unit]) > most:
			most = int(army.units[unit])
			best = unit
	return best
