extends SceneTree
## Headless test runner:
##   godot --headless --path client --import
##   godot --headless --path client --script res://tests/test_runner.gd

const VECTORS_PATH := "../data/fixtures/hex-vectors.json"
const RESOURCE_VECTORS_PATH := "../data/fixtures/resource-vectors.json"
const BUILDINGS_PATH := "../data/buildings.json"

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_test_hex_vectors()
	_test_hex_round_trip()
	_test_resource_vectors()
	_test_local_mapgen()
	_test_local_start()
	_test_local_villages()
	_test_local_waves()
	_test_local_notices()
	_test_local_saves()
	_test_sound_cues()
	_test_george_bar()
	_test_time_util()
	_test_rules()
	_test_village_layout()
	_test_training()
	_test_wave_math()
	_test_scout_text()
	_test_battle_text()
	_test_caravans()
	_test_expansion()
	_test_research()
	_test_heroes()
	_test_orders()
	_test_inbox()
	_test_armies()
	_test_field()
	_test_fronts()
	_test_horde()
	_test_group()
	_test_sites()
	_test_bridge()
	_test_run()
	_test_clans()
	_test_delegation()
	_test_onboarding_almanac()
	_test_art()
	_test_battle_story()
	_test_leaders()
	_test_translation()
	_test_walls()
	_test_rivers()
	_test_everything_loads("res://scripts")
	_test_everything_loads("res://scenes")
	print("%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: ", message)


func _v(pair: Array) -> Vector2i:
	return Vector2i(int(pair[0]), int(pair[1]))


func _test_hex_vectors() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join(VECTORS_PATH)
	var vectors: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(vectors != null, "hex vectors load from %s" % path)

	for i in HexMath.DIRECTIONS.size():
		_check(HexMath.DIRECTIONS[i] == _v(vectors.directions[i]), "direction %d" % i)
	for case in vectors.distance:
		var d := HexMath.distance(_v(case[0]), _v(case[1]))
		_check(d == int(case[2]), "distance %s -> %s = %d, got %d" % [case[0], case[1], case[2], d])
	for case in vectors.ringCounts:
		var cells := HexMath.ring(Vector2i.ZERO, int(case[0]))
		_check(cells.size() == int(case[1]), "ring %d size" % case[0])
		for cell in cells:
			_check(HexMath.distance(cell, Vector2i.ZERO) == int(case[0]), "ring %d cell %s" % [case[0], cell])
	for case in vectors.spiralCounts:
		_check(HexMath.spiral(Vector2i.ZERO, int(case[0])).size() == int(case[1]), "spiral %d size" % case[0])
	for case in vectors.toPixel:
		var p := HexMath.to_pixel(_v(case[0]), float(case[1]))
		var expected := Vector2(case[2][0], case[2][1])
		_check(p.distance_to(expected) < 1e-4, "to_pixel %s = %s, got %s" % [case[0], expected, p])
	for case in vectors.round:
		var r := HexMath.round_axial(float(case[0][0]), float(case[0][1]))
		_check(r == _v(case[1]), "round %s = %s, got %s" % [case[0], case[1], r])


func _test_hex_round_trip() -> void:
	for cell in HexMath.spiral(Vector2i.ZERO, 6):
		_check(HexMath.from_pixel(HexMath.to_pixel(cell, 37.0), 37.0) == cell, "pixel round trip %s" % cell)


func _test_resource_vectors() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join(RESOURCE_VECTORS_PATH)
	var vectors: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	for case in vectors.cases:
		var amounts := Ledger.amounts_at(case.ledger, TimeUtil.parse_iso(case.at))
		for kind in case.expected:
			_check(absf(amounts[kind] - case.expected[kind]) < 1e-6, "%s: %s = %s, got %s" % [case.name, kind, case.expected[kind], amounts[kind]])


func _test_time_util() -> void:
	_check(TimeUtil.parse_iso("1970-01-01T00:00:00.000Z") == 0.0, "epoch parses to 0")
	_check(absf(TimeUtil.parse_iso("2026-10-18T11:43:21.456Z") - 1792323801.456) < 1e-3, "ISO with millis parses")
	_check(TimeUtil.format_duration(45) == "45s", "45s")
	_check(TimeUtil.format_duration(125) == "2m 05s", "2m 05s")
	_check(TimeUtil.format_duration(3 * 3600 + 20 * 60) == "3h 20m", "3h 20m")
	_check(TimeUtil.format_duration(-5) == "0s", "negative clamps to 0s")


func _test_rules() -> void:
	var def := {"cost": {"wood": 40, "stone": 60, "grain": 30, "iron": 20}, "costGrowth": 1.6, "buildSeconds": 90, "timeGrowth": 1.55}
	_check(Rules.level_cost(def, 1) == {"wood": 40, "stone": 60, "grain": 30, "iron": 20}, "level 1 costs base")
	_check(Rules.level_cost(def, 2).wood == 64, "level 2 cost grows")
	_check(is_equal_approx(Rules.build_seconds(def, 1, 10.0), 9.0), "world speed divides build time")
	_check(is_equal_approx(Rules.build_seconds(def, 1, 10.0, 0.5), 4.5), "a bigger Elder's Hall builds faster")


func _test_village_layout() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join(BUILDINGS_PATH)
	var data := {"buildings": JSON.parse_string(FileAccess.get_file_as_string(path))}
	_check(Rules.unlocked_slots(data, 1) == 4, "4 slots open at Hall 1")
	_check(Rules.unlocked_slots(data, 3) == 6, "one more slot per Hall level")
	_check(Rules.unlocked_slots(data, 10) == 12, "capped at the slot count")
	_check(Rules.slot_unlock_level(data, 3) == 1 and Rules.slot_unlock_level(data, 4) == 2 and Rules.slot_unlock_level(data, 11) == 9, "slot unlock levels")
	for index in 12:
		var level := Rules.slot_unlock_level(data, index)
		_check(Rules.unlocked_slots(data, level) > index and (level == 1 or Rules.unlocked_slots(data, level - 1) <= index), "slot %d opens exactly at Hall %d" % [index, level])
	var base_queue := int(data.buildings.village.baseQueueLimit)
	_check(Rules.queue_limit(data, 1) == base_queue and Rules.queue_limit(data, 3) == base_queue + 1 and Rules.queue_limit(data, 9) == base_queue + 3, "queue grows every 3 Hall levels")
	_check(is_equal_approx(Rules.hall_speedup(data, 1), 1.0) and Rules.hall_speedup(data, 2) < 1.0, "Hall speeds up building")

	var village := {
		"levels": {"elder_hall": 1, "farm": 2, "storehouse": 1},
		"plots": {"c10": {"building": null, "level": 0}, "f6": {"building": "farm", "level": 2}, "c0": {"building": "elder_hall", "level": 1},
			"f10": {"building": "iron_mine", "level": 0}, "c1": {"building": "storehouse", "level": 1}, "c2": {"building": null, "level": 0},
			"f2": {"building": "woodcutter", "level": 0}, "c3": {"building": null, "level": 0}},
		"queue": [{"plot": "f6", "building": "farm", "targetLevel": 3}, {"plot": "f6", "building": "farm", "targetLevel": 4},
			{"plot": "c2", "building": "barracks", "targetLevel": 1}],
	}
	_check(Rules.plot_ids(village) == ["f2", "f6", "f10", "c0", "c1", "c2", "c3", "c10"], "plots in layout order: %s" % [Rules.plot_ids(village)])
	_check(Rules.planned_plot(village, "f6") == {"building": "farm", "level": 4}, "planned level counts the queue")
	_check(Rules.planned_plot(village, "c2") == {"building": "barracks", "level": 1}, "queued construction fills the slot")
	_check(Rules.planned_plot(village, "f2") == {"building": "woodcutter", "level": 0}, "untouched field")
	_check(not Rules.is_locked(data, village, "c3") and Rules.is_locked(data, village, "c10"), "slots past the Hall's reach are locked")
	_check(not Rules.is_locked(data, village, "f10"), "fields are never locked")
	_check(Rules.constructible(data, village) == ["scout_lodge", "caravan_yard", "settlers_lodge", "academy"], "only buildings not yet built or queued: %s" % [Rules.constructible(data, village)])
	var farm: Dictionary = data.buildings.buildings.farm
	_check(Rules.field_production(farm, 0, 1.0) == 0.0, "unbuilt field produces nothing")
	_check(is_equal_approx(Rules.field_production(farm, 2, 10.0), float(farm.production.basePerHour) * float(farm.production.growth) * 10.0), "field production grows per level")

	var with_outposts := village.duplicate(true)
	with_outposts.q = 2
	with_outposts.r = 0
	with_outposts.plots["o3,-2"] = {"building": "outpost", "level": 2, "terrain": "forest"}
	_check(Rules.plot_ids(with_outposts) == Rules.plot_ids(village), "outposts are not village plots")
	_check(Rules.outpost_plots(with_outposts) == ["o3,-2"] and Rules.outpost_hex("o3,-2") == Vector2i(3, -2), "outpost plots")
	_check(Rules.outpost_plot(Vector2i(-1, 4)) == "o-1,4" and Rules.outpost_hex("o-1,4") == Vector2i(-1, 4), "outpost plot ids round-trip")
	_check(Rules.outpost_limit(data, 1) == 1 and Rules.outpost_limit(data, 2) == 2 and Rules.outpost_limit(data, 5) == 3, "outposts per Hall level")
	var forest_yield := Rules.outpost_yield(data, "forest", 2, 10.0)
	_check(is_equal_approx(forest_yield.wood, 10.0 * 1.35 * 10.0) and forest_yield.stone == 0.0, "outpost yield by terrain and level: %s" % forest_yield)
	_check(Rules.outpost_yield(data, "hills", 1, 1.0) == {"wood": 0.0, "stone": 6.0, "grain": 0.0, "iron": 4.0}, "hills yield stone and iron")
	_check(Rules.outpost_yield(data, "forest", 0, 1.0).wood == 0.0, "an outpost in ruins gathers nothing")
	_check(Rules.claim_problem(data, village.merged({"q": 2, "r": 0}), Vector2i(3, -1), "plains", false) == "", "a free plains hex in range can be claimed")
	_check(Rules.claim_problem(data, with_outposts, Vector2i(3, -1), "plains", false).begins_with("Your village can hold 1 outpost;"), "the Hall limits outposts")
	_check(Rules.claim_problem(data, village.merged({"q": 2, "r": 0}), Vector2i(5, 0), "plains", false).begins_with("Outposts go within 2"), "out of range")
	_check(Rules.claim_problem(data, village.merged({"q": 2, "r": 0}), Vector2i(3, 0), "swamp", false) == "Nothing to gather here.", "no yield")
	_check(Rules.claim_problem(data, village.merged({"q": 2, "r": 0}), Vector2i(3, 0), "forest", true) == "Already taken.", "taken")

	var rects := VillageView.layout(Vector2(1000, 1000), 12, 12)
	_check(rects.size() == 25, "a rect per plot (12 fields, 12 slots, the gate)")
	_check((rects["c0"] as Rect2).get_center().is_equal_approx(Vector2(500, 500)), "the Hall stands in the middle")
	var ring := []
	for i in range(1, 12):
		ring.append(snappedf((rects["c%d" % i] as Rect2).get_center().distance_to(Vector2(500, 500)), 0.01))
	_check(ring.min() > 150.0 and ring.max() < 200.0, "the other slots stand in a ring around it: %s" % [ring])
	for a in rects:
		_check(VillageView.plot_at(rects, (rects[a] as Rect2).get_center()) == a, "tapping %s picks it" % a)
		for b in rects:
			if a < b:
				_check(not (rects[a] as Rect2).intersects(rects[b]), "%s and %s do not overlap" % [a, b])
	_check(VillageView.plot_at(rects, Vector2(2, 2)) == "", "a tap on open ground picks nothing")


