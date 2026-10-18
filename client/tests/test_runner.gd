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
	_test_server_url()
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
	_check(Rules.queue_limit(data, 1) == 2 and Rules.queue_limit(data, 3) == 3 and Rules.queue_limit(data, 9) == 5, "queue grows every 3 Hall levels")
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
	_check(rects.size() == 24, "a rect per plot")
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


func _test_server_url() -> void:
	var session := load("res://scripts/net/session.gd")
	_check(session.normalize_url(" 192.168.1.10:8080/ ") == "http://192.168.1.10:8080", "LAN IP gets http")
	_check(session.normalize_url("localhost:8080") == "http://localhost:8080", "localhost gets http")
	_check(session.normalize_url("affects-taken-marble-serial.trycloudflare.com") == "https://affects-taken-marble-serial.trycloudflare.com", "domain gets https")
	_check(session.normalize_url("http://example.com") == "http://example.com", "explicit scheme kept")


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
