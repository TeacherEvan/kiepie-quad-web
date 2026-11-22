extends Control
## Lobby room screen (built by tools/build_menus.gd).
## Entry mode is passed in via the static vars below by MainMenu.gd before the
## scene change; a fresh LobbyMenu instance consumes and clears them in _ready().

static var pending_mode: String = ""   # "" | "create" | "join_auto" | "join_code"
static var pending_code: String = ""
static var pending_game_mode: String = "battle_royale"

const SCENE_MAIN := "res://scenes/MainMenu.tscn"
const SCENE_ARENA := "res://scenes/Arena.tscn"
const SCENE_DEATH_RACE := "res://scenes/DeathRace.tscn"
const UI := preload("res://src/ui/UiTheme.gd")

const GAME_MODES := ["battle_royale", "death_race"]
const LAP_TARGETS := [2, 3, 5]
const KILL_TARGETS := [3, 5, 10, 15, 20]
const MAX_PLAYERS := [2, 3, 4, 5, 6, 7, 8]
const RESPAWNS := [1.0, 2.0, 2.5, 3.0, 4.0, 5.0]
const MATCH_SECONDS := [0, 180, 300, 600]
const DAMAGES := [20, 30, 40, 50]

const DEFAULT_SETTINGS := {
	"game_mode": "battle_royale",
	"lap_target": 3,
	"kill_target": 10,
	"max_players": 8,
	"respawn_delay": 2.5,
	"match_seconds": 0,
	"damage": 30,
	"pickups": true,
	"friendly_fire": false,
}

const COL_OK := UI.OK
const COL_WARN := UI.WARN
const COL_INFO := UI.INFO

@onready var _safe: MarginContainer = $SafeMargin
@onready var _status: Label = $SafeMargin/Scroll/VBox/Status
@onready var _code_field: LineEdit = $SafeMargin/Scroll/VBox/CodeRow/CodeField
@onready var _players_label: Label = $SafeMargin/Scroll/VBox/PlayersLabel
@onready var _player_list: VBoxContainer = $SafeMargin/Scroll/VBox/PlayerList
@onready var _host_panel: VBoxContainer = $SafeMargin/Scroll/VBox/HostPanel
@onready var _btn_ready: Button = $SafeMargin/Scroll/VBox/BtnReady
@onready var _btn_start: Button = $SafeMargin/Scroll/VBox/HostPanel/BtnStart
@onready var _btn_leave: Button = $SafeMargin/Scroll/VBox/TopBar/BtnLeave
@onready var _game_mode: OptionButton = get_node_or_null("SafeMargin/Scroll/VBox/HostPanel/GameModeRow/GameMode")
@onready var _lap_target: OptionButton = get_node_or_null("SafeMargin/Scroll/VBox/HostPanel/LapTargetRow/LapTarget")
@onready var _kill_target: OptionButton = $SafeMargin/Scroll/VBox/HostPanel/KillTargetRow/KillTarget
@onready var _max_players: OptionButton = $SafeMargin/Scroll/VBox/HostPanel/MaxPlayersRow/MaxPlayers
@onready var _respawn: OptionButton = $SafeMargin/Scroll/VBox/HostPanel/RespawnRow/RespawnDelay
@onready var _match_seconds: OptionButton = $SafeMargin/Scroll/VBox/HostPanel/MatchSecondsRow/MatchSeconds
@onready var _damage: OptionButton = $SafeMargin/Scroll/VBox/HostPanel/DamageRow/Damage
@onready var _pickups: CheckBox = $SafeMargin/Scroll/VBox/HostPanel/PickupsRow/Pickups

var _ready_state := false
var _transitioning := false
var _auto_start_gen := 0


func _ready() -> void:
	add_to_group("back_handler")
	Settings.call_deferred("sync_back_handler")
	_apply_safe_area(_safe)
	get_viewport().size_changed.connect(_on_viewport_resized)
	UI.style_scroll($SafeMargin/Scroll)
	_connect_signals()
	var mode := pending_mode
	var code := pending_code
	var gmode := pending_game_mode if pending_game_mode != "" else "battle_royale"
	pending_mode = ""
	pending_code = ""
	pending_game_mode = "battle_royale"

	if Match.lobby.is_empty():
		match mode:
			"create":
				await _create_lobby(gmode)
			"join_code":
				await _join_code(code)
			"join_auto", "":
				await _join_auto(gmode)
	if not is_inside_tree():
		return
	_refresh_all()


# ------------------------------------------------------------------ wiring ---

