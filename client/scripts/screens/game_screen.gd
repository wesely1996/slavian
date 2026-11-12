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
## Whether each resource's rate is shown as a loss (kind -> bool).
var _rate_negative := {}
## A rebuild of the sheet is waiting for the end of the frame.
var _panel_stale := false
## The chat is waiting to be laid out again; and you just sent a message.
var _chat_stale := false
var _chat_sent := false
## The newest message already reported as read.
var _chat_read_sent := 0
var _chat_sending := false
## The status line as last shown in a toast.
var _status_shown := ""
var _toast_box: PanelContainer
var _toast_tween: Tween
## What the sheet showed when last built (a change of place fades it in).
var _sheet_key := ""
## Which notices the inbox lists: "all", "battles", "economy" or "other".
var _inbox_filter := "all"

var _live_label: Label
## The top band of wood, and the words its buttons show at full width (they
## fold to icons when the band would be wider than the screen: _fit_bar).
var _top: PanelContainer
## The bar along the bottom: place -> its button.
var _nav: PanelContainer
var _nav_buttons := {}
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
## Which of the inbox and the chat the shared button opened last.
var _messages_tab := "inbox"
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
## Where it goes: {kind: "vault"}, or {kind: "village" | "fort" |
## "shipyard", id}. Picked on the map (_caravan_picking: the village it
## leaves from, while the map waits for the tap).
var _caravan_target := {"kind": "vault"}
var _caravan_picking := 0
## The sheet that was open when the caravan's target began to be picked:
## opening another drops the picking.
var _caravan_pick_mode := ""
var _caravan_load: Dictionary[String, int] = {"wood": 0, "stone": 0, "grain": 0, "iron": 0}
# What the caravan brings back from your own settlement, fort or supply point.
var _caravan_back: Dictionary[String, int] = {"wood": 0, "stone": 0, "grain": 0, "iron": 0}
## Army form: the hex it marches to (MAX: none picked yet), troops, and
## whether it joins the garrison of your settlement there, or harasses the
## horde at another's.
var _send_target := Vector2i.MAX
var _army_units: Dictionary[String, int] = {}
var _army_join := false
var _army_harass := false
## The village whose new army waits for a hex to march to (0: none).
var _army_sending := 0
## Hold form: whether your hero leads the army.
var _army_hero := false
## Whether the army being sent comes home by itself once its errand is done.
var _army_return := false
## The raid being planned: the front it goes to and how many fields deep.
var _raid_front := ""
var _raid_depth := 1
# The Raid tab: a strike on a gathering horde instead, and which (wave id).
var _strike_mode := false
var _strike_wave := 0
## The general picked to lead the next army sent (0: none).
var _army_general := 0
## The stance picked for the next army sent ("": its village's).
var _army_stance := ""
## Standing order forms: repeat training and the surplus share.
## The standing orders panel: making a new one (its village and kind).
var _order_creating := false
var _order_village := 0
var _order_kind := "train"
var _repeat_unit := "spearman"
## The training building whose troops the Train tab shows.
var _train_building := "barracks"
var _repeat_target := 20
var _repeat_batch := 5
var _surplus_share := 80
## The supply route form: the fort or supply point picked, and how full to keep it.
var _supply_fort := 0
var _supply_target := 1000
## What the bottom panel shows: "hex" (the selected hex) or "threats".
var _panel_mode := "hex"
## The army whose sheet is open, and the one waiting for a hex to march to
## (0: none).
var _army_id := 0
var _army_moving := 0
## The bug report being typed (kept while the sheet is rebuilt).
var _report_text := ""
## The side tab open on each sheet ("threats", "hero", …), and the page each
## paged list is on.
var _side: Dictionary[String, String] = {}
var _pages: Dictionary[String, int] = {}
## The end-of-run panel opens by itself once.
var _run_seen := false
var _threat_button: Button
## Chosen number of scouts to send, per wave id.
## Scouts picked to send, by "wave id:unit".
var _scout_counts: Dictionary[String, int] = {}
var _ruin_scouts: Dictionary[int, int] = {}
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
	Live.generals_updated.connect(Game.set_generals)
	Live.orders_updated.connect(Game.set_orders)
	Live.inbox_updated.connect(Game.set_inbox)
	Live.chat_received.connect(Game.add_chat)
	Live.armies_updated.connect(Game.set_armies)
	Live.forts_updated.connect(Game.set_forts)
	Game.armies_changed.connect(_on_waves_changed)
	Game.forts_changed.connect(_on_waves_changed)
	Game.inbox_changed.connect(_on_inbox_changed)
	Game.chat_changed.connect(_on_chat_changed)
	Game.orders_changed.connect(_on_waves_changed)
	Game.heroes_changed.connect(_on_waves_changed)
	Game.generals_changed.connect(_on_waves_changed)
	Game.research_changed.connect(_on_waves_changed)
	Game.expeditions_changed.connect(_on_waves_changed)
	Game.caravans_changed.connect(_on_waves_changed)
	Game.waves_changed.connect(_on_waves_changed)
	Game.raids_changed.connect(_on_waves_changed)
	Game.scouting_changed.connect(_on_waves_changed)
	Game.battles_changed.connect(_on_waves_changed)
	get_tree().set_quit_on_go_back(false)
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
	Live.generals_updated.disconnect(Game.set_generals)
	Live.orders_updated.disconnect(Game.set_orders)
	Live.inbox_updated.disconnect(Game.set_inbox)
	Live.chat_received.disconnect(Game.add_chat)
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
			label.tooltip_text = tr("%s: %s an hour, credited every minute (next in %s)") % [UI.resource_name(kind), UI.signed(TimeUtil.per_real_hour(rate)), TimeUtil.format_duration(Ledger.seconds_to_next(Game.server_now()))]
			_rate_labels[kind].text = tr("%s/min") % _per_minute(TimeUtil.per_real_hour(rate))
			# (Only when it turns: an override set again lays the label out again.)
			if _rate_negative.get(kind) != (rate < 0):
				_rate_negative[kind] = rate < 0
				_rate_labels[kind].add_theme_color_override("font_color", NEGATIVE if rate < 0 else UI.MUTED)
		_fit_resources()
	_threat_button.text = _threat_summary()
	# Nothing threatening: no line at all.
	_threat_button.visible = not Game.waves.is_empty() or RunText.is_over(Game.world) or Game.world.get("ritualAt") != null
	# What the game has to say (a refusal, a hint) pops up over the bar at
	# the bottom, where the thumb is, and fades.
	_status.visible = false
	if _status.text != _status_shown:
		_status_shown = _status.text
		if _status.text != "":
			_toast(_status.text, true)
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
	_top = top
	root.add_child(top)
	var top_rows := UI.vbox(10)
	top.add_child(top_rows)
	_top_rows = top_rows
	# One row: whose stores (tap: your next village), the four resources,
	# and the messages. Everything else is on the bar at the bottom.
	var bar := UI.hbox(6)
	top_rows.add_child(bar)
	# The resource strip: whose stores they are, then for each resource its
	# icon, stock and limit, the hourly rate, and how full the store is.
	_resources = UI.hbox(4)
	_resources.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_resources)
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
		# Never wider than the screen: in the last resort the rate trims.
		rate.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
		_rate_negative.erase(kind)
	# Shown only while the server can't be reached.
	_live_label = UI.label("", UI.SMALL_SIZE)
	_live_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_live_label.visible = false
	bar.add_child(_live_label)
	# Notices and the group chat share one button: it opens whichever has
	# something new (the chat first), and the sheet switches between them.
	_inbox_button = UI.button("", _show_messages, "icon/inbox")
	_inbox_button.theme_type_variation = "WoodIconButton"
	_inbox_button.tooltip_text = tr("Inbox") if Local.is_active() else tr("Inbox and chat")
	bar.add_child(_inbox_button)
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
	_build_nav()
	# The quest card floats over the map and the village, at their top left.
	_quest_card = QuestCard.new()
	_quest_card.claim.connect(_claim_onboarding)
	_quest_card.show_me.connect(_show_me)
	_quest_card.hide_tutorial.connect(func() -> void:
		Session.set_tutorial_flag(Game.world_id(), "hidden", true)
		_status.text = tr("Tutorial hidden. More → Tutorial brings it back.")
		_refresh_quest_card())
	layer.add_child(_quest_card)
	# The compass in the map's bottom right corner.
	_compass = Compass.new()
	layer.add_child(_compass)
	_main.resized.connect(_place_quest_card)
	get_viewport().size_changed.connect(_arrange)
	_arrange()


