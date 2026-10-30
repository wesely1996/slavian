class_name LocalSupply
extends RefCounted
## Field armies carry their own grain, for the local engine
## (server/src/sim/supply.ts). An army: {units, supply (grain at supplyAt),
## supplyAt (ms), hungrySince (ms or null)}.

const HOUR_MS := 3600000.0


static func army_upkeep(data: Dictionary, units: Dictionary, world_speed: float) -> float:
	return LocalVillage.upkeep_per_hour(data, units, world_speed)


## The grain an army carries when full: each unit its own `supplyHours`
## game hours of its upkeep, and a wagon its `supplyGrain` on top
## (data/units.json).
static func full_supply(data: Dictionary, units: Dictionary) -> float:
	var total := 0.0
	for unit in units:
		var def: Variant = data.units.units.get(unit)
		if def != null:
			total += (float(def.upkeepPerHour) * float(def.supplyHours) + float(def.get("supplyGrain", 0))) * int(units[unit])
	return total


static func supply_left(data: Dictionary, army: Dictionary, at: int, world_speed: float) -> float:
	var rate := army_upkeep(data, army.units, world_speed)
	return maxf(0.0, float(army.supply) - (rate * (at - int(army.supplyAt))) / HOUR_MS)


## When the food runs (or ran) out at the present rate (null: it eats nothing).
static func out_of_food_at(data: Dictionary, army: Dictionary, world_speed: float) -> Variant:
	if army.get("hungrySince") != null:
		return int(army.hungrySince)
	var rate := army_upkeep(data, army.units, world_speed)
	if rate <= 0:
		return null
	return int(army.supplyAt) + ceili((float(army.supply) * HOUR_MS) / rate)


static func hungry(data: Dictionary, army: Dictionary, at: int, world_speed: float) -> bool:
	var out: Variant = out_of_food_at(data, army, world_speed)
	return out != null and int(out) <= at


## The army's supply as of `at`, keeping when the food ran out.
static func settle(data: Dictionary, army: Dictionary, at: int, world_speed: float) -> void:
	var out: Variant = out_of_food_at(data, army, world_speed)
	var left := supply_left(data, army, at, world_speed)
	army.hungrySince = out if out != null and int(out) <= at else null
	army.supply = left
	army.supplyAt = at


## Grain added to an army's supply (settled first): it is fed again.
static func add(data: Dictionary, army: Dictionary, grain: float, at: int, world_speed: float) -> void:
	settle(data, army, at, world_speed)
	if grain <= 0:
		return
	army.supply = float(army.supply) + grain
	army.hungrySince = null


## An army setting off carries no more than its full supply: what its
## fallen left over while it stood still is left behind (settled first).
## Whether any was left.
static func trim(data: Dictionary, army: Dictionary, at: int, world_speed: float) -> bool:
	var full := full_supply(data, army.units)
	if supply_left(data, army, at, world_speed) <= full:
		return false
	settle(data, army, at, world_speed)
	army.supply = full
	return true


static func room(data: Dictionary, army: Dictionary, at: int, world_speed: float) -> float:
	return maxf(0.0, full_supply(data, army.units) - supply_left(data, army, at, world_speed))


## When hunger starts to kill, when the army is lost, and how often it
## strikes between, in ms ({} while it eats nothing).
static func _times(data: Dictionary, army: Dictionary, world_speed: float) -> Dictionary:
	var out: Variant = out_of_food_at(data, army, world_speed)
	if out == null:
		return {}
	var a: Dictionary = data.armies.attrition
	return {"start": int(out) + LocalWaves.js_round((float(a.lossAfterHours) * HOUR_MS) / world_speed),
		"end": int(out) + LocalWaves.js_round((float(a.lostAfterHours) * HOUR_MS) / world_speed),
		"tick": LocalWaves.js_round((float(a.checkHours) * HOUR_MS) / world_speed)}


static func next_check(data: Dictionary, army: Dictionary, at: int, world_speed: float) -> Variant:
	var t := _times(data, army, world_speed)
	if t.is_empty():
		return null
	var next := int(t.start)
	if at >= int(t.start):
		next = int(t.start) + (floori(float(at - int(t.start)) / int(t.tick)) + 1) * int(t.tick)
	return mini(next, int(t.end))


## What hunger does at `at`: {lost, losses}.
static func strikes(data: Dictionary, army: Dictionary, at: int, world_speed: float) -> Dictionary:
	var t := _times(data, army, world_speed)
	var losses := {}
	if t.is_empty() or at < int(t.start):
		return {"lost": false, "losses": losses}
	if at >= int(t.end):
		return {"lost": true, "losses": army.units.duplicate()}
	for unit in army.units:
		var n := int(army.units[unit])
		if n > 0:
			losses[unit] = mini(n, ceili(n * float(data.armies.attrition.lossShare)))
	return {"lost": false, "losses": losses}


static func speed_factor(data: Dictionary, army: Variant, at: int, world_speed: float) -> float:
	return float(data.armies.attrition.slowFactor) if army != null and hungry(data, army, at, world_speed) else 1.0
