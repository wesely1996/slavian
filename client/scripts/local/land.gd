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
