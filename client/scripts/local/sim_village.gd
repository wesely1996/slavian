class_name LocalVillage
extends RefCounted
## Villages for the local engine: server/src/sim/village.ts, with the bits of
## clans.ts, research.ts and training.ts it leans on. Same names, same
## arithmetic; times are whole milliseconds (LocalTime).
##
## A village state: {plots, levels, ledger: {amounts, ratesPerHour, capacity,
## settledAt}, queue, garrison, training, away, stance, besieged, adminUpkeep,
## bonuses}.

const HALL := "elder_hall"
const HALL_PLOT := "c0"
const OUTPOST := "outpost"
const WALL := "wall"
const WALL_PLOT := "w"
const KINDS := ["wood", "stone", "grain", "iron"]


static func field_plot(i: int) -> String:
	return "f%d" % i


static func center_plot(i: int) -> String:
	return "c%d" % i


static func tower_plot(i: int) -> String:
	return "t%d" % i


## "o3,-2" plots are outposts.
static func is_outpost_plot(plot: String) -> bool:
	return plot.begins_with("o")


static func resources(fn: Callable) -> Dictionary:
	var out := {}
	for kind in KINDS:
		out[kind] = fn.call(kind)
	return out


# --- research.ts, clans.ts, training.ts ---------------------------------------

static func bonus(bonuses: Dictionary, key: String) -> float:
	return float(bonuses.get(key, 0.0))


static func production_factor(bonuses: Dictionary, kind: String) -> float:
	return 1.0 + bonus(bonuses, "production.%s" % kind) + bonus(bonuses, "production.all")


static func clan_bonuses(data: Dictionary, clan: Variant) -> Dictionary:
	if clan == null or not data.clans.clans.has(clan):
		return {}
	var out: Dictionary = data.clans.clans[clan].effects.duplicate()
	out["clan.%s" % clan] = 1
	return out


## The owner's bonuses plus what the village's buildings add.
static func village_bonuses(data: Dictionary, state: Dictionary) -> Dictionary:
	var out: Variant = null
	for plot in state.plots.values():
		if plot.building == null or int(plot.level) <= 0:
			continue
		var effects: Variant = data.buildings.buildings.get(plot.building, {}).get("effects")
		if effects == null:
			continue
		if out == null:
			out = state.bonuses.duplicate()
		for key in effects:
			out[key] = float(out.get(key, 0.0)) + float(effects[key]) * int(plot.level)
	return state.bonuses if out == null else out


static func add_units(a: Dictionary, b: Dictionary) -> Dictionary:
	var sum := a.duplicate()
	for unit in b:
		sum[unit] = int(sum.get(unit, 0)) + int(b[unit])
	return sum


static func all_units(garrison: Dictionary, training: Array) -> Dictionary:
	var sum := garrison.duplicate()
	for batch in training:
		sum = add_units(sum, {batch.unit: batch.count})
	return sum


static func units_fed(state: Dictionary) -> Dictionary:
	return add_units(all_units(state.garrison, state.training), state.away)


static func upkeep_per_hour(data: Dictionary, units: Dictionary, world_speed: float) -> float:
	var total := 0.0
	for unit in units:
		total += float(data.units.units.get(unit, {}).get("upkeepPerHour", 0)) * int(units[unit])
	return total * world_speed


# --- village.ts ---------------------------------------------------------------

static func initial_plots(data: Dictionary) -> Dictionary:
	var v: Dictionary = data.buildings.village
	var plots := {}
	for i in v.fields.size():
		plots[field_plot(i)] = {"building": v.fields[i], "level": 0}
	for i in int(v.centerSlots):
		plots[center_plot(i)] = {"building": null, "level": 0}
	plots[HALL_PLOT] = {"building": HALL, "level": 1}
	return with_wall_plots(data, plots)


static func with_wall_plots(data: Dictionary, plots: Dictionary) -> Dictionary:
	var out := plots.duplicate(true)
	if not out.has(WALL_PLOT):
		out[WALL_PLOT] = {"building": WALL, "level": 0}
	for i in data.walls.slotsAt.size():
		if not out.has(tower_plot(i)):
			out[tower_plot(i)] = {"building": null, "level": 0}
	return out


## Highest level of each building in the village itself (outposts aside).
static func levels_of(plots: Dictionary) -> Dictionary:
	var levels := {}
	for id in plots:
		var plot: Dictionary = plots[id]
		if is_outpost_plot(id) or plot.building == null or int(plot.level) <= 0:
			continue
		levels[plot.building] = maxi(int(levels.get(plot.building, 0)), int(plot.level))
	return levels


