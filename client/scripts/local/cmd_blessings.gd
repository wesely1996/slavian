class_name LocalBlessings
extends RefCounted
## The gods' blessings (scheduler/blessings.ts, events.json blessings): once
## per world, for everyone. The water god's for a long river line the
## players dug, the forge god's for a unit forged to the last level of
## every line. Each makes the North hate the more, for good.

const NOTICES := {
	"water": {"title": "The water god's blessing",
		"body": "The rivers you dug run long and the waters are pleased: along every river, armies, caravans and scouts travel twice as fast. The North hates you the more for it."},
	"forge": {"title": "The forge god's blessing",
		"body": "A unit forged to the last of every craft: the forge god is pleased. Forging costs half and takes half as long for everyone. The North hates you the more for it."},
}


static func has(world: Dictionary, god: String) -> bool:
	return world.get("blessings", {}).get(god) != null


## db/worlds.ts blessingCount.
static func count(world: Dictionary) -> int:
	return (1 if has(world, "water") else 0) + (1 if has(world, "forge") else 0)


## The world view's blessings (api/views.ts).
static func view(world: Dictionary) -> Dictionary:
	var b: Dictionary = world.get("blessings", {})
	return {"water": LocalTime.iso(int(b.water)) if b.get("water") != null else null,
		"forge": LocalTime.iso(int(b.forge)) if b.get("forge") != null else null, "riverLine": int(b.get("riverLine", 0))}


## lastingHatred: what every horde of `front` takes for good.
static func lasting_hatred(data: Dictionary, world: Dictionary, front: String) -> float:
	return count(world) * float(data.events.blessings.northHatred) if front == "north" else 0.0


## bless: the world is blessed by `god`, if it isn't yet; everyone is told.
static func bless(server: LocalServer, world: Dictionary, god: String, at: int, changed: Array) -> void:
	if has(world, god):
		return
	world.merge({"blessings": {}})
	world.blessings[god] = at
	for member in world.members:
		LocalInbox.tell(server, world, member.accountId, {"kind": "event", "tier": "push", "title": NOTICES[god].title, "body": NOTICES[god].body, "vars": {}}, at)
	changed.append(["world"])


## riverDug: the longest line the players have dug, and the water god's
## blessing once it is long enough.
static func river_dug(server: LocalServer, world: Dictionary, at: int, changed: Array) -> void:
	var dug: Array = world.rivers.filter(func(e: Dictionary) -> bool: return e.get("dug", false))
	var line := longest_river(dug, world.hexes)
	world.merge({"blessings": {}})
	world.blessings.riverLine = maxi(line, int(world.blessings.get("riverLine", 0)))
	if line >= int(server.data.events.blessings.water.riverLine):
		bless(server, world, "water", at, changed)


## A corner of the grid: the three hexes that meet there.
static func _corner(a: Vector2i, b: Vector2i, c: Vector2i) -> String:
	var keys := [LocalLand.key(a), LocalLand.key(b), LocalLand.key(c)]
	keys.sort()
	return "/".join(keys)


## The two corners at the ends of the edge a|b.
static func _edge_corners(a: Vector2i, b: Vector2i) -> Array:
	var of_b := {}
	for n in HexMath.neighbors(b):
		of_b[LocalLand.key(n)] = true
	var common: Array = HexMath.neighbors(a).filter(func(n: Vector2i) -> bool: return of_b.has(LocalLand.key(n)))
	common.sort_custom(func(x: Vector2i, y: Vector2i) -> bool: return LocalLand.key(x) < LocalLand.key(y))
	return [_corner(a, b, common[0]), _corner(a, b, common[1])]


## sim/blessings.ts longestRiver: the longest river line, river edges joined
## corner to corner, each once, through lakes at their shortest; a line may
## end in a lake, at its farthest corner from where the river meets it. `rivers`:
## [{a, b}]; `terrain`: {"q,r": id}.
static func longest_river(rivers: Array, terrain: Dictionary) -> int:
	var links: Array = []
	var river_corners := {}
	for e in rivers:
		var ends := _edge_corners(e.a, e.b)
		links.append({"u": ends[0], "v": ends[1], "w": 1})
		river_corners[ends[0]] = true
		river_corners[ends[1]] = true
	var seen := {}
	var lake_keys: Array = terrain.keys().filter(func(k: String) -> bool: return terrain[k] == "lake")
	lake_keys.sort()
	for start in lake_keys:
		if seen.has(start):
			continue
		var body: Array = []
		var queue: Array = [start]
		seen[start] = true
		while not queue.is_empty():
			var parts: PackedStringArray = String(queue.pop_front()).split(",")
			var cell := Vector2i(int(parts[0]), int(parts[1]))
			body.append(cell)
			for n in HexMath.neighbors(cell):
				var k := LocalLand.key(n)
				if not seen.has(k) and terrain.get(k) == "lake":
					seen[k] = true
					queue.append(k)
		var graph := {}
		for cell in body:
			for n in HexMath.neighbors(cell):
				var ends := _edge_corners(cell, n)
				for c in ends:
					if not graph.has(c):
						graph[c] = {}
				graph[ends[0]][ends[1]] = true
				graph[ends[1]][ends[0]] = true
		var mouths: Array = graph.keys().filter(func(c: String) -> bool: return river_corners.has(c))
		mouths.sort()
		for i in mouths.size():
			var dist := {mouths[i]: 0}
			var bfs: Array = [mouths[i]]
			while not bfs.is_empty():
				var c: String = bfs.pop_front()
				var next: Array = graph[c].keys()
				next.sort()
				for n in next:
					if not dist.has(n):
						dist[n] = int(dist[c]) + 1
						bfs.append(n)
			for j in range(i + 1, mouths.size()):
				var d: Variant = dist.get(mouths[j])
				if d != null and int(d) > 0:
					links.append({"u": mouths[i], "v": mouths[j], "w": int(d)})
			# Or the line ends in the lake, at its farthest corner from this mouth.
			var far := 0
			for c in dist:
				far = maxi(far, int(dist[c]))
			if far > 0:
				links.append({"u": mouths[i], "v": "lake:%s:%s" % [start, mouths[i]], "w": far})
	var by_corner := {}
	for i in links.size():
		for c in [links[i].u, links[i].v]:
			if not by_corner.has(c):
				by_corner[c] = []
			by_corner[c].append(i)
	var state := {"best": 0, "used": {}}
	var corners: Array = by_corner.keys()
	corners.sort()
	for corner in corners:
		_walk(links, by_corner, corner, 0, state)
	return int(state.best)


## Longest trail from `at`, each link once.
static func _walk(links: Array, by_corner: Dictionary, at: String, length: int, state: Dictionary) -> void:
	if length > int(state.best):
		state.best = length
	for i in by_corner.get(at, []):
		if state.used.has(i):
			continue
		var l: Dictionary = links[i]
		state.used[i] = true
		_walk(links, by_corner, l.v if l.u == at else l.u, length + int(l.w), state)
		state.used.erase(i)