func _test_training() -> void:
	var batch := {"unit": "spearman", "count": 5, "startsAt": "2026-02-01T12:00:00.000Z", "perUnitMs": 1000}
	var t0 := TimeUtil.parse_iso(batch.startsAt)
	_check(Rules.finished_by(batch, t0 - 1.0) == 0, "nothing finished before the start")
	_check(Rules.finished_by(batch, t0 + 0.999) == 0, "first unit not done before its interval")
	_check(Rules.finished_by(batch, t0 + 3.5) == 3, "one unit per interval")
	_check(Rules.finished_by(batch, t0 + 99.0) == 5, "capped at the batch size")
	var village := {"garrison": {"spearman": 2, "scout": 1}, "training": [batch]}
	_check(Rules.garrison_at(village, t0 + 2.0) == {"spearman": 4, "scout": 1}, "garrison counts finished units")
	_check(Rules.unit_cost({"cost": {"wood": 50, "stone": 20, "grain": 30, "iron": 30}}, 3) == {"wood": 150, "stone": 60, "grain": 90, "iron": 90}, "batch cost")


## Catches parse errors in scripts and scenes the other tests don't touch.
## load() still returns a Script when it fails to parse, so check that it
## can actually be instantiated.
func _test_everything_loads(dir_path: String) -> void:
	for file in DirAccess.get_files_at(dir_path):
		var path := dir_path.path_join(file)
		if file.ends_with(".gd"):
			var script := load(path) as Script
			_check(script != null and script.can_instantiate(), "%s compiles" % path)
		elif file.ends_with(".tscn"):
			var scene := load(path) as PackedScene
			_check(scene != null and scene.can_instantiate(), "%s loads" % path)
	for sub in DirAccess.get_directories_at(dir_path):
		_test_everything_loads(dir_path.path_join(sub))


func _test_wave_math() -> void:
	var wave := {"status": "marching", "spawnAt": "2026-03-01T00:00:00.000Z", "path": [[0, -8, 0], [0, -7, 1000], [1, -7, 3000]]}
	var t0 := TimeUtil.parse_iso(wave.spawnAt)
	var start := WaveMath.progress(wave, t0)
	_check(start.from == Vector2i(0, -8) and start.to == Vector2i(0, -7) and is_equal_approx(start.t, 0.0), "starts at the spawn hex")
	var mid := WaveMath.progress(wave, t0 + 2.0)
	_check(mid.from == Vector2i(0, -7) and mid.to == Vector2i(1, -7) and is_equal_approx(mid.t, 0.5), "halfway along the second leg")
	_check(WaveMath.current_hex(wave, t0 + 1.8) == Vector2i(0, -7), "still on the hex it is leaving")
	_check(WaveMath.current_hex(wave, t0 + 2.6) == Vector2i(1, -7), "on the next hex past the midpoint")
	var done := WaveMath.progress(wave, t0 + 10.0)
	_check(done.to == Vector2i(1, -7) and is_equal_approx(done.t, 1.0), "stops at the target")
	_check(WaveMath.progress({"status": "scheduled", "spawnAt": wave.spawnAt, "path": null}, t0).is_empty(), "no position before spawning")
	_check(WaveMath.visible_waves([{"status": "scheduled"}, wave, {"status": "arrived"}]).size() == 2, "scheduled waves are not on the map")


func _test_scout_text() -> void:
	var base := {"sent": 6, "survivors": 3, "dispersed": false}
	_check(ScoutText.describe(base.merged({"tier": "none", "size": null, "units": []})) == "None of the 6 scouts came back.", "no survivors")
	_check(ScoutText.describe(base.merged({"dispersed": true, "tier": "none", "size": null, "units": []}, true)) == "The horde had already scattered.", "scattered")
	var rough := base.merged({"tier": "rough", "size": {"min": 18, "max": 33}, "units": [{"unit": "grey_wolf", "name": "Grey Wolf", "min": null, "max": null}]})
	_check(ScoutText.describe(rough) == "18–33 units, mostly Grey Wolf", "rough report: %s" % ScoutText.describe(rough))
	var detailed := base.merged({"tier": "detailed", "size": {"min": 23, "max": 28}, "units": [
		{"unit": "grey_wolf", "name": "Grey Wolf", "min": 11, "max": 17},
		{"unit": "cave_bear", "name": "Cave Bear", "min": 4, "max": 4}]})
	_check(ScoutText.describe(detailed) == "23–28 units: Grey Wolf 11–17, Cave Bear 4", "detailed report: %s" % ScoutText.describe(detailed))
	_check(ScoutText.survivors(base) == "3 of 6 scouts returned", "survivor count")


func _test_battle_text() -> void:
	var rounds := [
		{"attackerLosses": {"grey_wolf": 2}, "defenderLosses": {}},
		{"attackerLosses": {"grey_wolf": 3, "leshy_thrall": 1}, "defenderLosses": {"spearman": 1}},
	]
	var defended := {"status": "defended", "round": 2, "rounds": rounds, "loot": null}
	_check(BattleText.losses(defended) == {"attacker": 6, "defender": 1}, "losses add up over rounds")
	_check(BattleText.outcome(defended, "Vesna's village") == "Defended Vesna's village: 6 of the horde fell, we lost 1.", "defended text: %s" % BattleText.outcome(defended, "Vesna's village"))
	var raided := {"status": "raided", "round": 2, "rounds": rounds, "loot": {"wood": 120, "stone": 0, "grain": 30, "iron": 0}}
	_check(BattleText.outcome(raided, "Mila's village").ends_with("Taken: Wood 120, Grain 30."), "raided text: %s" % BattleText.outcome(raided, "Mila's village"))
	_check(BattleText.raid({"q": 3, "r": -2, "levelAfter": 0}, "Vesna's village") == "A horde burned the outpost of Vesna's village at (3, -2) to ruins.", "raid to ruins")
	_check(BattleText.raid({"q": 3, "r": -2, "levelAfter": 2}, "Vesna's village").ends_with("down to level 2."), "raid down a level")
	var stanced := {"sent": 4, "survivors": 4, "dispersed": false, "tier": "detailed", "stance": "hold_the_line", "size": {"min": 9, "max": 11}, "units": [{"unit": "grey_wolf", "name": "Grey Wolf", "min": 5, "max": 7}]}
	_check(ScoutText.describe(stanced) == "9–11 units, hold the line stance: Grey Wolf 5–7", "scout report shows stance: %s" % ScoutText.describe(stanced))


