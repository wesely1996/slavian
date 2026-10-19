class_name MapFeatures
extends Node2D
## What stands on the ground (MapGround): a faint hex grid, then each hex's
## features scattered from the art: woods of pines and oaks, peaks, hills,
## reeds, stones. Placement is seeded by the hex, so it never shifts, and
## everything is drawn back to front. Hexes with a settlement on them are
## left clear. Rebuilt only when the terrain or the settlements change.

const GRID := Color(0, 0, 0, 0.09)
## Per terrain: [art id, how many, size in hex widths, spread (0-1 of the
## hex)] for each kind of feature on it.
const FEATURES := {
	"forest": [["feature/pine", 5, 0.42, 0.72], ["feature/oak", 3, 0.42, 0.72]],
	"dark_forest": [["feature/dark_pine", 9, 0.46, 0.75]],
	"hills": [["feature/hill", 2, 0.78, 0.5], ["feature/oak", 1, 0.36, 0.7]],
	"mountain": [["feature/mountain", 1, 1.15, 0.12], ["feature/peak", 2, 0.66, 0.6]],
	"swamp": [["feature/reeds", 5, 0.3, 0.75]],
	"steppe": [["feature/grass", 3, 0.26, 0.75]],
	"plains": [["feature/bush", 1, 0.26, 0.7], ["feature/grass", 2, 0.24, 0.75]],
	"ice": [["feature/ice", 2, 0.5, 0.55]],
	"hallowed": [["feature/blossom", 4, 0.3, 0.6]],
}

var hex_size := 48.0
## [y, art id, rect] for every feature, sorted back to front.
var _placed: Array = []
var _cells: Array = []
var _built_for := 0


func build(terrain: Dictionary, size: float, occupied: Dictionary) -> void:
	var key := hash([terrain, size, occupied.keys()])
	if key == _built_for:
		return
	_built_for = key
	hex_size = size
	_cells = terrain.keys()
	_placed = []
	for cell in terrain:
		if occupied.has(cell):
			continue
		_place(cell, String(terrain[cell]))
	_placed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	queue_redraw()


func _draw() -> void:
	for cell in _cells:
		var outline := HexMath.corners(HexMath.to_pixel(cell, hex_size), hex_size)
		outline.append(outline[0])
		draw_polyline(outline, GRID, 1.2, true)
	for entry in _placed:
		var texture := Art.texture(entry[1])
		if texture != null:
			draw_texture_rect(texture, entry[2], false)


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
