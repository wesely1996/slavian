class_name LocalEdgeWalls
## Walls along hex edges in a solo world (sim/edgeWalls.ts,
## scheduler/edgeWalls.ts; data/field.json edgeWalls): a village raises one
## (or a gatehouse) tier by tier; standing, nobody crosses it but the
## players' own through a gatehouse. A horde planning its road weighs tearing
## one down against going round (LocalHordes.route_from); one that does
## (wall_breach, when it is through) leaves no wall. A wall finished in a
## marching horde's way makes it plan its road again. A gatehouse on an edge
## of its owner's fort's hex is the fort's outermost wall ring.

## The ring a gatehouse merged with a fort stands as (after the fort's 0..2).
const GATE_RING := 3
## A horde through a wall may already be at its target, the same moment.
const THROUGH := ["marching", "battling", "arrived", "razing"]


## What raising a wall (or a gatehouse) to `tier` costs.
static func tier_cost(data: Dictionary, kind: String, tier: int) -> Dictionary:
	var rules: Dictionary = data.field.edgeWalls
	var base: Dictionary = rules.tiers[tier - 1].cost
	if kind == "wall":
		return base.duplicate()
	var gate: Dictionary = rules.gatehouse
	var iron: Array = gate.iron
	var out := {}
	for r in ["wood", "stone", "grain", "iron"]:
		out[r] = LocalWaves.js_round(float(base[r]) * float(gate.costFactor)) + (int(iron[tier - 1] if tier - 1 < iron.size() else iron[-1]) if r == "iron" else 0)
	return out


## How long raising it to `tier` takes, in game seconds.
static func tier_seconds(data: Dictionary, kind: String, tier: int) -> float:
	var seconds := float(data.field.edgeWalls.tiers[tier - 1].buildSeconds)
	return seconds * float(data.field.edgeWalls.gatehouse.timeFactor) if kind == "gate" else seconds


## How many game hours a horde takes to tear it down ({gate, tier}).
static func break_hours(data: Dictionary, wall: Dictionary) -> float:
	var hours := float(data.field.edgeWalls.tiers[maxi(1, int(wall.tier)) - 1].breakHours)
	return hours * float(data.field.edgeWalls.gatehouse.breakFactor) if wall.gate else hours


## The fort wall ring level a gatehouse of `tier` counts as.
static func gate_ring_level(data: Dictionary, tier: int) -> int:
	var levels: Array = data.field.edgeWalls.gatehouse.fortRingLevels
	return int(levels[mini(levels.size(), maxi(1, tier)) - 1])


static func gate_ring_plots(data: Dictionary, tier: int) -> Dictionary:
	return {"w": {"building": "wall", "level": gate_ring_level(data, tier)}}


## The walls a road crosses from `from_ms` on: [{key, atMs}].
static func walls_crossed(path: Array, walls: Dictionary, from_ms := 0) -> Array:
	var out: Array = []
	for i in range(1, path.size()):
		var step: Dictionary = path[i]
		if int(step.atMs) < from_ms:
			continue
		var key := LocalLand.edge_key(Vector2i(int(path[i - 1].q), int(path[i - 1].r)), Vector2i(int(step.q), int(step.r)))
		if walls.has(key):
			out.append({"key": key, "atMs": int(step.atMs)})
	return out


## The world's walls in the server's order (by their ends).
static func listed(world: Dictionary) -> Array:
	var out: Array = world.get("walls", []).duplicate()
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		var p := [x.a.x, x.a.y, x.b.x, x.b.y, int(x.get("side", 0))]
		var q := [y.a.x, y.a.y, y.b.x, y.b.y, int(y.get("side", 0))]
		for i in 5:
			if p[i] != q[i]:
				return p[i] < q[i]
		return false)
	return out


static func wall_at(world: Dictionary, a: Vector2i, b: Vector2i, side := 0) -> Dictionary:
	var key := LocalLand.edge_key(a, b)
	for w in world.get("walls", []):
		if LocalLand.edge_key(w.a, w.b) == key and int(w.get("side", 0)) == side:
			return w
	return {}


