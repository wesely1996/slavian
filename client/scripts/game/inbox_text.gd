class_name InboxText
extends RefCounted
## Words for the inbox and notification settings.


## "5m ago", "3h ago", "2d ago".
static func ago(created_unix: float, now: float) -> String:
	var seconds := maxf(0.0, now - created_unix)
	if seconds < 60.0:
		return "just now"
	if seconds < 3600.0:
		return "%dm ago" % floori(seconds / 60.0)
	if seconds < 86400.0:
		return "%dh ago" % floori(seconds / 3600.0)
	return "%dd ago" % floori(seconds / 86400.0)


## Minutes after midnight as "22:00".
static func clock(minutes: int) -> String:
	var m := posmod(minutes, 1440)
	return "%02d:%02d" % [m / 60, m % 60]
