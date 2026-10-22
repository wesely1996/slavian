class_name LocalArmies
extends RefCounted
## Armies for the local engine: server/src/sim/armies.ts, sim/field.ts,
## commands/armies.ts, scheduler/armies.ts, the field battles, forts,
## roads and bridges of scheduler/field.ts, storming camps and abandoned
## forts (scheduler/camps.ts), and exploring sites (scheduler/sites.ts).

const FIGHTERS := ["infantry", "archers", "cavalry"]
const WATER := ["lake", "sea"]


# --- Rules (sim/armies.ts) ----------------------------------------------------------

static func fighters(data: Dictionary, units: Dictionary) -> Dictionary:
	var out := {}
	for unit in units:
		var def: Variant = data.units.units.get(unit)
		if def != null and def.family in FIGHTERS and unit != "settler" and int(units[unit]) > 0:
			out[unit] = units[unit]
	return out


## Hexes per hour on plains: the slowest unit sets the pace.
static func army_speed(data: Dictionary, units: Dictionary) -> float:
	var slowest := INF
	for unit in units:
		if int(units[unit]) > 0:
			slowest = minf(slowest, float(data.units.units.get(unit, {}).get("speed", 1)))
	return slowest if slowest != INF else 1.0


static func cavalry_share(data: Dictionary, units: Dictionary) -> float:
	var all := LocalBattle.total(units)
	if all == 0:
		return 0.0
	var cavalry := 0
	for unit in units:
		if data.units.units.get(unit, {}).get("family") == "cavalry":
			cavalry += int(units[unit])
	return float(cavalry) / all


static func _marches(data: Dictionary, unit: String, orders: String) -> bool:
	return not fighters(data, {unit: 1}).is_empty() or (orders == "explore" and data.units.units.get(unit, {}).get("family") == "scout")


## Checks an army about to set out: its units, or {"error"}.
static func validate_army(data: Dictionary, units: Dictionary, orders: String) -> Dictionary:
	for unit in units:
		var n := float(units[unit])
		if n != floorf(n) or n < 0:
			return LocalVillage.rule("Troop counts are whole numbers")
		if n > 0 and not _marches(data, unit, orders):
			return LocalVillage.rule("%s don't march with armies" % data.units.units.get(unit, {}).get("name", unit))
	var army := {}
	for unit in units:
		if int(units[unit]) > 0 and _marches(data, unit, orders):
			army[unit] = int(units[unit])
	if LocalBattle.total(army) == 0:
		return LocalVillage.rule("Send at least one soldier")
	if orders == "harass" and cavalry_share(data, army) < float(data.armies.harass.minCavalryShare):
		return LocalVillage.rule("Harassing takes mostly cavalry (%d%% or more)" % LocalWaves.js_round(float(data.armies.harass.minCavalryShare) * 100))
	return army


## `share` of each fighting unit, rounded down.
static func share_of(data: Dictionary, units: Dictionary, share: float) -> Dictionary:
	var out := {}
	var f := fighters(data, units)
	for unit in f:
		var part := floori(int(f[unit]) * share)
		if part > 0:
			out[unit] = part
	return out


## Degrees between the directions two forces come from, seen from `at`.
static func approach_angle(at: Vector2i, a: Vector2i, b: Vector2i) -> float:
	var sqrt3 := sqrt(3.0)
	var px := func(h: Vector2i) -> float: return sqrt3 * h.x + (sqrt3 / 2.0) * h.y
	var py := func(h: Vector2i) -> float: return 1.5 * h.y
	var ax: float = px.call(a) - px.call(at)
	var ay: float = py.call(a) - py.call(at)
	var bx: float = px.call(b) - px.call(at)
	var by: float = py.call(b) - py.call(at)
	var la := sqrt(ax * ax + ay * ay)
	var lb := sqrt(bx * bx + by * by)
	if la == 0 or lb == 0:
		return 0.0
	var c := maxf(-1.0, minf(1.0, (ax * bx + ay * by) / (la * lb)))
	return (acos(c) * 180.0) / PI


## The first-round bonus of an army joining a battle.
static func join_bonus(data: Dictionary, orders: String, army_size: int, horde_size: int, angle: float) -> float:
	if horde_size <= 0:
		return 0.0
	var ratio := float(army_size) / horde_size
	if orders == "harass":
		return minf(float(data.armies.harass.maxBonus), float(data.armies.harass.scale) * ratio)
	if angle < float(data.armies.pincer.minAngle):
		return 0.0
	return minf(float(data.armies.pincer.maxBonus), float(data.armies.pincer.scale) * ratio)


# --- Finding things ------------------------------------------------------------------

static func find_army(world: Dictionary, id: int) -> Dictionary:
	for a in world.armies:
		if int(a.id) == id:
			return a
	return {}


static func _by_id(list: Array) -> Array:
	var out := list.duplicate()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.id) < int(b.id))
	return out


## Armies at a village with one of `statuses` (db/armies.ts armiesAt).
static func armies_at(world: Dictionary, village_id: int, statuses: Array) -> Array:
	return _by_id(world.armies.filter(func(a: Dictionary) -> bool:
		return a.targetVillageId != null and int(a.targetVillageId) == village_id and a.status in statuses))


## Armies holding a hex (not at a village).
static func armies_holding(world: Dictionary, cell: Vector2i, statuses: Array) -> Array:
	return _by_id(world.armies.filter(func(a: Dictionary) -> bool:
		return a.targetVillageId == null and int(a.targetQ) == cell.x and int(a.targetR) == cell.y and a.status in statuses))


static func armies_in_battle(world: Dictionary, battle_id: int) -> Array:
	return _by_id(world.armies.filter(func(a: Dictionary) -> bool:
		return a.battleId != null and int(a.battleId) == battle_id and a.status == "engaged"))


static func hero_with_army(world: Dictionary, army_id: int) -> Dictionary:
	for h in world.heroes:
		if h.armyId != null and int(h.armyId) == army_id and h.status == "with_army":
			return h
	return {}


static func hero_of(world: Dictionary, account_id: int) -> Dictionary:
	for h in world.heroes:
		if int(h.accountId) == account_id:
			return h
	return {}


static func camp_at(world: Dictionary, cell: Vector2i) -> Dictionary:
	for c in world.camps:
		if c.status == "active" and int(c.q) == cell.x and int(c.r) == cell.y:
			return c
	return {}


