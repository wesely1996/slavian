class_name Parchment
extends StyleBox
## The sheets' parchment: the paper (art ui/parchment, a seamless tile)
## repeated inside a torn outline, the edge darkened and singed the way old
## paper ages. The tears depend only on the sheet's size, so a sheet keeps
## its edge while it is redrawn.

## How far the tears bite into the sheet, and how wide the aged band is.
const TEAR := 7.0
const AGED := 26.0
const RIM := Color(0.36, 0.22, 0.1, 0.85)
const AGE := Color(0.45, 0.3, 0.12)

var alpha := 1.0


func _init(padding := 22.0, alpha_ := 1.0) -> void:
	alpha = alpha_
	set_content_margin_all(padding + TEAR)


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var outline := _outline(rect)
	var paper := Art.texture("ui/parchment")
	# A soft shadow under the sheet.
	var shadow := PackedVector2Array()
	for p in outline:
		shadow.append(p + Vector2(0, 3))
	_fill(to_canvas_item, shadow, rect.get_center() + Vector2(0, 3), Color(0, 0, 0, 0.25 * alpha), null)
	if paper != null:
		RenderingServer.canvas_item_set_default_texture_repeat(to_canvas_item, RenderingServer.CANVAS_ITEM_TEXTURE_REPEAT_ENABLED)
	_fill(to_canvas_item, outline, rect.get_center(), Color(1, 1, 1, alpha) if paper != null else Color(UiTheme.FLAX, alpha), paper)
	# The aged band: the edge darkening towards the tear.
	var center := rect.get_center()
	var steps := 10
	for i in steps:
		var inset := AGED * float(i) / steps
		var band := PackedVector2Array()
		for p in outline:
			band.append(p + (center - p).normalized() * inset * _inset_scale(p, rect))
		band.append(band[0])
		var strength := pow(1.0 - float(i) / steps, 2.2) * 0.16 * alpha
		RenderingServer.canvas_item_add_polyline(to_canvas_item, band, PackedColorArray([Color(AGE, strength)]), AGED / steps + 0.5, true)
	# The singed rim.
	var rim := outline.duplicate()
	rim.append(outline[0])
	RenderingServer.canvas_item_add_polyline(to_canvas_item, rim, PackedColorArray([Color(RIM, RIM.a * alpha)]), 1.6, true)


## Fills the outline as a fan of triangles from `center` (the torn sheet is
## seen whole from its middle, so the fan never folds), tiling `paper` over it.
func _fill(item: RID, outline: PackedVector2Array, center: Vector2, color: Color, paper: Texture2D) -> void:
	var points := PackedVector2Array([center])
	points.append_array(outline)
	var indices := PackedInt32Array()
	var n := outline.size()
	for i in n:
		indices.append_array([0, 1 + i, 1 + (i + 1) % n])
	var uvs := PackedVector2Array()
	if paper != null:
		var tile := Vector2(paper.get_size())
		for p in points:
			uvs.append(p / tile)
	RenderingServer.canvas_item_add_triangle_array(item, indices, points, PackedColorArray([color]), uvs, PackedInt32Array(), PackedFloat32Array(), paper.get_rid() if paper != null else RID())


## Corners move inwards along the diagonal; keep the aged band even there.
func _inset_scale(p: Vector2, rect: Rect2) -> float:
	var to_center := (rect.get_center() - p).normalized()
	return 1.0 / maxf(0.5, maxf(absf(to_center.x), absf(to_center.y)))


## The torn edge, clockwise from the top left: small bites everywhere, a few
## deeper tears, the same for the same size.
func _outline(rect: Rect2) -> PackedVector2Array:
	var points := PackedVector2Array()
	var r := rect.grow(-TEAR * 0.25)
	var seed := int(r.size.x) * 7919 + int(r.size.y) * 104729
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for side in 4:
		var a: Vector2 = corners[side]
		var b: Vector2 = corners[(side + 1) % 4]
		var inward := (b - a).normalized().rotated(PI / 2.0)
		var length := a.distance_to(b)
		var count := maxi(2, int(length / 9.0))
		for i in count:
			var t := float(i) / count
			var h := _hash(seed + side * 7177 + i)
			var bite := TEAR * (0.25 + 0.55 * h)
			# Now and then a deeper tear, a few points wide.
			if _hash(seed + side * 31 + i / 3 * 977) > 0.93:
				bite += TEAR * 1.1 * sin(PI * float(i % 3 + 1) / 4.0)
			points.append(a.lerp(b, t) + inward * bite)
	return points


## A number from 0 to 1 for an integer, always the same for the same one.
static func _hash(n: int) -> float:
	var x := (n * 374761393 + 668265263) & 0x7fffffff
	x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff
	return float(x & 0xffff) / 65535.0
