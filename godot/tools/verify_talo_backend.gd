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
	backend._channel_id = 1
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

	# Host: unrelated kill claims inside the per-killer cooldown are rate-limited,
	# while same-blast chained drum tokens ("tok-1:c101") are allowed (P3-3).
	var rapid: Dictionary = await backend.call_rpc("register_kill",
			{"p_target": "2", "p_token": "tok-5", "p_killer": "1"})
	_check(not bool(rapid.get("ok", true)) and str(rapid.get("reason", "")) == "rate_limited",
			"host rate-limits an unrelated second kill within 1 s")
	var chain_kill: Dictionary = await backend.call_rpc("register_kill",
			{"p_target": "2", "p_token": "tok-1:c101", "p_killer": "1"})
	_check(bool(chain_kill.get("ok", false)) and int(chain_kill.get("score", 0)) == 2,
			"P3-3: host accepts same-blast chained drum kill within 0.6 s")

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
	var cur_proto := str(talo_script.get("PROTOCOL_VERSION"))
	_check(cur_proto == "3", "PROTOCOL_VERSION bumped to 3 for 3-vehicle Aston Martin integration")
	var now := Time.get_unix_time_from_system()
	var make_ch := func(members: int, owner_id: int, host_id: String, hb: float, roster_obj: Dictionary, status: String = "waiting", proto: String = "") -> RefCounted:
		var use_proto := cur_proto if proto == "__CURRENT__" else proto
		var props := {
			"status": status,
			"host_id": host_id,
			"heartbeat": str(int(hb)),
			"roster": JSON.stringify(roster_obj),
			"settings": JSON.stringify({"max_players": 4}),
		}
		if use_proto != "":
			props["protocol_version"] = use_proto
		return FakeChannel.new(members, owner_id, "2026-11-17T00:00:00Z", props)
	var live_roster := {"10": {"user_id": "10", "display_name": "H"}}
	_check(bool(talo_script.call("is_channel_joinable", make_ch.call(1, 10, "10", now - 5.0, live_roster, "waiting", "__CURRENT__"), now)),
			"live active channel is joinable")
	_check(not bool(talo_script.call("is_channel_joinable", make_ch.call(0, 10, "10", now - 5.0, live_roster, "waiting", "__CURRENT__"), now)),
			"zero-member channel is rejected by join_auto")
	_check(not bool(talo_script.call("is_channel_joinable", make_ch.call(1, 10, "10", now - 300.0, live_roster, "waiting", "__CURRENT__"), now)),
			"stale heartbeat channel is rejected by join_auto")
	_check(not bool(talo_script.call("is_channel_joinable", make_ch.call(1, 99, "10", now - 5.0, live_roster, "waiting", "__CURRENT__"), now)),
			"owner/host mismatch channel is rejected by join_auto")
	_check(not bool(talo_script.call("is_channel_joinable", make_ch.call(1, 10, "10", now - 5.0, {}, "waiting", "__CURRENT__"), now)),
			"channel missing host in roster is rejected by join_auto")
	_check(not bool(talo_script.call("is_channel_joinable", make_ch.call(4, 10, "10", now - 5.0, live_roster, "waiting", "__CURRENT__"), now)),
			"full channel is rejected by join_auto")
	_check(not bool(talo_script.call("is_channel_joinable", make_ch.call(1, 10, "10", now - 5.0, live_roster, "waiting", "2"), now)),
			"protocol-versioned channel with an older version (v2) is rejected")
	_check(not bool(talo_script.call("is_channel_joinable", make_ch.call(1, 10, "10", now - 5.0, live_roster, "waiting", "1"), now)),
			"protocol-versioned channel with an older version (v1) is rejected")
	_check(not bool(talo_script.call("is_channel_joinable", make_ch.call(1, 10, "10", now - 5.0, live_roster, "waiting", ""), now)),
			"channel missing protocol_version is rejected (pre-versioning lobby)")
	_check(bool(talo_script.call("protocol_ok", make_ch.call(1, 10, "10", now - 5.0, live_roster, "waiting", "__CURRENT__"))),
			"protocol_ok accepts the current wire version")
	_check(not bool(talo_script.call("protocol_ok", make_ch.call(1, 10, "10", now - 5.0, live_roster, "waiting", "1"))),
			"protocol_ok rejects an older wire version")

	# B-P0-1 & B-P0-2 regressions: lap_request rejected in battle_royale, rate-limited in death_race,
	# and Death Race kills never collide with lap score.
	var dr_backend := _new_backend()
	get_root().add_child(dr_backend)
	dr_backend._lobby["settings"] = {"game_mode": "battle_royale", "kill_target": 10, "lap_target": 3}
	var br_lap: Dictionary = await dr_backend.call_rpc("register_lap", {"p_racer": "1", "p_token": "br-lap-1"})
	_check(not bool(br_lap.get("ok", true)) and str(br_lap.get("reason", "")) == "wrong_mode",
			"B-P0-1: register_lap rejected with wrong_mode in battle_royale")

	dr_backend._lobby["settings"] = {"game_mode": "death_race", "kill_target": 10, "lap_target": 3}
	dr_backend._roster = {
		"1": {"user_id": "1", "display_name": "host", "score": 0},
		"2": {"user_id": "2", "display_name": "guest", "score": 0},
	}
	await dr_backend.call_rpc("register_kill", {"p_target": "2", "p_token": "dr-k1", "p_killer": "1"})
	dr_backend._kill_cooldowns.clear()
	await dr_backend.call_rpc("register_kill", {"p_target": "2", "p_token": "dr-k2", "p_killer": "1"})
	var dr_lap1: Dictionary = await dr_backend.call_rpc("register_lap", {"p_racer": "1", "p_token": "dr-lap-1"})
	_check(bool(dr_lap1.get("ok", false)) and int(dr_lap1.get("score", -1)) == 1
			and str(dr_lap1.get("lobby_status", "")) == "playing",
			"B-P0-2: 2 kills + 1 lap in 3-lap Death Race leaves score=1 and status=playing")
	var dr_lap_spam: Dictionary = await dr_backend.call_rpc("register_lap", {"p_racer": "1", "p_token": "dr-lap-2"})
	_check(not bool(dr_lap_spam.get("ok", true)) and str(dr_lap_spam.get("reason", "")) == "rate_limited",
			"B-P0-1: rapid second lap within MIN_LAP_SECONDS is rate_limited")

	# B-P1-4 & P1-3 regressions: leave_lobby_channel increments _prop_gen and drops ALL subsequent socket messages
	var gen_before := int(dr_backend.get("_prop_gen"))
	var post_leave_sigs := 0
	dr_backend.connect("broadcast_received", func(_e: String, _p: Variant) -> void: post_leave_sigs += 1)
	dr_backend.leave_lobby_channel()
	_check(int(dr_backend.get("_prop_gen")) > gen_before,
			"B-P1-4: leave_lobby_channel increments _prop_gen to invalidate in-flight writes")
	for kind in ["shot", "hurt", "kill", "leave"]:
		await dr_backend._on_socket_message("v1.channels.message", {
			"playerAlias": {"id": 2},
			"message": JSON.stringify({"k": kind, "p": {"id": "2", "victim": "2", "user_id": "2"}}),
		})
	_check(post_leave_sigs == 0,
			"P1-3: shot/hurt/kill/leave frames are all dropped after leave_lobby_channel")
	dr_backend.free()

	# P1-1 regression: AOE / twin-barrel multi-kill sub-tokens (:v / :b / :d) score up to 4 victims in 0.6 s
	var mk: Node = (load("res://src/net/TaloBackend.gd") as GDScript).new() as Node
	mk.user_id = "1"
	mk.is_ready = true
	mk._channel_id = 1
	mk._lobby = {"id": "1", "host_id": "1", "status": "playing", "settings": {"game_mode": "battle_royale", "kill_target": 10}}
	mk._roster = {
		"1": {"user_id": "1", "display_name": "host", "score": 0},
		"2": {"user_id": "2", "display_name": "p2", "score": 0},
		"3": {"user_id": "3", "display_name": "p3", "score": 0},
		"4": {"user_id": "4", "display_name": "p4", "score": 0},
		"5": {"user_id": "5", "display_name": "p5", "score": 0},
		"6": {"user_id": "6", "display_name": "p6", "score": 0},
	}
	var mk1: Dictionary = await mk.call_rpc("register_kill", {"p_target": "2", "p_token": "meteor-1:v2", "p_killer": "1"})
	var mk2: Dictionary = await mk.call_rpc("register_kill", {"p_target": "3", "p_token": "meteor-1:v3", "p_killer": "1"})
	var mk_dup: Dictionary = await mk.call_rpc("register_kill", {"p_target": "3", "p_token": "meteor-1:v3", "p_killer": "1"})
	var mk3: Dictionary = await mk.call_rpc("register_kill", {"p_target": "4", "p_token": "meteor-1:v4", "p_killer": "1"})
	var mk4: Dictionary = await mk.call_rpc("register_kill", {"p_target": "5", "p_token": "meteor-1:v5", "p_killer": "1"})
	var mk5: Dictionary = await mk.call_rpc("register_kill", {"p_target": "6", "p_token": "meteor-1:v6", "p_killer": "1"})
	_check(bool(mk1.get("ok", false)) and bool(mk2.get("ok", false))
			and bool(mk3.get("ok", false)) and bool(mk4.get("ok", false))
			and int(mk4.get("score", -1)) == 4,
			"P1-1: AOE sub-tokens (:v) score up to 4 unique victims in 0.6 s")
	_check(not bool(mk_dup.get("ok", true)) and str(mk_dup.get("reason", "")) == "token_consumed",
			"P1-1: replaying a consumed sub-token is rejected")
	_check(not bool(mk5.get("ok", true)) and str(mk5.get("reason", "")) == "rate_limited",
			"P1-1: 5th sub-token in same 0.6 s burst is rate_limited")
	mk.free()

	# P1-6a: guest _register_lap validates wrong_mode, token_consumed, and MIN_LAP_SECONDS before lap_request
	var gl := _new_backend()
	get_root().add_child(gl)
	gl.user_id = "2"
	gl._lobby = {"id": "1", "host_id": "1", "status": "playing", "settings": {"game_mode": "battle_royale", "lap_target": 3}}
	var gl_br: Dictionary = await gl.call_rpc("register_lap", {"p_racer": "2", "p_token": "g-br"})
	_check(not bool(gl_br.get("ok", true)) and str(gl_br.get("reason", "")) == "wrong_mode",
			"P1-6a: guest register_lap rejected with wrong_mode in battle_royale")
	gl._lobby["settings"] = {"game_mode": "death_race", "lap_target": 3}
	var gl_ok: Dictionary = await gl.call_rpc("register_lap", {"p_racer": "2", "p_token": "g-lap-1"})
	_check(bool(gl_ok.get("ok", false)) and bool(gl_ok.get("pending", false)),
			"P1-6a: first guest register_lap in death_race returns ok=true, pending=true")
	var gl_dup: Dictionary = await gl.call_rpc("register_lap", {"p_racer": "2", "p_token": "g-lap-1"})
	_check(not bool(gl_dup.get("ok", true)) and str(gl_dup.get("reason", "")) == "token_consumed",
			"P1-6a: replaying guest lap token is rejected with token_consumed")
	var gl_spam: Dictionary = await gl.call_rpc("register_lap", {"p_racer": "2", "p_token": "g-lap-2"})
	_check(not bool(gl_spam.get("ok", true)) and str(gl_spam.get("reason", "")) == "rate_limited",
			"P1-6a: rapid second guest lap within MIN_LAP_SECONDS is rate_limited")
	gl.free()

	# P1-3: _apply_props awaits _apply_drained when _apply_inflight is true
	var ap := _new_backend()
	get_root().add_child(ap)
	_check(ap.has_signal("_apply_drained"), "P1-3: TaloBackend exposes _apply_drained signal")
	ap.set("_apply_inflight", true)
	var resumed := [false]
	var drain_waiter := func() -> void:
		await ap.call("_apply_props", {"k": "v"})
		resumed[0] = true
	drain_waiter.call()
	await process_frame
	_check(not resumed[0], "P1-3: _apply_props blocks while _apply_inflight is true")
	ap.emit_signal("_apply_drained")
	await process_frame
	_check(resumed[0] and bool(ap.get("_apply_dirty")), "P1-3: _apply_props resumes on _apply_drained with _apply_dirty=true")
	ap.free()

	# P1-7 & P1-4/P1-5: _handoff_host_before_leave aborts on channel mismatch; _poll_host_alive guards _channel_id <= 0
	var ho := _new_backend()
	get_root().add_child(ho)
	var ho_lost := [false]
	ho.connect("host_lost", func() -> void: ho_lost[0] = true)
	ho._channel_id = 99
	await ho.call("_handoff_host_before_leave", 42)
	ho._channel_id = 0
	await ho.call("_poll_host_alive")
	_check(not ho_lost[0], "P1-7: _handoff_host_before_leave(mismatch) and _poll_host_alive(_channel_id=0) do not emit host_lost")
	ho.free()

	# P1-8: checked-in addons/talo/settings.cfg keeps auto_connect_socket=false
	var talo_cfg := ConfigFile.new()
	var cfg_ok := talo_cfg.load("res://addons/talo/settings.cfg") == OK
	_check(cfg_ok and not bool(talo_cfg.get_value("", "auto_connect_socket", true)),
			"P1-8: addons/talo/settings.cfg ships auto_connect_socket=false")

	# P0-1: late v1.players.identify.success promotes timed-out TaloBackend online
	var late_b := _new_backend()
	get_root().add_child(late_b)
	late_b.is_ready = false
	late_b.user_id = "42"
	var promoted := [false]
	late_b.connect("auth_status", func(ok: bool, _m: String) -> void:
		if ok:
			promoted[0] = true)
	await late_b.call("_on_socket_message", "v1.players.identify.success", {})
	_check(bool(late_b.is_ready) and promoted[0],
			"P0-1: late v1.players.identify.success promotes timed-out TaloBackend to is_ready=true")
	late_b.free()

	# P1-9: waiting-lobby host leave emits host_lost for guests
	var wl := _new_backend()
	get_root().add_child(wl)
	wl.user_id = "2"
	wl._lobby["status"] = "waiting"
	wl._lobby["host_id"] = "1"
	var wl_lost := [false]
	wl.connect("host_lost", func() -> void: wl_lost[0] = true)
	await wl.call("_on_socket_message", "v1.channels.message", {
		"playerAlias": {"id": 1},
		"message": JSON.stringify({"k": "leave", "p": {"user_id": "1"}}),
	})
	_check(wl_lost[0], "P1-9: host leave in waiting lobby emits host_lost")
	wl.free()

	# P1-1: host-handoff _state_seq rollover
	var hh := _new_backend()
	get_root().add_child(hh)
	hh.user_id = "2"
	hh._channel_id = 10
	hh._lobby = {"id": "10", "host_id": "1", "status": "playing"}
	await hh.call("_on_socket_message", "v1.channels.message", {
		"channel": {"id": 10},
		"playerAlias": {"id": 1},
		"message": JSON.stringify({"k": "state", "p": {"seq": 50, "lobby": {"id": "10", "host_id": "1", "status": "playing"}, "roster": {"1": {"user_id": "1"}, "2": {"user_id": "2"}}}}),
	})
	hh._lobby["host_id"] = "3"
	await hh.call("_on_socket_message", "v1.channels.message", {
		"channel": {"id": 10},
		"playerAlias": {"id": 3},
		"message": JSON.stringify({"k": "state", "p": {"seq": 1, "lobby": {"id": "10", "host_id": "3", "status": "playing"}, "roster": {"1": {"user_id": "1"}, "2": {"user_id": "2"}, "3": {"user_id": "3"}}}}),
	})
	_check(str(hh.get("_last_state_host")) == "3" and int(hh.get("_last_state_seq")) == 1 and (hh.get("_roster") as Dictionary).has("3"),
			"P1-1/P3-3: host handoff resets _last_state_host, accepts lower seq=1, and updates _roster")
	await hh.call("_on_socket_message", "v1.channels.message", {
		"channel": {"id": 10},
		"playerAlias": {"id": 3},
		"message": JSON.stringify({"k": "state", "p": {"seq": 7, "lobby": {"id": "10", "host_id": "2", "status": "playing"}, "roster": {"2": {"user_id": "2"}, "3": {"user_id": "3"}}}}),
	})
	_check(int(hh.get("_state_seq")) >= 7,
			"P1-1: new host seeds _state_seq >= _last_state_seq (got %d)" % int(hh.get("_state_seq")))

	# P2-7: late "join" from unknown uid during "playing" is rejected
	await hh.call("_on_socket_message", "v1.channels.message", {
		"channel": {"id": 10},
		"playerAlias": {"id": 99},
		"message": JSON.stringify({"k": "join", "p": {"user_id": "99", "display_name": "LATE"}}),
	})
	_check(not (hh.get("_roster") as Dictionary).has("99"),
			"P2-7: late join from unknown uid during playing match is rejected")

	# P1-1 (lap): guest retry allowed after 2.6 s (< 12 s) while host still enforces 12 s
	var gl_retry := _new_backend()
	get_root().add_child(gl_retry)
	gl_retry.user_id = "2"
	gl_retry._lobby = {"id": "1", "host_id": "1", "status": "playing", "settings": {"game_mode": "death_race", "lap_target": 3}}
	var now_s := Time.get_ticks_msec() / 1000.0
	gl_retry._lap_timestamps["2"] = now_s - 2.6
	var gl_retry_res: Dictionary = await gl_retry.call_rpc("register_lap", {"p_racer": "2", "p_token": "g-retry-ok"})
	_check(bool(gl_retry_res.get("ok", false)) and bool(gl_retry_res.get("pending", false)),
			"P1-1: guest register_lap allows recovery retry after 2.6 s")
	gl_retry.free()
	hh.free()

	# P1-3: post-await channel swap suppresses stale _broadcast_state
	var sw := _new_backend()
	get_root().add_child(sw)
	sw.user_id = "1"
	sw._channel_id = 10
	sw._lobby = {"id": "10", "host_id": "1", "status": "waiting"}
	sw._roster = {"1": {"user_id": "1"}, "2": {"user_id": "2", "is_ready": false}}
	sw.set("_apply_inflight", true)
	var seq_before := int(sw.get("_state_seq"))
	sw.call("_on_socket_message", "v1.channels.message", {
		"channel": {"id": 10},
		"playerAlias": {"id": 2},
		"message": JSON.stringify({"k": "ready_request", "p": {"user_id": "2", "ready": true}}),
	})
	sw._channel_id = 20
	sw._lobby = {"id": "20", "host_id": "1", "status": "waiting"}
	sw.emit_signal("_apply_drained")
	await process_frame
	_check(int(sw.get("_state_seq")) == seq_before,
			"P1-3: post-await channel swap suppresses stale _broadcast_state (seq=%d)" % int(sw.get("_state_seq")))
	sw.free()

	# P2-5: last_auth_error surfaces on MainMenu when offline
	var err_tb := _new_backend()
	_check(str(err_tb.get("last_auth_error")) == "", "P2-5: TaloBackend.last_auth_error starts empty")
	err_tb.free()
	var sb_err := get_root().get_node_or_null("Supabase")
	if sb_err != null:
		var prev_ready := bool(sb_err.get("is_ready"))
		var prev_mock := bool(sb_err.get("use_mock"))
		var prev_err := str(sb_err.get("last_auth_error")) if "last_auth_error" in sb_err else ""
		sb_err.set("is_ready", false)
		sb_err.set("use_mock", false)
		if "last_auth_error" in sb_err:
			sb_err.set("last_auth_error", "Auth timed out — check network")
		var mm_scene := load("res://scenes/MainMenu.tscn") as PackedScene
		if mm_scene != null:
			var mm := mm_scene.instantiate()
			get_root().add_child(mm)
			await process_frame
			var st_lbl := mm.get_node_or_null("SafeMargin/Scroll/ScrollBox/Card/VBox/Status") as Label
			var retry_btn := mm.get_node_or_null("SafeMargin/Scroll/ScrollBox/Card/VBox/BtnRetry") as Button
			_check(st_lbl != null and st_lbl.text.find("Auth timed out") >= 0
					and retry_btn != null and retry_btn.visible,
					"P2-5: MainMenu surfaces last_auth_error and shows BtnRetry when offline")
			mm.queue_free()
			await process_frame
		sb_err.set("is_ready", prev_ready)
		sb_err.set("use_mock", prev_mock)
		if "last_auth_error" in sb_err:
			sb_err.set("last_auth_error", prev_err)

	print("talo backend contract: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)
