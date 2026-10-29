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
## The player's language, for what the inbox tells them (accounts.language).
var language := "en"


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
			"heroKind": params.get("heroKind"), "onboarding": {}, "onboardingClaimed": {}, "researchPoints": 0, "researchSettledAt": null}],
		"villages": [], "heroes": [], "generals": [], "waves": [], "sites": [], "rivers": [], "roads": [], "events": [],
		"vault": {"level": 1, "amounts": {"wood": 0, "stone": 0, "grain": 0, "iron": 0}, "upgradingTo": null, "upgradeCompletesAt": null},
		"leaders": [], "fear": {}, "camps": [], "battles": [], "raids": [], "research": [], "lore": [], "caravans": [], "armies": [], "forts": [], "missions": [], "ruinSearches": [], "expeditions": [], "orders": [], "notifications": [], "quietStart": null, "quietEnd": null, "quietUtcOffset": 0,
		"next": {"village": 1, "wave": 1, "site": 1, "event": 1, "leader": 1, "battle": 1, "camp": 1, "raid": 1, "caravan": 1, "army": 1, "fort": 1, "mission": 1, "expedition": 1, "order": 1, "notification": 1, "general": 1, "ruinSearch": 1},
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
		world.rivers.append({"a": e.a, "b": e.b, "crossing": "standing" if e.bridge else "none", "size": int(e.size), "builtBy": null, "completesAt": null})
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
		refresh_bonuses(world, int(member.accountId), now)
	_ensure_sites(world)
	_place_starter_camps(world, now)
	world.bridge = {"stage": 0, "donated": {"wood": 0, "stone": 0, "grain": 0, "iron": 0}, "embers": 0, "quests": {},
		"stageStartedAt": LocalTime.iso(now), "sanctityAtStart": world.sanctity, "status": "open", "raisedAt": null}
	_announce_first_waves(world)
	LocalInbox.ensure_digests(self, world, now)
	world.hexes = _by_row(world.hexes)
	worlds[id] = world
	save(world)
	return world


## A small bandit camp near every village, the first one the getting-started
## quest sends an army to clear (scheduler/camps.ts placeStarterCamps).
func _place_starter_camps(world: Dictionary, now: int) -> void:
	var cells: Array = world.villages.map(func(v: Dictionary) -> Vector2i: return Vector2i(v.q, v.r))
	for i in world.villages.size():
		var village: Dictionary = world.villages[i]
		var cell := LocalCamps.starter_site(data, world.hexes, Vector2i(village.q, village.r), cells,
			LocalBattles.occupied_hexes(world), LocalWaves.rng_for(int(world.seed), i, 0x57))
		if cell == Vector2i.MAX:
			continue
		var front := LocalArmies.bandit_front(world, cell)
		var units := LocalWaves.compose_wave(data, front, 0, int(data.camps.starter.units), int(world.seed) ^ (0x5700 + i), world.members.size())
		LocalBattles.create_camp(self, world, {"kind": "bandit", "front": front, "q": cell.x, "r": cell.y, "units": units, "waveId": null}, now)


func insert_village(world: Dictionary, owner: int, name: String, at: Vector2i, state: Dictionary) -> Dictionary:
	var village := {"id": world.next.village, "ownerAccountId": owner, "name": name, "q": at.x, "r": at.y, "state": state,
		# Auto-reinforce defaults (migration 015): half the garrison, 4 hexes.
		"reinforce": {"share": 0.5, "range": 4}, "ruin": null, "refuge": false}
	world.next.village += 1
	world.villages.append(village)
	return village


## The map's hexes in the order the server reads them (db/worlds.ts
## loadHexes: by row, then column), which settles ties where code walks it.
static func _by_row(hexes: Dictionary) -> Dictionary:
	var cells: Array = hexes.keys().map(func(k: String) -> Vector2i:
		var parts := k.split(",")
		return Vector2i(int(parts[0]), int(parts[1])))
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var out := {}
	for cell in cells:
		out[LocalLand.key(cell)] = hexes[LocalLand.key(cell)]
	return out


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
## Gives each of the player's villages their current bonuses
## (scheduler/research.ts refreshBonuses).
func refresh_bonuses(world: Dictionary, account_id: int, at: int, changed: Array = []) -> void:
	var bonuses := player_bonuses(world, account_id)
	for village in world.villages:
		if int(village.ownerAccountId) == account_id:
			village.state = LocalVillage.with_bonuses(data, village.state, bonuses, at, world.speed)
			changed.append(["village", village.id])


