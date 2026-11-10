class_name LocalBattle
extends RefCounted
## Battle resolution for the local engine: server/src/sim/battle.ts.
##
## Units are walked in the dictionaries' own order, which follows the
## server's (`LocalStore`), since every target draws from the RNG.

const MAX_RETREAT_AT := 0.95


static func total(units: Dictionary) -> int:
	var n := 0
	for count in units.values():
		n += int(count)
	return n


static func attack_factor(bonuses: Dictionary, family: String) -> float:
	return 1.0 + float(bonuses.get("attack." + family, 0.0)) + float(bonuses.get("attack.all", 0.0))


static func defense_factor(bonuses: Dictionary, family: String, home: bool) -> float:
	return 1.0 + float(bonuses.get("defense." + family, 0.0)) + float(bonuses.get("defense.all", 0.0)) + (float(bonuses.get("homeDefense", 0.0)) if home else 0.0)


## The player's units, with their research: `home` adds the bonus for
## defending one's own village. Stats are {attack, defense, family}, and
## counters when the unit has its own in place of its family's.
static func player_stats(data: Dictionary, bonuses: Dictionary = {}, home := false) -> Callable:
	return func(unit: String) -> Dictionary:
		var def: Dictionary = data.units.units.get(unit, {"attack": 0, "defense": 1, "health": 1, "family": "infantry"})
		var stats := {"family": def.family, "attack": float(def.attack) * attack_factor(bonuses, def.family),
			"defense": float(def.defense) * defense_factor(bonuses, def.family, home), "health": float(def.health)}
		if def.get("counters") != null:
			stats.counters = def.counters
		return stats


static func enemy_stats(data: Dictionary, front: String) -> Callable:
	var units: Dictionary = data.enemies.fronts.get(front, {}).get("units", {})
	return func(unit: String) -> Dictionary:
		var def: Dictionary = units.get(unit, {"attack": 0, "defense": 1, "health": 1, "family": "infantry"})
		return {"family": def.family, "attack": float(def.attack), "defense": float(def.defense), "health": float(def.health)}


static func battle_rng(seed_value: int, battle_id: int, round: int) -> LocalRng:
	return LocalRng.new((seed_value ^ LocalRng.imul(battle_id + 1, 0xcc9e2d51) ^ LocalRng.imul(round + 1, 0x1b873593)) & 0xffffffff)


## A side's forces: its groups ({units, stance, stats?}) when it fights in
## groups, else the side itself as one.
static func _groups(side: Dictionary) -> Array:
	if side.has("groups"):
		return side.groups
	var one := {"units": side.units, "stance": side.stance}
	if side.has("champions"):
		one.champions = side.champions
	return [one]


## battle.ts championOf: a hero's or general's champion at `level`
## (heroes.json champion, generals.champion), growthPerLevel more each level.
static func champion_of(data: Dictionary, id: String, level: int) -> Dictionary:
	var c: Dictionary = data.heroes.champion if id == "hero" else data.heroes.generals.champion
	var f := 1.0 + float(c.growthPerLevel) * maxi(0, level - 1)
	return {"id": id, "attack": float(c.attack) * f, "defense": float(c.defense) * f, "health": float(c.health) * f}


## Kills `from` inflicts on `to` this round, by unit type, for each of
## `to`'s groups, and the champions it strikes down there ({losses, fallen}).
## A side: {units, stance, stats: Callable, home, groups?, champions?}.
static func _kills(data: Dictionary, from: Dictionary, to: Dictionary, rng: LocalRng) -> Dictionary:
	var battle: Dictionary = data.battle
	var strikers := _groups(from)
	var groups := _groups(to)
	var result: Array = []
	var fallen: Array = []
	for g in groups:
		result.append({})
		fallen.append([])
	var targets: Array = []
	var target_total := 0
	for i in groups.size():
		for unit in groups[i].units:
			if int(groups[i].units[unit]) > 0:
				targets.append([i, unit, int(groups[i].units[unit]), null])
				target_total += int(groups[i].units[unit])
	# Champions stand among their men: each is one more to strike at.
	for i in groups.size():
		for c in groups[i].get("champions", []):
			targets.append([i, c.id, 1, c])
			target_total += 1
	if target_total == 0:
		return {"losses": result, "fallen": fallen}
	for t in targets:
		var group: Dictionary = groups[t[0]]
		var target: String = t[1]
		var target_count: int = t[2]
		var champion: Variant = t[3]
		var stats: Dictionary = {"attack": champion.attack, "defense": champion.defense, "health": champion.health, "family": "infantry"} if champion != null \
			else (group.stats if group.has("stats") else to.stats).call(target)
		var damage := 0.0
		for striker in strikers:
			var from_stance: Dictionary = battle.stances[striker.stance]
			var matchup := float(battle.matchups.get(striker.stance, {}).get(group.stance, 1.0))
			var striker_stats: Callable = striker.stats if striker.has("stats") else from.stats
			for unit in striker.units:
				var count := int(striker.units[unit])
				if count <= 0:
					continue
				var attacker: Dictionary = striker_stats.call(unit)
				var counter := float(attacker.get("counters", battle.counters.get(attacker.family, {})).get(stats.family, 1.0))
				damage += count * float(attacker.attack) * float(from_stance.attack) * matchup * counter
			# Its champions strike too, at no family's weakness.
			for c in striker.get("champions", []):
				damage += float(c.attack) * float(from_stance.attack) * matchup
		var share := float(target_count) / target_total
		var variance := 1.0 + float(battle.variance) * (rng.next() * 2.0 - 1.0)
		# Defense is armor, as in an RPG: k / (k + armor) of the damage lands.
		# Each of the target's health that lands (hardened by its stance and
		# by fighting at home) fells one.
		var lands := float(battle.armorConstant) / (float(battle.armorConstant) + maxf(0.0, float(stats.defense)))
		var toughness := maxf(1.0, float(stats.health)) * float(battle.stances[group.stance].defense) * (float(battle.homeBonus) if to.home else 1.0)
		var expected := (damage * share * variance * float(battle.casualtyScale) * lands) / toughness
		# Round randomly so small fights still take losses on average.
		var whole := floori(expected) + (1 if rng.next() < expected - floorf(expected) else 0)
		var dead := mini(target_count, whole)
		if dead > 0 and champion != null:
			fallen[t[0]].append(champion.id)
		elif dead > 0:
			result[t[0]][target] = int(result[t[0]].get(target, 0)) + dead
	return {"losses": result, "fallen": fallen}


