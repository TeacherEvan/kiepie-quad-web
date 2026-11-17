extends Node
## Talo adapter for the game's existing net contract.
##
## Talo has no SQL RPCs, so lobby state lives in channel props (host-owned) and
## live events ride Talo socket channel messages. Scoring stays host-authoritative
## exactly as the old client-side path was; the Supabase server-side validation is
## intentionally not reproduced. Offline gates use MockBackend instead of this.

signal auth_status(ok: bool, message: String)
signal connection_state(state: String)
signal broadcast_received(event: String, payload: Variant)
signal postgres_change(data: Dictionary)
signal backend_error(message: String)

var user_id := ""
var is_ready := false

var _channel = null
var _channel_id := -1
var _lobby: Dictionary = {}
var _roster: Dictionary = {}          # user_id -> player row
var _starting := false
var _used_tokens: Dictionary = {}     # shot token -> true, stops echoed kills scoring twice
var _prop_gen := 0                    # guards interleaved channel-prop writes
var _reconnecting := false


# ------------------------------------------------------------------ lifecycle ---

func start() -> void:
	if _starting:
		return
	_starting = true
	var key := str(Talo.settings.get_value("", "access_key", ""))
	if not key.begins_with("eyJ"):
		auth_status.emit(false, "Talo game key missing — set TALO_API_GAME in .env")
		return
	await Talo.players.identify("anonymous", Talo.players.generate_identifier())
	if Talo.current_alias == null:
		auth_status.emit(false, "Talo identify failed — check key scopes")
		return
	user_id = str(Talo.current_alias.id)
	is_ready = true
	if not Talo.socket.message_received.is_connected(_on_socket_message):
		Talo.socket.message_received.connect(_on_socket_message)
	if not Talo.socket.connection_closed.is_connected(_on_socket_closed):
		Talo.socket.connection_closed.connect(_on_socket_closed)
	Talo.socket.open_connection()
	connection_state.emit("connected")
	auth_status.emit(true, "talo online · " + str(Talo.current_alias.identifier))


func _on_socket_closed(_code: int, _reason: String) -> void:
	connection_state.emit("disconnected")
	if not is_ready or _reconnecting:
		return
	_reconnecting = true
	await get_tree().create_timer(2.0).timeout
	_reconnecting = false
	if is_ready:
		Talo.socket.open_connection()
		connection_state.emit("reconnecting")


# ------------------------------------------------------------------ RPC surface ---

func call_rpc(name: String, args: Dictionary = {}) -> Dictionary:
	if not is_ready:
		backend_error.emit("Talo backend not ready")
		return {}
	match name:
		"create_lobby":
			return await _create_lobby(args)
		"join_auto":
			return await _join_auto(args)
		"join_by_code":
			return await _join_by_code(args)
		"leave_lobby":
			_leave_lobby()
			return {"ok": true}
		"start_match":
			return await _start_match()
		"set_settings":
			return await _set_settings(args)
		"set_ready":
			return await _set_ready(args)
		"issue_shot":
			return {"ok": true, "token": _token()}
		"register_kill":
			return await _register_kill(args)
		"time_up":
			return await _time_up()
		_:
			backend_error.emit("Unknown RPC: " + name)
			return {}


func join_lobby_channel(lobby_id: String) -> void:
	var id := int(lobby_id)
	if _channel_id == id or id <= 0:
		return
	var joined = await Talo.channels.join(id)
	_channel = joined if joined != null else await Talo.channels.find(id)
	if _channel != null:
		_channel_id = id
		_load_state()
		_send("join", {"user_id": user_id,
				"display_name": Settings.display_name(),
				"color": Settings.player_color()})


func leave_lobby_channel() -> void:
	if _channel_id > 0:
		Talo.channels.leave(_channel_id)
	_channel = null
	_channel_id = -1
	_lobby.clear()
	_roster.clear()


func broadcast(event: String, payload: Dictionary) -> void:
	_send(event, payload)


# ------------------------------------------------------------------ lobby ops ---

func _new_code() -> String:
	var alphabet := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var code := ""
	for i in range(5):
		code += alphabet[randi() % alphabet.length()]
	return code


func _player_row(args: Dictionary) -> Dictionary:
	return {
		"user_id": user_id,
		"display_name": str(args.get("p_display_name", Settings.display_name())),
		"color": str(args.get("p_color", Settings.player_color())),
		"score": 0,
		"respawn_at": "",
	}


