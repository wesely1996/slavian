class_name LocalArmyGroups
## Army groups in a solo world (sim/armyGroups.ts, scheduler/armyGroups.ts,
## commands/armyGroups.ts): a named army with a set composition and a home
## settlement. Every few game minutes (group_check) what it lacks is trained,
## each unit in the owner's settlement closest to its army (to its home
## while it has none), and the troops march to the army once trained (or,
## with none standing yet, gather at the home as its army).


static func view(g: Dictionary) -> Dictionary:
	return {"id": g.id, "ownerAccountId": g.ownerAccountId, "name": g.name, "homeVillageId": g.homeVillageId,
		"composition": g.composition.duplicate(), "armyId": g.armyId}


static func views(world: Dictionary) -> Array:
	return world.get("armyGroups", []).map(view)


static func find(world: Dictionary, id: int) -> Dictionary:
	for g in world.get("armyGroups", []):
		if int(g.id) == id:
			return g
	return {}


## sim/armyGroups.ts groupName: the name given, trimmed, or "<home>'s Army".
static func group_name(name: Variant, home_name: String) -> Dictionary:
	var given := String(name if name != null else "").strip_edges()
	if given.length() > 32:
		return LocalVillage.rule("A name is at most 32 letters")
	return {"name": given if given != "" else "%s's Army" % home_name}


## sim/armyGroups.ts validateComposition: units that march with armies, by
## unit in name order, at least one soldier, at most maxUnits.
static func validate_composition(data: Dictionary, composition: Dictionary) -> Dictionary:
	var army := LocalArmies.validate_army(data, composition, "hold")
	if army.has("error"):
		return army
	if LocalBattle.total(army) > int(data.armies.groups.maxUnits):
		return LocalVillage.rule("A group holds at most %d troops" % int(data.armies.groups.maxUnits))
	var keys: Array = army.keys()
	keys.sort()
	var out := {}
	for unit in keys:
		out[unit] = int(army[unit])
	return {"composition": out}


## What the group lacks of each unit (in name order).
static func missing_units(composition: Dictionary, have: Dictionary, coming: Dictionary) -> Dictionary:
	var keys: Array = composition.keys()
	keys.sort()
	var out := {}
	for unit in keys:
		var n := int(composition[unit]) - int(have.get(unit, 0)) - int(coming.get(unit, 0))
		if n > 0:
			out[unit] = n
	return out


## n, half of it, ... down to 1.
static func batch_tries(n: int, max_batch: int) -> Array:
	var out: Array = []
	var k := mini(n, max_batch)
	while k >= 1:
		out.append(k)
		k = floori(k / 2.0)
	return out


static func _check_ms(data: Dictionary, world_speed: float) -> int:
	return LocalWaves.js_round(float(data.armies.groups.checkMinutes) * 60_000.0 / world_speed)


static func schedule_check(server: LocalServer, world: Dictionary, group_id: int, from: int) -> void:
	server.schedule(world, from + _check_ms(server.data, world.speed), "group_check", {"groupId": group_id})


## The group's army while it stands ({}: none, or lost).
static func fielded_army(world: Dictionary, group: Dictionary) -> Dictionary:
	if group.armyId == null:
		return {}
	var army := LocalArmies.find_army(world, int(group.armyId))
	if army.is_empty() or army.status == "done" or army.ownerAccountId == null or int(army.ownerAccountId) != int(group.ownerAccountId):
		return {}
	return army


static func _own_settlements(world: Dictionary, owner: int) -> Array:
	return world.villages.filter(func(v: Dictionary) -> bool: return v.ownerAccountId != null and int(v.ownerAccountId) == owner and v.get("ruin") == null)


static func _coming_to(world: Dictionary, group: Dictionary, villages: Array) -> Dictionary:
	var coming := {}
	for v in villages:
		for batch in v.state.training:
			if batch.get("group") != null and int(batch.group) == int(group.id):
				coming = LocalVillage.add_units(coming, {batch.unit: int(batch.get("size", batch.count))})
	for a in world.armies:
		if a.get("groupId") != null and int(a.groupId) == int(group.id) and a.status != "done" and (group.armyId == null or int(a.id) != int(group.armyId)):
			coming = LocalVillage.add_units(coming, a.units)
	return coming


