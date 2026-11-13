extends "res://scripts/screens/game_screen_base.gd"
## The in-world screen, the map's part: what a tapped hex shows (terrain,
## outposts, forts, roads and rivers, the Holy City's bridge and vault), and
## what a tap on the map does.

## The sheet while a hex is picked: what to tap, and Cancel.
func _picking_panel() -> void:
	var row := UI.hbox()
	var army := _army_moving != 0 or _army_sending != 0
	var text := UI.label(tr("Tap the hex for the army to march to.") if army else
		tr("Tap where the caravan goes: a village or outpost, the Holy City, a shipyard, or a fort or supply point."), UI.SMALL_SIZE)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var cancel := UI.button(tr("Cancel"), func() -> void:
		var sending := _army_sending
		_army_moving = 0
		_army_sending = 0
		_caravan_picking = 0
		if sending != 0:
			_back_to_send(sending)
		_status.text = ""
		_rebuild_panel())
	cancel.custom_minimum_size.x = 140
	row.add_child(cancel)
	_panel_body.add_child(row)
	# Moving an army onto one of your settlements: does it join the garrison?
	# (On a line of its own, so the prompt keeps its width.)
	if _army_moving != 0:
		_panel_body.add_child(_join_check())


## "You command this for Mila until …" on a village handed to you.
func _handed_line(village: Dictionary) -> void:
	if Game.is_mine(village):
		return
	var d := DelegationText.of_owner(Game.delegations, int(village.ownerAccountId), Game.server_now())
	if d.is_empty():
		return
	_panel_body.add_child(UI.label(tr("You command it for %s for %s more; they see what you do.") % [Game.member_name(int(d.ownerAccountId)), TimeUtil.format_duration(TimeUtil.parse_iso(d.until) - Game.server_now())], UI.SMALL_SIZE, UI.ACCENT))


## The selected hex: a few lines on what it is, then a side tab for each
## thing to do there (or just the one, without tabs).
func _hex_panel() -> void:
	var cell := _selected
	var parts := []
	var here := WaveMath.visible_waves(Game.waves).filter(func(wave: Dictionary) -> bool:
		return WaveMath.current_hex(wave, Game.server_now(), Game.battles) == cell)
	if not here.is_empty():
		parts.append(["horde", "icon/threat", tr("Hordes here"), func() -> void:
			for wave in here:
				_wave_entry(wave)])
	var village := Game.village_at(cell)
	if village.is_empty():
		parts.append_array(_terrain_panel())
	else:
		var look := Art.settlement_id(Rules.hall_level(village))
		if Game.commands(village):
			parts.append(["village", look, village.name, _own_village_panel.bind(village)])
		else:
			parts.append(["village", look, village.name, _ally_village_panel.bind(village)])
	parts.append(["river", "feature/reeds", tr("Rivers"), _river_section.bind(cell)])
	parts.append(["road", "icon/map", tr("Roads"), _road_section.bind(cell)])
	parts = parts.filter(func(part: Array) -> bool: return _has_content(part[3]))
	if parts.size() == 1:
		parts[0][3].call()
	elif parts.size() > 1:
		_side_tabs("hex", parts, 120.0 if village.is_empty() else 0.0)


## A daily event's lines: what it brings, and how long it waits (it goes
## then, unless an army is already on its way).
func _event_lines(event: Dictionary, brings: String, unless := false) -> void:
	if brings != "":
		_panel_body.add_child(UI.label(brings, UI.SMALL_SIZE, UI.GOOD))
	if event.get("endsAt") == null:
		return
	var ends_at := TimeUtil.parse_iso(String(event.endsAt))
	var line := UI.label("", UI.SMALL_SIZE, UI.MUTED)
	_panel_body.add_child(line)
	_tick(line, func() -> String:
		var left := ends_at - Game.server_now()
		if left <= 0:
			return tr("Going…")
		return (tr("Gone in %s, unless someone sends resources") if unless else tr("Gone in %s, unless an army is on its way")) % TimeUtil.format_duration(left))


## What the selected empty hex is (laid out at the top of its sheet), and
## the parts of its sheet: [[key, art id, name, fill], …] for _hex_panel.
func _terrain_panel() -> Array:
	var id: String = Game.terrain.get(_selected, "")
	_panel_body.add_child(UI.label(tr("%s (%d, %d)") % [Terrain.display_name(id, Game.data), _selected.x, _selected.y], UI.HEADING_SIZE))
	var distance := HexMath.distance(_selected, Vector2i.ZERO)
	if distance > 0:
		_panel_body.add_child(UI.label(tr_n("%d hex from the Holy City.", "%d hexes from the Holy City.", distance) % distance, UI.SMALL_SIZE, UI.MUTED))
	var camp := Game.camp_at(_selected)
	if not camp.is_empty():
		_quest_place_line(camp.get("quest"))
		_panel_body.add_child(UI.label(HordeText.camp(camp, Game.front_faction(camp.front)), UI.SMALL_SIZE, UI.ERROR))
		_event_lines(camp, HordeText.captives(Game.data, camp.get("reward"), camp.get("quest")))
	var quest_site := Game.site_at(_selected)
	if not quest_site.is_empty() and quest_site.status == "unexplored":
		_quest_place_line(quest_site.get("quest"))
	if Game.fear.has(_selected):
		_panel_body.add_child(UI.label(tr("Hordes fear this place: they were beaten here (%.0f).") % Game.fear[_selected], UI.SMALL_SIZE, UI.MUTED))
	if id == "holy_city":
		_panel_body.add_child(UI.label(HordeText.sanctity(Game.world, Game.data), UI.SMALL_SIZE, UI.MUTED))
		return [["bridge", "ui/hero", tr("Kalinov Bridge"), _bridge_panel], ["vault", "icon/coin", tr("Vault"), _vault_panel]]
	var parts := []
	var yard := Game.shipyard_at(_selected)
	if not yard.is_empty():
		parts.append(["shipyard", "icon/coin", tr("Shipyard"), _shipyard_panel.bind(yard)])
	var holder := Game.outpost_owner(_selected)
	var site := Game.site_at(_selected)
	if not holder.is_empty():
		parts.append(["outpost", "map/outpost", tr("Outpost"), _outpost_panel.bind(holder, Rules.outpost_plot(_selected))])
	elif camp.is_empty() and site.is_empty():
		parts.append(["claim", "map/outpost", tr("Build an outpost"), _claim_panel.bind(id)])
		parts.append(["found", "unit/settler", tr("Found a village"), _found_panel.bind(id)])
	var hold_art := "icon/troops"
	if not camp.is_empty():
		hold_art = "map/camp_lair"
	elif not site.is_empty() and Art.has("site/%s" % site.kind):
		hold_art = "site/%s" % site.kind
	parts.append(["hold", hold_art, tr("Send an army"), _hold_panel.bind(id)])
	parts.append(["fort", "map/fort", tr("Build a fort"), _fort_panel.bind(id)])
	parts.append(["supply", "map/supply_point", tr("Build a supply point"), _fort_panel.bind(id, "supply")])
	return parts


