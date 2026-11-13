extends "res://scripts/screens/game_screen_village.gd"
## The in-world screen, the troops' part: a village's garrison and
## training, sending troops and raids, generals, an army's own sheet, and
## the Army sheet of all your forces.

func _armies_section(village: Dictionary) -> void:
	var village_id := int(village.id)
	var defs: Dictionary = Game.data.units.units
	# Armies from this village, and allies' troops standing guard here.
	var here := Game.armies.filter(func(army: Dictionary) -> bool:
		var mine: bool = int(army.homeVillageId) == village_id and army.status != "done"
		var guarding: bool = army.targetVillageId != null and int(army.targetVillageId) == village_id and army.status in ["stationed", "engaged"] and int(army.homeVillageId) != village_id
		return mine or guarding)
	_panel_body.add_child(UI.label(tr("Armies"), UI.HEADING_SIZE))
	_floor_rows(village)
	if here.is_empty():
		_panel_body.add_child(UI.label(tr("No armies out from here, and none standing guard."), UI.SMALL_SIZE, UI.MUTED))
	_paged("armies", here, 6 if _roomy() else 3, func(army: Dictionary) -> void:
		var mine: bool = int(army.homeVillageId) == village_id
		var row := UI.hbox()
		var info := UI.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UI.label(ArmyText.units_text(army.units, defs), UI.SMALL_SIZE))
		var line := UI.label("", UI.SMALL_SIZE, UI.MUTED)
		info.add_child(line)
		var target_name := ArmyText.target_name(army, Game.village_name)
		var from_name := Game.village_name(army.homeVillageId)
		if mine:
			_tick(line, func() -> String: return ArmyText.status(army, target_name, Game.server_now(), _search_ends(army)))
		else:
			line.text = tr("From %s, standing guard here") % from_name
		if army.get("supply") != null and army.status != "done":
			var food := UI.label("", UI.SMALL_SIZE, UI.MUTED)
			info.add_child(food)
			_tick(food, func() -> String:
				var hungry := ArmyText.out_of_food(Game.data, army, float(Game.world.speed), Game.server_now())
				food.add_theme_color_override("font_color", UI.ERROR if hungry else UI.MUTED)
				return ArmyText.supply_text(Game.data, army, float(Game.world.speed), Game.server_now()))
		row.add_child(info)
		var view_id := int(army.id)
		row.add_child(UI.button(tr("View"), func() -> void: _open_army(view_id)))
		_panel_body.add_child(row)
		if mine and army.status == "stationed":
			_army_orders_row(army))

	_panel_body.add_child(UI.with_info(UI.label(tr("Armies nearby answer battles"), UI.SMALL_SIZE, UI.MUTED), tr("The garrison stays home; armies standing within %d hexes of a battle march to it, unless told not to.") % int(Game.data.armies.respond.range)))


## How low the granary may fall for armies quartered here or filling up:
## a number to set, and the default (half the grain storage).
func _floor_rows(village: Dictionary) -> void:
	var village_id := int(village.id)
	var capacity := float(village.get("resources", {}).get("capacity", {}).get("grain", 0))
	var set_floor: Variant = village.get("armyFloor")
	var floor_now := FieldRules.settlement_floor(Game.data, set_floor, capacity)
	var text := tr("Armies may draw the granary down to %d grain") % floori(floor_now)
	_panel_body.add_child(UI.with_info(UI.label(text, UI.SMALL_SIZE),
		tr("Armies standing here eat half their upkeep from the granary, and armies setting off fill up from it, never below this. The garrison eats a quarter of its upkeep from it either way.")))
	var row := UI.hbox(8)
	var picked := [floori(floor_now)]
	row.add_child(_number_input("floor:%d" % village_id, floori(floor_now), 0, maxi(floori(capacity), floori(floor_now)), func(n: int) -> void: picked[0] = n))
	row.add_child(UI.button(tr("Set"), func() -> void:
		_drafts.erase("floor:%d" % village_id)
		_set_floor("/v1/villages/%d/army-floor" % village_id, picked[0])))
	var reset := UI.button(tr("Default"), func() -> void:
		_drafts.erase("floor:%d" % village_id)
		_set_floor("/v1/villages/%d/army-floor" % village_id, null))
	reset.disabled = set_floor == null
	row.add_child(reset)
	_panel_body.add_child(row)


## Troops from this village to a hex picked on the map: an open hex to hold,
## a camp to storm, a site to search, the Holy City to guard, or a
## settlement (yours: stand in it as an army, or join its garrison; another's:
## guard it, or harass the horde against it).
func _send_troops(village: Dictionary) -> void:
	var village_id := int(village.id)
	var home_units := Rules.garrison_at(village, Game.server_now())
	var here := Vector2i(int(village.q), int(village.r))
	_panel_body.add_child(UI.label(tr("Send troops"), UI.HEADING_SIZE))
	var pick := UI.button(tr("Choose where on the map") if _send_target == Vector2i.MAX else tr("Choose somewhere else"), func() -> void:
		_army_sending = village_id
		_set_view("map")
		_rebuild_panel(), "icon/map")
	if _send_target == Vector2i.MAX:
		_panel_body.add_child(pick)
		_panel_body.add_child(UI.label(tr("Tap a hex on the map for them to march to."), UI.SMALL_SIZE, UI.MUTED))
		return
	var cell := _send_target
	var away := HexMath.distance(here, cell)
	var target := Game.village_at(cell)
	var body := {}
	var where := ""
	if cell == here:
		_panel_body.add_child(pick)
		_panel_body.add_child(UI.label(tr("That is this village: choose somewhere else."), UI.SMALL_SIZE, UI.ERROR))
		return
	if cell == HOLY_CITY:
		where = tr("The Holy City")
		body = {"target": {"q": cell.x, "r": cell.y}, "orders": "hold"}
	elif not target.is_empty():
		where = tr("%s (%s)") % [target.name, Game.member_name(int(target.ownerAccountId))] if target.get("ownerAccountId") != null else String(target.name)
		var orders := "support"
		if Game.is_mine(target):
			orders = "garrison" if _army_join else "support"
		elif _army_harass and _horde_against(int(target.id)):
			orders = "harass"
		body = {"targetVillageId": int(target.id), "orders": orders}
	elif not Game.camp_at(cell).is_empty():
		where = tr("the camp at (%d, %d)") % [cell.x, cell.y]
		body = {"target": {"q": cell.x, "r": cell.y}, "orders": "clear"}
	elif not Game.site_at(cell).is_empty() and Game.site_at(cell).status != "explored":
		where = tr("the ancient site at (%d, %d)") % [cell.x, cell.y]
		body = {"target": {"q": cell.x, "r": cell.y}, "orders": "explore"}
	else:
		where = tr("the hex at (%d, %d)") % [cell.x, cell.y]
		body = {"target": {"q": cell.x, "r": cell.y}, "orders": "hold"}
	# Where they go on a line of its own (sharing a row with the button, the
	# wrapping text was squeezed to a letter a line), the button under it.
	var dest_text := UI.label(tr_n("To %s · %d hex", "To %s · %d hexes", away) % [where, away], UI.SMALL_SIZE)
	_panel_body.add_child(UI.with_info(dest_text, ArmyText.order_text(String(body.orders))))
	# Send sits at the top beside the destination, always in sight; the
	# troops and the rest follow under it.
	var fights: bool = body.orders != "garrison"
	var stays: bool = body.orders in ["support", "hold", "clear", "explore"]
	var go := UI.primary(tr("Send"), func() -> void:
		var order := body.duplicate()
		order.units = _picked_units(home_units)
		if stays:
			order.returnHome = _army_return
		if _ready_general(village_id) > 0:
			order.generalId = _ready_general(village_id)
		if fights:
			order.stance = _army_stance
		_send_army(village_id, order), "icon/troops")
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.text = tr("Change")
	var top_row := UI.hbox(8)
	top_row.add_child(pick)
	top_row.add_child(go)
	_panel_body.add_child(top_row)
	_picked_hint(go, home_units)
	if not target.is_empty() and Game.is_mine(target):
		_panel_body.add_child(_join_check())
	elif not target.is_empty() and _horde_against(int(target.id)):
		var harass := CheckBox.new()
		harass.text = tr("Harass the horde against it (strike, then come home)")
		harass.add_theme_font_size_override("font_size", UI.SMALL_SIZE)
		harass.button_pressed = _army_harass
		harass.toggled.connect(func(on: bool) -> void:
			_army_harass = on
			_rebuild_panel())
		_panel_body.add_child(harass)
	_unit_pickers(home_units, true, "send")
	_general_picker(village_id)
	if fights:
		_army_stance_picker(village)
	# Support and holding stay until called home, unless told to come back once done.
	if stays:
		_panel_body.add_child(_return_check(_army_return, ArmyText.return_text(String(body.orders), not Game.shipyard_at(cell).is_empty()), func(on: bool) -> void: _army_return = on))


## Onto one of your settlements: whether the army joins its garrison there
## (by default it stands in it as an army).
func _join_check() -> CheckBox:
	var join := CheckBox.new()
	join.text = tr("Join the garrison (if it is one of your settlements)")
	join.add_theme_font_size_override("font_size", UI.SMALL_SIZE)
	join.button_pressed = _army_join
	join.toggled.connect(func(on: bool) -> void:
		_army_join = on
		if _army_moving == 0:
			_rebuild_panel())
	return join


## Back to a village's Send troops form (after picking where on the map).
func _back_to_send(village_id: int) -> void:
	Game.current_village_id = village_id
	_tab = "troops"
	_side["troops"] = "send"
	_set_view("village")
	_rebuild_panel()


