class_name MapGenerator
extends RefCounted
## M0 placeholder world generator so the map view has something to show.
## From M1 the server generates the world (it is authoritative) and the
## client only renders what it receives.

enum Front { NORTH, EAST, SOUTH, WEST }

const EDGE_BELT_WIDTH := 2
const START_RING := 2


class MapData:
	extends RefCounted
	var radius: int
	var terrain: Dictionary[Vector2i, Terrain.Type] = {}
	var start_sites: Array[Vector2i] = []
	var active_fronts: Array[Front] = []


## PLAN.md §4.1: ~10 for 1-2 players, scaling up to ~16 for 6.
static func radius_for(player_count: int) -> int:
	return 10 if player_count <= 2 else roundi(10 + (player_count - 2) * 1.5)


## PLAN.md §4.4: solo faces North + South, 2 players add East, 3+ all four.
static func active_fronts_for(player_count: int) -> Array[Front]:
	if player_count <= 1:
		return [Front.NORTH, Front.SOUTH]
	if player_count == 2:
		return [Front.NORTH, Front.SOUTH, Front.EAST]
	return [Front.NORTH, Front.EAST, Front.SOUTH, Front.WEST]


## Which front a hex faces, by its angle from the centre (y grows downward).
static func front_of(cell: Vector2i) -> Front:
	var p := HexMath.to_pixel(cell, 1.0)
	var angle := rad_to_deg(atan2(p.y, p.x))
	if angle >= -135.0 and angle < -45.0:
		return Front.NORTH
	if angle >= -45.0 and angle < 45.0:
		return Front.EAST
	if angle >= 45.0 and angle < 135.0:
		return Front.SOUTH
	return Front.WEST


static func generate(map_seed: int, player_count: int) -> MapData:
	var map := MapData.new()
	map.radius = radius_for(player_count)
	map.active_fronts = active_fronts_for(player_count)

	var elevation := FastNoiseLite.new()
	elevation.seed = map_seed
	elevation.frequency = 0.09
	var moisture := FastNoiseLite.new()
	moisture.seed = map_seed + 7919
	moisture.frequency = 0.07

	var center := Vector2i.ZERO
	for cell in HexMath.spiral(center, map.radius):
		var dist := HexMath.distance(cell, center)
		var p := HexMath.to_pixel(cell, 1.0)
		var e := elevation.get_noise_2dv(p)
		var m := moisture.get_noise_2dv(p)
		var type: Terrain.Type
		if dist == 0:
			type = Terrain.Type.HOLY_CITY
		elif dist > map.radius - EDGE_BELT_WIDTH:
			type = _edge_terrain(front_of(cell), map.active_fronts, dist == map.radius, m)
		else:
			type = _interior_terrain(e, m)
			if dist <= START_RING and not _is_settleable(type):
				type = Terrain.Type.PLAINS
		map.terrain[cell] = type

	# Spread players evenly around the starting ring.
	var ring := HexMath.ring(center, START_RING)
	for i in player_count:
		map.start_sites.append(ring[roundi(i * ring.size() / float(player_count)) % ring.size()])
	return map


static func _interior_terrain(e: float, m: float) -> Terrain.Type:
	if e > 0.45:
		return Terrain.Type.MOUNTAIN
	if e > 0.2:
		return Terrain.Type.HILLS
	if e < -0.4 and m > 0.0:
		return Terrain.Type.LAKE
	if e < -0.15 and m > 0.3:
		return Terrain.Type.SWAMP
	if m > 0.05:
		return Terrain.Type.FOREST
	return Terrain.Type.PLAINS


static func _edge_terrain(front: Front, active: Array[Front], outermost: bool, m: float) -> Terrain.Type:
	if front not in active:
		return Terrain.Type.OCEAN
	match front:
		Front.NORTH:
			return Terrain.Type.ICE if outermost and m < 0.1 else Terrain.Type.DARK_FOREST
		Front.EAST:
			return Terrain.Type.STEPPE
		_:
			return Terrain.Type.HALLOWED


static func _is_settleable(type: Terrain.Type) -> bool:
	return type in [Terrain.Type.PLAINS, Terrain.Type.FOREST, Terrain.Type.HILLS]
