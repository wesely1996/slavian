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
		"production.wood": UI.t("wood"), "production.stone": UI.t("stone"), "production.iron": UI.t("iron"),
		"buildTime": UI.t("build time"), "trainTime": UI.t("training time"), "trainTime.settler": UI.t("settler training time"),
		"coldDefense": UI.t("defense against the North"), "fortCost": UI.t("fort cost"), "outpostYield": UI.t("outpost yield"),
		"storage": UI.t("storage"),
	}.get(key, key)


## The hero's own numbers, before any bonus table (server sim/heroes.ts):
## travel speed (hexes per game hour), time wounded after a lost fight,
## gear slots worn and skill points to spend.
static func base_stats(data: Dictionary, hero: Dictionary, world_speed: float) -> PackedStringArray:
	var speed := float(data.heroes.speed) * LocalHeroes.hero_factor(data, hero.kind, "heroSpeed")
	var wound_seconds := float(LocalHeroes.wound_ms(data, world_speed, hero.kind)) / 1000.0
	var worn := 0
	for slot in data.heroes.slots:
		if hero.get("gear", {}).get(slot) != null:
			worn += 1
	var points := int(hero.get("skillPoints", 0))
	return PackedStringArray([
		UI.t("Rides %s hexes an hour") % String.num(TimeUtil.per_real_hour(speed * world_speed), 1).trim_suffix(".0"),
		UI.t("Wounded for %s after a lost fight") % TimeUtil.format_duration(wound_seconds),
		UI.t("Gear: %d of %d slots worn") % [worn, data.heroes.slots.size()],
		UI.t("%d %s to spend") % [points, UI.tn("skill point", "skill points", points)],
	])


## Where the hero's bonuses come from (server sim/heroes.ts heroBonuses):
## {effect key: [own, skills, gear, total]}. Its own (roster effects and
## traits) count in all your villages; skills and gear (sets included)
## where it stands.
static func breakdown(data: Dictionary, hero: Dictionary) -> Dictionary:
	var parts := {}
	var add := func(effects: Dictionary, column: int, times := 1.0) -> void:
		for key in effects:
			if not parts.has(key):
				parts[key] = [0.0, 0.0, 0.0, 0.0]
			parts[key][column] += float(effects[key]) * times
			parts[key][3] += float(effects[key]) * times
	var def := roster(data, hero.get("kind"))
	add.call(def.get("effects", {}), 0)
	for trait_ in def.get("traits", []):
		add.call(trait_.get("effects", {}), 0)
	var heroes: Dictionary = data.get("heroes", {})
	for skill in hero.get("skills", {}):
		add.call(heroes.get("skills", {}).get(skill, {}).get("effectsPerRank", {}), 1, float(hero.skills[skill]))
	var worn: Array = hero.get("gear", {}).values().filter(func(item: Variant) -> bool: return item != null)
	for item in worn:
		add.call(heroes.get("items", {}).get(item, {}).get("effects", {}), 2)
	for set_id in heroes.get("sets", {}):
		var set_def: Dictionary = heroes.sets[set_id]
		if set_def.get("items", []).all(func(item: String) -> bool: return item in worn):
			add.call(set_def.get("effects", {}), 2)
	return parts


## Whether a bonus helps you: less upkeep, time or loot lost is better.
static func helps(key: String, value: float) -> bool:
	var less_is_better := key in ["upkeep", "researchTime", "buildTime", "woundTime", "lootTaken", "fortCost"] or key.begins_with("trainTime")
	return (value < 0.0) == less_is_better


## "+8%" or "−15%" for a bonus share.
static func percent(value: float) -> String:
	var whole := roundi(value * 100.0)
	return "—" if whole == 0 else ("+%d%%" % whole if whole > 0 else "−%d%%" % absi(whole))


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
