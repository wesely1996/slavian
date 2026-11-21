class_name LocalGround
## sim/ground.ts: the ground a battle is fought on (battle.json terrain):
## what its hex counts as (terrain.json ground), the mountains beside it and
## the waters (rivers along it, lakes beside it). Each feature adds its share
## to the attack or defense of the units fighting there: their family's,
## their own (units.json terrain) and their clan's.


## The ground at `cell` of `world` (its hexes and rivers).
static func at(data: Dictionary, world: Dictionary, cell: Vector2i) -> Dictionary:
	var hexes: Dictionary = world.hexes
	var rivers := {}
	for e in world.rivers:
		rivers[LocalLand.edge_key(e.a, e.b)] = true
	var out := {}
	var own: Variant = hexes.get(LocalLand.key(cell))
	if own != null:
		for tag in data.terrain.terrain.get(own, {}).get("ground", []):
			out[tag] = 1
	var mountains := 0
	var waters := 0
	for n in HexMath.neighbors(cell):
		var t: Variant = hexes.get(LocalLand.key(n))
		if t == "mountain":
			mountains += 1
		if t == "lake":
			waters += 1
		if rivers.has(LocalLand.edge_key(cell, n)):
			waters += 1
	if mountains > 0:
		out.mountain = mountains
	if waters > 0:
		out.water = waters
	return out


## A player's terrain shares from their bonuses (terrain.<feature>.<stat>,
## their clan's) on top of the unit's own.
static func player_shares(own: Variant, bonuses: Dictionary) -> Variant:
	var out: Variant = null
	for key in bonuses:
		var parts := String(key).split(".")
		if parts.size() != 3 or parts[0] != "terrain" or not (parts[2] in ["attack", "defense"]):
			continue
		if out == null:
			out = own.duplicate(true) if own is Dictionary else {}
		var now: Dictionary = out.get(parts[1], {}).duplicate()
		now[parts[2]] = float(now.get(parts[2], 0.0)) + float(bonuses[key])
		out[parts[1]] = now
	return out if out != null else own


## What `ground` makes of a unit of `family` with its own `shares`: its
## attack and defense factors.
static func factors(data: Dictionary, ground: Variant, family: String, shares: Variant) -> Dictionary:
	if not (ground is Dictionary):
		return {"attack": 1.0, "defense": 1.0}
	var rules: Dictionary = data.battle.terrain
	var family_shares: Dictionary = rules.families.get(family, {})
	var own: Dictionary = shares if shares is Dictionary else {}
	var attack := 0.0
	var defense := 0.0
	for feature in ground:
		var count := int(ground[feature])
		if count == 0:
			continue
		var times := float(mini(count, int(rules.maxStack)))
		for s in [family_shares.get(feature), own.get(feature)]:
			if s is Dictionary:
				attack += float(s.get("attack", 0.0)) * times
				defense += float(s.get("defense", 0.0)) * times
	return {"attack": maxf(0.0, 1.0 + attack), "defense": maxf(0.0, 1.0 + defense)}


## scheduler/ground.ts roadAt: whether a standing road runs into `cell`.
static func road_at(world: Dictionary, cell: Vector2i) -> bool:
	for e in world.roads:
		if e.status != "building" and int(e.get("level", 1)) > 0 and (Vector2i(e.a) == cell or Vector2i(e.b) == cell):
			return true
	return false
