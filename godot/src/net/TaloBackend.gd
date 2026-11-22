extends Node
## Talo adapter for the game's existing net contract.
##
## Talo has no SQL RPCs, so lobby state lives in channel props (host-owned) and
## live events ride Talo socket channel messages. Scoring stays host-authoritative
## exactly as the old client-side path was; the Supabase server-side validation is
## intentionally not reproduced. Offline gates use MockBackend instead of this.

const KT := preload("res://src/core/KiepieTime.gd")

## Talo wire protocol. Bump ONLY when the wire format breaks (message kinds,
## prop keys, kill-token semantics). Lobbies stamp it as the `protocol_version`
## channel prop; peers present it too — mismatched peers are never mixed into
## the same lobby.
const PROTOCOL_VERSION := "3"

signal auth_status(ok: bool, message: String)
signal connection_state(state: String)
signal broadcast_received(event: String, payload: Variant)
signal postgres_change(data: Dictionary)
signal _apply_drained()
signal backend_error(message: String)
signal host_lost()

var user_id := ""
var is_ready := false

var _channel = null
var _channel_id := -1
var _lobby: Dictionary = {}
var _roster: Dictionary = {}          # user_id -> player row
var _starting := false
var _used_tokens: Dictionary = {}     # shot token -> true, stops echoed kills scoring twice
var _kill_cooldowns: Dictionary = {}  # killer -> sec timestamp of last scored kill (host only)
var _kill_last_base: Dictionary = {}  # killer -> {"base": String, "count": int, "at": float}
var _kill_window: Dictionary = {}     # killer -> Array of sec timestamps (60 s, max 20)
var _hurt_log: Dictionary = {}        # sender -> Array of sec timestamps (1 s, max 24)
var _lap_timestamps: Dictionary = {}  # racer -> sec timestamp of last scored lap (host only)
const HEARTBEAT_INTERVAL_S := 20.0
const STALE_LOBBY_S := 90.0
const HOST_ACK_TIMEOUT_MS := 2000
const SOCKET_IDENTIFY_TIMEOUT_MS := 10000
const HOST_POLL_INTERVAL_S := 15.0
const MAX_USED_TOKENS := 512
const MIN_LAP_SECONDS := 12.0
const MAX_RECONNECT_ATTEMPTS := 5

var _prop_gen := 0                    # guards interleaved channel-prop writes
var _reconnecting := false
var _reconnect_attempts := 0          # exponential backoff for socket re-open
var _host_ack := false
var _heartbeat_accum := 0.0
var _host_poll_accum := 0.0           # non-host: staleness watch for the host
var _apply_inflight := false          # single-writer lock for channel props
var _apply_dirty := false             # a write was requested while one was in flight
var _apply_extra: Dictionary = {}     # merged one-shot prop overrides
var _host_lost_emitted := false       # emit host_lost once per lobby, not every poll
var _state_seq := 0                   # monotonic host state sequence
var _last_state_seq := -1             # last applied host state sequence on guest


# ------------------------------------------------------------------ lifecycle ---

func _promote_online() -> void:
	if is_ready:
		return
	is_ready = true
	_starting = false
	_reconnect_attempts = 0
	connection_state.emit("connected")
	var ident := str(Talo.current_alias.identifier) if (Talo != null and Talo.current_alias != null) else user_id
	auth_status.emit(true, "talo online · " + ident)


func reconnect() -> void:
	if is_ready or _starting:
		return
	start()


func start() -> void:
	if _starting:
		return
	_starting = true
	var key := str(Talo.settings.get_value("", "access_key", ""))
	if not key.begins_with("eyJ"):
		_starting = false
		auth_status.emit(false, "Talo game key missing — set TALO_API_GAME in .env")
		return
	await Talo.players.identify("anonymous", Talo.players.generate_identifier())
	if not is_inside_tree():
		_starting = false
		return
	if Talo.current_alias == null:
		_starting = false
		auth_status.emit(false, "Talo identify failed — check key scopes")
		return
	user_id = str(Talo.current_alias.id)
	if not Talo.socket.message_received.is_connected(_on_socket_message):
		Talo.socket.message_received.connect(_on_socket_message)
	if not Talo.socket.connection_closed.is_connected(_on_socket_closed):
		Talo.socket.connection_closed.connect(_on_socket_closed)
	await Talo.socket.open_connection()
	if not is_inside_tree():
		_starting = false
		return
	var sock_deadline := Time.get_ticks_msec() + SOCKET_IDENTIFY_TIMEOUT_MS
	while is_inside_tree() and not bool(Talo.socket.get("_identified")) and Time.get_ticks_msec() < sock_deadline:
		await get_tree().process_frame
	if bool(Talo.socket.get("_identified")):
		_promote_online()
		return
	# Wall-clock deadline, no server verdict: report failure, never a
	# false "online" that silently drops every send.
	is_ready = false
	_starting = false
	auth_status.emit(false, "Talo socket timed out — tap Retry or any multiplayer mode")
	return


