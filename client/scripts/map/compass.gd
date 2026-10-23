class_name Compass
extends Control
## A small see-through compass rose over the map's corner: north up, east to
## the right, as on any map.

const INK := Color(0.16, 0.12, 0.09, 0.55)
const PAPER := Color(0.95, 0.92, 0.84, 0.35)
const NORTH := Color(0.66, 0.2, 0.17, 0.75)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(92, 92)
	size = custom_minimum_size


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 2.0
	draw_circle(c, r, PAPER)
	draw_arc(c, r, 0.0, TAU, 40, INK, 1.5, true)
	draw_arc(c, r * 0.62, 0.0, TAU, 32, Color(INK, 0.3), 1.0, true)
	# The rose: a long point to each side, north's in madder.
	for i in 4:
		var way := Vector2.UP.rotated(i * PI / 2.0)
		var side := way.orthogonal() * r * 0.13
		var point := PackedVector2Array([c + way * r * 0.6, c + side, c - side])
		draw_colored_polygon(point, NORTH if i == 0 else INK)
	var font := get_theme_default_font()
	var px := int(r * 0.34)
	var points := [[UI.t("N"), Vector2.UP], [UI.t("E"), Vector2.RIGHT], [UI.t("S"), Vector2.DOWN], [UI.t("W"), Vector2.LEFT]]
	for i in points.size():
		var letter: String = points[i][0]
		var at: Vector2 = c + points[i][1] * r * 0.8
		var width := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		draw_string(font, at + Vector2(-width / 2.0, px * 0.36), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, px, NORTH if i == 0 else INK)