## Research, the group's scrolls, the player's clan and hero
## (scheduler/research.ts playerBonuses).
func player_bonuses(world: Dictionary, account_id: int) -> Dictionary:
	var member: Dictionary = {}
	for m in world.members:
		if int(m.accountId) == account_id:
			member = m
	var own := LocalHeroes.combine(LocalVillage.clan_bonuses(data, member.get("clan")), LocalHeroes.roster_bonuses(data, member.get("heroKind")))
	var research := LocalResearch.bonuses_of(data, LocalResearch.known(world, account_id))
	var lore := LocalResearch.lore_bonuses(data, LocalResearch.scrolls(world))
	return LocalHeroes.combine(LocalHeroes.combine(research, lore), own)


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
	# Armies out on the map count too.
	var field: Array = world.armies.filter(func(a: Dictionary) -> bool: return a.status != "done" and LocalArmies.supplied(a))
	field.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.id) < int(b.id))
	for army in field:
		for unit in army.units:
			var def: Dictionary = data.units.units.get(unit, {})
			if def.get("family") in ["infantry", "archers", "cavalry"] and unit != "settler" and int(army.units[unit]) > 0:
				attack += int(army.units[unit]) * float(def.get("attack", 0))
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
	# A finished run stays readable, but nothing more can be done in it
	# (withWorld); the reinforce rule is set outside it.
	var answer: Dictionary
	if world.status in ["won", "lost"] and method != "GET" and not (method == "PUT" and path.ends_with("/reinforce")):
		answer = _fail(400, "rule", "This run is over")
	else:
		answer = _route(world, method, parts, body if body is Dictionary else {}, now, changed)
	answer.changed = changed
	save(world)
	return answer


