class_name LocalSmithing
extends RefCounted
## The Blacksmith (data/smithing.json; server sim/smithing.ts,
## commands/smithing.ts, scheduler/smithing.ts): each player forges
## improvements for their own units, one at a time; every level of a line
## adds perLevel to that unit's stat, for all the player's villages and armies.

const BLACKSMITH := "blacksmith"
const LINES := ["attack", "defense", "health", "speed", "burn", "poison"]


## A line that forges an affliction (burn, poison) rather than a stat.
static func is_affliction(line: String) -> bool:
	return line in LocalBattle.AFFLICTIONS


## The lines a unit can be improved along: a stat it has, and an affliction
## for the families (or engines) it serves, for a unit that strikes and
## doesn't already carry it.
static func smith_lines(data: Dictionary, unit: String) -> Array:
	var def: Dictionary = data.units.units.get(unit, {})
	if def.is_empty():
		return []
	return LINES.filter(func(line: String) -> bool:
		if not is_affliction(line):
			return float(def.get(line, 0)) > 0
		var rules: Dictionary = data.smithing.lines[line]
		var serves: bool = def.family in rules.get("families", []) or (rules.get("engines", false) == true and def.get("engine", false) == true)
		return serves and float(def.attack) > 0 and not line in def.get("inflicts", []))


static func line_levels(data: Dictionary, line: String) -> int:
	return int(data.smithing.lines[line].get("levels", data.smithing.levels))


static func smithy_level_for(data: Dictionary, line: String, level: int) -> int:
	var levels: Array = data.smithing.lines[line].get("smithyLevels", data.smithing.smithyLevels)
	return int(levels[level - 1]) if level - 1 < levels.size() else 1


## The level a line's `level` is priced and timed as.
static func priced_level(data: Dictionary, line: String, level: int) -> int:
	return int(data.smithing.lines[line].get("costLevel", 1)) + level - 1


static func smith_level(smithing: Dictionary, unit: String, line: String) -> int:
	return int(smithing.get(unit, {}).get(line, 0))


static func smith_cost(data: Dictionary, unit: String, line: String, level: int) -> Dictionary:
	var def: Dictionary = data.units.units[unit]
	var priced := priced_level(data, line, level)
	var out := {}
	for kind in LocalLedger.KINDS:
		out[kind] = LocalWaves.js_round(float(def.cost[kind]) * float(data.smithing.costFactor) * priced)
	return out


static func smith_ms(data: Dictionary, unit: String, line: String, level: int, world_speed: float, bonuses: Dictionary = {}) -> int:
	var def: Dictionary = data.units.units[unit]
	var hours := (float(data.smithing.hours.base) + float(data.smithing.hours.perTier) * float(def.requiresLevel)) * priced_level(data, line, level)
	return LocalWaves.js_round((hours * 3600000.0 * maxf(0.1, 1.0 + LocalVillage.bonus(bonuses, "smithTime"))) / world_speed)


## Why the line can't be forged (a rule answer), or {"level": next}.
static func next_smith_level(data: Dictionary, smithing: Dictionary, unit: String, line: String, smithy_level: int, busy: bool) -> Dictionary:
	var def: Dictionary = data.units.units.get(unit, {})
	if def.is_empty():
		return LocalVillage.rule("Unknown unit \"%s\"" % unit)
	if not line in smith_lines(data, unit):
		return LocalVillage.rule("The Blacksmith can't improve the %s's %s" % [def.name, line])
	if busy:
		return LocalVillage.rule("Your Blacksmith is busy; one improvement at a time")
	var level := smith_level(smithing, unit, line) + 1
	if level > line_levels(data, line):
		return LocalVillage.rule("The %s's %s is as good as it gets" % [def.name, String(data.smithing.lines[line].name).to_lower()])
	var needs := smithy_level_for(data, line, level)
	if smithy_level < needs:
		return LocalVillage.rule("That needs a Blacksmith of level %d" % needs)
	return {"level": level}


## What the forged levels give: attack.unit.<id>, defense.unit.<id>, ...
static func smithing_bonuses(data: Dictionary, smithing: Dictionary) -> Dictionary:
	var out := {}
	var units: Array = smithing.keys()
	units.sort()
	for unit in units:
		for line in LINES:
			var level := int(smithing[unit].get(line, 0))
			if level > 0:
				out["%s.unit.%s" % [line, unit]] = 1.0 if is_affliction(line) else level * float(data.smithing.perLevel)
	return out


## A unit's speed with its forged harness.
static func unit_speed(data: Dictionary, unit: String, bonuses: Dictionary = {}) -> float:
	return float(data.units.units.get(unit, {}).get("speed", 1)) * (1.0 + LocalVillage.bonus(bonuses, "speed.unit.%s" % unit))


## commands/smithing.ts startSmithingCommand.
static func start(server: LocalServer, world: Dictionary, village: Dictionary, body: Dictionary, now: int) -> Dictionary:
	var data := server.data
	var unit := String(body.get("unit", ""))
	var line := String(body.get("line", ""))
	var smithy := int(village.state.levels.get(BLACKSMITH, 0))
	if smithy < 1:
		return LocalVillage.rule("Build a Blacksmith first")
	var member := LocalResearch.member(world, int(village.ownerAccountId))
	if member.is_empty():
		return LocalVillage.rule("Only a member of this world can forge")
	var next := next_smith_level(data, member.get("smithing", {}), unit, line, smithy, member.get("smithWork") != null)
	if next.has("error"):
		return next
	var level := int(next.level)
	var ledger := LocalLedger.spend(village.state.ledger, now, smith_cost(data, unit, line, level))
	if ledger.has("missing"):
		return ledger
	var completes_at := now + smith_ms(data, unit, line, level, world.speed, LocalVillage.village_bonuses(data, village.state))
	var work := {"unit": unit, "line": line, "level": level, "villageId": village.id, "completesAt": LocalTime.iso(completes_at)}
	member.smithWork = work
	server.schedule(world, completes_at, "smith_done", {"accountId": int(member.accountId)})
	var state: Dictionary = village.state.duplicate(true)
	state.ledger = ledger
	return {"state": state, "work": work}


## scheduler/smithing.ts smith_done.
static func on_smith_done(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var data := server.data
	var account_id := int(event.payload.accountId)
	var member := LocalResearch.member(world, account_id)
	var work: Variant = member.get("smithWork")
	if member.is_empty() or work == null or String(work.completesAt) != LocalTime.iso(int(event.dueAt)):
		return
	var smithing: Dictionary = member.get("smithing", {}).duplicate(true)
	var lines: Dictionary = smithing.get(work.unit, {})
	lines[work.line] = int(work.level)
	smithing[work.unit] = lines
	member.smithing = smithing
	member.smithWork = null
	server.refresh_bonuses(world, account_id, int(event.dueAt), changed)
	LocalInbox.tell(server, world, account_id, {"kind": "build_done", "tier": "digest",
		"title": "The Blacksmith finished: {unit}, {line} {level}",
		"body": "{line} for every {unit} of yours from now on." if is_affliction(String(work.line)) else "{line} for every {unit} of yours: +{share}% from now on.",
		"vars": {"unit": data.units.units.get(work.unit, {}).get("name", work.unit), "line": data.smithing.lines[work.line].name, "level": int(work.level),
			"share": LocalWaves.js_round(int(work.level) * float(data.smithing.perLevel) * 100)}}, int(event.dueAt))
	changed.append(["world"])
