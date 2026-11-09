class_name LocalRaids
extends RefCounted
## Raids beyond the map's edge, as the server has them (sim/raids.ts,
## scheduler/raids.ts): an army marches to the edge on a front's side, then
## fights one stage every stageHours (raid_stage): `depth` field battles,
## then the siege of the front's stronghold, and comes home with what it
## carries.

const MASK := 0xffffffff


## sim/raids.ts raidEdge: the hex on the map's last ring, on the front's
## side, nearest `from` that an army can stand on (Vector2i.MAX: none).
static func raid_edge(data: Dictionary, terrain: Dictionary, radius: int, front: String, from: Vector2i) -> Vector2i:
	var cells: Array = []
	for cell in HexMath.ring(Vector2i.ZERO, radius):
		var type: Variant = terrain.get(LocalLand.key(cell))
		if type == null or type == "holy_city" or data.terrain.terrain[type].moveCost == null or LocalMapgen.front_of(cell) != front:
			continue
		cells.append(cell)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := HexMath.distance(a, from)
		var db := HexMath.distance(b, from)
		if da != db:
			return da < db
		return a.x < b.x if a.x != b.x else a.y < b.y)
	return cells[0] if not cells.is_empty() else Vector2i.MAX


## sim/raids.ts raidStage: the field (in a seeded order) or, past `depth`,
## the stronghold, and the enemy there.
static func raid_stage(data: Dictionary, front: String, depth: int, stage: int, waves: int, seed_value: int, id: int, players: int) -> Dictionary:
	var rules: Dictionary = data.raids
	var lands: Dictionary = rules.fronts[front]
	var order: Array = range(lands.fields.size())
	var rng := LocalRng.new((seed_value ^ LocalRng.imul(id + 1, 0x5bd1e995) ^ 0x4a1d) & MASK)
	for i in range(order.size() - 1, 0, -1):
		var j := floori(rng.next() * (i + 1))
		var t: int = order[i]
		order[i] = order[j]
		order[j] = t
	var stronghold := stage > depth
	var size := float(rules.enemy.baseUnits) * pow(float(rules.enemy.growthPerStage), stage - 1) * pow(float(rules.enemy.growthPerWave), waves) \
		* (float(rules.stronghold.sizeFactor) if stronghold else 1.0)
	var enemy := LocalWaves.compose_wave(data, front, waves + stage, maxi(1, LocalWaves.js_round(size)), (seed_value ^ LocalRng.imul(id + 7, 0x27d4eb2f) ^ stage) & MASK, players)
	var field: Variant = null if stronghold else lands.fields[order[(stage - 1) % order.size()]]
	return {"stage": stage, "name": String(lands.stronghold) if stronghold else String(field.name), "stronghold": stronghold, "field": field, "enemy": enemy}


## sim/raids.ts raidBattle: the army attacks until one side breaks or the
## last round passes. {won, rounds, armyNow, enemyNow}.
static func raid_battle(data: Dictionary, army: Dictionary, army_stats: Callable, army_stance: String, stage: Dictionary, front: String, seed_value: int, id: int) -> Dictionary:
	var rules: Dictionary = data.raids
	var field: Variant = stage.field
	var walls := 1.0 + float(rules.stronghold.walls) if stage.stronghold else 1.0
	var base := LocalBattle.enemy_stats(data, front)
	var enemy_at := func(unit: String) -> Dictionary:
		var s: Dictionary = base.call(unit).duplicate()
		s.attack = float(s.attack) * (float(field.enemy.attack) if field != null else 1.0)
		s.defense = float(s.defense) * (float(field.enemy.defense) if field != null else 1.0) * walls
		return s
	var army_at := func(unit: String) -> Dictionary:
		var s: Dictionary = army_stats.call(unit).duplicate()
		s.attack = float(s.attack) * (float(field.army.attack) if field != null else 1.0)
		s.defense = float(s.defense) * (float(field.army.defense) if field != null else 1.0)
		return s
	var enemy_stance: String = rules.stronghold.stance if stage.stronghold else rules.fieldStance
	var army_now := army.duplicate()
	var enemy_now: Dictionary = stage.enemy.duplicate()
	var rounds: Array = []
	for round in range(1, int(data.battle.maxRounds) + 1):
		var result := LocalBattle.resolve_round(data, {"units": army_now, "stance": army_stance, "stats": army_at, "home": false},
			{"units": enemy_now, "stance": enemy_stance, "stats": enemy_at, "home": stage.stronghold}, LocalBattle.battle_rng(seed_value, id + 0x30000, round))
		army_now = LocalCamps.subtract_units(army_now, result.attackerLosses)
		enemy_now = LocalCamps.subtract_units(enemy_now, result.defenderLosses)
		rounds.append({"round": round, "attackerLosses": result.attackerLosses, "defenderLosses": result.defenderLosses,
			"attackerLeft": LocalBattle.total(army_now), "defenderLeft": LocalBattle.total(enemy_now)})
		var outcome := LocalBattle.battle_outcome(data, {"round": round, "attackerStance": army_stance, "attackerInitial": army, "attackerNow": army_now,
			"defenderStance": enemy_stance, "defenderInitial": stage.enemy, "defenderNow": enemy_now})
		if outcome != "ongoing":
			return {"won": outcome == "raided", "rounds": rounds, "armyNow": army_now, "enemyNow": enemy_now}
	return {"won": false, "rounds": rounds, "armyNow": army_now, "enemyNow": enemy_now}