static func site_at(world: Dictionary, cell: Vector2i) -> Dictionary:
	for s in world.sites:
		if int(s.q) == cell.x and int(s.r) == cell.y:
			return s
	return {}


static func fort_at(world: Dictionary, cell: Vector2i) -> Dictionary:
	for f in world.forts:
		if int(f.q) == cell.x and int(f.r) == cell.y:
			return f
	return {}


static func find_fort(world: Dictionary, id: int) -> Dictionary:
	for f in world.forts:
		if int(f.id) == id:
			return f
	return {}


# --- Setting out and coming home (scheduler/armies.ts) -----------------------------

## Sends troops from a village as an army (dispatchArmy): the army, or {"error"}.
static func dispatch_army(server: LocalServer, world: Dictionary, order: Dictionary) -> Dictionary:
	var data := server.data
	var units := validate_army(data, order.units, order.orders)
	if units.has("error"):
		return units
	var home := server.find_village(world, int(order.homeVillageId))
	var at := int(order.at)
	var to: Vector2i
	var target_hex: Variant = order.get("targetHex")
	match String(order.orders):
		"explore":
			if target_hex == null:
				return LocalVillage.rule("Say which site to explore")
			to = target_hex
			var site := site_at(world, to)
			if site.is_empty():
				return LocalVillage.rule("There is no ancient site there")
			if site.status == "explored":
				return LocalVillage.rule("That site has already been explored")
		"clear":
			if target_hex == null:
				return LocalVillage.rule("Say which camp to clear")
			to = target_hex
			if camp_at(world, to).is_empty():
				return LocalVillage.rule("There is no camp there")
		"hold":
			if target_hex == null:
				return LocalVillage.rule("Say which hex to hold")
			to = target_hex
			var terrain: Variant = world.hexes.get(LocalLand.key(to))
			if terrain == null or data.terrain.terrain[terrain].moveCost == null:
				return LocalVillage.rule("No army can stand there")
			if to == Vector2i(home.q, home.r):
				return LocalVillage.rule("That is the village itself")
		_:
			if order.get("targetVillageId") == null or int(order.targetVillageId) == int(home.id):
				return LocalVillage.rule("Send them to another village")
			var target := server.find_village(world, int(order.targetVillageId))
			if target.is_empty():
				return LocalVillage.rule("No such village in this world")
			to = Vector2i(target.q, target.r)
	var state := LocalVillage.complete_training(home.state, at)
	for unit in units:
		state = LocalVillage.send_away(state, unit, int(units[unit]), at)
		if state.has("error"):
			return state
	var path: Variant = LocalLogistics.road_route(data, LocalHordes.land_of(world), Vector2i(home.q, home.r), to, army_speed(data, units), world.speed)
	if path == null:
		return LocalVillage.rule("No road leads there")
	var hero_account: Variant = null
	if order.get("withHero", false):
		var hero := hero_of(world, int(home.ownerAccountId))
		if hero.status != "home" or hero.villageId == null or int(hero.villageId) != int(home.id):
			return LocalVillage.rule("%s is not ready in %s" % [hero.name, home.name])
		if home.state.besieged:
			return LocalVillage.rule("%s won't leave in the middle of a battle" % hero.name)
		hero_account = hero.accountId
	var army := {"id": world.next.army, "ownerAccountId": home.ownerAccountId, "homeVillageId": home.id,
		"targetVillageId": null if order.orders in ["hold", "clear", "explore"] else order.get("targetVillageId"),
		"targetQ": to.x, "targetR": to.y, "heroAccountId": hero_account, "orders": order.orders, "units": units, "status": "marching",
		"loot": null, "battleId": null, "joinsRound": null, "joinBonus": 0, "path": path, "departsAt": at, "arrivesAt": at + int(path[-1].atMs),
		"leavesAt": null, "returnsAt": null}
	world.next.army += 1
	world.armies.append(army)
	if hero_account != null:
		var hero := hero_of(world, int(hero_account))
		hero.status = "with_army"
		hero.villageId = null
		hero.armyId = army.id
	home.state = state
	server.schedule(world, int(army.arrivesAt), "army_arrive", {"armyId": army.id})
	return army


## Turns an army for home along the road it came. An army with no one left
## is done; its hero is carried home wounded.
static func send_home(server: LocalServer, world: Dictionary, army: Dictionary, at: int) -> Dictionary:
	if LocalBattle.total(army.units) == 0:
		army.status = "done"
		army.battleId = null
		army.leavesAt = at
		army.returnsAt = at
		var hero := hero_with_army(world, int(army.id))
		if not hero.is_empty():
			var wounded_until := at + LocalHeroes.wound_ms(server.data, world.speed, hero.kind)
			hero.status = "wounded"
			hero.villageId = army.homeVillageId
			hero.armyId = null
			hero.woundedUntil = LocalTime.iso(wounded_until)
			server.schedule(world, wounded_until, "hero_recover", {"accountId": hero.accountId})
		return army
	army.status = "returning"
	army.battleId = null
	army.leavesAt = at
	army.returnsAt = at + int(army.path[-1].atMs)
	server.schedule(world, int(army.returnsAt), "army_return", {"armyId": army.id})
	return army


## An army joins the battle at its target village from the next round.
static func join_battle(server: LocalServer, army: Dictionary, battle: Dictionary, wave: Dictionary) -> void:
	var village_hex := Vector2i(battle.q, battle.r)
	var horde_step: Variant = null
	if wave.path != null:
		for s in wave.path:
			if int(s.q) != village_hex.x or int(s.r) != village_hex.y:
				horde_step = s
	var army_step: Variant = army.path[-2] if army.path.size() >= 2 else null
	var angle := 0.0
	if horde_step != null and army_step != null:
		angle = approach_angle(village_hex, Vector2i(horde_step.q, horde_step.r), Vector2i(army_step.q, army_step.r))
	var bonus := join_bonus(server.data, army.orders, LocalBattle.total(army.units), LocalBattle.total(wave.composition), angle)
	army.status = "engaged"
	army.battleId = battle.id
	army.joinsRound = int(battle.round) + 1
	army.joinBonus = bonus
	_add_defenders(battle, army.units)


