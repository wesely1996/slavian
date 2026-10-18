class_name HexMap
extends Node2D
## Draws the hex map with placeholder flat colours. Redraws only when the
## map or the selection changes.

const OUTLINE_COLOR := Color(0, 0, 0, 0.25)
const SELECTION_COLOR := Color("#ffd75e")
const HOLY_CITY_COLOR := Color("#8a2b2b")
const START_SITE_COLOR := Color("#f4efe1")

@export var hex_size := 48.0

var map: MapGenerator.MapData
var selected := Vector2i.MAX


func set_map(new_map: MapGenerator.MapData) -> void:
	map = new_map
	selected = Vector2i.MAX
	queue_redraw()


func has_hex(cell: Vector2i) -> bool:
	return map != null and map.terrain.has(cell)


func local_to_hex(local_position: Vector2) -> Vector2i:
	return HexMath.from_pixel(local_position, hex_size)


func select(cell: Vector2i) -> void:
	selected = cell
	queue_redraw()


## Bounding rectangle of all hex centres, in local coordinates.
func get_bounds() -> Rect2:
	var extent := HexMath.to_pixel(Vector2i(map.radius, 0), hex_size).x
	return Rect2(-extent, -extent, extent * 2.0, extent * 2.0)


func _draw() -> void:
	if map == null:
		return
	for cell in map.terrain:
		var points := HexMath.corners(HexMath.to_pixel(cell, hex_size), hex_size)
		draw_colored_polygon(points, Terrain.color(map.terrain[cell]))
		points.append(points[0])
		draw_polyline(points, OUTLINE_COLOR, 1.5)

	draw_circle(Vector2.ZERO, hex_size * 0.45, HOLY_CITY_COLOR)
	for site in map.start_sites:
		var c := HexMath.to_pixel(site, hex_size)
		var half := hex_size * 0.25
		draw_rect(Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0), START_SITE_COLOR)

	if has_hex(selected):
		var outline := HexMath.corners(HexMath.to_pixel(selected, hex_size), hex_size * 0.92)
		outline.append(outline[0])
		draw_polyline(outline, SELECTION_COLOR, 4.0)
