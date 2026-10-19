class_name FrameStyle
extends StyleBox
## A nine-slice frame from the art: the corners keep their size, the edges
## and middle stretch. `margin` is the corner size in the art's own units
## (`design_size`, the SVG's size), so art imported at 2x stays sharp and
## replacement art of any resolution lines up.

var texture: Texture2D
var design_size := Vector2.ONE
var margin := 0.0


func _init(texture_: Texture2D = null, design_size_ := Vector2.ONE, margin_ := 0.0, content := 0.0) -> void:
	texture = texture_
	design_size = design_size_
	margin = margin_
	set_content_margin_all(content)


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if texture == null:
		return
	var tex_size := Vector2(texture.get_size())
	var m := minf(margin, minf(rect.size.x, rect.size.y) / 2.0)
	var src := margin * tex_size.x / design_size.x
	var xs := [rect.position.x, rect.position.x + m, rect.end.x - m, rect.end.x]
	var ys := [rect.position.y, rect.position.y + m, rect.end.y - m, rect.end.y]
	var sxs := [0.0, src, tex_size.x - src, tex_size.x]
	var sys := [0.0, src, tex_size.y - src, tex_size.y]
	for i in 3:
		for j in 3:
			var dst := Rect2(xs[i], ys[j], xs[i + 1] - xs[i], ys[j + 1] - ys[j])
			if dst.size.x <= 0.0 or dst.size.y <= 0.0:
				continue
			var part := Rect2(sxs[i], sys[j], sxs[i + 1] - sxs[i], sys[j + 1] - sys[j])
			RenderingServer.canvas_item_add_texture_rect_region(to_canvas_item, dst, texture.get_rid(), part)