func _connect_signals() -> void:
	_btn_leave.pressed.connect(_on_leave)
	$SafeMargin/Scroll/VBox/CodeRow/BtnCopy.pressed.connect(_on_copy)
	_btn_ready.pressed.connect(_on_ready_toggled)
	_btn_start.pressed.connect(_on_start)

	if _game_mode != null:
		_game_mode.item_selected.connect(func(_i): _push_settings())
	if _lap_target != null:
		_lap_target.item_selected.connect(func(_i): _push_settings())
	_kill_target.item_selected.connect(func(_i): _push_settings())
	_max_players.item_selected.connect(func(_i): _push_settings())
	_respawn.item_selected.connect(func(_i): _push_settings())
	_match_seconds.item_selected.connect(func(_i): _push_settings())
	_damage.item_selected.connect(func(_i): _push_settings())
	_pickups.toggled.connect(func(_v): _push_settings())

	Match.roster_changed.connect(_refresh_players)
	Match.score_updated.connect(_on_score_updated)
	Match.lobby_changed.connect(_on_lobby_changed)
	Match.match_started.connect(_on_match_started)
	Match.error_message.connect(_on_error)
	Lobby.error_message.connect(_on_error)
	Lobby.left.connect(_on_left_elsewhere)
	if Supabase != null and Supabase.has_signal("host_lost"):
		Supabase.host_lost.connect(_on_host_lost)


# ------------------------------------------------------------- lobby entry ---

func _create_lobby(gmode: String = "battle_royale") -> void:
	_set_status("Creating lobby…", COL_INFO)
	var init_settings := DEFAULT_SETTINGS.duplicate(true)
	init_settings["game_mode"] = "death_race" if gmode == "death_race" else "battle_royale"
	var ok: bool = await Lobby.create_lobby(Settings.display_name() + "'s Lobby", init_settings)
	if not is_inside_tree():
		return
	if not ok:
		_set_status("Could not create a lobby.", COL_WARN)


func _join_auto(gmode: String = "battle_royale") -> void:
	_set_status("Finding a lobby…", COL_INFO)
	var ok: bool = await Lobby.join_auto("death_race" if gmode == "death_race" else "battle_royale")
	if not is_inside_tree():
		return
	if not ok:
		_set_status("Auto-join failed — try the main menu.", COL_WARN)


func _join_code(code: String) -> void:
	if code.strip_edges() == "":
		_set_status("No room code supplied.", COL_WARN)
		return
	_set_status("Joining %s…" % code.to_upper(), COL_INFO)
	var ok: bool = await Lobby.join_by_code(code)
	if not is_inside_tree():
		return
	if not ok:
		_set_status("Could not join %s." % code.to_upper(), COL_WARN)


# ------------------------------------------------------------------- state ---

func _is_host() -> bool:
	var host := str(Match.lobby.get("host_id", ""))
	return host != "" and host == Match.my_user_id


func _set_status(text: String, color: Color) -> void:
	if _status == null:
		return
	_status.text = text
	_status.add_theme_color_override("font_color", color)


func _refresh_all() -> void:
	var code := str(Match.lobby.get("code", Lobby.current_lobby_id))
	_code_field.text = code
	_host_panel.visible = _is_host()
	_refresh_settings()
	_refresh_players()


func _refresh_status(board: Array) -> void:
	var code := str(Match.lobby.get("code", Lobby.current_lobby_id))
	var code_lbl := code if code != "" else "—"
	var ready_cnt := 0
	for entry in board:
		if bool((entry as Dictionary).get("is_ready", false)):
			ready_cnt += 1
	if Match.all_ready():
		_set_status("All %d riders ready — %s" % [
				board.size(),
				"starting match…" if _is_host() else "host starting…"], COL_OK)
	elif _is_host():
		_set_status("Room %s · HOST · %d/%d ready" % [code_lbl, ready_cnt, board.size()], COL_OK)
	else:
		_set_status("Room %s · RIDER · Waiting for host (%d/%d ready)" % [
				code_lbl, ready_cnt, board.size()], COL_INFO)


func _on_viewport_resized() -> void:
	_apply_safe_area(_safe)


func _on_score_updated(_user_id: String, _score: int) -> void:
	_refresh_players()