func _process(delta: float) -> void:
	if not is_ready or _channel_id <= 0:
		_heartbeat_accum = 0.0
		_host_poll_accum = 0.0
		return
	var status := str(_lobby.get("status", ""))
	if _is_host():
		# Heartbeat lives in channel props, so it must keep flowing during a
		# match — otherwise non-hosts polling it cannot tell host-silence from
		# host-aliveness. Skip only once the lobby is finished.
		if status == "finished":
			_heartbeat_accum = 0.0
			return
		_heartbeat_accum += delta
		if _heartbeat_accum >= HEARTBEAT_INTERVAL_S:
			_heartbeat_accum = 0.0
			_apply_props()
		return
	# Non-host: watch for host silence mid-match or in waiting lobby (tab kill, network drop).
	# One failed poll is not a verdict; only a stale heartbeat or missing host ends the lobby.
	if status == "playing" or status == "waiting":
		_host_poll_accum += delta
		if _host_poll_accum >= HOST_POLL_INTERVAL_S:
			_host_poll_accum = 0.0
			_poll_host_alive()
	else:
		_host_poll_accum = 0.0


func _poll_host_alive() -> void:
	if not is_inside_tree() or _channel_id <= 0:
		return
	var polled_id := _channel_id
	var polled_gen := _prop_gen
	var ch: Variant = await Talo.channels.find(polled_id)
	if _channel_id != polled_id or _prop_gen != polled_gen or _channel_id <= 0 or ch == null:
		return  # transient fetch failure or channel changed; do not void the match on one poll
	var ch_host := str(ch.get_prop("host_id", ""))
	if ch_host != "" and ch_host != str(_lobby.get("host_id", "")):
		_channel = ch
		_load_state()
		_emit_state()
		_emit_roster()
		return
	var hb := float(str(ch.get_prop("heartbeat", "0")))
	if hb <= 0.0:
		return
	var ch_roster := _parse_dict(str(ch.get_prop("roster", "{}")))
	var host_missing := not ch_roster.is_empty() and not ch_roster.has(str(_lobby.get("host_id", "")))
	if Time.get_unix_time_from_system() - hb > STALE_LOBBY_S or host_missing:
		if _host_lost_emitted:
			return  # one verdict per lobby; MatchState already ended the match
		_host_lost_emitted = true
		connection_state.emit("host_lost")
		host_lost.emit()


func _on_socket_closed(_code: int, _reason: String) -> void:
	connection_state.emit("disconnected")
	if not is_ready or _reconnecting:
		return
	_reconnecting = true
	# Hold _reconnecting across the full bounded retry loop so concurrent closes
	# never spawn racing reconnect coroutines, and transient pre-auth drops (where
	# vendored TaloSocket._poll() will not re-emit connection_closed) still retry.
	var reconnected := false
	while _reconnect_attempts < MAX_RECONNECT_ATTEMPTS and is_inside_tree() and is_ready:
		_reconnect_attempts += 1
		var delay := minf(30.0, 2.0 * pow(2.0, float(_reconnect_attempts - 1)))
		await get_tree().create_timer(delay).timeout
		if not is_inside_tree() or not is_ready:
			break
		if Talo.current_alias != null:
			await Talo.players.identify("anonymous", Talo.current_alias.identifier)
		if not is_inside_tree() or not is_ready:
			break
		await Talo.socket.open_connection()
		var sock_deadline := Time.get_ticks_msec() + SOCKET_IDENTIFY_TIMEOUT_MS
		while is_inside_tree() and not bool(Talo.socket.get("_identified")) and Time.get_ticks_msec() < sock_deadline:
			await get_tree().process_frame
		if bool(Talo.socket.get("_identified")):
			_reconnect_attempts = 0
			reconnected = true
			connection_state.emit("connected")
			# Re-sync authoritative state: a reconnect may have missed match-start,
			# host-handoff, or winner transitions — fetch fresh channel props and
			# re-emit state/roster so converged peers see the current lobby.
			if _channel_id > 0:
				var closed_id := _channel_id
				var closed_gen := _prop_gen
				var ch = await Talo.channels.find(closed_id)
				if _channel_id != closed_id or _prop_gen != closed_gen or _channel_id <= 0:
					break
				if ch != null:
					_channel = ch
				_load_state()
				_emit_state()
				_emit_roster()
			break
	_reconnecting = false
	if not reconnected and is_inside_tree() and is_ready:
		is_ready = false
		_starting = false
		connection_state.emit("disconnected")
		auth_status.emit(false, "Talo socket reconnect timed out — check your connection")


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
			await _leave_lobby()
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
		"register_lap":
			return await _register_lap(args)
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
		_host_lost_emitted = false
		_load_state()
		_send("join", {"user_id": user_id,
				"display_name": Settings.display_name(),
				"color": Settings.player_color(),
				"vehicle": Settings.preferred_vehicle()})