func _make_lobby(code: String, name: String, settings: Dictionary) -> Dictionary:
	_lobby = {
		"id": str(_channel_id),
		"code": code,
		"name": name,
		"host_id": user_id,
		"settings": settings,
		"status": "waiting",
		"started_at": "",
		"winner_id": "",
	}
	return _lobby


func _create_lobby(args: Dictionary) -> Dictionary:
	var settings: Dictionary = args.get("p_settings", {})
	var code := _new_code()
	var props := {
		"code": code,
		"name": str(args.get("p_name", "Kiepie Lobby")).substr(0, 32),
		"settings": JSON.stringify(settings),
		"host_id": user_id,
		"status": "waiting",
		"started_at": "",
		"winner_id": "",
		"roster": JSON.stringify({user_id: _player_row(args)}),
	}
	var channel = await Talo.channels.create(code, true, props)
	if channel == null:
		backend_error.emit("Could not create Talo channel")
		return {}
	_channel = channel
	_channel_id = int(channel.id)
	_roster = {user_id: _player_row(args)}
	_make_lobby(code, str(props["name"]), settings)
	_emit_state()
	return {"lobby": _lobby, "player": _roster[user_id]}


func _join_auto(args: Dictionary) -> Dictionary:
	var res = await Talo.channels.get_channels(0)
	var channels: Array = res[0] if res is Array and res.size() > 0 else []
	# Prefer the emptiest lobby; stale abandoned channels tend to have more members.
	channels.sort_custom(func(a, b): return int(a.member_count) < int(b.member_count))
	for channel in channels:
		if await _try_join(channel, args):
			return {"lobby": _lobby, "player": _roster.get(user_id, {})}
	return await _create_lobby(args)


func _join_by_code(args: Dictionary) -> Dictionary:
	var code := str(args.get("p_code", "")).strip_edges().to_upper()
	var res = await Talo.channels.get_channels(0)
	var channels: Array = res[0] if res is Array and res.size() > 0 else []
	for channel in channels:
		if str(channel.get_prop("code", "")).to_upper() == code and await _try_join(channel, args):
			return {"lobby": _lobby, "player": _roster.get(user_id, {})}
	return {}


func _try_join(channel, args: Dictionary) -> bool:
	if str(channel.get_prop("status", "waiting")) != "waiting":
		return false
	var settings := _parse_dict(channel.get_prop("settings", "{}"))
	var max_players := clampi(int(settings.get("max_players", 8)), 2, 8)
	if int(channel.member_count) >= max_players:
		return false
	var joined = await Talo.channels.join(int(channel.id))
	if joined == null:
		return false
	_channel = joined
	_channel_id = int(channel.id)
	_load_state()
	if not _roster.has(user_id):
		_roster[user_id] = _player_row(args)
	_emit_roster()
	_send("join", _roster[user_id])
	return true


func _leave_lobby() -> void:
	if _channel_id > 0:
		_send("leave", {"user_id": user_id})
	leave_lobby_channel()


func _load_state() -> void:
	if _channel == null:
		return
	var code := str(_channel.get_prop("code", ""))
	var settings := _parse_dict(_channel.get_prop("settings", "{}"))
	_lobby = {
		"id": str(_channel_id),
		"code": code,
		"name": str(_channel.get_prop("name", code)),
		"host_id": str(_channel.get_prop("host_id", "")),
		"settings": settings,
		"status": str(_channel.get_prop("status", "waiting")),
		"started_at": str(_channel.get_prop("started_at", "")),
		"winner_id": str(_channel.get_prop("winner_id", "")),
	}
	_roster = _parse_dict(_channel.get_prop("roster", "{}"))


func _apply_props(extra: Dictionary = {}) -> void:
	if _channel == null:
		return
	var props := {
		"code": str(_lobby.get("code", "")),
		"name": str(_lobby.get("name", "")),
		"settings": JSON.stringify(_lobby.get("settings", {})),
		"host_id": str(_lobby.get("host_id", "")),
		"status": str(_lobby.get("status", "")),
		"started_at": str(_lobby.get("started_at", "")),
		"winner_id": str(_lobby.get("winner_id", "")),
		"roster": JSON.stringify(_roster),
	}
	for k in extra.keys():
		props[k] = extra[k]
	# Talo 0.20's update() sends props as a Dictionary but the v1 API requires
	# an array of {key,value}. Go through its client with the correct shape.
	var prop_array: Array = []
	for k in props.keys():
		prop_array.append({"key": k, "value": str(props[k])})
	var gen := _prop_gen + 1
	_prop_gen = gen
	var res = await Talo.channels.client.make_request(
			HTTPClient.METHOD_PUT, "/%s" % _channel_id, {"props": prop_array})
	if gen != _prop_gen:
		return  # a newer write superseded this one
	if int(res.get("status", 0)) == 200:
		var body: Dictionary = res.get("body", {})
		if body.has("channel"):
			_channel = TaloChannel.new(body["channel"])
	else:
		backend_error.emit("Talo channel update failed: %s" % str(res.get("status", "?")))


