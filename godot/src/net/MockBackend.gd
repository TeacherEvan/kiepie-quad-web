extends Node
class_name MockBackend
## Offline stand-in for the Supabase backend. Used automatically when no project
## URL is configured, so every headless gate runs without network access.

signal broadcast_received(event: String, payload: Variant)
signal postgres_change(data: Dictionary)
signal backend_error(message: String)

const DEFAULT_SETTINGS := {
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
var shot_count := 0
var kill_count := 0
var last_kill_reason := ""
var _used_tokens: Dictionary = {}
var _issued_tokens: Dictionary = {}
var _last_kill_at := -100.0
var _kill_times: Array = []


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
	shot_count = 0
	kill_count = 0
	last_kill_reason = ""
	_used_tokens = {}
	_issued_tokens = {}
	_last_kill_at = -100.0
	_kill_times = []


func call_rpc(name: String, args: Dictionary = {}) -> Dictionary:
	match name:
		"join_auto", "create_lobby", "join_by_code":
			var me := "mock-host"
			if not players.has(me):
				players[me] = {
					"user_id": me,
					"display_name": str(args.get("p_display_name", "RIDER")),
					"color": str(args.get("p_color", "#ff7a1a")),
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
			return {"ok": true, "pending": false}
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
		_:
			return {}
	return {}


func _mock_register_kill(args: Dictionary) -> Dictionary:
	var shooter := str(args.get("p_shooter", "mock-host"))
	var token := str(args.get("p_token", ""))
	if token == "" or not _issued_tokens.has(token):
		last_kill_reason = "invalid_token"
		return {"ok": false, "reason": last_kill_reason}
	if _used_tokens.has(token):
		last_kill_reason = "token_consumed"
		return {"ok": false, "reason": last_kill_reason}
	if Time.get_ticks_msec() / 1000.0 - float(_issued_tokens[token]) > 10.0:
		last_kill_reason = "token_expired"
		return {"ok": false, "reason": last_kill_reason}
	if shooter == str(args.get("p_target", "")):
		last_kill_reason = "self_kill"
		return {"ok": false, "reason": last_kill_reason}
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_kill_at < 1.0:
		last_kill_reason = "kill_cooldown"
		return {"ok": false, "reason": last_kill_reason}
	_kill_times = _kill_times.filter(func(t): return now - float(t) < 60.0)
	if _kill_times.size() >= 20:
		last_kill_reason = "rate_limited"
		return {"ok": false, "reason": last_kill_reason}
	_used_tokens[token] = true
	_last_kill_at = now
	_kill_times.append(now)
	scores[shooter] = int(scores.get(shooter, 0)) + 1
	kill_count += 1
	var target := str(args.get("p_target", "mock-target"))
	players[target] = {
		"user_id": target, "display_name": "TARGET", "color": "#40c8ff",
		"score": 0, "is_ready": true, "respawn_at": "future",
	}
	var shooter_row: Dictionary = players.get(shooter, {}).duplicate(true)
	shooter_row["user_id"] = shooter
	shooter_row["score"] = scores[shooter]
	players[shooter] = shooter_row
	postgres_change.emit({
		"schema": "public", "table": "lobby_players", "type": "UPDATE",
		"record": shooter_row,
	})
	var winner = null
	var target_score := int((lobby["settings"] as Dictionary).get("kill_target", 10))
	if scores[shooter] >= target_score:
		lobby["status"] = "finished"
		lobby["winner_id"] = shooter
		winner = shooter
	return {
		"ok": true, "score": scores[shooter], "winner_id": winner,
		"lobby_status": lobby["status"],
	}


func reset_cooldown_for_test() -> void:
	_last_kill_at = -100.0
	_kill_times.clear()


func broadcast(event: String, payload: Dictionary) -> void:
	# loopback so gates can observe their own fired events
	broadcast_received.emit(event, payload)


func simulate_remote_state(payload: Dictionary) -> void:
	broadcast_received.emit("state", payload)


func simulate_remote_shot(payload: Dictionary) -> void:
	broadcast_received.emit("shot", payload)
