class_name LocalGenerals
extends RefCounted
## Generals for the local engine: server/src/sim/generals.ts,
## commands/generals.ts and scheduler/generals.ts. Only the hero is
## wounded: a general whose side loses is killed. A general:
## {id, accountId, name, status, villageId, level, xp, armyId, path,
## departsAt, until} with times in ms. Commands answer the general, or
## {"error"} / {"missing"}.


# --- Rules (sim/generals.ts) ---------------------------------------------------------

static func name_for(data: Dictionary, id: int) -> String:
	var names: Array = data.heroes.generals.names
	return names[(id - 1) % names.size()]


static func xp_to_next(data: Dictionary, level: int) -> int:
	var xp: Dictionary = data.heroes.generals.levelXp
	return LocalWaves.js_round(float(xp.base) * pow(float(xp.growth), level - 1))


## Adds XP, levelling up as far as it reaches: {level, xp}.
static func gain_xp(data: Dictionary, general: Dictionary, xp: float) -> Dictionary:
	var top := int(data.heroes.generals.maxLevel)
	var level := int(general.level)
	var pool := int(general.xp) + maxi(0, floori(xp))
	while level < top and pool >= xp_to_next(data, level):
		pool -= xp_to_next(data, level)
		level += 1
	return {"level": level, "xp": 0 if level >= top else pool}


## What a general adds to the troops it leads.
static func bonuses(data: Dictionary, general: Dictionary) -> Dictionary:
	var out := {}
	var per: Dictionary = data.heroes.generals.effectsPerLevel
	for key in per:
		out[key] = float(per[key]) * int(general.level)
	return out


## How many generals a player may have, by the levels of their Hero's Halls.
static func limit(data: Dictionary, hall_levels: Array) -> int:
	var g: Dictionary = data.heroes.generals
	var n := 0
	for level in hall_levels:
		if int(level) > 0:
			n += int(g.perHall) + floori(float(int(level) - 1) / int(g.hallLevelsPerGeneral))
	return n


static func recruit_cost(data: Dictionary, owned: int) -> Dictionary:
	var g: Dictionary = data.heroes.generals
	return LocalVillage.resources(func(kind: String) -> int: return LocalWaves.js_round(float(g.cost[kind]) * pow(float(g.costGrowth), owned)))


static func recruit_ms(data: Dictionary, world_speed: float) -> int:
	return LocalWaves.js_round((float(data.heroes.generals.recruitHours) * 3600000.0) / world_speed)


## The Hero's Hall in a village shortens the hero's wounds healed there.
static func hall_recovery(data: Dictionary, hall_level: int) -> float:
	if hall_level <= 0:
		return 1.0
	return maxf(0.1, 1.0 - float(data.heroes.generals.hallRecoveryPerLevel) * hall_level)


# --- Lookups (db/generals.ts) ---------------------------------------------------------

static func find(world: Dictionary, id: int) -> Dictionary:
	for g in world.generals:
		if int(g.id) == id:
			return g
	return {}


static func owned_by(world: Dictionary, account_id: int) -> Array:
	return world.generals.filter(func(g: Dictionary) -> bool: return int(g.accountId) == account_id)


## The general commanding a village's garrison: the best at home there
## (the first recruited among equals).
static func general_at(world: Dictionary, village_id: int) -> Dictionary:
	var best: Dictionary = {}
	for g in world.generals:
		if g.status != "home" or g.villageId == null or int(g.villageId) != village_id:
			continue
		if best.is_empty() or int(g.level) > int(best.level) or (int(g.level) == int(best.level) and int(g.id) < int(best.id)):
			best = g
	return best


static func general_with_army(world: Dictionary, army_id: int) -> Dictionary:
	for g in world.generals:
		if g.armyId != null and int(g.armyId) == army_id and g.status == "with_army":
			return g
	return {}


## The level of the Hero's Hall in a village (0: none, or no village).
static func hall_level_at(server: LocalServer, world: Dictionary, village_id: Variant) -> int:
	if village_id == null:
		return 0
	var village := server.find_village(world, int(village_id))
	return 0 if village.is_empty() else int(village.state.levels.get("heroes_hall", 0))


# --- Battles (scheduler/generals.ts) ------------------------------------------------------

## A general falls: it is gone (armies it led forget it).
static func kill(server: LocalServer, world: Dictionary, general: Dictionary, at: int) -> void:
	_remove(world, general)
	LocalInbox.tell(server, world, general.accountId, {"kind": "hero", "tier": "digest", "title": "{name} fell in battle",
		"body": "Recruit another at a Hero's Hall.", "vars": {"name": general.name}}, at)


## XP for the enemies that fell, or death when its side lost.
static func after_battle(server: LocalServer, world: Dictionary, general: Dictionary, result: Dictionary) -> void:
	if not result.won:
		kill(server, world, general, int(result.at))
		return
	var level_before := int(general.level)
	general.merge(gain_xp(server.data, general, float(result.kills)), true)
	if int(general.level) > level_before:
		LocalInbox.tell(server, world, general.accountId, {"kind": "hero", "tier": "digest", "title": "{name} reached level {level}",
			"body": "The troops they lead fight a little harder.", "vars": {"name": general.name, "level": int(general.level)}}, int(result.at))


