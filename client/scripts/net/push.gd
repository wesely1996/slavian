extends Node
## Push notifications on Android: asks for permission, gets the Firebase
## Cloud Messaging token and registers it with the server so it can notify
## this phone. The Firebase plugin only exists in Android exports (see
## ops/ci/setup-firebase-android.sh); everywhere else this does nothing.

signal permission_changed

const CORE := "GodotxFirebaseCore"
const MESSAGING := "GodotxFirebaseMessaging"

## "granted", "denied" or "" (not answered yet, or no pushes on this device).
var permission := ""

var _messaging: Object = null
var _token := ""
var _registered_token := ""
var _registering := false


func _ready() -> void:
	if OS.get_name() != "Android" or not Engine.has_singleton(CORE) or not Engine.has_singleton(MESSAGING):
		return
	var core := Engine.get_singleton(CORE)
	_messaging = Engine.get_singleton(MESSAGING)
	core.core_initialized.connect(_on_core_initialized)
	_messaging.messaging_permission_granted.connect(_on_permission_granted)
	_messaging.messaging_permission_denied.connect(_on_permission_denied)
	_messaging.messaging_token_received.connect(_on_token_received)
	_messaging.messaging_error.connect(_on_error)
	core.initialize()


## Whether this device can get pushes at all (the Android app).
func available() -> bool:
	return _messaging != null


## Asks for permission again (the settings' "Allow notifications").
func ask() -> void:
	if _messaging != null:
		_messaging.request_permission()


## Switches a topic on or off, here and (once signed in) on the server.
func set_topic(topic: String, on: bool) -> void:
	Session.push_off.erase(topic)
	if not on:
		Session.push_off.append(topic)
	Session.push_sync = true
	Session.save()
	sync_topics()


## Tells the server which topics are off, if it hasn't heard yet.
func sync_topics() -> void:
	if not Session.push_sync or not Session.is_logged_in():
		return
	var sent := Session.push_off.duplicate()
	var response := await Api.patch_json("/v1/me/notifications", {"pushOff": sent})
	# (A switch flipped meanwhile is still to be sent.)
	if response.ok and Session.push_off == sent:
		Session.push_sync = false
		Session.save()


## Sends the token to the server once there is both a token and a login.
## Safe to call any time; it is a no-op until both exist.
func register() -> void:
	sync_topics()
	if _registering or _token == "" or _token == _registered_token or not Session.is_logged_in():
		return
	_registering = true
	var token := _token
	var response := await Api.post_json("/v1/me/devices", {"token": token, "platform": "android"})
	_registering = false
	if response.ok:
		_registered_token = token
	else:
		push_warning("Push: could not register the device token: %s" % response.error)


func _on_core_initialized(success: bool) -> void:
	if not success:
		push_warning("Push: Firebase failed to initialise")
		return
	_messaging.initialize()
	_messaging.request_permission()


func _on_permission_granted() -> void:
	_answered(true)
	_messaging.get_token()


func _on_permission_denied() -> void:
	print("Push: notification permission denied")
	_answered(false)


## The first answer sets every topic: all on if allowed, all off if not.
func _answered(allowed: bool) -> void:
	permission = "granted" if allowed else "denied"
	if not Session.push_decided:
		Session.push_decided = true
		Session.push_off = [] if allowed else InboxText.PUSH_TOPICS.duplicate()
		Session.push_sync = true
		Session.save()
		sync_topics()
	permission_changed.emit()


func _on_token_received(token: String) -> void:
	_token = token
	register()


func _on_error(message: String) -> void:
	push_warning("Push: %s" % message)
