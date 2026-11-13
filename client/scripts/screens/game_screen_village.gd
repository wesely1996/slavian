extends "res://scripts/screens/game_screen_map.gd"
## The in-world screen, the village's part: its plots and buildings, the
## build queue, the market and its bounty board, research.

func _on_plot_tapped(plot: String) -> void:
	_plot = plot
	_tab = "village"
	_side["buildings"] = "plot"
	_panel_mode = "hex"
	_rebuild_panel()


func _research_section(village: Dictionary) -> void:
	var tabs := [["academy", "building/academy_1", tr("Academy"), _academy_tab.bind(village)]]
	for branch in Game.data.research.branches:
		tabs.append([branch, BRANCH_ART.get(branch, "icon/research"), tr(Game.data.research.branches[branch]), _research_branch.bind(village, branch)])
	_side_tabs("research", tabs, VILLAGE_TOP)


## What the group studies now (and what it still needs sent), and the
## group's lore scrolls.
func _academy_tab(village: Dictionary) -> void:
	var village_id := int(village.id)
	var academy := int(village.levels.get("academy", 0))
	var group := ResearchRules.group(Game.research)
	var current: Dictionary = group.current
	var techs: Dictionary = Game.data.research.techs
	_panel_body.add_child(UI.with_info(UI.label(tr("Academy Lv %d · the group knows %d of %d techs") % [academy, group.done.size(), techs.size()], UI.SMALL_SIZE, UI.MUTED),
		tr("Research is the group's: every tech helps every village of every member. One tech at a time: a member with a high enough Academy begins it with the group's research, then everyone sends its resources from any village; when it is all paid, the scholars set to work.")))
	# Research comes in from every member's Academies; every tech takes some.
	var points := UI.label("", UI.SMALL_SIZE)
	_panel_body.add_child(points)
	_tick(points, func() -> String:
		var pool := Game.group_research()
		return tr("The group's research: %d (+%d per hour from every Academy)") % [floori(pool.points), roundi(TimeUtil.per_real_hour(pool.perHour))])
	if current.is_empty():
		_panel_body.add_child(UI.label(tr("Nothing being researched: pick a tech from a branch.") if academy >= 1 else tr("Build an Academy to begin research for the group."), UI.SMALL_SIZE, UI.MUTED))
	else:
		var tech_name: String = tr(techs.get(current.tech, {}).get("name", current.tech))
		var starter := Game.member_name(int(current.accountId))
		if current.status == "funding":
			_panel_body.add_child(UI.label(tr("Gathering for %s (begun by %s)") % [tech_name, starter], UI.SMALL_SIZE, UI.ACCENT))
			var bar := _gauge(UI.GOOD)
			bar.value = ResearchRules.paid_share(current)
			_panel_body.add_child(bar)
			var left := ResearchRules.still_needed(current)
			_panel_body.add_child(UI.rich(tr("Still needed: %s") % UI.costs(left)))
			var send := UI.button(tr("Send what it needs from %s") % village.name, func() -> void: _fund_research(village_id), "icon/coin")
			_panel_body.add_child(send)
		else:
			var done_at := TimeUtil.parse_iso(current.completesAt)
			var line := UI.label("", UI.SMALL_SIZE)
			_panel_body.add_child(line)
			_tick(line, func() -> String: return tr("Researching %s · %s") % [tech_name, TimeUtil.format_duration(done_at - Game.server_now())])
	if Game.lore.is_empty():
		return
	_panel_body.add_child(UI.label(tr("Lore scrolls of the group"), UI.HEADING_SIZE))
	_paged("lore", Game.lore, 5 if _roomy() else 2, func(entry: Dictionary) -> void:
		var def: Dictionary = Game.data.lore.scrolls.get(entry.scroll, {})
		var finder := Game.member_name(int(entry.accountId)) if entry.get("accountId") != null else "?"
		_panel_body.add_child(UI.label(tr("%s (found by %s)") % [tr(def.get("name", entry.scroll)), finder]))
		_panel_body.add_child(UI.label(SiteText.scroll_effect(Game.data, entry.scroll), UI.SMALL_SIZE, UI.MUTED)))


## One branch of the group's tree, a few techs to a page.
func _research_branch(village: Dictionary, branch: String) -> void:
	var village_id := int(village.id)
	var academy := int(village.levels.get("academy", 0))
	var group := ResearchRules.group(Game.research)
	var done: Dictionary = group.done
	var current: Dictionary = group.current
	var techs: Dictionary = Game.data.research.techs
	var speed := float(Game.world.speed)
	_panel_body.add_child(UI.label(tr(Game.data.research.branches[branch]), UI.HEADING_SIZE))
	var in_branch := techs.keys().filter(func(tech: String) -> bool: return techs[tech].branch == branch)
	_paged("research " + branch, in_branch, 3 if _roomy() else 2, func(tech: String) -> void:
		var def: Dictionary = techs[tech]
		var info := UI.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var known := done.has(tech)
		info.add_child(UI.label(("✓ " if known else "") + tr(def.name)))
		info.add_child(UI.label(tr(def.description), UI.SMALL_SIZE, UI.MUTED))
		var row := UI.hbox()
		row.add_child(info)
		_panel_body.add_child(row)
		if known:
			return
		if not current.is_empty() and current.tech == tech:
			info.add_child(UI.label(tr("Being gathered for: see the Academy") if current.status == "funding" else tr("Being researched"), UI.SMALL_SIZE, UI.ACCENT))
			return
		var problem := ResearchRules.problem(Game.data, tech, academy, done, not current.is_empty(), Game.scrolls())
		var cost: Dictionary = def.cost
		var needed := ResearchRules.research_cost(Game.data, tech)
		var cost_line := UI.rich()
		info.add_child(cost_line)
		var duration := TimeUtil.format_duration(float(def.seconds) / speed)
		var cost_text := tr("%d research, then %s from the members · %s") % [needed, UI.costs(cost), duration]
		if problem != "":
			cost_line.text = tr("%s  (%s)") % [cost_text, problem.trim_suffix(".").to_lower()]
			return
		var button := UI.button(tr("Begin"), func() -> void: _start_research(village_id, tech))
		button.custom_minimum_size.x = 140
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(button)
		_tick(cost_line, func() -> String:
			var scholarly: bool = Game.group_research().points >= needed
			button.disabled = not scholarly
			return cost_text if scholarly else tr("%s  (not enough research)") % cost_text))


