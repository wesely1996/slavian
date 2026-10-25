extends Node2D
## In-world screen: the map from the server, your resources, a threat
## banner, and a panel for the selected hex (or the threats timeline). The
## Village button swaps the map for the inside of your village, where you
## build on its plots and train troops.

const START_SCENE := "res://scenes/start.tscn"
const UI_REFRESH_SEC := 0.25
const NEGATIVE := UiTheme.MADDER
const REPORT_MAX := 4000
## The Holy City stands in the middle of the map.
const HOLY_CITY := Vector2i.ZERO

@onready var hex_map: HexMap = $HexMap
@onready var camera: MapCamera = $MapCamera

var _selected := Vector2i.MAX
var _since_refresh := 0.0

var _live_label: Label
var _resource_labels: Dictionary[String, Label] = {}
## Under each stock: how full the storehouse is, and its limit.
var _resource_bars: Dictionary[String, ProgressBar] = {}
var _capacity_labels: Dictionary[String, Label] = {}
## Whose stores the strip shows (tap: the next of your villages).
var _stores_button: Button
var _rate_labels: Dictionary[String, Label] = {}
## "map", "village" (the inside of your own village) or "battle" (a battle
## on its campaign map).
var _view := "map"
var _view_button: Button
var _inbox_button: Button
## Notification settings as the server last sent them.
var _prefs: Dictionary = {}
var _spacer: Control
var _root: VBoxContainer
var _body: HBoxContainer
var _scroll: ScrollContainer
var _resources: HBoxContainer
var _top_rows: VBoxContainer
var _grade: MapGrade
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
## The town's name is being edited in the village panel.
var _renaming := false
## Names being typed (key -> {text, caret}). Game events rebuild the panel
## often; a draft keeps what was typed, where, and the keyboard focus.
var _drafts := {}
## The draft whose field had the focus when the panel was last rebuilt.
var _focused_draft := ""
## The panel is being cleared to be rebuilt (its fields lose the focus).
var _clearing := false
## A road being laid: from this hex, by this village, to a hex tapped next.
var _road_from := Vector2i.MAX
var _road_village := 0
## Caravan form: destination village id (0: the Holy City vault) and load.
var _caravan_to := 0
var _caravan_load: Dictionary[String, int] = {"wood": 0, "stone": 0, "grain": 0, "iron": 0}
## Army form: destination (village id; 0: the Holy City), troops and orders.
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
## The side tab open on each sheet ("threats", "hero", …), and the page each
## paged list is on.
var _side: Dictionary[String, String] = {}
var _pages: Dictionary[String, int] = {}
## The end-of-run panel opens by itself once.
var _run_seen := false
var _threat_button: Button
## Chosen number of scouts to send, per wave id.
var _scout_counts: Dictionary[int, int] = {}
## Chosen batch size per unit, kept while the panel rebuilds.
var _train_counts: Dictionary[String, int] = {}
var _status: Label
## The getting-started quest card over the map and the village (M5 step 23).
var _quest_card: QuestCard
var _compass: Compass
var _ui_layer: CanvasLayer
var _main: Control
var _panel: PanelContainer
var _panel_body: VBoxContainer
## Labels refreshed every UI tick, with a callable producing their text.
var _ticking: Array[Array] = []
## Hordes already marching on your villages: a new one sounds the horn.
var _known_hordes: Array = []


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
	_refresh_quest_card()
	_welcome_once()
	_known_hordes = SoundCues.incoming(Game.waves, _my_village_ids())
	_update_music()


func _exit_tree() -> void:
	# Back to the start screen: the real server answers again.
	Local.world_id = 0
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
			Sound.effect("clash")
			_rebuild_panel()
	_since_refresh += delta
	if _since_refresh < UI_REFRESH_SEC:
		return
	_since_refresh = 0.0
	_update_music()
	var home := _my_village()
	if not home.is_empty():
		var amounts := Ledger.amounts_at(home.resources, Game.server_now())
		_stores_button.text = ("%s ▸" % home.name) if Game.my_villages().size() > 1 else String(home.name)
		_stores_button.tooltip_text = tr("The stores of %s: each village keeps its own.") % home.name
		for kind in Ledger.KINDS:
			var rate: float = home.resources.ratesPerHour[kind]
			var label := _resource_labels[kind]
			label.text = str(int(amounts[kind]))
			var capacity := float(home.resources.capacity[kind])
			_capacity_labels[kind].text = "/%d" % roundi(capacity)
			var share := clampf(float(amounts[kind]) / capacity, 0.0, 1.0) if capacity > 0.0 else 0.0
			_resource_bars[kind].value = share
			_resource_bars[kind].modulate = Color(1.6, 0.6, 0.55) if share >= 0.95 else Color.WHITE
			label.tooltip_text = tr("%s: %s an hour, credited every minute (next in %ds)") % [UI.resource_name(kind), UI.signed(rate), Ledger.seconds_to_next(Game.server_now())]
			_rate_labels[kind].text = tr("%s/min") % _per_minute(rate)
			_rate_labels[kind].add_theme_color_override("font_color", NEGATIVE if rate < 0 else UI.MUTED)
	_threat_button.text = _threat_summary()
	_status.visible = _status.text != ""
	if hex_map.has_moving_hordes():
		hex_map.queue_redraw()
	for entry in _ticking:
		entry[0].text = (entry[1] as Callable).call()


# --- Layout ----------------------------------------------------------------

func _build_ui() -> void:
	# The light grade lies over the map, under the interface.
	var grade_layer := CanvasLayer.new()
	grade_layer.layer = 1
	add_child(grade_layer)
	_grade = MapGrade.new()
	_grade.camera = camera
	grade_layer.add_child(_grade)
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	_ui_layer = layer
	var root := UI.vbox(0)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	# The top band of wood: the world and its buttons, the resources, the
	# next threat.
	var top := UI.wood(14)
	top.add_theme_stylebox_override("panel", _top_style())
	root.add_child(top)
	var top_rows := UI.vbox(10)
	top.add_child(top_rows)
	_top_rows = top_rows
	var bar := UI.hbox(6)
	top_rows.add_child(bar)
	var back := UI.button("", _leave, "icon/back")
	back.theme_type_variation = "WoodIconButton"
	back.tooltip_text = tr("Worlds")
	bar.add_child(back)
	var title := UI.label(Game.world.get("name", ""), UI.HEADING_SIZE)
	title.theme_type_variation = "OnWoodHeading"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bar.add_child(title)
	_live_label = UI.label("", UI.SMALL_SIZE)
	_live_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	bar.add_child(_live_label)
	_view_button = UI.button(tr("Village"), _toggle_view, "icon/village")
	_view_button.theme_type_variation = "WoodButton"
	_view_button.visible = not _my_village().is_empty()
	bar.add_child(_view_button)
	# All your troops at a glance: where they stand, who is on the move.
	var forces := UI.button("", func() -> void:
		_panel_mode = "forces"
		_rebuild_panel(), "icon/troops")
	forces.theme_type_variation = "WoodIconButton"
	forces.tooltip_text = tr("Your forces")
	bar.add_child(forces)
	_inbox_button = UI.button("", _show_inbox, "icon/inbox")
	_inbox_button.theme_type_variation = "WoodIconButton"
	_inbox_button.tooltip_text = tr("Inbox")
	bar.add_child(_inbox_button)
	# The tutorial, shown or hidden at any time.
	var tutorial := UI.button("", _toggle_tutorial, "icon/help")
	tutorial.theme_type_variation = "WoodIconButton"
	tutorial.tooltip_text = tr("Tutorial")
	bar.add_child(tutorial)
	# The resource strip: whose stores they are, then for each resource its
	# icon, stock and limit, the hourly rate, and how full the store is.
	_resources = UI.hbox(4)
	top_rows.add_child(_resources)
	_stores_button = UI.button("", _next_village)
	_stores_button.theme_type_variation = "WoodIconButton"
	_stores_button.add_theme_font_size_override("font_size", 18)
	_stores_button.custom_minimum_size = Vector2(104, 0)
	_stores_button.clip_text = true
	_stores_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_stores_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_resources.add_child(_stores_button)
	for kind in Ledger.KINDS:
		var cell := UI.hbox(8)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(UI.icon("resource/" + kind, 36))
		var numbers := UI.vbox(0)
		var stock := UI.hbox(2)
		var label := UI.label("", 26)
		label.theme_type_variation = "OnWoodStrong"
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		stock.add_child(label)
		var most := UI.label("", 16)
		most.theme_type_variation = "OnWoodMuted"
		most.autowrap_mode = TextServer.AUTOWRAP_OFF
		most.size_flags_vertical = Control.SIZE_SHRINK_END
		stock.add_child(most)
		numbers.add_child(stock)
		var rate := UI.label("", 18)
		rate.theme_type_variation = "OnWoodMuted"
		rate.autowrap_mode = TextServer.AUTOWRAP_OFF
		numbers.add_child(rate)
		var full := ProgressBar.new()
		full.show_percentage = false
		full.custom_minimum_size = Vector2(70, 5)
		full.max_value = 1.0
		full.step = 0.0
		# The theme's ink groove vanishes on the wood: a darker one here.
		var groove := StyleBoxFlat.new()
		groove.bg_color = Color(0, 0, 0, 0.45)
		groove.border_color = Color(UiTheme.ON_WOOD, 0.35)
		groove.set_border_width_all(1)
		groove.set_corner_radius_all(3)
		full.add_theme_stylebox_override("background", groove)
		numbers.add_child(full)
		cell.add_child(numbers)
		_resources.add_child(cell)
		_resource_labels[kind] = label
		_capacity_labels[kind] = most
		_resource_bars[kind] = full
		_rate_labels[kind] = rate
	# The next threat: madder on the wood, opens the threats sheet.
	_threat_button = UI.button("", _show_threats, "icon/threat")
	_threat_button.custom_minimum_size.y = 56
	_threat_button.add_theme_font_size_override("font_size", UI.SMALL_SIZE + 2)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		_threat_button.add_theme_color_override(state, UiTheme.ON_WOOD)
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		_threat_button.add_theme_color_override(state, Color("#e58a7d"))
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(UiTheme.MADDER, 0.12 if state == "normal" else 0.3)
		style.border_color = UiTheme.MADDER
		style.border_width_left = 5
		style.set_corner_radius_all(2)
		style.content_margin_left = 16
		style.content_margin_right = 12
		_threat_button.add_theme_stylebox_override(state, style)
	_threat_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_threat_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top_rows.add_child(_threat_button)
	_status = UI.label("", UI.SMALL_SIZE, Color("#e58a7d"))
	top_rows.add_child(_status)
	_on_live_connection(Live.connected)
	root.add_child(Rushnyk.new())

	# Under the band: the map (or the village, or a battle), and the sheet
	# for what is picked, on the right in landscape and below in portrait.
	_body = UI.hbox(0)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_body)
	var main := UI.vbox(0)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(main)
	_main = main
	_spacer = Control.new()
	_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_child(_spacer)
	_village_view = VillageView.new()
	_village_view.clock = Game.server_now
	_village_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_village_view.visible = false
	_village_view.plot_tapped.connect(_on_plot_tapped)
	main.add_child(_village_view)
	_battle_view = BattleMap.new()
	_battle_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_battle_view.visible = false
	main.add_child(_battle_view)

	_panel = UI.panel(1.0, 18)
	_panel.add_theme_stylebox_override("panel", UiTheme.sheet_style(26))
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(_scroll)
	_panel_body = UI.vbox(14)
	_panel_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_panel_body)
	_root = root
	# The quest card floats over the map and the village, at their top left.
	_quest_card = QuestCard.new()
	_quest_card.claim.connect(_claim_onboarding)
	_quest_card.show_me.connect(_show_me)
	_quest_card.hide_tutorial.connect(func() -> void:
		Session.set_tutorial_flag(Game.world_id(), "hidden", true)
		_status.text = tr("The tutorial is hidden. The ? button at the top brings it back.")
		_refresh_quest_card())
	layer.add_child(_quest_card)
	# The compass in the map's bottom right corner.
	_compass = Compass.new()
	layer.add_child(_compass)
	_main.resized.connect(_place_quest_card)
	get_viewport().size_changed.connect(_arrange)
	_arrange()


