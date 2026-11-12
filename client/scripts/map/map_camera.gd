class_name MapCamera
extends Camera2D
## Touch-first map camera: one-finger drag pans, two-finger pinch zooms,
## a short tap selects. Mouse wheel and trackpad gestures work on desktop
## (mouse clicks arrive as touches via emulate_touch_from_mouse).

signal tapped(world_position: Vector2)

@export var min_zoom := 0.3
@export var max_zoom := 2.5
@export var wheel_zoom_step := 1.1
## A touch that moves further than this (screen pixels) is a drag, not a tap.
@export var tap_max_distance := 22.0
## A finger held still this long is still a tap (a careful one, as when
## picking where an army goes); longer is a hold.
@export var tap_max_msec := 900

## World-space rectangle the camera centre is kept inside.
var bounds := Rect2(-1e9, -1e9, 2e9, 2e9)
## Where on screen the camera's position shows, from the screen's centre:
## the middle of the part of the map not under a sheet.
var view_offset := Vector2.ZERO:
	set(value):
		view_offset = value
		_apply_offset()

var _touches: Dictionary[int, Vector2] = {}
var _tap_index := -1
var _tap_start := Vector2.ZERO
var _tap_start_msec := 0
var _tap_cancelled := false


func screen_to_world(screen_position: Vector2) -> Vector2:
	return position + (screen_position - get_viewport_rect().size / 2.0 - view_offset) / zoom


func zoom_at(screen_position: Vector2, factor: float) -> void:
	var before := screen_to_world(screen_position)
	var z := clampf(zoom.x * factor, min_zoom, max_zoom)
	zoom = Vector2(z, z)
	_apply_offset()
	position += before - screen_to_world(screen_position)
	_clamp_position()


func pan_by_screen(delta: Vector2) -> void:
	position -= delta / zoom
	_clamp_position()


## Every finger lifted is forgotten, wherever it comes up. A touch that went
## down on the map and came up over the interface (a sheet that grew under
## it, a bar at the screen's edge) never reaches _unhandled_input: left in
## _touches it would make every later tap look like the second finger of a
## pinch, and no tap would register again.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and not event.pressed and _touches.has(event.index):
		_forget.call_deferred(event.index)


func _forget(index: int) -> void:
	_touches.erase(index)
	if index == _tap_index:
		_tap_index = -1


## Fingers down when the app goes to the background never come up here.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_touches.clear()
		_tap_index = -1


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_at(event.position, wheel_zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_at(event.position, 1.0 / wheel_zoom_step)
	elif event is InputEventMagnifyGesture:
		zoom_at(event.position, event.factor)
	elif event is InputEventPanGesture:
		pan_by_screen(-event.delta * 16.0)


func _on_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		# The first finger (index 0) going down means none other is down.
		if event.index == 0:
			_touches.clear()
		_touches[event.index] = event.position
		if _touches.size() == 1:
			_tap_index = event.index
			_tap_start = event.position
			_tap_start_msec = Time.get_ticks_msec()
			_tap_cancelled = false
		else:
			_tap_cancelled = true
		return

	_touches.erase(event.index)
	if event.index == _tap_index:
		var is_tap := (
			not _tap_cancelled
			and event.position.distance_to(_tap_start) <= tap_max_distance
			and Time.get_ticks_msec() - _tap_start_msec <= tap_max_msec
		)
		_tap_index = -1
		if is_tap:
			tapped.emit(screen_to_world(event.position))


func _on_drag(event: InputEventScreenDrag) -> void:
	var previous: Vector2 = _touches.get(event.index, event.position - event.relative)
	_touches[event.index] = event.position
	if event.index == _tap_index and event.position.distance_to(_tap_start) > tap_max_distance:
		_tap_cancelled = true

	if _touches.size() == 1:
		pan_by_screen(event.position - previous)
		return

	# Pinch: zoom by the change in finger distance around the midpoint, and
	# pan by how far the midpoint moved.
	var other := _other_touch(event.index)
	var old_distance := previous.distance_to(other)
	var old_mid := (previous + other) / 2.0
	var new_mid := (event.position + other) / 2.0
	if old_distance > 1.0:
		zoom_at(old_mid, event.position.distance_to(other) / old_distance)
	pan_by_screen(new_mid - old_mid)


func _other_touch(index: int) -> Vector2:
	for i in _touches:
		if i != index:
			return _touches[i]
	return _touches[index]


func _apply_offset() -> void:
	offset = -view_offset / zoom.x


func _clamp_position() -> void:
	position = position.clamp(bounds.position, bounds.end)
