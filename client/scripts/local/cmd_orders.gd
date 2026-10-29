class_name LocalOrders
extends RefCounted
## Standing orders for the local engine: server/src/sim/orders.ts,
## commands/orders.ts and scheduler/orders.ts.


## The order as given, or {"error"} (validateOrder).
static func validate(data: Dictionary, spec: Dictionary) -> Dictionary:
	match String(spec.get("kind", "")):
		"train":
			if not data.units.units.has(String(spec.get("unit", ""))):
				return LocalVillage.rule("Unknown unit \"%s\"" % spec.get("unit", ""))
			var batch := float(spec.get("batch", 0))
			if batch != floorf(batch) or batch < 1 or batch > float(data.units.maxBatch):
				return LocalVillage.rule("Batches are 1 to %d" % int(data.units.maxBatch))
			var target := float(spec.get("target", 0))
			if target != floorf(target) or target < batch:
				return LocalVillage.rule("Keep at least one batch")
			return {"kind": "train", "unit": spec.unit, "batch": int(batch), "target": int(target)}
		"rebuild":
			return {"kind": "rebuild"}
		"surplus":
			var share := float(spec.get("share", -1))
			var bounds: Dictionary = data.orders.surplusShare
			if not (share >= float(bounds.min) and share <= float(bounds.max)):
				return LocalVillage.rule("Keep between %d%% and %d%% of storage" % [LocalWaves.js_round(float(bounds.min) * 100), LocalWaves.js_round(float(bounds.max) * 100)])
			return {"kind": "surplus", "share": spec.share}
		"supply":
			var fort_id: Variant = spec.get("fortId")
			var target: Variant = spec.get("target")
			if not (fort_id is int or fort_id is float) or float(fort_id) != floorf(float(fort_id)) or float(fort_id) < 1 \
					or not (target is int or target is float) or float(target) != floorf(float(target)):
				return {"error": "Say which fort or supply point to keep stocked, and how full", "kind": "invalid"}
			var most := maxi(int(data.field.fort.grainCapacity), int(data.field.supplyPoint.grainCapacity))
			if int(target) < int(data.orders.supplyMinLoad) or int(target) > most:
				return LocalVillage.rule("Keep between %d and %d grain there" % [int(data.orders.supplyMinLoad), most])
			return {"kind": "supply", "fortId": int(fort_id), "target": int(target)}
	return {"error": "Unknown order", "kind": "invalid"}


## Standing orders a village may keep (sim/orders.ts ordersLimit).
static func orders_limit(data: Dictionary, hall: int) -> int:
	return int(data.orders.maxPerVillage) + floori(hall / float(data.orders.hallLevelsPerOrder))


static func train_count(spec: Dictionary, have: int) -> int:
	return maxi(0, mini(int(spec.batch), int(spec.target) - have))


## Outposts below the best level they ever had, with nothing queued for them.
static func rebuild_targets(state: Dictionary) -> Array:
	return LocalVillage.outpost_plots(state.plots).filter(func(plot: String) -> bool:
		var p: Dictionary = state.plots[plot]
		return int(p.level) < int(p.get("peak", p.level)) and not state.queue.any(func(item: Dictionary) -> bool: return item.plot == plot))


## What lies above `share` of storage, trimmed to what the caravans at home
## can carry; null when it's too little to bother.
static func surplus_load(data: Dictionary, amounts: Dictionary, capacity: Dictionary, share: float, can_carry: float) -> Variant:
	var above := LocalVillage.resources(func(kind: String) -> int:
		return maxi(0, floori(float(amounts[kind]) - float(capacity[kind]) * share)))
	var total := 0
	for kind in LocalLedger.KINDS:
		total += int(above[kind])
	if total < maxi(1, int(data.orders.minSurplus)) or can_carry <= 0:
		return null
	if total <= can_carry:
		return above
	var scale := can_carry / total
	return LocalVillage.resources(func(kind: String) -> int: return floori(int(above[kind]) * scale))


## The grain to send on a supply route now: what the store lacks of the
## target (counting what is on the way), trimmed to what the village has
## and its caravans at home can carry; 0 when that is too little to bother.
static func supply_load(data: Dictionary, target: float, stored: float, on_the_way: float, capacity: float, grain: float, can_carry: float) -> int:
	var missing := floori(minf(target, capacity) - stored - on_the_way)
	var load := mini(mini(missing, floori(grain)), floori(can_carry))
	return 0 if load < int(data.orders.supplyMinLoad) else load


