class_name HeroText
extends RefCounted
## Words for heroes (see server heroView).


## The display name of a hero effect key (English source, Serbian via .po).
static func effect_name(key: String) -> String:
	return {
		"attack.all": UI.t("attack"), "attack.infantry": UI.t("infantry attack"), "attack.archers": UI.t("archer attack"), "attack.cavalry": UI.t("cavalry attack"),
		"defense.all": UI.t("defense"), "defense.infantry": UI.t("infantry defense"), "defense.archers": UI.t("archer defense"), "defense.cavalry": UI.t("cavalry defense"),
		"homeDefense": UI.t("defense at home"), "lootTaken": UI.t("loot taken"), "scoutSpeed": UI.t("scout speed"), "scoutSurvival": UI.t("scout survival"),
		"caravanSpeed": UI.t("caravan speed"), "caravanCapacity": UI.t("caravan load"),
	}.get(key, key)


## "+8% attack, −15% loot taken"
static func effects(bonuses: Dictionary) -> String:
	var parts := PackedStringArray()
	for key in bonuses:
		var value := float(bonuses[key])
		if is_zero_approx(value):
			continue
		var percent := roundi(value * 100.0)
		parts.append(UI.t("%s%d%% %s") % ["+" if percent > 0 else "−", absi(percent), effect_name(key)])
	return ", ".join(parts)


## Where the hero is, from the point of view of `village_id` (-1: none);
## `place` names the village it stands in or heads for.
static func whereabouts(hero: Dictionary, village_id: int, place: String, now: float) -> String:
	var here: bool = hero.villageId != null and int(hero.villageId) == village_id
	match hero.status:
		"traveling":
			return UI.t("%s is on the road to %s · %s") % [hero.name, place, TimeUtil.format_duration(TimeUtil.parse_iso(hero.arrivesAt) - now)]
		"wounded":
			return UI.t("%s lies wounded in %s · %s") % [hero.name, place, TimeUtil.format_duration(TimeUtil.parse_iso(hero.woundedUntil) - now)]
		"with_army":
			return UI.t("%s (Lv %d) leads an army in the field") % [hero.name, int(hero.level)]
	if here:
		return UI.t("Hero %s (Lv %d) leads this garrison") % [hero.name, int(hero.level)]
	return UI.t("Hero %s (Lv %d) stands in %s") % [hero.name, int(hero.level), place]
