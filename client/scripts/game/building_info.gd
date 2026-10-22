class_name BuildingInfo
extends RefCounted
## The cards behind a building's or a unit's info mark: what it is for, and
## for a building, level by level what it costs, how long it takes and what
## it gives (data/buildings.json, data/units.json).


## What `building` gives at `level`, in a few words ("" for nothing).
## `speed` is the world's; times and amounts are per real hour.
static func gives(data: Dictionary, building: String, level: int, speed: float) -> String:
	var def: Dictionary = data.buildings.buildings[building]
	var parts := PackedStringArray()
	if def.has("production"):
		parts.append(UI.t("%s +%d/h") % [UI.resource_name(String(def.production.resource)), roundi(Rules.field_production(def, level, speed))])
	match String(def.kind):
		"wall":
			parts.append(UI.t("%s, %d to batter down") % [WallText.tier(data, level), WallText.integrity(data, level)])
		"tower":
			parts.append(WallText.tower_at(data, building, level))
		"outpost":
			parts.append(UI.t("yields ×%.2f") % pow(float(def.get("yieldGrowth", 1.0)), level - 1))
	if building == Rules.HALL:
		parts.append(UI.t("%d slots · queue %d · %d outposts") % [Rules.unlocked_slots(data, level), Rules.queue_limit(data, level), Rules.outpost_limit(data, level)])
		var faster := roundi((1.0 - Rules.hall_speedup(data, level)) * 100.0)
		if faster > 0:
			parts.append(UI.t("builds %d%% faster") % faster)
	if def.has("capacityGrowth"):
		var base := float(data.buildings.village.baseCapacity)
		parts.append(UI.t("stores %d of each") % roundi(base * pow(float(def.capacityGrowth), level)))
	if def.has("effects"):
		var scaled := {}
		for key in def.effects:
			scaled[key] = float(def.effects[key]) * level
		parts.append(HeroText.effects(scaled))
	if building == "caravan_yard":
		var count := level * int(data.logistics.caravan.caravansPerYardLevel)
		parts.append(UI.tn("%d caravan", "%d caravans", count) % count)
	if building == "academy":
		var techs: Dictionary = data.research.techs
		var opened := techs.keys().filter(func(tech: String) -> bool: return int(techs[tech].academyLevel) == level).size()
		if opened > 0:
			parts.append(UI.tn("opens %d tech", "opens %d techs", opened) % opened)
	# Where troops are trained: faster each level, and who it opens.
	var trains := trained_at(data, building)
	if not trains.is_empty():
		if level > 1:
			parts.append(UI.t("trains %d%% faster") % roundi((1.0 - pow(float(data.units.trainingSpeedup), level - 1)) * 100.0))
		for unit in trains:
			if int(data.units.units[unit].requiresLevel) == level:
				parts.append(UI.t("opens %s") % UI.t(data.units.units[unit].name))
	return " · ".join(parts)


## The units trained in `building`.
static func trained_at(data: Dictionary, building: String) -> Array:
	var units: Dictionary = data.units.units
	return units.keys().filter(func(unit: String) -> bool: return units[unit].building == building)


## The picture of `building` at its first stage.
static func picture(data: Dictionary, building: String) -> String:
	match String(data.buildings.buildings[building].kind):
		"field":
			return Art.building_id(building, 1, true)
		"wall":
			return "building/wall_wood"
		"outpost":
			return "map/outpost"
	return Art.building_id(building, 1)