## The resource strip never pushes the screen wider than the phone: when
## the stocks and limits don't fit (big stores on a narrow screen), the
## limits are left out (the bar under each still shows how full it is).
func _fit_resources() -> void:
	var parent := _resources.get_parent_control()
	var room := _top_room()
	# In landscape it shares the title row with the buttons.
	if parent is HBoxContainer:
		for other in parent.get_children():
			if other != _resources and other is Control and (other as Control).visible:
				room -= (other as Control).get_combined_minimum_size().x + 8.0
	var need := _stores_button.custom_minimum_size.x
	for kind in Ledger.KINDS:
		need += 4 + 36 + 8 + maxf(_text_width(_resource_labels[kind]) + 2 + _text_width(_capacity_labels[kind]), _text_width(_rate_labels[kind]))
	var show := need <= room - 8.0
	for kind in Ledger.KINDS:
		_capacity_labels[kind].visible = show


## The bar along the bottom: the five places of the game, each a picture
## and a word. The one you are in is lit.
func _build_nav() -> void:
	_nav = UI.wood(6)
	var style := UiTheme.wood_style(6)
	style.content_margin_bottom = 14
	_nav.add_theme_stylebox_override("panel", style)
	var row := UI.hbox(0)
	_nav.add_child(row)
	for place in [["map", tr("Map"), "icon/map"], ["village", tr("Village"), "icon/village"], ["army", tr("Army"), "icon/troops"], ["hero", tr("Hero"), "icon/profile"], ["more", tr("More"), "icon/settings"]]:
		var key := String(place[0])
		var b := UI.button(String(place[1]), _go.bind(key), String(place[2]))
		b.theme_type_variation = "NavButton"
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.expand_icon = true
		b.custom_minimum_size.y = 92
		b.clip_text = true
		row.add_child(b)
		_nav_buttons[key] = b
	_root.add_child(_nav)
	_view_button = _nav_buttons["village"]
	_view_button.visible = not _my_village().is_empty()
	_nav_buttons["hero"].visible = not Game.my_hero().is_empty()