func _test_caravans() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join("../data/logistics.json")
	var data := {"logistics": JSON.parse_string(FileAccess.get_file_as_string(path))}
	_check(CaravanMath.needed(data, {"wood": 500}) == 1 and CaravanMath.needed(data, {"wood": 400, "iron": 101}) == 2, "caravans needed per 500")
	_check(CaravanMath.needed(data, {"wood": 0}) == 0, "nothing to carry")
	var trips := [
		{"villageId": 1, "caravans": 2, "status": "outbound"},
		{"villageId": 1, "caravans": 1, "status": "done"},
		{"villageId": 2, "caravans": 1, "status": "returning"},
	]
	_check(CaravanMath.out(trips, 1) == 2, "caravans still on the road")
	_check(CaravanMath.available(data, {"id": 1, "levels": {"caravan_yard": 3}}, trips) == 1, "yard level minus caravans out")
	_check(CaravanMath.vault_upgrade_cost(data, 2) == {"wood": 800, "stone": 1000, "grain": 400, "iron": 400}, "vault level 2 cost")
	_check(is_equal_approx(CaravanMath.vault_upgrade_seconds(data, 2, 10.0), 360.0), "vault upgrade time")

	var caravan := {"status": "outbound", "departsAt": "2026-03-01T00:00:00.000Z", "arrivesAt": "2026-03-01T00:00:02.000Z",
		"path": [[2, 0, 0], [1, 0, 1000], [0, 0, 2000]]}
	var t0 := TimeUtil.parse_iso(caravan.departsAt)
	var out := CaravanMath.progress(caravan, t0 + 0.5)
	_check(out.from == Vector2i(2, 0) and out.to == Vector2i(1, 0) and is_equal_approx(out.t, 0.5), "outbound on the first leg")
	caravan.status = "returning"
	var back := CaravanMath.progress(caravan, t0 + 2.5)
	_check(back.from == Vector2i(0, 0) and back.to == Vector2i(1, 0) and is_equal_approx(back.t, 0.5), "heading home the same road backwards: %s" % back)
	caravan.status = "done"
	_check(CaravanMath.progress(caravan, t0).is_empty(), "finished trips are off the map")


func _test_expansion() -> void:
	var root := ProjectSettings.globalize_path("res://")
	var data := {
		"expansion": JSON.parse_string(FileAccess.get_file_as_string(root.path_join("../data/expansion.json"))),
		"terrain": JSON.parse_string(FileAccess.get_file_as_string(root.path_join("../data/terrain.json"))),
	}
	var units: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("../data/units.json")))
	var home := Vector2i(2, 0)
	var villages := [home, Vector2i(-2, 0)]
	_check(Rules.settle_problem(data, Vector2i(5, 0), "plains", home, villages, false) == "", "a free plains hex can be settled")
	_check(Rules.settle_problem(data, Vector2i(5, 0), "swamp", home, villages, false).begins_with("Villages can't be founded on Swamp"), "swamp")
	_check(Rules.settle_problem(data, Vector2i(9, 0), "plains", home, villages, false).begins_with("Settlers walk at most 6"), "too far")
	_check(Rules.settle_problem(data, Vector2i(4, 0), "plains", home, villages, false).begins_with("Villages stand at least 3"), "too close")
	_check(Rules.settle_problem(data, Vector2i(5, 0), "plains", home, villages, true) == "An outpost stands there.", "outpost")
	var settler: Dictionary = units.units.settler
	_check(Rules.unit_cost(settler, 1, 3).wood == roundi(float(settler.cost.wood) * 2.25), "settlers get dearer per village")
	_check(Rules.unit_cost(units.units.spearman, 2, 3) == Rules.unit_cost(units.units.spearman, 2), "other units don't")
	_check(Rules.recommended_garrison(data, 1) == 10 and Rules.recommended_garrison(data, 3) == 20, "recommended garrison")


func _test_research() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join("../data/research.json")
	var data := {"research": JSON.parse_string(FileAccess.get_file_as_string(path))}
	var research := [
		{"accountId": 1, "tech": "spear_drill", "status": "done"},
		{"accountId": 1, "tech": "felling_axes", "status": "researching", "completesAt": "2026-01-01T00:00:00.000Z"},
		{"accountId": 2, "tech": "pathfinders", "status": "done"},
	]
	var mine := ResearchRules.progress(research, 1)
	_check(mine.done.keys() == ["spear_drill"] and mine.current.tech == "felling_axes", "my research")
	_check(ResearchRules.problem(data, "shield_wall", 2, mine.done, false) == "", "prerequisite known")
	_check(ResearchRules.problem(data, "shield_wall", 1, mine.done, false) == "Needs an Academy of level 2.", "academy level")
	_check(ResearchRules.problem(data, "shield_wall", 2, {}, false) == "Needs Spear Drill first.", "prerequisite missing")
	_check(ResearchRules.problem(data, "shield_wall", 2, mine.done, true) == "One tech at a time.", "one at a time")
	_check(ResearchRules.problem(data, "spear_drill", 2, mine.done, false) == "Known.", "known")
	_check(is_equal_approx(ResearchRules.time_factor({"buildTime": -0.1}, "buildTime"), 0.9) and ResearchRules.time_factor({"buildTime": -3.0}, "buildTime") == 0.1, "time factor")
	_check(CaravanMath.needed({"logistics": {"caravan": {"capacity": 500}}}, {"wood": 600}, {"caravanCapacity": 0.25}) == 1, "pack harnesses")


func _test_heroes() -> void:
	_check(HeroText.effects({"attack.all": 0.08, "lootTaken": -0.15}) == "+8% attack, −15% loot taken", "hero effects: %s" % HeroText.effects({"attack.all": 0.08, "lootTaken": -0.15}))
	_check(HeroText.effects({}) == "", "no effects")
	var hero := {"name": "Vasilisa", "level": 3, "status": "home", "villageId": 4}
	_check(HeroText.whereabouts(hero, 4, "Vesna", 0.0) == "Hero Vasilisa (Lv 3) leads this garrison", "hero at home")
	_check(HeroText.whereabouts(hero, 5, "Vesna", 0.0) == "Hero Vasilisa (Lv 3) stands in Vesna", "hero elsewhere")


func _test_orders() -> void:
	var units := {"spearman": {"name": "Spearman"}}
	_check(OrderText.describe({"kind": "train", "unit": "spearman", "target": 20, "batch": 5}, units) == "Keep 20 Spearman, 5 at a time", "train order")
	_check(OrderText.describe({"kind": "rebuild"}, units) == "Rebuild raided outposts", "rebuild order")
	_check(OrderText.describe({"kind": "surplus", "share": 0.8}, units) == "Send all above 80% of storage to the vault", "surplus order")


func _test_inbox() -> void:
	_check(InboxText.ago(1000.0, 1030.0) == "just now", "just now")
	_check(InboxText.ago(1000.0, 1000.0 + 5 * 60) == "5m ago", "minutes ago")
	_check(InboxText.ago(1000.0, 1000.0 + 3 * 3600) == "3h ago", "hours ago")
	_check(InboxText.ago(1000.0, 1000.0 + 2 * 86400) == "2d ago", "days ago")
	_check(InboxText.clock(22 * 60) == "22:00" and InboxText.clock(-60) == "23:00" and InboxText.clock(7 * 60 + 5) == "07:05", "clock")


func _test_armies() -> void:
	var defs := {"spearman": {"name": "Spearman"}, "horseman": {"name": "Horseman"}}
	_check(ArmyText.units_text({"spearman": 20, "horseman": 0}, defs) == "Spearman ×20", "army units text")
	var army := {"orders": "support", "status": "stationed", "arrivesAt": "2026-01-01T00:00:00.000Z"}
	_check(ArmyText.status(army, "Vesna", 0.0) == "Standing guard at Vesna", "army status")
	var battle := {"rounds": [{"joined": [{"villageId": 3, "orders": "reinforce", "bonus": 0.18}]}, {}]}
	var names := func(id: Variant) -> String: return "Ola's village" if int(id) == 3 else "?"
	_check(ArmyText.reinforcements(battle, names) == "Ola's village (+18% pincer)", "reinforcements: %s" % ArmyText.reinforcements(battle, names))


