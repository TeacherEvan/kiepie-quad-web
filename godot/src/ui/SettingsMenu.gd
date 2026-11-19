extends Control
## Settings screen (built by tools/build_menus.gd). Every control is bound live
## to the Settings autoload - changes apply immediately, no Apply/Cancel.

static var return_scene: String = ""

const SCENE_MAIN := "res://scenes/MainMenu.tscn"
const QUALITIES := ["auto", "low", "medium", "high"]
const UI := preload("res://src/ui/UiTheme.gd")
const MOBILE_INPUT := preload("res://src/ui/MobileTextInput.gd")

var _refreshing := false
var _rows: Node
var _pending_writes: Dictionary = {}     # "section.key" -> [section, key, value]
var _flush_timer: Timer = null
var _refresh_pending := false

@onready var _safe: MarginContainer = $SafeMargin


func _ready() -> void:
	add_to_group("back_handler")
	Settings.call_deferred("sync_back_handler")
	_apply_safe_area(_safe)
	get_viewport().size_changed.connect(_on_viewport_resized)
	UI.style_scroll($SafeMargin/VBox/Scroll)
	_rows = $SafeMargin/VBox/Scroll/Rows
	_connect_controls()
	Settings.changed.connect(_on_setting_changed)
	$SafeMargin/VBox/TopBar/BtnBack.pressed.connect(_on_back)
	$SafeMargin/VBox/BtnDefaults.pressed.connect(_on_defaults)
	_refresh_all()


# ------------------------------------------------------------------ helpers ---

func _c(path: String) -> Node:
	return _rows.get_node_or_null(path)


func _connect_controls() -> void:
	var quality := _c("QualityRow/Quality") as OptionButton
	if quality:
		quality.item_selected.connect(func(i):
			if _refreshing:
				return
			Settings.apply_quality(QUALITIES[i])
		)

	_bind_slider("ResolutionScaleRow/ResolutionScale", "ResolutionScaleRow/ResolutionScaleValue", "video", "resolution_scale", "%.2f")
	_bind_slider("ParticlesRow/Particles", "ParticlesRow/ParticlesValue", "video", "particles", "%.2f")
	_bind_slider("FovRow/Fov", "FovRow/FovValue", "video", "fov", "%.0f°")
	_bind_check("ShadowsRow/Shadows", "video", "shadows")
	_bind_check("GlowRow/Glow", "video", "glow")
	_bind_check("FullscreenRow/Fullscreen", "video", "fullscreen")
	_bind_check("ShowFpsRow/ShowFps", "video", "show_fps")

	_bind_slider("MasterRow/Master", "MasterRow/MasterValue", "audio", "master", "%.0f%%")
	_bind_slider("SfxRow/Sfx", "SfxRow/SfxValue", "audio", "sfx", "%.0f%%")
	_bind_slider("EngineRow/Engine", "EngineRow/EngineValue", "audio", "engine", "%.0f%%")
	_bind_slider("UiRow/Ui", "UiRow/UiValue", "audio", "ui", "%.0f%%")
	_bind_check("MutedRow/Muted", "audio", "muted")

	_bind_slider("SteerSensitivityRow/SteerSensitivity", "SteerSensitivityRow/SteerSensitivityValue", "controls", "steer_sensitivity", "%.2f")
	_bind_slider("DodgeSizeRow/DodgeSize", "DodgeSizeRow/DodgeSizeValue", "controls", "dodge_size", "%.2f")
	_bind_check("TouchForceRow/TouchForce", "controls", "touch_force")

	_bind_line("DisplayNameRow/DisplayName", "gameplay", "display_name")
	var display_name := _c("DisplayNameRow/DisplayName") as LineEdit
	if display_name != null:
		MOBILE_INPUT.attach(display_name, {
			"title": "DISPLAY NAME",
			"placeholder": "RIDER",
			"submit_label": "DONE",
			"enter_key_hint": "done",
			"uppercase": false,
			"commit_on_close": true,
			"max_length": 16,
		})
	var color := _c("ColorRow/Color") as ColorPickerButton
	if color:
		color.color_changed.connect(func(c):
			if _refreshing:
				return
			_queue_write("gameplay", "color", "#" + c.to_html(false))
		)
	_bind_slider("ScreenShakeRow/ScreenShake", "ScreenShakeRow/ScreenShakeValue", "gameplay", "screen_shake", "%.2f")
	_bind_check("ReducedMotionRow/ReducedMotion", "gameplay", "reduced_motion")


func _on_viewport_resized() -> void:
	_apply_safe_area(_safe)


func _exit_tree() -> void:
	var vp := get_viewport()
	if vp != null and vp.size_changed.is_connected(_on_viewport_resized):
		vp.size_changed.disconnect(_on_viewport_resized)
	if Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.disconnect(_on_setting_changed)
	_flush_writes()


func _queue_write(section: String, key: String, value: Variant) -> void:
	## Coalesce a burst of slider/color ticks into one ConfigFile write.
	_pending_writes["%s.%s" % [section, key]] = [section, key, value]
	if _flush_timer == null:
		_flush_timer = Timer.new()
		_flush_timer.one_shot = true
		_flush_timer.wait_time = 0.35
		_flush_timer.timeout.connect(_flush_writes)
		add_child(_flush_timer)
	_flush_timer.start()