func _fund_research(village_id: int) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/research/fund" % village_id, {})
	if not response.ok:
		_status.text = response.error
		Sound.effect("error")
		return
	Sound.effect("done")
	Game.note_server_time(response.data.serverTime)
	Game.update_village(response.data.village)


func _start_research(village_id: int, tech: String) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/research" % village_id, {"tech": tech})
	if not response.ok:
		_status.text = response.error
		Sound.effect("error")
		return
	Sound.effect("done")
	Game.note_server_time(response.data.serverTime)
	Game.update_village(response.data.village)


## The town's name between arrows that step through the player's towns (and
## those they look after), with a pen to rename it.
func _town_switcher(village: Dictionary) -> void:
	var mine := Game.my_villages()
	var index := 0
	for i in mine.size():
		if int(mine[i].id) == int(village.id):
			index = i
	var step := func(by: int) -> void:
		Game.current_village_id = int(mine[posmod(index + by, mine.size())].id)
		_plot = Rules.HALL_PLOT
		_renaming = false
		_rebuild_panel()
	# One village and no pen out: its name is on the top band already.
	if mine.size() < 2 and not _renaming:
		if not Game.is_mine(village):
			_panel_body.add_child(UI.label(tr("Looking after it for %s") % Game.member_name(int(village.ownerAccountId)), UI.SMALL_SIZE, UI.MUTED))
		return
	var row := UI.hbox(8)
	var back := UI.button("◀", step.bind(-1))
	back.tooltip_text = tr("Previous town")
	back.disabled = mine.size() < 2
	row.add_child(back)
	back.custom_minimum_size.x = 56.0
	if _renaming:
		var key := "town:%d" % int(village.id)
		var fresh := not _drafts.has(key)
		var field := _draft_field(key, tr("Town name"), village.name)
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var save := func(_text := "") -> void: _rename(int(village.id), field.text)
		field.text_submitted.connect(save)
		row.add_child(field)
		row.add_child(UI.primary(tr("Save"), save))
		# Opening the pen selects the old name to type over; a rebuild while
		# typing keeps the text and the caret instead (_draft_field).
		if fresh:
			_drafts[key] = {"text": village.name, "caret": village.name.length()}
			field.call_deferred("grab_focus")
			field.call_deferred("select_all")
	else:
		var title := UI.label(village.name, UI.HEADING_SIZE)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.autowrap_mode = TextServer.AUTOWRAP_OFF
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title.custom_minimum_size.x = 60.0
		title.tooltip_text = tr("Town %d of %d") % [index + 1, mine.size()]
		row.add_child(title)
		if Game.is_mine(village):
			var pen := UI.button("✎", func() -> void:
				_renaming = true
				_rebuild_panel())
			pen.tooltip_text = tr("Rename the town")
			pen.custom_minimum_size.x = 56.0
			row.add_child(pen)
	var forward := UI.button("▶", step.bind(1))
	forward.tooltip_text = tr("Next town")
	forward.disabled = mine.size() < 2
	forward.custom_minimum_size.x = 56.0
	row.add_child(forward)
	_panel_body.add_child(row)
	if not Game.is_mine(village):
		_panel_body.add_child(UI.label(tr("Looking after it for %s") % Game.member_name(int(village.ownerAccountId)), UI.SMALL_SIZE, UI.MUTED))


func _rename(village_id: int, name: String) -> void:
	_status.text = ""
	if name.strip_edges().is_empty():
		_renaming = false
		_drafts.erase("town:%d" % village_id)
		_rebuild_panel()
		return
	var response := await Api.post_json("/v1/villages/%d/rename" % village_id, {"name": name.strip_edges()})
	if not response.ok:
		_status.text = response.error
		return
	_renaming = false
	_drafts.erase("town:%d" % village_id)
	Game.update_village(response.data.village)
	_rebuild_panel()


func _village_panel() -> void:
	var village := _my_village()
	if village.is_empty():
		return
	_village_view.show_village(Game.data, village, _plot)
	_town_switcher(village)
	if village.get("ruin") is Dictionary:
		_ruin_section(village)
		return
	var tabs := [["village", tr("Buildings")], ["troops", tr("Troops")], ["caravans", tr("Caravans")], ["research", tr("Research")]]
	_panel_body.add_child(UI.tabs(tabs, _tab, func(key: String) -> void:
		_tab = key
		_scroll.scroll_vertical = 0
		_rebuild_panel()))
	if _tab == "troops":
		_troops_section(village)
	elif _tab == "caravans":
		_caravans_section(village)
	elif _tab == "research":
		_research_section(village)
	else:
		_side_tabs("buildings", [["plot", "icon/build", tr("The picked plot"), _plot_section.bind(village)],
			["queue", "icon/clock", tr("Build queue"), _queue_section.bind(village)],
			["outposts", "map/outpost", tr("Outposts"), _outposts_section.bind(village)]], VILLAGE_TOP)


