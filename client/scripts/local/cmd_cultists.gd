class_name LocalCultists
extends RefCounted
## Cultists of Černobog (scheduler/cultists.ts, events.json ritual): they
## camp and work a ritual; every soldier who falls fighting them brings its
## end nearer. If it ends, the Avatar of Černobog rises where they stood and
## marches on the villages like a horde.

const MS_PER_HOUR := 3600000.0
const MS_PER_MINUTE := 60000.0


## startRitual: the cultists' camp, its ritual ending `hours` from now.
static func start(server: LocalServer, world: Dictionary, cell: Vector2i, front: String, guards: Dictionary, at: int) -> Dictionary:
	var ends_at := LocalTime.ms(at + float(server.data.events.kinds.ritual.hours) * MS_PER_HOUR / world.speed)
	var camp := LocalBattles.create_camp(server, world, {"kind": "cultists", "front": front, "q": cell.x, "r": cell.y,
		"units": guards.duplicate(), "waveId": null, "reward": null, "endsAt": ends_at}, at)
	server.schedule(world, ends_at, "map_event_end", {"campId": camp.id})
	return camp


## quickenRitual: soldiers fell fighting the cultists; it ends the sooner.
static func quicken(server: LocalServer, world: Dictionary, camp: Dictionary, fallen: int, at: int) -> void:
	if fallen <= 0 or camp.get("endsAt") == null:
		return
	var sooner := maxi(at, LocalTime.ms(int(camp.endsAt) - float(fallen) * float(server.data.events.kinds.ritual.minutesPerFallen) * MS_PER_MINUTE / world.speed))
	camp.endsAt = sooner
	server.schedule(world, sooner, "map_event_end", {"campId": camp.id})


## ritualEnds: the cultists are gone, and the Avatar rises in their place.
static func ritual_ends(server: LocalServer, world: Dictionary, camp: Dictionary, due_at: int, changed: Array) -> void:
	if camp.status != "active" or camp.kind != "cultists" or camp.get("endsAt") == null or int(camp.endsAt) != due_at:
		return
	world.camps.erase(camp)
	var data := server.data
	var rules: Dictionary = data.events.kinds.ritual
	var levels: Array = data.waves.threatLevels
	var last := LocalBridgeCommands._last_horde(world)
	var composition := {String(rules.avatar): 1}
	var wave := {"id": world.next.wave, "index": int(last.index) if not last.is_empty() else 0, "front": camp.front, "status": "scheduled", "threat": levels[-1].name,
		"stance": "offensive", "composition": composition, "initial": composition.duplicate(), "spawnAt": due_at,
		"spawn": null, "targetVillageId": null, "path": null, "arrivesAt": null, "endsAt": null, "rampageEndsAt": null, "struck": [],
		"ritual": false, "leaderId": null, "hatred": 0.0, "bandOf": last.id if not last.is_empty() else null, "errand": {"kind": "avatar", "target": null, "from": {"q": int(camp.q), "r": int(camp.r)}}}
	world.next.wave += 1
	world.waves.append(wave)
	server.schedule(world, due_at, "wave_spawn", {"waveId": wave.id})
	for member in world.members:
		LocalInbox.tell(server, world, member.accountId, {"kind": "event", "tier": "push", "title": "The Avatar of Černobog walks at ({q}, {r})",
			"body": "The ritual is done. The Black God takes flesh and marches on the villages. Slay it for a great bounty.", "vars": {"q": camp.q, "r": camp.r}}, due_at)
	LocalAchievements.achieve_all(server, world, "avatar_risen", due_at)
	changed.append(["world"])


## sendAvatar: it marches from where it rose on the villages, choosing as
## a horde does; with none to reach, it sinks away.
static func send(server: LocalServer, world: Dictionary, wave: Dictionary, at: int) -> void:
	var from := Vector2i(int(wave.errand.from.q), int(wave.errand.from.r))
	# The Avatar goes for every village before the Holy City; those who fled a
	# burnt camp for the villages alone.
	var targets: Array = []
	if LocalBattles.is_avatar(wave):
		targets = LocalBattles.avatar_targets(world.villages)
	else:
		for v in world.villages:
			if v.ruin == null and v.ownerAccountId != null:
				targets.append({"id": v.id, "cell": Vector2i(v.q, v.r)})
	var route: Variant = null
	if not targets.is_empty():
		route = LocalHordes.route_from(server.data, LocalHordes.land_of(world), from, targets, wave.front, wave.composition, {}, LocalWaves.rng_for(int(world.seed), int(wave.index), 0xf7 if wave.errand.kind == "fled" else 0xa7), 0.0, world.speed)
	if route == null:
		wave.status = "dispersed"
		wave.endsAt = at
		return
	var march := {"path": route.path, "arrivesAt": at + int(route.arrivesMs)}
	# Those who fled a fire wait out the group's quiet hours like any horde.
	if wave.errand.kind == "fled":
		march = LocalHordes.hold_for_quiet(world, int(wave.spawnAt), march)
	wave.status = "marching"
	wave.spawn = {"q": from.x, "r": from.y}
	wave.targetVillageId = route.targetVillageId
	wave.path = march.path
	wave.arrivesAt = int(march.arrivesAt)
	server.schedule(world, int(wave.arrivesAt), "wave_arrive", {"waveId": wave.id})
	LocalHordes.plan_raids(server, world, wave, 0)
	LocalArmies.plan_intercepts(server, world, wave)
	LocalHordes.plan_warning(server, world, wave, at)


## avatarEnds: the Avatar beaten, every member gets the great bounty.
static func avatar_ends(server: LocalServer, world: Dictionary, wave: Dictionary, status: String, at: int, changed: Array) -> void:
	var errand: Variant = wave.get("errand")
	if not errand is Dictionary or errand.kind != "avatar" or status != "defeated":
		return
	var data := server.data
	var bounty := LocalEvents.bounty_at(data, world, at)
	var factor := float(data.events.kinds.ritual.avatarBountyFactor)
	var great := LocalVillage.resources(func(k: String) -> int: return LocalWaves.js_round(float(bounty[k]) * factor))
	var owners := {}
	for v in world.villages:
		if v.ruin == null and v.ownerAccountId != null:
			owners[int(v.ownerAccountId)] = true
	for member in world.members:
		if owners.has(int(member.accountId)):
			server.reward(world, int(member.accountId), great, at, changed)
		LocalInbox.tell(server, world, member.accountId, {"kind": "event", "tier": "push", "title": "The Avatar of Černobog is slain",
			"body": "Its flesh falls to ash. Every village of the group gets {bounty} resources.", "vars": {"bounty": LocalBattle.total(great)}}, at)
	LocalAchievements.achieve_all(server, world, "avatar_slain", at)
