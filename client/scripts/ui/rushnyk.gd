class_name Rushnyk
extends Control
## The one ornament of the interface: a strip of cross-stitch embroidery as
## on a rushnyk, the embroidered towel of Slavic houses, under the top band.
## A repeat of madder lozenges with ink hooks, on flax, drawn to the strip's
## height.

## Stitches across one repeat of the pattern (an odd number, so it has a
## middle).
const REPEAT := 13
## The pattern's rows of a repeat: "x" madder, "o" ink, "." flax.
const ROWS := [
	"......x......",
	".o...xxx...o.",
	"oo..xx.xx..oo",
	"...xx.o.xx...",
	"oo..xx.xx..oo",
	".o...xxx...o.",
	"......x......",
]


func _ready() -> void:
	custom_minimum_size.y = 28
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var rows := ROWS.size()
	# Edges of ink, the stitches between.
	var edge := maxf(1.0, size.y * 0.08)
	draw_rect(Rect2(Vector2.ZERO, size), UiTheme.FLAX)
	draw_rect(Rect2(0, 0, size.x, edge), UiTheme.WOOD_DEEP)
	draw_rect(Rect2(0, size.y - edge, size.x, edge), UiTheme.WOOD_DEEP)
	var cell := (size.y - edge * 2.0) / rows
	var repeats := ceili(size.x / (cell * REPEAT)) + 1
	# Centre a repeat on the middle, so the strip is symmetrical.
	var start := size.x / 2.0 - cell * REPEAT * (repeats / 2 + 0.5)
	for r in repeats:
		for y in rows:
			var row: String = ROWS[y]
			for x in REPEAT:
				var c := row[x]
				if c == ".":
					continue
				var at := Vector2(start + (r * REPEAT + x) * cell, edge + y * cell)
				_stitch(Rect2(at, Vector2(cell, cell)), UiTheme.MADDER if c == "x" else UiTheme.INK)


## One cross stitch: two strokes corner to corner.
func _stitch(rect: Rect2, color: Color) -> void:
	var r := rect.grow(-rect.size.x * 0.12)
	var width := maxf(1.0, rect.size.x * 0.32)
	draw_line(r.position, r.end, color, width, true)
	draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), color, width, true)