## A razed village: what rebuilding it costs, or how long until it stands.
func _ruin_section(village: Dictionary) -> void:
	var ruin: Dictionary = village.ruin
	var village_id := int(village.id)
	_panel_body.add_child(UI.label(tr("%s lies in ruins") % village.name, UI.HEADING_SIZE))
	if ruin.get("rebuildingUntil") != null:
		var line := UI.label("", UI.SMALL_SIZE, UI.MUTED)
		_panel_body.add_child(line)
		var until := TimeUtil.parse_iso(ruin.rebuildingUntil)
		_tick(line, func() -> String: return tr("Rebuilding · stands again in %s") % TimeUtil.format_duration(until - Game.server_now()))
		return
	_panel_body.add_child(UI.with_info(UI.label(tr("Burned down by a horde"), UI.SMALL_SIZE, UI.MUTED), tr("A horde burned it down. Rebuild everything as it stood, at %d%% of what it cost.") % roundi(float(Game.data.horde.ruins.rebuildCostShare) * 100.0)))
	var cost := HordeText.rebuild_cost(Game.data, ruin.plots)
	var seconds := float(Game.data.horde.ruins.rebuildHours) * 3600.0 / float(Game.world.speed)
	var row := UI.hbox()
	var cost_line := UI.rich()
	cost_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cost_line)
	var button := UI.button(tr("Rebuild"), func() -> void: _rebuild_village(village_id))
	button.custom_minimum_size.x = 160
	row.add_child(button)
	_panel_body.add_child(row)
	var cost_text := tr("%s · %s") % [UI.costs(cost), TimeUtil.format_duration(seconds)]
	_tick(cost_line, func() -> String:
		var current: Dictionary = Game.villages.get(village_id, village)
		button.disabled = not Ledger.can_afford(Ledger.amounts_at(current.resources, Game.server_now()), cost)
		return cost_text)


func _rebuild_village(village_id: int) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/rebuild" % village_id, {})
	if not response.ok:
		_status.text = response.error
		return
	Game.note_server_time(response.data.serverTime)
	Game.update_village(response.data.village)


func _queue_section(village: Dictionary) -> void:
	var queue: Array = village.queue
	var limit := Rules.queue_limit(Game.data, Rules.hall_level(village))
	_panel_body.add_child(UI.label(tr("Build queue (%d/%d)") % [queue.size(), limit], UI.SMALL_SIZE, UI.MUTED))
	if queue.is_empty():
		_panel_body.add_child(UI.label(tr("Nothing under construction."), UI.SMALL_SIZE, UI.MUTED))
	# A build can be called off for most of what it cost (more with a
	# higher Elder's Hall); later levels of the same plot go with it.
	var rule: Dictionary = Game.data.buildings.village.get("cancelRefund", {"base": 0.8, "perHallLevel": 0.02})
	var share := roundi(minf(1.0, float(rule.base) + float(rule.perHallLevel) * maxi(0, Rules.hall_level(village) - 1)) * 100.0)
	var village_id := int(village.id)
	for item in queue:
		var done_at := TimeUtil.parse_iso(item.completesAt)
		var text := tr("%s → Lv %d") % [tr(_building_def(item.building).name), int(item.targetLevel)]
		var row := UI.hbox(8)
		var line := UI.label()
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(line)
		_tick(line, func() -> String:
			var left := done_at - Game.server_now()
			return tr("%s   %s") % [text, TimeUtil.format_duration(left) if left > 0 else tr("finishing…")])
		if Game.is_mine(village):
			var plot := String(item.plot)
			var level := int(item.targetLevel)
			var cancel := UI.button(tr("Cancel"), func() -> void: _cancel_build(village_id, plot, level))
			cancel.tooltip_text = tr("Call it off: %d%% of what it cost comes back.") % share
			row.add_child(cancel)
		_panel_body.add_child(row)


func _cancel_build(village_id: int, plot: String, level: int) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/build/cancel" % village_id, {"plot": plot, "targetLevel": level})
	if not response.ok:
		_status.text = response.error
		Sound.effect("error")
		return
	Game.note_server_time(response.data.serverTime)
	Game.update_village(response.data.village)


func _outposts_section(village: Dictionary) -> void:
	var plots := Rules.outpost_plots(village)
	var limit := Rules.outpost_limit(Game.data, Rules.hall_level(village))
	_panel_body.add_child(UI.label(tr("Outposts (%d/%d)") % [plots.size(), limit], UI.SMALL_SIZE, UI.MUTED))
	if village.get("besieged", false):
		_panel_body.add_child(UI.label(tr("Under siege: outposts produce nothing until the battle ends."), UI.SMALL_SIZE, UI.ERROR))
	if plots.is_empty():
		_panel_body.add_child(UI.with_info(UI.label(tr("None yet: tap a hex near the village"), UI.SMALL_SIZE, UI.MUTED), tr("None yet. Tap a forest, plains, hills, mountain or lake hex within %d of the village on the map to claim one.") % int(Game.data.buildings.village.outpostRange)))
	var speed := float(Game.world.speed)
	_paged("outposts", plots, 6 if _roomy() else 3, func(plot: String) -> void:
		var holds: Dictionary = village.plots[plot]
		var cell := Rules.outpost_hex(plot)
		var level := int(holds.level)
		var terrain: String = holds.get("terrain", "")
		var row := UI.hbox()
		var text := UI.label(tr("%s (%d, %d)  %s") % [Terrain.display_name(terrain, Game.data), cell.x, cell.y,
			tr("Lv %d · %s") % [level, _yield_text(Rules.outpost_yield(Game.data, terrain, level, speed))] if level > 0 else tr("Lv 0")], UI.SMALL_SIZE)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var show_button := UI.button(tr("Show"), func() -> void:
			_set_view("map")
			camera.position = hex_map.hex_to_local(cell)
			_select(cell))
		show_button.custom_minimum_size.x = 120
		row.add_child(show_button)
		_panel_body.add_child(row))


