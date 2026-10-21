class_name LocalTime
extends RefCounted
## Times in the local engine are whole milliseconds since 1970 (UTC), like
## the server's Date; this writes and reads them as JavaScript's
## toISOString does ("2026-06-01T08:00:00.000Z").

const MS_PER_HOUR := 3600000


static func iso(ms: int) -> String:
	var seconds := floori(ms / 1000.0)
	var millis := ms - seconds * 1000
	var d := Time.get_datetime_dict_from_unix_time(seconds)
	return "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ" % [d.year, d.month, d.day, d.hour, d.minute, d.second, millis]


static func parse(text: String) -> int:
	var seconds := Time.get_unix_time_from_datetime_string(text.substr(0, 19))
	var millis := 0
	if text.length() >= 23 and text[19] == ".":
		millis = int(text.substr(20, 3))
	return int(seconds) * 1000 + millis


## The current time, as the device's clock gives it.
static func now() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


## JavaScript's `new Date(ms)` drops a fraction of a millisecond (towards 0).
static func ms(value: float) -> int:
	return int(value)
