class_name LocalEnemySettlements
## The enemy's settlements in a solo world (sim/enemySettlements.ts,
## scheduler/enemySettlements.ts; data/enemy-lands.json settlements): each
## active front founds the next of its settlements every few game days
## (enemy_found), the deepest band first, and every few game hours each that
## builds does one work (enemy_works): a wall, a stretch of road, a bridge, a
## moat, a tier. Their lands get their rivers the first time (ensure).

const MASK := 0xffffffff
const FRONTS := ["north", "east", "south", "west"]


static func _lands_by_key(data: Dictionary, world: Dictionary) -> Dictionary:
	var out := {}
	for e in LocalEnemyLands.of_world(data, world):
		out[LocalLand.key(e.cell)] = e
	return out


## Open land of `front` a settlement, a wall or a river may stand on.
static func _open(data: Dictionary, lands: Dictionary, cell: Vector2i, front: String) -> bool:
	var e: Variant = lands.get(LocalLand.key(cell))
	return e != null and e.front == front and data.terrain.terrain[e.terrain].moveCost != null


## The settlements a front founds, in order: [{kind, band}], the deepest first.
static func founding_order(data: Dictionary, front: String) -> Array:
	var rules: Dictionary = data.enemyLands.settlements
	var out: Array = []
	if front == "north":
		for l in rules.lairs:
			for i in int(l.max):
				out.append({"kind": "lair", "band": int(l.band)})
		return out
	var kinds: Array = []
	for kind in rules.kinds:
		var k: Dictionary = rules.kinds[kind]
		if int(k.band) > 0 and int(k.max) > 0:
			kinds.append([kind, k])
	kinds.sort_custom(func(x: Array, y: Array) -> bool: return int(x[1].band) > int(y[1].band))
	for entry in kinds:
		for i in int(entry[1].max):
			out.append({"kind": String(entry[0]), "band": int(entry[1].band)})
	return out


## Where a front's `index`-th settlement goes ({} when none is left).
static func site(data: Dictionary, world: Dictionary, front: String, index: int, taken: Array) -> Dictionary:
	var order := founding_order(data, front)
	if index >= order.size() or world.get("radius") == null:
		return {}
	var next: Dictionary = order[index]
	var lands := _lands_by_key(data, world)
	var apart := int(data.enemyLands.settlements.minApart)
	var candidates: Array = []
	for e in lands.values():
		if e.front != front or int(e.band) != int(next.band) or not _open(data, lands, e.cell, front):
			continue
		# Not on the lands' outer rim.
		if not HexMath.neighbors(e.cell).all(func(n: Vector2i) -> bool: return lands.has(LocalLand.key(n)) or HexMath.distance(n, Vector2i.ZERO) <= int(world.radius)):
			continue
		if taken.all(func(t: Vector2i) -> bool: return HexMath.distance(t, e.cell) >= apart):
			candidates.append(e)
	if candidates.is_empty():
		return {}
	var rng := LocalRng.new((int(world.seed) + 7919 * index + 104729 * FRONTS.find(front) + 0x5e7) & MASK)
	return {"kind": next.kind, "band": next.band, "cell": candidates[floori(rng.next() * candidates.size())].cell}