## A shipyard (a daily event): what the boat still needs and who can send
## it; while it is built, when it is done and when raiders come; once done,
## the river it sails.
func _shipyard_panel(yard: Dictionary) -> void:
	var rules: Dictionary = Game.data.events.kinds.shipyard
	var speed := int(rules.laneSpeed)
	_panel_body.add_child(UI.with_info(UI.label(tr("Shipyard"), UI.HEADING_SIZE),
		tr("A group project: once the boat is built, armies, caravans and scouts move %d× as fast between hexes along this river.") % speed))
	if yard.status == "done":
		_panel_body.add_child(UI.label(tr("The boat sails this river: marches along it go %d× as fast.") % speed, UI.SMALL_SIZE, UI.GOOD))
		return
	var speed_f := float(Game.world.speed)
	if yard.status == "building":
		var done_at := TimeUtil.parse_iso(String(yard.completesAt))
		var line := UI.label("", UI.SMALL_SIZE)
		_panel_body.add_child(line)
		var built := _gauge(UI.ACCENT)
		_panel_body.add_child(built)
		_tick(line, func() -> String:
			var now := Game.server_now()
			if is_instance_valid(built):
				built.value = EventText.build_share(Game.data, yard, now, speed_f)
			return tr("The boat is %d%% built · ready in %s") % [roundi(EventText.build_share(Game.data, yard, now, speed_f) * 100.0), TimeUtil.format_duration(done_at - now)])
		if yard.get("nextRaidAt") != null:
			# The raiders coming: drawn in black on the map, closing in on the yard.
			var raid_at := TimeUtil.parse_iso(String(yard.nextRaidAt))
			var raiders := int(yard.raiders)
			var warn := UI.label("", UI.SMALL_SIZE, UI.ERROR)
			_panel_body.add_child(warn)
			var closing := _gauge(Color(0.08, 0.08, 0.08))
			_panel_body.add_child(closing)
			_tick(warn, func() -> String:
				var now := Game.server_now()
				if is_instance_valid(closing):
					closing.value = maxf(0.0, EventText.raid_share(Game.data, yard, now, speed_f))
				return tr("%d raiders strike here in %s") % [raiders, TimeUtil.format_duration(raid_at - now)])
		_panel_body.add_child(UI.with_info(UI.label(tr("Raiders burn work unless an army stands here"), UI.SMALL_SIZE, UI.MUTED), tr("Armies standing here fight the raiders; if none drives them off, %d hours of work are lost.") % int(rules.setbackHours)))
		return
	var parts := PackedStringArray()
	var any_paid := false
	for kind in ["wood", "stone", "grain", "iron"]:
		if int(yard.cost[kind]) > 0:
			parts.append(tr("%s %d/%d") % [UI.resource_name(kind), int(yard.paid[kind]), int(yard.cost[kind])])
		any_paid = any_paid or int(yard.paid[kind]) > 0
	_panel_body.add_child(UI.label(tr("Paid: %s") % " · ".join(parts), UI.SMALL_SIZE))
	var paid_bar := _gauge(UI.GOOD)
	paid_bar.value = EventText.paid_share(yard)
	_panel_body.add_child(paid_bar)
	_panel_body.add_child(UI.with_info(UI.label(tr("Build time and raids"), UI.SMALL_SIZE, UI.MUTED), tr("When it is paid for, the boat takes %d hours to build, and raiders come every %d hours.") % [int(rules.buildHours), int(rules.raidEveryHours)]))
	if not any_paid:
		_event_lines(yard, "", true)
	# A caravan from any village with a Caravan Yard; a village close by can
	# also send what it needs at once.
	var cell := Vector2i(int(yard.q), int(yard.r))
	var yard_id := int(yard.id)
	var coming := Game.caravans.filter(func(c: Dictionary) -> bool:
		return c.get("destinationShipyardId") != null and int(c.destinationShipyardId) == yard_id and c.status == "outbound").size()
	if coming > 0:
		_panel_body.add_child(UI.label(tr_n("%d caravan is on its way here.", "%d caravans are on their way here.", coming) % coming, UI.SMALL_SIZE, UI.GOOD))
	var any := false
	for village in Game.my_villages():
		if village.get("ruin") != null:
			continue
		var village_id := int(village.id)
		if int(village.get("levels", {}).get("caravan_yard", 0)) >= 1:
			_panel_body.add_child(UI.button(tr("Send a caravan from %s") % village.name, func() -> void: _open_caravans({"kind": "shipyard", "id": yard_id}, village_id), "icon/caravan"))
			any = true
		if HexMath.distance(Vector2i(int(village.q), int(village.r)), cell) <= int(rules.range):
			_panel_body.add_child(UI.button(tr("Send what it needs from %s at once") % village.name, func() -> void: _pay_shipyard(village_id, yard_id)))
			any = true
	if not any:
		_panel_body.add_child(UI.with_info(UI.label(tr("Needs a Caravan Yard"), UI.SMALL_SIZE, UI.MUTED), tr("Build a Caravan Yard to send it resources by caravan (villages within %d hexes can send at once).") % int(rules.range)))


