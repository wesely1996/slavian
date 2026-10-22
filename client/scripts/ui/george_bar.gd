class_name GeorgeBar
extends Control
## The donation bar (Help, Support the game): the month's server costs as a
## strip of embroidery (Rushnyk) filling up, Saint George riding along it
## towards the dragon at its end, both in mosaic from an icon of Sveti Đorđe
## (tools/art/george_icon.py). When the costs are met he reaches it, his
## spear in its jaws as on the icon, and the dragon flinches.

## George's height on the bar; the dragon is drawn at the same scale.
const HEIGHT := 150.0
## Where the dragon lay under George on the icon, in George's heights from
## his picture's top left (printed by tools/art/george_icon.py).
const DRAGON_AT := Vector2(0.1931, 0.6794)
const TRACK := 30.0
const RIDE_SEC := 1.6

var ratio := 0.0
var _george: TextureRect
var _dragon: TextureRect
var _fill: Control
var _strip: Rushnyk
var _ridden := false
var _ride: Tween


func _init(raised: float, goal: float) -> void:
	ratio = clampf(raised / goal, 0.0, 1.0) if goal > 0.0 else 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill = Control.new()
	_fill.clip_contents = true
	add_child(_fill)
	_strip = Rushnyk.new()
	_fill.add_child(_strip)
	_dragon = _picture("ui/dragon")
	_george = _picture("ui/george")
	# Above the strip: George, raised by how far the dragon reaches below him.
	custom_minimum_size.y = _dragon.size.y + HEIGHT * DRAGON_AT.y + TRACK
	resized.connect(_layout)
	_layout.call_deferred()


## A picture at the bar's scale (George HEIGHT tall).
func _picture(id: String) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = Art.texture(id)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var george := Art.texture("ui/george")
	if rect.texture != null and george != null:
		rect.size = Vector2(rect.texture.get_size()) * HEIGHT / float(george.get_height())
	add_child(rect)
	return rect


func _draw() -> void:
	# The groove the embroidery fills.
	var groove := StyleBoxFlat.new()
	groove.bg_color = Color(UiTheme.INK, 0.12)
	groove.border_color = Color(UiTheme.INK, 0.4)
	groove.set_border_width_all(1)
	groove.set_corner_radius_all(3)
	draw_style_box(groove, _track())


func _track() -> Rect2:
	return Rect2(0, size.y - TRACK, size.x, TRACK)


func _layout() -> void:
	var track := _track()
	_fill.position = track.position
	_fill.size = Vector2(track.size.x * ratio, track.size.y)
	_strip.position = Vector2.ZERO
	_strip.size = track.size
	# The dragon lies on the strip at its end; George rides at the height the
	# icon puts him over it.
	_dragon.position = Vector2(track.end.x - _dragon.size.x, track.position.y - _dragon.size.y)
	_george.position.y = _dragon.position.y - DRAGON_AT.y * HEIGHT
	var strike := _dragon.position.x - DRAGON_AT.x * HEIGHT
	var goal_x := lerpf(0.0, strike, ratio)
	if size.x <= 0.0:
		return
	if _ridden:
		# Resized after the ride began: straight to his place.
		if _ride != null:
			_ride.kill()
		_george.position.x = goal_x
		_dragon.modulate = Color(1, 0.8, 0.8) if ratio >= 1.0 else Color.WHITE
		return
	# The first time: he rides in from the start of the strip.
	_ridden = true
	_george.position.x = 0.0
	var ride := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_ride = ride
	ride.tween_property(_george, "position:x", goal_x, RIDE_SEC * maxf(ratio, 0.2))
	if ratio >= 1.0:
		# The thrust: the dragon flinches and flushes red.
		ride.tween_property(_george, "position:x", goal_x + 8.0, 0.12)
		ride.parallel().tween_property(_dragon, "modulate", Color(1.4, 0.55, 0.5), 0.12)
		ride.tween_property(_george, "position:x", goal_x, 0.3)
		ride.parallel().tween_property(_dragon, "modulate", Color(1, 0.8, 0.8), 0.3)
