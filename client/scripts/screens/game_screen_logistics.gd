extends "res://scripts/screens/game_screen_army.gd"
## The in-world screen, logistics: caravans and standing orders.

## Opens your village's caravan tab, headed for `target` (see
## _caravan_target); from `village_id` when given.
func _open_caravans(target: Dictionary, village_id := 0) -> void:
	_caravan_target = target
	_caravan_step = 2
	if village_id != 0:
		Game.current_village_id = village_id
	_tab = "caravans"
	_side["caravans"] = "load"
	_set_view("village")


func _caravans_section(village: Dictionary) -> void:
	var village_id := int(village.id)
	var tabs := [["load", "icon/caravan", tr("Send a caravan"), _caravan_load_tab.bind(village)]]
	if int(village.levels.get("caravan_yard", 0)) >= 1 and not Game.camps.is_empty():
		tabs.append(["escort", "unit/spearman", tr("Escort"), _caravan_escort.bind(village)])
	tabs.append(["road", "icon/map", tr("On the road"), _caravan_trips.bind(village_id)])
	_side_tabs("caravans", tabs, VILLAGE_TOP)


func _caravan_load_tab(village: Dictionary) -> void:
	var yard := int(village.levels.get("caravan_yard", 0))
	var capacity := CaravanMath.capacity(Game.data, village.get("bonuses", {}))
	if yard < 1:
		_panel_body.add_child(UI.with_info(UI.label(tr("Needs a Caravan Yard"), UI.SMALL_SIZE, UI.MUTED), tr("Build a Caravan Yard in the village to send caravans to allies and the Holy City vault.")))
		return
	var free := CaravanMath.available(Game.data, village, Game.caravans)
	var total := yard * int(Game.data.logistics.caravan.caravansPerYardLevel)
	_panel_body.add_child(UI.label(tr("%d of %d caravans at home · %d each") % [free, total, capacity], UI.SMALL_SIZE, UI.MUTED))
	_caravan_form(village, free)


## Troops to see a caravan past the camps; the load tab sends them along.
func _caravan_escort(village: Dictionary) -> void:
	_panel_body.add_child(UI.with_info(UI.label(tr("Escort (optional)"), UI.HEADING_SIZE), tr("Camps ambush caravans passing close. An escort beats them off.")))
	_unit_pickers(Rules.garrison_at(village, Game.server_now()), false, "escort")


func _caravan_form(village: Dictionary, free: int) -> void:
	var village_id := int(village.id)
	# Where it goes, picked on the map; a place that is gone (or a boat
	# paid for) falls back to the vault.
	if _caravan_limits(_caravan_target).is_empty():
		_caravan_target = {"kind": "vault"}
	if _caravan_target.get("kind") == "village" and int(_caravan_target.id) == village_id:
		_caravan_target = {"kind": "vault"}
	_caravan_step = clampi(_caravan_step, 1, 3)
	var to_step := func(step: int) -> void:
		_caravan_step = step
		_scroll.scroll_vertical = 0
		_rebuild_panel()
	_steps_row([tr("Where"), tr("What"), tr("Confirm")], _caravan_step, to_step)
	var limits := _caravan_limits(_caravan_target)
	var own_place := _caravan_own_place(_caravan_target)
	for kind in Ledger.KINDS:
		if not limits.has(kind):
			_caravan_load[kind] = 0
		if own_place.is_empty() or not limits.has(kind):
			_caravan_back[kind] = 0
	if _caravan_step == 1:
		_caravan_where(village_id, to_step)
	elif _caravan_step == 2:
		_caravan_what(village, limits, own_place, free, to_step)
	else:
		_caravan_confirm(village, free, to_step)


## Step 1: where it goes.
func _caravan_where(village_id: int, to_step: Callable) -> void:
	_panel_body.add_child(UI.label(tr("To %s") % CaravanText.target_name(_caravan_target)))
	var row := UI.hbox(8)
	var pick := UI.button(tr("Pick on the map"), func() -> void: _pick_caravan_target(village_id), "icon/map")
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(pick)
	if _caravan_target.get("kind") != "vault":
		row.add_child(UI.button(tr("Holy City vault"), func() -> void:
			_caravan_target = {"kind": "vault"}
			_rebuild_panel()))
	_panel_body.add_child(row)
	var next := UI.primary(tr("Next"), func() -> void: to_step.call(2))
	_panel_body.add_child(next)


