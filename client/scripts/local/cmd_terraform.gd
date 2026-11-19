class_name LocalTerraform
extends RefCounted
## Terraforming (scheduler/terraform.ts, field.json terraform): a village
## reshapes the land near it. A forest cleared (its timber brought home),
## trees planted, a swamp drained: paid at once, the hex's terrain changes
## when the work is done.


## terraformProblem: why `action` can't be done ("" when it can).
static func problem(data: Dictionary, action: String, terrain: Variant, distance: int, taken: bool, busy: bool, held := false) -> String:
	var rules: Dictionary = data.field.terraform
	var def: Dictionary = rules.actions.get(action, {})
	if def.is_empty():
		return "No such work"
	if taken:
		return "Something stands there"
	if def.has("fire") and held:
		return "An army stands there"
	if distance < 1 or distance > int(rules.range):
		return "Land is reshaped within %d hexes of the village" % int(rules.range)
	if busy:
		return "Work is already under way there"
	if terrain == null or not def.from.has(terrain):
		return "That work cannot be done on this land"
	return ""


static func work_at(world: Dictionary, cell: Vector2i) -> Dictionary:
	for w in world.get("terraforms", []):
		if w.cell == cell:
			return w
	return {}


## startTerraform: the work under way, or {"error"} / {"missing"}.
static func start(server: LocalServer, world: Dictionary, village: Dictionary, cell: Vector2i, action: String, at: int) -> Dictionary:
	var data := server.data
	var taken := LocalBattles.taken_hexes(world)
	for f in world.forts:
		taken[LocalLand.key(Vector2i(f.q, f.r))] = true
	# A fire may be set on a bandit camp or a lair, to burn it out.
	var on_camp: bool = data.field.terraform.actions.get(action, {}).has("fire") and world.camps.any(func(c: Dictionary) -> bool:
		return int(c.q) == cell.x and int(c.r) == cell.y and c.kind in ["bandit", "lair"])
	var reason := problem(data, action, world.hexes.get(LocalLand.key(cell)), HexMath.distance(cell, Vector2i(village.q, village.r)),
		taken.has(LocalLand.key(cell)) and not on_camp, not work_at(world, cell).is_empty(), not LocalArmies.armies_holding(world, cell, ["stationed", "engaged"]).is_empty())
	if reason != "":
		return LocalVillage.rule(reason)
	var def: Dictionary = data.field.terraform.actions[action]
	var ledger := LocalLedger.spend(village.state.ledger, at, def.cost)
	if ledger.has("missing"):
		return ledger
	village.state.ledger = ledger
	world.merge({"terraforms": []})
	var work := {"cell": cell, "action": action, "villageId": village.id, "completesAt": LocalTime.ms(at + float(def.hours) * 3600000.0 / world.speed), "generation": 0}
	world.terraforms.append(work)
	server.schedule(world, work.completesAt, "terraform_done", {"q": cell.x, "r": cell.y})
	if def.has("fire"):
		burn_camps(server, world, cell, at)
		LocalDetours.avoid_fire(server, world, cell, int(work.completesAt), at)
		_spread(server, world, work, at)
	return work


