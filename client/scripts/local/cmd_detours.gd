class_name LocalDetours
extends RefCounted
## scheduler/detours.ts: a forest has caught fire; whatever is on the road
## and would enter it while it burns, a horde, an army, a caravan or
## settlers, finishes the hex it is crossing and goes round it to where it
## was going. With no way round (or the fire in the very next hex), it
## keeps its road.


## entersBefore: whether a road timed from `origin` still has to enter
## `cell` before `until` (a step after `at`).
static func enters_before(path: Array, origin: int, at: int, cell: Vector2i, until: int) -> bool:
	for s in path:
		var t := origin + int(s.atMs)
		if int(s.q) == cell.x and int(s.r) == cell.y and t > at and t < until:
			return true
	return false


## detour: the road from `elapsed_ms` along `path` round the fire, or null
## (no way round). Headed straight into the fire, it walks back to the hex
## before, as long as it had gone on, and goes round from there.
static func _detour(path: Array, elapsed_ms: int, cell: Vector2i, next: Callable) -> Variant:
	var i := path.size() - 1
	for k in path.size():
		if int(path[k].atMs) >= elapsed_ms:
			i = k
			break
	var ahead := Vector2i(int(path[i].q), int(path[i].r))
	if ahead != cell:
		var onward: Variant = next.call(ahead)
		return LocalLogistics.splice_route(path, elapsed_ms, func(_from: Vector2i) -> Variant: return onward) if onward != null else null
	if i == 0:
		return null
	var back: Dictionary = path[i - 1]
	var turn_at := elapsed_ms + (elapsed_ms - int(back.atMs))
	var turned: Variant = next.call(Vector2i(int(back.q), int(back.r)))
	if turned == null:
		return null
	var out: Array = path.slice(0, i)
	out.append({"q": back.q, "r": back.r, "atMs": turn_at})
	for k in range(1, turned.size()):
		out.append({"q": turned[k].q, "r": turned[k].r, "atMs": turn_at + int(turned[k].atMs)})
	return out


## hordeDetour: a horde's road round the fire (never back the way it came),
## or, with no way round, its road held at the fire's edge until it is out
## (`until_ms`, from its spawn).
static func horde_detour(path: Array, elapsed_ms: int, cell: Vector2i, until_ms: int, next: Callable) -> Array:
	var i := path.size() - 1
	for k in path.size():
		if int(path[k].atMs) >= elapsed_ms:
			i = k
			break
	var ahead: Dictionary = path[i]
	var into_fire := int(ahead.q) == cell.x and int(ahead.r) == cell.y and i > 0
	var from: Dictionary = path[i - 1] if into_fire else ahead
	var turn_at := elapsed_ms if into_fire else int(ahead.atMs)
	var onward: Variant = next.call(Vector2i(int(from.q), int(from.r)))
	if onward != null:
		var out: Array = path.slice(0, i - 1 if into_fire else i)
		out.append({"q": from.q, "r": from.r, "atMs": turn_at})
		for k in range(1, onward.size()):
			out.append({"q": onward[k].q, "r": onward[k].r, "atMs": turn_at + int(onward[k].atMs)})
		return out
	# No way round: it waits outside until the fire is out.
	var j := -1
	for k in range(i, path.size()):
		if int(path[k].q) == cell.x and int(path[k].r) == cell.y:
			j = k
			break
	var wait := maxi(0, until_ms - int(path[j].atMs)) if j >= 0 else 0
	var held: Array = []
	for k in path.size():
		var step: Dictionary = path[k].duplicate()
		if j >= 0 and k >= j:
			step.atMs = int(step.atMs) + wait
		held.append(step)
	return held


static func _by_departure(items: Array, key: String) -> Array:
	var out := items.duplicate()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a[key]) > int(b[key]) or (int(a[key]) == int(b[key]) and int(a.id) > int(b.id)))
	return out