## Step 2: what it carries there, and what it brings back.
func _caravan_what(village: Dictionary, limits: Dictionary, own_place: Dictionary, free: int, to_step: Callable) -> void:
	var village_id := int(village.id)
	# How much of each: typed in, up to what the village holds and what the
	# place takes (a store only grain, a boat what it still needs).
	var amounts := Ledger.amounts_at(village.resources, Game.server_now())
	for kind in Ledger.KINDS:
		if not limits.has(kind):
			continue
		var row := UI.hbox(8)
		row.add_child(UI.icon("resource/%s" % kind, 40))
		var most := int(floor(float(amounts.get(kind, 0))))
		if limits[kind] != null:
			most = mini(most, int(limits[kind]))
		row.add_child(_number_field("load:%s" % kind, mini(_caravan_load[kind], most), 0, maxi(most, _caravan_load[kind]), func(n: int) -> void:
			_caravan_load[kind] = n))
		var of := UI.label(tr("of %d") % most, UI.SMALL_SIZE, UI.MUTED)
		of.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(of)
		var all := UI.button(tr("All"), func() -> void:
			_caravan_load[kind] = most
			_drafts.erase("load:%s" % kind)
			_rebuild_panel())
		all.focus_mode = Control.FOCUS_NONE
		row.add_child(all)
		_panel_body.add_child(row)
	if limits.has("grain") and limits.size() == 1:
		_panel_body.add_child(UI.label(tr("A store takes only grain."), UI.SMALL_SIZE, UI.MUTED))
	# From your own settlement, fort or supply point it can bring back.
	if not own_place.is_empty():
		_panel_body.add_child(UI.with_info(UI.label(tr("Bring back"), UI.HEADING_SIZE),
			tr("On the way home it takes these from %s, as much as there is when it gets there.") % CaravanText.target_name(_caravan_target)))
		for kind in Ledger.KINDS:
			if not limits.has(kind):
				continue
			var row := UI.hbox(8)
			row.add_child(UI.icon("resource/%s" % kind, 40))
			var there := floori(float(own_place.get(kind, 0)))
			var top := maxi(there, _caravan_back[kind])
			row.add_child(_number_field("back:%s" % kind, _caravan_back[kind], 0, maxi(top, 1000000), func(n: int) -> void: _caravan_back[kind] = n))
			var have := UI.label(tr("%d there") % there, UI.SMALL_SIZE, UI.MUTED)
			have.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(have)
			_panel_body.add_child(row)
	var summary := UI.label("", UI.SMALL_SIZE, UI.MUTED)
	_panel_body.add_child(summary)
	var buttons := UI.hbox(8)
	buttons.add_child(UI.button(tr("Back"), func() -> void: to_step.call(1)))
	var next := UI.primary(tr("Next"), func() -> void: to_step.call(3))
	next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(next)
	_panel_body.add_child(buttons)
	_tick(summary, func() -> String:
		var needed := _caravans_needed(village)
		next.disabled = needed == 0
		var line := tr_n("Needs %d caravan", "Needs %d caravans", needed) % needed if needed > 0 else tr("Type how much of each to carry")
		if needed > free:
			line += tr(" (only %d at home)") % free
		return line)


## How many caravans the load (or what it brings back) takes.
func _caravans_needed(village: Dictionary) -> int:
	return maxi(CaravanMath.needed(Game.data, _caravan_load, village.get("bonuses", {})), CaravanMath.needed(Game.data, _caravan_back, village.get("bonuses", {})))


