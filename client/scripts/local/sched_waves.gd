class_name LocalHordes
extends RefCounted
## Hordes for the local engine: marching (server/src/sim/waves.ts planMarch,
## routeFrom), the fronts' leaders (sim/leaders.ts, scheduler/leaders.ts) and
## wave_spawn (scheduler/waves.ts), with the raids and warnings a march plans.

const MASK := 0xffffffff
const MAX_SPAWN_CANDIDATES := 12


# --- Marching (sim/waves.ts) --------------------------------------------------

## The slowest unit sets the pace, in hexes per hour on plains.
static func march_speed(data: Dictionary, front: String, composition: Dictionary) -> float:
	var units: Dictionary = data.enemies.fronts[front].units
	var slowest := INF
	for id in composition:
		slowest = minf(slowest, float(units[id].speed))
	return slowest


## The land: {"terrain": {"q,r": id}, "blocked": {edge key}, "roads": {edge key}}.
static func land_of(world: Dictionary) -> Dictionary:
	var blocked := {}
	for e in world.rivers:
		if e.crossing != "standing":
			blocked[LocalLand.edge_key(e.a, e.b)] = true
	var roads := {}
	for e in world.roads:
		if e.status == "standing":
			roads[LocalLand.edge_key(e.a, e.b)] = true
	return {"terrain": world.hexes, "blocked": blocked, "roads": roads}


## The cheapest target from `from`: road cost plus fear, plus extra for the
## Holy City; erratic fronts jitter villages against each other. Null when
## nothing can be reached. `targets`: [{id (or null), cell}].
static func route_from(data: Dictionary, land: Dictionary, from: Vector2i, targets: Array, front: String, composition: Dictionary,
		fear: Dictionary, rng: LocalRng, start_ms: float, world_speed: float) -> Variant:
	var rules: Dictionary = data.horde
	var road_factor := float(data.field.road.factor)
	var roads := front != "north"
	var step_cost := func(a: Vector2i, b: Vector2i) -> float:
		var type: Variant = land.terrain.get(LocalLand.key(b))
		if type == null or land.blocked.has(LocalLand.edge_key(a, b)):
			return -1.0
		var cost: Variant = data.terrain.terrain[type].moveCost
		if cost == null:
			return -1.0
		return float(cost) * road_factor if roads and land.roads.has(LocalLand.edge_key(a, b)) else float(cost)
	var search_cost := func(a: Vector2i, b: Vector2i) -> float:
		var cost: float = step_cost.call(a, b)
		return -1.0 if cost < 0.0 else cost + float(rules.fear.pathWeight) * float(fear.get(LocalLand.key(b), 0.0))
	var erratic := float(data.enemies.fronts[front].personality.erratic)
	var best: Variant = null
	var holy: Variant = null
	var cheapest_village := INF
	for target in targets:
		var path: Variant = LocalLand.find_path(from, target.cell, search_cost, road_factor if roads else 1.0)
		if path == null:
			continue
		var road := 0.0
		for i in range(1, path.size()):
			road += float(search_cost.call(path[i - 1], path[i]))
		var cost := road + float(rules.fear.targetWeight) * float(fear.get(LocalLand.key(target.cell), 0.0))
		if target.id == null:
			holy = {"path": path, "cost": cost + float(rules.holyCityExtraCost)}
			continue
		cheapest_village = minf(cheapest_village, cost)
		var score := cost * (1.0 + erratic * rng.next())
		if best == null or score < best.score or (score == best.score and int(target.id) < int(best.id if best.id != null else 0)):
			best = {"id": target.id, "path": path, "score": score}
	if holy != null and holy.cost < cheapest_village:
		best = {"id": null, "path": holy.path, "score": holy.cost}
	if best == null:
		return null
	var hours_per_cost := 1.0 / march_speed(data, front, composition)
	var at_ms := start_ms
	var steps: Array = []
	for i in best.path.size():
		var cell: Vector2i = best.path[i]
		if i > 0:
			at_ms += (float(step_cost.call(best.path[i - 1], cell)) * hours_per_cost * LocalTime.MS_PER_HOUR) / world_speed
		steps.append({"q": cell.x, "r": cell.y, "atMs": LocalWaves.js_round(at_ms)})
	return {"targetVillageId": best.id, "path": steps, "arrivesMs": steps[-1].atMs}