## The sheet beside the map in landscape, under it in portrait.
func _arrange() -> void:
	var area := get_viewport().get_visible_rect().size
	var landscape := area.x > area.y * 1.05
	# On some phones the on-screen keyboard resizes the window: the sheet is
	# only moved when the orientation turns, as taking it out of the tree
	# drops the typing focus and with it the keyboard.
	if _panel.get_parent() != (_body if landscape else _root):
		_move_panel(landscape, area)
	elif not landscape:
		_fit_sheet()
	# Centre the map in the part the sheet leaves uncovered.
	camera.view_offset = Vector2(-_panel.custom_minimum_size.x / 2.0, 0) if landscape else Vector2(0, -area.y * 0.1)
	_place_quest_card.call_deferred()


func _move_panel(landscape: bool, area: Vector2) -> void:
	if _panel.get_parent() != null:
		_panel.get_parent().remove_child(_panel)
	# In landscape the resources ride in the title row.
	var bar := _view_button.get_parent()
	_resources.get_parent().remove_child(_resources)
	if landscape:
		bar.add_child(_resources)
		bar.move_child(_resources, 2)
		_resources.size_flags_horizontal = Control.SIZE_SHRINK_END
		_resources.add_theme_constant_override("separation", 28)
	else:
		_top_rows.add_child(_resources)
		_top_rows.move_child(_resources, 1)
		_resources.size_flags_horizontal = Control.SIZE_FILL
		_resources.add_theme_constant_override("separation", 4)
	for cell in _resources.get_children():
		if cell != _stores_button:
			(cell as Control).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if landscape else Control.SIZE_EXPAND_FILL
	if landscape:
		_body.add_child(_panel)
		_panel.custom_minimum_size = Vector2(clampf(area.x * 0.34, 620.0, 900.0), 0)
		_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_scroll.custom_minimum_size.y = 0
	else:
		_root.add_child(_panel)
		_panel.custom_minimum_size = Vector2.ZERO
		_panel.size_flags_vertical = Control.SIZE_FILL
		_fit_sheet()


## In portrait the sheet under the map is short while the map matters (a
## hex, a village's plots, a battle), and taller for the sheets that don't
## need it, so that they fit without scrolling.
func _fit_sheet() -> void:
	var area := get_viewport().get_visible_rect().size
	if area.x > area.y * 1.05:
		return
	var tall := _panel_mode != "hex" or (_view == "village" and _tab != "village")
	_scroll.custom_minimum_size.y = area.y * (0.58 if tall else 0.36)
	# The tutorial's card folds while a tall sheet leaves the map little room.
	if tall != _sheet_tall:
		_sheet_tall = tall
		_quest_card.set_open(not tall)
		_refresh_quest_card()


var _sheet_tall := false


## How tall the sheet's scrolling part is.
func _sheet_height() -> float:
	if _scroll.custom_minimum_size.y > 0.0:
		return _scroll.custom_minimum_size.y
	return maxf(_scroll.size.y, 600.0)


## The strip shows the next of your villages' stores (and the sheets it).
func _next_village() -> void:
	var mine := Game.my_villages()
	if mine.size() < 2:
		return
	var at := 0
	for i in mine.size():
		if int(mine[i].id) == Game.current_village_id:
			at = i
	Game.current_village_id = int(mine[(at + 1) % mine.size()].id)
	_plot = Rules.HALL_PLOT
	_rebuild_panel()


## The wood band, with room at the top for a phone's status bar.
func _top_style() -> StyleBox:
	var style := UiTheme.wood_style(14)
	style.content_margin_top = 26
	style.content_margin_left = 18
	style.content_margin_right = 18
	return style


# --- Battle map --------------------------------------------------------------

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
	if battle.status == "ongoing" and _battle_round >= count:
		_panel_body.add_child(UI.label(tr("The fight goes on; the next round comes in %s.") % TimeUtil.format_duration(float(Game.data.battle.roundMinutes) * 60.0 / float(Game.world.speed)), UI.SMALL_SIZE, UI.MUTED))
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


# --- Selection panel ---------------------------------------------------------

func _select(cell: Vector2i) -> void:
	_selected = cell
	_side.erase("hex")
	_road_from = Vector2i.MAX
	hex_map.show_road_targets([])
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
	_renaming = false
	var on_map := view == "map"
	_view_button.text = tr("Village") if on_map else tr("Map")
	_view_button.icon = Art.texture("icon/village" if on_map else "icon/map")
	hex_map.visible = on_map
	_spacer.visible = on_map
	_grade.visible = on_map
	_village_view.visible = view == "village"
	_battle_view.visible = view == "battle"
	_compass.visible = on_map
	_battle_playing = _battle_playing and view == "battle"
	# The map camera listens for unhandled input; keep it still while the
	# village or a battle is open.
	camera.set_process_unhandled_input(on_map)
	_panel_mode = "hex"
	_update_music()
	_rebuild_panel()


func _on_plot_tapped(plot: String) -> void:
	_plot = plot
	_tab = "village"
	_side["buildings"] = "plot"
	_panel_mode = "hex"
	_rebuild_panel()


func _show_threats() -> void:
	_panel_mode = "run" if RunText.is_over(Game.world) else "threats"
	_rebuild_panel()


func _open_run_once() -> void:
	if RunText.is_over(Game.world) and not _run_seen:
		_run_seen = true
		_panel_mode = "run"


# --- Getting started ---------------------------------------------------------

## This player's entry in the world's members ({} if none).
func _me() -> Dictionary:
	for member in Game.world.get("members", []):
		if int(member.accountId) == Game.my_account_id():
			return member
	return {}


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


## "+12/min", or "+0.3/min" for a small rate (a fresh village at speed 1).
static func _per_minute(rate_per_hour: float) -> String:
	var per_minute := rate_per_hour / 60.0
	if absf(per_minute) >= 10.0 or is_zero_approx(per_minute):
		return UI.signed(per_minute)
	return ("+%.1f" if per_minute >= 0 else "−%.1f") % absf(per_minute)


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
	_paged("almanac " + section, AlmanacText.entries(Game.data, section), (2 if long else 3) if _roomy() else (1 if long else 2), func(entry: Array) -> void:
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


## "You command this for Mila until …" on a village handed to you.
func _handed_line(village: Dictionary) -> void:
	if Game.is_mine(village):
		return
	var d := DelegationText.of_owner(Game.delegations, int(village.ownerAccountId), Game.server_now())
	if d.is_empty():
		return
	_panel_body.add_child(UI.label(tr("You command it for %s for %s more; they see what you do.") % [Game.member_name(int(d.ownerAccountId)), TimeUtil.format_duration(TimeUtil.parse_iso(d.until) - Game.server_now())], UI.SMALL_SIZE, UI.ACCENT))


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


## The clan shown in the picker before it is picked.
var _clan_preview := ""


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
		for line in RunText.stats(run):
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


func _rebuild_panel() -> void:
	var focus := get_viewport().gui_get_focus_owner()
	# Only a field still being typed in gets its focus back (not one sent).
	var typing := focus is LineEdit and (focus as LineEdit).is_editing() and _panel_body.is_ancestor_of(focus)
	_focused_draft = String(focus.get_meta("draft", "")) if typing else ""
	_clearing = true
	UI.clear(_panel_body)
	_clearing = false
	_ticking.clear()
	_fit_sheet()
	# A road being laid is dropped once the sheet shows something else.
	if _road_from != Vector2i.MAX and _panel_mode != "hex":
		_road_from = Vector2i.MAX
		hex_map.show_road_targets([])
		_status.text = ""
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
	if _panel_mode == "forces":
		_forces_panel()
		return
	if _view == "village":
		_village_panel()
		return
	if _view == "battle":
		_battle_panel()
		return
	_hex_panel()


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


## Whether `fill` lays anything out: it is tried on a box that is thrown
## away (with whatever it set ticking).
func _has_content(fill: Callable) -> bool:
	var sheet_body := _panel_body
	var ticks := _ticking.size()
	_panel_body = UI.vbox()
	fill.call()
	var any := _panel_body.get_child_count() > 0
	_panel_body.free()
	_panel_body = sheet_body
	_ticking.resize(ticks)
	return any


## Side tabs down the sheet instead of one long scroll: `tabs_` is
## [[key, art id, name, fill], …], and the open tab's `fill` lays out its
## part beside them (it adds to _panel_body, which points there meanwhile).
## Which tab is open is kept per `sheet`. The tabs get smaller as there are
## more of them, to fit in the sheet's height less `above` (what comes
## before them on the sheet).
func _side_tabs(sheet: String, tabs_: Array, above := 90.0) -> void:
	var open := String(_side.get(sheet, ""))
	var fill: Callable = tabs_[0][3]
	var found := false
	for tab in tabs_:
		if tab[0] == open:
			fill = tab[3]
			found = true
	if not found:
		open = tabs_[0][0]
	var size := clampf(floorf((_sheet_height() - above) / tabs_.size()) - 6.0, 56.0, 88.0)
	var pictures := tabs_.map(func(tab: Array) -> Array: return tab.slice(0, 3))
	var layout := UI.side_layout(pictures, open, func(key: String) -> void:
		_side[sheet] = key
		_scroll.scroll_vertical = 0
		_rebuild_panel(), size)
	_panel_body.add_child(layout[0])
	var sheet_body := _panel_body
	_panel_body = layout[1]
	fill.call()
	_panel_body = sheet_body


## A long list a page at a time: `each` lays out the items on the open page,
## then come the arrows to turn it (when there is more than one page).
func _paged(list: String, items: Array, per_page: int, each: Callable) -> void:
	var page := UI.paged(items, int(_pages.get(list, 0)), per_page, func(at: int) -> void:
		_pages[list] = at
		_scroll.scroll_vertical = 0
		_rebuild_panel())
	for item in page[0]:
		each.call(item)
	if page[1].get_child_count() > 0:
		_panel_body.add_child(page[1])


## What the selected empty hex is (laid out at the top of its sheet), and
## the parts of its sheet: [[key, art id, name, fill], …] for _hex_panel.
func _terrain_panel() -> Array:
	var id: String = Game.terrain.get(_selected, "")
	_panel_body.add_child(UI.label(Terrain.display_name(id, Game.data), UI.HEADING_SIZE))
	var distance := HexMath.distance(_selected, Vector2i.ZERO)
	if distance > 0:
		_panel_body.add_child(UI.label(tr_n("%d hex from the Holy City.", "%d hexes from the Holy City.", distance) % distance, UI.SMALL_SIZE, UI.MUTED))
	var camp := Game.camp_at(_selected)
	if not camp.is_empty():
		_panel_body.add_child(UI.label(HordeText.camp(camp, Game.front_faction(camp.front)), UI.SMALL_SIZE, UI.ERROR))
	if Game.fear.has(_selected):
		_panel_body.add_child(UI.label(tr("Hordes fear this place: they were beaten here (%.0f).") % Game.fear[_selected], UI.SMALL_SIZE, UI.MUTED))
	if id == "holy_city":
		_panel_body.add_child(UI.label(HordeText.sanctity(Game.world, Game.data), UI.SMALL_SIZE, UI.MUTED))
		return [["bridge", "ui/hero", tr("Kalinov Bridge"), _bridge_panel], ["vault", "icon/coin", tr("Vault"), _vault_panel]]
	var parts := []
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
	return parts


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
		_panel_body.add_child(UI.button(tr("Send or fetch by caravan"), func() -> void: _open_caravans(0)))


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
	_side["caravans"] = "load"
	_set_view("village")


func _caravans_section(village: Dictionary) -> void:
	var village_id := int(village.id)
	var tabs := [["load", "icon/caravan", tr("Send a caravan"), _caravan_load_tab.bind(village)]]
	if int(village.levels.get("caravan_yard", 0)) >= 1 and not Game.camps.is_empty():
		tabs.append(["escort", "unit/spearman", tr("Escort"), _caravan_escort.bind(village)])
	tabs.append(["road", "icon/map", tr("On the road"), _caravan_trips.bind(village_id)])
	tabs.append(["vault", "settlement/holy_city", tr("Surplus to the vault"), _surplus_order.bind(village_id)])
	_side_tabs("caravans", tabs, VILLAGE_TOP)


func _caravan_load_tab(village: Dictionary) -> void:
	var yard := int(village.levels.get("caravan_yard", 0))
	var capacity := CaravanMath.capacity(Game.data, village.get("bonuses", {}))
	if yard < 1:
		_panel_body.add_child(UI.label(tr("Build a Caravan Yard in the village to send caravans to allies and the Holy City vault."), UI.SMALL_SIZE, UI.MUTED))
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
	var destinations := [[0, tr("Holy City vault")]]
	for other in Game.villages.values():
		if int(other.id) != village_id:
			destinations.append([int(other.id), tr("%s (%s)") % [other.name, Game.member_name(int(other.ownerAccountId))]])
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

	# How much of each: typed in, up to what the village holds.
	var amounts := Ledger.amounts_at(village.resources, Game.server_now())
	for kind in Ledger.KINDS:
		var row := UI.hbox(8)
		row.add_child(UI.icon("resource/%s" % kind, 40))
		var name := UI.label(UI.resource_name(kind), UI.SMALL_SIZE)
		name.custom_minimum_size.x = 90
		row.add_child(name)
		var most := int(floor(float(amounts.get(kind, 0))))
		row.add_child(_number_field("load:%s" % kind, mini(_caravan_load[kind], most), 0, maxi(most, _caravan_load[kind]), func(n: int) -> void:
			_caravan_load[kind] = n))
		var of := UI.label(tr("of %d") % most, UI.SMALL_SIZE, UI.MUTED)
		of.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(of)
		_panel_body.add_child(row)

	var garrison := Rules.garrison_at(village, Game.server_now())
	var escort := func() -> Dictionary: return _picked_units(garrison) if not Game.camps.is_empty() else {}
	var summary := UI.label("", UI.SMALL_SIZE, UI.MUTED)
	_panel_body.add_child(summary)
	var buttons := UI.hbox()
	var send := UI.button(tr("Send"), func() -> void: _send_caravan(village_id, _caravan_to, _caravan_load.duplicate(), escort.call()))
	send.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(send)
	var fetch: Button = null
	if _caravan_to == 0:
		fetch = UI.button(tr("Fetch from vault"), func() -> void: _fetch_from_vault(village_id, _caravan_load.duplicate(), escort.call()))
		fetch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.add_child(fetch)
	# What it takes, and whether it can go, as the numbers are typed.
	_tick(summary, func() -> String:
		var needed := CaravanMath.needed(Game.data, _caravan_load, village.get("bonuses", {}))
		var current: Dictionary = Game.villages.get(village_id, village)
		var affordable := Ledger.can_afford(Ledger.amounts_at(current.resources, Game.server_now()), _caravan_load)
		send.disabled = needed == 0 or needed > free or not affordable
		if fetch != null:
			fetch.disabled = needed == 0 or needed > free
		var line := tr_n("Needs %d caravan", "Needs %d caravans", needed) % needed if needed > 0 else tr("Type how much of each to carry")
		if needed > free:
			line += tr(" (only %d at home)") % free
		var guard: Dictionary = escort.call()
		if not guard.is_empty():
			line += " · " + tr("Escort: %s") % _units_text(guard)
		return line)
	_panel_body.add_child(buttons)


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
			_panel_body.add_child(UI.label(ambushed, UI.SMALL_SIZE, UI.ERROR)))