## Rivers through each active front's lands (sim/enemySettlements.ts enemyRivers).
static func rivers(data: Dictionary, world: Dictionary) -> Array:
	if world.get("radius") == null:
		return []
	var rules: Dictionary = data.enemyLands.rivers
	var lands := _lands_by_key(data, world)
	var deepest: int = data.enemyLands.bands.size()
	var laid := {}
	var out: Array = []
	for front in world.activeFronts:
		var bank := func(h: Vector2i) -> bool: return _open(data, lands, h, front)
		var sources: Array = lands.values().filter(func(e: Dictionary) -> bool: return e.front == front and int(e.band) == deepest and bank.call(e.cell))
		for i in int(rules.perFront):
			if sources.is_empty():
				break
			var rng := LocalRng.new((int(world.seed) + 31337 + 7919 * i + 104729 * FRONTS.find(front)) & MASK)
			var start: Vector2i = sources[floori(rng.next() * sources.size())].cell
			var firsts: Array = HexMath.neighbors(start).filter(func(n: Vector2i) -> bool: return bank.call(n) and not laid.has(LocalLand.edge_key(start, n)))
			if firsts.is_empty():
				continue
			var a := start
			var b: Vector2i = firsts[floori(rng.next() * firsts.size())]
			var corners := LocalLand.common_neighbors(a, b)
			var ahead: Vector2i = corners[1] if HexMath.distance(corners[1], Vector2i.ZERO) < HexMath.distance(corners[0], Vector2i.ZERO) else corners[0]
			var river: Array = [[a, b]]
			var seen := {LocalLand.edge_key(a, b): true}
			for step in deepest * 8:
				var e: Variant = lands.get(LocalLand.key(ahead))
				if e == null or e.front != front or not bank.call(ahead) or int(e.band) == 0:
					break
				var options: Array = []
				for pq in [[a, ahead], [b, ahead]]:
					var other: Vector2i = b if pq[0] == a else a
					var next: Vector2i = Vector2i.MAX
					for h in LocalLand.common_neighbors(pq[0], pq[1]):
						if h != other:
							next = h
							break
					options.append({"p": pq[0], "q": pq[1], "next": next, "score": HexMath.distance(next, Vector2i.ZERO) + rng.next() * 0.9})
				if float(options[1].score) < float(options[0].score):
					options.reverse()
				var moved := false
				var joined := false
				for o in options:
					var key := LocalLand.edge_key(o.p, o.q)
					if laid.has(key):
						joined = true
						break
					if seen.has(key) or not bank.call(o.p) or not bank.call(o.q):
						continue
					a = o.p
					b = o.q
					ahead = o.next
					river.append([a, b])
					seen[key] = true
					moved = true
					break
				if joined or not moved:
					break
			if river.size() < int(rules.minLength):
				continue
			for k in river.size():
				laid[LocalLand.edge_key(river[k][0], river[k][1])] = true
				out.append({"a": river[k][0], "b": river[k][1], "bridge": (k + 2) % int(rules.fordEvery) == 0, "size": 1})
	return out


## The older settlement of its front a settlement's road runs to ({} for none).
static func road_target(settlement: Dictionary, all: Array) -> Dictionary:
	var best := {}
	for s in all:
		if s.front != settlement.front or int(s.id) >= int(settlement.id):
			continue
		if best.is_empty() or HexMath.distance(s.cell, settlement.cell) < HexMath.distance(best.cell, settlement.cell):
			best = s
	return best


static func road(data: Dictionary, world: Dictionary, from: Vector2i, to: Vector2i, front: String, state: Dictionary) -> Variant:
	var lands := _lands_by_key(data, world)
	return LocalLand.find_path(from, to, func(p: Vector2i, q: Vector2i) -> float:
		if not _open(data, lands, q, front):
			return -1.0
		var key := LocalLand.edge_key(p, q)
		if state.walls.has(key) and not state.walls[key].gate and p != from and p != to and q != from and q != to:
			return -1.0
		var cost := float(data.terrain.terrain[lands[LocalLand.key(q)].terrain].moveCost)
		return (cost * 0.5 if state.roads.has(key) else cost) + (2.0 if state.rivers.has(key) and not state.rivers[key] else 0.0), 0.5)


## sim/enemySettlements.ts nextWork ({} with nothing left).
static func next_work(data: Dictionary, world: Dictionary, s: Dictionary, target: Variant, state: Dictionary) -> Dictionary:
	var kind: Variant = data.enemyLands.settlements.kinds.get(s.kind)
	if kind == null or not kind.builds:
		return {}
	var lands := _lands_by_key(data, world)
	var bank := func(h: Vector2i) -> bool: return _open(data, lands, h, s.front)
	var cell: Vector2i = s.cell
	for d in HexMath.DIRECTIONS:
		var n: Vector2i = cell + d
		var key := LocalLand.edge_key(cell, n)
		if bank.call(n) and not state.walls.has(key) and not state.rivers.has(key):
			return {"kind": "wall", "a": cell, "b": n}
	if target != null:
		var path: Variant = road(data, world, cell, target, s.front, state)
		if path != null:
			for i in range(1, path.size()):
				var p: Vector2i = path[i - 1]
				var q: Vector2i = path[i]
				var key := LocalLand.edge_key(p, q)
				if state.roads.has(key):
					continue
				if state.rivers.has(key) and not state.rivers[key]:
					return {"kind": "bridge", "a": p, "b": q}
				var gates: Array = [{"a": p, "b": q}] if state.walls.has(key) and not state.walls[key].gate else []
				return {"kind": "road", "a": p, "b": q, "gates": gates}
	if kind.moat:
		for d in HexMath.DIRECTIONS:
			var n: Vector2i = cell + d
			if not bank.call(n):
				continue
			for m in HexMath.neighbors(n):
				if HexMath.distance(m, cell) != 2 or not bank.call(m):
					continue
				var key := LocalLand.edge_key(n, m)
				if state.rivers.has(key) or state.walls.has(key):
					continue
				return {"kind": "moat", "a": n, "b": m, "bridged": state.roads.has(key)}
	var cap := wall_tier_cap(data, String(s.kind), int(s.level))
	var lowest := {}
	for d in HexMath.DIRECTIONS:
		var n: Vector2i = cell + d
		var wall: Variant = state.walls.get(LocalLand.edge_key(cell, n))
		if wall != null and int(wall.tier) < cap and (lowest.is_empty() or int(wall.tier) < int(lowest.tier)):
			lowest = {"a": cell, "b": n, "tier": int(wall.tier)}
	if lowest.is_empty():
		return {}
	return {"kind": "raise", "a": lowest.a, "b": lowest.b, "tier": int(lowest.tier) + 1}


