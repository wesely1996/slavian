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


# --- Quests (scheduler/quests.ts) -----------------------------------------------------

const DONE_KEPT := 30


## Sends the hero on one of its offers.
static func start_quest(server: LocalServer, world: Dictionary, hero: Dictionary, offer_id: String, now: int) -> Dictionary:
	if hero.status != "home":
		return LocalVillage.rule("%s must be at home, unhurt, to set out" % hero.name)
	var home := server.find_village(world, int(hero.villageId))
	if home.state.besieged:
		return LocalVillage.rule("%s won't leave %s in the middle of a battle" % [hero.name, home.name])
	var offer: Dictionary = {}
	for o in server.quest_offers(world, hero, now):
		if o.id == offer_id:
			offer = o
	if offer.is_empty():
		return LocalVillage.rule("That quest is no longer on offer")
	var returns_at := now + LocalHeroes.quest_ms(offer, world.speed)
	var away := hero.duplicate(true)
	away.status = "questing"
	var quest := offer.duplicate(true)
	quest.departsAt = LocalTime.iso(now)
	quest.returnsAt = LocalTime.iso(returns_at)
	away.quest = quest
	var done: Array = hero.questsDone + [offer.id]
	away.questsDone = done.slice(maxi(0, done.size() - DONE_KEPT))
	server.schedule(world, returns_at, "hero_quest", {"accountId": hero.accountId})
	return away


## The next horde from a front that hasn't set out yet.
static func _next_wave(world: Dictionary, front: Variant) -> Dictionary:
	var best: Dictionary = {}
	for w in world.waves:
		if w.front == front and w.status == "scheduled":
			if best.is_empty() or int(w.spawnAt) < int(best.spawnAt) or (int(w.spawnAt) == int(best.spawnAt) and int(w.id) < int(best.id)):
				best = w
	return best


## Does what the quest set out to do: what the hero has to tell, {body, vars}.
static func _fulfil(server: LocalServer, world: Dictionary, hero: Dictionary, quest: Dictionary, at: int, changed: Array) -> Dictionary:
	var data := server.data
	var home := server.find_village(world, int(hero.villageId))
	match String(quest.kind):
		"ambush":
			var wave := _next_wave(world, quest.front)
			if wave.is_empty():
				return {"body": "The road lay empty: that horde had already set out."}
			var delay := LocalWaves.js_round((float(data.quests.kinds.ambush.get("delayHours", 0)) * LocalTime.MS_PER_HOUR) / world.speed)
			wave.spawnAt = int(wave.spawnAt) + delay
			# Held up, it hates the more.
			wave.hatred = float(wave.get("hatred", 0.0)) + float(data.horde.hatred.perAmbush)
			for e in world.events:
				if e.status == "pending" and e.type in ["wave_spawn", "wave_warning"] and int(e.payload.get("waveId", -1)) == int(wave.id):
					e.dueAt = int(e.dueAt) + delay
			# Told in real minutes, at any world speed.
			return {"body": "The next horde from the {front} sets out {minutes} minutes later, hating you the more: +{hatred}% attack and defense.",
				"vars": {"front": quest.front if quest.front != null else "", "minutes": LocalWaves.js_round(delay / 60000.0), "hatred": LocalWaves.js_round(float(wave.hatred) * 100.0)}}
		"scout":
			var wave := _next_wave(world, quest.front)
			if wave.is_empty():
				return {"body": "That horde had already set out; the hero saw only its dust."}
			var tiers: Array = data.scouting.tiers.duplicate()
			var best: Dictionary = tiers[0]
			for t in tiers:
				if int(t.minSurvivors) > int(best.minSurvivors):
					best = t
			var sent := int(best.minSurvivors)
			var mission := LocalScouting.insert_mission(world, {"villageId": home.id, "waveId": wave.id, "sent": sent, "target": {"q": home.q, "r": home.r},
				"departsAt": LocalTime.parse(quest.departsAt), "arrivesAt": at, "returnsAt": at})
			mission.report = LocalScouting.scout_report(data, wave.front, wave.composition, wave.stance, sent, sent, false, int(world.seed), int(mission.id))
			mission.survivors = sent
			mission.status = "done"
			return {"body": "A full report on the next horde from the {front} is in the threats panel.",
				"vars": {"front": quest.front if quest.front != null else ""}}
		"caravan":
			var found := LocalHeroes.caravan_find(data, int(hero.level))
			home.state.ledger = LocalLogistics.receive(home.state.ledger, at, found).ledger
			changed.append(["village", home.id])
			return {"body": "Brought back {wood} wood, {stone} stone, {grain} grain and {iron} iron.", "vars": found}
		"hoard":
			var owned: Array = hero.inventory + hero.gear.values()
			var left: Array = data.heroes.items.keys().filter(func(i: String) -> bool: return not i in owned)
			left.sort()
			if left.is_empty():
				return {"body": "The hoard had been dug up already."}
			var rng := LocalRng.new((int(world.seed) ^ LocalRng.imul(int(hero.accountId) + 1, 0x165667b1) ^ left.size()) & 0xffffffff)
			var item: String = left[floori(rng.next() * left.size())]
			hero.inventory = hero.inventory + [item]
			return {"body": "Found the {item}.", "vars": {"item": data.heroes.items[item].name}}
		"ruins":
			var site: Dictionary = {}
			for s in world.sites:
				if quest.siteId != null and int(s.id) == int(quest.siteId):
					site = s
			if site.is_empty() or site.status == "explored" or LocalBattle.total(site.guardians) > 0:
				return {"body": "Someone had been there first."}
			var find := LocalSites.roll_find(data, site.kind, int(world.seed), int(site.id), LocalSites.distance_share(Vector2i(site.q, site.r), int(world.radius)),
				LocalResearch.scrolls(world), hero.inventory + hero.gear.values())
			if find.type == "resources":
				home.state.ledger = LocalLogistics.receive(home.state.ledger, at, find.resources).ledger
				changed.append(["village", home.id])
			LocalArmies.claim_find(server, world, site, hero.accountId, hero, find, at, changed)
			return {"body": "Searched the {site}.", "vars": {"site": data.sites.kinds.get(site.kind, {}).get("name", "site")}}
	return {"body": ""}