func _send_caravan(village_id: int, destination: int, cargo: Dictionary, escort: Dictionary) -> void:
	_status.text = ""
	var body := {"destinationVillageId": destination if destination != 0 else null, "load": cargo, "escort": escort}
	var response := await Api.post_json("/v1/villages/%d/caravans" % village_id, body)
	if not response.ok:
		_status.text = response.error
		Sound.effect("error")
		return
	Sound.effect("coins")
	_caravan_load = {"wood": 0, "stone": 0, "grain": 0, "iron": 0}
	_army_units.clear()
	_forget_drafts(["load:", "escort:"])
	Game.note_server_time(response.data.serverTime)
	Game.update_village(response.data.village)


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


## Your research: what you study now, then every branch of the tree. Shows
## which teammates know each tech, so the group can specialize.
## The picture on each research branch's tab.
const BRANCH_ART := {"economy": "resource/grain", "military": "unit/spearman", "fortification": "building/wall_stone",
	"scouting": "unit/scout", "faith": "building/granary_temple_1"}


func _research_section(village: Dictionary) -> void:
	var tabs := [["academy", "building/academy_1", tr("Academy"), _academy_tab.bind(village)]]
	for branch in Game.data.research.branches:
		tabs.append([branch, BRANCH_ART.get(branch, "icon/research"), tr(Game.data.research.branches[branch]), _research_branch.bind(village, branch)])
	_side_tabs("research", tabs, VILLAGE_TOP)


## What you study now, and the group's lore scrolls.
func _academy_tab(village: Dictionary) -> void:
	var academy := int(village.levels.get("academy", 0))
	var mine := ResearchRules.progress(Game.research, Game.my_account_id())
	var current: Dictionary = mine.current
	var techs: Dictionary = Game.data.research.techs
	if academy < 1:
		_panel_body.add_child(UI.label(tr("Build an Academy to research. Research belongs to you and helps all your villages."), UI.SMALL_SIZE, UI.MUTED))
	else:
		_panel_body.add_child(UI.label(tr("Academy Lv %d · %d of %d techs known") % [academy, mine.done.size(), techs.size()], UI.SMALL_SIZE, UI.MUTED))
	# Research comes in from all your Academies; every tech takes some.
	var points := UI.label("", UI.SMALL_SIZE)
	_panel_body.add_child(points)
	_tick(points, func() -> String:
		var research := Game.my_research()
		return tr("Research: %d (+%d per hour from your Academies)") % [floori(research.points), roundi(research.perHour)])
	if not current.is_empty():
		var done_at := TimeUtil.parse_iso(current.completesAt)
		var line := UI.label("", UI.SMALL_SIZE)
		_panel_body.add_child(line)
		var tech_name: String = tr(techs[current.tech].name)
		_tick(line, func() -> String: return tr("Researching %s · %s") % [tech_name, TimeUtil.format_duration(done_at - Game.server_now())])
	elif academy >= 1:
		_panel_body.add_child(UI.label(tr("Nothing being researched: pick a tech from a branch."), UI.SMALL_SIZE, UI.MUTED))
	if Game.lore.is_empty():
		return
	_panel_body.add_child(UI.label(tr("Lore scrolls of the group"), UI.HEADING_SIZE))
	_paged("lore", Game.lore, 5 if _roomy() else 2, func(entry: Dictionary) -> void:
		var def: Dictionary = Game.data.lore.scrolls.get(entry.scroll, {})
		var finder := Game.member_name(int(entry.accountId)) if entry.get("accountId") != null else "?"
		_panel_body.add_child(UI.label(tr("%s (found by %s)") % [tr(def.get("name", entry.scroll)), finder]))
		_panel_body.add_child(UI.label(SiteText.scroll_effect(Game.data, entry.scroll), UI.SMALL_SIZE, UI.MUTED)))


## One branch of the tree, a few techs to a page. Shows which teammates know
## each tech, so the group can specialize.
func _research_branch(village: Dictionary, branch: String) -> void:
	var village_id := int(village.id)
	var academy := int(village.levels.get("academy", 0))
	var mine := ResearchRules.progress(Game.research, Game.my_account_id())
	var done: Dictionary = mine.done
	var current: Dictionary = mine.current
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
		var others := _who_knows(tech)
		if not others.is_empty():
			info.add_child(UI.label(tr("Known by %s") % ", ".join(others), UI.SMALL_SIZE, UI.MUTED))
		var row := UI.hbox()
		row.add_child(info)
		_panel_body.add_child(row)
		if known or (not current.is_empty() and current.tech == tech):
			return
		var problem := ResearchRules.problem(Game.data, tech, academy, done, not current.is_empty(), Game.scrolls())
		var cost: Dictionary = def.cost
		var needed := ResearchRules.research_cost(Game.data, tech)
		var cost_line := UI.rich()
		info.add_child(cost_line)
		var duration := TimeUtil.format_duration(float(def.seconds) / speed)
		var cost_text := tr("%s · %d research · %s") % [UI.costs(cost), needed, duration]
		if problem != "":
			cost_line.text = tr("%s  (%s)") % [cost_text, problem.trim_suffix(".").to_lower()]
			return
		var button := UI.button(tr("Research"), func() -> void: _start_research(village_id, tech))
		button.custom_minimum_size.x = 160
		row.add_child(button)
		_tick(cost_line, func() -> String:
			var home: Dictionary = Game.villages.get(village_id, village)
			var scholarly: bool = Game.my_research().points >= needed
			button.disabled = not scholarly or not Ledger.can_afford(Ledger.amounts_at(home.resources, Game.server_now()), cost)
			return cost_text if scholarly else tr("%s  (not enough research)") % cost_text))


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
		Sound.effect("error")
		return
	Sound.effect("done")
	Game.note_server_time(response.data.serverTime)
	Game.update_village(response.data.village)


# --- Armies ------------------------------------------------------------------

func _armies_section(village: Dictionary) -> void:
	var village_id := int(village.id)
	var defs: Dictionary = Game.data.units.units
	# Armies from this village, and allies' troops standing guard here.
	var here := Game.armies.filter(func(army: Dictionary) -> bool:
		var mine: bool = int(army.homeVillageId) == village_id and army.status != "done"
		var guarding: bool = army.targetVillageId != null and int(army.targetVillageId) == village_id and army.status in ["stationed", "engaged"] and int(army.homeVillageId) != village_id
		return mine or guarding)
	_panel_body.add_child(UI.label(tr("Armies"), UI.HEADING_SIZE))
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
			_tick(line, func() -> String: return ArmyText.status(army, target_name, Game.server_now()))
		else:
			line.text = tr("From %s, standing guard here") % from_name
		row.add_child(info)
		if mine and army.status == "stationed":
			var army_id := int(army.id)
			var recall := UI.button(tr("Call home"), func() -> void: _recall_army(army_id))
			recall.custom_minimum_size.x = 150
			row.add_child(recall)
		_panel_body.add_child(row))

	var rule: Dictionary = village.get("reinforce", {}) if village.get("reinforce") != null else {}
	if rule.is_empty():
		return
	var share := roundi(float(rule.share) * 100.0)
	var range_ := int(rule.range)
	_panel_body.add_child(UI.label(tr("When a battle starts within %d hexes, send %d%% of the troops here to help.") % [range_, share] if share > 0 else tr("This village doesn't send help to battles nearby."), UI.SMALL_SIZE, UI.MUTED))
	# How much goes, then how far: two rows, to fit beside the side tabs.
	var rule_row := UI.hbox(8)
	for option in [0, 25, 50, 75]:
		var b := UI.button("%d%%" % option, func() -> void: _set_reinforce(village_id, option / 100.0, range_))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.x = 0
		b.disabled = option == share
		rule_row.add_child(b)
	_panel_body.add_child(rule_row)
	var range_row := UI.hbox(8)
	range_row.add_child(UI.label(tr("Within"), UI.SMALL_SIZE))
	var reach := [range_]
	range_row.add_child(_number_field("reinforce:%d" % village_id, range_, 0, int(Game.data.armies.reinforce.maxRange), func(n: int) -> void: reach[0] = n))
	var hexes := UI.label(tr("hexes"), UI.SMALL_SIZE)
	hexes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	range_row.add_child(hexes)
	range_row.add_child(UI.button(tr("Set"), func() -> void:
		_drafts.erase("reinforce:%d" % village_id)
		_set_reinforce(village_id, share / 100.0, int(reach[0]))))
	_panel_body.add_child(range_row)


