extends "res://scripts/screens/game_screen_threats.gd"
## The in-world screen, what it tells you: the More sheet, the tutorial and
## almanac, popups, the inbox and the chat.

## The one thing most worth doing now, from how things stand: [what, where
## it is done] ([] when nothing stands out).
func _next_step() -> Array:
	var now := Game.server_now()
	for village in Game.my_villages():
		if village.get("ruin") is Dictionary:
			continue
		var id := int(village.id)
		var open := func(tab: String) -> void:
			Game.current_village_id = id
			_tab = tab
			_set_view("village")
			_tab = tab
			_rebuild_panel()
		if village.queue.is_empty():
			return [tr("%s builds nothing") % village.name, open.bind("village")]
		var amounts := Ledger.amounts_at(village.resources, now)
		for kind in Ledger.KINDS:
			var capacity := float(village.resources.capacity[kind])
			if capacity > 0.0 and float(amounts[kind]) >= capacity * 0.97:
				return [tr("%s: the %s store is full") % [village.name, UI.resource_name(kind).to_lower()], open.bind("village")]
		if village.training.is_empty() and int(village.levels.get("barracks", 0)) > 0:
			return [tr("%s trains nobody") % village.name, open.bind("troops")]
	var hero := Game.my_hero()
	if not hero.is_empty() and int(hero.get("skillPoints", 0)) > 0:
		return [tr("Your hero has a skill point to spend"), func() -> void:
			_panel_mode = "hero"
			_rebuild_panel()]
	return []


## Everything the bar has no room for.
func _more_panel() -> void:
	_panel_body.add_child(UI.label(String(Game.world.get("name", "")), UI.HEADING_SIZE))
	var hint := _next_step()
	if not hint.is_empty():
		var card := UI.card(10)
		var row := UI.hbox(10)
		card.add_child(row)
		var words := UI.vbox(0)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.add_child(UI.label(tr("What next?"), UI.SMALL_SIZE, UI.MUTED))
		words.add_child(UI.label(String(hint[0])))
		row.add_child(words)
		var go := UI.primary(tr("Go"), hint[1])
		go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(go)
		_panel_body.add_child(card)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	var places := [
		[tr("Research"), "icon/research", func() -> void:
			_tab = "research"
			_set_view("village")
			_tab = "research"
			_rebuild_panel()],
		[tr("Caravans"), "icon/caravan", func() -> void:
			_tab = "caravans"
			_set_view("village")
			_tab = "caravans"
			_rebuild_panel()],
		[tr("Standing orders"), "icon/clock", func() -> void:
			_panel_mode = "orders"
			_order_creating = false
			_rebuild_panel()],
		[tr("Threats"), "icon/threat", _show_threats],
		[tr("Almanac"), "icon/help", func() -> void:
			_panel_mode = "almanac"
			_rebuild_panel()],
		[tr("Tutorial"), "icon/info", _toggle_tutorial],
		[tr("Report a bug"), "icon/chat", _report_bug],
		[tr("Worlds"), "icon/back", _leave],
	]
	for place in places:
		if _my_village().is_empty() and place[1] in ["icon/research", "icon/caravan"]:
			continue
		var b := UI.button(String(place[0]), place[2], String(place[1]))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		grid.add_child(b)
	_panel_body.add_child(grid)


func _refresh_quest_card() -> void:
	if _quest_card == null:
		return
	var running: bool = Game.world.get("status") == "running"
	if not running or Game.data.is_empty() or Session.tutorial_flag(Game.world_id(), "hidden") or _my_village().is_empty():
		_quest_card.visible = false
		return
	_quest_card.show_for(Game.data, _me())
	_place_quest_card.call_deferred()


## The ? button: brings the tutorial back, or puts it away.
func _toggle_tutorial() -> void:
	# Once the getting-started chain is over, the ? opens the almanac.
	if not _me().is_empty() and OnboardingText.current(Game.data, _me()).is_empty():
		_panel_mode = "almanac"
		_rebuild_panel()
		return
	var hidden := Session.tutorial_flag(Game.world_id(), "hidden") or not _quest_card.visible
	Session.set_tutorial_flag(Game.world_id(), "hidden", not hidden)
	_status.text = ""
	_refresh_quest_card()
	if hidden and not _quest_card.visible:
		_status.text = tr("The tutorial is for a running world with a village of your own.")


