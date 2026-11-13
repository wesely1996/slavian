extends Node2D
## The in-world screen's frame: its state, the top band and the bottom bar,
## the sheet and the helpers every sheet uses. The screens themselves are in
## the scripts that extend this one, a link each (game_screen_map.gd, …,
## game_screen.gd last); what they define and an earlier link calls is
## declared at the foot of this file.

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
## The handle along the sheet's top, and whether the sheet is folded away.
var _fold_handle: Button
var _sheet_folded := false

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
	# A handle along the sheet's top folds it away, so the map under it can
	# be seen and tapped, and brings it back.
	var sheet := UI.vbox(0)
	_fold_handle = Button.new()
	_fold_handle.flat = true
	_fold_handle.focus_mode = Control.FOCUS_NONE
	_fold_handle.custom_minimum_size = Vector2(0, 44)
	_fold_handle.add_theme_font_size_override("font_size", 26)
	_fold_handle.add_theme_color_override("font_color", UiTheme.MUTED)
	_fold_handle.pressed.connect(func() -> void:
		_sheet_folded = not _sheet_folded
		_fit_sheet()
		_arrange())
	sheet.add_child(_fold_handle)
	sheet.add_child(_scroll)
	_panel.add_child(sheet)
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
	# The words are told how wide they may be: a wrapping label that doesn't
	# know yet breaks after every letter, and the box grows tall and empty.
	label.custom_minimum_size = Vector2(width - 28.0, 0)
	label.size = Vector2(width - 28.0, 0)
	_toast_box.custom_minimum_size = Vector2(width, 0)
	_place_toast()
	# Again once laid out (the first time, the words only then know their lines).
	_place_toast.call_deferred()
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


## The toast just above the bottom bar, as tall as its words (never more
## than a few lines' worth).
func _place_toast() -> void:
	if _toast_box == null:
		return
	var area := get_viewport().get_visible_rect().size
	var width := _toast_box.custom_minimum_size.x
	var label := _toast_box.get_node("Words") as Label
	var lines := maxi(1, label.get_line_count())
	var height := minf(lines * label.get_line_height() + 30.0, 220.0)
	_toast_box.size = Vector2(width, height)
	var nav_height := _nav.size.y if _nav != null else 0.0
	_toast_box.position = Vector2((area.x - width) / 2.0, area.y - nav_height - 24.0 - height)


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
	if _fold_handle != null:
		# Beside the map (landscape) the sheet is not in its way: no handle.
		var beside := area.x > area.y * 1.05
		_fold_handle.visible = not beside and not _picking()
		_fold_handle.text = "▴  " + tr("Show") if _sheet_folded else "▾"
		_fold_handle.tooltip_text = tr("Show the sheet") if _sheet_folded else tr("Fold the sheet away")
		_scroll.visible = beside or _picking() or not _sheet_folded
	if area.x > area.y * 1.05:
		return
	# Picking a hex on the map: the sheet shrinks to a line, so the map has room.
	if _picking():
		# (Room for the join checkbox under the prompt while an army moves.)
		_scroll.custom_minimum_size.y = PICKING_HEIGHT + (60.0 if _army_moving != 0 else 0.0)
		return
	var tall := _panel_mode != "hex" or (_view == "village" and _tab != "village")
	# Bare ground has little to say: a peek, and the map keeps the room.
	var peek := not tall and _view == "map" and Game.village_at(_selected).is_empty() and _road_from == Vector2i.MAX
	_scroll.custom_minimum_size.y = area.y * (0.5 if tall else (0.22 if peek else 0.31))
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


func _select(cell: Vector2i) -> void:
	_selected = cell
	_sheet_folded = false
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


## This player's entry in the world's members ({} if none).
func _me() -> Dictionary:
	for member in Game.world.get("members", []):
		if int(member.accountId) == Game.my_account_id():
			return member
	return {}


