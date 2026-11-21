extends Node
class_name MockBackend
## Offline stand-in for the Supabase backend. Used automatically when no project
## URL is configured, so every headless gate runs without network access.

signal broadcast_received(event: String, payload: Variant)
signal postgres_change(data: Dictionary)
signal backend_error(message: String)
signal host_lost()

const DEFAULT_SETTINGS := {
	"game_mode": "battle_royale",
	"lap_target": 3,
	"kill_target": 10,
	"max_players": 8,
	"respawn_delay": 2.5,
	"match_seconds": 0,
	"damage": 30,
	"pickups": true,
	"friendly_fire": false,
}

var lobby: Dictionary = {}
var players: Dictionary = {}
var scores: Dictionary = {}
var kills: Dictionary = {}
var laps: Dictionary = {}
var shot_count := 0
var kill_count := 0
var last_kill_reason := ""
var _used_tokens: Dictionary = {}
var _issued_tokens: Dictionary = {}
var _last_kill_at := -100.0
var _kill_last_base: Dictionary = {}
var _kill_times: Array = []
var _lap_timestamps: Dictionary = {}
const MIN_LAP_SECONDS := 12.0


func _ready() -> void:
	_reset()


func _reset() -> void:
	lobby = {
		"id": "mock-lobby-0001",
		"code": "MOCK01",
		"name": "Offline Lobby",
		"host_id": "mock-host",
		"settings": DEFAULT_SETTINGS.duplicate(true),
		"status": "waiting",
		"winner_id": null,
	}
	players = {}
	scores = {}
	kills = {}
	laps = {}
	shot_count = 0
	kill_count = 0
	last_kill_reason = ""
	_used_tokens = {}
	_issued_tokens = {}
	_last_kill_at = -100.0
	_kill_last_base = {}
	_kill_times = []
	_lap_timestamps = {}


func call_rpc(name: String, args: Dictionary = {}) -> Dictionary:
	match name:
		"join_auto", "create_lobby", "join_by_code":
			if name == "create_lobby" and args.has("p_settings") and args["p_settings"] is Dictionary:
				var s_in: Dictionary = (lobby["settings"] as Dictionary).duplicate(true)
				for k in (args["p_settings"] as Dictionary).keys():
					s_in[k] = (args["p_settings"] as Dictionary)[k]
				lobby["settings"] = s_in
			elif name == "join_auto" and args.has("p_game_mode"):
				(lobby["settings"] as Dictionary)["game_mode"] = str(args["p_game_mode"])
			var me := "mock-host"
			if not players.has(me):
				players[me] = {
					"user_id": me,
					"display_name": str(args.get("p_display_name", "RIDER")),
					"color": str(args.get("p_color", "#ff7a1a")),
					"vehicle": VehicleRegistry.sanitize_preference(str(args.get("p_vehicle", ""))),
					"score": 0,
					"is_ready": false,
					"respawn_at": null,
				}
				scores[me] = 0
			return {"lobby": lobby.duplicate(true), "player": players[me].duplicate(true)}
		"set_settings":
			var s: Dictionary = (lobby["settings"] as Dictionary).duplicate(true)
			for k in (args.get("p_settings", {}) as Dictionary).keys():
				s[k] = (args["p_settings"] as Dictionary)[k]
			lobby["settings"] = s
			return lobby.duplicate(true)
		"set_ready":
			var me := "mock-host"
			if players.has(me):
				(players[me] as Dictionary)["is_ready"] = bool(args.get("p_ready", false))
			return {"ok": true, "pending": false, "players": players.duplicate(true)}
		"leave_lobby", "heartbeat":
			return {}
		"start_match":
			lobby["status"] = "playing"
			for k in scores.keys():
				scores[k] = 0
			return lobby.duplicate(true)
		"issue_shot":
			shot_count += 1
			var token := "mock-shot-%d" % shot_count
			_issued_tokens[token] = Time.get_ticks_msec() / 1000.0
			return {"token": token, "at": "2026-01-01T00:00:00Z"}
		"register_kill":
			return _mock_register_kill(args)
		"register_lap":
			return _mock_register_lap(args)
		_:
			return {}
	return {}