func _test_field() -> void:
	var data := {
		"terrain": {"terrain": {"plains": {"moveCost": 1}, "forest": {"moveCost": 2}, "mountain": {"moveCost": null}}},
		"field": {
			"ambush": {"terrain": ["forest"], "prepMinutes": 60, "bonus": 0.3},
			"choke": {"minBlockedNeighbors": 3, "attackerFactor": 0.7, "holdTheLineDefense": 0.3},
			"fort": {"range": 4, "defenseBonus": 0.3},
		},
	}
	var terrain := {Vector2i.ZERO: "forest"}
	for i in 6:
		terrain[HexMath.neighbors(Vector2i.ZERO)[i]] = "mountain" if i < 3 else "plains"
	_check(FieldRules.is_choke_point(data, terrain, Vector2i.ZERO), "choke point between three mountains")
	var open := {}
	for cell in HexMath.spiral(Vector2i.ZERO, 1):
		open[cell] = "plains"
	_check(not FieldRules.is_choke_point(data, open, Vector2i.ZERO), "open plains are no choke point")
	var lines := FieldRules.ground(data, terrain, Vector2i.ZERO, {"status": "standing"}, 10.0)
	_check(lines.size() == 3 and lines[0].begins_with("Ambush ground: +30%") and lines[2] == "Fort: +30% defense.", "ground: %s" % lines)
	var village := {"q": 0, "r": 3, "name": "Vesna"}
	_check(FieldRules.fort_problem(data, village, Vector2i(0, 3), "plains", false).begins_with("Forts go within 4"), "no fort on the village")
	_check(FieldRules.fort_problem(data, village, Vector2i.ZERO, "mountain", false) == "No fort can stand here.", "no fort on a mountain")
	_check(FieldRules.fort_problem(data, village, Vector2i.ZERO, "forest", false) == "", "fort in the forest")
	var hold := {"orders": "hold", "status": "stationed", "targetVillageId": null, "target": [2, -1]}
	_check(ArmyText.held_hex(hold) == Vector2i(2, -1), "held hex")
	_check(ArmyText.status(hold, ArmyText.target_name(hold, func(_id: Variant) -> String: return "?"), 0.0) == "Holding (2, -1)", "hold status")
	var battle := {"villageId": null, "q": 2, "r": -1, "status": "raided", "rounds": [], "setup": {"ambush": true, "fort": true}}
	_check(BattleText.setup_text(battle) == "Ambush, Fort", "setup text: %s" % BattleText.setup_text(battle))
	_check(BattleText.outcome(battle, "(2, -1)").begins_with("Our army fell back from (2, -1)"), "field battle lost")


func _test_fronts() -> void:
	var data := {"enemies": {"fronts": {"east": {"faction": "Nomad Horde", "signature": "Fast."}}}}
	var lines := WaveMath.front_lines(data, ["east", "west"])
	_check(lines.size() == 1 and lines[0] == "Nomad Horde (East): Fast.", "front lines: %s" % lines)
	_check(WaveMath.front_color("south") == WaveMath.front_color("west") and WaveMath.front_color("east") != WaveMath.front_color("north"), "front colours")


func _test_horde() -> void:
	var data := {
		"buildings": {"buildings": {"farm": {"cost": {"wood": 100, "stone": 0, "grain": 0, "iron": 0}, "costGrowth": 2.0}}},
		"horde": {"ruins": {"rebuildCostShare": 0.5}, "holyCity": {"sanctity": 100}},
	}
	var cost := HordeText.rebuild_cost(data, {"f0": {"building": "farm", "level": 2}, "c1": {"building": null, "level": 0}})
	_check(cost.wood == 150 and cost.stone == 0, "rebuild cost: %s" % cost)
	_check(HordeText.decision({"decision": {"choice": "raze", "reasons": ["help is far", "it is strong"]}}) == "Razed: help is far, it is strong.", "raze text")
	_check(HordeText.decision({"decision": null}) == "", "no decision")
	_check(HordeText.camp({"kind": "lair", "size": 12}, "Monsters of the North") == "Monster lair of the Monsters of the North · 12 strong", "camp text")
	_check(HordeText.sanctity({"sanctity": 87}, data) == "Sanctity 87 / 100", "sanctity text")

	_check(HordeText.ambush({"q": 2, "r": -1, "beatenOff": false, "lost": {"wood": 200}}) == "Ambushed near (2, -1): lost Wood 200", "ambush text")
	_check(HordeText.ambush({"q": 2, "r": -1, "beatenOff": true, "lost": {}}) == "Its escort beat off an ambush near (2, -1)", "beaten off text")
	_check(HordeText.assault({"q": 3, "r": 1, "status": "cleared"}, {"attacker": 9, "defender": 2}) == "Cleared the camp at (3, 1): 9 fell, we lost 2.", "assault text")
	_check(ArmyText.status({"orders": "clear", "status": "returning", "loot": {"wood": 5}, "returnsAt": "2026-01-01T00:00:00.000Z"}, "(3, 1)", TimeUtil.parse_iso("2026-01-01T00:00:00.000Z")).begins_with("Coming home from (3, 1) with loot"), "clear army status")


func _test_group() -> void:
	_check(GroupText.quiet(null) == "No quiet hours: hordes may arrive any time", "no quiet hours")
	_check(GroupText.quiet({"start": 1320, "end": 360, "utcOffsetMinutes": 120}) == "Hordes hold off 22:00–06:00 (UTC+02:00)", "quiet hours: %s" % GroupText.quiet({"start": 1320, "end": 360, "utcOffsetMinutes": 120}))
	_check(GroupText.offset_text(-300) == "UTC−05:00", "negative offset")
	_check(GroupText.difficulty({"difficulty": {"presets": {"hard": {"name": "Hard"}}}}, "hard") == "Hard", "difficulty name")


func _test_sites() -> void:
	var data := {
		"heroes": {"items": {"perun_axe": {"name": "Axe of Perun"}}},
		"lore": {"scrolls": {"stribog_winds": {"name": "Winds of Stribog", "description": "Teaches the Wind Riders."}}},
		"research": {"techs": {"wind_riders": {"name": "Wind Riders", "academyLevel": 3, "requires": [], "requiresScroll": "stribog_winds"}}},
	}
	_check(SiteText.find(data, {"type": "gear", "item": "perun_axe"}) == "Axe of Perun", "gear find")
	_check(SiteText.find(data, {"type": "scroll", "scroll": "stribog_winds"}) == "the scroll “Winds of Stribog”", "scroll find")
	_check(SiteText.find(data, {"type": "resources", "resources": {"wood": 600, "iron": 0}}) == "Wood 600", "resource find")
	_check(SiteText.status(data, {"status": "unexplored", "guardians": null}, "?") == "Unexplored · Whether anything guards it is unknown", "unexplored site")
	_check(SiteText.status(data, {"status": "explored", "find": {"type": "ember"}}, "Vesna") == "Explored by Vesna: found a Svarog's Ember", "explored site")
	_check(ResearchRules.problem(data, "wind_riders", 5, {}, false) == "Needs the Winds of Stribog scroll.", "rare tech locked")
	_check(ResearchRules.problem(data, "wind_riders", 5, {}, false, {"stribog_winds": true}) == "", "rare tech open")
	_check(ArmyText.status({"orders": "explore", "status": "stationed"}, "(4, -2)", 0.0) == "Searching the site at (4, -2)", "exploring army")


func _test_bridge() -> void:
	var data := {"bridge": {
		"stages": [{"name": "Foundation Stones", "story": "Old stones.", "cost": {"wood": 100, "stone": 200, "grain": 0, "iron": 0}, "embers": 1, "quests": [{"kind": "site", "story": "Bring a relic."}]}],
		"quests": {"site": {"name": "Bring back a relic"}},
	}}
	var bridge := {"stage": 0, "status": "open", "donated": {"wood": 100, "stone": 50}, "embers": 0, "quests": {}}
	_check(BridgeText.title(data, bridge) == "Stage 1 of 1: Foundation Stones", "bridge title")
	_check(BridgeText.progress(data, bridge) == "Wood 100 / 100, Stone 50 / 200, Ember 0 / 1", "bridge progress: %s" % BridgeText.progress(data, bridge))
	_check(BridgeText.missing(data, bridge).stone == 150 and BridgeText.embers_missing(data, bridge) == 1, "bridge missing")
	_check(BridgeText.quests(data, bridge) == [[false, "Bring back a relic", "Bring a relic."]], "bridge quests")
	_check(BridgeText.title(data, {"status": "complete", "stage": 1}) == "The Kalinov Bridge stands", "bridge done")


