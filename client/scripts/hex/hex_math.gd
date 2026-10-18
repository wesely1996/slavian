class_name HexMath
extends RefCounted
## Hex grid math: axial coordinates stored as Vector2i(q, r), pointy-top
## layout, y grows downward. Must match server/src/sim/hex.ts; both are
## checked against data/fixtures/hex-vectors.json.

## E, NE, NW, W, SW, SE
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]
const SQRT3 := 1.7320508075688772


@warning_ignore("integer_division")
static func distance(a: Vector2i, b: Vector2i) -> int:
	var d := a - b
	return (absi(d.x) + absi(d.y) + absi(d.x + d.y)) / 2


static func neighbors(h: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for d in DIRECTIONS:
		result.append(h + d)
	return result


static func ring(center: Vector2i, radius: int) -> Array[Vector2i]:
	if radius == 0:
		return [center]
	var result: Array[Vector2i] = []
	# Start at the SW corner and walk the six sides.
	var current := center + DIRECTIONS[4] * radius
	for d in DIRECTIONS:
		for _step in radius:
			result.append(current)
			current += d
	return result


static func spiral(center: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for k in radius + 1:
		result.append_array(ring(center, k))
	return result


static func to_pixel(h: Vector2i, size: float) -> Vector2:
	return Vector2(size * (SQRT3 * h.x + SQRT3 / 2.0 * h.y), size * 1.5 * h.y)


static func round_axial(q: float, r: float) -> Vector2i:
	var s := -q - r
	var rq := roundf(q)
	var rr := roundf(r)
	var rs := roundf(s)
	var dq := absf(rq - q)
	var dr := absf(rr - r)
	var ds := absf(rs - s)
	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	return Vector2i(int(rq), int(rr))


static func from_pixel(p: Vector2, size: float) -> Vector2i:
	var q := (SQRT3 / 3.0 * p.x - p.y / 3.0) / size
	var r := (2.0 / 3.0 * p.y) / size
	return round_axial(q, r)


## Corner points of a pointy-top hex centred at `center`.
static func corners(center: Vector2, size: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 6:
		var angle := deg_to_rad(60.0 * i - 30.0)
		points.append(center + Vector2(cos(angle), sin(angle)) * size)
	return points
