class_name LocalWalls
extends RefCounted
## Walls and siege for the local engine: server/src/sim/walls.ts.


static func wall_level(plots: Dictionary) -> int:
	return int(plots.get(LocalVillage.WALL_PLOT, {}).get("level", 0))


## The best level of a kind of tower in the wall slots (0: none).
static func tower_level(plots: Dictionary, tower: String) -> int:
	var best := 0
	for id in plots:
		if LocalVillage.tower_index(id) >= 0 and plots[id].building == tower:
			best = maxi(best, int(plots[id].level))
	return best


static func wall_tier_def(data: Dictionary, level: int) -> Variant:
	if level <= 0:
		return null
	var tiers: Array = data.walls.tiers
	for i in range(tiers.size() - 1, -1, -1):
		if level >= int(tiers[i].minLevel):
			return tiers[i]
	return tiers[0]


static func wall_integrity(data: Dictionary, plots: Dictionary) -> int:
	var level := wall_level(plots)
	var gate := tower_level(plots, "gate_tower") * float(data.walls.towers.gate_tower.integrityPerLevel)
	var tier: Variant = wall_tier_def(data, level)
	var toughness := float(tier.toughness) if tier != null else 1.0
	return LocalWaves.js_round(float(data.walls.integrityPerLevel) * level * toughness * (1.0 + gate))


static func wall_capacity(data: Dictionary, plots: Dictionary) -> int:
	return LocalWaves.js_round(wall_level(plots) * float(data.walls.manning.menPerLevel))


## While the walls stand: {defense, attack, archers} multipliers; `over` is
## the share of the horde's fighters over the walls.
static func wall_factors(data: Dictionary, plots: Dictionary, archers := 0.0, over := 0.0) -> Dictionary:
	var t: Dictionary = data.walls.towers
	var level := wall_level(plots)
	var shelter := level * float(data.walls.defensePerLevel) + tower_level(plots, "murder_holes") * float(t.murder_holes.defensePerLevel)
	var manned := minf(1.0, wall_capacity(data, plots) / archers) if archers > 0 else 0.0
	return {
		"defense": 1.0 + shelter * (1.0 - over),
		"attack": 1.0 + tower_level(plots, "archer_tower") * float(t.archer_tower.attackPerLevel),
		"archers": 1.0 + level * float(data.walls.manning.archerAttackPerLevel) * manned,
	}


static func siege_cut(data: Dictionary, plots: Dictionary) -> float:
	return minf(0.9, tower_level(plots, "ditch") * float(data.walls.towers.ditch.siegeCutPerLevel))


static func escalade_cut(data: Dictionary, plots: Dictionary) -> float:
	return minf(0.9, tower_level(plots, "ditch") * float(data.walls.towers.ditch.escaladeCutPerLevel))


static func _unit(data: Dictionary, front: String, unit: String) -> Variant:
	return data.enemies.fronts.get(front, {}).get("units", {}).get(unit)


static func unit_siege(data: Dictionary, front: String, unit: String) -> float:
	var def: Variant = _unit(data, front, unit)
	if def == null:
		return 0.0
	return float(def.siege) if def.get("siege") != null else float(def.attack) * float(data.walls.siege.unitSiegeShare)


static func unit_escalade(data: Dictionary, front: String, unit: String) -> float:
	var def: Variant = _unit(data, front, unit)
	return float(def.escalade) if def != null and def.get("escalade") != null else 0.0


static func is_engine(data: Dictionary, front: String, unit: String) -> bool:
	var def: Variant = _unit(data, front, unit)
	var siege := float(def.siege) if def != null and def.get("siege") != null else 0.0
	return siege >= 6 or unit_escalade(data, front, unit) > 0


static func _fighters(data: Dictionary, front: String, units: Dictionary) -> int:
	var n := 0
	for unit in units:
		if not is_engine(data, front, unit):
			n += int(units[unit])
	return n


