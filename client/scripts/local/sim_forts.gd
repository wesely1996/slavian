class_name LocalForts
## Forts as strongholds (sim/forts.ts and scheduler/forts.ts, forts.json):
## the Keep, the Storage and three wall rings with their towers, built one
## level at a time and paid from the village that built the fort; the
## Keep's zone of influence; the grain its Storage keeps and what it eats.


static func starting_plots() -> Dictionary:
	return {"keep": {"kind": "keep", "level": 1}, "storage": {"kind": "storage", "level": 1}}


static func level_of(plots: Dictionary, plot: String) -> int:
	return int(plots.get(plot, {}).get("level", 0))


static func _is_wall(plot: String) -> bool:
	return plot.length() == 2 and plot[0] == "w" and plot[1] in ["0", "1", "2"]


static func _is_tower(plot: String) -> bool:
	if plot.length() < 4 or plot[0] != "t" or not (plot[1] in ["0", "1", "2"]) or plot[2] != "-":
		return false
	return plot.substr(3).is_valid_int() and not plot.substr(3).begins_with("+") and not plot.substr(3).begins_with("-")


## The ring a wall or tower plot belongs to (0 inner, 2 outer), or -1.
static func ring_of(plot: String) -> int:
	return int(plot[1]) if _is_wall(plot) or _is_tower(plot) else -1


## Every plot of a fort, in order (sim/forts.ts fortPlotIds).
static func plot_ids(data: Dictionary) -> Array:
	var out := ["keep", "storage", "garrison"]
	var rings: Array = data.forts.rings
	for i in rings.size():
		out.append("w%d" % i)
		for s in int(rings[i].slots):
			out.append("t%d-%d" % [i, s])
	return out


## The building a plot holds or would hold (fortBuildingDef), or {}.
static func building_def(data: Dictionary, plot: String, kind: String) -> Dictionary:
	if plot == "keep" or plot == "storage" or plot == "garrison":
		return data.forts.buildings[plot] if kind == plot else {}
	var ring := ring_of(plot)
	if ring < 0:
		return {}
	var wall := _is_wall(plot)
	var def: Dictionary = data.buildings.buildings.get(kind, {})
	if def.is_empty() or def.kind != ("wall" if wall else "tower"):
		return {}
	if not wall and not data.walls.towers.has(kind):
		return {}
	var factor := float(data.forts.rings[ring].costFactor)
	return {"name": def.name, "cost": LocalVillage.resources(func(k: String) -> int: return LocalWaves.js_round(float(def.cost[k]) * factor)),
		"costGrowth": def.costGrowth, "buildSeconds": def.buildSeconds, "timeGrowth": def.timeGrowth,
		"maxLevel": data.forts.wallMaxLevel if wall else data.forts.towerMaxLevel}


static func level_cost(def: Dictionary, level: int) -> Dictionary:
	var factor := pow(float(def.costGrowth), level - 1)
	return LocalVillage.resources(func(kind: String) -> int: return LocalWaves.js_round(float(def.cost[kind]) * factor))


## Real-time milliseconds.
static func build_ms(def: Dictionary, level: int, world_speed: float) -> int:
	return LocalWaves.js_round((float(def.buildSeconds) * pow(float(def.timeGrowth), level - 1) * 1000.0) / world_speed)


## Why `kind` can't rise a level on `plot` ("" when it can).
static func build_problem(data: Dictionary, plots: Dictionary, work: Variant, plot: String, kind: String) -> String:
	if work != null:
		return "Something is already being built in this fort"
	var def := building_def(data, plot, kind)
	if def.is_empty():
		return "That cannot be built there"
	var now: Variant = plots.get(plot)
	if now != null and now.kind != kind:
		return "Something else stands there"
	var level := (int(now.level) if now != null else 0) + 1
	if level > int(def.maxLevel):
		return "It is at its highest level"
	var ring := ring_of(plot)
	if ring >= 0:
		var rule: Dictionary = data.forts.rings[ring]
		if level_of(plots, "keep") < int(rule.keepLevel):
			return "The %s needs the Keep at level %d" % [String(rule.name).to_lower(), int(rule.keepLevel)]
		if not _is_wall(plot):
			var wall := level_of(plots, "w%d" % ring)
			if wall == 0:
				return "Build the wall first"
			if level > wall:
				return "A tower cannot rise above its wall"
			if int(plot.substr(3)) >= int(rule.slots):
				return "That cannot be built there"
	return ""


## How far the Keep's zone of influence reaches.
static func zone_radius(data: Dictionary, plots: Dictionary) -> int:
	var keep := level_of(plots, "keep")
	if keep == 0:
		return 0
	return int(data.forts.zone.base) + floori(float(keep - 1) / float(data.forts.zone.every))


## Whether `cell` lies in the zone of a standing fort built by `village_id`.
static func in_zone(data: Dictionary, forts: Array, village_id: int, cell: Vector2i) -> bool:
	for f in forts:
		if f.get("kind", "fort") == "fort" and f.status == "standing" and f.villageId != null and int(f.villageId) == village_id \
				and HexMath.distance(cell, Vector2i(int(f.q), int(f.r))) <= zone_radius(data, f.get("plots", {})):
			return true
	return false


## The grain a fort or supply point keeps at most.
static func grain_capacity(data: Dictionary, fort: Dictionary) -> float:
	if fort.get("kind", "fort") == "supply":
		return float(data.field.supplyPoint.grainCapacity)
	return float(data.forts.storage.grainBase) + float(data.forts.storage.grainPerLevel) * level_of(fort.get("plots", {}), "storage")


