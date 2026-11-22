extends SceneTree
## Offline regression gate for the surgical audit. Locks the four defects that
## the original 15 gates did not catch: forged authoritative state, broken
## three-stop VFX gradient, misplaced exhaust flames, malformed shot payloads,
## and the respawn_at deadline contract.
## No live backend is touched (TaloBackend is staged in memory, _channel = null).

var _fail := 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS ", label)
	else:
		printerr("FAIL ", label)
		_fail += 1

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	await process_frame
	await _state_spoof()
	await _net_security_and_roster()
	await _join_allowlist_and_channel_guards()
	_gradient_stops()
	_exhaust_axis()
	_malformed_shot()
	_respawn_deadline()
	print("AUDIT REGRESSIONS: %d failure(s)" % _fail)
	quit(1 if _fail > 0 else 0)


## P0-1 (join allowlist) + P1-3 (channel-active guard on join/bike_state).
func _join_allowlist_and_channel_guards() -> void:
	# 1. Matching-alias "join" must not inject laps/kills/score/readiness —
	#    join rows are an explicit allowlist; forged values default to 0/false.
	var b: Node = (load("res://src/net/TaloBackend.gd") as GDScript).new()
	root.add_child(b)
	b.set("is_ready", true)
	b.set("user_id", "2")
	b.set("_lobby", {"id": "1", "host_id": "2", "status": "playing", "settings": {}})
	b.set("_roster", {"2": {"user_id": "2", "score": 0, "is_ready": false}})
	b.set("_channel_id", 1)
	b.set("_channel", null)
	var forged := JSON.stringify({"k": "join", "p": {
			"user_id": "2", "display_name": "RIDER", "color": "#00ff00",
			"laps": 99, "kills": 99, "score": 99, "is_ready": true}})
	await b.call("_on_socket_message", "v1.channels.message",
			{"playerAlias": {"id": 2}, "message": forged})
	var row1: Dictionary = b.get("_roster")["2"] as Dictionary
	_check(int(row1.get("laps", -1)) == 0 and int(row1.get("kills", -1)) == 0
			and int(row1.get("score", -1)) == 0 and not bool(row1.get("is_ready", true)),
			"P0-1: forged join from matching alias cannot inject laps/kills/score/readiness")
	# 2. Re-joining an existing peer omitting laps/kills preserves trusted state.
	var r2: Dictionary = b.get("_roster")["2"] as Dictionary
	r2["laps"] = 2
	r2["kills"] = 3
	r2["score"] = 2
	var join2 := JSON.stringify({"k": "join", "p": {"user_id": "2", "display_name": "RIDER"}})
	await b.call("_on_socket_message", "v1.channels.message",
			{"playerAlias": {"id": 2}, "message": join2})
	var row2: Dictionary = b.get("_roster")["2"] as Dictionary
	_check(int(row2.get("laps", -1)) == 2 and int(row2.get("kills", -1)) == 3
			and int(row2.get("score", -1)) == 2,
			"P0-1: join omitting laps/kills preserves trusted roster state (laps=2 kills=3 score=2)")
	# 3. After leave_lobby_channel (_channel_id == -1), live join/bike_state
	#    frames are dropped: roster stays empty, zero signals emitted.
	var sig := 0
	b.connect("broadcast_received", func(_e: String, _p: Variant) -> void: sig += 1)
	b.leave_lobby_channel()
	var join3 := JSON.stringify({"k": "join", "p": {"user_id": "2", "display_name": "RIDER"}})
	await b.call("_on_socket_message", "v1.channels.message",
			{"playerAlias": {"id": 2}, "message": join3})
	_check(b.get("_roster").is_empty() and sig == 0,
			"P1-3: join dropped after leave_lobby_channel (roster empty, 0 signals)")
	await b.call("_on_socket_message", "v1.channels.message",
			{"playerAlias": {"id": 2}, "message": JSON.stringify({"k": "bike_state", "p": {}})})
	await b.call("_on_socket_message", "v1.channels.message",
			{"playerAlias": {"id": 2}, "message": JSON.stringify({"k": "shot", "p": {"id": "2"}})})
	await b.call("_on_socket_message", "v1.channels.message",
			{"playerAlias": {"id": 2}, "message": JSON.stringify({"k": "hurt", "p": {"victim": "2", "amount": 30}})})
	await b.call("_on_socket_message", "v1.channels.message",
			{"playerAlias": {"id": 2}, "message": JSON.stringify({"k": "kill", "p": {"victim": "2", "killer": "1"}})})
	_check(b.get("_roster").is_empty() and sig == 0,
			"P1-3: bike_state/shot/hurt/kill dropped after leave_lobby_channel (roster empty, 0 signals)")
	b.free()