## sim/raids.ts raidCapacity: what an army can carry home.
static func capacity(data: Dictionary, units: Dictionary) -> float:
	var carry := 0.0
	for unit in units:
		var def: Dictionary = data.units.units.get(unit, {})
		var n := int(units[unit])
		if def.is_empty() or n <= 0:
			continue
		if float(def.get("supplyGrain", 0)) > 0:
			carry += float(data.raids.carry.perWagon) * n
		elif def.family != "scout" and unit != "settler":
			carry += float(data.raids.carry.perSoldier) * n
	return carry


## sim/raids.ts raidLoot: what a battle won yields.
static func loot(data: Dictionary, front: String, kills: int, stronghold: bool) -> Dictionary:
	var rules: Dictionary = data.raids
	var factor := float(data.enemies.fronts[front].personality.lootFactor) * (float(rules.north.resourceShare) if front == "north" else 1.0)
	return LocalVillage.resources(func(k: String) -> int:
		return LocalWaves.js_round((float(rules.loot.perKill[k]) * kills + (float(rules.loot.stronghold[k]) if stronghold else 0.0)) * factor))


## sim/raids.ts carryHome: `gain` added to `carried` as far as `room` allows.
static func carry_home(carried: Dictionary, gain: Dictionary, cap: float) -> Dictionary:
	var room := maxf(0.0, cap - LocalLogistics.total(carried))
	var out := {}
	for k in ["wood", "stone", "grain", "iron"]:
		var take := minf(room, float(gain[k]))
		room -= take
		out[k] = float(carried.get(k, 0)) + take
	return out


## sim/raids.ts northFinds: the kinds of rare find a battle won in the North
## turns up, by their chances.
static func north_finds(data: Dictionary, stronghold: bool, seed_value: int, id: int, stage: int) -> Array:
	var rules: Dictionary = data.raids.north
	var rng := LocalRng.new((seed_value ^ LocalRng.imul(id + 3, 0x1b873593) ^ LocalRng.imul(stage + 1, 0x85ebca6b)) & MASK)
	var factor := float(rules.strongholdFactor) if stronghold else 1.0
	var out: Array = []
	for type in ["gear", "scroll", "ember"]:
		if rng.next() < minf(1.0, float(rules.finds[type]) * factor):
			out.append(type)
	return out


## scheduler/raids.ts startRaid: an army from `village` off to raid a front.
static func start(server: LocalServer, world: Dictionary, village: Dictionary, body: Dictionary, now: int) -> Dictionary:
	var data := server.data
	var front := String(body.get("front", ""))
	var depth := int(body.get("depth", 0))
	if not front in world.activeFronts:
		return LocalVillage.rule("No enemy comes from that side in this world")
	if depth < 1 or depth > int(data.raids.maxDepth):
		return LocalVillage.rule("A raid goes 1 to %d fields deep" % int(data.raids.maxDepth))
	var edge := raid_edge(data, world.hexes, int(world.radius), front, Vector2i(village.q, village.r))
	if edge == Vector2i.MAX:
		return LocalVillage.rule("There is no way out to that side of the map")
	var army := LocalArmies.dispatch_army(server, world, {"homeVillageId": village.id, "targetVillageId": null, "targetHex": edge,
		"units": body.get("units", {}), "orders": "raid", "withHero": body.get("withHero", false), "generalId": body.get("generalId"),
		"stance": body.get("stance"), "at": now})
	if army.has("error") or army.has("missing"):
		return army
	army.raid = {"front": front, "depth": depth, "stage": 0, "battles": [], "finds": []}
	army.loot = {"wood": 0, "stone": 0, "grain": 0, "iron": 0}
	return army


