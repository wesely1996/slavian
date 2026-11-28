class_name HexMap
extends Node2D
## Draws the current world's map: the ground (MapGround, a shaded mesh where
## terrains blend into each other) and what stands on it (MapFeatures: woods,
## peaks, hills), both behind; then rivers, roads, villages, armies and enemy
## hordes from the art in client/art/art.json (docs/art-style.md), falling
## back to plain shapes where a piece is missing. Owners show by colour:
## green yours, blue allies', red enemies'. Redraws when something changes,
## and on every UI tick while a horde is on the move; battles' swords swing
## on a layer of their own (Clashes).

const SELECTION_COLOR := Color("#ffd75e")
const HOLY_CITY_COLOR := Color("#8a2b2b")
const MY_VILLAGE_COLOR := Color("#ffd75e")
const ALLY_VILLAGE_COLOR := Color("#f4efe1")
const VILLAGE_OUTLINE_COLOR := Color("#2b2118")
## Hordes' roads: half see-through, so the map shows through.
const HORDE_PATH_COLOR := Color(0.82, 0.14, 0.1, 0.5)
const RUINS_COLOR := Color("#6d655a")
const CARAVAN_COLOR := Color("#c99a5b")
const SETTLERS_COLOR := Color("#e8e2d0")
const HERO_COLOR := Color("#9b7bd4")
const ARMY_COLOR := Color("#5b8fd6")
const FORT_COLOR := Color("#8b6a45")
const GRAIN_COLOR := Color("#e2b33c")
const SITE_COLOR := Color("#d9b85c")
## Sides, for banners and outlines.
const MINE_COLOR := Color("#4caf50")
const ALLY_COLOR := Color("#3f7fd6")
const ENEMY_COLOR := Color("#d0453a")
## Raiders of a daily event (not a horde): black.
const RAIDER_COLOR := Color("#141414")
const RIVER_COLOR := Color("#4a86a3")
const RIVER_BANK := Color(0.1, 0.16, 0.12, 0.45)
const RIVER_GLINT := Color(0.75, 0.88, 0.92, 0.45)
const PLANK_COLOR := Color("#b07a45")
const LANE_COLOR := Color(0.95, 0.8, 0.35, 0.85)
## Walls along edges, by tier: a palisade of stakes, timber on stone, stone.
const WALL_COLORS := [Color("#7a5230"), Color("#8f8578"), Color("#b3ada3")]
const WALL_DARK := Color("#2b2118")
const GATE_IRON := Color("#3d3a38")
## Each front's emblem (art id "faction/<emblem>").
const EMBLEMS := {"north": "north", "east": "east", "south": "order", "west": "order"}

@export var hex_size := 48.0

var radius := 0
var selected := Vector2i.MAX
var _ground: MapGround
var _features: MapFeatures
var _highlights: MapHighlights
var _clashes: Clashes


func _ready() -> void:
	_ground = MapGround.new()
	_ground.show_behind_parent = true
	add_child(_ground)
	_features = MapFeatures.new()
	_features.show_behind_parent = true
	add_child(_features)
	_highlights = MapHighlights.new()
	_highlights.show_behind_parent = true
	add_child(_highlights)
	_clashes = Clashes.new()
	_clashes.map = self
	_clashes.set_process(false)
	add_child(_clashes)


## The map dressed for the season (data/seasons.json): the ground's colours
## (shaders/ground.gdshader) and the features' (MapFeatures.SEASON_TINTS).
func set_season(season: String) -> void:
	var index := maxi(0, SeasonText.ORDER.find(season))
	(_ground.material as ShaderMaterial).set_shader_parameter("season", index)
	_features.set_season(season)
	_ground.queue_redraw()


## Battles under way are drawn by a layer of their own (Clashes), so their
## swords can swing every frame without the whole map being drawn again.
class Clashes extends Node2D:
	var map: HexMap
	var battles: Array = []

	func show_battles(ongoing: Array) -> void:
		battles = ongoing
		set_process(not ongoing.is_empty())
		queue_redraw()

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		for battle in battles:
			map.draw_clash(self, battle)


func _ongoing_battles() -> Array:
	return Game.battles.filter(func(b: Dictionary) -> bool: return b.get("status") == "ongoing" and b.get("q") != null and b.get("r") != null)


## A battle under way: two swords over the hex swing in and clash, a spark
## where they meet, and a red glow pulsing on the ground.
func draw_clash(on: CanvasItem, battle: Dictionary) -> void:
	var cell := Vector2i(int(battle.q), int(battle.r))
	var center := HexMath.to_pixel(cell, hex_size)
	# Each battle swings in its own time.
	var t := Time.get_ticks_msec() / 1000.0 + float(int(battle.get("id", 0)) % 7) * 0.31
	var swing := pow((sin(t * 5.0) + 1.0) / 2.0, 3.0)
	var glow := HexMath.corners(center, hex_size * 0.9)
	on.draw_colored_polygon(glow, Color(ENEMY_COLOR, 0.12 + 0.12 * swing))
	var c := center + Vector2(0, -hex_size * 0.55)
	var s := hex_size * 0.55
	for side in [-1.0, 1.0]:
		var a := 0.95 - 0.7 * swing
		var dir := Vector2(-side * sin(a), -cos(a))
		var pivot := c + Vector2(side * s * 0.75, s * 0.7)
		var guard := pivot + dir * s * 0.32
		var tip := pivot + dir * s * 1.45
		var across := Vector2(dir.y, -dir.x)
		on.draw_line(pivot, guard, Color("#5b3a21"), s * 0.16, true)
		on.draw_circle(pivot, s * 0.09, Color("#c99a2e"))
		on.draw_line(guard - across * s * 0.24, guard + across * s * 0.24, Color("#c99a2e"), s * 0.11, true)
		on.draw_line(guard, tip, VILLAGE_OUTLINE_COLOR, s * 0.17, true)
		on.draw_line(guard, tip, Color("#dfe3e8"), s * 0.11, true)
	# A spark as the blades meet.
	if swing > 0.8:
		var spark := c + Vector2(0, -s * 0.15)
		var flash := (swing - 0.8) / 0.2
		for i in 8:
			var ray := Vector2.UP.rotated(i * TAU / 8.0) * s * (0.15 + 0.35 * flash)
			on.draw_line(spark, spark + ray, Color(1.0, 0.86, 0.4, flash), s * 0.06, true)
		on.draw_circle(spark, s * 0.08 * (1.0 + flash), Color(1, 1, 0.85, flash))


func refresh() -> void:
	var map: Variant = Game.world.get("map")
	radius = int(map.radius) if map is Dictionary else 0
	if _ground != null:
		# The enemy lands not yet seen are drawn as fog.
		var ground: Dictionary = Game.terrain.duplicate()
		for cell in Game.enemy_bands:
			if not ground.has(cell):
				ground[cell] = "fog"
		_ground.build(ground, hex_size)
		_features.build(Game.terrain, hex_size, _occupied())
	queue_redraw()


## Hexes kept clear of trees and peaks: settlements, camps, sites still to
## explore and forts.
func _occupied() -> Dictionary:
	var cells := {Vector2i.ZERO: true}
	for village in Game.villages.values():
		cells[Vector2i(int(village.q), int(village.r))] = true
	for list in [Game.camps, Game.sites.filter(func(site: Dictionary) -> bool: return site.status == "unexplored"), Game.forts]:
		for entry in list:
			cells[Vector2i(int(entry.q), int(entry.r))] = true
	return cells


func has_hex(cell: Vector2i) -> bool:
	return Game.terrain.has(cell)


func local_to_hex(local_position: Vector2) -> Vector2i:
	return HexMath.from_pixel(local_position, hex_size)


