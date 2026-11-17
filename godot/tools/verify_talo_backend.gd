extends SceneTree
## Offline contract tests for TaloBackend — no live Talo account is touched.
## Drives the facade directly with host state staged in memory; channel writes
## are inert because _channel is null and _channel_id <= 0.

var _failures := 0

func _check(cond: bool, msg: String) -> void:
	if not cond:
		push_error("FAIL: " + msg)
		_failures += 1

func _new_backend() -> Node:
	var script = load("res://src/net/TaloBackend.gd")
	var backend: Node = script.new()
	backend.is_ready = true
	backend.user_id = "1"
	backend._lobby = {
		"id": "1", "code": "ABC12", "name": "test", "host_id": "1",
		"settings": {"kill_target": 10, "match_seconds": 0},
		"status": "playing", "started_at": "", "winner_id": "",
	}
	backend._roster = {
		"1": {"user_id": "1", "display_name": "host", "score": 0},
		"2": {"user_id": "2", "display_name": "guest", "score": 0},
	}
	backend._channel = null
	backend._channel_id = -1
	return backend

func _initialize() -> void:
	var backend := _new_backend()
	get_root().add_child(backend)

	# Host: first kill scores, reused token is rejected by the backend contract.
	var first: Dictionary = await backend.call_rpc("register_kill",
			{"p_target": "2", "p_token": "tok-1", "p_killer": "1"})
	_check(bool(first.get("ok", false)) and int(first.get("score", 0)) == 1,
			"host scores a fresh kill")
	var reused: Dictionary = await backend.call_rpc("register_kill",
			{"p_target": "2", "p_token": "tok-1", "p_killer": "1"})
	_check(not bool(reused.get("ok", true)) and str(reused.get("reason", "")) == "token_consumed",
			"host rejects a reused token with token_consumed")

	# Host: self-kill and non-playing lobby are refused.
	var self_kill: Dictionary = await backend.call_rpc("register_kill",
			{"p_target": "1", "p_token": "tok-2", "p_killer": "1"})
	_check(not bool(self_kill.get("ok", true)) and str(self_kill.get("reason", "")) == "self_kill",
			"host rejects self-kill")
	backend._lobby["status"] = "waiting"
	var not_playing: Dictionary = await backend.call_rpc("register_kill",
			{"p_target": "2", "p_token": "tok-3", "p_killer": "1"})
	_check(not bool(not_playing.get("ok", true)), "host rejects kill outside a playing match")
	backend._lobby["status"] = "playing"

	# Host: a spoofed kill_request naming another shooter is ignored.
	var score_before := int((backend._roster["2"] as Dictionary).get("score", 0))
	var spoof := JSON.stringify({"k": "kill_request",
			"p": {"killer": "2", "target": "1", "token": "tok-spoof"}})
	await backend._on_socket_message("v1.channels.message",
			{"playerAlias": {"id": 999}, "message": spoof})
	_check(int((backend._roster["2"] as Dictionary).get("score", 0)) == score_before,
			"host ignores kill_request from a mismatched alias")

	# Host: a genuine alias-authored kill_request is applied.
	var genuine := JSON.stringify({"k": "kill_request",
			"p": {"killer": "2", "target": "1", "token": "tok-genuine"}})
	await backend._on_socket_message("v1.channels.message",
			{"playerAlias": {"id": 2}, "message": genuine})
	_check(int((backend._roster["2"] as Dictionary).get("score", 0)) == score_before + 1,
			"host applies kill_request from the matching alias")

	# Guest: scores are never optimistically applied; the host state is authoritative.
	backend._lobby["host_id"] = "2"
	var guest_score_before := int((backend._roster["1"] as Dictionary).get("score", 0))
	var guest: Dictionary = await backend.call_rpc("register_kill",
			{"p_target": "2", "p_token": "tok-guest", "p_killer": "1"})
	_check(bool(guest.get("ok", false)) and bool(guest.get("pending", false)),
			"guest kill is marked pending_host")
	_check(int((backend._roster["1"] as Dictionary).get("score", 0)) == guest_score_before,
			"guest backend does not mutate its own score")

	print("talo backend contract: %d checks, %d failure(s)" % [8, _failures])
	quit(1 if _failures > 0 else 0)
