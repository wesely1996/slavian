class_name HeroText
extends RefCounted
## Words for heroes (see server heroView).

const EFFECT_NAMES := {
	"attack.all": "attack", "attack.infantry": "infantry attack", "attack.archers": "archer attack", "attack.cavalry": "cavalry attack",
	"defense.all": "defense", "defense.infantry": "infantry defense", "defense.archers": "archer defense", "defense.cavalry": "cavalry defense",
	"homeDefense": "defense at home", "lootTaken": "loot taken", "scoutSpeed": "scout speed", "scoutSurvival": "scout survival",
	"caravanSpeed": "caravan speed", "caravanCapacity": "caravan load",
}


## "+8% attack, −15% loot taken"
static func effects(bonuses: Dictionary) -> String:
	var parts := PackedStringArray()
	for key in bonuses:
		var value := float(bonuses[key])
		if is_zero_approx(value):
			continue
		var percent := roundi(value * 100.0)
		parts.append("%s%d%% %s" % ["+" if percent > 0 else "−", absi(percent), EFFECT_NAMES.get(key, key)])
	return ", ".join(parts)


## Where the hero is, from the point of view of `village_id` (-1: none);
## `place` names the village it stands in or heads for.
static func whereabouts(hero: Dictionary, village_id: int, place: String, now: float) -> String:
	var here: bool = hero.villageId != null and int(hero.villageId) == village_id
	match hero.status:
		"traveling":
			return "%s is on the road to %s · %s" % [hero.name, place, TimeUtil.format_duration(TimeUtil.parse_iso(hero.arrivesAt) - now)]
		"wounded":
			return "%s lies wounded in %s · %s" % [hero.name, place, TimeUtil.format_duration(TimeUtil.parse_iso(hero.woundedUntil) - now)]
		"with_army":
			return "%s (Lv %d) leads an army in the field" % [hero.name, int(hero.level)]
	if here:
		return "Hero %s (Lv %d) leads this garrison" % [hero.name, int(hero.level)]
	return "Hero %s (Lv %d) stands in %s" % [hero.name, int(hero.level), place]
