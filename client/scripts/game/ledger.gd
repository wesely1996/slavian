class_name Ledger
extends RefCounted
## Client copy of the server's lazy resource ledger (server/src/sim/resources.ts):
## current amount = settled amount + rate * elapsed hours, capped by
## capacity for production and floored at zero. Production is credited once
## a minute: a minute's worth at every whole minute (UTC) since settledAt. Checked against
## data/fixtures/resource-vectors.json on both sides.

const KINDS: Array[String] = ["wood", "stone", "grain", "iron"]


## `resources` is the server's {amounts, ratesPerHour, capacity, settledAt}.
static func amounts_at(resources: Dictionary, at_unix: float) -> Dictionary:
	var settled := TimeUtil.parse_iso(resources.settledAt)
	var hours := maxf(0.0, floorf(at_unix / 60.0) - floorf(settled / 60.0)) / 60.0
	var result := {}
	for kind in KINDS:
		var amount: float = resources.amounts[kind]
		var rate: float = resources.ratesPerHour[kind]
		var projected := amount + rate * hours
		if rate > 0.0:
			result[kind] = maxf(amount, minf(projected, resources.capacity[kind]))
		else:
			result[kind] = maxf(0.0, projected)
	return result


static func can_afford(amounts: Dictionary, cost: Dictionary) -> bool:
	for kind in KINDS:
		if amounts[kind] < cost[kind]:
			return false
	return true


## Seconds until the next minute mark, when production is next credited.
static func seconds_to_next(at_unix: float) -> int:
	return int(ceilf(60.0 - fmod(at_unix, 60.0)))