## Grain on its way into a fort or supply point.
static func grain_on_the_way(world: Dictionary, fort_id: int) -> float:
	var n := 0.0
	for c in world.caravans:
		if c.get("destinationFortId") != null and int(c.destinationFortId) == fort_id and c.status == "outbound":
			n += float(c.cargo.grain)
	return n


static func _check_ms(data: Dictionary, world_speed: float) -> int:
	return LocalWaves.js_round((float(data.orders.checkMinutes) * 60000.0) / world_speed)


static func orders_of(world: Dictionary, village_id: int) -> Array:
	return world.orders.filter(func(o: Dictionary) -> bool: return int(o.villageId) == village_id)


## One order's turn: {state, result}, or {"error"} / {"missing"} to wait.
static func _run_order(server: LocalServer, world: Dictionary, village: Dictionary, state: Dictionary, spec: Dictionary, at: int) -> Dictionary:
	var data := server.data
	match String(spec.kind):
		"rebuild":
			var targets := rebuild_targets(state)
			if targets.is_empty():
				return {"state": state, "result": "Every outpost stands at its best"}
			var rebuilt: Array = []
			for plot in targets:
				# Each rebuild queued keeps its place even if a later one can't be paid for.
				var step := LocalVillage.queue_build(data, state, {"plot": plot}, at, world.speed)
				if step.has("error") or step.has("missing"):
					if rebuilt.is_empty():
						return step
					break
				state = step.state
				var q: Dictionary = step.queued
				server.schedule(world, int(q.completesAt), "build_complete", {"villageId": village.id, "plot": q.plot, "building": q.building, "targetLevel": q.targetLevel})
				var cell := LocalVillage.outpost_hex(plot)
				rebuilt.append("(%d, %d)" % [cell.x, cell.y])
			return {"state": state, "result": "Rebuilding the outpost%s at %s" % ["s" if rebuilt.size() > 1 else "", ", ".join(rebuilt)]}
		"train":
			var name: String = data.units.units.get(spec.unit, {}).get("name", spec.unit)
			var count := train_count(spec, int(LocalVillage.units_fed(state).get(spec.unit, 0)))
			if count == 0:
				return {"state": state, "result": "%d %s kept" % [int(spec.target), name]}
			var owned: int = world.villages.filter(func(v: Dictionary) -> bool: return int(v.ownerAccountId) == int(village.ownerAccountId)).size()
			var queued := LocalVillage.queue_training(data, state, spec.unit, count, at, world.speed, owned)
			if queued.has("error") or queued.has("missing"):
				return queued
			server.schedule(world, LocalVillage.batch_completes_at(queued.batch), "training_complete", {"villageId": village.id})
			return {"state": queued.state, "result": "Training %d %s" % [count, name]}
	var yard := int(state.levels.get(LocalLogistics.CARAVAN_YARD, 0))
	if yard < 1:
		return LocalVillage.rule("Build a Caravan Yard first")
	var out := 0
	for c in world.caravans:
		if int(c.villageId) == int(village.id) and c.status != "done":
			out += int(c.caravans)
	var free := LocalLogistics.caravans_at(data, yard) - out
	var with_state := village.duplicate()
	with_state.state = state
	var capacity := LocalLogistics.caravan_capacity(data, LocalLogistics.effective_bonuses(server, world, with_state))
	if spec.kind == "supply":
		var fort := LocalArmies.find_fort(world, int(spec.fortId))
		if fort.is_empty() or fort.ownerAccountId == null or int(fort.ownerAccountId) != int(village.ownerAccountId):
			return LocalVillage.rule("That fort or supply point is gone")
		var where := "(%d, %d)" % [int(fort.q), int(fort.r)]
		if fort.status != "standing":
			return LocalVillage.rule("The store at %s is still being built" % where)
		var room := LocalArmies.grain_capacity(data, fort.get("kind", "fort"))
		var goal := mini(int(spec.target), int(room))
		var on_the_way := grain_on_the_way(world, int(fort.id))
		if floori(goal - float(fort.grain) - on_the_way) < int(data.orders.supplyMinLoad):
			return {"state": state, "result": "%d grain kept at %s" % [goal, where]}
		if free <= 0:
			return {"state": state, "result": "All caravans are out"}
		var grain := supply_load(data, float(spec.target), float(fort.grain), on_the_way, room, float(LocalLedger.amounts_at(state.ledger, at).grain), free * capacity)
		if grain <= 0:
			return {"state": state, "result": "Waiting for resources"}
		var cargo := {"wood": 0, "stone": 0, "grain": grain, "iron": 0}
		var sent := LocalLogistics.dispatch(server, world, with_state, "deliver", {"destinationVillageId": null, "destinationFortId": fort.id, "load": cargo}, at)
		if sent.has("error"):
			return sent
		LocalLogistics.set_out(server, world, sent, at)
		var stocked := state.duplicate()
		stocked.ledger = LocalLedger.spend(state.ledger, at, cargo)
		return {"state": stocked, "result": "Sent %d grain to %s" % [grain, where]}
	var load: Variant = surplus_load(data, LocalLedger.amounts_at(state.ledger, at), state.ledger.capacity, float(spec.share), free * capacity)
	if load == null:
		return {"state": state, "result": "Nothing above %d%% of storage" % LocalWaves.js_round(float(spec.share) * 100) if free > 0 else "All caravans are out"}
	var caravan := LocalLogistics.dispatch(server, world, with_state, "deliver", {"destinationVillageId": null, "load": load}, at)
	if caravan.has("error"):
		return caravan
	LocalLogistics.set_out(server, world, caravan, at)
	var next := state.duplicate()
	next.ledger = LocalLedger.spend(state.ledger, at, load)
	return {"state": next, "result": "Sent %d to the vault" % int(LocalLogistics.total(load))}