## A settlement's level at `at`: one every growHours game hours from its founding.
static func level_at(data: Dictionary, founded_at: int, at: int, world_speed: float) -> int:
	var rules: Dictionary = data.enemyLands.settlements
	var hours := float(at - founded_at) * world_speed / LocalTime.MS_PER_HOUR
	return mini(int(rules.maxLevel), 1 + floori(maxf(0.0, hours) / float(rules.growHours)))


## The highest tier its walls rise to at `level`.
static func wall_tier_cap(data: Dictionary, kind: String, level: int) -> int:
	var rules: Dictionary = data.enemyLands.settlements
	return mini(int(rules.kinds.get(kind, {}).get("wallTier", 0)), 1 + floori(float(level - 1) / float(rules.levelsPerWallTier)))


static func settlement_name(data: Dictionary, front: String, kind: String) -> String:
	return String(data.enemyLands.settlements.names.get(front, {}).get(kind, kind))


static func _found_every(data: Dictionary, world: Dictionary) -> float:
	return float(data.enemyLands.settlements.everyDays) * float(data.seasons.dayHours) * LocalTime.MS_PER_HOUR / float(world.speed)


static func _works_every(data: Dictionary, world: Dictionary) -> float:
	return float(data.enemyLands.settlements.worksEveryHours) * LocalTime.MS_PER_HOUR / float(world.speed)


static func _pending(world: Dictionary, type: String) -> bool:
	return world.events.any(func(e: Dictionary) -> bool: return e.status == "pending" and e.type == type)


## Rivers into the world's river list (insertRivers: ON CONFLICT DO NOTHING).
static func _insert_rivers(world: Dictionary, edges: Array) -> void:
	var known := {}
	for e in world.rivers:
		known[LocalLand.edge_key(e.a, e.b)] = true
	for e in edges:
		var key := LocalLand.edge_key(e.a, e.b)
		if known.has(key):
			continue
		known[key] = true
		var ends := LocalServer._ordered(e.a, e.b)
		world.rivers.append({"a": ends[0], "b": ends[1], "crossing": "standing" if e.bridge else "none", "size": int(e.size), "builtBy": null, "completesAt": null, "dug": false})


## scheduler/enemySettlements.ts ensureEnemyLands.
static func ensure(server: LocalServer, world: Dictionary, now: int) -> void:
	if world.status != "running" or world.get("startedAt") == null or world.get("radius") == null or world.activeFronts.is_empty():
		return
	var data := server.data
	if not world.has("enemySettlements"):
		world.enemySettlements = []
	if not _pending(world, "enemy_found"):
		_insert_rivers(world, rivers(data, world))
		if world.enemySettlements.is_empty():
			_found(server, world, now)
		var every := _found_every(data, world)
		var rounds := floori(float(now - int(world.startedAt)) / every) + 1
		server.schedule(world, LocalTime.ms(int(world.startedAt) + rounds * every), "enemy_found", {})
	if not _pending(world, "enemy_works"):
		server.schedule(world, LocalTime.ms(now + _works_every(data, world)), "enemy_works", {})
	LocalEnemyForces.ensure(server, world, now)


