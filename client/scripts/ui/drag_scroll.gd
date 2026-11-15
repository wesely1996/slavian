class_name DragScroll
extends Node
## Lets a finger drag a ScrollContainer anywhere on it, over buttons and
## cards too (they take the touch for themselves, and the container's own
## drag never starts): past a few pixels the press becomes a scroll, the
## pressed button lets go (no click), and a flick carries on and slows.
## Add as a child of the ScrollContainer.

## How far a finger moves before a press becomes a scroll (pixels).
const DEADZONE := 14.0
## How fast a flick slows (share of its speed lost per second).
const FRICTION := 4.0

var _scroll: ScrollContainer
var _pressing := false
var _dragging := false
var _from := Vector2.ZERO
var _start := 0.0
var _last_y := 0.0
var _last_time := 0
var _speed := 0.0


func _enter_tree() -> void:
	_scroll = get_parent() as ScrollContainer


func _input(event: InputEvent) -> void:
	if _scroll == null or not _scroll.is_visible_in_tree():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_speed = 0.0
			_pressing = _scroll.get_global_rect().has_point(event.position) and not _over_own_drag()
			_dragging = false
			_from = event.position
			_start = _scroll.scroll_vertical
			_last_y = event.position.y
			_last_time = Time.get_ticks_msec()
		else:
			_pressing = false
			_dragging = false
	elif event is InputEventMouseMotion and _pressing:
		var dy: float = event.position.y - _from.y
		if not _dragging:
			if absf(dy) < DEADZONE or absf(dy) < absf(event.position.x - _from.x):
				return
			_dragging = true
			# The button under the finger lets go: no click when it lifts.
			_scroll.propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN)
			_from = event.position
			_start = _scroll.scroll_vertical
			dy = 0.0
		_scroll.scroll_vertical = roundi(_start - dy)
		var now := Time.get_ticks_msec()
		if now > _last_time:
			_speed = (_last_y - event.position.y) / ((now - _last_time) / 1000.0)
		_last_y = event.position.y
		_last_time = now
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _pressing or absf(_speed) < 20.0:
		if not _pressing:
			_speed = 0.0
		return
	_scroll.scroll_vertical += roundi(_speed * delta)
	_speed *= maxf(0.0, 1.0 - FRICTION * delta)


## Under the finger is something that drags by itself (a slider, a text
## field): leave it alone.
func _over_own_drag() -> bool:
	var under := get_viewport().gui_get_hovered_control()
	while under != null and under != _scroll:
		if under is Slider or under is TextEdit or under is ScrollBar or under is ScrollContainer:
			return true
		under = under.get_parent() as Control
	return false
