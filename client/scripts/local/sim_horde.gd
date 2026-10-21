class_name LocalHorde
extends RefCounted
## The horde AI's rules for the local engine: server/src/sim/horde.ts.


static func raze_ms(data: Dictionary, world_speed: float) -> float:
	return (float(data.horde.raze.hours) * LocalTime.MS_PER_HOUR) / world_speed


## Math.log2, exact at powers of two as JavaScript's is.
static func log2(x: float) -> float:
	var e := floori(log(x) / log(2.0))
	if pow(2.0, e) > x:
		e -= 1
	elif pow(2.0, e + 1) <= x:
		e += 1
	return e + log(x / pow(2.0, e)) / log(2.0)


## Raid or raze (decideRaze): {choice, reasons}. `input`: front, waveIndex,
## graceWaves, thresholdOffset, refuge, hordeNow, hordeInitial, helpNearby,
## rampageLeftMs, worldSpeed.
static func decide_raze(data: Dictionary, input: Dictionary) -> Dictionary:
	var rules: Dictionary = data.horde.raze
	var grace: Variant = input.get("graceWaves")
	if int(input.waveIndex) < (int(grace) if grace != null else int(rules.graceWaves)):
		return {"choice": "raid", "reasons": ["an early raiding party"]}
	if input.get("refuge", false):
		return {"choice": "raid", "reasons": ["refugees have nothing left to burn"]}
	if float(input.rampageLeftMs) < raze_ms(data, float(input.worldSpeed)):
		return {"choice": "raid", "reasons": ["no time to raze"]}
	var strength := float(input.hordeNow) / maxf(1.0, float(input.helpNearby))
	if strength < float(rules.minStrength):
		return {"choice": "raid", "reasons": ["help is near"]}
	var reasons: Array = []
	var bias := float(data.enemies.fronts[input.front].personality.razeBias)
	var score := bias + log2(strength)
	if bias > 0:
		reasons.append("its faction burns what it takes")
	if bias < 0:
		reasons.append("its faction prefers plunder")
	if float(input.hordeNow) < float(input.hordeInitial) / 2.0:
		score -= float(rules.weakenedPenalty)
		reasons.append("it is weakened")
	reasons.append("nothing nearby can stop it" if strength >= 4 else "it outnumbers the help nearby")
	var offset: Variant = input.get("thresholdOffset")
	var threshold := float(rules.threshold) + (float(offset) if offset != null else 0.0)
	return {"choice": "raze" if score >= threshold else "raid", "reasons": reasons}


## After a raid the horde swells with recruits.
static func recruit(data: Dictionary, initial: Dictionary, now: Dictionary) -> Dictionary:
	var share := float(data.horde.raid.recruitShare)
	var next := now.duplicate()
	for unit in initial:
		var extra := floori(int(initial[unit]) * share)
		if extra > 0:
			next[unit] = int(next.get(unit, 0)) + extra
	return next


## Everything burned: buildings and fields stand at level 0.
static func ruin_plots(plots: Dictionary) -> Dictionary:
	var out := {}
	for id in plots:
		var plot: Dictionary = plots[id].duplicate()
		plot.level = 0
		out[id] = plot
	return out


## A share of what everything that stood cost to build.
static func rebuild_cost(data: Dictionary, plots: Dictionary) -> Dictionary:
	var sum := {"wood": 0.0, "stone": 0.0, "grain": 0.0, "iron": 0.0}
	for id in plots:
		var plot: Dictionary = plots[id]
		var def: Variant = data.buildings.buildings.get(plot.building) if plot.building != null else null
		if def == null:
			continue
		for level in range(1, int(plot.level) + 1):
			var cost := LocalVillage.level_cost(def, level)
			for kind in sum:
				sum[kind] += float(cost[kind])
	return LocalVillage.resources(func(kind: String) -> int: return LocalWaves.js_round(sum[kind] * float(data.horde.ruins.rebuildCostShare)))


static func rebuild_ms(data: Dictionary, world_speed: float) -> float:
	return (float(data.horde.ruins.rebuildHours) * LocalTime.MS_PER_HOUR) / world_speed


static func _passable(data: Dictionary, terrain: Dictionary, cell: Vector2i) -> bool:
	var type: Variant = terrain.get(LocalLand.key(cell))
	return type != null and type != "holy_city" and data.terrain.terrain[type].moveCost != null


## Where survivors settle: the nearest free passable hex around `from`.
static func camp_site(data: Dictionary, terrain: Dictionary, from: Vector2i, taken: Dictionary) -> Variant:
	for radius in range(1, 5):
		for cell in HexMath.ring(from, radius):
			if _passable(data, terrain, cell) and not taken.has(LocalLand.key(cell)):
				return cell
	return null


## A refugee camp near the Holy City, on settleable free ground.
static func refugee_site(data: Dictionary, terrain: Dictionary, taken: Dictionary) -> Variant:
	var min_distance := int(data.horde.refugeeCamp.minDistance)
	var radius := 0
	for key in terrain:
		var parts: PackedStringArray = key.split(",")
		radius = maxi(radius, HexMath.distance(Vector2i(int(parts[0]), int(parts[1])), Vector2i.ZERO))
	for d in range(min_distance, radius + 1):
		for cell in HexMath.ring(Vector2i.ZERO, d):
			var type: Variant = terrain.get(LocalLand.key(cell))
			if type != null and data.terrain.terrain[type].settleable and not taken.has(LocalLand.key(cell)):
				return cell
	return null


## The Holy City's guard grows with every wave.
static func holy_city_guard(data: Dictionary, wave_index: int) -> Dictionary:
	var growth := pow(float(data.horde.holyCity.guardGrowthPerWave), wave_index)
	var out := {}
	for unit in data.horde.holyCity.guard:
		out[unit] = LocalWaves.js_round(float(data.horde.holyCity.guard[unit]) * growth)
	return out


static func sanctity_damage(data: Dictionary, survivors: int) -> int:
	return ceili(survivors * float(data.horde.holyCity.damagePerUnit))


static func fear_left(data: Dictionary, killed: int) -> float:
	return float(data.horde.fear.perDefeat) + float(data.horde.fear.perUnitLost) * killed


static func is_holy_city(cell: Vector2i) -> bool:
	return cell == Vector2i.ZERO
