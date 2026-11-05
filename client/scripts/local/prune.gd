class_name LocalPrune
extends RefCounted
## Daily pruning for the local engine (server/src/scheduler/prune.ts): once
## a day a running world forgets what is done and more than PRUNE_HOURS old,
## so its save (and its view) keeps small. Battles won and camps cleared are
## tallied first, for the run's summary.

const PRUNE_HOURS := 24
const PRUNE_MS := PRUNE_HOURS * 3600000


## A running world has its next pruning planned.
static func ensure(server: LocalServer, world: Dictionary, now: int) -> void:
	if world.status != "running" or world.startedAt == null:
		return
	if world.events.any(func(e: Dictionary) -> bool: return e.status == "pending" and e.type == "world_prune"):
		return
	var n := maxi(1, floori(float(now - int(world.startedAt)) / PRUNE_MS) + 1)
	server.schedule(world, int(world.startedAt) + n * PRUNE_MS, "world_prune", {})


static func on_world_prune(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	if world.status != "running":
		return
	var at := int(event.dueAt)
	var cutoff := at - PRUNE_MS
	var old := func(t: Variant) -> bool: return t != null and int(t) < cutoff
	var pruned: Dictionary = world.get("pruned", {})
	var won := 0
	var kept: Array = []
	for b in world.battles:
		if b.status != "ongoing" and old.call(b.get("endedAt")):
			if b.status in ["defended", "cleared", "repelled"]:
				won += 1
		else:
			kept.append(b)
	world.battles = kept
	var cleared := 0
	kept = []
	for c in world.camps:
		if c.status == "cleared" and old.call(c.get("createdAt")):
			cleared += 1
		else:
			kept.append(c)
	world.camps = kept
	world.pruned = {"battlesWon": int(pruned.get("battlesWon", 0)) + won, "campsCleared": int(pruned.get("campsCleared", 0)) + cleared}
	world.raids = world.raids.filter(func(r: Dictionary) -> bool: return not old.call(r.at))
	world.notifications = world.notifications.filter(func(n: Dictionary) -> bool: return not old.call(n.createdAt))
	for list in ["caravans", "missions", "expeditions", "ruinSearches"]:
		world[list] = world.get(list, []).filter(func(x: Dictionary) -> bool: return not (x.status == "done" and old.call(x.returnsAt)))
	world.armies = world.armies.filter(func(a: Dictionary) -> bool:
		return not (a.status == "done" and old.call(a.returnsAt if a.get("returnsAt") != null else a.arrivesAt)))
	server.schedule(world, at + PRUNE_MS, "world_prune", {})
	changed.append(["world"])
