class_name MapGrade
extends ColorRect
## The light grade over the map (shaders/grade.gdshader): a warm wash from
## the upper left, slow cloud shadows that drift a little faster than the
## ground when it pans, and a vignette round the map in view. Follows the
## camera every frame; never takes input.

const SHADER := "res://shaders/grade.gdshader"

var camera: MapCamera


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grade := ShaderMaterial.new()
	grade.shader = load(SHADER)
	grade.set_shader_parameter("clouds", MapGround._noise(256, 0.008, 3))
	material = grade


func _process(_delta: float) -> void:
	if camera == null or not visible:
		return
	var screen := get_viewport_rect().size
	var grade := material as ShaderMaterial
	grade.set_shader_parameter("camera", camera.position)
	grade.set_shader_parameter("zoom", camera.zoom.x)
	grade.set_shader_parameter("screen", screen)
	grade.set_shader_parameter("focus", (screen / 2.0 + camera.view_offset) / screen)
