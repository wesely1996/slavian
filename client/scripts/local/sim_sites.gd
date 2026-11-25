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


## What exploring a site turns up, seeded by the site: {type: "resources",
## resources} | {type: "gear", item} | {type: "scroll", scroll}, with
## "ember": true when a Svarog's Ember came besides (the kind's emberChance,
## split among the `players`). Old saves may hold {type: "ember"}.
static func roll_find(data: Dictionary, kind: String, seed_value: int, site_id: int, distance: float, found_scrolls: Array, owned_gear: Array, loot_factor := 1.0, players := 1) -> Dictionary:
	var rng := LocalRng.new((seed_value ^ LocalRng.imul(site_id + 1, 0x2c1b3c6d) ^ 0xf1d) & 0xffffffff)
	var weights: Dictionary = data.sites.kinds[kind].finds
	var scrolls: Array = data.lore.scrolls.keys().filter(func(s: String) -> bool: return not s in found_scrolls)
	scrolls.sort()
	var gear: Array = data.heroes.items.keys().filter(func(i: String) -> bool: return not i in owned_gear)
	gear.sort()
	var options: Array = ["resources", "gear", "scroll"].filter(func(type: String) -> bool:
		return float(weights[type]) > 0 and (type != "scroll" or not scrolls.is_empty()) and (type != "gear" or not gear.is_empty()))
	var total := 0.0
	for type in options:
		total += float(weights[type])
	var roll := rng.next() * total
	var picked := "resources"
	for type in options:
		roll -= float(weights[type])
		if roll < 0:
			picked = type
			break
	var find: Dictionary
	match picked:
		"gear":
			find = {"type": "gear", "item": gear[floori(rng.next() * gear.size())]}
		"scroll":
			find = {"type": "scroll", "scroll": scrolls[floori(rng.next() * scrolls.size())]}
		_:
			find = {"type": "resources", "resources": LocalVillage.resources(func(k: String) -> int:
				return LocalWaves.js_round(float(data.sites.loot[k]) * (1.0 + distance) * loot_factor))}
	if rng.next() < float(data.sites.kinds[kind].emberChance) / maxi(1, players):
		find.ember = true
	return find


## Whether a find brought a Svarog's Ember (sim/sites.ts withEmber).
static func with_ember(find: Dictionary) -> bool:
	return find.get("type") == "ember" or find.get("ember", false) == true


## How far from `center` scouts may search: to the map's farthest edge
## (sim/sites.ts ruinSearchReach).
static func ruin_search_reach(center: Vector2i, radius: int) -> int:
	return radius + HexMath.distance(center, Vector2i.ZERO)


## Real-time ms scouts searching from `center` are away (sim/sites.ts
## ruinSearchMs): `found` is the ruin's cell, or null finding nothing.
static func ruin_search_ms(data: Dictionary, center: Vector2i, radius: int, found: Variant, world_speed: float) -> int:
	var rules: Dictionary = data.scouting.ruinSearch
	var distance := HexMath.distance(center, found) if found is Vector2i else ruin_search_reach(center, radius)
	return LocalWaves.js_round((float(rules.searchHours) + 2.0 * float(rules.hoursPerHex) * distance) * 3600000.0 / world_speed)


## What scouts searching around `center` turn up, seeded by the search
## (sim/sites.ts searchRuin): a placed site on the nearest free ground, or
## {} when the roll fails or there is none. `taken` is {"q,r": true};
## `sites` the unexplored sites' cells.
static func search_ruin(data: Dictionary, terrain: Dictionary, radius: int, center: Vector2i, taken: Dictionary, sites: Array, scouts: int, seed_value: int) -> Dictionary:
	var rules: Dictionary = data.scouting.ruinSearch
	var rng := LocalRng.new((seed_value ^ 0x7417) & MASK)
	if rng.next() >= minf(float(rules.maxChance), float(rules.chancePerScout) * scouts):
		return {}
	var kinds: Dictionary = data.sites.kinds
	var usable: Array = []
	# The nearest free ground, ring by ring out to the map's edge.
	for d in range(1, ruin_search_reach(center, radius) + 1):
		if not usable.is_empty():
			break
		for cell in HexMath.ring(center, d):
			var key := "%d,%d" % [cell.x, cell.y]
			var type: String = terrain.get(key, "")
			if type == "" or type == "holy_city" or data.terrain.terrain[type].moveCost == null or taken.has(key):
				continue
			var fits := false
			for k in kinds.values():
				if type in k.terrain:
					fits = true
			if not fits or sites.any(func(s: Vector2i) -> bool: return HexMath.distance(s, cell) < int(rules.spacing)):
				continue
			usable.append({"cell": cell, "type": type})
	if usable.is_empty():
		return {}
	var picked: Dictionary = usable[floori(rng.next() * usable.size())]
	var fitting: Array = []
	for id in kinds:
		if picked.type in kinds[id].terrain:
			fitting.append(id)
	var kind: String = fitting[floori(rng.next() * fitting.size())]
	var watched := rng.next() < float(kinds[kind].guardianChance)
	return {"kind": kind, "q": picked.cell.x, "r": picked.cell.y,
		"guardians": guardians_for(data, picked.cell, radius, (seed_value ^ 0x9e37) & MASK) if watched else {}}
