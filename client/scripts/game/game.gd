extends Node
## What the client knows about the current world: the last state the server
## sent, plus the game data (buildings, terrain) it was built from.

signal world_changed
signal village_changed(village_id: int)
signal waves_changed
signal scouting_changed

var data: Dictionary = {}
var world: Dictionary = {}
var villages: Dictionary[int, Dictionary] = {}
var terrain: Dictionary[Vector2i, String] = {}
## Waves not yet dispersed, oldest first (see server waveView).
var waves: Array = []
## Scout missions with their shared reports, newest first.
var scouting: Array = []

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
