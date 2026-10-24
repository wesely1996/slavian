class_name LocalResearch
extends RefCounted
## Research and rebuilding for the local engine: server/src/sim/research.ts,
## commands/village.ts (startResearchCommand, rebuildCommand) and
## scheduler/research.ts.

const ACADEMY := "academy"


static func bonuses_of(data: Dictionary, techs: Array) -> Dictionary:
	var bonuses := {}
	for tech in techs:
		var effects: Dictionary = data.research.techs.get(tech, {}).get("effects", {})
		for key in effects:
			bonuses[key] = float(bonuses.get(key, 0.0)) + float(effects[key])
	return bonuses


## sim/sites.ts loreBonuses.
static func lore_bonuses(data: Dictionary, scrolls: Array) -> Dictionary:
	var bonuses := {}
	for scroll in scrolls:
		var effects: Dictionary = data.lore.scrolls.get(scroll, {}).get("effects", {})
		for key in effects:
			bonuses[key] = float(bonuses.get(key, 0.0)) + float(effects[key])
	return bonuses


## Why a player can't start `tech` ("" when they can).
static func research_problem(data: Dictionary, tech: String, academy_level: int, done: Array, researching: bool, scrolls: Array) -> String:
	var def: Variant = data.research.techs.get(tech)
	if def == null:
		return "Unknown tech \"%s\"" % tech
	if tech in done:
		return "%s is already known" % def.name
	if researching:
		return "Your scholars are busy; one tech at a time"
	if def.get("requiresScroll") != null and not def.requiresScroll in scrolls:
		var scroll: Variant = data.lore.scrolls.get(def.requiresScroll)
		return "%s needs the %s scroll" % [def.name, scroll.name if scroll != null else def.requiresScroll]
	if academy_level < int(def.academyLevel):
		return "%s needs an Academy of level %d" % [def.name, int(def.academyLevel)]
	var missing: Array = []
	for t in def.requires:
		if not t in done:
			missing.append(data.research.techs[t].name)
	if not missing.is_empty():
		return "%s needs %s first" % [def.name, " and ".join(missing)]
	return ""


## Research a tech takes, besides its cost in resources.
static func research_cost(data: Dictionary, tech: String) -> int:
	return LocalWaves.js_round(float(data.research.techs[tech].seconds) * float(data.research.researchPerSecond))


static func member(world: Dictionary, account_id: int) -> Dictionary:
	for m in world.members:
		if int(m.accountId) == account_id:
			return m
	return {}


## Research per hour the player's Academies bring in, as their villages stand.
static func research_rate(server: LocalServer, world: Dictionary, account_id: int) -> float:
	var rate := 0.0
	for v in world.villages:
		if v.ownerAccountId != null and int(v.ownerAccountId) == account_id:
			rate += LocalVillage.research_per_hour(server.data, v.state.plots, world.speed)
	return rate


## The player's research as of `at` (scheduler/research.ts settleResearchPoints,
## without saving it).
static func points_at(server: LocalServer, world: Dictionary, account_id: int, at: int) -> float:
	var m := member(world, account_id)
	var amount := float(m.get("researchPoints", 0))
	var settled: Variant = m.get("researchSettledAt")
	if settled == null:
		return amount
	return amount + (research_rate(server, world, account_id) * maxi(0, LocalLedger.minutes_between(int(settled), at))) / 60.0


## Credits the player's research up to `at`. Called before anything changes
## what their Academies bring in.
static func settle_points(server: LocalServer, world: Dictionary, account_id: int, at: int) -> float:
	var amount := points_at(server, world, account_id, at)
	var m := member(world, account_id)
	m.researchPoints = amount
	m.researchSettledAt = at
	return amount


static func research_ms(data: Dictionary, tech: String, world_speed: float, bonuses: Dictionary = {}) -> int:
	var def: Dictionary = data.research.techs[tech]
	return LocalWaves.js_round((float(def.seconds) * 1000.0 * maxf(0.1, 1.0 + float(bonuses.get("researchTime", 0.0)))) / world_speed)


