extends Node
## Autoload facade over the live Talo backend, or MockBackend for offline gates.
## Game code only talks to this singleton, so no caller changes are needed.

signal auth_status(ok: bool, message: String)
signal connection_state(state: String)
signal broadcast_received(event: String, payload: Variant)
signal postgres_change(data: Dictionary)
signal backend_error(message: String)

const MOCK_SCRIPT := preload("res://src/net/MockBackend.gd")
const TALO_PATH := "res://src/net/TaloBackend.gd"

var use_mock := false
var mock: Node
var talo: Node
var user_id := ""
var is_ready := false

var _lobby_id := ""


func _ready() -> void:
	var force_mock := OS.get_environment("KIEPIE_MOCK_BACKEND") == "1"
	var key := ""
	if Talo != null and Talo.settings != null:
		key = str(Talo.settings.get_value("", "access_key", ""))
	if force_mock or not key.begins_with("eyJ"):
		use_mock = true
		mock = MOCK_SCRIPT.new()
		mock.name = "MockBackend"
		add_child(mock)
		mock.broadcast_received.connect(_on_broadcast)
		mock.postgres_change.connect(_on_pg_change)
		mock.backend_error.connect(backend_error.emit)
		user_id = "mock-host"
		is_ready = true
		auth_status.emit(true, "offline mock backend")
		return

	var talo_script: GDScript = load(TALO_PATH) as GDScript
	talo = talo_script.new()
	talo.name = "TaloBackend"
	add_child(talo)
	talo.auth_status.connect(_on_talo_auth)
	talo.connection_state.connect(connection_state.emit)
	talo.broadcast_received.connect(_on_broadcast)
	talo.postgres_change.connect(_on_pg_change)
	talo.backend_error.connect(backend_error.emit)
	talo.start()


func _on_talo_auth(ok: bool, message: String) -> void:
	is_ready = ok
	if ok:
		user_id = str(talo.user_id)
	auth_status.emit(ok, message)


func call_rpc(name: String, args: Dictionary = {}) -> Dictionary:
	if use_mock:
		return await mock.call_rpc(name, args)
	if talo == null:
		backend_error.emit("Backend not configured")
		return {}
	return await talo.call_rpc(name, args)


func join_lobby_channel(lobby_id: String) -> void:
	_lobby_id = lobby_id
	if use_mock or talo == null:
		return
	talo.join_lobby_channel(lobby_id)


func leave_lobby_channel() -> void:
	_lobby_id = ""
	if use_mock or talo == null:
		return
	talo.leave_lobby_channel()


func broadcast(event: String, payload: Dictionary) -> void:
	if use_mock:
		mock.broadcast(event, payload)
	elif talo != null:
		talo.broadcast(event, payload)


func _on_broadcast(event: String, payload: Variant) -> void:
	broadcast_received.emit(event, payload)


func _on_pg_change(data: Dictionary) -> void:
	postgres_change.emit(data)
