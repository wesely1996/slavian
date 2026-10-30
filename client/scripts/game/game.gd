extends Node
## What the client knows about the current world: the last state the server
## sent, plus the game data (buildings, terrain) it was built from.

signal world_changed
signal village_changed(village_id: int)
signal waves_changed
signal scouting_changed
signal battles_changed
signal raids_changed
signal caravans_changed
signal expeditions_changed
signal research_changed
signal heroes_changed
signal generals_changed
signal orders_changed
signal inbox_changed
signal armies_changed
signal forts_changed

var data: Dictionary = {}
var world: Dictionary = {}
var villages: Dictionary[int, Dictionary] = {}
var terrain: Dictionary[Vector2i, String] = {}
## Waves not yet dispersed, oldest first (see server waveView).
var waves: Array = []
## Scout missions with their shared reports, newest first.
var scouting: Array = []
## Ongoing battles first, then the most recent finished ones.
var battles: Array = []
## Outposts burned by passing hordes, newest first.
var raids: Array = []
## Caravan trips on the road, then the latest finished ones.
var caravans: Array = []
## The Holy City vault (see server vaultView).
var vault: Dictionary = {}
## Settlers on the road to found villages, then the latest that ended.
var expeditions: Array = []
## Everyone's research: {accountId, tech, status, completesAt, ...}.
var research: Array = []
## Your notifications in this world, newest first, and how many are unread.
var inbox: Array = []
var unread := 0
## Armies on the road or abroad, then the latest that came home.
var armies: Array = []
## Forts, built or being built (see server fortView).
var forts: Array = []
## Bandit camps and monster lairs: {id, kind, front, q, r, size}.
var camps: Array = []
## Ancient sites (see server worldView) and the group's lore scrolls.
var sites: Array = []
var lore: Array = []
## The Kalinov Bridge (see server sim/bridge.ts).
var bridge: Dictionary = {}
## Hand-overs still running, and what delegates did lately.
## River edges: [aq, ar, bq, br, crossing] (see RiverText).
var rivers: Array = []
## Roads: [aq, ar, bq, br, status] (see RiverText.roads_at).
var roads: Array = []
var delegations: Array = []
var delegation_log: Array = []
## How much hordes fear each hex where they were beaten.
var fear: Dictionary[Vector2i, float] = {}
## Standing orders of every village (see server orderView).
var orders: Array = []
## Every player's hero (see server heroView).
var heroes: Array = []
## Every player's generals (see server generalView).
var generals: Array = []
## Enemy leaders, living and fallen, one alive per front (server leaderView).
var leaders: Array = []
## Which of your villages the screens show (0: the first).
var current_village_id := 0

## The server's clock: what it read at a moment of the device's clock, and
## how fast it runs from there (1; a solo world played faster or slower
## runs at its own pace, Local.rate).
var _clock_at := 0.0
var _clock_real := 0.0
var time_rate := 1.0


func server_now() -> float:
	return _clock_at + (Time.get_unix_time_from_system() - _clock_real) * time_rate


func note_server_time(iso: String) -> void:
	_clock_at = TimeUtil.parse_iso(iso)
	_clock_real = Time.get_unix_time_from_system()


## How fast the clock runs; durations on screen follow it (TimeUtil.rate).
func set_time_rate(rate: float) -> void:
	_clock_at = server_now()
	_clock_real = Time.get_unix_time_from_system()
	time_rate = rate
	TimeUtil.rate = rate


func world_id() -> int:
	return int(world.get("id", 0))


func my_account_id() -> int:
	return Local.ACCOUNT_ID if world_id() < 0 else int(Session.account.get("id", 0))


## Fetches buildings/terrain definitions once per session.
func ensure_data() -> String:
	if not data.is_empty():
		return ""
	# Offline, the bundled data (the same the server reads) will do.
	if Local.is_active():
		data = Local.server.data
		return ""
	var response := await Api.get_json("/v1/data")
	if not response.ok:
		return response.error
	data = response.data
	return ""


