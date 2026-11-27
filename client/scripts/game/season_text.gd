class_name SeasonText
## The season (data/seasons.json; server sim/seasons.ts): one game day
## each, in turn from the run's start.

const ORDER := ["spring", "summer", "autumn", "winter"]


## {season, endsAt (unix seconds)} for `world` at `now` (unix seconds);
## {} before the run starts.
static func at(data: Dictionary, world: Dictionary, now: float) -> Dictionary:
	if world.get("startedAt") == null or not data.has("seasons"):
		return {}
	var start := TimeUtil.parse_iso(String(world.startedAt))
	var length := float(data.seasons.dayHours) * 3600.0 / maxf(0.001, float(world.get("speed", 1)))
	var day := maxi(0, floori((now - start) / length))
	var order: Array = data.seasons.order
	return {"season": String(order[day % order.size()]), "endsAt": start + (day + 1) * length}


static func name_of(data: Dictionary, season: String) -> String:
	return UI.t(String(data.seasons.seasons[season].name))


static func description(data: Dictionary, season: String) -> String:
	return UI.t(String(data.seasons.seasons[season].description))


## "Summer · 3h 12m": the season and how long it lasts yet.
static func line(data: Dictionary, world: Dictionary, now: float) -> String:
	var s := at(data, world, now)
	if s.is_empty():
		return ""
	return "%s · %s" % [name_of(data, s.season), TimeUtil.format_duration(maxf(0.0, float(s.endsAt) - now))]
