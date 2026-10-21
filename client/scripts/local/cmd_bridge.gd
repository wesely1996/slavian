class_name LocalBridgeCommands
extends RefCounted
## The Kalinov Bridge, Ritual Night and the end of a run for the local
## engine: server/src/scheduler/bridge.ts, scheduler/ritual.ts, revealLair
## (scheduler/camps.ts), revealSite (scheduler/sites.ts) and db/runs.ts.


## Takes what the open stage still needs from what is offered (sim/bridge.ts
## donate): {bridge, taken, embers}, or {"error"}.
static func donate(data: Dictionary, bridge: Dictionary, resources: Dictionary, embers: int) -> Dictionary:
	if bridge.status != "open":
		return LocalVillage.rule("This stage is being raised" if bridge.status == "raising" else "The bridge stands")
	var need := LocalBridge.needs(data, bridge)
	var taken := LocalVillage.resources(func(kind: String) -> float: return maxf(0.0, minf(float(resources[kind]), float(need.resources[kind]))))
	var given := maxi(0, mini(embers, int(need.embers)))
	if LocalLedger.KINDS.all(func(k: String) -> bool: return float(taken[k]) == 0.0) and given == 0:
		return LocalVillage.rule("The stage needs none of that")
	var next := bridge.duplicate(true)
	next.donated = LocalVillage.resources(func(kind: String) -> float: return float(bridge.donated[kind]) + float(taken[kind]))
	next.embers = int(bridge.embers) + given
	return {"bridge": next, "taken": taken, "embers": given}


## Moves resources (and Ember) from the group's vault into the open stage.
static func donate_command(server: LocalServer, world: Dictionary, body: Dictionary, now: int) -> Dictionary:
	if world.status != "running":
		return LocalVillage.rule("This world is not running")
	var data := server.data
	var resources := {}
	var offered: Dictionary = body.get("resources", {})
	for kind in LocalLedger.KINDS:
		resources[kind] = offered.get(kind, 0)
	var embers := int(body.get("embers", 0))
	var from_vault := LocalLogistics.withdraw(world.vault.amounts, resources)
	if embers > int(world.embers):
		return LocalVillage.rule("The group has %d Svarog's Ember" % int(world.embers))
	var result := donate(data, world.bridge, from_vault.taken, embers)
	if result.has("error"):
		return result
	world.vault.amounts = LocalLogistics.withdraw(world.vault.amounts, result.taken).amounts
	world.embers = int(world.embers) - int(result.embers)
	LocalBattles.settle_bridge(server, world, result.bridge, now)
	return world.bridge


## Forges the ritual torc from the group's Ember (the ritual quest).
static func ritual_command(server: LocalServer, world: Dictionary, now: int) -> Dictionary:
	if world.status != "running":
		return LocalVillage.rule("This world is not running")
	var done: Variant = LocalBridge.complete_quest(server.data, world.bridge, "ritual", now)
	if done == null:
		return LocalVillage.rule("No stage needs the ritual torc now")
	var cost := int(server.data.bridge.ritualEmbers)
	if int(world.embers) < cost:
		return LocalVillage.rule("The torc takes %d Svarog's Ember" % cost)
	world.embers = int(world.embers) - cost
	LocalBattles.settle_bridge(server, world, done, now)
	return world.bridge


## The stage stands: on to the next (or the bridge is complete).
static func raised(data: Dictionary, bridge: Dictionary, at: int, sanctity: int) -> Dictionary:
	var stage := int(bridge.stage) + 1
	if stage >= data.bridge.stages.size():
		var done := bridge.duplicate(true)
		done.merge({"stage": stage, "status": "complete", "raisedAt": null, "quests": {}}, true)
		return done
	var next := LocalBridge.new_bridge(at, sanctity)
	next.stage = stage
	return next