## To one of the bar's places.
func _go(place: String) -> void:
	match place:
		"map":
			_set_view("map")
		"village":
			_tab = "village"
			_set_view("village")
		"army":
			if _view != "map":
				_set_view("map")
			_panel_mode = "forces"
			_rebuild_panel()
		_:
			_panel_mode = place
			_rebuild_panel()


## Which of the bar's places is on screen.
func _place() -> String:
	if _panel_mode in ["forces", "army"]:
		return "army"
	if _panel_mode == "hero":
		return "hero"
	if _panel_mode in ["more", "orders", "almanac", "threats", "report", "run"]:
		return "more"
	if _panel_mode in ["inbox", "chat"]:
		return ""
	return "village" if _view == "village" else "map"


func _light_nav() -> void:
	var here := _place()
	for key in _nav_buttons:
		(_nav_buttons[key] as Button).theme_type_variation = "NavButtonOn" if key == here else "NavButton"
	_nav_buttons["hero"].visible = not Game.my_hero().is_empty()


## A few words over the bottom bar for a few seconds: `warn` for a refusal
## or a hint (with a buzz of the phone), else something done.
func _toast(text: String, warn := false) -> void:
	if _ui_layer == null:
		return
	if _toast_box == null:
		_toast_box = PanelContainer.new()
		_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var words := UI.label("", UI.SMALL_SIZE)
		words.name = "Words"
		words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		words.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_toast_box.add_child(words)
		_ui_layer.add_child(_toast_box)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiTheme.MADDER.darkened(0.35), 0.95) if warn else Color(UiTheme.INK, 0.92)
	style.border_color = Color(UiTheme.ON_WOOD, 0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(14)
	_toast_box.add_theme_stylebox_override("panel", style)
	var label := _toast_box.get_node("Words") as Label
	label.text = text
	label.add_theme_color_override("font_color", UiTheme.ON_WOOD)
	var area := get_viewport().get_visible_rect().size
	var width := minf(area.x - 32.0, 640.0)
	_toast_box.custom_minimum_size = Vector2(width, 0)
	_toast_box.size = Vector2(width, 0)
	var nav_height := _nav.size.y if _nav != null else 0.0
	_toast_box.position = Vector2((area.x - width) / 2.0, area.y - nav_height - 130.0)
	_toast_box.visible = true
	_toast_box.modulate.a = 0.0
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast_box, "modulate:a", 1.0, 0.15)
	_toast_tween.tween_interval(2.2 + text.length() * 0.035)
	_toast_tween.tween_property(_toast_box, "modulate:a", 0.0, 0.4)
	_toast_tween.tween_callback(func() -> void: _toast_box.visible = false)
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(35 if warn else 15)


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


## Back (the phone's button, or Escape): out of a sheet to what is under it,
## out of the village to the map, and from the map to the worlds.
func _back() -> void:
	_order_creating = false
	if _panel_mode != "hex":
		_panel_mode = "hex"
		_rebuild_panel()
	elif _view != "map":
		_set_view("map")
	else:
		_leave()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()


## The room across the top band: the screen's width less the band's margins
## (never the band's own width, which a too-wide row has already stretched).
func _top_room() -> float:
	var room := get_viewport().get_visible_rect().size.x
	if _top != null:
		room -= _top.get_theme_stylebox("panel").get_minimum_size().x
	return room


func _fit_bar() -> void:
	_fit_resources()


func _row_need(row: HBoxContainer) -> float:
	var need := 0.0
	var shown := 0
	for c in row.get_children():
		if c is Control and (c as Control).visible:
			need += (c as Control).get_combined_minimum_size().x
			shown += 1
	return need + row.get_theme_constant("separation") * maxi(0, shown - 1)


func _text_width(label: Label) -> float:
	return label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x


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
	_fit_resources.call_deferred()
	_fit_bar.call_deferred()


