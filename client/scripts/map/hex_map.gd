class_name HexMap
extends Node2D
## Draws the current world's map (Game.terrain) and villages with
## placeholder flat colours. Redraws only when something changes.

const OUTLINE_COLOR := Color(0, 0, 0, 0.25)
const SELECTION_COLOR := Color("#ffd75e")
const HOLY_CITY_COLOR := Color("#8a2b2b")
const MY_VILLAGE_COLOR := Color("#ffd75e")
const ALLY_VILLAGE_COLOR := Color("#f4efe1")
const VILLAGE_OUTLINE_COLOR := Color("#2b2118")

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

	if has_hex(selected):
		var outline := HexMath.corners(HexMath.to_pixel(selected, hex_size), hex_size * 0.92)
		outline.append(outline[0])
		draw_polyline(outline, SELECTION_COLOR, 4.0)