## Where the group recruits for (null: not now): its home while it has no
## army, its army while that stands in one of its owner's settlements,
## forts or supply points.
static func _recruit_point(server: LocalServer, world: Dictionary, group: Dictionary, army: Dictionary) -> Variant:
	if army.is_empty():
		var home := server.find_village(world, int(group.homeVillageId))
		if home.is_empty() or home.get("ruin") != null or home.ownerAccountId == null or int(home.ownerAccountId) != int(group.ownerAccountId):
			return null
		return Vector2i(int(home.q), int(home.r))
	if army.status != "stationed":
		return null
	var place := LocalArmies.place_of(server, world, army)
	if place.is_empty():
		return null
	var owner: Variant = place.village.ownerAccountId if place.has("village") else place.store.ownerAccountId
	if owner == null or int(owner) != int(group.ownerAccountId):
		return null
	return Vector2i(int(army.targetQ), int(army.targetR))


## scheduler/armyGroups.ts recruitGroup.
static func recruit(server: LocalServer, world: Dictionary, group: Dictionary, at: int) -> void:
	var data := server.data
	var army := fielded_army(world, group)
	var point: Variant = _recruit_point(server, world, group, army)
	if point == null:
		return
	var owner := int(group.ownerAccountId)
	var villages := _own_settlements(world, owner)
	var missing := missing_units(group.composition, army.get("units", {}), _coming_to(world, group, villages))
	var near := villages.duplicate()
	near.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := HexMath.distance(point, Vector2i(int(a.q), int(a.r)))
		var db := HexMath.distance(point, Vector2i(int(b.q), int(b.r)))
		return da < db or (da == db and int(a.id) < int(b.id)))
	var owned: int = world.villages.filter(func(v: Dictionary) -> bool: return v.ownerAccountId != null and int(v.ownerAccountId) == owner).size()
	var member := server.member_of(world, owner)
	for unit in missing:
		var def: Dictionary = data.units.units.get(unit, {})
		if def.is_empty():
			continue
		var n := int(missing[unit])
		var slots := LocalSlots.of(data, world, owner)
		var per := int(def.get("slots", 0))
		var fit := floori((int(slots.cap) - int(slots.used)) / float(per)) if per > 0 else n
		var most := mini(n, fit)
		if most < 1:
			continue
		var tries: Array = [1] if def.get("oneAtATime", false) else batch_tries(most, int(data.units.maxBatch))
		var bought := int(member.get("bought", {}).get(unit, 0))
		var done := false
		for v in near:
			if done:
				break
			var village: Dictionary = v
			if village.state.besieged:
				continue
			for count in tries:
				var step := LocalVillage.queue_training(data, village.state, unit, int(count), at, world.speed, owned, bought)
				if step.has("missing"):
					continue
				if step.has("error"):
					break
				var batch: Dictionary = step.batch.duplicate()
				batch.group = group.id
				var state: Dictionary = step.state
				state.training[-1] = batch
				village.state = state
				if def.get("costStep") != null:
					server.add_bought(member, unit, int(count))
				server.schedule(world, LocalVillage.batch_completes_at(batch), "training_complete", {"villageId": village.id})
				done = true
				break


## Troops at home in `village` become an army standing there (quartered in
## it), with what grain they carry from its granary.
static func _stand_here(server: LocalServer, world: Dictionary, village: Dictionary, units: Dictionary, at: int) -> Dictionary:
	var data := server.data
	var state := LocalVillage.leave_garrison(data, village.state, units, at, world.speed)
	if state.has("error"):
		return state
	var grain := minf(LocalSupply.full_supply(data, units), LocalArmies.village_spare(data, state, at))
	if grain > 0:
		state.ledger = LocalLedger.spend(state.ledger, at, {"wood": 0.0, "stone": 0.0, "grain": grain, "iron": 0.0})
	village.state = state
	var army := {"id": world.next.army, "ownerAccountId": village.ownerAccountId, "homeVillageId": village.id, "targetVillageId": village.id,
		"targetQ": village.q, "targetR": village.r, "heroAccountId": null, "generalId": null, "orders": "support",
		"stance": String(village.state.stance), "engagedUnits": null, "units": units, "status": "stationed",
		"loot": null, "battleId": null, "joinsRound": null, "joinBonus": 0, "path": [{"q": village.q, "r": village.r, "atMs": 0}], "departsAt": at, "arrivesAt": at,
		"leavesAt": null, "returnsAt": null, "supply": grain, "supplyAt": at, "hungrySince": null, "hungerAt": null, "wagonFortAt": null,
		"returnHome": false, "quarteredAt": null, "respond": true, "post": null}
	world.next.army += 1
	world.armies.append(army)
	LocalArmies.quarter(server, world, army, at)
	LocalArmies.plan_hunger(server, world, army, at)
	return army


