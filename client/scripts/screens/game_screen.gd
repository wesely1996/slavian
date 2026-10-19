extends Node2D
## In-world screen: the map from the server, your resources, a threat
## banner, and a panel for the selected hex (or the threats timeline). The
## Village button swaps the map for the inside of your village, where you
## build on its plots and train troops.

const START_SCENE := "res://scenes/start.tscn"
const UI_REFRESH_SEC := 0.25
const NEGATIVE := Color("#ff8a7a")

@onready var hex_map: HexMap = $HexMap
@onready var camera: MapCamera = $MapCamera

var _selected := Vector2i.MAX
var _since_refresh := 0.0

var _live_label: Label
var _resource_labels: Dictionary[String, Label] = {}
## "map", "village" (the inside of your own village) or "battle" (a battle
## on its campaign map).
var _view := "map"
var _view_button: Button
var _inbox_button: Button
## Notification settings as the server last sent them.
var _prefs: Dictionary = {}
var _spacer: Control
var _village_view: VillageView
var _battle_view: BattleMap
## The battle on the battle map, the round shown, and whether it plays on.
var _battle_id := 0
var _battle_round := 0
var _battle_playing := false
var _battle_clock := 0.0
## The plot picked in the village view.
var _plot := Rules.HALL_PLOT
## Which part of the village panel is open: "village", "troops" or
## "caravans".
var _tab := "village"
## Caravan form: destination village id (0: the Holy City vault) and load.
var _caravan_to := 0
var _caravan_load: Dictionary[String, int] = {"wood": 0, "stone": 0, "grain": 0, "iron": 0}
## Army form: destination, troops and orders.
var _army_to := 0
var _army_units: Dictionary[String, int] = {}
var _army_orders := "support"
## Hold form: whether your hero leads the army.
var _army_hero := false
## Standing order forms: repeat training and the surplus share.
var _repeat_unit := "spearman"
var _repeat_target := 20
var _repeat_batch := 5
var _surplus_share := 80
## What the bottom panel shows: "hex" (the selected hex) or "threats".
var _panel_mode := "hex"
## The end-of-run panel opens by itself once.
var _run_seen := false
var _threat_button: Button
## Chosen number of scouts to send, per wave id.
var _scout_counts: Dictionary[int, int] = {}
## Chosen batch size per unit, kept while the panel rebuilds.
var _train_counts: Dictionary[String, int] = {}
var _status: Label
var _panel: PanelContainer
var _panel_body: VBoxContainer
## Labels refreshed every UI tick, with a callable producing their text.
var _ticking: Array[Array] = []


func _ready() -> void:
	_build_ui()
	camera.tapped.connect(_on_map_tapped)
	Game.world_changed.connect(_on_world_changed)
	Game.village_changed.connect(_on_village_changed)
	Live.village_updated.connect(Game.update_village)
	Live.world_updated.connect(Game.set_world)
	Live.connection_changed.connect(_on_live_connection)
	Live.waves_updated.connect(Game.set_waves)
	Live.scouting_updated.connect(Game.set_scouting)
	Live.battles_updated.connect(Game.set_battles)
	Live.raids_updated.connect(Game.set_raids)
	Live.caravans_updated.connect(Game.set_logistics)
	Live.expeditions_updated.connect(Game.set_expeditions)
	Live.research_updated.connect(Game.set_research)
	Live.heroes_updated.connect(Game.set_heroes)
	Live.orders_updated.connect(Game.set_orders)
	Live.inbox_updated.connect(Game.set_inbox)
	Live.armies_updated.connect(Game.set_armies)
	Live.forts_updated.connect(Game.set_forts)
	Game.armies_changed.connect(_on_waves_changed)
	Game.forts_changed.connect(_on_waves_changed)
	Game.inbox_changed.connect(_on_inbox_changed)
	Game.orders_changed.connect(_on_waves_changed)
	Game.heroes_changed.connect(_on_waves_changed)
	Game.research_changed.connect(_on_waves_changed)
	Game.expeditions_changed.connect(_on_waves_changed)
	Game.caravans_changed.connect(_on_waves_changed)
	Game.waves_changed.connect(_on_waves_changed)
	Game.raids_changed.connect(_on_waves_changed)
	Game.scouting_changed.connect(_on_waves_changed)
	Game.battles_changed.connect(_on_waves_changed)
	Live.watch(Game.world_id())
	_open_run_once()

	hex_map.refresh()
	camera.bounds = hex_map.get_bounds()
	var home := _my_village()
	if not home.is_empty():
		var cell := Vector2i(int(home.q), int(home.r))
		camera.position = hex_map.hex_to_local(cell)
		_select(cell)
	else:
		_select(Vector2i.ZERO)


func _exit_tree() -> void:
	Live.village_updated.disconnect(Game.update_village)
	Live.world_updated.disconnect(Game.set_world)
	Live.connection_changed.disconnect(_on_live_connection)
	Live.waves_updated.disconnect(Game.set_waves)
	Live.scouting_updated.disconnect(Game.set_scouting)
	Live.battles_updated.disconnect(Game.set_battles)
	Live.raids_updated.disconnect(Game.set_raids)
	Live.caravans_updated.disconnect(Game.set_logistics)
	Live.expeditions_updated.disconnect(Game.set_expeditions)
	Live.research_updated.disconnect(Game.set_research)
	Live.heroes_updated.disconnect(Game.set_heroes)
	Live.orders_updated.disconnect(Game.set_orders)
	Live.inbox_updated.disconnect(Game.set_inbox)
	Live.armies_updated.disconnect(Game.set_armies)
	Live.forts_updated.disconnect(Game.set_forts)


## Seconds a round stays on the battle map while it plays.
const BATTLE_ROUND_SEC := 1.6


func _process(delta: float) -> void:
	if _view == "battle" and _battle_playing:
		_battle_clock += delta
		if _battle_clock >= BATTLE_ROUND_SEC:
			_battle_clock = 0.0
			_battle_round += 1
			_battle_playing = _battle_round < _battle().get("rounds", []).size()
			_rebuild_panel()
	_since_refresh += delta
	if _since_refresh < UI_REFRESH_SEC:
		return
	_since_refresh = 0.0
	var home := _my_village()
	if not home.is_empty():
		var amounts := Ledger.amounts_at(home.resources, Game.server_now())
		for kind in Ledger.KINDS:
			var rate: float = home.resources.ratesPerHour[kind]
			var label := _resource_labels[kind]
			label.text = "%d  %s/h" % [amounts[kind], UI.signed(rate)]
			label.tooltip_text = kind.capitalize()
			label.add_theme_color_override("font_color", NEGATIVE if rate < 0 else UiTheme.TEXT)
	_threat_button.text = _threat_summary()
	_status.visible = _status.text != ""
	if hex_map.has_moving_hordes():
		hex_map.queue_redraw()
	for entry in _ticking:
		entry[0].text = (entry[1] as Callable).call()


# --- Layout ----------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	layer.add_child(margin)
	var column := UI.vbox(12)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	var top := UI.panel(Color(0.13, 0.11, 0.09, 0.85), 8)
	column.add_child(top)
	var top_rows := UI.vbox(6)
	top.add_child(top_rows)
	var bar := UI.hbox()
	top_rows.add_child(bar)
	var back := UI.button("", _leave, "icon/back")
	back.tooltip_text = "Worlds"
	bar.add_child(back)
	_view_button = UI.button("Village", _toggle_view, "icon/village")
	_view_button.visible = not _my_village().is_empty()
	bar.add_child(_view_button)
	_inbox_button = UI.button("", _show_inbox, "icon/inbox")
	_inbox_button.tooltip_text = "Inbox"
	bar.add_child(_inbox_button)
	var title := UI.label(Game.world.get("name", ""), UI.HEADING_SIZE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bar.add_child(title)
	_live_label = UI.label("", UI.SMALL_SIZE)
	_live_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	bar.add_child(_live_label)
	var resources := GridContainer.new()
	resources.columns = 2
	resources.add_theme_constant_override("h_separation", 24)
	top_rows.add_child(resources)
	for kind in Ledger.KINDS:
		var cell := UI.hbox(6)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(UI.icon("resource/" + kind, 40))
		var label := UI.label("", UI.SMALL_SIZE)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(label)
		resources.add_child(cell)
		_resource_labels[kind] = label
	_threat_button = UI.button("", _show_threats, "icon/threat")
	_threat_button.custom_minimum_size.y = 60
	_threat_button.add_theme_font_size_override("font_size", UI.SMALL_SIZE)
	_threat_button.add_theme_color_override("font_color", Color("#ffe0d8"))
	_threat_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_threat_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top_rows.add_child(_threat_button)
	_status = UI.label("", UI.SMALL_SIZE, UI.ERROR)
	top_rows.add_child(_status)
	_on_live_connection(Live.connected)

	_spacer = Control.new()
	_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_spacer)
	_village_view = VillageView.new()
	_village_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_village_view.visible = false
	_village_view.plot_tapped.connect(_on_plot_tapped)
	column.add_child(_village_view)
	_battle_view = BattleMap.new()
	_battle_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_battle_view.visible = false
	column.add_child(_battle_view)

	_panel = UI.panel()
	column.add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 420
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	_panel_body = UI.vbox(12)
	_panel_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_panel_body)


# --- Battle map --------------------------------------------------------------