func _move_panel(landscape: bool, area: Vector2) -> void:
	if _panel.get_parent() != null:
		_panel.get_parent().remove_child(_panel)
	if landscape:
		_body.add_child(_panel)
		_panel.custom_minimum_size = Vector2(clampf(area.x * 0.34, 620.0, 900.0), 0)
		_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_scroll.custom_minimum_size.y = 0
	else:
		_root.add_child(_panel)
		if _nav != null:
			_root.move_child(_nav, -1)
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
	# Picking a hex on the map: the sheet shrinks to a line, so the map has room.
	if _picking():
		# (Room for the join checkbox under the prompt while an army moves.)
		_scroll.custom_minimum_size.y = PICKING_HEIGHT + (60.0 if _army_moving != 0 else 0.0)
		return
	var tall := _panel_mode != "hex" or (_view == "village" and _tab != "village")
	_scroll.custom_minimum_size.y = area.y * (0.58 if tall else 0.36)
	# The tutorial's card folds while a tall sheet leaves the map little room.
	if tall != _sheet_tall:
		_sheet_tall = tall
		_quest_card.set_open(not tall)
		_refresh_quest_card()


var _sheet_tall := false
## The sheet's height while a hex is being picked on the map.
const PICKING_HEIGHT := 96.0


## Whether the map waits for a tap: where an army marches or a caravan goes.
func _picking() -> bool:
	return _army_moving != 0 or _army_sending != 0 or _caravan_picking != 0


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
	# Leaving the map stops waiting for a caravan's destination.
	if view != "map" and _caravan_picking != 0:
		_caravan_picking = 0
		_status.text = ""
	_renaming = false
	var on_map := view == "map"
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


func _rebuild_panel() -> void:
	_panel_stale = false
	var focus := get_viewport().gui_get_focus_owner()
	# Only a field still being typed in gets its focus back (not one sent).
	var typing := focus is LineEdit and (focus as LineEdit).is_editing() and _panel_body.is_ancestor_of(focus)
	_focused_draft = String(focus.get_meta("draft", "")) if typing else ""
	_clearing = true
	UI.clear(_panel_body)
	_clearing = false
	_ticking.clear()
	# A road being laid is dropped once the sheet shows something else.
	if _road_from != Vector2i.MAX and _panel_mode != "hex":
		_road_from = Vector2i.MAX
		hex_map.show_road_targets([])
		_status.text = ""
	# Likewise an army waiting to be told where to march.
	if _panel_mode != "army":
		if _army_moving != 0:
			_army_moving = 0
			_status.text = ""
		hex_map.select_army(0)
	if _caravan_picking != 0 and _panel_mode != _caravan_pick_mode:
		_caravan_picking = 0
		_status.text = ""
	_fit_sheet()
	_light_nav()
	var key := "%s/%s/%s/%s" % [_panel_mode, _view, _tab, _army_id if _panel_mode == "army" else 0]
	if key != _sheet_key:
		_sheet_key = key
		_panel_body.modulate.a = 0.0
		create_tween().tween_property(_panel_body, "modulate:a", 1.0, 0.16)
	if _picking():
		_picking_panel()
		return
	if _panel_mode == "army":
		_army_panel()
		return
	if _panel_mode == "report":
		_report_panel()
		return
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
	if _panel_mode == "chat":
		_chat_panel()
		return
	if _panel_mode == "orders":
		_orders_panel()
		return
	if _panel_mode == "forces":
		_forces_panel()
		return
	if _panel_mode == "more":
		_more_panel()
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