func set_world(new_world: Dictionary) -> void:
	world = new_world
	Local.world_id = int(new_world.get("id", 0)) if int(new_world.get("id", 0)) < 0 else 0
	if new_world.has("serverTime"):
		note_server_time(new_world.serverTime)
	set_time_rate(Local.rate())
	var world_map: Variant = new_world.get("map")
	rivers = world_map.get("rivers", []) if world_map is Dictionary else []
	roads = world_map.get("roads", []) if world_map is Dictionary else []
	villages.clear()
	for village in new_world.get("villages", []):
		villages[int(village.id)] = village
	waves = new_world.get("waves", [])
	scouting = new_world.get("scouting", [])
	battles = new_world.get("battles", [])
	raids = new_world.get("raids", [])
	caravans = new_world.get("caravans", [])
	expeditions = new_world.get("expeditions", [])
	research = new_world.get("research", [])
	heroes = new_world.get("heroes", [])
	generals = new_world.get("generals", [])
	leaders = new_world.get("leaders", [])
	orders = new_world.get("orders", [])
	armies = new_world.get("armies", [])
	forts = new_world.get("forts", [])
	camps = new_world.get("camps", [])
	sites = new_world.get("sites", [])
	lore = new_world.get("lore", [])
	var new_bridge: Variant = new_world.get("bridge")
	bridge = new_bridge if new_bridge is Dictionary else {}
	delegations = new_world.get("delegations", [])
	delegation_log = new_world.get("delegationLog", [])
	fear.clear()
	for entry in new_world.get("fear", []):
		fear[Vector2i(int(entry[0]), int(entry[1]))] = float(entry[2])
	var new_vault: Variant = new_world.get("vault")
	vault = new_vault if new_vault is Dictionary else {}
	terrain.clear()
	var map: Variant = new_world.get("map")
	if map is Dictionary:
		for cell in map.hexes:
			terrain[Vector2i(int(cell[0]), int(cell[1]))] = cell[2]
	world_changed.emit()


## Waves, and the enemy leaders with them when the server sends those.
func set_waves(world_id_: int, new_waves: Array, new_leaders: Variant = null) -> void:
	if world_id_ != world_id():
		return
	waves = new_waves
	if new_leaders is Array:
		leaders = new_leaders
	waves_changed.emit()


func set_scouting(world_id_: int, missions: Array) -> void:
	if world_id_ != world_id():
		return
	scouting = missions
	scouting_changed.emit()


func set_battles(world_id_: int, new_battles: Array) -> void:
	if world_id_ != world_id():
		return
	battles = new_battles
	battles_changed.emit()


func set_raids(world_id_: int, new_raids: Array) -> void:
	if world_id_ != world_id():
		return
	raids = new_raids
	raids_changed.emit()


func set_armies(world_id_: int, new_armies: Array) -> void:
	if world_id_ != world_id():
		return
	armies = new_armies
	armies_changed.emit()


func set_forts(world_id_: int, new_forts: Array) -> void:
	if world_id_ != world_id():
		return
	forts = new_forts
	forts_changed.emit()


## The ancient site still waiting on `cell`; one explored is gone from the
## land.
func site_at(cell: Vector2i) -> Dictionary:
	for site in sites:
		if Vector2i(int(site.q), int(site.r)) == cell and site.status == "unexplored":
			return site
	return {}


## Scrolls the group has, as a set.
func scrolls() -> Dictionary:
	var found := {}
	for entry in lore:
		found[entry.scroll] = true
	return found


func camp_at(cell: Vector2i) -> Dictionary:
	for camp in camps:
		if Vector2i(int(camp.q), int(camp.r)) == cell:
			return camp
	return {}


## A fort or supply point by id ({} once it is gone).
func fort_at_id(id: int) -> Dictionary:
	for fort in forts:
		if int(fort.id) == id:
			return fort
	return {}


func fort_at(cell: Vector2i) -> Dictionary:
	for fort in forts:
		if Vector2i(int(fort.q), int(fort.r)) == cell:
			return fort
	return {}


## Where a battle is fought: the village, or the hex of a field battle.
func battle_place(battle: Dictionary) -> String:
	var setup: Variant = battle.get("setup")
	if setup is Dictionary and setup.get("holyCity", false):
		return tr("the Holy City")
	if battle.get("villageId") == null and battle.has("q"):
		return "(%d, %d)" % [int(battle.q), int(battle.r)]
	return village_name(battle.villageId)


func set_inbox(world_id_: int, notifications: Array, unread_count: int) -> void:
	if world_id_ != world_id():
		return
	inbox = notifications
	unread = unread_count
	inbox_changed.emit()


func set_orders(world_id_: int, new_orders: Array) -> void:
	if world_id_ != world_id():
		return
	orders = new_orders
	orders_changed.emit()


func orders_of(village_id: int, kind: String) -> Array:
	return orders.filter(func(o: Dictionary) -> bool: return int(o.villageId) == village_id and o.kind == kind)


func set_heroes(world_id_: int, new_heroes: Array) -> void:
	if world_id_ != world_id():
		return
	heroes = new_heroes
	heroes_changed.emit()


func set_generals(world_id_: int, new_generals: Array) -> void:
	if world_id_ != world_id():
		return
	generals = new_generals
	generals_changed.emit()