func _route(world: Dictionary, method: String, parts: PackedStringArray, body: Dictionary, now: int, changed: Array) -> Dictionary:
	if method == "GET" and parts.size() == 3 and parts[1] == "worlds":
		return {"status": 200, "data": world_view(world, now)}
	# Quiet hours: no horde arrives in them (commands/worlds.ts setQuietHoursCommand).
	if method == "PUT" and parts.size() == 4 and parts[1] == "worlds" and parts[3] == "quiet":
		var start: Variant = body.get("start")
		var end: Variant = body.get("end")
		var none: bool = start == null or end == null or int(start) == int(end)
		world.quietStart = null if none else int(start)
		world.quietEnd = null if none else int(end)
		world.quietUtcOffset = 0 if none else int(body.get("utcOffsetMinutes", 0))
		changed.append(["world"])
		return {"status": 200, "data": world_view(world, now)}
	if parts.size() >= 4 and parts[1] == "worlds" and parts[3] == "notifications":
		if method == "GET" and parts.size() == 4:
			var inbox := LocalInbox.inbox_view(world, int(world.hostAccountId))
			inbox.serverTime = LocalTime.iso(now)
			return {"status": 200, "data": inbox}
		if method == "POST" and parts.size() == 5 and parts[4] == "read":
			LocalInbox.mark_all_read(world, int(world.hostAccountId), now)
			changed.append(["inbox"])
			return {"status": 200, "data": {"ok": true}}
	if method == "POST" and parts.size() == 5 and parts[1] == "worlds" and parts[3] == "onboarding" and parts[4] == "claim":
		var claimed := _claim_onboarding(world, String(body.get("step", "")), now, changed)
		if claimed.has("error"):
			return _rule_answer(claimed)
		var view := world_view(world, now)
		view.claimed = claimed
		return {"status": 200, "data": view}
	if method == "POST" and parts.size() == 5 and parts[1] == "worlds" and parts[3] == "hero":
		var hero := LocalHeroCommands.command(self, world, int(world.hostAccountId), parts[4], body, now)
		if hero.has("error"):
			return _rule_answer(hero)
		changed.append(["world"])
		return {"status": 200, "data": {"hero": _hero_view(world, hero, now), "serverTime": LocalTime.iso(now)}}
	if method == "POST" and parts.size() == 5 and parts[1] == "worlds" and parts[3] == "bridge":
		var bridge: Dictionary
		match parts[4]:
			"donate":
				bridge = LocalBridgeCommands.donate_command(self, world, body, now)
			"ritual":
				bridge = LocalBridgeCommands.ritual_command(self, world, now)
			_:
				return _fail(404, "not_found", "No such route")
		if bridge.has("error"):
			return _rule_answer(bridge)
		changed.append(["world"])
		return {"status": 200, "data": world_view(world, now)}
	if method == "POST" and parts.size() == 5 and parts[1] == "worlds" and parts[3] == "vault" and parts[4] == "upgrade":
		var vault := LocalLogistics.upgrade_vault(self, world, now)
		if vault.has("error"):
			return _rule_answer(vault)
		changed.append(["world"])
		return {"status": 200, "data": {"vault": LocalLogistics.vault_view(data, vault), "serverTime": LocalTime.iso(now)}}
	if method == "POST" and parts.size() == 4 and parts[1] == "generals":
		var general := LocalGenerals.command(self, world, int(world.hostAccountId), int(parts[2]), parts[3], body, now)
		if general.has("notFound"):
			return _fail(404, "not_found", "No such route")
		if general.has("error"):
			return _rule_answer(general)
		changed.append(["world"])
		if general.has("ok"):
			return {"status": 200, "data": {"ok": true, "serverTime": LocalTime.iso(now)}}
		return {"status": 200, "data": {"general": LocalGenerals.view(data, general), "serverTime": LocalTime.iso(now)}}
	if method == "POST" and parts.size() == 4 and parts[1] == "armies" and parts[3] in ["move", "disband", "resupply", "store"]:
		var found := LocalArmies.find_army(world, int(parts[2]))
		if found.is_empty():
			return _fail(404, "not_found", "No such army")
		var moved: Dictionary
		match parts[3]:
			"move":
				moved = LocalArmies.move(self, world, found, body, now)
			"disband":
				moved = LocalArmies.disband(self, world, found, now)
			"store":
				moved = LocalArmies.store_command(self, world, found, body, now)
			_:
				moved = LocalArmies.resupply_command(self, world, found, now)
		if moved.has("error"):
			return _rule_answer(moved)
		changed.append(["world"])
		return {"status": 200, "data": {"army": LocalArmies.army_view(moved), "serverTime": LocalTime.iso(now)}}
	if method == "POST" and parts.size() == 4 and parts[1] == "armies" and parts[3] == "recall":
		var army := LocalArmies.recall(self, world, int(parts[2]), now)
		if army.has("error"):
			return _rule_answer(army)
		changed.append(["world"])
		return {"status": 200, "data": {"army": LocalArmies.army_view(army), "serverTime": LocalTime.iso(now)}}
	if method == "PUT" and parts.size() == 4 and parts[1] == "villages" and parts[3] == "reinforce":
		var target := find_village(world, int(parts[2]))
		if target.is_empty():
			return _fail(404, "not_found", "Village %s not found" % parts[2])
		var set := LocalArmies.set_reinforce(data, target, body)
		if set.has("error"):
			return _rule_answer(set)
		changed.append(["village", target.id])
		return {"status": 200, "data": {"reinforce": body}}
	if parts.size() >= 4 and parts[1] == "villages" and method == "POST":
		var village := find_village(world, int(parts[2]))
		if village.is_empty():
			return _fail(404, "not_found", "Village %s not found" % parts[2])
		if int(village.ownerAccountId) != int(world.hostAccountId):
			return _fail(403, "forbidden", "Not your village")
		var action := "/".join(parts.slice(3))
		if action == "orders" or action.begins_with("orders/"):
			return _order_command(world, village, parts, body, now, changed)
		if action == "abandon":
			var gone := LocalLogistics.abandon_village(self, world, village, now)
			if gone.has("error"):
				return _rule_answer(gone)
			changed.append(["world"])
			return {"status": 200, "data": world_view(world, now)}
		# Only the village commands refuse ruins (ownVillageCommand); armies,
		# forts, roads and bridges go out from them all the same.
		if village.ruin != null and not action in ["rebuild", "armies", "forts", "supply-points", "crossings", "roads"]:
			return _fail(400, "rule", "%s lies in ruins; rebuild it first" % village.name)
		var result: Dictionary
		var step := ""
		# What the answer carries besides the village: [key, value].
		var extra: Array = []
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
			"research":
				result = LocalResearch.start_research(self, world, village, String(body.get("tech", "")), now)
				if result.has("research"):
					extra = ["research", LocalResearch.research_view(result.research)]
			"rebuild":
				result = LocalResearch.rebuild(self, world, village, now)
			"demolish":
				var plot := String(body.get("plot", ""))
				if not RegEx.create_from_string("^([fc]\\d{1,2}|w|t\\d{1,2})$").search(plot):
					return _fail(400, "invalid_request", "Give a plot")
				var standing: Variant = village.state.plots.get(plot, {}).get("building")
				result = LocalVillage.demolish(data, village.state, plot, now, world.speed)
				if result.has("refund"):
					extra = ["refund", result.refund]
					# Settled before the village changes (an Academy torn down).
					if data.buildings.buildings.get(standing, {}).get("research") != null:
						LocalResearch.settle_points(self, world, int(village.ownerAccountId), now)
			"market/trade":
				var give := String(body.get("give", ""))
				var get_ := String(body.get("get", ""))
				var amount: Variant = body.get("amount")
				if not give in LocalVillage.KINDS or not get_ in LocalVillage.KINDS or not (amount is float or amount is int) or float(amount) != floorf(float(amount)) or float(amount) < 1:
					return _fail(400, "invalid_request", "Give two resources and an amount")
				result = LocalVillage.trade(data, village.state, give, get_, int(amount), now)
				if result.has("got"):
					extra = ["got", result.got]
			"market/sell":
				result = LocalHeroCommands.sell_gear(self, world, village, String(body.get("item", "")), now)
			"dismiss":
				var units: Variant = body.get("units")
				if not units is Dictionary:
					return _fail(400, "invalid_request", "Say who to dismiss")
				var picked := {}
				for unit in units:
					if int(units[unit]) > 0:
						picked[unit] = int(units[unit])
				if picked.is_empty():
					return _fail(400, "rule", "Say who to dismiss")
				for unit in picked:
					if not data.units.units.has(unit):
						return _fail(400, "rule", "Unknown unit \"%s\"" % unit)
				result = {"state": LocalVillage.leave_garrison(data, village.state, picked, now, world.speed)}
				if result.state.has("error"):
					return _rule_answer(result.state)
			"generals":
				result = LocalGenerals.recruit(self, world, village, now)
				if result.has("general"):
					extra = ["general", LocalGenerals.view(data, result.general)]
			"scout":
				result = LocalScouting.send_scouts(self, world, village, body, now)
				if result.has("mission"):
					extra = ["mission", LocalScouting.mission_view(result.mission)]
					step = "scout"
			"scout/ruins":
				result = LocalScouting.search_ruins(self, world, village, body, now)
				if result.has("search"):
					extra = ["search", LocalScouting.ruin_search_view(result.search)]
			"found":
				result = LocalScouting.found_village(self, world, village, body, now)
				if result.has("expedition"):
					extra = ["expedition", LocalScouting.expeditions_view({"expeditions": [result.expedition]})[0]]
			"armies", "forts", "supply-points", "crossings", "roads":
				return _field_command(world, village, action, body, now, changed)
			"caravans", "caravans/fetch":
				result = LocalLogistics.send_caravan(self, world, village, body, now) if action == "caravans" else LocalLogistics.fetch_from_vault(self, world, village, body, now)
				if result.has("caravan"):
					extra = ["caravan", LocalLogistics.caravan_view(result.caravan)]
					step = result.get("onboarding", "")
			_:
				return _fail(501, "local", "Not in single player yet")
		if result.has("error") or result.has("missing"):
			return _rule_answer(result)
		village.state = result.state
		changed.append(["village", village.id])
		if action in ["research", "rebuild", "caravans", "caravans/fetch", "scout", "scout/ruins", "found", "market/sell", "generals"]:
			changed.append(["world"])
		if step != "":
			onboarding_step(world, int(village.ownerAccountId), step, now, changed)
		var answer := {"village": village_view(world, village), "serverTime": LocalTime.iso(now)}
		if not extra.is_empty():
			answer[extra[0]] = extra[1]
		return {"status": 200, "data": answer}
	return _fail(501, "local", "Not in single player yet")


