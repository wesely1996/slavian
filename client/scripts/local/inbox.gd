class_name LocalInbox
extends RefCounted
## The inbox for the local engine: what players are told (server/src/
## scheduler/notices.ts tell, tellOwner, wave_warning, daily_digest), in the
## player's language as the server renders it (i18n.ts localize) from the
## notice tables `npm run fixtures` bundles (client/data/notices.json),
## over the app's own catalog.

const NOTICES := "res://data/notices.json"
const MS_PER_MINUTE := 60000
const MINUTES_PER_DAY := 1440
## Push-free defaults (sim/notifications.ts DEFAULT_PREFS).
const DEFAULT_PREFS := {"quietStart": null, "quietEnd": null, "utcOffsetMinutes": 0, "digestHour": 18}

static var _notices: Dictionary = {}


static func _load() -> Dictionary:
	if _notices.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(NOTICES))
		_notices = parsed if parsed is Dictionary else {"tables": {}, "digestLabels": {}}
	return _notices


static func _tag(language: String) -> String:
	var lower := language.to_lower()
	return "sr" if lower.begins_with("sr") else lower


## A template's translation: the notice table first, then the app's catalog.
static func _lookup(tag: String, key: String) -> Variant:
	var table: Dictionary = _load().tables.get(tag, {})
	if table.has(key):
		return table[key]
	for locale in TranslationServer.get_loaded_locales():
		if _tag(locale) != tag:
			continue
		var t := TranslationServer.get_translation_object(locale)
		if t != null:
			var found := String(t.get_message(key))
			if found != "":
				return found
	return null


static func _translate_value(tag: String, value: String) -> String:
	var found: Variant = _lookup(tag, value)
	if found != null:
		return found
	var capital := value.left(1).to_upper() + value.substr(1)
	if capital != value:
		var cap: Variant = _lookup(tag, capital)
		if cap != null:
			return String(cap).left(1).to_lower() + String(cap).substr(1)
	if value.contains(", "):
		return ", ".join(Array(value.split(", ")).map(func(part: String) -> String: return _translate_value(tag, part)))
	return value


## Fills `{name}` placeholders (missing ones are left as-is).
static func fill(template: String, vars: Dictionary) -> String:
	var out := ""
	var i := 0
	while i < template.length():
		var open := template.find("{", i)
		if open < 0:
			out += template.substr(i)
			break
		var close := template.find("}", open)
		var key := template.substr(open + 1, close - open - 1) if close > open else ""
		if close > open and key.is_valid_identifier() and vars.has(key):
			out += template.substr(i, open - i) + _text(vars[key])
			i = close + 1
		else:
			out += template.substr(i, open - i + 1)
			i = open + 1
	return out


static func _text(value: Variant) -> String:
	if value is float or value is int:
		return LocalServer._js_number(value)
	return str(value)


## Renders an English template in `language`, then fills its values.
static func localize(language: String, template: String, vars: Dictionary = {}) -> String:
	var tag := _tag(language)
	if not _load().tables.has(tag):
		return fill(template, vars)
	var values := {}
	for key in vars:
		values[key] = _translate_value(tag, vars[key]) if vars[key] is String else vars[key]
	var own: Variant = _lookup(tag, template)
	return fill(own if own != null else template, values)


## Tells a player something: {kind, tier, title, body, vars?, bodyText?}
## (bodyText: a body already in the reader's language, the digest's).
static func tell(server: LocalServer, world: Dictionary, account_id: Variant, notice: Dictionary, at: int) -> void:
	if account_id == null:
		return
	var vars: Dictionary = notice.get("vars", {})
	world.notifications.append({"id": world.next.notification, "accountId": int(account_id), "kind": notice.kind, "tier": notice.tier,
		"title": localize(server.language, notice.title, vars),
		"body": notice.bodyText if notice.has("bodyText") else localize(server.language, notice.body, vars),
		"createdAt": at, "readAt": null, "digestId": null})
	world.next.notification += 1


## Tells the owner of a village; `notice` gets the village's name.
static func tell_owner(server: LocalServer, world: Dictionary, village_id: int, notice: Callable, at: int) -> void:
	var village := server.find_village(world, village_id)
	tell(server, world, village.ownerAccountId, notice.call(village.name), at)


static func tell_everyone(server: LocalServer, world: Dictionary, notice: Dictionary, at: int) -> void:
	for member in world.members:
		tell(server, world, member.accountId, notice, at)


# --- Digests (sim/notifications.ts) ------------------------------------------------

static func _local_minute(at: int, prefs: Dictionary) -> int:
	return posmod(floori(at / float(MS_PER_MINUTE)) + int(prefs.utcOffsetMinutes), MINUTES_PER_DAY)