## The picked plot: what stands there and what it would cost to upgrade, or
## for an empty slot, the buildings that could go there.
func _plot_section(village: Dictionary) -> void:
	if not village.plots.has(_plot):
		_plot = Rules.HALL_PLOT
	var holds: Dictionary = village.plots[_plot]
	var planned := Rules.planned_plot(village, _plot)
	var on_walls := Rules.is_tower_slot(_plot)
	if Rules.is_locked(Game.data, village, _plot):
		if on_walls:
			_panel_body.add_child(UI.label(tr("Wall slot"), UI.HEADING_SIZE))
			_panel_body.add_child(UI.label(tr("Raise the walls to level %d to build a tower here.") % Rules.tower_unlock_level(Game.data, Rules.plot_index(_plot)), UI.SMALL_SIZE, UI.MUTED))
			return
		_panel_body.add_child(UI.label(tr("Locked slot"), UI.HEADING_SIZE))
		var needed := Rules.slot_unlock_level(Game.data, Rules.plot_index(_plot))
		_panel_body.add_child(UI.label(tr("Upgrade the Elder's Hall to level %d to build here.") % needed, UI.SMALL_SIZE, UI.MUTED))
		return
	if planned.building == null:
		_panel_body.add_child(UI.label(tr("Empty wall slot") if on_walls else tr("Empty slot"), UI.HEADING_SIZE))
		var options := Rules.constructible(Game.data, village, "tower" if on_walls else "center", Game.village_site(village))
		if options.is_empty():
			_panel_body.add_child(UI.label(tr("Every tower already stands on these walls.") if on_walls else tr("Every building already stands in this village."), UI.SMALL_SIZE, UI.MUTED))
		# What can stand here, a card each: picture, name, price, Build.
		var grid := UI.vbox(8)
		var page := UI.paged(options, int(_pages.get("plot options", 0)), 5 if _roomy() else 3, func(at: int) -> void:
			_pages["plot options"] = at
			_scroll.scroll_vertical = 0
			_rebuild_panel())
		for building in page[0]:
			grid.add_child(_building_choice(village, building, on_walls))
		_panel_body.add_child(grid)
		if page[1].get_child_count() > 0:
			_panel_body.add_child(page[1])
		return

	var building: String = planned.building
	var def := _building_def(building)
	var level := int(holds.level)
	var title := tr("%s  Lv %d") % [tr(def.name), level]
	if level >= int(def.maxLevel):
		title += tr("  (max)")
	elif int(planned.level) > level:
		title += tr("  (→ %d queued)") % int(planned.level)
	_panel_body.add_child(UI.with_card(UI.label(title, UI.HEADING_SIZE), _building_card(village, building, level)))
	var effect := _effect_text(village, building, level)
	if effect != "":
		_panel_body.add_child(UI.label(effect, UI.SMALL_SIZE, UI.MUTED))
	var target := int(planned.level) + 1
	if target <= int(def.maxLevel):
		_build_row(village, _plot, building, target, (tr("Build") if level == 0 and int(planned.level) == 0 else tr("Upgrade")) + tr(" → Lv %d") % target, "", false)
	if building == Rules.HALL and Game.is_mine(village) and not _renaming and Game.my_villages().size() < 2:
		var pen := UI.button(tr("Rename"), func() -> void:
			_renaming = true
			_rebuild_panel())
		pen.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_panel_body.add_child(pen)
	if building == "market" and level > 0:
		_market_section(village, level)
	if building == "heroes_hall" and level > 0:
		_generals_section(village)
	_demolish_row(village, building, level)
	if building == Rules.HALL:
		_abandon_row(village)