## Step 3: the whole trip on one card, and Send.
func _caravan_confirm(village: Dictionary, free: int, to_step: Callable) -> void:
	var village_id := int(village.id)
	var garrison := Rules.garrison_at(village, Game.server_now())
	var escort := func() -> Dictionary: return _picked_units(garrison) if not Game.camps.is_empty() else {}
	var card := UI.card(12)
	var box := UI.vbox(6)
	card.add_child(box)
	box.add_child(UI.label(tr("To %s") % CaravanText.target_name(_caravan_target)))
	var carries := UI.rich("", UI.SMALL_SIZE, UiTheme.INK)
	carries.text = tr("Carries %s") % UI.costs(_nonzero(_caravan_load), 26) if _sum(_caravan_load) > 0 else tr("Carries nothing there")
	box.add_child(carries)
	if _sum(_caravan_back) > 0:
		var back := UI.rich("", UI.SMALL_SIZE, UiTheme.INK)
		back.text = tr("Brings back %s") % UI.costs(_nonzero(_caravan_back), 26)
		box.add_child(back)
	var guard: Dictionary = escort.call()
	if not guard.is_empty():
		box.add_child(UI.label(tr("Escort"), UI.SMALL_SIZE, UI.MUTED))
		box.add_child(_unit_chips(guard, 34.0))
	var summary := UI.label("", UI.SMALL_SIZE, UI.MUTED)
	box.add_child(summary)
	_panel_body.add_child(card)
	var buttons := UI.hbox(8)
	buttons.add_child(UI.button(tr("Back"), func() -> void: to_step.call(2)))
	var target := _caravan_target.duplicate()
	var send := UI.primary(tr("Send"), func() -> void: _send_caravan(village_id, target, _caravan_load.duplicate(), escort.call(), _caravan_back.duplicate()), "icon/caravan")
	send.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(send)
	_panel_body.add_child(buttons)
	var fetch: Button = null
	if _caravan_target.kind == "vault":
		fetch = UI.button(tr("Fetch from vault"), func() -> void: _fetch_from_vault(village_id, _caravan_load.duplicate(), escort.call()))
		_panel_body.add_child(UI.with_info(fetch, tr("Brings this much from the Holy City vault home instead of taking it there.")))
	# Whether it can go, as the stores and the yard stand.
	_tick(summary, func() -> String:
		var needed := _caravans_needed(village)
		var current: Dictionary = Game.villages.get(village_id, village)
		var affordable := Ledger.can_afford(Ledger.amounts_at(current.resources, Game.server_now()), _caravan_load)
		send.disabled = needed == 0 or needed > free or not affordable
		if fetch != null:
			fetch.disabled = CaravanMath.needed(Game.data, _caravan_load, village.get("bonuses", {})) == 0 or needed > free
		var line := tr_n("Needs %d caravan", "Needs %d caravans", needed) % needed if needed > 0 else tr("Nothing to carry")
		if needed > free:
			line += tr(" (only %d at home)") % free
		if not affordable:
			line += " · " + tr("Not enough in the stores to cover it.")
		return line)


## What a caravan's destination holds, when it is your own settlement, fort
## or supply point (it can bring back from there): {} otherwise.
func _caravan_own_place(target: Dictionary) -> Dictionary:
	match String(target.get("kind", "")):
		"village":
			var v: Dictionary = Game.villages.get(int(target.id), {})
			if v.is_empty() or not Game.is_mine(v):
				return {}
			return Ledger.amounts_at(v.resources, Game.server_now())
		"fort":
			var fort := Game.fort_at_id(int(target.id))
			if fort.is_empty() or fort.get("status") != "standing" or fort.get("ownerAccountId") == null or int(fort.ownerAccountId) != Game.my_account_id():
				return {}
			return {"grain": float(fort.get("grain", 0))}
	return {}


## Trips from this village, and deliveries on their way to it.
func _caravan_trips(village_id: int) -> void:
	var trips := Game.caravans.filter(func(c: Dictionary) -> bool:
		return int(c.villageId) == village_id or (c.destinationVillageId != null and int(c.destinationVillageId) == village_id))
	_panel_body.add_child(UI.label(tr("On the road"), UI.HEADING_SIZE))
	if trips.is_empty():
		_panel_body.add_child(UI.label(tr("No caravans on the road."), UI.SMALL_SIZE, UI.MUTED))
	_paged("caravans", trips, 6 if _roomy() else 4, func(caravan: Dictionary) -> void:
		var line := UI.label("", UI.SMALL_SIZE)
		_panel_body.add_child(line)
		_tick(line, func() -> String: return CaravanText.describe(caravan, village_id, Game.server_now()))
		var ambushed := HordeText.ambush(caravan.get("ambush"))
		if ambushed != "":
			_panel_body.add_child(UI.label(ambushed, UI.SMALL_SIZE, UI.ERROR))
		_caravan_turns(caravan, village_id))


