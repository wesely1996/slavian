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


## Whether a horde fights at a village or marches on it (a battle under way
## there, or a wave marching or fighting with it as its target).
static func horde_against(world: Dictionary, village_id: int) -> bool:
	for b in world.battles:
		if b.status == "ongoing" and b.get("villageId") != null and int(b.villageId) == village_id:
			return true
	for w in world.waves:
		if w.status in ["marching", "battling"] and w.get("targetVillageId") != null and int(w.targetVillageId) == village_id:
			return true
	return false


## sim/armies.ts terrainRelief: how much of harsh terrain's slowness an
## army's pathfinders take off (perUnit each, at most max).
static func terrain_relief(data: Dictionary, units: Dictionary) -> float:
	var relief := 0.0
	var cap := 0.0
	for unit in units:
		var finding: Variant = data.units.units.get(unit, {}).get("pathfinding")
		if finding == null or int(units[unit]) <= 0:
			continue
		relief += float(finding.perUnit) * int(units[unit])
		cap = maxf(cap, float(finding.max))
	return minf(cap, relief)


## Hexes per hour on plains: the slowest unit sets the pace.
## sim/armies.ts armySpeed: wagons that transport troops load siege engines
## first, each wagon taking `engines` of them, then foot soldiers into the
## wagons left, `infantry` a wagon; the slowest ride first. Those riding
## don't set the pace.
static func army_speed(data: Dictionary, units: Dictionary) -> float:
	var walking := {}
	for unit in units:
		if int(units[unit]) > 0:
			walking[unit] = int(units[unit])
	var def := func(u: String) -> Dictionary: return data.units.units.get(u, {})
	var engines: Array = walking.keys().filter(func(u: String) -> bool: return def.call(u).get("engine", false) == true)
	var foot: Array = walking.keys().filter(func(u: String) -> bool: return def.call(u).get("family") == "infantry" and def.call(u).get("engine", false) != true)
	var wagons: Array = walking.keys().filter(func(u: String) -> bool: return def.call(u).get("transports") is Dictionary)
	wagons.sort()
	var infantry_seats := 0
	for wagon in wagons:
		var per_wagon := int(def.call(wagon).transports.engines)
		var count := int(walking[wagon])
		var engines_left := 0
		for u in engines:
			engines_left += int(walking[u])
		var loaded := mini(engines_left, count * per_wagon) if per_wagon > 0 else 0
		_board(data, walking, engines, loaded)
		infantry_seats += (count - (ceili(float(loaded) / per_wagon) if per_wagon > 0 else 0)) * int(def.call(wagon).transports.infantry)
	_board(data, walking, foot, infantry_seats)
	var slowest := INF
	for unit in walking:
		if int(walking[unit]) > 0:
			slowest = minf(slowest, float(data.units.units.get(unit, {}).get("speed", 1)))
	return slowest if slowest != INF else 1.0


## Seats riders in `seats` places, the slowest first; what is left over.
static func _board(data: Dictionary, walking: Dictionary, riders: Array, seats: int) -> int:
	var order := riders.duplicate()
	order.sort_custom(func(a: String, b: String) -> bool:
		var sa := float(data.units.units.get(a, {}).get("speed", 1))
		var sb := float(data.units.units.get(b, {}).get("speed", 1))
		return sa < sb or (sa == sb and a < b))
	for unit in order:
		var riding := mini(seats, int(walking[unit]))
		walking[unit] = int(walking[unit]) - riding
		seats -= riding
	return seats


static func cavalry_share(data: Dictionary, units: Dictionary) -> float:
	var all := LocalBattle.total(units)
	if all == 0:
		return 0.0
	var cavalry := 0
	for unit in units:
		if data.units.units.get(unit, {}).get("family") == "cavalry":
			cavalry += int(units[unit])
	return float(cavalry) / all


## Fighters, and scouts (who never fight, but tell the army what it faces).
static func _marches(data: Dictionary, unit: String, _orders: String) -> bool:
	return not fighters(data, {unit: 1}).is_empty() or data.units.units.get(unit, {}).get("family") == "scout"


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
	# Scouts alone only explore.
	if LocalBattle.total(army) == 0 or (orders != "explore" and LocalBattle.total(fighters(data, army)) == 0):
		return LocalVillage.rule("Send at least one soldier")
	if orders == "harass" and cavalry_share(data, fighters(data, army)) < float(data.armies.harass.minCavalryShare):
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
		"raid":
			# To the map's edge (LocalRaids picks the hex).
			if target_hex == null:
				return LocalVillage.rule("Say where they leave the map")
			to = target_hex
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
			if order.orders == "garrison" and int(target.ownerAccountId) != int(home.ownerAccountId):
				return LocalVillage.rule("Troops only join the garrisons of your own villages")
			# Harassers strike a horde, never a friendly village: only where
			# one fights or marches on it.
			if order.orders == "harass" and not horde_against(world, int(target.id)):
				return LocalVillage.rule("No horde comes against %s to harass" % target.name)
			to = Vector2i(target.q, target.r)
	# The troops leave the garrison with what grain the granary can spare
	# above the village's floor for armies.
	var state := LocalVillage.leave_garrison(data, home.state, units, at, world.speed)
	if state.has("error"):
		return state
	var grain := minf(LocalSupply.full_supply(data, units), village_spare(data, state, at))
	if grain > 0:
		state.ledger = LocalLedger.spend(state.ledger, at, _grain_only(grain))
	var supplied := {"units": units, "supply": grain, "supplyAt": at, "hungrySince": null}
	var speed := army_speed(data, units) * LocalSupply.speed_factor(data, supplied, at, world.speed)
	var path: Variant = LocalLogistics.road_route(data, LocalHordes.land_of(world), Vector2i(home.q, home.r), to, speed, world.speed, terrain_relief(data, units))
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
	var general_id: Variant = null
	if order.get("generalId") != null:
		var general := LocalGenerals.find(world, int(order.generalId))
		if general.is_empty() or int(general.accountId) != int(home.ownerAccountId):
			return LocalVillage.rule("No such general")
		if general.status != "home" or general.villageId == null or int(general.villageId) != int(home.id):
			return LocalVillage.rule("%s is not ready in %s" % [general.name, home.name])
		if home.state.besieged:
			return LocalVillage.rule("%s won't leave in the middle of a battle" % general.name)
		general_id = general.id
	var army := {"id": world.next.army, "ownerAccountId": home.ownerAccountId, "homeVillageId": home.id,
		"targetVillageId": null if order.orders in ["hold", "clear", "explore", "raid"] else order.get("targetVillageId"),
		"targetQ": to.x, "targetR": to.y, "heroAccountId": hero_account, "generalId": general_id, "orders": order.orders,
		"stance": String(order.stance) if order.get("stance") != null else String(home.state.stance), "engagedUnits": null, "units": units, "status": "marching",
		"loot": null, "battleId": null, "joinsRound": null, "joinBonus": 0, "path": path, "departsAt": at, "arrivesAt": at + int(path[-1].atMs),
		"leavesAt": null, "returnsAt": null, "supply": grain, "supplyAt": at, "hungrySince": null, "hungerAt": null, "wagonFortAt": null,
		"returnHome": bool(order.get("returnHome", false)), "quarteredAt": null, "respond": true, "post": null}
	world.next.army += 1
	world.armies.append(army)
	if hero_account != null:
		var hero := hero_of(world, int(hero_account))
		hero.status = "with_army"
		hero.villageId = null
		hero.armyId = army.id
	if general_id != null:
		var general := LocalGenerals.find(world, int(general_id))
		general.status = "with_army"
		general.villageId = null
		general.armyId = army.id
	home.state = state
	server.schedule(world, int(army.arrivesAt), "army_arrive", {"armyId": army.id})
	plan_hunger(server, world, army, at)
	return army


static func _grain_only(grain: float) -> Dictionary:
	return {"wood": 0, "stone": 0, "grain": grain, "iron": 0}


## Whether an army carries its own grain (armies from before are fed by
## their home village).
static func supplied(army: Dictionary) -> bool:
	return army.get("supply") != null and army.get("supplyAt") != null


## Notes when the army's food next needs looking at and schedules it: for
## a quartered army, its place is charged every game hour; one standing at
## a place that can't feed it now tries again every game hour (and goes
## hungry as any other once its own grain is gone); nothing while it eats
## nothing, or carries no supply.
static func plan_hunger(server: LocalServer, world: Dictionary, army: Dictionary, at: int) -> void:
	var next: Variant = null
	if supplied(army):
		var tick := at + LocalQuarters.tick_ms(world.speed)
		if army.get("quarteredAt") != null:
			next = tick
		else:
			next = LocalSupply.next_check(server.data, army, at, world.speed)
			if army.status in ["stationed", "engaged"] and not place_of(server, world, army).is_empty() and (next == null or int(next) > tick):
				next = tick
	army.hungerAt = next
	if next != null:
		server.schedule(world, int(next), "army_hunger", {"armyId": army.id})


## An army setting off pays its quarters, then fills up to its full supply
## from where it stood (down to the place's floor), or leaves behind the
## grain it carries beyond its full supply; either way hunger comes at
## another time, so it is planned again. One sent off from a battle fills
## nothing (the battle keeps the stores).
static func _set_off(server: LocalServer, world: Dictionary, army: Dictionary, at: int) -> void:
	if not supplied(army):
		return
	unquarter(server, world, army, at)
	var place := place_of(server, world, army) if army.status == "stationed" else {}
	if not place.is_empty():
		fill_up(server, world, army, place, at)
	LocalSupply.trim(server.data, army, at, world.speed)
	plan_hunger(server, world, army, at)


## Where an army standing (or fighting) can be fed: {"village": v} for the
## village it stands in, {"store": fort} for the fort or supply point under
## it, {} for none.
static func place_of(server: LocalServer, world: Dictionary, army: Dictionary) -> Dictionary:
	if not army.status in ["stationed", "engaged"]:
		return {}
	if army.targetVillageId != null:
		var village := server.find_village(world, int(army.targetVillageId))
		return {"village": village} if not village.is_empty() and village.get("ruin") == null else {}
	var fort := store_here(world, army)
	return {"store": fort} if not fort.is_empty() else {}


## What grain a village can give armies at `at`: above its floor.
static func village_spare(data: Dictionary, state: Dictionary, at: int) -> float:
	var floor_value := LocalQuarters.settlement_floor(data, state.get("armyFloor"), float(state.ledger.capacity.grain))
	return LocalQuarters.spare_grain(float(LocalLedger.amounts_at(state.ledger, at).grain), floor_value)


static func _place_spare(data: Dictionary, place: Dictionary, at: int) -> float:
	if place.has("village"):
		return village_spare(data, place.village.state, at)
	return LocalQuarters.spare_grain(float(place.store.grain), LocalQuarters.store_floor(place.store.get("armyFloor")))


