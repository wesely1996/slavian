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


static func build_seconds(def: Dictionary, target_level: int, world_speed: float, hall_speedup := 1.0) -> float:
	return def.buildSeconds * pow(def.timeGrowth, target_level - 1) * hall_speedup / world_speed


# --- Village layout: fields "f0"… around the outside, slots "c0"… in the
# center ("c0" holds the Elder's Hall), the walls "w" and their slots "t0"…
# for towers. See server/src/sim/village.ts and walls.ts.

const HALL := "elder_hall"
const HALL_PLOT := "c0"
const WALL_PLOT := "w"
## Layout order of plot kinds.
const KIND_ORDER := {"f": 0, "c": 1, "w": 2, "t": 3}


static func hall_level(village: Dictionary) -> int:
	return int(village.get("levels", {}).get(HALL, 0))


## Center slots usable at an Elder's Hall level.
static func unlocked_slots(data: Dictionary, level: int) -> int:
	var v: Dictionary = data.buildings.village
	return mini(int(v.centerSlots), int(v.slotsUnlockedAtStart) + int(v.slotsPerHallLevel) * maxi(0, level - 1))


## Elder's Hall level that unlocks center slot `index`.
static func slot_unlock_level(data: Dictionary, index: int) -> int:
	var v: Dictionary = data.buildings.village
	var beyond := index - int(v.slotsUnlockedAtStart)
	if beyond < 0:
		return 1
	return 2 + beyond / int(v.slotsPerHallLevel)


static func queue_limit(data: Dictionary, level: int) -> int:
	var v: Dictionary = data.buildings.village
	return int(v.baseQueueLimit) + level / int(v.hallLevelsPerQueueSlot)


static func hall_speedup(data: Dictionary, level: int) -> float:
	return pow(float(data.buildings.village.hallBuildSpeedup), maxi(0, level - 1))


static func is_field(plot: String) -> bool:
	return plot.begins_with("f")


static func is_wall(plot: String) -> bool:
	return plot == WALL_PLOT


static func is_tower_slot(plot: String) -> bool:
	return plot.begins_with("t")


static func wall_level(village: Dictionary) -> int:
	return int(village.get("plots", {}).get(WALL_PLOT, {}).get("level", 0))


## Wall slots open at a walls level (walls.json slotsAt).
static func open_tower_slots(data: Dictionary, level: int) -> int:
	return data.get("walls", {}).get("slotsAt", []).filter(func(at: Variant) -> bool: return level >= int(at)).size()


## The walls level that opens wall slot `index`.
static func tower_unlock_level(data: Dictionary, index: int) -> int:
	var at: Array = data.get("walls", {}).get("slotsAt", [])
	return int(at[index]) if index < at.size() else 99


static func plot_index(plot: String) -> int:
	return int(plot.substr(1))


## Village plot ids in layout order (the server's JSON keeps no order):
## fields first, then center slots, each by number. Outposts aside.
static func plot_ids(village: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for id in village.get("plots", {}):
		if not is_outpost(id):
			ids.append(id)
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ka: int = KIND_ORDER.get(a.left(1), 9)
		var kb: int = KIND_ORDER.get(b.left(1), 9)
		if ka != kb:
			return ka < kb
		return plot_index(a) < plot_index(b))
	return ids


static func is_locked(data: Dictionary, village: Dictionary, plot: String) -> bool:
	if is_tower_slot(plot):
		return plot_index(plot) >= open_tower_slots(data, wall_level(village))
	return plot.begins_with("c") and plot_index(plot) >= unlocked_slots(data, hall_level(village))


## What a plot will hold once everything already queued completes.
static func planned_plot(village: Dictionary, plot: String) -> Dictionary:
	var current: Dictionary = village.plots.get(plot, {"building": null, "level": 0})
	var planned := {"building": current.building, "level": int(current.level)}
	for item in village.queue:
		if item.get("plot", "") == plot:
			planned = {"building": item.building, "level": int(item.targetLevel)}
	return planned


## Buildings of `kind` ("center", or "tower" for a wall slot) that could go
## in an empty slot: not built or queued anywhere in the village yet.
static func constructible(data: Dictionary, village: Dictionary, kind := "center") -> Array[String]:
	var taken := {}
	for id in village.get("plots", {}):
		var building: Variant = planned_plot(village, id).building
		if building != null:
			taken[building] = true
	var result: Array[String] = []
	var buildings: Dictionary = data.buildings.buildings
	for building in buildings:
		if buildings[building].kind == kind and not taken.has(building) and ClanText.allowed(buildings[building], village.get("bonuses", {})):
			result.append(building)
	return result


