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


func _test_onboarding_almanac() -> void:
	var data := {"onboarding": {"steps": [
		{"id": "build", "title": "Raise a building", "reward": {"wood": 150, "stone": 0, "grain": 100, "iron": 0}},
		{"id": "train", "title": "Train defenders", "reward": {"wood": 0, "stone": 0, "grain": 0, "iron": 50}},
	]}}
	_check(OnboardingText.next_step(data, {"onboarding": {}}).id == "build", "first step")
	_check(OnboardingText.next_step(data, {"onboarding": {"build": "x"}}).id == "train", "next step")
	_check(OnboardingText.next_step(data, {"onboarding": {"build": "x", "train": "y"}}).is_empty(), "all done")
	_check(OnboardingText.progress(data, {"onboarding": {"build": "x"}}) == "Getting started 1 of 2", "progress")
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
		if Art.texture(id) == null:
			missing.append(id)
	_check(missing.is_empty(), "every art id loads: %s" % [missing])
	for terrain in ["plains", "forest", "hills", "mountain", "swamp", "lake", "holy_city", "ocean", "dark_forest", "ice", "steppe", "hallowed"]:
		_check(Art.has("terrain/" + terrain), "terrain art for %s" % terrain)
	_check(Art.texture("no/such") == null, "missing art is null")
	_check(Art.settlement_id(1) == "settlement/village_1" and Art.settlement_id(2) == "settlement/village_1", "hall 1-2: stage 1")
	_check(Art.settlement_id(5) == "settlement/village_3" and Art.settlement_id(10) == "settlement/village_5", "hall 5: stage 3, hall 10: stage 5")
	_check(Art.settlement_id(0) == "settlement/village_1" and Art.settlement_id(14) == "settlement/village_5", "stages clamp")
