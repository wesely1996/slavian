extends Node
## The local engine in the app (autoload Local; docs/local-engine.md). While a
## solo world is open, Api hands it every request and Live gets its news
## from it, so the screens work the same as with the server.

## The player in every solo world.
const ACCOUNT_ID := 1

var server: LocalServer
## The solo world being played (0: none, the real server answers).
var world_id := 0


func _ready() -> void:
	server = LocalServer.new()


func is_active() -> bool:
	return world_id < 0


## Solo worlds on this device, newest first: [{id, name, startedAt, status}].
func list_worlds() -> Array:
	var out: Array = []
	for world in server.worlds.values():
		out.append({"id": world.id, "name": world.name, "status": world.status, "startedAt": LocalTime.iso(world.startedAt), "difficulty": world.difficulty})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.startedAt > b.startedAt)
	return out


## Starts a solo world and returns its view.
func start(params: Dictionary) -> Dictionary:
	var world := server.start_world(params, ACCOUNT_ID, LocalTime.now())
	return server.world_view(world, LocalTime.now())


## Answers a request as the server would: {status, data}, and tells the
## screens what changed, as the server's live messages would.
func respond(method: int, path: String, body: Variant) -> Dictionary:
	if method == HTTPClient.METHOD_GET and path == "/v1/data":
		return {"status": 200, "data": server.data}
	var verb: String = {HTTPClient.METHOD_GET: "GET", HTTPClient.METHOD_POST: "POST", HTTPClient.METHOD_PUT: "PUT",
		HTTPClient.METHOD_PATCH: "PATCH", HTTPClient.METHOD_DELETE: "DELETE"}.get(method, "GET")
	var answer := server.handle(world_id, verb, path, body, LocalTime.now())
	_announce.call_deferred(answer.get("changed", []))
	return answer


var _since_drain := 0.0


## Time passes in the open solo world: what falls due happens.
func _process(delta: float) -> void:
	if not is_active():
		return
	_since_drain += delta
	if _since_drain < 1.0:
		return
	_since_drain = 0.0
	var world: Dictionary = server.worlds.get(world_id, {})
	if world.is_empty():
		return
	var changed: Array = []
	if server.drain(world, LocalTime.now(), changed) > 0:
		server.save(world)
		_announce(changed)


## Sends the screens the news, once per village and once for the world.
func _announce(changed: Array) -> void:
	var world: Dictionary = server.worlds.get(world_id, {})
	if world.is_empty():
		return
	var now := LocalTime.now()
	Game.note_server_time(LocalTime.iso(now))
	var seen := {}
	for item in changed:
		var key := str(item)
		if seen.has(key):
			continue
		seen[key] = true
		if item[0] == "world":
			Live.world_updated.emit(server.world_view(world, now))
		elif item[0] == "village":
			var village := server._village(world, int(item[1]))
			if not village.is_empty():
				Live.village_updated.emit(server.village_view(world, village))
