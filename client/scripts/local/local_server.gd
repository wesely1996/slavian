class_name LocalServer
extends RefCounted
## The local engine's stand-in for the game server (docs/local-engine.md):
## solo worlds kept on the device, answering the same requests with the same
## JSON. Worlds have negative ids, and so does nothing on the real server.
##
## Starting a world follows server/src/commands/worlds.ts startWorldCommand
## step for step; the views follow server/src/api/views.ts. The client test
## checks a started world against data/fixtures/start-world.json, recorded
## from the real server.

const MASK := 0xffffffff
const DIR := "user://local"

## {world id: world}, loaded from DIR on first use.
var worlds: Dictionary = {}
var data: Dictionary = {}
## Where worlds are saved ("" keeps them in memory only, for tests).
var save_dir := DIR


func _init(game_data: Dictionary = {}, dir := DIR) -> void:
	data = game_data if not game_data.is_empty() else LocalData.load_data()
	save_dir = dir
	_load_all()


# --- Starting a solo world ----------------------------------------------------

## Creates and starts a solo world for `account_id`, at `now` (ms).
## `params`: {name, displayName, speed, difficulty, seed, heroKind?, clan?}.
func start_world(params: Dictionary, account_id: int, now: int) -> Dictionary:
	var id := -1
	while worlds.has(id):
		id -= 1
	var speed := float(params.get("speed", 1))
	var seed_value := int(params.get("seed", randi() & 0x7fffffff))
	var world := {
		"id": id, "name": String(params.get("name", "Solo")), "status": "running", "speed": speed,
		"difficulty": String(params.get("difficulty", "normal")), "seed": seed_value, "maxPlayers": 1,
		"hostAccountId": account_id, "startedAt": now, "embers": 0, "ritualAt": null, "endedAt": null,
		"members": [{"accountId": account_id, "displayName": String(params.get("displayName", "You")), "clan": params.get("clan"),
			"heroKind": params.get("heroKind"), "onboarding": {}, "onboardingClaimed": {}}],
		"villages": [], "heroes": [], "waves": [], "sites": [], "rivers": [], "roads": [], "events": [],
		"vault": {"level": 1, "amounts": {"wood": 0, "stone": 0, "grain": 0, "iron": 0}, "upgradingTo": null, "upgradeCompletesAt": null},
		"leaders": [], "fear": {}, "camps": [], "battles": [], "raids": [], "quietStart": null, "quietEnd": null, "quietUtcOffset": 0,
		"next": {"village": 1, "wave": 1, "site": 1, "event": 1, "leader": 1, "battle": 1, "camp": 1, "raid": 1},
	}
	# The map, its rivers and bridges.
	var map := LocalMapgen.generate(data, seed_value, world.members.size())
	# From here on the world carries the seed that made a playable map (the
	# server's markStarted); town names still come from the one it was given.
	world.seed = int(map.seed)
	world.radius = int(map.radius)
	world.activeFronts = map.activeFronts
	world.sanctity = int(data.horde.holyCity.sanctity)
	world.hexes = map.terrain
	for e in map.rivers:
		world.rivers.append({"a": e.a, "b": e.b, "crossing": "standing" if e.bridge else "none", "size": int(e.size)})
	# Every town gets a name of its own.
	var names: Array = []
	var name_rng := LocalRng.new((seed_value ^ 0x7a11) & MASK)
	for i in world.members.size():
		var member: Dictionary = world.members[i]
		var site: Vector2i = map.startSites[i]
		var town := LocalHeroes.town_name(data, names, name_rng)
		names.append(town)
		insert_village(world, member.accountId, town, site, LocalVillage.new_village(data, now, speed))
	_ensure_heroes(world)
	# Each village carries its owner's clan and hero.
	for member in world.members:
		_refresh_bonuses(world, int(member.accountId), now)
	_ensure_sites(world)
	world.bridge = {"stage": 0, "donated": {"wood": 0, "stone": 0, "grain": 0, "iron": 0}, "embers": 0, "quests": {},
		"stageStartedAt": LocalTime.iso(now), "sanctityAtStart": world.sanctity, "status": "open", "raisedAt": null}
	_announce_first_waves(world)
	worlds[id] = world
	save(world)
	return world


func insert_village(world: Dictionary, owner: int, name: String, at: Vector2i, state: Dictionary) -> Dictionary:
	var village := {"id": world.next.village, "ownerAccountId": owner, "name": name, "q": at.x, "r": at.y, "state": state,
		# Auto-reinforce defaults (migration 015): half the garrison, 4 hexes.
		"reinforce": {"share": 0.5, "range": 4}, "ruin": null, "refuge": false}
	world.next.village += 1
	world.villages.append(village)
	return village