# --- Outposts: plots "o<q>,<r>" on map hexes near the village.

const OUTPOST := "outpost"


static func outpost_plot(cell: Vector2i) -> String:
	return "o%d,%d" % [cell.x, cell.y]


static func is_outpost(plot: String) -> bool:
	return plot.begins_with("o")


static func outpost_hex(plot: String) -> Vector2i:
	var parts := plot.substr(1).split(",")
	return Vector2i(int(parts[0]), int(parts[1]))


static func outpost_plots(village: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for id in village.get("plots", {}):
		if is_outpost(id):
			ids.append(id)
	ids.sort()
	return ids


static func outpost_limit(data: Dictionary, level: int) -> int:
	var v: Dictionary = data.buildings.village
	return int(v.baseOutposts) + level / int(v.hallLevelsPerOutpost)


## Resources per hour an outpost gathers on `terrain` (world speed applied).
static func outpost_yield(data: Dictionary, terrain: String, level: int, world_speed: float) -> Dictionary:
	var def: Dictionary = data.buildings.buildings[OUTPOST]
	var base: Dictionary = def.yields.get(terrain, {})
	var factor := pow(float(def.yieldGrowth), level - 1) * world_speed if level > 0 else 0.0
	var result := {}
	for kind in Ledger.KINDS:
		result[kind] = float(base.get(kind, 0)) * factor
	return result


## Why `village` can't claim `cell` ("" when it can). `taken` says whether
## a village or outpost already stands there.
static func claim_problem(data: Dictionary, village: Dictionary, cell: Vector2i, terrain: String, taken: bool) -> String:
	var range_ := int(data.buildings.village.outpostRange)
	var distance := HexMath.distance(cell, Vector2i(int(village.q), int(village.r)))
	if distance == 0 or distance > range_:
		return UI.t("Outposts go within %d hexes of your village.") % range_
	if not data.buildings.buildings[OUTPOST].yields.has(terrain):
		return UI.t("Nothing to gather here.")
	if taken:
		return UI.t("Already taken.")
	var limit := outpost_limit(data, hall_level(village))
	if outpost_plots(village).size() >= limit:
		return UI.tn("Your village can hold %d outpost; upgrade the Elder's Hall for more.", "Your village can hold %d outposts; upgrade the Elder's Hall for more.", limit) % limit
	return ""


## Production per hour of one field plot at a level (world speed applied).
static func field_production(def: Dictionary, level: int, world_speed: float) -> float:
	if level <= 0 or not def.has("production"):
		return 0.0
	return float(def.production.basePerHour) * pow(float(def.production.growth), level - 1) * world_speed


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


## What `count` units cost an owner of `villages_owned` villages: settlers
## get dearer with every village (server unitCost).
static func unit_cost(def: Dictionary, count: int, villages_owned := 1) -> Dictionary:
	var factor := pow(float(def.get("costGrowthPerVillage", 1.0)), maxi(0, villages_owned - 1))
	var cost := {}
	for kind in Ledger.KINDS:
		cost[kind] = roundi(float(def.cost[kind]) * factor) * count
	return cost


# --- Founding villages (server/src/sim/expansion.ts).

## Why a village can't be founded on `cell` ("" when it can).
static func settle_problem(data: Dictionary, cell: Vector2i, terrain: String, home: Vector2i, villages: Array, outpost_here: bool) -> String:
	var rules: Dictionary = data.expansion
	var def: Dictionary = data.terrain.terrain.get(terrain, {})
	if def.is_empty():
		return UI.t("That hex is not on the map.")
	if not def.settleable:
		return UI.t("Villages can't be founded on %s.") % UI.t(def.name)
	if HexMath.distance(cell, home) > int(rules.maxDistance):
		return UI.t("Settlers walk at most %d hexes from their village.") % int(rules.maxDistance)
	if HexMath.distance(cell, Vector2i.ZERO) < int(rules.minHolyCityDistance):
		return UI.t("Too close to the Holy City.")
	for other in villages:
		if HexMath.distance(other, cell) < int(rules.minVillageDistance):
			return UI.t("Villages stand at least %d hexes apart.") % int(rules.minVillageDistance)
	if outpost_here:
		return UI.t("An outpost stands there.")
	return ""


static func recommended_garrison(data: Dictionary, villages_owned: int) -> int:
	var g: Dictionary = data.expansion.recommendedGarrison
	return int(g.base) + int(g.perVillage) * maxi(0, villages_owned - 1)
