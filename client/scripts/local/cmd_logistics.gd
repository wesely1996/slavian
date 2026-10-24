class_name LocalLogistics
extends RefCounted
## Caravans and the Holy City vault for the local engine: server/src/sim/
## logistics.ts, commands/logistics.ts, scheduler/caravans.ts, and the
## caravan ambushes of scheduler/camps.ts.

const CARAVAN_YARD := "caravan_yard"


# --- Rules (sim/logistics.ts) ----------------------------------------------------

static func caravans_at(data: Dictionary, yard_level: int) -> int:
	return yard_level * int(data.logistics.caravan.caravansPerYardLevel)


static func total(amounts: Dictionary) -> float:
	var sum := 0.0
	for kind in LocalLedger.KINDS:
		sum += float(amounts[kind])
	return sum


static func caravan_capacity(data: Dictionary, bonuses: Dictionary = {}) -> int:
	return floori(float(data.logistics.caravan.capacity) * (1.0 + float(bonuses.get("caravanCapacity", 0.0))))


## Caravans needed to carry `load`, or {"error"}.
static func caravans_for(data: Dictionary, load: Dictionary, bonuses: Dictionary = {}) -> Variant:
	for kind in LocalLedger.KINDS:
		var n := float(load[kind])
		if n != floorf(n) or n < 0:
			return LocalVillage.rule("Loads are whole, non-negative amounts")
	var amount := total(load)
	if amount <= 0:
		return LocalVillage.rule("Nothing to carry")
	return ceili(amount / caravan_capacity(data, bonuses))


## The road between two hexes: [{q, r, atMs}], or null when none leads there.
static func road_route(data: Dictionary, land: Dictionary, from: Vector2i, to: Vector2i, hexes_per_hour: float, world_speed: float) -> Variant:
	var move_cost := LocalLand.move_cost_on(data, land)
	var path: Variant = LocalLand.find_path(from, to, move_cost, float(data.field.road.factor))
	if path == null:
		return null
	var ms_per_cost := LocalTime.MS_PER_HOUR / hexes_per_hour / world_speed
	var at_ms := 0.0
	var steps: Array = []
	for i in path.size():
		if i > 0:
			at_ms += float(move_cost.call(path[i - 1], path[i])) * ms_per_cost
		steps.append({"q": path[i].x, "r": path[i].y, "atMs": maxi(i, LocalWaves.js_round(at_ms))})
	return steps


static func caravan_route(data: Dictionary, land: Dictionary, from: Vector2i, to: Vector2i, world_speed: float, bonuses: Dictionary = {}) -> Variant:
	return road_route(data, land, from, to, float(data.logistics.caravan.speed) * (1.0 + float(bonuses.get("caravanSpeed", 0.0))), world_speed)


static func vault_capacity(data: Dictionary, level: int) -> float:
	var v: Dictionary = data.logistics.vault
	return float(v.baseCapacity) * pow(float(v.capacityGrowth), level - 1)


static func vault_upgrade_cost(data: Dictionary, target_level: int) -> Dictionary:
	var v: Dictionary = data.logistics.vault
	return LocalVillage.resources(func(kind: String) -> int:
		return LocalWaves.js_round(float(v.upgradeCost[kind]) * pow(float(v.costGrowth), target_level - 2)))


static func vault_upgrade_ms(data: Dictionary, target_level: int, world_speed: float) -> int:
	var v: Dictionary = data.logistics.vault
	return LocalWaves.js_round((float(v.upgradeSeconds) * pow(float(v.timeGrowth), target_level - 2) * 1000.0) / world_speed)


## Puts `load` into stores holding `amounts` up to `capacity` each.
static func store(amounts: Dictionary, capacity: float, load: Dictionary) -> Dictionary:
	var stored := LocalVillage.resources(func(kind: String) -> float: return minf(float(load[kind]), maxf(0.0, capacity - float(amounts[kind]))))
	return {"amounts": LocalVillage.resources(func(kind: String) -> float: return float(amounts[kind]) + float(stored[kind])),
		"leftover": LocalVillage.resources(func(kind: String) -> float: return float(load[kind]) - float(stored[kind]))}


