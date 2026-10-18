class_name HexMap
extends Node2D
## Draws the current world's map (Game.terrain), villages and enemy hordes
## with placeholder flat colours. Redraws when something changes, and on
## every UI tick while a horde is on the move.

const OUTLINE_COLOR := Color(0, 0, 0, 0.25)
const SELECTION_COLOR := Color("#ffd75e")
const HOLY_CITY_COLOR := Color("#8a2b2b")
const MY_VILLAGE_COLOR := Color("#ffd75e")
const ALLY_VILLAGE_COLOR := Color("#f4efe1")
const VILLAGE_OUTLINE_COLOR := Color("#2b2118")
const HORDE_COLOR := Color("#c8372d")
const HORDE_PATH_COLOR := Color(0.78, 0.22, 0.18, 0.6)
const RUINS_COLOR := Color("#6d655a")
const CARAVAN_COLOR := Color("#c99a5b")
const SETTLERS_COLOR := Color("#e8e2d0")

@export var hex_size := 48.0

var radius := 0
var selected := Vector2i.MAX


func refresh() -> void:
	var map: Variant = Game.world.get("map")
	radius = int(map.radius) if map is Dictionary else 0
	queue_redraw()


func has_hex(cell: Vector2i) -> bool:
	return Game.terrain.has(cell)


func local_to_hex(local_position: Vector2) -> Vector2i:
	return HexMath.from_pixel(local_position, hex_size)


func hex_to_local(cell: Vector2i) -> Vector2:
	return HexMath.to_pixel(cell, hex_size)


func select(cell: Vector2i) -> void:
	selected = cell
	queue_redraw()


## Bounding rectangle of all hex centres, in local coordinates.
func get_bounds() -> Rect2:
	var extent := HexMath.to_pixel(Vector2i(radius, 0), hex_size).x
	return Rect2(-extent, -extent, extent * 2.0, extent * 2.0)


func _draw() -> void:
	for cell in Game.terrain:
		var points := HexMath.corners(HexMath.to_pixel(cell, hex_size), hex_size)
		draw_colored_polygon(points, Terrain.color(Game.terrain[cell]))
		points.append(points[0])
		draw_polyline(points, OUTLINE_COLOR, 1.5)

	if Game.terrain.has(Vector2i.ZERO):
		draw_circle(Vector2.ZERO, hex_size * 0.45, HOLY_CITY_COLOR)
	for village in Game.villages.values():
		var c := HexMath.to_pixel(Vector2i(int(village.q), int(village.r)), hex_size)
		var half := hex_size * 0.3
		var rect := Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0)
		draw_rect(rect, MY_VILLAGE_COLOR if Game.is_mine(village) else ALLY_VILLAGE_COLOR)
		draw_rect(rect, VILLAGE_OUTLINE_COLOR, false, 2.0)
		for plot in Rules.outpost_plots(village):
			_draw_outpost(Rules.outpost_hex(plot), int(village.plots[plot].level), Game.is_mine(village))

	var now := Game.server_now()
	for caravan in Game.caravans:
		var p := CaravanMath.progress(caravan, now)
		if not p.is_empty():
			var pos := HexMath.to_pixel(p.from, hex_size).lerp(HexMath.to_pixel(p.to, hex_size), p.t)
			draw_circle(pos, hex_size * 0.2, CARAVAN_COLOR)
			draw_arc(pos, hex_size * 0.2, 0.0, TAU, 16, VILLAGE_OUTLINE_COLOR, 2.0)
	for expedition in Game.expeditions:
		var p := CaravanMath.progress(expedition, now)
		if not p.is_empty():
			var pos := HexMath.to_pixel(p.from, hex_size).lerp(HexMath.to_pixel(p.to, hex_size), p.t)
			var r := hex_size * 0.22
			var tri := PackedVector2Array([pos + Vector2(0, -r), pos + Vector2(r, r * 0.8), pos + Vector2(-r, r * 0.8)])
			draw_colored_polygon(tri, SETTLERS_COLOR)
			tri.append(tri[0])
			draw_polyline(tri, VILLAGE_OUTLINE_COLOR, 2.0)
	for wave in WaveMath.visible_waves(Game.waves):
		_draw_horde(wave, now)

	if has_hex(selected):
		var outline := HexMath.corners(HexMath.to_pixel(selected, hex_size), hex_size * 0.92)
		outline.append(outline[0])
		draw_polyline(outline, SELECTION_COLOR, 4.0)


## A small watchtower: a diamond in the owner's colour, grey while in ruins
## or under construction.
func _draw_outpost(cell: Vector2i, level: int, mine: bool) -> void:
	var c := HexMath.to_pixel(cell, hex_size)
	var r := hex_size * 0.26
	var diamond := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
	var fill := RUINS_COLOR if level <= 0 else (MY_VILLAGE_COLOR if mine else ALLY_VILLAGE_COLOR)
	draw_colored_polygon(diamond, fill)
	diamond.append(diamond[0])
	draw_polyline(diamond, VILLAGE_OUTLINE_COLOR, 2.0)


func has_moving_hordes() -> bool:
	return Game.waves.any(func(w: Dictionary) -> bool: return w.status == "marching") \
		or Game.caravans.any(func(c: Dictionary) -> bool: return c.status != "done") \
		or Game.expeditions.any(func(e: Dictionary) -> bool: return e.status in ["outbound", "returning"])


func _draw_horde(wave: Dictionary, now: float) -> void:
	var p := WaveMath.progress(wave, now)
	if p.is_empty():
		return
	var pos := HexMath.to_pixel(p.from, hex_size).lerp(HexMath.to_pixel(p.to, hex_size), p.t)
	if wave.status == "marching":
		# The road still ahead, from the horde to its target.
		var trail := PackedVector2Array([pos])
		var ahead := false
		for step in wave.path:
			var cell := Vector2i(int(step[0]), int(step[1]))
			ahead = ahead or cell == p.to
			if ahead:
				trail.append(HexMath.to_pixel(cell, hex_size))
		if trail.size() >= 2:
			draw_polyline(trail, HORDE_PATH_COLOR, 5.0)
	else:
		# Camped at the gates: sit beside the village so both stay visible.
		pos += Vector2(hex_size * 0.42, -hex_size * 0.42)
	draw_circle(pos, hex_size * 0.34, HORDE_COLOR)
	draw_arc(pos, hex_size * 0.34, 0.0, TAU, 24, VILLAGE_OUTLINE_COLOR, 2.0)
