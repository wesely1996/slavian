class_name LocalEvents
extends RefCounted
## Daily map events for the local engine (server/src/sim/events.ts and
## scheduler/mapEvents.ts): each game day after the first, captives held in
## a camp, a hard ruin or a shipyard rise near one of the players' villages,
## and go after a while unless an army is on its way (or, for a shipyard,
## someone sent resources). A paid-for shipyard builds its boat, struck by
## raiders on the way; a finished boat makes its river a fast lane.


## The event of `day`, or {} when there is nowhere to put it: {kind, cell,
## front, guards, reward} for captives, {kind, cell, site} for a ruin,
## {kind, cell, edge: {a, b}, front, raiders} for a shipyard.
static func plan(data: Dictionary, world: Dictionary, villages: Array, day: int) -> Dictionary:
	var rules: Dictionary = data.events
	var rng := LocalRng.new((int(world.seed) ^ LocalRng.imul(day + 1, 0x632be5ab)) & 0xffffffff)
	if villages.is_empty():
		return {}
	var captives: Dictionary = rules.kinds.captives
	var ruin: Dictionary = rules.kinds.ruin
	var shipyard: Dictionary = rules.kinds.shipyard
	var pick := rng.next() * (float(captives.weight) + float(ruin.weight) + float(shipyard.weight))
	var kind := "captives" if pick < float(captives.weight) else ("ruin" if pick < float(captives.weight) + float(ruin.weight) else "shipyard")
	# Each bank hex's river edges, in edge-key order.
	var rivers: Array = world.rivers.duplicate()
	rivers.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return LocalLand.edge_key(x.a, x.b) < LocalLand.edge_key(y.a, y.b))
	var banks := {}
	for e in rivers:
		for end in [e.a, e.b]:
			if not banks.has(LocalLand.key(end)):
				banks[LocalLand.key(end)] = []
			banks[LocalLand.key(end)].append(e)
	var yards: Array = world.get("shipyards", []).map(func(y: Dictionary) -> Vector2i: return Vector2i(y.q, y.r))
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
			if kind == "shipyard" and (not banks.has(LocalLand.key(cell)) or yards.any(func(y: Vector2i) -> bool: return HexMath.distance(y, cell) < 2)):
				continue
			usable.append([cell, type])
	if usable.is_empty():
		return {}
	var picked: Array = usable[floori(rng.next() * usable.size())]
	var cell: Vector2i = picked[0]
	var grown := 1.0 + float(captives.growthPerDay) * (day - 1)
	var front := event_front(world, cell)
	if kind == "shipyard":
		var raiders := LocalWaves.compose_wave(data, front, day, LocalWaves.js_round(float(shipyard.raiders) * grown), (int(world.seed) ^ day ^ 0x5a17) & 0xffffffff, world.members.size())
		var edge: Dictionary = banks[LocalLand.key(cell)][0]
		# Stored as the server does (db/rivers.ts): the end with the smaller key first.
		var ends: Array = [edge.a, edge.b] if LocalLand.key(edge.a) < LocalLand.key(edge.b) else [edge.b, edge.a]
		return {"kind": kind, "cell": cell, "edge": {"a": ends[0], "b": ends[1]}, "front": front, "raiders": raiders}
	if kind == "captives":
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


## The front an event at `cell` belongs to: the land it rose in, or the
## first active one (sim/events.ts eventFront).
static func event_front(world: Dictionary, cell: Vector2i) -> String:
	var own := LocalMapgen.front_of(cell)
	return own if own in world.activeFronts else String(world.activeFronts[0])


## The bounty an event done at `at` brings (scheduler/eventOutcomes.ts).
static func bounty_at(data: Dictionary, world: Dictionary, at: int) -> Dictionary:
	var day := 1
	if world.startedAt != null:
		day = maxi(1, floori(float(at - int(world.startedAt)) / _hours_ms(float(data.events.everyHours), world.speed)))
	var grown := 1.0 + float(data.events.reward.growthPerDay) * (day - 1)
	return LocalVillage.resources(func(k: String) -> int: return LocalWaves.js_round(float(data.events.reward.resources[k]) * grown))