## For a caravan of this village on its way out: turn it back, or (one
## carrying goods, not on a supply route) send it somewhere else; it
## finishes the hex it is crossing first.
func _caravan_turns(caravan: Dictionary, village_id: int) -> void:
	if int(caravan.villageId) != village_id or caravan.status != "outbound":
		return
	var caravan_id := int(caravan.id)
	var row := UI.hbox(8)
	row.add_child(UI.button(tr("Turn back"), func() -> void: _reroute_caravan(caravan_id, {"home": true})))
	if caravan.kind == "deliver" and caravan.get("destinationFortId") == null:
		var targets: Array = [null]
		var labels := [tr("Send to…")]
		if caravan.destinationVillageId != null:
			labels.append(tr("Holy City vault"))
			targets.append(0)
		for v in Game.villages.values():
			if int(v.id) != village_id and (caravan.destinationVillageId == null or int(v.id) != int(caravan.destinationVillageId)):
				labels.append(String(v.name))
				targets.append(int(v.id))
		if targets.size() > 1:
			var to := UI.options(labels, 0)
			to.item_selected.connect(func(i: int) -> void:
				if i > 0:
					_reroute_caravan(caravan_id, {"villageId": targets[i] if int(targets[i]) != 0 else null}))
			row.add_child(to)
	_panel_body.add_child(row)


func _reroute_caravan(caravan_id: int, body: Dictionary) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/caravans/%d/reroute" % caravan_id, body)
	if not response.ok:
		_status.text = response.error
		Sound.effect("error")
		return
	_refetch_world()


## Where a caravan from `from_village_id` goes when `cell` is tapped: the
## vault (the Holy City), an open shipyard, a standing fort or supply point,
## or a village (an outpost's village); {} for anywhere else.
func _caravan_target_at(cell: Vector2i, from_village_id: int) -> Dictionary:
	if Game.terrain.get(cell) == "holy_city":
		return {"kind": "vault"}
	var yard := Game.shipyard_at(cell)
	if not yard.is_empty() and yard.status == "open":
		return {"kind": "shipyard", "id": int(yard.id)}
	for fort in Game.forts:
		if Vector2i(int(fort.q), int(fort.r)) == cell and fort.get("status") == "standing":
			return {"kind": "fort", "id": int(fort.id)}
	var village := Game.village_at(cell)
	if village.is_empty():
		village = Game.outpost_owner(cell)
	if not village.is_empty() and village.get("ruin") == null and int(village.id) != from_village_id:
		return {"kind": "village", "id": int(village.id)}
	return {}


## What a caravan to `target` may carry: {resource: most it takes, or null
## for no limit}; {} when the place is gone (or its boat is paid for).
func _caravan_limits(target: Dictionary) -> Dictionary:
	match String(target.get("kind", "")):
		"vault":
			return {"wood": null, "stone": null, "grain": null, "iron": null}
		"village":
			var village: Dictionary = Game.villages.get(int(target.id), {})
			return {} if village.is_empty() or village.get("ruin") != null else {"wood": null, "stone": null, "grain": null, "iron": null}
		"fort":
			var fort := Game.fort_at_id(int(target.id))
			return {} if fort.is_empty() or fort.get("status") != "standing" else {"grain": null}
		"shipyard":
			for yard in Game.shipyards:
				if int(yard.id) == int(target.id) and yard.status == "open":
					var need := {}
					for kind in Ledger.KINDS:
						var left := int(yard.cost[kind]) - int(yard.paid[kind])
						if left > 0:
							need[kind] = left
					return need
	return {}


## The map waits for where the caravan from `village_id` goes.
func _pick_caravan_target(village_id: int) -> void:
	_set_view("map")
	_caravan_picking = village_id
	_caravan_pick_mode = _panel_mode
	_rebuild_panel()


