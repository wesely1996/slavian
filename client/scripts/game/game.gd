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
signal orders_changed
signal inbox_changed

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
## Standing orders of every village (see server orderView).
var orders: Array = []
## Every player's hero (see server heroView).
var heroes: Array = []
## Which of your villages the screens show (0: the first).
var current_village_id := 0

## Server clock minus local clock, in seconds.
var _clock_offset := 0.0


func server_now() -> float:
	return Time.get_unix_time_from_system() + _clock_offset


func note_server_time(iso: String) -> void:
	_clock_offset = TimeUtil.parse_iso(iso) - Time.get_unix_time_from_system()


func world_id() -> int:
	return int(world.get("id", 0))


func my_account_id() -> int:
	return int(Session.account.get("id", 0))


## Fetches buildings/terrain definitions once per session.
func ensure_data() -> String:
	if not data.is_empty():
		return ""
	var response := await Api.get_json("/v1/data")
	if not response.ok:
		return response.error
	data = response.data
	return ""


func set_world(new_world: Dictionary) -> void:
	world = new_world
	if new_world.has("serverTime"):
		note_server_time(new_world.serverTime)
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
	orders = new_world.get("orders", [])
	var new_vault: Variant = new_world.get("vault")
	vault = new_vault if new_vault is Dictionary else {}
	terrain.clear()
	var map: Variant = new_world.get("map")
	if map is Dictionary:
		for cell in map.hexes:
			terrain[Vector2i(int(cell[0]), int(cell[1]))] = cell[2]
	world_changed.emit()


func set_waves(world_id_: int, new_waves: Array) -> void:
	if world_id_ != world_id():
		return
	waves = new_waves
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


## Your villages, oldest first.
func my_villages() -> Array:
	var mine := villages.values().filter(func(v: Dictionary) -> bool: return is_mine(v))
	mine.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.id) < int(b.id))
	return mine


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


func battle_for(wave_id: int) -> Dictionary:
	for battle in battles:
		if int(battle.waveId) == wave_id:
			return battle
	return {}


func missions_for(wave_id: int) -> Array:
	return scouting.filter(func(m: Dictionary) -> bool: return int(m.waveId) == wave_id)


func village_name(village_id: Variant) -> String:
	if village_id == null:
		return "the Holy City"
	return villages.get(int(village_id), {}).get("name", "a village")


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


func member_name(account_id: int) -> String:
	for member in world.get("members", []):
		if int(member.accountId) == account_id:
			return member.displayName
	return "?"