## At the top left of the map (or the village), narrower on a phone; the
## compass at the map's bottom right.
func _place_quest_card() -> void:
	if _quest_card == null or _main == null:
		return
	if _compass != null:
		var corner := _main.get_global_rect()
		_compass.visible = _view == "map"
		_compass.position = corner.end - _compass.size - Vector2(14, 14)
	var rect := _main.get_global_rect()
	var width := minf(460.0, rect.size.x - 32.0)
	_quest_card.custom_minimum_size.x = width
	_quest_card.size = Vector2(width, 0)
	_quest_card.position = rect.position + Vector2(16, 16)
	# Wrapped text knows its height only once laid out at this width.
	await get_tree().process_frame
	if is_instance_valid(_quest_card):
		_quest_card.size = Vector2(width, 0)


func _claim_onboarding(step_id: String) -> void:
	_status.text = ""
	var step: Dictionary = {}
	for s in Game.data.onboarding.steps:
		if s.id == step_id:
			step = s
	var from := _quest_card.get_global_rect().get_center()
	var response := await Api.post_json("/v1/worlds/%d/onboarding/claim" % Game.world_id(), {"step": step_id})
	if not response.ok:
		_status.text = response.error
		Sound.effect("error")
		return
	Sound.effect("done")
	_fly_reward(from, step.get("reward", {}))
	Game.set_world(response.data)
	if response.data.get("claimed", {}).get("finale", false):
		var finale: Dictionary = Game.data.onboarding.finale
		_fly_reward(from, finale.reward)
		_show_note(tr(finale.title), "%s\n\n%s" % [tr(finale.story), OnboardingText.reward(finale)], tr("Onward"))