## The grain a standing fort eats a game hour (its defenders' too).
static func upkeep(data: Dictionary, plots: Dictionary, defenders := {}) -> float:
	var men := 0
	for unit in defenders:
		men += int(defenders[unit])
	return float(data.forts.upkeep.grainPerHour) + float(data.forts.upkeep.perKeepLevel) * level_of(plots, "keep") + float(data.forts.upkeep.perDefender) * men


## The defenders the Fort Garrison keeps at its level.
static func defenders_wanted(data: Dictionary, plots: Dictionary) -> Dictionary:
	var level := level_of(plots, "garrison")
	var out := {}
	for unit in data.forts.garrison.perLevel:
		var n := int(data.forts.garrison.perLevel[unit]) * level
		if n > 0:
			out[unit] = n
	return out


## `count` fallen defenders come back, one at a time, each the kind most
## short (sim/forts.ts musterDefenders).
static func muster(data: Dictionary, plots: Dictionary, defenders: Dictionary, count: int) -> Dictionary:
	var wanted := defenders_wanted(data, plots)
	var out := {}
	for unit in defenders:
		if int(defenders[unit]) > 0 and int(wanted.get(unit, 0)) > 0:
			out[unit] = mini(int(defenders[unit]), int(wanted[unit]))
	for i in count:
		var best := ""
		var short := 0
		for unit in data.forts.garrison.perLevel:
			var gap := int(wanted.get(unit, 0)) - int(out.get(unit, 0))
			if gap > short:
				best = unit
				short = gap
		if best == "":
			break
		out[best] = int(out.get(best, 0)) + 1
	return out


static func is_manned(fort: Dictionary) -> bool:
	for unit in fort.get("defenders", {}):
		if int(fort.defenders[unit]) > 0:
			return true
	return false


## A wall ring's plots as a village's (sim/walls.ts): "w" and "t0"...
## sim/forts.ts ringPlots: each fort level is half a village level (rounded up).
static func ring_plots(plots: Dictionary, ring: int) -> Dictionary:
	var out := {}
	var wall: Variant = plots.get("w%d" % ring)
	if wall != null:
		out["w"] = {"building": "wall", "level": ceili(int(wall.level) / 2.0)}
	for id in plots:
		if _is_tower(id) and int(String(id)[1]) == ring:
			out["t" + String(id).substr(3)] = {"building": plots[id].kind, "level": ceili(int(plots[id].level) / 2.0)}
	return out


## The rings a horde meets, outer to inner: those with walls built.
static func standing_rings(plots: Dictionary) -> Array:
	return [2, 1, 0].filter(func(r: int) -> bool: return level_of(plots, "w%d" % r) > 0)


# --- On the scheduler (scheduler/forts.ts) ------------------------------------------

## buildInFort: the fort, or {"error"} / {"missing"}.
static func build(server: LocalServer, world: Dictionary, fort: Dictionary, plot: String, kind: String, at: int) -> Dictionary:
	var data := server.data
	if fort.get("kind", "fort") != "fort":
		return LocalVillage.rule("Only a fort has buildings")
	if fort.status != "standing":
		return LocalVillage.rule("The fort is not finished yet")
	if fort.villageId == null:
		return LocalVillage.rule("The village that built this fort is gone")
	var problem := build_problem(data, fort.get("plots", {}), fort.get("work"), plot, kind)
	if problem != "":
		return LocalVillage.rule(problem)
	var def := building_def(data, plot, kind)
	var level := level_of(fort.plots, plot) + 1
	var village := server.find_village(world, int(fort.villageId))
	if village.is_empty() or village.get("ruin") != null:
		return LocalVillage.rule("The village that built this fort lies in ruins")
	var ledger := LocalLedger.spend(village.state.ledger, at, level_cost(def, level))
	if ledger.has("missing"):
		return ledger
	village.state.ledger = ledger
	var completes := at + build_ms(def, level, float(world.speed))
	fort.work = {"plot": plot, "kind": kind, "level": level, "completesAt": LocalTime.iso(completes)}
	server.schedule(world, completes, "fort_work_done", {"fortId": fort.id, "plot": plot, "level": level})
	return fort


## tearDownFort.
static func tear_down(world: Dictionary, fort: Dictionary) -> Dictionary:
	if fort.get("neutral", false):
		return LocalVillage.rule("That is nobody's to tear down")
	remove(world, fort)
	return {}


## Deletes a fort or supply point (the server's ON DELETE SET NULL clears
## rally points on it).
static func remove(world: Dictionary, fort: Dictionary) -> void:
	world.forts.erase(fort)
	for m in world.members:
		if m.get("rallyFortId") != null and int(m.rallyFortId) == int(fort.id):
			m.rallyFortId = null


static func on_work_done(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var p: Dictionary = event.payload
	var fort := LocalArmies.find_fort(world, int(p.fortId))
	var work: Variant = fort.get("work")
	if fort.is_empty() or work == null or work.plot != p.plot or int(work.level) != int(p.level):
		return
	fort.plots[work.plot] = {"kind": work.kind, "level": int(work.level)}
	fort.work = null
	var def := building_def(server.data, work.plot, work.kind)
	LocalInbox.tell(server, world, fort.ownerAccountId, {"kind": "build_done", "tier": "digest", "title": "{building} level {level} in the fort at ({q}, {r})",
		"body": "The fort can build again.", "vars": {"building": def.get("name", work.kind), "level": int(work.level), "q": fort.q, "r": fort.r}}, int(event.dueAt))
	changed.append(["world"])