func _test_run() -> void:
	var data := {"bridge": {"endings": {"won": {"title": "The Kalinov Bridge holds", "story": "…"}, "lost": {"title": "The Holy City has fallen", "story": "…"}}}}
	_check(not RunText.is_over({"status": "running"}) and RunText.is_over({"status": "lost"}), "run over")
	_check(RunText.ending(data, {"status": "won"}).title == "The Kalinov Bridge holds", "run ending")
	_check(RunText.ending(data, {"status": "running"}).is_empty(), "no ending while running")
	var now := TimeUtil.parse_iso("2026-01-01T00:00:00.000Z")
	_check(RunText.ritual_line({"status": "running", "ritualAt": null}, now) == "", "no ritual yet")
	_check(RunText.ritual_line({"status": "running", "ritualAt": "2026-01-01T02:00:00.000Z"}, now).begins_with("Ritual Night · in"), "ritual countdown: %s" % RunText.ritual_line({"status": "running", "ritualAt": "2026-01-01T02:00:00.000Z"}, now))
	_check(RunText.ritual_line({"status": "running", "ritualAt": "2025-12-31T23:00:00.000Z"}, now) == "Ritual Night", "ritual under way")
	var run := {"days": 12.5, "wavesBeaten": 9, "wavesFaced": 11, "battlesWon": 14, "campsCleared": 3, "sitesExplored": 4, "scrolls": 2, "villagesFounded": 5, "villagesLost": 1}
	var lines := RunText.stats(run)
	_check(lines[0] == "12.5 days" and lines[1] == "Hordes beaten: 9 of 11", "run stats: %s" % lines)
	_check(RunText.stats({"days": 3.0, "wavesBeaten": 0, "wavesFaced": 0, "battlesWon": 0, "campsCleared": 0, "sitesExplored": 0, "scrolls": 0, "villagesFounded": 1, "villagesLost": 0})[0] == "3 days", "whole days")
	_check(RunText.member_line({"displayName": "Mila", "villages": 3, "villagesLost": 1}) == "Mila: 3 villages, 1 lost", "member line")
	_check(RunText.member_line({"displayName": "Rusa", "villages": 1, "villagesLost": 0}) == "Rusa: 1 village", "member line one")


func _test_clans() -> void:
	var data := {
		"clans": {"clans": {"rys": {"name": "Rod Rysa", "animal": "Lynx", "best": "Wood", "weakness": "Slower research", "unique": {"unit": "forest_archer"}}}},
		"units": {"units": {"forest_archer": {"name": "Forest Archer", "clan": "rys"}}},
		"buildings": {"buildings": {}},
	}
	_check(ClanText.title(data, "rys") == "Rod Rysa (Lynx)", "clan title")
	_check(ClanText.title(data, null) == "No clan", "no clan")
	_check(ClanText.perks(data, "rys") == "Best at: Wood · Weakness: Slower research · Own: Forest Archer (unit)", "clan perks: %s" % ClanText.perks(data, "rys"))
	_check(ClanText.allowed({"name": "Spearman"}, {}), "common unit allowed")
	_check(not ClanText.allowed({"clan": "rys"}, {"clan.sokol": 1}), "other clan's unit hidden")
	_check(ClanText.allowed({"clan": "rys"}, {"clan.rys": 1}), "own clan's unit allowed")
	_check(FieldRules.fort_cost({"field": {"fort": {"cost": {"wood": 600, "stone": 900}}}}, {"fortCost": 0.3}) == {"wood": 780, "stone": 1170}, "fort cost by clan")


func _test_delegation() -> void:
	var now := TimeUtil.parse_iso("2026-01-01T00:00:00.000Z")
	var delegations := [{"ownerAccountId": 1, "delegateAccountId": 2, "since": "2025-12-31T00:00:00.000Z", "until": "2026-01-02T00:00:00.000Z"}]
	_check(DelegationText.commands(delegations, 1, 1, now), "owner commands")
	_check(DelegationText.commands(delegations, 1, 2, now), "delegate commands")
	_check(not DelegationText.commands(delegations, 1, 3, now), "others don't")
	_check(not DelegationText.commands(delegations, 1, 2, now + 2 * 86400), "hand-over runs out")
	_check(DelegationText.owners_for(delegations, 2, now) == [1], "owners for delegate")
	var e := {"ownerAccountId": 1, "delegateAccountId": 2, "villageId": 7, "action": "queued a build", "at": "2026-01-01T00:00:00.000Z"}
	_check(DelegationText.entry(e, {1: "Mila", 2: "Goran"}, {7: "Mila's village"}) == "Goran (for Mila) queued a build in Mila's village", "delegation entry")


## The local engine against the server's rules (data/fixtures/mapgen-vectors.json).
func _test_local_mapgen() -> void:
	var root := ProjectSettings.globalize_path("res://").path_join("../data")
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("fixtures/mapgen-vectors.json")))
	for case in fixture.rng:
		var rng := LocalRng.new(int(case.seed))
		var same := true
		for value in case.values:
			same = same and int(rng.next() * 4294967296.0) == int(value)
		_check(same, "rng %d" % int(case.seed))
	for case in fixture.noise:
		var noise := LocalNoise.new(LocalRng.new(int(case.seed)).callable())
		var same := true
		for point in case.points:
			# Godot's JSON reader isn't exact in the last digits.
			same = same and absf(noise.noise(point[0], point[1]) - float(point[2])) < 1e-12
		_check(same, "noise %d" % int(case.seed))
	var data := LocalData.load_data()
	_check(data.has("terrain") and data.has("buildings") and data.buildings.has("buildings"), "bundled game data")
	for case in fixture.maps:
		var map := LocalMapgen.generate(data, int(case.seed), int(case.players))
		var terrain: Array = []
		for cell in HexMath.spiral(Vector2i.ZERO, map.radius):
			terrain.append(map.terrain[LocalLand.key(cell)])
		var starts: Array = []
		for s in map.startSites:
			starts.append([float(s.x), float(s.y)])
		var rivers: Array = []
		for e in map.rivers:
			rivers.append([float(e.a.x), float(e.a.y), float(e.b.x), float(e.b.y), 1.0 if e.bridge else 0.0, float(e.size)])
		var label := "map %d/%d" % [int(case.seed), int(case.players)]
		_check(int(map.seed) == int(case.madeWith) and int(map.radius) == int(case.radius) and map.activeFronts == case.activeFronts, label + " shape")
		_check(",".join(terrain) == case.terrain, label + " terrain")
		_check(str(starts) == str(case.startSites), label + " starts")
		_check(str(rivers) == str(case.rivers), label + " rivers")


## A solo world started in the app against one started on the server
## (data/fixtures/start-world.json, server/test/start-fixture.test.ts).
func _test_local_start() -> void:
	var root := ProjectSettings.globalize_path("res://").path_join("../data")
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("fixtures/start-world.json")))
	var local := LocalServer.new(LocalData.load_data(), "")
	var at := LocalTime.parse(fixture.startedAt)
	var world := local.start_world({"name": fixture.name, "displayName": fixture.members[0].displayName, "speed": fixture.speed,
		"difficulty": fixture.difficulty, "seed": 4242}, 1, at)
	var view := local.world_view(world, at)
	for key in fixture:
		var difference := _difference(view.get(key), fixture[key], key)
		_check(difference == "", "local start: %s" % (difference if difference != "" else key))
	_check(LocalTime.iso(at) == fixture.startedAt and LocalTime.parse("2026-06-10T08:20:27.870Z") == 1781079627870, "local times")
	# Saved on the device and read back, it is the same world.
	var dir := "user://test_local"
	if DirAccess.dir_exists_absolute(dir):
		for file in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute("%s/%s" % [dir, file])
	var saved := LocalServer.new(LocalData.load_data(), dir)
	var kept := saved.start_world({"name": "Kept", "seed": 99, "speed": 10}, 1, at)
	var reopened := LocalServer.new(LocalData.load_data(), dir)
	_check(reopened.worlds.has(int(kept.id)) and _difference(reopened.world_view(reopened.worlds[kept.id], at), saved.world_view(kept, at), "saved") == "", "local world saved and read back")


## A scripted solo session against the answers the server gave
## (data/fixtures/village-scenario.json).
func _test_local_villages() -> void:
	_replay_scenario("village-scenario.json", "local villages")
	_check(LocalServer._js_number(0.1 + 0.2) == "0.30000000000000004" and LocalServer._js_number(70.0) == "70" and LocalServer._js_number(70.5) == "70.5", "numbers as JavaScript prints them")


## Hordes setting out, battles and what follows (data/fixtures/wave-scenario.json,
## battle-scenario.json, raze-scenario.json, logistics-scenario.json,
## army-scenario.json, expansion-scenario.json, endgame-scenario.json,
## inbox-scenario.json, ember-scenario.json).
func _test_local_waves() -> void:
	_replay_scenario("wave-scenario.json", "local waves")
	_replay_scenario("battle-scenario.json", "local battles")
	_replay_scenario("raze-scenario.json", "local razes")
	_replay_scenario("logistics-scenario.json", "local logistics")
	_replay_scenario("army-scenario.json", "local armies")
	_replay_scenario("expansion-scenario.json", "local expansion")
	_replay_scenario("endgame-scenario.json", "local endgame")
	_replay_scenario("inbox-scenario.json", "local inbox")
	_replay_scenario("ember-scenario.json", "local embers")


## Solo worlds are saved on the device, read back, and deleted.
func _test_george_bar() -> void:
	_check(is_equal_approx(GeorgeBar.new(4.75, 9.5).ratio, 0.5), "george bar: half the costs raised, half way")
	_check(GeorgeBar.new(20.0, 9.5).ratio == 1.0 and GeorgeBar.new(0.0, 0.0).ratio == 1.0, "george bar: costs met (or none), he reaches the dragon")
	_check(GeorgeBar.new(-3.0, 9.5).ratio == 0.0, "george bar: never behind the start")
	for id in ["ui/george", "ui/dragon"]:
		_check(Art.texture(id) != null, "george bar: art %s" % id)


