class_name LocalEnemyForces
## The enemy's forces in a solo world (sim/enemyForces.ts,
## scheduler/enemyForces.ts; data/enemy-lands.json forces): garrisons and
## scouts, the watch (enemy_watch) that spots armies in the enemy lands, the
## sallies and patrols that march on them (band_arrive) and fight them, the
## patrols between settlements (enemy_patrol), and a horde's scouts finding
## an ambush.

const TWO_32 := 4294967296


static func seed_of(parts: Array) -> int:
	var sum := 0
	for i in parts.size():
		sum = (sum + int(parts[i]) * (1 if i == 0 else 7919 * i)) % TWO_32
	return sum


static func settlement_scouts(data: Dictionary, level: int) -> int:
	return 1 + floori(float(level - 1) / float(data.enemyLands.forces.scouts.perLevels))


static func garrison_size(data: Dictionary, kind: String, level: int) -> int:
	var g: Dictionary = data.enemyLands.forces.garrison
	return maxi(1, LocalWaves.js_round(float(g.baseUnits) * (1.0 + float(g.perLevel) * (level - 1)) * float(g.kinds.get(kind, 1.0))))


static func garrison_of(data: Dictionary, s: Dictionary, level: int, seed_value: int, players: int) -> Dictionary:
	return LocalWaves.compose_wave(data, String(s.front), level, garrison_size(data, String(s.kind), level), seed_of([seed_value, int(s.id), level]), players)


static func share_of(units: Dictionary, share: float) -> Dictionary:
	var out := {}
	var keys: Array = units.keys()
	keys.sort()
	for unit in keys:
		var n := LocalWaves.js_round(float(units[unit]) * share)
		if n > 0:
			out[unit] = n
	if out.is_empty():
		for unit in keys:
			if int(units[unit]) > 0:
				out[unit] = 1
				break
	return out


static func scouts_in(data: Dictionary, units: Dictionary) -> int:
	var n := 0
	for unit in units:
		if data.units.units.get(unit, {}).get("family") == "scout":
			n += int(units[unit])
	return n


static func spot_chance(data: Dictionary, scouts: int, against: int) -> float:
	var left := scouts - against
	return 1.0 - pow(1.0 - float(data.enemyLands.forces.scoutChance), left) if left > 0 else 0.0


static func horde_scouts(data: Dictionary, composition: Dictionary) -> int:
	var total := 0
	for unit in composition:
		total += int(composition[unit])
	return floori(float(total) / float(data.enemyLands.forces.scouts.hordeUnitsPerScout))


static func hex_on_path(path: Array, departs_at: int, at: int) -> Vector2i:
	var elapsed := at - departs_at
	var step: Dictionary = path[0]
	for s in path:
		if int(s.atMs) <= elapsed:
			step = s
	return Vector2i(int(step.q), int(step.r))


## Where an army is at `at` (Vector2i.MAX: nowhere on the map).
static func army_hex_at(army: Dictionary, at: int) -> Vector2i:
	if army.status == "stationed" or army.status == "engaged":
		return Vector2i(int(army.targetQ), int(army.targetR))
	var path: Variant = army.get("path")
	if path == null or path.is_empty():
		return Vector2i.MAX
	if army.status == "marching":
		return hex_on_path(path, int(army.departsAt), at)
	if army.status == "returning" and army.get("leavesAt") != null:
		var total := int(path[-1].atMs)
		var back: Array = []
		for i in range(path.size() - 1, -1, -1):
			back.append({"q": path[i].q, "r": path[i].r, "atMs": total - int(path[i].atMs)})
		return hex_on_path(back, int(army.leavesAt), at)
	return Vector2i.MAX


## The land war bands march on: the players' walls stop them, their own don't.
static func band_land(land: Dictionary) -> Dictionary:
	var out := land.duplicate()
	var walls := {}
	var all: Dictionary = land.get("walls", {})
	for key in all:
		if not all[key].get("enemy", false):
			walls[key] = all[key]
	out.walls = walls
	return out


static func _hours(data_hours: float, world: Dictionary) -> float:
	return data_hours * LocalTime.MS_PER_HOUR / float(world.speed)


