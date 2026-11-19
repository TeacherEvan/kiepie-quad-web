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


# --------------------------------------------------------------- hitstop ----

## Refcounted Engine.time_scale hitstop coordinator (P0-2). All slow-mo
## leases — kill cam (ArenaNet) and death hitstop (CombatController) — funnel
## through here so the engine time scale returns to 1.0 deterministically when
## the last beat ends, and never sticks below 1.0 after overlapping beats or
## scene unloads: reset_hitstop() bumps _gen so pending timers invalidated by
## the scene unload cannot clobber Engine.time_scale in the next scene.

static var _scales: Array = []
static var _active := 0
static var _gen := 0


static func trigger_hitstop(tree, scale: float, duration_s: float) -> void:
	# Untyped: callers pass SceneTree (ArenaNet/CombatController get_tree()) or
	# the root node (verify scripts); SceneTree scripts have no is_inside_tree().
	if tree == null or not tree.has_method("create_timer") or scale <= 0.0 or duration_s <= 0.0:
		return
	var my_gen := _gen
	_scales.append(scale)
	_active += 1
	tree.create_timer(duration_s, true, false, true).timeout.connect(func() -> void:
		if _gen != my_gen or _active <= 0:
			return
		_active -= 1
		if _active == 0:
			_scales.clear()
			Engine.time_scale = 1.0
		elif _scales.size() > 0:
			Engine.time_scale = minf(1.0, _scales.min())
	)
	if _active > 0 and _scales.size() > 0:
		Engine.time_scale = minf(1.0, _scales.min())


static func reset_hitstop() -> void:
	_gen += 1
	_scales.clear()
	_active = 0
	Engine.time_scale = 1.0