## The account's entries, in the server's order (account, completesAt, tech).
static func entries(world: Dictionary, account_id: Variant = null) -> Array:
	var out: Array = world.research.filter(func(e: Dictionary) -> bool: return account_id == null or int(e.accountId) == int(account_id))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.accountId) != int(b.accountId):
			return int(a.accountId) < int(b.accountId)
		if int(a.completesAt) != int(b.completesAt):
			return int(a.completesAt) < int(b.completesAt)
		return String(a.tech) < String(b.tech))
	return out


static func known(world: Dictionary, account_id: int) -> Array:
	return entries(world, account_id).filter(func(e: Dictionary) -> bool: return e.status == "done").map(func(e: Dictionary) -> String: return e.tech)


static func scrolls(world: Dictionary) -> Array:
	return world.lore.map(func(l: Dictionary) -> String: return l.scroll)


static func start_research(server: LocalServer, world: Dictionary, village: Dictionary, tech: String, now: int) -> Dictionary:
	var data := server.data
	var account := int(village.ownerAccountId)
	var mine := entries(world, account)
	var problem := research_problem(data, tech, int(village.state.levels.get(ACADEMY, 0)), known(world, account),
		mine.any(func(e: Dictionary) -> bool: return e.status == "researching"), scrolls(world))
	if problem != "":
		return LocalVillage.rule(problem)
	# Research comes from all the player's Academies, resources from this village.
	var needed := research_cost(data, tech)
	var points := points_at(server, world, account, now)
	if points < needed:
		return LocalVillage.rule("%s takes %d research; your Academies have brought in %d" % [data.research.techs[tech].name, needed, floori(points)])
	var ledger := LocalLedger.spend(village.state.ledger, now, data.research.techs[tech].cost)
	if ledger.has("missing"):
		return ledger
	var m := member(world, account)
	m.researchPoints = points - needed
	m.researchSettledAt = now
	var entry := {"accountId": account, "tech": tech, "status": "researching", "villageId": village.id, "startedAt": now,
		"completesAt": now + research_ms(data, tech, world.speed, village.state.bonuses)}
	world.research.append(entry)
	server.schedule(world, int(entry.completesAt), "research_complete", {"accountId": account, "tech": tech})
	var state: Dictionary = village.state.duplicate()
	state.ledger = ledger
	return {"state": state, "research": entry}


static func on_research_complete(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var p: Dictionary = event.payload
	for e in world.research:
		if int(e.accountId) == int(p.accountId) and e.tech == p.tech and e.status == "researching":
			e.status = "done"
			server.refresh_bonuses(world, int(p.accountId), int(event.dueAt), changed)
			var def: Dictionary = server.data.research.techs.get(p.tech, {})
			LocalInbox.tell(server, world, int(p.accountId), {"kind": "research_done", "tier": "digest", "title": "{tech} researched",
				"body": def.get("description", ""), "vars": {"tech": def.get("name", p.tech)}}, int(event.dueAt))
			changed.append(["world"])
			return


static func research_view(e: Dictionary) -> Dictionary:
	return {"accountId": e.accountId, "tech": e.tech, "status": e.status, "villageId": e.villageId,
		"startedAt": LocalTime.iso(e.startedAt), "completesAt": LocalTime.iso(e.completesAt)}


## Rebuilds a razed village: pays a share of what stood, and it stands
## again after the rebuild time.
static func rebuild(server: LocalServer, world: Dictionary, village: Dictionary, now: int) -> Dictionary:
	if village.ruin == null:
		return LocalVillage.rule("%s is not in ruins" % village.name)
	if village.ruin.rebuildingUntil != null:
		return LocalVillage.rule("%s is already being rebuilt" % village.name)
	var ledger := LocalLedger.spend(village.state.ledger, now, LocalHorde.rebuild_cost(server.data, village.ruin.plots))
	if ledger.has("missing"):
		return ledger
	var until := LocalTime.ms(now + LocalHorde.rebuild_ms(server.data, world.speed))
	village.ruin.rebuildingUntil = LocalTime.iso(until)
	server.schedule(world, until, "village_rebuilt", {"villageId": village.id})
	var state: Dictionary = village.state.duplicate()
	state.ledger = ledger
	return {"state": state}