func hex_to_local(cell: Vector2i) -> Vector2:
	return HexMath.to_pixel(cell, hex_size)


func select(cell: Vector2i) -> void:
	selected = cell
	queue_redraw()


## The army whose sheet is open (0: none): ringed on the map.
var selected_army := 0


func select_army(army_id: int) -> void:
	selected_army = army_id
	queue_redraw()


## The hexes a road being laid from the selected hex can go to: marked
## until one is picked (empty: none).
var road_targets: Array = []


func show_road_targets(cells: Array) -> void:
	road_targets = cells
	queue_redraw()


## Bounding rectangle of all hex centres, in local coordinates.
func get_bounds() -> Rect2:
	var reach := radius
	# The enemy lands reach further out.
	for cell in Game.enemy_bands:
		reach = maxi(reach, HexMath.distance(cell, Vector2i.ZERO))
	var extent := HexMath.to_pixel(Vector2i(reach, 0), hex_size).x
	return Rect2(-extent, -extent, extent * 2.0, extent * 2.0)


func _draw() -> void:
	_highlights.show_marks(MapHighlights.marks_from(Game.camps, Game.sites, Game.shipyards), hex_size)
	for road in Game.roads:
		_draw_road(road)
	for edge in Game.rivers:
		_draw_river(edge)
	_draw_lake_lanes()
	for wall in Game.walls:
		_draw_wall(wall)

	if Game.terrain.has(Vector2i.ZERO):
		if not _draw_art("settlement/holy_city", Vector2.ZERO, hex_size * 1.5):
			draw_circle(Vector2.ZERO, hex_size * 0.45, HOLY_CITY_COLOR)
	for village in Game.villages.values():
		for plot in Rules.outpost_plots(village):
			_draw_outpost(Rules.outpost_hex(plot), int(village.plots[plot].level), Game.is_mine(village), String(village.plots[plot].get("terrain", "")))
	# Land being reshaped: a forest on fire, or a spade where work goes on.
	for cell in Game.terraforms:
		var c := HexMath.to_pixel(cell, hex_size)
		if Game.data.field.terraform.actions.get(Game.terraforms[cell].action, {}).has("fire"):
			_draw_art("map/fire", c, hex_size * 1.1)
		else:
			_draw_art("icon/terraform", c + Vector2(-hex_size * 0.4, -hex_size * 0.3), hex_size * 0.42, Color(UiTheme.ON_WOOD, 0.9))
	for village in Game.villages.values():
		_draw_village(village)

	var now := Game.server_now()
	for caravan in Game.caravans:
		var p := CaravanMath.progress(caravan, now)
		if Game.is_mine(Game.villages.get(int(caravan.villageId), {})):
			_draw_trail(caravan.get("path", []), p, caravan.status == "returning", CARAVAN_COLOR)
		if not p.is_empty():
			var a := HexMath.to_pixel(p.from, hex_size)
			var b := HexMath.to_pixel(p.to, hex_size)
			var pos := a.lerp(b, p.t)
			# An ox cart (merchants: a horse and a painted trader's wagon),
			# facing the way it goes, on its side's ring.
			var tex := Art.texture("map/merchant_caravan" if caravan.get("kind") == "merchant" else "map/caravan")
			if tex == null:
				draw_circle(pos, hex_size * 0.2, CARAVAN_COLOR)
				draw_arc(pos, hex_size * 0.2, 0.0, TAU, 16, VILLAGE_OUTLINE_COLOR, 2.0)
				continue
			_draw_ring(pos + Vector2(0, hex_size * 0.24), hex_size * 0.8, MINE_COLOR if Game.is_mine(Game.villages.get(int(caravan.villageId), {})) else ALLY_COLOR)
			var w := hex_size * 0.95
			var h := w * tex.get_size().y / tex.get_size().x
			draw_set_transform(pos, 0.0, Vector2(-1.0 if b.x < a.x - 0.5 else 1.0, 1.0))
			draw_texture_rect(tex, Rect2(Vector2(-w, -h) / 2.0, Vector2(w, h)), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for expedition in Game.expeditions:
		var p := CaravanMath.progress(expedition, now)
		if not p.is_empty():
			var pos := HexMath.to_pixel(p.from, hex_size).lerp(HexMath.to_pixel(p.to, hex_size), p.t)
			if _draw_art("unit/settler", pos, hex_size * 0.5):
				continue
			var r := hex_size * 0.22
			var tri := PackedVector2Array([pos + Vector2(0, -r), pos + Vector2(r, r * 0.8), pos + Vector2(-r, r * 0.8)])
			draw_colored_polygon(tri, SETTLERS_COLOR)
			tri.append(tri[0])
			draw_polyline(tri, VILLAGE_OUTLINE_COLOR, 2.0)
	for fort in Game.forts:
		# (A mountain city's store is drawn as the city.)
		if not fort.get("neutral", false):
			_draw_fort(fort)
	for camp in Game.camps:
		_draw_camp(camp)
	for settlement in Game.settlements:
		_draw_settlement(settlement)
	for yard in Game.shipyards:
		_draw_shipyard(yard)
	for site in Game.sites:
		if site.status == "unexplored":
			_draw_site(site)
	for army in Game.armies:
		_draw_army(army, now)
	for hero in Game.heroes:
		_draw_hero(hero, now)
	for band in Game.bands:
		_draw_band(band, now)
	for wave in Game.waves:
		if wave.status == "scheduled" and wave.get("forecast") is Dictionary:
			_draw_forecast(wave)
	for wave in WaveMath.visible_waves(Game.waves):
		_draw_horde(wave, now)
	_clashes.show_battles(_ongoing_battles())

	if has_hex(selected):
		var outline := HexMath.corners(HexMath.to_pixel(selected, hex_size), hex_size * 0.92)
		outline.append(outline[0])
		draw_polyline(outline, SELECTION_COLOR, 4.0)
	# Where a road can go: a dashed track from here and the hex ringed.
	for cell in road_targets:
		var from := HexMath.to_pixel(selected, hex_size)
		var to := HexMath.to_pixel(cell, hex_size)
		var ring := HexMath.corners(to, hex_size * 0.86)
		draw_colored_polygon(ring, Color(SELECTION_COLOR, 0.18))
		ring.append(ring[0])
		draw_polyline(ring, SELECTION_COLOR, 4.0, true)
		draw_dashed_line(from, to, SELECTION_COLOR, hex_size * 0.08, hex_size * 0.18, true)


## A road between two hex centres, drawn by its level (field.json
## road.levels): a dirt track with wheel ruts, a stone road of gravel, a
## paved road of flagstones between kerbs, each wider than the last. Into a
## mountain it climbs in switchbacks, low walls on the outer bends. Being
## built: faded and dashed; being built, improved or repaired: a pick and
## shovel. Damaged by fire: scorched black in patches.
func _draw_road(road: Array) -> void:
	var from := Vector2i(int(road[0]), int(road[1]))
	var to := Vector2i(int(road[2]), int(road[3]))
	var status := String(road[4])
	var tier := clampi(int(road[5]) if road.size() > 5 else 1, 1, ROAD_TIERS.size())
	var look: Dictionary = ROAD_TIERS[tier - 1]
	var w := hex_size * float(look.width)
	var bends: Array = []
	var points := _road_points(from, to, w, bends)
	if status == "building":
		_draw_road_dashed(points, look, w)
	else:
		_draw_road_body(points, look, w, tier)
		for bend in bends:
			_draw_road_wall(bend[0], bend[1], w)
		if road.size() > 6 and road[6] == true:
			_draw_road_scorch(points, w, from)
	if status != "standing":
		_draw_road_works(_along(points, 0.5), w)


## Each road level's look: [edge, surface, detail] colours and width in hexes.
const ROAD_TIERS := [
	{"edge": Color("#4a3622"), "surface": Color("#a5845a"), "detail": Color("#6e5236"), "width": 0.1},
	{"edge": Color("#3b3935"), "surface": Color("#a29d93"), "detail": Color("#5f5b55"), "width": 0.13},
	{"edge": Color("#2e2a25"), "surface": Color("#ddd3bd"), "detail": Color("#8f8574"), "width": 0.16},
]


## The road's line from centre to centre: straight, or where it enters a
## mountain, zigzagging up to the centre in three tight bends. `bends` gets
## [point, outward direction] for each bend.
func _road_points(from: Vector2i, to: Vector2i, w: float, bends: Array) -> PackedVector2Array:
	var a := HexMath.to_pixel(from, hex_size)
	var b := HexMath.to_pixel(to, hex_size)
	var mid := (a + b) / 2.0
	var points := PackedVector2Array([a])
	if _mountain(from):
		points.append_array(_switchbacks(a, mid, w, bends, from))
	points.append(mid)
	if _mountain(to):
		var climb := _switchbacks(b, mid, w, bends, to)
		climb.reverse()
		points.append_array(climb)
	points.append(b)
	return points


## Land a road climbs into (terrain.json roadMoveCost: a mountain pass).
func _mountain(cell: Vector2i) -> bool:
	return Game.data.get("terrain", {}).get("terrain", {}).get(Game.terrain.get(cell, ""), {}).get("roadMoveCost") != null


## Bends between the top (a mountain's centre) and the foot (where its road
## leaves it), from the top down, swinging side to side; seeded by the hex
## so the same mountain winds the same way.
func _switchbacks(top: Vector2, foot: Vector2, w: float, bends: Array, cell: Vector2i) -> PackedVector2Array:
	var along := foot - top
	var across := Vector2(-along.y, along.x).normalized()
	var swing := hex_size * 0.3
	var side := 1.0 if (hash(cell) & 1) == 0 else -1.0
	var points := PackedVector2Array()
	for t in [0.22, 0.5, 0.78]:
		var p: Vector2 = top + along * t + across * swing * side
		points.append(p)
		bends.append([p, across * side])
		side = -side
	return points


## A point `t` of the way along a line of points (by length).
func _along(points: PackedVector2Array, t: float) -> Vector2:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	var left := total * t
	for i in range(1, points.size()):
		var step := points[i - 1].distance_to(points[i])
		if left <= step and step > 0.0:
			return points[i - 1].lerp(points[i], left / step)
		left -= step
	return points[points.size() - 1]


## A standing road: its edge, its surface (rounded at every bend), then the
## level's detail along each stretch.
func _draw_road_body(points: PackedVector2Array, look: Dictionary, w: float, tier: int) -> void:
	var edge := w * (1.45 if tier == 3 else 1.3)
	draw_polyline(points, look.edge, edge, true)
	for p in points:
		draw_circle(p, edge / 2.0, look.edge)
	draw_polyline(points, look.surface, w, true)
	for p in points:
		draw_circle(p, w / 2.0, look.surface)
	for i in range(1, points.size()):
		var a: Vector2 = points[i - 1]
		var b: Vector2 = points[i]
		var length := a.distance_to(b)
		if length < 1.0:
			continue
		var dir := (b - a) / length
		var across := Vector2(-dir.y, dir.x)
		match tier:
			1:
				# Two wheel ruts.
				for side in [-0.24, 0.24]:
					draw_line(a + across * w * side, b + across * w * side, Color(look.detail, 0.75), maxf(1.0, w * 0.12), true)
			2:
				# Gravel: small stones scattered along it, the same each time.
				var n := int(length / (w * 0.45))
				for k in n:
					var at := a + dir * (k + 0.5) * length / maxf(1, n)
					var jitter := float((hash(Vector2i(int(at.x), int(at.y))) % 7) - 3) / 3.0
					draw_circle(at + across * w * 0.27 * jitter, w * 0.1, look.detail)
			_:
				# Flagstones: joints across, and a line of kerb stones each side.
				var n := int(length / (w * 0.75))
				for k in range(1, n):
					var at := a + dir * k * length / n
					draw_line(at - across * w * 0.42, at + across * w * 0.42, Color(look.detail, 0.45), maxf(1.0, w * 0.06), true)
				for side in [-0.42, 0.42]:
					draw_line(a + across * w * side, b + across * w * side, Color(look.detail, 0.55), maxf(1.0, w * 0.08), true)


## A road a fire damaged: soot over the surface in patches and a few
## cracks across it, the same each time.
func _draw_road_scorch(points: PackedVector2Array, w: float, seed_cell: Vector2i) -> void:
	var soot := Color(0.1, 0.08, 0.07, 0.7)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_cell)
	for t in [0.18, 0.4, 0.62, 0.85]:
		var at := _along(points, t + rng.randf_range(-0.05, 0.05))
		draw_circle(at, w * rng.randf_range(0.45, 0.7), soot)
	for t in [0.3, 0.52, 0.74]:
		var at := _along(points, t)
		var next := _along(points, minf(1.0, t + 0.02))
		var dir := (next - at).normalized()
		var across := Vector2(-dir.y, dir.x)
		draw_line(at - across * w * 0.5, at + across * w * 0.3 + dir * w * 0.3, Color(0.05, 0.04, 0.03, 0.85), maxf(1.0, w * 0.1), true)