static func _add_defenders(battle: Dictionary, units: Dictionary) -> void:
	var sum: Dictionary = battle.defenderInitial.duplicate()
	for unit in units:
		sum[unit] = int(sum.get(unit, 0)) + int(units[unit])
	battle.defenderInitial = sum


## A battle starts at a village: armies standing there join at once, and
## villages in range send their share of troops.
static func rally_to_battle(server: LocalServer, world: Dictionary, battle: Dictionary, village: Dictionary, at: int) -> void:
	for army in armies_at(world, int(village.id), ["stationed"]):
		army.status = "engaged"
		army.battleId = battle.id
		army.joinsRound = 1
		army.joinBonus = 0
		_add_defenders(battle, army.units)
	for other in world.villages:
		if int(other.id) == int(village.id) or other.state.besieged:
			continue
		var rule: Dictionary = other.reinforce
		if float(rule.share) <= 0 or HexMath.distance(Vector2i(other.q, other.r), Vector2i(village.q, village.r)) > int(rule.range):
			continue
		var units := share_of(server.data, LocalVillage.complete_training(other.state, at).garrison, float(rule.share))
		if LocalBattle.total(units) == 0:
			continue
		# No road there: this village can't help.
		dispatch_army(server, world, {"homeVillageId": other.id, "targetVillageId": village.id, "units": units, "orders": "reinforce", "at": at})


## Losses an army took in a round: its home village stops feeding the dead.
static func army_losses(server: LocalServer, world: Dictionary, army: Dictionary, losses: Dictionary, at: int) -> Dictionary:
	if LocalBattle.total(losses) == 0:
		return army
	var home := server.find_village(world, int(army.homeVillageId))
	var state: Dictionary = home.state
	for unit in losses:
		state = LocalVillage.lose_away(server.data, state, unit, int(losses[unit]), at, world.speed)
	home.state = state
	var units := {}
	for unit in army.units:
		var n := int(army.units[unit]) - int(losses.get(unit, 0))
		if n > 0:
			units[unit] = n
	army.units = units
	return army


static func on_army_arrive(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var army := find_army(world, int(event.payload.armyId))
	if army.is_empty() or army.status != "marching":
		return
	var at := int(event.dueAt)
	changed.append(["world"])
	match String(army.orders):
		"explore":
			arrive_at_site(server, world, army, at, changed)
			return
		"clear":
			storm_camp(server, world, army, at, changed)
			return
		"hold":
			army.status = "stationed"
			var fort := fort_at(world, Vector2i(army.targetQ, army.targetR))
			if not fort.is_empty():
				fort.mannedAt = at
			intercept_at(server, world, Vector2i(army.targetQ, army.targetR), at)
			return
	var ongoing: Dictionary = {}
	for b in world.battles:
		if b.villageId != null and int(b.villageId) == int(army.targetVillageId) and b.status == "ongoing":
			ongoing = b
			break
	if not ongoing.is_empty() and ongoing.waveId != null:
		join_battle(server, army, ongoing, server.find_wave(world, int(ongoing.waveId)))
	elif army.orders == "support":
		army.status = "stationed"
	else:
		send_home(server, world, army, at)


static func on_army_return(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var army := find_army(world, int(event.payload.armyId))
	if army.is_empty() or army.status != "returning":
		return
	var home := server.find_village(world, int(army.homeVillageId))
	var state: Dictionary = home.state
	for unit in army.units:
		state = LocalVillage.return_home(state, unit, int(army.units[unit]))
	home.state = state
	army.status = "done"
	# Loot from a cleared camp goes into the stores.
	if army.loot != null:
		home.state.ledger = LocalLogistics.receive(home.state.ledger, int(event.dueAt), army.loot).ledger
		army.loot = null
	var hero := hero_with_army(world, int(army.id))
	if not hero.is_empty():
		hero.status = "home"
		hero.villageId = home.id
		hero.armyId = null
	changed.append(["village", home.id])
	changed.append(["world"])


# --- Commands (commands/armies.ts) -----------------------------------------------------

static func send_army(server: LocalServer, world: Dictionary, village: Dictionary, body: Dictionary, now: int) -> Dictionary:
	var target: Variant = body.get("target")
	var units: Variant = body.get("units")
	if not units is Dictionary or not String(body.get("orders", "")) in ["support", "reinforce", "harass", "hold", "clear", "explore"]:
		return {"error": "Give the army its units and orders", "kind": "invalid"}
	return dispatch_army(server, world, {"homeVillageId": village.id, "targetVillageId": body.get("targetVillageId"),
		"targetHex": Vector2i(int(target.q), int(target.r)) if target is Dictionary else null, "units": units, "orders": body.orders,
		"withHero": body.get("withHero", false), "at": now})


## Calls an army standing guard or holding a hex home.
static func recall(server: LocalServer, world: Dictionary, army_id: int, now: int) -> Dictionary:
	var army := find_army(world, army_id)
	if army.is_empty():
		return {"error": "No such army", "kind": "not_found"}
	if army.status == "engaged":
		return LocalVillage.rule("That army is in the middle of a battle")
	if army.status != "stationed":
		return LocalVillage.rule("Only armies standing guard can be called home")
	return send_home(server, world, army, now)


## How a village answers battles nearby.
static func set_reinforce(data: Dictionary, village: Dictionary, body: Dictionary) -> Dictionary:
	var share := float(body.get("share", -1))
	var range_value := float(body.get("range", -1))
	if not (share >= 0 and share <= 1):
		return LocalVillage.rule("Send between 0% and 100%")
	if range_value != floorf(range_value) or range_value < 0 or range_value > float(data.armies.reinforce.maxRange):
		return LocalVillage.rule("Range is 0 to %d hexes" % int(data.armies.reinforce.maxRange))
	village.reinforce = {"share": body.share, "range": body.range}
	return {"reinforce": village.reinforce}


# --- The field (sim/field.ts, scheduler/field.ts) -------------------------------------

static func is_choke_point(data: Dictionary, terrain: Dictionary, cell: Vector2i) -> bool:
	var passable := func(h: Vector2i) -> bool:
		var t: Variant = terrain.get(LocalLand.key(h))
		return t != null and data.terrain.terrain[t].moveCost != null
	if not passable.call(cell):
		return false
	var blocked := 0
	for n in HexMath.neighbors(cell):
		if not passable.call(n):
			blocked += 1
	return blocked >= int(data.field.choke.minBlockedNeighbors)


static func setup_at(data: Dictionary, terrain: Dictionary, cell: Vector2i, ready_since: int, horde_arrives: int, world_speed: float, fort: bool, river: bool) -> Dictionary:
	var type: Variant = terrain.get(LocalLand.key(cell))
	var prep_ms := (float(data.field.ambush.prepMinutes) * 60000.0) / world_speed
	return {"ambush": type != null and type in data.field.ambush.terrain and horde_arrives - ready_since >= prep_ms,
		"choke": is_choke_point(data, terrain, cell), "fort": fort, "river": river}


## Schedules a field_intercept for when `wave` enters each held hex at or
## after `from_ms` into its march (not the end of its road).
static func schedule_intercepts(server: LocalServer, world: Dictionary, wave: Dictionary, cells: Array, from_ms: int) -> void:
	if wave.path == null:
		return
	var end: Dictionary = wave.path[-1]
	for cell in cells:
		if int(end.q) == cell.x and int(end.r) == cell.y:
			continue
		var step: Dictionary = {}
		for s in wave.path:
			if int(s.q) == cell.x and int(s.r) == cell.y and int(s.atMs) >= from_ms:
				step = s
				break
		if step.is_empty():
			continue
		var payload := {"waveId": wave.id, "q": cell.x, "r": cell.y, "atMs": step.atMs}
		if server.pending(world, "field_intercept", payload):
			continue
		server.schedule(world, int(wave.spawnAt) + int(step.atMs), "field_intercept", payload)


## Hexes armies hold (DISTINCT; the server's order doesn't matter, each
## schedules its own event).
static func held_hexes(world: Dictionary) -> Array:
	var seen := {}
	var out: Array = []
	for a in world.armies:
		if a.orders == "hold" and a.targetVillageId == null and a.status == "stationed":
			var cell := Vector2i(a.targetQ, a.targetR)
			if not seen.has(cell):
				seen[cell] = true
				out.append(cell)
	return out


static func plan_intercepts(server: LocalServer, world: Dictionary, wave: Dictionary, from_ms := 0) -> void:
	schedule_intercepts(server, world, wave, held_hexes(world), from_ms)


## An army has just taken up a hex: hordes still to pass it will meet it.
static func intercept_at(server: LocalServer, world: Dictionary, cell: Vector2i, at: int) -> void:
	var active: Array = world.waves.filter(func(w: Dictionary) -> bool: return w.status == "marching")
	active.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.index) < int(b.index))
	for wave in active:
		schedule_intercepts(server, world, wave, [cell], at - int(wave.spawnAt))