## Troops from this village to another, or to guard the Holy City: where,
## on what orders, and who. Nearest first; `_army_to` 0 is the Holy City.
func _send_troops(village: Dictionary) -> void:
	var village_id := int(village.id)
	var home_units := Rules.garrison_at(village, Game.server_now())
	var here := Vector2i(int(village.q), int(village.r))
	var targets: Array = [{"id": 0, "name": tr("The Holy City"), "at": HOLY_CITY}]
	for v in Game.villages.values():
		if int(v.id) != village_id:
			targets.append({"id": int(v.id), "name": tr("%s (%s)") % [v.name, Game.member_name(int(v.ownerAccountId))], "at": Vector2i(int(v.q), int(v.r))})
	targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return HexMath.distance(here, a.at) < HexMath.distance(here, b.at))
	_panel_body.add_child(UI.label(tr("Send troops"), UI.HEADING_SIZE))
	var labels := targets.map(func(t: Dictionary) -> String:
		var away := HexMath.distance(here, t.at)
		return tr_n("%s · %d hex", "%s · %d hexes", away) % [t.name, away])
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
	var body := {}
	if _army_to == 0:
		# The Holy City: they hold it beside its guard, against every horde
		# that comes to its gates or passes through.
		_panel_body.add_child(UI.label(tr("They stand with the Holy City's guard and fight every horde that reaches it, until called home."), UI.SMALL_SIZE, UI.MUTED))
		body = {"target": {"q": HOLY_CITY.x, "r": HOLY_CITY.y}, "orders": "hold"}
	else:
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
		kind_row.add_child(UI.info(ArmyText.order_text(_army_orders)))
		_panel_body.add_child(kind_row)
		body = {"targetVillageId": _army_to, "orders": _army_orders}
	_unit_pickers(home_units, false, "send")
	var go := UI.button(tr("Send"), func() -> void:
		var order := body.duplicate()
		order.units = _picked_units(home_units)
		_send_army(village_id, order))
	_panel_body.add_child(go)
	_picked_hint(go, home_units)


## Steppers for each fighting unit at home, a few to a page (`list` keeps
## the page); returns the troops picked.
func _unit_pickers(home_units: Dictionary, with_scouts := false, list := "units") -> Dictionary:
	var defs: Dictionary = Game.data.units.units
	var families := ["infantry", "archers", "cavalry", "scout"] if with_scouts else ["infantry", "archers", "cavalry"]
	var fighting := home_units.keys().filter(func(unit: String) -> bool:
		var def: Dictionary = defs.get(unit, {})
		return not def.is_empty() and def.family in families and unit != "settler")
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
		return tr("Type how many of each to send.") if none else "")


## The troops picked in the fields, as many as are at home.
func _picked_units(home_units: Dictionary) -> Dictionary:
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
	_forget_drafts(["units:", "send:", "escort:"])
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
		_panel_body.add_child(UI.with_info(UI.label(tr(kind.get("name", tr("Ancient site"))), UI.HEADING_SIZE), tr(kind.get("description", ""))))
		var explorer := Game.member_name(int(site.exploredBy)) if site.get("exploredBy") != null else "?"
		_panel_body.add_child(UI.label(SiteText.status(Game.data, site, explorer), UI.SMALL_SIZE, UI.ACCENT))
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
		_tick(line, func() -> String: return ArmyText.status(army, where, Game.server_now()))
		row.add_child(info)
		if army.ownerAccountId != null and int(army.ownerAccountId) == Game.my_account_id() and army.status == "stationed":
			var army_id := int(army.id)
			var recall := UI.button(tr("Call home"), func() -> void: _recall_army(army_id))
			recall.custom_minimum_size.x = 150
			row.add_child(recall)
		_panel_body.add_child(row))

	var village_id := int(home.id)
	_panel_body.add_child(UI.label(tr("Send from %s") % home.name, UI.SMALL_SIZE, UI.MUTED))
	var at_home := Rules.garrison_at(home, Game.server_now())
	_unit_pickers(at_home, exploring)
	var hero := Game.my_hero()
	var hero_ready: bool = not hero.is_empty() and hero.status == "home" and hero.villageId != null and int(hero.villageId) == village_id
	if hero_ready:
		var lead := UI.button(tr("%s leads it: %s") % [hero.name, tr("yes") if _army_hero else tr("no")], func() -> void:
			_army_hero = not _army_hero
			_rebuild_panel())
		_panel_body.add_child(lead)
	var go := UI.button({"explore": tr("Explore"), "hold": tr("Hold this hex"), "clear": tr("Storm it")}[orders], func() -> void:
		_send_army(village_id, {"target": {"q": cell.x, "r": cell.y}, "units": _picked_units(at_home), "orders": orders, "withHero": _army_hero and hero_ready}))
	_panel_body.add_child(go)
	_picked_hint(go, at_home)


## A fort on the selected open hex, built from your village.
func _fort_panel(terrain_id: String) -> void:
	var home := _my_village()
	var cell := _selected
	if home.is_empty() or terrain_id == "holy_city" or not FieldRules.passable(Game.data, Game.terrain, cell):
		return
	if not Game.fort_at(cell).is_empty() or not Game.camp_at(cell).is_empty() or not Game.site_at(cell).is_empty():
		return
	var village_id := int(home.id)
	_panel_body.add_child(UI.label(tr("Build a fort"), UI.HEADING_SIZE))
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
	info.add_child(UI.label(tr("Build a fort (+%d%% defense here)") % roundi(float(Game.data.field.fort.defenseBonus) * 100.0)))
	var cost_line := UI.rich()
	info.add_child(cost_line)
	row.add_child(info)
	var button := UI.button(tr("Build fort"), func() -> void: _build_fort(village_id, cell))
	button.custom_minimum_size.x = 160
	row.add_child(button)
	_panel_body.add_child(row)
	var cost_text := tr("%s · %s") % [UI.costs(cost), TimeUtil.format_duration(seconds)]
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
	var names := ["E", "NE", "NW", "W", "SW", "SE"]  # tr
	var open: Array[int] = []
	var built := PackedStringArray()
	for i in 6:
		var other: Vector2i = cell + HexMath.DIRECTIONS[i]
		if roads.has(other):
			built.append("%s%s" % [tr(names[i]), "" if roads[other] == "standing" else tr(" (being built)")])
		elif not home.is_empty() and RiverText.road_problem(Game.data, Game.terrain, Game.rivers, Vector2i(int(home.q), int(home.r)), cell, other) == "":
			open.append(i)
	if built.is_empty() and open.is_empty():
		return
	_panel_body.add_child(UI.with_info(UI.label(tr("Roads"), UI.HEADING_SIZE), tr("Roads halve the march for everyone on them, the human hordes too, but the beasts of the North keep off them.")))
	if not built.is_empty():
		_panel_body.add_child(UI.label(tr("Roads run %s.") % ", ".join(built), UI.SMALL_SIZE))
	if open.is_empty():
		return
	# One button; then the hex the road goes to is tapped on the map.
	var cost: Dictionary = Game.data.field.road.cost
	var info := UI.rich("", UI.SMALL_SIZE, UiTheme.TEXT)
	_panel_body.add_child(info)
	var village_id := int(home.id)
	var targets: Array = open.map(func(i: int) -> Vector2i: return cell + HexMath.DIRECTIONS[i])
	var build := UI.button(tr("Build a road"), func() -> void:
		_road_from = cell
		_road_village = village_id
		hex_map.show_road_targets(targets)
		_status.text = tr("Tap the hex next to this one to build the road to."), "icon/map")
	_panel_body.add_child(build)
	var text := tr("A road: %s · %s") % [UI.costs(cost), TimeUtil.format_duration(float(Game.data.field.road.buildSeconds) / float(Game.world.speed))]
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
		info.add_child(UI.label(tr("Last: %s") % order.lastResult, UI.SMALL_SIZE, UI.MUTED))
	row.add_child(info)
	var village_id := int(order.villageId)
	var order_id := int(order.id)
	var cancel := UI.button(tr("Stop"), func() -> void: _cancel_order(village_id, order_id))
	cancel.custom_minimum_size.x = 110
	row.add_child(cancel)
	_panel_body.add_child(row)


## Repeat training: one order per unit, keeping a target count.
func _repeat_order(village: Dictionary) -> void:
	var village_id := int(village.id)
	_panel_body.add_child(UI.label(tr("Repeat training (checked every %d game minutes)") % int(Game.data.orders.checkMinutes), UI.SMALL_SIZE, UI.MUTED))
	for order in Game.orders_of(village_id, "train"):
		_order_row(order)
	var units: Dictionary = Game.data.units.units
	var names := units.keys()
	var picker := UI.options(names.map(func(u: String) -> String: return tr(units[u].name)), maxi(0, names.find(_repeat_unit)))
	picker.item_selected.connect(func(i: int) -> void:
		_repeat_unit = names[i]
		_rebuild_panel())
	_panel_body.add_child(picker)
	# How many to keep, and how many to train at a time: typed in.
	var row := UI.hbox(8)
	row.add_child(UI.label(tr("Keep"), UI.SMALL_SIZE))
	row.add_child(_number_field("repeat:target", _repeat_target, 1, 999, func(n: int) -> void: _repeat_target = n))
	row.add_child(UI.label(tr("ready, training"), UI.SMALL_SIZE))
	row.add_child(_number_field("repeat:batch", _repeat_batch, 1, int(Game.data.units.maxBatch), func(n: int) -> void: _repeat_batch = n))
	row.add_child(UI.label(tr("at a time"), UI.SMALL_SIZE))
	_panel_body.add_child(row)
	var unit := _repeat_unit
	var place := UI.button(tr("Keep %s topped up") % tr(units[unit].name), func() -> void:
		_place_order(village_id, {"kind": "train", "unit": unit, "batch": mini(_repeat_batch, _repeat_target), "target": _repeat_target}))
	place.disabled = not Game.orders_of(village_id, "train").filter(func(o: Dictionary) -> bool: return o.unit == unit).is_empty()
	_panel_body.add_child(place)


func _rebuild_order(village_id: int) -> void:
	var existing := Game.orders_of(village_id, "rebuild")
	if existing.is_empty():
		_panel_body.add_child(UI.button(tr("Rebuild raided outposts automatically"), func() -> void: _place_order(village_id, {"kind": "rebuild"})))
	for order in existing:
		_order_row(order)