func _mock_register_kill(args: Dictionary) -> Dictionary:
	var shooter := str(args.get("p_killer", args.get("p_shooter", "mock-host")))
	var token := str(args.get("p_token", ""))
	var colon := token.find(":")
	var base_tok := token.substr(0, colon) if colon > 0 else token
	var is_sub_tok := colon > 0
	if token == "" or not _issued_tokens.has(base_tok):
		last_kill_reason = "invalid_token"
		return {"ok": false, "reason": last_kill_reason}
	if _used_tokens.has(token):
		last_kill_reason = "token_consumed"
		return {"ok": false, "reason": last_kill_reason}
	if Time.get_ticks_msec() / 1000.0 - float(_issued_tokens[base_tok]) > 10.0:
		last_kill_reason = "token_expired"
		return {"ok": false, "reason": last_kill_reason}
	if shooter == str(args.get("p_target", "")):
		last_kill_reason = "self_kill"
		return {"ok": false, "reason": last_kill_reason}
	var now := Time.get_ticks_msec() / 1000.0
	var burst_ok := false
	if is_sub_tok and _kill_last_base.has(shooter):
		var prev_b: Dictionary = _kill_last_base[shooter] as Dictionary
		if str(prev_b.get("base", "")) == base_tok and (now - float(prev_b.get("at", -10.0))) < 0.6 and int(prev_b.get("count", 0)) < 4:
			burst_ok = true
	if now - _last_kill_at < 1.0 and not burst_ok:
		last_kill_reason = "kill_cooldown"
		return {"ok": false, "reason": last_kill_reason}
	_kill_times = _kill_times.filter(func(t): return now - float(t) < 60.0)
	if _kill_times.size() >= 20:
		last_kill_reason = "rate_limited"
		return {"ok": false, "reason": last_kill_reason}
	_used_tokens[token] = true
	_last_kill_at = now
	if burst_ok:
		var pb: Dictionary = _kill_last_base[shooter] as Dictionary
		pb["count"] = int(pb.get("count", 1)) + 1
		_kill_last_base[shooter] = pb
	else:
		_kill_last_base[shooter] = {"base": base_tok, "count": 1, "at": now}
	_kill_times.append(now)
	var s_dict := lobby.get("settings", {}) as Dictionary
	var gmode := str(s_dict.get("game_mode", "battle_royale"))
	kills[shooter] = int(kills.get(shooter, 0)) + 1
	if gmode != "death_race":
		scores[shooter] = int(kills[shooter])
	else:
		scores[shooter] = int(laps.get(shooter, 0))
	kill_count += 1
	var target := str(args.get("p_target", "mock-target"))
	# MatchState.is_respawning() reads respawn_at as a future ISO deadline.
	var deadline := Time.get_datetime_dict_from_unix_time(
			int(Time.get_unix_time_from_system()) + 3)
	players[target] = {
		"user_id": target, "display_name": "TARGET", "color": "#40c8ff",
		"score": 0, "is_ready": true,
		"respawn_at": "%04d-%02d-%02d %02d:%02d:%02dZ" % [deadline["year"],
				deadline["month"], deadline["day"], deadline["hour"],
				deadline["minute"], deadline["second"]],
	}
	var shooter_row: Dictionary = players.get(shooter, {}).duplicate(true)
	shooter_row["user_id"] = shooter
	shooter_row["kills"] = int(kills[shooter])
	shooter_row["score"] = int(scores[shooter])
	players[shooter] = shooter_row
	postgres_change.emit({
		"schema": "public", "table": "lobby_players", "type": "UPDATE",
		"record": shooter_row,
	})
	var winner = null
	var target_score := int(s_dict.get("kill_target", 10))
	if gmode != "death_race" and scores[shooter] >= target_score:
		lobby["status"] = "finished"
		lobby["winner_id"] = shooter
		winner = shooter
	return {
		"ok": true, "score": scores[shooter], "kills": kills[shooter], "winner_id": winner,
		"lobby_status": lobby["status"],
	}


func _mock_register_lap(args: Dictionary) -> Dictionary:
	var racer := str(args.get("p_racer", "mock-host"))
	var token := str(args.get("p_token", ""))
	var s_dict := lobby.get("settings", {}) as Dictionary
	if str(s_dict.get("game_mode", "battle_royale")) != "death_race":
		last_kill_reason = "wrong_mode"
		return {"ok": false, "reason": last_kill_reason}
	if str(lobby.get("status", "")) != "playing":
		last_kill_reason = "lobby_not_playing"
		return {"ok": false, "reason": last_kill_reason}
	if token == "" or not _issued_tokens.has(token):
		last_kill_reason = "invalid_token"
		return {"ok": false, "reason": last_kill_reason}
	if _used_tokens.has(token):
		last_kill_reason = "token_consumed"
		return {"ok": false, "reason": last_kill_reason}
	var now := Time.get_ticks_msec() / 1000.0
	var last_lap := float(_lap_timestamps.get(racer, -MIN_LAP_SECONDS))
	if now - last_lap < MIN_LAP_SECONDS:
		last_kill_reason = "rate_limited"
		return {"ok": false, "reason": last_kill_reason}
	_lap_timestamps[racer] = now
	_used_tokens[token] = true
	laps[racer] = int(laps.get(racer, 0)) + 1
	scores[racer] = int(laps[racer])
	var racer_row: Dictionary = players.get(racer, {}).duplicate(true)
	racer_row["user_id"] = racer
	racer_row["laps"] = int(laps[racer])
	racer_row["score"] = int(laps[racer])
	players[racer] = racer_row
	postgres_change.emit({
		"schema": "public", "table": "lobby_players", "type": "UPDATE",
		"record": racer_row,
	})
	var winner = null
	var target_laps := maxi(1, int(s_dict.get("lap_target", 3)))
	if laps[racer] >= target_laps:
		lobby["status"] = "finished"
		lobby["winner_id"] = racer
		winner = racer
	return {
		"ok": true, "score": laps[racer], "laps": laps[racer], "winner_id": winner,
		"lobby_status": lobby["status"],
	}


func reset_cooldown_for_test() -> void:
	_last_kill_at = -100.0
	_kill_times.clear()
	_lap_timestamps.clear()


func broadcast(event: String, payload: Dictionary) -> void:
	# loopback so gates can observe their own fired events
	broadcast_received.emit(event, payload)


func simulate_remote_state(payload: Dictionary) -> void:
	broadcast_received.emit("state", payload)


func simulate_remote_shot(payload: Dictionary) -> void:
	broadcast_received.emit("shot", payload)


func simulate_host_loss() -> void:
	## Test hook: the host vanished mid-match (gates, not game code).
	host_lost.emit()
