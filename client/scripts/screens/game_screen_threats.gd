extends "res://scripts/screens/game_screen_hero.gd"
## The in-world screen, the threats' part: hordes, scouting, battles and
## their reports, enemy leaders, the group and the run.

func _battle_button(battle: Dictionary) -> Button:
	var id := int(battle.id)
	var button := UI.button(tr("Battle map"), func() -> void: _open_battle(id), "icon/troops")
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return button


## Opens a battle on its map: a finished one plays from the start, one
## still being fought shows its latest round.
func _open_battle(battle_id: int) -> void:
	_battle_id = battle_id
	var battle := _battle()
	var finished: bool = battle.get("status", "ongoing") != "ongoing"
	_battle_round = 0 if finished else battle.get("rounds", []).size()
	_battle_playing = finished
	_battle_clock = 0.0
	_set_view("battle")


func _battle() -> Dictionary:
	for battle in Game.battles:
		if int(battle.id) == _battle_id:
			return battle
	return {}


func _battle_panel() -> void:
	var battle := _battle()
	if battle.is_empty():
		_panel_body.add_child(UI.label(tr("That battle is no longer in the reports."), UI.SMALL_SIZE, UI.MUTED))
		_panel_body.add_child(UI.button(tr("Back to the map"), func() -> void: _set_view("map"), "icon/map"))
		return
	var count: int = battle.rounds.size()
	_battle_round = clampi(_battle_round, 0, count)
	var ctx := _battle_ctx(battle)
	_battle_view.show_battle(Game.data, battle, _battle_round, ctx)
	_panel_body.add_child(UI.label(tr("Battle at %s") % ctx.place, UI.HEADING_SIZE))
	var row := UI.hbox(8)
	var back := UI.button("◀", func() -> void:
		_battle_playing = false
		_battle_round -= 1
		_rebuild_panel())
	back.disabled = _battle_round <= 0
	row.add_child(back)
	var where := UI.label(tr("Before the battle") if _battle_round == 0 else tr("Round %d of %d") % [_battle_round, count])
	where.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	where.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(where)
	var next := UI.button("▶", func() -> void:
		_battle_playing = false
		_battle_round += 1
		Sound.effect("clash")
		_rebuild_panel())
	next.disabled = _battle_round >= count
	row.add_child(next)
	var play := UI.button(tr("Pause") if _battle_playing else tr("Play"), func() -> void:
		_battle_playing = not _battle_playing
		if _battle_playing and _battle_round >= count:
			_battle_round = 0
		_battle_clock = 0.0
		_rebuild_panel())
	row.add_child(play)
	_panel_body.add_child(row)
	var story := BattleStory.opening(Game.data, battle, ctx) if _battle_round == 0 else BattleStory.narrate(Game.data, battle, _battle_round, ctx)
	_panel_body.add_child(UI.label(story))
	_sally_row(battle)
	if battle.status == "ongoing" and _battle_round >= count:
		_panel_body.add_child(UI.label(tr("The fight goes on; the next round comes in %s.") % TimeUtil.format_duration(float(Game.data.battle.roundMinutes) * 60.0), UI.SMALL_SIZE, UI.MUTED))
	_panel_body.add_child(UI.button(tr("Back to the map"), func() -> void: _set_view("map"), "icon/map"))


## Names, colours and ground for the battle map and its story.
func _battle_ctx(battle: Dictionary) -> Dictionary:
	var cell := Vector2i(int(battle.q), int(battle.r))
	var front := String(battle.front) if battle.get("front") != null else ""
	for wave in Game.waves:
		if battle.get("waveId") != null and int(wave.id) == int(battle.waveId):
			front = wave.front
	for camp in Game.camps:
		if battle.get("campId") != null and int(camp.id) == int(battle.campId):
			front = camp.front
	var village: Dictionary = Game.villages.get(int(battle.villageId), {}) if battle.get("villageId") != null else {}
	var chief := Game.leader(battle.get("leaderId"))
	var place := Game.battle_place(battle)
	var ctx := {
		"place": place,
		"enemy": (tr("the %s") % tr(Game.front_faction(front))) if front != "" else tr("the enemy"),
		"enemy_leader": tr("%s, level %d") % [chief.title, int(chief.level)] if not chief.is_empty() else tr("Their chief"),
		"led_by": String(chief.get("title", "")),
		"leader_after": LeaderText.after_battle(chief, battle, place),
		"from": {"north": tr("From the north"), "east": tr("From the east"), "south": tr("From the south"), "west": tr("From the west")}.get(front, tr("From the wilds")),
		"ours": HexMap.ALLY_COLOR if not village.is_empty() and not Game.is_mine(village) else HexMap.MINE_COLOR,
		"terrain": Game.terrain.get(cell, "plains"),
		"river": not RiverText.edges_at(Game.rivers, cell).is_empty(),
		"road": not RiverText.roads_at(Game.roads, cell).is_empty(),
		"village_name": Game.village_name,
	}
	for hero in Game.heroes:
		if not village.is_empty() and hero.get("villageId") != null and int(hero.villageId) == int(village.id) and hero.status == "home":
			ctx.leader = hero.name
	return ctx


