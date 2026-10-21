class_name LocalLedger
extends RefCounted
## The resource ledger for the local engine: server/src/sim/resources.ts.
## A ledger: {amounts, ratesPerHour, capacity, settledAt (ms)}. Production is
## credited a minute's worth at every whole minute (UTC) since settledAt.

const KINDS := ["wood", "stone", "grain", "iron"]
const MS_PER_MINUTE := 60000


static func minutes_between(from_ms: int, to_ms: int) -> int:
	return floori(to_ms / float(MS_PER_MINUTE)) - floori(from_ms / float(MS_PER_MINUTE))


static func amounts_at(ledger: Dictionary, at: int) -> Dictionary:
	var hours := minutes_between(int(ledger.settledAt), at) / 60.0
	var out := {}
	for kind in KINDS:
		var amount := float(ledger.amounts[kind])
		var rate := float(ledger.ratesPerHour[kind])
		var projected := amount + rate * hours
		if rate > 0:
			out[kind] = maxf(amount, minf(projected, float(ledger.capacity[kind])))
		else:
			out[kind] = maxf(0.0, projected)
	return out


static func settle(ledger: Dictionary, at: int) -> Dictionary:
	var out := ledger.duplicate(true)
	out.amounts = amounts_at(ledger, at)
	out.settledAt = at
	return out


static func with_rates(ledger: Dictionary, at: int, rates: Dictionary, capacity: Dictionary) -> Dictionary:
	var out := settle(ledger, at)
	out.ratesPerHour = rates
	out.capacity = capacity
	return out


static func missing_for(amounts: Dictionary, cost: Dictionary) -> Dictionary:
	var out := {}
	for kind in KINDS:
		out[kind] = maxf(0.0, float(cost[kind]) - float(amounts[kind]))
	return out


## Pays `cost` at `at`; {} with "missing" when there isn't enough.
static func spend(ledger: Dictionary, at: int, cost: Dictionary) -> Dictionary:
	var settled := settle(ledger, at)
	var missing := missing_for(settled.amounts, cost)
	for kind in KINDS:
		if missing[kind] > 0:
			return {"missing": missing}
	for kind in KINDS:
		settled.amounts[kind] = float(settled.amounts[kind]) - float(cost[kind])
	return settled


## Takes up to `amounts` (raiders' loot); never below zero.
static func take(ledger: Dictionary, at: int, amounts: Dictionary) -> Dictionary:
	var settled := settle(ledger, at)
	for kind in KINDS:
		settled.amounts[kind] = maxf(0.0, float(settled.amounts[kind]) - float(amounts[kind]))
	return settled