func _pay_shipyard(village_id: int, yard_id: int) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/shipyards/%d" % [village_id, yard_id], {})
	if not response.ok:
		_status.text = response.error
		return
	Game.set_world(response.data)


## An outpost on the selected hex: what it gathers; yours can be upgraded,
## rebuilt from ruins or abandoned.
func _outpost_panel(holder: Dictionary, plot: String) -> void:
	var holds: Dictionary = holder.plots[plot]
	var level := int(holds.level)
	var mine := Game.is_mine(holder)
	var who := tr("Yours") if mine else Game.member_name(int(holder.ownerAccountId))
	var planned := Rules.planned_plot(holder, plot)
	var state := tr("Lv %d") % level
	if level == 0:
		state = tr("being built") if int(planned.level) > 0 else tr("in ruins")
	_panel_body.add_child(UI.with_card(UI.label(tr("Outpost  %s") % state, UI.HEADING_SIZE), _building_card(holder, Rules.OUTPOST, level)))
	_panel_body.add_child(UI.label(tr("%s · supplies %s") % [who, holder.name], UI.SMALL_SIZE, UI.MUTED))
	var speed := float(Game.world.speed)
	var terrain: String = holds.get("terrain", "")
	var gathering := _yield_text(Rules.outpost_yield(Game.data, terrain, level, speed))
	var line := tr("Gathers %s") % gathering if level > 0 else tr("Gathers nothing until built")
	if holder.get("besieged", false) and level > 0:
		line += tr(" (not while %s is under siege)") % holder.name
	_panel_body.add_child(UI.label(line, UI.SMALL_SIZE, UI.MUTED))
	# A road link to the village: more gathered (data/field.json road levels).
	var road := float(holds.get("road", 0.0))
	if road > 0.0:
		_panel_body.add_child(UI.label(tr("Joined to %s by road: +%d%% gathered") % [holder.name, roundi(road * 100.0)], UI.SMALL_SIZE, UI.MUTED))
	elif mine:
		var best := float(Game.data.field.road.levels[-1].outpostBonus)
		_panel_body.add_child(UI.with_info(UI.label(tr("A road to its village raises the yield"), UI.SMALL_SIZE, UI.MUTED), tr("Join it to %s by road to gather up to +%d%%: the better the roads, the more.") % [holder.name, roundi(best * 100.0)]))
	if not mine:
		return
	var def := _building_def(Rules.OUTPOST)
	var target := int(planned.level) + 1
	if target <= int(def.maxLevel):
		_panel_body.add_child(UI.label(tr("At level %d: %s") % [target, _yield_text(Rules.outpost_yield(Game.data, terrain, target, speed))], UI.SMALL_SIZE, UI.MUTED))
		_build_row(holder, plot, Rules.OUTPOST, target, tr("Rebuild") if level == 0 and int(planned.level) == 0 else tr("Upgrade"))
	else:
		_panel_body.add_child(UI.label(tr("Max level"), UI.SMALL_SIZE, UI.MUTED))
	if int(planned.level) == level:
		var cell := _selected
		var village_id := int(holder.id)
		_panel_body.add_child(UI.button(tr("Abandon outpost"), func() -> void: _abandon_outpost(village_id, cell)))


## The Kalinov Bridge: the stage being built, its story, what it still
## needs and its quests; donations come from the vault.
func _bridge_panel() -> void:
	var bridge := Game.bridge
	if bridge.is_empty():
		return
	_panel_body.add_child(UI.with_info(UI.label(tr("Kalinov Bridge"), UI.HEADING_SIZE), tr(Game.data.bridge.story)))
	var stage := BridgeText.stage_def(Game.data, bridge)
	if stage.is_empty():
		_panel_body.add_child(UI.label(BridgeText.title(Game.data, bridge)))
		return
	_panel_body.add_child(UI.with_info(UI.label(BridgeText.title(Game.data, bridge)), tr(stage.story)))
	_panel_body.add_child(UI.label(BridgeText.progress(Game.data, bridge), UI.SMALL_SIZE))
	# What raising it brings: building early pays.
	var prize := BridgeText.reward(stage)
	if prize != "":
		var prize_label := UI.label(prize, UI.SMALL_SIZE, UI.GOOD)
		prize_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_panel_body.add_child(prize_label)
	for quest in BridgeText.quests(Game.data, bridge):
		_panel_body.add_child(UI.with_info(UI.label(("✓ " if quest[0] else "○ ") + String(quest[1]), UI.SMALL_SIZE, UI.MUTED if quest[0] else UI.ACCENT), quest[2]))
	if bridge.status == "raising":
		var line := UI.label("", UI.SMALL_SIZE)
		_panel_body.add_child(line)
		var done_at := TimeUtil.parse_iso(bridge.raisedAt)
		_tick(line, func() -> String: return tr("Being raised · stands in %s") % TimeUtil.format_duration(done_at - Game.server_now()))
		return
	var row := UI.hbox(8)
	var give := UI.button(tr("Give from the vault"), func() -> void: _donate_bridge(Game.vault.get("amounts", {}), 0))
	give.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(give)
	if BridgeText.embers_missing(Game.data, bridge) > 0 and int(Game.world.get("embers", 0)) > 0:
		var ember := UI.button(tr("Give an Ember"), func() -> void: _donate_bridge({}, 1))
		ember.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(ember)
	var ritual_open := false
	for quest in stage.quests:
		ritual_open = ritual_open or (quest.kind == "ritual" and not bridge.quests.has("ritual"))
	if ritual_open:
		var forge := UI.button(tr("Forge the torc"), func() -> void: _forge_torc())
		forge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		forge.disabled = int(Game.world.get("embers", 0)) < int(Game.data.bridge.ritualEmbers)
		row.add_child(forge)
	_panel_body.add_child(row)