## The card for `building`: what it is for, then each level with its cost,
## build time (at `time_factor`, the village's Hall and research) and what
## it gives; `level` (the one it stands at) is marked.
static func card(data: Dictionary, building: String, speed: float, time_factor := 1.0, level := 0) -> Control:
	var def: Dictionary = data.buildings.buildings[building]
	var box := UI.vbox(10)
	box.add_child(_head(picture(data, building), UI.t(def.name), UI.t(String(def.get("description", ""))),
		UI.t("Only %s") % ClanText.title(data, def.clan) if def.get("clan") != null else ""))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	for heading in [UI.t("Lv"), UI.t("Cost · time"), UI.t("Gives")]:
		var title := UI.label(heading, UI.SMALL_SIZE, UI.MUTED)
		title.autowrap_mode = TextServer.AUTOWRAP_OFF
		grid.add_child(title)
	for at in range(1, int(def.maxLevel) + 1):
		var here := at == level
		var number := UI.label(str(at), UI.SMALL_SIZE, UI.GOOD if here else UiTheme.INK)
		number.autowrap_mode = TextServer.AUTOWRAP_OFF
		number.custom_minimum_size.x = 40
		number.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		grid.add_child(number)
		var cost := UI.rich("%s · %s" % [UI.costs(Rules.level_cost(def, at), 22), TimeUtil.format_duration(Rules.build_seconds(def, at, speed, time_factor))], UI.SMALL_SIZE, UiTheme.INK)
		cost.custom_minimum_size.x = 250
		grid.add_child(cost)
		var what := UI.label(gives(data, building, at, speed), UI.SMALL_SIZE, UI.GOOD if here else UI.MUTED)
		what.custom_minimum_size.x = 170
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(what)
	# The levels on a little scroll that unrolls over the card.
	box.add_child(ScrollRoll.new(grid, 300.0))
	return box


## The card for `unit`: what it is for, its strengths, what it costs and
## how long it trains with the training building at `building_level`.
static func unit_card(data: Dictionary, unit: String, speed: float, building_level := 1, villages_owned := 1, time_factor := 1.0) -> Control:
	var def: Dictionary = data.units.units[unit]
	var family := String(def.family)
	var box := UI.vbox(8)
	box.add_child(_head("unit/%s" % unit, UI.t(def.name), UI.t(String(def.get("description", ""))),
		UI.t("Only %s") % ClanText.title(data, def.clan) if def.get("clan") != null else ""))
	box.add_child(UI.label(UI.t("%s · attack %d · defense %d") % [family.capitalize(), int(def.attack), int(def.defense)], UI.SMALL_SIZE))
	box.add_child(UI.label(UI.t("Speed %d hexes/h · carries %d · eats %d grain/h") % [int(def.speed), int(def.carry), int(def.upkeepPerHour)], UI.SMALL_SIZE))
	var counters: Dictionary = data.battle.counters
	for target in counters.get(family, {}):
		box.add_child(UI.label(UI.t("Strong against %s (×%.1f)") % [target, float(counters[family][target])], UI.SMALL_SIZE, UI.ACCENT))
	for attacker in counters:
		if counters[attacker].has(family):
			box.add_child(UI.label(UI.t("Weak against %s") % attacker, UI.SMALL_SIZE, UI.ERROR))
	var seconds := float(def.trainSeconds) * pow(float(data.units.trainingSpeedup), maxi(0, building_level - 1)) * time_factor / speed
	box.add_child(UI.rich(UI.t("%s each · trains in %s") % [UI.costs(Rules.unit_cost(def, 1, villages_owned), 22), TimeUtil.format_duration(seconds)], UI.SMALL_SIZE, UiTheme.INK))
	box.add_child(UI.label(UI.t("Trained at %s level %d") % [UI.t(data.buildings.buildings[def.building].name), int(def.requiresLevel)], UI.SMALL_SIZE, UI.MUTED))
	return box


static func _head(art_id: String, title: String, text: String, note: String) -> Control:
	var head := UI.hbox(12)
	if Art.has(art_id):
		var face := UI.icon(art_id, 72)
		face.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		head.add_child(face)
	var words := UI.vbox(4)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_child(UI.label(title, UI.HEADING_SIZE))
	if text != "":
		words.add_child(UI.label(text, UI.SMALL_SIZE, UI.MUTED))
	if note != "":
		words.add_child(UI.label(note, UI.SMALL_SIZE, UI.ACCENT))
	head.add_child(words)
	return head
