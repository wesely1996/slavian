class_name VillageGround
extends Control
## The ground of the village view, drawn with the map's own shader
## (shaders/ground.gdshader) so it has the same grain, relief and water: a
## mesh over the whole view whose vertices take their colour (and, in alpha,
## their height) from `shade`, a callable VillageView gives it. Rebuilt only
## when the key changes.

## Grid cells across the longer side.
const CELLS := 72

var _mesh: ArrayMesh
var _built_for := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	show_behind_parent = true
	var ground := ShaderMaterial.new()
	ground.shader = load(MapGround.SHADER)
	ground.set_shader_parameter("detail", MapGround._noise(256, 0.02, 4))
	ground.set_shader_parameter("macro", MapGround._noise(256, 0.012, 3))
	ground.set_shader_parameter("detail_scale", 0.006)
	material = ground


## Rebuilds the mesh for `area` when `key` changed; `shade(point)` gives the
## ground's colour there, its height in alpha.
func build(area: Vector2, key: int, shade: Callable) -> void:
	if key == _built_for and _mesh != null:
		return
	_built_for = key
	var step := maxf(area.x, area.y) / CELLS
	var columns := ceili(area.x / step) + 1
	var rows := ceili(area.y / step) + 1
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	for y in rows + 1:
		for x in columns + 1:
			var p := Vector2(x * step, y * step)
			points.append(p)
			colors.append(shade.call(p))
	var vertices := PackedVector2Array()
	var vertex_colors := PackedColorArray()
	for y in rows:
		for x in columns:
			var i := y * (columns + 1) + x
			for k in [i, i + 1, i + columns + 2, i, i + columns + 2, i + columns + 1]:
				vertices.append(points[k])
				vertex_colors.append(colors[k])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = vertex_colors
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	queue_redraw()


func _draw() -> void:
	if _mesh != null:
		draw_mesh(_mesh, null)