static func _pending(world: Dictionary, type: String) -> bool:
	return world.events.any(func(e: Dictionary) -> bool: return e.status == "pending" and e.type == type)


static func ensure(server: LocalServer, world: Dictionary, now: int) -> void:
	var rules: Dictionary = server.data.enemyLands.forces
	if not _pending(world, "enemy_watch"):
		server.schedule(world, LocalTime.ms(now + _hours(float(rules.watchHours), world)), "enemy_watch", {})
	if not _pending(world, "enemy_patrol"):
		server.schedule(world, LocalTime.ms(now + _hours(float(rules.patrols.everyHours), world)), "enemy_patrol", {})


static func _route(server: LocalServer, land: Dictionary, world: Dictionary, from: Vector2i, to: Vector2i) -> Variant:
	return LocalLogistics.road_route(server.data, land, from, to, float(server.data.enemyLands.forces.speed), float(world.speed))


static func band_hex_at(band: Dictionary, at: int) -> Vector2i:
	return hex_on_path(band.path, int(band.departsAt), at)


static func _level(server: LocalServer, world: Dictionary, s: Dictionary, at: int) -> int:
	return LocalEnemySettlements.level_at(server.data, int(s.foundedAt), at, float(world.speed))


static func _bands(world: Dictionary) -> Array:
	if not world.has("enemyBands"):
		world.enemyBands = []
	return world.enemyBands


static func _find_band(world: Dictionary, id: int) -> Dictionary:
	for b in _bands(world):
		if int(b.id) == id:
			return b
	return {}


static func _delete(world: Dictionary, band: Dictionary) -> void:
	world.enemyBands = _bands(world).filter(func(b: Dictionary) -> bool: return int(b.id) != int(band.id))


static func _insert(world: Dictionary, band: Dictionary) -> Dictionary:
	# As the server keeps it (jsonb key order).
	band.units = LocalStore.stored(band.units)
	if not world.next.has("enemyBand"):
		world.next.enemyBand = 1
	band.id = world.next.enemyBand
	world.next.enemyBand += 1
	_bands(world).append(band)
	return band


static func _settlement(world: Dictionary, id: Variant) -> Dictionary:
	if id == null:
		return {}
	for s in world.get("enemySettlements", []):
		if int(s.id) == int(id):
			return s
	return {}


static func _march(server: LocalServer, world: Dictionary, band: Dictionary, path: Array, at: int) -> void:
	band.path = path
	band.departsAt = at
	band.arrivesAt = at + int(path[-1].atMs)
	server.schedule(world, int(band.arrivesAt), "band_arrive", {"bandId": band.id})


static func _go_home(server: LocalServer, world: Dictionary, band: Dictionary, at: int) -> void:
	var cell := band_hex_at(band, at)
	var home := _settlement(world, band.settlementId)
	if home.is_empty():
		_delete(world, band)
		return
	if HexMath.distance(home.cell, cell) == 0:
		_arrived_home(server, world, band, at)
		return
	var path: Variant = _route(server, band_land(LocalEnemyLands.army_land(server.data, world)), world, cell, home.cell)
	if path == null:
		_delete(world, band)
		return
	band.status = "returning"
	band.targetArmyId = null
	_march(server, world, band, path, at)


static func data_rest(server: LocalServer) -> float:
	return float(server.data.enemyLands.forces.patrols.restHours)


static func _arrived_home(server: LocalServer, world: Dictionary, band: Dictionary, at: int) -> void:
	if band.kind == "sally":
		_delete(world, band)
		return
	_next_leg(server, world, band, at)


