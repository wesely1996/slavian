class_name LocalHeroes
extends RefCounted
## Heroes, their quests and town names for the local engine:
## server/src/sim/heroes.ts, quests.ts and names.ts.

const MASK := 0xffffffff


static func combine(a: Dictionary, b: Dictionary) -> Dictionary:
	var sum := a.duplicate()
	for key in b:
		sum[key] = float(sum.get(key, 0.0)) + float(b[key])
	return sum


static func roster_bonuses(data: Dictionary, kind: Variant) -> Dictionary:
	if kind == null or not data.heroes.roster.has(kind):
		return {}
	var def: Dictionary = data.heroes.roster[kind]
	var out := combine({}, def.effects)
	for t in def.traits:
		out = combine(out, t.effects)
	return out


static func hero_factor(data: Dictionary, kind: Variant, key: String) -> float:
	return maxf(0.1, 1.0 + float(roster_bonuses(data, kind).get(key, 0.0)))


static func free_hero_kind(data: Dictionary, taken: Array) -> Variant:
	for kind in data.heroes.roster:
		if not kind in taken:
			return kind
	return null


static func new_hero(data: Dictionary, kind: String) -> Dictionary:
	return {"kind": kind, "name": data.heroes.roster.get(kind, {}).get("name", kind), "level": 1, "xp": 0, "skillPoints": 0, "skills": {}, "gear": {}, "inventory": []}


static func xp_to_next(data: Dictionary, level: int) -> int:
	return LocalWaves.js_round(float(data.heroes.levelXp.base) * pow(float(data.heroes.levelXp.growth), level - 1))


## What the hero adds where it stands: skills by rank, gear and full sets.
static func hero_bonuses(data: Dictionary, hero: Dictionary) -> Dictionary:
	var out := {}
	for skill in hero.skills:
		var per: Dictionary = data.heroes.skills.get(skill, {}).get("effectsPerRank", {})
		for key in per:
			out[key] = float(out.get(key, 0.0)) + float(per[key]) * int(hero.skills[skill])
	var worn: Array = hero.gear.values()
	for item in worn:
		var effects: Dictionary = data.heroes.items.get(item, {}).get("effects", {})
		for key in effects:
			out[key] = float(out.get(key, 0.0)) + float(effects[key])
	for set_ in data.heroes.sets.values():
		var full := true
		for item in set_.items:
			if not item in worn:
				full = false
		if full:
			for key in set_.effects:
				out[key] = float(out.get(key, 0.0)) + float(set_.effects[key])
	return out


# --- names.ts -----------------------------------------------------------------

static func town_name(data: Dictionary, taken: Array, rng: LocalRng) -> String:
	var used := {}
	for n in taken:
		used[String(n).to_lower()] = true
	var free: Array = data.names.whole.filter(func(n: String) -> bool: return not used.has(n.to_lower()))
	if not free.is_empty():
		return free[floori(rng.next() * free.size())]
	var roots: Array = data.names.roots
	var endings: Array = data.names.endings
	for tries in 200:
		var root: String = roots[floori(rng.next() * roots.size())]
		var ending: String = endings[floori(rng.next() * endings.size())]
		var name := root.substr(0, root.length() - 1) + ending if "aeiouy".contains(root.right(1)) and "aeiouy".contains(ending.left(1)) else root + ending
		if not used.has(name.to_lower()):
			return name
	return "%s%s %d" % [roots[0], endings[0], used.size() + 1]


# --- quests.ts ----------------------------------------------------------------

## The offer period `at` falls in. `world`: {startedAt, speed}.
static func quest_slot(data: Dictionary, started_at: int, speed: float, at: int) -> int:
	var game_hours := ((at - started_at) * speed) / float(LocalTime.MS_PER_HOUR)
	return maxi(0, floori(game_hours / float(data.quests.refreshHours)))