## Steppers for each fighting unit at home, a few to a page (`list` keeps
## the page); returns the troops picked.
func _unit_pickers(home_units: Dictionary, with_scouts := false, list := "units") -> Dictionary:
	var defs: Dictionary = Game.data.units.units
	var families := ["infantry", "archers", "cavalry", "scout"] if with_scouts else ["infantry", "archers", "cavalry"]
	var fighting := home_units.keys().filter(func(unit: String) -> bool:
		var def: Dictionary = defs.get(unit, {})
		# None of them on hand: not offered at all.
		return not def.is_empty() and def.family in families and unit != "settler" and int(home_units[unit]) > 0)
	_paged(list, fighting, 6 if _roomy() else 3, func(unit: String) -> void:
		var def: Dictionary = defs[unit]
		var have := int(home_units[unit])
		var count := clampi(int(_army_units.get(unit, 0)), 0, have)
		var row := UI.hbox(8)
		row.tooltip_text = tr(def.name)
		if Art.has("unit/%s" % unit):
			row.add_child(UI.icon("unit/%s" % unit, 48))
		else:
			row.add_child(UI.label(tr(def.name), UI.SMALL_SIZE))
		var key := "%s:%s" % [list, unit]
		row.add_child(_number_field(key, count, 0, have, func(n: int) -> void: _army_units[unit] = n))
		var of := UI.label(tr("of %d") % have, UI.SMALL_SIZE, UI.MUTED)
		of.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(of)
		var all := UI.button(tr("All"), func() -> void:
			_army_units[unit] = have
			_drafts.erase(key)
			_rebuild_panel())
		all.custom_minimum_size.x = 80
		all.add_theme_font_size_override("font_size", UI.SMALL_SIZE)
		row.add_child(all)
		_panel_body.add_child(row))
	return _picked_units(home_units)


## Under a send button: it waits until some troops are picked.
func _picked_hint(button: Button, home_units: Dictionary) -> void:
	var hint := UI.label("", UI.SMALL_SIZE, UI.MUTED)
	_panel_body.add_child(hint)
	_tick(hint, func() -> String:
		var none := _picked_units(home_units).is_empty()
		button.disabled = none
		return tr("Pick the troops below.") if none else "")


## The troops picked in the fields, as many as are at home.
func _picked_units(home_units: Dictionary) -> Dictionary:
	var chosen := {}
	for unit in _army_units:
		if int(_army_units[unit]) > 0 and home_units.has(unit):
			chosen[unit] = mini(int(_army_units[unit]), int(home_units[unit]))
	return chosen


## A raid beyond the map's edge: the front, how many fields deep before
## the stronghold, what it brings, how long it takes against the grain it
## carries, and who goes.
func _raid_tab(village: Dictionary) -> void:
	var data := Game.data
	var village_id := int(village.id)
	_panel_body.add_child(UI.with_info(UI.label(tr("Raid"), UI.HEADING_SIZE),
		tr("An army marches to the edge of the map on a front's side and goes into the enemy's lands: it fights a battle on each field it crosses, then besieges the front's stronghold, and comes home with what it carries. A battle lost turns it home with what it has. Every battle won makes that front's next horde hate you the more. It eats its own grain all the way: military caravans carry more, and more loot.")))
	var gathering := Game.waves.filter(func(w: Dictionary) -> bool: return w.status == "scheduled" and w.get("bandOf") == null).size()
	_choice_rows([
		{"text": tr("Raid a front"), "selected": not _strike_mode, "pick": func() -> void: _strike_mode = false,
			"info": tr("Into a front's lands: a battle on each field, then its stronghold; loot comes home.")},
		{"text": tr("Strike a gathering horde"), "selected": _strike_mode, "pick": func() -> void: _strike_mode = true,
			"info": tr_n("%d horde gathers beyond the edge: the earlier struck, the fewer of it, but behind walls.", "%d hordes gather beyond the edge: the earlier struck, the fewer of them, but behind walls.", gathering) % gathering},
	])
	if _strike_mode:
		_strike_tab(village)
		return
	var map: Variant = Game.world.get("map")
	var fronts: Array = map.activeFronts if map is Dictionary else []
	if fronts.is_empty():
		return
	if not _raid_front in fronts:
		_raid_front = String(fronts[0])
	_panel_body.add_child(UI.label(tr("Which front"), UI.SMALL_SIZE, UI.MUTED))
	var front_choices: Array = []
	for front in fronts:
		var hatred := roundi(float(Game.world.get("hatred", {}).get(front, 0.0)) * 100.0)
		var stronghold := tr(String(data.raids.fronts.get(front, {}).get("stronghold", "")))
		var loot := tr("hero gear, lore scrolls, Embers") if front == "north" else tr("resources")
		front_choices.append({"text": RaidText.front_name(String(front)).capitalize(), "icon": WaveMath.front_icon(String(front)),
			"selected": _raid_front == front, "pick": func() -> void: _raid_front = String(front),
			"info": tr("%s · stronghold: %s · loot: %s · hatred now +%d%%") % [tr(Game.front_faction(String(front))), stronghold, loot, hatred]})
	_choice_rows(front_choices)
	var max_depth := int(data.raids.maxDepth)
	_raid_depth = clampi(_raid_depth, 1, max_depth)
	_panel_body.add_child(UI.label(tr("How deep"), UI.SMALL_SIZE, UI.MUTED))
	var depth_choices: Array = []
	for depth in range(1, max_depth + 1):
		var hate := roundi((float(data.raids.hatred.perBattle) * (depth + 1) + float(data.raids.hatred.stronghold)) * 100.0)
		depth_choices.append({"text": tr_n("%d field", "%d fields", depth) % depth, "selected": _raid_depth == depth, "pick": func() -> void: _raid_depth = depth,
			"info": tr("%d battles, the last at the stronghold's walls · about %s beyond the edge · up to +%d%% hatred if all are won") % [
				depth + 1, TimeUtil.format_duration(RaidText.stage_hours(data, depth) * 3600.0 / float(Game.world.speed)), hate]})
	_choice_rows(depth_choices)
	_panel_body.add_child(UI.label(RaidText.plan(data, _raid_front, _raid_depth), UI.SMALL_SIZE, UI.ACCENT))
	_panel_body.add_child(UI.label(RaidText.prize(_raid_front), UI.SMALL_SIZE, UI.MUTED))
	var home_units := Rules.garrison_at(village, Game.server_now())
	_unit_pickers(home_units, true, "raid")
	var hero := Game.my_hero()
	var hero_ready: bool = not hero.is_empty() and hero.status == "home" and hero.villageId != null and int(hero.villageId) == village_id
	if hero_ready:
		_panel_body.add_child(UI.button(tr("%s leads it: %s") % [hero.name, tr("yes") if _army_hero else tr("no")], func() -> void:
			_army_hero = not _army_hero
			_rebuild_panel()))
	_general_picker(village_id)
	_army_stance_picker(village)
	# What it can carry, and how long its grain lasts against the time beyond the edge.
	var sums := UI.label("", UI.SMALL_SIZE, UI.MUTED)
	sums.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel_body.add_child(sums)
	var depth_now := _raid_depth
	_tick(sums, func() -> String:
		var picked := _picked_units(home_units)
		if picked.is_empty():
			return ""
		var eats := RaidText.upkeep(data, picked)
		var current: Dictionary = Game.villages.get(int(village.id), village)
		var spare := FieldRules.village_spare(data, current, float(Ledger.amounts_at(current.resources, Game.server_now()).grain))
		var grain := minf(LocalSupply.full_supply(data, picked), spare)
		var lasts := grain / eats if eats > 0.0 else INF
		return tr("Carries up to %d loot · grain for about %s · %s of battles beyond the edge, besides the march there and back") % [
			RaidText.capacity(data, picked), TimeUtil.format_duration(lasts * 3600.0 / float(Game.world.speed)) if lasts < INF else tr("ever"),
			TimeUtil.format_duration(RaidText.stage_hours(data, depth_now) * 3600.0 / float(Game.world.speed))])
	var front_now := _raid_front
	var go := UI.button(tr("Raid %s") % RaidText.front_name(front_now), func() -> void:
		var body := {"front": front_now, "depth": depth_now, "units": _picked_units(home_units), "withHero": _army_hero and hero_ready, "stance": _army_stance}
		if _ready_general(village_id) > 0:
			body.generalId = _ready_general(village_id)
		_send_raid(village_id, body), "map/camp_bandit")
	_panel_body.add_child(go)
	_picked_hint(go, home_units)


## Choices one under another, each a full-width button with a line of what
## it means above it: {text, info, selected, pick, icon?}.
func _choice_rows(choices: Array) -> void:
	var list := UI.vbox(4)
	for choice in choices:
		var info := UI.label(String(choice.info), UI.SMALL_SIZE, UI.ACCENT if choice.selected else UI.MUTED)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(info)
		var pick: Callable = choice.pick
		var b := UI.button(String(choice.text), func() -> void:
			pick.call()
			_rebuild_panel(), String(choice.get("icon", "")))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = choice.selected
		list.add_child(b)
	_panel_body.add_child(list)