static func _next_leg(server: LocalServer, world: Dictionary, band: Dictionary, at: int) -> void:
	var cell := band_hex_at(band, at)
	var others: Array = world.get("enemySettlements", []).filter(func(s: Dictionary) -> bool: return s.front == band.front and HexMath.distance(s.cell, cell) > 0)
	if others.is_empty():
		_delete(world, band)
		return
	var rng := LocalRng.new(seed_of([int(world.seed), int(band.id), floori(float(at) / 60000.0)]))
	var to: Dictionary = others[floori(rng.next() * others.size())]
	var path: Variant = _route(server, band_land(LocalEnemyLands.army_land(server.data, world)), world, cell, to.cell)
	if path == null:
		_delete(world, band)
		return
	band.status = "patrolling"
	band.settlementId = to.id
	band.targetArmyId = null
	# It rests at the settlement first.
	_march(server, world, band, path, LocalTime.ms(at + _hours(float(data_rest(server)), world)))


static func _band_battle(server: LocalServer, world: Dictionary, band: Dictionary, army: Dictionary, cell: Vector2i, at: int) -> void:
	var data := server.data
	var home := _settlement(world, band.settlementId)
	var name := LocalEnemySettlements.settlement_name(data, String(home.front), String(home.kind)) if band.kind == "sally" and not home.is_empty() else "Patrol"
	var stage := {"stage": 1, "name": name, "stronghold": false, "field": null, "enemy": band.units}
	var village := server.find_village(world, int(army.homeVillageId))
	var hero := LocalArmies.hero_with_army(world, int(army.id))
	var general := LocalGenerals.general_with_army(world, int(army.id))
	var owned := LocalVillage.village_bonuses(data, village.state)
	var bonuses := LocalArmies._led_bonuses(data, owned, hero, general)
	var succession := LocalArmies._led_bonuses(data, owned, {}, general)
	var initial: Dictionary = army.units.duplicate()
	var fighters := LocalScouting.combatants(data, army.units)
	var result := LocalRaids.raid_battle(data, fighters, LocalScouting.with_intel(data, army.units, LocalBattle.player_stats(data, bonuses, false)),
		army.get("stance", "balanced"), stage, String(band.front), int(world.seed), int(army.id) * 8 + 5 + int(band.id) * 64,
		LocalChampions.champions_of(data, hero, general, owned), LocalScouting.with_intel(data, army.units, LocalBattle.player_stats(data, succession, false)),
		{"attacker": LocalLines.command_of(data, String(army.get("maneuver", "encircle")), [{"hero": hero, "general": general}]), "defender": LocalLines.no_command()}, LocalSeasons.defense_at(data, world, at))
	var kills := LocalBattle.total(band.units) - LocalBattle.total(result.enemyNow)
	var lost := LocalArmies._losses({"units": fighters}, result.armyNow)
	var battle := LocalArmies._assault_battle(world, {"waveId": null, "villageId": null, "q": cell.x, "r": cell.y,
		"setup": {"raid": {"front": band.front, "name": name, "stronghold": false, "stage": 1, "band": true}},
		"attackerStance": data.raids.fieldStance, "attackerInitial": band.units.duplicate(), "defenderInitial": initial, "startedAt": at},
		{"rounds": result.rounds}, at, "defended" if result.won else "raided", null)
	# The army holds its hex with those left (none left: it is gone).
	var after := LocalArmies.army_losses(server, world, army, lost, at)
	if LocalBattle.total(after.units) == 0:
		LocalArmies.send_home(server, world, after, at)
	LocalChampions.fall(server, world, result.fallen, hero, general, army.homeVillageId, {"kills": kills, "battleId": battle.id, "at": at})
	if not hero.is_empty() and not "hero" in result.fallen:
		LocalBattles.hero_after_battle(server, world, hero, {"kills": kills, "won": result.won, "battleId": battle.id, "at": at})
	if not general.is_empty() and not "general" in result.fallen:
		LocalGenerals.after_battle(server, world, general, {"kills": kills, "won": result.won, "at": at})
	if LocalBattle.total(result.enemyNow) == 0:
		_delete(world, band)
	else:
		band.units = LocalStore.stored(result.enemyNow)
		_go_home(server, world, band, at)
	LocalInbox.tell(server, world, army.ownerAccountId, {"kind": "battle_result", "tier": "push",
		"title": "Your army beat off a war band at ({q}, {r})" if result.won else "A war band mauled your army at ({q}, {r})",
		"body": "{kills} of them fell, {lost} of ours.", "vars": {"q": cell.x, "r": cell.y, "kills": kills, "lost": LocalBattle.total(lost)}}, at)