func leave_lobby_channel() -> void:
	# Bump _prop_gen so any in-flight _write_props() response cannot resurrect _channel.
	_prop_gen += 1
	_state_seq = 0
	_last_state_seq = -1
	_apply_dirty = false
	_apply_extra.clear()
	if _channel_id > 0 and _channel != null:
		Talo.channels.leave(_channel_id)
	_channel = null
	_channel_id = -1
	_lobby.clear()
	_roster.clear()
	_lap_timestamps.clear()
	_kill_cooldowns.clear()
	_kill_last_base.clear()
	_kill_window.clear()
	_hurt_log.clear()
	_host_lost_emitted = false


func broadcast(event: String, payload: Dictionary) -> void:
	# TaloBackend already reserves wire kind "state" for host-owned lobby/roster
	# snapshots; carry realtime ArenaNet bike transforms under "bike_state" so
	# peer positions are relayed instead of dropped by host checks.
	var wire_kind := "bike_state" if event == "state" else event
	_send(wire_kind, payload)


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
		"vehicle": VehicleRegistry.sanitize_preference(str(args.get("p_vehicle", ""))),
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
		"heartbeat": str(int(Time.get_unix_time_from_system())),
		"protocol_version": PROTOCOL_VERSION,
		"roster": JSON.stringify({user_id: _player_row(args)}),
	}
	var channel = await Talo.channels.create(code, true, props)
	if channel == null:
		backend_error.emit("Could not create Talo channel")
		return {}
	_channel = channel
	_channel_id = int(channel.id)
	_state_seq = 0
	_last_state_seq = -1
	_heartbeat_accum = 0.0
	_roster = {user_id: _player_row(args)}
	_make_lobby(code, str(props["name"]), settings)
	_emit_state()
	return {"lobby": _lobby, "player": _roster[user_id]}


static func protocol_ok(channel) -> bool:
	## A lobby is only matchable within the same protocol version. A missing
	## prop means a pre-versioning lobby: skip it rather than mix wires.
	if channel == null:
		return false
	return str(channel.get_prop("protocol_version", "")) == PROTOCOL_VERSION


static func is_channel_joinable(channel, now_unix: float, max_stale_sec: float = STALE_LOBBY_S) -> bool:
	if channel == null:
		return false
	if not protocol_ok(channel):
		return false
	if str(channel.get_prop("status", "waiting")) != "waiting":
		return false
	if int(channel.member_count) <= 0:
		return false
	var host_id := str(channel.get_prop("host_id", ""))
	if host_id == "":
		return false
	if channel.owner_alias == null or str(channel.owner_alias.id) != host_id:
		return false
	var roster := _parse_dict_static(str(channel.get_prop("roster", "{}")))
	if not roster.has(host_id):
		return false
	var settings := _parse_dict_static(str(channel.get_prop("settings", "{}")))
	var max_players := clampi(int(settings.get("max_players", 8)), 2, 8)
	if int(channel.member_count) >= max_players:
		return false
	var hb := float(str(channel.get_prop("heartbeat", "0")))
	if hb <= 0.0:
		hb = _parse_iso_static(str(channel.updated_at))
	if hb > 0.0 and (now_unix - hb) > max_stale_sec:
		return false
	return true


func _fetch_all_channels(max_pages: int = 10) -> Array:
	var all_channels: Array = []
	for page in range(max_pages):
		var res = await Talo.channels.get_channels(page)
		if not (res is Array) or res.is_empty():
			break
		var page_channels: Variant = res[0]
		if page_channels is Array:
			all_channels.append_array(page_channels as Array)
		var is_last := true
		if res.size() >= 3:
			is_last = bool(res[2])
		if is_last:
			break
	return all_channels