## Opens your village's caravan tab, headed for `target` (see
## _caravan_target); from `village_id` when given.
func _open_caravans(target: Dictionary, village_id := 0) -> void:
	_caravan_target = target
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
	var where := UI.hbox(8)
	var to := UI.label(tr("To %s") % CaravanText.target_name(_caravan_target), UI.SMALL_SIZE + 2)
	to.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	to.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	where.add_child(to)
	where.add_child(UI.button(tr("Pick on the map"), func() -> void: _pick_caravan_target(village_id), "icon/map"))
	_panel_body.add_child(where)

	# How much of each: typed in, up to what the village holds and what the
	# place takes (a store only grain, a boat what it still needs).
	var limits := _caravan_limits(_caravan_target)
	var amounts := Ledger.amounts_at(village.resources, Game.server_now())
	for kind in Ledger.KINDS:
		if not limits.has(kind):
			_caravan_load[kind] = 0
			continue
		var row := UI.hbox(8)
		row.add_child(UI.icon("resource/%s" % kind, 40))
		var name := UI.label(UI.resource_name(kind), UI.SMALL_SIZE)
		name.custom_minimum_size.x = 90
		row.add_child(name)
		var most := int(floor(float(amounts.get(kind, 0))))
		if limits[kind] != null:
			most = mini(most, int(limits[kind]))
		row.add_child(_number_field("load:%s" % kind, mini(_caravan_load[kind], most), 0, maxi(most, _caravan_load[kind]), func(n: int) -> void:
			_caravan_load[kind] = n))
		var of := UI.label(tr("of %d") % most, UI.SMALL_SIZE, UI.MUTED)
		of.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(of)
		_panel_body.add_child(row)
	if limits.has("grain") and limits.size() == 1:
		_panel_body.add_child(UI.label(tr("A store takes only grain."), UI.SMALL_SIZE, UI.MUTED))
	# From your own settlement, fort or supply point it can bring back.
	var own_place := _caravan_own_place(_caravan_target)
	for kind in Ledger.KINDS:
		if own_place.is_empty() or not limits.has(kind):
			_caravan_back[kind] = 0
	if not own_place.is_empty():
		_panel_body.add_child(UI.with_info(UI.label(tr("Bring back"), UI.HEADING_SIZE),
			tr("On the way home it takes these from %s, as much as there is when it gets there.") % CaravanText.target_name(_caravan_target)))
		for kind in Ledger.KINDS:
			if not limits.has(kind):
				continue
			var row := UI.hbox(8)
			row.add_child(UI.icon("resource/%s" % kind, 40))
			var label := UI.label(UI.resource_name(kind), UI.SMALL_SIZE)
			label.custom_minimum_size.x = 90
			row.add_child(label)
			var there := floori(float(own_place.get(kind, 0)))
			var top := maxi(there, _caravan_back[kind])
			row.add_child(_number_field("back:%s" % kind, _caravan_back[kind], 0, maxi(top, 1000000), func(n: int) -> void: _caravan_back[kind] = n))
			var have := UI.label(tr("%d there") % there, UI.SMALL_SIZE, UI.MUTED)
			have.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(have)
			_panel_body.add_child(row)

	var garrison := Rules.garrison_at(village, Game.server_now())
	var escort := func() -> Dictionary: return _picked_units(garrison) if not Game.camps.is_empty() else {}
	var summary := UI.label("", UI.SMALL_SIZE, UI.MUTED)
	_panel_body.add_child(summary)
	var buttons := UI.hbox()
	var target := _caravan_target.duplicate()
	var send := UI.button(tr("Send"), func() -> void: _send_caravan(village_id, target, _caravan_load.duplicate(), escort.call(), _caravan_back.duplicate()))
	send.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(send)
	var fetch: Button = null
	if _caravan_target.kind == "vault":
		fetch = UI.button(tr("Fetch from vault"), func() -> void: _fetch_from_vault(village_id, _caravan_load.duplicate(), escort.call()))
		fetch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.add_child(fetch)
	# What it takes, and whether it can go, as the numbers are typed.
	_tick(summary, func() -> String:
		var needed := maxi(CaravanMath.needed(Game.data, _caravan_load, village.get("bonuses", {})), CaravanMath.needed(Game.data, _caravan_back, village.get("bonuses", {})))
		var current: Dictionary = Game.villages.get(village_id, village)
		var affordable := Ledger.can_afford(Ledger.amounts_at(current.resources, Game.server_now()), _caravan_load)
		send.disabled = needed == 0 or needed > free or not affordable
		if fetch != null:
			fetch.disabled = CaravanMath.needed(Game.data, _caravan_load, village.get("bonuses", {})) == 0 or needed > free
		var line := tr_n("Needs %d caravan", "Needs %d caravans", needed) % needed if needed > 0 else tr("Type how much of each to carry")
		if needed > free:
			line += tr(" (only %d at home)") % free
		var guard: Dictionary = escort.call()
		if not guard.is_empty():
			line += " · " + tr("Escort: %s") % _units_text(guard)
		return line)
	_panel_body.add_child(buttons)


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
	_caravan_load = {"wood": 0, "stone": 0, "grain": 0, "iron": 0}
	_caravan_back = {"wood": 0, "stone": 0, "grain": 0, "iron": 0}
	_army_units.clear()
	_forget_drafts(["load:", "escort:", "back:"])
	Game.note_server_time(response.data.serverTime)
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


# --- Generals -------------------------------------------------------------------

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


# --- An army's own sheet ----------------------------------------------------------

func _open_army(army_id: int) -> void:
	_army_id = army_id
	_army_moving = 0
	_panel_mode = "army"
	hex_map.select_army(army_id)
	_rebuild_panel()


func _find_army(army_id: int) -> Dictionary:
	for army in Game.armies:
		if int(army.id) == army_id:
			return army
	return {}


