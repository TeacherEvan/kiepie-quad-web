extends Control
## Front door of the Kiepie Quad arena (built by tools/build_menus.gd).
## Node names referenced below are the scene contract; see the report for the tree.

const SCENE_TEST_RIDE := "res://scenes/TestRide.tscn"
const SCENE_DEATH_RACE := "res://scenes/DeathRace.tscn"
const SCENE_LOBBY := "res://scenes/LobbyMenu.tscn"
const SCENE_SETTINGS := "res://scenes/SettingsMenu.tscn"
const SCENE_ARENA := "res://scenes/Arena.tscn"

const UI := preload("res://src/ui/UiTheme.gd")
const MOBILE_INPUT := preload("res://src/ui/MobileTextInput.gd")
const COL_OK := UI.OK
const COL_WARN := UI.WARN
const COL_INFO := UI.INFO
const VEHICLE_IDS := VehicleRegistry.ALL_IDS

## Selected Dashboard game mode: "battle_royale" (default) | "death_race"
static var selected_game_mode := "battle_royale"

@onready var _safe: MarginContainer = $SafeMargin
@onready var _scroll: ScrollContainer = get_node_or_null("SafeMargin/Scroll")
@onready var _status: Label = $SafeMargin/Scroll/ScrollBox/Card/VBox/Status
@onready var _btn_retry: Button = get_node_or_null("SafeMargin/Scroll/ScrollBox/Card/VBox/BtnRetry")
@onready var _code: LineEdit = $SafeMargin/Scroll/ScrollBox/Card/VBox/JoinRow/CodeField
@onready var _btn_mode_br: Button = get_node_or_null("SafeMargin/Scroll/ScrollBox/Card/VBox/ModeRow/BtnModeBattleRoyale")
@onready var _btn_mode_dr: Button = get_node_or_null("SafeMargin/Scroll/ScrollBox/Card/VBox/ModeRow/BtnModeDeathRace")
@onready var _vehicle_select: OptionButton = get_node_or_null("SafeMargin/Scroll/ScrollBox/Card/VBox/VehicleRow/VehicleSelect")
@onready var _btn_practice: Button = $SafeMargin/Scroll/ScrollBox/Card/VBox/BtnPractice
@onready var _btn_create: Button = $SafeMargin/Scroll/ScrollBox/Card/VBox/BtnCreate
@onready var _btn_join_auto: Button = $SafeMargin/Scroll/ScrollBox/Card/VBox/BtnJoinAuto
@onready var _btn_join_code: Button = $SafeMargin/Scroll/ScrollBox/Card/VBox/JoinRow/BtnJoinCode
@onready var _btn_settings: Button = $SafeMargin/Scroll/ScrollBox/Card/VBox/BtnSettings

var _busy := false
var _card_style: StyleBoxFlat = null
var _pill_cache: Dictionary = {}


func _ready() -> void:
	Settings.call_deferred("sync_back_handler")
	if _scroll != null:
		UI.style_scroll(_scroll)
	_apply_safe_area(_safe)
	get_viewport().size_changed.connect(_on_viewport_resized)
	if _btn_mode_br != null:
		_btn_mode_br.pressed.connect(func() -> void:
			Sfx.play_ui("ui_click")
			select_game_mode("battle_royale"))
	if _btn_mode_dr != null:
		_btn_mode_dr.pressed.connect(func() -> void:
			Sfx.play_ui("ui_click")
			select_game_mode("death_race"))
	if _vehicle_select != null:
		var saved_v := str(Settings.get_value("gameplay", "vehicle", "auto"))
		var v_idx := VEHICLE_IDS.find(saved_v)
		_vehicle_select.selected = v_idx if v_idx >= 0 else 0
		_vehicle_select.item_selected.connect(func(i: int) -> void:
			Sfx.play_ui("ui_click")
			var vid: String = VEHICLE_IDS[clampi(i, 0, VEHICLE_IDS.size() - 1)]
			Settings.set_value("gameplay", "vehicle", vid))
	_btn_practice.pressed.connect(_on_practice)
	_btn_create.pressed.connect(_on_create)
	_btn_join_auto.pressed.connect(_on_join_auto)
	_btn_join_code.pressed.connect(_on_join_code)
	_btn_settings.pressed.connect(_on_settings)
	if _btn_retry != null:
		_btn_retry.pressed.connect(_on_retry)
	_code.text_submitted.connect(_on_join_code)
	_sync_mode_ui()
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
	elif not Supabase.is_connecting():
		var err_msg := str(Supabase.last_auth_error).strip_edges()
		_set_status(("Offline · %s" % err_msg) if err_msg != "" else "Offline · check connection and retry", COL_WARN)
		if _btn_retry != null:
			_btn_retry.visible = true
	else:
		_set_status("Connecting to backend…", COL_INFO)


