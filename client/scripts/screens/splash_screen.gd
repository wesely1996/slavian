extends Control
## The splash: the studio's logo (art id brand/studio, client/art/brand/
## night_forge.png, when it is there), then the game's logo settling in with
## one pass of light across its gold, then the start screen. A tap, click or
## key skips it. The background matches the boot splash (project settings),
## so the engine's start and this screen run on without a flash.

const NEXT_SCENE := "res://scenes/start.tscn"
const SHINE := "res://shaders/shine.gdshader"
const BACKGROUND := Color("#0e1117")

var _leaving := false
var _tween: Tween


func _ready() -> void:
	var back := ColorRect.new()
	back.color = BACKGROUND
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var studio := _picture(Art.texture("brand/studio"), 0.5)
	var game := _picture(Art.texture("brand/logo"), 0.62)
	var shine := ShaderMaterial.new()
	shine.shader = load(SHINE)
	game.material = shine
	_tween = create_tween()
	if studio.texture != null:
		_tween.tween_property(studio, "modulate:a", 1.0, 0.5)
		_tween.tween_interval(1.3)
		_tween.tween_property(studio, "modulate:a", 0.0, 0.45)
	# The game's logo: in, settling from a touch larger, one shine, out.
	game.scale = Vector2.ONE * 1.04
	_tween.tween_property(game, "modulate:a", 1.0, 0.6)
	_tween.parallel().tween_property(game, "scale", Vector2.ONE, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_method(func(t: float) -> void: shine.set_shader_parameter("sweep", t), -0.2, 1.2, 0.9).set_trans(Tween.TRANS_SINE)
	_tween.tween_interval(0.5)
	_tween.tween_property(game, "modulate:a", 0.0, 0.4)
	_tween.tween_callback(_leave)


## A picture centred on the screen, hidden until faded in.
func _picture(texture: Texture2D, share: float) -> TextureRect:
	var node := TextureRect.new()
	node.texture = texture
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.modulate.a = 0.0
	# As tall as `share` of the shorter side, never wider than the screen.
	var area := get_viewport_rect().size
	var aspect := float(texture.get_width()) / float(texture.get_height()) if texture != null else 1.0
	var height := minf(minf(area.x, area.y) * share, area.x * 0.86 / aspect)
	var size := Vector2(height * aspect, height)
	node.size = size
	node.position = (area - size) / 2.0
	node.pivot_offset = size / 2.0
	add_child(node)
	return node


func _unhandled_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventKey) and event.is_pressed()
	if pressed:
		_leave()


func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	if _tween != null:
		_tween.kill()
	get_tree().change_scene_to_file.call_deferred(NEXT_SCENE)
