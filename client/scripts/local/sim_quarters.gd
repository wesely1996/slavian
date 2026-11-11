class_name LocalQuarters
extends RefCounted
## Armies quartered in a settlement, fort or supply point, for the local
## engine (server/src/sim/quarters.ts): the place feeds them
## `quarters.upkeep` of their upkeep from its granary, and their own grain
## keeps. It feeds them down to its floor: forts and supply points to the
## last grain, settlements to `quarters.settlementFloor` of their grain
## storage, unless the owner sets another floor. An army setting off from
## such a place fills up to its full supply, down to the same floor.

const HOUR_MS := 3600000.0


## How low a settlement's grain may fall for armies.
static func settlement_floor(data: Dictionary, floor_value: Variant, grain_capacity: float) -> float:
	return float(floor_value) if floor_value != null else floorf(grain_capacity * float(data.armies.quarters.settlementFloor))


## How low a fort's or supply point's grain may fall for armies.
static func store_floor(floor_value: Variant) -> float:
	return float(floor_value) if floor_value != null else 0.0


static func spare_grain(grain: float, floor_value: float) -> float:
	return maxf(0.0, grain - floor_value)


## Grain a place feeds an army quartered in it per real hour.
static func rate(data: Dictionary, units: Dictionary, world_speed: float) -> float:
	return LocalSupply.army_upkeep(data, units, world_speed) * float(data.armies.quarters.upkeep)


## What a quartered army has eaten of the place's grain since `since`.
static func owed(data: Dictionary, units: Dictionary, since: int, at: int, world_speed: float) -> float:
	return (rate(data, units, world_speed) * maxf(0.0, float(at - since))) / HOUR_MS


## A game hour in real ms: how often a quartered army's place is charged.
static func tick_ms(world_speed: float) -> int:
	return LocalWaves.js_round(HOUR_MS / world_speed)