## Every member gets a roster hero (the first free one if they didn't pick),
## standing in their first village (db/heroes.ts ensureHeroes).
func _ensure_heroes(world: Dictionary) -> void:
	var kinds: Array = []
	for member in world.members:
		kinds.append(member.heroKind)
	for member in world.members:
		if member.heroKind == null:
			var kind: Variant = LocalHeroes.free_hero_kind(data, kinds)
			if kind != null:
				member.heroKind = kind
				kinds.append(kind)
	for member in world.members:
		var has_hero: bool = world.heroes.any(func(h: Dictionary) -> bool: return int(h.accountId) == int(member.accountId))
		var first: Dictionary = {}
		for v in world.villages:
			if int(v.ownerAccountId) == int(member.accountId) and (first.is_empty() or v.id < first.id):
				first = v
		if has_hero or first.is_empty():
			continue
		var hero := LocalHeroes.new_hero(data, member.heroKind if member.heroKind != null else data.heroes.roster.keys()[0])
		hero.merge({"accountId": member.accountId, "status": "home", "villageId": first.id, "armyId": null, "path": null,
			"departsAt": null, "arrivesAt": null, "woundedUntil": null, "quest": null, "questsDone": []})
		world.heroes.append(hero)


## A player's bonuses: research, the group's scrolls, their clan and hero
## (scheduler/research.ts playerBonuses), given to each of their villages.
func _refresh_bonuses(world: Dictionary, account_id: int, at: int) -> void:
	var bonuses := player_bonuses(world, account_id)
	for village in world.villages:
		if int(village.ownerAccountId) == account_id:
			village.state = LocalVillage.with_bonuses(data, village.state, bonuses, at, world.speed)


## Research, the group's scrolls, the player's clan and hero
## (scheduler/research.ts playerBonuses).
func player_bonuses(world: Dictionary, account_id: int) -> Dictionary:
	var member: Dictionary = {}
	for m in world.members:
		if int(m.accountId) == account_id:
			member = m
	var own := LocalHeroes.combine(LocalVillage.clan_bonuses(data, member.get("clan")), LocalHeroes.roster_bonuses(data, member.get("heroKind")))
	return LocalHeroes.combine(LocalHeroes.combine({}, {}), own)


func _ensure_sites(world: Dictionary) -> void:
	if not world.sites.is_empty():
		return
	var starts: Array = []
	for v in world.villages:
		starts.append(Vector2i(v.q, v.r))
	for s in LocalSites.place_sites(data, world.hexes, world.radius, starts, world.seed, world.members.size()):
		world.sites.append({"id": world.next.site, "kind": s.kind, "q": s.q, "r": s.r, "guardians": s.guardians, "guardiansSeen": false,
			"status": "unexplored", "exploredBy": null, "find": null, "exploredAt": null})
		world.next.site += 1


## The first waves, announced at the start (scheduler/waves.ts).
func _announce_first_waves(world: Dictionary) -> void:
	var previous: Variant = null
	for index in int(data.waves.upcoming):
		previous = announce_wave(world, index, previous).spawnAt


## Plans wave `index` after the one spawning at `previous_spawn_at` (ms, or
## null for the first), and schedules its spawn (announceWave).
func announce_wave(world: Dictionary, index: int, previous_spawn_at: Variant) -> Dictionary:
	var ctx := {"seed": world.seed, "activeFronts": world.activeFronts, "playerCount": world.members.size(), "startedAt": world.startedAt,
		"worldSpeed": world.speed, "sizeFactor": LocalWaves.wave_factor(data, world.difficulty, _group_power(world, index))}
	var planned := LocalWaves.plan_wave(data, ctx, index, previous_spawn_at)
	var wave := {"id": world.next.wave, "index": planned.index, "front": planned.front, "status": "scheduled", "threat": planned.threat,
		"stance": planned.stance, "composition": planned.composition, "initial": planned.composition.duplicate(), "spawnAt": planned.spawnAt,
		"spawn": null, "targetVillageId": null, "path": null, "arrivesAt": null, "endsAt": null, "rampageEndsAt": null, "struck": [],
		"ritual": false, "leaderId": null}
	world.next.wave += 1
	world.waves.append(wave)
	schedule(world, planned.spawnAt, "wave_spawn", {"waveId": wave.id})
	return wave


func find_wave(world: Dictionary, id: int) -> Dictionary:
	for w in world.waves:
		if int(w.id) == id:
			return w
	return {}