## The next moment at the player's digest hour, strictly after `after`.
static func next_digest_at(after: int, prefs: Dictionary) -> int:
	var m := _local_minute(after, prefs)
	var wait := int(prefs.digestHour) * 60 - m
	if wait <= 0:
		wait += MINUTES_PER_DAY
	return floori(after / float(MS_PER_MINUTE)) * MS_PER_MINUTE + wait * MS_PER_MINUTE


static func digest_summary(kinds: Array, language: String) -> String:
	var counts := {}
	for kind in kinds:
		counts[kind] = int(counts.get(kind, 0)) + 1
	if _tag(language) == "sr":
		var labels: Dictionary = _load().digestLabels.get("sr", {})
		var line := ", ".join(counts.keys().map(func(kind: String) -> String: return "%s: %d" % [labels.get(kind, "novosti"), counts[kind]]))
		return line.left(1).to_upper() + line.substr(1)
	var english := {
		"build_done": ["build finished", "builds finished"], "research_done": ["tech researched", "techs researched"],
		"battle_result": ["battle report", "battle reports"], "caravan_delivered": ["caravan delivery", "caravan deliveries"],
		"settlers": ["settlers report", "settlers reports"], "hero": ["hero report", "hero reports"],
		"leader": ["word of an enemy leader", "words of enemy leaders"],
	}
	return ", ".join(counts.keys().map(func(kind: String) -> String:
		var names: Array = english.get(kind, ["update", "updates"])
		return "%d %s" % [counts[kind], names[0] if counts[kind] == 1 else names[1]]))


## Every member gets a daily digest at their digest hour.
static func ensure_digests(server: LocalServer, world: Dictionary, from: int) -> void:
	for member in world.members:
		if server.pending(world, "daily_digest", {"accountId": member.accountId}):
			continue
		server.schedule(world, next_digest_at(from, DEFAULT_PREFS), "daily_digest", {"accountId": member.accountId})


static func on_daily_digest(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var account := int(event.payload.accountId)
	var at := int(event.dueAt)
	var pending: Array = world.notifications.filter(func(n: Dictionary) -> bool:
		return int(n.accountId) == account and n.tier == "digest" and n.digestId == null and int(n.createdAt) <= at)
	pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.createdAt) < int(b.createdAt))
	if not pending.is_empty():
		tell(server, world, account, {"kind": "digest", "tier": "push", "title": "Today in {world}",
			"bodyText": digest_summary(pending.map(func(n: Dictionary) -> String: return n.kind), server.language), "vars": {"world": world.name}}, at)
		var digest_id := int(world.next.notification) - 1
		for n in pending:
			n.digestId = digest_id
		changed.append(["inbox"])
	server.schedule(world, next_digest_at(at, DEFAULT_PREFS), "daily_digest", {"accountId": account})


## A horde is near: its target's owner hears of it.
static func on_wave_warning(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var wave := server.find_wave(world, int(event.payload.waveId))
	if wave.is_empty() or wave.status != "marching" or wave.targetVillageId == null or wave.arrivesAt == null:
		return
	var hours := LocalWaves.js_round(maxf(0.0, (int(wave.arrivesAt) - int(event.dueAt)) / LocalTime.MS_PER_HOUR))
	var when := "in about {hours} hours" if hours > 1 else ("in about an hour" if hours == 1 else "within the hour")
	tell_owner(server, world, int(wave.targetVillageId), func(name: String) -> Dictionary:
		return {"kind": "wave_soon", "tier": "push", "title": "A horde is coming to {village}",
			"body": "The {threat} {front} horde arrives %s. Check the garrison and its stance." % when,
			"vars": {"village": name, "threat": String(wave.threat).to_lower(), "front": wave.front, "hours": hours}}, int(event.dueAt))
	changed.append(["inbox"])


# --- Views (api/views.ts inboxView) -------------------------------------------------

static func inbox_view(world: Dictionary, account_id: int) -> Dictionary:
	var mine: Array = world.notifications.filter(func(n: Dictionary) -> bool: return int(n.accountId) == account_id)
	var unread := mine.filter(func(n: Dictionary) -> bool: return n.readAt == null).size()
	mine.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.createdAt) > int(b.createdAt) or (int(a.createdAt) == int(b.createdAt) and int(a.id) > int(b.id)))
	return {"notifications": mine.slice(0, 40).map(func(n: Dictionary) -> Dictionary:
		return {"id": n.id, "kind": n.kind, "tier": n.tier, "title": n.title, "body": n.body, "createdAt": LocalTime.iso(n.createdAt), "read": n.readAt != null}),
		"unread": unread}


static func mark_all_read(world: Dictionary, account_id: int, at: int) -> void:
	for n in world.notifications:
		if int(n.accountId) == account_id and n.readAt == null:
			n.readAt = at
