class_name MapHighlights
extends Node2D
## Hexes that matter, made easy to spot: a glow under the icon, strongest at
## the centre and gone by three-quarters of the way out, and the hex's own
## border in the same colour, twice as thick as the grid. Red: enemy camps;
## blue: ancient sites still to explore; gold: daily events still open
## (captives, a ritual, a shipyard), which pulse. A little stronger when
## zoomed out, where the icons are small. Drawn on its own layer, under the
## roads and icons, so the pulse doesn't redraw the whole map.

const CAMP := Color("#d0453a")
const SITE := Color("#4f9be0")
const EVENT := Color("#f2c041")
## The grid's line (MapFeatures) is 1.2 wide; a highlighted border twice that.
const BORDER_WIDTH := 2.4
const GLOW_ALPHA := 0.8
const GLOW_REACH := 0.78
const SEGMENTS := 28

var hex_size := 48.0
## [cell, colour, pulses] for each highlighted hex.
var _marks: Array = []
var _zoom := 1.0


func show_marks(marks: Array, size: float) -> void:
	hex_size = size
	if marks == _marks:
		return
	_marks = marks
	set_process(not marks.is_empty())
	queue_redraw()


## What to highlight, from the game's state.
static func marks_from(camps: Array, sites: Array, shipyards: Array) -> Array:
	var marks: Array = []
	for camp in camps:
		var event: bool = camp.get("kind") in ["captives", "cultists"]
		marks.append([Vector2i(int(camp.q), int(camp.r)), EVENT if event else CAMP, event])
	for site in sites:
		if site.get("status") == "unexplored":
			marks.append([Vector2i(int(site.q), int(site.r)), SITE, false])
	for yard in shipyards:
		if yard.get("status") in ["open", "building"]:
			marks.append([Vector2i(int(yard.q), int(yard.r)), EVENT, true])
	return marks


func _process(_delta: float) -> void:
	var zoom := get_canvas_transform().get_scale().x
	var pulsing := _marks.any(func(m: Array) -> bool: return m[2])
	if pulsing or absf(zoom - _zoom) > 0.02:
		_zoom = zoom
		queue_redraw()


## 1 at normal zoom, up to 1.6 zoomed far out.
func _boost() -> float:
	return clampf(1.0 + (1.0 - _zoom) * 0.9, 1.0, 1.6)


func _draw() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var boost := _boost()
	for mark in _marks:
		var strength := boost
		if mark[2]:
			# Brighter and dimmer about once every two seconds.
			strength *= 0.6 + 0.4 * (0.5 + 0.5 * sin(t * PI))
		_draw_mark(mark[0], mark[1], strength)


func _draw_mark(cell: Vector2i, color: Color, strength: float) -> void:
	var center := HexMath.to_pixel(cell, hex_size)
	var reach := hex_size * GLOW_REACH
	var glow := color.lightened(0.25)
	var core := Color(glow, clampf(GLOW_ALPHA * strength, 0.0, 0.95))
	var mid := Color(glow, core.a * 0.6)
	var clear := Color(glow, 0.0)
	# Strongest at the centre, 60% at half way, gone at the reach.
	for i in SEGMENTS:
		var a0 := TAU * i / SEGMENTS
		var a1 := TAU * (i + 1) / SEGMENTS
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		draw_polygon(PackedVector2Array([center, center + d0 * reach * 0.5, center + d1 * reach * 0.5]), PackedColorArray([core, mid, mid]))
		draw_polygon(PackedVector2Array([center + d0 * reach * 0.5, center + d0 * reach, center + d1 * reach, center + d1 * reach * 0.5]), PackedColorArray([mid, clear, clear, mid]))
	# The border, just inside the hex so a neighbour's shows beside it.
	var width := BORDER_WIDTH * minf(strength, 1.6) if strength > 1.0 else BORDER_WIDTH
	var outline := HexMath.corners(center, hex_size - width)
	outline.append(outline[0])
	draw_polyline(outline, Color(color, clampf(0.55 + 0.45 * minf(strength, 1.0), 0.0, 1.0)), width, true)
