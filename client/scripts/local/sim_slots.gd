class_name LocalSlots
## sim/slots.ts: army slots (units.json armySlots). Every unit takes its
## `slots` of its owner's army slots; each standing village gives `base` plus
## `perHallLevel` for each Elder's Hall level. No unit is trained beyond them.


## The slots these units take.
static func unit_slots(data: Dictionary, units: Dictionary) -> int:
	var n := 0
	for unit in units:
		n += int(units[unit]) * int(data.units.units.get(unit, {}).get("slots", 0))
	return n


## scheduler/slots.ts armySlotsOf: a player's slots, used and given.
static func of(data: Dictionary, world: Dictionary, account_id: int) -> Dictionary:
	var rules: Dictionary = data.units.armySlots
	var used := 0
	var cap := 0
	var ids := {}
	for v in world.villages:
		if v.ownerAccountId == null or int(v.ownerAccountId) != account_id:
			continue
		ids[int(v.id)] = true
		used += unit_slots(data, v.state.garrison)
		for batch in v.state.training:
			used += int(batch.count) * int(data.units.units.get(batch.unit, {}).get("slots", 0))
		if v.ruin == null:
			cap += int(rules.base) + int(rules.perHallLevel) * int(v.state.levels.get(LocalVillage.HALL, 0))
	for a in world.armies:
		if a.ownerAccountId != null and int(a.ownerAccountId) == account_id and a.status != "done":
			used += unit_slots(data, a.units)
	for c in world.get("caravans", []):
		if ids.has(int(c.villageId)) and c.status != "done":
			used += unit_slots(data, c.get("escort", {}))
	return {"used": used, "cap": cap}


## Training `count` more of `unit` must fit in the slots left: an error, or {}.
static func check(data: Dictionary, slots: Dictionary, unit: String, count: int) -> Dictionary:
	var need := count * int(data.units.units.get(unit, {}).get("slots", 0))
	if need == 0 or int(slots.used) + need <= int(slots.cap):
		return {}
	var left := maxi(0, int(slots.cap) - int(slots.used))
	return LocalVillage.rule("Your army has %d of %d slots free; %d %s take %d. Raise an Elder's Hall or found a village for more." % [left, int(slots.cap), count, String(data.units.units.get(unit, {}).get("name", unit)), need])