## One building that can go up on the picked plot, as a card: its picture
## and name (tap the i for its sheet), what it costs and how long it takes,
## and Build; or what it still needs.
func _building_choice(village: Dictionary, building: String, on_walls: bool) -> Control:
	var village_id := int(village.id)
	var plot := _plot
	var def := _building_def(building)
	var card := UI.card(8)
	var row := UI.hbox(10)
	card.add_child(row)
	var art := Art.building_id(building, 1)
	if Art.has(art):
		row.add_child(UI.icon(art, 64))
	var box := UI.vbox(2)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	box.add_child(UI.label(tr(def.name)))
	if on_walls:
		box.add_child(UI.label(WallText.tower_effect(Game.data, building, 0, float(Game.world.speed)), UI.SMALL_SIZE - 2, UI.MUTED))
	row.add_child(UI.info_card(_building_card(village, building, 0)))
	var missing := Rules.missing_requirement(Game.data, village, building)
	if not missing.is_empty():
		box.add_child(UI.label(tr("Needs %s level %d") % [tr(_building_def(missing[0]).name), missing[1]], UI.SMALL_SIZE, UI.ERROR))
		return card
	var hall := Rules.hall_level(village)
	var queue_full: bool = village.queue.size() >= Rules.queue_limit(Game.data, hall)
	var cost := Rules.level_cost(def, 1)
	var time := TimeUtil.format_duration(Rules.build_seconds(def, 1, float(Game.world.speed), Rules.hall_speedup(Game.data, hall) * ResearchRules.time_factor(village.get("bonuses", {}), "buildTime")))
	var cost_line := UI.rich()
	box.add_child(cost_line)
	var button := UI.primary(tr("Build"), func() -> void: _queue_build(village_id, plot, building))
	button.custom_minimum_size.x = 120
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(button)
	_tick(cost_line, func() -> String:
		var home: Dictionary = Game.villages.get(village_id, village)
		var have := Ledger.amounts_at(home.resources, Game.server_now())
		button.disabled = queue_full or not Ledger.can_afford(have, cost)
		return tr("%s · %s") % [UI.costs(cost, 22, have), time] + (tr("  (queue full)") if queue_full else ""))
	return card


func _market_section(village: Dictionary, level: int) -> void:
	var village_id := int(village.id)
	var rate := Rules.market_rate(Game.data, level)
	_panel_body.add_child(UI.label(tr("Trade"), UI.HEADING_SIZE))
	var kinds: Array = Ledger.KINDS
	var row := UI.hbox(8)
	var give := UI.options(kinds.map(func(kind: String) -> String: return UI.resource_name(kind)), kinds.find(_trade.give))
	give.item_selected.connect(func(i: int) -> void:
		_trade.give = kinds[i]
		_rebuild_panel())
	row.add_child(give)
	row.add_child(_number_field("trade:amount", int(_trade.amount), 1, 999999, func(n: int) -> void: _trade.amount = n))
	row.add_child(UI.label(tr("for"), UI.SMALL_SIZE))
	var get_ := UI.options(kinds.map(func(kind: String) -> String: return UI.resource_name(kind)), kinds.find(_trade.get))
	get_.item_selected.connect(func(i: int) -> void:
		_trade.get = kinds[i]
		_rebuild_panel())
	row.add_child(get_)
	_panel_body.add_child(row)
	var deal := UI.hbox(8)
	var summary := UI.label("", UI.SMALL_SIZE, UI.MUTED)
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deal.add_child(summary)
	var button := UI.primary(tr("Trade"), func() -> void: _market_trade(village_id))
	deal.add_child(button)
	_panel_body.add_child(deal)
	_tick(summary, func() -> String:
		var got := floori(int(_trade.amount) * rate)
		var home: Dictionary = Game.villages.get(village_id, village)
		var have := float(Ledger.amounts_at(home.resources, Game.server_now()).get(_trade.give, 0))
		button.disabled = _trade.give == _trade.get or got < 1 or have < int(_trade.amount)
		return tr("You get %d %s (%d%% of what you give)") % [got, UI.resource_name(_trade.get), roundi(rate * 100.0)])

	# The bounty board trades between players: single player has none.
	if not Local.is_active():
		_bounty_board(village, level)

	var hero := Game.my_hero()
	var spare: Array = hero.get("inventory", [])
	_panel_body.add_child(UI.label(tr("Sell spare gear"), UI.HEADING_SIZE))
	if spare.is_empty():
		_panel_body.add_child(UI.label(tr("Your hero carries no spare gear. Gear they wear must be taken off first."), UI.SMALL_SIZE, UI.MUTED))
		return
	var price: Dictionary = Game.data.buildings.village.market.gearValue
	for item in spare:
		var line := UI.hbox(8)
		var name := UI.label(tr(Game.data.heroes.items.get(item, {}).get("name", item)))
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name)
		line.add_child(UI.button(tr("Sell"), func() -> void: _market_sell(village_id, item)))
		_panel_body.add_child(line)
	var worth := UI.rich()
	worth.text = tr("Each piece fetches %s") % UI.costs(price)
	_panel_body.add_child(worth)