## scheduler/armyGroups.ts sendToGroup ({"error"} when refused).
static func _send_to_group(server: LocalServer, world: Dictionary, group: Dictionary, village: Dictionary, units: Dictionary, at: int) -> Dictionary:
	var army := fielded_army(world, group)
	if army.is_empty() and int(village.id) == int(group.homeVillageId):
		var formed := _stand_here(server, world, village, units, at)
		if formed.has("error"):
			return formed
		group.armyId = formed.id
		return {}
	if not army.is_empty() and army.targetVillageId != null and int(army.targetVillageId) == int(village.id):
		var here := _stand_here(server, world, village, units, at)
		if here.has("error"):
			return here
		if army.status == "stationed":
			LocalArmies.merge_armies(server, world, army, int(here.id), at)
		else:
			here.groupId = group.id
		return {}
	var order := {"homeVillageId": village.id, "units": units, "at": at}
	if army.is_empty():
		order.targetVillageId = group.homeVillageId
		order.orders = "support"
	elif army.targetVillageId != null:
		order.targetVillageId = army.targetVillageId
		order.orders = "support"
	else:
		order.targetVillageId = null
		order.targetHex = Vector2i(int(army.targetQ), int(army.targetR))
		order.orders = "hold"
	var sent := LocalArmies.dispatch_army(server, world, order)
	if sent.has("error"):
		return sent
	sent.groupId = group.id
	return {}


## scheduler/armyGroups.ts groupTrained.
static func group_trained(server: LocalServer, world: Dictionary, village: Dictionary, batches: Array, at: int) -> void:
	if village.state.besieged:
		return
	var by_group := {}
	var taken := {}
	for batch in batches:
		if batch.get("group") == null:
			continue
		var n := mini(int(village.state.garrison.get(batch.unit, 0)) - int(taken.get(batch.unit, 0)), int(batch.get("size", batch.count)))
		if n <= 0:
			continue
		taken[batch.unit] = int(taken.get(batch.unit, 0)) + n
		var g := int(batch.group)
		by_group[g] = LocalVillage.add_units(by_group.get(g, {}), {batch.unit: n})
	var ids: Array = by_group.keys()
	ids.sort()
	for id in ids:
		var group := find(world, int(id))
		if group.is_empty() or village.ownerAccountId == null or int(group.ownerAccountId) != int(village.ownerAccountId):
			continue
		_send_to_group(server, world, group, village, by_group[id], at)


## scheduler/armyGroups.ts joinGroup.
static func join_group(server: LocalServer, world: Dictionary, reinforcement: Dictionary, at: int) -> void:
	if reinforcement.get("groupId") == null or reinforcement.status != "stationed":
		return
	var group := find(world, int(reinforcement.groupId))
	if group.is_empty():
		reinforcement.groupId = null
		return
	var army := fielded_army(world, group)
	if army.is_empty() or int(army.id) == int(reinforcement.id):
		group.armyId = reinforcement.id
		reinforcement.groupId = null
		return
	var same_hex: bool = int(army.targetQ) == int(reinforcement.targetQ) and int(army.targetR) == int(reinforcement.targetR)
	if army.status == "stationed" and same_hex:
		LocalArmies.merge_armies(server, world, army, int(reinforcement.id), at)
		reinforcement.groupId = null
		return
	if not army.status in ["stationed", "marching"] or same_hex:
		return
	var to := {"villageId": army.targetVillageId, "join": false} if army.targetVillageId != null else {"target": {"q": army.targetQ, "r": army.targetR}}
	LocalArmies.move(server, world, reinforcement, to, at)


## A group's turn: its armies standing on their way join it, then what it
## lacks is recruited.
static func run_group(server: LocalServer, world: Dictionary, group: Dictionary, at: int) -> void:
	# In the server's order (db/armies.ts listArmies): latest set out first.
	var tagged: Array = world.armies.filter(func(a: Dictionary) -> bool:
		return a.get("groupId") != null and int(a.groupId) == int(group.id) and a.status == "stationed")
	tagged.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.departsAt) > int(b.departsAt) or (int(a.departsAt) == int(b.departsAt) and int(a.id) > int(b.id)))
	for a in tagged:
		join_group(server, world, a, at)
	recruit(server, world, group, at)


