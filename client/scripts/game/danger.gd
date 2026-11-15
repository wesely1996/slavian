class_name Danger
extends RefCounted
## How an assault on a camp or a guarded site is likely to go, for the
## player to see before sending: the fight is played many times over with
## the engine's own battle rules (attack and defense rolled in their ranges,
## as the server does), from what the player knows of the enemy, its
## numbers; who exactly is in there is guessed from its front.

## Fights played for one estimate.
const TRIALS := 30

static var _cache := {}


## {win, own, enemy}: the share of fights won, and the share of each side
## that falls on average. `units` march (scouts stand aside); `size`
## enemies of `front`, made up as a horde of wave `wave_index` would be.
static func estimate(data: Dictionary, units: Dictionary, bonuses: Dictionary, stance: String, size: int, front: String, wave_index: int) -> Dictionary:
	var key := hash([units, bonuses, stance, size, front, wave_index])
	if _cache.has(key):
		return _cache[key]
	var fighters := LocalScouting.combatants(data, units)
	var mine := LocalBattle.total(fighters)
	var result := {"win": 0.0, "own": 1.0, "enemy": 0.0}
	if mine > 0 and size > 0:
		var stats := LocalScouting.with_intel(data, units, LocalBattle.player_stats(data, bonuses, false))
		var wins := 0
		var own := 0.0
		var enemy := 0.0
		for i in TRIALS:
			# Who is in there differs from guess to guess, as it may in truth.
			var camp := LocalWaves.compose_wave(data, front, wave_index, size, 7919 * (i + 1))
			var fight := LocalArmies.assault(data, fighters, stats, stance, camp, front, 104729 * (i + 1), i)
			if fight.cleared:
				wins += 1
			own += 1.0 - float(LocalBattle.total(fight.armyNow)) / mine
			enemy += 1.0 - float(LocalBattle.total(fight.campNow)) / maxi(1, LocalBattle.total(camp))
		result = {"win": float(wins) / TRIALS, "own": own / TRIALS, "enemy": enemy / TRIALS}
	if _cache.size() > 200:
		_cache.clear()
	_cache[key] = result
	return result


## The estimate in a word and its colour: [text, Color].
static func verdict(estimate_: Dictionary) -> Array:
	var win := float(estimate_.win)
	var own := float(estimate_.own)
	if win >= 0.9 and own < 0.15:
		return [UI.t("Crushing victory"), UI.GOOD]
	if win >= 0.5 and own >= 0.4:
		return [UI.t("Pyrrhic victory"), UI.ACCENT]
	if win >= 0.75:
		return [UI.t("Clear victory"), UI.GOOD]
	if win >= 0.5:
		return [UI.t("Close victory"), UI.ACCENT]
	if win >= 0.25:
		return [UI.t("Close defeat"), UI.ACCENT]
	if win >= 0.05:
		return [UI.t("Defeat (a heroic victory at best)"), UI.ERROR]
	return [UI.t("Crushing defeat"), UI.ERROR]


## "Close victory · 62% to win · you lose about 35%, they 80%"
static func line(estimate_: Dictionary) -> String:
	return UI.t("%s · %d%% to win · you lose about %d%%, they %d%%") % [verdict(estimate_)[0], roundi(float(estimate_.win) * 100.0),
		roundi(float(estimate_.own) * 100.0), roundi(float(estimate_.enemy) * 100.0)]