static func _take_from_place(place: Dictionary, grain: float, at: int) -> void:
	if grain <= 0:
		return
	if place.has("store"):
		place.store.grain = float(place.store.grain) - grain
	else:
		place.village.state.ledger = LocalLedger.spend(place.village.state.ledger, at, _grain_only(grain))


## An army at a place takes on what grain it can carry from its stores,
## down to the place's floor.
static func fill_up(server: LocalServer, world: Dictionary, army: Dictionary, place: Dictionary, at: int) -> void:
	if not supplied(army):
		return
	var grain := minf(LocalSupply.room(server.data, army, at, world.speed), _place_spare(server.data, place, at))
	if grain <= 0:
		return
	_take_from_place(place, grain, at)
	LocalSupply.add(server.data, army, grain, at, world.speed)


## A quartered army's place pays for what it ate since it was last charged,
## down to its floor; a place that could not pay it all feeds it no more
## (from now it eats its own grain). An army no longer at a place is
## unquartered the same way.
static func settle_quarters(server: LocalServer, world: Dictionary, army: Dictionary, at: int) -> void:
	if not supplied(army) or army.get("quarteredAt") == null:
		return
	var place := place_of(server, world, army)
	var owed := LocalQuarters.owed(server.data, army.units, int(army.quarteredAt), at, world.speed)
	var paid := minf(owed, _place_spare(server.data, place, at)) if not place.is_empty() else 0.0
	if not place.is_empty():
		_take_from_place(place, paid, at)
	LocalSupply.settle(server.data, army, at, world.speed)
	army.quarteredAt = at if not place.is_empty() and paid >= owed - 1e-9 else null


## An army standing at a place with grain to spare is quartered there.
static func quarter(server: LocalServer, world: Dictionary, army: Dictionary, at: int) -> void:
	if not supplied(army) or army.get("quarteredAt") != null:
		return
	var place := place_of(server, world, army)
	if place.is_empty() or _place_spare(server.data, place, at) <= 0:
		return
	LocalSupply.settle(server.data, army, at, world.speed)
	army.quarteredAt = at
	army.hungrySince = null


## An army leaving where it stood pays what it owes and eats its own grain from now.
static func unquarter(server: LocalServer, world: Dictionary, army: Dictionary, at: int) -> void:
	if army.get("quarteredAt") == null:
		return
	settle_quarters(server, world, army, at)
	army.quarteredAt = null


## The grain a fort or supply point keeps at most.
static func grain_capacity(data: Dictionary, kind: String) -> float:
	return float(data.field.supplyPoint.grainCapacity if kind == "supply" else data.field.fort.grainCapacity)


## The standing fort or supply point an army stands on, out in the field ({} if none).
static func store_here(world: Dictionary, army: Dictionary) -> Dictionary:
	if army.targetVillageId != null or not army.status in ["stationed", "engaged"]:
		return {}
	var fort := fort_at(world, Vector2i(army.targetQ, army.targetR))
	return fort if not fort.is_empty() and fort.status == "standing" else {}


## A standing army on a fort or supply point leaves up to `grain` of its own
## supply in its stores: the army, or {"error"}.
static func store_command(server: LocalServer, world: Dictionary, army: Dictionary, body: Dictionary, at: int) -> Dictionary:
	var data := server.data
	var grain: Variant = body.get("grain")
	if not (grain is int or grain is float) or float(grain) != floorf(float(grain)) or float(grain) < 1 or float(grain) > 1000000:
		return {"error": "Say how much grain to leave", "kind": "invalid"}
	var refused := _standing(army)
	if not refused.is_empty():
		return refused
	var store := store_here(world, army)
	if store.is_empty():
		return LocalVillage.rule("They stand on no fort or supply point")
	if not supplied(army):
		return LocalVillage.rule("Their village feeds them")
	var room := grain_capacity(data, store.get("kind", "fort")) - float(store.grain)
	if room <= 0:
		return LocalVillage.rule("Its stores are full")
	var amount := minf(minf(float(grain), LocalSupply.supply_left(data, army, at, world.speed)), room)
	if amount <= 0:
		return LocalVillage.rule("They have no grain to spare")
	LocalSupply.settle(data, army, at, world.speed)
	store.grain = float(store.grain) + amount
	army.supply = float(army.supply) - amount
	plan_hunger(server, world, army, at)
	return army


## An army ends in a village of its owner: the troops join the garrison,
## what grain and loot it carries go into the stores, and whoever led it
## stays there.
static func join_village(server: LocalServer, world: Dictionary, army: Dictionary, village_id: int, at: int) -> void:
	var data := server.data
	# Quartered where it stood (perhaps this very village): that is paid first.
	unquarter(server, world, army, at)
	var village := server.find_village(world, village_id)
	var state := LocalVillage.complete_training(village.state, at)
	if supplied(army):
		state = LocalVillage.join_garrison(data, state, army.units, at, world.speed)
		# Its grain and loot into the stores.
		var loot: Variant = army.loot
		var carried := LocalSupply.supply_left(data, army, at, world.speed)
		var load := LocalVillage.resources(func(kind: String) -> float:
			return (float(loot.get(kind, 0)) if loot != null else 0.0) + (carried if kind == "grain" else 0.0))
		state.ledger = LocalLogistics.receive(state.ledger, at, load).ledger
		village.state = state
		army.status = "done"
		army.loot = null
		army.supply = 0
		army.supplyAt = at
		army.hungerAt = null
	else:
		# An army from before supplies, coming home: its village fed it.
		for unit in army.units:
			state = LocalVillage.return_home(data, state, unit, int(army.units[unit]), at, world.speed)
		village.state = state
		army.status = "done"
		if army.loot != null:
			village.state.ledger = LocalLogistics.receive(village.state.ledger, at, army.loot).ledger
			army.loot = null
	var hero := hero_with_army(world, int(army.id))
	if not hero.is_empty():
		hero.status = "home"
		hero.villageId = village.id
		hero.armyId = null
	var general := LocalGenerals.general_with_army(world, int(army.id))
	if not general.is_empty():
		general.status = "home"
		general.villageId = village.id
		general.armyId = null


## An army done with its errand stands on the hex it reached, holding it.
static func hold_hex(server: LocalServer, world: Dictionary, army: Dictionary, at: int) -> void:
	# Told to come home once done, it does.
	if not stays_out(world, army):
		send_home(server, world, army, at)
		return
	army.status = "stationed"
	army.orders = "hold"
	army.targetVillageId = null
	army.battleId = null
	intercept_at(server, world, Vector2i(army.targetQ, army.targetR), at)


## scheduler/armies.ts staysOut: whether an army done with its errand stays
## where it is: always, unless told to come home once done; and even then
## while it guards a shipyard whose boat isn't finished.
static func stays_out(world: Dictionary, army: Dictionary) -> bool:
	if not army.get("returnHome", false):
		return true
	if army.targetVillageId != null:
		return false
	for s in world.get("shipyards", []):
		if int(s.q) == int(army.targetQ) and int(s.r) == int(army.targetR) and s.status != "done":
			return true
	return false


## scheduler/armies.ts setReturnHome: whether an army comes home by itself
## once its errand is done; switched on for one standing with its errand
## done, it turns home now.
static func set_return_home(server: LocalServer, world: Dictionary, army_id: int, on: bool, at: int) -> Dictionary:
	var army := find_army(world, army_id)
	if army.is_empty():
		return {"error": "No such army", "kind": "not_found"}
	if army.status == "returning" or army.status == "done":
		return LocalVillage.rule("They are already on their way home")
	if not String(army.orders) in ["support", "hold", "clear", "explore"]:
		return LocalVillage.rule("They come home by themselves")
	army.returnHome = on
	if on and army.status == "stationed" and army.orders != "explore" and not stays_out(world, army):
		send_home(server, world, army, at)
	return army


## An army lost for good (starved): the hero carried home wounded, the
## general dead.
static func end_army(server: LocalServer, world: Dictionary, army: Dictionary, at: int) -> void:
	army.units = {}
	army.status = "done"
	army.battleId = null
	army.leavesAt = at
	army.returnsAt = at
	army.hungerAt = null
	send_home(server, world, army, at)


static func _standing(army: Dictionary) -> Dictionary:
	if army.status == "engaged":
		return LocalVillage.rule("That army is in the middle of a battle")
	if army.status != "stationed":
		return LocalVillage.rule("Only armies standing still can be given these orders")
	return {}


## Where a standing army goes next: a hex to hold, or a village.
static func move(server: LocalServer, world: Dictionary, army: Dictionary, body: Dictionary, at: int) -> Dictionary:
	var data := server.data
	# An army on the road can be turned too (not one in a battle).
	var on_the_road: bool = army.status in ["marching", "returning"]
	var refused := {} if on_the_road else _standing(army)
	if not refused.is_empty():
		return refused
	var here := Vector2i(army.targetQ, army.targetR)
	var dest: Vector2i
	var orders := "hold"
	var target_village: Variant = null
	if body.get("villageId") != null:
		var village := server.find_village(world, int(body.villageId))
		if village.is_empty():
			return LocalVillage.rule("No such village in this world")
		dest = Vector2i(village.q, village.r)
		# Its owner's: it joins the garrison unless `join` is false (then it
		# stands there as an army); `orders` overrides (answering a battle).
		if body.get("orders") != null:
			orders = String(body.orders)
		else:
			orders = "garrison" if village.ownerAccountId != null and int(village.ownerAccountId) == int(army.ownerAccountId) and body.get("join") != false else "support"
		target_village = village.id
	else:
		var target: Variant = body.get("target")
		if not target is Dictionary:
			return LocalVillage.rule("Say where they should go")
		dest = Vector2i(int(target.q), int(target.r))
		var terrain: Variant = world.hexes.get(LocalLand.key(dest))
		if terrain == null or data.terrain.terrain[terrain].moveCost == null:
			return LocalVillage.rule("No army can stand there")
		if world.villages.any(func(v: Dictionary) -> bool: return int(v.q) == dest.x and int(v.r) == dest.y):
			return LocalVillage.rule("That is a village; send them into it")
		# Sent onto a camp it storms it; onto a site not yet searched, it explores.
		if body.get("orders") != null:
			orders = String(body.orders)
		elif not camp_at(world, dest).is_empty():
			if LocalBattle.total(LocalScouting.combatants(data, army.units)) == 0:
				return LocalVillage.rule("Scouts alone don't storm camps")
			orders = "clear"
		else:
			var site := site_at(world, dest)
			if not site.is_empty() and site.status != "explored":
				orders = "explore"
	if not on_the_road and dest == here:
		if orders == "garrison":
			join_village(server, world, army, int(target_village), at)
			return army
		return LocalVillage.rule("They are already there")
	var land := LocalHordes.land_of(world)
	var path: Variant
	var departs_at := at
	if on_the_road:
		# It finishes the hex it is crossing, then takes the new road; the road
		# it came by stays (one coming home turns on that road, backwards).
		var speed := army_speed(data, army.units) * LocalSupply.speed_factor(data, army if supplied(army) else null, at, world.speed)
		var road: Array = LocalLogistics.reversed_route(army.path) if army.status == "returning" else army.path
		departs_at = int(army.leavesAt) if army.status == "returning" else int(army.departsAt)
		path = LocalLogistics.splice_route(road, at - departs_at, func(from: Vector2i) -> Variant:
			return LocalLogistics.road_route(data, land, from, dest, speed, world.speed, terrain_relief(data, army.units)))
	else:
		_set_off(server, world, army, at)
		var speed := army_speed(data, army.units) * LocalSupply.speed_factor(data, army if supplied(army) else null, at, world.speed)
		path = LocalLogistics.road_route(data, land, here, dest, speed, world.speed, terrain_relief(data, army.units))
	if path == null:
		return LocalVillage.rule("No road leads there")
	army.orders = orders
	army.targetVillageId = target_village
	army.targetQ = dest.x
	army.targetR = dest.y
	army.path = path
	army.status = "marching"
	army.battleId = null
	army.wagonFortAt = null
	army.departsAt = departs_at
	army.arrivesAt = departs_at + int(path[-1].atMs)
	army.leavesAt = null
	army.returnsAt = null
	server.schedule(world, int(army.arrivesAt), "army_arrive", {"armyId": army.id})
	return army


