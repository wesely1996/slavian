class_name RunText
extends RefCounted
## Words for Ritual Night and the end of a run (see server scheduler/ritual.ts).


static func is_over(world: Dictionary) -> bool:
	return world.get("status", "") in ["won", "lost"]


## The ending's title and story, from data/bridge.json.
static func ending(data: Dictionary, world: Dictionary) -> Dictionary:
	if not is_over(world):
		return {}
	return data.bridge.endings[world.status]


## "Ritual Night · in 5h 12m" until its hordes set out, then "Ritual Night".
static func ritual_line(world: Dictionary, now: float) -> String:
	var at: Variant = world.get("ritualAt")
	if at == null or is_over(world):
		return ""
	var left := TimeUtil.parse_iso(at) - now
	return "Ritual Night · in %s" % TimeUtil.format_duration(left) if left > 0 else "Ritual Night"


## The run's summary as lines for the end screen.
static func stats(run: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("%s days" % _number(float(run.days)))
	lines.append("Hordes beaten: %d of %d" % [int(run.wavesBeaten), int(run.wavesFaced)])
	lines.append("Battles won: %d · camps cleared: %d" % [int(run.battlesWon), int(run.campsCleared)])
	lines.append("Ancient sites explored: %d · lore scrolls: %d" % [int(run.sitesExplored), int(run.scrolls)])
	lines.append("Villages founded: %d · lost: %d" % [int(run.villagesFounded), int(run.villagesLost)])
	return lines


## "Mila: 3 villages, 1 lost".
static func member_line(member: Dictionary) -> String:
	var villages := int(member.villages)
	var line := "%s: %d village%s" % [member.displayName, villages, "" if villages == 1 else "s"]
	if int(member.villagesLost) > 0:
		line += ", %d lost" % int(member.villagesLost)
	return line


static func _number(n: float) -> String:
	return str(int(n)) if is_equal_approx(n, roundf(n)) else "%.1f" % n
