extends Node
## Sound effects and music (PLAN.md M5 step 26). Two buses, "Music" and
## "Effects", each with its own volume kept on the device. Music crossfades
## from one track to the next; every button taps. The sounds are all free to
## use and listed in client/audio/CREDITS.md and the menu's Help.

const MUSIC_DIR := "res://audio/music/"
const EFFECTS_DIR := "res://audio/sfx/"
## Tracks that play once (the end of a run); the rest loop.
const ONCE := ["won", "lost"]
## Effects with several takes, one picked at random each time.
const TAKES := {"clash": 5}
const FADE_SEC := 1.5
## Below this a bus is muted outright.
const SILENT := 0.01

var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _track := ""
var _effects: Array[AudioStreamPlayer] = []
var _next_effect := 0
var _cache: Dictionary = {}
var _fade: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in ["Music", "Effects"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus)
			AudioServer.set_bus_send(index, "Master")
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.bus = "Music"
		player.volume_db = linear_to_db(SILENT)
		add_child(player)
		_players.append(player)
	# A few voices so quick taps and battle rounds don't cut each other off.
	for i in 6:
		var player := AudioStreamPlayer.new()
		player.bus = "Effects"
		add_child(player)
		_effects.append(player)
	set_volume("Music", Session.music_volume)
	set_volume("Effects", Session.effects_volume)
	get_tree().node_added.connect(_on_node_added)


## Sets a bus's volume, 0 to 1.
func set_volume(bus: String, volume: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, SILENT)))
	AudioServer.set_bus_mute(index, volume < SILENT)


## Plays an effect: "tap", "build", "train", "clash", "horn", "done",
## "coins" or "error".
func effect(id: String) -> void:
	var file := id if not TAKES.has(id) else "%s_%d" % [id, randi() % int(TAKES[id])]
	var stream := _load(EFFECTS_DIR + file + ".ogg")
	if stream == null:
		return
	var player := _effects[_next_effect]
	_next_effect = (_next_effect + 1) % _effects.size()
	player.stream = stream
	player.play()


## Crossfades to a track: "map", "village", "threat", "battle", "won" or
## "lost". The same track keeps playing; "" fades the music out.
func music(id: String) -> void:
	if id == _track:
		return
	_track = id
	if _fade != null:
		_fade.kill()
	_fade = create_tween().set_parallel(true)
	var old := _players[_active]
	_fade.tween_property(old, "volume_db", linear_to_db(SILENT), FADE_SEC)
	var stream := _load(MUSIC_DIR + id + ".ogg") as AudioStreamOggVorbis if id != "" else null
	if stream != null:
		stream.loop = id not in ONCE
		_active = 1 - _active
		var player := _players[_active]
		player.stream = stream
		player.volume_db = linear_to_db(SILENT)
		player.play()
		_fade.tween_property(player, "volume_db", 0.0, FADE_SEC)
	_fade.chain().tween_callback(old.stop)


func track() -> String:
	return _track


func _load(path: String) -> AudioStream:
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


## Every button taps when pressed.
func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		node.pressed.connect(effect.bind("tap"))