## A road being built: its line dashed and faded.
func _draw_road_dashed(points: PackedVector2Array, look: Dictionary, w: float) -> void:
	for i in range(1, points.size()):
		draw_dashed_line(points[i - 1], points[i], Color(look.edge, 0.45), w * 1.3, w * 1.4, true)
		draw_dashed_line(points[i - 1], points[i], Color(look.surface, 0.55), w, w * 1.4, true)


## A low dry-stone wall on the outer side of a mountain bend.
func _draw_road_wall(at: Vector2, out: Vector2, w: float) -> void:
	var along := Vector2(-out.y, out.x)
	var c := at + out * w * 1.1
	# Three rough stones in a row.
	for k in [-0.62, 0.0, 0.62]:
		var p: Vector2 = c + along * w * k
		var stone := PackedVector2Array([p + along * w * 0.28 + out * w * 0.2, p - along * w * 0.26 + out * w * 0.22, p - along * w * 0.3 - out * w * 0.18, p + along * w * 0.3 - out * w * 0.2])
		draw_colored_polygon(stone, Color("#a39c8f"))
		stone.append(stone[0])
		draw_polyline(stone, Color("#4b4740"), maxf(1.0, w * 0.08), true)


## Work under way on a road: a crossed pick and shovel on a dark disc.
func _draw_road_works(at: Vector2, w: float) -> void:
	var r := maxf(w * 1.6, hex_size * 0.16)
	draw_circle(at, r, Color(0.16, 0.12, 0.08, 0.85))
	draw_arc(at, r, 0.0, TAU, 20, Color("#e2b33c"), 1.5, true)
	var handle := Color("#c9965a")
	var iron := Color("#d8dde2")
	# The shovel: handle from bottom left to top right, a blade at the top.
	var s0 := at + Vector2(-r * 0.55, r * 0.55)
	var s1 := at + Vector2(r * 0.3, -r * 0.3)
	draw_line(s0, s1, handle, r * 0.16, true)
	var blade := PackedVector2Array([s1 + Vector2(-r * 0.05, -r * 0.3), s1 + Vector2(r * 0.3, r * 0.05), s1 + Vector2(r * 0.42, -r * 0.3), s1 + Vector2(r * 0.12, -r * 0.45)])
	draw_colored_polygon(blade, iron)
	# The pick: handle from bottom right to top left, a curved head across it.
	var p0 := at + Vector2(r * 0.55, r * 0.55)
	var p1 := at + Vector2(-r * 0.4, -r * 0.4)
	draw_line(p0, p1, handle, r * 0.16, true)
	draw_arc(p1 + Vector2(r * 0.25, r * 0.25), r * 0.55, PI * 1.05, PI * 1.45, 8, iron, r * 0.14, true)