## Takes up to `request` out of `amounts`.
static func withdraw(amounts: Dictionary, request: Dictionary) -> Dictionary:
	var taken := LocalVillage.resources(func(kind: String) -> float: return minf(float(request[kind]), float(amounts[kind])))
	return {"amounts": LocalVillage.resources(func(kind: String) -> float: return float(amounts[kind]) - float(taken[kind])), "taken": taken}


## A delivery into a village's stores: up to its capacity, the rest left over.
static func receive(ledger: Dictionary, at: int, load: Dictionary) -> Dictionary:
	var settled := LocalLedger.settle(ledger, at)
	var stored := LocalVillage.resources(func(kind: String) -> float:
		return minf(float(load[kind]), maxf(0.0, float(settled.capacity[kind]) - float(settled.amounts[kind]))))
	settled.amounts = LocalVillage.resources(func(kind: String) -> float: return float(settled.amounts[kind]) + float(stored[kind]))
	return {"ledger": settled, "leftover": LocalVillage.resources(func(kind: String) -> float: return float(load[kind]) - float(stored[kind]))}


# --- Commands (commands/logistics.ts) --------------------------------------------

## Sends the escort away with the caravan, or {"error"}.
static func _with_escort(data: Dictionary, state: Dictionary, escort: Dictionary, at: int) -> Dictionary:
	var next := state
	for unit in escort:
		var n := int(escort[unit])
		if n <= 0:
			continue
		var def: Variant = data.units.units.get(unit)
		if def == null or not def.family in ["infantry", "archers", "cavalry"] or unit == "settler":
			return LocalVillage.rule("%s can't guard caravans" % (def.name if def != null else unit))
		next = LocalVillage.send_away(next, unit, n, at)
		if next.has("error"):
			return next
	return next


## The bonuses of a village with its hero (db/heroes.ts effectiveBonuses).
static func effective_bonuses(server: LocalServer, world: Dictionary, village: Dictionary) -> Dictionary:
	var hero := LocalBattles.hero_at(world, int(village.id))
	return LocalHeroes.combine(village.state.bonuses, LocalHeroes.hero_bonuses(server.data, hero)) if not hero.is_empty() else village.state.bonuses.duplicate()


## A caravan ready to set out (dispatchCaravan's checks), or {"error"}.
## Nothing changes until `set_out`, so a later check can still refuse.
static func dispatch(server: LocalServer, world: Dictionary, village: Dictionary, kind: String, order: Dictionary, now: int) -> Dictionary:
	var data := server.data
	var yard := int(village.state.levels.get(CARAVAN_YARD, 0))
	if yard < 1:
		return LocalVillage.rule("Build a Caravan Yard first")
	var bonuses := effective_bonuses(server, world, village)
	var needed: Variant = caravans_for(data, order.load, bonuses)
	if needed is Dictionary:
		return needed
	var out := 0
	for c in world.caravans:
		if int(c.villageId) == int(village.id) and c.status != "done":
			out += int(c.caravans)
	var free := caravans_at(data, yard) - out
	if int(needed) > free:
		return LocalVillage.rule("That takes %d caravan%s; %d at home" % [needed, "" if int(needed) == 1 else "s", maxi(0, free)])
	var to := Vector2i.ZERO
	if order.destinationVillageId != null:
		if int(order.destinationVillageId) == int(village.id):
			return LocalVillage.rule("Send it to another village")
		var destination := server.find_village(world, int(order.destinationVillageId))
		if destination.is_empty():
			return {"error": "No such village in this world", "kind": "not_found"}
		to = Vector2i(destination.q, destination.r)
	var path: Variant = caravan_route(data, LocalHordes.land_of(world), Vector2i(village.q, village.r), to, world.speed, bonuses)
	if path == null:
		return LocalVillage.rule("No road leads there")
	var travel := int(path[-1].atMs)
	var escort := {}
	for unit in order.get("escort", {}):
		if int(order.escort[unit]) > 0:
			escort[unit] = int(order.escort[unit])
	return {"villageId": village.id, "destinationVillageId": order.destinationVillageId, "kind": kind,
		"caravans": needed, "cargo": order.load.duplicate(), "carriedBack": null, "status": "outbound", "path": path, "departsAt": now,
		"arrivesAt": now + travel, "returnsAt": now + 2 * travel, "escort": escort, "ambush": null}


