class_name LocalLines
## sim/lines.ts: battle lines and maneuvers (battle.json lines). The smaller
## army sets the width of the line; round 1 is an exchange of missiles; from
## then on the larger side may flank, close a pincer or encircle, and if the
## smaller side destroys its surplus it breaks through.

const ORDER := ["none", "flank", "pincer", "encircle"]
const FAMILIES := ["infantry", "cavalry", "archers"]


## A side's command (sim/lines.ts commandOf): its cap, best general, its
## heroes' best skill ranks, a horde's leader, and its commanders' traits
## added up (maneuver.* effects, within battle.json lines.traitCap).
static func command_of(data: Dictionary, cap: String, leaders: Array, road := false, leader := 0) -> Dictionary:
	var skills := {}
	var general := 0
	var shares := {}
	var add := func(effects: Dictionary) -> void:
		for key in effects:
			var parts := String(key).split(".")
			if parts.size() == 2 and parts[0] == "maneuver" and parts[1] in ["flank", "pincer", "encircle", "breakthrough"]:
				shares[parts[1]] = float(shares.get(parts[1], 0.0)) + float(effects[key])
	for l in leaders:
		var hero: Variant = l.get("hero")
		if hero is Dictionary and not hero.is_empty():
			for id in hero.get("skills", {}):
				skills[id] = maxi(int(skills.get(id, 0)), int(hero.skills[id]))
			var kind: Variant = hero.get("kind")
			if kind != null and data.heroes.roster.has(kind):
				for t in data.heroes.roster[kind].get("traits", []):
					add.call(t.effects)
		var g: Variant = l.get("general")
		if g is Dictionary and not g.is_empty():
			general = maxi(general, int(g.get("level", 0)))
			add.call(LocalGenerals.trait_of(data, int(g.id)).effects)
	var out := {"cap": cap, "general": general, "skills": skills, "leader": leader, "road": road}
	if not shares.is_empty():
		var limit := float(data.battle.lines.traitCap)
		var power := {}
		for k in shares:
			power[k] = maxf(-limit, minf(limit, float(shares[k])))
		out.power = power
	return out


static func no_command() -> Dictionary:
	return {"cap": "encircle", "general": 0, "skills": {}, "leader": 0, "road": false}


static func _power(command: Dictionary, kind: String) -> float:
	return float(command.get("power", {}).get(kind, 0.0))


## The lines input for `round` of a battle set up so (sim/lines.ts linesFor).
static func lines_for(setup: Dictionary, round: int, state: Variant) -> Dictionary:
	return {"opening": round == 1 and not setup.get("noOpening", false), "attacker": setup.attacker, "defender": setup.defender,
		"fort": setup.get("fort"), "bridge": setup.get("bridge", false), "still": setup.get("still", false), "state": state}


## The round's report: the maneuver made, the breakthrough.
static func lines_log(lines: Variant) -> Dictionary:
	var out := {}
	if lines is Dictionary:
		if lines.maneuver != null:
			out.maneuver = lines.maneuver
		if lines.breakthrough != null:
			out.breakthrough = lines.breakthrough
	return out


## A battle's setup with the state the round's lines left (sim/lines.ts withLines).
static func with_lines(setup: Dictionary, lines: Variant) -> Dictionary:
	if not (lines is Dictionary):
		return setup
	var next: Dictionary = lines.state.duplicate()
	for key in next.keys():
		if next[key] == null:
			next.erase(key)
	if next == setup.get("lines", {}):
		return setup
	var out := setup.duplicate()
	if next.is_empty():
		out.erase("lines")
	else:
		out.lines = next
	return out


static func _sum(c: Dictionary) -> int:
	return int(c.infantry) + int(c.cavalry) + int(c.archers)


static func _other(side: String) -> String:
	return "defender" if side == "attacker" else "attacker"


static func _flat(dealt: float) -> Dictionary:
	return {"infantry": dealt, "cavalry": dealt, "archers": dealt}


