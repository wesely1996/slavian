class_name LocalEvents
extends RefCounted
## Daily map events for the local engine (server/src/sim/events.ts and
## scheduler/mapEvents.ts): each game day after the first, captives held in
## a camp or a hard ruin rise near one of the players' villages, and go
## after a while unless an army is on its way.


## The event of `day`, or {} when there is nowhere to put it: {kind, cell,
## front, guards, reward} for captives, {kind, cell, site} for a ruin.
static func plan(data: Dictionary, world: Dictionary, villages: Array, day: int) -> Dictionary:
	var rules: Dictionary = data.events
	var rng := LocalRng.new((int(world.seed) ^ LocalRng.imul(day + 1, 0x632be5ab)) & 0xffffffff)
	if villages.is_empty():
		return {}
	var captives: Dictionary = rules.kinds.captives
	var ruin: Dictionary = rules.kinds.ruin
	var kind := "captives" if rng.next() * (float(captives.weight) + float(ruin.weight)) < float(captives.weight) else "ruin"
	var center: Vector2i = villages[floori(rng.next() * villages.size())]
	var taken := LocalBattles.taken_hexes(world)
	var sites: Array = world.sites.map(func(s: Dictionary) -> Vector2i: return Vector2i(s.q, s.r))
	var usable: Array = []
	for d in range(int(rules.range.min), int(rules.range.max) + 1):
		for cell in HexMath.ring(center, d):
			var type: Variant = world.hexes.get(LocalLand.key(cell))
			if type == null or type == "holy_city" or data.terrain.terrain[type].moveCost == null or taken.has(LocalLand.key(cell)):
				continue
			if kind == "ruin" and not data.sites.kinds.values().any(func(k: Dictionary) -> bool: return type in k.terrain):
				continue
			if kind == "ruin" and sites.any(func(s: Vector2i) -> bool: return HexMath.distance(s, cell) < 2):
				continue
			usable.append([cell, type])
	if usable.is_empty():
		return {}
	var picked: Array = usable[floori(rng.next() * usable.size())]
	var cell: Vector2i = picked[0]
	var grown := 1.0 + float(captives.growthPerDay) * (day - 1)
	if kind == "captives":
		var own := LocalMapgen.front_of(cell)
		var front: String = own if own in world.activeFronts else String(world.activeFronts[0])
		var guards := LocalWaves.compose_wave(data, front, day, LocalWaves.js_round(float(captives.guards) * grown), (int(world.seed) ^ day) & 0xffffffff, world.members.size())
		var reward: Dictionary
		if rng.next() < float(captives.unitsChance):
			var unit: String = captives.units[floori(rng.next() * captives.units.size())]
			reward = {"units": {unit: int(captives.count) + floori(float(captives.countPerDay) * (day - 1))}}
		else:
			reward = {"resources": LocalVillage.resources(func(k: String) -> int: return LocalWaves.js_round(float(captives.resources[k]) * grown))}
		return {"kind": kind, "cell": cell, "front": front, "guards": guards, "reward": reward}
	var fitting: Array = []
	for id in data.sites.kinds:
		if picked[1] in data.sites.kinds[id].terrain:
			fitting.append(id)
	var site_kind: String = fitting[floori(rng.next() * fitting.size())]
	var guardians := {}
	var base := LocalSites.guardians_for(data, cell, int(world.radius), (int(world.seed) ^ LocalRng.imul(day, 0x9e37)) & 0xffffffff)
	for unit in base:
		guardians[unit] = LocalWaves.js_round(int(base[unit]) * float(ruin.guardianFactor))
	return {"kind": kind, "cell": cell, "site": {"kind": site_kind, "q": cell.x, "r": cell.y, "guardians": guardians}}


static func _hours_ms(hours: float, world_speed: float) -> int:
	return LocalWaves.js_round((hours * LocalTime.MS_PER_HOUR) / world_speed)


## A running world has its next day's event planned (scheduler/mapEvents.ts
## ensureMapEvents).
static func ensure(server: LocalServer, world: Dictionary, now: int) -> void:
	if world.status != "running" or world.startedAt == null:
		return
	if world.events.any(func(e: Dictionary) -> bool: return e.status == "pending" and e.type == "map_event"):
		return
	var every := _hours_ms(float(server.data.events.everyHours), world.speed)
	var day := maxi(1, floori(float(now - int(world.startedAt)) / every) + 1)
	server.schedule(world, int(world.startedAt) + day * every, "map_event", {"day": day})


static func on_map_event(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var data := server.data
	var day := int(event.payload.day)
	if world.status != "running":
		return
	var at := int(event.dueAt)
	var villages: Array = []
	for v in world.villages:
		if v.ruin == null and v.ownerAccountId != null:
			villages.append(Vector2i(v.q, v.r))
	var planned := plan(data, world, villages, day)
	var ends_at := at + _hours_ms(float(data.events.lastsHours), world.speed)
	if planned.get("kind") == "captives":
		var camp := LocalBattles.create_camp(server, world, {"kind": "captives", "front": planned.front, "q": planned.cell.x, "r": planned.cell.y,
			"units": planned.guards, "waveId": null, "reward": planned.reward, "endsAt": ends_at}, at)
		server.schedule(world, ends_at, "map_event_end", {"campId": camp.id})
	elif planned.get("kind") == "ruin":
		var site: Dictionary = planned.site
		var created := {"id": world.next.site, "kind": site.kind, "q": site.q, "r": site.r, "guardians": site.guardians, "guardiansSeen": false,
			"status": "unexplored", "exploredBy": null, "find": null, "exploredAt": null, "hard": true, "endsAt": ends_at}
		world.next.site += 1
		world.sites.append(created)
		server.schedule(world, ends_at, "map_event_end", {"siteId": created.id})
	if not planned.is_empty():
		var vars := {"q": planned.cell.x, "r": planned.cell.y}
		LocalInbox.tell_everyone(server, world, {"kind": "site", "tier": "digest", "title": "Captives are held at ({q}, {r})",
			"body": "Clear the camp to free them, before they are taken away.", "vars": vars} if planned.kind == "captives" else
			{"kind": "site", "tier": "digest", "title": "A forbidding ruin rises at ({q}, {r})",
			"body": "Strong guardians watch it, and rich finds lie within, for a while.", "vars": vars}, at)
		changed.append(["world"])
	server.schedule(world, at + _hours_ms(float(data.events.everyHours), world.speed), "map_event", {"day": day + 1})


## Its time is up: gone, unless an army is already on its way to it.
static func on_map_event_end(_server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var p: Dictionary = event.payload
	if p.get("campId") != null:
		var camp: Dictionary = {}
		for c in world.camps:
			if int(c.id) == int(p.campId):
				camp = c
		if camp.is_empty() or camp.status != "active":
			return
		if LocalArmies.armies_holding(world, Vector2i(camp.q, camp.r), ["marching", "engaged"]).any(func(a: Dictionary) -> bool: return a.orders == "clear"):
			return
		world.camps.erase(camp)
	if p.get("siteId") != null:
		var site: Dictionary = {}
		for s in world.sites:
			if int(s.id) == int(p.siteId):
				site = s
		if site.is_empty() or site.status != "unexplored":
			return
		if LocalArmies.armies_holding(world, Vector2i(site.q, site.r), ["marching", "engaged", "stationed"]).any(func(a: Dictionary) -> bool: return a.orders == "explore"):
			return
		world.sites.erase(site)
	changed.append(["world"])
