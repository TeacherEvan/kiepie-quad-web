extends SceneTree
# Builds the three front-end scenes (MainMenu / LobbyMenu / SettingsMenu).
# Scenes are generated, never hand-edited:
#   godot-4.3 --headless --path godot -s tools/build_menus.gd

const OUT_MAIN := "res://scenes/MainMenu.tscn"
const OUT_LOBBY := "res://scenes/LobbyMenu.tscn"
const OUT_SETTINGS := "res://scenes/SettingsMenu.tscn"

const ACCENT := Color(1.0, 0.55, 0.16)
const TEXT := Color(0.91, 0.93, 0.97)
const MUTED := Color(0.62, 0.68, 0.78)
const GOLD := Color(1.0, 0.82, 0.42)
const INFO := Color(0.72, 0.82, 0.96)
const UI := preload("res://src/ui/UiTheme.gd")

var _failed := false


# --------------------------------------------------------- style helpers ---
# Delegated to UiTheme so menus and arena share one token system.

func _chip(bg := Color(0.075, 0.085, 0.105, 0.80),
		border := Color(1.0, 1.0, 1.0, 0.08)) -> StyleBoxFlat:
	return UI.chip(bg, border, 12)


func _button_style(bg: Color, border: Color, corner := 13) -> StyleBoxFlat:
	return UI.button_style(bg, border, corner)


func _style_button(btn: Button, accent: Color) -> void:
	# Landscape phone friendly: every touch target stays at least 52 px tall.
	UI.style_button(btn, accent, 16, 52.0)


# ------------------------------------------------------------ node helpers ---

