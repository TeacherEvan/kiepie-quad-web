extends Control
## Front door of the Kiepie Quad arena (built by tools/build_menus.gd).
## Node names referenced below are the scene contract; see the report for the tree.

const SCENE_TEST_RIDE := "res://scenes/TestRide.tscn"
const SCENE_LOBBY := "res://scenes/LobbyMenu.tscn"
const SCENE_SETTINGS := "res://scenes/SettingsMenu.tscn"
const SCENE_ARENA := "res://scenes/Arena.tscn"

const COL_OK := Color(0.55, 0.95, 0.70)
const COL_WARN := Color(1.0, 0.72, 0.34)
const COL_INFO := Color(0.72, 0.82, 0.96)

@onready var _safe: MarginContainer = $SafeMargin
@onready var _status: Label = $SafeMargin/Card/VBox/Status
@onready var _code: LineEdit = $SafeMargin/Card/VBox/JoinRow/CodeField
@onready var _btn_practice: Button = $SafeMargin/Card/VBox/BtnPractice
@onready var _btn_create: Button = $SafeMargin/Card/VBox/BtnCreate
@onready var _btn_join_auto: Button = $SafeMargin/Card/VBox/BtnJoinAuto
@onready var _btn_join_code: Button = $SafeMargin/Card/VBox/JoinRow/BtnJoinCode
@onready var _btn_settings: Button = $SafeMargin/Card/VBox/BtnSettings

var _busy := false


func _ready() -> void:
	_apply_safe_area(_safe)
	_btn_practice.pressed.connect(_on_practice)
	_btn_create.pressed.connect(_on_create)
	_btn_join_auto.pressed.connect(_on_join_auto)
	_btn_join_code.pressed.connect(_on_join_code)
	_btn_settings.pressed.connect(_on_settings)
	_code.text_submitted.connect(_on_join_code)
	Supabase.auth_status.connect(_on_auth_status)
	Lobby.error_message.connect(_on_error)
	Match.error_message.connect(_on_error)

	if Supabase.is_ready:
		var label := "offline mock" if Supabase.use_mock else "online"
		_set_status("Ready · %s · %s" % [label, Settings.display_name()], COL_OK)
	else:
		_set_status("Connecting to backend…", COL_INFO)


# ------------------------------------------------------------------ ui ---

func _set_status(text: String, color: Color) -> void:
	if _status == null:
		return
	_status.text = text
	_status.add_theme_color_override("font_color", color)


func _set_busy(busy: bool, message: String) -> void:
	_busy = busy
	_btn_join_auto.disabled = busy
	_btn_join_code.disabled = busy
	_btn_create.disabled = busy
	if message != "":
		_set_status(message, COL_INFO)


func _apply_safe_area(margin: MarginContainer) -> void:
	if not DisplayServer.has_method("get_display_safe_area"):
		return
	var vp := get_viewport_rect().size
	var win := DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		return
	var sa := DisplayServer.get_display_safe_area()
	var sx := vp.x / float(win.x)
	var sy := vp.y / float(win.y)
	var l := int(maxf(24.0, float(sa.position.x) * sx))
	var t := int(maxf(20.0, float(sa.position.y) * sy))
	var r := int(maxf(24.0, float(win.x - sa.end.x) * sx))
	# The Web shell paints a fixed hint strip along the bottom; keep clear of it.
	var b := int(maxf(56.0, float(win.y - sa.end.y) * sy))
	margin.set("theme_override_constants/margin_left", l)
	margin.set("theme_override_constants/margin_top", t)
	margin.set("theme_override_constants/margin_right", r)
	margin.set("theme_override_constants/margin_bottom", b)


# --------------------------------------------------------------- actions ---

func _on_practice() -> void:
	get_tree().change_scene_to_file(SCENE_TEST_RIDE)


func _on_create() -> void:
	if _busy:
		return
	if not Supabase.is_ready:
		_set_status("Still connecting to the backend…", COL_WARN)
		return
	# Static var on the LobbyMenu script survives the scene change (no new autoload).
	var lobby_script = load("res://src/ui/LobbyMenu.gd")
	if lobby_script:
		lobby_script.pending_mode = "create"
		lobby_script.pending_code = ""
	get_tree().change_scene_to_file(SCENE_LOBBY)


func _on_join_auto() -> void:
	if _busy:
		return
	if not Supabase.is_ready:
		_set_status("Still connecting to the backend…", COL_WARN)
		return
	# Joining lands in the lobby room: the host must start the match there.
	var lobby_script = load("res://src/ui/LobbyMenu.gd")
	if lobby_script:
		lobby_script.pending_mode = "join_auto"
		lobby_script.pending_code = ""
	get_tree().change_scene_to_file(SCENE_LOBBY)


func _on_join_code(_text: String = "") -> void:
	if _busy:
		return
	var code := _code.text.strip_edges()
	if code == "":
		_set_status("Enter a room code first.", COL_WARN)
		return
	if not Supabase.is_ready:
		_set_status("Still connecting to the backend…", COL_WARN)
		return
	var lobby_script = load("res://src/ui/LobbyMenu.gd")
	if lobby_script:
		lobby_script.pending_mode = "join_code"
		lobby_script.pending_code = code.to_upper()
	get_tree().change_scene_to_file(SCENE_LOBBY)


func _on_settings() -> void:
	get_tree().change_scene_to_file(SCENE_SETTINGS)


func _on_auth_status(ok: bool, message: String) -> void:
	if ok:
		var label := "offline mock" if Supabase.use_mock else "online"
		_set_status("Ready · %s · %s" % [label, Settings.display_name()], COL_OK)
	else:
		_set_status("Offline · %s" % message, COL_WARN)


func _on_error(message: String) -> void:
	_set_busy(false, "")
	_set_status(message, COL_WARN)