func _donate_bridge(amounts: Dictionary, embers: int) -> void:
	_status.text = ""
	var resources := {}
	for kind in BridgeText.KINDS:
		resources[kind] = int(amounts.get(kind, 0))
	var response := await Api.post_json("/v1/worlds/%d/bridge/donate" % Game.world_id(), {"resources": resources, "embers": embers})
	if not response.ok:
		_status.text = response.error
		Sound.effect("error")
		return
	Sound.effect("coins")
	Game.set_world(response.data)


func _forge_torc() -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/worlds/%d/bridge/ritual" % Game.world_id(), {})
	if not response.ok:
		_status.text = response.error
		return
	Game.set_world(response.data)


## The group's vault in the Holy City: what it holds, and enlarging it.
func _vault_panel() -> void:
	if Game.vault.is_empty():
		return
	var vault := Game.vault
	var level := int(vault.level)
	var capacity := roundi(float(vault.capacity))
	_panel_body.add_child(UI.with_info(UI.label(tr("Vault  Lv %d") % level, UI.HEADING_SIZE), tr("Shared by the group. Caravans bring resources in and out.")))
	var parts := PackedStringArray()
	for kind in Ledger.KINDS:
		parts.append(tr("%s %d") % [UI.resource_name(kind), int(vault.amounts[kind])])
	_panel_body.add_child(UI.label("  ".join(parts) + tr("   (of %d each)") % capacity, UI.SMALL_SIZE))
	_panel_body.add_child(UI.label(tr("Svarog's Ember: %d (from lairs)") % int(Game.world.get("embers", 0)), UI.SMALL_SIZE, UI.MUTED))
	if vault.upgradingTo != null:
		var done_at := TimeUtil.parse_iso(vault.upgradeCompletesAt)
		var line := UI.label("", UI.SMALL_SIZE, UI.MUTED)
		_panel_body.add_child(line)
		_tick(line, func() -> String:
			return tr("Growing to level %d · %s") % [int(vault.upgradingTo), TimeUtil.format_duration(done_at - Game.server_now())])
	elif level < int(Game.data.logistics.vault.maxLevel):
		var cost := CaravanMath.vault_upgrade_cost(Game.data, level + 1)
		var row := UI.hbox()
		var info := UI.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UI.label(tr("Vault → Lv %d (paid from the vault)") % (level + 1)))
		var seconds := CaravanMath.vault_upgrade_seconds(Game.data, level + 1, float(Game.world.speed))
		info.add_child(UI.rich(tr("%s · %s") % [UI.costs(cost), TimeUtil.format_duration(seconds)]))
		row.add_child(info)
		var button := UI.button(tr("Enlarge"), _upgrade_vault)
		button.custom_minimum_size.x = 160
		button.disabled = not Ledger.can_afford(vault.amounts, cost)
		row.add_child(button)
		_panel_body.add_child(row)
	if not _my_village().is_empty():
		_panel_body.add_child(UI.button(tr("Send or fetch by caravan"), func() -> void: _open_caravans({"kind": "vault"})))


func _upgrade_vault() -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/worlds/%d/vault/upgrade" % Game.world_id(), {})
	if not response.ok:
		_status.text = response.error
		return
	Game.note_server_time(response.data.serverTime)


## Holding the selected hex: what the ground gives, armies already there,
## sending one (your hero may lead it) and building a fort.
func _hold_panel(terrain_id: String) -> void:
	var home := _my_village()
	if home.is_empty() or terrain_id == "holy_city" or not FieldRules.passable(Game.data, Game.terrain, _selected):
		return
	var cell := _selected
	var fort := Game.fort_at(cell)
	var camp := Game.camp_at(cell)
	var site := Game.site_at(cell)
	var exploring: bool = not site.is_empty() and site.status == "unexplored"
	var orders := "explore" if exploring else ("hold" if camp.is_empty() else "clear")
	if not site.is_empty():
		var kind: Dictionary = Game.data.sites.kinds.get(site.kind, {})
		_panel_body.add_child(UI.with_info(UI.label(tr(kind.get("name", tr("Ancient site"))), UI.HEADING_SIZE), tr(kind.get("description", ""))))
		var explorer := Game.member_name(int(site.exploredBy)) if site.get("exploredBy") != null else "?"
		_panel_body.add_child(UI.label(SiteText.status(Game.data, site, explorer), UI.SMALL_SIZE, UI.ACCENT))
		if site.status == "unexplored":
			_event_lines(site, "")
	var title := tr("Explore it") if exploring else (tr("Hold this hex") if camp.is_empty() else tr("Clear this camp"))
	_panel_body.add_child(UI.with_info(UI.label(title, UI.HEADING_SIZE), ArmyText.order_text(orders)))
	for line in FieldRules.ground(Game.data, Game.terrain, cell, fort, float(Game.world.speed)) if camp.is_empty() and not exploring else PackedStringArray():
		_panel_body.add_child(UI.label(line, UI.SMALL_SIZE, UI.MUTED))
	var defs: Dictionary = Game.data.units.units
	var held := Game.armies.filter(func(army: Dictionary) -> bool: return ArmyText.held_hex(army) == cell and army.status != "done")
	_paged("held " + str(cell), held, 4 if _roomy() else 2, func(army: Dictionary) -> void:
		var row := UI.hbox()
		var info := UI.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var owner_name := Game.member_name(int(army.ownerAccountId)) if army.ownerAccountId != null else "?"
		info.add_child(UI.label(tr("%s: %s") % [owner_name, ArmyText.units_text(army.units, defs)], UI.SMALL_SIZE))
		var line := UI.label("", UI.SMALL_SIZE, UI.MUTED)
		info.add_child(line)
		var where := ArmyText.target_name(army, Game.village_name)
		_tick(line, func() -> String: return ArmyText.status(army, where, Game.server_now(), _search_ends(army)))
		row.add_child(info)
		var view_id := int(army.id)
		row.add_child(UI.button(tr("View"), func() -> void: _open_army(view_id)))
		if army.ownerAccountId != null and int(army.ownerAccountId) == Game.my_account_id() and army.status in ["stationed", "marching"]:
			var army_id := int(army.id)
			var recall := UI.button(tr("Call home"), func() -> void: _recall_army(army_id))
			recall.custom_minimum_size.x = 150
			row.add_child(recall)
		_panel_body.add_child(row)
		_store_row(army))

	var village_id := int(home.id)
	_panel_body.add_child(UI.label(tr("Send from %s") % home.name, UI.SMALL_SIZE, UI.MUTED))
	var at_home := Rules.garrison_at(home, Game.server_now())
	_unit_pickers(at_home, true)
	var hero := Game.my_hero()
	var hero_ready: bool = not hero.is_empty() and hero.status == "home" and hero.villageId != null and int(hero.villageId) == village_id
	if hero_ready:
		var lead := UI.button(tr("%s leads it: %s") % [hero.name, tr("yes") if _army_hero else tr("no")], func() -> void:
			_army_hero = not _army_hero
			_rebuild_panel())
		_panel_body.add_child(lead)
	_general_picker(village_id)
	_army_stance_picker(home)
	_panel_body.add_child(_return_check(_army_return, ArmyText.return_text(orders, not Game.shipyard_at(cell).is_empty()), func(on: bool) -> void: _army_return = on))
	var go := UI.button({"explore": tr("Explore"), "hold": tr("Hold this hex"), "clear": tr("Storm it")}[orders], func() -> void:
		var order := {"target": {"q": cell.x, "r": cell.y}, "units": _picked_units(at_home), "orders": orders, "withHero": _army_hero and hero_ready, "stance": _army_stance, "returnHome": _army_return}
		if _ready_general(village_id) > 0:
			order.generalId = _ready_general(village_id)
		_send_army(village_id, order))
	_panel_body.add_child(go)
	_picked_hint(go, at_home)
	if orders == "hold":
		_move_here_rows(cell)


