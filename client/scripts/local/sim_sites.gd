class_name LocalSites
extends RefCounted
## Ancient sites for the local engine: placement from server/src/sim/sites.ts.
## A placed site: {kind, q, r, guardians}.

const MASK := 0xffffffff


static func distance_share(cell: Vector2i, radius: int) -> float:
	return minf(1.0, HexMath.distance(cell, Vector2i.ZERO) / float(radius)) if radius > 0 else 0.0


static func guardians_for(data: Dictionary, cell: Vector2i, radius: int, seed_value: int) -> Dictionary:
	var g: Dictionary = data.sites.guardians
	var size := LocalWaves.js_round(float(g.baseUnits) * (1.0 + float(g.distanceGrowth) * distance_share(cell, radius)))
	return LocalWaves.compose_wave(data, "north", int(g.waveIndex), size, seed_value)


static func _shuffled(items: Array, rng: LocalRng) -> Array:
	var out := items.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := floori(rng.next() * (i + 1))
		var swap: Variant = out[i]
		out[i] = out[j]
		out[j] = swap
	return out


## Sites for a new world: mostly in the borderlands, a few mid-map, apart from
## each other and from where players start. `terrain` is {"q,r": id}.
static func place_sites(data: Dictionary, terrain: Dictionary, radius: int, start_sites: Array, seed_value: int, players: int) -> Array:
	var p: Dictionary = data.sites.placement
	var rng := LocalRng.new((seed_value ^ 0x51e5) & MASK)
	var count := maxi(int(p.min), int(p.perPlayer) * players)
	var mid_count := LocalWaves.js_round(count * float(p.midShare))
	var kinds: Dictionary = data.sites.kinds
	var usable: Array = []
	for key in terrain:
		var type: String = terrain[key]
		var parts: PackedStringArray = key.split(",")
		var cell := Vector2i(int(parts[0]), int(parts[1]))
		if type == "holy_city" or data.terrain.terrain[type].moveCost == null:
			continue
		var fits := false
		for k in kinds.values():
			if type in k.terrain:
				fits = true
		if not fits:
			continue
		var apart := true
		for s in start_sites:
			if HexMath.distance(s, cell) < int(p.keepAway):
				apart = false
		if apart:
			usable.append({"cell": cell, "type": type})
	usable.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.cell.x < b.cell.x or (a.cell.x == b.cell.x and a.cell.y < b.cell.y))
	var border := usable.filter(func(u: Dictionary) -> bool: return HexMath.distance(u.cell, Vector2i.ZERO) >= radius - int(p.borderBand))
	var mid := usable.filter(func(u: Dictionary) -> bool:
		var share := distance_share(u.cell, radius)
		return share >= float(p.midRange[0]) and share <= float(p.midRange[1]))
	var placed: Array = []
	for pass_ in [[mid, mid_count], [border, count - mid_count]]:
		var taken := 0
		for u in _shuffled(pass_[0], rng):
			if taken >= int(pass_[1]):
				break
			var near := false
			for s in placed:
				if HexMath.distance(Vector2i(s.q, s.r), u.cell) < int(p.spacing):
					near = true
			if near:
				continue
			var fitting: Array = []
			for id in kinds:
				if u.type in kinds[id].terrain:
					fitting.append(id)
			var kind: String = fitting[floori(rng.next() * fitting.size())]
			var watched := rng.next() < float(kinds[kind].guardianChance)
			var guardians := guardians_for(data, u.cell, radius, (seed_value ^ (placed.size() * 0x9e37)) & MASK) if watched else {}
			placed.append({"kind": kind, "q": u.cell.x, "r": u.cell.y, "guardians": guardians})
			taken += 1
	return placed