static func _can(data: Dictionary, input: Dictionary, by: String, kind: String, big: Dictionary, small: Dictionary) -> bool:
	var rules: Dictionary = data.battle.lines
	var command: Dictionary = input[by]
	var ground: Dictionary = input.ground if input.get("ground") is Dictionary else {}
	var hills := int(ground.get("hills", 0)) > 0
	var factor := 1.0
	if command.road:
		factor -= float(rules.road.ratioCut)
	var fort: Variant = input.get("fort")
	if fort == by:
		factor *= float(rules.fort.holderFactor)
	elif fort != null:
		factor *= float(rules.fort.attackerFactor)
	var main := "infantry" if hills else "cavalry"
	var second := "cavalry" if hills else "infantry"
	if kind == "flank":
		return int(big[main]) > 0 and float(big[main]) >= float(rules.flank.ratio) * factor * float(small[main])
	if kind == "pincer":
		if int(ground.get("water", 0)) > 0 or int(ground.get("mountain", 0)) > 0:
			return false
		var cut := int(rules.road.rankCut) if command.road else 0
		var c: Dictionary = rules.commander
		var skills: Dictionary = command.skills
		var fury := int(skills.get("battle_fury", 0))
		var horse := int(skills.get("horse_lord", 0))
		var spear := int(skills.get("spearhead", 0))
		var led: bool = (int(command.general) > 0 and int(command.general) >= int(c.general) - cut) \
			or (fury > 0 and fury >= int(c.battleFury) - cut) \
			or (not hills and horse > 0 and horse >= int(c.horseLord) - cut) \
			or (hills and spear > 0 and spear >= int(c.spearhead) - cut) \
			or (int(command.leader) > 0 and int(command.leader) >= int(c.leader))
		if not led:
			return false
		var pure: bool = int(big[main]) > 0 and float(big[main]) >= float(rules.pincer.ratio) * factor * float(small[main])
		var both := int(big[main]) + int(big[second])
		var mixed: bool = both > 0 and float(both) >= float(rules.pincer.mixedRatio) * factor * float(int(small[main]) + int(small[second]))
		return pure or mixed
	# A fort by the water can't be surrounded.
	if fort == _other(by) and int(ground.get("water", 0)) > 0:
		return false
	return float(_sum(big)) >= float(rules.encircle.ratio) * factor * float(_sum(small))


static func _best(data: Dictionary, input: Dictionary, by: String, big: Dictionary, small: Dictionary) -> Variant:
	var cap := ORDER.find(String(input[by].cap))
	for kind in ["encircle", "pincer", "flank"]:
		if ORDER.find(kind) <= cap and _can(data, input, by, kind, big, small):
			return kind
	return null


static func _shield_bearer(data: Dictionary, command: Dictionary) -> bool:
	return int(command.skills.get("shield_bearer", 0)) >= int(data.battle.lines.shieldBearer.rank)