func _state_spoof() -> void:
	var b: Node = (load("res://src/net/TaloBackend.gd") as GDScript).new()
	root.add_child(b)
	b.set("is_ready", true)
	b.set("user_id", "1")
	b.set("_lobby", {"id": "1", "host_id": "1", "status": "playing", "settings": {}})
	b.set("_roster", {"1": {"user_id": "1", "score": 0},
			"2": {"user_id": "2", "score": 0}})
	b.set("_channel_id", 1)
	b.set("_channel", null)
	var forged := JSON.stringify({"k": "state", "p": {
		"lobby": {"status": "finished", "winner_id": "2"},
		"roster": {"2": {"user_id": "2", "score": 999}}}})
	await b.call("_on_socket_message", "v1.channels.message",
			{"playerAlias": {"id": 999}, "message": forged})
	var lobby: Dictionary = b.get("_lobby")
	var roster: Dictionary = b.get("_roster")
	_check(str(lobby.get("status", "")) == "playing" and
			int((roster["2"] as Dictionary).get("score", 0)) == 0,
			"guest cannot forge authoritative state")
	# P1-1: host ignores its own stale state echo; guest applies monotonic host state
	var host_echo := JSON.stringify({"k": "state", "p": {
		"seq": 1,
		"lobby": {"status": "playing", "settings": {}},
		"roster": {"2": {"user_id": "2", "score": 99}}}})
	await b.call("_on_socket_message", "v1.channels.message",
			{"playerAlias": {"id": 1}, "message": host_echo})
	var roster_host: Dictionary = b.get("_roster")
	_check(int((roster_host["2"] as Dictionary).get("score", 0)) == 0,
			"P1-1: host ignores its own echoed state frame")

	b.set("user_id", "2")
	var auth := JSON.stringify({"k": "state", "p": {
		"seq": 2,
		"lobby": {"status": "playing", "settings": {}},
		"roster": {"2": {"user_id": "2", "score": 7}}}})
	await b.call("_on_socket_message", "v1.channels.message",
			{"playerAlias": {"id": 1}, "message": auth})
	var roster2: Dictionary = b.get("_roster")
	_check(int((roster2["2"] as Dictionary).get("score", 0)) == 7,
			"authentic host state is applied on guest (positive control)")
	var stale_seq := JSON.stringify({"k": "state", "p": {
		"seq": 1,
		"lobby": {"status": "playing", "settings": {}},
		"roster": {"2": {"user_id": "2", "score": 1}}}})
	await b.call("_on_socket_message", "v1.channels.message",
			{"playerAlias": {"id": 1}, "message": stale_seq})
	var roster2_after: Dictionary = b.get("_roster")
	_check(int((roster2_after["2"] as Dictionary).get("score", 0)) == 7,
			"P1-1: guest drops out-of-order host state (seq 1 <= 2)")
	b.set("user_id", "1")
	# forged join: payload names a user_id that is not the sender's alias
	var forged_join := JSON.stringify({"k": "join", "p": {
		"user_id": "999", "display_name": "forger", "color": "#ff0000", "score": 9999}})
	await b.call("_on_socket_message", "v1.channels.message",
			{"playerAlias": {"id": 7}, "message": forged_join})
	var roster3: Dictionary = b.get("_roster")
	_check(not roster3.has("999"), "forged join from another alias is rejected")
	b.free()

