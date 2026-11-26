class_name LocalEnemyLands
extends RefCounted
## server/src/sim/enemyLands.ts: the enemy lands beyond the map's edge
## (data/enemy-lands.json), four bands deep on the sides of the active
## fronts, each front with its own terrain. Made from the world's seed, radius
## and fronts, never stored, so older saves get them too. Hordes keep to the
## heartland; armies may walk in.

static var _cache := {}


## Rings the enemy lands reach past the edge.
static func rings(data: Dictionary) -> int:
	var sum := 0
	for b in data.enemyLands.bands:
		sum += int(b.rings)
	return sum


## 0 inside the map's radius, 1.. beyond it, -1 past the last band.
static func band_of(data: Dictionary, cell: Vector2i, radius: int) -> int:
	var past := HexMath.distance(cell, Vector2i.ZERO) - radius
	if past <= 0:
		return 0
	var bands: Array = data.enemyLands.bands
	for i in bands.size():
		past -= int(bands[i].rings)
		if past <= 0:
			return i + 1
	return -1


## [{cell, terrain, front, band}], ring by ring outward.
static func lands(data: Dictionary, seed_value: int, radius: int, fronts: Array) -> Array:
	var cache_key := "%d:%d:%s" % [seed_value, radius, ",".join(PackedStringArray(fronts))]
	if _cache.has(cache_key):
		return _cache[cache_key]
	var rng := LocalRng.new((seed_value ^ 0x3e7a11d5) & 0xffffffff)
	var noise := LocalNoise.new(rng.callable())
	var out: Array = []
	var depth := rings(data)
	for d in range(radius + 1, radius + depth + 1):
		for cell in HexMath.ring(Vector2i.ZERO, d):
			var front := LocalMapgen.front_of(cell)
			if not front in fronts:
				continue
			var band := band_of(data, cell, radius)
			var seam := false
			for n in HexMath.neighbors(cell):
				if HexMath.distance(n, Vector2i.ZERO) > radius:
					var other := LocalMapgen.front_of(n)
					if other != front and other in fronts:
						seam = true
						break
			var terrain := String(data.enemyLands.seam)
			if not seam:
				var front_lands: Dictionary = data.enemyLands.fronts[front]
				var v := LocalMapgen._fbm(noise, 0.08, LocalLand.pixel_x(cell), LocalLand.pixel_y(cell)) + float(front_lands.shift) * (band - 1)
				var palette: Array = front_lands.palette
				terrain = String(palette[palette.size() - 1].terrain)
				for entry in palette:
					if v < float(entry.upTo):
						terrain = String(entry.terrain)
						break
			out.append({"cell": cell, "terrain": terrain, "front": front, "band": band})
	if _cache.size() > 16:
		_cache.clear()
	_cache[cache_key] = out
	return out


static func of_world(data: Dictionary, world: Dictionary) -> Array:
	if world.get("radius") == null:
		return []
	return lands(data, int(world.seed), int(world.radius), world.activeFronts)


## How many bands of a front the players see (deeper ones lie in fog).
static func sight_of(data: Dictionary, world: Dictionary, front: String) -> int:
	var seen := int(world.get("enemySight", {}).get(front, 0))
	return mini(data.enemyLands.bands.size(), maxi(int(data.enemyLands.sight), seen))


## The enemy-lands hex at `cell` ({} if none).
static func hex_at(data: Dictionary, world: Dictionary, cell: Vector2i) -> Dictionary:
	for e in of_world(data, world):
		if e.cell == cell:
			return e
	return {}


## The world's terrain with the enemy lands added: what armies walk on.
static func army_terrain(data: Dictionary, world: Dictionary) -> Dictionary:
	var terrain: Dictionary = world.hexes.duplicate()
	for e in of_world(data, world):
		terrain[LocalLand.key(e.cell)] = e.terrain
	return terrain


## LocalHordes.land_of with the enemy lands added (scheduler/armies.ts armyLand).
static func army_land(data: Dictionary, world: Dictionary) -> Dictionary:
	var land := LocalHordes.land_of(world)
	land.terrain = army_terrain(data, world)
	return land


## An army reached `cell`: in the enemy lands, it sees the band past it.
## True when the sight widened.
static func widen_sight(data: Dictionary, world: Dictionary, cell: Vector2i) -> bool:
	var e := hex_at(data, world, cell)
	if e.is_empty():
		return false
	var bands := mini(data.enemyLands.bands.size(), int(e.band) + 1)
	var sight: Dictionary = world.get("enemySight", {})
	if int(sight.get(e.front, 0)) >= bands:
		return false
	sight[e.front] = bands
	world.enemySight = sight
	return true


## api/views.ts enemyView: the seed the lands are made from, and each
## active front's bands seen.
static func view(data: Dictionary, world: Dictionary) -> Dictionary:
	var sight := {}
	for front in world.activeFronts:
		sight[front] = sight_of(data, world, front)
	return {"seed": int(world.seed), "sight": sight}
