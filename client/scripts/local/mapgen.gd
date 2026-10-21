class_name LocalMapgen
extends RefCounted
## World map generation for the local engine: a line-by-line port of
## server/src/sim/mapgen.ts, so a seed makes the same map in the app as on the
## server. Checked against data/fixtures/mapgen-vectors.json (written by the
## server's `npm run fixtures`); change both together.
##
## A map: {seed, radius, activeFronts, terrain: {"q,r": id} in spiral order,
## startSites: [Vector2i], rivers: [{a, b, bridge, size}]}.

const FRONTS := ["north", "east", "south", "west"]
const START_RING := 2
const EDGE_BELT_WIDTH := 2
const MAX_ATTEMPTS := 20
## How much lower a river reckons a step towards an older river (it joins it).
const JOIN_PULL := 0.25
## Terrain a river flows into and never runs along.
const WATER := ["lake", "ocean"]
const MASK := 0xffffffff


static func radius_for(players: int) -> int:
	return 10 if players <= 2 else int(floor(10 + (players - 2) * 1.5 + 0.5))


static func active_fronts_for(players: int) -> Array:
	if players <= 1:
		return ["north", "south"]
	if players == 2:
		return ["north", "south", "east"]
	return ["north", "east", "south", "west"]


## Which front a hex faces, by its angle from the centre (y grows downward).
static func front_of(cell: Vector2i) -> String:
	var angle := atan2(LocalLand.pixel_y(cell), LocalLand.pixel_x(cell)) * 180.0 / PI
	if angle >= -135 and angle < -45:
		return "north"
	if angle >= -45 and angle < 45:
		return "east"
	if angle >= 45 and angle < 135:
		return "south"
	return "west"


static func generate(data: Dictionary, seed_value: int, players: int) -> Dictionary:
	for attempt in MAX_ATTEMPTS:
		var s := seed_value + attempt * 7919
		var candidate := _candidate(s, players)
		var map: Dictionary = candidate.map
		var rivers := _lay_rivers(map, candidate.elevation, LocalRng.new((s ^ 0x51a5) & MASK))
		map.rivers = _bridge_roads(data, map, rivers)
		if _is_playable(data, map):
			return map
	push_error("No playable map found for seed %d" % seed_value)
	return {}


static func _candidate(seed_value: int, players: int) -> Dictionary:
	var rng := LocalRng.new(seed_value)
	var elevation := LocalNoise.new(rng.callable())
	var moisture := LocalNoise.new(rng.callable())
	var radius := radius_for(players)
	var fronts := active_fronts_for(players)
	var terrain := {}
	var heights := {}
	for cell in HexMath.spiral(Vector2i.ZERO, radius):
		var dist := HexMath.distance(cell, Vector2i.ZERO)
		var px := LocalLand.pixel_x(cell)
		var py := LocalLand.pixel_y(cell)
		var e := _fbm(elevation, 0.09, px, py)
		var m := _fbm(moisture, 0.07, px, py)
		heights[LocalLand.key(cell)] = e
		var type: String
		if dist == 0:
			type = "holy_city"
		elif dist > radius - EDGE_BELT_WIDTH:
			type = _edge_terrain(front_of(cell), fronts, dist == radius, m)
		else:
			type = _interior_terrain(e, m)
			if dist <= START_RING and not type in ["plains", "forest", "hills"]:
				type = "plains"
		terrain[LocalLand.key(cell)] = type
	var start_ring := HexMath.ring(Vector2i.ZERO, START_RING)
	var starts: Array[Vector2i] = []
	for i in players:
		starts.append(start_ring[int(floor(float(i * start_ring.size()) / players + 0.5)) % start_ring.size()])
	var map := {"seed": seed_value, "radius": radius, "activeFronts": fronts, "terrain": terrain, "startSites": starts, "rivers": []}
	return {"map": map, "elevation": heights}


## Fractal noise in roughly [-1, 1].
static func _fbm(noise: LocalNoise, frequency: float, x: float, y: float, octaves := 4) -> float:
	var sum := 0.0
	var amplitude := 1.0
	var norm := 0.0
	var f := frequency
	for i in octaves:
		sum += noise.noise(x * f, y * f) * amplitude
		norm += amplitude
		amplitude *= 0.5
		f *= 2
	return sum / norm