## Standing orders: place one (answering the village and the order after
## its first run), or cancel one.
func _order_command(world: Dictionary, village: Dictionary, parts: PackedStringArray, body: Dictionary, now: int, changed: Array) -> Dictionary:
	changed.append(["village", village.id])
	changed.append(["world"])
	if parts.size() == 4:
		var order := LocalOrders.place(self, world, village, body, now)
		if order.has("error"):
			return _rule_answer(order)
		return {"status": 200, "data": {"village": village_view(world, village), "order": LocalOrders.order_view(order), "serverTime": LocalTime.iso(now)}}
	if parts.size() == 6 and parts[5] == "cancel":
		var done := LocalOrders.cancel(world, village, int(parts[4]))
		if done.has("error"):
			return _rule_answer(done)
		return {"status": 200, "data": {"ok": true, "serverTime": LocalTime.iso(now)}}
	return _fail(404, "not_found", "No such route")


## Commands that answer with what they made rather than the village
## (commands/armies.ts): an army, a fort, or the world for a road or bridge.
func _field_command(world: Dictionary, village: Dictionary, action: String, body: Dictionary, now: int, changed: Array) -> Dictionary:
	var result: Dictionary
	match action:
		"armies":
			result = LocalArmies.send_army(self, world, village, body, now)
		"forts", "supply-points":
			result = LocalArmies.build_fort(self, world, village, Vector2i(int(body.get("q", 0)), int(body.get("r", 0))), now, "supply" if action == "supply-points" else "fort")
		"crossings", "roads":
			var a: Dictionary = body.get("a", {})
			var b: Dictionary = body.get("b", {})
			var from := Vector2i(int(a.get("q", 0)), int(a.get("r", 0)))
			var to := Vector2i(int(b.get("q", 0)), int(b.get("r", 0)))
			result = LocalArmies.build_crossing(self, world, village, from, to, now) if action == "crossings" else LocalArmies.build_road(self, world, village, from, to, now)
	if result.has("error") or result.has("missing"):
		return _rule_answer(result)
	changed.append(["village", village.id])
	changed.append(["world"])
	match action:
		"armies":
			return {"status": 200, "data": {"army": LocalArmies.army_view(result), "serverTime": LocalTime.iso(now)}}
		"forts", "supply-points":
			return {"status": 200, "data": {"fort": LocalArmies.fort_view(result), "serverTime": LocalTime.iso(now)}}
	return {"status": 200, "data": world_view(world, now)}


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
	if LocalArmies.site_at(world, cell).get("status") == "unexplored":
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
func onboarding_step(world: Dictionary, account_id: int, step: String, now: int, changed: Array) -> void:
	if world.status != "running":
		return
	for member in world.members:
		if int(member.accountId) == account_id and not member.onboarding.has(step):
			for s in data.onboarding.steps:
				if s.id == step:
					member.onboarding[step] = LocalTime.iso(now)
					LocalInbox.tell(self, world, account_id, {"kind": "onboarding", "tier": "digest", "title": "Done: {step}",
						"body": "Claim its reward from the quest card.", "vars": {"step": s.title}}, now)
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
	match String(result.get("kind", "rule")):
		"not_found":
			return _fail(404, "not_found", String(result.error))
		"invalid":
			return _fail(400, "invalid_request", String(result.error))
		"local":
			return _fail(501, "local", String(result.error))
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
	# A finished run (won or lost) stands still.
	while processed < 10000 and not world.status in ["won", "lost"]:
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
	# An Academy's level changes what research comes in from now on.
	if data.buildings.buildings.get(p.building, {}).get("research") != null and village.ownerAccountId != null:
		LocalResearch.settle_points(self, world, int(village.ownerAccountId), int(event.dueAt))
	var done := LocalVillage.complete_build(data, village.state, plot, int(p.targetLevel), int(event.dueAt), world.speed)
	if done.has("error"):
		return
	village.state = done
	var def: Variant = data.buildings.buildings.get(p.building)
	var big: bool = p.building == "elder_hall" or int(p.targetLevel) >= int(data.notifications.bigBuildLevel)
	LocalInbox.tell(self, world, village.ownerAccountId, {"kind": "build_done", "tier": "push" if big else "digest",
		"title": "{building} level {level} in {village}", "body": "Finished. Your build queue may have room for more." if big else "Finished.",
		"vars": {"building": def.name if def != null else p.building, "level": int(p.targetLevel), "village": village.name}}, int(event.dueAt))
	var cell := LocalVillage.outpost_hex(plot)
	if cell != Vector2i.MAX and int(p.targetLevel) == 1:
		LocalHordes.outpost_standing(self, world, {"villageId": village.id, "plot": plot, "cell": cell}, int(event.dueAt))
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
	for c in world.caravans:
		for key in ["cargo", "carriedBack", "escort", "ambush"]:
			c[key] = LocalStore.stored(c[key])
	for a in world.armies:
		a.units = LocalStore.stored(a.units)
		a.loot = LocalStore.stored(a.loot)
	for s in world.sites:
		s.guardians = LocalStore.stored(s.guardians)
	for l in world.leaders:
		l.skills = LocalStore.stored(l.skills)
	for h in world.heroes:
		h.skills = LocalStore.stored(h.skills)
		h.gear = LocalStore.stored(h.gear)
	world.bridge = LocalStore.stored(world.bridge)
	for o in world.orders:
		o.spec = LocalStore.stored(o.spec)


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