## scheduler/raids.ts reachEdge: it stands at the edge (beyond it) and the
## first battle comes one stage later.
static func reach_edge(server: LocalServer, world: Dictionary, army: Dictionary, at: int) -> void:
	if army.get("raid") == null:
		LocalArmies.send_home(server, world, army, at)
		return
	army.status = "stationed"
	server.schedule(world, at + _stage_ms(server.data, world.speed), "raid_stage", {"armyId": army.id, "stage": int(army.raid.stage) + 1})


static func _stage_ms(data: Dictionary, world_speed: float) -> int:
	return LocalWaves.js_round((float(data.raids.stageHours) * LocalTime.MS_PER_HOUR) / world_speed)


static func _waves_so_far(world: Dictionary, at: int) -> int:
	var best := -1
	for w in world.waves:
		if w.get("bandOf") == null and int(w.spawnAt) <= at:
			best = maxi(best, int(w.index))
	return best + 1


## A North find made concrete (scheduler/raids.ts pickFind): {} for none.
static func _pick_find(data: Dictionary, type: String, owned: Array, found: Array, seed_value: int) -> Dictionary:
	var rng := LocalRng.new(seed_value & MASK)
	if type == "ember":
		return {"kind": "ember"}
	if type == "gear":
		var items: Array = data.heroes.items.keys().filter(func(i: String) -> bool: return not i in owned)
		items.sort()
		return {"kind": "gear", "item": items[floori(rng.next() * items.size())]} if not items.is_empty() else {}
	var scrolls: Array = data.lore.scrolls.keys().filter(func(s: String) -> bool: return not s in found)
	scrolls.sort()
	return {"kind": "scroll", "scroll": scrolls[floori(rng.next() * scrolls.size())]} if not scrolls.is_empty() else {}