## A fort (or, with kind "supply", a supply point) on the selected open
## hex, built from your village.
func _fort_panel(terrain_id: String, kind := "fort") -> void:
	var home := _my_village()
	var cell := _selected
	var supply := kind == "supply"
	if home.is_empty() or terrain_id == "holy_city" or not FieldRules.passable(Game.data, Game.terrain, cell):
		return
	if not Game.fort_at(cell).is_empty() or not Game.camp_at(cell).is_empty() or not Game.site_at(cell).is_empty():
		return
	var village_id := int(home.id)
	_panel_body.add_child(UI.label(tr("Build a supply point") if supply else tr("Build a fort"), UI.HEADING_SIZE))
	var taken := not Game.village_at(cell).is_empty() or not Game.outpost_owner(cell).is_empty()
	var problem := FieldRules.fort_problem(Game.data, home, cell, terrain_id, taken, kind)
	if problem != "":
		_panel_body.add_child(UI.label(problem, UI.SMALL_SIZE, UI.MUTED))
		return
	var rules: Dictionary = Game.data.field.supplyPoint if supply else Game.data.field.fort
	var cost: Dictionary = rules.cost if supply else FieldRules.fort_cost(Game.data, home.get("bonuses", {}))
	var seconds := float(rules.buildSeconds) / float(Game.world.speed)
	var row := UI.hbox()
	var info := UI.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if supply:
		info.add_child(UI.with_info(UI.label(tr("A grain store for armies (%d grain)") % int(rules.grainCapacity)),
			tr("Armies standing here fill up from its grain, and can leave grain here. A supply route keeps it stocked by caravan. A horde passing close burns it unless an army stands on it.")))
	else:
		info.add_child(UI.label(tr("Build a fort (+%d%% defense here)") % roundi(float(Game.data.field.fort.defenseBonus) * 100.0)))
	var cost_line := UI.rich()
	info.add_child(cost_line)
	row.add_child(info)
	var button := UI.button(tr("Build supply point") if supply else tr("Build fort"), func() -> void: _build_fort(village_id, cell, kind))
	button.custom_minimum_size.x = 160
	row.add_child(button)
	_panel_body.add_child(row)
	var cost_text := tr("%s · %s") % [UI.costs(cost), TimeUtil.format_duration(seconds)]
	_tick(cost_line, func() -> String:
		var current: Dictionary = Game.villages.get(village_id, home)
		button.disabled = not Ledger.can_afford(Ledger.amounts_at(current.resources, Game.server_now()), cost)
		return cost_text)


func _build_fort(village_id: int, cell: Vector2i, kind := "fort") -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/%s" % [village_id, "supply-points" if kind == "supply" else "forts"], {"q": cell.x, "r": cell.y})
	if not response.ok:
		_status.text = response.error
		return
	Game.note_server_time(response.data.serverTime)


## Rivers along the selected hex: where bridges stand, and building more.
func _river_section(cell: Vector2i) -> void:
	var edges := RiverText.edges_at(Game.rivers, cell)
	if edges.is_empty():
		return
	_panel_body.add_child(UI.label(tr("Rivers"), UI.HEADING_SIZE))
	var home := _my_village()
	for e in edges:
		var other: Vector2i = e.other
		var text := tr("Towards (%d, %d): ") % [other.x, other.y]
		match String(e.crossing):
			"standing":
				_panel_body.add_child(UI.label(text + tr("a bridge crosses here."), UI.SMALL_SIZE, UI.MUTED))
				continue
			"building":
				_panel_body.add_child(UI.label(text + tr("a bridge is being built."), UI.SMALL_SIZE, UI.MUTED))
				continue
		_panel_body.add_child(UI.label(text + tr("no way across. Hordes can't cross either."), UI.SMALL_SIZE, UI.MUTED))
		if home.is_empty():
			continue
		var problem := RiverText.bridge_problem(Game.data, Vector2i(int(home.q), int(home.r)), cell, other, Game.terrain)
		if problem != "":
			_panel_body.add_child(UI.label(problem, UI.SMALL_SIZE, UI.MUTED))
			continue
		var cost: Dictionary = Game.data.field.bridge.cost
		var row := UI.hbox()
		var info := UI.rich("", UI.SMALL_SIZE, UiTheme.TEXT)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var village_id := int(home.id)
		var target := other
		var button := UI.button(tr("Build bridge"), func() -> void: _build_crossing(village_id, cell, target))
		button.custom_minimum_size.x = 160
		row.add_child(button)
		_panel_body.add_child(row)
		var price := tr("Build a bridge: %s · %s") % [UI.costs(cost), TimeUtil.format_duration(float(Game.data.field.bridge.buildSeconds) / float(Game.world.speed))]
		_tick(info, func() -> String:
			var current: Dictionary = Game.villages.get(village_id, home)
			button.disabled = not Ledger.can_afford(Ledger.amounts_at(current.resources, Game.server_now()), cost)
			return price)


