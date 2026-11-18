class_name AlmanacText
extends RefCounted
## The in-game almanac, written from the game data (data/*.json).

const SECTIONS := ["Units", "Enemies", "Buildings", "Stances", "Hordes", "Clans", "Terrain", "The run"]  # tr


## What kind of troop a unit is (units.json, enemies.json `family`).
const FAMILIES := ["Infantry", "Archers", "Cavalry", "Scout"]  # tr

## The picture on each section's tab.
const ART := {"Units": "unit/spearman", "Enemies": "unit/grey_wolf", "Buildings": "icon/build", "Stances": "icon/troops", "Hordes": "icon/threat",
	"Clans": "clan/volk", "Terrain": "icon/map", "The run": "settlement/holy_city"}
## Pictures for the kinds of ground that have one.
const TERRAIN_ART := {"plains": "feature/grass", "forest": "feature/pine", "hills": "feature/hill", "wooded_hills": "feature/hill", "mountain": "feature/mountain",
	"swamp": "feature/reeds", "holy_city": "settlement/holy_city", "dark_forest": "feature/dark_pine", "ice": "feature/ice",
	"steppe": "feature/bush", "hallowed": "feature/blossom", "mountain_city": "map/mountain_city"}


## [[title, text, art id or "", unit, building or clan id], …] for a
## section of the almanac (the id for those three only).
## `speed` is the world's: rates and times are told in real time.
static func entries(data: Dictionary, section: String, speed := 1.0) -> Array:
	match section:
		"Units":
			return _units(data, speed)
		"Enemies":
			return _enemies(data, speed)
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
		var text := UI.t("%s · attack %s · defense %s · health %d · speed %s hexes/h · carries %d · eats %s grain/h · food for %s on the march · trained at %s") % [
			UI.t(String(u.family).capitalize()), BattleText.stat_range(data, float(u.attack)), BattleText.stat_range(data, float(u.defense)), int(u.health), UI.number(TimeUtil.per_real_hour(float(u.speed) * speed)), int(u.carry), UI.number(TimeUtil.per_real_hour(float(u.upkeepPerHour) * speed)),
			TimeUtil.format_duration(float(u.get("supplyHours", 0)) * 3600.0 / speed), where]
		if u.get("counters") != null:
			var strong := PackedStringArray()
			for target in u.counters:
				strong.append("%s ×%.1f" % [target, float(u.counters[target])])
			text += UI.t(" · strong against %s") % ", ".join(strong)
		text += afflictions_text(u)
		if u.get("clan") != null:
			text += UI.t(" · only %s") % UI.t(data.clans.clans[u.clan].name)
		out.append([UI.t(u.name), text, "unit/%s" % id, id])
	return out


## What a unit's blows carry (battle.json afflictions), or "".
static func afflictions_text(u: Dictionary) -> String:
	var text := ""
	for a in u.get("inflicts", []):
		text += UI.t(" · its blows set the foe burning") if a == "burn" else UI.t(" · its blows poison")
	return text


## Every enemy unit, front by front and tier by tier, with its numbers.
static func _enemies(data: Dictionary, speed := 1.0) -> Array:
	var out := []
	var fronts: Dictionary = data.enemies.fronts
	for front in fronts:
		var f: Dictionary = fronts[front]
		# The Avatar of Černobog stays a surprise (enemies.json hidden).
		var ids: Array = f.units.keys().filter(func(id: String) -> bool: return not f.units[id].get("hidden", false))
		# By tier (engines, which have none, last), as the data lists them.
		ids.sort_custom(func(a: String, b: String) -> bool:
			var ta := int(f.units[a].tier) if f.units[a].get("tier") != null else 99
			var tb := int(f.units[b].tier) if f.units[b].get("tier") != null else 99
			return ta < tb or (ta == tb and f.units.keys().find(a) < f.units.keys().find(b)))
		for id in ids:
			var u: Dictionary = f.units[id]
			var rank := UI.t("tier %d (from wave %d)") % [int(u.tier), int(data.enemies.tiers.minWave[int(u.tier) - 1]) + 1] if u.get("tier") != null else UI.t("siege engine")
			var text := UI.t("%s · %s · %s · attack %s · defense %s · health %d · speed %s hexes/h") % [
				UI.t(f.faction), rank, UI.t(String(u.family).capitalize()), BattleText.stat_range(data, float(u.attack)), BattleText.stat_range(data, float(u.defense)),
				int(u.health), UI.number(TimeUtil.per_real_hour(float(u.get("speed", 0)) * speed))]
			if u.get("counters") != null:
				var strong := PackedStringArray()
				for target in u.counters:
					strong.append("%s ×%.1f" % [UI.t(String(target).capitalize()), float(u.counters[target])])
				text += UI.t(" · strong against %s") % ", ".join(strong)
			text += afflictions_text(u)
			out.append([UI.t(u.name), text, "unit/%s" % id])
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
	var rules: Dictionary = data.battle.get("afflictions", {})
	if rules.is_empty():
		return out
	out.append([UI.t("Burning"), UI.t("A burning unit's blow hurts its targets again: %d%% of it in each of the next %d rounds.") % [roundi(float(rules.burn.share) * 100.0), int(rules.burn.rounds)], ""])
	out.append([UI.t("Poison"), UI.t("A side struck by a poisoner fights at %d%% of its attack and defense for the next %d rounds.") % [roundi(float(rules.poison.factor) * 100.0), int(rules.poison.rounds)], ""])
	return out


static func _hordes(data: Dictionary) -> Array:
	var out := []
	var fronts: Dictionary = data.enemies.fronts
	for front in fronts:
		var f: Dictionary = fronts[front]
		# Its troops by tier, as they join the hordes; then its engines.
		var lines := PackedStringArray()
		for tier in range(1, 5):
			var names := PackedStringArray()
			for unit in f.units:
				if int(f.units[unit].get("tier", 0) if f.units[unit].get("tier") != null else 0) == tier:
					names.append(UI.t(f.units[unit].name))
			if not names.is_empty():
				lines.append(UI.t("Tier %d (from wave %d): %s") % [tier, int(data.enemies.tiers.minWave[tier - 1]) + 1, ", ".join(names)])
		var engines := PackedStringArray()
		for unit in f.units:
			if f.units[unit].get("tier") == null and not f.units[unit].get("hidden", false):
				engines.append(UI.t(f.units[unit].name))
		if not engines.is_empty():
			lines.append(UI.t("Engines: %s") % ", ".join(engines))
		out.append([UI.t("%s (%s front)") % [UI.t(f.faction), String(front).capitalize()], UI.t("%s Units: %s.") % [UI.t(f.signature), "; ".join(lines)], WaveMath.front_icon(String(front))])
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