## A thin gauge (0..1), gold for grain or red for fatigue.
func _gauge(color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	bar.max_value = 1.0
	bar.step = 0.0
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


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


## The "come home when done" checkbox, with what it means for these orders.
func _return_check(on: bool, explain: String, changed: Callable) -> Control:
	var box := CheckBox.new()
	box.text = tr("Come home when done")
	box.button_pressed = on
	box.add_theme_font_size_override("font_size", UI.SMALL_SIZE)
	box.toggled.connect(func(pressed: bool) -> void: changed.call(pressed))
	return UI.with_info(box, explain)


## What an army's scouts add to its attack and defense (sim/scouting.ts intelBonus).
func _intel_bonus(units: Dictionary) -> float:
	var intel := 0.0
	for unit in units:
		var def: Dictionary = Game.data.units.units.get(unit, {})
		if def.get("family") == "scout" and int(units[unit]) > 0:
			intel += int(units[unit]) * float(def.get("scouting", {}).get("intel", 1))
	return minf(float(Game.data.scouting.intel.max), float(Game.data.scouting.intel.perPoint) * intel)


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


# --- Standing orders ----------------------------------------------------------

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

## A number field between two words on one line ("Keep [20] ready"): the
## words never wrap, the first in a column of its own width.
func _number_row(before: String, field: Control, after: String) -> HBoxContainer:
	var row := UI.hbox(8)
	var head := UI.label(before, UI.SMALL_SIZE)
	head.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.custom_minimum_size.x = 64
	row.add_child(head)
	row.add_child(field)
	var tail := UI.label(after, UI.SMALL_SIZE)
	tail.autowrap_mode = TextServer.AUTOWRAP_OFF
	tail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(tail)
	for child in row.get_children():
		child.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return row


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
	_panel_body.add_child(_champion_line("hero", int(hero.level)))
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
		# Called off: it turns for home where it is, and brings nothing back.
		if quest.get("cancelled", false) == true:
			_panel_body.add_child(UI.label(tr("Called off: coming home empty-handed."), UI.SMALL_SIZE, UI.MUTED))
		else:
			_panel_body.add_child(UI.with_info(UI.button(tr("Call off the quest"), func() -> void: _hero_action("quest/cancel", {})),
				tr("The hero turns for home where it is (as far back as it went, or from the place itself) and brings nothing back. Once on the way home, it can't be called off.")))
		return
	# The army quest it leads its army on: where, and how long it stands.
	if hero.get("armyQuest") is Dictionary:
		var on: Dictionary = hero.armyQuest
		_panel_body.add_child(UI.label(tr(HeroText.quest_def(Game.data, on).get("name", "")), 0, UI.ACCENT))
		_panel_body.add_child(UI.label(HeroText.quest_description(Game.data, on), UI.SMALL_SIZE, UI.MUTED))
		var left := UI.label("", UI.SMALL_SIZE)
		_panel_body.add_child(left)
		if on.get("endsAt") != null:
			_tick(left, func() -> String: return tr("At (%d, %d), gone in %s") % [int(on.q), int(on.r), TimeUtil.format_duration(TimeUtil.parse_iso(String(on.endsAt)) - Game.server_now())])
		var cell := Vector2i(int(on.q), int(on.r))
		_panel_body.add_child(UI.button(tr("Show on the map"), func() -> void: _go_to(cell), "icon/map"))
		return
	var offers: Array = hero.get("offers", [])
	if offers.is_empty():
		var why := tr("No quests while the hero is away or wounded.")
		if hero.status == "with_army":
			why = tr("Army quests come while the army the hero leads stands still.")
		_panel_body.add_child(UI.label(why, UI.SMALL_SIZE, UI.MUTED))
		return
	if hero.status == "with_army":
		_panel_body.add_child(UI.with_info(UI.label(tr("Army quests"), UI.SMALL_SIZE, UI.MUTED), tr("Leading an army, the hero can take it on harder quests: their place rises near the army, which marches on it at once. Clear it in time for XP and the spoils.")))
	_paged("quests", offers, 3 if _roomy() else 1, func(offer: Dictionary) -> void:
		var army: bool = offer.get("army", false)
		var row := UI.hbox()
		var info := UI.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UI.label(tr(HeroText.quest_def(Game.data, offer).get("name", ""))))
		info.add_child(UI.label(HeroText.quest_description(Game.data, offer, _site_name(offer.get("siteId"))), UI.SMALL_SIZE, UI.MUTED))
		info.add_child(UI.label(HeroText.quest_terms(offer, float(Game.world.get("speed", 1))), UI.SMALL_SIZE))
		row.add_child(info)
		var go := UI.primary(tr("Lead the army") if army else tr("Set out"), func() -> void: _hero_action("quest", {"offer": String(offer.id)}))
		go.disabled = hero.status != ("with_army" if army else "home")
		go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(go)
		var card := UI.card(10)
		card.add_child(row)
		_panel_body.add_child(card))


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