func _exit_tree() -> void:
	# Named handlers disconnect cleanly when the autoload/viewport outlives us;
	# inline lambdas pinned the freed menu in memory and kept firing on stale
	# nodes after scene changes.
	var vp := get_viewport()
	if vp != null and vp.size_changed.is_connected(_on_viewport_resized):
		vp.size_changed.disconnect(_on_viewport_resized)
	if Match != null:
		if Match.roster_changed.is_connected(_refresh_players):
			Match.roster_changed.disconnect(_refresh_players)
		if Match.score_updated.is_connected(_on_score_updated):
			Match.score_updated.disconnect(_on_score_updated)
		if Match.lobby_changed.is_connected(_on_lobby_changed):
			Match.lobby_changed.disconnect(_on_lobby_changed)
		if Match.match_started.is_connected(_on_match_started):
			Match.match_started.disconnect(_on_match_started)
		if Match.error_message.is_connected(_on_error):
			Match.error_message.disconnect(_on_error)
	if Lobby != null:
		if Lobby.error_message.is_connected(_on_error):
			Lobby.error_message.disconnect(_on_error)
		if Lobby.left.is_connected(_on_left_elsewhere):
			Lobby.left.disconnect(_on_left_elsewhere)
	if Supabase != null and Supabase.has_signal("host_lost") and Supabase.host_lost.is_connected(_on_host_lost):
		Supabase.host_lost.disconnect(_on_host_lost)


func _on_lobby_changed() -> void:
	_refresh_all()


func _on_error(message: String) -> void:
	_set_status(message, COL_WARN)


# ----------------------------------------------------------------- players ---

func _refresh_players() -> void:
	for child in _player_list.get_children():
		_player_list.remove_child(child)
		child.queue_free()
	var board := Match.scoreboard()
	_players_label.text = "RIDERS  %d / %d" % [board.size(), Match.max_players()]
	for entry in board:
		var data := entry as Dictionary
		var row := HBoxContainer.new()
		row.name = "PlayerRow"
		row.custom_minimum_size = Vector2(0, 44)
		row.add_theme_constant_override("separation", 8)

		var swatch := ColorRect.new()
		swatch.name = "Color"
		swatch.custom_minimum_size = Vector2(12, 28)
		swatch.color = Color.from_string(str(data.get("color", "#ffffff")), Color.WHITE)
		row.add_child(swatch)

		var nm := Label.new()
		nm.name = "Name"
		var suffix := ""
		if bool(data.get("is_host", false)):
			suffix += "  [HOST]"
		if bool(data.get("is_me", false)):
			suffix += "  (YOU)"
		nm.text = str(data.get("name", "RIDER")) + suffix
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.clip_text = true
		nm.add_theme_font_size_override("font_size", 15)
		row.add_child(nm)

		var is_r := bool(data.get("is_ready", false))
		var sc := Label.new()
		sc.name = "Score"
		sc.text = "READY •" if is_r else "WAITING"
		sc.add_theme_font_size_override("font_size", 13)
		sc.add_theme_color_override("font_color", COL_OK if is_r else UI.MUTED)
		row.add_child(sc)

		_player_list.add_child(row)
	if Match.players.has(Match.my_user_id) and Match.players[Match.my_user_id] is Dictionary:
		_ready_state = bool((Match.players[Match.my_user_id] as Dictionary).get("is_ready", _ready_state))
		_btn_ready.text = "READY •" if _ready_state else "NOT READY"
		_btn_ready.add_theme_color_override(
			"font_color", COL_OK if _ready_state else Color(1.0, 0.82, 0.45))
	if not Match.lobby.is_empty():
		_refresh_status(board)
	_check_auto_start()


func _check_auto_start() -> void:
	_auto_start_gen += 1
	if not _is_host() or _transitioning or _btn_start.disabled or Match.is_playing() or not Match.all_ready():
		return
	var gen := _auto_start_gen
	_schedule_auto_start(gen)


func _schedule_auto_start(gen: int) -> void:
	await get_tree().create_timer(1.0).timeout
	if not is_instance_valid(self) or not is_inside_tree() or gen != _auto_start_gen:
		return
	if _is_host() and not _transitioning and not _btn_start.disabled and not Match.is_playing() and Match.all_ready():
		_on_start()


# ---------------------------------------------------------------- settings ---

func _merged_settings() -> Dictionary:
	var out := DEFAULT_SETTINGS.duplicate(true)
	var live := Match.settings()
	for key in out.keys():
		if live.has(key):
			out[key] = live[key]
	return out


func _select_value(opt: OptionButton, values: Array, value: Variant) -> void:
	var idx := values.find(value)
	if idx < 0:
		var target := float(value)
		var best := 0
		var best_dist := INF
		for i in values.size():
			var dist := absf(float(values[i]) - target)
			if dist < best_dist:
				best_dist = dist
				best = i
		idx = best
	opt.selected = idx


