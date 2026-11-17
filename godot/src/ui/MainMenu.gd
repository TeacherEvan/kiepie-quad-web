extends Control
## Front door of the Kiepie Quad arena (built by tools/build_menus.gd).
## Node names referenced below are the scene contract; see the report for the tree.

const SCENE_TEST_RIDE := "res://scenes/TestRide.tscn"
const SCENE_LOBBY := "res://scenes/LobbyMenu.tscn"
const SCENE_SETTINGS := "res://scenes/SettingsMenu.tscn"
const SCENE_ARENA := "res://scenes/Arena.tscn"

const UI := preload("res://src/ui/UiTheme.gd")
const MOBILE_INPUT := preload("res://src/ui/MobileTextInput.gd")
const COL_OK := UI.OK
const COL_WARN := UI.WARN
const COL_INFO := UI.INFO

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
	get_viewport().size_changed.connect(_on_viewport_resized)
	_btn_practice.pressed.connect(_on_practice)
	_btn_create.pressed.connect(_on_create)
	_btn_join_auto.pressed.connect(_on_join_auto)
	_btn_join_code.pressed.connect(_on_join_code)
	_btn_settings.pressed.connect(_on_settings)
	_code.text_submitted.connect(_on_join_code)
	MOBILE_INPUT.attach(_code, {
		"title": "ROOM CODE",
		"placeholder": "ROOM CODE",
		"submit_label": "JOIN",
		"enter_key_hint": "go",
		"uppercase": true,
		"commit_on_close": false,
	})
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


func _on_viewport_resized() -> void:
	_apply_safe_area(_safe)


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
	var short := vp.y <= 480.0
	var min_lr := 12.0 if vp.x <= 480.0 else 24.0
	var min_t := 6.0 if short else 14.0
	var min_b := 6.0 if short else (16.0 if vp.x < 720.0 else 56.0)
	var l := int(maxf(min_lr, float(sa.position.x) * sx))
	var t := int(maxf(min_t, float(sa.position.y) * sy))
	var r := int(maxf(min_lr, float(win.x - sa.end.x) * sx))
	# The Web shell paints a fixed hint strip along the bottom on wide desktop; keep clear of it.
	var b := int(maxf(min_b, float(win.y - sa.end.y) * sy))
	margin.set("theme_override_constants/margin_left", l)
	margin.set("theme_override_constants/margin_top", t)
	margin.set("theme_override_constants/margin_right", r)
	margin.set("theme_override_constants/margin_bottom", b)

	var card := get_node_or_null("SafeMargin/Card") as PanelContainer
	if card != null:
		var ps := card.get_theme_stylebox("panel")
		if ps != null:
			ps.content_margin_top = 10.0 if short else 22.0
			ps.content_margin_bottom = 10.0 if short else 22.0
	var vbox := get_node_or_null("SafeMargin/Card/VBox") as VBoxContainer
	if vbox != null:
		vbox.add_theme_constant_override("separation", 5 if short else 12)
	var subtitle := get_node_or_null("SafeMargin/Card/VBox/Subtitle") as Control
	if subtitle != null:
		subtitle.visible = not short
	var footer := get_node_or_null("SafeMargin/Card/VBox/Footer") as Control
	if footer != null:
		footer.visible = not short
	var title := get_node_or_null("SafeMargin/Card/VBox/Title") as Label
	if title != null and title.label_settings != null:
		title.label_settings.font_size = 26 if short else 38
	if _status != null:
		_status.custom_minimum_size.y = 24.0 if short else 44.0
	var btn_h := 44.0 if short else 52.0
	for btn in [_btn_practice, _btn_create, _btn_join_auto, _btn_join_code, _btn_settings]:
		if btn != null:
			btn.custom_minimum_size.y = btn_h
	if _code != null:
		_code.custom_minimum_size.y = 44.0 if short else 48.0


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