## What the group has built up, for wave sizes (difficulty.ts GroupPower).
func _group_power(world: Dictionary, index: int) -> Dictionary:
	var villages: Array = world.villages.filter(func(v: Dictionary) -> bool: return v.ruin == null)
	var attack := 0.0
	for village in villages:
		var fed := LocalVillage.units_fed(village.state)
		for unit in fed:
			var def: Dictionary = data.units.units.get(unit, {})
			if def.get("family") in ["infantry", "archers", "cavalry"] and unit != "settler" and int(fed[unit]) > 0:
				attack += int(fed[unit]) * float(def.get("attack", 0))
	return {"players": world.members.size(), "villages": villages.size(), "armyAttack": attack, "waveIndex": index,
		"bridgeStages": int(world.bridge.stage) if world.has("bridge") else 0}


func schedule(world: Dictionary, due_at: int, type: String, payload: Dictionary) -> void:
	world.events.append({"id": world.next.event, "dueAt": due_at, "type": type, "payload": payload, "status": "pending"})
	world.next.event += 1


## Whether a pending event of `type` carries all of `payload` (jsonb @>).
func pending(world: Dictionary, type: String, payload: Dictionary) -> bool:
	for e in world.events:
		if e.type != type or e.status != "pending":
			continue
		var all := true
		for key in payload:
			if not e.payload.has(key) or not _same(e.payload[key], payload[key]):
				all = false
				break
		if all:
			return true
	return false


static func _same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return float(a) == float(b)
	return typeof(a) == typeof(b) and a == b


# --- Requests (api/app.ts) ----------------------------------------------------

## Answers a request for a solo world as the server's routes do: {status,
## data}. Due events run first (withWorld), and `changed` lists what to tell
## the screens: ["village", id] or ["world"].
func handle(world_id: int, method: String, path: String, body: Variant, now: int) -> Dictionary:
	var world: Dictionary = worlds.get(world_id, {})
	if world.is_empty():
		return _fail(404, "not_found", "No such solo world")
	var parts := path.split("?")[0].split("/", false)
	var changed: Array = []
	drain(world, now, changed)
	as_stored(world)
	var answer := _route(world, method, parts, body if body is Dictionary else {}, now, changed)
	answer.changed = changed
	save(world)
	return answer


func _route(world: Dictionary, method: String, parts: PackedStringArray, body: Dictionary, now: int, changed: Array) -> Dictionary:
	if method == "GET" and parts.size() == 3 and parts[1] == "worlds":
		return {"status": 200, "data": world_view(world, now)}
	if method == "POST" and parts.size() == 5 and parts[1] == "worlds" and parts[3] == "onboarding" and parts[4] == "claim":
		var claimed := _claim_onboarding(world, String(body.get("step", "")), now, changed)
		if claimed.has("error"):
			return _rule_answer(claimed)
		var view := world_view(world, now)
		view.claimed = claimed
		return {"status": 200, "data": view}
	if parts.size() >= 4 and parts[1] == "villages" and method == "POST":
		var village := find_village(world, int(parts[2]))
		if village.is_empty():
			return _fail(404, "not_found", "Village %s not found" % parts[2])
		if int(village.ownerAccountId) != int(world.hostAccountId):
			return _fail(403, "forbidden", "Not your village")
		var action := "/".join(parts.slice(3))
		if village.ruin != null:
			return _fail(400, "rule", "%s lies in ruins; rebuild it first" % village.name)
		var result: Dictionary
		var step := ""
		match action:
			"build":
				result = _queue_build(world, village, body, now)
				step = "build"
			"train":
				result = _train(world, village, body, now)
				step = "train"
			"outposts":
				result = _claim_outpost(world, village, body, now)
				step = "outpost"
			"outposts/abandon":
				result = LocalVillage.abandon_outpost(data, village.state, LocalVillage.outpost_plot(Vector2i(int(body.get("q", 0)), int(body.get("r", 0)))), now, world.speed)
				if not result.has("error"):
					result = {"state": result}
			"stance":
				if not String(body.get("stance", "")) in data.battle.stances:
					return _fail(400, "invalid_request", "Unknown stance")
				var stanced: Dictionary = village.state.duplicate(true)
				stanced.stance = String(body.stance)
				result = {"state": stanced}
			"rename":
				var name := String(body.get("name", "")).strip_edges()
				if name == "" or name.length() > 32:
					return _fail(400, "invalid_request", "Give the town a name of 1 to 32 letters")
				village.name = name
				result = {"state": village.state}
			_:
				return _fail(501, "local", "Not in single player yet")
		if result.has("error") or result.has("missing"):
			return _rule_answer(result)
		village.state = result.state
		changed.append(["village", village.id])
		if step != "":
			_onboarding_step(world, int(village.ownerAccountId), step, now, changed)
		return {"status": 200, "data": {"village": village_view(world, village), "serverTime": LocalTime.iso(now)}}
	return _fail(501, "local", "Not in single player yet")