static func outpost_yield(def: Dictionary, terrain: Variant, level: int, world_speed: float) -> Dictionary:
	var base: Variant = def.get("yields", {}).get(terrain) if terrain != null else null
	var factor := pow(float(def.get("yieldGrowth", 1)), level - 1) * world_speed if level > 0 else 0.0
	return resources(func(kind: String) -> float: return float(base.get(kind, 0) if base != null else 0) * factor)


## Real-time rates; world speed multiplies production, research raises it.
static func production_per_hour(data: Dictionary, plots: Dictionary, world_speed: float, besieged: bool, bonuses: Dictionary) -> Dictionary:
	var rates := resources(func(kind: String) -> float: return float(data.buildings.village.baseProductionPerHour[kind]) * world_speed)
	var outpost_factor := 1.0 + bonus(bonuses, "outpostYield")
	for plot in plots.values():
		if plot.building == null or int(plot.level) <= 0:
			continue
		var def: Dictionary = data.buildings.buildings[plot.building]
		if def.get("production") != null:
			var p: Dictionary = def.production
			rates[p.resource] += float(p.basePerHour) * pow(float(p.growth), int(plot.level) - 1) * world_speed
		elif def.get("yields") != null and not besieged:
			var gathered := outpost_yield(def, plot.get("terrain"), int(plot.level), world_speed)
			for kind in KINDS:
				rates[kind] += gathered[kind] * outpost_factor
	return resources(func(kind: String) -> float: return rates[kind] * production_factor(bonuses, kind))


## Net rates: production minus grain upkeep for every unit fed.
static func village_rates(data: Dictionary, state: Dictionary, world_speed: float) -> Dictionary:
	var bonuses := village_bonuses(data, state)
	var rates := production_per_hour(data, state.plots, world_speed, state.besieged, bonuses)
	var troops := upkeep_per_hour(data, units_fed(state), world_speed) * maxf(0.0, 1.0 + bonus(bonuses, "upkeep"))
	var upkeep := troops + float(state.adminUpkeep) * world_speed
	rates.grain = rates.grain - upkeep
	return rates


static func capacity(data: Dictionary, levels: Dictionary, bonuses: Dictionary) -> Dictionary:
	var storehouse: Dictionary = data.buildings.buildings.get("storehouse", {})
	var level := int(levels.get("storehouse", 0))
	var cap := float(data.buildings.village.baseCapacity) * pow(float(storehouse.get("capacityGrowth", 1)), level) * (1.0 + bonus(bonuses, "storage"))
	return resources(func(_kind: String) -> float: return cap)


## A fresh village (the first one; founded ones come with the expansion port).
static func new_village(data: Dictionary, at: int, world_speed: float) -> Dictionary:
	var plots := initial_plots(data)
	var state := {
		"plots": plots,
		"levels": levels_of(plots),
		"queue": [],
		"garrison": {},
		"training": [],
		"away": {},
		"stance": "balanced",
		"besieged": false,
		"adminUpkeep": 0,
		"bonuses": {},
	}
	state.ledger = {
		"amounts": data.buildings.village.startingResources.duplicate(),
		"ratesPerHour": village_rates(data, state, world_speed),
		"capacity": capacity(data, state.levels, state.bonuses),
		"settledAt": at,
	}
	return state


## The owner's bonuses changed: new rates and capacity from `at`.
static func with_bonuses(data: Dictionary, state: Dictionary, bonuses: Dictionary, at: int, world_speed: float) -> Dictionary:
	var next := state.duplicate(true)
	next.bonuses = bonuses
	next.ledger = LocalLedger.with_rates(state.ledger, at, village_rates(data, next, world_speed), capacity(data, state.levels, bonuses))
	return next


# --- Commands (village.ts). Failures return {"error": message}. ---------------

static func rule(message: String) -> Dictionary:
	return {"error": message, "kind": "rule"}


static func build_def(data: Dictionary, building: String) -> Variant:
	return data.buildings.buildings.get(building)


## "o3,-2" -> Vector2i(3, -2); Vector2i.MAX for other plots.
static func outpost_hex(plot: String) -> Vector2i:
	var m := RegEx.create_from_string("^o(-?\\d+),(-?\\d+)$").search(plot)
	return Vector2i(int(m.get_string(1)), int(m.get_string(2))) if m else Vector2i.MAX


static func outpost_plot(cell: Vector2i) -> String:
	return "o%d,%d" % [cell.x, cell.y]


static func outpost_plots(plots: Dictionary) -> Array:
	return plots.keys().filter(func(id: String) -> bool: return outpost_hex(id) != Vector2i.MAX)