## The Raid tab's strike: a horde still gathering beyond the edge, hit
## before it sets out (data/raids.json strike).
func _strike_tab(village: Dictionary) -> void:
	var data := Game.data
	var village_id := int(village.id)
	var info := UI.label(tr("Attack a horde still gathering beyond the map's edge, before it sets out. The earlier you strike, the fewer of it have gathered, but those there fight from behind their encampment's walls. Its dead are gone for good; win or lose, that front's hatred rises sharply, and its next horde to set out takes it all."), UI.SMALL_SIZE, UI.MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel_body.add_child(info)
	var gathering: Array = Game.waves.filter(func(w: Dictionary) -> bool: return w.status == "scheduled" and w.get("bandOf") == null)
	if gathering.is_empty():
		_panel_body.add_child(UI.label(tr("No horde is gathering now."), UI.SMALL_SIZE, UI.MUTED))
		return
	if not gathering.any(func(w: Dictionary) -> bool: return int(w.id) == _strike_wave):
		_strike_wave = int(gathering[0].id)
	var now := Game.server_now()
	var choices: Array = []
	for wave in gathering:
		var left := TimeUtil.parse_iso(wave.spawnAt) - now
		var share := RaidText.strike_share(data, left / 3600.0 * float(Game.world.speed))
		var hatred := roundi(float(Game.world.get("hatred", {}).get(wave.front, 0.0)) * 100.0)
		choices.append({"text": tr("Horde of %s") % RaidText.front_name(String(wave.front)), "icon": WaveMath.front_icon(String(wave.front)),
			"selected": int(wave.id) == _strike_wave, "pick": func() -> void: _strike_wave = int(wave.id),
			"info": tr("%s threat · sets out in %s · about %d%% gathered · hatred now +%d%%") % [tr(String(wave.threat)).capitalize(),
				TimeUtil.format_duration(left), roundi(share * 100.0), hatred]})
	_choice_rows(choices)
	var home_units := Rules.garrison_at(village, now)
	_unit_pickers(home_units, true, "raid")
	var hero := Game.my_hero()
	var hero_ready: bool = not hero.is_empty() and hero.status == "home" and hero.villageId != null and int(hero.villageId) == village_id
	if hero_ready:
		_panel_body.add_child(UI.button(tr("%s leads it: %s") % [hero.name, tr("yes") if _army_hero else tr("no")], func() -> void:
			_army_hero = not _army_hero
			_rebuild_panel()))
	_general_picker(village_id)
	_army_stance_picker(village)
	var wave_now := _strike_wave
	var go := UI.button(tr("Strike the horde"), func() -> void:
		var body := {"waveId": wave_now, "units": _picked_units(home_units), "withHero": _army_hero and hero_ready, "stance": _army_stance}
		if _ready_general(village_id) > 0:
			body.generalId = _ready_general(village_id)
		_send_raid(village_id, body, "strike"), "map/camp_bandit")
	_panel_body.add_child(go)
	_picked_hint(go, home_units)


func _send_raid(village_id: int, body: Dictionary, route := "raids") -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/%s" % [village_id, route], body)
	if not response.ok:
		_status.text = response.error
		return
	_army_units.clear()
	_forget_drafts(["units:", "send:", "escort:", "raid:"])
	_army_hero = false
	_army_general = 0
	_army_stance = ""
	Game.note_server_time(response.data.serverTime)


func _send_army(village_id: int, body: Dictionary) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/armies" % village_id, body)
	if not response.ok:
		_status.text = response.error
		return
	_toast(tr("The army is on its way"))
	_army_units.clear()
	_forget_drafts(["units:", "send:", "escort:"])
	_send_target = Vector2i.MAX
	_army_join = false
	_army_harass = false
	_army_hero = false
	_army_general = 0
	_army_stance = ""
	Game.note_server_time(response.data.serverTime)


## Your generals ready in a village, and a choice of which leads the next
## army (or none).
func _general_picker(village_id: int) -> void:
	var ready := Game.my_generals().filter(func(g: Dictionary) -> bool: return g.status == "home" and g.villageId != null and int(g.villageId) == village_id)
	if ready.is_empty():
		return
	var labels := [tr("No general")]
	var selected := 0
	for i in ready.size():
		labels.append(tr("%s (Lv %d) leads it") % [ready[i].name, int(ready[i].level)])
		if int(ready[i].id) == _army_general:
			selected = i + 1
	var picker := UI.options(labels, selected)
	picker.item_selected.connect(func(i: int) -> void: _army_general = 0 if i == 0 else int(ready[i - 1].id))
	_panel_body.add_child(picker)


## The picked general, if still ready in the village (0: none).
func _ready_general(village_id: int) -> int:
	for g in Game.my_generals():
		if int(g.id) == _army_general and g.status == "home" and g.villageId != null and int(g.villageId) == village_id:
			return _army_general
	return 0


## The Hero's Hall: your generals, where they are, and recruiting another.
func _generals_section(village: Dictionary) -> void:
	var village_id := int(village.id)
	var mine := Game.my_generals()
	var halls := Game.my_villages().map(func(v: Dictionary) -> int: return int(v.get("levels", {}).get("heroes_hall", 0)))
	var keeps := GeneralText.limit(Game.data, halls)
	_panel_body.add_child(UI.label(tr("Generals: %d of %d") % [mine.size(), keeps], UI.SMALL_SIZE + 2))
	_panel_body.add_child(UI.with_info(UI.label(tr("What generals do"), UI.SMALL_SIZE, UI.MUTED), tr("A general leads an army it marches with, or commands the garrison of the village it stands in. A general whose side loses a battle is killed.")))
	var places := Game.my_villages()
	for general in mine:
		var row := UI.hbox()
		var info := UI.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var xp := tr("Lv %d · %d/%d XP") % [int(general.level), int(general.xp), int(general.xpToNext)] if general.get("xpToNext") != null else tr("Lv %d") % int(general.level)
		info.add_child(UI.label(tr("%s · %s · %s") % [general.name, xp, GeneralText.bonuses(general)], UI.SMALL_SIZE))
		info.add_child(_champion_line("general", int(general.level)))
		var where := UI.label("", UI.SMALL_SIZE, UI.MUTED)
		info.add_child(where)
		var place := Game.village_name(general.villageId)
		_tick(where, func() -> String: return GeneralText.whereabouts(general, place, Game.server_now()))
		row.add_child(info)
		_panel_body.add_child(row)
		# What can be done with one not out with an army, on a line of its own.
		var general_id := int(general.id)
		var actions := UI.hbox(8)
		if general.status == "home" and places.size() > 1:
			var others := places.filter(func(v: Dictionary) -> bool: return general.villageId == null or int(v.id) != int(general.villageId))
			var to := UI.options(others.map(func(v: Dictionary) -> String: return tr("Send to %s") % v.name), 0)
			to.item_selected.connect(func(i: int) -> void: _move_general(general_id, int(others[i].id)))
			to.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			to.custom_minimum_size.x = 0
			to.clip_text = true
			actions.add_child(to)
		if general.status != "with_army":
			var dismiss := UI.button(tr("Dismiss"), func() -> void: _dismiss_general(general_id))
			dismiss.custom_minimum_size.x = 130
			actions.add_child(dismiss)
		if actions.get_child_count() > 0:
			_panel_body.add_child(actions)
	var cost := GeneralText.recruit_cost(Game.data, mine.size())
	# The new general's name: yours to give, or one of the old names.
	var name_key := "general-name:%d" % village_id
	var name_field := _draft_field(name_key, tr("Name (optional)"), "")
	_panel_body.add_child(name_field)
	var row := UI.hbox()
	var cost_line := UI.rich()
	cost_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cost_line)
	var recruit := UI.primary(tr("Recruit"), func() -> void:
		var given := name_field.text.strip_edges()
		_forget_drafts([name_key])
		_recruit_general(village_id, given))
	recruit.custom_minimum_size.x = 160
	recruit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(recruit)
	_panel_body.add_child(row)
	var full := mine.size() >= keeps
	var wait := TimeUtil.format_duration(float(Game.data.heroes.generals.recruitHours) * 3600.0 / float(Game.world.speed))
	var text := tr("A general: %s · %s") % [UI.costs(cost), wait]
	_tick(cost_line, func() -> String:
		var home: Dictionary = Game.villages.get(village_id, village)
		var affordable := Ledger.can_afford(Ledger.amounts_at(home.resources, Game.server_now()), cost)
		recruit.disabled = full or not affordable
		return text + (tr("  (raise a Hero's Hall for more)") if full else ""))


func _recruit_general(village_id: int, given := "") -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/generals" % village_id, {"name": given} if given != "" else {})
	if not response.ok:
		_status.text = response.error
		return
	Game.update_village(response.data.village)
	# The live update may have brought it already: in place of that, not beside it.
	var general: Dictionary = response.data.general
	Game.set_generals(Game.world_id(), Game.generals.filter(func(g: Dictionary) -> bool: return int(g.id) != int(general.id)) + [general])


func _move_general(general_id: int, village_id: int) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/generals/%d/move" % general_id, {"villageId": village_id})
	if not response.ok:
		_status.text = response.error
		return
	Game.set_generals(Game.world_id(), Game.generals.map(func(g: Dictionary) -> Dictionary: return response.data.general if int(g.id) == general_id else g))


func _dismiss_general(general_id: int) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/generals/%d/dismiss" % general_id, {})
	if not response.ok:
		_status.text = response.error
		return
	Game.set_generals(Game.world_id(), Game.generals.filter(func(g: Dictionary) -> bool: return int(g.id) != general_id))


func _open_army(army_id: int) -> void:
	_army_id = army_id
	_army_moving = 0
	_panel_mode = "army"
	hex_map.select_army(army_id)
	_rebuild_panel()


