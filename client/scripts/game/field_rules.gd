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
		lines.append(UI.t("Ambush ground: +%d%% attack in the first round if your army is here %s before the horde.") % [
			roundi(float(data.field.ambush.bonus) * 100.0), TimeUtil.format_duration(prep)])
	if is_choke_point(data, terrain, cell):
		lines.append(UI.t("Choke point: the horde strikes at %d%%; Hold the Line adds +%d%% defense.") % [
			roundi(float(data.field.choke.attackerFactor) * 100.0), roundi(float(data.field.choke.holdTheLineDefense) * 100.0)])
	if not fort.is_empty() and fort.get("kind", "fort") == "supply":
		lines.append(UI.t("Supply point: armies here fill up from its grain.") if fort.status == "standing" else UI.t("Supply point being built."))
	elif not fort.is_empty():
		var bonus := roundi(float(data.field.fort.defenseBonus) * 100.0)
		lines.append(UI.t("Fort: +%d%% defense.") % bonus if fort.status == "standing" else UI.t("Fort being built (+%d%% defense when done).") % bonus)
	if not fort.is_empty() and fort.status == "standing":
		lines.append(UI.t("Grain kept here: %d of %d.") % [floori(float(fort.get("grain", 0))), int(grain_capacity(data, fort.get("kind", "fort")))])
	if lines.is_empty():
		lines.append(UI.t("Open ground: no help from the land."))
	return lines


## Why `village` can't build a fort (or, with kind "supply", a supply
## point) on `cell` ("" if it can).
static func fort_problem(data: Dictionary, village: Dictionary, cell: Vector2i, terrain_id: String, taken: bool, kind := "fort") -> String:
	var supply := kind == "supply"
	var range_ := int(data.field.supplyPoint.range if supply else data.field.fort.range)
	var distance := HexMath.distance(cell, Vector2i(int(village.q), int(village.r)))
	if distance == 0 or distance > range_:
		return (UI.t("Supply points go within %d hexes of %s.") if supply else UI.t("Forts go within %d hexes of %s.")) % [range_, village.name]
	if terrain_id == "holy_city" or data.terrain.terrain.get(terrain_id, {}).get("moveCost") == null:
		return UI.t("No supply point can stand here.") if supply else UI.t("No fort can stand here.")
	if taken:
		return UI.t("Something already stands here.")
	return ""


## Wagons (Military Caravans) among `units`: no soldiers.
static func wagons_in(data: Dictionary, units: Dictionary) -> int:
	var n := 0
	for unit in units:
		if data.units.units.get(unit, {}).get("wagon", false) == true:
			n += int(units[unit])
	return n


## The defense an army's wagon fort gives it (field.json wagonFort; with
## other armies on the hex the server counts them all): its wagons for
## each `menPerWagon` soldiers, at most `maxBonus`.
static func wagon_fort_bonus(data: Dictionary, units: Dictionary) -> float:
	var rules: Dictionary = data.field.wagonFort
	var wagons := wagons_in(data, units)
	if wagons == 0:
		return 0.0
	var soldiers := 0
	for unit in units:
		soldiers += int(units[unit])
	soldiers -= wagons
	return minf(float(rules.maxBonus), float(rules.bonusPerWagon) * wagons / maxf(1.0, ceilf(soldiers / float(rules.menPerWagon))))


## The grain a village's military reserve keeps at most (data/armies.json
## reserve; server sim/reserve.ts reserveCapacity).
static func reserve_capacity(data: Dictionary, plots: Dictionary) -> float:
	var levels := 0
	for plot in plots.values():
		if plot.get("building") != null and String(plot.building) in data.armies.reserve.buildings:
			levels += int(plot.level)
	return float(levels) * float(data.armies.reserve.grainPerLevel)


## The grain a fort or supply point keeps at most (data/field.json).
static func grain_capacity(data: Dictionary, kind: String) -> float:
	return float(data.field.supplyPoint.grainCapacity if kind == "supply" else data.field.fort.grainCapacity)


## What a fort costs a village with these bonuses (some clans pay more,
## some less; see server scheduler/field.ts fortCost).
static func fort_cost(data: Dictionary, bonuses: Dictionary) -> Dictionary:
	var factor := maxf(0.1, 1.0 + float(bonuses.get("fortCost", 0)))
	var cost := {}
	for kind in data.field.fort.cost:
		cost[kind] = roundi(float(data.field.fort.cost[kind]) * factor)
	return cost
