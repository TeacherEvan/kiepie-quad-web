extends SceneTree
## Offline gate: a victim's death broadcast awards the point to the killer
## through the authoritative RPC (only the killer's client calls register_kill).

var _fail := 0


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		printerr("FAIL ", label)
		_fail += 1


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	await process_frame
	var sb: Node = root.get_node("Supabase")
	if not bool(sb.get("use_mock")):
		printerr("LIVE BACKEND — refusing to run gate (KIEPIE_MOCK_BACKEND=1 not effective)")
		quit(2)
		return
	var match_state: Node = root.get_node("Match")
	var lobby: Node = root.get_node("Lobby")
	await lobby.call("join_auto")
	match_state.call("apply_lobby", {"status": "playing", "settings": {"kill_target": 10, "respawn_delay": 2.5}})
	var token: String = str((await match_state.call("issue_shot")).get("token", ""))
	_check(token != "", "killer issued a shot token")

	var net := Node3D.new()
	net.set_script(load("res://src/game/ArenaNet.gd"))
	root.add_child(net)
	net.call("_on_broadcast", "kill", {
		"killer": sb.get("user_id"), "victim": "victim-1", "token": token,
	})
	for i in range(8):
		await process_frame
		if int(match_state.call("my_score")) > 0:
			break
	_check(int(match_state.call("my_score")) == 1, "killer scored from the death broadcast")

	# A second client receiving the same event must NOT award another point.
	net.call("_on_broadcast", "kill", {
		"killer": "someone-else", "victim": "victim-1", "token": token,
	})
	for i in range(4):
		await process_frame
	_check(int(match_state.call("my_score")) == 1, "spectators do not score")

	net.queue_free()
	quit(1 if _fail > 0 else 0)