static func on_enemy_watch(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	if world.status != "running":
		return
	var data := server.data
	var at := int(event.dueAt)
	var rules: Dictionary = data.enemyLands.forces
	server.schedule(world, LocalTime.ms(at + _hours(float(rules.watchHours), world)), "enemy_watch", {})
	var settlements: Array = world.get("enemySettlements", [])
	var armies: Array = world.armies.filter(func(a: Dictionary) -> bool: return a.status != "done" and a.get("raid") == null)
	armies.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x.id) < int(y.id))
	var players: int = world.members.size()
	var land: Variant = null
	for army in armies:
		var cell := army_hex_at(army, at)
		if cell == Vector2i.MAX:
			continue
		var where := LocalEnemyLands.hex_at(data, world, cell)
		if where.is_empty():
			continue
		if _bands(world).any(func(b: Dictionary) -> bool: return b.status == "hunting" and b.targetArmyId != null and int(b.targetArmyId) == int(army.id)):
			continue
		var guards := scouts_in(data, army.units)
		var rng := LocalRng.new(seed_of([int(world.seed), int(army.id), floori(float(at) / 60000.0)]))
		var watchers: Array = []
		for s in settlements:
			if s.front == where.front and HexMath.distance(s.cell, cell) <= int(rules.sightRange):
				watchers.append(settlement_scouts(data, _level(server, world, s, at)))
		for b in _bands(world):
			if b.front == where.front and HexMath.distance(band_hex_at(b, at), cell) <= int(rules.sightRange):
				watchers.append(int(b.scouts))
		var spotted := false
		for scouts in watchers:
			if rng.next() < spot_chance(data, scouts, guards):
				spotted = true
		if not spotted:
			continue
		if land == null:
			land = band_land(LocalEnemyLands.army_land(data, world))
		var sent := 0
		var ready: Dictionary = {}
		for s in settlements:
			if s.front != where.front or HexMath.distance(s.cell, cell) > int(rules.pullRange):
				continue
			if s.get("sallyReadyAt") != null and int(s.sallyReadyAt) > at:
				continue
			if ready.is_empty() or HexMath.distance(s.cell, cell) < HexMath.distance(ready.cell, cell) or (HexMath.distance(s.cell, cell) == HexMath.distance(ready.cell, cell) and int(s.id) < int(ready.id)):
				ready = s
		if not ready.is_empty():
			var path: Variant = _route(server, land, world, ready.cell, cell)
			if path != null:
				var units := share_of(garrison_of(data, ready, _level(server, world, ready, at), int(world.seed), players), float(rules.sally.share))
				var band := _insert(world, {"front": ready.front, "kind": "sally", "settlementId": ready.id, "units": units, "scouts": 1, "status": "hunting",
					"path": path, "departsAt": at, "arrivesAt": at + int(path[-1].atMs), "targetArmyId": army.id})
				server.schedule(world, int(band.arrivesAt), "band_arrive", {"bandId": band.id})
				ready.sallyReadyAt = LocalTime.ms(at + _hours(float(rules.sally.cooldownHours), world))
				sent += 1
		for b in _bands(world).duplicate():
			if b.front != where.front or b.kind != "patrol" or b.status != "patrolling":
				continue
			var from := band_hex_at(b, at)
			if HexMath.distance(from, cell) > int(rules.pullRange):
				continue
			var path: Variant = _route(server, land, world, from, cell)
			if path == null:
				continue
			b.status = "hunting"
			b.targetArmyId = army.id
			_march(server, world, b, path, at)
			sent += 1
		if sent > 0:
			LocalInbox.tell(server, world, army.ownerAccountId, {"kind": "under_attack", "tier": "push", "title": "Enemy scouts spotted your army at ({q}, {r})",
				"body": "{bands} war band(s) of the {faction} march on it.", "vars": {"q": cell.x, "r": cell.y, "bands": sent, "faction": String(data.enemies.fronts.get(where.front, {}).get("faction", where.front))}}, at)
	changed.append(["world"])