static func on_field_intercept(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var p: Dictionary = event.payload
	var wave := server.find_wave(world, int(p.waveId))
	if wave.is_empty() or wave.status != "marching" or wave.path == null:
		return
	if not wave.path.any(func(s: Dictionary) -> bool: return int(s.q) == int(p.q) and int(s.r) == int(p.r) and int(s.atMs) == int(p.atMs)):
		return
	start_field_battle(server, world, wave, Vector2i(int(p.q), int(p.r)), int(event.dueAt))
	changed.append(["world"])


static func start_field_battle(server: LocalServer, world: Dictionary, wave: Dictionary, cell: Vector2i, at: int) -> void:
	var data := server.data
	var holders := armies_holding(world, cell, ["stationed"])
	if holders.is_empty():
		return
	var ready_since: int = holders.map(func(a: Dictionary) -> int: return int(a.arrivesAt)).min()
	var rivers := {}
	for e in world.rivers:
		rivers[LocalLand.edge_key(e.a, e.b)] = true
	var fort := fort_at(world, cell)
	var setup := setup_at(data, world.hexes, cell, ready_since, at, world.speed, not fort.is_empty() and fort.status == "standing",
		LocalBattles.came_over_river(wave.path if wave.path != null else [], cell, rivers))
	wave.status = "battling"
	var defenders := {}
	for a in holders:
		defenders = LocalCamps.add_units(defenders, a.units)
	var battle := LocalBattles.insert_battle(world, {"waveId": wave.id, "villageId": null, "q": cell.x, "r": cell.y, "setup": setup,
		"attackerStance": wave.stance, "attackerInitial": wave.composition, "defenderInitial": defenders, "startedAt": at})
	for army in holders:
		army.status = "engaged"
		army.battleId = battle.id
		army.joinsRound = 1
		army.joinBonus = 0
	server.schedule(world, at + LocalBattle.round_ms(data, world.speed), "battle_round", {"battleId": battle.id})
	var ground: Array = []
	for pair in [["ambush", "an ambush"], ["choke", "a choke point"], ["fort", "a fort"], ["river", "a river crossing"]]:
		if setup[pair[0]]:
			ground.append(pair[1])
	var text := ", ".join(ground)
	for owner in owners(holders):
		LocalInbox.tell(server, world, owner, {"kind": "under_attack", "tier": "push", "title": "A horde ran into your army at ({q}, {r})",
			"body": "{enemy} against {defenders}, with {ground}." if text != "" else "{enemy} against {defenders}.",
			"vars": {"q": cell.x, "r": cell.y, "enemy": LocalBattle.total(wave.composition), "defenders": LocalBattle.total(battle.defenderInitial), "ground": text}}, at)


## The accounts that own `armies`, each once, in order.
static func owners(armies: Array) -> Array:
	var out: Array = []
	for a in armies:
		if a.ownerAccountId != null and not int(a.ownerAccountId) in out:
			out.append(int(a.ownerAccountId))
	return out


## The horde broke through: the rest of its road shifts by the time it spent
## fighting, and its raids and later intercepts are planned again.
static func march_on(server: LocalServer, world: Dictionary, wave: Dictionary, cell: Vector2i, at: int) -> void:
	var path: Array = wave.path if wave.path != null else []
	var since_spawn := at - int(wave.spawnAt)
	var step: Dictionary = {}
	for i in range(path.size() - 1, -1, -1):
		var s: Dictionary = path[i]
		if int(s.q) == cell.x and int(s.r) == cell.y and int(s.atMs) <= since_spawn:
			step = s
			break
	var delay := maxi(0, since_spawn - int(step.atMs)) if not step.is_empty() else 0
	var shifted: Array = path.map(func(s: Dictionary) -> Dictionary:
		if not step.is_empty() and int(s.atMs) > int(step.atMs):
			var moved := s.duplicate()
			moved.atMs = int(s.atMs) + delay
			return moved
		return s)
	var late := LocalHordes.hold_for_quiet(world, int(wave.spawnAt), {"path": shifted,
		"arrivesAt": (int(wave.arrivesAt) if wave.arrivesAt != null else at) + delay})
	wave.status = "marching"
	wave.path = late.path
	wave.arrivesAt = late.arrivesAt
	world.events = world.events.filter(func(e: Dictionary) -> bool:
		return not (e.status == "pending" and e.type in ["outpost_raid", "field_intercept"] and int(e.payload.get("waveId", -1)) == int(wave.id)))
	server.schedule(world, int(late.arrivesAt), "wave_arrive", {"waveId": wave.id})
	LocalHordes.plan_raids(server, world, wave, since_spawn)
	plan_intercepts(server, world, wave, since_spawn + 1)


# --- Forts, roads and bridges --------------------------------------------------------

static func fort_cost(data: Dictionary, bonuses: Dictionary) -> Dictionary:
	var factor := maxf(0.1, 1.0 + float(bonuses.get("fortCost", 0.0)))
	return LocalVillage.resources(func(kind: String) -> int: return LocalWaves.js_round(float(data.field.fort.cost[kind]) * factor))


## Builds a fort near the village: the fort, or {"error"} / {"missing"}.
static func build_fort(server: LocalServer, world: Dictionary, village: Dictionary, cell: Vector2i, at: int) -> Dictionary:
	var data := server.data
	var rules: Dictionary = data.field.fort
	var distance := HexMath.distance(cell, Vector2i(village.q, village.r))
	if distance == 0 or distance > int(rules.range):
		return LocalVillage.rule("Forts go within %d hexes of the village" % int(rules.range))
	var terrain: Variant = world.hexes.get(LocalLand.key(cell))
	if terrain == null or terrain == "holy_city" or data.terrain.terrain[terrain].moveCost == null:
		return LocalVillage.rule("No fort can stand there")
	if world.villages.any(func(v: Dictionary) -> bool: return int(v.q) == cell.x and int(v.r) == cell.y):
		return LocalVillage.rule("There is a village there")
	for v in world.villages:
		for plot in LocalVillage.outpost_plots(v.state.plots):
			if LocalVillage.outpost_hex(plot) == cell:
				return LocalVillage.rule("There is an outpost there")
	if not fort_at(world, cell).is_empty():
		return LocalVillage.rule("There is a fort there already")
	if not camp_at(world, cell).is_empty():
		return LocalVillage.rule("A camp stands there; clear it first")
	if not site_at(world, cell).is_empty():
		return LocalVillage.rule("An ancient site lies there")
	var ledger := LocalLedger.spend(village.state.ledger, at, fort_cost(data, village.state.bonuses))
	if ledger.has("missing"):
		return ledger
	village.state.ledger = ledger
	var fort := {"id": world.next.fort, "ownerAccountId": village.ownerAccountId, "villageId": village.id, "q": cell.x, "r": cell.y,
		"status": "building", "completesAt": LocalTime.ms(at + (float(rules.buildSeconds) * 1000.0) / world.speed), "mannedAt": null}
	world.next.fort += 1
	world.forts.append(fort)
	server.schedule(world, int(fort.completesAt), "fort_complete", {"fortId": fort.id})
	return fort


static func fort_view(f: Dictionary) -> Dictionary:
	return {"id": f.id, "ownerAccountId": f.ownerAccountId, "villageId": f.villageId, "q": f.q, "r": f.r, "status": f.status,
		"completesAt": LocalTime.iso(f.completesAt)}


static func on_fort_complete(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var fort := find_fort(world, int(event.payload.fortId))
	if fort.is_empty() or fort.status != "building":
		return
	fort.status = "standing"
	_plan_fort_check(server, world, int(fort.id), int(event.dueAt))
	LocalInbox.tell(server, world, fort.ownerAccountId, {"kind": "build_done", "tier": "digest", "title": "Fort at ({q}, {r}) finished",
		"body": "Armies holding it fight from behind its walls.", "vars": {"q": fort.q, "r": fort.r}}, int(event.dueAt))
	changed.append(["world"])


static func _hours_ms(hours: float, world_speed: float) -> float:
	return (hours * LocalTime.MS_PER_HOUR) / world_speed


static func _plan_fort_check(server: LocalServer, world: Dictionary, fort_id: int, from: int) -> void:
	server.schedule(world, LocalTime.ms(from + _hours_ms(float(server.data.camps.fort.abandonHours), world.speed)), "fort_check", {"fortId": fort_id})


## The front whose bandits would take over a fort here.
static func bandit_front(world: Dictionary, cell: Vector2i) -> String:
	var here := LocalMapgen.front_of(cell)
	if here != "north" and here in world.activeFronts:
		return here
	for f in world.activeFronts:
		if f != "north":
			return f
	return world.activeFronts[0] if not world.activeFronts.is_empty() else "south"


static func on_fort_check(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var data := server.data
	var fort := find_fort(world, int(event.payload.fortId))
	if fort.is_empty() or fort.status != "standing":
		return
	var at := int(event.dueAt)
	if not armies_holding(world, Vector2i(fort.q, fort.r), ["stationed", "engaged"]).is_empty():
		fort.mannedAt = at
		_plan_fort_check(server, world, int(fort.id), at)
		return
	var since := int(fort.mannedAt if fort.mannedAt != null else fort.completesAt)
	var abandon_ms := _hours_ms(float(data.camps.fort.abandonHours), world.speed)
	if at - since < abandon_ms:
		server.schedule(world, LocalTime.ms(since + abandon_ms), "fort_check", {"fortId": fort.id})
		return
	# Left empty too long: bandits move in.
	world.forts.erase(fort)
	var front := bandit_front(world, Vector2i(fort.q, fort.r))
	var units := LocalWaves.compose_wave(data, front, 0, int(data.camps.fort.units), int(world.seed) ^ int(fort.id), world.members.size())
	LocalBattles.create_camp(server, world, {"kind": "bandit", "front": front, "q": fort.q, "r": fort.r, "units": units, "waveId": null}, at)
	LocalInbox.tell(server, world, fort.ownerAccountId, {"kind": "camp", "tier": "push", "title": "Bandits took the fort at ({q}, {r})",
		"body": "No army held it, and now it is their camp. Send an army to clear it.", "vars": {"q": fort.q, "r": fort.r}}, at)
	changed.append(["world"])


static func _river_edge(world: Dictionary, a: Vector2i, b: Vector2i) -> Dictionary:
	var key := LocalLand.edge_key(a, b)
	for e in world.rivers:
		if LocalLand.edge_key(e.a, e.b) == key:
			return e
	return {}


static func _road_edge(world: Dictionary, a: Vector2i, b: Vector2i) -> Dictionary:
	var key := LocalLand.edge_key(a, b)
	for e in world.roads:
		if LocalLand.edge_key(e.a, e.b) == key:
			return e
	return {}


## Builds a bridge over a river edge near the village.
static func build_crossing(server: LocalServer, world: Dictionary, village: Dictionary, a: Vector2i, b: Vector2i, at: int) -> Dictionary:
	var rules: Dictionary = server.data.field.bridge
	var home := Vector2i(village.q, village.r)
	if mini(HexMath.distance(a, home), HexMath.distance(b, home)) > int(rules.range):
		return LocalVillage.rule("Bridges go within %d hexes of the village" % int(rules.range))
	var edge := _river_edge(world, a, b)
	if edge.is_empty():
		return LocalVillage.rule("No river runs there")
	# Old maps had rivers along lake shores; a bridge needs land on both banks.
	for end in [a, b]:
		if world.hexes.get(LocalLand.key(end), "") in WATER:
			return LocalVillage.rule("A bridge needs land on both banks")
	if edge.crossing != "none":
		return LocalVillage.rule("A bridge already stands there" if edge.crossing == "standing" else "A bridge is being built there")
	var ledger := LocalLedger.spend(village.state.ledger, at, rules.cost)
	if ledger.has("missing"):
		return ledger
	village.state.ledger = ledger
	var completes_at := LocalTime.ms(at + (float(rules.buildSeconds) * 1000.0) / world.speed)
	edge.crossing = "building"
	edge.builtBy = village.id
	edge.completesAt = completes_at
	server.schedule(world, completes_at, "crossing_built", {"aq": a.x, "ar": a.y, "bq": b.x, "br": b.y})
	return edge


## Builds a road between two neighbouring hexes near the village.
static func build_road(server: LocalServer, world: Dictionary, village: Dictionary, a: Vector2i, b: Vector2i, at: int) -> Dictionary:
	var data := server.data
	var rules: Dictionary = data.field.road
	var home := Vector2i(village.q, village.r)
	if HexMath.distance(a, b) != 1:
		return LocalVillage.rule("A road joins two neighbouring hexes")
	if mini(HexMath.distance(a, home), HexMath.distance(b, home)) > int(rules.range):
		return LocalVillage.rule("Roads go within %d hexes of the village" % int(rules.range))
	for end in [a, b]:
		var type: Variant = world.hexes.get(LocalLand.key(end))
		if type == null or data.terrain.terrain[type].moveCost == null:
			return LocalVillage.rule("No road can run there")
	if LocalHordes.land_of(world).blocked.has(LocalLand.edge_key(a, b)):
		return LocalVillage.rule("A river lies between; build a bridge first")
	if not _road_edge(world, a, b).is_empty():
		return LocalVillage.rule("A road already runs there")
	var ledger := LocalLedger.spend(village.state.ledger, at, rules.cost)
	if ledger.has("missing"):
		return ledger
	village.state.ledger = ledger
	var ends := LocalServer._ordered(a, b)
	var completes_at := LocalTime.ms(at + (float(rules.buildSeconds) * 1000.0) / world.speed)
	var road := {"a": ends[0], "b": ends[1], "status": "building", "builtBy": village.id, "completesAt": completes_at}
	world.roads.append(road)
	server.schedule(world, completes_at, "road_built", {"aq": a.x, "ar": a.y, "bq": b.x, "br": b.y})
	return road


static func on_road_built(_server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var p: Dictionary = event.payload
	var road := _road_edge(world, Vector2i(int(p.aq), int(p.ar)), Vector2i(int(p.bq), int(p.br)))
	if road.is_empty() or road.status != "building":
		return
	road.status = "standing"
	road.completesAt = null
	changed.append(["world"])


## A bridge stands: from now on, roads (and hordes) may cross there.
static func on_crossing_built(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var p: Dictionary = event.payload
	var edge := _river_edge(world, Vector2i(int(p.aq), int(p.ar)), Vector2i(int(p.bq), int(p.br)))
	if edge.is_empty() or edge.crossing != "building":
		return
	var built_by: Variant = edge.builtBy
	edge.crossing = "standing"
	edge.builtBy = null
	edge.completesAt = null
	if built_by != null:
		LocalInbox.tell_owner(server, world, int(built_by), func(name: String) -> Dictionary:
			return {"kind": "build_done", "tier": "digest", "title": "A bridge stands near {village}",
				"body": "Roads now cross the river between ({aq}, {ar}) and ({bq}, {br}), for friend and foe alike.",
				"vars": {"village": name, "aq": int(p.aq), "ar": int(p.ar), "bq": int(p.bq), "br": int(p.br)}}, int(event.dueAt))
	changed.append(["world"])


# --- Storming camps (scheduler/camps.ts, sim/camps.ts) ------------------------------

## An army storms a camp (or a site's guardians): {cleared, rounds, armyNow, campNow}.
static func assault(data: Dictionary, army: Dictionary, army_stats: Callable, army_stance: String, camp: Dictionary, front: String, seed_value: int, id: int) -> Dictionary:
	var camp_stats := LocalBattle.enemy_stats(data, front)
	var stance: String = data.camps.assault.stance
	var army_now := army.duplicate()
	var camp_now := camp.duplicate()
	var rounds: Array = []
	for round in range(1, int(data.battle.maxRounds) + 1):
		var result := LocalBattle.resolve_round(data, {"units": army_now, "stance": army_stance, "stats": army_stats, "home": false},
			{"units": camp_now, "stance": stance, "stats": camp_stats, "home": true}, LocalBattle.battle_rng(seed_value, id + 0x10000, round))
		army_now = LocalCamps.subtract_units(army_now, result.attackerLosses)
		camp_now = LocalCamps.subtract_units(camp_now, result.defenderLosses)
		rounds.append({"round": round, "attackerLosses": result.attackerLosses, "defenderLosses": result.defenderLosses,
			"attackerLeft": LocalBattle.total(army_now), "defenderLeft": LocalBattle.total(camp_now)})
		var outcome := LocalBattle.battle_outcome(data, {"round": round, "attackerStance": army_stance, "attackerInitial": army, "attackerNow": army_now,
			"defenderStance": stance, "defenderInitial": camp, "defenderNow": camp_now})
		# "raided": the defenders (the camp) broke; "defended": the army did.
		if outcome != "ongoing":
			return {"cleared": outcome == "raided", "rounds": rounds, "armyNow": army_now, "campNow": camp_now}
	return {"cleared": false, "rounds": rounds, "armyNow": army_now, "campNow": camp_now}


static func camp_loot(data: Dictionary, units: Dictionary) -> Dictionary:
	var n := LocalBattle.total(units)
	return LocalVillage.resources(func(kind: String) -> int: return LocalWaves.js_round(float(data.camps.loot.perUnit[kind]) * n))


## Records an assault as a finished battle, the enemy as the attacker.
static func _assault_battle(world: Dictionary, fields: Dictionary, result: Dictionary, at: int, end_status: String, loot: Variant) -> Dictionary:
	var battle := LocalBattles.insert_battle(world, fields)
	for i in result.rounds.size():
		var round: Dictionary = result.rounds[i]
		var log := {"round": round.round, "at": LocalTime.iso(at), "attackerLosses": round.defenderLosses, "defenderLosses": round.attackerLosses,
			"attackerLeft": round.defenderLeft, "defenderLeft": round.attackerLeft}
		var last: bool = i == result.rounds.size() - 1
		LocalBattles._record_round(battle, log, {"status": end_status, "at": at, "loot": loot} if last else null)
	return battle


static func _losses(army: Dictionary, army_now: Dictionary) -> Dictionary:
	var lost := {}
	for unit in army.units:
		var n := int(army.units[unit]) - int(army_now.get(unit, 0))
		if n > 0:
			lost[unit] = n
	return lost


## An army sent to clear a camp has arrived: storm it.
static func storm_camp(server: LocalServer, world: Dictionary, army: Dictionary, at: int, changed: Array) -> void:
	var data := server.data
	var camp := camp_at(world, Vector2i(army.targetQ, army.targetR))
	if camp.is_empty():
		send_home(server, world, army, at)
		return
	var home := server.find_village(world, int(army.homeVillageId))
	var hero := hero_with_army(world, int(army.id))
	var bonuses: Dictionary = LocalHeroes.combine(home.state.bonuses, LocalHeroes.hero_bonuses(data, hero)) if not hero.is_empty() else home.state.bonuses
	var result := assault(data, army.units, LocalBattle.player_stats(data, bonuses, false), home.state.stance, camp.units, camp.front, int(world.seed), int(camp.id))
	var battle := _assault_battle(world, {"waveId": null, "campId": camp.id, "villageId": null, "q": camp.q, "r": camp.r,
		"attackerStance": data.camps.assault.stance, "attackerInitial": camp.units, "defenderInitial": army.units, "startedAt": at},
		result, at, "cleared" if result.cleared else "repelled", camp_loot(data, camp.units) if result.cleared else null)
	var after := army_losses(server, world, army, _losses(army, result.armyNow), at)
	var kills := LocalBattle.total(camp.units) - LocalBattle.total(result.campNow)
	var ember := false
	if result.cleared:
		camp.status = "cleared"
		after.loot = camp_loot(data, camp.units)
		# A lair holds an Ember by chance, and always while the bridge lacks one.
		var lucky := LocalWaves.rng_for(int(world.seed), int(camp.id), 0xe3).next() < float(data.camps.loot.emberChance)
		var bridge: Dictionary = world.get("bridge", {})
		var short: bool = not bridge.is_empty() and bridge.status == "open" and int(world.embers) < LocalBridge.embers_wanted(data, bridge)
		ember = camp.kind == "lair" and (lucky or short)
		if ember:
			world.embers = int(world.embers) + 1
		if camp.kind == "lair":
			LocalBattles.bridge_quest(server, world, "lair", at)
		server.onboarding_step(world, int(army.ownerAccountId), "camp", at, changed)
	else:
		camp.units = result.campNow
	if not hero.is_empty():
		if not result.cleared:
			hero.villageId = army.homeVillageId
			hero.armyId = null
		LocalBattles.hero_after_battle(server, world, hero, {"kills": kills, "won": result.cleared, "battleId": battle.id, "at": at})
	send_home(server, world, after, at)
	var where := "%s at (%d, %d)" % ["lair" if camp.kind == "lair" else "bandit camp", int(camp.q), int(camp.r)]
	var body := "{kills} of them fell; {defenders} still hold it."
	if result.cleared:
		body = "It carries home {loot} resources and a Svarog's Ember for the group." if ember else "It carries home {loot} resources."
	LocalInbox.tell(server, world, army.ownerAccountId, {"kind": "battle_result", "tier": "digest",
		"title": "Your army cleared the {where}" if result.cleared else "Your army was driven off from the {where}", "body": body,
		"vars": {"where": where, "loot": int(LocalLogistics.total(camp_loot(data, camp.units))), "kills": kills, "defenders": LocalBattle.total(result.campNow)}}, at)


# --- Ancient sites (scheduler/sites.ts) -----------------------------------------------

## An army sent to explore has reached the site.
static func arrive_at_site(server: LocalServer, world: Dictionary, army: Dictionary, at: int, _changed: Array) -> void:
	var data := server.data
	var site := site_at(world, Vector2i(army.targetQ, army.targetR))
	if site.is_empty() or site.status == "explored":
		send_home(server, world, army, at)
		return
	var explorers := army
	if LocalBattle.total(site.guardians) > 0:
		var home := server.find_village(world, int(army.homeVillageId))
		var hero := hero_with_army(world, int(army.id))
		var bonuses: Dictionary = LocalHeroes.combine(home.state.bonuses, LocalHeroes.hero_bonuses(data, hero)) if not hero.is_empty() else home.state.bonuses
		var result := assault(data, army.units, LocalBattle.player_stats(data, bonuses, false), home.state.stance, site.guardians, "north",
			int(world.seed), int(site.id) + 0x5000)
		var battle := _assault_battle(world, {"waveId": null, "siteId": site.id, "villageId": null, "q": site.q, "r": site.r,
			"attackerStance": data.camps.assault.stance, "attackerInitial": site.guardians, "defenderInitial": army.units, "startedAt": at},
			result, at, "cleared" if result.cleared else "repelled", null)
		explorers = army_losses(server, world, army, _losses(army, result.armyNow), at)
		var kills := LocalBattle.total(site.guardians) - LocalBattle.total(result.campNow)
		site.guardians = {} if result.cleared else result.campNow
		site.guardiansSeen = true
		if not hero.is_empty():
			if not result.cleared:
				hero.villageId = army.homeVillageId
				hero.armyId = null
			LocalBattles.hero_after_battle(server, world, hero, {"kills": kills, "won": result.cleared, "battleId": battle.id, "at": at})
		if not result.cleared or LocalBattle.total(explorers.units) == 0:
			send_home(server, world, explorers, at)
			LocalInbox.tell(server, world, army.ownerAccountId, {"kind": "battle_result", "tier": "digest", "title": "Guardians drove your army from the {where}",
				"body": "{kills} of them fell; {remaining} still watch it.",
				"vars": {"where": data.sites.kinds.get(site.kind, {}).get("name", "site"), "kills": kills, "remaining": LocalBattle.total(result.campNow)}}, at)
			return
	# Search the site.
	explorers.status = "stationed"
	explorers.battleId = null
	var done_at := LocalTime.ms(at + (float(data.sites.kinds[site.kind].exploreHours) * LocalTime.MS_PER_HOUR) / world.speed)
	server.schedule(world, done_at, "site_explored", {"armyId": army.id, "siteId": site.id})


## What a search turned up besides resources: Ember for the world, gear for
## the hero, a scroll for the whole group. The site is marked explored.
static func claim_find(server: LocalServer, world: Dictionary, site: Dictionary, account_id: Variant, hero: Dictionary, find: Dictionary, at: int, changed: Array) -> void:
	match String(find.type):
		"ember":
			world.embers = int(world.embers) + 1
		"gear":
			if not hero.is_empty():
				hero.inventory = hero.inventory + [find.item]
		"scroll":
			world.lore.append({"scroll": find.scroll, "accountId": account_id, "siteId": site.id, "foundAt": at})
			for member in world.members:
				server.refresh_bonuses(world, int(member.accountId), at, changed)
	site.status = "explored"
	site.exploredBy = account_id
	site.find = find
	site.exploredAt = at
	LocalBattles.bridge_quest(server, world, "site", at)
	var data := server.data
	var name: String = data.sites.kinds.get(site.kind, {}).get("name", "site")
	for member in world.members:
		var scroll: bool = find.type == "scroll"
		LocalInbox.tell(server, world, member.accountId, {"kind": "site",
			"tier": "push" if scroll and (account_id == null or int(member.accountId) != int(account_id)) else "digest",
			"title": "The {name} at ({q}, {r}) gave up {find}",
			"body": data.lore.scrolls.get(find.scroll, {}).get("description", "") if scroll else "Explored and done.",
			"vars": {"name": name, "q": site.q, "r": site.r, "find": find_text(data, find)}}, at)


static func find_text(data: Dictionary, find: Dictionary) -> String:
	match String(find.type):
		"resources":
			return "%d resources" % int(LocalLogistics.total(find.resources))
		"gear":
			return data.heroes.items.get(find.item, {}).get("name", find.item)
		"ember":
			return "a Svarog's Ember"
	return "the scroll \"%s\"" % data.lore.scrolls.get(find.scroll, {}).get("name", find.scroll)


static func on_site_explored(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var data := server.data
	var p: Dictionary = event.payload
	var army := find_army(world, int(p.armyId))
	var site: Dictionary = {}
	for s in world.sites:
		if int(s.id) == int(p.siteId):
			site = s
	var at := int(event.dueAt)
	if army.is_empty() or army.status != "stationed" or army.orders != "explore":
		return
	changed.append(["world"])
	if site.is_empty() or site.status == "explored":
		send_home(server, world, army, at)
		return
	var leader := hero_with_army(world, int(army.id))
	var owner_hero: Dictionary = leader if not leader.is_empty() else (hero_of(world, int(army.ownerAccountId)) if army.ownerAccountId != null else {})
	var gear: Array = owner_hero.inventory + owner_hero.gear.values() if not owner_hero.is_empty() else []
	var find := LocalSites.roll_find(data, site.kind, int(world.seed), int(site.id), LocalSites.distance_share(Vector2i(site.q, site.r), int(world.radius)),
		LocalResearch.scrolls(world), gear)
	if find.type == "resources":
		army.loot = find.resources
	claim_find(server, world, site, army.ownerAccountId, owner_hero, find, at, changed)
	send_home(server, world, army, at)


## Recorded army views: on the road or abroad, plus the latest five home.
static func armies_view(world: Dictionary) -> Array:
	var out_now: Array = world.armies.filter(func(a: Dictionary) -> bool: return a.status != "done")
	var done: Array = world.armies.filter(func(a: Dictionary) -> bool: return a.status == "done")
	done.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.returnsAt if a.returnsAt != null else a.arrivesAt) > int(b.returnsAt if b.returnsAt != null else b.arrivesAt))
	var shown: Array = out_now + done.slice(0, 5)
	shown.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.departsAt) > int(b.departsAt) or (int(a.departsAt) == int(b.departsAt) and int(a.id) > int(b.id)))
	return shown.map(army_view)


static func army_view(a: Dictionary) -> Dictionary:
	return {"id": a.id, "ownerAccountId": a.ownerAccountId, "homeVillageId": a.homeVillageId, "targetVillageId": a.targetVillageId,
		"target": [a.targetQ, a.targetR], "heroAccountId": a.heroAccountId, "orders": a.orders, "loot": a.loot, "units": a.units,
		"status": a.status, "battleId": a.battleId, "path": a.path.map(func(s: Dictionary) -> Array: return [s.q, s.r, s.atMs]),
		"departsAt": LocalTime.iso(a.departsAt), "arrivesAt": LocalTime.iso(a.arrivesAt),
		"leavesAt": LocalTime.iso(a.leavesAt) if a.leavesAt != null else null, "returnsAt": LocalTime.iso(a.returnsAt) if a.returnsAt != null else null}