func _battle_button(battle: Dictionary) -> Button:
	var id := int(battle.id)
	var button := UI.button("Battle map", func() -> void: _open_battle(id), "icon/troops")
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
		_panel_body.add_child(UI.label("That battle is no longer in the reports.", UI.SMALL_SIZE, UI.MUTED))
		_panel_body.add_child(UI.button("Back to the map", func() -> void: _set_view("map"), "icon/map"))
		return
	var count: int = battle.rounds.size()
	_battle_round = clampi(_battle_round, 0, count)
	var ctx := _battle_ctx(battle)
	_battle_view.show_battle(Game.data, battle, _battle_round, ctx)
	_panel_body.add_child(UI.label("Battle at %s" % ctx.place, UI.HEADING_SIZE))
	var row := UI.hbox(8)
	var back := UI.button("◀", func() -> void:
		_battle_playing = false
		_battle_round -= 1
		_rebuild_panel())
	back.disabled = _battle_round <= 0
	row.add_child(back)
	var where := UI.label("Before the battle" if _battle_round == 0 else "Round %d of %d" % [_battle_round, count])
	where.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	where.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(where)
	var next := UI.button("▶", func() -> void:
		_battle_playing = false
		_battle_round += 1
		_rebuild_panel())
	next.disabled = _battle_round >= count
	row.add_child(next)
	var play := UI.button("Pause" if _battle_playing else "Play", func() -> void:
		_battle_playing = not _battle_playing
		if _battle_playing and _battle_round >= count:
			_battle_round = 0
		_battle_clock = 0.0
		_rebuild_panel())
	row.add_child(play)
	_panel_body.add_child(row)
	var story := BattleStory.opening(Game.data, battle, ctx) if _battle_round == 0 else BattleStory.narrate(Game.data, battle, _battle_round, ctx)
	_panel_body.add_child(UI.label(story))
	if battle.status == "ongoing" and _battle_round >= count:
		_panel_body.add_child(UI.label("The fight goes on; the next round comes in %s." % TimeUtil.format_duration(float(Game.data.battle.roundMinutes) * 60.0 / float(Game.world.speed)), UI.SMALL_SIZE, UI.MUTED))
	_panel_body.add_child(UI.button("Back to the map", func() -> void: _set_view("map"), "icon/map"))


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
	var ctx := {
		"place": Game.battle_place(battle),
		"enemy": ("the " + Game.front_faction(front)) if front != "" else "the enemy",
		"enemy_leader": "Their chief",
		"from": front.capitalize() if front != "" else "wilds",
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


# --- Selection panel ---------------------------------------------------------

func _select(cell: Vector2i) -> void:
	_selected = cell
	var village := Game.village_at(cell)
	if not village.is_empty() and Game.commands(village):
		Game.current_village_id = int(village.id)
	_panel_mode = "hex"
	hex_map.select(cell)
	_rebuild_panel()


func _toggle_view() -> void:
	_set_view("village" if _view == "map" else "map")


func _set_view(view: String) -> void:
	_view = view
	var on_map := view == "map"
	_view_button.text = "Village" if on_map else "Map"
	_view_button.icon = Art.texture("icon/village" if on_map else "icon/map")
	hex_map.visible = on_map
	_spacer.visible = on_map
	_village_view.visible = view == "village"
	_battle_view.visible = view == "battle"
	_battle_playing = _battle_playing and view == "battle"
	# The map camera listens for unhandled input; keep it still while the
	# village or a battle is open.
	camera.set_process_unhandled_input(on_map)
	_panel_mode = "hex"
	_rebuild_panel()


func _on_plot_tapped(plot: String) -> void:
	_plot = plot
	_tab = "village"
	_panel_mode = "hex"
	_rebuild_panel()


func _show_threats() -> void:
	_panel_mode = "run" if RunText.is_over(Game.world) else "threats"
	_rebuild_panel()


func _open_run_once() -> void:
	if RunText.is_over(Game.world) and not _run_seen:
		_run_seen = true
		_panel_mode = "run"


## The next getting-started step, on your own villages.
func _onboarding_card(village: Dictionary) -> void:
	if not Game.is_mine(village) or Game.world.get("status") != "running":
		return
	for member in Game.world.get("members", []):
		if int(member.accountId) != Game.my_account_id():
			continue
		var step := OnboardingText.next_step(Game.data, member)
		if step.is_empty():
			return
		_panel_body.add_child(UI.label("%s: %s" % [OnboardingText.progress(Game.data, member), step.title], 0, Color("#e8d9a8")))
		_panel_body.add_child(UI.label(step.story, UI.SMALL_SIZE, UI.MUTED))
		_panel_body.add_child(UI.label("%s %s" % [step.hint, OnboardingText.reward(step)], UI.SMALL_SIZE))


var _almanac_section := "Units"


## The almanac: units, buildings, stances, hordes, clans, terrain and the run.
func _almanac_panel() -> void:
	_panel_body.add_child(UI.label("Almanac", UI.HEADING_SIZE))
	var picker := UI.options(AlmanacText.SECTIONS, AlmanacText.SECTIONS.find(_almanac_section))
	picker.item_selected.connect(func(i: int) -> void:
		_almanac_section = AlmanacText.SECTIONS[i]
		_rebuild_panel())
	_panel_body.add_child(picker)
	for entry in AlmanacText.entries(Game.data, _almanac_section):
		_panel_body.add_child(UI.label(entry[0]))
		_panel_body.add_child(UI.label(entry[1], UI.SMALL_SIZE, UI.MUTED))
	_panel_body.add_child(UI.button("Back", func() -> void:
		_panel_mode = "threats"
		_rebuild_panel()))


## "You command this for Mila until …" on a village handed to you.
func _handed_line(village: Dictionary) -> void:
	if Game.is_mine(village):
		return
	var d := DelegationText.of_owner(Game.delegations, int(village.ownerAccountId), Game.server_now())
	if d.is_empty():
		return
	_panel_body.add_child(UI.label("You command it for %s for %s more; they see what you do." % [Game.member_name(int(d.ownerAccountId)), TimeUtil.format_duration(TimeUtil.parse_iso(d.until) - Game.server_now())], UI.SMALL_SIZE, Color("#e8d9a8")))


## Hand-overs: give your villages to a teammate while away, take them back,
## and what delegates did lately.
func _delegation_section() -> void:
	if Game.world.get("status") != "running":
		return
	var me := Game.my_account_id()
	var now := Game.server_now()
	_panel_body.add_child(UI.label("Hand-overs", UI.HEADING_SIZE))
	var mine := DelegationText.of_owner(Game.delegations, me, now)
	if not mine.is_empty():
		_panel_body.add_child(UI.label("%s commands your villages for %s more." % [Game.member_name(int(mine.delegateAccountId)), TimeUtil.format_duration(TimeUtil.parse_iso(mine.until) - now)], UI.SMALL_SIZE))
		_panel_body.add_child(UI.button("Take them back", func() -> void: _end_delegation(me)))
	for owner in DelegationText.owners_for(Game.delegations, me, now):
		var d := DelegationText.of_owner(Game.delegations, owner, now)
		_panel_body.add_child(UI.label("You command %s's villages for %s more." % [Game.member_name(owner), TimeUtil.format_duration(TimeUtil.parse_iso(d.until) - now)], UI.SMALL_SIZE))
		_panel_body.add_child(UI.button("Hand them back", func() -> void: _end_delegation(owner)))
	var others: Array = Game.world.get("members", []).filter(func(m: Dictionary) -> bool: return int(m.accountId) != me)
	if mine.is_empty() and not others.is_empty():
		_panel_body.add_child(UI.label("Away for a while? Hand your villages to a teammate for 1–7 days.", UI.SMALL_SIZE, UI.MUTED))
		var row := UI.hbox(8)
		var who := UI.options(others.map(func(m: Dictionary) -> String: return m.displayName), 0)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(who)
		var days := UI.options(["1 day", "2 days", "3 days", "4 days", "5 days", "6 days", "7 days"], 1)
		row.add_child(days)
		_panel_body.add_child(row)
		_panel_body.add_child(UI.button("Hand over", func() -> void: _delegate(int(others[who.selected].accountId), days.selected + 1)))
	var names := {}
	for m in Game.world.get("members", []):
		names[int(m.accountId)] = m.displayName
	var village_names := {}
	for v in Game.villages.values():
		village_names[int(v.id)] = v.name
	for e in Game.delegation_log.slice(0, 8):
		_panel_body.add_child(UI.label("%s · %s ago" % [DelegationText.entry(e, names, village_names), TimeUtil.format_duration(now - TimeUtil.parse_iso(e.at))], UI.SMALL_SIZE, UI.MUTED))


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
	for member in Game.world.get("members", []):
		_panel_body.add_child(UI.label("%s: %s" % [member.displayName, ClanText.title(Game.data, member.get("clan"))], UI.SMALL_SIZE, UI.MUTED))
	var me: Dictionary = {}
	for member in Game.world.get("members", []):
		if int(member.accountId) == Game.my_account_id():
			me = member
	if me.is_empty() or me.get("clan") != null or RunText.is_over(Game.world):
		return
	_panel_body.add_child(UI.label("Pick your clan: its perks go to all your villages, for the rest of this run.", UI.SMALL_SIZE))
	for clan in ClanText.ids(Game.data):
		var pick := UI.button(ClanText.title(Game.data, clan), func() -> void: _pick_clan(clan))
		_panel_body.add_child(pick)
		_panel_body.add_child(UI.label(ClanText.perks(Game.data, clan), UI.SMALL_SIZE, UI.MUTED))


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
	_panel_body.add_child(UI.label(ending.title, UI.HEADING_SIZE, Color("#e8d9a8") if won else Color("#ffb4a8")))
	_panel_body.add_child(UI.label(ending.story, UI.SMALL_SIZE, UI.MUTED))
	var run: Variant = Game.world.get("run")
	if run is Dictionary:
		for line in RunText.stats(run):
			_panel_body.add_child(UI.label(line, UI.SMALL_SIZE))
		_panel_body.add_child(UI.label("The group", UI.HEADING_SIZE))
		for member in run.members:
			_panel_body.add_child(UI.label(RunText.member_line(member), UI.SMALL_SIZE))
	_panel_body.add_child(UI.label("The world stays open to look around, but nothing more can be done in it.", UI.SMALL_SIZE, UI.MUTED))
	var row := UI.hbox(8)
	var look := UI.button("Look at the map", func() -> void:
		_panel_mode = "hex"
		_rebuild_panel())
	look.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(look)
	var back := UI.button("Back to worlds", _leave)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(back)
	_panel_body.add_child(row)


func _rebuild_panel() -> void:
	UI.clear(_panel_body)
	_ticking.clear()
	if _panel_mode == "run":
		_run_panel()
		return
	if _panel_mode == "almanac":
		_almanac_panel()
		return
	if _panel_mode == "threats":
		_threats_panel()
		return
	if _panel_mode == "hero":
		_hero_panel()
		return
	if _panel_mode == "inbox":
		_inbox_panel()
		return
	if _view == "village":
		_village_panel()
		return
	if _view == "battle":
		_battle_panel()
		return
	for wave in WaveMath.visible_waves(Game.waves):
		if WaveMath.current_hex(wave, Game.server_now()) == _selected:
			_wave_entry(wave)
	var village := Game.village_at(_selected)
	if village.is_empty():
		_terrain_panel()
	elif Game.commands(village):
		_own_village_panel(village)
	else:
		_ally_village_panel(village)
	_river_section(_selected)
	_road_section(_selected)


func _terrain_panel() -> void:
	var id: String = Game.terrain.get(_selected, "")
	_panel_body.add_child(UI.label(Terrain.display_name(id, Game.data), UI.HEADING_SIZE))
	var distance := HexMath.distance(_selected, Vector2i.ZERO)
	var where := "The Holy City." if distance == 0 else "%d hex%s from the Holy City." % [distance, "" if distance == 1 else "es"]
	_panel_body.add_child(UI.label(where, UI.SMALL_SIZE, UI.MUTED))
	var camp := Game.camp_at(_selected)
	if not camp.is_empty():
		_panel_body.add_child(UI.label(HordeText.camp(camp, Game.front_faction(camp.front)), UI.SMALL_SIZE, Color("#ffb4a8")))
	if Game.fear.has(_selected):
		_panel_body.add_child(UI.label("Hordes fear this place: they were beaten here (%.0f)." % Game.fear[_selected], UI.SMALL_SIZE, UI.MUTED))
	if id == "holy_city":
		_panel_body.add_child(UI.label(HordeText.sanctity(Game.world, Game.data), UI.SMALL_SIZE, UI.MUTED))
		_bridge_panel()
		_vault_panel()
		return
	var holder := Game.outpost_owner(_selected)
	if not holder.is_empty():
		_outpost_panel(holder, Rules.outpost_plot(_selected))
	elif camp.is_empty() and Game.site_at(_selected).is_empty():
		_claim_panel(id)
		_found_panel(id)
	_hold_panel(id)


## An outpost on the selected hex: what it gathers; yours can be upgraded,
## rebuilt from ruins or abandoned.
func _outpost_panel(holder: Dictionary, plot: String) -> void:
	var holds: Dictionary = holder.plots[plot]
	var level := int(holds.level)
	var mine := Game.is_mine(holder)
	var who := "Yours" if mine else Game.member_name(int(holder.ownerAccountId))
	var planned := Rules.planned_plot(holder, plot)
	var state := "Lv %d" % level
	if level == 0:
		state = "being built" if int(planned.level) > 0 else "in ruins"
	_panel_body.add_child(UI.label("Outpost  %s" % state, UI.HEADING_SIZE))
	_panel_body.add_child(UI.label("%s · supplies %s" % [who, holder.name], UI.SMALL_SIZE, UI.MUTED))
	var speed := float(Game.world.speed)
	var terrain: String = holds.get("terrain", "")
	var gathering := _yield_text(Rules.outpost_yield(Game.data, terrain, level, speed))
	var line := "Gathers %s" % gathering if level > 0 else "Gathers nothing until built"
	if holder.get("besieged", false) and level > 0:
		line += " (not while %s is under siege)" % holder.name
	_panel_body.add_child(UI.label(line, UI.SMALL_SIZE, UI.MUTED))
	if not mine:
		return
	var def := _building_def(Rules.OUTPOST)
	var target := int(planned.level) + 1
	if target <= int(def.maxLevel):
		_panel_body.add_child(UI.label("At level %d: %s" % [target, _yield_text(Rules.outpost_yield(Game.data, terrain, target, speed))], UI.SMALL_SIZE, UI.MUTED))
		_build_row(holder, plot, Rules.OUTPOST, target, "Rebuild" if level == 0 and int(planned.level) == 0 else "Upgrade")
	else:
		_panel_body.add_child(UI.label("Max level", UI.SMALL_SIZE, UI.MUTED))
	if int(planned.level) == level:
		var cell := _selected
		var village_id := int(holder.id)
		_panel_body.add_child(UI.button("Abandon outpost", func() -> void: _abandon_outpost(village_id, cell)))


## The Kalinov Bridge: the stage being built, its story, what it still
## needs and its quests; donations come from the vault.
func _bridge_panel() -> void:
	var bridge := Game.bridge
	if bridge.is_empty():
		return
	_panel_body.add_child(UI.label("Kalinov Bridge", UI.HEADING_SIZE))
	_panel_body.add_child(UI.label(Game.data.bridge.story, UI.SMALL_SIZE, UI.MUTED))
	_panel_body.add_child(UI.label(BridgeText.title(Game.data, bridge)))
	var stage := BridgeText.stage_def(Game.data, bridge)
	if stage.is_empty():
		return
	_panel_body.add_child(UI.label(stage.story, UI.SMALL_SIZE, UI.MUTED))
	_panel_body.add_child(UI.label(BridgeText.progress(Game.data, bridge), UI.SMALL_SIZE))
	for quest in BridgeText.quests(Game.data, bridge):
		_panel_body.add_child(UI.label(("✓ " if quest[0] else "○ ") + String(quest[1]), UI.SMALL_SIZE, UI.MUTED if quest[0] else Color("#e8d9a8")))
		_panel_body.add_child(UI.label(quest[2], UI.SMALL_SIZE, UI.MUTED))
	if bridge.status == "raising":
		var line := UI.label("", UI.SMALL_SIZE)
		_panel_body.add_child(line)
		var done_at := TimeUtil.parse_iso(bridge.raisedAt)
		_tick(line, func() -> String: return "Being raised · stands in %s" % TimeUtil.format_duration(done_at - Game.server_now()))
		return
	var row := UI.hbox(8)
	var give := UI.button("Give from the vault", func() -> void: _donate_bridge(Game.vault.get("amounts", {}), 0))
	give.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(give)
	if BridgeText.embers_missing(Game.data, bridge) > 0 and int(Game.world.get("embers", 0)) > 0:
		var ember := UI.button("Give an Ember", func() -> void: _donate_bridge({}, 1))
		ember.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(ember)
	var ritual_open := false
	for quest in stage.quests:
		ritual_open = ritual_open or (quest.kind == "ritual" and not bridge.quests.has("ritual"))
	if ritual_open:
		var forge := UI.button("Forge the torc", func() -> void: _forge_torc())
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
		return
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
	_panel_body.add_child(UI.label("Vault  Lv %d" % level, UI.HEADING_SIZE))
	_panel_body.add_child(UI.label("Shared by the group. Caravans bring resources in and out.", UI.SMALL_SIZE, UI.MUTED))
	var parts := PackedStringArray()
	for kind in Ledger.KINDS:
		parts.append("%s %d" % [kind.capitalize(), int(vault.amounts[kind])])
	_panel_body.add_child(UI.label("  ".join(parts) + "   (of %d each)" % capacity, UI.SMALL_SIZE))
	_panel_body.add_child(UI.label("Svarog's Ember: %d (from lairs)" % int(Game.world.get("embers", 0)), UI.SMALL_SIZE, UI.MUTED))
	if vault.upgradingTo != null:
		var done_at := TimeUtil.parse_iso(vault.upgradeCompletesAt)
		var line := UI.label("", UI.SMALL_SIZE, UI.MUTED)
		_panel_body.add_child(line)
		_tick(line, func() -> String:
			return "Growing to level %d · %s" % [int(vault.upgradingTo), TimeUtil.format_duration(done_at - Game.server_now())])
	elif level < int(Game.data.logistics.vault.maxLevel):
		var cost := CaravanMath.vault_upgrade_cost(Game.data, level + 1)
		var row := UI.hbox()
		var info := UI.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UI.label("Vault → Lv %d (paid from the vault)" % (level + 1)))
		var seconds := CaravanMath.vault_upgrade_seconds(Game.data, level + 1, float(Game.world.speed))
		info.add_child(UI.rich("%s · %s" % [UI.costs(cost), TimeUtil.format_duration(seconds)]))
		row.add_child(info)
		var button := UI.button("Enlarge", _upgrade_vault)
		button.custom_minimum_size.x = 160
		button.disabled = not Ledger.can_afford(vault.amounts, cost)
		row.add_child(button)
		_panel_body.add_child(row)
	if not _my_village().is_empty():
		_panel_body.add_child(UI.button("Send or fetch by caravan", func() -> void: _open_caravans(0)))


