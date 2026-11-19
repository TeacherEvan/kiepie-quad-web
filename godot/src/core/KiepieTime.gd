extends RefCounted
class_name KiepieTime
## Single ISO-8601 codec shared by MatchState and TaloBackend.
## Format: "YYYY-MM-DD HH:MM:SSZ" (UTC, space-separated, trailing Z).
## A leading "T" separator is accepted and normalized.


## "2026-01-01 00:00:00Z" | "2026-01-01T00:00:00Z" | with or without Z -> unix seconds.
## Returns 0.0 on unparseable input.
static func parse_iso(value: String) -> float:
	var s := str(value).strip_edges()
	if s.is_empty() or s == "null":
		return 0.0
	s = s.replace("Z", "").replace("T", " ")
	var dict := Time.get_datetime_dict_from_datetime_string(s, false)
	if dict.is_empty():
		return 0.0
	return float(Time.get_unix_time_from_datetime_dict(dict))


## Format "YYYY-MM-DD HH:MM:SSZ" from unix seconds.
static func iso_from_unix(unix: float) -> String:
	var dict := Time.get_datetime_dict_from_unix_time(int(unix))
	return "%04d-%02d-%02d %02d:%02d:%02dZ" % [dict["year"], dict["month"],
			dict["day"], dict["hour"], dict["minute"], dict["second"]]


static func now_iso() -> String:
	return iso_from_unix(Time.get_unix_time_from_system())


static func iso_from_now(seconds: float) -> String:
	return iso_from_unix(Time.get_unix_time_from_system() + maxf(0.0, seconds))