func _test_sound_cues() -> void:
	var now := 1_000_000.0
	var soon := Time.get_datetime_string_from_unix_time(int(now + 600), false) + "Z"
	var later := Time.get_datetime_string_from_unix_time(int(now + 7200), false) + "Z"
	var waves := [
		{"id": 1, "status": "marching", "targetVillageId": 5, "arrivesAt": later},
		{"id": 2, "status": "marching", "targetVillageId": 9, "arrivesAt": soon},
		{"id": 3, "status": "spawning", "targetVillageId": null},
	]
	_check(SoundCues.incoming(waves, [5]) == [1], "sound: hordes marching on my villages")
	_check(not SoundCues.threatened(waves, [5], now), "sound: a horde two hours off is not near")
	_check(SoundCues.threatened(waves, [9], now), "sound: a horde ten minutes off is near")
	_check(SoundCues.threatened([{"id": 4, "status": "battling", "targetVillageId": 5}], [5], now), "sound: a battle at my village is near")
	_check(not SoundCues.threatened([{"id": 4, "status": "battling", "targetVillageId": 6}], [5], now), "sound: someone else's battle is not")
	_check(SoundCues.track("map", "running", false) == "map", "sound: calm map music")
	_check(SoundCues.track("village", "running", true) == "threat", "sound: tense music when a horde is near")
	_check(SoundCues.track("battle", "running", true) == "battle", "sound: battle music on the battle map")
	_check(SoundCues.track("battle", "won", false) == "won", "sound: the run's ending wins out")
	_check(SoundCues.new_hordes([1], [1, 2]) == [2], "sound: a horn for each new horde")
	_check(SoundCues.new_hordes([1, 2], [2]).is_empty(), "sound: no horn when a horde is gone")


func _test_local_saves() -> void:
	var dir := OS.get_user_data_dir().path_join("test-local-saves")
	DirAccess.make_dir_recursive_absolute(dir)
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	var data := LocalData.load_data()
	var first := LocalServer.new(data, dir)
	var a := first.start_world({"name": "One", "seed": 11}, 1, LocalTime.parse("2026-06-01T08:00:00.000Z"))
	var b := first.start_world({"name": "Two", "seed": 12}, 1, LocalTime.parse("2026-06-01T09:00:00.000Z"))
	_check(int(a.id) == -1 and int(b.id) == -2, "solo worlds take ids -1, -2: %s %s" % [a.id, b.id])
	var again := LocalServer.new(data, dir)
	_check(again.worlds.size() == 2 and again.worlds[-2].name == "Two", "solo worlds are read back from the device")
	_check(_difference(again.world_view(again.worlds[-1], 0), first.world_view(first.worlds[-1], 0), "view") == "", "a saved world reads back the same")
	again.delete_world(-1)
	_check(not again.worlds.has(-1) and LocalServer.new(data, dir).worlds.keys() == [-2], "a deleted solo world is gone from the device")
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))


## Notices rendered as the server renders them, in English and Serbian
## (data/fixtures/notice-vectors.json).
func _test_local_notices() -> void:
	var root := ProjectSettings.globalize_path("res://").path_join("../data")
	var vectors: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("fixtures/notice-vectors.json")))
	for v in vectors.localized:
		var text := LocalInbox.localize(v.language, v.template, v.vars)
		_check(text == v.text, "notice in %s: %s != %s" % [v.language, text, v.text])
	for d in vectors.digests:
		var text := LocalInbox.digest_summary(d.kinds, d.language)
		_check(text == d.text, "digest in %s: %s != %s" % [d.language, text, d.text])


## Replays a scenario recorded on the server (server/test/scenario.ts) on a
## solo world started in the app, and compares every answer.
func _replay_scenario(file: String, name: String) -> void:
	var root := ProjectSettings.globalize_path("res://").path_join("../data")
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("fixtures").path_join(file)))
	var start: Dictionary = fixture.start
	var local := LocalServer.new(LocalData.load_data(), "")
	var now := LocalTime.parse(start.at)
	var world := local.start_world({"name": start.name, "displayName": start.displayName, "speed": start.speed,
		"difficulty": start.difficulty, "seed": int(start.seed)}, 1, now)
	var i := 0
	for step in fixture.steps:
		i += 1
		if step.has("advance"):
			now += int(step.advance)
			local.drain(world, now, [])
			continue
		if step.has("set"):
			# The scenario jumps ahead (server/test/scenario.ts WorldSet).
			if step.set.has("bridge"):
				world.bridge = LocalServer._decode(step.set.bridge)
			if step.set.has("embers"):
				world.embers = int(step.set.embers)
			if step.set.has("vault"):
				world.vault.amounts = LocalServer._decode(step.set.vault)
			continue
		var answer := local.handle(int(world.id), String(step.method), String(step.path), step.get("body"), now)
		var label := "%s %d %s %s" % [name, i, step.method, step.path]
		_check(int(answer.status) == int(step.status), "%s: status %d != %d %s" % [label, int(answer.status), int(step.status), answer.data.get("message", "")])
		var difference := _difference(answer.data, step.response, "response")
		_check(difference == "", "%s: %s" % [label, difference])


## Where two JSON values differ ("" if they don't); numbers within a hair
## (Godot's JSON reader isn't exact), dictionaries in any order.
func _difference(a: Variant, b: Variant, path: String) -> String:
	if (a is int or a is float) and (b is int or b is float):
		return "" if absf(float(a) - float(b)) <= 1e-9 * maxf(1.0, absf(float(b))) else "%s: %s != %s" % [path, a, b]
	if a is Dictionary and b is Dictionary:
		for key in b:
			if not a.has(key):
				return "%s.%s missing" % [path, key]
			var d := _difference(a[key], b[key], "%s.%s" % [path, key])
			if d != "":
				return d
		for key in a:
			if not b.has(key):
				return "%s.%s extra" % [path, key]
		return ""
	if a is Array and b is Array:
		if a.size() != b.size():
			return "%s: %d items != %d" % [path, a.size(), b.size()]
		for i in a.size():
			var d := _difference(a[i], b[i], "%s[%d]" % [path, i])
			if d != "":
				return d
		return ""
	if a is String and b is String:
		return "" if a == b else "%s: %s != %s" % [path, a, b]
	if a == null and b == null:
		return ""
	if typeof(a) == typeof(b) and a == b:
		return ""
	return "%s: %s != %s" % [path, a, b]


func _test_onboarding_almanac() -> void:
	var data := {"onboarding": {"steps": [
		{"id": "build", "title": "Raise a building", "how": ["Tap Village.", "Tap a plot."], "reward": {"wood": 150, "stone": 0, "grain": 100, "iron": 0}},
		{"id": "train", "title": "Train defenders", "reward": {"wood": 0, "stone": 0, "grain": 0, "iron": 50}},
	]}}
	_check(OnboardingText.next_step(data, {"onboarding": {}}).id == "build", "first step")
	_check(OnboardingText.next_step(data, {"onboarding": {"build": "x"}}).id == "train", "next step")
	_check(OnboardingText.next_step(data, {"onboarding": {"build": "x", "train": "y"}}).is_empty(), "all done")
	_check(OnboardingText.progress(data, {"onboarding": {"build": "x"}, "onboardingClaimed": {"build": "x"}}) == "Getting started 1 of 2", "progress counts claims")
	_check(OnboardingText.progress(data, {"onboarding": {"build": "x"}}) == "Getting started 0 of 2", "not claimed yet")
	var waiting := {"onboarding": {"train": "x"}, "onboardingClaimed": {}}
	_check(OnboardingText.current(data, waiting).id == "train" and OnboardingText.claimable(waiting, data.onboarding.steps[1]), "a reward waits")
	_check(OnboardingText.current(data, {"onboarding": {"train": "x"}, "onboardingClaimed": {"train": "x"}}).id == "build", "back to the next step")
	_check(OnboardingText.how(data.onboarding.steps[0]) == PackedStringArray(["1. Tap Village.", "2. Tap a plot."]), "how-to lines")
	_check(OnboardingText.reward(data.onboarding.steps[0]) == "Reward: Wood 150, Grain 100", "reward")
	var full := {
		"units": {"units": {"spearman": {"name": "Spearman", "family": "infantry", "building": "barracks", "requiresLevel": 1, "attack": 20, "defense": 40, "speed": 5, "carry": 40, "upkeepPerHour": 1}}},
		"buildings": {"buildings": {"barracks": {"name": "Barracks", "kind": "center", "maxLevel": 10}}},
		"battle": {"stances": {"hold_the_line": {"name": "Hold the Line", "attack": 0.9, "defense": 1.15, "retreatAt": null}}, "counters": {"infantry": {"cavalry": 1.5}}},
	}
	var units := AlmanacText.entries(full, "Units")
	_check(units[0][0] == "Spearman" and units[0][1].begins_with("Infantry · attack 20 · defense 40"), "almanac unit: %s" % units[0][1])
	_check(AlmanacText.entries(full, "Buildings")[0][1] == "Building in the village · up to level 10", "almanac building")
	var stances := AlmanacText.entries(full, "Stances")
	_check(stances[0][1] == "attack ×0.90 · defense ×1.15 · never breaks", "almanac stance: %s" % stances[0][1])
	_check(stances[1][1] == "Infantry beat cavalry (×1.5)", "almanac counters")


