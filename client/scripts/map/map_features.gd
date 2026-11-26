class_name MapFeatures
extends Node2D
## What stands on the ground (MapGround): a faint hex grid, then each hex's
## features scattered from the art: woods of pines and oaks, peaks, hills,
## reeds, stones. Placement is seeded by the hex, so it never shifts, and
## everything is drawn back to front. Hexes with a settlement on them are
## left clear. Rebuilt only when the terrain or the settlements change.
## Drawn in horizontal strips (Strip), so what is out of view costs nothing.

const GRID := Color(0, 0, 0, 0.09)
## Rows of hexes in each strip the map is drawn in.
const STRIP_ROWS := 4
## Per terrain: [art id, how many, size in hex widths, spread (0-1 of the
## hex)] for each kind of feature on it.
const FEATURES := {
	"forest": [["feature/pine", 5, 0.42, 0.72], ["feature/oak", 3, 0.42, 0.72]],
	"dark_forest": [["feature/dark_pine", 9, 0.46, 0.75]],
	"hills": [["feature/hill", 2, 0.78, 0.5], ["feature/oak", 1, 0.36, 0.7]],
	"wooded_hills": [["feature/hill", 2, 0.78, 0.5], ["feature/pine", 3, 0.38, 0.72], ["feature/oak", 2, 0.38, 0.72]],
	"mountain": [["feature/mountain", 1, 1.15, 0.12], ["feature/peak", 2, 0.66, 0.6]],
	# A mountain city's peaks stand round it (the city itself is drawn on the map).
	"mountain_city": [["feature/peak", 2, 0.6, 0.85]],
	"swamp": [["feature/reeds", 5, 0.3, 0.75]],
	"steppe": [["feature/grass", 3, 0.26, 0.75]],
	"plains": [["feature/bush", 1, 0.26, 0.7], ["feature/grass", 2, 0.24, 0.75]],
	"ice": [["feature/ice", 2, 0.5, 0.55]],
	"hallowed": [["feature/blossom", 4, 0.3, 0.6]],
	"frozen_bog": [["feature/reeds", 3, 0.28, 0.7], ["feature/ice", 1, 0.4, 0.5]],
	"barrow_field": [["feature/hill", 3, 0.5, 0.65], ["feature/grass", 1, 0.24, 0.75]],
	"salt_flat": [["feature/grass", 1, 0.2, 0.8]],
	"kurgan_ridge": [["feature/hill", 2, 0.7, 0.5], ["feature/grass", 2, 0.26, 0.75]],
	"vineyard": [["feature/hill", 1, 0.7, 0.4], ["feature/bush", 4, 0.24, 0.7]],
	"olive_grove": [["feature/oak", 5, 0.36, 0.72]],
	"mill_meadow": [["feature/grass", 3, 0.24, 0.75], ["feature/bush", 1, 0.26, 0.7]],
	"abbey_orchard": [["feature/blossom", 3, 0.3, 0.6], ["feature/oak", 2, 0.36, 0.72]],
}

var hex_size := 48.0
## [y, art id, rect] for every feature, sorted back to front.
var _placed: Array = []
var _built_for := 0


## One horizontal strip of the map: its grid lines and the features whose
## foot stands in it. Strips are drawn top to bottom, so the whole stays back
## to front, and Godot skips the strips out of view.
class Strip extends Node2D:
	var grid := PackedVector2Array()
	var placed: Array = []

	func _draw() -> void:
		if not grid.is_empty():
			draw_multiline(grid, MapFeatures.GRID, 1.2, true)
		for entry in placed:
			var texture := Art.texture(entry[1])
			if texture != null:
				draw_texture_rect(texture, entry[2], false)


func build(terrain: Dictionary, size: float, occupied: Dictionary) -> void:
	var key := hash([terrain, size, occupied.keys()])
	if key == _built_for:
		return
	_built_for = key
	hex_size = size
	_placed = []
	for cell in terrain:
		if occupied.has(cell):
			continue
		_place(cell, String(terrain[cell]))
	_placed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	_rebuild_strips(terrain.keys())


## How tall a strip is: a few rows of hexes.
func _strip_height() -> float:
	return hex_size * 1.5 * STRIP_ROWS


func _strip_of(y: float) -> int:
	return floori(y / _strip_height())


func _rebuild_strips(cells: Array) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var strips := {}
	# Each edge of the grid once: an edge belongs to the hex that has it
	# among its first three sides, or to either if only one is on the map.
	var on_map := {}
	for cell in cells:
		on_map[cell] = true
	for cell in cells:
		var center := HexMath.to_pixel(cell, hex_size)
		var corners := HexMath.corners(center, hex_size)
		for k in 6:
			var a: Vector2 = corners[k]
			var b: Vector2 = corners[(k + 1) % 6]
			var neighbour := _across(cell, center, (a + b) / 2.0)
			if on_map.has(neighbour) and _owns(neighbour, cell):
				continue
			var strip := _strip(strips, _strip_of(minf(a.y, b.y)))
			strip.grid.append(a)
			strip.grid.append(b)
	for entry in _placed:
		_strip(strips, _strip_of(entry[0])).placed.append(entry)
	var rows := strips.keys()
	rows.sort()
	for row in rows:
		add_child(strips[row])
		strips[row].queue_redraw()


static func _strip(strips: Dictionary, row: int) -> Strip:
	if not strips.has(row):
		var strip := Strip.new()
		strip.show_behind_parent = true
		strips[row] = strip
	return strips[row]


## The hex on the other side of the edge whose midpoint is `mid`.
func _across(cell: Vector2i, center: Vector2, mid: Vector2) -> Vector2i:
	var best := cell
	var best_d := INF
	for n in HexMath.neighbors(cell):
		var d := HexMath.to_pixel(n, hex_size).distance_squared_to(mid)
		if d < best_d:
			best_d = d
			best = n
	return best


## Which of two neighbouring hexes draws the edge between them: the one
## that comes first (by row, then column).
static func _owns(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)


func _place(cell: Vector2i, terrain: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(cell) * 2654435761
	var center := HexMath.to_pixel(cell, hex_size)
	var width := sqrt(3.0) * hex_size
	for kind in FEATURES.get(terrain, []):
		var id: String = kind[0]
		if not Art.has(id):
			continue
		for i in int(kind[1]):
			# Spread over the hex, a little more across than up and down.
			var angle := rng.randf() * TAU
			var reach := sqrt(rng.randf()) * float(kind[3]) * hex_size * 0.8
			var foot := center + Vector2(cos(angle), sin(angle) * 0.8) * reach
			var texture := Art.texture(id)
			var w := width * float(kind[2]) * rng.randf_range(0.85, 1.15)
			var h := w * float(texture.get_height()) / float(texture.get_width())
			# The art's foot sits at the bottom centre of its picture.
			var rect := Rect2(foot - Vector2(w / 2.0, h * 0.92), Vector2(w, h))
			if rng.randf() < 0.5:
				rect = Rect2(rect.position + Vector2(w, 0), Vector2(-w, h))
			_placed.append([foot.y, id, rect])