static func escalade_power(data: Dictionary, front: String, units: Dictionary, plots: Dictionary) -> float:
	var raw := 0.0
	for unit in units:
		raw += int(units[unit]) * unit_escalade(data, front, unit)
	return raw * (1.0 - escalade_cut(data, plots))


static func over_the_walls(data: Dictionary, front: String, units: Dictionary, plots: Dictionary) -> float:
	var men := _fighters(data, front, units)
	return minf(1.0, escalade_power(data, front, units, plots) / men) if men > 0 else 0.0


static func held_back(data: Dictionary, over: float) -> float:
	var held := float(data.walls.escalade.meleeHeld)
	return held + (1.0 - held) * over


static func siege_power(data: Dictionary, front: String, units: Dictionary) -> float:
	var sum := 0.0
	for unit in units:
		sum += int(units[unit]) * unit_siege(data, front, unit)
	return sum


## What a horde builds before assaulting walls of `integrity`: {engine,
## count, setupMs}, or null.
static func siege_works(data: Dictionary, front: String, units: Dictionary, integrity: int, plots: Dictionary, world_speed: float) -> Variant:
	var def: Variant = data.enemies.fronts.get(front)
	if def == null or def.get("engine") == null or float(def.personality.siegeCraft) <= 0 or integrity <= 0:
		return null
	var engine: Dictionary = def.units[def.engine]
	var count: int
	if unit_escalade(data, front, def.engine) > 0:
		var cut := 1.0 - escalade_cut(data, plots)
		var needed := _fighters(data, front, units) * float(data.walls.escalade.climbShare)
		var have := escalade_power(data, front, units, plots)
		if have >= needed:
			return null
		count = ceili((needed - have) / (unit_escalade(data, front, def.engine) * cut))
	else:
		var cut := 1.0 - siege_cut(data, plots)
		var needed := integrity / float(data.walls.siege.breachRounds)
		var have := siege_power(data, front, units) * cut
		if have >= needed:
			return null
		count = ceili((needed - have) / (unit_siege(data, front, def.engine) * cut))
	var moat := 1.0 + tower_level(plots, "ditch") * float(data.walls.towers.ditch.setupPerLevel)
	var hours := float(data.walls.siege.setupHours) * float(def.personality.siegeCraft) * float(engine.setupFactor) * moat
	return {"engine": def.engine, "count": count, "setupMs": LocalWaves.js_round((hours * LocalTime.MS_PER_HOUR) / world_speed)}


static func siege_damage(data: Dictionary, front: String, units: Dictionary, plots: Dictionary) -> float:
	return siege_power(data, front, units) * (1.0 - siege_cut(data, plots))


## Engines the ballistae smash this round, the biggest first.
static func ballista_kills(data: Dictionary, front: String, units: Dictionary, plots: Dictionary, rng: LocalRng) -> Dictionary:
	var expected := tower_level(plots, "ballista") * float(data.walls.towers.ballista.enginesPerLevel)
	var left := floori(expected) + (1 if rng.next() < expected - floorf(expected) else 0)
	var engines: Array = []
	for unit in units:
		if int(units[unit]) > 0 and is_engine(data, front, unit):
			engines.append(unit)
	# Stable, biggest worth first (V8's sort is stable).
	var sorted: Array = []
	for unit in engines:
		var worth := unit_siege(data, front, unit) + unit_escalade(data, front, unit)
		var at := sorted.size()
		for i in sorted.size():
			if worth > unit_siege(data, front, sorted[i]) + unit_escalade(data, front, sorted[i]):
				at = i
				break
		sorted.insert(at, unit)
	var kills := {}
	for unit in sorted:
		if left <= 0:
			break
		var k := mini(int(units[unit]), left)
		kills[unit] = k
		left -= k
	return kills


static func warning_hours(data: Dictionary, plots: Dictionary) -> float:
	return tower_level(plots, "watchtower") * float(data.walls.towers.watchtower.warningHoursPerLevel)
