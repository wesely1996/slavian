class_name LocalScouting
extends RefCounted
## Scouting and settling for the local engine: server/src/sim/scouting.ts,
## sendScoutsCommand and foundVillageCommand (commands/village.ts),
## scheduler/scouting.ts and scheduler/expeditions.ts.

const SCOUT := "scout"
const SETTLER := "settler"


# --- Rules (sim/scouting.ts) ---------------------------------------------------------

## Where a wave can be found at `at`: on the march, at its target, or (not
## yet spawned) gathering in its front's spawn zone nearest the village.
static func scout_target(data: Dictionary, terrain: Dictionary, wave: Dictionary, from: Vector2i, at: int) -> Vector2i:
	if wave.path != null and not wave.path.is_empty():
		var elapsed := at - int(wave.spawnAt)
		var reached: Dictionary = wave.path[0]
		for step in wave.path:
			if int(step.atMs) <= elapsed:
				reached = step
		return Vector2i(reached.q, reached.r)
	var zone: Array = data.enemies.fronts.get(wave.front, {}).get("spawnTerrain", [])
	var best: Variant = null
	for key in terrain:
		if not terrain[key] in zone:
			continue
		var parts: PackedStringArray = key.split(",")
		var cell := Vector2i(int(parts[0]), int(parts[1]))
		if LocalMapgen.front_of(cell) != wave.front:
			continue
		if best == null or HexMath.distance(from, cell) < HexMath.distance(from, best):
			best = cell
	return best if best != null else from


## Real-time ms for scouts to walk from `from` to `to`.
static func scout_travel_ms(data: Dictionary, land: Dictionary, from: Vector2i, to: Vector2i, world_speed: float, bonuses: Dictionary = {}) -> int:
	var move_cost := LocalLand.move_cost_on(data, land)
	var path: Variant = LocalLand.find_path(from, to, move_cost, float(data.field.road.factor))
	var cost := 0.0
	if path != null:
		for i in range(1, path.size()):
			cost += float(move_cost.call(path[i - 1], path[i]))
	else:
		# Off-road targets: straight-line distance over rough ground.
		cost = HexMath.distance(from, to) * 2.0
	var speed := float(data.units.units[SCOUT].speed) * (1.0 + float(bonuses.get("scoutSpeed", 0.0)))
	return maxi(1, LocalWaves.js_round(((cost / speed) * LocalTime.MS_PER_HOUR) / world_speed))


static func _rng(seed_value: int, mission_id: int, salt: int) -> LocalRng:
	return LocalRng.new((seed_value ^ LocalRng.imul(mission_id + 1, 0x85ebca6b) ^ salt) & 0xffffffff)


static func survivors_of(data: Dictionary, front: String, sent: int, seed_value: int, mission_id: int, bonuses: Dictionary = {}) -> int:
	var base := float(data.scouting.survival.get(front, data.scouting.defaultSurvival))
	var chance := minf(0.98, base + float(bonuses.get("scoutSurvival", 0.0)))
	var rng := _rng(seed_value, mission_id, 0x17)
	var survivors := 0
	for i in sent:
		if rng.next() < chance:
			survivors += 1
	return survivors


## A range around `value` that always contains it, the true value placed
## randomly inside.
static func _range(value: int, error: float, rng: LocalRng) -> Dictionary:
	if error == 0:
		return {"min": value, "max": value}
	var shift := (rng.next() - 0.5) * error * value
	return {"min": maxi(0, floori(value + shift - error * value)), "max": ceili(value + shift + error * value)}