func _upgrade_vault() -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/worlds/%d/vault/upgrade" % Game.world_id(), {})
	if not response.ok:
		_status.text = response.error
		return
	Game.note_server_time(response.data.serverTime)


## Opens your village's caravan tab, headed for `destination` (0: vault).
func _open_caravans(destination: int) -> void:
	_caravan_to = destination
	_tab = "caravans"
	_set_view("village")


func _caravans_section(village: Dictionary) -> void:
	var village_id := int(village.id)
	var yard := int(village.levels.get("caravan_yard", 0))
	var capacity := CaravanMath.capacity(Game.data, village.get("bonuses", {}))
	if yard < 1:
		_panel_body.add_child(UI.label("Build a Caravan Yard in the village to send caravans to allies and the Holy City vault.", UI.SMALL_SIZE, UI.MUTED))
	else:
		var free := CaravanMath.available(Game.data, village, Game.caravans)
		var total := yard * int(Game.data.logistics.caravan.caravansPerYardLevel)
		_panel_body.add_child(UI.label("%d of %d caravans at home · %d each" % [free, total, capacity], UI.SMALL_SIZE, UI.MUTED))
		_caravan_form(village, free)
	_caravan_trips(village_id)
	_surplus_order(village_id)


func _caravan_form(village: Dictionary, free: int) -> void:
	var village_id := int(village.id)
	var destinations := [[0, "Holy City vault"]]
	for other in Game.villages.values():
		if int(other.id) != village_id:
			destinations.append([int(other.id), "%s (%s)" % [other.name, Game.member_name(int(other.ownerAccountId))]])
	var labels := destinations.map(func(d: Array) -> String: return d[1])
	var selected := 0
	for i in destinations.size():
		if destinations[i][0] == _caravan_to:
			selected = i
	var picker := UI.options(labels, selected)
	picker.item_selected.connect(func(index: int) -> void:
		_caravan_to = destinations[index][0]
		_rebuild_panel())
	_panel_body.add_child(picker)

	var amounts := Ledger.amounts_at(village.resources, Game.server_now())
	for kind in Ledger.KINDS:
		var row := UI.hbox(8)
		var amount_label := UI.label("%s %d" % [kind.capitalize(), _caravan_load[kind]])
		amount_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(amount_label)
		for step in [-500, -100, 100, 500]:
			var stepper := UI.button(("%+d" % step).replace("-", "−"), func() -> void:
				_caravan_load[kind] = clampi(_caravan_load[kind] + step, 0, 1_000_000)
				_rebuild_panel())
			stepper.custom_minimum_size.x = 84
			stepper.add_theme_font_size_override("font_size", UI.SMALL_SIZE)
			row.add_child(stepper)
		_panel_body.add_child(row)

	var needed := CaravanMath.needed(Game.data, _caravan_load, village.get("bonuses", {}))
	var summary := "Needs %d caravan%s" % [needed, "" if needed == 1 else "s"] if needed > 0 else "Pick what to carry"
	_panel_body.add_child(UI.label(summary, UI.SMALL_SIZE, UI.MUTED))
	if not Game.camps.is_empty():
		_panel_body.add_child(UI.label("Camps ambush caravans passing close. Escort (optional):", UI.SMALL_SIZE, UI.MUTED))
	var escort := _unit_pickers(Rules.garrison_at(village, Game.server_now())) if not Game.camps.is_empty() else {}
	var buttons := UI.hbox()
	var cargo := _caravan_load.duplicate()
	var send := UI.button("Send", func() -> void: _send_caravan(village_id, _caravan_to, cargo, escort))
	send.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	send.disabled = needed == 0 or needed > free or not Ledger.can_afford(amounts, cargo)
	buttons.add_child(send)
	if _caravan_to == 0:
		var fetch := UI.button("Fetch from vault", func() -> void: _fetch_from_vault(village_id, cargo, escort))
		fetch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fetch.disabled = needed == 0 or needed > free
		buttons.add_child(fetch)
	_panel_body.add_child(buttons)


## Trips from this village, and deliveries on their way to it.
func _caravan_trips(village_id: int) -> void:
	var trips := Game.caravans.filter(func(c: Dictionary) -> bool:
		return int(c.villageId) == village_id or (c.destinationVillageId != null and int(c.destinationVillageId) == village_id))
	if trips.is_empty():
		return
	_panel_body.add_child(UI.label("On the road", UI.SMALL_SIZE, UI.MUTED))
	for caravan in trips:
		var line := UI.label("", UI.SMALL_SIZE)
		_panel_body.add_child(line)
		_tick(line, func() -> String: return CaravanText.describe(caravan, village_id, Game.server_now()))
		var ambushed := HordeText.ambush(caravan.get("ambush"))
		if ambushed != "":
			_panel_body.add_child(UI.label(ambushed, UI.SMALL_SIZE, Color("#ffb4a8")))


func _send_caravan(village_id: int, destination: int, cargo: Dictionary, escort: Dictionary) -> void:
	_status.text = ""
	var body := {"destinationVillageId": destination if destination != 0 else null, "load": cargo, "escort": escort}
	var response := await Api.post_json("/v1/villages/%d/caravans" % village_id, body)
	if not response.ok:
		_status.text = response.error
		return
	_caravan_load = {"wood": 0, "stone": 0, "grain": 0, "iron": 0}
	_army_units.clear()
	Game.note_server_time(response.data.serverTime)
	Game.update_village(response.data.village)


func _fetch_from_vault(village_id: int, cargo: Dictionary, escort: Dictionary) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/caravans/fetch" % village_id, {"load": cargo, "escort": escort})
	if not response.ok:
		_status.text = response.error
		return
	_caravan_load = {"wood": 0, "stone": 0, "grain": 0, "iron": 0}
	Game.note_server_time(response.data.serverTime)
	Game.update_village(response.data.village)


## Your research: what you study now, then every branch of the tree. Shows
## which teammates know each tech, so the group can specialize.
func _research_section(village: Dictionary) -> void:
	var village_id := int(village.id)
	var academy := int(village.levels.get("academy", 0))
	var mine := ResearchRules.progress(Game.research, Game.my_account_id())
	var done: Dictionary = mine.done
	var current: Dictionary = mine.current
	var techs: Dictionary = Game.data.research.techs
	if academy < 1:
		_panel_body.add_child(UI.label("Build an Academy to research. Research belongs to you and helps all your villages.", UI.SMALL_SIZE, UI.MUTED))
	else:
		_panel_body.add_child(UI.label("Academy Lv %d · %d of %d techs known" % [academy, done.size(), techs.size()], UI.SMALL_SIZE, UI.MUTED))
	if not current.is_empty():
		var done_at := TimeUtil.parse_iso(current.completesAt)
		var line := UI.label("", UI.SMALL_SIZE)
		_panel_body.add_child(line)
		var tech_name: String = techs[current.tech].name
		_tick(line, func() -> String: return "Researching %s · %s" % [tech_name, TimeUtil.format_duration(done_at - Game.server_now())])
	if not Game.lore.is_empty():
		_panel_body.add_child(UI.label("Lore scrolls of the group", UI.HEADING_SIZE))
		for entry in Game.lore:
			var def: Dictionary = Game.data.lore.scrolls.get(entry.scroll, {})
			var finder := Game.member_name(int(entry.accountId)) if entry.get("accountId") != null else "?"
			_panel_body.add_child(UI.label("%s (found by %s)" % [def.get("name", entry.scroll), finder]))
			_panel_body.add_child(UI.label(SiteText.scroll_effect(Game.data, entry.scroll), UI.SMALL_SIZE, UI.MUTED))
	var speed := float(Game.world.speed)
	for branch in Game.data.research.branches:
		_panel_body.add_child(UI.label(Game.data.research.branches[branch], UI.HEADING_SIZE))
		for tech in techs:
			var def: Dictionary = techs[tech]
			if def.branch != branch:
				continue
			var info := UI.vbox(2)
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var known := done.has(tech)
			info.add_child(UI.label(("✓ " if known else "") + String(def.name)))
			info.add_child(UI.label(def.description, UI.SMALL_SIZE, UI.MUTED))
			var others := _who_knows(tech)
			if not others.is_empty():
				info.add_child(UI.label("Known by %s" % ", ".join(others), UI.SMALL_SIZE, UI.MUTED))
			var row := UI.hbox()
			row.add_child(info)
			_panel_body.add_child(row)
			if known or (not current.is_empty() and current.tech == tech):
				continue
			var problem := ResearchRules.problem(Game.data, tech, academy, done, not current.is_empty(), Game.scrolls())
			var cost: Dictionary = def.cost
			var cost_line := UI.rich()
			info.add_child(cost_line)
			var duration := TimeUtil.format_duration(float(def.seconds) / speed)
			var cost_text := "%s · %s" % [UI.costs(cost), duration]
			if problem != "":
				cost_line.text = "%s  (%s)" % [cost_text, problem.trim_suffix(".").to_lower()]
				continue
			var button := UI.button("Research", func() -> void: _start_research(village_id, tech))
			button.custom_minimum_size.x = 160
			row.add_child(button)
			_tick(cost_line, func() -> String:
				var home: Dictionary = Game.villages.get(village_id, village)
				button.disabled = not Ledger.can_afford(Ledger.amounts_at(home.resources, Game.server_now()), cost)
				return cost_text)