func _test_art() -> void:
	_check(Art.ids().size() >= 40, "art manifest read: %d ids" % Art.ids().size())
	var missing := []
	for id in Art.ids():
		if Art.texture(id) == null and not id in Art.OPTIONAL:
			missing.append(id)
	_check(missing.is_empty(), "every art id loads: %s" % [missing])
	_check(Art.has("brand/logo") and Art.has("brand/emblem") and Art.has("ui/hero") and Art.has("ui/wood"), "the brand, the start painting and the wood")
	for terrain in ["plains", "forest", "hills", "mountain", "swamp", "lake", "holy_city", "ocean", "dark_forest", "ice", "steppe", "hallowed"]:
		_check(Terrain.COLORS.has(terrain) and Terrain.HEIGHTS.has(terrain), "ground for %s" % terrain)
		for kind in MapFeatures.FEATURES.get(terrain, []):
			_check(Art.has(kind[0]), "%s on %s" % [kind[0], terrain])
	_check(Art.texture("no/such") == null, "missing art is null")
	_check(Art.settlement_id(1) == "settlement/village_1" and Art.settlement_id(2) == "settlement/village_1", "hall 1-2: stage 1")
	_check(Art.settlement_id(5) == "settlement/village_3" and Art.settlement_id(10) == "settlement/village_5", "hall 5: stage 3, hall 10: stage 5")
	_check(Art.settlement_id(0) == "settlement/village_1" and Art.settlement_id(14) == "settlement/village_5", "stages clamp")
	_check(ArmyText.main_unit({"units": {"spearman": 4, "archer": 9, "scout": 1}}) == "archer", "army's main unit")
	_check(ArmyText.main_unit({"units": {}}) == "", "empty army")
	_check(Art.building_id("barracks", 1) == "building/barracks_1" and Art.building_id("barracks", 4) == "building/barracks_2" and Art.building_id("barracks", 8) == "building/barracks_3", "building stages")
	_check(Art.building_id("farm", 10, true) == "field/farm_3", "field stages")
	var missing_art := []
	for b in ["elder_hall", "storehouse", "barracks", "scout_lodge", "caravan_yard", "settlers_lodge", "academy", "granary_temple", "stone_redoubt", "longhouse_hall"]:
		for level in [1, 5, 10]:
			if not Art.has(Art.building_id(b, level)):
				missing_art.append(Art.building_id(b, level))
	for f in ["woodcutter", "quarry", "farm", "iron_mine"]:
		if not Art.has(Art.building_id(f, 2, true)):
			missing_art.append(f)
	for material in ["wood", "timber", "stone", "fortress"]:
		if not Art.has(Art.building_id("wall", 1, false, material)):
			missing_art.append(material)
	var root := ProjectSettings.globalize_path("res://").path_join("../data")
	var fronts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("enemies.json"))).fronts
	for front in fronts:
		for unit in fronts[front].units:
			if not Art.has("unit/" + unit):
				missing_art.append("unit/" + unit)
	for b in ["archer_tower", "gate_tower", "ballista", "murder_holes", "ditch", "watchtower"]:
		for level in [1, 5, 10]:
			if not Art.has(Art.building_id(b, level)):
				missing_art.append(Art.building_id(b, level))
	_check(missing_art.is_empty(), "art for every village building, wall material and enemy unit: %s" % [missing_art])
	var theme := UiTheme.build()
	var panel := theme.get_stylebox("panel", "PanelContainer")
	_check(panel is Parchment and Art.texture("ui/parchment") != null, "sheets are torn parchment")
	var open_tab := theme.get_stylebox("disabled", "TabButton")
	_check(open_tab is StyleBoxFlat and (open_tab as StyleBoxFlat).border_width_bottom == 4 and (open_tab as StyleBoxFlat).border_color == UiTheme.MADDER, "open tab underlined in madder")
	_check(theme.get_stylebox("focus", "Button") is StyleBoxFlat, "keyboard focus is visible")
	_check(theme.get_stylebox("normal", "Primary") is StyleBoxFlat, "a gold primary button")
	_check(theme.get_font("font", "Heading") != null and theme.default_font != null, "fonts loaded")
	var heading_font := theme.get_font("font", "Heading")
	_check(heading_font.has_char("Č".unicode_at(0)) and heading_font.has_char("ђ".unicode_at(0)), "heading font covers Serbian")
	_check(UI.costs({"wood": 320, "stone": 0, "grain": 5, "iron": 1}).contains("[img=30]res://art/generated/resource/wood.svg[/img] 320"), "costs with icons")
	var flat := StyleBoxFlat.new()
	_check(UiTheme.frame("no/such", 64, 16, 10, flat) == flat, "the vector style without the art")
	_check(UiTheme.frame("icon/map", 64, 16, 10, flat) is FrameStyle, "art replaces the style")


func _test_rivers() -> void:
	var rivers := [[0, 1, 1, 1, "none"], [1, 0, 1, 1, "standing"]]
	var at := RiverText.edges_at(rivers, Vector2i(1, 1))
	_check(at.size() == 2 and at[0].other == Vector2i(0, 1) and at[1].crossing == "standing", "river edges at a hex")
	_check(RiverText.edges_at(rivers, Vector2i(5, 5)).is_empty(), "no river here")
	_check(RiverText.direction(Vector2i(0, 0), Vector2i(1, 0)) == 0 and RiverText.direction(Vector2i(0, 0), Vector2i(0, 1)) == 5, "edge directions")
	_check(RiverText.direction(Vector2i(0, 0), Vector2i(2, 0)) == -1, "not neighbours")
	var data := {"field": {"bridge": {"range": 4}}}
	_check(RiverText.bridge_problem(data, Vector2i(0, 0), Vector2i(3, 0), Vector2i(4, 0)) == "", "bridge in range")
	_check(RiverText.bridge_problem(data, Vector2i(0, 0), Vector2i(5, 0), Vector2i(6, 0)) != "", "bridge out of range")
	_check(RiverText.bridge_problem(data, Vector2i(0, 0), Vector2i(3, 0), Vector2i(4, 0), {Vector2i(4, 0): "lake"}) != "", "no bridge onto a lake")
	var hdata := {"heroes": {"roster": {"volkh": {"name": "Volkh", "title": "The wise volkhv", "effects": {"researchTime": -0.12}, "traits": [{"name": "Healing rites", "description": "Heals.", "effects": {"woundTime": -0.5}}]}}}}
	_check(HeroText.roster_ids(hdata) == ["volkh"] and HeroText.roster_title(hdata, "volkh") == "Volkh, the wise volkhv", "roster hero title")
	_check(HeroText.roster_title(hdata, null) == "No hero yet" and HeroText.roster(hdata, "nobody").is_empty(), "no roster hero")
	_check(HeroText.roster_traits(hdata, "volkh")[0] == "Healing rites: Heals. (−50% time wounded)", "roster traits")
	var qdata := {"quests": {"kinds": {"ambush": {"description": "The next horde from the {front} sets out later."}, "ruins": {"description": "Search the {site}."}}}}
	_check(HeroText.quest_description(qdata, {"kind": "ambush", "front": "north"}) == "The next horde from the north sets out later.", "quest front")
	_check(HeroText.quest_description(qdata, {"kind": "ruins", "front": null}, "Kurgan") == "Search the Kurgan.", "quest site")
	_check(HeroText.quest_terms({"hours": 4.0, "risk": 0.25, "xp": 40}, 1.0).ends_with("· 25% risk · +40 XP"), "quest terms")
	_check(RiverText.size_of([0, 0, 1, 0, "none", 3]) == 3 and RiverText.size_of([0, 0, 1, 0, "none"]) == 1, "river size")
	_check(RiverText.roads_at([[0, 0, 1, 0, "standing"], [0, 1, 0, 0, "building"]], Vector2i(0, 0)) == {Vector2i(1, 0): "standing", Vector2i(0, 1): "building"}, "roads at a hex")
	var rdata := {"field": {"road": {"range": 4}}, "terrain": {"terrain": {"plains": {"moveCost": 1}, "lake": {"moveCost": null}}}}
	var rterrain := {Vector2i(0, 0): "plains", Vector2i(1, 0): "plains", Vector2i(0, 1): "lake"}
	_check(RiverText.road_problem(rdata, rterrain, [], Vector2i(0, 0), Vector2i(0, 0), Vector2i(1, 0)) == "", "road can run")
	_check(RiverText.road_problem(rdata, rterrain, [], Vector2i(0, 0), Vector2i(0, 0), Vector2i(0, 1)) != "", "no road into a lake")
	_check(RiverText.road_problem(rdata, rterrain, [[0, 0, 1, 0, "none"]], Vector2i(0, 0), Vector2i(0, 0), Vector2i(1, 0)).begins_with("A river"), "no road over a river")