## The Market's bounty board: every open bounty (yours to call off, others'
## to take from this village), and a new one put together in two steps.
func _bounty_board(village: Dictionary, level: int) -> void:
	var data := Game.data
	var village_id := int(village.id)
	var share := roundi(float(data.buildings.village.market.bounties.feeShare) * 100.0)
	var slots := Rules.bounty_slots(data, level)
	var most := Rules.bounty_most(data, level)
	var mine_here := Game.bounties.filter(func(b: Dictionary) -> bool: return int(b.villageId) == village_id)
	_panel_body.add_child(UI.with_info(UI.label(tr("Bounty board"), UI.HEADING_SIZE),
		tr("Offer resources, or gear from your hero's pack, for others; another player takes your bounty at once. What you offer, and a %d%% fee on the resources, leave your stores (and the pack) when you post it; when it is taken you get what you asked for, less %d%%. Called off, what you offered comes back; the fee does not.") % [share, share]))
	_panel_body.add_child(UI.label(tr("%d of %d open here · at most %d a side") % [mine_here.size(), slots, most], UI.SMALL_SIZE, UI.MUTED))
	for bounty in Game.bounties:
		var row := UI.hbox(8)
		var mine: bool = bounty.ownerAccountId != null and int(bounty.ownerAccountId) == Game.my_account_id()
		var words := UI.rich()
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var who := tr("Yours, from %s") % Game.village_name(int(bounty.villageId)) if mine else Game.village_name(int(bounty.villageId))
		words.text = tr("%s: offers %s for %s") % [who, _bounty_offer_text(bounty.offer, bounty.get("items", [])), UI.costs(_nonzero(bounty.want), 22)]
		row.add_child(words)
		var bounty_id := int(bounty.id)
		if mine:
			row.add_child(UI.button(tr("Call off"), func() -> void: _bounty_command("/v1/bounties/%d/cancel" % bounty_id, {})))
		else:
			var take := UI.button(tr("Take"), func() -> void: _bounty_command("/v1/bounties/%d/take" % bounty_id, {"villageId": village_id}))
			# Gear your hero already has can't be taken twice.
			var hero := Game.my_hero()
			var owned: Array = hero.get("inventory", []) + hero.get("gear", {}).values()
			var twice: bool = bounty.get("items", []).any(func(item: String) -> bool: return item in owned)
			take.disabled = twice or not Ledger.can_afford(Ledger.amounts_at(village.resources, Game.server_now()), bounty.want)
			if twice:
				take.tooltip_text = tr("Your hero has that gear already")
			row.add_child(take)
		_panel_body.add_child(row)
	if Game.bounties.is_empty():
		_panel_body.add_child(UI.label(tr("No bounties on the board."), UI.SMALL_SIZE, UI.MUTED))
	if mine_here.size() >= slots:
		return
	# A new bounty: first what you give, then what you want for it.
	var step := clampi(int(_bounty.step), 1, 3)
	var side: String = "offer" if step == 1 else "want"
	_panel_body.add_child(UI.label(tr("Post a bounty"), UI.HEADING_SIZE))
	_steps_row([tr("You give"), tr("You want"), tr("Confirm")], step, func(to: int) -> void:
		_bounty.step = to
		_rebuild_panel())
	for kind in Ledger.KINDS:
		# The last step only sums it up.
		if step == 3:
			continue
		# A resource you give can't also be one you want.
		if step == 2 and int(_bounty.offer[kind]) > 0:
			continue
		var row := UI.hbox(8)
		row.add_child(UI.icon("resource/%s" % kind, 36))
		var name := UI.label(UI.resource_name(kind), UI.SMALL_SIZE)
		name.custom_minimum_size.x = 90
		row.add_child(name)
		row.add_child(_number_field("bounty:%s:%s" % [side, kind], int(_bounty[side][kind]), 0, most, func(n: int) -> void: _bounty[side][kind] = n))
		_panel_body.add_child(row)
	# Gear from the hero's pack can be offered too (not what it wears).
	var pack: Array = Game.my_hero().get("inventory", [])
	if step == 1 and not pack.is_empty():
		_panel_body.add_child(UI.label(tr("Gear from your hero's pack"), UI.SMALL_SIZE, UI.MUTED))
		var counts := {}
		for item in pack:
			counts[item] = int(counts.get(item, 0)) + 1
		for item in counts:
			var def: Dictionary = data.heroes.items.get(item, {})
			var pick := CheckBox.new()
			pick.text = tr(String(def.get("name", item)))
			pick.add_theme_font_size_override("font_size", UI.SMALL_SIZE)
			pick.button_pressed = item in _bounty.items
			var chosen: String = item
			pick.toggled.connect(func(on: bool) -> void:
				if on and not chosen in _bounty.items:
					_bounty.items.append(chosen)
				elif not on:
					_bounty.items.erase(chosen)
				_rebuild_panel())
			_panel_body.add_child(UI.with_info(pick, HeroText.effects(def.get("effects", {}))))
	var total_line := UI.rich()
	_panel_body.add_child(total_line)
	var buttons := UI.hbox(8)
	if step > 1:
		buttons.add_child(UI.button(tr("Back"), func() -> void:
			_bounty.step = step - 1
			_rebuild_panel()))
	var go := UI.primary(tr("Next") if step < 3 else tr("Post bounty"), func() -> void:
		if step < 3:
			_bounty.step = step + 1
			_rebuild_panel()
		else:
			_post_bounty(village_id))
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(go)
	_panel_body.add_child(buttons)
	# The total payment (what you give and the fee), and what you get, as typed.
	_tick(total_line, func() -> String:
		var offer: Dictionary = _bounty.offer
		var want: Dictionary = _bounty.want
		var fee := Rules.bounty_fee(data, offer)
		var pay := {}
		for kind in Ledger.KINDS:
			pay[kind] = int(offer[kind]) + int(fee[kind])
		var home: Dictionary = Game.villages.get(village_id, village)
		var afford := Ledger.can_afford(Ledger.amounts_at(home.resources, Game.server_now()), pay)
		var gives := _sum(offer)
		var wants := _sum(want)
		var items: Array = _bounty.items
		var text := tr("You pay %s (%s and a %d%% fee)") % [UI.costs(_nonzero(pay), 22), UI.costs(_nonzero(offer), 22), share] if gives > 0 else (tr("Type what you give.") if items.is_empty() else "")
		if not items.is_empty():
			text += ("\n" if text != "" else "") + tr("Gear offered: %s") % _gear_names(items)
		if gives > 0 and not afford:
			text += "\n" + tr("Not enough in the stores to cover it.")
		if step >= 2:
			text += "\n" + (tr("You get %s when it is taken") % UI.costs(_nonzero(Rules.bounty_return(data, want)), 22) if wants > 0 else tr("Type what you want for it."))
			go.disabled = (gives == 0 and items.is_empty()) or wants == 0 or not afford or gives > most or wants > most
		else:
			go.disabled = (gives == 0 and items.is_empty()) or not afford or gives > most
		return text)