## Runs every order of a village once. Returns whether it has any.
static func run_orders(server: LocalServer, world: Dictionary, village_id: int, at: int) -> bool:
	var orders := orders_of(world, village_id)
	if orders.is_empty():
		return false
	var village := server.find_village(world, village_id)
	var state := LocalVillage.complete_training(village.state, at)
	for order in orders:
		var ran := _run_order(server, world, village, state, order.spec, at)
		var result: String
		if ran.has("missing"):
			result = "Waiting for resources"
		elif ran.has("error"):
			result = "Waiting: %s" % ran.error
		else:
			state = ran.state
			result = ran.result
		order.lastResult = result
		order.lastRunAt = at
	village.state = state
	return true


static func on_orders_check(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var village_id := int(event.payload.villageId)
	if not run_orders(server, world, village_id, int(event.dueAt)):
		return
	server.schedule(world, int(event.dueAt) + _check_ms(server.data, world.speed), "orders_check", {"villageId": village_id})
	changed.append(["village", village_id])
	changed.append(["world"])


## Places a standing order and runs it right away: the order, or {"error"}.
static func place(server: LocalServer, world: Dictionary, village: Dictionary, body: Dictionary, now: int) -> Dictionary:
	var data := server.data
	var spec := validate(data, body)
	if spec.has("error"):
		return spec
	var existing := orders_of(world, int(village.id))
	var limit := orders_limit(data, int(village.state.levels.get(LocalVillage.HALL, 0)))
	if existing.size() >= limit:
		return LocalVillage.rule("A village keeps at most %d standing orders; a bigger Elder's Hall keeps more" % limit)
	if spec.kind == "supply":
		var fort := LocalArmies.find_fort(world, int(spec.fortId))
		if fort.is_empty() or fort.ownerAccountId == null or int(fort.ownerAccountId) != int(village.ownerAccountId):
			return LocalVillage.rule("No fort or supply point of yours there")
	for o in existing:
		if o.spec.kind == spec.kind and (spec.kind != "train" or o.spec.unit == spec.unit) and (spec.kind != "supply" or int(o.spec.fortId) == int(spec.fortId)):
			return LocalVillage.rule("This village already has that order; cancel it first")
	var order := {"id": world.next.order, "villageId": village.id, "spec": spec, "lastResult": null, "lastRunAt": null, "createdAt": now}
	world.next.order += 1
	world.orders.append(order)
	run_orders(server, world, int(village.id), now)
	if not server.pending(world, "orders_check", {"villageId": village.id}):
		server.schedule(world, now + _check_ms(data, world.speed), "orders_check", {"villageId": village.id})
	return order


static func cancel(world: Dictionary, village: Dictionary, order_id: int) -> Dictionary:
	for o in world.orders:
		if int(o.id) == order_id and int(o.villageId) == int(village.id):
			world.orders.erase(o)
			return {"ok": true}
	return {"error": "No such order", "kind": "not_found"}


static func order_view(o: Dictionary) -> Dictionary:
	var view := {"id": o.id, "villageId": o.villageId}
	view.merge(o.spec)
	view.merge({"lastResult": o.lastResult, "lastRunAt": LocalTime.iso(o.lastRunAt) if o.lastRunAt != null else null})
	return view
