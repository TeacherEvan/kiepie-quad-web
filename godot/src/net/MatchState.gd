extends Node
## Authoritative mirror of lobby + match state. Autoload name: Match.
## All score / win / respawn rules read from here, never from a peer.

signal roster_changed()
signal lobby_changed()
signal match_started()
signal match_finished(winner_id: String)
signal score_updated(user_id: String, score: int)
signal self_respawn_at(seconds: float)
signal error_message(message: String)

var lobby: Dictionary = {}
var players: Dictionary = {}      # user_id -> player row
var my_user_id := ""
var last_result: Dictionary = {}
var _time_up_called := false


func _ready() -> void:
	my_user_id = Supabase.user_id
	Supabase.auth_status.connect(_on_auth)
	Supabase.postgres_change.connect(_on_pg_change)
	Supabase.broadcast_received.connect(_on_broadcast)


func _on_auth(ok: bool, _message: String) -> void:
	if ok:
		my_user_id = Supabase.user_id


func time_limit_seconds() -> int:
	return maxi(0, int(settings().get("match_seconds", 0)))


func _process(_delta: float) -> void:
	if not is_playing() or _time_up_called:
		return
	var limit := time_limit_seconds()
	if limit <= 0 or str(lobby.get("host_id", "")) != my_user_id:
		return
	var started := _iso_to_unix(str(lobby.get("started_at", "")))
	if started <= 0.0:
		return
	if Time.get_unix_time_from_system() - started < float(limit):
		return
	_time_up_called = true
	var res: Dictionary = await Supabase.call_rpc("time_up", {})
	if not res.is_empty() and str(res.get("status", "")) == "finished":
		apply_lobby(res)
	else:
		# Network error or server/client clock skew - allow a later retry.
		_time_up_called = false


func reset_time_limit_guard() -> void:
	_time_up_called = false


func set_lobby(result: Dictionary) -> void:
	if result.has("lobby"):
		lobby = (result["lobby"] as Dictionary).duplicate(true)
	if result.has("player"):
		var p := (result["player"] as Dictionary).duplicate(true)
		players[str(p.get("user_id", my_user_id))] = p
	lobby_changed.emit()
	roster_changed.emit()


func apply_lobby(row: Dictionary) -> void:
	var was_playing := is_playing()
	lobby = row.duplicate(true)
	if is_playing() and not was_playing:
		_time_up_called = false
	lobby_changed.emit()
	match str(row.get("status", "")):
		"playing":
			match_started.emit()
		"finished":
			match_finished.emit(str(row.get("winner_id", "")))


func settings() -> Dictionary:
	return (lobby.get("settings", {}) as Dictionary).duplicate(true)


func kill_target() -> int:
	return maxi(1, int(settings().get("kill_target", 10)))


func max_players() -> int:
	return clampi(int(settings().get("max_players", 8)), 2, 8)


func respawn_delay() -> float:
	return clampf(float(settings().get("respawn_delay", 2.5)), 0.5, 10.0)


func damage() -> float:
	return clampf(float(settings().get("damage", 30.0)), 10.0, 100.0)


func pickups_enabled() -> bool:
	return bool(settings().get("pickups", true))


func is_playing() -> bool:
	return str(lobby.get("status", "")) == "playing"


func is_finished() -> bool:
	return str(lobby.get("status", "")) == "finished"


func player_count() -> int:
	return players.size()


func my_score() -> int:
	var p: Dictionary = players.get(my_user_id, {})
	return int(p.get("score", 0))


func leader_id() -> String:
	var best := ""
	var best_score := -1
	for uid in players.keys():
		var s := int((players[uid] as Dictionary).get("score", 0))
		if s > best_score:
			best = str(uid)
			best_score = s
	return best


func scoreboard() -> Array:
	var host := str(lobby.get("host_id", ""))
	var out: Array = []
	for uid in players.keys():
		var p := players[uid] as Dictionary
		out.append({
			"user_id": str(uid),
			"name": str(p.get("display_name", "RIDER")),
			"color": str(p.get("color", "#ffffff")),
			"score": int(p.get("score", 0)),
			"is_ready": bool(p.get("is_ready", false)),
			"is_host": str(uid) == host,
			"is_me": str(uid) == my_user_id,
		})
	out.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]))
	return out