## An army: where it is and what it does, each kind of troop with what it
## eats and how long it can carry food, the grain it carries, its fatigue
## (from hunger), the store where it stands, and its orders. Moving it:
## a button, then the hex (or village) tapped on the map.
func _army_panel() -> void:
	var army := _find_army(_army_id)
	var top := UI.hbox()
	if not army.is_empty() and Art.has("unit/" + ArmyText.main_unit(army)):
		top.add_child(UI.icon("unit/" + ArmyText.main_unit(army), 40))
	var title := UI.label(tr("Army from %s") % Game.village_name(army.homeVillageId) if not army.is_empty() else tr("Army"), UI.HEADING_SIZE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_panel_body.add_child(top)
	if army.is_empty() or army.status == "done":
		_panel_body.add_child(UI.label(tr("This army is no more: it came home, was disbanded or was lost."), UI.SMALL_SIZE, UI.MUTED))
		return
	var target := ArmyText.target_name(army, Game.village_name)
	var where := UI.label("", UI.SMALL_SIZE)
	_panel_body.add_child(where)
	# Searching a site: how far along the search is.
	var search_done := _search_ends(army)
	var search_bar: ProgressBar = null
	var search_span := 0.0
	if search_done > 0.0:
		search_span = ArmyText.search_seconds(Game.data, String(Game.site_at(ArmyText.held_hex(army)).get("kind", "")), army.units, float(Game.world.speed))
		search_bar = _gauge(UI.ACCENT)
		_panel_body.add_child(search_bar)
	_tick(where, func() -> String:
		if search_bar != null and is_instance_valid(search_bar):
			search_bar.value = clampf(1.0 - (search_done - Game.server_now()) / search_span, 0.0, 1.0) if search_span > 0.0 else 1.0
		# Beyond the map's edge on a raid, not standing guard.
		if army.get("raid") is Dictionary and army.status == "stationed" and army.orders == "raid":
			return RaidText.progress(army)
		return ArmyText.status(army, target, Game.server_now(), search_done))
	var mine: bool = army.get("ownerAccountId") != null and int(army.ownerAccountId) == Game.my_account_id()
	var tabs := [["orders", "icon/map", tr("Orders"), _army_tab_orders.bind(army)],
		["troops", "unit/" + ArmyText.main_unit(army) if Art.has("unit/" + ArmyText.main_unit(army)) else "icon/troops", tr("Troops & leaders"), _army_tab_troops.bind(army)],
		["supply", "resource/grain", tr("Supply"), _army_tab_supply.bind(army)]]
	if mine:
		tabs.append(["settings", "icon/settings", tr("Settings"), _army_tab_settings.bind(army)])
	_side_tabs("army", tabs, 150.0)


## The army's orders: its raid, its stance, where it goes (tap a hex), call
## it home, disband.
func _army_tab_orders(army: Dictionary) -> void:
	# A raid: where it stands, its battles, what it found and carries.
	if army.get("raid") is Dictionary:
		var raid: Dictionary = army.raid
		if raid.get("waveId") != null:
			_panel_body.add_child(UI.label(tr("Strike on the horde of %s") % RaidText.front_name(String(raid.front)), UI.HEADING_SIZE))
		else:
			_panel_body.add_child(UI.label(tr("Raid on %s") % RaidText.front_name(String(raid.front)), UI.HEADING_SIZE))
			_panel_body.add_child(UI.label(RaidText.plan(Game.data, String(raid.front), int(raid.depth)), UI.SMALL_SIZE, UI.MUTED))
		for line in RaidText.battles(raid):
			_panel_body.add_child(UI.label(line, UI.SMALL_SIZE))
		if not raid.get("finds", []).is_empty():
			_panel_body.add_child(UI.label(tr("Found: %s") % ", ".join(raid.finds), UI.SMALL_SIZE, UI.GOOD))
		var carried := int(LocalLogistics.total(army.loot)) if army.get("loot") is Dictionary else 0
		_panel_body.add_child(UI.label(tr("Carries %d of %d loot") % [carried, RaidText.capacity(Game.data, army.units)], UI.SMALL_SIZE, UI.MUTED))
	# Its stance: yours can be changed while it is out, not in a battle.
	var own: bool = army.get("ownerAccountId") != null and int(army.ownerAccountId) == Game.my_account_id()
	var stance: String = army.get("stance", "balanced")
	if own and army.status in ["stationed", "marching"]:
		_panel_body.add_child(UI.label(tr("Stance"), UI.HEADING_SIZE))
		var stance_army := int(army.id)
		_stance_grid(stance, func(next: String) -> void: _set_army_stance(stance_army, next))
	else:
		_panel_body.add_child(UI.label(_stance_text(stance), UI.SMALL_SIZE, UI.MUTED))
		if own and army.status == "engaged":
			_panel_body.add_child(UI.label(tr("Its stance can't be changed in the middle of a battle."), UI.SMALL_SIZE, UI.MUTED))

	var mine: bool = army.get("ownerAccountId") != null and int(army.ownerAccountId) == Game.my_account_id()
	if not mine or not army.status in ["stationed", "marching", "returning"]:
		return
	var army_id := int(army.id)
	_panel_body.add_child(UI.button(tr("Move: tap a hex"), func() -> void:
		# To the map first (it resets the sheet), then wait for the tap with
		# the army's sheet kept.
		if _view != "map":
			_set_view("map")
		_army_id = army_id
		_panel_mode = "army"
		_army_moving = army_id
		_rebuild_panel(), "icon/map"))
	_army_orders_row(army, false)


## Its troops and who leads them: what each eats and carries, the hero and
## a general, merging and splitting.
func _army_tab_troops(army: Dictionary) -> void:
	var data := Game.data
	var speed := float(Game.world.speed)
	var defs: Dictionary = data.units.units
	var led := PackedStringArray()
	for hero in Game.heroes:
		if army.get("heroAccountId") != null and int(hero.accountId) == int(army.heroAccountId):
			led.append(hero.name)
	for general in Game.generals:
		if army.get("generalId") != null and int(general.id) == int(army.generalId):
			led.append(general.name)
	if not led.is_empty():
		_panel_body.add_child(UI.label(tr("Led by %s") % ", ".join(led), UI.SMALL_SIZE, UI.MUTED))
	# Its scouts: they never fight, but tell it what it faces.
	var intel := _intel_bonus(army.units)
	if intel > 0.0:
		_panel_body.add_child(UI.with_info(UI.label(tr("Scouts: +%d%% attack and defense") % roundi(intel * 100.0), UI.SMALL_SIZE, UI.ACCENT),
			tr("Scouts with an army never fight, but it fights the better for knowing the enemy: +%d%% for each scout (pathfinders count two, assassins three), at most +%d%%.") % [
				roundi(float(Game.data.scouting.intel.perPoint) * 100.0), roundi(float(Game.data.scouting.intel.max) * 100.0)]))
	# The troops: what each eats, and how long each can carry its food.
	_panel_body.add_child(UI.label(tr("Troops"), UI.HEADING_SIZE))
	for unit in army.units:
		if int(army.units[unit]) <= 0:
			continue
		var def: Dictionary = defs.get(unit, {})
		var row := UI.hbox(10)
		if Art.has("unit/%s" % unit):
			row.add_child(UI.icon("unit/%s" % unit, 36))
		var words := UI.vbox(0)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.add_child(UI.label(tr("%s ×%d") % [tr(def.get("name", unit)), int(army.units[unit])], UI.SMALL_SIZE))
		var food := tr("Each eats %s grain an hour · carries food for %s") % [UI.number(TimeUtil.per_real_hour(float(def.get("upkeepPerHour", 0)) * speed)), TimeUtil.format_duration(float(def.get("supplyHours", 0)) * 3600.0 / speed)]
		if float(def.get("supplyGrain", 0)) > 0:
			food += " · " + tr("each wagon %d grain more") % int(def.supplyGrain)
		words.add_child(UI.label(food, UI.SMALL_SIZE, UI.MUTED))
		row.add_child(words)
		_panel_body.add_child(row)

	var mine: bool = army.get("ownerAccountId") != null and int(army.ownerAccountId) == Game.my_account_id()
	if mine and army.status in ["stationed", "marching", "returning"]:
		_army_leaders(army)


## Its grain, fatigue, the store where it stands and its wagon ring.
func _army_tab_supply(army: Dictionary) -> void:
	var data := Game.data
	var speed := float(Game.world.speed)
	# Its grain, and how worn it is for want of it.
	_panel_body.add_child(UI.label(tr("Supply"), UI.HEADING_SIZE))
	var eats := ArmyText.upkeep(data, army.units)
	if army.get("supply") == null:
		_panel_body.add_child(UI.label(tr("Fed by its home village: %s grain an hour.") % UI.number(TimeUtil.per_real_hour(eats * speed)), UI.SMALL_SIZE, UI.MUTED))
	else:
		var full := ArmyText.full_supply(data, army.units)
		var grain_bar := _gauge(HexMap.GRAIN_COLOR)
		_panel_body.add_child(grain_bar)
		var grain := UI.label("", UI.SMALL_SIZE)
		_panel_body.add_child(grain)
		_tick(grain, func() -> String:
			var left := ArmyText.supply_left(data, army, speed, Game.server_now())
			grain_bar.value = left / full if full > 0 else 0.0
			var eats_text := UI.number(TimeUtil.per_real_hour(eats * speed))
			# Grain over the full supply (the fallen's share) is shown apart:
			# it is left behind when the army sets off.
			if floori(left) > floori(full):
				return tr("Grain %d (+%d) of %d · eats %s an hour") % [floori(full), floori(left) - floori(full), floori(full), eats_text] \
					+ "\n" + tr("The extra grain is left behind when they march off.")
			return tr("Grain %d of %d · eats %s an hour") % [floori(left), floori(full), eats_text])
		if army.get("quarteredAt") != null:
			_panel_body.add_child(UI.with_info(UI.label(tr("Quartered: fed from the stores where it stands, %s grain an hour; its own grain keeps.") % UI.number(TimeUtil.per_real_hour(eats * speed * float(data.armies.quarters.upkeep))), UI.SMALL_SIZE, UI.ACCENT),
				tr("An army standing in a settlement, fort or supply point eats half its upkeep from its stores, never below the floor set there. Once the floor is reached it eats its own grain again.")))
		var lasts := UI.label("", UI.SMALL_SIZE, UI.MUTED)
		_panel_body.add_child(lasts)
		_tick(lasts, func() -> String: return ArmyText.supply_text(data, army, speed, Game.server_now()))
	var tired_row := UI.hbox(8)
	tired_row.add_child(UI.label(tr("Fatigue"), UI.SMALL_SIZE))
	var tired_bar := _gauge(UI.ERROR)
	tired_row.add_child(tired_bar)
	_panel_body.add_child(UI.with_info(tired_row, tr("Fatigue comes from hunger alone: out of food an army marches slower, after %s it starts losing men, and after %s it is lost.") % [
		TimeUtil.format_duration(float(data.armies.attrition.lossAfterHours) * 3600.0 / speed), TimeUtil.format_duration(float(data.armies.attrition.lostAfterHours) * 3600.0 / speed)]))
	var tired := UI.label("", UI.SMALL_SIZE, UI.MUTED)
	_panel_body.add_child(tired)
	_tick(tired, func() -> String:
		tired_bar.value = ArmyText.fatigue(data, army, speed, Game.server_now())
		tired.add_theme_color_override("font_color", UI.ERROR if tired_bar.value > 0 else UI.MUTED)
		return ArmyText.fatigue_text(data, army, speed, Game.server_now()))
	# The store where it stands.
	var store := Game.fort_at(ArmyText.held_hex(army)) if army.status in ["stationed", "engaged"] else {}
	if not store.is_empty() and store.status == "standing":
		var place := tr("Supply point") if store.get("kind", "fort") == "supply" else tr("Fort")
		_panel_body.add_child(UI.label(tr("%s here: %d of %d grain") % [place, floori(float(store.get("grain", 0))), int(FieldRules.grain_capacity(data, store.get("kind", "fort")))], UI.SMALL_SIZE))
		_store_floor_rows(store)
	# Its wagons drawn into a ring.
	if army.get("wagonFortAt") != null and army.status in ["stationed", "engaged"]:
		var ring_at := TimeUtil.parse_iso(String(army.wagonFortAt))
		var ring := UI.label("", UI.SMALL_SIZE)
		_panel_body.add_child(ring)
		_tick(ring, func() -> String:
			var bonus := roundi(FieldRules.wagon_fort_bonus(data, army.units) * 100.0)
			var left := ring_at - Game.server_now()
			if left > 0:
				return tr("Wagon fort: ready in %s (+%d%% defense)") % [TimeUtil.format_duration(left), bonus]
			return tr("Wagon fort: +%d%% defense") % bonus)

	var mine: bool = army.get("ownerAccountId") != null and int(army.ownerAccountId) == Game.my_account_id()
	if mine and army.status == "stationed":
		_store_row(army)
		_wagon_row(army)


## Its standing settings: answering battles, its home, coming home once done.
func _army_tab_settings(army: Dictionary) -> void:
	var army_id := int(army.id)
	if army.orders in ["support", "hold", "clear", "explore"]:
		var on: bool = army.get("returnHome", false)
		_panel_body.add_child(_return_check(on, ArmyText.return_text(String(army.orders), not Game.shipyard_at(ArmyText.held_hex(army)).is_empty()), func(next: bool) -> void:
			_army_command(army_id, "return-home", {"returnHome": next})))
	_army_settings(army)


## A fort's or supply point's floor: how low its grain may fall for armies
## (its owner sets it; by default to the last grain).
func _store_floor_rows(store: Dictionary) -> void:
	var floor_value: Variant = store.get("armyFloor")
	_panel_body.add_child(UI.label(tr("Armies may draw it down to %d grain") % int(floor_value if floor_value != null else 0), UI.SMALL_SIZE, UI.MUTED))
	if store.get("ownerAccountId") == null or int(store.ownerAccountId) != Game.my_account_id():
		return
	var fort_id := int(store.id)
	var row := UI.hbox(8)
	var picked := [int(floor_value if floor_value != null else 0)]
	row.add_child(_number_input("fort-floor:%d" % fort_id, picked[0], 0, int(FieldRules.grain_capacity(Game.data, store.get("kind", "fort"))), func(n: int) -> void: picked[0] = n))
	row.add_child(UI.button(tr("Set"), func() -> void:
		_drafts.erase("fort-floor:%d" % fort_id)
		_set_floor("/v1/forts/%d/army-floor" % fort_id, picked[0])))
	_panel_body.add_child(row)


## The rest of what your army can be told: whether it answers battles
## nearby, its home, its hero and general, merging with another army
## standing beside it and splitting off some of its troops.
func _army_settings(army: Dictionary) -> void:
	var army_id := int(army.id)
	var answers := CheckBox.new()
	answers.text = tr("Answer battles within %d hexes") % int(Game.data.armies.respond.range)
	answers.button_pressed = army.get("respond", true)
	answers.add_theme_font_size_override("font_size", UI.SMALL_SIZE)
	answers.toggled.connect(func(on: bool) -> void: _army_command(army_id, "respond", {"respond": on}))
	_panel_body.add_child(UI.with_info(answers, tr("Standing still, it marches to any battle that starts within %d hexes, and comes back here once it is over.") % int(Game.data.armies.respond.range)))
	# Its home: where it goes when called home.
	if army.status != "returning":
		var homes: Array = Game.villages.values().filter(func(v: Dictionary) -> bool: return Game.is_mine(v) and v.get("ruin") == null)
		homes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.id) < int(b.id))
		if homes.size() > 1:
			var labels := []
			var selected := 0
			for i in homes.size():
				labels.append(tr("Home: %s") % homes[i].name)
				if int(homes[i].id) == int(army.homeVillageId):
					selected = i
			var picker := UI.options(labels, selected)
			picker.item_selected.connect(func(i: int) -> void:
				if int(homes[i].id) != int(army.homeVillageId):
					_army_command(army_id, "home", {"villageId": int(homes[i].id)}))
			_panel_body.add_child(picker)