## Roads from the selected hex: where they run, and building more.
func _road_section(cell: Vector2i) -> void:
	if not Game.terrain.has(cell):
		return
	var home := _my_village()
	var roads := RiverText.roads_at(Game.roads, cell)
	var levels := RiverText.road_levels_at(Game.roads, cell)
	var road_levels: Array = Game.data.field.road.levels
	var names := ["E", "NE", "NW", "W", "SW", "SE"]  # tr
	var open: Array[int] = []
	# Standing roads from here your village may improve.
	var better: Array[int] = []
	var built := PackedStringArray()
	for i in 6:
		var other: Vector2i = cell + HexMath.DIRECTIONS[i]
		var buildable: bool = not home.is_empty() and RiverText.road_problem(Game.data, Game.terrain, Game.rivers, Vector2i(int(home.q), int(home.r)), cell, other) == ""
		if roads.has(other):
			var state: String = {"building": tr(" (being built)"), "upgrading": tr(" (being improved)")}.get(roads[other], "")
			built.append("%s%s%s" % [tr(names[i]), tr(" (level %d)") % int(levels[other]) if roads[other] != "building" else "", state])
			if buildable and roads[other] == "standing" and int(levels[other]) < road_levels.size():
				better.append(i)
		elif buildable:
			open.append(i)
	if built.is_empty() and open.is_empty():
		return
	_panel_body.add_child(UI.with_info(UI.label(tr("Roads"), UI.HEADING_SIZE),
		tr("Roads speed the march for everyone on them, the human hordes too, but the beasts of the North keep off them. Each level is faster; the march takes %s of the time.") % RiverText.road_speeds(Game.data)))
	if not built.is_empty():
		_panel_body.add_child(UI.label(tr("Roads run %s.") % ", ".join(built), UI.SMALL_SIZE))
	var village_id := int(home.id) if not home.is_empty() else 0
	for i in better:
		var other: Vector2i = cell + HexMath.DIRECTIONS[i]
		var next := int(levels[other]) + 1
		var step: Dictionary = road_levels[next - 1]
		var row := UI.hbox()
		var line := UI.rich("", UI.SMALL_SIZE, UiTheme.TEXT)
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(line)
		var improve := UI.button(tr("Improve"), func() -> void: _build_road(village_id, cell, other))
		improve.custom_minimum_size.x = 130
		row.add_child(improve)
		_panel_body.add_child(row)
		var step_text := tr("%s to level %d: %s · %s") % [tr(names[i]), next, UI.costs(step.cost), TimeUtil.format_duration(float(step.buildSeconds) / float(Game.world.speed))]
		_tick(line, func() -> String:
			var current: Dictionary = Game.villages.get(village_id, home)
			improve.disabled = not Ledger.can_afford(Ledger.amounts_at(current.resources, Game.server_now()), step.cost)
			return step_text)
	if open.is_empty():
		return
	# One button; then the hex the road goes to is tapped on the map.
	var cost: Dictionary = road_levels[0].cost
	var info := UI.rich("", UI.SMALL_SIZE, UiTheme.TEXT)
	_panel_body.add_child(info)
	var targets: Array = open.map(func(i: int) -> Vector2i: return cell + HexMath.DIRECTIONS[i])
	var build := UI.button(tr("Build a road"), func() -> void:
		_road_from = cell
		_road_village = village_id
		hex_map.show_road_targets(targets)
		_status.text = tr("Tap the hex next to this one to build the road to."), "icon/map")
	_panel_body.add_child(build)
	var text := tr("A road: %s · %s") % [UI.costs(cost), TimeUtil.format_duration(float(road_levels[0].buildSeconds) / float(Game.world.speed))]
	_tick(info, func() -> String:
		var current: Dictionary = Game.villages.get(village_id, home)
		build.disabled = not Ledger.can_afford(Ledger.amounts_at(current.resources, Game.server_now()), cost)
		return text)


func _build_road(village_id: int, a: Vector2i, b: Vector2i) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/roads" % village_id, {"a": {"q": a.x, "r": a.y}, "b": {"q": b.x, "r": b.y}})
	if not response.ok:
		_status.text = response.error
		return
	Game.set_world(response.data)


func _build_crossing(village_id: int, a: Vector2i, b: Vector2i) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/crossings" % village_id, {"a": {"q": a.x, "r": a.y}, "b": {"q": b.x, "r": b.y}})
	if not response.ok:
		_status.text = response.error
		return
	Game.set_world(response.data)


## Your armies standing elsewhere, each with a button to march here and
## hold this hex.
func _move_here_rows(cell: Vector2i) -> void:
	var standing := Game.armies.filter(func(a: Dictionary) -> bool:
		return a.status == "stationed" and a.get("supply") != null and a.ownerAccountId != null and int(a.ownerAccountId) == Game.my_account_id() and ArmyText.held_hex(a) != cell)
	if standing.is_empty():
		return
	_panel_body.add_child(UI.label(tr("Your armies standing elsewhere"), UI.SMALL_SIZE, UI.MUTED))
	var defs: Dictionary = Game.data.units.units
	for army in standing:
		var army_id := int(army.id)
		var row := UI.hbox()
		var text := UI.label(tr("%s · %s") % [ArmyText.units_text(army.units, defs), ArmyText.target_name(army, Game.village_name)], UI.SMALL_SIZE)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var go := UI.button(tr("Move here"), func() -> void: _army_command(army_id, "move", {"target": {"q": cell.x, "r": cell.y}}))
		go.custom_minimum_size.x = 150
		row.add_child(go)
		_panel_body.add_child(row)