static func on_enemy_patrol(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	if world.status != "running":
		return
	var data := server.data
	var at := int(event.dueAt)
	var rules: Dictionary = data.enemyLands.forces
	server.schedule(world, LocalTime.ms(at + _hours(float(rules.patrols.everyHours), world)), "enemy_patrol", {})
	var players: int = world.members.size()
	var land: Variant = null
	for i in world.activeFronts.size():
		var front: String = world.activeFronts[i]
		var own: Array = world.get("enemySettlements", []).filter(func(s: Dictionary) -> bool: return s.front == front)
		if own.size() < 2 or _bands(world).filter(func(b: Dictionary) -> bool: return b.front == front and b.kind == "patrol").size() >= int(rules.patrols.perFront):
			continue
		var rng := LocalRng.new(seed_of([int(world.seed), i + 1, floori(float(at) / 60000.0)]))
		var home: Dictionary = own[floori(rng.next() * own.size())]
		var others: Array = own.filter(func(s: Dictionary) -> bool: return int(s.id) != int(home.id))
		var to: Dictionary = others[floori(rng.next() * others.size())]
		if land == null:
			land = band_land(LocalEnemyLands.army_land(data, world))
		var path: Variant = _route(server, land, world, home.cell, to.cell)
		if path == null:
			continue
		var units := share_of(garrison_of(data, home, _level(server, world, home, at), int(world.seed), players), float(rules.patrols.share))
		var band := _insert(world, {"front": front, "kind": "patrol", "settlementId": to.id, "units": units, "scouts": int(rules.patrols.scouts), "status": "patrolling",
			"path": path, "departsAt": at, "arrivesAt": at + int(path[-1].atMs), "targetArmyId": null})
		server.schedule(world, int(band.arrivesAt), "band_arrive", {"bandId": band.id})
	changed.append(["world"])


static func on_band_arrive(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var band := _find_band(world, int(event.payload.bandId))
	var at := int(event.dueAt)
	if band.is_empty() or int(band.arrivesAt) != at or world.status != "running":
		return
	var data := server.data
	var cell := band_hex_at(band, at)
	if band.status == "hunting":
		var army: Dictionary = LocalArmies.find_army(world, int(band.targetArmyId)) if band.targetArmyId != null else {}
		var army_cell := army_hex_at(army, at) if not army.is_empty() and army.status != "done" and army.get("raid") == null else Vector2i.MAX
		if army_cell != Vector2i.MAX and HexMath.distance(army_cell, cell) <= 1:
			_band_battle(server, world, band, army, army_cell, at)
		elif army_cell != Vector2i.MAX and not LocalEnemyLands.hex_at(data, world, army_cell).is_empty() and HexMath.distance(army_cell, cell) <= int(data.enemyLands.forces.sally.chaseRange):
			var path: Variant = _route(server, band_land(LocalEnemyLands.army_land(data, world)), world, cell, army_cell)
			if path != null:
				_march(server, world, band, path, at)
			else:
				_go_home(server, world, band, at)
		else:
			_go_home(server, world, band, at)
	elif band.status == "patrolling":
		_next_leg(server, world, band, at)
	else:
		_arrived_home(server, world, band, at)
	changed.append(["world"])


## api map.bands (scheduler/enemyForces.ts bandsView).
static func view(data: Dictionary, world: Dictionary, now: int) -> Array:
	var out: Array = []
	for b in _bands(world):
		if b.status != "hunting":
			var where := LocalEnemyLands.hex_at(data, world, band_hex_at(b, now))
			if where.is_empty() or int(where.band) > LocalEnemyLands.sight_of(data, world, String(where.front)):
				continue
		out.append({"id": b.id, "front": b.front, "kind": b.kind, "status": b.status, "units": b.units.duplicate(), "targetArmyId": b.targetArmyId,
			"departsAt": LocalTime.iso(b.departsAt), "arrivesAt": LocalTime.iso(b.arrivesAt), "path": b.path.map(func(s: Dictionary) -> Array: return [s.q, s.r, s.atMs])})
	return out
