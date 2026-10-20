class_name PlatedWood
extends StyleBox
## Walnut with gold metal plating (docs/art-style.md, "The interface"): the
## wood grain (art id ui/wood) tiled under a soft top light and bottom shade,
## gold rails along the chosen edges with rivets, and chamfered gold plates
## at the corners, each with a cut lozenge (the sown-field sign of Slavic
## embroidery). All lit from the upper left, like the rest of the art, and
## drawn as vectors over the one texture, so it is sharp at any size.

## The plate's gold, from its lit face to its shade.
const GOLD := [Color("#fff4c2"), Color("#ecc457"), Color("#b8862a"), Color("#7a5512")]
const EDGE := Color("#2a1a08")
## The wood's colour where the texture is missing.
const WOOD := Color("#3a2719")

## Edges with a gold rail: any of SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM.
var rails: Array[int] = [SIDE_BOTTOM]
## Corners with a plate: any of CORNER_TOP_LEFT... (Godot's Corner enum).
var plates: Array[int] = [CORNER_TOP_LEFT, CORNER_TOP_RIGHT, CORNER_BOTTOM_LEFT, CORNER_BOTTOM_RIGHT]
var rail_width := 5.0
var plate_size := 30.0
## Rivets along the rails, this far apart (0: none).
var rivet_every := 140.0
## Lighter (above 0) or darker (below) wood, for a button under the finger
## or pressed.
var lift := 0.0

var _grain: Texture2D


func _init(padding := 14.0) -> void:
	_grain = Art.texture("ui/wood")
	set_content_margin_all(padding)


func _draw(to: RID, rect: Rect2) -> void:
	var rs := RenderingServer
	# The wood: the grain tiled from the top left, then a light from above
	# and a shade below.
	rs.canvas_item_add_rect(to, rect, WOOD)
	if _grain != null:
		var tile := Vector2(_grain.get_size()) * 0.5
		var y := rect.position.y
		while y < rect.end.y:
			var x := rect.position.x
			var h := minf(tile.y, rect.end.y - y)
			while x < rect.end.x:
				var w := minf(tile.x, rect.end.x - x)
				var src := Rect2(Vector2.ZERO, Vector2(w, h) * 2.0)
				rs.canvas_item_add_texture_rect_region(to, Rect2(x, y, w, h), _grain.get_rid(), src)
				x += w
			y += h
	if lift > 0.0:
		rs.canvas_item_add_rect(to, rect, Color(1, 0.9, 0.7, lift))
	elif lift < 0.0:
		rs.canvas_item_add_rect(to, rect, Color(0, 0, 0, -lift))
	_gradient(to, rect, Color(1, 0.92, 0.78, 0.10), Color(0, 0, 0, 0.0), 0.0, 0.45)
	_gradient(to, rect, Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.28), 0.55, 1.0)
	# The rails.
	for side in rails:
		_rail(to, rect, side)
	# The corner plates.
	for corner in plates:
		_plate(to, rect, corner)


## A band across the whole width from `from` to `to` (shares of the height),
## fading between the two colours.
func _gradient(to: RID, rect: Rect2, a: Color, b: Color, from: float, until: float) -> void:
	var y0 := rect.position.y + rect.size.y * from
	var y1 := rect.position.y + rect.size.y * until
	var points := PackedVector2Array([Vector2(rect.position.x, y0), Vector2(rect.end.x, y0), Vector2(rect.end.x, y1), Vector2(rect.position.x, y1)])
	RenderingServer.canvas_item_add_polygon(to, points, PackedColorArray([a, a, b, b]))


## A gold rail along `side`: lit on its outer half, shaded on its inner,
## with a dark line where it meets the wood, and rivets.
func _rail(to: RID, rect: Rect2, side: int) -> void:
	var w := rail_width
	var r: Rect2
	match side:
		SIDE_TOP:
			r = Rect2(rect.position.x, rect.position.y, rect.size.x, w)
		SIDE_BOTTOM:
			r = Rect2(rect.position.x, rect.end.y - w, rect.size.x, w)
		SIDE_LEFT:
			r = Rect2(rect.position.x, rect.position.y, w, rect.size.y)
		_:
			r = Rect2(rect.end.x - w, rect.position.y, w, rect.size.y)
	var across_y := side == SIDE_TOP or side == SIDE_BOTTOM
	RenderingServer.canvas_item_add_rect(to, r.grow(1.0), EDGE)
	# Three bands of the plate's gold across the rail, lit from the top left.
	var bands := 3
	for i in bands:
		var t0 := float(i) / bands
		var t1 := float(i + 1) / bands
		var a: Color = GOLD[i]
		var b: Color = GOLD[i + 1]
		var points: PackedVector2Array
		if across_y:
			var y0 := r.position.y + r.size.y * t0
			var y1 := r.position.y + r.size.y * t1
			points = PackedVector2Array([Vector2(r.position.x, y0), Vector2(r.end.x, y0), Vector2(r.end.x, y1), Vector2(r.position.x, y1)])
		else:
			var x0 := r.position.x + r.size.x * t0
			var x1 := r.position.x + r.size.x * t1
			points = PackedVector2Array([Vector2(x0, r.position.y), Vector2(x0, r.end.y), Vector2(x1, r.end.y), Vector2(x1, r.position.y)])
		RenderingServer.canvas_item_add_polygon(to, points, PackedColorArray([a, a, b, b]))
	if rivet_every <= 0.0:
		return
	var length := r.size.x if across_y else r.size.y
	var count := int(length / rivet_every)
	for i in range(1, count + 1):
		var t := float(i) / (count + 1)
		var at := r.get_center()
		if across_y:
			at.x = r.position.x + length * t
		else:
			at.y = r.position.y + length * t
		_rivet(to, at, w * 0.9)