## "+12/min", or "+0.3/min" for a small rate (a fresh village at speed 1).
static func _per_minute(rate_per_hour: float) -> String:
	var per_minute := rate_per_hour / 60.0
	if absf(per_minute) >= 10.0 or is_zero_approx(per_minute):
		return UI.signed(per_minute)
	return ("+%.1f" if per_minute >= 0 else "−%.1f") % absf(per_minute)


## The clan shown in the picker before it is picked.
var _clan_preview := ""


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
		# Somewhere new: the sheet comes back up.
		if _sheet_folded:
			_sheet_folded = false
			_fit_sheet()
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


## The steps of a form as a row of chips ("1 Where", "2 What", "3 Confirm"):
## the one you are on is lit, those behind it can be tapped to go back.
func _steps_row(names: Array, at: int, on_pick: Callable) -> void:
	var row := UI.hbox(6)
	for i in names.size():
		var step := i + 1
		var chip := UI.button("%d  %s" % [step, names[i]], func() -> void: on_pick.call(step))
		chip.theme_type_variation = "TabButton"
		chip.add_theme_font_size_override("font_size", UI.SMALL_SIZE)
		chip.custom_minimum_size.y = 56
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.clip_text = true
		# (A TabButton shown disabled is the open one.)
		chip.disabled = step == at
		if step > at:
			chip.modulate = Color(1, 1, 1, 0.45)
			chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(chip)
	_panel_body.add_child(row)


## Sending a caravan, a step at a time: where it goes, what it carries,
## then one card to look over before it leaves.
var _caravan_step := 1

## Your research: what you study now, then every branch of the tree. Shows
## which teammates know each tech, so the group can specialize.
## The picture on each research branch's tab.
const BRANCH_ART := {"economy": "resource/grain", "military": "unit/spearman", "fortification": "building/wall_stone",
	"scouting": "unit/scout", "faith": "building/granary_temple_1"}


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


## What comes before the side tabs on a village's sheet: the town's name
## and the village's tabs.
const VILLAGE_TOP := 170.0

## What the village's Market does: trade one resource for another, and buy
## the hero's spare gear.
var _trade := {"give": "wood", "get": "iron", "amount": 100}

## A bounty being put together: step 1 what you give, step 2 what you want.
var _bounty := {"step": 1, "offer": {"wood": 0, "stone": 0, "grain": 0, "iron": 0}, "want": {"wood": 0, "stone": 0, "grain": 0, "iron": 0}, "items": []}


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


## Tearing a building down gives back part of what it cost; it asks twice.
var _demolish_armed := ""

## Giving up a whole village (from its Elder's Hall); it asks twice.
var _abandon_armed := 0


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


var _sally_armed := 0


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
		# Unwrapped: a wrapping label in a flow container is given no width
		# and stood its letters one under another.
		var none := UI.label(tr("No troops"), UI.SMALL_SIZE, UI.MUTED)
		none.autowrap_mode = TextServer.AUTOWRAP_OFF
		flow.add_child(none)
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


## A horde's target by its village id; null is the Holy City.
func _target_name(village_id: Variant) -> String:
	return tr("the Holy City") if village_id == null else Game.village_name(village_id)


## Whether the sheet is a tall one: lists show more to a page there.
func _roomy() -> bool:
	return _sheet_height() >= 650.0


## Back to the menu (the world goes on), or quit it for good: a co-op world
## passes your villages to the team (the last one out closes it); a solo
## world is deleted. Quitting asks twice.
var _quit_armed := false


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


## Your armies out of their villages (not done).
func _my_armies() -> Array:
	return Game.armies.filter(func(army: Dictionary) -> bool:
		return army.status != "done" and army.get("ownerAccountId") != null and int(army.ownerAccountId) == Game.my_account_id())


## What a notice is about, for the inbox's filter.
const NOTICE_GROUPS := {
	"battles": ["battle_result", "under_attack", "razing", "wave_soon", "outpost_raided", "bandit", "camp", "lair", "leader"],
	"economy": ["build_done", "train", "store", "surplus", "caravan_delivered", "supply", "settlers", "village", "rebuild", "gear"],
}


func _leave() -> void:
	Live.stop()
	get_tree().change_scene_to_file(START_SCENE)


