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
		var def: Dictionary = data.units.units.get(unit, {"attack": 0, "defense": 1, "family": "infantry"})
		var stats := {"family": def.family, "attack": float(def.attack) * attack_factor(bonuses, def.family),
			"defense": float(def.defense) * defense_factor(bonuses, def.family, home)}
		if def.get("counters") != null:
			stats.counters = def.counters
		return stats


static func enemy_stats(data: Dictionary, front: String) -> Callable:
	var units: Dictionary = data.enemies.fronts.get(front, {}).get("units", {})
	return func(unit: String) -> Dictionary:
		var def: Dictionary = units.get(unit, {"attack": 0, "defense": 1, "family": "infantry"})
		return {"family": def.family, "attack": float(def.attack), "defense": float(def.defense)}


static func battle_rng(seed_value: int, battle_id: int, round: int) -> LocalRng:
	return LocalRng.new((seed_value ^ LocalRng.imul(battle_id + 1, 0xcc9e2d51) ^ LocalRng.imul(round + 1, 0x1b873593)) & 0xffffffff)


## Kills `from` inflicts on `to` this round, by unit type. A side:
## {units, stance, stats: Callable, home}.
static func _kills(data: Dictionary, from: Dictionary, to: Dictionary, rng: LocalRng) -> Dictionary:
	var battle: Dictionary = data.battle
	var targets: Array = []
	var target_total := 0
	for unit in to.units:
		if int(to.units[unit]) > 0:
			targets.append(unit)
			target_total += int(to.units[unit])
	var result := {}
	if target_total == 0:
		return result
	var from_stance: Dictionary = battle.stances[from.stance]
	var to_stance: Dictionary = battle.stances[to.stance]
	var matchup := float(battle.matchups.get(from.stance, {}).get(to.stance, 1.0))
	for target in targets:
		var target_count := int(to.units[target])
		var stats: Dictionary = to.stats.call(target)
		var damage := 0.0
		for unit in from.units:
			var count := int(from.units[unit])
			if count <= 0:
				continue
			var attacker: Dictionary = from.stats.call(unit)
			var counter := float(attacker.get("counters", battle.counters.get(attacker.family, {})).get(stats.family, 1.0))
			damage += count * float(attacker.attack) * float(from_stance.attack) * matchup * counter
		var share := float(target_count) / target_total
		var variance := 1.0 + float(battle.variance) * (rng.next() * 2.0 - 1.0)
		var toughness := maxf(1.0, float(stats.defense)) * float(to_stance.defense) * (float(battle.homeBonus) if to.home else 1.0)
		var expected := (damage * share * variance * float(battle.casualtyScale)) / toughness
		# Round randomly so small fights still take losses on average.
		var whole := floori(expected) + (1 if rng.next() < expected - floorf(expected) else 0)
		var dead := mini(target_count, whole)
		if dead > 0:
			result[target] = dead
	return result


## Simultaneous: both sides strike with the numbers they had at the start.
static func resolve_round(data: Dictionary, attacker: Dictionary, defender: Dictionary, rng: LocalRng) -> Dictionary:
	var attacker_losses := _kills(data, defender, attacker, rng)
	return {"attackerLosses": attacker_losses, "defenderLosses": _kills(data, attacker, defender, rng)}


static func subtract_units(units: Dictionary, losses: Dictionary) -> Dictionary:
	return LocalCamps.subtract_units(units, losses)


static func _broken(data: Dictionary, stance: String, initial: Dictionary, now: Dictionary, nerve := 1.0) -> bool:
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
	if _broken(data, input.attackerStance, input.attackerInitial, input.attackerNow, float(input.get("attackerNerve", 1.0))):
		return "defended"
	if _broken(data, input.defenderStance, input.defenderInitial, input.defenderNow):
		return "raided"
	return "defended" if int(input.round) >= int(data.battle.maxRounds) else "ongoing"


## What a victorious horde carries off.
static func raid_loot(data: Dictionary, amounts: Dictionary, attacker_initial: Dictionary, attacker_now: Dictionary, bonuses: Dictionary = {}, loot_factor := 1.0) -> Dictionary:
	var start := total(attacker_initial)
	var surviving := float(total(attacker_now)) / start if start > 0 else 0.0
	var share := minf(1.0, float(data.battle.raidShare) * loot_factor * maxf(0.0, 1.0 + float(bonuses.get("lootTaken", 0.0))))
	return LocalVillage.resources(func(kind: String) -> int: return floori(float(amounts[kind]) * share * surviving + 1e-9))


static func round_ms(data: Dictionary, world_speed: float) -> int:
	return LocalWaves.js_round((float(data.battle.roundMinutes) * 60000.0) / world_speed)