static func on_group_check(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var group := find(world, int(event.payload.groupId))
	if group.is_empty():
		return
	run_group(server, world, group, int(event.dueAt))
	schedule_check(server, world, int(group.id), int(event.dueAt))
	changed.append(["world"])


static func _home_of(server: LocalServer, world: Dictionary, village_id: Variant, owner: Variant) -> Dictionary:
	var village := server.find_village(world, int(village_id))
	if village.is_empty() or village.ownerAccountId == null or (owner != null and int(village.ownerAccountId) != int(owner)) or village.get("ruin") != null:
		return LocalVillage.rule("Only one of your own settlements can be its home")
	return village


static func _whole_positive(v: Variant) -> bool:
	return (v is int or v is float) and float(v) == floorf(float(v)) and float(v) > 0


static func _counts(v: Variant) -> bool:
	if not v is Dictionary:
		return false
	for unit in v:
		if not (v[unit] is int or v[unit] is float):
			return false
	return true


## commands/armyGroups.ts createArmyGroupCommand.
static func create(server: LocalServer, world: Dictionary, body: Dictionary, now: int) -> Dictionary:
	var data := server.data
	if not _whole_positive(body.get("homeVillageId")) or not _counts(body.get("composition")) or (body.has("name") and not (body.name is String and String(body.name).length() <= 64)):
		return {"error": "Invalid request", "kind": "invalid"}
	if server.find_village(world, int(body.homeVillageId)).is_empty():
		return {"error": "Village %d not found" % int(body.homeVillageId), "kind": "not_found"}
	var home := _home_of(server, world, body.homeVillageId, null)
	if home.has("error"):
		return home
	var owner := int(home.ownerAccountId)
	var most := int(data.armies.groups.maxPerPlayer)
	if world.get("armyGroups", []).filter(func(g: Dictionary) -> bool: return int(g.ownerAccountId) == owner).size() >= most:
		return LocalVillage.rule("You keep at most %d army groups" % most)
	var composition := validate_composition(data, body.composition)
	if composition.has("error"):
		return composition
	var named := group_name(body.get("name"), String(home.name))
	if named.has("error"):
		return named
	if not world.has("armyGroups"):
		world.armyGroups = []
	var id := int(world.next.get("armyGroup", 1))
	world.next.armyGroup = id + 1
	var group := {"id": id, "ownerAccountId": owner, "name": named.name, "composition": composition.composition, "homeVillageId": home.id, "armyId": null, "createdAt": now}
	world.armyGroups.append(group)
	recruit(server, world, group, now)
	schedule_check(server, world, id, now)
	return group


## commands/armyGroups.ts updateArmyGroupCommand.
static func update(server: LocalServer, world: Dictionary, group_id: int, body: Dictionary, now: int) -> Dictionary:
	var data := server.data
	if (body.has("homeVillageId") and not _whole_positive(body.homeVillageId)) or (body.has("composition") and not _counts(body.composition)) \
			or (body.has("name") and not (body.name is String and String(body.name).length() <= 64)):
		return {"error": "Invalid request", "kind": "invalid"}
	var group := find(world, group_id)
	if group.is_empty():
		return {"error": "Army group %d not found" % group_id, "kind": "not_found"}
	var home := {}
	if body.has("homeVillageId"):
		home = _home_of(server, world, body.homeVillageId, group.ownerAccountId)
		if home.has("error"):
			return home
	var name := String(group.name)
	if body.has("name"):
		var named := group_name(body.name, String((home if not home.is_empty() else server.find_village(world, int(group.homeVillageId))).name))
		if named.has("error"):
			return named
		name = named.name
	var composition: Dictionary = group.composition
	if body.has("composition"):
		var checked := validate_composition(data, body.composition)
		if checked.has("error"):
			return checked
		composition = checked.composition
	group.name = name
	if not home.is_empty():
		group.homeVillageId = home.id
	group.composition = composition
	return group


## commands/armyGroups.ts disbandArmyGroupCommand.
static func disband(world: Dictionary, group_id: int) -> Dictionary:
	var group := find(world, group_id)
	if group.is_empty():
		return {"error": "Army group %d not found" % group_id, "kind": "not_found"}
	for a in world.armies:
		if a.get("groupId") != null and int(a.groupId) == group_id:
			a.groupId = null
	world.armyGroups.erase(group)
	return {"ok": true}