## Every village it may strike, and the Holy City.
static func targets_of(villages: Array) -> Array:
	var out: Array = []
	for v in villages:
		out.append({"id": v.id, "cell": Vector2i(v.q, v.r)})
	out.append({"id": null, "cell": Vector2i.ZERO})
	return out


static func plan_march(data: Dictionary, land: Dictionary, wave: Dictionary, villages: Array, seed_value: int, depart_at: int, world_speed: float, fear: Dictionary) -> Dictionary:
	var spawn_terrain: Array = data.enemies.fronts[wave.front].spawnTerrain
	var candidates: Array = []
	for key in land.terrain:
		if land.terrain[key] in spawn_terrain:
			var parts: PackedStringArray = key.split(",")
			var cell := Vector2i(int(parts[0]), int(parts[1]))
			if LocalMapgen.front_of(cell) == wave.front:
				candidates.append(cell)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	var rng := LocalWaves.rng_for(seed_value, int(wave.index), 0x5a)
	for i in range(candidates.size() - 1, 0, -1):
		var j := floori(rng.next() * (i + 1))
		var swap: Vector2i = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = swap
	var targets := targets_of(villages)
	for spawn in candidates.slice(0, MAX_SPAWN_CANDIDATES):
		var route: Variant = route_from(data, land, spawn, targets, wave.front, wave.composition, fear,
			LocalWaves.rng_for(seed_value, int(wave.index), 0x7a), 0.0, world_speed)
		if route == null:
			continue
		return {"spawn": spawn, "targetVillageId": route.targetVillageId, "path": route.path, "arrivesAt": depart_at + int(route.arrivesMs)}
	push_error("Wave %d found no path from the %s front" % [wave.index, wave.front])
	return {}


## Outposts within `reach` of a route, with when the horde first comes that
## close (ms after departure). `outposts`: [{villageId, plot, cell}].
static func raids_along(path: Array, outposts: Array, reach: int, from_ms := 0) -> Array:
	var raids: Array = []
	for outpost in outposts:
		for s in path:
			if int(s.atMs) >= from_ms and HexMath.distance(Vector2i(s.q, s.r), outpost.cell) <= reach:
				var raid: Dictionary = outpost.duplicate()
				raid.atMs = int(s.atMs)
				raids.append(raid)
				break
	return raids


# --- Leaders (sim/leaders.ts) -------------------------------------------------

static func new_leader(data: Dictionary, front: String, seed_value: int, used: Array, level := 1) -> Dictionary:
	var names: Array = data.leaders.fronts[front].names
	var free := names.filter(func(n: String) -> bool: return not n in used)
	var pool := free if not free.is_empty() else names
	var rng := LocalRng.new((seed_value ^ LocalRng.imul(used.size() + 1, 0x85ebca6b) ^ ((front.length() * 0x27d4eb2f) & MASK)) & MASK)
	var leader := {"name": pool[floori(rng.next() * pool.size())], "level": 1, "xp": 0, "skills": {}}
	while int(leader.level) < mini(level, int(data.leaders.maxLevel)):
		leader = level_up(data, front, leader)
	return leader


static func rise_level(data: Dictionary, fallen_level: int) -> int:
	return 1 + floori(fallen_level * float(data.leaders.riseShare))


static func leader_title(data: Dictionary, front: String, leader: Dictionary) -> String:
	var ranks: Array = data.leaders.fronts.get(front, {}).get("ranks", [{"minLevel": 1, "title": "{name}"}])
	var rank: Dictionary = ranks[0]
	for r in ranks:
		if int(leader.level) >= int(r.minLevel):
			rank = r
	return String(rank.title).replace("{name}", leader.name)