## The name of an ancient site by its id ("" if unknown).
func _site_name(site_id: Variant) -> String:
	if site_id == null:
		return ""
	for site in Game.sites:
		if int(site.id) == int(site_id):
			return tr(Game.data.get("sites", {}).get("kinds", {}).get(String(site.kind), {}).get("name", ""))
	return ""


## Settlers from `village_id` on the road, and how recent ones ended.
func _expeditions_list(village_id: int) -> void:
	var mine := Game.expeditions.filter(func(e: Dictionary) -> bool: return int(e.villageId) == village_id)
	for expedition in mine:
		var line := UI.label("", UI.SMALL_SIZE)
		_panel_body.add_child(line)
		_tick(line, func() -> String:
			var now := Game.server_now()
			match expedition.status:
				"outbound":
					return tr("Settlers on their way to found %s · %s") % [expedition.name, TimeUtil.format_duration(TimeUtil.parse_iso(expedition.arrivesAt) - now)]
				"returning":
					return tr("Settlers coming home (%s) · %s") % [String(expedition.failure).trim_suffix("."), TimeUtil.format_duration(TimeUtil.parse_iso(expedition.returnsAt) - now)]
				"founded":
					return tr("Founded %s") % expedition.name
			return tr("Settlers came home from (%d, %d)") % [int(expedition.q), int(expedition.r)])


## An empty settleable hex: can your village send settlers here?
func _found_panel(terrain: String) -> void:
	var home := _my_village()
	var def: Dictionary = Game.data.terrain.terrain.get(terrain, {})
	if home.is_empty() or not def.get("settleable", false):
		return
	var home_cell := Vector2i(int(home.q), int(home.r))
	var others := Game.villages.values().map(func(v: Dictionary) -> Vector2i: return Vector2i(int(v.q), int(v.r)))
	var problem := Rules.settle_problem(Game.data, _selected, terrain, home_cell, others, not Game.outpost_owner(_selected).is_empty())
	_panel_body.add_child(UI.label(tr("Found a village"), UI.HEADING_SIZE))
	if problem != "":
		_panel_body.add_child(UI.label(problem, UI.SMALL_SIZE, UI.MUTED))
		return
	var needed := int(Game.data.expansion.settlersNeeded)
	var at_home := int(Rules.garrison_at(home, Game.server_now()).get("settler", 0))
	_panel_body.add_child(UI.label(tr("%d settlers from %s walk here and found it (%d at home). Train them in a Settlers' Lodge.") % [needed, home.name, at_home], UI.SMALL_SIZE, UI.MUTED))
	var name_edit := UI.line_edit(tr("Name (optional)"))
	_panel_body.add_child(name_edit)
	var village_id := int(home.id)
	var cell := _selected
	var send := UI.button(tr("Send settlers"), func() -> void: _send_settlers(village_id, cell, name_edit.text))
	send.disabled = at_home < needed
	_panel_body.add_child(send)


func _send_settlers(village_id: int, cell: Vector2i, village_name: String) -> void:
	_status.text = ""
	var body := {"q": cell.x, "r": cell.y}
	if village_name.strip_edges() != "":
		body.name = village_name.strip_edges()
	var response := await Api.post_json("/v1/villages/%d/found" % village_id, body)
	if not response.ok:
		_status.text = response.error
		return
	Game.note_server_time(response.data.serverTime)
	Game.update_village(response.data.village)


## An empty hex: can your village put an outpost here?
func _claim_panel(terrain: String) -> void:
	var home := _my_village()
	if home.is_empty() or not Game.data.buildings.buildings[Rules.OUTPOST].yields.has(terrain):
		return
	var taken := not Game.village_at(_selected).is_empty()
	var problem := Rules.claim_problem(Game.data, home, _selected, terrain, taken)
	var speed := float(Game.world.speed)
	_panel_body.add_child(UI.label(tr("An outpost here would gather %s.") % _yield_text(Rules.outpost_yield(Game.data, terrain, 1, speed)), UI.SMALL_SIZE, UI.MUTED))
	if problem != "":
		_panel_body.add_child(UI.label(problem, UI.SMALL_SIZE, UI.MUTED))
		return
	var def := _building_def(Rules.OUTPOST)
	var hall := Rules.hall_level(home)
	var queue_full: bool = home.queue.size() >= Rules.queue_limit(Game.data, hall)
	var cost := Rules.level_cost(def, 1)
	var seconds := Rules.build_seconds(def, 1, speed, Rules.hall_speedup(Game.data, hall) * ResearchRules.time_factor(home.get("bonuses", {}), "buildTime"))
	var village_id := int(home.id)
	var cell := _selected
	var row := UI.hbox()
	var info := UI.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(UI.with_card(UI.label(tr("Build an outpost")), _building_card(home, Rules.OUTPOST, 0)))
	var cost_line := UI.rich()
	info.add_child(cost_line)
	row.add_child(info)
	var button := UI.button(tr("Claim"), func() -> void: _claim_outpost(village_id, cell))
	button.custom_minimum_size.x = 160
	row.add_child(button)
	_panel_body.add_child(row)
	var cost_text := tr("%s · %s") % [UI.costs(cost), TimeUtil.format_duration(seconds)]
	_tick(cost_line, func() -> String:
		var current: Dictionary = Game.villages.get(village_id, home)
		var affordable := Ledger.can_afford(Ledger.amounts_at(current.resources, Game.server_now()), cost)
		button.disabled = queue_full or not affordable
		return cost_text + (tr("  (queue full)") if queue_full else ""))