func _net_security_and_roster() -> void:
	var b: Node = (load("res://src/net/TaloBackend.gd") as GDScript).new()
	root.add_child(b)
	b.set("is_ready", true)
	b.set("user_id", "1")
	b.set("_lobby", {"id": "1", "host_id": "1", "status": "playing", "settings": {}})
	b.set("_roster", {
		"1": {"user_id": "1", "score": 0, "is_ready": false},
		"2": {"user_id": "2", "score": 0, "is_ready": false},
		"3": {"user_id": "3", "score": 0, "is_ready": false},
	})
	b.set("_channel_id", 1)
	b.set("_channel", null)

	var relayed: Array = []
	b.connect("broadcast_received", func(ev: String, pay: Variant) -> void:
		relayed.append([ev, pay]))
	var pg_events: Array = []
	b.connect("postgres_change", func(d: Dictionary) -> void:
		pg_events.append(d))

	# F-01: guest cannot forge lobby_update; host lobby_update is relayed
	var forged_lu := JSON.stringify({"k": "lobby_update", "p": {
		"lobby": {"status": "finished", "winner_id": "2", "host_id": "2"}}})
	await b.call("_on_socket_message", "v1.channels.message",
			{"playerAlias": {"id": 2}, "message": forged_lu})
	_check(relayed.is_empty(), "F-01: guest forged lobby_update is dropped")
	var host_lu := JSON.stringify({"k": "lobby_update", "p": {
		"lobby": {"status": "playing", "host_id": "1"}}})
	await b.call("_on_socket_message", "v1.channels.message",
			{"playerAlias": {"id": 1}, "message": host_lu})
	_check(relayed.size() == 1 and str(relayed[0][0]) == "lobby_update",
			"F-01: authentic host lobby_update is relayed (positive control)")
	relayed.clear()

	# F-03: non-victim cannot spoof kill; victim's own kill is relayed
	var spoof_kill := JSON.stringify({"k": "kill", "p": {
		"killer": "1", "victim": "2", "token": "forged-tok"}})
	await b.call("_on_socket_message", "v1.channels.message",
			{"playerAlias": {"id": 3}, "message": spoof_kill})
	_check(relayed.is_empty(), "F-03: third-party spoofed kill broadcast is dropped")
	await b.call("_on_socket_message", "v1.channels.message",
			{"playerAlias": {"id": 2}, "message": spoof_kill})
	_check(relayed.size() == 1 and str(relayed[0][0]) == "kill",
			"F-03: victim-authored kill broadcast is relayed (positive control)")
	relayed.clear()

	# F-05: ready_request with missing playerAlias or mismatched alias is dropped
	var ready_msg := JSON.stringify({"k": "ready_request", "p": {
		"user_id": "2", "ready": true}})
	await b.call("_on_socket_message", "v1.channels.message", {"message": ready_msg})
	var r_after_empty: Dictionary = b.get("_roster")
	_check(not bool((r_after_empty["2"] as Dictionary).get("is_ready", false)),
			"F-05: ready_request with missing playerAlias is rejected")
	await b.call("_on_socket_message", "v1.channels.message",
			{"playerAlias": {"id": 3}, "message": ready_msg})
	var r_after_mismatch: Dictionary = b.get("_roster")
	_check(not bool((r_after_mismatch["2"] as Dictionary).get("is_ready", false)),
			"F-05: ready_request from mismatched alias is rejected")
	await b.call("_on_socket_message", "v1.channels.message",
			{"playerAlias": {"id": 2}, "message": ready_msg})
	var r_after_auth: Dictionary = b.get("_roster")
	_check(bool((r_after_auth["2"] as Dictionary).get("is_ready", false)),
			"F-05: authentic ready_request toggles is_ready (positive control)")

	# F-04: peer leave emits SYNC without departed uid and MatchState erases it
	var m: Node = root.get_node("Match")
	var prev_lobby: Dictionary = (m.get("lobby") as Dictionary).duplicate(true)
	var prev_players: Dictionary = (m.get("players") as Dictionary).duplicate(true)
	m.set("lobby", {"id": "1", "host_id": "1", "status": "waiting", "settings": {}})
	m.set("players", {
		"1": {"user_id": "1", "score": 0},
		"2": {"user_id": "2", "score": 0},
		"3": {"user_id": "3", "score": 0},
	})
	pg_events.clear()
	var leave_msg := JSON.stringify({"k": "leave", "p": {"user_id": "3"}})
	await b.call("_on_socket_message", "v1.channels.message",
			{"playerAlias": {"id": 3}, "message": leave_msg})
	for ev in pg_events:
		m.call("_on_pg_change", ev)
	var m_players: Dictionary = m.get("players")
	_check(not m_players.has("3") and m_players.has("1") and m_players.has("2"),
			"F-04: departed peer is removed from Match.players via roster SYNC")
	m.call("_on_pg_change", {"table": "lobby_players", "type": "DELETE", "record": {"user_id": "2"}})
	var m_players2: Dictionary = m.get("players")
	_check(not m_players2.has("2") and m_players2.has("1"),
			"F-04: MatchState._on_pg_change handles DELETE for lobby_players")
	m.call("set_lobby", {
		"lobby": {"id": "2", "host_id": "9", "status": "waiting", "settings": {}},
		"player": {"user_id": "9", "score": 0},
	})
	var m_players3: Dictionary = m.get("players")
	_check(not m_players3.has("1") and m_players3.has("9"),
			"F-04: MatchState.set_lobby clears prior players when switching lobby IDs")
	# P1-2: Lobby.leave() bumps _session_gen even when current_lobby_id == ""
	var lobby_node: Node = root.get_node_or_null("Lobby")
	if lobby_node != null:
		lobby_node.set("current_lobby_id", "")
		var gen_before := int(lobby_node.get("_session_gen"))
		lobby_node.call("leave")
		var gen_after := int(lobby_node.get("_session_gen"))
		_check(gen_after > gen_before, "P1-2: Lobby.leave() increments _session_gen even when current_lobby_id is empty")
		var ghost_ok: bool = await lobby_node.call("_enter_if_current", gen_before, {"lobby": {"id": "ghost-1"}})
		_check(not ghost_ok and str(lobby_node.get("current_lobby_id")) == "",
				"P1-2: stale in-flight join/create is rejected without entering ghost lobby")
	# P2-1: host join omitting "vehicle" preserves existing "AstonMartin" preference
	b.set("_roster", {"2": {"user_id": "2", "vehicle": "AstonMartin", "score": 0}})
	await b.call("_on_socket_message", "v1.channels.message", {
		"playerAlias": {"id": 2},
		"message": JSON.stringify({"k": "join", "p": {"user_id": "2", "display_name": "RIDER"}}),
	})
	var row_veh: Dictionary = b.get("_roster")["2"] as Dictionary
	_check(str(row_veh.get("vehicle", "")) == "AstonMartin",
			"P2-1: join omitting vehicle preserves existing AstonMartin preference")
	m.set("lobby", prev_lobby)
	m.set("players", prev_players)
	b.free()

