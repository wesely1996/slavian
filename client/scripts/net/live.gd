extends Node
## Live updates for the current world over WebSocket. Reconnects with
## backoff; after every (re)connect listeners should refetch the world,
## since updates may have been missed while disconnected.

signal connection_changed(connected: bool)
signal village_updated(village: Dictionary)
signal world_updated(world: Dictionary)
signal waves_updated(world_id: int, waves: Array)
signal scouting_updated(world_id: int, missions: Array)
signal battles_updated(world_id: int, battles: Array)
signal raids_updated(world_id: int, raids: Array)
signal caravans_updated(world_id: int, caravans: Array, vault: Dictionary)
signal expeditions_updated(world_id: int, expeditions: Array)
signal research_updated(world_id: int, research: Array)
signal heroes_updated(world_id: int, heroes: Array)
signal orders_updated(world_id: int, orders: Array)
signal inbox_updated(world_id: int, notifications: Array, unread: int)
signal armies_updated(world_id: int, armies: Array)
signal forts_updated(world_id: int, forts: Array)

const RETRY_MIN_SEC := 1.0
const RETRY_MAX_SEC := 30.0

var connected := false

var _socket: WebSocketPeer
var _subscribe_sent := false
var _world_id := 0
var _retry_in := 0.0
var _backoff := RETRY_MIN_SEC


func watch(world_id: int) -> void:
	stop()
	_world_id = world_id
	_open()


func stop() -> void:
	_world_id = 0
	if _socket:
		_socket.close()
		_socket = null
	_set_connected(false)


func _open() -> void:
	_socket = WebSocketPeer.new()
	_subscribe_sent = false
	_socket.handshake_headers = PackedStringArray(["Authorization: Bearer " + Session.token])
	if _socket.connect_to_url(Session.live_url()) != OK:
		_socket = null
		_schedule_retry()


func _process(delta: float) -> void:
	if _world_id == 0:
		return
	if _socket == null:
		_retry_in -= delta
		if _retry_in <= 0.0:
			_open()
		return

	_socket.poll()
	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _subscribe_sent:
				_subscribe_sent = true
				_backoff = RETRY_MIN_SEC
				_socket.send_text(JSON.stringify({"type": "subscribe", "worldId": _world_id}))
			while _socket.get_available_packet_count() > 0:
				_handle(_socket.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			_socket = null
			_set_connected(false)
			_schedule_retry()


func _handle(text: String) -> void:
	var message: Variant = JSON.parse_string(text)
	if not message is Dictionary:
		return
	if message.has("serverTime"):
		Game.note_server_time(message.serverTime)
	match message.get("type", ""):
		"subscribed":
			_set_connected(true)
		"village":
			village_updated.emit(message.village)
		"world":
			world_updated.emit(message.world)
		"waves":
			waves_updated.emit(int(message.worldId), message.waves)
		"scouting":
			scouting_updated.emit(int(message.worldId), message.missions)
		"battles":
			battles_updated.emit(int(message.worldId), message.battles)
		"raids":
			raids_updated.emit(int(message.worldId), message.raids)
		"armies":
			armies_updated.emit(int(message.worldId), message.armies)
			forts_updated.emit(int(message.worldId), message.get("forts", []))
		"notifications":
			inbox_updated.emit(int(message.worldId), message.notifications, int(message.unread))
		"orders":
			orders_updated.emit(int(message.worldId), message.orders)
		"heroes":
			heroes_updated.emit(int(message.worldId), message.heroes)
		"research":
			research_updated.emit(int(message.worldId), message.research)
		"expeditions":
			expeditions_updated.emit(int(message.worldId), message.expeditions)
		"caravans":
			caravans_updated.emit(int(message.worldId), message.caravans, message.vault)
		"error":
			push_warning("Live: %s" % message.get("message", ""))


func _schedule_retry() -> void:
	_retry_in = _backoff
	_backoff = minf(_backoff * 2.0, RETRY_MAX_SEC)


func _set_connected(value: bool) -> void:
	if connected != value:
		connected = value
		connection_changed.emit(value)