## db/edgeWalls.ts bankSide: 1 for the bank of the stored first end, 2 the other.
static func bank_side(a: Vector2i, b: Vector2i, bank: Vector2i) -> int:
	return 1 if LocalServer._ordered(a, b)[0] == bank else 2


## Which side of a|b a wall from `bank` stands on: one on each bank of a
## river edge, one along a dry edge (scheduler/edgeWalls.ts sideFor).
static func side_for(world: Dictionary, a: Vector2i, b: Vector2i, bank: Variant) -> int:
	var key := LocalLand.edge_key(a, b)
	for e in world.rivers:
		if LocalLand.edge_key(e.a, e.b) == key:
			return bank_side(a, b, bank if bank != null else a)
	return 0


static func _remove(world: Dictionary, wall: Dictionary) -> void:
	world.walls = world.walls.filter(func(w: Dictionary) -> bool: return w != wall)


## The land's walls (LocalHordes.land_of): {edge key: [{gate, tier, enemy}]}
## (one on each bank of a river edge).
static func land_walls(world: Dictionary) -> Dictionary:
	var out := {}
	for w in listed(world):
		if w.status != "building":
			var key := LocalLand.edge_key(w.a, w.b)
			if not out.has(key):
				out[key] = []
			out[key].append({"gate": w.kind == "gate", "tier": int(w.tier), "enemy": w.get("front") != null})
	return out


## map.walls: [aq, ar, bq, br, kind, status, tier, ownerAccountId, completesAt, front, side].
static func view(world: Dictionary) -> Array:
	return listed(world).map(func(w: Dictionary) -> Array:
		return [w.a.x, w.a.y, w.b.x, w.b.y, w.kind, w.status, int(w.tier), w.ownerAccountId, LocalTime.iso(w.completesAt) if w.completesAt != null else null, w.get("front"), int(w.get("side", 0))])


## scheduler/edgeWalls.ts buildEdgeWall.
static func build(server: LocalServer, world: Dictionary, village: Dictionary, a: Vector2i, b: Vector2i, kind: String, at: int, bank: Variant = null) -> Dictionary:
	var data := server.data
	var rules: Dictionary = data.field.edgeWalls
	if village.ruin != null:
		return LocalVillage.rule("A ruin raises no walls")
	var home := Vector2i(village.q, village.r)
	if HexMath.distance(a, b) != 1:
		return LocalVillage.rule("A wall runs between two neighbouring hexes")
	if mini(HexMath.distance(a, home), HexMath.distance(b, home)) > int(rules.range):
		if not LocalForts.in_zone(data, world.forts, int(village.id), a) and not LocalForts.in_zone(data, world.forts, int(village.id), b):
			return LocalVillage.rule("Walls go within %d hexes of the village or in its forts' zones" % int(rules.range))
	for end in [a, b]:
		var type: Variant = world.hexes.get(LocalLand.key(end))
		if type == null or data.terrain.terrain[type].moveCost == null:
			return LocalVillage.rule("No wall can stand there")
	var side := side_for(world, a, b, bank)
	var existing := wall_at(world, a, b, side)
	if not existing.is_empty() and existing.kind != kind:
		return LocalVillage.rule("A gatehouse stands there" if existing.kind == "gate" else "A wall stands there")
	if not existing.is_empty() and existing.ownerAccountId != village.ownerAccountId:
		return LocalVillage.rule("That wall is not yours")
	if existing.get("status") == "building" or existing.get("status") == "upgrading":
		return LocalVillage.rule("That wall is being raised")
	if not existing.is_empty() and int(existing.tier) >= rules.tiers.size():
		return LocalVillage.rule("That wall is as strong as it gets")
	var tier := int(existing.tier) + 1 if not existing.is_empty() else 1
	var ledger := LocalLedger.spend(village.state.ledger, at, tier_cost(data, kind, tier))
	if ledger.has("missing"):
		return ledger
	village.state.ledger = ledger
	var completes_at := LocalTime.ms(at + (tier_seconds(data, kind, tier) * 1000.0) / world.speed)
	var wall := existing
	if wall.is_empty():
		var ends := LocalServer._ordered(a, b)
		wall = {"a": ends[0], "b": ends[1], "kind": kind, "tier": 0, "status": "building", "builtBy": village.id, "ownerAccountId": village.ownerAccountId, "completesAt": completes_at, "front": null, "side": side}
		if not world.has("walls"):
			world.walls = []
		world.walls.append(wall)
	else:
		wall.status = "upgrading"
		wall.builtBy = village.id
		wall.completesAt = completes_at
	server.schedule(world, completes_at, "edge_wall_built", {"aq": a.x, "ar": a.y, "bq": b.x, "br": b.y, "side": side})
	return wall