## A standing army disbanded: its troops go home to their farms, and
## whoever led it makes their own way home.
static func disband(server: LocalServer, world: Dictionary, army: Dictionary, at: int) -> Dictionary:
	var data := server.data
	var refused := _standing(army)
	if not refused.is_empty():
		return refused
	# Quartered, its place is paid for what it ate till now.
	unquarter(server, world, army, at)
	var home := server.find_village(world, int(army.homeVillageId))
	var land := LocalHordes.land_of(world)
	var here := Vector2i(army.targetQ, army.targetR)
	army.units = {}
	army.status = "done"
	army.battleId = null
	army.leavesAt = at
	army.returnsAt = at
	army.hungerAt = null
	var hero := hero_with_army(world, int(army.id))
	if not hero.is_empty():
		var path: Variant = LocalLogistics.road_route(data, land, here, Vector2i(home.q, home.r), float(data.heroes.speed) * LocalHeroes.hero_factor(data, hero.kind, "heroSpeed"), world.speed)
		var arrives_at := at + int(path[-1].atMs)
		hero.status = "traveling"
		hero.villageId = home.id
		hero.armyId = null
		hero.path = path
		hero.departsAt = LocalTime.iso(at)
		hero.arrivesAt = LocalTime.iso(arrives_at)
		server.schedule(world, arrives_at, "hero_arrive", {"accountId": hero.accountId})
	var general := LocalGenerals.general_with_army(world, int(army.id))
	if not general.is_empty():
		var path: Variant = LocalLogistics.road_route(data, land, here, Vector2i(home.q, home.r), float(data.heroes.generals.speed), world.speed)
		general.status = "traveling"
		general.villageId = home.id
		general.armyId = null
		general.path = path
		general.departsAt = at
		general.until = at + int(path[-1].atMs)
		server.schedule(world, int(general.until), "general_arrive", {"generalId": general.id})
	return army


## A standing army in a village, or on a fort or supply point, takes on
## what grain it can carry from its stores, down to the place's floor.
static func resupply_command(server: LocalServer, world: Dictionary, army: Dictionary, at: int) -> Dictionary:
	var refused := _standing(army)
	if not refused.is_empty():
		return refused
	var place := place_of(server, world, army)
	if place.is_empty():
		return LocalVillage.rule("They stand in no village, fort or supply point")
	if not supplied(army):
		return LocalVillage.rule("Their village feeds them")
	fill_up(server, world, army, place, at)
	plan_hunger(server, world, army, at)
	return army


