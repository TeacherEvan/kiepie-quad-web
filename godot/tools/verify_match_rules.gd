extends SceneTree
## Offline gate: lobby join, shot tokens, scoring, respawn and win rules.
## Runs entirely on MockBackend (no Supabase project required).

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
	# autoload _ready runs after the tool's _initialize in --script mode
	await process_frame
	await process_frame
	var sb: Node = root.get_node("Supabase")
	if not bool(sb.get("use_mock")):
		printerr("LIVE BACKEND — refusing to run gate (KIEPIE_MOCK_BACKEND=1 not effective)")
		quit(2)
		return
	var match_state: Node = root.get_node("Match")
	var lobby: Node = root.get_node("Lobby")
	var joined: bool = await lobby.call("join_auto")
	_check(joined, "join_auto returns a lobby")
	_check(not (match_state.get("lobby") as Dictionary).is_empty(), "match state received lobby")
	_check(int(match_state.call("kill_target")) == 10, "default kill target is 10")
	_check(int(match_state.call("max_players")) == 8, "default max players is 8")
	_check(float(match_state.call("respawn_delay")) == 2.5, "default respawn delay is 2.5s")

	var shot: Dictionary = await match_state.call("issue_shot")
	_check(shot.has("token") and str(shot["token"]) != "", "issue_shot returns a token")
	var token := str(shot.get("token", ""))

	var kill: Dictionary = await match_state.call("register_kill", "target-alpha", token)
	_check(bool(kill.get("ok", false)), "valid kill accepted")
	_check(int(kill.get("score", 0)) == 1, "score incremented to 1")

	var reuse: Dictionary = await match_state.call("register_kill", "target-beta", token)
	_check(not bool(reuse.get("ok", true)), "reused token rejected")
	_check(str(reuse.get("reason", "")) == "token_consumed", "reason is token_consumed")

	(sb.get("mock") as Node).call("reset_cooldown_for_test")
	await match_state.call("set_lobby_settings", {"kill_target": 2, "game_mode": "death_race", "damage": 55})
	_check(int(match_state.call("kill_target")) == 2 and str(match_state.call("game_mode")) == "death_race" and int(match_state.call("damage")) == 55,
			"host settings updated to kill_target=2, death_race, damage=55")
	var second: Dictionary = await match_state.call("issue_shot")
	(sb.get("mock") as Node).call("reset_cooldown_for_test")
	var finish: Dictionary = await match_state.call("register_kill", "target-gamma", str(second.get("token", "")))
	_check(bool(finish.get("ok", false)), "second kill accepted")
	_check(str(finish.get("lobby_status", "")) == "finished", "match finished at kill target")
	_check(bool(match_state.call("is_finished")), "match state marked finished")

	lobby.call("leave")
	_check(match_state.get("lobby").is_empty(), "Lobby.leave() immediately empties Match.lobby (P1-2)")
	_check(str(match_state.call("game_mode")) == "battle_royale"
			and int(match_state.call("damage")) == 30.0,
			"Match._settings_cache resets on Lobby.leave() (P1-2)")
	quit(1 if _fail > 0 else 0)