func _exit_tree() -> void:
	if Supabase != null and Supabase.auth_status.is_connected(_on_auth_status):
		Supabase.auth_status.disconnect(_on_auth_status)
	if Lobby != null and Lobby.error_message.is_connected(_on_error):
		Lobby.error_message.disconnect(_on_error)
	if Match != null and Match.error_message.is_connected(_on_error):
		Match.error_message.disconnect(_on_error)
	var vp := get_viewport()
	if vp != null and vp.size_changed.is_connected(_on_viewport_resized):
		vp.size_changed.disconnect(_on_viewport_resized)


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
	var vp := UI.apply_safe_area(self, margin, 14.0, 4.0, 4.0)
	_apply_responsive_layout(vp, margin)


func _apply_responsive_layout(vp: Vector2, _margin: MarginContainer = null) -> void:
	var short := vp.y <= 480.0
	var very_short := vp.y <= 420.0
	var narrow := vp.x <= 480.0

	var card := get_node_or_null("SafeMargin/Scroll/ScrollBox/Card") as PanelContainer
	if card != null:
		if _card_style == null:
			var ps := card.get_theme_stylebox("panel")
			if ps is StyleBoxFlat:
				_card_style = (ps as StyleBoxFlat).duplicate() as StyleBoxFlat
				card.add_theme_stylebox_override("panel", _card_style)
		if _card_style != null:
			_card_style.content_margin_left = 14.0 if narrow else 28.0
			_card_style.content_margin_right = 14.0 if narrow else 28.0
			_card_style.content_margin_top = 8.0 if very_short else (12.0 if short else 22.0)
			_card_style.content_margin_bottom = 8.0 if very_short else (12.0 if short else 22.0)
	var vbox := get_node_or_null("SafeMargin/Scroll/ScrollBox/Card/VBox") as VBoxContainer
	if vbox != null:
		vbox.add_theme_constant_override("separation", 6 if very_short else (8 if short else 12))
	var subtitle := get_node_or_null("SafeMargin/Scroll/ScrollBox/Card/VBox/Subtitle") as Control
	if subtitle != null:
		subtitle.visible = not short
	var footer := get_node_or_null("SafeMargin/Scroll/ScrollBox/Card/VBox/Footer") as Control
	if footer != null:
		footer.visible = true
	var title := get_node_or_null("SafeMargin/Scroll/ScrollBox/Card/VBox/Title") as Label
	if title != null and title.label_settings != null:
		title.label_settings.font_size = 22 if very_short else (26 if short else (30 if narrow else 38))
	if _status != null:
		_status.custom_minimum_size.y = 24.0 if very_short else (28.0 if short else 44.0)
	var btn_h := 44.0 if short else 52.0
	for btn in [_btn_mode_br, _btn_mode_dr, _vehicle_select, _btn_retry, _btn_practice, _btn_create, _btn_join_auto, _btn_join_code, _btn_settings]:
		if btn != null:
			btn.custom_minimum_size.y = btn_h
	if _btn_join_code != null:
		_btn_join_code.custom_minimum_size.x = 84.0 if narrow else 120.0
	if _code != null:
		_code.custom_minimum_size.y = 44.0 if short else 48.0
	_sync_mode_ui(narrow)


func select_game_mode(mode: String) -> void:
	selected_game_mode = "death_race" if mode == "death_race" else "battle_royale"
	_sync_mode_ui()


func _apply_mode_pill_style(btn: Button, active: bool, accent: Color, narrow: bool = get_viewport_rect().size.x <= 480.0) -> void:
	if btn == null:
		return
	var cache_key := "%s_%s_%s" % [btn.name, str(active), str(narrow)]
	if not _pill_cache.has(cache_key):
		UI.style_button(btn, accent if active else Color(0.32, 0.38, 0.48), 13 if narrow else 16, btn.custom_minimum_size.y)
		var styles := {}
		for st in ["normal", "hover", "focus"]:
			var sb := btn.get_theme_stylebox(st)
			if sb is StyleBoxFlat:
				var dup := (sb as StyleBoxFlat).duplicate() as StyleBoxFlat
				if active:
					dup.bg_color = Color(accent.r * 0.24, accent.g * 0.20, accent.b * 0.10, 0.96)
					dup.border_color = Color(accent.r, accent.g, accent.b, 0.98)
					dup.set_border_width_all(2)
				else:
					dup.bg_color = Color(0.055, 0.065, 0.085, 0.76)
					dup.border_color = Color(0.35, 0.40, 0.50, 0.35)
					dup.set_border_width_all(1)
				styles[st] = dup
		_pill_cache[cache_key] = styles
	var cached: Dictionary = _pill_cache[cache_key]
	for st in cached.keys():
		btn.add_theme_stylebox_override(st, cached[st])
	btn.add_theme_font_size_override("font_size", 13 if narrow else 16)
	btn.add_theme_color_override("font_color", UI.GOLD if active else UI.MUTED)