func _surplus_order(village_id: int) -> void:
	var existing := Game.orders_of(village_id, "surplus")
	_panel_body.add_child(UI.with_info(UI.label(tr("Surplus to the vault"), UI.HEADING_SIZE), tr("Caravans take what is above this share of storage to the Holy City vault.")))
	for order in existing:
		_order_row(order)
	if not existing.is_empty():
		return
	var limits: Dictionary = Game.data.orders.surplusShare
	var row := UI.hbox(8)
	row.add_child(UI.label(tr("Above"), UI.SMALL_SIZE))
	row.add_child(_number_field("surplus", _surplus_share, roundi(float(limits.min) * 100.0), roundi(float(limits.max) * 100.0), func(n: int) -> void:
		_surplus_share = n))
	var text := UI.label(tr("% of storage"), UI.SMALL_SIZE)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var place := UI.button(tr("Start"), func() -> void: _place_order(village_id, {"kind": "surplus", "share": _surplus_share / 100.0}))
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
	var open := UI.button(tr("Hero"), func() -> void:
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
	var title := UI.label(tr("%s  Lv %d") % [hero.name, int(hero.level)], UI.HEADING_SIZE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(UI.button(tr("Close"), func() -> void:
		_panel_mode = "hex"
		_rebuild_panel()))
	_panel_body.add_child(top)
	var kind: Variant = hero.get("kind")
	var face := "hero/%s" % kind if kind != null and Art.has("hero/%s" % kind) else "ui/hero"
	_side_tabs("hero", [["about", face, tr("Your hero"), _hero_about.bind(hero)],
		["quests", "site/kurgan", tr("Quests"), _quest_section.bind(hero)],
		["stats", "icon/troops", tr("Stats"), _hero_stats.bind(hero)],
		["skills", "icon/research", tr("Skills"), _hero_skills.bind(hero)],
		["gear", "resource/iron", tr("Gear"), _hero_gear.bind(hero)],
		["journey", "icon/map", tr("Send to"), _hero_journey.bind(hero)]])


## Who it is: the portrait, the roster hero's strengths and traits, where
## it is and how far to the next level.
func _hero_about(hero: Dictionary) -> void:
	var kind: Variant = hero.get("kind")
	if not HeroText.roster(Game.data, kind).is_empty():
		var card := UI.hbox(14)
		var face := HeroText.portrait(kind, 104.0)
		face.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		card.add_child(face)
		var about := UI.vbox(4)
		about.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		about.add_child(UI.label(tr(HeroText.roster(Game.data, kind).title), 0, UI.ACCENT))
		about.add_child(UI.label(tr("In all your villages: %s") % HeroText.effects(HeroText.roster(Game.data, kind).effects), UI.SMALL_SIZE))
		for line in HeroText.roster_traits(Game.data, kind):
			about.add_child(UI.label(line, UI.SMALL_SIZE, UI.MUTED))
		card.add_child(about)
		_panel_body.add_child(card)
	var status := UI.label("", UI.SMALL_SIZE)
	_panel_body.add_child(status)
	_tick(status, func() -> String: return HeroText.whereabouts(hero, -1, Game.village_name(hero.villageId), Game.server_now()))
	var xp_text := tr("XP %d / %d") % [int(hero.xp), int(hero.xpToNext)] if hero.xpToNext != null else tr("Highest level")
	var skill_word := tr_n("skill point", "skill points", int(hero.skillPoints))
	_panel_body.add_child(UI.with_info(UI.label(tr("%s · %d %s") % [xp_text, int(hero.skillPoints), skill_word], UI.SMALL_SIZE, UI.MUTED),
		tr("XP comes from enemies slain while leading a garrison.")))
	var effects := HeroText.effects(hero.bonuses)
	if effects != "":
		_panel_body.add_child(UI.label(tr("Adds where it stands: %s") % effects, UI.SMALL_SIZE, UI.MUTED))


## What the hero adds, and from where: its own gifts (in all your
## villages), its skills and its gear (where it stands), and the total.
func _hero_stats(hero: Dictionary) -> void:
	_panel_body.add_child(UI.with_info(UI.label(tr("Stats"), UI.HEADING_SIZE),
		tr("Its own gifts count in all your villages; what its skills and gear add counts where it stands, and for the army it leads.")))
	var xp_text := tr("XP %d / %d") % [int(hero.xp), int(hero.xpToNext)] if hero.xpToNext != null else tr("Highest level")
	_panel_body.add_child(UI.label(tr("Level %d · %s") % [int(hero.level), xp_text], UI.SMALL_SIZE, UI.MUTED))
	for line in HeroText.base_stats(Game.data, hero, float(Game.world.speed)):
		_panel_body.add_child(UI.label(line, UI.SMALL_SIZE))
	var parts := HeroText.breakdown(Game.data, hero)
	if parts.is_empty():
		_panel_body.add_child(UI.label(tr("No bonuses yet."), UI.SMALL_SIZE, UI.MUTED))
		return
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	for heading in [tr("Bonus"), tr("Own"), tr("Skills"), tr("Gear"), tr("Total")]:
		var head := UI.label(heading, UI.SMALL_SIZE, UI.MUTED)
		head.autowrap_mode = TextServer.AUTOWRAP_OFF
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if heading == tr("Bonus") else HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(head)
	for key in parts:
		var name := UI.label(HeroText.effect_name(key), UI.SMALL_SIZE)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name)
		for column in 4:
			var value: float = parts[key][column]
			var cell := UI.label(HeroText.percent(value), UI.SMALL_SIZE,
				UiTheme.INK if column < 3 or is_zero_approx(value) else (UI.GOOD if HeroText.helps(key, value) else UI.ERROR))
			cell.autowrap_mode = TextServer.AUTOWRAP_OFF
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(cell)
	_panel_body.add_child(grid)


## The skill tree, a branch to a page on a phone.
func _hero_skills(hero: Dictionary) -> void:
	var data: Dictionary = Game.data.heroes
	var skill_word := tr_n("skill point", "skill points", int(hero.skillPoints))
	_panel_body.add_child(UI.label(tr("%d %s to spend") % [int(hero.skillPoints), skill_word], UI.SMALL_SIZE, UI.MUTED))
	_paged("hero skills", data.branches.keys(), 1, func(branch: String) -> void:
		_panel_body.add_child(UI.label(tr(data.branches[branch]), UI.HEADING_SIZE))
		for skill in data.skills:
			var def: Dictionary = data.skills[skill]
			if def.branch != branch:
				continue
			var rank := int(hero.skills.get(skill, 0))
			var row := UI.hbox()
			var info := UI.vbox(2)
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			info.add_child(UI.label(tr("%s  %d/%d") % [tr(def.name), rank, int(def.maxRank)]))
			info.add_child(UI.label(tr(def.description), UI.SMALL_SIZE, UI.MUTED))
			row.add_child(info)
			if rank < int(def.maxRank) and int(hero.skillPoints) > 0:
				var learn := UI.button("+", func() -> void: _hero_action("skills", {"skill": skill}))
				learn.custom_minimum_size.x = 90
				row.add_child(learn)
			_panel_body.add_child(row))


## What the hero wears, and what it carries to wear.
func _hero_gear(hero: Dictionary) -> void:
	var data: Dictionary = Game.data.heroes
	_panel_body.add_child(UI.label(tr("Gear"), UI.HEADING_SIZE))
	for slot in data.slots:
		var item: Variant = hero.gear.get(slot)
		var row := UI.hbox()
		var worn := UI.vbox(0)
		worn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		worn.add_child(UI.label(tr("%s: %s") % [String(slot).capitalize(), tr(data.items[item].name) if item != null else "—"], UI.SMALL_SIZE))
		if item != null:
			worn.add_child(UI.label(HeroText.effects(data.items[item].effects), UI.SMALL_SIZE, UI.GOOD))
		row.add_child(worn)
		if item != null:
			var off := UI.button(tr("Take off"), func() -> void: _hero_action("unequip", {"slot": slot}))
			off.custom_minimum_size.x = 150
			row.add_child(off)
		_panel_body.add_child(row)
	# Sets: what wearing all of one adds, and how much of it is worn.
	var wearing: Array = hero.gear.values()
	for set_id in data.get("sets", {}):
		var set_def: Dictionary = data.sets[set_id]
		var have: int = set_def.items.filter(func(it: String) -> bool: return it in wearing).size()
		if have > 0:
			_panel_body.add_child(UI.label(tr("%s set (%d of %d worn): %s") % [tr(set_def.get("name", set_id)), have, set_def.items.size(), HeroText.effects(set_def.effects)],
				UI.SMALL_SIZE, UI.GOOD if have == set_def.items.size() else UI.MUTED))
	if hero.inventory.is_empty():
		_panel_body.add_child(UI.with_info(UI.label(tr("No gear yet."), UI.SMALL_SIZE, UI.MUTED), tr("Beaten hordes sometimes leave gear behind for a hero who fought them.")))
	_paged("hero gear", hero.inventory, 4 if _roomy() else 2, func(item: String) -> void:
		var def: Dictionary = data.items[item]
		var row := UI.hbox()
		var info := UI.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UI.label(tr("%s (%s)") % [tr(def.name), def.slot]))
		info.add_child(UI.label(HeroText.effects(def.effects), UI.SMALL_SIZE, UI.MUTED))
		row.add_child(info)
		var wear := UI.button(tr("Wear"), func() -> void: _hero_action("equip", {"item": item}))
		wear.custom_minimum_size.x = 120
		row.add_child(wear)
		_panel_body.add_child(row))


## Send the hero to another of your villages, or rename it.
func _hero_journey(hero: Dictionary) -> void:
	var mine := Game.my_villages().filter(func(v: Dictionary) -> bool:
		return Game.is_mine(v) and (hero.villageId == null or int(hero.villageId) != int(v.id)))
	_panel_body.add_child(UI.label(tr("Send to"), UI.HEADING_SIZE))
	if mine.is_empty():
		_panel_body.add_child(UI.label(tr("Found another village to send the hero there."), UI.SMALL_SIZE, UI.MUTED))
	_paged("hero journey", mine, 6 if _roomy() else 3, func(village: Dictionary) -> void:
		var target := int(village.id)
		var go := UI.button(village.name, func() -> void: _hero_action("move", {"villageId": target}), Art.settlement_id(Rules.hall_level(village)))
		go.disabled = hero.status != "home"
		_panel_body.add_child(go))
	_panel_body.add_child(UI.label(tr("Name"), UI.HEADING_SIZE))
	var key := "hero:%d" % int(hero.accountId)
	var name_edit := _draft_field(key, tr("New name"), hero.name)
	_panel_body.add_child(name_edit)
	var rename := func(_text := "") -> void:
		if await _hero_action("rename", {"name": name_edit.text.strip_edges()}):
			_drafts.erase(key)
	name_edit.text_submitted.connect(rename)
	_panel_body.add_child(UI.button(tr("Rename"), rename))