## What a bounty offers: its resources and its gear.
func _bounty_offer_text(offer: Dictionary, items: Array) -> String:
	var parts := PackedStringArray()
	if _sum(offer) > 0:
		parts.append(UI.costs(_nonzero(offer), 22))
	if not items.is_empty():
		parts.append(_gear_names(items))
	return tr(" and ").join(parts)


func _post_bounty(village_id: int) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/bounties" % village_id, {"offer": _bounty.offer.duplicate(), "want": _bounty.want.duplicate(), "items": _bounty.items.duplicate()})
	if not response.ok:
		_status.text = response.error
		Sound.effect("error")
		return
	Sound.effect("coins")
	_bounty = {"step": 1, "offer": {"wood": 0, "stone": 0, "grain": 0, "iron": 0}, "want": {"wood": 0, "stone": 0, "grain": 0, "iron": 0}, "items": []}
	_forget_drafts(["bounty:"])
	Game.note_server_time(response.data.serverTime)
	Game.update_village(response.data.village)
	_refetch_world()


func _bounty_command(path: String, body: Dictionary) -> void:
	_status.text = ""
	var response := await Api.post_json(path, body)
	if not response.ok:
		_status.text = response.error
		Sound.effect("error")
		return
	Sound.effect("coins")
	Game.note_server_time(response.data.serverTime)
	Game.update_village(response.data.village)
	_refetch_world()


func _market_trade(village_id: int) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/market/trade" % village_id, {"give": _trade.give, "get": _trade.get, "amount": int(_trade.amount)})
	if not response.ok:
		_status.text = response.error
		Sound.effect("error")
		return
	Sound.effect("coins")
	Game.note_server_time(response.data.serverTime)
	Game.update_village(response.data.village)


func _market_sell(village_id: int, item: String) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/market/sell" % village_id, {"item": item})
	if not response.ok:
		_status.text = response.error
		Sound.effect("error")
		return
	Sound.effect("coins")
	Game.note_server_time(response.data.serverTime)
	Game.update_village(response.data.village)


func _demolish_row(village: Dictionary, building: String, level: int) -> void:
	var def := _building_def(building)
	if level <= 0 or building == Rules.HALL or not def.get("kind") in ["center", "tower"]:
		return
	if village.queue.any(func(item: Dictionary) -> bool: return item.get("plot", "") == _plot):
		return
	var village_id := int(village.id)
	var plot := _plot
	var armed := _demolish_armed == "%d:%s" % [village_id, plot]
	var button := UI.button(tr("Sure? Tear it down") if armed else tr("Tear down"), func() -> void:
		if _demolish_armed != "%d:%s" % [village_id, plot]:
			_demolish_armed = "%d:%s" % [village_id, plot]
			_rebuild_panel()
			return
		_demolish_armed = ""
		_demolish(village_id, plot))
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_panel_body.add_child(button)
	if armed:
		var refund := Rules.refund(Game.data, building, level, float(Game.data.buildings.village.demolishRefund))
		var text := UI.rich()
		text.text = tr("Tap again to tear down the %s. You get back %s, as far as the stores hold it.") % [tr(def.name), UI.costs(refund)]
		_panel_body.add_child(text)


func _demolish(village_id: int, plot: String) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/demolish" % village_id, {"plot": plot})
	if not response.ok:
		_status.text = response.error
		Sound.effect("error")
		return
	Sound.effect("build")
	Game.note_server_time(response.data.serverTime)
	Game.update_village(response.data.village)


func _abandon_row(village: Dictionary) -> void:
	var village_id := int(village.id)
	if village.get("refuge", false) or Game.my_villages().size() < 2:
		return
	var armed := _abandon_armed == village_id
	var button := UI.button(tr("Sure? Abandon %s") % village.name if armed else tr("Abandon this village"), func() -> void:
		if _abandon_armed != village_id:
			_abandon_armed = village_id
			_rebuild_panel()
			return
		_abandon_armed = 0
		_abandon(village_id), "icon/quit")
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_panel_body.add_child(button)
	if armed:
		var refund := Rules.village_refund(Game.data, village, float(Game.data.buildings.village.abandonRefund))
		var text := UI.rich()
		text.text = tr("Tap again to give it up for good. %s of what was built goes to the Holy City vault; its troops and your hero there move to your nearest village; what it has stored is lost. It must be quiet: no builds, training, caravans or armies under way.") % UI.costs(refund)
		_panel_body.add_child(text)


func _abandon(village_id: int) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/abandon" % village_id)
	if not response.ok:
		_status.text = response.error
		Sound.effect("error")
		return
	Sound.effect("done")
	Game.set_world(response.data)
	var mine := Game.my_villages()
	if not mine.is_empty():
		Game.current_village_id = int(mine[0].id)
	_plot = Rules.HALL_PLOT
	_rebuild_panel()