static func leader_xp_to_next(data: Dictionary, level: int) -> int:
	return LocalWaves.js_round(float(data.leaders.levelXp.base) * pow(float(data.leaders.levelXp.growth), level - 1))


static func level_up(data: Dictionary, front: String, leader: Dictionary) -> Dictionary:
	var level := int(leader.level) + 1
	var order: Array = data.leaders.fronts[front].skills
	var skills: Dictionary = leader.skills.duplicate()
	for i in order.size():
		var skill: String = order[(level - 2 + i) % order.size()]
		var rank := int(skills.get(skill, 0))
		if rank < int(data.leaders.skills[skill].maxRank):
			skills[skill] = rank + 1
			break
	var next := leader.duplicate()
	next.level = level
	next.skills = skills
	return next


static func gain_leader_xp(data: Dictionary, front: String, leader: Dictionary, xp: float) -> Dictionary:
	var next := leader.duplicate()
	next.xp = int(leader.xp) + maxi(0, floori(xp))
	while int(next.level) < int(data.leaders.maxLevel) and int(next.xp) >= leader_xp_to_next(data, int(next.level)):
		next.xp = int(next.xp) - leader_xp_to_next(data, int(next.level))
		next = level_up(data, front, next)
	if int(next.level) >= int(data.leaders.maxLevel):
		next.xp = 0
	return next


## What a battle does to its horde's leader (leaderAfterBattle): {state,
## dead, woundMs, grudge} where grudge is a village id, null, or "keep".
static func leader_after_battle(data: Dictionary, front: String, leader: Dictionary, outcome: Dictionary, world_speed: float) -> Dictionary:
	var xp: Dictionary = data.leaders.xp
	if not outcome.hordeWon and outcome.wiped:
		return {"state": leader, "dead": true, "woundMs": 0, "grudge": "keep"}
	var gained := float(xp.battle) + float(xp.perKill) * int(outcome.kills)
	gained += (float(xp.win) + (float(xp.raze) if outcome.get("razed", false) else 0.0)) if outcome.hordeWon else float(xp.escape)
	return {
		"state": gain_leader_xp(data, front, leader, gained), "dead": false,
		"woundMs": 0 if outcome.hordeWon else LocalWaves.js_round((float(data.leaders.woundHours) * LocalTime.MS_PER_HOUR) / world_speed),
		"grudge": "keep" if outcome.hordeWon else outcome.villageId,
	}


static func leader_effects(data: Dictionary, leader: Dictionary) -> Dictionary:
	var sum := {}
	for skill in leader.skills:
		var per: Dictionary = data.leaders.skills.get(skill, {}).get("effectsPerRank", {})
		for key in per:
			sum[key] = float(sum.get(key, 0.0)) + float(per[key]) * int(leader.skills[skill])
	return {"attack": float(sum.get("attack", 0.0)), "defense": float(sum.get("defense", 0.0)), "nerve": float(sum.get("nerve", 0.0)), "loot": float(sum.get("loot", 0.0))}


# --- The scheduler (scheduler/waves.ts, leaders.ts, outposts.ts, notices.ts) ---