static func on_general_ready(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var general := find(world, int(event.payload.generalId))
	if general.is_empty() or general.status != "recruiting" or general.until == null or int(general.until) > int(event.dueAt):
		return
	general.status = "home"
	general.until = null
	LocalInbox.tell(server, world, general.accountId, {"kind": "hero", "tier": "digest", "title": "{name} answers your call",
		"body": "A new general stands ready.", "vars": {"name": general.name}}, int(event.dueAt))
	changed.append(["world"])


static func on_general_arrive(_server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var general := find(world, int(event.payload.generalId))
	if general.is_empty() or general.status != "traveling" or general.until == null or int(general.until) > int(event.dueAt):
		return
	general.status = "home"
	general.path = null
	general.departsAt = null
	general.until = null
	changed.append(["world"])


# --- Commands (commands/generals.ts) --------------------------------------------------------

## Recruits a general at the village, paid from its stores: {state, general}.
static func recruit(server: LocalServer, world: Dictionary, village: Dictionary, now: int) -> Dictionary:
	var data := server.data
	var owner := int(village.ownerAccountId)
	var owned := owned_by(world, owner).size()
	var halls := []
	for v in world.villages:
		if int(v.ownerAccountId) == owner:
			halls.append(int(v.state.levels.get("heroes_hall", 0)))
	if int(village.state.levels.get("heroes_hall", 0)) < 1:
		return LocalVillage.rule("Generals are recruited at a Hero's Hall")
	var most := limit(data, halls)
	if owned >= most:
		return LocalVillage.rule("Your Hero's Halls keep %d %s; raise one to recruit more" % [most, "general" if most == 1 else "generals"])
	var ledger := LocalLedger.spend(village.state.ledger, now, recruit_cost(data, owned))
	if ledger.has("missing"):
		return ledger
	var state: Dictionary = village.state.duplicate()
	state.ledger = ledger
	var id := int(world.next.general)
	world.next.general += 1
	var general := {"id": id, "accountId": owner, "name": name_for(data, id), "status": "recruiting", "villageId": village.id,
		"level": 1, "xp": 0, "armyId": null, "path": null, "departsAt": null, "until": now + recruit_ms(data, world.speed)}
	world.generals.append(general)
	server.schedule(world, int(general.until), "general_ready", {"generalId": id})
	return {"state": state, "general": general}


static func _not_ready(general: Dictionary) -> Dictionary:
	match String(general.status):
		"recruiting":
			return LocalVillage.rule("%s has not arrived yet" % general.name)
		"traveling":
			return LocalVillage.rule("%s is already on the road" % general.name)
		"with_army":
			return LocalVillage.rule("%s is leading an army" % general.name)
	return {}


## Sends a general to another of the player's villages.
static func move(server: LocalServer, world: Dictionary, general: Dictionary, village_id: int, now: int) -> Dictionary:
	var data := server.data
	var refused := _not_ready(general)
	if not refused.is_empty():
		return refused
	if general.villageId != null and int(general.villageId) == village_id:
		return LocalVillage.rule("%s is already there" % general.name)
	var destination := server.find_village(world, village_id)
	if destination.is_empty() or int(destination.ownerAccountId) != int(general.accountId):
		return LocalVillage.rule("Generals only travel between your own villages")
	var from := server.find_village(world, int(general.villageId))
	if from.state.besieged:
		return LocalVillage.rule("%s won't leave %s in the middle of a battle" % [general.name, from.name])
	var path: Variant = LocalLogistics.road_route(data, LocalHordes.land_of(world), Vector2i(from.q, from.r), Vector2i(destination.q, destination.r),
		float(data.heroes.generals.speed), world.speed)
	if path == null:
		return LocalVillage.rule("No road leads there")
	general.status = "traveling"
	general.villageId = destination.id
	general.path = path
	general.departsAt = now
	general.until = now + int(path[-1].atMs)
	server.schedule(world, int(general.until), "general_arrive", {"generalId": general.id})
	return general


static func dismiss(world: Dictionary, general: Dictionary) -> Dictionary:
	if general.status == "with_army":
		return LocalVillage.rule("%s is leading an army; call it home first" % general.name)
	_remove(world, general)
	return {"ok": true}


static func _remove(world: Dictionary, general: Dictionary) -> void:
	world.generals = world.generals.filter(func(g: Dictionary) -> bool: return int(g.id) != int(general.id))
	# Armies it once led forget it (ON DELETE SET NULL).
	for a in world.armies:
		if a.get("generalId") != null and int(a.generalId) == int(general.id):
			a.generalId = null


## Runs a general command for `account_id` (POST /v1/generals/:id/<action>).
static func command(server: LocalServer, world: Dictionary, account_id: int, id: int, action: String, body: Dictionary, now: int) -> Dictionary:
	var general := find(world, id)
	if general.is_empty():
		return LocalVillage.rule("No such general")
	if int(general.accountId) != account_id:
		return LocalVillage.rule("That general is not yours")
	match action:
		"move":
			return move(server, world, general, int(body.get("villageId", 0)), now)
		"dismiss":
			return dismiss(world, general)
	return {"notFound": true}


# --- Views (api/views.ts generalView) --------------------------------------------------------

static func view(data: Dictionary, g: Dictionary) -> Dictionary:
	var path: Variant = null
	if g.path != null:
		path = g.path.map(func(step: Dictionary) -> Array: return [step.q, step.r, step.atMs])
	return {"id": g.id, "accountId": g.accountId, "name": g.name, "status": g.status, "villageId": g.villageId, "armyId": g.armyId,
		"level": g.level, "xp": g.xp, "xpToNext": null if int(g.level) >= int(data.heroes.generals.maxLevel) else xp_to_next(data, int(g.level)),
		"bonuses": bonuses(data, g), "path": path,
		"departsAt": LocalTime.iso(g.departsAt) if g.departsAt != null else null,
		"until": LocalTime.iso(g.until) if g.until != null else null}