static func tower_index(plot: String) -> int:
	var m := RegEx.create_from_string("^t(\\d+)$").search(plot)
	return int(m.get_string(1)) if m else -1


static func open_tower_slots(data: Dictionary, wall_level: int) -> int:
	return data.walls.slotsAt.filter(func(at: Variant) -> bool: return wall_level >= int(at)).size()


static func unlocked_slots(data: Dictionary, hall: int) -> int:
	var v: Dictionary = data.buildings.village
	return mini(int(v.centerSlots), int(v.slotsUnlockedAtStart) + int(v.slotsPerHallLevel) * maxi(0, hall - 1))


static func build_queue_limit(data: Dictionary, hall: int) -> int:
	var v: Dictionary = data.buildings.village
	return int(v.baseQueueLimit) + floori(hall / float(v.hallLevelsPerQueueSlot))


static func outpost_limit(data: Dictionary, hall: int) -> int:
	var v: Dictionary = data.buildings.village
	return int(v.baseOutposts) + floori(hall / float(v.hallLevelsPerOutpost))


static func level_cost(def: Dictionary, target_level: int) -> Dictionary:
	var factor := pow(float(def.costGrowth), target_level - 1)
	return resources(func(kind: String) -> int: return LocalWaves.js_round(float(def.cost[kind]) * factor))


static func build_seconds(def: Dictionary, target_level: int, world_speed: float, speedup := 1.0) -> float:
	return (float(def.buildSeconds) * pow(float(def.timeGrowth), target_level - 1) * speedup) / world_speed


static func hall_speedup(data: Dictionary, hall: int) -> float:
	return pow(float(data.buildings.village.hallBuildSpeedup), maxi(0, hall - 1))


static func time_factor(bonuses: Dictionary, key: String) -> float:
	return maxf(0.1, 1.0 + bonus(bonuses, key))


static func train_factor(bonuses: Dictionary, unit: String) -> float:
	return maxf(0.1, 1.0 + bonus(bonuses, "trainTime") + bonus(bonuses, "trainTime.%s" % unit))


static func has_clan(bonuses: Dictionary, clan: String) -> bool:
	return bonus(bonuses, "clan.%s" % clan) > 0


static func clan_name(data: Dictionary, clan: String) -> String:
	return String(data.clans.clans.get(clan, {}).get("name", clan))


## What a plot will hold once everything queued completes.
static func planned_plot(state: Dictionary, plot: String) -> Dictionary:
	for i in range(state.queue.size() - 1, -1, -1):
		var item: Dictionary = state.queue[i]
		if item.plot == plot:
			return {"building": item.building, "level": item.targetLevel}
	return state.plots[plot]


static func _unlocked_slot(data: Dictionary, plot: String, hall: int) -> bool:
	return plot.begins_with("c") and int(plot.substr(1)) < unlocked_slots(data, hall)


## Turns an order ({plot?, building?}) into a plot, or {"error"}.
static func _resolve_plot(data: Dictionary, state: Dictionary, order: Dictionary, hall: int) -> Variant:
	if order.get("plot") != null:
		return order.plot
	if order.get("building") == null:
		return rule("Say which plot or building to build")
	var def: Variant = build_def(data, order.building)
	if def == null:
		return rule("Unknown building \"%s\"" % order.building)
	if def.kind == "outpost":
		return rule("Pick a hex for the outpost")
	var ids: Array = state.plots.keys()
	if def.kind == "field":
		var fields := ids.filter(func(id: String) -> bool: return planned_plot(state, id).building == order.building)
		# A stable sort by planned level, as V8's.
		var sorted: Array = []
		for id in fields:
			var at := sorted.size()
			for i in sorted.size():
				if int(planned_plot(state, id).level) < int(planned_plot(state, sorted[i]).level):
					at = i
					break
			sorted.insert(at, id)
		if sorted.is_empty():
			return rule("This village has no %s fields" % def.name)
		return sorted[0]
	if def.kind == "wall":
		return WALL_PLOT
	for id in ids:
		if planned_plot(state, id).building == order.building:
			return id
	if def.kind == "tower":
		var open := open_tower_slots(data, int(planned_plot(state, WALL_PLOT).level) if state.plots.has(WALL_PLOT) else 0)
		for id in ids:
			var t := tower_index(id)
			if (t if t >= 0 else open) < open and planned_plot(state, id).building == null:
				return id
		return rule("No free wall slot; raise the walls")
	for id in ids:
		if _unlocked_slot(data, id, hall) and planned_plot(state, id).building == null:
			return id
	return rule("No free building slot; upgrade the Elder's Hall")


