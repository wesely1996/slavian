class_name CaravanMath
extends RefCounted
## Caravans from the server (see server caravanView): where they are on the
## road, and how many a village has out.


## {"from", "to", "t"} like WaveMath.progress, or {} when not on the road.
static func progress(caravan: Dictionary, at_unix: float) -> Dictionary:
	var path: Array = caravan.get("path", [])
	if path.is_empty():
		return {}
	if caravan.status == "outbound":
		return WaveMath.progress({"status": "marching", "spawnAt": caravan.departsAt, "path": path}, at_unix)
	if caravan.status == "returning":
		# The same road backwards, starting when it arrived.
		var total := float(path[path.size() - 1][2])
		var back := []
		for i in range(path.size() - 1, -1, -1):
			back.append([path[i][0], path[i][1], total - float(path[i][2])])
		return WaveMath.progress({"status": "marching", "spawnAt": caravan.arrivesAt, "path": back}, at_unix)
	return {}


## Caravans of a village still on the road.
static func out(caravans: Array, village_id: int) -> int:
	var n := 0
	for caravan in caravans:
		if int(caravan.villageId) == village_id and caravan.status != "done":
			n += int(caravan.caravans)
	return n


static func available(data: Dictionary, village: Dictionary, caravans: Array) -> int:
	var yard := int(village.get("levels", {}).get("caravan_yard", 0))
	return yard * int(data.logistics.caravan.caravansPerYardLevel) - out(caravans, int(village.id))


static func capacity(data: Dictionary, bonuses: Dictionary = {}) -> int:
	return floori(float(data.logistics.caravan.capacity) * (1.0 + ResearchRules.bonus(bonuses, "caravanCapacity")))


static func needed(data: Dictionary, cargo: Dictionary, bonuses: Dictionary = {}) -> int:
	var total := 0
	for kind in Ledger.KINDS:
		total += int(cargo.get(kind, 0))
	return ceili(float(total) / float(capacity(data, bonuses)))


static func vault_upgrade_cost(data: Dictionary, target_level: int) -> Dictionary:
	var v: Dictionary = data.logistics.vault
	var cost := {}
	for kind in Ledger.KINDS:
		cost[kind] = roundi(float(v.upgradeCost[kind]) * pow(float(v.costGrowth), target_level - 2))
	return cost


static func vault_upgrade_seconds(data: Dictionary, target_level: int, world_speed: float) -> float:
	var v: Dictionary = data.logistics.vault
	return float(v.upgradeSeconds) * pow(float(v.timeGrowth), target_level - 2) / world_speed