## Tears down a wall of the village's owner (nothing comes back).
static func tear_down(world: Dictionary, village: Dictionary, a: Vector2i, b: Vector2i, bank: Variant = null) -> Dictionary:
	var wall := wall_at(world, a, b, side_for(world, a, b, bank))
	if wall.is_empty():
		return LocalVillage.rule("No wall stands there")
	if wall.ownerAccountId != village.ownerAccountId:
		return LocalVillage.rule("That wall is not yours")
	_remove(world, wall)
	return wall


## A horde has set out (or set out again `from_ms` into its march): a breach
## planned for every wall on the rest of its road (scheduler/edgeWalls.ts
## planBreaches; from LocalHordes.plan_raids).
static func plan_breaches(server: LocalServer, world: Dictionary, wave: Dictionary, from_ms: int) -> void:
	if wave.path == null:
		return
	var walls := {}
	for w in listed(world):
		if w.status != "building":
			var key := LocalLand.edge_key(w.a, w.b)
			if not walls.has(key):
				walls[key] = []
			walls[key].append(w)
	for crossed in walls_crossed(wave.path, walls, from_ms):
		# Every wall on the edge (one on each bank of a river) comes down.
		for w in walls[crossed.key]:
			var payload := {"waveId": wave.id, "aq": w.a.x, "ar": w.a.y, "bq": w.b.x, "br": w.b.y, "side": int(w.get("side", 0))}
			if not server.pending(world, "wall_breach", payload):
				server.schedule(world, int(wave.spawnAt) + int(crossed.atMs), "wall_breach", payload)


## A wall finished across a marching horde's road: it plans its road again
## from the hex it is heading for, through the wall or round it.
static func _avoid_wall(server: LocalServer, world: Dictionary, key: String, at: int) -> void:
	var data := server.data
	var land := LocalHordes.land_of(world)
	var waves: Array = world.waves.filter(func(w: Dictionary) -> bool: return not w.status in ["dispersed", "defeated", "settled"])
	waves.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x.index) < int(y.index) or (int(x.index) == int(y.index) and int(x.id) < int(y.id)))
	for wave in waves:
		if wave.status != "marching" or wave.path == null:
			continue
		var since_spawn := at - int(wave.spawnAt)
		if walls_crossed(wave.path, {key: true}, since_spawn).is_empty():
			continue
		var target := server.find_village(world, int(wave.targetVillageId)) if wave.targetVillageId != null else {}
		var goal := {"id": target.id, "cell": Vector2i(target.q, target.r)} if not target.is_empty() else {"id": null, "cell": Vector2i.ZERO}
		var path: Variant = LocalLogistics.splice_route(wave.path, since_spawn, func(from: Vector2i) -> Variant:
			var route: Variant = LocalHordes.route_from(data, land, from, [goal], wave.front, wave.composition, {}, LocalWaves.rng_for(int(world.seed), int(wave.index), 0xe1), 0.0, world.speed)
			return route.path if route != null else null)
		if path == null:
			continue
		var march := LocalHordes.hold_for_quiet(world, int(wave.spawnAt), {"path": path, "arrivesAt": int(wave.spawnAt) + int(path[-1].atMs)})
		wave.status = "marching"
		wave.path = march.path
		wave.arrivesAt = march.arrivesAt
		wave.endsAt = null
		LocalHordes.cancel_plans(world, wave)
		server.schedule(world, int(march.arrivesAt), "wave_arrive", {"waveId": wave.id})
		LocalHordes.plan_raids(server, world, wave, since_spawn)
		LocalArmies.plan_intercepts(server, world, wave, since_spawn + 1)