## The front's leader takes the head of a horde setting out, unless wounded or
## already out; a front without one raises a new one.
static func assign_leader(server: LocalServer, world: Dictionary, wave: Dictionary, at: int) -> void:
	var data := server.data
	if not data.leaders.fronts.has(wave.front):
		return
	var leader: Variant = null
	for l in world.leaders:
		if l.front == wave.front and l.status == "alive":
			leader = l
	if leader == null:
		var used: Array = []
		var fallen: Variant = null
		for l in _leaders_in_order(world):
			used.append(l.name)
			if l.front == wave.front and l.status == "dead":
				fallen = l
		var state := new_leader(data, wave.front, int(world.seed) + int(wave.index), used, rise_level(data, int(fallen.level)) if fallen != null else 1)
		leader = {"id": world.next.leader, "front": wave.front, "name": state.name, "level": state.level, "xp": state.xp, "skills": state.skills,
			"status": "alive", "woundedUntil": null, "battles": 0, "wins": 0, "losses": 0, "razed": 0, "kills": 0, "grudgeVillageId": null,
			"diedAt": null, "createdAt": at}
		world.next.leader += 1
		world.leaders.append(leader)
	if leader.woundedUntil != null and int(leader.woundedUntil) > at:
		return
	for w in world.waves:
		if w.get("leaderId") == leader.id and not w.status in ["scheduled", "dispersed", "defeated", "settled"]:
			return
	wave.leaderId = leader.id


## The living first, then by front and id (db/leaders.ts listLeaders).
static func _leaders_in_order(world: Dictionary) -> Array:
	var out: Array = world.leaders.duplicate()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da: bool = a.status == "dead"
		var db: bool = b.status == "dead"
		if da != db:
			return not da
		if a.front != b.front:
			return a.front < b.front
		return a.id < b.id)
	return out


static func leaders_view(data: Dictionary, world: Dictionary) -> Array:
	var out: Array = []
	for l in _leaders_in_order(world):
		out.append({
			"id": l.id, "front": l.front, "name": l.name, "title": leader_title(data, l.front, l),
			"level": l.level, "xp": l.xp, "xpToNext": null if int(l.level) >= int(data.leaders.maxLevel) else leader_xp_to_next(data, int(l.level)),
			"skills": l.skills, "effects": leader_effects(data, l), "status": l.status,
			"woundedUntil": LocalTime.iso(l.woundedUntil) if l.woundedUntil != null else null,
			"battles": l.battles, "wins": l.wins, "losses": l.losses, "razed": l.razed, "kills": l.kills,
			"grudgeVillageId": l.grudgeVillageId, "diedAt": LocalTime.iso(l.diedAt) if l.diedAt != null else null,
		})
	return out