## The reward's resources fly from `from` into the resource strip.
func _fly_reward(from: Vector2, amounts: Dictionary) -> void:
	var delay := 0.0
	for kind in Ledger.KINDS:
		if int(amounts.get(kind, 0)) <= 0 or not _resource_labels.has(kind):
			continue
		var label: Label = _resource_labels[kind]
		var to := label.get_global_rect().get_center()
		for i in 3:
			var icon := UI.icon("resource/" + kind, 36)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.position = from - Vector2(18, 18) + Vector2(randf_range(-30, 30), randf_range(-20, 20))
			_ui_layer.add_child(icon)
			var tween := icon.create_tween()
			tween.tween_interval(delay + i * 0.08)
			tween.tween_property(icon, "position", to - Vector2(18, 18), 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tween.parallel().tween_property(icon, "scale", Vector2(0.6, 0.6), 0.7)
			tween.tween_callback(icon.queue_free)
		var bump := label.create_tween()
		bump.tween_interval(delay + 0.75)
		bump.tween_property(label, "modulate", Color(1.6, 1.4, 0.7), 0.15)
		bump.tween_property(label, "modulate", Color.WHITE, 0.4)
		delay += 0.12


## Show me: takes the player to the control the step needs and rings it.
func _show_me(target: String) -> void:
	var home := _my_village()
	if home.is_empty():
		return
	var home_cell := Vector2i(int(home.q), int(home.r))
	match target:
		"village":
			if _view != "village":
				_point_at(_view_button)
				return
			_tab = "village"
			_side["buildings"] = "plot"
			_rebuild_panel()
			_point_at(_find_button(_panel_body, [tr("Build"), tr("Upgrade")]))
		"troops", "caravans":
			# Straight to the training list, or the caravan's load.
			_tab = target
			_side[target] = "train" if target == "troops" else "load"
			if _view != "village":
				_set_view("village")
			else:
				_rebuild_panel()
			_point_at(_find_button(_panel_body, [tr("Train") if target == "troops" else tr("Send")]))
		"threats":
			_point_at(_threat_button)
		"outpost":
			if _view != "map":
				_set_view("map")
			for cell in HexMath.neighbors(home_cell):
				var terrain: String = Game.terrain.get(cell, "")
				if Game.data.buildings.buildings[Rules.OUTPOST].yields.has(terrain) and Game.outpost_owner(cell).is_empty() \
						and Rules.claim_problem(Game.data, home, cell, terrain, false) == "":
					_go_to(cell)
					_point_at(_find_button(_panel_body, [tr("Claim")]))
					return
			_point_at(_main)
		"camp":
			if _view != "map":
				_set_view("map")
			var best := {}
			for camp in Game.camps:
				var cell := Vector2i(int(camp.q), int(camp.r))
				if best.is_empty() or HexMath.distance(cell, home_cell) < HexMath.distance(Vector2i(int(best.q), int(best.r)), home_cell):
					best = camp
			if best.is_empty():
				_status.text = tr("No camps on the map yet: they rise where a horde was beaten.")
				return
			_go_to(Vector2i(int(best.q), int(best.r)))
			_point_at(_panel)


## Centres the map on `cell` and opens its sheet.
func _go_to(cell: Vector2i) -> void:
	camera.position = hex_map.hex_to_local(cell)
	_select(cell)


## The first button under `node` whose text starts with one of `texts`.
func _find_button(node: Node, texts: Array) -> Control:
	for child in node.get_children():
		if child is Button and (child as Button).visible:
			for text in texts:
				if String((child as Button).text).begins_with(String(text)):
					return child
		var found := _find_button(child, texts)
		if found != null:
			return found
	return null


## A pulsing gold ring around `target` for a few seconds.
func _point_at(target: Control) -> void:
	if target == null:
		return
	await get_tree().process_frame
	var ring := Panel.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.border_color = Color("#ecc457")
	style.set_border_width_all(5)
	style.set_corner_radius_all(10)
	ring.add_theme_stylebox_override("panel", style)
	var rect := target.get_global_rect().grow(8)
	ring.position = rect.position
	ring.size = rect.size
	_ui_layer.add_child(ring)
	var tween := ring.create_tween().set_loops(4)
	tween.tween_property(ring, "modulate:a", 0.25, 0.4)
	tween.tween_property(ring, "modulate:a", 1.0, 0.4)
	tween.finished.connect(ring.queue_free)


## The first time a player enters a running world: what the run is about,
## and where the quest card is.
func _welcome_once() -> void:
	var world_id := Game.world_id()
	if Game.world.get("status") != "running" or Session.tutorial_flag(world_id, "welcomed") or _my_village().is_empty():
		return
	Session.set_tutorial_flag(world_id, "welcomed", true)
	_show_welcome()


func _show_welcome() -> void:
	var text := tr("Hordes will come from the edges of the map, wave after wave. Hold your villages, help your group, and build the Kalinov Bridge in the Holy City before it falls.") \
		+ "\n\n" + tr("The quest card at the top of the map shows what to do next, with Show me to point the way and a reward for each step.")
	_show_note(tr("Welcome to %s") % Game.world.get("name", ""), text, tr("Let's begin"), tr("Skip the tutorial"), func() -> void:
		Session.set_tutorial_flag(Game.world_id(), "hidden", true)
		_refresh_quest_card())


## A card in the middle of the screen over a dimmed game.
func _show_note(title: String, text: String, ok: String, other := "", on_other := Callable()) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var card := UI.wood(28)
	card.custom_minimum_size.x = minf(640.0, get_viewport().get_visible_rect().size.x - 48.0)
	center.add_child(card)
	var body := UI.vbox(18)
	card.add_child(body)
	var heading := UI.label(title, UI.HEADING_SIZE)
	heading.theme_type_variation = "OnWoodHeading"
	body.add_child(heading)
	var words := UI.label(text)
	words.theme_type_variation = "OnWoodStrong"
	body.add_child(words)
	var row := UI.hbox(12)
	if other != "":
		var skip := UI.button(other, func() -> void:
			dim.queue_free()
			if on_other.is_valid():
				on_other.call())
		skip.theme_type_variation = "WoodButton"
		row.add_child(skip)
	var go := UI.primary(ok, dim.queue_free)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(go)
	body.add_child(row)


## The almanac: units, buildings, stances, hordes, clans, terrain and the
## run, a side tab each, a few entries to a page.
func _almanac_panel() -> void:
	var top := UI.hbox()
	var title := UI.label(tr("Almanac"), UI.HEADING_SIZE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var how := UI.button("", func() -> void:
		Session.set_tutorial_flag(Game.world_id(), "hidden", false)
		_refresh_quest_card()
		_show_welcome(), "icon/help")
	how.tooltip_text = tr("How to play")
	how.custom_minimum_size.x = 0.0
	top.add_child(how)
	top.add_child(UI.button(tr("Back"), func() -> void:
		_panel_mode = "threats"
		_rebuild_panel()))
	_panel_body.add_child(top)
	var tabs := []
	for section in AlmanacText.SECTIONS:
		tabs.append([section, AlmanacText.ART[section], tr(section), _almanac_section.bind(section)])
	_side_tabs("almanac", tabs)


func _almanac_section(section: String) -> void:
	_panel_body.add_child(UI.label(tr(section), UI.HEADING_SIZE))
	# Clans, hordes and the run come with a story each: fewer to a page.
	var long := section in ["Hordes", "Clans", "The run"]
	_paged("almanac " + section, AlmanacText.entries(Game.data, section, float(Game.world.speed)), (2 if long else 3) if _roomy() else (1 if long else 2), func(entry: Array) -> void:
		var row := UI.hbox(12)
		var art: String = entry[2] if entry.size() > 2 else ""
		if art != "" and Art.has(art):
			var picture := UI.icon(art, 56)
			picture.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			row.add_child(picture)
		var text := UI.vbox(2)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var id: String = entry[3] if entry.size() > 3 else ""
		var speed := float(Game.world.get("speed", 1))
		if section == "Units" and id != "":
			text.add_child(UI.with_card(UI.label(entry[0]), func() -> Control: return BuildingInfo.unit_card(Game.data, id, speed)))
		elif section == "Buildings" and id != "":
			text.add_child(UI.with_card(UI.label(entry[0]), func() -> Control: return BuildingInfo.card(Game.data, id, speed)))
		elif section == "Clans" and id != "":
			text.add_child(UI.with_card(UI.label(entry[0]), func() -> Control: return ClanText.card(Game.data, id)))
		else:
			text.add_child(UI.label(entry[0]))
		text.add_child(UI.label(entry[1], UI.SMALL_SIZE, UI.MUTED))
		row.add_child(text)
		_panel_body.add_child(row))


## Opens the report form on the sheet; the report is saved as a file and
## sent to the server.
func _report_bug() -> void:
	_panel_mode = "report"
	_rebuild_panel()


## The bug report: what went wrong, typed in; sent with the game's state.
func _report_panel() -> void:
	var top := UI.hbox()
	var title := UI.label(tr("Report a bug"), UI.HEADING_SIZE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_panel_body.add_child(top)
	var edit := TextEdit.new()
	edit.custom_minimum_size = Vector2(0, 220)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.placeholder_text = tr("What went wrong?")
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	# What was typed survives the sheet being rebuilt (live updates).
	edit.text = _report_text
	edit.text_changed.connect(func() -> void: _report_text = edit.text)
	_panel_body.add_child(edit)
	_panel_body.add_child(UI.label(tr("The current game state is attached to the report."), UI.SMALL_SIZE, UI.MUTED))
	var row := UI.hbox(8)
	var send := UI.primary(tr("Send"), func() -> void:
		var text := _report_text
		if text.strip_edges() == "":
			_status.text = tr("Write what went wrong first.")
			return
		_report_text = ""
		_panel_mode = "hex"
		_rebuild_panel()
		_send_report(text))
	send.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(send)
	var cancel := UI.button(tr("Cancel"), func() -> void:
		_panel_mode = "hex"
		_rebuild_panel())
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cancel)
	_panel_body.add_child(row)
	if _report_text == "":
		edit.call_deferred("grab_focus")


func _send_report(message: String) -> void:
	# The server takes up to 4000 characters.
	var clean := message.strip_edges().left(REPORT_MAX)
	if clean == "":
		_status.text = tr("Write what went wrong first.")
		return
	var report := {"message": clean, "worldId": Game.world_id(), "state": Game.world}
	DirAccess.make_dir_recursive_absolute("user://bug_reports")
	var path := "user://bug_reports/report_%d.json" % int(Time.get_unix_time_from_system())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	_status.text = tr("Sending the report…")
	# Reports go to the server even from a solo world (they need a sign-in).
	var response := await Api.post_json("/v1/reports", report, true)
	if response.ok:
		_status.text = tr("Report sent. Saved to %s") % ProjectSettings.globalize_path(path)
	else:
		_status.text = tr("Report saved to %s (the server did not take it: %s)") % [
			ProjectSettings.globalize_path(path), response.error]


func _refetch_inbox() -> void:
	var response := await Api.get_json("/v1/worlds/%d/notifications" % Game.world_id())
	if response.ok:
		Game.set_inbox(Game.world_id(), response.data.notifications, int(response.data.unread))


## The shared button's count: unread notices and chat messages together.
func _update_messages_badge() -> void:
	if _inbox_button == null:
		return
	var unread := Game.unread + (0 if Local.is_active() else Game.chat_unread)
	_inbox_button.text = str(unread) if unread > 0 else ""


## Opens the inbox or the chat: the one with something new (the chat first),
## else the one open last.
func _show_messages() -> void:
	if not Local.is_active() and Game.chat_unread > 0:
		_show_chat()
	elif Game.unread > 0 or Local.is_active() or _messages_tab != "chat":
		_show_inbox()
	else:
		_show_chat()


## At the foot of the inbox and the chat: switch to the other (a group's
## worlds only), each with its count of what is new.
func _messages_switch(open: String) -> void:
	if Local.is_active():
		return
	var row := UI.hbox(8)
	for tab in [["inbox", "icon/inbox", tr("Notifications"), Game.unread, _show_inbox], ["chat", "icon/chat", tr("Chat"), Game.chat_unread, _show_chat]]:
		var count := int(tab[3])
		var b := UI.button(String(tab[2]) + (" (%d)" % count if count > 0 else ""), tab[4], String(tab[1]))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = tab[0] == open
		row.add_child(b)
	_panel_body.add_child(row)


## Achievements new to the player (Game.fresh_achievements): each in a popup.
func _pop_achievements() -> void:
	var defs: Dictionary = Game.data.get("achievements", {}).get("achievements", {})
	for id in Game.fresh_achievements:
		if defs.has(id):
			Sound.effect("horn")
			_show_note(tr("Achievement: %s") % tr(String(defs[id].name)), tr(String(defs[id].description)), tr("Onward"))
	Game.fresh_achievements.clear()


## Daily map events, as they rise, are done or are left undone: each new
## event notice in a popup (the last few, oldest on top).
func _pop_events() -> void:
	var world_id := Game.world_id()
	var seen := Session.world_mark(world_id, "event_seen")
	var fresh: Array = Game.inbox.filter(func(n: Dictionary) -> bool: return n.get("kind") == "event" and not n.get("read", false) and int(n.id) > seen)
	_pop_achievements()
	if fresh.is_empty():
		return
	fresh.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.id) > int(b.id))
	Session.set_world_mark(world_id, "event_seen", int(fresh[0].id))
	Sound.effect("horn")
	# Added newest first, so the oldest lies on top and is read first.
	for n in fresh.slice(0, 3):
		_show_note(String(n.title), String(n.body), tr("Onward"))


