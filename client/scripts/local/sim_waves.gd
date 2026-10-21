class_name LocalWaves
extends RefCounted
## Enemy waves for the local engine: the planning half of
## server/src/sim/waves.ts, waveStance from battle.ts and waveFactor from
## difficulty.ts. A planned wave: {index, front, spawnAt (ms), composition,
## threat, stance}. A context: {seed, activeFronts, playerCount, startedAt,
## worldSpeed, sizeFactor}.

const MASK := 0xffffffff


## JavaScript's Math.round: halves go up.
static func js_round(x: float) -> int:
	return int(floor(x + 0.5))


static func rng_for(seed_value: int, index: int, salt: int) -> LocalRng:
	return LocalRng.new((seed_value ^ LocalRng.imul(index + 1, 0x9e3779b1) ^ salt) & MASK)


static func wave_fronts(data: Dictionary, active_fronts: Array) -> Array:
	var out: Array = []
	for front in data.waves.enabledFronts:
		if front in active_fronts:
			out.append(front)
	return out


static func spawn_time(data: Dictionary, ctx: Dictionary, index: int, previous_spawn_at: Variant) -> int:
	var hours: float
	var from: int
	if index == 0 or previous_spawn_at == null:
		hours = float(data.waves.graceHours)
		from = int(ctx.startedAt)
	else:
		var low := float(data.waves.intervalHours[0])
		var high := float(data.waves.intervalHours[1])
		hours = low + (high - low) * rng_for(int(ctx.seed), index, 0x51).next()
		from = int(previous_spawn_at)
	return LocalTime.ms(from + (hours * LocalTime.MS_PER_HOUR) / float(ctx.worldSpeed))


static func wave_size(data: Dictionary, index: int, player_count: int) -> int:
	var w: Dictionary = data.waves
	var players := 1.0 + float(w.perExtraPlayer) * maxi(0, player_count - 1)
	return maxi(1, js_round(float(w.baseUnits) * pow(float(w.growthPerWave), index) * players))


## Splits the size between the front's units by weight, the rest at random.
static func compose_wave(data: Dictionary, front: String, index: int, size: int, seed_value: int, player_count := 1) -> Dictionary:
	var units: Array = []
	var defs: Dictionary = data.enemies.fronts[front].units
	for id in defs:
		var def: Dictionary = defs[id]
		if float(def.weight) > 0 and int(def.minWave) <= index and int(def.get("minPlayers", 1) if def.get("minPlayers") != null else 1) <= player_count:
			units.append([id, float(def.weight)])
	var total_weight := 0.0
	for u in units:
		total_weight += u[1]
	var composition := {}
	var assigned := 0
	for u in units:
		var count := floori((size * u[1]) / total_weight)
		if count > 0:
			composition[u[0]] = count
		assigned += count
	var rng := rng_for(seed_value, index, 0xc0)
	while assigned < size:
		var roll := rng.next() * total_weight
		var picked: String = units[-1][0]
		for u in units:
			roll -= u[1]
			if roll < 0:
				picked = u[0]
				break
		composition[picked] = int(composition.get(picked, 0)) + 1
		assigned += 1
	return composition


static func threat_of(data: Dictionary, composition: Dictionary) -> String:
	var count := 0
	for n in composition.values():
		count += int(n)
	for t in data.waves.threatLevels:
		if t.maxUnits == null or count <= int(t.maxUnits):
			return t.name
	return data.waves.threatLevels[-1].name


static func wave_stance(data: Dictionary, front: String, seed_value: int, index: int) -> String:
	var stances: Dictionary = data.enemies.fronts.get(front, {}).get("stances", {})
	if stances.is_empty():
		return "balanced"
	var total_weight := 0.0
	for s in stances:
		total_weight += float(stances[s])
	var roll := LocalRng.new((seed_value ^ LocalRng.imul(index + 1, 0x27d4eb2f) ^ 0x57a7) & MASK).next() * total_weight
	for s in stances:
		roll -= float(stances[s])
		if roll < 0:
			return s
	return stances.keys()[-1]


static func plan_wave(data: Dictionary, ctx: Dictionary, index: int, previous_spawn_at: Variant) -> Dictionary:
	var fronts := wave_fronts(data, ctx.activeFronts)
	var front: String = fronts[index % fronts.size()]
	var size := maxi(1, js_round(wave_size(data, index, int(ctx.playerCount)) * float(ctx.get("sizeFactor", 1.0))))
	var composition := compose_wave(data, front, index, size, int(ctx.seed), int(ctx.playerCount))
	return {
		"index": index,
		"front": front,
		"spawnAt": spawn_time(data, ctx, index, previous_spawn_at),
		"composition": composition,
		"threat": threat_of(data, composition),
		"stance": wave_stance(data, front, int(ctx.seed), index),
	}


## How much bigger than its base size a wave comes (difficulty.ts).
static func wave_factor(data: Dictionary, difficulty: String, power: Dictionary) -> float:
	var p: Dictionary = data.difficulty.presets[difficulty]
	var players := maxf(1.0, float(power.players))
	var extra_villages := maxf(0.0, float(power.villages) / players - 1.0)
	var expected := players * float(data.difficulty.power.attackPerPlayer) * (1.0 + float(data.difficulty.power.growthPerWave) * int(power.waveIndex))
	var extra_army := maxf(0.0, float(power.armyAttack) / expected - 1.0)
	var bridge := 1.0 + float(data.bridge.powerPerStage) * float(power.get("bridgeStages", 0))
	var factor := float(p.waveScale) * (1.0 + float(p.powerWeight) * (extra_villages + extra_army)) * bridge
	return minf(float(p.maxFactor), maxf(float(p.floor), factor))
