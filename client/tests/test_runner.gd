extends SceneTree
## Headless test runner:
##   godot --headless --path client --import
##   godot --headless --path client --script res://tests/test_runner.gd

const VECTORS_PATH := "../data/fixtures/hex-vectors.json"
const RESOURCE_VECTORS_PATH := "../data/fixtures/resource-vectors.json"

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_test_hex_vectors()
	_test_hex_round_trip()
	_test_resource_vectors()
	_test_time_util()
	_test_rules()
	_test_training()
	_test_wave_math()
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
	var village := {"levels": {"farm": 2}, "queue": [{"building": "farm", "targetLevel": 3}, {"building": "farm", "targetLevel": 4}]}
	_check(Rules.planned_level(village, "farm") == 4, "planned level counts the queue")
	_check(Rules.planned_level(village, "quarry") == 0, "unbuilt building is level 0")


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