## The bounty, to the player's first standing village, and the notice of it
## (scheduler/eventOutcomes.ts rewardEvent).
static func reward(server: LocalServer, world: Dictionary, account_id: Variant, notice: Dictionary, at: int, changed: Array) -> void:
	if account_id == null:
		return
	var bounty := bounty_at(server.data, world, at)
	var home_id: Variant = server.reward(world, int(account_id), bounty, at, changed)
	var vars: Dictionary = notice.vars.duplicate()
	vars.merge({"village": server.find_village(world, int(home_id)).name if home_id != null else ""}, true)
	vars.merge(bounty, true)
	LocalInbox.tell(server, world, account_id, {"kind": "event", "tier": "push", "title": notice.title,
		"body": notice.get("body", "Bounty for {village}: {wood} wood, {stone} stone, {grain} grain and {iron} iron.") if home_id != null else "Done, with no village left to take the bounty.",
		"vars": vars}, at)


## Left undone: the next horde of the front hates the more, and everyone is
## told (scheduler/eventOutcomes.ts failEvent).
static func fail(server: LocalServer, world: Dictionary, front: String, title: String, vars: Dictionary, at: int) -> void:
	var wave := LocalHeroCommands._next_wave(world, front)
	var amount := float(server.data.events.failure.hatred)
	var angered := not wave.is_empty() and amount > 0
	var hatred := 0
	if not wave.is_empty():
		hatred = LocalWaves.js_round((float(wave.get("hatred", 0.0)) + amount) * 100)
	if angered:
		LocalHordes.anger_horde(server, world, wave, amount, at)
	var told := vars.duplicate()
	told.merge({"front": front, "hatred": hatred}, true)
	LocalInbox.tell_everyone(server, world, {"kind": "event", "tier": "push", "title": title,
		"body": "The next horde from the {front} hates you the more for it: +{hatred}% attack and defense." if angered else "Nothing more came of it.",
		"vars": told}, at)


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
	elif planned.get("kind") == "shipyard":
		world.merge({"shipyards": []})
		world.next.merge({"shipyard": 1})
		var yard := {"id": world.next.shipyard, "q": planned.cell.x, "r": planned.cell.y, "edge": planned.edge, "status": "open",
			"cost": data.events.kinds.shipyard.cost.duplicate(), "paid": {"wood": 0, "stone": 0, "grain": 0, "iron": 0},
			"front": planned.front, "raiders": planned.raiders, "raids": 0, "endsAt": ends_at, "completesAt": null, "nextRaidAt": null}
		world.next.shipyard += 1
		world.shipyards.append(yard)
		server.schedule(world, ends_at, "map_event_end", {"shipyardId": yard.id})
	if not planned.is_empty():
		var vars := {"q": planned.cell.x, "r": planned.cell.y, "front": event_front(world, planned.cell), "bounty": LocalBattle.total(bounty_at(data, world, at))}
		var notice := {"kind": "event", "tier": "push", "title": "Captives are held at ({q}, {r})",
			"body": "Clear the camp to free them before they are taken away, for a bounty of at least {bounty} resources. If they are taken, the next horde from the {front} hates you the more.", "vars": vars}
		if planned.kind == "ruin":
			notice = {"kind": "event", "tier": "push", "title": "A forbidding ruin rises at ({q}, {r})",
				"body": "Strong guardians watch it, and rich finds lie within, for a while. Searching it brings a bounty of at least {bounty} resources; left alone, it rouses the next horde from the {front}.", "vars": vars}
		elif planned.kind == "shipyard":
			notice = {"kind": "event", "tier": "push", "title": "Boatwrights wait at ({q}, {r})",
				"body": "Send them resources from your villages, and they build a boat that carries armies and caravans fast along the river, with a bounty of at least {bounty} resources for everyone. If nobody does, the next horde from the {front} hates you the more.", "vars": vars}
		LocalInbox.tell_everyone(server, world, notice, at)
		changed.append(["world"])
	server.schedule(world, at + _hours_ms(float(data.events.everyHours), world.speed), "map_event", {"day": day + 1})