func _join_auto(args: Dictionary) -> Dictionary:
	var wanted_mode := str(args.get("p_game_mode", ""))
	var raw_channels: Array = await _fetch_all_channels(10)
	var now_unix := Time.get_unix_time_from_system()
	var candidates: Array = []
	for ch in raw_channels:
		if is_channel_joinable(ch, now_unix):
			if wanted_mode != "":
				var ch_settings := _parse_dict_static(str(ch.get_prop("settings", "{}")))
				var ch_mode := str(ch_settings.get("game_mode", "battle_royale"))
				if ch_mode != wanted_mode:
					continue
			candidates.append(ch)
	# Prefer active lobbies with fewer players, breaking ties by newest heartbeat.
	candidates.sort_custom(func(a, b):
		var ma := int(a.member_count)
		var mb := int(b.member_count)
		if ma != mb:
			return ma < mb
		return float(str(a.get_prop("heartbeat", "0"))) > float(str(b.get_prop("heartbeat", "0"))))
	for channel in candidates:
		_host_ack = false
		if await _try_join(channel, args):
			if _is_host():
				return {"lobby": _lobby, "player": _roster.get(user_id, {})}
			var deadline := Time.get_ticks_msec() + HOST_ACK_TIMEOUT_MS
			while is_inside_tree() and not _host_ack and Time.get_ticks_msec() < deadline:
				await get_tree().process_frame
			if _host_ack:
				return {"lobby": _lobby, "player": _roster.get(user_id, {})}
			# Host vanished before heartbeat expired — leave zombie room and try next.
			leave_lobby_channel()
	var create_args := args.duplicate(true)
	if wanted_mode != "" and not create_args.has("p_settings"):
		create_args["p_settings"] = {
			"game_mode": wanted_mode,
			"lap_target": 3,
			"kill_target": 10,
			"max_players": 8,
			"respawn_delay": 2.5,
			"match_seconds": 0,
			"damage": 30,
			"pickups": true,
			"friendly_fire": false,
		}
	return await _create_lobby(create_args)


func _join_by_code(args: Dictionary) -> Dictionary:
	var code := str(args.get("p_code", "")).strip_edges().to_upper()
	var channels: Array = await _fetch_all_channels(10)
	var saw_protocol_mismatch := false
	var saw_stale := false
	var now_unix := Time.get_unix_time_from_system()
	for channel in channels:
		if str(channel.get_prop("code", "")).to_upper() != code:
			continue
		if not protocol_ok(channel):
			saw_protocol_mismatch = true
			continue
		if not is_channel_joinable(channel, now_unix):
			# Zombie room (dead host): never trap the guest inside — join_auto
			# applies the same heartbeat freshness check.
			saw_stale = true
			continue
		_host_ack = false
		if await _try_join(channel, args):
			if _is_host():
				return {"lobby": _lobby, "player": _roster.get(user_id, {})}
			# Guests must prove the host is alive before committing, exactly like
			# join_auto — otherwise every ready_request goes unanswered forever.
			var deadline := Time.get_ticks_msec() + HOST_ACK_TIMEOUT_MS
			while is_inside_tree() and not _host_ack and Time.get_ticks_msec() < deadline:
				await get_tree().process_frame
			if _host_ack:
				return {"lobby": _lobby, "player": _roster.get(user_id, {})}
			leave_lobby_channel()
			saw_stale = true
	if saw_protocol_mismatch:
		return {"message": "That room is on a different game version — update the game to join."}
	if saw_stale:
		return {"message": "That room appears to have expired — ask the host to start a new one."}
	return {}


func _try_join(channel, args: Dictionary) -> bool:
	if not protocol_ok(channel):
		backend_error.emit("Protocol mismatch — room is on a different game version")
		return false
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
	_state_seq = 0
	_last_state_seq = -1
	_load_state()
	if not _roster.has(user_id):
		_roster[user_id] = _player_row(args)
	_emit_state()
	_emit_roster()
	_send("join", _roster[user_id])
	return true


func _leave_lobby() -> void:
	var leaving_id := _channel_id
	if _channel_id > 0:
		if _is_host() and _roster.size() > 1 and str(_lobby.get("status", "")) == "waiting":
			await _handoff_host_before_leave(leaving_id)
		if _channel_id != leaving_id:
			return  # user already joined a new lobby — never wipe it
		_send("leave", {"user_id": user_id})
	leave_lobby_channel()