## A shipyard: a boat on the bank (highlighted by MapHighlights while it
## waits to be paid for or is being built); faded while being built.
func _draw_shipyard(yard: Dictionary) -> void:
	var c := HexMath.to_pixel(Vector2i(int(yard.q), int(yard.r)), hex_size)
	var tint := Color(1, 1, 1, 0.6) if yard.status == "building" else Color.WHITE
	# A mountain city: its walls and gate cut into the mountain (half
	# see-through until it is paid for and built).
	if EventText.is_city(yard):
		if not _draw_art("map/mountain_city", c, hex_size * 1.25, Color(1, 1, 1, 0.55) if yard.status == "open" else tint):
			draw_circle(c, hex_size * 0.35, Color("#8a8070") * tint)
	else:
		var r := hex_size * 0.32
		var hull := PackedVector2Array([c + Vector2(-r, 0), c + Vector2(r, 0), c + Vector2(r * 0.6, r * 0.45), c + Vector2(-r * 0.6, r * 0.45)])
		draw_colored_polygon(hull, PLANK_COLOR * tint)
		hull.append(hull[0])
		draw_polyline(hull, VILLAGE_OUTLINE_COLOR, 2.0)
		draw_line(c, c + Vector2(0, -r * 1.1), VILLAGE_OUTLINE_COLOR, 2.0)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 1.05), c + Vector2(r * 0.6, -r * 0.2), c + Vector2(0, -r * 0.2)]), Color(0.95, 0.92, 0.85) * tint)
	if yard.status == "done":
		return
	# (Highlighted under it by MapHighlights.)
	# How far along it is: paid for (green), then built (gold).
	var now := Game.server_now()
	var speed := float(Game.world.get("speed", 1))
	if yard.status == "open":
		_draw_bar(c + Vector2(0, hex_size * 0.62), EventText.paid_share(yard), UI.GOOD)
		return
	_draw_bar(c + Vector2(0, hex_size * 0.62), EventText.build_share(Game.data, yard, now, speed), GRAIN_COLOR)
	# The next raiders, in black: they close in from the wilds (away from
	# the Holy City) over the hours between raids, and strike when they reach it.
	var closing := EventText.raid_share(Game.data, yard, now, speed)
	if closing < 0.0:
		return
	var out := c.normalized() if c.length() > 0.0 else Vector2.UP
	var start := c + out * hex_size * 2.6
	var end := c + out * hex_size * 0.75
	var pos := start.lerp(end, closing)
	draw_dashed_line(pos, c + out * hex_size * 0.45, RAIDER_COLOR, hex_size * 0.06, hex_size * 0.16, true)
	draw_circle(pos, hex_size * 0.36, RAIDER_COLOR)
	draw_arc(pos, hex_size * 0.36, 0.0, TAU, 24, Color(0.85, 0.82, 0.75), 2.0)
	var emblem := "faction/" + String(EMBLEMS.get(String(yard.get("front", "north")), "north"))
	if Art.has(emblem):
		_draw_art(emblem, pos, hex_size * 0.6, Color(0.75, 0.72, 0.68))


## A gauge under something on the map (0..1) in `color`.
func _draw_bar(at: Vector2, full: float, color: Color) -> void:
	var w := hex_size * 0.8
	var h := hex_size * 0.1
	var box := Rect2(at - Vector2(w / 2.0, h / 2.0), Vector2(w, h))
	draw_rect(box, Color(0, 0, 0, 0.55))
	draw_rect(Rect2(box.position, Vector2(w * clampf(full, 0.0, 1.0), h)), color)
	draw_rect(box, VILLAGE_OUTLINE_COLOR, false, 1.5)


## A river along the edge between two hexes, and its bridge if one stands
## (faded while being built).
func _draw_river(edge: Array) -> void:
	var a := Vector2i(int(edge[0]), int(edge[1]))
	var b := Vector2i(int(edge[2]), int(edge[3]))
	var dir := RiverText.direction(a, b)
	if dir < 0:
		return
	var ends := _edge(HexMath.corners(HexMath.to_pixel(a, hex_size), hex_size), dir)
	# Wider below where rivers meet (edge[5], the size: 1 from the source).
	var wide := 1.0 + 0.4 * (RiverText.size_of(edge) - 1)
	draw_line(ends[0], ends[1], RIVER_BANK, hex_size * 0.2 * wide, true)
	draw_line(ends[0], ends[1], RIVER_COLOR, hex_size * 0.13 * wide, true)
	draw_line(ends[0].lerp(ends[1], 0.15), ends[0].lerp(ends[1], 0.85), RIVER_GLINT, hex_size * 0.03 * wide, true)
	draw_circle(ends[0], hex_size * 0.065 * wide, RIVER_COLOR)
	draw_circle(ends[1], hex_size * 0.065 * wide, RIVER_COLOR)
	# A river a finished boat sails: a golden thread down it.
	if Game.lanes.has(LocalLand.edge_key(a, b)):
		draw_dashed_line(ends[0], ends[1], LANE_COLOR, hex_size * 0.05 * wide, hex_size * 0.12, true)
	if String(edge[4]) == "none":
		return
	var mid: Vector2 = (ends[0] + ends[1]) / 2.0
	var across := (HexMath.to_pixel(b, hex_size) - HexMath.to_pixel(a, hex_size)).normalized()
	var tint := Color.WHITE if String(edge[4]) == "standing" else Color(1, 1, 1, 0.5)
	draw_line(mid - across * hex_size * 0.3, mid + across * hex_size * 0.3, VILLAGE_OUTLINE_COLOR * tint, hex_size * 0.3)
	draw_line(mid - across * hex_size * 0.27, mid + across * hex_size * 0.27, PLANK_COLOR * tint, hex_size * 0.22)


## Where a finished boat sails across a lake: a dashed golden thread along
## the edge between the hexes it crosses.
func _draw_lake_lanes() -> void:
	for k in Game.lanes:
		var ends := String(k).split("|")
		var a := _cell_of(ends[0])
		var b := _cell_of(ends[1])
		if Game.terrain.get(a, "") != "lake" and Game.terrain.get(b, "") != "lake":
			continue
		var dir := RiverText.direction(a, b)
		if dir < 0:
			continue
		var side := _edge(HexMath.corners(HexMath.to_pixel(a, hex_size), hex_size), dir)
		draw_dashed_line(side[0], side[1], LANE_COLOR, hex_size * 0.05, hex_size * 0.12, true)


func _cell_of(text: String) -> Vector2i:
	var parts := text.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))


## The corners shared with the neighbour in direction i (E, NE, NW, W, SW, SE).
func _edge(points: PackedVector2Array, i: int) -> Array:
	# Corners run from -30° (upper right) clockwise in 60° steps.
	var first: int = [0, 5, 4, 3, 2, 1][i]
	return [points[first], points[(first + 1) % 6]]


## Draws art id centred at `center`, `size` wide; false if there is no art.
func _draw_art(id: String, center: Vector2, size: float, tint := Color.WHITE) -> bool:
	var tex := Art.texture(id)
	if tex == null:
		return false
	var s := tex.get_size()
	var h := size * s.y / s.x
	draw_texture_rect(tex, Rect2(center - Vector2(size, h) / 2.0, Vector2(size, h)), false, tint)
	return true