## scheduler/terraform.ts burnCamps: a camp on a burning hex is gone; a
## bandit camp's or a lair's survivors flee as a small horde of its front
## from where it stood, and the front hates the more.
static func burn_camps(server: LocalServer, world: Dictionary, cell: Vector2i, at: int) -> void:
	var data := server.data
	for camp in world.camps.duplicate():
		if int(camp.q) != cell.x or int(camp.r) != cell.y:
			continue
		world.camps.erase(camp)
		if not camp.kind in ["bandit", "lair"]:
			continue
		var fled := fleeing(data, camp.units, int(world.seed), int(camp.id))
		var count := 0
		for unit in fled:
			count += int(fled[unit])
		if count > 0:
			var last := LocalBridgeCommands._last_horde(world)
			var wave := {"id": world.next.wave, "index": int(last.index) if not last.is_empty() else 0, "front": camp.front, "status": "scheduled",
				"threat": LocalWaves.threat_of(data, fled), "stance": "offensive", "composition": fled, "initial": fled.duplicate(), "spawnAt": at,
				"spawn": null, "targetVillageId": null, "path": null, "arrivesAt": null, "endsAt": null, "rampageEndsAt": null, "struck": [],
				"ritual": false, "leaderId": null, "hatred": 0.0, "bandOf": last.id if not last.is_empty() else null,
				"errand": {"kind": "fled", "target": null, "from": {"q": int(camp.q), "r": int(camp.r)}}}
			world.next.wave += 1
			world.waves.append(wave)
			# They flee at once (scheduler/waves.ts setOutNow).
			LocalCultists.send(server, world, wave, at)
			for member in world.members:
				LocalInbox.tell(server, world, member.accountId, {"kind": "camp", "tier": "push", "title": "The camp at ({q}, {r}) burns",
					"body": "{count} of them flee the flames and march on the villages.", "vars": {"q": camp.q, "r": camp.r, "count": count}}, at)
		LocalHordes.anger_front(server, world, String(camp.front), float(data.camps.burnt.hatred), at)


## sim/camps.ts fleeing: a seeded share of each kind of the camp's troops.
static func fleeing(data: Dictionary, units: Dictionary, seed_value: int, camp_id: int) -> Dictionary:
	var rules: Dictionary = data.camps.burnt.fleeShare
	var roll := LocalRng.new((seed_value ^ LocalRng.imul(camp_id + 1, 0x2c1b3c6d) ^ 0xf1ee) & 0xffffffff).next()
	var share := float(rules.min) + (float(rules.max) - float(rules.min)) * roll
	var out := {}
	var most := ""
	var most_n := 0
	for unit in units:
		var n := int(units[unit])
		if n <= 0:
			continue
		if most == "" or n > most_n:
			most = unit
			most_n = n
		var fled := LocalWaves.js_round(n * share)
		if fled > 0:
			out[unit] = fled
	if out.is_empty() and most != "":
		out[most] = 1
	return out


## fireCatches: one roll for each neighbouring hex, from the world's seed.
static func fire_catches(seed_value: int, to: Vector2i, at: int, chance: float) -> bool:
	var rng := LocalRng.new((seed_value ^ LocalRng.imul(to.x + 1000, 0x632be5ab) ^ LocalRng.imul(to.y + 1000, 0x5bd1e995) ^ (floori(at / 60000.0) & 0xfffff)) & 0xffffffff)
	return rng.next() < chance


## spreadFire: the fire may spread to each neighbouring hex it could burn
## (never a settlement), spreadHours later.
static func _spread(server: LocalServer, world: Dictionary, work: Dictionary, at: int) -> void:
	var def: Dictionary = server.data.field.terraform.actions[work.action]
	var fire: Dictionary = def.fire
	if int(work.generation) >= int(fire.generations):
		return
	var settled := {}
	for v in world.villages:
		settled[LocalLand.key(Vector2i(v.q, v.r))] = true
	for next in HexMath.neighbors(work.cell):
		var type: Variant = world.hexes.get(LocalLand.key(next))
		if type == null or not def.from.has(type) or settled.has(LocalLand.key(next)):
			continue
		# An army standing there keeps the fire off.
		if not LocalArmies.armies_holding(world, next, ["stationed", "engaged"]).is_empty():
			continue
		if work_at(world, next).get("action") == work.action:
			continue
		if not fire_catches(int(world.seed), next, at, float(fire.spreadChance)):
			continue
		server.schedule(world, LocalTime.ms(at + float(fire.spreadHours) * 3600000.0 / world.speed), "fire_spread",
			{"q": next.x, "r": next.y, "action": work.action, "generation": int(work.generation) + 1, "villageId": work.villageId})