func _handoff_host_before_leave(leaving_id: int) -> void:
	var keys: Array = _roster.keys()
	keys.sort()
	var next_host := ""
	for k in keys:
		if str(k) != user_id:
			next_host = str(k)
			break
	if next_host == "":
		return
	var new_roster := _roster.duplicate(true)
	new_roster.erase(user_id)
	var new_lobby := _lobby.duplicate(true)
	new_lobby["host_id"] = next_host
	var prop_array: Array = [
		{"key": "code", "value": str(new_lobby.get("code", ""))},
		{"key": "name", "value": str(new_lobby.get("name", ""))},
		{"key": "settings", "value": JSON.stringify(new_lobby.get("settings", {}))},
		{"key": "host_id", "value": next_host},
		{"key": "status", "value": str(new_lobby.get("status", ""))},
		{"key": "started_at", "value": str(new_lobby.get("started_at", ""))},
		{"key": "winner_id", "value": str(new_lobby.get("winner_id", ""))},
		{"key": "heartbeat", "value": str(int(Time.get_unix_time_from_system()))},
		{"key": "protocol_version", "value": PROTOCOL_VERSION},
		{"key": "roster", "value": JSON.stringify(new_roster)},
	]
	for attempt in range(2):
		if _channel_id != leaving_id or leaving_id <= 0:
			return
		var res: Variant = await Talo.channels.client.make_request(
				HTTPClient.METHOD_PUT, "/%s" % leaving_id,
				{"ownerAliasId": int(next_host), "props": prop_array})
		if _channel_id != leaving_id:
			return
		var status_code := int((res as Dictionary).get("status", 0)) if res is Dictionary else -1
		if status_code == 200:
			# Broadcast the new host only AFTER Talo commits ownerAliasId, so
			# guests never switch to a host whose channel PUTs fail with 403.
			_broadcast_state(new_lobby, new_roster)
			return
		if attempt == 0:
			continue  # one retry for transient failures
		var err_status := str((res as Dictionary).get("status", "?")) if res is Dictionary else "null"
		backend_error.emit(
				"Host hand-off failed (%s) — the lobby may be abandoned" % err_status)


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


## Single-writer queue for channel-prop writes. The heartbeat and the
## match-writers (kills, joins, readies) all funnel through here: requests made
## while a write is in flight coalesce into one follow-up write carrying the
## newest snapshot, so a stale heartbeat can never land after a fresher roster
## and roll the server state back. (_prop_gen keeps response freshness local;
## this lock is what orders the wire.)
func _apply_props(extra: Dictionary = {}) -> void:
	for k in extra.keys():
		_apply_extra[k] = extra[k]
	_apply_dirty = true
	if _apply_inflight:
		await _apply_drained
		return
	_apply_inflight = true
	while _apply_dirty:
		_apply_dirty = false
		var payload_extra := _apply_extra
		_apply_extra = {}
		await _write_props(payload_extra)
	_apply_inflight = false
	_apply_drained.emit()


func _write_props(extra: Dictionary) -> void:
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
		"heartbeat": str(int(Time.get_unix_time_from_system())),
		"protocol_version": PROTOCOL_VERSION,
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
	if gen != _prop_gen or _channel_id <= 0:
		return  # a newer write or leave_lobby_channel() superseded this one
	var code := int((res as Dictionary).get("status", 0)) if res is Dictionary else -1
	if code == 200:
		var body: Dictionary = (res as Dictionary).get("body", {}) as Dictionary
		if body.has("channel"):
			_channel = TaloChannel.new(body["channel"])
	else:
		var status_str := str((res as Dictionary).get("status", "?")) if res is Dictionary else "null"
		backend_error.emit("Talo channel update failed: %s" % status_str)


func _emit_state() -> void:
	postgres_change.emit({"table": "lobbies", "type": "UPDATE", "record": _lobby.duplicate(true)})


func _emit_roster() -> void:
	var records: Dictionary = {}
	for uid in _roster.keys():
		var row: Dictionary = (_roster[uid] as Dictionary).duplicate(true)
		row["user_id"] = str(uid)
		records[str(uid)] = row
	postgres_change.emit({"table": "lobby_players", "type": "SYNC", "records": records})


# ------------------------------------------------------------------ match ops ---

func _is_host() -> bool:
	return str(_lobby.get("host_id", "")) == user_id


func _start_match() -> Dictionary:
	if not _is_host():
		return {}
	_lobby["status"] = "playing"
	_lobby["started_at"] = _now_iso()
	await _apply_props()
	_broadcast_state(_lobby, _roster)
	return _lobby.duplicate(true)


func _set_settings(args: Dictionary) -> Dictionary:
	if not _is_host():
		return {}
	_lobby["settings"] = (args.get("p_settings", {}) as Dictionary).duplicate(true)
	await _apply_props()
	_broadcast_state(_lobby, _roster)
	return _lobby.duplicate(true)