## A side's mark under something on the map: a ring in its colour.
func _draw_ring(center: Vector2, width: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 33:
		var a := TAU * i / 32.0
		points.append(center + Vector2(cos(a) * width / 2.0, sin(a) * width * 0.17))
	draw_colored_polygon(points, Color(color, 0.22))
	draw_polyline(points, color, 3.0)


## The owner's banner beside something they hold.
func _draw_banner(base: Vector2, height: float, color: Color) -> void:
	var w := height * 64.0 / 96.0
	var rect := Rect2(base - Vector2(w * 0.22, height), Vector2(w, height))
	var pole := Art.texture("banner/pole")
	var cloth := Art.texture("banner/cloth")
	if pole == null or cloth == null:
		draw_line(base, base - Vector2(0, height), VILLAGE_OUTLINE_COLOR, 2.0)
		draw_rect(Rect2(base - Vector2(0, height), Vector2(height * 0.45, height * 0.35)), color)
		return
	draw_texture_rect(pole, rect, false)
	draw_texture_rect(cloth, rect, false, color)


## A village: its look by Elder's Hall level (or ruins), ringed and bannered
## in its owner's colour.
func _draw_village(village: Dictionary) -> void:
	var c := HexMath.to_pixel(Vector2i(int(village.q), int(village.r)), hex_size)
	var ruined: bool = village.get("ruin") is Dictionary
	var side := MINE_COLOR if Game.is_mine(village) else ALLY_COLOR
	var id := "settlement/ruins" if ruined else Art.settlement_id(int(village.get("levels", {}).get("elder_hall", 1)))
	_draw_ring(c + Vector2(0, hex_size * 0.42), hex_size * 1.5, side)
	if _draw_art(id, c + Vector2(0, -hex_size * 0.05), hex_size * 1.4):
		if not ruined:
			_draw_banner(c + Vector2(hex_size * 0.62, hex_size * 0.2), hex_size * 0.75, side)
		return
	var half := hex_size * 0.3
	var rect := Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0)
	draw_rect(rect, RUINS_COLOR if ruined else (MY_VILLAGE_COLOR if Game.is_mine(village) else ALLY_VILLAGE_COLOR))
	draw_rect(rect, VILLAGE_OUTLINE_COLOR, false, 2.0)
	if ruined:
		draw_line(rect.position, rect.end, VILLAGE_OUTLINE_COLOR, 3.0)
		draw_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y), VILLAGE_OUTLINE_COLOR, 3.0)


## A small watchtower: its art ringed in the owner's colour, faded while in
## ruins or under construction (a diamond without art).
## Every built outpost on the map (level 0 is still going up).
func _standing_outposts() -> Array:
	var cells: Array = []
	for village in Game.villages.values():
		for plot in Rules.outpost_plots(village):
			if int(village.plots[plot].level) > 0:
				cells.append(Rules.outpost_hex(plot))
	return cells


func _draw_outpost(cell: Vector2i, level: int, mine: bool, terrain: String) -> void:
	var c := HexMath.to_pixel(cell, hex_size)
	var side := MINE_COLOR if mine else ALLY_COLOR
	# Each land its own: a sawmill in the woods, a fishing boat on a lake.
	var look := String(Rules.outpost_kind(Game.data, terrain if terrain != "" else String(Game.terrain.get(cell, ""))).art)
	if not Art.has(look):
		look = "map/outpost"
	if Art.has(look):
		_draw_ring(c + Vector2(0, hex_size * 0.32), hex_size * 0.9, side)
		_draw_art(look, c, hex_size * 0.85, Color(1, 1, 1, 0.55) if level <= 0 else Color.WHITE)
		return
	var r := hex_size * 0.26
	var diamond := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
	var fill := RUINS_COLOR if level <= 0 else (MY_VILLAGE_COLOR if mine else ALLY_VILLAGE_COLOR)
	draw_colored_polygon(diamond, fill)
	diamond.append(diamond[0])
	draw_polyline(diamond, VILLAGE_OUTLINE_COLOR, 2.0)


## Where an army's marker is drawn (Vector2.INF: not on the map).
func army_position(army: Dictionary, now: float) -> Vector2:
	if army.status == "done":
		return Vector2.INF
	var p := ArmyText.progress(army, now)
	if not p.is_empty():
		return HexMath.to_pixel(p.from, hex_size).lerp(HexMath.to_pixel(p.to, hex_size), p.t)
	if army.status in ["stationed", "engaged"] and ArmyText.held_hex(army) != Vector2i.MAX:
		return HexMath.to_pixel(ArmyText.held_hex(army), hex_size) + Vector2(hex_size * 0.36, hex_size * 0.3)
	if army.status in ["stationed", "engaged"]:
		var village: Dictionary = Game.villages.get(int(army.targetVillageId), {})
		if not village.is_empty():
			return HexMath.to_pixel(Vector2i(int(village.q), int(village.r)), hex_size) + Vector2(-hex_size * 0.42, hex_size * 0.38)
	return Vector2.INF


## The ids of the armies whose markers are under `local` (none: []): those
## drawn on the same spot as the nearest, your own first, then the biggest
## (ArmyText.stack_order); a tap goes through them one after another.
func armies_at(local: Vector2, now: float) -> Array:
	var nearest := Vector2.INF
	var hits: Array = []
	for army in Game.armies:
		var pos := army_position(army, now)
		if pos == Vector2.INF or pos.distance_to(local) > hex_size * 0.3:
			continue
		hits.append([army, pos])
		if nearest == Vector2.INF or pos.distance_to(local) < nearest.distance_to(local):
			nearest = pos
	var stack: Array = []
	for hit in hits:
		if hit[1].distance_to(nearest) < hex_size * 0.15:
			stack.append(hit[0])
	return ArmyText.stack_order(stack, Game.my_account_id())


## An army: a blue shield on the road, or beside the village it guards.
func _draw_army(army: Dictionary, now: float) -> void:
	var p := ArmyText.progress(army, now)
	var mine := int(army.get("ownerAccountId", -1)) == Game.my_account_id()
	if mine:
		_draw_trail(army.get("path", []), p, army.status == "returning", MINE_COLOR)
	# A hex your army holds (or marches to hold): an ambush set, ringed.
	var held := ArmyText.held_hex(army)
	if mine and held != Vector2i.MAX and army.status in ["marching", "stationed", "engaged"] and army.orders == "hold":
		_draw_ambush(held, army.status != "marching")
	var pos := army_position(army, now)
	if pos == Vector2.INF:
		return
	if int(army.id) == selected_army:
		draw_arc(pos, hex_size * 0.34, 0.0, TAU, 32, SELECTION_COLOR, 3.0, true)
	var side := MINE_COLOR if int(army.get("ownerAccountId", -1)) == Game.my_account_id() else ALLY_COLOR
	# Its banner on the map: the army's symbol, and on the flag beside it
	# how many troops march under it.
	_draw_army_flag(pos + Vector2(hex_size * 0.22, -hex_size * 0.12), hex_size * 0.5, side, LocalBattle.total(army.get("units", {})))
	if Art.has("unit/" + ArmyText.main_unit(army)):
		draw_circle(pos, hex_size * 0.27, side)
		_draw_art("unit/" + ArmyText.main_unit(army), pos, hex_size * 0.46)
		return
	var r := hex_size * 0.2
	var shield := PackedVector2Array([pos + Vector2(-r, -r), pos + Vector2(r, -r), pos + Vector2(r, r * 0.3), pos + Vector2(0, r * 1.2), pos + Vector2(-r, r * 0.3)])
	draw_colored_polygon(shield, ARMY_COLOR)
	shield.append(shield[0])
	draw_polyline(shield, VILLAGE_OUTLINE_COLOR, 2.0)