func _show_threats() -> void:
	_panel_mode = "run" if RunText.is_over(Game.world) else "threats"
	_rebuild_panel()


func _open_run_once() -> void:
	if RunText.is_over(Game.world) and not _run_seen:
		_run_seen = true
		_panel_mode = "run"


## Hand-overs: give your villages to a teammate while away, take them back,
## and what delegates did lately.
func _delegation_section() -> void:
	var me := Game.my_account_id()
	var now := Game.server_now()
	_panel_body.add_child(UI.with_info(UI.label(tr("Hand-overs"), UI.HEADING_SIZE), tr("Away for a while? Hand your villages to a teammate for 1–7 days.")))
	var mine := DelegationText.of_owner(Game.delegations, me, now)
	if not mine.is_empty():
		_panel_body.add_child(UI.label(tr("%s commands your villages for %s more.") % [Game.member_name(int(mine.delegateAccountId)), TimeUtil.format_duration(TimeUtil.parse_iso(mine.until) - now)], UI.SMALL_SIZE))
		_panel_body.add_child(UI.button(tr("Take them back"), func() -> void: _end_delegation(me)))
	for owner in DelegationText.owners_for(Game.delegations, me, now):
		var d := DelegationText.of_owner(Game.delegations, owner, now)
		_panel_body.add_child(UI.label(tr("You command %s's villages for %s more.") % [Game.member_name(owner), TimeUtil.format_duration(TimeUtil.parse_iso(d.until) - now)], UI.SMALL_SIZE))
		_panel_body.add_child(UI.button(tr("Hand them back"), func() -> void: _end_delegation(owner)))
	var others: Array = Game.world.get("members", []).filter(func(m: Dictionary) -> bool: return int(m.accountId) != me)
	if mine.is_empty() and not others.is_empty():
		var row := UI.hbox(8)
		var who := UI.options(others.map(func(m: Dictionary) -> String: return m.displayName), 0)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(who)
		var days := UI.options(["1 day", "2 days", "3 days", "4 days", "5 days", "6 days", "7 days"].map(tr), 1)  # tr
		row.add_child(days)
		_panel_body.add_child(row)
		_panel_body.add_child(UI.button(tr("Hand over"), func() -> void: _delegate(int(others[who.selected].accountId), days.selected + 1)))
	var names := {}
	for m in Game.world.get("members", []):
		names[int(m.accountId)] = m.displayName
	var village_names := {}
	for v in Game.villages.values():
		village_names[int(v.id)] = v.name
	for e in Game.delegation_log.slice(0, 4):
		_panel_body.add_child(UI.label(tr("%s · %s ago") % [DelegationText.entry(e, names, village_names), TimeUtil.format_duration(now - TimeUtil.parse_iso(e.at))], UI.SMALL_SIZE, UI.MUTED))


func _delegate(to: int, days: int) -> void:
	_status.text = ""
	var response := await Api.request(HTTPClient.METHOD_PUT, "/v1/worlds/%d/delegation" % Game.world_id(), {"to": to, "days": days})
	if not response.ok:
		_status.text = response.error
		return
	Game.set_world(response.data)


func _end_delegation(owner: int) -> void:
	_status.text = ""
	var response := await Api.request(HTTPClient.METHOD_DELETE, "/v1/worlds/%d/delegation" % Game.world_id(), {"owner": owner})
	if not response.ok:
		_status.text = response.error
		return
	Game.set_world(response.data)