## Its time is up: gone, unless an army is already on its way to it.
static func on_map_event_end(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
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
		fail(server, world, String(camp.front), "The captives at ({q}, {r}) were taken away", {"q": camp.q, "r": camp.r}, int(event.dueAt))
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
		fail(server, world, event_front(world, Vector2i(site.q, site.r)), "The forbidding ruin at ({q}, {r}) sank back into the earth", {"q": site.q, "r": site.r}, int(event.dueAt))
	if p.get("shipyardId") != null:
		var yard := find_shipyard(world, int(p.shipyardId))
		# Gone only if nobody has sent anything, nor has a caravan on its way.
		if yard.is_empty() or yard.status != "open" or LocalBattle.total(yard.paid) > 0:
			return
		if world.caravans.any(func(c: Dictionary) -> bool: return c.get("destinationShipyardId") != null and int(c.destinationShipyardId) == int(yard.id) and c.status == "outbound"):
			return
		world.shipyards.erase(yard)
		fail(server, world, String(yard.front), "The boatwrights at ({q}, {r}) gave up and left", {"q": yard.q, "r": yard.r}, int(event.dueAt))
	changed.append(["world"])


static func find_shipyard(world: Dictionary, id: int) -> Dictionary:
	for y in world.get("shipyards", []):
		if int(y.id) == id:
			return y
	return {}


## Raiders strike the shipyard: the armies standing on it fight them one
## after another; if none drives them off, work is lost.
static func on_shipyard_raid(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var data := server.data
	var yard := find_shipyard(world, int(event.payload.shipyardId))
	if yard.is_empty() or yard.status != "building" or yard.nextRaidAt == null or int(yard.nextRaidAt) != int(event.dueAt):
		return
	var rules: Dictionary = data.events.kinds.shipyard
	var at := int(event.dueAt)
	var raiders: Dictionary = yard.raiders.duplicate()
	var where := {"q": yard.q, "r": yard.r}
	var holding: Array = LocalArmies.armies_holding(world, Vector2i(yard.q, yard.r), ["stationed"])
	for i in holding.size():
		if LocalBattle.total(raiders) == 0:
			break
		var army: Dictionary = holding[i]
		# Scouts alone stand aside; with an army they tell it what it faces.
		var fighting := LocalScouting.combatants(data, army.units)
		if LocalBattle.total(fighting) == 0:
			continue
		var home := server.find_village(world, int(army.homeVillageId))
		var result := LocalArmies.repel_raid(data, fighting, LocalScouting.with_intel(data, army.units, LocalBattle.player_stats(data, home.state.bonuses, false)), army.get("stance", "balanced"),
			raiders, String(rules.raiderStance), String(yard.front), int(world.seed), int(yard.id) * 64 + int(yard.raids) * 8 + i)
		var lost := {}
		for unit in fighting:
			var n := int(fighting[unit]) - int(result.armyNow.get(unit, 0))
			if n > 0:
				lost[unit] = n
		LocalArmies.army_losses(server, world, army, lost, at)
		var kills := LocalBattle.total(raiders) - LocalBattle.total(result.raidersNow)
		raiders = {} if result.held else result.raidersNow
		if not (result.held and LocalBattle.total(army.units) > 0):
			LocalArmies.send_home(server, world, army, at)
		var vars := where.duplicate()
		vars.merge({"kills": kills, "lost": LocalBattle.total(lost)})
		LocalInbox.tell(server, world, army.ownerAccountId, {"kind": "battle_result", "tier": "digest",
			"title": "Your army drove the raiders off the shipyard at ({q}, {r})" if result.held else "Raiders broke your army at the shipyard at ({q}, {r})",
			"body": "{kills} of them fell, for {lost} of yours.", "vars": vars}, at)
	var held := LocalBattle.total(raiders) == 0
	var completes_at := int(yard.completesAt) if held else int(yard.completesAt) + _hours_ms(float(rules.setbackHours), world.speed)
	var next := at + _hours_ms(float(rules.raidEveryHours), world.speed)
	yard.raids = int(yard.raids) + 1
	yard.completesAt = completes_at
	yard.nextRaidAt = next if next < completes_at else null
	if not held:
		server.schedule(world, completes_at, "shipyard_done", {"shipyardId": yard.id})
		var vars := where.duplicate()
		vars.merge({"hours": rules.setbackHours})
		LocalInbox.tell_everyone(server, world, {"kind": "site", "tier": "push", "title": "Raiders burned work at the shipyard at ({q}, {r})",
			"body": "The boat is set back {hours} hours. Armies standing there fight the next raiders.", "vars": vars}, at)
	if yard.nextRaidAt != null:
		server.schedule(world, int(yard.nextRaidAt), "shipyard_raid", {"shipyardId": yard.id})
	changed.append(["world"])


## The boat is done: from now on its river is a fast lane.
static func on_shipyard_done(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var yard := find_shipyard(world, int(event.payload.shipyardId))
	if yard.is_empty() or yard.status != "building" or yard.completesAt == null or int(yard.completesAt) != int(event.dueAt):
		return
	yard.status = "done"
	yard.nextRaidAt = null
	# Every member gets the bounty.
	for member in world.members:
		reward(server, world, member.accountId, {"title": "The boat at ({q}, {r}) is ready",
			"body": "Armies, caravans and scouts move fast between hexes along its river. The boatwrights' bounty for {village}: {wood} wood, {stone} stone, {grain} grain and {iron} iron.",
			"vars": {"q": yard.q, "r": yard.r}}, int(event.dueAt), changed)
	changed.append(["world"])


## A village sends what the shipyard still needs (as much as it has); once
## it is all paid, the boat is begun, and raiders come. The shipyard, or
## {error}.
static func pay(server: LocalServer, world: Dictionary, village: Dictionary, shipyard_id: int, at: int) -> Dictionary:
	var rules: Dictionary = server.data.events.kinds.shipyard
	var yard := find_shipyard(world, shipyard_id)
	if yard.is_empty():
		return {"error": "No such shipyard in this world"}
	if yard.status != "open":
		return {"error": "The boat is already paid for"}
	if HexMath.distance(Vector2i(village.q, village.r), Vector2i(yard.q, yard.r)) > int(rules.range):
		return {"error": "Villages within %d hexes send to a shipyard" % int(rules.range)}
	var have := LocalLedger.amounts_at(village.state.ledger, at)
	var sent := LocalVillage.resources(func(k: String) -> int: return maxi(0, mini(int(yard.cost[k]) - int(yard.paid[k]), floori(float(have[k])))))
	if LocalBattle.total(sent) == 0:
		return {"error": "The village has nothing the shipyard needs"}
	village.state.ledger = LocalLedger.spend(village.state.ledger, at, sent)
	return pay_into(server, world, yard, sent, at)


## Resources reach an open shipyard (from a village nearby, or by caravan):
## once it is all paid, the boat is begun, and raiders come
## (scheduler/mapEvents.ts payIntoShipyard).
static func pay_into(server: LocalServer, world: Dictionary, yard: Dictionary, sent: Dictionary, at: int) -> Dictionary:
	var rules: Dictionary = server.data.events.kinds.shipyard
	var all_paid := true
	for k in LocalLedger.KINDS:
		yard.paid[k] = int(yard.paid[k]) + int(sent.get(k, 0))
		if int(yard.paid[k]) < int(yard.cost[k]):
			all_paid = false
	if all_paid:
		var completes_at := at + _hours_ms(float(rules.buildHours), world.speed)
		var raid := at + _hours_ms(float(rules.raidEveryHours), world.speed)
		yard.status = "building"
		yard.completesAt = completes_at
		yard.nextRaidAt = raid if raid < completes_at else null
		server.schedule(world, completes_at, "shipyard_done", {"shipyardId": yard.id})
		if yard.nextRaidAt != null:
			server.schedule(world, int(yard.nextRaidAt), "shipyard_raid", {"shipyardId": yard.id})
		LocalInbox.tell_everyone(server, world, {"kind": "site", "tier": "push", "title": "The boat at ({q}, {r}) is begun",
			"body": "Raiders will come every {every} hours until it is done; armies standing there fight them.",
			"vars": {"q": yard.q, "r": yard.r, "every": rules.raidEveryHours}}, at)
	return yard


static func shipyard_view(y: Dictionary) -> Dictionary:
	return {"id": y.id, "q": y.q, "r": y.r, "edge": [y.edge.a.x, y.edge.a.y, y.edge.b.x, y.edge.b.y], "status": y.status,
		"cost": y.cost, "paid": y.paid, "front": y.front, "raiders": LocalBattle.total(y.raiders), "raids": y.raids,
		"endsAt": LocalTime.iso(y.endsAt) if y.endsAt != null else null,
		"completesAt": LocalTime.iso(y.completesAt) if y.completesAt != null else null,
		"nextRaidAt": LocalTime.iso(y.nextRaidAt) if y.nextRaidAt != null else null}