func _who_knows(tech: String) -> PackedStringArray:
	var names := PackedStringArray()
	for entry in Game.research:
		if entry.tech == tech and entry.status == "done" and int(entry.accountId) != Game.my_account_id():
			names.append(Game.member_name(int(entry.accountId)))
	return names


func _start_research(village_id: int, tech: String) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/research" % village_id, {"tech": tech})
	if not response.ok:
		_status.text = response.error
		return
	Game.note_server_time(response.data.serverTime)
	Game.update_village(response.data.village)


# --- Armies ------------------------------------------------------------------

func _armies_section(village: Dictionary) -> void:
	var village_id := int(village.id)
	var defs: Dictionary = Game.data.units.units
	# Armies from this village, and allies' troops standing guard here.
	for army in Game.armies:
		var mine: bool = int(army.homeVillageId) == village_id and army.status != "done"
		var guarding: bool = army.targetVillageId != null and int(army.targetVillageId) == village_id and army.status in ["stationed", "engaged"] and int(army.homeVillageId) != village_id
		if not mine and not guarding:
			continue
		var row := UI.hbox()
		var info := UI.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UI.label(ArmyText.units_text(army.units, defs), UI.SMALL_SIZE))
		var line := UI.label("", UI.SMALL_SIZE, UI.MUTED)
		info.add_child(line)
		var target_name := ArmyText.target_name(army, Game.village_name)
		var from_name := Game.village_name(army.homeVillageId)
		if mine:
			_tick(line, func() -> String: return ArmyText.status(army, target_name, Game.server_now()))
		else:
			line.text = "From %s, standing guard here" % from_name
		row.add_child(info)
		if mine and army.status == "stationed":
			var army_id := int(army.id)
			var recall := UI.button("Call home", func() -> void: _recall_army(army_id))
			recall.custom_minimum_size.x = 150
			row.add_child(recall)
		_panel_body.add_child(row)

	var home_units := Rules.garrison_at(village, Game.server_now())
	var targets := Game.villages.values().filter(func(v: Dictionary) -> bool: return int(v.id) != village_id)
	if targets.is_empty():
		return
	_panel_body.add_child(UI.label("Send troops", UI.SMALL_SIZE, UI.MUTED))
	var labels := targets.map(func(v: Dictionary) -> String: return "%s (%s)" % [v.name, Game.member_name(int(v.ownerAccountId))])
	var selected := 0
	for i in targets.size():
		if int(targets[i].id) == _army_to:
			selected = i
	_army_to = int(targets[selected].id)
	var picker := UI.options(labels, selected)
	picker.item_selected.connect(func(i: int) -> void:
		_army_to = int(targets[i].id)
		_rebuild_panel())
	_panel_body.add_child(picker)
	if _army_orders == "hold":
		_army_orders = "support"
	var kinds := ["support", "reinforce", "harass"]
	var kind_row := UI.hbox(8)
	for kind in kinds:
		var b := UI.button(String(kind).capitalize(), func() -> void:
			_army_orders = kind
			_rebuild_panel())
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = _army_orders == kind
		kind_row.add_child(b)
	_panel_body.add_child(kind_row)
	_panel_body.add_child(UI.label(ArmyText.ORDERS[_army_orders], UI.SMALL_SIZE, UI.MUTED))
	var chosen := _unit_pickers(home_units)
	var body := {"targetVillageId": _army_to, "units": chosen, "orders": _army_orders}
	var go := UI.button("Send", func() -> void: _send_army(village_id, body))
	go.disabled = chosen.is_empty()
	_panel_body.add_child(go)

	var rule: Dictionary = village.get("reinforce", {}) if village.get("reinforce") != null else {}
	if rule.is_empty():
		return
	var share := roundi(float(rule.share) * 100.0)
	var range_ := int(rule.range)
	_panel_body.add_child(UI.label("When a battle starts within %d hexes, send %d%% of the troops here to help." % [range_, share] if share > 0 else "This village doesn't send help to battles nearby.", UI.SMALL_SIZE, UI.MUTED))
	var rule_row := UI.hbox(8)
	for option in [0, 25, 50, 75]:
		var b := UI.button("%d%%" % option, func() -> void: _set_reinforce(village_id, option / 100.0, range_))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = option == share
		rule_row.add_child(b)
	for step in [-1, 1]:
		var b := UI.button(("%+d hex" % step).replace("-", "−"), func() -> void:
			_set_reinforce(village_id, share / 100.0, clampi(range_ + step, 0, int(Game.data.armies.reinforce.maxRange))))
		b.add_theme_font_size_override("font_size", UI.SMALL_SIZE)
		rule_row.add_child(b)
	_panel_body.add_child(rule_row)


## Steppers for each fighting unit at home; returns the troops picked.
func _unit_pickers(home_units: Dictionary, with_scouts := false) -> Dictionary:
	var defs: Dictionary = Game.data.units.units
	var families := ["infantry", "archers", "cavalry", "scout"] if with_scouts else ["infantry", "archers", "cavalry"]
	for unit in home_units:
		var def: Dictionary = defs.get(unit, {})
		if def.is_empty() or not def.family in families or unit == "settler":
			continue
		var have := int(home_units[unit])
		var count := clampi(int(_army_units.get(unit, 0)), 0, have)
		var row := UI.hbox(8)
		var label := UI.label("%s %d / %d" % [def.name, count, have], UI.SMALL_SIZE)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		for step in [-10, -1, 1, 10]:
			var stepper := UI.button(("%+d" % step).replace("-", "−"), func() -> void:
				_army_units[unit] = clampi(count + step, 0, have)
				_rebuild_panel())
			stepper.custom_minimum_size.x = 80
			stepper.add_theme_font_size_override("font_size", UI.SMALL_SIZE)
			row.add_child(stepper)
		var all := UI.button("All", func() -> void:
			_army_units[unit] = have
			_rebuild_panel())
		all.custom_minimum_size.x = 80
		all.add_theme_font_size_override("font_size", UI.SMALL_SIZE)
		row.add_child(all)
		_panel_body.add_child(row)
	var chosen := {}
	for unit in _army_units:
		if int(_army_units[unit]) > 0 and home_units.has(unit):
			chosen[unit] = mini(int(_army_units[unit]), int(home_units[unit]))
	return chosen


func _send_army(village_id: int, body: Dictionary) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/armies" % village_id, body)
	if not response.ok:
		_status.text = response.error
		return
	_army_units.clear()
	_army_hero = false
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
		_panel_body.add_child(UI.label(kind.get("name", "Ancient site"), UI.HEADING_SIZE))
		_panel_body.add_child(UI.label(kind.get("description", ""), UI.SMALL_SIZE, UI.MUTED))
		var explorer := Game.member_name(int(site.exploredBy)) if site.get("exploredBy") != null else "?"
		_panel_body.add_child(UI.label(SiteText.status(Game.data, site, explorer), UI.SMALL_SIZE, Color("#e8d9a8")))
	var title := "Explore it" if exploring else ("Hold this hex" if camp.is_empty() else "Clear this camp")
	_panel_body.add_child(UI.label(title, UI.HEADING_SIZE))
	if exploring:
		_panel_body.add_child(UI.label(ArmyText.ORDERS.explore, UI.SMALL_SIZE, UI.MUTED))
	if not camp.is_empty():
		_panel_body.add_child(UI.label(ArmyText.ORDERS.clear, UI.SMALL_SIZE, UI.MUTED))
	for line in FieldRules.ground(Game.data, Game.terrain, cell, fort, float(Game.world.speed)) if camp.is_empty() and not exploring else PackedStringArray():
		_panel_body.add_child(UI.label(line, UI.SMALL_SIZE, UI.MUTED))
	var defs: Dictionary = Game.data.units.units
	for army in Game.armies:
		if ArmyText.held_hex(army) != cell or army.status == "done":
			continue
		var row := UI.hbox()
		var info := UI.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var owner_name := Game.member_name(int(army.ownerAccountId)) if army.ownerAccountId != null else "?"
		info.add_child(UI.label("%s: %s" % [owner_name, ArmyText.units_text(army.units, defs)], UI.SMALL_SIZE))
		var line := UI.label("", UI.SMALL_SIZE, UI.MUTED)
		info.add_child(line)
		var where := ArmyText.target_name(army, Game.village_name)
		_tick(line, func() -> String: return ArmyText.status(army, where, Game.server_now()))
		row.add_child(info)
		if army.ownerAccountId != null and int(army.ownerAccountId) == Game.my_account_id() and army.status == "stationed":
			var army_id := int(army.id)
			var recall := UI.button("Call home", func() -> void: _recall_army(army_id))
			recall.custom_minimum_size.x = 150
			row.add_child(recall)
		_panel_body.add_child(row)

	var village_id := int(home.id)
	_panel_body.add_child(UI.label("Send from %s" % home.name, UI.SMALL_SIZE, UI.MUTED))
	var chosen := _unit_pickers(Rules.garrison_at(home, Game.server_now()), exploring)
	var hero := Game.my_hero()
	var hero_ready: bool = not hero.is_empty() and hero.status == "home" and hero.villageId != null and int(hero.villageId) == village_id
	if hero_ready:
		var lead := UI.button("%s leads it: %s" % [hero.name, "yes" if _army_hero else "no"], func() -> void:
			_army_hero = not _army_hero
			_rebuild_panel())
		_panel_body.add_child(lead)
	var body := {"target": {"q": cell.x, "r": cell.y}, "units": chosen, "orders": orders, "withHero": _army_hero and hero_ready}
	var go := UI.button({"explore": "Explore", "hold": "Hold this hex", "clear": "Storm it"}[orders], func() -> void: _send_army(village_id, body))
	go.disabled = chosen.is_empty()
	_panel_body.add_child(go)

	if not fort.is_empty() or not camp.is_empty() or not site.is_empty():
		return
	var taken := not Game.village_at(cell).is_empty() or not Game.outpost_owner(cell).is_empty()
	var problem := FieldRules.fort_problem(Game.data, home, cell, terrain_id, taken)
	if problem != "":
		_panel_body.add_child(UI.label(problem, UI.SMALL_SIZE, UI.MUTED))
		return
	var cost := FieldRules.fort_cost(Game.data, home.get("bonuses", {}))
	var seconds := float(Game.data.field.fort.buildSeconds) / float(Game.world.speed)
	var row := UI.hbox()
	var info := UI.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(UI.label("Build a fort (+%d%% defense here)" % roundi(float(Game.data.field.fort.defenseBonus) * 100.0)))
	var cost_line := UI.rich()
	info.add_child(cost_line)
	row.add_child(info)
	var button := UI.button("Build fort", func() -> void: _build_fort(village_id, cell))
	button.custom_minimum_size.x = 160
	row.add_child(button)
	_panel_body.add_child(row)
	var cost_text := "%s · %s" % [UI.costs(cost), TimeUtil.format_duration(seconds)]
	_tick(cost_line, func() -> String:
		var current: Dictionary = Game.villages.get(village_id, home)
		button.disabled = not Ledger.can_afford(Ledger.amounts_at(current.resources, Game.server_now()), cost)
		return cost_text)


func _build_fort(village_id: int, cell: Vector2i) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/forts" % village_id, {"q": cell.x, "r": cell.y})
	if not response.ok:
		_status.text = response.error
		return
	Game.note_server_time(response.data.serverTime)


## Rivers along the selected hex: where bridges stand, and building more.
func _river_section(cell: Vector2i) -> void:
	var edges := RiverText.edges_at(Game.rivers, cell)
	if edges.is_empty():
		return
	_panel_body.add_child(UI.label("Rivers", UI.HEADING_SIZE))
	var home := _my_village()
	for e in edges:
		var other: Vector2i = e.other
		var text := "Towards (%d, %d): " % [other.x, other.y]
		match String(e.crossing):
			"standing":
				_panel_body.add_child(UI.label(text + "a bridge crosses here.", UI.SMALL_SIZE, UI.MUTED))
				continue
			"building":
				_panel_body.add_child(UI.label(text + "a bridge is being built.", UI.SMALL_SIZE, UI.MUTED))
				continue
		_panel_body.add_child(UI.label(text + "no way across. Hordes can't cross either.", UI.SMALL_SIZE, UI.MUTED))
		if home.is_empty():
			continue
		var problem := RiverText.bridge_problem(Game.data, Vector2i(int(home.q), int(home.r)), cell, other)
		if problem != "":
			_panel_body.add_child(UI.label(problem, UI.SMALL_SIZE, UI.MUTED))
			continue
		var cost: Dictionary = Game.data.field.bridge.cost
		var row := UI.hbox()
		var info := UI.rich("Build a bridge: %s · %s" % [UI.costs(cost), TimeUtil.format_duration(float(Game.data.field.bridge.buildSeconds) / float(Game.world.speed))], UI.SMALL_SIZE, UiTheme.TEXT)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var village_id := int(home.id)
		var target := other
		var button := UI.button("Build bridge", func() -> void: _build_crossing(village_id, cell, target))
		button.custom_minimum_size.x = 160
		row.add_child(button)
		_panel_body.add_child(row)