static func avoid_fire(server: LocalServer, world: Dictionary, cell: Vector2i, until: int, at: int) -> void:
	var data := server.data
	var land := LocalHordes.land_of(world)
	# Hordes on the march: round it to their target.
	var waves: Array = world.waves.filter(func(w: Dictionary) -> bool: return not w.status in ["dispersed", "defeated", "settled"])
	waves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.index) < int(b.index) or (int(a.index) == int(b.index) and int(a.id) < int(b.id)))
	for wave in waves:
		if wave.status != "marching" or wave.path == null or not enters_before(wave.path, int(wave.spawnAt), at, cell, until):
			continue
		var target := server.find_village(world, int(wave.targetVillageId)) if wave.targetVillageId != null else {}
		var goal := {"id": target.id, "cell": Vector2i(target.q, target.r)} if not target.is_empty() else {"id": null, "cell": Vector2i.ZERO}
		var since_spawn := at - int(wave.spawnAt)
		var path: Array = horde_detour(wave.path, since_spawn, cell, until - int(wave.spawnAt), func(from: Vector2i) -> Variant:
			var route: Variant = LocalHordes.route_from(data, land, from, [goal], wave.front, wave.composition, {}, LocalWaves.rng_for(int(world.seed), int(wave.index), 0xf1), 0.0, world.speed)
			return route.path if route != null else null)
		var march := LocalHordes.hold_for_quiet(world, int(wave.spawnAt), {"path": path, "arrivesAt": int(wave.spawnAt) + int(path[-1].atMs)})
		wave.status = "marching"
		wave.path = march.path
		wave.arrivesAt = march.arrivesAt
		wave.endsAt = null
		world.events = world.events.filter(func(e: Dictionary) -> bool:
			return not (e.status == "pending" and e.type in ["outpost_raid", "supply_raid", "field_intercept"] and int(e.payload.get("waveId", -1)) == int(wave.id)))
		server.schedule(world, int(march.arrivesAt), "wave_arrive", {"waveId": wave.id})
		LocalHordes.plan_raids(server, world, wave, since_spawn)
		LocalArmies.plan_intercepts(server, world, wave, since_spawn + 1)
	# Armies on the road, out or coming home.
	for army in _by_departure(world.armies.filter(func(a: Dictionary) -> bool: return a.status != "done"), "departsAt"):
		if army.status == "marching" and enters_before(army.path, int(army.departsAt), at, cell, until):
			var dest := Vector2i(int(army.targetQ), int(army.targetR))
			var path: Variant = _detour(army.path, at - int(army.departsAt), cell, func(from: Vector2i) -> Variant: return _army_road(data, land, army, from, dest, at, world))
			if path == null:
				continue
			army.path = path
			army.arrivesAt = int(army.departsAt) + int(path[-1].atMs)
			server.schedule(world, int(army.arrivesAt), "army_arrive", {"armyId": army.id})
		elif army.status == "returning" and army.get("leavesAt") != null:
			var road := LocalLogistics.reversed_route(army.path)
			if not enters_before(road, int(army.leavesAt), at, cell, until):
				continue
			var home := server.find_village(world, int(army.homeVillageId))
			if home.is_empty():
				continue
			var back: Variant = _detour(road, at - int(army.leavesAt), cell, func(from: Vector2i) -> Variant: return _army_road(data, land, army, from, Vector2i(home.q, home.r), at, world))
			if back == null:
				continue
			army.path = LocalLogistics.reversed_route(back)
			army.returnsAt = int(army.leavesAt) + int(back[-1].atMs)
			server.schedule(world, int(army.returnsAt), "army_return", {"armyId": army.id})
	# Caravans, out or coming home.
	for caravan in _by_departure(world.caravans.filter(func(c: Dictionary) -> bool: return c.status != "done"), "departsAt"):
		var village := server.find_village(world, int(caravan.villageId))
		if village.is_empty():
			continue
		var bonuses := LocalLogistics.effective_bonuses(server, world, village)
		if caravan.status == "outbound" and enters_before(caravan.path, int(caravan.departsAt), at, cell, until):
			var dest := _caravan_goal(server, world, caravan)
			var path: Variant = _detour(caravan.path, at - int(caravan.departsAt), cell, func(from: Vector2i) -> Variant: return LocalLogistics.caravan_route(data, land, from, dest, world.speed, bonuses))
			if path == null:
				continue
			var travel := int(path[-1].atMs)
			caravan.path = path
			caravan.arrivesAt = int(caravan.departsAt) + travel
			caravan.returnsAt = int(caravan.departsAt) + 2 * travel
			_reroute_caravan(server, world, caravan, "out", "caravan_arrive", int(caravan.arrivesAt), at)
		elif caravan.status == "returning":
			var road := LocalLogistics.reversed_route(caravan.path)
			if not enters_before(road, int(caravan.arrivesAt), at, cell, until):
				continue
			var back: Variant = _detour(road, at - int(caravan.arrivesAt), cell, func(from: Vector2i) -> Variant: return LocalLogistics.caravan_route(data, land, from, Vector2i(village.q, village.r), world.speed, bonuses))
			if back == null:
				continue
			caravan.path = LocalLogistics.reversed_route(back)
			caravan.returnsAt = int(caravan.arrivesAt) + int(back[-1].atMs)
			_reroute_caravan(server, world, caravan, "back", "caravan_return", int(caravan.returnsAt), at)
	# Settlers, on their way or walking home.
	var settler_speed := float(data.units.units.settler.speed)
	for expedition in _by_departure(world.expeditions.filter(func(e: Dictionary) -> bool: return e.status in ["outbound", "returning"]), "departsAt"):
		var home := server.find_village(world, int(expedition.villageId))
		if home.is_empty():
			continue
		if expedition.status == "outbound" and enters_before(expedition.path, int(expedition.departsAt), at, cell, until):
			var goal := Vector2i(int(expedition.q), int(expedition.r))
			var path: Variant = _detour(expedition.path, at - int(expedition.departsAt), cell, func(from: Vector2i) -> Variant: return LocalLogistics.road_route(data, land, from, goal, settler_speed, world.speed))
			if path == null:
				continue
			var travel := int(path[-1].atMs)
			expedition.path = path
			expedition.arrivesAt = int(expedition.departsAt) + travel
			expedition.returnsAt = int(expedition.departsAt) + 2 * travel
			server.schedule(world, int(expedition.arrivesAt), "settlers_arrive", {"expeditionId": expedition.id})
		elif expedition.status == "returning":
			var road := LocalLogistics.reversed_route(expedition.path)
			if not enters_before(road, int(expedition.arrivesAt), at, cell, until):
				continue
			var back: Variant = _detour(road, at - int(expedition.arrivesAt), cell, func(from: Vector2i) -> Variant: return LocalLogistics.road_route(data, land, from, Vector2i(home.q, home.r), settler_speed, world.speed))
			if back == null:
				continue
			expedition.path = LocalLogistics.reversed_route(back)
			expedition.returnsAt = int(expedition.arrivesAt) + int(back[-1].atMs)
			server.schedule(world, int(expedition.returnsAt), "settlers_return", {"expeditionId": expedition.id})