static func _interior_terrain(e: float, m: float) -> String:
	if e > 0.38:
		return "mountain"
	if e > 0.2:
		return "hills"
	if e < -0.4 and m > 0:
		return "lake"
	if e < -0.15 and m > 0.3:
		return "swamp"
	if m > 0.05:
		return "forest"
	return "plains"


static func _edge_terrain(front: String, active: Array, outermost: bool, m: float) -> String:
	if not front in active:
		return "ocean"
	match front:
		"north":
			return "ice" if outermost and m < 0.1 else "dark_forest"
		"east":
			return "steppe"
	return "hallowed"


## Rivers along hex edges, downhill from the hills and mountains until the
## corner ahead is water or off the map, or an older river they join.
static func _lay_rivers(map: Dictionary, elevation: Dictionary, rng: LocalRng) -> Array:
	var radius: int = map.radius
	var terrain: Dictionary = map.terrain
	var on_map := func(h: Vector2i) -> bool: return terrain.has(LocalLand.key(h))
	var type_of := func(h: Vector2i) -> String: return String(terrain.get(LocalLand.key(h), ""))
	var water := func(h: Vector2i) -> bool: return String(terrain.get(LocalLand.key(h), "")) in WATER
	var bank := func(h: Vector2i) -> bool: return on_map.call(h) and not water.call(h) and type_of.call(h) != "holy_city"
	var elev := func(h: Vector2i) -> float: return float(elevation.get(LocalLand.key(h), 0.0))
	var height := func(a: Vector2i, b: Vector2i) -> float: return (float(elev.call(a)) + float(elev.call(b))) / 2.0
	var laid := {}
	var sources: Array = []
	for cell in HexMath.spiral(Vector2i.ZERO, radius - EDGE_BELT_WIDTH):
		if not String(type_of.call(cell)) in ["hills", "mountain"]:
			continue
		for n in HexMath.neighbors(cell):
			if LocalLand.key(cell) < LocalLand.key(n) and HexMath.distance(n, Vector2i.ZERO) <= radius - EDGE_BELT_WIDTH and bank.call(cell) and bank.call(n):
				sources.append([cell, n])
	var order: Array[String] = []
	var wanted := 2 + int(floor(radius / 6.0))
	var tries := 0
	while tries < 60 and order.size() < wanted * 8 and sources.size() > 0:
		tries += 1
		var source: Array = sources.pop_at(int(floor(rng.next() * sources.size())))
		var a0: Vector2i = source[0]
		var b0: Vector2i = source[1]
		if laid.has(LocalLand.edge_key(a0, b0)):
			continue
		var ends0 := LocalLand.common_neighbors(a0, b0)
		var a := a0
		var b := b0
		var ahead: Vector2i = ends0[0] if float(elev.call(ends0[0])) <= float(elev.call(ends0[1])) else ends0[1]
		var river: Array = [{"a": a, "b": b, "into": _corner([a, b, ahead])}]
		var seen := {LocalLand.edge_key(a, b): true}
		var mouth := ""
		var joins := ""
		for step in radius * 4:
			if not on_map.call(ahead) or water.call(ahead):
				mouth = "water"
				break
			var here := _corner([a, b, ahead])
			var leaving := ""
			for k in [LocalLand.edge_key(a, ahead), LocalLand.edge_key(b, ahead)]:
				if laid.has(k) and laid[k].into != here:
					leaving = k
					break
			if leaving != "":
				mouth = "join"
				joins = leaving
				break
			var options: Array = [[a, ahead], [b, ahead]]
			var lowness := func(x: Array) -> float:
				var pull := 0.0
				for h in LocalLand.common_neighbors(x[0], x[1]):
					if laid.has(LocalLand.edge_key(x[0], h)) or laid.has(LocalLand.edge_key(x[1], h)):
						pull = JOIN_PULL
						break
				return float(height.call(x[0], x[1])) - pull
			# Array.sort with a comparator on two items, as V8 runs it: one
			# call with the second item first, and a swap when it is below 0.
			var lower: float = lowness.call(options[1]) - lowness.call(options[0]) + (rng.next() - 0.5) * 0.08
			if lower < 0:
				options = [options[1], options[0]]
			var moved := false
			for option in options:
				var p: Vector2i = option[0]
				var q: Vector2i = option[1]
				var key := LocalLand.edge_key(p, q)
				if seen.has(key) or laid.has(key) or not bank.call(p) or not bank.call(q):
					continue
				var other := b if p == a else a
				var next := Vector2i.MAX
				for h in LocalLand.common_neighbors(p, q):
					if LocalLand.key(h) != LocalLand.key(other):
						next = h
						break
				if next == Vector2i.MAX:
					continue
				a = p
				b = q
				ahead = next
				river.append({"a": a, "b": b, "into": _corner([a, b, ahead])})
				seen[key] = true
				moved = true
				break
			if not moved:
				break
		if mouth == "" or river.size() < 3:
			continue
		for i in river.size():
			var e: Dictionary = river[i]
			var key := LocalLand.edge_key(e.a, e.b)
			var down: String = LocalLand.edge_key(river[i + 1].a, river[i + 1].b) if i + 1 < river.size() else joins
			laid[key] = {"a": e.a, "b": e.b, "into": e.into, "down": down, "size": 1}
			order.append(key)
		# Everything below the meeting point carries this river's water too.
		var k := joins
		while k != "":
			laid[k].size += 1
			k = laid[k].down
	var out: Array = []
	for i in order.size():
		var e: Dictionary = laid[order[i]]
		out.append({"a": e.a, "b": e.b, "bridge": (i + 2) % 5 == 0, "size": e.size})
	return out


