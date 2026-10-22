class_name LocalCamps
extends RefCounted
## Bandit camps and monster lairs for the local engine: server/src/sim/camps.ts
## and scheduler/camps.ts.


## A wave of the camp's front sets out: part of the camp goes with it.
static func feed(data: Dictionary, units: Dictionary) -> Dictionary:
	var sent := {}
	for unit in units:
		var s := floori(int(units[unit]) * float(data.camps.feed.share))
		if s > 0:
			sent[unit] = s
	return {"sent": sent, "kept": subtract_units(units, sent)}


static func add_units(a: Dictionary, b: Dictionary) -> Dictionary:
	var sum := a.duplicate()
	for unit in b:
		sum[unit] = int(sum.get(unit, 0)) + int(b[unit])
	return sum


## sim/battle.ts subtractUnits: what is left, without the units gone.
static func subtract_units(units: Dictionary, losses: Dictionary) -> Dictionary:
	var left := {}
	for unit in units:
		var remaining := int(units[unit]) - int(losses.get(unit, 0))
		if remaining > 0:
			left[unit] = remaining
	return left


static func total(units: Dictionary) -> int:
	var n := 0
	for count in units.values():
		n += int(count)
	return n


## Camps of a wave's front send part of themselves along (campsJoin).
static func camps_join(server: LocalServer, world: Dictionary, wave: Dictionary) -> void:
	var composition: Dictionary = wave.composition
	var joined := false
	var camps: Array = world.camps.filter(func(c: Dictionary) -> bool: return c.status == "active")
	camps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	for camp in camps:
		if camp.front != wave.front:
			continue
		var fed := feed(server.data, camp.units)
		if total(fed.sent) == 0:
			continue
		composition = add_units(composition, fed.sent)
		camp.units = fed.kept
		joined = true
	if joined:
		wave.composition = composition
		wave.initial = composition.duplicate()


static func camp_size(data: Dictionary, wave_index: int) -> int:
	var spawn: Dictionary = data.camps.spawn
	return maxi(1, LocalWaves.js_round(float(spawn.baseUnits) * pow(float(spawn.growthPerWave), wave_index)))


## Free hexes near a horde's road, away from villages, in a seeded order.
static func spawn_sites(data: Dictionary, terrain: Dictionary, path: Array, villages: Array, taken: Dictionary, rng: LocalRng, count: int) -> Array:
	var near := int(data.camps.spawn.nearRoad)
	var min_distance := int(data.camps.spawn.minVillageDistance)
	var seen := {}
	var candidates: Array = []
	for step in path:
		for cell in HexMath.spiral(Vector2i(step.q, step.r), near):
			var key := LocalLand.key(cell)
			if seen.has(key):
				continue
			seen[key] = true
			var type: Variant = terrain.get(key)
			if type == null or type == "holy_city" or data.terrain.terrain[type].moveCost == null:
				continue
			if data.terrain.terrain[type].get("edge", false) or taken.has(key):
				continue
			if villages.any(func(v: Vector2i) -> bool: return HexMath.distance(v, cell) < min_distance):
				continue
			candidates.append(cell)
	var picked: Array = []
	while picked.size() < count and not candidates.is_empty():
		var cell: Vector2i = candidates.pop_at(floori(rng.next() * candidates.size()))
		if picked.all(func(p: Vector2i) -> bool: return HexMath.distance(p, cell) > 1):
			picked.append(cell)
	return picked


## Where a village's starter camp goes: a free, passable hex within
## starter.minDistance-maxDistance of it, no nearer any other village or the
## Holy City, in a
## seeded order (Vector2i.MAX if none) (sim/camps.ts starterSite).
static func starter_site(data: Dictionary, terrain: Dictionary, village: Vector2i, villages: Array, taken: Dictionary, rng: LocalRng) -> Vector2i:
	var min_distance := int(data.camps.starter.minDistance)
	var candidates: Array = []
	for cell in HexMath.spiral(village, int(data.camps.starter.maxDistance)):
		var key := LocalLand.key(cell)
		var type: Variant = terrain.get(key)
		if type == null or type == "holy_city" or data.terrain.terrain[type].moveCost == null:
			continue
		if data.terrain.terrain[type].get("edge", false) or taken.has(key):
			continue
		# Not at the Holy City's gates either.
		if HexMath.distance(village, cell) < min_distance or HexMath.distance(cell, Vector2i.ZERO) < min_distance:
			continue
		if villages.all(func(v: Vector2i) -> bool: return HexMath.distance(v, cell) >= min_distance):
			candidates.append(cell)
	if candidates.is_empty():
		return Vector2i.MAX
	return candidates[floori(rng.next() * candidates.size())]


## A camp draws in more of its kind, up to a limit.
static func grow(data: Dictionary, units: Dictionary) -> Dictionary:
	var share := float(data.camps.growth.share)
	var max_units := int(data.camps.growth.maxUnits)
	var now := total(units)
	if now == 0 or now >= max_units:
		return units
	var extra := mini(max_units - now, maxi(1, LocalWaves.js_round(now * share)))
	var next := units.duplicate()
	# The most numerous first; ties keep their order (V8's sort is stable).
	var kinds: Array = []
	for unit in units:
		if int(units[unit]) > 0:
			var at := kinds.size()
			for i in kinds.size():
				if int(units[unit]) > int(units[kinds[i]]):
					at = i
					break
			kinds.insert(at, unit)
	for i in extra:
		var unit: String = kinds[i % kinds.size()]
		next[unit] = int(next.get(unit, 0)) + 1
	return next