## The quests the hero is offered, or the one it is on.
func _quest_section(hero: Dictionary) -> void:
	_panel_body.add_child(UI.with_info(UI.label(tr("Quests"), UI.HEADING_SIZE), tr("The hero rides out alone: no garrison to lead while away, and a chance to come back wounded. New quests every few hours.")))
	var kinds: Dictionary = Game.data.get("quests", {}).get("kinds", {})
	if hero.status == "questing" and hero.get("quest") is Dictionary:
		var quest: Dictionary = hero.quest
		_panel_body.add_child(UI.label(tr(kinds.get(String(quest.kind), {}).get("name", "")), 0, UI.ACCENT))
		_panel_body.add_child(UI.label(HeroText.quest_description(Game.data, quest, _site_name(quest.get("siteId"))), UI.SMALL_SIZE, UI.MUTED))
		var back := UI.label("", UI.SMALL_SIZE)
		_panel_body.add_child(back)
		_tick(back, func() -> String: return tr("Back in %s") % TimeUtil.format_duration(TimeUtil.parse_iso(String(quest.returnsAt)) - Game.server_now()))
		return
	var offers: Array = hero.get("offers", [])
	if offers.is_empty():
		_panel_body.add_child(UI.label(tr("No quests while the hero is away, wounded or leading an army."), UI.SMALL_SIZE, UI.MUTED))
		return
	_paged("quests", offers, 3 if _roomy() else 1, func(offer: Dictionary) -> void:
		var row := UI.hbox()
		var info := UI.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UI.label(tr(kinds.get(String(offer.kind), {}).get("name", ""))))
		info.add_child(UI.label(HeroText.quest_description(Game.data, offer, _site_name(offer.get("siteId"))), UI.SMALL_SIZE, UI.MUTED))
		info.add_child(UI.label(HeroText.quest_terms(offer, float(Game.world.get("speed", 1))), UI.SMALL_SIZE))
		row.add_child(info)
		var go := UI.primary(tr("Set out"), func() -> void: _hero_action("quest", {"offer": String(offer.id)}))
		go.disabled = hero.status != "home"
		go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(go)
		_panel_body.add_child(row))


## The name of an ancient site by its id ("" if unknown).
func _site_name(site_id: Variant) -> String:
	if site_id == null:
		return ""
	for site in Game.sites:
		if int(site.id) == int(site_id):
			return tr(Game.data.get("sites", {}).get("kinds", {}).get(String(site.kind), {}).get("name", ""))
	return ""


## True when the server took it.
func _hero_action(action: String, body: Dictionary) -> bool:
	_status.text = ""
	var response := await Api.post_json("/v1/worlds/%d/hero/%s" % [Game.world_id(), action], body)
	if not response.ok:
		_status.text = response.error
		return false
	Game.note_server_time(response.data.serverTime)
	var updated: Dictionary = response.data.hero
	var heroes := Game.heroes.filter(func(h: Dictionary) -> bool: return int(h.accountId) != int(updated.accountId))
	heroes.append(updated)
	Game.set_heroes(Game.world_id(), heroes)
	return true


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
			parts.append(tr("%s +%d/h") % [UI.resource_name(kind), roundi(float(amounts[kind]))])
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
	var troops := UI.label("", UI.SMALL_SIZE, UI.MUTED)
	_panel_body.add_child(troops)
	_tick(troops, func() -> String: return _units_text(Rules.garrison_at(village, Game.server_now())))
	var their_hero := Game.hero_at(int(village.id))
	if not their_hero.is_empty():
		_panel_body.add_child(UI.label(tr("Hero %s (Lv %d) leads the garrison") % [their_hero.name, int(their_hero.level)], UI.SMALL_SIZE, UI.MUTED))
	if not _my_village().is_empty():
		var ally_id := int(village.id)
		_panel_body.add_child(UI.button(tr("Send resources"), func() -> void: _open_caravans(ally_id)))


## Your village as seen on the map: a summary and the way in.
func _own_village_panel(village: Dictionary) -> void:
	_panel_body.add_child(UI.label(village.name, UI.HEADING_SIZE))
	_handed_line(village)
	var hall := Rules.hall_level(village)
	var queue: Array = village.queue
	_panel_body.add_child(UI.label(tr("Elder's Hall Lv %d · building %d of %d · outposts %d of %d") % [hall, queue.size(), Rules.queue_limit(Game.data, hall),
		Rules.outpost_plots(village).size(), Rules.outpost_limit(Game.data, hall)], UI.SMALL_SIZE, UI.MUTED))
	if village.get("besieged", false):
		_panel_body.add_child(UI.label(tr("Under siege: outposts produce nothing until the battle ends."), UI.SMALL_SIZE, UI.ERROR))
	if village.get("ruin") is Dictionary:
		_panel_body.add_child(UI.label(tr("In ruins: rebuild it from the village view."), UI.SMALL_SIZE, UI.ERROR))
	if village.get("refuge", false):
		_panel_body.add_child(UI.with_info(UI.label(tr("A refugee camp"), UI.SMALL_SIZE, UI.MUTED), tr("Hordes raid a refugee camp but never burn it.")))
	var village_id := int(village.id)
	var troops := UI.label("", UI.SMALL_SIZE, UI.MUTED)
	_panel_body.add_child(troops)
	_tick(troops, func() -> String:
		return _units_text(Rules.garrison_at(Game.villages.get(village_id, village), Game.server_now())))
	_panel_body.add_child(UI.button(tr("Enter village"), func() -> void: _set_view("village")))
	_hero_line(village_id)


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


## A name field whose text, caret and focus outlive the panel's rebuilds:
## typing is kept in _drafts under `key` until the caller erases it.
func _draft_field(key: String, placeholder: String, text: String) -> LineEdit:
	var draft: Dictionary = _drafts.get(key, {})
	var field := UI.line_edit(placeholder, String(draft.get("text", text)))
	field.max_length = 32
	field.set_meta("draft", key)
	field.text_changed.connect(func(typed: String) -> void:
		_drafts[key] = {"text": typed, "caret": field.caret_column})
	# (LineEdit has no caret signal: the caret is kept as of the last keystroke.)
	# Refocused even before anything is typed: a rebuild (a live update, the
	# keyboard resizing the window) must not close the keyboard just opened.
	if key == _focused_draft:
		var caret := int(draft.get("caret", field.text.length()))
		var refocus := func() -> void:
			if is_instance_valid(field):
				field.grab_focus()
				field.caret_column = caret
		refocus.call_deferred()
	return field


## Drops what was typed in the fields whose keys start so (once it is sent).
func _forget_drafts(prefixes: Array) -> void:
	for key in _drafts.keys():
		if prefixes.any(func(prefix: String) -> bool: return String(key).begins_with(prefix)):
			_drafts.erase(key)


## A field to type a number in, with − and + beside it to step it by one;
## what is typed outlives the panel's rebuilds (like _draft_field). `on_set`
## gets each number typed or stepped to, held within min..max; when done
## typing the field shows it.
func _number_field(key: String, value: int, min_value: int, max_value: int, on_set: Callable) -> Control:
	var field := _number_input(key, value, min_value, max_value, on_set)
	var step := func(by: int) -> void:
		var typed := field.text.strip_edges()
		var number := clampi((int(typed) if typed.is_valid_int() else value) + by, min_value, max_value)
		field.text = str(number)
		_drafts.erase(key)
		on_set.call(number)
	var row := UI.hbox(4)
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for part: Array in [["−", -1], ["+", 1]]:
		var button := UI.button(part[0], step.bind(part[1]))
		button.custom_minimum_size.x = 56
		# Tapping a step keeps the keyboard (and the field's focus) as it is.
		button.focus_mode = Control.FOCUS_NONE
		row.add_child(button)
		if part[1] < 0:
			row.add_child(field)
	return row


func _number_input(key: String, value: int, min_value: int, max_value: int, on_set: Callable) -> LineEdit:
	var field := _draft_field(key, "", str(value))
	field.max_length = 7
	field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	field.custom_minimum_size.x = 110
	field.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	field.select_all_on_focus = true
	field.text_changed.connect(func(typed: String) -> void:
		if typed.strip_edges().is_valid_int():
			on_set.call(clampi(int(typed.strip_edges()), min_value, max_value)))
	var done := func(_text := "") -> void:
		# A rebuild takes the focus away too: the draft stays for the new field.
		if _clearing or not is_instance_valid(field):
			return
		var typed := field.text.strip_edges()
		var number := clampi(int(typed) if typed.is_valid_int() else value, min_value, max_value)
		field.text = str(number)
		_drafts.erase(key)
		on_set.call(number)
	field.text_submitted.connect(done)
	field.focus_exited.connect(done)
	return field


func _village_panel() -> void:
	var village := _my_village()
	if village.is_empty():
		return
	_village_view.show_village(Game.data, village, _plot)
	_town_switcher(village)
	if village.get("ruin") is Dictionary:
		_ruin_section(village)
		return
	var tabs := [["village", tr("Buildings"), "icon/build"], ["troops", tr("Troops"), "icon/troops"], ["caravans", tr("Caravans"), "icon/caravan"], ["research", tr("Research"), "icon/research"]]
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


## What comes before the side tabs on a village's sheet: the town's name
## and the village's tabs.
const VILLAGE_TOP := 170.0


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
	_panel_body.add_child(UI.label(tr("A horde burned it down. Rebuild everything as it stood, at %d%% of what it cost.") % roundi(float(Game.data.horde.ruins.rebuildCostShare) * 100.0), UI.SMALL_SIZE, UI.MUTED))
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
	for item in queue:
		var done_at := TimeUtil.parse_iso(item.completesAt)
		var text := tr("%s → Lv %d") % [tr(_building_def(item.building).name), int(item.targetLevel)]
		var line := UI.label()
		_panel_body.add_child(line)
		_tick(line, func() -> String:
			var left := done_at - Game.server_now()
			return tr("%s   %s") % [text, TimeUtil.format_duration(left) if left > 0 else tr("finishing…")])


func _outposts_section(village: Dictionary) -> void:
	var plots := Rules.outpost_plots(village)
	var limit := Rules.outpost_limit(Game.data, Rules.hall_level(village))
	_panel_body.add_child(UI.label(tr("Outposts (%d/%d)") % [plots.size(), limit], UI.SMALL_SIZE, UI.MUTED))
	if village.get("besieged", false):
		_panel_body.add_child(UI.label(tr("Under siege: outposts produce nothing until the battle ends."), UI.SMALL_SIZE, UI.ERROR))
	if not plots.is_empty():
		_rebuild_order(int(village.id))
	if plots.is_empty():
		_panel_body.add_child(UI.label(tr("None yet. Tap a forest, plains, hills, mountain or lake hex within %d of the village on the map to claim one.") % int(Game.data.buildings.village.outpostRange), UI.SMALL_SIZE, UI.MUTED))
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
		var options := Rules.constructible(Game.data, village, "tower" if on_walls else "center")
		if options.is_empty():
			_panel_body.add_child(UI.label(tr("Every tower already stands on these walls.") if on_walls else tr("Every building already stands in this village."), UI.SMALL_SIZE, UI.MUTED))
		_paged("plot options", options, 5 if _roomy() else 2, func(building: String) -> void:
			if on_walls:
				_panel_body.add_child(UI.label(WallText.tower_effect(Game.data, building, 0), UI.SMALL_SIZE, UI.MUTED))
			var missing := Rules.missing_requirement(Game.data, village, building)
			if not missing.is_empty():
				_panel_body.add_child(UI.with_card(UI.label(tr(_building_def(building).name)), _building_card(village, building, 0)))
				_panel_body.add_child(UI.label(tr("Needs %s level %d") % [tr(_building_def(missing[0]).name), missing[1]], UI.SMALL_SIZE, UI.ERROR))
				return
			_build_row(village, _plot, building, 1, tr("Build")))
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
	if target > int(def.maxLevel):
		_panel_body.add_child(UI.label(tr("Max level"), UI.SMALL_SIZE, UI.MUTED))
	else:
		_build_row(village, _plot, building, target, tr("Build") if level == 0 and int(planned.level) == 0 else tr("Upgrade"))
	if building == "market" and level > 0:
		_market_section(village, level)
	_demolish_row(village, building, level)
	if building == Rules.HALL:
		_abandon_row(village)


## What the village's Market does: trade one resource for another, and buy
## the hero's spare gear.
var _trade := {"give": "wood", "get": "iron", "amount": 100}

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


## Tearing a building down gives back part of what it cost; it asks twice.
var _demolish_armed := ""

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