static func _corner(hexes: Array) -> String:
	var keys: Array[String] = []
	for h in hexes:
		keys.append(LocalLand.key(h))
	keys.sort()
	return "/".join(keys)


## The terrain's move cost onto `to` (-1: impassable), with `blocked` edges.
static func _move_cost(data: Dictionary, terrain: Dictionary, blocked: Dictionary) -> Callable:
	return func(from: Vector2i, to: Vector2i) -> float:
		var type: Variant = terrain.get(LocalLand.key(to))
		if type == null or blocked.has(LocalLand.edge_key(from, to)):
			return -1.0
		var cost: Variant = data.terrain.terrain[type].moveCost
		return -1.0 if cost == null else float(cost)


static func _spawn(front: String, radius: int, cost: Callable) -> Variant:
	for cell in HexMath.ring(Vector2i.ZERO, radius):
		if front_of(cell) == front and float(cost.call(cell, cell)) >= 0.0:
			return cell
	return null


## Every front's road to each start and the Holy City, and each start's road
## to the city, gets a bridge wherever it crosses a river.
static func _bridge_roads(data: Dictionary, map: Dictionary, rivers: Array) -> Array:
	var by_edge := {}
	for e in rivers:
		by_edge[LocalLand.edge_key(e.a, e.b)] = e
	var terrain_cost := _move_cost(data, map.terrain, {})
	var cost := func(from: Vector2i, to: Vector2i) -> float:
		var base: float = terrain_cost.call(from, to)
		if base < 0.0:
			return -1.0
		var edge: Variant = by_edge.get(LocalLand.edge_key(from, to))
		return base + 6 if edge != null and not edge.bridge else base
	var roads: Array = []
	for s in map.startSites:
		roads.append([s, Vector2i.ZERO])
	for front in map.activeFronts:
		var spawn: Variant = _spawn(front, map.radius, terrain_cost)
		if spawn == null:
			continue
		roads.append([spawn, Vector2i.ZERO])
		for s in map.startSites:
			roads.append([spawn, s])
	for road in roads:
		var path: Variant = LocalLand.find_path(road[0], road[1], cost)
		if path == null:
			continue
		for i in range(1, path.size()):
			var key := LocalLand.edge_key(path[i - 1], path[i])
			var edge: Variant = by_edge.get(key)
			if edge != null and not edge.bridge:
				var bridged: Dictionary = edge.duplicate()
				bridged.bridge = true
				by_edge[key] = bridged
	return by_edge.values()


## Every active front must reach every start and the Holy City.
static func _is_playable(data: Dictionary, map: Dictionary) -> bool:
	var blocked := {}
	for e in map.rivers:
		if not e.bridge:
			blocked[LocalLand.edge_key(e.a, e.b)] = true
	var cost := _move_cost(data, map.terrain, blocked)
	for front in map.activeFronts:
		var spawn: Variant = _spawn(front, map.radius, cost)
		if spawn == null:
			return false
		var targets: Array = [Vector2i.ZERO]
		targets.append_array(map.startSites)
		for target in targets:
			if LocalLand.find_path(spawn, target, cost) == null:
				return false
	return true