## A domed rivet: a dark rim, gold, and a highlight towards the upper left.
func _rivet(to: RID, at: Vector2, r: float) -> void:
	RenderingServer.canvas_item_add_circle(to, at + Vector2(0.6, 0.8), r + 0.8, Color(0, 0, 0, 0.45))
	RenderingServer.canvas_item_add_circle(to, at, r, GOLD[2])
	RenderingServer.canvas_item_add_circle(to, at - Vector2(r, r) * 0.18, r * 0.72, GOLD[1])
	RenderingServer.canvas_item_add_circle(to, at - Vector2(r, r) * 0.35, r * 0.3, GOLD[0])


## A chamfered gold plate over `corner`, a cut lozenge in it and a rivet.
func _plate(to: RID, rect: Rect2, corner: int) -> void:
	var s := minf(plate_size, minf(rect.size.x, rect.size.y) * 0.5)
	if s < 6.0:
		return
	# The plate in the top-left corner's frame, then mirrored into place.
	var sx := 1.0 if corner == CORNER_TOP_LEFT or corner == CORNER_BOTTOM_LEFT else -1.0
	var sy := 1.0 if corner == CORNER_TOP_LEFT or corner == CORNER_TOP_RIGHT else -1.0
	var origin := Vector2(rect.position.x if sx > 0.0 else rect.end.x, rect.position.y if sy > 0.0 else rect.end.y)
	var shape: Array[Vector2] = [Vector2(0, 0), Vector2(s, 0), Vector2(s, s * 0.32), Vector2(s * 0.32, s), Vector2(0, s)]
	var outline := PackedVector2Array()
	var face := PackedVector2Array()
	var colors := PackedColorArray()
	for p in shape:
		var v := origin + Vector2(p.x * sx, p.y * sy)
		outline.append(v)
	# The face, inset by a pixel, its gold by how far each point lies along
	# the light (from the screen's upper left to its lower right).
	var light := Vector2(1, 1).normalized()
	var lit_from := origin + Vector2(minf(0.0, s * sx), minf(0.0, s * sy))
	for p in shape:
		var inset: Vector2 = p * (1.0 - 2.0 / s) + Vector2(1, 1)
		var v := origin + Vector2(inset.x * sx, inset.y * sy)
		face.append(v)
		var t := clampf((v - lit_from).dot(light) / (s * 1.414), 0.0, 1.0)
		colors.append(_gold_at(t))
	RenderingServer.canvas_item_add_polygon(to, _shadowed(outline, Vector2(1.2, 1.6)), PackedColorArray([Color(0, 0, 0, 0.4)]))
	RenderingServer.canvas_item_add_polygon(to, outline, PackedColorArray([EDGE]))
	RenderingServer.canvas_item_add_polygon(to, face, colors)
	# The cut lozenge and its gold seed.
	var c := origin + Vector2(s * 0.36 * sx, s * 0.36 * sy)
	var d := s * 0.17
	RenderingServer.canvas_item_add_polygon(to, PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)]), PackedColorArray([EDGE]))
	var e := d * 0.45
	RenderingServer.canvas_item_add_polygon(to, PackedVector2Array([c + Vector2(0, -e), c + Vector2(e, 0), c + Vector2(0, e), c + Vector2(-e, 0)]),
		PackedColorArray([GOLD[0], GOLD[1], GOLD[3], GOLD[2]]))
	_rivet(to, origin + Vector2(s * 0.74 * sx, s * 0.14 * sy), maxf(1.6, s * 0.07))
	_rivet(to, origin + Vector2(s * 0.14 * sx, s * 0.74 * sy), maxf(1.6, s * 0.07))


static func _gold_at(t: float) -> Color:
	var f := clampf(t, 0.0, 1.0) * 3.0
	var i := mini(int(f), 2)
	return (GOLD[i] as Color).lerp(GOLD[i + 1], f - i)


static func _shadowed(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(p + offset)
	return out