func my_generals() -> Array:
	return generals.filter(func(g: Dictionary) -> bool: return int(g.accountId) == my_account_id())


## The general commanding a village's garrison: the best at home there.
func general_at(village_id: int) -> Dictionary:
	var best: Dictionary = {}
	for g in generals:
		if g.status != "home" or g.villageId == null or int(g.villageId) != village_id:
			continue
		if best.is_empty() or int(g.level) > int(best.level) or (int(g.level) == int(best.level) and int(g.id) < int(best.id)):
			best = g
	return best


func my_hero() -> Dictionary:
	return hero_of(my_account_id())


func hero_of(account_id: int) -> Dictionary:
	for hero in heroes:
		if int(hero.accountId) == account_id:
			return hero
	return {}


## The hero standing in a village (home or wounded), if any.
func hero_at(village_id: int) -> Dictionary:
	for hero in heroes:
		if hero.villageId != null and int(hero.villageId) == village_id and hero.status != "traveling":
			return hero
	return {}


func set_research(world_id_: int, new_research: Array) -> void:
	if world_id_ != world_id():
		return
	research = new_research
	research_changed.emit()


func set_expeditions(world_id_: int, new_expeditions: Array) -> void:
	if world_id_ != world_id():
		return
	expeditions = new_expeditions
	expeditions_changed.emit()


## The villages you command (yours, and any a teammate handed you), oldest first.
func my_villages() -> Array:
	var mine := villages.values().filter(func(v: Dictionary) -> bool: return commands(v))
	mine.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.id) < int(b.id))
	return mine


## How many villages `owner` has (costs and garrisons scale with it).
func villages_owned(owner: int) -> int:
	return villages.values().filter(func(v: Dictionary) -> bool: return v.get("ownerAccountId") != null and int(v.ownerAccountId) == owner).size()


## The village the screens show: the one picked, else your first.
func current_village() -> Dictionary:
	var mine := my_villages()
	for village in mine:
		if int(village.id) == current_village_id:
			return village
	return mine[0] if not mine.is_empty() else {}


func set_logistics(world_id_: int, new_caravans: Array, new_vault: Dictionary) -> void:
	if world_id_ != world_id():
		return
	caravans = new_caravans
	vault = new_vault
	caravans_changed.emit()


## The village whose outpost stands on `cell`, if any.
func outpost_owner(cell: Vector2i) -> Dictionary:
	var plot := Rules.outpost_plot(cell)
	for village in villages.values():
		if village.get("plots", {}).has(plot):
			return village
	return {}


func leader(leader_id: Variant) -> Dictionary:
	if leader_id == null:
		return {}
	for entry in leaders:
		if int(entry.id) == int(leader_id):
			return entry
	return {}


## The horde's battle: the one going on, else its latest.
func battle_for(wave_id: int) -> Dictionary:
	var found := {}
	for battle in battles:
		if battle.waveId != null and int(battle.waveId) == wave_id:
			if battle.status == "ongoing":
				return battle
			if found.is_empty() or int(battle.id) > int(found.id):
				found = battle
	return found


func missions_for(wave_id: int) -> Array:
	return scouting.filter(func(m: Dictionary) -> bool: return int(m.waveId) == wave_id)


func village_name(village_id: Variant) -> String:
	if village_id == null:
		return tr("the Holy City")
	return villages.get(int(village_id), {}).get("name", tr("a village"))


func front_faction(front: String) -> String:
	return data.get("enemies", {}).get("fronts", {}).get(front, {}).get("faction", front.capitalize())


func update_village(village: Dictionary) -> void:
	villages[int(village.id)] = village
	village_changed.emit(int(village.id))


func village_at(cell: Vector2i) -> Dictionary:
	for village in villages.values():
		if int(village.q) == cell.x and int(village.r) == cell.y:
			return village
	return {}


func is_mine(village: Dictionary) -> bool:
	return int(village.get("ownerAccountId", -1)) == my_account_id()


## Yours, or handed to you by a teammate for now.
func commands(village: Dictionary) -> bool:
	if village.get("ownerAccountId") == null:
		return false
	return DelegationText.commands(delegations, int(village.ownerAccountId), my_account_id(), server_now())


## The player's research: what their Academies have brought in by now, and
## what comes in per hour.
func my_research() -> Dictionary:
	for member in world.get("members", []):
		if int(member.accountId) == my_account_id():
			return {"points": ResearchRules.points(member, server_now()), "perHour": float(member.get("research", {}).get("perHour", 0))}
	return {"points": 0.0, "perHour": 0.0}


func member_name(account_id: int) -> String:
	for member in world.get("members", []):
		if int(member.accountId) == account_id:
			return member.displayName
	return "?"