## Its leaders (the hero and a general), and merging and splitting.
func _army_leaders(army: Dictionary) -> void:
	var army_id := int(army.id)
	var standing: bool = army.status == "stationed"
	# Its leaders: the hero and a general join it where it stands (in one
	# of your settlements) and leave it anywhere, not in a battle.
	var leaders := UI.hbox(8)
	var hero := Game.my_hero()
	if army.get("heroAccountId") != null:
		# The hero leading it: its sheet (its quests with the army among them).
		if not hero.is_empty() and int(army.heroAccountId) == int(hero.accountId):
			leaders.add_child(UI.button(tr("Hero"), func() -> void:
				_panel_mode = "hero"
				_side["hero"] = "quests"
				_rebuild_panel(), "ui/hero"))
		leaders.add_child(UI.button(tr("Hero leaves"), func() -> void: _army_command(army_id, "hero", {"join": false})))
	elif standing and not hero.is_empty() and hero.status == "home" and army.targetVillageId != null and hero.villageId != null and int(hero.villageId) == int(army.targetVillageId):
		leaders.add_child(UI.button(tr("%s takes command") % hero.name, func() -> void: _army_command(army_id, "hero", {"join": true})))
	if army.get("generalId") != null:
		leaders.add_child(UI.button(tr("General leaves"), func() -> void: _army_command(army_id, "general", {"generalId": null})))
	if standing and army.targetVillageId != null:
		var ready := Game.my_generals().filter(func(g: Dictionary) -> bool: return g.status == "home" and g.villageId != null and int(g.villageId) == int(army.targetVillageId))
		if not ready.is_empty():
			var labels := [tr("General…")]
			for g in ready:
				labels.append(tr("%s (Lv %d) takes command") % [g.name, int(g.level)])
			var picker := UI.options(labels, 0)
			picker.item_selected.connect(func(i: int) -> void:
				if i > 0:
					_army_command(army_id, "general", {"generalId": int(ready[i - 1].id)}))
			leaders.add_child(picker)
	if leaders.get_child_count() > 0:
		_panel_body.add_child(leaders)
	if not standing:
		return
	# Merging: another of your armies standing on the same hex joins this one.
	var beside := Game.armies.filter(func(a: Dictionary) -> bool:
		return int(a.id) != army_id and a.status == "stationed" and a.ownerAccountId != null and int(a.ownerAccountId) == Game.my_account_id() and ArmyText.held_hex(a) == ArmyText.held_hex(army))
	for other in beside:
		var other_id := int(other.id)
		_panel_body.add_child(UI.button(tr("Merge in: %s") % ArmyText.units_text(other.units, Game.data.units.units), func() -> void: _army_command(army_id, "merge", {"armyId": other_id})))
	# Splitting: the troops picked become an army of their own here.
	if LocalBattle.total(army.units) > 1:
		_panel_body.add_child(UI.label(tr("Split off"), UI.HEADING_SIZE))
		_unit_pickers(army.units, true, "split")
		var split := UI.button(tr("Split them off"), func() -> void:
			_army_command(army_id, "split", {"units": _picked_units(army.units), "withHero": false, "withGeneral": false})
			_army_units.clear())
		_panel_body.add_child(split)
		_picked_hint(split, army.units)


## When an army searching a site is done (0: not searching).
func _search_ends(army: Dictionary) -> float:
	return ArmyText.search_ends(Game.data, army, Game.site_at(ArmyText.held_hex(army)), float(Game.world.speed))


## What an army can be told: come home, march into a village, and, standing
## still, take on grain where it stands or disband.
func _army_orders_row(army: Dictionary, with_supply := true) -> void:
	var army_id := int(army.id)
	var standing: bool = army.status == "stationed"
	var row := UI.hbox(8)
	if army.status != "returning":
		row.add_child(UI.button(tr("Call home"), func() -> void: _recall_army(army_id)))
	if standing and army.targetVillageId != null and army.get("supply") != null:
		row.add_child(UI.button(tr("Take on grain"), func() -> void: _army_command(army_id, "resupply", {})))
	if standing:
		row.add_child(UI.button(tr("Disband"), func() -> void: _army_command(army_id, "disband", {})))
	_panel_body.add_child(row)
	if standing and with_supply:
		_store_row(army)
		_wagon_row(army)


## For your army holding open ground with wagons: draw them into a ring.
func _wagon_row(army: Dictionary) -> void:
	var data := Game.data
	if army.orders != "hold" or army.targetVillageId != null or army.get("wagonFortAt") != null:
		return
	if FieldRules.wagons_in(data, army.units) == 0 or not Game.fort_at(ArmyText.held_hex(army)).is_empty():
		return
	var army_id := int(army.id)
	var rules: Dictionary = data.field.wagonFort
	var circle := UI.button(tr("Circle the wagons (+%d%% defense)") % roundi(FieldRules.wagon_fort_bonus(data, army.units) * 100.0),
		func() -> void: _army_command(army_id, "wagon-fort", {}))
	_panel_body.add_child(UI.with_info(circle, tr("The wagons are drawn into a ring, ready in %s: +%d%% defense for each wagon per %d soldiers, at most +%d%%. The ring breaks up when the army moves.") % [
		TimeUtil.format_duration(float(rules.setupMinutes) * 60.0 / float(Game.world.speed)), roundi(float(rules.bonusPerWagon) * 100.0),
		int(rules.menPerWagon), roundi(float(rules.maxBonus) * 100.0)]))