func _send_caravan(village_id: int, target: Dictionary, cargo: Dictionary, escort: Dictionary, back := {}) -> void:
	_status.text = ""
	var body := {"destinationVillageId": int(target.id) if target.kind == "village" else null, "load": cargo, "escort": escort}
	var brings := 0
	for kind in back:
		brings += int(back[kind])
	if brings > 0:
		body.retrieve = back
	if target.kind == "fort":
		body.destinationFortId = int(target.id)
	elif target.kind == "shipyard":
		body.destinationShipyardId = int(target.id)
	var response := await Api.post_json("/v1/villages/%d/caravans" % village_id, body)
	if not response.ok:
		_status.text = response.error
		Sound.effect("error")
		return
	Sound.effect("coins")
	_toast(tr("The caravan is on its way"))
	_caravan_step = 1
	_caravan_load = {"wood": 0, "stone": 0, "grain": 0, "iron": 0}
	_caravan_back = {"wood": 0, "stone": 0, "grain": 0, "iron": 0}
	_army_units.clear()
	_forget_drafts(["load:", "escort:", "back:"])
	Game.note_server_time(response.data.serverTime)
	_sync_after_command()
	Game.update_village(response.data.village)
	if response.data.get("caravan") is Dictionary:
		Game.put_caravan(response.data.caravan)


func _fetch_from_vault(village_id: int, cargo: Dictionary, escort: Dictionary) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/caravans/fetch" % village_id, {"load": cargo, "escort": escort})
	if not response.ok:
		_status.text = response.error
		return
	_caravan_load = {"wood": 0, "stone": 0, "grain": 0, "iron": 0}
	_forget_drafts(["load:", "escort:"])
	Game.note_server_time(response.data.serverTime)
	Game.update_village(response.data.village)
	if response.data.get("caravan") is Dictionary:
		Game.put_caravan(response.data.caravan)


## One standing order: what it does, what it last did, and a cancel button.
func _order_row(order: Dictionary) -> void:
	var row := UI.hbox()
	var info := UI.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(UI.label(OrderText.describe(order, Game.data.units.units, Game.forts), UI.SMALL_SIZE))
	if order.lastResult != null:
		info.add_child(UI.label(tr("Last: %s") % order.lastResult, UI.SMALL_SIZE, UI.MUTED))
	row.add_child(info)
	var village_id := int(order.villageId)
	var order_id := int(order.id)
	var cancel := UI.button(tr("Stop"), func() -> void: _cancel_order(village_id, order_id))
	cancel.custom_minimum_size.x = 110
	row.add_child(cancel)
	_panel_body.add_child(row)


