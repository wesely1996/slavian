class_name LocalStore
extends RefCounted
## The order the server sees object keys in. It keeps units, plots and the
## like as jsonb, which stores an object's keys shortest first, then in byte
## order, and JavaScript walks a loaded object in that order. The local
## engine puts what the server keeps as jsonb in that order wherever the
## server would load it (LocalServer.as_stored), and builds dictionaries in
## the order the server's code builds objects, so loops that feed the RNG
## or a sum see keys in the same order.


static func _before(a: String, b: String) -> bool:
	var la := a.to_utf8_buffer().size()
	var lb := b.to_utf8_buffer().size()
	return la < lb or (la == lb and a < b)


## A dictionary's keys in jsonb order.
static func keys(value: Dictionary) -> Array:
	var out: Array = value.keys()
	out.sort_custom(_before)
	return out


## A copy with every dictionary inside in jsonb order, as the value reads
## after the server saved and loaded it.
static func stored(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		for k in keys(value):
			out[k] = stored(value[k])
		return out
	if value is Array:
		return value.map(stored)
	return value