## The quests a hero at `home` is offered. `world`: {seed, speed, startedAt,
## fronts, sites: [{id, q, r}], gearLeft}.
static func quest_offers(data: Dictionary, world: Dictionary, hero: Dictionary, home: Vector2i, at: int, done: Array) -> Array:
	var slot := quest_slot(data, world.startedAt, world.speed, at)
	var rng := LocalRng.new((int(world.seed) ^ LocalRng.imul(int(hero.accountId) + 1, 0x85ebca6b) ^ LocalRng.imul(slot + 1, 0xc2b2ae35)) & MASK)
	var speed := float(data.heroes.speed) * hero_factor(data, hero.kind, "heroSpeed")
	var nearest: Variant = null
	for s in world.sites:
		var d := HexMath.distance(home, Vector2i(s.q, s.r))
		if nearest == null or d < HexMath.distance(home, Vector2i(nearest.q, nearest.r)) or (d == HexMath.distance(home, Vector2i(nearest.q, nearest.r)) and s.id < nearest.id):
			nearest = s
	var open: Array = []
	for kind in ["ambush", "scout", "caravan", "hoard", "ruins"]:
		if kind in ["ambush", "scout"] and world.fronts.is_empty():
			continue
		if kind == "hoard" and not world.gearLeft:
			continue
		if kind == "ruins" and nearest == null:
			continue
		open.append(kind)
	for i in range(open.size() - 1, 0, -1):
		var j := floori(rng.next() * (i + 1))
		var swap: Variant = open[i]
		open[i] = open[j]
		open[j] = swap
	var offers: Array = []
	for kind in open:
		if offers.size() >= int(data.quests.offers):
			break
		var id := "%d:%s" % [slot, kind]
		if id in done:
			continue
		var def: Dictionary = data.quests.kinds[kind]
		var front: Variant = world.fronts[floori(rng.next() * world.fronts.size())] if kind in ["ambush", "scout"] else null
		var site: Variant = nearest if kind == "ruins" else null
		var distance := HexMath.distance(home, Vector2i(site.q, site.r)) if site != null else int(def.distance)
		# An ambush on a horde that hates already: riskier, and worth more.
		var hatred := float(world.get("hatred", {}).get(front, 0.0)) if kind == "ambush" and front != null else 0.0
		offers.append({
			"id": id, "kind": kind, "front": front, "siteId": site.id if site != null else null,
			"distance": distance, "hours": float(def.hours) + (2 * distance) / speed,
			"xp": LocalWaves.js_round(float(def.xp) * (1.0 + hatred * float(def.get("hatredXp", 0)))),
			"risk": minf(float(def.get("maxRisk", 1)), float(def.risk) + hatred * float(def.get("hatredRisk", 0))),
		})
	return offers


static func gain_xp(data: Dictionary, hero: Dictionary, xp: float) -> Dictionary:
	var level := int(hero.level)
	var points := int(hero.skillPoints)
	var pool := int(hero.xp) + maxi(0, floori(xp))
	while level < int(data.heroes.maxLevel) and pool >= xp_to_next(data, level):
		pool -= xp_to_next(data, level)
		level += 1
		points += 1
	var next := hero.duplicate()
	next.level = level
	next.skillPoints = points
	next.xp = 0 if level >= int(data.heroes.maxLevel) else pool
	return next


## Gear dropped by a beaten horde, or null.
static func roll_drop(data: Dictionary, hero: Dictionary, seed_value: int, battle_id: int) -> Variant:
	var rng := LocalRng.new((seed_value ^ LocalRng.imul(battle_id + 1, 0x2545f491) ^ 0xd2) & MASK)
	if rng.next() >= float(data.heroes.dropChance):
		return null
	var owned: Array = hero.inventory + hero.gear.values()
	var candidates: Array = data.heroes.items.keys().filter(func(item: String) -> bool: return not item in owned)
	candidates.sort()
	if candidates.is_empty():
		return null
	return candidates[floori(rng.next() * candidates.size())]


## How long a wound keeps the hero down; a Hero's Hall (of `hall_level`) in
## the village it lies in shortens it.
static func wound_ms(data: Dictionary, world_speed: float, kind: Variant = null, hall_level := 0) -> int:
	return LocalWaves.js_round((float(data.heroes.woundHours) * 3600000.0 * hero_factor(data, kind, "woundTime") * LocalGenerals.hall_recovery(data, hall_level)) / world_speed)


# --- Quests (sim/quests.ts) -------------------------------------------------------

static func quest_ms(offer: Dictionary, world_speed: float) -> int:
	return LocalWaves.js_round((float(offer.hours) * 3600000.0) / world_speed)


## What the hero brings home from a caravan quest, more as it rises in level.
static func caravan_find(data: Dictionary, level: int) -> Dictionary:
	var base: Dictionary = data.quests.kinds.caravan.get("resources", {"wood": 0, "stone": 0, "grain": 0, "iron": 0})
	var scale := 1.0 + float(data.quests.perLevel) * (level - 1)
	return {"wood": LocalWaves.js_round(float(base.wood) * scale), "stone": LocalWaves.js_round(float(base.stone) * scale),
		"grain": LocalWaves.js_round(float(base.grain) * scale), "iron": LocalWaves.js_round(float(base.iron) * scale)}


## Whether the hero comes home wounded, by the seed (fixed for one quest).
static func quest_wounds(offer: Dictionary, seed_value: int, account_id: int, departs_at: int) -> bool:
	var rng := LocalRng.new((seed_value ^ LocalRng.imul(account_id + 1, 0x27d4eb2f) ^ floori(departs_at / 1000.0)) & MASK)
	return rng.next() < float(offer.risk)


static func quest_xp(data: Dictionary, offer: Dictionary, kind: Variant) -> int:
	return LocalWaves.js_round(float(offer.xp) * hero_factor(data, kind, "heroXp"))
