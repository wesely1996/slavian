class_name LocalHeroCommands
extends RefCounted
## The player's hero for the local engine: server/src/commands/heroes.ts,
## sim/heroes.ts (skills and gear) and scheduler/heroes.ts (hero_arrive).
## Each command answers the changed hero, or {"error"}.


static func learn_skill(data: Dictionary, hero: Dictionary, skill: String) -> Dictionary:
	var def: Variant = data.heroes.skills.get(skill)
	if def == null:
		return LocalVillage.rule("Unknown skill \"%s\"" % skill)
	if int(hero.skillPoints) < 1:
		return LocalVillage.rule("No skill points left; they come with levels")
	var rank := int(hero.skills.get(skill, 0))
	if rank >= int(def.maxRank):
		return LocalVillage.rule("%s is already at its highest rank" % def.name)
	var next := hero.duplicate(true)
	next.skillPoints = int(hero.skillPoints) - 1
	next.skills[skill] = rank + 1
	return next


## Puts an item from the pack into its slot; what was there goes back.
static func equip(data: Dictionary, hero: Dictionary, item: String) -> Dictionary:
	var def: Variant = data.heroes.items.get(item)
	if def == null or not item in hero.inventory:
		return LocalVillage.rule("The hero has no such item")
	var previous: Variant = hero.gear.get(def.slot)
	var next := hero.duplicate(true)
	next.inventory = hero.inventory.filter(func(i: String) -> bool: return i != item)
	next.gear[def.slot] = item
	if previous != null:
		next.inventory.append(previous)
	return next


static func unequip(hero: Dictionary, slot: String) -> Dictionary:
	var item: Variant = hero.gear.get(slot)
	if item == null:
		return LocalVillage.rule("Nothing in that slot")
	var next := hero.duplicate(true)
	next.gear.erase(slot)
	next.inventory.append(item)
	return next


## Sends the hero to another of the player's villages.
static func move(server: LocalServer, world: Dictionary, hero: Dictionary, village_id: int, now: int) -> Dictionary:
	var data := server.data
	match String(hero.status):
		"wounded":
			return LocalVillage.rule("%s is wounded" % hero.name)
		"traveling":
			return LocalVillage.rule("%s is already on the road" % hero.name)
		"with_army":
			return LocalVillage.rule("%s is leading an army" % hero.name)
		"questing":
			return LocalVillage.rule("%s is away on a quest" % hero.name)
	if hero.villageId != null and int(hero.villageId) == village_id:
		return LocalVillage.rule("%s is already there" % hero.name)
	var destination := server.find_village(world, village_id)
	if destination.is_empty() or int(destination.ownerAccountId) != int(hero.accountId):
		return LocalVillage.rule("Heroes only travel between your own villages")
	var from: Dictionary = server.find_village(world, int(hero.villageId)) if hero.villageId != null else {}
	if from.is_empty():
		return LocalVillage.rule("%s has no village to leave from" % hero.name)
	if from.state.besieged:
		return LocalVillage.rule("%s won't leave %s in the middle of a battle" % [hero.name, from.name])
	var path: Variant = LocalLogistics.road_route(data, LocalHordes.land_of(world), Vector2i(from.q, from.r), Vector2i(destination.q, destination.r),
		float(data.heroes.speed) * LocalHeroes.hero_factor(data, hero.kind, "heroSpeed"), world.speed)
	if path == null:
		return LocalVillage.rule("No road leads there")
	var arrives_at := now + int(path[-1].atMs)
	server.schedule(world, arrives_at, "hero_arrive", {"accountId": hero.accountId})
	var next := hero.duplicate(true)
	next.status = "traveling"
	next.villageId = destination.id
	next.path = path
	next.departsAt = LocalTime.iso(now)
	next.arrivesAt = LocalTime.iso(arrives_at)
	return next


static func on_hero_arrive(_server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	for hero in world.heroes:
		if int(hero.accountId) != int(event.payload.accountId):
			continue
		if hero.status != "traveling" or hero.arrivesAt == null or LocalTime.parse(hero.arrivesAt) > int(event.dueAt):
			return
		hero.status = "home"
		hero.path = null
		hero.departsAt = null
		hero.arrivesAt = null
		changed.append(["world"])


## Runs a hero command for `account_id`: {status, data} as the route answers.
static func command(server: LocalServer, world: Dictionary, account_id: int, action: String, body: Dictionary, now: int) -> Dictionary:
	var hero: Dictionary = {}
	for h in world.heroes:
		if int(h.accountId) == account_id:
			hero = h
	if hero.is_empty():
		return {"error": "No hero in this world", "kind": "not_found"}
	var data := server.data
	var next: Dictionary
	match action:
		"skills":
			next = learn_skill(data, hero, String(body.get("skill", "")))
		"equip":
			next = equip(data, hero, String(body.get("item", "")))
		"unequip":
			next = unequip(hero, String(body.get("slot", "")))
		"rename":
			var name := String(body.get("name", "")).strip_edges()
			if name == "" or name.length() > 32:
				return {"error": "Give the hero a name of 1 to 32 letters", "kind": "invalid"}
			next = hero.duplicate(true)
			next.name = name
		"move":
			next = move(server, world, hero, int(body.get("villageId", 0)), now)
		_:
			return {"error": "Not in single player yet", "kind": "local"}
	if next.has("error"):
		return next
	hero.merge(next, true)
	return hero