## Pays for and queues a build: {state, queued} or {"error"}.
static func queue_build(data: Dictionary, state: Dictionary, order: Dictionary, at: int, world_speed: float) -> Dictionary:
	var hall := int(state.levels.get(HALL, 0))
	if state.queue.size() >= build_queue_limit(data, hall):
		return rule("Build queue is full")
	var resolved: Variant = _resolve_plot(data, state, order, hall)
	if resolved is Dictionary:
		return resolved
	var plot: String = resolved
	if not state.plots.has(plot):
		return rule("No plot \"%s\"" % plot)
	var planned := planned_plot(state, plot)
	var building: String
	if planned.building != null:
		building = planned.building
		if order.get("building") != null and order.building != building:
			return rule("That plot holds a %s" % build_def(data, building).name)
	else:
		var slot := tower_index(plot)
		var wall_level := int(planned_plot(state, WALL_PLOT).level) if state.plots.has(WALL_PLOT) else 0
		if slot >= 0 and slot >= open_tower_slots(data, wall_level):
			return rule("That wall slot is not open yet; raise the walls")
		if slot < 0 and not _unlocked_slot(data, plot, hall):
			return rule("That slot is locked; upgrade the Elder's Hall")
		if order.get("building") == null:
			return rule("Say which building to construct")
		building = order.building
		var def: Variant = build_def(data, building)
		if def == null:
			return rule("Unknown building \"%s\"" % building)
		if slot >= 0 and def.kind != "tower":
			return rule("%s is not built on the walls" % def.name)
		if slot < 0 and def.kind == "tower":
			return rule("%s is built in a wall slot" % def.name)
		if slot < 0 and def.kind != "center":
			return rule("%s is built on fields, not in the village" % def.name)
		if def.get("clan") != null and not has_clan(state.bonuses, def.clan):
			return rule("Only %s can build a %s" % [clan_name(data, def.clan), def.name])
		for id in state.plots:
			if id != plot and planned_plot(state, id).building == building:
				return rule("This village already has a %s" % def.name)
	var def: Dictionary = build_def(data, building)
	var target := int(planned.level) + 1
	if target > int(def.maxLevel):
		return rule("%s is already at max level" % def.name)
	var ledger := LocalLedger.spend(state.ledger, at, level_cost(def, target))
	if ledger.has("missing"):
		return ledger
	var starts_at: int = int(state.queue[-1].completesAt) if not state.queue.is_empty() else at
	var seconds := build_seconds(def, target, world_speed, hall_speedup(data, hall) * time_factor(state.bonuses, "buildTime"))
	var queued := {"plot": plot, "building": building, "targetLevel": target, "startsAt": starts_at, "completesAt": LocalTime.ms(starts_at + seconds * 1000.0)}
	var next := state.duplicate(true)
	next.ledger = ledger
	next.queue.append(queued)
	return {"state": next, "queued": queued}


## Applies the head of the queue at its scheduled completion time.
static func complete_build(data: Dictionary, state: Dictionary, plot: String, target: int, at: int, world_speed: float) -> Dictionary:
	if state.queue.is_empty() or state.queue[0].plot != plot or int(state.queue[0].targetLevel) != target:
		return rule("Build on %s to level %d is not at the head of the queue" % [plot, target])
	var head: Dictionary = state.queue[0]
	var next := state.duplicate(true)
	var before: Dictionary = next.plots.get(plot, {})
	var built := before.duplicate()
	built.building = head.building
	built.level = target
	if outpost_hex(plot) != Vector2i.MAX:
		built.peak = maxi(int(before.get("peak", 0)), target)
	next.plots[plot] = built
	next.levels = levels_of(next.plots)
	next.queue.pop_front()
	next.ledger = LocalLedger.with_rates(state.ledger, at, village_rates(data, next, world_speed), capacity(data, next.levels, state.bonuses))
	return next


## Claims a resource hex and queues its outpost: {state, queued} or {"error"}.
## `site`: {cell, terrain, home, taken: {"q,r": true}}.
static func claim_outpost(data: Dictionary, state: Dictionary, site: Dictionary, at: int, world_speed: float) -> Dictionary:
	var def: Dictionary = build_def(data, OUTPOST)
	var range_ := int(data.buildings.village.outpostRange)
	var distance := HexMath.distance(site.cell, site.home)
	if distance == 0 or distance > range_:
		return rule("Outposts go within %d hexes of the village" % range_)
	if def.get("yields", {}).get(site.terrain) == null:
		return rule("Nothing to gather on %s" % data.terrain.terrain[site.terrain].name)
	if site.taken.has(LocalLand.key(site.cell)):
		return rule("That hex is already taken")
	var limit := outpost_limit(data, int(state.levels.get(HALL, 0)))
	if outpost_plots(state.plots).size() >= limit:
		return rule("This village can hold %d outpost%s; upgrade the Elder's Hall for more" % [limit, "" if limit == 1 else "s"])
	var plot := outpost_plot(site.cell)
	var claimed := state.duplicate(true)
	claimed.plots[plot] = {"building": OUTPOST, "level": 0, "terrain": site.terrain}
	return queue_build(data, claimed, {"plot": plot}, at, world_speed)