static func set_out(server: LocalServer, world: Dictionary, caravan: Dictionary, now: int) -> Dictionary:
	caravan.id = world.next.caravan
	world.next.caravan += 1
	world.caravans.append(caravan)
	server.schedule(world, int(caravan.arrivesAt), "caravan_arrive", {"caravanId": caravan.id})
	plan_ambushes(server, world, caravan, "out", now)
	return caravan


## Loads resources and sends them to the vault or another village.
static func send_caravan(server: LocalServer, world: Dictionary, village: Dictionary, body: Dictionary, now: int) -> Dictionary:
	var order := _order(body)
	if order.has("error"):
		return order
	var escorted := _with_escort(server.data, village.state, order.escort, now)
	if escorted.has("error"):
		return escorted
	var caravan := dispatch(server, world, village, "deliver", order, now)
	if caravan.has("error"):
		return caravan
	var ledger := LocalLedger.spend(escorted.ledger, now, order.load)
	if ledger.has("missing"):
		# The server had already inserted the caravan: rolled back, its id
		# stays used (sequences aren't transactional).
		world.next.caravan += 1
		return ledger
	escorted.ledger = ledger
	set_out(server, world, caravan, now)
	var destination: Dictionary = server.find_village(world, int(order.destinationVillageId)) if order.destinationVillageId != null else {}
	var gift: bool = destination.is_empty() or int(destination.ownerAccountId) != int(village.ownerAccountId)
	return {"state": escorted, "caravan": caravan, "onboarding": "gift" if gift else ""}


## Sends empty caravans to the vault to bring back `load`.
static func fetch_from_vault(server: LocalServer, world: Dictionary, village: Dictionary, body: Dictionary, now: int) -> Dictionary:
	var order := _order(body)
	if order.has("error"):
		return order
	order.destinationVillageId = null
	var state := _with_escort(server.data, village.state, order.escort, now)
	if state.has("error"):
		return state
	var caravan := dispatch(server, world, village, "fetch", order, now)
	if caravan.has("error"):
		return caravan
	return {"state": state, "caravan": set_out(server, world, caravan, now)}


## The request body as an order: {destinationVillageId, load, escort}.
static func _order(body: Dictionary) -> Dictionary:
	var load: Variant = body.get("load")
	if not load is Dictionary:
		return {"error": "load is required", "kind": "invalid"}
	var full := {}
	for kind in LocalLedger.KINDS:
		full[kind] = load.get(kind, 0)
	var escort: Variant = body.get("escort", {})
	return {"destinationVillageId": body.get("destinationVillageId"), "load": full, "escort": escort if escort is Dictionary else {}}


## Any member can start the vault's next level, paid from the vault.
static func upgrade_vault(server: LocalServer, world: Dictionary, now: int) -> Dictionary:
	var data := server.data
	var vault: Dictionary = world.vault
	if vault.upgradingTo != null:
		return LocalVillage.rule("The vault is already being enlarged")
	if int(vault.level) >= int(data.logistics.vault.maxLevel):
		return LocalVillage.rule("The vault is as large as it gets")
	var target := int(vault.level) + 1
	var cost := vault_upgrade_cost(data, target)
	var missing: Array = LocalLedger.KINDS.filter(func(kind: String) -> bool: return float(vault.amounts[kind]) < float(cost[kind]))
	if not missing.is_empty():
		return LocalVillage.rule("The vault needs more %s for that" % ", ".join(missing))
	var completes_at := now + vault_upgrade_ms(data, target, world.speed)
	vault.amounts = withdraw(vault.amounts, cost).amounts
	vault.upgradingTo = target
	vault.upgradeCompletesAt = completes_at
	server.schedule(world, completes_at, "vault_upgrade", {})
	return vault