func _yield_text(amounts: Dictionary) -> String:
	var parts := PackedStringArray()
	for kind in Ledger.KINDS:
		if float(amounts[kind]) > 0.0:
			parts.append(tr("%s +%d/h") % [UI.resource_name(kind), roundi(TimeUtil.per_real_hour(float(amounts[kind])))])
	return ", ".join(parts) if not parts.is_empty() else tr("nothing")


func _claim_outpost(village_id: int, cell: Vector2i) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/outposts" % village_id, {"q": cell.x, "r": cell.y})
	if not response.ok:
		_status.text = response.error
		return
	Game.note_server_time(response.data.serverTime)
	Game.update_village(response.data.village)


func _abandon_outpost(village_id: int, cell: Vector2i) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/outposts/abandon" % village_id, {"q": cell.x, "r": cell.y})
	if not response.ok:
		_status.text = response.error
		return
	Game.note_server_time(response.data.serverTime)
	Game.update_village(response.data.village)


func _ally_village_panel(village: Dictionary) -> void:
	_panel_body.add_child(UI.label(village.name, UI.HEADING_SIZE))
	_panel_body.add_child(UI.label(tr("Ally: %s") % Game.member_name(int(village.ownerAccountId)), UI.SMALL_SIZE, UI.MUTED))
	var buildings := PackedStringArray()
	for building in village.levels:
		buildings.append(tr("%s %d") % [tr(_building_def(building).name), int(village.levels[building])])
	_panel_body.add_child(UI.label(" · ".join(buildings), UI.SMALL_SIZE))
	_panel_body.add_child(_live_unit_chips(func() -> Dictionary: return Rules.garrison_at(village, Game.server_now())))
	var their_hero := Game.hero_at(int(village.id))
	if not their_hero.is_empty():
		_panel_body.add_child(UI.label(tr("Hero %s (Lv %d) leads the garrison") % [their_hero.name, int(their_hero.level)], UI.SMALL_SIZE, UI.MUTED))
	if not _my_village().is_empty():
		var ally_id := int(village.id)
		_panel_body.add_child(UI.button(tr("Send resources"), func() -> void: _open_caravans({"kind": "village", "id": ally_id})))


## Your village as seen on the map: a summary and the way in.
func _own_village_panel(village: Dictionary) -> void:
	_panel_body.add_child(UI.label(village.name, UI.HEADING_SIZE))
	_handed_line(village)
	var hall := Rules.hall_level(village)
	var queue: Array = village.queue
	_panel_body.add_child(UI.label(tr("Hall %d · Building %d/%d · Outposts %d/%d") % [hall, queue.size(), Rules.queue_limit(Game.data, hall),
		Rules.outpost_plots(village).size(), Rules.outpost_limit(Game.data, hall)], UI.SMALL_SIZE, UI.MUTED))
	if village.get("besieged", false):
		_panel_body.add_child(UI.label(tr("Under siege: outposts produce nothing until the battle ends."), UI.SMALL_SIZE, UI.ERROR))
	if village.get("ruin") is Dictionary:
		_panel_body.add_child(UI.label(tr("In ruins: rebuild it from the village view."), UI.SMALL_SIZE, UI.ERROR))
	if village.get("refuge", false):
		_panel_body.add_child(UI.with_info(UI.label(tr("A refugee camp"), UI.SMALL_SIZE, UI.MUTED), tr("Hordes raid a refugee camp but never burn it.")))
	var village_id := int(village.id)
	_panel_body.add_child(_live_unit_chips(func() -> Dictionary:
		return Rules.garrison_at(Game.villages.get(village_id, village), Game.server_now())))
	_panel_body.add_child(UI.primary(tr("Enter village"), func() -> void: _set_view("village"), "icon/village"))
	_hero_line(village_id)


func _on_map_tapped(world_position: Vector2) -> void:
	var local := hex_map.to_local(world_position)
	var cell := hex_map.local_to_hex(local)
	# Picking where a caravan goes: a village, an outpost (its village), the
	# Holy City's vault, a shipyard or a fort or supply point.
	if _caravan_picking != 0:
		var target := _caravan_target_at(cell, _caravan_picking)
		if target.is_empty():
			_status.text = tr("A caravan can go to a village or outpost, the Holy City, a shipyard, or a fort or supply point.")
			return
		var from := _caravan_picking
		_caravan_picking = 0
		_status.text = ""
		_open_caravans(target, from)
		return
	# Moving an army: the hex tapped is where it goes (onto your own
	# settlement it joins the garrison only if told to).
	if _army_moving != 0:
		var army_id := _army_moving
		_army_moving = 0
		_status.text = ""
		if hex_map.has_hex(cell):
			var village := Game.village_at(cell)
			if village.is_empty():
				_army_command(army_id, "move", {"target": {"q": cell.x, "r": cell.y}})
			elif Game.is_mine(village):
				_army_command(army_id, "move", {"villageId": int(village.id), "join": _army_join})
			else:
				_army_command(army_id, "move", {"villageId": int(village.id)})
		_rebuild_panel()
		return
	# A new army's destination: back to the village's form with it.
	if _army_sending != 0:
		var from := _army_sending
		_army_sending = 0
		_status.text = ""
		if hex_map.has_hex(cell):
			_send_target = cell
		_back_to_send(from)
		return
	# Laying a road: the hex tapped is where it goes (anything else cancels).
	if _road_from != Vector2i.MAX:
		var from := _road_from
		_road_from = Vector2i.MAX
		var picked: bool = hex_map.road_targets.has(cell)
		hex_map.show_road_targets([])
		_status.text = ""
		if picked:
			_build_road(_road_village, from, cell)
			return
	# An army's marker: its own sheet.
	var tapped_army := hex_map.army_at(local, Game.server_now()) if _road_from == Vector2i.MAX else 0
	if tapped_army != 0:
		_open_army(tapped_army)
		return
	if hex_map.has_hex(cell):
		_select(cell)