## A horde sets out: its leader, camps joining, fear fading, its march, the
## raids and warnings along it, and the next wave announced.
static func on_wave_spawn(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var data := server.data
	var wave := server.find_wave(world, int(event.payload.waveId))
	if wave.is_empty() or wave.status != "scheduled":
		return
	var at := int(event.dueAt)
	assign_leader(server, world, wave, at)
	LocalCamps.camps_join(server, world, wave)
	wave.composition = LocalStore.stored(wave.composition)
	wave.initial = LocalStore.stored(wave.initial)
	# Old memories fade as a new horde sets out.
	var fear: Dictionary = world.fear
	for key in fear.keys():
		fear[key] = float(fear[key]) * float(data.horde.fear.decayPerWave)
		if fear[key] < float(data.horde.fear.minimum):
			fear.erase(key)
	var villages: Array = []
	for v in world.villages:
		if v.ruin == null:
			villages.append({"id": v.id, "q": v.q, "r": v.r})
	var weighted := fear_of(server, world)
	var march := hold_for_quiet(world, int(wave.spawnAt), plan_march(data, land_of(world), wave, villages, int(world.seed), at, world.speed, weighted))
	wave.status = "marching"
	wave.spawn = {"q": march.spawn.x, "r": march.spawn.y}
	wave.targetVillageId = march.targetVillageId
	wave.path = march.path
	wave.arrivesAt = march.arrivesAt
	server.schedule(world, int(wave.arrivesAt), "wave_arrive", {"waveId": wave.id})
	plan_raids(server, world, wave, 0)
	LocalArmies.plan_intercepts(server, world, wave)
	plan_warning(server, world, wave, at)
	if not wave.ritual and world.ritualAt == null:
		var last: Dictionary = {}
		for w in world.waves:
			if last.is_empty() or int(w.index) > int(last.index):
				last = w
		server.announce_wave(world, int(last.index) + 1, int(last.spawnAt))
	changed.append(["world"])


## A march arriving in the group's quiet hours waits outside until they end.
static func hold_for_quiet(world: Dictionary, spawn_at: int, march: Dictionary) -> Dictionary:
	var at := after_quiet(world, int(march.arrivesAt))
	if at <= int(march.arrivesAt):
		return march
	var held := march.duplicate()
	held.path = march.path.duplicate()
	held.path[-1] = march.path[-1].duplicate()
	held.path[-1].atMs = at - spawn_at
	held.arrivesAt = at
	return held


## sim/difficulty.ts afterQuiet, with the world's quiet window.
static func after_quiet(world: Dictionary, at: int) -> int:
	var start: Variant = world.get("quietStart")
	var end: Variant = world.get("quietEnd")
	if start == null or end == null or int(start) == int(end):
		return at
	var day := 1440
	var minute := floori(at / 60000.0)
	var local := posmod(minute + int(world.get("quietUtcOffset", 0)), day)
	var quiet := (local >= int(start) and local < int(end)) if int(start) < int(end) else (local >= int(start) or local < int(end))
	if not quiet:
		return at
	var wait := int(end) - local
	if wait <= 0:
		wait += day
	return (minute + wait) * 60000


## Fear as this world's hordes heed it (Story hordes don't learn).
static func fear_of(server: LocalServer, world: Dictionary) -> Dictionary:
	var weight := float(server.data.difficulty.presets[world.difficulty].fearWeight)
	var weighted := {}
	for key in world.fear:
		weighted[key] = float(world.fear[key]) * weight
	return weighted


## Raids on every standing outpost near the rest of a march.
static func plan_raids(server: LocalServer, world: Dictionary, wave: Dictionary, from_ms: int) -> void:
	var outposts: Array = []
	for v in world.villages:
		for plot in LocalVillage.outpost_plots(v.state.plots):
			if int(v.state.plots[plot].level) > 0:
				outposts.append({"villageId": v.id, "plot": plot, "cell": LocalVillage.outpost_hex(plot)})
	schedule_raids(server, world, wave, outposts, from_ms)


## An outpost has just been (re)built: hordes still on the march may pass it.
static func outpost_standing(server: LocalServer, world: Dictionary, target: Dictionary, at: int) -> void:
	var marching: Array = world.waves.filter(func(w: Dictionary) -> bool: return w.status == "marching")
	marching.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.index) < int(b.index))
	for wave in marching:
		schedule_raids(server, world, wave, [target], at - int(wave.spawnAt))


static func schedule_raids(server: LocalServer, world: Dictionary, wave: Dictionary, outposts: Array, from_ms: int) -> void:
	if wave.path == null:
		return
	var reach := int(server.data.enemies.fronts[wave.front].personality.raidReach)
	for raid in raids_along(wave.path, outposts, reach, from_ms):
		var payload := {"waveId": wave.id, "villageId": raid.villageId, "plot": raid.plot}
		if not server.pending(world, "outpost_raid", payload):
			server.schedule(world, int(wave.spawnAt) + int(raid.atMs), "outpost_raid", payload)


## The target's owner hears of a horde a few hours before it arrives.
static func plan_warning(server: LocalServer, world: Dictionary, wave: Dictionary, at: int) -> void:
	if wave.targetVillageId == null or wave.arrivesAt == null:
		return
	var target := server.find_village(world, int(wave.targetVillageId))
	var hours := float(server.data.notifications.waveWarningHours) + LocalWalls.warning_hours(server.data, target.state.plots)
	var warn_at := LocalTime.ms(int(wave.arrivesAt) - (hours * LocalTime.MS_PER_HOUR) / world.speed)
	server.schedule(world, warn_at if warn_at > at else at, "wave_warning", {"waveId": wave.id})
