class_name HexMap
extends Node2D
## Draws the current world's map: the ground (MapGround, a shaded mesh where
## terrains blend into each other) and what stands on it (MapFeatures: woods,
## peaks, hills), both behind; then rivers, roads, villages, armies and enemy
## hordes from the art in client/art/art.json (docs/art-style.md), falling
## back to plain shapes where a piece is missing. Owners show by colour:
## green yours, blue allies', red enemies'. Redraws when something changes,
## and on every UI tick while a horde is on the move.

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
const RIVER_COLOR := Color("#4a86a3")
const RIVER_BANK := Color(0.1, 0.16, 0.12, 0.45)
const RIVER_GLINT := Color(0.75, 0.88, 0.92, 0.45)
const PLANK_COLOR := Color("#b07a45")
const ROAD_COLOR := Color("#a8906a")
const ROAD_EDGE := Color(0.18, 0.14, 0.09, 0.35)
## Each front's emblem (art id "faction/<emblem>").
const EMBLEMS := {"north": "north", "east": "east", "south": "order", "west": "order"}

@export var hex_size := 48.0

var radius := 0
var selected := Vector2i.MAX
var _ground: MapGround
var _features: MapFeatures


func _ready() -> void:
	_ground = MapGround.new()
	_ground.show_behind_parent = true
	add_child(_ground)
	_features = MapFeatures.new()
	_features.show_behind_parent = true
	add_child(_features)


func refresh() -> void:
	var map: Variant = Game.world.get("map")
	radius = int(map.radius) if map is Dictionary else 0
	if _ground != null:
		_ground.build(Game.terrain, hex_size)
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
	var extent := HexMath.to_pixel(Vector2i(radius, 0), hex_size).x
	return Rect2(-extent, -extent, extent * 2.0, extent * 2.0)


func _draw() -> void:
	for road in Game.roads:
		_draw_road(road)
	for edge in Game.rivers:
		_draw_river(edge)

	if Game.terrain.has(Vector2i.ZERO):
		if not _draw_art("settlement/holy_city", Vector2.ZERO, hex_size * 1.5):
			draw_circle(Vector2.ZERO, hex_size * 0.45, HOLY_CITY_COLOR)
	for village in Game.villages.values():
		for plot in Rules.outpost_plots(village):
			_draw_outpost(Rules.outpost_hex(plot), int(village.plots[plot].level), Game.is_mine(village))
	for village in Game.villages.values():
		_draw_village(village)

	var now := Game.server_now()
	for caravan in Game.caravans:
		var p := CaravanMath.progress(caravan, now)
		if Game.is_mine(Game.villages.get(int(caravan.villageId), {})):
			_draw_trail(caravan.get("path", []), p, caravan.status == "returning", CARAVAN_COLOR)
		if not p.is_empty():
			var pos := HexMath.to_pixel(p.from, hex_size).lerp(HexMath.to_pixel(p.to, hex_size), p.t)
			draw_circle(pos, hex_size * 0.2, CARAVAN_COLOR)
			draw_arc(pos, hex_size * 0.2, 0.0, TAU, 16, VILLAGE_OUTLINE_COLOR, 2.0)
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
		_draw_fort(fort)
	for camp in Game.camps:
		_draw_camp(camp)
	for site in Game.sites:
		if site.status == "unexplored":
			_draw_site(site)
	for army in Game.armies:
		_draw_army(army, now)
	for hero in Game.heroes:
		_draw_hero(hero, now)
	for wave in Game.waves:
		if wave.status == "scheduled" and wave.get("forecast") is Dictionary:
			_draw_forecast(wave)
	for wave in WaveMath.visible_waves(Game.waves):
		_draw_horde(wave, now)

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