static func on_bridge_raised(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var data := server.data
	var bridge: Dictionary = world.bridge
	var at := int(event.dueAt)
	if bridge.status != "raising" or bridge.raisedAt == null or LocalTime.parse(bridge.raisedAt) > at:
		return
	var next := raised(data, bridge, at, int(world.sanctity))
	world.bridge = next
	changed.append(["world"])
	if next.status == "complete":
		call_ritual_night(server, world, at)
	# A relic is wanted and every ruin has been searched: one more is remembered.
	var stage: Variant = LocalBridge.current_stage(data, next)
	if stage != null and stage.quests.any(func(q: Dictionary) -> bool: return q.kind == "lair"):
		reveal_lair(server, world, at)
	if stage != null and stage.quests.any(func(q: Dictionary) -> bool: return q.kind == "site"):
		reveal_site(server, world)


## When the bridge wants a lair cleared and none stands, the North sends one
## by the road of its latest horde.
static func reveal_lair(server: LocalServer, world: Dictionary, at: int) -> bool:
	var data := server.data
	if world.camps.any(func(c: Dictionary) -> bool: return c.status == "active" and c.kind == "lair"):
		return false
	var wave: Dictionary = {}
	for w in world.waves:
		if w.front == "north" and w.path != null and (wave.is_empty() or int(w.index) > int(wave.index)):
			wave = w
	if wave.is_empty():
		return false
	var cells := LocalCamps.spawn_sites(data, world.hexes, wave.path, world.villages.map(func(v: Dictionary) -> Vector2i: return Vector2i(v.q, v.r)),
		LocalBattles.occupied_hexes(world), LocalWaves.rng_for(int(world.seed), int(wave.index), 0x1a), 1)
	if cells.is_empty():
		return false
	var cell: Vector2i = cells[0]
	var units := LocalWaves.compose_wave(data, "north", int(wave.index), LocalCamps.camp_size(data, int(wave.index)), int(world.seed) ^ 0x1a1, world.members.size())
	LocalBattles.create_camp(server, world, {"kind": "lair", "front": "north", "q": cell.x, "r": cell.y, "units": units, "waveId": wave.id}, at)
	return true


## When the bridge asks for a relic and every site has been searched, a new
## site appears, away from villages, camps and the other sites.
static func reveal_site(server: LocalServer, world: Dictionary) -> bool:
	var data := server.data
	if world.sites.any(func(s: Dictionary) -> bool: return s.status == "unexplored"):
		return false
	var taken: Array = world.sites.map(func(s: Dictionary) -> Vector2i: return Vector2i(s.q, s.r))
	for c in world.camps:
		if c.status == "active":
			taken.append(Vector2i(c.q, c.r))
	var spacing := int(data.sites.placement.spacing)
	var seed_value: int = (int(world.seed) ^ (world.sites.size() * 0x9e37)) & 0xffffffff
	var candidates := LocalSites.place_sites(data, world.hexes, int(world.radius), world.villages.map(func(v: Dictionary) -> Vector2i: return Vector2i(v.q, v.r)),
		seed_value, world.members.size())
	for c in candidates:
		if taken.all(func(t: Vector2i) -> bool: return HexMath.distance(t, Vector2i(c.q, c.r)) >= spacing):
			world.sites.append({"id": world.next.site, "kind": c.kind, "q": c.q, "r": c.r, "guardians": c.guardians, "guardiansSeen": false,
				"status": "unexplored", "exploredBy": null, "find": null, "exploredAt": null})
			world.next.site += 1
			return true
	return false


## The bridge is whole: the waves still to come are replaced by one horde
## from every active front, setting out together (after quiet hours).
static func call_ritual_night(server: LocalServer, world: Dictionary, at: int) -> void:
	var data := server.data
	var rules: Dictionary = data.bridge.ritualNight
	var spawn_at := LocalHordes.after_quiet(world, LocalTime.ms(at + (float(rules.delayHours) * LocalTime.MS_PER_HOUR) / world.speed))
	for w in world.waves:
		if w.status == "scheduled":
			w.status = "dispersed"
	world.ritualAt = spawn_at
	var fronts := LocalWaves.wave_fronts(data, world.activeFronts)
	var first := -1
	for w in world.waves:
		first = maxi(first, int(w.index))
	first += 1
	for i in fronts.size():
		var index := first + i
		var ctx := {"seed": world.seed, "activeFronts": world.activeFronts, "playerCount": world.members.size(), "startedAt": world.startedAt,
			"worldSpeed": world.speed, "sizeFactor": LocalWaves.wave_factor(data, world.difficulty, server._group_power(world, index)) * float(rules.sizeFactor)}
		var planned := LocalWaves.plan_wave(data, ctx, index, null)
		var wave := {"id": world.next.wave, "index": planned.index, "front": planned.front, "status": "scheduled", "threat": planned.threat,
			"stance": planned.stance, "composition": planned.composition, "initial": planned.composition.duplicate(), "spawnAt": spawn_at,
			"spawn": null, "targetVillageId": null, "path": null, "arrivesAt": null, "endsAt": null, "rampageEndsAt": null, "struck": [],
			"ritual": true, "leaderId": null}
		world.next.wave += 1
		world.waves.append(wave)
		server.schedule(world, spawn_at, "wave_spawn", {"waveId": wave.id})
	server.schedule(world, LocalTime.ms(spawn_at + (float(rules.checkHours) * LocalTime.MS_PER_HOUR) / world.speed), "ritual_check", {})


## Until Ritual Night's last horde is done; then, if the city stands, the run is won.
static func on_ritual_check(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	if world.status != "running":
		return
	var at := int(event.dueAt)
	var left: int = world.waves.filter(func(w: Dictionary) -> bool: return w.ritual and not w.status in ["dispersed", "defeated", "settled"]).size()
	if left > 0:
		server.schedule(world, LocalTime.ms(at + (float(server.data.bridge.ritualNight.checkHours) * LocalTime.MS_PER_HOUR) / world.speed), "ritual_check", {})
		return
	world.status = "won"
	world.endedAt = at
	changed.append(["world"])


## How a finished run went (db/runs.ts runSummary), or null while it runs.
static func run_summary(world: Dictionary) -> Variant:
	if not world.status in ["won", "lost"]:
		return null
	var end := int(world.endedAt if world.endedAt != null else world.startedAt)
	var members: Array = []
	for m in world.members:
		var mine: Array = world.villages.filter(func(v: Dictionary) -> bool: return int(v.ownerAccountId) == int(m.accountId))
		members.append({"accountId": m.accountId, "displayName": m.displayName,
			"villages": mine.filter(func(v: Dictionary) -> bool: return v.refuge != true).size(),
			"villagesLost": mine.filter(func(v: Dictionary) -> bool: return v.ruin != null).size()})
	var count := func(list: Array, keep: Callable) -> int: return list.filter(keep).size()
	var founded := 0
	var lost := 0
	for m in members:
		founded += int(m.villages)
		lost += int(m.villagesLost)
	return {
		"outcome": world.status,
		"days": LocalWaves.js_round((float(end - int(world.startedAt)) * world.speed) / 86400000.0 * 10) / 10.0,
		"wavesBeaten": count.call(world.waves, func(w: Dictionary) -> bool: return w.status == "defeated"),
		"wavesFaced": count.call(world.waves, func(w: Dictionary) -> bool: return w.spawn != null),
		"battlesWon": count.call(world.battles, func(b: Dictionary) -> bool: return b.status in ["defended", "cleared", "repelled"]),
		"campsCleared": count.call(world.camps, func(c: Dictionary) -> bool: return c.status == "cleared"),
		"sitesExplored": count.call(world.sites, func(s: Dictionary) -> bool: return s.status == "explored"),
		"scrolls": world.lore.size(),
		"villagesFounded": founded,
		"villagesLost": lost,
		"members": members,
	}
