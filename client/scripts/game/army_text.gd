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
		"clear": UI.t("Clear: storms a camp or lair and holds its hex with the loot until moved or called home."),
		"explore": UI.t("Explore: fights any guardians, searches the site for some hours, then holds its hex with what it found. Scouts may go too."),
		"garrison": UI.t("Garrison: marches into your village and joins its garrison, bringing what grain it has left."),
	}.get(order, order)


## What "come home when done" means for `order` (at a shipyard: `shipyard`).
static func return_text(order: String, shipyard: bool) -> String:
	if shipyard:
		return UI.t("Come home when done: they guard the shipyard against its raiders until the boat is finished, then march home with what they carry.")
	return {
		"support": UI.t("Come home when done: they march to the village, fight its battle if one is on, then come home instead of standing guard."),
		"hold": UI.t("Come home when done: they march to the hex and straight back, instead of holding it."),
		"clear": UI.t("Come home when done: once the camp is cleared they bring its loot home instead of holding its hex."),
		"explore": UI.t("Come home when done: once the guardians are beaten and the site searched, they bring what they found home."),
	}.get(order, UI.t("Come home when done: once their errand is done they march home by themselves."))


static func units_text(units: Dictionary, defs: Dictionary) -> String:
	var parts := PackedStringArray()
	for unit in units:
		if int(units[unit]) > 0:
			parts.append(UI.t("%s ×%d") % [UI.t(defs.get(unit, {"name": unit}).name), int(units[unit])])
	return ", ".join(parts) if not parts.is_empty() else UI.t("no one")


## "Supporting Vesna · arrives in 3m", from the point of view of its owner.
static func status(army: Dictionary, target_name: String, now: float, search_ends := 0.0) -> String:
	var verb: String = {
		"support": UI.t("Supporting"),
		"reinforce": UI.t("Reinforcing"),
		"harass": UI.t("Harassing"),
		"hold": UI.t("Marching to hold"),
		"clear": UI.t("Marching to clear the camp at"),
		"explore": UI.t("Marching to explore"),
		"garrison": UI.t("Marching into"),
	}.get(army.orders, UI.t("Marching to"))
	match army.status:
		"marching":
			return UI.t("%s %s · arrives in %s") % [verb, target_name, TimeUtil.format_duration(TimeUtil.parse_iso(army.arrivesAt) - now)]
		"stationed":
			if army.orders == "explore":
				if search_ends > now:
					return UI.t("Searching the site at %s · done in %s") % [target_name, TimeUtil.format_duration(search_ends - now)]
				return UI.t("Searching the site at %s") % target_name
			return (UI.t("Holding %s") if army.orders == "hold" else UI.t("Standing guard at %s")) % target_name
		"engaged":
			return UI.t("Fighting at %s") % target_name
		"returning":
			var loot := UI.t(" with loot") if army.get("loot") is Dictionary else ""
			return UI.t("Coming home from %s%s · %s") % [target_name, loot, TimeUtil.format_duration(TimeUtil.parse_iso(army.returnsAt) - now)]
	return UI.t("Back from %s") % target_name


## When an army searching a site is done (unix seconds; 0: not searching):
## the search starts as it arrives and takes the site's exploreHours, the
## less the more of them (sites.json search).
static func search_ends(data: Dictionary, army: Dictionary, site: Dictionary, world_speed: float) -> float:
	if army.orders != "explore" or army.status != "stationed" or site.is_empty():
		return 0.0
	return TimeUtil.parse_iso(army.arrivesAt) + search_seconds(data, String(site.kind), army.units, world_speed)


## Real-time seconds `units` take to search a site of `kind` (sim/sites.ts searchMs).
static func search_seconds(data: Dictionary, kind: String, units: Dictionary, world_speed: float) -> float:
	var count := 0
	for unit in units:
		count += maxi(0, int(units[unit]))
	var rules: Dictionary = data.sites.get("search", {"perUnit": 0.0, "minShare": 1.0})
	var share := maxf(float(rules.minShare), 1.0 / (1.0 + float(rules.perUnit) * maxi(0, count - 1)))
	# Without scouts it takes noScoutsFactor times as long.
	var scouts := 0
	for unit in units:
		if data.units.units.get(unit, {}).get("family", "") == "scout":
			scouts += maxi(0, int(units[unit]))
	var slow := 1.0 if scouts > 0 else float(rules.get("noScoutsFactor", 1.0))
	return float(data.sites.kinds.get(kind, {}).get("exploreHours", 0)) * 3600.0 * share * slow / world_speed


## When it gets there and when it is home again: on the march, the arrival
## and then the way back (orders that end on their own: reinforce, harass,
## clear, explore) or that it stays until called home; standing, how far
## home is; coming home, when it is back.
static func timeline(army: Dictionary, target_name: String, now: float) -> String:
	var road := TimeUtil.parse_iso(army.arrivesAt) - TimeUtil.parse_iso(army.departsAt)
	match army.status:
		"marching":
			var there := UI.t("At %s in %s") % [target_name, TimeUtil.format_duration(TimeUtil.parse_iso(army.arrivesAt) - now)]
			if army.orders in ["reinforce", "harass"]:
				return there + UI.t(" · then home, %s on the road") % TimeUtil.format_duration(road)
			return there + UI.t(" · stays until called home (%s back)") % TimeUtil.format_duration(road)
		"stationed", "engaged":
			return UI.t("At %s · called home, it is back in %s") % [target_name, TimeUtil.format_duration(road)]
		"returning":
			return UI.t("Coming home · back in %s") % TimeUtil.format_duration(TimeUtil.parse_iso(army.returnsAt) - now)
	return UI.t("Home")


