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
		"upkeep": UI.t("troop upkeep"), "ambush": UI.t("ambush"), "researchTime": UI.t("research time"),
		"production.all": UI.t("production"), "production.grain": UI.t("grain"), "trainTime.spearman": UI.t("spearman training time"),
		"heroSpeed": UI.t("hero speed"), "heroXp": UI.t("hero XP"), "woundTime": UI.t("time wounded"),
	}.get(key, key)


## The roster's heroes (data/heroes.json), in their order.
static func roster_ids(data: Dictionary) -> Array:
	return data.get("heroes", {}).get("roster", {}).keys()


## A roster hero's definition ({} if unknown).
static func roster(data: Dictionary, kind: Variant) -> Dictionary:
	if kind == null:
		return {}
	return data.get("heroes", {}).get("roster", {}).get(String(kind), {})


## "Dobrynya, the serpent-slayer prince"
static func roster_title(data: Dictionary, kind: Variant) -> String:
	var def := roster(data, kind)
	if def.is_empty():
		return UI.t("No hero yet")
	return UI.t("%s, %s") % [UI.t(def.name), UI.t(def.title).to_lower()]


## Its traits: "Tracker: Moves fast and teaches the scouts to come back alive."
static func roster_traits(data: Dictionary, kind: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	for trait_ in roster(data, kind).get("traits", []):
		out.append(UI.t("%s: %s (%s)") % [UI.t(trait_.name), UI.t(trait_.description), effects(trait_.effects)])
	return out


## The portrait, `width` wide (art id hero/<kind>).
static func portrait(kind: Variant, width: float) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = Art.texture("hero/%s" % String(kind)) if kind != null else null
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(width, width * 1.25)
	return rect


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
		"questing":
			var quest: Dictionary = hero.get("quest", {}) if hero.get("quest") is Dictionary else {}
			return UI.t("%s is away on a quest · back in %s") % [hero.name, TimeUtil.format_duration(TimeUtil.parse_iso(String(quest.get("returnsAt", ""))) - now)]
	if here:
		return UI.t("Hero %s (Lv %d) leads this garrison") % [hero.name, int(hero.level)]
	return UI.t("Hero %s (Lv %d) stands in %s") % [hero.name, int(hero.level), place]


## A quest's description, its front or site filled in (data/quests.json).
static func quest_description(data: Dictionary, offer: Dictionary, site_name := "") -> String:
	var def: Dictionary = data.get("quests", {}).get("kinds", {}).get(String(offer.kind), {})
	var text := UI.t(def.get("description", ""))
	text = text.replace("{front}", UI.t(String(offer.get("front", "")))) if offer.get("front") != null else text
	return text.replace("{site}", site_name if site_name != "" else UI.t("ancient site"))


## "3h 20m · 25% risk · +40 XP"
static func quest_terms(offer: Dictionary, world_speed: float) -> String:
	var seconds := float(offer.hours) * 3600.0 / maxf(1.0, world_speed)
	return UI.t("%s · %d%% risk · +%d XP") % [TimeUtil.format_duration(seconds), roundi(float(offer.risk) * 100.0), int(offer.xp)]