## A road between two hex centres: a dirt track, faded while being built.
## A road, wider at each level; faded while first being built.
func _draw_road(road: Array) -> void:
	var a := HexMath.to_pixel(Vector2i(int(road[0]), int(road[1])), hex_size)
	var b := HexMath.to_pixel(Vector2i(int(road[2]), int(road[3])), hex_size)
	var tint := Color(1, 1, 1, 0.45) if String(road[4]) == "building" else Color.WHITE
	var wide := 1.0 + 0.3 * float((int(road[5]) if road.size() > 5 else 1) - 1)
	draw_line(a, b, ROAD_EDGE * Color(1, 1, 1, tint.a), hex_size * 0.15 * wide, true)
	draw_line(a, b, ROAD_COLOR * tint, hex_size * 0.09 * wide, true)
	draw_circle(a, hex_size * 0.045 * wide, ROAD_COLOR * tint)
	draw_circle(b, hex_size * 0.045 * wide, ROAD_COLOR * tint)


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
	if String(edge[4]) == "none":
		return
	var mid: Vector2 = (ends[0] + ends[1]) / 2.0
	var across := (HexMath.to_pixel(b, hex_size) - HexMath.to_pixel(a, hex_size)).normalized()
	var tint := Color.WHITE if String(edge[4]) == "standing" else Color(1, 1, 1, 0.5)
	draw_line(mid - across * hex_size * 0.3, mid + across * hex_size * 0.3, VILLAGE_OUTLINE_COLOR * tint, hex_size * 0.3)
	draw_line(mid - across * hex_size * 0.27, mid + across * hex_size * 0.27, PLANK_COLOR * tint, hex_size * 0.22)


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


func _draw_outpost(cell: Vector2i, level: int, mine: bool) -> void:
	var c := HexMath.to_pixel(cell, hex_size)
	var side := MINE_COLOR if mine else ALLY_COLOR
	if Art.has("map/outpost"):
		_draw_ring(c + Vector2(0, hex_size * 0.32), hex_size * 0.9, side)
		_draw_art("map/outpost", c, hex_size * 0.85, Color(1, 1, 1, 0.55) if level <= 0 else Color.WHITE)
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


## The id of the army whose marker is under `local` (0: none): the
## nearest, your own before others'.
func army_at(local: Vector2, now: float) -> int:
	var best := 0
	var best_d := INF
	var best_mine := false
	for army in Game.armies:
		var pos := army_position(army, now)
		if pos == Vector2.INF or pos.distance_to(local) > hex_size * 0.3:
			continue
		var d := pos.distance_to(local)
		var mine := int(army.get("ownerAccountId", -1)) == Game.my_account_id()
		if (mine and not best_mine) or (mine == best_mine and d < best_d):
			best = int(army.id)
			best_d = d
			best_mine = mine
	return best


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
	if Art.has("unit/" + ArmyText.main_unit(army)):
		draw_circle(pos, hex_size * 0.27, side)
		_draw_art("unit/" + ArmyText.main_unit(army), pos, hex_size * 0.46)
		return
	var r := hex_size * 0.2
	var shield := PackedVector2Array([pos + Vector2(-r, -r), pos + Vector2(r, -r), pos + Vector2(r, r * 0.3), pos + Vector2(0, r * 1.2), pos + Vector2(-r, r * 0.3)])
	draw_colored_polygon(shield, ARMY_COLOR)
	shield.append(shield[0])
	draw_polyline(shield, VILLAGE_OUTLINE_COLOR, 2.0)


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


## A bandit camp or monster lair: a tent in its faction's colour.
func _draw_camp(camp: Dictionary) -> void:
	var c := HexMath.to_pixel(Vector2i(int(camp.q), int(camp.r)), hex_size)
	if Art.has("map/camp_" + String(camp.kind)):
		_draw_ring(c + Vector2(0, hex_size * 0.4), hex_size * 1.2, ENEMY_COLOR)
		_draw_art("map/camp_" + String(camp.kind), c, hex_size * 1.15)
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
	if fort.status == "standing":
		_draw_grain_bar(c + Vector2(0, hex_size * 0.62), float(fort.get("grain", 0)) / FieldRules.grain_capacity(Game.data, fort.get("kind", "fort")))
	_draw_fort_body(fort, c)


## A grain gauge under a store: gold for what it holds.
func _draw_grain_bar(at: Vector2, full: float) -> void:
	var w := hex_size * 0.8
	var h := hex_size * 0.1
	var box := Rect2(at - Vector2(w / 2.0, h / 2.0), Vector2(w, h))
	draw_rect(box, Color(0, 0, 0, 0.55))
	draw_rect(Rect2(box.position, Vector2(w * clampf(full, 0.0, 1.0), h)), GRAIN_COLOR)
	draw_rect(box, VILLAGE_OUTLINE_COLOR, false, 1.5)


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
		# Outposts it will burn on the way are targets too.
		var reach := int(Game.data.enemies.fronts[String(wave.get("front", "north"))].personality.raidReach)
		for cell in WaveMath.raided_outposts(wave, _standing_outposts(), reach, now):
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