func _emit_state() -> void:
	postgres_change.emit({"table": "lobbies", "type": "UPDATE", "record": _lobby.duplicate(true)})


func _emit_roster() -> void:
	for uid in _roster.keys():
		var row: Dictionary = (_roster[uid] as Dictionary).duplicate(true)
		row["user_id"] = str(uid)
		postgres_change.emit({"table": "lobby_players", "type": "UPDATE", "record": row})


# ------------------------------------------------------------------ match ops ---

func _is_host() -> bool:
	return str(_lobby.get("host_id", "")) == user_id


func _start_match() -> Dictionary:
	if not _is_host():
		return {}
	_lobby["status"] = "playing"
	_lobby["started_at"] = _now_iso()
	await _apply_props()
	_send("state", {"lobby": _lobby, "roster": _roster})
	return _lobby.duplicate(true)


func _set_settings(args: Dictionary) -> Dictionary:
	if not _is_host():
		return {}
	_lobby["settings"] = (args.get("p_settings", {}) as Dictionary).duplicate(true)
	await _apply_props()
	_send("state", {"lobby": _lobby, "roster": _roster})
	return _lobby.duplicate(true)


func _set_ready(args: Dictionary) -> Dictionary:
	var ready := bool(args.get("p_ready", false))
	if _is_host():
		var row: Dictionary = _roster.get(user_id, {})
		row["is_ready"] = ready
		_roster[user_id] = row
		await _apply_props()
		_emit_roster()
		_send("state", {"lobby": _lobby, "roster": _roster})
		return {"players": _roster.duplicate(true)}
	# Guests ask the host to update the authoritative roster.
	_send("ready_request", {"user_id": user_id, "ready": ready})
	return {"ok": true, "pending": true}


func _register_kill(args: Dictionary) -> Dictionary:
	var target := str(args.get("p_target", ""))
	var token := str(args.get("p_token", ""))
	var killer := str(args.get("p_killer", user_id))
	if target == "" or token == "" or killer == "":
		return {}
	if not _is_host():
		# Host owns the scoreboard. Request the kill but do NOT apply a score
		# locally: "pending" makes MatchState wait for the host's state event.
		_send("kill_request", {"killer": killer, "target": target, "token": token})
		return {"ok": true, "pending": true,
				"lobby_status": str(_lobby.get("status", "")),
				"winner_id": str(_lobby.get("winner_id", ""))}
	if _used_tokens.has(token):
		return {"ok": false, "reason": "token_consumed"}
	if killer == target:
		return {"ok": false, "reason": "self_kill"}
	if str(_lobby.get("status", "")) != "playing":
		return {"ok": false, "reason": "lobby_not_playing"}
	if not _roster.has(killer) or not _roster.has(target):
		return {"ok": false, "reason": "not_in_lobby"}
	_used_tokens[token] = true
	var row: Dictionary = _roster.get(killer, {})
	var score := int(row.get("score", 0)) + 1
	row["score"] = score
	_roster[killer] = row
	if target != "":
		var victim: Dictionary = _roster.get(target, {})
		victim["respawn_at"] = _now_iso()
		_roster[target] = victim
	var status := str(_lobby.get("status", "waiting"))
	var winner := ""
	var target_kills := maxi(1, int((_lobby.get("settings", {}) as Dictionary).get("kill_target", 10)))
	if score >= target_kills:
		status = "finished"
		winner = killer
		_lobby["status"] = status
		_lobby["winner_id"] = winner
	await _apply_props()
	_emit_roster()
	_emit_state()
	# CombatController already broadcasts the "kill" event for the feed; send the
	# authoritative state too so guests' scoreboards converge. Never re-send a
	# "kill" here — its echo would re-enter register_kill and loop.
	_send("state", {"lobby": _lobby, "roster": _roster})
	return {"ok": true, "score": score,
			"lobby_status": status,
			"winner_id": winner}