## The gatehouse of the fort's owner on an edge of its hex (the strongest),
## merged with it as its outermost ring; {} for none.
static func fort_gatehouse(world: Dictionary, cell: Vector2i, owner: Variant) -> Dictionary:
	var around := {}
	for n in HexMath.neighbors(cell):
		around[LocalLand.edge_key(cell, n)] = true
	var best := {}
	for w in listed(world):
		if w.kind == "gate" and w.status != "building" and w.ownerAccountId == owner and around.has(LocalLand.edge_key(w.a, w.b)):
			if best.is_empty() or int(w.tier) > int(best.tier):
				best = w
	return best


static func _merged_with_fort(world: Dictionary, wall: Dictionary) -> bool:
	if wall.kind != "gate":
		return false
	var keys := [LocalLand.key(wall.a), LocalLand.key(wall.b)]
	return world.forts.any(func(f: Dictionary) -> bool:
		return f.get("kind", "fort") == "fort" and f.status == "standing" and f.ownerAccountId == wall.ownerAccountId and LocalLand.key(Vector2i(int(f.q), int(f.r))) in keys)


## A fort's battle battered its gatehouse down: a tier lower, or gone.
static func breach_gatehouse(world: Dictionary, a: Vector2i, b: Vector2i, side := 0) -> void:
	var wall := wall_at(world, a, b, side)
	if wall.is_empty():
		return
	if int(wall.tier) <= 1:
		_remove(world, wall)
		return
	wall.tier = int(wall.tier) - 1
	if wall.status == "upgrading":
		wall.status = "standing"
		wall.completesAt = null


static func on_edge_wall_built(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var p: Dictionary = event.payload
	var wall := wall_at(world, Vector2i(int(p.aq), int(p.ar)), Vector2i(int(p.bq), int(p.br)), int(p.get("side", 0)))
	if wall.is_empty() or wall.status == "standing" or wall.completesAt == null or int(wall.completesAt) != int(event.dueAt):
		return
	wall.tier = int(wall.tier) + 1
	wall.status = "standing"
	wall.completesAt = null
	_avoid_wall(server, world, LocalLand.edge_key(wall.a, wall.b), int(event.dueAt))
	changed.append(["world"])
	changed.append(["waves"])


## A horde through a wall on its road: it tore the wall down.
static func on_wall_breach(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var p: Dictionary = event.payload
	var wave := server.find_wave(world, int(p.waveId))
	if wave.is_empty() or not wave.status in THROUGH:
		return
	var wall := wall_at(world, Vector2i(int(p.aq), int(p.ar)), Vector2i(int(p.bq), int(p.br)), int(p.get("side", 0)))
	if wall.is_empty() or wall.status == "building" or _merged_with_fort(world, wall):
		return
	_remove(world, wall)
	changed.append(["world"])
	LocalInbox.tell(server, world, wall.ownerAccountId, {"kind": "outpost_raided", "tier": "push",
		"title": "A horde broke down your gatehouse" if wall.kind == "gate" else "A horde tore down your wall",
		"body": "Between ({aq}, {ar}) and ({bq}, {br}).", "vars": {"aq": wall.a.x, "ar": wall.a.y, "bq": wall.b.x, "br": wall.b.y}}, int(event.dueAt))