static func on_hero_quest(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var data := server.data
	var hero := LocalArmies.hero_of(world, int(event.payload.accountId))
	var quest: Variant = hero.get("quest")
	var at := int(event.dueAt)
	if hero.status != "questing" or quest == null or LocalTime.parse(quest.returnsAt) > at:
		return
	var told := _fulfil(server, world, hero, quest, at, changed)
	var name: String = hero.name
	var wounded := LocalHeroes.quest_wounds(quest, int(world.seed), int(hero.accountId), LocalTime.parse(quest.departsAt))
	hero.merge(LocalHeroes.gain_xp(data, hero, LocalHeroes.quest_xp(data, quest, hero.kind)), true)
	hero.status = "home"
	hero.quest = null
	if wounded:
		var until := at + LocalHeroes.wound_ms(data, world.speed, hero.kind, LocalGenerals.hall_level_at(server, world, hero.villageId))
		hero.status = "wounded"
		hero.woundedUntil = LocalTime.iso(until)
		server.schedule(world, until, "hero_recover", {"accountId": hero.accountId})
	var vars: Dictionary = told.get("vars", {}).duplicate()
	vars.merge({"name": name, "quest": data.quests.kinds[quest.kind].name}, true)
	LocalInbox.tell(server, world, hero.accountId, {"kind": "hero", "tier": "digest",
		"title": "{name} came back wounded from: {quest}" if wounded else "{name} is back from: {quest}", "body": told.body, "vars": vars}, at)
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
		"quest":
			next = start_quest(server, world, hero, String(body.get("offer", "")), now)
		_:
			return {"error": "Not in single player yet", "kind": "local"}
	if next.has("error"):
		return next
	hero.merge(next, true)
	return hero


## Sells a piece of the hero's spare gear at the village's Market
## (commands/village.ts sellGearCommand): {state} or {"error"}.
static func sell_gear(server: LocalServer, world: Dictionary, village: Dictionary, item: String, now: int) -> Dictionary:
	var hero: Dictionary = {}
	for h in world.heroes:
		if int(h.accountId) == int(village.ownerAccountId):
			hero = h
	if hero.is_empty():
		return {"error": "You have no hero in this world", "kind": "not_found"}
	var index: int = hero.inventory.find(item)
	if index < 0:
		return LocalVillage.rule("The hero carries no such spare item")
	var sold := LocalVillage.sell_gear(server.data, village.state, now)
	if sold.has("error"):
		return sold
	hero.inventory.remove_at(index)
	return sold
