extends Node
## Lobby entry points. Autoload name: Lobby.

signal joined(lobby_id: String)
signal left()
signal error_message(message: String)

var current_lobby_id := ""
var _session_gen := 0


func _ready() -> void:
	Supabase.auth_status.connect(_on_auth)


func _on_auth(ok: bool, message: String) -> void:
	if not ok:
		error_message.emit(message)


func _enter(result: Dictionary) -> bool:
	if result.is_empty():
		error_message.emit("Lobby request failed")
		return false
	var lobby: Dictionary = result.get("lobby", {})
	if lobby.is_empty():
		error_message.emit(str(result.get("message", "No lobby returned")))
		return false
	_session_gen += 1
	current_lobby_id = str(lobby.get("id", ""))
	Match.set_lobby(result)
	Supabase.join_lobby_channel(current_lobby_id)
	joined.emit(current_lobby_id)
	return true


func join_auto(game_mode: String = "battle_royale") -> bool:
	var res: Dictionary = await Supabase.call_rpc("join_auto", {
		"p_display_name": Settings.display_name(),
		"p_color": Settings.player_color(),
		"p_game_mode": game_mode,
	})
	return _enter(res)


func join_by_code(code: String) -> bool:
	var res: Dictionary = await Supabase.call_rpc("join_by_code", {
		"p_code": code.strip_edges().to_upper(),
		"p_display_name": Settings.display_name(),
		"p_color": Settings.player_color(),
	})
	return _enter(res)


func create_lobby(name: String, settings: Dictionary) -> bool:
	var res: Dictionary = await Supabase.call_rpc("create_lobby", {
		"p_name": name.strip_edges().substr(0, 32),
		"p_settings": settings,
		"p_display_name": Settings.display_name(),
		"p_color": Settings.player_color(),
	})
	return _enter(res)


func leave() -> void:
	if current_lobby_id == "":
		return
	_session_gen += 1
	var gen := _session_gen
	# Synchronous reset: a Leave→Create race must never see stale Match.lobby
	# or stale Match._settings_cache, and LobbyMenu double-leave is a no-op.
	Match.clear_lobby()
	current_lobby_id = ""
	await Supabase.call_rpc("leave_lobby", {})
	if gen != _session_gen:
		return  # user already joined a new lobby — TaloBackend._leave_lobby
		# aborts the stale-room cleanup on a channel-id mismatch, and Match
		# state is already owned by the new lobby via LobbyService._enter.
	Supabase.leave_lobby_channel()
	left.emit()