## For your army standing on a fort or supply point: take on grain from
## its store, or leave half of what it carries there.
func _store_row(army: Dictionary) -> void:
	var store := Game.fort_at(ArmyText.held_hex(army))
	if army.targetVillageId != null or army.get("supply") == null or army.status != "stationed" or store.is_empty() or store.status != "standing":
		return
	if army.ownerAccountId == null or int(army.ownerAccountId) != Game.my_account_id():
		return
	var army_id := int(army.id)
	var row := UI.hbox(8)
	row.add_child(UI.button(tr("Take grain"), func() -> void: _army_command(army_id, "resupply", {})))
	row.add_child(UI.button(tr("Leave half its grain"), func() -> void:
		var half := floori(ArmyText.supply_left(Game.data, army, float(Game.world.speed), Game.server_now()) / 2.0)
		_army_command(army_id, "store", {"grain": maxi(1, half)})))
	_panel_body.add_child(row)


func _army_command(army_id: int, action: String, body: Dictionary) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/armies/%d/%s" % [army_id, action], body)
	if not response.ok:
		_status.text = response.error


func _recall_army(army_id: int) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/armies/%d/recall" % army_id, {})
	if not response.ok:
		_status.text = response.error


## How low a settlement's, fort's or supply point's grain may fall for
## armies (null: the default).
func _set_floor(path: String, grain: Variant) -> void:
	_status.text = ""
	var response := await Api.request(HTTPClient.METHOD_PUT, path, {"grain": grain})
	if not response.ok:
		_status.text = response.error
		return
	Game.note_server_time(response.data.serverTime)
	if path.begins_with("/v1/forts/"):
		_refetch_world()


func _troops_section(village: Dictionary) -> void:
	var hall := Rules.hall_level(village)
	_side_tabs("troops", [["garrison", Art.settlement_id(hall), tr("Garrison"), _garrison_tab.bind(village)],
		["train", "unit/spearman", tr("Train"), _train_tab.bind(village)],
		["armies", "icon/troops", tr("Armies"), _armies_section.bind(village)],
		["send", "unit/border_rider", tr("Send troops"), _send_troops.bind(village)],
		["raid", "map/camp_bandit", tr("Raid"), _raid_tab.bind(village)]], VILLAGE_TOP)


## Who guards the village and how they fight: the stance, the hero, the
## troops at home and away, settlers on the road.
func _garrison_tab(village: Dictionary) -> void:
	var village_id := int(village.id)
	for battle in Game.battles:
		if battle.get("status") == "ongoing" and battle.get("villageId") != null and int(battle.villageId) == village_id:
			_panel_body.add_child(_battle_button(battle))
			_sally_row(battle)
	_stance_picker(village)
	_hero_line(village_id)
	var commander := Game.general_at(village_id)
	if not commander.is_empty():
		_panel_body.add_child(UI.label(tr("%s (Lv %d) commands this garrison: %s") % [commander.name, int(commander.level), GeneralText.bonuses(commander)], UI.SMALL_SIZE, UI.MUTED))
	var recommended := Rules.recommended_garrison(Game.data, Game.villages_owned(int(village.ownerAccountId)))
	var guard := UI.label("", UI.SMALL_SIZE, UI.MUTED)
	_panel_body.add_child(guard)
	_tick(guard, func() -> String:
		var home_now := BattleText.total(Rules.garrison_at(Game.villages.get(village_id, village), Game.server_now()))
		return tr("Recommended garrison: %d (%d at home)") % [recommended, home_now])
	_expeditions_list(village_id)
	_panel_body.add_child(UI.label(tr("At home"), UI.SMALL_SIZE, UI.MUTED))
	_panel_body.add_child(_live_unit_chips(func() -> Dictionary:
		return Rules.garrison_at(Game.villages.get(village_id, village), Game.server_now())))

	var away: Dictionary = village.get("away", {}).duplicate()
	for unit in away.keys():
		if int(away[unit]) <= 0:
			away.erase(unit)
	if not away.is_empty():
		_panel_body.add_child(UI.label(tr("Away"), UI.SMALL_SIZE, UI.MUTED))
		_panel_body.add_child(_unit_chips(away))
	_ruin_search_section(village)
	_dismiss_section(village)


## Scouts sent to search the land around the village for a forgotten ruin,
## and what the last ones found.
func _ruin_search_section(village: Dictionary) -> void:
	var village_id := int(village.id)
	var searches: Array = Game.world.get("ruinSearches", []).filter(func(s: Dictionary) -> bool: return int(s.villageId) == village_id)
	if int(village.levels.get("scout_lodge", 0)) < 1 and searches.is_empty():
		return
	var rules: Dictionary = Game.data.scouting.ruinSearch
	var duration := TimeUtil.format_duration(float(rules.hours) * 3600.0 / float(Game.world.speed))
	_panel_body.add_child(UI.with_info(UI.label(tr("Search for ruins"), UI.SMALL_SIZE, UI.MUTED),
		tr("Scouts search the land up to %d hexes around the village for %s. Each scout gives a %d%% chance of finding a forgotten ruin (at most %d%%), which then waits to be explored.") % [
			int(rules.range), duration, roundi(float(rules.chancePerScout) * 100.0), roundi(float(rules.maxChance) * 100.0)]))
	for search in searches:
		var line := UI.label("", UI.SMALL_SIZE, UI.MUTED)
		_panel_body.add_child(line)
		if search.status == "out":
			_tick(line, func() -> String:
				return tr("%d scouts searching · back in %s") % [int(search.scouts), TimeUtil.format_duration(TimeUtil.parse_iso(search.returnsAt) - Game.server_now())])
			continue
		var site: Dictionary = {}
		for s in Game.world.get("sites", []):
			if search.siteId != null and int(s.id) == int(search.siteId):
				site = s
		if site.is_empty():
			line.text = tr("%d scouts came back empty-handed") % int(search.scouts)
		else:
			line.text = tr("%d scouts found a %s at (%d, %d)") % [int(search.scouts), tr(Game.data.sites.kinds.get(site.kind, {}).get("name", site.kind)), int(site.q), int(site.r)]
	if int(village.levels.get("scout_lodge", 0)) < 1:
		return
	var at_home := int(Rules.garrison_at(village, Game.server_now()).get("scout", 0))
	var least := int(rules.minScouts)
	var most := maxi(least, mini(int(Game.data.scouting.maxScouts), at_home))
	var count := clampi(_ruin_scouts.get(village_id, mini(maxi(at_home, least), 5)), least, most)
	var row := UI.hbox()
	_panel_body.add_child(row)
	row.add_child(_number_field("ruins:%d" % village_id, count, least, most, func(n: int) -> void: _ruin_scouts[village_id] = n))
	var send := UI.button(tr_n("Send to search (%d home)", "Send to search (%d home)", at_home) % at_home, func() -> void:
		_search_ruins(village_id, clampi(int(_ruin_scouts.get(village_id, count)), least, most)))
	send.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	send.disabled = at_home < least
	row.add_child(send)


func _search_ruins(village_id: int, count: int) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/scout/ruins" % village_id, {"count": count})
	if not response.ok:
		_status.text = response.error
		return
	Game.note_server_time(response.data.serverTime)
	Game.update_village(response.data.village)


## Soldiers sent home to their farms: they stop eating, and are gone.
func _dismiss_section(village: Dictionary) -> void:
	var village_id := int(village.id)
	var home_units := Rules.garrison_at(village, Game.server_now())
	if BattleText.total(home_units) == 0:
		return
	_panel_body.add_child(UI.label(tr("Dismiss soldiers"), UI.SMALL_SIZE, UI.MUTED))
	_unit_pickers(home_units, true, "dismiss")
	var go := UI.button(tr("Dismiss"), func() -> void: _dismiss_units(village_id, _picked_units(home_units)))
	_panel_body.add_child(go)


func _dismiss_units(village_id: int, units: Dictionary) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/dismiss" % village_id, {"units": units})
	if not response.ok:
		_status.text = response.error
		return
	_army_units.clear()
	Game.update_village(response.data.village)