static func _army_road(data: Dictionary, land: Dictionary, army: Dictionary, from: Vector2i, to: Vector2i, at: int, world: Dictionary) -> Variant:
	var speed := LocalArmies.army_speed(data, army.units) * LocalSupply.speed_factor(data, army if LocalArmies.supplied(army) else null, at, world.speed)
	return LocalLogistics.road_route(data, land, from, to, speed, world.speed, LocalArmies.terrain_relief(data, army.units))


static func _caravan_goal(server: LocalServer, world: Dictionary, caravan: Dictionary) -> Vector2i:
	if caravan.get("destinationFortId") != null:
		for f in world.forts:
			if int(f.id) == int(caravan.destinationFortId):
				return Vector2i(int(f.q), int(f.r))
	if caravan.get("destinationShipyardId") != null:
		var yard := LocalEvents.find_shipyard(world, int(caravan.destinationShipyardId))
		if not yard.is_empty():
			return Vector2i(int(yard.q), int(yard.r))
	if caravan.get("destinationVillageId") != null:
		var village := server.find_village(world, int(caravan.destinationVillageId))
		if not village.is_empty():
			return Vector2i(village.q, village.r)
	return Vector2i.ZERO


static func _reroute_caravan(server: LocalServer, world: Dictionary, caravan: Dictionary, leg: String, event: String, due: int, at: int) -> void:
	world.events = world.events.filter(func(e: Dictionary) -> bool:
		return not (e.status == "pending" and e.type == "caravan_ambush" and int(e.payload.get("caravanId", -1)) == int(caravan.id)))
	server.schedule(world, due, event, {"caravanId": caravan.id})
	if caravan.get("ambush") == null:
		LocalLogistics.plan_ambushes(server, world, caravan, leg, at)
