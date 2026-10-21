class_name LocalRng
extends RefCounted
## The server's seeded PRNG (server/src/sim/rng.ts, mulberry32), bit for bit:
## 32-bit unsigned arithmetic kept in GDScript's 64-bit ints. Checked against
## data/fixtures/mapgen-vectors.json.

const MASK := 0xffffffff
var _state := 0


func _init(seed_value: int) -> void:
	_state = seed_value & MASK


## The next float in [0, 1).
func next() -> float:
	_state = (_state + 0x6d2b79f5) & MASK
	var t := _state
	t = imul(t ^ (t >> 15), t | 1)
	t = t ^ ((t + imul(t ^ (t >> 7), t | 61)) & MASK)
	return float((t ^ (t >> 14)) & MASK) / 4294967296.0


## Math.imul as unsigned 32 bits: the low 32 bits of a * b.
static func imul(a: int, b: int) -> int:
	a &= MASK
	b &= MASK
	var low := (a & 0xffff) * b
	var high := ((a >> 16) * b) & 0xffff
	return (low + (high << 16)) & MASK


## A Callable for code written against `() => number`.
func callable() -> Callable:
	return next