static func scout_report(data: Dictionary, front: String, composition: Dictionary, stance: String, sent: int, survivors: int, dispersed: bool,
		seed_value: int, mission_id: int) -> Dictionary:
	var report := {"sent": sent, "survivors": survivors, "dispersed": dispersed}
	var tier: Variant = null
	var tiers: Array = data.scouting.tiers
	for i in range(tiers.size() - 1, -1, -1):
		if survivors >= int(tiers[i].minSurvivors):
			tier = tiers[i]
			break
	if tier == null or dispersed:
		report.merge({"tier": "none", "size": null, "units": [], "stance": null})
		return report
	var names: Dictionary = data.enemies.fronts[front].units
	var rng := _rng(seed_value, mission_id, 0x2e)
	var entries: Array = composition.keys()
	entries.sort_custom(func(a: String, b: String) -> bool:
		return int(composition[a]) > int(composition[b]) or (int(composition[a]) == int(composition[b]) and a < b))
	var total := 0
	for unit in entries:
		total += int(composition[unit])
	var size := _range(total, float(tier.sizeError), rng)
	var units: Array = []
	if tier.unitError == null:
		for unit in entries.slice(0, 1):
			units.append({"unit": unit, "name": names.get(unit, {}).get("name", unit), "min": null, "max": null})
	else:
		for unit in entries:
			var r := _range(int(composition[unit]), float(tier.unitError), rng)
			units.append({"unit": unit, "name": names.get(unit, {}).get("name", unit), "min": r.min, "max": r.max})
	report.merge({"tier": tier.name, "size": size, "units": units, "stance": stance if tier.revealsStance else null})
	return report


# --- Scouts ------------------------------------------------------------------------------

static func insert_mission(world: Dictionary, mission: Dictionary) -> Dictionary:
	var m := {"id": world.next.mission, "survivors": null, "status": "outbound", "report": null}
	m.merge(mission)
	world.next.mission += 1
	world.missions.append(m)
	return m


static func send_scouts(server: LocalServer, world: Dictionary, village: Dictionary, body: Dictionary, now: int) -> Dictionary:
	var data := server.data
	var max_scouts := int(data.scouting.maxScouts)
	var count := float(body.get("count", 0))
	if count != floorf(count) or count < 1 or count > max_scouts:
		return LocalVillage.rule("Send between 1 and %d scouts" % max_scouts)
	var wave := server.find_wave(world, int(body.get("waveId", 0)))
	if wave.is_empty():
		return {"error": "Wave %d not found" % int(body.get("waveId", 0)), "kind": "not_found"}
	if wave.status in ["dispersed", "defeated"]:
		return LocalVillage.rule("That horde has already scattered")
	var state := LocalVillage.send_away(village.state, SCOUT, int(count), now)
	if state.has("error"):
		return state
	var land := LocalHordes.land_of(world)
	var home := Vector2i(village.q, village.r)
	var target := scout_target(data, world.hexes, wave, home, now)
	var travel := scout_travel_ms(data, land, home, target, world.speed, LocalLogistics.effective_bonuses(server, world, village))
	var mission := insert_mission(world, {"villageId": village.id, "waveId": wave.id, "sent": int(count), "target": {"q": target.x, "r": target.y},
		"departsAt": now, "arrivesAt": now + travel, "returnsAt": now + 2 * travel})
	server.schedule(world, int(mission.arrivesAt), "scout_arrive", {"missionId": mission.id})
	return {"state": state, "mission": mission}


static func find_mission(world: Dictionary, id: int) -> Dictionary:
	for m in world.missions:
		if int(m.id) == id:
			return m
	return {}


static func on_scout_arrive(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var data := server.data
	var mission := find_mission(world, int(event.payload.missionId))
	if mission.is_empty() or mission.status != "outbound":
		return
	var wave := server.find_wave(world, int(mission.waveId))
	# A horde that already scattered can't hurt anyone.
	var dispersed: bool = wave.status in ["dispersed", "defeated"]
	var village := server.find_village(world, int(mission.villageId))
	var survivors := int(mission.sent) if dispersed else survivors_of(data, wave.front, int(mission.sent), int(world.seed), int(mission.id),
		LocalLogistics.effective_bonuses(server, world, village))
	var report := scout_report(data, wave.front, wave.composition, wave.stance, int(mission.sent), survivors, dispersed, int(world.seed), int(mission.id))
	mission.status = "returning"
	mission.survivors = survivors
	mission.report = report
	var lost := int(mission.sent) - survivors
	if lost > 0:
		village.state = LocalVillage.lose_away(data, village.state, SCOUT, lost, int(event.dueAt), world.speed)
		changed.append(["village", village.id])
	server.schedule(world, int(mission.returnsAt), "scout_return", {"missionId": mission.id})
	changed.append(["world"])


static func on_scout_return(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var mission := find_mission(world, int(event.payload.missionId))
	if mission.is_empty() or mission.status != "returning":
		return
	var village := server.find_village(world, int(mission.villageId))
	village.state = LocalVillage.return_home(village.state, SCOUT, int(mission.survivors if mission.survivors != null else 0))
	mission.status = "done"
	changed.append(["village", village.id])
	changed.append(["world"])


## Missions still worth showing, newest first (db/scouting.ts listMissions).
static func missions_view(server: LocalServer, world: Dictionary) -> Array:
	var shown: Array = world.missions.filter(func(m: Dictionary) -> bool:
		var wave := server.find_wave(world, int(m.waveId))
		return not wave.status in ["dispersed", "defeated"] or m.status != "done")
	shown.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.departsAt) > int(b.departsAt) or (int(a.departsAt) == int(b.departsAt) and int(a.id) > int(b.id)))
	return shown.map(mission_view)