# --- The scheduler (scheduler/caravans.ts) ---------------------------------------

static func find_caravan(world: Dictionary, id: int) -> Dictionary:
	for c in world.caravans:
		if int(c.id) == id:
			return c
	return {}


static func on_caravan_arrive(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var data := server.data
	var caravan := find_caravan(world, int(event.payload.caravanId))
	if caravan.is_empty() or caravan.status != "outbound":
		return
	var carried_back := {"wood": 0, "stone": 0, "grain": 0, "iron": 0}
	if caravan.destinationVillageId == null:
		var vault: Dictionary = world.vault
		if caravan.kind == "deliver":
			var stored := store(vault.amounts, vault_capacity(data, int(vault.level)), caravan.cargo)
			vault.amounts = stored.amounts
			carried_back = stored.leftover
		else:
			var taken := withdraw(vault.amounts, caravan.cargo)
			vault.amounts = taken.amounts
			carried_back = taken.taken
	else:
		var village := server.find_village(world, int(caravan.destinationVillageId))
		var received := receive(village.state.ledger, int(event.dueAt), caravan.cargo)
		village.state.ledger = received.ledger
		carried_back = received.leftover
		changed.append(["village", village.id])
		var sender := server.find_village(world, int(caravan.villageId))
		if int(sender.ownerAccountId) != int(village.ownerAccountId):
			LocalInbox.tell(server, world, village.ownerAccountId, {"kind": "caravan_delivered", "tier": "digest",
				"title": "A caravan from {sender} reached {village}", "body": "It brought {amount} resources.",
				"vars": {"sender": sender.name, "village": village.name, "amount": total(caravan.cargo) - total(received.leftover)}}, int(event.dueAt))
	caravan.status = "returning"
	caravan.carriedBack = carried_back
	plan_ambushes(server, world, caravan, "back", int(event.dueAt))
	server.schedule(world, int(caravan.returnsAt), "caravan_return", {"caravanId": caravan.id})
	changed.append(["world"])


## Home again. What doesn't fit in a full storehouse is lost.
static func on_caravan_return(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var caravan := find_caravan(world, int(event.payload.caravanId))
	if caravan.is_empty() or caravan.status != "returning":
		return
	var village := server.find_village(world, int(caravan.villageId))
	var back: Variant = caravan.carriedBack
	var received := receive(village.state.ledger, int(event.dueAt), back if back != null else {"wood": 0, "stone": 0, "grain": 0, "iron": 0})
	var state: Dictionary = village.state
	for unit in caravan.escort:
		state = LocalVillage.return_home(state, unit, int(caravan.escort[unit]))
	state = state.duplicate()
	state.ledger = received.ledger
	village.state = state
	caravan.status = "done"
	changed.append(["village", village.id])
	changed.append(["world"])


static func on_vault_upgrade(_server: LocalServer, world: Dictionary, _event: Dictionary, changed: Array) -> void:
	var vault: Dictionary = world.vault
	if vault.upgradingTo == null:
		return
	vault.level = vault.upgradingTo
	vault.upgradingTo = null
	vault.upgradeCompletesAt = null
	changed.append(["world"])


# --- Ambushes (scheduler/camps.ts) -----------------------------------------------

static func _has_goods(r: Variant) -> bool:
	return r != null and r.values().any(func(n: Variant) -> bool: return float(n) > 0)


## A caravan sets out ("out") or turns for home ("back"): the first camp it
## passes close to ambushes it.
static func plan_ambushes(server: LocalServer, world: Dictionary, caravan: Dictionary, leg: String, from: int) -> void:
	var goods: Variant = caravan.cargo if leg == "out" else caravan.carriedBack
	if not _has_goods(goods):
		return
	var travel := int(caravan.path[-1].atMs)
	var path: Array = caravan.path
	if leg != "out":
		path = []
		for i in range(caravan.path.size() - 1, -1, -1):
			var s: Dictionary = caravan.path[i]
			path.append({"q": s.q, "r": s.r, "atMs": travel - int(s.atMs)})
	var best: Dictionary = {}
	var camps: Array = world.camps.filter(func(c: Dictionary) -> bool: return c.status == "active")
	camps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	for camp in camps:
		var cell := Vector2i(camp.q, camp.r)
		var step: Dictionary = {}
		for s in path:
			if HexMath.distance(Vector2i(s.q, s.r), cell) <= int(server.data.camps.ambush.reach):
				step = s
				break
		if step.is_empty():
			continue
		var at := int(caravan.departsAt if leg == "out" else caravan.arrivesAt) + int(step.atMs)
		if at < from:
			continue
		if best.is_empty() or at < int(best.at):
			best = {"campId": camp.id, "at": at}
	if best.is_empty():
		return
	if server.pending(world, "caravan_ambush", {"caravanId": caravan.id, "leg": leg}):
		return
	server.schedule(world, int(best.at), "caravan_ambush", {"caravanId": caravan.id, "campId": best.campId, "leg": leg})


## A new camp: caravans already on the road near it may be ambushed.
static func plan_ambushes_for(server: LocalServer, world: Dictionary, at: int) -> void:
	for caravan in world.caravans:
		if caravan.status == "done" or caravan.ambush != null:
			continue
		plan_ambushes(server, world, caravan, "out" if caravan.status == "outbound" else "back", at)


## sim/camps.ts ambush: {beatenOff, lost, escortLosses}.
static func ambush(data: Dictionary, escort: Dictionary, escort_stats: Callable, camp: Dictionary, front: String, cargo: Dictionary) -> Dictionary:
	var rules: Dictionary = data.camps.ambush
	var strength := func(units: Dictionary, stats: Callable) -> float:
		var sum := 0.0
		for unit in units:
			sum += int(units[unit]) * float(stats.call(unit).attack)
		return sum
	var own: float = strength.call(escort, escort_stats)
	var theirs: float = strength.call(camp, LocalBattle.enemy_stats(data, front))
	if own > 0 and own >= theirs * float(rules.escortRatio):
		return {"beatenOff": true, "lost": {"wood": 0, "stone": 0, "grain": 0, "iron": 0}, "escortLosses": {}}
	var losses := {}
	for unit in escort:
		var dead := ceili(int(escort[unit]) * float(rules.escortLoss))
		if dead > 0:
			losses[unit] = dead
	return {"beatenOff": false, "lost": LocalVillage.resources(func(kind: String) -> int: return floori(float(cargo[kind]) * float(rules.cargoShare))),
		"escortLosses": losses}


static func on_caravan_ambush(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var data := server.data
	var p: Dictionary = event.payload
	var caravan := find_caravan(world, int(p.caravanId))
	var camp: Dictionary = {}
	for c in world.camps:
		if int(c.id) == int(p.campId):
			camp = c
	var expected := "outbound" if p.leg == "out" else "returning"
	if caravan.is_empty() or caravan.status != expected or caravan.ambush != null or camp.is_empty() or camp.status != "active":
		return
	var goods: Dictionary = caravan.cargo if p.leg == "out" else (caravan.carriedBack if caravan.carriedBack != null else {"wood": 0, "stone": 0, "grain": 0, "iron": 0})
	var village := server.find_village(world, int(caravan.villageId))
	var result := ambush(data, caravan.escort, LocalBattle.player_stats(data, village.state.bonuses, false), camp.units, camp.front, goods)
	var left := LocalVillage.resources(func(kind: String) -> float: return float(goods[kind]) - float(result.lost[kind]))
	var escort := {}
	for unit in caravan.escort:
		var n := int(caravan.escort[unit]) - int(result.escortLosses.get(unit, 0))
		if n > 0:
			escort[unit] = n
	if not result.escortLosses.is_empty():
		var state: Dictionary = village.state
		for unit in result.escortLosses:
			state = LocalVillage.lose_away(data, state, unit, int(result.escortLosses[unit]), int(event.dueAt), world.speed)
		village.state = state
		changed.append(["village", village.id])
	caravan.ambush = {"campId": camp.id, "q": camp.q, "r": camp.r, "at": LocalTime.iso(int(event.dueAt)), "beatenOff": result.beatenOff,
		"lost": result.lost, "escortLosses": result.escortLosses}
	if p.leg == "out":
		caravan.cargo = left
	else:
		caravan.carriedBack = left
	caravan.escort = escort
	LocalInbox.tell(server, world, village.ownerAccountId, {"kind": "ambush", "tier": "digest" if result.beatenOff else "push",
		"title": "A caravan from {village} beat off an ambush" if result.beatenOff else "A caravan from {village} was ambushed",
		"body": "Its escort drove off the {enemy} at ({q}, {r})." if result.beatenOff else "It lost {lost} of its load near ({q}, {r}).",
		"vars": {"village": village.name, "enemy": "beasts" if camp.kind == "lair" else "bandits", "q": camp.q, "r": camp.r,
			"lost": int(total(result.lost))}}, int(event.dueAt))
	changed.append(["world"])


# --- Views (api/views.ts) ----------------------------------------------------------

## On the road, plus the five most recent finished trips, newest first.
static func caravans_view(world: Dictionary) -> Array:
	var on_road: Array = world.caravans.filter(func(c: Dictionary) -> bool: return c.status != "done")
	var done: Array = world.caravans.filter(func(c: Dictionary) -> bool: return c.status == "done")
	done.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.returnsAt) > int(b.returnsAt))
	var shown: Array = on_road + done.slice(0, 5)
	shown.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.departsAt) > int(b.departsAt) or (int(a.departsAt) == int(b.departsAt) and int(a.id) > int(b.id)))
	return shown.map(caravan_view)