## The group's clans; a member with none yet picks one here.
func _clan_section() -> void:
	var me := _me()
	# Your clan in full; the others' a line each, their card behind a mark.
	if me.get("clan") != null:
		_panel_body.add_child(ClanText.card(Game.data, String(me.clan)))
	for member in Game.world.get("members", []):
		if int(member.accountId) == Game.my_account_id() and member.get("clan") != null:
			continue
		var row := UI.hbox(10)
		var clan: Variant = member.get("clan")
		if clan != null:
			row.add_child(UI.icon("clan/%s" % clan, 44))
		var line := UI.label(tr("%s: %s") % [member.displayName, ClanText.title(Game.data, clan)], UI.SMALL_SIZE, UI.MUTED)
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(line)
		if clan != null:
			row.add_child(UI.info_card(func() -> Control: return ClanText.card(Game.data, String(clan))))
		_panel_body.add_child(row)
	if me.is_empty() or me.get("clan") != null or RunText.is_over(Game.world):
		return
	_panel_body.add_child(UI.with_info(UI.label(tr("Pick your clan"), UI.HEADING_SIZE), tr("Its perks go to all your villages, for the rest of this run.")))
	# The emblems; the one tapped shows what it gives before you pick it.
	var grid := GridContainer.new()
	grid.columns = 6 if _roomy() and get_viewport().get_visible_rect().size.x > 1000.0 else 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var ids := ClanText.ids(Game.data)
	if not ids.has(_clan_preview):
		_clan_preview = ids[0]
	for clan in ids:
		var tile := UI.picture_button("clan/%s" % clan, ClanText.title(Game.data, clan), func() -> void:
			_clan_preview = clan
			_rebuild_panel())
		tile.disabled = clan == _clan_preview
		grid.add_child(tile)
	_panel_body.add_child(grid)
	_panel_body.add_child(UI.with_info(UI.label(ClanText.title(Game.data, _clan_preview), 0, UI.ACCENT), ClanText.arms(Game.data, _clan_preview)))
	_panel_body.add_child(UI.label(ClanText.perks(Game.data, _clan_preview), UI.SMALL_SIZE, UI.MUTED))
	var chosen := _clan_preview
	_panel_body.add_child(UI.primary(tr("Choose %s") % ClanText.title(Game.data, chosen), func() -> void: _pick_clan(chosen), "icon/play"))


func _pick_clan(clan: String) -> void:
	_status.text = ""
	var response := await Api.request(HTTPClient.METHOD_PUT, "/v1/worlds/%d/clan" % Game.world_id(), {"clan": clan})
	if not response.ok:
		_status.text = response.error
		return
	Game.set_world(response.data)


## How the run ended: its story and what the group did.
func _run_panel() -> void:
	var ending := RunText.ending(Game.data, Game.world)
	if ending.is_empty():
		return
	var won: bool = Game.world.status == "won"
	_panel_body.add_child(UI.label(tr(ending.title), UI.HEADING_SIZE, UI.ACCENT if won else UI.ERROR))
	_panel_body.add_child(UI.label(tr(ending.story), UI.SMALL_SIZE, UI.MUTED))
	var run: Variant = Game.world.get("run")
	if run is Dictionary:
		for line in RunText.stats(run, float(Game.world.speed), Local.run_seconds() if Local.is_active() else -1.0):
			_panel_body.add_child(UI.label(line, UI.SMALL_SIZE))
		_panel_body.add_child(UI.label(tr("The group"), UI.HEADING_SIZE))
		for member in run.members:
			_panel_body.add_child(UI.label(RunText.member_line(member), UI.SMALL_SIZE))
	var row := UI.hbox(8)
	row.add_child(UI.info(tr("The world stays open to look around, but nothing more can be done in it.")))
	var look := UI.button(tr("Look at the map"), func() -> void:
		_panel_mode = "hex"
		_rebuild_panel())
	look.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(look)
	var back := UI.button(tr("Back to worlds"), _leave)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(back)
	_panel_body.add_child(row)


## One line for the top banner: what needs attention first.
func _threat_summary() -> String:
	if RunText.is_over(Game.world):
		return tr("%s · see how the run went") % tr(RunText.ending(Game.data, Game.world).title)
	var ritual_at: Variant = Game.world.get("ritualAt")
	if ritual_at != null and TimeUtil.parse_iso(ritual_at) > Game.server_now():
		return RunText.ritual_line(Game.world, Game.server_now())
	if Game.waves.is_empty():
		return tr("No threats known")
	var now := Game.server_now()
	for wave in Game.waves:
		if wave.status == "razing":
			return tr("%s is burning, %s left") % [Game.village_name(wave.targetVillageId), TimeUtil.format_duration(TimeUtil.parse_iso(wave.endsAt) - now)]
	for wave in Game.waves:
		if wave.status == "marching":
			return tr("A horde reaches %s in %s") % [Game.village_name(wave.targetVillageId), TimeUtil.format_duration(TimeUtil.parse_iso(wave.arrivesAt) - now)]
	for wave in Game.waves:
		if wave.status == "battling":
			var battle := Game.battle_for(int(wave.id))
			var place := Game.battle_place(battle) if not battle.is_empty() else Game.village_name(wave.targetVillageId)
			return tr("Battle at %s, round %d") % [place, int(battle.get("round", 0))]
	for wave in Game.waves:
		if wave.status == "arrived":
			return tr("Horde at %s") % Game.village_name(wave.targetVillageId)
	var next: Dictionary = Game.waves[0]
	var line := tr("Horde from the %s (%s) · sets out in %s") % [String(next.front).to_lower(), tr(String(next.threat)).to_lower(), TimeUtil.format_duration(TimeUtil.parse_iso(next.spawnAt) - now)]
	if next.get("forecast") is Dictionary:
		line += tr(" → %s") % _target_name(next.forecast.targetVillageId)
	return line