func _set_ready(args: Dictionary) -> Dictionary:
	var ready := bool(args.get("p_ready", false))
	if _is_host():
		var row: Dictionary = _roster.get(user_id, {})
		row["is_ready"] = ready
		_roster[user_id] = row
		await _apply_props()
		_emit_roster()
		_broadcast_state(_lobby, _roster)
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
	# host rate limit: one scored kill per second per killer, max 20 a minute.
	# kill claims carry a forgeable token (clients mint their own); rate is the
	# server-side lever we actually have.
	var now_s := Time.get_ticks_msec() / 1000.0
	var last := float(_kill_cooldowns.get(killer, -10.0))
	var colon := token.find(":")
	var base_tok := token.substr(0, colon) if colon > 0 else token
	var is_sub_tok := colon > 0
	var burst_ok := false
	if is_sub_tok and _kill_last_base.has(killer):
		var prev_b: Dictionary = _kill_last_base[killer] as Dictionary
		# Same-shot AOE / twin-barrel / chained-drum multi-kills (derived "<base>:<suffix>")
		# may score up to 4 unique victims within 0.6 s while still consuming unique
		# sub-tokens & enforcing the 20/min sliding cap.
		if str(prev_b.get("base", "")) == base_tok and (now_s - float(prev_b.get("at", -10.0))) < 0.6 and int(prev_b.get("count", 0)) < 4:
			burst_ok = true
	if now_s - last < 1.0 and not burst_ok:
		return {"ok": false, "reason": "rate_limited"}
	var arr: Array = _kill_window.get(killer, [])
	var kept: Array = []
	for t in arr:
		if now_s - float(t) < 60.0:
			kept.append(t)
	if kept.size() >= 20:
		return {"ok": false, "reason": "rate_limited"}
	kept.append(now_s)
	_kill_cooldowns[killer] = now_s
	if burst_ok:
		var pb: Dictionary = _kill_last_base[killer] as Dictionary
		pb["count"] = int(pb.get("count", 1)) + 1
		_kill_last_base[killer] = pb
	else:
		_kill_last_base[killer] = {"base": base_tok, "count": 1, "at": now_s}
	_kill_window[killer] = kept
	_record_used_token(token)
	var s_dict := _lobby.get("settings", {}) as Dictionary
	var gmode := str(s_dict.get("game_mode", "battle_royale"))
	var row: Dictionary = _roster.get(killer, {})
	var kills := int(row.get("kills", int(row.get("score", 0)) if gmode != "death_race" else 0)) + 1
	row["kills"] = kills
	# In Death Race, row["score"] tracks completed laps only — kills must NEVER
	# collide with lap progress or allow 2 kills + 1 lap to finish a 3-lap race.
	var score := int(row.get("score", 0))
	if gmode != "death_race":
		score = kills
		row["score"] = score
	_roster[killer] = row
	if target != "":
		var victim: Dictionary = _roster.get(target, {})
		# respawn_at is a FUTURE deadline: MatchState.is_respawning() treats it
		# as one. Storing the kill time made those readers always report false.
		victim["respawn_at"] = _now_iso_from_now(Match.respawn_delay())
		_roster[target] = victim
	var status := str(_lobby.get("status", "waiting"))
	var winner := ""
	var target_kills := maxi(1, int(s_dict.get("kill_target", 10)))
	if gmode != "death_race" and score >= target_kills:
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
	_broadcast_state(_lobby, _roster)
	return {"ok": true, "score": score, "kills": kills,
			"lobby_status": status,
			"winner_id": winner}


