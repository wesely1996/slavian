class_name SoundCues
extends RefCounted
## When the game's music and horns change (M5 step 26): the calm theme of
## the view on screen, a tense one while a horde is near one of your
## villages, the battle theme on the battle map, and the run's ending.

## A marching horde this close (real seconds) makes the music tense.
const NEAR_SEC := 3600.0
## Statuses of a horde already at a village.
const AT_THE_GATES := ["arrived", "battling", "razing"]


## Ids of the hordes marching on one of `mine` (village ids).
static func incoming(waves: Array, mine: Array) -> Array:
	var ids := []
	for wave in waves:
		if wave.status == "marching" and wave.get("targetVillageId") != null and int(wave.targetVillageId) in mine:
			ids.append(int(wave.id))
	return ids


## Whether a horde is at one of `mine` or less than NEAR_SEC away.
static func threatened(waves: Array, mine: Array, now: float) -> bool:
	for wave in waves:
		if wave.get("targetVillageId") == null or int(wave.targetVillageId) not in mine:
			continue
		if wave.status in AT_THE_GATES:
			return true
		if wave.status == "marching" and wave.get("arrivesAt") != null and TimeUtil.parse_iso(wave.arrivesAt) - now <= NEAR_SEC:
			return true
	return false


## The track for the screen: `view` is "map", "village" or "battle";
## `status` is the world's.
static func track(view: String, status: String, near: bool) -> String:
	if status == "won" or status == "lost":
		return status
	if view == "battle":
		return "battle"
	return "threat" if near else view


## Hordes in `now_ids` not in `known`: each sounds the horn once.
static func new_hordes(known: Array, now_ids: Array) -> Array:
	return now_ids.filter(func(id: int) -> bool: return id not in known)