func _flush_writes() -> void:
	if _pending_writes.is_empty():
		return
	var pending := _pending_writes
	_pending_writes = {}
	for entry in pending.values():
		Settings.set_value(entry[0], entry[1], entry[2])


func _bind_slider(path: String, value_path: String, section: String, key: String, fmt: String) -> void:
	var slider := _c(path) as HSlider
	if slider == null:
		return
	slider.value_changed.connect(func(v):
		if _refreshing:
			return
		_queue_write(section, key, v)
		var lbl := _c(value_path) as Label
		if lbl:
			lbl.text = fmt % (v * 100.0 if fmt == "%.0f%%" else v)
	)


func _bind_check(path: String, section: String, key: String) -> void:
	var cb := _c(path) as CheckBox
	if cb == null:
		return
	cb.toggled.connect(func(v):
		if _refreshing:
			return
		Settings.set_value(section, key, v)
	)


func _bind_line(path: String, section: String, key: String) -> void:
	var le := _c(path) as LineEdit
	if le == null:
		return
	le.text_submitted.connect(func(t):
		if _refreshing:
			return
		Settings.set_value(section, key, t)
	)
	le.focus_exited.connect(func():
		if _refreshing:
			return
		Settings.set_value(section, key, le.text)
	)


# ----------------------------------------------------------------- refresh ---

func _set_slider(path: String, value_path: String, section: String, key: String, fmt: String) -> void:
	var slider := _c(path) as HSlider
	if slider == null:
		return
	slider.value = float(Settings.get_value(section, key, slider.value))
	var lbl := _c(value_path) as Label
	if lbl:
		var v := slider.value
		lbl.text = fmt % (v * 100.0 if fmt == "%.0f%%" else v)


func _set_check(path: String, section: String, key: String) -> void:
	var cb := _c(path) as CheckBox
	if cb:
		cb.set_pressed_no_signal(bool(Settings.get_value(section, key, false)))


func _set_line(path: String, section: String, key: String, fallback: String) -> void:
	var le := _c(path) as LineEdit
	if le:
		le.text = str(Settings.get_value(section, key, fallback))


func _refresh_all() -> void:
	_refreshing = true

	var quality := _c("QualityRow/Quality") as OptionButton
	if quality:
		var idx := QUALITIES.find(str(Settings.get_value("video", "quality", "auto")))
		quality.selected = idx if idx >= 0 else 0

	_set_slider("ResolutionScaleRow/ResolutionScale", "ResolutionScaleRow/ResolutionScaleValue", "video", "resolution_scale", "%.2f")
	_set_slider("ParticlesRow/Particles", "ParticlesRow/ParticlesValue", "video", "particles", "%.2f")
	_set_slider("FovRow/Fov", "FovRow/FovValue", "video", "fov", "%.0f°")
	_set_check("ShadowsRow/Shadows", "video", "shadows")
	_set_check("GlowRow/Glow", "video", "glow")
	_set_check("FullscreenRow/Fullscreen", "video", "fullscreen")
	_set_check("ShowFpsRow/ShowFps", "video", "show_fps")

	_set_slider("MasterRow/Master", "MasterRow/MasterValue", "audio", "master", "%.0f%%")
	_set_slider("SfxRow/Sfx", "SfxRow/SfxValue", "audio", "sfx", "%.0f%%")
	_set_slider("EngineRow/Engine", "EngineRow/EngineValue", "audio", "engine", "%.0f%%")
	_set_slider("UiRow/Ui", "UiRow/UiValue", "audio", "ui", "%.0f%%")
	_set_check("MutedRow/Muted", "audio", "muted")

	_set_slider("SteerSensitivityRow/SteerSensitivity", "SteerSensitivityRow/SteerSensitivityValue", "controls", "steer_sensitivity", "%.2f")
	_set_slider("DodgeSizeRow/DodgeSize", "DodgeSizeRow/DodgeSizeValue", "controls", "dodge_size", "%.2f")
	_set_check("TouchForceRow/TouchForce", "controls", "touch_force")

	_set_line("DisplayNameRow/DisplayName", "gameplay", "display_name", "RIDER")
	var color := _c("ColorRow/Color") as ColorPickerButton
	if color:
		color.color = Color.from_string(Settings.player_color(), Color(1.0, 0.48, 0.10))
	_set_slider("ScreenShakeRow/ScreenShake", "ScreenShakeRow/ScreenShakeValue", "gameplay", "screen_shake", "%.2f")
	_set_check("ReducedMotionRow/ReducedMotion", "gameplay", "reduced_motion")

	_refreshing = false


func _on_setting_changed(_section: String, _key: String, _value: Variant) -> void:
	## A slider burst emits one signal per tick; repaint all widgets once, at the end.
	if not is_inside_tree() or get_tree() == null:
		return
	if _refreshing or _refresh_pending:
		return
	_refresh_pending = true
	var timer := get_tree().create_timer(0.15)
	timer.timeout.connect(func() -> void:
		_refresh_pending = false
		if is_instance_valid(self) and is_inside_tree():
			_refresh_all())


# ----------------------------------------------------------------- actions ---

func _on_defaults() -> void:
	Settings.reset_defaults()
	_refresh_all()


func _on_back() -> void:
	var target := return_scene
	return_scene = ""
	if target == "" or not ResourceLoader.exists(target):
		target = SCENE_MAIN
	get_tree().change_scene_to_file(target)


func _on_back_requested() -> void:
	_on_back()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			_on_back()


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