func _register_lap(args: Dictionary) -> Dictionary:
	var token := str(args.get("p_token", ""))
	var racer := str(args.get("p_racer", user_id))
	if token == "" or racer == "":
		return {}
	var s_dict := _lobby.get("settings", {}) as Dictionary
	if str(s_dict.get("game_mode", "battle_royale")) != "death_race":
		return {"ok": false, "reason": "wrong_mode"}
	if _used_tokens.has(token):
		return {"ok": false, "reason": "token_consumed"}
	if str(_lobby.get("status", "")) != "playing":
		return {"ok": false, "reason": "lobby_not_playing"}
	var now_s := Time.get_ticks_msec() / 1000.0
	var last_lap := float(_lap_timestamps.get(racer, -MIN_LAP_SECONDS))
	if now_s - last_lap < MIN_LAP_SECONDS:
		return {"ok": false, "reason": "rate_limited"}
	if not _is_host():
		_lap_timestamps[racer] = now_s
		_record_used_token(token)
		_send("lap_request", {"racer": racer, "token": token})
		return {"ok": true, "pending": true,
				"lobby_status": str(_lobby.get("status", "")),
				"winner_id": str(_lobby.get("winner_id", ""))}
	if not _roster.has(racer):
		return {"ok": false, "reason": "not_in_lobby"}
	_lap_timestamps[racer] = now_s
	_record_used_token(token)
	var row: Dictionary = _roster.get(racer, {})
	var laps := int(row.get("laps", 0)) + 1
	row["laps"] = laps
	row["score"] = laps
	_roster[racer] = row
	var status := str(_lobby.get("status", "waiting"))
	var winner := ""
	var target_laps := maxi(1, int(s_dict.get("lap_target", 3)))
	if laps >= target_laps:
		status = "finished"
		winner = racer
		_lobby["status"] = status
		_lobby["winner_id"] = winner
	await _apply_props()
	_emit_roster()
	_emit_state()
	_broadcast_state(_lobby, _roster)
	return {"ok": true, "score": laps, "laps": laps,
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
	var uids := _roster.keys()
	uids.sort()  # deterministic tie-break: lowest user_id wins a score tie
	for uid in uids:
		var s := int((_roster[uid] as Dictionary).get("score", 0))
		if s > best_score:
			best = str(uid)
			best_score = s
	_lobby["status"] = "finished"
	_lobby["winner_id"] = best
	await _apply_props()
	_broadcast_state(_lobby, _roster)
	return _lobby.duplicate(true)


# ------------------------------------------------------------------ socket in ---

func _record_used_token(token: String) -> void:
	_used_tokens[token] = true
	while _used_tokens.size() > MAX_USED_TOKENS:
		# Dictionary preserves insertion order: drop the oldest consumed token.
		_used_tokens.erase(_used_tokens.keys()[0])


func _broadcast_state(lobby_dict: Dictionary = _lobby, roster_dict: Dictionary = _roster) -> void:
	_state_seq += 1
	_send("state", {"seq": _state_seq, "lobby": lobby_dict, "roster": roster_dict})


func _send(kind: String, payload: Dictionary) -> void:
	# Offline-safe: offline tests stage _channel_id = 1, _channel = null.
	if _channel_id <= 0 or _channel == null:
		return
	Talo.channels.send_message(_channel_id, JSON.stringify({"k": kind, "p": payload}))


func _on_socket_message(res: String, data: Dictionary) -> void:
	if res == "v1.players.identify.success":
		if not is_ready:
			if Talo != null and Talo.current_alias != null:
				user_id = str(Talo.current_alias.id)
			elif user_id == "":
				var pa: Variant = data.get("playerAlias", null)
				if pa is Dictionary and int((pa as Dictionary).get("id", -1)) > 0:
					user_id = str(int((pa as Dictionary).get("id", -1)))
			if user_id != "":
				_promote_online()
		return
	if res != "v1.channels.message":
		return
	if _channel_id <= 0:
		return
	_reconnect_attempts = 0
	var ch = data.get("channel", null)
	if ch is Dictionary and int((ch as Dictionary).get("id", _channel_id)) != _channel_id:
		return
	var alias = data.get("playerAlias", null)
	# Talo stamps every socket message with the sending alias; use an integer
	# string so JSON floats (e.g. 12345678.0) match str(Talo.current_alias.id).
	var sender_id := ""
	if alias is Dictionary:
		var alias_id := int((alias as Dictionary).get("id", -1))
		if alias_id <= 0:
			return
		sender_id = str(alias_id)
	if sender_id == "":
		return
	var raw := str(data.get("message", ""))
	var json := JSON.new()
	if json.parse(raw) != OK or not (json.get_data() is Dictionary):
		return
	var msg: Dictionary = json.get_data()
	var kind := str(msg.get("k", ""))
	var payload: Variant = msg.get("p", {})
	match kind:
		"state":
			# Authoritative state is host-owned. Without this alias check any
			# guest could forge the scoreboard / winner on every peer (the
			# kill_request and ready_request branches already validate sender).
			if sender_id == "" or sender_id != str(_lobby.get("host_id", "")):
				return
			_host_ack = true
			if _is_host() and sender_id == user_id:
				return
			if payload is Dictionary:
				var p := payload as Dictionary
				var seq := int(p.get("seq", -1))
				if seq >= 0:
					if seq <= _last_state_seq:
						return
					_last_state_seq = seq
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
				if sender_id == "" or uid != sender_id:
					# the alias stamp and the claimed identity must agree —
					# otherwise any member could forge or erase another's row
					return
				if kind == "join":
					if _roster.size() >= 8 and not _roster.has(uid):
						return  # full lobby; no unbounded growth
					var prev: Dictionary = {}
					if _roster.has(uid) and _roster[uid] is Dictionary:
						prev = _roster[uid] as Dictionary
					var col := str(p.get("color", "#40c8ff"))
					if not _is_hex_color(col):
						col = "#40c8ff"
					# Allowlist: join rows carry ONLY the keys below, so forged
					# frames cannot inject arbitrary lobby state; prior score/kills/
					# laps/readiness are re-seeded from trusted roster state.
					var raw_veh := str(p.get("vehicle", prev.get("vehicle", ""))) if p.has("vehicle") else str(prev.get("vehicle", ""))
					var row: Dictionary = {
						"user_id": uid,
						"display_name": str(p.get("display_name", "RIDER")).substr(0, 32),
						"color": col,
						"vehicle": VehicleRegistry.sanitize_preference(raw_veh),
						"score": int(prev.get("score", 0)),
						"kills": int(prev.get("kills", 0)),
						"laps": int(prev.get("laps", 0)),
						"is_ready": bool(prev.get("is_ready", false)),
						"respawn_at": str(prev.get("respawn_at", "")),
					}
					_roster[uid] = row
				else:
					_roster.erase(uid)
					# The host is gone mid-match or in waiting lobby: void cleanly now
					# instead of waiting up to ~105 s for the heartbeat poll to notice.
					var st := str(_lobby.get("status", ""))
					if not _host_lost_emitted and uid == str(_lobby.get("host_id", "")) \
							and (st == "playing" or st == "waiting"):
						_host_lost_emitted = true
						connection_state.emit("host_lost")
						host_lost.emit()
				_emit_roster()
				if _is_host():
					await _apply_props()
					_broadcast_state(_lobby, _roster)
		"ready_request":
			if _is_host() and payload is Dictionary:
				var p := payload as Dictionary
				var uid := str(p.get("user_id", ""))
				if uid == "" or not _roster.has(uid):
					return
				if sender_id == "" or sender_id != uid:
					return
				var row: Dictionary = _roster[uid]
				row["is_ready"] = bool(p.get("ready", false))
				_roster[uid] = row
				await _apply_props()
				_emit_roster()
				_broadcast_state(_lobby, _roster)
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
		"lap_request":
			if _is_host() and payload is Dictionary:
				var p := payload as Dictionary
				var racer := str(p.get("racer", ""))
				var token := str(p.get("token", ""))
				if sender_id == "" or racer != sender_id:
					return
				if token == "" or _used_tokens.has(token):
					return
				await _register_lap({"p_racer": racer, "p_token": token})
		"kill":
			if payload is Dictionary:
				var p := payload as Dictionary
				var victim := str(p.get("victim", ""))
				if victim == "" or sender_id == "" or victim != sender_id:
					return
				broadcast_received.emit("kill", payload)
		"hurt":
			# Victim-authoritative damage telemetry for the damage-number UI.
			# Backwards compatible with PROTOCOL_VERSION "2": peers on older
			# builds simply ignore the unknown kind.
			if payload is Dictionary:
				var p := payload as Dictionary
				var victim := str(p.get("victim", ""))
				var dmg := int(p.get("dmg", 0))
				if victim == "" or sender_id == "" or victim != sender_id:
					return
				if dmg < 1 or dmg > 500:
					return
				if not _hurt_rate_ok(sender_id):
					return
				broadcast_received.emit("hurt", payload)
		"bike_state":
			if payload is Dictionary:
				var p := payload as Dictionary
				var uid := str(p.get("id", ""))
				if uid == "" or sender_id == "" or uid != sender_id:
					return
				broadcast_received.emit("state", payload)
		"shot":
			if payload is Dictionary:
				var p := payload as Dictionary
				var oid := str(p.get("id", ""))
				if oid == "" or sender_id == "" or oid != sender_id:
					return
				broadcast_received.emit("shot", payload)
		"lobby_update":
			if sender_id == "" or sender_id != str(_lobby.get("host_id", "")):
				return
			broadcast_received.emit("lobby_update", payload)


# ------------------------------------------------------------------ helpers ---

func _hurt_rate_ok(sender_id: String) -> bool:
	## Per-sender 24/s cap on damage telemetry. Twin-barrel rapid fire can
	## legitimately produce bursts; this only stops a forged flood.
	var now := Time.get_ticks_msec() / 1000.0
	var window: Array = _hurt_log.get(sender_id, [])
	var kept: Array = []
	for t in window:
		if now - float(t) < 1.0:
			kept.append(t)
	if kept.size() >= 24:
		_hurt_log[sender_id] = kept
		return false
	kept.append(now)
	_hurt_log[sender_id] = kept
	return true

func _parse_dict(text: String) -> Dictionary:
	return _parse_dict_static(text)


static func _parse_dict_static(text: String) -> Dictionary:
	if text.is_empty():
		return {}
	var json := JSON.new()
	if json.parse(text) != OK or not (json.get_data() is Dictionary):
		return {}
	return json.get_data() as Dictionary


func _now_iso() -> String:
	return KT.now_iso()


func _now_iso_from_now(seconds: float) -> String:
	## ISO deadline `seconds` in the future, formatted to match _now_iso().
	return KT.iso_from_now(seconds)


func _iso_from_unix(unix: float) -> String:
	return KT.iso_from_unix(unix)


func _parse_iso(value: String) -> float:
	return KT.parse_iso(value)


static func _parse_iso_static(value: String) -> float:
	return KT.parse_iso(value)


func _token() -> String:
	return "%d-%d" % [Time.get_ticks_usec(), randi()]


func _is_hex_color(col: String) -> bool:
	if col.length() != 7 or col[0] != "#":
		return false
	for i in range(1, 7):
		var c := col.substr(i, 1)
		var ok := (c >= "0" and c <= "9") or (c >= "a" and c <= "f") or (c >= "A" and c <= "F")
		if not ok:
			return false
	return true
