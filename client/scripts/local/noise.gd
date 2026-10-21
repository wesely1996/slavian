class_name LocalNoise
extends RefCounted
## 2D simplex noise as the server's simplex-noise 4 builds it from a seeded
## random function (createNoise2D), so a seed gives the same map on both
## sides. Checked against data/fixtures/mapgen-vectors.json.

const F2 := 0.5 * (1.7320508075688772 - 1.0)
const G2 := (3.0 - 1.7320508075688772) / 6.0
const GRAD2: Array[float] = [1, 1, -1, 1, 1, -1, -1, -1, 1, 0, -1, 0, 1, 0, -1, 0, 0, 1, 0, -1, 0, 1, 0, -1]

var _perm := PackedInt32Array()
var _gx := PackedFloat64Array()
var _gy := PackedFloat64Array()


func _init(random: Callable) -> void:
	_perm.resize(512)
	for i in 256:
		_perm[i] = i
	for i in 255:
		var r := i + int(random.call() * (256 - i))
		var aux := _perm[i]
		_perm[i] = _perm[r]
		_perm[r] = aux
	for i in range(256, 512):
		_perm[i] = _perm[i - 256]
	_gx.resize(512)
	_gy.resize(512)
	for i in 512:
		_gx[i] = GRAD2[(_perm[i] % 12) * 2]
		_gy[i] = GRAD2[(_perm[i] % 12) * 2 + 1]


func noise(x: float, y: float) -> float:
	var n0 := 0.0
	var n1 := 0.0
	var n2 := 0.0
	var s := (x + y) * F2
	var i := int(floor(x + s))
	var j := int(floor(y + s))
	var t := (i + j) * G2
	var x0 := x - (i - t)
	var y0 := y - (j - t)
	var i1 := 0
	var j1 := 1
	if x0 > y0:
		i1 = 1
		j1 = 0
	var x1 := x0 - i1 + G2
	var y1 := y0 - j1 + G2
	var x2 := x0 - 1.0 + 2.0 * G2
	var y2 := y0 - 1.0 + 2.0 * G2
	var ii := i & 255
	var jj := j & 255
	var t0 := 0.5 - x0 * x0 - y0 * y0
	if t0 >= 0:
		var gi0 := ii + _perm[jj]
		t0 *= t0
		n0 = t0 * t0 * (_gx[gi0] * x0 + _gy[gi0] * y0)
	var t1 := 0.5 - x1 * x1 - y1 * y1
	if t1 >= 0:
		var gi1 := ii + i1 + _perm[jj + j1]
		t1 *= t1
		n1 = t1 * t1 * (_gx[gi1] * x1 + _gy[gi1] * y1)
	var t2 := 0.5 - x2 * x2 - y2 * y2
	if t2 >= 0:
		var gi2 := ii + 1 + _perm[jj + 1]
		t2 *= t2
		n2 = t2 * t2 * (_gx[gi2] * x2 + _gy[gi2] * y2)
	return 70.0 * (n0 + n1 + n2)