## One "build `building` to `target` on `plot`" row with its cost, time
## and button.
func _build_row(village: Dictionary, plot: String, building: String, target: int, verb: String, note := "", named := true) -> void:
	var village_id := int(village.id)
	var def := _building_def(building)
	var hall := Rules.hall_level(village)
	var queue_full: bool = village.queue.size() >= Rules.queue_limit(Game.data, hall)
	var cost := Rules.level_cost(def, target)
	var seconds := Rules.build_seconds(def, target, float(Game.world.speed), Rules.hall_speedup(Game.data, hall) * ResearchRules.time_factor(village.get("bonuses", {}), "buildTime"))

	# The building's own sheet has its name on top: there the price stands
	# over one wide button. In a list, the name leads each row.
	var row: BoxContainer = UI.hbox() if named else UI.vbox(8)
	var info := UI.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if named:
		info.add_child(UI.with_card(UI.label(tr("%s → Lv %d") % [tr(def.name), target]), _building_card(village, building, target - 1)))
	if note != "":
		info.add_child(UI.label(note, UI.SMALL_SIZE, UI.MUTED))
	var cost_line := UI.rich()
	info.add_child(cost_line)
	row.add_child(info)
	var button := UI.primary(verb, func() -> void: _queue_build(village_id, plot, building))
	button.custom_minimum_size.x = 160
	row.add_child(button)
	_panel_body.add_child(row)
	var time := TimeUtil.format_duration(seconds)
	_tick(cost_line, func() -> String:
		var home: Dictionary = Game.villages.get(village_id, village)
		var have := Ledger.amounts_at(home.resources, Game.server_now())
		button.disabled = queue_full or not Ledger.can_afford(have, cost)
		return tr("%s · %s") % [UI.costs(cost, 30, have), time] + (tr("  (queue full)") if queue_full else ""))


## What a building does at its level, and at the next one.
func _effect_text(village: Dictionary, building: String, level: int) -> String:
	var def := _building_def(building)
	var speed := float(Game.world.speed)
	if def.has("production"):
		var resource: String = def.production.resource
		return tr("%s +%d/h → +%d/h") % [UI.resource_name(resource),
			roundi(TimeUtil.per_real_hour(Rules.field_production(def, level, speed))), roundi(TimeUtil.per_real_hour(Rules.field_production(def, level + 1, speed)))]
	if building == "heroes_hall":
		var text := GeneralText.hall_gives(Game.data, level)
		return text.left(1).to_upper() + text.substr(1) + (tr("; level %d: %s") % [level + 1, GeneralText.hall_gives(Game.data, level + 1)] if level < int(def.maxLevel) else "")
	if building == Rules.HALL:
		var total := int(Game.data.buildings.village.centerSlots)
		var text := tr("Slots %d/%d · queue %d") % [Rules.unlocked_slots(Game.data, level), total, Rules.queue_limit(Game.data, level)]
		if level < int(def.maxLevel):
			text += "\n" + tr("Lv %d: slots %d · queue %d · builds %d%% faster") % [level + 1,
				Rules.unlocked_slots(Game.data, level + 1), Rules.queue_limit(Game.data, level + 1),
				roundi((1.0 - Rules.hall_speedup(Game.data, level + 1)) * 100.0)]
		return text
	if def.get("kind") == "wall":
		return WallText.wall_effect(Game.data, level)
	if def.get("kind") == "tower":
		return WallText.tower_effect(Game.data, building, level, float(Game.world.speed))
	if def.has("capacityGrowth"):
		var base := float(Game.data.buildings.village.baseCapacity)
		var total := roundi(float(village.get("resources", {}).get("capacity", {}).get("wood", base)))
		return tr("Holds %d of each resource above the base; the village keeps %d in all") % [roundi(base * (pow(float(def.capacityGrowth), level) - 1.0)), total]
	if def.has("grainCapacityGrowth"):
		var base_grain := float(Game.data.buildings.village.baseCapacity)
		var grain_total := roundi(float(village.get("resources", {}).get("capacity", {}).get("grain", base_grain)))
		return tr("Holds %d grain above the base; the village keeps %d grain in all") % [roundi(base_grain * (pow(float(def.grainCapacityGrowth), level) - 1.0)), grain_total]
	if def.has("research"):
		var research: Dictionary = def.research
		var per_hour := func(l: int) -> int: return roundi(TimeUtil.per_real_hour(float(research.basePerHour) * pow(float(research.growth), l - 1) * speed)) if l > 0 else 0
		return tr("Research +%d/h now, +%d/h at level %d") % [per_hour.call(level), per_hour.call(level + 1), level + 1]
	if building == "market":
		return tr("Trades at %d%% now, %d%% at level %d") % [roundi(Rules.market_rate(Game.data, level) * 100.0), roundi(Rules.market_rate(Game.data, level + 1) * 100.0), level + 1]
	var effects: Dictionary = def.get("effects", {}) if def.get("effects") != null else {}
	if effects.has("hospital"):
		return tr("%d%% of the garrison's fallen get up again when it holds the village") % roundi(float(effects.hospital) * level * 100.0)
	for key in effects:
		if String(key).begins_with("production."):
			var kind := String(key).trim_prefix("production.")
			return tr("%s +%d%% now, +%d%% at level %d") % [UI.resource_name(kind), roundi(float(effects[key]) * level * 100.0), roundi(float(effects[key]) * (level + 1) * 100.0), level + 1]
	return ""


func _queue_build(village_id: int, plot: String, building: String) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/build" % village_id, {"plot": plot, "building": building})
	if not response.ok:
		_status.text = response.error
		Sound.effect("error")
		return
	Sound.effect("build")
	_toast(tr("%s queued") % tr(_building_def(building).name) if building != "" else tr("Queued"))
	Game.note_server_time(response.data.serverTime)
	Game.update_village(response.data.village)
