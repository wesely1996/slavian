class_name Share
extends RefCounted
## Sharing text with other apps: on Android, the system's share sheet;
## elsewhere (or if that can't be reached) the text goes to the clipboard.


## Shares `body`; returns whether the share sheet opened (false: it was
## copied instead).
static func text(body: String, title: String) -> bool:
	if _android_share(body, title):
		return true
	DisplayServer.clipboard_set(body)
	return false


## Android's ACTION_SEND chooser, built from static calls only (Intent.parseUri,
## Intent.createChooser) through the AndroidRuntime plugin (Godot 4.4+).
static func _android_share(body: String, title: String) -> bool:
	if OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"):
		return false
	var activity: Variant = Engine.get_singleton("AndroidRuntime").getActivity()
	var intent_class: Variant = JavaClassWrapper.wrap("android.content.Intent")
	if activity == null or intent_class == null:
		return false
	var uri := "intent:#Intent;action=android.intent.action.SEND;type=text/plain;S.android.intent.extra.TEXT=%s;end" % body.uri_encode()
	var send: Variant = intent_class.parseUri(uri, 0)
	if send == null:
		return false
	var chooser: Variant = intent_class.createChooser(send, title)
	if chooser == null:
		return false
	activity.startActivity(chooser)
	return true