## The village of yours the screens show (see Game.current_village).
func _my_village() -> Dictionary:
	return Game.current_village()


func _building_def(building: String) -> Dictionary:
	return Game.data.buildings.buildings.get(building, {"name": building.capitalize()})


# --- Defined in the links after this one -----------------------------------
#
# What an earlier link calls of a later one is declared here, so that it
# reads as part of the screen; the link named above each defines it.


# game_screen_map.gd

func _picking_panel() -> void:
	pass

func _hex_panel() -> void:
	pass

func _on_map_tapped(world_position: Vector2) -> void:
	pass


# game_screen_village.gd

func _on_plot_tapped(plot: String) -> void:
	pass

func _village_panel() -> void:
	pass

func _build_row(village: Dictionary, plot: String, building: String, target: int, verb: String, note := "", named := true) -> void:
	pass


# game_screen_army.gd

func _join_check() -> CheckBox:
	return null

func _back_to_send(village_id: int) -> void:
	pass

func _unit_pickers(home_units: Dictionary, with_scouts := false, list := "units") -> Dictionary:
	return {}

func _picked_hint(button: Button, home_units: Dictionary) -> void:
	pass

func _picked_units(home_units: Dictionary) -> Dictionary:
	return {}

func _send_army(village_id: int, body: Dictionary) -> void:
	pass

func _general_picker(village_id: int) -> void:
	pass

func _ready_general(village_id: int) -> int:
	return 0

func _generals_section(village: Dictionary) -> void:
	pass

func _open_army(army_id: int) -> void:
	pass

func _army_panel() -> void:
	pass

func _search_ends(army: Dictionary) -> float:
	return 0.0

func _store_row(army: Dictionary) -> void:
	pass

func _army_command(army_id: int, action: String, body: Dictionary) -> void:
	pass

func _recall_army(army_id: int) -> void:
	pass

func _troops_section(village: Dictionary) -> void:
	pass

func _army_stance_picker(village: Dictionary) -> void:
	pass

func _forces_panel() -> void:
	pass


# game_screen_logistics.gd

func _open_caravans(target: Dictionary, village_id := 0) -> void:
	pass

func _caravans_section(village: Dictionary) -> void:
	pass

func _caravan_target_at(cell: Vector2i, from_village_id: int) -> Dictionary:
	return {}

func _orders_panel() -> void:
	pass


# game_screen_hero.gd

func _hero_line(village_id: int) -> void:
	pass

func _hero_panel() -> void:
	pass

func _quest_place_line(quest: Variant) -> void:
	pass


# game_screen_threats.gd

func _battle_button(battle: Dictionary) -> Button:
	return null

func _battle() -> Dictionary:
	return {}

func _battle_panel() -> void:
	pass

func _show_threats() -> void:
	pass

func _open_run_once() -> void:
	pass

func _run_panel() -> void:
	pass

func _threat_summary() -> String:
	return ""

func _threats_panel() -> void:
	pass

func _wave_entry(wave: Dictionary) -> void:
	pass


# game_screen_messages.gd

func _more_panel() -> void:
	pass

func _refresh_quest_card() -> void:
	pass

func _place_quest_card() -> void:
	pass

func _claim_onboarding(step_id: String) -> void:
	pass

func _show_me(target: String) -> void:
	pass

func _go_to(cell: Vector2i) -> void:
	pass

func _welcome_once() -> void:
	pass

func _almanac_panel() -> void:
	pass

func _report_bug() -> void:
	pass

func _report_panel() -> void:
	pass

func _show_messages() -> void:
	pass

func _chat_panel() -> void:
	pass

func _inbox_panel() -> void:
	pass


# game_screen_final.gd

func _on_waves_changed() -> void:
	pass

func _on_world_changed() -> void:
	pass

func _on_village_changed(_village_id: int) -> void:
	pass

func _on_live_connection(connected: bool) -> void:
	pass

func _refetch_world() -> void:
	pass

func _on_inbox_changed() -> void:
	pass

func _on_chat_changed() -> void:
	pass