## Out of food: the army loses men, or is lost altogether. Quartered, its
## place pays for the hour (or can't, and it eats its own from now);
## standing at a place with grain again, it is quartered.
static func on_army_hunger(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var army := find_army(world, int(event.payload.armyId))
	var at := int(event.dueAt)
	if army.is_empty() or not supplied(army) or army.status == "done" or army.get("hungerAt") == null or int(army.hungerAt) != at:
		return
	changed.append(["world"])
	var data := server.data
	if army.get("quarteredAt") != null:
		settle_quarters(server, world, army, at)
	else:
		quarter(server, world, army, at)
	if army.get("quarteredAt") != null:
		plan_hunger(server, world, army, at)
		return
	var strike := LocalSupply.strikes(data, army, at, world.speed)
	var home := server.find_village(world, int(army.homeVillageId))
	var name: String = home.name if not home.is_empty() else ""
	if not strike.lost:
		army_losses(server, world, army, strike.losses, at, false)
	if strike.lost or LocalBattle.total(army.units) == 0:
		end_army(server, world, army, at)
		LocalInbox.tell(server, world, army.ownerAccountId, {"kind": "battle_result", "tier": "push", "title": "An army from {village} starved",
			"body": "With no food left it scattered; none of them will come back.", "vars": {"village": name}}, at)
	else:
		plan_hunger(server, world, army, at)


## Turns an army for home along the road it came. An army with no one left
## is done; its hero is carried home wounded, and its general is dead.
static func send_home(server: LocalServer, world: Dictionary, army: Dictionary, at: int) -> Dictionary:
	if LocalBattle.total(army.units) == 0:
		army.status = "done"
		army.battleId = null
		army.leavesAt = at
		army.returnsAt = at
		var hero := hero_with_army(world, int(army.id))
		if not hero.is_empty():
			var wounded_until := at + LocalHeroes.wound_ms(server.data, world.speed, hero.kind, LocalGenerals.hall_level_at(server, world, army.homeVillageId))
			hero.status = "wounded"
			hero.villageId = army.homeVillageId
			hero.armyId = null
			hero.woundedUntil = LocalTime.iso(wounded_until)
			server.schedule(world, wounded_until, "hero_recover", {"accountId": hero.accountId})
		var general := LocalGenerals.general_with_army(world, int(army.id))
		if not general.is_empty():
			LocalGenerals.kill(server, world, general, at)
		return army
	_set_off(server, world, army, at)
	# An army that moved on from where it first went takes the road home from
	# where it stands (drawn backwards, as every road home is).
	var home := server.find_village(world, int(army.homeVillageId))
	if not home.is_empty() and (int(army.path[0].q) != int(home.q) or int(army.path[0].r) != int(home.r)):
		var speed := army_speed(server.data, army.units) * LocalSupply.speed_factor(server.data, army if supplied(army) else null, at, world.speed)
		army.path = LocalLogistics.road_route(server.data, LocalHordes.land_of(world), Vector2i(home.q, home.r), Vector2i(army.targetQ, army.targetR), speed, world.speed, terrain_relief(server.data, army.units))
	army.status = "returning"
	army.battleId = null
	army.wagonFortAt = null
	army.leavesAt = at
	army.returnsAt = at + int(army.path[-1].atMs)
	server.schedule(world, int(army.returnsAt), "army_return", {"armyId": army.id})
	return army


## An army joins the battle at its target village from the next round.
static func join_battle(server: LocalServer, world: Dictionary, army: Dictionary, battle: Dictionary, wave: Dictionary, at: int) -> void:
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
	# Kept as the server keeps it (a Postgres real).
	var bonus := pg_real(join_bonus(server.data, army.orders, LocalBattle.total(army.units), LocalBattle.total(wave.composition), angle))
	army.status = "engaged"
	army.battleId = battle.id
	army.joinsRound = int(battle.round) + 1
	army.joinBonus = bonus
	army.engagedUnits = army.units.duplicate()
	plan_hunger(server, world, army, at)
	_add_defenders(battle, LocalScouting.combatants(server.data, army.units))


## A number as a Postgres `real` column gives it back: rounded to single
## precision, printed in the fewest digits that read back the same.
static func pg_real(value: float) -> float:
	var single: float = PackedFloat32Array([value])[0]
	if single == 0.0:
		return 0.0
	var exponent := floori(log(absf(single)) / log(10.0))
	for digits in range(1, 10):
		var scale := pow(10.0, digits - 1 - exponent)
		var candidate := roundf(single * scale) / scale
		if PackedFloat32Array([candidate])[0] == single:
			return candidate
	return single


static func _add_defenders(battle: Dictionary, units: Dictionary) -> void:
	var sum: Dictionary = battle.defenderInitial.duplicate()
	for unit in units:
		sum[unit] = int(sum.get(unit, 0)) + int(units[unit])
	battle.defenderInitial = sum


## A battle starts at a village: armies standing there join at once, and
## armies standing nearby answer it.
static func rally_to_battle(server: LocalServer, world: Dictionary, battle: Dictionary, village: Dictionary, at: int) -> void:
	for army in armies_at(world, int(village.id), ["stationed"]):
		army.status = "engaged"
		army.battleId = battle.id
		army.joinsRound = 1
		army.joinBonus = 0
		army.engagedUnits = army.units.duplicate()
		_add_defenders(battle, LocalScouting.combatants(server.data, army.units))
	answer_battle(server, world, Vector2i(village.q, village.r), village.id, at)


## Standing armies that answer a battle at `cell`: every army standing
## within respond.range hexes of it (not there already) that fights and was
## not told to stay out (oldest first).
static func responders_to(data: Dictionary, world: Dictionary, cell: Vector2i) -> Array:
	var found := []
	for a in _by_id(world.armies):
		if a.status != "stationed" or not a.get("respond", true) or a.orders == "explore":
			continue
		var at_hex := Vector2i(int(a.targetQ), int(a.targetR))
		if at_hex == cell or HexMath.distance(at_hex, cell) > int(data.armies.respond.range):
			continue
		if LocalBattle.total(LocalScouting.combatants(data, a.units)) == 0:
			continue
		found.append(a)
	return found


## Armies standing nearby march to a battle that started at `cell` (a
## village's, or on open ground), remembering where they stood: they go
## back once it is over.
static func answer_battle(server: LocalServer, world: Dictionary, cell: Vector2i, village_id: Variant, at: int) -> void:
	for army in responders_to(server.data, world, cell):
		var post := {"q": int(army.targetQ), "r": int(army.targetR), "villageId": army.targetVillageId}
		var body := {"villageId": village_id, "orders": "reinforce"} if village_id != null else {"target": {"q": cell.x, "r": cell.y}, "orders": "hold"}
		# No road there: it can't help.
		if not _try_move(server, world, army, body, at):
			continue
		army.post = post


## Moves an army, or (refused) leaves it and the stores where it stands as
## they were, as the server's savepoint does. Whether it moved.
static func _try_move(server: LocalServer, world: Dictionary, army: Dictionary, body: Dictionary, at: int) -> bool:
	var before := army.duplicate(true)
	var place := place_of(server, world, army)
	var ledger: Variant = place.village.state.ledger.duplicate(true) if place.has("village") else null
	var grain: Variant = place.store.grain if place.has("store") else null
	if not move(server, world, army, body, at).has("error"):
		return true
	army.merge(before, true)
	if ledger != null:
		place.village.state.ledger = ledger
	if grain != null:
		place.store.grain = grain
	return false


## The ongoing battle with a horde on open ground at a hex ({} if none).
static func field_battle_at(world: Dictionary, cell: Vector2i) -> Dictionary:
	for b in world.battles:
		if b.get("villageId") == null and b.get("waveId") != null and b.status == "ongoing" and int(b.q) == cell.x and int(b.r) == cell.y:
			return b
	return {}


## An army done with a battle it went to: one that answered it goes back to
## where it stood; any other goes home.
static func after_battle(server: LocalServer, world: Dictionary, army: Dictionary, at: int) -> void:
	if army.get("post") == null or LocalBattle.total(army.units) == 0:
		send_home(server, world, army, at)
		return
	var post: Dictionary = army.post
	army.status = "stationed"
	army.battleId = null
	army.joinsRound = null
	army.joinBonus = 0
	army.post = null
	if int(army.targetQ) == int(post.q) and int(army.targetR) == int(post.r):
		quarter(server, world, army, at)
		plan_hunger(server, world, army, at)
		return
	var body := {"villageId": post.villageId, "join": false} if post.villageId != null else {"target": {"q": int(post.q), "r": int(post.r)}, "orders": "hold"}
	if not _try_move(server, world, army, body, at):
		# Where it stood is gone (or out of reach): it goes home.
		send_home(server, world, army, at)


## Losses an army took: its supply is settled first (the dead stop eating),
## or, for an army from before supplies, its home village stops feeding them.
static func army_losses(server: LocalServer, world: Dictionary, army: Dictionary, fallen: Dictionary, at: int, wounds := true) -> Dictionary:
	if LocalBattle.total(fallen) == 0:
		return army
	# Shamans with the army put some of those who fell in battle back on
	# their feet (not the starving).
	var chance := LocalVillage.healer_chance(server.data, army.units) if wounds else 0.0
	var healed := LocalVillage.heal_fallen(chance, fallen,
		LocalRng.new((int(world.seed) ^ LocalRng.imul(int(army.id) + 1, 0x632be5ab) ^ (floori(at / 60000.0) & 0xfffff)) & 0xffffffff))
	var losses := {}
	for unit in fallen:
		var n := int(fallen[unit]) - int(healed.get(unit, 0))
		if n > 0:
			losses[unit] = n
	if LocalBattle.total(losses) == 0:
		return army
	# Quartered, its place is paid for what the fallen ate till now.
	settle_quarters(server, world, army, at)
	if supplied(army):
		LocalSupply.settle(server.data, army, at, world.speed)
	else:
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
	# Turned on the road since: a later arrival is planned.
	if army.is_empty() or army.status != "marching" or int(army.arrivesAt) != int(event.dueAt):
		return
	var at := int(event.dueAt)
	changed.append(["world"])
	match String(army.orders):
		"raid":
			LocalRaids.reach_edge(server, world, army, at)
			return
		"explore":
			arrive_at_site(server, world, army, at, changed)
			return
		"clear":
			storm_camp(server, world, army, at, changed)
			return
		"hold":
			# Told to come home once there (and not guarding a shipyard), it turns back.
			if not stays_out(world, army):
				send_home(server, world, army, at)
				return
			var fort := fort_at(world, Vector2i(army.targetQ, army.targetR))
			if not fort.is_empty():
				fort.mannedAt = at
			# On a fort or supply point it is quartered there.
			army.status = "stationed"
			quarter(server, world, army, at)
			# A battle on the hex: it joins it from the next round.
			var battle := field_battle_at(world, Vector2i(army.targetQ, army.targetR))
			if not battle.is_empty():
				join_battle(server, world, army, battle, server.find_wave(world, int(battle.waveId)), at)
			else:
				plan_hunger(server, world, army, at)
			intercept_at(server, world, Vector2i(army.targetQ, army.targetR), at)
			return
	if army.orders == "garrison":
		join_village(server, world, army, int(army.targetVillageId), at)
		return
	# Any village it reaches quarters it.
	army.status = "stationed"
	quarter(server, world, army, at)
	var ongoing: Dictionary = {}
	for b in world.battles:
		if b.villageId != null and int(b.villageId) == int(army.targetVillageId) and b.status == "ongoing":
			ongoing = b
			break
	if not ongoing.is_empty() and ongoing.waveId != null:
		join_battle(server, world, army, ongoing, server.find_wave(world, int(ongoing.waveId)), at)
	elif army.orders == "support" and not army.get("returnHome", false):
		plan_hunger(server, world, army, at)
	else:
		after_battle(server, world, army, at)


static func on_army_return(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var army := find_army(world, int(event.payload.armyId))
	if army.is_empty() or army.status != "returning" or army.returnsAt == null or int(army.returnsAt) != int(event.dueAt):
		return
	# The troops join the garrison; loot and what grain is left go into the stores.
	join_village(server, world, army, int(army.homeVillageId), int(event.dueAt))
	changed.append(["village", army.homeVillageId])
	changed.append(["world"])


# --- Commands (commands/armies.ts) -----------------------------------------------------

static func send_army(server: LocalServer, world: Dictionary, village: Dictionary, body: Dictionary, now: int) -> Dictionary:
	var target: Variant = body.get("target")
	var units: Variant = body.get("units")
	if not units is Dictionary or not String(body.get("orders", "")) in ["support", "reinforce", "harass", "hold", "clear", "explore", "garrison"]:
		return {"error": "Give the army its units and orders", "kind": "invalid"}
	if body.get("stance") != null and not String(body.stance) in server.data.battle.stances:
		return {"error": "Unknown stance", "kind": "invalid"}
	return dispatch_army(server, world, {"homeVillageId": village.id, "targetVillageId": body.get("targetVillageId"),
		"targetHex": Vector2i(int(target.q), int(target.r)) if target is Dictionary else null, "units": units, "orders": body.orders,
		"withHero": body.get("withHero", false), "generalId": body.get("generalId"), "stance": body.get("stance"),
		"returnHome": body.get("returnHome", false) == true, "at": now})


## commands/armies.ts armyStanceCommand: an army's battle stance; not in the
## middle of a battle.
static func set_stance(world: Dictionary, army_id: int, stance: String) -> Dictionary:
	var army := find_army(world, army_id)
	if army.is_empty():
		return {"error": "No such army", "kind": "not_found"}
	if army.status == "engaged":
		return LocalVillage.rule("That army is in the middle of a battle")
	if army.status == "returning" or army.status == "done":
		return LocalVillage.rule("Only armies out in the field take a stance")
	army.stance = stance
	return army


## Calls an army standing guard or holding a hex home.
static func recall(server: LocalServer, world: Dictionary, army_id: int, now: int) -> Dictionary:
	var army := find_army(world, army_id)
	if army.is_empty():
		return {"error": "No such army", "kind": "not_found"}
	if army.status == "engaged":
		return LocalVillage.rule("That army is in the middle of a battle")
	if army.status == "returning":
		return LocalVillage.rule("They are already on their way home")
	# One on the march turns for home where it is, into the garrison.
	if army.status == "marching":
		return move(server, world, army, {"villageId": army.homeVillageId}, now)
	if army.status != "stationed":
		return LocalVillage.rule("Only armies out in the field can be called home")
	return send_home(server, world, army, now)


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


## Whether a unit is a wagon (a Military Caravan), not a soldier.
static func is_wagon(data: Dictionary, unit: String) -> bool:
	return data.units.units.get(unit, {}).get("wagon", false) == true


static func wagons_in(data: Dictionary, units: Dictionary) -> int:
	var n := 0
	for unit in units:
		if is_wagon(data, unit):
			n += int(units[unit])
	return n


## The defense a wagon fort gives the armies holding a hex (field.json
## wagonFort): the wagons of those whose ring stands ready by `at`, for
## each `menPerWagon` soldiers of them all, at most `maxBonus`.
static func wagon_fort_bonus(data: Dictionary, holders: Array, at: int) -> float:
	var rules: Dictionary = data.field.wagonFort
	var wagons := 0
	var soldiers := 0
	for army in holders:
		var n := wagons_in(data, army.units)
		if army.get("wagonFortAt") != null and int(army.wagonFortAt) <= at:
			wagons += n
		for unit in army.units:
			soldiers += int(army.units[unit])
		soldiers -= n
	if wagons == 0:
		return 0.0
	return minf(float(rules.maxBonus), (float(rules.bonusPerWagon) * wagons) / maxf(1.0, ceilf(soldiers / float(rules.menPerWagon))))


## A standing army holding open ground draws its wagons into a ring: a
## wagon fort, ready after field.json wagonFort.setupMinutes (game
## minutes), until it moves.
static func circle_wagons(server: LocalServer, world: Dictionary, army: Dictionary, at: int) -> Dictionary:
	var refused := _standing(army)
	if not refused.is_empty():
		return refused
	if army.orders != "hold" or army.targetVillageId != null:
		return LocalVillage.rule("Only an army holding open ground circles its wagons")
	if wagons_in(server.data, army.units) == 0:
		return LocalVillage.rule("They have no wagons")
	if army.get("wagonFortAt") != null:
		return LocalVillage.rule("Their wagons are already in a ring")
	if not fort_at(world, Vector2i(army.targetQ, army.targetR)).is_empty():
		return LocalVillage.rule("There is a fort or supply point there already")
	army.wagonFortAt = at + LocalWaves.js_round((float(server.data.field.wagonFort.setupMinutes) * 60000.0) / world.speed)
	return army


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
	# Another horde already fighting there: it joins that battle.
	if LocalBattles.join_horde_battle(server, world, wave, Vector2i(int(p.q), int(p.r)), int(event.dueAt)):
		changed.append(["world"])
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
	var setup := setup_at(data, world.hexes, cell, ready_since, at, world.speed, not fort.is_empty() and fort.status == "standing" and fort.get("kind", "fort") == "fort",
		LocalBattles.came_over_river(wave.path if wave.path != null else [], cell, rivers))
	var ring := wagon_fort_bonus(data, holders, at)
	if ring > 0:
		setup.wagonFort = ring
	wave.status = "battling"
	var defenders := {}
	for a in holders:
		defenders = LocalCamps.add_units(defenders, LocalScouting.combatants(data, a.units))
	var battle := LocalBattles.insert_battle(world, {"waveId": wave.id, "villageId": null, "q": cell.x, "r": cell.y, "setup": setup,
		"attackerStance": wave.stance, "attackerInitial": wave.composition, "defenderInitial": defenders, "startedAt": at})
	for army in holders:
		army.status = "engaged"
		army.battleId = battle.id
		army.joinsRound = 1
		army.joinBonus = 0
		army.engagedUnits = army.units.duplicate()
	# Armies standing nearby answer it.
	answer_battle(server, world, cell, null, at)
	server.schedule(world, at + LocalBattle.round_ms(data, world.speed), "battle_round", {"battleId": battle.id})
	var ground: Array = []
	for pair in [["ambush", "an ambush"], ["choke", "a choke point"], ["fort", "a fort"], ["wagonFort", "a wagon fort"], ["river", "a river crossing"]]:
		if setup.get(pair[0], false):
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
		return not (e.status == "pending" and e.type in ["outpost_raid", "supply_raid", "field_intercept"] and int(e.payload.get("waveId", -1)) == int(wave.id)))
	server.schedule(world, int(late.arrivesAt), "wave_arrive", {"waveId": wave.id})
	LocalHordes.plan_raids(server, world, wave, since_spawn)
	plan_intercepts(server, world, wave, since_spawn + 1)


# --- Forts, roads and bridges --------------------------------------------------------

static func fort_cost(data: Dictionary, bonuses: Dictionary) -> Dictionary:
	var factor := maxf(0.1, 1.0 + float(bonuses.get("fortCost", 0.0)))
	return LocalVillage.resources(func(kind: String) -> int: return LocalWaves.js_round(float(data.field.fort.cost[kind]) * factor))


## Builds a fort (or a supply point) near the village: the fort, or
## {"error"} / {"missing"}.
static func build_fort(server: LocalServer, world: Dictionary, village: Dictionary, cell: Vector2i, at: int, kind := "fort") -> Dictionary:
	var data := server.data
	var rules: Dictionary = data.field.supplyPoint if kind == "supply" else data.field.fort
	var what := "supply point" if kind == "supply" else "fort"
	var distance := HexMath.distance(cell, Vector2i(village.q, village.r))
	if distance == 0 or distance > int(rules.range):
		return LocalVillage.rule(("Supply points go within %d hexes of the village" if kind == "supply" else "Forts go within %d hexes of the village") % int(rules.range))
	var terrain: Variant = world.hexes.get(LocalLand.key(cell))
	if terrain == null or terrain == "holy_city" or data.terrain.terrain[terrain].moveCost == null:
		return LocalVillage.rule("No %s can stand there" % what)
	if world.villages.any(func(v: Dictionary) -> bool: return int(v.q) == cell.x and int(v.r) == cell.y):
		return LocalVillage.rule("There is a village there")
	for v in world.villages:
		for plot in LocalVillage.outpost_plots(v.state.plots):
			if LocalVillage.outpost_hex(plot) == cell:
				return LocalVillage.rule("There is an outpost there")
	var there := fort_at(world, cell)
	if not there.is_empty():
		return LocalVillage.rule("There is a supply point there already" if there.get("kind", "fort") == "supply" else "There is a fort there already")
	if not camp_at(world, cell).is_empty():
		return LocalVillage.rule("A camp stands there; clear it first")
	if site_at(world, cell).get("status") == "unexplored":
		return LocalVillage.rule("An ancient site lies there")
	var cost: Dictionary = data.field.supplyPoint.cost if kind == "supply" else fort_cost(data, village.state.bonuses)
	var ledger := LocalLedger.spend(village.state.ledger, at, cost)
	if ledger.has("missing"):
		return ledger
	village.state.ledger = ledger
	var fort := {"id": world.next.fort, "kind": kind, "ownerAccountId": village.ownerAccountId, "villageId": village.id, "q": cell.x, "r": cell.y,
		"status": "building", "completesAt": LocalTime.ms(at + (float(rules.buildSeconds) * 1000.0) / world.speed), "mannedAt": null, "grain": 0.0}
	world.next.fort += 1
	world.forts.append(fort)
	server.schedule(world, int(fort.completesAt), "fort_complete", {"fortId": fort.id})
	# Hordes on the march may pass it and burn it.
	if kind == "supply":
		LocalHordes.supply_point_placed(server, world, fort, at)
	return fort


static func fort_view(f: Dictionary) -> Dictionary:
	return {"id": f.id, "kind": f.get("kind", "fort"), "ownerAccountId": f.ownerAccountId, "villageId": f.villageId, "q": f.q, "r": f.r, "status": f.status,
		"completesAt": LocalTime.iso(f.completesAt), "grain": f.get("grain", 0.0), "armyFloor": f.get("armyFloor")}


static func on_fort_complete(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var fort := find_fort(world, int(event.payload.fortId))
	if fort.is_empty() or fort.status != "building":
		return
	fort.status = "standing"
	changed.append(["world"])
	if fort.get("kind", "fort") == "supply":
		LocalInbox.tell(server, world, fort.ownerAccountId, {"kind": "build_done", "tier": "digest", "title": "Supply point at ({q}, {r}) finished",
			"body": "Armies standing there fill up from its grain; supply routes keep it stocked.", "vars": {"q": fort.q, "r": fort.r}}, int(event.dueAt))
		return
	_plan_fort_check(server, world, int(fort.id), int(event.dueAt))
	LocalInbox.tell(server, world, fort.ownerAccountId, {"kind": "build_done", "tier": "digest", "title": "Fort at ({q}, {r}) finished",
		"body": "Armies holding it fight from behind its walls.", "vars": {"q": fort.q, "r": fort.r}}, int(event.dueAt))
	LocalAchievements.achieve(server, world, fort.ownerAccountId, "fort_built", int(event.dueAt))
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


## Builds a road between two neighbouring hexes near the village, or
## improves the standing road there to its next level.
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
	var existing := _road_edge(world, a, b)
	if existing.get("status") == "building":
		return LocalVillage.rule("A road is being built there")
	if existing.get("status") == "upgrading":
		return LocalVillage.rule("That road is being improved")
	if not existing.is_empty() and int(existing.level) >= rules.levels.size():
		return LocalVillage.rule("That road is as good as it gets")
	var level: Dictionary = rules.levels[int(existing.level) if not existing.is_empty() else 0]
	var ledger := LocalLedger.spend(village.state.ledger, at, level.cost)
	if ledger.has("missing"):
		return ledger
	village.state.ledger = ledger
	var completes_at := LocalTime.ms(at + (float(level.buildSeconds) * 1000.0) / world.speed)
	var road := existing
	if road.is_empty():
		var ends := LocalServer._ordered(a, b)
		road = {"a": ends[0], "b": ends[1], "status": "building", "level": 1, "builtBy": village.id, "completesAt": completes_at}
		world.roads.append(road)
	else:
		road.status = "upgrading"
		road.builtBy = village.id
		road.completesAt = completes_at
	server.schedule(world, completes_at, "road_built", {"aq": a.x, "ar": a.y, "bq": b.x, "br": b.y})
	return road


static func on_road_built(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var p: Dictionary = event.payload
	var road := _road_edge(world, Vector2i(int(p.aq), int(p.ar)), Vector2i(int(p.bq), int(p.br)))
	if road.is_empty() or road.status == "standing":
		return
	if road.status == "upgrading":
		road.level = int(road.level) + 1
	road.status = "standing"
	road.completesAt = null
	# Outposts joined to their village by it gather more.
	relink_outposts(server, world, int(event.dueAt), changed)
	changed.append(["world"])


## scheduler/outposts.ts relinkOutposts: every outpost's road link anew.
static func relink_outposts(server: LocalServer, world: Dictionary, at: int, changed: Array) -> void:
	var roads: Dictionary = LocalHordes.land_of(world).roads
	for village in world.villages:
		if LocalVillage.outpost_plots(village.state.plots).is_empty():
			continue
		var home := Vector2i(village.q, village.r)
		var link := func(cell: Vector2i) -> float: return LocalLand.road_link(server.data, roads, cell, home)
		var next := LocalVillage.with_road_links(server.data, village.state, link, at, world.speed)
		if next == village.state:
			continue
		village.state = next
		changed.append(["village", village.id])


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

## An army storms a camp (or a site's guardians): {cleared, rounds, armyNow,
## campNow, fallen}. `champions`: its hero and general fighting in its ranks;
## `stats_without_hero`: its stats once the hero has fallen.
static func assault(data: Dictionary, army: Dictionary, army_stats: Callable, army_stance: String, camp: Dictionary, front: String, seed_value: int, id: int,
		champions: Array = [], stats_without_hero: Callable = Callable()) -> Dictionary:
	var camp_stats := LocalBattle.enemy_stats(data, front)
	var stance: String = data.camps.assault.stance
	var fallen: Array = []
	var fighting: Array = champions.duplicate()
	var stats_now := func(unit: String) -> Dictionary:
		return (stats_without_hero if "hero" in fallen and stats_without_hero.is_valid() else army_stats).call(unit)
	var army_now := army.duplicate()
	var camp_now := camp.duplicate()
	var rounds: Array = []
	for round in range(1, int(data.battle.maxRounds) + 1):
		var result := LocalBattle.resolve_round(data, {"units": army_now, "stance": army_stance, "stats": stats_now, "home": false, "champions": fighting},
			{"units": camp_now, "stance": stance, "stats": camp_stats, "home": true}, LocalBattle.battle_rng(seed_value, id + 0x10000, round))
		for c in result.attackerFallen[0]:
			fallen.append(c)
		fighting = fighting.filter(func(c: Dictionary) -> bool: return not c.id in fallen)
		army_now = LocalCamps.subtract_units(army_now, result.attackerLosses)
		camp_now = LocalCamps.subtract_units(camp_now, result.defenderLosses)
		rounds.append({"round": round, "attackerLosses": result.attackerLosses, "defenderLosses": result.defenderLosses,
			"attackerLeft": LocalBattle.total(army_now), "defenderLeft": LocalBattle.total(camp_now)})
		var outcome := LocalBattle.battle_outcome(data, {"round": round, "attackerStance": army_stance, "attackerInitial": army, "attackerNow": army_now,
			"defenderStance": stance, "defenderInitial": camp, "defenderNow": camp_now})
		# "raided": the defenders (the camp) broke; "defended": the army did.
		if outcome != "ongoing":
			return {"cleared": outcome == "raided", "rounds": rounds, "armyNow": army_now, "campNow": camp_now, "fallen": fallen}
	return {"cleared": false, "rounds": rounds, "armyNow": army_now, "campNow": camp_now, "fallen": fallen}


## sim/camps.ts repelRaid: raiders strike an army standing guard; held
## when the raiders broke. {held, armyNow, raidersNow}.
static func repel_raid(data: Dictionary, army: Dictionary, army_stats: Callable, army_stance: String, raiders: Dictionary, raider_stance: String,
		front: String, seed_value: int, id: int) -> Dictionary:
	var raider_stats := LocalBattle.enemy_stats(data, front)
	var army_now := army.duplicate()
	var raiders_now := raiders.duplicate()
	for round in range(1, int(data.battle.maxRounds) + 1):
		var result := LocalBattle.resolve_round(data, {"units": raiders_now, "stance": raider_stance, "stats": raider_stats, "home": false},
			{"units": army_now, "stance": army_stance, "stats": army_stats, "home": false}, LocalBattle.battle_rng(seed_value, id + 0x20000, round))
		raiders_now = LocalCamps.subtract_units(raiders_now, result.attackerLosses)
		army_now = LocalCamps.subtract_units(army_now, result.defenderLosses)
		var outcome := LocalBattle.battle_outcome(data, {"round": round, "attackerStance": raider_stance, "attackerInitial": raiders, "attackerNow": raiders_now,
			"defenderStance": army_stance, "defenderInitial": army, "defenderNow": army_now})
		if outcome != "ongoing":
			return {"held": outcome == "defended", "armyNow": army_now, "raidersNow": raiders_now}
	return {"held": false, "armyNow": army_now, "raidersNow": raiders_now}


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
	var general := LocalGenerals.general_with_army(world, int(army.id))
	var bonuses := _led_bonuses(data, LocalVillage.village_bonuses(data, home.state), hero, general)
	var succession := _led_bonuses(data, LocalVillage.village_bonuses(data, home.state), {}, general)
	# Scouts never fight; they tell the army what it faces (intel).
	var result := assault(data, LocalScouting.combatants(data, army.units), LocalScouting.with_intel(data, army.units, LocalBattle.player_stats(data, bonuses, false)),
		army.get("stance", "balanced"), camp.units, camp.front, int(world.seed), int(camp.id),
		LocalChampions.champions_of(data, hero, general), LocalScouting.with_intel(data, army.units, LocalBattle.player_stats(data, succession, false)))
	var battle := _assault_battle(world, {"waveId": null, "campId": camp.id, "villageId": null, "q": camp.q, "r": camp.r,
		"attackerStance": data.camps.assault.stance, "attackerInitial": camp.units, "defenderInitial": army.units, "startedAt": at},
		result, at, "cleared" if result.cleared else "repelled", camp_loot(data, camp.units) if result.cleared else null)
	var after := army_losses(server, world, army, _losses({"units": LocalScouting.combatants(data, army.units)}, result.armyNow), at)
	var kills := LocalBattle.total(camp.units) - LocalBattle.total(result.campNow)
	var ember := false
	if result.cleared:
		camp.status = "cleared"
		after.loot = camp_loot(data, camp.units)
		# Captives freed (or a hero's quest camp cleared): troops join the army,
		# goods ride home with it.
		if camp.get("reward") != null:
			if camp.reward.has("units"):
				after.units = LocalCamps.add_units(after.units, camp.reward.units)
			else:
				var loot: Dictionary = after.loot
				after.loot = LocalVillage.resources(func(k: String) -> float: return float(loot.get(k, 0)) + float(camp.reward.resources[k]))
		# A lair holds an Ember by chance, and always while the bridge lacks one.
		var lucky := LocalWaves.rng_for(int(world.seed), int(camp.id), 0xe3).next() < float(data.camps.loot.emberChance)
		var bridge: Dictionary = world.get("bridge", {})
		var short: bool = not bridge.is_empty() and bridge.status == "open" and int(world.embers) < LocalBridge.embers_wanted(data, bridge)
		ember = camp.kind == "lair" and (lucky or short)
		if ember:
			world.embers = int(world.embers) + 1
		if camp.kind == "lair":
			LocalBattles.bridge_quest(server, world, "lair", at)
		# A bridge quest's lair.
		if camp.get("quest") != null and LocalHeroes.parse_army_quest_mark(camp.quest).is_empty():
			LocalBattles.bridge_quest(server, world, String(camp.quest), at)
		server.onboarding_step(world, int(army.ownerAccountId), "camp", at, changed)
	else:
		camp.units = result.campNow
	# Champions struck down fell; the others share the outcome.
	LocalChampions.fall(server, world, result.fallen, hero, general, army.homeVillageId, {"kills": kills, "battleId": battle.id, "at": at})
	if not hero.is_empty() and not "hero" in result.fallen:
		if not result.cleared:
			hero.villageId = army.homeVillageId
			hero.armyId = null
		LocalBattles.hero_after_battle(server, world, hero, {"kills": kills, "won": result.cleared, "battleId": battle.id, "at": at})
	if not general.is_empty() and not "general" in result.fallen:
		LocalGenerals.after_battle(server, world, general, {"kills": kills, "won": result.cleared, "at": at})
	# Cleared, the army stands on the camp's hex until it is moved or called home.
	if result.cleared and LocalBattle.total(after.units) > 0:
		hold_hex(server, world, after, at)
	else:
		send_home(server, world, after, at)
	var where := "%s at (%d, %d)" % ["lair" if camp.kind == "lair" else ("captives' camp" if camp.kind == "captives" else "bandit camp"), int(camp.q), int(camp.r)]
	var body := "{kills} of them fell; {defenders} still hold it."
	if result.cleared:
		body = "It carries home {loot} resources and a Svarog's Ember for the group." if ember else "It carries home {loot} resources."
	LocalInbox.tell(server, world, army.ownerAccountId, {"kind": "battle_result", "tier": "digest",
		"title": "Your army cleared the {where}" if result.cleared else "Your army was driven off from the {where}", "body": body,
		"vars": {"where": where, "loot": int(LocalLogistics.total(after.loot if result.cleared and after.get("loot") != null else camp_loot(data, camp.units))), "kills": kills, "defenders": LocalBattle.total(result.campNow)}}, at)
	if result.cleared:
		LocalAchievements.achieve(server, world, army.ownerAccountId, "lair_cleared" if camp.kind == "lair" else ("captives_freed" if camp.kind == "captives" else "camp_cleared"), at)
	# A hero's army quest done.
	if result.cleared:
		LocalHeroCommands.army_quest_done(server, world, camp.get("quest"), at)
	# Captives freed: the event's bounty.
	if result.cleared and camp.kind == "captives":
		LocalEvents.reward(server, world, army.ownerAccountId, {"title": "You freed the captives at ({q}, {r})", "vars": {"q": camp.q, "r": camp.r}}, at, changed)


# --- Ancient sites (scheduler/sites.ts) -----------------------------------------------

## sim/sites.ts searchMs: real-time ms an army of `units` takes to search a
## site of `kind`; the more of them, the faster.
static func search_ms(data: Dictionary, kind: String, units: Dictionary, world_speed: float) -> float:
	var count := 0
	for unit in units:
		count += maxi(0, int(units[unit]))
	var share := maxf(float(data.sites.search.minShare), 1.0 / (1.0 + float(data.sites.search.perUnit) * maxi(0, count - 1)))
	# Without scouts to read the ground it takes the longer.
	var slow := 1.0 if scouts_in(data, units) > 0 else float(data.sites.search.noScoutsFactor)
	return (float(data.sites.kinds[kind].exploreHours) * LocalTime.MS_PER_HOUR * share * slow) / world_speed


## sim/sites.ts scoutsIn: how many scouts (of any kind) are among `units`.
static func scouts_in(data: Dictionary, units: Dictionary) -> int:
	var n := 0
	for unit in units:
		if data.units.units.get(unit, {}).get("family", "") == "scout":
			n += maxi(0, int(units[unit]))
	return n


## sim/sites.ts scoutLoot: what scouts along on a search find besides the
## site's find, more with every scout.
static func scout_loot(data: Dictionary, scouts: int, distance: float, loot_factor := 1.0) -> Dictionary:
	var rules: Dictionary = data.sites.search.scoutLoot
	var share := minf(float(rules.max), float(rules.perScout) * scouts)
	return LocalVillage.resources(func(k: String) -> int:
		return LocalWaves.js_round(float(data.sites.loot[k]) * (1.0 + distance) * loot_factor * share))


## An army sent to explore has reached the site.
static func arrive_at_site(server: LocalServer, world: Dictionary, army: Dictionary, at: int, _changed: Array) -> void:
	var data := server.data
	var site := site_at(world, Vector2i(army.targetQ, army.targetR))
	if site.is_empty() or site.status == "explored":
		send_home(server, world, army, at)
		return
	var explorers := army
	# Scouts alone don't fight guardians: they count them and turn back.
	if LocalBattle.total(site.guardians) > 0 and LocalBattle.total(LocalScouting.combatants(data, army.units)) == 0:
		site.guardiansSeen = true
		send_home(server, world, army, at)
		LocalInbox.tell(server, world, army.ownerAccountId, {"kind": "battle_result", "tier": "digest", "title": "Guardians drove your army from the {where}",
			"body": "{kills} of them fell; {remaining} still watch it.",
			"vars": {"where": data.sites.kinds.get(site.kind, {}).get("name", "site"), "kills": 0, "remaining": LocalBattle.total(site.guardians)}}, at)
		return
	if LocalBattle.total(site.guardians) > 0:
		var home := server.find_village(world, int(army.homeVillageId))
		var hero := hero_with_army(world, int(army.id))
		var general := LocalGenerals.general_with_army(world, int(army.id))
		var bonuses := _led_bonuses(data, LocalVillage.village_bonuses(data, home.state), hero, general)
		var succession := _led_bonuses(data, LocalVillage.village_bonuses(data, home.state), {}, general)
		var result := assault(data, LocalScouting.combatants(data, army.units), LocalScouting.with_intel(data, army.units, LocalBattle.player_stats(data, bonuses, false)),
			army.get("stance", "balanced"), site.guardians, "north", int(world.seed), int(site.id) + 0x5000,
			LocalChampions.champions_of(data, hero, general), LocalScouting.with_intel(data, army.units, LocalBattle.player_stats(data, succession, false)))
		var battle := _assault_battle(world, {"waveId": null, "siteId": site.id, "villageId": null, "q": site.q, "r": site.r,
			"attackerStance": data.camps.assault.stance, "attackerInitial": site.guardians, "defenderInitial": army.units, "startedAt": at},
			result, at, "cleared" if result.cleared else "repelled", null)
		explorers = army_losses(server, world, army, _losses({"units": LocalScouting.combatants(data, army.units)}, result.armyNow), at)
		var kills := LocalBattle.total(site.guardians) - LocalBattle.total(result.campNow)
		site.guardians = {} if result.cleared else result.campNow
		site.guardiansSeen = true
		# Champions struck down fell; the others share the outcome.
		LocalChampions.fall(server, world, result.fallen, hero, general, army.homeVillageId, {"kills": kills, "battleId": battle.id, "at": at})
		if not hero.is_empty() and not "hero" in result.fallen:
			if not result.cleared:
				hero.villageId = army.homeVillageId
				hero.armyId = null
			LocalBattles.hero_after_battle(server, world, hero, {"kills": kills, "won": result.cleared, "battleId": battle.id, "at": at})
		if not general.is_empty() and not "general" in result.fallen:
			LocalGenerals.after_battle(server, world, general, {"kills": kills, "won": result.cleared, "at": at})
		if not result.cleared or LocalBattle.total(explorers.units) == 0:
			send_home(server, world, explorers, at)
			LocalInbox.tell(server, world, army.ownerAccountId, {"kind": "battle_result", "tier": "digest", "title": "Guardians drove your army from the {where}",
				"body": "{kills} of them fell; {remaining} still watch it.",
				"vars": {"where": data.sites.kinds.get(site.kind, {}).get("name", "site"), "kills": kills, "remaining": LocalBattle.total(result.campNow)}}, at)
			return
	# Search the site.
	explorers.status = "stationed"
	explorers.battleId = null
	# The more hands, the faster.
	var done_at := LocalTime.ms(at + search_ms(data, String(site.kind), explorers.units, world.speed))
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
	# A bridge quest's ruin.
	if site.get("quest") != null and LocalHeroes.parse_army_quest_mark(site.quest).is_empty():
		LocalBattles.bridge_quest(server, world, String(site.quest), at)
	var data := server.data
	var name: String = data.sites.kinds.get(site.kind, {}).get("name", "site")
	for member in world.members:
		var scroll: bool = find.type == "scroll"
		LocalInbox.tell(server, world, member.accountId, {"kind": "site",
			"tier": "push" if scroll and (account_id == null or int(member.accountId) != int(account_id)) else "digest",
			"title": "The {name} at ({q}, {r}) gave up {find}",
			"body": data.lore.scrolls.get(find.scroll, {}).get("description", "") if scroll else "Explored and done.",
			"vars": {"name": name, "q": site.q, "r": site.r, "find": find_text(data, find)}}, at)
	LocalAchievements.achieve(server, world, account_id, "site_explored", at)
	if find.type == "ember":
		LocalAchievements.achieve(server, world, account_id, "ember_found", at)
	if find.type == "scroll":
		LocalAchievements.achieve(server, world, account_id, "scroll_found", at)
	# A hero's army quest done.
	LocalHeroCommands.army_quest_done(server, world, site.get("quest"), at)
	# A forbidding ruin searched: the event's bounty.
	if site.get("hard", false):
		LocalEvents.reward(server, world, account_id, {"title": "You searched the forbidding ruin at ({q}, {r})", "vars": {"q": site.q, "r": site.r}}, at, changed)


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
	var distance := LocalSites.distance_share(Vector2i(site.q, site.r), int(world.radius))
	var loot_factor := float(data.events.kinds.ruin.lootFactor) if site.get("hard", false) else 1.0
	var find := LocalSites.roll_find(data, site.kind, int(world.seed), int(site.id), distance, LocalResearch.scrolls(world), gear, loot_factor)
	# Scouts along find more besides: resources carried home with the find.
	var extra := scout_loot(data, scouts_in(data, army.units), distance, loot_factor)
	if find.type == "resources" or LocalLogistics.total(extra) > 0:
		var found: Dictionary = find.resources if find.type == "resources" else {}
		army.loot = LocalVillage.resources(func(k: String) -> int: return int(found.get(k, 0)) + int(extra[k]))
	claim_find(server, world, site, army.ownerAccountId, owner_hero, find, at, changed)
	# Searched, the army stands on the site's hex until it is moved or called home.
	hold_hex(server, world, army, at)


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


## The research effects of troops led by `hero` and `general` (either may
## be {}): the hero commands, else the general.
static func _led_bonuses(data: Dictionary, own: Dictionary, hero: Dictionary, general: Dictionary) -> Dictionary:
	return LocalChampions.command_bonuses(data, own, hero, general)


static func army_view(a: Dictionary) -> Dictionary:
	return {"id": a.id, "ownerAccountId": a.ownerAccountId, "homeVillageId": a.homeVillageId, "targetVillageId": a.targetVillageId,
		"target": [a.targetQ, a.targetR], "heroAccountId": a.heroAccountId, "generalId": a.get("generalId"), "orders": a.orders,
		"stance": a.get("stance", "balanced"), "loot": a.loot, "units": a.units,
		"status": a.status, "battleId": a.battleId, "path": a.path.map(func(s: Dictionary) -> Array: return [s.q, s.r, s.atMs]),
		"departsAt": LocalTime.iso(a.departsAt), "arrivesAt": LocalTime.iso(a.arrivesAt),
		"leavesAt": LocalTime.iso(a.leavesAt) if a.leavesAt != null else null, "returnsAt": LocalTime.iso(a.returnsAt) if a.returnsAt != null else null,
		"supply": a.get("supply"), "supplyAt": LocalTime.iso(a.supplyAt) if a.get("supplyAt") != null else null,
		"hungrySince": LocalTime.iso(a.hungrySince) if a.get("hungrySince") != null else null,
		"wagonFortAt": LocalTime.iso(a.wagonFortAt) if a.get("wagonFortAt") != null else null,
		"returnHome": a.get("returnHome", false), "raid": a.get("raid"),
		"quarteredAt": LocalTime.iso(a.quarteredAt) if a.get("quarteredAt") != null else null,
		"respond": a.get("respond", true), "post": a.get("post")}


## Newly trained troops march to their owner's rally point (scheduler/
## armies.ts rallyTrained): each batch done (`batches`, as they stood before
## settling) sends as many of its unit as stand at home, up to its size, as
## one army joining the garrison there. Troops that can't march (settlers),
## or a village under siege, stay home.
static func rally_trained(server: LocalServer, world: Dictionary, home: Dictionary, batches: Array, at: int) -> void:
	var data := server.data
	if home.ownerAccountId == null or home.state.besieged or batches.is_empty():
		return
	var rally: Variant = null
	for m in world.members:
		if int(m.accountId) == int(home.ownerAccountId):
			rally = m.get("rallyVillageId")
	if rally == null or int(rally) == int(home.id):
		return
	var target := server.find_village(world, int(rally))
	if target.is_empty() or target.ownerAccountId == null or int(target.ownerAccountId) != int(home.ownerAccountId) or target.ruin != null:
		return
	var units := {}
	for batch in batches:
		var def: Dictionary = data.units.units.get(batch.unit, {})
		var marches: bool = def.get("family") == "scout" or LocalBattle.total(fighters(data, {batch.unit: 1})) > 0
		if not marches:
			continue
		var left := int(home.state.garrison.get(batch.unit, 0)) - int(units.get(batch.unit, 0))
		var n := mini(left, int(batch.get("size", batch.count)))
		if n > 0:
			units[batch.unit] = int(units.get(batch.unit, 0)) + n
	if LocalBattle.total(fighters(data, units)) == 0:
		return
	dispatch_army(server, world, {"homeVillageId": home.id, "targetVillageId": target.id, "units": units, "orders": "garrison", "at": at})


## A leader leaving an army out in the field makes their own way to a
## village: a hero walks, a general rides.
static func _hero_to(server: LocalServer, world: Dictionary, hero: Dictionary, from: Vector2i, village: Dictionary, at: int) -> void:
	var data := server.data
	var path: Variant = LocalLogistics.road_route(data, LocalHordes.land_of(world), from, Vector2i(village.q, village.r), float(data.heroes.speed) * LocalHeroes.hero_factor(data, hero.kind, "heroSpeed"), world.speed)
	var arrives_at := at + int(path[-1].atMs)
	hero.status = "traveling"
	hero.villageId = village.id
	hero.armyId = null
	hero.path = path
	hero.departsAt = LocalTime.iso(at)
	hero.arrivesAt = LocalTime.iso(arrives_at)
	server.schedule(world, arrives_at, "hero_arrive", {"accountId": hero.accountId})


static func _general_to(server: LocalServer, world: Dictionary, general: Dictionary, from: Vector2i, village: Dictionary, at: int) -> void:
	var data := server.data
	var path: Variant = LocalLogistics.road_route(data, LocalHordes.land_of(world), from, Vector2i(village.q, village.r), float(data.heroes.generals.speed), world.speed)
	general.status = "traveling"
	general.villageId = village.id
	general.armyId = null
	general.path = path
	general.departsAt = at
	general.until = at + int(path[-1].atMs)
	server.schedule(world, int(general.until), "general_arrive", {"generalId": general.id})


## The village of its owner's an army stands in ({} if none).
static func _own_village_here(server: LocalServer, world: Dictionary, army: Dictionary) -> Dictionary:
	if army.targetVillageId == null or not army.status in ["stationed", "engaged"]:
		return {}
	var village := server.find_village(world, int(army.targetVillageId))
	if village.is_empty() or village.ownerAccountId == null or int(village.ownerAccountId) != int(army.ownerAccountId) or village.get("ruin") != null:
		return {}
	return village


static func _not_in_battle(army: Dictionary) -> Dictionary:
	if army.status == "engaged":
		return LocalVillage.rule("That army is in the middle of a battle")
	if army.status == "done":
		return LocalVillage.rule("That army is no more")
	return {}


## Where an army is now: the hex it stands on, or for one on the road the
## last hex it reached.
static func _army_hex(army: Dictionary, at: int) -> Vector2i:
	if army.status in ["stationed", "engaged"]:
		return Vector2i(int(army.targetQ), int(army.targetR))
	var road: Array = LocalLogistics.reversed_route(army.path) if army.status == "returning" else army.path
	var since := at - (int(army.leavesAt) if army.status == "returning" else int(army.departsAt))
	var step: Dictionary = road[0]
	for s in road:
		if int(s.atMs) <= since:
			step = s
	return Vector2i(int(step.q), int(step.r))


## An army's home: another settlement of its owner's.
static func set_home(server: LocalServer, world: Dictionary, army: Dictionary, village_id: int) -> Dictionary:
	if army.status == "done":
		return LocalVillage.rule("That army is no more")
	if army.status == "returning":
		return LocalVillage.rule("They are on their way home; turn them first")
	var village := server.find_village(world, village_id)
	if village.is_empty() or village.ownerAccountId == null or int(village.ownerAccountId) != int(army.ownerAccountId) or village.get("ruin") != null:
		return LocalVillage.rule("Only one of your own settlements can be its home")
	if int(village.id) == int(army.homeVillageId):
		return LocalVillage.rule("%s is its home already" % village.name)
	army.homeVillageId = village.id
	return army


## Whether a standing army answers battles nearby.
static func set_respond(army: Dictionary, respond: bool) -> Dictionary:
	if army.status == "done":
		return LocalVillage.rule("That army is no more")
	army.respond = respond
	return army


## The hero joins a standing army in the village where the hero is, or
## leaves it (not in a battle).
static func army_hero(server: LocalServer, world: Dictionary, army: Dictionary, join: bool, at: int) -> Dictionary:
	var refused := _not_in_battle(army)
	if not refused.is_empty():
		return refused
	var led := hero_with_army(world, int(army.id))
	var general := LocalGenerals.general_with_army(world, int(army.id))
	if join:
		if not led.is_empty():
			return LocalVillage.rule("%s leads them already" % led.name)
		if army.status != "stationed":
			return LocalVillage.rule("Only a standing army can take on a hero")
		var hero := hero_of(world, int(army.ownerAccountId))
		if hero.is_empty():
			return LocalVillage.rule("You have no hero")
		if hero.status != "home" or army.targetVillageId == null or hero.villageId == null or int(hero.villageId) != int(army.targetVillageId):
			return LocalVillage.rule("%s is not where they stand" % hero.name)
		hero.status = "with_army"
		hero.villageId = null
		hero.armyId = army.id
		army.heroAccountId = hero.accountId
		army.generalId = general.id if not general.is_empty() else null
		return army
	if led.is_empty():
		return LocalVillage.rule("No hero leads them")
	var village := _own_village_here(server, world, army)
	if not village.is_empty():
		led.status = "home"
		led.villageId = village.id
		led.armyId = null
	else:
		_hero_to(server, world, led, _army_hex(army, at), server.find_village(world, int(army.homeVillageId)), at)
	army.heroAccountId = null
	army.generalId = general.id if not general.is_empty() else null
	return army


## A general takes command of a standing army in the village where the
## general is (the one leading it stays there), or the general leading it
## leaves (null). Not in a battle.
static func army_general(server: LocalServer, world: Dictionary, army: Dictionary, general_id: Variant, at: int) -> Dictionary:
	var refused := _not_in_battle(army)
	if not refused.is_empty():
		return refused
	var current := LocalGenerals.general_with_army(world, int(army.id))
	var led := hero_with_army(world, int(army.id))
	var hero_id: Variant = led.accountId if not led.is_empty() else null
	if general_id == null:
		if current.is_empty():
			return LocalVillage.rule("No general leads them")
		var village := _own_village_here(server, world, army)
		if not village.is_empty():
			current.status = "home"
			current.villageId = village.id
			current.armyId = null
		else:
			_general_to(server, world, current, _army_hex(army, at), server.find_village(world, int(army.homeVillageId)), at)
		army.heroAccountId = hero_id
		army.generalId = null
		return army
	if army.status != "stationed":
		return LocalVillage.rule("Only a standing army can take on a general")
	var general := LocalGenerals.find(world, int(general_id))
	if general.is_empty() or int(general.accountId) != int(army.ownerAccountId):
		return LocalVillage.rule("No such general")
	if not current.is_empty() and int(general.id) == int(current.id):
		return LocalVillage.rule("%s leads them already" % general.name)
	if general.status != "home" or army.targetVillageId == null or general.villageId == null or int(general.villageId) != int(army.targetVillageId):
		return LocalVillage.rule("%s is not where they stand" % general.name)
	if not current.is_empty():
		current.status = "home"
		current.villageId = army.targetVillageId
		current.armyId = null
	general.status = "with_army"
	general.villageId = null
	general.armyId = army.id
	army.heroAccountId = hero_id
	army.generalId = general.id
	return army


## Two standing armies of one owner on the same hex become one: the other's
## troops, grain, loot and leaders join this one (at most one general).
static func merge_armies(server: LocalServer, world: Dictionary, army: Dictionary, other_id: int, at: int) -> Dictionary:
	var data := server.data
	var refused := _standing(army)
	if not refused.is_empty():
		return refused
	if other_id == int(army.id):
		return LocalVillage.rule("Pick another army")
	var other := find_army(world, other_id)
	if other.is_empty() or other.ownerAccountId == null or int(other.ownerAccountId) != int(army.ownerAccountId):
		return LocalVillage.rule("No such army of yours")
	refused = _standing(other)
	if not refused.is_empty():
		return refused
	if int(other.targetQ) != int(army.targetQ) or int(other.targetR) != int(army.targetR):
		return LocalVillage.rule("They must stand on the same hex")
	var hero_a := hero_with_army(world, int(army.id))
	var hero_b := hero_with_army(world, int(other.id))
	var gen_a := LocalGenerals.general_with_army(world, int(army.id))
	var gen_b := LocalGenerals.general_with_army(world, int(other.id))
	if not gen_a.is_empty() and not gen_b.is_empty():
		return LocalVillage.rule("Both have a general: send one away first")
	unquarter(server, world, army, at)
	unquarter(server, world, other, at)
	var fed_a := supplied(army)
	var fed_b := supplied(other)
	var supply: Variant = null
	if fed_a or fed_b:
		supply = (LocalSupply.supply_left(data, army, at, world.speed) if fed_a else 0.0) + (LocalSupply.supply_left(data, other, at, world.speed) if fed_b else 0.0)
	var loot: Variant = null
	if army.loot != null or other.loot != null:
		var la: Variant = army.loot
		var lb: Variant = other.loot
		loot = LocalVillage.resources(func(kind: String) -> float:
			return (float(la.get(kind, 0)) if la != null else 0.0) + (float(lb.get(kind, 0)) if lb != null else 0.0))
	var units := LocalVillage.add_units(army.units, other.units)
	other.units = {}
	other.status = "done"
	other.supply = 0
	other.supplyAt = at
	other.hungerAt = null
	other.loot = null
	other.leavesAt = at
	other.returnsAt = at
	other.heroAccountId = null
	other.generalId = null
	var hero := hero_a if not hero_a.is_empty() else hero_b
	var general := gen_a if not gen_a.is_empty() else gen_b
	if not hero_b.is_empty():
		hero_b.armyId = army.id
	if not gen_b.is_empty():
		gen_b.armyId = army.id
	army.units = units
	army.supply = supply
	army.supplyAt = at if supply != null else null
	army.hungrySince = null
	army.loot = loot
	army.heroAccountId = hero.accountId if not hero.is_empty() else null
	army.generalId = general.id if not general.is_empty() else null
	var ring_a: Variant = army.get("wagonFortAt")
	var ring_b: Variant = other.get("wagonFortAt")
	army.wagonFortAt = maxi(int(ring_a), int(ring_b)) if ring_a != null and ring_b != null else ring_a
	quarter(server, world, army, at)
	plan_hunger(server, world, army, at)
	return army


## A standing army splits off some of its troops as an army of their own on
## the same hex, with their share of its grain, and its hero or general if
## told so (its loot stays): {army, split}, or {"error"}.
static func split_army(server: LocalServer, world: Dictionary, army: Dictionary, body: Dictionary, at: int) -> Dictionary:
	var data := server.data
	var refused := _standing(army)
	if not refused.is_empty():
		return refused
	var picked: Dictionary = body.units
	var units := {}
	for unit in picked:
		var n := float(picked[unit])
		if n != floorf(n) or n < 0:
			return LocalVillage.rule("Pick whole troops")
		if int(n) > int(army.units.get(unit, 0)):
			return LocalVillage.rule("They have not so many")
		if n > 0:
			units[unit] = int(n)
	var rest := {}
	for unit in army.units:
		var left := int(army.units[unit]) - int(units.get(unit, 0))
		if left > 0:
			rest[unit] = left
	if LocalBattle.total(units) == 0:
		return LocalVillage.rule("Pick who goes")
	if LocalBattle.total(rest) == 0:
		return LocalVillage.rule("Leave someone behind")
	var hero := hero_with_army(world, int(army.id)) if body.get("withHero", false) else {}
	if body.get("withHero", false) and hero.is_empty():
		return LocalVillage.rule("No hero leads them")
	var general := LocalGenerals.general_with_army(world, int(army.id)) if body.get("withGeneral", false) else {}
	if body.get("withGeneral", false) and general.is_empty():
		return LocalVillage.rule("No general leads them")
	var whole := LocalSupply.full_supply(data, army.units)
	unquarter(server, world, army, at)
	var fed := supplied(army)
	var carried := LocalSupply.supply_left(data, army, at, world.speed) if fed else 0.0
	var share := LocalSupply.full_supply(data, units) / whole if whole > 0 else float(LocalBattle.total(units)) / LocalBattle.total(army.units)
	var taken: Variant = carried * share if fed else null
	var orders := String(army.orders) if army.orders in ["support", "hold"] else ("hold" if army.targetVillageId == null else "support")
	var created := {"id": world.next.army, "ownerAccountId": army.ownerAccountId, "homeVillageId": army.homeVillageId,
		"targetVillageId": army.targetVillageId, "targetQ": army.targetQ, "targetR": army.targetR,
		"heroAccountId": hero.accountId if not hero.is_empty() else null, "generalId": general.id if not general.is_empty() else null,
		"orders": orders, "stance": army.get("stance", "balanced"), "engagedUnits": null, "units": units, "status": "stationed",
		"loot": null, "battleId": null, "joinsRound": null, "joinBonus": 0, "path": [{"q": int(army.targetQ), "r": int(army.targetR), "atMs": 0}],
		"departsAt": at, "arrivesAt": at, "leavesAt": null, "returnsAt": null, "supply": taken, "supplyAt": at if fed else null,
		"hungrySince": null, "hungerAt": null, "wagonFortAt": null, "returnHome": army.get("returnHome", false),
		"quarteredAt": null, "respond": army.get("respond", true), "post": null}
	world.next.army += 1
	world.armies.append(created)
	if not hero.is_empty():
		hero.armyId = created.id
	if not general.is_empty():
		general.armyId = created.id
	var left_hero: Variant = null
	if hero.is_empty():
		var h := hero_with_army(world, int(army.id))
		left_hero = h.accountId if not h.is_empty() else null
	var left_general: Variant = null
	if general.is_empty():
		var g := LocalGenerals.general_with_army(world, int(army.id))
		left_general = g.id if not g.is_empty() else null
	army.units = rest
	if fed:
		army.supply = carried - float(taken)
		army.supplyAt = at
	army.heroAccountId = left_hero
	army.generalId = left_general
	quarter(server, world, army, at)
	plan_hunger(server, world, army, at)
	quarter(server, world, created, at)
	plan_hunger(server, world, created, at)
	return {"army": army, "split": created}