func _queue_build(world: Dictionary, village: Dictionary, body: Dictionary, now: int) -> Dictionary:
	var order := {}
	if body.get("plot"):
		order.plot = String(body.plot)
	if body.get("building"):
		order.building = String(body.building)
	var result := LocalVillage.queue_build(data, village.state, order, now, world.speed)
	if result.has("state"):
		var q: Dictionary = result.queued
		schedule(world, int(q.completesAt), "build_complete", {"villageId": village.id, "plot": q.plot, "building": q.building, "targetLevel": q.targetLevel})
	return result


func _train(world: Dictionary, village: Dictionary, body: Dictionary, now: int) -> Dictionary:
	var owned: int = world.villages.filter(func(v: Dictionary) -> bool: return int(v.ownerAccountId) == int(village.ownerAccountId)).size()
	var result := LocalVillage.queue_training(data, village.state, String(body.get("unit", "")), int(body.get("count", 0)), now, world.speed, owned)
	if result.has("state"):
		schedule(world, LocalVillage.batch_completes_at(result.batch), "training_complete", {"villageId": village.id})
	return result


func _claim_outpost(world: Dictionary, village: Dictionary, body: Dictionary, now: int) -> Dictionary:
	var cell := Vector2i(int(body.get("q", 0)), int(body.get("r", 0)))
	var terrain: Variant = world.hexes.get(LocalLand.key(cell))
	if terrain == null:
		return LocalVillage.rule("That hex is not on the map")
	for s in world.sites:
		if s.q == cell.x and s.r == cell.y:
			return LocalVillage.rule("An ancient site lies there")
	var taken := {}
	for other in world.villages:
		taken[LocalLand.key(Vector2i(other.q, other.r))] = true
		for plot in LocalVillage.outpost_plots(other.state.plots):
			taken[LocalLand.key(LocalVillage.outpost_hex(plot))] = true
	var site := {"cell": cell, "terrain": terrain, "home": Vector2i(village.q, village.r), "taken": taken}
	var result := LocalVillage.claim_outpost(data, village.state, site, now, world.speed)
	if result.has("state"):
		var q: Dictionary = result.queued
		schedule(world, int(q.completesAt), "build_complete", {"villageId": village.id, "plot": q.plot, "building": q.building, "targetLevel": q.targetLevel})
	return result


func find_village(world: Dictionary, id: int) -> Dictionary:
	for v in world.villages:
		if int(v.id) == id:
			return v
	return {}


## The first time a player does a getting-started step (scheduler/onboarding.ts).
func _onboarding_step(world: Dictionary, account_id: int, step: String, now: int, changed: Array) -> void:
	for member in world.members:
		if int(member.accountId) == account_id and not member.onboarding.has(step):
			if data.onboarding.steps.any(func(s: Dictionary) -> bool: return s.id == step):
				member.onboarding[step] = LocalTime.iso(now)
				changed.append(["world"])


func _claim_onboarding(world: Dictionary, step: String, now: int, changed: Array) -> Dictionary:
	var member: Dictionary = world.members[0]
	var def: Dictionary = {}
	for s in data.onboarding.steps:
		if s.id == step:
			def = s
	if def.is_empty():
		return LocalVillage.rule("Unknown step \"%s\"" % step)
	if not member.onboarding.has(step):
		return LocalVillage.rule("\"%s\" is not done yet" % def.title)
	if member.onboardingClaimed.has(step):
		return LocalVillage.rule("That reward is already claimed")
	member.onboardingClaimed[step] = LocalTime.iso(now)
	var village_id: Variant = _reward(world, int(member.accountId), def.reward, now, changed)
	var finale := false
	var all_claimed: bool = data.onboarding.steps.all(func(s: Dictionary) -> bool: return member.onboardingClaimed.has(s.id))
	if all_claimed and not member.onboardingClaimed.has("finale"):
		member.onboardingClaimed["finale"] = LocalTime.iso(now)
		_reward(world, int(member.accountId), data.onboarding.finale.reward, now, changed)
		finale = true
	changed.append(["world"])
	return {"villageId": village_id, "finale": finale}


## A reward, all of it, to the player's first standing village.
func _reward(world: Dictionary, account_id: int, amounts: Dictionary, now: int, changed: Array) -> Variant:
	var home: Dictionary = {}
	for v in world.villages:
		if int(v.ownerAccountId) == account_id and v.ruin == null and (home.is_empty() or v.id < home.id):
			home = v
	if home.is_empty():
		return null
	var ledger := LocalLedger.settle(home.state.ledger, now)
	for kind in LocalLedger.KINDS:
		ledger.amounts[kind] = float(ledger.amounts[kind]) + float(amounts[kind])
	home.state.ledger = ledger
	changed.append(["village", home.id])
	return home.id