## Roads from the selected hex: where they run, and building more.
func _road_section(cell: Vector2i) -> void:
	if not Game.terrain.has(cell):
		return
	var home := _my_village()
	var roads := RiverText.roads_at(Game.roads, cell)
	var names := ["E", "NE", "NW", "W", "SW", "SE"]
	var open: Array[int] = []
	var built := PackedStringArray()
	for i in 6:
		var other: Vector2i = cell + HexMath.DIRECTIONS[i]
		if roads.has(other):
			built.append("%s%s" % [names[i], "" if roads[other] == "standing" else " (being built)"])
		elif not home.is_empty() and RiverText.road_problem(Game.data, Game.terrain, Game.rivers, Vector2i(int(home.q), int(home.r)), cell, other) == "":
			open.append(i)
	if built.is_empty() and open.is_empty():
		return
	_panel_body.add_child(UI.label("Roads", UI.HEADING_SIZE))
	_panel_body.add_child(UI.label("Roads halve the march for everyone on them, the human hordes too, but the beasts of the North keep off them.", UI.SMALL_SIZE, UI.MUTED))
	if not built.is_empty():
		_panel_body.add_child(UI.label("Roads run " + ", ".join(built) + ".", UI.SMALL_SIZE))
	if open.is_empty():
		return
	var cost: Dictionary = Game.data.field.road.cost
	_panel_body.add_child(UI.rich("Build a road (%s · %s each) towards:" % [UI.costs(cost), TimeUtil.format_duration(float(Game.data.field.road.buildSeconds) / float(Game.world.speed))], UI.SMALL_SIZE, UiTheme.TEXT))
	var row := UI.hbox(6)
	var village_id := int(home.id)
	for i in open:
		var other: Vector2i = cell + HexMath.DIRECTIONS[i]
		var button := UI.button(names[i], func() -> void: _build_road(village_id, cell, other))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(button)
	_panel_body.add_child(row)


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


func _recall_army(army_id: int) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/armies/%d/recall" % army_id, {})
	if not response.ok:
		_status.text = response.error


func _set_reinforce(village_id: int, share: float, range_: int) -> void:
	_status.text = ""
	var response := await Api.request(HTTPClient.METHOD_PUT, "/v1/villages/%d/reinforce" % village_id, {"share": share, "range": range_})
	if not response.ok:
		_status.text = response.error


# --- Standing orders ----------------------------------------------------------

## One standing order: what it does, what it last did, and a cancel button.
func _order_row(order: Dictionary) -> void:
	var row := UI.hbox()
	var info := UI.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(UI.label(OrderText.describe(order, Game.data.units.units), UI.SMALL_SIZE))
	if order.lastResult != null:
		info.add_child(UI.label("Last: %s" % order.lastResult, UI.SMALL_SIZE, UI.MUTED))
	row.add_child(info)
	var village_id := int(order.villageId)
	var order_id := int(order.id)
	var cancel := UI.button("Stop", func() -> void: _cancel_order(village_id, order_id))
	cancel.custom_minimum_size.x = 110
	row.add_child(cancel)
	_panel_body.add_child(row)


## Repeat training: one order per unit, keeping a target count.
func _repeat_order(village: Dictionary) -> void:
	var village_id := int(village.id)
	_panel_body.add_child(UI.label("Repeat training (checked every %d game minutes)" % int(Game.data.orders.checkMinutes), UI.SMALL_SIZE, UI.MUTED))
	for order in Game.orders_of(village_id, "train"):
		_order_row(order)
	var units: Dictionary = Game.data.units.units
	var names := units.keys()
	var picker := UI.options(names.map(func(u: String) -> String: return units[u].name), maxi(0, names.find(_repeat_unit)))
	picker.item_selected.connect(func(i: int) -> void:
		_repeat_unit = names[i]
		_rebuild_panel())
	_panel_body.add_child(picker)
	var row := UI.hbox(8)
	var text := UI.label("Keep %d, %d at a time" % [_repeat_target, _repeat_batch], UI.SMALL_SIZE)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	for step in [[-5, 0], [5, 0], [0, -1], [0, 1]]:
		var label := ("%+d" % step[0]) if step[0] != 0 else ("batch %+d" % step[1])
		var stepper := UI.button(label.replace("-", "−"), func() -> void:
			_repeat_target = clampi(_repeat_target + step[0], 1, 999)
			_repeat_batch = clampi(_repeat_batch + step[1], 1, mini(_repeat_target, int(Game.data.units.maxBatch)))
			_rebuild_panel())
		stepper.add_theme_font_size_override("font_size", UI.SMALL_SIZE)
		row.add_child(stepper)
	_panel_body.add_child(row)
	var unit := _repeat_unit
	var target := _repeat_target
	var batch := mini(_repeat_batch, _repeat_target)
	var place := UI.button("Keep %s topped up" % units[unit].name, func() -> void:
		_place_order(village_id, {"kind": "train", "unit": unit, "batch": batch, "target": target}))
	place.disabled = not Game.orders_of(village_id, "train").filter(func(o: Dictionary) -> bool: return o.unit == unit).is_empty()
	_panel_body.add_child(place)


func _rebuild_order(village_id: int) -> void:
	var existing := Game.orders_of(village_id, "rebuild")
	if existing.is_empty():
		_panel_body.add_child(UI.button("Rebuild raided outposts automatically", func() -> void: _place_order(village_id, {"kind": "rebuild"})))
	for order in existing:
		_order_row(order)


func _surplus_order(village_id: int) -> void:
	var existing := Game.orders_of(village_id, "surplus")
	_panel_body.add_child(UI.label("Surplus to the vault", UI.SMALL_SIZE, UI.MUTED))
	for order in existing:
		_order_row(order)
	if not existing.is_empty():
		return
	var limits: Dictionary = Game.data.orders.surplusShare
	var row := UI.hbox(8)
	var text := UI.label("Above %d%% of storage" % _surplus_share, UI.SMALL_SIZE)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	for step in [-5, 5]:
		var stepper := UI.button(("%+d%%" % step).replace("-", "−"), func() -> void:
			_surplus_share = clampi(_surplus_share + step, roundi(float(limits.min) * 100.0), roundi(float(limits.max) * 100.0))
			_rebuild_panel())
		stepper.custom_minimum_size.x = 100
		row.add_child(stepper)
	var share := _surplus_share
	var place := UI.button("Start", func() -> void: _place_order(village_id, {"kind": "surplus", "share": share / 100.0}))
	place.custom_minimum_size.x = 110
	row.add_child(place)
	_panel_body.add_child(row)


func _place_order(village_id: int, spec: Dictionary) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/orders" % village_id, spec)
	if not response.ok:
		_status.text = response.error
		return
	Game.note_server_time(response.data.serverTime)
	Game.update_village(response.data.village)


func _cancel_order(village_id: int, order_id: int) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/orders/%d/cancel" % [village_id, order_id], {})
	if not response.ok:
		_status.text = response.error


## Where your hero is, seen from a village, with the way to its panel.
func _hero_line(village_id: int) -> void:
	var hero := Game.my_hero()
	if hero.is_empty():
		return
	var row := UI.hbox()
	var text := UI.label("", UI.SMALL_SIZE, UI.MUTED)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var open := UI.button("Hero", func() -> void:
		_panel_mode = "hero"
		_rebuild_panel())
	open.custom_minimum_size.x = 120
	row.add_child(open)
	_panel_body.add_child(row)
	_tick(text, func() -> String: return HeroText.whereabouts(hero, village_id, Game.village_name(hero.villageId), Game.server_now()))


## Your hero: level, skills, gear and journeys.
func _hero_panel() -> void:
	var hero := Game.my_hero()
	if hero.is_empty():
		return
	var top := UI.hbox()
	var title := UI.label("%s  Lv %d" % [hero.name, int(hero.level)], UI.HEADING_SIZE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(UI.button("Close", func() -> void:
		_panel_mode = "hex"
		_rebuild_panel()))
	_panel_body.add_child(top)
	var status := UI.label("", UI.SMALL_SIZE)
	_panel_body.add_child(status)
	_tick(status, func() -> String: return HeroText.whereabouts(hero, -1, Game.village_name(hero.villageId), Game.server_now()))
	var xp_text := "XP %d / %d" % [int(hero.xp), int(hero.xpToNext)] if hero.xpToNext != null else "Highest level"
	_panel_body.add_child(UI.label("%s · %d skill point%s · XP comes from enemies slain while leading a garrison" % [xp_text, int(hero.skillPoints), "" if int(hero.skillPoints) == 1 else "s"], UI.SMALL_SIZE, UI.MUTED))
	var effects := HeroText.effects(hero.bonuses)
	if effects != "":
		_panel_body.add_child(UI.label("Adds where it stands: " + effects, UI.SMALL_SIZE, UI.MUTED))

	var data: Dictionary = Game.data.heroes
	for branch in data.branches:
		_panel_body.add_child(UI.label(data.branches[branch], UI.HEADING_SIZE))
		for skill in data.skills:
			var def: Dictionary = data.skills[skill]
			if def.branch != branch:
				continue
			var rank := int(hero.skills.get(skill, 0))
			var row := UI.hbox()
			var info := UI.vbox(2)
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			info.add_child(UI.label("%s  %d/%d" % [def.name, rank, int(def.maxRank)]))
			info.add_child(UI.label(def.description, UI.SMALL_SIZE, UI.MUTED))
			row.add_child(info)
			if rank < int(def.maxRank) and int(hero.skillPoints) > 0:
				var learn := UI.button("+", func() -> void: _hero_action("skills", {"skill": skill}))
				learn.custom_minimum_size.x = 90
				row.add_child(learn)
			_panel_body.add_child(row)

	_panel_body.add_child(UI.label("Gear", UI.HEADING_SIZE))
	for slot in data.slots:
		var item: Variant = hero.gear.get(slot)
		var row := UI.hbox()
		var label := UI.label("%s: %s" % [String(slot).capitalize(), data.items[item].name if item != null else "—"], UI.SMALL_SIZE)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		if item != null:
			var off := UI.button("Take off", func() -> void: _hero_action("unequip", {"slot": slot}))
			off.custom_minimum_size.x = 150
			row.add_child(off)
		_panel_body.add_child(row)
	if hero.inventory.is_empty():
		_panel_body.add_child(UI.label("Beaten hordes sometimes leave gear behind for a hero who fought them.", UI.SMALL_SIZE, UI.MUTED))
	for item in hero.inventory:
		var def: Dictionary = data.items[item]
		var row := UI.hbox()
		var info := UI.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UI.label("%s (%s)" % [def.name, def.slot]))
		info.add_child(UI.label(HeroText.effects(def.effects), UI.SMALL_SIZE, UI.MUTED))
		row.add_child(info)
		var wear := UI.button("Wear", func() -> void: _hero_action("equip", {"item": item}))
		wear.custom_minimum_size.x = 120
		row.add_child(wear)
		_panel_body.add_child(row)

	var mine := Game.my_villages().filter(func(v: Dictionary) -> bool: return Game.is_mine(v))
	if mine.size() > 1:
		_panel_body.add_child(UI.label("Send to", UI.HEADING_SIZE))
		for village in mine:
			if hero.villageId != null and int(hero.villageId) == int(village.id):
				continue
			var target := int(village.id)
			var go := UI.button(village.name, func() -> void: _hero_action("move", {"villageId": target}))
			go.disabled = hero.status != "home"
			_panel_body.add_child(go)
	var name_edit := UI.line_edit("New name", hero.name)
	_panel_body.add_child(name_edit)
	_panel_body.add_child(UI.button("Rename", func() -> void: _hero_action("rename", {"name": name_edit.text.strip_edges()})))


func _hero_action(action: String, body: Dictionary) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/worlds/%d/hero/%s" % [Game.world_id(), action], body)
	if not response.ok:
		_status.text = response.error
		return
	Game.note_server_time(response.data.serverTime)
	var updated: Dictionary = response.data.hero
	var heroes := Game.heroes.filter(func(h: Dictionary) -> bool: return int(h.accountId) != int(updated.accountId))
	heroes.append(updated)
	Game.set_heroes(Game.world_id(), heroes)


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
					return "Settlers on their way to found %s · %s" % [expedition.name, TimeUtil.format_duration(TimeUtil.parse_iso(expedition.arrivesAt) - now)]
				"returning":
					return "Settlers coming home (%s) · %s" % [String(expedition.failure).trim_suffix("."), TimeUtil.format_duration(TimeUtil.parse_iso(expedition.returnsAt) - now)]
				"founded":
					return "Founded %s" % expedition.name
			return "Settlers came home from (%d, %d)" % [int(expedition.q), int(expedition.r)])