static func _merged(losses: Array) -> Dictionary:
	var out := {}
	for l in losses:
		for unit in l:
			out[unit] = int(out.get(unit, 0)) + int(l[unit])
	return out


## Simultaneous: both sides strike with the numbers they had at the start.
## With defender groups, also their losses by group (defenderGroupLosses).
static func resolve_round(data: Dictionary, attacker: Dictionary, defender: Dictionary, rng: LocalRng) -> Dictionary:
	var struck := _kills(data, defender, attacker, rng)
	var by_group := _kills(data, attacker, defender, rng)
	var result := {"attackerLosses": _merged(struck.losses), "defenderLosses": _merged(by_group.losses),
		"attackerFallen": struck.fallen, "defenderFallen": by_group.fallen}
	if defender.has("groups"):
		result.defenderGroupLosses = by_group.losses
	return result


static func subtract_units(units: Dictionary, losses: Dictionary) -> Dictionary:
	return LocalCamps.subtract_units(units, losses)


static func broken(data: Dictionary, stance: String, initial: Dictionary, now: Dictionary, nerve := 1.0) -> bool:
	var base: Variant = data.battle.stances[stance].retreatAt
	if base == null:
		return false
	var retreat_at := minf(MAX_RETREAT_AT, float(base) * nerve)
	var start := total(initial)
	return start > 0 and float(start - total(now)) / start >= retreat_at


## "ongoing", "defended" or "raided", checked after each round. The
## defenders hold if both sides fall at once.
static func battle_outcome(data: Dictionary, input: Dictionary) -> String:
	if total(input.attackerNow) == 0:
		return "defended"
	if total(input.defenderNow) == 0:
		return "raided"
	if broken(data, input.attackerStance, input.attackerInitial, input.attackerNow, float(input.get("attackerNerve", 1.0))):
		return "defended"
	if input.has("defenderGroups"):
		# Defenders in groups, each breaking on its own: they lose once none
		# still stands.
		var standing := false
		for g in input.defenderGroups:
			if total(g.now) > 0 and not broken(data, g.stance, g.initial, g.now):
				standing = true
		if not standing:
			return "raided"
	elif broken(data, input.defenderStance, input.defenderInitial, input.defenderNow):
		return "raided"
	return "defended" if int(input.round) >= int(data.battle.maxRounds) else "ongoing"


## What a victorious horde carries off.
static func raid_loot(data: Dictionary, amounts: Dictionary, attacker_initial: Dictionary, attacker_now: Dictionary, bonuses: Dictionary = {}, loot_factor := 1.0) -> Dictionary:
	var start := total(attacker_initial)
	var surviving := float(total(attacker_now)) / start if start > 0 else 0.0
	var share := minf(1.0, float(data.battle.raidShare) * loot_factor * maxf(0.0, 1.0 + float(bonuses.get("lootTaken", 0.0))))
	return LocalVillage.resources(func(kind: String) -> int: return floori(float(amounts[kind]) * share * surviving + 1e-9))


## A round takes roundMinutes of real time, whatever the world's speed, so
## reinforcements have time to come.
static func round_ms(data: Dictionary, _world_speed := 1.0) -> int:
	return LocalWaves.js_round(float(data.battle.roundMinutes) * 60000.0)
