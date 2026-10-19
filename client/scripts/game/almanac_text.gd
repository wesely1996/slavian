class_name AlmanacText
extends RefCounted
## The in-game almanac, written from the game data (data/*.json).

const SECTIONS := ["Units", "Buildings", "Stances", "Hordes", "Clans", "Terrain", "The run"]


## [[title, text], …] for a section of the almanac.
static func entries(data: Dictionary, section: String) -> Array:
	match section:
		"Units":
			return _units(data)
		"Buildings":
			return _buildings(data)
		"Stances":
			return _stances(data)
		"Hordes":
			return _hordes(data)
		"Clans":
			return _clans(data)
		"Terrain":
			return _terrain(data)
		"The run":
			return _run(data)
	return []


static func _units(data: Dictionary) -> Array:
	var out := []
	var units: Dictionary = data.units.units
	for id in units:
		var u: Dictionary = units[id]
		var where := "%s level %d" % [data.buildings.buildings[u.building].name, int(u.requiresLevel)]
		var text := "%s · attack %d · defense %d · speed %d hexes/h · carries %d · eats %d grain/h · trained at %s" % [
			String(u.family).capitalize(), int(u.attack), int(u.defense), int(u.speed), int(u.carry), int(u.upkeepPerHour), where]
		if u.get("clan") != null:
			text += " · only %s" % data.clans.clans[u.clan].name
		out.append([u.name, text])
	return out


static func _buildings(data: Dictionary) -> Array:
	var out := []
	var buildings: Dictionary = data.buildings.buildings
	for id in buildings:
		var b: Dictionary = buildings[id]
		var kind: String = {"field": "Field around the village", "center": "Building in the village", "outpost": "Outpost on a nearby hex"}.get(b.kind, b.kind)
		var text := "%s · up to level %d" % [kind, int(b.maxLevel)]
		if b.has("production"):
			text += " · makes %s" % String(b.production.resource)
		if b.has("effects"):
			var parts := PackedStringArray()
			for key in b.effects:
				parts.append("%s %+d%%" % [key, roundi(float(b.effects[key]) * 100.0)])
			text += " · per level: " + ", ".join(parts)
		if b.get("clan") != null:
			text += " · only %s" % data.clans.clans[b.clan].name
		out.append([b.name, text])
	return out


static func _stances(data: Dictionary) -> Array:
	var out := []
	var stances: Dictionary = data.battle.stances
	for id in stances:
		var s: Dictionary = stances[id]
		var retreat := "never breaks" if s.retreatAt == null else "breaks at %d%% losses" % roundi(float(s.retreatAt) * 100.0)
		out.append([s.name, "attack ×%.2f · defense ×%.2f · %s" % [float(s.attack), float(s.defense), retreat]])
	var counters := PackedStringArray()
	for family in data.battle.counters:
		for target in data.battle.counters[family]:
			counters.append("%s beat %s (×%.1f)" % [String(family).capitalize(), target, float(data.battle.counters[family][target])])
	out.append(["Counters", ", ".join(counters)])
	return out


static func _hordes(data: Dictionary) -> Array:
	var out := []
	var fronts: Dictionary = data.enemies.fronts
	for front in fronts:
		var f: Dictionary = fronts[front]
		var names := PackedStringArray()
		for unit in f.units:
			names.append(f.units[unit].name)
		out.append(["%s (%s front)" % [f.faction, String(front).capitalize()], "%s Units: %s." % [f.signature, ", ".join(names)]])
	return out


static func _clans(data: Dictionary) -> Array:
	var out := []
	for clan in data.clans.clans:
		var c: Dictionary = data.clans.clans[clan]
		out.append(["%s (%s)" % [c.name, c.animal], "%s %s" % [c.story, ClanText.perks(data, clan)]])
	return out


static func _terrain(data: Dictionary) -> Array:
	var out := []
	var terrain: Dictionary = data.terrain.terrain
	for id in terrain:
		var t: Dictionary = terrain[id]
		var move := "impassable" if t.moveCost == null else "move cost %s" % str(t.moveCost)
		out.append([t.name, "%s · %s" % [move, "villages can be founded here" if t.settleable else "no villages"]])
	return out


static func _run(data: Dictionary) -> Array:
	return [
		["The Kalinov Bridge", data.bridge.story],
		["Ritual Night", data.bridge.ritualNight.story],
		["Winning", data.bridge.endings.won.title + ": the Holy City still stands when Ritual Night's last horde is done."],
		["Losing", data.bridge.endings.lost.title + ": its Sanctity reaches 0."],
	]
