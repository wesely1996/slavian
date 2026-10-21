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
		"next": {"village": 1, "wave": 1, "site": 1, "event": 1},
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
		_insert_village(world, member.accountId, town, site, LocalVillage.new_village(data, now, speed))
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


func _insert_village(world: Dictionary, owner: int, name: String, at: Vector2i, state: Dictionary) -> Dictionary:
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
	var member: Dictionary = {}
	for m in world.members:
		if int(m.accountId) == account_id:
			member = m
	var own := LocalHeroes.combine(LocalVillage.clan_bonuses(data, member.get("clan")), LocalHeroes.roster_bonuses(data, member.get("heroKind")))
	var bonuses := LocalHeroes.combine(LocalHeroes.combine({}, {}), own)
	for village in world.villages:
		if int(village.ownerAccountId) == account_id:
			village.state = LocalVillage.with_bonuses(data, village.state, bonuses, at, world.speed)


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
	var ctx := {"seed": world.seed, "activeFronts": world.activeFronts, "playerCount": world.members.size(), "startedAt": world.startedAt, "worldSpeed": world.speed}
	var previous: Variant = null
	for index in int(data.waves.upcoming):
		var factor := LocalWaves.wave_factor(data, world.difficulty, _group_power(world, index))
		var planned := LocalWaves.plan_wave(data, ctx.merged({"sizeFactor": factor}), index, previous)
		var wave := {"id": world.next.wave, "index": planned.index, "front": planned.front, "status": "scheduled", "threat": planned.threat,
			"stance": planned.stance, "composition": planned.composition, "spawnAt": planned.spawnAt, "spawn": null, "targetVillageId": null,
			"path": null, "arrivesAt": null, "endsAt": null, "rampageEndsAt": null, "struck": [], "ritual": false, "leaderId": null}
		world.next.wave += 1
		world.waves.append(wave)
		_schedule(world, planned.spawnAt, "wave_spawn", {"waveId": wave.id})
		previous = planned.spawnAt


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


func _schedule(world: Dictionary, due_at: int, type: String, payload: Dictionary) -> void:
	world.events.append({"id": world.next.event, "dueAt": due_at, "type": type, "payload": payload, "status": "pending"})
	world.next.event += 1


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
		"members": members, "villages": villages, "waves": waves, "scouting": [], "battles": [], "raids": [], "expeditions": [],
		"research": [], "heroes": heroes, "leaders": [], "orders": [], "armies": [], "forts": [], "camps": [], "sites": sites,
		"lore": [], "bridge": world.bridge, "fear": [], "delegations": [], "delegationLog": [], "run": null, "caravans": [],
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
