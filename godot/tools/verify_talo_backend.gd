extends SceneTree
## Offline contract tests for TaloBackend — no live Talo account is touched.
## Drives the facade directly with host state staged in memory; channel writes
## are inert because _channel is null and _channel_id <= 0.

var _failures := 0

class FakeOwner extends RefCounted:
	var id: int
	func _init(owner_id: int) -> void:
		id = owner_id


class FakeChannel extends RefCounted:
	var member_count: int
	var owner_alias: FakeOwner
	var updated_at: String
	var _props: Dictionary
	func _init(members: int, owner_id: int, updated: String, props: Dictionary) -> void:
		member_count = members
		owner_alias = FakeOwner.new(owner_id)
		updated_at = updated
		_props = props
	func get_prop(key: String, fallback: String = "") -> String:
		return str(_props.get(key, fallback))


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
	await process_frame
	await process_frame
	# autoload _ready runs after the tool's _initialize in --script mode;
	# the mock/live decision is only meaningful once it has run
	var sb: Node = get_root().get_node_or_null("Supabase")
	if sb == null or not bool(sb.get("use_mock")):
		printerr("LIVE BACKEND — refusing to run gate (KIEPIE_MOCK_BACKEND=1 not effective)")
		quit(2)
		return
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

	# Host: kill claims inside the per-killer cooldown are rate-limited.
	var rapid: Dictionary = await backend.call_rpc("register_kill",
			{"p_target": "2", "p_token": "tok-5", "p_killer": "1"})
	_check(not bool(rapid.get("ok", true)) and str(rapid.get("reason", "")) == "rate_limited",
			"host rate-limits a second kill within 1 s")

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

	# Host: a genuine alias-authored kill_request is applied (after host's
	# 1-second per-killer cooldown elapses).
	var wait_start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - wait_start < 1100:
		await process_frame
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

	# Auto-join channel filter: reject 0-member, stale, owner-mismatch, and full channels.
	var talo_script = load("res://src/net/TaloBackend.gd")
	var now := Time.get_unix_time_from_system()
	var make_ch := func(members: int, owner_id: int, host_id: String, hb: float, roster_obj: Dictionary, status: String = "waiting") -> RefCounted:
		return FakeChannel.new(members, owner_id, "2026-11-17T00:00:00Z", {
			"status": status,
			"host_id": host_id,
			"heartbeat": str(int(hb)),
			"roster": JSON.stringify(roster_obj),
			"settings": JSON.stringify({"max_players": 4}),
		})
	var live_roster := {"10": {"user_id": "10", "display_name": "H"}}
	_check(bool(talo_script.call("is_channel_joinable", make_ch.call(1, 10, "10", now - 5.0, live_roster), now)),
			"live active channel is joinable")
	_check(not bool(talo_script.call("is_channel_joinable", make_ch.call(0, 10, "10", now - 5.0, live_roster), now)),
			"zero-member channel is rejected by join_auto")
	_check(not bool(talo_script.call("is_channel_joinable", make_ch.call(1, 10, "10", now - 300.0, live_roster), now)),
			"stale heartbeat channel is rejected by join_auto")
	_check(not bool(talo_script.call("is_channel_joinable", make_ch.call(1, 99, "10", now - 5.0, live_roster), now)),
			"owner/host mismatch channel is rejected by join_auto")
	_check(not bool(talo_script.call("is_channel_joinable", make_ch.call(1, 10, "10", now - 5.0, {}), now)),
			"channel missing host in roster is rejected by join_auto")
	_check(not bool(talo_script.call("is_channel_joinable", make_ch.call(4, 10, "10", now - 5.0, live_roster), now)),
			"full channel is rejected by join_auto")

	print("talo backend contract: %d checks, %d failure(s)" % [14, _failures])
	quit(1 if _failures > 0 else 0)