static func abandon_outpost(data: Dictionary, state: Dictionary, plot: String, at: int, world_speed: float) -> Dictionary:
	if outpost_hex(plot) == Vector2i.MAX or not state.plots.has(plot):
		return rule("No outpost there")
	for item in state.queue:
		if item.plot == plot:
			return rule("The outpost is being built; wait for it to finish")
	var next := state.duplicate(true)
	next.plots.erase(plot)
	next.ledger = LocalLedger.with_rates(state.ledger, at, village_rates(data, next, world_speed), state.ledger.capacity)
	return next


# --- Training (village.ts, training.ts) -------------------------------------------

static func batch_completes_at(batch: Dictionary) -> int:
	return int(batch.startsAt) + int(batch.count) * int(batch.perUnitMs)


static func per_unit_ms(data: Dictionary, unit: String, building_level: int, world_speed: float, factor := 1.0) -> int:
	var def: Dictionary = data.units.units[unit]
	var speedup := pow(float(data.units.trainingSpeedup), maxi(0, building_level - 1)) * factor
	return maxi(1, LocalWaves.js_round((float(def.trainSeconds) * 1000.0 * speedup) / world_speed))


static func unit_cost(data: Dictionary, unit: String, count: int, villages_owned := 1) -> Dictionary:
	var def: Dictionary = data.units.units[unit]
	var factor := pow(float(def.get("costGrowthPerVillage", 1) if def.get("costGrowthPerVillage") != null else 1), maxi(0, villages_owned - 1))
	return resources(func(kind: String) -> int: return LocalWaves.js_round(float(def.cost[kind]) * factor) * count)


static func queue_training(data: Dictionary, state: Dictionary, unit: String, count: int, at: int, world_speed: float, villages_owned := 1) -> Dictionary:
	var def: Variant = data.units.units.get(unit)
	if def == null:
		return rule("Unknown unit \"%s\"" % unit)
	if count < 1 or count > int(data.units.maxBatch):
		return rule("Train between 1 and %d at a time" % int(data.units.maxBatch))
	if def.get("clan") != null and not has_clan(state.bonuses, def.clan):
		return rule("Only %s can train a %s" % [clan_name(data, def.clan), def.name])
	var level := int(state.levels.get(def.building, 0))
	if level < int(def.requiresLevel):
		return rule("%s needs %s level %d" % [def.name, build_def(data, def.building).name, int(def.requiresLevel)])
	if state.training.size() >= int(data.units.trainingQueueLimit):
		return rule("Training queue is full")
	var paid := LocalLedger.spend(state.ledger, at, unit_cost(data, unit, count, villages_owned))
	if paid.has("missing"):
		return paid
	var starts_at := at
	if not state.training.is_empty() and batch_completes_at(state.training[-1]) > at:
		starts_at = batch_completes_at(state.training[-1])
	var batch := {"unit": unit, "count": count, "startsAt": starts_at,
		"perUnitMs": per_unit_ms(data, unit, level, world_speed, train_factor(village_bonuses(data, state), unit))}
	var next := state.duplicate(true)
	next.training.append(batch)
	next.ledger = LocalLedger.with_rates(paid, at, village_rates(data, next, world_speed), paid.capacity)
	return {"state": next, "batch": batch}


## Moves units trained by `at` into the garrison.
static func complete_training(state: Dictionary, at: int) -> Dictionary:
	var finished := {}
	var remaining: Array = []
	for batch in state.training:
		var elapsed := at - int(batch.startsAt)
		var done := maxi(0, mini(int(batch.count), floori(elapsed / float(batch.perUnitMs))))
		if done > 0:
			finished[batch.unit] = int(finished.get(batch.unit, 0)) + done
		if done < int(batch.count):
			var left: Dictionary = batch.duplicate()
			left.count = int(batch.count) - done
			left.startsAt = int(batch.startsAt) + done * int(batch.perUnitMs)
			remaining.append(left)
	var next := state.duplicate(true)
	next.garrison = add_units(state.garrison, finished)
	next.training = remaining
	return next
