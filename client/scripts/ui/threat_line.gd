class_name ThreatLine
extends Control
## The hordes known of as beads on a line of time, from now to the last of
## them: each where it sets out (hollow) or strikes (full), in its front's
## colour, with the time left under it. Redrawn as time passes.

const FRONT_COLORS := {"north": Color("#5b8fd6"), "east": Color("#d9a441"), "south": Color("#b0473c"), "west": Color("#7a5aa8")}

var _since := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(0, 92)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_since += delta
	if _since >= 1.0:
		_since = 0.0
		queue_redraw()


## [seconds from now, front, whether it is on the march] for each horde.
static func beads(waves: Array, now: float) -> Array:
	var out := []
	for wave in waves:
		var marching: bool = wave.get("status") in ["marching", "battling", "arrived", "razing"]
		var at: Variant = wave.get("arrivesAt") if marching else wave.get("spawnAt")
		if at == null:
			continue
		out.append([maxf(0.0, TimeUtil.parse_iso(String(at)) - now), String(wave.get("front", "")), marching])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return out


func _draw() -> void:
	var list := beads(Game.waves, Game.server_now())
	if list.is_empty():
		return
	var font := ThemeDB.fallback_font
	var left := 18.0
	var right := size.x - 18.0
	var y := 26.0
	var span := maxf(60.0, float(list[-1][0]))
	draw_line(Vector2(left, y), Vector2(right, y), Color(UiTheme.INK, 0.35), 3.0, true)
	draw_string(font, Vector2(left - 12.0, y + 44.0), UI.t("now"), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UiTheme.MUTED)
	var last_x := -1000.0
	for bead in list:
		var x := lerpf(left, right, clampf(float(bead[0]) / span, 0.0, 1.0))
		var color: Color = FRONT_COLORS.get(bead[1], UiTheme.MADDER)
		if bead[2]:
			draw_circle(Vector2(x, y), 13.0, color)
		else:
			draw_circle(Vector2(x, y), 13.0, UiTheme.PAGE)
			draw_arc(Vector2(x, y), 13.0, 0.0, TAU, 28, color, 4.0, true)
		draw_arc(Vector2(x, y), 13.0, 0.0, TAU, 28, Color(UiTheme.INK, 0.6), 1.5, true)
		# The time under it, unless it would sit on its neighbour's.
		if x - last_x > 112.0 and float(bead[0]) > 0.0:
			var text := TimeUtil.format_duration(float(bead[0]))
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			draw_string(font, Vector2(clampf(x - width / 2.0, left + 30.0, right - width), y + 44.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UiTheme.INK)
			last_x = x