## A bounty being put together: step 1 what you give, step 2 what you want.
var _bounty := {"step": 1, "offer": {"wood": 0, "stone": 0, "grain": 0, "iron": 0}, "want": {"wood": 0, "stone": 0, "grain": 0, "iron": 0}, "items": []}


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
	var step := int(_bounty.step)
	var side: String = "offer" if step == 1 else "want"
	_panel_body.add_child(UI.label(tr("Post a bounty · 1 of 2: what you give") if step == 1 else tr("Post a bounty · 2 of 2: what you want"), UI.SMALL_SIZE + 2))
	for kind in Ledger.KINDS:
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
	if step == 2:
		buttons.add_child(UI.button(tr("Back"), func() -> void:
			_bounty.step = 1
			_rebuild_panel()))
	var go := UI.primary(tr("Next") if step == 1 else tr("Post bounty"), func() -> void:
		if step == 1:
			_bounty.step = 2
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
		if step == 2:
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


func _gear_names(items: Array) -> String:
	return ", ".join(items.map(func(item: String) -> String: return tr(String(Game.data.heroes.items.get(item, {}).get("name", item)))))


func _sum(amounts: Dictionary) -> int:
	var n := 0
	for kind in amounts:
		n += int(amounts[kind])
	return n


## Only the resources there are some of (for a short cost line).
func _nonzero(amounts: Dictionary) -> Dictionary:
	var out := {}
	for kind in amounts:
		if int(amounts[kind]) > 0:
			out[kind] = int(amounts[kind])
	return out


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


## Whether a horde fights at a village or marches on it (cmd_armies.gd
## horde_against).
func _horde_against(village_id: int) -> bool:
	for b in Game.battles:
		if b.get("status") == "ongoing" and b.get("villageId") != null and int(b.villageId) == village_id:
			return true
	for w in Game.waves:
		if w.get("status") in ["marching", "battling"] and w.get("targetVillageId") != null and int(w.targetVillageId) == village_id:
			return true
	return false


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
			Game.villages_owned(int(village.ownerAccountId)), ResearchRules.time_factor(village.get("bonuses", {}), "trainTime"), Game.bought(int(village.ownerAccountId), unit))


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


var _sally_armed := 0


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


## Troops as pictures with their numbers (a name where there is no picture).
func _unit_chips(units: Dictionary, size := 40.0) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 16)
	flow.add_theme_constant_override("v_separation", 6)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for unit in units:
		if int(units[unit]) <= 0:
			continue
		var name: String = tr(Game.data.units.units.get(unit, {"name": unit}).name)
		var chip := UI.hbox(4)
		chip.tooltip_text = name
		if Art.has("unit/%s" % unit):
			chip.add_child(UI.icon("unit/%s" % unit, size))
			var count := UI.label(str(int(units[unit])), UI.SMALL_SIZE)
			count.autowrap_mode = TextServer.AUTOWRAP_OFF
			chip.add_child(count)
		else:
			var words := UI.label(tr("%s ×%d") % [name, int(units[unit])], UI.SMALL_SIZE)
			words.autowrap_mode = TextServer.AUTOWRAP_OFF
			chip.add_child(words)
		flow.add_child(chip)
	if flow.get_child_count() == 0:
		flow.add_child(UI.label(tr("No troops"), UI.SMALL_SIZE, UI.MUTED))
	return flow


