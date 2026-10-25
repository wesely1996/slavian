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
const MARKET := "market"
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

## A founded village's fields follow the land within outpostRange (server
## fieldsFromLand): one of every kind, the rest shared out by what the
## outposts' yields say the land gives; land yielding nothing stays balanced.
static func fields_from_land(data: Dictionary, around: Array) -> Array:
	var balanced: Array = data.buildings.village.fields
	var kinds: Array = []
	for kind in balanced:
		if not kind in kinds:
			kinds.append(kind)
	var yields: Dictionary = data.buildings.buildings.outpost.get("yields", {})
	var weights: Array = []
	var total := 0
	for kind in kinds:
		var resource: String = data.buildings.buildings[kind].production.resource
		var w := 0
		for t in around:
			if t != null:
				w += int(yields.get(t, {}).get(resource, 0))
		weights.append(w)
		total += w
	var extra := balanced.size() - kinds.size()
	if total == 0 or extra < 0:
		return balanced.duplicate()
	var counts: Array = []
	var left := balanced.size()
	for i in kinds.size():
		counts.append(1 + int(weights[i] * extra / total))
		left -= counts[i]
	var order: Array = range(kinds.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		var ra: int = (weights[a] * extra) % total
		var rb: int = (weights[b] * extra) % total
		return ra > rb or (ra == rb and a < b))
	for i in order:
		if left <= 0:
			break
		counts[i] += 1
		left -= 1
	var out: Array = []
	for i in kinds.size():
		for n in counts[i]:
			out.append(kinds[i])
	return out


## The terrain of the hexes around a village's site (not its own).
static func land_around(data: Dictionary, hexes: Dictionary, cell: Vector2i) -> Array:
	var out: Array = []
	for h in HexMath.spiral(cell, int(data.buildings.village.outpostRange)).slice(1):
		out.append(hexes.get(LocalLand.key(h)))
	return out


static func initial_plots(data: Dictionary, fields: Array = []) -> Dictionary:
	var v: Dictionary = data.buildings.village
	if fields.is_empty():
		fields = v.fields
	var plots := {}
	for i in fields.size():
		plots[field_plot(i)] = {"building": fields[i], "level": 0}
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


## Every storehouse adds what it holds above the base.
static func capacity(data: Dictionary, plots: Dictionary, bonuses: Dictionary) -> Dictionary:
	var growth := float(data.buildings.buildings.get("storehouse", {}).get("capacityGrowth", 1))
	var factor := 1.0
	for id in plots:
		var plot: Dictionary = plots[id]
		if plot.building == "storehouse" and int(plot.level) > 0 and outpost_hex(id) == Vector2i.MAX:
			factor += pow(growth, int(plot.level)) - 1.0
	var cap := float(data.buildings.village.baseCapacity) * factor * (1.0 + bonus(bonuses, "storage"))
	return resources(func(_kind: String) -> float: return cap)


## Research the village's Academy brings in per hour (world speed applied).
static func research_per_hour(data: Dictionary, plots: Dictionary, world_speed: float) -> float:
	var rate := 0.0
	for plot in plots.values():
		if plot.building == null or int(plot.level) <= 0:
			continue
		var research: Variant = data.buildings.buildings.get(plot.building, {}).get("research")
		if research != null:
			rate += float(research.basePerHour) * pow(float(research.growth), int(plot.level) - 1) * world_speed
	return rate


## A fresh village (the first one; founded ones come with the expansion port).
## `founded`: for a village founded later, {startingResources, adminUpkeep,
## bonuses, fields?}.
static func new_village(data: Dictionary, at: int, world_speed: float, founded: Dictionary = {}) -> Dictionary:
	var plots := initial_plots(data, founded.get("fields", []))
	var state := {
		"plots": plots,
		"levels": levels_of(plots),
		"queue": [],
		"garrison": {},
		"training": [],
		"away": {},
		"stance": "balanced",
		"besieged": false,
		"adminUpkeep": founded.get("adminUpkeep", 0),
		"bonuses": founded.get("bonuses", {}),
	}
	state.ledger = {
		"amounts": founded.get("startingResources", data.buildings.village.startingResources).duplicate(),
		"ratesPerHour": village_rates(data, state, world_speed),
		"capacity": capacity(data, plots, state.bonuses),
		"settledAt": at,
	}
	return state


## The owner's bonuses changed: new rates and capacity from `at`.
static func with_bonuses(data: Dictionary, state: Dictionary, bonuses: Dictionary, at: int, world_speed: float) -> Dictionary:
	var next := state.duplicate(true)
	next.bonuses = bonuses
	next.ledger = LocalLedger.with_rates(state.ledger, at, village_rates(data, next, world_speed), capacity(data, state.plots, bonuses))
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
		if not def.get("multiple", false):
			for id in state.plots:
				if id != plot and planned_plot(state, id).building == building:
					return rule("This village already has a %s" % def.name)
		var requires: Dictionary = def.get("requires", {}) if def.get("requires") != null else {}
		for needed in requires:
			if int(state.levels.get(needed, 0)) < int(requires[needed]):
				return rule("%s needs %s level %d" % [def.name, build_def(data, needed).name, int(requires[needed])])
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
	next.ledger = LocalLedger.with_rates(state.ledger, at, village_rates(data, next, world_speed), capacity(data, next.plots, state.bonuses))
	return next