## Every active front founds its next settlement, if it has one left.
static func _found(server: LocalServer, world: Dictionary, at: int) -> void:
	var taken: Array = world.enemySettlements.map(func(s: Dictionary) -> Vector2i: return s.cell)
	for front in world.activeFronts:
		var index: int = world.enemySettlements.filter(func(s: Dictionary) -> bool: return s.front == front).size()
		var next := site(server.data, world, front, index, taken)
		if next.is_empty():
			continue
		if not world.next.has("enemySettlement"):
			world.next.enemySettlement = 1
		world.enemySettlements.append({"id": world.next.enemySettlement, "front": front, "kind": next.kind, "band": int(next.band), "cell": next.cell,
			"status": "standing", "garrison": {}, "foundedAt": at})
		world.next.enemySettlement += 1
		taken.append(next.cell)


static func _edge_state(world: Dictionary) -> Dictionary:
	var walls := {}
	for w in LocalEdgeWalls.listed(world):
		if w.status != "building":
			walls[LocalLand.edge_key(w.a, w.b)] = {"tier": int(w.tier), "gate": w.kind == "gate"}
	var roads := {}
	for e in world.roads:
		roads[LocalLand.edge_key(e.a, e.b)] = true
	var river := {}
	for e in world.rivers:
		river[LocalLand.edge_key(e.a, e.b)] = e.crossing == "standing"
	return {"walls": walls, "roads": roads, "rivers": river}


static func _do_work(world: Dictionary, front: String, work: Dictionary, state: Dictionary) -> void:
	var key := LocalLand.edge_key(work.a, work.b)
	var ends := LocalServer._ordered(work.a, work.b)
	match String(work.kind):
		"wall":
			if not world.has("walls"):
				world.walls = []
			world.walls.append({"a": ends[0], "b": ends[1], "kind": "wall", "tier": 1, "status": "standing", "builtBy": null, "ownerAccountId": null, "completesAt": null, "front": front, "side": 0})
			state.walls[key] = {"tier": 1, "gate": false}
		"raise":
			var wall := LocalEdgeWalls.wall_at(world, work.a, work.b)
			if not wall.is_empty():
				wall.tier = int(work.tier)
			state.walls[key].tier = int(work.tier)
		"road":
			if not state.roads.has(key):
				world.roads.append({"a": ends[0], "b": ends[1], "status": "standing", "level": 1, "builtBy": null, "completesAt": null})
			state.roads[key] = true
			for g in work.gates:
				var wall := LocalEdgeWalls.wall_at(world, g.a, g.b)
				if not wall.is_empty():
					wall.kind = "gate"
				state.walls[LocalLand.edge_key(g.a, g.b)].gate = true
		"bridge":
			for e in world.rivers:
				if LocalLand.edge_key(e.a, e.b) == key:
					e.crossing = "standing"
			state.rivers[key] = true
		_:
			_insert_rivers(world, [{"a": work.a, "b": work.b, "bridge": work.bridged, "size": 1}])
			state.rivers[key] = work.bridged


static func on_enemy_found(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	if world.status != "running":
		return
	_found(server, world, int(event.dueAt))
	server.schedule(world, LocalTime.ms(int(event.dueAt) + _found_every(server.data, world)), "enemy_found", {})
	changed.append(["world"])


static func on_enemy_works(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	if world.status != "running":
		return
	var all: Array = world.get("enemySettlements", []).map(func(o: Dictionary) -> Dictionary:
		var spot := o.duplicate()
		spot.level = level_at(server.data, int(o.foundedAt), int(event.dueAt), float(world.speed))
		return spot)
	var state := _edge_state(world)
	for s in all:
		var target := road_target(s, all)
		var work := next_work(server.data, world, s, target.cell if not target.is_empty() else null, state)
		if work.is_empty():
			continue
		_do_work(world, String(s.front), work, state)
		changed.append(["world"])
	server.schedule(world, LocalTime.ms(int(event.dueAt) + _works_every(server.data, world)), "enemy_works", {})


## The settlements players see (api/views.ts map.settlements): those in bands seen.
static func view(data: Dictionary, world: Dictionary, now: int) -> Array:
	var out: Array = []
	for s in world.get("enemySettlements", []):
		if int(s.band) <= LocalEnemyLands.sight_of(data, world, String(s.front)):
			out.append({"id": s.id, "front": s.front, "kind": s.kind, "name": settlement_name(data, String(s.front), String(s.kind)), "band": int(s.band),
				"q": s.cell.x, "r": s.cell.y, "status": s.status, "level": level_at(data, int(s.foundedAt), now, float(world.speed)), "foundedAt": LocalTime.iso(s.foundedAt)})
	return out