func _sync_mode_ui(narrow: bool = get_viewport_rect().size.x <= 480.0) -> void:
	var is_race := selected_game_mode == "death_race"
	if _btn_mode_br != null:
		_apply_mode_pill_style(_btn_mode_br, not is_race, UI.ACCENT, narrow)
		_btn_mode_br.text = "BATTLE ROYALE" if is_race else "• BATTLE ROYALE •"
	if _btn_mode_dr != null:
		_apply_mode_pill_style(_btn_mode_dr, is_race, UI.GOLD, narrow)
		_btn_mode_dr.text = "• DEATH RACE •" if is_race else "DEATH RACE"
	var subtitle := get_node_or_null("SafeMargin/Scroll/ScrollBox/Card/VBox/Subtitle") as Label
	if subtitle != null:
		subtitle.text = "DEATH RACE  ·  3 LAPS · LOOPS, PITS & FULL ARSENAL" if is_race else "BATTLE ROYALE  ·  ARENA COMBAT · ROCKETS & METEORS"
	if _btn_practice != null:
		_btn_practice.text = "PRACTICE (DEATH RACE TRACK)" if is_race else "PRACTICE (FREE RIDE)"


# --------------------------------------------------------------- actions ---

func _on_practice() -> void:
	Sfx.play_ui("ui_click")
	if selected_game_mode == "death_race":
		get_tree().change_scene_to_file(SCENE_DEATH_RACE)
	else:
		get_tree().change_scene_to_file(SCENE_TEST_RIDE)


func _prepare_lobby(mode: String, code: String) -> bool:
	## Single source of truth for the three LobbyMenu statics. All entry paths
	## (create, auto-join, join-by-code) must carry the selected game mode.
	var lobby_script = load("res://src/ui/LobbyMenu.gd")
	if lobby_script == null:
		_set_status("UI unavailable — lobby could not load", COL_WARN)
		return false
	lobby_script.pending_mode = mode
	lobby_script.pending_code = code
	lobby_script.pending_game_mode = selected_game_mode
	return true


func _on_create() -> void:
	Sfx.play_ui("ui_click")
	if _busy:
		return
	if not Supabase.is_ready:
		if _btn_retry != null:
			_btn_retry.visible = false
		_set_status("Reconnecting to backend…", COL_INFO)
		Supabase.reconnect()
		return
	# Static vars on the LobbyMenu script survive the scene change (no new autoload).
	if not _prepare_lobby("create", ""):
		return
	get_tree().change_scene_to_file(SCENE_LOBBY)


func _on_join_auto() -> void:
	Sfx.play_ui("ui_click")
	if _busy:
		return
	if not Supabase.is_ready:
		if _btn_retry != null:
			_btn_retry.visible = false
		_set_status("Reconnecting to backend…", COL_INFO)
		Supabase.reconnect()
		return
	# Joining lands in the lobby room: the host must start the match there.
	if not _prepare_lobby("join_auto", ""):
		return
	get_tree().change_scene_to_file(SCENE_LOBBY)


func _on_join_code(_text: String = "") -> void:
	Sfx.play_ui("ui_click")
	if _busy:
		return
	var code := _code.text.strip_edges()
	if code == "":
		_set_status("Enter a room code first.", COL_WARN)
		return
	if not Supabase.is_ready:
		if _btn_retry != null:
			_btn_retry.visible = false
		_set_status("Reconnecting to backend…", COL_INFO)
		Supabase.reconnect()
		return
	if not _prepare_lobby("join_code", code.to_upper()):
		return
	get_tree().change_scene_to_file(SCENE_LOBBY)


func _on_retry() -> void:
	Sfx.play_ui("ui_click")
	if _btn_retry != null:
		_btn_retry.visible = false
	_set_status("Reconnecting to backend…", COL_INFO)
	Supabase.reconnect()


func _on_settings() -> void:
	Sfx.play_ui("ui_click")
	get_tree().change_scene_to_file(SCENE_SETTINGS)


func _on_auth_status(ok: bool, message: String) -> void:
	if _btn_retry != null:
		_btn_retry.visible = not ok
	if ok:
		var label := "offline mock" if Supabase.use_mock else "online"
		_set_status("Ready · %s · %s" % [label, Settings.display_name()], COL_OK)
	else:
		_set_status("Offline · %s" % message, COL_WARN)


func _on_error(message: String) -> void:
	_set_busy(false, "")
	_set_status(message, COL_WARN)
