extends Node2D
## In-world screen: the map from the server, your resources, and a panel
## for the selected hex. Your own village's panel queues buildings.

const START_SCENE := "res://scenes/start.tscn"
const UI_REFRESH_SEC := 0.25

@onready var hex_map: HexMap = $HexMap
@onready var camera: MapCamera = $MapCamera

var _selected := Vector2i.MAX
var _since_refresh := 0.0

var _live_label: Label
var _resources_label: Label
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
	Live.watch(Game.world_id())

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


func _process(delta: float) -> void:
	_since_refresh += delta
	if _since_refresh < UI_REFRESH_SEC:
		return
	_since_refresh = 0.0
	var home := _my_village()
	if not home.is_empty():
		_resources_label.text = UI.resource_text(Ledger.amounts_at(home.resources, Game.server_now()))
	for entry in _ticking:
		(entry[0] as Label).text = (entry[1] as Callable).call()


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

	var top := UI.panel(Color(0.13, 0.11, 0.09, 0.85), 12)
	column.add_child(top)
	var top_rows := UI.vbox(6)
	top.add_child(top_rows)
	var bar := UI.hbox()
	top_rows.add_child(bar)
	bar.add_child(UI.button("‹ Worlds", _leave))
	var title := UI.label(Game.world.get("name", ""), UI.HEADING_SIZE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bar.add_child(title)
	_live_label = UI.label("", UI.SMALL_SIZE)
	_live_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	bar.add_child(_live_label)
	_resources_label = UI.label("", UI.SMALL_SIZE)
	top_rows.add_child(_resources_label)
	_status = UI.label("", UI.SMALL_SIZE, UI.ERROR)
	top_rows.add_child(_status)
	_on_live_connection(Live.connected)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	_panel = UI.panel()
	column.add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 420
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	_panel_body = UI.vbox(12)
	_panel_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_panel_body)


# --- Selection panel ---------------------------------------------------------

func _select(cell: Vector2i) -> void:
	_selected = cell
	hex_map.select(cell)
	_rebuild_panel()


func _rebuild_panel() -> void:
	UI.clear(_panel_body)
	_ticking.clear()
	var village := Game.village_at(_selected)
	if village.is_empty():
		_terrain_panel()
	elif Game.is_mine(village):
		_own_village_panel(village)
	else:
		_ally_village_panel(village)


func _terrain_panel() -> void:
	var id: String = Game.terrain.get(_selected, "")
	_panel_body.add_child(UI.label(Terrain.display_name(id, Game.data), UI.HEADING_SIZE))
	var distance := HexMath.distance(_selected, Vector2i.ZERO)
	var where := "The Holy City." if distance == 0 else "%d hexes from the Holy City." % distance
	_panel_body.add_child(UI.label(where, UI.SMALL_SIZE, UI.MUTED))


func _ally_village_panel(village: Dictionary) -> void:
	_panel_body.add_child(UI.label(village.name, UI.HEADING_SIZE))
	_panel_body.add_child(UI.label("Ally: %s" % Game.member_name(int(village.ownerAccountId)), UI.SMALL_SIZE, UI.MUTED))
	for building in village.levels:
		_panel_body.add_child(UI.label("%s  Lv %d" % [_building_def(building).name, village.levels[building]]))


func _own_village_panel(village: Dictionary) -> void:
	_panel_body.add_child(UI.label(village.name, UI.HEADING_SIZE))
	var village_id := int(village.id)

	var queue: Array = village.queue
	var limit := int(Game.data.buildings.village.queueLimit)
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

	_panel_body.add_child(UI.label("Buildings", UI.SMALL_SIZE, UI.MUTED))
	var speed := float(Game.world.speed)
	var buildings: Dictionary = Game.data.buildings.buildings
	for building in buildings:
		var def: Dictionary = buildings[building]
		var level := int(village.levels.get(building, 0))
		var target := Rules.planned_level(village, building) + 1
		var row := UI.hbox()
		var info := UI.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UI.label("%s  Lv %d" % [def.name, level]))
		if target > int(def.maxLevel):
			info.add_child(UI.label("Max level", UI.SMALL_SIZE, UI.MUTED))
			row.add_child(info)
			_panel_body.add_child(row)
			continue
		var cost := Rules.level_cost(def, target)
		var cost_line := UI.label("", UI.SMALL_SIZE, UI.MUTED)
		info.add_child(cost_line)
		row.add_child(info)
		var build := UI.button("Build", func() -> void: _queue_build(village_id, building))
		build.custom_minimum_size.x = 140
		row.add_child(build)
		_panel_body.add_child(row)
		var duration := TimeUtil.format_duration(Rules.build_seconds(def, target, speed))
		var cost_text := "→ Lv %d · %s · %s" % [target, UI.resource_text(cost), duration]
		var queue_full := queue.size() >= limit
		_tick(cost_line, func() -> String:
			var home: Dictionary = Game.villages.get(village_id, {})
			var affordable := Ledger.can_afford(Ledger.amounts_at(home.resources, Game.server_now()), cost)
			build.disabled = queue_full or not affordable
			return cost_text + ("  (queue full)" if queue_full else ""))


func _tick(label: Label, text: Callable) -> void:
	label.text = text.call()
	_ticking.append([label, text])


func _queue_build(village_id: int, building: String) -> void:
	_status.text = ""
	var response := await Api.post_json("/v1/villages/%d/build" % village_id, {"building": building})
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


func _leave() -> void:
	Live.stop()
	get_tree().change_scene_to_file(START_SCENE)


func _my_village() -> Dictionary:
	for village in Game.villages.values():
		if Game.is_mine(village):
			return village
	return {}


func _building_def(building: String) -> Dictionary:
	return Game.data.buildings.buildings.get(building, {"name": building.capitalize()})