func _refresh_settings() -> void:
	var s := _merged_settings()
	if _game_mode != null:
		var gm_idx := 1 if str(s.get("game_mode", "battle_royale")) == "death_race" else 0
		_game_mode.selected = gm_idx
	if _lap_target != null:
		_select_value(_lap_target, LAP_TARGETS, int(s.get("lap_target", 3)))
	_select_value(_kill_target, KILL_TARGETS, int(s["kill_target"]))
	_select_value(_max_players, MAX_PLAYERS, int(s["max_players"]))
	_select_value(_respawn, RESPAWNS, float(s["respawn_delay"]))
	_select_value(_match_seconds, MATCH_SECONDS, int(s["match_seconds"]))
	_select_value(_damage, DAMAGES, int(s["damage"]))
	_pickups.set_pressed_no_signal(bool(s["pickups"]))


func _push_settings() -> void:
	if not _is_host():
		return
	var s := _merged_settings()
	if _game_mode != null:
		s["game_mode"] = GAME_MODES[clampi(_game_mode.selected, 0, GAME_MODES.size() - 1)]
	if _lap_target != null:
		s["lap_target"] = LAP_TARGETS[clampi(_lap_target.selected, 0, LAP_TARGETS.size() - 1)]
	s["kill_target"] = KILL_TARGETS[clampi(_kill_target.selected, 0, KILL_TARGETS.size() - 1)]
	s["max_players"] = MAX_PLAYERS[clampi(_max_players.selected, 0, MAX_PLAYERS.size() - 1)]
	s["respawn_delay"] = RESPAWNS[clampi(_respawn.selected, 0, RESPAWNS.size() - 1)]
	s["match_seconds"] = MATCH_SECONDS[clampi(_match_seconds.selected, 0, MATCH_SECONDS.size() - 1)]
	s["damage"] = DAMAGES[clampi(_damage.selected, 0, DAMAGES.size() - 1)]
	s["pickups"] = bool(_pickups.button_pressed)
	await Match.set_lobby_settings(s)


# ----------------------------------------------------------------- actions ---

func _on_ready_toggled() -> void:
	Sfx.play_ui("ui_click")
	_ready_state = not _ready_state
	_btn_ready.text = "READY •" if _ready_state else "NOT READY"
	_btn_ready.add_theme_color_override(
		"font_color", COL_OK if _ready_state else Color(1.0, 0.82, 0.45))
	# Readiness is now sent to the backend so the host's authoritative roster
	# (and every guest's scoreboard) sees it, not just this local button.
	await Match.set_ready(_ready_state)


func _on_start() -> void:
	Sfx.play_ui("ui_click")
	if not _is_host():
		return
	if Match.is_playing():
		_on_match_started()
		return
	_btn_start.disabled = true
	_set_status("Starting match…", COL_INFO)
	await Match.start_match()
	if not is_inside_tree():
		return
	_btn_start.disabled = false
	if Match.is_playing():
		_on_match_started()


func _on_match_started() -> void:
	if _transitioning:
		return
	_transitioning = true
	var target_scene := SCENE_DEATH_RACE if Match.game_mode() == "death_race" else SCENE_ARENA
	get_tree().change_scene_to_file(target_scene)


func _on_leave() -> void:
	Sfx.play_ui("ui_click")
	if _transitioning:
		return
	_transitioning = true
	Lobby.leave()
	get_tree().change_scene_to_file(SCENE_MAIN)


func _on_back_requested() -> void:
	_on_leave()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			_on_leave()


func _on_left_elsewhere() -> void:
	if not _transitioning:
		_on_leave()


func _on_host_lost() -> void:
	if _transitioning or _is_host():
		return
	_transitioning = true
	_set_status("Host disconnected — leaving lobby…", COL_WARN)
	Lobby.leave()
	var w_self: WeakRef = weakref(self)
	if get_tree() != null:
		get_tree().create_timer(0.6).timeout.connect(func() -> void:
			var me := w_self.get_ref() as Node
			if me != null and is_instance_valid(me) and me.is_inside_tree():
				me.get_tree().change_scene_to_file(SCENE_MAIN))


func _on_copy() -> void:
	Sfx.play_ui("ui_click")
	var code := _code_field.text.strip_edges()
	if code == "" or not DisplayServer.has_method("clipboard_set"):
		return
	DisplayServer.clipboard_set(code)
	_set_status("Room code %s copied." % code, COL_OK)


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
	var min_t := 6.0 if short else 20.0
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
