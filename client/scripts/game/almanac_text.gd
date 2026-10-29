class_name AlmanacText
extends RefCounted
## The in-game almanac, written from the game data (data/*.json).

const SECTIONS := ["Units", "Buildings", "Stances", "Hordes", "Clans", "Terrain", "The run"]  # tr


## The picture on each section's tab.
const ART := {"Units": "unit/spearman", "Buildings": "icon/build", "Stances": "icon/troops", "Hordes": "icon/threat",
	"Clans": "clan/volk", "Terrain": "icon/map", "The run": "settlement/holy_city"}
## Pictures for the kinds of ground that have one.
const TERRAIN_ART := {"plains": "feature/grass", "forest": "feature/pine", "hills": "feature/hill", "mountain": "feature/mountain",
	"swamp": "feature/reeds", "holy_city": "settlement/holy_city", "dark_forest": "feature/dark_pine", "ice": "feature/ice",
	"steppe": "feature/bush", "hallowed": "feature/blossom"}


## [[title, text, art id or "", unit, building or clan id], …] for a
## section of the almanac (the id for those three only).
## `speed` is the world's: rates and times are told in real time.
static func entries(data: Dictionary, section: String, speed := 1.0) -> Array:
	match section:
		"Units":
			return _units(data, speed)
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


static func _units(data: Dictionary, speed := 1.0) -> Array:
	var out := []
	var units: Dictionary = data.units.units
	for id in units:
		var u: Dictionary = units[id]
		var where := UI.t("%s level %d") % [UI.t(data.buildings.buildings[u.building].name), int(u.requiresLevel)]
		var text := UI.t("%s · attack %d · defense %d · speed %s hexes/h · carries %d · eats %s grain/h · food for %s on the march · trained at %s") % [
			String(u.family).capitalize(), int(u.attack), int(u.defense), UI.number(float(u.speed) * speed), int(u.carry), UI.number(float(u.upkeepPerHour) * speed),
			TimeUtil.format_duration(float(u.get("supplyHours", 0)) * 3600.0 / speed), where]
		if u.get("counters") != null:
			var strong := PackedStringArray()
			for target in u.counters:
				strong.append("%s ×%.1f" % [target, float(u.counters[target])])
			text += UI.t(" · strong against %s") % ", ".join(strong)
		if u.get("clan") != null:
			text += UI.t(" · only %s") % UI.t(data.clans.clans[u.clan].name)
		out.append([UI.t(u.name), text, "unit/%s" % id, id])
	return out


static func _buildings(data: Dictionary) -> Array:
	var out := []
	var buildings: Dictionary = data.buildings.buildings
	for id in buildings:
		var b: Dictionary = buildings[id]
		var kind: String = {"field": UI.t("Field around the village"), "center": UI.t("Building in the village"), "outpost": UI.t("Outpost on a nearby hex")}.get(b.kind, b.kind)
		var text := UI.t("%s · up to level %d") % [kind, int(b.maxLevel)]
		if b.has("production"):
			text += UI.t(" · makes %s") % UI.resource_name(String(b.production.resource))
		if b.has("effects"):
			var parts := PackedStringArray()
			for key in b.effects:
				parts.append(UI.t("%s %+d%%") % [key, roundi(float(b.effects[key]) * 100.0)])
			text += UI.t(" · per level: ") + ", ".join(parts)
		if b.get("clan") != null:
			text += UI.t(" · only %s") % UI.t(data.clans.clans[b.clan].name)
		out.append([UI.t(b.name), text, BuildingInfo.picture(data, id), id])
	return out


static func _stances(data: Dictionary) -> Array:
	var out := []
	var stances: Dictionary = data.battle.stances
	for id in stances:
		var s: Dictionary = stances[id]
		var retreat := UI.t("never breaks") if s.retreatAt == null else UI.t("breaks at %d%% losses") % roundi(float(s.retreatAt) * 100.0)
		out.append([UI.t(s.name), UI.t("attack ×%.2f · defense ×%.2f · %s") % [float(s.attack), float(s.defense), retreat], ""])
	var counters := PackedStringArray()
	for family in data.battle.counters:
		for target in data.battle.counters[family]:
			counters.append(UI.t("%s beat %s (×%.1f)") % [String(family).capitalize(), target, float(data.battle.counters[family][target])])
	out.append([UI.t("Counters"), ", ".join(counters), ""])
	return out


static func _hordes(data: Dictionary) -> Array:
	var out := []
	var fronts: Dictionary = data.enemies.fronts
	for front in fronts:
		var f: Dictionary = fronts[front]
		var names := PackedStringArray()
		for unit in f.units:
			names.append(UI.t(f.units[unit].name))
		out.append([UI.t("%s (%s front)") % [UI.t(f.faction), String(front).capitalize()], UI.t("%s Units: %s.") % [UI.t(f.signature), ", ".join(names)], WaveMath.front_icon(String(front))])
	return out


static func _clans(data: Dictionary) -> Array:
	var out := []
	for clan in data.clans.clans:
		var c: Dictionary = data.clans.clans[clan]
		out.append([UI.t("%s (%s)") % [UI.t(c.name), UI.t(c.animal)], UI.t("%s %s") % [UI.t(c.story), ClanText.perks(data, clan)], "clan/%s" % clan, clan])
	return out


static func _terrain(data: Dictionary) -> Array:
	var out := []
	var terrain: Dictionary = data.terrain.terrain
	for id in terrain:
		var t: Dictionary = terrain[id]
		var move := UI.t("impassable") if t.moveCost == null else UI.t("move cost %s") % str(t.moveCost)
		out.append([UI.t(t.name), UI.t("%s · %s") % [move, UI.t("villages can be founded here") if t.settleable else UI.t("no villages")], TERRAIN_ART.get(id, "")])
	return out


static func _run(data: Dictionary) -> Array:
	return [
		[UI.t("The Kalinov Bridge"), UI.t(data.bridge.story)],
		[UI.t("Ritual Night"), UI.t(data.bridge.ritualNight.story)],
		[UI.t("Winning"), UI.t("%s: the Holy City still stands when Ritual Night's last horde is done.") % UI.t(data.bridge.endings.won.title)],
		[UI.t("Losing"), UI.t("%s: its Sanctity reaches 0.") % UI.t(data.bridge.endings.lost.title)],
	]
