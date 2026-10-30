class_name LocalBattles
extends RefCounted
## Hordes arriving, village battles and what follows for the local engine:
## server/src/scheduler/battles.ts and horde.ts, with the parts of waves.ts,
## camps.ts, leaders.ts, heroes.ts, outposts.ts and bridge.ts they call.
##
## Messages to players wait for the inbox (part 5). Armies come from
## cmd_armies.gd.

const RAIDING := ["marching", "battling", "arrived"]


# --- Arriving (scheduler/waves.ts) --------------------------------------------

static func on_wave_arrive(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var wave := server.find_wave(world, int(event.payload.waveId))
	var at := int(event.dueAt)
	# A horde held up in a field battle arrives later than first planned.
	if wave.is_empty() or wave.status != "marching" or (wave.arrivesAt != null and at < int(wave.arrivesAt)):
		return
	begin_rampage(server, world, wave, at)
	if wave.targetVillageId != null:
		var village := server.find_village(world, int(wave.targetVillageId))
		if village.ruin != null:
			# Another horde got here first: nothing left to fight for.
			_mark_struck(wave, int(village.id))
			move_on(server, world, wave, Vector2i(village.q, village.r), at, changed)
		else:
			start_battle(server, world, wave, int(village.id), at, changed)
	else:
		start_holy_city_battle(server, world, wave, at, changed)
	changed.append(["world"])


static func on_wave_disperse(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var wave := server.find_wave(world, int(event.payload.waveId))
	if wave.is_empty() or wave.status != "arrived":
		return
	wave.status = "dispersed"
	changed.append(["world"])


## The horde reached a target: its rampage clock starts (once).
static func begin_rampage(server: LocalServer, world: Dictionary, wave: Dictionary, at: int) -> void:
	if wave.rampageEndsAt == null:
		wave.rampageEndsAt = LocalTime.ms(at + (float(server.data.horde.rampageHours) * LocalTime.MS_PER_HOUR) / world.speed)


static func _mark_struck(wave: Dictionary, village_id: int) -> void:
	if not wave.struck.any(func(id: Variant) -> bool: return int(id) == village_id):
		wave.struck.append(village_id)


# --- Village battles (scheduler/battles.ts) ------------------------------------

## Whether a route came into `cell` over a river (sim/field.ts cameOverRiver).
static func came_over_river(path: Array, cell: Vector2i, rivers: Dictionary) -> bool:
	for i in path.size():
		if int(path[i].q) == cell.x and int(path[i].r) == cell.y:
			return i > 0 and rivers.has(LocalLand.edge_key(Vector2i(path[i - 1].q, path[i - 1].r), cell))
	return false


static func start_battle(server: LocalServer, world: Dictionary, wave: Dictionary, village_id: int, at: int, changed: Array) -> void:
	var data := server.data
	var village := server.find_village(world, village_id)
	# Units that finished training by now stand with the garrison; the
	# village's outposts stop producing while the battle lasts.
	var state := LocalVillage.set_besieged(data, LocalVillage.complete_training(village.state, at), true, at, world.speed)
	village.state = state
	wave.status = "battling"
	# Walls must be battered down; a horde without the siege to do it in time
	# builds engines first, and the assault waits for them.
	var setup := {}
	var rivers := {}
	for e in world.rivers:
		rivers[LocalLand.edge_key(e.a, e.b)] = true
	if came_over_river(wave.path if wave.path != null else [], Vector2i(village.q, village.r), rivers):
		setup.river = true
	var composition: Dictionary = wave.composition
	# As it arrived, before any engines built on site (the notice counts these).
	var arrived := LocalBattle.total(composition)
	var first_round := at + LocalBattle.round_ms(data, world.speed)
	var integrity := LocalWalls.wall_integrity(data, state.plots)
	if integrity > 0:
		var moat := LocalWalls.tower_level(state.plots, "ditch")
		setup.wall = {"level": LocalWalls.wall_level(state.plots), "integrity": integrity, "max": integrity}
		if moat > 0:
			setup.wall.moat = moat
		var works: Variant = LocalWalls.siege_works(data, wave.front, composition, integrity, state.plots, world.speed)
		if works != null:
			first_round += int(works.setupMs)
			composition = LocalCamps.add_units(composition, {works.engine: works.count})
			setup.siege = {"engine": works.engine, "count": works.count, "readyAt": LocalTime.iso(at + int(works.setupMs))}
			wave.composition = composition
	var battle := insert_battle(world, {"waveId": wave.id, "villageId": village_id, "q": village.q, "r": village.r, "setup": setup,
		"attackerStance": wave.stance, "attackerInitial": composition, "defenderInitial": state.garrison, "startedAt": at})
	server.schedule(world, first_round, "battle_round", {"battleId": battle.id})
	LocalArmies.rally_to_battle(server, world, battle, village, at)
	LocalInbox.tell(server, world, village.ownerAccountId, {"kind": "under_attack", "tier": "push", "title": "{village} is under attack",
		"body": "A horde of {enemy} is fighting your garrison of {defenders}.",
		"vars": {"village": village.name, "enemy": arrived, "defenders": LocalBattle.total(state.garrison)}}, at)
	changed.append(["village", village_id])


static func insert_battle(world: Dictionary, fields: Dictionary) -> Dictionary:
	var battle := {"id": world.next.battle, "waveId": null, "campId": null, "siteId": null, "villageId": null, "setup": {},
		"status": "ongoing", "round": 0, "rounds": [], "loot": null, "decision": null, "endedAt": null}
	battle.merge(fields, true)
	battle.attackerInitial = fields.attackerInitial.duplicate()
	battle.defenderInitial = fields.defenderInitial.duplicate()
	world.next.battle += 1
	world.battles.append(battle)
	return battle


static func find_battle(world: Dictionary, id: int) -> Dictionary:
	for b in world.battles:
		if int(b.id) == id:
			return b
	return {}


static func _record_round(battle: Dictionary, log: Dictionary, end: Variant) -> void:
	battle.round = log.round
	battle.rounds.append(log)
	battle.status = end.status if end != null else "ongoing"
	battle.endedAt = end.at if end != null else null
	battle.loot = end.loot if end != null and end.loot != null else null


## The horde's unit stats under its leader, striking `village_id`
## (scheduler/leaders.ts hordeStats): {stats, nerve, loot}.
static func horde_stats(server: LocalServer, world: Dictionary, wave: Dictionary, base: Callable, village_id: Variant) -> Dictionary:
	# Its hatred (horde.json hatred) adds to its attack and defense.
	var hatred := float(wave.get("hatred", 0.0))
	if hatred > 0:
		var unhated := base
		base = func(unit: String) -> Dictionary:
			var s: Dictionary = unhated.call(unit).duplicate()
			s.attack = float(s.attack) * (1.0 + hatred)
			s.defense = float(s.defense) * (1.0 + hatred)
			return s
	if wave.leaderId == null:
		return {"stats": base, "nerve": 0.0, "loot": 0.0}
	var leader := _leader(world, int(wave.leaderId))
	var effects := LocalHordes.leader_effects(server.data, leader)
	var grudge: bool = village_id != null and leader.grudgeVillageId != null and int(leader.grudgeVillageId) == int(village_id)
	var attack := 1.0 + float(effects.attack) + (float(server.data.leaders.grudge.attack) if grudge else 0.0)
	var defense := 1.0 + float(effects.defense)
	var stats := func(unit: String) -> Dictionary:
		var s: Dictionary = base.call(unit).duplicate()
		s.attack = float(s.attack) * attack
		s.defense = float(s.defense) * defense
		return s
	return {"stats": stats, "nerve": effects.nerve, "loot": effects.loot}


static func _leader(world: Dictionary, id: int) -> Dictionary:
	for l in world.leaders:
		if int(l.id) == id:
			return l
	return {}


## The hero standing in a village (db/heroes.ts heroAt).
static func hero_at(world: Dictionary, village_id: int) -> Dictionary:
	for h in world.heroes:
		if h.villageId != null and int(h.villageId) == village_id and h.status == "home":
			return h
	return {}


## Losses split over the forces that fought together (sim/armies.ts).
static func split_losses(losses: Dictionary, forces: Array) -> Array:
	var out: Array = forces.map(func(_f: Dictionary) -> Dictionary: return {})
	for unit in losses:
		var lost := int(losses[unit])
		var counts: Array = forces.map(func(f: Dictionary) -> int: return int(f.get(unit, 0)))
		var all := 0
		for c in counts:
			all += c
		if lost <= 0 or all <= 0:
			continue
		var take := mini(lost, all)
		var exact: Array = counts.map(func(c: int) -> float: return float(take * c) / all)
		var floors: Array = []
		var floored := 0
		for i in counts.size():
			floors.append(mini(counts[i], floori(exact[i])))
			floored += floors[i]
		var left := take - floored
		var order: Array = range(counts.size())
		order.sort_custom(func(a: int, b: int) -> bool:
			var fa: float = exact[a] - floorf(exact[a])
			var fb: float = exact[b] - floorf(exact[b])
			return fa > fb or (fa == fb and a < b))
		for i in order:
			if left <= 0:
				break
			if floors[i] < counts[i]:
				floors[i] += 1
				left -= 1
		for i in floors.size():
			if floors[i] > 0:
				out[i][unit] = floors[i]
	return out


## One round at a village. False when the battle is one the local engine
## doesn't fight yet (in the field, at the Holy City): it waits.
static func on_battle_round(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> bool:
	var data := server.data
	var battle := find_battle(world, int(event.payload.battleId))
	if battle.is_empty() or battle.status != "ongoing" or battle.waveId == null:
		return true
	if battle.villageId == null:
		return field_round(server, world, battle, int(event.dueAt), changed)
	var wave := server.find_wave(world, int(battle.waveId))
	var village := server.find_village(world, int(battle.villageId))
	var at := int(event.dueAt)
	var state := LocalVillage.complete_training(village.state, at)

	var round := int(battle.round) + 1
	# The hero standing in the village leads its garrison, with the general
	# commanding it.
	var hero := hero_at(world, int(village.id))
	var general := LocalGenerals.general_at(world, int(village.id))
	# The horde's leader drives it on, hardest against a village they hate.
	var led := horde_stats(server, world, wave, LocalBattle.enemy_stats(data, wave.front), village.id)
	var own := LocalVillage.village_bonuses(data, state)
	if wave.front == "north" and float(own.get("coldDefense", 0.0)) != 0.0:
		own = own.duplicate()
		own["defense.all"] = float(own.get("defense.all", 0.0)) + float(own.coldDefense)
	var heroic := LocalHeroes.combine(own, LocalHeroes.hero_bonuses(data, hero)) if not hero.is_empty() else own
	var bonuses := LocalHeroes.combine(heroic, LocalGenerals.bonuses(data, general)) if not general.is_empty() else heroic
	# The garrison fights alongside armies sent to help; armies joining this
	# round bring their pincer or harassment bonus.
	var engaged := LocalArmies.armies_in_battle(world, int(battle.id))
	var forces: Array = [state.garrison]
	for a in engaged:
		forces.append(a.units)
	var joining: Array = engaged.filter(func(a: Dictionary) -> bool: return a.joinsRound != null and int(a.joinsRound) == round)
	var surge := 1.0
	for a in joining:
		surge += float(a.joinBonus)
	# As they joined (losses below change the armies in place).
	var joined: Array = joining.map(func(a: Dictionary) -> Dictionary:
		return {"armyId": a.id, "villageId": a.homeVillageId, "orders": a.orders, "units": a.units.duplicate(), "bonus": a.joinBonus})
	var base_stats := LocalBattle.player_stats(data, bonuses, true)
	var rng := LocalBattle.battle_rng(int(world.seed), int(battle.id), round)
	var wall: Variant = battle.setup.get("wall")
	var standing: bool = wall != null and int(wall.integrity) > 0
	var smashed: Dictionary = LocalWalls.ballista_kills(data, wave.front, wave.composition, state.plots, rng) if standing else {}
	var assault := LocalCamps.subtract_units(wave.composition, smashed)
	var defenders := {}
	for f in forces:
		defenders = LocalCamps.add_units(defenders, f)
	var archers := 0
	for unit in defenders:
		if data.units.units.get(unit, {}).get("family") == "archers":
			archers += int(defenders[unit])
	var over := LocalWalls.over_the_walls(data, wave.front, assault, state.plots) if standing else 0.0
	var walls: Dictionary = LocalWalls.wall_factors(data, state.plots, archers, over) if standing else {"defense": 1.0, "attack": 1.0, "archers": 1.0}
	var held := LocalWalls.held_back(data, over) if standing else 1.0
	# A horde that came over a river into the fight strikes weaker.
	var river := float(data.field.river.attackerFactor) if battle.setup.get("river", false) else 1.0
	var led_stats: Callable = led.stats
	var result := LocalBattle.resolve_round(data,
		{"units": assault, "stance": battle.attackerStance, "home": false, "stats": func(unit: String) -> Dictionary:
			var s: Dictionary = led_stats.call(unit).duplicate()
			s.attack = float(s.attack) * river * (1.0 if s.family == "archers" else held)
			return s},
		{"units": defenders, "stance": state.stance, "home": true, "stats": func(unit: String) -> Dictionary:
			var s: Dictionary = base_stats.call(unit).duplicate()
			var shooting: float = walls.archers if s.family == "archers" else 1.0
			s.attack = float(s.attack) * surge * float(walls.attack) * shooting
			s.defense = float(s.defense) * float(walls.defense)
			return s},
		rng)
	var attacker_losses := LocalCamps.add_units(result.attackerLosses, smashed)
	var attacker_now := LocalCamps.subtract_units(wave.composition, attacker_losses)
	# The horde batters the walls with what came at them this round.
	var wall_left: Variant = null
	if standing:
		wall_left = maxi(0, LocalWaves.js_round(float(wall.integrity) - LocalWalls.siege_damage(data, wave.front, assault, state.plots)))
		var setup: Dictionary = battle.setup.duplicate(true)
		setup.wall.integrity = wall_left
		battle.setup = setup
	var shares := split_losses(result.defenderLosses, forces)
	var village_state := LocalVillage.lose_garrison(data, state, shares[0], at, world.speed)
	var defender_losses: Dictionary = shares[0].duplicate()
	var armies: Array = []
	for i in engaged.size():
		var army: Dictionary = engaged[i]
		var losses: Dictionary = shares[i + 1]
		# Harassers strike and ride off before the horde can close.
		if army.orders == "harass" and army.joinsRound != null and int(army.joinsRound) == round:
			var cut := {}
			for u in losses:
				cut[u] = floori(int(losses[u]) * float(data.armies.harass.lossFactor))
			losses = cut
		defender_losses = LocalCamps.add_units(defender_losses, losses)
		armies.append(LocalArmies.army_losses(server, world, army, losses, at))
	var leaving := func(a: Dictionary) -> bool: return a.orders == "harass" and a.joinsRound != null and int(a.joinsRound) == round
	var defenders_now: Dictionary = village_state.garrison.duplicate()
	for a in armies:
		if not leaving.call(a):
			defenders_now = LocalCamps.add_units(defenders_now, a.units)
	wave.composition = attacker_now
	# Every harassing strike makes the horde hate the more.
	var strikes := joining.filter(func(a: Dictionary) -> bool: return a.orders == "harass").size()
	if strikes > 0:
		wave.hatred = float(wave.get("hatred", 0.0)) + strikes * float(data.horde.hatred.perHarass)

	var outcome := LocalBattle.battle_outcome(data, {
		"round": round, "attackerStance": battle.attackerStance, "attackerInitial": battle.attackerInitial, "attackerNow": attacker_now,
		"defenderStance": state.stance, "defenderInitial": battle.defenderInitial, "defenderNow": defenders_now,
		"attackerNerve": float(data.enemies.fronts[wave.front].personality.nerve) * (1.0 + float(led.nerve)),
	})
	var log := {"round": round, "at": LocalTime.iso(at), "attackerLosses": attacker_losses, "defenderLosses": defender_losses,
		"attackerLeft": LocalBattle.total(attacker_now), "defenderLeft": LocalBattle.total(defenders_now)}
	if wall_left != null:
		log.wallLeft = wall_left
		log.breach = wall_left == 0
	if LocalBattle.total(smashed) > 0:
		log.smashed = smashed
	if over > 0:
		log.over = LocalWaves.js_round(over * 100) / 100.0
	if not joined.is_empty():
		log.joined = joined
	if not engaged.is_empty():
		log.garrisonLosses = shares[0]
	# Armies after the round: harassers ride home; when the battle is over,
	# support stays on guard and reinforcements go home.
	for army in armies:
		if leaving.call(army) or (outcome != "ongoing" and army.orders != "support"):
			LocalArmies.send_home(server, world, army, at)
		elif outcome != "ongoing":
			if LocalBattle.total(army.units) > 0:
				army.status = "stationed"
				army.battleId = null
				army.joinsRound = null
				army.joinBonus = 0
				LocalArmies.plan_hunger(server, world, army, at)
			else:
				army.status = "done"
		elif LocalBattle.total(army.units) == 0:
			army.status = "done"
	# Kills in the rounds before this one, for the leader.
	var kills_before := 0
	for r in battle.rounds:
		kills_before += LocalBattle.total(r.defenderLosses)

	var razed := false
	if outcome == "ongoing":
		_record_round(battle, log, null)
		server.schedule(world, at + LocalBattle.round_ms(data, world.speed), "battle_round", {"battleId": battle.id})
	elif outcome == "raided":
		# The horde decides: carry off what it can and move on, or stay and
		# burn the village to the ground.
		var decision := horde_wins(server, world, wave, village, attacker_now, at)
		razed = decision.choice == "raze"
		battle.decision = decision
		if decision.choice == "raid":
			var loot := LocalBattle.raid_loot(data, LocalLedger.amounts_at(village_state.ledger, at), battle.attackerInitial, attacker_now, bonuses,
				float(data.enemies.fronts[wave.front].personality.lootFactor) * (1.0 + float(led.loot)))
			# A raid, like a raze, burns whatever was being built.
			var lost_builds: int = village_state.queue.size()
			village_state = LocalVillage.plunder(village_state, loot, at)
			village_state.queue = []
			village_state = LocalVillage.set_besieged(data, village_state, false, at, world.speed)
			_record_round(battle, log, {"status": "raided", "at": at, "loot": loot})
			var body := "The horde carried off {loot} resources after {rounds} rounds."
			if lost_builds > 0:
				body += " The work on {buildings} building%s was lost." % ("" if lost_builds == 1 else "s")
			LocalInbox.tell(server, world, village.ownerAccountId, {"kind": "battle_result", "tier": "digest", "title": "{village} was raided",
				"body": body, "vars": {"village": village.name, "loot": int(LocalLogistics.total(loot)), "rounds": round, "buildings": lost_builds}}, at)
		else:
			_record_round(battle, log, {"status": "raided", "at": at, "loot": null})
			LocalInbox.tell(server, world, village.ownerAccountId, {"kind": "razing", "tier": "push", "title": "{village} is being razed",
				"body": "The horde broke the defenders after {rounds} rounds and is burning the village.",
				"vars": {"village": village.name, "rounds": round}}, at)
	else:
		village_state = LocalVillage.set_besieged(data, village_state, false, at, world.speed)
		# The hospital puts some of the garrison's fallen back on their feet.
		var fallen := {}
		for r in battle.rounds + [log]:
			fallen = LocalCamps.add_units(fallen, r.get("garrisonLosses", r.defenderLosses))
		var healed := LocalVillage.hospital_healed(LocalVillage.village_bonuses(data, village_state), fallen,
			LocalRng.new((int(world.seed) ^ LocalRng.imul(int(battle.id) + 1, 0x2545f491) ^ 0x4b) & 0xffffffff))
		var saved := LocalBattle.total(healed)
		if saved > 0:
			log.healed = healed
			village_state = LocalVillage.join_garrison(data, village_state, healed, at, world.speed)
		_record_round(battle, log, {"status": "defended", "at": at, "loot": null})
		horde_beaten(server, world, Vector2i(village.q, village.r), LocalBattle.total(battle.attackerInitial) - LocalBattle.total(attacker_now))
		LocalInbox.tell(server, world, village.ownerAccountId, {"kind": "battle_result", "tier": "digest", "title": "{village} held",
			"body": "The horde was beaten after {rounds} rounds; the hospital saved {healed} of the fallen." if saved > 0 else "The horde was beaten after {rounds} rounds.",
			"vars": {"village": village.name, "rounds": round, "healed": saved}}, at)
		finish_wave(server, world, wave, "defeated", at, changed)

	# A breach knocks the walls down a level.
	if outcome != "ongoing" and wall != null and int(wall_left if wall_left != null else wall.integrity) == 0:
		village_state = LocalVillage.breach_walls(data, village_state)
	village.state = village_state
	if outcome != "ongoing":
		leader_after(server, world, wave, {"hordeWon": outcome == "raided", "razed": razed, "kills": LocalBattle.total(defender_losses) + kills_before,
			"wiped": LocalBattle.total(attacker_now) == 0, "villageId": village.id}, at)
	# A raiding horde moves on once the village is saved.
	if outcome == "raided" and wave.status == "battling":
		move_on(server, world, wave, Vector2i(village.q, village.r), at, changed)
	if not hero.is_empty() and outcome != "ongoing":
		hero_after_battle(server, world, hero, {"kills": LocalBattle.total(battle.attackerInitial) - LocalBattle.total(attacker_now),
			"won": outcome != "raided", "battleId": battle.id, "at": at})
	if not general.is_empty() and outcome != "ongoing":
		LocalGenerals.after_battle(server, world, general, {"kills": LocalBattle.total(battle.attackerInitial) - LocalBattle.total(attacker_now),
			"won": outcome != "raided", "at": at})
	changed.append(["village", village.id])
	changed.append(["world"])
	return true


## A round away from the villages (scheduler/field.ts fieldRound): on open
## ground, or at the Holy City, whose guard fights beside any armies
## holding it.
static func field_round(server: LocalServer, world: Dictionary, battle: Dictionary, at: int, changed: Array) -> bool:
	var data := server.data
	var wave := server.find_wave(world, int(battle.waveId))
	var round := int(battle.round) + 1
	var engaged := LocalArmies.armies_in_battle(world, int(battle.id))
	var holy: bool = battle.setup.get("holyCity", false) == true
	var guard: Variant = battle.setup.get("guard", {}) if holy else null
	var leader: Dictionary = server.find_village(world, int(engaged[0].homeVillageId)) if not engaged.is_empty() else {}
	var stance: String = data.horde.holyCity.stance if holy else (leader.state.stance if not leader.is_empty() else "balanced")
	# The holders fight with their owner's research and the hero leading them.
	var hero: Dictionary = {}
	for army in engaged:
		if hero.is_empty():
			hero = LocalArmies.hero_with_army(world, int(army.id))
	var research: Dictionary = leader.state.bonuses if not leader.is_empty() else {}
	if wave.front == "north" and float(research.get("coldDefense", 0.0)) != 0.0:
		research = research.duplicate()
		research["defense.all"] = float(research.get("defense.all", 0.0)) + float(research.coldDefense)
	# And the best general among them.
	var general: Dictionary = {}
	for army in engaged:
		var g := LocalGenerals.general_with_army(world, int(army.id))
		if not g.is_empty() and (general.is_empty() or int(g.level) > int(general.level)):
			general = g
	var heroic: Dictionary = LocalHeroes.combine(research, LocalHeroes.hero_bonuses(data, hero)) if not hero.is_empty() else research
	var bonuses: Dictionary = LocalHeroes.combine(heroic, LocalGenerals.bonuses(data, general)) if not general.is_empty() else heroic
	var ground: Dictionary = battle.setup
	var first := round == 1
	var ambush: bool = ground.get("ambush", false) == true
	var hold_defense := 1.0
	if ground.get("fort", false):
		hold_defense += float(data.field.fort.defenseBonus)
	hold_defense += float(ground.get("wagonFort", 0))
	if ground.get("choke", false) and stance == "hold_the_line":
		hold_defense += float(data.field.choke.holdTheLineDefense)
	var hold_attack := (1.0 + float(data.field.ambush.bonus) + float(bonuses.get("ambush", 0.0))) if ambush and first else 1.0
	var horde_attack := (float(data.field.choke.attackerFactor) if ground.get("choke", false) else 1.0) * (float(data.field.river.attackerFactor) if ground.get("river", false) else 1.0)
	var forces: Array = []
	if guard != null:
		forces.append(guard)
	for army in engaged:
		forces.append(army.units)
	var holder_base := LocalBattle.player_stats(data, bonuses, false)
	var chief := horde_stats(server, world, wave, LocalBattle.enemy_stats(data, wave.front), null)
	var horde_base: Callable = chief.stats
	var defenders := {}
	for f in forces:
		defenders = LocalCamps.add_units(defenders, f)
	var result := LocalBattle.resolve_round(data,
		{"units": wave.composition, "stance": "balanced" if ambush and first else battle.attackerStance, "home": false,
			"stats": func(unit: String) -> Dictionary:
				var st: Dictionary = horde_base.call(unit).duplicate()
				st.attack = float(st.attack) * horde_attack
				return st},
		{"units": defenders, "stance": stance, "home": holy, "stats": func(unit: String) -> Dictionary:
			var st: Dictionary = holder_base.call(unit).duplicate()
			st.attack = float(st.attack) * hold_attack
			st.defense = float(st.defense) * hold_defense
			return st},
		LocalBattle.battle_rng(int(world.seed), int(battle.id), round))
	var attacker_now := LocalCamps.subtract_units(wave.composition, result.attackerLosses)
	wave.composition = attacker_now
	var shares := split_losses(result.defenderLosses, forces)
	var guard_now: Variant = LocalCamps.subtract_units(guard, shares[0]) if guard != null else null
	if guard_now != null:
		var setup: Dictionary = battle.setup.duplicate(true)
		setup.guard = guard_now
		battle.setup = setup
	var offset := 1 if guard != null else 0
	var armies: Array = []
	for i in engaged.size():
		armies.append(LocalArmies.army_losses(server, world, engaged[i], shares[i + offset], at))
	var defenders_now: Dictionary = guard_now.duplicate() if guard_now != null else {}
	for army in armies:
		defenders_now = LocalCamps.add_units(defenders_now, army.units)
	var outcome := LocalBattle.battle_outcome(data, {
		"round": round, "attackerStance": battle.attackerStance, "attackerInitial": battle.attackerInitial, "attackerNow": attacker_now,
		"defenderStance": stance, "defenderInitial": battle.defenderInitial, "defenderNow": defenders_now,
		"attackerNerve": float(data.enemies.fronts[wave.front].personality.nerve) * (1.0 + float(chief.nerve)),
	})
	var log := {"round": round, "at": LocalTime.iso(at), "attackerLosses": result.attackerLosses, "defenderLosses": result.defenderLosses,
		"attackerLeft": LocalBattle.total(attacker_now), "defenderLeft": LocalBattle.total(defenders_now)}
	if outcome == "ongoing":
		for army in armies:
			if LocalBattle.total(army.units) == 0:
				army.status = "done"
		_record_round(battle, log, null)
		server.schedule(world, at + LocalBattle.round_ms(data, world.speed), "battle_round", {"battleId": battle.id})
	else:
		var won := outcome == "defended"
		var kills := LocalBattle.total(battle.attackerInitial) - LocalBattle.total(attacker_now)
		# Beaten in the field, the horde's leader blames the army's village.
		var fallen := LocalBattle.total(result.defenderLosses)
		for r in battle.rounds:
			fallen += LocalBattle.total(r.defenderLosses)
		leader_after(server, world, wave, {"hordeWon": not won, "kills": fallen, "wiped": LocalBattle.total(attacker_now) == 0,
			"villageId": leader.id if not leader.is_empty() else null}, at)
		# Heroes first: a beaten hero is carried home wounded.
		for army in armies:
			var led := LocalArmies.hero_with_army(world, int(army.id))
			if led.is_empty():
				continue
			if not won:
				led.villageId = army.homeVillageId
				led.armyId = null
			hero_after_battle(server, world, led, {"kills": kills, "won": won, "battleId": battle.id, "at": at})
		for army in armies:
			var commander := LocalGenerals.general_with_army(world, int(army.id))
			if not commander.is_empty():
				LocalGenerals.after_battle(server, world, commander, {"kills": kills, "won": won, "at": at})
		for army in armies:
			if won and LocalBattle.total(army.units) > 0:
				army.status = "stationed"
				army.battleId = null
				army.joinsRound = null
				army.joinBonus = 0
			else:
				LocalArmies.send_home(server, world, army, at)
		_record_round(battle, log, {"status": "defended" if won else "raided", "at": at, "loot": null})
		if won:
			horde_beaten(server, world, Vector2i(battle.q, battle.r), kills)
			finish_wave(server, world, wave, "defeated", at, changed)
			# A strong point held: a choke, or a fort built on the horde's road.
			if ground.get("choke", false) or ground.get("fort", false):
				bridge_quest(server, world, "choke", at)
		elif holy:
			holy_city_falls(server, world, wave, attacker_now, at, changed)
		else:
			LocalArmies.march_on(server, world, wave, Vector2i(battle.q, battle.r), at)
		if holy:
			LocalInbox.tell_everyone(server, world, {"kind": "battle_result", "tier": "digest" if won else "push",
				"title": "The Holy City held" if won else "The Holy City was struck",
				"body": "The horde was beaten at its walls after {rounds} rounds." if won else "Its Sanctity fell to {sanctity}.",
				"vars": {"rounds": round} if won else {"sanctity": int(world.sanctity)}}, at)
		else:
			for owner in LocalArmies.owners(engaged):
				LocalInbox.tell(server, world, owner, {"kind": "battle_result", "tier": "digest",
					"title": "Your army held ({q}, {r})" if won else "Your army fell back from ({q}, {r})",
					"body": "The horde was beaten after {rounds} rounds." if won else "The horde marches on, {rounds} rounds late.",
					"vars": {"q": battle.q, "r": battle.r, "rounds": round}}, at)
	changed.append(["world"])
	return true


## A horde beat the Holy City's defenders: Sanctity falls by its survivors,
## and the horde, its rampage done, scatters. At none, the run is lost.
static func holy_city_falls(server: LocalServer, world: Dictionary, wave: Dictionary, survivors: Dictionary, at: int, changed: Array) -> void:
	var damage := LocalHorde.sanctity_damage(server.data, LocalBattle.total(survivors))
	if int(world.sanctity) - damage <= 0:
		world.status = "lost"
		world.endedAt = at
	world.sanctity = maxi(0, int(world.sanctity) - damage)
	finish_wave(server, world, wave, "dispersed", at, changed)
	if int(world.sanctity) <= 0:
		var lost: Dictionary = server.data.bridge.endings.lost
		LocalInbox.tell_everyone(server, world, {"kind": "ritual", "tier": "push", "title": lost.title, "body": lost.story}, at)


# --- The horde AI (scheduler/horde.ts) -----------------------------------------

## A horde was beaten here: hordes remember.
static func horde_beaten(server: LocalServer, world: Dictionary, cell: Vector2i, killed: int) -> void:
	var amount := LocalHorde.fear_left(server.data, killed)
	if amount <= 0:
		return
	var key := LocalLand.key(cell)
	world.fear[key] = float(world.fear.get(key, 0.0)) + amount


## Troops that could reach `village` in time: every other standing village
## whose reinforce rule covers it.
static func help_nearby(server: LocalServer, world: Dictionary, village: Dictionary) -> int:
	var help := 0
	for other in world.villages:
		if int(other.id) == int(village.id) or other.ruin != null or other.state.besieged:
			continue
		var rule: Dictionary = other.reinforce
		if float(rule.share) <= 0 or HexMath.distance(Vector2i(other.q, other.r), Vector2i(village.q, village.r)) > int(rule.range):
			continue
		var fighters := 0
		for unit in other.state.garrison:
			var def: Variant = server.data.units.units.get(unit)
			if def != null and def.family in ["infantry", "archers", "cavalry"] and unit != "settler" and int(other.state.garrison[unit]) > 0:
				fighters += int(other.state.garrison[unit])
		help += floori(fighters * float(rule.share))
	return help


## The horde beat the village's defenders: raid or raze?
static func horde_wins(server: LocalServer, world: Dictionary, wave: Dictionary, village: Dictionary, attacker_now: Dictionary, at: int) -> Dictionary:
	var data := server.data
	var rampage_left := (int(wave.rampageEndsAt) if wave.rampageEndsAt != null else at) - at
	var preset: Dictionary = data.difficulty.presets[world.difficulty]
	var decision := LocalHorde.decide_raze(data, {
		"front": wave.front, "waveIndex": wave.index, "graceWaves": preset.get("graceWaves"), "thresholdOffset": preset.get("razeThreshold"),
		"refuge": village.refuge == true, "hordeNow": LocalBattle.total(attacker_now), "hordeInitial": LocalBattle.total(wave.initial),
		"helpNearby": help_nearby(server, world, village), "rampageLeftMs": rampage_left, "worldSpeed": world.speed,
	})
	_mark_struck(wave, int(village.id))
	if decision.choice == "raze":
		var ends_at := LocalTime.ms(at + LocalHorde.raze_ms(data, world.speed))
		wave.status = "razing"
		wave.endsAt = ends_at
		server.schedule(world, ends_at, "wave_raze", {"waveId": wave.id, "villageId": village.id})
	else:
		wave.composition = LocalHorde.recruit(data, wave.initial, attacker_now)
	return decision


## Villages, outposts, forts, camps and sites (horde.ts takenHexes).
static func taken_hexes(world: Dictionary) -> Dictionary:
	var taken := {}
	for v in world.villages:
		taken[LocalLand.key(Vector2i(v.q, v.r))] = true
		for plot in LocalVillage.outpost_plots(v.state.plots):
			taken[LocalLand.key(LocalVillage.outpost_hex(plot))] = true
	for c in world.camps:
		if c.status == "active":
			taken[LocalLand.key(Vector2i(c.q, c.r))] = true
	for s in world.sites:
		taken[LocalLand.key(Vector2i(s.q, s.r))] = true
	return taken


## The rampage is over: survivors make camp near where they stand.
static func settle(server: LocalServer, world: Dictionary, wave: Dictionary, from: Vector2i, at: int, changed: Array) -> void:
	var units: Dictionary = wave.composition
	var site: Variant = LocalHorde.camp_site(server.data, world.hexes, from, taken_hexes(world)) if LocalBattle.total(units) > 0 else null
	if site == null:
		finish_wave(server, world, wave, "dispersed", at, changed)
	else:
		create_camp(server, world, {"kind": "lair" if wave.front == "north" else "bandit", "front": wave.front, "q": site.x, "r": site.y,
			"units": units, "waveId": wave.id}, at)
		wave.status = "settled"
		wave.endsAt = at
		_after_wave(server, world, wave, at)
		LocalInbox.tell_everyone(server, world, {"kind": "camp", "tier": "digest",
			"title": "Monsters made a lair at ({q}, {r})" if wave.front == "north" else "Raiders made camp at ({q}, {r})",
			"body": "{count} survivors of wave {wave} settled there.",
			"vars": {"q": site.x, "r": site.y, "count": LocalBattle.total(units), "wave": int(wave.index) + 1}}, at)
	changed.append(["world"])


## After a raid or raze at `from`: on to the next village it hasn't struck
## (or the Holy City), if the rampage clock allows; otherwise settle.
static func move_on(server: LocalServer, world: Dictionary, wave: Dictionary, from: Vector2i, at: int, changed: Array) -> void:
	var data := server.data
	var ends_at: Variant = wave.rampageEndsAt
	if ends_at == null or at >= int(ends_at) or LocalBattle.total(wave.composition) == 0:
		settle(server, world, wave, from, at, changed)
		return
	var villages: Array = []
	for v in world.villages:
		if v.ruin == null and not wave.struck.any(func(id: Variant) -> bool: return int(id) == int(v.id)):
			villages.append({"id": v.id, "q": v.q, "r": v.r})
	var targets: Array = LocalHordes.targets_of(villages).filter(func(t: Dictionary) -> bool: return t.cell != from)
	var since_spawn := at - int(wave.spawnAt)
	var route: Variant = LocalHordes.route_from(data, LocalHordes.land_of(world), from, targets, wave.front, wave.composition,
		LocalHordes.fear_of(server, world), LocalWaves.rng_for(int(world.seed), int(wave.index), 0x90 + wave.struck.size()), since_spawn, world.speed)
	if route == null:
		settle(server, world, wave, from, at, changed)
		return
	var march := LocalHordes.hold_for_quiet(world, int(wave.spawnAt), {"path": route.path, "arrivesAt": int(wave.spawnAt) + int(route.arrivesMs)})
	if int(march.arrivesAt) > int(ends_at):
		settle(server, world, wave, from, at, changed)
		return
	wave.status = "marching"
	wave.targetVillageId = route.targetVillageId
	wave.path = march.path
	wave.arrivesAt = march.arrivesAt
	wave.endsAt = null
	# Its timetable changed: raids and intercepts planned on the old road go.
	world.events = world.events.filter(func(e: Dictionary) -> bool:
		return not (e.status == "pending" and e.type in ["outpost_raid", "supply_raid", "field_intercept"] and int(e.payload.get("waveId", -1)) == int(wave.id)))
	server.schedule(world, int(march.arrivesAt), "wave_arrive", {"waveId": wave.id})
	LocalHordes.plan_raids(server, world, wave, since_spawn + 1)
	LocalArmies.plan_intercepts(server, world, wave, since_spawn + 1)
	LocalHordes.plan_warning(server, world, wave, at)
	changed.append(["world"])


## Everything burned: fields and buildings at 0, stores and troops gone.
static func ruined_state(data: Dictionary, state: Dictionary, at: int, world_speed: float) -> Dictionary:
	var next := state.duplicate(true)
	next.plots = LocalHorde.ruin_plots(state.plots)
	next.levels = LocalVillage.levels_of(next.plots)
	next.queue = []
	next.training = []
	next.garrison = {}
	next.besieged = false
	next.ledger.amounts = {"wood": 0, "stone": 0, "grain": 0, "iron": 0}
	next.ledger.settledAt = at
	next.ledger = LocalLedger.with_rates(next.ledger, at, LocalVillage.village_rates(data, next, world_speed), LocalVillage.capacity(data, next.plots, state.bonuses))
	return next


static func ruin_village(server: LocalServer, world: Dictionary, village: Dictionary, at: int) -> void:
	if village.ruin != null:
		return
	if LocalVillage.research_per_hour(server.data, village.state.plots, world.speed) > 0 and village.ownerAccountId != null:
		LocalResearch.settle_points(server, world, int(village.ownerAccountId), at)
	var data := server.data
	var plots: Dictionary = village.state.plots.duplicate(true)
	village.state = ruined_state(data, village.state, at, world.speed)
	village.ruin = {"plots": plots, "since": LocalTime.iso(at), "rebuildingUntil": null}
	LocalInbox.tell(server, world, village.ownerAccountId, {"kind": "razed", "tier": "push", "title": "{village} was razed",
		"body": "Only ruins are left. Rebuild them, or start over from what remains.", "vars": {"village": village.name}}, at)
	# Nothing left standing: a refugee camp by the Holy City.
	var owner := int(village.ownerAccountId)
	var standing: Array = world.villages.filter(func(v: Dictionary) -> bool: return int(v.ownerAccountId) == owner and v.ruin == null and v.id != village.id)
	var site: Variant = LocalHorde.refugee_site(data, world.hexes, taken_hexes(world)) if standing.is_empty() else null
	if site != null:
		var member: Dictionary = {}
		for m in world.members:
			if int(m.accountId) == owner:
				member = m
		var name := String(data.horde.refugeeCamp.name).replace("{owner}", member.get("displayName", "Refugees"))
		var camp := server.insert_village(world, owner, name, site,
			LocalVillage.new_village(data, at, world.speed, {"startingResources": data.buildings.village.startingResources, "adminUpkeep": 0,
				"bonuses": server.player_bonuses(world, owner)}))
		camp.refuge = true
		LocalInbox.tell(server, world, owner, {"kind": "refuge", "tier": "push", "title": "A refuge by the Holy City",
			"body": "{camp} takes in your people at ({q}, {r}).", "vars": {"camp": camp.name, "q": site.x, "r": site.y}}, at)


static func on_wave_raze(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var wave := server.find_wave(world, int(event.payload.waveId))
	if wave.is_empty() or wave.status != "razing":
		return
	var village := server.find_village(world, int(event.payload.villageId))
	ruin_village(server, world, village, int(event.dueAt))
	move_on(server, world, wave, Vector2i(village.q, village.r), int(event.dueAt), changed)
	changed.append(["village", village.id])
	changed.append(["world"])


static func on_village_rebuilt(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var village := server.find_village(world, int(event.payload.villageId))
	var ruin: Variant = village.get("ruin")
	if ruin == null or ruin.rebuildingUntil == null or LocalTime.parse(ruin.rebuildingUntil) > int(event.dueAt):
		return
	if LocalVillage.research_per_hour(server.data, ruin.plots, world.speed) > 0 and village.ownerAccountId != null:
		LocalResearch.settle_points(server, world, int(village.ownerAccountId), int(event.dueAt))
	var next: Dictionary = village.state.duplicate(true)
	for plot in ruin.plots:
		next.plots[plot] = ruin.plots[plot]
	next.levels = LocalVillage.levels_of(next.plots)
	next.ledger = LocalLedger.with_rates(village.state.ledger, int(event.dueAt), LocalVillage.village_rates(server.data, next, world.speed),
		LocalVillage.capacity(server.data, next.plots, next.bonuses))
	village.state = next
	village.ruin = null
	LocalInbox.tell(server, world, village.ownerAccountId, {"kind": "build_done", "tier": "push", "title": "{village} stands again",
		"body": "Its fields and buildings are rebuilt as they were.", "vars": {"village": village.name}}, int(event.dueAt))
	changed.append(["village", village.id])
	changed.append(["world"])


## A horde at the Holy City fights its guard and anyone holding the city.
static func start_holy_city_battle(server: LocalServer, world: Dictionary, wave: Dictionary, at: int, _changed: Array) -> void:
	var guard := LocalHorde.holy_city_guard(server.data, int(wave.index))
	wave.status = "battling"
	# In the order db/armies.ts listArmies gives them: newest first.
	var holders: Array = world.armies.filter(func(a: Dictionary) -> bool:
		return a.targetVillageId == null and int(a.targetQ) == 0 and int(a.targetR) == 0 and a.status == "stationed")
	holders.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.departsAt) > int(b.departsAt) or (int(a.departsAt) == int(b.departsAt) and int(a.id) > int(b.id)))
	var defenders: Dictionary = guard.duplicate()
	for army in holders:
		for unit in army.units:
			defenders[unit] = int(defenders.get(unit, 0)) + int(army.units[unit])
	var battle := insert_battle(world, {"waveId": wave.id, "villageId": null, "q": 0, "r": 0, "setup": {"holyCity": true, "guard": guard},
		"attackerStance": wave.stance, "attackerInitial": wave.composition, "defenderInitial": defenders, "startedAt": at})
	for army in holders:
		army.status = "engaged"
		army.battleId = battle.id
		army.joinsRound = 1
		army.joinBonus = 0
	server.schedule(world, at + LocalBattle.round_ms(server.data, world.speed), "battle_round", {"battleId": battle.id})
	LocalInbox.tell_everyone(server, world, {"kind": "under_attack", "tier": "push", "title": "A horde is at the Holy City",
		"body": "{enemy} of them against its guard of {defenders}.",
		"vars": {"enemy": LocalBattle.total(wave.composition), "defenders": LocalBattle.total(defenders)}}, at)


# --- Outposts (scheduler/outposts.ts) ------------------------------------------

static func on_outpost_raid(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var p: Dictionary = event.payload
	var wave := server.find_wave(world, int(p.waveId))
	if wave.is_empty() or not wave.status in RAIDING:
		return
	var village := server.find_village(world, int(p.villageId))
	var before: Variant = village.state.plots.get(p.plot)
	var state := LocalVillage.raid_outpost(server.data, village.state, p.plot, int(event.dueAt), world.speed)
	var after: Variant = state.plots.get(p.plot)
	if before == null or after == null or int(after.level) == int(before.level):
		return
	village.state = state
	var cell := LocalVillage.outpost_hex(p.plot)
	world.raids.append({"id": world.next.raid, "waveId": wave.id, "villageId": village.id, "q": cell.x, "r": cell.y,
		"levelAfter": after.level, "at": int(event.dueAt)})
	world.next.raid += 1
	LocalInbox.tell(server, world, village.ownerAccountId, {"kind": "outpost_raided", "tier": "push", "title": "A horde burned an outpost of {village}",
		"body": "The outpost at ({q}, {r}) is down to level {level}." if int(after.level) > 0 else "The outpost at ({q}, {r}) lies in ruins.",
		"vars": {"village": village.name, "q": cell.x, "r": cell.y, "level": int(after.level)}}, int(event.dueAt))
	changed.append(["village", village.id])
	changed.append(["world"])


## A horde comes by a supply point: with no army standing on it, it burns.
static func on_supply_raid(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var p: Dictionary = event.payload
	var wave := server.find_wave(world, int(p.waveId))
	if wave.is_empty() or not wave.status in RAIDING:
		return
	var point := LocalArmies.find_fort(world, int(p.fortId))
	if point.is_empty() or point.get("kind", "fort") != "supply":
		return
	if not LocalArmies.armies_holding(world, Vector2i(point.q, point.r), ["stationed", "engaged"]).is_empty():
		return
	world.forts.erase(point)
	LocalInbox.tell(server, world, point.ownerAccountId, {"kind": "outpost_raided", "tier": "push", "title": "A horde burned the supply point at ({q}, {r})",
		"body": "Its {grain} grain burned with it.", "vars": {"q": point.q, "r": point.r, "grain": floori(float(point.grain))}}, int(event.dueAt))
	changed.append(["world"])


# --- Camps (scheduler/camps.ts) ---------------------------------------------------

static func create_camp(server: LocalServer, world: Dictionary, camp: Dictionary, at: int) -> Dictionary:
	var created := {"id": world.next.camp, "status": "active", "createdAt": at}
	created.merge(camp.duplicate(true), true)
	world.next.camp += 1
	world.camps.append(created)
	server.schedule(world, LocalTime.ms(at + (float(server.data.camps.growth.everyHours) * LocalTime.MS_PER_HOUR) / world.speed), "camp_grow",
		{"campId": created.id})
	LocalLogistics.plan_ambushes_for(server, world, at)
	return created


## Every occupied hex: villages, outposts, forts, camps and sites.
static func occupied_hexes(world: Dictionary) -> Dictionary:
	return taken_hexes(world)


## A wave is over: new camps of its front rise near its road.
static func spawn_after_wave(server: LocalServer, world: Dictionary, wave: Dictionary, at: int) -> void:
	var data := server.data
	var rules: Dictionary = data.camps.spawn
	var active: int = world.camps.filter(func(c: Dictionary) -> bool: return c.status == "active" and c.front == wave.front).size()
	var exact := float(rules.perWave) * float(data.difficulty.presets[world.difficulty].campRate)
	var roll := LocalWaves.rng_for(int(world.seed), int(wave.index), 0xcb).next()
	var per_wave := floori(exact) + (1 if roll < exact - floorf(exact) else 0)
	# A horde that came to hate leaves more camps behind, beyond the limit:
	# the whole part of hatred x campChance surely, the rest by chance.
	var hate := float(wave.get("hatred", 0.0)) * float(data.horde.hatred.campChance)
	var hated := floori(hate) + (1 if LocalWaves.rng_for(int(world.seed), int(wave.index), 0xcc).next() < hate - floorf(hate) else 0)
	var count := maxi(0, mini(per_wave, int(rules.max) - active)) + hated
	if count <= 0 or wave.path == null:
		return
	var villages: Array = world.villages.map(func(v: Dictionary) -> Vector2i: return Vector2i(v.q, v.r))
	var sites := LocalCamps.spawn_sites(data, world.hexes, wave.path, villages, occupied_hexes(world), LocalWaves.rng_for(int(world.seed), int(wave.index), 0xca), count)
	for i in sites.size():
		var cell: Vector2i = sites[i]
		var units := LocalWaves.compose_wave(data, wave.front, int(wave.index), LocalCamps.camp_size(data, int(wave.index)), int(world.seed) ^ (0xc0 + i), world.members.size())
		create_camp(server, world, {"kind": "lair" if wave.front == "north" else "bandit", "front": wave.front, "q": cell.x, "r": cell.y,
			"units": units, "waveId": wave.id}, at)


## Ends a wave and lets its camps rise (finishWave).
static func finish_wave(server: LocalServer, world: Dictionary, wave: Dictionary, status: String, at: int, changed: Array) -> void:
	wave.status = status
	wave.endsAt = at
	_after_wave(server, world, wave, at)
	changed.append(["world"])


## spawnAfterWave and the "unscathed" bridge quest (afterSettling).
static func _after_wave(server: LocalServer, world: Dictionary, wave: Dictionary, at: int) -> void:
	spawn_after_wave(server, world, wave, at)
	bridge_quest(server, world, "unscathed", at)


static func on_camp_grow(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	var camp: Dictionary = {}
	for c in world.camps:
		if int(c.id) == int(event.payload.campId):
			camp = c
	if camp.is_empty() or camp.status != "active":
		return
	camp.units = LocalCamps.grow(server.data, camp.units)
	server.schedule(world, LocalTime.ms(int(event.dueAt) + (float(server.data.camps.growth.everyHours) * LocalTime.MS_PER_HOUR) / world.speed),
		"camp_grow", {"campId": camp.id})
	changed.append(["world"])


# --- The bridge (scheduler/bridge.ts) ------------------------------------------

## Something happened that may answer a quest of the open stage.
static func bridge_quest(server: LocalServer, world: Dictionary, quest: String, at: int) -> void:
	if world.status != "running":
		return
	var bridge: Dictionary = world.bridge
	if quest == "unscathed" and int(world.sanctity) < int(bridge.sanctityAtStart):
		return
	var done: Variant = LocalBridge.complete_quest(server.data, bridge, quest, at)
	if done == null:
		return
	var stage: Dictionary = LocalBridge.current_stage(server.data, done)
	var story := ""
	for q in stage.quests:
		if q.kind == quest:
			story = q.get("story", "")
			break
	LocalInbox.tell_everyone(server, world, {"kind": "bridge", "tier": "digest", "title": "{stage}: {quest}", "body": story,
		"vars": {"stage": stage.name, "quest": server.data.bridge.quests[quest].name}}, at)
	settle_bridge(server, world, done, at)


## Saves the bridge, and starts raising the stage once nothing is missing.
static func settle_bridge(server: LocalServer, world: Dictionary, bridge: Dictionary, at: int) -> void:
	var next := bridge
	if LocalBridge.is_ready(server.data, next):
		next = LocalBridge.start_raising(server.data, next, at, world.speed)
		server.schedule(world, LocalTime.parse(next.raisedAt), "bridge_raised", {"stage": next.stage})
		LocalInbox.tell_everyone(server, world, {"kind": "bridge", "tier": "digest", "title": "Raising {stage}",
			"body": "Everything it needs is in place; the builders are at work.", "vars": {"stage": LocalBridge.current_stage(server.data, next).name}}, at)
	world.bridge = next


# --- Leaders and heroes after a battle ------------------------------------------

## scheduler/leaders.ts leaderAfter.
static func leader_after(server: LocalServer, world: Dictionary, wave: Dictionary, outcome: Dictionary, at: int) -> void:
	if wave.leaderId == null:
		return
	var leader := _leader(world, int(wave.leaderId))
	if leader.status == "dead":
		return
	var after := LocalHordes.leader_after_battle(server.data, wave.front, leader, outcome, world.speed)
	var title_before := LocalHordes.leader_title(server.data, wave.front, leader)
	var level_before := int(leader.level)
	var state: Dictionary = after.state
	leader.level = state.level
	leader.xp = state.xp
	leader.skills = state.skills
	leader.battles = int(leader.battles) + 1
	leader.wins = int(leader.wins) + (1 if outcome.hordeWon else 0)
	leader.losses = int(leader.losses) + (0 if outcome.hordeWon else 1)
	leader.razed = int(leader.razed) + (1 if outcome.get("razed", false) else 0)
	leader.kills = int(leader.kills) + int(outcome.kills)
	leader.status = "dead" if after.dead else "alive"
	leader.diedAt = at if after.dead else null
	if int(after.woundMs) != 0:
		leader.woundedUntil = at + int(after.woundMs)
	if not (after.grudge is String and after.grudge == "keep"):
		leader.grudgeVillageId = after.grudge
	if after.dead:
		LocalInbox.tell_everyone(server, world, {"kind": "leader", "tier": "digest", "title": "{leader} has fallen",
			"body": "{leader} died with the last of the horde after {battles} battles. Another will rise to take their place.",
			"vars": {"leader": LocalHordes.leader_title(server.data, wave.front, leader), "battles": int(leader.battles)}}, at)
	elif int(leader.level) > level_before:
		LocalInbox.tell_everyone(server, world, {"kind": "leader", "tier": "digest", "title": "{leader} grows stronger",
			"body": "{leader} is now level {level}.", "vars": {"leader": title_before, "level": int(leader.level)}}, at)


## scheduler/heroes.ts heroAfterBattle.
static func hero_after_battle(server: LocalServer, world: Dictionary, hero: Dictionary, result: Dictionary) -> void:
	var data := server.data
	var next := LocalHeroes.gain_xp(data, hero, int(result.kills) * LocalHeroes.hero_factor(data, hero.kind, "heroXp"))
	if result.won:
		var item: Variant = LocalHeroes.roll_drop(data, next, int(world.seed), int(result.battleId))
		if item != null:
			next.inventory = next.inventory + [item]
	else:
		var wounded_until := int(result.at) + LocalHeroes.wound_ms(data, world.speed, hero.kind, LocalGenerals.hall_level_at(server, world, hero.villageId))
		next.status = "wounded"
		next.woundedUntil = LocalTime.iso(wounded_until)
		server.schedule(world, wounded_until, "hero_recover", {"accountId": hero.accountId})
	var level_before := int(hero.level)
	hero.merge(next, true)
	if not result.won:
		LocalInbox.tell(server, world, hero.accountId, {"kind": "hero", "tier": "digest", "title": "{name} is wounded",
			"body": "Back on their feet in a few hours.", "vars": {"name": hero.name}}, int(result.at))
	elif int(hero.level) > level_before:
		LocalInbox.tell(server, world, hero.accountId, {"kind": "hero", "tier": "digest", "title": "{name} reached level {level}",
			"body": "A new skill point to spend.", "vars": {"name": hero.name, "level": int(hero.level)}}, int(result.at))


static func on_hero_recover(server: LocalServer, world: Dictionary, event: Dictionary, changed: Array) -> void:
	for hero in world.heroes:
		if int(hero.accountId) != int(event.payload.accountId):
			continue
		if hero.status != "wounded" or hero.woundedUntil == null or LocalTime.parse(hero.woundedUntil) > int(event.dueAt):
			return
		hero.status = "home"
		hero.woundedUntil = null
		changed.append(["world"])
