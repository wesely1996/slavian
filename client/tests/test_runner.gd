extends SceneTree
## Headless test runner:
##   godot --headless --path client --import
##   godot --headless --path client --script res://tests/test_runner.gd

const VECTORS_PATH := "../data/fixtures/hex-vectors.json"

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_test_hex_vectors()
	_test_hex_round_trip()
	_test_map_generator()
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


func _test_map_generator() -> void:
	for players in range(1, 7):
		var map := MapGenerator.generate(42, players)
		var radius := MapGenerator.radius_for(players)
		_check(map.terrain.size() == HexMath.spiral(Vector2i.ZERO, radius).size(), "map %dp covers radius %d" % [players, radius])
		_check(map.terrain[Vector2i.ZERO] == Terrain.Type.HOLY_CITY, "map %dp has the Holy City at the centre" % players)
		_check(map.start_sites.size() == players, "map %dp has one start per player" % players)
		var unique := {}
		for site in map.start_sites:
			unique[site] = true
			_check(HexMath.distance(site, Vector2i.ZERO) == MapGenerator.START_RING, "start %s on ring 2" % site)
			_check(map.terrain[site] in [Terrain.Type.PLAINS, Terrain.Type.FOREST, Terrain.Type.HILLS], "start %s settleable" % site)
		_check(unique.size() == players, "map %dp starts are distinct" % players)
		# Every edge hex of an inactive front is ocean; active fronts have spawn terrain.
		for cell in HexMath.ring(Vector2i.ZERO, radius):
			var front := MapGenerator.front_of(cell)
			var is_ocean := map.terrain[cell] == Terrain.Type.OCEAN
			_check(is_ocean == (front not in map.active_fronts), "map %dp edge %s matches front activity" % [players, cell])

	_check(MapGenerator.active_fronts_for(1) == [MapGenerator.Front.NORTH, MapGenerator.Front.SOUTH], "solo fronts are N+S")
	_check(MapGenerator.active_fronts_for(2).size() == 3 and MapGenerator.Front.EAST in MapGenerator.active_fronts_for(2), "2 players add East")
	_check(MapGenerator.active_fronts_for(3).size() == 4, "3+ players face all four fronts")

	var a := MapGenerator.generate(7, 4)
	var b := MapGenerator.generate(7, 4)
	_check(a.terrain == b.terrain, "generation is deterministic for a seed")