func _time_up() -> Dictionary:
	if not _is_host() or str(_lobby.get("status", "")) != "playing":
		return {}
	var limit := maxi(0, int((_lobby.get("settings", {}) as Dictionary).get("match_seconds", 0)))
	if limit <= 0:
		return {}
	var started := _parse_iso(str(_lobby.get("started_at", "")))
	if started <= 0.0 or Time.get_unix_time_from_system() - started < float(limit):
		return {}
	var best := ""
	var best_score := -1
	for uid in _roster.keys():
		var s := int((_roster[uid] as Dictionary).get("score", 0))
		if s > best_score:
			best = str(uid)
			best_score = s
	_lobby["status"] = "finished"
	_lobby["winner_id"] = best
	await _apply_props()
	_send("state", {"lobby": _lobby, "roster": _roster})
	return _lobby.duplicate(true)


# ------------------------------------------------------------------ socket in ---

func _send(kind: String, payload: Dictionary) -> void:
	if _channel_id <= 0:
		return
	Talo.channels.send_message(_channel_id, JSON.stringify({"k": kind, "p": payload}))


func _on_socket_message(res: String, data: Dictionary) -> void:
	if res != "v1.channels.message":
		return
	var alias = data.get("playerAlias", null)
	if alias is Dictionary and int((alias as Dictionary).get("id", -1)) <= 0:
		return
	# Talo stamps every socket message with the sending alias; use it to reject
	# spoofed kill requests that name somebody else as the shooter.
	var sender_id := ""
	if alias is Dictionary:
		sender_id = str((alias as Dictionary).get("id", ""))
	var raw := str(data.get("message", ""))
	var json := JSON.new()
	if json.parse(raw) != OK or not (json.get_data() is Dictionary):
		return
	var msg: Dictionary = json.get_data()
	var kind := str(msg.get("k", ""))
	var payload: Variant = msg.get("p", {})
	match kind:
		"state":
			if payload is Dictionary:
				var p := payload as Dictionary
				if p.has("lobby") and p["lobby"] is Dictionary:
					_lobby = (p["lobby"] as Dictionary).duplicate(true)
				if p.has("roster") and p["roster"] is Dictionary:
					_roster = (p["roster"] as Dictionary).duplicate(true)
				_emit_state()
				_emit_roster()
		"join", "leave":
			if payload is Dictionary:
				var p := payload as Dictionary
				var uid := str(p.get("user_id", ""))
				if uid == "":
					return
				if kind == "join":
					var row := p.duplicate(true)
					row["user_id"] = uid
					_roster[uid] = row
				else:
					_roster.erase(uid)
				_emit_roster()
				if _is_host():
					await _apply_props()
					_send("state", {"lobby": _lobby, "roster": _roster})
		"ready_request":
			if _is_host() and payload is Dictionary:
				var p := payload as Dictionary
				var uid := str(p.get("user_id", ""))
				if uid == "" or not _roster.has(uid):
					return
				if sender_id != "" and uid != sender_id:
					return
				var row: Dictionary = _roster[uid]
				row["is_ready"] = bool(p.get("ready", false))
				_roster[uid] = row
				await _apply_props()
				_emit_roster()
				_send("state", {"lobby": _lobby, "roster": _roster})
		"kill_request":
			if _is_host() and payload is Dictionary:
				var p := payload as Dictionary
				var killer := str(p.get("killer", ""))
				var target := str(p.get("target", ""))
				var token := str(p.get("token", ""))
				if sender_id == "" or killer != sender_id:
					return
				if token == "" or _used_tokens.has(token):
					return
				await _register_kill({"p_target": target,
						"p_token": token,
						"p_killer": killer})
		"kill":
			if payload is Dictionary:
				broadcast_received.emit("kill", payload)
				var p := payload as Dictionary
				if str(p.get("victim", "")) == user_id:
					# refreshed roster arrives via the host's state message
					pass
		"shot":
			broadcast_received.emit("shot", payload)
		"lobby_update":
			broadcast_received.emit("lobby_update", payload)


# ------------------------------------------------------------------ helpers ---

func _parse_dict(text: String) -> Dictionary:
	if text.is_empty():
		return {}
	var json := JSON.new()
	if json.parse(text) != OK or not (json.get_data() is Dictionary):
		return {}
	return json.get_data() as Dictionary


func _now_iso() -> String:
	return Time.get_datetime_string_from_system(true, true).replace("T", " ") + "Z"


func _parse_iso(value: String) -> float:
	var s := value.replace("Z", "").replace("T", " ")
	var dict := Time.get_datetime_dict_from_datetime_string(s, true)
	if dict.is_empty():
		return 0.0
	return float(Time.get_unix_time_from_datetime_dict(dict))


func _token() -> String:
	return "%d-%d" % [Time.get_ticks_usec(), randi()]