## Giving up a whole village (from its Elder's Hall); it asks twice.
var _abandon_armed := 0

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
	info.add_child(UI.with_card(UI.label(tr("%s → Lv %d") % [tr(def.name), target]), _building_card(village, building, target - 1)))
	var cost_line := UI.rich()
	info.add_child(cost_line)
	row.add_child(info)
	var button := UI.primary(verb, func() -> void: _queue_build(village_id, plot, building))
	button.custom_minimum_size.x = 160
	row.add_child(button)
	_panel_body.add_child(row)
	var cost_text := tr("%s · %s") % [UI.costs(cost), TimeUtil.format_duration(seconds)]
	_tick(cost_line, func() -> String:
		var home: Dictionary = Game.villages.get(village_id, village)
		var affordable := Ledger.can_afford(Ledger.amounts_at(home.resources, Game.server_now()), cost)
		button.disabled = queue_full or not affordable
		return cost_text + (tr("  (queue full)") if queue_full else ""))


## Opens the card of `building` (BuildingInfo) with its build times in
## `village` (its Hall and research), `level` marked.
func _building_card(village: Dictionary, building: String, level: int) -> Callable:
	return func() -> Control:
		var factor := Rules.hall_speedup(Game.data, Rules.hall_level(village)) * ResearchRules.time_factor(village.get("bonuses", {}), "buildTime")
		return BuildingInfo.card(Game.data, building, float(Game.world.speed), factor, level)


## Opens the card of `unit` with its training time in `village`.
func _unit_card(village: Dictionary, unit: String) -> Callable:
	return func() -> Control:
		var def: Dictionary = Game.data.units.units[unit]
		return BuildingInfo.unit_card(Game.data, unit, float(Game.world.speed), maxi(1, int(village.levels.get(def.building, 1))),
			Game.villages_owned(int(village.ownerAccountId)), ResearchRules.time_factor(village.get("bonuses", {}), "trainTime"))


## What a building does at its level, and at the next one.
func _effect_text(village: Dictionary, building: String, level: int) -> String:
	var def := _building_def(building)
	var speed := float(Game.world.speed)
	if def.has("production"):
		var resource: String = def.production.resource
		return tr("%s +%d/h now, +%d/h at level %d") % [UI.resource_name(resource),
			roundi(Rules.field_production(def, level, speed)), roundi(Rules.field_production(def, level + 1, speed)), level + 1]
	if building == Rules.HALL:
		var total := int(Game.data.buildings.village.centerSlots)
		var text := tr("%d of %d building slots open, build queue %d.") % [Rules.unlocked_slots(Game.data, level), total, Rules.queue_limit(Game.data, level)]
		if level < int(def.maxLevel):
			text += tr(" Level %d: %d slots, queue %d, builds %d%% faster than level 1.") % [level + 1,
				Rules.unlocked_slots(Game.data, level + 1), Rules.queue_limit(Game.data, level + 1),
				roundi((1.0 - Rules.hall_speedup(Game.data, level + 1)) * 100.0)]
		return text
	if def.get("kind") == "wall":
		return WallText.wall_effect(Game.data, level)
	if def.get("kind") == "tower":
		return WallText.tower_effect(Game.data, building, level)
	if def.has("capacityGrowth"):
		var base := float(Game.data.buildings.village.baseCapacity)
		var total := roundi(float(village.get("resources", {}).get("capacity", {}).get("wood", base)))
		return tr("Holds %d of each resource above the base; the village keeps %d in all") % [roundi(base * (pow(float(def.capacityGrowth), level) - 1.0)), total]
	if def.has("research"):
		var research: Dictionary = def.research
		var per_hour := func(l: int) -> int: return roundi(float(research.basePerHour) * pow(float(research.growth), l - 1) * speed) if l > 0 else 0
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


func _troops_section(village: Dictionary) -> void:
	var hall := Rules.hall_level(village)
	_side_tabs("troops", [["garrison", Art.settlement_id(hall), tr("Garrison"), _garrison_tab.bind(village)],
		["train", "unit/spearman", tr("Train"), _train_tab.bind(village)],
		["orders", "icon/clock", tr("Repeat training"), _repeat_order.bind(village)],
		["armies", "icon/troops", tr("Armies"), _armies_section.bind(village)],
		["send", "unit/border_rider", tr("Send troops"), _send_troops.bind(village)]], VILLAGE_TOP)


## Who guards the village and how they fight: the stance, the hero, the
## troops at home and away, settlers on the road.
func _garrison_tab(village: Dictionary) -> void:
	var village_id := int(village.id)
	_stance_picker(village)
	_hero_line(village_id)
	var recommended := Rules.recommended_garrison(Game.data, Game.villages_owned(int(village.ownerAccountId)))
	var guard := UI.label("", UI.SMALL_SIZE, UI.MUTED)
	_panel_body.add_child(guard)
	_tick(guard, func() -> String:
		var home_now := BattleText.total(Rules.garrison_at(Game.villages.get(village_id, village), Game.server_now()))
		return tr("Recommended garrison: %d (%d at home)") % [recommended, home_now])
	_expeditions_list(village_id)
	_panel_body.add_child(UI.label(tr("At home"), UI.SMALL_SIZE, UI.MUTED))
	var home := UI.label()
	_panel_body.add_child(home)
	_tick(home, func() -> String:
		return _units_text(Rules.garrison_at(Game.villages.get(village_id, village), Game.server_now())))

	var away: Dictionary = village.get("away", {}).duplicate()
	for unit in away.keys():
		if int(away[unit]) <= 0:
			away.erase(unit)
	if not away.is_empty():
		_panel_body.add_child(UI.label(tr("Away: %s") % _units_text(away), UI.SMALL_SIZE, UI.MUTED))


## Who is in training, and what the village can train, a few to a page.
func _train_tab(village: Dictionary) -> void:
	var village_id := int(village.id)
	var units: Dictionary = Game.data.units.units
	var training: Array = village.training
	var limit := int(Game.data.units.trainingQueueLimit)
	_panel_body.add_child(UI.label(tr("Training (%d/%d)") % [training.size(), limit], UI.SMALL_SIZE, UI.MUTED))
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

	var queue_full := training.size() >= limit
	var max_batch := int(Game.data.units.maxBatch)
	# What the village can train first, then what it could with more building.
	var allowed := units.keys().filter(func(unit: String) -> bool: return ClanText.allowed(units[unit], village.get("bonuses", {})))
	var ready := func(unit: String) -> bool: return int(village.levels.get(units[unit].building, 0)) >= int(units[unit].requiresLevel)
	var trainable := allowed.filter(ready) + allowed.filter(func(unit: String) -> bool: return not ready.call(unit))
	_paged("train", trainable, 3 if _roomy() else 2, func(unit: String) -> void:
		var def: Dictionary = units[unit]
		var building_level := int(village.levels.get(def.building, 0))
		var unlocked := building_level >= int(def.requiresLevel)
		var card := UI.hbox(12)
		if Art.has("unit/%s" % unit):
			var picture := UI.icon("unit/%s" % unit, 64)
			picture.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			card.add_child(picture)
		var info := UI.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_child(info)
		info.add_child(UI.with_card(UI.label(tr(def.name)), _unit_card(village, unit)))
		info.add_child(UI.label(tr("%s · atk %d · def %d · %d grain/h") % [def.family.capitalize(), def.attack, def.defense, def.upkeepPerHour], UI.SMALL_SIZE, UI.MUTED))
		_panel_body.add_child(card)
		if not unlocked:
			info.add_child(UI.label(tr("Needs %s level %d") % [tr(_building_def(def.building).name), def.requiresLevel], UI.SMALL_SIZE, UI.ERROR))
			return
		var cost_line := UI.rich()
		info.add_child(cost_line)

		# How many: typed in; the cost and the button follow as it is typed.
		var row := UI.hbox()
		info.add_child(row)
		row.add_child(_number_field("train:%s" % unit, int(_train_counts.get(unit, 1)), 1, max_batch, func(n: int) -> void:
			_train_counts[unit] = n))
		var train := UI.primary(tr("Train"), func() -> void: _train(village_id, unit, int(_train_counts.get(unit, 1))))
		train.custom_minimum_size.x = 120
		row.add_child(train)
		var seconds := float(def.trainSeconds) * pow(float(Game.data.units.trainingSpeedup), maxi(0, building_level - 1)) \
			* ResearchRules.time_factor(village.get("bonuses", {}), "trainTime") / float(Game.world.speed)
		var owned := Game.villages_owned(int(village.ownerAccountId))
		_tick(cost_line, func() -> String:
			var cost := Rules.unit_cost(def, int(_train_counts.get(unit, 1)), owned)
			var current: Dictionary = Game.villages.get(village_id, village)
			var affordable := Ledger.can_afford(Ledger.amounts_at(current.resources, Game.server_now()), cost)
			train.disabled = queue_full or not affordable
			var text := tr("%s · %s each") % [UI.costs(cost), TimeUtil.format_duration(seconds)]
			if queue_full:
				return text + tr("  (queue full)")
			return text if affordable else text + tr("  (not enough)")))


func _stance_picker(village: Dictionary) -> void:
	var stances: Dictionary = Game.data.battle.stances
	var current: String = village.get("stance", "balanced")
	_panel_body.add_child(UI.label(tr("Stance when attacked"), UI.SMALL_SIZE, UI.MUTED))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_panel_body.add_child(grid)
	for stance in stances:
		var button := UI.button(tr(stances[stance].name), func() -> void: _set_stance(int(village.id), stance))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = stance == current
		grid.add_child(button)
	var def: Dictionary = stances[current]
	var breaks := tr("never breaks") if def.retreatAt == null else tr("breaks at %d%% losses") % roundi(float(def.retreatAt) * 100.0)
	_panel_body.add_child(UI.label(tr("%s: attack ×%.2f, defense ×%.2f, %s.") % [tr(def.name), def.attack, def.defense, breaks], UI.SMALL_SIZE, UI.MUTED))


func _set_stance(village_id: int, stance: String) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/stance" % village_id, {"stance": stance})
	if not response.ok:
		_status.text = response.error
		return
	Game.update_village(response.data.village)


func _units_text(units: Dictionary) -> String:
	if units.is_empty():
		return tr("No troops yet.")
	var parts := PackedStringArray()
	for unit in units:
		var def: Dictionary = Game.data.units.units.get(unit, {"name": unit})
		parts.append(tr("%s ×%d") % [tr(def.name), units[unit]])
	return ", ".join(parts)


func _train(village_id: int, unit: String, count: int) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/train" % village_id, {"unit": unit, "count": count})
	if not response.ok:
		_status.text = response.error
		Sound.effect("error")
		return
	Sound.effect("train")
	Game.note_server_time(response.data.serverTime)
	Game.update_village(response.data.village)


# --- Threats -----------------------------------------------------------------

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
	var line := tr("Next horde from the %s (%s threat) sets out in %s") % [String(next.front).to_lower(), tr(String(next.threat)).to_lower(), TimeUtil.format_duration(TimeUtil.parse_iso(next.spawnAt) - now)]
	if next.get("forecast") is Dictionary:
		line += tr(", expected at %s") % _target_name(next.forecast.targetVillageId)
	return line


## A horde's target by its village id; null is the Holy City.
func _target_name(village_id: Variant) -> String:
	return tr("the Holy City") if village_id == null else Game.village_name(village_id)


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


## Whether the sheet is a tall one: lists show more to a page there.
func _roomy() -> bool:
	return _sheet_height() >= 650.0