## An army's grain: how long it lasts, or how long it has gone without
## ("" for an army its home village feeds).
static func supply_text(data: Dictionary, army: Dictionary, speed: float, now: float) -> String:
	var out := _out_of_food_at(data, army, speed)
	if out < 0:
		return ""
	if now < out:
		return UI.t("Grain for %s") % TimeUtil.format_duration(out - now)
	var a: Dictionary = data.armies.attrition
	var hours := (now - out) * speed / 3600.0
	if hours < float(a.lossAfterHours):
		return UI.t("Out of food: marching slower · men start to die in %s") % TimeUtil.format_duration((float(a.lossAfterHours) - hours) * 3600.0 / speed)
	return UI.t("Starving: losing men every %s · gone in %s") % [TimeUtil.format_duration(float(a.checkHours) * 3600.0 / speed), TimeUtil.format_duration(maxf(0.0, float(a.lostAfterHours) - hours) * 3600.0 / speed)]


## The grain an army carries now (0 for one its home village feeds).
static func supply_left(data: Dictionary, army: Dictionary, speed: float, now: float) -> float:
	var out := _out_of_food_at(data, army, speed)
	if out < 0 or now >= out:
		return 0.0 if out >= 0 or army.get("supply") == null else float(army.supply)
	var at := TimeUtil.parse_iso(String(army.supplyAt))
	return float(army.supply) * (out - now) / maxf(1.0, out - at)


## Grain the units eat per game hour (each unit's upkeepPerHour).
static func upkeep(data: Dictionary, units: Dictionary) -> float:
	var total := 0.0
	for unit in units:
		total += float(data.units.units.get(unit, {}).get("upkeepPerHour", 0)) * int(units[unit])
	return total


## The grain an army carries when full: each unit its own supplyHours of
## its upkeep (server sim/supply.ts fullSupply).
static func full_supply(data: Dictionary, units: Dictionary) -> float:
	var total := 0.0
	for unit in units:
		var def: Dictionary = data.units.units.get(unit, {})
		total += (float(def.get("upkeepPerHour", 0)) * float(def.get("supplyHours", 0)) + float(def.get("supplyGrain", 0))) * int(units[unit])
	return total


## How worn the army is from going without food, 0 (fed) to 1 (lost): the
## game hours it has gone hungry against the day it can last
## (data/armies.json attrition). Fatigue comes from hunger alone.
static func fatigue(data: Dictionary, army: Dictionary, speed: float, now: float) -> float:
	var out := _out_of_food_at(data, army, speed)
	if out < 0 or now < out:
		return 0.0
	var hours := (now - out) * speed / 3600.0
	return clampf(hours / float(data.armies.attrition.lostAfterHours), 0.0, 1.0)


## Fatigue in words: fed, hungry (slower), or starving (losing men).
static func fatigue_text(data: Dictionary, army: Dictionary, speed: float, now: float) -> String:
	var out := _out_of_food_at(data, army, speed)
	if out < 0:
		return UI.t("Fed by its village")
	if now < out:
		return UI.t("Fed: no fatigue")
	var a: Dictionary = data.armies.attrition
	var hours := (now - out) * speed / 3600.0
	if hours < float(a.lossAfterHours):
		return UI.t("Hungry: marching %d%% slower") % roundi((1.0 - float(a.slowFactor)) * 100.0)
	return UI.t("Starving: losing %d%% of its men every %s") % [roundi(float(a.lossShare) * 100.0), TimeUtil.format_duration(float(a.checkHours) * 3600.0 / speed)]


## Whether an army carrying its own grain has run out of it.
static func out_of_food(data: Dictionary, army: Dictionary, speed: float, now: float) -> bool:
	var out := _out_of_food_at(data, army, speed)
	return out >= 0 and now >= out


## When an army's grain runs out, in unix seconds (-1: its village feeds it,
## or it eats nothing).
static func _out_of_food_at(data: Dictionary, army: Dictionary, speed: float) -> float:
	if army.get("supply") == null or army.get("supplyAt") == null or army.status == "done":
		return -1.0
	if army.get("hungrySince") != null:
		return TimeUtil.parse_iso(String(army.hungrySince))
	var rate := 0.0
	for unit in army.units:
		rate += float(data.units.units.get(unit, {}).get("upkeepPerHour", 0)) * int(army.units[unit])
	rate *= speed
	if rate <= 0:
		return -1.0
	return TimeUtil.parse_iso(String(army.supplyAt)) + float(army.supply) / rate * 3600.0


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
				text += UI.t(" (+%d%% %s)") % [bonus, UI.t("harassment") if joined.orders == "harass" else (UI.t("hammer and anvil") if joined.get("hammer", false) else UI.t("pincer"))]
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