func _on_supply_raid(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalBattles.on_supply_raid(self, world, event, changed)


func _on_camp_grow(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalBattles.on_camp_grow(self, world, event, changed)


func _on_research_complete(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalResearch.on_research_complete(self, world, event, changed)


func _on_caravan_arrive(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalLogistics.on_caravan_arrive(self, world, event, changed)


func _on_caravan_return(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalLogistics.on_caravan_return(self, world, event, changed)


func _on_caravan_ambush(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalLogistics.on_caravan_ambush(self, world, event, changed)


func _on_vault_upgrade(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalLogistics.on_vault_upgrade(self, world, event, changed)


func _on_hero_arrive(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalHeroCommands.on_hero_arrive(self, world, event, changed)


func _on_general_ready(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalGenerals.on_general_ready(self, world, event, changed)


func _on_general_arrive(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalGenerals.on_general_arrive(self, world, event, changed)



func _on_army_hunger(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalArmies.on_army_hunger(self, world, event, changed)


func _on_army_arrive(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalArmies.on_army_arrive(self, world, event, changed)


func _on_army_return(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalArmies.on_army_return(self, world, event, changed)


func _on_field_intercept(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalArmies.on_field_intercept(self, world, event, changed)


func _on_fort_complete(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalArmies.on_fort_complete(self, world, event, changed)


func _on_fort_check(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalArmies.on_fort_check(self, world, event, changed)


func _on_road_built(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalArmies.on_road_built(self, world, event, changed)


func _on_crossing_built(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalArmies.on_crossing_built(self, world, event, changed)


func _on_site_explored(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalArmies.on_site_explored(self, world, event, changed)


func _on_scout_arrive(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalScouting.on_scout_arrive(self, world, event, changed)


func _on_scout_return(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalScouting.on_scout_return(self, world, event, changed)


func _on_ruin_search(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalScouting.on_ruin_search(self, world, event, changed)


func _on_settlers_arrive(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalScouting.on_settlers_arrive(self, world, event, changed)


func _on_settlers_return(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalScouting.on_settlers_return(self, world, event, changed)


func _on_hero_quest(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalHeroCommands.on_hero_quest(self, world, event, changed)


func _on_orders_check(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalOrders.on_orders_check(self, world, event, changed)


func _on_bridge_raised(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalBridgeCommands.on_bridge_raised(self, world, event, changed)


func _on_ritual_check(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalBridgeCommands.on_ritual_check(self, world, event, changed)


func _on_hero_recover(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalBattles.on_hero_recover(self, world, event, changed)


func _on_wave_spawn(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalHordes.on_wave_spawn(self, world, event, changed)


func _on_wave_warning(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalInbox.on_wave_warning(self, world, event, changed)


func _on_daily_digest(world: Dictionary, event: Dictionary, changed: Array) -> void:
	LocalInbox.on_daily_digest(self, world, event, changed)


func _on_training_complete(world: Dictionary, event: Dictionary, changed: Array) -> void:
	var village := find_village(world, int(event.payload.villageId))
	if village.is_empty():
		return
	village.state = LocalVillage.complete_training(village.state, int(event.dueAt))
	changed.append(["village", village.id])


# --- Views (api/views.ts) -----------------------------------------------------

func world_view(world: Dictionary, now: int) -> Dictionary:
	var waves: Array = []
	var forecasts := _forecasts(world)
	for w in world.waves:
		if not w.status in ["dispersed", "defeated", "settled"]:
			waves.append(_wave_view(w, forecasts.get(w.id, {})))
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
		var settled: Variant = m.get("researchSettledAt")
		members.append({"accountId": m.accountId, "displayName": m.displayName, "clan": m.clan, "heroKind": m.heroKind,
			"onboarding": m.onboarding, "onboardingClaimed": m.onboardingClaimed,
			"research": {"points": m.get("researchPoints", 0), "perHour": LocalResearch.research_rate(self, world, int(m.accountId)),
				"settledAt": LocalTime.iso(settled) if settled != null else null}})
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
	var by_ends := func(a: Array, b: Array) -> bool:
		for i in 4:
			if a[i] != b[i]:
				return a[i] < b[i]
		return false
	rivers.sort_custom(by_ends)
	var roads: Array = []
	for e in world.roads:
		var ab := _ordered(e.a, e.b)
		roads.append([ab[0].x, ab[0].y, ab[1].x, ab[1].y, e.status, int(e.get("level", 1))])
	roads.sort_custom(by_ends)
	return {
		"id": world.id, "name": world.name, "status": world.status, "inviteCode": null, "speed": world.speed,
		"maxPlayers": world.maxPlayers, "hostAccountId": world.hostAccountId, "startedAt": LocalTime.iso(world.startedAt),
		"sanctity": world.sanctity, "embers": world.embers, "difficulty": world.difficulty, "quietHours": _quiet_window(world),
		"ritualAt": LocalTime.iso(world.ritualAt) if world.ritualAt != null else null,
		"endedAt": LocalTime.iso(world.endedAt) if world.endedAt != null else null,
		"members": members, "villages": villages, "waves": waves, "scouting": LocalScouting.missions_view(self, world), "ruinSearches": LocalScouting.ruin_searches_view(world), "battles": _battles_view(world), "raids": _raids_view(world),
		"expeditions": LocalScouting.expeditions_view(world),
		"research": LocalResearch.entries(world).map(LocalResearch.research_view), "heroes": heroes, "generals": world.generals.map(func(g: Dictionary) -> Dictionary: return LocalGenerals.view(data, g)), "leaders": LocalHordes.leaders_view(data, world), "orders": world.orders.map(LocalOrders.order_view), "armies": LocalArmies.armies_view(world), "forts": world.forts.map(LocalArmies.fort_view), "camps": _camps_view(world), "sites": sites,
		"lore": world.lore.map(func(l: Dictionary) -> Dictionary:
			return {"scroll": l.scroll, "accountId": l.accountId, "siteId": l.siteId, "foundAt": LocalTime.iso(l.foundAt)}),
		"bridge": world.bridge, "fear": _fear_view(world), "delegations": [], "delegationLog": [], "run": LocalBridgeCommands.run_summary(world),
		"caravans": LocalLogistics.caravans_view(world), "vault": LocalLogistics.vault_view(data, world.vault),
		"map": {"radius": world.radius, "activeFronts": world.activeFronts, "hexes": hexes, "rivers": rivers, "roads": roads},
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


## The quiet hours as the server shows them (db/worlds.ts quietWindow), or
## null for none.
static func _quiet_window(world: Dictionary) -> Variant:
	var start: Variant = world.get("quietStart")
	var end: Variant = world.get("quietEnd")
	if start == null or end == null or int(start) == int(end):
		return null
	return {"start": int(start), "end": int(end), "utcOffsetMinutes": int(world.get("quietUtcOffset", 0))}


## Where each scheduled wave is expected to go, by wave id: its march
## planned as at spawn from today's villages and fear (scheduler/waves.ts
## forecastMarches).
func _forecasts(world: Dictionary) -> Dictionary:
	var out := {}
	var scheduled: Array = world.waves.filter(func(w: Dictionary) -> bool: return w.status == "scheduled")
	if scheduled.is_empty():
		return out
	var land := LocalHordes.land_of(world)
	var villages: Array = []
	for v in world.villages:
		if v.ruin == null:
			villages.append({"id": v.id, "q": v.q, "r": v.r})
	var fear := LocalHordes.fear_of(self, world)
	for w in scheduled:
		var march := LocalHordes.plan_march(data, land, w, villages, int(world.seed), int(w.spawnAt), world.speed, fear)
		if not march.is_empty():
			out[w.id] = LocalHordes.hold_for_quiet(world, int(w.spawnAt), march)
	return out


func _wave_view(w: Dictionary, forecast := {}) -> Dictionary:
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
		"struck": w.struck, "ritual": w.ritual, "leaderId": w.leaderId,
		"forecast": null if forecast.is_empty() else {
			"spawn": {"q": forecast.spawn.x, "r": forecast.spawn.y}, "targetVillageId": forecast.targetVillageId,
			"path": forecast.path.map(func(step: Dictionary) -> Array: return [step.q, step.r, step.atMs]),
			"arrivesAt": LocalTime.iso(int(forecast.arrivesAt))}}


func _hero_view(world: Dictionary, h: Dictionary, now: int) -> Dictionary:
	return {
		"accountId": h.accountId, "kind": h.kind, "name": h.name, "status": h.status, "villageId": h.villageId, "armyId": h.armyId,
		"level": h.level, "xp": h.xp, "xpToNext": null if int(h.level) >= int(data.heroes.maxLevel) else LocalHeroes.xp_to_next(data, int(h.level)),
		"skillPoints": h.skillPoints, "skills": h.skills, "gear": h.gear, "inventory": h.inventory, "bonuses": LocalHeroes.hero_bonuses(data, h),
		"path": h.path.map(func(st: Dictionary) -> Array: return [st.q, st.r, st.atMs]) if h.path != null else null,
		"departsAt": h.departsAt, "arrivesAt": h.arrivesAt, "woundedUntil": h.woundedUntil, "quest": h.quest,
		"offers": quest_offers(world, h, now),
	}


## The quests a hero is offered now (scheduler/quests.ts heroQuestOffers).
func quest_offers(world: Dictionary, hero: Dictionary, now: int) -> Array:
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


## Forgets a world and removes its save.
func delete_world(id: int) -> void:
	worlds.erase(id)
	if save_dir != "":
		DirAccess.remove_absolute("%s/%d.json" % [save_dir, -id])


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
			world.merge({"leaders": [], "fear": {}, "camps": [], "battles": [], "raids": [], "research": [], "lore": [], "caravans": [],
				"armies": [], "forts": [], "missions": [], "expeditions": [], "orders": [], "notifications": [], "quietStart": null, "quietEnd": null, "quietUtcOffset": 0})
			world.next.merge({"leader": 1, "battle": 1, "camp": 1, "raid": 1, "caravan": 1, "army": 1, "fort": 1, "mission": 1, "expedition": 1, "order": 1,
				"notification": 1, "general": 1})
			# Worlds saved before generals.
			world.merge({"generals": []})
			# Worlds saved before ruin searches.
			world.merge({"ruinSearches": []})
			world.next.merge({"ruinSearch": 1})
			for a in world.armies:
				a.merge({"generalId": null})
				# Armies from before supplies: fed by their home village.
				a.merge({"supply": null, "supplyAt": null, "hungrySince": null, "hungerAt": null})
			for e in world.rivers:
				e.merge({"builtBy": null, "completesAt": null})
			# Roads from before road levels: level 1, as fast as they were.
			for e in world.roads:
				e.merge({"level": 1})
			# Worlds saved before supply points and grain in forts.
			for f in world.forts:
				f.merge({"kind": "fort", "grain": 0.0})
			for c in world.caravans:
				c.merge({"destinationFortId": null})
			world.hexes = _by_row(world.hexes)
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