## _unit_chips kept up to date: `units_now` is asked on every tick, and the
## chips are laid out again when the answer changes (training finishing).
func _live_unit_chips(units_now: Callable, size := 40.0) -> Control:
	var box := UI.vbox(0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var watch := Label.new()
	watch.visible = false
	box.add_child(watch)
	var shown := [-1]
	_tick(watch, func() -> String:
		var units: Dictionary = units_now.call()
		if units.hash() != shown[0]:
			shown[0] = units.hash()
			for child in box.get_children():
				if child != watch:
					child.queue_free()
			box.add_child(_unit_chips(units, size))
		return "")
	return box


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
	_toast(tr("Training %d × %s") % [count, tr(Game.data.units.units.get(unit, {"name": unit}).name)])
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
	var line := tr("Horde from the %s (%s) · sets out in %s") % [String(next.front).to_lower(), tr(String(next.threat)).to_lower(), TimeUtil.format_duration(TimeUtil.parse_iso(next.spawnAt) - now)]
	if next.get("forecast") is Dictionary:
		line += tr(" → %s") % _target_name(next.forecast.targetVillageId)
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


func _set_quiet(start: Variant, end: Variant) -> void:
	_status.text = ""
	var offset := int(Time.get_time_zone_from_system().get("bias", 0))
	var response := await Api.request(HTTPClient.METHOD_PUT, "/v1/worlds/%d/quiet" % Game.world_id(), {"start": start, "end": end, "utcOffsetMinutes": offset})
	if not response.ok:
		_status.text = response.error
		return
	Game.set_world(response.data)


## A bridge quest's ruin or lair: its name and what the quest asks.
func _quest_place_line(quest: Variant) -> void:
	# A hero's army quest ("hero:<account>:<kind>"): whose, and what.
	if quest is String and String(quest).begins_with("hero:"):
		var parts := String(quest).split(":")
		var def: Dictionary = Game.data.get("quests", {}).get("army", {}).get("kinds", {}).get(parts[2] if parts.size() > 2 else "", {})
		if not def.is_empty():
			var whose := ""
			for h in Game.heroes:
				if str(h.accountId) == parts[1]:
					whose = String(h.name)
			_panel_body.add_child(UI.with_info(UI.label(tr(String(def.name)), UI.HEADING_SIZE, UiTheme.GOLD),
				(tr("%s's quest with the army.") % whose + " " if whose != "" else "") + tr(String(def.description))))
		return
	if quest == null or not Game.data.bridge.questPlaces.has(String(quest)):
		return
	var place: Dictionary = Game.data.bridge.questPlaces[String(quest)]
	var asks: Dictionary = Game.data.bridge.quests.get(String(quest), {})
	_panel_body.add_child(UI.with_info(UI.label(tr(String(place.name)), UI.HEADING_SIZE, UiTheme.GOLD), tr(String(asks.get("description", "")))))


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


func _on_waves_changed() -> void:
	hex_map.queue_redraw()
	_sound_hordes()
	_rebuild_panel_soon()


## News from the server often comes several at once (a battle's end changes
## armies, villages, hordes and more): the sheet is rebuilt once for all of
## it, at the end of the frame.
func _rebuild_panel_soon() -> void:
	if _panel_stale:
		return
	_panel_stale = true
	_rebuild_stale_panel.call_deferred()


func _rebuild_stale_panel() -> void:
	if not _panel_stale:
		return
	# The chat shows nothing of the world: news of it must not rebuild the
	# sheet under whoever is typing (the keyboard blinks, the list jumps).
	if _panel_mode == "chat":
		_panel_stale = false
		return
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
	_toast(tr("%s queued") % tr(_building_def(building).name) if building != "" else tr("Queued"))
	Game.note_server_time(response.data.serverTime)
	Game.update_village(response.data.village)


# --- Events ------------------------------------------------------------------

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


func _on_world_changed() -> void:
	_update_music()
	hex_map.refresh()
	_refresh_quest_card()
	_open_run_once()
	_view_button.visible = not _my_village().is_empty()
	if _view == "village" and _my_village().is_empty():
		_set_view("map")
		return
	_rebuild_panel_soon()


func _on_village_changed(_village_id: int) -> void:
	hex_map.queue_redraw()
	_rebuild_panel_soon()


func _on_live_connection(connected: bool) -> void:
	_live_label.text = tr("○ offline")
	_live_label.add_theme_color_override("font_color", Color("#e58a7d"))
	_live_label.visible = not connected and not Local.is_active()
	_fit_bar()
	if connected:
		_refetch_world()


func _refetch_world() -> void:
	var response := await Api.get_json("/v1/worlds/%d" % Game.world_id())
	if response.ok:
		Game.set_world(response.data)
	_refetch_inbox()
	_refetch_chat()


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


func _on_inbox_changed() -> void:
	_update_messages_badge()
	_fit_bar()
	if _panel_mode == "inbox":
		_rebuild_panel()
	_pop_events()


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


# --- Forces ------------------------------------------------------------------

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


# --- Chat --------------------------------------------------------------------

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


func _on_chat_changed() -> void:
	_update_messages_badge()
	# The inbox's switch counts new chat messages.
	if _panel_mode == "inbox":
		_rebuild_panel()
	if _panel_mode != "chat":
		return
	# Several changes in a frame (a message, then its read mark) lay the
	# chat out once.
	if _chat_stale:
		return
	_chat_stale = true
	var bar := _scroll.get_v_scroll_bar()
	var from_end := int(bar.max_value - _scroll.size.y) - _scroll.scroll_vertical
	var at_bottom := from_end <= 8 or _chat_sent
	_chat_sent = false
	await get_tree().process_frame
	_chat_stale = false
	if _panel_mode != "chat":
		return
	_rebuild_panel()
	_read_chat()
	# Laid out over the next frame: then back to where the reader was (from
	# the end, so older messages loaded above don't push the page), or to
	# the newest.
	await get_tree().process_frame
	await get_tree().process_frame
	if _panel_mode != "chat":
		return
	var end := int(bar.max_value - _scroll.size.y)
	_scroll.scroll_vertical = end if at_bottom else maxi(0, end - from_end)


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


# --- Inbox -------------------------------------------------------------------

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


## What a notice is about, for the inbox's filter.
const NOTICE_GROUPS := {
	"battles": ["battle_result", "under_attack", "razing", "wave_soon", "outpost_raided", "bandit", "camp", "lair", "leader"],
	"economy": ["build_done", "train", "store", "surplus", "caravan_delivered", "supply", "settlers", "village", "rebuild", "gear"],
}


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


func _leave() -> void:
	Live.stop()
	get_tree().change_scene_to_file(START_SCENE)


## The village of yours the screens show (see Game.current_village).
func _my_village() -> Dictionary:
	return Game.current_village()


func _building_def(building: String) -> Dictionary:
	return Game.data.buildings.buildings.get(building, {"name": building.capitalize()})
