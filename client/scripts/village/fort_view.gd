class_name FortView
extends Control
## The inside of a fort (data/forts.json): the Keep and the Storage in the
## middle, three wall rings round them, inner to outer, each with its wall
## building at the bottom of the ring and its tower slots along it. A ring
## the Keep has not opened yet is drawn faint. Tap a plot to pick it.

signal plot_tapped(plot: String)

## Each ring's radius, of the view's half size, inner to outer.
const RINGS := [0.42, 0.64, 0.86]
const SLOT := 0.11
const CENTER := 0.17
const EARTH := Color("#8c7a58")
const GRASS := Color("#7d8c4c")
const LOCKED := Color(0.16, 0.14, 0.11, 0.55)
const EMPTY := Color("#4a3f30")
const BUILT := Color("#8f6d45")
const RISING := Color("#e2b04a")
const WALL := Color("#9d978c")
const PALISADE := Color("#6e4b2c")
const INK := Color("#1d1813")

## Game data and the fort as the server sent it; the picked plot.
var data: Dictionary = {}
var fort: Dictionary = {}
var selected := ""


func show_fort(game_data: Dictionary, f: Dictionary) -> void:
	data = game_data
	fort = f
	queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(UI.scaled(300), UI.scaled(300))
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)


func _half() -> float:
	return minf(size.x, size.y) * 0.5


func _middle() -> Vector2:
	return size * 0.5


## Where each plot stands, and how big it is drawn.
func _places() -> Dictionary:
	var out := {}
	if data.is_empty():
		return out
	var half := _half()
	var mid := _middle()
	out["keep"] = [mid + Vector2(-CENTER * 0.9, -CENTER * 0.1) * half, CENTER * half]
	out["storage"] = [mid + Vector2(CENTER * 1.0, CENTER * 0.35) * half, CENTER * 0.75 * half]
	var rings: Array = data.forts.rings
	for i in rings.size():
		var r: float = RINGS[i] * half
		# The wall building at the bottom; its towers spread along the ring.
		out["w%d" % i] = [mid + Vector2(0, r), SLOT * half]
		var slots := int(rings[i].slots)
		for s in slots:
			# Evenly round the ring, clear of the wall building at the bottom.
			var angle := PI / 2.0 + TAU * float(s + 1) / float(slots + 1)
			out["t%d-%d" % [i, s]] = [mid + Vector2(cos(angle), sin(angle)) * r, SLOT * 0.85 * half]
	return out


func _open(ring: int) -> bool:
	return LocalForts.level_of(fort.get("plots", {}), "keep") >= int(data.forts.rings[ring].keepLevel)


func _draw() -> void:
	if data.is_empty():
		return
	var half := _half()
	var mid := _middle()
	draw_rect(Rect2(Vector2.ZERO, size), GRASS)
	draw_circle(mid, RINGS[2] * half * 1.08, EARTH.darkened(0.08))
	var plots: Dictionary = fort.get("plots", {})
	var work: Variant = fort.get("work")
	for i in range(RINGS.size() - 1, -1, -1):
		var r: float = RINGS[i] * half
		var level := LocalForts.level_of(plots, "w%d" % i)
		var color := LOCKED if not _open(i) else (EMPTY if level == 0 else (WALL if level >= 5 else PALISADE))
		draw_arc(mid, r, 0, TAU, 96, color, maxf(3.0, half * (0.025 + 0.004 * level)), true)
	var font := get_theme_default_font()
	var places := _places()
	for plot in places:
		var at: Vector2 = places[plot][0]
		var s: float = places[plot][1]
		var ring := LocalForts.ring_of(plot)
		var held: Variant = plots.get(plot)
		var rising: bool = work != null and work.plot == plot
		var fill := EMPTY
		if ring >= 0 and not _open(ring):
			fill = LOCKED
		elif rising:
			fill = RISING
		elif held != null:
			fill = BUILT
		var tex := Art.texture(_art_id(plot, held, ring))
		if tex != null:
			var box := Rect2(at - Vector2(s, s), Vector2(s, s) * 2.0)
			draw_texture_rect(tex, box, false, Color.WHITE if fill != LOCKED else Color(1, 1, 1, 0.45))
			if rising:
				draw_arc(at, s * 0.62, 0, TAU, 32, RISING, 3.0, true)
		elif plot == "keep" or plot == "storage":
			draw_rect(Rect2(at - Vector2(s, s) * 0.5, Vector2(s, s)), fill)
			draw_rect(Rect2(at - Vector2(s, s) * 0.5, Vector2(s, s)), INK, false, 2.0)
		else:
			draw_circle(at, s * 0.5, fill)
			draw_arc(at, s * 0.5, 0, TAU, 24, INK, 2.0, true)
		if plot == selected:
			draw_arc(at, s * 0.72, 0, TAU, 32, Color.WHITE, 3.0, true)
		var label := ""
		if plot == "keep":
			label = UI.t("Keep")
		elif plot == "storage":
			label = UI.t("Storage")
		var level := int(held.level) if held != null else 0
		if level > 0:
			label = ("%s %d" % [label, level]).strip_edges()
		if label != "":
			var fs := UI.scaled(13)
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
			draw_string(font, at + Vector2(-w * 0.5, s * 0.85 + fs), label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color.WHITE)


## The art for a plot: the Keep as the fort, the Storage as a storehouse,
## walls by their material, towers by kind and stage; empty or locked plots.
func _art_id(plot: String, held: Variant, ring: int) -> String:
	var level := int(held.level) if held != null else 0
	if plot == "keep":
		return "map/fort"
	if plot == "storage":
		return Art.building_id("storehouse", maxi(level, 1))
	if ring >= 0 and not _open(ring):
		return "plot/locked"
	if held == null:
		return "plot/empty"
	if plot.begins_with("w"):
		return Art.building_id("wall", level, false, WallText.material(data, level))
	return Art.building_id(String(held.kind), level)


func _gui_input(event: InputEvent) -> void:
	var pressed: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	var touched: bool = event is InputEventScreenTouch and event.pressed
	if not (pressed or touched):
		return
	var at: Vector2 = event.position
	var places := _places()
	var best := ""
	var best_d := INF
	for plot in places:
		var d: float = at.distance_to(places[plot][0])
		if d <= float(places[plot][1]) * 0.75 and d < best_d:
			best = plot
			best_d = d
	if best != "":
		selected = best
		queue_redraw()
		plot_tapped.emit(best)
		accept_event()
