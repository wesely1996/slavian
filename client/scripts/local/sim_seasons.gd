class_name LocalSeasons
## Seasons in a solo world (sim/seasons.ts, scheduler/seasons.ts): one game
## day each, in turn from the run's start. At each turn (season_turn) every
## settlement's grain follows the new season and the player hears of it.


static func day_ms(data: Dictionary, world_speed: float) -> float:
	return (float(data.seasons.dayHours) * LocalTime.MS_PER_HOUR) / world_speed


## {season, day, startsAt, endsAt} at `at` (before the start: its first).
static func season_at(data: Dictionary, world: Dictionary, at: int) -> Dictionary:
	var start: int = int(world.startedAt) if world.get("startedAt") != null else at
	var length := day_ms(data, float(world.speed))
	var day := maxi(0, floori(float(at - start) / length))
	var starts_at := start + day * length
	var order: Array = data.seasons.order
	return {"season": String(order[day % order.size()]), "day": day, "startsAt": LocalTime.ms(starts_at), "endsAt": LocalTime.ms(starts_at + length)}


## What a season adds to every unit's defense in battle, as a factor.
static func defense(data: Dictionary, season: String) -> float:
	return 1.0 + float(data.seasons.seasons[season].defense)


## The settlement bonus a season gives (none in spring).
static func bonuses(data: Dictionary, season: String) -> Dictionary:
	var grain := float(data.seasons.seasons[season].grain)
	return {} if grain == 0.0 else {"season.grain": grain}


## How likely a front is to send a horde in `season`.
static func front_weight(data: Dictionary, season: String, front: String) -> float:
	return float(data.seasons.seasons[season].fronts.get(front, 1.0))


## The defense factor of the season at `at` in this world.
static func defense_at(data: Dictionary, world: Dictionary, at: int) -> float:
	return defense(data, String(season_at(data, world, at).season))


## scheduler/seasons.ts applySeason: every settlement on the season of `at`.
static func apply(server: LocalServer, world: Dictionary, at: int) -> void:
	var data := server.data
	var given := bonuses(data, String(season_at(data, world, at).season))
	for village in world.villages:
		if village.state.bonuses.get("season.grain") == given.get("season.grain"):
			continue
		village.state = LocalVillage.with_season(data, village.state, given, at, world.speed)


## scheduler/seasons.ts ensureSeasons: the next turn on the calendar.
static func ensure(server: LocalServer, world: Dictionary, now: int) -> void:
	if world.status != "running" or world.get("startedAt") == null:
		return
	if world.events.any(func(e: Dictionary) -> bool: return e.status == "pending" and e.type == "season_turn"):
		return
	apply(server, world, now)
	var at := season_at(server.data, world, now)
	server.schedule(world, int(at.endsAt), "season_turn", {"day": int(at.day) + 1})


static func on_season_turn(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	if world.status != "running":
		return
	var due := int(event.dueAt)
	apply(server, world, due)
	var at := season_at(server.data, world, due)
	var def: Dictionary = server.data.seasons.seasons[at.season]
	LocalInbox.tell_everyone(server, world, {"kind": "season", "tier": "push", "title": "%s has come" % def.name, "body": def.description}, due)
	server.schedule(world, int(at.endsAt), "season_turn", {"day": int(event.payload.day) + 1})
	changed.append(["world"])