## An army's flag: a pole and a cloth in its side's colour, with its number
## of troops written on the cloth.
func _draw_army_flag(base: Vector2, height: float, color: Color, count: int) -> void:
	var top := base - Vector2(0, height)
	draw_line(base, top, VILLAGE_OUTLINE_COLOR, maxf(1.5, height * 0.06), true)
	var text := str(count)
	var font := ThemeDB.fallback_font
	var size := maxi(8, roundi(height * 0.36))
	var width := maxf(height * 0.5, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + height * 0.16)
	var cloth := Rect2(top, Vector2(width, height * 0.44))
	draw_rect(cloth, color)
	draw_rect(cloth, VILLAGE_OUTLINE_COLOR, false, maxf(1.0, height * 0.04))
	draw_string(font, top + Vector2(height * 0.08, height * 0.44 - height * 0.1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE)


## An ambush set on a hex: a dashed ring in your colour and crossed spears
## (faint while the army is still on its way).
func _draw_ambush(cell: Vector2i, ready: bool) -> void:
	var center := HexMath.to_pixel(cell, hex_size)
	var color := Color(MINE_COLOR, 0.95 if ready else 0.5)
	var corners := HexMath.corners(center, hex_size * 0.82)
	for i in corners.size():
		draw_dashed_line(corners[i], corners[(i + 1) % corners.size()], color, 3.0, hex_size * 0.14, true)
	var at := center + Vector2(-hex_size * 0.38, -hex_size * 0.42)
	var r := hex_size * 0.16
	draw_circle(at, r * 1.25, Color(0.1, 0.12, 0.08, 0.6))
	draw_line(at + Vector2(-r, r), at + Vector2(r, -r), color, 2.5, true)
	draw_line(at + Vector2(r, r), at + Vector2(-r, -r), color, 2.5, true)


## An ancient site still to explore: a standing stone (explored ones are
## gone from the map).
func _draw_site(site: Dictionary) -> void:
	var c := HexMath.to_pixel(Vector2i(int(site.q), int(site.r)), hex_size)
	if _draw_art("site/" + String(site.kind), c, hex_size * 1.1, Color.WHITE):
		return
	var w := hex_size * 0.13
	var h := hex_size * 0.34
	var stone := PackedVector2Array([c + Vector2(-w, h * 0.7), c + Vector2(-w * 1.2, -h * 0.4), c + Vector2(0, -h), c + Vector2(w * 1.2, -h * 0.4), c + Vector2(w, h * 0.7)])
	draw_colored_polygon(stone, SITE_COLOR)
	stone.append(stone[0])
	draw_polyline(stone, VILLAGE_OUTLINE_COLOR, 2.0)


## An enemy settlement: its kind's look on its front's ring, with its level.
const SETTLEMENT_ART := {"seat": "settlement/village_5", "town": "settlement/village_3", "fort": "map/fort", "camp": "map/camp_bandit", "lair": "map/camp_lair"}


func _draw_settlement(s: Dictionary) -> void:
	var c := HexMath.to_pixel(Vector2i(int(s.q), int(s.r)), hex_size)
	var color := WaveMath.front_color(String(s.front))
	var big: bool = s.kind == "seat"
	_draw_ring(c + Vector2(0, hex_size * 0.42), hex_size * (1.35 if big else 1.15), color)
	var art: String = SETTLEMENT_ART.get(String(s.kind), "map/camp_bandit")
	if not _draw_art(art, c, hex_size * (1.4 if big else 1.1), Color(1.0, 0.82, 0.78)):
		draw_circle(c, hex_size * 0.35, color.darkened(0.2))
		draw_arc(c, hex_size * 0.35, 0, TAU, 24, VILLAGE_OUTLINE_COLOR, 2.0)
	# Its level, on a shield in its front's colour.
	var badge := c + Vector2(hex_size * 0.5, -hex_size * 0.45)
	draw_circle(badge, hex_size * 0.2, VILLAGE_OUTLINE_COLOR)
	draw_circle(badge, hex_size * 0.16, color)
	var font := ThemeDB.fallback_font
	var text := str(int(s.get("level", 1)))
	var size := int(hex_size * 0.26)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size).x
	draw_string(font, badge + Vector2(-w / 2.0, size * 0.36), text, HORIZONTAL_ALIGNMENT_CENTER, -1, size, Color.WHITE)


## A bandit camp or monster lair: a tent in its faction's colour.
func _draw_camp(camp: Dictionary) -> void:
	var c := HexMath.to_pixel(Vector2i(int(camp.q), int(camp.r)), hex_size)
	# Captives are held in a bandit camp.
	var art := "map/camp_" + ("bandit" if camp.kind == "captives" else String(camp.kind))
	if not Art.has(art):
		art = "map/camp_bandit"
	if Art.has(art):
		# (Highlighted under it by MapHighlights.)
		_draw_art(art, c, hex_size * 1.15)
		return
	var r := hex_size * 0.32
	var tent := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, r * 0.7), c + Vector2(-r, r * 0.7)])
	draw_colored_polygon(tent, WaveMath.front_color(String(camp.front)).darkened(0.25))
	tent.append(tent[0])
	draw_polyline(tent, VILLAGE_OUTLINE_COLOR, 2.0)
	draw_line(c + Vector2(0, -r * 0.1), c + Vector2(0, r * 0.7), VILLAGE_OUTLINE_COLOR, 2.0)


## A fort: a squat tower with battlements, faded while being built. A
## supply point: a stack of grain sacks under a roof. A standing one shows
## how full its grain store is.
func _draw_fort(fort: Dictionary) -> void:
	var c := HexMath.to_pixel(Vector2i(int(fort.q), int(fort.r)), hex_size)
	# A supply point beside a fort on the same hex stands off to one side.
	if fort.get("kind", "fort") == "supply" and not Game.fort_at_kind(Vector2i(int(fort.q), int(fort.r)), "fort").is_empty():
		c += Vector2(hex_size * 0.45, hex_size * 0.3)
	if fort.status == "standing":
		_draw_grain_bar(c + Vector2(0, hex_size * 0.62), float(fort.get("grain", 0)) / maxf(1.0, FieldRules.grain_capacity(Game.data, fort)))
	if fort.get("kind", "fort") == "fort":
		_draw_fort_curtain(fort, c)
	_draw_fort_body(fort, c)