static func mission_view(m: Dictionary) -> Dictionary:
	return {"id": m.id, "villageId": m.villageId, "waveId": m.waveId, "sent": m.sent, "status": m.status, "target": m.target,
		"departsAt": LocalTime.iso(m.departsAt), "arrivesAt": LocalTime.iso(m.arrivesAt), "returnsAt": LocalTime.iso(m.returnsAt), "report": m.report}


# --- Settlers -------------------------------------------------------------------------------

static func _outposts(world: Dictionary) -> Dictionary:
	var out := {}
	for v in world.villages:
		for plot in LocalVillage.outpost_plots(v.state.plots):
			out[LocalLand.key(LocalVillage.outpost_hex(plot))] = true
	return out


static func found_village(server: LocalServer, world: Dictionary, village: Dictionary, body: Dictionary, now: int) -> Dictionary:
	var data := server.data
	var cell := Vector2i(int(body.get("q", 0)), int(body.get("r", 0)))
	var home := Vector2i(village.q, village.r)
	var problem := LocalVillage.settle_problem(data, cell, world.hexes.get(LocalLand.key(cell)), home,
		world.villages.map(func(v: Dictionary) -> Vector2i: return Vector2i(v.q, v.r)), _outposts(world))
	if problem != "":
		return LocalVillage.rule(problem)
	if not LocalArmies.camp_at(world, cell).is_empty():
		return LocalVillage.rule("A camp stands there; clear it first")
	if LocalArmies.site_at(world, cell).get("status") == "unexplored":
		return LocalVillage.rule("An ancient site lies there")
	if world.expeditions.any(func(e: Dictionary) -> bool: return int(e.q) == cell.x and int(e.r) == cell.y and e.status == "outbound"):
		return LocalVillage.rule("Settlers are already on their way there")
	var settlers := int(data.expansion.settlersNeeded)
	var state := LocalVillage.send_away(village.state, SETTLER, settlers, now)
	if state.has("error"):
		return LocalVillage.rule("Founding a village takes %d settlers at home" % settlers)
	var path: Variant = LocalLogistics.road_route(data, LocalHordes.land_of(world), home, cell, float(data.units.units[SETTLER].speed), world.speed)
	if path == null:
		return LocalVillage.rule("No road leads there")
	var travel := int(path[-1].atMs)
	var taken: Array = world.villages.map(func(v: Dictionary) -> String: return v.name)
	for e in world.expeditions:
		if e.status == "outbound":
			taken.append(e.name)
	var name := String(body.get("name", "")).strip_edges()
	if name == "":
		name = LocalHeroes.town_name(data, taken, LocalRng.new((int(world.seed) ^ LocalRng.imul(taken.size() + 1, 0x9e3779b1)) & 0xffffffff))
	var expedition := {"id": world.next.expedition, "villageId": village.id, "q": cell.x, "r": cell.y, "name": name, "settlers": settlers,
		"status": "outbound", "failure": null, "foundedVillageId": null, "path": path, "departsAt": now, "arrivesAt": now + travel,
		"returnsAt": now + 2 * travel}
	world.next.expedition += 1
	world.expeditions.append(expedition)
	server.schedule(world, int(expedition.arrivesAt), "settlers_arrive", {"expeditionId": expedition.id})
	return {"state": state, "expedition": expedition}


