class_name LocalLand
extends RefCounted
## The server's hex keys, edges and path finding (server/src/sim/hex.ts and
## land.ts), kept identical down to the order of ties, so a path or a map
## comes out the same on both sides.

const SQRT3 := 1.7320508075688772


static func key(h: Vector2i) -> String:
	return "%d,%d" % [h.x, h.y]


## One key for the edge between two neighbours, whichever way round.
static func edge_key(a: Vector2i, b: Vector2i) -> String:
	var ka := key(a)
	var kb := key(b)
	return "%s|%s" % [ka, kb] if ka < kb else "%s|%s" % [kb, ka]


## The two hexes touching both a and b (the ends of their shared edge).
static func common_neighbors(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var around := {}
	for n in HexMath.neighbors(b):
		around[n] = true
	var out: Array[Vector2i] = []
	for n in HexMath.neighbors(a):
		if around.has(n):
			out.append(n)
	return out


## hexToPixel(h, 1) in doubles (Vector2 is single precision).
static func pixel_x(h: Vector2i) -> float:
	return SQRT3 * h.x + (SQRT3 / 2.0) * h.y


static func pixel_y(h: Vector2i) -> float:
	return 1.5 * h.y


## A* over the hex graph like the server's findPath: `step_cost(from, to)`
## returns a float, or -1.0 for impassable. Null when there is no way.
static func find_path(start: Vector2i, goal: Vector2i, step_cost: Callable, min_step_cost := 1.0, max_expanded := 10000) -> Variant:
	var heap := _Heap.new()
	var came_from := {}
	var cost_so_far := {start: 0.0}
	heap.push(start, 0.0)
	var expanded := 0
	while heap.size() > 0:
		var current: Vector2i = heap.pop()
		if current == goal:
			var path: Array[Vector2i] = [goal]
			var at := goal
			while at != start:
				at = came_from[at]
				path.append(at)
			path.reverse()
			return path
		expanded += 1
		if expanded > max_expanded:
			return null
		var current_cost: float = cost_so_far[current]
		for next in HexMath.neighbors(current):
			var step: float = step_cost.call(current, next)
			if step < 0.0:
				continue
			var new_cost := current_cost + step
			if not cost_so_far.has(next) or new_cost < cost_so_far[next]:
				cost_so_far[next] = new_cost
				came_from[next] = current
				heap.push(next, new_cost + HexMath.distance(next, goal) * min_step_cost)
	return null


## The server's binary min-heap, swap for swap.
class _Heap:
	var _values: Array = []
	var _priorities: Array[float] = []

	func size() -> int:
		return _values.size()

	func push(value: Variant, priority: float) -> void:
		_values.append(value)
		_priorities.append(priority)
		var i := _values.size() - 1
		while i > 0:
			var parent := (i - 1) >> 1
			if _priorities[parent] <= _priorities[i]:
				break
			_swap(parent, i)
			i = parent

	func pop() -> Variant:
		var top: Variant = _values[0]
		var last: Variant = _values.pop_back()
		var last_priority: float = _priorities.pop_back()
		if _values.size() > 0:
			_values[0] = last
			_priorities[0] = last_priority
			var i := 0
			while true:
				var left := 2 * i + 1
				var right := left + 1
				var smallest := i
				if left < _values.size() and _priorities[left] < _priorities[smallest]:
					smallest = left
				if right < _values.size() and _priorities[right] < _priorities[smallest]:
					smallest = right
				if smallest == i:
					break
				_swap(smallest, i)
				i = smallest
		return top

	func _swap(a: int, b: int) -> void:
		var v: Variant = _values[a]
		_values[a] = _values[b]
		_values[b] = v
		var p := _priorities[a]
		_priorities[a] = _priorities[b]
		_priorities[b] = p


## sim/land.ts roadFactor: the share of the terrain's move cost a road of
## `level` costs (1: no road); a damaged one saves only damage.effect of what
## it would.
static func road_factor(data: Dictionary, level: int, damaged := false) -> float:
	var levels: Array = data.field.road.levels
	if level <= 0:
		return 1.0
	var factor := float(levels[mini(level, levels.size()) - 1].factor)
	return 1.0 - (1.0 - factor) * float(data.field.road.damage.effect) if damaged else factor


## sim/land.ts roadRepairCost: what repairing a damaged road of `level`
## costs and how long it takes (game seconds): damage.repairShare of
## building that level.
static func road_repair_cost(data: Dictionary, level: int, mountain_pass: bool) -> Dictionary:
	var build := road_level_cost(data, level, mountain_pass)
	var share := float(data.field.road.damage.repairShare)
	var cost := {}
	for kind in build.cost:
		cost[kind] = float(roundi(float(build.cost[kind]) * share))
	return {"cost": cost, "buildSeconds": float(build.buildSeconds) * share}


## sim/land.ts fastestRoad: the cheapest a step can be (the path search's
## lower bound).
static func fastest_road(data: Dictionary) -> float:
	var best := 1.0
	for level in data.field.road.levels:
		best = minf(best, float(level.factor))
	return best


## sim/land.ts roadLink: what a road link to the village adds to an
## outpost's yield (0: none): over the fewest road steps from `from` to `to`
## (of those, the best built), the average of each step's level
## `outpostBonus`. `roads`: edge key -> level of each standing road; a
## damaged one (`damaged`: edge key -> true) adds only damage.effect of it.
static func road_link(data: Dictionary, roads: Dictionary, from: Vector2i, to: Vector2i, damaged := {}) -> float:
	var levels: Array = data.field.road.levels
	var effect := float(data.field.road.damage.effect)
	var goal := key(to)
	var best := {key(from): {"steps": 0, "sum": 0.0}}
	var layer: Array = [from]
	var steps := 1
	while not layer.is_empty() and not best.has(goal):
		var next: Array = []
		for cell in layer:
			var here: Dictionary = best[key(cell)]
			for n in HexMath.neighbors(cell):
				var level := int(roads.get(edge_key(cell, n), 0))
				if level <= 0:
					continue
				var k := key(n)
				var sum := float(here.sum) + float(levels[mini(level, levels.size()) - 1].outpostBonus) * (effect if damaged.has(edge_key(cell, n)) else 1.0)
				if not best.has(k):
					best[k] = {"steps": steps, "sum": sum}
					next.append(n)
				elif int(best[k].steps) == steps and sum > float(best[k].sum):
					best[k] = {"steps": steps, "sum": sum}
		layer = next
		steps += 1
	var link: Variant = best.get(goal)
	return float(link.sum) / float(link.steps) if link != null and int(link.steps) > 0 else 0.0


## sim/land.ts laneFactor: the share of the terrain's move cost a step
## along a boat's river costs.
static func lane_factor(data: Dictionary) -> float:
	return 1.0 / float(data.events.kinds.shipyard.laneSpeed)


## sim/land.ts riverSpeed: how many times as fast river travel is here.
static func river_speed(data: Dictionary, land: Dictionary) -> float:
	return float(data.events.blessings.water.speed) if land.get("blessed", false) else 1.0


## sim/land.ts waterFactor: along a boat's river, or (blessed) a river's banks.
static func water_factor(data: Dictionary, land: Dictionary, edge: String) -> float:
	var speed := river_speed(data, land)
	var lane := lane_factor(data) / speed if land.get("lanes", {}).has(edge) else 1.0
	var bank := 1.0 / speed if land.get("banks", {}).has(edge) else 1.0
	return minf(lane, bank)


## sim/land.ts fastestStep: the cheapest step players can take on this land.
static func fastest_step(data: Dictionary, land: Dictionary) -> float:
	var speed := river_speed(data, land)
	var best := fastest_road(data)
	if not land.get("lanes", {}).is_empty():
		best = minf(best, lane_factor(data) / speed)
	if not land.get("banks", {}).is_empty():
		best = minf(best, 1.0 / speed)
	return best


## sim/land.ts riverBanks: every step between two neighbouring hexes on the
## banks of the same river (edge key -> true).
static func river_banks(rivers: Array) -> Dictionary:
	var banks := {}
	var done := {}
	for e in rivers:
		if done.has(edge_key(e.a, e.b)):
			continue
		for lane in river_lanes(rivers, e.a, e.b):
			banks[lane] = true
		var water := river_water(rivers, e.a, e.b)
		for r in rivers:
			if water.has(key(r.a)) and water.has(key(r.b)):
				done[edge_key(r.a, r.b)] = true
	return banks


## sim/land.ts riverLanes: the steps (edge keys, sorted) a boat built on the
## river edge a-b sails: between neighbouring hexes on the banks of every
## river edge joined to it through a shared bank hex and, with `terrain`
## ({"q,r": id}), across every lake it reaches (its hexes and shores, and
## the rivers flowing into it). `rivers`: [{a, b}].
static func river_lanes(rivers: Array, a: Vector2i, b: Vector2i, terrain := {}) -> Array:
	var water := river_water(rivers, a, b, terrain)
	var lanes := {}
	for k in water:
		for n in HexMath.neighbors(water[k]):
			if water.has(key(n)):
				lanes[edge_key(water[k], n)] = true
	var out: Array = lanes.keys()
	out.sort()
	return out


## The hexes on the water of a-b's river (riverWater): its banks, and the
## lakes it reaches with their shores and rivers. {"q,r": Vector2i}.
static func river_water(rivers: Array, a: Vector2i, b: Vector2i, terrain := {}) -> Dictionary:
	var by_hex := {}
	for i in rivers.size():
		for end in [rivers[i].a, rivers[i].b]:
			if not by_hex.has(key(end)):
				by_hex[key(end)] = []
			by_hex[key(end)].append(i)
	var start := -1
	for i in rivers.size():
		if edge_key(rivers[i].a, rivers[i].b) == edge_key(a, b):
			start = i
			break
	if start < 0:
		return {}
	var state := {"seen": {start: true}, "queue": [start], "water": {}}
	while not state.queue.is_empty():
		var e: Dictionary = rivers[state.queue.pop_front()]
		for end in [e.a, e.b]:
			_reach(end, by_hex, terrain, state)
	return state.water


## A hex on the water (riverLanes): the rivers along it join, and a lake
## beside it is sailed whole, its shores with it.
static func _reach(cell: Vector2i, by_hex: Dictionary, terrain: Dictionary, state: Dictionary) -> void:
	var k := key(cell)
	if state.water.has(k):
		return
	state.water[k] = cell
	for next in by_hex.get(k, []):
		if not state.seen.has(next):
			state.seen[next] = true
			state.queue.append(next)
	var lake: bool = terrain.get(k) == "lake"
	for n in HexMath.neighbors(cell):
		if (terrain.has(key(n)) if lake else terrain.get(key(n)) == "lake"):
			_reach(n, by_hex, terrain, state)


## sim/land.ts moveCostOn: the cost of entering `to`, or -1 where it is
## impassable or a river lies between. `land`: {terrain, blocked, roads
## (edge key -> level), lanes (edge key -> true)}.
## `relief`: the share of harsh terrain's slowness (move cost above 1) that
## pathfinders marching along take off (units.json pathfinding).
static func move_cost_on(data: Dictionary, land: Dictionary, roads := true, relief := 0.0) -> Callable:
	return func(from: Vector2i, to: Vector2i) -> float:
		var type: Variant = land.terrain.get(key(to))
		if type == null or land.blocked.has(edge_key(from, to)) or land.get("burning", {}).has(key(to)):
			return -1.0
		# A lake is crossed only by boat.
		var sailed: bool = roads and type == "lake" and land.get("lanes", {}).has(edge_key(from, to))
		var level := int(land.roads.get(edge_key(from, to), 0))
		# A mountain pass: impassable land entered only along a standing road.
		var pass_cost: Variant = data.terrain.terrain[type].get("roadMoveCost") if roads and level > 0 else null
		var base: Variant = data.events.kinds.shipyard.lakeMoveCost if sailed else data.terrain.terrain[type].moveCost
		if base == null:
			base = pass_cost
		if base == null:
			return -1.0
		var cost: float = 1.0 + (float(base) - 1.0) * (1.0 - relief) if not sailed and relief > 0.0 and float(base) > 1.0 else float(base)
		if not roads:
			return float(cost)
		var road := road_factor(data, level, land.get("damaged", {}).has(edge_key(from, to)))
		return float(cost) * minf(road, water_factor(data, land, edge_key(from, to)))


## sim/land.ts edgesMeet: whether edges a|b and c|d meet at a corner.
static func edges_meet(a: Vector2i, b: Vector2i, c: Vector2i, d: Vector2i) -> bool:
	var shared: Array = [a, b].filter(func(h: Vector2i) -> bool: return h == c or h == d)
	if shared.size() != 1:
		return false
	var p: Vector2i = b if a == shared[0] else a
	var q: Vector2i = d if c == shared[0] else c
	return HexMath.neighbors(p).has(q)


## sim/land.ts reachable: the settlements of `cells` a march from the Holy
## City can reach over `land` (by key).
static func reachable(data: Dictionary, land: Dictionary, cells: Array) -> Dictionary:
	var step := move_cost_on(data, land)
	var wanted := {}
	for c in cells:
		wanted[key(c)] = true
	var seen := {key(Vector2i.ZERO): true}
	var queue: Array = [Vector2i.ZERO]
	var out := {}
	while not queue.is_empty():
		var at: Vector2i = queue.pop_front()
		if wanted.has(key(at)):
			out[key(at)] = true
		for n in HexMath.neighbors(at):
			if seen.has(key(n)) or float(step.call(at, n)) < 0.0:
				continue
			seen[key(n)] = true
			queue.append(n)
	return out


## sim/land.ts roadLevelCost: what building a road to `level` costs and how
## long it takes (game seconds), a mountain pass mountainFactor times both.
static func road_level_cost(data: Dictionary, level: int, mountain_pass: bool) -> Dictionary:
	var rules: Dictionary = data.field.road
	var def: Dictionary = rules.levels[level - 1]
	var k := float(rules.mountainFactor) if mountain_pass else 1.0
	var cost := {}
	for kind in def.cost:
		cost[kind] = float(def.cost[kind]) * k
	return {"cost": cost, "buildSeconds": float(def.buildSeconds) * k}