## Who is in training, and what the village can train, a few to a page.
func _train_tab(village: Dictionary) -> void:
	var village_id := int(village.id)
	var units: Dictionary = Game.data.units.units
	var training: Array = village.training
	var limit := Rules.training_queue_limit(Game.data, village.levels)
	_panel_body.add_child(UI.with_info(UI.label(tr("Training (%d/%d)") % [training.size(), limit], UI.SMALL_SIZE, UI.MUTED),
		tr("Batches waiting to be trained. Every %d levels of the Barracks, the Shooting Range and the Stables each add one more place.") % int(Game.data.units.buildingLevelsPerTrainingSlot)))
	if training.is_empty():
		_panel_body.add_child(UI.label(tr("Nobody in training."), UI.SMALL_SIZE, UI.MUTED))
	for batch in training:
		var line := UI.label("", UI.SMALL_SIZE)
		_panel_body.add_child(line)
		var unit_name: String = tr(units.get(batch.unit, {"name": batch.unit}).name)
		var done_at := TimeUtil.parse_iso(batch.completesAt)
		var start := TimeUtil.parse_iso(batch.startsAt)
		var per_unit := float(batch.perUnitMs) / 1000.0
		_tick(line, func() -> String:
			var now := Game.server_now()
			var done := Rules.finished_by(batch, now)
			if done >= int(batch.count):
				return tr("%s %d/%d   finishing…") % [unit_name, done, batch.count]
			var next_at := start + (done + 1) * per_unit
			return tr("%s %d/%d   next %s · all %s") % [unit_name, done, batch.count,
				TimeUtil.format_duration(next_at - now), TimeUtil.format_duration(done_at - now)])

	_rally_row(village)

	var queue_full := training.size() >= limit
	var max_batch := int(Game.data.units.maxBatch)
	var allowed := units.keys().filter(func(unit: String) -> bool: return ClanText.allowed(units[unit], village.get("bonuses", {})))
	# One training building's troops at a time, picked from those built.
	var buildings := []
	for unit in allowed:
		var building: String = units[unit].building
		if not buildings.has(building) and int(village.levels.get(building, 0)) > 0:
			buildings.append(building)
	if buildings.is_empty():
		_panel_body.add_child(UI.label(tr("Build a Barracks, Shooting Range or Stables in the village to train troops."), UI.SMALL_SIZE, UI.MUTED))
		return
	if not buildings.has(_train_building):
		_train_building = buildings[0]
	var labels: Array = buildings.map(func(building: String) -> String:
		return tr("%s (Lv %d)") % [tr(_building_def(building).name), int(village.levels.get(building, 0))])
	var picker := UI.options(labels, buildings.find(_train_building))
	picker.item_selected.connect(func(i: int) -> void:
		_train_building = buildings[i]
		_rebuild_panel())
	_panel_body.add_child(picker)
	allowed = allowed.filter(func(unit: String) -> bool: return units[unit].building == _train_building)
	# What the village can train first, then what it could with more building.
	var ready := func(unit: String) -> bool: return int(village.levels.get(units[unit].building, 0)) >= int(units[unit].requiresLevel)
	var trainable := allowed.filter(ready) + allowed.filter(func(unit: String) -> bool: return not ready.call(unit))
	_paged("train " + _train_building, trainable, 3 if _roomy() else 2, func(unit: String) -> void:
		var def: Dictionary = units[unit]
		var building_level := int(village.levels.get(def.building, 0))
		var unlocked := building_level >= int(def.requiresLevel)
		var frame := UI.card(10)
		var card := UI.hbox(12)
		frame.add_child(card)
		if Art.has("unit/%s" % unit):
			var picture := UI.icon("unit/%s" % unit, 64)
			picture.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			card.add_child(picture)
		var info := UI.vbox(4)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_child(info)
		info.add_child(UI.with_card(UI.label(tr(def.name)), _unit_card(village, unit)))
		var stats := UI.stats([["icon/attack", str(int(def.attack))], ["icon/defense", str(int(def.defense))], ["icon/health", str(int(def.health))],
			["icon/speed", UI.number(TimeUtil.per_real_hour(float(def.speed) * float(Game.world.speed)))],
			["resource/grain", tr("%s/h") % UI.number(TimeUtil.per_real_hour(float(def.upkeepPerHour) * float(Game.world.speed)))]])
		stats.tooltip_text = tr("Attack · Defense · Health · Speed (hexes/h) · Grain eaten")
		info.add_child(stats)
		_panel_body.add_child(frame)
		if not unlocked:
			info.add_child(UI.label(tr("Needs %s level %d") % [tr(_building_def(def.building).name), def.requiresLevel], UI.SMALL_SIZE, UI.ERROR))
			return
		var cost_line := UI.rich()
		info.add_child(cost_line)

		# How many: typed in; the cost and the button follow as it is typed.
		var row := UI.hbox()
		info.add_child(row)
		# Some (settlers) train one at a time, and dearer every few bought: a
		# single Recruit button, like a general's.
		var one: bool = def.get("oneAtATime", false)
		if one:
			_train_counts[unit] = 1
		else:
			row.add_child(_number_field("train:%s" % unit, int(_train_counts.get(unit, 1)), 1, max_batch, func(n: int) -> void:
				_train_counts[unit] = n))
			# As many as the stores pay for (up to a batch).
			var most := UI.button(tr("Max"), func() -> void:
				var home: Dictionary = Game.villages.get(village_id, village)
				var have := Ledger.amounts_at(home.resources, Game.server_now())
				var owned_now := Game.villages_owned(int(village.ownerAccountId))
				var n := max_batch
				while n > 1 and not Ledger.can_afford(have, Rules.unit_cost(def, n, owned_now, Game.bought(int(village.ownerAccountId), unit))):
					n -= 1
				_train_counts[unit] = n
				_drafts.erase("train:%s" % unit)
				_rebuild_panel())
			most.focus_mode = Control.FOCUS_NONE
			row.add_child(most)
		if def.get("costStep") != null:
			info.add_child(UI.with_info(UI.label(tr("One at a time; dearer for every %d you have recruited (%d).") % [int(def.costStep.every), Game.bought(int(village.ownerAccountId), unit)], UI.SMALL_SIZE, UI.MUTED),
				tr("Counted over all your villages. Each one that dies brings the price back down; founding a village with them does not.")))
		var train := UI.primary(tr("Recruit") if one else tr("Train"), func() -> void: _train(village_id, unit, int(_train_counts.get(unit, 1))))
		train.custom_minimum_size.x = 120
		if one:
			train.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(train)
		var seconds := float(def.trainSeconds) * LocalVillage.training_speed_factor(Game.data, String(def.building), building_level) \
			* ResearchRules.time_factor(village.get("bonuses", {}), "trainTime") / float(Game.world.speed)
		var owned := Game.villages_owned(int(village.ownerAccountId))
		_tick(cost_line, func() -> String:
			var cost := Rules.unit_cost(def, int(_train_counts.get(unit, 1)), owned, Game.bought(int(village.ownerAccountId), unit))
			var current: Dictionary = Game.villages.get(village_id, village)
			var have := Ledger.amounts_at(current.resources, Game.server_now())
			train.disabled = queue_full or not Ledger.can_afford(have, cost)
			var text := tr("%s · %s each") % [UI.costs(cost, 30, have), TimeUtil.format_duration(seconds)]
			return text + tr("  (queue full)") if queue_full else text))


func _stance_picker(village: Dictionary) -> void:
	var village_id := int(village.id)
	_panel_body.add_child(UI.with_info(UI.label(tr("Stance when attacked"), UI.SMALL_SIZE, UI.MUTED),
		tr("How the garrison fights, and the stance new armies take. Risk against reward: the earlier a stance breaks, the harder it hits or holds.")))
	_stance_grid(village.get("stance", "balanced"), func(stance: String) -> void: _set_stance(village_id, stance))


## A button for each stance (the current one pressed), and what it does.
func _stance_grid(current: String, pick: Callable, enabled := true) -> void:
	var stances: Dictionary = Game.data.battle.stances
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_panel_body.add_child(grid)
	for stance in stances:
		var button := UI.button(tr(stances[stance].name), func() -> void: pick.call(stance))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = stance == current or not enabled
		grid.add_child(button)
	_panel_body.add_child(UI.label(_stance_text(current), UI.SMALL_SIZE, UI.MUTED))


## A stance's numbers: what it gives, and when it breaks.
func _stance_text(stance: String) -> String:
	var def: Dictionary = Game.data.battle.stances[stance]
	var breaks := tr("never breaks") if def.retreatAt == null else tr("breaks at %d%% losses") % roundi(float(def.retreatAt) * 100.0)
	return tr("%s: attack ×%.2f, defense ×%.2f, %s.") % [tr(def.name), def.attack, def.defense, breaks]


## The stance a new army fights in (its village's to begin with).
func _army_stance_picker(village: Dictionary) -> void:
	var stances: Array = Game.data.battle.stances.keys()
	if not _army_stance in stances:
		_army_stance = village.get("stance", "balanced")
	var row := UI.hbox(8)
	row.add_child(UI.label(tr("Stance"), UI.SMALL_SIZE))
	var picker := UI.options(stances.map(func(s: String) -> String: return tr(Game.data.battle.stances[s].name)), stances.find(_army_stance))
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.item_selected.connect(func(i: int) -> void:
		_army_stance = stances[i]
		_rebuild_panel())
	row.add_child(picker)
	row.add_child(UI.info(tr("Each army fights in its own stance and breaks on its own losses: one that breaks falls back home beaten (its hero wounded, its general killed) while the others fight on.")))
	_panel_body.add_child(row)
	_panel_body.add_child(UI.label(_stance_text(_army_stance), UI.SMALL_SIZE, UI.MUTED))


func _set_army_stance(army_id: int, stance: String) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/armies/%d/stance" % army_id, {"stance": stance})
	if not response.ok:
		_status.text = response.error
		return
	Game.note_server_time(response.data.serverTime)


## While a horde is before your village's standing walls: the order to
## leave them and charge it (tap twice; there is no going back in).
func _sally_row(battle: Dictionary) -> void:
	if battle.is_empty() or battle.get("status") != "ongoing" or battle.get("villageId") == null:
		return
	var setup: Dictionary = battle.get("setup", {}) if battle.get("setup") is Dictionary else {}
	if not setup.has("wall") or int(setup.wall.integrity) <= 0:
		return
	var village_id := int(battle.villageId)
	var village: Dictionary = Game.villages.get(village_id, {})
	if village.is_empty() or not Game.commands(village):
		return
	if setup.get("sally", false):
		_panel_body.add_child(UI.label(tr("Our men are outside the walls, fighting in the open."), UI.SMALL_SIZE, UI.ACCENT))
		return
	var armed := _sally_armed == int(battle.id)
	var row := UI.hbox(8)
	var button := UI.button(tr("Sure? Charge out") if armed else tr("Charge out of the walls"), func() -> void:
		if _sally_armed != int(battle.id):
			_sally_armed = int(battle.id)
			_rebuild_panel()
			return
		_sally_armed = 0
		_sally(village_id), "icon/troops")
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(button)
	row.add_child(UI.info(tr("The garrison and the armies with it leave the walls and fight in the open from the next round: no wall defense, no shooting from the walls, and the horde's fighters are no longer held back. A horde still building its engines is fought at once. No going back in this battle.")))
	_panel_body.add_child(row)