static func _fail(status: int, error: String, message: String) -> Dictionary:
	return {"status": status, "data": {"error": error, "message": message}}


## A rule broken, or resources short, as the server answers them.
static func _rule_answer(result: Dictionary) -> Dictionary:
	if result.has("missing"):
		var parts: PackedStringArray = []
		for kind in LocalLedger.KINDS:
			parts.append("\"%s\":%s" % [kind, _js_number(result.missing[kind])])
		return {"status": 400, "data": {"error": "insufficient_resources", "message": "Insufficient resources: missing {%s}" % ",".join(parts), "missing": result.missing}}
	return _fail(400, "rule", String(result.error))


## A number as JavaScript prints it: whole numbers bare, others in the
## shortest form that reads back as the same number.
static func _js_number(value: Variant) -> String:
	var f := float(value)
	if f == floorf(f) and absf(f) < 1e15:
		return str(int(f))
	return String.num_scientific(f)


# --- Scheduler (scheduler/world.ts drainWorld) ---------------------------------

## Runs the world's pending events due by `until`, oldest first, one at a
## time (a handler may schedule an earlier one).
func drain(world: Dictionary, until: int, changed: Array) -> int:
	var processed := 0
	while processed < 10000:
		var next: Dictionary = {}
		for e in world.events:
			if e.status == "pending" and int(e.dueAt) <= until and (next.is_empty() or int(e.dueAt) < int(next.dueAt) or (int(e.dueAt) == int(next.dueAt) and e.id < next.id)):
				next = e
		if next.is_empty():
			break
		var handler := Callable(self, "_on_" + String(next.type))
		# Not ported yet (no handler, or a handler that answers false): the
		# server would run it; here it waits, and the world stops at it.
		if not handler.is_valid():
			break
		as_stored(world)
		var ran: Variant = handler.call(world, next, changed)
		if ran is bool and not ran:
			break
		next.status = "done"
		processed += 1
	world.events = world.events.filter(func(e: Dictionary) -> bool: return e.status == "pending")
	return processed


func _on_build_complete(world: Dictionary, event: Dictionary, changed: Array) -> void:
	var p: Dictionary = event.payload
	var village := find_village(world, int(p.villageId))
	if village.is_empty() or village.ruin != null:
		return
	var plot: String = p.get("plot", "")
	if not village.state.queue.any(func(item: Dictionary) -> bool: return item.plot == plot and int(item.targetLevel) == int(p.targetLevel)):
		return
	var done := LocalVillage.complete_build(data, village.state, plot, int(p.targetLevel), int(event.dueAt), world.speed)
	if done.has("error"):
		return
	village.state = done
	changed.append(["village", village.id])


## What the server keeps as jsonb, in the order it reads back in
## (LocalStore): run before each event and request, as the server loads
## its rows afresh for each.
func as_stored(world: Dictionary) -> void:
	for v in world.villages:
		v.state = LocalStore.stored(v.state)
		v.ruin = LocalStore.stored(v.ruin)
	for w in world.waves:
		w.composition = LocalStore.stored(w.composition)
		w.initial = LocalStore.stored(w.initial)
	for b in world.battles:
		for key in ["setup", "attackerInitial", "defenderInitial", "rounds", "loot", "decision"]:
			b[key] = LocalStore.stored(b[key])
	for c in world.camps:
		c.units = LocalStore.stored(c.units)
	for l in world.leaders:
		l.skills = LocalStore.stored(l.skills)
	for h in world.heroes:
		h.skills = LocalStore.stored(h.skills)
		h.gear = LocalStore.stored(h.gear)
	world.bridge = LocalStore.stored(world.bridge)