## A wall along an edge: stakes for a palisade, timber on a stone footing,
## or crenellated stone, faded while the first tier is built. A gatehouse
## leaves a gap in the middle, iron gates between two towers.
func _draw_wall(row: Array) -> void:
	var a := Vector2i(int(row[0]), int(row[1]))
	var b := Vector2i(int(row[2]), int(row[3]))
	var dir := RiverText.direction(a, b)
	if dir < 0:
		return
	var w := EdgeWallText.entry(row)
	var ends := _edge(HexMath.corners(HexMath.to_pixel(a, hex_size), hex_size), dir)
	# On a river's bank: drawn off the water, on its own side.
	if w.bank != null:
		var mid: Vector2 = (ends[0] + ends[1]) / 2.0
		var shift: Vector2 = (HexMath.to_pixel(w.bank, hex_size) - mid).normalized() * hex_size * 0.16
		ends = [ends[0].lerp(ends[1], 0.08) + shift, ends[1].lerp(ends[0], 0.08) + shift]
	var tier := clampi(maxi(1, int(w.tier)), 1, WALL_COLORS.size())
	var fade := Color(1, 1, 1, 0.45) if w.status == "building" else Color.WHITE
	var color: Color = WALL_COLORS[tier - 1] * fade
	# The enemy's walls in its lands: outlined in its front's colour.
	var front: Variant = row[9] if row.size() > 9 else null
	var dark := (WaveMath.front_color(String(front)).darkened(0.35) if front != null else WALL_DARK) * fade
	var thick := hex_size * (0.12 + 0.03 * tier)
	# Which side is out (away from a's centre), for the battlements.
	var out := (HexMath.to_pixel(b, hex_size) - HexMath.to_pixel(a, hex_size)).normalized()
	var gate: bool = w.kind == "gate"
	var spans: Array = [[0.0, 0.36], [0.64, 1.0]] if gate else [[0.0, 1.0]]
	for span in spans:
		var p: Vector2 = ends[0].lerp(ends[1], span[0])
		var q: Vector2 = ends[0].lerp(ends[1], span[1])
		draw_line(p, q, dark, thick + 3.0, true)
		draw_line(p, q, color, thick, true)
		var n := maxi(1, roundi((q - p).length() / (hex_size * 0.16)))
		for i in n + 1:
			var at := p.lerp(q, float(i) / float(n))
			match tier:
				1:
					# Sharpened stakes.
					draw_circle(at, thick * 0.42, color.darkened(0.25))
				2:
					# Timber posts on the stone.
					if i % 2 == 0:
						draw_line(at - out * thick * 0.5, at + out * thick * 0.5, WALL_COLORS[0] * fade, thick * 0.35)
				_:
					# Battlements.
					if i % 2 == 0:
						var m := at + out * thick * 0.45
						draw_rect(Rect2(m - Vector2.ONE * thick * 0.22, Vector2.ONE * thick * 0.44), color.lightened(0.15))
	draw_circle(ends[0], thick * 0.55, dark)
	draw_circle(ends[1], thick * 0.55, dark)
	if gate:
		var g0: Vector2 = ends[0].lerp(ends[1], 0.36)
		var g1: Vector2 = ends[0].lerp(ends[1], 0.64)
		# The gates (shut), then a tower each side.
		draw_line(g0, g1, GATE_IRON * fade, thick * 0.55, true)
		draw_line(g0.lerp(g1, 0.5) - out * thick * 0.3, g0.lerp(g1, 0.5) + out * thick * 0.3, dark, 2.0)
		for t in [g0, g1]:
			var side := thick * 1.7
			draw_rect(Rect2(t - Vector2.ONE * side * 0.5, Vector2.ONE * side), dark)
			draw_rect(Rect2(t - Vector2.ONE * side * 0.38, Vector2.ONE * side * 0.76), color.lightened(0.1))


## A fort merged with a gatehouse (EdgeWallText.fort_gatehouse): a curtain
## wall all round its hex at the gatehouse's tier, a tower at each corner.
func _draw_fort_curtain(fort: Dictionary, c: Vector2) -> void:
	var gate := EdgeWallText.fort_gatehouse(Game.walls, fort)
	if gate.is_empty():
		return
	var tier := clampi(int(gate.tier), 1, WALL_COLORS.size())
	var color: Color = WALL_COLORS[tier - 1]
	var ring := HexMath.corners(c, hex_size * 0.78)
	var closed := ring.duplicate()
	closed.append(ring[0])
	draw_polyline(closed, WALL_DARK, hex_size * 0.11 + 3.0, true)
	draw_polyline(closed, color, hex_size * 0.11, true)
	# A tower at every corner, larger for stone.
	for corner in ring:
		var side := hex_size * (0.12 + 0.025 * tier)
		draw_rect(Rect2(corner - Vector2.ONE * side * 0.5, Vector2.ONE * side), WALL_DARK)
		draw_rect(Rect2(corner - Vector2.ONE * side * 0.36, Vector2.ONE * side * 0.72), color.lightened(0.15))
	# (The gatehouse itself stands on its edge, drawn with the walls.)


## A grain gauge under a store: gold for what it holds.
func _draw_grain_bar(at: Vector2, full: float) -> void:
	_draw_bar(at, full, GRAIN_COLOR)


func _draw_fort_body(fort: Dictionary, c: Vector2) -> void:
	var supply: bool = fort.get("kind", "fort") == "supply"
	var art := "map/supply_point" if supply else "map/fort"
	if Art.has(art):
		var side := MINE_COLOR if int(fort.get("ownerAccountId", -1)) == Game.my_account_id() else ALLY_COLOR
		_draw_ring(c + Vector2(0, hex_size * 0.42), hex_size * 1.2, side)
		_draw_art(art, c, hex_size * 1.1, Color.WHITE if fort.status == "standing" else Color(1, 1, 1, 0.5))
		return
	if supply:
		var color := FORT_COLOR if fort.status == "standing" else RUINS_COLOR
		for offset in [Vector2(-0.14, 0.1), Vector2(0.14, 0.1), Vector2(0, -0.08)]:
			draw_circle(c + offset * hex_size, hex_size * 0.12, color)
			draw_arc(c + offset * hex_size, hex_size * 0.12, 0, TAU, 16, VILLAGE_OUTLINE_COLOR, 2.0)
		return
	var w := hex_size * 0.3
	var h := hex_size * 0.26
	var tower := PackedVector2Array([
		c + Vector2(-w, h), c + Vector2(-w, -h), c + Vector2(-w * 0.5, -h), c + Vector2(-w * 0.5, -h * 0.6),
		c + Vector2(-w * 0.1, -h * 0.6), c + Vector2(-w * 0.1, -h), c + Vector2(w * 0.1, -h), c + Vector2(w * 0.1, -h * 0.6),
		c + Vector2(w * 0.5, -h * 0.6), c + Vector2(w * 0.5, -h), c + Vector2(w, -h), c + Vector2(w, h)])
	draw_colored_polygon(tower, FORT_COLOR if fort.status == "standing" else RUINS_COLOR)
	tower.append(tower[0])
	draw_polyline(tower, VILLAGE_OUTLINE_COLOR, 2.0)


## An enemy war band on the march: a pennant in its front's colour with its
## strength, its road ahead dotted (red when it hunts one of your armies).
func _draw_band(band: Dictionary, now: float) -> void:
	var path: Array = band.get("path", [])
	if path.is_empty():
		return
	var steps: Array = path.map(func(s: Array) -> Dictionary: return {"q": int(s[0]), "r": int(s[1]), "atMs": int(s[2])})
	var p := CaravanMath.progress({"status": "outbound", "departsAt": band.departsAt, "path": steps}, now)
	var pos: Vector2
	if p.is_empty():
		# Resting before it sets out, or at the end of its road.
		var at: Dictionary = steps[0] if now < TimeUtil.parse_iso(String(band.departsAt)) else steps[-1]
		pos = HexMath.to_pixel(Vector2i(int(at.q), int(at.r)), hex_size)
	else:
		pos = HexMath.to_pixel(p.from, hex_size).lerp(HexMath.to_pixel(p.to, hex_size), p.t)
	var color := WaveMath.front_color(String(band.front))
	if band.status == "hunting":
		var ahead := PackedVector2Array([pos])
		for s in steps:
			if int(s.atMs) > (now - TimeUtil.parse_iso(String(band.departsAt))) * 1000.0:
				ahead.append(HexMath.to_pixel(Vector2i(int(s.q), int(s.r)), hex_size))
		if ahead.size() > 1:
			_draw_dots(ahead, HORDE_PATH_COLOR, hex_size * 0.07)
	var r := hex_size * 0.2
	draw_line(pos + Vector2(0, r * 1.2), pos + Vector2(0, -r * 1.6), VILLAGE_OUTLINE_COLOR, 3.0)
	var flag := PackedVector2Array([pos + Vector2(0, -r * 1.6), pos + Vector2(r * 1.4, -r * 1.15), pos + Vector2(0, -r * 0.7)])
	draw_colored_polygon(flag, color)
	flag.append(flag[0])
	draw_polyline(flag, VILLAGE_OUTLINE_COLOR, 2.0)
	var count := 0
	for unit in band.get("units", {}):
		count += int(band.units[unit])
	var font := ThemeDB.fallback_font
	var size := int(hex_size * 0.24)
	draw_string(font, pos + Vector2(-hex_size * 0.3, r * 1.9), str(count), HORIZONTAL_ALIGNMENT_CENTER, hex_size * 0.6, size, Color.WHITE)


