class_name TimeUtil
extends RefCounted
## Timestamps from the server are ISO 8601 UTC strings with milliseconds,
## e.g. "2026-10-18T11:43:21.456Z". Internally we use float unix seconds.

## How fast the game's clock runs against the player's (Game.set_time_rate):
## a solo world played at another speed than it was started with. Durations
## on the game's clock are shown in the player's time.
static var rate := 1.0


static func parse_iso(text: String) -> float:
	var date_time := text.trim_suffix("Z").split("T")
	var date := date_time[0].split("-")
	var time := date_time[1].split(":")
	var seconds := float(time[2])
	var whole := {
		"year": int(date[0]), "month": int(date[1]), "day": int(date[2]),
		"hour": int(time[0]), "minute": int(time[1]), "second": int(seconds),
	}
	return Time.get_unix_time_from_datetime_dict(whole) + (seconds - floorf(seconds))


## "45s", "12m 05s", "3h 20m", "2d 4h": `seconds` on the game's clock (a
## countdown, or game hours over the world's speed), told in the player's time.
static func format_duration(seconds: float) -> String:
	return format_real(seconds / rate)


## The same for seconds of the player's own time.
@warning_ignore("integer_division")
static func format_real(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	if s < 60:
		return "%ds" % s
	if s < 3600:
		return "%dm %02ds" % [s / 60, s % 60]
	if s < 86400:
		return "%dh %02dm" % [s / 3600, (s % 3600) / 60]
	return "%dd %dh" % [s / 86400, (s % 86400) / 3600]


## A rate per hour on the game's clock (world speed applied), per hour of the
## player's time.
static func per_real_hour(per_hour: float) -> float:
	return per_hour * rate