func _refetch_chat() -> void:
	if Local.is_active():
		return
	var world_id := Game.world_id()
	var response := await Api.get_json("/v1/worlds/%d/chat" % world_id)
	if response.ok:
		Game.set_chat(world_id, response.data.messages, int(response.data.lastReadId), int(response.data.unread))


func _show_chat() -> void:
	_panel_mode = "chat"
	_messages_tab = "chat"
	_rebuild_panel()
	_read_chat()
	# Scrolled to the newest message once the panel is laid out.
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


## Everything shown is read.
func _read_chat() -> void:
	if Game.chat.is_empty() or Game.chat_unread == 0:
		return
	var last := int(Game.chat[-1].id)
	if last <= _chat_read_sent:
		return
	_chat_read_sent = last
	Game.read_chat(last)
	await Api.post_json("/v1/worlds/%d/chat/read" % Game.world_id(), {"id": last})


func _chat_panel() -> void:
	var top := UI.hbox()
	var title := UI.label(tr("Chat"), UI.HEADING_SIZE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_panel_body.add_child(top)
	if Game.chat_more:
		_panel_body.add_child(UI.button(tr("Earlier messages"), _older_chat))
	if Game.chat.is_empty():
		_panel_body.add_child(UI.label(tr("No messages yet: say hello to your group."), UI.SMALL_SIZE, UI.MUTED))
	var now := Game.server_now()
	for message in Game.chat:
		var mine: bool = message.get("accountId") != null and int(message.accountId) == Game.my_account_id()
		var bubble := UI.card(10)
		var box := UI.vbox(2)
		bubble.add_child(box)
		box.add_child(UI.label(ChatText.header(message, mine, now), UI.SMALL_SIZE, UI.GOOD if mine else UI.ACCENT))
		box.add_child(UI.label(String(message.body)))
		# Yours lean right, the others' left.
		var line := MarginContainer.new()
		line.add_theme_constant_override("margin_left", 70 if mine else 0)
		line.add_theme_constant_override("margin_right", 0 if mine else 70)
		line.add_child(bubble)
		_panel_body.add_child(line)
	# What you write: Enter or Send.
	var row := UI.hbox(8)
	var field := _draft_field("chat", tr("Write to your group"), "")
	field.max_length = ChatText.MAX_LENGTH
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.text_submitted.connect(func(_text: String) -> void: _send_chat(field))
	row.add_child(field)
	row.add_child(UI.button(tr("Send"), func() -> void: _send_chat(field)))
	_panel_body.add_child(row)
	_messages_switch("chat")


func _send_chat(field: LineEdit) -> void:
	var text := field.text.strip_edges()
	# (Enter and Send together, or a second tap while the first is on its way.)
	if text == "" or _chat_sending:
		return
	_chat_sending = true
	_status.text = ""
	# Emptied at once, so what is typed next is not lost when the answer comes.
	field.text = ""
	_drafts.erase("chat")
	_focused_draft = "chat"
	var world_id := Game.world_id()
	var response := await Api.post_json("/v1/worlds/%d/chat" % world_id, {"body": text})
	_chat_sending = false
	if not response.ok:
		_status.text = response.error
		# Back in the field, unless something else was typed meanwhile.
		if not _drafts.has("chat"):
			_drafts["chat"] = {"text": text, "caret": text.length()}
			if is_instance_valid(field) and field.text == "":
				field.text = text
				field.caret_column = text.length()
		return
	_chat_sent = true
	Game.add_chat(world_id, response.data.message)
	# (The live copy of it may have come first: then nothing changed, and
	# the list still goes to the newest.)
	_on_chat_changed()


func _older_chat() -> void:
	if Game.chat.is_empty():
		return
	var world_id := Game.world_id()
	var response := await Api.get_json("/v1/worlds/%d/chat?before=%d" % [world_id, int(Game.chat[0].id)])
	if response.ok:
		Game.add_older_chat(world_id, response.data.messages)


## Opens the inbox: everything is read once seen.
func _show_inbox() -> void:
	_panel_mode = "inbox"
	_messages_tab = "inbox"
	_rebuild_panel()
	if Game.unread > 0:
		await Api.post_json("/v1/worlds/%d/notifications/read" % Game.world_id(), {})
	# Push settings belong to the account; a solo world sends no pushes.
	if Local.is_active():
		return
	var response := await Api.get_json("/v1/me/notifications")
	if response.ok:
		_prefs = response.data.prefs
		if _panel_mode == "inbox":
			_rebuild_panel()


func _inbox_panel() -> void:
	var top := UI.hbox()
	var title := UI.label(tr("Inbox"), UI.HEADING_SIZE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	if not Local.is_active():
		top.add_child(UI.info(tr("Danger is pushed to your phone; everything else waits for the daily digest.")))
	_panel_body.add_child(top)
	# Push settings are for a group's worlds (a solo world sends none).
	if _prefs.is_empty():
		_inbox_messages()
	else:
		_side_tabs("inbox", [["messages", "icon/inbox", tr("Messages"), _inbox_messages],
			["settings", "icon/settings", tr("Settings"), _notification_settings]])
	_messages_switch("inbox")


func _notice_group(kind: String) -> String:
	for group in NOTICE_GROUPS:
		if kind in NOTICE_GROUPS[group]:
			return group
	return "other"


func _inbox_messages() -> void:
	var chips := UI.hbox(6)
	for chip in [["all", tr("All")], ["battles", tr("Battles")], ["economy", tr("Economy")], ["other", tr("Other")]]:
		var key := String(chip[0])
		var b := UI.button(String(chip[1]), func() -> void:
			_inbox_filter = key
			_pages["inbox"] = 0
			_rebuild_panel())
		b.theme_type_variation = "TabButton"
		b.add_theme_font_size_override("font_size", UI.SMALL_SIZE)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = key == _inbox_filter
		chips.add_child(b)
	_panel_body.add_child(chips)
	var shown: Array = Game.inbox.filter(func(n: Dictionary) -> bool: return _inbox_filter == "all" or _notice_group(String(n.get("kind", ""))) == _inbox_filter)
	if shown.is_empty():
		_panel_body.add_child(UI.label(tr("Nothing here."), UI.SMALL_SIZE, UI.MUTED))
	var now := Game.server_now()
	_paged("inbox", shown, 6 if _roomy() else 3, func(n: Dictionary) -> void:
		var card := UI.card(10)
		var box := UI.vbox(2)
		card.add_child(box)
		var head := UI.hbox(8)
		var title := UI.label(("● " if not n.read else "") + String(n.title))
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		var when := UI.label(InboxText.ago(TimeUtil.parse_iso(n.createdAt), now), UI.SMALL_SIZE, UI.MUTED)
		when.autowrap_mode = TextServer.AUTOWRAP_OFF
		head.add_child(when)
		box.add_child(head)
		if String(n.body) != "":
			box.add_child(UI.label(String(n.body), UI.SMALL_SIZE, UI.MUTED))
		_panel_body.add_child(card))


func _notification_settings() -> void:
	if _prefs.is_empty():
		return
	_panel_body.add_child(UI.label(tr("Settings"), UI.HEADING_SIZE))
	var quiet: bool = _prefs.quietStart != null and _prefs.quietEnd != null
	var start := int(_prefs.quietStart) if quiet else 22 * 60
	var end := int(_prefs.quietEnd) if quiet else 7 * 60
	var quiet_row := UI.hbox(8)
	var quiet_text := UI.label(tr("Quiet hours %s–%s") % [InboxText.clock(start), InboxText.clock(end)] if quiet else tr("No quiet hours"), UI.SMALL_SIZE)
	quiet_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quiet_row.add_child(quiet_text)
	quiet_row.add_child(UI.button(tr("Off") if quiet else tr("On"), func() -> void:
		_save_prefs({"quietStart": null, "quietEnd": null} if quiet else {"quietStart": start, "quietEnd": end})))
	_panel_body.add_child(quiet_row)
	if quiet:
		var adjust := UI.hbox(8)
		for spec in [[tr("From −1h"), -60, 0], [tr("From +1h"), 60, 0], [tr("Until −1h"), 0, -60], [tr("Until +1h"), 0, 60]]:
			var button := UI.button(spec[0], func() -> void:
				_save_prefs({"quietStart": posmod(start + spec[1], 1440), "quietEnd": posmod(end + spec[2], 1440)}))
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.add_theme_font_size_override("font_size", UI.SMALL_SIZE)
			adjust.add_child(button)
		_panel_body.add_child(adjust)
	var digest := int(_prefs.digestHour)
	var digest_row := UI.hbox(8)
	var digest_text := UI.label(tr("Daily digest at %s") % InboxText.clock(digest * 60), UI.SMALL_SIZE)
	digest_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	digest_row.add_child(digest_text)
	for step in [-1, 1]:
		var button := UI.button(("%+dh" % step).replace("-", "−"), func() -> void: _save_prefs({"digestHour": posmod(digest + step, 24)}))
		button.custom_minimum_size.x = 100
		digest_row.add_child(button)
	_panel_body.add_child(digest_row)


## Saves settings, always with this phone's time zone.
func _save_prefs(changes: Dictionary) -> void:
	var body := changes.duplicate()
	body.utcOffsetMinutes = int(Time.get_time_zone_from_system().bias)
	var response := await Api.patch_json("/v1/me/notifications", body)
	if not response.ok:
		_status.text = response.error
		return
	_prefs = response.data.prefs
	_rebuild_panel()
