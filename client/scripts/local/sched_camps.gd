class_name LocalCamps
extends RefCounted
## Bandit camps and monster lairs for the local engine: server/src/sim/camps.ts
## and scheduler/camps.ts.


## A wave of the camp's front sets out: part of the camp goes with it.
static func feed(data: Dictionary, units: Dictionary) -> Dictionary:
	var sent := {}
	for unit in units:
		var s := floori(int(units[unit]) * float(data.camps.feed.share))
		if s > 0:
			sent[unit] = s
	return {"sent": sent, "kept": subtract_units(units, sent)}


static func add_units(a: Dictionary, b: Dictionary) -> Dictionary:
	var sum := a.duplicate()
	for unit in b:
		sum[unit] = int(sum.get(unit, 0)) + int(b[unit])
	return sum


## sim/battle.ts subtractUnits: what is left, without the units gone.
static func subtract_units(units: Dictionary, losses: Dictionary) -> Dictionary:
	var left := {}
	for unit in units:
		var remaining := int(units[unit]) - int(losses.get(unit, 0))
		if remaining > 0:
			left[unit] = remaining
	return left


static func total(units: Dictionary) -> int:
	var n := 0
	for count in units.values():
		n += int(count)
	return n


## Camps of a wave's front send part of themselves along (campsJoin).
static func camps_join(server: LocalServer, world: Dictionary, wave: Dictionary) -> void:
	var composition: Dictionary = wave.composition
	var joined := false
	var camps: Array = world.camps.filter(func(c: Dictionary) -> bool: return c.status == "active")
	camps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	for camp in camps:
		if camp.front != wave.front:
			continue
		var fed := feed(server.data, camp.units)
		if total(fed.sent) == 0:
			continue
		composition = add_units(composition, fed.sent)
		camp.units = fed.kept
		joined = true
	if joined:
		wave.composition = composition
		wave.initial = composition.duplicate()