func _full(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0


func _bg(color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.name = "Background"
	r.color = color
	_full(r)
	return r


func _margin() -> MarginContainer:
	var m := MarginContainer.new()
	m.name = "SafeMargin"
	_full(m)
	m.set("theme_override_constants/margin_left", 40)
	m.set("theme_override_constants/margin_top", 28)
	m.set("theme_override_constants/margin_right", 40)
	m.set("theme_override_constants/margin_bottom", 28)
	return m


func _vbox(name: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.name = name
	v.add_theme_constant_override("separation", 12)
	return v


func _hbox(name: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.name = name
	h.add_theme_constant_override("separation", 10)
	return h


func _label(name: String, text: String, size := 16, color := TEXT) -> Label:
	var l := Label.new()
	l.name = name
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(name: String, text: String, accent := ACCENT) -> Button:
	var b := Button.new()
	b.name = name
	b.text = text
	# Hybrid target: navigation buttons must be keyboard-reachable. Touch-only
	# gameplay buttons keep FOCUS_NONE (see verify_touch.gd).
	b.focus_mode = Control.FOCUS_ALL
	_style_button(b, accent)
	return b


func _option(name: String, labels: Array) -> OptionButton:
	var o := OptionButton.new()
	o.name = name
	for label in labels:
		o.add_item(str(label))
	UI.style_button(o, UI.INFO, 15, 48.0)
	o.custom_minimum_size = Vector2(0.0, 48.0)
	return o


func _slider(name: String, min_v: float, max_v: float, step: float, value: float) -> HSlider:
	var s := HSlider.new()
	s.name = name
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	UI.style_slider(s, 48.0)
	s.custom_minimum_size = Vector2(140.0, 48.0)
	return s


func _check(name: String, text: String, pressed: bool) -> CheckBox:
	var c := CheckBox.new()
	c.name = name
	c.text = text
	c.set_pressed_no_signal(pressed)
	UI.style_button(c, UI.OK, 15, 48.0)
	c.custom_minimum_size = Vector2(0.0, 48.0)
	return c


func _line(name: String, text: String, placeholder: String) -> LineEdit:
	var le := LineEdit.new()
	le.name = name
	le.text = text
	le.placeholder_text = placeholder
	UI.style_line(le, 48.0)
	le.custom_minimum_size = Vector2(0.0, 48.0)
	return le


func _value_label(name: String, text: String) -> Label:
	var l := _label(name, text, 15, GOLD)
	l.custom_minimum_size = Vector2(58.0, 32.0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


func _color_picker(name: String, hex: String) -> ColorPickerButton:
	var cp := ColorPickerButton.new()
	cp.name = name
	cp.color = Color.from_string(hex, Color(1.0, 0.48, 0.10))
	UI.style_button(cp, UI.GOLD, 15, 48.0)
	cp.custom_minimum_size = Vector2(0.0, 48.0)
	return cp


func _setting_row(name: String, label_text: String, control: Control) -> HBoxContainer:
	var row := _hbox(name)
	var lbl := _label("RowLabel", label_text, 14, TEXT)
	lbl.custom_minimum_size = Vector2(132.0, 32.0)
	row.add_child(lbl)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _slider_row(name: String, label_text: String, slider: HSlider, value_label: Label) -> HBoxContainer:
	var row := _hbox(name)
	var lbl := _label("RowLabel", label_text, 14, TEXT)
	lbl.custom_minimum_size = Vector2(132.0, 32.0)
	row.add_child(lbl)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	row.add_child(value_label)
	return row


func _section_header(name: String, text: String) -> Label:
	var l := _label(name, text, 15, GOLD)
	l.custom_minimum_size = Vector2(0.0, 34.0)
	return l


# ----------------------------------------------------------------- saving ---

func _own_all(node: Node, owner: Node) -> void:
	for c in node.get_children():
		c.owner = owner
		_own_all(c, owner)


func _save(root: Node, out: String) -> void:
	_own_all(root, root)
	var scene := PackedScene.new()
	var ok := scene.pack(root) == OK
	if not ok:
		printerr("pack failed: ", out)
	_failed = _failed or not ok
	if ok:
		ok = ResourceSaver.save(scene, out) == OK
		if not ok:
			printerr("save failed: ", out)
		_failed = _failed or not ok
	if ok:
		print("saved ", out)
	# Temporary build nodes are not part of the running tree - release their
	# rendering resources before exiting the headless process.
	root.free()


# ------------------------------------------------------------------- build ---

func _initialize() -> void:
	_build_main()
	_build_lobby()
	_build_settings()
	_verify()
	quit(1 if _failed else 0)


func _build_main() -> void:
	var root := Control.new()
	root.name = "MainMenu"
	root.set_script(load("res://src/ui/MainMenu.gd"))
	_full(root)
	root.add_child(_bg(Color(0.035, 0.045, 0.065, 1.0)))

	var margin := _margin()
	root.add_child(margin)

	var card := PanelContainer.new()
	card.name = "Card"
	var card_style := _chip(Color(0.06, 0.075, 0.10, 0.94), Color(1.0, 0.78, 0.30, 0.28))
	card_style.border_width_top = 2
	card_style.corner_radius_top_left = 18
	card_style.corner_radius_top_right = 18
	card_style.corner_radius_bottom_left = 18
	card_style.corner_radius_bottom_right = 18
	card_style.content_margin_left = 28.0
	card_style.content_margin_right = 28.0
	card_style.content_margin_top = 22.0
	card_style.content_margin_bottom = 22.0
	card.add_theme_stylebox_override("panel", card_style)
	card.custom_minimum_size = Vector2(360.0, 0.0)
	margin.add_child(card)

	var vbox := _vbox("VBox")
	card.add_child(vbox)

	var title := _label("Title", "KIEPIE QUAD", 38, GOLD)
	title.label_settings = UI.title_settings(38, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var subtitle := _label("Subtitle", "ARENA  ·  ONLINE MULTIPLAYER", 14, MUTED)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	var status := _label("Status", "Connecting…", 15, INFO)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(0.0, 44.0)
	vbox.add_child(status)

	var sep := HSeparator.new()
	sep.name = "Sep"
	vbox.add_child(sep)

	vbox.add_child(_button("BtnPractice", "PRACTICE (FREE RIDE)"))
	vbox.add_child(_button("BtnCreate", "CREATE LOBBY"))
	vbox.add_child(_button("BtnJoinAuto", "JOIN AUTO"))

	var join_row := _hbox("JoinRow")
	var code := _line("CodeField", "", "ROOM CODE")
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(code)
	var join_btn := _button("BtnJoinCode", "JOIN", Color(0.42, 0.62, 1.0))
	join_btn.custom_minimum_size = Vector2(120.0, 52.0)
	join_row.add_child(join_btn)
	vbox.add_child(join_row)

	vbox.add_child(_button("BtnSettings", "SETTINGS", Color(0.55, 0.60, 0.70)))

	var footer := _label("Footer", "W/A/S/D drive  ·  Q/E dodge  ·  SPACE handbrake  ·  F fire", 12, MUTED)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(footer)

	_save(root, OUT_MAIN)


func _build_lobby() -> void:
	var root := Control.new()
	root.name = "LobbyMenu"
	root.set_script(load("res://src/ui/LobbyMenu.gd"))
	_full(root)
	root.add_child(_bg(Color(0.035, 0.045, 0.065, 1.0)))

	var margin := _margin()
	root.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	var vbox := _vbox("VBox")
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var top := _hbox("TopBar")
	var title := _label("Title", "LOBBY", 28, GOLD)
	title.label_settings = UI.title_settings(28, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var leave := _button("BtnLeave", "LEAVE", Color(1.0, 0.42, 0.32))
	leave.custom_minimum_size = Vector2(120.0, 52.0)
	top.add_child(leave)
	vbox.add_child(top)

	var code_row := _hbox("CodeRow")
	code_row.add_child(_label("CodeLabel", "ROOM CODE", 15, MUTED))
	var code := _line("CodeField", "", "—")
	code.editable = false
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_row.add_child(code)
	var copy := _button("BtnCopy", "COPY", Color(0.55, 0.60, 0.70))
	copy.custom_minimum_size = Vector2(100.0, 52.0)
	code_row.add_child(copy)
	vbox.add_child(code_row)

	var status := _label("Status", "Connecting…", 15, INFO)
	status.custom_minimum_size = Vector2(0.0, 30.0)
	vbox.add_child(status)

	var players_label := _label("PlayersLabel", "RIDERS  0 / 8", 16, GOLD)
	vbox.add_child(players_label)
	vbox.add_child(_vbox("PlayerList"))

	var host_panel := _vbox("HostPanel")
	host_panel.add_child(_section_header("HostTitle", "HOST SETTINGS"))
	host_panel.add_child(_setting_row("KillTargetRow", "Eliminations", _option("KillTarget", ["3", "5", "10", "15", "20"])))
	host_panel.add_child(_setting_row("MaxPlayersRow", "Max riders", _option("MaxPlayers", ["2", "3", "4", "5", "6", "7", "8"])))
	host_panel.add_child(_setting_row("RespawnRow", "Respawn", _option("RespawnDelay", ["1s", "2s", "2.5s", "3s", "4s", "5s"])))
	host_panel.add_child(_setting_row("MatchSecondsRow", "Time limit", _option("MatchSeconds", ["Unlimited", "3 min", "5 min", "10 min"])))
	host_panel.add_child(_setting_row("DamageRow", "Damage", _option("Damage", ["20", "30", "40", "50"])))
	host_panel.add_child(_setting_row("PickupsRow", "Pickups", _check("Pickups", "", true)))
	host_panel.add_child(_button("BtnStart", "START MATCH", Color(0.35, 0.90, 0.55)))
	vbox.add_child(host_panel)

	vbox.add_child(_button("BtnReady", "NOT READY", Color(0.42, 0.62, 1.0)))
	# Web shell paints a fixed hint strip along the bottom; keep buttons clear of it.
	var lobby_pad := Control.new()
	lobby_pad.name = "BottomPad"
	lobby_pad.custom_minimum_size = Vector2(0.0, 60.0)
	vbox.add_child(lobby_pad)

	_save(root, OUT_LOBBY)


func _build_settings() -> void:
	var root := Control.new()
	root.name = "SettingsMenu"
	root.set_script(load("res://src/ui/SettingsMenu.gd"))
	_full(root)
	root.add_child(_bg(Color(0.035, 0.045, 0.065, 1.0)))

	var margin := _margin()
	root.add_child(margin)
	var vbox := _vbox("VBox")
	margin.add_child(vbox)

	var top := _hbox("TopBar")
	var title := _label("Title", "SETTINGS", 28, GOLD)
	title.label_settings = UI.title_settings(28, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var back := _button("BtnBack", "BACK", Color(0.55, 0.60, 0.70))
	back.custom_minimum_size = Vector2(110.0, 52.0)
	top.add_child(back)
	vbox.add_child(top)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var rows := _vbox("Rows")
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 8)
	scroll.add_child(rows)

	# ----- video
	rows.add_child(_section_header("VideoHeader", "VIDEO"))
	rows.add_child(_setting_row("QualityRow", "Quality", _option("Quality", ["Auto", "Low", "Medium", "High"])))
	rows.add_child(_slider_row("ResolutionScaleRow", "Resolution", _slider("ResolutionScale", 0.5, 1.0, 0.05, 1.0), _value_label("ResolutionScaleValue", "1.00")))
	rows.add_child(_setting_row("ShadowsRow", "Shadows", _check("Shadows", "", true)))
	rows.add_child(_slider_row("ParticlesRow", "Particles", _slider("Particles", 0.0, 1.0, 0.05, 1.0), _value_label("ParticlesValue", "1.00")))
	rows.add_child(_setting_row("GlowRow", "Glow", _check("Glow", "", true)))
	rows.add_child(_setting_row("FullscreenRow", "Fullscreen", _check("Fullscreen", "", false)))
	rows.add_child(_slider_row("FovRow", "Field of view", _slider("Fov", 50.0, 100.0, 1.0, 62.0), _value_label("FovValue", "62°")))
	rows.add_child(_setting_row("ShowFpsRow", "Show FPS", _check("ShowFps", "", false)))

	# ----- audio
	rows.add_child(_section_header("AudioHeader", "AUDIO"))
	rows.add_child(_slider_row("MasterRow", "Master", _slider("Master", 0.0, 1.0, 0.05, 0.9), _value_label("MasterValue", "90%")))
	rows.add_child(_slider_row("SfxRow", "Effects", _slider("Sfx", 0.0, 1.0, 0.05, 0.9), _value_label("SfxValue", "90%")))
	rows.add_child(_slider_row("EngineRow", "Engine", _slider("Engine", 0.0, 1.0, 0.05, 0.7), _value_label("EngineValue", "70%")))
	rows.add_child(_slider_row("UiRow", "UI", _slider("Ui", 0.0, 1.0, 0.05, 0.6), _value_label("UiValue", "60%")))
	rows.add_child(_setting_row("MutedRow", "Mute all", _check("Muted", "", false)))

	# ----- controls
	rows.add_child(_section_header("ControlsHeader", "CONTROLS"))
	rows.add_child(_slider_row("FireSizeRow", "Fire button", _slider("FireSize", 0.5, 2.0, 0.05, 1.0), _value_label("FireSizeValue", "1.00")))
	rows.add_child(_slider_row("SteerSensitivityRow", "Steering", _slider("SteerSensitivity", 0.3, 2.0, 0.05, 1.0), _value_label("SteerSensitivityValue", "1.00")))
	rows.add_child(_slider_row("DodgeSizeRow", "Dodge buttons", _slider("DodgeSize", 0.7, 1.6, 0.05, 1.0), _value_label("DodgeSizeValue", "1.00")))
	rows.add_child(_setting_row("TouchForceRow", "Always show touch pad", _check("TouchForce", "", false)))

	# ----- gameplay
	rows.add_child(_section_header("GameplayHeader", "GAMEPLAY"))
	rows.add_child(_setting_row("DisplayNameRow", "Display name", _line("DisplayName", "RIDER", "RIDER")))
	rows.add_child(_setting_row("ColorRow", "Rider colour", _color_picker("Color", "#ff7a1a")))
	rows.add_child(_slider_row("ScreenShakeRow", "Screen shake", _slider("ScreenShake", 0.0, 2.0, 0.05, 1.0), _value_label("ScreenShakeValue", "1.00")))
	rows.add_child(_setting_row("ReducedMotionRow", "Reduced motion", _check("ReducedMotion", "", false)))

	vbox.add_child(_button("BtnDefaults", "RESTORE DEFAULTS", Color(1.0, 0.42, 0.32)))
	# Web shell paints a fixed hint strip along the bottom; keep buttons clear of it.
	var settings_pad := Control.new()
	settings_pad.name = "BottomPad"
	settings_pad.custom_minimum_size = Vector2(0.0, 60.0)
	vbox.add_child(settings_pad)

	_save(root, OUT_SETTINGS)


# ----------------------------------------------------------------- verify ---

func _verify() -> void:
	# MainMenu passes the lobby entry mode through a static var on this script.
	var lobby_script = load("res://src/ui/LobbyMenu.gd")
	lobby_script.pending_mode = "__probe__"
	if lobby_script.pending_mode != "__probe__":
		printerr("static lobby-mode channel probe FAILED")
		_failed = true
	lobby_script.pending_mode = ""

	var checks := [
		{
			"path": OUT_MAIN,
			"script": "res://src/ui/MainMenu.gd",
			"nodes": ["SafeMargin", "SafeMargin/Card/VBox/Status", "SafeMargin/Card/VBox/JoinRow/CodeField",
					"SafeMargin/Card/VBox/BtnPractice", "SafeMargin/Card/VBox/BtnCreate",
					"SafeMargin/Card/VBox/BtnJoinAuto", "SafeMargin/Card/VBox/JoinRow/BtnJoinCode",
					"SafeMargin/Card/VBox/BtnSettings"],
		},
		{
			"path": OUT_LOBBY,
			"script": "res://src/ui/LobbyMenu.gd",
			"nodes": ["SafeMargin", "SafeMargin/Scroll/VBox/Status", "SafeMargin/Scroll/VBox/CodeRow/CodeField",
					"SafeMargin/Scroll/VBox/CodeRow/BtnCopy", "SafeMargin/Scroll/VBox/PlayersLabel", "SafeMargin/Scroll/VBox/PlayerList",
					"SafeMargin/Scroll/VBox/HostPanel", "SafeMargin/Scroll/VBox/HostPanel/BtnStart",
					"SafeMargin/Scroll/VBox/BtnReady", "SafeMargin/Scroll/VBox/TopBar/BtnLeave",
					"SafeMargin/Scroll/VBox/HostPanel/KillTargetRow/KillTarget",
					"SafeMargin/Scroll/VBox/HostPanel/MaxPlayersRow/MaxPlayers",
					"SafeMargin/Scroll/VBox/HostPanel/RespawnRow/RespawnDelay",
					"SafeMargin/Scroll/VBox/HostPanel/MatchSecondsRow/MatchSeconds",
					"SafeMargin/Scroll/VBox/HostPanel/DamageRow/Damage",
					"SafeMargin/Scroll/VBox/HostPanel/PickupsRow/Pickups"],
		},
		{
			"path": OUT_SETTINGS,
			"script": "res://src/ui/SettingsMenu.gd",
			"nodes": ["SafeMargin", "SafeMargin/VBox/Scroll/Rows", "SafeMargin/VBox/TopBar/BtnBack",
					"SafeMargin/VBox/BtnDefaults",
					"SafeMargin/VBox/Scroll/Rows/QualityRow/Quality",
					"SafeMargin/VBox/Scroll/Rows/ResolutionScaleRow/ResolutionScale",
					"SafeMargin/VBox/Scroll/Rows/ResolutionScaleRow/ResolutionScaleValue",
					"SafeMargin/VBox/Scroll/Rows/ShadowsRow/Shadows",
					"SafeMargin/VBox/Scroll/Rows/ParticlesRow/Particles",
					"SafeMargin/VBox/Scroll/Rows/ParticlesRow/ParticlesValue",
					"SafeMargin/VBox/Scroll/Rows/GlowRow/Glow",
					"SafeMargin/VBox/Scroll/Rows/FullscreenRow/Fullscreen",
					"SafeMargin/VBox/Scroll/Rows/FovRow/Fov",
					"SafeMargin/VBox/Scroll/Rows/FovRow/FovValue",
					"SafeMargin/VBox/Scroll/Rows/ShowFpsRow/ShowFps",
					"SafeMargin/VBox/Scroll/Rows/MasterRow/Master",
					"SafeMargin/VBox/Scroll/Rows/MasterRow/MasterValue",
					"SafeMargin/VBox/Scroll/Rows/SfxRow/Sfx",
					"SafeMargin/VBox/Scroll/Rows/SfxRow/SfxValue",
					"SafeMargin/VBox/Scroll/Rows/EngineRow/Engine",
					"SafeMargin/VBox/Scroll/Rows/EngineRow/EngineValue",
					"SafeMargin/VBox/Scroll/Rows/UiRow/Ui",
					"SafeMargin/VBox/Scroll/Rows/UiRow/UiValue",
					"SafeMargin/VBox/Scroll/Rows/MutedRow/Muted",
					"SafeMargin/VBox/Scroll/Rows/FireSizeRow/FireSize",
					"SafeMargin/VBox/Scroll/Rows/FireSizeRow/FireSizeValue",
					"SafeMargin/VBox/Scroll/Rows/SteerSensitivityRow/SteerSensitivity",
					"SafeMargin/VBox/Scroll/Rows/SteerSensitivityRow/SteerSensitivityValue",
					"SafeMargin/VBox/Scroll/Rows/DodgeSizeRow/DodgeSize",
					"SafeMargin/VBox/Scroll/Rows/DodgeSizeRow/DodgeSizeValue",
					"SafeMargin/VBox/Scroll/Rows/TouchForceRow/TouchForce",
					"SafeMargin/VBox/Scroll/Rows/DisplayNameRow/DisplayName",
					"SafeMargin/VBox/Scroll/Rows/ColorRow/Color",
					"SafeMargin/VBox/Scroll/Rows/ScreenShakeRow/ScreenShake",
					"SafeMargin/VBox/Scroll/Rows/ScreenShakeRow/ScreenShakeValue",
					"SafeMargin/VBox/Scroll/Rows/ReducedMotionRow/ReducedMotion"],
		},
	]

	for check in checks:
		var path := str(check["path"])
		var script_path := str(check["script"])
		if load(script_path) == null:
			printerr("SCRIPT LOAD FAIL ", script_path)
			_failed = true
		var packed := load(path) as PackedScene
		if packed == null:
			printerr("SCENE LOAD FAIL ", path)
			_failed = true
			continue
		# Inspect the packed state instead of instantiating: keeps headless runs
		# free of dummy-renderer RID leaks while still proving every named node
		# was actually saved into the .tscn.
		var state := packed.get_state()
		var saved_names := {}
		for i in range(state.get_node_count()):
			saved_names[str(state.get_node_name(i))] = true
		for node_path in check["nodes"]:
			var leaf := str(node_path).get_file()
			if not saved_names.has(leaf):
				printerr("MISSING NODE ", path, " :: ", node_path)
				_failed = true

	print("menu verify: ", "FAIL" if _failed else "OK")