## The lines for this round (sim/lines.ts battleLines).
static func battle_lines(data: Dictionary, input: Dictionary, attacker: Dictionary, defender: Dictionary) -> Dictionary:
	var rules: Dictionary = data.battle.lines
	var counts := {"attacker": attacker, "defender": defender}
	var state: Dictionary = input.state if input.get("state") is Dictionary else {}
	var line := {"attacker": {"dealt": _flat(1.0), "taken": 1.0}, "defender": {"dealt": _flat(1.0), "taken": 1.0}}
	var ta := _sum(attacker)
	var td := _sum(defender)
	if ta == 0 or td == 0:
		return _done(input, line, state, null, null)
	var big := "attacker" if ta > td else "defender"
	var small := _other(big)
	if input.get("bridge", false):
		var width := maxi(1, floori(int(counts[small].infantry) / 2.0))
		for side in ["attacker", "defender"]:
			var c: Dictionary = counts[side]
			var melee := minf(1.0, float(width) / float(maxi(1, int(c.infantry) + int(c.cavalry))))
			line[side].dealt = {"infantry": melee, "cavalry": melee, "archers": minf(1.0, float(width) / float(maxi(1, int(c.archers))))}
		return _done(input, line, state, null, null)
	var tb := _sum(counts[big])
	var ts := _sum(counts[small])
	if tb > ts:
		line[big].dealt = _flat(float(ts) / float(tb))
	if input.opening:
		return _done(input, line, state, null, null)

	var next: Dictionary = state
	var breakthrough: Variant = null
	var maneuver: Variant = null
	if next.get("active") is Dictionary:
		var by: String = next.active.by
		var kind: String = next.active.kind
		var holds := _can(data, input, by, kind, counts[by], next.active.weak)
		if not holds:
			breakthrough = {"by": _other(by), "kind": kind}
			var keep := kind == "flank" and _shield_bearer(data, input[by])
			var after := next.duplicate()
			after.active = null
			if not keep:
				var spent: Array = next.get("spent", []).duplicate() if next.get("spent") != null else []
				spent.append(by)
				after.spent = spent
			after.breakthrough = {"by": _other(by), "kind": kind, "base": _sum(next.active.weak)}
			if keep:
				after.kept = {"by": by}
			next = after
		elif by == big and _can(data, input, by, kind, counts[by], counts[_other(by)]):
			maneuver = {"by": by, "kind": kind}
		else:
			var after := next.duplicate()
			after.active = null
			next = after
	var spent_now: Array = next.get("spent", []) if next.get("spent") != null else []
	var through_now: Variant = next.get("breakthrough")
	if maneuver == null and not (next.get("active") is Dictionary) and not (next.get("kept") is Dictionary) and not input.get("still", false) \
			and not big in spent_now and not (through_now is Dictionary and through_now.by == small):
		var kind: Variant = _best(data, input, big, counts[big], counts[small])
		if kind != null:
			maneuver = {"by": big, "kind": kind}
			next = next.duplicate()
			next.active = {"by": big, "kind": kind, "weak": counts[small].duplicate()}
	if maneuver == null and next.get("kept") is Dictionary and next.kept.by == big:
		maneuver = {"by": big, "kind": "flank"}

	if maneuver != null:
		var x := tb - ts
		var boost := 1.0 + _power(input[big], maneuver.kind)
		if maneuver.kind == "encircle":
			line[big] = {"dealt": _flat(float(rules.encircle.dealt) * boost), "taken": float(rules.encircle.taken)}
		else:
			var r: Dictionary = rules[maneuver.kind]
			line[big] = {"dealt": _flat((ts + float(r.surplusDealt) * boost * x) / tb), "taken": (ts + float(r.surplusTaken) * x) / tb}
		if _shield_bearer(data, input[small]):
			line[small] = {"dealt": line[small].dealt, "taken": float(line[small].taken) * float(rules.shieldBearer.taken)}
	var through: Variant = next.get("breakthrough")
	if through is Dictionary:
		var side: String = through.by
		var share := minf(1.0, float(through.base) / float(maxi(1, _sum(counts[side]))))
		var dealt := (float(rules.encircle.dealt) if through.kind == "encircle" else float(rules[through.kind].surplusDealt)) + float(rules.breakthrough.dealtBonus) * (1.0 + _power(input[side], "breakthrough"))
		var taken := float(rules.encircle.taken) if through.kind == "encircle" else float(rules[through.kind].surplusTaken)
		var d := 1.0 + (dealt - 1.0) * share
		var was: Dictionary = line[side].dealt
		line[side] = {"dealt": {"infantry": float(was.infantry) * d, "cavalry": float(was.cavalry) * d, "archers": float(was.archers) * d},
			"taken": float(line[side].taken) * (1.0 - (1.0 - taken) * share)}
		if _shield_bearer(data, input[side]) and maneuver == null:
			line[side] = {"dealt": line[side].dealt, "taken": float(line[side].taken) * float(rules.shieldBearer.taken)}
	return _done(input, line, next, maneuver, breakthrough)


static func _done(input: Dictionary, line: Dictionary, state: Dictionary, maneuver: Variant, breakthrough: Variant) -> Dictionary:
	return {"opening": input.opening, "attacker": line.attacker, "defender": line.defender, "state": state, "maneuver": maneuver, "breakthrough": breakthrough}