## Everything a building of `level` cost to raise, level by level.
static func built_cost(def: Dictionary, level: int) -> Dictionary:
	var sum := resources(func(_kind: String) -> int: return 0)
	for l in range(1, level + 1):
		var cost := level_cost(def, l)
		for kind in KINDS:
			sum[kind] += cost[kind]
	return sum


## What tearing down everything that stands on `plots` gives back.
static func refund_of(data: Dictionary, plots: Dictionary, share: float) -> Dictionary:
	var sum := resources(func(_kind: String) -> int: return 0)
	for plot in plots.values():
		var def: Variant = build_def(data, plot.building) if plot.building != null else null
		if def == null or int(plot.level) <= 0:
			continue
		var cost := built_cost(def, int(plot.level))
		for kind in KINDS:
			sum[kind] += cost[kind]
	return resources(func(kind: String) -> int: return floori(sum[kind] * share))


## Tears down the building on a center or wall slot, for a share of what it
## cost: {state, refund} or {"error"}.
static func demolish(data: Dictionary, state: Dictionary, plot: String, at: int, world_speed: float) -> Dictionary:
	var current: Variant = state.plots.get(plot)
	if current == null or current.building == null or int(current.level) <= 0:
		return rule("Nothing stands there to tear down")
	var def: Dictionary = build_def(data, current.building)
	if current.building == HALL:
		return rule("The Elder's Hall can't be torn down")
	if def.kind != "center" and def.kind != "tower":
		return rule("The %s can't be torn down" % def.name)
	for item in state.queue:
		if item.plot == plot:
			return rule("The %s is being built; wait for it to finish" % def.name)
	var refund := refund_of(data, {plot: current}, float(data.buildings.village.demolishRefund))
	var next := state.duplicate(true)
	next.plots[plot] = {"building": null, "level": 0}
	next.levels = levels_of(next.plots)
	var ledger := LocalLedger.with_rates(state.ledger, at, village_rates(data, next, world_speed), capacity(data, next.plots, state.bonuses))
	next.ledger = LocalLogistics.receive(ledger, at, refund).ledger
	return {"state": next, "refund": refund}


static func market_rate(data: Dictionary, market_level: int) -> float:
	var market: Dictionary = data.buildings.village.market
	return float(market.baseRate) + float(market.ratePerLevel) * (market_level - 1) if market_level > 0 else 0.0


## Trades `amount` of `give` for `get` at the Market: {state, got} or {"error"}.
static func trade(data: Dictionary, state: Dictionary, give: String, get: String, amount: int, at: int) -> Dictionary:
	var rate := market_rate(data, int(state.levels.get(MARKET, 0)))
	if rate <= 0:
		return rule("Build a Market to trade")
	if give == get:
		return rule("Trade one resource for another")
	if amount < 1:
		return rule("Trade at least 1")
	var got := floori(amount * rate)
	if got < 1:
		return rule("Too little to fetch anything")
	var paid := LocalLedger.spend(state.ledger, at, resources(func(kind: String) -> int: return amount if kind == give else 0))
	if paid.has("missing"):
		return paid
	var next := state.duplicate(true)
	next.ledger = LocalLogistics.receive(paid, at, resources(func(kind: String) -> int: return got if kind == get else 0)).ledger
	return {"state": next, "got": got}


## The Market buys a piece of spare gear: {state} or {"error"}.
static func sell_gear(data: Dictionary, state: Dictionary, at: int) -> Dictionary:
	if int(state.levels.get(MARKET, 0)) <= 0:
		return rule("Build a Market to sell gear")
	var next := state.duplicate(true)
	next.ledger = LocalLogistics.receive(state.ledger, at, data.buildings.village.market.gearValue).ledger
	return {"state": next}


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


# --- Battles (village.ts) -------------------------------------------------------

## A breach knocks the walls down (walls.json breachLevelsLost).
static func breach_walls(data: Dictionary, state: Dictionary) -> Dictionary:
	var wall: Variant = state.plots.get(WALL_PLOT)
	if wall == null or int(wall.level) <= 0:
		return state
	var next := state.duplicate(true)
	next.plots[WALL_PLOT].level = maxi(0, int(wall.level) - int(data.walls.breachLevelsLost))
	next.levels = levels_of(next.plots)
	return next