## A hero: a small banner by its village, or on the road between two.
func _draw_hero(hero: Dictionary, now: float) -> void:
	var pos := Vector2.INF
	if hero.status == "traveling" and hero.path != null:
		var p := CaravanMath.progress({"status": "outbound", "departsAt": hero.departsAt, "path": hero.path}, now)
		if not p.is_empty():
			pos = HexMath.to_pixel(p.from, hex_size).lerp(HexMath.to_pixel(p.to, hex_size), p.t)
	elif hero.villageId != null:
		var village: Dictionary = Game.villages.get(int(hero.villageId), {})
		if not village.is_empty():
			pos = HexMath.to_pixel(Vector2i(int(village.q), int(village.r)), hex_size) + Vector2(-hex_size * 0.42, -hex_size * 0.38)
	if pos == Vector2.INF:
		return
	var color := HERO_COLOR.darkened(0.45) if hero.status == "wounded" else HERO_COLOR
	draw_circle(pos, hex_size * 0.17, color)
	draw_arc(pos, hex_size * 0.17, 0.0, TAU, 16, VILLAGE_OUTLINE_COLOR, 2.0)


func has_moving_hordes() -> bool:
	return Game.waves.any(func(w: Dictionary) -> bool: return w.status == "marching") \
		or Game.caravans.any(func(c: Dictionary) -> bool: return c.status != "done") \
		or Game.expeditions.any(func(e: Dictionary) -> bool: return e.status in ["outbound", "returning"]) \
		or Game.heroes.any(func(h: Dictionary) -> bool: return h.status == "traveling") \
		or Game.armies.any(func(a: Dictionary) -> bool: return a.status in ["marching", "returning"])


## A horde's road as a line of red dots, and a target where it will strike.
func _draw_route(points: PackedVector2Array, color: Color) -> void:
	_draw_dots(points, color, hex_size * 0.095)
	_draw_crosshair(points[points.size() - 1], color, 1.0)


## A target's crosshair; `scale` < 1 for one struck in passing.
func _draw_crosshair(at: Vector2, color: Color, scale: float) -> void:
	draw_arc(at, hex_size * 0.62 * scale, 0.0, TAU, 36, color, 4.0 * scale, true)
	draw_arc(at, hex_size * 0.3 * scale, 0.0, TAU, 24, color, 3.0 * scale, true)
	for i in 4:
		var way := Vector2.RIGHT.rotated(i * PI / 2.0)
		draw_line(at + way * hex_size * 0.42 * scale, at + way * hex_size * 0.8 * scale, color, 4.0 * scale, true)


## A line of dots along `points`.
func _draw_dots(points: PackedVector2Array, color: Color, dot: float) -> void:
	var spacing := hex_size * 0.3
	var carry := 0.0
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		var length := a.distance_to(b)
		var along := carry
		while along < length:
			draw_circle(a.lerp(b, along / length), dot, color)
			along += spacing
		carry = along - length


## The road still ahead of something on the move, from `pos`: on along
## `path` ([q, r, ms] steps) from the hex it heads for, or (`back`) the same
## road home.
func _road_ahead(path: Array, heading: Vector2i, pos: Vector2, back: bool) -> PackedVector2Array:
	var cells: Array = path.map(func(step: Array) -> Vector2i: return Vector2i(int(step[0]), int(step[1])))
	if back:
		cells.reverse()
	var trail := PackedVector2Array([pos])
	var ahead := false
	for cell in cells:
		ahead = ahead or cell == heading
		if ahead:
			trail.append(HexMath.to_pixel(cell, hex_size))
	return trail


## Your armies' and caravans' roads: dots to where they go, and home again.
func _draw_trail(path: Array, p: Dictionary, back: bool, color: Color) -> void:
	if p.is_empty() or path.is_empty():
		return
	var pos := HexMath.to_pixel(p.from, hex_size).lerp(HexMath.to_pixel(p.to, hex_size), p.t)
	var trail := _road_ahead(path, p.to, pos, back)
	if trail.size() < 2:
		return
	_draw_dots(trail, Color(color, 0.6), hex_size * 0.06)
	draw_arc(trail[trail.size() - 1], hex_size * 0.4, 0.0, TAU, 28, Color(color, 0.7), 3.0, true)


## Where a horde not yet out is expected to gather and go (its forecast):
## fainter than one on the march.
func _draw_forecast(wave: Dictionary) -> void:
	var forecast: Dictionary = wave.forecast
	var points := PackedVector2Array()
	for step in forecast.get("path", []):
		points.append(HexMath.to_pixel(Vector2i(int(step[0]), int(step[1])), hex_size))
	if points.size() < 2:
		return
	_draw_route(points, Color(HORDE_PATH_COLOR, 0.35))
	var emblem := "faction/" + String(EMBLEMS.get(String(wave.get("front", "north")), "north"))
	draw_circle(points[0], hex_size * 0.42, Color(ENEMY_COLOR, 0.5))
	if Art.has(emblem):
		_draw_art(emblem, points[0], hex_size * 0.72, Color(1, 1, 1, 0.6))


func _draw_horde(wave: Dictionary, now: float) -> void:
	var p := WaveMath.progress(wave, now, Game.battles)
	if p.is_empty():
		return
	var pos := HexMath.to_pixel(p.from, hex_size).lerp(HexMath.to_pixel(p.to, hex_size), p.t)
	if wave.status == "marching":
		# The road still ahead, from the horde to its target.
		var trail := PackedVector2Array([pos])
		var ahead := false
		for step in wave.path:
			var cell := Vector2i(int(step[0]), int(step[1]))
			ahead = ahead or cell == p.to
			if ahead:
				trail.append(HexMath.to_pixel(cell, hex_size))
		if trail.size() >= 2:
			_draw_route(trail, HORDE_PATH_COLOR)
		# Outposts it will march onto and burn on the way are targets too.
		for cell in WaveMath.raided_outposts(wave, _standing_outposts(), 0, now):
			_draw_crosshair(HexMath.to_pixel(cell, hex_size), HORDE_PATH_COLOR, 0.7)
	else:
		# Camped at the gates: sit beside the village so both stay visible.
		pos += Vector2(hex_size * 0.42, -hex_size * 0.42)
	var emblem := "faction/" + String(EMBLEMS.get(String(wave.get("front", "north")), "north"))
	if Art.has(emblem):
		draw_circle(pos, hex_size * 0.42, ENEMY_COLOR)
		_draw_art(emblem, pos, hex_size * 0.72)
		return
	draw_circle(pos, hex_size * 0.34, WaveMath.front_color(String(wave.get("front", "north"))))
	draw_arc(pos, hex_size * 0.34, 0.0, TAU, 24, VILLAGE_OUTLINE_COLOR, 2.0)