## An empty settleable hex: can your village send settlers here?
func _found_panel(terrain: String) -> void:
	var home := _my_village()
	var def: Dictionary = Game.data.terrain.terrain.get(terrain, {})
	if home.is_empty() or not def.get("settleable", false):
		return
	var home_cell := Vector2i(int(home.q), int(home.r))
	var others := Game.villages.values().map(func(v: Dictionary) -> Vector2i: return Vector2i(int(v.q), int(v.r)))
	var problem := Rules.settle_problem(Game.data, _selected, terrain, home_cell, others, not Game.outpost_owner(_selected).is_empty())
	_panel_body.add_child(UI.label("Found a village", UI.HEADING_SIZE))
	if problem != "":
		_panel_body.add_child(UI.label(problem, UI.SMALL_SIZE, UI.MUTED))
		return
	var needed := int(Game.data.expansion.settlersNeeded)
	var at_home := int(Rules.garrison_at(home, Game.server_now()).get("settler", 0))
	_panel_body.add_child(UI.label("%d settlers from %s walk here and found it (%d at home). Train them in a Settlers' Lodge." % [needed, home.name, at_home], UI.SMALL_SIZE, UI.MUTED))
	var name_edit := UI.line_edit("Name (optional)")
	_panel_body.add_child(name_edit)
	var village_id := int(home.id)
	var cell := _selected
	var send := UI.button("Send settlers", func() -> void: _send_settlers(village_id, cell, name_edit.text))
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
	_panel_body.add_child(UI.label("An outpost here would gather %s." % _yield_text(Rules.outpost_yield(Game.data, terrain, 1, speed)), UI.SMALL_SIZE, UI.MUTED))
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
	info.add_child(UI.label("Build an outpost"))
	var cost_line := UI.rich()
	info.add_child(cost_line)
	row.add_child(info)
	var button := UI.button("Claim", func() -> void: _claim_outpost(village_id, cell))
	button.custom_minimum_size.x = 160
	row.add_child(button)
	_panel_body.add_child(row)
	var cost_text := "%s · %s" % [UI.costs(cost), TimeUtil.format_duration(seconds)]
	_tick(cost_line, func() -> String:
		var current: Dictionary = Game.villages.get(village_id, home)
		var affordable := Ledger.can_afford(Ledger.amounts_at(current.resources, Game.server_now()), cost)
		button.disabled = queue_full or not affordable
		return cost_text + ("  (queue full)" if queue_full else ""))


func _yield_text(amounts: Dictionary) -> String:
	var parts := PackedStringArray()
	for kind in Ledger.KINDS:
		if float(amounts[kind]) > 0.0:
			parts.append("%s +%d/h" % [kind.capitalize(), roundi(float(amounts[kind]))])
	return ", ".join(parts) if not parts.is_empty() else "nothing"


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
	_panel_body.add_child(UI.label("Ally: %s" % Game.member_name(int(village.ownerAccountId)), UI.SMALL_SIZE, UI.MUTED))
	for building in village.levels:
		_panel_body.add_child(UI.label("%s  Lv %d" % [_building_def(building).name, village.levels[building]]))
	var troops := UI.label("", UI.SMALL_SIZE, UI.MUTED)
	_panel_body.add_child(troops)
	_tick(troops, func() -> String: return _units_text(Rules.garrison_at(village, Game.server_now())))
	var their_hero := Game.hero_at(int(village.id))
	if not their_hero.is_empty():
		_panel_body.add_child(UI.label("Hero %s (Lv %d) leads the garrison" % [their_hero.name, int(their_hero.level)], UI.SMALL_SIZE, UI.MUTED))
	if not _my_village().is_empty():
		var ally_id := int(village.id)
		_panel_body.add_child(UI.button("Send resources", func() -> void: _open_caravans(ally_id)))


## Your village as seen on the map: a summary and the way in.
func _own_village_panel(village: Dictionary) -> void:
	_panel_body.add_child(UI.label(village.name, UI.HEADING_SIZE))
	_handed_line(village)
	_onboarding_card(village)
	var hall := Rules.hall_level(village)
	var queue: Array = village.queue
	_panel_body.add_child(UI.label("Elder's Hall Lv %d · building %d of %d · outposts %d of %d" % [hall, queue.size(), Rules.queue_limit(Game.data, hall),
		Rules.outpost_plots(village).size(), Rules.outpost_limit(Game.data, hall)], UI.SMALL_SIZE, UI.MUTED))
	if village.get("besieged", false):
		_panel_body.add_child(UI.label("Under siege: outposts produce nothing until the battle ends.", UI.SMALL_SIZE, UI.ERROR))
	if village.get("ruin") is Dictionary:
		_panel_body.add_child(UI.label("In ruins: rebuild it from the village view.", UI.SMALL_SIZE, UI.ERROR))
	if village.get("refuge", false):
		_panel_body.add_child(UI.label("A refugee camp: hordes raid it but never burn it.", UI.SMALL_SIZE, UI.MUTED))
	var village_id := int(village.id)
	var troops := UI.label("", UI.SMALL_SIZE, UI.MUTED)
	_panel_body.add_child(troops)
	_tick(troops, func() -> String:
		return _units_text(Rules.garrison_at(Game.villages.get(village_id, village), Game.server_now())))
	_panel_body.add_child(UI.button("Enter village", func() -> void: _set_view("village")))
	_hero_line(village_id)


func _village_panel() -> void:
	var village := _my_village()
	if village.is_empty():
		return
	_village_view.show_village(Game.data, village, _plot)
	var mine := Game.my_villages()
	if mine.size() > 1:
		var names := mine.map(func(v: Dictionary) -> String: return v.name if Game.is_mine(v) else "%s (for %s)" % [v.name, Game.member_name(int(v.ownerAccountId))])
		var index := 0
		for i in mine.size():
			if int(mine[i].id) == int(village.id):
				index = i
		var picker := UI.options(names, index)
		picker.item_selected.connect(func(i: int) -> void:
			Game.current_village_id = int(mine[i].id)
			_plot = Rules.HALL_PLOT
			_rebuild_panel())
		_panel_body.add_child(picker)
	if village.get("ruin") is Dictionary:
		_ruin_section(village)
		return
	var tabs := [["village", "Buildings", "icon/build"], ["troops", "Troops", "icon/troops"], ["caravans", "Caravans", "icon/caravan"], ["research", "Research", "icon/research"]]
	_panel_body.add_child(UI.tabs(tabs, _tab, func(key: String) -> void:
		_tab = key
		_rebuild_panel()))
	if _tab == "troops":
		_troops_section(village)
	elif _tab == "caravans":
		_caravans_section(village)
	elif _tab == "research":
		_research_section(village)
	else:
		_queue_section(village)
		_plot_section(village)
		_outposts_section(village)


## A razed village: what rebuilding it costs, or how long until it stands.
func _ruin_section(village: Dictionary) -> void:
	var ruin: Dictionary = village.ruin
	var village_id := int(village.id)
	_panel_body.add_child(UI.label("%s lies in ruins" % village.name, UI.HEADING_SIZE))
	if ruin.get("rebuildingUntil") != null:
		var line := UI.label("", UI.SMALL_SIZE, UI.MUTED)
		_panel_body.add_child(line)
		var until := TimeUtil.parse_iso(ruin.rebuildingUntil)
		_tick(line, func() -> String: return "Rebuilding · stands again in %s" % TimeUtil.format_duration(until - Game.server_now()))
		return
	_panel_body.add_child(UI.label("A horde burned it down. Rebuild everything as it stood, at %d%% of what it cost." % roundi(float(Game.data.horde.ruins.rebuildCostShare) * 100.0), UI.SMALL_SIZE, UI.MUTED))
	var cost := HordeText.rebuild_cost(Game.data, ruin.plots)
	var seconds := float(Game.data.horde.ruins.rebuildHours) * 3600.0 / float(Game.world.speed)
	var row := UI.hbox()
	var cost_line := UI.rich()
	cost_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cost_line)
	var button := UI.button("Rebuild", func() -> void: _rebuild_village(village_id))
	button.custom_minimum_size.x = 160
	row.add_child(button)
	_panel_body.add_child(row)
	var cost_text := "%s · %s" % [UI.costs(cost), TimeUtil.format_duration(seconds)]
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
	_panel_body.add_child(UI.label("Build queue (%d/%d)" % [queue.size(), limit], UI.SMALL_SIZE, UI.MUTED))
	if queue.is_empty():
		_panel_body.add_child(UI.label("Nothing under construction.", UI.SMALL_SIZE, UI.MUTED))
	for item in queue:
		var done_at := TimeUtil.parse_iso(item.completesAt)
		var text := "%s → Lv %d" % [_building_def(item.building).name, int(item.targetLevel)]
		var line := UI.label()
		_panel_body.add_child(line)
		_tick(line, func() -> String:
			var left := done_at - Game.server_now()
			return "%s   %s" % [text, TimeUtil.format_duration(left) if left > 0 else "finishing…"])


func _outposts_section(village: Dictionary) -> void:
	var plots := Rules.outpost_plots(village)
	var limit := Rules.outpost_limit(Game.data, Rules.hall_level(village))
	_panel_body.add_child(UI.label("Outposts (%d/%d)" % [plots.size(), limit], UI.SMALL_SIZE, UI.MUTED))
	if village.get("besieged", false):
		_panel_body.add_child(UI.label("Under siege: outposts produce nothing until the battle ends.", UI.SMALL_SIZE, UI.ERROR))
	if not plots.is_empty():
		_rebuild_order(int(village.id))
	if plots.is_empty():
		_panel_body.add_child(UI.label("None yet. Tap a forest, plains, hills, mountain or lake hex within %d of the village on the map to claim one." % int(Game.data.buildings.village.outpostRange), UI.SMALL_SIZE, UI.MUTED))
	var speed := float(Game.world.speed)
	for plot in plots:
		var holds: Dictionary = village.plots[plot]
		var cell := Rules.outpost_hex(plot)
		var level := int(holds.level)
		var terrain: String = holds.get("terrain", "")
		var row := UI.hbox()
		var text := UI.label("%s (%d, %d)  %s" % [Terrain.display_name(terrain, Game.data), cell.x, cell.y,
			"Lv %d · %s" % [level, _yield_text(Rules.outpost_yield(Game.data, terrain, level, speed))] if level > 0 else "Lv 0"], UI.SMALL_SIZE)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var show_button := UI.button("Show", func() -> void:
			_set_view("map")
			camera.position = hex_map.hex_to_local(cell)
			_select(cell))
		show_button.custom_minimum_size.x = 120
		row.add_child(show_button)
		_panel_body.add_child(row)


## The picked plot: what stands there and what it would cost to upgrade, or
## for an empty slot, the buildings that could go there.
func _plot_section(village: Dictionary) -> void:
	if not village.plots.has(_plot):
		_plot = Rules.HALL_PLOT
	var holds: Dictionary = village.plots[_plot]
	var planned := Rules.planned_plot(village, _plot)
	if Rules.is_locked(Game.data, village, _plot):
		_panel_body.add_child(UI.label("Locked slot", UI.HEADING_SIZE))
		var needed := Rules.slot_unlock_level(Game.data, Rules.plot_index(_plot))
		_panel_body.add_child(UI.label("Upgrade the Elder's Hall to level %d to build here." % needed, UI.SMALL_SIZE, UI.MUTED))
		return
	if planned.building == null:
		_panel_body.add_child(UI.label("Empty slot", UI.HEADING_SIZE))
		var options := Rules.constructible(Game.data, village)
		if options.is_empty():
			_panel_body.add_child(UI.label("Every building already stands in this village.", UI.SMALL_SIZE, UI.MUTED))
		for building in options:
			_build_row(village, _plot, building, 1, "Build")
		return

	var building: String = planned.building
	var def := _building_def(building)
	var level := int(holds.level)
	var title := "%s  Lv %d" % [def.name, level]
	if int(planned.level) > level:
		title += "  (→ %d queued)" % int(planned.level)
	_panel_body.add_child(UI.label(title, UI.HEADING_SIZE))
	var effect := _effect_text(village, building, level)
	if effect != "":
		_panel_body.add_child(UI.label(effect, UI.SMALL_SIZE, UI.MUTED))
	var target := int(planned.level) + 1
	if target > int(def.maxLevel):
		_panel_body.add_child(UI.label("Max level", UI.SMALL_SIZE, UI.MUTED))
		return
	_build_row(village, _plot, building, target, "Build" if level == 0 and int(planned.level) == 0 else "Upgrade")


