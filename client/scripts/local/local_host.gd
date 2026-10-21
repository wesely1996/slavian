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


## Answers a request as the server would: {status, data}.
func respond(method: int, path: String, body: Variant) -> Dictionary:
	var now := LocalTime.now()
	var parts := path.split("?")[0].split("/", false)
	if method == HTTPClient.METHOD_GET and path == "/v1/data":
		return {"status": 200, "data": server.data}
	if parts.size() >= 3 and parts[1] == "worlds" and int(parts[2]) == world_id:
		var world: Dictionary = server.worlds.get(world_id, {})
		if world.is_empty():
			return _error(404, "No such solo world")
		if method == HTTPClient.METHOD_GET and parts.size() == 3:
			return {"status": 200, "data": server.world_view(world, now)}
	return _error(501, "Not in single player yet")


static func _error(status: int, message: String) -> Dictionary:
	return {"status": status, "data": {"error": "local", "message": message}}