## The hordes on their way, and what stands between them and the Holy City.
func _hordes_tab() -> void:
	var ritual := RunText.ritual_line(Game.world, Game.server_now())
	if ritual != "":
		_panel_body.add_child(UI.label(ritual, 0, UI.ERROR))
		_panel_body.add_child(UI.label(tr(Game.data.bridge.ritualNight.story), UI.SMALL_SIZE, UI.MUTED))
	_panel_body.add_child(UI.label(tr("The Holy City: %s") % HordeText.sanctity(Game.world, Game.data), UI.SMALL_SIZE, UI.MUTED))
	if Game.waves.is_empty():
		_panel_body.add_child(UI.label(tr("No waves announced."), UI.SMALL_SIZE, UI.MUTED))
	_paged("waves", Game.waves, 2 if _roomy() else 1, _wave_entry)


## How the battles went, newest first.
func _reports_tab() -> void:
	_panel_body.add_child(UI.label(tr("Battle reports"), UI.HEADING_SIZE))
	var finished := Game.battles.filter(func(b: Dictionary) -> bool: return b.status != "ongoing")
	if finished.is_empty():
		_panel_body.add_child(UI.label(tr("No battles fought yet."), UI.SMALL_SIZE, UI.MUTED))
	_paged("reports", finished, 3 if _roomy() else 2, _battle_report)


func _battle_report(battle: Dictionary) -> void:
	var report := HordeText.assault(battle, BattleText.losses(battle)) if battle.get("campId") != null or battle.get("siteId") != null else BattleText.outcome(battle, Game.battle_place(battle))
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


## The world's settings: its peaceful hours; report a bug, or leave it.
func _leave_tab() -> void:
	_quiet_section()
	# A bug report carries the current game state with the player's message.
	_panel_body.add_child(UI.button(tr("Report a bug"), _report_bug, "icon/help"))
	_leave_section()


## Back to the menu (the world goes on), or quit it for good: a co-op world
## passes your villages to the team (the last one out closes it); a solo
## world is deleted. Quitting asks twice.
var _quit_armed := false

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


## Opens a short form; the report is saved as a file and sent to the server.
func _report_bug() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = tr("Report a bug")
	dialog.ok_button_text = tr("Send")
	var box := UI.vbox(12)
	var edit := TextEdit.new()
	edit.custom_minimum_size = Vector2(540, 240)
	edit.placeholder_text = tr("What went wrong?")
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.add_child(edit)
	box.add_child(UI.label(tr("The current game state is attached to the report."), UI.SMALL_SIZE, UI.MUTED))
	dialog.add_child(box)
	dialog.confirmed.connect(func() -> void: _send_report(edit.text))
	add_child(dialog)
	dialog.popup_centered()


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
	_panel_body.add_child(UI.label(tr("Wave %d · %s") % [int(wave.index) + 1, tr(Game.front_faction(wave.front))]))
	var scouted := Game.missions_for(int(wave.id)).any(func(m: Dictionary) -> bool: return m.report != null)
	var known := "" if scouted else tr(" · composition unknown")
	var threat_row := UI.hbox(8)
	var threat_ic := UI.icon(WaveMath.threat_icon(String(wave.threat)), 26)
	threat_ic.self_modulate = WaveMath.threat_color(String(wave.threat))
	threat_row.add_child(threat_ic)
	threat_row.add_child(UI.label(tr("%s front · %s threat%s") % [String(wave.front).capitalize(), tr(wave.threat), known], UI.SMALL_SIZE, WaveMath.threat_color(String(wave.threat))))
	_panel_body.add_child(threat_row)
	var line := UI.label("", UI.SMALL_SIZE, UI.ERROR)
	_panel_body.add_child(line)
	_tick(line, func() -> String:
		var now := Game.server_now()
		match wave.status:
			"scheduled":
				var appears := tr("Appears in %s") % TimeUtil.format_duration(TimeUtil.parse_iso(wave.spawnAt) - now)
				var forecast: Variant = wave.get("forecast")
				if forecast is Dictionary:
					appears += tr(" · expected at %s in %s") % [_target_name(forecast.targetVillageId), TimeUtil.format_duration(TimeUtil.parse_iso(forecast.arrivesAt) - now)]
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
	var at_home := int(Rules.garrison_at(home, Game.server_now()).get("scout", 0))
	var max_scouts := mini(int(Game.data.scouting.maxScouts), maxi(at_home, 1))
	var count := clampi(_scout_counts.get(wave_id, mini(at_home, 3)), 1, max_scouts)
	var row := UI.hbox()
	_panel_body.add_child(row)
	row.add_child(_number_field("scouts:%d" % wave_id, count, 1, max_scouts, func(n: int) -> void: _scout_counts[wave_id] = n))
	var send := UI.button(tr_n("Send scouts (%d home)", "Send scouts (%d home)", at_home) % at_home, func() -> void:
		_send_scouts(village_id, wave_id, clampi(int(_scout_counts.get(wave_id, count)), 1, max_scouts)))
	send.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	send.disabled = at_home < 1
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
	_sound_hordes()
	_rebuild_panel()


# --- Sound -------------------------------------------------------------------

func _my_village_ids() -> Array:
	return Game.my_villages().map(func(v: Dictionary) -> int: return int(v.id))


## The music for what is on screen (SoundCues.track).
func _update_music() -> void:
	var near := SoundCues.threatened(Game.waves, _my_village_ids(), Game.server_now())
	Sound.music(SoundCues.track(_view, String(Game.world.get("status", "")), near))


## A horn for each horde that sets out on one of your villages.
func _sound_hordes() -> void:
	var now_ids := SoundCues.incoming(Game.waves, _my_village_ids())
	if not SoundCues.new_hordes(_known_hordes, now_ids).is_empty():
		Sound.effect("horn")
	_known_hordes = now_ids
	_update_music()


## Keeps a label (or rich label) showing `text`'s result.
func _tick(label: Control, text: Callable) -> void:
	label.text = text.call()
	_ticking.append([label, text])


func _queue_build(village_id: int, plot: String, building: String) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/build" % village_id, {"plot": plot, "building": building})
	if not response.ok:
		_status.text = response.error
		Sound.effect("error")
		return
	Sound.effect("build")
	Game.note_server_time(response.data.serverTime)
	Game.update_village(response.data.village)


# --- Events ------------------------------------------------------------------

func _on_map_tapped(world_position: Vector2) -> void:
	var cell := hex_map.local_to_hex(hex_map.to_local(world_position))
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
	if hex_map.has_hex(cell):
		_select(cell)


func _on_world_changed() -> void:
	_update_music()
	hex_map.refresh()
	_refresh_quest_card()
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
	_live_label.text = tr("● live") if connected else tr("○ offline")
	_live_label.add_theme_color_override("font_color", Color("#8fc4a6") if connected else UiTheme.ON_WOOD_MUTED)
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


# --- Forces ------------------------------------------------------------------

## All your troops: how many of each there are, each village's garrison,
## the armies out (from where, to where, and when) and the hero.
func _forces_panel() -> void:
	var top := UI.hbox()
	var title := UI.label(tr("Your forces"), UI.HEADING_SIZE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(UI.button(tr("Close"), func() -> void:
		_panel_mode = "hex"
		_rebuild_panel()))
	_panel_body.add_child(top)
	var hero := Game.my_hero()
	var tabs := [["totals", "unit/spearman", tr("All troops"), _forces_totals],
		["villages", "icon/village", tr("By village"), _forces_villages],
		["moving", "icon/troops", tr("Armies"), _forces_armies]]
	if not hero.is_empty():
		var face := "hero/%s" % hero.get("kind") if hero.get("kind") != null and Art.has("hero/%s" % hero.get("kind")) else "icon/profile"
		tabs.append(["hero", face, tr("Your hero"), _forces_hero])
	_side_tabs("forces", tabs)


## Your armies out of their villages (not done).
func _my_armies() -> Array:
	return Game.armies.filter(func(army: Dictionary) -> bool:
		return army.status != "done" and army.get("ownerAccountId") != null and int(army.ownerAccountId) == Game.my_account_id())


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
		words.add_child(UI.label(tr("At home: %s") % _units_text(Rules.garrison_at(village, now)), UI.SMALL_SIZE, UI.MUTED))
		var away: Dictionary = village.get("away", {}).duplicate()
		for unit in away.keys():
			if int(away[unit]) <= 0:
				away.erase(unit)
		if not away.is_empty():
			words.add_child(UI.label(tr("Away: %s") % _units_text(away), UI.SMALL_SIZE, UI.MUTED))
		if not village.training.is_empty():
			var training := {}
			for batch in village.training:
				training[batch.unit] = int(training.get(batch.unit, 0)) + int(batch.count) - Rules.finished_by(batch, now)
			words.add_child(UI.label(tr("Training: %s") % _units_text(training), UI.SMALL_SIZE, UI.MUTED))
		row.add_child(words)
		var village_id := int(village.id)
		var go := UI.button(tr("Open"), func() -> void:
			Game.current_village_id = village_id
			_tab = "troops"
			_side["troops"] = "garrison"
			_set_view("village"))
		go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(go)
		_panel_body.add_child(row))


## Your armies: who, from where to where, and when they arrive and are home.
func _forces_armies() -> void:
	var armies := _my_armies()
	if armies.is_empty():
		_panel_body.add_child(UI.label(tr("No armies out. Send them from a village's Troops tab, or from a hex on the map."), UI.SMALL_SIZE, UI.MUTED))
		return
	var defs: Dictionary = Game.data.units.units
	_paged("forces armies", armies, 4 if _roomy() else 2, func(army: Dictionary) -> void:
		var row := UI.hbox(10)
		var words := UI.vbox(2)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.add_child(UI.label(ArmyText.units_text(army.units, defs), UI.SMALL_SIZE))
		var target := ArmyText.target_name(army, Game.village_name)
		words.add_child(UI.label(tr("From %s to %s") % [Game.village_name(army.homeVillageId), target], UI.SMALL_SIZE, UI.MUTED))
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
		_panel_body.add_child(row))


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


# --- Inbox -------------------------------------------------------------------

## Opens the inbox: everything is read once seen.
func _show_inbox() -> void:
	_panel_mode = "inbox"
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
	top.add_child(UI.button(tr("Close"), func() -> void:
		_panel_mode = "hex"
		_rebuild_panel()))
	_panel_body.add_child(top)
	# Push settings are for a group's worlds (a solo world sends none).
	if _prefs.is_empty():
		_inbox_messages()
		return
	_side_tabs("inbox", [["messages", "icon/inbox", tr("Messages"), _inbox_messages],
		["settings", "icon/settings", tr("Settings"), _notification_settings]])


func _inbox_messages() -> void:
	if Game.inbox.is_empty():
		_panel_body.add_child(UI.label(tr("Nothing yet."), UI.SMALL_SIZE, UI.MUTED))
	var now := Game.server_now()
	_paged("inbox", Game.inbox, 8 if _roomy() else 4, func(n: Dictionary) -> void:
		var head := UI.label(("● " if not n.read else "") + String(n.title))
		_panel_body.add_child(head)
		var body := tr("%s · %s") % [InboxText.ago(TimeUtil.parse_iso(n.createdAt), now), n.body] if String(n.body) != "" else InboxText.ago(TimeUtil.parse_iso(n.createdAt), now)
		_panel_body.add_child(UI.label(body, UI.SMALL_SIZE, UI.MUTED)))


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


func _leave() -> void:
	Live.stop()
	get_tree().change_scene_to_file(START_SCENE)


## The village of yours the screens show (see Game.current_village).
func _my_village() -> Dictionary:
	return Game.current_village()


func _building_def(building: String) -> Dictionary:
	return Game.data.buildings.buildings.get(building, {"name": building.capitalize()})