## A passing horde burns an outpost down a level.
static func raid_outpost(data: Dictionary, state: Dictionary, plot: String, at: int, world_speed: float) -> Dictionary:
	var current: Variant = state.plots.get(plot)
	if outpost_hex(plot) == Vector2i.MAX or current == null or int(current.level) <= 0:
		return state
	var next := state.duplicate(true)
	next.plots[plot].level = int(current.level) - 1
	next.ledger = LocalLedger.with_rates(state.ledger, at, village_rates(data, next, world_speed), state.ledger.capacity)
	return next


static func set_besieged(data: Dictionary, state: Dictionary, besieged: bool, at: int, world_speed: float) -> Dictionary:
	if state.besieged == besieged:
		return state
	var next := state.duplicate(true)
	next.besieged = besieged
	next.ledger = LocalLedger.with_rates(state.ledger, at, village_rates(data, next, world_speed), state.ledger.capacity)
	return next


## Units away that will never come back: they stop eating now.
static func lose_away(data: Dictionary, state: Dictionary, unit: String, count: int, at: int, world_speed: float) -> Dictionary:
	var next := state.duplicate(true)
	next.away[unit] = maxi(0, int(state.away.get(unit, 0)) - count)
	next.ledger = LocalLedger.with_rates(state.ledger, at, village_rates(data, next, world_speed), state.ledger.capacity)
	return next


## Garrison losses in battle: the dead stop eating from `at`.
static func lose_garrison(data: Dictionary, state: Dictionary, losses: Dictionary, at: int, world_speed: float) -> Dictionary:
	var next := state.duplicate(true)
	for unit in losses:
		next.garrison[unit] = maxi(0, int(next.garrison.get(unit, 0)) - int(losses[unit]))
	next.ledger = LocalLedger.with_rates(state.ledger, at, village_rates(data, next, world_speed), state.ledger.capacity)
	return next


## Of the garrison's fallen (`lost`), those its hospital saves: each gets up
## again with the hospital's chance, drawn unit by unit (by name).
static func hospital_healed(bonuses: Dictionary, lost: Dictionary, rng: LocalRng) -> Dictionary:
	var chance := minf(1.0, bonus(bonuses, "hospital"))
	var healed := {}
	if chance <= 0:
		return healed
	var units: Array = lost.keys()
	units.sort()
	for unit in units:
		var saved := 0
		for i in int(lost[unit]):
			if rng.next() < chance:
				saved += 1
		if saved > 0:
			healed[unit] = saved
	return healed


## Soldiers joining the garrison (back on their feet, or moved in).
static func join_garrison(data: Dictionary, state: Dictionary, units: Dictionary, at: int, world_speed: float) -> Dictionary:
	var next := state.duplicate(true)
	next.garrison = add_units(state.garrison, units)
	next.ledger = LocalLedger.with_rates(state.ledger, at, village_rates(data, next, world_speed), state.ledger.capacity)
	return next


static func plunder(state: Dictionary, loot: Dictionary, at: int) -> Dictionary:
	var next := state.duplicate(true)
	next.ledger = LocalLedger.take(state.ledger, at, loot)
	return next


## Sends `count` units away from home (finished training counts as home):
## {"error"} when there aren't that many.
static func send_away(state: Dictionary, unit: String, count: int, at: int) -> Dictionary:
	var settled := complete_training(state, at)
	var home := int(settled.garrison.get(unit, 0))
	if home < count:
		return rule("Only %d %s at home" % [home, unit])
	settled.garrison[unit] = home - count
	settled.away = add_units(settled.away, {unit: count})
	return settled


## Units coming home from a mission.
static func return_home(state: Dictionary, unit: String, count: int) -> Dictionary:
	var next := state.duplicate(true)
	next.away[unit] = maxi(0, int(state.away.get(unit, 0)) - count)
	next.garrison = add_units(state.garrison, {unit: count})
	return next



# --- Expansion (expansion.ts) -------------------------------------------------------

## Why settlers can't found a village at `cell` ("" when they can).
static func settle_problem(data: Dictionary, cell: Vector2i, terrain: Variant, home: Vector2i, villages: Array, outposts: Dictionary) -> String:
	var rules: Dictionary = data.expansion
	if terrain == null:
		return "That hex is not on the map"
	if not data.terrain.terrain[terrain].settleable:
		return "Villages can't be founded on %s" % data.terrain.terrain[terrain].name
	if HexMath.distance(cell, home) > int(rules.maxDistance):
		return "Settlers walk at most %d hexes from their village" % int(rules.maxDistance)
	if HexMath.distance(cell, Vector2i.ZERO) < int(rules.minHolyCityDistance):
		return "Too close to the Holy City"
	if villages.any(func(v: Vector2i) -> bool: return HexMath.distance(v, cell) < int(rules.minVillageDistance)):
		return "Villages stand at least %d hexes apart" % int(rules.minVillageDistance)
	if outposts.has(LocalLand.key(cell)):
		return "An outpost stands there"
	return ""


static func admin_upkeep_for(data: Dictionary, villages_owned: int) -> float:
	return float(data.expansion.adminUpkeepPerVillage) * villages_owned
