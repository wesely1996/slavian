extends Node2D
## M0 map spike: generates a placeholder world and lets you pan, zoom and
## tap hexes. Player count and seed can be changed to preview map variants.

const MAX_PLAYERS := 6

@export var map_seed := 1337
@export var player_count := 4

@onready var hex_map: HexMap = $HexMap
@onready var camera: MapCamera = $MapCamera
@onready var players_button: Button = %PlayersButton
@onready var new_map_button: Button = %NewMapButton
@onready var info_label: Label = %InfoLabel
@onready var fps_label: Label = %FpsLabel


func _ready() -> void:
	camera.tapped.connect(_on_map_tapped)
	players_button.pressed.connect(_on_players_pressed)
	new_map_button.pressed.connect(_on_new_map_pressed)
	_generate()


func _process(_delta: float) -> void:
	fps_label.text = "%d FPS" % Engine.get_frames_per_second()


func _generate() -> void:
	hex_map.set_map(MapGenerator.generate(map_seed, player_count))
	camera.bounds = hex_map.get_bounds()
	camera.position = Vector2.ZERO
	players_button.text = "Players: %d" % player_count
	info_label.text = "Seed %d. Tap a hex." % map_seed


func _on_map_tapped(world_position: Vector2) -> void:
	var cell := hex_map.local_to_hex(hex_map.to_local(world_position))
	if not hex_map.has_hex(cell):
		return
	hex_map.select(cell)
	var map := hex_map.map
	var lines := PackedStringArray([
		"%s  (q %d, r %d)" % [Terrain.display_name(map.terrain[cell]), cell.x, cell.y],
		"Distance to Holy City: %d" % HexMath.distance(cell, Vector2i.ZERO),
		"Front: %s" % MapGenerator.Front.keys()[MapGenerator.front_of(cell)].capitalize(),
	])
	if cell in map.start_sites:
		lines.append("Starting village site")
	info_label.text = "\n".join(lines)


func _on_players_pressed() -> void:
	player_count = player_count % MAX_PLAYERS + 1
	_generate()


func _on_new_map_pressed() -> void:
	map_seed = randi()
	_generate()