func _gradient_stops() -> void:
	var vf: GDScript = load("res://src/game/VfxFactory.gd")
	var tex: GradientTexture1D = vf.call("_ramp", [
			Color(1, 1, 1, 1), Color(1, 0.5, 0.1, 0.7), Color(1, 0.2, 0, 0)])
	_check(tex.gradient.get_point_count() == 3,
			"three-stop VFX ramp keeps all three gradient points")
	_check(is_equal_approx(tex.gradient.get_offset(2), 1.0),
			"VFX ramp ends at offset 1.0 (transparent fade preserved)")

func _exhaust_axis() -> void:
	var bike := (load("res://scenes/KiepieBike.tscn") as PackedScene).instantiate()
	root.add_child(bike)
	bike.call("_build_flames")
	var fx := bike.get_node_or_null("ExhaustFlames") as GPUParticles3D
	var tip := bike.get_node_or_null("Model/Bike_Root/Silencer_Tip") as Node3D
	if fx != null and tip != null:
		var dir: Vector3 = (fx.process_material as ParticleProcessMaterial).direction
		_check(fx.position.z < 0.0 and dir.z < 0.0,
				"turbo flames sit at the rear and point backwards")
	else:
		_check(false, "exhaust flame / silencer nodes exist")
	bike.free()

func _malformed_shot() -> void:
	var net := Node3D.new()
	net.set_script(load("res://src/game/ArenaNet.gd"))
	root.add_child(net)
	var before := net.get_child_count()
	net.call("_spawn_remote_shot", {"id": "enemy", "o": [1], "d": [1, 0, 0], "token": "t"})
	_check(net.get_child_count() == before, "short shot arrays are rejected without a projectile")
	net.free()

func _respawn_deadline() -> void:
	var m: Node = root.get_node("Match")
	var future := Time.get_datetime_dict_from_unix_time(
			int(Time.get_unix_time_from_system()) + 10)
	var iso := "%04d-%02d-%02d %02d:%02d:%02dZ" % [future["year"], future["month"],
			future["day"], future["hour"], future["minute"], future["second"]]
	m.set("players", {"ghost": {"user_id": "ghost", "respawn_at": iso}})
	_check(bool(m.call("is_respawning", "ghost")),
			"respawn_at is read as a future deadline")
	var past := Time.get_datetime_dict_from_unix_time(
			int(Time.get_unix_time_from_system()) - 10)
	var past_iso := "%04d-%02d-%02d %02d:%02d:%02dZ" % [past["year"], past["month"],
			past["day"], past["hour"], past["minute"], past["second"]]
	m.set("players", {"ghost": {"user_id": "ghost", "respawn_at": past_iso}})
	_check(not bool(m.call("is_respawning", "ghost")),
			"respawn_at in the past is not respawning")
	m.set("players", {"ghost": {"user_id": "ghost", "respawn_at": ""}})
	_check(not bool(m.call("is_respawning", "ghost")),
			"empty respawn_at is not respawning")
