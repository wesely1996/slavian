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