func all_ready() -> bool:
	if players.size() < 2:
		return false
	for uid in players.keys():
		var p := players[uid] as Dictionary
		if not bool(p.get("is_ready", false)):
			return false
	return true


func is_respawning(user_id: String) -> bool:
	var p: Dictionary = players.get(user_id, {})
	var at := str(p.get("respawn_at", ""))
	if at == "" or at == "null":
		return false
	return _iso_to_unix(at) > Time.get_unix_time_from_system()


func respawn_remaining(user_id: String) -> float:
	var p: Dictionary = players.get(user_id, {})
	var at := str(p.get("respawn_at", ""))
	if at == "" or at == "null":
		return 0.0
	return maxf(0.0, _iso_to_unix(at) - Time.get_unix_time_from_system())


func _iso_to_unix(value: String) -> float:
	var s := value.replace("Z", "")
	var utc := value.ends_with("Z")
	var dict := Time.get_datetime_dict_from_datetime_string(s, utc)
	if dict.is_empty():
		return 0.0
	return float(Time.get_unix_time_from_datetime_dict(dict))


# ------------------------------------------------------------------ RPCs ---

func issue_shot() -> Dictionary:
	var res: Dictionary = await Supabase.call_rpc("issue_shot", {})
	return res


func register_kill(target_id: String, token: String) -> Dictionary:
	var res: Dictionary = await Supabase.call_rpc("register_kill", {
		"p_target": target_id,
		"p_token": token,
	})
	last_result = res
	if bool(res.get("ok", false)):
		if bool(res.get("pending", false)):
			# Host-authoritative backend: the host will broadcast the verified
			# score via "state". Scoring locally here would trust an unverified
			# client request and let guest/host scoreboards diverge.
			return res
		var score := int(res.get("score", my_score() + 1))
		var me := my_user_id
		if players.has(me):
			players[me]["score"] = score
		score_updated.emit(me, score)
		var status := str(res.get("lobby_status", ""))
		if status == "finished":
			lobby["status"] = "finished"
			lobby["winner_id"] = str(res.get("winner_id", ""))
			lobby_changed.emit()
			match_finished.emit(str(res.get("winner_id", "")))
	else:
		error_message.emit(str(res.get("reason", "kill rejected")))
	return res


func start_match() -> void:
	var res: Dictionary = await Supabase.call_rpc("start_match", {})
	if not res.is_empty():
		apply_lobby(res)


func set_lobby_settings(new_settings: Dictionary) -> void:
	var res: Dictionary = await Supabase.call_rpc("set_settings", {"p_settings": new_settings})
	if not res.is_empty():
		apply_lobby(res)


func set_ready(ready: bool) -> void:
	if players.has(my_user_id) and players[my_user_id] is Dictionary:
		players[my_user_id]["is_ready"] = ready
		roster_changed.emit()
	var res: Dictionary = await Supabase.call_rpc("set_ready", {"p_ready": ready})
	if not res.is_empty() and not bool(res.get("pending", false)) and res.has("players"):
		players = (res["players"] as Dictionary).duplicate(true)
		roster_changed.emit()


# ----------------------------------------------------------- realtime in ---

func _on_pg_change(data: Dictionary) -> void:
	var table := str(data.get("table", ""))
	var kind := str(data.get("type", ""))
	if kind == "DELETE":
		return
	var record: Variant = data.get("record", null)
	if not (record is Dictionary):
		return
	var row := record as Dictionary
	match table:
		"lobbies":
			apply_lobby(row)
		"lobby_players":
			var uid := str(row.get("user_id", ""))
			var old_score := int((players.get(uid, {}) as Dictionary).get("score", 0))
			players[uid] = row.duplicate(true)
			var new_score := int(row.get("score", 0))
			if new_score != old_score:
				score_updated.emit(uid, new_score)
			if uid == my_user_id and not str(row.get("respawn_at", "")).is_empty():
				self_respawn_at.emit(respawn_delay())
			roster_changed.emit()


func _on_broadcast(event: String, payload: Variant) -> void:
	if not (payload is Dictionary):
		return
	var p := payload as Dictionary
	match event:
		"lobby_update":
			if p.has("lobby") and p["lobby"] is Dictionary:
				apply_lobby(p["lobby"] as Dictionary)
		"kill":
			# kill feed is rendered by the HUD; score already came from Postgres
			pass
