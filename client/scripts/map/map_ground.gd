class_name MapGround
extends Node2D
## The map's ground as one mesh (shaders/ground.gdshader): every hex keeps
## its terrain's colour in its middle and blends into its neighbours across
## the outer part, so the land reads as land, not tiles; the map's rim fades
## into the dark. Vertex alpha carries the terrain's height for the relief.
## Rebuilt only when the terrain changes.

const SHADER := "res://shaders/ground.gdshader"
## Beyond the map.
const VOID := Color("#171b20")
## How far out from the centre a hex keeps its own colour.
const CORE := 0.55

var hex_size := 48.0
var _mesh: ArrayMesh
var _built_for := 0


func _ready() -> void:
	var material := ShaderMaterial.new()
	material.shader = load(SHADER)
	material.set_shader_parameter("detail", _noise(256, 0.02, 4))
	material.set_shader_parameter("macro", _noise(256, 0.012, 3))
	self.material = material


## Rebuilds the mesh if the terrain changed since the last build.
func build(terrain: Dictionary, size: float) -> void:
	var key := hash([terrain, size])
	if key == _built_for and _mesh != null:
		return
	_built_for = key
	hex_size = size
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	for cell in terrain:
		_hex(terrain, cell, vertices, colors)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	queue_redraw()


func _draw() -> void:
	if _mesh != null:
		draw_mesh(_mesh, null)


## One hex: a fan in its own colour to CORE, then a band out to its rim,
## where corners take the mean of the three hexes meeting there and edge
## midpoints the mean of the two sharing the edge.
func _hex(terrain: Dictionary, cell: Vector2i, vertices: PackedVector2Array, colors: PackedColorArray) -> void:
	var center := HexMath.to_pixel(cell, hex_size)
	var corners := HexMath.corners(center, hex_size)
	var own := _ground(terrain, cell)
	# Corner k lies between the edges to the neighbours in these directions.
	var edge_dir := [0, 5, 4, 3, 2, 1]
	var outer := PackedVector2Array()
	var outer_colors := PackedColorArray()
	for k in 6:
		var before := cell + HexMath.DIRECTIONS[edge_dir[(k + 5) % 6]]
		var after := cell + HexMath.DIRECTIONS[edge_dir[k]]
		outer.append(corners[k])
		outer_colors.append(_mean([own, _ground(terrain, before), _ground(terrain, after)]))
		outer.append((corners[k] + corners[(k + 1) % 6]) / 2.0)
		outer_colors.append(_mean([own, _ground(terrain, after)]))
	for j in 12:
		var n := (j + 1) % 12
		var inner_a := center + (outer[j] - center) * CORE
		var inner_b := center + (outer[n] - center) * CORE
		vertices.append_array([center, inner_a, inner_b, inner_a, outer[j], outer[n], inner_a, outer[n], inner_b])
		colors.append_array([own, own, own, own, outer_colors[j], outer_colors[n], own, outer_colors[n], own])


## A cell's ground colour with its height in alpha; beyond the map, the dark.
static func _ground(terrain: Dictionary, cell: Vector2i) -> Color:
	if not terrain.has(cell):
		return Color(VOID, 0.25)
	var id: String = terrain[cell]
	return Color(Terrain.color(id), Terrain.height(id))


static func _mean(parts: Array) -> Color:
	var sum := Color(0, 0, 0, 0)
	for c in parts:
		sum += c
	return sum / float(parts.size())


static func _noise(size: int, frequency: float, octaves: int) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	var texture := NoiseTexture2D.new()
	texture.width = size
	texture.height = size
	texture.seamless = true
	texture.generate_mipmaps = true
	texture.noise = noise
	return texture