## One "build `building` to `target` on `plot`" row with its cost, time
## and button.
func _build_row(village: Dictionary, plot: String, building: String, target: int, verb: String) -> void:
	var village_id := int(village.id)
	var def := _building_def(building)
	var hall := Rules.hall_level(village)
	var queue_full: bool = village.queue.size() >= Rules.queue_limit(Game.data, hall)
	var cost := Rules.level_cost(def, target)
	var seconds := Rules.build_seconds(def, target, float(Game.world.speed), Rules.hall_speedup(Game.data, hall) * ResearchRules.time_factor(village.get("bonuses", {}), "buildTime"))

	var row := UI.hbox()
	var info := UI.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(UI.label("%s → Lv %d" % [def.name, target]))
	var cost_line := UI.rich()
	info.add_child(cost_line)
	row.add_child(info)
	var button := UI.button(verb, func() -> void: _queue_build(village_id, plot, building))
	button.custom_minimum_size.x = 160
	row.add_child(button)
	_panel_body.add_child(row)
	var cost_text := "%s · %s" % [UI.costs(cost), TimeUtil.format_duration(seconds)]
	_tick(cost_line, func() -> String:
		var home: Dictionary = Game.villages.get(village_id, village)
		var affordable := Ledger.can_afford(Ledger.amounts_at(home.resources, Game.server_now()), cost)
		button.disabled = queue_full or not affordable
		return cost_text + ("  (queue full)" if queue_full else ""))


## What a building does at its level, and at the next one.
func _effect_text(village: Dictionary, building: String, level: int) -> String:
	var def := _building_def(building)
	var speed := float(Game.world.speed)
	if def.has("production"):
		var resource: String = def.production.resource
		return "%s +%d/h now, +%d/h at level %d" % [resource.capitalize(),
			roundi(Rules.field_production(def, level, speed)), roundi(Rules.field_production(def, level + 1, speed)), level + 1]
	if building == Rules.HALL:
		var total := int(Game.data.buildings.village.centerSlots)
		var text := "%d of %d building slots open, build queue %d." % [Rules.unlocked_slots(Game.data, level), total, Rules.queue_limit(Game.data, level)]
		if level < int(def.maxLevel):
			text += " Level %d: %d slots, queue %d, builds %d%% faster than level 1." % [level + 1,
				Rules.unlocked_slots(Game.data, level + 1), Rules.queue_limit(Game.data, level + 1),
				roundi((1.0 - Rules.hall_speedup(Game.data, level + 1)) * 100.0)]
		return text
	if def.has("capacityGrowth"):
		var base := float(Game.data.buildings.village.baseCapacity)
		return "Stores %d of each resource" % roundi(base * pow(float(def.capacityGrowth), level))
	return ""


func _troops_section(village: Dictionary) -> void:
	var village_id := int(village.id)
	_stance_picker(village)
	_hero_line(village_id)
	var recommended := Rules.recommended_garrison(Game.data, Game.villages_owned(int(village.ownerAccountId)))
	var guard := UI.label("", UI.SMALL_SIZE, UI.MUTED)
	_panel_body.add_child(guard)
	_tick(guard, func() -> String:
		var home_now := BattleText.total(Rules.garrison_at(Game.villages.get(village_id, village), Game.server_now()))
		return "Recommended garrison: %d (%d at home)" % [recommended, home_now])
	_expeditions_list(village_id)
	_panel_body.add_child(UI.label("At home", UI.SMALL_SIZE, UI.MUTED))
	var home := UI.label()
	_panel_body.add_child(home)
	_tick(home, func() -> String:
		return _units_text(Rules.garrison_at(Game.villages.get(village_id, village), Game.server_now())))

	var away: Dictionary = village.get("away", {}).duplicate()
	for unit in away.keys():
		if int(away[unit]) <= 0:
			away.erase(unit)
	if not away.is_empty():
		_panel_body.add_child(UI.label("Away: %s" % _units_text(away), UI.SMALL_SIZE, UI.MUTED))

	var units: Dictionary = Game.data.units.units
	var training: Array = village.training
	var limit := int(Game.data.units.trainingQueueLimit)
	_panel_body.add_child(UI.label("Training (%d/%d)" % [training.size(), limit], UI.SMALL_SIZE, UI.MUTED))
	if training.is_empty():
		_panel_body.add_child(UI.label("Nobody in training.", UI.SMALL_SIZE, UI.MUTED))
	for batch in training:
		var line := UI.label()
		_panel_body.add_child(line)
		var unit_name: String = units.get(batch.unit, {"name": batch.unit}).name
		var done_at := TimeUtil.parse_iso(batch.completesAt)
		var start := TimeUtil.parse_iso(batch.startsAt)
		var per_unit := float(batch.perUnitMs) / 1000.0
		_tick(line, func() -> String:
			var now := Game.server_now()
			var done := Rules.finished_by(batch, now)
			if done >= int(batch.count):
				return "%s %d/%d   finishing…" % [unit_name, done, batch.count]
			var next_at := start + (done + 1) * per_unit
			return "%s %d/%d   next %s · all %s" % [unit_name, done, batch.count,
				TimeUtil.format_duration(next_at - now), TimeUtil.format_duration(done_at - now)])

	_armies_section(village)
	_repeat_order(village)
	_panel_body.add_child(UI.label("Train", UI.SMALL_SIZE, UI.MUTED))
	var queue_full := training.size() >= limit
	var max_batch := int(Game.data.units.maxBatch)
	for unit in units:
		var def: Dictionary = units[unit]
		if not ClanText.allowed(def, village.get("bonuses", {})):
			continue
		var building_level := int(village.levels.get(def.building, 0))
		var unlocked := building_level >= int(def.requiresLevel)
		var count: int = _train_counts.get(unit, 1)

		var info := UI.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UI.label("%s  ×%d" % [def.name, count]))
		info.add_child(UI.label("%s · atk %d · def %d · %d grain/h" % [def.family.capitalize(), def.attack, def.defense, def.upkeepPerHour], UI.SMALL_SIZE, UI.MUTED))
		_panel_body.add_child(info)
		if not unlocked:
			info.add_child(UI.label("Needs %s level %d" % [_building_def(def.building).name, def.requiresLevel], UI.SMALL_SIZE, UI.ERROR))
			continue
		var cost := Rules.unit_cost(def, count, Game.villages_owned(int(village.ownerAccountId)))
		var cost_line := UI.rich()
		info.add_child(cost_line)

		var row := UI.hbox()
		_panel_body.add_child(row)
		for step in [-5, -1, 1, 5]:
			var stepper := UI.button(("%+d" % step).replace("-", "−"), func() -> void:
				_train_counts[unit] = clampi(count + step, 1, max_batch)
				_rebuild_panel())
			stepper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(stepper)
		var train := UI.button("Train", func() -> void: _train(village_id, unit, count))
		train.custom_minimum_size.x = 140
		row.add_child(train)
		var seconds := float(def.trainSeconds) * pow(float(Game.data.units.trainingSpeedup), maxi(0, building_level - 1)) \
			* ResearchRules.time_factor(village.get("bonuses", {}), "trainTime") / float(Game.world.speed)
		var cost_text := "%s · %s each" % [UI.costs(cost), TimeUtil.format_duration(seconds)]
		_tick(cost_line, func() -> String:
			var current: Dictionary = Game.villages.get(village_id, village)
			var affordable := Ledger.can_afford(Ledger.amounts_at(current.resources, Game.server_now()), cost)
			train.disabled = queue_full or not affordable
			return cost_text + ("  (queue full)" if queue_full else ""))


func _stance_picker(village: Dictionary) -> void:
	var stances: Dictionary = Game.data.battle.stances
	var current: String = village.get("stance", "balanced")
	_panel_body.add_child(UI.label("Stance when attacked", UI.SMALL_SIZE, UI.MUTED))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_panel_body.add_child(grid)
	for stance in stances:
		var button := UI.button(stances[stance].name, func() -> void: _set_stance(int(village.id), stance))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = stance == current
		grid.add_child(button)
	var def: Dictionary = stances[current]
	var breaks := "never breaks" if def.retreatAt == null else "breaks at %d%% losses" % roundi(float(def.retreatAt) * 100.0)
	_panel_body.add_child(UI.label("%s: attack ×%.2f, defense ×%.2f, %s." % [def.name, def.attack, def.defense, breaks], UI.SMALL_SIZE, UI.MUTED))


func _set_stance(village_id: int, stance: String) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/stance" % village_id, {"stance": stance})
	if not response.ok:
		_status.text = response.error
		return
	Game.update_village(response.data.village)


func _units_text(units: Dictionary) -> String:
	if units.is_empty():
		return "No troops yet."
	var parts := PackedStringArray()
	for unit in units:
		var def: Dictionary = Game.data.units.units.get(unit, {"name": unit})
		parts.append("%s ×%d" % [def.name, units[unit]])
	return ", ".join(parts)


func _train(village_id: int, unit: String, count: int) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/train" % village_id, {"unit": unit, "count": count})
	if not response.ok:
		_status.text = response.error
		return
	Game.note_server_time(response.data.serverTime)
	Game.update_village(response.data.village)


# --- Threats -----------------------------------------------------------------

## One line for the top banner: what needs attention first.
func _threat_summary() -> String:
	if RunText.is_over(Game.world):
		return "%s · see how the run went" % RunText.ending(Game.data, Game.world).title
	var ritual_at: Variant = Game.world.get("ritualAt")
	if ritual_at != null and TimeUtil.parse_iso(ritual_at) > Game.server_now():
		return RunText.ritual_line(Game.world, Game.server_now())
	if Game.waves.is_empty():
		return "No threats known"
	var now := Game.server_now()
	for wave in Game.waves:
		if wave.status == "razing":
			return "%s is burning · %s" % [Game.village_name(wave.targetVillageId), TimeUtil.format_duration(TimeUtil.parse_iso(wave.endsAt) - now)]
	for wave in Game.waves:
		if wave.status == "marching":
			return "Horde marching on %s · %s" % [Game.village_name(wave.targetVillageId), TimeUtil.format_duration(TimeUtil.parse_iso(wave.arrivesAt) - now)]
	for wave in Game.waves:
		if wave.status == "battling":
			var battle := Game.battle_for(int(wave.id))
			var place := Game.battle_place(battle) if not battle.is_empty() else Game.village_name(wave.targetVillageId)
			return "Battle at %s · round %d" % [place, int(battle.get("round", 0))]
	for wave in Game.waves:
		if wave.status == "arrived":
			return "Horde at %s" % Game.village_name(wave.targetVillageId)
	var next: Dictionary = Game.waves[0]
	return "Next wave: %s · %s · in %s" % [String(next.front).capitalize(), next.threat, TimeUtil.format_duration(TimeUtil.parse_iso(next.spawnAt) - now)]