## catchFire: whatever stands there burns, and it burns for its hours.
static func on_fire_spread(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var p: Dictionary = event.payload
	var data := server.data
	var cell := Vector2i(int(p.q), int(p.r))
	var at := int(event.dueAt)
	var def: Dictionary = data.field.terraform.actions.get(p.action, {})
	if not def.has("fire"):
		return
	var type: Variant = world.hexes.get(LocalLand.key(cell))
	if type == null or not def.from.has(type) or world.villages.any(func(v: Dictionary) -> bool: return int(v.q) == cell.x and int(v.r) == cell.y):
		return
	if not LocalArmies.armies_holding(world, cell, ["stationed", "engaged"]).is_empty():
		return
	var there := work_at(world, cell)
	if there.get("action") == p.action:
		return
	if not there.is_empty():
		world.terraforms.erase(there)
	for village in world.villages:
		var plot := ""
		for candidate in LocalVillage.outpost_plots(village.state.plots):
			if LocalVillage.outpost_hex(candidate) == cell:
				plot = candidate
		if plot == "" or int(village.state.plots[plot].level) <= 0:
			continue
		var state: Dictionary = village.state
		while int(state.plots[plot].level) > 0:
			state = LocalVillage.raid_outpost(data, state, plot, at, world.speed)
		village.state = state
		changed.append(["village", village.id])
		LocalInbox.tell(server, world, village.ownerAccountId, {"kind": "outpost_raided", "tier": "push", "title": "Fire burned an outpost of {village}",
			"body": "The outpost at ({q}, {r}) lies in ruins.", "vars": {"village": village.name, "q": cell.x, "r": cell.y}}, at)
	for fort in world.forts.duplicate():
		if int(fort.q) != cell.x or int(fort.r) != cell.y:
			continue
		world.forts.erase(fort)
		LocalInbox.tell(server, world, fort.ownerAccountId, {"kind": "outpost_raided", "tier": "push", "title": "Fire burned your stronghold at ({q}, {r})",
			"body": "Nothing is left of it, nor of its grain.", "vars": {"q": cell.x, "r": cell.y}}, at)
	burn_camps(server, world, cell, at)
	world.merge({"terraforms": []})
	var work := {"cell": cell, "action": String(p.action), "villageId": p.villageId, "completesAt": LocalTime.ms(at + float(def.hours) * 3600000.0 / world.speed), "generation": int(p.generation)}
	world.terraforms.append(work)
	server.schedule(world, work.completesAt, "terraform_done", {"q": cell.x, "r": cell.y})
	LocalDetours.avoid_fire(server, world, cell, int(work.completesAt), at)
	_spread(server, world, work, at)
	changed.append(["world"])


static func on_done(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var cell := Vector2i(int(event.payload.q), int(event.payload.r))
	var work := work_at(world, cell)
	if work.is_empty() or int(work.completesAt) != int(event.dueAt):
		return
	world.terraforms.erase(work)
	var def: Dictionary = server.data.field.terraform.actions.get(work.action, {})
	var terrain: Variant = world.hexes.get(LocalLand.key(cell))
	if not def.is_empty() and terrain != null and def.from.has(terrain):
		world.hexes[LocalLand.key(cell)] = def.from[terrain]
		server.forget_hexes_view(world)
	if work.villageId != null:
		var village := server.find_village(world, int(work.villageId))
		# A fire tells only the one who set it, where they set it.
		if not village.is_empty() and village.ownerAccountId != null and int(work.get("generation", 0)) == 0:
			if def.has("gain"):
				village.state.ledger = LocalLogistics.receive(village.state.ledger, int(event.dueAt), def.gain).ledger
			LocalInbox.tell_owner(server, world, int(village.id), func(name: String) -> Dictionary:
				return {"kind": "build_done", "tier": "digest", "title": "The land near {village} is reshaped", "body": "The work at ({q}, {r}) is done.",
					"vars": {"village": name, "q": cell.x, "r": cell.y}}, int(event.dueAt))
			changed.append(["village", village.id])
	changed.append(["world"])


## The map's terraforms: [q, r, action, villageId, completesAt], by (q, r).
static func view(world: Dictionary) -> Array:
	var out: Array = world.get("terraforms", []).map(func(w: Dictionary) -> Array:
		return [w.cell.x, w.cell.y, w.action, w.villageId, LocalTime.iso(w.completesAt)])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	return out