## scheduler/raids.ts raid_stage: the next battle of a raid.
static func on_raid_stage(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var data := server.data
	var p: Dictionary = event.payload
	var army := LocalArmies.find_army(world, int(p.armyId))
	if army.is_empty() or army.status != "stationed" or army.orders != "raid" or army.get("raid") == null or int(army.raid.stage) + 1 != int(p.stage):
		return
	var at := int(event.dueAt)
	changed.append(["world"])
	var raid: Dictionary = army.raid
	var front := String(raid.front)
	var stage_no := int(p.stage)
	var stage := raid_stage(data, front, int(raid.depth), stage_no, _waves_so_far(world, at), int(world.seed), int(army.id), world.members.size())
	var home := server.find_village(world, int(army.homeVillageId))
	var hero := LocalArmies.hero_with_army(world, int(army.id))
	var general := LocalGenerals.general_with_army(world, int(army.id))
	var bonuses := LocalArmies._led_bonuses(data, home.state.bonuses, hero, general)
	var initial: Dictionary = army.units.duplicate()
	var fighters := LocalScouting.combatants(data, army.units)
	var result := raid_battle(data, fighters, LocalScouting.with_intel(data, army.units, LocalBattle.player_stats(data, bonuses, false)),
		army.get("stance", "balanced"), stage, front, int(world.seed), int(army.id) * 8 + stage_no)
	var kills := LocalBattle.total(stage.enemy) - LocalBattle.total(result.enemyNow)
	var lost := LocalArmies._losses({"units": fighters}, result.armyNow)
	var after := LocalArmies.army_losses(server, world, army, lost, at)
	var carried: Dictionary = after.loot if after.get("loot") != null else {"wood": 0, "stone": 0, "grain": 0, "iron": 0}
	var taken := carry_home(carried, loot(data, front, kills, stage.stronghold), capacity(data, after.units)) if result.won else carried
	var battle := LocalArmies._assault_battle(world, {"waveId": null, "villageId": null, "q": army.targetQ, "r": army.targetR,
		"setup": {"raid": {"front": front, "name": stage.name, "stronghold": stage.stronghold, "stage": stage_no}},
		"attackerStance": data.raids.stronghold.stance if stage.stronghold else data.raids.fieldStance,
		"attackerInitial": stage.enemy, "defenderInitial": initial, "startedAt": at},
		{"rounds": result.rounds}, at, "cleared" if result.won else "repelled", taken if result.won else null)
	if not hero.is_empty():
		if not result.won:
			hero.villageId = army.homeVillageId
			hero.armyId = null
		LocalBattles.hero_after_battle(server, world, hero, {"kills": kills, "won": result.won, "battleId": battle.id, "at": at})
	if not general.is_empty():
		LocalGenerals.after_battle(server, world, general, {"kills": kills, "won": result.won, "at": at})
	var finds: Array = []
	if result.won:
		var wave := LocalHeroCommands._next_wave(world, front)
		var amount := float(data.raids.hatred.perBattle) + (float(data.raids.hatred.stronghold) if stage.stronghold else 0.0)
		if not wave.is_empty() and amount > 0:
			LocalHordes.anger_horde(server, world, wave, amount, at)
		if front == "north":
			var owner_hero: Dictionary = hero if not hero.is_empty() else (LocalArmies.hero_of(world, int(army.ownerAccountId)) if army.ownerAccountId != null else {})
			var kinds := north_finds(data, stage.stronghold, int(world.seed), int(army.id), stage_no)
			for i in kinds.size():
				var owned: Array = owner_hero.inventory + owner_hero.gear.values() if not owner_hero.is_empty() else []
				var picked := _pick_find(data, kinds[i], owned, LocalResearch.scrolls(world),
					int(world.seed) ^ LocalRng.imul(int(army.id) + 1, 0x9e3779b1) ^ (stage_no * 16 + i))
				if picked.is_empty():
					continue
				match String(picked.kind):
					"ember":
						world.embers = int(world.embers) + 1
						finds.append("a Svarog's Ember")
					"gear":
						if owner_hero.is_empty():
							continue
						owner_hero.inventory = owner_hero.inventory + [picked.item]
						finds.append(String(data.heroes.items.get(picked.item, {}).get("name", picked.item)))
					"scroll":
						world.lore.append({"scroll": picked.scroll, "accountId": army.ownerAccountId, "siteId": null, "foundAt": at})
						for member in world.members:
							server.refresh_bonuses(world, int(member.accountId), at, changed)
						finds.append("the scroll \"%s\"" % data.lore.scrolls.get(picked.scroll, {}).get("name", picked.scroll))
	var entry := {"stage": stage_no, "name": stage.name, "stronghold": stage.stronghold, "won": result.won, "battleId": battle.id, "kills": kills, "lost": LocalBattle.total(lost)}
	after.raid = {"front": front, "depth": raid.depth, "stage": stage_no, "battles": raid.battles + [entry], "finds": raid.finds + finds}
	after.loot = taken
	var done: bool = not result.won or stage.stronghold or LocalBattle.total(LocalScouting.combatants(data, after.units)) == 0
	if done:
		LocalArmies.send_home(server, world, after, at)
	else:
		server.schedule(world, at + _stage_ms(data, world.speed), "raid_stage", {"armyId": army.id, "stage": stage_no + 1})
	var found := " and %s" % ", ".join(finds) if not finds.is_empty() else ""
	var title := "Your raid was beaten at the {name}"
	var body := "It turns for home with {loot} resources; {lost} of its men fell."
	if result.won:
		title = "Your raid sacked the {name}" if stage.stronghold else "Your raid won the battle of the {name}"
		body = "It comes home with {loot} resources{found}." if stage.stronghold else "{kills} of the enemy fell; it carries {loot} resources{found} and marches on."
	LocalInbox.tell(server, world, army.ownerAccountId, {"kind": "battle_result", "tier": "push" if done else "digest", "title": title, "body": body,
		"vars": {"name": stage.name, "kills": kills, "loot": int(LocalLogistics.total(taken)), "found": found, "lost": LocalBattle.total(lost)}}, at)