func _threats_panel() -> void:
	var top := UI.hbox()
	var title := UI.label(tr("Threats"), UI.HEADING_SIZE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(UI.button(tr("Almanac"), func() -> void:
		_panel_mode = "almanac"
		_rebuild_panel(), "icon/research"))
	_panel_body.add_child(top)
	var tabs := [["hordes", "icon/threat", tr("Hordes"), _hordes_tab]]
	tabs.append(["events", "map/camp_bandit", tr("Events"), _events_tab])
	var living := Game.leaders.filter(func(chief: Dictionary) -> bool: return chief.status != "dead")
	if not Game.leaders.is_empty():
		var front := String((living[0] if not living.is_empty() else Game.leaders[0]).front)
		tabs.append(["leaders", WaveMath.front_icon(front), tr("Enemy leaders"), _leaders_section])
	tabs.append(["reports", "icon/troops", tr("Battle reports"), _reports_tab])
	tabs.append(["fronts", "map/camp_lair", tr("Camps and fronts"), _fronts_tab])
	var clan: Variant = _me().get("clan")
	tabs.append(["group", "clan/%s" % clan if clan != null else "icon/profile", tr("Your group"), _group_tab])
	# Hand-overs are between teammates: none in a solo world.
	if Game.world.get("status") == "running" and not Local.is_active():
		tabs.append(["handovers", "icon/village", tr("Hand-overs"), _delegation_section])
	tabs.append(["leave", "icon/settings", tr("World settings"), _leave_tab])
	_side_tabs("threats", tabs)


## The hordes on their way, and what stands between them and the Holy City.
func _hordes_tab() -> void:
	var ritual := RunText.ritual_line(Game.world, Game.server_now())
	if ritual != "":
		_panel_body.add_child(UI.label(ritual, 0, UI.ERROR))
		_panel_body.add_child(UI.label(tr(Game.data.bridge.ritualNight.story), UI.SMALL_SIZE, UI.MUTED))
	_panel_body.add_child(UI.label(tr("The Holy City: %s") % HordeText.sanctity(Game.world, Game.data), UI.SMALL_SIZE, UI.MUTED))
	if Game.waves.is_empty():
		_panel_body.add_child(UI.label(tr("No waves announced."), UI.SMALL_SIZE, UI.MUTED))
	else:
		_panel_body.add_child(ThreatLine.new())
	_paged("waves", Game.waves, 2 if _roomy() else 1, _wave_entry)


## The daily events still going: captives, forbidding ruins, shipyards;
## each with how it stands and a button that shows it on the map.
func _events_tab() -> void:
	_panel_body.add_child(UI.with_info(UI.label(tr("Events"), UI.HEADING_SIZE),
		tr("Every day something rises on the map near a village: captives to free, a forbidding ruin to search, a shipyard to pay for and defend. Each brings a bounty; one left undone makes the next horde hate you more.")))
	var events := EventText.active(Game.camps, Game.sites, Game.shipyards)
	if events.is_empty():
		_panel_body.add_child(UI.label(tr("No events on the map now."), UI.SMALL_SIZE, UI.MUTED))
	_paged("events", events, 4 if _roomy() else 3, _event_entry)


func _event_entry(event: Dictionary) -> void:
	var row := UI.hbox()
	var text := UI.vbox(2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(UI.label(EventText.title(event), UI.SMALL_SIZE))
	var line := UI.label("", UI.SMALL_SIZE, UI.MUTED)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(line)
	# A shipyard: how much is paid, then how far the boat is built.
	var bar: ProgressBar = null
	if event.kind == "shipyard":
		bar = _gauge(UI.ACCENT if event.item.status == "building" else UI.GOOD)
		text.add_child(bar)
	_tick(line, func() -> String:
		var now := Game.server_now()
		if bar != null and is_instance_valid(bar):
			bar.value = EventText.build_share(Game.data, event.item, now, float(Game.world.speed)) if event.item.status == "building" else EventText.paid_share(event.item)
		return EventText.state(Game.data, event, now, float(Game.world.speed)))
	row.add_child(text)
	var cell: Vector2i = event.cell
	var show_button := UI.button(tr("Show on map"), func() -> void:
		_set_view("map")
		_go_to(cell))
	show_button.custom_minimum_size.x = 150
	row.add_child(show_button)
	_panel_body.add_child(row)


## How the battles went, newest first.
func _reports_tab() -> void:
	_panel_body.add_child(UI.label(tr("Battle reports"), UI.HEADING_SIZE))
	var finished := Game.battles.filter(func(b: Dictionary) -> bool: return b.status != "ongoing")
	if finished.is_empty():
		_panel_body.add_child(UI.label(tr("No battles fought yet."), UI.SMALL_SIZE, UI.MUTED))
	_paged("reports", finished, 3 if _roomy() else 2, _battle_report)


func _battle_report(battle: Dictionary) -> void:
	var report := RaidText.report(battle, BattleText.losses(battle))
	if report == "":
		report = HordeText.assault(battle, BattleText.losses(battle)) if battle.get("campId") != null or battle.get("siteId") != null else BattleText.outcome(battle, Game.battle_place(battle))
	_panel_body.add_child(UI.label(report, UI.SMALL_SIZE))
	var details := tr("%s horde, %d rounds") % [String(battle.attackerStance).replace("_", " ").capitalize(), int(battle.round)]
	var ground := BattleText.setup_text(battle)
	if ground != "":
		details += " · " + ground
	_panel_body.add_child(UI.label(details, UI.SMALL_SIZE, UI.MUTED))
	var choice := HordeText.decision(battle)
	if choice != "":
		_panel_body.add_child(UI.label(choice, UI.SMALL_SIZE, UI.ERROR))
	var helpers := ArmyText.reinforcements(battle, Game.village_name)
	if helpers != "":
		_panel_body.add_child(UI.label(tr("Help came from %s") % helpers, UI.SMALL_SIZE, UI.MUTED))
	_panel_body.add_child(_battle_button(battle))
	_sally_row(battle)


## Where the hordes come from: the fronts, their camps and lairs, and the
## outposts they burned.
func _fronts_tab() -> void:
	var map: Variant = Game.world.get("map")
	if map is Dictionary:
		_panel_body.add_child(UI.label(tr("Fronts"), UI.HEADING_SIZE))
		for front in map.activeFronts:
			var line := WaveMath.front_line(Game.data, String(front))
			if line == "":
				continue
			var row := UI.hbox(8)
			row.add_child(UI.icon(WaveMath.front_icon(String(front)), 28))
			row.add_child(UI.label(line, UI.SMALL_SIZE, UI.MUTED))
			_panel_body.add_child(row)
	if not Game.camps.is_empty():
		_panel_body.add_child(UI.label(tr("Camps and lairs"), UI.HEADING_SIZE))
	_paged("camps", Game.camps, 5 if _roomy() else 3, func(camp: Dictionary) -> void:
		_panel_body.add_child(UI.label(tr("%s at (%d, %d)") % [HordeText.camp(camp, Game.front_faction(camp.front)), int(camp.q), int(camp.r)], UI.SMALL_SIZE)))
	if not Game.raids.is_empty():
		_panel_body.add_child(UI.label(tr("Outposts burned"), UI.HEADING_SIZE))
	_paged("raids", Game.raids, 3 if _roomy() else 2, func(raid: Dictionary) -> void:
		_panel_body.add_child(UI.label(BattleText.raid(raid, Game.village_name(raid.villageId)), UI.SMALL_SIZE)))


## The group: difficulty and quiet hours, everyone's clan, and hand-overs.
func _group_tab() -> void:
	var difficulty := tr(GroupText.difficulty(Game.data, String(Game.world.get("difficulty", "normal"))))
	_panel_body.add_child(UI.label(tr("%s difficulty") % difficulty, UI.SMALL_SIZE, UI.MUTED))
	_clan_section()


## A solo world can be played faster when there is time, and slower for the
## night: everything in it keeps pace, from builds to the hordes.
func _speed_section() -> void:
	_panel_body.add_child(UI.with_info(UI.label(tr("Game speed"), UI.HEADING_SIZE),
		tr("Everything in the world runs at this speed, the hordes too: an hour of the game passes in an hour divided by it. Speed up when you have time to play, slow down before you sleep.")))
	var current := Local.speed()
	_panel_body.add_child(UI.label(tr("Now %s×") % UI.number(current), UI.SMALL_SIZE, UI.MUTED))
	var row: HBoxContainer = null
	for i in Local.SPEEDS.size():
		if i % 4 == 0:
			row = UI.hbox(8)
			_panel_body.add_child(row)
		var value: float = Local.SPEEDS[i]
		var b := UI.button("%s×" % UI.number(value), func() -> void:
			Local.set_speed(value)
			_rebuild_panel())
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.x = 0
		b.disabled = is_equal_approx(value, current) or Game.world.get("status") != "running"
		row.add_child(b)


## Quiet hours: no horde arrives in them (it waits outside until they end),
## so nothing falls while you sleep. The host sets them (in solo, you).
func _quiet_section() -> void:
	_panel_body.add_child(UI.with_info(UI.label(tr("Peaceful hours"), UI.HEADING_SIZE),
		tr("No horde arrives in these hours: one that would waits outside until they end. Set them to when you sleep.")))
	var window: Variant = Game.world.get("quietHours")
	_panel_body.add_child(UI.label(GroupText.quiet(window), UI.SMALL_SIZE, UI.MUTED))
	var host: bool = Local.is_active() or (Game.world.get("hostAccountId") != null and int(Game.world.hostAccountId) == Game.my_account_id())
	if not host:
		_panel_body.add_child(UI.label(tr("The host sets them."), UI.SMALL_SIZE, UI.MUTED))
		return
	var quiet_row := UI.hbox(8)
	var off := UI.button(tr("Off"), func() -> void: _set_quiet(null, null))
	off.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	off.custom_minimum_size.x = 0
	off.disabled = not window is Dictionary
	quiet_row.add_child(off)
	for choice in GroupText.QUIET_CHOICES:
		var start: int = choice[0] * 60
		var end: int = choice[1] * 60
		var b := UI.button("%02d–%02d" % [choice[0], choice[1]], func() -> void: _set_quiet(start, end))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.x = 0
		b.disabled = window is Dictionary and int(window.start) == start and int(window.end) == end
		quiet_row.add_child(b)
	_panel_body.add_child(quiet_row)


## The world's settings: its peaceful hours (in solo, its speed); report a
## bug, or leave it.
func _leave_tab() -> void:
	if Local.is_active():
		_speed_section()
	else:
		_quiet_section()
	# A bug report carries the current game state with the player's message.
	_panel_body.add_child(UI.button(tr("Report a bug"), _report_bug, "icon/help"))
	_leave_section()


func _leave_section() -> void:
	_panel_body.add_child(UI.label(tr("Leave"), UI.HEADING_SIZE))
	var row := UI.hbox(8)
	var menu := UI.button(tr("Back to the menu"), _leave, "icon/back")
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(menu)
	var quit := UI.button(tr("Sure? Quit this world") if _quit_armed else tr("Quit this world"), _quit_world, "icon/quit")
	quit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(quit)
	_panel_body.add_child(row)
	if _quit_armed:
		var solo := Local.is_active()
		var alone: bool = Game.world.get("members", []).size() <= 1
		_panel_body.add_child(UI.label(
			tr("Tap again to delete this solo world.") if solo
			else tr("Tap again to quit. You're the last one here, so the world closes.") if alone
			else tr("Tap again to quit. Your villages go to your teammates, and you can't come back."), UI.SMALL_SIZE, UI.ERROR))


func _quit_world() -> void:
	if not _quit_armed:
		_quit_armed = true
		_rebuild_panel()
		return
	_quit_armed = false
	var id := Game.world_id()
	if Local.is_active():
		Local.delete_world(id)
	else:
		var response := await Api.post_json("/v1/worlds/%d/leave" % id)
		if not response.ok:
			_status.text = response.error
			return
	if int(Session.last_world.get("id", 0)) == id:
		Session.last_world = {}
		Session.save()
	_leave()


## The host sets the group's quiet hours, in this device's time zone.
## The enemy's leaders: who leads each front, how strong, what they've done,
## who they hate; the fallen in one line.
func _leaders_section() -> void:
	if Game.leaders.is_empty():
		return
	_panel_body.add_child(UI.label(tr("Enemy leaders"), UI.HEADING_SIZE))
	var fallen := PackedStringArray()
	for chief in Game.leaders:
		if chief.status == "dead":
			fallen.append(LeaderText.name_line(chief))
	var living := Game.leaders.filter(func(chief: Dictionary) -> bool: return chief.status != "dead")
	_paged("leaders", living, 3 if _roomy() else 2, func(chief: Dictionary) -> void:
		var name_row := UI.hbox(8)
		name_row.add_child(UI.icon(WaveMath.front_icon(String(chief.front)), 28))
		name_row.add_child(UI.label(tr("%s · %s front") % [LeaderText.name_line(chief), String(chief.front).capitalize()], UI.SMALL_SIZE, UiTheme.GOLD))
		_panel_body.add_child(name_row)
		var state := UI.label("", UI.SMALL_SIZE, UI.MUTED)
		_panel_body.add_child(state)
		_tick(state, func() -> String: return tr("%s · %s") % [LeaderText.state(chief, Game.server_now()), LeaderText.effects(chief)])
		_panel_body.add_child(UI.label(LeaderText.record(chief), UI.SMALL_SIZE, UI.MUTED))
		var grudge := LeaderText.grudge(Game.data, chief, Game.village_name)
		if grudge != "":
			_panel_body.add_child(UI.label(grudge, UI.SMALL_SIZE, UI.ERROR)))
	if not fallen.is_empty():
		_panel_body.add_child(UI.label(tr("Fallen: %s") % ", ".join(fallen), UI.SMALL_SIZE, UI.MUTED))


func _set_quiet(start: Variant, end: Variant) -> void:
	_status.text = ""
	var offset := int(Time.get_time_zone_from_system().get("bias", 0))
	var response := await Api.request(HTTPClient.METHOD_PUT, "/v1/worlds/%d/quiet" % Game.world_id(), {"start": start, "end": end, "utcOffsetMinutes": offset})
	if not response.ok:
		_status.text = response.error
		return
	Game.set_world(response.data)


func _wave_entry(wave: Dictionary) -> void:
	var errand: Variant = wave.get("errand")
	if errand is Dictionary and errand.kind == "quest":
		# A bridge quest's host, apart from the hordes.
		_panel_body.add_child(UI.label(tr("%s · %s") % [tr(String(Game.data.bridge.questPlaces.defense.name)), tr(Game.front_faction(wave.front))]))
	elif errand is Dictionary:
		# A band sent at the bridge's builders while a stage is raised.
		_panel_body.add_child(UI.label(tr("Raiders of the bridge · %s") % tr(Game.front_faction(wave.front))))
	elif wave.get("bandOf") != null:
		# A band its hating horde sent out after a village.
		_panel_body.add_child(UI.label(tr("A band of horde %d · %s") % [int(wave.index) + 1, tr(Game.front_faction(wave.front))]))
	else:
		_panel_body.add_child(UI.label(tr("Wave %d · %s") % [int(wave.index) + 1, tr(Game.front_faction(wave.front))]))
	var scouted := Game.missions_for(int(wave.id)).any(func(m: Dictionary) -> bool: return m.report != null)
	var known := "" if scouted else tr(" · composition unknown")
	var threat_row := UI.hbox(8)
	var threat_ic := UI.icon(WaveMath.threat_icon(String(wave.threat)), 26)
	threat_ic.self_modulate = WaveMath.threat_color(String(wave.threat))
	threat_row.add_child(threat_ic)
	threat_row.add_child(UI.label(tr("%s front · %s threat%s") % [String(wave.front).capitalize(), tr(wave.threat), known], UI.SMALL_SIZE, WaveMath.threat_color(String(wave.threat))))
	_panel_body.add_child(threat_row)
	# Hatred belongs to the front: ambushes, harassment, raids, strikes and
	# events left undone add to it, and its next horde to set out takes it all.
	var band_share := roundi(float(Game.data.horde.hatred.bandShare) * 100.0)
	if wave.status == "scheduled" and wave.get("bandOf") == null:
		var front_hatred := float(Game.world.get("hatred", {}).get(wave.front, 0.0))
		if front_hatred > 0:
			var camps := front_hatred * float(Game.data.horde.hatred.campChance)
			_panel_body.add_child(UI.with_info(UI.label(tr("Hatred of the %s front: +%d%% attack and defense") % [String(wave.front).capitalize(), roundi(front_hatred * 100.0)], UI.SMALL_SIZE, UI.ERROR),
				tr("The front's hatred grows with every ambush, harassing strike, raid and strike against its hordes, and every map event left undone. Its next horde to set out takes all of it, and the front's hatred starts again from nothing. Each time it passes another 100%%, the front's next horde sends a band of %d%% of its troops against the nearest village. A horde that took it leaves %s more camps behind when it is over (the whole part surely, the rest by chance). Ambushes on the front are riskier, and worth more.") % [band_share, UI.number(camps)]))
	else:
		var hatred := float(wave.get("hatred", 0.0))
		if hatred > 0:
			var camps := hatred * float(Game.data.horde.hatred.campChance)
			_panel_body.add_child(UI.with_info(UI.label(tr("Hatred: +%d%% attack and defense") % roundi(hatred * 100.0), UI.SMALL_SIZE, UI.ERROR),
				tr("It took all of its front's hatred as it set out. When it is over, it leaves %s more camps behind (the whole part surely, the rest by chance).") % UI.number(camps)))
	var line := UI.label("", UI.SMALL_SIZE, UI.ERROR)
	_panel_body.add_child(line)
	_tick(line, func() -> String:
		var now := Game.server_now()
		match wave.status:
			"scheduled":
				var appears := tr("Appears in %s") % TimeUtil.format_duration(TimeUtil.parse_iso(wave.spawnAt) - now)
				var forecast: Variant = wave.get("forecast")
				if forecast is Dictionary:
					appears += tr(" → %s in %s") % [_target_name(forecast.targetVillageId), TimeUtil.format_duration(TimeUtil.parse_iso(forecast.arrivesAt) - now)]
				return appears
			"marching":
				return tr("Marching on %s · arrives in %s") % [Game.village_name(wave.targetVillageId), TimeUtil.format_duration(TimeUtil.parse_iso(wave.arrivesAt) - now)]
			"arrived":
				return tr("At the gates of %s · leaves in %s") % [Game.village_name(wave.targetVillageId), TimeUtil.format_duration(TimeUtil.parse_iso(wave.endsAt) - now)]
			"razing":
				return tr("Burning %s · done in %s") % [Game.village_name(wave.targetVillageId), TimeUtil.format_duration(TimeUtil.parse_iso(wave.endsAt) - now)]
			"battling":
				var battle := Game.battle_for(int(wave.id))
				return tr("Fighting at %s · round %d of %d · %d of them left") % [Game.battle_place(battle) if not battle.is_empty() else Game.village_name(wave.targetVillageId), int(battle.get("round", 0)), int(Game.data.battle.maxRounds), BattleText.total(battle.get("attackerNow", {}))]
		return String(wave.status).capitalize())
	var chief := Game.leader(wave.get("leaderId"))
	if not chief.is_empty():
		_panel_body.add_child(UI.label(tr("Led by %s") % LeaderText.name_line(chief), UI.SMALL_SIZE, UiTheme.GOLD))
	var fighting := Game.battle_for(int(wave.id))
	if not fighting.is_empty() and fighting.status == "ongoing":
		_panel_body.add_child(_battle_button(fighting))
		_sally_row(fighting)
	_scouting_section(wave)


func _scouting_section(wave: Dictionary) -> void:
	var wave_id := int(wave.id)
	var missions := Game.missions_for(wave_id)
	var latest: Dictionary = {}
	for mission in missions:
		if mission.report != null:
			latest = mission
			break
	if not latest.is_empty():
		var by := Game.village_name(latest.villageId)
		_panel_body.add_child(UI.label(tr("Scouts from %s: %s") % [by, ScoutText.survivors(latest.report)], UI.SMALL_SIZE, UI.MUTED))
		_panel_body.add_child(UI.label(ScoutText.describe(latest.report), UI.SMALL_SIZE))
		var slain := ScoutText.slain(latest.report)
		if slain != "":
			_panel_body.add_child(UI.label(slain, UI.SMALL_SIZE, UiTheme.GOLD))
	for mission in missions:
		if mission.status == "done":
			continue
		var line := UI.label("", UI.SMALL_SIZE, UI.MUTED)
		_panel_body.add_child(line)
		_tick(line, func() -> String:
			var now := Game.server_now()
			if mission.status == "outbound":
				return tr("%d scouts en route · report in %s") % [mission.sent, TimeUtil.format_duration(TimeUtil.parse_iso(mission.arrivesAt) - now)]
			return tr("Scouts heading home · back in %s") % TimeUtil.format_duration(TimeUtil.parse_iso(mission.returnsAt) - now))

	var home := _my_village()
	if home.is_empty() or int(home.levels.get("scout_lodge", 0)) < 1:
		return
	var village_id := int(home.id)
	# How many of each kind of scout to send (all go together, at the pace
	# of the slowest).
	var garrison := Rules.garrison_at(home, Game.server_now())
	var kinds: Array = Game.data.units.units.keys().filter(func(unit: String) -> bool:
		return Game.data.units.units[unit].family == "scout" and int(garrison.get(unit, 0)) > 0)
	if kinds.is_empty():
		_panel_body.add_child(UI.label(tr("No scouts at home."), UI.SMALL_SIZE, UI.MUTED))
		return
	var max_scouts := int(Game.data.scouting.maxScouts)
	for unit in kinds:
		var have := int(garrison[unit])
		var key := "%d:%s" % [wave_id, unit]
		var count := clampi(int(_scout_counts.get(key, mini(have, 3) if unit == "scout" else 0)), 0, mini(have, max_scouts))
		_scout_counts[key] = count
		var row := UI.hbox(8)
		row.tooltip_text = tr(Game.data.units.units[unit].name)
		if Art.has("unit/%s" % unit):
			row.add_child(UI.icon("unit/%s" % unit, 40))
		row.add_child(_number_field("scouts:" + key, count, 0, mini(have, max_scouts), func(n: int) -> void: _scout_counts[key] = n))
		var of := UI.label(tr("%s · %d home") % [tr(Game.data.units.units[unit].name), have], UI.SMALL_SIZE, UI.MUTED)
		of.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(of)
		_panel_body.add_child(row)
	var send := UI.button(tr("Send scouts"), func() -> void:
		var units := {}
		for unit in kinds:
			var n := int(_scout_counts.get("%d:%s" % [wave_id, unit], 0))
			if n > 0:
				units[unit] = n
		_send_scouts(village_id, wave_id, units))
	_panel_body.add_child(send)


func _send_scouts(village_id: int, wave_id: int, units: Dictionary) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/scout" % village_id, {"waveId": wave_id, "units": units})
	if not response.ok:
		_status.text = response.error
		return
	Game.note_server_time(response.data.serverTime)
	Game.update_village(response.data.village)
