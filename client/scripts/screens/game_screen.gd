extends Node2D
## In-world screen: the map from the server, your resources, a threat
## banner, and a panel for the selected hex (or the threats timeline). Your
## own village's panel queues buildings and trains troops.

const START_SCENE := "res://scenes/start.tscn"
const UI_REFRESH_SEC := 0.25
const NEGATIVE := Color("#ff8a7a")

@onready var hex_map: HexMap = $HexMap
@onready var camera: MapCamera = $MapCamera

var _selected := Vector2i.MAX
var _since_refresh := 0.0

var _live_label: Label
var _resource_labels: Dictionary[String, Label] = {}
## Which part of your village panel is open: "buildings" or "troops".
var _tab := "buildings"
## What the bottom panel shows: "hex" (the selected hex) or "threats".
var _panel_mode := "hex"
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
	Game.waves_changed.connect(_on_waves_changed)
	Game.scouting_changed.connect(_on_waves_changed)
	Game.battles_changed.connect(_on_waves_changed)
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
	Live.waves_updated.disconnect(Game.set_waves)
	Live.scouting_updated.disconnect(Game.set_scouting)
	Live.battles_updated.disconnect(Game.set_battles)


func _process(delta: float) -> void:
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
			label.text = "%s %d  %s/h" % [kind.capitalize(), amounts[kind], UI.signed(rate)]
			label.add_theme_color_override("font_color", NEGATIVE if rate < 0 else Color.WHITE)
	_threat_button.text = _threat_summary()
	if hex_map.has_moving_hordes():
		hex_map.queue_redraw()
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
	var resources := GridContainer.new()
	resources.columns = 2
	resources.add_theme_constant_override("h_separation", 24)
	top_rows.add_child(resources)
	for kind in Ledger.KINDS:
		var label := UI.label("", UI.SMALL_SIZE)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		resources.add_child(label)
		_resource_labels[kind] = label
	_threat_button = UI.button("", _show_threats)
	_threat_button.custom_minimum_size.y = 56
	_threat_button.add_theme_font_size_override("font_size", UI.SMALL_SIZE)
	_threat_button.add_theme_color_override("font_color", Color("#ffb4a8"))
	_threat_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_threat_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top_rows.add_child(_threat_button)
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
	_panel_mode = "hex"
	hex_map.select(cell)
	_rebuild_panel()


func _show_threats() -> void:
	_panel_mode = "threats"
	_rebuild_panel()


func _rebuild_panel() -> void:
	UI.clear(_panel_body)
	_ticking.clear()
	if _panel_mode == "threats":
		_threats_panel()
		return
	for wave in WaveMath.visible_waves(Game.waves):
		if WaveMath.current_hex(wave, Game.server_now()) == _selected:
			_wave_entry(wave)
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
	var troops := UI.label("", UI.SMALL_SIZE, UI.MUTED)
	_panel_body.add_child(troops)
	_tick(troops, func() -> String: return _units_text(Rules.garrison_at(village, Game.server_now())))


func _own_village_panel(village: Dictionary) -> void:
	_panel_body.add_child(UI.label(village.name, UI.HEADING_SIZE))
	var tabs := UI.hbox()
	for tab in [["buildings", "Buildings"], ["troops", "Troops"]]:
		var button := UI.button(tab[1], func() -> void:
			_tab = tab[0]
			_rebuild_panel())
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = _tab == tab[0]
		tabs.add_child(button)
	_panel_body.add_child(tabs)
	if _tab == "troops":
		_troops_section(village)
	else:
		_buildings_section(village)


func _buildings_section(village: Dictionary) -> void:
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


func _troops_section(village: Dictionary) -> void:
	var village_id := int(village.id)
	_stance_picker(village)
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

	_panel_body.add_child(UI.label("Train", UI.SMALL_SIZE, UI.MUTED))
	var queue_full := training.size() >= limit
	var max_batch := int(Game.data.units.maxBatch)
	for unit in units:
		var def: Dictionary = units[unit]
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
		var cost := Rules.unit_cost(def, count)
		var cost_line := UI.label("", UI.SMALL_SIZE, UI.MUTED)
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
		var seconds := float(def.trainSeconds) * pow(float(Game.data.units.trainingSpeedup), maxi(0, building_level - 1)) / float(Game.world.speed)
		var cost_text := "%s · %s each" % [UI.resource_text(cost), TimeUtil.format_duration(seconds)]
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
	if Game.waves.is_empty():
		return "No threats known"
	var now := Game.server_now()
	for wave in Game.waves:
		if wave.status == "marching":
			return "Horde marching on %s · %s" % [Game.village_name(wave.targetVillageId), TimeUtil.format_duration(TimeUtil.parse_iso(wave.arrivesAt) - now)]
	for wave in Game.waves:
		if wave.status == "battling":
			var battle := Game.battle_for(int(wave.id))
			return "Battle at %s · round %d" % [Game.village_name(wave.targetVillageId), int(battle.get("round", 0))]
	for wave in Game.waves:
		if wave.status == "arrived":
			return "Horde at %s" % Game.village_name(wave.targetVillageId)
	var next: Dictionary = Game.waves[0]
	return "Next wave: %s · %s · in %s" % [String(next.front).capitalize(), next.threat, TimeUtil.format_duration(TimeUtil.parse_iso(next.spawnAt) - now)]


func _threats_panel() -> void:
	_panel_body.add_child(UI.label("Threats", UI.HEADING_SIZE))
	if Game.waves.is_empty():
		_panel_body.add_child(UI.label("No waves announced.", UI.SMALL_SIZE, UI.MUTED))
	for wave in Game.waves:
		_wave_entry(wave)
	var finished := Game.battles.filter(func(b: Dictionary) -> bool: return b.status != "ongoing")
	if not finished.is_empty():
		_panel_body.add_child(UI.label("Battle reports", UI.HEADING_SIZE))
	for battle in finished:
		_panel_body.add_child(UI.label(BattleText.outcome(battle, Game.village_name(battle.villageId)), UI.SMALL_SIZE))
		_panel_body.add_child(UI.label("%s horde, %d rounds" % [String(battle.attackerStance).replace("_", " ").capitalize(), int(battle.round)], UI.SMALL_SIZE, UI.MUTED))


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
			"battling":
				var battle := Game.battle_for(int(wave.id))
				return "Fighting at %s · round %d of %d · %d of them left" % [Game.village_name(wave.targetVillageId), int(battle.get("round", 0)), int(Game.data.battle.maxRounds), BattleText.total(battle.get("attackerNow", {}))]
		return String(wave.status).capitalize())
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