func _sally(village_id: int) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/sally" % village_id, {})
	if not response.ok:
		_status.text = response.error
		Sound.effect("error")
		return
	Sound.effect("horn")
	Game.update_village(response.data.village)
	# The solo engine sends no live news: fetch the battle as it now stands.
	_refetch_world()


func _set_stance(village_id: int, stance: String) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/stance" % village_id, {"stance": stance})
	if not response.ok:
		_status.text = response.error
		return
	Game.update_village(response.data.village)


func _train(village_id: int, unit: String, count: int) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/train" % village_id, {"unit": unit, "count": count})
	if not response.ok:
		_status.text = response.error
		Sound.effect("error")
		return
	Sound.effect("train")
	_toast(tr("Training %d × %s") % [count, tr(Game.data.units.units.get(unit, {"name": unit}).name)])
	Game.note_server_time(response.data.serverTime)
	Game.update_village(response.data.village)


## A hero's or general's own battle stats: it fights in the ranks.
func _champion_line(id: String, level: int) -> Control:
	var c := LocalBattle.champion_of(Game.data, id, level)
	var line := UI.stats([["icon/attack", str(roundi(float(c.attack)))], ["icon/defense", str(roundi(float(c.defense)))], ["icon/health", str(roundi(float(c.health)))]], UI.SMALL_SIZE, UiTheme.GOLD)
	line.tooltip_text = tr("In battle: attack · defense · health")
	var why := tr("The hero fights in the ranks as a champion, striking like a band of soldiers. It commands the troops it stands with; struck down, it is carried home wounded and a general with it takes command.") if id == "hero" \
		else tr("A general fights in the ranks too, a lesser champion than the hero. It commands the troops it stands with when no hero does, and takes command when the hero falls; struck down, it dies.")
	return UI.with_info(line, why)


## The rally point, seen from one of the player's villages: where its new
## troops march, and a button to make this village the rally point (or stop).
func _rally_row(village: Dictionary) -> void:
	if not Game.is_mine(village):
		return
	var village_id := int(village.id)
	var rally := Game.rally_village()
	var row := UI.hbox(8)
	var text := tr("No rally point")
	if rally == village_id:
		text = tr("Rally point: troops trained in your other settlements march here once done.")
	elif rally != 0:
		text = tr("Rally point: %s. Troops trained here march there once done.") % Game.villages.get(rally, {}).get("name", "?")
	var label := UI.label(text, UI.SMALL_SIZE, UI.ACCENT if rally != 0 else UI.MUTED)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	if rally == village_id:
		row.add_child(UI.button(tr("Stop rallying"), func() -> void: _set_rally(null)))
	else:
		row.add_child(UI.button(tr("Rally here"), func() -> void: _set_rally(village_id)))
	row.add_child(UI.info(tr("One of your settlements can be your rally point: every batch of troops trained in your other settlements marches there as soon as it is done, to join its garrison. Settlers stay home, and so do troops of a village under siege.")))
	_panel_body.add_child(row)


func _set_rally(village_id: Variant) -> void:
	_status.text = ""
	var response := await Api.request(HTTPClient.METHOD_PUT, "/v1/worlds/%d/rally" % Game.world_id(), {"villageId": village_id})
	if not response.ok:
		_status.text = response.error
		return
	Game.set_world(response.data)
	_rebuild_panel()


## All your troops: how many of each there are, each village's garrison,
## the armies out (from where, to where, and when) and the hero.
func _forces_panel() -> void:
	var top := UI.hbox()
	var title := UI.label(tr("Army"), UI.HEADING_SIZE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_panel_body.add_child(top)
	var hero := Game.my_hero()
	var tabs := [["totals", "unit/spearman", tr("All troops"), _forces_totals],
		["villages", "icon/village", tr("By village"), _forces_villages],
		["moving", "icon/troops", tr("Armies"), _forces_armies]]
	if not hero.is_empty():
		var face := "hero/%s" % hero.get("kind") if hero.get("kind") != null and Art.has("hero/%s" % hero.get("kind")) else "icon/profile"
		tabs.append(["hero", face, tr("Your hero"), _forces_hero])
	_side_tabs("forces", tabs)


## How many of each unit you have: at home, out in armies, in training.
func _forces_totals() -> void:
	var now := Game.server_now()
	var home := {}
	var training := {}
	for village in Game.my_villages():
		for unit in Rules.garrison_at(village, now):
			home[unit] = int(home.get(unit, 0)) + int(Rules.garrison_at(village, now)[unit])
		for batch in village.training:
			training[batch.unit] = int(training.get(batch.unit, 0)) + int(batch.count) - Rules.finished_by(batch, now)
	var out := {}
	for army in _my_armies():
		for unit in army.units:
			out[unit] = int(out.get(unit, 0)) + int(army.units[unit])
	var kinds := {}
	for table in [home, out, training]:
		for unit in table:
			if int(table[unit]) > 0:
				kinds[unit] = true
	if kinds.is_empty():
		_panel_body.add_child(UI.label(tr("No troops yet. Train them in a village's Troops tab."), UI.SMALL_SIZE, UI.MUTED))
		return
	var defs: Dictionary = Game.data.units.units
	var grand := 0
	_paged("forces totals", kinds.keys(), 8 if _roomy() else 4, func(unit: String) -> void:
		var row := UI.hbox(10)
		if Art.has("unit/%s" % unit):
			row.add_child(UI.icon("unit/%s" % unit, 44))
		var words := UI.vbox(0)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var all := int(home.get(unit, 0)) + int(out.get(unit, 0)) + int(training.get(unit, 0))
		words.add_child(UI.label(tr("%s ×%d") % [tr(defs.get(unit, {"name": unit}).name), all]))
		words.add_child(UI.label(tr("%d at home · %d out · %d in training") % [int(home.get(unit, 0)), int(out.get(unit, 0)), int(training.get(unit, 0))], UI.SMALL_SIZE, UI.MUTED))
		row.add_child(words)
		_panel_body.add_child(row))
	for unit in kinds:
		grand += int(home.get(unit, 0)) + int(out.get(unit, 0)) + int(training.get(unit, 0))
	_panel_body.add_child(UI.label(tr("%d in all") % grand, UI.SMALL_SIZE, UI.MUTED))


## Each of your villages: who is at home, who is away, who is training.
func _forces_villages() -> void:
	var now := Game.server_now()
	_paged("forces villages", Game.my_villages(), 4 if _roomy() else 2, func(village: Dictionary) -> void:
		var row := UI.hbox(10)
		row.add_child(UI.icon(Art.settlement_id(Rules.hall_level(village)), 48))
		var words := UI.vbox(2)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.add_child(UI.label(village.name))
		words.add_child(_unit_chips(Rules.garrison_at(village, now), 34.0))
		var away: Dictionary = village.get("away", {}).duplicate()
		for unit in away.keys():
			if int(away[unit]) <= 0:
				away.erase(unit)
		if not away.is_empty():
			words.add_child(UI.label(tr("Away"), UI.SMALL_SIZE, UI.MUTED))
			words.add_child(_unit_chips(away, 34.0))
		if not village.training.is_empty():
			var training := {}
			for batch in village.training:
				training[batch.unit] = int(training.get(batch.unit, 0)) + int(batch.count) - Rules.finished_by(batch, now)
			words.add_child(UI.label(tr("Training"), UI.SMALL_SIZE, UI.MUTED))
			words.add_child(_unit_chips(training, 34.0))
		row.add_child(words)
		var village_id := int(village.id)
		var go := UI.button(tr("Open"), func() -> void:
			Game.current_village_id = village_id
			_tab = "troops"
			_side["troops"] = "garrison"
			_set_view("village"))
		go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(go)
		var card := UI.card(10)
		card.add_child(row)
		_panel_body.add_child(card))


## Your armies: who, from where to where, and when they arrive and are home.
func _forces_armies() -> void:
	var armies := _my_armies()
	if armies.is_empty():
		_panel_body.add_child(UI.with_info(UI.label(tr("No armies out"), UI.SMALL_SIZE, UI.MUTED), tr("No armies out. Send them from a village's Troops tab, or from a hex on the map.")))
		return
	_paged("forces armies", armies, 4 if _roomy() else 2, func(army: Dictionary) -> void:
		var row := UI.hbox(10)
		var words := UI.vbox(2)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.add_child(_unit_chips(army.units, 34.0))
		var target := ArmyText.target_name(army, Game.village_name)
		words.add_child(UI.label(tr("%s → %s") % [Game.village_name(army.homeVillageId), target], UI.SMALL_SIZE, UI.MUTED))
		var line := UI.label("", UI.SMALL_SIZE)
		words.add_child(line)
		_tick(line, func() -> String: return ArmyText.timeline(army, target, Game.server_now()))
		row.add_child(words)
		var show := UI.button(tr("Show"), func() -> void:
			var p := ArmyText.progress(army, Game.server_now())
			var cell: Vector2i = ArmyText.held_hex(army)
			if not p.is_empty():
				cell = p.to
			elif cell == Vector2i.MAX and army.get("target") is Array:
				cell = Vector2i(int(army.target[0]), int(army.target[1]))
			_set_view("map")
			camera.position = hex_map.hex_to_local(cell)
			_select(cell))
		show.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(show)
		var view_id := int(army.id)
		var view := UI.button(tr("View"), func() -> void: _open_army(view_id))
		view.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(view)
		var card := UI.card(10)
		card.add_child(row)
		_panel_body.add_child(card))


## Where your hero is.
func _forces_hero() -> void:
	var hero := Game.my_hero()
	var line := UI.label("", UI.SMALL_SIZE)
	_panel_body.add_child(UI.label(tr("%s  Lv %d") % [hero.name, int(hero.level)], UI.HEADING_SIZE))
	_panel_body.add_child(line)
	_tick(line, func() -> String: return HeroText.whereabouts(hero, -1, Game.village_name(hero.villageId), Game.server_now()))
	_panel_body.add_child(UI.button(tr("Open the hero"), func() -> void:
		_panel_mode = "hero"
		_rebuild_panel(), "icon/profile"))
