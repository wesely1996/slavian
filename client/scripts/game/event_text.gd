class_name EventText
extends RefCounted
## The daily map events still going (data/events.json): captives held in a
## camp, a forbidding ruin, a shipyard being paid for or built, and how far
## along a boat and the raiders coming for it are.


## Every event on the map now, soonest to end first:
## [{kind: "captives"|"ruin"|"shipyard", cell: Vector2i, item: the camp, site or shipyard}].
static func active(camps: Array, sites: Array, shipyards: Array) -> Array:
	var out: Array = []
	for camp in camps:
		if camp.get("kind") == "captives":
			out.append({"kind": "captives", "cell": Vector2i(int(camp.q), int(camp.r)), "item": camp})
	for site in sites:
		if site.get("hard", false) and site.get("status") == "unexplored":
			out.append({"kind": "ruin", "cell": Vector2i(int(site.q), int(site.r)), "item": site})
	for yard in shipyards:
		if yard.get("status") != "done":
			out.append({"kind": "shipyard", "cell": Vector2i(int(yard.q), int(yard.r)), "item": yard})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _ends(a) < _ends(b))
	return out


## When an event goes or is next decided (seconds; INF when nothing presses).
static func _ends(event: Dictionary) -> float:
	var item: Dictionary = event.item
	# A boat being built: the next raid, or when it is done.
	var keys := ["nextRaidAt", "completesAt"] if item.get("status") == "building" else ["endsAt"]
	for key in keys:
		if item.get(key) != null:
			return TimeUtil.parse_iso(String(item[key]))
	return INF


## How much of a shipyard's cost has been paid (0..1).
static func paid_share(yard: Dictionary) -> float:
	var cost := 0.0
	var paid := 0.0
	for kind in yard.get("cost", {}):
		cost += float(yard.cost[kind])
		paid += minf(float(yard.get("paid", {}).get(kind, 0)), float(yard.cost[kind]))
	return 1.0 if cost <= 0.0 else paid / cost


## How far along a boat being built is (0..1): the work left against its
## buildHours (raids that burn work push it back).
static func build_share(data: Dictionary, yard: Dictionary, now: float, world_speed: float) -> float:
	if yard.get("status") == "done":
		return 1.0
	if yard.get("status") != "building" or yard.get("completesAt") == null:
		return 0.0
	var span := float(data.events.kinds.shipyard.buildHours) * 3600.0 / world_speed
	var left := TimeUtil.parse_iso(String(yard.completesAt)) - now
	return clampf(1.0 - left / span, 0.0, 1.0) if span > 0.0 else 1.0


## How close the next raiders are to a shipyard (0: just set out, 1: they
## strike), over the raidEveryHours between raids; -1 when none are coming.
static func raid_share(data: Dictionary, yard: Dictionary, now: float, world_speed: float) -> float:
	if yard.get("status") != "building" or yard.get("nextRaidAt") == null:
		return -1.0
	var span := float(data.events.kinds.shipyard.raidEveryHours) * 3600.0 / world_speed
	var left := TimeUtil.parse_iso(String(yard.nextRaidAt)) - now
	return clampf(1.0 - left / span, 0.0, 1.0) if span > 0.0 else 1.0


## The event's name for the list: "Captives at (-2, 1)".
static func title(event: Dictionary) -> String:
	var cell: Vector2i = event.cell
	match String(event.kind):
		"captives":
			return UI.t("Captives at (%d, %d)") % [cell.x, cell.y]
		"ruin":
			return UI.t("Forbidding ruin at (%d, %d)") % [cell.x, cell.y]
	return UI.t("Shipyard at (%d, %d)") % [cell.x, cell.y]


## Its state now, in a line.
static func state(data: Dictionary, event: Dictionary, now: float, world_speed: float) -> String:
	var item: Dictionary = event.item
	if event.kind == "shipyard":
		if item.status == "building":
			var line := UI.t("Boat %d%% built · ready in %s") % [roundi(build_share(data, item, now, world_speed) * 100.0),
				TimeUtil.format_duration(TimeUtil.parse_iso(String(item.completesAt)) - now)]
			if item.get("nextRaidAt") != null:
				line += " · " + UI.t("%d raiders strike in %s") % [int(item.raiders), TimeUtil.format_duration(TimeUtil.parse_iso(String(item.nextRaidAt)) - now)]
			return line
		var paid := UI.t("%d%% paid") % roundi(paid_share(item) * 100.0)
		if item.get("endsAt") != null and paid_share(item) <= 0.0:
			paid += " · " + UI.t("gone in %s") % TimeUtil.format_duration(TimeUtil.parse_iso(String(item.endsAt)) - now)
		return paid
	if item.get("endsAt") == null:
		return UI.t("An army is on its way")
	return UI.t("Gone in %s, unless an army is on its way") % TimeUtil.format_duration(TimeUtil.parse_iso(String(item.endsAt)) - now)
