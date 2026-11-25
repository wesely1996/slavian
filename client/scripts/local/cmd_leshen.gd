class_name LocalLeshen
extends RefCounted
## The Leshen, the wrath of nature (scheduler/leshen.ts, events.json
## leshen): a forest a player sets alight may wake him. He rises from the
## ashes with monsters of the North and marches like the Avatar of
## Černobog. Slaying his whole host brings a great bounty.


## leshenSeed: the roll for a fire burnt out on `cell` at `at` (ms).
static func seed_for(world: Dictionary, cell: Vector2i, at: int) -> int:
	return (int(world.seed) ^ LocalRng.imul(cell.x + 0x3c1, 0x45d9f3b) ^ LocalRng.imul(cell.y + 0x7f1, 0x27d4eb2d) ^ floori(float(at) / 60000.0)) & 0xffffffff


## maybeLeshen: a forest a player set alight has burnt out on `cell`.
static func maybe_rise(server: LocalServer, world: Dictionary, cell: Vector2i, at: int, changed: Array) -> void:
	var seed_value := seed_for(world, cell, at)
	if LocalRng.new(seed_value).next() < float(server.data.events.leshen.chance):
		rise(server, world, cell, at, seed_value, changed)


## leshenRises: he rises on `cell` with his host, and marches.
static func rise(server: LocalServer, world: Dictionary, cell: Vector2i, at: int, seed_value: int, changed: Array) -> void:
	var data := server.data
	var rules: Dictionary = data.events.leshen
	var levels: Array = data.waves.threatLevels
	# Like the Avatar, he goes as a band of the latest horde, on his own errand.
	var last := LocalBridgeCommands._last_horde(world)
	var index := int(last.index) if not last.is_empty() else 0
	var minions := LocalWaves.compose_wave(data, "north", maxi(1, index), int(rules.minions), seed_value, maxi(1, world.members.size()))
	var composition := {String(rules.unit): 1}
	composition.merge(minions)
	var wave := {"id": world.next.wave, "index": index, "front": "north", "status": "scheduled", "threat": levels[-1].name,
		"stance": "offensive", "composition": composition, "initial": composition.duplicate(), "spawnAt": at,
		"spawn": null, "targetVillageId": null, "path": null, "arrivesAt": null, "endsAt": null, "rampageEndsAt": null, "struck": [],
		"ritual": false, "leaderId": null, "hatred": 0.0, "bandOf": last.id if not last.is_empty() else null, "errand": {"kind": "leshen", "target": null, "from": {"q": cell.x, "r": cell.y}}}
	world.next.wave += 1
	world.waves.append(wave)
	server.schedule(world, at, "wave_spawn", {"waveId": wave.id})
	for member in world.members:
		LocalInbox.tell(server, world, member.accountId, {"kind": "event", "tier": "push", "title": "The Leshen rises from the ashes at ({q}, {r})",
			"body": "The burnt forest wakes its lord. The wrath of nature marches on the villages with the beasts of the North. Slay his host for a great bounty.",
			"vars": {"q": cell.x, "r": cell.y}}, at)
	changed.append(["world"])


## leshenEnds: his host beaten, every member gets the great bounty, the
## one who felled him Svarog's Embers (solo: the player), and the North
## hates the more.
static func ends(server: LocalServer, world: Dictionary, wave: Dictionary, status: String, at: int, changed: Array) -> void:
	var errand: Variant = wave.get("errand")
	if not errand is Dictionary or errand.kind != "leshen" or status != "defeated":
		return
	var data := server.data
	var rules: Dictionary = data.events.leshen
	world.embers = int(world.embers) + int(rules.embers)
	LocalHordes.anger_front(server, world, "north", float(rules.hatred), at)
	var bounty := LocalEvents.bounty_at(data, world, at)
	var factor := float(data.events.leshen.bountyFactor)
	var great := LocalVillage.resources(func(k: String) -> int: return LocalWaves.js_round(float(bounty[k]) * factor))
	var owners := {}
	for v in world.villages:
		if v.ruin == null and v.ownerAccountId != null:
			owners[int(v.ownerAccountId)] = true
	for member in world.members:
		if owners.has(int(member.accountId)):
			server.reward(world, int(member.accountId), great, at, changed)
		LocalInbox.tell(server, world, member.accountId, {"kind": "event", "tier": "push", "title": "The Leshen is felled",
			"body": "The wrath of nature sinks back into the earth. Every village of the group gets {bounty} resources, and the North rages at his fall.", "vars": {"bounty": LocalBattle.total(great)}}, at)