static func caravan_view(c: Dictionary) -> Dictionary:
	return {"id": c.id, "villageId": c.villageId, "destinationVillageId": c.destinationVillageId, "kind": c.kind, "caravans": c.caravans,
		"cargo": c.cargo, "carriedBack": c.carriedBack, "status": c.status, "path": c.path.map(func(s: Dictionary) -> Array: return [s.q, s.r, s.atMs]),
		"departsAt": LocalTime.iso(c.departsAt), "arrivesAt": LocalTime.iso(c.arrivesAt), "returnsAt": LocalTime.iso(c.returnsAt),
		"escort": c.escort, "ambush": c.ambush}


static func vault_view(data: Dictionary, vault: Dictionary) -> Dictionary:
	return {"level": vault.level, "amounts": vault.amounts, "capacity": vault_capacity(data, int(vault.level)), "upgradingTo": vault.upgradingTo,
		"upgradeCompletesAt": LocalTime.iso(vault.upgradeCompletesAt) if vault.upgradeCompletesAt != null else null}


# --- Abandoning a village (commands/village.ts abandonVillageCommand) ---------

## Gives up a quiet village: a share of what stood there goes to the vault,
## its garrison and the hero standing there move to the owner's nearest other
## standing village, and the village is gone (with what the server's rows
## lose or forget along with it). {} or {"error"}.
static func abandon_village(server: LocalServer, world: Dictionary, village: Dictionary, now: int) -> Dictionary:
	var data := server.data
	var id := int(village.id)
	if village.refuge:
		return LocalVillage.rule("A refugee camp is not yours to abandon")
	var home := Vector2i(village.q, village.r)
	var to: Dictionary = {}
	for v in world.villages:
		if int(v.id) != id and v.ownerAccountId != null and int(v.ownerAccountId) == int(village.ownerAccountId) and v.ruin == null:
			if to.is_empty() or HexMath.distance(Vector2i(v.q, v.r), home) < HexMath.distance(Vector2i(to.q, to.r), home):
				to = v
	if to.is_empty():
		return LocalVillage.rule("Its people need another standing village of yours to move to")
	if village.state.besieged or world.battles.any(func(b: Dictionary) -> bool: return b.villageId != null and int(b.villageId) == id and b.status == "ongoing"):
		return LocalVillage.rule("Not while a battle is fought there")
	if world.waves.any(func(w: Dictionary) -> bool: return w.targetVillageId != null and int(w.targetVillageId) == id and w.status in ["marching", "arrived", "battling", "razing"]):
		return LocalVillage.rule("A horde is on its way there")
	var state := LocalVillage.complete_training(village.state, now)
	if not state.queue.is_empty() or not state.training.is_empty():
		return LocalVillage.rule("Wait for its builds and training to finish")
	if state.away.values().any(func(n: Variant) -> bool: return int(n) > 0):
		return LocalVillage.rule("Wait for everyone away to come home")
	if world.caravans.any(func(c: Dictionary) -> bool:
		return c.status != "done" and (int(c.villageId) == id or (c.destinationVillageId != null and int(c.destinationVillageId) == id))):
		return LocalVillage.rule("Not while caravans are on the road to or from it")
	if world.armies.any(func(a: Dictionary) -> bool:
		return a.status != "done" and (int(a.homeVillageId) == id or (a.targetVillageId != null and int(a.targetVillageId) == id))):
		return LocalVillage.rule("Not while armies march from it, to it or stand guard there")
	# (Its standing orders' checks go with it.)
	var its_own := func(e: Dictionary) -> bool: return e.status == "pending" and e.payload.get("villageId") != null and int(e.payload.villageId) == id
	if world.events.any(func(e: Dictionary) -> bool: return its_own.call(e) and e.type != "orders_check"):
		return LocalVillage.rule("It still has work under way")
	var hero: Dictionary = {}
	for h in world.heroes:
		if h.villageId != null and int(h.villageId) == id:
			hero = h
	if not hero.is_empty() and hero.status == "traveling":
		return LocalVillage.rule("%s is on the way there" % hero.name)

	if LocalVillage.research_per_hour(data, village.state.plots, world.speed) > 0:
		LocalResearch.settle_points(server, world, int(village.ownerAccountId), now)
	var refund := LocalVillage.refund_of(data, village.state.plots, float(data.buildings.village.abandonRefund))
	world.vault.amounts = store(world.vault.amounts, vault_capacity(data, int(world.vault.level)), refund).amounts
	to.state = LocalVillage.join_garrison(data, LocalVillage.complete_training(to.state, now), state.garrison, now, world.speed)
	if not hero.is_empty():
		hero.villageId = to.id
	# What goes with the village's row (ON DELETE CASCADE), and what forgets it
	# (ON DELETE SET NULL).
	var other := func(key: String) -> Callable:
		return func(row: Dictionary) -> bool: return row.get(key) == null or int(row[key]) != id
	world.events = world.events.filter(func(e: Dictionary) -> bool: return not its_own.call(e))
	world.villages = world.villages.filter(other.call("id"))
	for list in ["battles", "raids", "missions", "orders"]:
		world[list] = world[list].filter(other.call("villageId"))
	world.caravans = world.caravans.filter(func(c: Dictionary) -> bool: return other.call("villageId").call(c) and other.call("destinationVillageId").call(c))
	world.expeditions = world.expeditions.filter(other.call("villageId"))
	world.armies = world.armies.filter(func(a: Dictionary) -> bool: return other.call("homeVillageId").call(a) and other.call("targetVillageId").call(a))
	for pair in [["expeditions", "foundedVillageId"], ["research", "villageId"], ["forts", "villageId"], ["rivers", "builtBy"], ["roads", "builtBy"],
			["leaders", "grudgeVillageId"], ["waves", "targetVillageId"]]:
		for row in world[pair[0]]:
			if row.get(pair[1]) != null and int(row[pair[1]]) == id:
				row[pair[1]] = null
	return {}