## Every standing order of yours, village by village, with a way to stop
## each; "Create order" opens the form for a new one.
func _orders_panel() -> void:
	var top := UI.hbox()
	var title := UI.label(tr("Standing orders"), UI.HEADING_SIZE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	if not _order_creating:
		top.add_child(UI.primary(tr("Create order"), func() -> void:
			_order_creating = true
			_rebuild_panel()))
	_panel_body.add_child(top)
	_panel_body.add_child(UI.with_info(UI.label(tr("Orders run on their own"), UI.SMALL_SIZE, UI.MUTED), tr("They run on their own, checked every %s: repeat training, rebuilding raided outposts, surplus to the vault and supply routes.") % TimeUtil.format_duration(float(Game.data.orders.checkMinutes) * 60.0 / float(Game.world.speed))))
	var villages := Game.my_villages().filter(func(v: Dictionary) -> bool: return v.get("ruin") == null)
	if villages.is_empty():
		_panel_body.add_child(UI.label(tr("You have no village to give orders from."), UI.SMALL_SIZE, UI.MUTED))
		return
	if _order_creating:
		_order_form(villages)
		return
	for village in villages:
		_panel_body.add_child(UI.label(String(village.name), UI.SMALL_SIZE + 4))
		_orders_count(village)
		var mine := Game.orders.filter(func(o: Dictionary) -> bool: return int(o.villageId) == int(village.id))
		if mine.is_empty():
			_panel_body.add_child(UI.label(tr("No standing orders."), UI.SMALL_SIZE, UI.MUTED))
		for order in mine:
			_order_row(order)


## A new standing order: from which village, of what kind, and its details.
func _order_form(villages: Array) -> void:
	var ids := villages.map(func(v: Dictionary) -> int: return int(v.id))
	if not _order_village in ids:
		_order_village = int(Game.current_village().get("id", ids[0])) if int(Game.current_village().get("id", 0)) in ids else ids[0]
	if villages.size() > 1:
		var from := UI.options(villages.map(func(v: Dictionary) -> String: return tr("From %s") % v.name), ids.find(_order_village))
		from.item_selected.connect(func(i: int) -> void:
			_order_village = ids[i]
			_rebuild_panel())
		_panel_body.add_child(from)
	var village: Dictionary = Game.villages.get(_order_village, villages[0])
	var kinds := ["train", "rebuild", "surplus", "supply"]
	var names := [tr("Repeat training"), tr("Rebuild raided outposts"), tr("Surplus to the vault"), tr("Supply route")]
	var kind := UI.options(names, maxi(0, kinds.find(_order_kind)))
	kind.item_selected.connect(func(i: int) -> void:
		_order_kind = kinds[i]
		_rebuild_panel())
	_panel_body.add_child(kind)
	_orders_count(village)
	match _order_kind:
		"train":
			_train_order_form(village)
		"rebuild":
			_rebuild_order_form(int(village.id))
		"surplus":
			_surplus_order_form(int(village.id))
		"supply":
			_supply_order_form(int(village.id))
	_panel_body.add_child(UI.button(tr("Cancel"), func() -> void:
		_order_creating = false
		_rebuild_panel()))


## Repeat training: one order per unit, keeping a target count.
func _train_order_form(village: Dictionary) -> void:
	var village_id := int(village.id)
	_panel_body.add_child(UI.label(tr("Keeps a unit topped up: when fewer are ready, it trains more."), UI.SMALL_SIZE, UI.MUTED))
	var units: Dictionary = Game.data.units.units
	var names := units.keys()
	var picker := UI.options(names.map(func(u: String) -> String: return tr(units[u].name)), maxi(0, names.find(_repeat_unit)))
	picker.item_selected.connect(func(i: int) -> void:
		_repeat_unit = names[i]
		_rebuild_panel())
	_panel_body.add_child(picker)
	# How many to keep, and how many to train at a time: typed in, a row each.
	_panel_body.add_child(_number_row(tr("Keep"), _number_field("repeat:target", _repeat_target, 1, 999, func(n: int) -> void: _repeat_target = n), tr("ready")))
	_panel_body.add_child(_number_row(tr("Train"), _number_field("repeat:batch", _repeat_batch, 1, int(Game.data.units.maxBatch), func(n: int) -> void: _repeat_batch = n), tr("at a time")))
	var unit := _repeat_unit
	var place := UI.primary(tr("Keep %s topped up") % tr(units[unit].name), func() -> void:
		_place_order(village_id, {"kind": "train", "unit": unit, "batch": mini(_repeat_batch, _repeat_target), "target": _repeat_target}))
	place.disabled = not Game.orders_of(village_id, "train").filter(func(o: Dictionary) -> bool: return o.unit == unit).is_empty()
	_panel_body.add_child(place)


## How many standing orders the village keeps, of how many its Hall allows.
func _orders_count(village: Dictionary) -> void:
	var have := Game.orders.filter(func(o: Dictionary) -> bool: return int(o.villageId) == int(village.id)).size()
	var most := Rules.orders_limit(Game.data, Rules.hall_level(village))
	_panel_body.add_child(UI.label(tr("Orders %d/%d · +1 every %d Hall levels") % [have, most, int(Game.data.orders.hallLevelsPerOrder)], UI.SMALL_SIZE, UI.ERROR if have >= most else UI.MUTED))


func _rebuild_order_form(village_id: int) -> void:
	_panel_body.add_child(UI.label(tr("Rebuilds the village's raided outposts to the best level they had."), UI.SMALL_SIZE, UI.MUTED))
	if not Game.orders_of(village_id, "rebuild").is_empty():
		_panel_body.add_child(UI.label(tr("This village already does."), UI.SMALL_SIZE, UI.GOOD))
		return
	_panel_body.add_child(UI.primary(tr("Rebuild raided outposts automatically"), func() -> void: _place_order(village_id, {"kind": "rebuild"})))


func _surplus_order_form(village_id: int) -> void:
	_panel_body.add_child(UI.label(tr("Caravans take what is above this share of storage to the Holy City vault."), UI.SMALL_SIZE, UI.MUTED))
	if not Game.orders_of(village_id, "surplus").is_empty():
		_panel_body.add_child(UI.label(tr("This village already does."), UI.SMALL_SIZE, UI.GOOD))
		return
	var limits: Dictionary = Game.data.orders.surplusShare
	var row := UI.hbox(8)
	row.add_child(UI.label(tr("Above"), UI.SMALL_SIZE))
	row.add_child(_number_field("surplus", _surplus_share, roundi(float(limits.min) * 100.0), roundi(float(limits.max) * 100.0), func(n: int) -> void:
		_surplus_share = n))
	var text := UI.label(tr("% of storage"), UI.SMALL_SIZE)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	_panel_body.add_child(row)
	_panel_body.add_child(UI.primary(tr("Start"), func() -> void: _place_order(village_id, {"kind": "surplus", "share": _surplus_share / 100.0})))


## Supply routes: keep one of your forts or supply points stocked with
## grain from this village, by caravan.
func _supply_order_form(village_id: int) -> void:
	_panel_body.add_child(UI.with_info(UI.label(tr("Keeps a fort or supply point fed"), UI.SMALL_SIZE, UI.MUTED), tr("Caravans from this village keep a fort or supply point of yours filled with grain up to the amount you set, whenever at least %d is missing.") % int(Game.data.orders.supplyMinLoad)))
	var stores: Array = Game.forts.filter(func(f: Dictionary) -> bool:
		return f.ownerAccountId != null and int(f.ownerAccountId) == Game.my_account_id())
	if stores.is_empty():
		_panel_body.add_child(UI.label(tr("Build a fort or a supply point on the map first."), UI.SMALL_SIZE, UI.MUTED))
		return
	var ids: Array = stores.map(func(f: Dictionary) -> int: return int(f.id))
	if not _supply_fort in ids:
		_supply_fort = ids[0]
	var labels: Array = stores.map(func(f: Dictionary) -> String:
		return (tr("Supply point at (%d, %d)") if f.get("kind", "fort") == "supply" else tr("Fort at (%d, %d)")) % [int(f.q), int(f.r)])
	var picker := UI.options(labels, ids.find(_supply_fort))
	picker.item_selected.connect(func(i: int) -> void:
		_supply_fort = ids[i]
		_rebuild_panel())
	_panel_body.add_child(picker)
	var most := maxi(int(Game.data.field.fort.grainCapacity), int(Game.data.field.supplyPoint.grainCapacity))
	var row := UI.hbox(8)
	row.add_child(UI.label(tr("Keep"), UI.SMALL_SIZE))
	row.add_child(_number_field("supply", _supply_target, int(Game.data.orders.supplyMinLoad), most, func(n: int) -> void: _supply_target = n))
	var text := UI.label(tr("grain there"), UI.SMALL_SIZE)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	_panel_body.add_child(row)
	var fort_id := _supply_fort
	var place := UI.primary(tr("Start"), func() -> void: _place_order(village_id, {"kind": "supply", "fortId": fort_id, "target": _supply_target}))
	place.disabled = Game.orders_of(village_id, "supply").any(func(o: Dictionary) -> bool: return int(o.fortId) == fort_id)
	_panel_body.add_child(place)


func _place_order(village_id: int, spec: Dictionary) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/orders" % village_id, spec)
	if not response.ok:
		_status.text = response.error
		return
	# Placed: back to the list, where it now stands.
	_order_creating = false
	Game.note_server_time(response.data.serverTime)
	Game.update_village(response.data.village)


func _cancel_order(village_id: int, order_id: int) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/orders/%d/cancel" % [village_id, order_id], {})
	if not response.ok:
		_status.text = response.error
		return
	_sync_after_command()