func _on_wave_arrive(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalBattles.on_wave_arrive(self, world, event, changed)


func _on_wave_disperse(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalBattles.on_wave_disperse(self, world, event, changed)


func _on_battle_round(world: Dictionary, event: Dictionary, changed: Array) -> bool:
	return LocalBattles.on_battle_round(self, world, event, changed)


func _on_wave_raze(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalBattles.on_wave_raze(self, world, event, changed)


func _on_village_rebuilt(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalBattles.on_village_rebuilt(self, world, event, changed)


func _on_outpost_raid(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalBattles.on_outpost_raid(self, world, event, changed)


func _on_camp_grow(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalBattles.on_camp_grow(self, world, event, changed)


func _on_hero_recover(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalBattles.on_hero_recover(self, world, event, changed)


func _on_wave_spawn(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalHordes.on_wave_spawn(self, world, event, changed)


## The target's owner is told a horde is near; the inbox comes in part 5.
func _on_wave_warning(_world: Dictionary, _event: Dictionary, _changed: Array) -> void:
	pass


func _on_training_complete(world: Dictionary, event: Dictionary, changed: Array) -> void:
	var village := find_village(world, int(event.payload.villageId))
	if village.is_empty():
		return
	village.state = LocalVillage.complete_training(village.state, int(event.dueAt))
	changed.append(["village", village.id])


# --- Views (api/views.ts) -----------------------------------------------------

func world_view(world: Dictionary, now: int) -> Dictionary:
	var waves: Array = []
	for w in world.waves:
		if not w.status in ["dispersed", "defeated", "settled"]:
			waves.append(_wave_view(w))
	waves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.index < b.index)
	var heroes: Array = []
	for h in world.heroes:
		heroes.append(_hero_view(world, h, now))
	var sites: Array = []
	for s in world.sites:
		sites.append({"id": s.id, "kind": s.kind, "q": s.q, "r": s.r, "status": s.status,
			"guardians": _total(s.guardians) if s.guardiansSeen else null, "exploredBy": s.exploredBy, "find": s.find,
			"exploredAt": LocalTime.iso(s.exploredAt) if s.exploredAt != null else null})
	var members: Array = []
	for m in world.members:
		members.append({"accountId": m.accountId, "displayName": m.displayName, "clan": m.clan, "heroKind": m.heroKind,
			"onboarding": m.onboarding, "onboardingClaimed": m.onboardingClaimed})
	var villages: Array = []
	for v in world.villages:
		villages.append(village_view(world, v))
	var hexes: Array = []
	for key in world.hexes:
		var parts: PackedStringArray = key.split(",")
		hexes.append([int(parts[0]), int(parts[1]), world.hexes[key]])
	hexes.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1] or (a[1] == b[1] and a[0] < b[0]))
	var rivers: Array = []
	for e in world.rivers:
		var ab := _ordered(e.a, e.b)
		rivers.append([ab[0].x, ab[0].y, ab[1].x, ab[1].y, e.crossing, e.size])
	rivers.sort_custom(func(a: Array, b: Array) -> bool:
		for i in 4:
			if a[i] != b[i]:
				return a[i] < b[i]
		return false)
	return {
		"id": world.id, "name": world.name, "status": world.status, "inviteCode": null, "speed": world.speed,
		"maxPlayers": world.maxPlayers, "hostAccountId": world.hostAccountId, "startedAt": LocalTime.iso(world.startedAt),
		"sanctity": world.sanctity, "embers": world.embers, "difficulty": world.difficulty, "quietHours": null,
		"ritualAt": LocalTime.iso(world.ritualAt) if world.ritualAt != null else null,
		"endedAt": LocalTime.iso(world.endedAt) if world.endedAt != null else null,
		"members": members, "villages": villages, "waves": waves, "scouting": [], "battles": _battles_view(world), "raids": _raids_view(world), "expeditions": [],
		"research": [], "heroes": heroes, "leaders": LocalHordes.leaders_view(data, world), "orders": [], "armies": [], "forts": [], "camps": _camps_view(world), "sites": sites,
		"lore": [], "bridge": world.bridge, "fear": _fear_view(world), "delegations": [], "delegationLog": [], "run": null, "caravans": [],
		"vault": {"level": world.vault.level, "amounts": world.vault.amounts, "capacity": _vault_capacity(int(world.vault.level)),
			"upgradingTo": world.vault.upgradingTo, "upgradeCompletesAt": world.vault.upgradeCompletesAt},
		"map": {"radius": world.radius, "activeFronts": world.activeFronts, "hexes": hexes, "rivers": rivers, "roads": []},
		"serverTime": LocalTime.iso(now),
	}


func village_view(world: Dictionary, village: Dictionary) -> Dictionary:
	var s: Dictionary = village.state
	var queue: Array = []
	for item in s.queue:
		queue.append({"plot": item.plot, "building": item.building, "targetLevel": item.targetLevel,
			"startsAt": LocalTime.iso(item.startsAt), "completesAt": LocalTime.iso(item.completesAt)})
	var training: Array = []
	for b in s.training:
		training.append({"unit": b.unit, "count": b.count, "startsAt": LocalTime.iso(b.startsAt), "perUnitMs": b.perUnitMs,
			"completesAt": LocalTime.iso(int(b.startsAt) + int(b.count) * int(b.perUnitMs))})
	return {
		"id": village.id, "worldId": world.id, "ownerAccountId": village.ownerAccountId, "name": village.name, "q": village.q, "r": village.r,
		"plots": s.plots.duplicate(true), "levels": s.levels.duplicate(), "queue": queue, "garrison": s.garrison.duplicate(),
		"away": s.away.duplicate(), "stance": s.stance, "besieged": s.besieged, "adminUpkeep": s.adminUpkeep,
		"bonuses": s.bonuses.duplicate(), "reinforce": village.reinforce, "ruin": village.ruin, "refuge": village.refuge == true,
		"training": training,
		"resources": {"amounts": s.ledger.amounts, "ratesPerHour": s.ledger.ratesPerHour, "capacity": s.ledger.capacity,
			"settledAt": LocalTime.iso(s.ledger.settledAt)},
	}


func _wave_view(w: Dictionary) -> Dictionary:
	var path: Variant = null
	if w.path != null:
		path = []
		for step in w.path:
			path.append([step.q, step.r, step.atMs])
	return {"id": w.id, "index": w.index, "front": w.front, "status": w.status, "threat": w.threat, "spawnAt": LocalTime.iso(w.spawnAt),
		"spawn": w.spawn, "targetVillageId": w.targetVillageId, "path": path,
		"arrivesAt": LocalTime.iso(w.arrivesAt) if w.arrivesAt != null else null,
		"endsAt": LocalTime.iso(w.endsAt) if w.endsAt != null else null,
		"rampageEndsAt": LocalTime.iso(w.rampageEndsAt) if w.rampageEndsAt != null else null,
		"struck": w.struck, "ritual": w.ritual, "leaderId": w.leaderId}


func _hero_view(world: Dictionary, h: Dictionary, now: int) -> Dictionary:
	return {
		"accountId": h.accountId, "kind": h.kind, "name": h.name, "status": h.status, "villageId": h.villageId, "armyId": h.armyId,
		"level": h.level, "xp": h.xp, "xpToNext": null if int(h.level) >= int(data.heroes.maxLevel) else LocalHeroes.xp_to_next(data, int(h.level)),
		"skillPoints": h.skillPoints, "skills": h.skills, "gear": h.gear, "inventory": h.inventory, "bonuses": LocalHeroes.hero_bonuses(data, h),
		"path": h.path, "departsAt": h.departsAt, "arrivesAt": h.arrivesAt, "woundedUntil": h.woundedUntil, "quest": h.quest,
		"offers": _quest_offers(world, h, now),
	}


## The quests a hero is offered now (scheduler/quests.ts heroQuestOffers).
func _quest_offers(world: Dictionary, hero: Dictionary, now: int) -> Array:
	if hero.villageId == null or world.status != "running":
		return []
	var home: Dictionary = {}
	for v in world.villages:
		if v.id == hero.villageId:
			home = v
	var fronts: Array = []
	for w in world.waves:
		if w.status == "scheduled" and not w.front in fronts:
			fronts.append(w.front)
	fronts.sort()
	var sites: Array = []
	for s in world.sites:
		if s.status == "unexplored" and _total(s.guardians) == 0:
			sites.append({"id": s.id, "q": s.q, "r": s.r})
	var owned: Array = hero.inventory + hero.gear.values()
	var gear_left: bool = data.heroes.items.keys().any(func(item: String) -> bool: return not item in owned)
	var quest_world := {"seed": world.seed, "speed": world.speed, "startedAt": world.startedAt, "fronts": fronts, "sites": sites, "gearLeft": gear_left}
	return LocalHeroes.quest_offers(data, quest_world, hero, Vector2i(home.q, home.r), now, hero.questsDone)


## Ongoing battles and the ten latest, newest first (api/views.ts).
func _battles_view(world: Dictionary) -> Array:
	var battles: Array = world.battles.duplicate()
	battles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if (a.status == "ongoing") != (b.status == "ongoing"):
			return a.status == "ongoing"
		if int(a.startedAt) != int(b.startedAt):
			return int(a.startedAt) > int(b.startedAt)
		return int(a.id) > int(b.id))
	var out: Array = []
	for battle in battles.slice(0, 10):
		var wave: Dictionary = find_wave(world, int(battle.waveId)) if battle.waveId != null else {}
		var now: Dictionary
		if wave.is_empty():
			# A camp's numbers after the assault: its start minus what fell.
			var left: Dictionary = battle.attackerInitial.duplicate()
			for r in battle.rounds:
				for unit in r.attackerLosses:
					left[unit] = int(left.get(unit, 0)) - int(r.attackerLosses[unit])
			now = {}
			for unit in left:
				if int(left[unit]) > 0:
					now[unit] = left[unit]
		else:
			now = wave.composition
		var front: Variant = wave.front if not wave.is_empty() else null
		if battle.campId != null:
			for c in world.camps:
				if int(c.id) == int(battle.campId):
					front = c.front
		out.append({"id": battle.id, "front": front, "leaderId": wave.get("leaderId"), "waveId": battle.waveId, "campId": battle.campId,
			"siteId": battle.siteId, "villageId": battle.villageId, "q": battle.q, "r": battle.r, "setup": battle.setup, "status": battle.status,
			"round": battle.round, "attackerStance": battle.attackerStance, "attackerInitial": battle.attackerInitial, "attackerNow": now,
			"defenderInitial": battle.defenderInitial, "rounds": battle.rounds, "loot": battle.loot, "decision": battle.decision,
			"startedAt": LocalTime.iso(battle.startedAt), "endedAt": LocalTime.iso(battle.endedAt) if battle.endedAt != null else null})
	return out


func _raids_view(world: Dictionary) -> Array:
	var raids: Array = world.raids.duplicate()
	raids.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.at) > int(b.at) or (int(a.at) == int(b.at) and int(a.id) > int(b.id)))
	return raids.slice(0, 10).map(func(r: Dictionary) -> Dictionary:
		return {"id": r.id, "waveId": r.waveId, "villageId": r.villageId, "q": r.q, "r": r.r, "levelAfter": r.levelAfter, "at": LocalTime.iso(r.at)})


func _camps_view(world: Dictionary) -> Array:
	var out: Array = []
	for c in world.camps:
		if c.status == "active":
			out.append({"id": c.id, "kind": c.kind, "front": c.front, "q": c.q, "r": c.r, "size": _total(c.units), "waveId": c.waveId})
	return out


## [q, r, fear], to a tenth.
func _fear_view(world: Dictionary) -> Array:
	var out: Array = []
	for key in world.fear:
		var parts: PackedStringArray = key.split(",")
		out.append([int(parts[0]), int(parts[1]), LocalWaves.js_round(float(world.fear[key]) * 10) / 10.0])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	return out


func _vault_capacity(level: int) -> float:
	var v: Dictionary = data.logistics.vault
	return float(v.baseCapacity) * pow(float(v.capacityGrowth), level - 1)


static func _total(units: Dictionary) -> int:
	var n := 0
	for count in units.values():
		n += int(count)
	return n


## An edge's ends in the server's stored order (db/rivers.ts ordered).
static func _ordered(a: Vector2i, b: Vector2i) -> Array:
	return [a, b] if LocalLand.edge_key(a, b).begins_with(LocalLand.key(a) + "|") else [b, a]


# --- Saving -------------------------------------------------------------------

## Writes a world to the device (nothing when save_dir is "").
func save(world: Dictionary) -> void:
	if save_dir == "":
		return
	DirAccess.make_dir_recursive_absolute(save_dir)
	var file := FileAccess.open("%s/%d.json" % [save_dir, -int(world.id)], FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_encode(world)))


func _load_all() -> void:
	if save_dir == "" or not DirAccess.dir_exists_absolute(save_dir):
		return
	for file in DirAccess.get_files_at(save_dir):
		if not file.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [save_dir, file]))
		if parsed is Dictionary:
			var world: Dictionary = _decode(parsed)
			# Worlds saved before part 4.
			world.merge({"leaders": [], "fear": {}, "camps": [], "battles": [], "raids": [], "quietStart": null, "quietEnd": null, "quietUtcOffset": 0})
			world.next.merge({"leader": 1, "battle": 1, "camp": 1, "raid": 1})
			for w in world.waves:
				w.merge({"initial": w.composition.duplicate()})
			worlds[int(world.id)] = world


## Vector2i doesn't survive JSON: hexes are written as {"@hex": [q, r]}.
static func _encode(value: Variant) -> Variant:
	if value is Vector2i:
		return {"@hex": [value.x, value.y]}
	if value is Dictionary:
		var out := {}
		for k in value:
			out[k] = _encode(value[k])
		return out
	if value is Array:
		return value.map(_encode)
	return value


## JSON numbers come back as floats: whole ones become ints again.
static func _decode(value: Variant) -> Variant:
	if value is Dictionary:
		if value.size() == 1 and value.has("@hex"):
			return Vector2i(int(value["@hex"][0]), int(value["@hex"][1]))
		var out := {}
		for k in value:
			out[k] = _decode(value[k])
		return out
	if value is Array:
		return value.map(_decode)
	if value is float and value == floorf(value) and absf(value) < 9.0e15:
		return int(value)
	return value