func _threats_panel() -> void:
	_panel_body.add_child(UI.label("Threats", UI.HEADING_SIZE))
	_panel_body.add_child(UI.button("Open the almanac", func() -> void:
		_panel_mode = "almanac"
		_rebuild_panel()))
	_clan_section()
	_delegation_section()
	var ritual := RunText.ritual_line(Game.world, Game.server_now())
	if ritual != "":
		_panel_body.add_child(UI.label(ritual, 0, Color("#ffb4a8")))
		_panel_body.add_child(UI.label(Game.data.bridge.ritualNight.story, UI.SMALL_SIZE, UI.MUTED))
	_panel_body.add_child(UI.label("The Holy City: " + HordeText.sanctity(Game.world, Game.data), UI.SMALL_SIZE, UI.MUTED))
	_panel_body.add_child(UI.label("%s difficulty · %s" % [GroupText.difficulty(Game.data, String(Game.world.get("difficulty", "normal"))), GroupText.quiet(Game.world.get("quietHours"))], UI.SMALL_SIZE, UI.MUTED))
	if Game.world.get("hostAccountId") != null and int(Game.world.hostAccountId) == Game.my_account_id():
		var quiet_row := UI.hbox(8)
		var off := UI.button("Off", func() -> void: _set_quiet(null, null))
		off.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		quiet_row.add_child(off)
		for choice in GroupText.QUIET_CHOICES:
			var start: int = choice[0] * 60
			var end: int = choice[1] * 60
			var b := UI.button("%02d–%02d" % [choice[0], choice[1]], func() -> void: _set_quiet(start, end))
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			quiet_row.add_child(b)
		_panel_body.add_child(quiet_row)
	if Game.waves.is_empty():
		_panel_body.add_child(UI.label("No waves announced.", UI.SMALL_SIZE, UI.MUTED))
	for wave in Game.waves:
		_wave_entry(wave)
	var finished := Game.battles.filter(func(b: Dictionary) -> bool: return b.status != "ongoing")
	if not finished.is_empty():
		_panel_body.add_child(UI.label("Battle reports", UI.HEADING_SIZE))
	for battle in finished:
		var report := HordeText.assault(battle, BattleText.losses(battle)) if battle.get("campId") != null or battle.get("siteId") != null else BattleText.outcome(battle, Game.battle_place(battle))
		_panel_body.add_child(UI.label(report, UI.SMALL_SIZE))
		var details := "%s horde, %d rounds" % [String(battle.attackerStance).replace("_", " ").capitalize(), int(battle.round)]
		var ground := BattleText.setup_text(battle)
		if ground != "":
			details += " · " + ground
		_panel_body.add_child(UI.label(details, UI.SMALL_SIZE, UI.MUTED))
		var choice := HordeText.decision(battle)
		if choice != "":
			_panel_body.add_child(UI.label(choice, UI.SMALL_SIZE, Color("#ffb4a8")))
		var helpers := ArmyText.reinforcements(battle, Game.village_name)
		if helpers != "":
			_panel_body.add_child(UI.label("Help came from " + helpers, UI.SMALL_SIZE, UI.MUTED))
		_panel_body.add_child(_battle_button(battle))
	if not Game.camps.is_empty():
		_panel_body.add_child(UI.label("Camps and lairs", UI.HEADING_SIZE))
	for camp in Game.camps:
		_panel_body.add_child(UI.label("%s at (%d, %d)" % [HordeText.camp(camp, Game.front_faction(camp.front)), int(camp.q), int(camp.r)], UI.SMALL_SIZE))
	if not Game.raids.is_empty():
		_panel_body.add_child(UI.label("Outposts burned", UI.HEADING_SIZE))
	for raid in Game.raids:
		_panel_body.add_child(UI.label(BattleText.raid(raid, Game.village_name(raid.villageId)), UI.SMALL_SIZE))
	var map: Variant = Game.world.get("map")
	if map is Dictionary:
		_panel_body.add_child(UI.label("Fronts", UI.HEADING_SIZE))
		for line in WaveMath.front_lines(Game.data, map.activeFronts):
			_panel_body.add_child(UI.label(line, UI.SMALL_SIZE, UI.MUTED))


## The host sets the group's quiet hours, in this device's time zone.
func _set_quiet(start: Variant, end: Variant) -> void:
	_status.text = ""
	var offset := int(Time.get_time_zone_from_system().get("bias", 0))
	var response := await Api.request(HTTPClient.METHOD_PUT, "/v1/worlds/%d/quiet" % Game.world_id(), {"start": start, "end": end, "utcOffsetMinutes": offset})
	if not response.ok:
		_status.text = response.error
		return
	Game.set_world(response.data)


func _wave_entry(wave: Dictionary) -> void:
	_panel_body.add_child(UI.label("Wave %d · %s" % [int(wave.index) + 1, Game.front_faction(wave.front)]))
	var scouted := Game.missions_for(int(wave.id)).any(func(m: Dictionary) -> bool: return m.report != null)
	var known := "" if scouted else " · composition unknown"
	_panel_body.add_child(UI.label("%s front · %s threat%s" % [String(wave.front).capitalize(), wave.threat, known], UI.SMALL_SIZE, UI.MUTED))
	var line := UI.label("", UI.SMALL_SIZE, Color("#ffb4a8"))
	_panel_body.add_child(line)
	_tick(line, func() -> String:
		var now := Game.server_now()
		match wave.status:
			"scheduled":
				return "Appears in %s" % TimeUtil.format_duration(TimeUtil.parse_iso(wave.spawnAt) - now)
			"marching":
				return "Marching on %s · arrives in %s" % [Game.village_name(wave.targetVillageId), TimeUtil.format_duration(TimeUtil.parse_iso(wave.arrivesAt) - now)]
			"arrived":
				return "At the gates of %s · leaves in %s" % [Game.village_name(wave.targetVillageId), TimeUtil.format_duration(TimeUtil.parse_iso(wave.endsAt) - now)]
			"razing":
				return "Burning %s · done in %s" % [Game.village_name(wave.targetVillageId), TimeUtil.format_duration(TimeUtil.parse_iso(wave.endsAt) - now)]
			"battling":
				var battle := Game.battle_for(int(wave.id))
				return "Fighting at %s · round %d of %d · %d of them left" % [Game.battle_place(battle) if not battle.is_empty() else Game.village_name(wave.targetVillageId), int(battle.get("round", 0)), int(Game.data.battle.maxRounds), BattleText.total(battle.get("attackerNow", {}))]
		return String(wave.status).capitalize())
	var fighting := Game.battle_for(int(wave.id))
	if not fighting.is_empty() and fighting.status == "ongoing":
		_panel_body.add_child(_battle_button(fighting))
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
		_panel_body.add_child(UI.label("Scouts from %s: %s" % [by, ScoutText.survivors(latest.report)], UI.SMALL_SIZE, UI.MUTED))
		_panel_body.add_child(UI.label(ScoutText.describe(latest.report), UI.SMALL_SIZE))
	for mission in missions:
		if mission.status == "done":
			continue
		var line := UI.label("", UI.SMALL_SIZE, UI.MUTED)
		_panel_body.add_child(line)
		_tick(line, func() -> String:
			var now := Game.server_now()
			if mission.status == "outbound":
				return "%d scouts en route · report in %s" % [mission.sent, TimeUtil.format_duration(TimeUtil.parse_iso(mission.arrivesAt) - now)]
			return "Scouts heading home · back in %s" % TimeUtil.format_duration(TimeUtil.parse_iso(mission.returnsAt) - now))

	var home := _my_village()
	if home.is_empty() or int(home.levels.get("scout_lodge", 0)) < 1:
		return
	var village_id := int(home.id)
	var at_home := int(Rules.garrison_at(home, Game.server_now()).get("scout", 0))
	var max_scouts := mini(int(Game.data.scouting.maxScouts), maxi(at_home, 1))
	var count := clampi(_scout_counts.get(wave_id, mini(at_home, 3)), 1, max_scouts)
	var row := UI.hbox()
	_panel_body.add_child(row)
	for step in [-1, 1]:
		var stepper := UI.button(("%+d" % step).replace("-", "−"), func() -> void:
			_scout_counts[wave_id] = clampi(count + step, 1, max_scouts)
			_rebuild_panel())
		stepper.custom_minimum_size.x = 80
		row.add_child(stepper)
	var send := UI.button("Send %d scout%s (%d home)" % [count, "" if count == 1 else "s", at_home], func() -> void:
		_send_scouts(village_id, wave_id, count))
	send.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	send.disabled = at_home < count
	row.add_child(send)


func _send_scouts(village_id: int, wave_id: int, count: int) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/scout" % village_id, {"waveId": wave_id, "count": count})
	if not response.ok:
		_status.text = response.error
		return
	Game.note_server_time(response.data.serverTime)
	Game.update_village(response.data.village)


func _on_waves_changed() -> void:
	hex_map.queue_redraw()
	_rebuild_panel()


## Keeps a label (or rich label) showing `text`'s result.
func _tick(label: Control, text: Callable) -> void:
	label.text = text.call()
	_ticking.append([label, text])


func _queue_build(village_id: int, plot: String, building: String) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/build" % village_id, {"plot": plot, "building": building})
	if not response.ok:
		_status.text = response.error
		return
	Game.note_server_time(response.data.serverTime)
	Game.update_village(response.data.village)


# --- Events ------------------------------------------------------------------

func _on_map_tapped(world_position: Vector2) -> void:
	var cell := hex_map.local_to_hex(hex_map.to_local(world_position))
	if hex_map.has_hex(cell):
		_select(cell)


func _on_world_changed() -> void:
	hex_map.refresh()
	_open_run_once()
	_view_button.visible = not _my_village().is_empty()
	if _view == "village" and _my_village().is_empty():
		_set_view("map")
		return
	_rebuild_panel()


func _on_village_changed(_village_id: int) -> void:
	hex_map.queue_redraw()
	_rebuild_panel()


func _on_live_connection(connected: bool) -> void:
	_live_label.text = "● live" if connected else "○ offline"
	_live_label.add_theme_color_override("font_color", Color("#9fd18b") if connected else UI.MUTED)
	if connected:
		_refetch_world()


func _refetch_world() -> void:
	var response := await Api.get_json("/v1/worlds/%d" % Game.world_id())
	if response.ok:
		Game.set_world(response.data)
	_refetch_inbox()


func _refetch_inbox() -> void:
	var response := await Api.get_json("/v1/worlds/%d/notifications" % Game.world_id())
	if response.ok:
		Game.set_inbox(Game.world_id(), response.data.notifications, int(response.data.unread))


func _on_inbox_changed() -> void:
	_inbox_button.text = str(Game.unread) if Game.unread > 0 else ""
	if _panel_mode == "inbox":
		_rebuild_panel()


# --- Inbox -------------------------------------------------------------------

## Opens the inbox: everything is read once seen.
func _show_inbox() -> void:
	_panel_mode = "inbox"
	_rebuild_panel()
	if Game.unread > 0:
		await Api.post_json("/v1/worlds/%d/notifications/read" % Game.world_id(), {})
	var response := await Api.get_json("/v1/me/notifications")
	if response.ok:
		_prefs = response.data.prefs
		if _panel_mode == "inbox":
			_rebuild_panel()


func _inbox_panel() -> void:
	var top := UI.hbox()
	var title := UI.label("Inbox", UI.HEADING_SIZE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(UI.button("Close", func() -> void:
		_panel_mode = "hex"
		_rebuild_panel()))
	_panel_body.add_child(top)
	_panel_body.add_child(UI.label("Danger is pushed to your phone; everything else waits for the daily digest.", UI.SMALL_SIZE, UI.MUTED))
	if Game.inbox.is_empty():
		_panel_body.add_child(UI.label("Nothing yet.", UI.SMALL_SIZE, UI.MUTED))
	var now := Game.server_now()
	for n in Game.inbox:
		var head := UI.label(("● " if not n.read else "") + String(n.title))
		_panel_body.add_child(head)
		var body := "%s · %s" % [InboxText.ago(TimeUtil.parse_iso(n.createdAt), now), n.body] if String(n.body) != "" else InboxText.ago(TimeUtil.parse_iso(n.createdAt), now)
		_panel_body.add_child(UI.label(body, UI.SMALL_SIZE, UI.MUTED))
	_notification_settings()


func _notification_settings() -> void:
	if _prefs.is_empty():
		return
	_panel_body.add_child(UI.label("Settings", UI.HEADING_SIZE))
	var quiet: bool = _prefs.quietStart != null and _prefs.quietEnd != null
	var start := int(_prefs.quietStart) if quiet else 22 * 60
	var end := int(_prefs.quietEnd) if quiet else 7 * 60
	var quiet_row := UI.hbox(8)
	var quiet_text := UI.label("Quiet hours %s–%s" % [InboxText.clock(start), InboxText.clock(end)] if quiet else "No quiet hours", UI.SMALL_SIZE)
	quiet_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quiet_row.add_child(quiet_text)
	quiet_row.add_child(UI.button("Off" if quiet else "On", func() -> void:
		_save_prefs({"quietStart": null, "quietEnd": null} if quiet else {"quietStart": start, "quietEnd": end})))
	_panel_body.add_child(quiet_row)
	if quiet:
		var adjust := UI.hbox(8)
		for spec in [["From −1h", -60, 0], ["From +1h", 60, 0], ["Until −1h", 0, -60], ["Until +1h", 0, 60]]:
			var button := UI.button(spec[0], func() -> void:
				_save_prefs({"quietStart": posmod(start + spec[1], 1440), "quietEnd": posmod(end + spec[2], 1440)}))
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.add_theme_font_size_override("font_size", UI.SMALL_SIZE)
			adjust.add_child(button)
		_panel_body.add_child(adjust)
	var digest := int(_prefs.digestHour)
	var digest_row := UI.hbox(8)
	var digest_text := UI.label("Daily digest at %s" % InboxText.clock(digest * 60), UI.SMALL_SIZE)
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


func _leave() -> void:
	Live.stop()
	get_tree().change_scene_to_file(START_SCENE)


## The village of yours the screens show (see Game.current_village).
func _my_village() -> Dictionary:
	return Game.current_village()


func _building_def(building: String) -> Dictionary:
	return Game.data.buildings.buildings.get(building, {"name": building.capitalize()})
