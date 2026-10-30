class_name LocalReserve
extends RefCounted
## The military reserve for the local engine (server/src/sim/reserve.ts):
## grain kept for armies in the military buildings, apart from the granary.
## An army leaving a settlement takes its grain from the reserve alone;
## troops in a village eat from the granary. Grain an army brings in goes
## into it first. It tops itself up from the granary when a building
## finishes a level, a training batch is done, and an army comes in.


## Grain the reserve keeps at most: `grainPerLevel` for each level of each
## military building.
static func capacity(data: Dictionary, plots: Dictionary) -> float:
	var levels := 0
	for plot in plots.values():
		if plot.get("building") != null and String(plot.building) in data.armies.reserve.buildings:
			levels += int(plot.level)
	return float(levels) * float(data.armies.reserve.grainPerLevel)


static func of(state: Dictionary) -> float:
	return float(state.get("reserve", 0))


static func _grain_only(grain: float) -> Dictionary:
	return {"wood": 0, "stone": 0, "grain": grain, "iron": 0}


## Fills the reserve from the granary; over its capacity (a building lost),
## the rest goes back into the granary.
static func top_up(data: Dictionary, state: Dictionary, at: int) -> Dictionary:
	var cap := capacity(data, state.plots)
	var reserve := of(state)
	if reserve > cap:
		state.reserve = cap
		state.ledger = LocalLogistics.receive(state.ledger, at, _grain_only(reserve - cap)).ledger
		return state
	var moved := minf(cap - reserve, float(LocalLedger.amounts_at(state.ledger, at).grain))
	if moved <= 0:
		return state
	state.reserve = reserve + moved
	state.ledger = LocalLedger.spend(state.ledger, at, _grain_only(moved))
	return state


## Grain an army leaving takes, from the reserve alone: the granary is not
## touched.
static func take_for_army(state: Dictionary, grain: float) -> Dictionary:
	if grain > 0:
		state.reserve = maxf(0.0, of(state) - grain)
	return state


## Grain an army brings in: into the reserve first, the rest into the
## granary (as far as it holds it).
static func store_from_army(data: Dictionary, state: Dictionary, grain: float, at: int) -> Dictionary:
	if grain <= 0:
		return state
	var room := maxf(0.0, capacity(data, state.plots) - of(state))
	var to_reserve := minf(grain, room)
	state.reserve = of(state) + to_reserve
	if grain - to_reserve > 0:
		state.ledger = LocalLogistics.receive(state.ledger, at, _grain_only(grain - to_reserve)).ledger
	return state
