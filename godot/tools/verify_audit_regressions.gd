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
	_state_spoof()
	_gradient_stops()
	_exhaust_axis()
	_malformed_shot()
	_respawn_deadline()
	print("AUDIT REGRESSIONS: %d failure(s)" % _fail)
	quit(1 if _fail > 0 else 0)

func _state_spoof() -> void:
	var b: Node = (load("res://src/net/TaloBackend.gd") as GDScript).new()
	root.add_child(b)
	b.set("is_ready", true)
	b.set("user_id", "1")
	b.set("_lobby", {"id": "1", "host_id": "1", "status": "playing", "settings": {}})
	b.set("_roster", {"1": {"user_id": "1", "score": 0},
			"2": {"user_id": "2", "score": 0}})
	b.set("_channel_id", -1)
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
	# positive control: an authentic host state message MUST be applied —
	# a one-sided lock would stay green even if the state branch were deleted
	var auth := JSON.stringify({"k": "state", "p": {
		"lobby": {"status": "playing", "settings": {}},
		"roster": {"2": {"user_id": "2", "score": 7}}}})
	await b.call("_on_socket_message", "v1.channels.message",
			{"playerAlias": {"id": 1}, "message": auth})
	var roster2: Dictionary = b.get("_roster")
	_check(int((roster2["2"] as Dictionary).get("score", 0)) == 7,
			"authentic host state is applied (positive control)")
	# forged join: payload names a user_id that is not the sender's alias
	var forged_join := JSON.stringify({"k": "join", "p": {
		"user_id": "999", "display_name": "forger", "color": "#ff0000", "score": 9999}})
	await b.call("_on_socket_message", "v1.channels.message",
			{"playerAlias": {"id": 7}, "message": forged_join})
	var roster3: Dictionary = b.get("_roster")
	_check(not roster3.has("999"), "forged join from another alias is rejected")
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