func _test_battle_story() -> void:
	var data := {
		"units": {"units": {"spearman": {"name": "Spearman", "family": "infantry"}, "archer": {"name": "Archer", "family": "archers"}}},
		"enemies": {"fronts": {"north": {"units": {"grey_wolf": {"name": "Grey Wolf", "family": "cavalry"}}}}},
	}
	var battle := {
		"id": 3, "status": "defended", "attackerStance": "offensive", "villageId": 1,
		"attackerInitial": {"grey_wolf": 40}, "defenderInitial": {"spearman": 20, "archer": 10},
		"rounds": [
			{"round": 1, "attackerLosses": {"grey_wolf": 12}, "defenderLosses": {"spearman": 3}},
			{"round": 2, "attackerLosses": {"grey_wolf": 20}, "defenderLosses": {"archer": 1}, "joined": [{"armyId": 9, "villageId": 2, "orders": "pincer", "units": {"spearman": 5}, "bonus": 0.2}]},
		],
	}
	var start := BattleStory.units_at(battle, 0)
	var after := BattleStory.units_at(battle, 2)
	_check(start.attacker.grey_wolf == 40 and start.defender.spearman == 20, "battle: the start")
	_check(after.attacker.grey_wolf == 8 and after.defender.spearman == 22 and after.defender.archer == 9, "battle: losses and help after two rounds")
	var squads := BattleStory.squads(data, start.defender, after.defender)
	_check(squads.size() == 2 and squads[0].unit == "spearman" and squads[1].unit == "archer", "squads front to back by family")
	_check(BattleStory.per_block({"grey_wolf": 40}) == 5 and BattleStory.squads(data, start.attacker, after.attacker)[0].alive == 2, "blocks of five wolves, two left")
	_check(BattleStory.units_text(data, {"grey_wolf": 2, "spearman": 1}) == "2 Grey Wolves and 1 Spearman", "unit list in words")
	_check(BattleStory.plural("Spearman", 3) == "Spearmen", "plural men")
	var ctx := {"place": "Vesna's village", "enemy": "the Monsters of the North", "village_name": func(_id: Variant) -> String: return "Mila's village"}
	_check(BattleStory.opening(data, battle, ctx).begins_with("The Monsters of the North came on, offensive, with 40 Grey Wolves."), "battle opening")
	var two := BattleStory.narrate(data, battle, 2, ctx)
	_check(two.contains("Help from Mila's village struck from behind with 5 Spearmen (+20%)") and two.contains("20 Grey Wolves fell") and two.ends_with("The field is ours."), "round two told: %s" % two)
	_check(BattleStory.narrate(data, battle, 3, ctx) == "", "no third round")


func _test_leaders() -> void:
	var chief := {"id": 4, "front": "east", "title": "Khan Konchak", "level": 5, "status": "alive", "woundedUntil": null,
		"battles": 3, "wins": 2, "losses": 1, "razed": 1, "kills": 14, "grudgeVillageId": 7,
		"effects": {"attack": 0.08, "defense": 0.0, "nerve": 0.06, "loot": 0.24}, "diedAt": null}
	_check(LeaderText.name_line(chief) == "Khan Konchak · level 5", "leader name line")
	_check(LeaderText.record(chief) == "3 battles: 2 won, 1 lost · 1 village razed · 14 of ours slain", "leader record")
	_check(LeaderText.effects(chief) == "+8% attack, holds 6% longer, +24% plunder", "leader effects")
	_check(LeaderText.state(chief, 0.0) == "Ready to ride", "leader ready")
	var data := {"leaders": {"grudge": {"attack": 0.15}}}
	_check(LeaderText.grudge(data, chief, func(_id: Variant) -> String: return "Vesna's village") == "Swore revenge on Vesna's village (+15% attack there)", "leader grudge")
	var battle := {"status": "defended", "endedAt": "2030-01-01T10:00:00.000Z"}
	_check(LeaderText.after_battle(chief, battle, "Vesna's village") == "Khan Konchak fled the field wounded, swearing revenge on Vesna's village.", "leader fled")
	var dead := chief.duplicate()
	dead.status = "dead"
	dead.diedAt = "2030-01-01T10:00:00.000Z"
	_check(LeaderText.after_battle(dead, battle, "x") == "Khan Konchak fell with the last of them.", "leader fell")
	_check(LeaderText.after_battle(chief, {"status": "raided"}, "x") == "Khan Konchak rode on, prouder.", "leader won")


func _test_translation() -> void:
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("sr_Latn")
	_check(UI.t("Play as guest") == "Igraj kao gost", "Serbian: %s" % UI.t("Play as guest"))
	_check(UI.tn("%d player", "%d players", 1) == "%d igrač" and UI.tn("%d player", "%d players", 3) == "%d igrača" and UI.tn("%d player", "%d players", 5) == "%d igrača", "Serbian plurals")
	_check(UI.t("{name} the Hungry").replace("{name}", "Mara") == "Mara Gladni", "data strings translated")
	TranslationServer.set_locale("en")
	_check(UI.t("Play as guest") == "Play as guest", "English is the source")
	TranslationServer.set_locale(before)


func _test_walls() -> void:
	var root := ProjectSettings.globalize_path("res://").path_join("../data")
	var data := {"walls": JSON.parse_string(FileAccess.get_file_as_string(root.path_join("walls.json"))),
		"enemies": JSON.parse_string(FileAccess.get_file_as_string(root.path_join("enemies.json"))),
		"buildings": {"village": {"centerSlots": 12, "slotsUnlockedAtStart": 4, "slotsPerHallLevel": 1}}}
	var village := {"levels": {"elder_hall": 1}, "plots": {"w": {"building": "wall", "level": 3}, "t0": {"building": null, "level": 0}, "t1": {"building": null, "level": 0}, "t2": {"building": null, "level": 0}, "c5": {"building": null, "level": 0}, "f0": {"building": "farm", "level": 0}}}
	_check(Rules.open_tower_slots(data, 3) == 2 and Rules.tower_unlock_level(data, 2) == 5, "wall slots open with the walls")
	_check(not Rules.is_locked(data, village, "t1") and Rules.is_locked(data, village, "t2"), "wall slot locks")
	_check(Rules.is_locked(data, village, "c5") and not Rules.is_locked(data, village, "w") and not Rules.is_locked(data, village, "f0"), "other plots lock as before")
	_check(Rules.plot_ids(village) == ["f0", "c5", "w", "t0", "t1", "t2"], "plots in layout order: %s" % [Rules.plot_ids(village)])
	_check(WallText.tier(data, 2) == "Palisade" and WallText.tier(data, 3) == "Timber Rampart" and WallText.tier(data, 8) == "Fortress Walls" and WallText.tier(data, 0) == "", "wall tiers")
	_check(WallText.material(data, 1) == "wood" and WallText.material(data, 6) == "stone" and WallText.material(data, 0) == "", "wall materials")
	_check(WallText.integrity(data, 5, 2) == roundi(120 * 5 * 1.35 * 1.16), "wall integrity by material, with a gate tower: %d" % WallText.integrity(data, 5, 2))
	_check(WallText.capacity(data, 4) == 120, "the walls hold 30 men a level")
	_check(not WallText.moat_water(data, 3) and WallText.moat_water(data, 4), "the moat holds water from level 4")
	_check(WallText.tower_effect(data, "ditch", 1).begins_with("A dry moat with stakes keeps off 5% of the battering and 6% of the climbers"), "moat effect: %s" % WallText.tower_effect(data, "ditch", 1))
	_check(WallText.round_text({"setup": {"wall": {"max": 720}}}, {"wallLeft": 700, "over": 0.25}).ends_with("carried 25% of them onto the walls."), "climbers in the battle story")
	_check(BattleStory.is_engine(data, "siege_tower") and BattleStory.escalade(data, "scaling_ladders") == 8.0 and not BattleStory.is_engine(data, "zealot"), "engines and climbers")
	_check(WallText.tower_effect(data, "watchtower", 2).begins_with("Warns of a horde 2 hours earlier."), "watchtower effect: %s" % WallText.tower_effect(data, "watchtower", 2))
	_check(WallText.round_text({"setup": {"wall": {"max": 720}}}, {"wallLeft": 540}) == "The walls hold: 540 of 720 left." and WallText.round_text({}, {"wallLeft": 0, "breach": true}) == "The walls are breached!", "walls in the battle story")
	# Every village's own outline keeps its plots clear of each other.
	var clear := true
	var differ := false
	for seed in range(0, 200, 7):
		var rects := VillageView.layout(Vector2(1000, 1000), 12, 12, 5, seed)
		var keys := rects.keys()
		for i in keys.size():
			for j in range(i + 1, keys.size()):
				if (rects[keys[i]] as Rect2).intersects(rects[keys[j]]):
					clear = false
					printerr("overlap at seed ", seed, ": ", keys[i], " ", keys[j])
		differ = differ or not (rects["f3"] as Rect2).is_equal_approx(VillageView.layout(Vector2(1000, 1000), 12, 12, 5, 0)["f3"])
	_check(clear, "walls and slots laid out clear of the rest, for any village")
	_check(differ, "each village has its own outline")