static func find_expedition(world: Dictionary, id: int) -> Dictionary:
	for e in world.expeditions:
		if int(e.id) == id:
			return e
	return {}


static func on_settlers_arrive(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var data := server.data
	var expedition := find_expedition(world, int(event.payload.expeditionId))
	if expedition.is_empty() or expedition.status != "outbound":
		return
	var at := int(event.dueAt)
	var home := server.find_village(world, int(expedition.villageId))
	var cell := Vector2i(expedition.q, expedition.r)
	var problem := LocalVillage.settle_problem(data, cell, world.hexes.get(LocalLand.key(cell)), Vector2i(home.q, home.r),
		world.villages.map(func(v: Dictionary) -> Vector2i: return Vector2i(v.q, v.r)), _outposts(world))
	changed.append(["world"])
	if problem != "":
		expedition.status = "returning"
		expedition.failure = problem
		LocalInbox.tell(server, world, home.ownerAccountId, {"kind": "settlers", "tier": "digest", "title": "Settlers turned back from ({q}, {r})",
			"body": "{problem}. They are walking home to {home}.", "vars": {"q": expedition.q, "r": expedition.r, "problem": problem, "home": home.name}}, at)
		server.schedule(world, int(expedition.returnsAt), "settlers_return", {"expeditionId": expedition.id})
		return
	var owner := int(home.ownerAccountId)
	var owned: int = world.villages.filter(func(v: Dictionary) -> bool: return int(v.ownerAccountId) == owner).size()
	var founded := server.insert_village(world, owner, expedition.name, cell, LocalVillage.new_village(data, at, world.speed,
		{"startingResources": data.expansion.startingResources, "adminUpkeep": LocalVillage.admin_upkeep_for(data, owned), "bonuses": home.state.bonuses,
		"fields": LocalVillage.fields_from_land(data, LocalVillage.land_around(data, world.hexes, cell))}))
	# The settlers become the new village's people: they stop eating at home.
	home.state = LocalVillage.lose_away(data, home.state, SETTLER, int(expedition.settlers), at, world.speed)
	expedition.status = "founded"
	expedition.foundedVillageId = founded.id
	LocalInbox.tell(server, world, owner, {"kind": "settlers", "tier": "digest", "title": "{name} founded",
		"body": "Your settlers built a new village.", "vars": {"name": expedition.name}}, at)


static func on_settlers_return(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var expedition := find_expedition(world, int(event.payload.expeditionId))
	if expedition.is_empty() or expedition.status != "returning":
		return
	var home := server.find_village(world, int(expedition.villageId))
	home.state = LocalVillage.return_home(home.state, SETTLER, int(expedition.settlers))
	expedition.status = "done"
	changed.append(["village", home.id])
	changed.append(["world"])


## On the road, plus the five latest that ended, newest first.
static func expeditions_view(world: Dictionary) -> Array:
	var going: Array = world.expeditions.filter(func(e: Dictionary) -> bool: return e.status in ["outbound", "returning"])
	var ended: Array = world.expeditions.filter(func(e: Dictionary) -> bool: return e.status in ["founded", "done"])
	ended.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.arrivesAt) > int(b.arrivesAt))
	var shown: Array = going + ended.slice(0, 5)
	shown.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.departsAt) > int(b.departsAt) or (int(a.departsAt) == int(b.departsAt) and int(a.id) > int(b.id)))
	return shown.map(func(e: Dictionary) -> Dictionary:
		return {"id": e.id, "villageId": e.villageId, "q": e.q, "r": e.r, "name": e.name, "settlers": e.settlers, "status": e.status,
			"failure": e.failure, "foundedVillageId": e.foundedVillageId, "path": e.path.map(func(s: Dictionary) -> Array: return [s.q, s.r, s.atMs]),
			"departsAt": LocalTime.iso(e.departsAt), "arrivesAt": LocalTime.iso(e.arrivesAt), "returnsAt": LocalTime.iso(e.returnsAt)})
