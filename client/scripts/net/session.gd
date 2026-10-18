extends Node
## The server address and login token, persisted on the device.

const PATH := "user://session.cfg"
const DEFAULT_SERVER_URL := "http://127.0.0.1:8080"

var server_url := DEFAULT_SERVER_URL
var token := ""
var account: Dictionary = {}


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		server_url = config.get_value("session", "server_url", DEFAULT_SERVER_URL)
		token = config.get_value("session", "token", "")


func save() -> void:
	var config := ConfigFile.new()
	config.set_value("session", "server_url", server_url)
	config.set_value("session", "token", token)
	config.save(PATH)


func is_logged_in() -> bool:
	return token != ""


func log_out() -> void:
	token = ""
	account = {}
	save()


func set_server_url(url: String) -> void:
	server_url = url.strip_edges().trim_suffix("/")
	if not server_url.contains("://"):
		server_url = "http://" + server_url


func live_url() -> String:
	return server_url.replace("https://", "wss://").replace("http://", "ws://") + "/v1/live"
